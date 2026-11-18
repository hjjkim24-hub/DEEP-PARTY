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

const PAWN_SCALE := 1.25

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
	we.environment = env
	world3.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 40.0
	world3.add_child(sun)
	kit = BoardWorld.new()
	_build_stage()


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
	env.background_color = Color(0.03, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.55, 0.6)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.26, 0.3)
	env.fog_density = 0.035
	sun.light_color = Color(0.95, 1.0, 0.92)
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-62, -25, 0)


func ocean(y: float = 0.0, size: float = 160.0, calm_r: float = 0.0, day: bool = true) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 220
	pm.subdivide_depth = 220
	var m := ShaderMaterial.new()
	m.shader = OceanShader
	m.set_shader_parameter("calm_radius", calm_r)
	if day:
		m.set_shader_parameter("deep", Color(0.01, 0.13, 0.2))
		m.set_shader_parameter("shallow", Color(0.03, 0.36, 0.42))
		m.set_shader_parameter("sky", Color(0.62, 0.76, 0.86))
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
			mi.material_override = kit._rock_mat(randi() % 3)
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
	n.color = p["color"]
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


## 사람: 마우스 쪽으로. (자동 점검 · 미리보기면 ai 가 정한 target)
func human_target(w: Dictionary) -> void:
	var p: Dictionary = w["p"]
	if is_human(p) and playing:
		var g := mouse_ground(walk_y)
		if g != Vector3.INF:
			w["target"] = Vector3(g.x, walk_y, g.z)


func step_walkers(delta: float) -> void:
	_t3 += delta
	var list := walkers.values()
	for w in list:
		if w["out"]:
			continue
		human_target(w)
		var pos: Vector3 = w["pos"]
		var to: Vector3 = w["target"] - pos
		to.y = 0.0
		var sp: float = float(w["speed"]) * (0.45 if float(w["slow"]) > 0.0 else 1.0)
		w["slow"] = maxf(0.0, float(w["slow"]) - delta)
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


# ── 효과 ─────────────────────────────────────────────────────
## 바닥의 붉은 경고 원
func danger_ring(pos: Vector3, r: float, full: Vector3 = Vector3.ONE, yaw: float = 0.0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = DangerShader
	m.set_shader_parameter("aspect", full.z / maxf(full.x, 0.01))
	var mi := add_mesh(q, m, pos + Vector3(0, 0.04, 0), Basis(Vector3.UP, yaw))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = full * 0.2
	create_tween().tween_property(mi, "scale", full, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return mi


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


## 보드와 같은 크라켄 촉수 (셰이더로 휘는 관). 돌려줌 {"root", "mat"}
func tentacle(length: float, radius: float, dir: Vector3) -> Dictionary:
	var tn: Dictionary = kit.make_tentacle(1, radius, length, dir)
	var m: ShaderMaterial = tn["mat"]
	m.set_shader_parameter("caustics", 0.0)
	m.set_shader_parameter("opacity", 0.96)
	world3.add_child(tn["root"])
	return tn


func pose_tentacle(m: ShaderMaterial, a: Array, b: Array, f: float) -> void:
	m.set_shader_parameter("pitch", lerpf(a[0], b[0], f))
	m.set_shader_parameter("curl", lerpf(a[1], b[1], f))
	m.set_shader_parameter("hook", lerpf(a[2], b[2], f))
	m.set_shader_parameter("tipback", lerpf(a[3], b[3], f))
	m.set_shader_parameter("wave", lerpf(a[4], b[4], f))
	m.set_shader_parameter("wtime", _t3)


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


## 점수 등 떠오르는 글씨를 3D 위치 위에
func float_at(p3: Vector3, text: String, col: Color, size_: int = 40) -> void:
	float_text(to_arena(p3), text, col, size_)
