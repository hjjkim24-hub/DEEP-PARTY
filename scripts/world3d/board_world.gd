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
##   골인 없음.
##
## 칸 종류 (kind):
##   plain    일반 칸 — 아무 일도 없음
##   chance   찬스 칸 — 랜덤 찬스 카드 (카드 내용은 나중에)
##   minigame 미니게임 칸 — 가장 많음
##   portal   포탈 칸 — 짝이 되는 반대편 포탈로 이동 (portal_partner())
##   shop     상점 칸 — 옆에 가게 노점 (상품은 나중에)
##   junction 갈림길, start 시작 광장
## 칸 배치는 아래 ROUTES 의 "tiles" 에서 길마다 순서대로 정해요.

const FloorShader := preload("res://shaders/sea_floor.gdshader")
const TileShader := preload("res://shaders/tile_top.gdshader")
const KelpShader := preload("res://shaders/kelp3d.gdshader")
const RayShader := preload("res://shaders/light_ray.gdshader")
const PortalShader := preload("res://shaders/portal_top.gdshader")
const MeshKit := preload("res://scripts/world3d/mesh_kit.gd")
const ReefKit := preload("res://scripts/world3d/reef_kit.gd")
const SeagrassShader := preload("res://shaders/seagrass3d.gdshader")
const FishShader := preload("res://shaders/fish3d.gdshader")
const AnemoneShader := preload("res://shaders/anemone3d.gdshader")
const RockShader := preload("res://shaders/reef_rock.gdshader")
const BrainShader := preload("res://shaders/brain_coral.gdshader")
const SkyShader := preload("res://shaders/underwater_sky.gdshader")
const FAN_TEX := preload("res://textures/decor/sea_fan.png")
const ICONS := {
	"plain": preload("res://textures/tiles/icon_plain.png"),
	"chance": preload("res://textures/tiles/icon_chance.png"),
	"minigame": preload("res://textures/tiles/icon_minigame.png"),
	"portal": preload("res://textures/tiles/icon_portal.png"),
	"shop": preload("res://textures/tiles/icon_shop.png"),
	"junction": preload("res://textures/tiles/icon_arrows.png"),
	"start": preload("res://textures/tiles/icon_start.png"),
	"coin_plus": preload("res://textures/tiles/icon_coin_plus.png"),
	"coin_minus": preload("res://textures/tiles/icon_coin_minus.png"),
}
const BORDER_TEX := preload("res://textures/tiles/icon_border.png")
const CHANCE_CARD_TEX := preload("res://textures/tiles/card_chance.png")
const TILE_COLORS := {
	"plain": Color(0.84, 0.82, 0.72), "chance": Color(0.98, 0.72, 0.2), "minigame": Color(0.26, 0.58, 0.9),
	"portal": Color(0.58, 0.38, 0.92), "shop": Color(0.94, 0.43, 0.56),
	"junction": Color(0.8, 0.82, 0.77), "start": Color(0.5, 0.64, 0.62),
	"coin_plus": Color(0.3, 0.76, 0.4), "coin_minus": Color(0.86, 0.3, 0.32),
}
const INK_COLORS := {
	"plain": Color(1, 1, 1), "chance": Color(1.0, 0.98, 0.9), "minigame": Color(0.95, 0.98, 1.0),
	"portal": Color(1, 1, 1), "shop": Color(1.0, 0.96, 0.97),
	"junction": Color(0.84, 0.63, 0.2), "start": Color(0.84, 0.63, 0.2),
	"coin_plus": Color(1, 1, 1), "coin_minus": Color(1, 1, 1),
}
## 범례 순서 + 화면에 보일 이름 (번역 키)
const KIND_ORDER := ["plain", "chance", "minigame", "portal", "shop"]
const KIND_NAMES := {
	"plain": "Plain", "chance": "Chance", "minigame": "Minigame", "portal": "Portal", "shop": "Shop",
	"coin_plus": "Lucky +5", "coin_minus": "Trap -5",
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

## 길: 지나가는 점들 (x, 높이, z), 다리 여부, 칸 종류 (길 처음→끝 순서, 양 끝 갈림길 제외)
## (일반 7 · 찬스 6 · 미니게임 15 · 포탈 2 · 상점 2)
var ROUTES := [
	{"pts": [S, N], "tiles": ["minigame"]},
	{"pts": [S, W], "tiles": ["minigame", "chance"]},
	{"pts": [S, E], "tiles": ["minigame", "plain"]},
	{"pts": [N, Vector3(-4, 0, -14), Vector3(-8, 2.0, -16.5), Vector3(-12.5, 4.0, -16), Vector3(-16.5, 4.0, -12),
			Vector3(-18, 4.0, -7.5), Vector3(-17.5, 2.0, -3.5), W],
		"tiles": ["plain", "minigame", "chance", "minigame", "shop", "minigame", "plain", "chance", "minigame"]},
	{"pts": [W, Vector3(-16.5, 0, 5), Vector3(-12.5, 0, 9.5), Vector3(-6.5, 0, 12.5), SO],
		"tiles": ["plain", "portal", "minigame", "chance", "minigame", "plain"], "end": "minigame"},
	{"pts": [SO, Vector3(5, 0, 13.5), Vector3(8.8, 1.3, 11.2), Vector3(12, 1.3, 8.2), Vector3(15, 0, 5), E], "bridge": true,
		"tiles": ["plain", "shop", "minigame", "chance", "minigame", "plain"]},
	{"pts": [E, Vector3(16.5, 0, -4), Vector3(14.2, 0.9, -8), Vector3(10.2, 0.9, -11.2), Vector3(5, 0, -13.5), N], "spacing": 4.6,
		"tiles": ["minigame", "portal", "minigame", "chance", "minigame"]},
]
const FILL_PATTERN := ["minigame", "plain", "minigame", "chance"]   ## tiles 가 모자랄 때
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
var _blocked: Array = []      ## 장식을 놓지 않을 자리 [Vector2 중심, 반지름]
var _spinners: Array = []     ## 빙글빙글 도는 찬스 카드 {node, base_y, phase}
var _portal_fx: Array = []    ## 포탈 고리 {node, mat, light, phase}
var _jellies: Array = []      ## 해파리 {node, base, phase}
var trophy_tile := -1         ## 트로피가 떠 있는 칸 (-1 = 없음)
var _trophy_node: Node3D
var _meshes := {}
var _time := 0.0


func _ready() -> void:
	_rng.seed = 7
	_build_spaces()
	_environment()
	_floor()
	_board_rim()
	_tiles()
	_connectors()
	_tile_props()
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
	for r in ROUTES:
		var kinds: Array = r.get("tiles", [])
		var k := 0
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
				kind = kinds[k] if k < kinds.size() else FILL_PATTERN[k % FILL_PATTERN.size()]
				k += 1
			elif j == n and r.has("end"):
				kind = r["end"]
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
			sp["kind"] = "junction" if sp["links"].size() > 2 else "plain"
		if sp["kind"] != "start" and sp["links"].size() > 2:
			sp["kind"] = "junction"
			sp["yaw"] = 0.0
		var top_h: float = PLAZA * 0.0 + (0.5 if sp["kind"] == "start" else TILE_H)
		sp["pos"] = (sp["base"] as Vector3) + Vector3(0, top_h, 0)
	# 포탈은 나온 순서대로 둘씩 짝 (1번↔2번, 3번↔4번 …)
	var portals := spaces_of_kind("portal")
	for i in range(0, portals.size() - 1, 2):
		spaces[portals[i]]["partner"] = portals[i + 1]
		spaces[portals[i + 1]]["partner"] = portals[i]


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


func _mi(mesh: Mesh, mat: Material, pos: Vector3, basis_: Basis = Basis(), parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis_, pos)
	(parent if parent else self).add_child(mi)
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
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SkyShader
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.6, 0.6)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.88
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.3, 0.33)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_angular_distance = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# 그림자 쪽을 살짝 밝혀 주는 물빛 반사광
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.28
	fill.light_color = Color(0.45, 0.85, 0.85)
	add_child(fill)


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
	var lacquer := _mat(Color(0.04, 0.2, 0.26), 0.22)
	var gold := _mat(Color(0.95, 0.76, 0.34), 0.25, 0.85)
	var t := 1.2
	for side in [[Vector3(0, 0.2, -HALF_D - t / 2), Vector3(HALF_W * 2 + t * 2, 1.6, t)],
			[Vector3(0, 0.2, HALF_D + t / 2), Vector3(HALF_W * 2 + t * 2, 1.6, t)],
			[Vector3(-HALF_W - t / 2, 0.2, 0), Vector3(t, 1.6, HALF_D * 2)],
			[Vector3(HALF_W + t / 2, 0.2, 0), Vector3(t, 1.6, HALF_D * 2)]]:
		_mi(_rbox(side[1], 0.18), lacquer, side[0])
		var inlay: Vector3 = side[1]
		inlay = Vector3(maxf(inlay.x - 0.6, 0.15) if inlay.x > 2 else 0.15, 0.05, maxf(inlay.z - 0.6, 0.15) if inlay.z > 2 else 0.15)
		_mi(_box(inlay), gold, (side[0] as Vector3) + Vector3(0, 0.81, 0))
	# 모서리 장식 구슬
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var sp := SphereMesh.new()
			sp.radius = 0.55
			sp.height = 1.1
			_mi(sp, gold, Vector3(cx * (HALF_W + t / 2), 1.3, cz * (HALF_D + t / 2)))
	# 판 아래 받침
	_mi(_box(Vector3(HALF_W * 2 + t * 2, 2.0, HALF_D * 2 + t * 2)), lacquer, Vector3(0, -8.0, 0))


