extends "res://scripts/board/board_session.gd"
## 진짜 보드 게임 한 판: 크라켄 생존전 (개인전 · 2대2). 로비 → 보드 고르기 → PLAY 로 시작.
## 각자 하트 5개. 라운드마다 모두 한 번씩 주사위 → 칸 효과. 라운드가 끝날 때마다:
##   내려칠 때가 된 칸(붉게 빛나고 옆에서 촉수가 꿈틀)을 내려침 → 거기 서 있으면 하트 -1
##   기한이 끝난 독가시 칸 · 상점 가격 폭등이 풀림
##   탈락한 사람은 크라켄의 부하가 되어 다음 라운드에 내려칠 칸을 하나씩 고름
##   2 라운드마다 크라켄 차례: 행동 하나를 무작위로 (Rules.KRAKEN_ACTIONS 참고)
## 마지막까지 살아남은 사람(2대2는 팀)이 승리. 맵은 board_maps.gd 의 SUNKEN ISLAND.

const BOARD_TITLES := {"sunken_island": "SUNKEN ISLAND"}

var rig_kraken := ""          ## 다음 크라켄 행동 ("" = 무작위)
var hold_loop := false        ## 개발용: 크라켄 등장 뒤 게임을 진행하지 않음 (장면 촬영용)
var _kraken_awake := false   ## 처음 KRAKEN_WAKE_ROUND 라운드 동안은 잠들어 있음
var _attack_cd := Rules.KRAKEN_ATTACK_EVERY   ## 크라켄 차례까지 남은 라운드 (이번 라운드 포함)
var _attacks := 0             ## 지금까지 크라켄 차례 수 (공격이 점점 거세짐)
var _strike_due := {}         ## 칸 → 이 라운드가 끝날 때 내려침
var _spines := {}             ## 독가시 칸 → {"until": 이 라운드 끝에 풀림, "prev": 원래 칸 변화}
var _surge_until := -1        ## 이 라운드 끝에 상점 가격이 돌아옴
var _ship_until := -1         ## 이 라운드 끝에 크라켄의 배에서 섬으로 돌아옴


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
	if hold_loop:
		return
	if GameState.debug_showcase:
		await _kraken_wakes()
		_kraken_awake = true
		await _debug_showcase()
	else:
		# 크라켄은 아직 섬 밑에서 잠들어 있음 → 주사위를 두 번 굴린 뒤 깨어남
		_move_camera(world.overview, world.overview_zoom, 1.0)
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
			if int(p.get("skip", 0)) > 0:
				await _skip_turn(p)
				await _net_sync()
				continue
			await _play_turn(p)
			if _over():
				break
			await _tile_effect(p)
			await _net_sync()
			if _over():
				break
		if _over():
			break
		await _kraken_phase(r)
		await _net_sync()
	_over()
	_highlight_chip({})
	await _show_results()


## 왼쪽 위: 라운드 + 크라켄 차례까지 남은 라운드 + 걸려 있는 효과
func _update_round_label() -> void:
	var t := tr("ROUND %d / %d") % [_round, _round_limit()]
	if world.on_ship:
		var left := mini(_ship_until - _round + 1, Rules.SHIP_ROUNDS)
		t += "\n" + (tr("Kraken's ship: back to the island after this round") if left <= 1 else tr("Kraken's ship: %d rounds left") % left)
	elif not _kraken_awake:
		var w := Rules.KRAKEN_WAKE_ROUND - _round + 1
		t += "\n" + (tr("The kraken wakes: end of this round") if w <= 1 else tr("The kraken wakes: in %d rounds") % w)
	else:
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
	# 보드 음악을 끊고 웅장하고 어두운 등장 음악 (처음엔 물속처럼 먹먹하다가 포효에 맞춰 터짐)
	await Audio.stop_music(0.8)
	Audio.play_music(0.0, "kraken_wake")
	# 판 북쪽 끝에서 올려다보는 연출: 깊은 곳에서 거대한 머리와 눈이 솟아오름
	var eye := world.kraken_eye_pos()
	_move_camera(Vector3(lair.x, 6.0, -world.half_d + 2.0), 3.0, 1.6)
	_cinematic(Vector3(eye.x - 16.0, 20.0, -world.half_d + 46.0), eye + Vector3(0, 2.0, -6.0), 1.0, 1.6)
	await get_tree().create_timer(1.6, false).timeout
	Audio.play("kraken_rumble")
	_shake_camera(0.25, 1.2)
	world.kraken_awaken()
	await get_tree().create_timer(1.6, false).timeout
	Audio.play("roar")
	_shake_camera(0.6, 0.8)
	# 촉수들이 판을 콱 움켜쥠
	await get_tree().create_timer(2.05, false).timeout
	Audio.play("kraken_rumble")
	Audio.play("kraken_slam")
	_shake_camera(0.9, 0.9)
	await get_tree().create_timer(1.6, false).timeout
	shot_hint = "34_kraken_awakens"
	await _banner(tr("THE KRAKEN AWAKENS!"), "", 1.8)
	# 연출 카메라에서 판 전체 보기로 (크라켄이 판을 움켜쥔 모습이 한눈에), 그다음 첫 차례로
	_move_camera(world.overview, world.overview_zoom, 0.01)
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 1.6)
	await get_tree().create_timer(1.0, false).timeout


