extends Control
## 튜토리얼 안내 화면: 화면을 어둡게 하고 설명할 곳만 밝게 뚫어 보여줘요 (스포트라이트).
## 뚫린 곳은 그대로 클릭할 수 있고, 나머지는 클릭이 막혀요.
##
## 단계(step) 하나는 Dictionary:
##   "text":   설명 문장 (영어 키, 번역됨)
##   "target": func() -> Control   밝게 보여줄 곳 (없으면 화면 가운데에 말풍선만)
##   "until":  func() -> bool      이게 true 가 되면 다음 단계로 (플레이어가 직접 눌러야 하는 단계)
##                                 없으면 NEXT 버튼으로 넘어가요
##   "enter":  func()              단계 시작할 때 할 일
##   "auto":   func()              자동 점검용: 플레이어 대신 눌러 줄 동작
##   "pad":    float               뚫는 영역 여유 (기본 12)
##   "dim":    bool                false 면 화면을 어둡게 하지 않음 (전체를 보여줄 때)
##   "quad":   func() -> PackedVector2Array   화면 위 네 점 — 그 모양 그대로 딱 맞게 뚫음 (3D 칸 강조)
##   "interact": bool             "until" 없는 설명 단계에서도 밝힌 곳을 누를 수 있게 (기본: 보기만)
## 다 끝나면 finished, 건너뛰면 skipped 신호.
##
## 두 가지 쓰는 법:
##   start(steps)      단계 목록을 한 번에 (메인 메뉴 튜토리얼)
##   show_step(step)   한 단계씩 (보드 튜토리얼: 사이사이 게임이 진행됨) — 끝나면 step_done,
##                     그동안은 '쉬는 중'(is_idle) 이라 화면을 가리지 않음. 다 끝나면 finish().

signal finished
signal skipped
signal step_done

const QuadShader := preload("res://shaders/spotlight_quad.gdshader")

const UIFont := preload("res://fonts/PirataOne-Regular.ttf")   ## 글씨체는 부모 화면의 테마를 따름
const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const DIM := Color(0.0, 0.05, 0.05, 0.62)
const BUBBLE_W := 560.0

var steps: Array = []
var index := -1
var font_variation: Font

var _hole := Rect2()
var _hole_target := Rect2()
var _has_hole := false
var _t := 0.0
var _bubble: PanelContainer
var _title: Label
var _text: Label
var _next: Button
var _skip: Button
var _count: Label
var _waiting := false
var _enter_delay := 0.0
var dynamic := false
var _idle := false
var _quad_mode := false
var _quad := PackedVector2Array()
var _quad_rect: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_quad_rect = ColorRect.new()
	_quad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var qm := ShaderMaterial.new()
	qm.shader = QuadShader
	qm.set_shader_parameter("dim_color", DIM)
	_quad_rect.material = qm
	_quad_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quad_rect.visible = false
	add_child(_quad_rect)
	_build_bubble()
	# 건너뛰기: 튜토리얼 동안 늘 오른쪽 위 구석에
	_skip = _small_button("SKIP TUTORIAL", false)
	_skip.pressed.connect(_on_skip)
	_skip.set_meta("sfx", "back")
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_skip)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.14, 0.13, 0.94)
	sb.set_corner_radius_all(22)
	sb.border_color = Color(AQUA, 0.7)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.custom_minimum_size = Vector2(BUBBLE_W, 0)
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bubble)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_bubble.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = Label.new()
	_title.text = "GUIDE"
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", AQUA)
	top.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_count = Label.new()
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(PEARL, 0.55))
	top.add_child(_count)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BUBBLE_W - 52, 0)
	_text.add_theme_font_size_override("font_size", 23)
	_text.add_theme_color_override("font_color", PEARL)
	_text.add_theme_constant_override("line_spacing", 5)
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp2)
	_next = _small_button("NEXT", true)
	_next.pressed.connect(next)
	row.add_child(_next)


func _small_button(label: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(130 if primary else 0, 50)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	var n := StyleBoxFlat.new()
	n.set_corner_radius_all(14)
	n.set_content_margin_all(10)
	n.content_margin_left = 18
	n.content_margin_right = 18
	n.anti_aliasing = true
	if primary:
		n.bg_color = Color(AQUA, 0.95)
	else:
		n.bg_color = Color(0.02, 0.2, 0.18, 0.6)
		n.border_color = Color(AQUA, 0.25)
		n.set_border_width_all(1)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color("a6f7e8") if primary else Color(0.06, 0.32, 0.29, 0.7)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := DEEP if primary else Color(PEARL, 0.8)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fc)
	return b


func start(step_list: Array) -> void:
	steps = step_list
	index = -1
	next()


func current() -> Dictionary:
	if _idle:
		return {}
	return steps[index] if index >= 0 and index < steps.size() else {}


## 지금 단계가 플레이어 동작을 기다리는지 (자동 점검용)
func is_waiting_for_action() -> bool:
	return _waiting


## 한 단계 보여주기 (끝날 때까지 기다리려면: await overlay.step_done)
func show_step(st: Dictionary) -> void:
	dynamic = true
	steps.append(st)
	index = steps.size() - 1
	_idle = false
	_bubble.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_count.visible = false
	_begin_step()


func is_idle() -> bool:
	return _idle


func finish() -> void:
	finished.emit()
	queue_free()


func _go_idle() -> void:
	_idle = true
	_waiting = false
	_bubble.visible = false
	_has_hole = false
	_quad_mode = false
	_quad_rect.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func next() -> void:
	if dynamic:
		if _idle:
			return
		_go_idle()
		step_done.emit()
		return
	index += 1
	if index >= steps.size():
		finished.emit()
		queue_free()
		return
	_begin_step()


