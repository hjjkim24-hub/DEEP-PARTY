extends "res://scripts/minigames/minigame_3d.gd"
## 촉수 피하기 (마우스): 폭풍 치는 바다 한가운데 둥근 뗏목. 크라켄 촉수가 붉은 원을 노리고 내려쳐요.
## 말은 마우스 쪽으로 걸어가요. 하트 3개 — 다 잃으면 바다로 튕겨 나가 탈락. 30초 버티기.
## 순위: 살아남은 사람(하트 많은 순) → 늦게 탈락한 순

const RAFT_R := 7.0
const HIT_R := 1.45
const STRIPE_W := 1.5    ## 촉수가 눕는 띠의 폭
const HEARTS := 3

var _hearts := {}       ## slot → 하트
var _out_at := {}       ## slot → 탈락한 시각
var _inv := {}          ## slot → 무적 남은 시간
var _ai := {}           ## slot → {t, wander}
var _rings: Array = []  ## {pos, r, t_hit, mark}
var _elapsed := 0.0
var _next_attack := 1.2
var _raft: Node3D


func _init() -> void:
	title = "TENTACLE DODGE"
	how_to = "The kraken slams the red circles! Move your pawn with the mouse and get out of the way. 3 hearts each - last one on the raft wins!"
	goal = "Last one on the raft wins!"
	controls = "MOUSE_MOVE"
	duration = 30.0


func _build_stage() -> void:
	env_sea_day()
	ocean(-0.55, 180.0, RAFT_R + 1.5)
	cam.position = Vector3(0, 13.2, 12.0)
	cam.look_at(Vector3(0, 0, 0.6))
	_raft = Node3D.new()
	world3.add_child(_raft)
	_build_raft()


func _build_raft() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 11
	# 통나무 받침 (물에 반쯤 잠김)
	var log_mat := wood_mat(Color(0.32, 0.22, 0.14), Vector3(1, 0, 0), 0.4)
	for k in 5:
		var z := -RAFT_R * 0.8 + k * RAFT_R * 0.4
		var half := sqrt(maxf(RAFT_R * RAFT_R - z * z, 1.0)) - 0.2
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.42
		cyl.height = half * 2.0
		cyl.radial_segments = 20
		add_mesh(cyl, log_mat, Vector3(0, -0.55, z), Basis(Vector3(0, 0, 1), PI / 2), _raft)
	# 널빤지 (가장자리는 원을 따라 들쭉날쭉)
	var cols := [Color(0.36, 0.27, 0.19), Color(0.4, 0.3, 0.21), Color(0.33, 0.25, 0.18), Color(0.38, 0.28, 0.2)]
	var z := -RAFT_R + 0.25
	var idx := 0
	while z < RAFT_R - 0.2:
		var half := sqrt(maxf(RAFT_R * RAFT_R - z * z, 0.5)) + rr.randf_range(-0.25, 0.15)
		var m := wood_mat(cols[idx % cols.size()], Vector3(1, 0, 0), 0.12)
		box(Vector3(half * 2.0, 0.16, 0.4), m, Vector3(rr.randf_range(-0.1, 0.1), -0.08 + rr.randf_range(-0.015, 0.015), z),
			Basis(Vector3.UP, rr.randf_range(-0.012, 0.012)), _raft)
		z += 0.43
		idx += 1
	# 널을 묶은 밧줄 · 테두리 기둥 · 등불
	var rope := std_mat(Color(0.66, 0.55, 0.38), 0.9)
	var post := wood_mat(Color(0.36, 0.25, 0.16), Vector3(0, 1, 0), 0.3)
	var metal := std_mat(Color(0.18, 0.17, 0.16), 0.45, 0.8)
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * (RAFT_R - 0.35)
		var c := CylinderMesh.new()
		c.top_radius = 0.11
		c.bottom_radius = 0.13
		c.height = 1.5
		add_mesh(c, post, p + Vector3(0, 0.6, 0), Basis(), _raft)
		var tor := TorusMesh.new()
		tor.inner_radius = 0.1
		tor.outer_radius = 0.17
		add_mesh(tor, rope, p + Vector3(0, 0.15, 0), Basis(), _raft)
		# 등불
		var lb := box(Vector3(0.26, 0.34, 0.26), metal, p + Vector3(0, 1.48, 0), Basis(), _raft)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(1.0, 0.75, 0.4)
		glass.emission_enabled = true
		glass.emission = Color(1.0, 0.62, 0.25)
		glass.emission_energy_multiplier = 3.0
		box(Vector3(0.2, 0.24, 0.2), glass, Vector3(0, 0, 0), Basis(), lb).scale = Vector3(1.05, 1.0, 1.05)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.35)
		l.light_energy = 1.4
		l.omni_range = 6.0
		l.position = p + Vector3(0, 1.5, 0)
		_raft.add_child(l)
	# 밧줄 난간 (기둥 사이)
	for k in 6:
		var a0 := TAU * (k + 0.5) / 6.0
		var a1 := TAU * (k + 1.5) / 6.0
		var p0 := Vector3(cos(a0), 0, sin(a0)) * (RAFT_R - 0.35) + Vector3(0, 0.95, 0)
		var p1 := Vector3(cos(a1), 0, sin(a1)) * (RAFT_R - 0.35) + Vector3(0, 0.95, 0)
		for s in 6:
			var f0 := float(s) / 6.0
			var f1 := float(s + 1) / 6.0
			var q0 := p0.lerp(p1, f0) - Vector3(0, sin(f0 * PI) * 0.22, 0)
			var q1 := p0.lerp(p1, f1) - Vector3(0, sin(f1 * PI) * 0.22, 0)
			var d := q1 - q0
			var cy := CylinderMesh.new()
			cy.top_radius = 0.03
			cy.bottom_radius = 0.03
			cy.height = d.length()
			cy.radial_segments = 6
			var y := d.normalized()
			var x := y.cross(Vector3.UP).normalized()
			add_mesh(cy, rope, (q0 + q1) * 0.5, Basis(x, y, x.cross(y)), _raft)
	# 나무통 · 밧줄 더미 (가장자리 장식)
	var barrel := wood_mat(Color(0.45, 0.3, 0.18), Vector3(0, 1, 0), 0.2)
	for a: float in [0.9, 2.4, 4.1, 5.3]:
		var p := Vector3(cos(a), 0, sin(a)) * (RAFT_R - 0.9)
		var c := CylinderMesh.new()
		c.top_radius = 0.34
		c.bottom_radius = 0.34
		c.height = 0.8
		add_mesh(c, barrel, p + Vector3(0, 0.4, 0), Basis(), _raft)
		for hy: float in [0.15, 0.65]:
			var band := CylinderMesh.new()
			band.top_radius = 0.355
			band.bottom_radius = 0.355
			band.height = 0.06
			add_mesh(band, metal, p + Vector3(0, hy, 0), Basis(), _raft)


