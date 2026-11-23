extends SceneTree
## 찬스 카드 그림: 카드마다 바닷속 작은 무대(모래 바닥 · 바위 · 빛줄기 · 떠다니는 부유물)를 꾸미고
## 소품을 세워 사진처럼 찍음 → res://textures/ui/cards/art/<id>.png (가로 3 : 세로 2)
## 마무리(비네트 · 색감 · 필름 입자)는 tools/finish_card_art.py
##   xvfb-run -a godot --rendering-method gl_compatibility --rendering-driver opengl3 --path . -s res://tools/render_card_art.gd

const W := 1200
const H := 800
const CM := preload("res://scripts/world3d/card_models.gd")
const IM := preload("res://scripts/world3d/item_models.gd")
const IDS := ["coins5", "coins10", "roll_again", "lucky_spaces", "trap_spaces", "pickpocket", "warp", "heal", "shield",
	"harpoon", "trap", "vampire", "bait"]

var vp: SubViewport
var cam: Camera3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := OS.get_environment("CARD")
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://textures/ui/cards/art"))
	for id in IDS:
		if only != "" and id != only:
			continue
		var stage := _stage(id)
		# 노이즈 텍스처(모래 · 나뭇결 · 금속 결)는 따로 만들어지므로 다 될 때까지 기다림
		for f in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(ProjectSettings.globalize_path("res://textures/ui/cards/art/%s_raw.png" % id))
		print("art ", id)
		stage.queue_free()
		await process_frame
	quit(0)


## 무대 + 소품 + 카메라 · 조명 (카드마다 분위기 색이 조금씩 다름)
func _stage(id: String) -> Node3D:
	var st := Node3D.new()
	vp.add_child(st)
	var mood := {"trap_spaces": Color(0.55, 0.2, 0.18), "vampire": Color(0.5, 0.18, 0.4), "bait": Color(0.45, 0.15, 0.15),
		"warp": Color(0.3, 0.2, 0.55), "trap": Color(0.3, 0.3, 0.32)}
	var tint: Color = mood.get(id, Color(0.12, 0.42, 0.5))
	# 하늘 = 물속 배경 (위는 밝은 청록, 아래로 갈수록 깊은 남색) · 금속 반사도 이걸로
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.62, 0.7).lerp(tint, 0.25)
	sky_mat.sky_horizon_color = Color(0.05, 0.25, 0.32).lerp(tint, 0.35)
	sky_mat.ground_horizon_color = Color(0.04, 0.16, 0.2).lerp(tint, 0.3)
	sky_mat.ground_bottom_color = Color(0.01, 0.04, 0.06)
	sky_mat.sky_curve = 0.25
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_light_energy = 1.0
	env.fog_density = 0.13
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	st.add_child(we)
	# 물 위에서 내려오는 햇빛 (그림자) + 차가운 보조광 + 뒤 테두리 빛
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.95, 0.97, 0.85)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	st.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -1.0, -0.45), Vector3.FORWARD)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.75, 0.9)
	fill.light_energy = 0.45
	st.add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.8, -0.3, -0.6), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.7, 0.95, 1.0)
	rim.light_energy = 0.9
	st.add_child(rim)
	rim.look_at_from_position(Vector3.ZERO, Vector3(0.2, -0.5, 1.0), Vector3.UP)
	_floor(st)
	_scenery(st, id)
	# 소품
	var prop := _prop(id)
	st.add_child(prop)
	# 카메라: 소품 크기에 맞춰 3:2 화면에 꽉 차게, 살짝 내려다봄
	var box := _aabb(prop)
	var c := box.get_center()
	var half := maxf(box.size.x * 0.5 / (float(W) / H), box.size.y * 0.5) * 1.22
	half = maxf(half, 0.55)
	var dist := half / tan(deg_to_rad(cam.fov * 0.5)) + box.size.z * 0.5
	var dirs := {"roll_again": Vector3(0.2, 0.5, 1.0), "lucky_spaces": Vector3(0.0, 0.45, 1.0), "trap_spaces": Vector3(0.0, 0.45, 1.0),
		"vampire": Vector3(0.1, 0.05, 1.0), "bait": Vector3(0.15, 0.08, 1.0), "warp": Vector3(0.25, 0.15, 1.0),
		"trap": Vector3(0.0, 0.75, 1.0), "coins10": Vector3(0.15, 0.55, 1.0), "coins5": Vector3(0.15, 0.45, 1.0)}
	var dir: Vector3 = (dirs.get(id, Vector3(0.3, 0.32, 1.0)) as Vector3).normalized()
	cam.look_at_from_position(c + dir * dist, c, Vector3.UP)
	return st


