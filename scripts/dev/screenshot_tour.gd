extends Node
## 개발용: 화면들을 자동으로 돌며 스크린샷을 찍고 종료합니다. 게임에는 영향 없음.
##   godot --path . -- --screenshot-tour --shots-dir=/절대/경로
## GitHub 자동 빌드에서 실제 Godot 화면을 확인하는 데 씁니다.

var _dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.substr("--shots-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("TOUR TIMEOUT")
		get_tree().quit(2))
	_run()


func _sec(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("SHOT: ", path, " ", img.get_size())


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
	await _sec(3.0)
	await _shot("01_main")

	m._show_page("mode")
	await _sec(1.5)
	await _shot("02_mode")

	m._open_lobby(0)
	await _sec(1.0)
	m._lobby_add_cpu(1)
	m._lobby_add_cpu(2)
	await _sec(1.5)
	await _shot("03_lobby")

	m._lobby_customize()
	await _sec(1.0)
	m._select_cz_tab(1)
	m._on_item_pressed("hat", "crown")
	await _sec(1.5)
	await _shot("04_customize")
	m._go_back()
	await _sec(1.0)

	m._on_lobby_start()
	await _sec(2.0)
	await _shot("05_board_select")
	m._select_board(1)
	await _sec(1.5)
	await _shot("06_board_select_locked")
	m._select_board(0)
	await _sec(0.5)
	m._go_back()
	await _sec(1.0)
	m._go_back()
	await _sec(1.0)
	m._go_back()
	await _sec(1.0)

	m._show_page("settings")
	await _sec(1.5)
	await _shot("07_settings")

	print("TOUR DONE")
	await Audio.stop_music(0.1)
	get_tree().quit(0)
