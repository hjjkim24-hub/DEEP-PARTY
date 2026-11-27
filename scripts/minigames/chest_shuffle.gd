extends "res://scripts/minigames/minigame_3d.gd"
## 보물상자 셔플 (마우스): 황금 진주가 상자 하나에 들어가면, 크라켄 촉수가 상자들을 휙휙 섞어요.
## 섞기가 끝나면 3 초 안에 진주가 든 상자를 클릭! (3 초 동안은 바꿀 수 있고, 내 화면엔 내 선택만 보임 →
## 3 초가 지나면 잠기고 모두의 선택이 드러남) 맞히면 1점. 4판 (판마다 더 빠르고 많이). 동점이면 함께 순위.

const ROUNDS := 4
## 판마다: 상자 수 · 섞는 횟수 · 한 번 섞는 시간 · 고를 시간 (예전 5판째가 마지막 4판째)
const CHESTS_BY_ROUND := [3, 3, 4, 5]
const SWAPS_BY_ROUND := [5, 7, 9, 16]
const SWAP_TIME_BY_ROUND := [0.6, 0.48, 0.38, 0.21]
const PICK_TIME_BY_ROUND := [3.0, 3.0, 3.0, 3.0]
## 상자 수마다 카메라 자리 (5 개도 양 끝까지 화면에 다 들어오게)
const CAM_BY_COUNT := {3: Vector3(0, 5.2, 7.4), 4: Vector3(0, 5.9, 8.5), 5: Vector3(0, 6.8, 10.2)}

var _chests: Array = []      ## {node, lid, slot(위치 번호)}
var _slots: Array = []       ## 위치 번호 → Vector3
var _pearl_in := 0           ## 진주가 든 상자 번호 (_chests 의 번호)
var _pearl: MeshInstance3D
var _phase := "idle"         ## idle · show · shuffle · pick · reveal · done
var _round := 0
var _picks := {}             ## slot → 상자 번호
var _pick_marks := {}        ## slot → 표시 구슬
var _pick_left := 0.0
var _track := {}             ## CPU 가 믿는 진주 상자 (가끔 놓침)
var _arms: Array = []
var _hover := -1


func _init() -> void:
	auto_bake = true
	title = "CHEST SHUFFLE"
	how_to = "Watch the golden pearl! The kraken's tentacles shuffle the chests - then you have 3 seconds to click the chest with the pearl. You can change your pick until time runs out. 4 rounds, each one faster!"
	goal = "Most correct picks wins!"
	controls = "MOUSE"
	duration = 999.0
	show_timer = false


func _build_stage() -> void:
	env_underwater()
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
	underwater_fx(10.0, 10.0)
	fish_school(Vector3(0.0, 5.5, -6.0), 8.0, 24, 0.3, 0.5, Color(1.0, 0.8, 0.35), Color(0.95, 0.95, 1.0))
	# 무대 조명: 위에서 상자들을 비추는 빛 (주변은 살짝 어둡게)
	env.ambient_light_energy = 0.45
	sun.light_energy = 0.8
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.85, 1.0, 0.95)
	spot.light_energy = 6.0
	spot.spot_range = 16.0
	spot.spot_angle = 26.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = true
	spot.position = Vector3(0, 10.0, 2.5)
	spot.rotation_degrees = Vector3(-80, 0, 0)
	world3.add_child(spot)
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
	var c := treasure_chest(1.35, 0.72, 0.92)
	return {"node": c["root"], "lid": c["lid"], "slot": i, "floor": float(c["floor"])}


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
		# 상자 부품(판자 · 쇠테 · 금장식 수십 개)을 몸통 · 뚜껑 각각 한 덩어리로 (뚜껑은 따로 열리니 따로)
		bake_static(c["lid"])
		bake_static(c["node"])


func _setup_game() -> void:
	for p in players:
		scores[int(p["slot"])] = 0
	_layout(3)


