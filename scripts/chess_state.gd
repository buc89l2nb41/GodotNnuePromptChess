extends RefCounted
class_name ChessState

## Board: file a=0..h=7, rank 0=white's first rank (♖ row), rank 7=black's first rank.
const NONE := 0
const W_PAWN := 1
const W_KNIGHT := 2
const W_BISHOP := 3
const W_ROOK := 4
const W_QUEEN := 5
const W_KING := 6
const B_PAWN := 7
const B_KNIGHT := 8
const B_BISHOP := 9
const B_ROOK := 10
const B_QUEEN := 11
const B_KING := 12

const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8

var board: Array = []
var white_to_move: bool = true
var castling: int = CASTLE_WK | CASTLE_WQ | CASTLE_BK | CASTLE_BQ
## En-passant target square (file, rank) of the square behind the pawn that double-moved; (-1,-1) if none.
var ep_square: Vector2i = Vector2i(-1, -1)
var halfmove_clock: int = 0
var fullmove_number: int = 1

static func idx(f: int, r: int) -> int:
	return f + r * 8


static func is_white_piece(p: int) -> bool:
	return p >= W_PAWN and p <= W_KING


static func is_black_piece(p: int) -> bool:
	return p >= B_PAWN and p <= B_KING


static func piece_color_white(p: int) -> bool:
	return is_white_piece(p)


func piece_atv(sq: Vector2i) -> int:
	if sq.x < 0 or sq.x > 7 or sq.y < 0 or sq.y > 7:
		return NONE
	return board[idx(sq.x, sq.y)]


func piece_at(f: int, r: int) -> int:
	return piece_atv(Vector2i(f, r))


func _init(copy_from: ChessState = null) -> void:
	board.resize(64)
	if copy_from:
		board = copy_from.board.duplicate()
		white_to_move = copy_from.white_to_move
		castling = copy_from.castling
		ep_square = copy_from.ep_square
		halfmove_clock = copy_from.halfmove_clock
		fullmove_number = copy_from.fullmove_number
	else:
		reset_to_start()


func reset_to_start() -> void:
	for i in 64:
		board[i] = NONE
	# White rank 0
	board[idx(0, 0)] = W_ROOK
	board[idx(1, 0)] = W_KNIGHT
	board[idx(2, 0)] = W_BISHOP
	board[idx(3, 0)] = W_QUEEN
	board[idx(4, 0)] = W_KING
	board[idx(5, 0)] = W_BISHOP
	board[idx(6, 0)] = W_KNIGHT
	board[idx(7, 0)] = W_ROOK
	for f in 8:
		board[idx(f, 1)] = W_PAWN
	# Black rank 7
	board[idx(0, 7)] = B_ROOK
	board[idx(1, 7)] = B_KNIGHT
	board[idx(2, 7)] = B_BISHOP
	board[idx(3, 7)] = B_QUEEN
	board[idx(4, 7)] = B_KING
	board[idx(5, 7)] = B_BISHOP
	board[idx(6, 7)] = B_KNIGHT
	board[idx(7, 7)] = B_ROOK
	for f in 8:
		board[idx(f, 6)] = B_PAWN
	white_to_move = true
	castling = CASTLE_WK | CASTLE_WQ | CASTLE_BK | CASTLE_BQ
	ep_square = Vector2i(-1, -1)
	halfmove_clock = 0
	fullmove_number = 1


func fen() -> String:
	# Piece placement: ranks 8..1
	var rows: PackedStringArray = PackedStringArray()
	for r in range(7, -1, -1):
		var empty := 0
		var row := ""
		for f in 8:
			var p: int = piece_at(f, r)
			if p == NONE:
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			row += _fen_piece_char(p)
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var placement := "/".join(rows)

	var stm := "w" if white_to_move else "b"

	var castle := ""
	if castling & CASTLE_WK:
		castle += "K"
	if castling & CASTLE_WQ:
		castle += "Q"
	if castling & CASTLE_BK:
		castle += "k"
	if castling & CASTLE_BQ:
		castle += "q"
	if castle.is_empty():
		castle = "-"

	var ep := "-"
	if ep_square != Vector2i(-1, -1):
		ep = String.chr(97 + ep_square.x) + str(ep_square.y + 1)

	return "%s %s %s %s %d %d" % [placement, stm, castle, ep, halfmove_clock, fullmove_number]


