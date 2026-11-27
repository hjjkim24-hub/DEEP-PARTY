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
const INK_DARK := Color(0.12, 0.06, 0.02)   ## 설명 본문: 얼룩진 양피지 위에서도 또렷하게
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
	if net != "":
		return int(p["slot"]) == net_me and not auto_human
	return not bool(p["cpu"]) and not auto_human


## 온라인: "" · "host" · "client". 준비 도장은 방장이 모아서 모두에게 알려 줌
var net := ""
var net_me := 0


func net_setup(mode: String, me: int) -> void:
	net = mode
	net_me = me
	if mode != "":
		Net.message.connect(_on_net_msg)


func _on_net_msg(from: int, d: Dictionary) -> void:
	if not is_inside_tree() or String(d.get("k", "")) != "ready":
		return
	if net == "host":
		for p in players:
			if int(GameState.players[int(p["slot"])].get("peer", -999)) == from:
				_set_ready(int(p["slot"]))
	elif net == "client":
		_set_ready(int(d.get("s", -1)))


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


## 한글이 단어 한가운데서 줄바꿈되지 않게 (글자 사이에 줄바꿈 금지 문자)
static func _keep_words(t: String) -> String:
	var out := ""
	for i in t.length():
		out += t[i]
		if i + 1 < t.length() and t[i] != " " and t[i + 1] != " " and t[i] != "\n" and t[i + 1] != "\n":
			out += char(0x2060)
	return out


