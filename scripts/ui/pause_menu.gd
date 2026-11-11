extends Control
## 게임 중 ESC (또는 왼쪽 위 MENU) → 일시정지 메뉴.
##   RESUME (게임으로 돌아가기) / SETTINGS (볼륨 · 화면 · 언어) / LEAVE GAME (게임 나가기)
## 열려 있는 동안 게임은 멈춰요 (get_tree().paused). 이 메뉴만 계속 움직여요.

signal leave_requested

const PirateFonts := preload("res://scripts/ui/pirate_fonts.gd")
const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")

var leave_text := "LEAVE GAME"
var _main: PanelContainer
var _settings: PanelContainer
var _vol_labels := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	th.default_font = PirateFonts.body()
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	theme = th
	var dim := ColorRect.new()
	dim.color = Color(0, 0.03, 0.04, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_main = _build_main()
	add_child(_main)
	_settings = _build_settings()
	add_child(_settings)
	_settings.visible = false
	visible = false


func open() -> void:
	if visible:
		return
	visible = true
	_main.visible = true
	_settings.visible = false
	get_tree().paused = true
	Audio.play("tab")
	_center(_main)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Audio.play("back")


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_show_main()
		else:
			close()


func _center(p: Control) -> void:
	await get_tree().process_frame
	p.position = (get_viewport().get_visible_rect().size - p.size) * 0.5
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2.ONE * 0.85
	var t := create_tween()
	t.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.17, 0.16, 0.97)
	st.border_color = Color(AQUA, 0.7)
	st.set_border_width_all(3)
	st.set_corner_radius_all(26)
	st.set_content_margin_all(40)
	st.shadow_color = Color(0, 0, 0, 0.4)
	st.shadow_size = 20
	st.anti_aliasing = true
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(520, 0)
	return p


func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(420, 70)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 24)
	var n := StyleBoxFlat.new()
	n.set_corner_radius_all(18)
	n.anti_aliasing = true
	n.bg_color = Color(AQUA, 0.95) if primary else Color(0.02, 0.22, 0.2, 0.75)
	n.border_color = Color(AQUA, 0.35)
	n.set_border_width_all(0 if primary else 2)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color("a6f7e8") if primary else Color(0.07, 0.36, 0.32, 0.85)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := DEEP if primary else PEARL
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fc)
	return b


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 48)
	l.add_theme_color_override("font_color", AQUA)
	return l


func _build_main() -> PanelContainer:
	var p := _panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(_title("PAUSED"))
	var resume := _button("RESUME", true)
	resume.pressed.connect(close)
	v.add_child(resume)
	var settings := _button("SETTINGS")
	settings.pressed.connect(_show_settings)
	v.add_child(settings)
	var leave := _button(leave_text)
	leave.name = "Leave"
	leave.set_meta("sfx", "back")
	leave.pressed.connect(func() -> void:
		get_tree().paused = false
		visible = false
		leave_requested.emit())
	v.add_child(leave)
	return p


func set_leave_text(t: String) -> void:
	leave_text = t
	if _main:
		(_main.find_child("Leave", true, false) as Button).text = t


func _show_settings() -> void:
	_main.visible = false
	_settings.visible = true
	_refresh_settings()
	_center(_settings)


func _show_main() -> void:
	_settings.visible = false
	_main.visible = true
	_center(_main)


func _build_settings() -> PanelContainer:
	var p := _panel()
	p.custom_minimum_size = Vector2(640, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(_title("SETTINGS"))
	for key in ["master", "music", "sfx"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := Label.new()
		l.text = {"master": "MASTER VOLUME", "music": "MUSIC", "sfx": "SOUND EFFECTS"}[key]
		l.custom_minimum_size = Vector2(230, 0)
		l.add_theme_font_size_override("font_size", 20)
		row.add_child(l)
		var s := HSlider.new()
		s.name = "Slider_" + key
		s.min_value = 0
		s.max_value = 100
		s.step = 1
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.custom_minimum_size = Vector2(240, 30)
		s.focus_mode = Control.FOCUS_NONE
		s.value_changed.connect(_on_volume.bind(key))
		row.add_child(s)
		var val := Label.new()
		val.custom_minimum_size = Vector2(70, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		val.add_theme_font_size_override("font_size", 20)
		row.add_child(val)
		_vol_labels[key] = val
		v.add_child(row)
	# 화면 모드
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 10)
	var wl := Label.new()
	wl.text = "WINDOW MODE"
	wl.custom_minimum_size = Vector2(230, 0)
	wl.add_theme_font_size_override("font_size", 20)
	wrow.add_child(wl)
	for i in Settings.WINDOW_MODES.size():
		var b := _small_toggle(Settings.WINDOW_MODES[i])
		b.name = "Win_%d" % i
		b.pressed.connect(func() -> void:
			Settings.window_mode = i
			Settings.apply_video()
			Settings.save_settings()
			_refresh_settings())
		wrow.add_child(b)
	v.add_child(wrow)
	# 언어
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 10)
	var ll := Label.new()
	ll.text = "LANGUAGE"
	ll.custom_minimum_size = Vector2(230, 0)
	ll.add_theme_font_size_override("font_size", 20)
	lrow.add_child(ll)
	for lang in Settings.LANGUAGES:
		var b := _small_toggle(lang[1])
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.name = "Lang_" + String(lang[0])
		var code: String = lang[0]
		b.pressed.connect(func() -> void:
			Settings.language = code
			Settings.apply_language()
			Settings.save_settings()
			_refresh_settings())
		lrow.add_child(b)
	v.add_child(lrow)
	var back := _button("BACK")
	back.set_meta("sfx", "back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_show_main)
	v.add_child(back)
	return p


func _small_toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	b.set_meta("sfx", "tick")
	var n := StyleBoxFlat.new()
	n.set_corner_radius_all(12)
	n.set_content_margin_all(10)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.bg_color = Color(0.02, 0.22, 0.2, 0.7)
	n.border_color = Color(AQUA, 0.25)
	n.set_border_width_all(1)
	var on := n.duplicate() as StyleBoxFlat
	on.bg_color = Color(AQUA, 0.9)
	var hv := n.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.07, 0.36, 0.32, 0.85)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_pressed_color", DEEP)
	b.add_theme_color_override("font_hover_pressed_color", DEEP)
	return b


func _refresh_settings() -> void:
	var vals := {"master": Settings.master_volume, "music": Settings.music_volume, "sfx": Settings.sfx_volume}
	for key in vals:
		var s := _settings.find_child("Slider_" + key, true, false) as HSlider
		s.set_value_no_signal(roundf(float(vals[key]) * 100.0))
		(_vol_labels[key] as Label).text = "%d%%" % int(roundf(float(vals[key]) * 100.0))
	for i in Settings.WINDOW_MODES.size():
		(_settings.find_child("Win_%d" % i, true, false) as Button).set_pressed_no_signal(Settings.window_mode == i)
	for lang in Settings.LANGUAGES:
		(_settings.find_child("Lang_" + String(lang[0]), true, false) as Button).set_pressed_no_signal(Settings.language == lang[0])


func _on_volume(value: float, key: String) -> void:
	match key:
		"master":
			Settings.master_volume = value / 100.0
		"music":
			Settings.music_volume = value / 100.0
		"sfx":
			Settings.sfx_volume = value / 100.0
	Settings.apply_audio()
	Settings.save_settings()
	(_vol_labels[key] as Label).text = "%d%%" % int(value)
