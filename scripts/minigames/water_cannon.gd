extends "res://scripts/minigames/minigame_3d.gd"
## 물대포 싸움 (WASD 이동 · 마우스 조준 · 왼쪽 버튼 꾹 = 발사 · 스페이스 연타 = 펌프):
## 바다 위에 뜬 커다란 뗏목 하나. 그 위에 선실 오두막 · 상자 벽 · 통 줄 · 천막 같은 구조물이 놓여 있어
## 위에서 내려다보는 슈팅 게임 맵처럼 통로와 엄폐물이 생김. 구조물은 물줄기를 막아 줌 (숨거나 돌아가서 쏘기).
## 각자 네 귀퉁이 상자 진지에서 시작. 스페이스를 연타해 물통을 채우고 마우스로 겨눠 쏘면, 맞는 동안 체력이 깎임
## (가까이서 맞을수록 많이). 체력이 0이 되면 흠뻑 젖어 쓰러짐 = 탈락. 마지막까지 남은 사람이 승리 (시간이 다 되면 체력 순).
## 바다에 빠지지는 않음 (가장자리는 막힘). 화면은 각자 내 말을 따라감.

const HX := 13.0                ## 뗏목 반 너비 (좌우)
const HZ := 10.0                ## 뗏목 반 길이 (앞뒤)
const RANGE := 6.2              ## 물줄기 길이
const DRAIN := 0.32             ## 쏘는 동안 초당 줄어드는 물
const PUMP := 0.085             ## 펌프 한 번에 차는 물
const KNOCK := 0.9              ## 맞으면 살짝 밀림 (느낌만)
const HP_MAX := 100.0
const DPS_NEAR := 12.0          ## 가까이서 맞을 때 초당 깎이는 체력
const DPS_FAR := 5.0           ## 물줄기 끝에서 맞을 때
const BODY := 0.32              ## 말 반지름 (구조물과 부딪힘)

var _world: Node3D
var _covers: Array = []         ## ["c", 중심 Vector2, 반지름] 또는 ["b", 중심 Vector2, 반크기 Vector2]
var _tank := {}
var _aim := {}
var _spray := {}
var _guns := {}
var _hit_cd := {}
var _fx_cd := {}
var _stagger := {}
var _out_at := {}
var _order := 0
var _wait := 0.0
var _ai := {}
var _aim_send := 0.0
var _was_spray := false
var _jet_mat: StandardMaterial3D
var _cam_f := Vector3.ZERO
var _prev := {}
var _hp := {}
var _bars := {}               ## slot → {root, hp, hp_m, water}
var _flash := {}              ## slot → 맞은 직후 번쩍


func _init() -> void:
	title = "WATER CANNON"
	how_to = "A water fight on a big raft full of crates, barrels and a cabin! Mash SPACE to pump water into your tank, aim with the mouse and hold the left button to spray. Getting hit drains your health - the closer the shot, the more it hurts. At zero you are soaked and out. The structures block the water - use them as cover. Last one standing wins!"
	goal = "Soak everyone out!"
	controls = "KEYS_MOUSE"
	duration = 60.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-58, -25, 0)
	var sea := ocean(-0.6, 220.0, 9.0)
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.6)
	sky_clouds(12, 190.0, 28.0)
	cam.fov = 46.0
	_place_cam(Vector3.ZERO, true)
	_world = Node3D.new()
	world3.add_child(_world)
	_build_raft()
	_build_structures()
	sea_debris(14, 18.0, 34.0, -0.5, 14)
	gulls(5, Vector3(0, 0, -8), 18.0, 7.0, 9)
	island(Vector3(90, -1.5, -170), 22.0, 13.0, 7)
	island(Vector3(-130, -1.5, -120), 15.0, 9.0, 3)
	_jet_mat = StandardMaterial3D.new()
	_jet_mat.albedo_color = Color(0.62, 0.86, 1.0, 0.55)
	_jet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_jet_mat.roughness = 0.05
	_jet_mat.metallic_specular = 1.0
	_jet_mat.emission_enabled = true
	_jet_mat.emission = Color(0.35, 0.6, 0.75)
	_jet_mat.emission_energy_multiplier = 0.3


## 화면: 내 말 (자동이면 살아남은 사람들 가운데) 을 위에서 비스듬히 따라감
func _place_cam(f: Vector3, snap: bool = false, delta: float = 0.0) -> void:
	_cam_f = f if snap else _cam_f.lerp(f, clampf(delta * 3.0, 0.0, 1.0))
	var xf := Transform3D(Basis(), _cam_f + Vector3(0, 14.0, 10.5))
	xf = xf.looking_at(_cam_f + Vector3(0, 0, 0.6), Vector3.UP)
	cam_base = xf
	cam.transform = xf


