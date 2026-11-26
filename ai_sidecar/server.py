"""
Local HTTP sidecar: Godot <-> Cursor SDK for hybrid chess AI.

Auth: CURSOR_API_KEY env var or ai_sidecar/.env (never commit keys).
Mock: AI_SIDECAR_MOCK=1 skips Cursor and picks a skill-weighted candidate.
Gate demo: AI_SIDECAR_INJECT_UCI=e1e8 replaces the LLM's answer with that UCI
(test-only injection) so the candidate gate can be seen without an API key.
Every /move decision prints a "[GATE]" line to stdout (sidecar.log).

Run:
  copy .env.example .env   # then edit CURSOR_API_KEY
  uvicorn server:app --host 127.0.0.1 --port 8765
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import traceback
import uuid
from pathlib import Path
from typing import Any, Optional

# cursor_sdk on Windows calls os.get_blocking (Unix-only). Patch before SDK import.
from win_os_patch import patch_cursor_sdk_bridge, patch_os_blocking

patch_os_blocking()

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from openings import (
    book_next_moves,
    looks_like_opening_request,
    looks_like_recommend_request,
    looks_like_setup_request,
    parse_history,
    normalize_book_lines,
    pick_by_skill,
    resolve_book_move,
)

import practice

# Load ai_sidecar/.env if present (does not override already-set process env).
load_dotenv(Path(__file__).resolve().parent / ".env")

app = FastAPI(title="Chess Cursor AI Sidecar", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

MOCK = os.environ.get("AI_SIDECAR_MOCK", "").strip() in ("1", "true", "TRUE", "yes")
MODEL = os.environ.get("CURSOR_AI_MODEL", "composer-2.5").strip() or "composer-2.5"
# Bump when move/opening logic changes so Godot can restart stale servers.
CODE_REV = 13
WORKDIR = os.environ.get(
    "AI_SIDECAR_WORKDIR",
    os.path.join(tempfile.gettempdir(), "chess_cursor_ai_sidecar"),
)

# Shared coach wording: searchable names beat casual Korean transliteration.
COACH_ROLE = """
역할: 당신은 전 국면 체스 코치이자 대국 상대입니다.
오프닝뿐 아니라 middlegame, tactics, positional play, endgame, 시간 압박·실전 판단까지
질문·지시에 맞게 다룹니다. 오프닝만 전문인 봇이 아닙니다.
"""

TERMINOLOGY_RULES = """
용어/표기 규칙 (검색·학습용 — 반드시 준수):
- 오프닝·배리에이션 이름: 항상 표준 영어만.
  예: "Sicilian Defense, Najdorf Variation", "Queen's Gambit Accepted",
  "Nimzo-Indian Defense", "Ruy Lopez, Berlin Defense".
  한글 음차 금지 (시실리안/시칠리안/나이도프/나이도르츠/퀸즈갬빗 등 쓰지 말 것).
  opening_name 필드와 reply 안의 오프닝 이름 모두 영어.
- 체스 용어: 한국 플레이어가 실제로 검색·쓰는 말이 있으면 그 한글
  (캐슬링, 앙파상, 포크, 핀, 스큐어, 디스커버드 어택, 체크, 체크메이트, 기권 등).
  확신이 없거나 검색용 고유명(오프닝/ECO/이론명)이면 영어.
