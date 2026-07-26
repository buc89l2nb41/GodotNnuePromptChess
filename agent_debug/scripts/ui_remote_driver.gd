extends SceneTree

## UI Remote Driver (local TCP)
##
## 목적:
## - Godot이 현재 창 위치/크기와 클릭 타겟(버튼/보드 칸 중심)의 "화면 좌표"를 Python에 제공
## - Python은 pyautogui로 "진짜 마우스 클릭"을 수행
## - 캡처는 Godot 뷰포트 기준으로 저장(스크린샷은 deterministic)
##
## 실행 예:
##   Godot_console.exe --path "<chess>" -s "res://agent_debug/scripts/begin_capture_session.gd"
##   Godot_console.exe --path "<chess>" -s "res://agent_debug/scripts/ui_remote_driver.gd"
##
## 프로토콜(1줄 JSON):
## - {"cmd":"hello"} -> {"ok":true,"port":<port>,"pid":<pid>}
## - {"cmd":"targets"} -> {"ok":true,"window":{...},"targets":{name:{x,y}}, ...}
## - {"cmd":"calib_points"} -> {"ok":true,"p1":{x,y},"p2":{x,y}}
## - {"cmd":"mouse_pos"} -> {"ok":true,"x":<screen_x>,"y":<screen_y>}
## - {"cmd":"capture","name":"foo"} -> {"ok":true,"path":"<abs png>"}
## - {"cmd":"quit"} -> {"ok":true}

const ARTIFACT_DIR := "res://agent_debug/artifacts"
const SESSIONS_DIR := "res://agent_debug/artifacts/sessions"
const LATEST_TXT := "res://agent_debug/artifacts/latest_capture.txt"

var _server := TCPServer.new()
var _peer: StreamPeerTCP

var _board: Control
var _win: Window

const ChessState := preload("res://scripts/chess_state.gd")


func _timestamp_tag() -> String:
	var dt := Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(dt.year), int(dt.month), int(dt.day),
		int(dt.hour), int(dt.minute), int(dt.second),
		int(Time.get_ticks_msec() % 1000)
	]


func _read_latest_session_rel() -> String:
	var latest_abs := ProjectSettings.globalize_path(LATEST_TXT)
	if not FileAccess.file_exists(latest_abs):
		return ""
	var s := FileAccess.get_file_as_string(latest_abs).strip_edges()
	return s.split("\n", false)[0] if not s.is_empty() else ""


func _ensure_session_dir_abs() -> String:
	var rel := _read_latest_session_rel()
	if rel.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SESSIONS_DIR))
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


func _json_send(obj: Variant) -> void:
	if _peer == null:
		return
	var s := JSON.stringify(obj) + "\n"
	_peer.put_data(s.to_utf8_buffer())


func _get_window_rect() -> Dictionary:
	var pos := DisplayServer.window_get_position()
	var size := DisplayServer.window_get_size()
	var scale := DisplayServer.screen_get_scale()
	return {
		"x": int(pos.x),
		"y": int(pos.y),
		"w": int(size.x),
		"h": int(size.y),
		"scale": float(scale),
	}


func _calib_points() -> Dictionary:
	# Two far-apart points in screen coordinates for calibration.
	# Use board squares (stable, canvas-transformed).
	var p1 := _screen_pt_from_board_square_center(Vector2i(0, 0)) # a1
	var p2 := _screen_pt_from_board_square_center(Vector2i(7, 7)) # h8
	return {"ok": true, "p1": {"x": int(p1.x), "y": int(p1.y)}, "p2": {"x": int(p2.x), "y": int(p2.y)}}


func _mouse_pos() -> Dictionary:
	var p := DisplayServer.mouse_get_position()
	return {"ok": true, "x": int(p.x), "y": int(p.y)}


func _screen_pt_from_control_center(n: Control) -> Vector2:
	# Main window / board host: `get_screen_position()` is wrong for this SceneTree root layout
	# (reports canvas-like coords); keep the stable window_pos + canvas_rect mapping.
	var r: Rect2 = n.get_global_rect()
	var canvas_pt: Vector2 = r.position + r.size * 0.5
	var wp := DisplayServer.window_get_position()
	return Vector2(wp.x + canvas_pt.x, wp.y + canvas_pt.y)


