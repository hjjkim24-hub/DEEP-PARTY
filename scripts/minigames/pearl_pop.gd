extends "res://scripts/minigames/minigame_base.gd"
## 진주 클릭 레이스: 아래에서 떠오르는 진주를 클릭해서 터뜨려요.
##   흰 진주 +1, 금 진주 +3, 성게 -2. 같은 화면의 진주를 CPU 커서도 노려요 (먼저 누르는 사람이 임자).

const KINDS := {
	"pearl": {"points": 1, "r": 44.0},
	"gold": {"points": 3, "r": 40.0},
	"urchin": {"points": -2, "r": 46.0},
}

var _items: Array = []        ## {pos, vel, kind, r, phase, alive}
var _spawn_acc := 0.0
var _cursors := {}            ## slot → {pos, target, wait}
var _field: Control
var _t := 0.0


func _init() -> void:
	goal = "Most points wins!"
	title = "PEARL POP"
	how_to = "Click the pearls as they float up! White pearls are 1 point, gold pearls are 3. Watch out for sea urchins: -2!"
	controls = "MOUSE"
	duration = 20.0


func _setup_game() -> void:
	_field = Control.new()
	_field.size = ARENA
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_field.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_field.gui_input.connect(_on_input)
	_field.draw.connect(_draw_field)
	arena.add_child(_field)
	for p in players:
		if not is_human(p):
			_cursors[int(p["slot"])] = {"pos": Vector2(rng.randf_range(400, 1500), 900), "target": null, "wait": rng.randf_range(0.2, 0.6)}


func _spawn() -> void:
	var roll := rng.randf()
	var kind := "pearl"
	if roll < 0.13:
		kind = "gold"
	elif roll < 0.32:
		kind = "urchin"
	var r: float = KINDS[kind]["r"] * rng.randf_range(0.9, 1.1)
	_items.append({
		"pos": Vector2(rng.randf_range(140, ARENA.x - 140), ARENA.y + r),
		"vel": Vector2(0, -rng.randf_range(170, 290) * (1.0 + 0.6 * (1.0 - time_left / duration))),
		"kind": kind, "r": r, "phase": rng.randf() * TAU, "alive": true,
	})


func _tick(delta: float) -> void:
	_t += delta
	_spawn_acc += delta * lerpf(2.6, 4.6, 1.0 - time_left / duration)
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_spawn()
	for it in _items:
		it["pos"] += it["vel"] * delta + Vector2(sin(_t * 2.2 + float(it["phase"])) * 40.0 * delta, 0)
	_items = _items.filter(func(it: Dictionary) -> bool: return it["alive"] and (it["pos"] as Vector2).y > -80.0)
	# CPU 커서
	for slot in _cursors:
		var c: Dictionary = _cursors[slot]
		var p := player_by_slot(slot)
		var sk := skill(p)
		c["wait"] = float(c["wait"]) - delta
		var tgt = c["target"]
		if tgt == null or not tgt["alive"]:
			c["target"] = _pick_target(c["pos"], sk)
			tgt = c["target"]
		if tgt == null or float(c["wait"]) > 0.0:
			continue
		var speed := lerpf(700.0, 1300.0, sk / 2.0)
		var to: Vector2 = tgt["pos"]
		var d := to - (c["pos"] as Vector2)
		if d.length() < 26.0:
			_pop(tgt, slot)
			c["target"] = null
			c["wait"] = rng.randf_range(0.18, 0.4) * lerpf(1.5, 0.7, sk / 2.0)
		else:
			c["pos"] = (c["pos"] as Vector2) + d.normalized() * minf(d.length(), speed * delta)
	_field.queue_redraw()


func _pick_target(from: Vector2, sk: float) -> Variant:
	var best = null
	var bs := -INF
	for it in _items:
		if not it["alive"] or (it["pos"] as Vector2).y > ARENA.y - 30:
			continue
		# 쉬운 CPU 는 가끔 성게도 노림
		if it["kind"] == "urchin" and rng.randf() > 0.12 * (2.0 - sk):
			continue
		var score := -from.distance_to(it["pos"]) + (500.0 if it["kind"] == "gold" else 0.0) + rng.randf_range(0, 250)
		if score > bs:
			bs = score
			best = it
	return best