func _begin_step() -> void:
	var st: Dictionary = steps[index]
	if st.has("enter"):
		(st["enter"] as Callable).call()
	_text.text = st.get("text", "")
	_count.text = "%d / %d" % [index + 1, steps.size()]
	_waiting = st.has("until")
	_next.visible = not _waiting
	_enter_delay = 0.35   # 화면 전환이 끝날 시간을 조금 줌
	_bubble.modulate.a = 0.0
	_update_target(true)


func _on_skip() -> void:
	skipped.emit()
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _idle or index < 0 or index >= steps.size():
		return
	var st: Dictionary = steps[index]
	if _enter_delay > 0.0:
		_enter_delay -= delta
		if _enter_delay <= 0.0:
			_update_target(true)
	else:
		_update_target(false)
		_bubble.modulate.a = minf(1.0, _bubble.modulate.a + delta * 5.0)
	_hole = Rect2(_hole.position.lerp(_hole_target.position, 1.0 - exp(-delta * 12.0)),
		_hole.size.lerp(_hole_target.size, 1.0 - exp(-delta * 12.0)))
	_place_bubble()
	queue_redraw()
	if _waiting and _enter_delay <= 0.0 and (st["until"] as Callable).call():
		_waiting = false
		next()


func _update_target(snap: bool) -> void:
	var st: Dictionary = steps[index]
	_quad_mode = false
	if st.has("quad"):
		var q: PackedVector2Array = (st["quad"] as Callable).call()
		if q.size() == 4:
			var off := get_global_rect().position
			for k in 4:
				q[k] -= off
			_quad = q
			_quad_mode = true
			var r := Rect2(q[0], Vector2.ZERO)
			for k in range(1, 4):
				r = r.expand(q[k])
			_hole_target = r.grow(6.0)
			_hole = _hole_target
			_has_hole = true
			var m := _quad_rect.material as ShaderMaterial
			m.set_shader_parameter("rect_size", size)
			for k in 4:
				m.set_shader_parameter("q%d" % k, q[k])
			m.set_shader_parameter("ring_color", Color(AQUA, 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 4.0))))
			_quad_rect.visible = bool(st.get("dim", true))
			return
	_quad_rect.visible = false
	var target: Control = null
	if st.has("target"):
		var got = (st["target"] as Callable).call()
		if is_instance_valid(got):
			target = got
	if target and target.is_visible_in_tree():
		var pad: float = st.get("pad", 12.0)
		var r := target.get_global_rect().grow(pad)
		r.position -= get_global_rect().position
		_hole_target = r
		if not _has_hole or snap and _hole.size == Vector2.ZERO:
			_hole = r
		_has_hole = true
	else:
		_has_hole = false
		_hole_target = Rect2(size * 0.5, Vector2.ZERO)
		if snap:
			_hole = _hole_target


func _place_bubble() -> void:
	var bs := _bubble.get_combined_minimum_size()
	bs.x = maxf(bs.x, BUBBLE_W)
	_bubble.size = bs
	var pos: Vector2
	var margin := 28.0
	if not _has_hole:
		pos = Vector2((size.x - bs.x) * 0.5, size.y - bs.y - 90.0)
	else:
		var h := _hole_target
		# 오른쪽 → 왼쪽 → 아래 → 위 순서로 자리 찾기
		if h.end.x + margin + bs.x < size.x - 20:
			pos = Vector2(h.end.x + margin, h.get_center().y - bs.y * 0.5)
		elif h.position.x - margin - bs.x > 20:
			pos = Vector2(h.position.x - margin - bs.x, h.get_center().y - bs.y * 0.5)
		elif h.end.y + margin + bs.y < size.y - 20:
			pos = Vector2(h.get_center().x - bs.x * 0.5, h.end.y + margin)
		else:
			pos = Vector2(h.get_center().x - bs.x * 0.5, h.position.y - margin - bs.y)
	pos.x = clampf(pos.x, 20.0, size.x - bs.x - 20.0)
	pos.y = clampf(pos.y, 20.0, size.y - bs.y - 20.0)
	_bubble.position = _bubble.position.lerp(pos, 0.35) if _bubble.modulate.a > 0.05 else pos


## 뚫린 곳에서는 클릭이 아래로 지나가도록
func _has_point(point: Vector2) -> bool:
	if _idle:
		return false
	# 설명만 하는 단계: 밝힌 곳은 보기만 (실수로 눌러서 진행이 막히지 않게)
	var st := current()
	if not st.has("until") and not bool(st.get("interact", false)):
		return true
	if _quad_mode:
		return not Geometry2D.is_point_in_polygon(point, _quad)
	if _has_hole and _hole.has_point(point):
		return false
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()   # 어두운 곳 클릭은 막기


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if _idle or _quad_mode:
		return
	if index >= 0 and index < steps.size() and not bool(steps[index].get("dim", true)):
		return
	if not _has_hole or _hole.size.x < 2.0:
		draw_rect(full, DIM)
		return
	var h := _hole
	# 구멍 둘레 네 조각
	draw_rect(Rect2(0, 0, size.x, h.position.y), DIM)
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), DIM)
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), DIM)
	# 반짝이는 테두리
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_corner_radius_all(18)
	ring.set_border_width_all(3)
	ring.border_color = Color(AQUA, 0.55 + 0.45 * pulse)
	ring.anti_aliasing = true
	draw_style_box(ring, h.grow(2.0 + pulse * 4.0))
