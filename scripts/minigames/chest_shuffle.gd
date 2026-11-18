extends "res://scripts/minigames/minigame_3d.gd"
## 보물상자 셔플 (마우스): 황금 진주가 상자 하나에 들어가면, 크라켄 촉수가 상자들을 휙휙 섞어요.
## 섞기가 끝나면 진주가 든 상자를 클릭! 맞히면 1점. 3판 (판마다 더 빠르고 많이). 동점이면 함께 순위.

const ROUNDS := 3
const PICK_TIME := 5.0
const CHESTS_BY_ROUND := [3, 4, 4]
const SWAPS_BY_ROUND := [6, 8, 11]
const SWAP_TIME_BY_ROUND := [0.55, 0.42, 0.32]

var _chests: Array = []      ## {node, lid, slot(위치 번호)}
var _slots: Array = []       ## 위치 번호 → Vector3
var _pearl_in := 0           ## 진주가 든 상자 번호 (_chests 의 번호)
var _pearl: MeshInstance3D
var _phase := "idle"         ## idle · show · shuffle · pick · reveal · done
var _round := 0
var _picks := {}             ## slot → 상자 번호
var _pick_marks: Array = []
var _pick_left := 0.0
var _track := {}             ## CPU 가 믿는 진주 상자 (가끔 놓침)
var _arms: Array = []
var _hover := -1


func _init() -> void:
	title = "CHEST SHUFFLE"
	how_to = "Watch the golden pearl! The kraken's tentacles shuffle the chests - then click the chest with the pearl. 3 rounds, each one faster!"
	goal = "Most correct picks wins!"
	controls = "MOUSE"
	duration = 999.0
	show_timer = false


func _build_stage() -> void:
	env_underwater()
	env.fog_density = 0.02
	cam.fov = 42.0
	cam.position = Vector3(0, 5.2, 7.4)
	cam.look_at(Vector3(0, 0.7, -0.2))
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 70)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/mg_sand.gdshader")
	sm.set_shader_parameter("sand_albedo", kit._mip_tex(load("res://textures/seabed/sand_albedo.png")))
	sm.set_shader_parameter("sand_normal", kit._mip_tex(load("res://textures/seabed/sand_normal.png")))
	add_mesh(pm, sm, Vector3.ZERO)
	seed(11)
	var rr := RandomNumberGenerator.new()
	rr.seed = 9
	# 뒤쪽 바위 무대 + 산호
	for k in 9:
		var x := -9.0 + k * 2.3 + rr.randf_range(-0.4, 0.4)
		reef("rock", Vector3(x, -0.3, -4.6 + rr.randf_range(-0.5, 0.6)), Color.WHITE, rr.randf_range(1.3, 2.2))
	var cols := [Color(1.0, 0.4, 0.38), Color(0.76, 0.42, 0.98), Color(1.0, 0.6, 0.28), Color(0.35, 0.85, 0.8)]
	for k in 8:
		var x := -8.0 + k * 2.3
		reef(["coral", "anemone", "fan", "brain"][k % 4], Vector3(x + rr.randf_range(-0.5, 0.5), 0, -3.2 + rr.randf_range(-0.3, 0.3)), cols[k % 4], 0.9)
	for k in 6:
		reef("kelp", Vector3(-10.0 + k * 4.0, 0, -6.5), Color.WHITE, rr.randf_range(5.0, 7.0))
	# 큰 촉수 둘이 무대 양옆에서 (섞을 때 꿈틀)
	for sd: float in [-1.0, 1.0]:
		var tn := tentacle(7.0, 0.7, Vector3(-sd, 0, 0.15))
		(tn["root"] as Node3D).position = Vector3(sd * 6.6, -1.2, -1.2)
		var m: ShaderMaterial = tn["mat"]
		m.set_shader_parameter("pitch", 0.35)
		m.set_shader_parameter("curl", 0.6)
		m.set_shader_parameter("tip", 0.16)
		_arms.append(m)
	# 진주
	var ps := SphereMesh.new()
	ps.radius = 0.28
	ps.height = 0.56
	var pmat := std_mat(Color(1.0, 0.86, 0.45), 0.08, 0.3)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.7, 0.2)
	pmat.emission_energy_multiplier = 1.6
	pmat.rim_enabled = true
	_pearl = add_mesh(ps, pmat, Vector3(0, 2.5, 0))
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.8, 0.4)
	gl.light_energy = 1.5
	gl.omni_range = 3.0
	_pearl.add_child(gl)


