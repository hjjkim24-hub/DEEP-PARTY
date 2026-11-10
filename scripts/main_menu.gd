extends Control
## 메인 메뉴: 왼쪽에 로고 + 메뉴, 오른쪽에 바다 밑에 가라앉은 보드게임 판.
## 색은 바다에 맞춰 진주빛 흰색 / 아쿠아 / 깊은 청록 세 가지로 통일 (반투명 유리 느낌).
## 화면 구성은 전부 코드로 만들어져 있어서, 메뉴 항목·색·문구는 아래 상수만 고치면 돼요.
## 모든 조작은 마우스(클릭, 드래그)로 해요.

const BackgroundScene := preload("res://scenes/underwater_background.tscn")
const TitleLogo := preload("res://scripts/ui/title_logo.gd")
const ModeIcon := preload("res://scripts/ui/mode_icon.gd")
const ToggleSwitch := preload("res://scripts/ui/toggle_switch.gd")
const LobbyPawn := preload("res://scripts/ui/lobby_pawn.gd")
const ItemIcon := preload("res://scripts/ui/item_icon.gd")
const BoardBoxView := preload("res://scripts/ui/board_box_view.gd")
const UIFont := preload("res://fonts/Poppins-Bold.ttf")

const GAME_TITLE := "DEEP\nPARTY"
const GAME_SUBTITLE := "UP TO 4 PLAYERS  •  MINIGAME PARTY"
const VERSION_TEXT := "v0.1.0  •  Dev Build"
## 한글 등 Poppins 에 없는 글자를 그릴 시스템 폰트 (출시 전에는 한글 폰트 파일을 넣어 교체하세요)
const FALLBACK_FONTS := ["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "NanumGothic"]
const SETTINGS_TABS := ["AUDIO", "VIDEO", "LANGUAGE"]
const GAME_SCENE := "res://scenes/board.tscn"  ## 아직 없음 - 만들면 보드 고르기에서 PLAY 를 누를 때 넘어가요

## 보드 고르기 화면에 나오는 보드게임 상자들 (상자 그림은 tools/render_boardbox.py)
const BOARDS := [
	{
		"id": "sunken_isles",
		"name": "SUNKEN ISLES",
		"desc": "Islands scattered across the seabed. Roll the dice, hop from island to island and win minigames to come out on top!",
		"tags": ["1-4 PLAYERS", "ALL MODES"],
		"box": preload("res://textures/boards/sunken_isles_box.png"),
		"locked": false,
	},
	{
		"id": "",
		"name": "COMING SOON",
		"desc": "A new board is on the way. Stay tuned!",
		"tags": [],
		"box": preload("res://textures/boards/locked_box.png"),
		"locked": true,
	},
	{
		"id": "",
		"name": "COMING SOON",
		"desc": "A new board is on the way. Stay tuned!",
		"tags": [],
		"box": preload("res://textures/boards/locked_box.png"),
		"locked": true,
	},
]


const LEFT_MARGIN := 120      ## 화면 왼쪽 여백
const COLUMN_WIDTH := 660     ## 왼쪽 메뉴 영역 폭

## 색 (바다 팔레트)
const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const GLASS := Color(0.02, 0.17, 0.16, 0.52)
const GLASS_HOVER := Color(0.08, 0.40, 0.36, 0.58)
const GLASS_PRESSED := Color(0.03, 0.26, 0.24, 0.7)
const GLASS_BORDER := Color(0.65, 1.0, 0.92, 0.22)
const TEXT_DIM := Color(0.75, 0.95, 0.9, 0.78)

const MENU_ITEMS := [
	{"id": "play", "text": "PLAY"},
	{"id": "collection", "text": "MINIGAMES"},
	{"id": "settings", "text": "SETTINGS"},
	{"id": "quit", "text": "QUIT"},
]

## mode 값은 GameState.Mode 와 같아요 (0 개인전, 1 팀전, 2 협동)
const MODE_CARDS := [
	{"mode": 0, "title": "FREE-FOR-ALL", "desc": "Every player for themselves.\nOnly one takes the crown!"},
	{"mode": 1, "title": "2 VS 2", "desc": "Team up in pairs and\noutplay the other side!"},
	{"mode": 2, "title": "CO-OP", "desc": "All four work together\nto clear every minigame!"},
]

var _bg
var _logo
var _spaced_font: FontVariation
var _pages := {}
var _current := ""
var _busy := false
var _main_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _last_main_button: Button
var _settings_first: Control
var _settings_tab := 0
var _tab_buttons: Array[Button] = []
var _tab_pages: Array[Control] = []
var _vol_sliders := {}
var _vol_values := {}
var _mode_seg: HBoxContainer
var _lang_seg: HBoxContainer
var _res_drop: OptionButton
var _fps_drop: OptionButton
var _vsync_switch: Button
var _grabber_tex: ImageTexture
var _res_note: Label
var _res_list: Array[Vector2i] = []
var _lobby_mode_label: Label
var _lobby_slots: HBoxContainer
var _lobby_start: Button
var _lobby_hint: Label
var _cz_pawn
var _cz_color_name: Label
var _cz_swatches: Array[Button] = []
var _cz_tab := 0
var _cz_tab_buttons: Array[Button] = []
var _cz_tab_pages: Array[Control] = []
# 보드 고르기
var _board_index := 0
var _board_big: BoardBoxView
var _board_name: Label
var _board_desc: Label
var _board_tags: HBoxContainer
var _board_thumbs: Array[Button] = []
var _board_play: Button
var _board_hint: Label
var _board_mode_label: Label
var _cz_tiles := {}     # 종류 -> [아이템 칸 버튼들]
var _cz_remove := {}    # 종류 -> 제거 버튼
const CZ_TABS := ["COLOR", "HAT", "PATTERN", "ACCESSORY", "OUTFIT"]
const CZ_CATEGORY := ["", "hat", "pattern", "accessory", "outfit"]
const CZ_CAPTION := ["PICK YOUR COLOR", "PICK A HAT", "PICK A PATTERN", "PICK AN ACCESSORY", "PICK AN OUTFIT"]
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _fade: ColorRect


func _ready() -> void:
	_build_theme()
	Audio.play_music()

	_bg = BackgroundScene.instantiate()
	add_child(_bg)

	var ui := Control.new()
	add_child(ui)
	_full_rect(ui, "UI")
	_build_left_shade(ui)

	_pages["main"] = _build_main_page(ui)
	_pages["mode"] = _build_mode_page(ui)
	_pages["settings"] = _build_settings_page(ui)
	_pages["lobby"] = _build_lobby_page(ui)
	_pages["customize"] = _build_customize_page(ui)
	_pages["board"] = _build_board_page(ui)
	_build_footer(ui)
	_build_toast(ui)

	_fade = ColorRect.new()
	add_child(_fade)
	_full_rect(_fade, "Fade")
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)

	_pages["mode"].hide()
	_pages["settings"].hide()
	_pages["lobby"].hide()
	_pages["customize"].hide()
	_pages["board"].hide()
	_play_intro()


