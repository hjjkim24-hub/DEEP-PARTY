extends Node3D
## 크라켄의 배: 밤하늘 구름 바다 위를 떠가는 거대한 해적선 (칸 34 개, 칸은 갑판 안쪽에 모여 있고 둘레가 넉넉함).
## board_world.gd 가 섬을 다 만든 뒤 build() 로 만들고, 크라켄이 '크라켄의 배' 카드를 뽑으면
## board_world.enter_ship() 로 섬 대신 이 배와 밤하늘을 보여 줌.
##   배 길이는 x 축 (뱃머리 +x, 고물 -x), 폭은 z 축 (우현 +z 가 카메라 쪽). 좌표는 이 노드 기준 (AT 가 원점).
##   갑판 4 층: 큰 갑판(0) · 앞갑판(FC_Y) · 뒷갑판(QD_Y) · 맨 뒤 선장실 지붕(PP_Y). 층 사이는 가파른 배 계단.
##   칸은 지금은 전부 일반 칸 (배 전용 칸은 나중에). 칸은 모두 갑판 위, 길은 반듯하게:
##     - 양쪽 뱃전을 따라 한 바퀴 (4 층 갑판을 계단으로 오르내림)
##     - 뚫린 짐칸을 가로지르는 널다리 (보물 더미가 내려다보임)

const SailShader := preload("res://shaders/sail.gdshader")
const CloudSeaShader := preload("res://shaders/cloud_sea.gdshader")
const CloudPuffShader := preload("res://shaders/cloud_puff.gdshader")
const SmokeShader := preload("res://shaders/smoke_puff.gdshader")
const NightSkyShader := preload("res://shaders/night_sky.gdshader")
const EMBLEM := preload("res://textures/ship/emblem.png")
const ReefKit := preload("res://scripts/world3d/reef_kit.gd")

const AT := Vector3(0, 40, 320)      ## 배가 놓인 곳 (섬과 멀리 떨어진 하늘)
const BOW := 66.0
const STERN := -63.0
const MID := 14.5                    ## 갑판 반폭 (가운데)
const FC_X := 36.0                   ## 앞갑판이 시작되는 곳
const FC_Y := 4.0
const QD_X := -29.0                  ## 뒷갑판
const QD_Y := 4.5
const PP_X := -49.5                  ## 맨 뒤 선장실 지붕
const PP_Y := 8.5
const HOLD := Rect2(11.5, -4.5, 11.5, 9.0)   ## 뚫린 짐칸 (x, z, 길이, 폭)
const HOLD_DEPTH := 8.0
## 돛대: [x, 갑판 높이, 갑판 위 높이, 밑동 굵기]
const MASTS := [[29.0, 0.0, 50.0, 0.8], [-3.0, 0.0, 60.0, 0.9], [-42.0, QD_Y, 40.0, 0.65]]
const TOP_K := 0.46                  ## 망대 높이 (돛대 높이 비율)
const CLOUD_Y := -62.0
const BRACE := 0.38                  ## 활대를 비스듬히 돌린 각도

## 칸 자리 (종류는 지금 전부 일반 칸). 뱃전 길은 z = ±LANE 의 곧은 줄
const LANE := 7.5
const TILES := {
	"P1": Vector3(-53.0, PP_Y, 5.0), "P2": Vector3(-58.0, PP_Y, 0.0), "P3": Vector3(-53.0, PP_Y, -5.0),
	"Q1": Vector3(-44.5, QD_Y, LANE), "Q2": Vector3(-38.0, QD_Y, LANE), "Q3": Vector3(-31.5, QD_Y, LANE),
	"Q4": Vector3(-44.5, QD_Y, -LANE), "Q5": Vector3(-38.0, QD_Y, -LANE), "Q6": Vector3(-31.5, QD_Y, -LANE),
	"S1": Vector3(-23.5, 0, LANE), "S2": Vector3(-16.69, 0, LANE), "S3": Vector3(-9.88, 0, LANE), "S4": Vector3(-3.06, 0, LANE),
	"S5": Vector3(3.75, 0, LANE), "S6": Vector3(10.56, 0, LANE), "S7": Vector3(17.38, 0, LANE), "S8": Vector3(24.19, 0, LANE),
	"S9": Vector3(31.0, 0, LANE),
	"F1": Vector3(39.5, FC_Y, LANE), "F2": Vector3(45.0, FC_Y, 5.4), "F3": Vector3(48.5, FC_Y, 0.0), "F4": Vector3(45.0, FC_Y, -5.4),
	"F5": Vector3(39.5, FC_Y, -LANE),
	"M1": Vector3(31.0, 0, -LANE), "M2": Vector3(24.19, 0, -LANE), "M3": Vector3(17.38, 0, -LANE), "M4": Vector3(10.56, 0, -LANE),
	"M5": Vector3(3.75, 0, -LANE), "M6": Vector3(-3.06, 0, -LANE), "M7": Vector3(-9.88, 0, -LANE), "M8": Vector3(-16.69, 0, -LANE),
	"M9": Vector3(-23.5, 0, -LANE),
	"H1": Vector3(17.38, 0.4, 2.4), "H2": Vector3(17.38, 0.4, -2.4),
}
## 한 바퀴 길 (앞으로 가는 순서) + 갈래길들 (모두 갑판 위)
const LOOP := ["P2", "P1", "Q1", "Q2", "Q3", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9",
	"F1", "F2", "F3", "F4", "F5", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "Q6", "Q5", "Q4", "P3"]
const BRANCHES := [["S7", "H1", "H2", "M3"]]
const STAIRS := [["Q3", "S1"], ["S9", "F1"], ["F5", "M1"], ["M9", "Q6"], ["Q4", "P3"], ["P1", "Q1"]]
const DROPS := ["S3", "M6", "F2", "P2"]
## 특별한 칸 (나머지는 일반 칸)
const SPECIAL := {"F3": "kraken_chest", "S5": "cannon", "M4": "cannon"}
const CHEST_AT := Vector3(53.6, FC_Y, 0.0)   ## 크라켄의 보물상자 (보물상자 칸 바로 앞, 뱃머리 쪽)
const WHEEL_AT := Vector3(55.6, FC_Y, -5.8)  ## 크라켄의 행운 바퀴 (상자 옆에 세워 둔 커다란 나무 바퀴, 앞이 +z)
const WHEEL_R := 1.8
const WHEEL_H := 2.75                        ## 갑판에서 바퀴 축까지
const WHEEL_SEGS := 10

var w                                ## board_world
var env: Environment
var lights: Array = []               ## 배에 있을 때만 켜는 빛 (달빛)
var first := 0                       ## 배 칸 번호 시작
var drop_tiles: Array = []           ## 떨어질 때 말들이 내려앉을 칸 (서로 멀리)
var ids := {}                        ## 칸 이름 → 칸 번호
var _puffs: Array = []
var _lamps: Array = []
var _swing: Array = []
var _t := 0.0
var _mats := {}
var _ropes: Array = []
var _ropes_thin: Array = []


# ── 배 모양 ─────────────────────────────────────────────────
## 갑판 안쪽 반폭 (뱃전 안쪽까지)
func hb(x: float) -> float:
	if x > 21.0:
		var u := (x - 21.0) / (BOW + 0.5 - 21.0)
		return MID * sqrt(maxf(1.0 - u * u, 0.0))
	if x < -45.0:
		var u2 := (-45.0 - x) / 18.0
		return MID - 3.0 * u2 * u2
	return MID


func deck_y(x: float) -> float:
	if x > FC_X:
		return FC_Y
	if x < PP_X:
		return PP_Y
	if x < QD_X:
		return QD_Y
	return 0.0


## 뱃전 꼭대기 높이 (앞뒤로 갈수록 솟음)
func gunwale(x: float) -> float:
	var g := 1.5
	g = lerpf(g, FC_Y + 1.3, smoothstep(FC_X - 4.5, FC_X + 1.5, x))
	g += smoothstep(BOW - 12.0, BOW, x) * 1.6
	g = lerpf(g, QD_Y + 1.3, smoothstep(QD_X + 3.5, QD_X - 1.5, x))
	g = lerpf(g, PP_Y + 1.3, smoothstep(PP_X + 3.0, PP_X - 1.5, x))
	g += smoothstep(STERN + 12.0, STERN, x) * 1.0
	return g


func keel(x: float) -> float:
	var k := -19.0
	if x > 21.0:
		k += 13.5 * pow((x - 21.0) / (BOW - 21.0), 2.0)
	if x < -39.0:
		k += 3.5 * pow((-39.0 - x) / 27.0, 2.0)
	return k


func hw(x: float) -> float:
	return hb(x) + 0.42


## 단면 t (0 = 뱃전 꼭대기, PI/2 = 용골) 의 점. s = +1 우현 / -1 좌현
func hull_pt(x: float, t: float, s: float) -> Vector3:
	var g := gunwale(x)
	var k := keel(x)
	var y := g - (g - k) * sin(t)
	var z := hw(x) * pow(maxf(cos(t), 0.0), 0.45) * (1.0 + 0.08 * sin(2.0 * t))
	return Vector3(x, y, z * s)


func t_at(x: float, y: float) -> float:
	var g := gunwale(x)
	var k := keel(x)
	return asin(clampf((g - y) / maxf(g - k, 0.01), 0.0, 1.0))


## 망대 윗면 높이
func top_y(mi: int) -> float:
	return float(MASTS[mi][1]) + float(MASTS[mi][2]) * TOP_K


## 칸 자리 (망대 · 흔들다리 칸은 높이를 돛대에서 계산)
func tile_pos(n: String) -> Vector3:
	return TILES[n]


func near_tile(p: Vector3, r: float) -> bool:
	for n in TILES:
		var q := tile_pos(n)
		if absf(q.y - p.y) < 3.0 and Vector2(q.x - p.x, q.z - p.z).length() < r:
			return true
	return false


# ── 재질 ─────────────────────────────────────────────────────
func smat(c: Color, kind: String, plank := -1.0, grain := Vector3(1, 0, 0), moss := 0.04) -> ShaderMaterial:
	var key := "%s_%s_%.2f_%s_%.2f" % [c.to_html(), kind, plank, grain, moss]
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial = (w._smat(c, kind, 0.0, moss) as ShaderMaterial).duplicate()
	m.set_shader_parameter("caustics", 0.0)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("grain", grain)
	if plank >= 0.0:
		m.set_shader_parameter("plank_w", plank)
	_mats[key] = m
	return m


func mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	return w._mat(c, rough, metal)


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func gold() -> StandardMaterial3D:
	return mat(Color(0.86, 0.66, 0.3), 0.3, 0.85)


func iron() -> StandardMaterial3D:
	return mat(Color(0.11, 0.1, 0.09), 0.45, 0.7)


## 밧줄 (나중에 한꺼번에 MultiMesh 로)
func rope(a: Vector3, b: Vector3, thin := false) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := y.cross(Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	var z := x.cross(y)
	(_ropes_thin if thin else _ropes).append(Transform3D(Basis(x, y * l, z), (a + b) * 0.5))


func _mi(mesh: Mesh, m: Material, pos: Vector3, b := Basis(), parent: Node = null) -> MeshInstance3D:
	return w._mi(mesh, m, pos, b, parent if parent else self)


func _rod(a: Vector3, b: Vector3, r: float, m: Material, r2 := -1.0, segs := 10, parent: Node = null) -> void:
	w._rod(a, b, r, m, parent if parent else self, segs, r2)


func _box(size: Vector3, m: Material, pos: Vector3, b := Basis()) -> MeshInstance3D:
	return _mi(w._box(size), m, pos, b)


func _multi(mesh: Mesh, m: Material, xs: Array) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)


# ── 만들기 ───────────────────────────────────────────────────
func build() -> void:
	position = AT
	_environment()
	_hull()
	_decks()
	_hold()
	_spaces()
	_tiles()
	_stairs_and_rails()
	_masts()
	_bow()
	_stern()
	_deck_props()
	_kraken_arms()
	_kraken_things()
	_kraken_chest()
	_fortune_wheel()
	_swivel_cannons()
	_lights_decor()
	_flush_ropes()
	_sky_clouds()
	visible = false


func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = NightSkyShader
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.4, 0.66)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.09, 0.2)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.08
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-46, -38, 0)
	moon.light_color = Color(0.66, 0.74, 1.0)
	moon.light_energy = 1.05
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_max_distance = 200.0
	moon.visible = false
	w.add_child(moon)
	lights.append(moon)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 150, 0)
	rim.light_color = Color(0.45, 0.5, 0.95)
	rim.light_energy = 0.45
	rim.visible = false
	w.add_child(rim)
	lights.append(rim)


## 선체: 검붉은 칠 윗단 · 나무 몸통 · 구리판 밑바닥 + 금테 · 굵은 띠널
func _hull() -> void:
	var paint := smat(Color(0.34, 0.07, 0.06), "wood", 0.32)
	var wood := smat(Color(0.25, 0.16, 0.1), "wood", 0.36)
	var copper := smat(Color(0.2, 0.27, 0.24), "masonry", -1.0, Vector3(1, 0, 0), 0.0)
	var band := func(x: float) -> float: return deck_y(x) - 0.6
	_hull_band(func(x: float) -> float: return gunwale(x), band, paint)
	_hull_band(band, func(_x: float) -> float: return -10.5, wood)
	_hull_band(func(_x: float) -> float: return -10.5, func(x: float) -> float: return keel(x) - 0.01, copper)
	# 고물 판
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(STERN, (gunwale(STERN) + keel(STERN)) * 0.5, 0)
	var n := 24
	for s: float in [-1.0, 1.0]:
		for i in n:
			ReefKit._tri(st, c, hull_pt(STERN, PI * 0.5 * i / n, s), hull_pt(STERN, PI * 0.5 * (i + 1) / n, s), Vector3(-1, 0, 0))
	ReefKit._tri(st, c, hull_pt(STERN, 0.0, -1.0), hull_pt(STERN, 0.0, 1.0), Vector3(-1, 0, 0))
	st.generate_normals()
	_mi(st.commit(), smat(Color(0.3, 0.07, 0.06), "wood", 0.3, Vector3(0, 0, 1)), Vector3.ZERO)
	var dark := smat(Color(0.14, 0.09, 0.06), "wood", 0.0)
	for s: float in [-1.0, 1.0]:
		_hull_line(func(x: float) -> float: return gunwale(x) - 0.07, s, 0.2, dark, 0.0)
		_hull_line(band, s, 0.11, gold(), 0.03)
		_hull_line(func(x: float) -> float: return deck_y(x) - 4.0, s, 0.26, dark, 0.02)
		_hull_line(func(x: float) -> float: return deck_y(x) - 6.3, s, 0.2, dark, 0.02)
		_hull_line(func(_x: float) -> float: return -10.5, s, 0.12, gold(), 0.02)


