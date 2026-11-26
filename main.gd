extends Control

const _PgnFen = preload("res://scripts/pgn_fen.gd")
const EngineSettings := preload("res://scripts/engine/engine_settings.gd")
const UciMoves := preload("res://scripts/uci/uci_moves.gd")
const MockBestmove := preload("res://scripts/engine/mock_bestmove.gd")
const UciEngineController := preload("res://scripts/engine/uci_engine_controller.gd")
const UciMultipv := preload("res://scripts/engine/uci_multipv.gd")
const AiSidecarClient := preload("res://scripts/ai/ai_sidecar_client.gd")
const AiSidecarProcess := preload("res://scripts/ai/ai_sidecar_process.gd")
const MoveGate := preload("res://scripts/ai/move_gate.gd")

## chess.com 기본 그린 보드 + 플레이 화면(다크 크롬·브랜드 그린)에 맞춘 팔레트
const LIGHT := Color(0.933333, 0.933333, 0.823529) # #EEEED2
const DARK := Color(0.462745, 0.588235, 0.337255) # #769656
const MAIN_BG := Color(0.188235, 0.180392, 0.168627) # #302E2B
const BAR_BG := Color(0.149020, 0.141176, 0.129412) # #262421
const BAR_SEPARATOR := Color(0, 0, 0, 0.24)
const BOARD_FRAME := Color(0.270588, 0.254902, 0.231373) # #45413B
const LAST_MOVE := Color(0.803922, 0.823529, 0.415686, 0.38) # #CDD26A
const HINT := Color(0.25, 0.55, 0.95, 0.45) # 에이전트 추천 수
const SELECT := Color(0.505882, 0.713725, 0.298039, 0.48) # #81B64C 오버레이
const LEGAL_DOT := Color(0.2, 0.22, 0.18, 0.4)
const LEGAL_RING := Color(0.16, 0.18, 0.13, 0.58)
const COORD_LEFT_PAD := 24.0
const COORD_BOTTOM_PAD := 28.0
const COORD_ON_LIGHT := Color(0.466667, 0.584314, 0.337255, 0.95) # #779556
const COORD_ON_DARK := Color(0.921569, 0.925490, 0.815686, 0.95) # #EBECD0
const COORD_GUTTER := Color(0.69, 0.69, 0.69, 1) # rank 숫자
## 상단 바(차례·버튼)와 동일하게 유지 → main.tscn Bar 높이와 맞출 것
const TOP_BAR_HEIGHT := 58.0
const CHAT_PANEL_WIDTH := 280.0

## 기물 렌더링(폰트 기반) → SVG 텍스처 기반으로 교체.
## chess.com과 동일 세트는 불가(저작권)지만, lichess에서 널리 쓰는 cburnett로 자연스러운 실루엣 확보.
const PIECE_SET_DIR := "res://assets/pieces/cburnett"
const PIECE_SCALE_FRAC := 0.92
const PIECE_SVG_RASTER_SCALE := 6.0
## 상단 바와 8단 사이 여유
const BOARD_ORIGIN_Y_EXTRA := 16.0

@onready var _turn_label: Label = $VBox/Bar/TurnLabel
@onready var _reset_btn: Button = $VBox/Bar/ResetButton
@onready var _undo_btn: Button = $VBox/Bar/UndoButton
@onready var _edit_btn: Button = $VBox/Bar/EditButton
@onready var _cpu_btn: Button = $VBox/Bar/CpuButton
@onready var _settings_btn: Button = $VBox/Bar/SettingsButton
@onready var _player_side: OptionButton = $VBox/Bar/PlayerSide
@onready var _engine_status: Label = $VBox/Bar/EngineStatus
@onready var _settings_popup: PopupPanel = $SettingsPopup
@onready var _settings_level: OptionButton = $SettingsPopup/Margin/VBox/Row/Level
@onready var _settings_skill: SpinBox = $SettingsPopup/Margin/VBox/Row/Skill
@onready var _settings_movetime: SpinBox = $SettingsPopup/Margin/VBox/Row/MoveTime
@onready var _settings_max_depth: SpinBox = $SettingsPopup/Margin/VBox/Row/MaxDepth
@onready var _engine_log_toggle: CheckBox = $SettingsPopup/Margin/VBox/EngineLogToggle
@onready var _engine_log_view: TextEdit = $SettingsPopup/Margin/VBox/EngineLogView
@onready var _settings_close: Button = $SettingsPopup/Margin/VBox/Close
@onready var _promo: PopupPanel = $PromotionPopup
@onready var _promo_grid: GridContainer = $PromotionPopup/Margin/VBox/Grid
@onready var _chat_log: RichTextLabel = $ChatPanel/Margin/VBox/ChatLog
@onready var _chat_input: TextEdit = $ChatPanel/Margin/VBox/ChatInput
@onready var _chat_send: Button = $ChatPanel/Margin/VBox/Row/ChatSend
@onready var _position_paste: TextEdit = $ChatPanel/Margin/VBox/PositionPaste
@onready var _position_apply: Button = $ChatPanel/Margin/VBox/PositionRow/PositionApply
@onready var _position_coach: Button = $ChatPanel/Margin/VBox/PositionRow/PositionCoach
@onready var _position_copy_fen: Button = $ChatPanel/Margin/VBox/PositionRow/PositionCopyFen
@onready var _position_status: Label = $ChatPanel/Margin/VBox/PositionStatus
@onready var _ai_http: HTTPRequest = $AiHttp
@onready var _ai_health_http: HTTPRequest = $AiHealthHttp

var _ui_font: Font
var _shaped_line: TextLine
var _piece_tex: Dictionary[int, Texture2D] = {}
var _state: ChessState
var _cell: float = 72.0
var _board_origin: Vector2 = Vector2.ZERO
var _selected: Vector2i = Vector2i(-1, -1)
var _legals: Array = []
var _pending_from: Vector2i
var _pending_to: Vector2i
var _game_over: bool = false
var _last_from: Vector2i = Vector2i(-1, -1)
var _last_to: Vector2i = Vector2i(-1, -1)

var _undo_stack: Array[Dictionary] = []

var _editor_active: bool = false
var _editor_popup: PopupPanel
var _editor_error: Label
var _editor_turn: OptionButton
var _editor_castle_k: CheckBox
var _editor_castle_q: CheckBox
var _editor_castle_kk: CheckBox
var _editor_castle_qq: CheckBox
var _editor_ep: OptionButton
var _editor_halfmove: SpinBox
var _editor_fullmove: SpinBox
var _editor_fen: LineEdit
var _editor_selected_piece: int = ChessState.NONE
var _editor_pre_state: ChessState
var _editor_pre_last_from: Vector2i = Vector2i(-1, -1)
var _editor_pre_last_to: Vector2i = Vector2i(-1, -1)
var _editor_pre_uci: PackedStringArray = PackedStringArray()
var _editor_pre_game_over: bool = false

var _engine_path: String = ""
enum OpponentMode { OFF, CPU, AI }
var _opponent_mode: int = OpponentMode.OFF
## Legacy alias: true when CPU or AI (engine opponent active).
var _cpu_enabled: bool = false
enum PlayerSide { WHITE, BLACK }
var _player_side_mode: int = PlayerSide.WHITE
var _uci_history: PackedStringArray = PackedStringArray()
var _engine: UciEngineController
var _difficulty_ms: int = 200
var _last_engine_error: String = ""
var _lichess_level: int = 4
var _skill_level: int = 10
var _max_depth: int = 3
var _syncing_settings_ui: bool = false
var _engine_log_enabled: bool = false

var _ai: AiSidecarClient
var _ai_proc: AiSidecarProcess
var _ai_pending_candidates: Array = []
var _ai_pending_bestmove: String = ""
## Who the next engine candidates are for: "ai" (AI move), "chat" (recommendation), "setup" (verify).
var _cand_purpose: String = ""
var _chat_pending_msg: String = ""
var _chat_pending_fen: String = ""
## Position-setup gate: agent FEN waiting for the engine check, and one automatic retry.
var _setup_pending: Dictionary = {}
var _setup_request_msg: String = ""
var _setup_retry_left: int = 0
## Agent move recommendation shown on the board (after both gates).
var _hint_from: Vector2i = Vector2i(-1, -1)
var _hint_to: Vector2i = Vector2i(-1, -1)
var _awaiting_ai_pick: bool = false
var _ai_sidecar_ready: bool = false
var _ai_sidecar_starting: bool = false
var _ai_health_tries: int = 0
var _ai_sidecar_bootstrapped: bool = false
const _AI_HEALTH_MAX_TRIES := 20
## Must match ai_sidecar/server.py CODE_REV
const _AI_SIDECAR_CODE_REV := 11

enum TurnMode { HUMAN_TURN, ENGINE_THINKING, ENGINE_MOVE_APPLYING, GAME_OVER, CHAT_ANALYZING }
var _turn_mode: int = TurnMode.HUMAN_TURN