## 깨어나기 전 라운드 끝: 땅이 우르르 · 북쪽 골짜기에서 거품
func _kraken_stirs() -> void:
	if world.kraken_root == null:
		return
	_follow = null
	var lair := world.kraken_root.position
	_move_camera(Vector3(lair.x, 2.0, -world.half_d + 4.0), 4.0, 1.0)
	await get_tree().create_timer(1.0, false).timeout
	Audio.play("kraken_rumble")
	_shake_camera(0.18, 1.4)
	for k in 3:
		world.bubbles_at(Vector3(lair.x + (k - 1) * 3.0, 0.3, -world.half_d + 3.0), 16, 0.7, true)
	await get_tree().create_timer(1.6, false).timeout
	_move_camera(world.overview, world.overview_zoom, 1.0)
	await get_tree().create_timer(0.6, false).timeout


## 라운드 끝: 때가 된 칸 내려치기 → 효과 풀기 → 부하들이 칸 고르기 → (2 라운드마다) 크라켄 차례
func _kraken_phase(r: int) -> void:
	_highlight_chip({})
	# 잠든 동안: 섬이 점점 흔들리다가, 때가 되면 깨어나서 곧바로 첫 차례
	if not _kraken_awake and not world.on_ship:
		if r < Rules.KRAKEN_WAKE_ROUND:
			await _kraken_stirs()
			return
		await _kraken_wakes()
		_kraken_awake = true
		_attack_cd = Rules.KRAKEN_ATTACK_EVERY
		_update_round_label()
		await _kraken_turn(r)
		# 첫 차례가 끝나면 등장 음악을 서서히 내리고 원래 음악으로 (배로 끌려갔으면 배 음악이 이미 나옴)
		if Audio.current_track() == "kraken_wake":
			await Audio.stop_music(1.5)
			Audio.play_music(2.0, "board")
		return
	# 크라켄의 배 위: 공격 없음. 때가 되면 섬으로 돌아가고, 그때부터 다음 크라켄 차례를 다시 셈
	if world.on_ship:
		if r >= _ship_until:
			await _ship_return()
			_attack_cd = Rules.KRAKEN_ATTACK_EVERY
			_update_round_label()
			await _expire_effects(r)
		return
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
		Audio.play("kraken_rise")
		world.tentacle_strike(t)
		await world.tentacle_slammed
		shot_hint = "49b_kraken_strike"
		Audio.play("kraken_slam")
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
	Audio.play("kraken_rumble")
	_shake_camera(0.3, 1.2)
	await _banner(tr("TENTACLE STORM"), "", 0.6)
	for t in targets:
		world.tentacle_strike(t, _rng.randf_range(0.0, 0.9))
	# 솟구침(0.5) + 젖힘(0.35) + 내려침(0.22) 뒤 쾅쾅쾅
	Audio.play("kraken_rise")
	await get_tree().create_timer(1.1, false).timeout
	Audio.play("kraken_slam")
	_shake_camera(1.0, 1.1)
	await get_tree().create_timer(0.5, false).timeout
	Audio.play("kraken_slam")
	shot_hint = "49b_kraken_strike"
	await get_tree().create_timer(0.8, false).timeout
	var hit := []
	for q in _alive_pawns():
		if targets.has(int(q["tile"])):
			hit.append(q)
	if hit.is_empty():
		await get_tree().create_timer(0.4, false).timeout
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
		await _banner(tr("The poison spines fade"), "", 0.9)
	if _surge_until >= 0 and _surge_until <= r:
		_surge_until = -1
		shop_price_mult = 1
		await _banner(tr("THE MERCHANT CALMS DOWN"), "", 0.9)


