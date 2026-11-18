extends "res://scripts/minigames/minigame_3d.gd"
## 닻 내리기 (클릭 타이밍): 바닷속을 내려다보는 장면. 바닥 모래에 빛나는 과녁(보물 표시)이 있고,
## 내 배가 물 위를 지나가요. 클릭하면 닻이 떨어져 바닥에 꽂혀요. 과녁 가운데에 가까울수록 점수!
## 5판: 판마다 배가 더 빠르고, 물살이 닻을 옆으로 밀고, 과녁이 작아져요.

const ROUNDS := 5
const SEA_Y := 6.0
const LANE_GAP := 3.2

var _round := 0
var _phase := "idle"
var _boats := {}         ## slot → {node, x, dir, dropped, anchor, land_x, score}
var _target_x := 0.0
var _speed := 3.0
var _current := 0.0
var _target_r := 1.2
var _marker: Node3D
var _total := {}
var _ai := {}


func _init() -> void:
	title = "ANCHOR DROP"
	how_to = "Your boat sails over the sunken treasure! Click to drop your anchor - the closer it lands to the center of the glowing mark, the more points. Watch out for the current!"
	goal = "Most points after 5 drops wins!"
	controls = "MOUSE"
	duration = 999.0
	show_timer = false


func _build_stage() -> void:
	env_underwater()
	env.fog_depth_begin = 12.0
	env.fog_depth_end = 34.0
	cam.fov = 58.0
	cam.position = Vector3(0, 3.6, 10.5)
	cam.look_at(Vector3(0, 2.7, 0))
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/mg_sand.gdshader")
	sm.set_shader_parameter("sand_albedo", kit._mip_tex(load("res://textures/seabed/sand_albedo.png")))
	sm.set_shader_parameter("sand_normal", kit._mip_tex(load("res://textures/seabed/sand_normal.png")))
	add_mesh(pm, sm, Vector3.ZERO)
	# 수면 (밑에서 올려다본 물결면)
	surface_from_below(SEA_Y)
	seed(5)
	var rr := RandomNumberGenerator.new()
	rr.seed = 12
	for k in 10:
		reef("rock", Vector3(-13.0 + k * 2.9 + rr.randf_range(-0.5, 0.5), -0.3, -6.0 + rr.randf_range(-1.5, 1.0)), Color.WHITE, rr.randf_range(1.4, 2.4))
	var cols := [Color(1.0, 0.4, 0.38), Color(0.76, 0.42, 0.98), Color(1.0, 0.6, 0.28), Color(0.35, 0.85, 0.8)]
	for k in 10:
		reef(["coral", "anemone", "fan", "brain", "kelp"][k % 5], Vector3(-12.0 + k * 2.7, 0, -3.8 + rr.randf_range(-0.6, 0.6)), cols[k % 4], 5.0 if k % 5 == 4 else 0.9)
	underwater_fx(14.0, SEA_Y)
	fish_school(Vector3(-4.0, 3.5, -5.0), 7.0, 24, 0.35, 0.45, Color(1.0, 0.75, 0.3), Color(0.95, 0.95, 1.0))
	# 과녁: 바닥의 빛나는 동심원 + 가라앉은 상자
	_marker = Node3D.new()
	world3.add_child(_marker)
	for k in 3:
		var tor := TorusMesh.new()
		tor.inner_radius = 1.0 - k * 0.33 - 0.06
		tor.outer_radius = 1.0 - k * 0.33
		tor.rings = 48
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = [Color(1.0, 0.85, 0.35), Color(1.0, 0.65, 0.25), Color(1.0, 0.4, 0.2)][k]
		add_mesh(tor, m, Vector3(0, 0.04, 0), Basis(), _marker).scale = Vector3(1, 0.15, 1)
	var dot := CylinderMesh.new()
	dot.top_radius = 0.12
	dot.bottom_radius = 0.12
	dot.height = 0.02
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.3, 0.2)
	add_mesh(dot, dm, Vector3(0, 0.05, 0), Basis(), _marker)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.9
	beam.bottom_radius = 1.0
	beam.height = 5.5
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1.0, 0.7, 0.3, 0.06)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_mesh(beam, bm, Vector3(0, 2.75, 0), Basis(), _marker).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.75, 0.35)
	gl.light_energy = 1.5
	gl.omni_range = 3.0
	gl.position = Vector3(0, 0.6, 0)
	_marker.add_child(gl)


