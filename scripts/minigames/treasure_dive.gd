extends "res://scripts/minigames/minigame_3d.gd"
## 보물 줍기 (마우스): 바닷속 모래밭 한가운데 크라켄의 보물상자가 들썩이며 보물을 뿜어요.
## 말은 마우스 쪽으로 걸어가요. 동전 1 · 진주 2 · 보석 5점. 크라켄 먹물 구름 속에선 느려져요. 30초.

const SandShader := preload("res://shaders/mg_sand.gdshader")
const SandAlbedo := preload("res://textures/seabed/sand_albedo.png")
const SandNormal := preload("res://textures/seabed/sand_normal.png")

const ARENA_R := 8.2
const PICK_R := 0.75
const KINDS := {
	"coin": {"pts": 1, "col": Color(1.0, 0.78, 0.25)},
	"pearl": {"pts": 2, "col": Color(0.95, 0.95, 1.0)},
	"gem": {"pts": 5, "col": Color(0.95, 0.15, 0.3)},
}

var _items: Array = []     ## {node, pos, kind, flying, from, to, t, fly}
var _inks: Array = []      ## {node, pos, vel, r, life}
var _burst_t := 1.2
var _ink_t := 6.0
var _elapsed := 0.0
var _ai := {}
var _lid: Node3D
var _chest: Node3D
var _meshes := {}
var _arm_mats: Array = []


func _init() -> void:
	title = "TREASURE DIVE"
	how_to = "The kraken's chest is spitting out treasure! Move your pawn with the mouse to grab it. Coin 1, pearl 2, gem 5. Ink clouds slow you down!"
	goal = "Most treasure wins!"
	controls = "MOUSE_MOVE"
	duration = 30.0


