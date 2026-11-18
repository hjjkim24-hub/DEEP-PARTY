extends "res://scripts/minigames/minigame_3d.gd"
## 화약통 넘기기 (마우스로 걷기): 뗏목 위, 심지가 타들어 가는 화약통을 든 사람이 술래.
## 다른 사람에게 닿으면 화약통이 넘어가요 (넘겨받은 사람은 잠깐 못 넘김). 펑! 터지면 든 사람이 탈락.
## 마지막까지 남은 사람이 승리. 터질 때마다 다음 심지는 더 짧아져요.

const RAFT_R := 6.6
const PASS_R := 0.9

var _holder := -1
var _fuse := 0.0
var _fuse_max := 0.0
var _no_pass := 0.0
var _out_at := {}
var _order := 0
var _keg: Node3D
var _spark: CPUParticles3D
var _keg_light: OmniLight3D
var _ai := {}
var _wait := 0.0
var _raft: Node3D


func _init() -> void:
	title = "POWDER KEG"
	how_to = "Someone is holding a lit powder keg! Bump into another player to pass it on. It blows up at a random moment - whoever holds it is out. Last one standing wins!"
	goal = "Don't be holding it when it blows!"
	controls = "KEYS"
	duration = 999.0
	show_timer = false


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	var sea := ocean(-0.55, 180.0, RAFT_R + 1.5)
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.6)
	cam.fov = 46.0
	cam.position = Vector3(0, 12.8, 11.6)
	cam.look_at(Vector3(0, 0, 0.6))
	_raft = Node3D.new()
	world3.add_child(_raft)
	var rr := RandomNumberGenerator.new()
	rr.seed = 31
	var cols := [Color(0.36, 0.27, 0.19), Color(0.4, 0.3, 0.21), Color(0.33, 0.25, 0.18)]
	var z := -RAFT_R + 0.25
	var idx := 0
	while z < RAFT_R - 0.2:
		var half := sqrt(maxf(RAFT_R * RAFT_R - z * z, 0.5)) + rr.randf_range(-0.25, 0.15)
		box(Vector3(half * 2.0, 0.16, 0.4), wood_mat(cols[idx % 3], Vector3(1, 0, 0), 0.12),
			Vector3(rr.randf_range(-0.1, 0.1), -0.08, z), Basis(Vector3.UP, rr.randf_range(-0.012, 0.012)), _raft)
		z += 0.43
		idx += 1
	var log_mat := wood_mat(Color(0.32, 0.22, 0.14), Vector3(1, 0, 0), 0.4)
	for k in 5:
		var zz := -RAFT_R * 0.8 + k * RAFT_R * 0.4
		var half := sqrt(maxf(RAFT_R * RAFT_R - zz * zz, 1.0)) - 0.2
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.42
		cyl.height = half * 2.0
		add_mesh(cyl, log_mat, Vector3(0, -0.55, zz), Basis(Vector3(0, 0, 1), PI / 2), _raft)
	# 가장자리 화약통 더미 · 횃불 기둥
	var barrel := wood_mat(Color(0.45, 0.3, 0.18), Vector3(0, 1, 0), 0.2)
	var metal := std_mat(Color(0.18, 0.17, 0.16), 0.45, 0.8)
	for a: float in [0.6, 2.2, 3.7, 5.1]:
		var p := Vector3(cos(a), 0, sin(a)) * (RAFT_R - 0.6)
		_barrel(p, barrel, metal, 0.32, 0.75)
	for k in 4:
		var a := TAU * (k + 0.125) / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * (RAFT_R - 0.3)
		var c := CylinderMesh.new()
		c.top_radius = 0.08
		c.bottom_radius = 0.1
		c.height = 1.8
		add_mesh(c, wood_mat(Color(0.36, 0.25, 0.16), Vector3(0, 1, 0), 0.3), p + Vector3(0, 0.9, 0), Basis(), _raft)
		var fl := StandardMaterial3D.new()
		fl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fl.albedo_color = Color(1.0, 0.7, 0.3)
		var s := SphereMesh.new()
		s.radius = 0.14
		s.height = 0.34
		add_mesh(s, fl, p + Vector3(0, 1.9, 0), Basis(), _raft)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.light_energy = 2.0
		l.omni_range = 6.0
		l.position = p + Vector3(0, 2.0, 0)
		_raft.add_child(l)