## 작은 돛단배 (위쪽 물 위) + 닻
func _make_boat(p: Dictionary, z: float) -> Dictionary:
	var root := Node3D.new()
	world3.add_child(root)
	var boat := sailboat(Color(p["color"]), root, 2.6, 1.0, 0.55)
	boat.position = Vector3(0, SEA_Y - 0.08, z)
	var pawn := make_pawn(p)
	pawn.reparent(root, false)
	pawn.position = Vector3(-0.75, SEA_Y + 0.14, z)
	pawn.scale = Vector3.ONE * 0.7
	# 닻 (쇠)
	var iron := std_mat(Color(0.22, 0.22, 0.24), 0.4, 0.8)
	var anchor := Node3D.new()
	root.add_child(anchor)
	var shank := CylinderMesh.new()
	shank.top_radius = 0.06
	shank.bottom_radius = 0.06
	shank.height = 0.9
	add_mesh(shank, iron, Vector3(0, 0.45, 0), Basis(), anchor)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.13
	add_mesh(ring, iron, Vector3(0, 0.95, 0), Basis(Vector3(1, 0, 0), PI / 2), anchor)
	var arm := TorusMesh.new()
	arm.inner_radius = 0.38
	arm.outer_radius = 0.46
	var am := add_mesh(arm, iron, Vector3(0, 0.38, 0), Basis(Vector3(1, 0, 0), PI / 2), anchor)
	am.scale = Vector3(1, 1, 1)
	# 아래 반만 보이게 위쪽 반원은 가림막 대신 짧은 가로대
	box(Vector3(0.62, 0.07, 0.07), iron, Vector3(0, 0.78, 0), Basis(), anchor)
	for sx: float in [-1.0, 1.0]:
		var tipm := CylinderMesh.new()
		tipm.top_radius = 0.0
		tipm.bottom_radius = 0.09
		tipm.height = 0.22
		add_mesh(tipm, iron, Vector3(sx * 0.4, 0.06, 0), Basis(Vector3(0, 0, 1), sx * 0.6), anchor)
	anchor.position = Vector3(0.2, SEA_Y - 0.3, z)
	anchor.scale = Vector3.ONE * 1.3
	# 사슬 (닻 ↔ 배)
	var chain := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 1.0
	chain.mesh = cm
	chain.material_override = iron
	root.add_child(chain)
	return {"node": root, "x": 0.0, "dir": 1.0, "dropped": false, "anchor": anchor, "chain": chain, "z": z, "land_x": 0.0, "pts": 0, "drop_y": SEA_Y - 0.3, "drift": 0.0}


func _setup_game() -> void:
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var z := (float(i) - (n - 1) * 0.5) * -1.1
		_boats[int(p["slot"])] = _make_boat(p, z)
		_total[int(p["slot"])] = 0
		scores[int(p["slot"])] = 0


func _start_game() -> void:
	_run()


func _run() -> void:
	for r in ROUNDS:
		_round = r
		await _play_round()
	_phase = "done"


func _is_done() -> bool:
	return _phase == "done"


