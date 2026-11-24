extends "res://scripts/minigames/minigame_3d.gd"
## 물대포 싸움 (WASD 이동 · 마우스 조준 · 왼쪽 버튼 꾹 = 발사 · 스페이스 연타 = 펌프):
## 난간 없는 네모난 짐배 위, 다들 등에 물통을 메고 손에 놋쇠 물대포를 들었어요.
## 스페이스를 연타해 물통을 채우고, 마우스로 겨눠 물줄기를 쏘면 맞은 사람이 쭉 밀려나요. 배 밖으로 밀려나면 풍덩(탈락).
## 걸어서는 가장자리 밖으로 안 나감 (밀려야만 떨어짐). 마지막까지 배 위에 남은 사람이 승리.

const HX := 7.0                 ## 배 반 너비 (좌우)
const HZ := 5.0                 ## 배 반 길이 (앞뒤)
const RANGE := 6.2              ## 물줄기 길이
const DRAIN := 0.32             ## 쏘는 동안 초당 줄어드는 물
const PUMP := 0.085             ## 펌프 한 번에 차는 물
const PUSH := 3.3               ## 가까이서 맞을 때 밀리는 세기 (걸어서 버틸 수는 있게)

var _deck: Node3D
var _tank := {}                 ## slot → 0..1
var _aim := {}                  ## slot → 겨눈 방향 (각도)
var _spray := {}                ## slot → 쏘는 중인지 (물이 있을 때만 실제로 나감)
var _guns := {}                 ## slot → {gun, jet, gauge, fill}
var _hit_cd := {}               ## "a_b" → 다음 밀기까지
var _fx_cd := {}                ## slot → 다음 물보라까지 (보여주기)
var _stagger := {}              ## slot → 남은 시간 (물줄기를 얼굴에 맞아 휘청: 그동안 못 쏨)
var _out_at := {}
var _order := 0
var _wait := 0.0
var _ai := {}
var _aim_send := 0.0
var _was_spray := false
var _jet_mat: StandardMaterial3D


func _init() -> void:
	title = "WATER CANNON"
	how_to = "Everyone has a brass water cannon and a tank on their back! Mash SPACE to pump water, aim with the mouse and hold the left button to spray. Blast the others off the barge - last one aboard wins!"
	goal = "Spray everyone overboard!"
	controls = "KEYS_MOUSE"
	duration = 45.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	var sea := ocean(-0.6, 180.0, 9.0)
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.55)
	sky_clouds(10, 170.0, 26.0)
	cam.fov = 46.0
	cam.position = Vector3(0, 13.6, 11.4)
	cam.look_at(Vector3(0, 0, 0.7))
	_deck = Node3D.new()
	world3.add_child(_deck)
	_build_barge()
	sea_debris(8, 11.0, 18.0, -0.5, 14)
	gulls(4, Vector3(0, 0, -16), 13.0, 6.0, 9)
	island(Vector3(80, -1.5, -160), 20.0, 13.0, 7)
	_jet_mat = StandardMaterial3D.new()
	_jet_mat.albedo_color = Color(0.62, 0.86, 1.0, 0.55)
	_jet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_jet_mat.roughness = 0.05
	_jet_mat.metallic_specular = 1.0
	_jet_mat.emission_enabled = true
	_jet_mat.emission = Color(0.35, 0.6, 0.75)
	_jet_mat.emission_energy_multiplier = 0.3


