extends RefCounted

## Godot-side move gate for the Prompt AI opponent.
##
## The sidecar already restricts LLM picks to Stockfish MultiPV candidates
## (see ai_sidecar/server.py `_clamp_move`). Opening-book moves can come from
## outside MultiPV, so the last check here is the rules: `ChessState.make_move`
## on a copy of the position. Anything that fails is replaced with a
## skill-weighted engine candidate (or the engine bestmove).
##
## Every decision prints one "[GATE]" line so it shows up in the Godot console
## next to the sidecar's own "[GATE]" lines in ai_sidecar/sidecar.log.

const UciMoves := preload("res://scripts/uci/uci_moves.gd")


## True when `uci` parses and is a legal move in `state` (state is not modified).
static func is_legal_uci(state: ChessState, uci: String) -> bool:
	if uci.is_empty() or state == null:
		return false
	var parsed := UciMoves.parse_uci_move(uci)
	if not bool(parsed.get("ok", false)):
		return false
	var probe := ChessState.new(state)
	var promo_piece := ChessState.W_QUEEN
	var promo := String(parsed.get("promo", ""))
	if not promo.is_empty():
		var w := probe.white_to_move
		match promo:
			"q":
				promo_piece = ChessState.W_QUEEN if w else ChessState.B_QUEEN
			"r":
				promo_piece = ChessState.W_ROOK if w else ChessState.B_ROOK
			"b":
				promo_piece = ChessState.W_BISHOP if w else ChessState.B_BISHOP
			"n":
				promo_piece = ChessState.W_KNIGHT if w else ChessState.B_KNIGHT
	return probe.make_move(parsed.from, parsed.to, promo_piece)


## Rank-weighted random pick: higher skill → rank 1 more often.
static func pick_skill_weighted(candidates: Array, skill_level: int) -> String:
	if candidates.is_empty():
		return ""
	var items: Array = candidates.duplicate()
	items.sort_custom(func(a, b) -> bool:
		return int(a.get("rank", 99)) < int(b.get("rank", 99))
	)
	if items.size() == 1:
		return String(items[0].get("uci", ""))
	var skill := clampi(skill_level, 0, 20)
	var exponent := 0.35 + (float(skill) / 20.0) * 3.15
	var weights: Array[float] = []
	var total := 0.0
	for it in items:
		var r := maxi(1, int(it.get("rank", 1)))
		var w := 1.0 / pow(float(r), exponent)
		weights.append(w)
		total += w
	var roll := randf() * total
	var acc := 0.0
	for i in items.size():
		acc += weights[i]
		if roll <= acc:
			return String(items[i].get("uci", ""))
	return String(items[0].get("uci", ""))


## Decide which move goes on the board.
## Returns { "uci": String, "replaced": bool, "log": String }.
static func decide(
	state: ChessState,
	proposed_uci: String,
	candidates: Array,
	bestmove: String,
	skill_level: int,
) -> Dictionary:
	var cand_ucis: Array[String] = []
	for c in candidates:
		cand_ucis.append(String(c.get("uci", "")))
	var fen := state.fen() if state != null else ""
	if is_legal_uci(state, proposed_uci):
		return {
			"uci": proposed_uci,
			"replaced": false,
			"log": "[GATE] GODOT    PASS     proposed=%s applied=%s candidates=%s fen=%s" % [
				proposed_uci, proposed_uci, ",".join(cand_ucis), fen],
		}
	var pick := pick_skill_weighted(candidates, skill_level)
	if pick.is_empty():
		pick = bestmove
	return {
		"uci": pick,
		"replaced": true,
		"log": "[GATE] GODOT    ILLEGAL  proposed=%s applied=%s candidates=%s fen=%s" % [
			proposed_uci if not proposed_uci.is_empty() else "(none)", pick, ",".join(cand_ucis), fen],
	}
