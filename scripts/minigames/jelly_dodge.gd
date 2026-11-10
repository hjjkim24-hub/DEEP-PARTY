extends "res://scripts/minigames/minigame_base.gd"
## 해파리 피하기 (키보드): WASD / 방향키로 내 물고기를 움직여 내려오는 해파리를 피해요.
## 모두 같은 바다에서 함께 헤엄쳐요. 하트 3개 — 다 잃으면 탈락. 30초 버티기.
## 순위: 끝까지 살아남은 사람(남은 하트 많은 순) → 늦게 탈락한 순

const SPEED := 560.0
const FISH_R := 30.0
const TOP := 150.0
const BOTTOM := 1030.0

var _fish := {}               ## slot → {pos, vel, hearts, out_at, inv, face, ai_t, ai_dir}
var _jellies: Array = []      ## {pos, vel, r, phase, side}
var _spawn_acc := 0.0
var _t := 0.0
var _field: Control


func _init() -> void:
	title = "JELLY DODGE"
	how_to = "Swim with WASD or the arrow keys and dodge the jellyfish! You have 3 hearts. Survive for 30 seconds!"
	controls = "KEYBOARD"
	duration = 30.0


func _setup_game() -> void:
	_field = Control.new()
	_field.size = ARENA
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.draw.connect(_draw_field)
	arena.add_child(_field)
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		_fish[int(p["slot"])] = {
			"pos": Vector2(ARENA.x * (float(i) + 0.5) / n, BOTTOM - 120), "vel": Vector2.ZERO,
			"hearts": 3, "out_at": -1.0, "inv": 0.0, "face": 1.0, "ai_t": 0.0, "ai_dir": Vector2.ZERO,
		}


func _spawn() -> void:
	var prog := 1.0 - time_left / duration
	var side := prog > 0.35 and rng.randf() < 0.25
	var r := rng.randf_range(38, 62) * (1.4 if rng.randf() < 0.12 else 1.0)
	if side:
		var from_left := rng.randf() < 0.5
		_jellies.append({"pos": Vector2(-r if from_left else ARENA.x + r, rng.randf_range(TOP + 120, BOTTOM - 80)),
			"vel": Vector2((1 if from_left else -1) * rng.randf_range(220, 320), 0), "r": r, "phase": rng.randf() * TAU, "side": true})
	else:
		_jellies.append({"pos": Vector2(rng.randf_range(60, ARENA.x - 60), TOP - r),
			"vel": Vector2(0, rng.randf_range(170, 260) * (1.0 + prog * 0.9)), "r": r, "phase": rng.randf() * TAU, "side": false})


func _tick(delta: float) -> void:
	_t += delta
	var prog := 1.0 - time_left / duration
	_spawn_acc += delta * lerpf(1.6, 4.2, prog)
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		_spawn()
	for j in _jellies:
		var wob := Vector2(sin(_t * 2.0 + float(j["phase"])) * 60.0, 0) if not j["side"] else Vector2(0, sin(_t * 2.4 + float(j["phase"])) * 50.0)
		j["pos"] = (j["pos"] as Vector2) + ((j["vel"] as Vector2) + wob) * delta
	_jellies = _jellies.filter(func(j: Dictionary) -> bool:
		var p: Vector2 = j["pos"]
		return p.y < ARENA.y + 120 and p.x > -200 and p.x < ARENA.x + 200)
	for slot in _fish:
		var f: Dictionary = _fish[slot]
		if int(f["hearts"]) <= 0:
			f["pos"] = (f["pos"] as Vector2) + Vector2(0, -120 * delta)   # 탈락: 위로 둥둥
			continue
		var p := player_by_slot(slot)
		var want := _input_dir() if is_human(p) else _ai_dir(slot, f, delta)
		var vel: Vector2 = f["vel"]
		vel = vel.lerp(want * SPEED, 1.0 - exp(-delta * 10.0))
		f["vel"] = vel
		var pos: Vector2 = (f["pos"] as Vector2) + vel * delta
		pos.x = clampf(pos.x, 40, ARENA.x - 40)
		pos.y = clampf(pos.y, TOP + 30, BOTTOM - 30)
		f["pos"] = pos
		if absf(vel.x) > 20:
			f["face"] = signf(vel.x)
		f["inv"] = maxf(0.0, float(f["inv"]) - delta)
		if float(f["inv"]) <= 0.0:
			for j in _jellies:
				if pos.distance_to(j["pos"]) < FISH_R + float(j["r"]) * 0.72:
					_hit(slot)
					break
		scores[slot] = float(f["hearts"])
	_field.queue_redraw()


