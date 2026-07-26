extends RefCounted
class_name UciDirectRunner

signal completed(bestmove: String)
signal failed(msg: String)

var _thread: Thread


func request_bestmove(engine_path: String, fen: String, movetime_ms: int, skill_level: int, max_depth: int) -> void:
	_cancel_thread_if_any()
	var args := {
		"engine_path": engine_path,
		"fen": fen,
		"movetime_ms": movetime_ms,
		"skill_level": skill_level,
		"max_depth": max_depth,
	}
	# In headless tests, avoid threads to keep teardown deterministic.
	if DisplayServer.get_name() == "headless":
		var r := _run_request(args)
		var best := String(r.get("bestmove", ""))
		var err := String(r.get("error", ""))
		if not err.is_empty():
			_emit_failed(err)
		else:
			_emit_completed(best)
		return
	_thread = Thread.new()
	_thread.start(_thread_entry.bind(args))


func shutdown() -> void:
	_cancel_thread_if_any()


func _cancel_thread_if_any() -> void:
	if _thread == null:
		return
	# Best effort: we can't safely kill OS.execute from GDScript, so always wait.
	_thread.wait_to_finish()
	_thread = null


func _thread_entry(args: Dictionary) -> void:
	var r := _run_request(args)
	var best := String(r.get("bestmove", ""))
	var err := String(r.get("error", ""))
	call_deferred("_finish_thread", best, err)


func _finish_thread(bestmove: String, err: String) -> void:
	if not err.is_empty():
		failed.emit(err)
	else:
		completed.emit(bestmove)


func _run_request(args: Dictionary) -> Dictionary:
	var engine_path := String(args.get("engine_path", ""))
	var fen := String(args.get("fen", ""))
	var movetime_ms := int(args.get("movetime_ms", 200))
	var skill_level := int(args.get("skill_level", 20))
	var max_depth := int(args.get("max_depth", 0))

	if engine_path.is_empty():
		return {"bestmove": "", "error": "engine_path is empty"}
	if not FileAccess.file_exists(engine_path):
		return {"bestmove": "", "error": "engine not found: %s" % engine_path}
	if fen.is_empty():
		return {"bestmove": "", "error": "fen is empty"}

	var cmd_file := _write_uci_script(fen, movetime_ms, skill_level, max_depth)
	if cmd_file.is_empty():
		return {"bestmove": "", "error": "failed to write uci script"}

	var out: Array = []
	var code := _exec_with_stdin_redirection(engine_path, cmd_file, out)
	# Cleanup best-effort.
	if FileAccess.file_exists(cmd_file):
		DirAccess.remove_absolute(cmd_file)

	if code != 0:
		var joined := ""
		for chunk in out:
			joined += String(chunk)
		joined = joined.strip_edges()
		if joined.is_empty():
			joined = "<no output>"
		return {"bestmove": "", "error": "engine exec failed (code=%d): %s" % [code, joined]}

	var best := _parse_bestmove(out)
	if best.is_empty():
		return {"bestmove": "", "error": "no bestmove in output"}
	return {"bestmove": best, "error": ""}


func _emit_completed(bestmove: String) -> void:
	completed.emit(bestmove)


func _emit_failed(msg: String) -> void:
	failed.emit(msg)


func _write_uci_script(fen: String, movetime_ms: int, skill_level: int, max_depth: int) -> String:
	var dir := OS.get_user_data_dir().path_join("uci_tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("uci_%d.txt" % Time.get_ticks_usec())

	var lines: PackedStringArray = PackedStringArray()
	lines.append("uci")
	lines.append("isready")
	lines.append("ucinewgame")
	lines.append("isready")
	lines.append("setoption name Skill Level value %d" % clampi(skill_level, 0, 20))
	lines.append("position fen " + fen)
	if max_depth > 0:
		lines.append("go depth %d" % max_depth)
	else:
		lines.append("go movetime %d" % maxi(1, movetime_ms))
	lines.append("quit")

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	for l in lines:
		f.store_string(l + "\n")
	f.flush()
	f.close()
	return path


func _exec_with_stdin_redirection(engine_path: String, stdin_file: String, out: Array) -> int:
	# We run the engine in a shell so we can redirect stdin from a file.
	# This keeps the implementation Python-free and works on exported builds.
	if OS.has_feature("windows"):
		# Avoid cmd.exe quoting pitfalls: Windows PowerShell doesn't support '<' redirection;
		# use a pipeline: Get-Content file | & exe
		var exe := engine_path.replace("'", "''")
		var in_file := stdin_file.replace("'", "''")
		var ps := "Get-Content -LiteralPath '%s' | & '%s'" % [in_file, exe]
		return OS.execute(
			"powershell",
			PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", ps]),
			out,
			true,
			true
		)
	else:
		# /bin/sh -lc '"engine" < "file"'
		var cmd := "\"%s\" < \"%s\"" % [_escape_sh_arg(engine_path), _escape_sh_arg(stdin_file)]
		return OS.execute("/bin/sh", PackedStringArray(["-lc", cmd]), out, true, true)


static func _parse_bestmove(out: Array) -> String:
	var joined := ""
	for chunk in out:
		joined += String(chunk)
	var lines := joined.split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		var l := String(lines[i]).strip_edges()
		if l.begins_with("bestmove "):
			var parts := l.split(" ", false)
			if parts.size() >= 2:
				return parts[1]
	return ""


static func _escape_cmd_arg(s: String) -> String:
	# For our usage: we always wrap in double-quotes; just escape embedded quotes.
	return s.replace("\"", "\\\"")


static func _escape_sh_arg(s: String) -> String:
	# We also wrap in double-quotes in the shell command.
	return s.replace("\"", "\\\"")

