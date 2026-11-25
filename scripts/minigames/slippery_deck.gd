extends "res://scripts/minigames/minigame_3d.gd"
## 미끄러운 갑판 레이스 (WASD + 스페이스): 꽁꽁 얼고 눈 덮인 길고 좁은 잔교(바다 위 나무 다리)를 위로 달려 결승선까지.
## 이동 = 가속만 붙고 잘 안 멈춤(관성). 스페이스 = 앞으로 확 돌진 (부딪친 사람은 튕겨 나감).
## 꼭대기에서 술통이 계속 랜덤으로 굴러 내려옴 → 맞으면 뒤로 밀려나고 잠깐 휘청. 가운데는 빙판, 가장자리는 눈 더미.
## 다리 옆으로 미끄러져 떨어지면 풍덩 → 조금 뒤에서 다시 올라옴. 결승선에 먼저 닿은 순서대로 순위.
## 화면은 각자 자기 말을 따라가요 (미리보기 · 자동 점검은 선두를 따라감).

const HALF_W := 4.8             ## 다리 반 너비 (9.6m)
const START_Z := 6.0            ## 출발선
const FINISH_Z := -86.0         ## 결승선 (길게 — 화면은 각자 내 말을 따라감)
const ACC := 10.5
const MAXV := 6.6
const DASH := 8.6
const DASH_CD := 1.4
const BUMP_R := 0.84
const BARREL_R := 0.42
## 술통: 시간과 상관없이 랜덤. 속도는 언제나 보고 피할 수 있는 범위로 고정
const BARREL_V_MIN := 4.6
const BARREL_V_MAX := 6.0
const BARREL_GAP_MIN := 0.45
const BARREL_GAP_MAX := 0.85

var _track: Node3D
var _elapsed := 0.0
var _done := {}                 ## slot → 도착 시간
var _done_n := 0
var _pair_cd := {}
var _barrels: Array = []        ## {id, x, speed, t0, node, holder, hit{}, hop}
var _barrel_t := 1.0
var _next_barrel := 0
var _ai := {}
var _cam_z := START_Z
var _skid_mat: StandardMaterial3D
var _snowfall: CPUParticles3D
var _floes: Array = []


func _init() -> void:
	title = "SLIPPERY DECK"
	how_to = "Race up the long frozen pier to the finish line! It's a sheet of ice - once you slide, it's hard to stop. Barrels keep rolling down from the top: dodge them! SPACE dashes forward and bumps others aside. Slip off the edge and you'll climb back on a little behind."
	goal = "Reach the finish line first!"
	controls = "KEYS_DASH"
	duration = 60.0


func _build_stage() -> void:
	env_sea_day()
	# 한겨울 바다: 희뿌연 하늘 · 차가운 햇빛 · 낮게 깔린 눈안개. 해는 결승선 쪽 → 빙판에 햇빛이 길게 비침
	var wsky := env.sky.sky_material as ProceduralSkyMaterial
	wsky.sky_top_color = Color(0.42, 0.55, 0.7)
	wsky.sky_horizon_color = Color(0.86, 0.9, 0.94)
	wsky.ground_horizon_color = Color(0.78, 0.84, 0.9)
	wsky.ground_bottom_color = Color(0.08, 0.14, 0.2)
	env.fog_light_color = Color(0.85, 0.89, 0.94)
	env.fog_density = 0.0075
	env.ambient_light_energy = 0.7
	sun.light_color = Color(0.92, 0.96, 1.0)
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-32, 160, 0)
	var sea := ocean(-1.9, 320.0)
	sea.position.z = (START_Z + FINISH_Z) * 0.5
	(sea.material_override as ShaderMaterial).set_shader_parameter("crest_foam", 0.55)
	sky_clouds(14, 220.0, 30.0, Vector3(0, 0, FINISH_Z * 0.5))
	cam.fov = 52.0
	_place_cam(START_Z, true)
	_track = Node3D.new()
	world3.add_child(_track)
	_build_pier()
	gulls(6, Vector3(0, 0, FINISH_Z * 0.5), 20.0, 9.0, 11)
	island(Vector3(-90, -2.4, -170), 22.0, 14.0, 6)
	island(Vector3(110, -2.4, -120), 16.0, 10.0, 2)
	_skid_mat = StandardMaterial3D.new()
	_skid_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.9)   # 미끄러질 때 튀는 눈가루 · 얼음 부스러기
	_skid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_skid_mat.roughness = 0.8


