extends "res://scripts/minigames/minigame_3d.gd"
## 미끄러운 갑판 (WASD + 스페이스): 기름이 쏟아진 둥근 갑판, 다들 얼음판처럼 미끄러져요.
## 이동 = 가속만 붙어서 한번 미끄러지면 잘 안 멈춤(관성). 스페이스 = 앞으로 몸통 박치기 돌진.
## 부딪치면 서로 튕겨 나가고, 가장자리 밖으로 미끄러지면 바다에 풍덩(탈락).
## 굴러오는 술통(1초 전에 줄 경고)에 맞으면 크게 튕겨요. 시간이 갈수록 더 미끄럽고 술통도 잦아짐.
## 마지막까지 갑판에 남은 사람이 승리 (시간이 다 되면 가운데에 가까운 순).

const R := 7.0                  ## 갑판 반지름
const EDGE := R + 0.15          ## 이보다 밖이면 떨어짐
const ACC := 9.5                ## 키를 누를 때 붙는 가속
const MAXV := 6.2
const DASH := 9.0               ## 몸통 박치기 돌진 속도
const DASH_CD := 1.3
const BUMP_R := 0.84

var _raft: Node3D
var _elapsed := 0.0
var _out_at := {}
var _order := 0
var _wait := 0.0
var _pair_cd := {}              ## "a_b" → 남은 시간 (한 번 부딪치면 잠깐 다시 안 튕김)
var _barrels: Array = []        ## {id, start, dir, speed, t0, node, mark, hit{}}
var _barrel_t := 3.0
var _next_barrel := 0
var _ai := {}
var _space_was := false
var _skid_mat: StandardMaterial3D


func _init() -> void:
	title = "SLIPPERY DECK"
	how_to = "Oil spilled all over the deck - it's as slippery as ice! Once you slide, it's hard to stop. Press SPACE to dash and bump others overboard, and dodge the rolling barrels. Last one on deck wins!"
	goal = "Stay on the deck!"
	controls = "KEYS_DASH"
	duration = 45.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	var sea := ocean(-0.55, 180.0, R + 1.5)
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.6)
	sky_clouds(10, 170.0, 26.0)
	cam.fov = 46.0
	cam.position = Vector3(0, 14.2, 12.6)
	cam.look_at(Vector3(0, 0, 0.7))
	_raft = Node3D.new()
	world3.add_child(_raft)
	build_raft(_raft, R, 47)
	_oil_puddles()
	# 기름이 샌 통 (뒤쪽 가장자리, 쓰러져서 기름이 흘러나옴)
	var keg := barrel(_raft, Vector3(-1.6, 0.34, -R + 0.9), 0.34, 0.8, Color(0.2, 0.17, 0.14))
	keg.rotation = Vector3(PI / 2, 0.4, 0)
	sea_debris(8, R + 3.0, R + 10.0, -0.45, 12)
	gulls(4, Vector3(0, 0, -16), 13.0, 5.5, 6)
	island(Vector3(-70, -1.5, -150), 18.0, 12.0, 3)
	_skid_mat = StandardMaterial3D.new()
	_skid_mat.albedo_color = Color(0.05, 0.04, 0.03, 0.8)
	_skid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_skid_mat.roughness = 0.1


