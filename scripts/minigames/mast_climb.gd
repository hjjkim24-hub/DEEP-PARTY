extends "res://scripts/minigames/minigame_3d.gd"
## 돛대 오르기 (A/D 또는 ←/→ 번갈아): 나란히 선 돛대 네 개, 각자 줄사다리를 타고 꼭대기 깃발까지.
## 두 키를 번갈아 누를 때마다 한 칸씩 올라감. 같은 키를 두 번 누르면 발이 미끄러져 살짝 내려옴.
## 갈매기 떼가 옆으로 가로질러 날아옴 → 지나갈 높이에 붉은 띠가 먼저 깔림. 그 높이에 있다 부딪히면 쭉 미끄러져 내려옴.
## 꼭대기 깃발을 먼저 잡은 순서대로 순위 (시간이 다 되면 높이 올라간 순).

const TOP := 11.6               ## 깃발을 잡는 높이 (발 기준)
const STEP := 0.17
const SLIP := 0.14
const LANE_GAP := 3.8
const GULL_HIT := 0.8           ## 갈매기 높이 ± 이 안이면 부딪힘
const KNOCK := 2.4

var _lanes := {}                ## slot → {x, h, shown, last, stun, done, time, pawn, flag, flagmat, ladder_y, sway}
var _elapsed := 0.0
var _gulls_fly: Array = []      ## {id, h, dir, speed, t0, node, wl, wr, band, hit{}}
var _gull_t := 2.5
var _next_gull := 0
var _ai := {}
var _done_n := 0


func _init() -> void:
	title = "MAST CLIMB"
	how_to = "Race up the rope ladder to the flag at the top of the mast! Press the two keys one after the other to climb - pressing the same key twice makes you slip. Seagulls swoop across at the height marked in red: don't be there when they pass!"
	goal = "Grab the flag first!"
	controls = "ALT_KEYS"
	duration = 30.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	env.fog_light_color = Color(0.66, 0.78, 0.88)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	ocean(-3.0, 260.0)
	sky_clouds(16, 200.0, 36.0)
	# 돛대 꼭대기 깃발까지 화면에 다 들어오게
	cam.fov = 44.0
	cam.position = Vector3(0, 6.8, 24.5)
	cam.look_at(Vector3(0, 7.3, 0))
	_build_ship()
	gulls(5, Vector3(0, 0, -30), 18.0, 16.0, 8)
	island(Vector3(-110, -3.5, -230), 24.0, 16.0, 5)
	var sb := sailboat(Color(0.9, 0.88, 0.8), world3)
	sb.scale = Vector3.ONE * 7.0
	sb.position = Vector3(80, -3.4, -170)
	sb.rotation.y = 2.6


func _build_ship() -> void:
	var cols := [Color(0.46, 0.34, 0.23), Color(0.5, 0.37, 0.25), Color(0.42, 0.31, 0.21)]
	# 갑판 널 · 뱃전 · 선체
	for k in 8:
		box(Vector3(24.0, 0.2, 0.74), wood_mat(cols[k % 3], Vector3(1, 0, 0), 0.05), Vector3(0, -0.1, -2.6 + k * 0.76))
	var hull := wood_mat(Color(0.3, 0.19, 0.12), Vector3(1, 0, 0), 0.2)
	var rail := wood_mat(Color(0.5, 0.35, 0.22), Vector3(1, 0, 0), 0.05)
	box(Vector3(24.0, 3.4, 0.4), hull, Vector3(0, -1.6, 3.4))
	box(Vector3(24.0, 0.8, 0.22), hull, Vector3(0, 0.4, 3.3))
	box(Vector3(24.4, 0.14, 0.42), rail, Vector3(0, 0.86, 3.3))
	for k in 13:
		box(Vector3(0.18, 0.9, 0.18), rail, Vector3(-12.0 + k * 2.0, 0.45, 3.2))
	box(Vector3(24.0, 0.18, 0.3), std_mat(Color(0.07, 0.06, 0.06), 0.6), Vector3(0, -0.5, 3.62))
	deck_clutter(world3, [Vector3(-10.6, 0, 1.2), Vector3(10.4, 0, 1.0), Vector3(-9.8, 0, -1.6), Vector3(9.9, 0, -1.8)], 23)