func _setup_game() -> void:
	walk_radius = RAFT_R - 1.0
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var a := TAU * float(i) / n + PI * 0.25
		add_walker(p, Vector3(cos(a), 0, sin(a)) * 2.6, 5.2)
		var s := int(p["slot"])
		_hearts[s] = HEARTS
		_inv[s] = 0.0
		_ai[s] = {"t": 0.0, "goal": Vector3(cos(a), 0, sin(a)) * 2.6}
		scores[s] = HEARTS


func _start_game() -> void:
	_elapsed = 0.0
	_next_attack = 1.0


func _tick(delta: float) -> void:
	_elapsed += delta
	_think(delta)
	step_walkers(delta)
	for s in _inv:
		_inv[s] = maxf(0.0, float(_inv[s]) - delta)
		var w: Dictionary = walkers[s]
		if not w["out"]:
			(w["node"] as Node3D).visible = float(_inv[s]) <= 0.0 or fmod(float(_inv[s]), 0.16) > 0.07
	_next_attack -= delta
	if _next_attack <= 0.0:
		_attack()
	for ring in _rings.duplicate():
		if _elapsed >= float(ring["t_hit"]) and not ring.get("done", false):
			ring["done"] = true
			_hit_ring(ring)


func _alive() -> Array:
	return walkers.values().filter(func(w: Dictionary) -> bool: return not w["out"])


## 공격: 바다에서 촉수가 솟아 뗏목 위로 길게 쾅 눕음 (붉은 띠 = 눕는 자리). 시간이 지날수록 자주 · 여러 개 · 경고는 짧게
func _attack() -> void:
	var f := clampf(_elapsed / duration, 0.0, 1.0)
	var count := 1 if f < 0.3 else (2 if f < 0.75 else 3)
	var warn := lerpf(1.4, 0.95, f)
	_next_attack = lerpf(1.7, 1.05, f) + rng.randf_range(-0.15, 0.15)
	var alive := _alive()
	if alive.is_empty():
		return
	var used: Array = []
	for k in count:
		var target: Vector3
		if rng.randf() < 0.8:
			var w: Dictionary = alive[(rng.randi() + k) % alive.size()]
			target = (w["pos"] as Vector3) + (w["vel"] as Vector3) * 0.3 + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		else:
			var a := rng.randf() * TAU
			target = Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, RAFT_R - 1.4)
		# 들어오는 방향: 카메라 쪽(앞)은 빼고, 앞서 고른 방향과 겹치지 않게
		var ang := 0.0
		for tries in 12:
			# 뿌리가 카메라 쪽(+z)에 오지 않게: cos(ang) <= 0.3 인 각도만
			ang = rng.randf_range(1.27, 5.01)
			var ok := true
			for u in used:
				if absf(angle_difference(ang, float(u))) < 0.7:
					ok = false
			if ok:
				break
		used.append(ang)
		_add_stripe(target, Vector3(sin(ang), 0, cos(ang)), warn + k * 0.12)