# ── 칸 ───────────────────────────────────────────────────────
func _tile_top_mat(kind: String) -> ShaderMaterial:
	var key := "tile_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	if kind == "portal":
		m.shader = PortalShader
		m.set_shader_parameter("border_tex", BORDER_TEX)
		_mats[key] = m
		return m
	m.shader = TileShader
	m.set_shader_parameter("tile_color", TILE_COLORS[kind])
	m.set_shader_parameter("ink_color", INK_COLORS[kind])
	m.set_shader_parameter("icon_tex", ICONS[kind])
	m.set_shader_parameter("border_tex", BORDER_TEX)
	m.set_shader_parameter("icon_scale", 0.8 if kind == "start" else 0.62)
	_mats[key] = m
	return m


## 둥근 상자 (같은 크기는 한 번만 만들어 씀)
func _rbox(size: Vector3, r: float) -> ArrayMesh:
	var key := "rb_%s_%.2f" % [size, r]
	if not _meshes.has(key):
		_meshes[key] = MeshKit.rounded_box(size, r, false, 3)
	return _meshes[key]


func _tiles() -> void:
	var foot_m := _mat(Color(0.76, 0.72, 0.62), 0.55)
	var gold := _mat(Color(0.95, 0.76, 0.34), 0.25, 0.85)
	var stud := SphereMesh.new()
	stud.radius = 0.08
	stud.height = 0.12
	stud.radial_segments = 10
	stud.rings = 5
	for sp in spaces:
		var base: Vector3 = sp["base"]
		var kind: String = sp["kind"]
		var b := Basis(Vector3.UP, sp["yaw"])
		if kind == "start":
			_mi(_rbox(Vector3(PLAZA, 0.5, PLAZA), 0.22), _mat(Color(0.5, 0.6, 0.58), 0.35), base + Vector3(0, 0.25, 0), b)
			_mi(_rbox(Vector3(PLAZA + 0.6, 0.2, PLAZA + 0.6), 0.08), foot_m, base + Vector3(0, 0.1, 0), b)
			var top := PlaneMesh.new()
			top.size = Vector2(PLAZA - 0.5, PLAZA - 0.5)
			_mi(top, _tile_top_mat("start"), base + Vector3(0, 0.505, 0), b)
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					_mi(stud, gold, base + b * Vector3(cx * (PLAZA * 0.5 + 0.15), 0.21, cz * (PLAZA * 0.5 + 0.15)))
			continue
		var size := TILE + (0.2 if kind == "junction" else 0.0)
		var body_c: Color = Color(0.93, 0.93, 0.88) if kind == "junction" else (TILE_COLORS[kind] as Color).darkened(0.2)
		# 유약 바른 도자기 같은 칸 몸통 + 크림색 받침 + 금 장식
		sp["body_mi"] = _mi(_rbox(Vector3(size, TILE_H, size), 0.15), _mat(body_c, 0.25), base + Vector3(0, TILE_H * 0.5, 0), b)
		_mi(_rbox(Vector3(size + 0.36, 0.16, size + 0.36), 0.07), foot_m, base + Vector3(0, 0.08, 0), b)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				_mi(stud, gold, base + b * Vector3(cx * (size * 0.5 + 0.1), 0.17, cz * (size * 0.5 + 0.1)))
		var plane := PlaneMesh.new()
		plane.size = Vector2(size - 0.3, size - 0.3)
		# 윗면은 칸과 같은 방향 (그림은 셰이더가 늘 똑바로 세워 줌)
		sp["top_mi"] = _mi(plane, _tile_top_mat(kind), base + Vector3(0, TILE_H + 0.004, 0), b)
		# 협곡 위 칸은 돌기둥이 받침
		if _in_chasm(base.x, base.z):
			var depth := base.y - natural_height(base.x, base.z) + 0.5
			_mi(_cyl(0.85, 1.05, depth, 16), _rock_mat(0), base - Vector3(0, depth * 0.5, 0))
			_mi(_cyl(1.25, 0.9, 0.35, 16), _rock_mat(1), base + Vector3(0, -0.15, 0))