# ── 뗏목 ────────────────────────────────────────────────────
## 커다란 뗏목: 통나무 받침 위에 햇볕 · 바닷물에 바랜 널판을 가로로 엮고, 가장자리 각목 · 밧줄 매듭 · 밑에 뜬 통
func _build_raft() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	var cols := [Color(0.5, 0.42, 0.33), Color(0.55, 0.46, 0.35), Color(0.46, 0.39, 0.31), Color(0.52, 0.45, 0.36)]
	var mats := []
	for col in cols:
		mats.append(wood_mat(col, Vector3(1, 0, 0), 0.12))
	var pw := 0.5
	var nz := int(HZ * 2.0 / pw)
	for k in nz:
		var z := -HZ + (k + 0.5) * pw
		# 널판 두세 장을 이어 붙인 줄 (이음매가 엇갈림)
		var x := -HX
		var j := 0
		while x < HX - 0.05:
			var ln := minf(rr.randf_range(4.0, 8.5), HX - x)
			box(Vector3(ln - 0.03, 0.15, pw - 0.04), mats[(k + j) % mats.size()], Vector3(x + ln * 0.5, -0.08 + rr.randf_range(-0.01, 0.01), z),
				Basis(Vector3.UP, rr.randf_range(-0.004, 0.004)), _world)
			x += ln
			j += 1
	var beam := wood_mat(Color(0.33, 0.25, 0.17), Vector3(1, 0, 0), 0.3)
	box(Vector3(HX * 2.0 + 0.3, 0.3, 0.3), beam, Vector3(0, -0.2, -HZ), Basis(), _world)
	box(Vector3(HX * 2.0 + 0.3, 0.3, 0.3), beam, Vector3(0, -0.2, HZ), Basis(), _world)
	var beam_z := wood_mat(Color(0.33, 0.25, 0.17), Vector3(0, 0, 1), 0.3)
	box(Vector3(0.3, 0.3, HZ * 2.0), beam_z, Vector3(-HX, -0.2, 0), Basis(), _world)
	box(Vector3(0.3, 0.3, HZ * 2.0), beam_z, Vector3(HX, -0.2, 0), Basis(), _world)
	box(Vector3(HX * 2.0 - 0.4, 0.5, HZ * 2.0 - 0.4), std_mat(Color(0.1, 0.08, 0.06), 0.9), Vector3(0, -0.5, 0), Basis(), _world)
	# 밧줄 매듭 (가장자리 각목을 따라)
	var rope := std_mat(Color(0.58, 0.47, 0.32), 0.95)
	var t := TorusMesh.new()
	t.inner_radius = 0.16
	t.outer_radius = 0.2
	var xx := -HX + 1.0
	while xx < HX:
		for sz: float in [-1.0, 1.0]:
			add_mesh(t, rope, Vector3(xx, -0.2, sz * HZ), Basis(Vector3.FORWARD, PI / 2), _world)
		xx += 2.2
	# 밑에 뜬 통
	for x: float in [-HX + 1.0, -HX * 0.5, 0.0, HX * 0.5, HX - 1.0]:
		for z: float in [-HZ + 0.5, 0.0, HZ - 0.5]:
			var b := barrel(_world, Vector3(x, -0.62, z), 0.4, 1.0, Color(0.32, 0.22, 0.13))
			b.rotation = Vector3(PI / 2, 0, 0)


# ── 구조물 ──────────────────────────────────────────────────
## 나무 상자 하나 (모서리 각목)
func _crate(p: Vector3, s: float, yaw: float, rr: RandomNumberGenerator) -> void:
	var cn := Node3D.new()
	cn.position = p
	cn.rotation.y = yaw
	_world.add_child(cn)
	var wm := wood_mat(Color(0.56, 0.43, 0.28).darkened(rr.randf_range(0.0, 0.15)), Vector3(1, 0, 0), 0.12)
	var edge := wood_mat(Color(0.38, 0.28, 0.18), Vector3(0, 1, 0), 0.12)
	box(Vector3(s, s, s), wm, Vector3(0, s * 0.5, 0), Basis(), cn)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(Vector3(0.06, s + 0.02, 0.06), edge, Vector3(sx * s * 0.5, s * 0.5, sz * s * 0.5), Basis(), cn)
	box(Vector3(s + 0.02, 0.06, 0.06), edge, Vector3(0, s, s * 0.5), Basis(), cn)
	box(Vector3(s + 0.02, 0.06, 0.06), edge, Vector3(0, s, -s * 0.5), Basis(), cn)


