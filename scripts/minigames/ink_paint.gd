extends "res://scripts/minigames/minigame_3d.gd"
## 먹물 땅따먹기 (마우스로 걷기): 크라켄의 배 갑판 위. 걸어가는 자리마다 내 색 먹물이 칠해져요.
## 30초 뒤 가장 넓게 칠한 사람이 승리. 남의 색 위도 덮어 칠할 수 있어요.
## 후반엔 크라켄이 검은 먹물 덩이를 뱉어 칠해 둔 땅을 지워 버려요 (갈수록 크게 · 자주).
## 중간중간 갑판 아무 데나 오리발(잠수용 핀)이 떨어짐 → 주우면 몇 초 동안 빨라짐.

const GRID := 120
const HALF := 7.2               ## 갑판 반 너비 (정사각형)
const BRUSH := 0.8

var _owner := PackedInt32Array()   ## 칸마다 주인 slot (-1 = 빈칸)
var _img: Image
var _tex: ImageTexture
var _paint_mat: ShaderMaterial
var _cols := {}
var _count := {}
var _blob_t := 6.0
var _blobs: Array = []
var _ai := {}
var _dirty := false
const BOOST_TIME := 4.0
var _fins := {}          ## id → {"node", "pos"}
var _fin_t := 3.0
var _fin_id := 0