# ── 길 (돌길 / 계단 / 다리 / 징검다리) ────────────────────────
func _connectors() -> void:
	var cobble := _mat(Color(0.7, 0.66, 0.55), 0.85)
	var step_m := _mat(Color(0.74, 0.71, 0.62), 0.6)
	var pebble_cols := [Color(0.82, 0.78, 0.7), Color(0.9, 0.7, 0.64), Color(0.62, 0.8, 0.78), Color(0.74, 0.68, 0.84)]
	var pebble := SphereMesh.new()
	pebble.radius = 0.13
	pebble.height = 0.12
	pebble.radial_segments = 12
	pebble.rings = 6
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
					_mi(_rbox(Vector3(1.6, hgt, glen / n + 0.02), 0.05), step_m, Vector3(pos.x, low + hgt * 0.5, pos.z), bas)
				continue
			# 평범한 자갈길
			var y := (a.y + b.y) * 0.5 + 0.08
			_mi(_rbox(Vector3(1.2, 0.14, glen + 0.1), 0.06), cobble, Vector3(mid.x, y, mid.z), bas)
			# 길 양옆 동글동글 조약돌
			for s in int(glen / 0.42):
				var f := (float(s) + 0.5) / int(glen / 0.42)
				var pp := p0.lerp(p1, f)
				for side in [-0.7, 0.7]:
					var off: Vector3 = bas.x * (side + _rng.randf_range(-0.04, 0.04))
					var pm := _mat(pebble_cols[_rng.randi() % pebble_cols.size()], 0.35)
					var mi := _mi(pebble, pm, Vector3(pp.x + off.x, y + 0.04, pp.z + off.z))
					mi.scale = Vector3.ONE * _rng.randf_range(0.8, 1.15)


func _bridge(p0: Vector3, p1: Vector3, bas: Basis, glen: float, wood: Material, rope: Material) -> void:
	var n := int(glen / 0.42)
	for s in n:
		var f := (float(s) + 0.5) / n
		var pos := p0.lerp(p1, f)
		var sag := sin(f * PI) * -0.25
		_mi(_box(Vector3(1.7, 0.1, 0.34)), wood, Vector3(pos.x, pos.y + TILE_H - 0.1 + sag, pos.z), bas.rotated(Vector3.UP, 0.0))
	for side in [-0.9, 0.9]:
		var off: Vector3 = bas.x * side
		for end in [p0, p1]:
			_mi(_cyl(0.07, 0.08, 1.4, 8), wood, end + off + Vector3(0, TILE_H + 0.3, 0))
		var mid: Vector3 = (p0 + p1) * 0.5 + off + Vector3(0, TILE_H + 0.7, 0)
		_mi(_box(Vector3(0.05, 0.05, glen)), rope, mid, bas)


# ── 볼거리 ───────────────────────────────────────────────────
func _landmarks() -> void:
	var stone := _mat(Color(0.9, 0.88, 0.8), 0.45)
	var moss := _mat(Color(0.36, 0.6, 0.38), 0.9)
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
	var rock := _rock_mat(2)
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
	for bl in _blocked:
		if Vector2(x, z).distance_to(bl[0]) < float(bl[1]) + r:
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
	var mi := _mi(mesh, _rock_mat(_rng.randi() % 3), p)
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


func _rock_mat(k: int) -> ShaderMaterial:
	var key := "rock_%d" % k
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = RockShader
		m.set_shader_parameter("rock_color", [Color(0.52, 0.52, 0.48), Color(0.47, 0.5, 0.47), Color(0.56, 0.52, 0.47)][k % 3])
		_mats[key] = m
	return _mats[key]


func _kelp(p: Vector3, h: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = KelpShader
	m.set_shader_parameter("phase", _rng.randf() * TAU)
	m.set_shader_parameter("height", h)
	m.set_shader_parameter("tip_color", Color(0.62, 0.68, 0.22).lerp(Color(0.42, 0.66, 0.3), _rng.randf()))
	_mi(ReefKit.kelp_mesh(_rng, h), m, p, Basis(Vector3.UP, _rng.randf() * TAU))
	# 공기주머니
	var bl := SphereMesh.new()
	bl.radius = 0.09
	bl.height = 0.18
	bl.radial_segments = 8
	bl.rings = 4
	for k in 2:
		_mi(bl, _mat(Color(0.66, 0.6, 0.22), 0.3), p + Vector3(_rng.randf_range(-0.2, 0.2), h * _rng.randf_range(0.2, 0.5), _rng.randf_range(-0.2, 0.2)))


## 뇌산호
func _brain(p: Vector3, c: Color, size: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = BrainShader
	m.set_shader_parameter("color", c)
	var mi := _mi(ReefKit.brain_mesh(_rng), m, p - Vector3(0, 0.05, 0))
	mi.scale = Vector3(size, size, size) * _rng.randf_range(0.5, 0.8)


## 탁자산호 (줄기 위에 넓적한 판)
func _table_coral(p: Vector3, c: Color, size: float) -> void:
	var m := _mat(c, 0.55)
	var h := 0.9 * size
	_mi(_cyl(0.12 * size, 0.2 * size, h, 10), m, p + Vector3(0, h * 0.5, 0))
	for k in 2:
		var r := (1.0 - k * 0.35) * size
		var plate := _cyl(r, r * 0.92, 0.1, 20)
		_mi(plate, m if k == 0 else _mat(c.lightened(0.2), 0.5), p + Vector3(_rng.randf_range(-0.2, 0.2), h + k * 0.35, _rng.randf_range(-0.2, 0.2)),
			Basis(Vector3(1, 0, 0), _rng.randf_range(-0.12, 0.12)))


## 부채산호 (그물 무늬 판, 양면)
func _fan_coral(p: Vector3, c: Color, size: float) -> void:
	var key := "fan_" + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = FAN_TEX
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.6
		m.emission_enabled = true
		m.emission = c * 0.15
		_mats[key] = m
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0) * size
	var mi := _mi(q, _mats[key], p + Vector3(0, size * 0.95, 0), Basis(Vector3.UP, _rng.randf() * TAU))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 말미잘
func _anemone(p: Vector3, c: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = AnemoneShader
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("tip_color", c.lightened(0.55))
	m.set_shader_parameter("phase", _rng.randf() * TAU)
	var mi := _mi(ReefKit.anemone_mesh(_rng), m, p)
	mi.scale = Vector3.ONE * _rng.randf_range(0.9, 1.4)


## 항아리 (옛날 배에서 떨어진)
func _amphora(p: Vector3, tipped: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := [Vector2(0.0, 0.0), Vector2(0.18, 0.02), Vector2(0.34, 0.25), Vector2(0.38, 0.5), Vector2(0.3, 0.8),
		Vector2(0.13, 0.98), Vector2(0.12, 1.15), Vector2(0.19, 1.22)]
	var n := 16
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for j in n:
			var t0 := TAU * j / n
			var t1 := TAU * (j + 1) / n
			var v := [Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x), Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x),
				Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x), Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)]
			var out := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = v[tri[0]]
				var B: Vector3 = v[tri[1]]
				var C: Vector3 = v[tri[2]]
				if (B - A).cross(C - A).dot(out) > 0.0:
					var tmp := B
					B = C
					C = tmp
				st.add_vertex(A)
				st.add_vertex(B)
				st.add_vertex(C)
	st.index()
	st.generate_normals()
	var b := Basis(Vector3.UP, _rng.randf() * TAU)
	if tipped:
		b = b * Basis(Vector3(0, 0, 1), PI / 2 - 0.15)
	var mi := _mi(st.commit(), _mat(Color(0.78, 0.45, 0.3), 0.7), p + (Vector3(0, 0.35, 0) if tipped else Vector3.ZERO), b)
	mi.scale = Vector3.ONE * 1.3


