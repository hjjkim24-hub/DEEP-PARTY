extends Button
## 클릭하면 켜지고 꺼지는 스위치 (손잡이가 부드럽게 미끄러져요).

const ON_COLOR := Color("7ff0db")
const OFF_COLOR := Color(1, 1, 1, 0.16)
const KNOB := Color("eafffa")

var _k := 0.0


func _ready() -> void:
	toggle_mode = true
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(84, 44)
	_k = 1.0 if button_pressed else 0.0


func _process(delta: float) -> void:
	var target := 1.0 if button_pressed else 0.0
	if absf(_k - target) > 0.001:
		_k = move_toward(_k, target, delta * 7.0)
		queue_redraw()


func _draw() -> void:
	var w := 80.0
	var h := 40.0
	var rect := Rect2(Vector2(size.x - w, (size.y - h) * 0.5), Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = OFF_COLOR.lerp(ON_COLOR, _k)
	sb.set_corner_radius_all(int(h * 0.5))
	sb.anti_aliasing = true
	if is_hovered():
		sb.border_color = Color(1, 1, 1, 0.5)
		sb.set_border_width_all(2)
	draw_style_box(sb, rect)
	var kx := lerpf(rect.position.x + h * 0.5, rect.end.x - h * 0.5, _k)
	draw_circle(Vector2(kx, rect.get_center().y + 1.5), h * 0.36, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(kx, rect.get_center().y), h * 0.36, KNOB)