- 수 표기: SAN 또는 UCI 영문 (Nf3, O-O, e2e4). 기물을 이상한 한글로 음차하지 말 것.
"""

# agent_id -> { agent, style_notes, opening_name, book_lines, last_move }
_sessions: dict[str, dict[str, Any]] = {}


class SessionRequest(BaseModel):
    style_notes: str = ""


class SessionResponse(BaseModel):
    agent_id: str
    mock: bool = False


class Candidate(BaseModel):
    rank: int = 1
    uci: str
    score_cp: int = 0
    mate: int = 0
    depth: int = 0


class MoveRequest(BaseModel):
    fen: str
    side: str = Field(description="white or black — side to move / AI side")
    candidates: list[Candidate]
    style_notes: str = ""
    last_human_uci: str = ""
    history_uci: str = ""  # space-separated UCI from start
    skill_level: int = 10  # 0..20 — affects non-book candidate weighting
    book_lines: list[list[str]] = Field(default_factory=list)
    opening_name: str = ""
    agent_id: str = ""


class MoveResponse(BaseModel):
    uci: str
    reason: str
    reply: str
    fallback: bool = False
    agent_id: str = ""
    # What the model (or test injection) proposed, before the candidate gate.
    llm_uci: str = ""
    # pass | replaced | book | mock | error
    gate: str = ""


class ChatRequest(BaseModel):
    fen: str = ""
    history_summary: str = ""
    message: str
    agent_id: str = ""
    style_notes: str = ""
    last_ai_uci: str = ""
    last_reason: str = ""
    # Stockfish MultiPV for the current position (side to move = the user).
    # When present, any move the agent recommends must be one of these.
    candidates: list[Candidate] = Field(default_factory=list)
    side: str = ""  # side to move: white | black


class SetupInfo(BaseModel):
    """What the agent claims about a position it set up (Godot verifies it)."""

    name: str = ""
    goal: str = "practice"  # mate | endgame | practice
    mate_in: int = 0
    material: str = ""  # e.g. "KBN v K" (white v black)
    source: str = "agent"  # agent (LLM-made FEN) | catalog (practice_positions.json)
    catalog_id: str = ""


class ChatResponse(BaseModel):
    reply: str
    style_update: Optional[str] = None
    opening_name: Optional[str] = None
    book_lines: list[list[str]] = Field(default_factory=list)
    # Optional FEN to load onto the Godot board (paste/practice).
    board_fen: Optional[str] = None
    agent_id: str = ""
    # Gated move recommendation for the user (UCI) and how the gate treated it.
    recommend_uci: Optional[str] = None
    recommend_llm_uci: str = ""
    recommend_gate: str = ""  # pass | replaced | filled | book
    setup: Optional[SetupInfo] = None


class ExplainRequest(BaseModel):
    fen: str = ""
    last_ai_uci: str = ""
    last_reason: str = ""
    message: str = "지금 둔 수는 어떤 관점에서 둔 거야?"
    agent_id: str = ""
    candidates: list[Candidate] = Field(default_factory=list)


def _ensure_workdir() -> str:
    os.makedirs(WORKDIR, exist_ok=True)
    return WORKDIR


def _api_key() -> str:
    key = os.environ.get("CURSOR_API_KEY", "").strip().strip('"').strip("'")
    if not key:
        return ""
    # Reject unedited / mangled placeholders from .env.example
    lowered = key.lower()
    if (
        "your_api_key" in lowered
        or "api_key_here" in lowered
        or key.endswith("_here")
        or key == "cursor_..."
    ):
        return ""
    return key


def _use_mock() -> bool:
    return MOCK or not bool(_api_key())


def _extract_json_object(text: str) -> dict[str, Any]:
    text = (text or "").strip()
    if not text:
        return {}
    # Fenced block
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL | re.IGNORECASE)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    # First {...}
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        try:
            return json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            pass
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {}


_FEN_RE = re.compile(
    r"\b([rnbqkpRNBQKP1-8]+(?:/[rnbqkpRNBQKP1-8]+){7})"
    r"(?:\s+([wb]))"
    r"(?:\s+([KQkq-]{1,4}))"
    r"(?:\s+([a-h][36]|-))"
    r"(?:\s+(\d+))"
    r"(?:\s+(\d+))?\b"
)


def _extract_fen_from_text(text: str) -> Optional[str]:
    """Pull a standard 6-field FEN from free text if present."""
    if not text:
        return None
    m = _FEN_RE.search(text.replace("\n", " "))
    if not m:
        return None
    parts = [m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)]
    parts.append(m.group(6) or "1")
    return " ".join(parts)


def _optional_board_fen(data: dict[str, Any], message: str = "") -> Optional[str]:
    raw = data.get("board_fen")
    if raw is not None:
        s = str(raw).strip()
        if s and s.lower() not in ("null", "none", ""):
            fen = _extract_fen_from_text(s) or (s if s.count("/") == 7 else None)
            if fen:
                return fen
    # If agent forgot board_fen but user pasted a FEN and asked to load/set.
    msg = (message or "").lower()
    load_words = ("보드", "올려", "불러", "load", "set", "연습", "이 포지션", "이 자리")
    if any(w in msg for w in load_words):
        return _extract_fen_from_text(message)
    return None


def _candidate_ucis(candidates: list[Candidate]) -> list[str]:
    out: list[str] = []
    for c in candidates:
        u = (c.uci or "").strip()
        if u and u not in out:
            out.append(u)
    return out


def _pick_fallback(
    candidates: list[Candidate], reason: str, skill_level: int = 10
) -> MoveResponse:
    uci = pick_by_skill(candidates, skill_level)
    return MoveResponse(
        uci=uci,
        reason=reason,
        reply="",
        fallback=True,
    )


def _gate_log(gate: str, proposed: str, applied: str, allowed: list[str], fen: str, note: str = "") -> None:
    """One greppable line per move decision (Godot redirects stdout to sidecar.log)."""
    line = (
        f"[GATE] {gate.upper():8s} proposed={proposed or '(none)'} applied={applied or '(none)'} "
        f"candidates={','.join(allowed)} fen={fen}"
    )
    if note:
        line += f" note={note}"
    print(line, flush=True)


def _clamp_move(
    uci: str,
    candidates: list[Candidate],
    reason: str,
    reply: str,
    skill_level: int = 10,
    fen: str = "",
    source: str = "llm",
) -> MoveResponse:
    allowed_list = _candidate_ucis(candidates)
    allowed = set(allowed_list)
    u = (uci or "").strip().lower()
    if u in allowed:
        _gate_log("pass", u, u, allowed_list, fen, source)
        return MoveResponse(
            uci=u, reason=reason or "", reply=reply or "", fallback=False, llm_uci=u, gate="pass"
        )
    fb = _pick_fallback(candidates, "", skill_level)
    fb.reason = f"{source} 제안 '{u or '(파싱 실패)'}'는 후보 밖 → 난이도 가중 후보 {fb.uci}로 교체"
    fb.reason = (reason + " | " if reason else "") + fb.reason
    fb.llm_uci = u
    fb.gate = "replaced"
    _gate_log("replaced", u, fb.uci, allowed_list, fen, source)
    if reply:
        fb.reply = reply
    return fb


def _gate_recommend(
    proposed: Any,
    candidates: list[Candidate],
    fen: str,
    asked: bool,
    book_lines: Any = None,
    history: str = "",
) -> tuple[Optional[str], str, str]:
    """
    Candidate gate for moves the agent recommends to the user.
    Returns (uci or None, gate, note). Allowed = MultiPV candidates + next book move.
    """
    allowed_list = _candidate_ucis(candidates)
    if not allowed_list:
        return None, "", ""
    book_ok: list[str] = []
    lines = normalize_book_lines(book_lines)
    if lines:
        book_ok = book_next_moves(lines, parse_history(history))
    u = str(proposed or "").strip().lower()
    if u in ("none", "null"):
        u = ""
    best = allowed_list[0]
    if u and u in allowed_list:
        _gate_log("pass", u, u, allowed_list, fen, "recommend")
        return u, "pass", ""
    if u and u in book_ok:
        _gate_log("book", u, u, allowed_list, fen, "recommend book move (Godot checks legality)")
        return u, "book", ""
    if u:
        _gate_log("replaced", u, best, allowed_list, fen, "recommend")
        return best, "replaced", f"(게이트: 에이전트 추천 {u}는 엔진 후보 밖이라 엔진 1위 {best}로 바꿨습니다)"
    if asked:
        _gate_log("filled", "", best, allowed_list, fen, "recommend (agent gave none)")
        return best, "filled", f"(추천 수는 엔진 1위 {best}입니다)"
    return None, "", ""


def _candidates_prompt(body: "ChatRequest") -> str:
    if not body.candidates:
        return ""
    side = body.side or "(side to move)"
    rows = [
        {"rank": c.rank, "uci": c.uci, "score_cp": c.score_cp, "mate": c.mate}
        for c in body.candidates
    ]
    return f"""
