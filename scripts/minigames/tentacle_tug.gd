extends "res://scripts/minigames/minigame_3d.gd"
## 촉수 줄다리기 (마우스 연타): 배 난간에 나란히 선 네 명이 각자 밧줄로 바다 속 크라켄 촉수와 줄다리기.
## 마우스를 연타하면 내 말이 밧줄을 당겨요. 끝까지 당기면 촉수가 버티다 놓아 줌 (빨리 이길수록 높은 순위).
## 반대로 끌려가 난간을 넘으면 바다에 풍덩 (탈락). 촉수는 갈수록 세게 · 갑자기 확 잡아채기도 해요.

const SEA_Y := -2.8
const PULL := 0.024            ## 한 번 당길 때
const LANE_GAP := 3.3

var _lanes := {}              ## slot → {x, p, done, out, time, pawn, tn, root, rope[], tense, cps, next_click}
var _elapsed := 0.0
var _yank_t := 4.0
var _yank_warn := -1.0
var _rope_mat: StandardMaterial3D


func _init() -> void:
	title = "TENTACLE TUG"
	how_to = "Each of you has a rope tied to a kraken tentacle! Click as fast as you can to pull. Haul it all the way in to win - get dragged over the rail and you're out!"
	goal = "Pull your tentacle in first!"
	controls = "MOUSE"
	duration = 25.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-38, 150, 0)
	env.fog_light_color = Color(0.66, 0.77, 0.86)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	ocean(SEA_Y, 260.0)
	var far := ocean(SEA_Y - 1.3, 5000.0)
	(far.mesh as PlaneMesh).subdivide_width = 2
	(far.mesh as PlaneMesh).subdivide_depth = 2
	(far.material_override as ShaderMaterial).set_shader_parameter("amp", 0.0)
	sky_clouds(14, 260.0, 38.0, Vector3.ZERO, Vector2(-1.3, 1.3))
	cam.fov = 50.0
	cam.position = Vector3(0, 6.4, 10.8)
	cam.look_at(Vector3(0, -0.6, -4.0))
	_rope_mat = std_mat(Color(0.7, 0.58, 0.38), 0.95)
	_build_deck()


func _build_deck() -> void:
	var cols := [Color(0.42, 0.31, 0.21), Color(0.46, 0.34, 0.23), Color(0.39, 0.29, 0.2)]
	for k in 24:
		box(Vector3(1.0, 0.2, 10.0), wood_mat(cols[k % 3], Vector3(0, 0, 1), 0.05), Vector3(-12.0 + k * 1.04, -0.1, 5.0))
	var hull := wood_mat(Color(0.32, 0.21, 0.14), Vector3(1, 0, 0), 0.2)
	var rail := wood_mat(Color(0.5, 0.35, 0.22), Vector3(1, 0, 0), 0.05)
	box(Vector3(26.0, 0.9, 0.35), hull, Vector3(0, 0.45, -0.1))
	box(Vector3(26.4, 0.16, 0.55), rail, Vector3(0, 1.0, -0.1))
	box(Vector3(26.0, 4.0, 0.4), hull, Vector3(0, -2.1, -0.35))
	for k in 14:
		box(Vector3(0.22, 1.05, 0.22), rail, Vector3(-13.0 + k * 2.0, 0.5, 0.15))
	# 밧줄이 걸리는 쇠 고리 (레인마다) · 나무통 · 밧줄 감개
	var iron := std_mat(Color(0.3, 0.29, 0.27), 0.4, 0.6)
	var rope := std_mat(Color(0.62, 0.5, 0.33), 0.95)
	for x: float in [-9.5, 9.5]:
		var c := CylinderMesh.new()
		c.top_radius = 0.42
		c.bottom_radius = 0.42
		c.height = 1.0
		add_mesh(c, wood_mat(Color(0.48, 0.32, 0.2), Vector3(0, 1, 0), 0.1), Vector3(x, 0.5, 2.6))
		for k in 4:
			var tor := TorusMesh.new()
			tor.inner_radius = 0.25 + k * 0.04
			tor.outer_radius = 0.42 + k * 0.04
			add_mesh(tor, rope, Vector3(x * 0.85, 0.07 + k * 0.1, 5.0))
	_lane_iron = iron


var _lane_iron: Material


func _setup_game() -> void:
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var x := (float(i) - (n - 1) * 0.5) * LANE_GAP
		var pawn := make_pawn(p)
		pawn.rotation.y = PI
		# 난간의 쇠 고리
		var tor := TorusMesh.new()
		tor.inner_radius = 0.06
		tor.outer_radius = 0.12
		add_mesh(tor, _lane_iron, Vector3(x, 1.1, -0.1), Basis(Vector3(1, 0, 0), PI / 2))
		# 바다 속 촉수 (곧게 선 채로 배 쪽으로 기울어 밧줄을 붙잡음)
		var tn := tentacle(7.5, 0.7, Vector3(0, 0, 1))
		var m: ShaderMaterial = tn["mat"]
		m.set_shader_parameter("tip", 0.2)
		m.set_shader_parameter("pattern_scale", 2.2)
		var root := Vector3(x, SEA_Y - 3.0, -7.5)
		var rope := []
		for k in 14:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.045
			cy.bottom_radius = 0.045
			cy.height = 1.0
			cy.radial_segments = 8
			var seg := MeshInstance3D.new()
			seg.mesh = cy
			seg.material_override = _rope_mat
			world3.add_child(seg)
			rope.append(seg)
		_lanes[s] = {"x": x, "p": 0.0, "done": false, "out": false, "time": 0.0, "pawn": pawn, "tn": tn, "root": root,
			"rope": rope, "tense": 0.0, "cps": 0.0, "next": rng.randf_range(0.3, 0.6), "jit": 0.0, "pulse": 0.0}
		scores[s] = 0
	_place_all(0.0)