## 번들번들한 검은 기름 웅덩이 (무지갯빛이 살짝 도는 반들반들한 막)
func _oil_puddles() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 99
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.07, 0.04, 0.5)   # 젖은 나무처럼 짙어진 정도 (구멍처럼 까맣지 않게)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.roughness = 0.04
	dark.metallic = 0.4
	dark.metallic_specular = 1.0
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.7, Color(1, 1, 1, 0.9))
	g.gradient = gr
	dark.albedo_texture = g
	var sheen := StandardMaterial3D.new()
	sheen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheen.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var sg := GradientTexture2D.new()
	sg.fill = GradientTexture2D.FILL_RADIAL
	sg.fill_from = Vector2(0.5, 0.5)
	sg.fill_to = Vector2(0.5, 0.0)
	var sgr := Gradient.new()
	sgr.set_color(0, Color(0, 0, 0, 0))
	sgr.set_color(1, Color(0, 0, 0, 0))
	sgr.add_point(0.5, Color(0.45, 0.2, 0.55, 0.14))
	sgr.add_point(0.62, Color(0.2, 0.45, 0.55, 0.14))
	sgr.add_point(0.74, Color(0.55, 0.5, 0.15, 0.12))
	sg.gradient = sgr
	sheen.albedo_texture = sg
	var spots := [Vector3(0, 0, 0), Vector3(-2.8, 0, 1.4), Vector3(2.6, 0, -1.8), Vector3(1.2, 0, 3.4), Vector3(-1.5, 0, -3.6),
		Vector3(4.2, 0, 1.6), Vector3(-4.4, 0, -1.2), Vector3(-1.6, 0, -R + 1.8)]
	for k in spots.size():
		var p: Vector3 = spots[k]
		for j in 3:
			var q := QuadMesh.new()
			var sz := rr.randf_range(1.2, 2.2) * (1.0 if j == 0 else 0.6)
			q.size = Vector2(sz * rr.randf_range(1.0, 1.6), sz)
			q.orientation = PlaneMesh.FACE_Y
			var off := Vector3(rr.randf_range(-0.6, 0.6), 0, rr.randf_range(-0.6, 0.6)) * (0.0 if j == 0 else 1.0)
			var mi := add_mesh(q, dark, p + off + Vector3(0, 0.012 + j * 0.002, 0), Basis(Vector3.UP, rr.randf() * TAU), _raft)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if j == 0:
				var sh := add_mesh(q, sheen, p + Vector3(0, 0.018, 0), Basis(Vector3.UP, rr.randf() * TAU), _raft)
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_game() -> void:
	walk_radius = 99.0
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var a := TAU * float(i) / n + PI * 0.25
		var w := add_walker(p, Vector3(cos(a), 0, sin(a)) * 3.4, 5.0)
		w["face"] = atan2(-cos(a), -sin(a))
		w["dash_cd"] = 0.0
		w["dash_t"] = 0.0
		_ai[int(p["slot"])] = {"t": 0.0, "goal": Vector3.ZERO, "target": -1, "inp": Vector3.ZERO}
		scores[int(p["slot"])] = 1


func _start_game() -> void:
	_elapsed = 0.0
	_barrel_t = 3.0


func _alive() -> Array:
	return walkers.keys().filter(func(s: int) -> bool: return not walkers[s]["out"])


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
		var s := local_slot()
		if walkers.has(s):
			_dash(s)


## 돌진: 내 말은 내 PC 가 움직이므로 바로 속도를 붙이고, 모두에게 효과만 알림
func _dash(s: int) -> void:
	var w: Dictionary = walkers[s]
	if w["out"] or float(w["dash_cd"]) > 0.0:
		return
	var dir := Vector3(sin(float(w["face"])), 0, cos(float(w["face"])))
	var inp: Vector3 = key_dir() if is_local(w["p"]) else (_ai[s]["inp"] as Vector3)
	if inp.length() > 0.1:
		dir = inp.normalized()
	w["vel"] = (w["vel"] as Vector3) * 0.35 + dir * DASH
	w["dash_cd"] = DASH_CD
	w["dash_t"] = 0.35
	if is_local(w["p"]):
		net_input("dash")
	else:
		net_call("_dash_fx", [s])   # 방장의 CPU


func _net_input(slot: int, action: String, _args: Array) -> void:
	if action == "dash":
		net_call("_dash_fx", [slot])


func _dash_fx(s: int) -> void:
	var w: Dictionary = walkers.get(s, {})
	if w.is_empty():
		return
	w["dash_t"] = 0.35
	sfx("whoosh", 60)
	splash((w["pos"] as Vector3) + Vector3(0, 0.15, 0), 6, 0.25)


## 방장 → 그 말을 움직이는 PC: 이만큼 튕겨 (내 말이면 바로)
func _kick(s: int, v: Vector3) -> void:
	var w: Dictionary = walkers.get(s, {})
	if w.is_empty() or w["out"]:
		return
	var p: Dictionary = w["p"]
	if net == "host" and s != net_me and not bool(p["cpu"]):
		Net.broadcast({"k": "mg_e", "m": "_kick_me", "v": Marshalls.variant_to_base64([s, v])})
	else:
		w["vel"] = (w["vel"] as Vector3) + v


