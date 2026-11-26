extends "res://scripts/minigames/minigame_3d.gd"
## 동굴 탈출 (A/D 또는 ←/→ 이동 · 스페이스(또는 W/↑) 점프): 바닷가 동굴을 옆에서 본 레이스.
## 왼쪽 입구에서 오른쪽 출구(햇빛)까지 장애물 구간을 지나 먼저 빠져나간 순서대로 순위.
## 구간: 움직이는 발판(물웅덩이 위) → 흔들리는 닻 → 가라앉는 부목 → 솟구치는 물기둥 → 낙석 → 게 떼 → 출구.
## 물웅덩이에 빠지면 1초 동안 조작 불가 → 그 구간 시작 땅으로 옮겨짐 (탈락 없음, 시간만 손해).
## 장애물은 계속 반복 (부목은 밟으면 가라앉았다 다시 떠오름). 뒤에서 밀물이 따라옴 → 잡히면 물속을 걷느라 느려짐.
## 화면은 각자 내 말을 따라감. 서로 부딪히면 살짝 밀림.

const RUN := 6.2
const ACC_G := 42.0
const ACC_A := 20.0
const GRAV := 24.0
const JUMP := 9.0
const HW := 0.3                 ## 말 반 너비 (충돌)
const PH := 1.15                ## 말 키 (충돌)
const WATER_Y := -1.3           ## 웅덩이 물높이
const FALL_Y := -0.9            ## 이보다 내려가면 빠짐
const FINISH_X := 104.0
const TIDE_START := 5.0         ## 밀물이 들어오기 시작하는 시각
const TIDE_SPEED := 2.5
## 땅 (x0, x1, 윗면 y): 사이사이가 물웅덩이
const GROUND := [[-8.0, 8.0, 0.0], [20.0, 37.0, 0.0], [28.6, 29.5, 0.75], [51.0, 70.0, 0.0], [70.0, 86.0, 0.0], [86.0, 101.0, 0.0], [101.0, 118.0, 0.0]]
## 웅덩이 (x0, x1, 빠지면 돌아갈 자리 x)
const PITS := [[8.0, 20.0, 6.6], [37.0, 51.0, 35.6]]
const ANCHORS := [[25.6, 0.0], [32.4, 1.6]]          ## x, 위상
const LOGS := [39.3, 42.6, 45.9, 49.2]
const GEYSERS := [[54.0, 0.0], [57.8, 0.85], [61.6, 1.7], [65.4, 0.4]]
const GEY_T := 2.5              ## 물기둥 주기 (쉼 → 1.0 부글 → 1.7 솟구침)
const GEY_WARN := 1.0
const GEY_ON := 1.7
const ROCKS := [[72.6, 0.0], [75.9, 0.7], [79.2, 1.4], [82.5, 0.35]]
const ROCK_T := 2.0             ## 낙석 주기 (1.15 그림자 → 1.65 떨어짐 → 2.0 쾅)
const ROCK_WARN := 1.15
const ROCK_FALL := 1.65
const CRABS := [[87.6, 90.8, 3.0, 0.0], [90.8, 94.0, 3.4, 1.3], [94.2, 97.4, 3.1, 2.6], [97.4, 100.4, 3.6, 0.7]]
const LOG_HALF := 0.95         ## 부목 반 길이
const LOG_SINK := 0.8           ## 이만큼 올라서 있으면 가라앉음
const PLAT_HALF := 0.85         ## 움직이는 발판 반 길이
const ANCHOR_PIVOT_Y := 7.6
const ANCHOR_L := 6.0

var _el := 0.0
var _P := {}                    ## slot → 말 상태
var _ai := {}
var _done_n := 0
var _send := 0.0
var _jump_buf := 0.0
var _logs: Array = []           ## [{trig, node}]
var _anchors: Array = []        ## [{root}]
var _geysers: Array = []        ## [{col, spray, bubbles, mat}]
var _rocks: Array = []          ## [{rock, shadow, smat, hit}]
var _crabs: Array = []          ## [{node, legs, last_x}]
var _plats: Array = []          ## 움직이는 발판 노드
var _tide: Node3D
var _tide_foam: CPUParticles3D
var _cam_x := 0.0
var _cam_y := 1.0
var _pool_lights: Array = []
var _batches := {}
static var _mesh_cache := {}    ## 동굴 지형 메시는 매번 같음 → 한 번 만들어 두고 다시 씀 (설명창 데모 · 본게임)


func _init() -> void:
	title = "CAVE RUN"
	how_to = "Race through the sea cave to the sunlit exit! Ride the moving planks, dodge the swinging anchors, hop across the sinking logs, watch out for water spouts, falling rocks and pinching crabs. Fall into the water and you'll be put back at the start of that section. The tide is coming in behind you - don't dawdle!"
	goal = "Get out of the cave first!"
	controls = "SIDE_JUMP"
	duration = 60.0


# ── 무대 ────────────────────────────────────────────────────
func _build_stage() -> void:
	env_sea_day()
	# 동굴 안: 하늘은 안 보이고 어둑어둑. 천장 틈 빛줄기 · 벽 횃불 · 출구 햇빛
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.58, 0.64)
	env.ambient_light_energy = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.1, 0.13)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	sun.light_color = Color(0.85, 0.92, 1.0)
	sun.light_energy = 0.35
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-62, 20, 0)
	# 앞쪽(화면 쪽)에서 은은하게 비추는 빛: 동굴 안 반사광 (그림자 없이)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.8, 0.88)
	fill.light_energy = 0.85
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-32, 8, 0)
	world3.add_child(fill)
	cam.fov = 48.0
	_place_cam(true)
	_build_cave()
	_build_hazards()
	_flush_batches()
	_build_tide()


func _rock_m(c: Color, moss: float = 0.5) -> ShaderMaterial:
	return stone_mat(c, "stone", moss)


