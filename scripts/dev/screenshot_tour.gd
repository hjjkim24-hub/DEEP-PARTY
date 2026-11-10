extends Node
## 개발용: 화면들을 자동으로 돌며 스크린샷을 찍고 종료합니다. 게임에는 영향 없음.
##   godot --path . -- --screenshot-tour --shots-dir=/절대/경로
## GitHub 자동 빌드에서 실제 Godot 화면을 확인하는 데 씁니다.

var _dir := "user://shots"


func _ready() -> void:
	# 가상 화면은 아주 느려서(초당 몇 장) 게임 시계가 실제 시간보다 느리게 감 → 물리 단계 제한을 풀어 맞춤
	Engine.physics_ticks_per_second = 20
	Engine.max_physics_steps_per_frame = 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func() -> void:
		print("TOUR TIMEOUT")
		get_tree().quit(2))
	_run()


func _sec(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


## 화면 전환이 끝날 때까지 기다림 (가상 화면은 느려서 넉넉히)
func _settle(m: Node, page: String) -> void:
	var waited := 0.0
	while (m._current != page or m._busy) and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await _sec(2.5)


func _idle(m: Node) -> void:
	while m._busy:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("SHOT: ", path, " ", img.get_size())


## scene_time: 3D 보드에서는 게임 시간으로 기다림 (가상 화면은 너무 느려서 게임 시계가 실제 시간보다 느리게 감)
func _drive(overlay: Node, shots: Dictionary, scene_time: bool = false) -> void:
	var last := -2
	var stuck := 0.0
	while is_instance_valid(overlay) and overlay.is_inside_tree():
		await _sec(0.8)
		if not is_instance_valid(overlay):
			break
		var idx: int = overlay.index
		if idx != last:
			last = idx
			stuck = 0.0
			var cur: Dictionary = overlay.current()
			var named := String(cur.get("shot", ""))
			if named != "":
				await get_tree().create_timer(3.0).timeout
				await _shot(named)
			elif shots.has(idx):
				if scene_time:
					await get_tree().create_timer(4.0).timeout
				else:
					await _sec(4.0)
				await _shot(shots[idx])
			if not is_instance_valid(overlay):
				break
			var st: Dictionary = overlay.current()
			if overlay.is_waiting_for_action():
				if st.has("auto"):
					(st["auto"] as Callable).call()
			else:
				overlay.next()
		else:
			stuck += 0.8
			if overlay.has_method("is_idle") and overlay.is_idle():
				stuck = 0.0
			if stuck > 40.0:
				print("TOUR: tutorial stuck at ", idx)
				return


func _run() -> void:
	# 시작 로고 (Godot 로고가 다 나타났을 때)
	while true:
		var sc := get_tree().current_scene
		if sc and sc.name == "Splash" and int(sc.get("_index")) == 0 and int(sc.get("_phase")) == 2:
			break
		if sc and sc.name == "MainMenu":
			break
		await get_tree().process_frame
	if get_tree().current_scene.name == "Splash":
		await _shot("00_splash_godot")
	while get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu":
		await get_tree().process_frame
	var m: Node = get_tree().current_scene
	await _sec(7.0)
	await _shot("01_main")

	await _idle(m)
	m._show_page("mode")
	await _settle(m, "mode")
	await _shot("02_mode")

	await _idle(m)
	m._open_lobby(0)
	await _settle(m, "lobby")
	m._lobby_add_cpu(1)
	m._lobby_add_cpu(2)
	await _sec(1.0)
	await _shot("03_lobby")

	await _idle(m)
	m._lobby_customize()
	await _settle(m, "customize")
	m._select_cz_tab(1)
	m._on_item_pressed("hat", "crown")
	await _sec(1.5)
	await _shot("04_customize")
	await _idle(m)
	m._go_back()
	await _settle(m, "lobby")

	m._on_lobby_start()
	await _settle(m, "board")
	await _shot("05_board_select")
	m._select_board(2)
	await _sec(2.0)
	await _shot("06_board_select_locked")
	m._select_board(1)
	await _sec(0.5)
	await _idle(m)
	m._go_back()
	await _settle(m, "lobby")
	m._go_back()
	await _settle(m, "mode")
	m._go_back()
	await _settle(m, "main")

	m._show_page("settings")
	await _settle(m, "settings")
	await _shot("07_settings")

	# 튜토리얼
	m._go_back()
	await _settle(m, "main")
	m._start_tutorial()
	await _drive(m._tutorial, {0: "10_tut_welcome", 2: "11_tut_modes", 7: "12_tut_add_cpu", 13: "13_tut_hat", 17: "14_tut_board_box"})
	while get_tree().current_scene == null or get_tree().current_scene.name != "TutorialBoard":
		await get_tree().process_frame
	var tb: Node = get_tree().current_scene
	await _sec(1.2)
	await _shot("15_world_board_view")
	await _sec(2.6)
	await _shot("16_world_diving_in")
	while tb._overlay == null:
		await get_tree().process_frame
	await _drive(tb._overlay, {}, true)
	await _sec(0.6)
	await _shot("21_tutorial_complete")
	while get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu":
		await get_tree().process_frame

	print("TOUR DONE")
	await Audio.stop_music(0.1)
	get_tree().quit(0)
