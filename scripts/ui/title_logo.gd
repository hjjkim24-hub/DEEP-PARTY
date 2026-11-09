extends Control
## 게임 로고. 바다 색으로 통일 (진주빛 흰색 + 아쿠아), 글자가 물결처럼 살짝 흔들려요.
## text 에 "\n" 을 넣으면 여러 줄. play_intro() 를 부르면 글자가 위에서 하나씩 내려와요.

@export var text := "DEEP\nPARTY"
@export var font_size := 168
@export var line_spacing := 0.86          ## 줄 간격 (글자 크기 대비)
@export var align_left := true
@export var line_colors: Array[Color] = [Color("eafffa"), Color("8ff0dc")]  ## 줄마다 글자색
@export var outline_color := Color("05302c")
@export var rim_color := Color(0.55, 1.0, 0.9, 0.9)   ## 테두리 안쪽 얇은 빛

var _t := 0.0
var _intro_t := 999.0


func play_intro() -> void:
	_intro_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_intro_t += delta
	queue_redraw()


func _ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var lines := text.split("\n")
	var spacing := font_size * 0.015
	var line_h := font_size * line_spacing
	var block_h := line_h * float(lines.size() - 1)
	var first_baseline := size.y * 0.5 - block_h * 0.5 + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pad := 18.0

	var letters: Array[Dictionary] = []
	var gi := 0
	for li in lines.size():
		var line: String = lines[li]
		var widths: Array[float] = []
		var total := 0.0
		for ch in line:
			var w := font_size * 0.3 if ch == " " else font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			widths.append(w)
			total += w + spacing
		total -= spacing
		var x := pad if align_left else (size.x - total) * 0.5
		var baseline := first_baseline + line_h * float(li)
		for ci in line.length():
			var ch := line[ci]
			var w := widths[ci]
			var cx := x + w * 0.5
			x += w + spacing
			if ch == " ":
				continue
			var p := clampf((_intro_t - float(gi) * 0.05) / 0.7, 0.0, 1.0)
			letters.append({
				"ch": ch, "w": w, "alpha": p,
				"pos": Vector2(cx, baseline + (1.0 - _ease_out_cubic(p)) * -60.0 + sin(_t * 1.4 + float(gi) * 0.5) * 6.0),
				"rot": sin(_t * 1.1 + float(gi) * 0.7) * 0.025,
				"color": line_colors[li % line_colors.size()],
			})
			gi += 1

	# 층별로 겹쳐 그리기: 그림자 → 진한 테두리 → 안쪽 빛 테두리 → 글자
	for layer in 4:
		for L in letters:
			var a: float = L["alpha"]
			if a <= 0.0:
				continue
			var ch: String = L["ch"]
			var o := Vector2(-float(L["w"]) * 0.5, 0.0)
			draw_set_transform(L["pos"], L["rot"], Vector2.ONE)
			match layer:
				0:
					var sc := Color(0.0, 0.06, 0.05, 0.35 * a)
					draw_string_outline(font, o + Vector2(0, 12), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 34, sc)
				1:
					draw_string_outline(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 24, Color(outline_color, a))
				2:
					draw_string_outline(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, Color(rim_color, rim_color.a * a))
				3:
					var col: Color = L["color"]
					draw_string(font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(col, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
