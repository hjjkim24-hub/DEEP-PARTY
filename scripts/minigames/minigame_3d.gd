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
var cam_base := Transform3D()   ## 흔들림 없는 카메라 자리 (무대 만든 뒤 저장)
var _shake := 0.0
var _shake_t := 0.0


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
	if cam == null:
		return
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
	env.background_color = Color(0.03, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.6, 0.64)
	env.ambient_light_energy = 0.85
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
	world3.add_child(snow)
	var rr := RandomNumberGenerator.new()
	rr.seed = 4
	for k in 8:
		var q := QuadMesh.new()
		q.size = Vector2(rr.randf_range(2.0, 4.5), 30.0)
		var m := ShaderMaterial.new()
		m.shader = RayShader
		m.set_shader_parameter("phase", rr.randf() * TAU)
		m.set_shader_parameter("strength", rr.randf_range(0.018, 0.04))
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
		m.set_shader_parameter("glow", f * 0.6), 0.0, 1.0, rise_t)
	t.tween_method(func(f: float) -> void: pose_tentacle(m, raised, wound, f), 0.0, 1.0, wind_t).set_trans(Tween.TRANS_SINE)
	t.tween_interval(maxf(0.0, warn - rise_t - wind_t - 0.2))
	t.tween_method(func(f: float) -> void: pose_tentacle(m, wound, slammed, f * f), 0.0, 1.0, 0.2)
	t.tween_interval(0.55)
	t.tween_method(func(f: float) -> void:
		pose_tentacle(m, slammed, raised, f)
		m.set_shader_parameter("glow", 0.6 * (1.0 - f)), 0.0, 1.0, 0.35)
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