# =============================================================== 화면 만들기

func _build_theme() -> void:
	var th := Theme.new()
	th.default_font = UIFont
	th.default_font_size = 28
	th.set_color("font_color", "Label", PEARL)
	theme = th
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(FALLBACK_FONTS)
	fb.font_weight = 700
	var ui_font: Font = UIFont
	var fbs: Array[Font] = [fb]
	ui_font.fallbacks = fbs
	_spaced_font = FontVariation.new()
	_spaced_font.base_font = UIFont
	_spaced_font.spacing_glyph = 3


## 메뉴 글씨가 잘 보이도록 왼쪽을 살짝 어둡게
func _build_left_shade(parent: Control) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.07, 0.06, 0.62))
	g.set_color(1, Color(0.0, 0.07, 0.06, 0.0))
	g.set_offset(1, 1.0)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	tex.width = 256
	tex.height = 4
	var shade := TextureRect.new()
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.name = "LeftShade"
	parent.add_child(shade)
	shade.anchor_right = 0.55
	shade.anchor_bottom = 1.0


func _full_rect(c: Control, node_name: String) -> void:
	c.name = node_name
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 왼쪽 정렬된 세로 줄을 가진 페이지를 만들어요
func _make_left_page(parent: Control, node_name: String, separation: int) -> VBoxContainer:
	var page := Control.new()
	parent.add_child(page)
	_full_rect(page, node_name)
	var margin := MarginContainer.new()
	page.add_child(margin)
	_full_rect(margin, "Margin")
	margin.add_theme_constant_override("margin_left", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 70)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	col.add_theme_constant_override("separation", separation)
	margin.add_child(col)
	return col


func _build_main_page(parent: Control) -> Control:
	var col := _make_left_page(parent, "MainPage", 14)

	_logo = TitleLogo.new()
	_logo.text = GAME_TITLE
	_logo.custom_minimum_size = Vector2(COLUMN_WIDTH, 330)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_logo)

	var sub := _pill_label(GAME_SUBTITLE, 22)
	sub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(sub)

	col.add_child(_spacer(26))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(box)
	for item in MENU_ITEMS:
		var b := _make_glass_button(item["text"], Vector2(440, 74), 28)
		b.pressed.connect(_on_menu_pressed.bind(item["id"], b))
		box.add_child(b)
		_main_buttons.append(b)
	return col.get_parent().get_parent() as Control


func _build_mode_page(parent: Control) -> Control:
	var col := _make_left_page(parent, "ModePage", 22)

	var header := _header("CHOOSE A MODE", 54)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(header)
	col.add_child(_spacer(6))

	for data in MODE_CARDS:
		var b := _make_mode_card(data)
		col.add_child(b)
		_mode_buttons.append(b)

	col.add_child(_spacer(8))
	var back := _make_glass_button("BACK", Vector2(240, 64), 24)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_go_back)
	back.set_meta("sfx", "back")
	col.add_child(back)
	return col.get_parent().get_parent() as Control


# =============================================================== 로비 (방)
## 모드를 고르면 방이 만들어지고, 빈자리에 CPU를 넣거나 친구를 초대해요.

func _build_lobby_page(parent: Control) -> Control:
	# 로비는 화면 전체를 써요: 위에 제목, 가운데 큰 카드 4장, 아래 왼쪽 BACK·INVITE / 오른쪽 START
	var page := Control.new()
	parent.add_child(page)
	_full_rect(page, "LobbyPage")
	var margin := MarginContainer.new()
	page.add_child(margin)
	_full_rect(margin, "Margin")
	margin.add_theme_constant_override("margin_left", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_right", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 76)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 28)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	head.add_child(_header("LOBBY", 54))
	var pill := _pill_label("", 20)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pill)
	_lobby_mode_label = pill.get_child(0) as Label

	_lobby_slots = HBoxContainer.new()
	_lobby_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_slots.add_theme_constant_override("separation", 24)
	col.add_child(_lobby_slots)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	var back := _make_glass_button("BACK", Vector2(170, 66), 20)
	back.pressed.connect(_go_back)
	back.set_meta("sfx", "back")
	bottom.add_child(back)
	var invite := _make_glass_button("INVITE FRIEND", Vector2(250, 66), 20)
	invite.pressed.connect(_lobby_invite)
	bottom.add_child(invite)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	_lobby_hint = Label.new()
	_lobby_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lobby_hint.add_theme_font_size_override("font_size", 18)
	_lobby_hint.add_theme_color_override("font_color", TEXT_DIM)
	bottom.add_child(_lobby_hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	bottom.add_child(gap)
	_lobby_start = _make_primary_button("START", Vector2(240, 66))
	_lobby_start.pressed.connect(_on_lobby_start)
	_lobby_start.set_meta("sfx", "")   # 시작 가능할 때만 "start" (아래에서)
	bottom.add_child(_lobby_start)
	return page


## 꽉 찬 아쿠아색 버튼 (가장 중요한 버튼용)
func _make_primary_button(text: String, min_size: Vector2) -> Button:
	var b := _make_glass_button(text, min_size, 22)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.set_meta("pivot_left", false)
	var on := _glass_box(Color(AQUA, 0.92), AQUA, 1)
	var on_h := _glass_box(Color("a6f7e8"), Color.WHITE, 1)
	var off := _glass_box(Color(0.02, 0.12, 0.11, 0.45), Color(AQUA, 0.12), 1)
	for box in [on, on_h, off]:
		box.content_margin_left = 16
		box.content_margin_right = 16
	b.add_theme_stylebox_override("normal", on)
	b.add_theme_stylebox_override("hover", on_h)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on_h)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, DEEP)
	b.add_theme_color_override("font_disabled_color", Color(PEARL, 0.3))
	return b


func _open_lobby(mode: int) -> void:
	GameState.set_mode(mode)
	GameState.reset_lobby()
	_lobby_mode_label.text = GameState.get_mode_name(mode)
	_refresh_lobby()
	_show_page("lobby")


func _refresh_lobby() -> void:
	for c in _lobby_slots.get_children():
		_lobby_slots.remove_child(c)
		c.queue_free()
	var team := GameState.selected_mode == GameState.Mode.TEAM_2V2
	var cpu_no := 0
	for i in GameState.MAX_PLAYERS:
		var p: Dictionary = GameState.players[i]
		if p.get("kind", "") == "cpu":
			cpu_no += 1
		if team and i == 2:
			var team_gap := Control.new()
			team_gap.custom_minimum_size = Vector2(24, 0)
			_lobby_slots.add_child(team_gap)
		_lobby_slots.add_child(_make_slot(i, p, cpu_no, team))
	_lobby_start.disabled = not GameState.can_start()
	if GameState.can_start():
		_lobby_hint.text = "Ready to start!"
	elif team:
		_lobby_hint.text = "2 VS 2 needs all four seats filled."
	else:
		_lobby_hint.text = "Add at least one more player to start."


