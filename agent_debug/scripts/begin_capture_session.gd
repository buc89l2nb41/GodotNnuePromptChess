extends SceneTree

## Create a new capture session directory and record it in latest_capture.txt.
## Run before a batch of UI visual verification captures.

const ARTIFACT_DIR := "res://agent_debug/artifacts"
const SESSIONS_DIR := "res://agent_debug/artifacts/sessions"
const LATEST_TXT := "res://agent_debug/artifacts/latest_capture.txt"


func _timestamp_tag() -> String:
	var dt := Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(dt.year), int(dt.month), int(dt.day),
		int(dt.hour), int(dt.minute), int(dt.second),
		int(Time.get_ticks_msec() % 1000)
	]


func _write_latest_session(rel_session_dir: String) -> void:
	var latest_abs := ProjectSettings.globalize_path(LATEST_TXT)
	var f := FileAccess.open(latest_abs, FileAccess.WRITE)
	if f:
		f.store_string(rel_session_dir + "\n")
		f.flush()
		f.close()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sessions_abs := ProjectSettings.globalize_path(SESSIONS_DIR)
	DirAccess.make_dir_recursive_absolute(sessions_abs)

	var rel_session_dir := "sessions/%s" % _timestamp_tag()
	var session_abs := ProjectSettings.globalize_path(ARTIFACT_DIR).path_join(rel_session_dir)
	DirAccess.make_dir_recursive_absolute(session_abs)

	_write_latest_session(rel_session_dir)
	print("capture-session: ", rel_session_dir)
	quit(0)