## 카메라: 내 말 뒤 위에서 앞(위쪽)을 내려다봄
func _place_cam(z: float, snap: bool = false) -> void:
	if snap:
		_cam_z = z
	var xf := Transform3D(Basis(), Vector3(0, 10.6, _cam_z + 9.6))
	xf = xf.looking_at(Vector3(0, 0, _cam_z - 5.5), Vector3.UP)
	cam_base = xf
	cam.transform = xf


## 바다 위 잔교: 가로로 깐 널빤지 · 양옆 각목 · 물속 기둥 · 가장자리 말뚝 · 출발선/결승선 · 꼭대기 술통 더미
func _build_pier() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 17
	var cols := [Color(0.5, 0.38, 0.26), Color(0.55, 0.42, 0.29), Color(0.47, 0.35, 0.24), Color(0.52, 0.4, 0.27)]
	var mats := []
	for c in cols:
		var wm := wood_mat(c, Vector3(1, 0, 0), 0.05)
		wm.set_shader_parameter("oil", 0.7)
		mats.append(wm)
	var z0 := START_Z + 3.0
	var z1 := FINISH_Z - 8.0
	var z := z0
	var k := 0
	while z > z1:
		var w := rr.randf_range(0.42, 0.5)
		box(Vector3(HALF_W * 2.0 + rr.randf_range(-0.08, 0.08), 0.16, w - 0.03), mats[k % mats.size()],
			Vector3(rr.randf_range(-0.04, 0.04), -0.08, z - w * 0.5), Basis(Vector3.UP, rr.randf_range(-0.006, 0.006)), _track)
		z -= w
		k += 1
	var beam := wood_mat(Color(0.3, 0.2, 0.12), Vector3(0, 0, 1), 0.3)
	var length := z0 - z1
	for sx: float in [-1.0, 1.0]:
		box(Vector3(0.26, 0.3, length), beam, Vector3(sx * (HALF_W + 0.05), -0.22, (z0 + z1) * 0.5), Basis(), _track)
	box(Vector3(HALF_W * 2.0 - 0.3, 0.3, length), std_mat(Color(0.1, 0.07, 0.05), 0.9), Vector3(0, -0.35, (z0 + z1) * 0.5), Basis(), _track)
	# 물속 기둥 (따개비 낀 통나무) + 가장자리 낮은 말뚝
	var pile := wood_mat(Color(0.25, 0.18, 0.12), Vector3(0, 1, 0), 0.6)
	var zz := z0 - 1.0
	while zz > z1:
		for sx: float in [-1.0, 1.0]:
			var c := CylinderMesh.new()
			c.top_radius = 0.2
			c.bottom_radius = 0.24
			c.height = 3.2
			c.radial_segments = 12
			add_mesh(c, pile, Vector3(sx * (HALF_W + 0.05), -1.8, zz), Basis(), _track)
			var b := CylinderMesh.new()
			b.top_radius = 0.1
			b.bottom_radius = 0.13
			b.height = 0.5
			add_mesh(b, pile, Vector3(sx * (HALF_W + 0.05), 0.12, zz), Basis(), _track)
		zz -= 6.0
	_winter(z0, z1)
	# 뒤쪽 막힘판 (출발선 뒤로는 못 감)
	box(Vector3(HALF_W * 2.2, 1.0, 0.3), beam, Vector3(0, 0.45, z0 - 0.15), Basis(), _track)
	# 출발선 (흰 칠) · 결승선 (체크무늬 + 아치 + 깃발 줄)
	box(Vector3(HALF_W * 2.0, 0.02, 0.18), std_mat(Color(0.95, 0.95, 0.9), 0.7), Vector3(0, 0.03, START_Z), Basis(), _track)
	var blk := std_mat(Color(0.06, 0.06, 0.06), 0.6)
	var wht := std_mat(Color(0.95, 0.95, 0.92), 0.6)
	var cells := 12
	for i in cells:
		for j in 2:
			box(Vector3(HALF_W * 2.0 / cells, 0.02, 0.3), blk if (i + j) % 2 == 0 else wht,
				Vector3(-HALF_W + (i + 0.5) * HALF_W * 2.0 / cells, 0.03, FINISH_Z + (j - 0.5) * 0.3), Basis(), _track)
	var post := wood_mat(Color(0.42, 0.28, 0.16), Vector3(0, 1, 0), 0.1)
	for sx: float in [-1.0, 1.0]:
		var p := CylinderMesh.new()
		p.top_radius = 0.14
		p.bottom_radius = 0.17
		p.height = 4.6
		add_mesh(p, post, Vector3(sx * (HALF_W + 0.35), 2.2, FINISH_Z), Basis(), _track)
	box(Vector3(HALF_W * 2.0 + 1.2, 0.5, 0.18), post, Vector3(0, 4.3, FINISH_Z), Basis(), _track)
	# 깃발 줄 (삼각 깃발이 아치에 매달림)
	var flag_cols := [Color(0.85, 0.15, 0.12), Color(0.95, 0.8, 0.2), Color(0.15, 0.45, 0.85), Color(0.95, 0.95, 0.92)]
	for i in 14:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = flag_cols[i % 4]
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tri := CylinderMesh.new()
		tri.top_radius = 0.0
		tri.bottom_radius = 0.18
		tri.height = 0.42
		tri.radial_segments = 3
		var x := -HALF_W - 0.3 + i * (HALF_W * 2.0 + 0.6) / 13.0
		var mi := add_mesh(tri, fm, Vector3(x, 3.85 - sin(float(i) / 13.0 * PI) * 0.3, FINISH_Z), Basis(Vector3.RIGHT, PI), _track)
		mi.scale = Vector3(1, 1, 0.15)
	var banner := Label3D.new()
	banner.text = tr("FINISH")
	banner.font_size = 160
	banner.pixel_size = 0.006
	banner.outline_size = 24
	banner.modulate = Color(1.0, 0.85, 0.3)
	banner.outline_modulate = Color(0.2, 0.08, 0.02)
	banner.position = Vector3(0, 4.3, FINISH_Z + 0.12)
	_track.add_child(banner)
	# 꼭대기: 술통이 쏟아져 나오는 비탈 + 쌓인 술통 더미
	var nb := int(HALF_W * 2.0)
	for i in nb:
		barrel(_track, Vector3(-HALF_W + 0.6 + i * 1.0, 0.0, FINISH_Z - 6.5), 0.4, 0.8, Color(0.4, 0.25, 0.13))
	for i in nb - 1:
		barrel(_track, Vector3(-HALF_W + 1.1 + i * 1.0, 0.8, FINISH_Z - 6.7), 0.4, 0.8, Color(0.36, 0.23, 0.12))


