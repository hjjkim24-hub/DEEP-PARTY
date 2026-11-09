extends Control
## 로비 카드 안의 큰 말 그림. 받침대 위에 서서 살짝 둥실거려요.
## 빈자리는 흐릿한 실루엣으로 보여줘요.
## (나중에 말 커스터마이징을 넣으면 여기서 모자·무늬 등을 그리면 돼요)

const PieceDraw := preload("res://scripts/background/piece_draw.gd")

var color := Color("eafffa")
var empty := false
var look: Dictionary = {}   ## 꾸미기 {"hat": "crown", ...}
var size_factor := 0.62     ## 영역 높이 대비 말 크기 (위쪽은 모자 자리)
var base_frac := 0.9        ## 받침대 위치 (영역 높이 비율)
var _t := 0.0


func _ready() -> void:
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var h := minf(size.y * size_factor, size.x * 1.25)
	var base := Vector2(size.x * 0.5, size.y * base_frac)
	# 받침대 + 은은한 빛
	var glow_a := 0.05 if empty else 0.12
	for i in 4:
		var k := 1.0 + float(i) * 0.25
		PieceDraw.poly(self, PieceDraw.ellipse(base + Vector2(0, -h * 0.35), h * 0.42 * k, h * 0.42 * k, 40), Color(color, glow_a * 0.4))
	PieceDraw.poly(self, PieceDraw.ellipse(base + Vector2(0, 6), h * 0.5, h * 0.12, 40), Color(0.0, 0.05, 0.05, 0.35))
	PieceDraw.poly(self, PieceDraw.ellipse(base, h * 0.5, h * 0.12, 40), Color(color, 0.10 if empty else 0.22))
	draw_arc(base, h * 0.5, 0, TAU, 48, Color(color, 0.2), 2.0, true)
	if empty:
		PieceDraw.draw_pawn_real(self, base, h, Color(color, 0.14), 0.0)
		return
	var bob := absf(sin(_t * 1.8)) * h * 0.03
	PieceDraw.draw_pawn_real(self, base + Vector2(0, -bob), h, color, 1.0, look)