## 크라켄 차례: 행동 하나를 무작위로
func _kraken_turn(r: int) -> void:
	_attacks += 1
	var acts: Array = Rules.KRAKEN_ACTIONS
	var a: String = rig_kraken if rig_kraken != "" else String(acts[_rng.randi() % acts.size()])
	rig_kraken = ""
	_follow = null
	# 크라켄이 몸을 일으키며 으르렁
	_move_camera(world.overview, world.overview_zoom * 0.85, 0.9)
	Audio.play("kraken_rumble")
	Audio.play("roar")
	_shake_camera(0.4, 1.0)
	await get_tree().create_timer(0.9, false).timeout
	await _kraken_card(a)
	match a:
		"barrage":
			await _kraken_barrage(r)
		"spines":
			await _kraken_spines(r)
		"surge":
			await _kraken_surge(r)
		"ship":
			await _kraken_ship(r)


## 크라켄 행동 카드: 크라켄 눈이 그려진 카드가 떠올라 부르르 떨다가 뒤집히며 행동 그림 · 이름 · 설명
const KRAKEN_CARDS := {
	"barrage": {"title": "TENTACLE STORM", "art": preload("res://textures/ui/kraken/art_barrage.png"),
		"text": "At the end of next round, it smashes every area marked in red."},
	"spines": {"title": "POISON SPINES", "art": preload("res://textures/ui/kraken/art_spines.png"),
		"text": "Turns random spaces into poison spine spaces that instantly hurt players who land on them."},
	"surge": {"title": "SHOP PANIC", "art": preload("res://textures/ui/kraken/art_surge.png"),
		"text": "The frightened merchant doubles shop prices for 2 rounds."},
	"ship": {"title": "THE KRAKEN'S SHIP", "art": preload("res://textures/ui/kraken/art_ship.png"),
		"text": "Portals open beneath every player, dropping them onto the kraken's flying ship for 2 rounds."},
}
const KRAKEN_CARD_BACK := preload("res://textures/ui/kraken/back_board.png")   ## tools/make_card_back.py
const KCARD_NEON := Color(0.45, 1.0, 0.32)
const KCARD_DARK := Color(0.02, 0.08, 0.06)


func _kraken_card_frame(size: Vector2) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = KCARD_DARK
	st.border_color = KCARD_NEON.darkened(0.15)
	st.set_border_width_all(5)
	st.set_corner_radius_all(24)
	st.shadow_color = Color(KCARD_NEON, 0.35)
	st.shadow_size = 26
	st.anti_aliasing = true
	return st


## 둥근 창 안에 그림 (그림이 창 모양으로 잘림)
func _kraken_card_window(tex: Texture2D, size: Vector2, radius: int) -> Panel:
	var win := Panel.new()
	win.custom_minimum_size = size
	win.size = size
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color.WHITE
	ws.set_corner_radius_all(radius)
	ws.anti_aliasing = true
	win.add_theme_stylebox_override("panel", ws)
	win.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(art)
	return win


## 띄어쓰기 단위로 줄바꿈 (한 줄이 width 를 넘지 않게)
func _wrap_words(text: String, font: Font, fs: int, width: float) -> String:
	var lines := []
	var cur := ""
	for w in text.split(" ", false):
		var t := w if cur == "" else cur + " " + w
		if cur != "" and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			lines.append(cur)
			cur = w
		else:
			cur = t
	if cur != "":
		lines.append(cur)
	return "\n".join(lines)