## 꽁꽁 언 잔교: 빙판 + 눈 (셰이더) · 가장자리 눈 더미 · 말뚝 위 눈 · 옆 각목에 매달린 고드름 · 바다 위 유빙 · 내리는 눈
func _winter(z0: float, z1: float) -> void:
	var length := z0 - z1
	var rr := RandomNumberGenerator.new()
	rr.seed = 33
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_W * 2.0 + 0.1, length - 0.3)
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/ice_snow.gdshader")
	fm.set_shader_parameter("half_w", HALF_W)
	var sheet := add_mesh(pm, fm, Vector3(0, 0.014, (z0 + z1) * 0.5), Basis(), _track)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.94, 0.96, 1.0)
	snow_mat.roughness = 0.85
	var ice_mat := StandardMaterial3D.new()
	ice_mat.albedo_color = Color(0.75, 0.9, 1.0, 0.55)
	ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice_mat.roughness = 0.04
	ice_mat.metallic_specular = 1.0
	ice_mat.rim_enabled = true
	ice_mat.rim = 0.5
	# 가장자리 눈 더미 (납작하게 뭉친 눈덩이를 길게 이어 붙임)
	var lump := SphereMesh.new()
	lump.radius = 0.5
	lump.height = 1.0
	lump.radial_segments = 18
	lump.rings = 10
	lump.material = snow_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lump
	var xs: Array = []
	var z := z0 - 0.3
	while z > z1 + 0.3:
		for sx: float in [-1.0, 1.0]:
			# 바깥 줄 (크고 길게 겹침) + 안쪽 줄 (작고 낮게) → 이어진 눈 둔덕
			var b := Basis(Vector3.UP, rr.randf_range(-0.25, 0.25)).scaled(Vector3(rr.randf_range(0.8, 1.2), rr.randf_range(0.14, 0.3), rr.randf_range(1.6, 2.6)))
			xs.append(Transform3D(b, Vector3(sx * (HALF_W - 0.2 - rr.randf_range(0.0, 0.15)), -0.02, z)))
			if rr.randf() < 0.55:
				var b2 := Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3(rr.randf_range(0.5, 0.9), rr.randf_range(0.06, 0.14), rr.randf_range(0.7, 1.4)))
				xs.append(Transform3D(b2, Vector3(sx * (HALF_W - 0.75 - rr.randf_range(0.0, 0.35)), -0.01, z + rr.randf_range(-0.4, 0.4))))
		z -= rr.randf_range(0.45, 0.8)
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_track.add_child(mmi)
	# 말뚝 위 눈 모자
	var zz := z0 - 1.0
	while zz > z1:
		for sx: float in [-1.0, 1.0]:
			var cap := SphereMesh.new()
			cap.radius = 0.15
			cap.height = 0.14
			add_mesh(cap, snow_mat, Vector3(sx * (HALF_W + 0.05), 0.39, zz), Basis(), _track)
		zz -= 6.0
	# 고드름 (옆 각목 아래로 주렁주렁)
	var icicle := CylinderMesh.new()
	icicle.top_radius = 0.045
	icicle.bottom_radius = 0.0
	icicle.height = 1.0
	icicle.radial_segments = 6
	icicle.rings = 1
	icicle.material = ice_mat
	var im := MultiMesh.new()
	im.transform_format = MultiMesh.TRANSFORM_3D
	im.mesh = icicle
	var ts: Array = []
	z = z0 - 0.2
	while z > z1:
		for sx: float in [-1.0, 1.0]:
			if rr.randf() < 0.75:
				var l := rr.randf_range(0.12, 0.55)
				var th := rr.randf_range(0.7, 1.3)
				ts.append(Transform3D(Basis().scaled(Vector3(th, l, th)), Vector3(sx * (HALF_W + 0.17), -0.37 - l * 0.5, z)))
		z -= rr.randf_range(0.18, 0.4)
	im.instance_count = ts.size()
	for i in ts.size():
		im.set_instance_transform(i, ts[i])
	var imi := MultiMeshInstance3D.new()
	imi.multimesh = im
	imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track.add_child(imi)
	# 결승 아치 위에 쌓인 눈
	box(Vector3(HALF_W * 2.0 + 1.1, 0.14, 0.24), snow_mat, Vector3(0, 4.6, FINISH_Z), Basis(), _track)
	# 바다 위 유빙 (납작하고 울퉁불퉁한 얼음 조각)
	var floe_mat := StandardMaterial3D.new()
	floe_mat.albedo_color = Color(0.8, 0.88, 0.94)
	floe_mat.roughness = 0.35
	for i in 22:
		var fl := CylinderMesh.new()
		var r := rr.randf_range(0.5, 1.8)
		fl.top_radius = r
		fl.bottom_radius = r * 1.05
		fl.height = 0.22
		fl.radial_segments = rr.randi_range(7, 11)
		fl.rings = 1
		var sx2 := -1.0 if rr.randf() < 0.5 else 1.0
		var pos := Vector3(sx2 * rr.randf_range(HALF_W + 4.0, 34.0), -1.84, rr.randf_range(z1 - 20.0, z0 + 15.0))
		var f := add_mesh(fl, floe_mat, pos, Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3(1.0, 1.0, rr.randf_range(0.6, 1.0))), world3)
		f.set_meta("bob", rr.randf() * TAU)
		_floes.append(f)
	# 내리는 눈 (화면 따라다님)
	var flake := QuadMesh.new()
	flake.size = Vector2(0.06, 0.06)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var fg := GradientTexture2D.new()
	fg.fill = GradientTexture2D.FILL_RADIAL
	fg.fill_from = Vector2(0.5, 0.5)
	fg.fill_to = Vector2(0.5, 0.0)
	var fgr := Gradient.new()
	fgr.set_color(0, Color(1, 1, 1, 0.95))
	fgr.set_color(1, Color(1, 1, 1, 0))
	fg.gradient = fgr
	fmat.albedo_texture = fg
	flake.material = fmat
	_snowfall = CPUParticles3D.new()
	_snowfall.amount = 700
	_snowfall.lifetime = 7.0
	_snowfall.preprocess = 7.0
	_snowfall.local_coords = false
	_snowfall.mesh = flake
	_snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snowfall.emission_box_extents = Vector3(16.0, 0.5, 18.0)
	_snowfall.direction = Vector3(0.25, -1, 0)
	_snowfall.spread = 15.0
	_snowfall.initial_velocity_min = 1.2
	_snowfall.initial_velocity_max = 2.0
	_snowfall.gravity = Vector3(0.2, -0.3, 0)
	_snowfall.scale_amount_min = 0.6
	_snowfall.scale_amount_max = 1.8
	_snowfall.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	world3.add_child(_snowfall)
	_snowfall.position = Vector3(0, 11.0, _cam_z - 8.0)