func _init() -> void:
	title = "INK SPLAT"
	how_to = "Walk to paint the deck in your color! You can paint over other colors too. Grab swim fins for a burst of speed. Watch out - the kraken spits black ink that wipes the deck clean. Biggest area wins!"
	goal = "Paint the most deck!"
	controls = "KEYS"
	duration = 30.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	var sea := ocean(-1.4, 200.0)
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.5)
	sky_clouds(12, 200.0, 30.0)
	cam.fov = 44.0
	cam.position = Vector3(0, 15.5, 12.5)
	cam.look_at(Vector3(0, 0, 0.8))
	_build_ship()
	# 칠하는 면 (갑판 바로 위 투명 판)
	_img = Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	var q := PlaneMesh.new()
	q.size = Vector2(HALF * 2.0, HALF * 2.0)
	_paint_mat = ShaderMaterial.new()
	_paint_mat.shader = load("res://shaders/ink_paint.gdshader")
	_paint_mat.set_shader_parameter("paint", _tex)
	_paint_mat.set_shader_parameter("grid", float(GRID))
	add_mesh(q, _paint_mat, Vector3(0, 0.02, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 뒤쪽 바다의 크라켄 (먹물을 뱉음)
	kraken_head(Vector3(0, -5.0, -24.0), 4.2, 0.0, -0.1)


## 갑판 = 큰 배의 주갑판: 선체(뱃머리는 크라켄 쪽) · 널빤지(선체 모양대로) · 뱃전 · 대포 · 돛대 · 잡동사니
func _build_ship() -> void:
	const L := 25.0
	const B := 19.0
	const D := 4.2
	var stern_z := HALF + 1.6
	var hull := MeshInstance3D.new()
	hull.mesh = hull_mesh(L, B, D, 24, 14)
	hull.material_override = wood_mat(Color(0.3, 0.19, 0.11), Vector3(1, 0, 0), 0.3)
	# 메시 +X(뱃머리) → 월드 -Z
	hull.basis = Basis(Vector3.UP, PI / 2)
	hull.position = Vector3(0, -0.05, stern_z - L * 0.5)
	world3.add_child(hull)
	# 흘수선 위 검은 띠 (wale)
	var wale := MeshInstance3D.new()
	wale.mesh = hull.mesh
	wale.material_override = std_mat(Color(0.07, 0.06, 0.06), 0.6)
	wale.basis = hull.basis.scaled(Vector3(1.004, 0.12, 1.004))
	wale.position = hull.position + Vector3(0, -0.28, 0)
	world3.add_child(wale)
	# t(0=고물, 1=뱃머리) ↔ z
	var z_of := func(t: float) -> float: return stern_z - t * L
	# 갑판 널: 세로(배 길이 방향)로, 선체 폭 안쪽만
	var cols := [Color(0.56, 0.42, 0.28), Color(0.6, 0.46, 0.31), Color(0.52, 0.39, 0.26), Color(0.58, 0.44, 0.3)]
	var rr := RandomNumberGenerator.new()
	rr.seed = 21
	var pw := 0.62
	var nx := int(B / pw)
	var nail := std_mat(Color(0.12, 0.1, 0.09), 0.5, 0.7)
	var nail_m := CylinderMesh.new()
	nail_m.top_radius = 0.03
	nail_m.bottom_radius = 0.03
	nail_m.height = 0.02
	nail_m.radial_segments = 6
	for k in nx:
		var x := -B * 0.5 + (k + 0.5) * pw
		var t0 := -1.0
		var t1 := -1.0
		for i in 101:
			var t := i / 100.0
			if hull_half_width(t, B) * 0.94 > absf(x) + pw * 0.5:
				if t0 < 0.0:
					t0 = t
				t1 = t
		if t0 < 0.0:
			continue
		# 널 한 줄을 이음매 몇 개로 나눔 (엇갈린 이음)
		var za: float = z_of.call(t0)
		var zb: float = z_of.call(t1)
		var seg := 3.6 + rr.randf_range(-0.4, 0.4)
		var z := za - rr.randf_range(0.0, seg)
		var pieces := []
		pieces.append(za)
		while z > zb:
			pieces.append(z)
			z -= seg
		pieces.append(zb)
		for j in pieces.size() - 1:
			var z0: float = pieces[j]
			var z1: float = pieces[j + 1]
			var ln := z0 - z1
			if ln < 0.2:
				continue
			box(Vector3(pw - 0.04, 0.22, ln - 0.03), wood_mat(cols[(k + j) % cols.size()], Vector3(0, 0, 1), 0.04),
				Vector3(x, -0.11 + rr.randf_range(-0.01, 0.01), (z0 + z1) * 0.5))
			# 이음매의 못 두 개
			add_mesh(nail_m, nail, Vector3(x - pw * 0.22, 0.005, z0 - 0.12))
			add_mesh(nail_m, nail, Vector3(x + pw * 0.22, 0.005, z0 - 0.12))
	# 널 아래 메움 (틈으로 보이는 어두운 바닥)
	box(Vector3(B * 0.9, 0.2, L * 0.9), std_mat(Color(0.12, 0.08, 0.05), 0.9), Vector3(0, -0.3, stern_z - L * 0.47))
	# 뱃전 (bulwark): 선체 둘레를 따라 판벽 + 기둥 + 위 난간
	var wall := wood_mat(Color(0.38, 0.25, 0.15), Vector3(1, 0, 0), 0.15)
	var cap := wood_mat(Color(0.26, 0.16, 0.09), Vector3(1, 0, 0), 0.1)
	var n := 30
	for sd: float in [-1.0, 1.0]:
		for i in n:
			var ta := float(i) / n * 0.985
			var tb := float(i + 1) / n * 0.985
			var pa := Vector3(sd * hull_half_width(ta, B) * 0.97, 0, z_of.call(ta))
			var pb := Vector3(sd * hull_half_width(tb, B) * 0.97, 0, z_of.call(tb))
			var sg := pb - pa
			var bb := Basis.looking_at(sg.normalized(), Vector3.UP)
			box(Vector3(0.16, 0.85, sg.length() + 0.04), wall, (pa + pb) * 0.5 + Vector3(0, 0.42, 0), bb)
			box(Vector3(0.32, 0.1, sg.length() + 0.06), cap, (pa + pb) * 0.5 + Vector3(0, 0.88, 0), bb)
			if i % 2 == 0:
				var inward := Vector3(-sd * 0.12, 0, 0)
				box(Vector3(0.16, 0.9, 0.16), cap, pa + inward + Vector3(0, 0.45, 0), bb)
	# 고물 쪽 가로 난간 (카메라 앞)
	var hw0 := hull_half_width(0.0, B) * 0.97
	box(Vector3(hw0 * 2.0, 0.85, 0.16), wall, Vector3(0, 0.42, stern_z), Basis())
	box(Vector3(hw0 * 2.0 + 0.2, 0.1, 0.32), cap, Vector3(0, 0.88, stern_z), Basis())
	# 대포: 양쪽 뱃전에 3문씩 (무대 밖 여백)
	var iron := std_mat(Color(0.1, 0.1, 0.11), 0.4, 0.75)
	var carriage := wood_mat(Color(0.42, 0.28, 0.17), Vector3(1, 0, 0), 0.1)
	for sd: float in [-1.0, 1.0]:
		for z: float in [-HALF * 0.65, 0.0, HALF * 0.65]:
			var t := (stern_z - z) / L
			var xw := hull_half_width(t, B) * 0.97 - 0.75
			var c := Node3D.new()
			c.position = Vector3(sd * xw, 0, z)
			c.rotation.y = -sd * PI / 2
			world3.add_child(c)
			box(Vector3(0.7, 0.3, 1.0), carriage, Vector3(0, 0.2, 0.0), Basis(), c)
			for wx: float in [-0.3, 0.3]:
				for wz: float in [-0.35, 0.35]:
					var wh := CylinderMesh.new()
					wh.top_radius = 0.16
					wh.bottom_radius = 0.16
					wh.height = 0.1
					add_mesh(wh, carriage, Vector3(wx + signf(wx) * 0.05, 0.16, wz), Basis(Vector3(0, 0, 1), PI / 2), c)
			var bar := CylinderMesh.new()
			bar.top_radius = 0.13
			bar.bottom_radius = 0.2
			bar.height = 1.6
			add_mesh(bar, iron, Vector3(0, 0.45, -0.55), Basis(Vector3(1, 0, 0), -PI / 2 + 0.05), c)
			var muz := TorusMesh.new()
			muz.inner_radius = 0.09
			muz.outer_radius = 0.17
			add_mesh(muz, iron, Vector3(0, 0.49, -1.33), Basis(Vector3(1, 0, 0), PI / 2), c)
	# 돛대 (뱃머리 쪽, 무대 밖) + 돛줄
	var mast_z := -HALF - 3.2
	var mast := CylinderMesh.new()
	mast.top_radius = 0.32
	mast.bottom_radius = 0.42
	mast.height = 22.0
	add_mesh(mast, cap, Vector3(0, 11.0, mast_z))
	for k in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.4
		ring.outer_radius = 0.48
		add_mesh(ring, iron, Vector3(0, 0.6 + k * 1.2, mast_z))
	var yard := CylinderMesh.new()
	yard.top_radius = 0.16
	yard.bottom_radius = 0.16
	yard.height = 14.0
	add_mesh(yard, cap, Vector3(0, 12.0, mast_z + 0.5), Basis(Vector3(0, 0, 1), PI / 2))
	var rope := std_mat(Color(0.5, 0.42, 0.3), 0.9)
	for sd: float in [-1.0, 1.0]:
		for k in 4:
			var t := (stern_z - (mast_z + 1.8 + k * 0.7)) / L
			var a := Vector3(sd * hull_half_width(t, B) * 0.96, 0.9, mast_z + 1.8 + k * 0.7)
			var b := Vector3(sd * 0.3, 14.0, mast_z)
			var sg := b - a
			var c := CylinderMesh.new()
			c.top_radius = 0.03
			c.bottom_radius = 0.03
			c.height = sg.length()
			c.radial_segments = 5
			var y := sg.normalized()
			var xx := y.cross(Vector3(0, 0, 1)).normalized()
			add_mesh(c, rope, (a + b) * 0.5, Basis(xx, y, xx.cross(y)))
	# 잡동사니: 무대(정사각형) 밖 여백 — 고물 쪽 양 모서리 · 돛대 주변
	deck_clutter(world3, [Vector3(-HALF - 0.2, 0.0, HALF + 0.9), Vector3(HALF + 0.3, 0.0, HALF + 0.9), Vector3(-1.6, 0.0, mast_z + 1.2),
		Vector3(1.5, 0.0, mast_z + 1.3), Vector3(-3.4, 0.0, mast_z + 0.6), Vector3(3.3, 0.0, mast_z + 0.4)], 14)
	# 칠할 구역 경계: 갑판에 박은 낮은 말뚝 + 밧줄
	var post := wood_mat(Color(0.3, 0.2, 0.12), Vector3(0, 1, 0), 0.1)
	var rope2 := std_mat(Color(0.75, 0.62, 0.42), 0.9)
	var e := HALF + 0.12
	for k in 9:
		var f := -e + k * e * 2.0 / 8.0
		for p: Vector3 in [Vector3(f, 0, -e), Vector3(f, 0, e), Vector3(-e, 0, f), Vector3(e, 0, f)]:
			var c := CylinderMesh.new()
			c.top_radius = 0.07
			c.bottom_radius = 0.08
			c.height = 0.34
			c.radial_segments = 8
			add_mesh(c, post, p + Vector3(0, 0.17, 0))
	for sd: float in [-1.0, 1.0]:
		box(Vector3(e * 2.0, 0.05, 0.05), rope2, Vector3(0, 0.28, sd * e))
		box(Vector3(0.05, 0.05, e * 2.0), rope2, Vector3(sd * e, 0.28, 0))
	sea_debris(8, 15.0, 28.0, -1.3, 6)
	gulls(5, Vector3(0, 0, -6), 12.0, 14.0, 7)


func _setup_game() -> void:
	walk_radius = HALF * 1.3
	_owner.resize(GRID * GRID)
	_owner.fill(-1)
	var n := players.size()
	var corners := [Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1)]
	for i in n:
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		add_walker(p, corners[i] * (HALF - 1.2), 5.4)
		var c0 := Color(p["color"])
		_cols[s] = Color.from_hsv(c0.h, clampf(c0.s * 1.6 + 0.2, 0.0, 0.95), clampf(c0.v * 0.85, 0.0, 0.9))
		_count[s] = 0
		_ai[s] = {"t": 0.0, "goal": corners[i] * (HALF - 1.2)}
		scores[s] = 0


func _start_game() -> void:
	_blob_t = lerpf(7.0, 3.0, heat)


func _tick(delta: float) -> void:
	_t3 += delta
	_think(delta)
	step_walkers(delta)
	# 네모 갑판 밖으로 못 나가게
	for w in walkers.values():
		var pp: Vector3 = w["pos"]
		pp.x = clampf(pp.x, -HALF + 0.3, HALF - 0.3)
		pp.z = clampf(pp.z, -HALF + 0.3, HALF - 0.3)
		w["pos"] = pp
		var nd: Node3D = w["node"]
		nd.position.x = pp.x
		nd.position.z = pp.z
		# 지난 자리에서 지금 자리까지 빈틈없이 칠함
		var last: Vector3 = w.get("last_paint", pp)
		var steps := maxi(1, int(last.distance_to(pp) / (BRUSH * 0.5)))
		for k in steps:
			_paint_at(last.lerp(pp, float(k + 1) / steps), BRUSH, int(w["p"]["slot"]))
		w["last_paint"] = pp
	# 오리발: 방장이 가끔 아무 데나 떨어뜨리고, 밟은 사람이 줍기
	_fin_t -= delta
	if _fin_t <= 0.0 and not is_client():
		_fin_t = rng.randf_range(3.5, 6.0)
		if _fins.size() < 2:
			_fin_id += 1
			var at := Vector3(rng.randf_range(-HALF + 1.0, HALF - 1.0), 0, rng.randf_range(-HALF + 1.0, HALF - 1.0))
			net_call("_fin_spawn", [_fin_id, at, rng.randf() * TAU])
	for id in _fins.keys():
		var f: Dictionary = _fins[id]
		var fn: Node3D = f["node"]
		fn.position.y = 0.12 + sin(_t3 * 3.0 + float(id)) * 0.06
		fn.rotation.y += delta * 1.2
		if is_client():
			continue
		for w in walkers.values():
			if w["out"]:
				continue
			if Vector2((w["pos"] as Vector3).x - (f["pos"] as Vector3).x, (w["pos"] as Vector3).z - (f["pos"] as Vector3).z).length() < 0.95:
				net_call("_fin_take", [id, int(w["p"]["slot"])])
				break
	for w in walkers.values():
		if float(w.get("boost", 0.0)) > 0.0 and fmod(_t3, 0.12) < delta:
			splash((w["pos"] as Vector3) + Vector3(0, 0.2, 0), 3, 0.25)
	var pr := pressure()
	_blob_t -= delta
	if _blob_t <= 0.0 and pr > 0.15 and not is_client():
		_spit()
		_blob_t = lerpf(4.0, 1.4, pr) * rng.randf_range(0.8, 1.2)
	for b in _blobs.duplicate():
		b["t"] = float(b["t"]) + delta
		var f := clampf(float(b["t"]) / float(b["fly"]), 0.0, 1.0)
		var node: Node3D = b["node"]
		node.position = (b["from"] as Vector3).lerp(b["to"], f) + Vector3(0, sin(f * PI) * 7.0, 0)
		if f >= 1.0:
			_blobs.erase(b)
			node.queue_free()
			if not is_client():
				_splat(b["to"], float(b["r"]))
	if _dirty:
		_tex.update(_img)
		_dirty = false
		if not is_client():
			for s in _count:
				scores[s] = int(_count[s])


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int((p.x + HALF) / (HALF * 2.0) * GRID), int((p.z + HALF) / (HALF * 2.0) * GRID))


