"""
Gate check without an API key: feed the sidecar a model answer that is NOT a
Stockfish candidate and confirm it is replaced by a candidate.

  cd ai_sidecar
  python test_gate.py

If engine/stockfish/stockfish(.exe) exists, candidates come from a real
Stockfish MultiPV search on the start position. Otherwise a fixed candidate
list is used (printed as "fixed").

The model answer is injected through the same AI_SIDECAR_INJECT_UCI path the
game uses for the gate demo, so /move runs the real `_clamp_move` gate.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import server  # noqa: E402
from server import Candidate, MoveRequest, _gate_recommend, choose_move  # noqa: E402

START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


def _stockfish_path() -> Path | None:
    root = HERE.parent / "engine" / "stockfish"
    for name in ("stockfish.exe", "stockfish"):
        p = root / name
        if p.is_file():
            return p
    return None


def stockfish_candidates(fen: str, multipv: int = 5, movetime_ms: int = 300) -> list[Candidate]:
    exe = _stockfish_path()
    if exe is None:
        return []
    cmds = (
        "uci\n"
        f"setoption name MultiPV value {multipv}\n"
        "isready\n"
        f"position fen {fen}\n"
        f"go movetime {movetime_ms}\n"
    )
    proc = subprocess.Popen(
        [str(exe)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True
    )
    assert proc.stdin and proc.stdout
    proc.stdin.write(cmds)
    proc.stdin.flush()
    best: dict[int, Candidate] = {}
    for line in proc.stdout:
        parts = line.split()
        if parts[:1] == ["bestmove"]:
            break
        if "multipv" in parts and " pv " in line:
            rank = int(parts[parts.index("multipv") + 1])
            uci = parts[parts.index("pv") + 1]
            depth = int(parts[parts.index("depth") + 1]) if "depth" in parts else 0
            cp = 0
            mate = 0
            if "cp" in parts:
                cp = int(parts[parts.index("cp") + 1])
            if "mate" in parts:
                mate = int(parts[parts.index("mate") + 1])
            best[rank] = Candidate(rank=rank, uci=uci, score_cp=cp, mate=mate, depth=depth)
    proc.stdin.write("quit\n")
    proc.stdin.flush()
    proc.wait(timeout=5)
    return [best[k] for k in sorted(best)]


def run_case(label: str, injected: str, cands: list[Candidate]) -> bool:
    os.environ["AI_SIDECAR_INJECT_UCI"] = injected
    try:
        resp = choose_move(MoveRequest(fen=START_FEN, side="white", candidates=cands))
    finally:
        os.environ.pop("AI_SIDECAR_INJECT_UCI", None)
    allowed = {c.uci for c in cands}
    ok_in = resp.uci in allowed
    expect_gate = "pass" if injected in allowed else "replaced"
    ok = ok_in and resp.gate == expect_gate and resp.llm_uci == injected
    print(
        f"{'PASS' if ok else 'FAIL'} {label}: proposed={injected} -> applied={resp.uci} "
        f"gate={resp.gate} reason={resp.reason}"
    )
    return ok


def main() -> int:
    cands = stockfish_candidates(START_FEN)
    source = "stockfish"
    if not cands:
        source = "fixed"
        cands = [
            Candidate(rank=1, uci="e2e4"),
            Candidate(rank=2, uci="d2d4"),
            Candidate(rank=3, uci="g1f3"),
        ]
    print(f"candidates ({source}): {[c.uci for c in cands]}")

    results = [
        # King jumps across the board: illegal and not a candidate.
        run_case("illegal move", "e1e8", cands),
        # Legal but not in MultiPV (a weak first move).
        run_case("legal but off-candidate", "g2g4" if "g2g4" not in {c.uci for c in cands} else "h2h4", cands),
        # Not UCI at all (model wrote prose).
        run_case("unparseable answer", "knight to f3", cands),
        # A real candidate passes unchanged.
        run_case("candidate passes", cands[0].uci, cands),
    ]
    # Recommendations to the user (/chat) go through the same kind of gate.
    def rec_case(label: str, proposed: str, asked: bool, want_gate: str, book=None, hist="") -> bool:
        uci, gate, note = _gate_recommend(proposed, cands, START_FEN, asked, book, hist)
        allowed = {c.uci for c in cands} | ({proposed} if want_gate == "book" else set())
        ok = gate == want_gate and (uci in allowed if want_gate else uci is None)
        print(f"{'PASS' if ok else 'FAIL'} recommend {label}: proposed={proposed or '(none)'} -> {uci} gate={gate} {note}")
        return ok

    results += [
        rec_case("candidate passes", cands[0].uci, True, "pass"),
        rec_case("off-candidate replaced", "g2g4" if "g2g4" not in {c.uci for c in cands} else "h2h4", True, "replaced"),
        rec_case("illegal replaced", "e1e8", True, "replaced"),
        rec_case("missing but asked -> engine #1", "", True, "filled"),
        rec_case("not asked -> none", "", False, ""),
        rec_case("next book move allowed", "b2b3", True, "book", [["b2b3", "e7e5"]], ""),
    ]
    results += catalog_cases()
    failed = results.count(False)
    print(f"gate test: {len(results) - failed}/{len(results)} passed")
    return 1 if failed else 0


def catalog_cases() -> list[bool]:
    """Every practice position: Stockfish confirms it, and Korean/English names find it."""
    import practice

    out: list[bool] = []
    have_engine = _stockfish_path() is not None
    for p in practice.positions():
        if not have_engine:
            break
        c = stockfish_candidates(p["fen"], multipv=1, movetime_ms=1500)
        top = c[0] if c else None
        if p["goal"] == "mate":
            ok = bool(top) and top.mate == p["mate_in"] and top.uci in p.get("solution", [])
        else:
            ok = bool(top) and (top.mate > 0 or top.score_cp >= 100)
        seen = f"mate {top.mate}" if top and top.mate else f"cp {top.score_cp if top else '?'}"
        print(f"{'PASS' if ok else 'FAIL'} catalog {p['id']}: goal={p['goal']} best={top.uci if top else '?'} {seen}")
        out.append(ok)
    for msg, want in [
        ("비나메이트 연습하고 싶어, 기물 세팅해줘", "bishop_knight_mate"),
        ("룩 메이트 해보고 싶어", "rook_mate"),
        ("투룩 메이트", "two_rook_mate"),
        ("백랭크메이트 연습", "back_rank_mate"),
        ("퀸 대 룩 엔딩 연습", "queen_vs_rook"),
        ("Boden's mate please", "boden_mate"),
    ]:
        got = practice.match(msg)
        ok = got is not None and got["id"] == want
        print(f"{'PASS' if ok else 'FAIL'} catalog match '{msg}' -> {got['id'] if got else None}")
        out.append(ok)
    return out


if __name__ == "__main__":
    sys.exit(main())