func _setup_game() -> void:
	walk_radius = 999.0
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var x := (float(i) - (n - 1) * 0.5) * 2.0
		var w := add_walker(p, Vector3(x, 0, START_Z + 1.0), 5.0)
		w["face"] = PI   # 위(앞)를 봄
		w["dash_cd"] = 0.0
		w["dash_t"] = 0.0
		w["stun"] = 0.0
		w["fallen"] = 0.0
		_ai[int(p["slot"])] = {"t": 0.0, "lane": x, "inp": Vector3.ZERO}
		scores[int(p["slot"])] = 0.0


func _start_game() -> void:
	_elapsed = 0.0
	_barrel_t = 0.6


func _racing() -> Array:
	return walkers.keys().filter(func(s: int) -> bool: return not _done.has(s))


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
	if _done.has(s) or float(w["dash_cd"]) > 0.0 or float(w["fallen"]) > 0.0 or float(w["stun"]) > 0.0:
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
	splash((w["pos"] as Vector3) + Vector3(0, 0.15, 0), 6, 0.25)


## 방장 → 그 말을 움직이는 PC: 이만큼 튕겨 + 잠깐 휘청
func _kick(s: int, v: Vector3, stun: float = 0.0) -> void:
	var w: Dictionary = walkers.get(s, {})
	if w.is_empty() or _done.has(s):
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
		_barrel_t -= delta
		if _barrel_t <= 0.0:
			_spawn_barrel()
			_barrel_t = rng.randf_range(BARREL_GAP_MIN, BARREL_GAP_MAX)
	_slide(delta)
	_update_barrels(delta)
	if not is_client():
		_bumps(delta)
		_check_edges()
	for s in walkers:
		scores[s] = 1000.0 - float(_done[s]) if _done.has(s) else START_Z - float((walkers[s]["pos"] as Vector3).z)
	_follow_cam(delta)


