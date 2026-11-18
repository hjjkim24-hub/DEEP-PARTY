extends "res://scripts/minigames/minigame_3d.gd"
## 먹물 땅따먹기 (마우스로 걷기): 크라켄의 배 갑판 위. 걸어가는 자리마다 내 색 먹물이 칠해져요.
## 30초 뒤 가장 넓게 칠한 사람이 승리. 남의 색 위도 덮어 칠할 수 있어요.
## 후반엔 크라켄이 검은 먹물 덩이를 뱉어 칠해 둔 땅을 지워 버려요 (갈수록 크게 · 자주).

const GRID := 72
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


func _init() -> void:
	title = "INK SPLAT"
	how_to = "Walk to paint the deck in your color! You can paint over other colors too. Watch out - the kraken spits black ink that wipes the deck clean. Biggest area wins!"
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
	# 갑판 (네모난 뗏목 · 널빤지)
	var cols := [Color(0.5, 0.38, 0.26), Color(0.55, 0.42, 0.29), Color(0.47, 0.35, 0.24)]
	for k in 18:
		var x := -HALF - 0.4 + k * 0.9
		box(Vector3(0.86, 0.3, HALF * 2.0 + 0.8), wood_mat(cols[k % 3], Vector3(0, 0, 1), 0.06), Vector3(x, -0.15, 0))
	var rail := wood_mat(Color(0.36, 0.24, 0.15), Vector3(1, 0, 0), 0.2)
	for sd: float in [-1.0, 1.0]:
		box(Vector3(HALF * 2.0 + 1.4, 0.5, 0.35), rail, Vector3(0, 0.1, sd * (HALF + 0.55)))
		box(Vector3(0.35, 0.5, HALF * 2.0 + 1.4), rail, Vector3(sd * (HALF + 0.55), 0.1, 0))
	box(Vector3(HALF * 2.0 + 1.6, 1.2, HALF * 2.0 + 1.6), wood_mat(Color(0.3, 0.2, 0.13), Vector3(1, 0, 0), 0.4), Vector3(0, -0.9, 0))
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
	var pr := pressure()
	_blob_t -= delta
	if _blob_t <= 0.0 and pr > 0.15:
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
			_splat(b["to"], float(b["r"]))
	if _dirty:
		_tex.update(_img)
		_dirty = false
		for s in _count:
			scores[s] = int(_count[s])


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int((p.x + HALF) / (HALF * 2.0) * GRID), int((p.z + HALF) / (HALF * 2.0) * GRID))


func _paint_at(p: Vector3, r: float, s: int) -> void:
	var c := _cell(p)
	var rc := int(ceil(r / (HALF * 2.0) * GRID))
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= GRID or y >= GRID:
				continue
			var cp := Vector3((x + 0.5) / GRID * HALF * 2.0 - HALF, 0, (y + 0.5) / GRID * HALF * 2.0 - HALF)
			if Vector2(cp.x - p.x, cp.z - p.z).length() > r:
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
	var r := lerpf(1.3, 2.6, pr)
	var fly := lerpf(1.3, 0.9, pr)
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
	sfx("splash", 60)
	shake(0.25)
	_paint_at(at, r, -1)
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
		w["target"] = a["goal"]


func _score_text(p: Dictionary) -> String:
	return "%d%%" % int(round(float(_count.get(int(p["slot"]), 0)) * 100.0 / (GRID * GRID)))
