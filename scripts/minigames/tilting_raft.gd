extends "res://scripts/minigames/minigame_3d.gd"
## 기우는 뗏목 (WASD + 스페이스): 망망대해에 뜬 작은 통나무 뗏목 위에서 서로 밀어 바다에 떨어뜨리기.
## 뗏목은 사람 무게가 쏠린 쪽으로 기울고 (한쪽에 몰리면 다 같이 미끄러짐), 파도에 계속 출렁임 — 갈수록 파도가 커짐.
## 스페이스 = 앞으로 확 돌진 (부딪친 사람은 튕겨 나감). 바깥 통나무는 삐걱대며 흔들리다(예고) 밧줄이 끊겨 하나씩 떠내려감.
## 바다에 빠지면 탈락 (물에 떠서 허우적). 마지막까지 뗏목 위에 남은 사람이 승리 (시간이 다 되면 남은 사람 중 가운데에 가까운 순).
## 뗏목: 껍질 붙은 굵기 제각각의 통나무 아홉 개를 물속 받침목 두 개에 밧줄로 칭칭 묶고, 가운데는 밧줄을 위아래로 엮음.

const N_LOGS := 9
const LOG_LEN := 7.4
const DECK_TOP := 0.42          ## 뗏목 기준 윗면 높이 (말이 서는 높이)
const BEAM_Z := 2.75            ## 받침목 · 묶은 자리
const ACC := 11.0
const FRIC := 2.6
const MAXV := 4.0
const DASH := 7.2
const DASH_CD := 1.5
const BUMP_R := 0.82
const SLIDE := 27.0             ## 기울기만큼 미끄러지는 힘 (젖은 통나무)
const W_TILT := 0.0105          ## 한 사람 무게(1m 떨어짐)가 만드는 기울기 (통나무 부력이 커서 크게는 안 기욺)
const TILT_MAX := 0.145
const PITCH_MAX := 0.075        ## 앞뒤로는 덜 기욺 (통나무가 길어서 끝이 깊이 잠기지 않게)
const SPRING := 5.0
const DAMP := 2.0
const DETACH_AT := [14.0, 24.0, 34.0, 44.0]
const WARN_T := 2.6

var _raft: Node3D
var _logs: Array = []            ## {x, r, len, z0, node, ropes[], state(0 묶임 1 흔들림 2 떠내려감), warn_t}
var _beams: Array = []           ## 받침목 노드
var _drift: Array = []           ## 떠내려가는 통나무 {node, vx, t, r}
var _swim: Array = []            ## 물에 빠진 말 {node, vel, t}
var _roll := 0.0
var _pitch := 0.0
var _rv := 0.0
var _pv := 0.0
var _heave := 0.0
var _net_r := 0.0
var _net_p := 0.0
var _elapsed := 0.0
var _order: Array = []
var _detach_order: Array = []
var _next_detach := 0
var _pair_cd := {}
var _ai := {}
var _wash_t := 0.0
var _wash := 0.0
var _log_mats: Array = []
var _rope_mat: ShaderMaterial
var _wait := 0.0
var _beam_len := 8.0


func _init() -> void:
	title = "TILTING RAFT"
	how_to = "Push everyone off a small log raft at sea! It tilts toward wherever the weight is - crowd one side and you'll all slide. SPACE dashes forward and bumps others away. The waves keep getting bigger and the outer logs creak and break loose one by one. Fall in and you're out - last one aboard wins!"
	goal = "Be the last one on the raft!"
	controls = "KEYS_DASH"
	duration = 60.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-50, -32, 0)
	env.fog_light_color = Color(0.62, 0.72, 0.8)
	env.fog_density = 0.004
	var sea := ocean(0.0, 260.0, 7.5)   # 뗏목 둘레는 물결이 낮게 (물결이 통나무를 뚫고 올라오지 않게)
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.7)
	sky_clouds(16, 200.0, 32.0)
	gulls(3, Vector3(0, 0, -30), 26.0, 9.0, 4)
	island(Vector3(-140, -1.5, -200), 20.0, 12.0, 9)
	sea_debris(10, 14.0, 40.0, -0.05, 21)
	cam.fov = 46.0
	_raft = Node3D.new()
	world3.add_child(_raft)
	_build_raft()
	_place_cam(true)


func _place_cam(snap: bool = false) -> void:
	var xf := Transform3D(Basis(), Vector3(0, 7.6 + _heave * 0.3, 8.4))
	xf = xf.looking_at(Vector3(0, _heave * 0.3, 0.3), Vector3.UP)
	cam_base = xf
	if snap:
		cam.transform = xf
	else:
		cam.transform = xf