func _kick_me(s: int, v: Vector3) -> void:
	if s != net_me:
		return
	var w: Dictionary = walkers.get(s, {})
	if not w.is_empty() and not w["out"]:
		w["vel"] = (w["vel"] as Vector3) + v


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	var pr := pressure()
	if not is_client():
		_think(delta)
		_barrel_t -= delta
		if _barrel_t <= 0.0 and _alive().size() > 1:
			_spawn_barrel(pr)
			_barrel_t = lerpf(4.6, 1.7, pr) * rng.randf_range(0.8, 1.2)
	_slide(delta, pr)
	_update_barrels(delta)
	if not is_client():
		_bumps(delta)
		_check_falls()
	if _wait > 0.0:
		_wait -= delta


## 미끄러지는 움직임: 가속만 붙고 마찰은 아주 약함 (시간이 갈수록 더 약해짐)
func _slide(delta: float, pr: float) -> void:
	var fric := lerpf(0.75, 0.35, pr)
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"]:
			continue
		w["dash_cd"] = maxf(0.0, float(w["dash_cd"]) - delta)
		w["dash_t"] = maxf(0.0, float(w["dash_t"]) - delta)
		if w.has("net_pos"):
			_step_puppet(w, delta)
			_pose(w, delta, Vector3.ZERO)
			continue
		var p: Dictionary = w["p"]
		var inp := Vector3.ZERO
		if is_local(p):
			inp = key_dir()
		elif not is_human(p):
			inp = _ai[s]["inp"]
		var vel: Vector3 = w["vel"]
		vel += inp * ACC * delta
		vel *= exp(-fric * delta)
		var sp := vel.length()
		if sp > MAXV:
			vel = vel.normalized() * lerpf(sp, MAXV, clampf(delta * 1.6, 0.0, 1.0))
		var pos: Vector3 = w["pos"] + vel * delta
		# 겹치지 않게 살짝 밀어냄 (튕기는 건 방장이 따로 판정)
		for o in walkers:
			if o == s or walkers[o]["out"]:
				continue
			var d: Vector3 = pos - (walkers[o]["pos"] as Vector3)
			d.y = 0.0
			if d.length() < 0.7 and d.length() > 0.001:
				pos += d.normalized() * (0.7 - d.length()) * 0.5
		pos.y = walk_y
		w["pos"] = pos
		w["vel"] = vel
		if inp.length() > 0.1:
			w["face"] = lerp_angle(float(w["face"]), atan2(inp.x, inp.z), clampf(delta * 9.0, 0.0, 1.0))
		_pose(w, delta, inp)


## 말 자세: 미끄러질 땐 팔 벌리고 휘청 (옆으로 미끄러질수록 크게 기울어짐) · 돌진 땐 앞으로 숙임
func _pose(w: Dictionary, delta: float, inp: Vector3) -> void:
	var n: Node3D = w["node"]
	var vel: Vector3 = w["vel"]
	var sp := vel.length()
	var face := float(w["face"])
	var fwd := Vector3(sin(face), 0, cos(face))
	var side := fwd.cross(Vector3.UP)
	var slip := vel.dot(side) / maxf(MAXV, 0.01)
	w["bob"] = float(w["bob"]) + delta * (4.0 + sp * 1.5)
	var wobble := sin(float(w["bob"]) * 1.7) * 0.12 * clampf(sp / MAXV, 0.0, 1.0)
	var lean_f := 0.45 if float(w["dash_t"]) > 0.0 else clampf(inp.length() * 0.12 + sp * 0.02, 0.0, 0.22)
	n.position = (w["pos"] as Vector3) + Vector3(0, absf(sin(float(w["bob"]))) * 0.05 * clampf(sp / 3.0, 0.0, 1.0), 0)
	n.rotation = Vector3(lean_f, face, clampf(-slip * 0.5, -0.4, 0.4) + wobble)
	# 빠르게 미끄러지면 기름 방울이 튐
	if sp > 3.5 and fmod(_t3 + float(w["bob"]) * 0.01, 0.15) < delta:
		_skid(w)