## 상자 벽: 가로(또는 세로)로 줄지어 쌓은 상자 (2단, 군데군데 1단)
func _crate_wall(c: Vector2, half: Vector2, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var along_x := half.x >= half.y
	var L := (half.x if along_x else half.y) * 2.0
	var n := maxi(1, int(round(L / 0.72)))
	var s := L / n
	for k in n:
		var t := -L * 0.5 + (k + 0.5) * s
		var p := Vector3(c.x + (t if along_x else 0.0), 0, c.y + (0.0 if along_x else t))
		_crate(p, s * 0.96, rr.randf_range(-0.06, 0.06), rr)
		if rr.randf() < 0.7:
			_crate(p + Vector3(rr.randf_range(-0.04, 0.04), s * 0.96, rr.randf_range(-0.04, 0.04)), s * 0.9, rr.randf_range(-0.12, 0.12), rr)
	_covers.append(["b", c, half])


## 통 줄: 통을 한 줄로 빽빽이 세움
func _barrel_row(c: Vector2, half: Vector2, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var along_x := half.x >= half.y
	var L := (half.x if along_x else half.y) * 2.0
	var n := maxi(1, int(round(L / 0.74)))
	for k in n:
		var t := -L * 0.5 + (k + 0.5) * L / n
		var p := Vector3(c.x + (t if along_x else 0.0), 0, c.y + (0.0 if along_x else t))
		barrel(_world, p, 0.34, 0.95, [Color(0.42, 0.28, 0.16), Color(0.36, 0.24, 0.14), Color(0.46, 0.31, 0.18)][k % 3])
	_covers.append(["b", c, half])


## 선실 오두막: 널빤지 벽 + 지붕 + 창 + 문 (들어갈 수는 없음, 큰 엄폐물)
func _cabin(c: Vector2, half: Vector2) -> void:
	var p := Vector3(c.x, 0, c.y)
	var wall := wood_mat(Color(0.45, 0.32, 0.2), Vector3(0, 1, 0), 0.15)
	var trim := wood_mat(Color(0.3, 0.2, 0.12), Vector3(0, 1, 0), 0.15)
	var h := 1.9
	box(Vector3(half.x * 2.0, h, half.y * 2.0), wall, p + Vector3(0, h * 0.5, 0), Basis(), _world)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(Vector3(0.14, h + 0.05, 0.14), trim, p + Vector3(sx * half.x, h * 0.5, sz * half.y), Basis(), _world)
	# 판자 이음 줄
	var k := -half.x + 0.3
	while k < half.x:
		box(Vector3(0.03, h - 0.05, half.y * 2.0 + 0.02), trim, p + Vector3(k, h * 0.5, 0), Basis(), _world)
		k += 0.3
	# 박공 지붕 (타르 칠한 천)
	var roof := wood_mat(Color(0.36, 0.26, 0.17), Vector3(1, 0, 0), 0.2)   # 지붕널
	for sd: float in [-1.0, 1.0]:
		box(Vector3(half.x * 2.0 + 0.5, 0.08, half.y + 0.45), roof, p + Vector3(0, h + 0.38, sd * (half.y * 0.5 + 0.1)), Basis(Vector3.RIGHT, -sd * 0.55), _world)
	box(Vector3(half.x * 2.0 + 0.55, 0.12, 0.14), trim, p + Vector3(0, h + 0.68, 0), Basis(), _world)
	# 창 (앞 · 뒤) · 문 (앞) · 굴뚝 대신 연통
	var glass := std_mat(Color(0.25, 0.35, 0.4), 0.1, 0.2)
	for sd: float in [-1.0, 1.0]:
		box(Vector3(0.6, 0.45, 0.05), glass, p + Vector3(-half.x * 0.45, 1.25, sd * (half.y + 0.02)), Basis(), _world)
		box(Vector3(0.7, 0.07, 0.08), trim, p + Vector3(-half.x * 0.45, 1.0, sd * (half.y + 0.03)), Basis(), _world)
	box(Vector3(0.75, 1.5, 0.06), trim, p + Vector3(half.x * 0.4, 0.75, half.y + 0.03), Basis(), _world)
	var knob := SphereMesh.new()
	knob.radius = 0.04
	knob.height = 0.08
	add_mesh(knob, std_mat(Color(0.8, 0.6, 0.25), 0.3, 0.9), p + Vector3(half.x * 0.4 + 0.25, 0.78, half.y + 0.08), Basis(), _world)
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.09
	pipe.bottom_radius = 0.09
	pipe.height = 0.8
	add_mesh(pipe, std_mat(Color(0.18, 0.17, 0.16), 0.5, 0.6), p + Vector3(half.x * 0.6, h + 0.8, -half.y * 0.3), Basis(), _world)
	_covers.append(["b", c, half])


func _cover(parent: Node3D, kind: int, c: Vector2, _rid: int, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var p := Vector3(c.x, 0, c.y)
	var r := 0.75
	match kind:
		0:   # 나무 상자 더미 (2~3단)
			var wm := wood_mat(Color(0.56, 0.43, 0.28), Vector3(1, 0, 0), 0.12)
			var edge := wood_mat(Color(0.38, 0.28, 0.18), Vector3(0, 1, 0), 0.12)
			var spots := [[Vector3(-0.32, 0, -0.2), 0.7], [Vector3(0.38, 0, 0.18), 0.65], [Vector3(0.0, 0.68, 0.0), 0.6]]
			for sp: Array in spots:
				var cn := Node3D.new()
				cn.position = p + (sp[0] as Vector3)
				cn.rotation.y = rr.randf_range(-0.4, 0.4)
				parent.add_child(cn)
				var s := float(sp[1])
				box(Vector3(s, s, s), wm, Vector3(0, s * 0.5, 0), Basis(), cn)
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						box(Vector3(0.06, s + 0.02, 0.06), edge, Vector3(sx * s * 0.5, s * 0.5, sz * s * 0.5), Basis(), cn)
			r = 0.8
		1:   # 통 무더기 (세 개 + 위에 하나)
			for k in 3:
				var a := k * TAU / 3.0 + 0.4
				barrel(parent, p + Vector3(cos(a), 0, sin(a)) * 0.38, 0.32, 0.85, Color(0.42, 0.28, 0.16))
			var tb := barrel(parent, p + Vector3(0, 0.45, 0), 0.3, 0.8, Color(0.38, 0.25, 0.14))
			tb.rotation = Vector3(PI / 2, 0.7, 0)
			r = 0.72
		2:   # 낡은 돛천으로 친 천막 (막대 두 개 + 처진 천)
			var cloth := std_mat(Color(0.74, 0.67, 0.52), 0.95)   # 바닷물에 바랜 돛천
			cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
			var pole := wood_mat(Color(0.45, 0.33, 0.2), Vector3(0, 1, 0), 0.1)
			for sx: float in [-0.85, 0.85]:
				var pm := CylinderMesh.new()
				pm.top_radius = 0.04
				pm.bottom_radius = 0.05
				pm.height = 1.3
				add_mesh(pm, pole, p + Vector3(sx, 0.65, 0), Basis(), parent)
			# A자 천막: 꼭대기 줄에서 양옆으로 비스듬히 내려온 천 두 장 (가운데가 살짝 처짐)
			for sd: float in [-1.0, 1.0]:
				var q := QuadMesh.new()
				q.size = Vector2(1.9, 1.35)
				q.subdivide_width = 6
				add_mesh(q, cloth, p + Vector3(0, 0.74, sd * 0.42), Basis(Vector3.RIGHT, -sd * 0.68), parent)
			var ridge := CylinderMesh.new()
			ridge.top_radius = 0.03
			ridge.bottom_radius = 0.03
			ridge.height = 1.9
			add_mesh(ridge, std_mat(Color(0.5, 0.4, 0.28), 0.9), p + Vector3(0, 1.26, 0), Basis(Vector3.FORWARD, PI / 2), parent)
			# 천막 꼭대기에 찢어진 깃발
			var fp := CylinderMesh.new()
			fp.top_radius = 0.025
			fp.bottom_radius = 0.03
			fp.height = 1.2
			add_mesh(fp, pole, p + Vector3(0.85, 1.85, 0), Basis(), parent)
			var fl := QuadMesh.new()
			fl.size = Vector2(0.55, 0.32)
			var fm := std_mat(Color(0.75, 0.2, 0.15), 0.9)
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			add_mesh(fl, fm, p + Vector3(1.13, 2.25, 0), Basis(), parent)
			r = 0.95
		3:   # 빗물 받는 큰 통 (뚜껑 없이 물이 찰랑)
			var big := barrel(parent, p, 0.48, 1.0, Color(0.36, 0.24, 0.14))
			big.scale = Vector3(1, 1, 1)
			var wq := CylinderMesh.new()
			wq.top_radius = 0.42
			wq.bottom_radius = 0.42
			wq.height = 0.02
			var wmat := std_mat(Color(0.25, 0.45, 0.55), 0.05)
			add_mesh(wq, wmat, p + Vector3(0, 0.9, 0), Basis(), parent)
			r = 0.55
	_covers.append(["c", c, r])


## 맵: 네 귀퉁이 상자 진지 · 가운데 선실 · 변 가운데 통 줄 / 상자 벽 · 사이사이 엄폐물. 통로는 넉넉히
func _build_structures() -> void:
	_cabin(Vector2(0, 0), Vector2(1.7, 1.2))
	# 귀퉁이 진지: ㄱ자 상자 벽 (출발 자리를 안쪽으로 감쌈)
	var seed_ := 100
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_crate_wall(Vector2(sx * 8.6, sz * 5.6), Vector2(1.45, 0.36), seed_)
			_crate_wall(Vector2(sx * 6.9, sz * 7.3), Vector2(0.36, 1.1), seed_ + 1)
			seed_ += 2
	# 변 가운데: 위 · 아래는 통 줄, 왼쪽 · 오른쪽은 세로 상자 벽
	_barrel_row(Vector2(0, -6.0), Vector2(1.85, 0.36), 7)
	_barrel_row(Vector2(0, 6.0), Vector2(1.85, 0.36), 8)
	_crate_wall(Vector2(-7.6, 0), Vector2(0.36, 1.45), 9)
	_crate_wall(Vector2(7.6, 0), Vector2(0.36, 1.45), 10)
	# 사이사이 엄폐물 (대각선 대칭)
	_cover(_world, 1, Vector2(-4.2, -3.0), -1, 21)
	_cover(_world, 1, Vector2(4.2, 3.0), -1, 22)
	_cover(_world, 0, Vector2(4.4, -3.2), -1, 23)
	_cover(_world, 0, Vector2(-4.4, 3.2), -1, 24)
	_cover(_world, 0, Vector2(-10.6, 0.0), -1, 25)
	_cover(_world, 3, Vector2(10.6, 0.0), -1, 26)
	_cover(_world, 3, Vector2(0.0, -8.6), -1, 27)
	_cover(_world, 1, Vector2(0.0, 8.6), -1, 28)
	# 엄폐물이 아닌 바닥 소품 (밧줄 더미 · 양동이)
	deck_clutter(_world, [Vector3(-11.8, 0, -9.0), Vector3(11.8, 0, 9.0), Vector3(-2.6, 0, -1.9), Vector3(2.8, 0, 1.9)], 41)


# ── 바닥 · 엄폐물 판정 ──────────────────────────────────────
func _walkable(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) <= HX + margin and absf(p.z) <= HZ + margin


func _edge_dist(p: Vector3) -> float:
	return minf(HX - absf(p.x), HZ - absf(p.z))


func _nearest_walkable(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -HX + 0.6, HX - 0.6), p.y, clampf(p.z, -HZ + 0.6, HZ - 0.6))


## 물줄기(반직선)가 구조물에 막히는 거리 (없으면 INF)
func _cover_block(from: Vector3, dir: Vector3) -> float:
	var best := INF
	for cv in _covers:
		var c: Vector2 = cv[1]
		if cv[0] == "c":
			var rel := Vector3(c.x - from.x, 0, c.y - from.z)
			var along := rel.dot(dir)
			if along <= 0.0:
				continue
			var lat2 := rel.length_squared() - along * along
			var r := float(cv[2])
			if lat2 < r * r:
				best = minf(best, along - sqrt(r * r - lat2))
		else:
			var h: Vector2 = cv[2]
			var t0 := -INF
			var t1 := INF
			var ok := true
			for ax in 2:
				var o := from.x if ax == 0 else from.z
				var d := dir.x if ax == 0 else dir.z
				var lo := (c.x - h.x) if ax == 0 else (c.y - h.y)
				var hi := (c.x + h.x) if ax == 0 else (c.y + h.y)
				if absf(d) < 0.0001:
					if o < lo or o > hi:
						ok = false
						break
				else:
					var a := (lo - o) / d
					var b := (hi - o) / d
					t0 = maxf(t0, minf(a, b))
					t1 = minf(t1, maxf(a, b))
			if ok and t1 >= maxf(t0, 0.0) and t0 > 0.0:
				best = minf(best, t0)
	return best


## 구조물과 겹치면 바깥으로 밀어냄
func _push_out(pos: Vector3) -> Vector3:
	for cv in _covers:
		var c: Vector2 = cv[1]
		if cv[0] == "c":
			var d := Vector2(pos.x - c.x, pos.z - c.y)
			var rr := float(cv[2]) + BODY
			if d.length() < rr and d.length() > 0.001:
				d = d.normalized() * rr
				pos.x = c.x + d.x
				pos.z = c.y + d.y
		else:
			var h: Vector2 = (cv[2] as Vector2) + Vector2(BODY, BODY)
			var dx := pos.x - c.x
			var dz := pos.z - c.y
			if absf(dx) < h.x and absf(dz) < h.y:
				# 가장 얕게 겹친 쪽으로 밀어냄
				if h.x - absf(dx) < h.y - absf(dz):
					pos.x = c.x + signf(dx if dx != 0.0 else 1.0) * h.x
				else:
					pos.z = c.y + signf(dz if dz != 0.0 else 1.0) * h.y
	return pos


func _setup_game() -> void:
	walk_radius = 999.0
	var spots := [Vector3(-10.6, 0, -7.9), Vector3(10.6, 0, 7.9), Vector3(10.6, 0, -7.9), Vector3(-10.6, 0, 7.9)]
	for i in players.size():
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var spot: Vector3 = spots[i % 4]
		var w := add_walker(p, spot, 4.6)
		w["face"] = atan2(-spot.x, -spot.z)
		_tank[s] = 0.3
		_hp[s] = HP_MAX
		_bars[s] = _make_bars()
		_aim[s] = float(w["face"])
		_spray[s] = false
		_ai[s] = {"t": 0.0, "goal": w["pos"], "target": -1, "pump": 0.0, "detour": Vector3.ZERO, "detour_t": 0.0, "stuck": 0.0}
		_guns[s] = _make_gun(w["node"])
		scores[s] = HP_MAX
	_place_cam(_focus(), true)


func _make_gun(pawn: Node3D) -> Dictionary:
	var brass := std_mat(Color(0.85, 0.62, 0.25), 0.28, 0.9)
	var copper := std_mat(Color(0.88, 0.52, 0.3), 0.3, 0.85)
	var rubber := std_mat(Color(0.08, 0.08, 0.09), 0.7)
	var gun := Node3D.new()
	gun.position = Vector3(0.22, 0.5, 0.2)
	pawn.add_child(gun)
	var barrel_m := CylinderMesh.new()
	barrel_m.top_radius = 0.045
	barrel_m.bottom_radius = 0.07
	barrel_m.height = 0.56
	barrel_m.radial_segments = 16
	add_mesh(barrel_m, brass, Vector3(0, 0, 0.26), Basis(Vector3.RIGHT, PI / 2), gun)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.075
	add_mesh(ring, brass, Vector3(0, 0, 0.54), Basis(Vector3.RIGHT, PI / 2), gun)
	add_mesh(ring, brass, Vector3(0, 0, 0.08), Basis(Vector3.RIGHT, PI / 2), gun)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.05, 0.14, 0.06)
	add_mesh(grip, std_mat(Color(0.35, 0.22, 0.12), 0.7), Vector3(0, -0.08, 0.04), Basis(Vector3.RIGHT, -0.3), gun)
	var tank := Node3D.new()
	tank.position = Vector3(0, 0.5, -0.24)
	tank.scale = Vector3.ONE * 0.8
	pawn.add_child(tank)
	var tm := CylinderMesh.new()
	tm.top_radius = 0.13
	tm.bottom_radius = 0.13
	tm.height = 0.42
	tm.radial_segments = 18
	add_mesh(tm, copper, Vector3.ZERO, Basis(), tank)
	for y: float in [-0.18, 0.18]:
		var band := CylinderMesh.new()
		band.top_radius = 0.137
		band.bottom_radius = 0.137
		band.height = 0.03
		add_mesh(band, brass, Vector3(0, y, 0), Basis(), tank)
	var cap := SphereMesh.new()
	cap.radius = 0.13
	cap.height = 0.12
	add_mesh(cap, copper, Vector3(0, 0.21, 0), Basis(), tank)
	# 물 높이 창 (뒤쪽, 파란 물이 차오름)
	var glass := BoxMesh.new()
	glass.size = Vector3(0.06, 0.32, 0.01)
	add_mesh(glass, std_mat(Color(0.1, 0.12, 0.14), 0.2), Vector3(0, 0, -0.135), Basis(), tank)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.3, 0.75, 1.0)
	water.emission_enabled = true
	water.emission = Color(0.2, 0.6, 1.0)
	water.emission_energy_multiplier = 0.8
	var fill := Node3D.new()
	fill.position = Vector3(0, -0.15, -0.142)
	tank.add_child(fill)
	var fb := BoxMesh.new()
	fb.size = Vector3(0.045, 0.3, 0.005)
	add_mesh(fb, water, Vector3(0, 0.15, 0), Basis(), fill)
	# 호스: 물통 아래 → 물대포 손잡이 (몇 마디로 처짐)
	var a := Vector3(0.08, 0.4, -0.2)
	var b := Vector3(0.2, 0.46, 0.18)
	var prev := a
	for k in 5:
		var t := (k + 1) / 5.0
		var q := a.lerp(b, t) + Vector3(0, -sin(t * PI) * 0.1, 0)
		var d := q - prev
		var hc := CylinderMesh.new()
		hc.top_radius = 0.018
		hc.bottom_radius = 0.018
		hc.height = d.length() + 0.01
		hc.radial_segments = 6
		add_mesh(hc, rubber, (q + prev) * 0.5, Basis(Quaternion(Vector3.UP, d.normalized())), pawn)
		prev = q
	# 물줄기: 물방울 덩어리들이 총구에서 맞는 자리까지 이어져 흐름 (매 프레임 _show 에서 자리 잡음)
	var blobs := []
	var bm := SphereMesh.new()
	bm.radius = 0.1
	bm.height = 0.2
	bm.radial_segments = 10
	bm.rings = 5
	for k in 18:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _jet_mat_or_new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		world3.add_child(mi)
		blobs.append(mi)
	return {"gun": gun, "blobs": blobs, "fill": fill}