# ── 뗏목 만들기 ─────────────────────────────────────────────
func _build_raft() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 7
	_rope_mat = ShaderMaterial.new()
	_rope_mat.shader = load("res://shaders/rope.gdshader")
	var radii := []
	var total := 0.0
	for i in N_LOGS:
		var r := rr.randf_range(0.34, 0.44)
		radii.append(r)
		total += r * 2.0 + (rr.randf_range(0.02, 0.06) if i < N_LOGS - 1 else 0.0)
	var x := -total * 0.5
	var max_r := 0.0
	for r0: float in radii:
		max_r = maxf(max_r, r0)
	_beam_len = total + 0.5
	var bark := [Color(0.22, 0.15, 0.095), Color(0.25, 0.17, 0.1), Color(0.19, 0.135, 0.085), Color(0.27, 0.19, 0.12)]
	for i in N_LOGS:
		var r: float = radii[i]
		var cx := x + r
		x += r * 2.0 + rr.randf_range(0.02, 0.06)
		var ln := LOG_LEN + rr.randf_range(-0.35, 0.3)
		var z0 := rr.randf_range(-0.18, 0.18)
		var node := Node3D.new()
		node.position = Vector3(cx, DECK_TOP - r, 0)
		_raft.add_child(node)
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/raft_log.gdshader")
		m.set_shader_parameter("radius", r)
		m.set_shader_parameter("seed", float(i) * 1.37 + 0.4)
		m.set_shader_parameter("bark_col", bark[i % bark.size()])
		m.set_shader_parameter("wood_col", Color(0.55, 0.41, 0.27).lerp(Color(0.62, 0.5, 0.36), rr.randf()))
		_log_mats.append(m)
		var bend := Vector2(rr.randf_range(-0.06, 0.06), rr.randf_range(-0.03, 0.05))
		var lm := MeshInstance3D.new()
		lm.mesh = _log_mesh(ln, r, bend, rr.randf() * 10.0)
		lm.material_override = m
		lm.position = Vector3(0, 0, z0)
		node.add_child(lm)
		# 받침목에 묶은 밧줄 (통나무를 세 바퀴 감고 아래 받침목까지 내려감)
		var ropes := []
		for sz: float in [-1.0, 1.0]:
			var rz := sz * BEAM_Z + rr.randf_range(-0.06, 0.06)
			var rope := _lash(r, 2.0 * max_r - 2.0 * r + 0.2, rz, rr)   # 아래로 받침목 밑까지
			node.add_child(rope)
			ropes.append(rope)
		# 가운데: 통나무 위아래로 엮은 밧줄 (짝수 통나무 위로 지나감)
		if i % 2 == 0:
			var pts := []
			for k in 9:
				var a := lerpf(PI + 0.35, -0.35, k / 8.0)
				pts.append(Vector3(cos(a) * (r * 1.09 + 0.03), sin(a) * (r * 1.09 + 0.03), rr.randf_range(-0.01, 0.01) + 0.15))
			var wv := MeshInstance3D.new()
			wv.mesh = _tube(pts, 0.026, 6)
			wv.material_override = _rope_mat
			node.add_child(wv)
			ropes.append(wv)
		_logs.append({"x": cx, "r": r, "len": ln, "z0": z0, "node": node, "ropes": ropes, "state": 0, "warn_t": 0.0})
	# 물속 받침목 두 개 (통나무 아래를 가로질러)
	var beam_m := ShaderMaterial.new()
	beam_m.shader = load("res://shaders/raft_log.gdshader")
	beam_m.set_shader_parameter("radius", 0.13)
	beam_m.set_shader_parameter("seed", 9.1)
	for sz: float in [-1.0, 1.0]:
		var bm := MeshInstance3D.new()
		bm.mesh = _log_mesh(_beam_len, 0.13, Vector2(0.03, 0.02), sz * 3.0)
		bm.material_override = beam_m
		bm.basis = Basis(Vector3.UP, PI / 2)
		bm.position = Vector3(0, DECK_TOP - max_r * 2.0 - 0.1, sz * BEAM_Z)
		_raft.add_child(bm)
		_beams.append(bm)
	# 갑판 위 잡동사니 (가운데 통나무 위 — 끝까지 남는 곳): 감아 둔 밧줄 · 묶어 둔 노
	var mid: Dictionary = _logs[N_LOGS / 2]
	var coil := Node3D.new()
	coil.position = Vector3(0.05, float(mid["r"]) + 0.03, -3.05)
	(mid["node"] as Node3D).add_child(coil)
	for k in 4:
		var t := TorusMesh.new()
		t.inner_radius = 0.17 - k * 0.012
		t.outer_radius = 0.22 - k * 0.012
		t.rings = 24
		t.ring_segments = 8
		add_mesh(t, _rope_mat, Vector3(rr.randf_range(-0.015, 0.015), k * 0.045, rr.randf_range(-0.015, 0.015)), Basis(Vector3.RIGHT, rr.randf_range(-0.06, 0.06)), coil)
	var side: Dictionary = _logs[N_LOGS / 2 + 1]
	var paddle := Node3D.new()
	paddle.position = Vector3(-0.08, float(side["r"]) + 0.03, 1.1)
	paddle.rotation = Vector3(0, 0.06, 0)
	(side["node"] as Node3D).add_child(paddle)
	var oar_wood := std_mat(Color(0.5, 0.38, 0.25), 0.8)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.028
	shaft.bottom_radius = 0.032
	shaft.height = 1.5
	add_mesh(shaft, oar_wood, Vector3(0, 0, 0), Basis(Vector3.RIGHT, PI / 2), paddle)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.2, 0.025, 0.55)
	add_mesh(blade, oar_wood, Vector3(0, 0, 1.0), Basis(), paddle)
	for mi in _raft.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 통나무 메시: 끝으로 갈수록 살짝 가늘고, 길게 휘었고, 둘레가 울퉁불퉁 · 양 끝은 잘린 단면 (COLOR.r = 1)
