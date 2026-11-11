extends Control
## 보드 상자 열리는 연출: 덜덜 떨림 → 틈으로 빛이 샘 → 뚜껑이 팍 날아가며 빛기둥 → 빛 속으로 빨려 들어감 → 하얗게
##   var fx := BoxOpenFx.new(); add_child(fx); await fx.play(box_texture, box_rect)
## box_rect = 화면에서 상자 그림이 그려진 자리 (그림 전체 크기)

signal finished

const LightShader := preload("res://shaders/box_light.gdshader")

const IMG := Vector2(963, 665)            ## 상자 그림 크기 (tools/render_boardbox.py)
## 상자 윗면 네 꼭짓점 (그림 좌표): 왼쪽, 뒤, 오른쪽, 앞
const TOP := [Vector2(80, 268), Vector2(398, 6), Vector2(887, 152), Vector2(627, 470)]
const SIDE := 100.0                        ## 옆면 높이 (그림 좌표)
const SHAKE_T := 1.4
const BURST_T := 0.55
const SUCK_T := 1.15

var _box: Texture2D
var _rect: Rect2
var _t := -1.0
var _rng := RandomNumberGenerator.new()
var _sparks: Array = []                    ## [pos, vel, life, size]
var _streaks: Array = []                   ## 빨려 들어가는 빛줄기 [angle, dist, speed, len]
var _glow: Control
var _light: ColorRect
var _lm: ShaderMaterial
var _shake := Vector2.ZERO
var _shake_rot := 0.0
var freeze := false                        ## 스크린샷 찍을 때 잠깐 멈춤
var _soft: GradientTexture2D               ## 부드러운 동그란 빛 (가장자리로 갈수록 투명)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_light = ColorRect.new()
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lm = ShaderMaterial.new()
	_lm.shader = LightShader
	_light.material = _lm
	add_child(_light)
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	_soft = GradientTexture2D.new()
	_soft.gradient = g
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 256
	_soft.height = 256


func play(box: Texture2D, rect: Rect2) -> void:
	_box = box
	_rect = rect
	_t = 0.0
	Audio.play("box_rumble")
	await finished


func _total() -> float:
	return SHAKE_T + BURST_T + SUCK_T + 0.35


func _process(delta: float) -> void:
	if _t < 0.0 or freeze:
		return
	var prev := _t
	_t += delta
	# 소리 맞추기
	if prev < SHAKE_T and _t >= SHAKE_T:
		Audio.play("box_burst")
		_spawn_burst()
	if prev < SHAKE_T + BURST_T * 0.6 and _t >= SHAKE_T + BURST_T * 0.6:
		Audio.play("box_whoosh")
	# 떨림 (점점 세게)
	if _t < SHAKE_T:
		var k := pow(_t / SHAKE_T, 1.6)
		_shake = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (1.5 + 11.0 * k) * (_rect.size.x / 900.0)
		_shake_rot = _rng.randf_range(-1, 1) * 0.012 * k
		# 틈새로 튀는 불티
		if _rng.randf() < 0.25 + k:
			var a: Vector2 = _top(_rng.randi() % 4)
			var b: Vector2 = _top((_rng.randi() % 4 + 1) % 4)
			_sparks.append([a.lerp(b, _rng.randf()), Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-160, -60)), 0.7, _rng.randf_range(2.0, 4.5)])
	else:
		_shake = Vector2.ZERO
		_shake_rot = 0.0
	# 빨려 들어가는 빛줄기
	var s0 := SHAKE_T + BURST_T * 0.5
	if _t > s0 and _t < s0 + SUCK_T:
		for i in 6:
			_streaks.append([_rng.randf() * TAU, maxf(size.x, size.y) * _rng.randf_range(0.55, 0.8), _rng.randf_range(500, 900), _rng.randf_range(40, 140)])
	for sp in _sparks:
		sp[0] += sp[1] * delta
		sp[1] += Vector2(0, 30) * delta
		sp[2] -= delta
	_sparks = _sparks.filter(func(sp: Array) -> bool: return sp[2] > 0.0)
	for st in _streaks:
		st[2] *= 1.0 + delta * 3.0
		st[1] -= st[2] * delta
	_streaks = _streaks.filter(func(st: Array) -> bool: return st[1] > 10.0)
	_update_light()
	queue_redraw()
	_glow.queue_redraw()
	if _t >= _total():
		_t = -1.0
		finished.emit()


