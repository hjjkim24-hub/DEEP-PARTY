extends SceneTree
## 아이템 3D 모델을 사진처럼 찍어 아이콘으로 저장 (투명 배경 · 256x256) → res://textures/ui/items/<id>.png
## 화면이 있어야 그려짐: xvfb-run 으로 실행
##   xvfb-run -a godot --rendering-method gl_compatibility --rendering-driver opengl3 --path . -s res://tools/render_item_icons.gd

const SIZE := 512
const IM := preload("res://scripts/world3d/item_models.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.65)
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	# 3점 조명: 따뜻한 주광 · 차가운 보조광 · 뒤에서 테두리 빛
	for l in [[Vector3(-0.7, -0.6, -0.5), Color(1.0, 0.94, 0.85), 1.35, true], [Vector3(0.8, -0.3, -0.4), Color(0.7, 0.82, 1.0), 0.35, false],
			[Vector3(0.2, -0.4, 1.0), Color(0.9, 0.95, 1.0), 0.9, false]]:
		var dl := DirectionalLight3D.new()
		dl.light_color = l[1]
		dl.light_energy = l[2]
		dl.shadow_enabled = l[3]
		vp.add_child(dl)
		dl.look_at_from_position(Vector3.ZERO, l[0], Vector3.UP if absf((l[0] as Vector3).normalized().y) < 0.95 else Vector3.FORWARD)
	var cam := Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://textures/ui/items"))
	for id in IM.ORDER:
		var m: Node3D = IM.make(id)
		vp.add_child(m)
		# 모델 크기에 맞춰 화면에 꽉 차게
		var box := _aabb(m)
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 0.93
		var dir := Vector3(0.55, 0.42, 1.0).normalized()
		cam.look_at_from_position(c + dir * dist, c, Vector3.UP)
		for f in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		var path := "res://textures/ui/items/%s.png" % id
		img.save_png(ProjectSettings.globalize_path(path))
		print("icon ", path)
		m.queue_free()
		await process_frame
	quit(0)


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var b := g.global_transform * g.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
