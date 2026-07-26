extends RefCounted
class_name PgnFen

## Load a FEN string or PGN game text into a ChessState.
## Returns { ok: bool, error: String, fen: String, uci_history: PackedStringArray }


static func looks_like_fen(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty():
		return false
	# Placement has 7 rank separators.
	var first := t.split(" ", false)
	if first.is_empty():
		return false
	return first[0].count("/") == 7


static func extract_fen(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ").replace("\t", " ")
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	# Prefer full 6-field FEN if present.
	var re := RegEx.new()
	re.compile(
		"([rnbqkpRNBQKP1-8]+(?:/[rnbqkpRNBQKP1-8]+){7})\\s+([wb])\\s+([KQkq\\-]{1,4})\\s+([a-h][36]|-)\\s+(\\d+)\\s+(\\d+)"
	)
	var m := re.search(t)
	if m:
		return "%s %s %s %s %s %s" % [
			m.get_string(1), m.get_string(2), m.get_string(3),
			m.get_string(4), m.get_string(5), m.get_string(6)
		]
	# Placement + side at minimum.
	re.compile("([rnbqkpRNBQKP1-8]+(?:/[rnbqkpRNBQKP1-8]+){7})\\s+([wb])\\s+([KQkq\\-]{1,4})\\s+([a-h][36]|-)")
	m = re.search(t)
	if m:
		return "%s %s %s %s 0 1" % [
			m.get_string(1), m.get_string(2), m.get_string(3), m.get_string(4)
		]
	return ""


static func load_text(text: String) -> Dictionary:
	var raw := text.strip_edges()
	if raw.is_empty():
		return {"ok": false, "error": "비어 있습니다", "fen": "", "uci_history": PackedStringArray()}

	if looks_like_fen(raw) or extract_fen(raw) != "":
		var fen := extract_fen(raw)
		if fen.is_empty():
			fen = raw.strip_edges().split("\n", false)[0].strip_edges()
		var st := ChessState.new()
		var res := st.load_fen(fen)
		if not bool(res.get("ok", false)):
			return {
				"ok": false,
				"error": String(res.get("error", "invalid fen")),
				"fen": "",
				"uci_history": PackedStringArray(),
			}
		return {"ok": true, "error": "", "fen": st.fen(), "uci_history": PackedStringArray()}

	return _load_pgn(raw)


static func _load_pgn(text: String) -> Dictionary:
	var st := ChessState.new()
	var uci_hist := PackedStringArray()

	# Optional [FEN "..."] start position.
	var fen_tag := RegEx.new()
	fen_tag.compile("\\[FEN\\s+\"([^\"]+)\"\\s*\\]")
	var fm := fen_tag.search(text)
	if fm:
		var fres := st.load_fen(fm.get_string(1))
		if not bool(fres.get("ok", false)):
			return {
				"ok": false,
				"error": "PGN FEN 태그 오류: %s" % String(fres.get("error", "")),
				"fen": "",
				"uci_history": PackedStringArray(),
			}

	var moves := _tokenize_pgn_moves(text)
	if moves.is_empty():
		return {"ok": false, "error": "PGN에서 수를 찾지 못했습니다", "fen": "", "uci_history": PackedStringArray()}

	var i := 0
	for san in moves:
		i += 1
		var applied := _apply_san(st, san)
		if not bool(applied.get("ok", false)):
			return {
				"ok": false,
				"error": "%d번째 수 '%s': %s" % [i, san, String(applied.get("error", "실패"))],
				"fen": "",
				"uci_history": PackedStringArray(),
			}
		uci_hist.append(String(applied.get("uci", "")))

	return {"ok": true, "error": "", "fen": st.fen(), "uci_history": uci_hist}


static func _tokenize_pgn_moves(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	# Drop tag pairs.
	var no_tags := RegEx.new()
	no_tags.compile("\\[[^\\]]*\\]")
	var body := no_tags.sub(text, " ", true)
	# Drop comments {..} 
	var no_brace := RegEx.new()
	no_brace.compile("\\{[^}]*\\}")
	body = no_brace.sub(body, " ", true)
	# Drop RAV variations (...) including nested ones — chess.com often embeds sidelines.
	body = _strip_parentheses(body)
	var no_nag := RegEx.new()
	no_nag.compile("\\$\\d+")
	body = no_nag.sub(body, " ", true)
	# Normalize newlines/tabs from chess.com soft-wrapped PGNs (e.g. "Kd1\nNd5").
	body = body.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").replace("\t", " ")
	# Drop result tokens (whole tokens only — avoid eating move fragments).
	var no_result := RegEx.new()
	no_result.compile("\\b(1-0|0-1|1/2-1/2|\\*)\\b")
	body = no_result.sub(body, " ", true)
	# Drop move numbers: 12. 12... 
	var no_num := RegEx.new()
	no_num.compile("\\d+\\.(\\.\\.)?")
	body = no_num.sub(body, " ", true)
	while body.find("  ") >= 0:
		body = body.replace("  ", " ")
	for tok in body.split(" ", false):
		var t := String(tok).strip_edges()
		if t.is_empty():
			continue
		t = t.replace("!", "").replace("?", "")
		if t.is_empty():
			continue
		out.append(t)
	return out


static func _strip_parentheses(text: String) -> String:
	var out := ""
	var depth := 0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "(":
			depth += 1
			continue
		if ch == ")":
			depth = maxi(depth - 1, 0)
			continue
		if depth == 0:
			out += ch
	return out


static func _apply_san(st: ChessState, san_raw: String) -> Dictionary:
	var san := san_raw.strip_edges()
	san = san.trim_suffix("+").trim_suffix("#").trim_suffix("+").trim_suffix("#")
	if san.is_empty():
		return {"ok": false, "error": "빈 SAN"}

	# UCI-style token inside PGN.
	if san.length() >= 4 and san.length() <= 5:
		var uci_try := san.to_lower()
		var parsed := UciMoves.parse_uci_move(uci_try)
		if bool(parsed.get("ok", false)):
			var from: Vector2i = parsed.from
			var to: Vector2i = parsed.to
			var promo_ch := String(parsed.get("promo", ""))
			var promo := _promo_piece(st.white_to_move, promo_ch)
			if st.make_move(from, to, promo):
				return {"ok": true, "uci": UciMoves.move_to_uci(from, to, promo_ch)}

	var white := st.white_to_move
	# Castling.
	var castle := san.replace("0", "O")
	if castle == "O-O" or castle == "O-O-O":
		var from := Vector2i(4, 0 if white else 7)
		var to := Vector2i(6 if castle == "O-O" else 2, from.y)
		if st.make_move(from, to):
			return {"ok": true, "uci": UciMoves.move_to_uci(from, to)}
		return {"ok": false, "error": "캐슬링 불가"}

	var promo_ch2 := ""
	var eq := san.find("=")
	if eq >= 0:
		promo_ch2 = san.substr(eq + 1, 1).to_lower()
		san = san.substr(0, eq)
	# Also e8Q style.
	if promo_ch2.is_empty() and san.length() >= 2:
		var last := san.substr(san.length() - 1, 1)
		if "QRBNqrbn".find(last) >= 0 and san.length() >= 3:
			var maybe_sq := san.substr(san.length() - 3, 2)
			if _is_sq(maybe_sq):
				promo_ch2 = last.to_lower()
				san = san.substr(0, san.length() - 1)

	if san.length() < 2:
		return {"ok": false, "error": "SAN 파싱 실패"}

	var dest_s := san.substr(san.length() - 2, 2)
	if not _is_sq(dest_s):
		return {"ok": false, "error": "목적지 칸 없음"}
	var to_sq := UciMoves.uci_to_square(dest_s.to_lower())
	san = san.substr(0, san.length() - 2)
	san = san.replace("x", "").replace("X", "")

	var piece_type := "P"
	var hint_file := -1
	var hint_rank := -1
	if not san.is_empty():
		var c0 := san.substr(0, 1)
		if "KQRBN".find(c0) >= 0:
			piece_type = c0
			san = san.substr(1)
		for j in san.length():
			var ch := san.substr(j, 1)
			var code := ch.unicode_at(0)
			if code >= 97 and code <= 104: # a-h
				hint_file = code - 97
			elif code >= 49 and code <= 56: # 1-8
				hint_rank = code - 49

	var want := _piece_code(white, piece_type)
	var promo := _promo_piece(white, promo_ch2)
	var matches: Array = []
	for r in 8:
		for f in 8:
			var from := Vector2i(f, r)
			if st.piece_atv(from) != want:
				continue
			if hint_file >= 0 and from.x != hint_file:
				continue
			if hint_rank >= 0 and from.y != hint_rank:
				continue
			var legals: Array = st.legal_moves_from(from)
			for dest in legals:
				if dest == to_sq:
					matches.append(from)
					break

	if matches.is_empty():
		return {"ok": false, "error": "합법 수 없음"}
	if matches.size() > 1:
		return {"ok": false, "error": "모호한 SAN (후보 %d)" % matches.size()}

	var from_sq: Vector2i = matches[0]
	if not st.make_move(from_sq, to_sq, promo):
		return {"ok": false, "error": "수 적용 실패"}
	return {"ok": true, "uci": UciMoves.move_to_uci(from_sq, to_sq, promo_ch2)}


static func _is_sq(s: String) -> bool:
	if s.length() != 2:
		return false
	var f := s.unicode_at(0)
	var r := s.unicode_at(1)
	return f >= 97 and f <= 104 and r >= 49 and r <= 56


static func _piece_code(white: bool, letter: String) -> int:
	match letter:
		"K":
			return ChessState.W_KING if white else ChessState.B_KING
		"Q":
			return ChessState.W_QUEEN if white else ChessState.B_QUEEN
		"R":
			return ChessState.W_ROOK if white else ChessState.B_ROOK
		"B":
			return ChessState.W_BISHOP if white else ChessState.B_BISHOP
		"N":
			return ChessState.W_KNIGHT if white else ChessState.B_KNIGHT
		_:
			return ChessState.W_PAWN if white else ChessState.B_PAWN


static func _promo_piece(white: bool, ch: String) -> int:
	match ch.to_lower():
		"q":
			return ChessState.W_QUEEN if white else ChessState.B_QUEEN
		"r":
			return ChessState.W_ROOK if white else ChessState.B_ROOK
		"b":
			return ChessState.W_BISHOP if white else ChessState.B_BISHOP
		"n":
			return ChessState.W_KNIGHT if white else ChessState.B_KNIGHT
		_:
			return ChessState.W_QUEEN if white else ChessState.B_QUEEN