## 설명이 길어 오른쪽 칸을 넘치면 글씨를 조금씩 줄임 (그래도 24 이하로는 안 줄임)
func _fit_desc(desc: Label, side: Control) -> void:
	for k in 4:
		await get_tree().process_frame
		if not is_instance_valid(desc):
			return
		if side.get_combined_minimum_size().y <= 585.0:
			return
		var fs := desc.get_theme_font_size("font_size")
		if fs <= 24:
			return
		desc.add_theme_font_size_override("font_size", fs - 2)
		desc.add_theme_constant_override("line_spacing", 6)


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
	var goal := _label(_info.goal, 36, CREAM, 12)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.position = Vector2(0, 200)
	goal.size = Vector2(ARENA.x, 52)
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
	rec.position = Vector2(130, 283)   # 액자 위 나무틀에 (미리보기 화면 속 점수판을 가리지 않게)
	_arena.add_child(rec)
	_rec_dot = Panel.new()
	_rec_dot.custom_minimum_size = Vector2(20, 20)
	_rec_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_dot.add_theme_stylebox_override("panel", _box(Color("ff4d5e"), Color.WHITE, 0, 10))
	rec.add_child(_rec_dot)
	rec.add_child(_label("PREVIEW", 24, PEARL, 8))
	# 렉 줄이기: 미리보기 화면은 해상도를 조금 낮추고(액자 안 작은 화면이라 차이 거의 없음) 그림자 줄임,
	# 소개 화면이 먼저 부드럽게 뜬 뒤 몇 프레임 지나서 미리보기 게임을 만듦 (한 프레임에 다 만들면 멈칫)
	_demo_vp.scaling_3d_scale = 0.75
	_demo_vp.msaa_3d = Viewport.MSAA_DISABLED
	_demo_vp.positional_shadow_atlas_size = 1024
	# 미리보기 게임은 화면이 아직 까만 동안(들어오는 순간) 바로 만듦 → 밝아지는 도중에 멈칫하지 않음
	_restart_demo()

	# 오른쪽: 하는 방법 + 조작법
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	side.position = Vector2(1180, 278)
	side.size = Vector2(650, 585)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(side)
	var parch := _tex_box(T_PARCH, Vector4(90, 90, 90, 90), Vector4(60, 44, 66, 40))
	var how := PanelContainer.new()
	how.add_theme_stylebox_override("panel", parch)
	how.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(how)
	var how_in := how   # 나침반 · 글씨 모두 양피지 안쪽에 바로 (글 길이에 맞춰 양피지가 늘어남)
	# 지도 그림: 오른쪽 아래 나침반 + 점선 뱃길 + 붉은 X
	var comp := TextureRect.new()
	comp.texture = T_COMPASS
	comp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comp.modulate = Color(1, 1, 1, 0.14)   # 글씨 뒤에 깔리므로 아주 옅게
	comp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comp.custom_minimum_size = Vector2(150, 150)
	comp.size_flags_horizontal = Control.SIZE_SHRINK_END
	comp.size_flags_vertical = Control.SIZE_SHRINK_END
	how_in.add_child(comp)
	# (점선 뱃길 · X 표시는 설명 글씨와 겹쳐 읽기 어려워서 뺌)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 12)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how_in.add_child(hv)
	hv.add_child(_ink("How to Play", 40, INK_RED, true))
	var desc := _ink(_keep_words(tr(_info.how_to)), 30, INK_DARK)
	desc.auto_translate = false
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(540, 0)
	desc.add_theme_constant_override("line_spacing", 9)
	_fit_desc.call_deferred(desc, side)
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
	if _info.controls == "MOUSE" or _info.controls == "MOUSE_MOVE":
		ch.add_child(_mouse_icon())
		var t := _ink("Click with the left mouse button" if _info.controls == "MOUSE" else "Move the mouse - your pawn walks to it", 28, INK_DARK)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(400, 0)
		ch.add_child(t)
	elif _info.controls == "ALT_KEYS":
		# 번갈아 누르기 (돛대 오르기)
		ch.add_child(_key_row(["A", "D"]))
		var or_a := _ink("or", 26, Color(INK, 0.9))
		or_a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(or_a)
		ch.add_child(_key_row(["←", "→"]))
		ch.add_child(_ink_wrap("Press them one after the other", 28, 230))
	elif _info.controls == "ALT_KEYS_GRIP":
		# 번갈아 누르기 + 스페이스 꾹 (돛대 오르기)
		cv.remove_child(ch)
		ch.queue_free()
		cv.add_theme_constant_override("separation", 6)
		var g1 := HBoxContainer.new()
		g1.add_theme_constant_override("separation", 12)
		cv.add_child(g1)
		g1.add_child(_key_row(["A", "D"]))
		var g_or := _ink("or", 26, Color(INK, 0.9))
		g_or.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g1.add_child(g_or)
		g1.add_child(_key_row(["←", "→"]))
		g1.add_child(_ink_wrap("Press them one after the other", 28, 300))
		var g2 := HBoxContainer.new()
		g2.add_theme_constant_override("separation", 16)
		cv.add_child(g2)
		g2.add_child(_key_row(["SPACE"]))
		g2.add_child(_ink_wrap("Hold to cling on in a gust!", 28, 420))
	elif _info.controls == "SIDE_JUMP":
		# 좌우 이동 + 점프 (동굴 탈출)
		cv.remove_child(ch)
		ch.queue_free()
		cv.add_theme_constant_override("separation", 6)
		var j1 := HBoxContainer.new()
		j1.add_theme_constant_override("separation", 12)
		cv.add_child(j1)
		j1.add_child(_key_row(["A", "D"]))
		var j_or := _ink("or", 26, Color(INK, 0.9))
		j_or.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		j1.add_child(j_or)
		j1.add_child(_key_row(["←", "→"]))
		j1.add_child(_ink_wrap("Move", 28, 120))
		var j2 := HBoxContainer.new()
		j2.add_theme_constant_override("separation", 16)
		cv.add_child(j2)
		j2.add_child(_key_row(["SPACE"]))
		j2.add_child(_ink_wrap("Jump", 28, 200))
	elif _info.controls == "KEYS_DASH" or _info.controls == "KEYS_MOUSE" or _info.controls == "KEYS_ACT" or _info.controls == "KEYS_DIG":
		# 이동 + 스페이스 (+ 마우스): 줄마다 한 가지씩, 작게
		cv.remove_child(ch)
		ch.queue_free()
		cv.add_theme_constant_override("separation", 6)
		var r1 := HBoxContainer.new()
		r1.add_theme_constant_override("separation", 12)
		cv.add_child(r1)
		r1.add_child(_key_row(["W", "A", "S", "D"]))
		var sl := _ink("/", 26, Color(INK, 0.9))
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r1.add_child(sl)
		r1.add_child(_key_row(["↑", "←", "↓", "→"]))
		r1.add_child(_ink_wrap("Move", 28, 90))
		if _info.controls == "KEYS_MOUSE":
			var r2 := HBoxContainer.new()
			r2.add_theme_constant_override("separation", 16)
			cv.add_child(r2)
			var mi := _mouse_icon()
			mi.custom_minimum_size = Vector2(90, 120)
			mi.scale = Vector2(0.62, 0.62)
			var mw := Control.new()
			mw.custom_minimum_size = Vector2(60, 76)
			mw.add_child(mi)
			r2.add_child(mw)
			r2.add_child(_ink_wrap("Aim with the mouse, click to fire a shot", 26, 460))
		var r3 := HBoxContainer.new()
		r3.add_theme_constant_override("separation", 16)
		cv.add_child(r3)
		r3.add_child(_key_row(["SPACE"]))
		var r3_txt := "Dash and bump!" if _info.controls == "KEYS_DASH" else ("Pick up · put down · shove" if _info.controls == "KEYS_ACT" else ("Dig under the detector" if _info.controls == "KEYS_DIG" else "Pump water (every 0.4 s)"))
		r3.add_child(_ink_wrap(r3_txt, 28, 380))
	else:
		ch.add_child(_keys_icon(["W", "A", "S", "D"]))
		var or_l := _ink("or", 26, Color(INK, 0.9))
		or_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(or_l)
		ch.add_child(_keys_icon(["↑", "←", "↓", "→"]))
		var t2 := _ink("Move", 30, INK_DARK)
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
	var status := _ink("WAITING...", 24, Color(INK, 0.85))
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
	if net == "host":
		Net.broadcast({"k": "ready", "s": slot})
	elif net == "client" and slot == net_me:
		Net.to_host({"k": "ready"})
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
		# CPU 는 잠시 뒤 알아서 준비 (온라인 손님 PC 에서는 방장이 알려 줌)
		var auto_me := auto_human and not bool(p["cpu"]) and (net == "" or int(p["slot"]) == net_me)
		if (bool(p["cpu"]) and net != "client") or auto_me:
			_cpu_ready_later(int(p["slot"]), _rng.randf_range(0.6, 3.2))
	while not _all_ready():
		await get_tree().process_frame
	# 모두 준비되면 멘트 없이 바로 게임으로 (3 · 2 · 1 · 게임 시작! 은 게임 화면에서)
	await get_tree().create_timer(0.35, false).timeout


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
func _start_demo_later() -> void:
	for k in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	if is_inside_tree():
		_restart_demo()


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


## 조작 설명 글씨: 한글이 단어 중간에서 안 끊기게, 정해진 너비 안에서 줄바꿈
func _ink_wrap(text: String, size_: int, width: float) -> Label:
	var t := _ink(_keep_words(tr(text)), size_, INK_DARK)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(width, 0)
	return t


## 가로로 늘어선 키 (SPACE 는 넓게)
func _key_row(keys: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for kname in keys:
		var k := PanelContainer.new()
		var st := _box(Color(0.93, 0.86, 0.7), INK, 2, 8)
		st.border_width_bottom = 6
		k.add_theme_stylebox_override("panel", st)
		k.custom_minimum_size = Vector2(150 if String(kname).length() > 2 else 46, 46)
		var l := _ink(String(kname), 20 if String(kname).length() > 2 else 24, INK)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		k.add_child(l)
		h.add_child(k)
	return h


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
