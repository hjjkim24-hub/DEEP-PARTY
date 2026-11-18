extends "res://scripts/minigames/minigame_3d.gd"
## 대포 사격 (마우스): 배 난간에 대포 4문. 바다에서 크라켄 촉수가 불쑥불쑥 솟아요.
## 촉수를 클릭하면 내 대포가 그쪽으로 쏴요. 포탄이 닿을 때 아직 솟아 있으면 명중! 금빛 촉수는 3점.
## 같은 촉수를 여럿이 노리면 먼저 닿은 사람 점수. 30초.

const SEA_Y := -3.2              ## 바다 높이 (갑판은 0)
const RELOAD := 0.55
const BALL_SPEED := 30.0

var _cannons := {}      ## slot → {node, barrel, pos, reload, yaw, pitch}
var _targets: Array = []  ## {id, pos, gold, up_until, alive, tn, node, hit_by}
var _balls: Array = []
var _spawn := 0.0
var _elapsed := 0.0
var _next_id := 0
var _ai := {}
var _cursor: MeshInstance3D


func _init() -> void:
	title = "CANNON VOLLEY"
	how_to = "Tentacles burst out of the sea! Click one to fire your cannon at it. Golden tentacles are worth 3 points. Hit the most in 30 seconds!"
	goal = "Most hits wins!"
	controls = "MOUSE"
	duration = 30.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-40, 160, 0)
	# 먼 바다가 하늘빛 안개로 스르르 이어지게
	env.fog_light_color = Color(0.66, 0.77, 0.86)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	ocean(SEA_Y, 260.0)
	# 먼 바다 (파도 없는 큰 판, 수평선까지)
	var far := ocean(SEA_Y - 1.3, 5000.0)
	(far.mesh as PlaneMesh).subdivide_width = 2
	(far.mesh as PlaneMesh).subdivide_depth = 2
	(far.material_override as ShaderMaterial).set_shader_parameter("amp", 0.0)
	cam.fov = 50.0
	cam.position = Vector3(0, 6.2, 9.0)
	cam.look_at(Vector3(0, -1.0, -14.0))
	_build_deck()



func _build_deck() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	var cols := [Color(0.36, 0.27, 0.19), Color(0.4, 0.3, 0.21), Color(0.33, 0.25, 0.18)]
	# 갑판 널 (앞뒤로 길게)
	for k in 26:
		var x := -13.0 + k * 1.04
		box(Vector3(1.0, 0.2, 9.0), wood_mat(cols[k % 3], Vector3(0, 0, 1), 0.05), Vector3(x, -0.1, 4.5 + rr.randf_range(-0.05, 0.05)))
	# 뱃전 (난간 벽) + 손잡이 + 기둥
	var hull := wood_mat(Color(0.28, 0.18, 0.12), Vector3(1, 0, 0), 0.2)
	var rail := wood_mat(Color(0.45, 0.31, 0.2), Vector3(1, 0, 0), 0.05)
	box(Vector3(28.0, 1.0, 0.35), hull, Vector3(0, 0.5, -0.1))
	box(Vector3(28.4, 0.16, 0.55), rail, Vector3(0, 1.08, -0.1))
	box(Vector3(28.0, 4.0, 0.4), hull, Vector3(0, -2.2, -0.35))
	for k in 15:
		box(Vector3(0.24, 1.15, 0.24), rail, Vector3(-14.0 + k * 2.0, 0.55, 0.15))
	# 대포 구멍 사이 밧줄 감개 · 나무통
	var barrel := wood_mat(Color(0.42, 0.29, 0.18), Vector3(0, 1, 0), 0.1)
	for x: float in [-9.5, 9.5]:
		var c := CylinderMesh.new()
		c.top_radius = 0.42
		c.bottom_radius = 0.42
		c.height = 1.0
		add_mesh(c, barrel, Vector3(x, 0.5, 2.2))
	# 돛대 밑동 (뒤쪽 화면 밖으로)
	var mast := CylinderMesh.new()
	mast.top_radius = 0.35
	mast.bottom_radius = 0.4
	mast.height = 14.0
	add_mesh(mast, wood_mat(Color(0.4, 0.28, 0.18), Vector3(0, 1, 0), 0.1), Vector3(-11.0, 7.0, 6.0))


