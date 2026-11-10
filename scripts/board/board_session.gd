extends Node3D
## 보드 위 게임 진행 공통 부분 (튜토리얼 보드와 진짜 게임이 같이 씀).
##   - 3D 보드 세상, 말, 카메라 (차례인 말을 가까이 따라감)
##   - 차례: 주사위 → 이동 (갈림길 고르기, START 보너스, 트로피 칸은 지나가도 멈춰서 물어봄) → 칸 효과
##   - 규칙: 동전 · 트로피 (숫자는 scripts/board/rules.gd), 찬스 카드, 상점, 미니게임(지금은 임시 순위)
##   - 화면: 이름표(동전·트로피), 칸 안내판, 주사위 버튼, 갈림길 화살표, 물어보는 창, 결과 화면
## 상속: scripts/tutorial_board.gd (튜토리얼), scripts/board_game.gd (진짜 게임)

const Rules := preload("res://scripts/board/rules.gd")
const BoardWorld := preload("res://scripts/world3d/board_world.gd")
const Pawn3D := preload("res://scripts/world3d/pawn3d.gd")
const Dice3D := preload("res://scripts/world3d/dice3d.gd")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
const PathArrow := preload("res://scripts/ui/path_arrow.gd")
const UIFont := preload("res://fonts/Poppins-Bold.ttf")
const CARD_TEX := preload("res://textures/tiles/card_chance.png")
const COIN_TEX := preload("res://textures/ui/coin.png")
const TROPHY_TEX := preload("res://textures/ui/trophy.png")
const GOLD := Color("ffcf4a")
const DICE_ATLAS := preload("res://textures/dice/dice_atlas.png")
const MAIN_MENU := "res://scenes/main_menu.tscn"

const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const PAWN_SCALE := 1.7            ## 말 키 (미터)
const CLOSE := Vector3(0, 3.4, 6.2)   ## 말 가까이 볼 때 카메라 위치 (말 기준)
const ZOOM_MIN := 0.55
const ZOOM_MAX := 4.5
const TILE_ZOOM := 1.15            ## 칸을 강조할 때 늘 같은 거리 (칸 크기가 화면에서 늘 같게)
const DICE_H := 3.4                ## 말 위 주사위 높이
const HOP_TIME := 0.3

var world: BoardWorld
var _pawns: Array = []        ## {slot, name, color, cpu, team, node, spot, tile, prev, chip, coins, trophies}
var _camera: Camera3D
var _focus := Vector3.ZERO    ## 카메라가 바라보는 점
var _zoom := 1.0              ## 1 = 가까이, 클수록 멀리
var _follow: Node3D = null    ## 이 말을 카메라가 따라감
var _cam_tween: Tween
var _ui: CanvasLayer
var _root: Control
var _chips: HBoxContainer
var _my_pawn_btn: Button
var _start_marker: Control
var _screen_marker: Control
var _legend: PanelContainer
var _overlay
var _fade: ColorRect
var _title: Label
var _intro_done := false
var _focused := false
var _dragging := false

# 차례 진행 상태
var _dice: Dice3D
var _dice_btn: Button
var _click_hint: Label
var _steps_label: Label
var _turn_pawn: Dictionary = {}
var _awaiting_roll := false
var _dice_hit := false
var _last_roll := 0
var _steps_left := 0
var _choosing := false
var _choice := -1
var _forced_next := -1
var _arrows: Array = []
var _landed := false
var _shop_open := false
var _shop_panel: Control
var _shop_close: Button
var _shop_buy: Button
var _popup_root: Control

# 규칙 상태
var _rng := RandomNumberGenerator.new()
var _round := 0
var _round_label: Label
var _game_over := false
var _winner: Dictionary = {}
var _trophy_next_round := Rules.TROPHY_FIRST_ROUND
var _tile_mods := {}          ## 칸 → "coin_plus" / "coin_minus" (찬스 카드로 바뀐 칸)
var _legend_box: VBoxContainer
var _dialog_open := false
var _dialog_buttons: Array = []
var _dialog_choice := -1
var _picking_tile := false
var _picked_tile := -1
var _hover_tile := -1
var _pick_marker: MeshInstance3D
var _tile_catcher: Control

# 튜토리얼·점검용으로 결과를 미리 정해 둘 수 있음
var rig_ranking: Array = []   ## 다음 미니게임 순위 (pawn 목록)
var rig_card := ""            ## 다음 찬스 카드 id
var force_shop_trophy := -1   ## 1 = 다음 상점에 트로피 꼭 진열, 0 = 꼭 안 함, -1 = 확률대로
var force_trophy_buy := false ## 튜토리얼: 트로피 살지 물을 때 BUY 만 누를 수 있게
var shot_hint := ""           ## 자동 스크린샷용: 지금 보여 주는 장면 이름


func _ready() -> void:
	_rng.randomize()
	world = BoardWorld.new()
	add_child(world)
	_setup_pawns()
	_dice = Dice3D.new()
	add_child(_dice)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 400.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 22.0
	attrs.dof_blur_far_transition = 18.0
	attrs.dof_blur_amount = 0.05
	_camera.attributes = attrs
	add_child(_camera)
	_camera.make_current()
	_build_ui()
	Audio.play_music()
	_intro()


func _setup_pawns() -> void:
	var list := []
	var cpu_no := 0
	for slot in 4:
		var p: Dictionary = GameState.players[slot]
		if p.is_empty():
			continue
		var pname := "You"
		var cpu := false
		if p.get("kind", "") == "cpu":
			cpu_no += 1
			pname = tr("CPU %d") % cpu_no
			cpu = true
		list.append({"slot": slot, "name": pname, "cpu": cpu, "color": GameState.player_color(slot), "look": GameState.look(slot)})
	if list.is_empty():
		list.append({"slot": 0, "name": "You", "cpu": false, "color": GameState.PALETTE[0], "look": {}})
	for d in list:
		d["coins"] = Rules.START_COINS
		d["trophies"] = 0
		d["team"] = ("A" if int(d["slot"]) < 2 else "B") if _team_mode() else ""
	var spots: Array = world.start_spots(list.size())
	for i in list.size():
		var d: Dictionary = list[i]
		var node := Pawn3D.new()
		node.color = d["color"]
		node.look = d["look"]
		node.scale = Vector3.ONE * PAWN_SCALE
		node.visible = false
		add_child(node)
		node.position = spots[i]
		node.rotation.y = PI   # 카메라 쪽(남쪽)을 보게
		d["node"] = node
		d["spot"] = spots[i]
		d["tile"] = world.start_index
		d["prev"] = -1
		d["start_i"] = i
		_pawns.append(d)


func _team_mode() -> bool:
	return GameState.selected_mode == GameState.Mode.TEAM_2V2


## 사람 대신 알아서 하는 말인지 (CPU, 또는 자동 점검 중인 내 말)
func _is_auto(p: Dictionary) -> bool:
	return bool(p["cpu"]) or GameState.debug_autoplay


## 보드 제목 (상속해서 바꿈)
func board_title() -> String:
	return "TUTORIAL BOARD"


func _my_pawn() -> Dictionary:
	for p in _pawns:
		if int(p["slot"]) == 0:
			return p
	return _pawns[0]