func _build_stage() -> void:
	env_underwater()
	env.fog_density = 0.014
	cam.fov = 46.0
	cam.position = Vector3(0, 13.5, 10.8)
	cam.look_at(Vector3(0, 0, 0.9))
	# 모래 바닥
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	var sm := ShaderMaterial.new()
	sm.shader = SandShader
	sm.set_shader_parameter("sand_albedo", kit._mip_tex(SandAlbedo))
	sm.set_shader_parameter("sand_normal", kit._mip_tex(SandNormal))
	add_mesh(pm, sm, Vector3.ZERO)
	# 둘레: 보드와 같은 바위 · 산호 · 말미잘 · 다시마
	var rr := RandomNumberGenerator.new()
	rr.seed = 3
	seed(7)
	for k in 22:
		var a := TAU * k / 22.0 + rr.randf_range(-0.05, 0.05)
		var r := ARENA_R + 1.3 + rr.randf_range(-0.1, 0.7)
		reef("rock", Vector3(cos(a) * r, -0.2, sin(a) * r), Color.WHITE, rr.randf_range(1.0, 1.7))
	var coral_cols := [Color(1.0, 0.4, 0.38), Color(1.0, 0.6, 0.28), Color(0.76, 0.42, 0.98), Color(1.0, 0.38, 0.64), Color(1.0, 0.84, 0.38), Color(0.35, 0.85, 0.8)]
	var kinds := ["coral", "brain", "fan", "anemone", "table", "sponge", "coral", "anemone"]
	for k in 20:
		var a := TAU * (k + 0.5) / 20.0
		var base := Vector3(cos(a), 0, sin(a)) * (ARENA_R + 0.45 + rr.randf_range(-0.1, 0.3))
		reef(kinds[k % kinds.size()], base, coral_cols[k % coral_cols.size()], rr.randf_range(0.7, 1.0))
	for k in 10:
		var a := TAU * (k + 0.25) / 10.0
		reef("kelp", Vector3(cos(a), 0, sin(a)) * (ARENA_R + 2.6), Color.WHITE, rr.randf_range(4.0, 6.5))
	_build_chest()
	# 빛줄기 (수면에서 비스듬히)
	for k in 5:
		var q := QuadMesh.new()
		q.size = Vector2(2.2, 26.0)
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		lm.albedo_color = Color(0.5, 0.85, 0.8, 0.07)
		lm.cull_mode = BaseMaterial3D.CULL_DISABLED
		lm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		var ray := add_mesh(q, lm, Vector3(rr.randf_range(-9, 9), 11.0, rr.randf_range(-10, 2)), Basis(Vector3(0, 0, 1), 0.3))
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_chest() -> void:
	_chest = Node3D.new()
	world3.add_child(_chest)
	var wood := wood_mat(Color(0.35, 0.21, 0.12), Vector3(1, 0, 0), 0.5)
	var gold := std_mat(Color(0.95, 0.7, 0.25), 0.3, 0.9)
	box(Vector3(1.8, 0.9, 1.15), wood, Vector3(0, 0.45, 0), Basis(), _chest)
	for x: float in [-0.72, 0.0, 0.72]:
		box(Vector3(0.1, 0.94, 1.2), gold, Vector3(x, 0.45, 0), Basis(), _chest)
	box(Vector3(0.22, 0.28, 0.06), gold, Vector3(0, 0.72, 0.6), Basis(), _chest)
	# 금화 더미 (안쪽)
	var coins := CylinderMesh.new()
	coins.top_radius = 0.75
	coins.bottom_radius = 0.82
	coins.height = 0.25
	add_mesh(coins, gold, Vector3(0, 0.85, 0), Basis(), _chest).scale = Vector3(1.0, 1.0, 0.65)
	# 뚜껑 (뒤쪽 경첩)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.9, -0.57)
	_chest.add_child(_lid)
	var lidm := CylinderMesh.new()
	lidm.top_radius = 0.58
	lidm.bottom_radius = 0.58
	lidm.height = 1.8
	lidm.radial_segments = 20
	add_mesh(lidm, wood, Vector3(0, 0.0, 0.57), Basis(Vector3(0, 0, 1), PI / 2), _lid).scale = Vector3(0.62, 1.0, 1.0)
	_lid.rotation.x = -0.35
	# 상자를 휘감은 크라켄 촉수 (보드와 같은 것)
	for sd: float in [-1.0, 1.0]:
		var tn := tentacle(4.5, 0.42, Vector3(-sd, 0, 0.3))
		var n: Node3D = tn["root"]
		n.position = Vector3(sd * 2.2, -0.6, -0.4)
		var m: ShaderMaterial = tn["mat"]
		m.set_shader_parameter("pitch", 0.6)
		m.set_shader_parameter("curl", 1.4)
		m.set_shader_parameter("wave", 0.2)
		m.set_shader_parameter("tip", 0.15)
		_arm_mats.append(m)


func _setup_game() -> void:
	walk_radius = ARENA_R
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var a := TAU * float(i) / n + PI * 0.25
		add_walker(p, Vector3(cos(a), 0, sin(a)) * 5.0, 5.4)
		_ai[int(p["slot"])] = {"t": 0.0}
		scores[int(p["slot"])] = 0
	_make_item_meshes()


func _make_item_meshes() -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.24
	c.bottom_radius = 0.24
	c.height = 0.06
	c.radial_segments = 20
	var cm := std_mat(KINDS["coin"]["col"], 0.25, 0.95)
	cm.emission_enabled = true
	cm.emission = Color(0.5, 0.35, 0.05)
	c.material = cm
	_meshes["coin"] = c
	var p := SphereMesh.new()
	p.radius = 0.2
	p.height = 0.4
	var pmat := std_mat(KINDS["pearl"]["col"], 0.1, 0.0)
	pmat.clearcoat_enabled = true
	pmat.rim_enabled = true
	pmat.rim = 0.6
	pmat.emission_enabled = true
	pmat.emission = Color(0.25, 0.27, 0.3)
	p.material = pmat
	_meshes["pearl"] = p
	var g := SphereMesh.new()
	g.radius = 0.3
	g.height = 0.6
	g.radial_segments = 6
	g.rings = 2
	var gm := std_mat(KINDS["gem"]["col"], 0.05, 0.2)
	gm.emission_enabled = true
	gm.emission = Color(0.6, 0.05, 0.12)
	gm.emission_energy_multiplier = 1.5
	g.material = gm
	_meshes["gem"] = g


