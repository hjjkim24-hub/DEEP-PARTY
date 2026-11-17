extends "res://scripts/board/board_session.gd"
## 진짜 보드 게임 한 판: 크라켄 생존전 (개인전 · 2대2). 로비 → 보드 고르기 → PLAY 로 시작.
## 각자 하트 3개. 라운드마다 모두 한 번씩 주사위 → 칸 효과. 라운드가 끝날 때마다:
##   내려칠 때가 된 칸(붉게 빛나고 옆에서 촉수가 꿈틀)을 내려침 → 거기 서 있으면 하트 -1
##   기한이 끝난 독가시 칸 · 상점 가격 폭등이 풀림
##   탈락한 사람은 크라켄의 부하가 되어 다음 라운드에 내려칠 칸을 하나씩 고름
##   2 라운드마다 크라켄 차례: 행동 하나를 무작위로 (Rules.KRAKEN_ACTIONS 참고)
## 마지막까지 살아남은 사람(2대2는 팀)이 승리. 맵은 board_maps.gd 의 SUNKEN ISLAND.

const BOARD_TITLES := {"sunken_island": "SUNKEN ISLAND"}

var rig_kraken := ""          ## 다음 크라켄 행동 ("" = 무작위)
var hold_loop := false        ## 개발용: 크라켄 등장 뒤 게임을 진행하지 않음 (장면 촬영용)
var _attack_cd := Rules.KRAKEN_ATTACK_EVERY   ## 크라켄 차례까지 남은 라운드 (이번 라운드 포함)
var _attacks := 0             ## 지금까지 크라켄 차례 수 (공격이 점점 거세짐)
var _strike_due := {}         ## 칸 → 이 라운드가 끝날 때 내려침
var _spines := {}             ## 독가시 칸 → {"until": 이 라운드 끝에 풀림, "prev": 원래 칸 변화}
var _surge_until := -1        ## 이 라운드 끝에 상점 가격이 돌아옴


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
	if hold_loop:
		return
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
		_update_round_label()
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


## 왼쪽 위: 라운드 + 크라켄 차례까지 남은 라운드 + 걸려 있는 효과
func _update_round_label() -> void:
	var t := tr("ROUND %d / %d") % [_round, _round_limit()]
	t += "\n" + (tr("Kraken's turn: end of this round") if _attack_cd <= 1 else tr("Kraken's turn: in %d rounds") % _attack_cd)
	if _surge_until >= _round:
		t += "\n" + tr("Shop prices x2")
	if not _spines.is_empty():
		t += "\n" + tr("Poison spines: %d spaces") % _spines.size()
	_round_label.text = t


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
	var eye := world.kraken_eye_pos()
	_move_camera(Vector3(lair.x, 6.0, -world.half_d + 2.0), 3.0, 1.6)
	_cinematic(Vector3(eye.x - 16.0, 20.0, -world.half_d + 46.0), eye + Vector3(0, 2.0, -6.0), 1.0, 1.6)
	await get_tree().create_timer(1.6, false).timeout
	Audio.play("box_rumble")
	_shake_camera(0.25, 1.2)
	world.kraken_awaken()
	await get_tree().create_timer(1.6, false).timeout
	Audio.play("box_burst")
	_shake_camera(0.6, 0.8)
	# 촉수들이 판을 콱 움켜쥠
	await get_tree().create_timer(2.05, false).timeout
	Audio.play("box_burst")
	_shake_camera(0.9, 0.9)
	await get_tree().create_timer(1.6, false).timeout
	shot_hint = "34_kraken_awakens"
	await _banner(tr("THE KRAKEN AWAKENS!"), tr("Dodge its tentacles. Last one standing wins!"), 1.8)
	# 연출 카메라에서 판 전체 보기로 (크라켄이 판을 움켜쥔 모습이 한눈에), 그다음 첫 차례로
	_move_camera(world.overview, world.overview_zoom, 0.01)
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 1.6)
	await _banner(tr("EVERY 2 ROUNDS..."), tr("...the kraken takes its turn. Stay alert!"), 1.4)


## 라운드 끝: 때가 된 칸 내려치기 → 효과 풀기 → 부하들이 칸 고르기 → (2 라운드마다) 크라켄 차례
func _kraken_phase(r: int) -> void:
	_highlight_chip({})
	await _kraken_strikes(r)
	if _over():
		return
	await _expire_effects(r)
	for q in _pawns:
		if not bool(q["alive"]):
			await _minion_mark(q)
	_attack_cd -= 1
	if _attack_cd <= 0:
		_attack_cd = Rules.KRAKEN_ATTACK_EVERY
		await _kraken_turn(r)


## 칸을 붉게 표시하고, due 라운드가 끝날 때 내려치게 예약
func _mark(t: int, due: int, light: bool = true) -> void:
	world.mark_danger(t, light)
	_strike_due[t] = mini(int(_strike_due.get(t, due)), due)


