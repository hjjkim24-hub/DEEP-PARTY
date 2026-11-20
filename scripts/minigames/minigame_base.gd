extends Control
## 미니게임 공통 틀. 모든 미니게임이 이걸 상속해요.
##   소개 카드(설명·조작법) → READY → 3·2·1·GO → 플레이 → FINISH! → finished(순위) 신호
## 화면은 1920x1080 기준 'arena' 안에 그리고, 창 크기에 맞춰 늘려요.
## 사람은 이 컴퓨터의 플레이어 한 명(마우스/키보드), 나머지는 CPU 가 같이 플레이해요.
##
## 상속해서 채울 것:
##   _setup_game()       화면 만들기          _start_game()      GO! 순간
##   _tick(delta)        매 프레임 (플레이 중)  _is_done() -> bool  끝났는지 (기본: 시간 다 됨)
##   _ranking() -> Array 순위 (기본: 점수 높은 순)
##   _score_text(p)      이름표에 보일 점수 글씨

signal finished(ranking: Array)
signal demo_done

const PirateFonts := preload("res://scripts/ui/pirate_fonts.gd")
const BackgroundScene := preload("res://scenes/underwater_background.tscn")
const ARENA := Vector2(1920, 1080)
const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const GOLD := Color("ffcf4a")

var title := "MINIGAME"
var how_to := ""
var goal := "Highest score wins!"   ## 소개 화면에 보일 목표 한 줄
var controls := "MOUSE"          ## "MOUSE" 또는 "KEYBOARD"
var duration := 20.0
var show_timer := true           ## 시간 제한이 없는 게임은 false
var players: Array = []          ## 보드의 말 정보 (name, color, cpu, slot)
var auto_human := false          ## 자동 점검: 사람도 CPU처럼
var demo := false                ## 소개 화면의 미리보기 (모두 자동, 소리 없음)
var scores := {}                 ## slot → 점수
var heat := 0.25                 ## 기본 난이도를 살짝 높이는 값 (보드 진행과 상관없이 늘 같음)
var time_left := 0.0
var playing := false
var arena: Control
var rng := RandomNumberGenerator.new()

var _hint_cb: Callable
var _hud: HBoxContainer
var _chips := {}                 ## slot → Label
var _timer_label: Label
var _overlay: Control


func setup(p_players: Array, auto: bool, hint: Callable = Callable()) -> void:
	players = p_players
	auto_human = auto
	_hint_cb = hint
	for p in players:
		scores[int(p["slot"])] = 0.0


## 사람이 하는 자리인지 (CPU 생각을 돌리지 않을 자리).
## 온라인 손님 PC 에서는 모두 true → 손님 PC 는 CPU 를 직접 움직이지 않고 방장이 보낸 대로 보여줌
func is_human(p: Dictionary) -> bool:
	if net == "client":
		return true
	return not bool(p["cpu"]) and not auto_human


## 이 PC 의 키보드 · 마우스로 조작하는 자리인지
func is_local(p: Dictionary) -> bool:
	if bool(p["cpu"]) or auto_human:
		return false
	return net == "" or int(p["slot"]) == net_me


## 이 PC 사람의 자리 (오프라인이면 첫 번째 사람)
func local_slot() -> int:
	if net != "":
		return net_me
	for p in players:
		if not bool(p["cpu"]):
			return int(p["slot"])
	return -1


# ── 온라인 (방장이 게임을 진행하고, 손님은 조작을 보내고 결과를 받아 보여줌) ─────────
## net: "" 오프라인 · "host" 방장 · "client" 손님
var net := ""
var net_me := 0
var net_seed := 0
var _net_acc := 0.0
var _net_done := false
var _net_rank: Array = []
const NET_DT := 1.0 / 15.0


func net_setup(mode: String, me: int) -> void:
	net = mode
	net_me = me
	if mode != "":
		Net.message.connect(_on_net_msg)


func is_client() -> bool:
	return net == "client"


## 방장(또는 혼자)만 정하고, 모두가 같은 걸 실행 (적 생성 · 맞음 · 점수 등)
func net_call(method: String, args: Array = []) -> void:
	if net == "client":
		return
	callv(method, args)
	if net == "host":
		Net.broadcast({"k": "mg_e", "m": method, "v": Marshalls.variant_to_base64(args)})


## 방장: 손님들에게만 알림 (방장 쪽은 직접 await 하며 실행할 때)
func net_tell(method: String, args: Array = []) -> void:
	if net == "host":
		Net.broadcast({"k": "mg_e", "m": method, "v": Marshalls.variant_to_base64(args)})


