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
	var base := Vector3(0, 0.905, 0)
	var cone := _cyl(0.0, 0.118, 0.27)
	_add(cone, _stripe_mat(Color(0.95, 0.42, 0.40), Color(0.98, 0.94, 0.86), 14.0, 0), base + Vector3(0, 0.135, 0), Vector3(0, 0, 0.12))
	_add(_sphere(0.042), _mat(Color(0.45, 0.88, 0.80), 0.8), base + Vector3(-0.033, 0.28, 0))


func _top_hat() -> void:
	var y := 0.915
	var black := _mat(Color(0.07, 0.07, 0.085), 0.35)
	_add(_cyl(0.205, 0.205, 0.016), black, Vector3(0, y, 0))
	_add(_cyl(0.118, 0.118, 0.23), black, Vector3(0, y + 0.115, 0))
	_add(_cyl(0.121, 0.121, 0.043), _mat(Color(0.8, 0.22, 0.26), 0.4), Vector3(0, y + 0.034, 0))


func _crown() -> void:
	var y := 0.905
	var gold := _mat(Color(1.0, 0.76, 0.28), 0.25, 0.9)
	var ring := _cyl(0.137, 0.137, 0.08)
	ring.cap_top = false
	ring.cap_bottom = false
	var rm := gold.duplicate() as StandardMaterial3D
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(ring, rm, Vector3(0, y + 0.04, 0))
	_add(_torus(0.137, 0.014), gold, Vector3(0, y + 0.006, 0))
	for k in 5:
		var a := k * TAU / 5.0
		var p := Vector3(sin(a) * 0.132, y + 0.115, cos(a) * 0.132)
		_add(_cyl(0.0, 0.034, 0.08, 12), gold, p)
		_add(_sphere(0.018), gold, p + Vector3(0, 0.045, 0))
		var gem := _mat(Color(0.85, 0.12, 0.2) if k % 2 == 0 else Color(0.15, 0.35, 0.9), 0.15, 0.2)
		_add(_sphere(0.017), gem, Vector3(sin(a + PI / 5) * 0.14, y + 0.045, cos(a + PI / 5) * 0.14))


func _beanie() -> void:
	var cap := SphereMesh.new()
	cap.radius = HEAD_R + 0.026
	cap.height = (HEAD_R + 0.026) * 2.0
	cap.is_hemisphere = true
	cap.radial_segments = 32
	cap.rings = 12
	var orange := _stripe_mat(Color(0.9, 0.62, 0.22), Color(0.8, 0.54, 0.18), 34.0, 1, 0.9)
	_add(cap, orange, HEAD_C + Vector3(0, 0.03, 0))
	_add(_torus(HEAD_R * 0.95 + 0.012, 0.03), _mat(Color(0.8, 0.52, 0.16), 0.95), Vector3(0, 0.845, 0))
	_add(_sphere(0.055), _mat(Color(0.97, 0.93, 0.85), 1.0), Vector3(0, 0.99, 0))


# ── 장식품 ───────────────────────────────────────────────────
func _scarf() -> void:
	var red := _stripe_mat(Color(0.78, 0.15, 0.18), Color(0.96, 0.92, 0.84), 12.0, 1, 0.95)
	_add(_torus(0.128, 0.058), red, Vector3(0, 0.662, 0))
	var tail := _stripe_mat(Color(0.78, 0.15, 0.18), Color(0.96, 0.92, 0.84), 18.0, 0, 0.95)
	_add(_box(0.1, 0.3, 0.03), tail, Vector3(0.085, 0.5, 0.175), Vector3(0.22, 0, -0.16))
	_add(_box(0.09, 0.24, 0.03), tail, Vector3(0.03, 0.53, 0.185), Vector3(0.2, 0, 0.1))


func _sunglasses() -> void:
	var glass := _mat(Color(0.04, 0.08, 0.1), 0.05, 0.3)
	for sx in [-1.0, 1.0]:
		_add(_box(0.12, 0.075, 0.014), glass, Vector3(sx * 0.064, 0.792, 0.146), Vector3(0, sx * 0.3, 0))
		_add(_box(0.006, 0.006, 0.14), glass, Vector3(sx * 0.13, 0.802, 0.05), Vector3(0, sx * 0.15, 0))
	_add(_box(0.04, 0.008, 0.008), glass, Vector3(0, 0.805, 0.158))


func _pearls() -> void:
	var pearl := _mat(Color(0.96, 0.94, 0.92), 0.12, 0.1)
	for k in 24:
		var a := k * TAU / 24.0
		var f := 0.5 + 0.5 * cos(a)
		var r := 0.128 + 0.012 * f
		_add(_sphere(0.023), pearl, Vector3(sin(a) * r, 0.648 - 0.03 * f, cos(a) * r))


# ── 옷 ───────────────────────────────────────────────────────
func _cape() -> void:
	var pr := PackedVector2Array()
	for i in 12:
		var y := lerpf(0.1, 0.6, float(i) / 11.0)
		pr.append(Vector2(0.205 + (0.6 - y) * 0.3, y))
	var mesh := lathe(pr, 24, PI * 0.62, PI * 1.38)   # 뒤쪽만
	var red := _mat(Color(0.7, 0.08, 0.11), 0.6)
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(mesh, red, Vector3.ZERO)
	var gold := _mat(Color(0.98, 0.76, 0.3), 0.3, 0.8)
	_add(_torus(0.19, 0.016), gold, Vector3(0, 0.6, 0))
	_add(_sphere(0.022), gold, Vector3(0, 0.598, 0.19))


func _swim_ring() -> void:
	var r := body_radius(0.29) + 0.07
	_add(_torus(r, 0.074), _stripe_mat(Color(0.95, 0.38, 0.36), Color(0.98, 0.96, 0.92), 8.0, 1, 0.3), Vector3(0, 0.29, 0))


func _coat() -> void:
	var pr := PackedVector2Array()
	for i in 16:
		var y := lerpf(0.125, 0.585, float(i) / 15.0)
		pr.append(Vector2(body_radius(y) + 0.022 + maxf(0.5 - y, 0.0) * 0.06, y))
	var brown := _mat(Color(0.66, 0.46, 0.28), 0.85)
	brown.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(lathe(pr, 40), brown, Vector3.ZERO)
	_add(_torus(0.155, 0.03), _mat(Color(0.56, 0.38, 0.22), 0.85), Vector3(0, 0.585, 0))
	for by in [0.24, 0.34, 0.44]:
		var rr := body_radius(by) + 0.022 + maxf(0.5 - by, 0.0) * 0.06
		_add(_sphere(0.016), _mat(Color(0.22, 0.13, 0.07), 0.4), Vector3(0, by, rr + 0.004))