## 돛대 + 줄사다리 + 접힌 돛 + 꼭대기 깃발
func _mast(x: float, col: Color) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(x, 0, 0)
	world3.add_child(root)
	var wood := wood_mat(Color(0.47, 0.32, 0.19), Vector3(0, 1, 0), 0.08)
	var iron := std_mat(Color(0.18, 0.17, 0.16), 0.45, 0.7)
	var m := CylinderMesh.new()
	m.top_radius = 0.15
	m.bottom_radius = 0.26
	m.height = TOP + 2.2
	m.radial_segments = 16
	add_mesh(m, wood, Vector3(0, (TOP + 2.2) * 0.5, -0.1), Basis(), root)
	for k in 6:
		var band := CylinderMesh.new()
		var r := lerpf(0.27, 0.16, (k * 2.2 + 0.5) / (TOP + 2.2))
		band.top_radius = r
		band.bottom_radius = r
		band.height = 0.08
		add_mesh(band, iron, Vector3(0, k * 2.2 + 0.5, -0.1), Basis(), root)
	# 가로 활대 + 둘둘 말아 묶은 돛 (두 군데)
	var sail := std_mat(Color(0.86, 0.82, 0.7), 0.95)
	var rope := std_mat(Color(0.6, 0.49, 0.32), 0.95)
	for y: float in [4.6, 8.8]:
		var yard := CylinderMesh.new()
		yard.top_radius = 0.07
		yard.bottom_radius = 0.07
		yard.height = 3.0
		add_mesh(yard, wood, Vector3(0, y, -0.32), Basis(Vector3.BACK, PI / 2), root)
		var furl := CylinderMesh.new()
		furl.top_radius = 0.16
		furl.bottom_radius = 0.16
		furl.height = 2.7
		add_mesh(furl, sail, Vector3(0, y - 0.18, -0.36), Basis(Vector3.BACK, PI / 2), root)
		for k in 5:
			var tie := TorusMesh.new()
			tie.inner_radius = 0.15
			tie.outer_radius = 0.19
			add_mesh(tie, rope, Vector3(-1.1 + k * 0.55, y - 0.18, -0.36), Basis(Vector3.BACK, PI / 2), root)
	# 망대 (꼭대기 아래 작은 발판)
	var top := CylinderMesh.new()
	top.top_radius = 0.7
	top.bottom_radius = 0.6
	top.height = 0.14
	add_mesh(top, wood, Vector3(0, TOP + 0.3, -0.1), Basis(), root)
	# 줄사다리: 양쪽 밧줄 + 가로대 (돛대 앞)
	var lad := std_mat(Color(0.66, 0.54, 0.36), 0.95)
	for sx: float in [-0.34, 0.34]:
		var r := CylinderMesh.new()
		r.top_radius = 0.025
		r.bottom_radius = 0.025
		r.height = TOP + 0.6
		r.radial_segments = 6
		add_mesh(r, lad, Vector3(sx, (TOP + 0.6) * 0.5, 0.28), Basis(Vector3.RIGHT, -0.02), root)
	var y := 0.35
	while y < TOP + 0.3:
		var rung := CylinderMesh.new()
		rung.top_radius = 0.022
		rung.bottom_radius = 0.022
		rung.height = 0.7
		rung.radial_segments = 6
		add_mesh(rung, lad, Vector3(0, y, 0.28 + y * 0.0003), Basis(Vector3.BACK, PI / 2), root)
		y += 0.38
	# 깃발: 깃대 + 펄럭이는 천 (처음엔 해골 흑기, 잡으면 그 사람 색)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.05
	pole.height = 1.4
	add_mesh(pole, wood, Vector3(0, TOP + 2.9, -0.1), Basis(), root)
	var flag := Node3D.new()
	flag.position = Vector3(0.05, TOP + 3.25, -0.1)
	root.add_child(flag)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.08, 0.09)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.roughness = 0.9
	var segs := []
	for k in 6:
		var q := QuadMesh.new()
		q.size = Vector2(0.2, 0.62)
		var mi := add_mesh(q, fm, Vector3(0.1 + k * 0.2, 0, 0), Basis(), flag)
		segs.append(mi)
	# 해골 표시 (흰 점 두 개 + 턱)
	var bone := std_mat(Color(0.92, 0.9, 0.84), 0.8)
	var skull := SphereMesh.new()
	skull.radius = 0.1
	skull.height = 0.18
	var sk := add_mesh(skull, bone, Vector3(0.6, 0.04, 0.012), Basis(), flag)
	sk.scale = Vector3(1, 1, 0.15)
	return {"root": root, "flag": flag, "fm": fm, "segs": segs, "skull": sk}


