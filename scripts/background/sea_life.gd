extends Node2D
## 바다 생물: 물살에 흔들리는 해초(켈프)와 천천히 헤엄치는 물고기 떼.
## 좌표는 1920x1080 기준이고, 화면 크기가 달라지면 view_scale 로 맞춰요.
## 해초 위치/크기는 KELP 표에서, 물고기 떼는 SCHOOLS 표에서 고치면 돼요.

## [뿌리 x, 뿌리 y, 높이, 줄기 수, 안개(0=가까움 1=멀리)]
const KELP := [
	[20.0, 1110.0, 700.0, 3, 0.0],
	[78.0, 1125.0, 470.0, 2, 0.0],
	[1880.0, 1110.0, 900.0, 3, 0.0],
	[1790.0, 1130.0, 560.0, 2, 0.05],
	[1470.0, 330.0, 300.0, 3, 0.75],
	[1520.0, 340.0, 220.0, 2, 0.75],
	[1715.0, 430.0, 280.0, 3, 0.6],
	[880.0, 380.0, 260.0, 3, 0.8],
]

## [시작 x, 높이 y, 물고기 수, 크기, 속도(px/초), 안개]
const SCHOOLS := [
	[-300.0, 210.0, 16, 13.0, 34.0, 0.7],
	[900.0, 120.0, 9, 9.0, 22.0, 0.85],
	[400.0, 300.0, 6, 18.0, 46.0, 0.55],
]

const NEAR_COLOR := Color(0.02, 0.16, 0.12)
const FAR_COLOR := Color(0.2, 0.55, 0.5)

var view_scale := Vector2.ONE
var _t := 0.0
var _fish: Array[Dictionary] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for si in SCHOOLS.size():
		var s: Array = SCHOOLS[si]
		for i in int(s[2]):
			_fish.append({
				"school": si,
				"off": Vector2(rng.randf_range(-90, 90), rng.randf_range(-35, 35)),
				"ph": rng.randf() * TAU,
				"size": float(s[3]) * rng.randf_range(0.8, 1.15),
			})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, view_scale)
	# 멀리 있는 것부터
	var order := range(KELP.size())
	order.sort_custom(func(a, b): return KELP[a][4] > KELP[b][4])
	for i in order:
		_draw_kelp(KELP[i], i)
	_draw_fish()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _kelp_color(fog: float, light: float, alpha: float) -> Color:
	var c := NEAR_COLOR.lerp(Color(0.12, 0.38, 0.22), light).lerp(FAR_COLOR, fog)
	return Color(c, alpha * (1.0 - fog * 0.45))


func _draw_kelp(k: Array, idx: int) -> void:
	var root := Vector2(k[0], k[1])
	var hgt: float = k[2]
	var count: int = k[3]
	var fog: float = k[4]
	for s in count:
		var seed_f := float(idx * 7 + s * 3)
		var lean := (float(s) - float(count - 1) * 0.5) * 0.12
		var h := hgt * (1.0 - 0.18 * float(s % 2))
		var width := lerpf(16.0, 7.0, fog) * (1.0 + 0.2 * sin(seed_f))
		var segs := 18
		var pts := PackedVector2Array()
		for j in segs + 1:
			var f := float(j) / float(segs)
			var sway := sin(_t * 0.9 + seed_f + f * 2.6) * 38.0 * f * f + sin(_t * 0.43 + seed_f * 1.7) * 22.0 * f
			pts.append(root + Vector2(lean * h * f + sway, -h * f))
		# 줄기 (아래는 굵고 진하게, 위는 얇고 밝게)
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var cols := PackedColorArray()
		for j in pts.size():
			var f := float(j) / float(segs)
			var dir := (pts[mini(j + 1, segs)] - pts[maxi(j - 1, 0)]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var w := width * (1.0 - f * 0.6)
			left.append(pts[j] + nrm * w * 0.5)
			right.append(pts[j] - nrm * w * 0.5)
		var poly := PackedVector2Array()
		poly.append_array(left)
		for j in range(right.size() - 1, -1, -1):
			poly.append(right[j])
		for j in left.size():
			cols.append(_kelp_color(fog, float(j) / float(segs) * 0.6, 0.95))
		for j in range(right.size() - 1, -1, -1):
			cols.append(_kelp_color(fog, float(j) / float(segs) * 0.6, 0.95))
		if not Geometry2D.triangulate_polygon(poly).is_empty():
			draw_polygon(poly, cols)
		else:
			# 많이 휘어서 외곽선이 꼬이면 마디마다 따로 그림
			for j in left.size() - 1:
				var q := PackedVector2Array([left[j], left[j + 1], right[j + 1], right[j]])
				_safe_poly(q, cols[j])
		# 잎
		for j in range(2, segs, 2):
			var f := float(j) / float(segs)
			var dir := (pts[j + 1] - pts[j - 1]).normalized()
			var side := 1.0 if (j / 2) % 2 == 0 else -1.0
			var leaf_dir := (dir.rotated(side * (1.15 - f * 0.4)) + Vector2(sin(_t * 1.3 + seed_f + f * 4.0) * 0.25, 0)).normalized()
			var leaf_len := lerpf(70.0, 40.0, f) * (1.0 - fog * 0.4) * (h / 800.0 + 0.4)
			var leaf_w := leaf_len * 0.22
			var base := pts[j]
			var tip := base + leaf_dir * leaf_len
			var mid := (base + tip) * 0.5
			var nrm := Vector2(-leaf_dir.y, leaf_dir.x)
			var leaf := PackedVector2Array([base, mid + nrm * leaf_w, tip, mid - nrm * leaf_w * 0.6])
			_safe_poly(leaf, _kelp_color(fog, 0.35 + f * 0.4, 0.85))


func _draw_fish() -> void:
	for fd in _fish:
		var s: Array = SCHOOLS[fd["school"]]
		var speed: float = s[4]
		var fog: float = s[5]
		var span := 1920.0 + 600.0
		var cx := fmod(float(s[0]) + _t * speed + 300.0, span) - 300.0
		var cy: float = float(s[1]) + sin(_t * 0.3 + float(fd["school"])) * 30.0
		var ph: float = fd["ph"]
		var off: Vector2 = fd["off"]
		var p := Vector2(cx, cy) + off + Vector2(sin(_t * 0.7 + ph) * 14.0, sin(_t * 1.1 + ph * 1.3) * 8.0)
		var sz: float = fd["size"]
		var tail := sin(_t * 9.0 + ph) * 0.35
		var col := Color(NEAR_COLOR.lerp(FAR_COLOR, fog), 0.75 - fog * 0.3)
		var body := PackedVector2Array()
		for i in 12:
			var a := TAU * float(i) / 12.0
			body.append(p + Vector2(cos(a) * sz, sin(a) * sz * 0.38))
		_safe_poly(body, col)
		var tb := p + Vector2(-sz * 0.85, 0)
		var tail_pts := PackedVector2Array([
			tb, tb + Vector2(-sz * 0.6, -sz * 0.45).rotated(tail), tb + Vector2(-sz * 0.6, sz * 0.45).rotated(tail)])
		_safe_poly(tail_pts, col)
		draw_circle(p + Vector2(sz * 0.2, -sz * 0.12), sz * 0.6, Color(1, 1, 1, 0.06))


## 꼬이거나 납작한 도형은 건너뜀 (삼각분할 오류 방지)
func _safe_poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
		return
	draw_colored_polygon(pts, c)