func _make_chest(i: int) -> Dictionary:
	var root := Node3D.new()
	world3.add_child(root)
	var wood := wood_mat(Color(0.36, 0.22, 0.13), Vector3(1, 0, 0), 0.35)
	var gold := std_mat(Color(0.95, 0.72, 0.28), 0.3, 0.9)
	box(Vector3(1.3, 0.75, 0.9), wood, Vector3(0, 0.375, 0), Basis(), root)
	for x: float in [-0.55, 0.55]:
		box(Vector3(0.08, 0.79, 0.94), gold, Vector3(x, 0.375, 0), Basis(), root)
	box(Vector3(1.34, 0.08, 0.94), gold, Vector3(0, 0.02, 0), Basis(), root)
	box(Vector3(0.18, 0.22, 0.05), gold, Vector3(0, 0.6, 0.47), Basis(), root)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.75, -0.45)
	root.add_child(lid)
	var lm := CylinderMesh.new()
	lm.top_radius = 0.45
	lm.bottom_radius = 0.45
	lm.height = 1.3
	lm.radial_segments = 20
	add_mesh(lm, wood, Vector3(0, 0, 0.45), Basis(Vector3(0, 0, 1), PI / 2), lid).scale = Vector3(0.55, 1.0, 1.0)
	for x: float in [-0.55, 0.55]:
		var band := CylinderMesh.new()
		band.top_radius = 0.465
		band.bottom_radius = 0.465
		band.height = 0.08
		add_mesh(band, gold, Vector3(x, 0, 0.45), Basis(Vector3(0, 0, 1), PI / 2), lid).scale = Vector3(0.57, 1.0, 1.02)
	return {"node": root, "lid": lid, "slot": i}


func _layout(n: int) -> void:
	for c in _chests:
		(c["node"] as Node3D).queue_free()
	_chests.clear()
	_slots.clear()
	for i in n:
		_slots.append(Vector3((float(i) - (n - 1) * 0.5) * 2.4, 0, 0.6))
		var c := _make_chest(i)
		(c["node"] as Node3D).position = _slots[i]
		_chests.append(c)


func _setup_game() -> void:
	for p in players:
		scores[int(p["slot"])] = 0
	_layout(3)


func _start_game() -> void:
	_run_rounds()


func _run_rounds() -> void:
	for r in ROUNDS:
		_round = r
		await _play_round()
	_phase = "done"


func _is_done() -> bool:
	return _phase == "done"