func load_fen(fen_str: String) -> Dictionary:
	# Minimal but strict-ish FEN loader used by the board editor.
	# Returns: { ok: bool, error: String }
	var parts := fen_str.strip_edges().split(" ", false)
	if parts.size() < 4:
		return {"ok": false, "error": "FEN must have at least 4 fields"}
	var placement: String = parts[0]
	var stm: String = parts[1]
	var castle: String = parts[2]
	var ep: String = parts[3]
	var half: int = int(parts[4]) if parts.size() >= 5 else 0
	var full: int = int(parts[5]) if parts.size() >= 6 else 1

	var ranks := placement.split("/", false)
	if ranks.size() != 8:
		return {"ok": false, "error": "FEN placement must have 8 ranks"}
	var new_board: Array = []
	new_board.resize(64)
	for i in 64:
		new_board[i] = NONE
	for rr in range(8):
		var rstr: String = ranks[rr]
		var file := 0
		for j in rstr.length():
			var ch := rstr.substr(j, 1)
			if ch >= "1" and ch <= "8":
				file += int(ch)
				continue
			var p := _piece_from_fen_char(ch)
			if p == NONE:
				return {"ok": false, "error": "invalid piece char: %s" % ch}
			if file < 0 or file > 7:
				return {"ok": false, "error": "rank has too many files"}
			var board_rank := 7 - rr
			new_board[idx(file, board_rank)] = p
			file += 1
		if file != 8:
			return {"ok": false, "error": "rank does not sum to 8 files"}

	var new_white_to_move := (stm == "w")
	if stm != "w" and stm != "b":
		return {"ok": false, "error": "side-to-move must be w or b"}

	var new_castling := 0
	if castle != "-":
		for i in castle.length():
			var k := castle.substr(i, 1)
			match k:
				"K": new_castling |= CASTLE_WK
				"Q": new_castling |= CASTLE_WQ
				"k": new_castling |= CASTLE_BK
				"q": new_castling |= CASTLE_BQ
				_:
					return {"ok": false, "error": "invalid castling field"}

	var new_ep := Vector2i(-1, -1)
	if ep != "-":
		if ep.length() != 2:
			return {"ok": false, "error": "invalid ep field"}
		var ef := ep.unicode_at(0) - "a".unicode_at(0)
		var er := int(ep.substr(1, 1)) - 1
		if ef < 0 or ef > 7 or er < 0 or er > 7:
			return {"ok": false, "error": "invalid ep square"}
		new_ep = Vector2i(ef, er)

	board = new_board
	white_to_move = new_white_to_move
	castling = new_castling
	ep_square = new_ep
	halfmove_clock = maxi(0, half)
	fullmove_number = maxi(1, full)
	return {"ok": true, "error": ""}


static func _piece_from_fen_char(ch: String) -> int:
	match ch:
		"P": return W_PAWN
		"N": return W_KNIGHT
		"B": return W_BISHOP
		"R": return W_ROOK
		"Q": return W_QUEEN
		"K": return W_KING
		"p": return B_PAWN
		"n": return B_KNIGHT
		"b": return B_BISHOP
		"r": return B_ROOK
		"q": return B_QUEEN
		"k": return B_KING
	return NONE


static func _fen_piece_char(p: int) -> String:
	match p:
		W_PAWN: return "P"
		W_KNIGHT: return "N"
		W_BISHOP: return "B"
		W_ROOK: return "R"
		W_QUEEN: return "Q"
		W_KING: return "K"
		B_PAWN: return "p"
		B_KNIGHT: return "n"
		B_BISHOP: return "b"
		B_ROOK: return "r"
		B_QUEEN: return "q"
		B_KING: return "k"
	return ""


func unicode_for(p: int) -> String:
	match p:
		W_PAWN: return "♙"
		W_KNIGHT: return "♘"
		W_BISHOP: return "♗"
		W_ROOK: return "♖"
		W_QUEEN: return "♕"
		W_KING: return "♔"
		B_PAWN: return "♟"
		B_KNIGHT: return "♞"
		B_BISHOP: return "♝"
		B_ROOK: return "♜"
		B_QUEEN: return "♛"
		B_KING: return "♚"
	return ""