## 가라앉은 보물상자 (반짝반짝 금화)
func _treasure(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _rng.randf_range(-0.6, 0.6)
	add_child(root)
	var wood := _mat(Color(0.45, 0.27, 0.15), 0.7)
	var gold := _mat(Color(1.0, 0.8, 0.3), 0.2, 0.9)
	_mi(_rbox(Vector3(1.6, 0.9, 1.0), 0.06), wood, Vector3(0, 0.45, 0), Basis(), root)
	for x in [-0.6, 0.0, 0.6]:
		_mi(_box(Vector3(0.12, 0.94, 1.04)), gold, Vector3(x, 0.45, 0), Basis(), root)
	# 열린 뚜껑
	var lid := _cyl(0.5, 0.5, 1.6, 16)
	var lid_mi := _mi(lid, wood, Vector3(0, 1.05, -0.55), Basis(Vector3(0, 0, 1), PI / 2), root)
	lid_mi.scale = Vector3(1, 1, 0.55)
	# 금화 무더기
	var coin := _cyl(0.13, 0.13, 0.03, 12)
	for k in 26:
		var a := _rng.randf() * TAU
		var r := _rng.randf() * 0.6
		var cp := Vector3(cos(a) * r * 0.9, 0.92 + _rng.randf() * 0.15, sin(a) * r * 0.5)
		if k > 16:
			cp = Vector3(_rng.randf_range(-1.4, 1.4), 0.03, _rng.randf_range(0.5, 1.3))
		_mi(coin, gold, cp, Basis(Vector3(1, 0, 0), _rng.randf_range(-0.5, 0.5)), root)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.82, 0.4)
	glow.light_energy = 1.2
	glow.omni_range = 3.5
	glow.position = Vector3(0, 1.3, 0.2)
	root.add_child(glow)
	_blocked.append([Vector2(p.x, p.z), 2.0])


## 여러 개를 한 번에 그리기 (MultiMesh)
func _multi(mesh: Mesh, mat: Material, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if colors.size() > 0:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


## 해초밭 (덤불 수백 개)
func _seagrass() -> void:
	var meshes := [ReefKit.grass_clump_mesh(_rng, 6, 0.8), ReefKit.grass_clump_mesh(_rng, 5, 1.1), ReefKit.grass_clump_mesh(_rng, 8, 0.6)]
	var m := ShaderMaterial.new()
	m.shader = SeagrassShader
	var lists := [[], [], []]
	for patch in 22:
		var cx := _rng.randf_range(-HALF_W + 3, HALF_W - 3)
		var cz := _rng.randf_range(-HALF_D + 3, HALF_D - 3)
		var rad := _rng.randf_range(1.5, 3.2)
		for k in 55:
			var x := cx + _rng.randfn(0.0, rad * 0.5)
			var z := cz + _rng.randfn(0.0, rad * 0.5)
			if not _free_spot(x, z, 0.1):
				continue
			var y := ground_height(x, z)
			if y < -1.0:
				continue
			var sc := _rng.randf_range(0.7, 1.3)
			var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, y - 0.03, z))
			lists[_rng.randi() % 3].append(t)
	for i in 3:
		if lists[i].size() > 0:
			_multi(meshes[i], m, lists[i])