func _play_round() -> void:
	var n: int = CHESTS_BY_ROUND[_round]
	_layout(n)
	_picks.clear()
	for m in _pick_marks:
		(m as Node3D).queue_free()
	_pick_marks.clear()
	await _big_text_safe(tr("ROUND %d") % (_round + 1))
	# 1) 진주가 상자 하나로 쏙
	_phase = "show"
	_pearl_in = rng.randi() % n
	var c: Dictionary = _chests[_pearl_in]
	await _open(c, true)
	_pearl.visible = true
	var at: Vector3 = (c["node"] as Node3D).position
	_pearl.position = at + Vector3(0, 2.6, 0)
	var t := create_tween()
	t.tween_property(_pearl, "position", at + Vector3(0, 0.55, 0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	sfx("coins")
	await get_tree().create_timer(0.35, false).timeout
	_pearl.visible = false
	await _open(c, false)
	for p in players:
		_track[int(p["slot"])] = _pearl_in
	await get_tree().create_timer(0.4, false).timeout
	# 2) 섞기: 두 상자가 위아래로 호를 그리며 자리 바꿈
	_phase = "shuffle"
	var swaps: int = SWAPS_BY_ROUND[_round]
	var st: float = SWAP_TIME_BY_ROUND[_round]
	for k in swaps:
		var a := rng.randi() % n
		var b := (a + 1 + rng.randi() % (n - 1)) % n
		await _swap(a, b, st)
	# 3) 고르기
	_phase = "pick"
	_pick_left = PICK_TIME
	sfx("toast")
	while _pick_left > 0.0 and _picks.size() < players.size():
		await get_tree().process_frame
	# 안 고른 사람은 무작위
	for p in players:
		if not _picks.has(int(p["slot"])):
			_choose(int(p["slot"]), rng.randi() % n)
	await get_tree().create_timer(0.4, false).timeout
	# 4) 공개
	_phase = "reveal"
	var win: Dictionary = _chests[_pearl_in]
	await _open(win, true)
	_pearl.visible = true
	_pearl.position = (win["node"] as Node3D).position + Vector3(0, 0.7, 0)
	var up := create_tween()
	up.tween_property(_pearl, "position:y", 1.6, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sfx("start")
	for p in players:
		var s := int(p["slot"])
		if int(_picks[s]) == _chests.find(win):
			scores[s] = int(scores[s]) + 1
			float_at((win["node"] as Node3D).position + Vector3(0, 2.4, 0), "+1", Color(p["color"]).lightened(0.3), 46)
	await get_tree().create_timer(1.6, false).timeout
	_pearl.visible = false
	await _open(win, false)


func _big_text_safe(text: String) -> void:
	await _big_text(text, 0.7)


func _open(c: Dictionary, open: bool) -> void:
	var lid: Node3D = c["lid"]
	var t := create_tween()
	t.tween_property(lid, "rotation:x", -1.5 if open else 0.0, 0.25).set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if open:
		sfx("creak", 80)
	else:
		sfx("thud", 80)
	await t.finished


## 두 상자 자리 바꾸기 (하나는 앞으로, 하나는 뒤로 호를 그림)
func _swap(a: int, b: int, time: float) -> void:
	var ca: Dictionary = _chests[a]
	var cb: Dictionary = _chests[b]
	var na: Node3D = ca["node"]
	var nb: Node3D = cb["node"]
	var pa := na.position
	var pb := nb.position
	sfx("whoosh", 60)
	var t := create_tween().set_parallel(true)
	t.tween_method(func(f: float) -> void:
		var e := smoothstep(0.0, 1.0, f)
		na.position = pa.lerp(pb, e) + Vector3(0, sin(e * PI) * 0.5, sin(e * PI) * 1.3)
		nb.position = pb.lerp(pa, e) + Vector3(0, sin(e * PI) * 0.25, -sin(e * PI) * 1.3)
		na.rotation.y = sin(e * PI) * 0.4
		nb.rotation.y = -sin(e * PI) * 0.4, 0.0, 1.0, time)
	for m: ShaderMaterial in _arms:
		m.set_shader_parameter("pitch", 0.35 + rng.randf_range(-0.25, 0.25))
	await t.finished
	var sa: int = ca["slot"]
	ca["slot"] = cb["slot"]
	cb["slot"] = sa
	# CPU 가 따라가기 (실력이 낮을수록, 빠를수록 가끔 놓침)
	for p in players:
		var s := int(p["slot"])
		if is_human(p):
			continue
		var miss := lerpf(0.12, 0.03, skill(p) / 2.0) * (0.55 / time)
		if int(_track[s]) == a or int(_track[s]) == b:
			if rng.randf() < miss:
				# 다른 쪽 상자를 따라감 (헷갈림)
				_track[s] = b if int(_track[s]) == a else a


func _tick(delta: float) -> void:
	_t3 += delta
	for m: ShaderMaterial in _arms:
		m.set_shader_parameter("wtime", _t3)
		m.set_shader_parameter("wave", 0.6 if _phase == "shuffle" else 0.2)
	if _phase == "pick":
		_pick_left -= delta
		_cpu_picks(delta)
		_hover_chest()


func _cpu_picks(_delta: float) -> void:
	for p in players:
		var s := int(p["slot"])
		if is_human(p) or _picks.has(s):
			continue
		if PICK_TIME - _pick_left > 0.6 + float(s) * 0.35:
			_choose(s, int(_track[s]))


func _hover_chest() -> void:
	var i := _chest_under_mouse()
	if i == _hover:
		return
	_hover = i
	for k in _chests.size():
		var n: Node3D = _chests[k]["node"]
		create_tween().tween_property(n, "scale", Vector3.ONE * (1.12 if k == i else 1.0), 0.12)


func _chest_under_mouse() -> int:
	var m := mouse_vp()
	var best := -1
	var bd := 120.0 * (float(vp.size.y) / 1080.0)
	for k in _chests.size():
		var sp := cam.unproject_position((_chests[k]["node"] as Node3D).position + Vector3(0, 0.5, 0))
		var d := sp.distance_to(m)
		if d < bd:
			bd = d
			best = k
	return best


func _gui_input(e: InputEvent) -> void:
	if _phase != "pick" or demo:
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for p in players:
		if is_human(p) and not _picks.has(int(p["slot"])):
			var i := _chest_under_mouse()
			if i >= 0:
				_choose(int(p["slot"]), i)


## 고름: 상자 위에 그 사람 색 구슬이 하나씩 쌓임
func _choose(s: int, i: int) -> void:
	if _picks.has(s):
		return
	_picks[s] = i
	var p := player_by_slot(s)
	var n: Node3D = _chests[i]["node"]
	var count := _picks.values().filter(func(v: int) -> bool: return v == i).size()
	var gem := SphereMesh.new()
	gem.radius = 0.16
	gem.height = 0.32
	var m := std_mat(p["color"], 0.25)
	m.emission_enabled = true
	m.emission = Color(p["color"]) * 0.5
	var mk := add_mesh(gem, m, n.position + Vector3(-0.45 + (count - 1) * 0.3, 1.45, 0.3))
	_pick_marks.append(mk)
	mk.scale = Vector3.ONE * 0.01
	create_tween().tween_property(mk, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sfx("tick")


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(scores[int(a["slot"])]) > int(scores[int(b["slot"])]))
	return order


func _score_text(p: Dictionary) -> String:
	return "%d/%d" % [int(scores[int(p["slot"])]), ROUNDS]
