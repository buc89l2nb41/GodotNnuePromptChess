extends SceneTree

## Agent: 뷰포트 캡처 → agent_debug/artifacts/ 에 PNG 저장.
## 실행: Godot --path chess -s res://agent_debug/scripts/capture_screenshot.gd

const ARTIFACT_DIR := "res://agent_debug/artifacts"
const SESSIONS_DIR := "res://agent_debug/artifacts/sessions"
const LATEST_TXT := "res://agent_debug/artifacts/latest_capture.txt"

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")
const UciMoves := preload("res://scripts/uci/uci_moves.gd")


func _timestamp_tag() -> String:
	var dt := Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(dt.year), int(dt.month), int(dt.day),
		int(dt.hour), int(dt.minute), int(dt.second),
		int(Time.get_ticks_msec() % 1000)
	]


func _sanitize_name(s: String) -> String:
	var out := ""
	for ch in s:
		var c := String(ch)
		var ok := (
			(c >= "a" and c <= "z")
			or (c >= "A" and c <= "Z")
			or (c >= "0" and c <= "9")
			or c == "_"
			or c == "-"
		)
		out += c if ok else "_"
	out = out.strip_edges()
	return out if not out.is_empty() else "capture"


func _parse_capture_args() -> Dictionary:
	# Use args after "--" when running: Godot ... -s script.gd -- --name=... --player_side=...
	var args := OS.get_cmdline_user_args()
	var name := "capture"
	var player_side := "keep" # keep|white|black
	var press_paths: PackedStringArray = PackedStringArray()
	var extra_wait_frames := 0
	var uci_line := ""
	var fen_line := ""
	# get_cmdline_user_args() returns args after "--" verbatim.
	for j in range(args.size()):
		var a := String(args[j])
		if a.begins_with("--name="):
			name = a.substr("--name=".length())
		elif a.begins_with("--player_side="):
			player_side = a.substr("--player_side=".length()).to_lower()
		elif a.begins_with("--press="):
			press_paths.append(a.substr("--press=".length()))
		elif a.begins_with("--wait_frames="):
			extra_wait_frames = maxi(0, int(a.substr("--wait_frames=".length())))
		elif a.begins_with("--uci="):
			uci_line = a.substr("--uci=".length())
		elif a.begins_with("--fen="):
			fen_line = a.substr("--fen=".length())
	return {
		"name": _sanitize_name(name),
		"player_side": player_side,
		"press_paths": press_paths,
		"extra_wait_frames": extra_wait_frames,
		"uci": uci_line,
		"fen": fen_line,
	}


func _read_latest_session_rel() -> String:
	var latest_abs := ProjectSettings.globalize_path(LATEST_TXT)
	if not FileAccess.file_exists(latest_abs):
		return ""
	var s := FileAccess.get_file_as_string(latest_abs).strip_edges()
	# Expect one-line "sessions/<id>".
	return s.split("\n", false)[0] if not s.is_empty() else ""


func _ensure_session_dir_abs() -> String:
	var rel := _read_latest_session_rel()
	if rel.is_empty():
		# Fallback: create a session lazily.
		var sessions_abs := ProjectSettings.globalize_path(SESSIONS_DIR)
		DirAccess.make_dir_recursive_absolute(sessions_abs)
		rel = "sessions/%s" % _timestamp_tag()
		var latest_abs := ProjectSettings.globalize_path(LATEST_TXT)
		var f := FileAccess.open(latest_abs, FileAccess.WRITE)
		if f:
			f.store_string(rel + "\n")
			f.close()
	var base_abs := ProjectSettings.globalize_path(ARTIFACT_DIR)
	var session_abs := base_abs.path_join(rel)
	DirAccess.make_dir_recursive_absolute(session_abs)
	return session_abs


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg := _parse_capture_args()
	var player_side := String(cfg.get("player_side", "keep"))
	if player_side == "white":
		EngineSettings.save_int("player", "side", 0)
	elif player_side == "black":
		EngineSettings.save_int("player", "side", 1)

	await process_frame
	var win := root as Window
	if win:
		win.size = Vector2i(900, 960)
	var board := load("res://main.tscn").instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in 4:
		await process_frame

	# Optional UI actions before capture (e.g. open popups).
	var press_paths: PackedStringArray = cfg.get("press_paths", PackedStringArray())
	for p in press_paths:
		var n := board.get_node_or_null(String(p))
		if n == null:
			push_error("capture: node not found for --press: %s" % String(p))
			continue
		if n is BaseButton:
			(n as BaseButton).pressed.emit()
		else:
			push_error("capture: node is not BaseButton for --press: %s" % String(p))
		for _j in 2:
			await process_frame

	# Optional position setup via FEN (applies directly to the underlying ChessState).
	var fen_line: String = String(cfg.get("fen", "")).strip_edges()
	if not fen_line.is_empty():
		var st: ChessState = board.automation_state()
		var res := st.load_fen(fen_line)
		if not bool(res.get("ok", false)):
			push_error("capture: invalid fen in --fen: %s" % String(res.get("error", "unknown error")))
		board.queue_redraw()
		for _f in 2:
			await process_frame

	# Optional scripted moves via UCI sequence (space-separated, e.g. "e2e4 e7e5 ...").
	var uci_line: String = String(cfg.get("uci", "")).strip_edges()
	if not uci_line.is_empty():
		var tokens := uci_line.split(" ", false)
		for t in tokens:
			var uci := String(t).strip_edges()
			if uci.is_empty():
				continue
			var parsed := UciMoves.parse_uci_move(uci)
			if not bool(parsed.get("ok", false)):
				push_error("capture: invalid uci in --uci: %s" % uci)
				continue
			var from_sq: Vector2i = parsed.get("from", Vector2i(-1, -1))
			var to_sq: Vector2i = parsed.get("to", Vector2i(-1, -1))
			if from_sq.x < 0 or to_sq.x < 0:
				push_error("capture: invalid squares in --uci: %s" % uci)
				continue
			# Drive the UI via built-in automation helpers (respects board flip).
			board.automation_click_square(from_sq)
			board.automation_click_square(to_sq)
			for _m in 2:
				await process_frame
			# Promotion is resolved via popup; default to queen for automation.
			var promo := String(parsed.get("promo", ""))
			if not promo.is_empty():
				board.automation_promote_queen()
				for _n in 2:
					await process_frame

	var extra_wait_frames: int = int(cfg.get("extra_wait_frames", 0))
	for _k in range(extra_wait_frames):
		await process_frame
	await RenderingServer.frame_post_draw
	var vp := root as Viewport
	if vp == null:
		push_error("capture: root is not Viewport")
		quit(1)
		return
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		push_error("capture: viewport texture null")
		quit(1)
		return
	var img: Image = tex.get_image()
	if img == null:
		push_error("capture: get_image() null")
		quit(1)
		return
	var session_abs := _ensure_session_dir_abs()
	var name := String(cfg.get("name", "capture"))
	var out_path: String = session_abs.path_join("%s_%s.png" % [name, _timestamp_tag()])
	var err := img.save_png(out_path)
	if err != OK:
		push_error("capture: save_png failed %s" % err)
		quit(1)
		return
	print("capture: saved ", out_path)
	quit(0)