## 바닥에 흩어진 불가사리·조개·자갈
func _scatter() -> void:
	var star_cols := [Color(1.0, 0.5, 0.25), Color(1.0, 0.42, 0.55), Color(0.62, 0.42, 0.95), Color(1.0, 0.78, 0.3)]
	var shell_cols := [Color(0.99, 0.92, 0.82), Color(1.0, 0.76, 0.66), Color(0.98, 0.7, 0.78)]
	var pebble_cols := [Color(0.72, 0.7, 0.64), Color(0.86, 0.83, 0.75), Color(0.6, 0.62, 0.6), Color(0.9, 0.78, 0.72)]
	var vm := StandardMaterial3D.new()
	vm.vertex_color_use_as_albedo = true
	vm.roughness = 0.5
	var sets := {"star": [[], []], "shell": [[], []], "pebble": [[], []]}
	var want := {"star": 34, "shell": 40, "pebble": 420}
	for kind in want:
		var n := 0
		var tries := 0
		while n < int(want[kind]) and tries < int(want[kind]) * 8:
			tries += 1
			var x := _rng.randf_range(-HALF_W + 1.5, HALF_W - 1.5)
			var z := _rng.randf_range(-HALF_D + 1.5, HALF_D - 1.5)
			if not _free_spot(x, z, 0.1):
				continue
			var y := ground_height(x, z)
			var sc := 0.0
			var col := Color.WHITE
			var b := Basis(Vector3.UP, _rng.randf() * TAU)
			match kind:
				"star":
					sc = _rng.randf_range(0.22, 0.36)
					col = star_cols[_rng.randi() % star_cols.size()]
				"shell":
					sc = _rng.randf_range(0.18, 0.3)
					col = shell_cols[_rng.randi() % shell_cols.size()]
				_:
					sc = _rng.randf_range(0.06, 0.16)
					col = pebble_cols[_rng.randi() % pebble_cols.size()]
					b = b.scaled(Vector3(1.0, 0.55, 1.0))
			sets[kind][0].append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(x, y + 0.01, z)))
			sets[kind][1].append(col)
			n += 1
	var pm := SphereMesh.new()
	pm.radius = 1.0
	pm.height = 2.0
	pm.radial_segments = 8
	pm.rings = 4
	_multi(ReefKit.starfish_mesh(), vm, sets["star"][0], sets["star"][1])
	_multi(ReefKit.shell_mesh(), vm, sets["shell"][0], sets["shell"][1])
	_multi(pm, vm, sets["pebble"][0], sets["pebble"][1])


## 물고기 떼 (셰이더가 헤엄치게 함)
func _fish_school(center: Vector3, radius: float, count: int, speed: float, length: float, col_a: Color, col_b: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = ReefKit.fish_mesh(length)
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(_rng.randfn(0.0, 0.35), _rng.randfn(0.0, 0.9), _rng.randfn(0.0, 0.6), _rng.randf()))
	var m := ShaderMaterial.new()
	m.shader = FishShader
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("color_a", col_a)
	m.set_shader_parameter("color_b", col_b)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## 해파리 (둥실둥실)
func _jelly(p: Vector3, c: Color) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.8
	m.roughness = 0.2
	var dome := SphereMesh.new()
	dome.radius = 0.55
	dome.height = 0.7
	dome.is_hemisphere = true
	dome.radial_segments = 20
	dome.rings = 8
	var bell := MeshInstance3D.new()
	bell.mesh = dome
	bell.material_override = m
	bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bell)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(c.lightened(0.3), 0.45)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.emission_enabled = true
	tm.emission = c.lightened(0.3)
	tm.emission_energy_multiplier = 0.6
	for k in 7:
		var a := TAU * k / 7.0
		var ln := _rng.randf_range(0.9, 1.6)
		var t := MeshInstance3D.new()
		t.mesh = _cyl(0.025, 0.012, ln, 5)
		t.material_override = tm
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.position = Vector3(cos(a) * 0.32, -ln * 0.5, sin(a) * 0.32)
		root.add_child(t)
	_jellies.append({"node": root, "base": p, "phase": _rng.randf() * TAU})


## 빈자리 찾기 (가까운 곳부터)
func _find_free(x: float, z: float, r: float, spread: float = 3.0) -> Vector3:
	for t in 60:
		var xx := x + (_rng.randfn(0.0, spread) if t > 0 else 0.0)
		var zz := z + (_rng.randfn(0.0, spread) if t > 0 else 0.0)
		if _free_spot(xx, zz, r):
			return Vector3(xx, ground_height(xx, zz), zz)
	return Vector3(INF, 0, 0)


func _decor() -> void:
	var coral_cols := [Color(1.0, 0.4, 0.38), Color(1.0, 0.6, 0.28), Color(0.76, 0.42, 0.98), Color(1.0, 0.38, 0.64), Color(1.0, 0.84, 0.38),
		Color(0.35, 0.85, 0.8)]
	# 보물상자 · 항아리 (먼저 자리 잡기)
	var tp := _find_free(22.0, 3.0, 1.5)
	if tp.x != INF:
		_treasure(tp)
	for at in [Vector2(-6.0, 5.5), Vector2(5.5, -5.5), Vector2(-21.0, -2.0)]:
		var ap := _find_free(at.x, at.y, 0.6, 1.5)
		if ap.x != INF:
			_amphora(ap, _rng.randf() < 0.5)
			_blocked.append([Vector2(ap.x, ap.z), 0.9])
	# 산호 언덕 위·주변
	var zones := [[PLATEAU_C, 6.0, 20], [Vector2(-22, -18), 4.0, 8], [Vector2(20, 17), 5.0, 10], [Vector2(-6, 18), 4.0, 7],
		[Vector2(22, 4), 3.0, 5], [Vector2(-4, -20), 4.0, 7], [Vector2(6, 4), 3.0, 4], [Vector2(-7, -5), 3.0, 4],
		[Vector2(8, -18), 3.5, 6], [Vector2(-24, 6), 3.0, 5], [Vector2(24, -10), 3.0, 5]]
	for z in zones:
		var c: Vector2 = z[0]
		for k in z[2]:
			for t in 20:
				var x: float = c.x + _rng.randfn(0.0, z[1])
				var zz: float = c.y + _rng.randfn(0.0, z[1])
				if _free_spot(x, zz, 0.8):
					var p := Vector3(x, ground_height(x, zz), zz)
					var col: Color = coral_cols[_rng.randi() % coral_cols.size()]
					var roll := _rng.randf()
					if roll < 0.32:
						_coral(p, col, _rng.randf_range(0.8, 1.4))
					elif roll < 0.47:
						_brain(p, col.lerp(Color(0.95, 0.85, 0.6), 0.4), _rng.randf_range(0.9, 1.4))
					elif roll < 0.6:
						_table_coral(p, col, _rng.randf_range(0.7, 1.1))
					elif roll < 0.74:
						_fan_coral(p, col, _rng.randf_range(0.8, 1.3))
					elif roll < 0.87:
						_anemone(p, col)
					else:
						_sponge(p, col)
					_blocked.append([Vector2(x, zz), 0.6])
					break
	# 바위
	for k in 40:
		for t in 20:
			var x := _rng.randf_range(-HALF_W + 2, HALF_W - 2)
			var zz := _rng.randf_range(-HALF_D + 2, HALF_D - 2)
			var r := _rng.randf_range(0.5, 1.6) if _rng.randf() < 0.85 else _rng.randf_range(1.8, 2.8)
			if _free_spot(x, zz, r):
				_rock(Vector3(x, ground_height(x, zz) - r * 0.25, zz), r)
				_blocked.append([Vector2(x, zz), r * 0.8])
				break
	# 다시마 숲 (남서쪽) + 판 가장자리 (가운데 길 쪽은 비워서 카메라를 가리지 않게)
	for k in 46:
		for t in 10:
			var x := -21.0 + _rng.randfn(0.0, 3.5)
			var zz := 15.0 + _rng.randfn(0.0, 4.0)
			if _free_spot(x, zz, 0.4):
				_kelp(Vector3(x, ground_height(x, zz), zz), _rng.randf_range(4.0, 7.5))
				break
	for k in 40:
		for t in 10:
			var x := _rng.randf_range(-HALF_W + 1.5, HALF_W - 1.5)
			var zz := _rng.randf_range(-HALF_D + 1.5, HALF_D - 1.5)
			if absf(x) < HALF_W - 5.0 and absf(zz) < HALF_D - 4.0:
				continue
			if _free_spot(x, zz, 0.4):
				_kelp(Vector3(x, ground_height(x, zz), zz), _rng.randf_range(3.5, 6.5))
				break
	_seagrass()
	_scatter()
	# 물고기 떼
	_fish_school(Vector3(-15.5, 7.5, -12.0), 6.5, 24, 0.22, 0.45, Color(1.0, 0.82, 0.25), Color(0.3, 0.62, 1.0))
	_fish_school(Vector3(19.0, 3.2, 13.0), 4.5, 16, -0.3, 0.42, Color(1.0, 0.55, 0.2), Color(0.98, 0.96, 0.92))
	_fish_school(Vector3(-20.0, 3.8, 14.0), 4.5, 18, 0.26, 0.4, Color(0.7, 0.85, 0.95), Color(0.35, 0.85, 0.78))
	_fish_school(Vector3(0.0, 9.0, 0.0), 19.0, 32, -0.07, 0.6, Color(0.98, 0.5, 0.7), Color(0.6, 0.5, 0.98))
	# 해파리
	for jp in [Vector3(-24, 6.5, -10), Vector3(24, 7.5, -4), Vector3(-10, 8.5, 21), Vector3(14, 6.0, 20), Vector3(4, 9.0, -21), Vector3(-25, 7.0, 20)]:
		_jelly(jp, [Color(1.0, 0.55, 0.8), Color(0.65, 0.6, 1.0), Color(0.5, 0.95, 0.95)][_rng.randi() % 3])


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
		m.set_shader_parameter("strength", _rng.randf_range(0.025, 0.06))
		var p := Vector3(_rng.randf_range(-HALF_W, HALF_W), 14.0, _rng.randf_range(-HALF_D, HALF_D))
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3(0, 0, 1), deg_to_rad(18))
		_mi(q, m, p, b)