사용자({side}) 차례의 Stockfish 후보 (rank 1이 최선, score_cp는 사용자 기준):
{json.dumps(rows, ensure_ascii=False)}
사용자가 수 추천을 원하면 recommend_uci에 위 후보 중 하나(또는 방금 준비한 오프닝 북의 사용자 쪽 다음 수)만 넣으세요.
reply에서 추천 수를 말할 때도 recommend_uci와 같은 수만 말하세요. 후보에 없는 수는 추천하지 마세요.
추천을 원하지 않으면 recommend_uci는 null.
"""


def _mentions_mate(message: str) -> bool:
    m = (message or "").lower()
    return any(k in m for k in ("메이트", "mate", "엔딩", "endgame", "엔드게임"))


def _catalog_response(p: dict[str, Any], agent_id: str) -> "ChatResponse":
    return ChatResponse(
        reply=practice.reply_for(p),
        board_fen=p["fen"],
        setup=SetupInfo(
            name=p["name"],
            goal=p["goal"],
            mate_in=int(p.get("mate_in", 0)),
            material=p["material"],
            source="catalog",
            catalog_id=p["id"],
        ),
        agent_id=agent_id,
    )


def _run_agent_text(agent_id: str, prompt: str) -> str:
    if _use_mock():
        return ""

    sess = _sessions.get(agent_id)
    if sess is None:
        raise HTTPException(status_code=404, detail="unknown agent_id; call /session first")

    agent = sess.get("agent")
    if agent is None:
        try:
            agent = _create_cursor_agent()
            sess["agent"] = agent
            sess["agent_sdk_id"] = getattr(agent, "agent_id", None) or getattr(
                agent, "agentId", None
            )
        except Exception as e:
            traceback.print_exc()
            raise RuntimeError(
                "Cursor Agent.create 실패. .env 의 CURSOR_API_KEY 를 확인하세요 "
                f"(Dashboard → Integrations). 원인: {e}"
            ) from e

    run = agent.send(prompt)
    # Prefer convenience text() if available
    if hasattr(run, "text") and callable(run.text):
        return str(run.text() or "")
    result = run.wait()
    # Best-effort extract
    if hasattr(result, "result") and result.result:
        return str(result.result)
    return ""


def _create_cursor_agent():
    from cursor_sdk import Agent, LocalAgentOptions

    patch_cursor_sdk_bridge()
    _ensure_workdir()
    key = _api_key()
    created = Agent.create(
        model=MODEL,
        api_key=key,
        local=LocalAgentOptions(cwd=_ensure_workdir()),
    )
    # Context-manager style create: enter if needed
    if hasattr(created, "__enter__"):
        return created.__enter__()
    return created


def _close_agent(agent: Any) -> None:
    if agent is None:
        return
    try:
        if hasattr(agent, "close") and callable(agent.close):
            agent.close()
        elif hasattr(agent, "__exit__"):
            agent.__exit__(None, None, None)
    except Exception:
        pass


@app.get("/health")
def health() -> dict[str, Any]:
    key = _api_key()
    raw = os.environ.get("CURSOR_API_KEY", "").strip()
    return {
        "ok": True,
        "mock": _use_mock(),
        "model": MODEL,
        "sessions": len(_sessions),
        "api_key_set": bool(key),
        "api_key_placeholder": bool(raw) and not bool(key),
        "code_rev": CODE_REV,
    }


@app.post("/session", response_model=SessionResponse)
def create_session(body: SessionRequest | None = None) -> SessionResponse:
    """Allocate a session id only. Cursor Agent is created lazily on first /move or /chat."""
    body = body or SessionRequest()
    agent_id = "sess_" + uuid.uuid4().hex[:12]
    mock = _use_mock()
    _sessions[agent_id] = {
        "agent": None,
        "style_notes": body.style_notes or "",
        "opening_name": "",
        "book_lines": [],
        "last_move": {},
    }
    return SessionResponse(agent_id=agent_id, mock=mock)


@app.delete("/session/{agent_id}")
def delete_session(agent_id: str) -> dict[str, bool]:
    sess = _sessions.pop(agent_id, None)
    if sess:
        _close_agent(sess.get("agent"))
    return {"ok": True}


@app.post("/move", response_model=MoveResponse)
def choose_move(body: MoveRequest) -> MoveResponse:
    if not body.candidates:
        raise HTTPException(status_code=400, detail="candidates required")

    agent_id = body.agent_id
    if not agent_id or agent_id not in _sessions:
        created = create_session(SessionRequest(style_notes=body.style_notes))
        agent_id = created.agent_id

    sess = _sessions[agent_id]
    style = body.style_notes or sess.get("style_notes", "")
    if body.style_notes:
        sess["style_notes"] = body.style_notes

    # Client-provided book wins; else session book from prior /chat lookup.
    client_book = normalize_book_lines(body.book_lines)
    if client_book:
        sess["book_lines"] = client_book
    if body.opening_name:
        sess["opening_name"] = body.opening_name
    book_lines = client_book or sess.get("book_lines") or []
    opening_name = body.opening_name or sess.get("opening_name") or ""

    history = body.history_uci or ""
    skill = int(body.skill_level) if body.skill_level is not None else 10

    inject = os.environ.get("AI_SIDECAR_INJECT_UCI", "").strip()
    if inject:
        # Test-only: pretend the model answered with `inject`, then run the same gate.
        # Runs before the opening book so the demo is deterministic.
        resp = _clamp_move(inject, body.candidates, "", "", skill, body.fen, source="inject")
        resp.agent_id = agent_id
        sess["last_move"] = {"uci": resp.uci, "reason": resp.reason, "fen": body.fen}
        return resp

    book = resolve_book_move(book_lines, history, body.side, opening_name)
    if book is not None:
        resp = MoveResponse(
            uci=book["uci"],
            reason=book["reason"],
            reply=book["reply"],
            fallback=False,
            agent_id=agent_id,
            llm_uci=book["uci"],
            gate="book",
        )
        _gate_log("book", resp.uci, resp.uci, _candidate_ucis(body.candidates), body.fen, "book line (Godot checks legality)")
        sess["last_move"] = {"uci": resp.uci, "reason": resp.reason, "fen": body.fen}
        return resp

    # Optional: ask agent for the next book move if we have an opening name but
    # history left the stored lines (transposition / longer game).
    if opening_name and not _use_mock():
        try:
            look = _run_agent_text(
                agent_id,
                f"""{COACH_ROLE}
