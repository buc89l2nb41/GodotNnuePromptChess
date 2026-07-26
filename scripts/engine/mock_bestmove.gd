extends RefCounted
class_name MockBestmove

const UciMoves := preload("res://scripts/uci/uci_moves.gd")

static func choose_bestmove_uci(state: ChessState) -> String:
	# 엔진 연결 전까지의 임시 CPU. 항상 합법 수 중 하나를 고른다.
	# (추후 Stockfish bestmove로 교체될 지점)
	var moves: Array = _all_legal_moves(state)
	if moves.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pick: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
	return UciMoves.move_to_uci(pick["from"], pick["to"], pick["promo"])


static func _all_legal_moves(state: ChessState) -> Array:
	# returns [{from,to,promo}]
	var out: Array = []
	for r in 8:
		for f in 8:
			var from := Vector2i(f, r)
			var p := state.piece_atv(from)
			if p == ChessState.NONE:
				continue
			if ChessState.piece_color_white(p) != state.white_to_move:
				continue
			var leg := state.legal_moves_from(from)
			for to in leg:
				var promo := ""
				if (p == ChessState.W_PAWN and to.y == 7) or (p == ChessState.B_PAWN and to.y == 0):
					promo = "q"
				out.append({"from": from, "to": to, "promo": promo})
	return out