func _kraken_strikes(r: int) -> void:
	var targets: Array = []
	for t in world.danger_tiles():
		if int(_strike_due.get(t, r)) <= r:
			targets.append(t)
	if targets.is_empty():
		return
	_follow = null
	if targets.size() > Rules.KRAKEN_MASS_STRIKE:
		await _mass_strike(targets)
		return
	await _banner(tr("THE KRAKEN STRIKES!"), "", 0.7)
	for t in targets:
		_strike_due.erase(t)
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
		for q in _alive_pawns():
			if int(q["tile"]) == t:
				await _damage(q, 1)
		await get_tree().create_timer(0.7, false).timeout


## 촉수 폭풍: 판 전체를 보여 주며 모든 붉은 칸을 거의 한꺼번에 내려침 → 맞은 사람을 한 명씩 보여 줌
func _mass_strike(targets: Array) -> void:
	for t in targets:
		_strike_due.erase(t)
	_move_camera(world.overview, world.overview_zoom * 0.85, 0.9)
	await get_tree().create_timer(0.9, false).timeout
	Audio.play("box_rumble")
	_shake_camera(0.3, 1.2)
	await _banner(tr("TENTACLE STORM!"), "", 0.6)
	for t in targets:
		world.tentacle_strike(t, _rng.randf_range(0.0, 0.9))
	# 솟구침(0.5) + 젖힘(0.35) + 내려침(0.22) 뒤 쾅쾅쾅
	await get_tree().create_timer(1.1, false).timeout
	Audio.play("box_burst")
	_shake_camera(1.0, 1.1)
	await get_tree().create_timer(0.5, false).timeout
	Audio.play("box_burst")
	shot_hint = "49b_kraken_strike"
	await get_tree().create_timer(0.8, false).timeout
	var hit := []
	for q in _alive_pawns():
		if targets.has(int(q["tile"])):
			hit.append(q)
	if hit.is_empty():
		await _banner(tr("NOBODY WAS HIT!"), tr("Everyone dodged the storm."), 0.9)
		return
	for q in hit:
		if _over():
			return
		focus_on(q, 0.6)
		await get_tree().create_timer(0.6, false).timeout
		await _damage(q, 1)
	_follow = null


## 기한이 끝난 독가시 칸 · 상점 폭등 되돌리기
func _expire_effects(r: int) -> void:
	var done := []
	for t in _spines:
		if int(_spines[t]["until"]) <= r:
			done.append(t)
	if done.size() > 0:
		_follow = null
		_move_camera(world.overview, world.overview_zoom * 0.7, 0.8)
		await get_tree().create_timer(0.8, false).timeout
		for t in done:
			var prev: String = _spines[t]["prev"]
			_spines.erase(t)
			if prev == "":
				_tile_mods.erase(t)
				world.set_tile_look(t, String(world.spaces[t]["kind"]))
			else:
				_tile_mods[t] = prev
				world.set_tile_look(t, prev)
			Audio.play("toast")
			await get_tree().create_timer(0.15, false).timeout
		await _banner(tr("THE SPINES WITHER"), tr("The poison spaces are back to normal."), 0.9)
	if _surge_until >= 0 and _surge_until <= r:
		_surge_until = -1
		shop_price_mult = 1
		await _banner(tr("THE MERCHANT CALMS DOWN"), tr("Shop prices are back to normal."), 0.9)


## 크라켄 차례: 행동 하나를 무작위로
func _kraken_turn(r: int) -> void:
	_attacks += 1
	var acts: Array = Rules.KRAKEN_ACTIONS
	var a: String = rig_kraken if rig_kraken != "" else String(acts[_rng.randi() % acts.size()])
	rig_kraken = ""
	_follow = null
	# 크라켄이 몸을 일으키며 으르렁
	_move_camera(world.overview, world.overview_zoom * 0.85, 0.9)
	Audio.play("box_rumble")
	_shake_camera(0.4, 1.0)
	await get_tree().create_timer(0.9, false).timeout
	await _banner(tr("THE KRAKEN'S TURN!"), "", 0.9)
	match a:
		"barrage":
			await _kraken_barrage(r)
		"spines":
			await _kraken_spines(r)
		"surge":
			await _kraken_surge(r)


## 1) 많은 칸을 붉게 표시 → 다음 라운드 끝에 내려침
func _kraken_barrage(r: int) -> void:
	var n := mini(Rules.KRAKEN_TARGETS_MAX, int(Rules.KRAKEN_TARGETS_BASE + Rules.KRAKEN_TARGETS_GROW * (_attacks - 1)))
	await _kraken_aim(n, r + 1)
	shot_hint = "60_kraken_barrage"
	await _banner(tr("TENTACLE STORM!"), tr("It will smash every red space at the end of next round!"), 1.4)