func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
	sf.generate_mipmaps = true
	_ui_font = sf
	_shaped_line = TextLine.new()
	_turn_label.add_theme_font_override("font", _ui_font)
	_reset_btn.add_theme_font_override("font", _ui_font)
	_undo_btn.add_theme_font_override("font", _ui_font)
	_edit_btn.add_theme_font_override("font", _ui_font)
	var promo_title: Label = _promo.get_node_or_null("Margin/VBox/Title") as Label
	if promo_title:
		promo_title.add_theme_font_override("font", _ui_font)
	for child in _promo_grid.get_children():
		if child is Button:
			child.add_theme_font_override("font", _ui_font)
			child.pressed.connect(_on_promo_choice.bind(child))
	_reset_btn.pressed.connect(_new_game)
	_undo_btn.pressed.connect(_undo)
	_edit_btn.pressed.connect(_open_editor)
	_cpu_btn.pressed.connect(_cycle_opponent_mode)
	_settings_btn.pressed.connect(_open_settings)
	_player_side.item_selected.connect(_on_player_side_selected)
	_settings_level.item_selected.connect(_on_level_selected)
	_settings_skill.value_changed.connect(_on_skill_changed)
	_settings_movetime.value_changed.connect(_on_movetime_changed)
	_settings_max_depth.value_changed.connect(_on_max_depth_changed)
	_engine_log_toggle.toggled.connect(_on_engine_log_toggled)
	_settings_close.pressed.connect(func() -> void: _settings_popup.hide())
	_chat_send.pressed.connect(_on_chat_send)
	_chat_input.gui_input.connect(_on_chat_input_gui_input)
	_position_apply.pressed.connect(_on_position_apply)
	_position_coach.pressed.connect(_on_position_coach)
	_position_copy_fen.pressed.connect(_on_position_copy_fen)
	_promo.hide()
	_load_piece_textures()
	_apply_promo_button_icons()
	_load_cpu_settings_on_start()
	_engine_path = EngineSettings.find_default_engine_path()
	_engine = UciEngineController.new()
	_engine.set_multipv(8)
	_engine.bestmove_received.connect(_on_engine_bestmove)
	_engine.candidates_received.connect(_on_engine_candidates)
	_engine.error.connect(_on_engine_error)
	_engine.log_updated.connect(_on_engine_log_updated)
	_engine.ready_changed.connect(func(_ready: bool) -> void:
		_update_engine_status()
		# If opponent is enabled and it's their turn (e.g. player chose black),
		# trigger the first move as soon as the engine becomes ready.
		if _ready:
			call_deferred("_after_any_move")
	)
	_ai = AiSidecarClient.new()
	_ai.base_url = EngineSettings.load_string("ai", "sidecar_url", "http://127.0.0.1:8765")
	_ai.style_notes = EngineSettings.load_string("ai", "style_notes", "")
	_ai.opening_name = EngineSettings.load_string("ai", "opening_name", "")
	_ai.attach_http(_ai_http)
	_ai.move_chosen.connect(_on_ai_move_chosen)
	_ai.chat_replied.connect(_on_ai_chat_replied)
	_ai.request_failed.connect(_on_ai_request_failed)
	_ai_proc = AiSidecarProcess.new()
	_ai_proc.base_url = _ai.base_url
	_ai_health_http.request_completed.connect(_on_ai_health_completed)
	_new_game()

	_build_editor_ui()