## 촉수 하나: 뿌리 = 과녁에서 out 쪽 바다. 눕는 띠는 뿌리에서 0.23L ~ 0.68L (셰이더 자세로 계산한 값)
func _add_stripe(target: Vector3, out: Vector3, warn: float) -> void:
	var edge_d := RAFT_R + 1.3
	# 과녁에서 out 방향으로 뗏목 밖(물)까지의 거리
	var tp := Vector2(target.x, target.z)
	var od := Vector2(out.x, out.z)
	var b := tp.dot(od)
	var c := tp.length_squared() - edge_d * edge_d
	var to_edge := -b + sqrt(maxf(b * b - c, 0.0))
	var length := clampf(to_edge / 0.42, 8.0, 19.0)
	var root := target + out * (length * 0.42)
	var dir := -out
	var a0 := root + dir * length * 0.2
	var a1 := root + dir * length * 0.7
	var mid := (a0 + a1) * 0.5
	var full := Vector3(STRIPE_W * 0.5 + 0.1, 1.0, a0.distance_to(a1) * 0.5 + 0.2)
	var mark := danger_ring(Vector3(mid.x, 0, mid.z), 1.0, full, atan2(dir.x, dir.z))
	var ring := {"a": Vector3(a0.x, 0, a0.z), "b": Vector3(a1.x, 0, a1.z), "t_hit": _elapsed + warn, "mark": mark}
	_rings.append(ring)
	sfx("tick", 60)
	_swing(ring, Vector3(root.x, 0, root.z), dir, length, warn)


func _swing(ring: Dictionary, root: Vector3, dir: Vector3, length: float, warn: float) -> void:
	# 눕는 부분이 갑판 위 0.55 m 에 오게 뿌리 높이를 맞춤 (중심선 높이 ≈ 0.25L)
	root.y = 0.55 - 0.25 * length
	var tn := tentacle(length, 0.78, dir)
	var node: Node3D = tn["root"]
	var m: ShaderMaterial = tn["mat"]
	m.set_shader_parameter("tip", 0.22)
	m.set_shader_parameter("hook_at", 0.2)
	m.set_shader_parameter("pattern_scale", 1.6 / 0.78)
	var straight := [0.0, 0.0, 0.0, 0.0, 0.15]
	var raised := [-0.25, 0.9, 0.0, -0.5, 0.25]
	var wound := [-0.6, 1.5, 0.0, -0.9, 0.1]
	var slammed := [0.5, 0.0, 1.2, 1.0, 0.0]
	pose_tentacle(m, straight, straight, 0.0)
	node.position = root + Vector3(0, -length, 0)
	var rise_t := minf(0.55, warn * 0.45)
	var wind_t := maxf(0.1, minf(0.4, warn - rise_t - 0.22))
	var t := create_tween()
	t.tween_property(node, "position:y", root.y, rise_t).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(func(f: float) -> void:
		pose_tentacle(m, straight, raised, smoothstep(0.35, 1.0, f))
		m.set_shader_parameter("glow", f * 0.6), 0.0, 1.0, rise_t)
	t.tween_method(func(f: float) -> void: pose_tentacle(m, raised, wound, f), 0.0, 1.0, wind_t).set_trans(Tween.TRANS_SINE)
	t.tween_interval(maxf(0.0, warn - rise_t - wind_t - 0.22))
	t.tween_method(func(f: float) -> void: pose_tentacle(m, wound, slammed, f * f), 0.0, 1.0, 0.22)
	t.tween_interval(0.6)
	t.tween_method(func(f: float) -> void:
		pose_tentacle(m, slammed, raised, f)
		m.set_shader_parameter("glow", 0.6 * (1.0 - f)), 0.0, 1.0, 0.35)
	t.tween_property(node, "position:y", root.y - length, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(node.queue_free)
	splash(Vector3(root.x, -0.4, root.z), 30, 1.2)
	sfx("kraken_rise", 120)


func _hit_ring(ring: Dictionary) -> void:
	var a: Vector3 = ring["a"]
	var b: Vector3 = ring["b"]
	sfx("kraken_slam", 90)
	for k in 3:
		var p := a.lerp(b, (k + 0.5) / 3.0)
		debris(p + Vector3(0, 0.1, 0), Color(0.42, 0.33, 0.25), 8)
		splash(p + Vector3(0, 0.1, 0), 12, 0.6)
	var mark: MeshInstance3D = ring["mark"]
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(mark, "scale", Vector3(0.01, 1, 0.01), 0.25)
	tw.parallel().tween_property(mark, "transparency", 1.0, 0.25)
	tw.tween_callback(mark.queue_free)
	tw.tween_callback(func() -> void: _rings.erase(ring))
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"] or float(_inv[s]) > 0.0:
			continue
		var pos: Vector3 = w["pos"]
		var cl := Geometry3D.get_closest_point_to_segment(Vector3(pos.x, 0, pos.z), a, b)
		var d := Vector3(pos.x, 0, pos.z) - cl
		if d.length() <= STRIPE_W * 0.5 + 0.2:
			_hurt(int(s), d)


func _hurt(s: int, away: Vector3) -> void:
	var w: Dictionary = walkers[s]
	_hearts[s] = int(_hearts[s]) - 1
	scores[s] = float(_hearts[s])
	_inv[s] = 1.3
	var dir := away.normalized() if away.length() > 0.05 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	w["push"] = dir * 7.0
	w["slow"] = 0.5
	sfx("thud")
	float_at((w["pos"] as Vector3) + Vector3(0, 2.0, 0), "-1", Color(1.0, 0.45, 0.4), 44)
	if int(_hearts[s]) <= 0:
		_knock_out(s, dir)


## 탈락: 바다로 휙 날아가 첨벙
func _knock_out(s: int, dir: Vector3) -> void:
	var w: Dictionary = walkers[s]
	w["out"] = true
	_out_at[s] = _elapsed
	scores[s] = 0.0
	var n: Node3D = w["node"]
	n.visible = true
	var from: Vector3 = n.position
	var flat := Vector2(from.x, from.z)
	var land := flat.normalized() * (RAFT_R + 3.5) if flat.length() > 0.5 else Vector2(dir.x, dir.z).normalized() * (RAFT_R + 3.5)
	var to := Vector3(land.x, -0.9, land.y)
	var t := create_tween()
	t.tween_method(func(f: float) -> void:
		n.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 4.0, 0)
		n.rotation.x = f * TAU * 1.5, 0.0, 1.0, 0.8)
	t.tween_callback(func() -> void:
		splash(Vector3(to.x, -0.4, to.z), 50, 1.1)
		sfx("splash")
		n.visible = false)


