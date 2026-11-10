extends Node
## 개발용 자동 점검. 게임에는 영향 없음.
## `godot --headless -- --smoke-test` 로 실행하면
## 시작 로고 → 메인화면 → 설정/모드/로비/꾸미기 화면을 자동으로 한 바퀴 돌고 종료합니다.
## GitHub 자동 빌드에서 스크립트 오류를 미리 잡는 데 씁니다.

const TIMEOUT_SEC := 600.0


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SEC, true, false, true).timeout.connect(func() -> void:
		print("SMOKE TEST TIMEOUT (scene: %s)" % [get_tree().current_scene.name if get_tree().current_scene else "none"])
		get_tree().quit(2))
	_run()


func _sec(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _step(msg: String) -> void:
	print("SMOKE: ", msg)


## 튜토리얼 안내를 끝까지 자동으로 넘김 (플레이어 동작이 필요한 단계는 "auto" 로 대신 눌러 줌)
func _drive(overlay: Node, on_step: Callable = Callable()) -> void:
	var last := -2
	var stuck := 0.0
	var idle := 0.0
	while is_instance_valid(overlay) and overlay.is_inside_tree():
		await _sec(0.6)
		if not is_instance_valid(overlay):
			break
		var idx: int = overlay.index
		if idx != last:
			last = idx
			stuck = 0.0
			idle = 0.0
			if on_step.is_valid():
				await on_step.call(idx)
			if not is_instance_valid(overlay):
				break
			var st: Dictionary = overlay.current()
			print("SMOKE:   step %d: %s" % [idx, String(st.get("text", "")).left(50)])
			if overlay.is_waiting_for_action():
				if st.has("auto"):
					(st["auto"] as Callable).call()
			else:
				overlay.next()
		elif overlay.has_method("is_idle") and overlay.is_idle():
			# 보드 튜토리얼은 단계 사이에 게임이 진행됨 (쉬는 중) — 너무 오래면 멈춘 것
			idle += 0.6
			if idle > 90.0:
				push_error("Tutorial board stuck between steps (after step %d)" % idx)
				return
		else:
			stuck += 0.6
			if stuck > 25.0:
				push_error("Tutorial stuck at step %d" % idx)
				return


func _run() -> void:
	# 메인화면이 뜰 때까지
	while get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu":
		await get_tree().process_frame
	var m: Node = get_tree().current_scene
	await _sec(2.0)

	_step("audio: sfx %d/%d, music playing %s" % [Audio._streams.size(), Audio.SFX_NAMES.size(), Audio._music.playing])
	if Audio._streams.size() != Audio.SFX_NAMES.size() or not Audio._music.playing:
		push_error("Audio files missing")
	for n in Audio.SFX_NAMES:
		Audio.play(n)

	_step("tutorial button")
	m._on_menu_pressed("tutorial", m._main_buttons[1])
	await _sec(0.3)

	_step("tutorial: menu walkthrough")
	m._start_tutorial()
	await _drive(m._tutorial)
	var waited := 0.0
	while (get_tree().current_scene == null or get_tree().current_scene.name != "TutorialBoard") and waited < 15.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if get_tree().current_scene.name != "TutorialBoard":
		push_error("Tutorial board did not open")
	else:
		_step("tutorial: board")
		var tb: Node = get_tree().current_scene
		while tb._overlay == null:
			await get_tree().process_frame
		await _drive(tb._overlay)
	waited = 0.0
	while (get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu") and waited < 15.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	m = get_tree().current_scene
	if m.name != "MainMenu" or GameState.tutorial_active:
		push_error("Did not return to the main menu after the tutorial")
	await _sec(2.0)

	_step("settings")
	m._show_page("settings")
	await _sec(0.8)
	for i in m._tab_buttons.size():
		m._select_settings_tab(i)
		await _sec(0.3)
	_step("language ko/en")
	m._on_language_changed(1)
	await _sec(0.3)
	m._on_language_changed(0)
	await _sec(0.3)
	m._go_back()
	await _sec(0.8)

	for mode in 3:
		_step("lobby mode %d" % mode)
		m._show_page("mode")
		await _sec(0.8)
		m._open_lobby(mode)
		await _sec(0.8)
		for slot in range(1, 4):
			m._lobby_add_cpu(slot)
			await _sec(0.1)
		m._lobby_set_level(1, 2)
		m._lobby_remove(3)
		await _sec(0.2)
		m._lobby_add_cpu(3)
		m._lobby_invite()
		await _sec(0.5)

		_step("customize (mode %d)" % mode)
		m._lobby_customize()
		await _sec(0.8)
		for tab in m._cz_tab_buttons.size():
			m._select_cz_tab(tab)
			await _sec(0.2)
		m._on_swatch_pressed(3)
		for cat in GameState.COSMETICS:
			for item_id in GameState.COSMETICS[cat]:
				m._on_item_pressed(cat, item_id)
				await _sec(0.1)
			m._on_item_remove(cat)
		m._on_item_pressed("hat", "crown")
		await _sec(0.3)
		m._go_back()   # → 로비
		await _sec(0.8)

		_step("board select (mode %d)" % mode)
		m._on_lobby_start()
		await _sec(0.8)
		if m._current != "board":
			push_error("Board select page did not open")
		m._select_board(2)
		await _sec(0.3)
		m._on_board_play()   # 잠긴 보드 → 아무 일 없음
		m._select_board(1)
		await _sec(0.3)
		if mode == GameState.Mode.COOP:
			m._on_board_play()   # 협동 규칙은 아직 → 안내 메시지만
			await _sec(0.5)
		m._go_back()   # → 로비
		await _sec(0.8)
		m._go_back()   # → 모드 선택
		await _sec(0.8)
		m._go_back()   # → 메인
		await _sec(0.8)

	# 진짜 보드 게임: 내 말도 자동으로, 모든 카드를 한 번씩 써 보고 2라운드
	await _play_board_game(GameState.Mode.FREE_FOR_ALL, true, 2, [{"kind": "cpu", "level": 1, "color": 2}, {"kind": "cpu", "level": 1, "color": 5}, {}])
	# 2대2 한 라운드
	await _play_board_game(GameState.Mode.TEAM_2V2, false, 1, [{"kind": "cpu", "level": 1, "color": 2}, {"kind": "cpu", "level": 1, "color": 5}, {"kind": "cpu", "level": 1, "color": 8}])

	print("SMOKE TEST DONE")
	await Audio.stop_music(0.1)
	await _sec(0.3)
	get_tree().quit(0)


func _play_board_game(mode: int, showcase: bool, rounds: int, others: Array) -> void:
	_step("board game (mode %d, showcase %s, %d rounds)" % [mode, showcase, rounds])
	GameState.debug_autoplay = true
	GameState.debug_showcase = showcase
	GameState.debug_round_limit = rounds
	GameState.selected_mode = mode
	GameState.selected_board = "sunken_island"
	for i in 3:
		GameState.players[i + 1] = others[i]
	get_tree().change_scene_to_file("res://scenes/board.tscn")
	var waited := 0.0
	while (get_tree().current_scene == null or get_tree().current_scene.name != "BoardGame") and waited < 15.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var last_hint := ""
	waited = 0.0
	while (get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu") and waited < 300.0:
		await _sec(0.5)
		waited += 0.5
		var sc := get_tree().current_scene
		if sc and sc.name == "BoardGame" and String(sc.shot_hint) != last_hint:
			last_hint = String(sc.shot_hint)
			_step("  game: " + last_hint)
	if get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu":
		push_error("Board game did not finish")
	GameState.debug_autoplay = false
	GameState.debug_showcase = false
	GameState.debug_round_limit = 0
	await _sec(1.0)
