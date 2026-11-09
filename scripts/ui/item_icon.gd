extends Control
## 꾸미기 화면 아이템 칸의 그림. 말에 끼운 모습이 아니라 아이템만 단독으로 보여줘요.
## 무늬는 말 색 구슬 위에 무늬가 칠해진 모양으로 보여줘요.

const PieceDraw := preload("res://scripts/background/piece_draw.gd")
const SPHERE_DIFFUSE := preload("res://textures/cosmetics/icons/sphere_diffuse.png")
const SPHERE_SPEC := preload("res://textures/cosmetics/icons/sphere_spec.png")
const ICONS := {
	"party_hat": preload("res://textures/cosmetics/icons/party_hat.png"),
	"top_hat": preload("res://textures/cosmetics/icons/top_hat.png"),
	"crown": preload("res://textures/cosmetics/icons/crown.png"),
	"beanie": preload("res://textures/cosmetics/icons/beanie.png"),
	"stripes": preload("res://textures/cosmetics/icons/pattern_stripes.png"),
	"diamond": preload("res://textures/cosmetics/icons/pattern_diamond.png"),
	"scarf": preload("res://textures/cosmetics/icons/scarf.png"),
	"sunglasses": preload("res://textures/cosmetics/icons/sunglasses.png"),
	"pearl_necklace": preload("res://textures/cosmetics/icons/pearl_necklace.png"),
	"red_cape": preload("res://textures/cosmetics/icons/red_cape.png"),
	"swim_ring": preload("res://textures/cosmetics/icons/swim_ring.png"),
	"coat": preload("res://textures/cosmetics/icons/coat.png"),
}

var item_id := ""
var is_pattern := false
var tint := Color.WHITE      ## 무늬 구슬 색 (내 말 색)
var _t := 0.0
var hovered := false


func _process(delta: float) -> void:
	_t += delta * (2.0 if hovered else 1.0)
	queue_redraw()


func _draw() -> void:
	if not ICONS.has(item_id):
		return
	var side := minf(size.x, size.y)
	var bob := sin(_t * 1.6) * side * 0.015
	var rect := Rect2((size - Vector2(side, side)) * 0.5 + Vector2(0, bob), Vector2(side, side))
	# 바닥 그림자
	PieceDraw.poly(self, PieceDraw.ellipse(Vector2(size.x * 0.5, rect.end.y - side * 0.04), side * 0.3, side * 0.05), Color(0, 0, 0, 0.22))
	if is_pattern:
		draw_texture_rect(SPHERE_DIFFUSE, rect, false, tint)
		draw_texture_rect(ICONS[item_id], rect, false, PieceDraw.pattern_color(tint))
		draw_texture_rect(SPHERE_SPEC, rect, false, Color.WHITE)
	else:
		draw_texture_rect(ICONS[item_id], rect, false, Color.WHITE)