func _hit(slot: int) -> void:
	var f: Dictionary = _fish[slot]
	f["hearts"] = int(f["hearts"]) - 1
	f["inv"] = 1.4
	var human := is_human(player_by_slot(slot))
	if human or int(f["hearts"]) <= 0:
		Audio.play("remove", 0.05)
	if int(f["hearts"]) <= 0:
		f["out_at"] = _t
		float_text(f["pos"], tr("OUT!"), Color("ff6b6b"), 46)
	else:
		float_text(f["pos"], "-1", Color("ff6b6b"), 40)


func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		d.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		d.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		d.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		d.y += 1
	return d.normalized()


## CPU: 가까운 해파리에서 멀어지는 쪽으로 (실력이 낮으면 늦게·덜 정확하게)
func _ai_dir(slot: int, f: Dictionary, delta: float) -> Vector2:
	f["ai_t"] = float(f["ai_t"]) - delta
	if float(f["ai_t"]) > 0.0:
		return f["ai_dir"]
	var sk := skill(player_by_slot(slot))
	f["ai_t"] = lerpf(0.28, 0.08, sk / 2.0) + rng.randf_range(0, 0.08)
	var pos: Vector2 = f["pos"]
	var push := Vector2.ZERO
	var look := lerpf(170.0, 300.0, sk / 2.0)
	for j in _jellies:
		var jp: Vector2 = j["pos"]
		# 해파리가 움직일 곳을 조금 앞서 봄
		jp += (j["vel"] as Vector2) * lerpf(0.1, 0.35, sk / 2.0)
		var d := pos - jp
		var dist := d.length()
		if dist < look + float(j["r"]):
			push += d.normalized() * pow((look + float(j["r"]) - dist) / look, 2.0) * 2.0
	# 가운데 아래쪽에 머무르려는 힘
	push += (Vector2(ARENA.x * 0.5, BOTTOM - 200) - pos) / 1600.0
	push += Vector2(rng.randfn(0, 1), rng.randfn(0, 1)) * lerpf(0.35, 0.08, sk / 2.0)
	f["ai_dir"] = push.normalized() if push.length() > 0.05 else Vector2.ZERO
	return f["ai_dir"]


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	for slot in _fish:
		if int(_fish[slot]["hearts"]) > 0:
			return false
	return true


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa: Dictionary = _fish[int(a["slot"])]
		var fb: Dictionary = _fish[int(b["slot"])]
		if int(fa["hearts"]) != int(fb["hearts"]):
			return int(fa["hearts"]) > int(fb["hearts"])
		return float(fa["out_at"]) > float(fb["out_at"]))
	return order