func _paint_at(p: Vector3, r: float, s: int, wob: Array = []) -> void:
	var c := _cell(p)
	var rc := int(ceil(r * (1.4 if wob.size() > 0 else 1.0) / (HALF * 2.0) * GRID))
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= GRID or y >= GRID:
				continue
			var cp := Vector3((x + 0.5) / GRID * HALF * 2.0 - HALF, 0, (y + 0.5) / GRID * HALF * 2.0 - HALF)
			var dv := Vector2(cp.x - p.x, cp.z - p.z)
			var rr := r
			if wob.size() > 0:
				# 들쭉날쭉한 얼룩 테두리: 각도에 따른 사인 몇 개를 겹침
				var ang := dv.angle()
				var f := 1.0
				for h in wob:
					f += float(h.x) * sin(ang * float(h.y) + float(h.z))
				rr = r * f
			if dv.length() > rr:
				continue
			var i := y * GRID + x
			var old := _owner[i]
			if old == s:
				continue
			if old >= 0:
				_count[old] = int(_count[old]) - 1
			_owner[i] = s
			if s >= 0:
				_count[s] = int(_count[s]) + 1
				var col: Color = _cols[s]
				# 먹물 얼룩 느낌: 칸마다 진하기가 조금씩 다름
				var k := 0.82 + 0.18 * fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
				_img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, 0.93))
			else:
				_img.set_pixel(x, y, Color(0.05, 0.04, 0.07, 0.75))
			_dirty = true


