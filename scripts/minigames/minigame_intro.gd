extends Control
## 미니게임 소개 화면 (보드와 완전히 다른 화면).
##   큰 제목 · 목표 · 미리보기(CPU들이 실제로 하는 장면이 반복 재생) · 하는 방법 · 조작법
##   아래에 플레이어별 준비 카드 — 사람은 READY 버튼, CPU 는 잠시 뒤 알아서 준비.
##   모두 준비되면 run() 이 끝나요.

const Minigames := preload("res://scripts/minigames/registry.gd")
const BgShader := preload("res://shaders/mg_intro_bg.gdshader")
const PirateFonts := preload("res://scripts/ui/pirate_fonts.gd")
const ARENA := Vector2(1920, 1080)
const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const GOLD := Color("ffcf4a")
const GREEN := Color("7dff9a")
## 보물지도 느낌 재료 (tools/make_map_ui.py)
const T_PARCH := preload("res://textures/ui/map/parchment.png")
const T_CARD := preload("res://textures/ui/map/parchment_card.png")
const T_COMPASS := preload("res://textures/ui/map/compass.png")
const T_SEAL := preload("res://textures/ui/map/wax_seal.png")
const T_STAMP := preload("res://textures/ui/map/stamp.png")
const T_FRAME := preload("res://textures/ui/map/frame.png")
const T_RIBBON := preload("res://textures/ui/map/ribbon.png")
const INK := Color(0.24, 0.13, 0.06)
const INK_RED := Color(0.55, 0.13, 0.08)
const CREAM := Color(0.98, 0.9, 0.7)

var game_id := ""
var players: Array = []
var auto_human := false
var _hint_cb: Callable
var _rng := RandomNumberGenerator.new()
var _arena: Control
var _ready_state := {}       ## slot → bool
var _cards := {}             ## slot → {status: Label, panel}
var _demo_vp: SubViewport
var _demo: Control
var _info: Control           ## 제목 등을 읽으려고 잠깐 만든 미니게임
var _t := 0.0
var _rec_dot: Control


func setup(id: String, p_players: Array, auto: bool, hint: Callable = Callable()) -> void:
	game_id = id
	players = p_players
	auto_human = auto
	_hint_cb = hint


func _is_human(p: Dictionary) -> bool:
	return not bool(p["cpu"]) and not auto_human


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	PirateFonts.style_theme(th)
	th.default_font_size = 26
	th.set_color("font_color", "Label", PEARL)
	theme = th
	var bg := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = BgShader
	bg.material = m
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_arena = Control.new()
	_arena.size = ARENA
	_arena.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_arena)
	_fit()
	get_viewport().size_changed.connect(_fit)
	_info = Minigames.create(game_id, _rng)
	_build()


func _exit_tree() -> void:
	if is_instance_valid(_info):
		_info.free()


func _fit() -> void:
	var v := get_viewport().get_visible_rect().size
	var s := minf(v.x / ARENA.x, v.y / ARENA.y)
	_arena.scale = Vector2.ONE * s
	_arena.position = (v - ARENA * s) * 0.5


