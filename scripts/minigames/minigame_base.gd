extends Control
## 미니게임 공통 틀. 모든 미니게임이 이걸 상속해요.
##   소개 카드(설명·조작법) → READY → 3·2·1·GO → 플레이 → FINISH! → finished(순위) 신호
## 화면은 1920x1080 기준 'arena' 안에 그리고, 창 크기에 맞춰 늘려요.
## 사람은 이 컴퓨터의 플레이어 한 명(마우스/키보드), 나머지는 CPU 가 같이 플레이해요.
##
## 상속해서 채울 것:
##   _setup_game()       화면 만들기          _start_game()      GO! 순간
##   _tick(delta)        매 프레임 (플레이 중)  _is_done() -> bool  끝났는지 (기본: 시간 다 됨)
##   _ranking() -> Array 순위 (기본: 점수 높은 순)
##   _score_text(p)      이름표에 보일 점수 글씨

signal finished(ranking: Array)

const UIFont := preload("res://fonts/Poppins-Bold.ttf")
const BackgroundScene := preload("res://scenes/underwater_background.tscn")
const ARENA := Vector2(1920, 1080)
const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const GOLD := Color("ffcf4a")

var title := "MINIGAME"
var how_to := ""
var controls := "MOUSE"          ## "MOUSE" 또는 "KEYBOARD"
var duration := 20.0
var show_timer := true           ## 시간 제한이 없는 게임은 false
var players: Array = []          ## 보드의 말 정보 (name, color, cpu, slot)
var auto_human := false          ## 자동 점검: 사람도 CPU처럼
var scores := {}                 ## slot → 점수
var time_left := 0.0
var playing := false
var arena: Control
var rng := RandomNumberGenerator.new()

var _hint_cb: Callable
var _hud: HBoxContainer
var _chips := {}                 ## slot → Label
var _timer_label: Label
var _overlay: Control


func setup(p_players: Array, auto: bool, hint: Callable = Callable()) -> void:
	players = p_players
	auto_human = auto
	_hint_cb = hint
	for p in players:
		scores[int(p["slot"])] = 0.0


func is_human(p: Dictionary) -> bool:
	return not bool(p["cpu"]) and not auto_human


func hint(name_: String) -> void:
	if _hint_cb.is_valid():
		_hint_cb.call(name_)


func _ready() -> void:
	rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	th.default_font = UIFont
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	theme = th
	var bg := BackgroundScene.instantiate()
	if "show_seabed" in bg:
		bg.show_seabed = false
	add_child(bg)
	arena = Control.new()
	arena.size = ARENA
	arena.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(arena)
	_fit_arena()
	get_viewport().size_changed.connect(_fit_arena)
	_setup_game()
	_build_hud()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _fit_arena() -> void:
	var v := get_viewport().get_visible_rect().size
	var s := minf(v.x / ARENA.x, v.y / ARENA.y)
	arena.scale = Vector2.ONE * s
	arena.position = (v - ARENA * s) * 0.5


## 처음부터 끝까지 (await 하면 순위가 나옴)
func run() -> Array:
	hint("50_mg_%s_intro" % name.to_snake_case())
	await _intro()
	await _countdown()
	time_left = duration
	playing = true
	_start_game()
	while not _is_done():
		await get_tree().process_frame
	playing = false
	Audio.play("start")
	await _big_text("FINISH!", 1.2)
	var r := _ranking()
	finished.emit(r)
	return r


func _process(delta: float) -> void:
	if playing:
		time_left = maxf(0.0, time_left - delta)
		_tick(delta)
	if _timer_label:
		_timer_label.text = str(ceili(time_left)) if show_timer and (playing or time_left > 0.0) else ""
	for p in players:
		var l: Label = _chips.get(int(p["slot"]))
		if l:
			l.text = _score_text(p)


# ── 상속해서 채울 것 ──────────────────────────────────────────
func _setup_game() -> void:
	pass


func _start_game() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _is_done() -> bool:
	return time_left <= 0.0


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()   # 동점이면 무작위
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(scores[int(a["slot"])]) > float(scores[int(b["slot"])]))
	return order


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))