func _hull_band(ya: Callable, yb: Callable, m: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 170
	var nt := 14
	for s: float in [-1.0, 1.0]:
		var grid := []
		for i in nx + 1:
			var x := lerpf(STERN, BOW, float(i) / nx)
			var t0 := t_at(x, ya.call(x))
			var t1 := t_at(x, yb.call(x))
			var row := []
			for j in nt + 1:
				row.append(hull_pt(x, lerpf(t0, t1, float(j) / nt), s))
			grid.append(row)
		for i in nx:
			for j in nt:
				var a: Vector3 = grid[i][j]
				var b: Vector3 = grid[i + 1][j]
				var c: Vector3 = grid[i + 1][j + 1]
				var d: Vector3 = grid[i][j + 1]
				var mid := (a + c) * 0.5
				var out := Vector3(0, (mid.y - (gunwale(mid.x) + keel(mid.x)) * 0.5) * 0.5, mid.z * 1.5).normalized()
				ReefKit._tri(st, a, b, c, out)
				ReefKit._tri(st, a, c, d, out)
	st.generate_normals()
	_mi(st.commit(), m, Vector3.ZERO)


func _hull_line(yf: Callable, s: float, r: float, m: Material, out_off: float) -> void:
	var pts := []
	var nx := 90
	for i in nx + 1:
		var x := lerpf(STERN + 0.05, BOW - 0.2, float(i) / nx)
		var y: float = yf.call(x)
		if y > gunwale(x) or y < keel(x) + 0.3:
			pts.append(null)
			continue
		var p := hull_pt(x, t_at(x, y), s)
		p.z += s * out_off
		pts.append(p)
	for i in nx:
		if pts[i] != null and pts[i + 1] != null:
			_rod(pts[i], pts[i + 1], r, m, -1.0, 8)


## 갑판 (널판 결이 배 길이 방향, 큰 갑판 가운데는 짐칸 구멍) + 층 앞벽 (문 · 창)
func _decks() -> void:
	var plank := smat(Color(0.5, 0.37, 0.24), "wood", 0.26)
	_deck_plate(QD_X - 0.4, FC_X + 0.4, 0.0, plank, true)
	_deck_plate(FC_X, BOW + 0.3, FC_Y, plank)
	_deck_plate(PP_X, QD_X, QD_Y, plank)
	_deck_plate(STERN, PP_X, PP_Y, plank)
	var wall := smat(Color(0.33, 0.2, 0.12), "wood", 0.24, Vector3(0, 0, 1))
	var door := smat(Color(0.18, 0.11, 0.07), "wood", 0.18, Vector3(0, 1, 0))
	# [x, 아래 높이, 위 높이, 앞벽이 보는 쪽 (+1 뱃머리)]
	for e in [[FC_X, 0.0, FC_Y, -1.0], [QD_X, 0.0, QD_Y, 1.0], [PP_X, QD_Y, PP_Y, 1.0]]:
		var x: float = e[0]
		var y0: float = e[1]
		var y1: float = e[2]
		var face: float = e[3]
		var h := y1 - y0
		var wdt := hb(x) * 2.0
		_box(Vector3(0.3, h, wdt), wall, Vector3(x, y0 + h * 0.5, 0))
		_box(Vector3(0.44, 0.16, wdt + 0.1), gold(), Vector3(x, y1 - 0.06, 0))
		var fx := x + face * 0.17
		_box(Vector3(0.08, 2.0, 1.2), door, Vector3(fx, y0 + 1.0, 0))
		_box(Vector3(0.1, 2.16, 1.4), gold(), Vector3(fx - face * 0.01, y0 + 1.05, 0))
		for sz: float in [-1.0, 1.0]:
			for k in (2 if h > 2.9 else 1):
				var zz := sz * (2.8 + k * 3.6)
				_box(Vector3(0.06, 0.8, 1.0), _glow(Color(1.0, 0.62, 0.28), 2.2), Vector3(fx, y0 + 1.75, zz))
				_box(Vector3(0.08, 0.96, 1.16), gold(), Vector3(fx - face * 0.01, y0 + 1.75, zz))
				_box(Vector3(0.1, 0.05, 1.0), door, Vector3(fx + face * 0.02, y0 + 1.75, zz))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.35)
		l.light_energy = 1.4
		l.omni_range = 7.0
		l.position = Vector3(fx + face * 1.4, y0 + 1.8, 0)
		add_child(l)
		_lamps.append([l, 1.4, randf() * TAU])


func _deck_plate(x0: float, x1: float, y: float, m: Material, hole := false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := []
	var n := maxi(4, int((x1 - x0) / 0.8))
	for i in n + 1:
		xs.append(lerpf(x0, x1, float(i) / n))
	if hole:
		xs.append(HOLD.position.x)
		xs.append(HOLD.end.x)
		xs.sort()
	for i in xs.size() - 1:
		var xa: float = xs[i]
		var xb: float = xs[i + 1]
		if xb - xa < 0.01:
			continue
		var za := hb(xa) + 0.1
		var zb := hb(xb) + 0.1
		var spans := [[-1.0, 1.0]]
		if hole and xa >= HOLD.position.x - 0.01 and xb <= HOLD.end.x + 0.01:
			spans = [[-1.0, HOLD.position.y], [HOLD.end.y, 1.0]]
		for sp in spans:
			var lo: float = sp[0]
			var hi: float = sp[1]
			var a := Vector3(xa, y, -za if lo == -1.0 else lo)
			var b := Vector3(xb, y, -zb if lo == -1.0 else lo)
			var c := Vector3(xb, y, zb if hi == 1.0 else hi)
			var d := Vector3(xa, y, za if hi == 1.0 else hi)
			ReefKit._tri(st, a, b, c, Vector3.UP)
			ReefKit._tri(st, a, c, d, Vector3.UP)
	st.generate_normals()
	_mi(st.commit(), m, Vector3.ZERO)


## 뚫린 짐칸: 테두리 턱 + 안쪽 벽 + 바닥의 보물 더미 (따뜻한 불빛) + 가로지르는 널다리
func _hold() -> void:
	var wall := smat(Color(0.22, 0.14, 0.09), "wood", 0.3, Vector3(1, 0, 0))
	var coam := smat(Color(0.3, 0.19, 0.11), "wood", 0.0)
	var h := HOLD
	var cx := h.position.x + h.size.x * 0.5
	var y0 := -HOLD_DEPTH
	_box(Vector3(h.size.x, 0.2, h.size.y), smat(Color(0.3, 0.21, 0.13), "wood", 0.3), Vector3(cx, y0, 0))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(h.size.x, HOLD_DEPTH, 0.2), wall, Vector3(cx, y0 * 0.5, s * (h.size.y * 0.5 + 0.1)))
		_box(Vector3(0.2, HOLD_DEPTH, h.size.y), wall, Vector3(cx + s * (h.size.x * 0.5 + 0.1), y0 * 0.5, 0))
		_box(Vector3(h.size.x + 0.6, 0.3, 0.3), coam, Vector3(cx, 0.15, s * (h.size.y * 0.5 + 0.15)))
		_box(Vector3(0.3, 0.3, h.size.y + 0.6), coam, Vector3(cx + s * (h.size.x * 0.5 + 0.15), 0.15, 0))
	# 보물: 상자 · 금화 더미 · 흩어진 금화
	var chest_w := smat(Color(0.4, 0.24, 0.12), "wood", 0.2, Vector3(1, 0, 0))
	var coin := _glow(Color(1.0, 0.76, 0.3), 0.6)
	coin.metallic = 0.9
	coin.roughness = 0.3
	for c in [[Vector3(-3.6, 0, -2.4), 0.4], [Vector3(2.8, 0, 2.6), -0.3], [Vector3(3.8, 0, -2.6), 0.9], [Vector3(-3.4, 0, 2.6), 1.6]]:
		var p: Vector3 = Vector3(cx, y0 + 0.1, 0) + c[0]
		var b := Basis(Vector3.UP, c[1])
		_mi(w._box(Vector3(1.3, 0.7, 0.85)), chest_w, p + Vector3(0, 0.35, 0), b)
		_mi(w._cyl(0.43, 0.43, 1.3, 16), chest_w, p + Vector3(0, 0.7, 0), b * Basis(Vector3(0, 0, 1), PI * 0.5))
		for bx: float in [-0.45, 0.45]:
			_mi(w._box(Vector3(0.08, 1.15, 0.9)), gold(), p + b * Vector3(bx, 0.55, 0), b)
	var pile := SphereMesh.new()
	pile.radius = 1.0
	pile.height = 0.6
	for q in [[Vector3(-0.6, 0, 1.6), 1.9], [Vector3(1.0, 0, -1.2), 1.5], [Vector3(-3.8, 0, 0.6), 1.0]]:
		_mi(pile, coin, Vector3(cx, y0 + 0.1, 0) + q[0], Basis().scaled(Vector3(q[1], q[1] * 0.7, q[1])))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.09
	cm.height = 0.03
	cm.radial_segments = 10
	var xs := []
	for k in 70:
		xs.append(Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(-0.3, 0.3)), Vector3(cx + rng.randf_range(-5.0, 5.0), y0 + 0.13, rng.randf_range(-4.0, 4.0))))
	_multi(cm, coin, xs)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 2.4
	l.omni_range = 13.0
	l.position = Vector3(cx, y0 + 3.0, 0)
	add_child(l)
	_lamps.append([l, 2.4, 0.3])
	# 널다리 (우현 S7 → H1 → H2 → 좌현 M3, 짐칸을 곧게 가로지름)
	var plank := smat(Color(0.46, 0.32, 0.2), "wood", 0.0, Vector3(1, 0, 0))
	var pts := [tile_pos("S7"), tile_pos("H1"), tile_pos("H2"), tile_pos("M3")]
	for k in 3:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		var bas := Basis(Vector3.UP, atan2(d.x, d.z))
		_mi(w._box(Vector3(2.0, 0.16, d.length())), plank, (a + b) * 0.5 + Vector3(0, 0.22, 0), bas)
		for s: float in [-1.0, 1.0]:
			var off := bas * Vector3(s * 1.05, 0, 0)
			rope(a + off + Vector3(0, 1.1, 0), b + off + Vector3(0, 1.1, 0))
			_rod(a + off, a + off + Vector3(0, 1.15, 0), 0.05, coam, -1.0, 6)


# ── 칸 ───────────────────────────────────────────────────────
func _spaces() -> void:
	first = w.spaces.size()
	for n in TILES:
		ids[n] = w.spaces.size()
		var base: Vector3 = AT + tile_pos(n)
		w.spaces.append({"base": base, "kind": SPECIAL.get(n, "plain"), "links": [], "next": [], "yaw": 0.0, "bridge": false, "ship": true,
			"pos": base + Vector3(0, w.TILE_H, 0), "ship_name": n})
	var chains := [LOOP + [LOOP[0]]] + BRANCHES
	for ch in chains:
		for k in ch.size() - 1:
			var a: int = ids[ch[k]]
			var b: int = ids[ch[k + 1]]
			w.spaces[a]["links"].append(b)
			w.spaces[b]["links"].append(a)
			w.spaces[a]["next"].append(b)
	# 칸 방향: 배와 나란히 (곧은 길) · 앞갑판 둥근 길은 앞뒤 칸을 잇는 방향
	for i in range(first, w.spaces.size()):
		var sp: Dictionary = w.spaces[i]
		var ls: Array = sp["links"]
		var a: Vector3 = w.spaces[ls[0]]["base"]
		var b: Vector3 = w.spaces[ls[ls.size() - 1]]["base"] if ls.size() > 1 else sp["base"]
		var d := b - a
		var yaw := atan2(d.x, d.z)
		var snap := roundf(yaw / (PI * 0.5)) * PI * 0.5
		sp["yaw"] = yaw if String(sp["ship_name"]) in ["F2", "F4"] else snap
		if sp["kind"] == "kraken_chest":
			sp["yaw"] = PI * 0.5     # 보물상자 반쪽이 뱃머리(상자) 쪽을 보게
	for n in DROPS:
		drop_tiles.append(ids[n])


## 도자기 칸 + 나무 받침 + 놋쇠 장식
func _tiles() -> void:
	var plinth := smat(Color(0.24, 0.15, 0.09), "wood", 0.2, Vector3(1, 0, 0))
	var brass := gold()
	var stud := SphereMesh.new()
	stud.radius = 0.08
	stud.height = 0.12
	stud.radial_segments = 10
	stud.rings = 5
	var studs := []
	for i in range(first, w.spaces.size()):
		var sp: Dictionary = w.spaces[i]
		var kind: String = sp["kind"]
		var p: Vector3 = (sp["base"] as Vector3) - AT
		var b := Basis(Vector3.UP, sp["yaw"])
		var size: float = w.TILE + (0.2 if kind == "junction" else 0.0)
		var body_c: Color = Color(0.82, 0.82, 0.77) if kind == "junction" else (w.TILE_COLORS[kind] as Color).darkened(0.2)
		var glaze: StandardMaterial3D = mat(body_c, 0.32)
		glaze.clearcoat_enabled = true
		glaze.clearcoat = 0.7
		glaze.clearcoat_roughness = 0.1
		glaze.rim_enabled = true
		glaze.rim = 0.25
		sp["body_mi"] = _mi(w._rbox(Vector3(size, w.TILE_H, size), 0.15), glaze, p + Vector3(0, w.TILE_H * 0.5, 0), b)
		_mi(w._rbox(Vector3(size + 0.46, 0.12, size + 0.46), 0.04), plinth, p + Vector3(0, 0.06, 0), b)
		_mi(w._rbox(Vector3(size + 0.06, 0.07, size + 0.06), 0.03), brass, p + Vector3(0, 0.2, 0), b)
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				studs.append(Transform3D(Basis(), p + b * Vector3(cx * (size * 0.5 + 0.13), 0.13, cz * (size * 0.5 + 0.13))))
		var plane := PlaneMesh.new()
		plane.size = Vector2(size - 0.3, size - 0.3)
		sp["top_mi"] = _mi(plane, w._tile_top_mat(kind, true), p + Vector3(0, w.TILE_H + 0.004, 0), b)
	_multi(stud, brass, studs)
	# 칸 소품 (찬스 카드 · 상점): 섬 쪽 함수로 만들고 배 밑으로 옮김
	for i in range(first, w.spaces.size()):
		var k: String = w.spaces[i]["kind"]
		if k != "chance" and k != "shop":
			continue
		var before: int = w.get_child_count()
		if k == "chance":
			w._chance_card(i)
		else:
			w._shop_stall(i)
		var moved := []
		for c in range(before, w.get_child_count()):
			moved.append(w.get_child(c))
		for n in moved:
			w.remove_child(n)
			add_child(n)
			if n is Node3D:
				(n as Node3D).position -= AT
			for sp in w._spinners:
				if sp["node"] == n:
					sp["base_y"] = float(sp["base_y"]) - AT.y


## 배 갑판 위가 비어 있는지 (상점 노점 자리 고르기)
func deck_free(c: Vector3, own: int) -> bool:
	var l := c - AT
	if absf(l.z) > hb(l.x) - 1.3 or l.x > BOW - 8.0 or l.x < STERN + 2.0:
		return false
	if absf(deck_y(l.x) - ((w.spaces[own]["base"] as Vector3).y - AT.y)) > 0.5:
		return false
	if HOLD.grow(1.0).has_point(Vector2(l.x, l.z)):
		return false
	for m in MASTS:
		if Vector2(l.x - float(m[0]), l.z).length() < 2.2:
			return false
	for j in range(first, w.spaces.size()):
		if j == own:
			continue
		var b: Vector3 = w.spaces[j]["base"]
		if Vector2(c.x - b.x, c.z - b.z).length() < 2.6:
			return false
	return true


# ── 계단 · 층 끝 난간 ────────────────────────────────────────
func _stairs_and_rails() -> void:
	var step_m := smat(Color(0.46, 0.33, 0.21), "wood", 0.0, Vector3(0, 0, 1))
	var side_m := smat(Color(0.28, 0.17, 0.1), "wood", 0.0, Vector3(1, 0, 0))
	var gaps := {FC_X: [], QD_X: [], PP_X: []}
	for e in STAIRS:
		var a := tile_pos(e[0])
		var b := tile_pos(e[1])
		var lo := a if a.y < b.y else b
		var hi := b if a.y < b.y else a
		var ex: float = FC_X if hi.x > 0.0 else (PP_X if hi.y > PP_Y - 0.5 else QD_X)
		var dir := signf(hi.x - lo.x)
		var zc := lerpf(lo.z, hi.z, clampf((ex - lo.x) / (hi.x - lo.x), 0.0, 1.0))
		gaps[ex].append(zc)
		var y0 := lo.y
		var h := hi.y - lo.y
		var n := int(ceil(h / 0.36))
		var tread := 0.3
		var run := n * tread
		for k in n:
			var top := y0 + h * float(k + 1) / n
			var x := ex - dir * (run - (k + 0.5) * tread)
			_box(Vector3(tread + 0.02, 0.1, 1.8), step_m, Vector3(x, top - 0.05, zc))
			_box(Vector3(0.04, top - y0 - 0.1, 1.7), side_m, Vector3(x + dir * tread * 0.5 - dir * 0.02, y0 + (top - y0 - 0.1) * 0.5, zc))
		for sz: float in [-1.0, 1.0]:
			var p0 := Vector3(ex - dir * run, y0, zc + sz * 0.95)
			var p1 := Vector3(ex, hi.y, zc + sz * 0.95)
			_mi(w._box(Vector3((p1 - p0).length() + 0.2, 0.34, 0.08)), side_m, (p0 + p1) * 0.5 + Vector3(0, -0.05, 0),
				Basis(Vector3(0, 0, 1), atan2(p1.y - p0.y, p1.x - p0.x)))
			_rod(p0 + Vector3(0, 1.0, 0), p1 + Vector3(dir * 0.2, 1.0, 0), 0.05, gold(), -1.0, 8)
			_rod(p0, p0 + Vector3(0, 1.05, 0), 0.06, side_m, -1.0, 8)
	var rail_m := smat(Color(0.3, 0.18, 0.1), "wood", 0.0, Vector3(0, 0, 1))
	var post_m := smat(Color(0.42, 0.28, 0.17), "wood", 0.0, Vector3(0, 1, 0))
	var bal := CylinderMesh.new()
	bal.top_radius = 0.045
	bal.bottom_radius = 0.06
	bal.height = 0.85
	bal.radial_segments = 8
	var xs := []
	for ex in [FC_X, QD_X, PP_X]:
		var y: float = FC_Y if ex == FC_X else (QD_Y if ex == QD_X else PP_Y)
		var half := hb(ex) - 0.1
		var segs := []
		var cur := -half
		var gl: Array = gaps[ex]
		gl.sort()
		for g in gl:
			segs.append([cur, float(g) - 1.0])
			cur = float(g) + 1.0
		segs.append([cur, half])
		for sg in segs:
			var z0: float = sg[0]
			var z1: float = sg[1]
			if z1 - z0 < 0.3:
				continue
			_box(Vector3(0.14, 0.1, z1 - z0), rail_m, Vector3(ex, y + 0.95, (z0 + z1) * 0.5))
			var nb := int((z1 - z0) / 0.32)
			for k in nb + 1:
				xs.append(Transform3D(Basis(), Vector3(ex, y + 0.45, lerpf(z0, z1, float(k) / maxf(nb, 1)))))
			for zz: float in [z0, z1]:
				_box(Vector3(0.18, 1.1, 0.18), post_m, Vector3(ex, y + 0.55, zz))
	_multi(bal, post_m, xs)