# ── 카메라 ───────────────────────────────────────────────────
func _apply_camera() -> void:
	# 멀어질수록 더 위에서 내려다보게 (아주 멀면 보드판 전체가 보임)
	var off := Vector3(0, CLOSE.y * _zoom * (1.0 + 0.35 * maxf(_zoom - 1.0, 0.0)), CLOSE.z * _zoom)
	_camera.position = _focus + off
	_camera.look_at(_focus + Vector3(0, 0.9, 0), Vector3.UP)
	var attrs := _camera.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = off.length() + 7.0 + _zoom * 4.0


func _process(delta: float) -> void:
	if _follow and is_instance_valid(_follow):
		_focus = _focus.lerp(_follow.position, 1.0 - exp(-delta * 7.0))
	_apply_camera()
	# 튜토리얼이 가리킬 START 광장 화면 위치
	var top: Vector3 = world.spaces[world.start_index]["pos"]
	var r := Rect2()
	var first := true
	for c in [Vector3(-3.6, 0, -3.6), Vector3(3.6, 0, -3.6), Vector3(-3.6, 0, 3.6), Vector3(3.6, 0, 3.6), Vector3(0, 2.4, 0)]:
		var wp: Vector3 = top + c
		if _camera.is_position_behind(wp):
			continue
		var sp := _camera.unproject_position(wp)
		if first:
			r = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			r = r.expand(sp)
	_start_marker.position = r.position
	_start_marker.size = r.size
	var v := get_viewport().get_visible_rect().size
	_screen_marker.position = Vector2(60, 110)
	_screen_marker.size = v - Vector2(120, 220)
	_update_play_ui()


func _move_camera(focus: Vector3, zoom: float, time: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(self, "_focus", focus, time)
	_cam_tween.tween_property(self, "_zoom", zoom, time)


## 이 말을 가까이 보기 (차례마다 부름)
func focus_on(p: Dictionary, time: float = 0.9) -> void:
	_follow = null
	_move_camera((p["node"] as Node3D).position, 1.0, time)


func _focus_my_pawn() -> void:
	focus_on(_my_pawn())
	_focused = true


func _unhandled_input(event: InputEvent) -> void:
	if not _intro_done:
		return
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if _cam_tween:
				_cam_tween.kill()
			_zoom = clampf(_zoom * (0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), ZOOM_MIN, ZOOM_MAX)
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		if _cam_tween:
			_cam_tween.kill()
		_follow = null
		var k := 0.02 * _zoom
		_focus += Vector3(-mm.relative.x * k, 0, -mm.relative.y * k)
		_focus.x = clampf(_focus.x, -BoardWorld.HALF_W, BoardWorld.HALF_W)
		_focus.z = clampf(_focus.z, -BoardWorld.HALF_D, BoardWorld.HALF_D)


# ── 화면 UI ──────────────────────────────────────────────────
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = UIFont
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	root.theme = th
	_ui.add_child(root)
	_root = root

	_start_marker = Control.new()
	_start_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_start_marker)
	_screen_marker = Control.new()
	_screen_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_screen_marker)

	# 주사위 누르는 곳 (주사위 위에 투명하게 겹쳐 둠)
	_dice_btn = Button.new()
	_dice_btn.flat = true
	_dice_btn.focus_mode = Control.FOCUS_NONE
	_dice_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_dice_btn.set_meta("sfx", "tick")
	_dice_btn.pressed.connect(_hit_dice)
	_dice_btn.visible = false
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		_dice_btn.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	root.add_child(_dice_btn)
	_click_hint = _outlined_label("CLICK!", 30)
	_click_hint.visible = false
	root.add_child(_click_hint)
	_steps_label = _outlined_label("", 64)
	_steps_label.visible = false
	root.add_child(_steps_label)

	_legend = _build_legend()
	root.add_child(_legend)
	_legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 30)
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend.visible = false

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 10)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chips)
	_chips.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_chips.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chips.position.y = 30
	for p in _pawns:
		var chip := _make_chip(p)
		p["chip"] = chip
		_chips.add_child(chip)

	var exit := _glass_button("EXIT TUTORIAL")
	exit.set_meta("sfx", "back")
	exit.pressed.connect(_exit_to_menu)
	root.add_child(exit)
	exit.position = Vector2(30, 30)
	_round_label = _outlined_label("", 26)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_round_label.position = Vector2(34, 92)
	_round_label.visible = false
	root.add_child(_round_label)

	_my_pawn_btn = _glass_button("MY PAWN")
	_my_pawn_btn.custom_minimum_size = Vector2(180, 60)
	_my_pawn_btn.pressed.connect(_focus_my_pawn)
	root.add_child(_my_pawn_btn)
	_my_pawn_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)
	_my_pawn_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_my_pawn_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_my_pawn_btn.visible = false

	_popup_root = Control.new()
	_popup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popup_root)

	_title = Label.new()
	_title.text = board_title()
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_outline_color", DEEP)
	_title.add_theme_constant_override("outline_size", 18)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.position.y = 110
	_title.modulate.a = 0.0
	root.add_child(_title)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _outlined_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", maxi(8, font_size / 4))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _glass(bg: Color, border: Color, bw: int, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.anti_aliasing = true
	return s