func _jet_mat_or_new() -> StandardMaterial3D:
	if _jet_mat == null:
		_jet_mat = StandardMaterial3D.new()
	return _jet_mat


## 머리 위 막대: 체력 (굵게) + 물 (가늘게). 늘 카메라를 봄
func _make_bars() -> Dictionary:
	var root := Node3D.new()
	world3.add_child(root)
	var mk := func(col: Color, size: Vector2, pri: int) -> MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.no_depth_test = true
		m.render_priority = pri
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = col
		var q := QuadMesh.new()
		q.size = size
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		return mi
	var bg: MeshInstance3D = mk.call(Color(0.05, 0.06, 0.08, 0.8), Vector2(1.0, 0.24), 2)
	bg.position = Vector3(0, 0.05, 0)
	var hp: MeshInstance3D = mk.call(Color(0.35, 0.9, 0.4), Vector2(0.92, 0.11), 3)
	hp.position = Vector3(0, 0.095, 0)
	var water: MeshInstance3D = mk.call(Color(0.35, 0.75, 1.0), Vector2(0.92, 0.05), 3)
	water.position = Vector3(0, -0.02, 0)
	return {"root": root, "hp": hp, "water": water}


func _start_game() -> void:
	pass


func _alive() -> Array:
	return walkers.keys().filter(func(s: int) -> bool: return not walkers[s]["out"])


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
		net_input("pump")
		sfx("pump", 60)