## 화면: 내 말 (자동이면 아직 달리는 사람 중 선두) 을 부드럽게 따라감
func _follow_cam(delta: float) -> void:
	var focus := START_Z
	var me := local_slot()
	if walkers.has(me) and is_local(walkers[me]["p"]):
		focus = float((walkers[me]["pos"] as Vector3).z)
	else:
		var best := INF
		for s in _racing():
			best = minf(best, float((walkers[s]["pos"] as Vector3).z))
		focus = best if best < INF else FINISH_Z
	focus = clampf(focus, FINISH_Z - 2.0, START_Z)
	_cam_z = lerpf(_cam_z, focus, clampf(delta * 3.0, 0.0, 1.0))
	_place_cam(_cam_z)
	if _snowfall:
		_snowfall.position = Vector3(0, 11.0, _cam_z - 8.0)
	for f: Node3D in _floes:
		var ph := float(f.get_meta("bob")) + _t3 * 0.9
		f.position.y = -1.84 + sin(ph) * 0.06
		f.rotation.x = sin(ph * 0.8) * 0.03


## 미끄러지는 움직임 (가속만, 마찰 약함)
func _slide(delta: float) -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		w["dash_cd"] = maxf(0.0, float(w["dash_cd"]) - delta)
		w["dash_t"] = maxf(0.0, float(w["dash_t"]) - delta)
		w["stun"] = maxf(0.0, float(w["stun"]) - delta)
		if float(w["fallen"]) > 0.0:
			_fallen_step(s, w, delta)
			continue
		if w.has("net_pos"):
			_step_puppet(w, delta)
			_pose(w, delta, Vector3.ZERO)
			continue
		var p: Dictionary = w["p"]
		var inp := Vector3.ZERO
		if _done.has(s):
			inp = Vector3.ZERO
		elif is_local(p):
			inp = key_dir()
		elif not is_human(p):
			inp = _ai[s]["inp"]
		if float(w["stun"]) > 0.0:
			inp = Vector3.ZERO
		var fric := 1.05
		if _done.has(s):
			fric = 3.0
		var vel: Vector3 = w["vel"]
		vel += inp * ACC * delta
		vel *= exp(-fric * delta)
		var sp := vel.length()
		if sp > MAXV:
			vel = vel.normalized() * lerpf(sp, MAXV, clampf(delta * 1.6, 0.0, 1.0))
		var pos: Vector3 = w["pos"] + vel * delta
		for o in walkers:
			if o == s or float(walkers[o]["fallen"]) > 0.0:
				continue
			var d: Vector3 = pos - (walkers[o]["pos"] as Vector3)
			d.y = 0.0
			if d.length() < 0.7 and d.length() > 0.001:
				pos += d.normalized() * (0.7 - d.length()) * 0.5
		# 출발선 뒤 막힘판
		if pos.z > START_Z + 2.6:
			pos.z = START_Z + 2.6
			vel.z = -absf(vel.z) * 0.4
		pos.y = walk_y
		w["pos"] = pos
		w["vel"] = vel
		if inp.length() > 0.1:
			w["face"] = lerp_angle(float(w["face"]), atan2(inp.x, inp.z), clampf(delta * 9.0, 0.0, 1.0))
		_pose(w, delta, inp)


