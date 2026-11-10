extends Node3D
## 튜토리얼 보드 (3D). 보드 고르기에서 튜토리얼 상자를 열면 여기로 와요.
## 칸 종류(일반·찬스·미니게임·포탈·상점)를 하나씩 찾아가 보여주고, 왼쪽 아래에 안내판.
## 1) 보드판을 위에서 내려다보다가  2) 카메라가 판 속으로 쑥 들어가 내 말 가까이 가고
## 3) 말들이 위에서 START 광장으로 떨어져요.  이후 튜토리얼 안내 (규칙은 나중에 추가).
## 카메라는 '지금 보는 말'을 가까이 따라가요 (나중에 차례마다 그 사람 말로 바꾸면 됨: focus_on()).

const BoardWorld := preload("res://scripts/world3d/board_world.gd")
const Pawn3D := preload("res://scripts/world3d/pawn3d.gd")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
const UIFont := preload("res://fonts/Poppins-Bold.ttf")
const MAIN_MENU := "res://scenes/main_menu.tscn"

const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const PAWN_SCALE := 1.7            ## 말 키 (미터)
const CLOSE := Vector3(0, 3.4, 6.2)   ## 말 가까이 볼 때 카메라 위치 (말 기준)
const ZOOM_MIN := 0.55
const ZOOM_MAX := 4.5

var world: BoardWorld
var _pawns: Array = []        ## {slot, name, color, node: Node3D, spot: Vector3}
var _camera: Camera3D
var _focus := Vector3.ZERO    ## 카메라가 바라보는 점
var _zoom := 1.0              ## 1 = 가까이, 클수록 멀리
var _cam_tween: Tween
var _ui: CanvasLayer
var _chips: HBoxContainer
var _my_pawn_btn: Button
var _start_marker: Control
var _screen_marker: Control
var _tile_marker: Control     ## 튜토리얼이 가리키는 칸 (화면 위치를 매 프레임 따라감)
var _marker_tile := -1
var _demo_token := 0
var _legend: PanelContainer
var _overlay
var _fade: ColorRect
var _title: Label
var _intro_done := false
var _focused := false
var _dragging := false


func _ready() -> void:
	world = BoardWorld.new()
	add_child(world)
	_setup_pawns()
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 400.0
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
		if p.get("kind", "") == "cpu":
			cpu_no += 1
			pname = tr("CPU %d") % cpu_no
		list.append({"slot": slot, "name": pname, "color": GameState.player_color(slot), "look": GameState.look(slot)})
	if list.is_empty():
		list.append({"slot": 0, "name": "You", "color": GameState.PALETTE[0], "look": {}})
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


func _process(_delta: float) -> void:
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
	_update_tile_marker()


func _update_tile_marker() -> void:
	if _marker_tile < 0:
		return
	var sp: Dictionary = world.spaces[_marker_tile]
	var kind: String = sp["kind"]
	var rr := 3.4 if kind == "shop" else 1.3
	var hh := 0.3 if kind == "plain" or kind == "minigame" else 3.3
	var top: Vector3 = sp["pos"]
	var r := Rect2()
	var first := true
	for c in [Vector3(-rr, 0, -rr), Vector3(rr, 0, -rr), Vector3(-rr, 0, rr), Vector3(rr, 0, rr),
			Vector3(-rr * 0.6, hh, 0), Vector3(rr * 0.6, hh, 0)]:
		var wp: Vector3 = top + c
		if _camera.is_position_behind(wp):
			continue
		var p2 := _camera.unproject_position(wp)
		if first:
			r = Rect2(p2, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p2)
	_tile_marker.position = r.position
	_tile_marker.size = r.size