func _net_input(slot: int, action: String, args: Array) -> void:
	if not playing:
		return
	match action:
		"pump":
			_tank[slot] = minf(1.0, float(_tank.get(slot, 0.0)) + PUMP)
		"aim":
			if args.size() >= 2:
				_aim[slot] = float(args[0])
				_spray[slot] = bool(args[1])


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_t3 += delta
	var pr := pressure()
	_local_aim(delta)
	if not is_client():
		_think(delta)
	for s in walkers:
		walkers[s]["speed"] = 2.8 if bool(_spray.get(s, false)) and float(_tank.get(s, 0.0)) > 0.0 else 4.6
		_prev[s] = walkers[s]["pos"]
	step_walkers(delta)
	_keep_on_raft()
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"]:
			continue
		if bool(_spray.get(s, false)) or is_local(w["p"]):
			w["face"] = lerp_angle(float(w["face"]), float(_aim.get(s, w["face"])), clampf(delta * 14.0, 0.0, 1.0))
			(w["node"] as Node3D).rotation.y = float(w["face"])
	if not is_client():
		_sprays(delta, pr)
	_show(delta)
	if _wait > 0.0:
		_wait -= delta
	_place_cam(_focus(), false, delta)


func _focus() -> Vector3:
	var me := local_slot()
	if walkers.has(me) and is_local(walkers[me]["p"]) and not walkers[me]["out"]:
		return walkers[me]["pos"]
	var al := _alive()
	if al.is_empty():
		return _cam_f
	var c := Vector3.ZERO
	for s in al:
		c += walkers[s]["pos"] as Vector3
	return c / al.size()