func _build_editor_ui() -> void:
	# Programmatic UI keeps main.tscn small while still being visible for screenshots.
	_editor_popup = PopupPanel.new()
	_editor_popup.name = "EditorPopup"
	# Keep popup open while placing pieces on the board (clicking outside should not auto-close).
	# This also makes OS-level "real click" automation much more reliable.
	if _editor_popup is Window:
		(_editor_popup as Window).exclusive = true
	add_child(_editor_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	_editor_popup.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title := Label.new()
	title.text = "보드 편집"
	title.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_font_override("font", _ui_font)
	v.add_child(title)

	_editor_error = Label.new()
	_editor_error.text = ""
	_editor_error.visible = false
	_editor_error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_editor_error.add_theme_font_override("font", _ui_font)
	v.add_child(_editor_error)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	v.add_child(row1)

	var start_btn := Button.new()
	start_btn.text = "시작 포지션"
	start_btn.pressed.connect(func() -> void:
		_state.reset_to_start()
		_sync_editor_ui_from_state()
		queue_redraw()
	)
	row1.add_child(start_btn)

	var clear_btn := Button.new()
	clear_btn.text = "클리어"
	clear_btn.pressed.connect(func() -> void:
		for i in 64:
			_state.board[i] = ChessState.NONE
		_state.white_to_move = true
		_state.castling = 0
		_state.ep_square = Vector2i(-1, -1)
		_state.halfmove_clock = 0
		_state.fullmove_number = 1
		_sync_editor_ui_from_state()
		queue_redraw()
	)
	row1.add_child(clear_btn)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)

	var turn_label := Label.new()
	turn_label.text = "턴"
	turn_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	turn_label.add_theme_font_override("font", _ui_font)
	row2.add_child(turn_label)

	_editor_turn = OptionButton.new()
	_editor_turn.add_item("백 차례", 0)
	_editor_turn.add_item("흑 차례", 1)
	_editor_turn.item_selected.connect(func(idx: int) -> void:
		_state.white_to_move = (idx == 0)
		_sync_editor_ui_from_state()
	)
	row2.add_child(_editor_turn)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 10)
	v.add_child(row3)

	var castle_label := Label.new()
	castle_label.text = "캐슬링"
	castle_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	castle_label.add_theme_font_override("font", _ui_font)
	row3.add_child(castle_label)

	_editor_castle_k = CheckBox.new()
	_editor_castle_k.text = "K"
	row3.add_child(_editor_castle_k)
	_editor_castle_q = CheckBox.new()
	_editor_castle_q.text = "Q"
	row3.add_child(_editor_castle_q)
	_editor_castle_kk = CheckBox.new()
	_editor_castle_kk.text = "k"
	row3.add_child(_editor_castle_kk)
	_editor_castle_qq = CheckBox.new()
	_editor_castle_qq.text = "q"
	row3.add_child(_editor_castle_qq)

	var castle_changed := func(_on: bool) -> void:
		var c := 0
		if _editor_castle_k.button_pressed: c |= ChessState.CASTLE_WK
		if _editor_castle_q.button_pressed: c |= ChessState.CASTLE_WQ
		if _editor_castle_kk.button_pressed: c |= ChessState.CASTLE_BK
		if _editor_castle_qq.button_pressed: c |= ChessState.CASTLE_BQ
		_state.castling = c
		_sync_editor_ui_from_state()
	_editor_castle_k.toggled.connect(castle_changed)
	_editor_castle_q.toggled.connect(castle_changed)
	_editor_castle_kk.toggled.connect(castle_changed)
	_editor_castle_qq.toggled.connect(castle_changed)

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 10)
	v.add_child(row4)

	var ep_label := Label.new()
	ep_label.text = "EP"
	ep_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	ep_label.add_theme_font_override("font", _ui_font)
	row4.add_child(ep_label)

	_editor_ep = OptionButton.new()
	_editor_ep.add_item("-", 0)
	# a3..h3 and a6..h6 are the only ranks that make sense as EP targets.
	var ep_items: Array[String] = []
	for f in 8:
		ep_items.append(String.chr(97 + f) + "3")
	for f in 8:
		ep_items.append(String.chr(97 + f) + "6")
	for s in ep_items:
		_editor_ep.add_item(s)
	_editor_ep.item_selected.connect(func(idx: int) -> void:
		if idx == 0:
			_state.ep_square = Vector2i(-1, -1)
		else:
			var s := _editor_ep.get_item_text(idx)
			var ef := s.unicode_at(0) - "a".unicode_at(0)
			var er := int(s.substr(1, 1)) - 1
			_state.ep_square = Vector2i(ef, er)
		_sync_editor_ui_from_state()
	)
	row4.add_child(_editor_ep)

	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 10)
	v.add_child(row5)

	var hm_label := Label.new()
	hm_label.text = "Half"
	hm_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	hm_label.add_theme_font_override("font", _ui_font)
	row5.add_child(hm_label)
	_editor_halfmove = SpinBox.new()
	_editor_halfmove.min_value = 0
	_editor_halfmove.max_value = 200
	_editor_halfmove.step = 1
	_editor_halfmove.rounded = true
	_editor_halfmove.value_changed.connect(func(vv: float) -> void:
		_state.halfmove_clock = int(vv)
		_sync_editor_ui_from_state()
	)
	row5.add_child(_editor_halfmove)

	var fm_label := Label.new()
	fm_label.text = "Full"
	fm_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	fm_label.add_theme_font_override("font", _ui_font)
	row5.add_child(fm_label)
	_editor_fullmove = SpinBox.new()
	_editor_fullmove.min_value = 1
	_editor_fullmove.max_value = 999
	_editor_fullmove.step = 1
	_editor_fullmove.rounded = true
	_editor_fullmove.value_changed.connect(func(vv: float) -> void:
		_state.fullmove_number = int(vv)
		_sync_editor_ui_from_state()
	)
	row5.add_child(_editor_fullmove)

	var row6 := HBoxContainer.new()
	row6.add_theme_constant_override("separation", 10)
	v.add_child(row6)

	var fen_label := Label.new()
	fen_label.text = "FEN"
	fen_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
	fen_label.add_theme_font_override("font", _ui_font)
	row6.add_child(fen_label)

	_editor_fen = LineEdit.new()
	_editor_fen.custom_minimum_size = Vector2(520, 0)
	row6.add_child(_editor_fen)

	var copy_btn := Button.new()
	copy_btn.text = "복사"
	copy_btn.pressed.connect(func() -> void:
		if _state != null:
			DisplayServer.clipboard_set(_state.fen())
	)
	row6.add_child(copy_btn)

	var load_btn := Button.new()
	load_btn.text = "불러오기"
	load_btn.pressed.connect(func() -> void:
		if _state == null:
			return
		var res := _state.load_fen(_editor_fen.text)
		if not bool(res.get("ok", false)):
			_show_editor_error(String(res.get("error", "invalid fen")))
			return
		_hide_editor_error()
		_sync_editor_ui_from_state()
		queue_redraw()
	)
	row6.add_child(load_btn)

	var palette := GridContainer.new()
	palette.columns = 7
	palette.add_theme_constant_override("h_separation", 8)
	palette.add_theme_constant_override("v_separation", 8)
	v.add_child(palette)

	var add_tool := func(label: String, piece: int) -> void:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(52, 36)
		b.pressed.connect(func() -> void:
			_editor_selected_piece = piece
		)
		palette.add_child(b)

	add_tool.call("지움", ChessState.NONE)
	add_tool.call("wK", ChessState.W_KING)
	add_tool.call("wQ", ChessState.W_QUEEN)
	add_tool.call("wR", ChessState.W_ROOK)
	add_tool.call("wB", ChessState.W_BISHOP)
	add_tool.call("wN", ChessState.W_KNIGHT)
	add_tool.call("wP", ChessState.W_PAWN)
	add_tool.call("bK", ChessState.B_KING)
	add_tool.call("bQ", ChessState.B_QUEEN)
	add_tool.call("bR", ChessState.B_ROOK)
	add_tool.call("bB", ChessState.B_BISHOP)
	add_tool.call("bN", ChessState.B_KNIGHT)
	add_tool.call("bP", ChessState.B_PAWN)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)

	var apply_btn := Button.new()
	apply_btn.text = "적용"
	apply_btn.pressed.connect(_apply_editor)
	bottom.add_child(apply_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "취소"
	cancel_btn.pressed.connect(_cancel_editor)
	bottom.add_child(cancel_btn)


func _open_editor() -> void:
	if _state == null:
		return
	# Snapshot current game to support Cancel.
	_editor_pre_state = ChessState.new(_state)
	_editor_pre_last_from = _last_from
	_editor_pre_last_to = _last_to
	_editor_pre_uci = _uci_history.duplicate()
	_editor_pre_game_over = _game_over
	_editor_active = true
	_hide_editor_error()
	_sync_editor_ui_from_state()
	_editor_popup.popup_centered(Vector2i(760, 520))


func _cancel_editor() -> void:
	if _editor_pre_state != null:
		_state = ChessState.new(_editor_pre_state)
	_last_from = _editor_pre_last_from
	_last_to = _editor_pre_last_to
	_uci_history = _editor_pre_uci
	_game_over = _editor_pre_game_over
	_editor_active = false
	_editor_popup.hide()
	_turn_mode = TurnMode.HUMAN_TURN
	_refresh_ui()
	queue_redraw()


func _apply_editor() -> void:
	if _state == null:
		return
	# Policy: require exactly one king per side.
	var wk := 0
	var bk := 0
	for i in 64:
		if _state.board[i] == ChessState.W_KING:
			wk += 1
		elif _state.board[i] == ChessState.B_KING:
			bk += 1
	if wk != 1 or bk != 1:
		_show_editor_error("킹은 백/흑 각각 1개여야 합니다 (wK=%d, bK=%d)." % [wk, bk])
		return
	_hide_editor_error()
	_editor_active = false
	_editor_popup.hide()
	# Applying an arbitrary position invalidates undo history.
	_undo_stack.clear()
	_selected = Vector2i(-1, -1)
	_legals.clear()
	_turn_mode = TurnMode.HUMAN_TURN
	_refresh_ui()
	queue_redraw()
	_after_any_move()


func _sync_editor_ui_from_state() -> void:
	if _state == null:
		return
	_editor_turn.select(0 if _state.white_to_move else 1)
	_editor_castle_k.button_pressed = bool(_state.castling & ChessState.CASTLE_WK)
	_editor_castle_q.button_pressed = bool(_state.castling & ChessState.CASTLE_WQ)
	_editor_castle_kk.button_pressed = bool(_state.castling & ChessState.CASTLE_BK)
	_editor_castle_qq.button_pressed = bool(_state.castling & ChessState.CASTLE_BQ)
	_editor_halfmove.value = float(_state.halfmove_clock)
	_editor_fullmove.value = float(_state.fullmove_number)
	_editor_fen.text = _state.fen()
	if _state.ep_square == Vector2i(-1, -1):
		_editor_ep.select(0)
	else:
		var ep_s := String.chr(97 + _state.ep_square.x) + str(_state.ep_square.y + 1)
		for i in _editor_ep.item_count:
			if _editor_ep.get_item_text(i) == ep_s:
				_editor_ep.select(i)
				break


func _show_editor_error(msg: String) -> void:
	if _editor_error == null:
		return
	_editor_error.text = msg
	_editor_error.visible = true


func _hide_editor_error() -> void:
	if _editor_error == null:
		return
	_editor_error.text = ""
	_editor_error.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# Ctrl+Z: Undo last move (kept simple; project doesn't define an InputMap action yet).
	if event is InputEventKey and event.pressed and not event.echo:
		var ev := event as InputEventKey
		if ev.ctrl_pressed and (ev.keycode == KEY_Z):
			_undo()
			accept_event()


func _push_undo_snapshot() -> void:
	if _state == null:
		return
	_undo_stack.append({
		"state": ChessState.new(_state),
		"last_from": _last_from,
		"last_to": _last_to,
		"uci_history": _uci_history.duplicate(),
	})


func _undo() -> void:
	if _promo != null:
		_promo.hide()
	_selected = Vector2i(-1, -1)
	_legals.clear()

	if _state == null or _undo_stack.is_empty():
		return

	# In CPU/AI games, Undo should usually revert both sides (2 plies) so it's still the player's turn.
	# If only one ply exists (e.g. player just moved and CPU hasn't), revert one ply.
	var player_is_white := (_player_side_mode == PlayerSide.WHITE)

	_restore_from_undo_snapshot(_undo_stack.pop_back())
	if _cpu_enabled and _undo_stack.size() > 0:
		# If after undo it's still not the player's turn, pop one more ply.
		if _state != null and _state.white_to_move != player_is_white:
			_restore_from_undo_snapshot(_undo_stack.pop_back())

	_turn_mode = TurnMode.HUMAN_TURN
	_awaiting_ai_pick = false
	_game_over = false
	_refresh_ui()
	_update_engine_status()
	queue_redraw()


func _restore_from_undo_snapshot(snap: Dictionary) -> void:
	var st: ChessState = snap.get("state", null)
	if st != null:
		_state = st
	_last_from = snap.get("last_from", Vector2i(-1, -1))
	_last_to = snap.get("last_to", Vector2i(-1, -1))
	var uh: PackedStringArray = snap.get("uci_history", PackedStringArray())
	_uci_history = uh


func _process(_delta: float) -> void:
	if _engine != null:
		_engine.poll()


func _load_cpu_settings_on_start() -> void:
	var legacy_cpu := EngineSettings.load_bool("cpu", "enabled", false)
	_opponent_mode = EngineSettings.load_int("opponent", "mode", OpponentMode.CPU if legacy_cpu else OpponentMode.OFF)
	_opponent_mode = clampi(_opponent_mode, OpponentMode.OFF, OpponentMode.AI)
	_cpu_enabled = _opponent_mode != OpponentMode.OFF
	_player_side_mode = EngineSettings.load_int("player", "side", PlayerSide.WHITE)
	_lichess_level = EngineSettings.load_int("cpu", "lichess_level", 4)
	_skill_level = EngineSettings.load_int("cpu", "skill_level", 10)
	_difficulty_ms = EngineSettings.load_int("cpu", "movetime_ms", 200)
	_max_depth = EngineSettings.load_int("cpu", "max_depth", 3)
	_engine_log_enabled = EngineSettings.load_bool("dev", "engine_log", false)
	_player_side.select(clampi(_player_side_mode, 0, 1))
	_apply_engine_strength(_skill_level, _difficulty_ms, _max_depth)
	_sync_settings_ui_from_values()
	_settings_level.select(clampi(_lichess_level - 1, 0, 7))
	_sync_opponent_button()
	_engine_log_toggle.button_pressed = _engine_log_enabled
	_engine_log_view.visible = _engine_log_enabled
	if _engine != null:
		_engine.set_engine_log_enabled(_engine_log_enabled)


func _sync_opponent_button() -> void:
	match _opponent_mode:
		OpponentMode.CPU:
			_cpu_btn.text = "상대: CPU"
		OpponentMode.AI:
			_cpu_btn.text = "상대: AI"
		_:
			_cpu_btn.text = "상대: OFF"


func _update_engine_status() -> void:
	if _engine_status == null:
		return
	if _opponent_mode == OpponentMode.OFF:
		_engine_status.text = "ENGINE: -"
		return
	if _opponent_mode == OpponentMode.AI:
		if _ai_sidecar_starting:
			_engine_status.text = "AI: STARTING"
			return
		if not _ai_sidecar_ready:
			_engine_status.text = "AI: NO SIDECAR"
			return
		if _awaiting_ai_pick:
			_engine_status.text = "AI: THINKING"
			return
		if _engine != null and _engine.is_ready():
			_engine_status.text = "AI: READY"
			return
		if not _last_engine_error.is_empty():
			_engine_status.text = "ENGINE: ERROR"
			return
		_engine_status.text = "ENGINE: CONNECTING"
		return
	if _engine != null and _engine.is_ready():
		_engine_status.text = "ENGINE: READY"
		return
	if not _last_engine_error.is_empty():
		_engine_status.text = "ENGINE: ERROR"
		return
	_engine_status.text = "ENGINE: CONNECTING"


func _on_engine_log_toggled(on: bool) -> void:
	_engine_log_enabled = on
	EngineSettings.save_bool("dev", "engine_log", _engine_log_enabled)
	if _engine_log_view != null:
		_engine_log_view.visible = _engine_log_enabled
	if _engine != null:
		_engine.set_engine_log_enabled(_engine_log_enabled)


func _on_engine_log_updated(lines: PackedStringArray) -> void:
	if not _engine_log_enabled:
		return
	if _engine_log_view == null:
		return
	_engine_log_view.text = "\n".join(lines)
	_engine_log_view.scroll_vertical = 1_000_000


func _load_piece_textures() -> void:
	_piece_tex.clear()
	_piece_tex[ChessState.W_KING] = _raster_svg_to_texture(PIECE_SET_DIR + "/wK.svg")
	_piece_tex[ChessState.W_QUEEN] = _raster_svg_to_texture(PIECE_SET_DIR + "/wQ.svg")
	_piece_tex[ChessState.W_ROOK] = _raster_svg_to_texture(PIECE_SET_DIR + "/wR.svg")
	_piece_tex[ChessState.W_BISHOP] = _raster_svg_to_texture(PIECE_SET_DIR + "/wB.svg")
	_piece_tex[ChessState.W_KNIGHT] = _raster_svg_to_texture(PIECE_SET_DIR + "/wN.svg")
	_piece_tex[ChessState.W_PAWN] = _raster_svg_to_texture(PIECE_SET_DIR + "/wP.svg")
	_piece_tex[ChessState.B_KING] = _raster_svg_to_texture(PIECE_SET_DIR + "/bK.svg")
	_piece_tex[ChessState.B_QUEEN] = _raster_svg_to_texture(PIECE_SET_DIR + "/bQ.svg")
	_piece_tex[ChessState.B_ROOK] = _raster_svg_to_texture(PIECE_SET_DIR + "/bR.svg")
	_piece_tex[ChessState.B_BISHOP] = _raster_svg_to_texture(PIECE_SET_DIR + "/bB.svg")
	_piece_tex[ChessState.B_KNIGHT] = _raster_svg_to_texture(PIECE_SET_DIR + "/bN.svg")
	_piece_tex[ChessState.B_PAWN] = _raster_svg_to_texture(PIECE_SET_DIR + "/bP.svg")


func _raster_svg_to_texture(path: String) -> Texture2D:
	# Headless 테스트 환경에서 .svg importer가 안 도는 경우가 있어 런타임에서 래스터라이즈.
	var svg := FileAccess.get_file_as_string(path)
	if svg.is_empty():
		return null
	var img := Image.new()
	var err := img.load_svg_from_string(svg, PIECE_SVG_RASTER_SCALE)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


func _apply_promo_button_icons() -> void:
	# Button icon은 중앙 정렬이 쉬워서, 텍스트 유니코드 대신 아이콘으로.
	for child in _promo_grid.get_children():
		var btn := child as Button
		if btn == null:
			continue
		var p: int = ChessState.NONE
		match btn.name:
			"Q":
				p = ChessState.W_QUEEN
			"R":
				p = ChessState.W_ROOK
			"B":
				p = ChessState.W_BISHOP
			"N":
				p = ChessState.W_KNIGHT
			_:
				continue
		var t: Texture2D = _piece_tex.get(p, null)
		if t == null:
			continue
		btn.icon = t
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.expand_icon = true


func _new_game() -> void:
	_state = ChessState.new()
	_selected = Vector2i(-1, -1)
	_legals.clear()
	_last_from = Vector2i(-1, -1)
	_last_to = Vector2i(-1, -1)
	_game_over = false
	_turn_mode = TurnMode.HUMAN_TURN
	_awaiting_ai_pick = false
	_ai_pending_candidates = []
	_ai_pending_bestmove = ""
	_uci_history = PackedStringArray()
	_undo_stack.clear()
	_promo.hide()
	if _ai != null:
		_ai.reset_session()
	_refresh_ui()
	queue_redraw()
	if _cpu_enabled:
		_engine.start(_engine_path)
		if _opponent_mode == OpponentMode.AI:
			_ensure_ai_sidecar()
		# If the engine is already ready, this will let opponent open immediately.
		_after_any_move()


func _refresh_ui() -> void:
	if _state == null:
		return
	var extra := _state.result_string()
	if extra.is_empty():
		_turn_label.text = "백 차례" if _state.white_to_move else "흑 차례"
		if _state.in_check(_state.white_to_move):
			_turn_label.text += "  ·  체크"
	else:
		_turn_label.text = extra
		_game_over = true
		_turn_mode = TurnMode.GAME_OVER


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _board_layout() -> Dictionary:
	var margin_top := TOP_BAR_HEIGHT
	var chat_w := CHAT_PANEL_WIDTH
	var avail := Vector2(size.x - COORD_LEFT_PAD - chat_w, size.y - margin_top - COORD_BOTTOM_PAD)
	var side := minf(avail.x, avail.y - 10.0)
	var cell: float = floorf(side / 8.0)
	var bw: float = cell * 8.0
	var origin := Vector2(
		COORD_LEFT_PAD + (avail.x - bw) * 0.5,
		margin_top + BOARD_ORIGIN_Y_EXTRA + (avail.y - bw) * 0.5
	)
	return {"margin_top": margin_top, "cell": cell, "bw": bw, "origin": origin}


func _rect_for_square(sq: Vector2i) -> Rect2:
	var vf := sq.x if not _is_flipped() else 7 - sq.x
	var sr := (7 - sq.y) if not _is_flipped() else sq.y
	return Rect2(_board_origin + Vector2(vf * _cell, sr * _cell), Vector2(_cell, _cell))


func _square_is_light(sq: Vector2i) -> bool:
	return (sq.x + sq.y) % 2 == 1


func automation_square_to_local_center(sq: Vector2i) -> Vector2:
	# Keep automation aligned with actual on-screen mapping (supports board flip).
	return _rect_for_square(sq).get_center()


func automation_send_click_local(local_pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local_pos
	_gui_input(ev)


func automation_click_square(sq: Vector2i) -> void:
	automation_send_click_local(automation_square_to_local_center(sq))


func automation_state() -> ChessState:
	return _state


func automation_turn_label_text() -> String:
	return _turn_label.text


func automation_promote_queen() -> void:
	var q := _promo_grid.get_node_or_null("Q") as Button
	if q:
		_on_promo_choice(q)


func _draw() -> void:
	if _state == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), MAIN_BG)
	var lay := _board_layout()
	var margin_top: float = lay.margin_top
	draw_rect(Rect2(0, 0, size.x, margin_top), BAR_BG)
	draw_line(Vector2(0, margin_top), Vector2(size.x, margin_top), BAR_SEPARATOR, 1.0)
	_cell = lay.cell
	_board_origin = lay.origin
	var bw: float = lay.bw

	var frame_pad := 2.0
	draw_rect(
		Rect2(_board_origin - Vector2(frame_pad, frame_pad), Vector2(bw + frame_pad * 2, bw + frame_pad * 2)),
		BOARD_FRAME,
		false,
		1.0,
		true
	)

	for y in 8:
		for x in 8:
			var sq := Vector2i(x, y)
			var light := _square_is_light(sq)
			draw_rect(_rect_for_square(sq), LIGHT if light else DARK)

	if _last_from.x >= 0:
		draw_rect(_rect_for_square(_last_from), LAST_MOVE)
	if _last_to.x >= 0:
		draw_rect(_rect_for_square(_last_to), LAST_MOVE)
	if _hint_from.x >= 0:
		draw_rect(_rect_for_square(_hint_from), HINT)
	if _hint_to.x >= 0:
		draw_rect(_rect_for_square(_hint_to), HINT)

	if _selected.x >= 0:
		draw_rect(_rect_for_square(_selected), SELECT)

	for dest in _legals:
		var r := _rect_for_square(dest)
		var c := r.get_center()
		var cap := _legal_dest_is_capture(dest)
		if cap:
			var rad: float = _cell * 0.36
			draw_arc(c, rad, 0.0, TAU, 48, LEGAL_RING, maxf(2.5, _cell * 0.055), true)
		else:
			draw_circle(c, maxf(3.0, _cell * 0.125), LEGAL_DOT)

	for y in 8:
		for x in 8:
			var sq := Vector2i(x, y)
			var p := _state.piece_atv(sq)
			if p != ChessState.NONE:
				var center := _rect_for_square(sq).get_center()
				_draw_piece_texture(center, p)

	_draw_board_coordinates(lay)