사용자가 요청한 오프닝 '{opening_name}' 라인을 이 포지션에서 이어갈 수 있으면 이어가세요.
현재 기보(UCI): {history or '(시작)'}
FEN: {body.fen}
AI side: {body.side}

오프닝/이론 수로 둘 수 있으면 지금 AI가 둘 UCI 한 수만 JSON으로:
{{"uci":"e7e5","reason":"내부용 짧은 메모","reply":"","in_book":true}}
이론과 무관하거나 미들/엔드로 넘어갔으면 in_book=false 와 빈 uci.
합법적인 UCI만. reply는 항상 "".
""",
            )
            data = _extract_json_object(look)
            if bool(data.get("in_book", False)):
                u = str(data.get("uci", "")).strip().lower()
                if u:
                    resp = MoveResponse(
                        uci=u,
                        reason=str(data.get("reason", f"{opening_name} 판단")),
                        reply="",
                        fallback=False,
                        agent_id=agent_id,
                        llm_uci=u,
                        gate="book",
                    )
                    _gate_log("book", u, u, _candidate_ucis(body.candidates), body.fen, "llm book move (Godot checks legality)")
                    sess["last_move"] = {
                        "uci": resp.uci,
                        "reason": resp.reason,
                        "fen": body.fen,
                    }
                    return resp
        except Exception:
            traceback.print_exc()

    book_hint = ""
    if opening_name:
        book_hint = (
            f"\n요청 오프닝: {opening_name}. 북 수가 이번 포지션에 없으면 "
            "candidates 안에서 아이디어만 맞추세요. rank 1만 고르지 마세요."
        )

    cand_payload = [c.model_dump() for c in body.candidates]
    prompt = f"""{COACH_ROLE}