func _setup_game() -> void:
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var x := (float(i) - (n - 1) * 0.5) * LANE_GAP
		var mast := _mast(x, p["color"])
		var pawn := make_pawn(p)
		pawn.rotation.y = PI
		pawn.position = Vector3(x, 0.0, 0.62)
		_lanes[s] = {"x": x, "h": 0.0, "shown": 0.0, "last": -1, "stun": 0.0, "done": false, "time": 0.0, "pawn": pawn,
			"mast": mast, "pulse": 0.0, "slip": 0.0}
		_ai[s] = {"next": rng.randf_range(0.2, 0.5), "hold": 0.0}
		scores[s] = 0.0


func _start_game() -> void:
	_elapsed = 0.0
	_gull_t = 2.6


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var side := -1
	match k.physical_keycode:
		KEY_A, KEY_LEFT:
			side = 0
		KEY_D, KEY_RIGHT:
			side = 1
	if side >= 0:
		net_input("step", [side])


func _net_input(slot: int, action: String, args: Array) -> void:
	if action == "step" and playing and args.size() > 0:
		_step(slot, int(args[0]))


## 방장: 한 발. 번갈아 누르면 위로, 같은 키 두 번이면 미끄러짐
func _step(s: int, side: int) -> void:
	var L: Dictionary = _lanes.get(s, {})
	if L.is_empty() or L["done"] or float(L["stun"]) > 0.0:
		return
	if int(L["last"]) == side:
		L["h"] = maxf(0.0, float(L["h"]) - SLIP)
		L["stun"] = 0.22
		net_call("_slip_fx", [s])
	else:
		L["h"] = float(L["h"]) + STEP
		L["pulse"] = 1.0
		if float(L["h"]) >= TOP:
			L["h"] = TOP
			net_call("_finish", [s, _elapsed])
	L["last"] = side


func _slip_fx(s: int) -> void:
	var L: Dictionary = _lanes[s]
	L["slip"] = 0.3
	if player_by_slot(s).has("slot") and is_local(player_by_slot(s)):
		sfx("thud", 80)


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	var pr := pressure()
	if not is_client():
		_think(delta)
		_gull_t -= delta
		if _gull_t <= 0.0:
			_spawn_gull(pr)
			_gull_t = lerpf(3.6, 2.0, pr) * rng.randf_range(0.85, 1.15)
		for s in _lanes:
			var L: Dictionary = _lanes[s]
			L["stun"] = maxf(0.0, float(L["stun"]) - delta)
			scores[s] = float(L["h"])
	_update_gulls(delta)
	_place(delta)


