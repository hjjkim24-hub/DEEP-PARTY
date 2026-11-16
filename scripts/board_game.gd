extends "res://scripts/board/board_session.gd"
## 진짜 보드 게임 한 판: 크라켄 생존전 (개인전 · 2대2). 로비 → 보드 고르기 → PLAY 로 시작.
## 각자 하트 3개. 라운드마다 모두 한 번씩 주사위 → 칸 효과, 라운드가 끝나면 크라켄 차례:
##   노려 둔 칸(붉게 빛나고 옆에서 촉수가 꿈틀)을 내려침 → 거기 서 있으면 하트 -1, 그 칸은 성게 함정이 됨
##   탈락한 사람은 크라켄의 부하가 되어 노릴 칸을 하나씩 고름 → 크라켄이 다음에 내려칠 칸을 새로 노림
## 마지막까지 살아남은 사람(2대2는 팀)이 승리. 맵은 board_maps.gd 의 SUNKEN ISLAND.

const BOARD_TITLES := {"sunken_island": "SUNKEN ISLAND"}


func survival() -> bool:
	return true


func map_id() -> String:
	return "sunken_island" if GameState.selected_board == "sunken_island" else "tutorial"


func exit_label() -> String:
	return "LEAVE GAME"


func board_title() -> String:
	return BOARD_TITLES.get(GameState.selected_board, "DEEP PARTY")


func _after_intro() -> void:
	_round_label.visible = true
	await _kraken_wakes()
	if GameState.debug_showcase:
		await _debug_showcase()
	await _game_loop()


func _round_limit() -> int:
	return GameState.debug_round_limit if GameState.debug_round_limit > 0 else Rules.ROUND_LIMIT


func _game_loop() -> void:
	var limit := _round_limit()
	for r in range(1, limit + 1):
		if _over():
			break
		_round = r
		_round_label.text = tr("ROUND %d / %d") % [r, limit]
		shot_hint = "39_round_%d" % r
		await _banner(tr("FINAL ROUND!") if r == limit else tr("ROUND %d") % r, "", 0.8)
		for p in _pawns:
			if not bool(p["alive"]):
				continue
			await _play_turn(p)
			if _over():
				break
			await _tile_effect(p)
			if _over():
				break
		if _over():
			break
		await _kraken_phase(r)
	_over()
	_highlight_chip({})
	await _show_results()


## 살아남은 쪽(개인 또는 팀)이 하나 이하면 끝
func _over() -> bool:
	if _game_over:
		return true
	var sides := {}
	for q in _pawns:
		if bool(q["alive"]):
			sides[String(q["team"]) if String(q["team"]) != "" else str(q["slot"])] = q
	if sides.size() <= 1:
		_game_over = true
		_winner = sides.values()[0] if sides.size() == 1 else _ranking()[0]
		return true
	return false


func _eliminate(p: Dictionary) -> void:
	p["out_round"] = _round
	shot_hint = "50_eliminated"
	await super(p)


# ── 크라켄 ───────────────────────────────────────────────────
## 시작: 북쪽 골짜기에서 크라켄이 깨어나고 첫 번째 칸들을 노림
func _kraken_wakes() -> void:
	if world.kraken_root == null:
		return
	_follow = null
	var lair := world.kraken_root.position
	# 판 북쪽 끝에서 올려다보는 연출: 깊은 곳에서 거대한 머리와 눈이 솟아오름
	var sc: float = world.KRAKEN_SCALE
	var eye := Vector3(lair.x, world.KRAKEN_AWAKE_Y + 0.6 * sc, lair.z + 1.47 * sc)
	_move_camera(Vector3(lair.x, 6.0, -world.half_d + 2.0), 3.0, 1.6)
	_cinematic(eye + Vector3(7.0, 4.0, 36.0), eye + Vector3(0, 7.0, -4.0), 1.0, 1.6)
	await get_tree().create_timer(1.6, false).timeout
	Audio.play("box_rumble")
	_shake_camera(0.25, 1.2)
	world.kraken_awaken()
	await get_tree().create_timer(1.6, false).timeout
	Audio.play("box_burst")
	_shake_camera(0.6, 0.8)
	await get_tree().create_timer(2.3, false).timeout
	shot_hint = "34_kraken_awakens"
	await _banner(tr("THE KRAKEN AWAKENS!"), tr("Dodge its tentacles. Last one standing wins!"), 1.8)
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 1.4)
	await _kraken_aim(1)