func _start_game() -> void:
	_elapsed = 0.0
	_burst_t = 0.6


func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	_burst_t -= delta
	if _burst_t <= 0.0:
		_burst()
		_burst_t = rng.randf_range(2.6, 3.6)
	_ink_t -= delta
	if _ink_t <= 0.0 and _elapsed > 5.0:
		_spawn_ink()
		_ink_t = rng.randf_range(4.0, 6.0)
	for m: ShaderMaterial in _arm_mats:
		m.set_shader_parameter("wtime", _t3)
	_update_items(delta)
	_update_inks(delta)
	_think(delta)
	for w in walkers.values():
		w["slow"] = 0.15 if _in_ink(w["pos"], 0.0) else w["slow"]
	step_walkers(delta)
	_collect()


## 상자가 들썩 → 뚜껑이 열리며 보물이 사방으로
func _burst() -> void:
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.35, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(_lid, "rotation:x", -0.35, 0.4).set_trans(Tween.TRANS_SINE)
	var j := create_tween()
	j.tween_property(_chest, "position:y", 0.25, 0.1)
	j.tween_property(_chest, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	sfx("box_burst", 100)
	var n := rng.randi_range(6, 9)
	for k in n:
		var roll := rng.randf()
		var kind := "gem" if roll < 0.08 else ("pearl" if roll < 0.35 else "coin")
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.0, ARENA_R - 0.6)
		var to := Vector3(cos(a) * d, 0.12, sin(a) * d)
		_spawn_item(kind, Vector3(0, 1.2, 0), to, rng.randf_range(0.7, 1.1) + k * 0.03)
	var bub := CPUParticles3D.new()
	bub.one_shot = true
	bub.amount = 30
	bub.lifetime = 1.6
	bub.explosiveness = 0.85
	bub.direction = Vector3.UP
	bub.spread = 30.0
	bub.initial_velocity_min = 1.5
	bub.initial_velocity_max = 3.5
	bub.gravity = Vector3(0, 1.5, 0)
	var bs := SphereMesh.new()
	bs.radius = 0.06
	bs.height = 0.12
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.8, 0.95, 1.0, 0.5)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.roughness = 0.05
	bs.material = bm
	bub.mesh = bs
	bub.position = Vector3(0, 1.0, 0)
	world3.add_child(bub)
	bub.emitting = true
	bub.finished.connect(bub.queue_free)


func _spawn_item(kind: String, from: Vector3, to: Vector3, fly: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[kind]
	world3.add_child(mi)
	mi.position = from
	_items.append({"node": mi, "pos": to, "kind": kind, "flying": true, "from": from, "to": to, "t": 0.0, "fly": fly, "spin": rng.randf() * TAU})


func _update_items(delta: float) -> void:
	for it in _items:
		var n: MeshInstance3D = it["node"]
		it["spin"] = float(it["spin"]) + delta * 2.0
		if it["flying"]:
			it["t"] = float(it["t"]) + delta
			var f := clampf(float(it["t"]) / float(it["fly"]), 0.0, 1.0)
			n.position = (it["from"] as Vector3).lerp(it["to"], f) + Vector3(0, sin(f * PI) * 3.2, 0)
			n.rotation = Vector3(f * 9.0, f * 5.0, 0)
			if f >= 1.0:
				it["flying"] = false
		else:
			var to: Vector3 = it["to"]
			n.position = to + Vector3(0, 0.15 + sin(float(it["spin"]) * 1.3) * 0.06, 0)
			n.rotation = Vector3(0.0 if it["kind"] != "coin" else PI / 2 * 0.0, float(it["spin"]), 0.0)
			if it["kind"] == "coin":
				n.rotation = Vector3(PI / 2, float(it["spin"]), 0.0)


func _collect() -> void:
	for it in _items.duplicate():
		if it["flying"]:
			continue
		for s in walkers:
			var w: Dictionary = walkers[s]
			var d: Vector3 = (w["pos"] as Vector3) - (it["to"] as Vector3)
			d.y = 0.0
			if d.length() < PICK_R:
				var pts: int = KINDS[it["kind"]]["pts"]
				scores[s] = int(scores[s]) + pts
				_items.erase(it)
				var n: Node3D = it["node"]
				var tw := create_tween()
				tw.tween_property(n, "position:y", 1.6, 0.25)
				tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.01, 0.25)
				tw.tween_callback(n.queue_free)
				sfx("coins" if it["kind"] == "coin" else "add", 50)
				var col: Color = KINDS[it["kind"]]["col"]
				float_at((it["to"] as Vector3) + Vector3(0, 1.5, 0), "+%d" % pts, col.lightened(0.2), 36 if pts < 5 else 52)
				break


