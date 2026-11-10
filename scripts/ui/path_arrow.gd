extends Button
## 갈림길에서 고르는 화살표 버튼 (동그라미 + 화살표). angle 방향을 가리켜요.
## 화면 위치는 보드 스크립트가 매 프레임 3D 칸 위치에 맞춰 옮겨 줘요.

const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const R := 34.0

var angle := 0.0
var tile := -1
var locked := false
var _t := 0.0
var _hover := false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(R * 2.4, R * 2.4)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _hover = true)
	mouse_exited.connect(func() -> void: _hover = false)
	set_meta("sfx", "tick")


func _process(delta: float) -> void:
	_t += delta
	disabled = locked
	mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	var s := 1.0 + (0.12 if _hover and not locked else 0.0) + (0.0 if locked else 0.06 * sin(_t * 5.0))
	scale = Vector2.ONE * s
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var a := 0.35 if locked else 1.0
	draw_circle(c + Vector2(0, 4), R, Color(0, 0, 0, 0.3 * a))
	draw_circle(c, R, Color(DEEP, 0.85 * a))
	draw_arc(c, R - 2, 0, TAU, 48, Color(AQUA, (0.9 if _hover else 0.7) * a), 3.0, true)
	var d := Vector2.from_angle(angle)
	var n := d.orthogonal()
	var tip := c + d * R * 0.62
	var back := c - d * R * 0.45
	var pts := PackedVector2Array([
		tip,
		c + d * R * 0.02 + n * R * 0.5,
		c + d * R * 0.02 + n * R * 0.2,
		back + n * R * 0.2,
		back - n * R * 0.2,
		c + d * R * 0.02 - n * R * 0.2,
		c + d * R * 0.02 - n * R * 0.5,
	])
	if not Geometry2D.triangulate_polygon(pts).is_empty():
		draw_colored_polygon(pts, Color(AQUA if not locked else Color(0.6, 0.7, 0.7), a))


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= R + 6.0