func _make_cannon(p: Dictionary, x: float) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(x, 0, 1.0)
	root.scale = Vector3.ONE * 0.85
	world3.add_child(root)
	var dark := std_mat(Color(0.08, 0.08, 0.09), 0.35, 0.85)
	var wood := wood_mat(Color(0.38, 0.24, 0.15), Vector3(0, 0, 1), 0.05)
	# 받침 (바퀴 달린 나무 수레)
	box(Vector3(1.1, 0.45, 1.6), wood, Vector3(0, 0.38, 0.1), Basis(), root)
	for sx: float in [-0.6, 0.6]:
		for sz: float in [-0.45, 0.6]:
			var wh := CylinderMesh.new()
			wh.top_radius = 0.24
			wh.bottom_radius = 0.24
			wh.height = 0.14
			add_mesh(wh, wood, Vector3(sx, 0.24, sz), Basis(Vector3(0, 0, 1), PI / 2), root)
	# 포신 (yaw → pitch 순서로 돌아가는 받침대)
	var yaw := Node3D.new()
	yaw.position = Vector3(0, 0.85, 0.1)
	root.add_child(yaw)
	var pitch := Node3D.new()
	yaw.add_child(pitch)
	var tube := CylinderMesh.new()
	tube.top_radius = 0.2
	tube.bottom_radius = 0.29
	tube.height = 2.0
	tube.radial_segments = 24
	add_mesh(tube, dark, Vector3(0, 0, -0.75), Basis(Vector3(1, 0, 0), PI / 2), pitch)
	for zz: float in [-1.7, -0.9, 0.05]:
		var ring := CylinderMesh.new()
		ring.top_radius = 0.31 if zz > -0.5 else 0.25
		ring.bottom_radius = ring.top_radius
		ring.height = 0.1
		add_mesh(ring, dark, Vector3(0, 0, zz), Basis(Vector3(1, 0, 0), PI / 2), pitch)
	var knob := SphereMesh.new()
	knob.radius = 0.2
	knob.height = 0.4
	add_mesh(knob, dark, Vector3(0, 0, 0.35), Basis(), pitch)
	# 내 색 깃발 (막대 + 천)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.035
	pole.height = 1.6
	add_mesh(pole, wood, Vector3(0.62, 1.2, 0.85), Basis(), root)
	var flag := std_mat(p["color"], 0.8)
	flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	box(Vector3(0.02, 0.36, 0.55), flag, Vector3(0.63, 1.8, 0.58), Basis(), root)
	return {"node": root, "yaw": yaw, "pitch": pitch, "pos": root.position + Vector3(0, 0.72, 0.1), "reload": 0.0}


func _setup_game() -> void:
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var x := (float(i) - (n - 1) * 0.5) * 3.2
		_cannons[int(p["slot"])] = _make_cannon(p, x)
		# 대포 뒤에 선 내 말
		var pawn := make_pawn(p)
		pawn.position = Vector3(x + 0.4, 0, 2.15)
		pawn.scale = Vector3.ONE * 1.05
		pawn.rotation.y = PI
		_ai[int(p["slot"])] = {"t": rng.randf_range(0.3, 1.1), "aim": -1}
		scores[int(p["slot"])] = 0
	# 내 조준점 (바다 위 동그라미)
	var q := TorusMesh.new()
	q.inner_radius = 0.55
	q.outer_radius = 0.7
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor = add_mesh(q, m, Vector3(0, SEA_Y + 0.2, -10))
	_cursor.visible = false


func _start_game() -> void:
	_elapsed = 0.0
	_spawn = 0.3


func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	_spawn -= delta
	if _spawn <= 0.0:
		_spawn_target()
		var f := _elapsed / duration
		_spawn = lerpf(0.8, 0.42, f) * rng.randf_range(0.8, 1.2)
	for s in _cannons:
		_cannons[s]["reload"] = maxf(0.0, float(_cannons[s]["reload"]) - delta)
	_update_targets(delta)
	_update_balls(delta)
	_think(delta)
	_human(delta)