## 동굴 바위 재질 (지층 · 젖음 · 이끼 셰이더)
func _cave_mat(base: Color, moss: float = 0.4, drip_: float = 0.5, glow_: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/cave_rock.gdshader")
	m.set_shader_parameter("base_col", base)
	m.set_shader_parameter("dark_col", base.darkened(0.55))
	m.set_shader_parameter("water_y", WATER_Y)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("drip", drip_)
	m.set_shader_parameter("glow", glow_)
	return m


## 단면(profile: (z, y) 점들)을 x 방향으로 쭉 이어 만든 울퉁불퉁한 바위 면.
## amp(j): 그 점을 노이즈로 얼마나 들쑥날쑥하게 할지. hint_sign: 바깥(보이는 쪽) 방향
func _sweep(x0: float, x1: float, step: float, prof: Array, amps: Array, nz: FastNoiseLite, hint_up: bool) -> ArrayMesh:
	var key := "sw|%s|%s|%s|%s|%s|%d|%s" % [x0, x1, step, prof, amps, nz.seed, hint_up]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var made := _sweep_make(x0, x1, step, prof, amps, nz, hint_up)
	_mesh_cache[key] = made
	return made


func _sweep_make(x0: float, x1: float, step: float, prof: Array, amps: Array, nz: FastNoiseLite, hint_up: bool) -> ArrayMesh:
	var nx := maxi(2, int(ceil((x1 - x0) / step)) + 1)
	var np := prof.size()
	var P := []
	for i in nx:
		var x := lerpf(x0, x1, float(i) / (nx - 1))
		var row := []
		for j in np:
			var a: Vector2 = prof[j]
			var b: Vector2 = prof[mini(j + 1, np - 1)]
			var c: Vector2 = prof[maxi(j - 1, 0)]
			var t := (b - c).normalized()
			# 단면에서의 바깥 방향: hint_up 이면 (진행 방향 기준) 위 · 앞쪽, 아니면 안쪽(동굴 속)
			var nrm := Vector2(-t.y, t.x) if hint_up else Vector2(t.y, -t.x)
			var amp := float(amps[j])
			var d := nz.get_noise_3d(x, a.y, a.x) * amp + nz.get_noise_3d(x * 3.1, a.y * 3.1, a.x * 3.1) * amp * 0.35
			var q := a + nrm * d
			row.append(Vector3(x + nz.get_noise_3d(a.x * 2.0, a.y * 2.0, x) * amp * 0.3, q.y, q.x))
		P.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nx - 1:
		for j in np - 1:
			var a: Vector3 = P[i][j]
			var b: Vector3 = P[i + 1][j]
			var c: Vector3 = P[i + 1][j + 1]
			var d: Vector3 = P[i][j + 1]
			var pa: Vector2 = prof[j]
			var pb: Vector2 = prof[j + 1]
			var t := (pb - pa).normalized()
			var n2 := Vector2(-t.y, t.x) if hint_up else Vector2(t.y, -t.x)
			var hint := Vector3(0, n2.y, n2.x)
			for tri: Array in [[a, b, c], [a, c, d]]:
				var v0: Vector3 = tri[0]
				var v1: Vector3 = tri[1]
				var v2: Vector3 = tri[2]
				# Godot 앞면 = 시계 방향 → 기하 노멀이 바깥과 반대가 되게 정렬
				if (v1 - v0).cross(v2 - v0).dot(hint) > 0.0:
					var tmp := v1
					v1 = v2
					v2 = tmp
				st.add_vertex(v0)
				st.add_vertex(v1)
				st.add_vertex(v2)
	st.index()
	st.generate_normals()
	return st.commit()


## 땅 한 덩어리: 뒤쪽은 바위가 솟고, 가운데(달리는 길)는 거의 평평, 앞은 둥근 턱 → 깎아지른 바위 절벽
func _ground_mesh(x0: float, x1: float, top: float, nz: FastNoiseLite, mat: Material) -> void:
	var prof := [Vector2(-3.2, top + 1.3), Vector2(-2.7, top + 0.7), Vector2(-2.2, top + 0.25), Vector2(-1.7, top + 0.05),
		Vector2(-1.2, top), Vector2(-0.4, top), Vector2(0.4, top), Vector2(1.2, top), Vector2(1.7, top - 0.02),
		Vector2(2.05, top - 0.12), Vector2(2.25, top - 0.4), Vector2(2.3, top - 1.2), Vector2(2.35, top - 2.2),
		Vector2(2.3, top - 3.3), Vector2(2.4, top - 4.6)]
	var amps := [0.45, 0.35, 0.22, 0.06, 0.02, 0.015, 0.015, 0.02, 0.05, 0.1, 0.18, 0.3, 0.32, 0.3, 0.3]
	var mi := MeshInstance3D.new()
	mi.mesh = _sweep(x0, x1, 0.25, prof, amps, nz, true)
	mi.material_override = mat
	world3.add_child(mi)
	# 웅덩이 쪽 끝면: 울퉁불퉁한 절벽 (위 → 아래로 층층이)
	for side: int in [0, 1]:
		var ex := x0 if side == 0 else x1
		var out := -1.0 if side == 0 else 1.0
		var ekey := "end|%s|%s|%d" % [ex, top, nz.seed]
		if _mesh_cache.has(ekey):
			var cm := MeshInstance3D.new()
			cm.mesh = _mesh_cache[ekey]
			cm.material_override = mat
			world3.add_child(cm)
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var zs := 12
		var ys := 10
		var G := []
		for a in zs + 1:
			var z := lerpf(-2.9, 2.35, float(a) / zs)
			var col := []
			for b in ys + 1:
				var y := lerpf(top + (0.0 if absf(z) < 1.8 else 0.3), top - 4.6, float(b) / ys)
				var dx := nz.get_noise_3d(ex * 2.0, y * 1.5, z * 1.5) * 0.18 + 0.04
				if b == 0:
					dx = 0.0
				col.append(Vector3(ex + out * dx, y, z))
			G.append(col)
		for a in zs:
			for b in ys:
				var p0: Vector3 = G[a][b]
				var p1: Vector3 = G[a + 1][b]
				var p2: Vector3 = G[a + 1][b + 1]
				var p3: Vector3 = G[a][b + 1]
				var hint := Vector3(out, 0, 0)
				for tri: Array in [[p0, p1, p2], [p0, p2, p3]]:
					var v0: Vector3 = tri[0]
					var v1: Vector3 = tri[1]
					var v2: Vector3 = tri[2]
					if (v1 - v0).cross(v2 - v0).dot(hint) > 0.0:
						var tmp := v1
						v1 = v2
						v2 = tmp
					st.add_vertex(v0)
					st.add_vertex(v1)
					st.add_vertex(v2)
		st.index()
		st.generate_normals()
		var em := MeshInstance3D.new()
		em.mesh = st.commit()
		_mesh_cache[ekey] = em.mesh
		em.material_override = mat
		world3.add_child(em)


## 울퉁불퉁한 바위 덩어리 (구를 노이즈로 찌그러뜨림)
func _boulder(c: Vector3, size: Vector3, nz: FastNoiseLite, mat: Material, seed_: float) -> MeshInstance3D:
	var key := "bo|%s|%s|%d" % [size, seed_, nz.seed]
	if _mesh_cache.has(key):
		var mc := MeshInstance3D.new()
		mc.mesh = _mesh_cache[key]
		mc.material_override = mat
		mc.position = c
		world3.add_child(mc)
		return mc
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	var arr := sm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for k in vs.size():
		var v := vs[k]
		var d := 1.0 + nz.get_noise_3d(v.x * 1.7 + seed_, v.y * 1.7, v.z * 1.7) * 0.35 + nz.get_noise_3d(v.x * 5.0, v.y * 5.0 + seed_, v.z * 5.0) * 0.08
		v = v * d
		if v.y < -0.3:
			v.y = -0.3 + (v.y + 0.3) * 0.3   # 바닥은 납작
		vs[k] = v * size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k in idx.size():
		st.add_vertex(vs[idx[k]])
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_mesh_cache[key] = mi.mesh
	mi.material_override = mat
	mi.position = c
	world3.add_child(mi)
	return mi


## 종유석 하나 (끝에 물방울이 맺힘)
## 종유석 · 석순 · 물방울: 하나씩 노드로 만들지 않고 모아 뒀다가 재질별로 한 번에 그림 (MultiMesh)
func _stalactite(p: Vector3, len: float, r: float, mat: Material, drop_mat: Material, up: bool = false) -> void:
	var sgn := -1.0 if not up else 1.0
	var b := Basis(Vector3.FORWARD, randf_range(-0.08, 0.08)).scaled(Vector3(r, len, r * randf_range(0.7, 1.0)))
	_batch(mat, "up" if up else "down", Transform3D(b, p + Vector3(0, sgn * len * 0.5, 0)))
	if not up and randf() < 0.6:
		_batch(drop_mat, "drop", Transform3D(Basis(), p + Vector3(0, -len - 0.02, 0)))


func _batch(mat: Material, kind: String, xf: Transform3D) -> void:
	var key := "%d|%s" % [mat.get_instance_id(), kind]
	if not _batches.has(key):
		_batches[key] = {"mat": mat, "kind": kind, "xf": []}
	(_batches[key]["xf"] as Array).append(xf)


func _flush_batches() -> void:
	for key in _batches:
		var B: Dictionary = _batches[key]
		var mesh: Mesh
		match String(B["kind"]):
			"down", "up":
				var cm := CylinderMesh.new()
				cm.top_radius = 1.0 if B["kind"] == "down" else 0.0
				cm.bottom_radius = 0.0 if B["kind"] == "down" else 1.0
				cm.height = 1.0
				cm.radial_segments = 9
				cm.rings = 3
				mesh = cm
			_:
				var d := SphereMesh.new()
				d.radius = 0.035
				d.height = 0.08
				d.radial_segments = 8
				d.rings = 4
				mesh = d
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var xs: Array = B["xf"]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = B["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world3.add_child(mmi)
	_batches.clear()


func _build_cave() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 9
	seed(9)
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 0.45
	nz.fractal_octaves = 3
	var ground_m := _cave_mat(Color(0.4, 0.37, 0.33), 0.45, 0.35)
	var wall_m := _cave_mat(Color(0.37, 0.34, 0.31), 0.25, 0.8, 0.7)
	var drop_m := StandardMaterial3D.new()
	drop_m.albedo_color = Color(0.8, 0.9, 1.0, 0.6)
	drop_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_m.roughness = 0.02
	drop_m.metallic_specular = 1.0
	# 땅 덩어리들 (턱 바위는 둥근 바위로)
	var runs := []   # 맞닿은 평지는 한 덩어리로 (이음매 없이)
	for g: Array in GROUND:
		if float(g[2]) > 0.01:
			_boulder(Vector3((float(g[0]) + float(g[1])) * 0.5, 0.05, 0), Vector3((float(g[1]) - float(g[0])) * 0.62, 0.75, 1.9), nz, ground_m, 3.0)
			continue
		if not runs.is_empty() and absf(float(runs[runs.size() - 1][1]) - float(g[0])) < 0.01:
			runs[runs.size() - 1][1] = float(g[1])
		else:
			runs.append([float(g[0]), float(g[1])])
	for r: Array in runs:
		_ground_mesh(float(r[0]), float(r[1]), 0.0, nz, ground_m)
	# 웅덩이: 잔물결 · 물가 거품이 이는 물 + 앞쪽 물에 잠긴 바위 턱
	for pt: Array in PITS:
		var x0 := float(pt[0])
		var x1 := float(pt[1])
		var w := ocean(WATER_Y, 1.0)
		var pm := PlaneMesh.new()
		pm.size = Vector2(x1 - x0 + 0.4, 5.4)
		pm.subdivide_width = int((x1 - x0) * 3.0)
		pm.subdivide_depth = 14
		w.mesh = pm
		w.position = Vector3((x0 + x1) * 0.5, WATER_Y, -0.2)
		var om := w.material_override as ShaderMaterial
		om.set_shader_parameter("amp", 0.04)
		om.set_shader_parameter("choppy", 0.2)
		om.set_shader_parameter("speed", 0.6)
		om.set_shader_parameter("crest_foam", 0.0)
		om.set_shader_parameter("edge_foam", 0.25)
		om.set_shader_parameter("deep", Color(0.0, 0.04, 0.05))
		om.set_shader_parameter("shallow", Color(0.02, 0.17, 0.17))
		om.set_shader_parameter("sss_col", Color(0.03, 0.3, 0.27))
		var rim := MeshInstance3D.new()
		rim.mesh = _sweep(x0 - 0.3, x1 + 0.3, 0.3, [Vector2(1.9, WATER_Y - 2.0), Vector2(2.1, WATER_Y - 0.3), Vector2(2.3, WATER_Y + 0.12), Vector2(2.6, WATER_Y + 0.02), Vector2(2.75, WATER_Y - 0.6), Vector2(2.8, WATER_Y - 3.5)],
			[0.1, 0.12, 0.1, 0.12, 0.2, 0.2], nz, true)
		rim.material_override = ground_m
		world3.add_child(rim)
		# 물 아래 깊은 바닥 (어둡게)
		box(Vector3(x1 - x0, 0.3, 5.0), std_mat(Color(0.02, 0.03, 0.035), 0.9), Vector3((x0 + x1) * 0.5, WATER_Y - 3.4, 0), Basis(), world3)
		# 물빛이 바위에 일렁임
		var cl := OmniLight3D.new()
		cl.light_color = Color(0.35, 0.75, 0.7)
		cl.light_energy = 0.9
		cl.omni_range = 6.0
		cl.position = Vector3((x0 + x1) * 0.5, WATER_Y + 0.6, 0.5)
		world3.add_child(cl)
		_pool_lights.append(cl)
	# 뒷벽 → 천장으로 이어지는 아치 (지층 · 굴곡 · 발광 이끼)
	var arch := [Vector2(-2.6, -0.6), Vector2(-3.4, 0.6), Vector2(-3.9, 2.2), Vector2(-4.0, 4.0), Vector2(-3.8, 5.8),
		Vector2(-3.2, 7.4), Vector2(-2.0, 8.5), Vector2(-0.4, 9.1), Vector2(1.4, 9.3), Vector2(3.2, 9.2), Vector2(4.6, 8.8)]
	var aamps := [0.3, 0.55, 0.7, 0.75, 0.75, 0.7, 0.6, 0.55, 0.5, 0.5, 0.4]
	var am := MeshInstance3D.new()
	am.mesh = _sweep(-10.0, 112.0, 0.32, arch, aamps, nz, false)
	am.material_override = wall_m
	world3.add_child(am)
	# 입구 쪽 막힌 바위 · 출구 쪽 동굴 입구 테두리
	for k in 5:
		_boulder(Vector3(-8.6 + rr.randf_range(-0.4, 0.4), k * 1.8, rr.randf_range(-2.0, 1.5)), Vector3(1.6, 1.4, 1.6), nz, wall_m, float(k) * 7.0)
	# 출구 테두리: 아치 단면을 따라 바위를 둘러 동굴 입구 모양 (밖은 환한 바다)
	for k in arch.size() - 1:
		for h in 2:
			var ap: Vector2 = (arch[k] as Vector2).lerp(arch[k + 1], h * 0.5)
			var sz := rr.randf_range(1.5, 2.1)
			_boulder(Vector3(112.4 + rr.randf_range(-0.3, 0.3), ap.y, ap.x - 0.4), Vector3(sz * 0.9, sz, sz), nz, wall_m, 40.0 + k * 2 + h)
	_boulder(Vector3(112.0, 0.0, 2.6), Vector3(1.2, 1.6, 1.0), nz, ground_m, 55.0)
	# 뒤쪽 바닥의 바위 · 석순
	var x := -6.0
	while x < 110.0:
		if rr.randf() < 0.55:
			_boulder(Vector3(x, rr.randf_range(-0.2, 0.3), rr.randf_range(-2.9, -2.2)), Vector3(rr.randf_range(0.5, 1.1), rr.randf_range(0.4, 0.9), rr.randf_range(0.4, 0.7)), nz, ground_m, x)
		if rr.randf() < 0.3:
			_stalactite(Vector3(x + 0.5, -0.1, rr.randf_range(-2.7, -2.2)), rr.randf_range(0.5, 1.4), rr.randf_range(0.12, 0.22), ground_m, drop_m, true)
		x += rr.randf_range(1.8, 3.2)
	# 종유석 무리 (천장)
	x = -8.0
	while x < 110.0:
		var n := rr.randi_range(2, 5)
		for k in n:
			var zz := rr.randf_range(-2.2, 1.8)
			var top := 8.9 - absf(zz + 0.4) * 0.15
			_stalactite(Vector3(x + rr.randf_range(-0.8, 0.8), top, zz), rr.randf_range(0.5, 2.2), rr.randf_range(0.08, 0.26), wall_m, drop_m)
		x += rr.randf_range(2.5, 4.5)
	# 벽 횃불 (바위 턱 위) · 천장에 밧줄로 매단 랜턴
	for tx: float in [2.0, 24.0, 33.5, 58.0, 74.0, 90.0, 99.0]:
		torch(world3, Vector3(tx, -0.05, -2.3), 1.7)
	var rope := std_mat(Color(0.45, 0.36, 0.24), 0.95)
	for lx: float in [14.0, 44.0, 66.0, 82.0]:
		var ln := rr.randf_range(2.6, 3.6)
		box(Vector3(0.04, ln, 0.04), rope, Vector3(lx, 9.0 - ln * 0.5, -1.4), Basis(), world3)
		lantern(world3, Vector3(lx, 9.0 - ln - 0.3, -1.4))
	# 천장 틈 빛줄기
	for lx: float in [12.0, 41.0, 62.0, 90.0]:
		_light_shaft(Vector3(lx, 0, 0))
	# 난파선 잔해: 부목 웅덩이 뒤쪽에 비스듬히 박힌 부러진 선체 판자 · 돛대 토막
	var wreck := wood_mat(Color(0.33, 0.25, 0.17), Vector3(1, 0, 0), 0.6)
	for k in 6:
		var bx := 38.8 + k * 0.42
		var ln := rr.randf_range(1.6, 2.6)
		box(Vector3(0.36, ln, 0.1), wreck, Vector3(bx, WATER_Y + ln * 0.35, -2.4 + k * 0.03), Basis(Vector3.BACK, -0.35 + rr.randf_range(-0.08, 0.08)), world3)
	var mastp := CylinderMesh.new()
	mastp.top_radius = 0.16
	mastp.bottom_radius = 0.2
	mastp.height = 4.5
	add_mesh(mastp, wood_mat(Color(0.38, 0.27, 0.17), Vector3(0, 1, 0), 0.5), Vector3(47.5, WATER_Y + 1.3, -2.5), Basis(Vector3.BACK, 0.75), world3)
	# 잡동사니: 낡은 통 · 상자 (뒤쪽)
	var crate_m := wood_mat(Color(0.45, 0.34, 0.22), Vector3(1, 0, 0), 0.4)
	for cx: float in [-4.5, 22.0, 54.0, 71.5, 102.5]:
		barrel(world3, Vector3(cx, 0.0, -1.85), 0.34, 0.85, Color(0.36, 0.25, 0.15))
		box(Vector3(0.7, 0.6, 0.7), crate_m, Vector3(cx + 0.8, 0.3, -2.0), Basis(Vector3.UP, 0.3), world3)
	# 출구: 밝은 바다와 하늘
	var sky := StandardMaterial3D.new()
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.albedo_color = Color(0.82, 0.93, 1.0)
	# 바깥 풍경 판: 위는 파란 하늘 → 수평선은 희뿌옇게 → 아래는 반짝이는 바다
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(0.45, 0.7, 0.95))
	gr.set_color(1, Color(0.06, 0.32, 0.42))
	gr.add_point(0.58, Color(0.95, 0.97, 1.0))
	gr.add_point(0.62, Color(0.4, 0.7, 0.8))
	gt.gradient = gr
	sky.albedo_texture = gt
	sky.albedo_color = Color(1, 1, 1)
	var sq := QuadMesh.new()
	sq.size = Vector2(14, 14)
	add_mesh(sq, sky, Vector3(113.6, 3.0, -0.5), Basis(Vector3.UP, -PI / 2), world3)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.95, 0.82)
	glow.light_energy = 4.0
	glow.omni_range = 24.0
	glow.position = Vector3(113, 4, 2)
	world3.add_child(glow)
	# 결승: 나무 기둥 두 개 + 깃발 줄 + 바닥 흰 줄
	var post := wood_mat(Color(0.42, 0.3, 0.18), Vector3(0, 1, 0), 0.2)
	for z: float in [-1.8, 1.8]:
		var p := CylinderMesh.new()
		p.top_radius = 0.1
		p.bottom_radius = 0.13
		p.height = 3.2
		add_mesh(p, post, Vector3(FINISH_X, 1.6, z), Basis(), world3)
	box(Vector3(0.05, 0.05, 3.6), std_mat(Color(0.55, 0.45, 0.3), 0.9), Vector3(FINISH_X, 3.0, 0), Basis(), world3)
	var cols := [Color(0.85, 0.15, 0.12), Color(0.95, 0.8, 0.2), Color(0.15, 0.45, 0.85), Color(0.95, 0.95, 0.92)]
	for i in 9:
		var fm := std_mat(cols[i % 4], 0.8)
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tri := CylinderMesh.new()
		tri.top_radius = 0.0
		tri.bottom_radius = 0.14
		tri.height = 0.32
		tri.radial_segments = 3
		var mi := add_mesh(tri, fm, Vector3(FINISH_X, 2.82, -1.6 + i * 0.4), Basis(Vector3.RIGHT, PI), world3)
		mi.scale = Vector3(0.15, 1, 1)
	for i in 2:
		box(Vector3(0.12, 0.02, 3.2), std_mat(Color(0.9, 0.88, 0.8), 0.7), Vector3(FINISH_X + (i - 0.5) * 0.25, 0.03, 0), Basis(), world3)