## 말 자세: 미끄러지면 휘청 · 돌진 땐 앞으로 숙임 · 술통에 맞으면 빙글
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
	var spin := float(w["stun"]) * 9.0
	n.position = (w["pos"] as Vector3) + Vector3(0, absf(sin(float(w["bob"]))) * 0.05 * clampf(sp / 3.0, 0.0, 1.0), 0)
	n.rotation = Vector3(lean_f, face + spin, clampf(-slip * 0.5, -0.4, 0.4) + wobble)
	if sp > 3.5 and fmod(_t3 + float(w["bob"]) * 0.01, 0.15) < delta:
		_skid(w)


func _skid(w: Dictionary) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 5
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = -(w["vel"] as Vector3).normalized() + Vector3(0, 0.8, 0)
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


## 방장: 서로 부딪침 (돌진한 쪽이 이김)
func _bumps(delta: float) -> void:
	for k in _pair_cd.keys():
		_pair_cd[k] = float(_pair_cd[k]) - delta
		if float(_pair_cd[k]) <= 0.0:
			_pair_cd.erase(k)
	var al := _racing().filter(func(s: int) -> bool: return float(walkers[s]["fallen"]) <= 0.0)
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
			var imp := rel * 0.9 + 2.0
			_kick(a, -n * imp * (0.4 if da else 0.8) * (1.5 if db else 1.0))
			_kick(b, n * imp * (0.4 if db else 0.8) * (1.5 if da else 1.0))
			net_call("_bump_fx", [((wa["pos"] as Vector3) + (wb["pos"] as Vector3)) * 0.5, minf(imp / 8.0, 1.0)])


func _bump_fx(at: Vector3, power: float) -> void:
	sfx("thud", 50)
	splash(at + Vector3(0, 0.6, 0), int(8 + power * 14), 0.4 + power * 0.4)


# ── 떨어짐 · 다시 올라옴 · 도착 ─────────────────────────────
func _check_edges() -> void:
	for s in _racing():
		var w: Dictionary = walkers[s]
		if float(w["fallen"]) > 0.0:
			continue
		var pos: Vector3 = w["pos"]
		if absf(pos.x) > HALF_W + 0.25:
			net_call("_fall", [s, pos])
		elif pos.z < FINISH_Z:
			net_call("_finish", [s, _elapsed])


func _fall(s: int, at: Vector3) -> void:
	var w: Dictionary = walkers[s]
	if float(w["fallen"]) > 0.0:
		return
	w["fallen"] = 1.6
	w["fall_at"] = at
	w["vel"] = Vector3.ZERO
	sfx("whoosh")
	float_at(at + Vector3(0, 2.4, 0), tr("SPLASH!"), Color(0.6, 0.9, 1.0), 44)


