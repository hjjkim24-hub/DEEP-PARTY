extends "res://scripts/board/board_session.gd"
## 진짜 보드 게임 한 판. 로비 → 보드 고르기 → PLAY 로 시작.
## 라운드마다 모두 한 번씩 차례 → 칸 효과. 트로피 5개를 먼저 모으면 바로 끝 (2대2는 팀 합계).
## 3라운드가 끝나면 랜덤 칸에 트로피가 생기고, 누가 사면 2라운드 뒤 다른 곳에 다시 생겨요.
## (지금은 SUNKEN ISLAND 전용 맵이 없어서 튜토리얼 맵으로 진행)

const BOARD_TITLES := {"sunken_island": "SUNKEN ISLAND"}


func exit_label() -> String:
	return "LEAVE GAME"


func confirm_exit() -> bool:
	return true


func board_title() -> String:
	return BOARD_TITLES.get(GameState.selected_board, "DEEP PARTY")


func _after_intro() -> void:
	_round_label.visible = true
	if GameState.debug_showcase:
		await _debug_showcase()
	await _game_loop()


func _game_loop() -> void:
	var limit := Rules.ROUND_LIMIT
	if GameState.debug_round_limit > 0:
		limit = GameState.debug_round_limit
	for r in range(1, limit + 1):
		_round = r
		_round_label.text = tr("ROUND %d / %d") % [r, limit]
		shot_hint = "39_round_%d" % r
		await _banner(tr("FINAL ROUND!") if r == limit else tr("ROUND %d") % r, "", 0.8)
		if world.trophy_tile < 0 and r >= _trophy_next_round:
			await _spawn_trophy()
		for p in _pawns:
			await _play_turn(p)
			if _game_over:
				break
			await _tile_effect(p)
			if _game_over:
				break
		if _game_over:
			break
	_highlight_chip({})
	await _show_results()


## 자동 점검용: 트로피 사기 · 모든 찬스 카드 · 상점 트로피 · 미니게임 결과를 한 번씩
func _debug_showcase() -> void:
	var me := _my_pawn()
	_round = 1
	_add_coins(me, 60)
	await _spawn_trophy()
	await _offer_trophy(me)
	for c in Rules.CARDS:
		rig_card = String(c["id"])
		await _draw_card(me)
		if _game_over:
			return
	force_shop_trophy = 1
	await _open_shop(me)
	await _run_minigame(me, false)
	_trophy_next_round = 1
