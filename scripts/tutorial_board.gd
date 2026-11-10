extends Control
## 튜토리얼 보드 (연습판). 메인화면 튜토리얼의 마지막에 보드 고르기에서 PLAY 를 누르면 여기로 와요.
## 칸 16개짜리 작은 판 위에서 주사위를 굴려 움직이는 기본만 알려줘요.
## 판 그림과 칸 위치는 tools/render_tutorial_board.py 가 만들어요.

const BackgroundScene := preload("res://scenes/underwater_background.tscn")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
const PieceDraw := preload("res://scripts/background/piece_draw.gd")
const UIFont := preload("res://fonts/Poppins-Bold.ttf")
const BOARD_TEX := preload("res://textures/boards/tutorial_board_scene.png")
const MARKS_PATH := "res://textures/boards/tutorial_board_marks.json"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const BASE := Vector2(1920, 1080)

const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const TEXT_DIM := Color(0.75, 0.95, 0.9, 0.78)
const HOP_TIME := 0.3

var _tiles: Array = []          # [{x, y, w}] 1920x1080 기준
var _pawns: Array = []          # [{slot, name, color, look, tile, pos, hop}]
var _turn := -1                 # 지금 차례인 _pawns 번호 (-1 = 아무도)
var _player_moved := false
var _cpus_done := false
var _busy := false
var _cover_scale := 1.0
var _cover_offset := Vector2.ZERO

var _bg
var _board: TextureRect
var _layer: Node2D
var _dice: Dice
var _dice_label: Label
var _dice_panel: PanelContainer
var _turn_bar: HBoxContainer
var _chips: Array[PanelContainer] = []
var _markers: Array[Control] = []
var _overlay
var _fade: ColorRect


# ── 주사위 ───────────────────────────────────────────────────
class Dice extends Control:
	signal rolled(value: int)
	var value := 1
	var rolling := false
	var clickable := false
	var _t := 0.0
	var _flip := 0.0
	var _hover := false

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true)
		mouse_exited.connect(func() -> void: _hover = false)

	func roll() -> void:
		if rolling:
			return
		rolling = true
		_t = 0.0
		_flip = 0.0
		Audio.play("bubbles")

	func _process(delta: float) -> void:
		if rolling:
			_t += delta
			_flip += delta
			if _flip > 0.07:
				_flip = 0.0
				var v := randi_range(1, 6)
				while v == value:
					v = randi_range(1, 6)
				value = v
				Audio.play("tick", 0)
			if _t > 0.9:
				rolling = false
				value = randi_range(1, 6)
				Audio.play("toggle_on")
				rolled.emit(value)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and clickable and not rolling:
			accept_event()
			roll()

	func _draw() -> void:
		var s := minf(size.x, size.y) * 0.78
		var c := size * 0.5
		var wob := sin(_t * 40.0) * 0.25 if rolling else 0.0
		var lift := (sin(Time.get_ticks_msec() / 260.0) * 4.0 if clickable and not rolling else 0.0)
		var k := 1.06 if (_hover and clickable) else 1.0
		draw_set_transform(c + Vector2(0, -lift), wob, Vector2(k, k))
		var r := Rect2(-s * 0.5, -s * 0.5, s, s)
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0.08, 0.07, 0.35)
		shadow.set_corner_radius_all(int(s * 0.2))
		draw_style_box(shadow, Rect2(r.position + Vector2(0, s * 0.07), r.size))
		var face := StyleBoxFlat.new()
		face.bg_color = PEARL
		face.set_corner_radius_all(int(s * 0.2))
		face.border_color = AQUA if clickable else Color(AQUA, 0.0)
		face.set_border_width_all(int(s * 0.035))
		face.anti_aliasing = true
		draw_style_box(face, r)
		var pr := s * 0.085
		var o := s * 0.26
		var spots := {
			1: [Vector2.ZERO],
			2: [Vector2(-o, -o), Vector2(o, o)],
			3: [Vector2(-o, -o), Vector2.ZERO, Vector2(o, o)],
			4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
			5: [Vector2(-o, -o), Vector2(o, -o), Vector2.ZERO, Vector2(-o, o), Vector2(o, o)],
			6: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, 0), Vector2(o, 0), Vector2(-o, o), Vector2(o, o)],
		}
		for p in spots[value]:
			draw_circle(p, pr, DEEP)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── 말 그리기 층 (1920x1080 좌표) ─────────────────────────────