func _legal_dest_is_capture(sq: Vector2i) -> bool:
	if _state.piece_atv(sq) != ChessState.NONE:
		return true
	if sq == _state.ep_square and _selected.x >= 0:
		var mv: int = _state.piece_atv(_selected)
		if mv == ChessState.W_PAWN or mv == ChessState.B_PAWN:
			return true
	return false


func _draw_board_coordinates(lay: Dictionary) -> void:
	var font: Font = _ui_font if _ui_font != null else ThemeDB.fallback_font
	var cell: float = lay.cell
	var bw: float = lay.bw
	var origin: Vector2 = lay.origin
	var cfs := maxi(11, int(cell * 0.21))
	for sr in 8:
		var rank_label := str(8 - sr) if not _is_flipped() else str(sr + 1)
		_shaped_line.clear()
		_shaped_line.add_string(rank_label, font, cfs)
		var asc_r := _shaped_line.get_line_ascent()
		var desc_r := _shaped_line.get_line_descent()
		var w_r := _shaped_line.get_line_width()
		var row_cy := origin.y + sr * cell + cell * 0.5
		var y_r := row_cy - (desc_r - asc_r) * 0.5
		var x := origin.x - w_r - 6.0
		draw_string(font, Vector2(x, y_r), rank_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, COORD_GUTTER)
	for f in 8:
		var bf := f if not _is_flipped() else 7 - f
		var by := 0 if not _is_flipped() else 7
		var sq_bottom := Vector2i(bf, by)
		var col: Color = COORD_ON_LIGHT if _square_is_light(sq_bottom) else COORD_ON_DARK
		var file_label := String.chr(97 + bf)
		_shaped_line.clear()
		_shaped_line.add_string(file_label, font, cfs)
		var asc_f := _shaped_line.get_line_ascent()
		var desc_f := _shaped_line.get_line_descent()
		var w_f := _shaped_line.get_line_width()
		var file_cy := origin.y + bw + 10.0
		var y_f := file_cy - (desc_f - asc_f) * 0.5
		var cx := origin.x + f * cell + cell * 0.5 - w_f * 0.5
		draw_string(font, Vector2(cx, y_f), file_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, col)


