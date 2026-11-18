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
var _slam_t := 99.0
var _stripes: Array = []   ## 후반 촉수 내려치기 {a, b, t_hit, mark}
var _stun := {}            ## slot → 남은 기절 시간
var _elapsed := 0.0
var _ai := {}
var _lid: Node3D
var _chest: Node3D
var _meshes := {}
var _arm_mats: Array = []


func _init() -> void:
	title = "TREASURE DIVE"
	how_to = "The kraken's chest is spitting out treasure! Move your pawn with WASD or the arrow keys to grab it. Coin 1, pearl 2, gem 5. Ink clouds slow you down!"
	goal = "Most treasure wins!"
	controls = "KEYS"
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
	underwater_fx(13.0, 13.0)
	fish_school(Vector3(-2.0, 6.5, -4.0), 7.0, 26, 0.35, 0.45, Color(1.0, 0.75, 0.3), Color(0.95, 0.95, 1.0))
	fish_school(Vector3(4.0, 8.0, -7.0), 9.0, 18, 0.25, 0.6, Color(0.4, 0.8, 1.0), Color(0.2, 0.35, 0.8))
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
	var c := treasure_chest(1.9, 0.95, 1.2, _chest)
	_lid = c["lid"]
	# 안에 수북한 금화
	var gold: Material = c["gold"]
	var heap := SphereMesh.new()
	heap.radius = 0.8
	heap.height = 0.5
	var hm := add_mesh(heap, gold, Vector3(0, 0.95, 0), Basis(), _chest)
	hm.scale = Vector3(1.05, 0.7, 0.62)
	_lid.rotation.x = -0.35


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
	# 금화: 가장자리 테가 도톰한 진짜 동전 모양 (돌림 단면)
	var prof := [Vector2(0.0, 0.022), Vector2(0.17, 0.02), Vector2(0.19, 0.032), Vector2(0.235, 0.034), Vector2(0.25, 0.02),
		Vector2(0.25, -0.02), Vector2(0.235, -0.034), Vector2(0.19, -0.032), Vector2(0.17, -0.02), Vector2(0.0, -0.022)]
	_meshes["coin"] = _lathe(prof, 28)
	var cm := std_mat(Color(1.0, 0.8, 0.32), 0.3, 0.75)
	cm.emission_enabled = true
	cm.emission = Color(0.55, 0.38, 0.08)
	(_meshes["coin"] as ArrayMesh).surface_set_material(0, cm)
	var p := SphereMesh.new()
	p.radius = 0.2
	p.height = 0.4
	var pmat := std_mat(KINDS["pearl"]["col"], 0.08, 0.0)
	pmat.clearcoat_enabled = true
	pmat.clearcoat = 1.0
	pmat.rim_enabled = true
	pmat.rim = 0.8
	pmat.rim_tint = 0.3
	pmat.emission_enabled = true
	pmat.emission = Color(0.22, 0.24, 0.28)
	p.material = pmat
	_meshes["pearl"] = p
	# 보석: 브릴리언트 컷 (윗면 평평한 테이블 + 뾰족한 아래)
	var gp := [Vector2(0.0, 0.16), Vector2(0.17, 0.16), Vector2(0.3, 0.06), Vector2(0.3, 0.03), Vector2(0.0, -0.3)]
	_meshes["gem"] = _lathe(gp, 8, true)
	var gm := std_mat(KINDS["gem"]["col"], 0.02, 0.1)
	gm.emission_enabled = true
	gm.emission = Color(0.7, 0.04, 0.12)
	gm.emission_energy_multiplier = 1.2
	gm.rim_enabled = true
	gm.rim = 1.0
	gm.rim_tint = 0.0
	gm.clearcoat_enabled = true
	(_meshes["gem"] as ArrayMesh).surface_set_material(0, gm)