class PawnLayer extends Node2D:
	var board  # 바깥 스크립트

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var order: Array = board._pawns.duplicate()
		order.sort_custom(func(a, b) -> bool: return a["pos"].y < b["pos"].y)
		for p in order:
			var pos: Vector2 = p["pos"]
			var h: float = p["h"]
			var arc: float = p.get("arc", 0.0)
			# 그림자 (땅에 붙어 있음)
			var sh := PieceDraw.ellipse(pos + Vector2(h * 0.06, h * 0.02), h * 0.3 * (1.0 - arc * 0.004), h * 0.1, 24)
			PieceDraw.poly(self, sh, Color(0.0, 0.08, 0.07, 0.35))
			var glow: bool = board._turn >= 0 and board._pawns[board._turn] == p
			if glow:
				draw_arc(pos, h * 0.34, 0, TAU, 40, Color(AQUA, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)), 3.0, true)
			PieceDraw.draw_pawn_real(self, pos + Vector2(0, -arc), h, p["color"], 1.0, p["look"])


func _ready() -> void:
	_build_theme()
	_load_marks()
	_setup_players()
	_build_scene()
	_build_ui()
	resized.connect(_on_resized)
	_on_resized()
	Audio.play_music()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.6)
	await t.finished
	_fade.hide()
	_start_tutorial()


func _build_theme() -> void:
	var th := Theme.new()
	th.default_font = UIFont
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	theme = th


func _load_marks() -> void:
	var f := FileAccess.open(MARKS_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	_tiles = data["tiles"]


func _setup_players() -> void:
	var cpu_no := 0
	for slot in 4:
		var p: Dictionary = GameState.players[slot]
		if p.is_empty():
			continue
		var pname := "You"
		if p.get("kind", "") == "cpu":
			cpu_no += 1
			pname = tr("CPU %d") % cpu_no
		_pawns.append({"slot": slot, "name": pname, "color": GameState.player_color(slot),
			"look": GameState.look(slot), "tile": 0, "pos": Vector2.ZERO, "h": 120.0, "arc": 0.0})
	if _pawns.size() < 2:   # 혼자면 연습 상대 하나
		_pawns.append({"slot": 1, "name": tr("CPU %d") % 1, "color": GameState.PALETTE[2],
			"look": {}, "tile": 0, "pos": Vector2.ZERO, "h": 120.0, "arc": 0.0})
	_place_all()


## 같은 칸에 여러 명이면 살짝 비켜 세우기
func _spot(tile: int, who: int) -> Vector2:
	var t: Dictionary = _tiles[tile]
	var base := Vector2(t["x"], t["y"])
	var w: float = t["w"]
	var here: Array = []
	for i in _pawns.size():
		if int(_pawns[i]["tile"]) == tile:
			here.append(i)
	if here.size() <= 1:
		return base + Vector2(0, w * 0.12)
	var k := here.find(who)
	var offs := [Vector2(-0.22, -0.02), Vector2(0.22, -0.02), Vector2(-0.22, 0.26), Vector2(0.22, 0.26)]
	return base + offs[k % 4] * w


func _place_all() -> void:
	for i in _pawns.size():
		var p: Dictionary = _pawns[i]
		if p.get("hopping", false):
			continue
		p["pos"] = _spot(p["tile"], i)
		p["h"] = float(_tiles[p["tile"]]["w"]) * 0.95


func _build_scene() -> void:
	_bg = BackgroundScene.instantiate()
	_bg.show_seabed = false
	add_child(_bg)
	_board = TextureRect.new()
	_board.texture = BOARD_TEX
	_board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer = PawnLayer.new()
	_layer.board = self
	add_child(_layer)


func _build_ui() -> void:
	var ui := Control.new()
	ui.name = "UI"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 칸 위치 표시용 (튜토리얼이 가리킬 수 있게, 보이지 않음)
	for i in _tiles.size():
		var m := Control.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(m)
		_markers.append(m)

	# 위: 제목 + 차례 표시
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.position.y = 30
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_turn_bar = HBoxContainer.new()
	_turn_bar.add_theme_constant_override("separation", 10)
	_turn_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_turn_bar)
	for p in _pawns:
		var chip := _make_chip(p)
		_turn_bar.add_child(chip)
		_chips.append(chip)

	# 왼쪽 위: 나가기
	var exit := Button.new()
	exit.text = "EXIT TUTORIAL"
	exit.focus_mode = Control.FOCUS_NONE
	exit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	exit.add_theme_font_size_override("font_size", 17)
	exit.add_theme_stylebox_override("normal", _glass(Color(0.02, 0.17, 0.16, 0.6), Color(AQUA, 0.25), 1))
	exit.add_theme_stylebox_override("hover", _glass(Color(0.08, 0.4, 0.36, 0.65), Color(AQUA, 0.5), 1))
	exit.add_theme_stylebox_override("pressed", _glass(Color(0.03, 0.26, 0.24, 0.7), AQUA, 1))
	exit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	exit.set_meta("sfx", "back")
	exit.pressed.connect(_exit_to_menu)
	ui.add_child(exit)
	exit.position = Vector2(30, 30)

	# 오른쪽: 주사위
	_dice_panel = PanelContainer.new()
	_dice_panel.add_theme_stylebox_override("panel", _glass(Color(0.02, 0.15, 0.14, 0.78), Color(AQUA, 0.35), 2, 26))
	ui.add_child(_dice_panel)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	_dice_panel.add_child(dv)
	var cap := Label.new()
	cap.text = "DICE"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 16)
	cap.add_theme_color_override("font_color", AQUA)
	dv.add_child(cap)
	_dice = Dice.new()
	_dice.custom_minimum_size = Vector2(170, 170)
	_dice.rolled.connect(_on_rolled)
	dv.add_child(_dice)
	_dice_label = Label.new()
	_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_label.add_theme_font_size_override("font_size", 17)
	_dice_label.add_theme_color_override("font_color", TEXT_DIM)
	_dice_label.custom_minimum_size = Vector2(200, 0)
	_dice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_dice_label)
	_set_dice_state(false, "Wait for your turn")

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _glass(bg: Color, border: Color, bw: int, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(16)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.anti_aliasing = true
	return s


func _make_chip(p: Dictionary) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _glass(Color(0.02, 0.15, 0.14, 0.6), Color(AQUA, 0.15), 1, 30))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	chip.add_child(h)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.color = p["color"]
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var l := Label.new()
	l.text = p["name"]
	l.add_theme_font_size_override("font_size", 19)
	h.add_child(l)
	return chip


