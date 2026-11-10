extends Node3D
## 3D 말. 메뉴의 실사풍 말(tools/render_pawn.py)과 같은 옆모양을 돌려 깎아 만들고,
## 꾸미기 아이템 12가지를 간단한 3D 모양으로 얹어요. 키는 1 (부모에서 scale 로 키움).
##   var p := Pawn3D.new(); p.color = ...; p.look = {"hat": "crown"}; add_child(p)

const PawnShader := preload("res://shaders/pawn3d.gdshader")
const StripeShader := preload("res://shaders/stripes3d.gdshader")

## 옆모양 (반지름, 높이) — render_pawn.py 의 PROFILE 과 같음
const PROFILE_BASE := [
	Vector2(0.0, 0.0), Vector2(0.300, 0.0), Vector2(0.312, 0.012), Vector2(0.315, 0.045), Vector2(0.305, 0.070),
	Vector2(0.275, 0.088), Vector2(0.245, 0.098), Vector2(0.215, 0.118), Vector2(0.190, 0.150), Vector2(0.165, 0.205),
	Vector2(0.143, 0.275), Vector2(0.126, 0.355), Vector2(0.114, 0.440), Vector2(0.106, 0.515), Vector2(0.104, 0.560),
	Vector2(0.150, 0.575), Vector2(0.178, 0.592), Vector2(0.182, 0.608), Vector2(0.170, 0.624), Vector2(0.118, 0.640),
	Vector2(0.096, 0.655),
]
const HEAD_C := Vector3(0, 0.792, 0)
const HEAD_R := 0.152
const SEGMENTS := 48

var color := Color("ff7a6b")
var look: Dictionary = {}
var _body: MeshInstance3D

static var _profile_cache: PackedVector2Array


func _ready() -> void:
	_build()