Stockfish MultiPV 후보 중에서 하나만 고르세요.
candidates에 없는 UCI는 금지입니다. 채팅에 자동 해설을 쓰지 마세요.

국면(오프닝/미들/전술/포지셔널/엔드)에 맞게 판단하세요.
중요:
- Skill Level={skill}/20 입니다. 낮을수록 2~N순위 후보를 더 자주 고르세요. 항상 rank 1만 고르지 마세요.
- 사용자가 요청한 오프닝·스타일·연습 목표를 존중하세요.
- reply는 항상 "" (빈 문자열). reason은 나중에 사용자가 물을 때만 쓸 내부 메모.

FEN: {body.fen}
AI side: {body.side}
기보(UCI): {history or "(시작)"}
상대의 직전 수(UCI): {body.last_human_uci or "(없음)"}
스타일/오프닝 지시: {style or "(없음)"}
{book_hint}

candidates JSON:
{json.dumps(cand_payload, ensure_ascii=False)}

응답은 오직 JSON 한 개만:
{{"uci":"<후보 중 하나>","reason":"<내부용 짧은 메모>","reply":""}}
"""

    if _use_mock():
        resp = _pick_fallback(body.candidates, "mock: 난이도 가중 후보 선택", skill)
        resp.gate = "mock"
        _gate_log("mock", "", resp.uci, _candidate_ucis(body.candidates), body.fen)
        if opening_name:
            resp.reason = f"{opening_name} 북 수 없음 → Skill {skill} 가중 ({resp.uci})"
        resp.reply = ""
        resp.agent_id = agent_id
        sess["last_move"] = {"uci": resp.uci, "reason": resp.reason, "fen": body.fen}
        return resp

    try:
        text = _run_agent_text(agent_id, prompt)
        data = _extract_json_object(text)
        resp = _clamp_move(
            str(data.get("uci", "")),
            body.candidates,
            str(data.get("reason", "")),
            "",  # never auto-chat on moves
            skill,
            body.fen,
        )
        resp.reply = ""
        resp.agent_id = agent_id
        sess["last_move"] = {"uci": resp.uci, "reason": resp.reason, "fen": body.fen}
        return resp
    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        resp = _pick_fallback(body.candidates, f"에이전트 오류 → 폴백 ({e})", skill)
        resp.gate = "error"
        _gate_log("error", "", resp.uci, _candidate_ucis(body.candidates), body.fen, type(e).__name__)
        resp.agent_id = agent_id
        sess["last_move"] = {"uci": resp.uci, "reason": resp.reason, "fen": body.fen}
        return resp


@app.post("/chat", response_model=ChatResponse)
def chat(body: ChatRequest) -> ChatResponse:
    agent_id = body.agent_id
    if not agent_id or agent_id not in _sessions:
        created = create_session(SessionRequest(style_notes=body.style_notes))
        agent_id = created.agent_id

    sess = _sessions[agent_id]
    style = body.style_notes or sess.get("style_notes", "")
    last = sess.get("last_move") or {}
    last_uci = (body.last_ai_uci or last.get("uci", "") or "").strip()
    last_reason = (body.last_reason or last.get("reason", "") or "").strip()

    asked_recommend = looks_like_recommend_request(body.message)
    cand_block = _candidates_prompt(body)

    # Position setup request (mate pattern / endgame drill) → agent proposes a FEN,
    # Godot verifies it (rules + material + Stockfish) before it touches the board.
    cat = practice.match(body.message)
    if cat is not None and (looks_like_setup_request(body.message) or _mentions_mate(body.message)):
        print(f"[SETUP] catalog id={cat['id']} fen={cat['fen']}", flush=True)
        return _catalog_response(cat, agent_id)

    if looks_like_setup_request(body.message):
        if _use_mock():
            return ChatResponse(
                reply="포지션 세팅에는 유효한 CURSOR_API_KEY 가 필요합니다.",
                agent_id=agent_id,
            )
        prompt = f"""{COACH_ROLE}