# ── 촉수 ─────────────────────────────────────────────────────
func _spawn_target() -> void:
	var alive := _targets.filter(func(t: Dictionary) -> bool: return t["alive"])
	if alive.size() >= 7:
		return
	var pos := Vector3.ZERO
	for tries in 10:
		pos = Vector3(rng.randf_range(-14.0, 14.0), SEA_Y, rng.randf_range(-26.0, -7.0))
		var ok := true
		for t in alive:
			if (t["pos"] as Vector3).distance_to(pos) < 4.0:
				ok = false
		if ok:
			break
	var gold := rng.randf() < 0.14
	var length := rng.randf_range(6.0, 8.5)
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var tn := tentacle(length, 0.85, dir)
	var node: Node3D = tn["root"]
	var m: ShaderMaterial = tn["mat"]
	m.set_shader_parameter("tip", 0.18)
	m.set_shader_parameter("pattern_scale", 1.9)
	if gold:
		m.set_shader_parameter("neon", Color(1.0, 0.82, 0.25))
		m.set_shader_parameter("deep", Color(0.35, 0.2, 0.02))
		m.set_shader_parameter("vein_col", Color(1.0, 0.95, 0.6))
	node.position = pos + Vector3(0, -length, 0)
	var t := {"id": _next_id, "pos": pos, "gold": gold, "alive": true, "tn": tn, "node": node, "len": length,
		"up_until": _elapsed + lerpf(2.8, 1.9, _elapsed / duration), "phase": rng.randf() * TAU, "rise": 0.0}
	_next_id += 1
	_targets.append(t)
	splash(pos + Vector3(0, 0.3, 0), 30, 1.1)
	sfx("splash", 120)


func _update_targets(delta: float) -> void:
	for t in _targets.duplicate():
		var node: Node3D = t["node"]
		if not is_instance_valid(node):
			_targets.erase(t)
			continue
		var m: ShaderMaterial = (t["tn"] as Dictionary)["mat"]
		var length: float = t["len"]
		if t["alive"]:
			t["rise"] = minf(1.0, float(t["rise"]) + delta * 3.0)
			if _elapsed > float(t["up_until"]):
				t["alive"] = false
		else:
			t["rise"] = float(t["rise"]) - delta * 2.2
			if float(t["rise"]) <= 0.0:
				node.queue_free()
				_targets.erase(t)
				continue
		var r: float = t["rise"]
		var e := 1.0 - pow(1.0 - clampf(r, 0.0, 1.0), 3.0)
		node.position.y = SEA_Y - length * (1.0 - e) - 0.4
		var ph: float = t["phase"]
		m.set_shader_parameter("pitch", sin(_t3 * 1.7 + ph) * 0.25)
		m.set_shader_parameter("curl", 0.55 + sin(_t3 * 2.3 + ph) * 0.35)
		m.set_shader_parameter("wave", 0.35)
		m.set_shader_parameter("wtime", _t3)


## 촉수 몸통의 가운데쯤 (조준 · 맞는 자리)
func _aim_point(t: Dictionary) -> Vector3:
	return (t["pos"] as Vector3) + Vector3(0, float(t["len"]) * 0.45, 0)


# ── 사람: 클릭하면 마우스 가까운 촉수로 ──────────────────────
func _human(_delta: float) -> void:
	for p in players:
		if not is_human(p):
			continue
		var g := mouse_ground(SEA_Y)
		_cursor.visible = g != Vector3.INF and playing
		if g != Vector3.INF:
			_cursor.position = g + Vector3(0, 0.15, 0)
			_cursor.rotation.x = 0.0


func _gui_input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for p in players:
		if is_human(p):
			var best := _pick_under_mouse()
			if not best.is_empty():
				_fire(int(p["slot"]), best)
			else:
				var g := mouse_ground(SEA_Y)
				if g != Vector3.INF:
					_fire_at(int(p["slot"]), g, -1)


func _pick_under_mouse() -> Dictionary:
	var m := mouse_vp()
	var best: Dictionary = {}
	var bd := 90.0 * (float(vp.size.y) / 1080.0)
	for t in _targets:
		if not t["alive"]:
			continue
		for f: float in [0.15, 0.45, 0.75]:
			var sp := cam.unproject_position((t["pos"] as Vector3) + Vector3(0, float(t["len"]) * f, 0))
			var d := sp.distance_to(m)
			if d < bd:
				bd = d
				best = t
	return best


# ── 대포 · 포탄 ──────────────────────────────────────────────
func _fire(s: int, t: Dictionary) -> void:
	_fire_at(s, _aim_point(t), int(t["id"]))