## 가장자리 밖으로는 못 나감 (바다에 안 빠짐). 구조물은 못 뚫고 지나감
func _keep_on_raft() -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"] or w.has("net_pos"):
			continue
		var pos: Vector3 = w["pos"]
		pos.x = clampf(pos.x, -HX + 0.3, HX - 0.3)
		pos.z = clampf(pos.z, -HZ + 0.3, HZ - 0.3)
		pos = _push_out(pos)
		w["pos"] = pos
		(w["node"] as Node3D).position.x = pos.x
		(w["node"] as Node3D).position.z = pos.z


## 내 물대포: 마우스 쪽으로 겨눔, 왼쪽 버튼 누르는 동안 발사 (방장에게 알림)
func _local_aim(delta: float) -> void:
	var s := local_slot()
	if not walkers.has(s) or walkers[s]["out"] or demo:
		return
	var w: Dictionary = walkers[s]
	if not is_local(w["p"]):
		return
	var mg := mouse_ground(0.5)
	var d: Vector3 = mg - (w["pos"] as Vector3)
	var yaw := float(_aim.get(s, 0.0))
	if Vector2(d.x, d.z).length() > 0.2:
		yaw = atan2(d.x, d.z)
	var on := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_aim[s] = yaw
	_spray[s] = on
	_aim_send -= delta
	if on != _was_spray or _aim_send <= 0.0:
		_aim_send = 0.08
		_was_spray = on
		net_input("aim", [yaw, on])


## 겨눈 쪽으로 물줄기가 처음 닿는 사람 (구조물에 먼저 막히면 -1). [slot, 거리, 막힌 거리]
func _ray_hit(s: int) -> Array:
	var w: Dictionary = walkers[s]
	var yaw := float(_aim.get(s, 0.0))
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	var from: Vector3 = (w["pos"] as Vector3) + dir * 0.5
	var block := minf(_cover_block(from, dir), RANGE)
	var best := -1
	var best_along := block
	for o in _alive():
		if o == s:
			continue
		var rel: Vector3 = (walkers[o]["pos"] as Vector3) - from
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < 0.0 or along > best_along:
			continue
		var lat := (rel - dir * along).length()
		if lat < 0.7 + along * 0.08:   # 물줄기는 멀수록 퍼짐
			best_along = along
			best = o
	return [best, best_along, block]


## 방장: 물줄기 판정. 처음 닿는 사람을 밀어냄 (가까울수록 세게). 구조물 뒤는 안전
func _sprays(delta: float, pr: float) -> void:
	for k in _hit_cd.keys():
		_hit_cd[k] = float(_hit_cd[k]) - delta
	for k in _stagger.keys():
		_stagger[k] = float(_stagger[k]) - delta
	for s in _alive():
		var on := bool(_spray.get(s, false)) and float(_tank[s]) > 0.0 and float(_stagger.get(s, 0.0)) <= 0.0
		if not on:
			continue
		_tank[s] = maxf(0.0, float(_tank[s]) - DRAIN * delta)
		var hr := _ray_hit(s)
		var best := int(hr[0])
		if best < 0:
			continue
		var key := "%d_%d" % [s, best]
		if float(_hit_cd.get(key, 0.0)) > 0.0:
			continue
		_hit_cd[key] = 0.09
		var yaw := float(_aim[s])
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var dmg := lerpf(DPS_NEAR, DPS_FAR, float(hr[1]) / RANGE) * lerpf(1.0, 1.2, pr) * 0.09
		_hp[best] = maxf(0.0, float(_hp[best]) - dmg)
		scores[best] = float(_hp[best])
		net_push(best, dir * KNOCK, 0.15)
		if float(_hp[best]) <= 0.0:
			net_call("_ko", [best])
		var facing := Vector3(sin(float(_aim.get(best, 0.0))), 0, cos(float(_aim.get(best, 0.0))))
		if facing.dot(-dir) > 0.3:
			_stagger[best] = 0.2




