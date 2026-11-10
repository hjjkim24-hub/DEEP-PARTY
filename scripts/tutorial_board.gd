extends Node3D
## 튜토리얼 보드 (3D). 보드 고르기에서 튜토리얼 상자를 열면 여기로 와요.
## 1) 보드판을 위에서 내려다보다가  2) 카메라가 판 속으로 쑥 들어가 내 말 가까이 가고
## 3) 말들이 위에서 START 광장으로 떨어져요.
## 4) 직접 해 보면서 배워요: 주사위 굴리기 → 갈림길 고르기 → 칸에 멈추기.
##    튜토리얼은 주사위 숫자를 정해 둬서 일반 → 포탈 → 미니게임 → 상점 → 찬스 칸 순서로 꼭 멈춰요.
##    CPU 차례도 한 번 보여줘요 (차례마다 그 사람 말을 카메라가 가까이 비춤).
##
## 게임 진행 부분(_play_turn, _tile_effect …)은 나중에 진짜 보드 게임에서도 그대로 쓸 수 있게 만들었어요.

const BoardWorld := preload("res://scripts/world3d/board_world.gd")
const Pawn3D := preload("res://scripts/world3d/pawn3d.gd")
const Dice3D := preload("res://scripts/world3d/dice3d.gd")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
const PathArrow := preload("res://scripts/ui/path_arrow.gd")
const UIFont := preload("res://fonts/Poppins-Bold.ttf")
const CARD_TEX := preload("res://textures/tiles/card_chance.png")
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
var _pawns: Array = []        ## {slot, name, color, cpu, node, spot, tile, prev, chip}
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
var _popup_root: Control


func _ready() -> void:
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
	_title.text = "TUTORIAL BOARD"
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
	var head := Label.new()
	head.text = "SPACES"
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", AQUA)
	v.add_child(head)
	for kind in BoardWorld.KIND_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		row.add_child(_kind_swatch(kind, 30))
		var l := Label.new()
		l.text = BoardWorld.KIND_NAMES[kind]
		l.add_theme_font_size_override("font_size", 17)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	return panel


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
	var l := Label.new()
	l.text = p["name"]
	l.add_theme_font_size_override("font_size", 19)
	h.add_child(l)
	return chip


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
	if p["cpu"]:
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
	while _steps_left > 0:
		var opts := _next_options(p)
		var nxt: int = opts[0]
		if opts.size() > 1:
			if p["cpu"]:
				await get_tree().create_timer(0.5).timeout
				nxt = opts[randi() % opts.size()]
			else:
				nxt = await _choose(p, opts, int(forced.get(int(p["tile"]), -1)))
		await _hop(p, nxt)
		_steps_left -= 1
		_steps_label.text = str(_steps_left)
		_pop(_steps_label)
	await get_tree().create_timer(0.2).timeout
	_steps_label.visible = false
	Audio.play("add")
	world.bubbles_at(node.position + Vector3(0, 0.2, 0), 12, 0.5, true)
	_landed = true


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


# ── 칸 효과 ──────────────────────────────────────────────────
func _tile_effect(p: Dictionary) -> void:
	var tile: int = p["tile"]
	match String(world.spaces[tile]["kind"]):
		"portal":
			await _warp(p)
		"minigame":
			Audio.play("start")
			await _banner(tr("MINIGAME!"), tr("Minigames are coming soon!"), 1.3)
		"chance":
			await _chance_card_popup()
		"shop":
			await _open_shop(p["cpu"])
		_:
			await _banner("...", tr("Nothing happens."), 0.6)