## 크라켄이 먹물 덩이를 뱉음: 떨어질 자리에 그림자 원 → 철퍽 (그 자리 칠이 지워짐)
func _spit() -> void:
	var pr := pressure()
	var to := Vector3(rng.randf_range(-HALF + 1.0, HALF - 1.0), 0, rng.randf_range(-HALF + 1.0, HALF - 1.0))
	# 가장 넓게 칠한 사람 땅을 노리는 일이 많음
	var lead := -1
	var best := -1
	for s in _count:
		if int(_count[s]) > best:
			best = int(_count[s])
			lead = s
	if lead >= 0 and rng.randf() < 0.6:
		var cells := []
		for i in _owner.size():
			if _owner[i] == lead:
				cells.append(i)
		if not cells.is_empty():
			var i: int = cells[rng.randi() % cells.size()]
			to = Vector3((i % GRID + 0.5) / GRID * HALF * 2.0 - HALF, 0, (i / GRID + 0.5) / GRID * HALF * 2.0 - HALF)
	net_call("_spit_do", [to, lerpf(1.3, 2.6, pr), lerpf(1.3, 0.9, pr)])


## 먹물 덩이 하나 (방장이 정한 자리로 모두 같게)
func _spit_do(to: Vector3, r: float, fly: float) -> void:
	var ring := danger_ring(to, r)
	get_tree().create_timer(fly).timeout.connect(ring.queue_free)
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.1
	m.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.04, 0.03, 0.06)
	mm.roughness = 0.1
	mm.clearcoat_enabled = true
	m.material_override = mm
	world3.add_child(m)
	var from := Vector3(0, 1.5, -20.0)
	_blobs.append({"node": m, "from": from, "to": to, "t": 0.0, "fly": fly, "r": r})
	sfx("bubbles", 100)