func _label(text: String, size_: int, col: Color = PEARL, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", DEEP)
		l.add_theme_constant_override("outline_size", outline)
	return l


func _ink(text: String, size_: int, col: Color = INK, is_title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_)
	return PirateFonts.ink(l, col, is_title)


## 늘려도 가장자리가 그대로인 그림 판 (양피지 · 액자 · 리본)
func _tex_box(tex: Texture2D, margin: Vector4, content: Vector4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = margin.x
	s.texture_margin_top = margin.y
	s.texture_margin_right = margin.z
	s.texture_margin_bottom = margin.w
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	return s


func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _build() -> void:
	# 위: MINIGAME! 리본 + 제목 + 목표
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _tex_box(T_RIBBON, Vector4(60, 20, 60, 20), Vector4(70, 8, 70, 14)))
	var pl := _ink("MINIGAME!", 32, CREAM, true)
	pl.add_theme_color_override("font_shadow_color", Color(0.2, 0.02, 0.0, 0.7))
	pl.add_theme_constant_override("shadow_offset_y", 2)
	pill.add_child(pl)
	_arena.add_child(pill)
	pill.position = Vector2(ARENA.x * 0.5 - 170, 26)
	pill.size = Vector2(340, 0)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label(_info.title, 92, GOLD, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 86)
	title.size = Vector2(ARENA.x, 120)
	_arena.add_child(title)
	var goal := _label(_info.goal, 30, CREAM, 10)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.position = Vector2(0, 204)
	goal.size = Vector2(ARENA.x, 44)
	_arena.add_child(goal)

	# 왼쪽: 미리보기 화면 (실제 게임을 CPU들이 자동으로 하는 장면)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _tex_box(T_FRAME, Vector4(70, 70, 70, 70), Vector4(40, 40, 40, 40)))
	frame.position = Vector2(90, 278)
	frame.size = Vector2(1040, 585)
	frame.custom_minimum_size = frame.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(svc)
	_demo_vp = SubViewport.new()
	_demo_vp.size = Vector2i(1280, 720)
	_demo_vp.handle_input_locally = false
	_demo_vp.gui_disable_input = true
	svc.add_child(_demo_vp)
	var rec := HBoxContainer.new()
	rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec.add_theme_constant_override("separation", 10)
	rec.position = Vector2(150, 330)
	_arena.add_child(rec)
	_rec_dot = Panel.new()
	_rec_dot.custom_minimum_size = Vector2(20, 20)
	_rec_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_dot.add_theme_stylebox_override("panel", _box(Color("ff4d5e"), Color.WHITE, 0, 10))
	rec.add_child(_rec_dot)
	rec.add_child(_label("PREVIEW", 24, PEARL, 8))
	_restart_demo()

	# 오른쪽: 하는 방법 + 조작법
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	side.position = Vector2(1180, 278)
	side.size = Vector2(650, 585)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(side)
	var parch := _tex_box(T_PARCH, Vector4(90, 90, 90, 90), Vector4(52, 44, 52, 40))
	var how := PanelContainer.new()
	how.add_theme_stylebox_override("panel", parch)
	how.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(how)
	var how_in := Control.new()
	how_in.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how.add_child(how_in)
	# 지도 그림: 오른쪽 아래 나침반 + 점선 뱃길 + 붉은 X
	var comp := TextureRect.new()
	comp.texture = T_COMPASS
	comp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comp.modulate = Color(1, 1, 1, 0.55)
	comp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	comp.offset_left = -170
	comp.offset_top = -170
	comp.offset_right = 10
	comp.offset_bottom = 10
	how_in.add_child(comp)
	var path := Control.new()
	path.mouse_filter = Control.MOUSE_FILTER_IGNORE
	path.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	path.draw.connect(func() -> void: _draw_map_path(path))
	path.resized.connect(path.queue_redraw)
	how_in.add_child(path)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 12)
	hv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how_in.add_child(hv)
	hv.add_child(_ink("How to Play", 40, INK_RED, true))
	var desc := _ink(_info.how_to, 28)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(540, 0)
	desc.add_theme_constant_override("line_spacing", 6)
	hv.add_child(desc)
	var ctrl := PanelContainer.new()
	ctrl.add_theme_stylebox_override("panel", _tex_box(T_PARCH, Vector4(90, 90, 90, 90), Vector4(52, 34, 52, 34)))
	side.add_child(ctrl)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	ctrl.add_child(cv)
	cv.add_child(_ink("Controls", 36, INK_RED, true))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 22)
	cv.add_child(ch)
	if _info.controls == "MOUSE":
		ch.add_child(_mouse_icon())
		var t := _ink("Click with the left mouse button", 26)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(400, 0)
		ch.add_child(t)
	else:
		ch.add_child(_keys_icon(["W", "A", "S", "D"]))
		var or_l := _ink("or", 24, Color(INK, 0.7))
		or_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(or_l)
		ch.add_child(_keys_icon(["↑", "←", "↓", "→"]))
		var t2 := _ink("Swim", 26)
		t2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(t2)

	# 아래: 플레이어 준비 카드
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.position = Vector2(0, 892)
	row.size = Vector2(ARENA.x, 150)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(row)
	for p in players:
		row.add_child(_player_card(p))