## 행동마다 오라 색 (촉수 폭풍 초록 · 독 가시 보라 · 상점 주황 · 크라켄의 배 검붉은색)
const KRAKEN_AURA := {
	"barrage": Color(0.4, 1.0, 0.3), "spines": Color(0.72, 0.3, 1.0),
	"surge": Color(1.0, 0.55, 0.12), "ship": Color(0.62, 0.03, 0.05),
}
const CardAuraShader := preload("res://shaders/card_aura.gdshader")
const KCARD_SIZE := Vector2(400, 580)
const KCARD_COUNT := 7        ## 돌아가는 카드 수


func _kraken_card_back() -> Panel:
	var back := Panel.new()
	back.size = KCARD_SIZE
	back.pivot_offset = KCARD_SIZE * 0.5
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", _kraken_card_frame(KCARD_SIZE))
	var bw := _kraken_card_window(KRAKEN_CARD_BACK, KCARD_SIZE - Vector2(44, 44), 16)
	bw.position = Vector2(22, 22)
	back.add_child(bw)
	return back


## 크라켄 행동 카드 뽑기: 뒷면 카드들이 둥글게 돌며(반시계) 점점 느려지다 멈춤 → 뽑힌 카드만 앞으로 와서 뒤집힘 + 행동 색 오라
func _kraken_card(a: String) -> void:
	var data: Dictionary = KRAKEN_CARDS[a]
	var aura_col: Color = KRAKEN_AURA.get(a, KCARD_NEON)
	var v := get_viewport().get_visible_rect().size
	var size := KCARD_SIZE
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_root.add_child(holder)
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.01, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dim)
	var deck := Control.new()
	deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(deck)
	var center := v * 0.5
	var k_n := KCARD_COUNT
	var chosen := _rng.randi() % k_n
	var cards: Array[Panel] = []
	for k in k_n:
		var b := _kraken_card_back()
		deck.add_child(b)
		cards.append(b)
	var rx := minf(v.x * 0.3, 520.0)
	var ry := 70.0
	var base_scale := 0.62
	# 카드 배치: 바닥 쪽(앞)일수록 크고 밝고 위에 그려짐
	var place := func(spin: float, spread: float) -> void:
		var order := []
		for k in k_n:
			var th := spin + TAU * k / k_n
			var depth := cos(th)          # 1 = 맨 앞
			var c: Panel = cards[k]
			var sc := base_scale * (0.72 + 0.28 * (depth + 1.0) * 0.5)
			c.scale = Vector2(sc, sc)
			c.position = center + Vector2(sin(th) * rx * spread, cos(th) * ry * spread - 30.0) - size * 0.5
			c.rotation = sin(th) * 0.12 * spread
			c.modulate = Color(1, 1, 1).darkened(0.45 * (1.0 - (depth + 1.0) * 0.5))
			order.append([depth, c])
		order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for o in order:
			deck.move_child(o[1], -1)
	# 1) 카드들이 가운데에서 둥글게 펼쳐짐
	Audio.play("card_draw")
	var t0 := create_tween()
	t0.tween_property(dim, "color:a", 0.55, 0.3)
	t0.parallel().tween_method(func(f: float) -> void: place.call(-f * 1.2, f), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t0.finished
	# 2) 반시계로 빠르게 돌다가 점점 느려져 뽑힌 카드가 맨 앞에 딱 멈춤
	var start := -1.2
	var target := TAU * 4.0 - TAU * chosen / k_n
	while target - start < TAU * 3.0:
		target += TAU
	var last_slot := [int(floor(start / (TAU / k_n)))]
	var spin_t := create_tween()
	spin_t.tween_method(func(sp: float) -> void:
		place.call(sp, 1.0)
		var slot := int(floor(sp / (TAU / k_n)))
		if slot != last_slot[0]:
			last_slot[0] = slot
			Audio.play("card_pass", 40), start, target, 3.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await spin_t.finished
	await get_tree().create_timer(0.25, false).timeout
	# 3) 나머지는 흩어지고, 뽑힌 카드만 앞으로 크게
	var pick: Panel = cards[chosen]
	var gather := create_tween().set_parallel(true)
	for k in k_n:
		if k == chosen:
			continue
		var c: Panel = cards[k]
		gather.tween_property(c, "modulate:a", 0.0, 0.35)
		gather.tween_property(c, "scale", c.scale * 0.8, 0.35)
	gather.tween_property(pick, "position", center - size * 0.5, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gather.tween_property(pick, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gather.tween_property(pick, "rotation", 0.0, 0.4)
	await gather.finished
	# 오라 (카드 뒤에서 일렁임)
	var aura := ColorRect.new()
	var pad := Vector2(180, 200)
	aura.size = size + pad
	aura.position = center - aura.size * 0.5
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var am := ShaderMaterial.new()
	am.shader = CardAuraShader
	am.set_shader_parameter("aura_color", aura_col)
	am.set_shader_parameter("rect_px", aura.size)
	am.set_shader_parameter("card_px", size)
	am.set_shader_parameter("strength", 0.0)
	am.set_shader_parameter("bright", 1.0 if aura_col.get_luminance() > 0.2 else 0.3)
	aura.material = am
	holder.add_child(aura)
	holder.move_child(aura, deck.get_index())
	# 앞면
	var front := Panel.new()
	front.size = size
	front.pivot_offset = size * 0.5
	front.position = center - size * 0.5
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fst := _kraken_card_frame(size)
	fst.border_color = aura_col.lerp(Color.WHITE, 0.15) if aura_col.get_luminance() > 0.2 else aura_col.lightened(0.35)
	fst.shadow_color = Color(aura_col, 0.45)
	front.add_theme_stylebox_override("panel", fst)
	front.scale = Vector2(0.05, 1.0)
	front.visible = false
	holder.add_child(front)
	var fv := VBoxContainer.new()
	fv.position = Vector2(22, 18)
	fv.size = Vector2(size.x - 44, size.y - 36)
	fv.add_theme_constant_override("separation", 12)
	fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(fv)
	var head := Label.new()
	head.text = tr("KRAKEN'S MOVE")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", aura_col.lerp(Color.WHITE, 0.25) if aura_col.get_luminance() > 0.2 else Color(0.9, 0.35, 0.35))
	fv.add_child(head)
	var aw := _kraken_card_window(data["art"], Vector2(size.x - 44, (size.x - 44) * 0.75), 14)
	fv.add_child(aw)
	var t1 := Label.new()
	t1.text = tr(String(data["title"]))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_font_size_override("font_size", 44)
	t1.add_theme_color_override("font_color", Color(0.92, 1.0, 0.86))
	t1.add_theme_color_override("font_outline_color", Color(0.0, 0.1, 0.05))
	t1.add_theme_constant_override("outline_size", 8)
	fv.add_child(t1)
	var t2 := Label.new()
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.custom_minimum_size = Vector2(size.x - 60, 0)
	t2.add_theme_font_size_override("font_size", 22)
	fv.add_child(t2)
	t2.text = _wrap_words(tr(String(data["text"])), t2.get_theme_font("font"), 22, size.x - 64)
	t2.add_theme_color_override("font_color", Color(0.8, 0.92, 0.84))
	t2.add_theme_constant_override("line_spacing", 4)
	# 4) 잠깐 뜸 들였다가 천천히 뒤집힘 + 오라가 웅웅 피어오름
	await get_tree().create_timer(0.45, false).timeout
	Audio.play("card_flip")
	var flip := create_tween()
	flip.tween_property(pick, "scale:x", 0.05, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	flip.tween_callback(func() -> void:
		pick.visible = false
		front.visible = true
		Audio.play("aura")
		_shake_camera(0.25, 0.5))
	flip.tween_property(front, "scale:x", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flip.parallel().tween_method(func(f: float) -> void: am.set_shader_parameter("strength", f), 0.0, 1.0, 0.9)
	await flip.finished
	shot_hint = "60_kraken_card_" + a
	await get_tree().create_timer(2.8, false).timeout
	var out := create_tween()
	out.tween_property(holder, "modulate:a", 0.0, 0.3)
	await out.finished
	holder.queue_free()


## 1) 많은 칸을 붉게 표시 → 다음 라운드 끝에 내려침
func _kraken_barrage(r: int) -> void:
	var n := mini(Rules.KRAKEN_TARGETS_MAX, int(Rules.KRAKEN_TARGETS_BASE + Rules.KRAKEN_TARGETS_GROW * (_attacks - 1)))
	await _kraken_aim(n, r + 1)
	shot_hint = "60_kraken_barrage"
	await get_tree().create_timer(0.8, false).timeout


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
	await get_tree().create_timer(0.8, false).timeout


## 4) 2 라운드 동안 상점 가격 2 배
func _kraken_surge(r: int) -> void:
	var shops: Array = world.spaces_of_kind("shop")
	if shops.size() > 0:
		var sp: Vector3 = world.spaces[int(shops[0])]["pos"]
		_move_camera(sp + Vector3(0, 0.5, 0), 1.8, 0.8)
		await get_tree().create_timer(0.8, false).timeout
		for t in shops:
			world.bubbles_at(world.spaces[int(t)]["pos"], 18, 0.8, true)
		Audio.play("splash")
		Audio.play("coins")
		_shake_camera(0.4, 0.5)
	shop_price_mult = Rules.KRAKEN_SURGE_MULT
	_surge_until = r + Rules.KRAKEN_EFFECT_ROUNDS
	shot_hint = "60_kraken_surge"
	await get_tree().create_timer(0.8, false).timeout


## 3) 크라켄의 배: 모두의 발밑에 포탈이 열려 밤하늘을 나는 배로 떨어짐 → Rules.SHIP_ROUNDS 라운드 뒤 섬으로
func _kraken_ship(r: int) -> void:
	if world.ship == null:
		return
	_ship_until = r + Rules.SHIP_ROUNDS
	# 섬에 남아 있던 붉은 칸은 거둠 (크라켄이 배를 띄우느라 바쁨)
	world.clear_all_dangers()
	_strike_due.clear()
	var alive := _alive_pawns()
	for q in _pawns:
		q["island_tile"] = q["tile"]
		q["island_prev"] = q["prev"]
	await _fall_through(alive, false)
	# 배 위 내려앉을 칸 (서로 멀리)
	var drops: Array = world.ship.drop_tiles.duplicate()
	for k in alive.size():
		var q: Dictionary = alive[k]
		var t: int = drops[k % drops.size()]
		q["tile"] = t
		q["prev"] = _prev_on_loop(t)
	await _arrive(alive, true)
	_legend_add("kraken_chest")
	_legend_add("cannon")
	_update_round_label()
	shot_hint = "60_kraken_ship"
	await _banner(tr("THE KRAKEN'S SHIP"), "", 1.4)


## 배에서 섬으로: 갑판에 포탈이 열려 떨어짐 → 원래 있던 칸 위 하늘에서 내려앉음
func _ship_return() -> void:
	var alive := _alive_pawns()
	_follow = null
	_move_camera(world.overview, world.overview_zoom * 0.85, 0.8)
	await get_tree().create_timer(0.8, false).timeout
	await _banner(tr("BACK TO THE ISLAND"), "", 0.9)
	await _fall_through(alive, true)
	for q in _pawns:
		if q.has("island_tile"):
			q["tile"] = q["island_tile"]
			q["prev"] = q["island_prev"]
			q.erase("island_tile")
			q.erase("island_prev")
	await _arrive(alive, false)
	_ship_until = -1


## 말들 발밑에 검붉은 포탈이 열리고 빙글빙글 빨려 들어감 → 화면이 까매짐
func _fall_through(alive: Array, from_ship: bool) -> void:
	_follow = null
	_move_camera(world.overview, world.overview_zoom * (0.85 if from_ship else 0.7), 0.8)
	await get_tree().create_timer(0.8, false).timeout
	var portals := []
	for q in alive:
		portals.append(world.drop_portal((q["node"] as Node3D).position + Vector3(0, 0.04, 0)))
		Audio.play("portal", 300)
		await get_tree().create_timer(0.12, false).timeout
	Audio.play("kraken_rumble")
	_shake_camera(0.35, 1.0)
	await get_tree().create_timer(0.7, false).timeout
	shot_hint = "60b_ship_portals" if not from_ship else "60e_ship_leave"
	await get_tree().create_timer(0.4, false).timeout
	Audio.play("whoosh")
	for q in alive:
		var node: Node3D = q["node"]
		var t := create_tween().set_parallel(true)
		t.tween_property(node, "position:y", node.position.y - 2.6, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(node, "rotation:y", node.rotation.y + TAU * 1.5, 0.75)
		t.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE * 0.5, 0.75)
	await get_tree().create_timer(0.8, false).timeout
	for q in alive:
		(q["node"] as Node3D).visible = false
	for p in portals:
		world.close_portal(p)
	await get_tree().create_timer(0.35, false).timeout
	_fade.get_parent().move_child(_fade, -1)
	await _fade_black(_fade, 1.0, 0.45)
	# 탈락한 말은 섬에 남음 (배 위에선 안 보이게)
	for q in _pawns:
		if not bool(q["alive"]):
			(q["node"] as Node3D).visible = from_ship
	if from_ship:
		world.leave_ship()
		Audio.play_ambience("")
		Audio.play_music(1.0, "board")
	else:
		world.enter_ship()
		Audio.play_ambience("wind", -14.0, 2.5)
		Audio.play_music(1.0, "ship")
	_update_round_label()


## 화면이 밝아지며 하늘에 포탈이 열리고 말들이 하나씩 떨어져 칸에 내려앉음
func _arrive(alive: Array, to_ship: bool) -> void:
	if to_ship:
		# 밤하늘을 나는 배를 옆에서 먼저 보여 줌
		var at: Vector3 = world.ship.AT
		_cinematic(at + Vector3(36.0, 14.0, 168.0), at + Vector3(4.0, 16.0, 0.0), 1.0, 0.01)
		_move_camera(world.overview, world.overview_zoom, 0.01)
		await get_tree().create_timer(0.15, false).timeout
		await _fade_black(_fade, 0.0, 0.7)
		shot_hint = "60c_ship_reveal"
		await get_tree().create_timer(1.6, false).timeout
		_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 1.4)
		await get_tree().create_timer(1.4, false).timeout
	else:
		_move_camera(world.overview, world.overview_zoom * 0.7, 0.01)
		await get_tree().create_timer(0.15, false).timeout
		await _fade_black(_fade, 0.0, 0.6)
	var portals := []
	for q in alive:
		var node: Node3D = q["node"]
		var spot := _spot_on(int(q["tile"]), q)
		portals.append(world.drop_portal(spot + Vector3(0, 7.5, 0), true))
		node.position = spot + Vector3(0, 7.0, 0)
		node.rotation.y = 0.0
		node.scale = Vector3.ONE * PAWN_SCALE * 0.5
		Audio.play("portal", 300)
		await get_tree().create_timer(0.15, false).timeout
	await get_tree().create_timer(0.45, false).timeout
	for k in alive.size():
		var q: Dictionary = alive[k]
		var node: Node3D = q["node"]
		var spot := _spot_on(int(q["tile"]), q)
		node.visible = true
		var t := create_tween().set_parallel(true)
		t.tween_property(node, "position", spot, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE, 0.35)
		t.tween_property(node, "rotation:y", TAU, 0.5)
		get_tree().create_timer(0.5, false).timeout.connect(func() -> void:
			Audio.play("thud", 60)
			_squash(node)
			world.bubbles_at(spot + Vector3(0, 0.2, 0), 10, 0.5, true))
		if k == 1:
			shot_hint = "60d_ship_drop"
		await get_tree().create_timer(0.3, false).timeout
	await get_tree().create_timer(0.55, false).timeout
	_shake_camera(0.3, 0.4)
	for p in portals:
		world.close_portal(p)
	await get_tree().create_timer(0.5, false).timeout


## 배 위 한 바퀴 길에서 t 바로 앞 칸 (떨어진 뒤 앞으로 가는 방향을 정함)
func _prev_on_loop(t: int) -> int:
	for i in world.spaces.size():
		if world.in_play(i) and (world.spaces[i]["next"] as Array).has(t) and (world.spaces[i]["links"] as Array).size() <= 2:
			return i
	for i in world.spaces.size():
		if world.in_play(i) and (world.spaces[i]["next"] as Array).has(t):
			return i
	return -1


## 배 위에서는 '크라켄 미끼' 카드가 나오지 않음 (크라켄이 배를 붙들고 있어서)
func _draw_card(p: Dictionary) -> void:
	if world.on_ship and rig_card == "":
		var c: Dictionary = Rules.random_card(_rng, true)
		while String(c["id"]) == "bait":
			c = Rules.random_card(_rng, true)
		rig_card = String(c["id"])
	await super(p)


## 크라켄이 다음에 내려칠 칸들 (대개 누군가 다음 차례에 멈출 만한 곳)
func _kraken_aim(n: int, due: int) -> void:
	var picks := _spread_picks(n)
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


## 촉수 폭풍이 노릴 칸 n 개를 판 전체에 고르게 (붙어 있는 칸끼리 몰리지 않게)
##   1) 살아 있는 사람마다 주사위로 갈 수 있는 앞 1~6 칸 중 Rules.KRAKEN_AIM_PER_PAWN 칸 (누구도 안전하지 않게)
##   2) 나머지는 '가장 먼 후보 고르기': 후보 몇 개를 뽑아, 이미 고른 칸들과 가장 멀리 떨어진 칸을 고름
##   어느 칸이든 이미 노린 칸과 Rules.KRAKEN_SPREAD_GAP m 안쪽이면 피함 (자리가 모자라면 간격을 조금씩 줄임)
func _spread_picks(n: int) -> Array:
	var picks := []
	var used := []          # 간격을 잴 위치 (이미 노린 칸 포함)
	for t in world.danger_tiles():
		used.append(world.spaces[t]["pos"])
	var taken := func(i: int) -> bool: return picks.has(i) or world.danger_tiles().has(i) or i == world.start_index
	var gap_to := func(i: int) -> float:
		var p: Vector3 = world.spaces[i]["pos"]
		var best := INF
		for u: Vector3 in used:
			best = minf(best, Vector2(p.x - u.x, p.z - u.z).length())
		return best
	# 후보들 중 기존 칸과 가장 먼 칸 (최소 간격 gap 이상만)
	var choose := func(cands: Array, gap: float, tries: int) -> int:
		var best_i := -1
		var best_d := -1.0
		var pool := cands.duplicate()
		_shuffle(pool)
		for k in mini(tries, pool.size()):
			var c: int = pool[k]
			if taken.call(c):
				continue
			var d: float = gap_to.call(c)
			if d >= gap and d > best_d:
				best_d = d
				best_i = c
		return best_i
	var add := func(i: int) -> void:
		picks.append(i)
		used.append(world.spaces[i]["pos"])
	# 1) 사람마다 앞길에 몇 칸
	var alive := _alive_pawns()
	_shuffle(alive)
	for q in alive:
		var near := _reachable(int(q["tile"]), 1, 6)
		for k in Rules.KRAKEN_AIM_PER_PAWN:
			if picks.size() >= n:
				break
			var t: int = choose.call(near, Rules.KRAKEN_SPREAD_GAP, near.size())
			if t >= 0:
				add.call(t)
	# 2) 나머지는 판 전체에 고르게
	var all := _aimable()
	var gap := Rules.KRAKEN_SPREAD_GAP
	while picks.size() < n and gap > 0.5:
		var t: int = choose.call(all, gap, 14)
		if t < 0:
			# 14 개를 뽑아 봤는데 자리가 없으면 전부 훑어 보고, 그래도 없으면 간격을 줄임
			t = choose.call(all, gap, all.size())
			if t < 0:
				gap *= 0.8
				continue
		add.call(t)
	return picks


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
	_shuffle(near)
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
