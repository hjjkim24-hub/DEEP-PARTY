extends Node2D
## 튜토리얼 월드 — 말이 보드게임 속 세상으로 직접 뛰어들어요.
## 1) 처음엔 보드판처럼 멀리서 내려다보다가  2) 카메라가 판 속으로 쑥 들어가고
## 3) 말들이 위에서 START 광장으로 퐁 떨어져요.
## 세상은 넓고, 길이 여러 갈래로 갈라졌다 다시 만나요 (골인 지점 없음).
## 지도·칸 위치는 tools/render_world.py 가 만들어요. 규칙은 나중에 정해지면 _steps() 에 추가.

const BackgroundScene := preload("res://scenes/underwater_background.tscn")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
const PieceDraw := preload("res://scripts/background/piece_draw.gd")
const Bubbles := preload("res://scripts/background/bubbles.gd")
const CausticShader := preload("res://shaders/world_caustics.gdshader")
const UIFont := preload("res://fonts/Poppins-Bold.ttf")
const MAP_TEX := preload("res://textures/worlds/tutorial_map.png")
const WORLD_JSON := "res://textures/worlds/tutorial_world.json"
const MAIN_MENU := "res://scenes/main_menu.tscn"

const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const PAWN_H := 140.0          ## 세상 안에서 말 키 (월드 좌표)
const ZOOM_IN := 1.0
const ZOOM_MAX := 1.4

var world := {}                ## JSON: size, spaces, kelp, vents ...
var map_size := Vector2(4800, 3200)
var _pawns: Array = []         ## {slot, name, color, look, pos, drop}
var _kelp: Array = []

var _camera: Camera2D
var _actors: Node2D
var _vents: Node2D
var _ui: CanvasLayer
var _chips: HBoxContainer
var _my_pawn_btn: Button
var _start_marker: Control
var _screen_marker: Control
var _overlay
var _fade: ColorRect
var _title: Label

var _intro_done := false
var _focused := false          ## MY PAWN 을 눌러 내 말로 돌아왔는지 (튜토리얼 확인용)
var _dragging := false
var _cam_tween: Tween


