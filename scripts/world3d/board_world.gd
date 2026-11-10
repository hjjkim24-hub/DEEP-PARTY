extends Node3D
## 3D 튜토리얼 보드 세상 (말이 직접 들어가 걷는 바다 밑 보드).
## 전부 코드로 만들어요: 바닥, 칸, 길(돌길·계단·다리), 협곡 위 돌기둥 징검다리, 바위 아치 터널,
## 산호 언덕, 화산 분수, 다시마, 물방울, 빛줄기, 보드판 테두리.
##
## 지도 구조 (위에서 본 모습, 북쪽이 위):
##   가운데 START 광장에서 북·서·동 세 갈래 지름길
##   북→서: 산호 언덕 (계단으로 올라갔다 내려옴)
##   서→남: 바위 아치 터널
##   남→동: 협곡 위 나무다리
##   동→북: 협곡 위 돌기둥 징검다리 (칸 사이가 멀리 떨어짐)
##   골인 없음. 칸 색깔 종류는 규칙이 정해지면 의미를 붙여요.

const FloorShader := preload("res://shaders/sea_floor.gdshader")
const TileShader := preload("res://shaders/tile_top.gdshader")
const KelpShader := preload("res://shaders/kelp3d.gdshader")
const RayShader := preload("res://shaders/light_ray.gdshader")
const ICONS := {
	"blue": preload("res://textures/tiles/icon_pearl.png"),
	"red": preload("res://textures/tiles/icon_urchin.png"),
	"event": preload("res://textures/tiles/icon_event.png"),
	"star": preload("res://textures/tiles/icon_star.png"),
	"junction": preload("res://textures/tiles/icon_arrows.png"),
	"start": preload("res://textures/tiles/icon_start.png"),
}
const BORDER_TEX := preload("res://textures/tiles/icon_border.png")
const TILE_COLORS := {
	"blue": Color(0.27, 0.59, 0.9), "red": Color(0.89, 0.32, 0.31), "event": Color(0.35, 0.77, 0.43),
	"star": Color(0.95, 0.75, 0.24), "junction": Color(0.93, 0.94, 0.9), "start": Color(0.95, 0.96, 0.92),
}
const INK_COLORS := {
	"blue": Color(0.92, 0.96, 1.0), "red": Color(1.0, 0.92, 0.89), "event": Color(0.95, 1.0, 0.93),
	"star": Color(1.0, 0.98, 0.86), "junction": Color(0.84, 0.63, 0.2), "start": Color(0.84, 0.63, 0.2),
}

const HALF_W := 28.0          ## 판 가로 반
const HALF_D := 24.0          ## 판 세로 반
const STEP := 0.5             ## 바닥 격자 간격
const TILE := 2.2
const TILE_H := 0.45
const PLAZA := 6.0
const SPACING := 3.4

const S := Vector3(0, 0, 0)
const N := Vector3(0, 0, -11)
const W := Vector3(-15, 0, 0)
const E := Vector3(15, 0, 0)
const SO := Vector3(0, 0, 12)

## 길: 지나가는 점들 (x, 높이, z), 다리 여부
var ROUTES := [
	{"pts": [S, N]},
	{"pts": [S, W]},
	{"pts": [S, E]},
	{"pts": [N, Vector3(-4, 0, -14), Vector3(-8, 2.0, -16.5), Vector3(-12.5, 4.0, -16), Vector3(-16.5, 4.0, -12),
			Vector3(-18, 4.0, -7.5), Vector3(-17.5, 2.0, -3.5), W]},
	{"pts": [W, Vector3(-16.5, 0, 5), Vector3(-12.5, 0, 9.5), Vector3(-6.5, 0, 12.5), SO]},
	{"pts": [SO, Vector3(5, 0, 13.5), Vector3(8.8, 1.3, 11.2), Vector3(12, 1.3, 8.2), Vector3(15, 0, 5), E], "bridge": true},
	{"pts": [E, Vector3(16.5, 0, -4), Vector3(14.2, 0.9, -8), Vector3(10.2, 0.9, -11.2), Vector3(5, 0, -13.5), N], "spacing": 4.6},
]
const PLATEAU_C := Vector2(-15.5, -12.0)
const PLATEAU_R := Vector2(5.8, 6.2)
const PLATEAU_H := 4.0
const CHASMS := [
	{"c": Vector2(12.2, -9.6), "r": Vector2(3.4, 3.9), "depth": 6.5},
	{"c": Vector2(10.4, 9.7), "r": Vector2(3.6, 3.2), "depth": 6.5},
]
const VOLCANO := Vector2(21.0, -16.0)
const ARCH_AT := Vector2(-12.5, 9.5)