# ── 돛대 · 활대 · 돛 · 밧줄 ──────────────────────────────────
func _masts() -> void:
	var mast_m := smat(Color(0.36, 0.24, 0.14), "wood", 0.0, Vector3(0, 1, 0))
	var yard_m := smat(Color(0.3, 0.2, 0.12), "wood", 0.0, Vector3(0, 0, 1))
	var furl_m := mat(Color(0.5, 0.42, 0.34), 0.95)
	for mi in MASTS.size():
		var m: Array = MASTS[mi]
		var x: float = m[0]
		var y0: float = m[1]
		var h: float = m[2]
		var r: float = m[3]
		var k_r := r / 0.6
		var p0 := Vector3(x, y0, 0)
		var lo := h * TOP_K
		_rod(p0 + Vector3(0, -0.6, 0), p0 + Vector3(0, lo + 1.4, 0), r * 0.82, mast_m, r, 16)
		_rod(p0 + Vector3(0, lo - 1.2, 0), p0 + Vector3(0, h * 0.78 + 1.0, 0), r * 0.48, mast_m, r * 0.62, 14)
		_rod(p0 + Vector3(0, h * 0.76, 0), p0 + Vector3(0, h, 0), r * 0.26, mast_m, r * 0.38, 12)
		for k in 7:
			_mi(w._cyl(r * 0.95, r * 0.95, 0.14, 16), iron(), p0 + Vector3(0, lerpf(1.4, lo - 0.6, k / 6.0), 0))
		_mi(w._cyl(r * 0.5, r * 0.5, 0.35, 12), iron(), p0 + Vector3(0, h + 0.1, 0))
		_box(Vector3(0.22, 0.22, 3.4 * k_r), yard_m, p0 + Vector3(0, h * 0.78, 0))
		_box(Vector3(2.0 * k_r, 0.22, 0.22), yard_m, p0 + Vector3(0, h * 0.78, 0))
		_mi(w._cyl(2.4 * k_r, 2.2 * k_r, 0.3, 24), yard_m, p0 + Vector3(0, lo - 0.15, 0))
		# 활대 3 단 (맨 아래는 돛을 말아 묶음)
		var span := 10.0 * (h / 40.0) + 1.5
		var yards := [[0.33, 1.0], [0.6, 0.8], [0.86, 0.56]]
		var bas := Basis(Vector3.UP, BRACE * (1.0 if mi != 2 else 0.6))
		var ends := []
		for k in yards.size():
			var yy: float = y0 + h * float(yards[k][0])
			var half: float = span * float(yards[k][1])
			var a := Vector3(x, yy, 0) + bas * Vector3(0, 0, -half)
			var b := Vector3(x, yy, 0) + bas * Vector3(0, 0, half)
			_rod(a, b, 0.11 + 0.08 * yards[k][1], yard_m, 0.11 + 0.08 * yards[k][1] * 1.6, 10)
			ends.append([a, b, yy, half])
			if k == 0:
				_rod(a + bas * Vector3(0.05, -0.34, 0.5), b + bas * Vector3(0.05, -0.34, -0.5), 0.38, furl_m, 0.38, 12)
				for q in 9:
					var pq := a.lerp(b, (q + 0.5) / 9.0) + bas * Vector3(0.05, -0.34, 0)
					_mi(w._cyl(0.41, 0.41, 0.07, 12), mat(Color(0.2, 0.15, 0.1), 0.9), pq, bas * Basis(Vector3(1, 0, 0), PI * 0.5))
			rope(a, Vector3(x - 4.5, gunwale(x - 4.5) + 0.2, -hw(x - 4.5) + 0.2) if k == 0 else ends[k - 1][0], true)
			rope(b, Vector3(x - 4.5, gunwale(x - 4.5) + 0.2, hw(x - 4.5) - 0.2) if k == 0 else ends[k - 1][1], true)
		if mi != 2:
			for k in [1, 2]:
				var top: Array = ends[k]
				var bot: Array = ends[k - 1]
				var ht: float = float(top[2]) - float(bot[2]) - 0.3
				_sail(Vector3(x, float(top[2]) - 0.18, 0) + bas * Vector3(0.14, 0, 0), bas, float(top[3]) * 1.92, float(bot[3]) * 1.84, ht,
					1.0 + ht * 0.08, mi == 1 and k == 1, mi * 3.1 + k)
		else:
			_spanker(x, y0, h)
		# 옆 버팀줄 + 줄사다리 (뱃전으로)
		for s: float in [-1.0, 1.0]:
			var lows := []
			for k in 6:
				var cx := x + lerpf(-3.6, 2.6, k / 5.0)
				lows.append(Vector3(cx, gunwale(cx) + 0.1, s * (hw(cx) + 0.15)))
			var tz := s * 0.6 * k_r
			for k in 6:
				rope(Vector3(x + lerpf(-0.3, 0.3, k / 5.0), y0 + lo, tz), lows[k])
			for q in 32:
				var f := (q + 1) / 33.0
				rope(Vector3(x - 0.3, y0 + lo, tz).lerp(lows[0], f), Vector3(x + 0.3, y0 + lo, tz).lerp(lows[5], f), true)
			for k in 3:
				rope(Vector3(x, y0 + h * 0.78, s * 0.25), Vector3(x + (k - 1) * 0.8, y0 + lo + 0.1, s * 2.2 * k_r), true)
			rope(Vector3(x, y0 + h * 0.97, 0), Vector3(x - 10.0, gunwale(x - 10.0) + 0.1, s * (hw(x - 10.0) + 0.1)))
		_flag(Vector3(x, y0 + h + 0.3, 0), Vector2(10.0 if mi == 1 else 7.0, 1.5), Color(0.5, 0.06, 0.06), false, mi * 1.7)
	rope(Vector3(MASTS[1][0], top_y(1), 0), Vector3(MASTS[0][0] - 0.6, 1.6, 0))
	rope(Vector3(MASTS[1][0], MASTS[1][2], 0), Vector3(MASTS[0][0], MASTS[0][2] * 0.78, 0))
	rope(Vector3(MASTS[2][0], MASTS[2][1] + MASTS[2][2], 0), Vector3(MASTS[1][0], MASTS[1][2] * 0.78, 0))
	var nest_m := smat(Color(0.32, 0.21, 0.12), "wood", 0.14, Vector3(0, 1, 0))
	var ny: float = MASTS[1][2] * 0.78 + 0.1
	_mi(w._cyl(1.3, 1.05, 1.3, 20), nest_m, Vector3(MASTS[1][0], ny + 0.65, 0))
	_mi(w._cyl(1.38, 1.38, 0.14, 20), iron(), Vector3(MASTS[1][0], ny + 1.28, 0))
	_lantern(Vector3(MASTS[1][0] + 1.4, ny + 1.0, 0), 0.9, true, true)


