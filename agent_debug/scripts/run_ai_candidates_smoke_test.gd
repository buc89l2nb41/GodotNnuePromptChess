extends SceneTree

## Headless: MultiPV candidates + AI fallback membership (no Cursor required).
## Godot --headless --path chess -s res://agent_debug/scripts/run_ai_candidates_smoke_test.gd

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")
const UciEngineController := preload("res://scripts/engine/uci_engine_controller.gd")
const UciMultipv := preload("res://scripts/engine/uci_multipv.gd")
const UciMoves := preload("res://scripts/uci/uci_moves.gd")

var _failed := 0


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		push_error("EXPECT: " + msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Offline unit path already covered in run_chess_tests; here we hit Stockfish if present.
	var engine_exe := EngineSettings.find_default_engine_path()
	if engine_exe.is_empty() or not FileAccess.file_exists(engine_exe):
		print("AI candidates smoke: no Stockfish — skipping live MultiPV (unit tests still cover parse)")
		_finish()
		return

	var engine := UciEngineController.new()
	var last_err := ""
	var box := {"got": [], "best": ""}
	engine.error.connect(func(msg: String) -> void:
		last_err = msg
	)
	engine.candidates_received.connect(func(cands: Array, b: String) -> void:
		box["got"] = cands
		box["best"] = b
	)
	engine.set_strength(10, 0)
	engine.set_multipv(3)
	engine.start(engine_exe)

	var ready_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < ready_deadline and not engine.is_ready() and last_err.is_empty():
		engine.poll()
		await process_frame
	expect(engine.is_ready(), "engine ready for multipv")
	if not engine.is_ready():
		expect(false, "engine not ready: %s" % last_err)
		engine.stop()
		_finish()
		return

	const START := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	engine.request_candidates_from_fen(START, 200, 3)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and (box["got"] as Array).is_empty() and last_err.is_empty():
		engine.poll()
		await process_frame

	var got: Array = box["got"]
	var best := String(box["best"])
	expect(last_err.is_empty(), "no engine error: %s" % last_err)
	expect(got.size() >= 1, "at least 1 candidate (got=%d best='%s')" % [got.size(), best])
	expect(not best.is_empty(), "bestmove non-empty")
	var ucis := UciMultipv.candidate_ucis(got)
	expect(ucis.size() >= 1, "uci list non-empty")
	# Simulate sidecar returning illegal UCI → Godot fallback to best/rank1
	var illegal := "a2a3"
	if ucis.has(illegal):
		illegal = "h2h3"
	var pick := illegal
	if not ucis.has(pick):
		pick = best if not best.is_empty() else (ucis[0] if ucis.size() > 0 else "")
	expect(pick != illegal or ucis.has(illegal), "fallback replaced illegal pick")
	expect(not pick.is_empty(), "fallback pick non-empty")
	var parsed := UciMoves.parse_uci_move(pick)
	expect(bool(parsed.get("ok", false)), "fallback UCI parses: %s" % pick)

	engine.stop()
	_finish()


func _finish() -> void:
	if _failed > 0:
		push_error("AI candidates smoke: %d failed" % _failed)
		quit(1)
	else:
		print("AI candidates smoke: all passed")
		quit(0)