func _draw_piece_texture(center: Vector2, piece: int) -> void:
	var t: Texture2D = _piece_tex.get(piece, null)
	if t == null:
		return
	var side := _cell * PIECE_SCALE_FRAC
	var rect := Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
	draw_texture_rect(t, rect, false)


func _gui_input(event: InputEvent) -> void:
	if _game_over or _state == null:
		return
	if _turn_mode != TurnMode.HUMAN_TURN:
		return
	if _cpu_enabled and _cpu_should_move_now():
		# Opponent 차례에는 입력 무시
		return
	if _awaiting_ai_pick:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sq := _screen_to_square(event.position)
		if sq.x < 0:
			return
		_handle_click(sq)
		accept_event()


func _screen_to_square(screen: Vector2) -> Vector2i:
	var lay := _board_layout()
	var c: float = lay.cell
	var bw: float = lay.bw
	var origin: Vector2 = lay.origin
	var local := screen - origin
	if local.x < 0 or local.y < 0 or local.x >= bw or local.y >= bw:
		return Vector2i(-1, -1)
	var f := int(local.x / c)
	var sr := int(local.y / c)
	if not _is_flipped():
		return Vector2i(f, 7 - sr)
	return Vector2i(7 - f, sr)


func _handle_click(sq: Vector2i) -> void:
	if _editor_active:
		_state.board[ChessState.idx(sq.x, sq.y)] = _editor_selected_piece
		_sync_editor_ui_from_state()
		queue_redraw()
		return
	var p := _state.piece_atv(sq)
	var my_white := _state.white_to_move
	if _selected.x >= 0:
		if _legals.has(sq):
			var moving := _state.piece_atv(_selected)
			if (moving == ChessState.W_PAWN and sq.y == 7) or (moving == ChessState.B_PAWN and sq.y == 0):
				_pending_from = _selected
				_pending_to = sq
				_promo.popup_centered()
				return
			_push_undo_snapshot()
			if _state.make_move(_selected, sq):
				_last_from = _selected
				_last_to = sq
				_record_uci_from_squares(_selected, sq)
				_finish_move()
			return
		if p != ChessState.NONE and ChessState.piece_color_white(p) == my_white:
			_selected = sq
			_legals = _state.legal_moves_from(sq)
			queue_redraw()
			return
		_selected = Vector2i(-1, -1)
		_legals.clear()
		queue_redraw()
		return
	if p != ChessState.NONE and ChessState.piece_color_white(p) == my_white:
		_selected = sq
		_legals = _state.legal_moves_from(sq)
		queue_redraw()


func _on_promo_choice(btn: Button) -> void:
	_promo.hide()
	var piece := ChessState.W_QUEEN
	var w := _state.white_to_move
	match btn.name:
		"Q":
			piece = ChessState.W_QUEEN if w else ChessState.B_QUEEN
		"R":
			piece = ChessState.W_ROOK if w else ChessState.B_ROOK
		"B":
			piece = ChessState.W_BISHOP if w else ChessState.B_BISHOP
		"N":
			piece = ChessState.W_KNIGHT if w else ChessState.B_KNIGHT
	_push_undo_snapshot()
	if _state.make_move(_pending_from, _pending_to, piece):
		_last_from = _pending_from
		_last_to = _pending_to
		_record_uci_from_squares(_pending_from, _pending_to, piece)
		_finish_move()


func _finish_move() -> void:
	_selected = Vector2i(-1, -1)
	_legals.clear()
	_refresh_ui()
	queue_redraw()
	_after_any_move()


func _record_uci_from_squares(from: Vector2i, to: Vector2i, promo_piece: int = ChessState.NONE) -> void:
	var promo := ""
	match promo_piece:
		ChessState.W_QUEEN, ChessState.B_QUEEN:
			promo = "q"
		ChessState.W_ROOK, ChessState.B_ROOK:
			promo = "r"
		ChessState.W_BISHOP, ChessState.B_BISHOP:
			promo = "b"
		ChessState.W_KNIGHT, ChessState.B_KNIGHT:
			promo = "n"
	_uci_history.append(UciMoves.move_to_uci(from, to, promo))


func _after_any_move() -> void:
	_clear_hint()
	if _state == null:
		return
	if _game_over:
		return
	# Opponent 차례면 다음 프레임에 처리(입력/팝업 흐름과 분리)
	if _cpu_enabled and _cpu_should_move_now():
		_turn_mode = TurnMode.ENGINE_THINKING
		if _opponent_mode == OpponentMode.AI:
			call_deferred("_ai_make_move")
		else:
			call_deferred("_cpu_make_move")


func _cpu_make_move() -> void:
	if _state == null or _game_over:
		_turn_mode = TurnMode.HUMAN_TURN
		return
	if not (_cpu_enabled and _cpu_should_move_now()):
		_turn_mode = TurnMode.HUMAN_TURN
		return
	if _opponent_mode != OpponentMode.CPU:
		_turn_mode = TurnMode.HUMAN_TURN
		return
	# 엔진 준비되면 실제 bestmove 요청, 아니면 mock으로 fallback.
	if _engine != null and _engine.is_ready():
		_engine.request_bestmove_from_fen(_state.fen(), _difficulty_ms)
		return
	_apply_cpu_move_uci(MockBestmove.choose_bestmove_uci(_state))


func _ai_make_move() -> void:
	if _state == null or _game_over:
		_turn_mode = TurnMode.HUMAN_TURN
		return
	if not (_opponent_mode == OpponentMode.AI and _cpu_should_move_now()):
		_turn_mode = TurnMode.HUMAN_TURN
		return
	if not _ai_sidecar_ready:
		_ensure_ai_sidecar()
		# Sidecar ready 후 _after_any_move 가 다시 호출됨.
		return
	if _engine != null and _engine.is_ready():
		_cand_purpose = "ai"
		_engine.request_candidates_from_fen(_state.fen(), _difficulty_ms)
		return
	# AI 모드에서는 엔진이 필수에 가깝다 — mock 대신 안내 후 중단.
	_chat_append_system("Stockfish가 준비되지 않아 AI 수를 둘 수 없습니다.")
	_turn_mode = TurnMode.HUMAN_TURN
	_update_engine_status()


