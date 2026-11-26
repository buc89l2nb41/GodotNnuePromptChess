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

	await _run_setup_cases()
	print("gate test: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Position-setup gate: rules + claimed material + full-strength engine check.
func _run_setup_cases() -> void:
	var rules := [
		# [fen, claimed material, expect ok, label]
		["6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "KR v KPPP", true, "back-rank mate setup passes rules"],
		["8/8/8/4k3/8/8/8/4KBN1 w - - 0 1", "KBN v K", true, "KBN v K setup passes rules"],
		["8/8/8/4k3/8/8/8/4KB2 w - - 0 1", "KBN v K", false, "missing knight is rejected (material)"],
		["K6k/8/8/8/8/8/8/K7 w - - 0 1", "", false, "two white kings are rejected"],
		["4k3/8/8/8/8/8/8/4RK2 w - - 0 1", "", false, "side not to move in check is rejected"],
		["P3k3/8/8/8/8/8/8/4K3 w - - 0 1", "", false, "pawn on 8th rank is rejected"],
	]
	for c in rules:
		var v: Dictionary = MoveGate.validate_setup(String(c[0]), String(c[1]))
		print("[GATE] SETUP    RULES %s fen=%s claimed=%s actual=%s %s" % [
			"PASS" if bool(v.ok) else "REJECT", c[0], c[1], v.material, v.error])
		expect(bool(v.ok) == bool(c[2]), String(c[3]))

	# Every catalog position must pass the same rules gate the game uses.
	var f := FileAccess.open("res://ai_sidecar/practice_positions.json", FileAccess.READ)
	var cat: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
	var cat_list: Array = cat.get("positions", [])
	expect(cat_list.size() > 0, "practice catalog loads (%d positions)" % cat_list.size())
	for p in cat_list:
		var vv: Dictionary = MoveGate.validate_setup(String(p.fen), String(p.material))
		expect(bool(vv.ok), "catalog %s passes rules (%s) %s" % [p.id, vv.material, vv.error])

	var engine_cases := [
		# [fen, goal, mate_in, expect ok, label]
		["6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "mate", 1, true, "engine confirms back-rank mate in 1"],
		["8/8/8/4k3/8/8/8/4KBN1 w - - 0 1", "endgame", 0, true, "engine confirms KBN v K is winning"],
		["8/8/8/4k3/8/8/8/4KBN1 w - - 0 1", "mate", 2, false, "KBN v K claimed as mate-in-2 is rejected"],
	]
	for c in engine_cases:
		var live: Dictionary = await _live_analysis(String(c[0]))
		if live.is_empty():
			print("setup engine case skipped (no Stockfish): %s" % c[4])
			continue
		var top: Dictionary = (live.cands as Array)[0] if (live.cands as Array).size() > 0 else {}
		var r: Dictionary = MoveGate.check_setup_engine(String(c[1]), int(c[2]), top)
		print("[GATE] SETUP    ENGINE %s goal=%s mate_in=%d engine=%s fen=%s" % [
			"PASS" if bool(r.ok) else "REJECT", c[1], c[2], r.seen, c[0]])
		expect(bool(r.ok) == bool(c[3]), String(c[4]))


func _live_analysis(fen: String) -> Dictionary:
	var engine_exe := EngineSettings.find_default_engine_path()
	if engine_exe.is_empty() or not FileAccess.file_exists(engine_exe):
		return {}
	var engine := UciEngineController.new()
	var box := {"got": [], "done": false, "err": ""}
	engine.error.connect(func(msg: String) -> void: box["err"] = msg)
	engine.candidates_received.connect(func(cands: Array, _b: String) -> void:
		box["got"] = cands
		box["done"] = true
	)
	engine.start(engine_exe)
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not engine.is_ready() and String(box["err"]).is_empty():
		engine.poll()
		await process_frame
	if not engine.is_ready():
		engine.stop()
		return {}
	engine.request_analysis_from_fen(fen, 1500, 1)
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not bool(box["done"]) and String(box["err"]).is_empty():
		engine.poll()
		await process_frame
	engine.stop()
	return {"cands": box["got"]}