var spaces: Array = []        ## {pos: Vector3 (칸 윗면 가운데), kind, links: Array[int], yaw}
var start_index := 0
var _rng := RandomNumberGenerator.new()
var _mats := {}


func _ready() -> void:
	_rng.seed = 7
	_build_spaces()
	_environment()
	_floor()
	_board_rim()
	_tiles()
	_connectors()
	_landmarks()
	_decor()
	_effects()


# ── 칸 배치 ──────────────────────────────────────────────────
func _catmull(pts: Array, per: int) -> Array:
	var out := []
	var p := [pts[0]] + pts + [pts[pts.size() - 1]]
	for i in range(1, p.size() - 2):
		var p0: Vector3 = p[i - 1]
		var p1: Vector3 = p[i]
		var p2: Vector3 = p[i + 1]
		var p3: Vector3 = p[i + 2]
		for s in per:
			var t := float(s) / per
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out


func _node_at(p: Vector3, kind: String, yaw: float) -> int:
	for i in spaces.size():
		var q: Vector3 = spaces[i]["base"]
		if Vector2(q.x - p.x, q.z - p.z).length() < 0.5:
			return i
	spaces.append({"base": p, "kind": kind, "links": [], "yaw": yaw, "bridge": false})
	return spaces.size() - 1


func _build_spaces() -> void:
	_node_at(S, "start", 0.0)
	var pattern := ["blue", "blue", "red", "blue", "event", "blue", "star", "blue", "red", "blue", "event"]
	var k := 0
	for r in ROUTES:
		var curve := _catmull(r["pts"], 24)
		var cum := [0.0]
		for i in range(1, curve.size()):
			var a: Vector3 = curve[i - 1]
			var b: Vector3 = curve[i]
			cum.append(cum[i - 1] + Vector2(b.x - a.x, b.z - a.z).length())
		var total: float = cum[cum.size() - 1]
		var sp: float = r.get("spacing", SPACING)
		var n := maxi(1, int(round(total / sp)))
		var ids := []
		for j in n + 1:
			var d := total * j / n
			var idx := 0
			while idx < cum.size() - 2 and cum[idx + 1] < d:
				idx += 1
			var seg_len: float = maxf(cum[idx + 1] - cum[idx], 0.0001)
			var f: float = (d - cum[idx]) / seg_len
			var p: Vector3 = (curve[idx] as Vector3).lerp(curve[idx + 1], f)
			var dir: Vector3 = (curve[mini(idx + 1, curve.size() - 1)] as Vector3) - (curve[idx] as Vector3)
			var yaw := atan2(dir.x, dir.z)
			if j == 0:
				p = r["pts"][0]
			elif j == n:
				p = r["pts"][r["pts"].size() - 1]
			elif Vector2(p.x - S.x, p.z - S.z).length() < PLAZA * 0.5 + 1.9:
				continue
			var kind := "space"
			if j != 0 and j != n:
				kind = pattern[k % pattern.size()]
				k += 1
			var id := _node_at(p, kind, yaw)
			if r.get("bridge", false):
				spaces[id]["bridge"] = true
			ids.append(id)
		for j in ids.size() - 1:
			var a: int = ids[j]
			var b: int = ids[j + 1]
			if not spaces[a]["links"].has(b):
				spaces[a]["links"].append(b)
				spaces[b]["links"].append(a)
	for sp in spaces:
		if sp["kind"] == "space":
			sp["kind"] = "junction" if sp["links"].size() > 2 else "blue"
		if sp["kind"] != "start" and sp["links"].size() > 2:
			sp["kind"] = "junction"
			sp["yaw"] = 0.0
		var top_h: float = PLAZA * 0.0 + (0.5 if sp["kind"] == "start" else TILE_H)
		sp["pos"] = (sp["base"] as Vector3) + Vector3(0, top_h, 0)