## 떨어지는 중: 옆으로 날아 바다에 풍덩 → 잠깐 뒤 다리 가운데 조금 뒤쪽에서 다시 (움직이는 PC 가 자리 정함)
func _fallen_step(s: int, w: Dictionary, delta: float) -> void:
	var t0 := float(w["fallen"])
	w["fallen"] = t0 - delta
	var n: Node3D = w["node"]
	var at: Vector3 = w["fall_at"]
	var f := clampf((1.6 - float(w["fallen"])) / 0.55, 0.0, 1.0)
	var side := signf(at.x)
	if t0 > 1.05:
		n.position = at + Vector3(side * f * 1.4, sin(f * PI) * 0.9 - f * 2.2, 0)
		n.rotation = Vector3(f * 1.8, float(w["face"]), side * f)
		if float(w["fallen"]) <= 1.05:
			splash(n.position + Vector3(0, 0.6, 0), 40, 1.0)
			sfx("splash")
	if float(w["fallen"]) <= 0.0:
		w["fallen"] = 0.0
		var back := Vector3(clampf(at.x * 0.2, -1.0, 1.0), walk_y, minf(at.z + 2.5, START_Z + 1.0))
		if not w.has("net_pos"):
			w["pos"] = back
		w["vel"] = Vector3.ZERO
		w["stun"] = 0.3
		n.position = back + Vector3(0, 2.0, 0)
		var tw := create_tween()
		tw.tween_property(n, "position:y", walk_y, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		splash(back, 12, 0.5)


func _finish(s: int, t: float) -> void:
	if _done.has(s):
		return
	_done[s] = t
	_done_n += 1
	var p := player_by_slot(s)
	sfx("start")
	var w: Dictionary = walkers[s]
	float_at((w["pos"] as Vector3) + Vector3(0, 2.6, 0), tr("No.%d") % _done_n, (p["color"] as Color).lightened(0.3), 56)
	splash((w["pos"] as Vector3) + Vector3(0, 1.0, 0), 30, 0.8)


# ── 굴러오는 술통 ────────────────────────────────────────────
func _spawn_barrel() -> void:
	# 가끔은 달리는 사람을 노림
	var x := rng.randf_range(-HALF_W + 0.5, HALF_W - 0.5)
	if rng.randf() < 0.3:
		var rc := _racing()
		if not rc.is_empty():
			x = clampf(float((walkers[rc[rng.randi() % rc.size()]]["pos"] as Vector3).x) + rng.randf_range(-0.6, 0.6), -HALF_W + 0.5, HALF_W - 0.5)
	# 바로 직전에 나온 통과 너무 붙어 나오지 않게 (한 줄로 벽을 만들면 못 피함)
	for k in 6:
		var ok := true
		for br in _barrels:
			if _elapsed - float(br["t0"]) < 0.9 and absf(float(br["x"]) - x) < 1.7:
				ok = false
		if ok:
			break
		x = rng.randf_range(-HALF_W + 0.5, HALF_W - 0.5)
	_next_barrel += 1
	net_call("_barrel_go", [_next_barrel, x, rng.randf_range(BARREL_V_MIN, BARREL_V_MAX), _elapsed, rng.randf() < 0.25])


func _barrel_go(id: int, x: float, speed: float, t0: float, hop: bool) -> void:
	var root := Node3D.new()
	world3.add_child(root)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP)   # 굴러가는 축 = 좌우
	var b := barrel(holder, Vector3(0, 0, -0.55), BARREL_R, 1.1, [Color(0.4, 0.25, 0.13), Color(0.34, 0.22, 0.12), Color(0.45, 0.3, 0.16)][id % 3])
	b.rotation = Vector3(PI / 2, 0, 0)
	root.position = Vector3(x, BARREL_R, FINISH_Z - 5.5)
	_barrels.append({"id": id, "x": x, "speed": speed, "t0": t0, "node": root, "holder": holder, "hit": {}, "hop": hop})


func _barrel_z(br: Dictionary) -> float:
	return FINISH_Z - 5.5 + float(br["speed"]) * (_elapsed - float(br["t0"]))


func _update_barrels(delta: float) -> void:
	for br in _barrels.duplicate():
		var z := _barrel_z(br)
		var node: Node3D = br["node"]
		var t := _elapsed - float(br["t0"])
		var y := BARREL_R + (absf(sin(t * 3.2)) * 0.7 if br["hop"] else 0.0)   # 통통 튀며 오는 통
		node.position = Vector3(float(br["x"]) + sin(t * 1.3 + float(br["id"])) * 0.15, y, z)
		(br["holder"] as Node3D).rotate_object_local(Vector3.FORWARD, -float(br["speed"]) * delta / BARREL_R)
		if z > START_Z + 2.4:
			_barrels.erase(br)
			# 출발선 뒤 막힘판에 부딪혀 바다로 튕겨 떨어짐
			var tw := create_tween()
			tw.tween_property(node, "position", node.position + Vector3(signf(float(br["x"])) * 3.0 + 0.5, -2.5, 0.3), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void:
				splash(node.position + Vector3(0, 1.2, 0), 20, 0.7)
				node.queue_free())
			continue
		if is_client():
			continue
		var hit: Dictionary = br["hit"]
		for s in _racing():
			var w: Dictionary = walkers[s]
			if hit.has(s) or float(w["fallen"]) > 0.0:
				continue
			var pos: Vector3 = w["pos"]
			if absf(pos.z - z) < 0.8 and absf(pos.x - node.position.x) < 0.9 and y < 1.2:
				hit[s] = true
				var away := signf(pos.x - node.position.x)
				if away == 0.0:
					away = 1.0 if rng.randf() < 0.5 else -1.0
				_kick(s, Vector3(away * 2.6, 0, float(br["speed"]) * 0.95), 0.45)
				net_call("_bump_fx", [Vector3(pos.x, 0, z), 1.0])


