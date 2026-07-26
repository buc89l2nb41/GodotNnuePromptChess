extends SceneTree

const UciEngineController := preload("res://scripts/engine/uci_engine_controller.gd")
const EngineSettings := preload("res://scripts/engine/engine_settings.gd")

var _failed := 0
var _engine: UciEngineController
var _got_best := false
var _best := ""


func _init() -> void:
	call_deferred("_run")
	return


func _run() -> void:
	await process_frame
	await _test_stockfish_bestmove_direct()
	# Give pipes/process teardown time to complete (prevents leak warnings on exit).
	await _drain_shutdown_frames()
	if _failed > 0:
		push_error("Stockfish bestmove smoke: %d failed" % _failed)
		quit(1)
	else:
		print("Stockfish bestmove smoke: all passed")
		quit(0)


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		push_error("EXPECT: " + msg)


func _drain_shutdown_frames() -> void:
	# RefCounted + OS pipes may release resources over a few frames.
	for _i in 8:
		await process_frame
	# A tiny timer adds slack even in headless mode.
	var timer := create_timer(0.10)
	await timer.timeout


func _test_stockfish_bestmove_direct() -> void:
	var engine_exe := EngineSettings.find_default_engine_path()
	expect(not engine_exe.is_empty(), "engine exists at default relative path (see EngineSettings.default_engine_candidates)")
	if engine_exe.is_empty():
		return
	expect(FileAccess.file_exists(engine_exe), "engine exists at: %s" % engine_exe)
	if not FileAccess.file_exists(engine_exe):
		return

	_engine = UciEngineController.new()
	_got_best = false
	_best = ""
	_engine.bestmove_received.connect(func(m: String) -> void:
		_got_best = true
		_best = m
	)
	_engine.error.connect(func(msg: String) -> void:
		expect(false, "engine error: %s" % msg)
	)
	_engine.start(engine_exe)
	# Persistent UCI init is async; poll until ready.
	var ready_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < ready_deadline and not _engine.is_ready():
		_engine.poll()
		await process_frame
	expect(_engine.is_ready(), "engine ready")
	if not _engine.is_ready():
		_engine.stop()
		_engine = null
		return

	_engine.request_bestmove_from_startpos(PackedStringArray(), 50)

	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not _got_best:
		_engine.poll()
		await process_frame

	expect(_got_best, "should receive bestmove from real stockfish (direct)")
	expect(_best.length() >= 4, "bestmove looks valid: '%s'" % _best)
	_engine.stop()
	_engine = null
	await _drain_shutdown_frames()