# ── 칸 소품 (포탈 고리 · 상점 노점 · 찬스 카드) ───────────────
func _unshaded(c: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _tile_props() -> void:
	for i in spaces.size():
		match String(spaces[i]["kind"]):
			"portal":
				_portal_gate(i)
			"shop":
				_shop_stall(i)
			"chance":
				_chance_card(i)


## 포탈: 칸 위에 서 있는 빛나는 고리 (말이 그 사이를 지나감) + 반짝이 + 보라 불빛
func _portal_gate(i: int) -> void:
	var sp: Dictionary = spaces[i]
	var top: Vector3 = sp["pos"]
	var yaw := _path_yaw(i)
	var ring_mat := _unshaded(Color(0.72, 0.48, 1.0), 2.2)
	var t := TorusMesh.new()
	t.inner_radius = 1.04
	t.outer_radius = 1.26
	t.rings = 40
	t.ring_segments = 12
	var pivot := Node3D.new()
	pivot.position = top + Vector3(0, 1.3, 0)
	pivot.basis = Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI / 2)
	add_child(pivot)
	var ring := MeshInstance3D.new()
	ring.mesh = t
	ring.material_override = ring_mat
	pivot.add_child(ring)
	# 고리 바깥 돌테
	var t2 := TorusMesh.new()
	t2.inner_radius = 1.24
	t2.outer_radius = 1.4
	t2.rings = 40
	t2.ring_segments = 8
	var frame := MeshInstance3D.new()
	frame.mesh = t2
	frame.material_override = _mat(Color(0.36, 0.3, 0.46), 0.6, 0.2)
	pivot.add_child(frame)
	# 받침돌 두 개
	var side := Basis(Vector3.UP, yaw).x
	for sgn in [-1.0, 1.0]:
		_mi(_box(Vector3(0.42, 0.34, 0.5)), _mat(Color(0.4, 0.34, 0.5), 0.7), top + side * (1.18 * sgn) + Vector3(0, 0.12, 0), Basis(Vector3.UP, yaw))
	# 고리 둘레 반짝이
	var sparks := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _unshaded(Color(0.92, 0.8, 1.0), 3.0)
	sparks.mesh = sm
	sparks.amount = 36
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3(0, 1, 0)   # 고리 축 (피벗 기준)
	sparks.emission_ring_radius = 1.15
	sparks.emission_ring_inner_radius = 0.9
	sparks.emission_ring_height = 0.1
	sparks.direction = Vector3(0, 0, 0)
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 0.05
	sparks.initial_velocity_max = 0.3
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 1.2
	pivot.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.45, 1.0)
	light.light_energy = 1.6
	light.omni_range = 5.5
	light.position = top + Vector3(0, 1.0, 0)
	add_child(light)
	_portal_fx.append({"node": pivot, "mat": ring_mat, "light": light, "phase": float(i)})
	_blocked.append([Vector2(top.x, top.z), 2.0])