func _splat(at: Vector3, r: float) -> void:
	# 철퍽: 들쭉날쭉한 큰 얼룩 + 사방으로 튄 작은 방울과 꼬리 (모양은 방장이 정함)
	var wob := []
	for k in 4:
		wob.append(Vector3(rng.randf_range(0.04, 0.13), float(rng.randi_range(3, 9)), rng.randf() * TAU))
	var drops := []
	for k in rng.randi_range(7, 12):
		var a := rng.randf() * TAU
		drops.append([at + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.9, 1.7), r * rng.randf_range(0.08, 0.22)])
	net_call("_splat_do", [at, r, wob, drops])


func _splat_do(at: Vector3, r: float, wob: Array, drops: Array) -> void:
	sfx("splash", 60)
	shake(0.25)
	_paint_at(at, r * 0.85, -1, wob)
	for dp in drops:
		var q: Vector3 = dp[0]
		var dr := float(dp[1])
		_paint_at(q, dr, -1)
		# 방울 쪽으로 가늘어지는 꼬리
		for t in 3:
			var f := (t + 1) / 4.0
			_paint_at(at.lerp(q, 0.55 + f * 0.4), dr * (1.0 - f * 0.6), -1)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 30
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -14, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.03, 0.06)
	sm.material = m
	p.mesh = sm
	p.position = at + Vector3(0, 0.2, 0)
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	# 먹물에 맞은 말은 잠깐 느려짐
	for w in walkers.values():
		if Vector2((w["pos"] as Vector3).x - at.x, (w["pos"] as Vector3).z - at.z).length() < r:
			w["slow"] = 1.2