## 난간 없는 네모 짐배: 널빤지 갑판 + 가장자리 각목 테 + 물에 반쯤 잠긴 뜬 통 + 잡동사니
func _build_barge() -> void:
	var cols := [Color(0.5, 0.38, 0.26), Color(0.55, 0.42, 0.29), Color(0.47, 0.35, 0.24), Color(0.52, 0.4, 0.27)]
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	var pw := 0.56
	var nz := int(HZ * 2.0 / pw)
	for k in nz:
		var z := -HZ + (k + 0.5) * pw
		box(Vector3(HX * 2.0 + rr.randf_range(-0.05, 0.05), 0.16, pw - 0.03), wood_mat(cols[k % cols.size()], Vector3(1, 0, 0), 0.08),
			Vector3(rr.randf_range(-0.04, 0.04), -0.08, z), Basis(Vector3.UP, rr.randf_range(-0.004, 0.004)), _deck)
	var beam := wood_mat(Color(0.32, 0.21, 0.13), Vector3(1, 0, 0), 0.25)
	box(Vector3(HX * 2.0 + 0.3, 0.3, 0.3), beam, Vector3(0, -0.2, -HZ), Basis(), _deck)
	box(Vector3(HX * 2.0 + 0.3, 0.3, 0.3), beam, Vector3(0, -0.2, HZ), Basis(), _deck)
	box(Vector3(0.3, 0.3, HZ * 2.0), wood_mat(Color(0.32, 0.21, 0.13), Vector3(0, 0, 1), 0.25), Vector3(-HX, -0.2, 0), Basis(), _deck)
	box(Vector3(0.3, 0.3, HZ * 2.0), wood_mat(Color(0.32, 0.21, 0.13), Vector3(0, 0, 1), 0.25), Vector3(HX, -0.2, 0), Basis(), _deck)
	box(Vector3(HX * 2.0 - 0.4, 0.5, HZ * 2.0 - 0.4), std_mat(Color(0.12, 0.08, 0.05), 0.9), Vector3(0, -0.5, 0), Basis(), _deck)
	# 아래에 뜬 통 (물 위로 조금 보임)
	for x: float in [-HX + 0.8, -HX * 0.33, HX * 0.33, HX - 0.8]:
		for z: float in [-HZ + 0.4, HZ - 0.4]:
			var b := barrel(_deck, Vector3(x, -0.6, z), 0.42, 1.0, Color(0.34, 0.22, 0.12))
			b.rotation = Vector3(PI / 2, 0, 0)
	# 못 · 물 웅덩이(반짝)
	var nail := std_mat(Color(0.12, 0.1, 0.09), 0.5, 0.7)
	var nm := CylinderMesh.new()
	nm.top_radius = 0.025
	nm.bottom_radius = 0.025
	nm.height = 0.02
	nm.radial_segments = 6
	for k in nz:
		for x: float in [-HX * 0.66, 0.0, HX * 0.66]:
			add_mesh(nm, nail, Vector3(x + rr.randf_range(-0.1, 0.1), 0.005, -HZ + (k + 0.5) * pw), Basis(), _deck)
	deck_clutter(_deck, [Vector3(-HX + 0.6, 0, -HZ + 0.6), Vector3(HX - 0.6, 0, HZ - 0.6)], 31)


func _setup_game() -> void:
	walk_radius = 99.0
	var spots := [Vector3(-3.2, 0, -2.0), Vector3(3.2, 0, 2.0), Vector3(3.2, 0, -2.0), Vector3(-3.2, 0, 2.0)]
	for i in players.size():
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var w := add_walker(p, spots[i % 4], 4.6)
		var to_c: Vector3 = -(spots[i % 4] as Vector3)
		w["face"] = atan2(to_c.x, to_c.z)
		_tank[s] = 0.55
		_aim[s] = float(w["face"])
		_spray[s] = false
		_ai[s] = {"t": 0.0, "goal": w["pos"], "target": -1, "pump": 0.0}
		_guns[s] = _make_gun(w["node"])
		scores[s] = 1


