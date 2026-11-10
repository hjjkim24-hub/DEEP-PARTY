extends "res://scripts/minigames/minigame_base.gd"
## 타이밍 멈추기: 줄어드는 고리가 가운데 과녁 고리와 딱 겹칠 때 클릭!
## 사람마다 자기 고리가 한 줄로 있어요. 5라운드, 점점 빨라짐. 오차가 작을수록 점수 (라운드당 최대 100)

const ROUNDS := 5
## 고리 크기는 사람 수에 맞춰 (4명이면 칸이 좁아서 작게)
var START_R := 330.0
var TARGET_R := 120.0

var _round := 0
var _phase := "wait"          ## wait → shrink → result
var _t := 0.0
var _speed := 1.0             ## 초당 줄어드는 비율
var _cols := {}               ## slot → {x, r, stopped, err, label, cpu_stop}
var _field: Control
var _done := false


func _init() -> void:
	goal = "Highest total score wins!"
	title = "PERFECT STOP"
	how_to = "Click when the shrinking ring lines up with the target ring! 5 rounds, and it gets faster every time."
	controls = "MOUSE"
	duration = 999.0


func _setup_game() -> void:
	_field = Control.new()
	_field.size = ARENA
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_field.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_field.gui_input.connect(_on_input)
	_field.draw.connect(_draw_field)
	arena.add_child(_field)
	var n := players.size()
	START_R = minf(330.0, ARENA.x / n * 0.4)
	TARGET_R = START_R * 0.364
	show_timer = false
	for i in n:
		var p: Dictionary = players[i]
		var x := ARENA.x * (float(i) + 0.5) / n
		var l := outlined("", 40)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size = Vector2(ARENA.x / n, 60)
		l.position = Vector2(x - l.size.x * 0.5, 530 + START_R + 40)
		arena.add_child(l)
		var nm := outlined(p["name"], 34)
		nm.size = Vector2(ARENA.x / n, 50)
		nm.position = Vector2(x - nm.size.x * 0.5, 530 - START_R - 100)
		nm.add_theme_color_override("font_color", p["color"])
		arena.add_child(nm)
		_cols[int(p["slot"])] = {"x": x, "r": START_R, "stopped": false, "err": 0.0, "label": l, "cpu_stop": 0.0}
	var tip := outlined("", 30)
	tip.name = "Tip"
	tip.size = Vector2(ARENA.x, 50)
	tip.position = Vector2(0, 920)
	arena.add_child(tip)


func _start_game() -> void:
	_next_round()


func _next_round() -> void:
	_round += 1
	if _round > ROUNDS:
		_done = true
		return
	_speed = lerpf(0.55, 1.15, float(_round - 1) / (ROUNDS - 1))
	for slot in _cols:
		var c: Dictionary = _cols[slot]
		c["r"] = START_R
		c["stopped"] = false
		c["err"] = 0.0
		(c["label"] as Label).text = ""
		var p := player_by_slot(slot)
		if not is_human(p):
			# CPU: 과녁에 닿을 시간 근처에서 실력만큼 흔들려 멈춤
			var ideal := (START_R - TARGET_R) / (START_R * _speed)
			var spread := lerpf(0.11, 0.035, skill(p) / 2.0) * (0.8 + _round * 0.12)
			c["cpu_stop"] = ideal + rng.randfn(0.0, spread)
	(arena.get_node("Tip") as Label).text = tr("Round %d / %d") % [_round, ROUNDS]
	_phase = "wait"
	_t = 0.0


func _tick(delta: float) -> void:
	_t += delta
	match _phase:
		"wait":
			if _t > 0.8:
				_phase = "shrink"
				_t = 0.0
		"shrink":
			var all_done := true
			for slot in _cols:
				var c: Dictionary = _cols[slot]
				if c["stopped"]:
					continue
				c["r"] = maxf(0.0, START_R * (1.0 - _t * _speed))
				var p := player_by_slot(slot)
				if not is_human(p) and _t >= float(c["cpu_stop"]):
					_stop(slot)
				elif float(c["r"]) <= 0.0:
					_stop(slot)
				if not c["stopped"]:
					all_done = false
			if all_done:
				_phase = "result"
				_t = 0.0
		"result":
			if _t > 1.3:
				_next_round()
	_field.queue_redraw()


func _stop(slot: int) -> void:
	var c: Dictionary = _cols[slot]
	if c["stopped"]:
		return
	c["stopped"] = true
	var err := absf(float(c["r"]) - TARGET_R) * (330.0 / START_R)   # 고리 크기가 달라도 같은 기준
	c["err"] = err
	var pts := maxi(0, int(round(100.0 - err * 3.0)))
	scores[slot] = float(scores[slot]) + pts
	var word := "MISS"
	var col := Color("ff6b6b")
	if err < 4.0:
		word = "PERFECT!"
		col = GOLD
	elif err < 12.0:
		word = "GREAT!"
		col = AQUA
	elif err < 25.0:
		word = "GOOD"
		col = PEARL
	var l: Label = c["label"]
	l.text = "%s  +%d" % [tr(word), pts]
	l.add_theme_color_override("font_color", col)
	if is_human(player_by_slot(slot)):
		sfx("start" if err < 4.0 else ("add" if err < 25.0 else "remove"))
	else:
		sfx("tick", 0.05)


func _on_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and playing and _phase == "shrink":
		for p in players:
			if is_human(p):
				_stop(int(p["slot"]))


func _is_done() -> bool:
	return _done


func _draw_field() -> void:
	for slot in _cols:
		var c: Dictionary = _cols[slot]
		var p := player_by_slot(slot)
		var center := Vector2(float(c["x"]), 530)
		var col: Color = p["color"]
		# 받침 원판
		_field.draw_circle(center, START_R + 26, Color(0.02, 0.12, 0.12, 0.55))
		# 과녁 (두꺼운 금빛 고리)
		_field.draw_arc(center, TARGET_R, 0, TAU, 96, Color(GOLD, 0.35), 26.0, true)
		_field.draw_arc(center, TARGET_R, 0, TAU, 96, GOLD, 4.0, true)
		# 줄어드는 고리
		var r: float = c["r"]
		var stopped: bool = c["stopped"]
		var rc := col if not stopped else (GOLD if float(c["err"]) < 4.0 else col.lerp(Color.WHITE, 0.3))
		if r > 1.0:
			_field.draw_arc(center, r, 0, TAU, 96, rc, 10.0 if not stopped else 14.0, true)
		_field.draw_circle(center, 10, col)
		if is_human(p):
			_field.draw_arc(center, START_R + 26, 0, TAU, 96, Color(col, 0.9), 5.0, true)


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))