## CPU: 주변에서 내 색이 아닌 칸이 가장 많은 쪽으로
func _think(delta: float) -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0 or (w["pos"] as Vector3).distance_to(a["goal"]) < 0.5:
			var sk := skill(p)
			a["t"] = lerpf(1.1, 0.5, sk / 2.0) + rng.randf_range(0.0, 0.3)
			var pos: Vector3 = w["pos"]
			var best: Vector3 = pos
			var bv := -INF
			for k in 12:
				var ang := TAU * k / 12.0 + rng.randf() * 0.4
				var dist := rng.randf_range(1.8, 4.0)
				var c := pos + Vector3(cos(ang), 0, sin(ang)) * dist
				if absf(c.x) > HALF - 0.5 or absf(c.z) > HALF - 0.5:
					continue
				var v := 0.0
				for t in 5:
					var q := pos.lerp(c, (t + 1) / 5.0)
					var cc := _cell(q)
					if cc.x >= 0 and cc.y >= 0 and cc.x < GRID and cc.y < GRID:
						v += 0.0 if _owner[cc.y * GRID + cc.x] == s else (1.3 if _owner[cc.y * GRID + cc.x] >= 0 else 1.0)
				v += rng.randf_range(0.0, lerpf(2.5, 0.5, sk / 2.0))
				if v > bv:
					bv = v
					best = c
			a["goal"] = best
			# 가까운 오리발이 있으면 주우러 감
			for f in _fins.values():
				if pos.distance_to(f["pos"]) < lerpf(2.0, 4.5, sk / 2.0):
					a["goal"] = f["pos"]
					break
		w["target"] = a["goal"]


