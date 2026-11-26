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


## "KBN v K" style material string (white v black), pieces in K Q R B N P order.
static func material_string(state: ChessState) -> String:
	var order := "KQRBNP"
	var w := {}
	var b := {}
	for i in 64:
		var p: int = state.board[i]
		if p == ChessState.NONE:
			continue
		var ch := ChessState._fen_piece_char(p)
		if ch == ch.to_upper():
			w[ch] = int(w.get(ch, 0)) + 1
		else:
			b[ch.to_upper()] = int(b.get(ch.to_upper(), 0)) + 1
	var ws := ""
	var bs := ""
	for c in order:
		ws += c.repeat(int(w.get(c, 0)))
		bs += c.repeat(int(b.get(c, 0)))
	return "%s v %s" % [ws, bs]


static func _normalize_material(m: String) -> String:
	var parts := m.to_upper().replace("VS", "V").split("V", false)
	if parts.size() != 2:
		return ""
	var order := "KQRBNP"
	var out: Array[String] = []
	for part in parts:
		var sorted := ""
		for c in order:
			sorted += c.repeat(part.count(c))
		out.append(sorted)
	return "%s v %s" % [out[0], out[1]]


## Rules part of the setup gate: is this FEN a sane position to put on the board,
## and does it hold the material the agent claimed?
## Returns { ok, error, material }.
static func validate_setup(fen: String, claimed_material: String = "") -> Dictionary:
	var st := ChessState.new()
	var res := st.load_fen(fen)
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": "FEN 형식 오류: %s" % res.get("error", ""), "material": ""}
	var wk := 0
	var bk := 0
	for i in 64:
		var p: int = st.board[i]
		if p == ChessState.W_KING:
			wk += 1
		elif p == ChessState.B_KING:
			bk += 1
		elif p == ChessState.W_PAWN or p == ChessState.B_PAWN:
			var rank := i / 8
			if rank == 0 or rank == 7:
				return {"ok": false, "error": "1·8랭크에 폰이 있습니다", "material": ""}
	var mat := material_string(st)
	if wk != 1 or bk != 1:
		return {"ok": false, "error": "킹 수가 맞지 않습니다 (백 %d, 흑 %d)" % [wk, bk], "material": mat}
	if st.in_check(not st.white_to_move):
		return {"ok": false, "error": "차례가 아닌 쪽 킹이 이미 체크 상태입니다", "material": mat}
	if not st.has_any_legal_move(st.white_to_move):
		return {"ok": false, "error": "차례인 쪽에 둘 수 있는 수가 없습니다", "material": mat}
	if not claimed_material.is_empty():
		var want := _normalize_material(claimed_material)
		if not want.is_empty() and want != mat:
			return {"ok": false, "error": "기물이 요청과 다릅니다 (주장 %s, 실제 %s)" % [want, mat], "material": mat}
	return {"ok": true, "error": "", "material": mat}


## Engine part of the setup gate, given full-strength MultiPV rank-1 for the side to move.
## goal "mate": engine must see a forced mate within mate_in + 1 moves.
## goal "endgame": side to move must be clearly better (mate found or >= +1.00).
## (Measured: Stockfish 18, 1.5 s, scores KBN v K around +1.5, not as a mate.)
static func check_setup_engine(goal: String, mate_in: int, top: Dictionary) -> Dictionary:
	var mate := int(top.get("mate", 0))
	var cp := int(top.get("score_cp", 0))
	var seen := ("mate in %d" % mate) if mate != 0 else ("%+.2f" % (cp / 100.0))
	if goal == "mate":
		var limit := maxi(1, mate_in) + 1
		if mate > 0 and mate <= limit:
			return {"ok": true, "seen": seen}
		return {"ok": false, "seen": seen, "error": "엔진 기준 %d수 안에 메이트가 없습니다 (엔진: %s)" % [limit, seen]}
	if goal == "endgame":
		if mate > 0 or cp >= 100:
			return {"ok": true, "seen": seen}
		return {"ok": false, "seen": seen, "error": "차례인 쪽이 유리한 포지션이 아닙니다 (엔진: %s)" % seen}
	return {"ok": true, "seen": seen}


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