func _on_engine_candidates(candidates: Array, bestmove: String) -> void:
	var purpose := _cand_purpose
	_cand_purpose = ""
	if purpose == "chat":
		_on_chat_candidates(candidates)
		return
	if purpose == "setup":
		_on_setup_candidates(candidates)
		return
	if _turn_mode != TurnMode.ENGINE_THINKING:
		return
	if _opponent_mode != OpponentMode.AI:
		return
	_ai_pending_candidates = candidates
	_ai_pending_bestmove = bestmove
	if candidates.is_empty() and not bestmove.is_empty():
		_ai_pending_candidates = [{"rank": 1, "uci": bestmove, "score_cp": 0, "mate": 0, "depth": 0}]
	if _ai_pending_candidates.is_empty():
		_chat_append_system("엔진 후보가 비어 있습니다.")
		_turn_mode = TurnMode.HUMAN_TURN
		return
	_awaiting_ai_pick = true
	_update_engine_status()
	var side := "white" if _state.white_to_move else "black"
	var last_human := ""
	if _uci_history.size() > 0:
		last_human = _uci_history[_uci_history.size() - 1]
	var hist := " ".join(_uci_history)
	if _ai != null:
		_ai.request_move(_state.fen(), side, _ai_pending_candidates, last_human, hist, _skill_level)


func _pick_skill_weighted_candidate(candidates: Array, skill_level: int) -> String:
	return MoveGate.pick_skill_weighted(candidates, skill_level)


func _on_ai_move_chosen(uci: String, reason: String, _reply: String, fallback: bool) -> void:
	if not _awaiting_ai_pick:
		return
	_awaiting_ai_pick = false
	# Gate 1 (sidecar): LLM pick must be one of the MultiPV candidates.
	var llm_uci := _ai.last_llm_uci if _ai != null else ""
	var side_gate := _ai.last_gate if _ai != null else ""
	if side_gate == "replaced":
		var side_log := "[GATE] SIDECAR  REPLACED proposed=%s applied=%s (후보 밖)" % [
			llm_uci if not llm_uci.is_empty() else "(none)", uci]
		print(side_log)
		_chat_append_system("게이트: AI 제안 %s는 엔진 후보가 아니라 %s로 교체" % [
			llm_uci if not llm_uci.is_empty() else "(파싱 실패)", uci])
	# Gate 2 (Godot): rules check via ChessState.make_move on a copy.
	# Opening-book moves may come from outside MultiPV, so this runs for every pick.
	var d := MoveGate.decide(_state, uci, _ai_pending_candidates, _ai_pending_bestmove, _skill_level)
	print(String(d.log))
	var pick := String(d.uci)
	if bool(d.replaced):
		fallback = true
		_chat_append_system("게이트: 수 %s는 규칙상 불가라 엔진 후보 %s로 교체" % [
			uci if not uci.is_empty() else "(없음)", pick])
	elif fallback and side_gate != "replaced" and reason.find("북") < 0 and not pick.is_empty():
		# Moves stay silent in chat — explanations only when the user asks via Send.
		_chat_append_system("폴백 적용: %s" % pick)
	_apply_cpu_move_uci(pick)
	_update_engine_status()


func _on_ai_chat_replied(reply: String, style_update: String, opening_name: String, book_lines: Array, board_fen: String = "") -> void:
	if not reply.is_empty():
		_chat_append_ai(reply)
		_set_position_status("코칭 완료", false)
	if not style_update.is_empty() and _ai != null:
		_ai.style_notes = style_update
		EngineSettings.save_string("ai", "style_notes", style_update)
	if not opening_name.is_empty() and _ai != null:
		_ai.opening_name = opening_name
		EngineSettings.save_string("ai", "opening_name", opening_name)
		_chat_append_system("오프닝: %s" % opening_name)
	if book_lines.size() > 0 and _ai != null:
		_ai.book_lines = book_lines
		_chat_append_system("오프닝 북 %d줄 적용" % book_lines.size())
	if not board_fen.is_empty():
		if _ai != null and not _ai.last_setup.is_empty():
			_verify_setup(board_fen, _ai.last_setup)
		else:
			_load_board_from_text(board_fen, false)
	elif _ai != null and not _ai.last_recommend_uci.is_empty():
		_show_recommendation(_ai.last_recommend_uci)


func _on_position_apply() -> void:
	if _position_paste == null:
		return
	_load_board_from_text(_position_paste.text, true)


func _on_position_coach() -> void:
	if _position_paste == null or _ai == null:
		return
	var raw := _position_paste.text.strip_edges()
	if raw.is_empty():
		_set_position_status("FEN/PGN을 붙여넣으세요.", true)
		return
	if not _load_board_from_text(raw, true):
		return
	# Keep the original PGN/FEN in the paste box for follow-up coaching.
	_position_paste.text = raw
	if not _ai_sidecar_ready:
		_ensure_ai_sidecar(true)
		_set_position_status("사이드카 준비 후 다시 코칭을 눌러 주세요.", true)
		_chat_append_system("코칭용 사이드카 준비 중…")
		return
	var coach_msg := (
		"다음 기보/포지션을 코칭해 주세요. "
		+ "국면 요약, 핵심 아이디어, 실수·더 나은 수, 이후 플랜을 한국어로 설명해 주세요. "
		+ "보드에는 이미 최종 포지션이 올라가 있으니 board_fen은 null로 두세요.\n\n"
		+ raw
	)
	_chat_append_user("이 기보 코칭해 줘")
	_set_position_status("코칭 요청 중…", false)
	var fen := _state.fen() if _state != null else ""
	var hist := " ".join(_uci_history)
	_ai.request_chat(fen, hist, coach_msg)


func _on_position_copy_fen() -> void:
	if _state == null or _position_paste == null:
		return
	_position_paste.text = _state.fen()
	_set_position_status("현재 보드 FEN을 넣었습니다.", false)


func _set_position_status(msg: String, is_error: bool) -> void:
	if _position_status == null:
		return
	_position_status.text = msg
	_position_status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.45, 0.45) if is_error else Color(0.65, 0.78, 0.55)
	)


func _load_board_from_text(text: String, from_position_panel: bool) -> bool:
	var loaded := _PgnFen.load_text(text)
	if not bool(loaded.get("ok", false)):
		var err := String(loaded.get("error", "불러오기 실패"))
		if from_position_panel:
			_set_position_status(err, true)
		else:
			_chat_append_system("보드 적용 실패: %s" % err)
		return false
	var fen := String(loaded.get("fen", ""))
	var hist: PackedStringArray = loaded.get("uci_history", PackedStringArray())
	var res := _state.load_fen(fen)
	if not bool(res.get("ok", false)):
		var err2 := String(res.get("error", "invalid fen"))
		if from_position_panel:
			_set_position_status(err2, true)
		else:
			_chat_append_system("보드 FEN 적용 실패: %s" % err2)
		return false
	_selected = Vector2i(-1, -1)
	_legals.clear()
	_last_from = Vector2i(-1, -1)
	_last_to = Vector2i(-1, -1)
	_game_over = false
	_turn_mode = TurnMode.HUMAN_TURN
	_awaiting_ai_pick = false
	_ai_pending_candidates = []
	_ai_pending_bestmove = ""
	_hint_from = Vector2i(-1, -1)
	_hint_to = Vector2i(-1, -1)
	_uci_history = hist
	_undo_stack.clear()
	_promo.hide()
	if _ai != null:
		_ai.opening_name = ""
		_ai.book_lines = []
		EngineSettings.save_string("ai", "opening_name", "")
	# Keep PGN text visible when loading from the position panel; only replace pure FEN loads.
	if _position_paste != null and (not from_position_panel or hist.size() == 0):
		_position_paste.text = fen
	var note := "보드 적용"
	if hist.size() > 0:
		note = "보드 적용 (PGN %d수)" % hist.size()
	if from_position_panel:
		_set_position_status(note, false)
		_chat_append_system(note)
	else:
		_chat_append_system(note)
	_refresh_ui()
	queue_redraw()
	if _cpu_enabled:
		_after_any_move()
	return true


func _on_ai_request_failed(kind: String, message: String) -> void:
	_chat_append_system("AI(%s) 오류: %s" % [kind, message])
	if kind == "move" and _awaiting_ai_pick:
		_awaiting_ai_pick = false
		var pick := _pick_skill_weighted_candidate(_ai_pending_candidates, _skill_level)
		if pick.is_empty():
			pick = _ai_pending_bestmove
		_chat_append_system("사이드카 실패 → 난이도 가중 후보 폴백")
		_apply_cpu_move_uci(pick)
	_update_engine_status()


func _chat_append_system(msg: String) -> void:
	if _chat_log == null:
		return
	_chat_log.append_text("\n[color=#9E9E9E]%s[/color]" % msg)