func _king_square(for_white: bool) -> Vector2i:
	var k := W_KING if for_white else B_KING
	for i in 64:
		if board[i] == k:
			return Vector2i(i % 8, i / 8)
	return Vector2i(-1, -1)


func is_square_attacked(sq: Vector2i, by_white: bool) -> bool:
	var f := sq.x
	var r := sq.y
	# Pawns
	var pawn_dir := 1 if by_white else -1
	var pr := r - pawn_dir
	if pr >= 0 and pr <= 7:
		for df in [-1, 1]:
			var nf: int = f + int(df)
			if nf >= 0 and nf <= 7:
				var p: int = piece_at(nf, pr)
				if by_white and p == W_PAWN:
					return true
				if not by_white and p == B_PAWN:
					return true
	var kd: Array[Vector2i] = [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
		Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
	]
	for d: Vector2i in kd:
		var nf: int = f + d.x
		var nr: int = r + d.y
		if nf < 0 or nf > 7 or nr < 0 or nr > 7:
			continue
		var p: int = piece_at(nf, nr)
		if by_white and p == W_KNIGHT:
			return true
		if not by_white and p == B_KNIGHT:
			return true
	# King (adjacent)
	for df in range(-1, 2):
		for dr in range(-1, 2):
			if df == 0 and dr == 0:
				continue
			var nf: int = f + df
			var nr: int = r + dr
			if nf < 0 or nf > 7 or nr < 0 or nr > 7:
				continue
			var p: int = piece_at(nf, nr)
			if by_white and p == W_KING:
				return true
			if not by_white and p == B_KING:
				return true
	var rook_dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for d: Vector2i in rook_dirs:
		var nf: int = f
		var nr: int = r
		while true:
			nf += d.x
			nr += d.y
			if nf < 0 or nf > 7 or nr < 0 or nr > 7:
				break
			var p: int = piece_at(nf, nr)
			if p == NONE:
				continue
			if by_white:
				if p == W_ROOK or p == W_QUEEN:
					return true
			else:
				if p == B_ROOK or p == B_QUEEN:
					return true
			break
	var bishop_dirs: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for d: Vector2i in bishop_dirs:
		var nf: int = f
		var nr: int = r
		while true:
			nf += d.x
			nr += d.y
			if nf < 0 or nf > 7 or nr < 0 or nr > 7:
				break
			var p: int = piece_at(nf, nr)
			if p == NONE:
				continue
			if by_white:
				if p == W_BISHOP or p == W_QUEEN:
					return true
			else:
				if p == B_BISHOP or p == B_QUEEN:
					return true
			break
	return false


func in_check(for_white: bool) -> bool:
	return is_square_attacked(_king_square(for_white), not for_white)


func _add_ray_moves(from: Vector2i, piece: int, dirs: Array[Vector2i], out: Array, _capture_only_block: bool = false) -> void:
	for d: Vector2i in dirs:
		var cur: Vector2i = from + d
		while cur.x >= 0 and cur.x <= 7 and cur.y >= 0 and cur.y <= 7:
			var target: int = piece_atv(cur)
			if target == NONE:
				out.append(cur)
				cur += d
				continue
			var enemy := is_black_piece(target) if piece_color_white(piece) else is_white_piece(target)
			if enemy:
				out.append(cur)
			break


func _pawn_pushes(from: Vector2i, piece: int, out: Array) -> void:
	var forward := 1 if piece == W_PAWN else -1
	var one := Vector2i(from.x, from.y + forward)
	if piece_atv(one) == NONE:
		out.append(one)
		var start_rank := 1 if piece == W_PAWN else 6
		if from.y == start_rank:
			var two := Vector2i(from.x, from.y + 2 * forward)
			if piece_atv(two) == NONE:
				out.append(two)
	for df in [-1, 1]:
		var cap: Vector2i = Vector2i(from.x + int(df), from.y + forward)
		if cap.x < 0 or cap.x > 7 or cap.y < 0 or cap.y > 7:
			continue
		var t: int = piece_atv(cap)
		var enemy: bool = is_black_piece(t) if piece == W_PAWN else is_white_piece(t)
		if enemy:
			out.append(cap)
		# En passant
		if ep_square != Vector2i(-1, -1) and cap == ep_square:
			var ep_pawn_rank := from.y
			var passer_file := ep_square.x
			var passer := piece_at(passer_file, from.y)
			if piece == W_PAWN and passer == B_PAWN:
				out.append(cap)
			elif piece == B_PAWN and passer == W_PAWN:
				out.append(cap)


