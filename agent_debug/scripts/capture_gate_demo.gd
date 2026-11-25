extends SceneTree

## Gate demo capture (real game window, real Stockfish, real sidecar).
##
## Starts the game in "상대: AI" mode with AI_SIDECAR_INJECT_UCI set, so the
## sidecar treats that UCI as the model's answer. The player (white) plays
## e2e4; the AI (black) "proposes" the injected move, the candidate gate
## replaces it with a Stockfish MultiPV candidate, and the chat panel shows
## the replacement. Saves a PNG and prints the [GATE] log lines.
##
## Needs: engine/stockfish/stockfish.exe, Python with ai_sidecar requirements.
## No API key needed (the injected answer stands in for the model).
##
##   Godot --path . -s res://agent_debug/scripts/capture_gate_demo.gd -- --inject=e8e1 --out=res://docs/images/gate_demo_ingame.png
##
## Your saved opponent mode / player side are restored afterwards.

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")
const UciMoves := preload("res://scripts/uci/uci_moves.gd")


func _init() -> void:
	call_deferred("_run")


func _arg(name: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--%s=" % name):
			return String(a).substr(name.length() + 3)
	return default


func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return false


func _run() -> void:
	var inject := _arg("inject", "e8e1")
	var human := _arg("human", "e2e4")
	var out := _arg("out", "res://docs/images/gate_demo_ingame.png")

	var prev_mode := EngineSettings.load_int("opponent", "mode", 0)
	var prev_side := EngineSettings.load_int("player", "side", 0)
	EngineSettings.save_int("opponent", "mode", 2) # AI
	EngineSettings.save_int("player", "side", 0) # player = white, AI = black
	# Inherited by the sidecar process Godot starts.
	OS.set_environment("AI_SIDECAR_INJECT_UCI", inject)
	print("gate demo: inject=%s human=%s" % [inject, human])

	var win := root as Window
	if win:
		win.size = Vector2i(1280, 860)
	var board := load("res://main.tscn").instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ok := await _wait_until(func() -> bool:
		return bool(board.get("_ai_sidecar_ready")) and board.get("_engine") != null and board.get("_engine").is_ready(), 40000)
	if not ok:
		push_error("gate demo: sidecar/engine not ready (status=%s)" % str(board.get("_engine_status").text))
		_finish(board, prev_mode, prev_side, 1)
		return

	var parsed := UciMoves.parse_uci_move(human)
	board.automation_click_square(parsed.from)
	board.automation_click_square(parsed.to)
	var st: ChessState = board.automation_state()
	ok = await _wait_until(func() -> bool: return st.white_to_move and st.fullmove_number >= 2, 40000)
	if not ok:
		push_error("gate demo: AI did not move in time")
		_finish(board, prev_mode, prev_side, 1)
		return
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = (root as Viewport).get_texture().get_image()
	var out_abs := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())
	var err := img.save_png(out_abs)
	print("gate demo: saved %s (err=%d)" % [out_abs, err])
	print("gate demo: fen after AI move = %s" % st.fen())
	var chat: RichTextLabel = board.get("_chat_log")
	if chat != null:
		print("gate demo: chat panel text ↓\n" + chat.get_parsed_text())
	_finish(board, prev_mode, prev_side, 0 if err == OK else 1)


func _finish(board: Node, prev_mode: int, prev_side: int, code: int) -> void:
	EngineSettings.save_int("opponent", "mode", prev_mode)
	EngineSettings.save_int("player", "side", prev_side)
	var proc = board.get("_ai_proc")
	if proc != null and proc.has_method("free_port"):
		proc.free_port()
	quit(code)
