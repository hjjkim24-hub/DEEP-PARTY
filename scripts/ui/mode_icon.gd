extends Control
## 모드 선택 카드 안의 그림 (개인전 / 2:2 팀전 / 4인 협동). 바다 색 두 가지로만 그려요.
## excited = true 이면 (카드에 커서가 올라가면) 더 신나게 뛰어요.

const PieceDraw := preload("res://scripts/background/piece_draw.gd")
const PEARL := Color("eafffa")
const AQUA := Color("6fe6cf")
const DEEP := Color("05302c")

@export var mode := 0
var excited := false

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta * (2.0 if excited else 1.0)
	queue_redraw()


func _shadow(x: float, ground: float, w: float) -> void:
	PieceDraw.poly(self, PieceDraw.ellipse(Vector2(x, ground + 2.0), w * 0.55, w * 0.15), Color(0, 0, 0, 0.2))


func _draw() -> void:
	var c := size * 0.5
	var ground := c.y + size.y * 0.36
	match mode:
		0:  # 개인전: 4명이 번갈아 폴짝
			var h := size.y * 0.5
			var cols := [PEARL, PEARL.lerp(AQUA, 0.35), PEARL.lerp(AQUA, 0.7), AQUA]
			for i in 4:
				var x := c.x + (float(i) - 1.5) * size.x * 0.22
				var hop := absf(sin(_t * 3.0 + float(i) * 0.9)) * h * 0.18
				_shadow(x, ground, h * 0.6)
				PieceDraw.draw_pawn_real(self, Vector2(x, ground - hop), h, cols[i])
		1:  # 2:2 팀전: 진주색 팀 VS 아쿠아 팀
			var h := size.y * 0.46
			var team := [[-0.4, PEARL], [-0.23, PEARL], [0.23, AQUA], [0.4, AQUA]]
			for i in 4:
				var x := c.x + float(team[i][0]) * size.x
				var hop := absf(sin(_t * 3.0 + (0.0 if i < 2 else 1.6))) * h * 0.16
				_shadow(x, ground, h * 0.6)
				PieceDraw.draw_pawn_real(self, Vector2(x, ground - hop), h, team[i][1])
			var font := get_theme_default_font()
			if font:
				var fs := 40
				var ts := font.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var pos := Vector2(c.x - ts.x * 0.5, c.y + size.y * 0.06 + fs * 0.35)
				draw_string_outline(font, pos, "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, DEEP)
				draw_string(font, pos, "VS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PEARL)
		2:  # 4인 협동: 가운데 별을 둘러싸고 다 같이 폴짝
			var h := size.y * 0.46
			var hop := absf(sin(_t * 3.0)) * h * 0.16
			var star_c := Vector2(c.x, c.y - size.y * 0.02 - hop * 0.5)
			var r := size.y * 0.17
			PieceDraw.poly(self, PieceDraw.star(star_c, r * 1.15, r * 0.55, 1.0, -PI * 0.5 + sin(_t) * 0.15), DEEP)
			PieceDraw.poly(self, PieceDraw.star(star_c, r, r * 0.45, 1.0, -PI * 0.5 + sin(_t) * 0.15), PEARL)
			var xs := [-0.39, -0.2, 0.2, 0.39]
			for i in 4:
				var x := c.x + float(xs[i]) * size.x
				_shadow(x, ground, h * 0.6)
				PieceDraw.draw_pawn_real(self, Vector2(x, ground - hop), h, AQUA)
