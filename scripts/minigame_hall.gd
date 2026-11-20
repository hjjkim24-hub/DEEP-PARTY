extends Control
## 미니게임 모음 (메인화면 MINIGAMES → 로비 → START → 여기)
##   1) 한 화면에 9개씩 3×3 카드 (게임 장면 + 이름). 9개가 넘으면 ◀ ▶ 로 넘김
##   2) 카드를 누르면 보드에서 걸렸을 때와 같은 소개 화면(설명 · 조작 · 준비) → 게임
##   3) 끝나면 순위 + [다시 하기] [미니게임 목록]
##   뒤로 / ESC → 같은 사람들이 그대로인 로비로

const Minigames := preload("res://scripts/minigames/registry.gd")
const MinigameIntro := preload("res://scripts/minigames/minigame_intro.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const PirateFonts := preload("res://scripts/ui/pirate_fonts.gd")
const BackgroundScene := preload("res://scenes/underwater_background.tscn")
const MAIN_MENU := "res://scenes/main_menu.tscn"
const THUMB_DIR := "res://textures/ui/minigames/"

const PER_PAGE := 9
const PEARL := Color("eafffa")
const AQUA := Color("5ff2d6")
const GOLD := Color("ffcf4a")
const TEXT_DIM := Color(0.75, 0.95, 0.9, 0.78)
const DEEP := Color(0.0, 0.1, 0.1)
const THUMB_SIZE := Vector2(360, 202)

var _ids: Array = []
var _page := 0
var _players: Array = []
var _rng := RandomNumberGenerator.new()

var _ui: Control                 ## 고르기 화면 (카드 · 제목 · 버튼)
var _grid: GridContainer
var _page_label: Label
var _prev_btn: Button
var _next_btn: Button
var _fade: ColorRect
var _layer: CanvasLayer          ## 소개 · 게임 · 결과가 올라가는 층
var _pause: Control
var _busy := false
var _playing_id := ""
var _run_token := 0              ## 게임 도중 나가면 늘려서, 끝난 뒤 처리 코드를 멈춤
var _current: Node               ## 지금 떠 있는 소개 화면이나 미니게임


## 온라인: "" 혼자 · "host" 방장(게임을 고르고 진행) · "client" 손님(방장을 따라감)
var _net := ""
var _wait_label: Label
var _seed := 0


func _ready() -> void:
	_rng.randomize()
	_ids = Minigames.ids()
	_net = "host" if Net.is_host() else ("client" if Net.is_guest() else "")
	_players = _make_players()
	if _net != "":
		Net.message.connect(_on_net)
		Net.room_closed.connect(_on_lost.bind("The host closed the room."))
		Net.disconnected.connect(_on_lost.bind("Lost connection to the server."))
	var th := Theme.new()
	PirateFonts.style_theme(th)
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	theme = th

	add_child(BackgroundScene.instantiate())
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.05, 0.06, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ui = Control.new()
	add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_picker()

	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)

	var pl := CanvasLayer.new()
	pl.layer = 50
	pl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pl)
	_pause = PauseMenu.new()
	pl.add_child(_pause)
	_pause.set_leave_text("LEAVE ROOM" if _net == "client" else "ALL MINIGAMES")
	_pause.leave_requested.connect(_abort_game)

	var fl := CanvasLayer.new()
	fl.layer = 60
	add_child(fl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_show_page(0)
	await get_tree().process_frame
	Audio.play_music(0.0, "mg_hall")
	await _fade_to(0.0, 0.6)


## 로비 자리 → 미니게임에 넘길 참가자 목록 (보드와 같은 모양)
func _make_players() -> Array:
	var list := []
	var cpu_no := 0
	for slot in GameState.MAX_PLAYERS:
		var p: Dictionary = GameState.players[slot]
		if p.is_empty():
			continue
		var pname := "You"
		var cpu := false
		match p.get("kind", ""):
			"cpu":
				cpu_no += 1
				pname = tr("CPU %d") % cpu_no
				cpu = true
			"host":
				if slot != GameState.my_slot:
					pname = "Host"
			"friend":
				if slot != GameState.my_slot:
					pname = tr("Player %d") % (slot + 1)
		list.append({"slot": slot, "name": pname, "cpu": cpu, "color": GameState.player_color(slot), "look": GameState.look(slot)})
	if list.is_empty():
		list.append({"slot": 0, "name": "You", "cpu": false, "color": GameState.PALETTE[0], "look": {}})
	return list


# ── 고르기 화면 ───────────────────────────────────────────────
func _build_picker() -> void:
	var margin := MarginContainer.new()
	_ui.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 110)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 48)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	var title := _outlined("MINIGAMES", 58)
	head.add_child(title)
	var sub := _outlined("Pick a minigame to play", 22, TEXT_DIM, 6)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_prev_btn = _glass_button("◀", Vector2(64, 60), 26)
	_prev_btn.pressed.connect(func() -> void: _show_page(_page - 1))
	head.add_child(_prev_btn)
	_page_label = _outlined("1 / 1", 24, PEARL, 6)
	_page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_page_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.add_child(_page_label)
	_next_btn = _glass_button("▶", Vector2(64, 60), 26)
	_next_btn.pressed.connect(func() -> void: _show_page(_page + 1))
	head.add_child(_next_btn)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	head.add_child(gap)
	var back := _glass_button("BACK", Vector2(170, 60), 22)
	back.set_meta("sfx", "back")
	back.pressed.connect(_back_to_lobby)
	head.add_child(back)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(center)
	if _net == "client":
		sub.text = "The host picks the minigame"
		_wait_label = _outlined("Waiting for the host to pick a game…", 26, GOLD, 8)
		_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_wait_label)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 34)
	_grid.add_theme_constant_override("v_separation", 22)
	center.add_child(_grid)