## 놋쇠 물대포 (손에) + 등에 멘 구리 물통 (물 높이가 유리창으로 보임) + 고무호스
func _make_gun(pawn: Node3D) -> Dictionary:
	var brass := std_mat(Color(0.85, 0.62, 0.25), 0.28, 0.9)
	var copper := std_mat(Color(0.88, 0.52, 0.3), 0.3, 0.85)
	var rubber := std_mat(Color(0.08, 0.08, 0.09), 0.7)
	var gun := Node3D.new()
	gun.position = Vector3(0.22, 0.5, 0.2)
	pawn.add_child(gun)
	var barrel_m := CylinderMesh.new()
	barrel_m.top_radius = 0.045
	barrel_m.bottom_radius = 0.07
	barrel_m.height = 0.56
	barrel_m.radial_segments = 16
	add_mesh(barrel_m, brass, Vector3(0, 0, 0.26), Basis(Vector3.RIGHT, PI / 2), gun)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.075
	add_mesh(ring, brass, Vector3(0, 0, 0.54), Basis(Vector3.RIGHT, PI / 2), gun)
	add_mesh(ring, brass, Vector3(0, 0, 0.08), Basis(Vector3.RIGHT, PI / 2), gun)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.05, 0.14, 0.06)
	add_mesh(grip, std_mat(Color(0.35, 0.22, 0.12), 0.7), Vector3(0, -0.08, 0.04), Basis(Vector3.RIGHT, -0.3), gun)
	var tank := Node3D.new()
	tank.position = Vector3(0, 0.5, -0.24)
	tank.scale = Vector3.ONE * 0.8
	pawn.add_child(tank)
	var tm := CylinderMesh.new()
	tm.top_radius = 0.13
	tm.bottom_radius = 0.13
	tm.height = 0.42
	tm.radial_segments = 18
	add_mesh(tm, copper, Vector3.ZERO, Basis(), tank)
	for y: float in [-0.18, 0.18]:
		var band := CylinderMesh.new()
		band.top_radius = 0.137
		band.bottom_radius = 0.137
		band.height = 0.03
		add_mesh(band, brass, Vector3(0, y, 0), Basis(), tank)
	var cap := SphereMesh.new()
	cap.radius = 0.13
	cap.height = 0.12
	add_mesh(cap, copper, Vector3(0, 0.21, 0), Basis(), tank)
	# 물 높이 창 (뒤쪽, 파란 물이 차오름)
	var glass := BoxMesh.new()
	glass.size = Vector3(0.06, 0.32, 0.01)
	add_mesh(glass, std_mat(Color(0.1, 0.12, 0.14), 0.2), Vector3(0, 0, -0.135), Basis(), tank)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.3, 0.75, 1.0)
	water.emission_enabled = true
	water.emission = Color(0.2, 0.6, 1.0)
	water.emission_energy_multiplier = 0.8
	var fill := Node3D.new()
	fill.position = Vector3(0, -0.15, -0.142)
	tank.add_child(fill)
	var fb := BoxMesh.new()
	fb.size = Vector3(0.045, 0.3, 0.005)
	add_mesh(fb, water, Vector3(0, 0.15, 0), Basis(), fill)
	# 호스: 물통 아래 → 물대포 손잡이 (몇 마디로 처짐)
	var a := Vector3(0.08, 0.4, -0.2)
	var b := Vector3(0.2, 0.46, 0.18)
	var prev := a
	for k in 5:
		var t := (k + 1) / 5.0
		var q := a.lerp(b, t) + Vector3(0, -sin(t * PI) * 0.1, 0)
		var d := q - prev
		var hc := CylinderMesh.new()
		hc.top_radius = 0.018
		hc.bottom_radius = 0.018
		hc.height = d.length() + 0.01
		hc.radial_segments = 6
		add_mesh(hc, rubber, (q + prev) * 0.5, Basis(Quaternion(Vector3.UP, d.normalized())), pawn)
		prev = q
	# 물줄기: 물방울 덩어리들이 총구에서 맞는 자리까지 이어져 흐름 (매 프레임 _show 에서 자리 잡음)
	var blobs := []
	var bm := SphereMesh.new()
	bm.radius = 0.1
	bm.height = 0.2
	bm.radial_segments = 10
	bm.rings = 5
	for k in 18:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _jet_mat_or_new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		world3.add_child(mi)
		blobs.append(mi)
	return {"gun": gun, "blobs": blobs, "fill": fill}


