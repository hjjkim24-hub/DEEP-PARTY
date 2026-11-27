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
	auto_bake = true
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
	# 자루 · 위 고리 · 가로대(나무 stock) · 아래 둥근 팔(crown) · 끝의 삽 모양 갈고리(fluke)
	var shank := CylinderMesh.new()
	shank.top_radius = 0.05
	shank.bottom_radius = 0.07
	shank.height = 1.0
	add_mesh(shank, iron, Vector3(0, 0.5, 0), Basis(), anchor)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.06
	ring.outer_radius = 0.11
	add_mesh(ring, iron, Vector3(0, 1.08, 0), Basis(Vector3(1, 0, 0), PI / 2), anchor)
	var stock := CylinderMesh.new()
	stock.top_radius = 0.05
	stock.bottom_radius = 0.05
	stock.height = 0.95
	add_mesh(stock, wood_mat(Color(0.36, 0.24, 0.15), Vector3(0, 1, 0), 0.4), Vector3(0, 0.88, 0), Basis(Vector3(1, 0, 0), PI / 2), anchor)
	for sz: float in [-0.48, 0.48]:
		var cap := SphereMesh.new()
		cap.radius = 0.065
		cap.height = 0.13
		add_mesh(cap, iron, Vector3(0, 0.88, sz), Basis(), anchor)
	var arc_r := 0.42
	var prev := Vector3.ZERO
	for k in 13:
		var ang := lerpf(-1.25, 1.25, k / 12.0)
		var q := Vector3(sin(ang) * arc_r, arc_r - cos(ang) * arc_r + 0.02, 0)
		if k > 0:
			var d := q - prev
			var c := CylinderMesh.new()
			c.top_radius = 0.06
			c.bottom_radius = 0.06
			c.height = d.length() + 0.02
			c.radial_segments = 8
			add_mesh(c, iron, (q + prev) * 0.5, Basis(Vector3(0, 0, 1), -atan2(d.x, d.y)), anchor)
		prev = q
	for sx: float in [-1.0, 1.0]:
		var ang := sx * 1.25
		var tip := Vector3(sin(ang) * arc_r, arc_r - cos(ang) * arc_r + 0.02, 0)
		var fl := CylinderMesh.new()
		fl.top_radius = 0.0
		fl.bottom_radius = 0.16
		fl.height = 0.3
		fl.radial_segments = 3
		var mi := add_mesh(fl, iron, tip + Vector3(sx * 0.06, 0.1, 0), Basis(Vector3(0, 0, 1), -sx * 0.55), anchor)
		mi.scale = Vector3(1.0, 1.0, 0.35)
	anchor.position = Vector3(0.2, SEA_Y - 0.3, z)
	anchor.scale = Vector3.ONE * 1.3
	# 이름표: 배 바로 밑 물속에 (내 배는 크게 "▼ 나" + 빛 고리) — 수면 위가 안 보여도 내 배를 바로 찾게
	var mine := is_local(p)
	var tag := Label3D.new()
	tag.text = ("▼ " + tr("YOU")) if mine else String(p["name"])
	tag.font_size = 64 if mine else 44
	tag.outline_size = 14
	tag.modulate = Color(p["color"]).lightened(0.35)
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.pixel_size = 0.006
	tag.position = Vector3(0, SEA_Y - 0.95, z)
	root.add_child(tag)
	if mine:
		var halo := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.45
		tm.outer_radius = 1.6
		halo.mesh = tm
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.albedo_color = Color(Color(p["color"]).lightened(0.4), 0.7)
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo.material_override = hm
		halo.position = Vector3(0, SEA_Y - 0.12, z)
		halo.scale = Vector3(1.0, 0.3, 0.6)
		root.add_child(halo)
	# 사슬 (닻 ↔ 배)
	# 사슬: 고리를 엇갈려 꿴 쇠사슬 (길이에 맞춰 고리 수를 바꿈)
	var chain := MultiMeshInstance3D.new()
	var mmc := MultiMesh.new()
	mmc.transform_format = MultiMesh.TRANSFORM_3D
	var link := TorusMesh.new()
	link.inner_radius = 0.035
	link.outer_radius = 0.07
	link.rings = 8
	link.ring_segments = 6
	mmc.mesh = link
	mmc.instance_count = 160
	mmc.visible_instance_count = 0
	chain.multimesh = mmc
	chain.material_override = iron
	chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if not is_client():
		_run()


