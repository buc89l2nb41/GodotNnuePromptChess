extends SceneTree

## Agent/CI: 규칙 엔진(ChessState) 단위 테스트. 실행: Godot --path chess -s res://agent_debug/scripts/run_chess_tests.gd

var _failed := 0


func _init() -> void:
	_test_start_position()
	_test_fen_start_position()
	_test_fen_after_e2e4()
	_test_load_fen_roundtrip()
	_test_pawn_double_and_ep()
	_test_en_passant_capture()
	_test_illegal_move_rejected()
	_test_castle_kingside_white()
	_test_cannot_move_into_check()
	_test_fools_mate()
	_test_multipv_parsing()
	_test_main_scene_loads()
	if _failed > 0:
		push_error("Chess tests: %d failed" % _failed)
		quit(1)
	else:
		print("Chess tests: all passed")
		quit(0)


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		push_error("EXPECT: " + msg)


func _count_pieces(s: ChessState) -> int:
	var n := 0
	for i in 64:
		if s.board[i] != ChessState.NONE:
			n += 1
	return n


func _has_move(moves: Array, to: Vector2i) -> bool:
	for m in moves:
		if m == to:
			return true
	return false


func _test_start_position() -> void:
	var s := ChessState.new()
	expect(_count_pieces(s) == 32, "start should have 32 pieces")
	expect(s.piece_at(4, 0) == ChessState.W_KING, "e1 white king")
	expect(s.piece_at(4, 7) == ChessState.B_KING, "e8 black king")
	var e2 := Vector2i(4, 1)
	var leg := s.legal_moves_from(e2)
	expect(_has_move(leg, Vector2i(4, 2)), "pawn e2-e3")
	expect(_has_move(leg, Vector2i(4, 3)), "pawn e2-e4")


func _test_fen_start_position() -> void:
	var s := ChessState.new()
	var fen := s.fen()
	expect(fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "start fen mismatch: '%s'" % fen)


func _test_fen_after_e2e4() -> void:
	var s := ChessState.new()
	expect(s.make_move(Vector2i(4, 1), Vector2i(4, 3)), "e2-e4")
	var fen := s.fen()
	expect(fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "e2e4 fen mismatch: '%s'" % fen)


func _test_load_fen_roundtrip() -> void:
	var s := ChessState.new()
	expect(s.make_move(Vector2i(4, 1), Vector2i(4, 3)), "e4 for fen roundtrip")
	expect(s.make_move(Vector2i(1, 7), Vector2i(2, 5)), "Nc6 for fen roundtrip")
	var fen := s.fen()
	var t := ChessState.new()
	var res := t.load_fen(fen)
	expect(bool(res.get("ok", false)), "load_fen ok: %s" % String(res.get("error", "")))
	expect(t.fen() == fen, "load_fen roundtrip mismatch: '%s' vs '%s'" % [t.fen(), fen])


func _test_pawn_double_and_ep() -> void:
	var s := ChessState.new()
	expect(s.make_move(Vector2i(4, 1), Vector2i(4, 3)), "e2-e4")
	expect(not s.white_to_move, "black to move after e4")
	expect(s.ep_square == Vector2i(4, 2), "ep after e2-e4")


func _test_en_passant_capture() -> void:
	var s := ChessState.new()
	expect(s.make_move(Vector2i(4, 1), Vector2i(4, 3)), "e4")
	expect(s.make_move(Vector2i(1, 7), Vector2i(2, 5)), "Nc6")
	expect(s.make_move(Vector2i(4, 3), Vector2i(4, 4)), "e5")
	expect(s.make_move(Vector2i(3, 6), Vector2i(3, 4)), "d5")
	expect(s.ep_square == Vector2i(3, 5), "ep after d7-d5")
	expect(s.white_to_move, "white to capture ep")
	expect(s.make_move(Vector2i(4, 4), Vector2i(3, 5)), "exd6 ep")
	expect(s.piece_at(3, 4) == ChessState.NONE, "captured d-pawn gone")
	expect(s.piece_at(3, 5) == ChessState.W_PAWN, "white pawn on d6")


func _test_illegal_move_rejected() -> void:
	var s := ChessState.new()
	expect(not s.make_move(Vector2i(4, 1), Vector2i(4, 6)), "illegal pawn jump")


