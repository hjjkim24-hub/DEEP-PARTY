extends RefCounted
## 배경·아이콘에서 같이 쓰는 그리기 도우미 (게임 말, 별, 타원, 둥근 사각형).
## 이미지 파일 없이 코드로만 그리기 때문에 해상도에 상관없이 선명해요.

const PLAYER_COLORS := [Color("ff4d5e"), Color("3d7bff"), Color("ffc93c"), Color("2fd37f")]

## 실사풍 말 그림 (tools/render_pawn.py 로 만듦). 아이템 그림도 같은 크기·같은 카메라라서 그대로 겹치면 맞아요.
const PAWN_DIFFUSE := preload("res://textures/pawn_diffuse.png")   # 명암 (색을 곱해서 칠함)
const PAWN_SPEC := preload("res://textures/pawn_spec.png")         # 반짝임
const PAWN_TOP := 0.2573      # 그림 안에서 말 위끝 위치 (비율, 모자 자리 포함해서 위가 비어 있음)
const PAWN_BOTTOM := 0.9781   # 그림 안에서 말 아래끝 위치 (비율)
const COSMETIC_TEX := {
	"party_hat": preload("res://textures/cosmetics/party_hat.png"),
	"top_hat": preload("res://textures/cosmetics/top_hat.png"),
	"crown": preload("res://textures/cosmetics/crown.png"),
	"beanie": preload("res://textures/cosmetics/beanie.png"),
	"stripes": preload("res://textures/cosmetics/pattern_stripes.png"),
	"diamond": preload("res://textures/cosmetics/pattern_diamond.png"),
	"scarf": preload("res://textures/cosmetics/scarf.png"),
	"sunglasses": preload("res://textures/cosmetics/sunglasses.png"),
	"pearl_necklace": preload("res://textures/cosmetics/pearl_necklace.png"),
	"red_cape": preload("res://textures/cosmetics/red_cape.png"),
	"swim_ring": preload("res://textures/cosmetics/swim_ring.png"),
	"coat": preload("res://textures/cosmetics/coat.png"),
}


## 무늬 색: 말 색이 밝으면 진하게, 어두우면 크림색으로 (항상 잘 보이게)
static func pattern_color(tint: Color) -> Color:
	var lum := tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114
	return Color(tint.darkened(0.45), tint.a) if lum > 0.62 else Color(0.97, 0.94, 0.88, tint.a)


## 실사풍 말 그리기. base = 바닥 가운데 점, h = 말 높이, tint = 칠할 색, look = 꾸미기 {"hat": "crown", ...}
static func draw_pawn_real(ci: CanvasItem, base: Vector2, h: float, tint: Color, shine: float = 1.0, look: Dictionary = {}) -> void:
	if h < 2.0:
		return
	var tex_h := h / (PAWN_BOTTOM - PAWN_TOP)
	var tex_w := tex_h * float(PAWN_DIFFUSE.get_width()) / float(PAWN_DIFFUSE.get_height())
	var rect := Rect2(base.x - tex_w * 0.5, base.y - PAWN_BOTTOM * tex_h, tex_w, tex_h)
	ci.draw_texture_rect(PAWN_DIFFUSE, rect, false, tint)
	if look.has("pattern") and COSMETIC_TEX.has(look["pattern"]):
		ci.draw_texture_rect(COSMETIC_TEX[look["pattern"]], rect, false, pattern_color(tint))
	if shine > 0.0:
		ci.draw_texture_rect(PAWN_SPEC, rect, false, Color(1, 1, 1, shine * tint.a))
	# 옷 → 장식품 → 모자 순서로 겹쳐 그림
	for cat in ["outfit", "accessory", "hat"]:
		if look.has(cat) and COSMETIC_TEX.has(look[cat]):
			ci.draw_texture_rect(COSMETIC_TEX[look[cat]], rect, false, Color(1, 1, 1, tint.a))