## 오리발 한 켤레 (노란 날 · 검은 고무 발주머니 · 옆 테두리) + 바닥에 은은한 빛 고리
func _fin_spawn(id: int, at: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = at + Vector3(0, 0.12, 0)
	root.rotation.y = yaw
	add_child(root)
	var blade := StandardMaterial3D.new()
	blade.albedo_color = Color(1.0, 0.82, 0.1)
	blade.roughness = 0.35
	blade.clearcoat_enabled = true
	blade.clearcoat = 0.5
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.06, 0.06, 0.07)
	rubber.roughness = 0.7
	for sgn in [-1.0, 1.0]:
		var fin := Node3D.new()
		fin.position = Vector3(sgn * 0.2, 0, 0)
		fin.rotation = Vector3(0, sgn * 0.12, sgn * 0.08)
		root.add_child(fin)
		# 날: 발 쪽은 좁고 끝은 넓은 납작한 판 (SurfaceTool 사다리꼴)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w0 := 0.1
		var w1 := 0.17
		var z0 := 0.1
		var z1 := 0.72
		var th := 0.012
		var top := [Vector3(-w0, th, z0), Vector3(w0, th, z0), Vector3(w1, th + 0.03, z1), Vector3(-w1, th + 0.03, z1)]
		var bot := [Vector3(-w0, -th, z0), Vector3(w0, -th, z0), Vector3(w1, -th + 0.03, z1), Vector3(-w1, -th + 0.03, z1)]
		for tri in [[top[0], top[2], top[1]], [top[0], top[3], top[2]], [bot[0], bot[1], bot[2]], [bot[0], bot[2], bot[3]],
				[top[1], top[2], bot[2]], [top[1], bot[2], bot[1]], [top[3], top[0], bot[0]], [top[3], bot[0], bot[3]], [top[2], top[3], bot[3]], [top[2], bot[3], bot[2]]]:
			for v in tri:
				st.add_vertex(v)
		st.generate_normals()
		var bm := MeshInstance3D.new()
		bm.mesh = st.commit()
		bm.material_override = blade
		fin.add_child(bm)
		# 옆 테두리 (검은 고무 날개살)
		for x in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(0.025, 0.04, 0.62)
			rail.mesh = rb
			rail.material_override = rubber
			rail.position = Vector3(x * 0.135, 0.02, 0.41)
			rail.rotation.y = -x * 0.11
			fin.add_child(rail)
		# 발주머니
		var pocket := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		pocket.mesh = sm
		pocket.material_override = rubber
		pocket.scale = Vector3(0.22, 0.13, 0.3)
		pocket.position = Vector3(0, 0.05, 0.0)
		fin.add_child(pocket)
	# 바닥 빛 고리
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.66
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.5, 0.95, 1.0, 0.55)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position = Vector3(at.x, 0.06, at.z)
	ring.scale = Vector3(1, 0.3, 1)
	add_child(ring)
	root.set_meta("ring", ring)
	root.scale = Vector3.ONE * 0.05
	create_tween().tween_property(root, "scale", Vector3.ONE * 1.3, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	splash(at + Vector3(0, 0.1, 0), 10, 0.5)
	_fins[id] = {"node": root, "pos": at}


func _fin_take(id: int, s: int) -> void:
	if not _fins.has(id):
		return
	var f: Dictionary = _fins[id]
	_fins.erase(id)
	var node: Node3D = f["node"]
	var ring = node.get_meta("ring")
	if ring is Node:
		(ring as Node).queue_free()
	node.queue_free()
	if walkers.has(s):
		var w: Dictionary = walkers[s]
		w["boost"] = BOOST_TIME
		float_at((w["pos"] as Vector3) + Vector3(0, 2.2, 0), tr("SPEED UP!"), Color(0.55, 0.95, 1.0), 34)
	sfx("equip")
	splash((f["pos"] as Vector3) + Vector3(0, 0.2, 0), 18, 0.7)


## 온라인: 칠한 칸 전체를 가끔 (방장 → 손님, 조금씩 어긋난 걸 맞춤)
var _grid_acc := 0.0


func _net_state() -> Dictionary:
	_grid_acc += NET_DT
	if _grid_acc < 1.5:
		return {}
	_grid_acc = 0.0
	var b := PackedByteArray()
	b.resize(_owner.size())
	for i in _owner.size():
		b[i] = _owner[i] + 1
	return {"grid": b.compress(FileAccess.COMPRESSION_DEFLATE)}


func _net_apply(st: Dictionary) -> void:
	if not st.has("grid"):
		return
	var b: PackedByteArray = (st["grid"] as PackedByteArray).decompress(GRID * GRID, FileAccess.COMPRESSION_DEFLATE)
	if b.size() != GRID * GRID:
		return
	for i in b.size():
		var o := int(b[i]) - 1
		if o == _owner[i]:
			continue
		_owner[i] = o
		var x := i % GRID
		var y := i / GRID
		if o >= 0:
			var col: Color = _cols[o]
			var k := 0.82 + 0.18 * fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			_img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, 0.93))
		else:
			_img.set_pixel(x, y, Color(0.05, 0.04, 0.07, 0.75))   # 칠했던 칸이 비었으면 먹물에 지워진 것
	_dirty = true


func _score_text(p: Dictionary) -> String:
	return "%d%%" % int(round(float(_count.get(int(p["slot"]), 0)) * 100.0 / (GRID * GRID)))