## 말 · 깃발 모습
func _place(delta: float) -> void:
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		var pawn: Node3D = L["pawn"]
		L["shown"] = lerpf(float(L["shown"]), float(L["h"]), clampf(delta * 14.0, 0.0, 1.0))
		L["pulse"] = maxf(0.0, float(L["pulse"]) - delta * 6.0)
		L["slip"] = maxf(0.0, float(L["slip"]) - delta)
		var h: float = L["shown"]
		var x: float = L["x"]
		if L["done"]:
			# 망대 위에서 깃발 흔들며 방방
			pawn.position = Vector3(x, TOP + 0.38 + absf(sin(_t3 * 6.0)) * 0.25, 0.1)
			pawn.rotation = Vector3(0, PI + sin(_t3 * 3.0) * 0.5, 0)
		else:
			# 사다리에 매달림: 한 발마다 좌우로 몸이 기울고 살짝 위로
			var sway := sin(float(L["shown"]) / STEP * PI) * 0.16
			pawn.position = Vector3(x + sway * 0.4, h + float(L["pulse"]) * 0.05, 0.6)
			pawn.rotation = Vector3(-0.12 - float(L["slip"]) * 0.8, PI, sway + (sin(_t3 * 30.0) * 0.1 if float(L["stun"]) > 0.3 else 0.0))
		# 깃발 펄럭임
		var mast: Dictionary = L["mast"]
		var segs: Array = mast["segs"]
		for k in segs.size():
			var seg: Node3D = segs[k]
			seg.position.z = sin(_t3 * 5.0 - k * 0.8 + s) * 0.06 * k
			seg.rotation.y = cos(_t3 * 5.0 - k * 0.8 + s) * 0.35


## 방장: 갈매기 한 마리 (옆에서 가로질러 날아옴)
func _spawn_gull(pr: float) -> void:
	var dir := 1.0 if rng.randf() < 0.5 else -1.0
	# 가장 높이 올라간 사람 근처를 더 자주 노림
	var lead := 0.0
	for s in _lanes:
		if not _lanes[s]["done"]:
			lead = maxf(lead, float(_lanes[s]["h"]))
	var gh := clampf(lead + rng.randf_range(1.0, 3.0), 2.0, TOP - 0.8) if rng.randf() < 0.4 else rng.randf_range(2.0, TOP - 0.8)
	_next_gull += 1
	# 띠가 먼저 깔리고 1초 뒤에 갈매기가 화면 밖에서 날아 들어옴
	net_call("_gull_go", [_next_gull, gh, dir, lerpf(10.0, 13.5, pr), _elapsed + 1.0])


func _gull_go(id: int, gh: float, dir: float, speed: float, t0: float) -> void:
	var n := Node3D.new()
	world3.add_child(n)
	var white := std_mat(Color(0.95, 0.95, 0.93), 0.7)
	var grey := std_mat(Color(0.5, 0.52, 0.56), 0.7)
	var beak := std_mat(Color(0.95, 0.7, 0.2), 0.5)
	var body := SphereMesh.new()
	body.radius = 0.12
	body.height = 0.24
	add_mesh(body, white, Vector3.ZERO, Basis(), n).scale = Vector3(1.0, 0.9, 2.6)
	var bk := CylinderMesh.new()
	bk.top_radius = 0.0
	bk.bottom_radius = 0.035
	bk.height = 0.12
	add_mesh(bk, beak, Vector3(0, 0.02, -0.36), Basis(Vector3(1, 0, 0), -PI / 2), n)
	var eye := std_mat(Color(0.02, 0.02, 0.02), 0.3)
	var em := SphereMesh.new()
	em.radius = 0.02
	em.height = 0.04
	for sx: float in [-0.07, 0.07]:
		add_mesh(em, eye, Vector3(sx, 0.05, -0.24), Basis(), n)
	var wl := Node3D.new()
	var wr := Node3D.new()
	n.add_child(wl)
	n.add_child(wr)
	box(Vector3(0.7, 0.02, 0.2), white, Vector3(-0.36, 0, 0), Basis(), wl)
	box(Vector3(0.28, 0.021, 0.14), grey, Vector3(-0.62, 0, 0.02), Basis(), wl)
	box(Vector3(0.7, 0.02, 0.2), white, Vector3(0.36, 0, 0), Basis(), wr)
	box(Vector3(0.28, 0.021, 0.14), grey, Vector3(0.62, 0, 0.02), Basis(), wr)
	n.scale = Vector3.ONE * 2.2
	# 부리가 나는 쪽 + 몸을 카메라 쪽으로 기울여 날개가 보이게 (옆에서 보면 날개가 판자처럼 보여서)
	var pivot := Node3D.new()
	world3.add_child(pivot)
	n.reparent(pivot, false)
	pivot.rotation.y = -dir * PI / 2
	n.rotation.z = 0.75 * dir
	n.rotation.x = 0.15
	# 지나갈 높이에 붉은 띠 (돛대 앞을 가로지름, 깜빡)
	var band := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(LANE_GAP * 4.2, GULL_HIT * 2.0)
	band.mesh = q
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0, 0)
	g.fill_to = Vector2(0, 1)
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.15, 0.1, 0.0))
	gr.set_color(1, Color(1.0, 0.15, 0.1, 0.0))
	gr.add_point(0.5, Color(1.0, 0.2, 0.12, 0.42))
	g.gradient = gr
	bm.albedo_texture = g
	band.material_override = bm
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.position = Vector3(0, gh + 0.55, 1.0)
	world3.add_child(band)
	# 띠 끝 화살표 (어느 쪽에서 오는지)
	var arrow := outlined_3d("◀◀" if dir < 0 else "▶▶", Color(1.0, 0.35, 0.25))
	arrow.position = Vector3(-dir * LANE_GAP * 2.25, gh + 0.55, 1.1)
	world3.add_child(arrow)
	_gulls_fly.append({"id": id, "h": gh, "dir": dir, "speed": speed, "t0": t0, "node": pivot, "wl": wl, "wr": wr,
		"band": band, "arrow": arrow, "hit": {}})
	sfx("gull", 150)