## 단면(반지름, 높이)을 돌려 깎은 메시. flat = 면마다 각지게 (보석)
func _lathe(prof: Array, seg: int, flat: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
			if flat:
				var nrm := (v01 - v00).cross(v11 - v00).normalized()
				if nrm.dot((v00 + v11) * 0.5) < 0.0:
					nrm = -nrm
				for v in [v00, v11, v01, v00, v10, v11]:
					st.set_normal(nrm)
					st.add_vertex(v)
			else:
				for v in [v00, v11, v01, v00, v10, v11]:
					st.add_vertex(v)
	if not flat:
		st.generate_normals()
	return st.commit()


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
	var pr := pressure()
	_ink_t -= delta
	if _ink_t <= 0.0 and _elapsed > lerpf(5.0, 1.0, heat):
		_spawn_ink()
		_ink_t = lerpf(5.5, 1.3, pr) * rng.randf_range(0.8, 1.2)
	# 후반: 크라켄 촉수가 모래를 뚫고 나와 말을 노리고 내려침 (맞으면 기절 + 보물을 흘림)
	if pr > 0.4:
		_slam_t = minf(_slam_t, 1.0)
		_slam_t -= delta
		if _slam_t <= 0.0:
			_slam()
			_slam_t = lerpf(2.4, 0.75, (pr - 0.4) / 0.6) * rng.randf_range(0.85, 1.15)
	for st in _stripes.duplicate():
		if _elapsed >= float(st["t_hit"]):
			_stripes.erase(st)
			_slam_hit(st)
	for s in _stun.keys():
		_stun[s] = float(_stun[s]) - delta
		var w: Dictionary = walkers[s]
		if float(_stun[s]) > 0.0:
			w["target"] = w["pos"]
			(w["node"] as Node3D).rotation.z = sin(_t3 * 20.0) * 0.25
		else:
			_stun.erase(s)
	for m: ShaderMaterial in _arm_mats:
		m.set_shader_parameter("wtime", _t3)
	_update_items(delta)
	_update_inks(delta)
	_think(delta)
	for s in _stun:
		walkers[s]["target"] = walkers[s]["pos"]
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


# ── 후반 촉수 ───────────────────────────────────────────────
func _slam() -> void:
	var alive := walkers.values()
	if alive.is_empty():
		return
	var w: Dictionary = alive[rng.randi() % alive.size()]
	var pr := pressure()
	var target: Vector3 = (w["pos"] as Vector3) + (w["vel"] as Vector3) * lerpf(0.2, 0.5, pr)
	var a := rng.randf_range(1.85, 4.43)
	var out := Vector3(sin(a), 0, cos(a))
	var length := 8.0
	var root := target + out * (length * 0.42)
	var dir := -out
	var a0 := root + dir * length * 0.12
	var a1 := root + dir * length * 0.74
	a0.y = 0.0
	a1.y = 0.0
	var warn := lerpf(1.2, 0.7, pr)
	var mark := rect_mark(a0, a1, 1.6, null, 0.03)
	_stripes.append({"a": a0, "b": a1, "t_hit": _elapsed + warn, "mark": mark})
	slam_tentacle(Vector3(root.x, 0, root.z), dir, length, warn, 0.0)
	sfx("tick", 60)


func _slam_hit(st: Dictionary) -> void:
	sfx("kraken_slam", 90)
	shake(0.4)
	var mark: MeshInstance3D = st["mark"]
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(mark, "transparency", 1.0, 0.25)
	tw.tween_callback(mark.queue_free)
	for s in walkers:
		var w: Dictionary = walkers[s]
		var pos: Vector3 = w["pos"]
		var q := Vector3(pos.x, 0, pos.z)
		var cl := Geometry3D.get_closest_point_to_segment(q, st["a"], st["b"])
		if in_rect(pos, st["a"], st["b"], 1.6, 0.25):
			_stun[s] = 1.1
			var lost := mini(int(scores[s]), 3)
			scores[s] = int(scores[s]) - lost
			w["push"] = (q - cl).normalized() * 6.0 if q.distance_to(cl) > 0.05 else Vector3(1, 0, 0) * 6.0
			sfx("thud")
			if lost > 0:
				float_at(pos + Vector3(0, 2.0, 0), "-%d" % lost, Color(1.0, 0.45, 0.4), 44)
				# 잃은 보물은 둘레에 흩어짐 (다시 주울 수 있음)
				for k in lost:
					var a := rng.randf() * TAU
					var to := pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.2, 2.4)
					var flat := Vector2(to.x, to.z)
					if flat.length() > ARENA_R - 0.5:
						flat = flat.normalized() * (ARENA_R - 0.5)
					_spawn_item("coin", pos + Vector3(0, 0.6, 0), Vector3(flat.x, 0.12, flat.y), 0.6)


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
	var pr := pressure()
	vel *= lerpf(1.0, 1.9, pr)
	var rad := lerpf(1.6, 2.5, pr)
	p.emission_sphere_radius = rad * 0.7
	p.amount = int(lerpf(26, 40, pr))
	_inks.append({"node": p, "pos": start, "vel": vel, "r": rad, "life": 10.0})
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
			for st in _stripes:
				if in_rect(to, st["a"], st["b"], 1.6, 0.6):
					v *= lerpf(0.6, 0.05, sk / 2.0)
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