func _jet_mat_or_new() -> StandardMaterial3D:
	if _jet_mat == null:
		_jet_mat = StandardMaterial3D.new()
	return _jet_mat


func _start_game() -> void:
	pass


func _alive() -> Array:
	return walkers.keys().filter(func(s: int) -> bool: return not walkers[s]["out"])


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
		net_input("pump")
		sfx("pump", 60)


## 걸어서는 가장자리 밖으로 못 나가게 목표를 안쪽으로 (밀려야만 떨어짐)
func human_target(w: Dictionary) -> void:
	super.human_target(w)
	var t: Vector3 = w["target"]
	t.x = clampf(t.x, -HX + 0.45, HX - 0.45)
	t.z = clampf(t.z, -HZ + 0.45, HZ - 0.45)
	w["target"] = t


func _net_input(slot: int, action: String, args: Array) -> void:
	if not playing:
		return
	match action:
		"pump":
			_tank[slot] = minf(1.0, float(_tank.get(slot, 0.0)) + PUMP)
		"aim":
			if args.size() >= 2:
				_aim[slot] = float(args[0])
				_spray[slot] = bool(args[1])


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_t3 += delta
	var pr := pressure()
	_local_aim(delta)
	if not is_client():
		_think(delta)
	# 쏘는 동안은 느리게 걸음
	for s in walkers:
		walkers[s]["speed"] = 2.8 if bool(_spray.get(s, false)) and float(_tank.get(s, 0.0)) > 0.0 else 4.6
	step_walkers(delta)
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w["out"]:
			continue
		# 쏘거나 겨누는 쪽을 봄
		if bool(_spray.get(s, false)) or is_local(w["p"]):
			w["face"] = lerp_angle(float(w["face"]), float(_aim.get(s, w["face"])), clampf(delta * 14.0, 0.0, 1.0))
			(w["node"] as Node3D).rotation.y = float(w["face"])
	if not is_client():
		_sprays(delta, pr)
		_check_falls()
	_show(delta)
	if _wait > 0.0:
		_wait -= delta


## 내 물대포: 마우스 쪽으로 겨눔, 왼쪽 버튼 누르는 동안 발사 (방장에게 알림)
func _local_aim(delta: float) -> void:
	var s := local_slot()
	if not walkers.has(s) or walkers[s]["out"] or demo:
		return
	var w: Dictionary = walkers[s]
	if not is_local(w["p"]):
		return
	var mg := mouse_ground(0.5)
	var d: Vector3 = mg - (w["pos"] as Vector3)
	var yaw := float(_aim.get(s, 0.0))
	if Vector2(d.x, d.z).length() > 0.2:
		yaw = atan2(d.x, d.z)
	var on := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_aim[s] = yaw
	_spray[s] = on
	_aim_send -= delta
	if on != _was_spray or _aim_send <= 0.0:
		_aim_send = 0.08
		_was_spray = on
		net_input("aim", [yaw, on])