## 세로로 긴 플레이어 카드 (말을 크게 보여줌)
func _make_slot(i: int, p: Dictionary, cpu_no: int, team: bool) -> PanelContainer:
	var kind: String = p.get("kind", "")
	var filled := kind != ""
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg := _glass_box(Color(0.02, 0.15, 0.14, 0.74) if filled else Color(0.02, 0.12, 0.11, 0.55),
		Color(AQUA, 0.3) if kind == "host" else (GLASS_BORDER if filled else Color(AQUA, 0.12)), 2 if kind == "host" else 1, 24)
	bg.set_content_margin_all(22)
	card.add_theme_stylebox_override("panel", bg)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	# 위: 번호 + 팀/역할
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var badge := Label.new()
	badge.text = "P%d" % (i + 1)
	badge.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	badge.custom_minimum_size = Vector2(52, 52)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", DEEP if filled else Color(PEARL, 0.4))
	var bs := StyleBoxFlat.new()
	var pcol := GameState.player_color(i)
	bs.bg_color = Color(pcol, 0.95) if filled else Color(1, 1, 1, 0.06)
	bs.set_corner_radius_all(26)
	badge.add_theme_stylebox_override("normal", bs)
	top.add_child(badge)
	if team:
		var tl := _caption("TEAM A" if i < 2 else "TEAM B")
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tl)

	# 가운데: 큰 말
	var pawn = LobbyPawn.new()
	pawn.color = pcol
	pawn.look = GameState.look(i)
	pawn.empty = not filled
	pawn.custom_minimum_size = Vector2(0, 340)
	pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pawn)

	# 이름
	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_override("font", _spaced_font)
	name_l.add_theme_font_size_override("font_size", 30)
	var sub_l := Label.new()
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_l.add_theme_font_size_override("font_size", 16)
	sub_l.add_theme_color_override("font_color", TEXT_DIM)
	v.add_child(name_l)
	v.add_child(sub_l)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(push)

	# 아래: 버튼
	match kind:
		"host":
			name_l.text = "You"
			sub_l.text = "Host"
			var cz := _make_slot_button("CUSTOMIZE")
			cz.pressed.connect(_lobby_customize)
			v.add_child(cz)
		"cpu":
			name_l.text = tr("CPU %d") % cpu_no
			name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			sub_l.text = "Computer player"
			var lv := _make_segmented(["Easy", "Normal", "Hard"], int(p.get("level", 1)), func(lvl: int) -> void: _lobby_set_level(i, lvl))
			lv.add_theme_constant_override("separation", 4)
			for b in lv.get_meta("buttons"):
				b.custom_minimum_size = Vector2(0, 48)
				b.add_theme_font_size_override("font_size", 16)
			v.add_child(lv)
			var rm := _make_slot_button("REMOVE")
			rm.pressed.connect(_lobby_remove.bind(i))
			rm.set_meta("sfx", "remove")
			v.add_child(rm)
		"friend":
			name_l.text = str(p.get("name", "Friend"))
			name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			sub_l.text = "Steam"
		_:
			name_l.text = "Empty slot"
			name_l.add_theme_color_override("font_color", Color(PEARL, 0.45))
			sub_l.text = "Add a CPU or invite a friend"
			var add := _make_slot_button("+ ADD CPU")
			add.pressed.connect(_lobby_add_cpu.bind(i))
			add.set_meta("sfx", "add")
			v.add_child(add)
	return card


## 카드 아래쪽 가로로 꽉 찬 버튼
func _make_slot_button(text: String) -> Button:
	var b := _make_glass_button(text, Vector2(0, 54), 18)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.set_meta("pivot_left", false)
	b.set_meta("hover_scale", 1.03)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		box.content_margin_left = 8
		box.content_margin_right = 8
		b.add_theme_stylebox_override(st, box)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _lobby_customize() -> void:
	_cz_tab = 0
	_refresh_customize()
	_show_page("customize")


func _lobby_add_cpu(i: int) -> void:
	GameState.players[i] = {"kind": "cpu", "level": 1, "color": GameState.first_free_color()}
	_refresh_lobby()


func _lobby_remove(i: int) -> void:
	GameState.players[i] = {}
	_refresh_lobby()


func _lobby_set_level(i: int, lvl: int) -> void:
	GameState.players[i]["level"] = lvl


func _lobby_invite() -> void:
	_toast(tr("Friend invites will work once Steam is connected."))


func _on_lobby_start() -> void:
	if _busy:
		return
	if not GameState.can_start():
		Audio.play("back")
		return
	Audio.play("click")
	_open_board_select()



# =============================================================== 보드 고르기 (BOARD SELECT)
## 로비에서 START → 여기. 왼쪽: 보드 이름·설명 + 작은 상자들, 오른쪽: 고른 보드게임 상자를 크게.

