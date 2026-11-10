extends "res://scripts/board/board_session.gd"
## 튜토리얼 보드. 보드 고르기에서 튜토리얼 상자를 열면 여기로 와요. (보드 진행 공통 부분은 board_session.gd)
## 직접 해 보면서 배워요: 주사위 → 갈림길 → 칸 → 동전·트로피.
## 주사위 숫자와 결과를 정해 둬서 늘 같은 순서로 진행돼요:
##   일반 칸 → CPU 차례 구경 → 포탈 → 미니게임(1등, 동전 받기) → 트로피 칸 지나가며 사기 → 상점 → 찬스(+5)


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

	await _say({"text": "You've jumped into the board! In DEEP PARTY, your pawn walks around inside the board world.",
		"target": func() -> Control: return _start_marker, "shot": "17_world_start"})
	await _say({"text": "Collect 5 trophies before anyone else to win! Everyone's coins and trophies are shown up here.",
		"target": func() -> Control: return _chips, "pad": 10.0, "shot": "17b_hud"})
	await _say({"text": "Paths split off at the arrow spaces and loop back around, so there's no finish line. Take any road you like!",
		"enter": func() -> void: _move_camera(Vector3(0, 0, 0), 3.2, 1.8), "dim": false, "shot": "18_world_overview"})
	await _say({"text": "Climb the stairs up the coral hill, cross the bridge, hop across the stone pillars and go through the rock tunnel!",
		"enter": func() -> void: _move_camera(Vector3(-13, 3.5, -11), 1.7, 1.6), "dim": false, "shot": "19_world_plateau"})
	await _say({"text": "Drag with the mouse to look around, and roll the mouse wheel to zoom in and out.",
		"target": func() -> Control: return _screen_marker, "pad": 0.0, "interact": true})

	# 1) 주사위 · 갈림길 · 일반 칸
	await _guided_turn(_tile_near(11.2, 0.0),
		"It's your turn! Click the dice above your pawn to roll it.",
		"You rolled a %d! You're at a fork in the road. Click the glowing arrow to choose your way.",
		"Plain space! Nothing happens here. Take a breather.",
		["22_dice", "23_fork", "24_plain"])

	# 2) CPU 차례 구경
	var cpus := []
	for p in _pawns:
		if p["cpu"]:
			cpus.append(p)
	if cpus.size() > 0:
		await _say({"text": "Everyone takes turns. On each turn, the camera zooms in on that player's pawn. Let's watch the CPU!", "dim": false})
		for c in cpus:
			var cp := _plan(c, _tile_near(-2.6, -13.0))
			await _play_turn(c, int(cp["rig"]), cp["forced"])
			await _tile_effect(c)

	# 3) 포탈
	await _guided_turn(_tile_near(14.5, -7.6),
		"Your turn again! Roll the dice.",
		"Another fork! Let's head for the stone pillars this time.",
		"Portal space! You'll warp to the portal on the other side of the board.",
		["", "", "25_portal"])
	await _say({"text": "Whoosh! You popped out on the other side of the board.", "dim": false, "shot": "26_warped"})

	# 4) 미니게임 → 동전 (직접 한 판!)
	rig_minigame = "pearl_pop"
	await _guided_turn(_tile_near(-7.0, 12.4),
		"Roll again!",
		"After a warp, you can pick which way to go. Let's go this way!",
		"Minigame space! Stop here and everyone plays a minigame. There are lots of them all over the board.",
		["", "", "27_minigame"])
	await _say({"text": "Minigames pay coins by rank: 10 for 1st, 6 for 2nd, 3 for 3rd and 1 for 4th. Whoever landed on the space gets 2 more!",
		"target": func() -> Control: return _chips, "pad": 10.0})
	# 트로피를 꼭 사 볼 수 있게, 모자라면 연습 보너스
	var need := Rules.TROPHY_PRICE + 2 - int(me["coins"])
	if need > 0:
		_add_coins(me, need)
		await _say({"text": "Tutorial bonus! Here are a few extra coins so you can try buying a trophy.",
			"target": func() -> Control: return _chips, "pad": 10.0})

	# 5) 트로피 등장 → 지나가며 사기
	var trophy_at := _tile_near(0.0, 12.0)
	_follow = null
	_move_camera(world.spaces[trophy_at]["pos"], 1.6, 1.0)
	await get_tree().create_timer(1.05, false).timeout
	world.show_trophy(trophy_at)
	Audio.play("start")
	await _say({"text": "Look, a trophy appeared! In a real game, a trophy pops up on a random space after round 3. Buy it for 20 coins!",
		"dim": false, "shot": "27b_trophy_spawn"})
	var plan := _plan(me, _tile_near(6.4, 13.0))
	force_trophy_buy = true
	_play_turn(me, int(plan["rig"]), plan["forced"])
	await _wait_for(func() -> bool: return _awaiting_roll)
	await _say({"text": "Keep rolling!", "target": func() -> Control: return _dice_btn, "pad": 6.0,
		"until": func() -> bool: return _dice_hit, "auto": _hit_dice})
	await _wait_for(func() -> bool: return _dialog_open)
	await get_tree().create_timer(0.35, false).timeout
	await _say({"text": "You only have to pass the trophy, not stop on it! You stop to decide, then move the rest of the way. Click BUY!",
		"target": func() -> Control: return _dialog_panel if _dialog_open else null, "pad": 8.0,
		"until": func() -> bool: return not _dialog_open, "auto": func() -> void: _press_dialog(0), "shot": "27c_trophy_buy"})
	force_trophy_buy = false
	await _wait_for(func() -> bool: return _landed)

	# 6) 상점 (트로피가 진열된 날)
	await _explain_tile(me, "Shop space! Drop by the stall to buy items.", "28_shop")
	force_shop_trophy = 1
	_open_shop(me)
	await _wait_for(func() -> bool: return _shop_open)
	await get_tree().create_timer(0.4, false).timeout
	await _say({"text": "Sometimes the shop sells a trophy for 40 coins! Other items will be added later. Click CLOSE to leave the shop.",
		"target": func() -> Control: return _shop_close, "pad": 8.0,
		"until": func() -> bool: return not _shop_open, "auto": _close_shop, "shot": "29_shop_window"})

	# 7) 찬스 (+5 동전)
	rig_card = "coins5"
	await _guided_turn(_tile_near(11.5, 8.7),
		"One more roll!",
		"Pick a way!",
		"Chance space! You draw a random Chance Card.",
		["", "", "30_chance"])
	await _say({"text": "Chance cards can give coins, extra rolls or warps, set coin traps, or even let you steal a trophy!", "dim": false})

	await _say({"text": "Forgot what a space does? Check the guide in the bottom left.",
		"target": func() -> Control: return _legend, "shot": "31_legend"})
	await _say({"text": "Lost? Press MY PAWN to jump back to your pawn.",
		"enter": func() -> void: _look_away(),
		"target": func() -> Control: return _my_pawn_btn,
		"until": func() -> bool: return _focused,
		"auto": func() -> void: _focus_my_pawn(),
		"shot": "20_world_my_pawn"})
	_highlight_chip({})
	await _say({"text": "That's all the basics! Collect 5 trophies before anyone else to win. Have fun!"})
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