func _set_turn(i: int) -> void:
	_turn = i
	for k in _chips.size():
		var on := k == i
		_chips[k].add_theme_stylebox_override("panel", _glass(
			Color(0.06, 0.32, 0.29, 0.85) if on else Color(0.02, 0.15, 0.14, 0.6),
			AQUA if on else Color(AQUA, 0.15), 2 if on else 1, 30))


func _set_dice_state(clickable: bool, msg: String) -> void:
	_dice.clickable = clickable
	_dice_label.text = msg


func _on_resized() -> void:
	_cover_scale = maxf(size.x / BASE.x, size.y / BASE.y)
	_cover_offset = (size - BASE * _cover_scale) * 0.5
	_layer.scale = Vector2.ONE * _cover_scale
	_layer.position = _cover_offset
	_dice_panel.position = Vector2(size.x - _dice_panel.size.x - 40, size.y * 0.5 - _dice_panel.size.y * 0.5)


func _process(_delta: float) -> void:
	_dice_panel.position = Vector2(size.x - _dice_panel.size.x - 40, size.y * 0.5 - _dice_panel.size.y * 0.5 - 40)
	for i in _markers.size():
		var t: Dictionary = _tiles[i]
		var w: float = float(t["w"]) * 1.05 * _cover_scale
		var c := _cover_offset + Vector2(t["x"], t["y"]) * _cover_scale
		_markers[i].position = c - Vector2(w, w * 0.75) * 0.5
		_markers[i].size = Vector2(w, w * 0.75)


func _screen(p: Vector2) -> Vector2:
	return _cover_offset + p * _cover_scale


# ── 차례 진행 ────────────────────────────────────────────────
func _player_index() -> int:
	for i in _pawns.size():
		if int(_pawns[i]["slot"]) == 0:
			return i
	return 0


func _begin_player_turn() -> void:
	_set_turn(_player_index())
	_set_dice_state(true, "Click the dice to roll!")


