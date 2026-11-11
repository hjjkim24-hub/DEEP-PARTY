extends RefCounted
## 게임 안 글씨: 해적 보드게임 느낌
##   제목·큰 글씨  = Pirata One (해적 깃발 같은 굵은 고딕 글씨)
##   보통 글씨     = Almendra Bold (옛날 항해 지도 같은 글씨)
##   한글          = 고운바탕 Bold (옛 인쇄물 느낌, 두 글씨 모두의 대신 글씨)
## 메인화면은 그대로 Poppins.

const TITLE := preload("res://fonts/PirataOne-Regular.ttf")
const BODY := preload("res://fonts/Almendra-Bold.ttf")
const KO := preload("res://fonts/GowunBatang-Bold.ttf")
const TITLE_SIZE := 34      ## 이 크기 이상 글씨는 제목 글씨로


static func body() -> Font:
	var f: FontFile = BODY
	if f.fallbacks.is_empty():
		f.fallbacks = [KO]
	return f


static func title() -> Font:
	var f: FontFile = TITLE
	if f.fallbacks.is_empty():
		f.fallbacks = [KO]
	return f


## root 아래에 새로 생기는 큰 글씨(라벨 · 버튼)는 자동으로 제목 글씨로 바꿈
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
	# 이미 있는 것들
	for n in root.find_children("*", "Control", true, false):
		if n is Label or n is Button:
			_check(n)


static func _check(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var c := n as Control
	if c.has_theme_font_override("font"):
		return
	if c.has_theme_font_size_override("font_size") and c.get_theme_font_size("font_size") >= TITLE_SIZE:
		c.add_theme_font_override("font", title())