## 상점: 칸 옆에 줄무늬 차양을 친 작은 노점
func _shop_stall(i: int) -> void:
	var sp: Dictionary = spaces[i]
	var base: Vector3 = sp["base"]
	var yaw := _path_yaw(i)
	var side := Basis(Vector3.UP, yaw).x
	var at := Vector3.ZERO
	var dir := 0.0
	for sgn in [1.0, -1.0]:
		var c: Vector3 = base + side * (2.9 * sgn)
		if _stall_ok(c, i):
			at = c
			dir = sgn
			break
	if dir == 0.0:
		at = base + side * 2.9
		dir = 1.0
	at.y = base.y
	# 노점 정면(+Z)이 칸을 보게
	var face := -side * dir
	var b := Basis(Vector3.UP, atan2(face.x, face.z))
	var root := Node3D.new()
	root.transform = Transform3D(b, at)
	add_child(root)
	var wood := _mat(Color(0.55, 0.36, 0.22), 0.75)
	var light_wood := _mat(Color(0.78, 0.6, 0.4), 0.6)
	var pink := _mat(Color(0.94, 0.43, 0.56), 0.55)
	var cream := _mat(Color(0.99, 0.95, 0.88), 0.55)
	# 받침 + 계산대
	_mi(_box(Vector3(2.3, 0.9, 1.7)), _mat(Color(0.6, 0.6, 0.56), 0.9), Vector3(0, -0.37, 0), Basis(), root)
	_mi(_box(Vector3(1.9, 0.9, 0.7)), wood, Vector3(0, 0.53, 0.35), Basis(), root)
	_mi(_box(Vector3(2.05, 0.08, 0.86)), light_wood, Vector3(0, 1.02, 0.35), Basis(), root)
	_mi(_box(Vector3(1.6, 0.12, 0.02)), pink, Vector3(0, 0.75, 0.71), Basis(), root)
	# 기둥
	for x in [-0.9, 0.9]:
		_mi(_cyl(0.06, 0.07, 2.5, 8), wood, Vector3(x, 1.3, -0.45), Basis(), root)
		_mi(_cyl(0.06, 0.07, 2.15, 8), wood, Vector3(x, 1.12, 0.66), Basis(), root)
	# 줄무늬 차양 (앞으로 기울어짐)
	var tilt := Basis(Vector3(1, 0, 0), 0.32)
	for k in 7:
		var x := -1.05 + 0.35 * k
		_mi(_box(Vector3(0.35, 0.05, 1.5)), pink if k % 2 == 0 else cream, Vector3(x + 0.175, 2.35, 0.12), tilt, root)
	# 차양 끝 물결 장식
	for k in 7:
		var x := -0.875 + 0.35 * k
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.2
		sph.radial_segments = 10
		sph.rings = 5
		_mi(sph, pink if k % 2 == 0 else cream, Vector3(x, 2.05, 0.86), Basis(), root)
	# 간판 (쇼핑백 그림)
	_mi(_box(Vector3(0.9, 0.9, 0.08)), pink, Vector3(0, 2.95, -0.2), Basis(), root)
	var q := QuadMesh.new()
	q.size = Vector2(0.72, 0.72)
	var icon_m := StandardMaterial3D.new()
	icon_m.albedo_texture = ICONS["shop"]
	icon_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	icon_m.alpha_scissor_threshold = 0.4
	icon_m.emission_enabled = true
	icon_m.emission = Color(0.4, 0.35, 0.35)
	_mi(q, icon_m, Vector3(0, 2.95, -0.155), Basis(), root)
	# 물건: 진주, 작은 보물상자, 병
	var pearl := SphereMesh.new()
	pearl.radius = 0.12
	pearl.height = 0.24
	for k in 3:
		_mi(pearl, _mat(Color(0.95, 0.93, 1.0).lerp(Color(1.0, 0.75, 0.85), k * 0.4), 0.15, 0.3), Vector3(-0.65 + k * 0.22, 1.18, 0.35), Basis(), root)
	_mi(_box(Vector3(0.42, 0.28, 0.3)), _mat(Color(0.6, 0.38, 0.18), 0.6), Vector3(0.25, 1.2, 0.3), Basis(), root)
	_mi(_box(Vector3(0.44, 0.06, 0.32)), _mat(Color(0.95, 0.75, 0.25), 0.3, 0.6), Vector3(0.25, 1.36, 0.3), Basis(), root)
	_mi(_cyl(0.08, 0.1, 0.36, 10), _mat(Color(0.35, 0.8, 0.7), 0.1), Vector3(0.7, 1.24, 0.38), Basis(), root)
	# 등불
	var lamp := SphereMesh.new()
	lamp.radius = 0.13
	lamp.height = 0.26
	_mi(lamp, _unshaded(Color(1.0, 0.8, 0.45), 2.5), Vector3(0.7, 1.95, 0.75), Basis(), root)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.5)
	l.light_energy = 1.0
	l.omni_range = 4.0
	l.position = Vector3(0.7, 1.9, 0.9)
	root.add_child(l)
	_blocked.append([Vector2(at.x, at.z), 1.8])


func _stall_ok(c: Vector3, own: int) -> bool:
	if _in_chasm(c.x, c.z) or absf(c.x) > HALF_W - 1.5 or absf(c.z) > HALF_D - 1.5:
		return false
	if absf(natural_height(c.x, c.z) - (spaces[own]["base"] as Vector3).y) > 0.9:
		return false
	for j in spaces.size():
		if j == own:
			continue
		var b: Vector3 = spaces[j]["base"]
		var r := PLAZA * 0.5 + 1.0 if spaces[j]["kind"] == "start" else 2.4
		if Vector2(c.x - b.x, c.z - b.z).length() < r:
			return false
	for i in spaces.size():
		for j in spaces[i]["links"]:
			var a: Vector3 = spaces[i]["base"]
			var b: Vector3 = spaces[j]["base"]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := Vector2(c.x - a.x, c.z - a.z)
			var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if (ap - ab * t).length() < 1.7:
				return false
	return true


## 찬스: 칸 위에 떠서 빙글빙글 도는 ? 카드
func _chance_card(i: int) -> void:
	var top: Vector3 = spaces[i]["pos"]
	var pivot := Node3D.new()
	pivot.position = top + Vector3(0, 2.9, 0)
	add_child(pivot)
	var m := StandardMaterial3D.new()
	m.albedo_texture = CHANCE_CARD_TEX
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.emission_enabled = true
	m.emission_texture = CHANCE_CARD_TEX
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.45
	m.roughness = 0.35
	for back in [false, true]:
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position = Vector3(0, 0, -0.012 if back else 0.012)
		mi.rotation.y = PI if back else 0.0
		pivot.add_child(mi)
	# 카드 아래 작은 빛
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.35)
	glow.light_energy = 0.8
	glow.omni_range = 3.0
	pivot.add_child(glow)
	_spinners.append({"node": pivot, "base_y": pivot.position.y, "phase": float(i) * 0.7})


## 칸에서 길이 나가는 방향 (yaw)
func _path_yaw(i: int) -> float:
	var sp: Dictionary = spaces[i]
	var links: Array = sp["links"]
	if links.size() >= 2:
		var a: Vector3 = spaces[links[0]]["base"]
		var b: Vector3 = spaces[links[1]]["base"]
		var d := b - a
		return atan2(d.x, d.z)
	return float(sp["yaw"])