func _light_shaft(p: Vector3) -> void:
	var sp := SpotLight3D.new()
	sp.light_color = Color(0.9, 0.97, 1.0)
	sp.light_energy = 5.0
	sp.spot_range = 12.0
	sp.spot_angle = 16.0
	sp.position = p + Vector3(0, 9.0, 0)
	sp.rotation_degrees = Vector3(-90, 0, 0)
	world3.add_child(sp)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0.5, 0.0)
	g.fill_to = Vector2(0.5, 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(0.7, 0.85, 0.95, 0.22))
	gr.set_color(1, Color(0.7, 0.85, 0.95, 0.0))
	g.gradient = gr
	m.albedo_texture = g
	for k in 2:
		var q := QuadMesh.new()
		q.size = Vector2(2.2, 9.0)
		var mi := add_mesh(q, m, p + Vector3(0, 4.3, 0), Basis(Vector3.UP, k * PI / 2), world3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dust := CPUParticles3D.new()
	dust.amount = 30
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.9, 4.0, 0.9)
	dust.gravity = Vector3(0.02, -0.05, 0)
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.08
	var dm := QuadMesh.new()
	dm.size = Vector2(0.03, 0.03)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.albedo_color = Color(1, 1, 0.9, 0.6)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.material = dmat
	dust.mesh = dm
	dust.position = p + Vector3(0, 4.0, 0)
	world3.add_child(dust)