# ── 화면 공통 ────────────────────────────────────────────────
func _build_hud() -> void:
	_hud = HBoxContainer.new()
	_hud.add_theme_constant_override("separation", 12)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.position.y = 24
	for p in players:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", _glass(Color(0.02, 0.15, 0.14, 0.75), Color(p["color"], 0.8) if is_human(p) else Color(AQUA, 0.2), 2 if is_human(p) else 1, 26))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		chip.add_child(h)
		h.add_child(dot(p["color"], 22))
		var n := Label.new()
		n.text = p["name"]
		n.add_theme_font_size_override("font_size", 19)
		h.add_child(n)
		var s := Label.new()
		s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		s.add_theme_font_size_override("font_size", 22)
		s.add_theme_color_override("font_color", GOLD)
		s.custom_minimum_size = Vector2(44, 0)
		h.add_child(s)
		_chips[int(p["slot"])] = s
		_hud.add_child(chip)
	_timer_label = outlined("", 64)
	_timer_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-150, 14)
	_timer_label.size = Vector2(120, 80)
	add_child(_timer_label)


func _glass(bg: Color, border: Color, bw: int, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(12)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.anti_aliasing = true
	return s


func dot(c: Color, px: int) -> Panel:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(px, px)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(px / 2)
	d.add_theme_stylebox_override("panel", st)
	return d


func outlined(text: String, size_: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", maxi(8, size_ / 4))
	return l


## 화면 가운데 큰 글씨
func _big_text(text: String, hold: float, col: Color = PEARL) -> void:
	var l := outlined(text, 120)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = tr(text)
	l.add_theme_color_override("font_color", col)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(l)
	l.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	l.scale = Vector2.ONE * 0.4
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(hold)
	t.tween_property(l, "modulate:a", 0.0, 0.2)
	await t.finished
	l.queue_free()


## 소개 카드: 제목 · 설명 · 조작법 · READY
func _intro() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0.04, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	var st := _glass(Color(0.03, 0.17, 0.16, 0.96), Color(AQUA, 0.7), 3, 28)
	st.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(760, 0)
	dim.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	var head := Label.new()
	head.text = "MINIGAME!"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", AQUA)
	v.add_child(head)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 56)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	var d := Label.new()
	d.text = how_to
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(680, 0)
	d.add_theme_font_size_override("font_size", 25)
	v.add_child(d)
	var c := Label.new()
	c.text = "Controls: Mouse" if controls == "MOUSE" else "Controls: WASD / Arrow keys"
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_theme_font_size_override("font_size", 20)
	c.add_theme_color_override("font_color", Color(PEARL, 0.7))
	v.add_child(c)
	var ready_btn := Button.new()
	ready_btn.text = "READY!"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.custom_minimum_size = Vector2(240, 66)
	ready_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ready_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ready_btn.add_theme_font_size_override("font_size", 26)
	var n := _glass(Color(AQUA, 0.95), Color(AQUA), 0, 18)
	var hv := _glass(Color("a6f7e8"), Color(AQUA), 0, 18)
	ready_btn.add_theme_stylebox_override("normal", n)
	ready_btn.add_theme_stylebox_override("hover", hv)
	ready_btn.add_theme_stylebox_override("pressed", n)
	ready_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		ready_btn.add_theme_color_override(k, DEEP)
	v.add_child(ready_btn)
	await get_tree().process_frame
	panel.position = (get_viewport().get_visible_rect().size - panel.size) * 0.5
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * 0.6
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var human := false
	for p in players:
		if is_human(p):
			human = true
	if human:
		await ready_btn.pressed
	else:
		await get_tree().create_timer(2.2).timeout
	var out := create_tween()
	out.tween_property(dim, "modulate:a", 0.0, 0.2)
	await out.finished
	dim.queue_free()


func _countdown() -> void:
	for k in ["3", "2", "1"]:
		Audio.play("tick")
		await _big_text(k, 0.45)
	Audio.play("start")
	_big_text("GO!", 0.35, GOLD)
	hint("51_mg_%s_play" % name.to_snake_case())


## 점수 등이 떠오르는 글씨 (arena 좌표)
func float_text(at: Vector2, text: String, col: Color, size_: int = 40) -> void:
	var l := outlined(text, size_)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_color_override("font_color", col)
	l.size = Vector2(240, 60)
	l.position = at - l.size * 0.5
	arena.add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 70.0, 0.7).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.3)
	t.tween_callback(l.queue_free)


func player_by_slot(slot: int) -> Dictionary:
	for p in players:
		if int(p["slot"]) == slot:
			return p
	return {}


## CPU 실력 (0 쉬움 ~ 2 어려움). 자동 점검 중인 사람은 보통
func skill(p: Dictionary) -> float:
	if not bool(p["cpu"]):
		return 1.0
	return float(GameState.players[int(p["slot"])].get("level", 1))
