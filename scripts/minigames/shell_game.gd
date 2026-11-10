extends "res://scripts/minigames/minigame_base.gd"
## 기억력 조개 뒤집기: 진주가 들어간 조개를 잘 보고, 섞인 뒤 그 조개를 클릭!
## 5라운드 — 조개 수와 섞는 횟수가 늘고 점점 빨라져요. 맞히면 1점 (동점이면 더 빨리 고른 사람)

const ROUNDS := [
	{"shells": 3, "swaps": 4, "time": 0.42},
	{"shells": 3, "swaps": 6, "time": 0.36},
	{"shells": 4, "swaps": 7, "time": 0.32},
	{"shells": 4, "swaps": 9, "time": 0.28},
	{"shells": 5, "swaps": 11, "time": 0.24},
]
const BASE_Y := 700.0
const SPACING := 320.0
const PICK_TIME := 6.0

var _round := -1
var _phase := "show"
var _t := 0.0
var _shells: Array = []       ## {x, lift, pos}  (pos = 몇 번째 자리)
var _pearl := 0               ## 진주가 든 조개 번호
var _swaps_left := 0
var _swap: Array = []         ## [a, b, from_a, from_b]
var _picks := {}              ## slot → 조개 번호
var _pick_time := {}          ## slot → 고른 시간 합
var _cpu_pick_at := {}
var _field: Control
var _tip: Label
var _done := false


func _init() -> void:
	title = "SHELL SHUFFLE"
	how_to = "Watch which shell hides the pearl. After the shells shuffle, click the one with the pearl! It gets faster every round."
	controls = "MOUSE"
	duration = 999.0


func _setup_game() -> void:
	show_timer = false
	_field = Control.new()
	_field.size = ARENA
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_field.gui_input.connect(_on_input)
	_field.draw.connect(_draw_field)
	arena.add_child(_field)
	_tip = outlined("", 40)
	_tip.size = Vector2(ARENA.x, 60)
	_tip.position = Vector2(0, 220)
	arena.add_child(_tip)
	for p in players:
		_pick_time[int(p["slot"])] = 0.0


func _start_game() -> void:
	_next_round()


func _slot_x(pos: int, n: int) -> float:
	return ARENA.x * 0.5 + (pos - (n - 1) * 0.5) * SPACING


func _next_round() -> void:
	_round += 1
	if _round >= ROUNDS.size():
		_done = true
		return
	var cfg: Dictionary = ROUNDS[_round]
	var n: int = cfg["shells"]
	_shells = []
	for k in n:
		_shells.append({"x": _slot_x(k, n), "lift": 0.0, "pos": k})
	_pearl = rng.randi() % n
	_swaps_left = cfg["swaps"]
	_picks = {}
	_phase = "show"
	_t = 0.0
	_tip.text = tr("Round %d / %d") % [_round + 1, ROUNDS.size()] + "  —  " + tr("Watch the pearl!")


func _tick(delta: float) -> void:
	_t += delta
	var cfg: Dictionary = ROUNDS[mini(_round, ROUNDS.size() - 1)]
	match _phase:
		"show":
			# 들어 올려 진주 보여주기 → 잠깐 → 닫기
			var lift := clampf(_t / 0.3, 0.0, 1.0) if _t < 1.9 else maxf(0.0, 1.0 - (_t - 1.9) / 0.3)
			for s in _shells:
				s["lift"] = lift
			if _t > 2.25:
					Audio.play("tick")
					_phase = "shuffle"
					_t = 0.0
					_start_swap()
		"shuffle":
			var dur: float = cfg["time"]
			var f := clampf(_t / dur, 0.0, 1.0)
			var e := f * f * (3.0 - 2.0 * f)
			var a: Dictionary = _shells[_swap[0]]
			var b: Dictionary = _shells[_swap[1]]
			a["x"] = lerpf(_swap[2], _swap[3], e)
			b["x"] = lerpf(_swap[3], _swap[2], e)
			a["arc"] = sin(f * PI) * 70.0
			b["arc"] = -sin(f * PI) * 40.0
			if f >= 1.0:
				a["arc"] = 0.0
				b["arc"] = 0.0
				var tmp: int = a["pos"]
				a["pos"] = b["pos"]
				b["pos"] = tmp
				_swaps_left -= 1
				if _swaps_left > 0:
					_start_swap()
					_t = 0.0
				else:
					_phase = "pick"
					_t = 0.0
					_tip.text = tr("Which shell has the pearl? Click it!")
					_plan_cpu_picks()
		"pick":
			for slot in _cpu_pick_at:
				if not _picks.has(slot) and _t >= float(_cpu_pick_at[slot]):
					_pick(slot, _cpu_choice(slot))
			var all_in := _picks.size() == players.size()
			if all_in or _t > PICK_TIME:
				_phase = "reveal"
				_t = 0.0
				_reveal()
		"reveal":
			for s in _shells:
				s["lift"] = minf(1.0, _t / 0.3)
			if _t > 2.0:
				_next_round()
	_field.queue_redraw()


func _start_swap() -> void:
	var n := _shells.size()
	var pa := rng.randi() % n
	var pb := (pa + 1 + rng.randi() % (n - 1)) % n
	var ia := -1
	var ib := -1
	for k in n:
		if int(_shells[k]["pos"]) == pa:
			ia = k
		if int(_shells[k]["pos"]) == pb:
			ib = k
	_swap = [ia, ib, float(_shells[ia]["x"]), float(_shells[ib]["x"])]
	Audio.play("tick", 0.05)


func _plan_cpu_picks() -> void:
	_cpu_pick_at = {}
	for p in players:
		if not is_human(p):
			_cpu_pick_at[int(p["slot"])] = rng.randf_range(0.7, 2.2) * lerpf(1.3, 0.7, skill(p) / 2.0)


