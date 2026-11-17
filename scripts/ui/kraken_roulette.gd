extends Control
## 크라켄의 보물상자 룰렛: 보물상자(금) · 크라켄(초록) 칸이 번갈아 있는 원판. 위쪽 바늘이 가리키는 칸이 결과.
##   spin(win) 을 await 하면 여러 바퀴 돌다가 천천히 멈춤 → 그 칸이 반짝임

const SEGS := 10
const R := 250.0
const CHEST_TEX := preload("res://textures/tiles/icon_treasure.png")
const KRAKEN_TEX := preload("res://textures/tiles/icon_boss.png")
const GOLD := Color(0.97, 0.74, 0.24)
const GOLD_DARK := Color(0.62, 0.4, 0.1)
const KRAKEN := Color(0.1, 0.36, 0.24)
const KRAKEN_DARK := Color(0.04, 0.18, 0.12)

var wheel: Control
var _hl := -1          ## 반짝일 칸
var _hl_t := 0.0
var _last_seg := -1


func _ready() -> void:
	custom_minimum_size = Vector2(R * 2.0 + 40.0, R * 2.0 + 70.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel = Control.new()
	wheel.size = Vector2(R * 2.0, R * 2.0)
	wheel.position = Vector2(20.0, 50.0)
	wheel.pivot_offset = Vector2(R, R)
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.draw.connect(_draw_wheel)
	add_child(wheel)


## 칸 k 의 가운데 각도 (원판 기준, 0 = 위)
func _seg_angle(k: int) -> float:
	return TAU * (k + 0.5) / SEGS


func _draw_wheel() -> void:
	var c := Vector2(R, R)
	# 바깥 금테 + 그림자
	wheel.draw_circle(c + Vector2(0, 8), R + 14.0, Color(0, 0, 0, 0.35))
	wheel.draw_circle(c, R + 14.0, GOLD_DARK)
	wheel.draw_circle(c, R + 8.0, GOLD)
	for k in SEGS:
		var a0 := TAU * k / SEGS - PI * 0.5
		var a1 := TAU * (k + 1) / SEGS - PI * 0.5
		var chest := k % 2 == 0
		var pts := PackedVector2Array([c])
		for q in 13:
			var a := lerpf(a0, a1, q / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * R)
		var col := GOLD if chest else KRAKEN
		if k == _hl:
			col = col.lightened(0.25 + 0.2 * sin(_hl_t * 14.0))
		wheel.draw_colored_polygon(pts, col)
		# 안쪽 그늘 (입체감)
		var inner := PackedVector2Array([c])
		for q in 13:
			var a := lerpf(a0, a1, q / 12.0)
			inner.append(c + Vector2(cos(a), sin(a)) * R * 0.42)
		wheel.draw_colored_polygon(inner, (GOLD_DARK if chest else KRAKEN_DARK).lerp(col, 0.3))
		# 칸 경계선
		wheel.draw_line(c, c + Vector2(cos(a0), sin(a0)) * R, Color(0.25, 0.15, 0.05), 4.0, true)
		# 그림 (원판 바깥쪽 가까이, 가운데를 향해 똑바로)
		var am := (a0 + a1) * 0.5
		var ip := c + Vector2(cos(am), sin(am)) * R * 0.7
		var sz := 74.0
		wheel.draw_set_transform(ip, am + PI * 0.5, Vector2.ONE)
		wheel.draw_texture_rect(CHEST_TEX if chest else KRAKEN_TEX, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false,
			Color(0.35, 0.18, 0.04) if chest else Color(0.62, 1.0, 0.5))
		wheel.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 가운데 금 단추 + 크라켄 눈
	wheel.draw_circle(c, 46.0, GOLD_DARK)
	wheel.draw_circle(c, 40.0, GOLD)
	wheel.draw_texture_rect(KRAKEN_TEX, Rect2(c - Vector2(30, 30), Vector2(60, 60)), false, Color(0.15, 0.08, 0.02))


func _draw() -> void:
	# 위쪽 바늘 (원판 위에 고정)
	var tip := Vector2(R + 20.0, 50.0 + 34.0)
	var pts := PackedVector2Array([tip, tip + Vector2(-26, -58), tip + Vector2(26, -58)])
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 5), tip + Vector2(-29, -55), tip + Vector2(29, -55)]), Color(0, 0, 0, 0.4))
	draw_colored_polygon(pts, Color(0.95, 0.2, 0.16))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), GOLD, 4.0, true)
	draw_circle(tip + Vector2(0, -44), 9.0, GOLD)


func _process(delta: float) -> void:
	_hl_t += delta
	# 바늘 아래 칸이 바뀔 때마다 딸깍
	var a := fposmod(-wheel.rotation, TAU)
	var seg := int(a / (TAU / SEGS)) % SEGS
	if seg != _last_seg:
		_last_seg = seg
		Audio.play("tick", 30)
	wheel.queue_redraw()


## 돌리기: win 이면 보물상자 칸, 아니면 크라켄 칸에 멈춤 (await)
func spin(win: bool) -> void:
	var picks := []
	for k in SEGS:
		if (k % 2 == 0) == win:
			picks.append(k)
	var k: int = picks[randi() % picks.size()]
	# 바늘(위)이 칸 k 의 가운데를 가리키려면 원판을 -(칸 각도) 만큼 돌림 + 칸 안에서 살짝 비껴서
	var jitter := randf_range(-0.32, 0.32) * TAU / SEGS
	var target := -_seg_angle(k) + jitter - TAU * 6.0
	wheel.rotation = fposmod(wheel.rotation, TAU)
	var t := create_tween()
	t.tween_property(wheel, "rotation", target, 4.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await t.finished
	_hl = k
	_hl_t = 0.0
	await get_tree().create_timer(1.1, false).timeout