func _on_rolled(value: int) -> void:
	if _turn < 0:
		return
	_set_dice_state(false, tr("Rolled a %d!") % value)
	await _move(_turn, value)
	if int(_pawns[_turn]["slot"]) == 0:
		_player_moved = true
		_set_dice_state(false, "Nice roll!")


func _move(i: int, steps: int) -> void:
	_busy = true
	var p: Dictionary = _pawns[i]
	p["hopping"] = true
	for s in steps:
		var from: Vector2 = p["pos"]
		p["tile"] = (int(p["tile"]) + 1) % _tiles.size()
		var to := _spot(p["tile"], i)
		var h0: float = p["h"]
		var h1: float = float(_tiles[p["tile"]]["w"]) * 0.95
		var t := 0.0
		while t < HOP_TIME:
			t += get_process_delta_time()
			var k := clampf(t / HOP_TIME, 0.0, 1.0)
			p["pos"] = from.lerp(to, k)
			p["h"] = lerpf(h0, h1, k)
			p["arc"] = sin(k * PI) * h1 * 0.35
			await get_tree().process_frame
		p["arc"] = 0.0
		Audio.play("tick", 0)
	p["hopping"] = false
	_place_all()
	Audio.play("add")
	_bg.burst_bubbles(_screen(p["pos"]), 10)
	_busy = false


func _run_cpu_turns() -> void:
	await get_tree().create_timer(0.6).timeout
	for i in _pawns.size():
		if int(_pawns[i]["slot"]) == 0:
			continue
		_set_turn(i)
		_set_dice_state(false, tr("%s is rolling...") % _pawns[i]["name"])
		await get_tree().create_timer(0.6).timeout
		_dice.roll()
		await _dice.rolled
		while _busy or _dice.rolling:
			await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		# _on_rolled 가 움직임을 처리하므로 끝날 때까지 기다림
		while _busy:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
	_set_turn(-1)
	_set_dice_state(false, "Round over!")
	_cpus_done = true


# ── 튜토리얼 안내 ────────────────────────────────────────────
func _start_tutorial() -> void:
	_overlay = TutorialOverlay.new()
	_overlay.name = "Tutorial"
	add_child(_overlay)
	_overlay.finished.connect(_on_tutorial_finished)
	_overlay.skipped.connect(_exit_to_menu)
	_overlay.start(_steps())


func _steps() -> Array:
	return [
		{
			"text": "Welcome to the Tutorial Board! This is where the party happens. Everyone starts on the START space.",
			"target": func() -> Control: return _markers[0],
			"pad": 20.0,
		},
		{
			"text": "Players take turns one by one. The highlighted name shows whose turn it is.",
			"target": func() -> Control: return _turn_bar,
			"enter": func() -> void: _set_turn(_player_index()),
		},
		{
			"text": "On your turn, roll the dice and move forward that many spaces. Click the dice!",
			"target": func() -> Control: return _dice_panel,
			"enter": func() -> void: _begin_player_turn(),
			"until": func() -> bool: return _player_moved and not _busy,
			"auto": func() -> void: _dice.roll(),
		},
		{
			"text": "Nice roll! Your pawn hopped forward one space for each dot on the dice.",
			"target": func() -> Control: return _markers[int(_pawns[_player_index()]["tile"])],
			"pad": 30.0,
		},
		{
			"text": "Now the other players take their turns. Watch them go!",
			"enter": func() -> void: _run_cpu_turns(),
			"until": func() -> bool: return _cpus_done,
		},
		{
			"text": "When everyone has moved, the round is over. In a real game a minigame starts after every round, and winning minigames helps you get ahead!",
		},
		{
			"text": "That's the basics of DEEP PARTY! More rules will be added to this tutorial as the game grows. Have fun!",
		},
	]


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
	add_child(banner)
	Audio.play("start")
	_bg.burst_bubbles(size * 0.5, 30)
	var t := create_tween()
	t.tween_property(banner, "modulate:a", 1.0, 0.3)
	t.tween_interval(1.6)
	await t.finished
	_exit_to_menu()


func _exit_to_menu() -> void:
	if _fade.visible and _fade.color.a > 0.5:
		return
	GameState.tutorial_active = false
	_fade.show()
	move_child(_fade, get_child_count() - 1)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.4)
	await t.finished
	get_tree().change_scene_to_file(MAIN_MENU)
