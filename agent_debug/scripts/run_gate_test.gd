extends SceneTree

## Headless: Godot-side move gate (scripts/ai/move_gate.gd).
## A proposed move that is illegal must be replaced by an engine candidate;
## a legal candidate must pass unchanged. Uses live Stockfish MultiPV when
## engine/stockfish/stockfish.exe exists, otherwise a fixed candidate list.
##
## Godot --headless --path . -s res://agent_debug/scripts/run_gate_test.gd

const EngineSettings := preload("res://scripts/engine/engine_settings.gd")
const UciEngineController := preload("res://scripts/engine/uci_engine_controller.gd")
const MoveGate := preload("res://scripts/ai/move_gate.gd")

const START := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
# White to move after 1.e4 e5.
const AFTER_E4_E5 := "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"

var _failed := 0
var _passed := 0


func expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS " + msg)
	else:
		_failed += 1
		push_error("FAIL " + msg)


func _init() -> void:
	call_deferred("_run")


func _live_candidates(fen: String) -> Dictionary:
	var engine_exe := EngineSettings.find_default_engine_path()
	if engine_exe.is_empty() or not FileAccess.file_exists(engine_exe):
		return {}
	var engine := UciEngineController.new()
	var box := {"got": [], "best": "", "err": ""}
	engine.error.connect(func(msg: String) -> void: box["err"] = msg)
	engine.candidates_received.connect(func(cands: Array, b: String) -> void:
		box["got"] = cands
		box["best"] = b
	)
	engine.set_strength(20, 0)
	engine.set_multipv(5)
	engine.start(engine_exe)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not engine.is_ready() and String(box["err"]).is_empty():
		engine.poll()
		await process_frame
	if not engine.is_ready():
		engine.stop()
		return {}
	engine.request_candidates_from_fen(fen, 300, 5)
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and (box["got"] as Array).is_empty() and String(box["err"]).is_empty():
		engine.poll()
		await process_frame
	engine.stop()
	return {"cands": box["got"], "best": box["best"]}


func _run() -> void:
	for fen in [START, AFTER_E4_E5]:
		var live: Dictionary = await _live_candidates(fen)
		var cands: Array = live.get("cands", [])
		var best := String(live.get("best", ""))
		var source := "stockfish"
		if cands.is_empty():
			source = "fixed"
			cands = [{"rank": 1, "uci": "g1f3"}, {"rank": 2, "uci": "b1c3"}]
			best = "g1f3"
		var ucis: Array[String] = []
		for c in cands:
			ucis.append(String(c.get("uci", "")))
		print("candidates (%s) fen=%s : %s" % [source, fen, ",".join(ucis)])

		var state := ChessState.new()
		expect(bool(state.load_fen(fen).get("ok", false)), "load fen")
		var before := state.fen()

		# King e1 → e8 jumps over pieces: illegal.
		var d: Dictionary = MoveGate.decide(state, "e1e8", cands, best, 20)
		print(d.log)
		expect(bool(d.replaced), "illegal e1e8 is replaced")
		expect(ucis.has(String(d.uci)), "replacement %s is an engine candidate" % d.uci)

		# Not UCI at all.
		d = MoveGate.decide(state, "Nf3!", cands, best, 20)
		print(d.log)
		expect(bool(d.replaced) and ucis.has(String(d.uci)), "unparseable answer is replaced by a candidate")

		# A real candidate passes.
		d = MoveGate.decide(state, ucis[0], cands, best, 20)
		print(d.log)
		expect(not bool(d.replaced) and String(d.uci) == ucis[0], "candidate %s passes" % ucis[0])

		expect(state.fen() == before, "gate does not modify the board")

	print("gate test: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
