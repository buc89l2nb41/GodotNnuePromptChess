extends SceneTree

# Headless smoke: prove "CPU mode" works without Python by running a short
# engine-driven sequence using direct UCI execution.

const ChessState := preload("res://scripts/chess_state.gd")
const UciMoves := preload("res://scripts/uci/uci_moves.gd")
const EngineSettings := preload("res://scripts/engine/engine_settings.gd")
const UciEngineController := preload("res://scripts/engine/uci_engine_controller.gd")

var _failed := 0


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		push_error("EXPECT: " + msg)


func _init() -> void:
	call_deferred("_run")


func _apply_uci_to_state(st: ChessState, uci: String) -> bool:
	var parsed := UciMoves.parse_uci_move(uci)
	if not bool(parsed.get("ok", false)):
		return false
	var promo_piece := ChessState.W_QUEEN
	var promo := String(parsed.get("promo", ""))
	if not promo.is_empty():
		var w := st.white_to_move
		match promo:
			"q":
				promo_piece = ChessState.W_QUEEN if w else ChessState.B_QUEEN
			"r":
				promo_piece = ChessState.W_ROOK if w else ChessState.B_ROOK
			"b":
				promo_piece = ChessState.W_BISHOP if w else ChessState.B_BISHOP
			"n":
				promo_piece = ChessState.W_KNIGHT if w else ChessState.B_KNIGHT
	return st.make_move(parsed.from, parsed.to, promo_piece)


func _run() -> void:
	# Resolve engine path first.
	var engine_exe := EngineSettings.find_default_engine_path()
	expect(not engine_exe.is_empty(), "engine exists at default relative path")
	expect(engine_exe.is_empty() or FileAccess.file_exists(engine_exe), "engine exists: %s" % engine_exe)
	if engine_exe.is_empty() or not FileAccess.file_exists(engine_exe):
		_finish()
		return

	var engine := UciEngineController.new()
	var last_err := ""
	var received: Array[String] = []
	engine.error.connect(func(msg: String) -> void:
		last_err = msg
	)
	engine.bestmove_received.connect(func(m: String) -> void:
		received.append(m)
	)
	engine.start(engine_exe)
	# Persistent UCI init is async; poll until ready.
	var ready_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < ready_deadline and not engine.is_ready() and last_err.is_empty():
		engine.poll()
		await process_frame
	expect(engine.is_ready(), "engine ready")
	if not engine.is_ready():
		expect(false, "engine not ready: %s" % last_err)
		engine.stop()
		_finish()
		return

	# "Minimum 1 game" is a human-level requirement; for automation we prove
	# the loop works by playing N plies legally.
	var st := ChessState.new()
	var plies := 16
	for _i in range(plies):
		var prev_n := received.size()
		engine.request_bestmove_from_fen(st.fen(), 80)

		var deadline := Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < deadline and received.size() == prev_n and last_err.is_empty():
			engine.poll()
			await process_frame

		expect(last_err.is_empty(), "no engine error during game: %s" % last_err)
		if not last_err.is_empty():
			break
		expect(received.size() > prev_n, "got bestmove ply %d" % (_i + 1))
		if received.size() <= prev_n:
			break
		var move := String(received[-1])
		expect(move.length() >= 4, "bestmove looks valid: %s" % move)
		expect(_apply_uci_to_state(st, move), "move applied legally: %s" % move)
		if st.result_string() != "":
			# Game ended early, that's still a valid "game works" signal.
			break

	engine.stop()
	_finish()


func _finish() -> void:
	if _failed > 0:
		push_error("Direct CPU game smoke: %d failed" % _failed)
		quit(1)
	else:
		print("Direct CPU game smoke: all passed")
		quit(0)