func _update_light() -> void:
	var z := _zoom()
	_lm.set_shader_parameter("screen", size)
	_lm.set_shader_parameter("origin", _z(_center()))
	_lm.set_shader_parameter("scale", _rect.size.x * minf(z, 10.0))
	if _t < SHAKE_T:
		var k := pow(_t / SHAKE_T, 1.8)
		_lm.set_shader_parameter("power", 1.0)
		_lm.set_shader_parameter("core", 0.03 + 0.14 * k)
		_lm.set_shader_parameter("rays", 0.0)
		_lm.set_shader_parameter("spread", 0.5)
	else:
		var b := _t - SHAKE_T
		var open_k := clampf(b / 0.25, 0.0, 1.0)
		var flash := clampf(1.0 - b / 0.4, 0.0, 1.0)
		var u := clampf((_t - SHAKE_T - BURST_T * 0.5) / SUCK_T, 0.0, 1.0)
		_lm.set_shader_parameter("power", 1.0 + flash * 1.2 + u * u * 2.5)
		_lm.set_shader_parameter("core", 0.5 + open_k * 0.7)
		_lm.set_shader_parameter("rays", open_k * 1.3)
		_lm.set_shader_parameter("spread", lerpf(0.55, 1.25, open_k) + u * 1.6)


# ── 좌표 ─────────────────────────────────────────────────────
func _center() -> Vector2:
	return (_top(0) + _top(1) + _top(2) + _top(3)) * 0.25


## 빨려 들어갈 때 화면 확대 (상자 입구를 중심으로)
func _zoom() -> float:
	var u := clampf((_t - SHAKE_T - BURST_T * 0.5) / SUCK_T, 0.0, 1.0)
	return 1.0 + pow(u, 2.4) * 16.0


func _img(p: Vector2) -> Vector2:
	var q := _rect.position + p / IMG * _rect.size
	var c := _rect.position + _rect.size * 0.5
	q = c + (q - c).rotated(_shake_rot) + _shake
	return q


func _top(i: int) -> Vector2:
	return _img(TOP[i])


func _z(p: Vector2) -> Vector2:
	var c := _center()
	return c + (p - c) * _zoom()