func _run() -> void:
	for r in ROUNDS:
		_round = r
		await _play_round()
	_phase = "done"


func _is_done() -> bool:
	return _phase == "done"


func _play_round() -> void:
	# 판마다: 과녁 위치 · 배 속도 · 물살 · 과녁 크기 (방장이 정해서 모두에게)
	var f := float(_round) / (ROUNDS - 1)
	f = clampf(f + heat * 0.15, 0.0, 1.0)
	var starts := {}
	for s in _boats:
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		starts[s] = [dir, -11.0 * dir - dir * rng.randf_range(0.0, 4.5)]
	net_call("_round_setup", [_round, lerpf(3.2, 7.5, f), lerpf(0.0, 2.4, f) * (1.0 if rng.randf() < 0.5 else -1.0),
		lerpf(1.2, 0.75, f), rng.randf_range(-4.0, 4.0), starts])
	await _big_text(tr("ROUND %d") % (_round + 1), 0.6)
	for s in _boats:
		var p := player_by_slot(s)
		if not is_human(p):
			_ai[s] = _cpu_plan(p, _boats[s])
	_phase = "sail"
	net_call("_set_phase", ["sail"])
	var t := 0.0
	while t < 27.0 / _speed + 1.8:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _all_landed():
			break
	# 아직 안 떨어뜨린 사람은 끝에서 자동으로 (점수 거의 없음)
	for s in _boats:
		if not _boats[s]["dropped"]:
			net_call("_drop_at", [s, float(_boats[s]["x"])])
	while not _all_landed():
		await get_tree().process_frame
	var res := {}
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
		res[s] = [float(b["land_x"]), pts]
	net_call("_score_do", [res])
	await get_tree().create_timer(1.6, false).timeout


## 판 시작 (모두 같게)
func _round_setup(r: int, speed: float, current: float, target_r: float, target_x: float, starts: Dictionary) -> void:
	_round = r
	_speed = speed
	_current = current
	_target_r = target_r
	_target_x = target_x
	_marker.position = Vector3(_target_x, 0, 0)
	_marker.scale = Vector3.ONE * _target_r
	if is_client():
		_big_text(tr("ROUND %d") % (_round + 1), 0.6)
	_show_current()
	for s in _boats:
		var b: Dictionary = _boats[s]
		var st: Array = starts.get(s, [1.0, -11.0])
		b["dropped"] = false
		b["landed"] = false
		b["brake"] = 0.0
		b["dir"] = float(st[0])
		b["x"] = float(st[1])
		b.erase("land_x")
		(b["node"] as Node3D).position.x = b["x"]
		var an: Node3D = b["anchor"]
		an.position = Vector3(0.2, SEA_Y - 0.3, float(b["z"]))
		an.rotation = Vector3.ZERO
	_phase = "intro"


func _set_phase(ph: String) -> void:
	_phase = ph


## 판 점수 (방장이 계산한 착지 자리 · 점수 그대로)
func _score_do(res: Dictionary) -> void:
	_phase = "score"
	for s in res:
		var b: Dictionary = _boats[int(s)]
		var v: Array = res[s]
		b["land_x"] = float(v[0])
		b["landed"] = true
		var pts := int(v[1])
		_total[int(s)] = int(_total[int(s)]) + pts
		scores[int(s)] = _total[int(s)]
		var an: Node3D = b["anchor"]
		an.global_position = Vector3(float(b["land_x"]), 0.05, float(b["z"]))
		float_at(an.global_position + Vector3(0, 1.4, 0), "+%d" % pts if pts > 0 else "0",
			GOLD if pts >= 5 else Color(player_by_slot(int(s))["color"]).lightened(0.3), 46 if pts >= 5 else 36)
	sfx("start")


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
	net_input("drop")


func _net_input(slot: int, action: String, _args: Array) -> void:
	if action == "drop" and _phase == "sail" and _boats.has(slot) and not _boats[slot]["dropped"]:
		net_call("_drop_at", [slot, float(_boats[slot]["x"])])