# ── 높이 ─────────────────────────────────────────────────────
func _noise2(x: float, z: float) -> float:
	return sin(x * 0.31 + sin(z * 0.17) * 1.3) * 0.5 + sin(z * 0.27 + sin(x * 0.21) * 1.7) * 0.5


func natural_height(x: float, z: float) -> float:
	var h := _noise2(x, z) * 0.35 + sin(x * 0.9 + z * 0.4) * 0.05
	# 산호 언덕
	var pd := Vector2((x - PLATEAU_C.x) / PLATEAU_R.x, (z - PLATEAU_C.y) / PLATEAU_R.y).length()
	pd += _noise2(x * 2.0, z * 2.0) * 0.06
	h += PLATEAU_H * smoothstep(1.08, 0.92, pd)
	# 협곡
	for c in CHASMS:
		var cc: Vector2 = c["c"]
		var rr: Vector2 = c["r"]
		var cd := Vector2((x - cc.x) / rr.x, (z - cc.y) / rr.y).length() + _noise2(x * 2.3, z * 2.3) * 0.07
		h -= float(c["depth"]) * smoothstep(1.05, 0.8, cd)
	# 화산
	var vd := Vector2(x - VOLCANO.x, z - VOLCANO.y).length()
	h += pow(clampf(1.0 - vd / 7.5, 0.0, 1.0), 1.3) * 5.0 - exp(-pow(vd / 1.6, 2.0)) * 3.2
	return h


func _in_chasm(x: float, z: float) -> bool:
	return natural_height(x, z) < -1.5


func ground_height(x: float, z: float) -> float:
	var h := natural_height(x, z)
	if h < -1.5:
		return h
	# 칸 근처는 칸 높이에 맞춰 평평하게 (계단 언덕도 여기서 생김)
	var best_w := 0.0
	var target := 0.0
	for sp in spaces:
		var b: Vector3 = sp["base"]
		var r := PLAZA * 0.75 if sp["kind"] == "start" else 2.4
		var d := Vector2(x - b.x, z - b.z).length()
		if d < r * 1.6:
			var w := smoothstep(r * 1.6, r * 0.7, d)
			if w > best_w:
				best_w = w
				target = b.y - 0.05
	return lerpf(h, target, best_w)


# ── 재질 ─────────────────────────────────────────────────────
func _mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


func _mi(mesh: Mesh, mat: Material, pos: Vector3, basis_: Basis = Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis_, pos)
	add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r_top: float, r_bot: float, h: float, segs: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 2
	return c


# ── 환경 ─────────────────────────────────────────────────────
func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.17, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.62, 0.6)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.32, 0.32)
	env.fog_density = 0.013
	env.glow_enabled = true
	env.glow_intensity = 0.5
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.97, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


# ── 바닥 ─────────────────────────────────────────────────────
func _floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(HALF_W * 2.0 / STEP)
	var nz := int(HALF_D * 2.0 / STEP)
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := -HALF_W + i * STEP
			var z := -HALF_D + j * STEP
			hs[j * (nx + 1) + i] = ground_height(x, z)
	for j in nz + 1:
		for i in nx + 1:
			var x := -HALF_W + i * STEP
			var z := -HALF_D + j * STEP
			var hl := hs[j * (nx + 1) + maxi(i - 1, 0)]
			var hr := hs[j * (nx + 1) + mini(i + 1, nx)]
			var hd := hs[maxi(j - 1, 0) * (nx + 1) + i]
			var hu := hs[mini(j + 1, nz) * (nx + 1) + i]
			st.set_normal(Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized())
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, hs[j * (nx + 1) + i], z))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)
	var m := ShaderMaterial.new()
	m.shader = FloorShader
	_mi(st.commit(), m, Vector3.ZERO)