func _fire_at(s: int, at: Vector3, target_id: int) -> void:
	var c: Dictionary = _cannons[s]
	if float(c["reload"]) > 0.0:
		return
	c["reload"] = RELOAD
	var from: Vector3 = c["pos"]
	var d := at - from
	(c["yaw"] as Node3D).rotation.y = atan2(-d.x, -d.z)
	var flat := Vector2(d.x, d.z).length()
	(c["pitch"] as Node3D).rotation.x = clampf(atan2(d.y, flat) + 0.12, -0.35, 0.5)
	var muzzle: Vector3 = from + (Basis(Vector3.UP, atan2(-d.x, -d.z)) * Vector3(0, 0.15, -1.8))
	var fly := clampf(muzzle.distance_to(at) / BALL_SPEED, 0.35, 1.1)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	ball.mesh = sm
	ball.material_override = std_mat(Color(0.06, 0.06, 0.07), 0.4, 0.7)
	world3.add_child(ball)
	ball.position = muzzle
	_balls.append({"node": ball, "from": muzzle, "to": at, "t": 0.0, "fly": fly, "slot": s, "target": target_id})
	# 반동 · 연기 · 소리
	var pn: Node3D = c["pitch"]
	var tw := create_tween()
	tw.tween_property(pn, "position:z", 0.35, 0.05)
	tw.tween_property(pn, "position:z", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	_smoke(muzzle)
	sfx("cannon", 50)


func _update_balls(delta: float) -> void:
	var list := _balls.duplicate()
	list.shuffle()   # 같은 순간에 닿으면 누가 먼저인지 무작위
	for b in list:
		b["t"] = float(b["t"]) + delta
		var f := clampf(float(b["t"]) / float(b["fly"]), 0.0, 1.0)
		var node: Node3D = b["node"]
		var arc := sin(f * PI) * (b["from"] as Vector3).distance_to(b["to"]) * 0.08
		node.position = (b["from"] as Vector3).lerp(b["to"], f) + Vector3(0, arc, 0)
		if f >= 1.0:
			_balls.erase(b)
			node.queue_free()
			_land(b)


func _land(b: Dictionary) -> void:
	var at: Vector3 = b["to"]
	var s: int = b["slot"]
	for t in _targets:
		if int(t["id"]) == int(b["target"]) and t["alive"]:
			t["alive"] = false
			var pts := 3 if t["gold"] else 1
			scores[s] = int(scores[s]) + pts
			sfx("explode", 60)
			_burst(at, t["gold"])
			var p := player_by_slot(s)
			float_at(at + Vector3(0, 1.2, 0), "+%d" % pts, GOLD if t["gold"] else Color(p["color"]).lightened(0.3), 48)
			return
	# 빗나감: 물기둥
	splash(Vector3(at.x, SEA_Y + 0.2, at.z), 26, 1.0)
	sfx("splash", 60)


func _burst(at: Vector3, gold: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 34
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9, 0)
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.3) if gold else Color(0.55, 1.0, 0.35)
	s.material = m
	p.mesh = s
	p.position = at
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	splash(Vector3(at.x, SEA_Y + 0.2, at.z), 40, 1.3)


func _smoke(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.direction = Vector3(0, 0.4, -1)
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := ShaderMaterial.new()
	m.shader = SmokeShader
	m.set_shader_parameter("opacity", 0.55)
	m.set_shader_parameter("tint", Color(0.75, 0.75, 0.78))
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = at
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# ── CPU ──────────────────────────────────────────────────────
func _think(delta: float) -> void:
	for p in players:
		if is_human(p):
			continue
		var s := int(p["slot"])
		var a: Dictionary = _ai[s]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) > 0.0:
			continue
		var sk := skill(p)
		a["t"] = lerpf(0.75, 0.38, sk / 2.0) + rng.randf_range(0.0, 0.3)
		var cands := _targets.filter(func(t: Dictionary) -> bool: return t["alive"] and _elapsed < float(t["up_until"]) - 0.4)
		if cands.is_empty():
			continue
		# 금빛 먼저, 아니면 가까운 것 (가끔 빗맞힘)
		var c: Dictionary = (_cannons[s] as Dictionary)
		cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			var dx := (x["pos"] as Vector3).distance_to(c["pos"]) - (12.0 if x["gold"] else 0.0)
			var dy := (y["pos"] as Vector3).distance_to(c["pos"]) - (12.0 if y["gold"] else 0.0)
			return dx < dy)
		var pick: Dictionary = cands[mini(rng.randi() % 3, cands.size() - 1)]
		if rng.randf() < lerpf(0.35, 0.1, sk / 2.0):
			_fire_at(s, _aim_point(pick) + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.0, 2.0)), -1)
		else:
			_fire(s, pick)


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))