## 내 조작 → 방장 (혼자 · 방장이면 바로)
func net_input(action: String, args: Array = []) -> void:
	if net == "client":
		Net.to_host({"k": "mg_i", "a": action, "v": Marshalls.variant_to_base64(args)})
	else:
		_net_input(local_slot(), action, args)


## 게임마다: 조작 처리 (방장 PC 에서 그 자리 사람의 조작으로)
func _net_input(_slot: int, _action: String, _args: Array) -> void:
	pass


## 게임마다: 방장이 손님에게 보낼 상태 / 손님이 받은 상태 적용
func _net_state() -> Dictionary:
	return {}


func _net_apply(_s: Dictionary) -> void:
	pass


## 3D 공통(걷는 말 등)이 덧붙이는 상태
func _net_state_common() -> Dictionary:
	return {}


func _net_apply_common(_s: Dictionary) -> void:
	pass


func _peer_slot(peer: int) -> int:
	for p in players:
		if int(GameState.players[int(p["slot"])].get("peer", -999)) == peer:
			return int(p["slot"])
	return -1


var _dbg_n := 0


func _on_net_msg(from: int, d: Dictionary) -> void:
	if OS.get_environment("NET_DEBUG") != "" and _dbg_n < 40:
		_dbg_n += 1
		print("NETDBG ", net, " got ", d.get("k"), " ", d.get("m", ""), " inside=", is_inside_tree())
	if not is_inside_tree():
		return
	match String(d.get("k", "")):
		"mg_e":
			if net == "client":
				var m := String(d.get("m", ""))
				var args = Marshalls.base64_to_variant(String(d.get("v", "")))
				if has_method(m) and typeof(args) == TYPE_ARRAY:
					callv(m, args)
		"mg_s":
			if net == "client":
				var st = Marshalls.base64_to_variant(String(d.get("v", "")))
				if typeof(st) == TYPE_DICTIONARY:
					time_left = float(st.get("tl", time_left))
					var sc: Dictionary = st.get("sc", {})
					for k in sc:
						scores[int(k)] = sc[k]
					_net_apply_common(st)
					_net_apply(st)
		"mg_i":
			if net == "host":
				var slot := _peer_slot(from)
				var args = Marshalls.base64_to_variant(String(d.get("v", "")))
				if slot >= 0 and typeof(args) == TYPE_ARRAY:
					_net_input(slot, String(d.get("a", "")), args)
		"mg_end":
			if net == "client":
				_net_rank = d.get("r", [])
				_net_done = true


func _net_send_state() -> void:
	var st := {"tl": time_left, "sc": scores}
	st.merge(_net_state_common(), true)
	st.merge(_net_state(), true)
	Net.broadcast({"k": "mg_s", "v": Marshalls.variant_to_base64(st)})


func hint(name_: String) -> void:
	if not demo and _hint_cb.is_valid():
		_hint_cb.call(name_)


func _ready() -> void:
	rng.randomize()
	if net_seed != 0:
		rng.seed = net_seed   # 온라인: 모두 같은 무대 (조개 색 등)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	PirateFonts.style_theme(th)
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	theme = th
	_make_stage()
	arena = Control.new()
	arena.size = ARENA
	arena.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(arena)
	_fit_arena()
	get_viewport().size_changed.connect(_fit_arena)
	_setup_game()
	_build_hud()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


## 배경 (3D 미니게임은 덮어써서 3D 무대를 깔아요)
func _make_stage() -> void:
	var bg := BackgroundScene.instantiate()
	if "show_seabed" in bg:
		bg.show_seabed = false
	add_child(bg)


func _fit_arena() -> void:
	var v := get_viewport().get_visible_rect().size
	var s := minf(v.x / ARENA.x, v.y / ARENA.y)
	arena.scale = Vector2.ONE * s
	arena.position = (v - ARENA * s) * 0.5


## 효과음 (미리보기에선 조용히)
func sfx(name_: String, min_interval: float = 0.0) -> void:
	if not demo:
		Audio.play(name_, min_interval)


## 미리보기: 소개 없이 바로 플레이, 끝나면 demo_done
func run_demo() -> void:
	demo = true
	auto_human = true
	if duration < 100.0:
		duration = minf(duration, 12.0)
	time_left = duration
	playing = true
	_start_game()
	while not _is_done():
		await get_tree().process_frame
	playing = false
	await get_tree().create_timer(1.2, false).timeout
	demo_done.emit()


