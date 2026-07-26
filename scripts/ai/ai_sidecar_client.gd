extends RefCounted
class_name AiSidecarClient

signal session_ready(agent_id: String)
signal move_chosen(uci: String, reason: String, reply: String, fallback: bool)
signal chat_replied(reply: String, style_update: String, opening_name: String, book_lines: Array, board_fen: String)
signal request_failed(kind: String, message: String)

enum Kind { NONE, SESSION, MOVE, CHAT }

var base_url: String = "http://127.0.0.1:8765"
var agent_id: String = ""
var style_notes: String = ""
var opening_name: String = ""
var book_lines: Array = []
var last_ai_uci: String = ""
var last_ai_reason: String = ""

var _http: HTTPRequest
var _pending: int = Kind.NONE
var _busy: bool = false
var _queue: Array = []


func attach_http(http: HTTPRequest) -> void:
	_http = http
	if not _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.connect(_on_request_completed)


func is_busy() -> bool:
	return _busy


func ensure_session() -> void:
	if not agent_id.is_empty():
		session_ready.emit(agent_id)
		return
	_enqueue("/session", {"style_notes": style_notes}, Kind.SESSION)


func request_move(
	fen: String,
	side: String,
	candidates: Array,
	last_human_uci: String,
	history_uci: String = "",
	skill_level: int = 10
) -> void:
	var cand_json: Array = []
	for c in candidates:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		cand_json.append({
			"rank": int(c.get("rank", 1)),
			"uci": String(c.get("uci", "")),
			"score_cp": int(c.get("score_cp", 0)),
			"mate": int(c.get("mate", 0)),
			"depth": int(c.get("depth", 0)),
		})
	var body := {
		"fen": fen,
		"side": side,
		"candidates": cand_json,
		"style_notes": style_notes,
		"last_human_uci": last_human_uci,
		"history_uci": history_uci,
		"skill_level": clampi(skill_level, 0, 20),
		"book_lines": book_lines,
		"opening_name": opening_name,
		"agent_id": agent_id,
	}
	_enqueue("/move", body, Kind.MOVE)


func request_chat(fen: String, history_summary: String, message: String) -> void:
	var body := {
		"fen": fen,
		"history_summary": history_summary,
		"message": message,
		"agent_id": agent_id,
		"style_notes": style_notes,
		"last_ai_uci": last_ai_uci,
		"last_reason": last_ai_reason,
	}
	_enqueue("/chat", body, Kind.CHAT)


func reset_session() -> void:
	agent_id = ""
	last_ai_uci = ""
	last_ai_reason = ""
	# Keep style/opening/book across new games unless user changes them.
	_queue.clear()


func clear_opening() -> void:
	opening_name = ""
	book_lines = []
	style_notes = ""


func _enqueue(path: String, body: Dictionary, kind: int) -> void:
	_queue.append({"path": path, "body": body, "kind": kind})
	_pump()


func _pump() -> void:
	if _busy:
		return
	if _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_post_now(String(item.get("path", "")), item.get("body", {}), int(item.get("kind", Kind.NONE)))


func _post_now(path: String, body: Dictionary, kind: int) -> void:
	if _http == null:
		request_failed.emit(_kind_name(kind), "HTTPRequest not attached")
		_pump()
		return
	if kind != Kind.SESSION and body is Dictionary:
		body["agent_id"] = agent_id
		body["style_notes"] = style_notes
		if kind == Kind.MOVE:
			body["book_lines"] = book_lines
			body["opening_name"] = opening_name
	_busy = true
	_pending = kind
	var url := base_url.rstrip("/") + path
	var payload := JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		_busy = false
		_pending = Kind.NONE
		request_failed.emit(_kind_name(kind), "HTTP request failed to start (%d) — 사이드카가 켜져 있는지 확인하세요" % err)
		_pump()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _pending
	_pending = Kind.NONE
	_busy = false
	var kind_name := _kind_name(kind)
	if result != HTTPRequest.RESULT_SUCCESS:
		var hint := "HTTP result=%d" % result
		if result == HTTPRequest.RESULT_CANT_CONNECT:
			hint = "사이드카에 연결할 수 없습니다 (127.0.0.1:8765). ai_sidecar를 먼저 실행하세요."
		elif result == HTTPRequest.RESULT_TIMEOUT:
			hint = "사이드카 응답 시간 초과"
		request_failed.emit(kind_name, hint)
		_pump()
		return
	var text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		request_failed.emit(kind_name, "HTTP %d: %s" % [response_code, text])
		_pump()
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit(kind_name, "invalid JSON")
		_pump()
		return
	var data: Dictionary = parsed
	match kind:
		Kind.SESSION:
			agent_id = String(data.get("agent_id", ""))
			session_ready.emit(agent_id)
		Kind.MOVE:
			var uci := String(data.get("uci", ""))
			var reason := String(data.get("reason", ""))
			var reply := String(data.get("reply", ""))
			var fallback := bool(data.get("fallback", false))
			var aid := String(data.get("agent_id", ""))
			if not aid.is_empty():
				agent_id = aid
			last_ai_uci = uci
			last_ai_reason = reason
			move_chosen.emit(uci, reason, reply, fallback)
		Kind.CHAT:
			var reply2 := String(data.get("reply", ""))
			var style_up := ""
			if data.has("style_update") and data["style_update"] != null:
				style_up = String(data["style_update"])
			var opn := ""
			if data.has("opening_name") and data["opening_name"] != null:
				opn = String(data["opening_name"])
			var books: Array = []
			if data.has("book_lines") and typeof(data["book_lines"]) == TYPE_ARRAY:
				books = data["book_lines"]
			var bfen := ""
			if data.has("board_fen") and data["board_fen"] != null:
				bfen = String(data["board_fen"]).strip_edges()
			var aid2 := String(data.get("agent_id", ""))
			if not aid2.is_empty():
				agent_id = aid2
			if not style_up.is_empty():
				style_notes = style_up
			if not opn.is_empty():
				opening_name = opn
			if books.size() > 0:
				book_lines = books
			chat_replied.emit(reply2, style_up, opn, books, bfen)
		_:
			request_failed.emit(kind_name, "unknown pending kind")
	_pump()


func _kind_name(kind: int) -> String:
	match kind:
		Kind.SESSION:
			return "session"
		Kind.MOVE:
			return "move"
		Kind.CHAT:
			return "chat"
		_:
			return "unknown"