func _skid(w: Dictionary) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.local_coords = false
	var back := -(w["vel"] as Vector3).normalized()
	p.direction = back + Vector3(0, 0.8, 0)
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -7.0, 0)
	var m := SphereMesh.new()
	m.radius = 0.035
	m.height = 0.07
	m.material = _skid_mat
	p.mesh = m
	p.position = (w["pos"] as Vector3) + Vector3(0, 0.08, 0)
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 방장: 서로 부딪침 → 다가오던 속도만큼 (+ 기본 힘) 서로 반대로 튕김. 돌진 중이면 훨씬 세게
func _bumps(delta: float) -> void:
	for k in _pair_cd.keys():
		_pair_cd[k] = float(_pair_cd[k]) - delta
		if float(_pair_cd[k]) <= 0.0:
			_pair_cd.erase(k)
	var al := _alive()
	for i in al.size():
		for j in range(i + 1, al.size()):
			var a: int = al[i]
			var b: int = al[j]
			var wa: Dictionary = walkers[a]
			var wb: Dictionary = walkers[b]
			var d: Vector3 = (wb["pos"] as Vector3) - (wa["pos"] as Vector3)
			d.y = 0.0
			if d.length() > BUMP_R or d.length() < 0.001:
				continue
			var key := "%d_%d" % [a, b]
			if _pair_cd.has(key):
				continue
			var n := d.normalized()
			var rel := ((wa["vel"] as Vector3) - (wb["vel"] as Vector3)).dot(n)
			if rel < 0.4:
				continue
			_pair_cd[key] = 0.3
			var da := float(wa["dash_t"]) > 0.0
			var db := float(wb["dash_t"]) > 0.0
			var imp := rel * 1.0 + 2.4
			# 돌진한 쪽은 덜 밀리고, 맞은 쪽은 더 멀리
			var ka := imp * (0.45 if da else 0.85) * (1.5 if db else 1.0)
			var kb := imp * (0.45 if db else 0.85) * (1.5 if da else 1.0)
			_kick(a, -n * ka)
			_kick(b, n * kb)
			net_call("_bump_fx", [((wa["pos"] as Vector3) + (wb["pos"] as Vector3)) * 0.5, minf(imp / 8.0, 1.0)])


func _bump_fx(at: Vector3, power: float) -> void:
	sfx("thud", 50)
	if power > 0.6:
		shake(0.25)
	splash(at + Vector3(0, 0.6, 0), int(8 + power * 14), 0.4 + power * 0.4)


## 방장: 가장자리 밖으로 미끄러진 말 → 풍덩
func _check_falls() -> void:
	for s in _alive():
		var pos: Vector3 = walkers[s]["pos"]
		if Vector2(pos.x, pos.z).length() > EDGE:
			net_call("_fall", [s, pos, walkers[s]["vel"]])


func _fall(s: int, at: Vector3, vel: Vector3) -> void:
	var w: Dictionary = walkers[s]
	if w["out"]:
		return
	w["out"] = true
	if OS.get_environment("MG_DEBUG") != "":
		print("MGFALL slot %d t=%.1f" % [s, duration - time_left])
	_out_at[s] = _order
	_order += 1
	scores[s] = 0
	_wait = 1.6
	var n: Node3D = w["node"]
	var from := at
	var flat := Vector2(at.x, at.z).normalized()
	var push := Vector3(flat.x, 0, flat.y) * maxf(vel.length() * 0.35, 1.6)
	var to := from + push + Vector3(0, -1.0, 0)
	sfx("whoosh")
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void:
		n.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 1.2, 0)
		n.rotation = Vector3(f * 2.2, float(w["face"]), sin(f * 9.0) * 0.4), 0.0, 1.0, 0.55)
	tw.tween_callback(func() -> void:
		splash(n.global_position + Vector3(0, 0.4, 0), 45, 1.0)
		sfx("splash")
		n.rotation = Vector3(0.9, rng.randf() * TAU, 0.3)
		var bob := create_tween().set_loops()
		bob.tween_property(n, "position:y", -0.75, 0.9).set_trans(Tween.TRANS_SINE)
		bob.tween_property(n, "position:y", -1.0, 0.9).set_trans(Tween.TRANS_SINE))
	float_at(at + Vector3(0, 2.4, 0), tr("SPLASH!"), Color(0.6, 0.9, 1.0), 44)


