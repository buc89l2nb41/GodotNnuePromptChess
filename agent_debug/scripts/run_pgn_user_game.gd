extends SceneTree
const P = preload("res://scripts/pgn_fen.gd")
func _init():
	var pgn := """[Event \"Live Chess\"]
[Site \"Chess.com\"]
[Date \"2026.07.26\"]
[Round \"?\"]
[White \"Guest2084306416\"]
[Black \"Guest4072334167\"]
[Result \"0-1\"]
[TimeControl \"600\"]
[WhiteElo \"200\"]
[BlackElo \"200\"]
[Termination \"Guest4072334167님 승 - 게임 유기됨\"]
[Link \"https://www.chess.com/game/172106450112\"]

1. e4 c5 2. Qf3 e6 3. Nh3 Nc6 4. d3 Nf6 5. Bg5 Be7 6. e5 Nd4 7. Qf4 Nxc2+ 8. Kd1
Nd5 9. Qh4 Nxa1 10. Nf4 Bxg5 11. Qg4 Nxf4 12. g3 Nd5 13. h4 Bh6 0-1
"""
	var r: Dictionary = P.load_text(pgn)
	print("ok=", r.get("ok", false), " err=", r.get("error", ""), " n=", PackedStringArray(r.get("uci_history", PackedStringArray())).size())
	var toks = P._tokenize_pgn_moves(pgn)
	print("tokens(", toks.size(), "): ", " ".join(toks))
	quit(0 if bool(r.get("ok", false)) else 1)
