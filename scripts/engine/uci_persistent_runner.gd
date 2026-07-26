extends RefCounted
class_name UciPersistentRunner

signal ready_changed(is_ready: bool)
signal bestmove_received(uci_move: String)
signal candidates_received(candidates: Array, bestmove: String)
signal error(msg: String)
signal log_line(line: String)

const UciMultipv := preload("res://scripts/engine/uci_multipv.gd")
const _READ_CHUNK := 4096

var _engine_path: String = ""
var _pid: int = -1
var _stdio: FileAccess
var _stderr: FileAccess

var _rx_buf: String = ""
var _rx_err_buf: String = ""

var _is_ready: bool = false
var _awaiting_uciok: bool = false
var _awaiting_readyok: bool = false
var _awaiting_bestmove: bool = false
## When true, collect MultiPV candidates and emit candidates_received on bestmove.
var _collect_candidates: bool = false
var _candidate_store: Dictionary = {}

var _pending_stop_depth: int = 0
var _sent_stop_for_depth: bool = false

var _log_enabled: bool = false
var _recent_log: PackedStringArray = PackedStringArray()
var _recent_log_limit: int = 40

var _applied_skill_level: int = -1
var _applied_threads: int = -1
var _applied_hash_mb: int = -1
var _applied_multipv: int = -1
## When true, option change needs readyok before the next go.
var _pending_go_after_ready: bool = false
var _pending_go_fen: String = ""
var _pending_go_movetime_ms: int = 0


func is_ready() -> bool:
	return _is_ready


func set_log_enabled(enabled: bool) -> void:
	_log_enabled = enabled


func set_recent_log_limit(lines: int) -> void:
	_recent_log_limit = clampi(lines, 0, 400)
	_trim_recent_log()


func recent_log_lines() -> PackedStringArray:
	return _recent_log


func start(engine_path: String, threads: int = 1, hash_mb: int = 16) -> void:
	stop()
	_engine_path = engine_path
	if _engine_path.is_empty():
		_emit_error("engine_path is empty")
		return
	if not FileAccess.file_exists(_engine_path):
		_emit_error("engine not found: %s" % _engine_path)
		return
	if not OS.has_method("execute_with_pipe"):
		_emit_error("Godot OS.execute_with_pipe not available (requires Godot 4.3+)")
		return

	var info: Dictionary = OS.execute_with_pipe(_engine_path, PackedStringArray(), false)
	if info.is_empty():
		_emit_error("failed to start engine process")
		return

	_stdio = info.get("stdio", null)
	_stderr = info.get("stderr", null)
	_pid = int(info.get("pid", -1))
	if _stdio == null:
		_emit_error("engine started but stdio pipe is null")
		return

	_is_ready = false
	_awaiting_uciok = true
	_awaiting_readyok = false
	_awaiting_bestmove = false
	_collect_candidates = false
	_candidate_store = {}
	_pending_go_after_ready = false
	_pending_go_fen = ""
	_pending_go_movetime_ms = 0
	_sent_stop_for_depth = false
	_pending_stop_depth = 0

	_recent_log = PackedStringArray()
	_applied_skill_level = -1
	_applied_threads = -1
	_applied_hash_mb = -1
	_applied_multipv = -1

	_send_line("uci")
	_send_line("isready")
	_apply_perf_options_once(threads, hash_mb)


func stop() -> void:
	_is_ready = false
	_awaiting_uciok = false
	_awaiting_readyok = false
	_awaiting_bestmove = false
	_collect_candidates = false
	_candidate_store = {}
	_pending_go_after_ready = false
	_pending_go_fen = ""
	_pending_go_movetime_ms = 0
	_pending_stop_depth = 0
	_sent_stop_for_depth = false
	if _stdio != null:
		# Best-effort graceful quit.
		_send_line("quit")
		_stdio.close()
	if _stderr != null:
		_stderr.close()
	_stdio = null
	_stderr = null
	if _pid > 0:
		# If engine ignores quit, don't leave it running.
		OS.kill(_pid)
	_pid = -1
	ready_changed.emit(false)