func _log_mesh(ln: float, r: float, bend: Vector2, ph: float) -> ArrayMesh:
	var NL := 18
	var NA := 18
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var ring_r := func(t: float, a: float) -> float:
		var base := r * (1.04 - 0.08 * t)
		return base * (1.0 + 0.035 * sin(a * 3.0 + ph + t * 4.0) + 0.02 * sin(a * 7.0 + t * 11.0 + ph * 2.0) + 0.012 * sin(a * 13.0 + ph))
	var cen := func(t: float) -> Vector2:
		return bend * sin(PI * t)
	for i in NL:
		var t := float(i) / (NL - 1)
		var z := (t - 0.5) * ln
		var c: Vector2 = cen.call(t)
		for j in NA + 1:
			var a := float(j) / NA * TAU
			var rad: float = ring_r.call(t, a)
			v.append(Vector3(c.x + cos(a) * rad, c.y + sin(a) * rad, z))
			nrm.append(Vector3(cos(a), sin(a), 0))
			uv.append(Vector2(float(j) / NA, z))
			col.append(Color(0, 0, 0))
	for i in NL - 1:
		for j in NA:
			var a0 := i * (NA + 1) + j
			var b0 := a0 + NA + 1
			idx.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	# 잘린 끝 (부채꼴)
	for end in 2:
		var t := float(end)
		var z := (t - 0.5) * ln
		var c: Vector2 = cen.call(t)
		var sz := 1.0 if end == 1 else -1.0
		var ci := v.size()
		v.append(Vector3(c.x, c.y, z))
		nrm.append(Vector3(0, 0, sz))
		uv.append(Vector2.ZERO)
		col.append(Color(1, 0, 0))
		for j in NA + 1:
			var a := float(j) / NA * TAU
			var rad: float = ring_r.call(t, a)
			v.append(Vector3(c.x + cos(a) * rad, c.y + sin(a) * rad, z))
			nrm.append(Vector3(0, 0, sz))
			uv.append(Vector2(cos(a) * rad, sin(a) * rad))
			col.append(Color(1, 0, 0))
		for j in NA:
			if end == 1:
				idx.append_array([ci, ci + 2 + j, ci + 1 + j])
			else:
				idx.append_array([ci, ci + 1 + j, ci + 2 + j])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## 밧줄 관: 점들을 잇는 둥근 관 (UV.x = 길이, UV.y = 둘레)