func _floor(st: Node3D) -> void:
	var sand := StandardMaterial3D.new()
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.03
	n.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.36, 0.32, 0.25))
	g.set_color(1, Color(0.62, 0.56, 0.44))
	tex.color_ramp = g
	sand.albedo_texture = tex
	var rip := FastNoiseLite.new()
	rip.seed = 12
	rip.noise_type = FastNoiseLite.TYPE_SIMPLEX
	rip.frequency = 0.012
	rip.domain_warp_enabled = true
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.noise = rip
	sand.normal_enabled = true
	sand.normal_texture = nt
	sand.roughness = 0.95
	sand.uv1_scale = Vector3(6, 6, 1)
	# 일렁이는 빛 무늬
	sand.emission_enabled = true
	sand.emission_texture = load("res://textures/models/caustics.png")
	sand.emission = Color(0.55, 0.85, 0.9)
	sand.emission_energy_multiplier = 0.18
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = sand
	st.add_child(mi)


## 배경 소품: 바위 · 해초 · 위에서 비추는 빛줄기 · 떠다니는 입자 (카드마다 배치를 살짝 바꿈)
func _scenery(st: Node3D, id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var rock := IM._grain(Color(0.32, 0.33, 0.3), 0.9, Vector2(2, 2), 0.4, 1.0, 0.0, 7)
	for k in 7:
		var p := Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-9, -3))
		var r := rng.randf_range(0.5, 1.6)
		var mi := IM._mi(IM._sph(r, r * 1.2, 20), rock, p, st)
		mi.scale = Vector3(rng.randf_range(1.0, 1.8), rng.randf_range(0.5, 0.9), 1.0)
		mi.rotation.y = rng.randf() * TAU
	var weed := IM._grain(Color(0.18, 0.38, 0.2), 0.8, Vector2(1, 4), 0.35, 0.4, 0.0, 8)
	for k in 9:
		var base := Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-7, -2.5))
		var h := rng.randf_range(0.8, 2.2)
		var prev := base
		for j in 8:
			var t := (j + 1) / 8.0
			var q := base + Vector3(sin(t * 3.0 + k) * 0.18, t * h, cos(t * 2.0 + k) * 0.1)
			var dv := q - prev
			IM._mi(IM._cyl(0.025 * (1.2 - t), 0.035 * (1.2 - t), dv.length() + 0.02, 6), weed, (q + prev) * 0.5, st, Basis(Quaternion(Vector3.UP, dv.normalized())))
			prev = q
	# 빛줄기
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gtex := GradientTexture2D.new()
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	gr.add_point(0.35, Color(1, 1, 1, 1.0))
	gtex.gradient = gr
	beam.albedo_texture = gtex
	beam.albedo_color = Color(0.6, 0.9, 1.0, 0.09)
	for k in 5:
		var mi := IM._mi(IM._cyl(0.25, 0.9, 14, 16), beam, Vector3(rng.randf_range(-4, 3), 6, rng.randf_range(-6, -1)), st,
			Basis(Vector3.BACK, 0.3 + rng.randf_range(-0.06, 0.06)) * Basis(Vector3.RIGHT, 0.3))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 부유물 · 공기방울
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.albedo_color = Color(0.85, 0.95, 1.0, 0.45)
	for k in 70:
		var mi := IM._mi(IM._sph(rng.randf_range(0.006, 0.02), -1.0, 6), mote, Vector3(rng.randf_range(-3, 3), rng.randf_range(0.2, 3.5), rng.randf_range(-4, 1.5)), st)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bub := IM._glass(Color(0.85, 0.95, 1.0, 0.25))
	for k in 9:
		var r := rng.randf_range(0.03, 0.09)
		IM._mi(IM._sph(r, -1.0, 14), bub, Vector3(rng.randf_range(-1.6, 1.8), rng.randf_range(0.8, 2.6), rng.randf_range(-1.0, 0.6)), st)


func _prop(id: String) -> Node3D:
	match id:
		"coins5":
			return CM.coin_pile(5, false, 3)
		"coins10":
			return CM.coin_pile(12, false, 9)
		"roll_again":
			var r := Node3D.new()
			var a := CM.die6(0.55)
			a.position = Vector3(-0.38, 0.275, 0.05)
			a.rotation = Vector3(0, 0.5, 0)
			r.add_child(a)
			var b := CM.die6(0.55)
			b.position = Vector3(0.38, 0.55, -0.05)
			b.rotation = Vector3(0.7, -0.4, 0.5)   # 아직 구르는 중
			r.add_child(b)
			return r
		"lucky_spaces":
			return CM.slab_with_coin(false)
		"trap_spaces":
			return CM.slab_with_coin(true)
		"pickpocket":
			return CM.pouch()
		"warp":
			return CM.portal()
		"heal":
			return IM.make("potion")
		"shield":
			return IM.make("shield")
		"harpoon":
			return CM.harpoon()
		"trap":
			return CM.bear_trap()
		"vampire":
			return CM.jelly()
		"bait":
			return CM.bait()
	return Node3D.new()


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.has_meta("nofit") or (g.get_parent() and g.get_parent().has_meta("nofit")):
			continue
		var b := g.global_transform * g.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