func request_bestmove_from_fen(
	fen: String,
	movetime_ms: int,
	skill_level: int,
	max_depth: int
) -> void:
	_begin_search(fen, movetime_ms, skill_level, max_depth, 1, false)


func request_candidates_from_fen(
	fen: String,
	movetime_ms: int,
	skill_level: int,
	max_depth: int,
	multipv: int = 5
) -> void:
	_begin_search(fen, movetime_ms, skill_level, max_depth, clampi(multipv, 1, 10), true)


func _begin_search(
	fen: String,
	movetime_ms: int,
	skill_level: int,
	max_depth: int,
	multipv: int,
	collect_candidates: bool
) -> void:
	if not _is_ready:
		_emit_error("engine not ready")
		return
	if fen.is_empty():
		_emit_error("fen is empty")
		return
	if _awaiting_bestmove:
		# Don't queue multiple concurrent searches.
		return

	_awaiting_bestmove = true
	_collect_candidates = collect_candidates
	_candidate_store = {}
	_sent_stop_for_depth = false
	_pending_stop_depth = maxi(0, max_depth)

	var options_changed := false
	var prev_skill := _applied_skill_level
	var prev_mpv := _applied_multipv
	_apply_skill_if_needed(skill_level)
	_apply_multipv_if_needed(multipv)
	if _applied_skill_level != prev_skill or _applied_multipv != prev_mpv:
		options_changed = true

	if options_changed:
		# UCI: after setoption, wait for readyok before go.
		_pending_go_after_ready = true
		_pending_go_fen = fen
		_pending_go_movetime_ms = maxi(1, movetime_ms)
		_awaiting_readyok = true
		_send_line("isready")
		return

	_send_line("position fen " + fen)
	_send_line("go movetime %d" % maxi(1, movetime_ms))


func _apply_multipv_if_needed(multipv: int) -> void:
	var m := clampi(multipv, 1, 10)
	if _applied_multipv == m:
		return
	_send_line("setoption name MultiPV value %d" % m)
	_applied_multipv = m


func poll() -> void:
	if _stdio == null:
		return
	_read_pipes()


func _apply_perf_options_once(threads: int, hash_mb: int) -> void:
	var t := clampi(threads, 1, 64)
	var h := clampi(hash_mb, 1, 4096)
	if _applied_threads != t:
		_send_line("setoption name Threads value %d" % t)
		_applied_threads = t
	if _applied_hash_mb != h:
		_send_line("setoption name Hash value %d" % h)
		_applied_hash_mb = h


func _apply_skill_if_needed(skill_level: int) -> void:
	var s := clampi(skill_level, 0, 20)
	if _applied_skill_level == s:
		return
	_send_line("setoption name Skill Level value %d" % s)
	_applied_skill_level = s


func _send_line(line: String) -> void:
	if _stdio == null:
		return
	_stdio.store_string(line + "\n")
	_stdio.flush()


func _read_pipes() -> void:
	# stdout
	var out_chunk := _read_available_as_text(_stdio)
	if not out_chunk.is_empty():
		_rx_buf += out_chunk
		_drain_lines(_rx_buf, false)

	# stderr (best-effort; useful for debug)
	if _stderr != null:
		var err_chunk := _read_available_as_text(_stderr)
		if not err_chunk.is_empty():
			_rx_err_buf += err_chunk
			_drain_lines(_rx_err_buf, true)


func _read_available_as_text(fa: FileAccess) -> String:
	if fa == null:
		return ""
	var bytes: PackedByteArray = fa.get_buffer(_READ_CHUNK)
	if bytes.size() <= 0:
		return ""
	return bytes.get_string_from_utf8()