## 라운드 끝: 노린 칸 내려치기 → 부하들이 칸 고르기 → 새로 노리기
func _kraken_phase(r: int) -> void:
	_highlight_chip({})
	await _kraken_strikes()
	if _over():
		return
	for q in _pawns:
		if not bool(q["alive"]):
			await _minion_mark(q)
	await _kraken_aim(r + 1)


func _kraken_strikes() -> void:
	var targets: Array = world.danger_tiles()
	if targets.is_empty():
		return
	_follow = null
	await _banner(tr("THE KRAKEN STRIKES!"), "", 0.7)
	for t in targets:
		if _over():
			return
		var pos: Vector3 = world.spaces[t]["pos"]
		_move_camera(pos + Vector3(0, 0.5, 0), 1.5, 0.55)
		await get_tree().create_timer(0.55, false).timeout
		Audio.play("box_rumble")
		world.tentacle_strike(t)
		await world.tentacle_slammed
		shot_hint = "49b_kraken_strike"
		Audio.play("box_burst")
		_shake_camera(0.55, 0.4)
		# 일반 칸은 성게 가시가 박힌 함정 칸이 됨
		if String(world.spaces[t]["kind"]) in ["plain", "minigame", "chance"] and t != world.start_index:
			_tile_mods[t] = "urchin"
			world.set_tile_look(t, "urchin")
			_legend_add("urchin")
		for q in _alive_pawns():
			if int(q["tile"]) == t:
				await _damage(q, 1)
		await get_tree().create_timer(0.7, false).timeout


## 크라켄이 다음에 내려칠 칸들 (대개 누군가 다음 차례에 멈출 만한 곳)
func _kraken_aim(r: int) -> void:
	var n := mini(Rules.KRAKEN_TARGETS_MAX, int(Rules.KRAKEN_TARGETS_BASE + Rules.KRAKEN_TARGETS_GROW * (r - 1)))
	var picks := []
	var alive := _alive_pawns()
	for k in n:
		var t := -1
		if alive.size() > 0 and _rng.randf() < Rules.KRAKEN_AIM_AT_PAWN:
			var q: Dictionary = alive[_rng.randi() % alive.size()]
			var near := _reachable(int(q["tile"]), 1, 6)
			near = near.filter(func(i: int) -> bool: return not picks.has(i) and not world.danger_tiles().has(i))
			if near.size() > 0:
				t = near[_rng.randi() % near.size()]
		if t < 0:
			var pool := _aimable().filter(func(i: int) -> bool: return not picks.has(i) and not world.danger_tiles().has(i))
			if pool.size() > 0:
				t = pool[_rng.randi() % pool.size()]
		if t >= 0:
			picks.append(t)
	if picks.is_empty():
		return
	_follow = null
	_move_camera(world.overview, world.overview_zoom * 0.7, 1.0)
	await get_tree().create_timer(1.0, false).timeout
	for t in picks:
		world.mark_danger(t)
		Audio.play("tick")
		await get_tree().create_timer(0.22, false).timeout
	shot_hint = "49_kraken_aim"
	await _banner(tr("THE KRAKEN IS WATCHING..."), tr("Don't stop on the glowing red spaces!"), 1.1)


## 탈락한 사람: 크라켄의 부하가 되어 칸 하나를 노림
func _minion_mark(q: Dictionary) -> void:
	var alive := _alive_pawns()
	if alive.is_empty():
		return
	var victim: Dictionary = alive[_rng.randi() % alive.size()]
	var near := _reachable(int(victim["tile"]), 1, 6)
	var auto_t: int = near[_rng.randi() % near.size()] if near.size() > 0 else int(victim["tile"])
	await _banner(tr("KRAKEN'S MINION"), tr("%s picks a space to strike!") % q["name"], 0.6)
	var t: int = await _pick_tile(q, tr("Pick a space for the kraken to strike!"), auto_t, "51_minion_pick")
	if t >= 0 and t != world.start_index:
		world.mark_danger(t)
		Audio.play("tick")
		await get_tree().create_timer(0.5, false).timeout