## 체력 0: 흠뻑 젖어 옆으로 쓰러짐 (탈락). 물보라 + 물웅덩이
func _ko(s: int) -> void:
	var w: Dictionary = walkers[s]
	if w["out"]:
		return
	w["out"] = true
	if OS.get_environment("MG_DEBUG") != "":
		print("MGKO slot %d t=%.1f" % [s, duration - time_left])
	_out_at[s] = _order
	_order += 1
	_hp[s] = 0.0
	scores[s] = 0
	_spray[s] = false
	_wait = 1.6
	var n: Node3D = w["node"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	sfx("splash")
	splash(n.global_position + Vector3(0, 0.9, 0), 40, 0.9)
	var tw := create_tween()
	tw.tween_property(n, "rotation:z", side * 1.45, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(n, "position:y", 0.15, 0.45)
	var pud := QuadMesh.new()
	pud.size = Vector2(1.4, 1.4)
	pud.orientation = PlaneMesh.FACE_Y
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.3, 0.55, 0.7, 0.45)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.02
	pm.metallic_specular = 1.0
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	pm.albedo_texture = g
	var pd := add_mesh(pud, pm, Vector3(n.position.x, 0.02, n.position.z), Basis(), _world)
	pd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pd.scale = Vector3.ONE * 0.2
	create_tween().tween_property(pd, "scale", Vector3.ONE, 0.6)


## 보여주기 (모든 PC): 물줄기 · 맞은 자리 물보라 · 등 물통 눈금 · 쏘는 소리. 엄폐물에 막히면 거기서 튐
func _show(delta: float) -> void:
	for s in _bars:
		var bd: Dictionary = _bars[s]
		var w0: Dictionary = walkers[s]
		var root: Node3D = bd["root"]
		root.visible = not w0["out"]
		root.position = (w0["node"] as Node3D).position + Vector3(0, 1.75, 0)
		var hp := clampf(float(_hp.get(s, HP_MAX)) / HP_MAX, 0.0, 1.0)
		var tk := clampf(float(_tank.get(s, 0.0)), 0.0, 1.0)
		var hb: MeshInstance3D = bd["hp"]
		hb.scale = Vector3(maxf(hp, 0.001), 1, 1)
		hb.position.x = -0.46 * (1.0 - hp)
		var wb: MeshInstance3D = bd["water"]
		wb.scale = Vector3(maxf(tk, 0.001), 1, 1)
		wb.position.x = -0.46 * (1.0 - tk)
		# 체력이 줄었으면 잠깐 하얗게 번쩍
		var last := float(bd.get("last", hp))
		if hp < last - 0.001:
			_flash[s] = 0.12
		bd["last"] = hp
		_flash[s] = maxf(0.0, float(_flash.get(s, 0.0)) - delta)
		var col := Color(0.95, 0.25, 0.2).lerp(Color(1.0, 0.8, 0.2), clampf(hp * 2.0, 0.0, 1.0)).lerp(Color(0.35, 0.9, 0.4), clampf(hp * 2.0 - 1.0, 0.0, 1.0))
		if float(_flash[s]) > 0.0:
			col = Color(1, 1, 1)
		(hb.material_override as StandardMaterial3D).albedo_color = col
	for s in _guns:
		var g: Dictionary = _guns[s]
		var w: Dictionary = walkers[s]
		var on: bool = bool(_spray.get(s, false)) and float(_tank.get(s, 0.0)) > 0.0 and not w["out"]
		(g["fill"] as Node3D).scale = Vector3(1, maxf(0.02, float(_tank.get(s, 0.0))), 1)
		var blobs: Array = g["blobs"]
		if not on:
			for b in blobs:
				(b as Node3D).visible = false
			continue
		if is_local(w["p"]) or demo:
			sfx("spray", 520)
		var yaw := float(_aim.get(s, 0.0))
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var nozzle: Vector3 = (g["gun"] as Node3D).global_transform * Vector3(0, 0, 0.58)
		var hr := _ray_hit(s)
		var hit_at: Vector3
		var short := true
		if int(hr[0]) >= 0:
			hit_at = (walkers[int(hr[0])]["pos"] as Vector3) + Vector3(0, 0.75, 0) - dir * 0.3
		elif float(hr[2]) < RANGE:
			hit_at = (w["pos"] as Vector3) + dir * (0.5 + float(hr[2])) + Vector3(0, 0.6, 0)
		else:
			hit_at = (w["pos"] as Vector3) + dir * (RANGE + 0.5)
			hit_at.y = 0.05
			short = false
		var n := blobs.size()
		var sag := 0.35 if short else 0.0
		for k in n:
			var t := fmod(float(k) / n + _t3 * 2.6, 1.0)
			var p := nozzle.lerp(hit_at, t)
			p.y -= sin(t * PI) * sag + (t * t * 0.4 if not short else 0.0)
			p += Vector3(sin(_t3 * 31.0 + k * 1.7), cos(_t3 * 27.0 + k * 2.3), 0) * 0.04 * t
			var b: MeshInstance3D = blobs[k]
			b.visible = true
			b.global_position = p
			var sc := lerpf(0.55, 1.5, t)
			b.scale = Vector3(sc, sc, sc * 1.8)
			b.look_at(p + dir + Vector3(0, 0.001, 0), Vector3.UP)
		_fx_cd[s] = float(_fx_cd.get(s, 0.0)) - delta
		if float(_fx_cd[s]) <= 0.0:
			_fx_cd[s] = 0.1
			splash(hit_at, 7, 0.4)


# ── CPU ─────────────────────────────────────────────────────
## 목표까지 곧장 가다 구조물에 막히면 옆으로 비켜 돌아감
func _steer(s: int, pos: Vector3, goal: Vector3, delta: float) -> Vector3:
	var a: Dictionary = _ai[s]
	a["detour_t"] = maxf(0.0, float(a["detour_t"]) - delta)
	if float(a["detour_t"]) > 0.0:
		return a["detour"]
	var to := goal - pos
	to.y = 0.0
	var dist := to.length()
	if dist < 0.3:
		return goal
	var dir := to / dist
	var block := _cover_block(pos, dir)
	# 제자리걸음 감지 (구석에 끼임)
	var moved := ((_prev.get(s, pos) as Vector3) - pos).length()
	a["stuck"] = float(a["stuck"]) + delta if moved < 0.01 and dist > 1.0 else 0.0
	if block < minf(dist, 2.2) or float(a["stuck"]) > 0.4:
		var side := Vector3(-dir.z, 0, dir.x)
		if rng.randf() < 0.5:
			side = -side
		# 덜 막힌 쪽으로
		if _cover_block(pos, (dir + side).normalized()) < _cover_block(pos, (dir - side).normalized()):
			side = -side
		a["detour"] = _nearest_walkable(pos + (side * 2.2 + dir * 0.6))
		a["detour_t"] = 0.7
		a["stuck"] = 0.0
		return a["detour"]
	return goal


## 물이 적으면 구조물 뒤에 숨어 펌프질, 물이 있으면 상대가 가장자리 쪽으로 밀리게 반대편에서 겨눠 쏨.
## 시야가 트였을 때만 쏨. 실력이 좋을수록 정확히 겨누고 펌프도 빠름
func _think(delta: float) -> void:
	for s in _alive():
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p)
		var pos: Vector3 = w["pos"]
		var tank := float(_tank[s])
		var want_pump := tank < lerpf(0.3, 0.45, sk / 2.0) or (tank < 0.9 and not bool(_spray[s]))
		if want_pump:
			a["pump"] = float(a["pump"]) - delta
			var guard := 0
			while float(a["pump"]) <= 0.0 and guard < 6:
				guard += 1
				a["pump"] = float(a["pump"]) + 1.0 / (lerpf(4.5, 8.0, sk / 2.0) * rng.randf_range(0.85, 1.15))
				_tank[s] = minf(1.0, float(_tank[s]) + PUMP)
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.45, 0.18, sk / 2.0) + rng.randf_range(0.0, 0.12)
			var best := -1
			var bv := INF
			for o in _alive():
				if o == s:
					continue
				var op: Vector3 = walkers[o]["pos"]
				var v := op.distance_to(pos) * 0.6 + float(_hp.get(o, HP_MAX)) * 0.03
				if v < bv:
					bv = v
					best = o
			a["target"] = best
			var goal := pos
			if best >= 0:
				var tp: Vector3 = walkers[best]["pos"]
				var away := pos - tp
				away.y = 0.0
				away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
				var cen := -tp
				cen.y = 0.0
				cen = cen.normalized() if cen.length() > 0.1 else Vector3.ZERO
				goal = _attack_spot(pos, tp, lerpf(4.0, 3.2, sk / 2.0))
			if tank < 0.2 or (float(_hp[s]) < lerpf(25.0, 45.0, sk / 2.0) and tank < 0.6):
				# 물이 없거나 다쳤으면 가까운 구조물 뒤(상대 반대쪽)로 숨어 펌프질
				goal = _hide_spot(pos, best)
			a["goal"] = _nearest_walkable(goal)
			a["err"] = rng.randf_range(-1.0, 1.0) * lerpf(0.2, 0.04, sk / 2.0)
		var tg := int(a["target"])
		if tg >= 0 and walkers.has(tg) and not walkers[tg]["out"]:
			var tp2: Vector3 = (walkers[tg]["pos"] as Vector3) + (walkers[tg]["vel"] as Vector3) * 0.15
			var d := tp2 - pos
			d.y = 0.0
			var want := atan2(d.x, d.z) + float(a.get("err", 0.0))
			_aim[s] = lerp_angle(float(_aim[s]), want, clampf(delta * lerpf(6.0, 14.0, sk / 2.0), 0.0, 1.0))
			var clear := d.length() < 0.1 or _cover_block(pos + d.normalized() * 0.5, d.normalized()) > d.length() - 0.6
			_spray[s] = d.length() < RANGE - 0.4 and clear and float(_tank[s]) > 0.05 and not (float(_tank[s]) < 0.3 and want_pump)
		else:
			_spray[s] = false
		w["target"] = _steer(s, pos, a["goal"], delta)
		if OS.get_environment("MG_DEBUG") != "" and fmod(_t3, 1.0) < delta:
			print("WCDBG t=%.1f s=%d pos=(%.1f,%.1f) goal=(%.1f,%.1f) tgt=(%.1f,%.1f) det=%.2f stuck=%.2f" % [_t3, s, pos.x, pos.z, (a["goal"] as Vector3).x, (a["goal"] as Vector3).z, (w["target"] as Vector3).x, (w["target"] as Vector3).z, float(a["detour_t"]), float(a["stuck"])])