# ── 그리기 ────────────────────────────────────────────────────
func _draw() -> void:
	if _t < 0.0 or _box == null:
		return
	var vp := Rect2(Vector2.ZERO, size)
	# 뒤 배경은 점점 어둡게
	draw_rect(vp, Color(0.0, 0.03, 0.04, clampf(_t / 0.5, 0.0, 1.0) * 0.72))
	var opened := _t >= SHAKE_T
	var b := _t - SHAKE_T
	if opened:
		# 열린 상자 몸통: 옆면 두 개 + 안쪽 바닥
		var down := Vector2(0, SIDE * _rect.size.y / IMG.y * 0.75)
		var L: Vector2 = _top(0)
		var F: Vector2 = _top(3)
		var R: Vector2 = _top(2)
		var side_c := Color(0.03, 0.2, 0.19)
		draw_colored_polygon(PackedVector2Array([_z(L), _z(F), _z(F + down), _z(L + down)]), side_c)
		draw_colored_polygon(PackedVector2Array([_z(F), _z(R), _z(R + down), _z(F + down)]), side_c.darkened(0.3))
		# 옆면 금테
		draw_polyline(PackedVector2Array([_z(L), _z(F), _z(R)]), Color(0.95, 0.8, 0.4), 3.0 * minf(_zoom(), 3.0), true)
		# 상자 안: 안쪽 벽 (뒤쪽 두 벽이 보임) + 빛이 차오르는 바닥
		var inset := 0.1
		var cc := _center()
		var rimp: Array = []
		var flo: Array = []
		for i in 4:
			var tp: Vector2 = _top(i)
			rimp.append(tp)
			flo.append(tp.lerp(cc, inset) + down * 0.9)
		var wall_c := Color(0.05, 0.28, 0.26)
		# 뒤쪽 벽 (왼쪽-뒤, 뒤-오른쪽)
		draw_colored_polygon(PackedVector2Array([_z(rimp[0]), _z(rimp[1]), _z(flo[1]), _z(flo[0])]), wall_c.lightened(0.15))
		draw_colored_polygon(PackedVector2Array([_z(rimp[1]), _z(rimp[2]), _z(flo[2]), _z(flo[1])]), wall_c)
		# 바닥: 가운데가 하얗게 빛나는 그라데이션
		var core: Vector2 = (flo[0] + flo[1] + flo[2] + flo[3]) * 0.25
		var bright := clampf(b / 0.25, 0.0, 1.0)
		for i in 4:
			var a2: Vector2 = flo[i]
			var b2: Vector2 = flo[(i + 1) % 4]
			draw_polygon(PackedVector2Array([_z(core), _z(a2), _z(b2)]),
				PackedColorArray([Color(0.95, 1.0, 0.96), Color(0.1, 0.5, 0.45).lerp(Color(0.5, 0.95, 0.85), bright * 0.6), Color(0.1, 0.5, 0.45).lerp(Color(0.5, 0.95, 0.85), bright * 0.6)]))
		# 앞쪽 벽 윗단 (두께)
		draw_polyline(PackedVector2Array([_z(rimp[0]), _z(rimp[3]), _z(rimp[2])]), Color(0.08, 0.36, 0.33), 6.0 * minf(_zoom(), 3.0), true)
		# 날아가는 뚜껑 (상자 그림 통째로)
		if b < BURST_T + 0.4:
			var u := clampf(b / (BURST_T + 0.4), 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			var c := _rect.get_center()
			var lid_pos := c + Vector2(_rect.size.x * 0.25 * e, -_rect.size.y * 1.3 * e)
			var sc := 1.0 + 0.25 * e
			draw_set_transform(lid_pos, -0.55 * e, Vector2(sc, sc))
			draw_texture_rect(_box, Rect2(-_rect.size * 0.5, _rect.size), false, Color(1, 1, 1, 1.0 - u * u))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_set_transform(_rect.get_center() + _shake, _shake_rot, Vector2.ONE)
		draw_texture_rect(_box, Rect2(-_rect.size * 0.5, _rect.size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 마지막: 온 화면이 하얗게
	var w0 := SHAKE_T + BURST_T * 0.5 + SUCK_T * 0.72
	if _t > w0:
		var a := clampf((_t - w0) / (_total() - w0 - 0.1), 0.0, 1.0)
		draw_rect(vp, Color(0.9, 1.0, 0.97, a))


func _draw_glow() -> void:
	if _t < 0.0:
		return
	var c := _center()
	var rim := PackedVector2Array([_top(0), _top(1), _top(2), _top(3), _top(0)])
	if _t < SHAKE_T:
		# 뚜껑 틈으로 새는 빛 (가늘고 부드럽게 번짐)
		var k := pow(_t / SHAKE_T, 1.5)
		for i in 6:
			var w := (1.5 + i * i * 2.2) * (0.5 + k)
			_glow.draw_polyline(rim, Color(0.55, 1.0, 0.88, (0.42 - i * 0.065) * k), w, true)
	else:
		# 빨려 들어가는 빛줄기 (꼬리가 흐려지는 가는 선)
		for st in _streaks:
			var dir := Vector2.from_angle(st[0])
			var p0: Vector2 = c + dir * float(st[1])
			var p1: Vector2 = c + dir * (float(st[1]) + float(st[3]))
			_glow.draw_polyline_colors(PackedVector2Array([p0, p1]), PackedColorArray([Color(0.75, 1.0, 0.94, 0.4), Color(0.2, 0.8, 0.7, 0.0)]), 2.0, true)
	for sp in _sparks:
		var a := clampf(float(sp[2]) / 0.7, 0.0, 1.0)
		var sp_p := _z(sp[0])
		_glow_disc(sp_p, float(sp[3]) * 4.0, Color(0.4, 1.0, 0.85, a * 0.5))
		_glow.draw_circle(sp_p, float(sp[3]) * 0.5 * (0.6 + a), Color(1.0, 1.0, 0.95, a))


func _glow_disc(p: Vector2, r: float, col: Color) -> void:
	_glow.draw_texture_rect(_soft, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _spawn_burst() -> void:
	var c := _center()
	for i in 70:
		var a := _rng.randf_range(-PI, 0.0)
		var sp := _rng.randf_range(250, 900)
		_sparks.append([c + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-20, 20)), Vector2.from_angle(a) * sp, _rng.randf_range(0.5, 1.0), _rng.randf_range(2.0, 6.0)])