func _tube(pts: Array, rad: float, seg: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var acc := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var fwd: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() < 0.1:
			side = fwd.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(fwd).normalized()
		if i > 0:
			acc += p.distance_to(pts[i - 1])
		for j in seg + 1:
			var a := float(j) / seg * TAU
			var d := side * cos(a) + up * sin(a)
			v.append(p + d * rad)
			nrm.append(d)
			tan.append_array([fwd.x, fwd.y, fwd.z, 1.0])
			uv.append(Vector2(acc, float(j) / seg))
	for i in pts.size() - 1:
		for j in seg:
			var a0 := i * (seg + 1) + j
			var b0 := a0 + seg + 1
			idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## 통나무 하나를 받침목에 묶은 밧줄: 통나무를 세 바퀴 감고, 아래쪽은 받침목까지 내려가 함께 감음
func _lash(r: float, down: float, z: float, rr: RandomNumberGenerator) -> MeshInstance3D:
	var pts := []
	var turns := 3
	var n := 22
	for k in turns * n + 1:
		var a := float(k) / n * TAU + 0.3
		var rad := r * 1.1 + 0.03 + rr.randf_range(-0.004, 0.004)
		var y := sin(a) * rad
		if y < 0.0:
			y = sin(a) * (rad + down * 0.9)
		pts.append(Vector3(cos(a) * rad, y, z + (float(k) / n - turns * 0.5) * 0.045))
	var mi := MeshInstance3D.new()
	mi.mesh = _tube(pts, 0.024, 6)
	mi.material_override = _rope_mat
	return mi


# ── 시작 ────────────────────────────────────────────────────
func _setup_game() -> void:
	walk_radius = 999.0
	var spots := [Vector3(-1.6, 0, -1.4), Vector3(1.6, 0, 1.4), Vector3(1.6, 0, -1.4), Vector3(-1.6, 0, 1.4)]
	for i in players.size():
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var pos: Vector3 = spots[i % 4]
		var w := add_walker(p, pos, 4.0)
		(w["node"] as Node3D).reparent(_raft, false)
		w["face"] = atan2(-pos.x, -pos.z)
		w["dash_cd"] = 0.0
		w["dash_t"] = 0.0
		w["stun"] = 0.0
		_ai[s] = {"t": 0.0, "goal": pos, "inp": Vector3.ZERO, "target": -1}
		scores[s] = 1.0
	_detach_order = [0, N_LOGS - 1, 1, N_LOGS - 2] if rng.randf() < 0.5 else [N_LOGS - 1, 0, N_LOGS - 2, 1]
	for s in walkers:
		_pose(walkers[s], 0.0, Vector3.ZERO)


func _start_game() -> void:
	_elapsed = 0.0


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


func _dash(s: int) -> void:
	var w: Dictionary = walkers[s]
	if w["out"] or float(w["dash_cd"]) > 0.0 or float(w["stun"]) > 0.0:
		return
	var dir := Vector3(sin(float(w["face"])), 0, cos(float(w["face"])))
	var inp: Vector3 = key_dir() if is_local(w["p"]) else (_ai[s]["inp"] as Vector3)
	if inp.length() > 0.1:
		dir = inp.normalized()
	w["vel"] = (w["vel"] as Vector3) * 0.3 + dir * DASH
	w["dash_cd"] = DASH_CD
	w["dash_t"] = 0.35
	if is_local(w["p"]):
		net_input("dash")
	else:
		net_call("_dash_fx", [s])


func _net_input(slot: int, action: String, _args: Array) -> void:
	if action == "dash":
		net_call("_dash_fx", [slot])


func _dash_fx(s: int) -> void:
	var w: Dictionary = walkers.get(s, {})
	if w.is_empty():
		return
	w["dash_t"] = 0.35
	sfx("whoosh", 60)


## 방장 → 그 말을 움직이는 PC: 이만큼 튕겨 + 잠깐 휘청
func _kick(s: int, v: Vector3, stun: float = 0.0) -> void:
	var w: Dictionary = walkers.get(s, {})
	if w.is_empty() or w["out"]:
		return
	var p: Dictionary = w["p"]
	if net == "host" and s != net_me and not bool(p["cpu"]):
		Net.broadcast({"k": "mg_e", "m": "_kick_me", "v": Marshalls.variant_to_base64([s, v, stun])})
	else:
		w["vel"] = (w["vel"] as Vector3) + v
		w["stun"] = maxf(float(w["stun"]), stun)


func _kick_me(s: int, v: Vector3, stun: float) -> void:
	if s != net_me:
		return
	var w: Dictionary = walkers.get(s, {})
	if not w.is_empty():
		w["vel"] = (w["vel"] as Vector3) + v
		w["stun"] = maxf(float(w["stun"]), stun)


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	if not is_client():
		_think(delta)
		_raft_sim(delta)
		_detach_sched()
	else:
		_roll = lerpf(_roll, _net_r, clampf(delta * 10.0, 0.0, 1.0))
		_pitch = lerpf(_pitch, _net_p, clampf(delta * 10.0, 0.0, 1.0))
	_heave = 0.13 + 0.06 * sin(_t3 * 1.25) + 0.035 * sin(_t3 * 0.77 + 1.3) - 0.012 * _alive().size()   # 통나무는 3분의 1쯤 잠겨 뜸
	_raft.position = Vector3(0, _heave, 0)
	_raft.basis = Basis.from_euler(Vector3(_pitch, 0, _roll))
	_move(delta)
	if not is_client():
		_bumps(delta)
		_check_edges()
	_show_logs(delta)
	_show_swim(delta)
	_show_wash(delta)
	if _wait > 0.0:
		_wait -= delta
	_place_cam()


## 방장: 뗏목 기울기 — 사람 무게가 쏠린 쪽 + 파도 (갈수록 큼) 로 향하는 용수철
func _raft_sim(delta: float) -> void:
	var sx := 0.0
	var sz := 0.0
	for s in _alive():
		var p: Vector3 = walkers[s]["pos"]
		sx += p.x
		sz += p.z
	var grow := clampf(_elapsed / 50.0, 0.0, 1.0)
	var amp := lerpf(0.014, 0.052, grow)
	var wave_r := amp * (sin(_t3 * 1.07) * 0.7 + sin(_t3 * 0.63 + 2.1) * 0.5)
	var wave_p := amp * 0.6 * (sin(_t3 * 0.91 + 0.8) * 0.7 + sin(_t3 * 1.43 + 4.0) * 0.4)
	var req := -W_TILT * sx + wave_r
	var peq := W_TILT * 0.55 * sz + wave_p * 0.6
	_rv += (SPRING * (req - _roll) - DAMP * _rv) * delta
	_pv += (SPRING * (peq - _pitch) - DAMP * _pv) * delta
	_roll = clampf(_roll + _rv * delta, -TILT_MAX, TILT_MAX)
	_pitch = clampf(_pitch + _pv * delta, -PITCH_MAX, PITCH_MAX)


## 뗏목 가장자리 (남은 통나무 기준, 뗏목 좌표): [x 왼쪽, x 오른쪽, z 반길이]
func _edges(ignore_warn: bool = true) -> Array:
	var x0 := INF
	var x1 := -INF
	var hz := INF
	for L: Dictionary in _logs:
		var st := int(L["state"])
		if st == 2 or (st == 1 and not ignore_warn):
			continue
		x0 = minf(x0, float(L["x"]) - float(L["r"]))
		x1 = maxf(x1, float(L["x"]) + float(L["r"]))
		hz = minf(hz, float(L["len"]) * 0.5 - absf(float(L["z0"])))
	return [x0, x1, hz]


## 움직임 (각자 자기 말 · 방장은 CPU 도): 힘 준 만큼 + 기울어진 쪽으로 미끄러짐
func _move(delta: float) -> void:
	var slope := Vector3(-sin(_roll), 0, sin(_pitch) * 1.3) * SLIDE
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"]:
			continue
		w["dash_cd"] = maxf(0.0, float(w["dash_cd"]) - delta)
		w["dash_t"] = maxf(0.0, float(w["dash_t"]) - delta)
		w["stun"] = maxf(0.0, float(w["stun"]) - delta)
		if w.has("net_pos"):
			_step_puppet(w, delta)
			_pose(w, delta, Vector3.ZERO)
			continue
		var p: Dictionary = w["p"]
		var inp := Vector3.ZERO
		if is_local(p) and not demo:
			inp = key_dir()
		elif not is_human(p):
			inp = _ai[s]["inp"]
		if float(w["stun"]) > 0.0:
			inp = Vector3.ZERO
		var vel: Vector3 = w["vel"]
		# 가만히 서 있으면 발로 버텨서 덜 미끄러짐 (움직이거나 휘청이면 그대로 미끄러짐)
		var grip := 0.4 if inp.length() < 0.1 and float(w["stun"]) <= 0.0 and float(w["dash_t"]) <= 0.0 else 1.0
		vel += (inp * ACC + slope * grip) * delta
		vel *= exp(-FRIC * delta)
		var sp := vel.length()
		if sp > MAXV and float(w["dash_t"]) <= 0.0:
			vel = vel.normalized() * lerpf(sp, MAXV, clampf(delta * 3.0, 0.0, 1.0))
		var pos: Vector3 = (w["pos"] as Vector3) + vel * delta
		for o in walkers:
			if o == s or walkers[o]["out"]:
				continue
			var d: Vector3 = pos - (walkers[o]["pos"] as Vector3)
			d.y = 0.0
			if d.length() < 0.66 and d.length() > 0.001:
				pos += d.normalized() * (0.66 - d.length()) * 0.5
		pos.y = 0.0
		w["pos"] = pos
		w["vel"] = vel
		if inp.length() > 0.1:
			w["face"] = lerp_angle(float(w["face"]), atan2(inp.x, inp.z), clampf(delta * 9.0, 0.0, 1.0))
		_pose(w, delta, inp)


## 말 자세: 뗏목이 기울어도 몸은 거의 똑바로 (버팀), 미끄러지면 휘청 · 돌진 땐 앞으로 숙임
func _pose(w: Dictionary, delta: float, inp: Vector3) -> void:
	var n: Node3D = w["node"]
	var vel: Vector3 = w["vel"]
	var sp := vel.length()
	var face := float(w["face"])
	w["bob"] = float(w["bob"]) + delta * (4.0 + sp * 2.0)
	var lean := 0.45 if float(w["dash_t"]) > 0.0 else clampf(inp.length() * 0.1 + sp * 0.03, 0.0, 0.22)
	var fwd := Vector3(sin(face), 0, cos(face))
	var side := fwd.cross(Vector3.UP)
	var slip := clampf(-vel.dot(side) / MAXV * 0.4, -0.35, 0.35) + sin(float(w["bob"]) * 1.3) * 0.06 * clampf(sp / MAXV, 0.0, 1.0)
	var spin := float(w["stun"]) * 8.0
	var hop := absf(sin(float(w["bob"]))) * 0.05 * clampf(sp / 2.5, 0.0, 1.0)
	n.position = (w["pos"] as Vector3) + Vector3(0, DECK_TOP + hop, 0)
	var keep_up := Basis.from_euler(Vector3(-_pitch * 0.75, 0, -_roll * 0.75))
	n.basis = (keep_up * Basis(Vector3.UP, face + spin) * Basis.from_euler(Vector3(lean, 0, slip))).scaled(Vector3.ONE * PAWN_SCALE)


## 방장: 서로 부딪침 (돌진한 쪽이 이김)
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
			var nn := d.normalized()
			var rel := ((wa["vel"] as Vector3) - (wb["vel"] as Vector3)).dot(nn)
			if rel < 0.5:
				continue
			_pair_cd[key] = 0.3
			var da := float(wa["dash_t"]) > 0.0
			var db := float(wb["dash_t"]) > 0.0
			var imp := rel * 0.8 + 1.6
			_kick(a, -nn * imp * (0.35 if da else 0.75) * (1.6 if db else 1.0), 0.25 if db else 0.0)
			_kick(b, nn * imp * (0.35 if db else 0.75) * (1.6 if da else 1.0), 0.25 if da else 0.0)
			net_call("_bump_fx", [((wa["pos"] as Vector3) + (wb["pos"] as Vector3)) * 0.5, minf(imp / 7.0, 1.0)])


func _bump_fx(at: Vector3, power: float) -> void:
	sfx("thud", 45 + int(power * 40.0))
	var g := _raft.global_transform * (at + Vector3(0, DECK_TOP + 0.6, 0))
	splash(g, int(4 + power * 8), 0.3 + power * 0.3)


# ── 떨어짐 ──────────────────────────────────────────────────
func _check_edges() -> void:
	var e := _edges()
	for s in _alive():
		var w: Dictionary = walkers[s]
		var p: Vector3 = w["pos"]
		if p.x < float(e[0]) - 0.12 or p.x > float(e[1]) + 0.12 or absf(p.z) > float(e[2]) + 0.12:
			net_call("_fall", [s, p, w["vel"]])


## 모두: 바다로 풍덩 → 탈락. 말은 물에 떠서 허우적대며 조금씩 떠내려감
func _fall(s: int, at: Vector3, vel: Vector3) -> void:
	var w: Dictionary = walkers[s]
	if w["out"]:
		return
	w["out"] = true
	_order.append(s)
	scores[s] = 0.0
	_wait = 1.3
	if OS.get_environment("MG_DEBUG") != "":
		print("TR fall s=%d x=%.1f z=%.1f t=%.1f" % [s, at.x, at.z, _elapsed])
	var n: Node3D = w["node"]
	n.reparent(world3, true)
	var out_dir := Vector3(at.x, 0, at.z).normalized() if Vector3(at.x, 0, at.z).length() > 0.1 else Vector3(1, 0, 0)
	var g0 := n.global_position
	var land := g0 + out_dir * 1.1 + Vector3(vel.x, 0, vel.z) * 0.15
	land.y = -0.95
	sfx("whoosh", 70)
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void:
		n.global_position = g0.lerp(land, f) + Vector3(0, sin(f * PI) * 0.7, 0)
		n.rotation = Vector3(f * 1.2, n.rotation.y, 0), 0.0, 1.0, 0.5)
	tw.tween_callback(func() -> void:
		splash(Vector3(land.x, 0.1, land.z), 40, 1.0)
		sfx("splash", 100)
		_swim.append({"node": n, "vel": out_dir * 0.35, "t": 0.0, "ph": randf() * TAU}))
	if is_local(w["p"]):
		shake(0.3)