func _board_rim() -> void:
	var lacquer := _mat(Color(0.05, 0.29, 0.3), 0.3)
	var pearl := _mat(Color(0.9, 0.97, 0.94), 0.25)
	var t := 1.2
	for side in [[Vector3(0, 0.2, -HALF_D - t / 2), Vector3(HALF_W * 2 + t * 2, 1.6, t)],
			[Vector3(0, 0.2, HALF_D + t / 2), Vector3(HALF_W * 2 + t * 2, 1.6, t)],
			[Vector3(-HALF_W - t / 2, 0.2, 0), Vector3(t, 1.6, HALF_D * 2)],
			[Vector3(HALF_W + t / 2, 0.2, 0), Vector3(t, 1.6, HALF_D * 2)]]:
		_mi(_box(side[1]), lacquer, side[0])
		var inlay: Vector3 = side[1]
		inlay = Vector3(maxf(inlay.x - 0.6, 0.15) if inlay.x > 2 else 0.15, 0.03, maxf(inlay.z - 0.6, 0.15) if inlay.z > 2 else 0.15)
		_mi(_box(inlay), pearl, (side[0] as Vector3) + Vector3(0, 0.81, 0))
	# 판 아래 받침
	_mi(_box(Vector3(HALF_W * 2 + t * 2, 2.0, HALF_D * 2 + t * 2)), lacquer, Vector3(0, -8.0, 0))


# ── 칸 ───────────────────────────────────────────────────────
func _tile_top_mat(kind: String) -> ShaderMaterial:
	var key := "tile_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TileShader
	m.set_shader_parameter("tile_color", TILE_COLORS[kind])
	m.set_shader_parameter("ink_color", INK_COLORS[kind])
	m.set_shader_parameter("icon_tex", ICONS[kind])
	m.set_shader_parameter("border_tex", BORDER_TEX)
	m.set_shader_parameter("icon_scale", 0.8 if kind == "start" else 0.62)
	_mats[key] = m
	return m


func _tiles() -> void:
	var stone := _mat(Color(0.84, 0.85, 0.81), 0.7)
	var dark := _mat(Color(0.5, 0.53, 0.5), 0.9)
	for sp in spaces:
		var base: Vector3 = sp["base"]
		var kind: String = sp["kind"]
		var b := Basis(Vector3.UP, sp["yaw"])
		if kind == "start":
			_mi(_box(Vector3(PLAZA, 0.5, PLAZA)), stone, base + Vector3(0, 0.25, 0), b)
			_mi(_box(Vector3(PLAZA + 0.4, 0.18, PLAZA + 0.4)), dark, base + Vector3(0, 0.09, 0), b)
			var top := PlaneMesh.new()
			top.size = Vector2(PLAZA - 0.3, PLAZA - 0.3)
			_mi(top, _tile_top_mat("start"), base + Vector3(0, 0.505, 0), b)
			continue
		var size := TILE + (0.2 if kind == "junction" else 0.0)
		_mi(_box(Vector3(size, TILE_H, size)), stone, base + Vector3(0, TILE_H * 0.5, 0), b)
		# 아래 굽 (살짝 넓은 받침)
		_mi(_box(Vector3(size + 0.25, 0.12, size + 0.25)), dark, base + Vector3(0, 0.06, 0), b)
		var plane := PlaneMesh.new()
		plane.size = Vector2(size - 0.12, size - 0.12)
		_mi(plane, _tile_top_mat(kind), base + Vector3(0, TILE_H + 0.004, 0), b)
		# 협곡 위 칸은 돌기둥이 받침
		if _in_chasm(base.x, base.z):
			var depth := base.y - natural_height(base.x, base.z) + 0.5
			_mi(_cyl(0.85, 1.05, depth, 16), _mat(Color(0.58, 0.6, 0.57), 0.9), base - Vector3(0, depth * 0.5, 0))
			_mi(_cyl(1.2, 0.9, 0.35, 16), _mat(Color(0.66, 0.68, 0.64), 0.85), base + Vector3(0, -0.15, 0))


