extends Node2D
## 위로 보글보글 올라가는 물방울 + 물속에 떠다니는 작은 부유물

@export var ambient_rate := 7.0    ## 초당 새로 생기는 물방울 수
@export var snow_count := 90       ## 떠다니는 작은 알갱이 수

var area_size := Vector2(1920, 1080)
var vents: Array[Vector2] = []    ## 공기방울이 줄지어 새어 나오는 지점들
@export var vent_rate := 2.5      ## 지점마다 초당 물방울 수

var _bubbles: Array[Dictionary] = []
var _snow: Array[Dictionary] = []
var _acc := 0.0
var _vent_acc := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in 35:
		_spawn_ambient(true)
	for i in snow_count:
		_snow.append({
			"pos": Vector2(_rng.randf() * area_size.x, _rng.randf() * area_size.y),
			"r": _rng.randf_range(0.8, 2.4),
			"a": _rng.randf_range(0.12, 0.4),
			"vx": _rng.randf_range(-6.0, 6.0),
			"vy": _rng.randf_range(-3.0, 9.0),
			"ph": _rng.randf() * TAU,
		})


func _spawn_ambient(anywhere: bool) -> void:
	var r := lerpf(2.5, 16.0, pow(_rng.randf(), 2.4))
	var y := _rng.randf() * area_size.y if anywhere else area_size.y + r + 8.0
	_bubbles.append({
		"pos": Vector2(_rng.randf() * area_size.x, y),
		"r": r,
		"vy": 35.0 + r * 7.0 + _rng.randf() * 20.0,
		"ph": _rng.randf() * TAU,
		"wob": _rng.randf_range(8.0, 22.0),
		"wf": _rng.randf_range(1.2, 2.6),
	})


## 특정 위치에서 물방울을 뿜어요 (버튼에 마우스를 올리거나 클릭할 때)
func burst(at: Vector2, count: int = 8) -> void:
	for i in count:
		_bubbles.append({
			"pos": at + Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-10.0, 10.0)),
			"r": _rng.randf_range(2.5, 8.5),
			"vy": _rng.randf_range(90.0, 180.0),
			"ph": _rng.randf() * TAU,
			"wob": _rng.randf_range(12.0, 28.0),
			"wf": _rng.randf_range(2.0, 3.5),
		})


func _process(delta: float) -> void:
	_t += delta
	_acc += delta * ambient_rate
	while _acc >= 1.0:
		_acc -= 1.0
		_spawn_ambient(false)

	_vent_acc += delta * vent_rate
	while _vent_acc >= 1.0 and not vents.is_empty():
		_vent_acc -= 1.0
		for v in vents:
			if _rng.randf() < 0.75:
				_bubbles.append({
					"pos": v + Vector2(_rng.randf_range(-6.0, 6.0), 0.0),
					"r": _rng.randf_range(1.5, 4.5),
					"vy": _rng.randf_range(55.0, 95.0),
					"ph": _rng.randf() * TAU,
					"wob": _rng.randf_range(6.0, 14.0),
					"wf": _rng.randf_range(2.0, 3.2),
				})

	for i in range(_bubbles.size() - 1, -1, -1):
		var b := _bubbles[i]
		var p: Vector2 = b["pos"]
		p.y -= b["vy"] * delta
		p.x += cos(_t * b["wf"] + b["ph"]) * b["wob"] * delta
		b["pos"] = p
		if p.y < -b["r"] - 20.0:
			_bubbles.remove_at(i)

	for s in _snow:
		var p: Vector2 = s["pos"]
		p.x += (s["vx"] + sin(_t * 0.5 + s["ph"]) * 5.0) * delta
		p.y += s["vy"] * delta
		if p.x < -5.0:
			p.x += area_size.x + 10.0
		elif p.x > area_size.x + 5.0:
			p.x -= area_size.x + 10.0
		if p.y < -5.0:
			p.y += area_size.y + 10.0
		elif p.y > area_size.y + 5.0:
			p.y -= area_size.y + 10.0
		s["pos"] = p

	queue_redraw()


func _draw() -> void:
	for s in _snow:
		draw_circle(s["pos"], s["r"], Color(0.85, 1.0, 0.95, s["a"]))
	for b in _bubbles:
		var p: Vector2 = b["pos"]
		var r: float = b["r"]
		draw_circle(p, r, Color(0.72, 1.0, 0.92, 0.1))
		draw_arc(p, r, 0.0, TAU, 14 + int(r), Color(0.88, 1.0, 0.96, 0.6), maxf(1.2, r * 0.13), true)
		draw_circle(p + Vector2(-r * 0.35, -r * 0.38), r * 0.24, Color(1, 1, 1, 0.8))