func _start_game() -> void:
	_elapsed = 0.0
	_yank_t = rng.randf_range(4.0, 6.0)


func _gui_input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	for p in players:
		if is_human(p):
			_pull(int(p["slot"]))


func _pull(s: int) -> void:
	var L: Dictionary = _lanes[s]
	if L["done"] or L["out"]:
		return
	L["p"] = float(L["p"]) + PULL
	L["pulse"] = 1.0
	if float(L["p"]) >= 1.0:
		_win(s)


func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	var pr := pressure()
	# 촉수 힘: 갈수록 세짐 (마지막엔 연타로도 버티기 버거움)
	var force := lerpf(0.04, 0.12, pr)
	# 잡아채기: 촉수가 번쩍 빛나며 움찔하는 예고 → 0.5초 뒤 확 끌어감
	_yank_t -= delta
	if _yank_t <= 0.0 and _yank_warn < 0.0:
		_yank_warn = 0.55
		sfx("kraken_rise", 200)
	if _yank_warn >= 0.0:
		_yank_warn -= delta
		if _yank_warn < 0.0:
			for s in _lanes:
				var L: Dictionary = _lanes[s]
				if not L["done"] and not L["out"]:
					L["p"] = maxf(float(L["p"]) - lerpf(0.05, 0.09, pr), -0.8)
			sfx("kraken_slam", 200)
			shake(0.35)
			_yank_t = lerpf(6.0, 3.5, pr) * rng.randf_range(0.8, 1.2)
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		if L["done"] or L["out"]:
			continue
		var p := player_by_slot(s)
		# CPU 연타 (실력 = 초당 횟수, 가끔 힘 빠짐)
		if not is_human(p):
			L["next"] = float(L["next"]) - delta
			while float(L["next"]) <= 0.0 and not L["done"]:
				var sk := skill(p)
				var cps := lerpf(5.5, 9.0, sk / 2.0) * (0.75 + 0.35 * sin(_t3 * 0.9 + s * 1.7)) * rng.randf_range(0.85, 1.15)
				L["next"] = float(L["next"]) + 1.0 / maxf(cps, 1.0)
				_pull(s)
		L["p"] = float(L["p"]) - force * delta * (1.0 + 0.25 * sin(_t3 * 2.1 + s))
		# 처음 4초는 절대 안 끌려감, 그 뒤에도 끝자리에 1.2초 버텨야 끌려감 (한 번 실수로 탈락하지 않게)
		if float(L["p"]) <= -1.0:
			L["p"] = -1.0
			L["edge"] = float(L.get("edge", 0.0)) + delta
			if _elapsed > 4.0 and float(L["edge"]) >= 1.2:
				_drag_out(s)
		else:
			L["edge"] = 0.0
		scores[s] = float(L["p"])
	_place_all(delta)