func _start_game() -> void:
	if not is_client():
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
	net_call("_cs_round", [_round, n])
	await _big_text_safe(tr("ROUND %d") % (_round + 1))
	# 1) 진주가 상자 하나로 쏙
	var idx := rng.randi() % n
	net_tell("_cs_show", [idx])
	await _cs_show(idx)
	for p in players:
		_track[int(p["slot"])] = _pearl_in
	await get_tree().create_timer(0.4, false).timeout
	# 2) 섞기: 두 상자가 위아래로 호를 그리며 자리 바꿈
	net_call("_set_phase", ["shuffle"])
	# 보드 후반이면 처음부터 조금 더 빠르고 많이
	var swaps: int = int(SWAPS_BY_ROUND[_round] * (1.0 + heat * 0.3))
	var st: float = SWAP_TIME_BY_ROUND[_round] * (1.0 - heat * 0.15)
	for k in swaps:
		var a := rng.randi() % n
		var b := (a + 1 + rng.randi() % (n - 1)) % n
		# 4판째부터: 두 쌍이 동시에 자리 바꿈 (눈을 두 군데 써야 함)
		if _round >= 3 and n >= 4 and rng.randf() < 0.55:
			var rest := []
			for i in n:
				if i != a and i != b:
					rest.append(i)
			rest.shuffle()
			net_tell("_swap_set", [[[rest[0], rest[1]], [a, b]], st])
			_swap(rest[0], rest[1], st)
		else:
			net_tell("_swap_set", [[[a, b]], st])
		await _swap(a, b, st)
	# 3) 고르기: 3 초 (그동안은 바꿀 수 있음)
	net_call("_cs_pick", [float(PICK_TIME_BY_ROUND[_round])])
	while _pick_left > 0.0:
		await get_tree().process_frame
	# 안 고른 사람은 무작위 → 잠그고 모두의 선택 공개
	for p in players:
		if not _picks.has(int(p["slot"])):
			_choose(int(p["slot"]), rng.randi() % n)
	net_call("_cs_lock", [])
	await get_tree().create_timer(0.9, false).timeout
	# 4) 공개
	net_tell("_cs_reveal", [_pearl_in])
	await _cs_reveal(_pearl_in)


## 판 시작 (모두 같게)
func _cs_round(r: int, n: int) -> void:
	_round = r
	_layout(n)
	_picks.clear()
	for m in _pick_marks.values():
		(m as Node3D).queue_free()
	_pick_marks.clear()
	# 상자가 많아지면 카메라를 뒤로 (양 끝 상자가 잘리지 않게)
	var to: Vector3 = CAM_BY_COUNT.get(n, CAM_BY_COUNT[5])
	var ct := create_tween()
	ct.tween_method(func(f: float) -> void:
		cam.position = cam.position.lerp(to, f)
		cam.look_at(Vector3(0, 0.7, -0.2)), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	if is_client():
		_big_text_safe(tr("ROUND %d") % (_round + 1))


func _set_phase(ph: String) -> void:
	_phase = ph


## 손님: 섞기 신호가 몰려 와도 한 번씩 차례로 (동시에 바꾸는 두 쌍은 같이)
var _swap_q: Array = []
var _swapping := false


func _swap_set(pairs: Array, st: float) -> void:
	_swap_q.append([pairs, st])
	if _swapping:
		return
	_swapping = true
	while not _swap_q.is_empty():
		var job: Array = _swap_q.pop_front()
		var ps: Array = job[0]
		# 밀린 게 많으면 조금 빨리 따라잡기
		var t := float(job[1]) * (0.6 if _swap_q.size() > 1 else 1.0)
		for k in ps.size() - 1:
			_swap(int(ps[k][0]), int(ps[k][1]), t)
		var last: Array = ps[ps.size() - 1]
		await _swap(int(last[0]), int(last[1]), t)
	_swapping = false


var _count_lbl: Label
var _count_last := -1


func _cs_pick(t: float) -> void:
	_phase = "pick"
	_pick_left = t
	_count_last = -1
	if _count_lbl == null:
		_count_lbl = Label.new()
		_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_count_lbl.add_theme_font_size_override("font_size", 120)
		_count_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		_count_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
		_count_lbl.add_theme_constant_override("outline_size", 22)
		_count_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_count_lbl.position.y += 90
		_count_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_overlay.add_child(_count_lbl)
	_count_lbl.visible = true


## 3 초 끝: 잠그고 모두의 선택을 보여 줌
func _cs_lock() -> void:
	_phase = "locked"
	if _count_lbl:
		_count_lbl.visible = false
	for m in _pick_marks.values():
		(m as Node3D).queue_free()
	_pick_marks.clear()
	var stack := {}
	for s in _picks:
		var i := int(_picks[s])
		stack[i] = int(stack.get(i, 0)) + 1
		_place_mark(int(s), i, int(stack[i]))
	sfx("tick")


## 진주가 상자 idx 로 들어가는 장면
func _cs_show(idx: int) -> void:
	_phase = "show"
	_pearl_in = idx
	var c: Dictionary = _chests[_pearl_in]
	await _open(c, true)
	_pearl.visible = true
	var at: Vector3 = (c["node"] as Node3D).position
	# 열린 상자 위에서 떨어져 → 상자 속 벨벳 쿠션 위에 톡 튀며 안착 (벽을 뚫지 않고 안쪽 공간에 들어감)
	var rest := at + Vector3(0, float(c.get("floor", 0.15)) + 0.28, 0)
	_pearl.position = at + Vector3(0, 2.6, 0)
	var t := create_tween()
	t.tween_property(_pearl, "position", rest, 0.75).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.42, false).timeout
	sfx("coins")
	await t.finished
	await get_tree().create_timer(0.45, false).timeout
	# 진주가 든 채로 뚜껑이 닫히고, 다 닫힌 뒤에 숨김
	await _open(c, false)
	_pearl.visible = false