func _build_board_page(parent: Control) -> Control:
	var page := Control.new()
	parent.add_child(page)
	_full_rect(page, "BoardPage")
	var margin := MarginContainer.new()
	page.add_child(margin)
	_full_rect(margin, "Margin")
	margin.add_theme_constant_override("margin_left", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_right", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 76)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 28)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	head.add_child(_header("CHOOSE A BOARD", 54))
	var pill := _pill_label("", 20)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pill)
	_board_mode_label = pill.get_child(0) as Label
	_board_mode_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 40)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)

	# ---- 왼쪽: 이름, 태그, 설명, 상자 고르기
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(640, 0)
	left.add_theme_constant_override("separation", 18)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 30)
	left.add_child(top_gap)
	_board_name = _header("", 64)
	left.add_child(_board_name)
	_board_tags = HBoxContainer.new()
	_board_tags.add_theme_constant_override("separation", 10)
	_board_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_board_tags)
	_board_desc = Label.new()
	_board_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board_desc.custom_minimum_size = Vector2(600, 0)
	_board_desc.add_theme_font_size_override("font_size", 24)
	_board_desc.add_theme_color_override("font_color", TEXT_DIM)
	_board_desc.add_theme_constant_override("line_spacing", 6)
	left.add_child(_board_desc)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(fill)
	var cap := Label.new()
	cap.text = "BOARDS"
	cap.add_theme_font_override("font", _spaced_font)
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", TEXT_DIM)
	left.add_child(cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	left.add_child(row)
	for i in BOARDS.size():
		var tb := _make_board_thumb(i)
		row.add_child(tb)
		_board_thumbs.append(tb)

	# ---- 오른쪽: 큰 상자
	var big := BoardBoxView.new()
	big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big.mouse_filter = Control.MOUSE_FILTER_PASS
	big.bob_amount = 0.02
	body.add_child(big)
	_board_big = big

	# ---- 아래: BACK / PLAY
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	var back := _make_glass_button("BACK", Vector2(170, 66), 20)
	back.pressed.connect(_go_back)
	back.set_meta("sfx", "back")
	bottom.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	_board_hint = Label.new()
	_board_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_board_hint.add_theme_font_size_override("font_size", 18)
	_board_hint.add_theme_color_override("font_color", TEXT_DIM)
	bottom.add_child(_board_hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	bottom.add_child(gap)
	_board_play = _make_primary_button("PLAY", Vector2(240, 66))
	_board_play.pressed.connect(_on_board_play)
	_board_play.set_meta("sfx", "")   # PLAY 소리는 _on_board_play 에서
	bottom.add_child(_board_play)
	return page


## 왼쪽 아래 작은 상자 버튼
func _make_board_thumb(i: int) -> Button:
	var data: Dictionary = BOARDS[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(196, 188)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	var normal := _glass_box(Color(0.02, 0.15, 0.14, 0.55), GLASS_BORDER, 1, 18)
	var hover := _glass_box(Color(0.06, 0.3, 0.27, 0.6), Color(AQUA, 0.45), 1, 18)
	var sel := _glass_box(Color(0.06, 0.3, 0.27, 0.7), AQUA, 3, 18)
	for box in [normal, hover, sel]:
		box.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.toggle_mode = true
	b.set_meta("sel_box", sel)
	b.set_meta("normal_box", normal)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var view := BoardBoxView.new()
	view.react_to_mouse = false
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.bob_amount = 0.0
	view.box = data["box"]
	view.dim = bool(data["locked"])
	v.add_child(view)
	var l := Label.new()
	l.text = data["name"]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", PEARL if not data["locked"] else TEXT_DIM)
	v.add_child(l)
	b.set_meta("view", view)
	b.mouse_entered.connect(func() -> void: view.hovered = true)
	b.mouse_exited.connect(func() -> void: view.hovered = false)
	b.pressed.connect(_select_board.bind(i))
	return b


func _open_board_select() -> void:
	var n := GameState.filled_count()
	_board_mode_label.text = "%s  •  %s" % [tr(GameState.get_mode_name()), tr("%d PLAYERS") % n]
	_select_board(_board_index, false)
	_show_page("board")


func _select_board(i: int, with_fx: bool = true) -> void:
	var data: Dictionary = BOARDS[i]
	var changed := i != _board_index or _board_big.box == null
	_board_index = i
	if changed:
		_board_big.box = data["box"]
	_board_big.dim = bool(data["locked"])
	_board_name.text = data["name"]
	_board_desc.text = data["desc"]
	for c in _board_tags.get_children():
		c.queue_free()
	for tag in data["tags"]:
		_board_tags.add_child(_pill_label(tag, 16))
	for k in _board_thumbs.size():
		var tb := _board_thumbs[k]
		tb.set_pressed_no_signal(k == i)
		(tb.get_meta("view") as Control).set("selected", k == i)
	var locked := bool(data["locked"])
	_board_play.disabled = locked
	_board_hint.text = "This board isn't ready yet." if locked else ""
	if with_fx and changed:
		var r := _board_big.get_global_rect()
		_bg.burst_bubbles(r.get_center() + Vector2(0, r.size.y * 0.2), 10)


func _on_board_play() -> void:
	if _busy:
		return
	var data: Dictionary = BOARDS[_board_index]
	if data["locked"]:
		Audio.play("back")
		return
	Audio.play("start")
	GameState.selected_board = data["id"]
	if ResourceLoader.exists(GAME_SCENE):
		_busy = true
		Audio.stop_music(0.4)
		var t := create_tween()
		t.tween_property(_fade, "color:a", 1.0, 0.4)
		await t.finished
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		_toast(tr("Let's go! The board itself is being built next."))

# =============================================================== 꾸미기 (CUSTOMIZE)
## 왼쪽: 내 말 크게 미리보기 / 오른쪽: 색 고르기 (모자·무늬는 나중에)

func _build_customize_page(parent: Control) -> Control:
	var page := Control.new()
	parent.add_child(page)
	_full_rect(page, "CustomizePage")
	var margin := MarginContainer.new()
	page.add_child(margin)
	_full_rect(margin, "Margin")
	margin.add_theme_constant_override("margin_left", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_right", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 76)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 28)
	margin.add_child(col)
	col.add_child(_header("CUSTOMIZE", 54))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 32)
	col.add_child(body)

	# ---- 왼쪽: 미리보기 카드
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	var cb := _glass_box(Color(0.02, 0.15, 0.14, 0.74), Color(AQUA, 0.3), 2, 24)
	cb.set_content_margin_all(26)
	card.add_theme_stylebox_override("panel", cb)
	body.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var who := Label.new()
	who.text = "You"
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_override("font", _spaced_font)
	who.add_theme_font_size_override("font_size", 34)
	cv.add_child(who)
	_cz_pawn = LobbyPawn.new()
	_cz_pawn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cz_pawn.custom_minimum_size = Vector2(0, 420)
	_cz_pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(_cz_pawn)
	_cz_color_name = Label.new()
	_cz_color_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cz_color_name.add_theme_font_size_override("font_size", 20)
	_cz_color_name.add_theme_color_override("font_color", TEXT_DIM)
	cv.add_child(_cz_color_name)

	# ---- 오른쪽: 탭 (색 / 모자 / 무늬 / 장식품 / 옷)
	var opts := PanelContainer.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ob := _glass_box(Color(0.02, 0.15, 0.14, 0.74), GLASS_BORDER, 1, 24)
	ob.set_content_margin_all(30)
	opts.add_theme_stylebox_override("panel", ob)
	body.add_child(opts)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 24)
	opts.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	right.add_child(tabs)
	for i in CZ_TABS.size():
		var tb := _make_glass_button(CZ_TABS[i], Vector2(0, 58), 19)
		tb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.set_meta("pivot_left", false)
		tb.set_meta("hover_scale", 1.03)
		tb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := tb.get_theme_stylebox(st).duplicate() as StyleBoxFlat
			box.content_margin_left = 8
			box.content_margin_right = 8
			tb.add_theme_stylebox_override(st, box)
		tb.pressed.connect(_select_cz_tab.bind(i))
		tb.set_meta("sfx", "tick")
		tabs.add_child(tb)
		_cz_tab_buttons.append(tb)

	for i in CZ_TABS.size():
		var pagev := VBoxContainer.new()
		pagev.add_theme_constant_override("separation", 20)
		right.add_child(pagev)
		_cz_tab_pages.append(pagev)
		var head_row := HBoxContainer.new()
		pagev.add_child(head_row)
		var cap := _caption(CZ_CAPTION[i])
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head_row.add_child(cap)
		if i == 0:
			# 색 고르기
			var grid := GridContainer.new()
			grid.columns = 6
			grid.add_theme_constant_override("h_separation", 22)
			grid.add_theme_constant_override("v_separation", 22)
			pagev.add_child(grid)
			for ci in GameState.PALETTE.size():
				var sw := Button.new()
				sw.custom_minimum_size = Vector2(96, 96)
				sw.focus_mode = Control.FOCUS_NONE
				sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				sw.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				sw.pressed.connect(_on_swatch_pressed.bind(ci))
				sw.set_meta("sfx", "color")
				grid.add_child(sw)
				_cz_swatches.append(sw)
			continue
		# 아이템 고르기 + 제거 버튼
		var cat: String = CZ_CATEGORY[i]
		var rm := _make_glass_button("REMOVE", Vector2(150, 48), 17)
		rm.alignment = HORIZONTAL_ALIGNMENT_CENTER
		rm.set_meta("pivot_left", false)
		rm.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		rm.add_theme_stylebox_override("disabled", _glass_box(Color(0.02, 0.10, 0.09, 0.35), Color(AQUA, 0.08), 1))
		rm.add_theme_color_override("font_disabled_color", Color(PEARL, 0.3))
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := rm.get_theme_stylebox(st).duplicate() as StyleBoxFlat
			box.content_margin_left = 8
			box.content_margin_right = 8
			rm.add_theme_stylebox_override(st, box)
		rm.pressed.connect(_on_item_remove.bind(cat))
		rm.set_meta("sfx", "")   # 착용 중일 때만 소리 (아래에서)
		head_row.add_child(rm)
		_cz_remove[cat] = rm
		var items_row := HBoxContainer.new()
		items_row.add_theme_constant_override("separation", 18)
		pagev.add_child(items_row)
		var tiles: Array[Button] = []
		for item_id in GameState.COSMETICS[cat]:
			var tile := _make_item_tile(cat, item_id)
			items_row.add_child(tile)
			tiles.append(tile)
		_cz_tiles[cat] = tiles

	# ---- 아래 버튼
	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	var back := _make_glass_button("BACK", Vector2(170, 66), 20)
	back.pressed.connect(_go_back)
	back.set_meta("sfx", "back")
	bottom.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	var done := _make_primary_button("DONE", Vector2(240, 66))
	done.pressed.connect(_go_back)
	bottom.add_child(done)
	return page


func _swatch_box(col: Color, selected: bool, hover: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(48)
	b.anti_aliasing = true
	if selected:
		b.border_color = Color.WHITE
		b.set_border_width_all(5)
		b.set_expand_margin_all(6)
	elif hover:
		b.border_color = Color(1, 1, 1, 0.6)
		b.set_border_width_all(3)
		b.set_expand_margin_all(4)
	return b


## 아이템 한 칸: 아이템만 단독으로 + 이름
func _make_item_tile(cat: String, item_id: String) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(230, 280)
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.set_meta("cat", cat)
	tile.set_meta("item", item_id)
	tile.pressed.connect(_on_item_pressed.bind(cat, item_id))
	tile.set_meta("sfx", "")   # 착용 소리는 _on_item_pressed 에서
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 10
	v.offset_bottom = -14
	var icon = ItemIcon.new()
	icon.item_id = item_id
	icon.is_pattern = cat == "pattern"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(icon)
	tile.set_meta("icon", icon)
	var nm := Label.new()
	nm.text = GameState.COSMETIC_NAMES[item_id]
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 18)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var tag := Label.new()
	tag.text = "EQUIPPED"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", _spaced_font)
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", AQUA)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)
	tile.set_meta("tag", tag)
	return tile


func _select_cz_tab(i: int) -> void:
	_cz_tab = i
	for k in _cz_tab_pages.size():
		_cz_tab_pages[k].visible = k == i
	for k in _cz_tab_buttons.size():
		var on := k == i
		var tb := _cz_tab_buttons[k]
		var box := _glass_box(GLASS_HOVER if on else GLASS, Color(AQUA, 0.6) if on else GLASS_BORDER, 1)
		box.content_margin_left = 8
		box.content_margin_right = 8
		tb.add_theme_stylebox_override("normal", box)
		tb.add_theme_color_override("font_color", PEARL if on else Color(PEARL, 0.6))


func _refresh_customize() -> void:
	var mine := int(GameState.players[0].get("color", 0))
	var my_col: Color = GameState.PALETTE[mine]
	var my_look := GameState.look(0)
	# 색
	for ci in _cz_swatches.size():
		var sw := _cz_swatches[ci]
		var col: Color = GameState.PALETTE[ci]
		sw.text = ""
		sw.add_theme_stylebox_override("normal", _swatch_box(col, ci == mine, false))
		sw.add_theme_stylebox_override("hover", _swatch_box(col, ci == mine, true))
		sw.add_theme_stylebox_override("pressed", _swatch_box(col, true, false))
		sw.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 아이템
	for cat in _cz_tiles:
		var cur := GameState.equipped(0, cat)
		_cz_remove[cat].disabled = cur == ""
		for tile in _cz_tiles[cat]:
			var item_id: String = tile.get_meta("item")
			var on := item_id == cur
			var icon = tile.get_meta("icon")
			icon.tint = my_col
			tile.get_meta("tag").visible = on
			var nb := _glass_box(Color(0.06, 0.30, 0.27, 0.8) if on else Color(0.02, 0.12, 0.11, 0.6), Color(AQUA, 1.0) if on else Color(AQUA, 0.15), 3 if on else 1, 18)
			var hb := _glass_box(Color(0.06, 0.26, 0.24, 0.8), Color(AQUA, 1.0) if on else Color(AQUA, 0.5), 3 if on else 2, 18)
			tile.add_theme_stylebox_override("normal", nb)
			tile.add_theme_stylebox_override("hover", hb)
			tile.add_theme_stylebox_override("pressed", hb)
			tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_cz_pawn.color = my_col
	_cz_pawn.look = my_look
	_cz_color_name.text = GameState.PALETTE_NAMES[mine]
	_select_cz_tab(_cz_tab)


func _on_swatch_pressed(ci: int) -> void:
	GameState.players[0]["color"] = ci  # 다른 사람과 같은 색이어도 괜찮아요
	_refresh_customize()
	_bg.burst_bubbles(_cz_swatches[ci].get_global_rect().get_center(), 8)


func _on_item_pressed(cat: String, item_id: String) -> void:
	Audio.play("equip")
	GameState.equip(0, cat, item_id)
	_refresh_customize()
	_bg.burst_bubbles(get_global_mouse_position(), 8)


func _on_item_remove(cat: String) -> void:
	if String(GameState.equipped(0, cat)) != "":
		Audio.play("unequip")
	GameState.unequip(0, cat)
	_refresh_customize()


func _build_settings_page(parent: Control) -> Control:
	var col := _make_left_page(parent, "SettingsPage", 0)
	_grabber_tex = _circle_texture(30, PEARL)

	# 메인화면·모드 선택 화면처럼 큰 판 없이 배경 위에 바로 올려요
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	v.add_theme_constant_override("separation", 34)
	col.add_child(v)

	var header := _header("SETTINGS", 54)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(header)

	# ---- 탭
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	v.add_child(tabs)
	for i in SETTINGS_TABS.size():
		var tb := _make_glass_button(SETTINGS_TABS[i], Vector2(170, 60), 20)
		tb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.set_meta("pivot_left", false)
		tb.set_meta("hover_scale", 1.03)
		tb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tb.pressed.connect(_select_settings_tab.bind(i))
		tb.set_meta("sfx", "tick")
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	_settings_first = _tab_buttons[0]

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(0, 420)
	v.add_child(content)

	# ---- 오디오: 슬라이더를 끌어서 조절
	var audio := _settings_tab_box(content)
	audio.add_child(_volume_row("MASTER VOLUME", "master", Settings.master_volume))
	audio.add_child(_volume_row("MUSIC", "music", Settings.music_volume))
	audio.add_child(_volume_row("SOUND EFFECTS", "sfx", Settings.sfx_volume))

	# ---- 비디오
	var video := _settings_tab_box(content)
	_mode_seg = _make_segmented(Settings.WINDOW_MODES, Settings.window_mode, _on_window_mode_changed)
	video.add_child(_stack_row("WINDOW MODE", _mode_seg))

	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 20)
	_res_list = Settings.available_resolutions()
	var res_names: Array = []
	for r in _res_list:
		res_names.append("%d × %d" % [r.x, r.y])
	_res_drop = _make_dropdown(res_names, maxi(_res_list.find(Settings.resolution), 0), _on_resolution_changed)
	var res_col := _stack_row("RESOLUTION", _res_drop)
	res_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(res_col)
	var fps_names: Array = []
	for f in Settings.FPS_LIMITS:
		fps_names.append("Unlimited" if f == 0 else "%d FPS" % f)
	_fps_drop = _make_dropdown(fps_names, maxi(Settings.FPS_LIMITS.find(Settings.max_fps), 0), _on_fps_changed)
	var fps_col := _stack_row("FRAME RATE LIMIT", _fps_drop)
	fps_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(fps_col)
	video.add_child(two)

	_res_note = Label.new()
	_res_note.text = "Fullscreen and borderless use your monitor's resolution."
	_res_note.add_theme_font_size_override("font_size", 16)
	_res_note.add_theme_color_override("font_color", TEXT_DIM)
	_res_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	video.add_child(_res_note)

	_vsync_switch = ToggleSwitch.new()
	_vsync_switch.custom_minimum_size = Vector2(84, 48)
	_vsync_switch.button_pressed = Settings.vsync
	_vsync_switch.toggled.connect(_set_vsync)
	_vsync_switch.set_meta("sfx", "")
	video.add_child(_inline_row("V-SYNC", _vsync_switch))

	# ---- 언어
	var lang := _settings_tab_box(content)
	var lang_names: Array = []
	var lang_idx := 0
	for i in Settings.LANGUAGES.size():
		lang_names.append(Settings.LANGUAGES[i][1])
		if Settings.LANGUAGES[i][0] == Settings.language:
			lang_idx = i
	_lang_seg = _make_segmented(lang_names, lang_idx, _on_language_changed, false)
	lang.add_child(_stack_row("LANGUAGE", _lang_seg))

	# ---- 아래 버튼
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	v.add_child(bottom)
	var defaults := _make_glass_button("DEFAULTS", Vector2(190, 64), 20)
	defaults.pressed.connect(_on_defaults_pressed)
	bottom.add_child(defaults)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var close := _make_glass_button("BACK", Vector2(190, 64), 20)
	close.pressed.connect(_go_back)
	close.set_meta("sfx", "back")
	bottom.add_child(close)

	_select_settings_tab(0)
	_update_resolution_state()
	return col.get_parent().get_parent() as Control


func _settings_tab_box(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30)
	parent.add_child(box)
	_tab_pages.append(box)
	return box


## 작은 제목(위) + 조작 버튼(아래, 전체 폭)
func _stack_row(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(_caption(label_text))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box


## 작은 제목(왼쪽) + 조작 버튼(오른쪽)
func _inline_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var cap := _caption(label_text)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _spaced_font)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(AQUA, 0.85))
	return l


