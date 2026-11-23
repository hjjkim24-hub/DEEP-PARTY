extends Control
## 보드게임 상자 그림. 물속에서 살짝 둥실거리고, 마우스를 올리면 조금 떠올라요.
## 그림자는 제자리에 두고 상자만 움직여서 떠 있는 느낌을 줘요.
## box / shadow 그림은 tools/render_boardbox.py 가 같은 크기로 만들어 둔 것.

const SHADOW := preload("res://textures/boards/box_shadow.png")

var box: Texture2D:
	set(v):
		box = v
		_pop = 1.0      # 상자가 바뀌면 톡 튀어나오는 효과
		queue_redraw()
var dim := false          ## 잠긴 상자: 어둡게
var hovered := false      ## 마우스 올림 (작은 상자 고르기 칸에서 씀)
var selected := false     ## 고른 상자 (작은 상자 고르기 칸에서 씀)
var bob_amount := 0.025   ## 둥실거리는 정도 (상자 높이 대비)
var react_to_mouse := true
var backdrop := false     ## 뒤에 은은한 어두운 빛 웅덩이 (뒷배경 보드판과 구분되게)

var _t := 0.0
var _lift := 0.0
var _pop := 0.0


static var _pool: GradientTexture2D
static var _light: GradientTexture2D


static func _radial(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(e: Array) -> float: return e[0]))
	g.colors = PackedColorArray(stops.map(func(e: Array) -> Color: return e[1]))
	var t := GradientTexture2D.new()
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.gradient = g
	return t


static func _pool_tex() -> GradientTexture2D:
	if _pool == null:
		_pool = _radial([[0.0, Color(0.0, 0.05, 0.045, 0.34)], [0.45, Color(0.0, 0.05, 0.045, 0.22)], [0.8, Color(0.0, 0.05, 0.045, 0.07)], [1.0, Color(0.0, 0.05, 0.045, 0.0)]])
	return _pool


static func _light_tex() -> GradientTexture2D:
	if _light == null:
		_light = _radial([[0.0, Color(0.75, 1.0, 0.92, 0.13)], [0.5, Color(0.6, 0.95, 0.85, 0.06)], [1.0, Color(0.6, 0.95, 0.85, 0.0)]])
	return _light


func _ready() -> void:
	_t = randf() * 10.0
	if react_to_mouse:
		mouse_entered.connect(func() -> void: hovered = true)
		mouse_exited.connect(func() -> void: hovered = false)


func _process(delta: float) -> void:
	_t += delta
	_lift = move_toward(_lift, 1.0 if (hovered or selected) else 0.0, delta * 4.0)
	_pop = maxf(0.0, _pop - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if box == null:
		return
	var ts := box.get_size()
	var k := minf(size.x / ts.x, size.y / ts.y)
	var draw_size := ts * k
	var origin := (size - draw_size) * 0.5
	var ease_lift := _lift * _lift * (3.0 - 2.0 * _lift)
	var bob := sin(_t * 1.6) * draw_size.y * bob_amount
	var rise := ease_lift * draw_size.y * 0.04 + bob
	var pop_s := 1.0 + sin(_pop * PI) * 0.05
	var scale_k := (1.0 + ease_lift * 0.03) * pop_s

	if backdrop:
		# 뒤에 깔리는 어스름 + 위에서 내려오는 은은한 빛 웅덩이: 매끈한 그라데이션 한 장씩 (겹친 원 때문에 생기던 계단 무늬 없음)
		var c := origin + draw_size * Vector2(0.5, 0.55)
		var r := maxf(draw_size.x, draw_size.y) * 0.66
		draw_texture_rect(_pool_tex(), Rect2(c - Vector2(r, r * 0.72), Vector2(r * 2.0, r * 1.44)), false, Color(1, 1, 1, 1))
		var lr := r * 0.8
		var flick := 0.9 + 0.1 * sin(_t * 0.9) * sin(_t * 1.7 + 1.0)
		draw_texture_rect(_light_tex(), Rect2(c - Vector2(lr, lr * 0.62) + Vector2(0, -draw_size.y * 0.06), Vector2(lr * 2.0, lr * 1.24)), false, Color(1, 1, 1, flick))

	# 그림자: 상자가 뜰수록 연하고 넓게
	var sh_a := (0.75 if not dim else 0.5) * (1.0 - ease_lift * 0.25 - clampf(rise / draw_size.y, -0.05, 0.1))
	var sh_scale := 1.0 + ease_lift * 0.04
	var sh_size := draw_size * sh_scale
	draw_texture_rect(SHADOW, Rect2(origin + (draw_size - sh_size) * 0.5, sh_size), false, Color(1, 1, 1, sh_a))

	var bs := draw_size * scale_k
	var pos := origin + (draw_size - bs) * 0.5 - Vector2(0, rise)
	var mod := Color(0.55, 0.62, 0.62, 1.0) if dim else Color(1, 1, 1, 1)
	if dim and (hovered or selected):
		mod = Color(0.72, 0.8, 0.8, 1.0)
	draw_texture_rect(box, Rect2(pos, bs), false, mod)