# ── 길 (돌길 / 계단 / 다리 / 징검다리) ────────────────────────
func _connectors() -> void:
	var cobble := _mat(Color(0.62, 0.63, 0.58), 0.95)
	var step_m := _mat(Color(0.78, 0.78, 0.74), 0.85)
	var wood := _mat(Color(0.48, 0.33, 0.2), 0.8)
	var rope := _mat(Color(0.78, 0.68, 0.48), 0.9)
	var done := {}
	for i in spaces.size():
		for j in spaces[i]["links"]:
			var key := "%d_%d" % [mini(i, j), maxi(i, j)]
			if done.has(key):
				continue
			done[key] = true
			var a: Vector3 = spaces[i]["base"]
			var b: Vector3 = spaces[j]["base"]
			var ra := PLAZA * 0.5 if spaces[i]["kind"] == "start" else TILE * 0.5
			var rb := PLAZA * 0.5 if spaces[j]["kind"] == "start" else TILE * 0.5
			var flat := Vector3(b.x - a.x, 0, b.z - a.z)
			var dist := flat.length()
			var dir := flat / dist
			var p0 := a + dir * ra
			var p1 := b - dir * rb
			var gap := (p1 - p0)
			var glen := Vector2(gap.x, gap.z).length()
			if glen < 0.05:
				continue
			var yaw := atan2(dir.x, dir.z)
			var bas := Basis(Vector3.UP, yaw)
			var mid := (p0 + p1) * 0.5
			var over_chasm := _in_chasm(mid.x, mid.z)
			var dy := b.y - a.y
			if over_chasm:
				if spaces[i]["bridge"] and spaces[j]["bridge"]:
					_bridge(p0, p1, bas, glen, wood, rope)
				# 아니면 징검다리 — 아무것도 없이 뚝 떨어져 있음
				continue
			if absf(dy) > 0.3:
				var n := maxi(2, int(ceil(absf(dy) / 0.28)))
				for s in n:
					var f := (float(s) + 0.5) / n
					var pos := p0.lerp(p1, f)
					var top := lerpf(a.y + TILE_H, b.y + TILE_H, (float(s) + 1.0) / n) if dy > 0 else lerpf(a.y + TILE_H, b.y + TILE_H, float(s) / n)
					var low := minf(a.y, b.y) - 0.3
					var hgt := top - low
					_mi(_box(Vector3(1.6, hgt, glen / n + 0.02)), step_m, Vector3(pos.x, low + hgt * 0.5, pos.z), bas)
				continue
			# 평범한 자갈길
			var y := (a.y + b.y) * 0.5 + 0.08
			_mi(_box(Vector3(1.3, 0.16, glen + 0.1)), cobble, Vector3(mid.x, y, mid.z), bas)
			for s in int(glen / 0.55):
				var f := (float(s) + 0.5) / int(glen / 0.55)
				var pp := p0.lerp(p1, f)
				for side in [-0.32, 0.32]:
					var off := bas.x * side
					_mi(_box(Vector3(0.5, 0.06, 0.45)), _mat(Color(0.7, 0.71, 0.66).darkened(_rng.randf() * 0.15), 0.9),
						Vector3(pp.x + off.x, y + 0.1, pp.z + off.z), Basis(Vector3.UP, yaw + _rng.randf_range(-0.2, 0.2)))


func _bridge(p0: Vector3, p1: Vector3, bas: Basis, glen: float, wood: Material, rope: Material) -> void:
	var n := int(glen / 0.42)
	for s in n:
		var f := (float(s) + 0.5) / n
		var pos := p0.lerp(p1, f)
		var sag := sin(f * PI) * -0.25
		_mi(_box(Vector3(1.7, 0.1, 0.34)), wood, Vector3(pos.x, pos.y + TILE_H - 0.1 + sag, pos.z), bas.rotated(Vector3.UP, 0.0))
	for side in [-0.9, 0.9]:
		var off := bas.x * side
		for end in [p0, p1]:
			_mi(_cyl(0.07, 0.08, 1.4, 8), wood, end + off + Vector3(0, TILE_H + 0.3, 0))
		var mid := (p0 + p1) * 0.5 + off + Vector3(0, TILE_H + 0.7, 0)
		_mi(_box(Vector3(0.05, 0.05, glen)), rope, mid, bas)