func _draw_field() -> void:
	# 놀이 구역 테두리
	_field.draw_rect(Rect2(20, TOP, ARENA.x - 40, BOTTOM - TOP), Color(0.0, 0.1, 0.1, 0.18))
	_field.draw_rect(Rect2(20, TOP, ARENA.x - 40, BOTTOM - TOP), Color(AQUA, 0.35), false, 4.0)
	for j in _jellies:
		_draw_jelly(j["pos"], j["r"], float(j["phase"]))
	for slot in _fish:
		var f: Dictionary = _fish[slot]
		var p := player_by_slot(slot)
		var out := int(f["hearts"]) <= 0
		var blink := float(f["inv"]) > 0.0 and int(_t * 12) % 2 == 0
		if blink:
			continue
		_draw_fish(f["pos"], p["color"] if not out else Color(0.5, 0.55, 0.55), float(f["face"]), out)
		# 하트
		var hp: Vector2 = (f["pos"] as Vector2) + Vector2(-26, -58)
		for k in 3:
			var c := Color("ff5a6e") if k < int(f["hearts"]) else Color(1, 1, 1, 0.2)
			_draw_heart(hp + Vector2(k * 26, 0), 9, c)
		if is_human(p) and not out:
			_field.draw_arc(f["pos"], FISH_R + 14, 0, TAU, 32, Color(p["color"], 0.8), 3.0, true)


func _draw_fish(pos: Vector2, col: Color, face: float, out: bool) -> void:
	var body := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20
		body.append(pos + Vector2(cos(a) * FISH_R * 1.25, sin(a) * FISH_R * 0.8))
	var tail := PackedVector2Array([pos + Vector2(-face * FISH_R * 1.0, 0), pos + Vector2(-face * FISH_R * 1.9, -FISH_R * 0.75), pos + Vector2(-face * FISH_R * 1.9, FISH_R * 0.75)])
	_field.draw_colored_polygon(tail, col.darkened(0.15))
	_field.draw_colored_polygon(body, col)
	_field.draw_circle(pos + Vector2(face * FISH_R * 0.15, FISH_R * 0.25), FISH_R * 0.5, col.lightened(0.25))
	var eye := pos + Vector2(face * FISH_R * 0.6, -FISH_R * 0.18)
	_field.draw_circle(eye, 8, Color.WHITE)
	if out:
		_field.draw_line(eye + Vector2(-5, -5), eye + Vector2(5, 5), DEEP, 3)
		_field.draw_line(eye + Vector2(-5, 5), eye + Vector2(5, -5), DEEP, 3)
	else:
		_field.draw_circle(eye + Vector2(face * 2, 0), 4, DEEP)


func _draw_jelly(pos: Vector2, r: float, ph: float) -> void:
	var pulse := 1.0 + sin(_t * 4.0 + ph) * 0.06
	# 촉수
	for k in 6:
		var x0 := pos.x + (k - 2.5) * r * 0.28
		var pts := PackedVector2Array()
		for s in 8:
			var y := pos.y + r * 0.2 + s * r * 0.22
			pts.append(Vector2(x0 + sin(_t * 3.0 + ph + s * 0.8 + k) * 6.0, y))
		_field.draw_polyline(pts, Color(1.0, 0.7, 0.9, 0.55), 4.0, true)
	# 몸 (반원 돔)
	var dome := PackedVector2Array()
	for k in 21:
		var a := PI + PI * k / 20
		dome.append(pos + Vector2(cos(a) * r * pulse, sin(a) * r * 0.85 / pulse))
	dome.append(pos + Vector2(r * pulse, r * 0.12))
	dome.append(pos + Vector2(-r * pulse, r * 0.12))
	_field.draw_colored_polygon(dome, Color(1.0, 0.55, 0.82, 0.78))
	_field.draw_circle(pos + Vector2(-r * 0.3, -r * 0.42), r * 0.18, Color(1, 1, 1, 0.5))


func _draw_heart(c: Vector2, s: float, col: Color) -> void:
	_field.draw_circle(c + Vector2(-s * 0.5, 0), s * 0.6, col)
	_field.draw_circle(c + Vector2(s * 0.5, 0), s * 0.6, col)
	_field.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.08, s * 0.15), c + Vector2(s * 1.08, s * 0.15), c + Vector2(0, s * 1.3)]), col)


func _score_text(p: Dictionary) -> String:
	var f: Dictionary = _fish[int(p["slot"])]
	return "x%d" % int(f["hearts"]) if int(f["hearts"]) > 0 else tr("OUT")