func _screen_pt_from_popup_control_center(popup: Window, n: Control) -> Vector2:
	var r: Rect2 = n.get_global_rect()
	var c: Vector2 = r.position + r.size * 0.5
	var wp := Vector2(DisplayServer.window_get_position())
	if popup.is_embedded():
		# Child rects are in popup-local content space; offset by embedded Window origin.
		return wp + Vector2(popup.position) + c
	var wid: int = popup.get_window_id()
	var origin := Vector2(DisplayServer.window_get_position(wid))
	return origin + c


func _screen_pt_from_board_square_center(sq: Vector2i) -> Vector2:
	var local_center: Vector2 = _board.automation_square_to_local_center(sq)
	var xf: Transform2D = _board.get_global_transform_with_canvas()
	var canvas_pt: Vector2 = xf * local_center
	var wp := DisplayServer.window_get_position()
	return Vector2(wp.x + canvas_pt.x, wp.y + canvas_pt.y)


func _targets_snapshot() -> Dictionary:
	var t := {}
	# A stable "safe click" point intended to be outside popups/board,
	# used by real-click automation to close non-exclusive popups without triggering UI actions.
	var wp := DisplayServer.window_get_position()
	t["outside_popup"] = {"x": int(wp.x + 8), "y": int(wp.y + 8)}
	# Top bar buttons
	var edit_btn := _board.get_node_or_null("VBox/Bar/EditButton") as Control
	if edit_btn:
		var p := _screen_pt_from_control_center(edit_btn)
		t["edit_button"] = {"x": int(p.x), "y": int(p.y)}

	# If editor popup exists, include frequently used controls by text.
	var popup := _board.get_node_or_null("EditorPopup") as PopupPanel
	if popup:
		t["_popup_visible"] = popup.visible
		if popup.visible:
			# Debug: popup rect in screen coordinates.
			# Coordinate system for popup children:
			# - `popup.position` is popup-local offset within the main Window.
			# - `n.get_global_rect()` for controls under the popup is in popup-local coordinates.
			# - So "screen point" = window_pos + popup_pos + control_local_point.
			var wp2 := DisplayServer.window_get_position()
			t["_popup_rect"] = {
				"x": int(wp2.x + popup.position.x),
				"y": int(wp2.y + popup.position.y),
				"w": int(popup.size.x),
				"h": int(popup.size.y),
			}
			# Buttons created programmatically; find by text each time (small tree).
			var names := ["클리어", "시작 포지션", "적용", "취소", "복사", "불러오기", "지움", "wK", "wB", "wN", "bK"]
			for label in names:
				var b := _find_first_button_by_text(popup, label)
				if b:
					var bp := _screen_pt_from_popup_control_center(popup, b)
					t["btn_%s" % label] = {"x": int(bp.x), "y": int(bp.y)}
					# ASCII aliases for Python scripts (avoid locale/encoding issues).
					match label:
						"클리어":
							t["btn_clear"] = {"x": int(bp.x), "y": int(bp.y)}
						"시작 포지션":
							t["btn_startpos"] = {"x": int(bp.x), "y": int(bp.y)}
						"적용":
							t["btn_apply"] = {"x": int(bp.x), "y": int(bp.y)}
						"취소":
							t["btn_cancel"] = {"x": int(bp.x), "y": int(bp.y)}
						"복사":
							t["btn_copy"] = {"x": int(bp.x), "y": int(bp.y)}
						"불러오기":
							t["btn_load"] = {"x": int(bp.x), "y": int(bp.y)}
						"지움":
							t["btn_erase"] = {"x": int(bp.x), "y": int(bp.y)}
						_:
							pass
			# FEN input field (first LineEdit).
			var fen := _find_first_line_edit(popup)
			if fen:
				var fp := _screen_pt_from_popup_control_center(popup, fen)
				t["fen_input"] = {"x": int(fp.x), "y": int(fp.y)}
			# Diagnostics: expose all button texts currently in popup.
			var all_texts: PackedStringArray = PackedStringArray()
			_collect_button_texts(popup, all_texts)
			t["_popup_button_texts"] = all_texts
			# Popup local rect in screen coords (for calibration / debugging).
			# (PopupPanel is not a Control in this project environment; skip rect introspection.)

	# Common squares (for scripted flows)
	var squares := {
		"e8": Vector2i(4, 7),
		"e1": Vector2i(4, 0),
		"c4": Vector2i(2, 3),
		"g1": Vector2i(6, 0),
		"f3": Vector2i(5, 2),
	}
	for k in squares.keys():
		var pt := _screen_pt_from_board_square_center(squares[k])
		t["sq_%s" % String(k)] = {"x": int(pt.x), "y": int(pt.y)}
	return t


