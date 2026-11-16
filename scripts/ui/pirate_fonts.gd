extends RefCounted
## 게임 안 글씨: 해적 보드게임 느낌
##   제목·큰 글씨  = Pirata One (해적 깃발 같은 굵은 고딕 글씨) + 금박 재질 + 짙은 갈색 테두리 + 그림자
##   보통 글씨     = 같은 Pirata One + 잉크 결 + 갈색 테두리
##   한글          = 고운바탕 Bold (옛 인쇄물 느낌, 대신 글씨)
## 메인화면도 같은 글씨 (Pirata One + 고운바탕 Bold).

const TITLE := preload("res://fonts/PirataOne-Regular.ttf")
const BODY := TITLE
const KO := preload("res://fonts/GowunBatang-Bold.ttf")
const TextShader := preload("res://shaders/pirate_text.gdshader")
const TITLE_SIZE := 34      ## 이 크기 이상 글씨는 제목 글씨로
const INK := Color(0.17, 0.09, 0.04)


static func body() -> Font:
	return title()


static func title() -> Font:
	var f: FontFile = TITLE
	if f.fallbacks.is_empty():
		f.fallbacks = [KO]
	return f


## 테마 기본 글씨: 갈색 테두리 + 옅은 그림자
static func style_theme(th: Theme) -> void:
	th.default_font = body()
	for t in ["Label", "Button"]:
		th.set_color("font_outline_color", t, Color(INK, 0.85))
		th.set_constant("outline_size", t, 5)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	th.set_constant("shadow_offset_x", "Label", 0)
	th.set_constant("shadow_offset_y", "Label", 2)


## root 아래 글씨들에 재질을 입힘 (새로 생기는 것도)
static func watch(root: Node) -> void:
	var tree := root.get_tree()
	var cb := func(n: Node) -> void:
		if not is_instance_valid(root) or not (n is Label or n is Button):
			return
		if root.is_ancestor_of(n):
			(func() -> void: _check(n)).call_deferred()
	tree.node_added.connect(cb)
	root.tree_exiting.connect(func() -> void:
		if tree.node_added.is_connected(cb):
			tree.node_added.disconnect(cb))
	for n in root.find_children("*", "Control", true, false):
		if n is Label or n is Button:
			_check(n)


static func _check(n: Node) -> void:
	if not is_instance_valid(n) or n.has_meta("pirate_done"):
		return
	n.set_meta("pirate_done", true)
	var c := n as Control
	var big := c.has_theme_font_size_override("font_size") and c.get_theme_font_size("font_size") >= TITLE_SIZE
	if big and not c.has_theme_font_override("font"):
		c.add_theme_font_override("font", title())
	if big:
		var sz := c.get_theme_font_size("font_size")
		c.add_theme_color_override("font_outline_color", INK)
		c.add_theme_constant_override("outline_size", maxi(6, sz / 6))
		if n is Label:
			c.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
			c.add_theme_constant_override("shadow_offset_y", maxi(3, sz / 14))
			c.add_theme_constant_override("shadow_offset_x", 0)
			c.add_theme_constant_override("shadow_outline_size", maxi(6, sz / 6))
	if n is Label:
		var m := ShaderMaterial.new()
		m.shader = TextShader
		m.set_shader_parameter("metal", 1.0 if big else 0.0)
		c.material = m
		var upd := func() -> void: _update(n as Label)
		c.resized.connect(upd)
		(n as Label).draw.connect(upd)
		_update(n as Label)


## 양피지 위에 쓴 잉크 글씨 (테두리 · 그림자 없이, 잉크 결만)
static func ink(l: Label, col: Color, is_title: bool = false) -> Label:
	l.set_meta("pirate_done", true)
	l.add_theme_font_override("font", title() if is_title else body())
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var m := ShaderMaterial.new()
	m.shader = TextShader
	m.set_shader_parameter("metal", 0.0)
	l.material = m
	return l


## 셰이더에 줄 위치를 알려 줌 (세로 금빛 그라데이션이 글자 높이에 맞게)
static func _update(l: Label) -> void:
	if not is_instance_valid(l) or not (l.material is ShaderMaterial):
		return
	var lh := float(l.get_line_height())
	var lines := maxi(1, l.get_visible_line_count())
	var total := lh * lines
	var y0 := 0.0
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y0 = (l.size.y - total) * 0.5
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y0 = l.size.y - total
	var key := Vector2(y0, maxf(lh, 1.0))
	if l.get_meta("pirate_key", Vector2(-1, -1)) == key:
		return
	l.set_meta("pirate_key", key)
	var m := l.material as ShaderMaterial
	m.set_shader_parameter("y0", key.x)
	m.set_shader_parameter("line_h", key.y)