func _play_round() -> void:
	# 판마다: 과녁 위치 · 배 속도 · 물살 · 과녁 크기
	var f := float(_round) / (ROUNDS - 1)
	f = clampf(f + heat * 0.15, 0.0, 1.0)
	_speed = lerpf(3.2, 7.5, f)
	_current = lerpf(0.0, 2.4, f) * (1.0 if rng.randf() < 0.5 else -1.0)
	_target_r = lerpf(1.2, 0.75, f)
	_target_x = rng.randf_range(-4.0, 4.0)
	_marker.position = Vector3(_target_x, 0, 0)
	_marker.scale = Vector3.ONE * _target_r
	await _big_text(tr("ROUND %d") % (_round + 1), 0.6)
	if absf(_current) > 0.1:
		float_at(Vector3(0, 4.0, 0), ("≫ " + tr("Current")) if _current > 0 else (tr("Current") + " ≪"), Color(0.6, 0.95, 1.0), 40)
	for s in _boats:
		var b: Dictionary = _boats[s]
		b["dropped"] = false
		b["landed"] = false
		b["brake"] = 0.0
		b["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
		b["x"] = -11.0 * float(b["dir"]) - float(b["dir"]) * rng.randf_range(0.0, 4.5)
		var an: Node3D = b["anchor"]
		an.position = Vector3(0.2, SEA_Y - 0.3, float(b["z"]))
		an.rotation = Vector3.ZERO
		var p := player_by_slot(s)
		if not is_human(p):
			_ai[s] = _cpu_plan(p, b)
	_phase = "sail"
	var t := 0.0
	while t < 27.0 / _speed + 1.8:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _all_landed():
			break
	# 아직 안 떨어뜨린 사람은 끝에서 자동으로 (점수 거의 없음)
	for s in _boats:
		if not _boats[s]["dropped"]:
			_drop(s)
	while not _all_landed():
		await get_tree().process_frame
	_phase = "score"
	for s in _boats:
		var b: Dictionary = _boats[s]
		var d := absf(float(b["land_x"]) - _target_x) / _target_r
		var pts := 0
		if d <= 0.15:
			pts = 5
		elif d <= 0.45:
			pts = 3
		elif d <= 0.8:
			pts = 2
		elif d <= 1.0:
			pts = 1
		_total[s] = int(_total[s]) + pts
		scores[s] = _total[s]
		var an: Node3D = b["anchor"]
		float_at(an.global_position + Vector3(0, 1.4, 0), "+%d" % pts if pts > 0 else "0",
			GOLD if pts >= 5 else Color(player_by_slot(s)["color"]).lightened(0.3), 46 if pts >= 5 else 36)
	sfx("start")
	await get_tree().create_timer(1.6, false).timeout


func _all_landed() -> bool:
	for s in _boats:
		if not _boats[s].get("landed", false):
			return false
	return true


## CPU: 언제 떨어뜨릴지 미리 계산 (물살까지 읽고) + 실력만큼 오차
func _cpu_plan(p: Dictionary, b: Dictionary) -> Dictionary:
	var sk := skill(p)
	var fall := _fall_time()
	var aim := _target_x - _current * fall
	var err := rng.randf_range(-1.0, 1.0) * lerpf(1.2, 0.3, sk / 2.0) * (1.0 + _speed / 6.0) * 0.6
	return {"x": aim - float(b["dir"]) * _speed * fall * 0.0 + err}


func _fall_time() -> float:
	return sqrt(2.0 * (SEA_Y - 0.3) / 12.0)


func _gui_input(e: InputEvent) -> void:
	if _phase != "sail" or demo:
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for p in players:
		if is_human(p):
			_drop(int(p["slot"]))


func _drop(s: int) -> void:
	var b: Dictionary = _boats[s]
	if b["dropped"]:
		return
	b["dropped"] = true
	b["vy"] = 0.0
	b["ax"] = float(b["x"]) + 0.2
	sfx("whoosh", 60)
	splash(Vector3(float(b["x"]), SEA_Y, float(b["z"])), 16, 0.6)


func _tick(delta: float) -> void:
	_t3 += delta
	for s in _boats:
		var b: Dictionary = _boats[s]
		var node: Node3D = b["node"]
		if _phase == "sail" or _phase == "score":
			# 닻이 바닥에 걸리면 배가 서서히 멈춰 그 자리에 정박
			if _phase == "sail":
				var sp := _speed
				if b.get("landed", false):
					b["brake"] = minf(1.0, float(b.get("brake", 0.0)) + delta * 2.5)
					sp *= 1.0 - float(b["brake"])
				elif b["dropped"]:
					sp *= 0.6
				b["x"] = float(b["x"]) + float(b["dir"]) * sp * delta
			node.position.x = float(b["x"])
			node.rotation.z = sin(_t3 * 1.6 + s) * 0.05
			node.position.y = sin(_t3 * 1.3 + s) * 0.06
		var an: Node3D = b["anchor"]
		if _phase == "sail" and not b["dropped"]:
			var p := player_by_slot(s)
			if not is_human(p) and _ai.has(s):
				# 배가 계획한 자리 근처를 지날 때 떨어뜨림
				if absf(float(b["x"]) + 0.2 - float(_ai[s]["x"])) < _speed * delta * 1.2 + 0.02:
					_drop(s)
		if b["dropped"] and not b.get("landed", false):
			b["vy"] = float(b["vy"]) + 12.0 * delta
			var y := an.position.y - float(b["vy"]) * delta
			b["ax"] = float(b["ax"]) + _current * delta
			an.position.x = float(b["ax"]) - node.position.x
			an.rotation.z = lerpf(an.rotation.z, -_current * 0.15, delta * 3.0)
			if y <= 0.05:
				y = 0.05
				b["landed"] = true
				b["land_x"] = float(b["ax"])
				sfx("thud", 40)
				var sand := CPUParticles3D.new()
				sand.one_shot = true
				sand.amount = 16
				sand.lifetime = 1.2
				sand.explosiveness = 0.9
				sand.direction = Vector3.UP
				sand.spread = 70.0
				sand.initial_velocity_min = 0.6
				sand.initial_velocity_max = 1.6
				sand.gravity = Vector3(0, -0.6, 0)
				var sm := SphereMesh.new()
				sm.radius = 0.08
				sm.height = 0.16
				var smm := StandardMaterial3D.new()
				smm.albedo_color = Color(0.9, 0.82, 0.62, 0.6)
				smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.material = smm
				sand.mesh = sm
				sand.position = Vector3(float(b["ax"]), 0.1, float(b["z"]))
				world3.add_child(sand)
				sand.emitting = true
				sand.finished.connect(sand.queue_free)
			an.position.y = y
		elif b.get("landed", false):
			an.global_position = Vector3(float(b["land_x"]), 0.05, float(b["z"]))
		# 사슬: 배 → 닻 고리
		var chain: MeshInstance3D = b["chain"]
		var top := node.global_position + Vector3(0.2, SEA_Y - 0.1, float(b["z"]))
		var bot := an.global_position + an.basis * Vector3(0, 0.95, 0) * 0.9
		var d := bot - top
		if d.length() > 0.05:
			chain.visible = true
			var y := d.normalized()
			var xx := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
			chain.global_transform = Transform3D(Basis(xx, y * d.length(), xx.cross(y)), (top + bot) * 0.5)
		else:
			chain.visible = false


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(_total[int(a["slot"])]) > int(_total[int(b["slot"])]))
	return order


func _score_text(p: Dictionary) -> String:
	return str(int(_total.get(int(p["slot"]), 0)))