func _sail(top_c: Vector3, bas: Basis, wt: float, wb: float, ht: float, billow: float, emblem: bool, seed: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 16
	var nv := 12
	for i in nu:
		for j in nv:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / nu
				var v := float(c[1]) / nv
				quad.append([Vector3((u - 0.5) * lerpf(wt, wb, v), -v * ht, 0), Vector2(u, v)])
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for q in tri:
					st.set_uv(quad[q][1])
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(quad[q][0])
	var m := _sail_mat(Vector2(maxf(wt, wb), ht), billow, seed, 0.7)
	if emblem:
		m.set_shader_parameter("emblem", EMBLEM)
		m.set_shader_parameter("emblem_on", 1.0)
		m.set_shader_parameter("emblem_rect", Vector4(0.2, 0.08, 0.6, 0.8))
	var b := bas * Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	var mi := _mi(st.commit(), m, top_c, b)
	mi.custom_aabb = AABB(Vector3(-wb, -ht - 1.0, -billow - 2.0), Vector3(wb * 2.0, ht + 2.0, billow * 2.0 + 4.0))


func _sail_mat(size: Vector2, billow: float, seed: float, tatter: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SailShader
	m.set_shader_parameter("cloth", Color(0.58, 0.12, 0.11))
	m.set_shader_parameter("hem", Color(0.3, 0.06, 0.05))
	m.set_shader_parameter("billow", billow)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("tatter", tatter)
	m.set_shader_parameter("emblem_col", Color(0.88, 0.82, 0.68))
	return m


## 뒷돛대 세로 돛 (가프 돛): 크라켄 문양이 옆에서 크게 보임. 아랫단은 선장실 지붕 칸 위로 높게
func _spanker(x: float, y0: float, h: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foot := PP_Y + 3.4
	var head := y0 + h * 0.74
	var ln := 9.0
	var peak := head + 3.6
	var nu := 14
	var nv := 12
	for i in nu:
		for j in nv:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / nu
				var v := float(c[1]) / nv
				quad.append([Vector3(-u * ln, lerpf(lerpf(head, peak, u), foot, v), 0), Vector2(u, v)])
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for q in tri:
					st.set_uv(quad[q][1])
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(quad[q][0])
	var m := _sail_mat(Vector2(ln, peak - foot), -1.3, 5.5, 0.6)
	m.set_shader_parameter("emblem", EMBLEM)
	m.set_shader_parameter("emblem_on", 1.0)
	m.set_shader_parameter("emblem_rect", Vector4(0.12, 0.12, 0.76, 0.76))
	var mi := _mi(st.commit(), m, Vector3(x - 0.4, 0, 0))
	mi.custom_aabb = AABB(Vector3(-ln - 1, foot - 1, -3), Vector3(ln + 2, peak - foot + 2, 6))
	var spar := smat(Color(0.3, 0.2, 0.12), "wood", 0.0, Vector3(1, 0, 0))
	_rod(Vector3(x - 0.4, head, 0), Vector3(x - 0.4 - ln - 0.6, peak + 0.15, 0), 0.14, spar, 0.18, 10)
	_rod(Vector3(x - 0.4, foot - 0.1, 0), Vector3(x - 0.4 - ln - 1.4, foot - 0.1, 0), 0.16, spar, 0.2, 10)
	_flag(Vector3(x - 0.4 - ln - 0.6, peak + 0.1, 0), Vector2(4.4, 2.9), Color(0.05, 0.05, 0.06), true, 2.2)


func _flag(at: Vector3, size: Vector2, col: Color, emblem: bool, seed: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 16
	var nv := 4
	for i in nu:
		for j in nv:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / nu
				var v := float(c[1]) / nv
				var hh := size.y * (1.0 if emblem else 1.0 - u * 0.9)
				quad.append([Vector3(-u * size.x, -(v - 0.5) * hh, 0), Vector2(u, v)])
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for q in tri:
					st.set_uv(quad[q][1])
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(quad[q][0])
	var m := _sail_mat(size, 0.0, seed, 0.8)
	m.set_shader_parameter("mode", 2)
	m.set_shader_parameter("cloth", col)
	m.set_shader_parameter("hem", col.darkened(0.3))
	if emblem:
		m.set_shader_parameter("emblem", EMBLEM)
		m.set_shader_parameter("emblem_on", 1.0)
		m.set_shader_parameter("emblem_rect", Vector4(0.18, 0.05, 0.64, 0.9))
		m.set_shader_parameter("emblem_col", Color(0.9, 0.86, 0.76))
	var mi := _mi(st.commit(), m, at - Vector3(0, size.y * 0.5, 0))
	mi.custom_aabb = AABB(Vector3(-size.x - 1, -size.y - 1, -2), Vector3(size.x + 2, size.y * 2 + 2, 4))
	_rod(at + Vector3(0, -size.y - 0.2, 0), at + Vector3(0, 0.6, 0), 0.05, mat(Color(0.2, 0.14, 0.09), 0.7), -1.0, 6)


# ── 뱃머리 · 고물 ────────────────────────────────────────────
func _bow() -> void:
	var spar := smat(Color(0.34, 0.22, 0.13), "wood", 0.0, Vector3(1, 0, 0))
	var b0 := Vector3(BOW - 3.0, FC_Y + 2.2, 0)
	var b1 := Vector3(BOW + 24.0, FC_Y + 11.5, 0)
	_rod(b0, b1, 0.32, spar, 0.75, 14)
	for k in 3:
		_mi(w._cyl(0.46 - k * 0.07, 0.46 - k * 0.07, 0.14, 12), iron(), b0.lerp(b1, 0.25 + k * 0.2),
			Basis(Vector3(0, 0, 1), -PI * 0.5 + atan2(b1.y - b0.y, b1.x - b0.x)))
	var fm: Array = MASTS[0]
	var h1 := Vector3(fm[0], float(fm[2]) * 0.78, 0)
	var t1 := b0.lerp(b1, 0.93)
	_jib(h1, t1, h1.lerp(t1, 0.7) + Vector3(-4.6, -8.0, 0), 1.0)
	var h2 := Vector3(fm[0], float(fm[2]) * 0.6, 0)
	var t2 := b0.lerp(b1, 0.6)
	_jib(h2, t2, h2.lerp(t2, 0.68) + Vector3(-3.8, -6.4, 0), 2.0)
	rope(Vector3(fm[0], float(fm[2]) * 0.97, 0), b1)
	rope(b1, Vector3(BOW - 0.5, -4.0, 0))
	for s: float in [-1.0, 1.0]:
		rope(b0.lerp(b1, 0.7), Vector3(BOW - 6.5, gunwale(BOW - 6.5), s * hw(BOW - 6.5)), true)
	# 뱃머리 장식: 금박 크라켄 조각 (눈은 검붉게 빛남)
	var fig := Node3D.new()
	fig.position = Vector3(BOW + 0.6, -1.4, 0)
	fig.basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, 0.7)
	fig.scale = Vector3.ONE * 1.1
	add_child(fig)
	var body := MeshInstance3D.new()
	body.mesh = w.KRAKEN_BODY
	body.material_override = mat(Color(0.82, 0.6, 0.26), 0.38, 0.9)
	fig.add_child(body)
	for sd: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.3
		eye.height = 0.6
		_mi(eye, _glow(Color(1.0, 0.16, 0.12), 3.0), Vector3(sd * 1.57, 0.74, 1.3), Basis(Vector3.UP, sd * 0.72), fig)
	# 닻 (우현 뱃머리 옆에 매달림)
	var ax := BOW - 13.0
	var az := hw(ax) + 0.4
	var ay := FC_Y - 1.6
	_rod(Vector3(ax, ay + 2.0, az), Vector3(ax, ay - 2.0, az), 0.15, iron(), -1.0, 8)
	_rod(Vector3(ax - 1.4, ay + 1.8, az), Vector3(ax + 1.4, ay + 1.8, az), 0.11, spar, -1.0, 8)
	for s: float in [-1.0, 1.0]:
		_rod(Vector3(ax, ay - 2.0, az), Vector3(ax + s * 1.3, ay - 0.9, az), 0.14, iron(), -1.0, 8)
		_mi(w._prism(0.34, 0.5, 0.14), iron(), Vector3(ax + s * 1.35, ay - 0.8, az), Basis(Vector3(0, 0, 1), s * 0.6))
	for k in 10:
		_mi(w._cyl(0.11, 0.11, 0.26, 6), iron(), Vector3(ax + 0.1 * sin(k), ay + 2.3 + k * 0.2, az), Basis(Vector3(1, 0, 0), PI * 0.5 * (k % 2)))


func _jib(head: Vector3, tack: Vector3, clew: Vector3, seed: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for i in n:
		for j in n:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / n
				var v := float(c[1]) / n
				quad.append([head.lerp(tack.lerp(clew, u), v), Vector2(u, v)])
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for q in tri:
					st.set_uv(quad[q][1])
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(quad[q][0])
	var m := _sail_mat(Vector2((tack - clew).length(), (head - tack).length()), 0.9, seed, 0.0)
	m.set_shader_parameter("mode", 1)
	var mi := _mi(st.commit(), m, Vector3.ZERO)
	mi.custom_aabb = AABB(Vector3(0, 0, -4), Vector3(BOW + 20, 40, 8))
	rope(head, tack, true)


func _stern() -> void:
	var dark := smat(Color(0.18, 0.11, 0.07), "wood", 0.0)
	var x := STERN - 0.04
	for row in 3:
		var y := PP_Y - 1.6 - row * 2.2
		var n := 7 - row
		for k in n:
			var z := (k - (n - 1) * 0.5) * 1.9
			if absf(z) > hw(STERN) * pow(maxf(cos(t_at(STERN, y)), 0.0), 0.45) - 0.8:
				continue
			_box(Vector3(0.06, 1.05, 0.95), _glow(Color(1.0, 0.6, 0.26), 2.6), Vector3(x, y, z))
			_box(Vector3(0.1, 1.24, 1.14), gold(), Vector3(x + 0.03, y, z))
			_box(Vector3(0.12, 0.05, 0.95), dark, Vector3(x - 0.02, y, z))
			_box(Vector3(0.12, 1.05, 0.05), dark, Vector3(x - 0.02, y, z))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.position = Vector3(STERN - 2.0, PP_Y - 2.5, 0)
	add_child(l)
	_lamps.append([l, 2.2, 1.0])
	var gy := gunwale(STERN)
	_lantern(Vector3(STERN - 0.5, gy + 1.1, 0), 2.0)
	for s: float in [-1.0, 1.0]:
		_lantern(Vector3(STERN + 0.8, gy + 0.85, s * (hw(STERN + 0.8) - 0.3)), 1.5)
	# 조타륜 (선장실 지붕 가운데)
	var wheel_x := -53.8
	var wood := smat(Color(0.4, 0.26, 0.15), "wood", 0.0, Vector3(0, 1, 0))
	_box(Vector3(0.6, 1.2, 0.6), wood, Vector3(wheel_x - 0.5, PP_Y + 0.6, 0))
	var wheel := Node3D.new()
	wheel.position = Vector3(wheel_x, PP_Y + 1.4, 0)
	add_child(wheel)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.78
	tor.outer_radius = 0.92
	tor.rings = 32
	tor.ring_segments = 8
	_mi(tor, wood, Vector3.ZERO, Basis(Vector3(0, 0, 1), PI * 0.5), wheel)
	for k in 8:
		var a := TAU * k / 8.0
		var d := Vector3(0, cos(a), sin(a))
		_rod(d * 0.1, d * 1.2, 0.04, wood, 0.06, 6, wheel)
	_mi(w._cyl(0.14, 0.14, 0.34, 10), gold(), Vector3.ZERO, Basis(Vector3(0, 0, 1), PI * 0.5), wheel)
	_swing.append([wheel, 0.12, 0.0])
	_rod(Vector3(STERN + 0.4, gy - 0.5, 0), Vector3(STERN - 1.6, gy + 6.0, 0), 0.08, dark, 0.12, 8)


# ── 갑판 소품 ───────────────────────────────────────────────
func _deck_props() -> void:
	var wood := smat(Color(0.42, 0.28, 0.17), "wood", 0.0, Vector3(0, 1, 0))
	var dark := smat(Color(0.2, 0.13, 0.08), "wood", 0.0)
	# 대포: 갑판 위 바퀴 받침 + 포신이 뱃전 밖으로 (칸 · 공중 발판 계단과 겹치지 않는 자리만)
	for s: float in [-1.0, 1.0]:
		for cx: float in [-30.2, -24.7, -19.2, -13.7, -8.2, -2.7, 2.7, 8.2, 13.7, 19.2, 24.7, 30.2, 35.6]:
			var z := s * (hb(cx) - 1.4)
			if near_tile(Vector3(cx, 0, z), 2.1) or _near_swivel(Vector3(cx, 0, z)):
				continue
			_box(Vector3(0.75, 0.42, 1.3), dark, Vector3(cx, 0.36, z))
			for wx: float in [-0.38, 0.38]:
				for wz: float in [-0.46, 0.46]:
					_mi(w._cyl(0.2, 0.2, 0.09, 12), dark, Vector3(cx + wx, 0.2, z + wz), Basis(Vector3(0, 0, 1), PI * 0.5))
			var a := Vector3(cx, 0.84, z - s * 0.6)
			var b := Vector3(cx, 0.9, z + s * 2.2)
			_rod(a, b, 0.15, iron(), 0.23, 14)
			_mi(w._cyl(0.2, 0.2, 0.14, 14), iron(), b, Basis(Vector3(1, 0, 0), PI * 0.5))
			_mi(SphereMesh.new(), iron(), a - Vector3(0, 0, s * 0.12), Basis().scaled(Vector3.ONE * 0.32))
			var hp := hull_pt(cx, t_at(cx, 0.85), s)
			_box(Vector3(0.95, 0.85, 0.08), smat(Color(0.12, 0.08, 0.05), "wood", 0.0), Vector3(cx, 0.85, hp.z + s * 0.03))
		# 아래층 대포 구멍
		for k in 18:
			var gx := -46.0 + k * 5.6
			if gx > 50.0:
				continue
			var y := deck_y(gx) - 4.8
			var hp := hull_pt(gx, t_at(gx, y), s)
			var open := k % 3 == 1
			_box(Vector3(1.1, 0.95, 0.12), smat(Color(0.3, 0.06, 0.05), "wood", 0.0) if not open else smat(Color(0.03, 0.02, 0.02), "wood", 0.0),
				Vector3(gx, y, hp.z + s * 0.02))
			_box(Vector3(1.28, 1.12, 0.06), gold(), Vector3(gx, y, hp.z - s * 0.01))
			if open:
				_rod(Vector3(gx, y, hp.z - s * 0.3), Vector3(gx, y, hp.z + s * 1.1), 0.16, iron(), 0.22, 12)
	# 닻 감는 기둥
	var cap := Vector3(-22.0, 0, 0)
	_mi(w._cyl(0.6, 0.75, 1.3, 16), wood, cap + Vector3(0, 0.65, 0))
	_mi(w._cyl(0.86, 0.86, 0.18, 16), dark, cap + Vector3(0, 1.27, 0))
	for k in 6:
		var a := TAU * k / 6.0
		_rod(cap + Vector3(0, 1.1, 0), cap + Vector3(cos(a) * 1.8, 1.1, sin(a) * 1.8), 0.06, wood, -1.0, 6)
	# 나무통 · 상자 더미 (칸과 겹치지 않는 자리만)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.4
	barrel.bottom_radius = 0.4
	barrel.height = 1.1
	barrel.radial_segments = 14
	var bwood := smat(Color(0.45, 0.29, 0.16), "wood", 0.12, Vector3(0, 1, 0))
	var crate := smat(Color(0.5, 0.36, 0.22), "wood", 0.18, Vector3(1, 0, 0))
	for spot in [[Vector3(37.0, 0, 1.0), 4], [Vector3(38.0, 0, -4.0), 2], [Vector3(-30.5, 0, 4.0), 3], [Vector3(-30.5, 0, -4.2), 2],
			[Vector3(-47.0, QD_Y, 4.4), 2], [Vector3(-9.0, 0, -3.0), 2], [Vector3(25.5, 0, 2.6), 3], [Vector3(47.5, FC_Y, 0.0), 2],
			[Vector3(-61.0, PP_Y, -8.0), 2], [Vector3(-17.5, 0, -3.4), 2], [Vector3(6.0, 0, 4.0), 3], [Vector3(5.0, 0, -5.0), 2]]:
		var c: Vector3 = spot[0]
		for q in int(spot[1]):
			var p := c + Vector3((q % 2) * 0.82 - 0.41, 0.55, (q / 2) * 0.82)
			if near_tile(p, 1.9):
				continue
			if q == 3:
				p += Vector3(0.4, 1.1, -0.4)
			_mi(barrel, bwood, p, Basis(Vector3.UP, q * 0.7))
			for yy: float in [-0.36, 0.36]:
				_mi(w._cyl(0.41, 0.41, 0.07, 14), iron(), p + Vector3(0, yy, 0))
	for spot in [Vector3(36.0, 0, 5.0), Vector3(-28.5, 0, 0.4), Vector3(-39.0, QD_Y, 4.0), Vector3(-61.5, PP_Y, 7.4), Vector3(25.0, 0, -3.8),
			Vector3(-14.0, 0, 2.6), Vector3(57.0, FC_Y, 7.5), Vector3(0.0, 0, 3.0), Vector3(9.0, 0, -4.0), Vector3(-45.0, QD_Y, -3.6)]:
		if near_tile(spot, 1.8):
			continue
		_box(Vector3(1.0, 0.8, 1.0), crate, spot + Vector3(0, 0.4, 0), Basis(Vector3.UP, 0.3))
		_box(Vector3(0.7, 0.55, 0.7), smat(Color(0.44, 0.31, 0.19), "wood", 0.15, Vector3(0, 0, 1)), spot + Vector3(0.1, 1.08, 0.05), Basis(Vector3.UP, -0.2))
	var coil := TorusMesh.new()
	coil.inner_radius = 0.2
	coil.outer_radius = 0.52
	coil.rings = 20
	coil.ring_segments = 8
	for p in [Vector3(-6.0, 0.06, 3.0), Vector3(29.0, 0.06, -2.8), Vector3(-42.0, QD_Y + 0.06, 2.6), Vector3(46.0, FC_Y + 0.06, 3.0), Vector3(-6.0, 0.06, -4.6), Vector3(-58.0, PP_Y + 0.06, 4.0)]:
		if near_tile(p, 2.0):
			continue
		for k in 3:
			_mi(coil, mat(Color(0.55, 0.45, 0.3), 0.95), p + Vector3(0, k * 0.09, 0), Basis().scaled(Vector3(1.0 - k * 0.12, 1.0, 1.0 - k * 0.12)))
	# 종 (앞갑판 앞 난간 가운데)
	var bell := Node3D.new()
	bell.position = Vector3(FC_X + 0.8, FC_Y + 2.1, 0)
	add_child(bell)
	for z: float in [-0.7, 0.7]:
		_rod(Vector3(FC_X + 0.6, FC_Y, z), Vector3(FC_X + 0.6, FC_Y + 2.4, z), 0.07, dark, -1.0, 6)
	_rod(Vector3(FC_X + 0.6, FC_Y + 2.4, -0.8), Vector3(FC_X + 0.6, FC_Y + 2.4, 0.8), 0.08, dark, -1.0, 6)
	_mi(w._cyl(0.14, 0.36, 0.5, 16), gold(), Vector3(0, 0.05, 0), Basis(), bell)
	_swing.append([bell, 0.15, 0.5])
	# 뱃전 위 등불
	for s: float in [-1.0, 1.0]:
		for x: float in [-58.0, -42.0, -25.0, -14.0, -3.0, 9.0, 19.5, 30.5, 46.0, 58.0]:
			var p := Vector3(x, gunwale(x) + 0.05, s * (hw(x) - 0.12))
			_rod(p, p + Vector3(0, 1.0, 0), 0.05, dark, -1.0, 6)
			_rod(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, -s * 0.5), 0.04, iron(), -1.0, 6)
			_lantern(p + Vector3(0, 0.58, -s * 0.5), 0.95, s > 0.0 or absf(x) > 20.0, true)
	# 뱃전 꼭대기 난간 (짧은 기둥 줄 + 손잡이)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.08
	post.height = 0.5
	post.radial_segments = 6
	var xs := []
	for s: float in [-1.0, 1.0]:
		var x := STERN + 0.5
		while x < BOW - 1.0:
			xs.append(Transform3D(Basis(), Vector3(x, gunwale(x) + 0.2, s * (hw(x) - 0.12))))
			x += 1.2
	_multi(post, dark, xs)
	for s: float in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		var nx := 90
		for i in nx + 1:
			var x := lerpf(STERN + 0.5, BOW - 1.0, float(i) / nx)
			var p := Vector3(x, gunwale(x) + 0.47, s * (hw(x) - 0.12))
			if i > 0:
				_rod(prev, p, 0.08, dark, -1.0, 6)
			prev = p


## 등불: 쇠 틀 + 따뜻한 불빛
func _lantern(p: Vector3, s: float, light := true, hang := false, col := Color(1.0, 0.66, 0.3)) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	_mi(w._cyl(0.17 * s, 0.22 * s, 0.1 * s, 8), iron(), Vector3(0, 0.28 * s, 0), Basis(), root)
	_mi(w._cyl(0.02 * s, 0.17 * s, 0.22 * s, 8), iron(), Vector3(0, 0.42 * s, 0), Basis(), root)
	_mi(w._cyl(0.2 * s, 0.2 * s, 0.06 * s, 8), iron(), Vector3(0, -0.28 * s, 0), Basis(), root)
	_mi(w._cyl(0.16 * s, 0.16 * s, 0.48 * s, 8), _glow(col, 3.2), Vector3.ZERO, Basis(), root)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		_mi(w._box(Vector3(0.03, 0.56, 0.03) * s), iron(), Vector3(cos(a), 0, sin(a)) * 0.18 * s, Basis(), root)
	if hang:
		_swing.append([root, 0.08, randf() * TAU])
	if light:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.5
		l.omni_range = 7.0 * s
		l.omni_attenuation = 1.2
		root.add_child(l)
		_lamps.append([l, 1.5, randf() * TAU])


func _flush_ropes() -> void:
	for pair in [[_ropes, 0.05], [_ropes_thin, 0.028]]:
		var list: Array = pair[0]
		if list.is_empty():
			continue
		var c := CylinderMesh.new()
		c.top_radius = float(pair[1])
		c.bottom_radius = float(pair[1])
		c.height = 1.0
		c.radial_segments = 5
		c.rings = 1
		_multi(c, mat(Color(0.16, 0.12, 0.08), 0.9), list)


# ── 구름 바다 · 스쳐 가는 구름 ────────────────────────────────
func _sky_clouds() -> void:
	for layer in [[CLOUD_Y, 0.45, 1.0, Vector2(-9.0, 0.5), 0.007], [CLOUD_Y + 15.0, 0.62, 0.55, Vector2(-14.0, 0.8), 0.011]]:
		var pm := PlaneMesh.new()
		pm.size = Vector2(4000, 4000)
		var m := ShaderMaterial.new()
		m.shader = CloudSeaShader
		m.set_shader_parameter("cover", layer[1])
		m.set_shader_parameter("opacity", layer[2])
		m.set_shader_parameter("flow", layer[3])
		m.set_shader_parameter("scale", layer[4])
		m.set_shader_parameter("center", AT)
		var mi := _mi(pm, m, Vector3(0, float(layer[0]), 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	for k in 34:
		var q := QuadMesh.new()
		var sz := rng.randf_range(36.0, 90.0)
		q.size = Vector2(sz * 1.6, sz)
		var m := ShaderMaterial.new()
		m.shader = CloudPuffShader
		m.set_shader_parameter("seed", rng.randf() * 10.0)
		m.set_shader_parameter("opacity", rng.randf_range(0.55, 0.9))
		var p := Vector3(rng.randf_range(-450, 450), 0, 0)
		var band := k % 3
		if band == 0:
			p.y = rng.randf_range(-48, -28)
			p.z = rng.randf_range(-240, 240)
		elif band == 1:
			p.y = rng.randf_range(-12, 60)
			p.z = rng.randf_range(-450, -130)
		else:
			p.y = rng.randf_range(20, 90)
			p.z = rng.randf_range(-380, -90)
		var mi := _mi(q, m, p)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_puffs.append([mi, rng.randf_range(6.0, 12.0)])


## 섬에서 쓰던 재질 중 물속 빛 무늬가 있는 것은 배 쪽 복사본으로 (상점 노점 등)
func strip_caustics(n: Node, cache := {}) -> void:
	for c in n.get_children():
		strip_caustics(c, cache)
	var gi := n as GeometryInstance3D
	if gi and gi.material_override is ShaderMaterial:
		var sm := gi.material_override as ShaderMaterial
		if sm.shader and sm.get_shader_parameter("caustics") != null and float(sm.get_shader_parameter("caustics")) > 0.0:
			if not cache.has(sm):
				var d := sm.duplicate() as ShaderMaterial
				d.set_shader_parameter("caustics", 0.0)
				cache[sm] = d
			gi.material_override = cache[sm]


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for p in _puffs:
		var n: Node3D = p[0]
		n.position.x -= float(p[1]) * delta
		if n.position.x < -470.0:
			n.position.x += 940.0
	for l in _lamps:
		(l[0] as OmniLight3D).light_energy = float(l[1]) * (0.85 + 0.1 * sin(_t * 9.0 + float(l[2])) + 0.05 * sin(_t * 23.0 + float(l[2]) * 2.0))
	for s in _swing:
		(s[0] as Node3D).rotation.x = sin(_t * 1.1 + float(s[2])) * float(s[1])
	_wheel_process(delta)



# ── 크라켄 꾸미기 ────────────────────────────────────────────
## 곡선을 따라 휘어진 크라켄 촉수 (pts: 뿌리 → 끝). belly(p) = 그 자리에서 빨판이 향할 쪽
func _spline_tentacle(pts: Array, r0: float, belly: Callable, tip := 0.08) -> void:
	var dense: Array = w._catmull(pts, 14)
	var cum := [0.0]
	for i in range(1, dense.size()):
		cum.append(float(cum[i - 1]) + ((dense[i] as Vector3) - (dense[i - 1] as Vector3)).length())
	var total: float = cum[cum.size() - 1]
	var at := func(d: float) -> Vector3:
		var j := 0
		while j < dense.size() - 2 and float(cum[j + 1]) < d:
			j += 1
		var f := (d - float(cum[j])) / maxf(float(cum[j + 1]) - float(cum[j]), 0.0001)
		return (dense[j] as Vector3).lerp(dense[j + 1], clampf(f, 0.0, 1.0))
	var n := 140
	var rad := 18
	var P := []
	var T := []
	for i in n + 1:
		P.append(at.call(total * i / n))
	for i in n + 1:
		var a: Vector3 = P[maxi(i - 1, 0)]
		var b: Vector3 = P[mini(i + 1, n)]
		T.append((b - a).normalized())
	var N := []
	var prev_n := Vector3.ZERO
	for i in n + 1:
		var t: Vector3 = T[i]
		var h: Vector3 = belly.call(P[i])
		var nn := h - t * h.dot(t)
		if nn.length() < 0.05:
			nn = prev_n
		nn = nn.normalized()
		if prev_n != Vector3.ZERO:
			nn = prev_n.lerp(nn, 0.35).normalized()
			nn = (nn - t * nn.dot(t)).normalized()
		N.append(nn)
		prev_n = nn
	var r_at := func(u: float) -> float: return r0 * lerpf(1.0, tip, pow(u, 0.85))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n + 1:
		var u := float(i) / n
		var t: Vector3 = T[i]
		var nn: Vector3 = N[i]
		var bb := t.cross(nn)
		var r: float = r_at.call(u)
		for k in rad + 1:
			var a := float(k) / rad * TAU
			var d := bb * sin(a) + nn * cos(a)
			st.set_normal(d)
			st.set_uv(Vector2(float(k) / rad, u))
			st.set_uv2(Vector2(0, 0))
			st.add_vertex((P[i] as Vector3) + d * r)
	var wv := rad + 1
	for i in n:
		for k in rad:
			var i0 := i * wv + k
			st.add_index(i0); st.add_index(i0 + wv + 1); st.add_index(i0 + 1)
			st.add_index(i0); st.add_index(i0 + wv); st.add_index(i0 + wv + 1)
	var m := ShaderMaterial.new()
	m.shader = w.KrakenArmShader
	m.set_shader_parameter("spline_mode", true)
	m.set_shader_parameter("arm_len", total)
	m.set_shader_parameter("radius", r0)
	m.set_shader_parameter("tip", tip)
	m.set_shader_parameter("pattern_scale", 1.6 / maxf(r0, 0.3))
	var mi := _mi(st.commit(), m, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 빨판 두 줄 (배 쪽, 엇갈려서)
	var xs := []
	var cs := []
	var u := 0.04
	var row := 0
	while u < 0.97:
		var ang := (0.42 if row % 2 == 0 else -0.42) + randf_range(-0.03, 0.03)
		var fi := u * n
		var i := int(fi)
		var t: Vector3 = T[i]
		var nn: Vector3 = N[i]
		var bb := t.cross(nn)
		var r: float = r_at.call(u)
		var nd := (bb * sin(ang) + nn * cos(ang)).normalized()
		var side := t.cross(nd).normalized()
		var sz := r * 0.3 * randf_range(0.92, 1.06)
		var c: Vector3 = (P[i] as Vector3).lerp(P[mini(i + 1, n)], fi - i) + nd * r
		xs.append(Transform3D(Basis(side * sz, nd * sz, t * sz), c))
		cs.append(Color(u, ang, 0.3, 0.0))
		u += r * 0.46 / total
		row += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = w._sucker_mesh()
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_custom_data(k, cs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)


## 구름 아래에서 솟아 뱃전을 넘어와 갑판 가장자리에 축 늘어진 촉수. s = +1 우현 / -1 좌현, along = 끝이 뻗는 쪽 (x)
func _drape(x: float, s: float, along: float, r0: float) -> void:
	var dy := deck_y(x + along * 3.0)
	var hz := func(xx: float, yy: float) -> float: return absf(hull_pt(xx, t_at(xx, yy), 1.0).z)
	var pts := [
		Vector3(x - along * 18.0, CLOUD_Y - 8.0, s * (hw(x) + 22.0)),
		Vector3(x - along * 4.0, CLOUD_Y + 12.0, s * (hw(x) + 15.0)),
		Vector3(x - along * 12.0, -30.0, s * (hw(x) + 9.0)),
		Vector3(x - along * 8.0, -20.0, s * (hz.call(x - along * 8.0, -20.0) + 3.5)),
		Vector3(x - along * 2.5, -10.0, s * (hz.call(x - along * 2.5, -10.0) + 1.8)),
		Vector3(x - along * 0.4, -1.5, s * (hz.call(x, -1.5) + 1.0)),
		Vector3(x, gunwale(x) + 0.8, s * (hw(x) + 0.2)),
		Vector3(x + along * 1.2, dy + 0.9, s * (hb(x) - 1.3)),
		Vector3(x + along * 3.6, dy + 0.55, s * (hb(x) - 2.7)),
		Vector3(x + along * 6.0, dy + 0.45, s * (hb(x) - 2.4)),
		Vector3(x + along * 7.2, dy + 0.55, s * (hb(x) - 1.3)),
		Vector3(x + along * 6.4, dy + 0.75, s * (hb(x) - 0.6)),
		Vector3(x + along * 5.6, dy + 0.9, s * (hb(x) - 1.1)),
	]
	_spline_tentacle(pts, r0, func(p: Vector3) -> Vector3:
		# 선체 옆에선 선체 쪽, 갑판 위에선 아래(갑판) 쪽으로 빨판이 붙음
		var k := smoothstep(gunwale(x) - 1.0, gunwale(x) + 0.5, p.y)
		var on_deck := absf(p.z) < hb(p.x) + 0.2
		return Vector3(0, -1, 0) if on_deck else Vector3(0, -0.4 * k, -s).normalized())


## 뱃전에 걸친 촉수들: [x, 쪽, 끝이 뻗는 쪽, 굵기]
const DRAPES := [[-15.0, 1.0, -1.0, 2.6], [25.0, 1.0, -1.0, 2.2], [-2.0, -1.0, -1.0, 2.6], [48.0, -1.0, -1.0, 1.8],
	[-57.0, 1.0, -1.0, 1.9], [7.0, 1.0, 1.0, 2.3], [44.0, 1.0, 1.0, 1.7], [21.0, -1.0, 1.0, 2.2], [-20.0, -1.0, -1.0, 2.3],
	[-37.0, 1.0, 1.0, 1.9], [-58.0, -1.0, 1.0, 1.7]]


func _kraken_arms() -> void:
	for d in DRAPES:
		_drape(d[0], d[1], d[2], d[3])
	# 짐칸에서 솟아 앞돛대를 칭칭 감아 오른 촉수
	_coil(MASTS[0][0], 0.0, 5.6, 12, 1.25, [Vector3(19.0, -HOLD_DEPTH + 0.5, 2.2), Vector3(20.5, -3.0, 2.8), Vector3(21.6, 0.8, 3.3),
		Vector3(23.6, 3.6, 3.0), Vector3(26.2, 5.0, 2.0)], PI * 0.7)
	# 좌현 밖에서 뒷갑판을 넘어와 뒷돛대를 감은 촉수
	_coil(MASTS[2][0], QD_Y, QD_Y + 5.0, 10, 1.45, [Vector3(-46.0, CLOUD_Y - 6.0, -36.0), Vector3(-40.0, CLOUD_Y + 14.0, -26.0),
		Vector3(-45.0, -22.0, -21.0), Vector3(-42.5, -8.0, -16.6), Vector3(-41.6, QD_Y + 1.0, -15.4), Vector3(-41.3, QD_Y + 5.2, -14.0),
		Vector3(-41.2, QD_Y + 4.6, -9.5), Vector3(-41.6, QD_Y + 4.4, -4.0)], -PI * 0.5)


## 앞쪽 점들(pts)을 지나 돛대(mx)를 나선으로 감아 오르는 촉수
func _coil(mx: float, base_y: float, y0: float, turns_pts: int, r0: float, pts: Array, a0: float) -> void:
	var y := y0
	var a := a0
	var rr := 1.9 + float(MASTS[0][3]) * 0.3
	for k in turns_pts:
		pts.append(Vector3(mx + cos(a) * rr, y, sin(a) * rr))
		a -= 1.25
		y += 0.85
		rr = maxf(rr - 0.06, 1.15)
	_spline_tentacle(pts, r0, func(p: Vector3) -> Vector3:
		var d := Vector3(mx - p.x, 0, -p.z)
		if d.length() < 3.0 and p.y > base_y + 3.0:
			return d.normalized()
		return Vector3(0, -1, 0) if absf(p.z) < hb(p.x) + 0.2 and p.y > -1.0 else Vector3(0, 0, -signf(p.z)))


## 크라켄 숭배 물건들: 금빛 크라켄 상 · 알 둥지 · 표본 병 · 먹물 통 · 뱃전 밖 깃발
func _kraken_things() -> void:
	var stone := smat(Color(0.26, 0.25, 0.28), "masonry", -1.0, Vector3(1, 0, 0), 0.0)
	var green := Color(0.45, 1.0, 0.4)
	# 1) 뒷갑판 가운데 크라켄 상 + 촛불
	var ip := Vector3(-35.5, QD_Y, 0)
	_mi(w._cyl(1.3, 1.6, 0.6, 8), stone, ip + Vector3(0, 0.3, 0))
	_mi(w._cyl(0.9, 1.1, 1.2, 8), stone, ip + Vector3(0, 1.2, 0))
	var idol := Node3D.new()
	idol.position = ip + Vector3(0, 2.15, 0)
	idol.basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -0.15)
	idol.scale = Vector3.ONE * 0.62
	add_child(idol)
	var body := MeshInstance3D.new()
	body.mesh = w.KRAKEN_BODY
	body.material_override = mat(Color(0.85, 0.62, 0.26), 0.35, 0.9)
	idol.add_child(body)
	for sd: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.3
		eye.height = 0.6
		_mi(eye, _glow(Color(0.5, 1.0, 0.35), 4.0), Vector3(sd * 1.57, 0.74, 1.3), Basis(), idol)
	for k in 8:
		var a := TAU * k / 8.0
		var cp := ip + Vector3(cos(a) * 1.9, 0, sin(a) * 1.9)
		var h := 0.3 + 0.25 * float(k % 3)
		_mi(w._cyl(0.07, 0.08, h, 8), mat(Color(0.92, 0.88, 0.76), 0.6), cp + Vector3(0, h * 0.5, 0))
		_mi(SphereMesh.new(), _glow(Color(1.0, 0.7, 0.3), 5.0), cp + Vector3(0, h + 0.07, 0), Basis().scaled(Vector3(0.09, 0.16, 0.09)))
	var il := OmniLight3D.new()
	il.light_color = Color(0.6, 1.0, 0.45)
	il.light_energy = 1.6
	il.omni_range = 8.0
	il.position = ip + Vector3(0, 3.0, 0)
	add_child(il)
	_lamps.append([il, 1.6, 0.7])
	# 2) 크라켄 알 둥지 (밧줄 둥지 위 반투명 초록 알)
	var egg_m := StandardMaterial3D.new()
	egg_m.albedo_color = Color(0.35, 0.75, 0.35, 0.75)
	egg_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	egg_m.emission_enabled = true
	egg_m.emission = Color(0.3, 0.9, 0.3)
	egg_m.emission_energy_multiplier = 1.4
	egg_m.roughness = 0.15
	egg_m.rim_enabled = true
	egg_m.rim = 0.6
	var nest := TorusMesh.new()
	nest.inner_radius = 0.6
	nest.outer_radius = 1.5
	nest.rings = 24
	nest.ring_segments = 10
	for np: Vector3 in [Vector3(6.0, 0, -11.2), Vector3(-12.0, 0, 11.4), Vector3(44.0, FC_Y, 0.0)]:
		_mi(nest, mat(Color(0.5, 0.4, 0.26), 0.95), np + Vector3(0, 0.2, 0), Basis().scaled(Vector3(1.0, 0.7, 1.0)))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(np.x * 10)
		for k in 7:
			var a := TAU * k / 7.0 + rng.randf() * 0.4
			var rr := 0.0 if k == 0 else 0.62
			var e := SphereMesh.new()
			e.radius = 0.36
			e.height = 0.9
			_mi(e, egg_m, np + Vector3(cos(a) * rr, 0.55 + (0.12 if k == 0 else 0.0), sin(a) * rr), Basis(Vector3(1, 0, 0), rng.randf_range(-0.3, 0.3)))
		var el := OmniLight3D.new()
		el.light_color = green
		el.light_energy = 1.2
		el.omni_range = 5.0
		el.position = np + Vector3(0, 1.2, 0)
		add_child(el)
		_lamps.append([el, 1.2, np.x])
	# 3) 표본 병 선반 (초록 물 속 작은 촉수)
	var shelf_p := Vector3(-30.0, QD_Y, -11.6)
	var wood := smat(Color(0.36, 0.23, 0.14), "wood", 0.0, Vector3(1, 0, 0))
	_box(Vector3(3.6, 0.12, 1.0), wood, shelf_p + Vector3(0, 1.0, 0))
	_box(Vector3(3.6, 0.12, 1.0), wood, shelf_p + Vector3(0, 0.1, 0))
	for e: float in [-1.7, 1.7]:
		_box(Vector3(0.12, 1.1, 1.0), wood, shelf_p + Vector3(e, 0.55, 0))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 1.0, 0.75, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.rim_enabled = true
	var liquid := _glow(Color(0.3, 0.85, 0.35), 1.0)
	var curl := TorusMesh.new()
	curl.inner_radius = 0.06
	curl.outer_radius = 0.14
	for row: float in [0.16, 1.06]:
		for k in 4:
			var jp := shelf_p + Vector3(-1.2 + k * 0.8, row, 0)
			var hh := 0.55 + 0.15 * float((k + int(row)) % 2)
			_mi(w._cyl(0.2, 0.2, hh * 0.8, 12), liquid, jp + Vector3(0, hh * 0.4, 0))
			_mi(curl, mat(Color(0.75, 0.4, 0.45), 0.4), jp + Vector3(0, hh * 0.45, 0), Basis(Vector3(1, 0, 0), 1.2))
			_mi(w._cyl(0.24, 0.24, hh, 12), glass, jp + Vector3(0, hh * 0.5, 0))
			_mi(w._cyl(0.18, 0.2, 0.1, 12), smat(Color(0.4, 0.28, 0.16), "wood", 0.0), jp + Vector3(0, hh + 0.05, 0))
	# 4) 먹물 통 (번들번들한 검은 통 + 바닥에 번진 먹물)
	var ink := mat(Color(0.02, 0.02, 0.04), 0.08, 0.2)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.42
	barrel.bottom_radius = 0.46
	barrel.height = 1.15
	barrel.radial_segments = 16
	for bp: Vector3 in [Vector3(-6.5, 0, 11.6), Vector3(14.0, 0, -11.8), Vector3(34.0, 0, 11.4)]:
		if near_tile(bp, 2.0):
			continue
		_mi(barrel, smat(Color(0.12, 0.1, 0.1), "wood", 0.12, Vector3(0, 1, 0)), bp + Vector3(0, 0.58, 0))
		for yy: float in [-0.36, 0.36]:
			_mi(w._cyl(0.47, 0.47, 0.07, 16), iron(), bp + Vector3(0, 0.58 + yy, 0))
		_mi(w._cyl(0.38, 0.38, 0.04, 16), ink, bp + Vector3(0, 1.17, 0))
		_mi(w._cyl(1.3, 1.3, 0.02, 20), ink, bp + Vector3(0.6, 0.02, 0.3), Basis().scaled(Vector3(1.0, 1.0, 0.7)))
	# 5) 뱃전 밖에 늘어뜨린 크라켄 깃발 (선체를 따라 비스듬히)
	for b in [[-30.0, 1.0], [-21.5, 1.0], [14.0, 1.0], [-31.0, -1.0], [30.0, -1.0], [40.0, -1.0]]:
		var bx: float = b[0]
		var sd: float = b[1]
		var g := gunwale(bx)
		var top := hull_pt(bx, t_at(bx, g - 0.35), sd) + Vector3(0, 0, sd * 0.25)
		var bot := hull_pt(bx, t_at(bx, g - 6.8), sd) + Vector3(0, 0, sd * 0.25)
		var up := (top - bot).normalized()
		var outw := Vector3(0, 0, sd)
		outw = (outw - up * outw.dot(up)).normalized()
		var along := up.cross(outw)
		var bas := Basis(along, up, outw)
		_banner(top, bas, Vector2(3.4, (top - bot).length()), bx)


func _banner(top: Vector3, bas: Basis, size: Vector2, seed: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 8
	var nv := 12
	for i in nu:
		for j in nv:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / nu
				var v := float(c[1]) / nv
				# 아랫단은 제비꼬리 (가운데가 파임)
				var y := -v * size.y
				if v > 0.85:
					y += (1.0 - absf(u - 0.5) * 2.0) * (v - 0.85) / 0.15 * size.y * 0.1
				quad.append([Vector3((u - 0.5) * size.x, y, 0), Vector2(u, v)])
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for q in tri:
					st.set_uv(quad[q][1])
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(quad[q][0])
	var m := _sail_mat(size, 0.12, seed, 0.25)
	m.set_shader_parameter("cloth", Color(0.5, 0.08, 0.08))
	m.set_shader_parameter("flutter", 0.04)
	m.set_shader_parameter("emblem", EMBLEM)
	m.set_shader_parameter("emblem_on", 1.0)
	m.set_shader_parameter("emblem_rect", Vector4(0.08, 0.16, 0.84, 0.48))
	_mi(st.commit(), m, top, bas)
	_rod(top + bas * Vector3(-size.x * 0.55, 0.05, 0.05), top + bas * Vector3(size.x * 0.55, 0.05, 0.05), 0.06, gold(), -1.0, 8)


## 등불 꾸미기: 돛대에서 뱃전으로 늘어진 전구 줄 · 갑판 가장자리 등불 기둥 · 층 앞벽 벽등
func _lights_decor() -> void:
	var bulbs := []
	var bulbs_g := []
	var garland := func(a: Vector3, b: Vector3, sag: float, green_every: int) -> void:
		var n := int((b - a).length() / 1.1)
		var prev := a
		for k in range(1, n + 1):
			var f := float(k) / n
			var p := a.lerp(b, f) - Vector3(0, sin(f * PI) * sag, 0)
			rope(prev, p, true)
			if k < n:
				((bulbs_g if green_every > 0 and k % green_every == 0 else bulbs) as Array).append(Transform3D(Basis().scaled(Vector3.ONE * 0.13), p - Vector3(0, 0.12, 0)))
			prev = p
	for mi in [0, 1]:
		var mx: float = MASTS[mi][0]
		var ty: float = float(MASTS[mi][2]) * TOP_K
		for sd: float in [-1.0, 1.0]:
			for dx: float in [-9.0, 9.0]:
				var x2 := mx + dx
				garland.call(Vector3(mx, ty - 0.2, sd * 1.8), Vector3(x2, gunwale(x2) + 0.5, sd * (hw(x2) - 0.1)), 1.6, 4)
	# 돛대 사이 · 앞뒤 갑판으로
	garland.call(Vector3(MASTS[1][0], 14.0, 0), Vector3(MASTS[0][0], 13.0, 0), 2.4, 3)
	garland.call(Vector3(MASTS[1][0], 13.0, 0), Vector3(QD_X, QD_Y + 6.5, 0), 1.8, 3)
	garland.call(Vector3(MASTS[0][0], 12.0, 0), Vector3(FC_X + 9.0, FC_Y + 5.5, 0), 1.6, 3)
	garland.call(Vector3(MASTS[2][0], QD_Y + 13.0, 0), Vector3(PP_X - 4.0, PP_Y + 4.0, 0), 1.2, 3)
	var bm := SphereMesh.new()
	bm.radius = 1.0
	bm.height = 2.0
	bm.radial_segments = 8
	bm.rings = 4
	_multi(bm, _glow(Color(1.0, 0.72, 0.36), 4.5), bulbs)
	_multi(bm, _glow(Color(0.5, 1.0, 0.45), 4.0), bulbs_g)
	# 갑판 가장자리 등불 기둥 (뱃전 길 칸 사이, 바깥쪽)
	var post_m := smat(Color(0.25, 0.16, 0.1), "wood", 0.0, Vector3(0, 1, 0))
	for sd: float in [-1.0, 1.0]:
		for k in LANE_XS().size() - 1:
			var x: float = (LANE_XS()[k] + LANE_XS()[k + 1]) * 0.5
			var skip := false
			for d in DRAPES:
				if float(d[1]) == sd and absf(float(d[0]) + float(d[2]) * 3.0 - x) < 5.5:
					skip = true
			if skip:
				continue
			var p := Vector3(x, 0, sd * (LANE + 2.6))
			if near_tile(p, 1.6):
				continue
			_rod(p, p + Vector3(0, 2.6, 0), 0.08, post_m, 0.1, 8)
			_rod(p + Vector3(0, 2.5, 0), p + Vector3(0, 2.5, -sd * 0.7), 0.05, iron(), -1.0, 6)
			_lantern(p + Vector3(0, 2.0, -sd * 0.7), 0.9, k % 3 == 1, true, Color(1.0, 0.66, 0.3) if k % 2 == 0 else Color(0.55, 1.0, 0.45))
	# 층 앞벽 문 양옆 벽등
	for e in [[FC_X, 0.0, -1.0], [QD_X, 0.0, 1.0], [PP_X, QD_Y, 1.0]]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(float(e[0]) + float(e[2]) * 0.45, float(e[1]) + 2.4, sz * 1.15)
			_lantern(p, 0.7, false, false, Color(0.55, 1.0, 0.45) if e[0] == PP_X else Color(1.0, 0.66, 0.3))


func LANE_XS() -> Array:
	var out := []
	for n in TILES:
		if String(n).begins_with("S") and String(n).substr(1).is_valid_int():
			out.append((TILES[n] as Vector3).x)
	out.sort()
	return out



# ── 크라켄의 보물상자 (뱃머리 끝, 보물상자 칸 바로 앞) ───────────
var chest_lid: Node3D
var chest_light: OmniLight3D
var chest_glow: StandardMaterial3D

func _kraken_chest() -> void:
	var root := Node3D.new()
	root.position = CHEST_AT
	root.basis = Basis(Vector3.UP, -PI * 0.5)       # 상자 앞(+z)이 칸(-x) 쪽을 봄
	add_child(root)
	var cw := 2.8                 # 폭
	var cd := 1.8                 # 깊이
	var ch := 1.25                # 몸통 높이
	var y0 := 0.42                # 받침 위
	var plank := smat(Color(0.36, 0.19, 0.1), "wood", 0.26, Vector3(1, 0, 0), 0.0)
	var plank_side := smat(Color(0.33, 0.17, 0.09), "wood", 0.26, Vector3(0, 0, 1), 0.0)
	var dark := smat(Color(0.14, 0.08, 0.05), "wood", 0.0)
	var brass := mat(Color(0.9, 0.68, 0.3), 0.26, 0.92)
	var iron_m := mat(Color(0.14, 0.13, 0.12), 0.38, 0.85)
	var rivet := SphereMesh.new()
	rivet.radius = 0.045
	rivet.height = 0.07
	rivet.radial_segments = 8
	rivet.rings = 4
	var rivets := []
	# 받침: 금테 두른 검은 나무 단 (둥근 모서리) + 붉은 천
	_mi(w._rbox(Vector3(cw + 1.6, 0.26, cd + 1.6), 0.1), dark, Vector3(0, 0.13, 0), Basis(), root)
	_mi(w._rbox(Vector3(cw + 1.7, 0.06, cd + 1.7), 0.03), brass, Vector3(0, 0.24, 0), Basis(), root)
	_mi(w._rbox(Vector3(cw + 0.9, 0.14, cd + 0.9), 0.06), mat(Color(0.45, 0.06, 0.08), 0.85), Vector3(0, 0.33, 0), Basis(), root)
	# 몸통: 앞뒤는 가로 널, 옆은 세로 결 + 아랫단 굽
	_mi(w._rbox(Vector3(cw, ch, cd), 0.05), plank, Vector3(0, y0 + ch * 0.5, 0), Basis(), root)
	_mi(w._rbox(Vector3(cw + 0.02, ch - 0.1, cd - 0.1), 0.04), plank_side, Vector3(0, y0 + ch * 0.5, 0), Basis(), root)
	_mi(w._rbox(Vector3(cw + 0.12, 0.16, cd + 0.12), 0.04), dark, Vector3(0, y0 + 0.08, 0), Basis(), root)
	_mi(w._rbox(Vector3(cw + 0.1, 0.1, cd + 0.1), 0.03), brass, Vector3(0, y0 + ch - 0.05, 0), Basis(), root)
	# 세로 띠 (몸통 감싼 놋쇠) + 징
	for bx: float in [-cw * 0.36, cw * 0.36]:
		_mi(w._box(Vector3(0.2, ch + 0.02, cd + 0.05)), brass, Vector3(bx, y0 + ch * 0.5, 0), Basis(), root)
		for k in 4:
			var yy := y0 + 0.2 + k * (ch - 0.4) / 3.0
			for sz: float in [-1.0, 1.0]:
				rivets.append(Transform3D(Basis(), Vector3(bx, yy, sz * (cd * 0.5 + 0.03))))
	# 모서리 쇠 장식 (ㄱ자) + 징
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			for cy: float in [0.0, 1.0]:
				var py := y0 + 0.12 + cy * (ch - 0.24)
				_mi(w._box(Vector3(0.36, 0.26, 0.05)), iron_m, Vector3(cx * (cw * 0.5 - 0.16), py, cz * (cd * 0.5 + 0.02)), Basis(), root)
				_mi(w._box(Vector3(0.05, 0.26, 0.36)), iron_m, Vector3(cx * (cw * 0.5 + 0.02), py, cz * (cd * 0.5 - 0.16)), Basis(), root)
				rivets.append(Transform3D(Basis(), Vector3(cx * (cw * 0.5 - 0.22), py, cz * (cd * 0.5 + 0.05))))
	# 옆 손잡이 (쇠고리)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.22
	ring.rings = 24
	ring.ring_segments = 8
	for cx: float in [-1.0, 1.0]:
		_mi(w._box(Vector3(0.06, 0.24, 0.3)), iron_m, Vector3(cx * (cw * 0.5 + 0.03), y0 + ch * 0.62, 0), Basis(), root)
		_mi(ring, iron_m, Vector3(cx * (cw * 0.5 + 0.08), y0 + ch * 0.5, 0), Basis(Vector3(0, 0, 1), PI * 0.5), root)
	# 앞 자물쇠판 + 열쇠 구멍 + 크라켄 눈 보석
	var front := cd * 0.5 + 0.03
	_mi(w._rbox(Vector3(0.56, 0.66, 0.07), 0.05), brass, Vector3(0, y0 + ch - 0.3, front), Basis(), root)
	_mi(w._box(Vector3(0.07, 0.16, 0.02)), mat(Color(0.02, 0.02, 0.02), 0.6), Vector3(0, y0 + ch - 0.42, front + 0.04), Basis(), root)
	_mi(w._cyl(0.05, 0.05, 0.02, 12), mat(Color(0.02, 0.02, 0.02), 0.6), Vector3(0, y0 + ch - 0.33, front + 0.04), Basis(Vector3(1, 0, 0), PI * 0.5), root)
	var gem := SphereMesh.new()
	gem.radius = 0.13
	gem.height = 0.2
	_mi(gem, _glow(Color(0.4, 1.0, 0.35), 3.0), Vector3(0, y0 + ch - 0.13, front + 0.05), Basis(), root)
	_mi(w._box(Vector3(0.03, 0.15, 0.02)), mat(Color(0.02, 0.04, 0.02), 0.3), Vector3(0, y0 + ch - 0.13, front + 0.16), Basis(), root)
	for k in 6:
		var a := TAU * k / 6.0
		rivets.append(Transform3D(Basis(), Vector3(cos(a) * 0.2, y0 + ch - 0.3 + sin(a) * 0.24, front + 0.04)))
	# 안쪽: 넘칠 듯 쌓인 진짜 금화 더미 (한 닢씩 겹겹이 기울어 쌓임 · 빛나지 않는 금속)
	chest_glow = StandardMaterial3D.new()
	chest_glow.albedo_color = Color(0.86, 0.62, 0.24)
	chest_glow.metallic = 1.0
	chest_glow.roughness = 0.4
	chest_glow.emission_enabled = true
	chest_glow.emission = Color(1.0, 0.7, 0.25)
	chest_glow.emission_energy_multiplier = 0.0
	var coin_m := _coin_mesh()
	var coins := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var top_y := y0 + ch - 0.35          # 더미 바닥 (몸통 안)
	var hx := cw * 0.5 - 0.14
	var hz := cd * 0.5 - 0.14
	for layer in 9:
		var ly := top_y + layer * 0.045
		var shrink := 1.0 - pow(layer / 9.0, 1.6) * 0.75     # 위로 갈수록 가운데만 (둥근 더미)
		var n := int(260 * shrink)
		for k in n:
			var u := rng.randf_range(-1, 1) * shrink
			var v := rng.randf_range(-1, 1) * shrink
			var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.55))
			coins.append(Transform3D(tilt.rotated(Vector3.UP, rng.randf() * TAU), Vector3(u * hx, ly + rng.randf() * 0.03, v * hz)))
	# 앞 테두리에 걸쳐 흘러내린 금화
	for k in 26:
		var x := rng.randf_range(-cw * 0.42, cw * 0.42)
		coins.append(Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(0.6, 1.3)).rotated(Vector3.UP, rng.randf_range(-0.4, 0.4)),
			Vector3(x, y0 + ch + 0.02 + rng.randf() * 0.05, cd * 0.5 - 0.05)))
	var cmm := MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.mesh = coin_m
	cmm.instance_count = coins.size()
	for k in coins.size():
		cmm.set_instance_transform(k, coins[k])
	var cmi := MultiMeshInstance3D.new()
	cmi.multimesh = cmm
	cmi.material_override = chest_glow
	root.add_child(cmi)
	# 더미 아래는 어두운 바닥 (틈 사이가 빛나지 않게)
	_mi(w._box(Vector3(cw - 0.12, 0.1, cd - 0.12)), mat(Color(0.12, 0.07, 0.03), 0.9), Vector3(0, top_y - 0.04, 0), Basis(), root)
	for g in [[Color(0.9, 0.08, 0.15), Vector3(-0.7, 0.32, 0.2)], [Color(0.1, 0.8, 0.35), Vector3(0.4, 0.38, -0.25)], [Color(0.15, 0.35, 1.0), Vector3(0.9, 0.28, 0.35)],
			[Color(0.75, 0.2, 1.0), Vector3(-0.2, 0.4, -0.4)], [Color(0.9, 0.08, 0.15), Vector3(1.1, 0.25, -0.3)]]:
		var gm := _glow(g[0], 0.25)
		gm.metallic_specular = 1.0
		gm.roughness = 0.05
		_mi(w._prism(0.2, 0.2, 0.2), gm, Vector3(0, y0 + ch - 0.12, 0) + g[1], Basis(Vector3(rng.randf(), 1, rng.randf()).normalized(), rng.randf() * TAU), root)
	# 진주 목걸이 (앞으로 늘어짐)
	var pearl := SphereMesh.new()
	pearl.radius = 0.045
	pearl.height = 0.09
	pearl.radial_segments = 8
	pearl.rings = 4
	var pearls := []
	for k in 26:
		var f := k / 25.0
		pearls.append(Transform3D(Basis(), Vector3(lerpf(-0.9, 0.2, f), y0 + ch + 0.08 - sin(f * PI) * 0.45 * smoothstep(0.3, 0.6, f), cd * 0.5 + 0.06 * sin(f * PI))))
	_multi_in(root, pearl, mat(Color(0.96, 0.94, 0.9), 0.15, 0.1), pearls)
	# 뚜껑: 반원통 (가로 널) + 끝 마구리 + 놋쇠 띠 3 줄 + 징. 뒤쪽 위 모서리 경첩을 축으로 열림
	chest_lid = Node3D.new()
	chest_lid.position = Vector3(0, y0 + ch, -cd * 0.5)
	root.add_child(chest_lid)
	var lr := cd * 0.5
	_mi(_half_drum(cw, lr, 0.62, 0.0), plank, Vector3(0, 0, lr), Basis(), chest_lid)
	for bx: float in [-cw * 0.36, cw * 0.36]:
		_mi(_half_drum(0.2, lr + 0.025, 0.62, 0.0), brass, Vector3(bx, 0, lr), Basis(), chest_lid)
		for k in 5:
			var a := PI * (k + 0.5) / 5.0
			rivets.append(Transform3D(Basis(), chest_lid.position + Vector3(bx, sin(a) * (lr + 0.04) * 0.62, lr + cos(a) * (lr + 0.04))))
	_mi(_half_drum(cw + 0.1, lr + 0.03, 0.62, 0.0, 0.08), brass, Vector3(0, 0, lr), Basis(), chest_lid)
	_mi(w._box(Vector3(cw + 0.08, 0.08, cd + 0.08)), dark, Vector3(0, 0.04, lr), Basis(), chest_lid)
	# 경첩
	for bx: float in [-cw * 0.36, cw * 0.36]:
		_mi(w._cyl(0.07, 0.07, 0.3, 10), iron_m, Vector3(bx, 0.0, -0.02), Basis(Vector3(0, 0, 1), PI * 0.5), chest_lid)
	_multi_in(root, rivet, brass, rivets.filter(func(x: Transform3D) -> bool: return x.origin.y < y0 + ch + 0.01))
	var lid_rivets := []
	for x: Transform3D in rivets:
		if x.origin.y >= y0 + ch + 0.01:
			lid_rivets.append(Transform3D(x.basis, x.origin - chest_lid.position))
	_multi_in(chest_lid, rivet, brass, lid_rivets)
	chest_lid.rotation.x = -0.22     # 살짝 들린 뚜껑 틈으로 금빛이 새어 나옴
	# 상자를 휘감은 크라켄 촉수 (뒤쪽 갑판에서 기어 올라 옆을 감고 뚜껑 위를 꽉 누름)
	var g := root.global_transform
	var to_ship := func(lp: Vector3) -> Vector3: return (g * lp) - global_transform.origin
	var pts := []
	for lp in [Vector3(-3.4, 0.25, -3.2), Vector3(-2.3, 0.35, -2.0), Vector3(-1.75, 0.8, -1.05), Vector3(-1.62, 1.35, -0.1),
			Vector3(-1.58, 1.65, 0.75), Vector3(-1.1, 2.15, 0.95), Vector3(-0.3, 2.32, 0.6), Vector3(0.45, 2.3, 0.0),
			Vector3(0.95, 2.1, -0.55), Vector3(1.25, 1.85, -0.2), Vector3(1.05, 1.95, 0.2)]:
		pts.append(to_ship.call(lp))
	_spline_tentacle(pts, 0.42, func(p: Vector3) -> Vector3: return ((CHEST_AT + Vector3(0, 1.1, 0)) - p).normalized(), 0.12)
	# 흩어진 금화 · 쌓인 금화 · 보석
	var spill := []
	for k in 60:
		var a := rng.randf_range(-1.3, 1.3)
		var r := rng.randf_range(1.6, 2.9)
		spill.append(Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(-0.25, 0.25)).rotated(Vector3.UP, rng.randf() * TAU),
			Vector3(sin(a) * r, 0.43 if r < 2.3 else 0.27, cos(a) * r * 0.9)))
	for k in 3:
		var sx: float = [-1.6, 1.5, 0.9][k]
		var sz: float = [1.4, 1.3, 1.9][k]
		for q in 5 + k * 2:
			spill.append(Transform3D(Basis().rotated(Vector3.UP, q * 0.7), Vector3(sx + rng.randf_range(-0.02, 0.02), 0.42 + q * 0.032, sz)))
	_multi_in(root, coin_m, chest_glow, spill)
	chest_light = OmniLight3D.new()
	chest_light.light_color = Color(1.0, 0.72, 0.35)
	chest_light.light_energy = 1.6
	chest_light.omni_range = 7.0
	chest_light.position = CHEST_AT + Vector3(0, 2.2, 0)
	add_child(chest_light)
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.8, 0.5)
	gl.light_energy = 0.5
	gl.omni_range = 2.6
	gl.position = Vector3(0, y0 + ch + 0.4, 0.3)
	root.add_child(gl)
	_lantern(CHEST_AT + Vector3(0.6, 1.0, 3.0), 0.8, false, false, Color(0.55, 1.0, 0.45))
	_lantern(CHEST_AT + Vector3(0.6, 1.0, -3.0), 0.8, false, false, Color(0.55, 1.0, 0.45))