# ── 장애물 모양 ─────────────────────────────────────────────
func _build_hazards() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 21
	# 움직이는 발판: 밧줄로 묶은 부서진 갑판 조각
	for i in 3:
		var n := Node3D.new()
		world3.add_child(n)
		var wm := wood_mat(Color(0.5, 0.38, 0.25), Vector3(1, 0, 0), 0.3)
		for k in 4:
			box(Vector3(PLAT_HALF * 2.0, 0.16, 0.95), wm, Vector3(0, -0.08, -1.4 + k * 0.95), Basis(Vector3.UP, rr.randf_range(-0.03, 0.03)), n)
		box(Vector3(0.2, 0.2, 3.9), wood_mat(Color(0.32, 0.23, 0.15), Vector3(0, 0, 1), 0.3), Vector3(-PLAT_HALF + 0.25, -0.22, 0), Basis(), n)
		box(Vector3(0.2, 0.2, 3.9), wood_mat(Color(0.32, 0.23, 0.15), Vector3(0, 0, 1), 0.3), Vector3(PLAT_HALF - 0.25, -0.22, 0), Basis(), n)
		_plats.append(n)
	# 흔들리는 닻: 천장 쇠고리 + 쇠사슬 + 닻
	var iron := std_mat(Color(0.2, 0.19, 0.18), 0.45, 0.8)
	var rust := std_mat(Color(0.35, 0.2, 0.12), 0.7, 0.4)
	for a: Array in ANCHORS:
		var root := Node3D.new()
		root.position = Vector3(float(a[0]), ANCHOR_PIVOT_Y, -0.2)
		world3.add_child(root)
		var link := TorusMesh.new()
		link.inner_radius = 0.06
		link.outer_radius = 0.11
		var k := 0
		var y := -0.15
		while y > -ANCHOR_L + 1.0:
			add_mesh(link, iron, Vector3(0, y, 0), Basis(Vector3.FORWARD, PI / 2) * Basis(Vector3.RIGHT, (k % 2) * PI / 2), root)
			y -= 0.17
			k += 1
		var head := Node3D.new()
		head.position = Vector3(0, -ANCHOR_L, 0)
		root.add_child(head)
		var shank := CylinderMesh.new()
		shank.top_radius = 0.09
		shank.bottom_radius = 0.11
		shank.height = 1.6
		add_mesh(shank, rust, Vector3(0, 0.75, 0), Basis(), head)
		box(Vector3(1.0, 0.1, 0.1), iron, Vector3(0, 1.4, 0), Basis(), head)        # 닻채 (가로대)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.1
		ring.outer_radius = 0.16
		add_mesh(ring, iron, Vector3(0, 1.62, 0), Basis(Vector3.RIGHT, PI / 2), head)
		for sd: float in [-1.0, 1.0]:
			box(Vector3(0.7, 0.13, 0.13), rust, Vector3(sd * 0.3, 0.08, 0), Basis(Vector3.BACK, sd * 0.55), head)   # 팔
			var fl := CylinderMesh.new()
			fl.top_radius = 0.0
			fl.bottom_radius = 0.2
			fl.height = 0.42
			fl.radial_segments = 3
			var f := add_mesh(fl, rust, Vector3(sd * 0.64, 0.36, 0), Basis(Vector3.BACK, -sd * 0.4), head)   # 갈고리 끝
			f.scale = Vector3(1, 1, 0.35)
		var crown := SphereMesh.new()
		crown.radius = 0.14
		crown.height = 0.24
		add_mesh(crown, rust, Vector3(0, -0.02, 0), Basis(), head)
		box(Vector3(0.5, 0.2, 0.5), iron, Vector3(0, 0.1, 0), Basis(), root)
		_anchors.append({"root": root})
	# 가라앉는 부목
	for lx: float in LOGS:
		var n := Node3D.new()
		n.position = Vector3(lx, -0.15, 0)
		world3.add_child(n)
		var lm := wood_mat(Color(0.42, 0.33, 0.24), Vector3(1, 0, 0), 0.5)
		for z: float in [-0.75, 0.0, 0.75]:
			var c := CylinderMesh.new()
			c.top_radius = 0.24
			c.bottom_radius = 0.26
			c.height = LOG_HALF * 2.0
			c.radial_segments = 12
			add_mesh(c, lm, Vector3(0, -0.18, z), Basis(Vector3.FORWARD, PI / 2), n)
		var rope := std_mat(Color(0.58, 0.47, 0.32), 0.95)
		for rx: float in [-0.7, 0.7]:
			box(Vector3(0.06, 0.52, 2.0), rope, Vector3(rx * 1.1, -0.18, 0), Basis(), n)
		_logs.append({"trig": -1.0, "node": n, "x": lx})
	# 물기둥: 바닥 갈라진 틈 + 솟는 물 + 물보라
	for g: Array in GEYSERS:
		var gx := float(g[0])
		var crack := CylinderMesh.new()
		crack.top_radius = 0.42
		crack.bottom_radius = 0.42
		crack.height = 0.04
		add_mesh(crack, std_mat(Color(0.05, 0.06, 0.06), 0.9), Vector3(gx, 0.005, 0), Basis(), world3)
		for k in 6:
			var a := k * TAU / 6.0
			var s := SphereMesh.new()
			s.radius = 0.16
			s.height = 0.2
			add_mesh(s, _rock_m(Color(0.27, 0.26, 0.24), 0.8), Vector3(gx + cos(a) * 0.5, 0.03, sin(a) * 0.5), Basis(), world3)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.7, 0.86, 0.95, 0.28)
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.roughness = 0.02
		cm.metallic_specular = 1.0
		cm.rim_enabled = true
		cm.rim = 1.0
		cm.rim_tint = 0.2
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var col := CylinderMesh.new()
		col.top_radius = 0.42
		col.bottom_radius = 0.26
		col.height = 1.0
		col.radial_segments = 18
		col.rings = 6
		var ci := add_mesh(col, cm, Vector3(gx, 0, 0), Basis(), world3)
		ci.visible = false
		var spray := CPUParticles3D.new()
		spray.amount = 90
		spray.lifetime = 0.9
		spray.emitting = false
		spray.direction = Vector3(0, 1, 0)
		spray.spread = 50.0
		spray.initial_velocity_min = 1.5
		spray.initial_velocity_max = 4.5
		spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		spray.emission_sphere_radius = 0.35
		spray.scale_amount_min = 0.4
		spray.scale_amount_max = 1.4
		spray.gravity = Vector3(0, -9.8, 0)
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		var smat := std_mat(Color(0.85, 0.95, 1.0), 0.05)
		smat.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material = smat
		spray.mesh = sm
		world3.add_child(spray)
		var bub := CPUParticles3D.new()
		bub.amount = 14
		bub.lifetime = 0.5
		bub.emitting = false
		bub.direction = Vector3(0, 1, 0)
		bub.spread = 25.0
		bub.initial_velocity_min = 0.6
		bub.initial_velocity_max = 1.4
		bub.gravity = Vector3(0, -3.0, 0)
		bub.mesh = sm
		bub.position = Vector3(gx, 0.05, 0)
		world3.add_child(bub)
		_geysers.append({"col": ci, "spray": spray, "bub": bub, "x": gx})
	# 낙석: 천장 갈라진 틈 + 떨어지는 돌 + 바닥 그림자
	for r: Array in ROCKS:
		var rx := float(r[0])
		box(Vector3(1.2, 0.3, 1.0), std_mat(Color(0.04, 0.04, 0.04), 0.9), Vector3(rx, 8.35, 0), Basis(), world3)
		var rk := SphereMesh.new()
		rk.radius = 0.5
		rk.height = 0.9
		rk.radial_segments = 8
		rk.rings = 5
		var ri := add_mesh(rk, _rock_m(Color(0.33, 0.31, 0.28), 0.3), Vector3(rx, 9, 0), Basis(), world3)
		ri.scale = Vector3(1.0, 0.8, 0.9)
		var sh := QuadMesh.new()
		sh.size = Vector2(1.4, 1.4)
		sh.orientation = PlaneMesh.FACE_Y
		var shm := StandardMaterial3D.new()
		shm.albedo_color = Color(0, 0, 0, 0)
		shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shm.albedo_texture = _soft_dot()
		var si := add_mesh(sh, shm, Vector3(rx, 0.02, 0), Basis(), world3)
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rocks.append({"rock": ri, "shadow": si, "smat": shm, "x": rx, "landed": -1})
	# 게 통로: 낮게 내려온 천장 바위
	var ov := _cave_mat(Color(0.36, 0.33, 0.3), 0.3, 0.7)
	var nz2 := FastNoiseLite.new()
	nz2.seed = 11
	nz2.frequency = 0.45
	var ox := 86.5
	while ox < 101.0:
		# 뒷벽에서 앞으로 튀어나온 바위 턱 (뒤쪽은 벽 속에 묻힘)
		var bo := _boulder(Vector3(ox, rr.randf_range(4.5, 5.0), -2.4), Vector3(rr.randf_range(1.4, 1.9), rr.randf_range(0.8, 1.1), 2.6), nz2, ov, ox)
		bo.rotation.z = rr.randf_range(-0.15, 0.15)
		for k in 3:
			_stalactite(Vector3(ox + rr.randf_range(-1.0, 1.0), 4.0, rr.randf_range(-1.0, -0.1)), rr.randf_range(0.3, 0.8), rr.randf_range(0.06, 0.13), ov, ov)
		ox += rr.randf_range(1.4, 2.2)
	# 게
	for c: Array in CRABS:
		_crabs.append(_make_crab(float(c[0])))


