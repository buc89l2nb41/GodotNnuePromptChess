"""
Practice-position catalog (mate patterns / piece mates) for chat-driven setup.

The positions live in practice_positions.json. They are verified by
test_gate.py (Stockfish: intended first move mates / side to move converts)
and by Godot's run_gate_test.gd (rules + material). The game still runs the
setup gate on them like on any agent-made position.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Optional

_PATH = Path(__file__).resolve().parent / "practice_positions.json"
_CACHE: Optional[list[dict[str, Any]]] = None


def positions() -> list[dict[str, Any]]:
    global _CACHE
    if _CACHE is None:
        data = json.loads(_PATH.read_text(encoding="utf-8"))
        _CACHE = list(data.get("positions", []))
    return _CACHE


def _squash(text: str) -> str:
    return re.sub(r"[\s'’\-_.·/]+", "", (text or "").lower())


def by_id(pid: str) -> Optional[dict[str, Any]]:
    for p in positions():
        if p["id"] == pid:
            return p
    return None


def match(message: str) -> Optional[dict[str, Any]]:
    """
    Name/alias found earliest in the message wins; ties go to the longer alias.
    So "투룩 메이트" is two_rook_mate (not rook_mate) and "퀸 대 룩" is queen_vs_rook.
    """
    msg = _squash(message)
    if not msg:
        return None
    best: tuple[int, int, Optional[dict[str, Any]]] = (10**9, 0, None)
    for p in positions():
        keys = [*p.get("aliases", []), p["id"], p["name"], p.get("name_ko", "")]
        for k in keys:
            k2 = _squash(k)
            if not k2:
                continue
            pos = msg.find(k2)
            if pos < 0:
                continue
            if pos < best[0] or (pos == best[0] and len(k2) > best[1]):
                best = (pos, len(k2), p)
    return best[2]


def catalog_prompt() -> str:
    rows = [f'- {p["id"]}: {p["name"]} / {p.get("name_ko", "")} ({p["material"]})' for p in positions()]
    return "\n".join(rows)


def reply_for(p: dict[str, Any]) -> str:
    side = "백" if p["fen"].split()[1] == "w" else "흑"
    if p["goal"] == "mate":
        return (
            f'{p["name"]}({p.get("name_ko", "")}) 포지션을 올렸어요. '
            f'{side} 차례이고, {p["mate_in"]}수 만에 메이트할 수 있습니다. 찾아보세요.'
        )
    return (
        f'{p["name"]}({p.get("name_ko", "")}) 연습 포지션을 올렸어요. '
        f'{side} 차례, 기물은 {p["material"]}입니다. 상대 킹을 몰아 메이트해 보세요.'
    )