## 방장: 물줄기 판정. 겨눈 쪽으로 가장 먼저 닿는 사람을 밀어냄 (가까울수록 세게), 쏘는 사람은 살짝 뒤로 밀림
func _sprays(delta: float, pr: float) -> void:
	for k in _hit_cd.keys():
		_hit_cd[k] = float(_hit_cd[k]) - delta
	for k in _stagger.keys():
		_stagger[k] = float(_stagger[k]) - delta
	for s in _alive():
		var on := bool(_spray.get(s, false)) and float(_tank[s]) > 0.0 and float(_stagger.get(s, 0.0)) <= 0.0
		if not on:
			continue
		_tank[s] = maxf(0.0, float(_tank[s]) - DRAIN * delta)
		var w: Dictionary = walkers[s]
		var yaw := float(_aim[s])
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var from: Vector3 = (w["pos"] as Vector3) + dir * 0.5
		var best := -1
		var best_along := RANGE
		for o in _alive():
			if o == s:
				continue
			var rel: Vector3 = (walkers[o]["pos"] as Vector3) - from
			rel.y = 0.0
			var along := rel.dot(dir)
			if along < 0.0 or along > RANGE:
				continue
			var lat := (rel - dir * along).length()
			if lat < 0.7 + along * 0.08 and along < best_along:   # 물줄기는 멀수록 퍼짐
				best_along = along
				best = o
		if best < 0:
			continue
		var key := "%d_%d" % [s, best]
		if float(_hit_cd.get(key, 0.0)) > 0.0:
			continue
		_hit_cd[key] = 0.09
		var f := lerpf(PUSH, PUSH * 0.45, best_along / RANGE) * lerpf(1.0, 1.25, pr)
		net_push(best, dir * f, 0.15)   # 물줄기 속에선 걸음도 느려짐
		# 정면으로 맞으면 휘청해서 잠깐 못 쏨 → 먼저 맞힌 사람이 유리
		var facing := Vector3(sin(float(_aim.get(best, 0.0))), 0, cos(float(_aim.get(best, 0.0))))
		if facing.dot(-dir) > 0.3:
			_stagger[best] = 0.2


func _check_falls() -> void:
	for s in _alive():
		var pos: Vector3 = walkers[s]["pos"]
		if absf(pos.x) > HX + 0.15 or absf(pos.z) > HZ + 0.15:
			net_call("_fall", [s, pos])


func _fall(s: int, at: Vector3) -> void:
	var w: Dictionary = walkers[s]
	if w["out"]:
		return
	w["out"] = true
	if OS.get_environment("MG_DEBUG") != "":
		print("MGFALL slot %d t=%.1f" % [s, duration - time_left])
	_out_at[s] = _order
	_order += 1
	scores[s] = 0
	_spray[s] = false
	_wait = 1.6
	var n: Node3D = w["node"]
	var out_dir := Vector3(signf(at.x) if absf(at.x) / HX > absf(at.z) / HZ else 0.0, 0, signf(at.z) if absf(at.z) / HZ >= absf(at.x) / HX else 0.0)
	var from := at
	var to := at + out_dir * 1.6 + Vector3(0, -1.0, 0)
	sfx("whoosh")
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void:
		n.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 1.1, 0)
		n.rotation = Vector3(f * 2.0, float(w["face"]), sin(f * 8.0) * 0.4), 0.0, 1.0, 0.55)
	tw.tween_callback(func() -> void:
		splash(n.global_position + Vector3(0, 0.4, 0), 45, 1.0)
		sfx("splash")
		n.rotation = Vector3(0.9, rng.randf() * TAU, 0.3)
		var bob := create_tween().set_loops()
		bob.tween_property(n, "position:y", -0.8, 0.9).set_trans(Tween.TRANS_SINE)
		bob.tween_property(n, "position:y", -1.05, 0.9).set_trans(Tween.TRANS_SINE))
	float_at(at + Vector3(0, 2.4, 0), tr("SPLASH!"), Color(0.6, 0.9, 1.0), 44)