func _win(s: int) -> void:
	var L: Dictionary = _lanes[s]
	L["done"] = true
	L["time"] = _elapsed
	L["p"] = 1.0
	sfx("start")
	var tn: Dictionary = L["tn"]
	var node: Node3D = tn["root"]
	# 촉수가 버티다 밧줄을 놓고 물속으로
	var t := create_tween()
	t.tween_property(node, "position:y", node.position.y - 9.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	splash(Vector3(float(L["x"]), SEA_Y + 0.2, -7.0), 40, 1.3)
	var pawn: Node3D = L["pawn"]
	var j := create_tween()
	j.tween_property(pawn, "position:y", 1.2, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	j.tween_property(pawn, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	float_at(pawn.position + Vector3(0, 2.4, 0), "%.1fs" % _elapsed, Color(player_by_slot(s)["color"]).lightened(0.3), 46)
	for seg in L["rope"]:
		(seg as Node3D).visible = false


func _drag_out(s: int) -> void:
	var L: Dictionary = _lanes[s]
	L["out"] = true
	L["time"] = _elapsed
	var pawn: Node3D = L["pawn"]
	var from := pawn.position
	var to := Vector3(float(L["x"]), SEA_Y - 0.3, -3.5)
	sfx("whoosh")
	var t := create_tween()
	t.tween_method(func(f: float) -> void:
		pawn.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 2.6, 0)
		pawn.rotation.x = -f * 2.5, 0.0, 1.0, 0.7)
	t.tween_callback(func() -> void:
		splash(to + Vector3(0, 0.4, 0), 50, 1.2)
		sfx("splash")
		pawn.rotation = Vector3(0.9, rng.randf() * TAU, 0.3)
		var bob := create_tween().set_loops()
		bob.tween_property(pawn, "position:y", SEA_Y - 0.15, 0.9).set_trans(Tween.TRANS_SINE)
		bob.tween_property(pawn, "position:y", SEA_Y - 0.4, 0.9).set_trans(Tween.TRANS_SINE))
	for seg in L["rope"]:
		(seg as Node3D).visible = false


## 말 · 촉수 · 밧줄 자리 (당김 정도 p 에 따라)
func _place_all(delta: float) -> void:
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		var x: float = L["x"]
		var f := (float(L["p"]) + 1.0) * 0.5          # 0 = 난간까지 끌려감, 1 = 다 당김
		L["pulse"] = maxf(0.0, float(L["pulse"]) - delta * 6.0)
		var pawn: Node3D = L["pawn"]
		if not L["out"] and not L["done"]:
			pawn.position = Vector3(x, 0.0, lerpf(0.75, 4.2, f))
			# 뒤로 버티는 자세 + 당길 때마다 확 젖힘
			var lean := 0.32 + float(L["pulse"]) * 0.18 + (0.2 if _yank_warn >= 0.0 else 0.0)
			pawn.rotation = Vector3(-lean, PI, sin(_t3 * 9.0 + s) * 0.04)
		var tn: Dictionary = L["tn"]
		var node: Node3D = tn["root"]
		var m: ShaderMaterial = tn["mat"]
		if not L["done"]:
			# 지는 쪽은 촉수가 물 밖으로 높이 솟아 배 쪽을 노려봄, 이기는 쪽은 배 쪽으로 끌려와 낮게 누움
			# 지는 쪽은 촉수가 꼿꼿이 버팀, 끌려올수록 배 쪽으로 휘어 기울어짐
			var root: Vector3 = L["root"]
			var pitch := lerpf(0.08, 0.5, f) + (0.18 if _yank_warn >= 0.0 else 0.0) * -1.0
			node.position = Vector3(root.x, root.y + lerpf(1.0, 1.8, f), root.z + lerpf(0.0, 2.2, f))
			node.rotation = Vector3(0, 0, sin(_t3 * 1.3 + s) * 0.06)
			m.set_shader_parameter("pitch", pitch)
			m.set_shader_parameter("curl", 0.25 + sin(_t3 * 2.0 + s) * 0.15)
			m.set_shader_parameter("hook", 0.0)
			m.set_shader_parameter("tipback", -0.2)
			m.set_shader_parameter("wave", 0.25 + (0.6 if _yank_warn >= 0.0 else 0.0))
			m.set_shader_parameter("wtime", _t3)
			m.set_shader_parameter("glow", 0.9 if _yank_warn >= 0.0 else 0.15)
			L["grip"] = node.position + Vector3(0, 7.5 * 0.62 * cos(pitch * 0.62), 7.5 * 0.62 * sin(pitch * 0.62))
		# 밧줄: 말 허리 → 난간 고리 → 촉수 끝
		if L["out"] or L["done"]:
			continue
		var hand := pawn.position + Vector3(0, 1.05, 0.05)
		var hook := Vector3(x, 1.12, -0.1)
		_rope(L["rope"], [hand, hook, L["grip"]])


func _rope(segs: Array, pts: Array) -> void:
	# 두 구간: 말→고리 (팽팽), 고리→촉수 끝 (살짝 처짐)
	var path := []
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	for k in 5:
		path.append(a.lerp(b, k / 4.0))
	for k in range(1, 10):
		var f := k / 9.0
		path.append(b.lerp(c, f) - Vector3(0, sin(f * PI) * 0.35, 0))
	for k in segs.size():
		var seg: MeshInstance3D = segs[k]
		if k + 1 >= path.size():
			seg.visible = false
			continue
		var p0: Vector3 = path[k]
		var p1: Vector3 = path[k + 1]
		var d := p1 - p0
		var len := d.length()
		if len < 0.001:
			seg.visible = false
			continue
		seg.visible = true
		var y := d / len
		var xx := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		seg.transform = Transform3D(Basis(xx, y * len, xx.cross(y)), (p0 + p1) * 0.5)


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		if not L["done"] and not L["out"]:
			return false
	return true


## 순위: 다 당긴 사람(빨리 끝낸 순) → 남은 사람(많이 당긴 순) → 끌려간 사람(늦게 끌려간 순)
func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	var key := func(p: Dictionary) -> float:
		var L: Dictionary = _lanes[int(p["slot"])]
		if L["done"]:
			return 2000.0 - float(L["time"])
		if L["out"]:
			return float(L["time"])
		return 1000.0 + float(L["p"])
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


func _score_text(p: Dictionary) -> String:
	var L: Dictionary = _lanes[int(p["slot"])]
	if L["done"]:
		return "%.1fs" % float(L["time"])
	if L["out"]:
		return "✕"
	return "%d%%" % int((float(L["p"]) + 1.0) * 50.0)