func _pseudo_legal_moves_from(from: Vector2i) -> Array:
	var out: Array = []
	var piece := piece_atv(from)
	if piece == NONE:
		return out
	var mine_white := piece_color_white(piece)
	if mine_white != white_to_move:
		return out
	match piece:
		W_PAWN, B_PAWN:
			_pawn_pushes(from, piece, out)
		W_KNIGHT, B_KNIGHT:
			var ndeltas: Array[Vector2i] = [
				Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
				Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
			]
			for d: Vector2i in ndeltas:
				var t: Vector2i = from + d
				if t.x < 0 or t.x > 7 or t.y < 0 or t.y > 7:
					continue
				var tp: int = piece_atv(t)
				if tp == NONE:
					out.append(t)
				elif is_black_piece(tp) != is_black_piece(piece):
					out.append(t)
		W_BISHOP, B_BISHOP:
			var bdirs: Array[Vector2i] = [
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
			]
			_add_ray_moves(from, piece, bdirs, out)
		W_ROOK, B_ROOK:
			var rdirs: Array[Vector2i] = [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			]
			_add_ray_moves(from, piece, rdirs, out)
		W_QUEEN, B_QUEEN:
			var qdirs: Array[Vector2i] = [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
			]
			_add_ray_moves(from, piece, qdirs, out)
		W_KING, B_KING:
			for df in range(-1, 2):
				for dr in range(-1, 2):
					if df == 0 and dr == 0:
						continue
					var t: Vector2i = Vector2i(from.x + df, from.y + dr)
					if t.x < 0 or t.x > 7 or t.y < 0 or t.y > 7:
						continue
					var tp: int = piece_atv(t)
					if tp == NONE or (is_black_piece(tp) != is_black_piece(piece)):
						out.append(t)
			# Castling
			if piece == W_KING and from == Vector2i(4, 0):
				if castling & CASTLE_WK and piece_at(5, 0) == NONE and piece_at(6, 0) == NONE and piece_at(7, 0) == W_ROOK:
					out.append(Vector2i(6, 0))
				if castling & CASTLE_WQ and piece_at(3, 0) == NONE and piece_at(2, 0) == NONE and piece_at(1, 0) == NONE and piece_at(0, 0) == W_ROOK:
					out.append(Vector2i(2, 0))
			if piece == B_KING and from == Vector2i(4, 7):
				if castling & CASTLE_BK and piece_at(5, 7) == NONE and piece_at(6, 7) == NONE and piece_at(7, 7) == B_ROOK:
					out.append(Vector2i(6, 7))
				if castling & CASTLE_BQ and piece_at(3, 7) == NONE and piece_at(2, 7) == NONE and piece_at(1, 7) == NONE and piece_at(0, 7) == B_ROOK:
					out.append(Vector2i(2, 7))
	return out


## ep_capture: en-passant landing square from the current position (self.ep_square before the move).
func _apply_move_internal(from: Vector2i, to: Vector2i, promotion: int, ep_capture: Vector2i) -> void:
	var moving := piece_atv(from)
	var captured := piece_atv(to)
	board[idx(from.x, from.y)] = NONE
	if moving == W_KING and from == Vector2i(4, 0) and to == Vector2i(6, 0):
		board[idx(7, 0)] = NONE
		board[idx(5, 0)] = W_ROOK
	elif moving == W_KING and from == Vector2i(4, 0) and to == Vector2i(2, 0):
		board[idx(0, 0)] = NONE
		board[idx(3, 0)] = W_ROOK
	elif moving == B_KING and from == Vector2i(4, 7) and to == Vector2i(6, 7):
		board[idx(7, 7)] = NONE
		board[idx(5, 7)] = B_ROOK
	elif moving == B_KING and from == Vector2i(4, 7) and to == Vector2i(2, 7):
		board[idx(0, 7)] = NONE
		board[idx(3, 7)] = B_ROOK
	if (moving == W_PAWN or moving == B_PAWN) and ep_capture != Vector2i(-1, -1) and to == ep_capture and captured == NONE:
		board[idx(ep_capture.x, from.y)] = NONE
	var place := moving
	if moving == W_PAWN and to.y == 7:
		place = promotion
	elif moving == B_PAWN and to.y == 0:
		place = promotion
	board[idx(to.x, to.y)] = place