## 보여주기 (모든 PC): 물줄기 · 맞은 자리 물보라 · 등 물통 눈금 · 쏘는 소리
func _show(delta: float) -> void:
	for s in _guns:
		var g: Dictionary = _guns[s]
		var w: Dictionary = walkers[s]
		var on: bool = bool(_spray.get(s, false)) and float(_tank.get(s, 0.0)) > 0.0 and not w["out"]
		(g["fill"] as Node3D).scale = Vector3(1, maxf(0.02, float(_tank.get(s, 0.0))), 1)
		var blobs: Array = g["blobs"]
		if not on:
			for b in blobs:
				(b as Node3D).visible = false
			continue
		if is_local(w["p"]) or demo:
			sfx("spray", 520)
		# 물줄기가 닿는 곳: 겨눈 쪽으로 가장 먼저 맞는 사람 (없으면 최대 거리, 바다/갑판에 떨어짐)
		var yaw := float(_aim.get(s, 0.0))
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var nozzle: Vector3 = (g["gun"] as Node3D).global_transform * Vector3(0, 0, 0.58)
		var from: Vector3 = (w["pos"] as Vector3) + dir * 0.5
		var best := RANGE
		var hit_at: Vector3 = (w["pos"] as Vector3) + dir * (RANGE + 0.5)
		hit_at.y = 0.05
		for o in walkers:
			if o == s or walkers[o]["out"]:
				continue
			var rel: Vector3 = (walkers[o]["pos"] as Vector3) - from
			rel.y = 0.0
			var along := rel.dot(dir)
			if along > 0.0 and along < best and (rel - dir * along).length() < 0.7 + along * 0.08:
				best = along
				hit_at = (walkers[o]["pos"] as Vector3) + Vector3(0, 0.75, 0) - dir * 0.3
		# 물방울 덩어리: 총구 → 맞는 자리, 끝으로 갈수록 굵어지고 살짝 처짐 (흐르는 것처럼 앞으로 밀려감)
		var n := blobs.size()
		var sag := 0.35 if best < RANGE else 0.0
		for k in n:
			var t := fmod(float(k) / n + _t3 * 2.6, 1.0)
			var p := nozzle.lerp(hit_at, t)
			p.y -= sin(t * PI) * sag + (t * t * 0.4 if best >= RANGE else 0.0)
			p += Vector3(sin(_t3 * 31.0 + k * 1.7), cos(_t3 * 27.0 + k * 2.3), 0) * 0.04 * t
			var b: MeshInstance3D = blobs[k]
			b.visible = true
			b.global_position = p
			var sc := lerpf(0.55, 1.5, t)
			b.scale = Vector3(sc, sc, sc * 1.8)
			b.look_at(p + dir + Vector3(0, 0.001, 0), Vector3.UP)
		_fx_cd[s] = float(_fx_cd.get(s, 0.0)) - delta
		if float(_fx_cd[s]) <= 0.0:
			_fx_cd[s] = 0.1
			splash(hit_at, 7, 0.4)