func _find_first_button_by_text(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for c in root.get_children():
		var b := _find_first_button_by_text(c, text)
		if b != null:
			return b
	return null


func _collect_button_texts(root: Node, out: PackedStringArray) -> void:
	if root is Button:
		out.append((root as Button).text)
	for c in root.get_children():
		_collect_button_texts(c, out)


func _find_first_line_edit(root: Node) -> LineEdit:
	if root is LineEdit:
		return root as LineEdit
	for c in root.get_children():
		var le := _find_first_line_edit(c)
		if le != null:
			return le
	return null


func _capture_png(name: String) -> Dictionary:
	# Avoid waiting on frame_post_draw which can stall under some window/modal states.
	for _i in 2:
		await process_frame
	var vp := root as Viewport
	var tex: ViewportTexture = vp.get_texture()
	var img: Image = tex.get_image()
	var session_abs := _ensure_session_dir_abs()
	var out_path := session_abs.path_join("%s_%s.png" % [name, _timestamp_tag()])
	var err := img.save_png(out_path)
	return {"ok": err == OK, "path": out_path, "err": int(err)}


func _ready_scene() -> void:
	_win = root as Window
	if _win:
		_win.size = Vector2i(900, 960)
		# Embed PopupPanel instances into this root window so control rects share one canvas
		# space with the top bar (OS-level real-click automation matches `wp + get_global_rect()`).
		_win.gui_embed_subwindows = true
	_board = load("res://main.tscn").instantiate() as Control
	root.add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in 8:
		await process_frame


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _ready_scene()

	# Bind ephemeral local port (0) on loopback.
	var err := _server.listen(0, "127.0.0.1")
	if err != OK:
		push_error("remote-driver: listen failed %s" % err)
		quit(1)
		return
	print("REMOTE_READY port=%d" % _server.get_local_port())

	while true:
		if _peer == null:
			if _server.is_connection_available():
				_peer = _server.take_connection()
				_peer.set_no_delay(true)
				# Do not send unsolicited data; client will request via {"cmd":"hello"}.
		else:
			if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peer = null
			else:
				var avail := _peer.get_available_bytes()
				if avail > 0:
					var data_bytes: PackedByteArray = _peer.get_data(avail)[1]
					var s_in: String = data_bytes.get_string_from_utf8()
					for line in s_in.split("\n", false):
						var msg: String = line.strip_edges()
						if msg.is_empty():
							continue
						var parsed_v: Variant = JSON.parse_string(msg)
						if parsed_v == null or typeof(parsed_v) != TYPE_DICTIONARY:
							_json_send({"ok": false, "error": "invalid json"})
							continue
						var parsed: Dictionary = parsed_v
						var cmd: String = String(parsed.get("cmd", ""))
						match cmd:
							"hello":
								_json_send({"ok": true, "port": int(_server.get_local_port()), "pid": int(OS.get_process_id())})
							"targets":
								_json_send({"ok": true, "window": _get_window_rect(), "targets": _targets_snapshot()})
							"calib_points":
								_json_send(_calib_points())
							"mouse_pos":
								_json_send(_mouse_pos())
							"set_fen":
								var fen: String = String(parsed.get("fen", ""))
								var st: ChessState = _board.automation_state()
								var res := st.load_fen(fen)
								_board.queue_redraw()
								_json_send({"ok": bool(res.get("ok", false)), "error": String(res.get("error", ""))})
							"capture":
								var nm := String(parsed.get("name", "capture"))
								var r := await _capture_png(nm)
								_json_send(r)
							"quit":
								_json_send({"ok": true})
								quit(0)
								return
							_:
								_json_send({"ok": false, "error": "unknown cmd"})
		await process_frame

