extends SceneTree

## Real-agent chat capture (real game window, real Stockfish, real sidecar + LLM).
##
## Sends one chat message as the user would, waits until the chat panel shows
## one of the --until markers, then saves a PNG and prints the chat panel and
## the [GATE] lines. Needs a CURSOR_API_KEY in ai_sidecar/.env.
##
##   Godot --path . -s res://agent_debug/scripts/capture_agent_chat.gd -- \
##     "--say=시실리안 나이도프로 둬주고 나에게 수를 추천해줘" \
##     "--until=추천 수:" --out=res://docs/images/agent_recommend.png
##
## Your saved opponent mode / player side are restored afterwards.

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")


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
	var say := _arg("say", "")
	var until := _arg("until", "추천 수:|게이트 통과|포기했습니다").split("|", false)
	var out := _arg("out", "res://docs/images/agent_chat.png")
	var timeout_s := int(_arg("timeout", "180"))
	OS.set_environment("AI_SIDECAR_INJECT_UCI", "")

	var prev_mode := EngineSettings.load_int("opponent", "mode", 0)
	var prev_side := EngineSettings.load_int("player", "side", 0)
	EngineSettings.save_int("opponent", "mode", 2) # AI
	EngineSettings.save_int("player", "side", 0)
	EngineSettings.save_string("ai", "opening_name", "")

	var win := root as Window
	if win:
		win.size = Vector2i(1280, 860)
	var board := load("res://main.tscn").instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ok := await _wait_until(func() -> bool:
		return bool(board.get("_ai_sidecar_ready")) and board.get("_engine") != null and board.get("_engine").is_ready(), 40000)
	if not ok:
		push_error("agent chat: sidecar/engine not ready")
		_finish(board, prev_mode, prev_side, 1)
		return

	var chat: RichTextLabel = board.get("_chat_log")
	var input: TextEdit = board.get("_chat_input")
	var t0 := Time.get_ticks_msec()
	input.text = say
	board.call("_on_chat_send")
	print("agent chat: sent '%s'" % say)
	ok = await _wait_until(func() -> bool:
		var txt := chat.get_parsed_text()
		for m in until:
			if txt.find(m) >= 0:
				return true
		return false, timeout_s * 1000)
	var elapsed := Time.get_ticks_msec() - t0
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = (root as Viewport).get_texture().get_image()
	var out_abs := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())
	img.save_png(out_abs)
	print("agent chat: %s after %d ms, saved %s" % ["done" if ok else "TIMEOUT", elapsed, out_abs])
	print("agent chat: board fen = %s" % (board.automation_state() as ChessState).fen())
	print("agent chat: chat panel text ↓\n" + chat.get_parsed_text())
	_finish(board, prev_mode, prev_side, 0 if ok else 1)


func _finish(board: Node, prev_mode: int, prev_side: int, code: int) -> void:
	EngineSettings.save_int("opponent", "mode", prev_mode)
	EngineSettings.save_int("player", "side", prev_side)
	var proc = board.get("_ai_proc")
	if proc != null and proc.has_method("free_port"):
		proc.free_port()
	quit(code)