func _glass_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", _glass(Color(0.02, 0.17, 0.16, 0.7), Color(AQUA, 0.3), 1))
	b.add_theme_stylebox_override("hover", _glass(Color(0.08, 0.4, 0.36, 0.75), Color(AQUA, 0.6), 1))
	b.add_theme_stylebox_override("pressed", _glass(Color(0.03, 0.26, 0.24, 0.8), AQUA, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## 왼쪽 아래 칸 종류 안내판
func _build_legend() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := _glass(Color(0.02, 0.15, 0.14, 0.72), Color(AQUA, 0.25), 1, 14)
	st.content_margin_left = 16
	st.content_margin_right = 18
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	_legend_box = v
	var head := Label.new()
	head.text = "SPACES"
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", AQUA)
	v.add_child(head)
	for kind in BoardWorld.KIND_ORDER:
		_legend_row(v, kind)
	return panel


func _legend_row(v: VBoxContainer, kind: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + kind
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(_kind_swatch(kind, 30))
	var l := Label.new()
	l.text = BoardWorld.KIND_NAMES[kind]
	l.add_theme_font_size_override("font_size", 17)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)


## +5 / -5 칸이 처음 생기면 안내판에도 한 줄 추가
func _legend_add(kind: String) -> void:
	if _legend_box and not _legend_box.has_node("Row_" + kind):
		_legend_row(_legend_box, kind)


func _kind_swatch(kind: String, px: int) -> Panel:
	var sw := Panel.new()
	sw.custom_minimum_size = Vector2(px, px)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = BoardWorld.TILE_COLORS[kind]
	ss.border_color = Color(0.95, 0.95, 0.9)
	ss.set_border_width_all(2)
	ss.set_corner_radius_all(int(px * 0.2))
	sw.add_theme_stylebox_override("panel", ss)
	var ic := TextureRect.new()
	ic.texture = BoardWorld.ICONS[kind]
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = px * 0.16
	ic.offset_top = px * 0.16
	ic.offset_right = -px * 0.16
	ic.offset_bottom = -px * 0.16
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_child(ic)
	return sw


func _make_chip(p: Dictionary) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _glass(Color(0.02, 0.15, 0.14, 0.7), Color(AQUA, 0.2), 1, 30))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	chip.add_child(h)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ds := StyleBoxFlat.new()
	ds.bg_color = p["color"]
	ds.set_corner_radius_all(11)
	dot.add_theme_stylebox_override("panel", ds)
	h.add_child(dot)
	if String(p["team"]) != "":
		var tl := Label.new()
		tl.text = String(p["team"])
		tl.add_theme_font_size_override("font_size", 15)
		tl.add_theme_color_override("font_color", AQUA)
		h.add_child(tl)
	var l := Label.new()
	l.text = p["name"]
	l.add_theme_font_size_override("font_size", 19)
	h.add_child(l)
	for k in ["coins", "trophies"]:
		var ic := TextureRect.new()
		ic.texture = COIN_TEX if k == "coins" else TROPHY_TEX
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(24, 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var n := Label.new()
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.add_theme_font_size_override("font_size", 19)
		n.add_theme_color_override("font_color", GOLD)
		n.custom_minimum_size = Vector2(26, 0)
		h.add_child(n)
		p[k + "_label"] = n
	_refresh_chip(p)
	return chip


func _refresh_chip(p: Dictionary) -> void:
	if p.has("coins_label"):
		(p["coins_label"] as Label).text = str(p["coins"])
		(p["trophies_label"] as Label).text = str(p["trophies"])


## 지금 차례인 사람 이름표만 또렷하게
func _highlight_chip(p: Dictionary) -> void:
	for q in _pawns:
		var chip: PanelContainer = q["chip"]
		var on: bool = q == p
		chip.modulate = Color(1, 1, 1, 1.0 if on or p.is_empty() else 0.45)
		chip.add_theme_stylebox_override("panel", _glass(Color(0.04, 0.3, 0.27, 0.85) if on else Color(0.02, 0.15, 0.14, 0.7),
			Color(AQUA, 0.9 if on else 0.2), 2 if on else 1, 30))


# ── 매 프레임: 주사위 버튼 · 남은 칸 숫자 · 갈림길 화살표 위치 ─────────
func _update_play_ui() -> void:
	if _dice.visible:
		var r: Rect2 = _dice.screen_rect(_camera).grow(18.0)
		_dice_btn.position = r.position
		_dice_btn.size = r.size
		_click_hint.position = Vector2(r.get_center().x - _click_hint.size.x * 0.5, r.position.y - 46.0 + sin(Time.get_ticks_msec() * 0.008) * 6.0)
	_dice_btn.visible = _awaiting_roll
	_click_hint.visible = _awaiting_roll
	if _steps_label.visible and not _turn_pawn.is_empty():
		var wp: Vector3 = (_turn_pawn["node"] as Node3D).position + Vector3(0, 3.0, 0)
		if not _camera.is_position_behind(wp):
			var sp := _camera.unproject_position(wp)
			_steps_label.position = sp - _steps_label.size * 0.5
	for btn in _arrows:
		var t: int = btn.tile
		var from: Vector3 = world.spaces[int(_turn_pawn["tile"])]["pos"]
		var to: Vector3 = world.spaces[t]["pos"]
		var dir := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
		var at := from + dir * 1.9 + Vector3(0, 0.35, 0)
		if _camera.is_position_behind(at):
			continue
		var s0 := _camera.unproject_position(at)
		var s1 := _camera.unproject_position(at + dir)
		btn.angle = (s1 - s0).angle()
		btn.position = s0 - btn.size * 0.5


# ── 차례 진행 ────────────────────────────────────────────────
## 한 사람 차례: 주사위 → 이동(갈림길 고르기) → 칸에 멈춤. 칸 효과는 _tile_effect 로 따로.
## rig > 0 이면 그 숫자가 나오고, forced = {칸: 다음 칸} 이면 갈림길에서 그쪽만 고를 수 있음 (튜토리얼용)
func _play_turn(p: Dictionary, rig: int = 0, forced: Dictionary = {}) -> void:
	_turn_pawn = p
	_landed = false
	_dice_hit = false
	_highlight_chip(p)
	await _turn_banner(p)
	var node: Node3D = p["node"]
	# 말과 머리 위 주사위가 같이 잘 보이게
	_follow = null
	_move_camera(node.position + Vector3(0, 1.3, 0), 1.25, 0.8)
	await get_tree().create_timer(0.85).timeout
	_dice.show_at(node.position + Vector3(0, DICE_H, 0))
	if _is_auto(p):
		await get_tree().create_timer(1.0).timeout
		_dice_hit = true
	else:
		_awaiting_roll = true
		while not _dice_hit:
			await get_tree().process_frame
		_awaiting_roll = false
	var n: int = rig if rig > 0 else randi_range(1, 6)
	_last_roll = n
	Audio.play("click")
	_pawn_bump(node)
	await _dice.roll_to(n)
	Audio.play("toast")
	_steps_left = n
	_steps_label.text = str(n)
	_steps_label.visible = true
	_pop(_steps_label)
	await get_tree().create_timer(0.45).timeout
	_dice.hide_dice()
	_follow = node
	while _steps_left > 0 and not _game_over:
		var opts := _next_options(p)
		var nxt: int = opts[0]
		if opts.size() > 1:
			if _is_auto(p):
				await get_tree().create_timer(0.5).timeout
				nxt = _cpu_pick_path(p, opts)
			else:
				nxt = await _choose(p, opts, int(forced.get(int(p["tile"]), -1)))
		await _hop(p, nxt)
		_steps_left -= 1
		_steps_label.text = str(_steps_left)
		_pop(_steps_label)
		if nxt == world.start_index:
			_add_coins(p, Rules.START_BONUS)
		# 트로피 칸: 지나가기만 해도 멈춰서 살지 물어봄 → 남은 칸 계속
		if nxt == world.trophy_tile:
			_steps_label.visible = false
			await _offer_trophy(p)
			if _steps_left > 0 and not _game_over:
				_steps_label.visible = true
				_follow = node
	await get_tree().create_timer(0.2).timeout
	_steps_label.visible = false
	Audio.play("add")
	world.bubbles_at(node.position + Vector3(0, 0.2, 0), 12, 0.5, true)
	_landed = true


## CPU 갈림길: 트로피가 있으면 대개 트로피 쪽으로, 아니면 아무 데나
func _cpu_pick_path(p: Dictionary, opts: Array) -> int:
	if world.trophy_tile >= 0 and _rng.randf() < 0.75:
		var best: int = opts[0]
		var bd := 999
		for o in opts:
			var d := _distance(int(o), int(p["tile"]), world.trophy_tile)
			if d < bd:
				bd = d
				best = int(o)
		return best
	return int(opts[_rng.randi() % opts.size()])


## from 칸에서(직전 칸 prev 로 되돌아가지 않고) target 까지 칸 수
func _distance(from: int, prev: int, target: int) -> int:
	var queue := [[from, prev, 0]]
	var seen := {}
	while queue.size() > 0:
		var it: Array = queue.pop_front()
		if int(it[0]) == target:
			return int(it[2])
		var key := "%d_%d" % [it[0], it[1]]
		if seen.has(key) or int(it[2]) > 40:
			continue
		seen[key] = true
		var links: Array = world.spaces[int(it[0])]["links"]
		for l in links:
			if int(l) == int(it[1]) and links.size() > 1:
				continue
			queue.append([int(l), int(it[0]), int(it[2]) + 1])
	return 999


func _next_options(p: Dictionary) -> Array:
	var links: Array = world.spaces[int(p["tile"])]["links"]
	var out := []
	for l in links:
		if int(l) != int(p["prev"]):
			out.append(int(l))
	if out.is_empty():
		out = links.duplicate()
	return out


## 갈림길: 화살표를 띄우고 고를 때까지 기다림 → 고른 칸 번호
func _choose(p: Dictionary, opts: Array, forced: int) -> int:
	_choice = -1
	_forced_next = forced
	_follow = null
	_move_camera((p["node"] as Node3D).position, 1.25, 0.5)
	for t in opts:
		var a := PathArrow.new()
		a.tile = int(t)
		a.locked = forced >= 0 and int(t) != forced
		a.pressed.connect(func() -> void: _choice = a.tile)
		_root.add_child(a)
		_arrows.append(a)
	_choosing = true
	while _choice < 0:
		await get_tree().process_frame
	_choosing = false
	for a in _arrows:
		(a as Node).queue_free()
	_arrows.clear()
	_follow = p["node"]
	return _choice


func _forced_arrow() -> Control:
	for a in _arrows:
		if not a.locked:
			return a
	return _arrows[0] if _arrows.size() > 0 else null


func _pick_forced() -> void:
	var a := _forced_arrow()
	if a:
		_choice = a.tile


func _hit_dice() -> void:
	if _awaiting_roll:
		_dice_hit = true


## 칸 위에 서는 자리 (여럿이 같은 칸이면 살짝 비켜 섬)
func _spot_on(tile: int, p: Dictionary) -> Vector3:
	var top: Vector3 = world.spaces[tile]["pos"]
	if tile == world.start_index:
		return world.start_spots(_pawns.size())[int(p["start_i"])]
	var offs := [Vector3.ZERO, Vector3(0.6, 0, 0.35), Vector3(-0.6, 0, 0.35), Vector3(0, 0, -0.55)]
	var k := 0
	for q in _pawns:
		if q != p and int(q["tile"]) == tile:
			k += 1
	return top + offs[k % offs.size()]


func _hop(p: Dictionary, nxt: int) -> void:
	var node: Node3D = p["node"]
	var from := node.position
	var to := _spot_on(nxt, p)
	p["prev"] = p["tile"]
	p["tile"] = nxt
	var lift := 0.9 + maxf(0.0, to.y - from.y)
	var t := create_tween()
	t.tween_method(func(f: float) -> void: node.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * lift, 0), 0.0, 1.0, HOP_TIME)
	await t.finished
	Audio.play("tick")
	_squash(node)


func _squash(node: Node3D) -> void:
	var t := create_tween()
	t.tween_property(node, "scale", Vector3(1.15, 0.82, 1.15) * PAWN_SCALE, 0.07)
	t.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE, 0.16).set_trans(Tween.TRANS_BACK)