사용자가 특정 메이트 패턴이나 엔드게임을 연습할 포지션을 보드에 세팅해 달라고 합니다.
요청을 해석해 연습용 포지션 하나를 표준 6필드 FEN으로 만드세요.

{TERMINOLOGY_RULES}

포지션 규칙 (Godot가 규칙·기물·Stockfish로 검증하고, 틀리면 거부합니다):
- 백 킹 1개, 흑 킹 1개. 1·8랭크에 폰 없음.
- 차례가 아닌 쪽 킹은 체크 상태가 아니어야 합니다.
- 차례(side to move)는 연습하는 쪽(공격하는 쪽)입니다.
- 메이트 패턴(예: Boden's Mate, Anastasia's Mate, Back-rank Mate, Smothered Mate)이면
  goal="mate", mate_in=실제 메이트까지 수(1~3). 패턴이 실제로 나오는 위치여야 합니다.
- 엔드게임 기술(예: 비숍+나이트 메이트 = KBN vs K, 룩 엔딩, 킹+폰)이면 goal="endgame",
  mate_in=0, 차례인 쪽이 이기는 포지션.
- material은 "백 기물 v 흑 기물"을 킹 포함 대문자로 (예: "KBN v K", "KR v K", "KQ v KR").
  FEN의 실제 기물과 정확히 같아야 합니다.
- 캐슬링 권리는 보통 "-".

검증된 연습 포지션 목록 (요청이 이 중 하나면 FEN을 만들지 말고 catalog_id만 주세요):
{practice.catalog_prompt()}

현재 보드 FEN(참고): {body.fen or "(없음)"}
사용자: {body.message}

응답은 오직 JSON 한 개 (목록에 있으면 {{"catalog_id": "rook_mate"}} 만):
{{
  "catalog_id": null,
  "reply": "한국어 짧은 안내 (무슨 포지션인지, 무엇을 연습하는지). 해답 수순은 쓰지 마세요.",
  "board_fen": "<6필드 FEN>",
  "setup": {{"name": "Bishop and Knight Mate", "goal": "endgame", "mate_in": 0, "material": "KBN v K"}}
}}
"""
        try:
            text = _run_agent_text(agent_id, prompt)
            data = _extract_json_object(text)
            picked = practice.by_id(str(data.get("catalog_id") or "").strip())
            if picked is not None:
                print(f"[SETUP] agent picked catalog id={picked['id']}", flush=True)
                return _catalog_response(picked, agent_id)
            fen = str(data.get("board_fen") or "").strip() or None
            setup_raw = data.get("setup") if isinstance(data.get("setup"), dict) else {}
            setup = SetupInfo(
                name=str(setup_raw.get("name", "") or ""),
                goal=str(setup_raw.get("goal", "practice") or "practice").lower(),
                mate_in=int(setup_raw.get("mate_in", 0) or 0),
                material=str(setup_raw.get("material", "") or ""),
            )
            print(
                f"[SETUP] proposed fen={fen} name={setup.name} goal={setup.goal} "
                f"mate_in={setup.mate_in} material={setup.material}",
                flush=True,
            )
            return ChatResponse(
                reply=str(data.get("reply", "") or "포지션을 준비했어요."),
                board_fen=fen,
                setup=setup if fen else None,
                agent_id=agent_id,
            )
        except Exception as e:
            traceback.print_exc()
            return ChatResponse(reply=f"포지션 세팅 오류: {e}", agent_id=agent_id)

    # Opening request → ask Cursor to look up / recall main lines as UCI book.
    if looks_like_opening_request(body.message):
        if _use_mock():
            return ChatResponse(
                reply=(
                    "오프닝을 찾으려면 유효한 CURSOR_API_KEY 가 필요합니다. "
                    ".env 에 키를 넣은 뒤 상대:AI 를 다시 켜 주세요."
                ),
                style_update=None,
                opening_name=None,
                book_lines=[],
                agent_id=agent_id,
            )

        prompt = f"""{COACH_ROLE}
