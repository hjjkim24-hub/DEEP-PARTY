extends "res://scripts/minigames/minigame_base.gd"
## 3D 미니게임 공통 틀. 화면 전체에 자기만의 3D 세상(SubViewport)을 깔고 그 위에 점수판 · 글씨를 올려요.
##   world3 : 3D 물체를 붙이는 곳        cam : 카메라         env : 환경(하늘 · 안개)
##   mouse_ground(h)  마우스가 가리키는 높이 h 바닥 위 점 (없으면 INF)
##   to_arena(p3)     3D 점 → 점수 글씨 띄울 화면(arena) 좌표
##   make_pawn(p)     그 사람 색 · 꾸미기 그대로의 말
##   walkers          말 걸어다니기 (사람은 마우스 쪽으로, CPU 는 ai 가 정한 곳으로)

const BoardWorld := preload("res://scripts/world3d/board_world.gd")
const Pawn3D := preload("res://scripts/world3d/pawn3d.gd")
const OceanShader := preload("res://shaders/ocean.gdshader")
const DangerShader := preload("res://shaders/mg_mark.gdshader")
const SmokeShader := preload("res://shaders/smoke_puff.gdshader")
const KrakenBodyShader := preload("res://shaders/kraken_body.gdshader")
const KrakenEyeShader := preload("res://shaders/kraken_eye.gdshader")
const KRAKEN_BODY := preload("res://models/kraken_body.obj")
const CloudShader := preload("res://shaders/cloud_puff.gdshader")
const RayShader := preload("res://shaders/light_ray.gdshader")

const PAWN_SCALE := 1.45

var vpc: SubViewportContainer
var vp: SubViewport
var world3: Node3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var kit: Node3D                   ## 보드 세상의 재질 · 촉수 만드는 도구만 빌려 씀 (화면엔 안 붙임)
var walkers := {}                 ## slot → {node, pos, vel, target, speed, out, face, bob}
var walk_radius := 6.0            ## 말이 다닐 수 있는 원 (가운데 0,0)
var walk_y := 0.0
var _t3 := 0.0
var cam_base := Transform3D()   ## 흔들림 없는 카메라 자리 (무대 만든 뒤 저장)
var _shake := 0.0
var _shake_t := 0.0
var _floaters: Array = []      ## 물 위에 둥둥 떠다니는 것 {node, base, ph}
var _gulls: Array = []         ## 하늘을 도는 갈매기 {node, wl, wr, c, r, h, sp, ph}
var _flickers: Array = []      ## 일렁이는 불빛 {light, base, ph}


func _make_stage() -> void:
	vpc = SubViewportContainer.new()
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vpc)
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.positional_shadow_atlas_size = 1024
	vp.handle_input_locally = false
	vpc.add_child(vp)
	world3 = Node3D.new()
	vp.add_child(world3)
	# 입자(물보라 · 먹물 · 불꽃 · 거품)는 그림자를 드리우지 않게 — 네모난 그림자 얼룩 방지
	(Engine.get_main_loop() as SceneTree).node_added.connect(func(n: Node) -> void:
		if n is CPUParticles3D or n is GPUParticles3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.current = true
	world3.add_child(cam)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.2
	env.ssr_enabled = true          # 물 · 젖은 면에 비치는 모습 (Forward+)
	env.ssr_max_steps = 48
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	env.glow_hdr_threshold = 0.85
	we.environment = env
	world3.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 40.0
	world3.add_child(sun)
	kit = BoardWorld.new()
	_build_stage()
	cam_base = cam.transform


func _process(delta: float) -> void:
	super._process(delta)
	_net_send_me(delta)
	if cam == null:
		return
	var tt := Time.get_ticks_msec() / 1000.0
	for fl in _flickers:
		var l: OmniLight3D = fl["light"]
		if is_instance_valid(l):
			var ph: float = fl["ph"]
			l.light_energy = float(fl["base"]) * (0.82 + 0.12 * sin(tt * 13.0 + ph) + 0.08 * sin(tt * 31.0 + ph * 2.0))
	for f in _floaters:
		var n: Node3D = f["node"]
		var ph: float = f["ph"]
		n.position = (f["base"] as Vector3) + Vector3(sin(tt * 0.3 + ph) * 0.4, sin(tt * 1.1 + ph) * 0.12, cos(tt * 0.25 + ph) * 0.4)
		n.rotation = Vector3(sin(tt * 0.9 + ph) * 0.12, f["yaw"] + tt * 0.05, cos(tt * 0.8 + ph) * 0.12)
	for g in _gulls:
		var n: Node3D = g["node"]
		var a := tt * float(g["sp"]) + float(g["ph"])
		var c: Vector3 = g["c"]
		var r: float = g["r"]
		n.position = c + Vector3(cos(a) * r, float(g["h"]) + sin(a * 2.0) * 0.6, sin(a) * r * 0.7)
		n.rotation = Vector3(0, -a + (PI if float(g["sp"]) > 0 else 0.0), sin(a) * 0.3)
		var flap := sin(tt * 7.0 + float(g["ph"]) * 3.0) * 0.55 + 0.1
		(g["wl"] as Node3D).rotation.z = flap
		(g["wr"] as Node3D).rotation.z = -flap
	if _shake > 0.0:
		_shake_t += delta
		_shake = maxf(0.0, _shake - delta * 2.4)
		var a := _shake * _shake
		var off := Vector3(sin(_shake_t * 47.0) * 0.6 + sin(_shake_t * 23.0) * 0.4, cos(_shake_t * 41.0) * 0.5 + sin(_shake_t * 29.0) * 0.3, 0.0) * a * 0.35
		cam.transform = cam_base * Transform3D(Basis(Vector3(0, 0, 1), sin(_shake_t * 37.0) * a * 0.01), off)
	else:
		cam.transform = cam_base


## 화면 흔들림 (0~1)
func shake(strength: float) -> void:
	if demo:
		strength *= 0.4
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


func _exit_tree() -> void:
	if is_instance_valid(kit):
		kit.free()


## 무대 만들기 (상속해서 채움)
func _build_stage() -> void:
	pass


# ── 환경 ─────────────────────────────────────────────────────
## 맑은 오후 바다 (구름 조금)
func env_sea_day() -> void:
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.72)
	sm.sky_horizon_color = Color(0.7, 0.8, 0.88)
	sm.sky_curve = 0.15
	sm.ground_bottom_color = Color(0.02, 0.1, 0.16)
	sm.ground_horizon_color = Color(0.55, 0.68, 0.76)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_exposure = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.72, 0.82)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.2
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-48, -35, 0)


## 폭풍이 다가오는 해 질 녘 바다
func env_stormy_dusk() -> void:
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.12, 0.2)
	sm.sky_horizon_color = Color(0.85, 0.5, 0.38)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.03, 0.05, 0.07)
	sm.ground_horizon_color = Color(0.5, 0.36, 0.34)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.33, 0.36)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.25
	sun.light_color = Color(1.0, 0.72, 0.52)
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-28, -38, 0)