## 처음부터 끝까지 (await 하면 순위가 나옴). 소개는 미니게임 소개 화면이 따로 해요
func run() -> Array:
	await _countdown()
	time_left = duration
	playing = true
	_start_game()
	var r: Array
	if net == "client":
		while not _net_done:
			await get_tree().process_frame
		r = []
		for sl in _net_rank:
			var p := player_by_slot(int(sl))
			if not p.is_empty():
				r.append(p)
	else:
		while not _is_done():
			await get_tree().process_frame
		r = _ranking()
		if net == "host":
			_net_send_state()
			Net.broadcast({"k": "mg_end", "r": r.map(func(p: Dictionary) -> int: return int(p["slot"]))})
	playing = false
	sfx("start")
	await _big_text("FINISH!", 1.2)
	finished.emit(r)
	return r


func _process(delta: float) -> void:
	if playing:
		time_left = maxf(0.0, time_left - delta)
		_tick(delta)
		if net == "host":
			_net_acc += delta
			if _net_acc >= NET_DT:
				_net_acc = 0.0
				_net_send_state()
	if _timer_label:
		_timer_label.text = str(ceili(time_left)) if show_timer and (playing or time_left > 0.0) else ""
	for p in players:
		var l: Label = _chips.get(int(p["slot"]))
		if l:
			l.text = _score_text(p)


# ── 상속해서 채울 것 ──────────────────────────────────────────
func _setup_game() -> void:
	pass


func _start_game() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _is_done() -> bool:
	return time_left <= 0.0


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()   # 동점이면 무작위
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(scores[int(a["slot"])]) > float(scores[int(b["slot"])]))
	return order


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))


# ── 화면 공통 ────────────────────────────────────────────────
func _build_hud() -> void:
	_hud = HBoxContainer.new()
	_hud.add_theme_constant_override("separation", 12)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.position.y = 24
	for p in players:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", _glass(Color(0.02, 0.15, 0.14, 0.75), Color(p["color"], 0.8) if is_local(p) else Color(AQUA, 0.2), 2 if is_local(p) else 1, 26))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		chip.add_child(h)
		h.add_child(dot(p["color"], 22))
		var n := Label.new()
		n.text = p["name"]
		n.add_theme_font_size_override("font_size", 19)
		h.add_child(n)
		var s := Label.new()
		s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		s.add_theme_font_size_override("font_size", 22)
		s.add_theme_color_override("font_color", GOLD)
		s.custom_minimum_size = Vector2(44, 0)
		h.add_child(s)
		_chips[int(p["slot"])] = s
		_hud.add_child(chip)
	_timer_label = outlined("", 64)
	_timer_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-150, 14)
	_timer_label.size = Vector2(120, 80)
	add_child(_timer_label)


func _glass(bg: Color, border: Color, bw: int, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(12)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.anti_aliasing = true
	return s


func dot(c: Color, px: int) -> Panel:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(px, px)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(px / 2)
	d.add_theme_stylebox_override("panel", st)
	return d


func outlined(text: String, size_: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", maxi(8, size_ / 4))
	return l


## 화면 가운데 큰 글씨
func _big_text(text: String, hold: float, col: Color = PEARL) -> void:
	var l := outlined(text, 120)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = tr(text)
	l.add_theme_color_override("font_color", col)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(l)
	l.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	l.scale = Vector2.ONE * 0.4
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(hold)
	t.tween_property(l, "modulate:a", 0.0, 0.2)
	await t.finished
	l.queue_free()


func _countdown() -> void:
	for k in ["3", "2", "1"]:
		Audio.play("tick")
		await _big_text(k, 0.45)
	Audio.play("start")
	_big_text(tr("GAME START!"), 0.45, GOLD)
	hint("51_mg_%s_play" % name.to_snake_case())


## 점수 등이 떠오르는 글씨 (arena 좌표)
func float_text(at: Vector2, text: String, col: Color, size_: int = 40) -> void:
	var l := outlined(text, size_)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_color_override("font_color", col)
	l.size = Vector2(240, 60)
	l.position = at - l.size * 0.5
	arena.add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 70.0, 0.7).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.3)
	t.tween_callback(l.queue_free)


func player_by_slot(slot: int) -> Dictionary:
	for p in players:
		if int(p["slot"]) == slot:
			return p
	return {}


## 지금 난이도 (0 ~ 1): 판이 진행될수록 가파르게 올라 마지막엔 1 (진짜 어려움).
## 보드 후반(heat)이면 시작부터 조금 높음
func pressure() -> float:
	var f := clampf(1.0 - time_left / maxf(duration, 0.01), 0.0, 1.0)
	var base := heat * 0.3
	return clampf(base + (1.0 - base) * pow(f, 1.7), 0.0, 1.0)


## CPU 실력 (0 쉬움 ~ 2 어려움). 자동 점검 중인 사람은 보통
func skill(p: Dictionary) -> float:
	if not bool(p["cpu"]):
		return 1.0
	return float(GameState.players[int(p["slot"])].get("level", 1))