func outlined_3d(text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Color(0.1, 0.02, 0.02)
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


func _update_gulls(_delta: float) -> void:
	var start_x := LANE_GAP * 2.0 + 5.0
	for g in _gulls_fly.duplicate():
		var t := _elapsed - float(g["t0"])
		var dir := float(g["dir"])
		var gx := -dir * start_x + dir * float(g["speed"]) * t
		var n: Node3D = g["node"]
		var gh := float(g["h"])
		n.visible = t >= 0.0
		n.position = Vector3(gx, gh + 0.55 + sin(t * 7.0) * 0.12, 0.9)
		var flap := sin(t * 16.0) * 0.6 + 0.1
		(g["wl"] as Node3D).rotation.z = flap
		(g["wr"] as Node3D).rotation.z = -flap
		var band: MeshInstance3D = g["band"]
		(band.material_override as StandardMaterial3D).albedo_color.a = 0.65 + 0.35 * sin(_elapsed * 14.0)
		if absf(gx) > start_x + 0.5 and t > 0.3:
			_gulls_fly.erase(g)
			n.queue_free()
			band.queue_free()
			(g["arrow"] as Node).queue_free()
			continue
		# 이미 지나간 줄의 띠 부분은 흐리게 → 남은 쪽만 경고
		if is_client():
			continue
		var hit: Dictionary = g["hit"]
		for s in _lanes:
			var L: Dictionary = _lanes[s]
			if hit.has(s) or L["done"]:
				continue
			if absf(gx - float(L["x"])) < 0.6 and absf(float(L["h"]) + 0.55 - (gh + 0.55)) < GULL_HIT and float(L["h"]) > 0.3:
				hit[s] = true
				L["h"] = maxf(0.0, float(L["h"]) - KNOCK)
				L["stun"] = 0.8
				L["last"] = -1
				net_call("_gull_hit", [s, Vector3(gx, gh + 0.6, 0.8)])


func _gull_hit(s: int, at: Vector3) -> void:
	var L: Dictionary = _lanes[s]
	L["slip"] = 0.8
	sfx("whoosh", 60)
	sfx("thud", 60)
	debris(at, Color(0.95, 0.95, 0.93), 16)   # 깃털
	float_at(at + Vector3(0, 0.8, 0), "-%.0fm" % KNOCK, Color(1.0, 0.5, 0.4), 40)
	if is_local(player_by_slot(s)):
		shake(0.3)


func _finish(s: int, t: float) -> void:
	var L: Dictionary = _lanes[s]
	if L["done"]:
		return
	L["done"] = true
	L["time"] = t
	L["h"] = TOP
	_done_n += 1
	var p := player_by_slot(s)
	var mast: Dictionary = L["mast"]
	(mast["fm"] as StandardMaterial3D).albedo_color = (p["color"] as Color)
	(mast["skull"] as Node3D).visible = false
	sfx("start")
	splash(Vector3(float(L["x"]), TOP + 2.6, 0.2), 30, 0.6)
	float_at(Vector3(float(L["x"]), TOP + 1.6, 0.6), tr("No.%d") % _done_n, (p["color"] as Color).lightened(0.3), 54)


# ── CPU ─────────────────────────────────────────────────────
## 실력만큼 빠르게 번갈아 누름 (가끔 같은 키 실수). 갈매기 띠가 머리 위에 있으면 실력 좋을수록 멈춰 기다림
func _think(delta: float) -> void:
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		var p := player_by_slot(s)
		if is_human(p) or L["done"]:
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p)
		a["next"] = float(a["next"]) - delta
		# 화면이 느려도(프레임이 적어도) 초당 누르는 횟수는 같게: 밀린 만큼 여러 번
		var guard := 0
		while float(a["next"]) <= 0.0 and guard < 6 and not L["done"]:
			guard += 1
			_cpu_press(s, L, a, sk)