func _make_crab(x: float) -> Dictionary:
	var n := Node3D.new()
	n.position = Vector3(x, 0, 0.3)
	world3.add_child(n)
	var shell := std_mat(Color(0.72, 0.24, 0.12), 0.45)
	var dark := std_mat(Color(0.45, 0.13, 0.07), 0.5)
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 0.4
	var bi := add_mesh(body, shell, Vector3(0, 0.3, 0), Basis(), n)
	bi.scale = Vector3(1.3, 0.75, 1.0)
	var legs := []
	for sd: float in [-1.0, 1.0]:
		for k in 3:
			var l := CylinderMesh.new()
			l.top_radius = 0.025
			l.bottom_radius = 0.035
			l.height = 0.42
			var leg := Node3D.new()
			leg.position = Vector3(sd * 0.3, 0.27, -0.16 + k * 0.16)
			n.add_child(leg)
			add_mesh(l, dark, Vector3(sd * 0.15, -0.12, 0), Basis(Vector3.BACK, -sd * 0.9), leg)
			legs.append(leg)
		# 집게
		var arm := Node3D.new()
		arm.position = Vector3(sd * 0.32, 0.36, 0.24)
		n.add_child(arm)
		var cl := SphereMesh.new()
		cl.radius = 0.12
		cl.height = 0.2
		var ci := add_mesh(cl, shell, Vector3(sd * 0.12, 0.04, 0.14), Basis(), arm)
		ci.scale = Vector3(0.8, 1.0, 1.4)
		var pin := CylinderMesh.new()
		pin.top_radius = 0.0
		pin.bottom_radius = 0.05
		pin.height = 0.16
		add_mesh(pin, dark, Vector3(sd * 0.12, 0.08, 0.3), Basis(Vector3.RIGHT, PI / 2), arm)
		# 눈자루
		var st := CylinderMesh.new()
		st.top_radius = 0.02
		st.bottom_radius = 0.02
		st.height = 0.14
		add_mesh(st, dark, Vector3(sd * 0.09, 0.5, 0.18), Basis(), n)
		var eye := SphereMesh.new()
		eye.radius = 0.035
		eye.height = 0.07
		add_mesh(eye, std_mat(Color(0.03, 0.03, 0.03), 0.2), Vector3(sd * 0.09, 0.58, 0.18), Basis(), n)
	return {"node": n, "legs": legs, "last_x": x}