# ── CPU ─────────────────────────────────────────────────────
## 물이 적으면 가운데로 물러나 펌프질, 물이 있으면 상대가 가장자리 쪽으로 밀리게 반대편에서 겨눠 쏨.
## 물줄기에 맞고 있으면 옆으로 빠져나옴. 실력이 좋을수록 정확히 겨누고 펌프도 빠름
func _think(delta: float) -> void:
	for s in _alive():
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p)
		var pos: Vector3 = w["pos"]
		# 펌프 연타
		var tank := float(_tank[s])
		var want_pump := tank < lerpf(0.3, 0.45, sk / 2.0) or (tank < 0.9 and not bool(_spray[s]))
		if want_pump:
			a["pump"] = float(a["pump"]) - delta
			var guard := 0
			while float(a["pump"]) <= 0.0 and guard < 6:
				guard += 1
				a["pump"] = float(a["pump"]) + 1.0 / (lerpf(4.5, 8.0, sk / 2.0) * rng.randf_range(0.85, 1.15))
				_tank[s] = minf(1.0, float(_tank[s]) + PUMP)
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.4, 0.15, sk / 2.0) + rng.randf_range(0.0, 0.12)
			var best := -1
			var bv := INF
			for o in _alive():
				if o == s:
					continue
				var op: Vector3 = walkers[o]["pos"]
				# 가장자리에 가까운 상대 + 가까운 상대를 노림
				var edge := minf(HX - absf(op.x), HZ - absf(op.z))
				var v := op.distance_to(pos) * 0.6 + edge * 1.2
				if v < bv:
					bv = v
					best = o
			a["target"] = best
			var goal := pos
			if best >= 0:
				var tp: Vector3 = walkers[best]["pos"]
				# 상대보다 가운데 쪽에 3.4 m 떨어져 섬 (그래야 쏘면 상대가 가장자리로 밀림).
				# 지금 있는 쪽을 유지해서 서로 엇갈려 지나가지 않게
				var away := pos - tp
				away.y = 0.0
				away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
				var cen := -tp
				cen.y = 0.0
				cen = cen.normalized() if cen.length() > 0.1 else Vector3.ZERO
				var side := (away + cen * 0.8).normalized() if (away + cen * 0.8).length() > 0.05 else away
				goal = tp + side * 3.4
			if tank < 0.2:
				goal = pos.lerp(Vector3.ZERO, 0.6)
			# 내가 가장자리 쪽이면 안쪽으로
			if absf(pos.x) > HX - 1.6 or absf(pos.z) > HZ - 1.4:
				goal = pos.lerp(Vector3.ZERO, 0.7)
			goal.x = clampf(goal.x, -HX + 0.9, HX - 0.9)
			goal.z = clampf(goal.z, -HZ + 0.9, HZ - 0.9)
			a["goal"] = goal
			# 겨누기 오차 (실력이 낮을수록 크게 빗나감) — 생각할 때마다 새로 정하고, 겨누는 건 매 프레임 따라감
			a["err"] = rng.randf_range(-1.0, 1.0) * lerpf(0.2, 0.04, sk / 2.0)
		var tg := int(a["target"])
		if tg >= 0 and walkers.has(tg) and not walkers[tg]["out"]:
			var tp2: Vector3 = (walkers[tg]["pos"] as Vector3) + (walkers[tg]["vel"] as Vector3) * 0.15
			var d := tp2 - pos
			d.y = 0.0
			var want := atan2(d.x, d.z) + float(a.get("err", 0.0))
			_aim[s] = lerp_angle(float(_aim[s]), want, clampf(delta * lerpf(6.0, 14.0, sk / 2.0), 0.0, 1.0))
			_spray[s] = d.length() < RANGE - 0.4 and float(_tank[s]) > 0.05 and not (float(_tank[s]) < 0.3 and want_pump)
		else:
			_spray[s] = false
		w["target"] = a["goal"]
		if OS.get_environment("MG_DEBUG") != "" and fmod(_t3, 0.5) < delta:
			print("WCDBG t=%.1f s=%d pos=(%.1f,%.1f) tgt=%d goal=(%.1f,%.1f) aim=%.2f spray=%s" % [_t3, s, pos.x, pos.z, int(a["target"]), (a["goal"] as Vector3).x, (a["goal"] as Vector3).z, float(_aim[s]), _spray[s]])


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	return _alive().size() <= 1 and _wait <= 0.0


## 순위: 끝까지 남은 사람(가장자리에서 먼 순) → 늦게 떨어진 순
func _ranking() -> Array:
	var order := players.duplicate()
	var key := func(p: Dictionary) -> float:
		var s := int(p["slot"])
		if _out_at.has(s):
			return float(_out_at[s])
		var pos: Vector3 = walkers[s]["pos"]
		return 1000.0 + minf(HX - absf(pos.x), HZ - absf(pos.z))
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 물통 · 겨눈 방향 · 쏘는 중 (방장 → 손님)
func _net_state() -> Dictionary:
	var g := {}
	for s in _tank:
		g[s] = [float(_tank[s]), float(_aim[s]), bool(_spray[s])]
	return {"g": g}


func _net_apply(st: Dictionary) -> void:
	var g: Dictionary = st.get("g", {})
	for s in g:
		var v: Array = g[s]
		var si := int(s)
		_tank[si] = float(v[0])
		# 내 조준은 내 PC 가 정함
		if si != net_me:
			_aim[si] = float(v[1])
			_spray[si] = bool(v[2])


func _score_text(p: Dictionary) -> String:
	var s := int(p["slot"])
	if walkers.has(s) and walkers[s]["out"]:
		return "✕"
	return tr("Water %d%%") % int(round(float(_tank.get(s, 0.0)) * 100.0))