# ── 먹물 ─────────────────────────────────────────────────────
func _spawn_ink() -> void:
	var a := rng.randf() * TAU
	var start := Vector3(cos(a), 0, sin(a)) * (ARENA_R + 1.0)
	var vel := (-start).normalized().rotated(Vector3.UP, rng.randf_range(-0.5, 0.5)) * rng.randf_range(1.0, 1.6)
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 2.2
	p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 2.2
	p.scale_amount_max = 3.4
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := ShaderMaterial.new()
	m.shader = SmokeShader
	m.set_shader_parameter("tint", Color(0.04, 0.03, 0.06))
	m.set_shader_parameter("opacity", 0.7)
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.25, Color(1, 1, 1, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.position = start + Vector3(0, 0.6, 0)
	world3.add_child(p)
	_inks.append({"node": p, "pos": start, "vel": vel, "r": 1.7, "life": 9.0})
	sfx("bubbles", 200)


func _update_inks(delta: float) -> void:
	for ink in _inks.duplicate():
		ink["pos"] = (ink["pos"] as Vector3) + (ink["vel"] as Vector3) * delta
		ink["life"] = float(ink["life"]) - delta
		var p: CPUParticles3D = ink["node"]
		p.position = (ink["pos"] as Vector3) + Vector3(0, 0.6, 0)
		if float(ink["life"]) <= 0.0 or Vector2((ink["pos"] as Vector3).x, (ink["pos"] as Vector3).z).length() > ARENA_R + 3.0:
			p.emitting = false
			_inks.erase(ink)
			get_tree().create_timer(2.5).timeout.connect(p.queue_free)


func _in_ink(pos: Vector3, margin: float) -> bool:
	for ink in _inks:
		var d := Vector2(pos.x - (ink["pos"] as Vector3).x, pos.z - (ink["pos"] as Vector3).z).length()
		if d < float(ink["r"]) + margin:
			return true
	return false


# ── CPU: 점수 / 거리 가 좋은 보물로 (먹물은 돌아감) ──────────
func _think(delta: float) -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) > 0.0 and a.has("goal"):
			w["target"] = a["goal"]
			continue
		var sk := skill(p)
		a["t"] = lerpf(0.55, 0.2, sk / 2.0) + rng.randf_range(0.0, 0.2)
		var pos: Vector3 = w["pos"]
		var best: Vector3 = pos
		var bv := -1.0
		for it in _items:
			var to: Vector3 = it["to"]
			var d := pos.distance_to(to) + (0.6 if it["flying"] else 0.0)
			var v := float(KINDS[it["kind"]]["pts"]) / (d + 1.5)
			if _in_ink(to, 0.3):
				v *= 0.4
			# 다른 말이 더 가까우면 덜 끌림
			for o in walkers.values():
				if o != w and (o["pos"] as Vector3).distance_to(to) < d * 0.6:
					v *= 0.6
			v *= rng.randf_range(lerpf(0.5, 0.85, sk / 2.0), 1.0)
			if v > bv:
				bv = v
				best = to
		if bv < 0.0:
			best = Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		a["goal"] = best
		w["target"] = best


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))