func _chat_append_user(msg: String) -> void:
	if _chat_log == null:
		return
	_chat_log.append_text("\n[color=#81B64C]나:[/color] %s" % msg)


func _chat_append_ai(msg: String) -> void:
	if _chat_log == null:
		return
	_chat_log.append_text("\n[color=#CDD26A]AI:[/color] %s" % msg)


func _on_chat_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER and key.ctrl_pressed:
			_on_chat_send()
			_chat_input.accept_event()


func _on_chat_send() -> void:
	if _ai == null:
		return
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	_chat_input.text = ""
	_chat_append_user(msg)
	if _opponent_mode == OpponentMode.AI and not _ai_sidecar_ready:
		_ensure_ai_sidecar()
		_chat_append_system("사이드카 준비 후 다시 전송해 주세요.")
		return
	var fen := _state.fen() if _state != null else ""
	var hist := " ".join(_uci_history)
	_setup_request_msg = msg
	_setup_retry_left = 1
	_clear_hint()
	if _can_analyze_for_chat():
		# Get full-strength engine candidates for the user's side first, so any move
		# the agent recommends can be gated against them.
		_chat_pending_msg = msg
		_chat_pending_fen = fen
		_cand_purpose = "chat"
		_turn_mode = TurnMode.CHAT_ANALYZING
		_engine.request_analysis_from_fen(fen, 300, 5)
		return
	_ai.request_chat(fen, hist, msg)


func _can_analyze_for_chat() -> bool:
	if _engine == null or not _engine.is_ready() or _state == null:
		return false
	if _game_over or _editor_active or _awaiting_ai_pick:
		return false
	if _turn_mode != TurnMode.HUMAN_TURN:
		return false
	if _cpu_enabled and _cpu_should_move_now():
		return false
	return _state.has_any_legal_move(_state.white_to_move)


func _on_chat_candidates(candidates: Array) -> void:
	_turn_mode = TurnMode.HUMAN_TURN
	if _ai == null:
		return
	var side := "white" if _state.white_to_move else "black"
	_ai.request_chat(_chat_pending_fen, " ".join(_uci_history), _chat_pending_msg, candidates, side)


func _clear_hint() -> void:
	if _hint_from.x < 0 and _hint_to.x < 0:
		return
	_hint_from = Vector2i(-1, -1)
	_hint_to = Vector2i(-1, -1)
	queue_redraw()


func _show_recommendation(rec: String) -> void:
	# Gate 2 for recommendations: the sidecar already limited it to engine candidates
	# (or the next book move); the rules decide whether it is shown on the board.
	var fen := _state.fen()
	if not MoveGate.is_legal_uci(_state, rec):
		print("[GATE] GODOT    REC-ILLEGAL proposed=%s fen=%s" % [rec, fen])
		_chat_append_system("게이트: 추천 수 %s는 규칙상 둘 수 없어 표시하지 않습니다" % rec)
		return
	print("[GATE] GODOT    REC-PASS  proposed=%s gate=%s fen=%s" % [rec, _ai.last_recommend_gate, fen])
	var parsed := UciMoves.parse_uci_move(rec)
	_hint_from = parsed.from
	_hint_to = parsed.to
	queue_redraw()
	var tag := "엔진 후보"
	match _ai.last_recommend_gate:
		"book":
			tag = "오프닝 북"
		"replaced":
			tag = "에이전트 제안 %s → 엔진 1위로 교체" % _ai.last_recommend_llm_uci
		"filled":
			tag = "엔진 1위"
	_chat_append_system("추천 수: %s (%s, 보드에 파란색 표시)" % [rec, tag])


func _verify_setup(fen: String, setup: Dictionary) -> void:
	var material := String(setup.get("material", ""))
	var v := MoveGate.validate_setup(fen, material)
	print("[GATE] SETUP    RULES %s fen=%s claimed=%s actual=%s %s" % [
		"PASS" if bool(v.ok) else "REJECT", fen, material, v.material, v.error])
	if not bool(v.ok):
		_setup_reject(String(v.error), fen)
		return
	var goal := String(setup.get("goal", "practice"))
	var engine_free := _engine != null and _engine.is_ready() and _turn_mode == TurnMode.HUMAN_TURN and not _awaiting_ai_pick
	if (goal == "mate" or goal == "endgame") and engine_free:
		_setup_pending = {"fen": fen, "setup": setup}
		_cand_purpose = "setup"
		_turn_mode = TurnMode.CHAT_ANALYZING
		_chat_append_system("포지션 검증 중… (규칙 통과, 엔진 확인)")
		_engine.request_analysis_from_fen(fen, 1500, 1)
		return
	_apply_setup(fen, setup, "규칙 검사만 통과 (엔진 확인 생략)")


func _on_setup_candidates(candidates: Array) -> void:
	_turn_mode = TurnMode.HUMAN_TURN
	var fen := String(_setup_pending.get("fen", ""))
	var setup: Dictionary = _setup_pending.get("setup", {})
	_setup_pending = {}
	var top: Dictionary = candidates[0] if candidates.size() > 0 else {}
	var r := MoveGate.check_setup_engine(String(setup.get("goal", "")), int(setup.get("mate_in", 0)), top)
	print("[GATE] SETUP    ENGINE %s goal=%s mate_in=%d engine=%s fen=%s" % [
		"PASS" if bool(r.ok) else "REJECT", setup.get("goal", ""), int(setup.get("mate_in", 0)), r.seen, fen])
	if not bool(r.ok):
		_setup_reject(String(r.error), fen)
		return
	_apply_setup(fen, setup, "엔진 확인: %s" % r.seen)


func _setup_reject(why: String, fen: String = "") -> void:
	_chat_append_system("게이트: 에이전트가 만든 포지션을 보드에 올리지 않았습니다 — %s" % why)
	if _setup_retry_left > 0 and _ai != null and not _setup_request_msg.is_empty():
		_setup_retry_left -= 1
		_chat_append_system("같은 요청으로 한 번 더 만들어 달라고 합니다…")
		var retry := "%s\n\n[자동 재요청] 방금 만든 FEN '%s'은 검증에 실패했습니다: %s. 같은 요청에 맞게 규칙을 지킨 포지션을 다시 세팅해 주세요." % [
			_setup_request_msg, fen, why]
		_ai.request_chat(_state.fen(), " ".join(_uci_history), retry)
	else:
		_chat_append_system("포지션 세팅을 포기했습니다. 요청을 바꿔 다시 시도해 주세요.")


func _apply_setup(fen: String, setup: Dictionary, note: String) -> void:
	var stm_white := fen.strip_edges().split(" ", false)[1] == "w"
	# The user practices the side to move; the opponent (CPU/AI) defends.
	_player_side_mode = PlayerSide.WHITE if stm_white else PlayerSide.BLACK
	_player_side.select(_player_side_mode)
	EngineSettings.save_int("player", "side", _player_side_mode)
	if not _load_board_from_text(fen, false):
		return
	var v := MoveGate.validate_setup(fen)
	print("[GATE] SETUP    APPLIED name=%s material=%s %s fen=%s" % [setup.get("name", ""), v.material, note, fen])
	var src := "검증된 카탈로그" if String(setup.get("source", "")) == "catalog" else "에이전트가 만든 포지션"
	_chat_append_system("게이트 통과: %s (%s, %s, %s). %s 차례입니다." % [
		String(setup.get("name", "포지션")), src, v.material, note, "백(당신)" if stm_white else "흑(당신)"])


func _apply_cpu_move_uci(uci: String) -> void:
	if uci.is_empty():
		_refresh_ui()
		_turn_mode = TurnMode.HUMAN_TURN
		return
	_turn_mode = TurnMode.ENGINE_MOVE_APPLYING
	var parsed := UciMoves.parse_uci_move(uci)
	if not bool(parsed.get("ok", false)):
		push_error("CPU move: invalid uci '%s'" % uci)
		_turn_mode = TurnMode.HUMAN_TURN
		return
	_push_undo_snapshot()
	var promo_piece := ChessState.W_QUEEN
	var promo := String(parsed.get("promo", ""))
	if not promo.is_empty():
		var w := _state.white_to_move
		match promo:
			"q":
				promo_piece = ChessState.W_QUEEN if w else ChessState.B_QUEEN
			"r":
				promo_piece = ChessState.W_ROOK if w else ChessState.B_ROOK
			"b":
				promo_piece = ChessState.W_BISHOP if w else ChessState.B_BISHOP
			"n":
				promo_piece = ChessState.W_KNIGHT if w else ChessState.B_KNIGHT
	if _state.make_move(parsed.from, parsed.to, promo_piece):
		_last_from = parsed.from
		_last_to = parsed.to
	_uci_history.append(uci)
	_turn_mode = TurnMode.HUMAN_TURN
	_finish_move()


func _on_engine_bestmove(uci: String) -> void:
	if _turn_mode != TurnMode.ENGINE_THINKING:
		return
	if _opponent_mode != OpponentMode.CPU:
		return
	_apply_cpu_move_uci(uci)


