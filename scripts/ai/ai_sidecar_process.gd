extends RefCounted
class_name AiSidecarProcess

## Starts local uvicorn for ai_sidecar when Godot needs AI mode.
## Owns the child PID only if this process started it (won't kill an external server).

signal started()
signal failed(message: String)
signal already_running()

var base_url: String = "http://127.0.0.1:8765"
var _pid: int = -1
var _owned: bool = false
var _sidecar_dir: String = ""


func sidecar_dir() -> String:
	if not _sidecar_dir.is_empty():
		return _sidecar_dir
	var res := ProjectSettings.globalize_path("res://ai_sidecar")
	if DirAccess.dir_exists_absolute(res):
		_sidecar_dir = res
		return _sidecar_dir
	var exe_side := OS.get_executable_path().get_base_dir().path_join("ai_sidecar")
	if DirAccess.dir_exists_absolute(exe_side):
		_sidecar_dir = exe_side
		return _sidecar_dir
	_sidecar_dir = res
	return _sidecar_dir


func is_owned_running() -> bool:
	return _owned and _pid > 0


func find_python() -> String:
	var dir := sidecar_dir()
	var candidates: PackedStringArray = PackedStringArray()
	if OS.get_name() == "Windows":
		candidates.append(dir.path_join(".venv\\Scripts\\python.exe"))
		candidates.append(dir.path_join(".venv/Scripts/python.exe"))
	else:
		candidates.append(dir.path_join(".venv/bin/python"))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	# Fall back to PATH — create_process needs an executable; try common names via where/which.
	if OS.get_name() == "Windows":
		var out: Array = []
		var code := OS.execute("where", PackedStringArray(["python"]), out, true, false)
		if code == 0 and out.size() > 0:
			var line := String(out[0]).strip_edges().split("\n")[0].strip_edges()
			if FileAccess.file_exists(line):
				return line
		code = OS.execute("where", PackedStringArray(["py"]), out, true, false)
		if code == 0 and out.size() > 0:
			# `py` launcher — use it as the executable with -3
			var line2 := String(out[0]).strip_edges().split("\n")[0].strip_edges()
			if FileAccess.file_exists(line2):
				return line2
	else:
		var out2: Array = []
		if OS.execute("which", PackedStringArray(["python3"]), out2, true, false) == 0 and out2.size() > 0:
			return String(out2[0]).strip_edges()
		if OS.execute("which", PackedStringArray(["python"]), out2, true, false) == 0 and out2.size() > 0:
			return String(out2[0]).strip_edges()
	return ""


func start_detached() -> Dictionary:
	## { ok: bool, message: String, pid: int }
	if _owned and _pid > 0:
		return {"ok": true, "message": "already owned", "pid": _pid}

	var dir := sidecar_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return {"ok": false, "message": "ai_sidecar 폴더 없음: %s" % dir, "pid": -1}
	if not FileAccess.file_exists(dir.path_join("server.py")):
		return {"ok": false, "message": "server.py 없음: %s" % dir, "pid": -1}

	var py := find_python()
	if py.is_empty():
		return {
			"ok": false,
			"message": "Python을 찾을 수 없습니다. Python 설치 또는 ai_sidecar\\.venv 생성 후 pip install -r requirements.txt",
			"pid": -1,
		}

	var host_port := _host_port_from_url(base_url)
	var log_path := dir.path_join("sidecar.log")

	var pid := -1
	# --app-dir 로 cwd 없이도 server.py / .env 를 찾게 함. PID 는 python 자체.
	var args := PackedStringArray([
		"-m", "uvicorn",
		"--app-dir", dir,
		"server:app",
		"--host", String(host_port.host),
		"--port", str(int(host_port.port)),
	])
	if OS.get_name() == "Windows":
		# Redirect via cmd so logs land in sidecar.log without a console window.
		var quoted_args := ""
		for a in args:
			quoted_args += " \"%s\"" % String(a).replace("\"", "\\\"")
		var cmdline := "\"%s\"%s > \"%s\" 2>&1" % [py, quoted_args, log_path]
		pid = OS.create_process("cmd.exe", PackedStringArray(["/c", cmdline]), false)
	else:
		var cmdline2 := "\"%s\"" % py
		for a in args:
			cmdline2 += " '%s'" % String(a).replace("'", "'\\''")
		cmdline2 += " > '%s' 2>&1" % log_path
		pid = OS.create_process("/bin/sh", PackedStringArray(["-c", cmdline2]), false)

	if pid <= 0:
		return {"ok": false, "message": "사이드카 프로세스 시작 실패 (python/uvicorn 확인)", "pid": -1}

	_pid = pid
	_owned = true
	return {"ok": true, "message": "started pid=%d" % pid, "pid": pid}


func free_port() -> void:
	## Best-effort: stop whatever is listening on the sidecar port (stale uvicorn).
	var hp := _host_port_from_url(base_url)
	var port := int(hp.port)
	if OS.get_name() == "Windows":
		var script := (
			"$p=%d; Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | "
			+ "ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"
		) % port
		OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-Command", script]), [], true, false)
	else:
		var cmd := "fuser -k %d/tcp 2>/dev/null || true" % port
		OS.execute("/bin/sh", PackedStringArray(["-c", cmd]), [], true, false)
	_pid = -1
	_owned = false


func restart_fresh() -> Dictionary:
	free_port()
	# Brief pause so the OS releases the port before rebind.
	OS.delay_msec(400)
	return start_detached()


func stop_if_owned() -> void:
	if not _owned:
		_pid = -1
		return
	if _pid > 0:
		OS.kill(_pid)
	_pid = -1
	_owned = false


func _host_port_from_url(url: String) -> Dictionary:
	var host := "127.0.0.1"
	var port := 8765
	var u := url.strip_edges()
	u = u.trim_prefix("http://").trim_prefix("https://")
	var slash := u.find("/")
	if slash >= 0:
		u = u.substr(0, slash)
	var colon := u.rfind(":")
	if colon >= 0:
		host = u.substr(0, colon)
		port = int(u.substr(colon + 1))
	elif not u.is_empty():
		host = u
	return {"host": host, "port": port}
