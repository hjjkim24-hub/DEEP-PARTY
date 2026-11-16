extends Node
## 개발용: 보드 게임 화면 몇 장만 빨리 찍고 종료 (전체 투어는 30분, 이건 몇 분)
##   godot --path . -- --quick-shot=map,kraken --shots-dir=/절대/경로
## 찍을 수 있는 장면: map(맵 전체), kraken(크라켄 정면), eye(눈 클로즈업), tile(칸 가까이), village(마을), board(평소 게임 화면)

var _dir := "user://shots"
var _want: PackedStringArray = ["map"]


func _ready() -> void:
	Engine.physics_ticks_per_second = 20
	Engine.max_physics_steps_per_frame = 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.substr("--shots-dir=".length())
		elif a.begins_with("--quick-shot="):
			_want = a.substr("--quick-shot=".length()).split(",", false)
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func() -> void:
		print("QUICK SHOT TIMEOUT")
		get_tree().quit(2))
	_run()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("SHOT: ", path, " ", img.get_size())


func _run() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	GameState.debug_autoplay = true
	GameState.debug_auto_minigames = true
	GameState.selected_mode = GameState.Mode.FREE_FOR_ALL
	GameState.selected_board = "sunken_island"
	GameState.players[1] = {"kind": "cpu", "level": 1, "color": 2}
	GameState.players[2] = {"kind": "cpu", "level": 1, "color": 5}
	get_tree().change_scene_to_file("res://scenes/board.tscn")
	# 크라켄이 다 솟아오를 때까지
	var g: Node = null
	while true:
		await get_tree().process_frame
		g = get_tree().current_scene
		if g and "world" in g and g.world and g.world.kraken_root \
				and g.world.kraken_root.position.y >= g.world.KRAKEN_AWAKE_Y - 0.3:
			break
	await get_tree().create_timer(3.0).timeout
	var w: Node = g.world
	var sc: float = w.KRAKEN_SCALE
	var eye: Vector3 = w.kraken_eye_pos()
	for s in _want:
		match s:
			"map":
				g._cinematic(Vector3(0, 0.95 * w.half_d + 40.0, w.half_d + 52.0), Vector3(0, 2.0, -w.half_d * 0.22), 1.0, 0.01)
			"kraken":
				g._cinematic(Vector3(eye.x - 16.0, 20.0, -w.half_d + 46.0), eye + Vector3(0, 2.0, -6.0), 1.0, 0.01)
			"eye":
				var e2 := eye + Vector3(1.37 * sc, 0, 0)
				g._cinematic(e2 + Vector3(10.0, -4.0, 16.0), e2, 1.0, 0.01)
			"tile":
				var sp: Dictionary = w.spaces[int(w.spaces[w.start_index]["links"][0])]
				var tp: Vector3 = sp["pos"]
				g._cinematic(tp + Vector3(2.6, 2.4, 4.6), tp + Vector3(-0.6, 0.0, -0.8), 1.0, 0.01)
			"temple":
				g._cinematic(Vector3(13.0, 11.0, 15.0), Vector3(0.0, 2.5, -2.0), 1.0, 0.01)
			"wreck":
				g._cinematic(Vector3(-32.0, 11.0, 24.0), Vector3(-46.0, 2.0, 10.0), 1.0, 0.01)
			"light":
				g._cinematic(Vector3(24.0, 8.0, 14.0), Vector3(35.0, 5.0, 4.0), 1.0, 0.01)
			"village":
				g._cinematic(Vector3(-30.0, 9.0, 10.0), Vector3(-36.0, 0.5, -1.0), 1.0, 0.01)
			_:
				g._cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.01)
		await get_tree().create_timer(2.0).timeout
		await _shot("q_" + s)
	get_tree().quit(0)