사용자가 오프닝/라인 연습을 요청했습니다. 요청을 해석해 메인 라인을 UCI book으로 준비하세요.
필요하면 표준 메인/사이드 라인 2~4개를 제시하세요.
수를 보드에 두지 말고 JSON만 반환하세요. 게임이 이 오프닝을 따르도록 book_lines를 채우세요.

{TERMINOLOGY_RULES}

현재 FEN: {body.fen or "(시작)"}
기보 요약(UCI): {body.history_summary or "(없음)"}
이전 스타일: {style or "(없음)"}
사용자: {body.message}
{cand_block}
응답 JSON 스키마:
{{
  "reply": "한국어 대화 톤. 오프닝 이름은 영어만 (예: Sicilian Defense, Najdorf Variation)",
  "recommend_uci": null,
  "opening_name": "Sicilian Defense, Najdorf Variation",
  "style_update": "opening:sicilian_najdorf | short English coaching note",
  "book_lines": [
    ["e2e4", "c7c5", "g1f3", "d7d6"],
    ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4"]
  ]
}}

규칙:
- opening_name 은 반드시 표준 영어 (한글 음차 금지)
- book_lines 의 각 수는 반드시 UCI (예: e2e4, g1f3, e8g8, a7a8q)
- 라인은 시작 포지션부터의 수순. AI가 흑/백 어느 쪽이든 쓸 수 있게 양쪽 수 포함
- SAN(Nf3) 금지, UCI만
"""
        try:
            text = _run_agent_text(agent_id, prompt)
            data = _extract_json_object(text)
            reply = str(data.get("reply", "") or text or "오프닝을 준비했어요.")
            style_update = data.get("style_update")
            if style_update is not None:
                style_update = str(style_update).strip() or None
            opening_name = data.get("opening_name")
            if opening_name is not None:
                opening_name = str(opening_name).strip() or None
            book_lines = normalize_book_lines(data.get("book_lines"))
            if style_update:
                sess["style_notes"] = style_update
            if opening_name:
                sess["opening_name"] = opening_name
            if book_lines:
                sess["book_lines"] = book_lines
                reply = f"{reply} (북 {len(book_lines)}줄 로드)"
            elif opening_name:
                reply = f"{reply} (북 라인을 못 받아 이후 수에서 다시 판단할게요)"
            llm_rec = str(data.get("recommend_uci") or "").strip().lower()
            rec, rec_gate, rec_note = _gate_recommend(
                llm_rec, body.candidates, body.fen, asked_recommend,
                book_lines or sess.get("book_lines"), body.history_summary,
            )
            if rec_note:
                reply = f"{reply} {rec_note}"
            return ChatResponse(
                reply=reply,
                style_update=style_update,
                opening_name=opening_name,
                book_lines=book_lines,
                agent_id=agent_id,
                recommend_uci=rec,
                recommend_llm_uci=llm_rec,
                recommend_gate=rec_gate,
            )
        except Exception as e:
            traceback.print_exc()
            return ChatResponse(
                reply=f"오프닝 조회 오류: {e}",
                style_update=None,
                opening_name=None,
                book_lines=[],
                agent_id=agent_id,
            )

    prompt = f"""{COACH_ROLE}
사용자와 한국어로 자연스럽게 대화하세요.
자발적으로 매 수 해설을 하지 마세요. 사용자가 물은 내용에만 답하세요.
오프닝·미들게임·전술·포지셔널·엔드게임·연습 목표 등 어떤 주제든 다룹니다.

{TERMINOLOGY_RULES}

사용자가 메시지에 FEN 또는 PGN을 붙여넣으면:
- 그 포지션/기보를 우선 분석·코칭하세요 (아래 "현재 보드 FEN"보다 붙여넣은 쪽이 우선).
- PGN이면 국면·핵심 수·대안·실수를 설명해 주세요.
- FEN이면 평가·플랜·후보 아이디어·전술 테마를 설명해 주세요.
- 보드에 올리거나 그 포지션에서 연습하자고 하면 board_fen에 표준 6필드 FEN을 넣으세요.
  (PGN만 있으면 최종/요청 포지션의 FEN을 스스로 추론해 board_fen에 넣으세요.)
- 코칭만 원하고 보드 변경을 말하지 않으면 board_fen은 null.

체스/대국 관련 명령이면 JSON 필드로 게임에 반영합니다:
- 오프닝/라인 요청 → opening_name(영어) + book_lines(UCI 수순)
- 스타일·연습 요청(공격적/전술 위주/엔드 연습 등) → style_update
- 직전 수 이유("왜?", "그 수 설명해줘") → last AI 수를 바탕으로 reply에 설명
- 보드에 올릴 FEN → board_fen
- 일반 잡담/질문 → reply만, 다른 필드는 null/[]
- "어떤 메이트를 연습할 수 있어?" 같은 질문 → 아래 연습 포지션 이름을 소개 (사용자가 이름을 말하면 바로 보드에 올라갑니다)