func _barrel(p: Vector3, wood: Material, metal: Material, r: float, h: float, parent: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.position = p
	(parent if parent else _raft).add_child(root)
	var c := CylinderMesh.new()
	c.top_radius = r * 0.88
	c.bottom_radius = r * 0.88
	c.height = h
	c.radial_segments = 20
	add_mesh(c, wood, Vector3(0, h * 0.5, 0), Basis(), root)
	var bulge := SphereMesh.new()
	bulge.radius = r
	bulge.height = h * 0.95
	bulge.radial_segments = 20
	add_mesh(bulge, wood, Vector3(0, h * 0.5, 0), Basis(), root)
	for hy: float in [0.12, 0.5, 0.88]:
		var band := CylinderMesh.new()
		var rr := r * (0.92 if hy != 0.5 else 1.01)
		band.top_radius = rr
		band.bottom_radius = rr
		band.height = 0.05
		add_mesh(band, metal, Vector3(0, h * hy, 0), Basis(), root)
	return root


func _setup_game() -> void:
	walk_radius = RAFT_R - 0.8
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var a := TAU * float(i) / n + PI * 0.25
		var w := add_walker(p, Vector3(cos(a), 0, sin(a)) * 3.2, 5.0)
		(w["node"] as Node3D).reparent(_raft, false)
		_ai[int(p["slot"])] = {"t": 0.0, "goal": w["pos"]}
		scores[int(p["slot"])] = 1
	# 머리 위에 드는 화약통 + 심지 불꽃
	_keg = _barrel(Vector3.ZERO, wood_mat(Color(0.3, 0.18, 0.1), Vector3(0, 1, 0), 0.1), std_mat(Color(0.15, 0.14, 0.13), 0.4, 0.8), 0.32, 0.6, world3)
	var skull := std_mat(Color(0.92, 0.9, 0.82), 0.6)
	box(Vector3(0.22, 0.18, 0.02), skull, Vector3(0, 0.33, 0.31), Basis(), _keg)
	_spark = CPUParticles3D.new()
	_spark.amount = 30
	_spark.lifetime = 0.5
	_spark.direction = Vector3.UP
	_spark.spread = 60.0
	_spark.initial_velocity_min = 1.0
	_spark.initial_velocity_max = 2.5
	_spark.gravity = Vector3(0, -4, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.75, 0.3)
	sm.material = smat
	_spark.mesh = sm
	_spark.position = Vector3(0, 0.8, 0)
	_keg.add_child(_spark)
	_keg_light = OmniLight3D.new()
	_keg_light.light_color = Color(1.0, 0.6, 0.25)
	_keg_light.light_energy = 2.5
	_keg_light.omni_range = 4.0
	_keg_light.position = Vector3(0, 0.9, 0)
	_keg.add_child(_keg_light)
	_keg.scale = Vector3.ONE * 1.15


func _start_game() -> void:
	_new_round()


func _alive() -> Array:
	return walkers.keys().filter(func(s: int) -> bool: return not walkers[s]["out"])


func _new_round() -> void:
	var alive := _alive()
	if alive.size() <= 1:
		return
	_holder = alive[rng.randi() % alive.size()]
	# 15 ~ 25초 사이 아무 때나 터짐 (아무도 모름)
	_fuse_max = rng.randf_range(15.0, 25.0)
	_fuse = _fuse_max
	_no_pass = 0.8
	_keg.visible = true
	sfx("toast")


func _tick(delta: float) -> void:
	_t3 += delta
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_new_round()
		step_walkers(delta)
		return
	if _holder < 0:
		return
	_fuse -= delta
	_no_pass = maxf(0.0, _no_pass - delta)
	_think(delta)
	# 든 사람은 조금 느림, 쫓는 게 아니라 쫓기는 쪽은 빠름
	for s in walkers:
		walkers[s]["speed"] = 4.6 if s == _holder else 5.0
	step_walkers(delta)
	var hw: Dictionary = walkers[_holder]
	var hp: Vector3 = (hw["node"] as Node3D).global_position
	_keg.global_position = hp + Vector3(0, 1.75 + sin(_t3 * 14.0) * 0.03, 0)
	_keg.rotation.y += delta * 2.0
	# 언제 터질지 알 수 없게: 늘 같은 빠르기로 지글지글 · 깜빡
	_keg_light.light_energy = 3.0 + sin(_t3 * 11.0) * 1.2
	_keg.scale = Vector3.ONE * (1.15 + sin(_t3 * 9.0) * 0.03)
	if fmod(_t3, 0.5) < delta:
		sfx("tick", 40)
	# 넘기기: 닿으면
	if _no_pass <= 0.0:
		for s in _alive():
			if s == _holder:
				continue
			var d: Vector3 = (walkers[s]["pos"] as Vector3) - (hw["pos"] as Vector3)
			d.y = 0.0
			if d.length() < PASS_R:
				_pass(s)
				break
	if _fuse <= 0.0:
		_boom()


func _pass(to: int) -> void:
	var from := _holder
	_holder = to
	_no_pass = 0.6
	sfx("thud", 50)
	var d: Vector3 = (walkers[to]["pos"] as Vector3) - (walkers[from]["pos"] as Vector3)
	if d.length() > 0.01:
		walkers[to]["push"] = d.normalized() * 3.0
	float_at((walkers[to]["pos"] as Vector3) + Vector3(0, 2.8, 0), "!", Color(1.0, 0.5, 0.3), 54)


func _boom() -> void:
	var s := _holder
	_holder = -1
	var w: Dictionary = walkers[s]
	var at: Vector3 = _keg.global_position
	_keg.visible = false
	sfx("explode")
	shake(0.9)
	debris(at, Color(0.35, 0.22, 0.12), 26)
	# 불덩이
	var fb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	fb.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.65, 0.25, 0.95)
	fb.material_override = m
	fb.position = at
	world3.add_child(fb)
	var t := create_tween().set_parallel(true)
	t.tween_property(fb, "scale", Vector3.ONE * 4.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color", Color(0.3, 0.2, 0.15, 0.0), 0.5)
	t.chain().tween_callback(fb.queue_free)
	# 터진 사람은 바다로 날아감
	w["out"] = true
	_out_at[s] = _order
	_order += 1
	scores[s] = 0
	var n: Node3D = w["node"]
	var from := n.position
	var flat := Vector2(from.x, from.z)
	var dir := flat.normalized() if flat.length() > 0.3 else Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	var to := Vector3(dir.x, 0, dir.y) * (RAFT_R + 4.0) + Vector3(0, -0.9, 0)
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void:
		n.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 6.0, 0)
		n.rotation.x = f * TAU * 2.0, 0.0, 1.0, 1.0)
	tw.tween_callback(func() -> void:
		splash(n.global_position + Vector3(0, 0.4, 0), 50, 1.1)
		sfx("splash")
		n.rotation = Vector3(0.9, rng.randf() * TAU, 0.3))
	_wait = 1.8