# ── 굴러오는 술통 ────────────────────────────────────────────
func _spawn_barrel(pr: float) -> void:
	# 갑판을 가로지르는 줄 하나 (사람이 많은 쪽을 조금 더 노림)
	var a := rng.randf() * TAU
	var dir := Vector3(cos(a), 0, sin(a))
	var side := dir.cross(Vector3.UP)
	var off := rng.randf_range(-R * 0.55, R * 0.55)
	if rng.randf() < 0.6:
		var al := _alive()
		var t: Vector3 = walkers[al[rng.randi() % al.size()]]["pos"]
		off = clampf(t.dot(side), -R * 0.7, R * 0.7)
	var start := side * off - dir * (R + 1.5)
	_next_barrel += 1
	net_call("_barrel_go", [_next_barrel, start, dir, lerpf(5.5, 8.5, pr), _elapsed + 1.1])


func _barrel_go(id: int, start: Vector3, dir: Vector3, speed: float, t0: float) -> void:
	var side := dir.cross(Vector3.UP)
	var lane_a := start + dir * (R * 0.2)
	var lane_b := start + dir * (R * 2.0 + 3.0)
	var mark := rect_mark(Vector3(lane_a.x, 0.04, lane_a.z), Vector3(lane_b.x, 0.04, lane_b.z), 1.3, null, 0.05)
	var root := Node3D.new()
	world3.add_child(root)
	# 옆으로 눕힌 통: holder 의 앞(-Z) 축 = 굴러가는 축(side), 통 가운데가 holder 원점
	var holder := Node3D.new()
	root.add_child(holder)
	holder.basis = Basis.looking_at(side, Vector3.UP)
	var b := barrel(holder, Vector3(0, 0, -0.4), 0.4, 0.8, Color(0.4, 0.25, 0.13))
	b.rotation = Vector3(PI / 2, 0, 0)
	root.position = start + Vector3(0, 0.4, 0)
	_barrels.append({"id": id, "start": start, "dir": dir, "speed": speed, "t0": t0, "node": root, "holder": holder, "mark": mark, "hit": {}, "spin": 0.0})
	sfx("tick", 100)