func _show_swim(delta: float) -> void:
	for sw: Dictionary in _swim:
		var n: Node3D = sw["node"]
		sw["t"] = float(sw["t"]) + delta
		var t := float(sw["t"])
		var p := n.global_position + (sw["vel"] as Vector3) * delta
		p.y = lerpf(p.y, -1.02 + sin(t * 2.4 + float(sw["ph"])) * 0.07, clampf(delta * 3.0, 0.0, 1.0))   # 머리만 내놓고 허우적
		n.global_position = p
		n.rotation = Vector3(sin(t * 3.1) * 0.15 + 0.15, n.rotation.y + delta * 0.4, sin(t * 2.3) * 0.18)
		sw["vel"] = (sw["vel"] as Vector3) * exp(-0.3 * delta)
		if fmod(t + float(sw["ph"]), 1.1) < delta:
			splash(Vector3(p.x, 0.08, p.z), 5, 0.3)   # 허우적


# ── 통나무가 떨어져 나감 ────────────────────────────────────
func _detach_sched() -> void:
	if _next_detach >= DETACH_AT.size():
		return
	if _elapsed >= float(DETACH_AT[_next_detach]) - WARN_T:
		var i: int = _detach_order[_next_detach]
		_next_detach += 1
		net_call("_log_warn", [i])


