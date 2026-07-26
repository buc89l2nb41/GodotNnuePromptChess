"""Generic UCI opening-book helpers.

Openings are NOT hardcoded here. The Cursor agent looks up / recalls a line when
the user asks in chat, and those UCI sequences are stored on the session.
"""

from __future__ import annotations

import random
import re
from typing import Any, Optional


_UCI_RE = re.compile(r"^[a-h][1-8][a-h][1-8][qrbn]?$", re.IGNORECASE)


def parse_history(history: Any) -> list[str]:
    if history is None:
        return []
    if isinstance(history, list):
        return [str(x).strip().lower() for x in history if str(x).strip()]
    s = str(history).strip()
    if not s:
        return []
    return [p.strip().lower() for p in s.replace(",", " ").split() if p.strip()]


def normalize_book_lines(raw: Any) -> list[list[str]]:
    """Accept list[list[str]] or list[str] (single line) and keep only valid UCI tokens."""
    if raw is None:
        return []
    lines_in: list[Any]
    if isinstance(raw, list) and raw and isinstance(raw[0], str):
        lines_in = [raw]
    elif isinstance(raw, list):
        lines_in = raw
    else:
        return []

    out: list[list[str]] = []
    for line in lines_in:
        if not isinstance(line, (list, tuple)):
            continue
        cleaned: list[str] = []
        for mv in line:
            u = str(mv).strip().lower()
            if _UCI_RE.match(u):
                cleaned.append(u)
        if cleaned:
            out.append(cleaned)
    return out


def book_next_moves(book_lines: list[list[str]], history: list[str]) -> list[str]:
    hist = [h.lower() for h in history]
    out: list[str] = []
    for line in book_lines:
        line_l = [m.lower() for m in line]
        if len(hist) > len(line_l):
            continue
        if hist == line_l[: len(hist)]:
            if len(hist) < len(line_l):
                nxt = line_l[len(hist)]
                if nxt not in out:
                    out.append(nxt)
    return out


def resolve_book_move(
    book_lines: Any,
    history: Any,
    side: str = "",
    opening_name: str = "",
) -> Optional[dict[str, str]]:
    """Next book UCI for this turn, if any line matches history. Not limited to MultiPV."""
    lines = normalize_book_lines(book_lines)
    if not lines:
        return None
    hist = parse_history(history)
    stm_is_black = len(hist) % 2 == 1
    if side:
        want_black = str(side).strip().lower().startswith("b")
        if want_black != stm_is_black:
            return None
    preferred = book_next_moves(lines, hist)
    if not preferred:
        return None
    pref = preferred[0]
    label = opening_name.strip() or "요청 오프닝"
    return {
        "uci": pref,
        "reason": f"{label} 북 수 ({pref})",
        "reply": "",
    }


def looks_like_opening_request(message: str) -> bool:
    msg = (message or "").strip().lower()
    if not msg:
        return False
    keys = (
        "오프닝",
        "opening",
        "둬",
        "두어",
        "상대",
        "defence",
        "defense",
        "gambit",
        "갬빗",
        "인디언",
        "시실리안",
        "sicilian",
        "프랑스",
        "카로",
        "루이",
        "이탈리",
        "잉글리시",
        "네오",
        "님조",
        "그룬",
        "슬라브",
        "카탈란",
        "킹스",
        "퀸즈",
        "페트로프",
        "피안케토",
    )
    return any(k in msg for k in keys)


def candidate_list(candidates: list[Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for i, c in enumerate(candidates):
        if hasattr(c, "uci"):
            u = str(c.uci).strip().lower()
            rank = int(getattr(c, "rank", i + 1) or (i + 1))
        elif isinstance(c, dict):
            u = str(c.get("uci", "")).strip().lower()
            rank = int(c.get("rank", i + 1) or (i + 1))
        else:
            u = str(c).strip().lower()
            rank = i + 1
        if u:
            out.append({"uci": u, "rank": rank})
    out.sort(key=lambda x: x["rank"])
    return out


def pick_by_skill(candidates: list[Any], skill_level: int = 10) -> str:
    items = candidate_list(candidates)
    if not items:
        return ""
    if len(items) == 1:
        return items[0]["uci"]
    skill = max(0, min(20, int(skill_level)))
    exponent = 0.35 + (skill / 20.0) * 3.15
    weights: list[float] = []
    for it in items:
        r = max(1, int(it["rank"]))
        weights.append(1.0 / (float(r) ** exponent))
    total = sum(weights) or 1.0
    pick_roll = random.random() * total
    acc = 0.0
    for it, w in zip(items, weights):
        acc += w
        if pick_roll <= acc:
            return it["uci"]
    return items[0]["uci"]