## 밀물: 왼쪽에서 들어오는 얕은 물 (앞머리에 거품)
func _build_tide() -> void:
	_tide = Node3D.new()
	world3.add_child(_tide)
	var q := PlaneMesh.new()
	q.size = Vector2(60, 4.4)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.3, 0.34, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.9
	var mi := add_mesh(q, m, Vector3(-30, 0, 0), Basis(), _tide)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fm := std_mat(Color(0.92, 0.96, 1.0), 0.6)
	box(Vector3(0.5, 0.12, 4.4), fm, Vector3(-0.2, 0.04, 0), Basis(), _tide)
	_tide_foam = CPUParticles3D.new()
	_tide_foam.amount = 30
	_tide_foam.lifetime = 0.7
	_tide_foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_tide_foam.emission_box_extents = Vector3(0.2, 0.05, 2.0)
	_tide_foam.direction = Vector3(0.6, 1, 0)
	_tide_foam.spread = 25.0
	_tide_foam.initial_velocity_min = 1.0
	_tide_foam.initial_velocity_max = 2.0
	_tide_foam.gravity = Vector3(0, -8, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.material = fm
	_tide_foam.mesh = sm
	_tide.add_child(_tide_foam)
	_tide.position = Vector3(_tide_x(), 0.3, 0)


func _tide_x() -> float:
	return -12.0 + maxf(0.0, _el - TIDE_START) * TIDE_SPEED


# ── 장애물 상태 (시간으로 정해져서 모두 똑같이 보임) ─────────
func _plat_pos(i: int, t: float) -> Vector2:
	match i:
		0:
			return Vector2(10.6 + sin(t * 1.75) * 1.3, -0.05)
		1:
			return Vector2(14.0, 0.25 + sin(t * 2.0 + 1.0) * 1.0)
		_:
			return Vector2(17.6 + sin(t * 1.6 + 2.0) * 1.2, -0.05)


func _log_y(i: int, t: float) -> float:
	var trig := float(_logs[i]["trig"])
	if trig < 0.0:
		# 올라선 시간만큼 점점 잠김
		return -0.15 - float(_logs[i].get("load", 0.0)) * 0.22 + sin(t * 2.0 + i) * 0.03
	var dt := t - trig
	if dt < 0.6:
		return lerpf(-0.37, -1.9, dt / 0.6)
	if dt < 3.1:
		return -1.9
	if dt < 3.9:
		return lerpf(-1.9, -0.15, (dt - 3.1) / 0.8)
	return -0.15


func _anchor_a(i: int, t: float) -> float:
	return 1.15 * sin(t * 2.1 + float(ANCHORS[i][1]))


func _anchor_head(i: int, t: float) -> Vector2:
	var a := _anchor_a(i, t)
	return Vector2(float(ANCHORS[i][0]) + sin(a) * ANCHOR_L, ANCHOR_PIVOT_Y - cos(a) * ANCHOR_L + 0.7)


## 물기둥: 0 쉼, 1 부글부글(경고), 2 솟구침
func _geyser_state(i: int, t: float) -> int:
	var ph := fmod(t + float(GEYSERS[i][1]), GEY_T)
	if ph > GEY_ON:
		return 2
	if ph > GEY_WARN:
		return 1
	return 0


## 낙석: 위상 (0~ROCK_T). ROCK_WARN~ROCK_FALL 그림자, ROCK_FALL~ 떨어짐
func _rock_ph(i: int, t: float) -> float:
	return fmod(t + float(ROCKS[i][1]), ROCK_T)


func _crab_x(i: int, t: float) -> float:
	var c: Array = CRABS[i]
	return lerpf(float(c[0]), float(c[1]), 0.5 + 0.5 * sin(t * float(c[2]) * 0.9 + float(c[3])))


## 발판 하나만 (id), 지금 없으면 []
func _solid_one(id: int, t: float) -> Array:
	if id <= -10:
		var g: Array = GROUND[-10 - id]
		return [float(g[0]), float(g[1]), float(g[2]), -6.0, id]
	if id < 10:
		var p := _plat_pos(id, t)
		return [p.x - PLAT_HALF, p.x + PLAT_HALF, p.y, p.y - 0.3, id]
	var y := _log_y(id - 10, t)
	if y <= FALL_Y + 0.05:
		return []
	return [float(LOGS[id - 10]) - LOG_HALF, float(LOGS[id - 10]) + LOG_HALF, y, y - 0.5, id]


## 지금 밟을 수 있는 것들 [x0, x1, 윗면 y, 바닥 y, id]  (id: -10 이하 땅 조각, 0~2 발판, 10~ 부목)
func _solids(t: float) -> Array:
	var out := []
	for gi in GROUND.size():
		var g: Array = GROUND[gi]
		out.append([float(g[0]), float(g[1]), float(g[2]), -6.0 if float(g[2]) <= 0.01 else 0.0, -10 - gi])
	for i in 3:
		var p := _plat_pos(i, t)
		out.append([p.x - PLAT_HALF, p.x + PLAT_HALF, p.y, p.y - 0.3, i])
	for i in _logs.size():
		var y := _log_y(i, t)
		if y > FALL_Y + 0.05:
			out.append([float(LOGS[i]) - LOG_HALF, float(LOGS[i]) + LOG_HALF, y, y - 0.5, 10 + i])
	return out


func _setup_game() -> void:
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var pawn := make_pawn(p)
		var z := lerpf(-0.9, 0.9, float(i) / maxf(n - 1, 1))
		_P[s] = {"x": -3.5 + i * 1.1, "y": 0.0, "vx": 0.0, "vy": 0.0, "ground": true, "carrier": -9, "fall": 0.0, "stun": 0.0,
			"done": false, "time": 0.0, "node": pawn, "z": z, "face": 1.0, "bob": randf() * TAU, "hitcd": 0.0, "coyote": 0.0,
			"wade": false, "tx": -3.5 + i * 1.1, "ty": 0.0, "cp": 0.0, "p": p}
		_ai[s] = {"wait": 0.0, "react": 0.0, "jumped": 0.0}
		scores[s] = 0.0
	_pose_all(0.0)
	_place_cam(true)


func _start_game() -> void:
	_el = 0.0


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode in [KEY_SPACE, KEY_W, KEY_UP]:
		_jump_buf = 0.14


func _local_dir() -> float:
	var d := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d += 1.0
	return d


func _net_input(slot: int, action: String, args: Array) -> void:
	if action == "me" and _P.has(slot) and args.size() >= 4:
		var P: Dictionary = _P[slot]
		P["tx"] = float(args[0])
		P["ty"] = float(args[1])
		P["face"] = float(args[2])
		P["fall"] = float(args[3])


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	# 프레임이 길어도 (느린 PC) 물리는 1/60초씩 잘게 나눠 계산 → 발판을 뚫고 지나가지 않음
	var n := clampi(int(ceil(delta / 0.0167)), 1, 12)
	var sub := delta / n
	for k in n:
		_step_world(sub)
	_send_me(delta)
	_show_hazards(delta)
	_pose_all(delta)
	_place_cam(false, delta)


func _step_world(delta: float) -> void:
	_el += delta
	_t3 += delta
	_jump_buf = maxf(0.0, _jump_buf - delta)
	if not is_client():
		_update_logs(delta)
	for s in _P:
		var P: Dictionary = _P[s]
		if _sim_here(s):
			var dir := 0.0
			var jump := false
			if is_local(P["p"]) and not demo:
				dir = _local_dir()
				jump = _jump_buf > 0.0
				if jump and (bool(P["ground"]) or float(P["coyote"]) > 0.0):
					_jump_buf = 0.0
			else:
				var r := _think(s, delta)
				dir = r[0]
				jump = r[1]
			_phys(s, P, delta, dir, jump)
			_hazards(s, P)
		else:
			# 남이 움직이는 말: 받은 자리로 부드럽게
			var goal := Vector2(float(P["tx"]), float(P["ty"]))
			var cur := Vector2(float(P["x"]), float(P["y"]))
			var np := goal if cur.distance_to(goal) > 3.0 else cur.lerp(goal, clampf(delta * 14.0, 0.0, 1.0))
			P["vx"] = (np.x - cur.x) / maxf(delta, 0.001)
			P["vy"] = (np.y - cur.y) / maxf(delta, 0.001)
			P["x"] = np.x
			P["y"] = np.y
			P["ground"] = absf(float(P["vy"])) < 0.5
	_separate()
	if not is_client():
		for s in _P:
			var P: Dictionary = _P[s]
			if not P["done"] and float(P["x"]) >= FINISH_X:
				net_call("_finish", [s, _el])
			scores[s] = 1000.0 - float(P["time"]) if P["done"] else float(P["x"])


## 이 PC 가 직접 움직이는 말인가 (내 말 · 방장이면 CPU)
func _sim_here(s: int) -> bool:
	var p: Dictionary = _P[s]["p"]
	if is_local(p):
		return true
	return not is_client() and not is_human(p)


func _send_me(delta: float) -> void:
	if net != "client":
		return
	_send -= delta
	if _send > 0.0:
		return
	_send = 0.066
	var me := local_slot()
	if _P.has(me):
		var P: Dictionary = _P[me]
		net_input("me", [float(P["x"]), float(P["y"]), float(P["face"]), float(P["fall"])])


## 말 하나 움직이기 (가속 · 중력 · 점프 · 발판 위에 서기 · 벽에 막히기 · 물에 빠지기)
func _phys(s: int, P: Dictionary, delta: float, dir: float, jump: bool) -> void:
	P["stun"] = maxf(0.0, float(P["stun"]) - delta)
	P["hitcd"] = maxf(0.0, float(P["hitcd"]) - delta)
	if P["done"]:
		dir = 1.0 if float(P["x"]) < FINISH_X + 3.0 else 0.0
		jump = false
	if float(P["fall"]) > 0.0:
		# 빠짐: 조작 불가 → 시간이 다 되면 그 구간 시작 땅으로
		P["fall"] = float(P["fall"]) - delta
		P["y"] = lerpf(float(P["y"]), WATER_Y - 0.35, clampf(delta * 6.0, 0.0, 1.0))
		if float(P["fall"]) <= 0.0:
			P["fall"] = 0.0
			P["x"] = float(P["cp"])
			P["y"] = 0.0
			P["vx"] = 0.0
			P["vy"] = 0.0
			P["ground"] = true
			P["carrier"] = -1
			P["stun"] = 0.2
		return
	if float(P["stun"]) > 0.0:
		dir = 0.0
		jump = false
	var wade := float(P["x"]) < _tide_x() and float(P["y"]) < 0.6
	P["wade"] = wade
	var top_speed := RUN * (0.55 if wade else 1.0)
	var acc := ACC_G if P["ground"] else ACC_A
	P["vx"] = move_toward(float(P["vx"]), dir * top_speed, acc * delta)
	if dir != 0.0:
		P["face"] = signf(dir)
	P["coyote"] = maxf(0.0, float(P["coyote"]) - delta)
	if jump and (bool(P["ground"]) or float(P["coyote"]) > 0.0):
		P["vy"] = JUMP * (0.85 if wade else 1.0)
		P["ground"] = false
		P["coyote"] = 0.0
		P["carrier"] = -9
		if is_local(P["p"]) or demo:
			sfx("whoosh", 25)
	# 발판 위면 같이 움직임
	var sol_now := _solids(_el)
	if P["ground"] and int(P["carrier"]) >= 0:
		var prev := _solids(_el - delta)
		for a: Array in sol_now:
			if int(a[4]) != int(P["carrier"]):
				continue
			for b: Array in prev:
				if int(b[4]) == int(a[4]):
					P["x"] = float(P["x"]) + (float(a[0]) - float(b[0]))
					P["y"] = float(a[2])
	P["vy"] = maxf(float(P["vy"]) - GRAV * delta, -22.0)
	var x := float(P["x"])
	var y := float(P["y"])
	# 가로: 내 발보다 높은 바위 · 땅 옆면에 막힘
	var nx := x + float(P["vx"]) * delta
	for a: Array in sol_now:
		var top := float(a[2])
		var bot := float(a[3])
		if y + 0.05 >= top or y + PH <= bot:
			continue
		if nx + HW > float(a[0]) and nx - HW < float(a[1]):
			if x <= float(a[0]):
				nx = float(a[0]) - HW
			elif x >= float(a[1]):
				nx = float(a[1]) + HW
			P["vx"] = 0.0
	# 세로: 떨어지다 윗면에 닿으면 섬
	var ny := y + float(P["vy"]) * delta
	var was_ground: bool = P["ground"]
	P["ground"] = false
	if float(P["vy"]) <= 0.0 or true:
		# 움직이는 발판: 직전 높이도 같이 봄 (위로 올라오는 발판을 뚫고 지나가지 않게)
		var prev_top := {}
		for b: Array in _solids(_el - delta):
			if int(b[4]) >= 0:
				prev_top[int(b[4])] = float(b[2])
		var best := -INF
		var bid := -9
		for a: Array in sol_now:
			if nx + HW * 0.7 < float(a[0]) or nx - HW * 0.7 > float(a[1]):
				continue
			var top := float(a[2])
			var low := minf(top, float(prev_top.get(int(a[4]), top)))
			if float(P["vy"]) > 0.0 and top <= low + 0.001:
				continue   # 올라가는 중엔 가만있는 발판에 안 붙음
			if float(P["vy"]) > 0.0 and ny > top:
				continue
			if y >= low - 0.12 and ny <= top + 0.02 and top > best:
				best = top
				bid = int(a[4])
		if bid != -9:
			ny = best
			P["vy"] = 0.0
			P["ground"] = true
			P["carrier"] = bid
	if was_ground and not P["ground"]:
		P["coyote"] = 0.1
	P["x"] = nx
	P["y"] = ny
	# 물에 빠짐
	if ny < FALL_Y:
		var cp := nx
		for pt: Array in PITS:
			if nx > float(pt[0]) - 1.0 and nx < float(pt[1]) + 1.0:
				cp = float(pt[2])
		P["cp"] = cp
		P["fall"] = 1.0
		if OS.get_environment("MG_DEBUG") != "":
			print("CR fall s=%d x=%.1f t=%.1f" % [s, nx, _el])
		P["vx"] = 0.0
		P["vy"] = 0.0
		splash(Vector3(nx, WATER_Y + 0.2, float(P["z"])), 40, 1.0)
		if is_local(P["p"]) or demo:
			sfx("splash")


## 장애물에 맞았는지 (이 PC 가 움직이는 말만)
func _hazards(s: int, P: Dictionary) -> void:
	if P["done"] or float(P["fall"]) > 0.0 or float(P["hitcd"]) > 0.0:
		return
	var x := float(P["x"])
	var y := float(P["y"])
	var mid := Vector2(x, y + 0.6)
	# 닻
	for i in ANCHORS.size():
		var h := _anchor_head(i, _el)
		if h.distance_to(mid) < 0.85:
			var hv := _anchor_head(i, _el + 0.05) - h
			_hit(s, P, (signf(hv.x) if absf(hv.x) > 0.001 else -1.0) * 6.0, 5.0, 0.45)
			return
	# 물기둥
	for i in GEYSERS.size():
		if _geyser_state(i, _el) == 2 and absf(float(GEYSERS[i][0]) - x) < 0.6 and y < 3.5:
			_hit(s, P, -2.5, 13.0, 0.3)
			return
	# 낙석 (돌이 바닥에 닿는 순간 근처)
	for i in ROCKS.size():
		var ph := _rock_ph(i, _el)
		if ph > ROCK_T - 0.18 and absf(float(ROCKS[i][0]) - x) < 0.75 and y < 1.2:
			_hit(s, P, -3.0, 3.0, 0.9)
			return
	# 게 (땅에서만, 위로 뛰어넘으면 안전)
	for i in CRABS.size():
		if absf(_crab_x(i, _el) - x) < 0.55 and y < 0.45:
			_hit(s, P, -3.5, 3.5, 0.7)
			return


func _hit(s: int, P: Dictionary, vx: float, vy: float, stun: float) -> void:
	P["vx"] = vx
	P["vy"] = vy
	P["ground"] = false
	P["carrier"] = -9
	P["stun"] = stun
	P["hitcd"] = 0.8
	splash(Vector3(float(P["x"]), float(P["y"]) + 0.8, float(P["z"])), 14, 0.5)
	if is_local(P["p"]) or demo:
		sfx("thud", 70)
		shake(0.2)


## 서로 부딪히면 살짝 밀려남
func _separate() -> void:
	var ks := _P.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var A: Dictionary = _P[ks[i]]
			var B: Dictionary = _P[ks[j]]
			if float(A["fall"]) > 0.0 or float(B["fall"]) > 0.0 or A["done"] or B["done"]:
				continue
			var dx := float(B["x"]) - float(A["x"])
			if absf(dx) < 0.55 and absf(float(B["y"]) - float(A["y"])) < 0.9:
				var push := (0.55 - absf(dx)) * 0.5 * (signf(dx) if dx != 0.0 else 1.0)
				if _sim_here(ks[i]):
					A["x"] = float(A["x"]) - push
				if _sim_here(ks[j]):
					B["x"] = float(B["x"]) + push


## 방장: 누가 부목 위에 서면 1초 뒤 가라앉기 시작 (다 떠오르면 다시 밟힐 수 있음)
func _update_logs(dl: float) -> void:
	for i in _logs.size():
		var L: Dictionary = _logs[i]
		var trig := float(L["trig"])
		if trig >= 0.0 and _el - trig > 3.9:
			L["trig"] = -1.0
			L["load"] = 0.0
			trig = -1.0
		if trig >= 0.0:
			continue
		# 누가 1.2초 넘게 올라서 있으면 가라앉음 (그냥 밟고 지나가면 괜찮음)
		var on := false
		for s in _P:
			var P: Dictionary = _P[s]
			if absf(float(P["x"]) - float(LOGS[i])) < LOG_HALF + 0.1 and absf(float(P["y"]) - _log_y(i, _el)) < 0.15 and float(P["fall"]) <= 0.0:
				on = true
				break
		L["load"] = clampf(float(L.get("load", 0.0)) + (dl / LOG_SINK if on else -dl * 0.8), 0.0, 1.0)
		if float(L["load"]) >= 1.0:
			L["trig"] = _el


func _finish(s: int, t: float) -> void:
	var P: Dictionary = _P[s]
	if P["done"]:
		return
	P["done"] = true
	P["time"] = t
	_done_n += 1
	if OS.get_environment("MG_DEBUG") != "":
		print("CR finish s=%d t=%.1f" % [s, t])
	sfx("start")
	splash(Vector3(float(P["x"]), float(P["y"]) + 1.0, float(P["z"])), 24, 0.6)


# ── 모습 ────────────────────────────────────────────────────
func _show_hazards(delta: float) -> void:
	for i in _plats.size():
		var p := _plat_pos(i, _el)
		(_plats[i] as Node3D).position = Vector3(p.x, p.y, 0)
		(_plats[i] as Node3D).rotation.z = sin(_el * 1.7 + i) * 0.02
	for i in _anchors.size():
		(_anchors[i]["root"] as Node3D).rotation.z = _anchor_a(i, _el)
	for i in _logs.size():
		var n: Node3D = _logs[i]["node"]
		var y := _log_y(i, _el)
		n.position.y = y
		n.rotation.z = sin(_el * 1.3 + i) * 0.03 + (0.12 if y < -0.4 else 0.0)
	for i in _geysers.size():
		var G: Dictionary = _geysers[i]
		var st := _geyser_state(i, _el)
		var ci: MeshInstance3D = G["col"]
		(G["bub"] as CPUParticles3D).emitting = st == 1
		var on := st == 2
		ci.visible = on
		if on:
			var ph := fmod(_el + float(GEYSERS[i][1]), GEY_T) - GEY_ON
			var hgt := 4.2 * clampf(ph / 0.15, 0.0, 1.0) * (1.0 - clampf((ph - 0.7) / 0.2, 0.0, 1.0)) + 0.1
			ci.scale = Vector3(1.0 + sin(_el * 30.0) * 0.06, hgt, 1.0 + cos(_el * 27.0) * 0.06)
			ci.position = Vector3(float(G["x"]), hgt * 0.5, 0)
			var sp: CPUParticles3D = G["spray"]
			sp.position = Vector3(float(G["x"]), hgt, 0)
			sp.emitting = true
		else:
			(G["spray"] as CPUParticles3D).emitting = false
	for i in _rocks.size():
		var R: Dictionary = _rocks[i]
		var ph := _rock_ph(i, _el)
		var rk: MeshInstance3D = R["rock"]
		var shm: StandardMaterial3D = R["smat"]
		var sh: MeshInstance3D = R["shadow"]
		var wl := ROCK_FALL - ROCK_WARN
		if ph < ROCK_WARN:
			rk.visible = false
			shm.albedo_color.a = 0.0
		elif ph < ROCK_FALL:
			rk.visible = true
			rk.position = Vector3(float(R["x"]) + sin(_el * 40.0) * 0.03 * (ph - ROCK_WARN), 8.1, 0)
			shm.albedo_color.a = lerpf(0.0, 0.55, (ph - ROCK_WARN) / wl)
			sh.scale = Vector3.ONE * lerpf(1.4, 0.8, (ph - ROCK_WARN) / wl)
		else:
			var f := clampf((ph - ROCK_FALL) / (ROCK_T - ROCK_FALL), 0.0, 1.0)
			rk.visible = true
			rk.position = Vector3(float(R["x"]), lerpf(8.1, 0.4, f * f), 0)
			rk.rotation = Vector3(f * 3.0, 0, f * 2.0)
			shm.albedo_color.a = 0.65
			sh.scale = Vector3.ONE * 0.8
		# 바닥에 부딪치는 순간: 먼지 · 파편
		var cycle := int((_el + float(ROCKS[i][1])) / ROCK_T)
		if ph > ROCK_T - 0.08 and int(R["landed"]) != cycle:
			R["landed"] = cycle
			debris(Vector3(float(R["x"]), 0.3, 0), Color(0.35, 0.33, 0.3), 12)
			if absf(float(R["x"]) - _cam_x) < 14.0:
				sfx("thud", 40)
	for i in _crabs.size():
		var C: Dictionary = _crabs[i]
		var n: Node3D = C["node"]
		var x := _crab_x(i, _el)
		var vx := (x - float(C["last_x"])) / maxf(delta, 0.001)
		C["last_x"] = x
		n.position.x = x
		var k := 0
		for leg: Node3D in C["legs"]:
			leg.rotation.z = sin(_el * 18.0 + k * 1.3) * 0.35 * clampf(absf(vx), 0.0, 1.0)
			k += 1
		n.rotation.y = sin(_el * 3.0 + i) * 0.15
	for k in _pool_lights.size():
		(_pool_lights[k] as OmniLight3D).light_energy = 0.8 + sin(_el * 2.3 + k) * 0.2 + sin(_el * 5.1 + k * 2.0) * 0.12
	var tx := _tide_x()
	_tide.position.x = tx
	_tide.position.y = 0.28 + sin(_el * 2.0) * 0.04
	_tide_foam.emitting = tx > -10.0


func _pose_all(delta: float) -> void:
	for s in _P:
		var P: Dictionary = _P[s]
		var n: Node3D = P["node"]
		var vx := float(P["vx"])
		var y := float(P["y"])
		P["bob"] = float(P["bob"]) + delta * (4.0 + absf(vx) * 2.0)
		var run := clampf(absf(vx) / RUN, 0.0, 1.0)
		var hop := absf(sin(float(P["bob"]))) * 0.12 * run if P["ground"] else 0.0
		n.position = Vector3(float(P["x"]), y + hop, float(P["z"]))
		var face := float(P["face"])
		var lean := 0.0 if P["ground"] else clampf(-float(P["vy"]) * 0.03, -0.3, 0.3)
		var spin := float(P["stun"]) * 10.0 if float(P["stun"]) > 0.2 else 0.0
		if float(P["fall"]) > 0.0:
			n.rotation = Vector3(0.6, PI / 2 * face, sin(_t3 * 10.0) * 0.4)
		else:
			n.rotation = Vector3(run * 0.18 + lean, PI / 2 * face + spin, sin(float(P["bob"])) * 0.06 * run)


## 화면: 내 말 (자동이면 아직 달리는 사람 중 선두) 을 옆에서 따라감
func _place_cam(snap: bool = false, delta: float = 0.0) -> void:
	var fx := 0.0
	var fy := 0.0
	var me := local_slot()
	if _P.has(me) and is_local(_P[me]["p"]):
		fx = float(_P[me]["x"])
		fy = float(_P[me]["y"])
	elif not _P.is_empty():
		var best := -INF
		for s in _P:
			var P: Dictionary = _P[s]
			if not P["done"] and float(P["x"]) > best:
				best = float(P["x"])
				fy = float(P["y"])
		fx = best if best > -INF else FINISH_X
	fy = clampf(fy, 0.0, 3.0)
	if snap:
		_cam_x = fx
		_cam_y = fy
	else:
		_cam_x = lerpf(_cam_x, fx, clampf(delta * 4.0, 0.0, 1.0))
		_cam_y = lerpf(_cam_y, fy, clampf(delta * 2.5, 0.0, 1.0))
	var xf := Transform3D(Basis(), Vector3(_cam_x + 2.4, _cam_y + 3.0, 12.5))
	xf = xf.looking_at(Vector3(_cam_x + 2.4, _cam_y + 1.3, 0), Vector3.UP)
	cam_base = xf
	cam.transform = xf


# ── CPU ─────────────────────────────────────────────────────
## 앞에 발 디딜 곳이 있는지 (지금 기준, 0.5m 앞)
func _support(x: float, y: float, t: float) -> bool:
	for a: Array in _solids(t):
		if x + HW * 0.5 > float(a[0]) and x - HW * 0.5 < float(a[1]) and absf(float(a[2]) - y) < 0.35:
			return true
	return false


## 지금 뛰면 안전하게 내릴 발판이 있는지: 앞쪽 발판마다 "공중에서 그 가운데로 몸을 트는" 궤적을 내다봄.
## 내릴 수 있으면 그 발판 id, 없으면 -99
func _jump_target(P: Dictionary) -> int:
	var me_slot := int(P["p"]["slot"])
	var cands := []
	for a: Array in _solids(_el):
		if float(a[1]) > float(P["x"]) + 0.6 and float(a[0]) < float(P["x"]) + 5.5 and int(a[4]) != int(P["carrier"]):
			cands.append(a)
	cands.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
	for c: Array in cands:
		var id := int(c[4])
		if id >= 10 and float(_logs[id - 10]["trig"]) >= 0.0:
			continue
		if id >= 10:
			var busy := false
			for o in _P:
				if o != me_slot and absf(float(_P[o]["x"]) - (float(c[0]) + float(c[1])) * 0.5) < LOG_HALF + 0.2 and absf(float(_P[o]["y"]) - float(c[2])) < 0.4:
					busy = true
			if busy:
				continue
		if _sim_jump(P, id):
			return id
	return -99


## 공중에서 발판 id 가운데로 몸을 틀며 뛰었을 때 거기 안쪽에 내리는지 (그 발판만 따라가며 계산 → 가벼움)
func _sim_jump(P: Dictionary, id: int) -> bool:
	var x := float(P["x"])
	var y := float(P["y"])
	var vx := float(P["vx"])
	var vy := JUMP
	var t := _el
	var dt := 0.05
	for k in 36:
		t += dt
		var a := _solid_one(id, t)
		if a.is_empty():
			return false
		var cx := (float(a[0]) + float(a[1])) * 0.5
		var d := 0.0 if absf(cx - x) < 0.25 else signf(cx - x)
		vx = move_toward(vx, d * RUN, ACC_A * dt)
		vy -= GRAV * dt
		var nx := x + vx * dt
		var ny := y + vy * dt
		if vy <= 0.0 and nx + HW * 0.7 >= float(a[0]) and nx - HW * 0.7 <= float(a[1]):
			var top := float(a[2])
			if y >= top - 0.15 and ny <= top + 0.02:
				return nx > float(a[0]) + 0.25 and nx < float(a[1]) - 0.25
		if ny < FALL_Y:
			return false
		x = nx
		y = ny
	return false


## 앞쪽 위험 (닻 · 물기둥 · 낙석)이 곧 내 길을 지나가는지
func _danger_ahead(x: float, y: float) -> bool:
	for i in ANCHORS.size():
		for dt: float in [0.15, 0.35]:
			var h := _anchor_head(i, _el + dt)
			if h.x - x > -0.5 and h.x - x < 1.8 and h.y < y + 2.2:
				return true
	for i in GEYSERS.size():
		var gx := float(GEYSERS[i][0])
		if gx - x > -0.2 and gx - x < 1.6 and (_geyser_state(i, _el) != 0 or _geyser_state(i, _el + 0.4) != 0):
			return true
	for i in ROCKS.size():
		var rx := float(ROCKS[i][0])
		if rx - x > -0.3 and rx - x < 1.8:
			var ph := _rock_ph(i, _el)
			if ph > ROCK_WARN - 0.1 or _rock_ph(i, _el + 0.45) > ROCK_WARN - 0.1:
				return true
	return false


## CPU: 오른쪽으로 달리며, 낭떠러지 앞에선 착지할 곳이 보이면 뜀 (아니면 기다림).
## 위험이 다가오면 멈춰 기다리고, 게가 가까우면 뛰어넘음. 실력이 낮으면 반응이 늦고 가끔 무모하게 뜀
func _think(s: int, delta: float) -> Array:
	var P: Dictionary = _P[s]
	var a: Dictionary = _ai[s]
	var sk := skill(P["p"]) / 2.0
	if P["done"]:
		return [1.0, false]
	if OS.get_environment("MG_DEBUG") != "" and fmod(_t3, 2.0) < delta:
		print("CRDBG t=%.1f s=%d x=%.1f y=%.2f g=%s c=%d st=%.1f f=%.1f" % [_el, s, float(P["x"]), float(P["y"]), str(P["ground"]), int(P["carrier"]), float(P["stun"]), float(P["fall"])])
	a["jumped"] = maxf(0.0, float(a["jumped"]) - delta)
	a["wait"] = maxf(0.0, float(a["wait"]) - delta)
	var x := float(P["x"])
	var y := float(P["y"])
	var dir := 1.0
	var jump := false
	if not P["ground"]:
		# 공중: 정해 둔 발판 가운데로 몸을 틂
		var tid := int(a.get("tgt", -99))
		if tid != -99:
			for so: Array in _solids(_el):
				if int(so[4]) == tid:
					var cx := (float(so[0]) + float(so[1])) * 0.5
					return [0.0 if absf(cx - x) < 0.25 else signf(cx - x), false]
		return [1.0, false]
	a["tgt"] = -99
	# 부목 위에 서 있으면 꾸물대지 않음
	var on_log := int(P["carrier"]) >= 10
	var vx := maxf(float(P["vx"]), 0.0)
	var look := 0.45 + vx * vx / (2.0 * ACC_G) + 0.1   # 멈추는 데 필요한 거리만큼 미리 봄
	var edge := not _support(x + look, y, _el)
	if edge or (on_log and not _support(x + 0.5, y, _el)):
		var tid := -99
		a["jt_t"] = float(a.get("jt_t", 0.0)) - delta
		if float(a["jt_t"]) <= 0.0:
			a["jt_t"] = 0.07
			tid = _jump_target(P)
		if tid != -99:
			jump = true
			a["tgt"] = tid
			if OS.get_environment("MG_DEBUG") != "":
				print("CRJ t=%.2f s=%d x=%.2f y=%.2f vx=%.2f car=%d tgt=%d" % [_el, s, x, y, float(P["vx"]), int(P["carrier"]), tid])
		elif on_log and not _support(x + 0.5, y, _el):
			jump = true   # 부목이 곧 가라앉으니 어쩔 수 없이
		elif rng.randf() < lerpf(0.02, 0.0, sk):
			jump = true   # 무모하게
		else:
			dir = 0.0
	# 턱이 있으면 뜀
	for g: Array in GROUND:
		if float(g[2]) > y + 0.3 and float(g[0]) - x > 0.0 and float(g[0]) - x < 0.8:
			jump = true
	# 게: 가까우면 뛰어넘음
	for i in CRABS.size():
		var cx := _crab_x(i, _el + 0.15)
		if cx - x > 0.2 and cx - x < lerpf(0.9, 1.4, sk):
			jump = true
	# 위험 기다리기 (실력이 낮으면 가끔 못 봄)
	if not jump and _danger_ahead(x, y):
		if float(a["react"]) <= 0.0:
			a["react"] = lerpf(0.35, 0.05, sk)
			a["see"] = rng.randf() < lerpf(0.6, 0.97, sk)
		a["react"] = float(a["react"]) - delta
		if bool(a.get("see", true)) and float(a["react"]) <= 0.0:
			dir = 0.0 if not on_log else 1.0
	else:
		a["react"] = 0.0
	if jump and float(a["jumped"]) > 0.0:
		jump = false
	if jump:
		a["jumped"] = 0.25
	return [dir, jump]


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	for s in _P:
		if not _P[s]["done"]:
			return false
	return true


## 순위: 먼저 나간 순 → 못 나갔으면 멀리 간 순
func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	var key := func(p: Dictionary) -> float:
		var P: Dictionary = _P[int(p["slot"])]
		if P["done"]:
			return 10000.0 - float(P["time"])
		return float(P["x"])
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 시간 · 말 자리 · 부목 (방장 → 손님)
func _net_state() -> Dictionary:
	var ps := {}
	for s in _P:
		var P: Dictionary = _P[s]
		ps[s] = [float(P["x"]), float(P["y"]), float(P["face"]), float(P["fall"]), float(P["stun"]), bool(P["done"])]
	var lg := []
	for L in _logs:
		lg.append([float(L["trig"]), float(L.get("load", 0.0))])
	return {"el": _el, "ps": ps, "lg": lg}


func _net_apply(st: Dictionary) -> void:
	_el = float(st.get("el", _el))
	var ps: Dictionary = st.get("ps", {})
	for s in ps:
		var si := int(s)
		if not _P.has(si):
			continue
		var P: Dictionary = _P[si]
		var v: Array = ps[s]
		if si != net_me:
			P["tx"] = float(v[0])
			P["ty"] = float(v[1])
			P["face"] = float(v[2])
			P["fall"] = float(v[3])
			P["stun"] = float(v[4])
		if v.size() >= 6 and bool(v[5]) and not P["done"]:
			P["done"] = true
	var lg: Array = st.get("lg", [])
	for i in mini(lg.size(), _logs.size()):
		var v: Array = lg[i]
		_logs[i]["trig"] = float(v[0])
		_logs[i]["load"] = float(v[1])


func _score_text(p: Dictionary) -> String:
	var P: Dictionary = _P[int(p["slot"])]
	if P["done"]:
		return "%.1fs" % float(P["time"])
	return "%dm" % maxi(0, int(round(FINISH_X - float(P["x"]))))