func _log_warn(i: int) -> void:
	var L: Dictionary = _logs[i]
	L["state"] = 1
	L["warn_t"] = WARN_T
	sfx("creak", 90)


func _log_go(i: int) -> void:
	var L: Dictionary = _logs[i]
	if int(L["state"]) == 2:
		return
	L["state"] = 2
	var node: Node3D = L["node"]
	for r in L["ropes"]:
		(r as Node3D).visible = false
	node.reparent(world3, true)
	_drift.append({"node": node, "vx": signf(float(L["x"])) * 0.9, "t": 0.0, "r": float(L["r"])})
	sfx("snap", 100)
	sfx("splash", 70)
	splash(node.global_position + Vector3(0, 0.4, 0), 30, 0.8)
	debris(node.global_position + Vector3(0, 0.5, BEAM_Z), Color(0.6, 0.5, 0.34), 8)
	debris(node.global_position + Vector3(0, 0.5, -BEAM_Z), Color(0.6, 0.5, 0.34), 8)
	# 받침목도 남은 폭만큼 (끊어진 쪽 끝은 물속으로 감춰짐)
	var e := _edges()
	for b: Node3D in _beams:
		b.position.x = (float(e[0]) + float(e[1])) * 0.5
		var wdt := float(e[1]) - float(e[0]) + 0.5
		b.basis = Basis(Vector3.UP, PI / 2).scaled(Vector3(wdt / _beam_len, 1, 1))
	shake(0.2)