func _player_card(p: Dictionary) -> Control:
	var slot := int(p["slot"])
	_ready_state[slot] = false
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(420, 150)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", _tex_box(T_CARD, Vector4(60, 50, 60, 50), Vector4(30, 18, 40, 18)))
	wrap.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	card.add_child(h)
	# 플레이어 색 밀랍 봉인
	var seal := TextureRect.new()
	seal.texture = T_SEAL
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.custom_minimum_size = Vector2(86, 86)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.modulate = (p["color"] as Color).lightened(0.2)
	seal.rotation = randf_range(-0.3, 0.3)
	seal.pivot_offset = Vector2(43, 43)
	h.add_child(seal)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	v.add_child(_ink(p["name"], 34, INK, true))
	var status := _ink("WAITING...", 22, Color(INK, 0.6))
	v.add_child(status)
	# 준비되면 찍히는 붉은 도장
	var stamp := Control.new()
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.size = Vector2(250, 92)
	stamp.position = Vector2(150, 30)
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation = -0.16
	stamp.visible = false
	var st_tex := TextureRect.new()
	st_tex.texture = T_STAMP
	st_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	st_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st_tex.modulate = Color(0.72, 0.1, 0.08, 0.92)
	st_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.add_child(st_tex)
	var st_l := _ink("READY!", 50, Color(0.72, 0.1, 0.08, 0.92), true)
	st_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.add_child(st_l)
	wrap.add_child(stamp)
	_cards[slot] = {"status": status, "panel": wrap, "color": p["color"], "stamp": stamp}
	if _is_human(p):
		var b := Button.new()
		b.text = "READY!"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 70)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_font_override("font", PirateFonts.title())
		var red := Color(0.55, 0.1, 0.07)
		b.add_theme_stylebox_override("normal", _box(red, Color(0.85, 0.65, 0.3), 3, 14))
		b.add_theme_stylebox_override("hover", _box(red.lightened(0.15), Color(1.0, 0.8, 0.4), 3, 14))
		b.add_theme_stylebox_override("pressed", _box(red.darkened(0.2), Color(0.85, 0.65, 0.3), 3, 14))
		b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, CREAM)
		b.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
		b.pressed.connect(func() -> void:
			b.disabled = true
			_set_ready(slot))
		h.add_child(b)
		_cards[slot]["button"] = b
	return wrap


## 양피지 위 점선 뱃길과 보물 X
func _draw_map_path(c: Control) -> void:
	var s := c.size
	if s.x < 50:
		return
	var a := Vector2(s.x * 0.05, s.y * 0.95)
	var ctl := Vector2(s.x * 0.35, s.y * 0.62)
	var b := Vector2(s.x * 0.62, s.y * 0.9)
	var prev := a
	for i in range(1, 41):
		var t := i / 40.0
		var p := a.lerp(ctl, t).lerp(ctl.lerp(b, t), t)
		if i % 2 == 0:
			c.draw_line(prev, p, Color(INK, 0.45), 3.0, true)
		prev = p
	var x := b + Vector2(16, 0)
	var r := 13.0
	c.draw_line(x + Vector2(-r, -r), x + Vector2(r, r), Color(INK_RED, 0.8), 6.0, true)
	c.draw_line(x + Vector2(-r, r), x + Vector2(r, -r), Color(INK_RED, 0.8), 6.0, true)


func _set_ready(slot: int) -> void:
	if _ready_state.get(slot, true):
		return
	_ready_state[slot] = true
	var c: Dictionary = _cards[slot]
	var st: Label = c["status"]
	st.text = "Aye, ready!"
	# 도장 꽝!
	var stamp: Control = c["stamp"]
	stamp.visible = true
	stamp.scale = Vector2.ONE * 2.2
	stamp.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(stamp, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(stamp, "modulate:a", 1.0, 0.1)
	var panel: Control = c["panel"]
	panel.pivot_offset = panel.size * 0.5
	var t2 := create_tween()
	t2.tween_interval(0.15)
	t2.tween_property(panel, "scale", Vector2.ONE * 0.96, 0.05)
	t2.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK)
	Audio.play("toggle_on")