func make_move(from: Vector2i, to: Vector2i, promotion: int = W_QUEEN) -> bool:
	var legal := legal_moves_from(from)
	var ok := false
	for d in legal:
		if d == to:
			ok = true
			break
	if not ok:
		return false
	var moving := piece_atv(from)
	var prev_ep := ep_square
	var next_ep := Vector2i(-1, -1)
	if moving == W_PAWN and from.y == 1 and to.y == 3:
		next_ep = Vector2i(from.x, 2)
	elif moving == B_PAWN and from.y == 6 and to.y == 4:
		next_ep = Vector2i(from.x, 5)
	if moving == W_PAWN or moving == B_PAWN or piece_atv(to) != NONE or ((moving == W_PAWN or moving == B_PAWN) and to == prev_ep):
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	if moving == W_KING:
		castling &= ~(CASTLE_WK | CASTLE_WQ)
	elif moving == B_KING:
		castling &= ~(CASTLE_BK | CASTLE_BQ)
	if from == Vector2i(0, 0) or to == Vector2i(0, 0):
		castling &= ~CASTLE_WQ
	if from == Vector2i(7, 0) or to == Vector2i(7, 0):
		castling &= ~CASTLE_WK
	if from == Vector2i(0, 7) or to == Vector2i(0, 7):
		castling &= ~CASTLE_BQ
	if from == Vector2i(7, 7) or to == Vector2i(7, 7):
		castling &= ~CASTLE_BK
	_apply_move_internal(from, to, promotion, prev_ep)
	ep_square = next_ep
	white_to_move = not white_to_move
	if white_to_move:
		# black just moved
		fullmove_number += 1
	return true


func legal_moves_from(from: Vector2i) -> Array:
	var pseudo: Array = _pseudo_legal_moves_from(from)
	var legal: Array = []
	var piece := piece_atv(from)
	if piece == NONE:
		return legal
	var side_white := piece_color_white(piece)
	var ep_now := ep_square
	for dest in pseudo:
		var prom := piece
		if piece == W_PAWN and dest.y == 7:
			prom = W_QUEEN
		elif piece == B_PAWN and dest.y == 0:
			prom = B_QUEEN
		var test := ChessState.new(self)
		test._apply_move_internal(from, dest, prom, ep_now)
		if not test.in_check(side_white):
			# Castling: king cannot pass through attacked squares
			if piece == W_KING and from == Vector2i(4, 0) and dest == Vector2i(6, 0):
				if is_square_attacked(Vector2i(4, 0), false) or is_square_attacked(Vector2i(5, 0), false):
					continue
			if piece == W_KING and from == Vector2i(4, 0) and dest == Vector2i(2, 0):
				if is_square_attacked(Vector2i(4, 0), false) or is_square_attacked(Vector2i(3, 0), false):
					continue
			if piece == B_KING and from == Vector2i(4, 7) and dest == Vector2i(6, 7):
				if is_square_attacked(Vector2i(4, 7), true) or is_square_attacked(Vector2i(5, 7), true):
					continue
			if piece == B_KING and from == Vector2i(4, 7) and dest == Vector2i(2, 7):
				if is_square_attacked(Vector2i(4, 7), true) or is_square_attacked(Vector2i(3, 7), true):
					continue
			legal.append(dest)
	return legal


func has_any_legal_move(for_white: bool) -> bool:
	for r in 8:
		for f in 8:
			var p := piece_at(f, r)
			if p == NONE:
				continue
			if piece_color_white(p) != for_white:
				continue
			if legal_moves_from(Vector2i(f, r)).size() > 0:
				return true
	return false


func result_string() -> String:
	var wtm := white_to_move
	var side_in_check := in_check(wtm)
	if not has_any_legal_move(wtm):
		if side_in_check:
			return "체크메이트 — " + ("흑 승" if wtm else "백 승")
		return "스테일메이트 — 무승부"
	if halfmove_clock >= 100:
		return "50수 규칙 — 무승부"
	return ""