func _pawn_bump(node: Node3D) -> void:
	var y := node.position.y
	var t := create_tween()
	t.tween_property(node, "position:y", y + 0.9, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "position:y", y, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _pop(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var t := create_tween()
	t.tween_property(c, "scale", Vector2.ONE * 1.3, 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _turn_banner(p: Dictionary) -> void:
	var text := tr("YOUR TURN!") if not p["cpu"] else tr("%s'S TURN!") % p["name"]
	await _banner(text, "", 1.0)


## 화면 가운데 큰 글씨 (뿅 나타났다 사라짐)
func _banner(text: String, sub: String, hold: float) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_popup_root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := _outlined_label(text, 76)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(l)
	if sub != "":
		var s := _outlined_label(sub, 28)
		box.add_child(s)
	box.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	box.scale = Vector2.ONE * 0.3
	box.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(box, "modulate:a", 1.0, 0.15)
	t.tween_interval(hold)
	t.tween_property(box, "modulate:a", 0.0, 0.25)
	await t.finished
	box.queue_free()


# ── 동전 · 트로피 ───────────────────────────────────────────
func _add_coins(p: Dictionary, n: int) -> void:
	var before: int = p["coins"]
	p["coins"] = maxi(0, before + n)
	var d: int = int(p["coins"]) - before
	_refresh_chip(p)
	_pop(p["chip"])
	if d > 0:
		Audio.play("add")
		_float_text(p, "+%d" % d, GOLD, COIN_TEX)
	elif d < 0:
		Audio.play("remove")
		_float_text(p, "%d" % d, Color("ff6b6b"), COIN_TEX)


func _add_trophy(p: Dictionary, n: int) -> void:
	p["trophies"] = maxi(0, int(p["trophies"]) + n)
	_refresh_chip(p)
	_pop(p["chip"])
	if n > 0:
		Audio.play("start")
		_float_text(p, "+%d" % n, GOLD, TROPHY_TEX)
		_check_win(p)
	elif n < 0:
		Audio.play("remove")
		_float_text(p, "%d" % n, Color("ff6b6b"), TROPHY_TEX)


## 2대2는 팀원 둘 합계
func _team_trophies(p: Dictionary) -> int:
	if String(p["team"]) == "":
		return int(p["trophies"])
	var t := 0
	for q in _pawns:
		if q["team"] == p["team"]:
			t += int(q["trophies"])
	return t


func _check_win(p: Dictionary) -> void:
	if _team_trophies(p) >= Rules.TROPHIES_TO_WIN:
		_game_over = true
		_winner = p


## 말 머리 위로 떠오르는 +5 같은 글씨
func _float_text(p: Dictionary, text: String, col: Color, icon: Texture2D) -> void:
	var node: Node3D = p["node"]
	var wp := node.position + Vector3(0, 2.6, 0)
	if _camera.is_position_behind(wp):
		return
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var ic := TextureRect.new()
	ic.texture = icon
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.custom_minimum_size = Vector2(38, 38)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(ic)
	var l := _outlined_label(text, 40)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	_popup_root.add_child(box)
	await get_tree().process_frame
	var sp := _camera.unproject_position(wp)
	box.position = sp - box.size * 0.5
	var t := create_tween()
	t.tween_property(box, "position:y", box.position.y - 70.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(box, "modulate:a", 0.0, 0.5).set_delay(0.6)
	await t.finished
	box.queue_free()


## 트로피 칸: 멈춰서 살지 물어봄
func _offer_trophy(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	_follow = null
	_move_camera(node.position + Vector3(0, 1.0, 0), 1.15, 0.5)
	await get_tree().create_timer(0.55).timeout
	if int(p["coins"]) < Rules.TROPHY_PRICE:
		shot_hint = "41_trophy_poor"
		await _banner(tr("A TROPHY!"), tr("You need %d coins to buy it.") % Rules.TROPHY_PRICE, 1.1)
		return
	shot_hint = "41_trophy_offer"
	var c: int = await _ask(p, tr("A TROPHY!"), tr("Buy a trophy for %d coins?") % Rules.TROPHY_PRICE,
		[tr("BUY"), tr("NO THANKS")], 0, TROPHY_TEX, [1] if force_trophy_buy else [])
	if c == 0:
		_add_coins(p, -Rules.TROPHY_PRICE)
		world.hide_trophy()
		_trophy_next_round = _round + Rules.TROPHY_RESPAWN_ROUNDS
		_add_trophy(p, 1)
		await _banner(tr("+1 TROPHY!"), "", 0.7)


## 트로피를 랜덤 칸에 띄움 (진짜 게임에서 라운드 시작 때)
func _spawn_trophy() -> void:
	var pool := []
	for i in world.regular_tiles():
		if _tile_mods.has(i):
			continue
		var taken := false
		for q in _pawns:
			if int(q["tile"]) == i:
				taken = true
		if not taken:
			pool.append(i)
	if pool.is_empty():
		return
	var t: int = pool[_rng.randi() % pool.size()]
	_follow = null
	_move_camera(world.spaces[t]["pos"], 1.6, 1.1)
	await get_tree().create_timer(1.15).timeout
	world.show_trophy(t)
	Audio.play("start")
	shot_hint = "40_trophy_spawn"
	await _banner(tr("A TROPHY APPEARED!"), tr("Pass by and buy it for %d coins!") % Rules.TROPHY_PRICE, 1.4)


# ── 칸 효과 ──────────────────────────────────────────────────
func _tile_effect(p: Dictionary) -> void:
	var tile: int = p["tile"]
	if _tile_mods.has(tile):
		var plus: bool = _tile_mods[tile] == "coin_plus"
		Audio.play("toast")
		_add_coins(p, Rules.COIN_SPACE_AMOUNT if plus else -Rules.COIN_SPACE_AMOUNT)
		await _banner(tr("LUCKY!") if plus else tr("OUCH!"), "", 0.6)
		return
	match String(world.spaces[tile]["kind"]):
		"portal":
			await _warp(p)
		"minigame":
			await _run_minigame(p, false)
		"chance":
			await _draw_card(p)
		"shop":
			await _open_shop(p)
		_:
			await _banner("...", tr("Nothing happens."), 0.6)


## 포탈: 짝 포탈로
func _warp(p: Dictionary) -> void:
	var b: int = world.portal_partner(int(p["tile"]))
	if b >= 0:
		await _warp_to(p, b)


## 어느 칸으로든 순간이동 (빨려 들어가 → 튀어나옴)
func _warp_to(p: Dictionary, b: int) -> void:
	var node: Node3D = p["node"]
	var a: int = p["tile"]
	Audio.play("bubbles")
	var t := create_tween().set_parallel(true)
	t.tween_property(node, "scale", Vector3.ONE * 0.05, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(node, "position:y", node.position.y + 1.3, 0.55)
	t.tween_property(node, "rotation:y", node.rotation.y + TAU * 2.0, 0.55)
	await t.finished
	world.portal_burst(world.spaces[a]["pos"])
	node.visible = false
	_follow = null
	_move_camera(world.spaces[b]["pos"], 1.0, 1.0)
	await get_tree().create_timer(1.0).timeout
	p["prev"] = -1
	p["tile"] = b
	var spot := _spot_on(b, p)
	node.position = spot + Vector3(0, 1.3, 0)
	node.rotation.y = PI
	node.visible = true
	world.portal_burst(world.spaces[b]["pos"])
	Audio.play("add")
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t2.tween_property(node, "position", spot, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await t2.finished
	_follow = node


## 미니게임 (아직 미니게임이 없어서 순위는 운으로 정함). trophy=true 면 1등이 트로피
func _run_minigame(lander: Dictionary, trophy: bool) -> void:
	Audio.play("start")
	await _banner(tr("TROPHY MINIGAME!") if trophy else tr("MINIGAME!"), tr("Minigames are coming soon! For now, luck decides the ranking."), 1.2)
	var order: Array = rig_ranking.duplicate() if rig_ranking.size() == _pawns.size() else _pawns.duplicate()
	if rig_ranking.size() != _pawns.size():
		order.shuffle()
	rig_ranking = []
	# 결과 창
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(AQUA, 0.7))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "RESULTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	v.add_child(title)
	for k in order.size():
		var q: Dictionary = order[k]
		var reward := 0
		var got_trophy := trophy and k == 0
		if not trophy:
			reward = int(Rules.MINIGAME_REWARDS[mini(k, Rules.MINIGAME_REWARDS.size() - 1)])
			if q == lander:
				reward += Rules.MINIGAME_LANDER_BONUS
		v.add_child(_result_row(k + 1, q, reward, got_trophy))
	if not trophy:
		var note := Label.new()
		note.text = tr("Whoever landed on the space gets +%d bonus coins.") % Rules.MINIGAME_LANDER_BONUS
		note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		note.add_theme_font_size_override("font_size", 16)
		note.add_theme_color_override("font_color", Color(PEARL, 0.6))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(note)
	await _show_modal(panel)
	shot_hint = "43_minigame_results"
	await get_tree().create_timer(2.4).timeout
	dim.queue_free()
	for k in order.size():
		var q: Dictionary = order[k]
		if trophy:
			if k == 0:
				_add_trophy(q, 1)
		else:
			var reward := int(Rules.MINIGAME_REWARDS[mini(k, Rules.MINIGAME_REWARDS.size() - 1)])
			if q == lander:
				reward += Rules.MINIGAME_LANDER_BONUS
			_add_coins(q, reward)
	await get_tree().create_timer(0.8).timeout


func _result_row(rank: int, q: Dictionary, reward: int, trophy: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var r := Label.new()
	r.text = "%d" % rank
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	r.custom_minimum_size = Vector2(36, 0)
	r.add_theme_font_size_override("font_size", 30)
	r.add_theme_color_override("font_color", GOLD if rank == 1 else PEARL)
	row.add_child(r)
	row.add_child(_dot(q["color"], 24))
	var n := Label.new()
	n.text = q["name"]
	n.custom_minimum_size = Vector2(170, 0)
	n.add_theme_font_size_override("font_size", 24)
	row.add_child(n)
	if trophy or reward > 0:
		row.add_child(_icon(TROPHY_TEX if trophy else COIN_TEX, 30))
		var m := Label.new()
		m.text = "+1" if trophy else "+%d" % reward
		m.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		m.add_theme_font_size_override("font_size", 24)
		m.add_theme_color_override("font_color", GOLD)
		row.add_child(m)
	return row


# ── 찬스 카드 ────────────────────────────────────────────────
func _draw_card(p: Dictionary) -> void:
	var c: Dictionary = Rules.card(rig_card) if rig_card != "" else Rules.random_card(_rng)
	rig_card = ""
	await _card_popup(c)
	await _apply_card(p, String(c["id"]))


func _card_icon(id: String) -> Texture2D:
	match id:
		"trophy_minigame":
			return BoardWorld.ICONS["minigame"]
		"trophy_thief":
			return TROPHY_TEX
		"warp":
			return BoardWorld.ICONS["portal"]
		"lucky_spaces":
			return BoardWorld.ICONS["coin_plus"]
		"trap_spaces":
			return BoardWorld.ICONS["coin_minus"]
		"roll_again":
			return DICE_ATLAS
	return COIN_TEX


## 카드가 날아와 뒤집히면 앞면에 내용
func _card_popup(c: Dictionary) -> void:
	Audio.play("start")
	var v := get_viewport().get_visible_rect().size
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_root.add_child(holder)
	var size := Vector2(280, 384)
	var back := TextureRect.new()
	back.texture = CARD_TEX
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.size = size
	back.pivot_offset = size * 0.5
	back.position = Vector2(v.x * 0.5 - size.x * 0.5, v.y + 40)
	holder.add_child(back)
	# 앞면
	var front := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("fff6df")
	st.border_color = Color("f4b43a")
	st.set_border_width_all(8)
	st.set_corner_radius_all(26)
	st.set_content_margin_all(22)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 16
	front.add_theme_stylebox_override("panel", st)
	front.custom_minimum_size = size
	front.size = size
	front.pivot_offset = size * 0.5
	front.position = Vector2(v.x * 0.5 - size.x * 0.5, v.y * 0.5 - size.y * 0.5)
	front.scale = Vector2(0.05, 1.0)
	front.visible = false
	holder.add_child(front)
	var fv := VBoxContainer.new()
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	fv.add_theme_constant_override("separation", 14)
	front.add_child(fv)
	var head := Label.new()
	head.text = "CHANCE CARD!"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("c9821c"))
	fv.add_child(head)
	var id := String(c["id"])
	if id in ["warp", "trophy_minigame", "lucky_spaces", "trap_spaces"]:
		var kinds := {"warp": "portal", "trophy_minigame": "minigame", "lucky_spaces": "coin_plus", "trap_spaces": "coin_minus"}
		var kind: String = kinds[id]
		var sw := _kind_swatch(kind, 110)
		sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		fv.add_child(sw)
	else:
		var tex := _card_icon(id)
		if id == "roll_again":
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(256 * 2, 0, 256, 256)
			tex = at
		var ic := _icon(tex, 110)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		fv.add_child(ic)
	var t1 := Label.new()
	t1.text = c["title"]
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t1.add_theme_font_size_override("font_size", 30)
	t1.add_theme_color_override("font_color", Color("3a2a10"))
	fv.add_child(t1)
	var t2 := Label.new()
	t2.text = c["text"]
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t2.custom_minimum_size = Vector2(size.x - 50, 0)
	t2.add_theme_font_size_override("font_size", 18)
	t2.add_theme_color_override("font_color", Color("6a5536"))
	fv.add_child(t2)
	var t := create_tween()
	t.tween_property(back, "position:y", v.y * 0.5 - size.y * 0.5, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(back, "rotation", TAU, 0.45)
	t.tween_property(back, "scale:x", 0.05, 0.14)
	t.tween_callback(func() -> void:
		back.visible = false
		front.visible = true)
	t.tween_property(front, "scale:x", 1.0, 0.2).set_trans(Tween.TRANS_BACK)
	await t.finished
	shot_hint = "42_card_" + id
	await get_tree().create_timer(1.9).timeout
	var t3 := create_tween()
	t3.tween_property(holder, "modulate:a", 0.0, 0.3)
	await t3.finished
	holder.queue_free()


func _others(p: Dictionary) -> Array:
	var out := []
	for q in _pawns:
		if q != p and (String(p["team"]) == "" or q["team"] != p["team"]):
			out.append(q)
	return out


func _apply_card(p: Dictionary, id: String) -> void:
	match id:
		"coins5":
			_add_coins(p, 5)
			await get_tree().create_timer(0.8).timeout
		"coins10":
			_add_coins(p, 10)
			await get_tree().create_timer(0.8).timeout
		"roll_again":
			await _play_turn(p)
			if not _game_over:
				await _tile_effect(p)
		"lucky_spaces":
			await _spawn_coin_spaces(p, "coin_plus")
		"trap_spaces":
			await _spawn_coin_spaces(p, "coin_minus")
		"pickpocket":
			var cands := _others(p)
			if cands.is_empty():
				return
			var target: Dictionary = await _pick_player(p, cands, tr("Who do you take %d coins from?") % Rules.STEAL_COINS, "coins")
			var amount := mini(Rules.STEAL_COINS, int(target["coins"]))
			_add_coins(target, -amount)
			await get_tree().create_timer(0.3).timeout
			_add_coins(p, amount)
			await get_tree().create_timer(0.8).timeout
		"warp":
			var t: int = await _pick_tile(p)
			if t >= 0 and t != int(p["tile"]):
				await _warp_to(p, t)
				if t == world.trophy_tile:
					await _offer_trophy(p)
		"trophy_minigame":
			await _run_minigame(p, true)
		"trophy_thief":
			var cands := []
			for q in _others(p):
				if int(q["trophies"]) > 0:
					cands.append(q)
			if cands.is_empty():
				await _banner(tr("NO LUCK!"), tr("Nobody has a trophy to steal yet."), 1.0)
				return
			var target: Dictionary = await _pick_player(p, cands, tr("Whose trophy do you steal?"), "trophies")
			_add_trophy(target, -1)
			await get_tree().create_timer(0.3).timeout
			_add_trophy(p, 1)
			await get_tree().create_timer(0.8).timeout


## 찬스 카드: 보드 곳곳에 +5 / -5 동전 칸이 생김
func _spawn_coin_spaces(p: Dictionary, kind: String) -> void:
	var pool := []
	for i in world.regular_tiles():
		if not _tile_mods.has(i) and i != world.trophy_tile and String(world.spaces[i]["kind"]) != "chance":
			pool.append(i)
	pool.shuffle()
	_follow = null
	_move_camera(Vector3(0, 0, 1.5), 3.4, 1.0)
	await get_tree().create_timer(1.05).timeout
	_legend_add(kind)
	for k in mini(Rules.COIN_SPACES_PER_CARD, pool.size()):
		var i: int = pool[k]
		_tile_mods[i] = kind
		world.set_tile_look(i, kind)
		Audio.play("toast")
		await get_tree().create_timer(0.35).timeout
	shot_hint = "44_" + kind
	await get_tree().create_timer(1.0).timeout
	focus_on(p, 0.8)
	await get_tree().create_timer(0.8).timeout
	_follow = p["node"]


# ── 상점 ─────────────────────────────────────────────────────
## 들를 때마다 가끔 트로피가 진열됨 (다른 상품은 나중에)
func _open_shop(p: Dictionary) -> void:
	Audio.play("toast")
	var has_trophy := _rng.randf() < Rules.SHOP_TROPHY_CHANCE
	if force_shop_trophy >= 0:
		has_trophy = force_shop_trophy == 1
		force_shop_trophy = -1
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(1.0, 0.6, 0.7, 0.8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(_kind_swatch("shop", 48))
	var title := Label.new()
	title.text = "SHOP"
	title.add_theme_font_size_override("font_size", 44)
	head.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	_shop_buy = null
	for k in 3:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(150, 190)
		slot.add_theme_stylebox_override("panel", _glass(Color(0.06, 0.26, 0.24, 0.8), Color(GOLD, 0.7) if k == 0 and has_trophy else Color(AQUA, 0.3), 2, 18))
		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_theme_constant_override("separation", 6)
		slot.add_child(sv)
		if k == 0 and has_trophy:
			var ic := _icon(TROPHY_TEX, 72)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			sv.add_child(ic)
			var price := HBoxContainer.new()
			price.alignment = BoxContainer.ALIGNMENT_CENTER
			price.add_child(_icon(COIN_TEX, 24))
			var pl := Label.new()
			pl.text = str(Rules.SHOP_TROPHY_PRICE)
			pl.add_theme_color_override("font_color", GOLD)
			price.add_child(pl)
			sv.add_child(price)
			var buy := _glass_button("BUY")
			buy.custom_minimum_size = Vector2(110, 44)
			buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			buy.disabled = int(p["coins"]) < Rules.SHOP_TROPHY_PRICE
			sv.add_child(buy)
			_shop_buy = buy
			buy.pressed.connect(func() -> void:
				if buy.disabled:
					return
				buy.disabled = true
				buy.text = "SOLD"
				_add_coins(p, -Rules.SHOP_TROPHY_PRICE)
				_add_trophy(p, 1))
		else:
			var q := Label.new()
			q.text = "?"
			q.add_theme_font_size_override("font_size", 64)
			q.add_theme_color_override("font_color", Color(PEARL, 0.5))
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sv.add_child(q)
		row.add_child(slot)
	var msg := Label.new()
	msg.text = "More items are coming soon!"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(PEARL, 0.8))
	v.add_child(msg)
	var close := _glass_button("CLOSE")
	close.custom_minimum_size = Vector2(200, 56)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.set_meta("sfx", "back")
	v.add_child(close)
	_shop_panel = dim
	_shop_close = close
	_shop_open = true
	close.pressed.connect(_close_shop)
	await _show_modal(panel)
	shot_hint = "45_shop_trophy" if has_trophy else "45_shop"
	if _is_auto(p):
		await get_tree().create_timer(1.4).timeout
		if _shop_buy and not _shop_buy.disabled:
			_shop_buy.pressed.emit()
			await get_tree().create_timer(0.8).timeout
		_close_shop()
	while _shop_open:
		await get_tree().process_frame


func _close_shop() -> void:
	if not _shop_open:
		return
	_shop_open = false
	if is_instance_valid(_shop_panel):
		_shop_panel.queue_free()


# ── 창 · 고르기 ──────────────────────────────────────────────
func _modal_dim() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0, 0.04, 0.04, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_root.add_child(dim)
	return dim


func _modal_panel(dim: Control, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := _glass(Color(0.03, 0.17, 0.16, 0.96), border, 3, 26)
	st.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", st)
	dim.add_child(panel)
	return panel


func _show_modal(panel: Control) -> void:
	await get_tree().process_frame
	panel.position = (get_viewport().get_visible_rect().size - panel.size) * 0.5
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * 0.6
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _icon(tex: Texture2D, px: int) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _dot(c: Color, px: int) -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = c
	ds.set_corner_radius_all(px / 2)
	dot.add_theme_stylebox_override("panel", ds)
	return dot


## 물어보는 창 → 고른 버튼 번호. 자동이면 auto_choice 를 잠깐 뒤에 고름. locked 번호는 못 누름 (튜토리얼)
func _ask(p: Dictionary, title: String, body: String, options: Array, auto_choice: int, icon: Texture2D = null, locked: Array = []) -> int:
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(GOLD, 0.8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	if icon:
		var ic := _icon(icon, 80)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var t := Label.new()
	t.text = title
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_color_override("font_color", Color(PEARL, 0.85))
	v.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_dialog_buttons = []
	_dialog_choice = -1
	for k in options.size():
		var btn := _glass_button(options[k])
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.custom_minimum_size = Vector2(190, 58)
		btn.disabled = k in locked
		var idx := k
		btn.pressed.connect(func() -> void: _dialog_choice = idx)
		row.add_child(btn)
		_dialog_buttons.append(btn)
	_dialog_open = true
	await _show_modal(panel)
	if _is_auto(p):
		await get_tree().create_timer(1.5).timeout
		_dialog_choice = auto_choice
	while _dialog_choice < 0:
		await get_tree().process_frame
	_dialog_open = false
	_dialog_buttons = []
	dim.queue_free()
	return _dialog_choice


## 열린 창의 버튼 누르기 (튜토리얼 자동 점검용)
func _press_dialog(i: int) -> void:
	if i < _dialog_buttons.size():
		(_dialog_buttons[i] as Button).pressed.emit()


func _dialog_button(i: int) -> Control:
	return _dialog_buttons[i] if i < _dialog_buttons.size() else null


## 사람 고르기 (동전 뺏기 · 트로피 뺏기)
func _pick_player(p: Dictionary, cands: Array, prompt: String, by: String) -> Dictionary:
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(AQUA, 0.7))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = prompt
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	v.add_child(t)
	_dialog_buttons = []
	_dialog_choice = -1
	for k in cands.size():
		var q: Dictionary = cands[k]
		var btn := _glass_button("")
		btn.custom_minimum_size = Vector2(440, 66)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 12)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 20
		btn.add_child(h)
		h.add_child(_dot(q["color"], 24))
		var n := Label.new()
		n.text = q["name"]
		n.custom_minimum_size = Vector2(170, 0)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(n)
		for key in ["coins", "trophies"]:
			h.add_child(_icon(COIN_TEX if key == "coins" else TROPHY_TEX, 26))
			var m := Label.new()
			m.text = str(q[key])
			m.custom_minimum_size = Vector2(44, 0)
			m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			m.add_theme_color_override("font_color", GOLD)
			h.add_child(m)
		var idx := k
		btn.pressed.connect(func() -> void: _dialog_choice = idx)
		v.add_child(btn)
		_dialog_buttons.append(btn)
	_dialog_open = true
	await _show_modal(panel)
	shot_hint = "46_pick_player"
	if _is_auto(p):
		await get_tree().create_timer(1.5).timeout
		var best := 0
		for k in cands.size():
			if int(cands[k][by]) > int(cands[best][by]):
				best = k
		_dialog_choice = best
	while _dialog_choice < 0:
		await get_tree().process_frame
	_dialog_open = false
	_dialog_buttons = []
	dim.queue_free()
	return cands[_dialog_choice]


## 원하는 칸 고르기 (순간이동 카드): 보드 전체를 보여주고 칸을 클릭
func _pick_tile(p: Dictionary) -> int:
	_follow = null
	_move_camera(Vector3(0, 0, 1.5), 3.6, 1.0)
	await get_tree().create_timer(1.0).timeout
	var prompt := _outlined_label(tr("Click the space you want to warp to!"), 34)
	prompt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.position.y = 140
	_popup_root.add_child(prompt)
	if not _pick_marker:
		var tm := TorusMesh.new()
		tm.inner_radius = 1.2
		tm.outer_radius = 1.45
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = AQUA
		_pick_marker = MeshInstance3D.new()
		_pick_marker.mesh = tm
		_pick_marker.material_override = mm
		add_child(_pick_marker)
	_pick_marker.visible = false
	_picked_tile = -1
	_hover_tile = -1
	shot_hint = "47_pick_tile"
	if _is_auto(p):
		await get_tree().create_timer(1.2).timeout
		var t := world.trophy_tile
		if t < 0 or t == int(p["tile"]):
			var pool: Array = world.regular_tiles()
			t = pool[_rng.randi() % pool.size()]
		_show_pick_marker(t)
		await get_tree().create_timer(0.6).timeout
		_picked_tile = t
	else:
		_tile_catcher = Control.new()
		_tile_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tile_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		_tile_catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_tile_catcher.gui_input.connect(_on_pick_input)
		_popup_root.add_child(_tile_catcher)
		_picking_tile = true
		while _picked_tile < 0:
			await get_tree().process_frame
		_picking_tile = false
		_tile_catcher.queue_free()
	prompt.queue_free()
	_pick_marker.visible = false
	return _picked_tile


func _on_pick_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var best := -1
		var bd := 70.0
		for i in world.spaces.size():
			var wp: Vector3 = world.spaces[i]["pos"]
			if _camera.is_position_behind(wp) or i == world.start_index:
				continue
			var d := _camera.unproject_position(wp).distance_to(mm.position)
			if d < bd:
				bd = d
				best = i
		if best != _hover_tile:
			_hover_tile = best
			if best >= 0:
				_show_pick_marker(best)
				Audio.play("hover", 0.05)
			else:
				_pick_marker.visible = false
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _hover_tile >= 0:
		Audio.play("click")
		_picked_tile = _hover_tile


func _show_pick_marker(i: int) -> void:
	_pick_marker.visible = true
	_pick_marker.position = (world.spaces[i]["pos"] as Vector3) + Vector3(0, 0.15, 0)


# ── 결과 화면 ────────────────────────────────────────────────
func _ranking() -> Array:
	var order := _pawns.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _team_trophies(a) != _team_trophies(b):
			return _team_trophies(a) > _team_trophies(b)
		if int(a["trophies"]) != int(b["trophies"]):
			return int(a["trophies"]) > int(b["trophies"])
		return int(a["coins"]) > int(b["coins"]))
	return order


func _show_results() -> void:
	if _winner.is_empty():
		_winner = _ranking()[0]
	var w := _winner
	_follow = null
	_move_camera((w["node"] as Node3D).position, 1.1, 1.2)
	await get_tree().create_timer(1.2).timeout
	for k in 3:
		world.bubbles_at((w["node"] as Node3D).position + Vector3(0, 0.5, 0), 30, 0.8, true)
		world.portal_burst((w["node"] as Node3D).position)
		await get_tree().create_timer(0.25).timeout
	var head: String = (tr("TEAM %s WINS!") % w["team"]) if String(w["team"]) != "" else (tr("%s WINS!") % w["name"])
	await _banner(head, "", 1.6)
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(GOLD, 0.9))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = head
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	var order := _ranking()
	for k in order.size():
		var q: Dictionary = order[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var r := Label.new()
		r.text = str(k + 1)
		r.custom_minimum_size = Vector2(36, 0)
		r.add_theme_font_size_override("font_size", 30)
		row.add_child(r)
		row.add_child(_dot(q["color"], 24))
		var n := Label.new()
		n.text = ("%s · %s" % [q["team"], q["name"]]) if String(q["team"]) != "" else String(q["name"])
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.custom_minimum_size = Vector2(200, 0)
		n.add_theme_font_size_override("font_size", 24)
		row.add_child(n)
		for key in ["trophies", "coins"]:
			row.add_child(_icon(TROPHY_TEX if key == "trophies" else COIN_TEX, 30))
			var m := Label.new()
			m.text = str(q[key])
			m.custom_minimum_size = Vector2(50, 0)
			m.add_theme_font_size_override("font_size", 24)
			m.add_theme_color_override("font_color", GOLD)
			row.add_child(m)
		v.add_child(row)
	var back := _glass_button("BACK TO MENU")
	back.custom_minimum_size = Vector2(260, 58)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_exit_to_menu)
	v.add_child(back)
	await _show_modal(panel)
	shot_hint = "48_results"
	Audio.play("start")
	if GameState.debug_autoplay:
		await get_tree().create_timer(3.0).timeout
		_exit_to_menu()


# ── 튜토리얼 도우미 ──────────────────────────────────────────
## 칸 윗면 네 모서리의 화면 위치 (스포트라이트를 칸 모양에 딱 맞춤)
func _tile_quad(i: int) -> PackedVector2Array:
	var sp: Dictionary = world.spaces[i]
	var half: float = (BoardWorld.TILE + (0.2 if sp["kind"] == "junction" else 0.0)) * 0.5
	var b := Basis(Vector3.UP, float(sp["yaw"]))
	var top: Vector3 = sp["pos"]
	var out := PackedVector2Array()
	for c in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]:
		var wp: Vector3 = top + b * c
		if _camera.is_position_behind(wp):
			return PackedVector2Array()
		out.append(_camera.unproject_position(wp))
	return out


## 말이 선 칸으로 카메라를 늘 같은 거리에서 맞추고, 그 칸만 딱 밝힘
func _explain_tile(p: Dictionary, text: String, shot: String) -> void:
	var i: int = p["tile"]
	_follow = null
	_move_camera(world.spaces[i]["pos"], TILE_ZOOM, 0.7)
	await get_tree().create_timer(0.75).timeout
	await _say({"text": text, "quad": func() -> PackedVector2Array: return _tile_quad(i), "shot": shot})


## MY PAWN 버튼 안내 전에 카메라를 딴 데로 돌려 둠
func _look_away() -> void:
	_focused = false
	_follow = null
	_move_camera(Vector3(-6, 0, -8), 2.2, 0.8)


func _say(st: Dictionary) -> void:
	_overlay.show_step(st)
	await _overlay.step_done


func _wait_for(cond: Callable) -> void:
	while not cond.call():
		await get_tree().process_frame


## 지금 자리에서 target 칸까지 가는 길 (되돌아가기 없이) → {rig: 칸 수, forced: {칸: 다음 칸}}
func _plan(p: Dictionary, target: int) -> Dictionary:
	var start := [int(p["tile"]), int(p["prev"])]
	var seen := {}
	var queue := [[start[0], start[1], []]]
	while queue.size() > 0:
		var it: Array = queue.pop_front()
		var cur: int = it[0]
		var prev: int = it[1]
		var path: Array = it[2]
		if cur == target and path.size() > 0:
			var forced := {}
			var at: int = start[0]
			for nx in path:
				forced[at] = nx
				at = nx
			return {"rig": mini(path.size(), 6), "forced": forced}
		var key := "%d_%d" % [cur, prev]
		if seen.has(key) or path.size() >= 6:
			continue
		seen[key] = true
		for l in world.spaces[cur]["links"]:
			if int(l) == prev and world.spaces[cur]["links"].size() > 1:
				continue
			queue.append([int(l), cur, path + [int(l)]])
	return {"rig": 0, "forced": {}}


func _tile_near(x: float, z: float) -> int:
	var best := 0
	var bd := INF
	for i in world.spaces.size():
		var q: Vector3 = world.spaces[i]["base"]
		var d := Vector2(q.x - x, q.z - z).length()
		if d < bd:
			bd = d
			best = i
	return best


# ── 들어가기 연출 ────────────────────────────────────────────
func _intro() -> void:
	# 1) 보드판처럼 위에서 내려다보기
	_focus = Vector3(0, 0, 2.0)
	_zoom = ZOOM_MAX * 1.1
	_apply_camera()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.7)
	t.parallel().tween_property(_title, "modulate:a", 1.0, 0.7)
	await get_tree().create_timer(1.8).timeout
	# 2) 판 속으로 쑥
	Audio.play("bubbles")
	create_tween().tween_property(_title, "modulate:a", 0.0, 0.5)
	var me: Dictionary = _my_pawn()
	_move_camera(me["spot"], 1.0, 2.6)
	await _cam_tween.finished
	# 3) 말들이 위에서 퐁퐁
	for i in _pawns.size():
		_drop_pawn(_pawns[i])
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(1.0).timeout
	_intro_done = true
	_my_pawn_btn.visible = true
	_legend.visible = true
	_after_intro()


func _drop_pawn(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	var spot: Vector3 = p["spot"]
	node.visible = true
	node.position = spot + Vector3(0, 9.0, 0)
	var t := create_tween()
	t.tween_property(node, "position", spot, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.45).timeout
	Audio.play("add")
	world.bubbles_at(spot + Vector3(0, 0.2, 0), 18, 0.5, true)


## 들어가기 연출이 끝나면 (상속해서 채움: 튜토리얼 / 게임 진행)
func _after_intro() -> void:
	pass


func _exit_to_menu() -> void:
	if _fade.color.a > 0.5 and not _intro_done:
		return
	GameState.tutorial_active = false
	_fade.get_parent().move_child(_fade, -1)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.4)
	await t.finished
	get_tree().change_scene_to_file(MAIN_MENU)