## 포탈: 고리 속으로 빨려 들어가 → 짝 포탈에서 튀어나옴
func _warp(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	var a: int = p["tile"]
	var b: int = world.portal_partner(a)
	if b < 0:
		return
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


## 찬스 카드: 카드가 날아와 뒤집힘 (카드 내용은 나중에)
func _chance_card_popup() -> void:
	Audio.play("start")
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_root.add_child(holder)
	var v := get_viewport().get_visible_rect().size
	var card := TextureRect.new()
	card.texture = CARD_TEX
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	card.size = Vector2(240, 330)
	card.pivot_offset = card.size * 0.5
	card.position = Vector2(v.x * 0.5 - 120, v.y + 40)
	holder.add_child(card)
	var l := _outlined_label(tr("CHANCE CARD!"), 54)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.size = Vector2(v.x, 80)
	l.position = Vector2(0, v.y * 0.5 - 290)
	l.modulate.a = 0.0
	holder.add_child(l)
	var s := _outlined_label(tr("Chance Cards are coming soon!"), 28)
	s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	s.size = Vector2(v.x, 50)
	s.position = Vector2(0, v.y * 0.5 + 190)
	s.modulate.a = 0.0
	holder.add_child(s)
	var t := create_tween()
	t.tween_property(card, "position:y", v.y * 0.5 - 165, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(card, "rotation", TAU, 0.45)
	t.tween_property(card, "scale:x", 0.05, 0.14)
	t.tween_property(card, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(l, "modulate:a", 1.0, 0.2)
	t.parallel().tween_property(s, "modulate:a", 1.0, 0.2)
	t.tween_interval(1.6)
	t.tween_property(holder, "modulate:a", 0.0, 0.3)
	await t.finished
	holder.queue_free()


## 상점 창 (상품은 나중에). 사람이면 CLOSE 를 누를 때까지, CPU 는 잠깐 보고 닫음.
func _open_shop(cpu: bool) -> void:
	Audio.play("toast")
	var dim := ColorRect.new()
	dim.color = Color(0, 0.04, 0.04, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_root.add_child(dim)
	var panel := PanelContainer.new()
	var st := _glass(Color(0.03, 0.17, 0.16, 0.96), Color(1.0, 0.6, 0.7, 0.8), 3, 26)
	st.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", st)
	dim.add_child(panel)
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
	for k in 3:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(140, 160)
		slot.add_theme_stylebox_override("panel", _glass(Color(0.06, 0.26, 0.24, 0.8), Color(AQUA, 0.3), 2, 18))
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 64)
		q.add_theme_color_override("font_color", Color(PEARL, 0.5))
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(q)
		row.add_child(slot)
	var msg := Label.new()
	msg.text = "Items are coming soon!"
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
	await get_tree().process_frame
	panel.position = (get_viewport().get_visible_rect().size - panel.size) * 0.5
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * 0.6
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if cpu:
		await get_tree().create_timer(1.4).timeout
		_close_shop()
	while _shop_open:
		await get_tree().process_frame


func _close_shop() -> void:
	if not _shop_open:
		return
	_shop_open = false
	if is_instance_valid(_shop_panel):
		_shop_panel.queue_free()


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
	_run_tutorial()


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


# ── 튜토리얼 (직접 해 보기) ──────────────────────────────────
## 내 차례 한 번: 주사위 안내 → (갈림길 안내) → 칸 설명 → 칸 효과
func _guided_turn(target: int, roll_text: String, fork_text: String, tile_text: String, shots: Array) -> void:
	var me := _my_pawn()
	var plan := _plan(me, target)
	_play_turn(me, int(plan["rig"]), plan["forced"])
	await _wait_for(func() -> bool: return _awaiting_roll)
	await _say({"text": roll_text, "target": func() -> Control: return _dice_btn, "pad": 6.0,
		"until": func() -> bool: return _dice_hit, "auto": _hit_dice, "shot": shots[0]})
	while not _landed:
		if _choosing:
			var txt := tr(fork_text)
			if "%d" in txt:
				txt = txt % _last_roll
			await _say({"text": txt, "target": func() -> Control: return _forced_arrow(), "pad": 4.0,
				"until": func() -> bool: return not _choosing, "auto": _pick_forced, "shot": shots[1]})
		await get_tree().process_frame
	await _explain_tile(me, tile_text, shots[2])
	await _tile_effect(me)


func _run_tutorial() -> void:
	_overlay = TutorialOverlay.new()
	_overlay.name = "Tutorial"
	_ui.add_child(_overlay)
	_overlay.finished.connect(_on_tutorial_finished)
	_overlay.skipped.connect(_exit_to_menu)
	var me := _my_pawn()

	await _say({"text": "You've jumped into the board! In DEEP PARTY, your pawn walks around inside the board world.",
		"target": func() -> Control: return _start_marker, "shot": "17_world_start"})
	await _say({"text": "Paths split off at the arrow spaces and loop back around, so there's no finish line. Take any road you like!",
		"enter": func() -> void: _move_camera(Vector3(0, 0, 0), 3.2, 1.8), "dim": false, "shot": "18_world_overview"})
	await _say({"text": "Climb the stairs up the coral hill, cross the bridge, hop across the stone pillars and go through the rock tunnel!",
		"enter": func() -> void: _move_camera(Vector3(-13, 3.5, -11), 1.7, 1.6), "dim": false, "shot": "19_world_plateau"})
	await _say({"text": "Drag with the mouse to look around, and roll the mouse wheel to zoom in and out.",
		"target": func() -> Control: return _screen_marker, "pad": 0.0})

	# 1) 주사위 · 갈림길 · 일반 칸
	await _guided_turn(_tile_near(11.2, 0.0),
		"It's your turn! Click the dice above your pawn to roll it.",
		"You rolled a %d! You're at a fork in the road. Click the glowing arrow to choose your way.",
		"Plain space! Nothing happens here. Take a breather.",
		["22_dice", "23_fork", "24_plain"])

	# 2) CPU 차례 구경
	var cpus := []
	for p in _pawns:
		if p["cpu"]:
			cpus.append(p)
	if cpus.size() > 0:
		await _say({"text": "Everyone takes turns. On each turn, the camera zooms in on that player's pawn. Let's watch the CPU!", "dim": false})
		for c in cpus:
			await _play_turn(c)
			await _tile_effect(c)

	# 3) 포탈
	await _guided_turn(_tile_near(14.5, -7.6),
		"Your turn again! Roll the dice.",
		"Another fork! Let's head for the stone pillars this time.",
		"Portal space! You'll warp to the portal on the other side of the board.",
		["", "", "25_portal"])
	await _say({"text": "Whoosh! You popped out on the other side of the board.", "dim": false, "shot": "26_warped"})

	# 4) 미니게임
	await _guided_turn(_tile_near(-7.0, 12.4),
		"Roll again!",
		"After a warp, you can pick which way to go. Let's go this way!",
		"Minigame space! Stop here and a minigame begins. There are lots of them all over the board.",
		["", "", "27_minigame"])

	# 5) 상점
	var shop_target := _tile_near(6.4, 13.0)
	var plan := _plan(me, shop_target)
	_play_turn(me, int(plan["rig"]), plan["forced"])
	await _wait_for(func() -> bool: return _awaiting_roll)
	await _say({"text": "Keep rolling!", "target": func() -> Control: return _dice_btn, "pad": 6.0,
		"until": func() -> bool: return _dice_hit, "auto": _hit_dice})
	await _wait_for(func() -> bool: return _landed)
	await _explain_tile(me, "Shop space! Drop by the stall to buy items.", "28_shop")
	_open_shop(false)
	await _wait_for(func() -> bool: return _shop_open)
	await get_tree().create_timer(0.4).timeout
	await _say({"text": "Items will be added later. Click CLOSE to leave the shop.",
		"target": func() -> Control: return _shop_close, "pad": 8.0,
		"until": func() -> bool: return not _shop_open, "auto": _close_shop, "shot": "29_shop_window"})

	# 6) 찬스
	await _guided_turn(_tile_near(11.5, 8.7),
		"One more roll!",
		"Pick a way!",
		"Chance space! You draw a random Chance Card.",
		["", "", "30_chance"])

	await _say({"text": "Forgot what a space does? Check the guide in the bottom left.",
		"target": func() -> Control: return _legend, "shot": "31_legend"})
	await _say({"text": "Lost? Press MY PAWN to jump back to your pawn.",
		"enter": func() -> void: _look_away(),
		"target": func() -> Control: return _my_pawn_btn,
		"until": func() -> bool: return _focused,
		"auto": func() -> void: _focus_my_pawn(),
		"shot": "20_world_my_pawn"})
	_highlight_chip({})
	await _say({"text": "That's all the basics! How to win will be explained here soon. Stay tuned!"})
	_overlay.finish()


func _on_tutorial_finished() -> void:
	GameState.tutorial_active = false
	var banner := Label.new()
	banner.text = "TUTORIAL COMPLETE!"
	banner.add_theme_font_size_override("font_size", 72)
	banner.add_theme_color_override("font_outline_color", DEEP)
	banner.add_theme_constant_override("outline_size", 18)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.modulate.a = 0.0
	_fade.get_parent().add_child(banner)
	Audio.play("start")
	var t := create_tween()
	t.tween_property(banner, "modulate:a", 1.0, 0.3)
	t.tween_interval(1.6)
	await t.finished
	_exit_to_menu()


func _exit_to_menu() -> void:
	if _fade.color.a > 0.5 and not _intro_done:
		return
	GameState.tutorial_active = false
	_fade.get_parent().move_child(_fade, -1)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.4)
	await t.finished
	get_tree().change_scene_to_file(MAIN_MENU)