## 공개: 진주 상자가 열리고 맞힌 사람 +1 (점수는 방장 것이 기준)
func _cs_reveal(idx: int) -> void:
	_phase = "reveal"
	_pearl_in = idx
	var win: Dictionary = _chests[_pearl_in]
	await _open(win, true)
	_pearl.visible = true
	_pearl.position = (win["node"] as Node3D).position + Vector3(0, float(win.get("floor", 0.15)) + 0.28, 0)
	var up := create_tween()
	up.tween_property(_pearl, "position:y", 1.6, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sfx("start")
	for p in players:
		var s := int(p["slot"])
		if int(_picks.get(s, -1)) == _chests.find(win):
			if not is_client():
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
	t.tween_property(lid, "rotation:x", -1.85 if open else 0.0, 0.3).set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
	_sand_puff(pa)
	_sand_puff(pb)
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


## 상자가 미끄러질 때 모래가 뿌옇게
func _sand_puff(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, -0.3, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var m := ShaderMaterial.new()
	m.shader = SmokeShader
	m.set_shader_parameter("tint", Color(0.85, 0.78, 0.6))
	m.set_shader_parameter("opacity", 0.45)
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = at + Vector3(0, 0.15, 0)
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _tick(delta: float) -> void:
	_t3 += delta
	for m: ShaderMaterial in _arms:
		m.set_shader_parameter("wtime", _t3)
		m.set_shader_parameter("wave", 0.6 if _phase == "shuffle" else 0.2)
	if _phase == "pick":
		_pick_left -= delta
		# 3 · 2 · 1 카운트 (숫자가 바뀔 때마다 톡)
		var sec := int(ceil(maxf(_pick_left, 0.0)))
		if _count_lbl and sec != _count_last:
			_count_last = sec
			_count_lbl.text = str(maxi(sec, 1))
			_count_lbl.pivot_offset = _count_lbl.size * 0.5
			_count_lbl.scale = Vector2.ONE * 1.35
			create_tween().tween_property(_count_lbl, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
			sfx("tick")
		if not is_client():
			_cpu_picks(delta)
		_hover_chest()


func _cpu_picks(_delta: float) -> void:
	for p in players:
		var s := int(p["slot"])
		if is_human(p) or _picks.has(s):
			continue
		if float(PICK_TIME_BY_ROUND[_round]) - _pick_left > 0.5 + float(s) * 0.25:
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
	var i := _chest_under_mouse()
	if i >= 0:
		net_input("pick", [i])


func _net_input(slot: int, action: String, args: Array) -> void:
	if action == "pick" and _phase == "pick" and args.size() > 0:
		_choose(slot, int(args[0]))


## 고름 (방장이 받아서 모두에게). 3 초 안에는 다시 골라서 바꿀 수 있음
func _choose(s: int, i: int) -> void:
	if _phase != "pick" and _picks.has(s):
		return
	if i < 0 or i >= _chests.size() or int(_picks.get(s, -1)) == i:
		return
	net_call("_choose_do", [s, i])


## 고른 기록: 고르는 동안엔 내 화면에 내 선택만 구슬로 보임 (남의 선택은 3 초 뒤 공개)
func _choose_do(s: int, i: int) -> void:
	_picks[s] = i
	if s == local_slot() and _phase == "pick":
		if _pick_marks.has(s):
			(_pick_marks[s] as Node3D).queue_free()
		_place_mark(s, i, 1)
		sfx("tick")


func _place_mark(s: int, i: int, count: int) -> void:
	var p := player_by_slot(s)
	var n: Node3D = _chests[i]["node"]
	var gem := SphereMesh.new()
	gem.radius = 0.16
	gem.height = 0.32
	var m := std_mat(p["color"], 0.25)
	m.emission_enabled = true
	m.emission = Color(p["color"]) * 0.5
	var mk := add_mesh(gem, m, n.position + Vector3(-0.45 + (count - 1) * 0.3, 1.45, 0.3))
	_pick_marks[s] = mk
	mk.scale = Vector3.ONE * 0.01
	create_tween().tween_property(mk, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(scores[int(a["slot"])]) > int(scores[int(b["slot"])]))
	return order


func _score_text(p: Dictionary) -> String:
	return "%d/%d" % [int(scores[int(p["slot"])]), ROUNDS]
