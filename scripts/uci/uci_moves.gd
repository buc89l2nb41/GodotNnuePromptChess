extends RefCounted
class_name UciMoves

static func square_to_uci(sq: Vector2i) -> String:
	return String.chr(97 + sq.x) + str(sq.y + 1)


static func uci_to_square(s: String) -> Vector2i:
	if s.length() != 2:
		return Vector2i(-1, -1)
	var file_c := s.unicode_at(0)
	var rank_c := s.unicode_at(1)
	var f := int(file_c) - 97
	var r := int(rank_c) - 49
	if f < 0 or f > 7 or r < 0 or r > 7:
		return Vector2i(-1, -1)
	return Vector2i(f, r)


static func move_to_uci(from: Vector2i, to: Vector2i, promo_char: String = "") -> String:
	return square_to_uci(from) + square_to_uci(to) + promo_char


static func parse_uci_move(mv: String) -> Dictionary:
	# { ok: bool, from: Vector2i, to: Vector2i, promo: String }
	if mv.length() < 4:
		return {"ok": false}
	var from_s := mv.substr(0, 2)
	var to_s := mv.substr(2, 2)
	var from_sq := uci_to_square(from_s)
	var to_sq := uci_to_square(to_s)
	if from_sq.x < 0 or to_sq.x < 0:
		return {"ok": false}
	var promo := ""
	if mv.length() >= 5:
		promo = mv.substr(4, 1).to_lower()
	return {"ok": true, "from": from_sq, "to": to_sq, "promo": promo}

