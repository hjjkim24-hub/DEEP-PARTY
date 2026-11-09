extends Node
## 개발용 자동 점검. 게임에는 영향 없음.
## `godot --headless -- --smoke-test` 로 실행하면
## 시작 로고 → 메인화면 → 설정/모드/로비/꾸미기 화면을 자동으로 한 바퀴 돌고 종료합니다.
## GitHub 자동 빌드에서 스크립트 오류를 미리 잡는 데 씁니다.

const TIMEOUT_SEC := 120.0


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SEC, true, false, true).timeout.connect(func() -> void:
		print("SMOKE TEST TIMEOUT (scene: %s)" % [get_tree().current_scene.name if get_tree().current_scene else "none"])
		get_tree().quit(2))
	_run()


func _sec(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _step(msg: String) -> void:
	print("SMOKE: ", msg)


func _run() -> void:
	# 메인화면이 뜰 때까지
	while get_tree().current_scene == null or get_tree().current_scene.name != "MainMenu":
		await get_tree().process_frame
	var m: Node = get_tree().current_scene
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
		m._go_back()   # → 모드 선택
		await _sec(0.8)
		m._go_back()   # → 메인
		await _sec(0.8)

	print("SMOKE TEST DONE")
	get_tree().quit(0)