# ── CPU ─────────────────────────────────────────────────────
## 앞으로 달리며 앞에서 굴러오는 술통이 내 줄에 있으면 옆 빈 줄로 비킴. 가장자리는 피하고, 길이 비면 돌진
func _think(delta: float) -> void:
	for s in _racing():
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p)
		var pos: Vector3 = w["pos"]
		var vel: Vector3 = w["vel"]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.4, 0.12, sk / 2.0) + rng.randf_range(0.0, 0.1)
			# 앞으로 잠깐 사이에 내 자리를 지나갈 술통들 → 줄마다 위험도
			var best_x: float = a["lane"]
			var best_v := INF
			for k in 11:
				var lx := lerpf(-HALF_W + 0.7, HALF_W - 0.7, k / 10.0)
				var danger := 0.0
				for br in _barrels:
					var bz := _barrel_z(br)
					var gap := pos.z - bz
					if gap < -0.6 or gap > 12.0:
						continue
					var closing := float(br["speed"]) - vel.z
					var eta := gap / maxf(closing, 1.0)
					if eta > lerpf(0.7, 1.8, sk / 2.0):
						continue
					if absf(lx - float(br["x"])) < 1.0:
						danger += 3.0 / maxf(eta, 0.2)
				var v := danger + absf(lx - pos.x) * 0.35 + absf(lx) * 0.12 + rng.randf_range(0.0, lerpf(1.5, 0.2, sk / 2.0))
				if v < best_v:
					best_v = v
					best_x = lx
			a["lane"] = best_x
		var want := Vector3((float(a["lane"]) - pos.x) * 2.4, 0, -lerpf(4.2, 6.2, sk / 2.0))
		# 가장자리 근처: 바깥으로 미끄러지는 중이면 안쪽으로 강하게
		if absf(pos.x) > HALF_W - lerpf(0.6, 1.2, sk / 2.0) and vel.x * signf(pos.x) > -0.3:
			want.x = -signf(pos.x) * 5.0
		var steer := want - vel
		a["inp"] = steer.normalized() if steer.length() > 0.35 else Vector3.ZERO
		# 앞이 비었고 가장자리가 아니면 돌진 (앞으로)
		if float(w["dash_cd"]) <= 0.0 and absf(pos.x) < HALF_W - 1.2 and float(w["stun"]) <= 0.0:
			var clear := true
			for br in _barrels:
				var bz := _barrel_z(br)
				if pos.z - bz < 6.0 and pos.z - bz > -0.5 and absf(pos.x - float(br["x"])) < 1.2:
					clear = false
			if clear and rng.randf() < lerpf(0.05, 0.35, sk / 2.0) * delta * 10.0:
				a["inp"] = Vector3(0, 0, -1)
				_dash(s)


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	return _racing().is_empty()


## 순위: 도착한 순서 → 못 온 사람은 많이 올라간 순
func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	var key := func(p: Dictionary) -> float:
		var s := int(p["slot"])
		if _done.has(s):
			return 10000.0 - float(_done[s])
		return -float((walkers[s]["pos"] as Vector3).z)
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


func _net_state() -> Dictionary:
	return {"el": _elapsed}


func _net_apply(st: Dictionary) -> void:
	_elapsed = float(st.get("el", _elapsed))


func _score_text(p: Dictionary) -> String:
	var s := int(p["slot"])
	if _done.has(s):
		return "%.1fs" % float(_done[s])
	if not walkers.has(s):
		return ""
	return "%dm" % maxi(0, int(round(float((walkers[s]["pos"] as Vector3).z) - FINISH_Z)))