func _cpu_choice(slot: int) -> int:
	var p := player_by_slot(slot)
	var acc := clampf(0.95 - 0.07 * _round + 0.05 * (skill(p) - 1.0), 0.3, 0.97)
	if rng.randf() < acc:
		return _pearl
	var k := rng.randi() % _shells.size()
	if k == _pearl:
		k = (k + 1) % _shells.size()
	return k


func _pick(slot: int, shell: int) -> void:
	if _picks.has(slot):
		return
	_picks[slot] = shell
	_pick_time[slot] = float(_pick_time[slot]) + _t
	if is_human(player_by_slot(slot)):
		Audio.play("click")


func _reveal() -> void:
	var any := false
	for slot in _picks:
		if int(_picks[slot]) == _pearl:
			scores[slot] = float(scores[slot]) + 1.0
			any = true
	for p in players:
		if not _picks.has(int(p["slot"])):
			_pick_time[int(p["slot"])] = float(_pick_time[int(p["slot"])]) + PICK_TIME
	Audio.play("start" if any else "remove")
	var s: Dictionary = _shells[_pearl]
	float_text(Vector2(float(s["x"]), BASE_Y - 260), tr("HERE!"), GOLD, 46)
	_tip.text = ""


func _on_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if not (mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and playing and _phase == "pick"):
		return
	for p in players:
		if is_human(p) and not _picks.has(int(p["slot"])):
			for k in _shells.size():
				var c := Vector2(float(_shells[k]["x"]), BASE_Y - 70)
				var d := (mb.position - c) / Vector2(130, 110)
				if d.length() <= 1.0:
					_pick(int(p["slot"]), k)
					return


func _is_done() -> bool:
	return _done


func _ranking() -> Array:
	var order := players.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := float(scores[int(a["slot"])])
		var sb := float(scores[int(b["slot"])])
		if sa != sb:
			return sa > sb
		return float(_pick_time[int(a["slot"])]) < float(_pick_time[int(b["slot"])]))
	return order


func _draw_field() -> void:
	# 모래 바닥 띠
	_field.draw_rect(Rect2(0, BASE_Y + 20, ARENA.x, ARENA.y - BASE_Y), Color(0.78, 0.72, 0.56, 0.35))
	var hover := -1
	if _phase == "pick":
		var m := _field.get_local_mouse_position()
		for k in _shells.size():
			var c := Vector2(float(_shells[k]["x"]), BASE_Y - 70)
			if ((m - c) / Vector2(130, 110)).length() <= 1.0:
				hover = k
	for k in _shells.size():
		var s: Dictionary = _shells[k]
		var x: float = s["x"]
		var lift: float = s["lift"]
		var arc: float = s.get("arc", 0.0)
		# 진주 (조개를 들었을 때 보임)
		if k == _pearl and lift > 0.05:
			var pp := Vector2(x, BASE_Y - 28)
			_field.draw_circle(pp + Vector2(3, 5), 30, Color(0, 0, 0, 0.2))
			_field.draw_circle(pp, 30, Color("9d93bd"))
			_field.draw_circle(pp + Vector2(-2, -2), 27, Color("f4f1ff"))
			_field.draw_circle(pp + Vector2(-10, -11), 8, Color(1, 1, 1, 0.9))
		_draw_shell(Vector2(x, BASE_Y - lift * 150.0 - arc), k == hover)
		# 누가 골랐는지 (공개 때)
		if _phase == "reveal":
			var who := []
			for slot in _picks:
				if int(_picks[slot]) == k:
					who.append(slot)
			for i in who.size():
				var col: Color = player_by_slot(int(who[i]))["color"]
				var dp := Vector2(x + (i - (who.size() - 1) * 0.5) * 44, BASE_Y + 70)
				_field.draw_circle(dp, 17, col)
				_field.draw_arc(dp, 17, 0, TAU, 24, Color.WHITE if k == _pearl else Color(1, 0.4, 0.4), 3.0, true)
	# 내가 고른 조개 표시 (고르는 중)
	if _phase == "pick":
		for p in players:
			if is_human(p) and _picks.has(int(p["slot"])):
				var s: Dictionary = _shells[int(_picks[int(p["slot"])])]
				_field.draw_arc(Vector2(float(s["x"]), BASE_Y - 70), 150, 0, TAU, 64, Color(p["color"], 0.9), 6.0, true)


func _draw_shell(base: Vector2, hover: bool) -> void:
	var w := 125.0
	var h := 150.0
	var col := Color("f2b7a3") if not hover else Color("ffd0bf")
	var dark := Color("c97e6a")
	# 그림자
	_field.draw_colored_polygon(_ellipse(base + Vector2(6, 10), w, 26), Color(0, 0, 0, 0.22))
	# 부채꼴 몸통
	var pts := PackedVector2Array()
	var n := 14
	for k in n + 1:
		var a := PI + PI * k / n
		var bump := 1.0 + 0.05 * (1 if k % 2 == 0 else -1)
		pts.append(base + Vector2(cos(a) * w * bump, sin(a) * h * bump))
	_field.draw_colored_polygon(pts, col)
	# 골 (방사형 줄)
	for k in range(1, n):
		var a := PI + PI * k / n
		_field.draw_line(base + Vector2(0, -12), base + Vector2(cos(a) * w * 0.96, sin(a) * h * 0.96), dark, 4.0, true)
	# 밑동 (경첩)
	_field.draw_colored_polygon(PackedVector2Array([base + Vector2(-40, 0), base + Vector2(40, 0), base + Vector2(28, 26), base + Vector2(-28, 26)]), dark)
	_field.draw_arc(base, w * 0.98, PI, TAU, 40, Color(1, 1, 1, 0.25), 4.0, true)


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))