## 버튼 여러 개 중 하나를 클릭해서 고르는 묶음 (선택된 것은 아쿠아색으로 채워짐)
func _make_segmented(opts: Array, idx: int, callback: Callable, translate: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for i in opts.size():
		var b := Button.new()
		b.text = str(opts[i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == idx
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not translate:
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Color(PEARL, 0.75))
		b.add_theme_color_override("font_hover_color", PEARL)
		b.add_theme_color_override("font_pressed_color", DEEP)
		b.add_theme_color_override("font_hover_pressed_color", DEEP)
		var off := _glass_box(Color(0.02, 0.12, 0.11, 0.7), Color(AQUA, 0.18), 1, 12)
		var hov := _glass_box(Color(0.06, 0.26, 0.24, 0.8), Color(AQUA, 0.5), 1, 12)
		var on := _glass_box(Color(AQUA, 0.92), Color(AQUA, 1.0), 1, 12)
		for box in [off, hov, on]:
			box.content_margin_left = 10
			box.content_margin_right = 10
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(callback.bind(i))
		b.set_meta("sfx", "tick")
		row.add_child(b)
		buttons.append(b)
	row.set_meta("buttons", buttons)
	return row


func _set_segment(row: HBoxContainer, idx: int) -> void:
	var buttons: Array = row.get_meta("buttons")
	for k in buttons.size():
		buttons[k].set_pressed_no_signal(k == idx)


## 클릭하면 목록이 펼쳐지는 선택 상자
func _make_dropdown(opts: Array, idx: int, callback: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for o in opts:
		ob.add_item(str(o))
	ob.select(idx)
	ob.custom_minimum_size = Vector2(0, 60)
	ob.focus_mode = Control.FOCUS_NONE
	ob.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ob.fit_to_longest_item = false
	ob.add_theme_font_size_override("font_size", 20)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		ob.add_theme_color_override(key, PEARL)
	ob.add_theme_color_override("font_disabled_color", Color(PEARL, 0.3))
	var nb := _glass_box(Color(0.02, 0.12, 0.11, 0.7), Color(AQUA, 0.25), 1, 12)
	var hb := _glass_box(Color(0.06, 0.26, 0.24, 0.8), Color(AQUA, 0.6), 1, 12)
	var db := _glass_box(Color(0.02, 0.09, 0.08, 0.45), Color(AQUA, 0.08), 1, 12)
	for box in [nb, hb, db]:
		box.content_margin_left = 18
	ob.add_theme_stylebox_override("normal", nb)
	ob.add_theme_stylebox_override("hover", hb)
	ob.add_theme_stylebox_override("pressed", hb)
	ob.add_theme_stylebox_override("hover_pressed", hb)
	ob.add_theme_stylebox_override("disabled", db)
	ob.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	ob.add_theme_constant_override("arrow_margin", 18)
	# 펼쳐지는 목록 꾸미기
	var pop := ob.get_popup()
	var pp := StyleBoxFlat.new()
	pp.bg_color = Color(0.02, 0.13, 0.12, 0.97)
	pp.border_color = Color(AQUA, 0.35)
	pp.set_border_width_all(1)
	pp.set_corner_radius_all(12)
	pp.set_content_margin_all(8)
	pop.add_theme_stylebox_override("panel", pp)
	var ph := StyleBoxFlat.new()
	ph.bg_color = Color(AQUA, 0.22)
	ph.set_corner_radius_all(8)
	pop.add_theme_stylebox_override("hover", ph)
	pop.add_theme_font_override("font", UIFont)
	pop.add_theme_font_size_override("font_size", 20)
	pop.add_theme_color_override("font_color", PEARL)
	pop.add_theme_color_override("font_hover_color", PEARL)
	pop.add_theme_constant_override("v_separation", 16)
	pop.add_theme_constant_override("item_start_padding", 12)
	ob.item_selected.connect(callback)
	ob.item_selected.connect(func(_i: int) -> void: Audio.play("tick"))
	return ob


func _volume_row(label_text: String, key: String, value: float) -> VBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundf(value * 100.0)
	slider.custom_minimum_size = Vector2(0, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.scrollable = false
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_slider(slider)
	slider.value_changed.connect(_on_volume_changed.bind(key))
	slider.value_changed.connect(func(_v: float) -> void: Audio.play("tick", 70))
	box.add_child(slider)
	var val := Label.new()
	val.custom_minimum_size = Vector2(72, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", PEARL)
	val.add_theme_font_size_override("font_size", 24)
	val.text = "%d%%" % int(slider.value)
	box.add_child(val)
	_vol_sliders[key] = slider
	_vol_values[key] = val
	return _stack_row(label_text, box)


## 슬라이더 손잡이용 동그라미 그림
func _circle_texture(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x - c, y - c).length()
			var a := clampf(c - dist + 0.5, 0.0, 1.0)
			var shade := 1.0 - clampf((dist / c) * 0.12, 0.0, 0.12)
			img.set_pixel(x, y, Color(col.r * shade, col.g * shade, col.b * shade, a))
	return ImageTexture.create_from_image(img)


func _select_settings_tab(i: int) -> void:
	_settings_tab = i
	for k in _tab_pages.size():
		_tab_pages[k].visible = k == i
	for k in _tab_buttons.size():
		var on := k == i
		var tb := _tab_buttons[k]
		tb.add_theme_stylebox_override("normal", _glass_box(GLASS_HOVER if on else GLASS, Color(AQUA, 0.6) if on else GLASS_BORDER, 1))
		tb.add_theme_color_override("font_color", PEARL if on else Color(PEARL, 0.6))


func _update_resolution_state() -> void:
	var windowed := Settings.window_mode == 0
	_res_drop.disabled = not windowed
	_res_note.visible = not windowed


func _refresh_settings_controls() -> void:
	_vol_sliders["master"].set_value_no_signal(roundf(Settings.master_volume * 100.0))
	_vol_sliders["music"].set_value_no_signal(roundf(Settings.music_volume * 100.0))
	_vol_sliders["sfx"].set_value_no_signal(roundf(Settings.sfx_volume * 100.0))
	for key in _vol_sliders:
		_vol_values[key].text = "%d%%" % int(_vol_sliders[key].value)
	_set_segment(_mode_seg, Settings.window_mode)
	_res_drop.select(maxi(_res_list.find(Settings.resolution), 0))
	_fps_drop.select(maxi(Settings.FPS_LIMITS.find(Settings.max_fps), 0))
	_vsync_switch.set_pressed_no_signal(Settings.vsync)
	_update_resolution_state()


func _build_footer(parent: Control) -> void:
	var ver := Label.new()
	ver.text = VERSION_TEXT
	ver.add_theme_font_size_override("font_size", 20)
	ver.add_theme_color_override("font_color", Color(PEARL, 0.55))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)


func _build_toast(parent: Control) -> void:
	var margin := MarginContainer.new()
	parent.add_child(margin)
	_full_rect(margin, "ToastArea")
	margin.add_theme_constant_override("margin_top", 24)
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(holder)

	_toast_panel = _pill_label("", 22)
	_toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_label = _toast_panel.get_child(0) as Label
	holder.add_child(_toast_panel)
	_toast_panel.hide()


# =============================================================== 부품

func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _header(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _spaced_font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", PEARL)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(0, 0.05, 0.05, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.add_theme_constant_override("shadow_outline_size", 14)
	return l


func _pill_label(text: String, font_size: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.16, 0.15, 0.45)
	s.set_corner_radius_all(40)
	s.border_color = GLASS_BORDER
	s.set_border_width_all(1)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _spaced_font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", AQUA)
	p.add_child(l)
	return p


func _glass_box(bg: Color, border: Color, border_w: int, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = 34
	s.content_margin_right = 24
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


## 선택된 버튼 표시: 왼쪽에 아쿠아 빛 막대 + 얇은 밝은 테두리
func _focus_ring(radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_border_width_all(2)
	s.border_width_left = 7
	s.border_color = AQUA
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _make_glass_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", _spaced_font)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(PEARL, 0.88))
	for key in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, PEARL)
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, GLASS_BORDER, 1))
	b.add_theme_stylebox_override("hover", _glass_box(GLASS_HOVER, Color(AQUA, 0.45), 1))
	b.add_theme_stylebox_override("pressed", _glass_box(GLASS_PRESSED, Color(AQUA, 0.6), 1))
	b.add_theme_stylebox_override("hover_pressed", _glass_box(GLASS_PRESSED, Color(AQUA, 0.6), 1))
	b.add_theme_stylebox_override("focus", _focus_ring(16))
	b.set_meta("pivot_left", true)
	_hook_button_fx(b, 1.04)
	return b


func _make_mode_card(data: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(COLUMN_WIDTH, 184)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", _glass_box(GLASS, GLASS_BORDER, 1, 20))
	b.add_theme_stylebox_override("hover", _glass_box(GLASS_HOVER, Color(AQUA, 0.45), 1, 20))
	b.add_theme_stylebox_override("pressed", _glass_box(GLASS_PRESSED, Color(AQUA, 0.6), 1, 20))
	b.add_theme_stylebox_override("focus", _focus_ring(20))
	b.set_meta("pivot_left", true)
	_hook_button_fx(b, 1.025)

	var margin := MarginContainer.new()
	b.add_child(margin)
	_full_rect(margin, "Margin")
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 14)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var icon = ModeIcon.new()
	icon.mode = int(data["mode"])
	icon.custom_minimum_size = Vector2(230, 140)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	b.set_meta("icon", icon)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 4)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)

	var title := Label.new()
	title.text = data["title"]
	title.add_theme_font_override("font", _spaced_font)
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", PEARL)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)

	var desc := Label.new()
	desc.text = data["desc"]
	desc.add_theme_font_size_override("font_size", 21)
	desc.add_theme_color_override("font_color", TEXT_DIM)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(desc)

	b.pressed.connect(_on_mode_chosen.bind(int(data["mode"]), String(data["title"]), b))
	return b


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(AQUA, 0.9)
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _grabber_tex)
	s.add_theme_icon_override("grabber_highlight", _grabber_tex)
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _hook_button_fx(b: Button, hover_scale: float) -> void:
	b.set_meta("hover_scale", hover_scale)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.resized.connect(_update_pivot.bind(b))
	b.mouse_entered.connect(_on_btn_mouse_entered.bind(b))
	b.focus_entered.connect(_on_btn_focus.bind(b))
	b.focus_exited.connect(_on_btn_unfocus.bind(b))
	b.button_down.connect(_on_btn_down.bind(b))
	b.button_up.connect(_on_btn_up.bind(b))


func _update_pivot(b: Control) -> void:
	if b.get_meta("pivot_left", false):
		b.pivot_offset = Vector2(0, b.size.y * 0.5)
	else:
		b.pivot_offset = b.size * 0.5


func _on_btn_mouse_entered(b: Button) -> void:
	if not _busy and b.is_visible_in_tree():
		b.grab_focus()


func _on_btn_focus(b: Button) -> void:
	_tween_scale(b, b.get_meta("hover_scale", 1.07), 0.25)
	if b.has_meta("icon"):
		var icon = b.get_meta("icon")
		icon.excited = true
	var r := b.get_global_rect()
	_bg.burst_bubbles(Vector2(r.position.x + r.size.x * randf_range(0.15, 0.85), r.end.y - 10.0), 5)


func _on_btn_unfocus(b: Button) -> void:
	_tween_scale(b, 1.0, 0.2)
	if b.has_meta("icon"):
		var icon = b.get_meta("icon")
		icon.excited = false


func _on_btn_down(b: Button) -> void:
	_tween_scale(b, 0.95, 0.08)


func _on_btn_up(b: Button) -> void:
	_tween_scale(b, b.get_meta("hover_scale", 1.07) if b.has_focus() else 1.0, 0.2)


func _tween_scale(b: Control, target: float, time: float) -> void:
	var old = (b.get_meta("scale_tween") if b.has_meta("scale_tween") else null)
	if old is Tween:
		old.kill()
	var t := create_tween()
	t.tween_property(b, "scale", Vector2.ONE * target, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.set_meta("scale_tween", t)


# =============================================================== 화면 전환

func _play_intro() -> void:
	_busy = true
	_current = "main"
	create_tween().tween_property(_fade, "color:a", 0.0, 0.9)
	_logo.play_intro()
	for i in _main_buttons.size():
		var b := _main_buttons[i]
		b.modulate.a = 0.0
		b.scale = Vector2(0.6, 0.6)
		var t := create_tween().set_parallel(true)
		var delay := 0.6 + float(i) * 0.07
		t.tween_property(b, "modulate:a", 1.0, 0.25).set_delay(delay)
		t.tween_property(b, "scale", Vector2.ONE, 0.45).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.05).timeout
	_busy = false
	_main_buttons[0].grab_focus()


func _show_page(id: String) -> void:
	if _busy or id == _current:
		return
	_busy = true
	var old: Control = _pages.get(_current)
	var page: Control = _pages[id]
	if old:
		var t := create_tween().set_parallel(true)
		t.tween_property(old, "modulate:a", 0.0, 0.16)
		t.tween_property(old, "position:x", -60.0, 0.16)
		await t.finished
		old.hide()
		old.position.x = 0.0
	_current = id
	page.modulate.a = 0.0
	page.position.x = -60.0
	page.show()
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(page, "modulate:a", 1.0, 0.22)
	t2.tween_property(page, "position:x", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_busy = false
	match id:
		"main":
			(_last_main_button if _last_main_button else _main_buttons[0]).grab_focus()
		"mode":
			_mode_buttons[0].grab_focus()
		"settings":
			_settings_first.grab_focus()
		"lobby", "customize", "board":
			pass


func _go_back() -> void:
	if _current == "settings":
		Settings.save_settings()
	if _current == "lobby":
		_show_page("mode")
	elif _current == "customize":
		_refresh_lobby()
		_show_page("lobby")
	elif _current == "board":
		_show_page("lobby")
	else:
		_show_page("main")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _busy:
			return
		if _current == "main":
			_main_buttons[_main_buttons.size() - 1].grab_focus()  # QUIT 버튼으로
		else:
			_go_back()


func _input(event: InputEvent) -> void:
	# 화면 아무 데나 클릭하면 물방울이 보글보글
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_bg.burst_bubbles(get_global_mouse_position(), 7)
		Audio.play("bubbles", 120)


# =============================================================== 버튼 동작

func _on_menu_pressed(id: String, b: Button) -> void:
	if _busy:
		return
	_last_main_button = b
	match id:
		"play":
			_show_page("mode")
		"collection":
			_toast(tr("Minigames will show up here once they're made!"))
		"settings":
			_show_page("settings")
		"quit":
			_quit()


func _on_mode_chosen(mode: int, _title: String, b: Button) -> void:
	if _busy:
		return
	var r := b.get_global_rect()
	_bg.burst_bubbles(r.get_center(), 18)
	_open_lobby(mode)

func _set_vsync(on: bool) -> void:
	Audio.play("toggle_on" if on else "toggle_off")
	Settings.vsync = on
	Settings.apply_video()
	Settings.save_settings()


func _on_volume_changed(value: float, key: String) -> void:
	match key:
		"master":
			Settings.master_volume = value / 100.0
		"music":
			Settings.music_volume = value / 100.0
		"sfx":
			Settings.sfx_volume = value / 100.0
	Settings.apply_audio()
	_vol_values[key].text = "%d%%" % int(value)


func _on_window_mode_changed(idx: int) -> void:
	_set_segment(_mode_seg, idx)
	Settings.window_mode = idx
	Settings.apply_video()
	Settings.save_settings()
	_update_resolution_state()


func _on_resolution_changed(idx: int) -> void:
	Settings.resolution = _res_list[idx]
	Settings.apply_video()
	Settings.save_settings()


func _on_fps_changed(idx: int) -> void:
	Settings.max_fps = Settings.FPS_LIMITS[idx]
	Settings.apply_video()
	Settings.save_settings()


func _on_language_changed(idx: int) -> void:
	_set_segment(_lang_seg, idx)
	Settings.language = Settings.LANGUAGES[idx][0]
	Settings.apply_language()
	Settings.save_settings()


func _on_defaults_pressed() -> void:
	Settings.reset_defaults()
	_refresh_settings_controls()
	_toast(tr("Settings restored to defaults."))


func _quit() -> void:
	_busy = true
	Audio.stop_music(0.35)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	await t.finished
	get_tree().quit()


func _toast(msg: String) -> void:
	Audio.play("toast")
	_toast_label.text = msg
	if _toast_tween:
		_toast_tween.kill()
	_toast_panel.show()
	_toast_panel.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_toast_panel.hide)