func _all_ready() -> bool:
	for slot in _ready_state:
		if not _ready_state[slot]:
			return false
	return true


## 모두 준비될 때까지 (CPU 는 잠시 뒤 알아서 준비)
func run() -> void:
	await get_tree().create_timer(1.6, false).timeout
	if _hint_cb.is_valid():
		_hint_cb.call("52_mg_%s_intro_screen" % game_id)
	for p in players:
		if not _is_human(p):
			_cpu_ready_later(int(p["slot"]), _rng.randf_range(0.6, 3.2))
	while not _all_ready():
		await get_tree().process_frame
	Audio.play("start")
	var go := _label("LET'S GO!", 120, GOLD, 26)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	go.size = Vector2(ARENA.x, 300)
	go.position = Vector2(0, ARENA.y * 0.5 - 150)
	go.pivot_offset = go.size * 0.5
	go.scale = Vector2.ONE * 0.3
	_arena.add_child(go)
	var t := create_tween()
	t.tween_property(go, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.1, false).timeout


func _cpu_ready_later(slot: int, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	if is_inside_tree():
		_set_ready(slot)


func _process(delta: float) -> void:
	_t += delta
	if _rec_dot:
		_rec_dot.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 5.0))
	# CPU 카드: 준비 전엔 '...' 이 움직임
	for slot in _cards:
		if not _ready_state.get(slot, true):
			var st: Label = _cards[slot]["status"]
			st.text = tr("WAITING") + ".".repeat(1 + int(_t * 3.0) % 3)


## 미리보기: 같은 미니게임을 작은 화면에서 자동으로 계속
func _restart_demo() -> void:
	if is_instance_valid(_demo):
		_demo.queue_free()
	_demo = Minigames.create(game_id, _rng)
	_demo.setup(players, true)
	_demo.demo = true
	_demo_vp.add_child(_demo)
	_demo.demo_done.connect(_restart_demo, CONNECT_ONE_SHOT)
	_demo.run_demo()


# ── 조작법 그림 ──────────────────────────────────────────────
func _mouse_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(90, 120)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var r := Rect2(10, 6, 70, 108)
		var body := StyleBoxFlat.new()
		body.bg_color = Color(0.93, 0.86, 0.7)
		body.border_color = INK
		body.set_border_width_all(3)
		body.set_corner_radius_all(34)
		body.anti_aliasing = true
		c.draw_style_box(body, r)
		var left := StyleBoxFlat.new()
		left.bg_color = INK_RED if int(_t * 2.5) % 2 == 0 else Color(INK_RED, 0.4)
		left.corner_radius_top_left = 34
		left.anti_aliasing = true
		c.draw_style_box(left, Rect2(10, 6, 34, 46))
		c.draw_line(Vector2(45, 6), Vector2(45, 52), INK, 3)
		c.draw_line(Vector2(10, 52), Vector2(80, 52), INK, 3))
	c.set_process(true)
	var tm := Timer.new()
	tm.wait_time = 0.2
	tm.autostart = true
	tm.timeout.connect(c.queue_redraw)
	c.add_child(tm)
	return c


func _keys_icon(keys: Array) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(170, 116)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pos := [Vector2(58, 2), Vector2(2, 60), Vector2(58, 60), Vector2(114, 60)]
	for i in 4:
		var k := PanelContainer.new()
		var st := _box(Color(0.93, 0.86, 0.7), INK, 2, 8)
		st.border_width_bottom = 6
		k.add_theme_stylebox_override("panel", st)
		k.position = pos[i]
		k.size = Vector2(54, 54)
		k.custom_minimum_size = Vector2(54, 54)
		var l := _ink(keys[i], 26, INK)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		k.add_child(l)
		c.add_child(k)
	return c