## 상대를 쏠 수 있는 자리: 상대 둘레 (반지름 r) 중 물줄기가 막히지 않고, 바닥 안 · 구조물 밖이며 나와 가까운 곳
func _attack_spot(pos: Vector3, tp: Vector3, r: float) -> Vector3:
	var best := tp + (pos - tp).normalized() * r
	var bv := INF
	for k in 16:
		var ang := k * TAU / 16.0
		var c := tp + Vector3(sin(ang), 0, cos(ang)) * r
		if _edge_dist(c) < 0.9 or _push_out(c).distance_to(c) > 0.01:
			continue
		var d := tp - c
		d.y = 0.0
		var clear := _cover_block(c + d.normalized() * 0.5, d.normalized()) > d.length() - 0.6
		var v := c.distance_to(pos) + (0.0 if clear else 50.0)
		if v < bv:
			bv = v
			best = c
	return best


## 상대 반대편, 가까운 구조물 뒤 자리
func _hide_spot(pos: Vector3, enemy: int) -> Vector3:
	var ep: Vector3 = walkers[enemy]["pos"] if enemy >= 0 and walkers.has(enemy) else Vector3.ZERO
	var best := pos
	var bd := INF
	for cv in _covers:
		var c: Vector2 = cv[1]
		var cp := Vector3(c.x, 0, c.y)
		var away := cp - ep
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
		var ext := float(cv[2]) if cv[0] == "c" else maxf((cv[2] as Vector2).x, (cv[2] as Vector2).y) * 0.6
		var spot := cp + away * (ext + 0.9)
		var d := spot.distance_to(pos)
		if d < bd and _edge_dist(spot) > 1.0:
			bd = d
			best = spot
	return best


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	return _alive().size() <= 1 and _wait <= 0.0


## 순위: 끝까지 남은 사람(체력 많은 순) → 늦게 쓰러진 순
func _ranking() -> Array:
	var order := players.duplicate()
	var key := func(p: Dictionary) -> float:
		var s := int(p["slot"])
		if _out_at.has(s):
			return float(_out_at[s])
		return 1000.0 + float(_hp.get(s, 0.0))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 물통 · 겨눈 방향 · 쏘는 중 (방장 → 손님)
func _net_state() -> Dictionary:
	var g := {}
	for s in _tank:
		g[s] = [float(_tank[s]), float(_aim[s]), bool(_spray[s]), float(_hp.get(s, HP_MAX))]
	return {"g": g}


func _net_apply(st: Dictionary) -> void:
	var g: Dictionary = st.get("g", {})
	for s in g:
		var v: Array = g[s]
		var si := int(s)
		_tank[si] = float(v[0])
		if v.size() >= 4:
			_hp[si] = float(v[3])
			scores[si] = float(v[3])
		if si != net_me:
			_aim[si] = float(v[1])
			_spray[si] = bool(v[2])


func _score_text(p: Dictionary) -> String:
	var s := int(p["slot"])
	if walkers.has(s) and walkers[s]["out"]:
		return "✕"
	return tr("HP %d") % int(ceil(float(_hp.get(s, HP_MAX))))