## 닻 내림 (방장 PC 의 배 자리 기준으로 모두 같게)
func _drop_at(s: int, x: float) -> void:
	var b: Dictionary = _boats[s]
	if b["dropped"]:
		return
	b["x"] = x
	_drop(s)


func _drop(s: int) -> void:
	var b: Dictionary = _boats[s]
	if b["dropped"]:
		return
	b["dropped"] = true
	b["vy"] = 0.0
	b["ax"] = float(b["x"]) + 0.2
	sfx("whoosh", 60)
	splash(Vector3(float(b["x"]), SEA_Y, float(b["z"])), 16, 0.6)


var _edge_lbl: Label


## 내 배가 화면 밖이면 화면 가장자리에 "◀ 나" 화살표
func _edge_marker() -> void:
	var me := local_slot()
	if not _boats.has(me) or _phase != "sail":
		if _edge_lbl:
			_edge_lbl.visible = false
		return
	var b: Dictionary = _boats[me]
	var wp := Vector3(float(b["x"]), SEA_Y - 0.6, float(b["z"]))
	var sp := cam.unproject_position(wp)
	var size := Vector2(vp.size)
	var off := sp.x < 40.0 or sp.x > size.x - 40.0
	if _edge_lbl == null:
		_edge_lbl = Label.new()
		_edge_lbl.add_theme_font_size_override("font_size", 40)
		_edge_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_edge_lbl.add_theme_constant_override("outline_size", 10)
		_overlay.add_child(_edge_lbl)
	_edge_lbl.visible = off
	if off:
		var p := player_by_slot(me)
		_edge_lbl.add_theme_color_override("font_color", Color(p["color"]).lightened(0.35))
		var left := sp.x < 40.0
		_edge_lbl.text = ("◀ " + tr("YOU")) if left else (tr("YOU") + " ▶")
		var scale := get_viewport().get_visible_rect().size.x / size.x
		_edge_lbl.position = Vector2(24.0 if left else get_viewport().get_visible_rect().size.x - _edge_lbl.size.x - 24.0, clampf(sp.y * scale, 120.0, 600.0))


func _tick(delta: float) -> void:
	_t3 += delta
	_edge_marker()
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
					net_call("_drop_at", [s, float(b["x"])])
		if b["dropped"] and not b.get("landed", false):
			b["vy"] = float(b["vy"]) + 12.0 * delta
			var y := an.position.y - float(b["vy"]) * delta
			b["ax"] = float(b["ax"]) + _current * delta
			an.position.x = float(b["ax"]) - node.position.x
			an.rotation.z = lerpf(an.rotation.z, -_current * 0.15, delta * 3.0)
			if y <= 0.05:
				y = 0.05
				b["landed"] = true
				if not b.has("land_x") or not is_client():
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
		var chain: MultiMeshInstance3D = b["chain"]
		var top := node.global_position + Vector3(0.2, SEA_Y - 0.1, float(b["z"]))
		var bot := an.global_transform * Vector3(0, 1.08, 0)
		var d := bot - top
		var mmc := chain.multimesh
		if d.length() > 0.05:
			chain.global_transform = Transform3D.IDENTITY
			var y := d.normalized()
			var xx := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
			var zz := xx.cross(y)
			var step := 0.11
			var cnt := mini(int(d.length() / step) + 1, mmc.instance_count)
			mmc.visible_instance_count = cnt
			for k in cnt:
				var f := float(k) * step
				var bas := Basis(xx, y, zz)
				# 고리를 세로로 세우고 하나 건너 90도 돌림
				bas = bas * Basis(Vector3(1, 0, 0), PI / 2) * Basis(Vector3(0, 0, 1), 0.0)
				if k % 2 == 1:
					bas = Basis(y, PI / 2) * bas
				mmc.set_instance_transform(k, Transform3D(bas.scaled(Vector3(1.0, 1.0, 1.0)) * Basis().scaled(Vector3(1.0, 1.0, 1.7)), top + y * f))
		else:
			mmc.visible_instance_count = 0