## CPU: 든 사람은 가장 가까운 사람을 쫓고, 나머지는 든 사람에게서 멀어짐 (벽에 몰리지 않게)
func _think(delta: float) -> void:
	for s in _alive():
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		a["t"] = float(a["t"]) - delta
		var sk := skill(p)
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.4, 0.12, sk / 2.0) + rng.randf_range(0.0, 0.12)
			var pos: Vector3 = w["pos"]
			if s == _holder:
				var best := pos
				var bd := INF
				for o in _alive():
					if o == s:
						continue
					var op: Vector3 = walkers[o]["pos"]
					var d := op.distance_to(pos)
					if d < bd:
						bd = d
						best = op + (walkers[o]["vel"] as Vector3) * lerpf(0.0, 0.35, sk / 2.0)
				a["goal"] = best
			else:
				var hp: Vector3 = walkers[_holder]["pos"]
				var away := pos - hp
				away.y = 0.0
				var best := pos
				var bv := -INF
				for k in 16:
					var ang := TAU * k / 16.0
					var c := pos + Vector3(cos(ang), 0, sin(ang)) * 2.0
					var cr := Vector2(c.x, c.z).length()
					if cr > RAFT_R - 1.0:
						continue
					var v := c.distance_to(hp) - cr * 0.35 + rng.randf_range(0.0, lerpf(2.0, 0.4, sk / 2.0))
					if v > bv:
						bv = v
						best = c
				a["goal"] = best
		w["target"] = a["goal"]


func _is_done() -> bool:
	return _alive().size() <= 1 and _wait <= 0.0


func _ranking() -> Array:
	var order := players.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(_out_at.get(int(a["slot"]), 99)) > int(_out_at.get(int(b["slot"]), 99)))
	return order


func _score_text(p: Dictionary) -> String:
	var s := int(p["slot"])
	if walkers.has(s) and walkers[s]["out"]:
		return "✕"
	return tr("KEG!") if s == _holder else tr("Safe")
