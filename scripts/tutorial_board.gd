extends "res://scripts/board/board_session.gd"
## 튜토리얼 보드. 보드 고르기에서 튜토리얼 상자를 열면 여기로 와요. (보드 진행 공통 부분은 board_session.gd)
## 짧게: 하트 · 생존 규칙 → 화면 조작 → 주사위 · 갈림길 → 크라켄의 붉은 칸 (실제로 내려침) → 칸 안내 → 끝


## 튜토리얼도 크라켄 생존전 규칙 (하트)
func survival() -> bool:
	return true


func _after_intro() -> void:
	_run_tutorial()


## 내 차례 한 번: 주사위 안내 → (갈림길 안내) → 칸 설명 → 칸 효과
func _guided_turn(target: int, roll_text: String, fork_text: String, tile_text: String, shots: Array) -> void:
	var me := _my_pawn()
	var plan := _plan(me, target)
	_play_turn(me, int(plan["rig"]), plan["forced"])
	await _wait_for(func() -> bool: return _awaiting_roll)
	await _say({"text": roll_text, "target": func() -> Control: return _dice_btn, "pad": 6.0,
		"until": func() -> bool: return _dice_hit, "auto": _hit_dice, "shot": shots[0]})
	while not _landed:
		if _choosing:
			var txt := tr(fork_text)
			if "%d" in txt:
				txt = txt % _last_roll
			await _say({"text": txt, "target": func() -> Control: return _forced_arrow(), "pad": 4.0,
				"until": func() -> bool: return not _choosing, "auto": _pick_forced, "shot": shots[1]})
		await get_tree().process_frame
	await _explain_tile(me, tile_text, shots[2])
	await _tile_effect(me)


func _run_tutorial() -> void:
	_overlay = TutorialOverlay.new()
	_overlay.name = "Tutorial"
	_ui.add_child(_overlay)
	_overlay.finished.connect(_on_tutorial_finished)
	_overlay.skipped.connect(_exit_to_menu)
	var me := _my_pawn()

	await _say({"text": "A giant kraken lurks around this board! Everyone starts with 3 hearts. Lose them all and you're out. The last one standing wins!",
		"target": func() -> Control: return _chips, "pad": 10.0, "shot": "17b_hud"})
	await _say({"text": "Drag with the mouse to look around, and roll the mouse wheel to zoom in and out.",
		"target": func() -> Control: return _screen_marker, "pad": 0.0, "interact": true})

	# 1) 주사위 · 갈림길 · 일반 칸
	await _guided_turn(_tile_near(11.2, 0.0),
		"It's your turn! Click the dice above your pawn to roll it.",
		"You rolled a %d! You're at a fork in the road. Click the glowing arrow to choose your way.",
		"Plain space! Nothing happens here. Take a breather.",
		["22_dice", "23_fork", "24_plain"])

	# 2) 크라켄: 바로 앞 칸을 붉게 표시하고 실제로 내려침
	var ahead := -1
	for l in world.spaces[int(me["tile"])]["links"]:
		if int(l) != int(me["prev"]) and int(l) != world.start_index:
			ahead = int(l)
			break
	if ahead < 0:
		ahead = int(world.spaces[int(me["tile"])]["links"][0])
	_follow = null
	_move_camera(world.spaces[ahead]["pos"], 1.6, 0.8)
	await get_tree().create_timer(0.8, false).timeout
	world.mark_danger(ahead)
	Audio.play("tick")
	await _say({"text": "Every 2 rounds the kraken takes its turn. Red spaces get smashed by its tentacles at the end of the next round. Don't stop on them!",
		"dim": false, "shot": "25_kraken_red"})
	Audio.play("kraken_rise")
	world.tentacle_strike(ahead)
	await world.tentacle_slammed
	Audio.play("kraken_slam")
	_shake_camera(0.55, 0.4)
	await get_tree().create_timer(1.2, false).timeout
	await _say({"text": "Ouch! Standing there costs you a heart. The kraken has other tricks too, like poison spines or dropping everyone onto its flying ship.",
		"dim": false, "shot": "26_kraken_strike"})

	# 3) 칸 안내 → 끝
	await _say({"text": "Minigames pay coins, the shop sells potions and shields, and chance cards can help or hurt.",
		"shot": "31_spaces"})
	_highlight_chip({})
	await _say({"text": "That's all! Dodge the kraken and be the last one standing. Have fun!"})
	_overlay.finish()


func _on_tutorial_finished() -> void:
	GameState.tutorial_active = false
	var banner := Label.new()
	banner.text = "TUTORIAL COMPLETE!"
	banner.add_theme_font_size_override("font_size", 72)
	banner.add_theme_color_override("font_outline_color", DEEP)
	banner.add_theme_constant_override("outline_size", 18)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.modulate.a = 0.0
	_fade.get_parent().add_child(banner)
	Audio.play("start")
	var t := create_tween()
	t.tween_property(banner, "modulate:a", 1.0, 0.3)
	t.tween_interval(1.6)
	await t.finished
	_exit_to_menu()