func _on_engine_error(_msg: String) -> void:
	# 엔진 실패 시에는 mock으로 계속 진행할 수 있어야 함.
	_last_engine_error = _msg
	if _turn_mode == TurnMode.CHAT_ANALYZING:
		var purpose := _cand_purpose
		_cand_purpose = ""
		_turn_mode = TurnMode.HUMAN_TURN
		if purpose == "chat" and _ai != null:
			# No candidates → the sidecar cannot gate a recommendation, so it won't make one.
			_ai.request_chat(_chat_pending_fen, " ".join(_uci_history), _chat_pending_msg)
		elif purpose == "setup":
			_setup_reject("엔진 검증 실패: %s" % _msg)
	_update_engine_status()


func _cycle_opponent_mode() -> void:
	_opponent_mode = (_opponent_mode + 1) % 3
	_cpu_enabled = _opponent_mode != OpponentMode.OFF
	_sync_opponent_button()
	EngineSettings.save_int("opponent", "mode", _opponent_mode)
	EngineSettings.save_bool("cpu", "enabled", _opponent_mode == OpponentMode.CPU)
	_awaiting_ai_pick = false
	if _cpu_enabled:
		_engine.start(_engine_path)
		if _opponent_mode == OpponentMode.AI:
			_ensure_ai_sidecar()
	else:
		if _engine != null:
			_engine.stop()
		_ai_sidecar_ready = false
		_ai_sidecar_starting = false
	_last_engine_error = ""
	_update_engine_status()
	_after_any_move()


func _ensure_ai_sidecar(force: bool = false) -> void:
	if _opponent_mode != OpponentMode.AI and not force:
		return
	if _ai_sidecar_ready:
		if _ai != null:
			_ai.ensure_session()
		return
	if _ai_sidecar_starting:
		return
	_ai_sidecar_starting = true
	_ai_health_tries = 0
	_chat_append_system("AI 사이드카 확인 중…")
	_update_engine_status()
	# First AI enable this session: kill stale uvicorn so new openings/.env load.
	if not _ai_sidecar_bootstrapped and _ai_proc != null:
		_ai_sidecar_bootstrapped = true
		_chat_append_system("사이드카를 최신 코드로 재시작…")
		var r: Dictionary = _ai_proc.restart_fresh()
		if not bool(r.get("ok", false)):
			_chat_append_system(String(r.get("message", "사이드카 재시작 실패")))
	_ping_ai_health()


func _ping_ai_health() -> void:
	if _ai_health_http == null or _ai == null:
		return
	var url := _ai.base_url.rstrip("/") + "/health"
	var err := _ai_health_http.request(url)
	if err != OK:
		_on_ai_health_unavailable()


func _on_ai_health_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _opponent_mode != OpponentMode.AI:
		_ai_sidecar_starting = false
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var text := body.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		var rev := 0
		if typeof(parsed) == TYPE_DICTIONARY:
			rev = int(parsed.get("code_rev", 0))
		# Stale server without new openings / book logic.
		if rev < _AI_SIDECAR_CODE_REV and _ai_proc != null:
			_chat_append_system("사이드카 버전이 오래됨(rev %d) → 재시작" % rev)
			_ai_sidecar_ready = false
			var r2: Dictionary = _ai_proc.restart_fresh()
			if bool(r2.get("ok", false)):
				_ai_health_tries = 0
				get_tree().create_timer(0.6).timeout.connect(_ping_ai_health, CONNECT_ONE_SHOT)
				return
			_ai_sidecar_starting = false
			_chat_append_system(String(r2.get("message", "재시작 실패")))
			_update_engine_status()
			return
		_ai_sidecar_ready = true
		_ai_sidecar_starting = false
		if typeof(parsed) == TYPE_DICTIONARY and bool(parsed.get("api_key_placeholder", false)):
			_chat_append_system("사이드카 준비됨 — .env 의 CURSOR_API_KEY 가 placeholder입니다. 실제 키로 고친 뒤 상대:AI를 다시 켜세요.")
		elif typeof(parsed) == TYPE_DICTIONARY and bool(parsed.get("mock", false)):
			_chat_append_system("사이드카 준비됨 (mock 모드)")
		else:
			_chat_append_system("사이드카 준비됨")
		_update_engine_status()
		if _ai != null:
			_ai.ensure_session()
		call_deferred("_after_any_move")
		return
	_on_ai_health_unavailable()


func _on_ai_health_unavailable() -> void:
	if _opponent_mode != OpponentMode.AI:
		_ai_sidecar_starting = false
		return
	# First failure: try to spawn; then keep polling.
	if _ai_health_tries == 0 and _ai_proc != null and not _ai_proc.is_owned_running():
		var r: Dictionary = _ai_proc.restart_fresh()
		if bool(r.get("ok", false)):
			_chat_append_system("사이드카 자동 시작… (잠시만)")
		else:
			_ai_sidecar_starting = false
			_ai_sidecar_ready = false
			_chat_append_system(String(r.get("message", "사이드카 시작 실패")))
			_update_engine_status()
			return
	_ai_health_tries += 1
	if _ai_health_tries >= _AI_HEALTH_MAX_TRIES:
		_ai_sidecar_starting = false
		_ai_sidecar_ready = false
		_chat_append_system(
			"사이드카가 응답하지 않습니다. ai_sidecar에서 `pip install -r requirements.txt` 후 게임을 다시 켜거나, sidecar.log 를 확인하세요."
		)
		_update_engine_status()
		return
	get_tree().create_timer(0.5).timeout.connect(_ping_ai_health, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	if _engine != null:
		_engine.stop()
	if _ai_proc != null:
		_ai_proc.stop_if_owned()


func _cpu_should_move_now() -> bool:
	if _state == null:
		return false
	if _editor_active:
		return false
	if not _cpu_enabled:
		return false
	# CPU가 켜져 있어도, 엔진이 준비되지 않았으면(연결중/에러) 자동 수를 두지 않는다.
	# UI 테스트/초기 부팅 타이밍에서 mock fallback이 끼어드는 걸 방지.
	if _engine == null or not _engine.is_ready():
		return false
	var player_is_white := (_player_side_mode == PlayerSide.WHITE)
	# CPU is always the opponent of the player.
	return _state.white_to_move != player_is_white


func _on_player_side_selected(idx: int) -> void:
	_player_side_mode = clampi(idx, 0, 1)
	EngineSettings.save_int("player", "side", _player_side_mode)
	# Side choice affects board orientation; restart to keep UX clear.
	_new_game()


func _is_flipped() -> bool:
	# If the player chooses black, black should be at the bottom.
	return _player_side_mode == PlayerSide.BLACK


func _apply_lichess_level(level: int) -> void:
	# Lichess-style mapping (commonly cited fishnet defaults)
	# levels: 1..8
	var skill := [0, 3, 6, 10, 14, 16, 18, 20]
	var times := [50, 100, 150, 200, 300, 400, 500, 1000]
	var depths := [1, 1, 2, 3, 5, 8, 13, 22]
	var idx := clampi(level - 1, 0, 7)
	_lichess_level = idx + 1
	_skill_level = int(skill[idx])
	_difficulty_ms = int(times[idx])
	_max_depth = int(depths[idx])
	_apply_engine_strength(_skill_level, _difficulty_ms, _max_depth)
	_sync_settings_ui_from_values()


func _sync_settings_ui_from_values() -> void:
	if _settings_skill == null or _settings_movetime == null or _settings_max_depth == null:
		return
	_syncing_settings_ui = true
	_settings_skill.value = float(_skill_level)
	_settings_movetime.value = float(_difficulty_ms)
	_settings_max_depth.value = float(_max_depth)
	_syncing_settings_ui = false


func _open_settings() -> void:
	_settings_popup.popup_centered()


func _on_level_selected(idx: int) -> void:
	_apply_lichess_level(idx + 1)
	EngineSettings.save_int("cpu", "lichess_level", _lichess_level)


func _apply_engine_strength(skill_level: int, movetime_ms: int, max_depth: int) -> void:
	_skill_level = clampi(skill_level, 0, 20)
	_difficulty_ms = maxi(10, movetime_ms)
	_max_depth = maxi(0, max_depth)
	if _engine != null:
		_engine.set_strength(_skill_level, _max_depth)


func _on_skill_changed(v: float) -> void:
	if _syncing_settings_ui:
		return
	_apply_engine_strength(int(v), _difficulty_ms, _max_depth)
	EngineSettings.save_int("cpu", "skill_level", _skill_level)


func _on_movetime_changed(v: float) -> void:
	if _syncing_settings_ui:
		return
	_apply_engine_strength(_skill_level, int(v), _max_depth)
	EngineSettings.save_int("cpu", "movetime_ms", _difficulty_ms)


func _on_max_depth_changed(v: float) -> void:
	if _syncing_settings_ui:
		return
	_apply_engine_strength(_skill_level, _difficulty_ms, int(v))
	EngineSettings.save_int("cpu", "max_depth", _max_depth)