## 금화 한 닢: 테두리가 도톰하고 가운데가 살짝 파인 동전 (반지름 0.1)
var _coin: ArrayMesh
func _coin_mesh() -> ArrayMesh:
	if _coin:
		return _coin
	var prof := [Vector2(0.0, 0.009), Vector2(0.07, 0.008), Vector2(0.078, 0.013), Vector2(0.094, 0.014), Vector2(0.1, 0.008),
		Vector2(0.1, -0.008), Vector2(0.094, -0.014), Vector2(0.078, -0.013), Vector2(0.07, -0.008), Vector2(0.0, -0.009)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 18
	for k in prof.size() - 1:
		var p0: Vector2 = prof[k]
		var p1: Vector2 = prof[k + 1]
		for j in seg:
			var a0 := TAU * j / seg
			var a1 := TAU * (j + 1) / seg
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var mid := (v00 + v11) * 0.5
			var out := Vector3(mid.x, mid.y * 6.0, mid.z).normalized()
			ReefKit._tri(st, v00, v01, v11, out)
			ReefKit._tri(st, v00, v11, v10, out)
	st.generate_normals()
	_coin = st.commit()
	return _coin


func _multi_in(parent: Node, mesh: Mesh, m: Material, xs: Array) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	parent.add_child(mmi)


## 반원통 (뚜껑): 길이 ln (x), 반지름 r, 높이 비율 k (둥근 지붕이 납작하게). band > 0 이면 테 (안쪽 없이 바깥 면만, 그 폭만큼)
func _half_drum(ln: float, r: float, k: float, _unused: float, band := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	var hx := ln * 0.5
	var arc := func(a: float) -> Vector2: return Vector2(cos(a) * r, sin(a) * r * k)    # (z, y)
	for i in n:
		var a0 := PI * i / n
		var a1 := PI * (i + 1) / n
		var p0: Vector2 = arc.call(a0)
		var p1: Vector2 = arc.call(a1)
		var o := Vector3(0, (p0.y + p1.y) * 0.5, (p0.x + p1.x) * 0.5).normalized()
		if band > 0.0:
			for e: float in [-1.0, 1.0]:
				# 테의 양쪽 끝 둘레 띠 (x = ±hx 에서 band 폭)
				var xa := e * hx
				var xb := e * (hx - band)
				ReefKit._tri(st, Vector3(xa, p0.y, p0.x), Vector3(xb, p0.y, p0.x), Vector3(xb, p1.y, p1.x), o)
				ReefKit._tri(st, Vector3(xa, p0.y, p0.x), Vector3(xb, p1.y, p1.x), Vector3(xa, p1.y, p1.x), o)
			continue
		ReefKit._tri(st, Vector3(-hx, p0.y, p0.x), Vector3(hx, p0.y, p0.x), Vector3(hx, p1.y, p1.x), o)
		ReefKit._tri(st, Vector3(-hx, p0.y, p0.x), Vector3(hx, p1.y, p1.x), Vector3(-hx, p1.y, p1.x), o)
		if band <= 0.0:
			for e: float in [-1.0, 1.0]:
				ReefKit._tri(st, Vector3(e * hx, 0, 0), Vector3(e * hx, p0.y, p0.x), Vector3(e * hx, p1.y, p1.x), Vector3(e, 0, 0))
	st.generate_normals()
	return st.commit()


## 보물상자 뚜껑 연출: win = 활짝 열리며 금빛, 아니면 크라켄 초록빛으로 쾅
func chest_reveal(win: bool) -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(chest_lid, "rotation:x", -1.7 if win else -1.1, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	chest_light.light_color = Color(1.0, 0.75, 0.35) if win else Color(0.45, 1.0, 0.35)
	t.tween_property(chest_light, "light_energy", 6.0, 0.25)
	t.tween_method(func(v: float) -> void: chest_glow.emission_energy_multiplier = v, 0.0, 0.5 if win else 0.0, 0.3)
	t.chain().tween_interval(1.4)
	t.chain().set_parallel(true)
	t.tween_property(chest_lid, "rotation:x", -0.22, 0.5).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(chest_light, "light_energy", 1.4, 0.6)
	t.tween_method(func(v: float) -> void: chest_glow.emission_energy_multiplier = v, 0.5 if win else 0.0, 0.0, 0.6)



# ── 크라켄의 행운 바퀴 (보물상자 칸의 룰렛): 세워 둔 커다란 칠한 나무 바퀴 ──────
## 바퀴 판 · 놋쇠 칸막이 · 테두리 못(딸깍) · 조타륜 손잡이 · 가운데 금빛 크라켄. 위쪽 가죽 혀가 못에 걸려 튐
var wheel_disc: Node3D
var _wheel_mat: ShaderMaterial
var _flapper: Node3D
var _wheel_r := 0.0
var _wheel_seg := 0
var _wheel_kick := 0.0
var _wheel_hl := -1
var _wheel_t := 0.0
const FortuneShader := preload("res://shaders/fortune_wheel.gdshader")

func _fortune_wheel() -> void:
	var root := Node3D.new()
	root.position = WHEEL_AT
	add_child(root)
	var wood := smat(Color(0.32, 0.18, 0.09), "wood", 0.0, Vector3(0, 1, 0), 0.0)
	var wood_h := smat(Color(0.36, 0.2, 0.1), "wood", 0.0, Vector3(1, 0, 0), 0.0)
	var dark := smat(Color(0.14, 0.08, 0.05), "wood", 0.0)
	var brass := mat(Color(0.9, 0.68, 0.3), 0.24, 0.92)
	var iron_m := mat(Color(0.14, 0.13, 0.12), 0.38, 0.85)
	var c := Vector3(0, WHEEL_H, 0)
	# 받침: 무거운 나무 받침대 + 양쪽 기둥(비스듬히) + 가로대 + 축
	# 받침대는 바퀴 뒤쪽 (앞에서 보면 바퀴를 가리지 않게)
	_mi(w._rbox(Vector3(3.2, 0.32, 1.5), 0.06), dark, Vector3(0, 0.16, -0.75), Basis(), root)
	_mi(w._rbox(Vector3(3.3, 0.06, 1.6), 0.03), brass, Vector3(0, 0.33, -0.75), Basis(), root)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_rod(Vector3(sx * 1.25, 0.3, -0.75 + sz * 0.5), c + Vector3(sx * 0.2, 0, -0.42 + sz * 0.08), 0.09, wood, 0.12, 8, root)
		_mi(w._box(Vector3(0.16, 0.16, 1.1)), wood_h, Vector3(sx * 0.98, 0.95, -0.75), Basis(), root)
	_mi(w._cyl(0.09, 0.09, 0.7, 12), iron_m, c + Vector3(0, 0, -0.3), Basis(Vector3(1, 0, 0), PI * 0.5), root)
	# 위쪽: 가죽 혀를 단 놋쇠 걸이 + 등불
	var top := c + Vector3(0, WHEEL_R + 0.55, 0.0)
	_rod(Vector3(-1.3, 0.3, -1.1), top + Vector3(-0.05, 0.2, -0.32), 0.07, wood, 0.09, 8, root)
	_rod(Vector3(1.3, 0.3, -1.1), top + Vector3(0.05, 0.2, -0.32), 0.07, wood, 0.09, 8, root)
	_mi(w._box(Vector3(0.5, 0.18, 0.7)), wood_h, top + Vector3(0, 0.2, -0.05), Basis(), root)
	_mi(w._box(Vector3(0.54, 0.05, 0.74)), brass, top + Vector3(0, 0.31, -0.05), Basis(), root)
	_flapper = Node3D.new()
	_flapper.position = top + Vector3(0, 0.08, 0.26)
	root.add_child(_flapper)
	_mi(w._cyl(0.05, 0.05, 0.22, 10), brass, Vector3.ZERO, Basis(Vector3(0, 0, 1), PI * 0.5), _flapper)
	var tongue := PrismMesh.new()
	tongue.size = Vector3(0.22, 0.62, 0.05)
	_mi(tongue, mat(Color(0.45, 0.07, 0.05), 0.55), Vector3(0, -0.34, 0), Basis(Vector3(0, 0, 1), PI), _flapper)
	_mi(w._box(Vector3(0.05, 0.5, 0.06)), brass, Vector3(0, -0.28, 0.01), Basis(), _flapper)
	_lantern(top + Vector3(0, 0.75, -0.05), 0.85, true, false, Color(1.0, 0.7, 0.35))
	# 돌아가는 바퀴
	wheel_disc = Node3D.new()
	wheel_disc.position = c
	root.add_child(wheel_disc)
	# 두꺼운 나무 바퀴판 (옆면 나무) + 칠한 앞면
	_mi(w._cyl(WHEEL_R, WHEEL_R, 0.2, 48), wood, Vector3.ZERO, Basis(Vector3(1, 0, 0), PI * 0.5), wheel_disc)
	var face := QuadMesh.new()
	face.size = Vector2(WHEEL_R, WHEEL_R) * 2.0
	_wheel_mat = ShaderMaterial.new()
	_wheel_mat.shader = FortuneShader
	_wheel_mat.set_shader_parameter("chest_tex", w._mip_tex(w.ICONS["treasure"]))
	_wheel_mat.set_shader_parameter("kraken_tex", w._mip_tex(w.ICONS["boss"]))
	_wheel_mat.set_shader_parameter("segs", float(WHEEL_SEGS))
	_wheel_mat.set_shader_parameter("radius", WHEEL_R)
	_mi(face, _wheel_mat, Vector3(0, 0, 0.101), Basis(), wheel_disc)
	# 놋쇠 테 (바깥 · 안쪽) + 칸막이 + 테두리 못
	var rim := TorusMesh.new()
	rim.inner_radius = WHEEL_R - 0.03
	rim.outer_radius = WHEEL_R + 0.09
	rim.rings = 64
	rim.ring_segments = 10
	for rz: float in [-0.06, 0.06]:
		_mi(rim, brass, Vector3(0, 0, rz), Basis(Vector3(1, 0, 0), PI * 0.5), wheel_disc)
	var sw := TAU / WHEEL_SEGS
	var peg := CylinderMesh.new()
	peg.top_radius = 0.04
	peg.bottom_radius = 0.05
	peg.height = 0.2
	peg.radial_segments = 10
	var cap := SphereMesh.new()
	cap.radius = 0.06
	cap.height = 0.1
	for k in WHEEL_SEGS:
		var a := k * sw
		var dir := Vector3(sin(a), cos(a), 0)
		var bas := Basis(Vector3(0, 0, 1), -a)
		# 칸막이: 가운데 축에서 테두리까지 볼록한 놋쇠 띠
		_mi(w._box(Vector3(0.05, WHEEL_R * 0.66, 0.03)), brass, dir * WHEEL_R * 0.57 + Vector3(0, 0, 0.115), bas, wheel_disc)
		# 못 (가죽 혀가 걸림)
		var pp := dir * (WHEEL_R * 0.95) + Vector3(0, 0, 0.2)
		_mi(peg, brass, pp, Basis(Vector3(1, 0, 0), PI * 0.5), wheel_disc)
		_mi(cap, brass, pp + Vector3(0, 0, 0.1), Basis(), wheel_disc)
		# 조타륜 손잡이 (바깥으로 뻗은 나무 손잡이, 칸 사이마다 하나 건너)
		if k % 2 == 0:
			_rod(dir * (WHEEL_R + 0.05), dir * (WHEEL_R + 0.62), 0.06, wood_h, 0.075, 10, wheel_disc)
			_mi(w._cyl(0.085, 0.085, 0.06, 10), brass, dir * (WHEEL_R + 0.12), bas, wheel_disc)
			var knob := SphereMesh.new()
			knob.radius = 0.09
			knob.height = 0.16
			_mi(knob, wood_h, dir * (WHEEL_R + 0.66), Basis(), wheel_disc)
	# 가운데 축: 놋쇠 돔 + 금빛 크라켄
	_mi(w._cyl(0.42, 0.46, 0.14, 32), brass, Vector3(0, 0, 0.14), Basis(Vector3(1, 0, 0), PI * 0.5), wheel_disc)
	var hubring := TorusMesh.new()
	hubring.inner_radius = 0.38
	hubring.outer_radius = 0.48
	hubring.rings = 32
	hubring.ring_segments = 8
	_mi(hubring, brass, Vector3(0, 0, 0.13), Basis(Vector3(1, 0, 0), PI * 0.5), wheel_disc)
	# 가운데 돔 + 크라켄 눈 보석 (세로 동공)
	var dome := SphereMesh.new()
	dome.radius = 0.3
	dome.height = 0.3
	dome.is_hemisphere = true
	_mi(dome, brass, Vector3(0, 0, 0.2), Basis(Vector3(1, 0, 0), PI * 0.5), wheel_disc)
	var gem := SphereMesh.new()
	gem.radius = 0.13
	gem.height = 0.16
	_mi(gem, _glow(Color(0.4, 1.0, 0.32), 2.0), Vector3(0, 0, 0.47), Basis(), wheel_disc)
	_mi(w._box(Vector3(0.035, 0.17, 0.02)), mat(Color(0.02, 0.05, 0.02), 0.3), Vector3(0, 0, 0.55), Basis(), wheel_disc)
	# 바퀴 앞 놋쇠 이름판
	_mi(w._rbox(Vector3(1.3, 0.34, 0.06), 0.04), brass, Vector3(0, 0.55, -0.02), Basis(Vector3(1, 0, 0), -0.25), root)
	# 불빛: 앞에서 바퀴를 비추는 따뜻한 등
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.55)
	l.light_energy = 1.6
	l.omni_range = 6.5
	l.position = c + Vector3(0.6, 0.8, 2.6)
	root.add_child(l)
	_wheel_r = randf() * TAU
	wheel_disc.rotation.z = _wheel_r


## 바퀴를 정면에서 보는 카메라 자리 (월드 좌표): [카메라, 바라볼 곳]
func wheel_view() -> Array:
	var c := global_transform.origin + WHEEL_AT + Vector3(0, WHEEL_H, 0)
	return [c + Vector3(1.3, 0.6, 7.2), c + Vector3(0, 0.15, 0)]


## 바퀴 돌리기: win 이면 보물상자 칸, 아니면 크라켄 칸이 맨 위(가죽 혀 아래)에 멈춤 (await)
func wheel_spin(win: bool) -> void:
	_wheel_hl = -1
	_wheel_mat.set_shader_parameter("highlight", -1)
	var picks := []
	for k in WHEEL_SEGS:
		if (k % 2 == 0) == win:
			picks.append(k)
	var k: int = picks[randi() % picks.size()]
	var sw := TAU / WHEEL_SEGS
	# 앞에서 볼 때 칸 k 가 맨 위로: 바퀴 각도 r ≡ (k + 0.5) · 칸 폭 (반시계로 돌수록 r 증가)
	var base := fposmod(_wheel_r, TAU)
	var want := (k + 0.5) * sw + randf_range(-0.28, 0.28) * sw
	var target := _wheel_r - base + want + TAU * 6.0
	if target - _wheel_r < TAU * 5.5:
		target += TAU
	_wheel_seg = int(floor(_wheel_r / sw))
	var t := create_tween()
	t.tween_method(_set_wheel, _wheel_r, target, 5.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await t.finished
	_wheel_hl = k
	_wheel_t = 0.0
	await get_tree().create_timer(1.2, false).timeout


func _set_wheel(r: float) -> void:
	_wheel_r = r
	wheel_disc.rotation.z = r
	var sw := TAU / WHEEL_SEGS
	var seg := int(floor(r / sw))
	if seg != _wheel_seg:
		_wheel_seg = seg
		Audio.play("tick", 25)
		_wheel_kick = 1.0


func _wheel_process(delta: float) -> void:
	if _flapper == null:
		return
	_wheel_kick = maxf(_wheel_kick - delta * 7.0, 0.0)
	# 못이 왼쪽으로 지나가며 혀를 밀었다가 놓음
	_flapper.rotation.z = -0.55 * sin(clampf(_wheel_kick, 0.0, 1.0) * PI * 0.5)
	if _wheel_hl >= 0:
		_wheel_t += delta
		_wheel_mat.set_shader_parameter("highlight", _wheel_hl)
		_wheel_mat.set_shader_parameter("flash", 0.5 + 0.5 * sin(_wheel_t * 10.0))



# ── 대포 칸 옆 회전 대포: 원하는 상대를 겨눠 포탄을 쏨 ───────────────
var cannons := {}            ## 칸 번호 → {"yaw": Node3D, "pitch": Node3D, "barrel": Node3D, "muzzle": Node3D, "flash": ..., "light": ...}

func _swivel_at(n: String) -> Vector3:
	var t: Vector3 = TILES[n]
	return Vector3(t.x, deck_y(t.x), signf(t.z) * (absf(t.z) + 3.6))


func _near_swivel(p: Vector3) -> bool:
	for n in SPECIAL:
		if SPECIAL[n] == "cannon" and Vector2(p.x - _swivel_at(n).x, p.z - _swivel_at(n).z).length() < 3.2:
			return true
	return false


func _swivel_cannons() -> void:
	var bronze := mat(Color(0.55, 0.36, 0.18), 0.32, 0.9)
	var iron_m := mat(Color(0.13, 0.12, 0.11), 0.4, 0.8)
	var wood := smat(Color(0.3, 0.17, 0.09), "wood", 0.0, Vector3(1, 0, 0), 0.0)
	var dark := smat(Color(0.14, 0.08, 0.05), "wood", 0.0)
	for n in SPECIAL:
		if SPECIAL[n] != "cannon":
			continue
		var at := _swivel_at(n)
		var s := signf(at.z)
		var root := Node3D.new()
		root.position = at
		add_child(root)
		# 돌림판: 쇠테 두른 둥근 나무 받침 + 축
		_mi(w._cyl(1.05, 1.15, 0.22, 32), dark, Vector3(0, 0.11, 0), Basis(), root)
		var ring := TorusMesh.new()
		ring.inner_radius = 1.02
		ring.outer_radius = 1.14
		ring.rings = 40
		ring.ring_segments = 8
		_mi(ring, iron_m, Vector3(0, 0.2, 0), Basis(), root)
		var yaw := Node3D.new()
		yaw.position = Vector3(0, 0.22, 0)
		yaw.rotation.y = PI if s > 0.0 else 0.0     # 처음엔 배 안쪽을 봄 (+z 앞)
		root.add_child(yaw)
		# 바퀴 달린 나무 포가 (양쪽 볼판 + 굴대 + 바퀴 4)
		for sx: float in [-1.0, 1.0]:
			_mi(w._box(Vector3(0.14, 0.7, 1.7)), wood, Vector3(sx * 0.42, 0.42, 0.0), Basis(), yaw)
			for sz: float in [-0.55, 0.6]:
				_mi(w._cyl(0.28, 0.28, 0.12, 16), dark, Vector3(sx * 0.58, 0.28, sz), Basis(Vector3(0, 0, 1), PI * 0.5), yaw)
				_mi(w._cyl(0.08, 0.08, 0.14, 8), iron_m, Vector3(sx * 0.62, 0.28, sz), Basis(Vector3(0, 0, 1), PI * 0.5), yaw)
		_mi(w._box(Vector3(0.84, 0.16, 1.4)), wood, Vector3(0, 0.22, 0), Basis(), yaw)
		# 포신 (앞으로 +z): 굵은 뒤 → 가는 앞 + 고리 띠 + 포구 + 뒤 꼭지
		var pitch := Node3D.new()
		pitch.position = Vector3(0, 0.82, -0.1)
		yaw.add_child(pitch)
		var barrel := Node3D.new()
		pitch.add_child(barrel)
		_rod(Vector3(0, 0, -0.85), Vector3(0, 0, 1.9), 0.17, bronze, 0.3, 20, barrel)
		for bz: float in [-0.7, -0.25, 0.6, 1.75]:
			var rr := lerpf(0.33, 0.21, (bz + 0.85) / 2.75)
			_mi(w._cyl(rr, rr, 0.1, 20), bronze, Vector3(0, 0, bz), Basis(Vector3(1, 0, 0), PI * 0.5), barrel)
		var muzzle_ring := TorusMesh.new()
		muzzle_ring.inner_radius = 0.12
		muzzle_ring.outer_radius = 0.24
		muzzle_ring.rings = 24
		muzzle_ring.ring_segments = 10
		_mi(muzzle_ring, bronze, Vector3(0, 0, 1.92), Basis(Vector3(1, 0, 0), PI * 0.5), barrel)
		_mi(w._cyl(0.11, 0.11, 0.06, 16), mat(Color(0.02, 0.02, 0.02), 0.9), Vector3(0, 0, 1.95), Basis(Vector3(1, 0, 0), PI * 0.5), barrel)
		var knob := SphereMesh.new()
		knob.radius = 0.13
		knob.height = 0.26
		_mi(knob, bronze, Vector3(0, 0, -1.0), Basis(), barrel)
		_mi(w._cyl(0.06, 0.06, 0.95, 10), iron_m, Vector3(0, 0, 0), Basis(Vector3(0, 0, 1), PI * 0.5), barrel)   # 귀축
		var muzzle := Node3D.new()
		muzzle.position = Vector3(0, 0, 2.05)
		barrel.add_child(muzzle)
		var fl := _glow(Color(1.0, 0.72, 0.3), 8.0)
		var flash := MeshInstance3D.new()
		var fs := SphereMesh.new()
		fs.radius = 0.5
		fs.height = 1.0
		flash.mesh = fs
		flash.material_override = fl
		flash.visible = false
		muzzle.add_child(flash)
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.7, 0.35)
		lt.light_energy = 0.0
		lt.omni_range = 9.0
		muzzle.add_child(lt)
		# 포탄 더미 + 화약 통 + 꽂아 둔 꽂을대
		var ball := SphereMesh.new()
		ball.radius = 0.16
		ball.height = 0.32
		for q in 4:
			_mi(ball, iron_m, Vector3((q % 2) * 0.34 - 0.17 + 1.3, 0.16 + (q / 3) * 0.26, -0.4 + (q / 2) * 0.3 * float(q < 3)), Basis(), root)
		_mi(w._cyl(0.3, 0.32, 0.6, 14), smat(Color(0.3, 0.18, 0.1), "wood", 0.12, Vector3(0, 1, 0)), Vector3(-1.35, 0.3, 0.3), Basis(), root)
		_rod(Vector3(-1.2, 0.05, -0.7), Vector3(-1.0, 2.0, -0.95), 0.03, wood, -1.0, 6, root)
		cannons[ids[n]] = {"yaw": yaw, "pitch": pitch, "barrel": barrel, "muzzle": muzzle, "flash": flash, "light": lt}


signal cannon_fired(fly: float)


## 대포 칸(tile)의 대포가 target(월드 좌표)을 겨눠 쏨 → 포탄이 날아가 터질 때까지 (await)
func cannon_fire(tile: int, target: Vector3) -> void:
	var c: Dictionary = cannons[tile]
	var yaw: Node3D = c["yaw"]
	var pitch: Node3D = c["pitch"]
	var barrel: Node3D = c["barrel"]
	var muzzle: Node3D = c["muzzle"]
	# 겨누기 (끼익 돌아감)
	var from := yaw.global_transform.origin
	var d := target - from
	var want := atan2(d.x, d.z)
	var cur := yaw.rotation.y
	var goal := cur + angle_difference(cur, want)
	var dist := Vector2(d.x, d.z).length()
	Audio.play("creak")
	var t := create_tween().set_parallel(true)
	t.tween_property(yaw, "rotation:y", goal, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(pitch, "rotation:x", -clampf(0.12 + dist * 0.006, 0.12, 0.45), 0.8).set_trans(Tween.TRANS_CUBIC)
	await t.finished
	await get_tree().create_timer(0.35, false).timeout
	# 쾅: 불꽃 · 빛 · 반동 · 연기
	Audio.play("cannon")
	var flash: MeshInstance3D = c["flash"]
	var lt: OmniLight3D = c["light"]
	flash.visible = true
	flash.scale = Vector3.ONE * 0.3
	var ft := create_tween().set_parallel(true)
	ft.tween_property(flash, "scale", Vector3.ONE * 1.4, 0.08)
	ft.tween_property(lt, "light_energy", 8.0, 0.05)
	ft.chain().set_parallel(true)
	ft.tween_property(flash, "scale", Vector3.ONE * 0.01, 0.18)
	ft.tween_property(lt, "light_energy", 0.0, 0.35)
	ft.chain().tween_callback(func() -> void: flash.visible = false)
	var rt := create_tween()
	rt.tween_property(barrel, "position:z", -0.45, 0.06)
	rt.tween_property(barrel, "position:z", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var mp := muzzle.global_transform.origin
	var fwd := (muzzle.global_transform.basis.z).normalized()
	_smoke(mp - global_transform.origin, fwd, 0.45)
	# 포탄: 포물선으로 날아감
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.2
	bm.height = 0.4
	ball.mesh = bm
	ball.material_override = mat(Color(0.08, 0.08, 0.08), 0.35, 0.8)
	add_child(ball)
	var a := mp - global_transform.origin
	var b := target - global_transform.origin
	var fly := clampf(dist / 26.0, 0.55, 1.4)
	var apex := 1.5 + dist * 0.18
	cannon_fired.emit(fly)
	Audio.play("whoosh")
	var bt := create_tween()
	bt.tween_method(func(f: float) -> void:
		ball.position = a.lerp(b, f) + Vector3(0, sin(f * PI) * apex, 0), 0.0, 1.0, fly)
	await bt.finished
	ball.queue_free()
	# 터짐: 빛 · 연기 · 파편
	Audio.play("explode")
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.6, 0.3)
	bl.light_energy = 7.0
	bl.omni_range = 8.0
	bl.position = b + Vector3(0, 0.8, 0)
	add_child(bl)
	create_tween().tween_property(bl, "light_energy", 0.0, 0.6).finished.connect(bl.queue_free)
	# 불덩이: 순간 부풀었다 꺼짐
	var fb := MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.5
	fs.height = 1.0
	fb.mesh = fs
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1.0, 0.62, 0.22, 0.95)
	fb.material_override = fm
	fb.position = b + Vector3(0, 0.3, 0)
	fb.scale = Vector3.ONE * 0.4
	add_child(fb)
	var fbt := create_tween().set_parallel(true)
	fbt.tween_property(fb, "scale", Vector3.ONE * 2.6, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	fbt.tween_property(fm, "albedo_color", Color(1.0, 0.35, 0.1, 0.0), 0.38)
	fbt.chain().tween_callback(fb.queue_free)
	_smoke(b, Vector3.UP, 1.6)
	_debris(b)


## 화약 연기 (회색 뭉게연기가 퍼지며 사라짐)
func _smoke(p: Vector3, dir: Vector3, amount: float) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = int(22 * amount)
	cp.lifetime = 2.2
	cp.explosiveness = 0.9
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.emission_sphere_radius = 0.3
	cp.direction = dir
	cp.spread = 35.0
	cp.initial_velocity_min = 1.5
	cp.initial_velocity_max = 5.0
	cp.damping_min = 3.0
	cp.damping_max = 5.0
	cp.gravity = Vector3(0, 0.6, 0)
	cp.scale_amount_min = 1.2
	cp.scale_amount_max = 2.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	cp.scale_amount_curve = sc
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := ShaderMaterial.new()
	m.shader = SmokeShader
	m.set_shader_parameter("opacity", clampf(0.25 + amount * 0.25, 0.3, 0.65))
	m.set_shader_parameter("tint", Color(0.4, 0.39, 0.4))
	q.material = m
	cp.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.6, 0.9))
	g.add_point(0.15, Color(0.75, 0.75, 0.78, 0.7))
	g.set_color(1, Color(0.6, 0.6, 0.65, 0.0))
	cp.color_ramp = g
	cp.position = p
	add_child(cp)
	cp.emitting = true
	get_tree().create_timer(3.0).timeout.connect(cp.queue_free)


func _debris(p: Vector3) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = 26
	cp.lifetime = 1.2
	cp.explosiveness = 1.0
	cp.direction = Vector3.UP
	cp.spread = 70.0
	cp.initial_velocity_min = 4.0
	cp.initial_velocity_max = 8.0
	cp.gravity = Vector3(0, -14, 0)
	cp.angular_velocity_min = -400
	cp.angular_velocity_max = 400
	cp.scale_amount_min = 0.5
	cp.scale_amount_max = 1.2
	var bx := BoxMesh.new()
	bx.size = Vector3(0.12, 0.04, 0.3)
	bx.material = mat(Color(0.42, 0.28, 0.16), 0.8)
	cp.mesh = bx
	cp.position = p + Vector3(0, 0.3, 0)
	add_child(cp)
	cp.emitting = true
	get_tree().create_timer(2.0).timeout.connect(cp.queue_free)