func _move_camera(focus: Vector3, zoom: float, time: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(self, "_focus", focus, time)
	_cam_tween.tween_property(self, "_zoom", zoom, time)


## 이 말을 가까이 보기 (차례가 생기면 차례마다 부르면 됨)
func focus_on(p: Dictionary, time: float = 0.9) -> void:
	_move_camera((p["node"] as Node3D).position, 1.0, time)


## 튜토리얼에서 칸 하나 보여주기
func _show_tile(i: int, zoom: float = 1.5) -> void:
	_demo_token += 1
	if i < 0:
		return
	_marker_tile = i
	_move_camera(world.spaces[i]["pos"], zoom, 1.3)


func _my_spot() -> Vector3:
	return _my_pawn()["spot"]


## 포탈 칸 보여주고 → 슝 → 반대편 포탈로 카메라 이동
func _portal_demo() -> void:
	var a: int = world.nearest_of_kind("portal", _my_spot())
	_show_tile(a, 1.8)
	var token := _demo_token
	var b: int = world.portal_partner(a)
	await get_tree().create_timer(2.0).timeout
	if token != _demo_token or b < 0:
		return
	Audio.play("bubbles")
	world.portal_burst(world.spaces[a]["pos"])
	_marker_tile = b
	_move_camera(world.spaces[b]["pos"], 1.8, 0.9)
	await get_tree().create_timer(0.9).timeout
	if token != _demo_token:
		return
	Audio.play("add")
	world.portal_burst(world.spaces[b]["pos"])


func _back_to_my_pawn() -> void:
	_demo_token += 1
	_marker_tile = -1
	_focus_my_pawn()


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

	_start_marker = Control.new()
	_start_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_start_marker)
	_screen_marker = Control.new()
	_screen_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_screen_marker)
	_tile_marker = Control.new()
	_tile_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tile_marker)

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
		_chips.add_child(_make_chip(p))

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
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(30, 30)
		var ss := StyleBoxFlat.new()
		ss.bg_color = BoardWorld.TILE_COLORS[kind]
		ss.border_color = Color(0.95, 0.95, 0.9)
		ss.set_border_width_all(2)
		ss.set_corner_radius_all(6)
		sw.add_theme_stylebox_override("panel", ss)
		row.add_child(sw)
		var ic := TextureRect.new()
		ic.texture = BoardWorld.ICONS[kind]
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 5
		ic.offset_top = 5
		ic.offset_right = -5
		ic.offset_bottom = -5
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(ic)
		var l := Label.new()
		l.text = BoardWorld.KIND_NAMES[kind]
		l.add_theme_font_size_override("font_size", 17)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	return panel


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
	_start_tutorial()


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


# ── 튜토리얼 안내 ────────────────────────────────────────────
func _start_tutorial() -> void:
	_overlay = TutorialOverlay.new()
	_overlay.name = "Tutorial"
	_ui.add_child(_overlay)
	_overlay.finished.connect(_on_tutorial_finished)
	_overlay.skipped.connect(_exit_to_menu)
	_overlay.start(_steps())


func _steps() -> Array:
	return [
		{
			"text": "You've jumped into the board! In DEEP PARTY, your pawn walks around inside the board world.",
			"target": func() -> Control: return _start_marker,
		},
		{
			"text": "Paths split off at the arrow spaces and loop back around, so there's no finish line. Take any road you like!",
			"enter": func() -> void: _move_camera(Vector3(0, 0, 0), 3.2, 1.8),
			"dim": false,
		},
		{
			"text": "Climb the stairs up the coral hill, cross the bridge, hop across the stone pillars and go through the rock tunnel!",
			"enter": func() -> void: _move_camera(Vector3(-13, 3.5, -11), 1.7, 1.6),
			"dim": false,
		},
		{
			"text": "There are five kinds of spaces! Plain spaces: nothing happens here. Take a breather.",
			"enter": func() -> void: _show_tile(world.nearest_of_kind("plain", _my_spot())),
			"target": func() -> Control: return _tile_marker,
			"pad": 14.0,
		},
		{
			"text": "Chance spaces: draw a random Chance Card!",
			"enter": func() -> void: _show_tile(world.nearest_of_kind("chance", _my_spot()), 1.7),
			"target": func() -> Control: return _tile_marker,
			"pad": 14.0,
		},
		{
			"text": "Minigame spaces: stop here and a minigame begins! You'll find lots of them all over the board.",
			"enter": func() -> void: _show_tile(world.nearest_of_kind("minigame", _my_spot())),
			"target": func() -> Control: return _tile_marker,
			"pad": 14.0,
		},
		{
			"text": "Portal spaces: whoosh! You warp to the portal on the other side of the board.",
			"enter": func() -> void: _portal_demo(),
			"target": func() -> Control: return _tile_marker,
			"pad": 14.0,
		},
		{
			"text": "Shop spaces: drop by the stall to buy items.",
			"enter": func() -> void: _show_tile(world.nearest_of_kind("shop", _my_spot()), 2.1),
			"target": func() -> Control: return _tile_marker,
			"pad": 14.0,
		},
		{
			"text": "Forgot what a space does? Check the guide in the bottom left.",
			"enter": func() -> void: _back_to_my_pawn(),
			"target": func() -> Control: return _legend,
		},
		{
			"text": "Drag with the mouse to look around, and roll the mouse wheel to zoom in and out.",
			"target": func() -> Control: return _screen_marker,
			"pad": 0.0,
		},
		{
			"text": "Lost? Press MY PAWN to jump back to your pawn.",
			"enter": func() -> void: _focused = false,
			"target": func() -> Control: return _my_pawn_btn,
			"until": func() -> bool: return _focused,
			"auto": func() -> void: _focus_my_pawn(),
		},
		{
			"text": "How to play in this world will be explained here soon. Stay tuned!",
		},
	]


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
