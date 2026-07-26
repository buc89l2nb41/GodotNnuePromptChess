extends RefCounted
class_name UciEngineController

signal ready_changed(is_ready: bool)
signal bestmove_received(uci_move: String)
signal candidates_received(candidates: Array, bestmove: String)
signal error(msg: String)
signal log_updated(lines: PackedStringArray)

const UciPersistentRunner := preload("res://scripts/engine/uci_persistent_runner.gd")
var _runner: UciPersistentRunner
var _is_ready: bool = false
var _awaiting_bestmove: bool = false
var _engine_path: String = ""
var _skill_level: int = 20
var _max_depth: int = 0
var _multipv: int = 5

var _log_enabled: bool = false
var _log_limit: int = 40


func is_ready() -> bool:
	return _is_ready


func start(engine_path: String) -> void:
	stop()
	_engine_path = engine_path
	if _engine_path.is_empty():
		error.emit("engine_path is empty")
		return

	_runner = UciPersistentRunner.new()
	_runner.set_log_enabled(_log_enabled)
	_runner.set_recent_log_limit(_log_limit)
	_runner.ready_changed.connect(func(r: bool) -> void:
		_is_ready = r
		ready_changed.emit(r)
	)
	_runner.bestmove_received.connect(func(m: String) -> void:
		_awaiting_bestmove = false
		bestmove_received.emit(m)
	)
	_runner.candidates_received.connect(func(cands: Array, best: String) -> void:
		_awaiting_bestmove = false
		candidates_received.emit(cands, best)
	)
	_runner.error.connect(func(msg: String) -> void:
		_awaiting_bestmove = false
		error.emit("engine failed: " + msg)
	)
	_runner.log_line.connect(func(_l: String) -> void:
		log_updated.emit(_runner.recent_log_lines())
	)
	_runner.start(_engine_path)


func poll() -> void:
	if _runner != null:
		_runner.poll()


func stop() -> void:
	_is_ready = false
	_awaiting_bestmove = false
	ready_changed.emit(false)
	if _runner != null:
		_runner.stop()
	_runner = null


func request_bestmove_from_startpos(uci_moves: PackedStringArray, movetime_ms: int = 200) -> void:
	if not _is_ready:
		error.emit("engine not ready")
		return
	if _awaiting_bestmove:
		pass
	_awaiting_bestmove = true

	# Convert startpos+moves to a FEN by delegating to ChessState would be heavyweight here;
	# this path is only used by smoke tests, so just request from startpos without moves.
	if uci_moves.size() > 0:
		error.emit("startpos+moves not supported (use fen)")
		_awaiting_bestmove = false
		return
	const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	request_bestmove_from_fen(START_FEN, movetime_ms)
	return


func request_bestmove_from_fen(fen: String, movetime_ms: int = 200) -> void:
	if not _is_ready:
		error.emit("engine not ready")
		return
	if fen.is_empty():
		error.emit("fen is empty")
		return
	if _awaiting_bestmove:
		pass
	_awaiting_bestmove = true
	if _runner != null:
		_runner.request_bestmove_from_fen(fen, movetime_ms, _skill_level, _max_depth)


func request_candidates_from_fen(fen: String, movetime_ms: int = 200, multipv: int = -1) -> void:
	if not _is_ready:
		error.emit("engine not ready")
		return
	if fen.is_empty():
		error.emit("fen is empty")
		return
	if _awaiting_bestmove:
		pass
	_awaiting_bestmove = true
	var n := _multipv if multipv < 1 else clampi(multipv, 1, 10)
	if _runner != null:
		_runner.request_candidates_from_fen(fen, movetime_ms, _skill_level, _max_depth, n)


func set_strength(skill_level: int, max_depth: int) -> void:
	_skill_level = clampi(skill_level, 0, 20)
	_max_depth = maxi(0, max_depth)


func set_multipv(n: int) -> void:
	_multipv = clampi(n, 1, 10)


func set_engine_log_enabled(enabled: bool) -> void:
	_log_enabled = enabled
	if _runner != null:
		_runner.set_log_enabled(enabled)
	log_updated.emit(get_engine_log_lines())


func set_engine_log_limit(lines: int) -> void:
	_log_limit = clampi(lines, 0, 400)
	if _runner != null:
		_runner.set_recent_log_limit(_log_limit)
	log_updated.emit(get_engine_log_lines())


func get_engine_log_lines() -> PackedStringArray:
	if _runner == null:
		return PackedStringArray()
	return _runner.recent_log_lines()
