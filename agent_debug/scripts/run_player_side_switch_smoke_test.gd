extends SceneTree

## Headless smoke: switching player side triggers a clean restart and doesn't break input mapping.

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")

var _failed := 0


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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Keep deterministic: opponent OFF.
	EngineSettings.save_bool("cpu", "enabled", false)
	EngineSettings.save_int("opponent", "mode", 0)
	EngineSettings.save_int("player", "side", 0) # start as white

	await process_frame
	var board := load("res://main.tscn").instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in 3:
		await process_frame

	expect(board._player_side != null, "PlayerSide exists")
	expect(board._player_side.item_count == 2, "PlayerSide has 2 options")
	expect(_count_pieces(board.automation_state()) == 32, "initial pieces=32")

	# Make a move e2->e4 to ensure state changes.
	board.automation_click_square(Vector2i(4, 1))
	board.automation_click_square(Vector2i(4, 3))
	await process_frame
	expect(_count_pieces(board.automation_state()) == 32, "after one move pieces=32")

	# Switch to BLACK; main.gd should restart game.
	board._player_side.select(1)
	board._on_player_side_selected(1)
	for _i in 2:
		await process_frame
	expect(_count_pieces(board.automation_state()) == 32, "after side switch pieces reset to 32")

	# Smoke: click mapping should still roundtrip for a known square.
	var e2 := Vector2i(4, 1)
	var local_c: Vector2 = board.automation_square_to_local_center(e2)
	var mapped: Vector2i = board._screen_to_square(local_c)
	expect(mapped == e2, "roundtrip square mapping after flip, got %s" % mapped)

	_finish()


func _finish() -> void:
	if _failed > 0:
		push_error("Player side switch smoke: %d failed" % _failed)
		quit(1)
	else:
		print("Player side switch smoke: all passed")
		quit(0)

