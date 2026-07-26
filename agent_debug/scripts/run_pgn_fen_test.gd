extends SceneTree

const PgnFenScript = preload("res://scripts/pgn_fen.gd")

func _init() -> void:
	var failed := 0
	# FEN
	var fen := "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	var a: Dictionary = PgnFenScript.load_text(fen)
	if not bool(a.get("ok", false)):
		push_error("fen load fail: %s" % a.get("error", ""))
		failed += 1
	elif String(a.get("fen", "")) != fen:
		push_error("fen mismatch")
		failed += 1

	# Mini PGN: 1.e4 c5 2.Nf3
	var pgn := "1. e4 c5 2. Nf3"
	var b: Dictionary = PgnFenScript.load_text(pgn)
	if not bool(b.get("ok", false)):
		push_error("pgn load fail: %s" % b.get("error", ""))
		failed += 1
	else:
		var hist: PackedStringArray = b.get("uci_history", PackedStringArray())
		if hist.size() != 3:
			push_error("pgn hist size %d" % hist.size())
			failed += 1
		elif String(hist[0]) != "e2e4" or String(hist[1]) != "c7c5" or String(hist[2]) != "g1f3":
			push_error("pgn hist %s" % " ".join(hist))
			failed += 1

	# chess.com style with RAV variation — main line only
	var pgn2 := """[Event "?"]
1. e4 e5 2. Bc4 Nc6 (2... Bc5 3. Qf3 Nc6 4. Qxf7#) 3. Qf3 *"""
	var c: Dictionary = PgnFenScript.load_text(pgn2)
	if not bool(c.get("ok", false)):
		push_error("pgn2 load fail: %s" % c.get("error", ""))
		failed += 1
	else:
		var hist2: PackedStringArray = c.get("uci_history", PackedStringArray())
		if hist2.size() != 5:
			push_error("pgn2 hist size %d (%s)" % [hist2.size(), " ".join(hist2)])
			failed += 1
		elif String(hist2[4]) != "d1f3":
			push_error("pgn2 last %s" % hist2[4])
			failed += 1

	# Soft-wrapped line break between moves (chess.com)
	var pgn3 := "1. e4 e5 2. Nf3\nNc6 3. Bb5"
	var d: Dictionary = PgnFenScript.load_text(pgn3)
	if not bool(d.get("ok", false)):
		push_error("pgn3 load fail: %s" % d.get("error", ""))
		failed += 1
	else:
		var hist3: PackedStringArray = d.get("uci_history", PackedStringArray())
		if hist3.size() != 5:
			push_error("pgn3 hist size %d" % hist3.size())
			failed += 1

	if failed == 0:
		print("PgnFen OK")
		quit(0)
	else:
		print("PgnFen FAILED %d" % failed)
		quit(1)