# ── 해류 세기 표시 ───────────────────────────────────────────
## 화면 위쪽 패널: 방향 화살표 개수 + 세기 막대 + 말(약함 · 보통 · 강함). 물속엔 해류 따라 흐르는 부유물
var _cur_panel: PanelContainer
var _cur_lbl: Label
var _cur_bar: ProgressBar
var _flow: CPUParticles3D


func _show_current() -> void:
	var c := _current
	var mag := absf(c)
	var word := "No current"
	var arrows := 0
	if mag >= 0.1:
		arrows = clampi(int(ceil(mag / 0.6)), 1, 4)
		word = "Weak current" if mag < 0.8 else ("Medium current" if mag < 1.6 else "Strong current")
	if _cur_panel == null:
		_cur_panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.1, 0.14, 0.82)
		sb.border_color = Color(0.5, 0.9, 1.0, 0.8)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 8
		sb.content_margin_bottom = 10
		_cur_panel.add_theme_stylebox_override("panel", sb)
		_cur_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_cur_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_cur_panel.position.y += 96
		_overlay.add_child(_cur_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		_cur_panel.add_child(v)
		_cur_lbl = Label.new()
		_cur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cur_lbl.add_theme_font_size_override("font_size", 30)
		_cur_lbl.add_theme_color_override("font_color", Color(0.7, 0.97, 1.0))
		_cur_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_cur_lbl.add_theme_constant_override("outline_size", 8)
		v.add_child(_cur_lbl)
		_cur_bar = ProgressBar.new()
		_cur_bar.show_percentage = false
		_cur_bar.custom_minimum_size = Vector2(300, 14)
		_cur_bar.max_value = 2.4
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.45, 0.9, 1.0)
		fill.set_corner_radius_all(7)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.12)
		bg.set_corner_radius_all(7)
		_cur_bar.add_theme_stylebox_override("fill", fill)
		_cur_bar.add_theme_stylebox_override("background", bg)
		v.add_child(_cur_bar)
	var arrow_s := ""
	for k in arrows:
		arrow_s += ("▶" if c > 0 else "◀")
	_cur_lbl.text = (arrow_s + "  " + tr(word) + "  " + arrow_s) if arrows > 0 else tr(word)
	_cur_bar.value = mag
	_cur_panel.modulate.a = 0.0
	create_tween().tween_property(_cur_panel, "modulate:a", 1.0, 0.3)
	# 물속 부유물이 해류 세기만큼 흘러감
	if _flow == null:
		_flow = CPUParticles3D.new()
		_flow.amount = 90
		_flow.lifetime = 6.0
		_flow.preprocess = 6.0
		_flow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_flow.emission_box_extents = Vector3(16, 2.6, 3.0)
		_flow.position = Vector3(0, 3.0, 0)
		_flow.gravity = Vector3.ZERO
		_flow.spread = 6.0
		_flow.local_coords = false
		var qm := QuadMesh.new()
		qm.size = Vector2(0.5, 0.04)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.albedo_color = Color(0.8, 0.95, 1.0, 0.35)
		qm.material = mm
		_flow.mesh = qm
		world3.add_child(_flow)
	_flow.emitting = mag >= 0.1
	_flow.direction = Vector3(signf(c) if c != 0.0 else 1.0, 0, 0)
	_flow.initial_velocity_min = mag * 1.4 + 0.2
	_flow.initial_velocity_max = mag * 1.8 + 0.3


## 온라인: 배 자리 보정 (방장 → 손님)
func _net_state() -> Dictionary:
	var bx := {}
	for s in _boats:
		bx[s] = float(_boats[s]["x"])
	return {"bx": bx}


func _net_apply(st: Dictionary) -> void:
	var bx: Dictionary = st.get("bx", {})
	for s in bx:
		var b: Dictionary = _boats.get(int(s), {})
		if not b.is_empty() and not b["dropped"]:
			b["x"] = lerpf(float(b["x"]), float(bx[s]), 0.5)


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(_total[int(a["slot"])]) > int(_total[int(b["slot"])]))
	return order


func _score_text(p: Dictionary) -> String:
	return str(int(_total.get(int(p["slot"]), 0)))