func _drain_lines(buf: String, from_stderr: bool) -> void:
	# NOTE: Godot strings are immutable-ish; keep logic simple and safe.
	while true:
		var idx := buf.find("\n")
		if idx < 0:
			break
		var line := buf.substr(0, idx).strip_edges()
		buf = buf.substr(idx + 1)
		if not line.is_empty():
			_on_engine_line(line, from_stderr)

	if from_stderr:
		_rx_err_buf = buf
	else:
		_rx_buf = buf


func _on_engine_line(line: String, from_stderr: bool) -> void:
	if from_stderr:
		_maybe_log("stderr: " + line)
		return

	if _awaiting_uciok:
		# Stockfish prints "uciok" at the end of UCI init.
		if line == "uciok":
			_awaiting_uciok = false
			_awaiting_readyok = true
		_maybe_log(line)
		return

	if _awaiting_readyok:
		if line == "readyok":
			_awaiting_readyok = false
			if not _is_ready:
				_is_ready = true
				ready_changed.emit(true)
			if _pending_go_after_ready:
				_pending_go_after_ready = false
				var fen := _pending_go_fen
				var mt := _pending_go_movetime_ms
				_pending_go_fen = ""
				_pending_go_movetime_ms = 0
				_send_line("position fen " + fen)
				_send_line("go movetime %d" % mt)
		_maybe_log(line)
		return

	if line.begins_with("info "):
		_handle_info_line(line)
		return

	if line.begins_with("bestmove "):
		var mv := _parse_bestmove(line)
		_awaiting_bestmove = false
		_pending_stop_depth = 0
		_sent_stop_for_depth = false
		if _collect_candidates:
			var cands := UciMultipv.store_to_sorted_array(_candidate_store)
			cands = UciMultipv.ensure_bestmove_candidate(cands, mv)
			_collect_candidates = false
			_candidate_store = {}
			candidates_received.emit(cands, mv)
		else:
			bestmove_received.emit(mv)
		_maybe_log(line)
		return

	_maybe_log(line)


func _handle_info_line(line: String) -> void:
	# If MaxDepth is set, stop when reaching it.
	if _awaiting_bestmove and _pending_stop_depth > 0 and not _sent_stop_for_depth:
		var d := UciMultipv.parse_info_depth(line)
		if d >= _pending_stop_depth:
			_send_line("stop")
			_sent_stop_for_depth = true

	if _collect_candidates:
		var cand := UciMultipv.candidate_from_info_line(line)
		UciMultipv.merge_candidate(_candidate_store, cand)

	_maybe_log(_summarize_info(line))


func _summarize_info(line: String) -> String:
	# Keep a compact, UI-friendly line: depth + score + pv prefix.
	var depth := UciMultipv.parse_info_depth(line)
	var score_fields := UciMultipv.parse_info_score_fields(line)
	var score := ""
	var kind := String(score_fields.get("kind", ""))
	if kind == "cp":
		score = "cp %d" % int(score_fields.get("value", 0))
	elif kind == "mate":
		score = "mate %d" % int(score_fields.get("value", 0))
	var pv := UciMultipv.parse_info_pv_first(line)
	var multipv := UciMultipv.parse_multipv_rank(line)
	var parts: PackedStringArray = PackedStringArray()
	if multipv > 0:
		parts.append("mpv%d" % multipv)
	if depth >= 0:
		parts.append("d%d" % depth)
	if not score.is_empty():
		parts.append(score)
	if not pv.is_empty():
		parts.append("pv " + pv)
	if parts.size() == 0:
		return line
	return "info " + " ".join(parts)


func _parse_bestmove(line: String) -> String:
	var parts := line.split(" ", false)
	if parts.size() >= 2:
		return String(parts[1]).strip_edges()
	return ""


func _maybe_log(line: String) -> void:
	if not _log_enabled:
		return
	_recent_log.append(line)
	_trim_recent_log()
	log_line.emit(line)


func _trim_recent_log() -> void:
	if _recent_log_limit <= 0:
		_recent_log = PackedStringArray()
		return
	while _recent_log.size() > _recent_log_limit:
		_recent_log.remove_at(0)


func _emit_error(msg: String) -> void:
	error.emit(msg)