## 미끼 카드: 그 사람 앞쪽 칸 두 곳을 노림
func _bait(target: Dictionary) -> void:
	var near := _reachable(int(target["tile"]), 1, 6)
	near.shuffle()
	_follow = null
	_move_camera((target["node"] as Node3D).position, 2.2, 0.8)
	await get_tree().create_timer(0.8, false).timeout
	for k in mini(2, near.size()):
		world.mark_danger(near[k])
		Audio.play("tick")
		await get_tree().create_timer(0.3, false).timeout
	await get_tree().create_timer(0.8, false).timeout


## from 에서 lo~hi 칸 떨어진 칸들 (길을 따라)
func _reachable(from: int, lo: int, hi: int) -> Array:
	var out := {}
	var frontier := [from]
	var seen := {from: true}
	for d in range(1, hi + 1):
		var nxt := []
		for c in frontier:
			for l in world.spaces[c]["links"]:
				if not seen.has(l):
					seen[l] = true
					nxt.append(int(l))
					if d >= lo and int(l) != world.start_index:
						out[int(l)] = true
		frontier = nxt
	return out.keys()


func _aimable() -> Array:
	var out := []
	for i in world.spaces.size():
		if i != world.start_index:
			out.append(i)
	return out


## 자동 점검용: 맵 볼거리 · 일시정지 · 상점 · 생존 카드 · 탈락 · 미니게임을 한 번씩
func _debug_showcase() -> void:
	var me := _my_pawn()
	_follow = null
	# 맵 전체: 남쪽 하늘 높이에서 판 · 크라켄 · 둘러싼 촉수가 한 화면에
	_cinematic(Vector3(0, 0.95 * world.half_d + 40.0, world.half_d + 52.0), Vector3(0, 2.0, -world.half_d * 0.22), 1.0, 1.0)
	await get_tree().create_timer(1.4, false).timeout
	shot_hint = "36_map_overview"
	await get_tree().create_timer(3.2, false).timeout
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.5)
	for lm in world.cfg.get("landmarks", []):
		var at: Vector2 = lm["at"]
		_move_camera(Vector3(at.x, world.ground_height(at.x, at.y), at.y), 2.0, 1.0)
		await get_tree().create_timer(1.3, false).timeout
		shot_hint = "37_lm_" + String(lm["type"]) + ("_%d" % int(at.x))
		await get_tree().create_timer(2.4, false).timeout
	# 크라켄 얼굴 · 촉수 가까이
	if world.kraken_root:
		var kr := world.kraken_root.position
		var sc: float = world.KRAKEN_SCALE
		var eye := Vector3(kr.x + 1.42 * sc, kr.y + 0.6 * sc, kr.z + 1.47 * sc)
		_cinematic(eye + Vector3(9.0, 2.0, 14.0), eye, 1.0, 1.0)
		await get_tree().create_timer(1.3, false).timeout
		shot_hint = "35_kraken_eye"
		await get_tree().create_timer(2.4, false).timeout
		var c0: Node3D = world.kraken_coils[0][0]["root"]
		_cinematic(c0.position + Vector3(30.0, 22.0, 40.0), c0.position + Vector3(0, 18.0, 15.0), 1.0, 1.0)
		await get_tree().create_timer(1.3, false).timeout
		shot_hint = "35b_kraken_coil"
		await get_tree().create_timer(2.4, false).timeout
		_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.5)
	focus_on(me)
	_open_pause()
	shot_hint = "38_pause"
	await get_tree().create_timer(1.6, true).timeout
	_pause._show_settings()
	shot_hint = "38b_pause_settings"
	await get_tree().create_timer(1.6, true).timeout
	_pause.close()
	_round = 1
	_add_coins(me, 40)
	me["hearts"] = 2
	_refresh_chip(me)
	await _open_shop(me)
	for id in ["heal", "shield", "bait"]:
		rig_card = id
		await _draw_card(me)
	# 탈락 장면: CPU 하나를 하트 1 로 만들고 그 칸을 내려침
	for q in _pawns:
		if q != me and bool(q["alive"]):
			q["hearts"] = 1
			_refresh_chip(q)
			world.mark_danger(int(q["tile"]))
			break
	await _kraken_strikes()
	for q in _pawns:
		if not bool(q["alive"]):
			await _minion_mark(q)
			break
	for id in Minigames.ids():
		rig_minigame = String(id)
		await _run_minigame(me, false)