func _process(delta: float) -> void:
	_time += delta
	for s in _spinners:
		var n: Node3D = s["node"]
		n.rotation.y += delta * 1.3
		n.position.y = float(s["base_y"]) + sin(_time * 2.0 + float(s["phase"])) * 0.15
	if _trophy_node:
		_trophy_node.rotation.y += delta * 1.2
		var cup := _trophy_node.get_child(0) as Node3D
		cup.position.y = 2.6 + sin(_time * 2.2) * 0.18
	for j in _jellies:
		var jn: Node3D = j["node"]
		var ph: float = j["phase"]
		var pulse := 0.5 + 0.5 * sin(_time * 1.6 + ph)
		jn.position = (j["base"] as Vector3) + Vector3(sin(_time * 0.2 + ph) * 0.8, sin(_time * 0.8 + ph) * 0.6, cos(_time * 0.17 + ph) * 0.8)
		jn.scale = Vector3(1.0 + pulse * 0.12, 1.0 - pulse * 0.1, 1.0 + pulse * 0.12)
	for f in _portal_fx:
		var k := 0.5 + 0.5 * sin(_time * 3.0 + float(f["phase"]))
		(f["mat"] as StandardMaterial3D).emission_energy_multiplier = 1.6 + k * 1.6
		(f["light"] as OmniLight3D).light_energy = 1.2 + k * 0.9


# ── 다른 스크립트가 쓰는 것들 ─────────────────────────────────
## 트로피 칸이 될 수 있는 평범한 칸들 (갈림길·START·포탈·상점 제외)
func regular_tiles() -> Array:
	var out := []
	for i in spaces.size():
		if String(spaces[i]["kind"]) in ["plain", "minigame", "chance"]:
			out.append(i)
	return out


## 칸 모양 바꾸기 (찬스 카드로 생기는 +5 / -5 동전 칸)
func set_tile_look(i: int, kind: String) -> void:
	var sp: Dictionary = spaces[i]
	if not sp.has("top_mi"):
		return
	(sp["top_mi"] as MeshInstance3D).material_override = _tile_top_mat(kind)
	(sp["body_mi"] as MeshInstance3D).material_override = _mat((TILE_COLORS[kind] as Color).darkened(0.2), 0.25)
	var body := sp["body_mi"] as Node3D
	var top := sp["top_mi"] as Node3D
	for n in [body, top]:
		var t := create_tween()
		t.tween_property(n, "scale", Vector3(1.15, 1.6, 1.15), 0.12)
		t.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	bubbles_at(sp["pos"], 14, 0.6, true)


## 트로피를 칸 위에 띄우기 (금빛 기둥이 멀리서도 보임)
func show_trophy(i: int) -> void:
	hide_trophy(false)
	trophy_tile = i
	var top: Vector3 = spaces[i]["pos"]
	var root := Node3D.new()
	root.position = top
	add_child(root)
	var cup := Node3D.new()
	cup.position.y = 2.6
	root.add_child(cup)
	var gold := _mat(Color(1.0, 0.78, 0.25), 0.18, 0.95)
	# 컵 (돌림판 모양)
	var prof := [Vector2(0.0, -0.55), Vector2(0.3, -0.55), Vector2(0.3, -0.45), Vector2(0.08, -0.38), Vector2(0.07, -0.12),
		Vector2(0.18, -0.02), Vector2(0.36, 0.1), Vector2(0.44, 0.35), Vector2(0.46, 0.55), Vector2(0.4, 0.56), Vector2(0.0, 0.5)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for k in prof.size() - 1:
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		for j in n:
			var t0 := TAU * j / n
			var t1 := TAU * (j + 1) / n
			var v := [Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x), Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x),
				Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x), Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)]
			var out := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = v[tri[0]]
				var B: Vector3 = v[tri[1]]
				var C: Vector3 = v[tri[2]]
				if (B - A).cross(C - A).dot(out) > 0.0:
					var tmp := B
					B = C
					C = tmp
				st.add_vertex(A)
				st.add_vertex(B)
				st.add_vertex(C)
	st.index()
	st.generate_normals()
	_mi(st.commit(), gold, Vector3.ZERO, Basis(), cup)
	for sx in [-1.0, 1.0]:
		var h := TorusMesh.new()
		h.inner_radius = 0.1
		h.outer_radius = 0.17
		_mi(h, gold, Vector3(sx * 0.46, 0.28, 0), Basis(Vector3(1, 0, 0), PI / 2), cup)
	# 금빛 기둥 + 불빛 + 반짝이
	var beam_m := StandardMaterial3D.new()
	beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_m.albedo_color = Color(1.0, 0.8, 0.35, 0.16)
	var beam := _mi(_cyl(0.9, 1.1, 16.0, 24), beam_m, Vector3(0, 8.0, 0), Basis(), root)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 2.0
	l.omni_range = 5.0
	l.position = Vector3(0, 2.4, 0)
	root.add_child(l)
	_trophy_node = root
	root.scale = Vector3.ONE * 0.01
	var t := create_tween()
	t.tween_property(root, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	portal_burst(top)


func hide_trophy(burst: bool = true) -> void:
	if _trophy_node:
		if burst:
			portal_burst(_trophy_node.position)
		_trophy_node.queue_free()
		_trophy_node = null
	trophy_tile = -1

func spaces_of_kind(kind: String) -> Array:
	var out := []
	for i in spaces.size():
		if spaces[i]["kind"] == kind:
			out.append(i)
	return out


## 포탈 칸이면 짝 포탈 번호, 아니면 -1
func portal_partner(i: int) -> int:
	return int(spaces[i].get("partner", -1))


## p 에서 가장 가까운 그 종류 칸 번호
func nearest_of_kind(kind: String, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in spaces_of_kind(kind):
		var d := (spaces[i]["pos"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## 포탈 이동할 때 반짝 터지는 효과
func portal_burst(p: Vector3) -> void:
	var c := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _unshaded(Color(0.9, 0.75, 1.0), 3.0)
	c.mesh = sm
	c.amount = 60
	c.lifetime = 1.2
	c.one_shot = true
	c.explosiveness = 0.95
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	c.emission_sphere_radius = 0.6
	c.direction = Vector3.UP
	c.spread = 70.0
	c.gravity = Vector3(0, -1.0, 0)
	c.initial_velocity_min = 2.0
	c.initial_velocity_max = 4.5
	c.scale_amount_min = 0.6
	c.scale_amount_max = 1.6
	c.position = p + Vector3(0, 1.0, 0)
	add_child(c)
	c.emitting = true
	get_tree().create_timer(2.0).timeout.connect(c.queue_free)


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