func _pop(it: Dictionary, slot: int) -> void:
	if not it["alive"]:
		return
	it["alive"] = false
	var pts: int = KINDS[it["kind"]]["points"]
	scores[slot] = float(scores[slot]) + pts
	var col := GOLD if pts > 1 else (Color("ff6b6b") if pts < 0 else PEARL)
	float_text(it["pos"], ("+%d" % pts) if pts > 0 else str(pts), col, 44)
	var human := is_human(player_by_slot(slot))
	if human or rng.randf() < 0.35:
		sfx("remove" if pts < 0 else ("add" if pts > 1 else "click"), 0.03)
	_burst(it["pos"], col)


var _bursts: Array = []


func _burst(at: Vector2, col: Color) -> void:
	_bursts.append({"pos": at, "t": 0.0, "col": col})


func _on_input(event: InputEvent) -> void:
	if not playing:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var me := {}
		for p in players:
			if is_human(p):
				me = p
		if me.is_empty():
			return
		var best = null
		var bd := INF
		for it in _items:
			if not it["alive"]:
				continue
			var d := mb.position.distance_to(it["pos"])
			if d < float(it["r"]) * 1.15 and d < bd:
				bd = d
				best = it
		if best != null:
			_pop(best, int(me["slot"]))


func _draw_field() -> void:
	for it in _items:
		if not it["alive"]:
			continue
		var p: Vector2 = it["pos"]
		var r: float = it["r"]
		match String(it["kind"]):
			"urchin":
				_draw_urchin(p, r)
			"gold":
				_draw_pearl(p, r, Color("ffc93c"), Color("b8760e"))
			_:
				_draw_pearl(p, r, Color("f4f1ff"), Color("9d93bd"))
	var keep := []
	for b in _bursts:
		b["t"] = float(b["t"]) + get_process_delta_time()
		var f: float = b["t"] / 0.35
		if f < 1.0:
			_field.draw_arc(b["pos"], 30.0 + f * 50.0, 0, TAU, 40, Color(b["col"], 1.0 - f), 6.0 * (1.0 - f) + 1.0, true)
			keep.append(b)
	_bursts = keep
	for slot in _cursors:
		var c: Dictionary = _cursors[slot]
		var col: Color = player_by_slot(slot)["color"]
		var pos: Vector2 = c["pos"]
		_field.draw_circle(pos + Vector2(3, 4), 16, Color(0, 0, 0, 0.25))
		_field.draw_circle(pos, 16, Color(col, 0.9))
		_field.draw_arc(pos, 16, 0, TAU, 24, Color.WHITE, 3.0, true)
		_field.draw_circle(pos, 5, Color.WHITE)


func _draw_pearl(p: Vector2, r: float, base: Color, rim: Color) -> void:
	_field.draw_circle(p + Vector2(4, 6), r, Color(0, 0, 0, 0.18))
	_field.draw_circle(p, r, rim)
	_field.draw_circle(p + Vector2(-r * 0.06, -r * 0.06), r * 0.9, base)
	_field.draw_circle(p + Vector2(r * 0.12, r * 0.15), r * 0.6, base.lerp(rim, 0.25))
	_field.draw_circle(p + Vector2(-r * 0.32, -r * 0.34), r * 0.24, Color(1, 1, 1, 0.85))
	_field.draw_circle(p + Vector2(r * 0.35, r * 0.42), r * 0.1, Color(1, 1, 1, 0.4))


func _draw_urchin(p: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var n := 22
	for k in n * 2:
		var a := TAU * k / (n * 2) + _t * 0.6
		var rr := r * (1.15 if k % 2 == 0 else 0.62)
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	_field.draw_colored_polygon(pts, Color("3b1f4f"))
	_field.draw_circle(p, r * 0.62, Color("5a2d78"))
	_field.draw_circle(p + Vector2(-r * 0.2, -r * 0.22), r * 0.2, Color(1, 0.8, 1, 0.35))


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))
