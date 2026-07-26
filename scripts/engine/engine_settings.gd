extends RefCounted
class_name EngineSettings

const SETTINGS_PATH := "user://settings.cfg"

static func load_bool(section: String, key: String, default_value: bool) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_value
	return bool(cfg.get_value(section, key, default_value))


static func save_bool(section: String, key: String, value: bool) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	return cfg.save(SETTINGS_PATH)


static func load_int(section: String, key: String, default_value: int) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_value
	return int(cfg.get_value(section, key, default_value))


static func save_int(section: String, key: String, value: int) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	return cfg.save(SETTINGS_PATH)


static func load_float(section: String, key: String, default_value: float) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_value
	return float(cfg.get_value(section, key, default_value))


static func save_float(section: String, key: String, value: float) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	return cfg.save(SETTINGS_PATH)


static func default_engine_candidates() -> PackedStringArray:
	# Engine path is fixed to a relative location.
	# - In editor/dev runs: res://engine/stockfish/stockfish.exe
	# - In exports: <exe_dir>/engine/stockfish/stockfish.exe
	var res_candidate := ProjectSettings.globalize_path("res://engine/stockfish/stockfish.exe")
	var exe_dir := OS.get_executable_path().get_base_dir()
	var portable_candidate := exe_dir.path_join("engine/stockfish/stockfish.exe")
	return PackedStringArray([res_candidate, portable_candidate])


static func find_default_engine_path() -> String:
	for p in default_engine_candidates():
		if FileAccess.file_exists(p):
			return p
	return ""


static func load_string(section: String, key: String, default_value: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_value
	return String(cfg.get_value(section, key, default_value))


static func save_string(section: String, key: String, value: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	return cfg.save(SETTINGS_PATH)

