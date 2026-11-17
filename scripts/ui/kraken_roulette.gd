extends Control
## 크라켄의 보물상자 룰렛: 보물상자(금) · 크라켄(초록) 칸이 번갈아 있는 원판 (shaders/roulette_wheel.gdshader).
##   테두리 전구가 돌 때는 줄지어 달리고, 멈추면 결과 색으로 깜빡임. 위쪽 붉은 보석 바늘이 가리키는 칸이 결과.
##   spin(win) 을 await 하면 여러 바퀴 돌다가 천천히 멈춤

const SEGS := 10
const R := 260.0
const BULBS := 30
const WheelShader := preload("res://shaders/roulette_wheel.gdshader")
const CHEST_TEX := preload("res://textures/tiles/icon_treasure.png")
const KRAKEN_TEX := preload("res://textures/tiles/icon_boss.png")
const GOLD := Color(0.97, 0.74, 0.24)

var angle := 0.0                 ## 원판 회전 (시계 방향 +)
var _wheel: ColorRect
var _mat: ShaderMaterial
var _icons: Control
var _hl := -1
var _t := 0.0
var _speed := 0.0
var _done := false
var _win := false
var _last_seg := -1
var _prev_angle := 0.0
var _needle_kick := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(R * 2.0 + 80.0, R * 2.0 + 100.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := _center()
	_wheel = ColorRect.new()
	_wheel.size = Vector2(R, R) * 2.0
	_wheel.position = c - Vector2(R, R)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = WheelShader
	_mat.set_shader_parameter("segs", float(SEGS))
	_wheel.material = _mat
	add_child(_wheel)
	_icons = Control.new()
	_icons.size = custom_minimum_size
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.draw.connect(_draw_top)
	add_child(_icons)


func _center() -> Vector2:
	return Vector2(R + 40.0, R + 66.0)


func _seg_angle(k: int) -> float:
	return TAU * (k + 0.5) / SEGS


## 원판 뒤 그림자 · 은은한 빛
func _draw() -> void:
	var c := _center()
	for k in 6:
		draw_circle(c + Vector2(0, 14), R + 30.0 - k * 4.0, Color(0, 0, 0, 0.07))
	var glow := Color(0.55, 1.0, 0.45, 0.0) if not _done else (Color(1.0, 0.8, 0.3) if _win else Color(0.45, 1.0, 0.4))
	if _done:
		for k in 8:
			draw_circle(c, R + 24.0 + k * 7.0, Color(glow, 0.05 * (0.6 + 0.4 * sin(_t * 10.0))))


## 그림 · 전구 · 바늘 (원판 위)
func _draw_top() -> void:
	var c := _center()
	var ci := _icons
	# 칸 그림 (돋을새김: 그림자 + 본색 + 윗면 빛)
	for k in SEGS:
		var am := _seg_angle(k) + angle - PI * 0.5
		var ip := c + Vector2(cos(am), sin(am)) * R * 0.6
		var chest := k % 2 == 0
		var sz := 84.0
		var tex := CHEST_TEX if chest else KRAKEN_TEX
		var base := Color(0.36, 0.17, 0.03) if chest else Color(0.58, 1.0, 0.48)
		if k == _hl and _done:
			base = base.lerp(Color(1, 1, 1), 0.35 + 0.35 * sin(_t * 12.0))
		ci.draw_set_transform(ip, am + PI * 0.5, Vector2.ONE)
		ci.draw_texture_rect(tex, Rect2(Vector2(-sz, -sz) * 0.5 + Vector2(2, 4), Vector2(sz, sz)), false, Color(0, 0, 0, 0.45))
		ci.draw_texture_rect(tex, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), false, base)
		ci.draw_texture_rect(tex, Rect2(Vector2(-sz, -sz) * 0.5 + Vector2(-1, -1.5), Vector2(sz, sz)), false, Color(1, 1, 1, 0.18 if chest else 0.12))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 가운데 크라켄 눈 각인
	ci.draw_texture_rect(KRAKEN_TEX, Rect2(c - Vector2(26, 26), Vector2(52, 52)), false, Color(0.3, 0.16, 0.03, 0.85))
	# 테두리 전구 (나무 테 위, 원판과 함께 돎)
	for k in BULBS:
		var a := TAU * k / BULBS + angle - PI * 0.5
		var bp := c + Vector2(cos(a), sin(a)) * R * 0.952
		var on := 0.0
		if _done:
			on = 0.55 + 0.45 * sin(_t * 12.0 + (k % 2) * PI)
		else:
			var chase := fposmod(k - _t * (6.0 + _speed * 3.0), 6.0)
			on = 0.25 + 0.75 * smoothstep(1.6, 0.0, chase)
		var bc := Color(1.0, 0.86, 0.5) if not _done else (Color(1.0, 0.86, 0.45) if _win else Color(0.6, 1.0, 0.5))
		ci.draw_circle(bp, 11.0, Color(0.15, 0.08, 0.03))
		ci.draw_circle(bp, 8.5, bc.darkened(0.6).lerp(bc, on))
		ci.draw_circle(bp, 14.0 + on * 6.0, Color(bc, 0.12 * on))
		ci.draw_circle(bp + Vector2(-2.5, -2.5), 2.6, Color(1, 1, 1, 0.5 * on + 0.15))
	# 바늘: 놋쇠 받침 + 붉은 보석 (칸막이에 걸리면 살짝 튐)
	var top := c + Vector2(0, -R - 6.0)
	var kick := _needle_kick
	var tf := Transform2D(kick * 0.35, top)
	ci.draw_set_transform_matrix(tf)
	var body := PackedVector2Array([Vector2(0, 64), Vector2(-30, -6), Vector2(-20, -30), Vector2(20, -30), Vector2(30, -6)])
	var sh := PackedVector2Array()
	for p in body:
		sh.append(p + Vector2(3, 5))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.4))
	ci.draw_colored_polygon(body, Color(0.55, 0.36, 0.1))
	var inner := PackedVector2Array([Vector2(0, 52), Vector2(-21, -3), Vector2(-14, -22), Vector2(14, -22), Vector2(21, -3)])
	ci.draw_colored_polygon(inner, Color(0.75, 0.06, 0.08))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 52), Vector2(-21, -3), Vector2(-14, -22), Vector2(0, -8)]), Color(0.95, 0.2, 0.18))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-10, -16), Vector2(-4, -19), Vector2(-12, 4)]), Color(1, 1, 1, 0.45))
	ci.draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[0]]), Color(1.0, 0.85, 0.5), 3.0, true)
	ci.draw_circle(Vector2(0, -38), 15.0, Color(0.55, 0.36, 0.1))
	ci.draw_circle(Vector2(0, -38), 11.0, GOLD)
	ci.draw_circle(Vector2(-3, -41), 4.0, Color(1, 1, 1, 0.55))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _process(delta: float) -> void:
	_t += delta
	_speed = absf(angle - _prev_angle) / maxf(delta, 0.0001)
	_prev_angle = angle
	_mat.set_shader_parameter("angle", angle)
	_mat.set_shader_parameter("highlight", _hl if _done else -1)
	_mat.set_shader_parameter("flash", 0.5 + 0.5 * sin(_t * 12.0))
	# 바늘 아래 칸이 바뀔 때마다 딸깍 + 바늘이 튐
	var a := fposmod(-angle, TAU)
	var seg := int(a / (TAU / SEGS)) % SEGS
	if seg != _last_seg:
		_last_seg = seg
		Audio.play("tick", 30)
		_needle_kick = -0.5 if _speed > 0.3 else 0.0
	_needle_kick = lerpf(_needle_kick, 0.0, 1.0 - exp(-delta * 10.0))
	queue_redraw()
	_icons.queue_redraw()


## 돌리기: win 이면 보물상자 칸, 아니면 크라켄 칸에 멈춤 (await)
func spin(win: bool) -> void:
	var picks := []
	for k in SEGS:
		if (k % 2 == 0) == win:
			picks.append(k)
	var k: int = picks[randi() % picks.size()]
	var jitter := randf_range(-0.3, 0.3) * TAU / SEGS
	angle = fposmod(angle, TAU)
	var target := -_seg_angle(k) + jitter - TAU * 7.0
	var t := create_tween()
	t.tween_property(self, "angle", target, 5.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await t.finished
	_hl = k
	_win = win
	_done = true
	await get_tree().create_timer(1.3, false).timeout