func _test_castle_kingside_white() -> void:
	var s := ChessState.new()
	s.board[ChessState.idx(5, 0)] = ChessState.NONE
	s.board[ChessState.idx(6, 0)] = ChessState.NONE
	var leg := s.legal_moves_from(Vector2i(4, 0))
	expect(_has_move(leg, Vector2i(6, 0)), "O-O available")
	expect(s.make_move(Vector2i(4, 0), Vector2i(6, 0)), "castle")
	expect(s.piece_at(6, 0) == ChessState.W_KING, "king g1")
	expect(s.piece_at(5, 0) == ChessState.W_ROOK, "rook f1")


func _test_cannot_move_into_check() -> void:
	var s := ChessState.new()
	s.board[ChessState.idx(4, 1)] = ChessState.NONE
	s.board[ChessState.idx(4, 2)] = ChessState.B_QUEEN
	var leg_k := s.legal_moves_from(Vector2i(4, 0))
	expect(not _has_move(leg_k, Vector2i(4, 1)), "king cannot step into e2 with queen on e3")


func _test_fools_mate() -> void:
	var s := ChessState.new()
	expect(s.make_move(Vector2i(5, 1), Vector2i(5, 2)), "f3")
	expect(s.make_move(Vector2i(4, 6), Vector2i(4, 4)), "e5")
	expect(s.make_move(Vector2i(6, 1), Vector2i(6, 3)), "g4")
	expect(s.make_move(Vector2i(3, 7), Vector2i(7, 3)), "Qh4#")
	var rs := s.result_string()
	expect(rs.contains("체크메이트"), "fool's mate: expected checkmate, got '%s'" % rs)


func _test_multipv_parsing() -> void:
	const UciMultipv := preload("res://scripts/engine/uci_multipv.gd")
	var line1 := "info depth 8 seldepth 12 multipv 1 score cp 34 nodes 1000 pv e2e4 e7e5 g1f3"
	var line2 := "info depth 8 seldepth 11 multipv 2 score cp 12 nodes 900 pv d2d4 d7d5"
	var line3 := "info depth 9 seldepth 12 multipv 1 score cp 40 nodes 2000 pv e2e4 e7e5"
	var line_mate := "info depth 5 multipv 3 score mate 3 pv g2g4"
	var c1 := UciMultipv.candidate_from_info_line(line1)
	expect(int(c1.get("rank", 0)) == 1, "multipv rank 1")
	expect(String(c1.get("uci", "")) == "e2e4", "pv first e2e4")
	expect(int(c1.get("score_cp", 0)) == 34, "score cp 34")
	var store: Dictionary = {}
	UciMultipv.merge_candidate(store, c1)
	UciMultipv.merge_candidate(store, UciMultipv.candidate_from_info_line(line2))
	UciMultipv.merge_candidate(store, UciMultipv.candidate_from_info_line(line3))
	UciMultipv.merge_candidate(store, UciMultipv.candidate_from_info_line(line_mate))
	var arr := UciMultipv.store_to_sorted_array(store)
	expect(arr.size() == 3, "3 unique candidates, got %d" % arr.size())
	expect(String(arr[0].get("uci", "")) == "e2e4", "rank1 uci after deeper merge")
	expect(int(arr[0].get("score_cp", 0)) == 40, "deeper depth wins for rank1")
	expect(String(arr[2].get("uci", "")) == "g2g4", "rank3 uci g2g4")
	expect(int(arr[2].get("mate", 0)) == 3, "mate score on rank3")
	var with_best := UciMultipv.ensure_bestmove_candidate(arr, "e2e4")
	expect(with_best.size() == 3, "ensure bestmove already present")
	var only_best := UciMultipv.ensure_bestmove_candidate([], "g1f3")
	expect(only_best.size() == 1 and String(only_best[0].get("uci", "")) == "g1f3", "bestmove alone")
	# Invalid pick fallback simulation: candidate_ucis membership
	var ucis := UciMultipv.candidate_ucis(arr)
	expect(ucis.has("e2e4"), "uci list has e2e4")
	expect(not ucis.has("a2a3"), "illegal a2a3 not in candidates")


func _test_main_scene_loads() -> void:
	var p := load("res://main.tscn") as PackedScene
	expect(p != null, "main.tscn should load")
	var root := p.instantiate()
	expect(root != null, "main.tscn should instantiate")
	root.free()