## 멀리 있는 물체일수록 물 색에 섞이게 (fog.a = 섞는 정도)
static func fogged(c: Color, fog: Color) -> Color:
	if fog.a <= 0.0:
		return c
	return Color(lerpf(c.r, fog.r, fog.a), lerpf(c.g, fog.g, fog.a), lerpf(c.b, fog.b, fog.a), c.a)


static func lit(c: Color, s: float) -> Color:
	return Color(clampf(c.r * s, 0.0, 1.0), clampf(c.g * s, 0.0, 1.0), clampf(c.b * s, 0.0, 1.0), c.a)


## 너무 납작해진 도형은 건너뛰어서 삼각분할 오류를 막아요
static func poly(ci: CanvasItem, pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size()
	if n < 3:
		return
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	if absf(area) < 3.0:
		return
	ci.draw_colored_polygon(pts, c)


static func ellipse(center: Vector2, rx: float, ry: float, seg: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func star(center: Vector2, r_out: float, r_in: float, sx: float = 1.0, rot: float = -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var r := r_out if i % 2 == 0 else r_in
		var a := rot + PI * float(i) / 5.0
		pts.append(center + Vector2(cos(a) * r * sx, sin(a) * r))
	return pts


static func rounded_rect(rect: Rect2, r: float, seg: int = 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [
		rect.position + Vector2(rect.size.x - r, rect.size.y - r),
		rect.position + Vector2(r, rect.size.y - r),
		rect.position + Vector2(r, r),
		rect.position + Vector2(rect.size.x - r, r),
	]
	for c in 4:
		var start := PI * 0.5 * float(c)
		for s in seg + 1:
			var ang := start + PI * 0.5 * float(s) / float(seg)
			pts.append(corners[c] + Vector2(cos(ang), sin(ang)) * r)
	return pts


## 보드게임 말(폰). base = 바닥 가운데 점, h = 전체 높이
static func draw_pawn(ci: CanvasItem, base: Vector2, h: float, color: Color) -> void:
	if h < 2.0:
		return
	var w := h * 0.6
	var dark := color.darkened(0.38)
	var light := color.lightened(0.45)

	# 받침
	poly(ci, ellipse(base, w * 0.5, w * 0.17), dark)
	poly(ci, ellipse(base + Vector2(0, -h * 0.07), w * 0.5, w * 0.17), color)

	# 몸통 (종 모양)
	var body := PackedVector2Array()
	var shine := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var f := float(i) / float(steps)
		var y := lerpf(-h * 0.07, -h * 0.6, f)
		var hw := lerpf(w * 0.42, w * 0.14, pow(f, 0.7))
		body.append(base + Vector2(-hw, y))
	for i in range(steps, -1, -1):
		var f := float(i) / float(steps)
		var y := lerpf(-h * 0.07, -h * 0.6, f)
		var hw := lerpf(w * 0.42, w * 0.14, pow(f, 0.7))
		body.append(base + Vector2(hw, y))
	poly(ci, body, color)

	# 몸통 반짝임
	for i in range(1, steps):
		var f := float(i) / float(steps)
		var y := lerpf(-h * 0.07, -h * 0.6, f)
		var hw := lerpf(w * 0.42, w * 0.14, pow(f, 0.7))
		shine.append(base + Vector2(-hw * 0.72, y))
	for i in range(steps - 1, 0, -1):
		var f := float(i) / float(steps)
		var y := lerpf(-h * 0.07, -h * 0.6, f)
		var hw := lerpf(w * 0.42, w * 0.14, pow(f, 0.7))
		shine.append(base + Vector2(-hw * 0.42, y))
	poly(ci, shine, Color(light.r, light.g, light.b, 0.55))

	# 목 받침 + 머리
	poly(ci, ellipse(base + Vector2(0, -h * 0.6), w * 0.27, w * 0.09), dark)
	var head := base + Vector2(0, -h * 0.77)
	ci.draw_circle(head, w * 0.28, color)
	ci.draw_arc(head, w * 0.28, PI * 0.15, PI * 0.85, 12, dark, maxf(1.0, h * 0.025), true)
	ci.draw_circle(head + Vector2(-w * 0.09, -w * 0.1), w * 0.09, light)