# ── 볼거리 ───────────────────────────────────────────────────
func _landmarks() -> void:
	var stone := _mat(Color(0.86, 0.85, 0.8), 0.8)
	var moss := _mat(Color(0.36, 0.55, 0.36), 0.95)
	# START 광장 둘레 부서진 기둥
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for k in corners.size():
		var c: Vector2 = corners[k] * (PLAZA * 0.5 + 1.0)
		var hgt: float = [3.2, 2.1, 1.4, 2.7][k]
		var p := Vector3(c.x, 0, c.y)
		_mi(_box(Vector3(1.3, 0.35, 1.3)), stone, p + Vector3(0, 0.17, 0))
		_mi(_cyl(0.45, 0.5, hgt, 16), stone, p + Vector3(0, 0.35 + hgt * 0.5, 0))
		_mi(_cyl(0.47, 0.47, 0.08, 16), moss, p + Vector3(0, 0.35 + hgt, 0), Basis(Vector3(1, 0, 0), 0.15))
	# 쓰러진 기둥
	_mi(_cyl(0.45, 0.45, 3.2, 16), stone, Vector3(-PLAZA * 0.5 - 2.6, 0.4, PLAZA * 0.5 - 0.6), Basis(Vector3(0, 0, 1), PI / 2).rotated(Vector3.UP, 0.4))

	# 바위 아치 터널 (서→남 길 위)
	var rock := _mat(Color(0.5, 0.5, 0.46), 0.95)
	var dir := Vector2(-6.5 - (-16.5), 12.5 - 5.0).normalized()
	var yaw := atan2(dir.x, dir.y)
	for k in 3:
		var off := (k - 1) * 1.3
		var p := Vector3(ARCH_AT.x + dir.x * off, ground_height(ARCH_AT.x, ARCH_AT.y) - 0.3, ARCH_AT.y + dir.y * off)
		var t := TorusMesh.new()
		t.inner_radius = 2.3
		t.outer_radius = 3.5 - k * 0.15
		t.rings = 24
		t.ring_segments = 10
		# 고리를 세워서 길과 수직으로
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI / 2)
		_mi(t, rock, p, b)
	# 아치 위 이끼·산호
	_coral(Vector3(ARCH_AT.x, ground_height(ARCH_AT.x, ARCH_AT.y) + 3.0, ARCH_AT.y), Color(1.0, 0.45, 0.55), 0.7)

	# 화산 분수 안쪽 불빛
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.25)
	glow.light_energy = 3.0
	glow.omni_range = 7.0
	glow.position = Vector3(VOLCANO.x, natural_height(VOLCANO.x, VOLCANO.y) + 1.0, VOLCANO.y)
	add_child(glow)
	var lava := StandardMaterial3D.new()
	lava.albedo_color = Color(1.0, 0.45, 0.15)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.45, 0.15)
	lava.emission_energy_multiplier = 2.5
	_mi(_cyl(1.0, 1.0, 0.1, 16), lava, Vector3(VOLCANO.x, natural_height(VOLCANO.x, VOLCANO.y) + 0.2, VOLCANO.y))


func _free_spot(x: float, z: float, r: float) -> bool:
	if absf(x) > HALF_W - 1.5 or absf(z) > HALF_D - 1.5:
		return false
	if _in_chasm(x, z):
		return false
	for sp in spaces:
		var b: Vector3 = sp["base"]
		var rr := PLAZA * 0.5 + 1.5 if sp["kind"] == "start" else 2.2
		if Vector2(x - b.x, z - b.z).length() < rr + r:
			return false
	# 길 사이 (연결선) 근처도 피함
	for i in spaces.size():
		for j in spaces[i]["links"]:
			var a: Vector3 = spaces[i]["base"]
			var b: Vector3 = spaces[j]["base"]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := Vector2(x - a.x, z - a.z)
			var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if (ap - ab * t).length() < 1.4 + r:
				return false
	if Vector2(x - ARCH_AT.x, z - ARCH_AT.y).length() < 3.5 + r:
		return false
	return true