func _show_page(p: int) -> void:
	var pages := maxi(1, ceili(float(_ids.size()) / PER_PAGE))
	_page = clampi(p, 0, pages - 1)
	for c in _grid.get_children():
		c.queue_free()
	for i in range(_page * PER_PAGE, mini(_ids.size(), (_page + 1) * PER_PAGE)):
		_grid.add_child(_card(String(_ids[i])))
	_page_label.text = "%d / %d" % [_page + 1, pages]
	var multi := pages > 1
	_prev_btn.visible = multi
	_next_btn.visible = multi
	_page_label.visible = multi
	_prev_btn.disabled = _page == 0
	_next_btn.disabled = _page >= pages - 1


## 카드 한 장: 게임 장면 + 이름
func _card(id: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = THUMB_SIZE + Vector2(20, 66)
	b.add_theme_stylebox_override("normal", _glass(Color(0.02, 0.13, 0.13, 0.72), Color(PEARL, 0.22), 1, 16))
	b.add_theme_stylebox_override("hover", _glass(Color(0.05, 0.3, 0.28, 0.82), Color(AQUA, 0.85), 2, 16))
	b.add_theme_stylebox_override("pressed", _glass(Color(0.03, 0.22, 0.2, 0.85), AQUA, 2, 16))
	b.add_theme_stylebox_override("focus", _glass(Color(0, 0, 0, 0), Color(AQUA, 0.9), 2, 16))
	b.set_meta("sfx", "click")
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.offset_bottom = -8
	# 장면 (모서리 둥글게 잘라서)
	var clip := Panel.new()
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = THUMB_SIZE
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color.WHITE
	cs.set_corner_radius_all(10)
	clip.add_theme_stylebox_override("panel", cs)
	v.add_child(clip)
	var tr_ := TextureRect.new()
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := THUMB_DIR + id + ".png"
	if ResourceLoader.exists(path):
		tr_.texture = load(path)
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	clip.add_child(tr_)
	tr_.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 이름
	var name_l := _outlined(_title_of(id), 27, PEARL, 8)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	# 마우스를 올리면 살짝 커짐
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		Audio.play("hover")
		create_tween().tween_property(b, "scale", Vector2.ONE * 1.035, 0.12).set_trans(Tween.TRANS_SINE))
	b.mouse_exited.connect(func() -> void: create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	if _net == "client":
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_theme_stylebox_override("disabled", _glass(Color(0.02, 0.13, 0.13, 0.72), Color(PEARL, 0.22), 1, 16))
	else:
		b.pressed.connect(_play.bind(id))
	return b


var _titles := {}


## 미니게임 이름 (스크립트의 title, 언어에 맞게)
func _title_of(id: String) -> String:
	if not _titles.has(id):
		var mg: Control = Minigames.create(id, _rng)
		_titles[id] = String(mg.title)
		mg.free()
	return tr(_titles[id])


# ── 한 판: 소개 → 게임 → 결과 ────────────────────────────────
func _play(id: String, seed_: int = 0) -> void:
	if _busy:
		return
	_busy = true
	_playing_id = id
	_seed = seed_ if seed_ != 0 else randi() % 2000000000 + 1
	if _net == "host":
		Net.broadcast({"k": "hall_play", "id": id, "seed": _seed})
	_run_token += 1
	var token := _run_token
	Audio.stop_music(0.4)
	await _fade_to(1.0, 0.4)
	_ui.visible = false
	# 소개 화면 (설명 · 조작 · 준비 버튼)
	var intro := MinigameIntro.new()
	intro.setup(id, _players, GameState.debug_auto_minigames, Callable())
	intro.net_setup(_net, GameState.my_slot)
	_layer.add_child(intro)
	_current = intro
	Audio.play_music(0.0, "mg_intro")
	await _fade_to(0.0, 0.4)
	await intro.run()
	if token != _run_token:
		return
	Audio.stop_music(0.4)
	await _fade_to(1.0, 0.4)
	intro.queue_free()
	await _run_game(id, token)


func _run_game(id: String, token: int) -> void:
	var mg: Control = Minigames.create(id, _rng)
	mg.setup(_players, GameState.debug_auto_minigames, Callable())
	mg.net_seed = _seed
	mg.net_setup(_net, GameState.my_slot)
	_layer.add_child(mg)
	_current = mg
	Audio.play_music(0.0, id)
	await _fade_to(0.0, 0.4)
	var order: Array = await mg.run()
	if token != _run_token:
		return
	Audio.stop_music(0.4)
	await _fade_to(1.0, 0.4)
	mg.queue_free()
	_current = null
	_show_results(order, token)
	Audio.play_music(0.0, "results")
	await _fade_to(0.0, 0.4)


## 결과: 순위 + 다시 하기 / 미니게임 목록
func _show_results(order: Array, token: int) -> void:
	var root := Control.new()
	_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_current = root
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.05, 0.06, 0.6)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var st := _glass(Color(0.02, 0.12, 0.13, 0.9), Color(AQUA, 0.45), 2, 22)
	st.content_margin_left = 54
	st.content_margin_right = 54
	st.content_margin_top = 36
	st.content_margin_bottom = 36
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var t := _outlined(_title_of(_playing_id), 46)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := _outlined("RESULTS", 24, TEXT_DIM, 6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	v.add_child(sp)
	for k in order.size():
		v.add_child(_result_row(k + 1, order[k]))
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 14)
	v.add_child(sp2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	if _net == "client":
		var wl := _outlined("Waiting for the host…", 24, GOLD, 6)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(wl)
		_busy = false
		return
	var again := _glass_button("PLAY AGAIN", Vector2(250, 66), 22, true)
	again.pressed.connect(func() -> void:
		if token != _run_token:
			return
		_replay(root))
	row.add_child(again)
	var list := _glass_button("ALL MINIGAMES", Vector2(280, 66), 22)
	list.set_meta("sfx", "back")
	list.pressed.connect(func() -> void:
		if token != _run_token:
			return
		_back_to_picker())
	row.add_child(list)
	again.grab_focus.call_deferred()
	_busy = false


func _result_row(rank: int, q: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var r := _outlined(str(rank), 34, GOLD if rank == 1 else PEARL, 6)
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	r.custom_minimum_size = Vector2(40, 0)
	row.add_child(r)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ds := StyleBoxFlat.new()
	ds.bg_color = q.get("color", Color.WHITE)
	ds.set_corner_radius_all(13)
	ds.border_color = Color(1, 1, 1, 0.7)
	ds.set_border_width_all(2)
	dot.add_theme_stylebox_override("panel", ds)
	row.add_child(dot)
	var n := _outlined(String(q.get("name", "?")), 28, PEARL, 6)
	n.custom_minimum_size = Vector2(260, 0)
	row.add_child(n)
	return row


func _replay(results: Control, seed_: int = 0) -> void:
	if _busy:
		return
	_busy = true
	_seed = seed_ if seed_ != 0 else randi() % 2000000000 + 1
	if _net == "host":
		Net.broadcast({"k": "hall_again", "seed": _seed})
	_run_token += 1
	var token := _run_token
	Audio.stop_music(0.4)
	await _fade_to(1.0, 0.4)
	results.queue_free()
	await _run_game(_playing_id, token)


func _back_to_picker() -> void:
	if _net == "host":
		Net.broadcast({"k": "hall_list"})
	_run_token += 1
	Audio.stop_music(0.3)
	await _fade_to(1.0, 0.35)
	for c in _layer.get_children():
		c.queue_free()
	_current = null
	_ui.visible = true
	_busy = false
	Audio.play_music(0.0, "mg_hall")
	await _fade_to(0.0, 0.4)


## 게임 도중 ESC → [미니게임 목록] (손님은 방에서 나감)
func _abort_game() -> void:
	if _net == "client":
		Net.leave()
		_leave_to_menu("")
		return
	_back_to_picker()


func _back_to_lobby(forced: bool = false) -> void:
	if _busy and not forced:
		return
	if _net == "host":
		Net.broadcast({"k": "hall_lobby"})
	elif _net == "client" and not forced:
		# 손님이 뒤로 → 방에서 나감
		Net.leave()
		_leave_to_menu("")
		return
	_busy = true
	Audio.stop_music(0.5)
	await _fade_to(1.0, 0.4)
	GameState.return_to = "mg_lobby"
	get_tree().change_scene_to_file(MAIN_MENU)


## 온라인: 방장이 보낸 진행 신호 (손님 PC)
func _on_net(_from: int, d: Dictionary) -> void:
	if _net != "client" or not is_inside_tree():
		return
	match String(d.get("k", "")):
		"hall_play":
			if not _busy:
				_play(String(d.get("id", "")), int(d.get("seed", 1)))
		"hall_again":
			var res := _layer.get_children().filter(func(n: Node) -> bool: return n.get_script() == null)
			if not res.is_empty():
				_replay(res[0], int(d.get("seed", 1)))
		"hall_list":
			_back_to_picker()
		"hall_lobby":
			_back_to_lobby(true)


func _on_lost(msg: String) -> void:
	if _net == "client":
		_leave_to_menu(msg)
	else:
		_net = ""


## 손님이 방을 떠나 메인화면으로 (내 원래 말로)
func _leave_to_menu(msg: String) -> void:
	_run_token += 1
	_busy = true
	var me := {"kind": "host", "color": 0}
	if not GameState.my_profile.is_empty():
		me.merge(GameState.my_profile, true)
		me["kind"] = "host"
	GameState.players = [me, {}, {}, {}]
	GameState.my_slot = 0
	GameState.return_to = "toast:" + msg if msg != "" else ""
	Audio.stop_music(0.4)
	await _fade_to(1.0, 0.4)
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _pause.is_open():
		return
	get_viewport().set_input_as_handled()
	if _ui.visible and not _busy:
		Audio.play("back")
		_back_to_lobby()
	elif _current != null:
		_pause.open()


# ── 작은 도우미 ──────────────────────────────────────────────
func _fade_to(a: float, time: float) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if a > 0.5 else Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.tween_property(_fade, "color:a", a, time)
	await t.finished


func _outlined(text: String, size_: int, col: Color = PEARL, outline: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _glass(bg: Color, border: Color, bw: int, radius: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 8
	return s


func _glass_button(text: String, min_size: Vector2, font_size: int, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", DEEP if primary else PEARL)
	b.add_theme_color_override("font_hover_color", DEEP if primary else PEARL)
	b.add_theme_color_override("font_focus_color", DEEP if primary else PEARL)
	b.add_theme_color_override("font_pressed_color", DEEP if primary else PEARL)
	b.add_theme_color_override("font_disabled_color", Color(PEARL, 0.3))
	if primary:
		b.add_theme_stylebox_override("normal", _glass(Color(AQUA, 0.92), Color(PEARL, 0.7), 1))
		b.add_theme_stylebox_override("hover", _glass(Color(0.6, 1.0, 0.9), PEARL, 2))
		b.add_theme_stylebox_override("pressed", _glass(Color(0.3, 0.8, 0.7), PEARL, 2))
	else:
		b.add_theme_stylebox_override("normal", _glass(Color(0.01, 0.13, 0.13, 0.7), Color(PEARL, 0.26), 1))
		b.add_theme_stylebox_override("hover", _glass(Color(0.05, 0.3, 0.28, 0.8), Color(AQUA, 0.7), 1))
		b.add_theme_stylebox_override("pressed", _glass(Color(0.03, 0.22, 0.2, 0.85), AQUA, 1))
	b.add_theme_stylebox_override("disabled", _glass(Color(0.01, 0.1, 0.1, 0.4), Color(PEARL, 0.1), 1))
	b.add_theme_stylebox_override("focus", _glass(Color(0, 0, 0, 0), Color(AQUA, 0.9), 2))
	return b
