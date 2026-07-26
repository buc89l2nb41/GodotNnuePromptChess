extends SceneTree

## Agent/CI: main.tscn UI 클릭 시뮬레이션. 실행: Godot --path chess -s res://agent_debug/scripts/run_ui_chess_tests.gd

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")

var _failed := 0


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		push_error("UIEXPECT: " + msg)


func _count_pieces(s: ChessState) -> int:
	var n := 0
	for i in 64:
		if s.board[i] != ChessState.NONE:
			n += 1
	return n


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Make UI tests deterministic: ensure opponent is OFF regardless of previous user settings.
	EngineSettings.save_bool("cpu", "enabled", false)
	EngineSettings.save_int("opponent", "mode", 0)

	await process_frame
	var win := root as Window
	if win:
		win.size = Vector2i(900, 960)
	var board := load("res://main.tscn").instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame

	var e2 := Vector2i(4, 1)
	var local_c: Vector2 = board.automation_square_to_local_center(e2)
	var mapped: Vector2i = board._screen_to_square(local_c)
	expect(mapped == e2, "roundtrip e2 center -> square, got %s" % mapped)

	var st: ChessState = board.automation_state()
	expect(st.piece_at(4, 1) == ChessState.W_PAWN, "e2 pawn before move")
	board.automation_click_square(e2)
	board.automation_click_square(Vector2i(4, 3))
	st = board.automation_state()
	expect(not st.white_to_move, "black to move after e4")
	expect(st.piece_at(4, 3) == ChessState.W_PAWN, "pawn on e4")
	expect(board.automation_turn_label_text().contains("흑"), "라벨에 흑 차례")

	board._undo_btn.pressed.emit()
	await process_frame
	st = board.automation_state()
	expect(st.white_to_move, "undo: back to white to move")
	expect(st.piece_at(4, 1) == ChessState.W_PAWN, "undo: pawn back on e2")
	expect(st.piece_at(4, 3) == ChessState.NONE, "undo: e4 empty")

	board.automation_click_square(Vector2i(1, 7))
	board.automation_click_square(Vector2i(2, 5))
	expect(board.automation_state().white_to_move, "white after Nc6")

	board._reset_btn.pressed.emit()
	await process_frame
	expect(_count_pieces(board.automation_state()) == 32, "reset 32 pieces")
	board.automation_click_square(Vector2i(4, 1))
	board.automation_click_square(Vector2i(4, 3))
	board.automation_click_square(Vector2i(1, 7))
	board.automation_click_square(Vector2i(2, 5))
	board.automation_click_square(Vector2i(4, 3))
	board.automation_click_square(Vector2i(4, 4))
	board.automation_click_square(Vector2i(3, 6))
	board.automation_click_square(Vector2i(3, 4))
	board.automation_click_square(Vector2i(4, 4))
	board.automation_click_square(Vector2i(3, 5))
	st = board.automation_state()
	expect(st.piece_at(3, 5) == ChessState.W_PAWN, "ep: white on d6")
	expect(st.piece_at(3, 4) == ChessState.NONE, "ep: d5 empty")

	board._undo_btn.pressed.emit()
	await process_frame
	st = board.automation_state()
	expect(st.white_to_move, "undo ep: white to move")
	expect(st.piece_at(4, 4) == ChessState.W_PAWN, "undo ep: pawn back on e5")
	expect(st.piece_at(3, 4) == ChessState.B_PAWN, "undo ep: black pawn back on d5")
	expect(st.ep_square == Vector2i(3, 5), "undo ep: ep_square restored to d6")

	# Promotion undo (force a simple promotion position).
	board._reset_btn.pressed.emit()
	await process_frame
	st = board.automation_state()
	for i in 64:
		st.board[i] = ChessState.NONE
	st.board[ChessState.idx(4, 0)] = ChessState.W_KING
	st.board[ChessState.idx(4, 7)] = ChessState.B_KING
	st.board[ChessState.idx(0, 6)] = ChessState.W_PAWN # a7
	st.white_to_move = true
	st.castling = 0
	st.ep_square = Vector2i(-1, -1)
	st.halfmove_clock = 0
	st.fullmove_number = 1
	board.queue_redraw()
	await process_frame
	board.automation_click_square(Vector2i(0, 6))
	board.automation_click_square(Vector2i(0, 7))
	await process_frame
	board.automation_promote_queen()
	await process_frame
	st = board.automation_state()
	expect(st.piece_at(0, 7) == ChessState.W_QUEEN, "promo: queen on a8")
	board._undo_btn.pressed.emit()
	await process_frame
	st = board.automation_state()
	expect(st.piece_at(0, 6) == ChessState.W_PAWN, "undo promo: pawn back on a7")
	expect(st.piece_at(0, 7) == ChessState.NONE, "undo promo: a8 empty")

	if _failed > 0:
		push_error("UI chess tests: %d failed" % _failed)
		quit(1)
	else:
		print("UI chess tests: all passed")
		quit(0)