## CPU: 붉은 원 안이면 가장 가까운 안전한 곳으로, 아니면 가끔 어슬렁 (실력에 따라 늦게 · 가끔 실수)
func _think(delta: float) -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"]:
			continue
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) > 0.0:
			w["target"] = a["goal"]
			continue
		var sk := skill(p)
		a["t"] = lerpf(0.5, 0.18, sk / 2.0) + rng.randf_range(0.0, 0.15)
		var pos: Vector3 = w["pos"]
		var danger := _in_danger(pos, 0.45)
		if danger and rng.randf() > lerpf(0.3, 0.05, sk / 2.0):
			a["goal"] = _safe_spot(pos)
		elif not danger and rng.randf() < 0.18:
			var g := pos + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
			if Vector2(g.x, g.z).length() < RAFT_R - 1.6 and not _in_danger(g, 0.6):
				a["goal"] = g
		w["target"] = a["goal"]


func _in_danger(pos: Vector3, margin: float) -> bool:
	for ring in _rings:
		if ring.get("done", false):
			continue
		var q := Vector3(pos.x, 0, pos.z)
		var cl := Geometry3D.get_closest_point_to_segment(q, ring["a"], ring["b"])
		if q.distance_to(cl) < STRIPE_W * 0.5 + margin:
			return true
	return false


func _safe_spot(pos: Vector3) -> Vector3:
	var best := pos
	var bd := INF
	for k in 24:
		var a := TAU * k / 24.0 + rng.randf() * 0.2
		for r: float in [1.6, 2.6, 3.6]:
			var c := pos + Vector3(cos(a), 0, sin(a)) * r
			if Vector2(c.x, c.z).length() > RAFT_R - 1.3:
				continue
			if _in_danger(c, 0.7):
				continue
			var d := c.distance_to(pos) + Vector2(c.x, c.z).length() * 0.15
			if d < bd:
				bd = d
				best = c
	return best


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	return players.size() > 1 and _alive().size() <= 1


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a["slot"])
		var sb := int(b["slot"])
		var ka := float(_hearts[sa]) * 1000.0 + (float(_out_at.get(sa, 999.0)))
		var kb := float(_hearts[sb]) * 1000.0 + (float(_out_at.get(sb, 999.0)))
		return ka > kb)
	return order


func _score_text(p: Dictionary) -> String:
	var h := int(_hearts.get(int(p["slot"]), 0))
	return "♥".repeat(h) if h > 0 else "✕"