## 모두: 흔들리는 통나무 (예고) · 떠내려가는 통나무 · 젖음 높이
func _show_logs(delta: float) -> void:
	for i in _logs.size():
		var L: Dictionary = _logs[i]
		var node: Node3D = L["node"]
		if int(L["state"]) == 1:
			L["warn_t"] = float(L["warn_t"]) - delta
			var k := 1.0 - float(L["warn_t"]) / WARN_T
			node.position = Vector3(float(L["x"]) + sin(_t3 * 37.0) * 0.012 * (0.5 + k), DECK_TOP - float(L["r"]) + sin(_t3 * 23.0) * 0.02 * (0.4 + k), 0)
			node.rotation = Vector3(0, 0, sin(_t3 * 19.0) * 0.05 * (0.4 + k))
			for r in L["ropes"]:
				(r as Node3D).scale = Vector3.ONE * (1.0 + sin(_t3 * 31.0) * 0.04 * k)
			if fmod(float(L["warn_t"]), 0.8) < delta:
				sfx("creak", 50)
			if not is_client() and float(L["warn_t"]) <= 0.0:
				net_call("_log_go", [i])
	for dr: Dictionary in _drift:
		var n: Node3D = dr["node"]
		dr["t"] = float(dr["t"]) + delta
		var t := float(dr["t"])
		var p := n.global_position
		p.x += float(dr["vx"]) * delta
		dr["vx"] = float(dr["vx"]) * exp(-0.25 * delta)
		p.y = lerpf(p.y, 0.04 + sin(t * 1.6) * 0.06, clampf(delta * 1.5, 0.0, 1.0))   # 반쯤 잠겨 둥둥
		n.global_position = p
		var b := n.global_transform.basis.get_rotation_quaternion()
		var flat := Quaternion(Vector3.FORWARD, sin(t * 0.9) * 0.08 + t * 0.15 * signf(float(dr["vx"]) + 0.001))
		n.quaternion = b.slerp(flat, clampf(delta * 1.2, 0.0, 1.0))
	for m: ShaderMaterial in _log_mats:
		m.set_shader_parameter("wash", _wash)


## 크게 기울면 낮은 쪽 가장자리로 바닷물이 넘쳐 들어옴 (물보라 + 윗면이 잠깐 젖음)
func _show_wash(delta: float) -> void:
	_wash = maxf(0.0, _wash - delta * 0.15)
	var tilt := maxf(absf(_roll), absf(_pitch))
	if tilt < 0.075:
		return
	_wash_t -= delta
	if _wash_t > 0.0:
		return
	_wash_t = lerpf(0.5, 0.15, clampf((tilt - 0.075) / 0.06, 0.0, 1.0))
	_wash = minf(1.0, _wash + 0.15)
	var e := _edges()
	var at: Vector3
	if absf(_roll) >= absf(_pitch):
		at = Vector3(float(e[1]) if _roll < 0.0 else float(e[0]), DECK_TOP - 0.1, rng.randf_range(-3.0, 3.0))
	else:
		at = Vector3(rng.randf_range(float(e[0]), float(e[1])), DECK_TOP - 0.1, float(e[2]) * (1.0 if _pitch > 0.0 else -1.0))
	splash(_raft.global_transform * at, 10, 0.55)
	if rng.randf() < 0.35:
		sfx("splash", 35)