## 밝은 물속 (모래 바닥 + 물빛)
func env_underwater() -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.1, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.55, 0.62)
	env.ambient_light_energy = 0.42
	env.tonemap_exposure = 0.78
	# 거리 안개: 가까운 무대는 또렷, 멀어질수록 짙은 청록 물속으로 사라짐
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.02, 0.17, 0.22)
	env.fog_density = 1.0
	env.fog_depth_begin = 10.0
	env.fog_depth_end = 42.0
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 1.0
	# 물속 색 보정: 붉은빛은 먼저 흡수되고, 그림자는 청록으로 뜸
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.035, 0.06))
	g.set_color(1, Color(0.85, 0.96, 1.0))
	g.add_point(0.25, Color(0.07, 0.15, 0.2))
	g.add_point(0.55, Color(0.33, 0.47, 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 256
	env.adjustment_color_correction = gt
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.0
	env.glow_intensity = 0.5
	sun.light_color = Color(0.85, 1.0, 0.95)
	sun.light_energy = 1.45
	# 먼 물속 배경 (안개가 닿지 않는 끝을 감싸는 큰 구)
	var bs := SphereMesh.new()
	bs.radius = 46.0
	bs.height = 92.0
	bs.radial_segments = 32
	bs.rings = 16
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/uw_backdrop.gdshader")
	var bmi := add_mesh(bs, bm, Vector3.ZERO)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun.rotation_degrees = Vector3(-62, -25, 0)


## 밑에서 올려다본 수면: 짙은 청록 + 일렁이는 밝은 물결 하이라이트
func surface_from_below(y: float, size: float = 120.0) -> MeshInstance3D:
	var surf := PlaneMesh.new()
	surf.size = Vector2(size, size)
	surf.flip_faces = true
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.32, 0.38, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.normal_enabled = true
	m.normal_texture = load("res://textures/ocean/water_normal_a.png")
	m.normal_scale = 1.6
	m.uv1_scale = Vector3(5, 5, 5)
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.emission_enabled = true
	m.emission = Color(0.2, 0.48, 0.52)
	m.emission_energy_multiplier = 1.0
	var mi := add_mesh(surf, m, Vector3(0, y, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func ocean(y: float = 0.0, size: float = 160.0, calm_r: float = 0.0, day: bool = true) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 220
	pm.subdivide_depth = 220
	var m := ShaderMaterial.new()
	m.shader = OceanShader
	m.render_priority = -1     # 다른 투명한 것(촉수 · 연기)보다 먼저
	m.set_shader_parameter("calm_radius", calm_r)
	m.set_shader_parameter("normal_a", load("res://textures/ocean/water_normal_a.png"))
	m.set_shader_parameter("normal_b", load("res://textures/ocean/water_normal_b.png"))
	m.set_shader_parameter("foam_tex", load("res://textures/ocean/foam.png"))
	if day:
		m.set_shader_parameter("deep", Color(0.0, 0.075, 0.13))
		m.set_shader_parameter("shallow", Color(0.03, 0.3, 0.32))
		m.set_shader_parameter("sss_col", Color(0.04, 0.48, 0.44))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world3.add_child(mi)
	return mi


## 보드 세상의 돌 · 나무 재질 (결 · 이끼 무늬 셰이더)
func wood_mat(c: Color, axis: Vector3 = Vector3(0, 0, 1), moss: float = 0.15) -> ShaderMaterial:
	var m: ShaderMaterial = kit._wood(c, axis, moss)
	m = m.duplicate()
	m.set_shader_parameter("caustics", 0.0)
	return m


func stone_mat(c: Color, kind: String = "stone", moss: float = 0.4) -> ShaderMaterial:
	return kit._smat(c, kind, 0.0, moss)


## 보드의 장식(바위 · 산호 · 말미잘 · 다시마)을 그대로 빌려 와서 이 무대에 놓기
func reef(kind: String, p: Vector3, c: Color = Color.WHITE, size: float = 1.0) -> void:
	var before := kit.get_child_count()
	match kind:
		"rock":
			var mi := MeshInstance3D.new()
			mi.mesh = kit._rock_mesh()
			var rm: ShaderMaterial = kit._rock_mat(randi() % 3).duplicate()
			rm.set_shader_parameter("moss_color", Color(0.2, 0.3, 0.19))
			rm.set_shader_parameter("moss", 0.6)
			mi.material_override = rm
			mi.position = p
			mi.scale = Vector3(size * randf_range(0.9, 1.3), size * randf_range(0.6, 0.85), size * randf_range(0.9, 1.2))
			mi.rotation = Vector3(randf_range(-0.12, 0.12), randf() * TAU, randf_range(-0.12, 0.12))
			world3.add_child(mi)
			return
		"coral":
			kit._coral(p, c, size)
		"brain":
			kit._brain(p, c, size)
		"table":
			kit._table_coral(p, c, size)
		"fan":
			kit._fan_coral(p, c, size)
		"anemone":
			kit._anemone(p, c)
		"sponge":
			kit._sponge(p, c)
		"kelp":
			kit._kelp(p, size)
	# 도구(kit)에 붙은 것을 이 무대로 옮김 (모양 · 위치 그대로)
	var moved := kit.get_children().slice(before)
	for n in moved:
		kit.remove_child(n)
		world3.add_child(n)


func std_mat(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func box(size: Vector3, mat: Material, pos: Vector3, basis_: Basis = Basis(), parent: Node3D = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return add_mesh(b, mat, pos, basis_, parent)


func add_mesh(mesh: Mesh, mat: Material, pos: Vector3, basis_: Basis = Basis(), parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis_, pos)
	(parent if parent else world3).add_child(mi)
	return mi


# ── 마우스 · 화면 ────────────────────────────────────────────
func mouse_vp() -> Vector2:
	return vpc.get_local_mouse_position() * (Vector2(vp.size) / vpc.size) if vpc.size.x > 0 else Vector2.ZERO


func mouse_ground(h: float = 0.0) -> Vector3:
	var m := mouse_vp()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (h - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t


func mouse_ray() -> Array:
	var m := mouse_vp()
	return [cam.project_ray_origin(m), cam.project_ray_normal(m)]


## 3D 점 → arena 좌표 (float_text 용)
func to_arena(p3: Vector3) -> Vector2:
	var sp := cam.unproject_position(p3) * (vpc.size / Vector2(vp.size))
	return (sp - arena.position) / arena.scale.x


# ── 말 ───────────────────────────────────────────────────────
func make_pawn(p: Dictionary) -> Node3D:
	var n := Pawn3D.new()
	var pc: Color = p["color"]
	n.color = Color.from_hsv(pc.h, minf(pc.s * 1.25 + 0.05, 1.0), pc.v * 0.92)
	n.look = p.get("look", {})
	n.scale = Vector3.ONE * PAWN_SCALE
	world3.add_child(n)
	return n


func add_walker(p: Dictionary, pos: Vector3, speed: float = 5.0) -> Dictionary:
	var w := {"node": make_pawn(p), "pos": pos, "vel": Vector3.ZERO, "target": pos, "speed": speed,
		"out": false, "face": 0.0, "bob": randf() * TAU, "slow": 0.0, "push": Vector3.ZERO, "p": p}
	(w["node"] as Node3D).position = pos
	walkers[int(p["slot"])] = w
	return w


## 사람: WASD / 방향키로 이동 (카메라가 보는 쪽이 위). 자동 점검 · 미리보기면 ai 가 정한 target
func human_target(w: Dictionary) -> void:
	var p: Dictionary = w["p"]
	if is_local(p) and playing:
		var d := key_dir()
		var pos: Vector3 = w["pos"]
		w["target"] = pos + d * 2.0 if d != Vector3.ZERO else pos


## 키보드 방향 (월드 바닥 기준, 화면 위 = 카메라 앞쪽)
func key_dir() -> Vector3:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if v == Vector2.ZERO:
		return Vector3.ZERO
	v = v.normalized()
	var fwd := -cam_base.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var right := fwd.cross(Vector3.UP).normalized()
	return (right * v.x - fwd * v.y).normalized()


func step_walkers(delta: float) -> void:
	_t3 += delta
	var list := walkers.values()
	for w in list:
		if w["out"]:
			continue
		# 온라인: 다른 PC 가 움직이는 말은 받은 자리로 부드럽게 따라감 (걷는 모습은 그대로)
		if w.has("net_pos"):
			_step_puppet(w, delta)
			continue
		human_target(w)
		var pos: Vector3 = w["pos"]
		var to: Vector3 = w["target"] - pos
		to.y = 0.0
		var sp: float = float(w["speed"]) * (0.45 if float(w["slow"]) > 0.0 else 1.0)
		w["slow"] = maxf(0.0, float(w["slow"]) - delta)
		# 속도 증가 (색칠 게임의 물살 구슬 등)
		if float(w.get("boost", 0.0)) > 0.0:
			sp *= 1.65
			w["boost"] = maxf(0.0, float(w["boost"]) - delta)
		var want := Vector3.ZERO
		if to.length() > 0.15:
			want = to.normalized() * sp * clampf(to.length() / 0.8, 0.25, 1.0)
		var vel: Vector3 = (w["vel"] as Vector3).lerp(want, clampf(delta * 10.0, 0.0, 1.0))
		var push: Vector3 = w["push"]
		pos += (vel + push) * delta
		w["push"] = push.lerp(Vector3.ZERO, clampf(delta * 4.0, 0.0, 1.0))
		# 서로 밀어내기
		for o in list:
			if o == w or o["out"]:
				continue
			var d: Vector3 = pos - (o["pos"] as Vector3)
			d.y = 0.0
			if d.length() < 0.7 and d.length() > 0.001:
				pos += d.normalized() * (0.7 - d.length()) * 0.5
		var flat := Vector2(pos.x, pos.z)
		if flat.length() > walk_radius:
			flat = flat.normalized() * walk_radius
			pos.x = flat.x
			pos.z = flat.y
		pos.y = walk_y
		w["pos"] = pos
		w["vel"] = vel
		var n: Node3D = w["node"]
		var spd := vel.length()
		if spd > 0.3:
			w["face"] = lerp_angle(float(w["face"]), atan2(vel.x, vel.z), clampf(delta * 12.0, 0.0, 1.0))
		w["bob"] = float(w["bob"]) + delta * (6.0 + spd * 2.2)
		var hop := absf(sin(float(w["bob"]))) * clampf(spd / 4.0, 0.0, 1.0) * 0.22
		n.position = pos + Vector3(0, hop, 0)
		n.rotation = Vector3(clampf(spd * 0.04, 0.0, 0.25), float(w["face"]), sin(float(w["bob"])) * 0.06 * clampf(spd / 4.0, 0.0, 1.0))


func _step_puppet(w: Dictionary, delta: float) -> void:
	var pos: Vector3 = w["pos"]
	var goal: Vector3 = w["net_pos"]
	goal.y = walk_y
	var np := pos.lerp(goal, clampf(delta * 12.0, 0.0, 1.0))
	if pos.distance_to(goal) > 4.0:
		np = goal   # 너무 멀면 순간이동 (밀려남 · 부활 등)
	var vel := (np - pos) / maxf(delta, 0.001)
	vel.y = 0.0
	w["pos"] = np
	w["vel"] = vel
	w["face"] = lerp_angle(float(w["face"]), float(w.get("net_face", w["face"])), clampf(delta * 12.0, 0.0, 1.0))
	var spd := vel.length()
	w["bob"] = float(w["bob"]) + delta * (6.0 + spd * 2.2)
	var hop := absf(sin(float(w["bob"]))) * clampf(spd / 4.0, 0.0, 1.0) * 0.22
	var n: Node3D = w["node"]
	n.position = np + Vector3(0, hop, 0)
	n.rotation = Vector3(clampf(spd * 0.04, 0.0, 0.25), float(w["face"]), sin(float(w["bob"])) * 0.06 * clampf(spd / 4.0, 0.0, 1.0))


## 온라인: 걷는 말 상태 (방장 → 손님). 손님 자기 말은 손님 PC 가 움직이고 방장에게 알려 줌
func _net_state_common() -> Dictionary:
	if walkers.is_empty():
		return {}
	var ws := {}
	for s in walkers:
		var w: Dictionary = walkers[s]
		ws[s] = [w["pos"], float(w["face"]), bool(w["out"])]
	return {"w": ws}


func _net_apply_common(st: Dictionary) -> void:
	var ws: Dictionary = st.get("w", {})
	for s in ws:
		var w: Dictionary = walkers.get(int(s), {})
		if w.is_empty():
			continue
		var v: Array = ws[s]
		if int(s) == net_me and not bool(v[2]):
			continue
		w["net_pos"] = v[0]
		w["net_face"] = v[1]
		if bool(v[2]) and not bool(w["out"]):
			w["out"] = true


## 손님: 내 말 자리를 방장에게 (초당 15번)
var _me_acc := 0.0


func _net_send_me(delta: float) -> void:
	if net != "client" or not playing:
		return
	_me_acc += delta
	if _me_acc < NET_DT:
		return
	_me_acc = 0.0
	var w: Dictionary = walkers.get(net_me, {})
	if w.is_empty() or w["out"]:
		return
	Net.to_host({"k": "mg_me", "p": [w["pos"].x, w["pos"].z, float(w["face"])]})


## 방장: 손님 말 자리 받기
func _on_net_msg(from: int, d: Dictionary) -> void:
	if String(d.get("k", "")) == "mg_me" and net == "host":
		var slot := _peer_slot(from)
		var w: Dictionary = walkers.get(slot, {})
		var a: Array = d.get("p", [])
		if not w.is_empty() and a.size() >= 3 and not w["out"]:
			w["net_pos"] = Vector3(float(a[0]), walk_y, float(a[1]))
			w["net_face"] = float(a[2])
		return
	super._on_net_msg(from, d)


## 방장 → 손님 한 명: 네 말을 이만큼 밀어 (맞아서 튕겨 남 등)
func net_push(slot: int, push: Vector3, slow: float = 0.0) -> void:
	var w: Dictionary = walkers.get(slot, {})
	if w.is_empty():
		return
	if net == "host" and slot != net_me:
		Net.broadcast({"k": "mg_e", "m": "_push_me", "v": Marshalls.variant_to_base64([slot, push, slow])})
	else:
		w["push"] = push
		w["slow"] = maxf(float(w["slow"]), slow)


func _push_me(slot: int, push: Vector3, slow: float) -> void:
	if slot != net_me:
		return
	var w: Dictionary = walkers.get(slot, {})
	if not w.is_empty():
		w["push"] = push
		w["slow"] = maxf(float(w["slow"]), slow)


# ── 효과 ─────────────────────────────────────────────────────
## 바닥의 붉은 경고 원
func danger_ring(pos: Vector3, r: float, full: Vector3 = Vector3.ONE, yaw: float = 0.0, parent: Node3D = null) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = DangerShader
	m.set_shader_parameter("aspect", full.z / maxf(full.x, 0.01))
	var mi := add_mesh(q, m, pos + Vector3(0, 0.04, 0), Basis(Vector3.UP, yaw), parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = full * 0.2
	create_tween().tween_property(mi, "scale", full, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return mi


## 바닥의 직사각형 경고 (a → b 쪽으로 폭 width). 촉수가 눕는 자리 그대로
func rect_mark(a: Vector3, b: Vector3, width: float, parent: Node3D = null, y: float = 0.05) -> MeshInstance3D:
	var len := maxf(a.distance_to(b), 0.1)
	var q := QuadMesh.new()
	q.size = Vector2(width, len)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = DangerShader
	m.set_shader_parameter("rect", true)
	m.set_shader_parameter("size", Vector2(width, len))
	var dir := (b - a).normalized()
	var mid := (a + b) * 0.5
	# 쿼드의 UV.y 가 a(0) → b(1) 쪽이 되게: 로컬 -z 가 b 쪽
	var mi := add_mesh(q, m, Vector3(mid.x, y, mid.z), Basis(Vector3.UP, atan2(-dir.x, -dir.z)), parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 1.0, 0.05)
	create_tween().tween_property(mi, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return mi


## 점 p 가 a→b 직사각형(폭 width) 안인지 (높이 무시)
static func in_rect(p: Vector3, a: Vector3, b: Vector3, width: float, margin: float = 0.0) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var len := d.length()
	if len < 0.001:
		return false
	var u := d / len
	var q := Vector2(p.x - a.x, p.z - a.z)
	var along := q.dot(u)
	var side := absf(q.x * u.y - q.y * u.x)
	return along >= -margin and along <= len + margin and side <= width * 0.5 + margin


## 물보라 (흰 물방울이 튀었다 떨어짐)
func splash(pos: Vector3, amount: int = 40, power: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.1
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 2.5 * power
	p.initial_velocity_max = 5.0 * power
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	s.material = m
	p.mesh = s
	p.position = pos
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 먼지 · 나무 부스러기 튐
func debris(pos: Vector3, col: Color, amount: int = 18) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -16, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var b := BoxMesh.new()
	b.size = Vector3(0.14, 0.05, 0.08)
	b.material = std_mat(col, 0.8)
	p.mesh = b
	p.position = pos
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 미니게임용 크라켄 피부: 형광을 낮춰 젖은 문어 살갗처럼 (경고 때 glow 로 달아오르는 건 그대로)
static func skin_tone(m: ShaderMaterial) -> void:
	m.set_shader_parameter("neon", Color(0.13, 0.42, 0.17))
	m.set_shader_parameter("vein_col", Color(0.3, 0.44, 0.12))
	m.set_shader_parameter("deep", Color(0.03, 0.12, 0.06))
	m.set_shader_parameter("bio", 0.3)


## 보드와 같은 크라켄 촉수 (셰이더로 휘는 관). 돌려줌 {"root", "mat"}
func tentacle(length: float, radius: float, dir: Vector3) -> Dictionary:
	var tn: Dictionary = kit.make_tentacle(1, radius, length, dir)
	var m: ShaderMaterial = tn["mat"]
	m.set_shader_parameter("caustics", 0.0)
	m.set_shader_parameter("opacity", 0.96)
	# 미니게임에선 형광을 낮춰 실제 문어 · 오징어 같은 젖은 살갗 느낌으로
	skin_tone(m)
	world3.add_child(tn["root"])
	return tn


func pose_tentacle(m: ShaderMaterial, a: Array, b: Array, f: float) -> void:
	m.set_shader_parameter("pitch", lerpf(a[0], b[0], f))
	m.set_shader_parameter("curl", lerpf(a[1], b[1], f))
	m.set_shader_parameter("hook", lerpf(a[2], b[2], f))
	m.set_shader_parameter("tipback", lerpf(a[3], b[3], f))
	m.set_shader_parameter("wave", lerpf(a[4], b[4], f))
	m.set_shader_parameter("wtime", _t3)


## 통나무 뗏목 (반지름 R): 물에 잠긴 통나무 받침(가로질러) + 들쭉날쭉한 널빤지(사이 틈) + 통나무 자리마다 밧줄로 동여맴 + 못
func build_raft(parent: Node3D, R: float, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var log_cols := [Color(0.3, 0.21, 0.13), Color(0.27, 0.19, 0.12), Color(0.33, 0.23, 0.14)]
	var log_x := []
	for k in 5:
		var x := -R * 0.72 + k * R * 0.36
		log_x.append(x)
		var half := sqrt(maxf(R * R - x * x, 1.0)) - 0.15
		var cyl := CylinderMesh.new()
		var lr := rr.randf_range(0.36, 0.46)
		cyl.top_radius = lr
		cyl.bottom_radius = lr * 1.05
		cyl.height = half * 2.0
		cyl.radial_segments = 18
		add_mesh(cyl, wood_mat(log_cols[k % 3], Vector3(0, 0, 1), 0.55), Vector3(x, -0.5, rr.randf_range(-0.1, 0.1)), Basis(Vector3(1, 0, 0), PI / 2), parent)
		# 잘린 통나무 끝 (나이테 색)
		for sd: float in [-1.0, 1.0]:
			var cap := CylinderMesh.new()
			cap.top_radius = lr * 0.98
			cap.bottom_radius = lr * 0.98
			cap.height = 0.03
			add_mesh(cap, std_mat(Color(0.4, 0.3, 0.2), 0.95), Vector3(x, -0.5, sd * half), Basis(Vector3(1, 0, 0), PI / 2), parent)
	var cols := [Color(0.42, 0.32, 0.22), Color(0.46, 0.35, 0.24), Color(0.39, 0.29, 0.2), Color(0.44, 0.33, 0.22), Color(0.36, 0.27, 0.19)]
	var nail := std_mat(Color(0.26, 0.2, 0.16), 0.7, 0.4)
	var nail_m := CylinderMesh.new()
	nail_m.top_radius = 0.018
	nail_m.bottom_radius = 0.018
	nail_m.height = 0.02
	nail_m.radial_segments = 6
	var z := -R + 0.25
	var idx := 0
	while z < R - 0.2:
		var w := rr.randf_range(0.34, 0.44)
		var half := sqrt(maxf(R * R - z * z, 0.5)) + rr.randf_range(-0.3, 0.12)
		var off := rr.randf_range(-0.12, 0.12)
		var tilt := rr.randf_range(-0.015, 0.015)
		box(Vector3(half * 2.0, 0.14, w), wood_mat(cols[idx % cols.size()], Vector3(1, 0, 0), 0.1),
			Vector3(off, -0.07 + rr.randf_range(-0.012, 0.012), z), Basis(Vector3.UP, tilt) * Basis(Vector3(1, 0, 0), rr.randf_range(-0.02, 0.02)), parent)
		for x: float in log_x:
			if absf(x - off) < half - 0.15 and rr.randf() < 0.8:
				for dz: float in [-w * 0.28, w * 0.28]:
					add_mesh(nail_m, nail, Vector3(x + rr.randf_range(-0.05, 0.05), 0.005, z + dz), Basis(), parent)
		z += w + rr.randf_range(0.03, 0.06)
		idx += 1
	# 가장자리 통나무 끝을 감은 밧줄 (물 위로 보이는 곳만)
	var rope := std_mat(Color(0.58, 0.48, 0.32), 0.95)
	for x: float in log_x:
		for sd: float in [-1.0, 1.0]:
			var zz: float = sd * (sqrt(maxf(R * R - x * x, 1.0)) - 0.45)
			for k in 3:
				var t := TorusMesh.new()
				t.inner_radius = 0.38
				t.outer_radius = 0.45
				t.rings = 20
				add_mesh(t, rope, Vector3(x, -0.5, zz - sd * k * 0.08), Basis(Vector3(1, 0, 0), PI / 2), parent)


## 갑판 잡동사니: 나무 상자 · 감긴 밧줄 · 양동이 · 그물 더미 (pos 들에)
func deck_clutter(parent: Node3D, spots: Array, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var rope := std_mat(Color(0.62, 0.5, 0.33), 0.95)
	var iron := std_mat(Color(0.2, 0.19, 0.18), 0.5, 0.7)
	for k in spots.size():
		var p: Vector3 = spots[k]
		match k % 4:
			0:   # 나무 상자 (판자 + 모서리 각목)
				var c := Node3D.new()
				c.position = p
				c.rotation.y = rr.randf_range(-0.6, 0.6)
				parent.add_child(c)
				var sz := rr.randf_range(0.55, 0.75)
				box(Vector3(sz, sz, sz), wood_mat(Color(0.55, 0.42, 0.27), Vector3(1, 0, 0), 0.1), Vector3(0, sz * 0.5, 0), Basis(), c)
				var edge := wood_mat(Color(0.4, 0.29, 0.18), Vector3(0, 1, 0), 0.1)
				for sx: float in [-1.0, 1.0]:
					for sz2: float in [-1.0, 1.0]:
						box(Vector3(0.07, sz + 0.02, 0.07), edge, Vector3(sx * sz * 0.5, sz * 0.5, sz2 * sz * 0.5), Basis(), c)
				box(Vector3(sz + 0.02, 0.06, 0.07), edge, Vector3(0, sz * 0.5, sz * 0.5), Basis(Vector3(0, 0, 1), 0.78), c)
			1:   # 감긴 밧줄
				for j in 5:
					var t := TorusMesh.new()
					t.inner_radius = 0.18 + j * 0.035
					t.outer_radius = 0.28 + j * 0.035
					t.rings = 24
					add_mesh(t, rope, p + Vector3(0, 0.05 + j * 0.075, 0), Basis(), parent)
			2:   # 양동이 (나무 + 쇠테)
				var b := CylinderMesh.new()
				b.top_radius = 0.22
				b.bottom_radius = 0.18
				b.height = 0.36
				add_mesh(b, wood_mat(Color(0.5, 0.36, 0.22), Vector3(0, 1, 0), 0.1), p + Vector3(0, 0.18, 0), Basis(), parent)
				for hy: float in [0.08, 0.3]:
					var band := CylinderMesh.new()
					band.top_radius = 0.19 + hy * 0.1
					band.bottom_radius = band.top_radius
					band.height = 0.03
					add_mesh(band, iron, p + Vector3(0, hy, 0), Basis(), parent)
			3:   # 그물 더미 (울퉁불퉁한 그물 + 찌)
				var net := std_mat(Color(0.35, 0.42, 0.36), 0.95)
				for j in 3:
					var sp := SphereMesh.new()
					sp.radius = 0.35
					sp.height = 0.3
					add_mesh(sp, net, p + Vector3(rr.randf_range(-0.2, 0.2), 0.08, rr.randf_range(-0.2, 0.2)), Basis(), parent).scale = Vector3(1.2, 0.6, 1.0)
				for j in 3:
					var fl := SphereMesh.new()
					fl.radius = 0.07
					fl.height = 0.14
					add_mesh(fl, std_mat(Color(0.9, 0.35, 0.2), 0.5), p + Vector3(rr.randf_range(-0.3, 0.3), 0.2, rr.randf_range(-0.3, 0.3)), Basis(), parent)


## 배 선체 메시: 뱃머리는 뾰족하고 고물은 뭉툭, 단면은 둥근 V, 갑판선(sheer)은 앞뒤로 휨. +X = 뱃머리
static func hull_mesh(L: float, B: float, D: float, stations: int = 18, ring: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := []
	for i in stations + 1:
		var t := float(i) / stations                       # 0 = 고물, 1 = 뱃머리
		var x := (t - 0.5) * L
		var w := B * 0.5 * (pow(sin(PI * clampf(t * 0.82 + 0.18, 0.0, 1.0)), 0.55))
		if t > 0.97:
			w *= (1.0 - t) / 0.03 * 0.3 + 0.0
		var sheer := 0.18 * D * pow(absf(t - 0.45) * 1.8, 2.0)
		var depth := D * (0.55 + 0.45 * sin(PI * clampf(t * 0.9 + 0.05, 0.0, 1.0)))
		var row := []
		for j in ring + 1:
			var a := -PI * 0.5 + PI * float(j) / ring             # 좌현 갑판선 → 용골 → 우현 갑판선
			var ca := cos(a)
			var sa := sin(a)
			var yy := sheer - depth * pow(ca, 1.35)
			var zz := w * signf(sa) * pow(absf(sa), 0.7)
			row.append(Vector3(x, yy, zz))
		rows.append(row)
	for i in stations:
		for j in ring:
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i + 1][j]
			var c: Vector3 = rows[i + 1][j + 1]
			var d: Vector3 = rows[i][j + 1]
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	# 고물 판 (transom)
	var r0: Array = rows[0]
	var cen := Vector3(r0[0].x, r0[0].y, 0)
	for j in ring:
		st.add_vertex(cen); st.add_vertex(r0[j]); st.add_vertex(r0[j + 1])
	st.generate_normals()
	return st.commit()


## 갑판 윤곽(위에서 본 폭) — hull_mesh 와 같은 식
static func hull_half_width(t: float, B: float) -> float:
	var w := B * 0.5 * pow(sin(PI * clampf(t * 0.82 + 0.18, 0.0, 1.0)), 0.55)
	if t > 0.97:
		w *= (1.0 - t) / 0.03 * 0.3
	return w


## 작은 돛단배 한 척: 선체 · 갑판 널 · 뱃전 난간 · 돛대 · 붐 · 삼각돛 · 밧줄 · 깃발. 반환 = 루트 (원점 = 수면)
func sailboat(sail_col: Color, parent: Node3D, L: float = 2.6, B: float = 1.0, D: float = 0.55) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var hull_m := wood_mat(Color(0.36, 0.22, 0.13), Vector3(1, 0, 0), 0.25)
	var hull := MeshInstance3D.new()
	hull.mesh = hull_mesh(L, B, D)
	hull.material_override = hull_m
	hull.position = Vector3(0, 0.22, 0)
	root.add_child(hull)
	# 갑판 널 (선체 폭에 맞춰)
	var deck := wood_mat(Color(0.6, 0.46, 0.3), Vector3(1, 0, 0), 0.05)
	var n := 9
	for i in n:
		var t0 := (float(i) + 0.5) / n * 0.92 + 0.02
		var w := hull_half_width(t0, B) * 2.0 * 0.9
		if w > 0.05:
			box(Vector3(L / n * 0.98, 0.04, w), deck, Vector3((t0 - 0.5) * L, 0.2, 0), Basis(), root)
	# 뱃전 난간
	var rail := wood_mat(Color(0.28, 0.17, 0.1), Vector3(1, 0, 0), 0.1)
	for sd: float in [-1.0, 1.0]:
		for i in 12:
			var ta := float(i) / 12.0 * 0.96
			var tb := float(i + 1) / 12.0 * 0.96
			var pa := Vector3((ta - 0.5) * L, 0.26 + 0.18 * D * pow(absf(ta - 0.45) * 1.8, 2.0), sd * hull_half_width(ta, B))
			var pb := Vector3((tb - 0.5) * L, 0.26 + 0.18 * D * pow(absf(tb - 0.45) * 1.8, 2.0), sd * hull_half_width(tb, B))
			var seg := pb - pa
			var bb := Basis.looking_at(seg.normalized(), Vector3.UP)
			box(Vector3(0.06, 0.08, seg.length() + 0.02), rail, (pa + pb) * 0.5, bb, root)
	# 돛대 · 붐
	var mast_x := L * 0.1
	var mast := CylinderMesh.new()
	mast.top_radius = 0.035
	mast.bottom_radius = 0.05
	mast.height = L * 0.95
	add_mesh(mast, rail, Vector3(mast_x, 0.2 + L * 0.475, 0), Basis(), root)
	var boom := CylinderMesh.new()
	boom.top_radius = 0.03
	boom.bottom_radius = 0.03
	boom.height = L * 0.55
	add_mesh(boom, rail, Vector3(mast_x - L * 0.27, 0.62, 0), Basis(Vector3(0, 0, 1), PI / 2), root)
	# 삼각돛 (살짝 바람에 부푼 면)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(mast_x, 0.2 + L * 0.9, 0)
	var foot0 := Vector3(mast_x, 0.68, 0)
	var foot1 := Vector3(mast_x - L * 0.52, 0.68, 0)
	var g := 6
	var pts := []
	for i in g + 1:
		var row := []
		for j in g + 1 - i:
			var u := float(j) / g
			var v := float(i) / g
			var pp := foot0 + (foot1 - foot0) * u + (top - foot0) * v
			pp.z += sin(PI * u / maxf(1.0 - v, 0.001) * (1.0 - v)) * sin(PI * minf(v + 0.1, 1.0)) * 0.16
			row.append(pp)
		pts.append(row)
	for i in g:
		for j in g - i:
			st.add_vertex(pts[i][j]); st.add_vertex(pts[i][j + 1]); st.add_vertex(pts[i + 1][j])
			if j + 1 < pts[i + 1].size():
				st.add_vertex(pts[i][j + 1]); st.add_vertex(pts[i + 1][j + 1]); st.add_vertex(pts[i + 1][j])
	st.generate_normals()
	var sail_m := std_mat(sail_col.lerp(Color(0.95, 0.92, 0.84), 0.45), 0.9)
	sail_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sail := MeshInstance3D.new()
	sail.mesh = st.commit()
	sail.material_override = sail_m
	root.add_child(sail)
	# 버팀줄 (돛대 꼭대기 → 뱃머리 / 고물)
	var rope := std_mat(Color(0.55, 0.47, 0.33), 0.9)
	for end: Vector3 in [Vector3(L * 0.48, 0.3, 0), Vector3(-L * 0.46, 0.3, 0.0)]:
		var a := top + Vector3(0, 0.02, 0)
		var seg := end - a
		var c := CylinderMesh.new()
		c.top_radius = 0.008
		c.bottom_radius = 0.008
		c.height = seg.length()
		c.radial_segments = 4
		var y := seg.normalized()
		var x := y.cross(Vector3(0, 0, 1)).normalized()
		add_mesh(c, rope, (a + end) * 0.5, Basis(x, y, x.cross(y)), root)
	# 돛대 꼭대기 깃발
	var flag := std_mat(sail_col, 0.7)
	flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	box(Vector3(0.3, 0.16, 0.01), flag, Vector3(mast_x - 0.17, 0.2 + L * 0.93, 0), Basis(), root)
	return root


## 돌림체 메시: prof = [(반지름, 높이), ...] 아래→위
static func lathe_mesh(prof: Array, seg: int = 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := Vector3(sin(t0) * a.x, a.y, cos(t0) * a.x)
			var p01 := Vector3(sin(t1) * a.x, a.y, cos(t1) * a.x)
			var p10 := Vector3(sin(t0) * b.x, b.y, cos(t0) * b.x)
			var p11 := Vector3(sin(t1) * b.x, b.y, cos(t1) * b.x)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
	st.generate_normals()
	return st.commit()


## 배불뚝이 나무통: 가운데가 불룩한 몸통 · 쑥 들어간 뚜껑 · 쇠테 4줄. 원점 = 바닥 가운데
func barrel(parent: Node3D, pos: Vector3, r: float, h: float, col := Color(0.44, 0.29, 0.17)) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var prof := []
	for i in 13:
		var y := float(i) / 12.0
		prof.append(Vector2(r * (0.84 + 0.16 * sin(PI * y)), y * h))
	prof.append(Vector2(r * 0.8, h))
	prof.append(Vector2(r * 0.8, h - 0.04))
	prof.append(Vector2(0.0, h - 0.04))
	add_mesh(lathe_mesh(prof, 22), wood_mat(col, Vector3(0, 1, 0), 0.12), Vector3.ZERO, Basis(), root)
	# 뚜껑 판 이음 (진한 선 두 줄)
	var lid_line := std_mat(col.darkened(0.5), 0.9)
	for dx: float in [-r * 0.27, r * 0.27]:
		box(Vector3(0.015, 0.01, r * 1.5), lid_line, Vector3(dx, h - 0.035, 0), Basis(), root)
	var iron := std_mat(Color(0.17, 0.16, 0.15), 0.45, 0.75)
	for hy: float in [0.07, 0.3, 0.7, 0.93]:
		var band := CylinderMesh.new()
		var rb := r * (0.84 + 0.16 * sin(PI * hy)) + 0.012
		band.top_radius = rb
		band.bottom_radius = rb
		band.height = h * 0.045
		band.radial_segments = 22
		add_mesh(band, iron, Vector3(0, h * hy, 0), Basis(), root)
	return root


## 횃불 기둥: 나무 장대 · 쇠 바구니 · 일렁이는 불꽃(입자) · 깜빡이는 불빛
func torch(parent: Node3D, pos: Vector3, h: float = 1.8) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = h
	add_mesh(pole, wood_mat(Color(0.33, 0.22, 0.14), Vector3(0, 1, 0), 0.2), Vector3(0, h * 0.5, 0), Basis(), root)
	var iron := std_mat(Color(0.14, 0.13, 0.12), 0.5, 0.75)
	var cup := CylinderMesh.new()
	cup.top_radius = 0.2
	cup.bottom_radius = 0.08
	cup.height = 0.22
	cup.radial_segments = 8
	add_mesh(cup, iron, Vector3(0, h + 0.08, 0), Basis(), root)
	var coal := SphereMesh.new()
	coal.radius = 0.16
	coal.height = 0.14
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.2, 0.08, 0.03)
	cm.emission_enabled = true
	cm.emission = Color(1.0, 0.35, 0.08)
	cm.emission_energy_multiplier = 2.0
	add_mesh(coal, cm, Vector3(0, h + 0.18, 0), Basis(), root)
	root.add_child(_flame(Vector3(0, h + 0.22, 0), 0.17))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.28)
	l.light_energy = 2.0
	l.omni_range = 6.0
	l.shadow_enabled = false
	l.position = Vector3(0, h + 0.5, 0)
	root.add_child(l)
	_flickers.append({"light": l, "base": 2.0, "ph": randf() * TAU})
	return root


## 불꽃 입자 (위로 날름대며 사라지는 주황 → 빨강 빛 덩어리)
func _flame(pos: Vector3, size_: float) -> CPUParticles3D:
	var f := CPUParticles3D.new()
	f.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(size_, size_ * 1.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	q.material = m
	f.mesh = q
	f.local_coords = true
	f.amount = 18
	f.lifetime = 0.45
	f.direction = Vector3.UP
	f.spread = 12.0
	f.initial_velocity_min = 0.7
	f.initial_velocity_max = 1.3
	f.gravity = Vector3.ZERO
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = size_ * 0.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.8))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.1))
	f.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.7, 0.3, 0.55))
	g.add_point(0.35, Color(1.0, 0.4, 0.08, 0.45))
	g.set_color(g.get_point_count() - 1, Color(0.5, 0.1, 0.02, 0.0))
	f.color_ramp = g
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return f


var _dot_tex: Texture2D


## 가장자리가 부드러운 동그라미 텍스처 (불꽃 · 연기용)
func _soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	_dot_tex = gt
	return gt


## 쇠 등불: 받침 · 네 모서리 기둥 · 빛나는 유리 · 뾰족 지붕 · 고리
func lantern(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var iron := std_mat(Color(0.13, 0.12, 0.11), 0.45, 0.8)
	box(Vector3(0.3, 0.04, 0.3), iron, Vector3(0, 0.02, 0), Basis(), root)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(Vector3(0.03, 0.32, 0.03), iron, Vector3(sx * 0.12, 0.2, sz * 0.12), Basis(), root)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.8, 0.5)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.6, 0.25)
	glass.emission_energy_multiplier = 2.5
	box(Vector3(0.21, 0.28, 0.21), glass, Vector3(0, 0.2, 0), Basis(), root)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 0.22
	roof.height = 0.14
	roof.radial_segments = 4
	add_mesh(roof, iron, Vector3(0, 0.43, 0), Basis(Vector3.UP, PI / 4), root)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.04
	ring.outer_radius = 0.06
	add_mesh(ring, iron, Vector3(0, 0.54, 0), Basis(Vector3(1, 0, 0), PI / 2), root)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.66, 0.35)
	l.light_energy = 1.4
	l.omni_range = 6.0
	l.position = Vector3(0, 0.25, 0)
	root.add_child(l)
	_flickers.append({"light": l, "base": 1.4, "ph": randf() * TAU})
	return root


## 먼 수평선의 열대 섬: 모래 띠 · 바위 · 짙은 숲 덩어리 · 야자수 몇 그루
func island(pos: Vector3, r: float, h: float, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var root := Node3D.new()
	root.position = pos
	world3.add_child(root)
	var sand := CylinderMesh.new()
	sand.top_radius = r * 0.92
	sand.bottom_radius = r * 1.0
	sand.height = h * 0.05
	add_mesh(sand, std_mat(Color(0.66, 0.6, 0.46), 0.95), Vector3(0, h * 0.02, 0), Basis(), root)
	var rock := std_mat(Color(0.32, 0.3, 0.28), 0.9)
	var green := std_mat(Color(0.14, 0.27, 0.12), 0.95)
	var green2 := std_mat(Color(0.18, 0.33, 0.14), 0.95)
	for k in 5:
		var s := SphereMesh.new()
		var rk := r * rr.randf_range(0.35, 0.6)
		s.radius = rk
		s.height = rk * 2.0
		var off := Vector3(rr.randf_range(-r * 0.45, r * 0.45), 0, rr.randf_range(-r * 0.3, r * 0.3))
		var hh := h * (1.25 if k == 1 else rr.randf_range(0.45, 0.85))
		if k == 1:
			off = Vector3(rr.randf_range(-r * 0.15, r * 0.15), 0, 0)
		add_mesh(s, rock if k == 0 else (green if k % 2 == 0 else green2), off + Vector3(0, 0.0, 0), Basis(), root).scale = Vector3(1.0, hh / rk, 1.0)
	# 야자수
	var trunk := std_mat(Color(0.42, 0.33, 0.22), 0.9)
	for k in 6:
		var base := Vector3(rr.randf_range(-r * 0.85, r * 0.85), h * 0.08, rr.randf_range(r * 0.2, r * 0.7))
		var th := h * rr.randf_range(0.55, 0.85)
		var lean := rr.randf_range(-0.35, 0.35)
		var top := base + Vector3(sin(lean) * th, cos(lean) * th, 0)
		var c := CylinderMesh.new()
		c.top_radius = h * 0.012
		c.bottom_radius = h * 0.022
		c.height = th
		add_mesh(c, trunk, (base + top) * 0.5, Basis(Vector3(0, 0, 1), -lean), root)
		for j in 7:
			var a := TAU * j / 7.0
			var fd := Vector3(cos(a), -0.35, sin(a)).normalized()
			var fl := h * 0.28
			var bb := Basis.looking_at(fd, Vector3.UP)
			box(Vector3(fl * 0.25, h * 0.008, fl), green2, top + fd * fl * 0.5, bb, root)


## 물 위에 떠다니는 나무통 · 널조각 · 부표 (뗏목 둘레 r0 ~ r1)
func sea_debris(count: int, r0: float, r1: float, y: float, seed_: int, center := Vector3.ZERO) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	for k in count:
		var a := rr.randf() * TAU
		var d := rr.randf_range(r0, r1)
		var n := Node3D.new()
		world3.add_child(n)
		match k % 3:
			0:
				var b := barrel(n, Vector3(-0.4, 0, 0), 0.32, 0.8, Color(0.38, 0.26, 0.16))
				b.rotation.z = -PI / 2
			1:
				box(Vector3(rr.randf_range(1.2, 2.0), 0.1, 0.32), wood_mat(Color(0.38, 0.28, 0.19), Vector3(1, 0, 0), 0.5), Vector3.ZERO, Basis(), n)
			2:
				var s := SphereMesh.new()
				s.radius = 0.28
				s.height = 0.5
				add_mesh(s, std_mat(Color(0.85, 0.25, 0.18), 0.4), Vector3.ZERO, Basis(), n)
				box(Vector3(0.6, 0.06, 0.06), std_mat(Color(0.95, 0.95, 0.9), 0.5), Vector3(0, 0.12, 0), Basis(), n)
		var base := center + Vector3(cos(a) * d, y, sin(a) * d)
		n.position = base
		_floaters.append({"node": n, "base": base, "ph": rr.randf() * TAU, "yaw": rr.randf() * TAU})


## 하늘을 빙빙 도는 갈매기들
func gulls(count: int, center: Vector3, radius: float, h: float, seed_: int) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var white := std_mat(Color(0.95, 0.95, 0.93), 0.7)
	var grey := std_mat(Color(0.55, 0.57, 0.6), 0.7)
	var beak := std_mat(Color(0.95, 0.7, 0.2), 0.5)
	for k in count:
		var n := Node3D.new()
		world3.add_child(n)
		var body := SphereMesh.new()
		body.radius = 0.12
		body.height = 0.24
		add_mesh(body, white, Vector3.ZERO, Basis(), n).scale = Vector3(1.0, 0.9, 2.6)
		var bk := CylinderMesh.new()
		bk.top_radius = 0.0
		bk.bottom_radius = 0.035
		bk.height = 0.12
		add_mesh(bk, beak, Vector3(0, 0.02, -0.36), Basis(Vector3(1, 0, 0), -PI / 2), n)
		var wl := Node3D.new()
		var wr := Node3D.new()
		n.add_child(wl)
		n.add_child(wr)
		box(Vector3(0.7, 0.02, 0.2), white, Vector3(-0.36, 0, 0), Basis(), wl)
		box(Vector3(0.28, 0.021, 0.14), grey, Vector3(-0.62, 0, 0.02), Basis(), wl)
		box(Vector3(0.7, 0.02, 0.2), white, Vector3(0.36, 0, 0), Basis(), wr)
		box(Vector3(0.28, 0.021, 0.14), grey, Vector3(0.62, 0, 0.02), Basis(), wr)
		n.scale = Vector3.ONE * rr.randf_range(0.9, 1.2)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gulls.append({"node": n, "wl": wl, "wr": wr, "c": center + Vector3(rr.randf_range(-4, 4), 0, rr.randf_range(-4, 4)),
			"r": radius * rr.randf_range(0.7, 1.2), "h": h + rr.randf_range(-1.5, 2.0), "sp": rr.randf_range(0.25, 0.4) * (1.0 if rr.randf() < 0.6 else -1.0), "ph": rr.randf() * TAU})


## 하늘의 뭉게구름 (빌보드) — 수평선 둘레에
func sky_clouds(count: int, dist: float, h: float, center: Vector3 = Vector3.ZERO, arc: Vector2 = Vector2(-PI, PI)) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 21
	for k in count:
		var a := lerpf(arc.x, arc.y, (k + rr.randf()) / count)
		var d := dist * rr.randf_range(0.8, 1.2)
		var q := QuadMesh.new()
		var w := rr.randf_range(28.0, 60.0) * dist / 160.0
		q.size = Vector2(w, w * rr.randf_range(0.42, 0.6))
		var m := ShaderMaterial.new()
		m.shader = CloudShader
		m.set_shader_parameter("top_col", Color(1.0, 0.98, 0.96))
		m.set_shader_parameter("shade_col", Color(0.62, 0.7, 0.8))
		m.set_shader_parameter("seed", rr.randf() * 10.0)
		m.set_shader_parameter("opacity", rr.randf_range(0.7, 0.95))
		var mi := add_mesh(q, m, center + Vector3(sin(a) * d, h + rr.randf_range(-0.2, 0.5) * h, -cos(a) * d))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 물속 분위기: 떠다니는 알갱이 · 비스듬한 빛줄기 · 물고기 떼 · 해파리
func underwater_fx(half: float, top: float = 12.0) -> void:
	var snow := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 4
	sm.rings = 2
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 1.0, 0.95, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	snow.mesh = sm
	snow.amount = 500
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(half, top * 0.5, half)
	snow.position = Vector3(0, top * 0.5, 0)
	snow.gravity = Vector3(0, -0.03, 0)
	snow.initial_velocity_max = 0.15
	snow.spread = 180.0
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world3.add_child(snow)
	var rr := RandomNumberGenerator.new()
	rr.seed = 4
	for k in 8:
		var q := QuadMesh.new()
		q.size = Vector2(rr.randf_range(2.0, 4.5), 30.0)
		var m := ShaderMaterial.new()
		m.shader = RayShader
		m.set_shader_parameter("phase", rr.randf() * TAU)
		m.set_shader_parameter("strength", rr.randf_range(0.012, 0.026))
		var p := Vector3(rr.randf_range(-half, half), top, rr.randf_range(-half, half * 0.4))
		var b := Basis(Vector3.UP, rr.randf_range(-0.5, 0.5)) * Basis(Vector3(0, 0, 1), deg_to_rad(18))
		add_mesh(q, m, p, b).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func fish_school(center: Vector3, radius: float, count: int, speed: float, length: float, a: Color, b: Color) -> void:
	var before := kit.get_child_count()
	kit._fish_school(center, radius, count, speed, length, a, b)
	for n in kit.get_children().slice(before):
		kit.remove_child(n)
		world3.add_child(n)


func jelly(p: Vector3, c: Color) -> void:
	var before := kit.get_child_count()
	kit._jelly(p, c)
	for n in kit.get_children().slice(before):
		kit.remove_child(n)
		world3.add_child(n)


## 보물상자 (널빤지 몸통 · 쇠띠 · 모서리 쇠 · 자물쇠판 · 둥근 뚜껑). 크기 w × h × d, 돌려줌 {root, lid}
func treasure_chest(w: float, h: float, d: float, parent: Node3D = null) -> Dictionary:
	var root := Node3D.new()
	(parent if parent else world3).add_child(root)
	var cols := [Color(0.55, 0.34, 0.19), Color(0.6, 0.38, 0.21), Color(0.5, 0.31, 0.17)]
	var iron := std_mat(Color(0.32, 0.3, 0.28), 0.45, 0.55)
	var gold := std_mat(Color(0.92, 0.7, 0.3), 0.28, 0.95)
	# 몸통: 가로 널 여러 장
	var rows := 4
	for k in rows:
		var m := wood_mat(cols[k % 3], Vector3(1, 0, 0), 0.25)
		box(Vector3(w, h / rows - 0.012, d), m, Vector3(0, h / rows * (k + 0.5), 0), Basis(), root)
	# 쇠띠 (세로) · 모서리 쇠
	for x: float in [-w * 0.32, w * 0.32]:
		box(Vector3(w * 0.07, h + 0.02, d + 0.03), iron, Vector3(x, h * 0.5, 0), Basis(), root)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(Vector3(w * 0.09, h + 0.03, w * 0.09), iron, Vector3(sx * (w * 0.5 - w * 0.035), h * 0.5, sz * (d * 0.5 - w * 0.035)), Basis(), root)
	# 리벳
	var rv := SphereMesh.new()
	rv.radius = w * 0.016
	rv.height = w * 0.032
	rv.radial_segments = 8
	rv.rings = 4
	for x: float in [-w * 0.32, w * 0.32]:
		for k in 3:
			add_mesh(rv, iron, Vector3(x, h * (0.2 + k * 0.3), d * 0.5 + 0.018), Basis(), root)
	# 자물쇠판 + 열쇠구멍
	box(Vector3(w * 0.16, h * 0.32, 0.03), gold, Vector3(0, h * 0.7, d * 0.5 + 0.02), Basis(), root)
	box(Vector3(w * 0.025, h * 0.1, 0.02), std_mat(Color(0.02, 0.02, 0.02), 0.9), Vector3(0, h * 0.66, d * 0.5 + 0.035), Basis(), root)
	# 뚜껑 (뒤 경첩, 반원통: 널 + 쇠띠)
	var lid := Node3D.new()
	lid.position = Vector3(0, h, -d * 0.5)
	root.add_child(lid)
	var rr := d * 0.5
	var planks := 6
	for k in planks:
		var a0 := PI * k / planks
		var a1 := PI * (k + 1) / planks
		var am := (a0 + a1) * 0.5
		var pos := Vector3(0, sin(am) * rr * 0.62, d * 0.5 - cos(am) * rr)
		var m := wood_mat(cols[(k + 1) % 3], Vector3(1, 0, 0), 0.25)
		var nrm := Vector2(-cos(am), sin(am) * 0.62).normalized()   # (z, y) 바깥쪽
		box(Vector3(w, 0.05, rr * (a1 - a0) * 1.04), m, pos, Basis(Vector3(1, 0, 0), atan2(nrm.x, nrm.y)), lid)
	# 뚜껑 양끝 마구리 (나무) + 쇠띠 둘
	var cap_m := wood_mat(cols[2], Vector3(0, 1, 0), 0.25)
	for x: float in [-w * 0.5 + 0.03, w * 0.5 - 0.03]:
		var cap := CylinderMesh.new()
		cap.top_radius = rr * 0.98
		cap.bottom_radius = rr * 0.98
		cap.height = 0.06
		cap.radial_segments = 24
		add_mesh(cap, cap_m, Vector3(x, 0, d * 0.5), Basis(Vector3(0, 0, 1), PI / 2), lid).scale = Vector3(0.62, 1.0, 1.0)
	for x: float in [-w * 0.32, w * 0.32]:
		var band := CylinderMesh.new()
		band.top_radius = rr * 1.03
		band.bottom_radius = rr * 1.03
		band.height = w * 0.06
		band.radial_segments = 24
		var bm := add_mesh(band, iron, Vector3(x, 0, d * 0.5), Basis(Vector3(0, 0, 1), PI / 2), lid)
		bm.scale = Vector3(0.64, 1.0, 1.0)
	return {"root": root, "lid": lid, "gold": gold}


## 굵기가 변하는 촉수를 점들(pts)을 지나는 곡선으로 (보드 · 배와 같은 셰이더, 빨판은 belly 쪽). parent 기준 좌표
func spline_tentacle(pts: Array, r0: float, belly: Callable, tip := 0.1, parent: Node3D = null) -> MeshInstance3D:
	var dense: Array = kit._catmull(pts, 14)
	var cum := [0.0]
	for i in range(1, dense.size()):
		cum.append(float(cum[i - 1]) + ((dense[i] as Vector3) - (dense[i - 1] as Vector3)).length())
	var total: float = cum[cum.size() - 1]
	var at := func(d: float) -> Vector3:
		var j := 0
		while j < dense.size() - 2 and float(cum[j + 1]) < d:
			j += 1
		var f := (d - float(cum[j])) / maxf(float(cum[j + 1]) - float(cum[j]), 0.0001)
		return (dense[j] as Vector3).lerp(dense[j + 1], clampf(f, 0.0, 1.0))
	var n := 160
	var rad := 18
	var P := []
	var T := []
	for i in n + 1:
		P.append(at.call(total * i / n))
	for i in n + 1:
		T.append(((P[mini(i + 1, n)] as Vector3) - (P[maxi(i - 1, 0)] as Vector3)).normalized())
	var N := []
	var prev_n := Vector3.ZERO
	for i in n + 1:
		var t: Vector3 = T[i]
		var h: Vector3 = belly.call(P[i])
		var nn := h - t * h.dot(t)
		if nn.length() < 0.05:
			nn = prev_n
		nn = nn.normalized()
		if prev_n != Vector3.ZERO:
			nn = prev_n.lerp(nn, 0.35).normalized()
			nn = (nn - t * nn.dot(t)).normalized()
		N.append(nn)
		prev_n = nn
	var r_at := func(u: float) -> float: return r0 * lerpf(1.0, tip, pow(u, 0.85))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n + 1:
		var u := float(i) / n
		var t: Vector3 = T[i]
		var nn: Vector3 = N[i]
		var bb := t.cross(nn)
		var r: float = r_at.call(u)
		for k in rad + 1:
			var a := float(k) / rad * TAU
			var d := bb * sin(a) + nn * cos(a)
			st.set_normal(d)
			st.set_uv(Vector2(float(k) / rad, u))
			st.set_uv2(Vector2(0, 0))
			st.add_vertex((P[i] as Vector3) + d * r)
	var wv := rad + 1
	for i in n:
		for k in rad:
			var i0 := i * wv + k
			st.add_index(i0); st.add_index(i0 + wv + 1); st.add_index(i0 + 1)
			st.add_index(i0); st.add_index(i0 + wv); st.add_index(i0 + wv + 1)
	var m := ShaderMaterial.new()
	m.shader = BoardWorld.KrakenArmShader
	m.set_shader_parameter("spline_mode", true)
	m.set_shader_parameter("arm_len", total)
	m.set_shader_parameter("radius", r0)
	m.set_shader_parameter("tip", tip)
	m.set_shader_parameter("opacity", 0.97)
	m.set_shader_parameter("pattern_scale", 1.6 / maxf(r0, 0.3))
	skin_tone(m)
	var mi := add_mesh(st.commit(), m, Vector3.ZERO, Basis(), parent)
	# 빨판 두 줄 (배 쪽, 엇갈려서)
	var xs := []
	var cs := []
	var u := 0.04
	var row := 0
	while u < 0.97:
		var ang := (0.42 if row % 2 == 0 else -0.42) + randf_range(-0.03, 0.03)
		var fi := u * n
		var i := int(fi)
		var t: Vector3 = T[i]
		var nn: Vector3 = N[i]
		var bb := t.cross(nn)
		var r: float = r_at.call(u)
		var nd := (bb * sin(ang) + nn * cos(ang)).normalized()
		var side := t.cross(nd).normalized()
		var sz := r * 0.3 * randf_range(0.92, 1.06)
		var c: Vector3 = (P[i] as Vector3).lerp(P[mini(i + 1, n)], fi - i) + nd * r
		xs.append(Transform3D(Basis(side * sz, nd * sz, t * sz), c))
		cs.append(Color(u, ang, 0.3, 0.0))
		u += r * 0.46 / total
		row += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = kit._sucker_mesh()
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_custom_data(k, cs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mi.add_child(mmi)
	return mi


## 상자(가로 hw*2 × 세로 hd*2) 둘레를 m 만큼 띄워 감는 길 (모서리는 둥글게). 오른쪽 면 가운데에서 s=0, 위에서 볼 때 반시계.
## s0 에서 시작해 length 만큼, 높이는 y0 → y1. 돌려줌: 점 목록
static func wrap_path(hw: float, hd: float, m: float, s0: float, length: float, y0: float, y1: float, step: float = 0.22) -> Array:
	var seg := [hd * 2.0, PI * 0.5 * m, hw * 2.0, PI * 0.5 * m, hd * 2.0, PI * 0.5 * m, hw * 2.0, PI * 0.5 * m]
	var per := 0.0
	for v in seg:
		per += v
	var at := func(s: float) -> Vector2:
		s = fposmod(s + hd, per)      # 오른쪽 면 맨 뒤(-z)에서부터 재기
		var x := 0.0
		var z := 0.0
		for k in 8:
			var L: float = seg[k]
			if s <= L or k == 7:
				var f := s / maxf(L, 0.0001)
				match k:
					0: return Vector2(hw + m, -hd + s)
					1: return Vector2(hw + cos(f * PI * 0.5) * m, hd + sin(f * PI * 0.5) * m)
					2: return Vector2(hw - s, hd + m)
					3: return Vector2(-hw + cos(PI * 0.5 + f * PI * 0.5) * m, hd + sin(PI * 0.5 + f * PI * 0.5) * m)
					4: return Vector2(-hw - m, hd - s)
					5: return Vector2(-hw + cos(PI + f * PI * 0.5) * m, -hd + sin(PI + f * PI * 0.5) * m)
					6: return Vector2(-hw + s, -hd - m)
					7: return Vector2(hw + cos(PI * 1.5 + f * PI * 0.5) * m, -hd + sin(PI * 1.5 + f * PI * 0.5) * m)
			s -= L
		return Vector2(x, z)
	var out := []
	var cnt := maxi(2, int(absf(length) / step))
	for i in cnt + 1:
		var f := float(i) / cnt
		var q: Vector2 = at.call(s0 + length * f)
		out.append(Vector3(q.x, lerpf(y0, y1, f), q.y))
	return out


## 상자 표면을 따라 스멀스멀 감기는 길: 정규화 좌표 (x: -1..1 = 왼쪽..오른쪽 면, y: 0..1 = 바닥..뚜껑 이음새, z: -1..1 = 뒤..앞 면)
## 로 찍은 점들을 실제 표면 위 m 만큼 띄운 점으로 바꾸고, 모서리를 넘을 땐 둥글게 부풀려 넘어감. 살짝씩 울퉁불퉁 · 높낮이 흔들림
static func chest_path(hw: float, hd: float, h: float, y_base: float, m: float, way: Array, seed_: int = 1) -> Array:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_
	var out := []
	for w: Vector3 in way:
		var onx := absf(w.x) >= 0.999
		var onz := absf(w.z) >= 0.999
		var n := Vector3(signf(w.x) if onx else 0.0, 0.0, signf(w.z) if onz else 0.0)
		if n.length() < 0.5:
			n = Vector3(0, 1, 0)
		n = n.normalized()
		# 모서리에서는 조금 더 부풀어 둥글게 넘어감
		var mm := m * (1.25 if onx and onz else 1.0) + rr.randf_range(-0.03, 0.05) * m * 4.0
		var p := Vector3(clampf(w.x, -1, 1) * hw, y_base + w.y * h + rr.randf_range(-0.03, 0.03), clampf(w.z, -1, 1) * hd) + n * mm
		out.append(p)
	return out


## 보드의 크라켄 머리 (외투막 + 눈). 바다 멀리서 지켜보게
func kraken_head(pos: Vector3, scl: float, yaw: float = 0.0, tilt: float = -0.35) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.basis = (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)).scaled(Vector3.ONE * scl)
	world3.add_child(root)
	var bm := ShaderMaterial.new()
	bm.shader = KrakenBodyShader
	bm.set_shader_parameter("pattern_scale", 1.2)
	bm.set_shader_parameter("opacity", 1.0)
	skin_tone(bm)
	add_mesh(KRAKEN_BODY, bm, Vector3.ZERO, Basis(), root)
	var em := ShaderMaterial.new()
	em.shader = KrakenEyeShader
	for sd: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.36
		eye.height = 0.72
		eye.radial_segments = 32
		eye.rings = 16
		add_mesh(eye, em, Vector3(sd * 1.57, 0.74, 1.3), Basis(Vector3.UP, sd * 0.72), root)
	return root


## 촉수 내려치기 한 번: root(바닥 높이의 뿌리 자리)에서 솟아 → 뒤로 젖혔다가 → dir 쪽으로 쾅 눕고 → 들어감.
## 눕는 부분은 뿌리에서 0.23L ~ 0.68L, 바닥 위 0.55 m (셰이더 자세로 계산한 값). warn 초 뒤에 쾅.
## water_y 가 있으면 뿌리에 물보라, 없으면(물속 모래) 모래 먼지
func slam_tentacle(root: Vector3, dir: Vector3, length: float, warn: float, floor_y: float, water_y: float = NAN) -> void:
	root.y = floor_y + 0.55 - 0.25 * length
	var rad := clampf(0.3 + length * 0.04, 0.55, 0.8)
	var tn := tentacle(length, rad, dir)
	var node: Node3D = tn["root"]
	var m: ShaderMaterial = tn["mat"]
	m.set_shader_parameter("tip", 0.22)
	m.set_shader_parameter("hook_at", 0.2)
	m.set_shader_parameter("pattern_scale", 1.6 / rad)
	var straight := [0.0, 0.0, 0.0, 0.0, 0.15]
	var raised := [-0.25, 0.9, 0.0, -0.5, 0.25]
	var wound := [-0.6, 1.5, 0.0, -0.9, 0.1]
	var slammed := [0.5, 0.0, 1.2, 1.0, 0.0]
	pose_tentacle(m, straight, straight, 0.0)
	node.position = root + Vector3(0, -length, 0)
	var rise_t := minf(0.55, warn * 0.45)
	var wind_t := maxf(0.08, minf(0.4, warn - rise_t - 0.2))
	var t := create_tween()
	t.tween_property(node, "position:y", root.y, rise_t).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(func(f: float) -> void:
		pose_tentacle(m, straight, raised, smoothstep(0.35, 1.0, f))
		m.set_shader_parameter("glow", f * 0.35), 0.0, 1.0, rise_t)
	t.tween_method(func(f: float) -> void: pose_tentacle(m, raised, wound, f), 0.0, 1.0, wind_t).set_trans(Tween.TRANS_SINE)
	t.tween_interval(maxf(0.0, warn - rise_t - wind_t - 0.2))
	t.tween_method(func(f: float) -> void: pose_tentacle(m, wound, slammed, f * f), 0.0, 1.0, 0.2)
	t.tween_interval(0.55)
	t.tween_method(func(f: float) -> void:
		pose_tentacle(m, slammed, raised, f)
		m.set_shader_parameter("glow", 0.35 * (1.0 - f)), 0.0, 1.0, 0.35)
	t.tween_property(node, "position:y", root.y - length, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(node.queue_free)
	if is_nan(water_y):
		debris(Vector3(root.x, floor_y + 0.1, root.z), Color(0.8, 0.72, 0.55), 16)
	else:
		splash(Vector3(root.x, water_y, root.z), 30, 1.2)
	sfx("kraken_rise", 120)


## 점수 등 떠오르는 글씨를 3D 위치 위에
func float_at(p3: Vector3, text: String, col: Color, size_: int = 40) -> void:
	float_text(to_arena(p3), text, col, size_)
