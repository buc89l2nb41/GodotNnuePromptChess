extends RefCounted
class_name UciMultipv

## Parse Stockfish/UCI `info ... multipv N ...` lines into candidate dicts.
## Candidate shape: { rank: int, uci: String, score_cp: int, mate: int, depth: int }
## score_cp is set when score kind is cp; mate is set when kind is mate; unused = 0 and the other field used.


static func parse_multipv_rank(line: String) -> int:
	var parts := line.split(" ", false)
	for i in range(parts.size() - 1):
		if parts[i] == "multipv":
			return int(parts[i + 1])
	return -1


static func parse_info_depth(line: String) -> int:
	var parts := line.split(" ", false)
	for i in range(parts.size() - 1):
		if parts[i] == "depth":
			return int(parts[i + 1])
	return -1


static func parse_info_score_fields(line: String) -> Dictionary:
	# { kind: "cp"|"mate"|"", value: int }
	var parts := line.split(" ", false)
	for i in range(parts.size() - 2):
		if parts[i] == "score":
			var kind := String(parts[i + 1])
			var v := int(parts[i + 2])
			if kind == "cp" or kind == "mate":
				return {"kind": kind, "value": v}
	return {"kind": "", "value": 0}


static func parse_info_pv_first(line: String) -> String:
	var parts := line.split(" ", false)
	for i in range(parts.size() - 1):
		if parts[i] == "pv":
			return String(parts[i + 1]).strip_edges()
	return ""


static func candidate_from_info_line(line: String) -> Dictionary:
	if not line.begins_with("info "):
		return {}
	var rank := parse_multipv_rank(line)
	var uci := parse_info_pv_first(line)
	if uci.is_empty():
		return {}
	# MultiPV may be omitted when MultiPV=1; treat as rank 1.
	if rank < 1:
		rank = 1
	var depth := parse_info_depth(line)
	var score := parse_info_score_fields(line)
	var out := {
		"rank": rank,
		"uci": uci,
		"score_cp": 0,
		"mate": 0,
		"depth": depth,
	}
	var kind := String(score.get("kind", ""))
	if kind == "cp":
		out["score_cp"] = int(score.get("value", 0))
	elif kind == "mate":
		out["mate"] = int(score.get("value", 0))
	return out


static func merge_candidate(store: Dictionary, cand: Dictionary) -> void:
	# store: rank(int) -> candidate dict; keep highest depth per rank.
	if cand.is_empty():
		return
	var rank := int(cand.get("rank", 0))
	if rank < 1:
		return
	var prev: Dictionary = store.get(rank, {})
	if prev.is_empty():
		store[rank] = cand
		return
	var prev_depth := int(prev.get("depth", -1))
	var new_depth := int(cand.get("depth", -1))
	if new_depth >= prev_depth:
		store[rank] = cand


static func store_to_sorted_array(store: Dictionary) -> Array:
	var ranks: Array = store.keys()
	ranks.sort()
	var out: Array = []
	var seen_uci: Dictionary = {}
	for r in ranks:
		var c: Dictionary = store[r]
		var uci := String(c.get("uci", ""))
		if uci.is_empty():
			continue
		if seen_uci.has(uci):
			continue
		seen_uci[uci] = true
		out.append(c)
	return out


static func ensure_bestmove_candidate(candidates: Array, bestmove: String) -> Array:
	if bestmove.is_empty():
		return candidates
	for c in candidates:
		if String(c.get("uci", "")) == bestmove:
			return candidates
	var out: Array = candidates.duplicate()
	out.insert(0, {"rank": 1, "uci": bestmove, "score_cp": 0, "mate": 0, "depth": 0})
	return out


static func candidate_ucis(candidates: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for c in candidates:
		var u := String(c.get("uci", ""))
		if not u.is_empty():
			out.append(u)
	return out