# ── CPU ─────────────────────────────────────────────────────
## 가장자리(곧 떨어질 통나무 포함)에서 멀찍이 · 크게 기울면 높은 쪽으로 버팀.
## 가장자리 가까이 있는 상대를 골라 그 바깥쪽 반대편에서 다가가 돌진해 밀어냄. 실력이 좋을수록 침착하고 정확함
func _think(delta: float) -> void:
	var e := _edges(false)
	var cx := (float(e[0]) + float(e[1])) * 0.5
	var hx := (float(e[1]) - float(e[0])) * 0.5
	var hz := float(e[2])
	var uphill := Vector3(sin(_roll), 0, -sin(_pitch))
	for s in _alive():
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p) / 2.0
		var pos: Vector3 = w["pos"]
		var vel: Vector3 = w["vel"]
		var margin := lerpf(0.7, 1.25, sk)
		var edge_x := hx - absf(pos.x - cx)
		var edge_z := hz - absf(pos.z)
		var edge := minf(edge_x, edge_z)
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.35, 0.14, sk) + rng.randf_range(0.0, 0.1)
			var goal := pos
			var best := -1
			var bv := INF
			for o in _alive():
				if o == s:
					continue
				var op: Vector3 = walkers[o]["pos"]
				var oe := minf(hx - absf(op.x - cx), hz - absf(op.z))
				var v := oe * 1.6 + op.distance_to(pos) * 0.35 + rng.randf_range(0.0, lerpf(1.2, 0.2, sk))
				if v < bv:
					bv = v
					best = o
			a["target"] = best
			if best >= 0:
				var tp: Vector3 = walkers[best]["pos"]
				# 상대에게 가장 가까운 가장자리 쪽으로 밀어내려면 그 반대편에 서야 함
				var ex := hx - absf(tp.x - cx)
				var ez := hz - absf(tp.z)
				var out := Vector3(signf(tp.x - cx), 0, 0) if ex < ez else Vector3(0, 0, signf(tp.z))
				goal = tp - out * 1.5
			goal.x = clampf(goal.x, cx - hx + margin, cx + hx - margin)
			goal.z = clampf(goal.z, -hz + margin, hz - margin)
			a["goal"] = goal
		var g: Vector3 = a["goal"]
		var want := (g - pos)
		want.y = 0.0
		want = want.limit_length(1.0) * MAXV * 0.8
		# 가장자리 · 기울기 대응
		if edge < margin:
			var inward := Vector3(cx - pos.x, 0, -pos.z).normalized()
			want = want * 0.3 + inward * MAXV
		var tilt := maxf(absf(_roll), absf(_pitch))
		if tilt > lerpf(0.12, 0.06, sk):
			want += uphill.normalized() * MAXV * 0.6 if uphill.length() > 0.01 else Vector3.ZERO
		# 미끄러지는 힘을 미리 버팀 (실력만큼)
		var steer := want - vel - Vector3(-sin(_roll), 0, sin(_pitch)) * SLIDE * lerpf(0.0, 0.08, sk)
		a["inp"] = steer.normalized() if steer.length() > 0.3 else Vector3.ZERO
		# 돌진: 상대가 바로 앞(가장자리 쪽 방향으로 일직선)이면
		var tg := int(a["target"])
		if tg >= 0 and walkers.has(tg) and not walkers[tg]["out"] and float(w["dash_cd"]) <= 0.0 and edge > margin * 0.8:
			var tp2: Vector3 = walkers[tg]["pos"]
			var d := tp2 - pos
			d.y = 0.0
			if d.length() < lerpf(1.9, 2.5, sk) and d.length() > 0.4:
				var after := tp2 + d.normalized() * 1.5
				var off_edge := absf(after.x - cx) > hx - 0.2 or absf(after.z) > hz - 0.2
				if (off_edge or rng.randf() < 0.3) and rng.randf() < lerpf(0.25, 0.7, sk) * delta * 8.0:
					a["inp"] = d.normalized()
					w["face"] = atan2(d.x, d.z)
					_dash(s)


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	return _alive().size() <= 1 and _wait <= 0.0


## 순위: 끝까지 남은 사람 (가운데에 가까운 순) → 늦게 빠진 순
func _ranking() -> Array:
	var order := players.duplicate()
	var key := func(p: Dictionary) -> float:
		var s := int(p["slot"])
		var i := _order.find(s)
		if i >= 0:
			return float(i)
		return 1000.0 - (walkers[s]["pos"] as Vector3).length()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 뗏목 기울기 · 시간 (방장 → 손님). 통나무 · 빠짐은 따로 알림
func _net_state() -> Dictionary:
	return {"el": _elapsed, "r": _roll, "p": _pitch}


func _net_apply(st: Dictionary) -> void:
	_elapsed = float(st.get("el", _elapsed))
	_net_r = float(st.get("r", _net_r))
	_net_p = float(st.get("p", _net_p))


func _score_text(p: Dictionary) -> String:
	var s := int(p["slot"])
	if walkers.has(s) and walkers[s]["out"]:
		return "✕"
	return tr("Aboard")