# ── 말·다시마를 앞뒤 순서대로 그리는 층 ───────────────────────
class Actors extends Node2D:
	var w   # 바깥 스크립트

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var items: Array = []
		for k in w._kelp:
			items.append([float(k[1]), 0, k])
		for p in w._pawns:
			items.append([(p["pos"] as Vector2).y, 1, p])
		items.sort_custom(func(a, b) -> bool: return a[0] < b[0])
		for it in items:
			if it[1] == 0:
				_draw_kelp(it[2], t)
			else:
				_draw_pawn(it[2])

	func _draw_kelp(k: Array, t: float) -> void:
		var base := Vector2(k[0], k[1])
		var hgt: float = k[2]
		var ph: float = k[3]
		var n := 14
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var prev := base
		var spine: Array[Vector2] = []
		for i in n + 1:
			var f := float(i) / n
			var sway := sin(t * 1.1 + ph + f * 2.2) * 34.0 * f * f + sin(t * 2.3 + ph * 2.0) * 6.0 * f
			var p := base + Vector2(sway, -hgt * f)
			spine.append(p)
		for i in spine.size():
			var f := float(i) / n
			var dir := (spine[mini(i + 1, n)] - spine[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var wd := lerpf(9.0, 3.0, f)
			left.append(spine[i] + nrm * wd)
			right.append(spine[i] - nrm * wd)
		right.reverse()
		var poly := left + right
		# 그림자
		PieceDraw.poly(self, PieceDraw.ellipse(base + Vector2(10, 2), 26.0, 8.0, 14), Color(0, 0.1, 0.08, 0.3))
		draw_colored_polygon(poly, Color(0.12, 0.42, 0.24, 0.95))
		# 잎
		for i in range(2, n, 2):
			var p: Vector2 = spine[i]
			var side := 1.0 if i % 4 == 0 else -1.0
			var lf := sin(t * 1.6 + ph + i) * 0.25
			var tip := p + Vector2(side * 38.0, -16.0).rotated(lf * side)
			draw_colored_polygon(PackedVector2Array([p, p + (tip - p) * 0.5 + Vector2(0, -10), tip, p + (tip - p) * 0.5 + Vector2(0, 8)]),
				Color(0.2, 0.55, 0.3, 0.92))

	func _draw_pawn(p: Dictionary) -> void:
		var pos: Vector2 = p["pos"]
		var drop: float = p["drop"]
		if drop > 2000.0:
			return
		# 땅 그림자: 높이 있을수록 작고 연하게
		var k := clampf(1.0 - drop / 900.0, 0.2, 1.0)
		PieceDraw.poly(self, PieceDraw.ellipse(pos + Vector2(8, 4), PAWN_H * 0.3 * k, PAWN_H * 0.1 * k, 24), Color(0, 0.08, 0.07, 0.4 * k))
		PieceDraw.draw_pawn_real(self, pos + Vector2(0, -drop), PAWN_H, p["color"], 1.0, p["look"])


func _ready() -> void:
	_load_world()
	_setup_pawns()
	_build_world()
	_build_ui()
	Audio.play_music()
	_intro()


func _load_world() -> void:
	var f := FileAccess.open(WORLD_JSON, FileAccess.READ)
	world = JSON.parse_string(f.get_as_text())
	map_size = Vector2(world["size"][0], world["size"][1])
	_kelp = world["kelp"]


func _start_pos() -> Vector2:
	var s: Dictionary = world["spaces"][int(world["start"])]
	return Vector2(s["x"], s["y"])


func _setup_pawns() -> void:
	var cpu_no := 0
	for slot in 4:
		var p: Dictionary = GameState.players[slot]
		if p.is_empty():
			continue
		var pname := "You"
		if p.get("kind", "") == "cpu":
			cpu_no += 1
			pname = tr("CPU %d") % cpu_no
		_pawns.append({"slot": slot, "name": pname, "color": GameState.player_color(slot),
			"look": GameState.look(slot), "pos": Vector2.ZERO, "drop": 99999.0})
	if _pawns.is_empty():
		_pawns.append({"slot": 0, "name": "You", "color": GameState.PALETTE[0], "look": {}, "pos": Vector2.ZERO, "drop": 99999.0})
	# START 광장 위에 나란히
	var offs := [Vector2(-58, -22), Vector2(58, -22), Vector2(-58, 40), Vector2(58, 40)]
	if _pawns.size() == 1:
		offs = [Vector2(0, 0)]
	for i in _pawns.size():
		_pawns[i]["pos"] = _start_pos() + offs[i % 4]


func _build_world() -> void:
	# 맨 뒤: 물 (화면에 고정)
	var back := CanvasLayer.new()
	back.layer = -10
	add_child(back)
	var bg = BackgroundScene.instantiate()
	bg.show_seabed = false
	back.add_child(bg)

	var map := Sprite2D.new()
	map.texture = MAP_TEX
	map.centered = false
	var m := ShaderMaterial.new()
	m.shader = CausticShader
	m.set_shader_parameter("map_size", map_size)
	map.material = m
	add_child(map)

	_vents = Bubbles.new()
	_vents.ambient_rate = 0.0
	_vents.snow_count = 0
	_vents.area_size = map_size
	var vents: Array[Vector2] = []
	for v in world["vents"]:
		vents.append(Vector2(v[0], v[1]))
	_vents.vents = vents
	_vents.vent_rate = 3.0
	add_child(_vents)

	_actors = Actors.new()
	_actors.w = self
	add_child(_actors)

	# 떠다니는 알갱이·물방울 (세상 전체)
	var snow := Bubbles.new()
	snow.area_size = map_size
	snow.ambient_rate = 14.0
	snow.snow_count = 260
	add_child(snow)

	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()


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

	# 위: 참가자
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
	_my_pawn_btn.pressed.connect(_focus_my_pawn)
	root.add_child(_my_pawn_btn)
	_my_pawn_btn.custom_minimum_size = Vector2(180, 60)
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


# ── 카메라 ───────────────────────────────────────────────────
func _view_size() -> Vector2:
	return get_viewport_rect().size


func _fit_zoom() -> float:
	var v := _view_size()
	return minf(v.x / map_size.x, v.y / map_size.y) * 0.92


func _clamp_camera() -> void:
	var view := _view_size() / _camera.zoom
	var pos := _camera.position
	for axis in 2:
		var half := view[axis] * 0.5
		var lo := half - 60.0
		var hi := map_size[axis] - half + 60.0
		pos[axis] = map_size[axis] * 0.5 if lo > hi else clampf(pos[axis], lo, hi)
	_camera.position = pos


func _move_camera(target: Vector2, zoom: float, time: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_camera, "position", target, time)
	_cam_tween.tween_property(_camera, "zoom", Vector2.ONE * zoom, time)


func _focus_my_pawn() -> void:
	for p in _pawns:
		if int(p["slot"]) == 0:
			_move_camera(p["pos"] + Vector2(0, -PAWN_H * 0.4), ZOOM_IN, 0.8)
			break
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
			var before := get_global_mouse_position()
			var z := _camera.zoom.x * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			_camera.zoom = Vector2.ONE * clampf(z, _fit_zoom(), ZOOM_MAX)
			_camera.position += before - get_global_mouse_position()
			_clamp_camera()
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		if _cam_tween:
			_cam_tween.kill()
		_camera.position -= mm.relative / _camera.zoom
		_clamp_camera()


func _process(_delta: float) -> void:
	# 튜토리얼이 가리킬 수 있게 START 광장의 화면 위치를 따라감
	var xf := get_viewport().get_canvas_transform()
	var r := Rect2(_start_pos() - Vector2(260, 230), Vector2(520, 360))
	var a := xf * r.position
	var b := xf * r.end
	_start_marker.position = a
	_start_marker.size = b - a
	var v := _view_size()
	_screen_marker.position = Vector2(60, 110)
	_screen_marker.size = v - Vector2(120, 220)


# ── 들어가기 연출 ────────────────────────────────────────────
func _intro() -> void:
	_camera.position = map_size * 0.5
	_camera.zoom = Vector2.ONE * _fit_zoom()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.6)
	t.parallel().tween_property(_title, "modulate:a", 1.0, 0.6)
	await get_tree().create_timer(1.6).timeout
	# 판 속으로 쑥
	Audio.play("bubbles")
	var tt := create_tween()
	tt.tween_property(_title, "modulate:a", 0.0, 0.4)
	_move_camera(_start_pos() + Vector2(0, -PAWN_H * 0.4), ZOOM_IN, 2.4)
	await _cam_tween.finished
	# 말들이 퐁퐁 떨어짐
	for i in _pawns.size():
		_drop_pawn(i)
		await get_tree().create_timer(0.28).timeout
	await get_tree().create_timer(1.0).timeout
	_intro_done = true
	_my_pawn_btn.visible = true
	_start_tutorial()


func _drop_pawn(i: int) -> void:
	var p: Dictionary = _pawns[i]
	p["drop"] = 900.0
	var t := create_tween()
	t.tween_method(func(v: float) -> void: p["drop"] = v, 900.0, 0.0, 0.75).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.42).timeout
	Audio.play("add")
	_vents.burst(p["pos"], 12)


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
			"text": "This world is big. Paths split off in many directions and loop back around, so there's no finish line.",
			"enter": func() -> void: _move_camera(map_size * 0.5, _fit_zoom() * 1.05, 1.6),
			"dim": false,
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
	if _fade.color.a > 0.5 and _fade.visible and not _intro_done:
		return
	GameState.tutorial_active = false
	_fade.get_parent().move_child(_fade, -1)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.4)
	await t.finished
	get_tree().change_scene_to_file(MAIN_MENU)