func _update_barrels(delta: float) -> void:
	for br in _barrels.duplicate():
		var t := _elapsed - float(br["t0"])
		var mark: MeshInstance3D = br["mark"]
		var node: Node3D = br["node"]
		if t < 0.0:
			if is_instance_valid(mark):
				mark.visible = fmod(_elapsed, 0.2) < 0.13 or t < -0.5
			continue
		if is_instance_valid(mark):
			mark.queue_free()
			br["mark"] = null
			sfx("thud", 100)
		var dir: Vector3 = br["dir"]
		var pos: Vector3 = (br["start"] as Vector3) + dir * float(br["speed"]) * t
		node.position = pos + Vector3(0, 0.4, 0)
		(br["holder"] as Node3D).rotate_object_local(Vector3.FORWARD, float(br["speed"]) * delta / 0.4)
		var far := Vector2(pos.x, pos.z).length() > R + 1.2 and pos.dot(dir) > 0.0
		if far:
			# 갑판 밖으로 굴러떨어져 풍덩
			_barrels.erase(br)
			var tw := create_tween()
			tw.tween_property(node, "position", node.position + dir * 1.5 + Vector3(0, -1.6, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void:
				splash(node.position + Vector3(0, 1.0, 0), 25, 0.8)
				node.queue_free())
			continue
		if is_client():
			continue
		var hit: Dictionary = br["hit"]
		for s in _alive():
			if hit.has(s):
				continue
			var d: Vector3 = (walkers[s]["pos"] as Vector3) - pos
			d.y = 0.0
			if d.length() < 0.95:
				hit[s] = true
				var side_dir := d - dir * d.dot(dir)
				var away := side_dir.normalized() if side_dir.length() > 0.05 else dir.cross(Vector3.UP)
				_kick(s, dir * float(br["speed"]) * 1.2 + away * 4.5)
				net_call("_bump_fx", [pos, 1.0])


# ── CPU ─────────────────────────────────────────────────────
## 미끄러지는 걸 감안한 조향: 원하는 속도 - 지금 속도 쪽으로 키를 누름.
## 가장자리에 가까우면 안쪽으로, 술통 줄에 있으면 옆으로 피하고, 가까운 상대에게 다가가 돌진
func _think(delta: float) -> void:
	for s in _alive():
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p)
		a["t"] = float(a["t"]) - delta
		var pos: Vector3 = w["pos"]
		var vel: Vector3 = w["vel"]
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.45, 0.15, sk / 2.0) + rng.randf_range(0.0, 0.15)
			# 가장 가까운 상대
			var best := -1
			var bd := INF
			for o in _alive():
				if o == s:
					continue
				var dd: float = (walkers[o]["pos"] as Vector3).distance_to(pos)
				if dd < bd:
					bd = dd
					best = o
			a["target"] = best
			var goal := Vector3.ZERO
			if best >= 0:
				var tp: Vector3 = walkers[best]["pos"]
				# 상대를 바깥쪽으로 밀 수 있게 상대보다 안쪽에서 접근
				goal = tp - Vector3(tp.x, 0, tp.z).normalized() * 0.9 if Vector2(tp.x, tp.z).length() > 0.5 else tp
				if Vector2(goal.x, goal.z).length() > R * 0.6:
					goal = goal.normalized() * R * 0.6
			# 술통 줄 피하기
			for br in _barrels:
				var dir: Vector3 = br["dir"]
				var st: Vector3 = br["start"]
				var rel := pos - st
				var along := rel.dot(dir)
				var cur := float(br["speed"]) * (_elapsed - float(br["t0"]))
				if along > cur - 0.5:
					var lat := rel - dir * along
					if lat.length() < 1.5:
						var away := lat.normalized() if lat.length() > 0.05 else dir.cross(Vector3.UP)
						goal = pos + away * 2.5
			a["goal"] = goal
		var goal: Vector3 = a["goal"]
		var want := (goal - pos)
		want.y = 0.0
		want = want.limit_length(2.0) * 2.2
		var r := Vector2(pos.x, pos.z).length()
		var outward := Vector3(pos.x, 0, pos.z).normalized() if r > 0.01 else Vector3.ZERO
		# 가장자리 위험: 실력 좋을수록 일찍 알아챔
		var margin := lerpf(0.9, 2.3, sk / 2.0)
		if r > R - margin and vel.dot(outward) > -0.5:
			want = -outward * 4.0
		var steer := want - vel
		a["inp"] = steer.normalized() if steer.length() > 0.35 else Vector3.ZERO
		# 돌진: 상대가 가깝고 그쪽을 향해 있으면 (실력 좋을수록 잘 노림, 가장자리에서 등지고는 안 함)
		var tg := int(a["target"])
		if tg >= 0 and float(w["dash_cd"]) <= 0.0 and walkers.has(tg) and not walkers[tg]["out"]:
			var to: Vector3 = (walkers[tg]["pos"] as Vector3) - pos
			to.y = 0.0
			if to.length() < lerpf(1.8, 2.8, sk / 2.0) and r < R - 1.8:
				var face := Vector3(sin(float(w["face"])), 0, cos(float(w["face"])))
				if face.dot(to.normalized()) > lerpf(0.6, 0.85, sk / 2.0) and rng.randf() < lerpf(0.25, 0.7, sk / 2.0) * delta * 10.0:
					a["inp"] = to.normalized()
					_dash(s)


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	return _alive().size() <= 1 and _wait <= 0.0


## 순위: 끝까지 남은 사람(가운데에 가까운 순) → 늦게 떨어진 순
func _ranking() -> Array:
	var order := players.duplicate()
	var key := func(p: Dictionary) -> float:
		var s := int(p["slot"])
		if _out_at.has(s):
			return float(_out_at[s])
		var pos: Vector3 = walkers[s]["pos"]
		return 1000.0 - Vector2(pos.x, pos.z).length()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 떨어진 사람 · 술통 상태는 이벤트로, 여기선 경과 시간만 맞춤
func _net_state() -> Dictionary:
	return {"el": _elapsed}


func _net_apply(st: Dictionary) -> void:
	_elapsed = float(st.get("el", _elapsed))


func _score_text(p: Dictionary) -> String:
	var s := int(p["slot"])
	if walkers.has(s) and walkers[s]["out"]:
		return "✕"
	return tr("On deck")