func _cpu_press(s: int, L: Dictionary, a: Dictionary, sk: float) -> void:
	if true:
		var cps := lerpf(5.6, 8.6, sk / 2.0) * (0.85 + 0.2 * sin(_t3 * 1.1 + s)) * rng.randf_range(0.85, 1.15)
		a["next"] = float(a["next"]) + 1.0 / maxf(cps, 1.0)
		# 갈매기 피하기: 곧(1.3초 안) 내 줄을 지나가는데 그때 띠 안에 있게 되면 띠 아래에서 기다림 (실력 따라 알아챔)
		var wait := false
		for g in _gulls_fly:
			var gx := -float(g["dir"]) * (LANE_GAP * 2.0 + 5.0) + float(g["dir"]) * float(g["speed"]) * (_elapsed - float(g["t0"]))
			var ahead := (float(L["x"]) - gx) * float(g["dir"])
			if ahead < -0.6:
				continue   # 이미 지나감
			var eta := ahead / float(g["speed"])
			if eta > 1.3:
				continue
			var gh := float(g["h"])
			var h := float(L["h"])
			var h_then := h + eta * cps * STEP
			if h < gh - GULL_HIT and h_then > gh - GULL_HIT - 0.2 and rng.randf() < lerpf(0.3, 0.95, sk / 2.0):
				wait = true
		if wait:
			a["next"] = maxf(float(a["next"]), 0.12)
			return
		var side := 1 - maxi(int(L["last"]), 0)
		if rng.randf() < lerpf(0.1, 0.02, sk / 2.0):
			side = maxi(int(L["last"]), 0)   # 실수
		_step(s, side)


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	for s in _lanes:
		if not _lanes[s]["done"]:
			return false
	return true


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	var key := func(p: Dictionary) -> float:
		var L: Dictionary = _lanes[int(p["slot"])]
		if L["done"]:
			return 1000.0 - float(L["time"])
		return float(L["h"])
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 줄마다 높이 · 기절 (방장 → 손님)
func _net_state() -> Dictionary:
	var hs := {}
	for s in _lanes:
		hs[s] = [float(_lanes[s]["h"]), float(_lanes[s]["stun"])]
	return {"hs": hs, "el": _elapsed}


func _net_apply(st: Dictionary) -> void:
	var hs: Dictionary = st.get("hs", {})
	for s in hs:
		if _lanes.has(int(s)):
			var L: Dictionary = _lanes[int(s)]
			var v: Array = hs[s]
			if float(v[0]) > float(L["h"]) + 0.05:
				L["pulse"] = 1.0
			L["h"] = float(v[0])
			L["stun"] = float(v[1])
	_elapsed = float(st.get("el", _elapsed))


func _score_text(p: Dictionary) -> String:
	var L: Dictionary = _lanes[int(p["slot"])]
	if L["done"]:
		return "%.1fs" % float(L["time"])
	return "%dm" % int(round(float(L["h"])))