func _rock(p: Vector3, r: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var seed_ := _rng.randf() * 10.0
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + 0.18 * sin(v.x * 3.1 + seed_) * sin(v.y * 2.7 + seed_ * 2.0) + 0.1 * sin(v.z * 5.3 + seed_)
		verts[i] = v * k
		norms[i] = (v * k).normalized()
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var c := Color(0.5, 0.5, 0.46).lerp(Color(0.42, 0.48, 0.44), _rng.randf())
	var mi := _mi(mesh, _mat(c, 0.95), p)
	mi.scale = Vector3(r * _rng.randf_range(0.9, 1.3), r * _rng.randf_range(0.55, 0.8), r * _rng.randf_range(0.9, 1.2))
	mi.rotation.y = _rng.randf() * TAU


func _coral(p: Vector3, c: Color, size: float) -> void:
	var m := _mat(c, 0.7)
	var tip := _mat(c.lightened(0.25), 0.6)
	var stack := [[p, Vector3.UP, 0.9 * size, 0.13 * size, 3]]
	for k in 2:
		stack.append([p, Vector3(_rng.randf_range(-0.5, 0.5), 1.0, _rng.randf_range(-0.5, 0.5)).normalized(), 0.8 * size, 0.11 * size, 3])
	while stack.size() > 0:
		var it: Array = stack.pop_back()
		var a: Vector3 = it[0]
		var d: Vector3 = it[1]
		var ln: float = it[2]
		var rad: float = it[3]
		var depth: int = it[4]
		var b := a + d * ln
		var q := Quaternion(Vector3.UP, d)
		_mi(_cyl(rad * 0.75, rad, ln, 8), m, (a + b) * 0.5, Basis(q))
		if depth == 0:
			var s := SphereMesh.new()
			s.radius = rad * 0.8
			s.height = rad * 1.6
			s.radial_segments = 8
			s.rings = 4
			_mi(s, tip, b)
			continue
		for side in [-1.0, 1.0]:
			var nd := (d + Vector3(side * _rng.randf_range(0.35, 0.7), _rng.randf_range(0.05, 0.3), _rng.randf_range(-0.5, 0.5))).normalized()
			stack.append([b, nd, ln * 0.74, rad * 0.74, depth - 1])


func _sponge(p: Vector3, c: Color) -> void:
	var m := _mat(c, 0.85)
	var inner := _mat(c.darkened(0.6), 0.9)
	for k in _rng.randi_range(3, 5):
		var off := Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
		var h := _rng.randf_range(1.0, 2.2)
		var r := _rng.randf_range(0.18, 0.28)
		_mi(_cyl(r, r * 1.1, h, 12), m, p + off + Vector3(0, h * 0.5, 0))
		_mi(_cyl(r * 0.75, r * 0.75, 0.02, 12), inner, p + off + Vector3(0, h + 0.005, 0))


func _kelp(p: Vector3, h: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var y0 := h * i / n
		var y1 := h * (i + 1) / n
		var w0 := lerpf(0.28, 0.08, float(i) / n)
		var w1 := lerpf(0.28, 0.08, float(i + 1) / n)
		var v := [Vector3(-w0, y0, 0), Vector3(w0, y0, 0), Vector3(w1, y1, 0), Vector3(-w1, y1, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(v[idx])
		if i % 2 == 0 and i > 1:
			var side := 1.0 if i % 4 == 0 else -1.0
			var lv := [Vector3(side * w0, y0, 0), Vector3(side * (w0 + 0.7), y0 + 0.35, 0.1), Vector3(side * w0, y0 + 0.55, 0)]
			for idx in [0, 1, 2]:
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(lv[idx])
	var m := ShaderMaterial.new()
	m.shader = KelpShader
	m.set_shader_parameter("phase", _rng.randf() * TAU)
	m.set_shader_parameter("color", Color(0.14, 0.46, 0.26).lerp(Color(0.3, 0.55, 0.22), _rng.randf()))
	_mi(st.commit(), m, p, Basis(Vector3.UP, _rng.randf() * TAU))


func _decor() -> void:
	var coral_cols := [Color(1.0, 0.42, 0.38), Color(1.0, 0.62, 0.3), Color(0.75, 0.43, 0.95), Color(1.0, 0.4, 0.62), Color(1.0, 0.85, 0.42)]
	# 산호 언덕 위·주변
	var zones := [[PLATEAU_C, 6.0, 16], [Vector2(-22, -18), 4.0, 6], [Vector2(20, 17), 5.0, 8], [Vector2(-6, 18), 4.0, 5],
		[Vector2(22, 4), 3.0, 4], [Vector2(-4, -20), 4.0, 5], [Vector2(6, 4), 3.0, 3], [Vector2(-7, -5), 3.0, 3]]
	for z in zones:
		var c: Vector2 = z[0]
		for k in z[2]:
			for t in 20:
				var x: float = c.x + _rng.randfn(0.0, z[1])
				var zz: float = c.y + _rng.randfn(0.0, z[1])
				if _free_spot(x, zz, 0.8):
					var p := Vector3(x, ground_height(x, zz), zz)
					if _rng.randf() < 0.7:
						_coral(p, coral_cols[_rng.randi() % coral_cols.size()], _rng.randf_range(0.8, 1.4))
					else:
						_sponge(p, coral_cols[_rng.randi() % coral_cols.size()])
					break
	# 바위
	for k in 46:
		for t in 20:
			var x := _rng.randf_range(-HALF_W + 2, HALF_W - 2)
			var zz := _rng.randf_range(-HALF_D + 2, HALF_D - 2)
			var r := _rng.randf_range(0.5, 1.6) if _rng.randf() < 0.85 else _rng.randf_range(1.8, 2.8)
			if _free_spot(x, zz, r):
				_rock(Vector3(x, ground_height(x, zz) - r * 0.25, zz), r)
				break
	# 다시마 숲 (남서쪽)
	for k in 70:
		for t in 10:
			var x := -21.0 + _rng.randfn(0.0, 4.0)
			var zz := 12.0 + _rng.randfn(0.0, 5.0)
			if _free_spot(x, zz, 0.3):
				_kelp(Vector3(x, ground_height(x, zz), zz), _rng.randf_range(4.0, 8.0))
				break
	for k in 24:
		for t in 10:
			var x := _rng.randf_range(-HALF_W + 2, HALF_W - 2)
			var zz := _rng.randf_range(-HALF_D + 2, HALF_D - 2)
			if _free_spot(x, zz, 0.3):
				_kelp(Vector3(x, ground_height(x, zz), zz), _rng.randf_range(3.0, 6.0))
				break


# ── 물방울·빛줄기 ────────────────────────────────────────────
func _bubble_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 1.0, 0.97, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 0.65)
	m.emission_energy_multiplier = 0.4
	s.material = m
	return s


func bubbles_at(p: Vector3, amount: int, radius: float, one_shot: bool = false) -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.mesh = _bubble_mesh(0.09)
	c.amount = amount
	c.lifetime = 4.0
	c.one_shot = one_shot
	c.explosiveness = 0.9 if one_shot else 0.0
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	c.emission_sphere_radius = radius
	c.direction = Vector3.UP
	c.spread = 18.0
	c.gravity = Vector3(0, 1.4, 0)
	c.initial_velocity_min = 0.6
	c.initial_velocity_max = 1.6
	c.scale_amount_min = 0.5
	c.scale_amount_max = 2.2
	c.position = p
	add_child(c)
	c.emitting = true
	return c


func _effects() -> void:
	bubbles_at(Vector3(VOLCANO.x, natural_height(VOLCANO.x, VOLCANO.y) + 0.5, VOLCANO.y), 40, 0.6)
	for c in CHASMS:
		var cc: Vector2 = c["c"]
		bubbles_at(Vector3(cc.x, -float(c["depth"]) + 0.5, cc.y), 14, 1.5)
	# 떠다니는 알갱이
	var snow := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 4
	sm.rings = 2
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 1.0, 0.95, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	snow.mesh = sm
	snow.amount = 400
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(HALF_W, 4.0, HALF_D)
	snow.position = Vector3(0, 4.0, 0)
	snow.gravity = Vector3(0, -0.03, 0)
	snow.initial_velocity_min = 0.0
	snow.initial_velocity_max = 0.15
	snow.spread = 180.0
	add_child(snow)
	# 빛줄기
	for k in 9:
		var q := QuadMesh.new()
		q.size = Vector2(_rng.randf_range(2.0, 5.0), 34.0)
		var m := ShaderMaterial.new()
		m.shader = RayShader
		m.set_shader_parameter("phase", _rng.randf() * TAU)
		m.set_shader_parameter("strength", _rng.randf_range(0.06, 0.14))
		var p := Vector3(_rng.randf_range(-HALF_W, HALF_W), 14.0, _rng.randf_range(-HALF_D, HALF_D))
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3(0, 0, 1), deg_to_rad(18))
		_mi(q, m, p, b)


## START 광장 위 말 세울 자리
func start_spots(n: int) -> Array:
	var top: Vector3 = spaces[start_index]["pos"]
	var offs := [Vector3(-1.1, 0, -0.9), Vector3(1.1, 0, -0.9), Vector3(-1.1, 0, 1.1), Vector3(1.1, 0, 1.1)]
	if n == 1:
		return [top]
	var out := []
	for i in n:
		out.append(top + offs[i % 4])
	return out
