extends SceneTree

const UciMoves := preload("res://scripts/uci/uci_moves.gd")
const MockBestmove := preload("res://scripts/engine/mock_bestmove.gd")

var _failed := 0


func _init() -> void:
	_test_mock_move_is_legal_and_parsable()
	if _failed > 0:
		push_error("CPU mock smoke: %d failed" % _failed)
		quit(1)
	else:
		print("CPU mock smoke: all passed")
		quit(0)


func expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		push_error("EXPECT: " + msg)


func _test_mock_move_is_legal_and_parsable() -> void:
	var s := ChessState.new()
	s.white_to_move = false # 흑 차례에서 mock이 한 수 둔다 가정
	var mv := MockBestmove.choose_bestmove_uci(s)
	expect(not mv.is_empty(), "mock bestmove should not be empty")
	var parsed := UciMoves.parse_uci_move(mv)
	expect(bool(parsed.get("ok", false)), "uci should parse: '%s'" % mv)
	var from_sq: Vector2i = parsed.get("from", Vector2i(-1, -1))
	var to_sq: Vector2i = parsed.get("to", Vector2i(-1, -1))
	expect(from_sq.x >= 0 and to_sq.x >= 0, "squares valid: '%s'" % mv)
	expect(s.make_move(from_sq, to_sq), "mock move must be legal: '%s'" % mv)