## 2) 적은 칸을 2 라운드 동안 독가시 칸으로 (상점 · 포털 · 미니게임 칸도 바뀔 수 있음)
func _kraken_spines(r: int) -> void:
	var n := mini(Rules.KRAKEN_SPINES_MAX, Rules.KRAKEN_SPINES_BASE + int((_attacks - 1) / 2.0))
	var picks := []
	var alive := _alive_pawns()
	for k in n:
		var pool := []
		if alive.size() > 0 and _rng.randf() < Rules.KRAKEN_AIM_AT_PAWN:
			var q: Dictionary = alive[_rng.randi() % alive.size()]
			pool = _reachable(int(q["tile"]), 1, 6)
		pool = pool.filter(func(i: int) -> bool: return not picks.has(i) and not _spines.has(i))
		if pool.is_empty():
			pool = _aimable().filter(func(i: int) -> bool: return not picks.has(i) and not _spines.has(i))
		if pool.size() > 0:
			picks.append(pool[_rng.randi() % pool.size()])
	if picks.is_empty():
		return
	_move_camera(world.overview, world.overview_zoom * 0.7, 0.8)
	await get_tree().create_timer(0.8, false).timeout
	_legend_add("urchin")
	for t in picks:
		_spines[t] = {"until": r + Rules.KRAKEN_EFFECT_ROUNDS, "prev": String(_tile_mods.get(t, ""))}
		_tile_mods[t] = "urchin"
		world.set_tile_look(t, "urchin")
		Audio.play("remove")
		await get_tree().create_timer(0.3, false).timeout
	shot_hint = "60_kraken_spines"
	await _banner(tr("POISON SPINES!"), tr("Stopping on a purple space costs a heart — for %d rounds!") % Rules.KRAKEN_EFFECT_ROUNDS, 1.4)


## 4) 2 라운드 동안 상점 가격 2 배
func _kraken_surge(r: int) -> void:
	var shops: Array = world.spaces_of_kind("shop")
	if shops.size() > 0:
		var sp: Vector3 = world.spaces[int(shops[0])]["pos"]
		_move_camera(sp + Vector3(0, 0.5, 0), 1.8, 0.8)
		await get_tree().create_timer(0.8, false).timeout
		for t in shops:
			world.bubbles_at(world.spaces[int(t)]["pos"], 18, 0.8, true)
		Audio.play("box_burst")
		_shake_camera(0.4, 0.5)
	shop_price_mult = Rules.KRAKEN_SURGE_MULT
	_surge_until = r + Rules.KRAKEN_EFFECT_ROUNDS
	shot_hint = "60_kraken_surge"
	await _banner(tr("SHOP PANIC!"), tr("The kraken scared the merchant. Prices x%d for %d rounds!") % [Rules.KRAKEN_SURGE_MULT, Rules.KRAKEN_EFFECT_ROUNDS], 1.4)


## 크라켄이 다음에 내려칠 칸들 (대개 누군가 다음 차례에 멈출 만한 곳)
func _kraken_aim(n: int, due: int) -> void:
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
	# 수십 칸이면 빠르게 촤르륵 (전부 합쳐 2.5초 안쪽)
	var gap := clampf(2.5 / picks.size(), 0.04, 0.18)
	for k in picks.size():
		_mark(picks[k], due, picks.size() <= 8 or k % 6 == 0)
		if k % 3 == 0 or picks.size() <= 8:
			Audio.play("tick")
		await get_tree().create_timer(gap, false).timeout
	shot_hint = "49_kraken_aim"


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
		_mark(t, _round + 1)
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
		_mark(near[k], _round)
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
		var eye := world.kraken_eye_pos() + Vector3(1.57 * world.KRAKEN_SCALE, 0, 0)
		_cinematic(eye + Vector3(10.0, -4.0, 16.0), eye, 1.0, 1.0)
		await get_tree().create_timer(1.3, false).timeout
		shot_hint = "35_kraken_eye"
		await get_tree().create_timer(2.4, false).timeout
		var c0: Node3D = world.kraken_coils[0]["tn"]["root"]
		_cinematic(c0.position + Vector3(-38.0, 26.0, 46.0), c0.position + Vector3(4.0, 6.0, 14.0), 1.0, 1.0)
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
			_mark(int(q["tile"]), 0)
			break
	await _kraken_strikes(0)
	for q in _pawns:
		if not bool(q["alive"]):
			await _minion_mark(q)
			break
	# 크라켄 차례 행동 하나씩 (+ 가격이 오른 상점)
	for a in Rules.KRAKEN_ACTIONS:
		rig_kraken = String(a)
		await _kraken_turn(0)
	await _open_shop(me)
	for id in Minigames.ids():
		rig_minigame = String(id)
		await _run_minigame(me, false)