연습 포지션 목록:
{practice.catalog_prompt()}

수를 보드에 직접 두지 마세요. 합법 UCI book만 제시합니다.

현재 보드 FEN: {body.fen or "(없음)"}
기보(UCI): {body.history_summary or "(없음)"}
현재 스타일: {style or "(없음)"}
세션 오프닝: {sess.get("opening_name") or "(없음)"}
직전 AI 수(UCI): {last_uci or "(없음)"}
직전 내부 메모: {last_reason or "(없음)"}
사용자: {body.message}
{cand_block}
응답은 오직 JSON 한 개:
{{
  "reply": "한국어 답변 (오프닝명은 영어, 용어는 한국 관용/영어)",
  "recommend_uci": null,
  "style_update": null,
  "opening_name": null,
  "book_lines": [],
  "board_fen": null
}}
"""

    if _use_mock():
        return ChatResponse(
            reply="mock 채팅입니다. 오프닝 조회·실전 해설은 CURSOR_API_KEY 가 필요합니다.",
            agent_id=agent_id,
        )

    try:
        text = _run_agent_text(agent_id, prompt)
        data = _extract_json_object(text)
        reply = str(data.get("reply", "") or text or "응답을 파싱하지 못했어요.")
        style_update = data.get("style_update")
        if style_update is not None:
            style_update = str(style_update).strip() or None
        opening_name = data.get("opening_name")
        if opening_name is not None:
            opening_name = str(opening_name).strip() or None
        book_lines = normalize_book_lines(data.get("book_lines"))
        if style_update:
            sess["style_notes"] = style_update
        if opening_name:
            sess["opening_name"] = opening_name
        if book_lines:
            sess["book_lines"] = book_lines
            reply = f"{reply} (북 {len(book_lines)}줄 로드)"
        board_fen = _optional_board_fen(data, body.message)
        llm_rec = str(data.get("recommend_uci") or "").strip().lower()
        rec, rec_gate, rec_note = _gate_recommend(
            llm_rec, body.candidates, body.fen, asked_recommend,
            sess.get("book_lines"), body.history_summary,
        )
        if rec_note:
            reply = f"{reply} {rec_note}"
        return ChatResponse(
            reply=reply,
            style_update=style_update,
            opening_name=opening_name,
            book_lines=book_lines,
            board_fen=board_fen,
            agent_id=agent_id,
            recommend_uci=rec,
            recommend_llm_uci=llm_rec,
            recommend_gate=rec_gate,
        )
    except Exception as e:
        traceback.print_exc()
        return ChatResponse(reply=f"채팅 오류: {e}", agent_id=agent_id)


@app.post("/explain", response_model=ChatResponse)
def explain(body: ExplainRequest) -> ChatResponse:
    agent_id = body.agent_id
    if not agent_id or agent_id not in _sessions:
        created = create_session(SessionRequest())
        agent_id = created.agent_id

    sess = _sessions[agent_id]
    last = sess.get("last_move") or {}
    uci = body.last_ai_uci or last.get("uci", "")
    reason = body.last_reason or last.get("reason", "")

    prompt = f"""{COACH_ROLE}
직전 AI 수에 대해 사용자가 이유를 묻습니다. JSON만 반환.
국면(오프닝/미들/전술/포지셔널/엔드)에 맞게 설명하세요.

{TERMINOLOGY_RULES}

FEN(수 둔 뒤 또는 직전): {body.fen or last.get("fen", "")}
AI가 둔 UCI: {uci}
당시 짧은 이유: {reason}
후보였던 수: {json.dumps([c.model_dump() for c in body.candidates], ensure_ascii=False)}
사용자 질문: {body.message}

응답 JSON:
{{"reply":"<한국어 설명. 오프닝명은 영어, 용어는 한국 관용 또는 영어>","style_update":null}}
"""

    if _use_mock():
        reply = (
            f"mock 해설: {uci or '?'}는 엔진 후보 안에서 고른 수예요. "
            f"기록된 이유: {reason or '(없음)'}"
        )
        return ChatResponse(reply=reply, style_update=None, agent_id=agent_id)

    try:
        text = _run_agent_text(agent_id, prompt)
        data = _extract_json_object(text)
        reply = str(data.get("reply", "") or text or "해설을 파싱하지 못했어요.")
        return ChatResponse(reply=reply, style_update=None, agent_id=agent_id)
    except Exception as e:
        traceback.print_exc()
        return ChatResponse(reply=f"해설 오류: {e}", style_update=None, agent_id=agent_id)


@app.on_event("shutdown")
def _shutdown() -> None:
    for aid in list(_sessions.keys()):
        sess = _sessions.pop(aid, None)
        if sess:
            _close_agent(sess.get("agent"))