static func profile() -> PackedVector2Array:
	if _profile_cache.size() > 0:
		return _profile_cache
	var pts: Array[Vector2] = []
	for p in PROFILE_BASE:
		pts.append(p)
	for k in range(1, 26):
		var a := -1.15 + (PI / 2.0 + 1.15) * float(k) / 25.0
		pts.append(Vector2(0.152 * cos(a), 0.792 + 0.152 * sin(a)))
	pts.append(Vector2(0.0, 0.944))
	# 부드럽게 (Catmull-Rom)
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		var p0: Vector2 = pts[maxi(i - 1, 1)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		for s in 6:
			var t := float(s) / 6.0
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	_profile_cache = out
	return out


## 그 높이에서 몸 반지름
static func body_radius(y: float) -> float:
	var pr := profile()
	var best := 0.0
	for i in pr.size() - 1:
		var a := pr[i]
		var b := pr[i + 1]
		if (a.y - y) * (b.y - y) <= 0.0 and a.y != b.y:
			var t := (y - a.y) / (b.y - a.y)
			best = maxf(best, lerpf(a.x, b.x, t))
	return best


## 옆모양을 돌려 깎은 메쉬 (from_angle~to_angle 만 만들 수도 있음: 망토 등)
static func lathe(pr: PackedVector2Array, segs: int, from_a: float = 0.0, to_a: float = TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pr.size()
	var norms: Array[Vector2] = []
	for i in n:
		var a := pr[maxi(i - 1, 0)]
		var b := pr[mini(i + 1, n - 1)]
		var tng := (b - a).normalized()
		norms.append(Vector2(tng.y, -tng.x))
	for s in segs:
		var a0 := lerpf(from_a, to_a, float(s) / segs)
		var a1 := lerpf(from_a, to_a, float(s + 1) / segs)
		for i in n - 1:
			var quad := [[i, a0], [i + 1, a0], [i + 1, a1], [i, a1]]
			var vs: Array[Vector3] = []
			var ns: Array[Vector3] = []
			for q in quad:
				var p: Vector2 = pr[q[0]]
				var nn: Vector2 = norms[q[0]]
				var ang: float = q[1]
				vs.append(Vector3(sin(ang) * p.x, p.y, cos(ang) * p.x))
				ns.append(Vector3(sin(ang) * nn.x, nn.y, cos(ang) * nn.x).normalized())
			for idx in [0, 1, 2, 0, 2, 3]:   # Godot 앞면 = 시계 방향
				st.set_normal(ns[idx])
				st.add_vertex(vs[idx])
	return st.commit()


func _mat(c: Color, rough: float = 0.4, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _stripe_mat(a: Color, b: Color, count: float, mode: int, rough: float = 0.45) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = StripeShader
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("count", count)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("roughness_v", rough)
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _cyl(top: float, bottom: float, h: float, segs: int = 32) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _torus(ring_r: float, tube_r: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ring_r - tube_r
	t.outer_radius = ring_r + tube_r
	t.rings = 32
	t.ring_segments = 12
	return t


func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


static func pattern_color(tint: Color) -> Color:
	var lum := tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114
	return tint.darkened(0.45) if lum > 0.62 else Color(0.97, 0.94, 0.88)


func _build() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = lathe(profile(), SEGMENTS)
	var m := ShaderMaterial.new()
	m.shader = PawnShader
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("pattern_color", pattern_color(color))
	var pat: String = look.get("pattern", "")
	m.set_shader_parameter("pattern", 1 if pat == "stripes" else (2 if pat == "diamond" else 0))
	_body.material_override = m
	add_child(_body)
	match look.get("hat", ""):
		"party_hat": _party_hat()
		"top_hat": _top_hat()
		"crown": _crown()
		"beanie": _beanie()
	match look.get("accessory", ""):
		"scarf": _scarf()
		"sunglasses": _sunglasses()
		"pearl_necklace": _pearls()
	match look.get("outfit", ""):
		"red_cape": _cape()
		"swim_ring": _swim_ring()
		"coat": _coat()


# ── 모자 ─────────────────────────────────────────────────────
func _party_hat() -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, 0.905, 0.0)
	root.rotation = Vector3(-0.08, 0, 0.16)
	add_child(root)
	var cone := _cyl(0.0, 0.135, 0.34)
	_add_to(root, cone, _stripe_mat(Color(0.96, 0.36, 0.42), Color(1.0, 0.93, 0.62), 10.0, 0, 0.5), Vector3(0, 0.17, 0))
	# 아래 주름 테두리 + 꼭대기 방울 (보송보송)
	for k in 14:
		var a := TAU * k / 14.0
		_add_to(root, _sphere(0.026), _mat(Color(0.45, 0.88, 0.80), 0.9), Vector3(sin(a) * 0.132, 0.012, cos(a) * 0.132))
	for k in 6:
		var a := TAU * k / 6.0
		_add_to(root, _sphere(0.03), _mat(Color(1.0, 0.86, 0.35), 0.95), Vector3(sin(a) * 0.022, 0.355 + (k % 2) * 0.012, cos(a) * 0.022))
	_add_to(root, _sphere(0.032), _mat(Color(1.0, 0.86, 0.35), 0.95), Vector3(0, 0.372, 0))


func _top_hat() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, 0.912, 0)
	root.rotation = Vector3(0, 0, -0.08)
	add_child(root)
	var black := _mat(Color(0.06, 0.06, 0.075), 0.3)
	var silk := _mat(Color(0.09, 0.09, 0.11), 0.18, 0.15)
	_add_to(root, _cyl(0.215, 0.215, 0.014), black, Vector3(0, 0, 0))
	_add_to(root, _torus(0.208, 0.016), black, Vector3(0, 0.012, 0))       # 살짝 말린 챙
	_add_to(root, _cyl(0.132, 0.122, 0.26), silk, Vector3(0, 0.137, 0))
	_add_to(root, _cyl(0.126, 0.126, 0.05), _mat(Color(0.78, 0.16, 0.22), 0.45), Vector3(0, 0.035, 0))
	_add_to(root, _box(0.05, 0.05, 0.02), _mat(Color(1.0, 0.8, 0.35), 0.25, 0.9), Vector3(0, 0.035, 0.128))   # 버클
	_add_to(root, _torus(0.128, 0.008), silk, Vector3(0, 0.268, 0))


func _crown() -> void:
	var y := 0.9
	var gold := _mat(Color(1.0, 0.76, 0.28), 0.22, 0.95)
	var ring := _cyl(0.15, 0.142, 0.1)
	ring.cap_top = false
	ring.cap_bottom = false
	var rm := gold.duplicate() as StandardMaterial3D
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(ring, rm, Vector3(0, y + 0.05, 0))
	_add(_torus(0.146, 0.017), gold, Vector3(0, y + 0.004, 0))
	_add(_torus(0.152, 0.012), gold, Vector3(0, y + 0.1, 0))
	var velvet := SphereMesh.new()
	velvet.radius = 0.135
	velvet.height = 0.17
	velvet.is_hemisphere = true
	_add(velvet, _mat(Color(0.62, 0.08, 0.16), 0.9), Vector3(0, y + 0.06, 0))
	for k in 5:
		var a := k * TAU / 5.0
		var p := Vector3(sin(a) * 0.148, y + 0.15, cos(a) * 0.148)
		_add(_cyl(0.0, 0.04, 0.1, 12), gold, p)
		_add(_sphere(0.021), _mat(Color(0.98, 0.96, 0.92), 0.12, 0.1), p + Vector3(0, 0.058, 0))
		var gem := _mat(Color(0.9, 0.1, 0.2) if k % 2 == 0 else Color(0.15, 0.4, 0.95), 0.08, 0.3)
		gem.emission_enabled = true
		gem.emission = gem.albedo_color
		gem.emission_energy_multiplier = 0.35
		_add(_sphere(0.022), gem, Vector3(sin(a + PI / 5) * 0.155, y + 0.05, cos(a + PI / 5) * 0.155))
	_add(_sphere(0.026), gold, Vector3(0, y + 0.2, 0))


func _beanie() -> void:
	var r := HEAD_R + 0.022
	var cap := SphereMesh.new()
	cap.radius = r
	cap.height = r * 2.0
	cap.is_hemisphere = true
	cap.radial_segments = 32
	cap.rings = 12
	var knit := _stripe_mat(Color(0.95, 0.55, 0.22), Color(0.86, 0.46, 0.16), 40.0, 1, 0.95)
	var mi := _add(cap, knit, HEAD_C + Vector3(0, 0.0, 0))
	mi.scale = Vector3(1.0, 1.12, 1.0)
	# 두툼한 접힌 단 (골지)
	var cuff := _cyl(r + 0.012, r + 0.016, 0.07, 32)
	_add(cuff, _stripe_mat(Color(0.86, 0.44, 0.15), Color(0.76, 0.38, 0.12), 48.0, 1, 0.95), HEAD_C + Vector3(0, 0.03, 0))
	# 보송보송 방울
	var white := _mat(Color(0.98, 0.95, 0.9), 1.0)
	var top := HEAD_C + Vector3(0, r * 1.12 + 0.03, 0)
	_add(_sphere(0.05), white, top)
	for k in 8:
		var a := TAU * k / 8.0
		_add(_sphere(0.03), white, top + Vector3(sin(a) * 0.035, (k % 2) * 0.02 - 0.005, cos(a) * 0.035))


# ── 장식품 ───────────────────────────────────────────────────
func _scarf() -> void:
	var red := _stripe_mat(Color(0.82, 0.14, 0.18), Color(0.98, 0.93, 0.85), 12.0, 1, 0.95)
	_add(_torus(0.15, 0.05), red, Vector3(0, 0.655, 0))
	_add(_torus(0.165, 0.042), red, Vector3(0, 0.615, 0), Vector3(0.12, 0, 0))
	var tail := _stripe_mat(Color(0.82, 0.14, 0.18), Color(0.98, 0.93, 0.85), 18.0, 0, 0.95)
	_add(_box(0.1, 0.3, 0.035), tail, Vector3(0.085, 0.49, 0.19), Vector3(0.28, 0, -0.18))
	_add(_box(0.09, 0.24, 0.035), tail, Vector3(0.03, 0.52, 0.2), Vector3(0.24, 0, 0.1))
	for k in 4:   # 술
		_add(_cyl(0.008, 0.008, 0.05, 6), _mat(Color(0.98, 0.93, 0.85), 0.9), Vector3(0.11 + k * 0.02 - 0.03, 0.335, 0.215), Vector3(0.28, 0, -0.18))


func _sunglasses() -> void:
	var frame := _mat(Color(0.08, 0.08, 0.1), 0.25, 0.4)
	var lens := _mat(Color(0.06, 0.1, 0.16), 0.03, 0.6)
	lens.rim_enabled = true
	lens.rim = 0.6
	var y := 0.8
	for sx: float in [-1.0, 1.0]:
		var x := sx * 0.062
		var z := sqrt(HEAD_R * HEAD_R - x * x) + 0.012
		var face := Vector3(PI / 2, sx * 0.4, 0)
		var disc := _cyl(0.05, 0.05, 0.012, 24)
		var l := _add(disc, lens, Vector3(x, y, z), face)
		l.scale = Vector3(1.15, 1.0, 0.85)
		var rim := _add(_torus(0.052, 0.008), frame, Vector3(x, y, z), face)
		rim.scale = Vector3(1.15, 1.0, 0.85)
		# 다리
		_add(_box(0.008, 0.01, 0.15), frame, Vector3(sx * 0.137, y + 0.01, 0.06), Vector3(0, sx * 0.2, 0))
		# 반짝
		_add(_sphere(0.009), _mat(Color(1, 1, 1), 0.1), Vector3(x - 0.02, y + 0.02, z + 0.009))
	_add(_box(0.042, 0.009, 0.009), frame, Vector3(0, y + 0.012, HEAD_R + 0.014))


func _pearls() -> void:
	var pearl := _mat(Color(0.98, 0.96, 0.94), 0.1, 0.15)
	pearl.rim_enabled = true
	pearl.rim = 0.4
	# 옷깃 위에 걸쳐 앞쪽으로 늘어진 진주 목걸이
	for k in 30:
		var a := k * TAU / 30.0
		var f := 0.5 + 0.5 * cos(a)          # 앞쪽(1) ~ 뒤쪽(0)
		var r := 0.19 + 0.012 * f
		_add(_sphere(0.022), pearl, Vector3(sin(a) * r, 0.612 - 0.07 * f * f, cos(a) * r))
	# 가운데 큰 진주 + 금 고리
	_add(_torus(0.016, 0.005), _mat(Color(1.0, 0.8, 0.35), 0.25, 0.9), Vector3(0, 0.528, 0.208), Vector3(PI / 2, 0, 0))
	var big := _add(_sphere(0.036), pearl, Vector3(0, 0.49, 0.212))
	big.scale = Vector3(1.0, 1.15, 1.0)


# ── 옷 ───────────────────────────────────────────────────────
## 주름진 망토 (어깨에서 펄럭이며 뒤로 퍼짐). 안감은 금색
func _cape_mesh(inset: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 14
	var cols := 28
	var a0 := PI * 0.5
	var a1 := PI * 1.5
	var pts := []
	for i in rows + 1:
		var t := float(i) / rows                  # 0 = 어깨, 1 = 바닥
		var y := lerpf(0.6, 0.08, t)
		var row := []
		for j in cols + 1:
			var u := float(j) / cols
			var a := lerpf(a0, a1, u)
			var back := maxf(0.0, -cos(a))         # 뒤쪽일수록 1
			var fold := sin(u * PI * 9.0) * 0.018 * t
			var r := body_radius(clampf(y, 0.1, 0.6)) + 0.03 + t * t * 0.13 * back + fold - inset
			r = maxf(r, 0.17 - inset)
			row.append(Vector3(sin(a) * r, y - back * t * 0.02, cos(a) * r))
		pts.append(row)
	for i in rows:
		for j in cols:
			var p00: Vector3 = pts[i][j]
			var p01: Vector3 = pts[i][j + 1]
			var p10: Vector3 = pts[i + 1][j]
			var p11: Vector3 = pts[i + 1][j + 1]
			var n := (p10 - p00).cross(p01 - p00).normalized()
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(-n)
				st.add_vertex(v)
	return st.commit()


func _cape() -> void:
	var red := _mat(Color(0.72, 0.07, 0.12), 0.55)
	red.cull_mode = BaseMaterial3D.CULL_FRONT     # 바깥에서 보이는 면 (삼각형이 안쪽을 앞면으로 둠)
	var lining := _mat(Color(0.95, 0.74, 0.3), 0.35, 0.3)
	lining.cull_mode = BaseMaterial3D.CULL_BACK
	_add(_cape_mesh(0.0), red, Vector3.ZERO)
	_add(_cape_mesh(0.0), lining, Vector3.ZERO)
	var red2 := red.duplicate() as StandardMaterial3D
	red2.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(_cyl(0.215, 0.215, 0.07, 32), red2, Vector3(0, 0.6, 0))               # 높은 깃
	var gold := _mat(Color(0.98, 0.76, 0.3), 0.25, 0.9)
	_add(_torus(0.205, 0.014), gold, Vector3(0, 0.567, 0))
	_add(_sphere(0.03), gold, Vector3(0, 0.575, 0.205))
	var gem := _mat(Color(0.2, 0.95, 0.7), 0.1, 0.2)
	gem.emission_enabled = true
	gem.emission = Color(0.2, 0.95, 0.7)
	gem.emission_energy_multiplier = 0.5
	_add(_sphere(0.018), gem, Vector3(0, 0.575, 0.232))


func _swim_ring() -> void:
	var r := body_radius(0.29) + 0.075
	_add(_torus(r, 0.08), _stripe_mat(Color(0.97, 0.36, 0.36), Color(0.99, 0.97, 0.93), 8.0, 1, 0.22), Vector3(0, 0.29, 0))
	# 밧줄 손잡이
	var rope := _mat(Color(0.95, 0.88, 0.7), 0.9)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4
		_add(_torus(0.045, 0.008), rope, Vector3(sin(a) * (r + 0.07), 0.29, cos(a) * (r + 0.07)), Vector3(0, a, PI / 2))


func _coat() -> void:
	var pr := PackedVector2Array()
	for i in 16:
		var y := lerpf(0.12, 0.585, float(i) / 15.0)
		pr.append(Vector2(body_radius(y) + 0.022 + maxf(0.5 - y, 0.0) * 0.07, y))
	var brown := _mat(Color(0.68, 0.48, 0.3), 0.85)
	brown.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(lathe(pr, 40), brown, Vector3.ZERO)
	var dark := _mat(Color(0.5, 0.33, 0.19), 0.85)
	# 옷깃 (앞에서 V 자로 벌어짐)
	for sx: float in [-1.0, 1.0]:
		_add(_box(0.07, 0.17, 0.02), dark, Vector3(sx * 0.055, 0.53, body_radius(0.53) + 0.03), Vector3(-0.25, 0, sx * 0.45))
	_add(_torus(0.16, 0.032), dark, Vector3(0, 0.588, 0))
	# 허리띠 + 버클
	var by := 0.34
	_add(_torus(body_radius(by) + 0.03, 0.018), _mat(Color(0.3, 0.19, 0.1), 0.6), Vector3(0, by, 0))
	_add(_box(0.05, 0.045, 0.012), _mat(Color(1.0, 0.8, 0.35), 0.25, 0.9), Vector3(0, by, body_radius(by) + 0.05))
	# 단추 · 주머니
	for yy: float in [0.255, 0.44, 0.5]:
		var rr := body_radius(yy) + 0.022 + maxf(0.5 - yy, 0.0) * 0.07
		_add(_sphere(0.017), _mat(Color(0.22, 0.13, 0.07), 0.35), Vector3(0, yy, rr + 0.006))
	for sx: float in [-1.0, 1.0]:
		var py := 0.22
		var rr := body_radius(py) + 0.022 + maxf(0.5 - py, 0.0) * 0.07
		_add(_box(0.07, 0.012, 0.03), dark, Vector3(sx * rr * 0.6, py, rr * 0.8 + 0.005), Vector3(0, sx * 0.65, 0))


func _add_to(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi
