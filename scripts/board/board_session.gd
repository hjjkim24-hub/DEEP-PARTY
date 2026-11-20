extends Node3D
## 보드 위 게임 진행 공통 부분 (튜토리얼 보드와 진짜 게임이 같이 씀).
##   - 3D 보드 세상, 말, 카메라 (차례인 말을 가까이 따라감)
##   - 차례: 주사위 → 이동 (갈림길 고르기, START 보너스, 트로피 칸은 지나가도 멈춰서 물어봄) → 칸 효과
##   - 규칙: 동전 · 트로피 (숫자는 scripts/board/rules.gd), 찬스 카드, 상점, 미니게임(지금은 임시 순위)
##   - 화면: 이름표(동전·트로피), 칸 안내판, 주사위 버튼, 갈림길 화살표, 물어보는 창, 결과 화면
## 상속: scripts/tutorial_board.gd (튜토리얼), scripts/board_game.gd (진짜 게임)

const Rules := preload("res://scripts/board/rules.gd")
const Minigames := preload("res://scripts/minigames/registry.gd")
const BoardWorld := preload("res://scripts/world3d/board_world.gd")
const Pawn3D := preload("res://scripts/world3d/pawn3d.gd")
const Dice3D := preload("res://scripts/world3d/dice3d.gd")
const TutorialOverlay := preload("res://scripts/ui/tutorial_overlay.gd")
const PathArrow := preload("res://scripts/ui/path_arrow.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const MinigameIntro := preload("res://scripts/minigames/minigame_intro.gd")
const PirateFonts := preload("res://scripts/ui/pirate_fonts.gd")
const CARD_TEX := preload("res://textures/tiles/card_chance.png")
const COIN_TEX := preload("res://textures/ui/coin.png")
const TROPHY_TEX := preload("res://textures/ui/trophy.png")
const HEART_TEX := preload("res://textures/ui/coop/heart.png")
const HEART_EMPTY_TEX := preload("res://textures/ui/coop/heart_empty.png")
const POTION_TEX := preload("res://textures/ui/coop/potion.png")
const SHIELD_TEX := preload("res://textures/ui/coop/shield.png")
## 아이템 사진 (tools/render_item_icons.gd 로 3D 모델을 찍은 것)
const ITEM_TEX := {
	"potion": preload("res://textures/ui/items/potion.png"),
	"shield": preload("res://textures/ui/items/shield.png"),
	"dice": preload("res://textures/ui/items/dice.png"),
	"scroll": preload("res://textures/ui/items/scroll.png"),
	"conch": preload("res://textures/ui/items/conch.png"),
	"oxygen": preload("res://textures/ui/items/oxygen.png"),
	"net": preload("res://textures/ui/items/net.png"),
}
const GOLD := Color("ffcf4a")
const DICE_ATLAS := preload("res://textures/dice/dice_atlas.png")
const SHOP_TEX := {
	"wall": preload("res://textures/ui/shop/wall.png"),
	"awning": preload("res://textures/ui/shop/awning.png"),
	"counter": preload("res://textures/ui/shop/counter.png"),
	"slot": preload("res://textures/ui/shop/slot.png"),
	"sign": preload("res://textures/ui/shop/sign.png"),
	"tag": preload("res://textures/ui/shop/tag.png"),
	"shutter": preload("res://textures/ui/shop/shutter.png"),
	"button": preload("res://textures/ui/shop/button.png"),
	"awning_shadow": preload("res://textures/ui/shop/awning_shadow.png"),
	"lantern": preload("res://textures/ui/shop/lantern.png"),
	"glow": preload("res://textures/ui/shop/glow.png"),
}
const MAIN_MENU := "res://scenes/main_menu.tscn"

const PEARL := Color("eafffa")
const AQUA := Color("7ff0db")
const DEEP := Color("05302c")
const PAWN_SCALE := 1.7            ## 말 키 (미터)
const CLOSE := Vector3(0, 3.4, 6.2)   ## 말 가까이 볼 때 카메라 위치 (말 기준)
const ZOOM_MIN := 0.55
const ZOOM_MAX := 4.5
const TILE_ZOOM := 1.15            ## 칸을 강조할 때 늘 같은 거리 (칸 크기가 화면에서 늘 같게)
const DICE_H := 3.4                ## 말 위 주사위 높이
const HOP_TIME := 0.3

var world: BoardWorld
var _pawns: Array = []        ## {slot, name, color, cpu, team, node, spot, tile, prev, chip, coins, trophies}
var _camera: Camera3D
var _focus := Vector3.ZERO    ## 카메라가 바라보는 점
var _zoom := 1.0              ## 1 = 가까이, 클수록 멀리
var _cine := 0.0              ## 0..1: 연출용 카메라(_cine_xf)로 넘어간 정도
var _cine_xf := Transform3D()
var _follow: Node3D = null    ## 이 말을 카메라가 따라감
var _cam_tween: Tween
var _ui: CanvasLayer
var _root: Control
var _chips: HBoxContainer
var _my_pawn_btn: Button
var _start_marker: Control
var _screen_marker: Control
var _legend: PanelContainer
var _overlay
var _pause: Control
var _fade: ColorRect
var _title: Label
var _intro_done := false
var _focused := false
var _dragging := false

# 차례 진행 상태
var _dice: Dice3D
var _dice_btn: Button
var _click_hint: Label
var _steps_label: Label
var _turn_pawn: Dictionary = {}
var _awaiting_roll := false
var _dice_hit := false
var _last_roll := 0
var _steps_left := 0
var _choosing := false
var _choice := -1
var _forced_next := -1
var _arrows: Array = []
var _landed := false
var _shop_open := false
var _shop_panel: Control
var _shop_close: Button
var _shop_buy: Button
var _shop_buys: Array = []
var _popup_root: Control

# 규칙 상태
var _rng := RandomNumberGenerator.new()
var _round := 0
var _round_label: Label
var _game_over := false
var _winner: Dictionary = {}
var _trophy_next_round := Rules.TROPHY_FIRST_ROUND
var _tile_mods := {}          ## 칸 → "coin_plus" / "coin_minus" (찬스 카드로 바뀐 칸)
var _legend_box: VBoxContainer
var _dialog_open := false
var _dialog_buttons: Array = []
var _dialog_panel: Control
var _dialog_choice := -1
var _picking_tile := false
var _pick_allowed: Array = []   ## 비어 있지 않으면 이 칸들만 고를 수 있음 (덫 해체)
var _picked_tile := -1
var _hover_tile := -1
var _pick_marker: MeshInstance3D
var _tile_catcher: Control

# 튜토리얼·점검용으로 결과를 미리 정해 둘 수 있음
var rig_ranking: Array = []   ## 다음 미니게임 순위 (pawn 목록)
var rig_card := ""            ## 다음 찬스 카드 id
var shop_price_mult := 1      ## 상점 가격 배수 (크라켄이 상점을 습격하면 2)
var rig_minigame := ""        ## 다음 미니게임 id ("" = 랜덤)
var rig_chest := -1           ## 개발용: 크라켄의 보물상자 결과 (1 = 보물, 0 = 크라켄, -1 = 확률대로)
var force_shop_stock: Array = []   ## 점검 · 촬영용: 다음 상점 진열을 이걸로
var force_shop_trophy := -1   ## 1 = 다음 상점에 트로피 꼭 진열, 0 = 꼭 안 함, -1 = 확률대로
var force_trophy_buy := false ## 튜토리얼: 트로피 살지 물을 때 BUY 만 누를 수 있게
var shot_hint := ""           ## 자동 스크린샷용: 지금 보여 주는 장면 이름


func _ready() -> void:
	_rng.randomize()
	_aux_rng.randomize()
	_online = Net.is_online() and GameState.board_online
	if _online:
		_rng.seed = GameState.board_seed   # 모두 같은 씨앗 → 같은 주사위 · 크라켄 · 카드
		Net.message.connect(_on_board_net)
		Net.peer_left.connect(_on_board_peer_left)
		Net.room_closed.connect(_on_board_lost.bind("The host closed the room."))
		Net.disconnected.connect(_on_board_lost.bind("Lost connection to the server."))
	world = BoardWorld.new()
	world.map_id = map_id()
	add_child(world)
	_setup_pawns()
	_dice = Dice3D.new()
	add_child(_dice)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 400.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 22.0
	attrs.dof_blur_far_transition = 18.0
	attrs.dof_blur_amount = 0.05
	_camera.attributes = attrs
	add_child(_camera)
	_camera.make_current()
	_build_ui()
	_intro()


func _setup_pawns() -> void:
	var list := []
	var cpu_no := 0
	for slot in 4:
		var p: Dictionary = GameState.players[slot]
		if p.is_empty():
			continue
		var pname := "You"
		var cpu := false
		match p.get("kind", ""):
			"cpu":
				cpu_no += 1
				pname = tr("CPU %d") % cpu_no
				cpu = true
			"host":
				if slot != GameState.my_slot:
					pname = "Host"
			"friend":
				if slot != GameState.my_slot:
					pname = tr("Player %d") % (slot + 1)
		list.append({"slot": slot, "name": pname, "cpu": cpu, "color": GameState.player_color(slot), "look": GameState.look(slot)})
	if list.is_empty():
		list.append({"slot": 0, "name": "You", "cpu": false, "color": GameState.PALETTE[0], "look": {}})
	for d in list:
		d["coins"] = Rules.START_COINS
		d["trophies"] = 0
		d["hearts"] = Rules.HEARTS_START
		d["shield"] = 0
		d["items"] = []
		if OS.is_debug_build() and OS.get_environment("BOARD_TEST_ITEMS") != "":
			d["items"] = Array(OS.get_environment("BOARD_TEST_ITEMS").split(","))
		d["alive"] = true
		d["team"] = ("A" if int(d["slot"]) < 2 else "B") if _team_mode() else ""
	var spots: Array = world.start_spots(list.size())
	for i in list.size():
		var d: Dictionary = list[i]
		var node := Pawn3D.new()
		node.color = d["color"]
		node.look = d["look"]
		node.scale = Vector3.ONE * PAWN_SCALE
		node.visible = false
		add_child(node)
		node.position = spots[i]
		node.rotation.y = 0.0   # 말 앞쪽(+Z)이 카메라(남쪽)를 보게
		d["node"] = node
		d["spot"] = spots[i]
		d["tile"] = world.start_index
		d["prev"] = -1
		d["start_i"] = i
		_pawns.append(d)


func _team_mode() -> bool:
	return GameState.selected_mode == GameState.Mode.TEAM_2V2


## 크라켄 생존전인지 (게임이 덮어씀). 트로피 대신 하트
func survival() -> bool:
	return false


## 이름표 · 결과에 보이는 두 숫자
func _stat_keys() -> Array:
	return ["coins", "hearts"] if survival() else ["coins", "trophies"]


func _stat_tex(key: String) -> Texture2D:
	match key:
		"coins":
			return COIN_TEX
		"hearts":
			return HEART_TEX
	return TROPHY_TEX


func _alive_pawns() -> Array:
	return _pawns.filter(func(q: Dictionary) -> bool: return bool(q.get("alive", true)))


## 사람 대신 알아서 하는 말인지 (CPU, 또는 자동 점검 중인 내 말)
func _is_auto(p: Dictionary) -> bool:
	match _ctl(p):
		"cpu", "proxy":
			return true
		"me":
			return GameState.debug_autoplay
	return false


# ── 온라인 보드 (방 코드) ─────────────────────────────────────
## 모든 PC 가 같은 씨앗으로 같은 판을 진행하고, 사람이 고른 것(주사위 · 갈림길 · 대답 · 상점 · 칸 고르기)만
## 서로 주고받음. 차례가 끝날 때마다 방장이 상태를 보내 혹시 어긋난 걸 맞춤.
var _online := false
var _aux_rng := RandomNumberGenerator.new()   ## 내 말 자동 진행(점검용)에만 · 모두와 같은 _rng 를 건드리지 않게
var _dec_q := {}            ## slot → [받은 결정 …]
var _departed := {}         ## 방장: 나간 친구 slot → true (방장이 대신 정해서 보냄)
var _sync_n := 0
var _sync_got := {}         ## n → 상태 (손님)
var _acks := {}             ## n → {peer: true} (방장)


## 이 말을 누가 움직이나: "cpu" 모두가 같은 _rng 로 · "me" 이 PC 사람 · "proxy" 방장이 나간 친구 대신 · "remote" 다른 PC 사람
func _ctl(p: Dictionary) -> String:
	if bool(p["cpu"]):
		return "cpu"
	if not _online:
		return "me"
	if int(p["slot"]) == GameState.my_slot:
		return "me"
	if Net.is_host() and _departed.has(int(p["slot"])):
		return "proxy"
	return "remote"


func _is_remote(p: Dictionary) -> bool:
	return _ctl(p) == "remote"


## 사람 말을 자동으로 정할 때는 다른 _rng 를 써서 모두의 _rng 순서가 어긋나지 않게
func _use_aux(p: Dictionary) -> RandomNumberGenerator:
	var keep := _rng
	if _online and not bool(p["cpu"]):
		_rng = _aux_rng
	return keep


## 내가(또는 방장이 대신) 고른 것을 모두에게
func _put_dec(p: Dictionary, v: Variant) -> void:
	if _online and _ctl(p) in ["me", "proxy"]:
		Net.broadcast({"k": "bd", "s": int(p["slot"]), "v": Marshalls.variant_to_base64(v)})


## 다른 PC 사람이 고를 때까지 기다림
func _get_dec(p: Dictionary) -> Variant:
	var s := int(p["slot"])
	_waiting_label(p, true)
	while (not _dec_q.has(s) or (_dec_q[s] as Array).is_empty()) and is_inside_tree():
		await get_tree().process_frame
	_waiting_label(p, false)
	return (_dec_q[s] as Array).pop_front()


var _wait_lbl: Label


func _waiting_label(p: Dictionary, on: bool) -> void:
	if on:
		if _wait_lbl == null:
			_wait_lbl = _outlined_label("", 28)
			_wait_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_wait_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			_wait_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_wait_lbl.position.y -= 150
			_root.add_child(_wait_lbl)
		_wait_lbl.text = tr("%s is choosing…") % tr(String(p["name"]))
		_wait_lbl.visible = true
	elif _wait_lbl:
		_wait_lbl.visible = false


func _on_board_net(from: int, d: Dictionary) -> void:
	match String(d.get("k", "")):
		"bd":
			var s := int(d.get("s", -1))
			var v = Marshalls.base64_to_variant(String(d.get("v", "")))
			if not _dec_q.has(s):
				_dec_q[s] = []
			(_dec_q[s] as Array).append(v)
		"bd_sync":
			_sync_got[int(d.get("n", 0))] = Marshalls.base64_to_variant(String(d.get("st", "")))
		"bd_ack":
			var n := int(d.get("n", 0))
			if not _acks.has(n):
				_acks[n] = {}
			_acks[n][from] = true
		"bd_exit":
			if Net.is_guest():
				_exit_to_menu(true)


## 차례가 끝날 때: 방장이 상태를 보내고 손님들이 받을 때까지 기다림 (서로 너무 앞서가지 않게 + 어긋남 보정)
func _net_sync() -> void:
	if not _online:
		return
	_sync_n += 1
	var n := _sync_n
	if Net.is_host():
		var st := {"pawns": {}, "departed": _departed.keys()}
		for q in _pawns:
			st["pawns"][int(q["slot"])] = [int(q["tile"]), int(q["coins"]), int(q["trophies"]), int(q.get("hearts", 0)), int(q.get("shield", 0)), bool(q.get("alive", true))]
		Net.broadcast({"k": "bd_sync", "n": n, "st": Marshalls.variant_to_base64(st)})
		var t0 := Time.get_ticks_msec()
		while is_inside_tree() and Time.get_ticks_msec() - t0 < 15000:
			var got: Dictionary = _acks.get(n, {})
			var all := true
			for peer in Net.peers:
				if not got.has(peer):
					all = false
			if all:
				break
			await get_tree().process_frame
		_acks.erase(n)
	else:
		var t0 := Time.get_ticks_msec()
		while is_inside_tree() and not _sync_got.has(n) and Time.get_ticks_msec() - t0 < 60000:
			await get_tree().process_frame
		var st = _sync_got.get(n)
		_sync_got.erase(n)
		if typeof(st) == TYPE_DICTIONARY:
			_apply_sync(st)
		Net.to_host({"k": "bd_ack", "n": n})


func _apply_sync(st: Dictionary) -> void:
	var ps: Dictionary = st.get("pawns", {})
	for q in _pawns:
		var v: Array = ps.get(int(q["slot"]), [])
		if v.size() < 6:
			continue
		var mine := [int(q["tile"]), int(q["coins"]), int(q["trophies"]), int(q.get("hearts", 0)), int(q.get("shield", 0)), bool(q.get("alive", true))]
		if OS.is_debug_build() and OS.get_environment("BOARD_NET_DEBUG") != "":
			print("BSYNC %d slot %d %s %s" % [_sync_n, q["slot"], "OK" if mine == v else "MISMATCH", str(mine) + " vs " + str(v)])
		if int(q["tile"]) != int(v[0]):
			push_warning("online board: tile mismatch for slot %d (%d vs %d) — corrected" % [q["slot"], q["tile"], v[0]])
			q["tile"] = int(v[0])
			(q["node"] as Node3D).position = _spot_on(int(v[0]), q)
		q["coins"] = int(v[1])
		q["trophies"] = int(v[2])
		q["hearts"] = int(v[3])
		q["shield"] = int(v[4])
		q["alive"] = bool(v[5])
		_refresh_chip(q)


## 방장: 친구가 나가면 그 말은 방장이 대신 (자동으로) 진행
func _on_board_peer_left(id: int) -> void:
	if not Net.is_host():
		return
	for q in _pawns:
		if int(GameState.players[int(q["slot"])].get("peer", -999)) == id:
			_departed[int(q["slot"])] = true


func _on_board_lost(msg: String) -> void:
	if not _online:
		return
	if Net.is_host():
		_online = false
		return
	_online = false
	var me := {"kind": "host", "color": 0}
	if not GameState.my_profile.is_empty():
		me.merge(GameState.my_profile, true)
		me["kind"] = "host"
	GameState.players = [me, {}, {}, {}]
	GameState.my_slot = 0
	GameState.return_to = "toast:" + msg
	_exit_to_menu(true)


## 왼쪽 위 나가기 버튼 글씨 (상속해서 바꿈)
func exit_label() -> String:
	return "EXIT TUTORIAL"


## 보드 제목 (상속해서 바꿈)
func board_title() -> String:
	return "TUTORIAL BOARD"


func _my_pawn() -> Dictionary:
	for p in _pawns:
		if int(p["slot"]) == GameState.my_slot:
			return p
	return _pawns[0]


# ── 카메라 ───────────────────────────────────────────────────
func _apply_camera() -> void:
	# 멀어질수록 더 위에서 내려다보게 (아주 멀면 보드판 전체가 보임)
	var off := Vector3(0, CLOSE.y * _zoom * (1.0 + 0.35 * maxf(_zoom - 1.0, 0.0)), CLOSE.z * _zoom)
	_camera.position = _focus + off
	_camera.look_at(_focus + Vector3(0, 0.9, 0), Vector3.UP)
	if _cine > 0.001:
		_camera.transform = _camera.transform.interpolate_with(_cine_xf, _cine)
	var attrs := _camera.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = lerpf(off.length() + 7.0 + _zoom * 4.0, 400.0, _cine)


func _process(delta: float) -> void:
	if _follow and is_instance_valid(_follow):
		_focus = _focus.lerp(_follow.position, 1.0 - exp(-delta * 7.0))
	_apply_camera()
	# 튜토리얼이 가리킬 START 광장 화면 위치
	var top: Vector3 = world.spaces[world.start_index]["pos"]
	var r := Rect2()
	var first := true
	for c in [Vector3(-3.6, 0, -3.6), Vector3(3.6, 0, -3.6), Vector3(-3.6, 0, 3.6), Vector3(3.6, 0, 3.6), Vector3(0, 2.4, 0)]:
		var wp: Vector3 = top + c
		if _camera.is_position_behind(wp):
			continue
		var sp := _camera.unproject_position(wp)
		if first:
			r = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			r = r.expand(sp)
	_start_marker.position = r.position
	_start_marker.size = r.size
	var v := get_viewport().get_visible_rect().size
	_screen_marker.position = Vector2(60, 110)
	_screen_marker.size = v - Vector2(120, 220)
	_update_play_ui()


## 연출 카메라: from 에서 at 을 바라보게 부드럽게 넘어감 (to = 1) / 돌아옴 (to = 0)
func _cinematic(from: Vector3, at: Vector3, to: float, time: float) -> void:
	if to > 0.0:
		_cine_xf = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	create_tween().tween_property(self, "_cine", to, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _move_camera(focus: Vector3, zoom: float, time: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(self, "_focus", focus, time)
	_cam_tween.tween_property(self, "_zoom", zoom, time)


## 이 말을 가까이 보기 (차례마다 부름)
func focus_on(p: Dictionary, time: float = 0.9) -> void:
	_follow = null
	_move_camera((p["node"] as Node3D).position, 1.0, time)


func _focus_my_pawn() -> void:
	focus_on(_my_pawn())
	_focused = true


func _open_pause() -> void:
	if _pause and not _pause.is_open():
		_pause.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_open_pause()
		return
	if not _intro_done:
		return
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if _cam_tween:
				_cam_tween.kill()
			_zoom = clampf(_zoom * (0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), ZOOM_MIN, world.zoom_max)
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		if _cam_tween:
			_cam_tween.kill()
		_follow = null
		var k := 0.02 * _zoom
		_focus += Vector3(-mm.relative.x * k, 0, -mm.relative.y * k)
		_focus.x = clampf(_focus.x, world.view_center.x - world.half_w, world.view_center.x + world.half_w)
		_focus.z = clampf(_focus.z, world.view_center.z - world.half_d, world.view_center.z + world.half_d)


# ── 화면 UI ──────────────────────────────────────────────────
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	PirateFonts.style_theme(th)
	th.default_font_size = 24
	th.set_color("font_color", "Label", PEARL)
	root.theme = th
	_ui.add_child(root)
	_root = root
	PirateFonts.watch(self)    # 큰 글씨는 해적 깃발 글씨로

	_start_marker = Control.new()
	_start_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_start_marker)
	_screen_marker = Control.new()
	_screen_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_screen_marker)

	# 주사위 누르는 곳 (주사위 위에 투명하게 겹쳐 둠)
	_dice_btn = Button.new()
	_dice_btn.flat = true
	_dice_btn.focus_mode = Control.FOCUS_NONE
	_dice_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_dice_btn.set_meta("sfx", "tick")
	_dice_btn.pressed.connect(_hit_dice)
	_dice_btn.visible = false
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		_dice_btn.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	root.add_child(_dice_btn)
	_click_hint = _outlined_label("CLICK!", 30)
	_click_hint.visible = false
	root.add_child(_click_hint)
	# [아이템 사용]: 내 차례 · 주사위 굴리기 전에만 보임 (화면 아래 가운데)
	_item_btn = _glass_button("USE ITEM")
	_item_btn.custom_minimum_size = Vector2(230, 60)
	_item_btn.visible = false
	root.add_child(_item_btn)
	_item_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 36)
	_item_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_item_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_item_btn.pressed.connect(func() -> void:
		if _awaiting_roll and not _turn_pawn.is_empty():
			_open_bag(_turn_pawn))
	_steps_label = _outlined_label("", 64)
	_steps_label.visible = false
	root.add_child(_steps_label)

	_legend = _build_legend()
	root.add_child(_legend)
	_legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 30)
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend.visible = false

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 10)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chips)
	_chips.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_chips.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chips.position.y = 30
	for p in _pawns:
		var chip := _make_chip(p)
		p["chip"] = chip
		_chips.add_child(chip)

	# 왼쪽 위: 메뉴 (ESC 와 같음)
	var menu_btn := _glass_button("MENU")
	menu_btn.custom_minimum_size = Vector2(130, 0)
	menu_btn.pressed.connect(_open_pause)
	root.add_child(menu_btn)
	menu_btn.position = Vector2(30, 30)
	var pl := CanvasLayer.new()
	pl.layer = 50
	pl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pl)
	_pause = PauseMenu.new()
	pl.add_child(_pause)
	_pause.set_leave_text(exit_label())
	_pause.leave_requested.connect(_exit_to_menu)
	_round_label = _outlined_label("", 26)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_round_label.position = Vector2(34, 92)
	_round_label.visible = false
	root.add_child(_round_label)

	_my_pawn_btn = _glass_button("MY PAWN")
	_my_pawn_btn.custom_minimum_size = Vector2(180, 60)
	_my_pawn_btn.pressed.connect(_focus_my_pawn)
	root.add_child(_my_pawn_btn)
	_my_pawn_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)
	_my_pawn_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_my_pawn_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_my_pawn_btn.visible = false

	_popup_root = Control.new()
	_popup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popup_root)

	_title = Label.new()
	_title.text = board_title()
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_outline_color", DEEP)
	_title.add_theme_constant_override("outline_size", 18)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.position.y = 110
	_title.modulate.a = 0.0
	root.add_child(_title)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _outlined_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", maxi(8, font_size / 4))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _glass(bg: Color, border: Color, bw: int, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.anti_aliasing = true
	return s


func _glass_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", _glass(Color(0.02, 0.17, 0.16, 0.7), Color(AQUA, 0.3), 1))
	b.add_theme_stylebox_override("hover", _glass(Color(0.08, 0.4, 0.36, 0.75), Color(AQUA, 0.6), 1))
	b.add_theme_stylebox_override("pressed", _glass(Color(0.03, 0.26, 0.24, 0.8), AQUA, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## 왼쪽 아래 칸 종류 안내판
func _build_legend() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := _glass(Color(0.02, 0.15, 0.14, 0.72), Color(AQUA, 0.25), 1, 14)
	st.content_margin_left = 16
	st.content_margin_right = 18
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	_legend_box = v
	var head := Label.new()
	head.text = "SPACES"
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", AQUA)
	v.add_child(head)
	for kind in BoardWorld.KIND_ORDER:
		_legend_row(v, kind)
	if not world.spaces_of_kind("harpoon").is_empty():
		_legend_row(v, "harpoon")
	return panel


func _legend_row(v: VBoxContainer, kind: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + kind
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(_kind_swatch(kind, 30))
	var l := Label.new()
	l.text = BoardWorld.KIND_NAMES[kind]
	l.add_theme_font_size_override("font_size", 17)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)


## +5 / -5 칸이 처음 생기면 안내판에도 한 줄 추가
func _legend_add(kind: String) -> void:
	if _legend_box and not _legend_box.has_node("Row_" + kind):
		_legend_row(_legend_box, kind)


func _kind_swatch(kind: String, px: int) -> Panel:
	var sw := Panel.new()
	sw.custom_minimum_size = Vector2(px, px)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = BoardWorld.TILE_COLORS[kind]
	ss.border_color = Color(0.95, 0.95, 0.9)
	ss.set_border_width_all(2)
	ss.set_corner_radius_all(int(px * 0.2))
	sw.add_theme_stylebox_override("panel", ss)
	var ic := TextureRect.new()
	ic.texture = BoardWorld.ICONS[kind]
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = px * 0.16
	ic.offset_top = px * 0.16
	ic.offset_right = -px * 0.16
	ic.offset_bottom = -px * 0.16
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_child(ic)
	return sw


func _make_chip(p: Dictionary) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _glass(Color(0.02, 0.15, 0.14, 0.7), Color(AQUA, 0.2), 1, 30))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	chip.add_child(h)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ds := StyleBoxFlat.new()
	ds.bg_color = p["color"]
	ds.set_corner_radius_all(11)
	dot.add_theme_stylebox_override("panel", ds)
	h.add_child(dot)
	if String(p["team"]) != "":
		var tl := Label.new()
		tl.text = String(p["team"])
		tl.add_theme_font_size_override("font_size", 15)
		tl.add_theme_color_override("font_color", AQUA)
		h.add_child(tl)
	var l := Label.new()
	l.text = p["name"]
	l.add_theme_font_size_override("font_size", 19)
	h.add_child(l)
	for k in _stat_keys():
		var ic := TextureRect.new()
		ic.texture = _stat_tex(k)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(24, 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var n := Label.new()
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.add_theme_font_size_override("font_size", 19)
		n.add_theme_color_override("font_color", GOLD)
		n.custom_minimum_size = Vector2(26, 0)
		h.add_child(n)
		p[k + "_label"] = n
	# 방패 (생존전: 있을 때만 보임)
	var sh := TextureRect.new()
	sh.texture = SHIELD_TEX
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sh.custom_minimum_size = Vector2(24, 24)
	sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.visible = false
	h.add_child(sh)
	p["shield_icon"] = sh
	# 가방 (들고 있는 아이템 사진 · 최대 3)
	var bag := HBoxContainer.new()
	bag.add_theme_constant_override("separation", 2)
	bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in Rules.BAG_SIZE:
		var it := TextureRect.new()
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.custom_minimum_size = Vector2(26, 26)
		it.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		it.visible = false
		bag.add_child(it)
	h.add_child(bag)
	p["bag_box"] = bag
	_refresh_chip(p)
	return chip


func _refresh_chip(p: Dictionary) -> void:
	for k in _stat_keys():
		if p.has(k + "_label"):
			(p[k + "_label"] as Label).text = str(p[k])
	if p.has("shield_icon"):
		(p["shield_icon"] as Control).visible = int(p.get("shield", 0)) > 0
	if p.has("bag_box"):
		var items: Array = p.get("items", [])
		var bag: Node = p["bag_box"]
		for k in bag.get_child_count():
			var it := bag.get_child(k) as TextureRect
			it.visible = k < items.size()
			if k < items.size():
				it.texture = ITEM_TEX.get(String(items[k]))
	if p.has("chip") and not bool(p.get("alive", true)):
		(p["chip"] as Control).modulate = Color(0.55, 0.45, 0.5, 0.75)


## 지금 차례인 사람 이름표만 또렷하게
func _highlight_chip(p: Dictionary) -> void:
	for q in _pawns:
		var chip: PanelContainer = q["chip"]
		var on: bool = q == p
		chip.modulate = Color(1, 1, 1, 1.0 if on or p.is_empty() else 0.45)
		if not bool(q.get("alive", true)):
			chip.modulate = Color(0.55, 0.45, 0.5, 0.6)
		chip.add_theme_stylebox_override("panel", _glass(Color(0.04, 0.3, 0.27, 0.85) if on else Color(0.02, 0.15, 0.14, 0.7),
			Color(AQUA, 0.9 if on else 0.2), 2 if on else 1, 30))


# ── 매 프레임: 주사위 버튼 · 남은 칸 숫자 · 갈림길 화살표 위치 ─────────
func _update_play_ui() -> void:
	if _dice.visible:
		var r: Rect2 = _dice.screen_rect(_camera).grow(18.0)
		_dice_btn.position = r.position
		_dice_btn.size = r.size
		_click_hint.position = Vector2(r.get_center().x - _click_hint.size.x * 0.5, r.position.y - 46.0 + sin(Time.get_ticks_msec() * 0.008) * 6.0)
	_dice_btn.visible = _awaiting_roll and not _bag_open
	_click_hint.visible = _awaiting_roll and not _bag_open
	if _item_btn:
		var n_items := (_turn_pawn.get("items", []) as Array).size() if not _turn_pawn.is_empty() else 0
		_item_btn.visible = _awaiting_roll and not _bag_open
		_item_btn.disabled = n_items == 0
		_item_btn.text = tr("USE ITEM") + " (%d)" % n_items
	if _steps_label.visible and not _turn_pawn.is_empty():
		var wp: Vector3 = (_turn_pawn["node"] as Node3D).position + Vector3(0, 3.0, 0)
		if not _camera.is_position_behind(wp):
			var sp := _camera.unproject_position(wp)
			_steps_label.position = sp - _steps_label.size * 0.5
	for btn in _arrows:
		var t: int = btn.tile
		var from: Vector3 = world.spaces[int(_turn_pawn["tile"])]["pos"]
		var to: Vector3 = world.spaces[t]["pos"]
		var dir := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
		var at := from + dir * 1.9 + Vector3(0, 0.35, 0)
		if _camera.is_position_behind(at):
			continue
		var s0 := _camera.unproject_position(at)
		var s1 := _camera.unproject_position(at + dir)
		btn.angle = (s1 - s0).angle()
		btn.position = s0 - btn.size * 0.5


# ── 차례 진행 ────────────────────────────────────────────────
## 한 사람 차례: 주사위 → 이동(갈림길 고르기) → 칸에 멈춤. 칸 효과는 _tile_effect 로 따로.
## rig > 0 이면 그 숫자가 나오고, forced = {칸: 다음 칸} 이면 갈림길에서 그쪽만 고를 수 있음 (튜토리얼용)
func _play_turn(p: Dictionary, rig: int = 0, forced: Dictionary = {}) -> void:
	_turn_pawn = p
	_landed = false
	_dice_hit = false
	_highlight_chip(p)
	await _turn_banner(p)
	var node: Node3D = p["node"]
	# 말과 머리 위 주사위가 같이 잘 보이게
	_follow = null
	_move_camera(node.position + Vector3(0, 1.3, 0), 1.25, 0.8)
	await get_tree().create_timer(0.85, false).timeout
	_dice.show_at(node.position + Vector3(0, DICE_H, 0))
	# 주사위 굴리기 전: 아이템을 쓸 수 있음 (순간이동서를 쓰면 이번 차례는 이동으로 끝)
	if _is_remote(p):
		while true:
			var d = await _get_dec(p)
			if typeof(d) == TYPE_STRING and String(d).begins_with("item:"):
				if await _use_item(p, int(String(d).substr(5))):
					_dice.hide_dice()
					_landed = true
					return
				await _back_to_dice(p)
				continue
			break
		_dice_hit = true
	elif _is_auto(p):
		await get_tree().create_timer(1.0, false).timeout
		while true:
			var keep := _use_aux(p)
			var k := _cpu_pick_item(p)
			_rng = keep
			if k < 0:
				break
			_put_dec(p, "item:%d" % k)
			if await _use_item(p, k):
				_dice.hide_dice()
				_landed = true
				return
			await _back_to_dice(p)
		_dice_hit = true
		_put_dec(p, "roll")
	else:
		_item_req = -1
		_awaiting_roll = true
		while not _dice_hit:
			if _item_req >= 0:
				var k := _item_req
				_item_req = -1
				_awaiting_roll = false
				_put_dec(p, "item:%d" % k)
				if await _use_item(p, k):
					_dice.hide_dice()
					_landed = true
					return
				await _back_to_dice(p)
				_awaiting_roll = true
			await get_tree().process_frame
		_awaiting_roll = false
		_put_dec(p, "roll")
	# 그물에 걸렸으면 이번 주사위는 1~3 만
	var netted := bool(p.get("netted", false))
	var n: int = rig if rig > 0 else (_rng.randi_range(1, 3) if netted else _rng.randi_range(1, 6))
	Audio.play("dice_shake")
	_pawn_bump(node)
	await _dice.roll_to(n)
	Audio.play("dice_land")
	if netted:
		_free_net(p)
	# 추가 주사위 (1~3) 를 한 번 더 굴려 더함
	if bool(p.get("extra_die", false)):
		p.erase("extra_die")
		_steps_label.text = str(n)
		_steps_label.visible = true
		_pop(_steps_label)
		await get_tree().create_timer(0.5, false).timeout
		var m := _rng.randi_range(1, 3)
		Audio.play("dice_shake")
		await _dice.roll_to(m)
		Audio.play("dice_land")
		_float_text(p, "+%d" % m, GOLD, ITEM_TEX["dice"])
		n += m
	_last_roll = n
	_steps_left = n
	_steps_label.text = str(n)
	_steps_label.visible = true
	_pop(_steps_label)
	await get_tree().create_timer(0.45, false).timeout
	_dice.hide_dice()
	_follow = node
	while _steps_left > 0 and not _game_over:
		var opts := _next_options(p)
		var nxt: int = opts[0]
		if opts.size() > 1:
			if _is_remote(p):
				nxt = int(await _get_dec(p))
			elif _is_auto(p):
				await get_tree().create_timer(0.5, false).timeout
				var keep := _use_aux(p)
				nxt = _cpu_pick_path(p, opts)
				_rng = keep
				_put_dec(p, nxt)
			else:
				nxt = await _choose(p, opts, int(forced.get(int(p["tile"]), -1)))
				_put_dec(p, nxt)
		await _hop(p, nxt)
		_steps_left -= 1
		_steps_label.text = str(_steps_left)
		_pop(_steps_label)
		if nxt == world.start_index:
			_add_coins(p, Rules.START_BONUS)
		# 트로피 칸: 지나가기만 해도 멈춰서 살지 물어봄 → 남은 칸 계속
		if nxt == world.trophy_tile:
			_steps_label.visible = false
			await _offer_trophy(p)
			if _steps_left > 0 and not _game_over:
				_steps_label.visible = true
				_follow = node
	await get_tree().create_timer(0.2, false).timeout
	_steps_label.visible = false
	Audio.play("add")
	world.bubbles_at(node.position + Vector3(0, 0.2, 0), 12, 0.5, true)
	_landed = true


# ── 아이템 (상점에서 사서 가방에) ──────────────────────────────
var _item_req := -1          ## 가방 창에서 [사용] 을 누른 아이템 번호 (내 차례 주사위 전)
var _item_btn: Button
var _bag_open := false


## 한국어가 글자 중간에서 줄바뀌지 않게: 띄어쓰기 사이 글자들을 '단어 이음표(U+2060)'로 묶음
static func _keep_words(t: String) -> String:
	var out := ""
	for i in t.length():
		out += t[i]
		if i + 1 < t.length() and t[i] != " " and t[i + 1] != " " and t[i] != "\n" and t[i + 1] != "\n":
			out += char(0x2060)
	return out


## 아이템을 쓴 뒤 다시 주사위 앞으로
func _back_to_dice(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	_follow = null
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.5)
	_move_camera(node.position + Vector3(0, 1.3, 0), 1.25, 0.6)
	await get_tree().create_timer(0.6, false).timeout
	_dice.show_at(node.position + Vector3(0, DICE_H, 0))


func _item_usable(p: Dictionary, id: String) -> bool:
	match id:
		"potion":
			return int(p["hearts"]) < Rules.HEARTS_MAX
		"shield":
			return int(p.get("shield", 0)) <= 0
		"dice":
			return not bool(p.get("extra_die", false))
		"oxygen":
			return false
		"net":
			return not _others(p).is_empty()
	return true


## CPU: 쓸 아이템 고르기 (없으면 -1)
func _cpu_pick_item(p: Dictionary) -> int:
	var items: Array = p.get("items", [])
	for k in items.size():
		var id := String(items[k])
		if not _item_usable(p, id):
			continue
		match id:
			"potion":
				if int(p["hearts"]) <= Rules.HEARTS_MAX - 2:
					return k
			"shield":
				if int(p["hearts"]) <= 3:
					return k
			"net":
				return k
			"conch":
				for t in _traps:
					if int(_traps[t]) != int(p["slot"]):
						return k
			"dice":
				if _rng.randf() < 0.5:
					return k
	return -1


## CPU: 상점에서 살 것 (앞에서부터 돈 · 가방이 되는 만큼)
func _cpu_shop_wants(p: Dictionary) -> Array:
	var out := []
	var items: Array = p.get("items", [])
	if int(p["hearts"]) <= Rules.HEARTS_MAX - 2:
		out.append("potion")
	if int(p.get("shield", 0)) <= 0 and not "shield" in items:
		out.append("shield")
	if int(p["coins"]) >= 28 and not "oxygen" in items:
		out.append("oxygen")
	if _rng.randf() < 0.4:
		out.append("net")
	if _rng.randf() < 0.3:
		out.append("dice")
	if _rng.randf() < 0.15:
		out.append("conch")
	return out


## 아이템 사용 → 이번 차례가 끝나면(순간이동) true
func _use_item(p: Dictionary, k: int) -> bool:
	var items: Array = p.get("items", [])
	if k < 0 or k >= items.size():
		return false
	var id := String(items[k])
	items.remove_at(k)
	_refresh_chip(p)
	_dice.hide_dice()
	await _item_pop(p, id)
	match id:
		"potion":
			Audio.play("bubbles")
			await _heal(p, 1)
		"shield":
			p["shield"] = 1
			_refresh_chip(p)
			Audio.play("equip")
			world.bubbles_at((p["node"] as Node3D).position + Vector3(0, 1.0, 0), 18, 0.6, true)
			_float_text(p, tr("SHIELD UP!"), Color("bfe9ff"), ITEM_TEX["shield"])
			await get_tree().create_timer(0.7, false).timeout
		"dice":
			p["extra_die"] = true
			_float_text(p, "+1~3", GOLD, ITEM_TEX["dice"])
			await get_tree().create_timer(0.6, false).timeout
		"scroll":
			var t: int = await _pick_tile(p, tr("Pick a space to teleport to!"))
			if t >= 0 and t != int(p["tile"]):
				await _warp_to(p, t)
			return true
		"conch":
			await _conch(p)
		"net":
			await _throw_net(p)
	return false


## 쓴 아이템이 말 머리 위로 떠올랐다 사라짐 (진짜 3D 모델)
func _item_pop(p: Dictionary, id: String) -> void:
	var node: Node3D = p["node"]
	var m := ItemModels.make(id)
	m.scale = Vector3.ONE * 0.05
	add_child(m)
	var base := node.position + Vector3(0, 2.3, 0)
	m.position = base
	_follow = null
	_move_camera(node.position + Vector3(0, 1.6, 0), 1.0, 0.5)
	var t := create_tween()
	t.tween_property(m, "scale", Vector3.ONE * 0.85, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(m, "rotation:y", TAU * 0.75, 1.2).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(m, "position:y", base.y + 0.35, 1.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(m, "scale", Vector3.ONE * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(m.queue_free)
	Audio.play("equip")
	await get_tree().create_timer(1.25, false).timeout


## 덫 탐지 소라: 숨겨진 덫이 보이고 하나를 골라 해체 (쓴 사람 화면에만 덫 위치 표시)
func _conch(p: Dictionary) -> void:
	var found := []
	for t in _traps:
		if int(_traps[t]) != int(p["slot"]):
			found.append(int(t))
	Audio.play("aura")
	if found.is_empty():
		await _banner(tr("NO TRAPS FOUND"), "", 0.9)
		return
	var mine := _ctl(p) == "me"
	if mine:
		for t in found:
			if not _trap_marks.has(t):
				var mk := Sprite3D.new()
				mk.texture = BoardWorld.ICONS["trap"]
				mk.pixel_size = 0.006
				mk.modulate = Color(1.0, 0.4, 0.3, 0.85)
				mk.axis = Vector3.AXIS_Y
				mk.position = (world.spaces[t]["pos"] as Vector3) + Vector3(0, 0.03, 0)
				add_child(mk)
				_trap_marks[t] = mk
	_pick_allowed = found
	var pick: int = await _pick_tile(p, tr("Pick a trap to disarm!"), found[0], "49_pick_disarm", true)
	_pick_allowed = []
	if _traps.has(pick):
		_traps.erase(pick)
		if _trap_marks.has(pick):
			(_trap_marks[pick] as Node).queue_free()
			_trap_marks.erase(pick)
		Audio.play("snap")
		if mine:
			_float_text(p, tr("DISARMED!"), Color("bfe9ff"), BoardWorld.ICONS["trap"])
		await get_tree().create_timer(0.6, false).timeout


## 그물: 상대를 골라 던짐 → 그물이 덮여 다음 주사위는 1~3
func _throw_net(p: Dictionary) -> void:
	var cands := _others(p)
	if cands.is_empty():
		return
	var target: Dictionary = await _pick_player(p, cands, tr("Pick a player to catch in the net!"), "hearts")
	var pnode: Node3D = p["node"]
	var tnode: Node3D = target["node"]
	var a := pnode.position + Vector3(0, 1.4, 0)
	var b := tnode.position + Vector3(0, 0.05, 0)
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	var mid := a.lerp(b, 0.5)
	_follow = null
	_cinematic(mid + side * (4.0 + span * 0.6) - dir * (1.0 + span * 0.1) + Vector3(0, 2.4 + span * 0.2, 0), mid, 1.0, 0.6)
	await get_tree().create_timer(0.6, false).timeout
	var net := ItemModels.spread_net(0.9, 1.6)
	net.position = a
	net.scale = Vector3(0.25, 0.25, 0.25)
	add_child(net)
	Audio.play("whoosh")
	var fly := clampf(span / 16.0, 0.5, 1.1)
	var ft := create_tween()
	ft.tween_method(func(f: float) -> void:
		net.position = a.lerp(b + Vector3(0, 0.3, 0), f) + Vector3(0, sin(f * PI) * (1.0 + span * 0.08), 0)
		net.rotation.y = f * TAU * 1.5
		net.scale = Vector3.ONE * lerpf(0.25, 1.0, f), 0.0, 1.0, fly).set_trans(Tween.TRANS_SINE)
	await ft.finished
	shot_hint = "68_net"
	Audio.play("splash")
	var dt := create_tween()
	dt.tween_property(net, "position", b, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dt.parallel().tween_property(net, "scale", Vector3(1.05, 0.9, 1.05), 0.18)
	await dt.finished
	_squash(tnode)
	target["netted"] = true
	target["net_node"] = net
	_float_text(target, tr("NET!"), Color("ffe08a"), ITEM_TEX["net"])
	await get_tree().create_timer(0.9, false).timeout
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.6)


func _free_net(p: Dictionary) -> void:
	p.erase("netted")
	var net = p.get("net_node")
	p.erase("net_node")
	if net is Node3D and is_instance_valid(net):
		var t := create_tween()
		t.tween_property(net, "scale", Vector3.ONE * 0.05, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_callback(net.queue_free)


## [아이템 사용] → 가방 창: 아이템을 고르고 [사용]
func _open_bag(p: Dictionary) -> void:
	if _bag_open:
		return
	_bag_open = true
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(GOLD, 0.8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var title := Label.new()
	title.text = "BAG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	v.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var desc := Label.new()
	desc.text = tr("Pick an item")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(600, 56)
	desc.add_theme_font_size_override("font_size", 19)
	v.add_child(desc)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 20)
	v.add_child(btns)
	var use := _glass_button("USE")
	use.disabled = true
	use.custom_minimum_size = Vector2(180, 56)
	btns.add_child(use)
	var close := _glass_button("CLOSE")
	close.custom_minimum_size = Vector2(180, 56)
	close.set_meta("sfx", "back")
	btns.add_child(close)
	var sel := [-1]
	var cells := []
	var items: Array = p.get("items", [])
	for k in Rules.BAG_SIZE:
		var cell := Button.new()
		cell.toggle_mode = true
		cell.focus_mode = Control.FOCUS_NONE
		cell.custom_minimum_size = Vector2(190, 210)
		cell.add_theme_stylebox_override("normal", _glass(Color(0.02, 0.12, 0.11, 0.85), Color(AQUA, 0.25), 2, 18))
		cell.add_theme_stylebox_override("hover", _glass(Color(0.04, 0.2, 0.18, 0.9), Color(AQUA, 0.6), 2, 18))
		cell.add_theme_stylebox_override("pressed", _glass(Color(0.08, 0.28, 0.22, 0.95), Color(GOLD, 1.0), 4, 18))
		cell.add_theme_stylebox_override("disabled", _glass(Color(0.02, 0.08, 0.08, 0.6), Color(AQUA, 0.1), 1, 18))
		row.add_child(cell)
		cells.append(cell)
		var cv := VBoxContainer.new()
		cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cv)
		if k >= items.size():
			cell.disabled = true
			var e := Label.new()
			e.text = "EMPTY"
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			cv.add_child(e)
			continue
		var id := String(items[k])
		var ic := _icon(ITEM_TEX[id], 130)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(ic)
		var nm := Label.new()
		nm.text = String(Rules.ITEMS[id]["title"])
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(180, 0)
		nm.add_theme_font_size_override("font_size", 16)
		cv.add_child(nm)
		var kk := k
		cell.pressed.connect(func() -> void:
			sel[0] = kk
			for c in cells.size():
				(cells[c] as Button).set_pressed_no_signal(c == kk)
			var ok := _item_usable(p, id)
			use.disabled = not ok
			var why := ""
			if not ok:
				why = "\n" + tr("Works automatically") if id == "oxygen" else "\n" + tr("Can't use it now")
			desc.text = _keep_words(tr(String(Rules.ITEMS[id]["text"]))) + why)
	var done := func() -> void:
		_bag_open = false
		var t := create_tween()
		t.tween_property(dim, "modulate:a", 0.0, 0.2)
		t.tween_callback(dim.queue_free)
	close.pressed.connect(done)
	use.pressed.connect(func() -> void:
		if sel[0] >= 0:
			_item_req = sel[0]
		done.call())
	shot_hint = "69_bag"
	await _show_modal(panel)


## CPU 갈림길: 트로피가 있으면 대개 트로피 쪽으로. 그 밖엔 남은 걸음으로 멈출 칸을 내다보고
## 크라켄이 노린 붉은 칸 · 독가시 칸 (하트가 1 개면 크라켄의 보물상자도)을 피함, 비슷하면 아무 데나
func _cpu_pick_path(p: Dictionary, opts: Array) -> int:
	if world.trophy_tile >= 0 and _rng.randf() < 0.75:
		var best: int = opts[0]
		var bd := 999
		for o in opts:
			var d := _distance(int(o), int(p["tile"]), world.trophy_tile)
			if d < bd:
				bd = d
				best = int(o)
		return best
	var pick: int = opts[0]
	var low := INF
	for o in opts:
		var r := _cpu_risk(p, int(o)) + _rng.randf() * 0.5
		if r < low:
			low = r
			pick = int(o)
	return pick


## 이 길(first)로 가면 멈출 칸이 얼마나 위험한지 (갈림길에선 첫 길로 간다고 보고 내다봄)
func _cpu_risk(p: Dictionary, first: int) -> float:
	var prev: int = p["tile"]
	var cur := first
	for k in maxi(_steps_left - 1, 0):
		var nxt := -1
		for l in world.spaces[cur]["links"]:
			if int(l) != prev:
				nxt = int(l)
				break
		if nxt < 0:
			nxt = prev
		prev = cur
		cur = nxt
	var risk := 0.0
	if world.danger_tiles().has(cur):
		risk += 10.0
	if String(_tile_mods.get(cur, "")) == "urchin":
		risk += 8.0
	var kind := String(world.spaces[cur]["kind"])
	if kind == "kraken_chest" and int(p.get("hearts", 3)) <= 1:
		risk += 5.0
	if kind == "shop" and int(p.get("hearts", 3)) < Rules.HEARTS_MAX and int(p["coins"]) >= Rules.POTION_PRICE * shop_price_mult:
		risk -= 2.0
	return risk


## from 칸에서(직전 칸 prev 로 되돌아가지 않고) target 까지 칸 수
func _distance(from: int, prev: int, target: int) -> int:
	var queue := [[from, prev, 0]]
	var seen := {}
	while queue.size() > 0:
		var it: Array = queue.pop_front()
		if int(it[0]) == target:
			return int(it[2])
		var key := "%d_%d" % [it[0], it[1]]
		if seen.has(key) or int(it[2]) > 40:
			continue
		seen[key] = true
		var links: Array = world.spaces[int(it[0])]["links"]
		for l in links:
			if int(l) == int(it[1]) and links.size() > 1:
				continue
			queue.append([int(l), int(it[0]), int(it[2]) + 1])
	return 999


func _next_options(p: Dictionary) -> Array:
	var links: Array = world.spaces[int(p["tile"])]["links"]
	var out := []
	for l in links:
		if int(l) != int(p["prev"]):
			out.append(int(l))
	if out.is_empty():
		out = links.duplicate()
	return out


## 갈림길: 화살표를 띄우고 고를 때까지 기다림 → 고른 칸 번호
func _choose(p: Dictionary, opts: Array, forced: int) -> int:
	_choice = -1
	_forced_next = forced
	_follow = null
	_move_camera((p["node"] as Node3D).position, 1.25, 0.5)
	for t in opts:
		var a := PathArrow.new()
		a.tile = int(t)
		a.locked = forced >= 0 and int(t) != forced
		a.pressed.connect(func() -> void: _choice = a.tile)
		_root.add_child(a)
		_arrows.append(a)
	_choosing = true
	while _choice < 0:
		await get_tree().process_frame
	_choosing = false
	for a in _arrows:
		(a as Node).queue_free()
	_arrows.clear()
	_follow = p["node"]
	return _choice


func _forced_arrow() -> Control:
	for a in _arrows:
		if not a.locked:
			return a
	return _arrows[0] if _arrows.size() > 0 else null


func _pick_forced() -> void:
	var a := _forced_arrow()
	if a:
		_choice = a.tile


func _hit_dice() -> void:
	if _awaiting_roll:
		_dice_hit = true


## 칸 위에 서는 자리 (여럿이 같은 칸이면 살짝 비켜 섬)
func _spot_on(tile: int, p: Dictionary) -> Vector3:
	var top: Vector3 = world.spaces[tile]["pos"]
	if tile == world.start_index:
		return world.start_spots(_pawns.size())[int(p["start_i"])]
	var offs := [Vector3.ZERO, Vector3(0.6, 0, 0.35), Vector3(-0.6, 0, 0.35), Vector3(0, 0, -0.55)]
	var k := 0
	for q in _pawns:
		if q != p and int(q["tile"]) == tile and bool(q.get("alive", true)):
			k += 1
	return top + offs[k % offs.size()]


func _hop(p: Dictionary, nxt: int) -> void:
	var node: Node3D = p["node"]
	var from := node.position
	var to := _spot_on(nxt, p)
	p["prev"] = p["tile"]
	p["tile"] = nxt
	var dy := to.y - from.y
	var t := create_tween()
	if absf(dy) > 4.0:
		# 줄사다리 오르내리기 (크라켄의 배 돛대 망대): 천천히, 좌우로 살짝 흔들리며
		var dur := 0.35 + absf(dy) * 0.045
		t.tween_method(func(f: float) -> void:
			var e := f * f * (3.0 - 2.0 * f)
			node.position = from.lerp(to, e) + Vector3(0, sin(f * PI) * 0.6, 0) + Vector3(sin(f * TAU * 3.0) * 0.12, 0, 0), 0.0, 1.0, dur)
	else:
		var lift := 0.9 + maxf(0.0, dy)
		t.tween_method(func(f: float) -> void: node.position = from.lerp(to, f) + Vector3(0, sin(f * PI) * lift, 0), 0.0, 1.0, HOP_TIME)
	await t.finished
	Audio.play("tick")
	_squash(node)


func _squash(node: Node3D) -> void:
	var t := create_tween()
	t.tween_property(node, "scale", Vector3(1.15, 0.82, 1.15) * PAWN_SCALE, 0.07)
	t.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE, 0.16).set_trans(Tween.TRANS_BACK)


func _pawn_bump(node: Node3D) -> void:
	var y := node.position.y
	var t := create_tween()
	t.tween_property(node, "position:y", y + 0.9, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "position:y", y, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _pop(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var t := create_tween()
	t.tween_property(c, "scale", Vector2.ONE * 1.3, 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _turn_banner(p: Dictionary) -> void:
	var mine := not bool(p["cpu"]) and int(p["slot"]) == GameState.my_slot
	var text := tr("YOUR TURN!") if mine else tr("%s'S TURN!") % tr(String(p["name"]))
	await _banner(text, "", 1.0)


## 화면 가운데 큰 글씨 (뿅 나타났다 사라짐)
func _banner(text: String, sub: String, hold: float) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_popup_root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := _outlined_label(text, 76)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(l)
	if sub != "":
		var s := _outlined_label(sub, 28)
		box.add_child(s)
	box.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	box.scale = Vector2.ONE * 0.3
	box.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(box, "modulate:a", 1.0, 0.15)
	t.tween_interval(hold)
	t.tween_property(box, "modulate:a", 0.0, 0.25)
	await t.finished
	box.queue_free()


# ── 동전 · 트로피 ───────────────────────────────────────────
func _add_coins(p: Dictionary, n: int) -> void:
	var before: int = p["coins"]
	p["coins"] = maxi(0, before + n)
	var d: int = int(p["coins"]) - before
	_refresh_chip(p)
	_pop(p["chip"])
	if d > 0:
		Audio.play("add")
		_float_text(p, "+%d" % d, GOLD, COIN_TEX)
	elif d < 0:
		Audio.play("remove")
		_float_text(p, "%d" % d, Color("ff6b6b"), COIN_TEX)


func _add_trophy(p: Dictionary, n: int) -> void:
	p["trophies"] = maxi(0, int(p["trophies"]) + n)
	_refresh_chip(p)
	_pop(p["chip"])
	if n > 0:
		Audio.play("start")
		_float_text(p, "+%d" % n, GOLD, TROPHY_TEX)
		_check_win(p)
	elif n < 0:
		Audio.play("remove")
		_float_text(p, "%d" % n, Color("ff6b6b"), TROPHY_TEX)


## 2대2는 팀원 둘 합계
func _team_trophies(p: Dictionary) -> int:
	if String(p["team"]) == "":
		return int(p["trophies"])
	var t := 0
	for q in _pawns:
		if q["team"] == p["team"]:
			t += int(q["trophies"])
	return t


func _check_win(p: Dictionary) -> void:
	if _team_trophies(p) >= Rules.TROPHIES_TO_WIN:
		_game_over = true
		_winner = p


## 말 머리 위로 떠오르는 +5 같은 글씨
func _float_text(p: Dictionary, text: String, col: Color, icon: Texture2D) -> void:
	var node: Node3D = p["node"]
	var wp := node.position + Vector3(0, 2.6, 0)
	if _camera.is_position_behind(wp):
		return
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var ic := TextureRect.new()
	ic.texture = icon
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.custom_minimum_size = Vector2(38, 38)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(ic)
	var l := _outlined_label(text, 40)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	box.visible = false
	_popup_root.add_child(box)
	await get_tree().process_frame
	if not is_instance_valid(box):
		return
	var sp := _camera.unproject_position(wp)
	box.position = sp - box.size * 0.5
	box.visible = true
	var t := create_tween()
	t.tween_property(box, "position:y", box.position.y - 70.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(box, "modulate:a", 0.0, 0.5).set_delay(0.6)
	await t.finished
	box.queue_free()


## 트로피 칸: 멈춰서 살지 물어봄
func _offer_trophy(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	_follow = null
	_move_camera(node.position + Vector3(0, 1.0, 0), 1.15, 0.5)
	await get_tree().create_timer(0.55, false).timeout
	if int(p["coins"]) < Rules.TROPHY_PRICE:
		shot_hint = "41_trophy_poor"
		await _banner(tr("A TROPHY!"), tr("You need %d coins to buy it.") % Rules.TROPHY_PRICE, 1.1)
		return
	shot_hint = "41_trophy_offer"
	var c: int = await _ask(p, tr("A TROPHY!"), tr("Buy a trophy for %d coins?") % Rules.TROPHY_PRICE,
		[tr("BUY"), tr("NO THANKS")], 0, TROPHY_TEX, [1] if force_trophy_buy else [])
	if c == 0:
		_add_coins(p, -Rules.TROPHY_PRICE)
		world.hide_trophy()
		_trophy_next_round = _round + Rules.TROPHY_RESPAWN_ROUNDS
		_add_trophy(p, 1)
		await _banner(tr("+1 TROPHY!"), "", 0.7)


## 트로피를 랜덤 칸에 띄움 (진짜 게임에서 라운드 시작 때)
func _spawn_trophy() -> void:
	var pool := []
	for i in world.regular_tiles():
		if _tile_mods.has(i):
			continue
		var taken := false
		for q in _pawns:
			if int(q["tile"]) == i:
				taken = true
		if not taken:
			pool.append(i)
	if pool.is_empty():
		return
	var t: int = pool[_rng.randi() % pool.size()]
	_follow = null
	_move_camera(world.spaces[t]["pos"], 1.6, 1.1)
	await get_tree().create_timer(1.15, false).timeout
	world.show_trophy(t)
	Audio.play("start")
	shot_hint = "40_trophy_spawn"
	await _banner(tr("A TROPHY APPEARED!"), "", 1.2)


# ── 칸 효과 ──────────────────────────────────────────────────
func _tile_effect(p: Dictionary) -> void:
	var tile: int = p["tile"]
	if _traps.has(tile) and int(_traps[tile]) != int(p["slot"]):
		await _spring_trap(p, tile)
		return
	if _tile_mods.get(tile, "") == "urchin":
		await _urchin_trap(p)
		return
	if _tile_mods.has(tile):
		var plus: bool = _tile_mods[tile] == "coin_plus"
		Audio.play("toast")
		_add_coins(p, Rules.COIN_SPACE_AMOUNT if plus else -Rules.COIN_SPACE_AMOUNT)
		await _banner(tr("LUCKY!") if plus else tr("OUCH!"), "", 0.6)
		return
	match String(world.spaces[tile]["kind"]):
		"portal":
			await _warp(p)
		"minigame":
			await _run_minigame(p, false)
		"chance":
			await _draw_card(p)
		"shop":
			await _open_shop(p)
		"kraken_chest":
			await _kraken_chest(p)
		"cannon":
			await _cannon(p)
		"harpoon":
			await _harpoon(p)
		"eel":
			await _eel(p)
		_:
			await get_tree().create_timer(0.3, false).timeout


## 작살: 다른 사람을 골라 작살을 쏨 → 맞으면 하트 -1 (방패가 막음 · 하트가 없는 판이면 동전 -5)
## 작살 칸이면 옆의 작살포가 돌아가 쏘고, 작살 카드면 내 말이 직접 던짐
func _harpoon(p: Dictionary, thrown: bool = false) -> void:
	var cands := _others(p)
	if cands.is_empty():
		return
	var target: Dictionary = await _pick_player(p, cands, tr("Pick a player to harpoon!"), "hearts" if survival() else "coins")
	var tile := int(p["tile"])
	var gun := not thrown and world.harpoon_guns.has(tile)
	var pnode: Node3D = p["node"]
	var tnode: Node3D = target["node"]
	var src: Vector3 = (world.harpoon_guns[tile]["muzzle"] as Node3D).global_position if gun else pnode.position + Vector3(0, 1.1, 0)
	var tpos := tnode.position + Vector3(0, 0.75, 0)
	var dir := Vector3(tpos.x - src.x, 0, tpos.z - src.z).normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	# 옆에서 쏘는 쪽과 맞는 쪽이 한 화면에 다 들어오게 (날아가는 길 전체가 보임)
	var span := Vector2(tpos.x - src.x, tpos.z - src.z).length()
	var mid := src.lerp(tpos, 0.5)
	var eye := mid + side * (4.0 + span * 0.62) - dir * (1.0 + span * 0.12) + Vector3(0, 2.6 + span * 0.22, 0)
	_follow = null
	_cinematic(eye, mid + Vector3(0, 0.4, 0), 1.0, 0.75)
	await get_tree().create_timer(0.8, false).timeout
	shot_hint = "64a_harpoon_aim"
	if gun:
		src = await world.harpoon_aim(tile, tpos)
		await get_tree().create_timer(0.25, false).timeout
		world.harpoon_fired(tile)
		Audio.play("cannon")
		_shake_camera(0.3, 0.25)
	else:
		# 내 말이 상대 쪽으로 돌아서 몸을 뒤로 젖혔다가 휙 던짐
		var face := atan2(dir.x, dir.z)
		var wt := create_tween()
		wt.tween_property(pnode, "rotation:y", pnode.rotation.y + angle_difference(pnode.rotation.y, face), 0.25)
		wt.tween_property(pnode, "rotation:x", -0.35, 0.22)
		wt.tween_property(pnode, "rotation:x", 0.25, 0.08)
		wt.tween_property(pnode, "rotation:x", 0.0, 0.3)
		await get_tree().create_timer(0.5, false).timeout
		src = pnode.position + Vector3(0, 1.2, 0) + dir * 0.4
	Audio.play("whoosh")
	# 날아가는 작살 + 뒤에 끌려가는 밧줄
	var hp := world.harpoon_mesh(1.9)
	add_child(hp)
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.032
	rm.bottom_radius = 0.032
	rm.height = 1.0
	rm.radial_segments = 6
	rope.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.86, 0.76, 0.55)
	rmat.roughness = 0.95
	rope.material_override = rmat
	add_child(rope)
	var dist := src.distance_to(tpos)
	var fly := clampf(dist / 32.0, 0.3, 0.8)
	var apex := 0.3 + dist * 0.035
	var place := func(f: float) -> void:
		var pos := src.lerp(tpos, f) + Vector3(0, sin(f * PI) * apex, 0)
		var vel := (tpos - src) + Vector3(0, cos(f * PI) * PI * apex, 0)
		if vel.length() > 0.01:
			hp.global_transform = Transform3D(Basis.looking_at(-vel.normalized(), Vector3.UP), pos)
		var tail := pos - vel.normalized() * 1.1
		var rv := tail - src
		var rl := maxf(rv.length(), 0.01)
		rope.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, rv / rl)) * Basis.from_scale(Vector3(1, rl, 1)), src + rv * 0.5)
	place.call(0.0)
	var ft := create_tween()
	ft.tween_method(place, 0.0, 1.0, fly)
	await ft.finished
	shot_hint = "64b_harpoon_hit"
	Audio.play("thud")
	Audio.play("splash")
	_shake_camera(0.45, 0.25)
	# 맞은 말: 뒤로 휘청
	var base := _spot_on(int(target["tile"]), target)
	var hop := create_tween()
	hop.tween_property(tnode, "position", base + dir * 0.6 + Vector3(0, 0.5, 0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.parallel().tween_property(tnode, "rotation:x", 0.5, 0.16)
	hop.tween_property(tnode, "position", base, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.parallel().tween_property(tnode, "rotation:x", 0.0, 0.35)
	# 작살은 땅에 비스듬히 꽂힘
	var stuck := Transform3D(Basis.looking_at(-(dir + Vector3(0, -0.7, 0)).normalized(), Vector3.UP), base + dir * 0.9 + Vector3(0, 0.35, 0))
	create_tween().tween_property(hp, "global_transform", stuck, 0.12)
	await hop.finished
	_squash(tnode)
	if survival():
		await _damage(target, 1)
	else:
		_add_coins(target, -Rules.CANNON_COINS)
		await get_tree().create_timer(0.8, false).timeout
	# 밧줄을 감아 작살을 회수
	var tail0 := hp.global_position
	var reel := create_tween()
	reel.tween_method(func(f: float) -> void:
		var pos := tail0.lerp(src, f)
		hp.global_position = pos
		var rv := pos - src
		var rl := maxf(rv.length(), 0.01)
		rope.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, rv / rl if rl > 0.02 else Vector3.UP)) * Basis.from_scale(Vector3(1, rl, 1)), src + rv * 0.5), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await reel.finished
	hp.queue_free()
	rope.queue_free()
	if gun:
		world.harpoon_reload(tile)
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.8)
	await get_tree().create_timer(0.5, false).timeout


# ── 곰덫 카드 ─────────────────────────────────────────────
var _traps := {}        ## 칸 → 놓은 사람 slot (놓은 사람은 걸리지 않음)
var _trap_marks := {}   ## 칸 → 표시 (덫을 놓은 사람의 화면에만)


func _set_trap(p: Dictionary) -> void:
	# CPU: 하트가 가장 많은 상대가 지나갈 앞길 3 칸째
	var auto_t := -1
	var best: Dictionary = {}
	for q in _others(p):
		if best.is_empty() or int(q["hearts"]) > int(best["hearts"]):
			best = q
	if not best.is_empty():
		auto_t = int(best["tile"])
		for k in 3:
			var nx: Array = world.spaces[auto_t]["next"]
			if nx.is_empty():
				break
			auto_t = int(nx[0])
	var t: int = await _pick_tile(p, tr("Pick a space to hide the trap!"), auto_t, "48_pick_trap", true)
	if t < 0:
		return
	_traps[t] = int(p["slot"])
	# 덫 놓은 사람 화면에만 흐릿한 덫 표시
	if not bool(p["cpu"]) and int(p["slot"]) == GameState.my_slot:
		var mk := Sprite3D.new()
		mk.texture = BoardWorld.ICONS["trap"]
		mk.pixel_size = 0.006
		mk.modulate = Color(1.0, 0.55, 0.45, 0.75)
		mk.axis = Vector3.AXIS_Y
		mk.position = (world.spaces[t]["pos"] as Vector3) + Vector3(0, 0.03, 0)
		add_child(mk)
		_trap_marks[t] = mk
	Audio.play("snap")
	await get_tree().create_timer(0.4, false).timeout


## 덫에 걸림: 쇠 이빨이 철컥 → 하트 -1 + 다음 차례 쉼 (쉬는 동안 덫에 물려 있음)
func _spring_trap(p: Dictionary, tile: int) -> void:
	_traps.erase(tile)
	if _trap_marks.has(tile):
		(_trap_marks[tile] as Node).queue_free()
		_trap_marks.erase(tile)
	var node: Node3D = p["node"]
	_follow = null
	_move_camera(node.position + Vector3(0, 0.8, 0), 0.9, 0.5)
	await get_tree().create_timer(0.5, false).timeout
	var tr_ := world.bear_trap()
	var root: Node3D = tr_["root"]
	root.position = world.spaces[tile]["pos"]
	root.scale = Vector3.ONE * 1.6
	add_child(root)
	shot_hint = "65_trap"
	var jt := create_tween().set_parallel(true)
	jt.tween_property(tr_["jaws"][0], "rotation:x", -1.42, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	jt.tween_property(tr_["jaws"][1], "rotation:x", 1.42, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await jt.finished
	Audio.play("snap")
	_shake_camera(0.5, 0.25)
	world.bubbles_at(root.position + Vector3(0, 0.3, 0), 14, 0.5, true)
	p["skip"] = Rules.TRAP_SKIP
	p["trap_node"] = root
	await _damage(p, 1)
	if not bool(p.get("alive", true)) and is_instance_valid(root):
		root.queue_free()


## 덫에 물려 이번 차례를 쉼 → 덫이 풀림
func _skip_turn(p: Dictionary) -> void:
	p["skip"] = int(p.get("skip", 0)) - 1
	_highlight_chip(p)
	var node: Node3D = p["node"]
	_follow = null
	_move_camera(node.position + Vector3(0, 0.8, 0), 1.0, 0.6)
	await get_tree().create_timer(0.6, false).timeout
	var mine := not bool(p["cpu"]) and int(p["slot"]) == GameState.my_slot
	await _banner(tr("YOU SKIP A TURN") if mine else tr("%s SKIPS A TURN") % tr(String(p["name"])), "", 0.9)
	var root = p.get("trap_node")
	if int(p["skip"]) <= 0 and root is Node3D and is_instance_valid(root):
		p.erase("trap_node")
		Audio.play("creak")
		var t := create_tween()
		t.tween_property(root, "scale", Vector3.ONE * 0.01, 0.35).set_delay(0.2)
		t.tween_callback(root.queue_free)
		await t.finished


# ── 전기뱀장어 칸 ─────────────────────────────────────────────
## 멈추면 굴 속 뱀장어가 튀어나와 방전: 내 칸 앞뒤 EEL_RANGE 칸씩 (모두 5 칸) 안의 다른 사람 하트 -1
func _eel_zone(tile: int) -> Array:
	var seen := {tile: 0}
	var q := [tile]
	while not q.is_empty():
		var a: int = q.pop_front()
		if int(seen[a]) >= Rules.EEL_RANGE:
			continue
		for b in world.spaces[a]["links"]:
			if not seen.has(int(b)) and world.in_play(int(b)):
				seen[int(b)] = int(seen[a]) + 1
				q.append(int(b))
	return seen.keys()


var _fx_rng := RandomNumberGenerator.new()   ## 번개 모양 같은 볼거리만 (게임 결과에 안 씀 · 온라인 순서와 무관)


func _eel(p: Dictionary) -> void:
	var tile := int(p["tile"])
	var zone := _eel_zone(tile)
	var victims := []
	for q in _others(p):
		if zone.has(int(q["tile"])):
			victims.append(q)
	var den: Dictionary = world.eel_dens.get(tile, {})
	_follow = null
	_move_camera((world.spaces[tile]["pos"] as Vector3) + Vector3(0, 0.6, 0), 1.7, 0.7)
	await get_tree().create_timer(0.75, false).timeout
	# 뱀장어가 몸을 쭉 내밀며 빛을 모음
	var head_pos: Vector3 = (world.spaces[tile]["pos"] as Vector3) + Vector3(0, 1.2, 0)
	if not den.is_empty():
		var body: Node3D = den["body"]
		var mat: StandardMaterial3D = den["mat"]
		Audio.play("splash")
		var lt := create_tween().set_parallel(true)
		lt.tween_property(body, "scale", Vector3(1.0, 1.15, 1.35), 0.35).set_trans(Tween.TRANS_BACK)
		lt.tween_property(mat, "emission_energy_multiplier", 3.0, 0.5)
		await lt.finished
		head_pos = (den["head"] as Node3D).global_position
	# 범위 칸들이 파랗게 번쩍
	var flashes := []
	for t in zone:
		var fm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(BoardWorld.TILE, BoardWorld.TILE)
		fm.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.45, 0.85, 1.0, 0.0)
		fm.material_override = m
		fm.position = (world.spaces[t]["pos"] as Vector3) + Vector3(0, 0.03, 0)
		fm.rotation.y = float(world.spaces[t]["yaw"])
		add_child(fm)
		flashes.append(fm)
		create_tween().tween_property(m, "albedo_color:a", 0.7, 0.25)
	await get_tree().create_timer(0.3, false).timeout
	shot_hint = "66_eel_zap"
	Audio.play("zap")
	_shake_camera(0.45, 0.5)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.55, 0.85, 1.0)
	glow.omni_range = 12.0
	glow.light_energy = 6.0
	glow.position = head_pos
	add_child(glow)
	# 번개: 뱀장어 머리 → 범위 칸마다, 맞는 사람에게는 굵게. 세 번 번쩍임
	var targets := []
	for t in zone:
		targets.append((world.spaces[t]["pos"] as Vector3) + Vector3(0, 0.2, 0))
	for q in victims:
		targets.append((q["node"] as Node3D).position + Vector3(0, 0.9, 0))
	for flick in 3:
		var bolts := []
		for k in targets.size():
			bolts.append(_bolt(head_pos, targets[k], 0.07 if k >= zone.size() else 0.035))
		for q in victims:
			var vn: Node3D = q["node"]
			vn.rotation.z = _fx_rng.randf_range(-0.25, 0.25)
		await get_tree().create_timer(0.12, false).timeout
		for b in bolts:
			b.queue_free()
		await get_tree().create_timer(0.05, false).timeout
	for q in victims:
		(q["node"] as Node3D).rotation.z = 0.0
	create_tween().tween_property(glow, "light_energy", 0.0, 0.4).finished.connect(glow.queue_free)
	for fm in flashes:
		var ft := create_tween()
		ft.tween_property((fm as MeshInstance3D).material_override, "albedo_color:a", 0.0, 0.4)
		ft.tween_callback(fm.queue_free)
	if not den.is_empty():
		var rt := create_tween().set_parallel(true)
		rt.tween_property(den["body"], "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_SINE)
		rt.tween_property(den["mat"], "emission_energy_multiplier", 0.0, 0.8)
	for q in victims:
		await _damage(q, 1)
	if victims.is_empty():
		await get_tree().create_timer(0.5, false).timeout


## 번개 한 줄기: 지그재그로 꺾인 빛 막대들 (가는 심 + 바깥 번짐)
func _bolt(a: Vector3, b: Vector3, w: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = Color(0.85, 0.97, 1.0)
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_color = Color(0.3, 0.65, 1.0, 0.45)
	var n := 7
	var pts := [a]
	var dir := b - a
	var side := dir.cross(Vector3.UP).normalized()
	for k in range(1, n):
		var f := float(k) / n
		var off := side * _fx_rng.randf_range(-1.0, 1.0) * 0.35 + Vector3.UP * _fx_rng.randf_range(-0.3, 0.3)
		pts.append(a + dir * f + off * sin(f * PI) * minf(dir.length() * 0.12, 1.2))
	pts.append(b)
	for k in n:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var v := p1 - p0
		var L := maxf(v.length(), 0.01)
		var bs := Basis(Quaternion(Vector3.UP, v / L))
		for layer in [[w, core], [w * 3.2, halo]]:
			var cm := CylinderMesh.new()
			cm.top_radius = layer[0]
			cm.bottom_radius = layer[0]
			cm.height = 1.0
			cm.radial_segments = 5
			cm.rings = 1
			var mi := MeshInstance3D.new()
			mi.mesh = cm
			mi.material_override = layer[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = Transform3D(bs * Basis.from_scale(Vector3(1, L, 1)), p0 + v * 0.5)
			root.add_child(mi)
	return root


# ── 흡혈 해파리 카드 ──────────────────────────────────────────
const JELLY_SCALE := 1.5
## 고른 사람에게 해파리가 날아가 하트 1 을 빨아 와서 나에게 (방패면 막힘). 내 하트가 가득이면 못 씀
func _vampire(p: Dictionary) -> void:
	if int(p["hearts"]) >= Rules.HEARTS_MAX:
		await _banner(tr("HEARTS FULL"), "", 0.8)
		return
	var cands := _others(p)
	if cands.is_empty():
		return
	var target: Dictionary = await _pick_player(p, cands, tr("Pick a player to drain!"), "hearts")
	var pnode: Node3D = p["node"]
	var tnode: Node3D = target["node"]
	var jf := world.jelly()
	add_child(jf)
	var a := pnode.position + Vector3(0, 2.2, 0)
	var b := tnode.position + Vector3(0, 2.0, 0)
	jf.position = a
	jf.scale = Vector3.ONE * 0.01
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	# 카메라: 처음엔 내 말 곁 → 해파리를 따라 상대 곁으로
	var off := side * 3.6 - dir * 2.2 + Vector3(0, 1.4, 0)
	_follow = null
	_cinematic(a + off, a + Vector3(0, -0.5, 0), 1.0, 0.7)
	Audio.play("bubbles")
	create_tween().tween_property(jf, "scale", Vector3.ONE * JELLY_SCALE, 0.4).set_trans(Tween.TRANS_BACK)
	# 촉수가 물결치듯
	var swim := create_tween().set_loops()
	swim.tween_property(jf, "scale", Vector3(1.12, 0.85, 1.12) * JELLY_SCALE, 0.35).set_trans(Tween.TRANS_SINE)
	swim.tween_property(jf, "scale", Vector3(0.95, 1.08, 0.95) * JELLY_SCALE, 0.35).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.7, false).timeout
	var fly := clampf(span / 14.0, 0.7, 1.8)
	_cinematic(b + off, b + Vector3(0, -0.7, 0), 1.0, fly)
	var mt := create_tween()
	mt.tween_method(func(f: float) -> void: jf.position = a.lerp(b, f) + Vector3(0, sin(f * PI) * 1.2, 0), 0.0, 1.0, fly).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await mt.finished
	# 내려앉아 감싸고 빨아들임 (붉게 빛남)
	shot_hint = "67_vampire"
	var dn := create_tween()
	dn.tween_property(jf, "position", tnode.position + Vector3(0, 1.75, 0), 0.3).set_trans(Tween.TRANS_QUAD)
	await dn.finished
	Audio.play("portal")
	var before := int(target["hearts"])
	await _damage(target, 1)
	var stolen := int(target["hearts"]) < before
	if stolen:
		# 빨간 빛 방울이 해파리를 타고 내 말로
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		orb.mesh = sm
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.albedo_color = Color(1.0, 0.25, 0.4)
		orb.material_override = om
		add_child(orb)
		var o0 := jf.position
		var o1 := pnode.position + Vector3(0, 1.2, 0)
		var ot := create_tween()
		ot.tween_method(func(f: float) -> void: orb.position = o0.lerp(o1, f) + Vector3(0, sin(f * PI) * 1.5, 0), 0.0, 1.0, fly * 0.8).set_trans(Tween.TRANS_SINE)
		await ot.finished
		orb.queue_free()
		await _heal(p, 1)
	swim.kill()
	var gone := create_tween()
	gone.tween_property(jf, "scale", Vector3.ONE * 0.01, 0.35)
	gone.tween_callback(jf.queue_free)
	await gone.finished
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.8)
	await get_tree().create_timer(0.4, false).timeout


## 대포 칸: 원하는 상대를 골라 대포를 쏨 → 맞은 상대는 동전 5개를 잃음
func _cannon(p: Dictionary) -> void:
	var cands := _others(p)
	if cands.is_empty() or world.ship == null or not world.ship.cannons.has(int(p["tile"])):
		await _banner(tr("CANNON"), tr("Nobody to fire at."), 0.9)
		return
	var target: Dictionary = await _pick_player(p, cands, tr("Pick a player to fire the cannon at!"), "coins")
	var tnode: Node3D = target["node"]
	var c: Dictionary = world.ship.cannons[int(p["tile"])]
	var cpos: Vector3 = (c["yaw"] as Node3D).global_transform.origin
	var tpos := tnode.position
	# 대포 뒤 어깨너머에서 상대 쪽을 봄
	var dir := Vector3(tpos.x - cpos.x, 0, tpos.z - cpos.z).normalized()
	var side := Vector3(dir.z, 0, -dir.x)
	_follow = null
	_cinematic(cpos - dir * 3.5 + side * 3.2 + Vector3(0, 5.2, 0), cpos.lerp(tpos, 0.5) + Vector3(0, 0.8, 0), 1.0, 0.8)
	await get_tree().create_timer(0.85, false).timeout
	shot_hint = "63a_cannon_aim"
	# 발사 직후 카메라가 포탄을 따라 상대 쪽으로 미끄러져 감
	var near_from := tpos - dir * 7.5 + side * 3.0 + Vector3(0, 3.8, 0)
	var near_xf := Transform3D(Basis.looking_at(tpos + Vector3(0, 0.9, 0) - near_from, Vector3.UP), near_from)
	world.ship.cannon_fired.connect(func(fly: float) -> void:
		_shake_camera(0.45, 0.3)
		shot_hint = "63b_cannon_fire"
		create_tween().tween_property(self, "_cine_xf", near_xf, fly + 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT), CONNECT_ONE_SHOT)
	await world.ship.cannon_fire(int(p["tile"]), tpos + Vector3(0, 0.9, 0))
	get_tree().create_timer(0.3, false).timeout.connect(func() -> void: shot_hint = "63c_cannon_hit")
	_shake_camera(0.6, 0.4)
	# 맞은 말: 펄쩍 튀었다가 떨어짐 + 동전 -5
	var base := _spot_on(int(target["tile"]), target)
	var hop := create_tween()
	hop.tween_property(tnode, "position", base + Vector3(0, 1.6, 0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.parallel().tween_property(tnode, "rotation:z", 0.6, 0.22)
	hop.tween_property(tnode, "position", base, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.parallel().tween_property(tnode, "rotation:z", 0.0, 0.3)
	await hop.finished
	Audio.play("thud")
	_squash(tnode)
	_add_coins(target, -Rules.CANNON_COINS)
	await _banner(tr("BOOM!"), tr("%s loses %d coins") % [target["name"], Rules.CANNON_COINS], 1.1)
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.8)
	await get_tree().create_timer(0.6, false).timeout


## 크라켄의 보물상자 칸: 가진 동전을 원하는 만큼 걸고 룰렛 → 보물상자면 건 동전의 두 배를 받고,
## 크라켄이면 건 동전을 잃고 하트 -1
func _kraken_chest(p: Dictionary) -> void:
	var coins: int = p["coins"]
	_follow = null
	var cp: Vector3 = world.spaces[int(p["tile"])]["pos"]
	_move_camera(cp + Vector3(2.0, 0.6, 0), 1.7, 0.7)
	await get_tree().create_timer(0.75, false).timeout
	if coins <= 0:
		await _banner(tr("KRAKEN'S CHEST"), tr("You have no coins to bet."), 1.1)
		return
	var bet := await _ask_bet(p, coins)
	_add_coins(p, -bet)
	await get_tree().create_timer(0.45, false).timeout
	var win: bool = _rng.randf() < Rules.KRAKEN_CHEST_WIN if rig_chest < 0 else rig_chest == 1
	rig_chest = -1
	# 상자 옆 크라켄의 행운 바퀴를 정면에서 보며 돌림
	var view: Array = world.ship.wheel_view()
	_cinematic(view[0], view[1], 1.0, 0.9)
	var cap := VBoxContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_constant_override("separation", 2)
	_popup_root.add_child(cap)
	var title := _outlined_label(tr("KRAKEN'S CHEST"), 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	cap.add_child(title)
	var sub := _outlined_label(tr("%s bets %d coins") % [p["name"], bet], 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(sub)
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	cap.position = Vector2((vs.x - cap.size.x) * 0.5, vs.y - cap.size.y - 70.0)
	await get_tree().create_timer(1.0, false).timeout
	Audio.play("creak")
	get_tree().create_timer(1.8, false).timeout.connect(func() -> void: shot_hint = "62b_chest_spin")
	await world.ship.wheel_spin(win)
	shot_hint = "62e_chest_wheel_stop"
	await get_tree().create_timer(0.6, false).timeout
	cap.queue_free()
	_cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.8)
	await get_tree().create_timer(0.6, false).timeout
	if world.ship:
		world.ship.chest_reveal(win)
	if win:
		Audio.play("start")
		Audio.play("coins")
		_add_coins(p, bet * 2)
		shot_hint = "62c_chest_win"
		await _banner(tr("TREASURE!"), tr("Your bet is doubled: +%d coins") % (bet * 2), 1.3)
	else:
		Audio.play("kraken_slam")
		Audio.play("roar")
		_shake_camera(0.55, 0.45)
		shot_hint = "62d_chest_kraken"
		await _banner(tr("THE KRAKEN!"), "", 1.0)
		await _damage(p, 1)


## 걸 동전 고르기 (−5 −1 [금액] +1 +5 · 최소 · 절반 · 전부 → 돌리기). 자동이면 가진 돈의 25~70%
func _ask_bet(p: Dictionary, coins: int) -> int:
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(GOLD, 0.8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 26)
	v.add_child(icons)
	var ic1 := _icon(BoardWorld.ICONS["treasure"], 72)
	ic1.modulate = GOLD
	icons.add_child(ic1)
	var ic2 := _icon(BoardWorld.ICONS["boss"], 72)
	ic2.modulate = Color(0.55, 1.0, 0.45)
	icons.add_child(ic2)
	var t := Label.new()
	t.text = tr("KRAKEN'S CHEST")
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	var body := Label.new()
	body.text = tr("Bet your coins and spin the wheel.\nTreasure chest: your bet is doubled.\nKraken: you lose your bet and 1 heart.")
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", Color(PEARL, 0.85))
	v.add_child(body)
	var st := {"bet": clampi(coins / 2, 1, coins), "done": false}
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var amount := Label.new()
	amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	amount.custom_minimum_size = Vector2(130, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", 54)
	amount.add_theme_color_override("font_color", GOLD)
	var have := Label.new()
	have.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	have.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	have.add_theme_color_override("font_color", Color(PEARL, 0.7))
	var btns := {}
	var refresh := func() -> void:
		amount.text = str(st["bet"])
		have.text = tr("You have %d coins") % coins
		for k in btns:
			var d: int = int(k)
			(btns[k] as Button).disabled = int(st["bet"]) + d < 1 or int(st["bet"]) + d > coins
	var step_btn := func(d: int) -> Button:
		var b := _glass_button(("%+d" % d))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(82, 58)
		b.pressed.connect(func() -> void:
			st["bet"] = clampi(int(st["bet"]) + d, 1, coins)
			Audio.play("tick")
			refresh.call())
		btns[d] = b
		return b
	row.add_child(step_btn.call(-5))
	row.add_child(step_btn.call(-1))
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.add_child(_icon(COIN_TEX, 46))
	mid.add_child(amount)
	row.add_child(mid)
	row.add_child(step_btn.call(1))
	row.add_child(step_btn.call(5))
	v.add_child(have)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	v.add_child(row2)
	for q in [["MIN", 0.0], ["HALF", 0.5], ["ALL", 1.0]]:
		var b := _glass_button(tr(q[0]))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(130, 52)
		var f: float = q[1]
		b.pressed.connect(func() -> void:
			st["bet"] = clampi(int(round(coins * f)), 1, coins)
			Audio.play("tick")
			refresh.call())
		row2.add_child(b)
	var go := _glass_button(tr("SPIN"))
	go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	go.custom_minimum_size = Vector2(260, 66)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 30)
	go.pressed.connect(func() -> void:
		Audio.play("click")
		st["done"] = true)
	v.add_child(go)
	refresh.call()
	_dialog_open = true
	await _show_modal(panel)
	shot_hint = "62a_chest_bet"
	if _is_remote(p):
		_block(panel)
		st["bet"] = int(await _get_dec(p))
		refresh.call()
		await get_tree().create_timer(0.5, false).timeout
		st["done"] = true
	elif _is_auto(p):
		await get_tree().create_timer(1.2, false).timeout
		var keep := _use_aux(p)
		var k := 0.15 if int(p.get("hearts", 3)) <= 1 else _rng.randf_range(0.25, 0.7)
		_rng = keep
		st["bet"] = clampi(int(round(coins * k)), 1, coins)
		refresh.call()
		await get_tree().create_timer(0.8, false).timeout
		st["done"] = true
	while not bool(st["done"]):
		await get_tree().process_frame
	if not _is_remote(p):
		_put_dec(p, int(st["bet"]))
	_dialog_open = false
	dim.queue_free()
	return int(st["bet"])


## 성게 함정 칸에 멈춤 (생존전에서 크라켄이 만든 칸)
func _urchin_trap(p: Dictionary) -> void:
	await _damage(p, 1)


## 하트 잃기 (방패가 있으면 대신 깨짐). 0 이 되면 탈락
func _damage(p: Dictionary, n: int) -> void:
	if not bool(p.get("alive", true)):
		return
	var node: Node3D = p["node"]
	if int(p.get("shield", 0)) > 0:
		p["shield"] = int(p["shield"]) - 1
		_refresh_chip(p)
		Audio.play("toggle_off")
		_float_text(p, tr("PROTECTED!"), Color("bfe9ff"), SHIELD_TEX)
		world.bubbles_at(node.position + Vector3(0, 1.0, 0), 18, 0.6, true)
		await get_tree().create_timer(0.7, false).timeout
		return
	var oxygen := int(p["hearts"]) - n <= 0 and "oxygen" in (p.get("items", []) as Array)
	p["hearts"] = maxi(1 if oxygen else 0, int(p["hearts"]) - n)
	if oxygen:
		(p["items"] as Array).erase("oxygen")
	_refresh_chip(p)
	_pop(p["chip"])
	Audio.play("remove")
	_float_text(p, "-%d" % n, Color("ff6b6b"), HEART_TEX)
	_shake_camera(0.35, 0.18)
	var t := create_tween()
	t.tween_property(node, "scale", Vector3(1.3, 0.6, 1.3) * PAWN_SCALE, 0.08)
	t.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE, 0.3).set_trans(Tween.TRANS_ELASTIC)
	await get_tree().create_timer(0.8, false).timeout
	if oxygen:
		# 산소통: 마지막 하트에서 버팀 (공기 방울이 확 터지며 숨을 돌림)
		await _item_pop(p, "oxygen")
		Audio.play("bubbles")
		world.bubbles_at(node.position + Vector3(0, 1.2, 0), 40, 1.0, true)
		_float_text(p, tr("OXYGEN!"), Color("ffe08a"), ITEM_TEX["oxygen"])
		await get_tree().create_timer(0.8, false).timeout
	if int(p["hearts"]) <= 0:
		await _eliminate(p)


func _heal(p: Dictionary, n: int) -> void:
	var before: int = p["hearts"]
	p["hearts"] = mini(Rules.HEARTS_MAX, before + n)
	_refresh_chip(p)
	_pop(p["chip"])
	if int(p["hearts"]) > before:
		Audio.play("add")
		_float_text(p, "+%d" % (int(p["hearts"]) - before), Color("ff8fa3"), HEART_TEX)
	else:
		_float_text(p, tr("FULL"), Color("ff8fa3"), HEART_TEX)
	await get_tree().create_timer(0.6, false).timeout


## 하트 0: 촉수가 휘감아 바닷속으로 끌고 감 (게임이 덮어써서 승패 판정)
func _eliminate(p: Dictionary) -> void:
	p["alive"] = false
	var node: Node3D = p["node"]
	_follow = null
	_move_camera(node.position + Vector3(0, 1.0, 0), 1.2, 0.6)
	await get_tree().create_timer(0.6, false).timeout
	await world.tentacle_drag(node)
	_refresh_chip(p)
	var mine := not bool(p["cpu"]) and int(p["slot"]) == GameState.my_slot
	await _banner(tr("YOU'RE GONE!") if mine else tr("%s IS GONE!") % tr(String(p["name"])), "", 1.2)


## 화면 흔들기 (촉수가 내려칠 때)
func _shake_camera(amount: float, time: float) -> void:
	var t := create_tween()
	var steps := int(time / 0.03)
	for k in steps:
		var f := 1.0 - float(k) / steps
		t.tween_property(_camera, "h_offset", randf_range(-1, 1) * amount * f, 0.03)
		t.parallel().tween_property(_camera, "v_offset", randf_range(-1, 1) * amount * f, 0.03)
	t.tween_property(_camera, "h_offset", 0.0, 0.03)
	t.parallel().tween_property(_camera, "v_offset", 0.0, 0.03)


## 포탈: 짝 포탈로
func _warp(p: Dictionary) -> void:
	var b: int = world.portal_partner(int(p["tile"]))
	if b >= 0:
		await _warp_to(p, b)


## 어느 칸으로든 순간이동 (빨려 들어가 → 튀어나옴)
func _warp_to(p: Dictionary, b: int) -> void:
	var node: Node3D = p["node"]
	var a: int = p["tile"]
	Audio.play("bubbles")
	var t := create_tween().set_parallel(true)
	t.tween_property(node, "scale", Vector3.ONE * 0.05, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(node, "position:y", node.position.y + 1.3, 0.55)
	t.tween_property(node, "rotation:y", node.rotation.y + TAU * 2.0, 0.55)
	await t.finished
	world.portal_burst(world.spaces[a]["pos"])
	node.visible = false
	_follow = null
	_move_camera(world.spaces[b]["pos"], 1.0, 1.0)
	await get_tree().create_timer(1.0, false).timeout
	p["prev"] = -1
	p["tile"] = b
	var spot := _spot_on(b, p)
	node.position = spot + Vector3(0, 1.3, 0)
	node.rotation.y = 0.0
	node.visible = true
	world.portal_burst(world.spaces[b]["pos"])
	Audio.play("add")
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(node, "scale", Vector3.ONE * PAWN_SCALE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t2.tween_property(node, "position", spot, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await t2.finished
	_follow = node


## 미니게임 (아직 미니게임이 없어서 순위는 운으로 정함). trophy=true 면 1등이 트로피
func _run_minigame(lander: Dictionary, trophy: bool) -> void:
	Audio.play("start")
	await _banner(tr("TROPHY MINIGAME!") if trophy else tr("MINIGAME!"), "", 0.9)
	var order: Array
	if rig_ranking.size() == _pawns.size():
		order = rig_ranking.duplicate()
	else:
		order = await _play_minigame(rig_minigame)
	rig_ranking = []
	rig_minigame = ""
	# 결과 창
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(AQUA, 0.7))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "RESULTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	v.add_child(title)
	for k in order.size():
		var q: Dictionary = order[k]
		var reward := 0
		var got_trophy := trophy and k == 0
		if not trophy:
			reward = int(Rules.MINIGAME_REWARDS[mini(k, Rules.MINIGAME_REWARDS.size() - 1)])
			if q == lander:
				reward += Rules.MINIGAME_LANDER_BONUS
		v.add_child(_result_row(k + 1, q, reward, got_trophy))
	if false:   # 설명 글은 뺌 (보너스는 그대로 들어감)
		var note := Label.new()
		note.text = tr("Whoever landed on the space gets +%d bonus coins.") % Rules.MINIGAME_LANDER_BONUS
		note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		note.add_theme_font_size_override("font_size", 16)
		note.add_theme_color_override("font_color", Color(PEARL, 0.6))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(note)
	await _show_modal(panel)
	shot_hint = "43_minigame_results"
	await get_tree().create_timer(2.4, false).timeout
	dim.queue_free()
	for k in order.size():
		var q: Dictionary = order[k]
		if trophy:
			if k == 0:
				_add_trophy(q, 1)
		else:
			var reward := int(Rules.MINIGAME_REWARDS[mini(k, Rules.MINIGAME_REWARDS.size() - 1)])
			if q == lander:
				reward += Rules.MINIGAME_LANDER_BONUS
			_add_coins(q, reward)
	if survival() and order.size() > 0 and bool(order[0].get("alive", true)):
		await get_tree().create_timer(0.4, false).timeout
		await _heal(order[0], Rules.MINIGAME_WIN_HEAL)
	await get_tree().create_timer(0.8, false).timeout


## 미니게임 한 판: 검은 화면 → 소개 화면(전용 음악, 미리보기, 준비) → 검은 화면 → 게임(게임별 음악) → 보드로
func _play_minigame(id: String) -> Array:
	id = Minigames.pick(id, _rng)
	var auto := GameState.debug_autoplay or GameState.debug_auto_minigames
	var hint_cb := func(h: String) -> void: shot_hint = h
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	Audio.stop_music(0.5)
	await _fade_black(black, 1.0, 0.5)
	# 미니게임 동안 보드 세상은 그리지 않음 (미니게임은 자기 3D 무대가 따로 있어서 겹쳐 그리면 무거움)
	world.visible = false
	await get_tree().create_timer(0.7, false).timeout
	# 소개 화면
	var net_mode := ("host" if Net.is_host() else "client") if _online else ""
	var mg_seed := _rng.randi() % 2000000000 + 1
	var intro := MinigameIntro.new()
	intro.setup(id, _pawns, auto, hint_cb)
	intro.net_setup(net_mode, GameState.my_slot)
	layer.add_child(intro)
	layer.move_child(black, -1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Audio.play_music(0.0, "mg_intro")
	await _fade_black(black, 0.0, 0.45)
	await intro.run()
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	Audio.stop_music(0.5)
	await _fade_black(black, 1.0, 0.45)
	intro.queue_free()
	await get_tree().create_timer(1.0, false).timeout
	# 게임
	var mg := Minigames.create(id, _rng)
	mg.setup(_pawns, auto, hint_cb)
	mg.net_seed = mg_seed
	mg.net_setup(net_mode, GameState.my_slot)
	if has_method("_round_limit"):
		pass   # 보드 진행에 따른 난이도 변화 없음 (미니게임 기본 난이도만 살짝 높게 · heat 기본값)
	if GameState.debug_autoplay and mg.duration < 100.0:
		mg.duration *= 0.4   # 자동 점검은 짧게
	layer.add_child(mg)
	layer.move_child(black, -1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Audio.play_music(0.0, id)
	await _fade_black(black, 0.0, 0.4)
	var order: Array = await mg.run()
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	Audio.stop_music(0.4)
	await _fade_black(black, 1.0, 0.4)
	mg.queue_free()
	world.visible = true
	await get_tree().create_timer(0.4, false).timeout
	Audio.play_music(0.0, "ship" if world.on_ship else "board")
	await _fade_black(black, 0.0, 0.4)
	layer.queue_free()
	return order


## 모두 같은 순서로 섞기 (온라인: 전역 난수 대신 _rng)
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _fade_black(black: ColorRect, to: float, time: float) -> void:
	var t := create_tween()
	t.tween_property(black, "color:a", to, time)
	await t.finished


func _result_row(rank: int, q: Dictionary, reward: int, trophy: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var r := Label.new()
	r.text = "%d" % rank
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	r.custom_minimum_size = Vector2(36, 0)
	r.add_theme_font_size_override("font_size", 30)
	r.add_theme_color_override("font_color", GOLD if rank == 1 else PEARL)
	row.add_child(r)
	row.add_child(_dot(q["color"], 24))
	var n := Label.new()
	n.text = q["name"]
	n.custom_minimum_size = Vector2(170, 0)
	n.add_theme_font_size_override("font_size", 24)
	row.add_child(n)
	if trophy or reward > 0:
		row.add_child(_icon(TROPHY_TEX if trophy else COIN_TEX, 30))
		var m := Label.new()
		m.text = "+1" if trophy else "+%d" % reward
		m.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		m.add_theme_font_size_override("font_size", 24)
		m.add_theme_color_override("font_color", GOLD)
		row.add_child(m)
	return row


# ── 찬스 카드 ────────────────────────────────────────────────
func _draw_card(p: Dictionary) -> void:
	var c: Dictionary = Rules.card(rig_card) if rig_card != "" else Rules.random_card(_rng, survival())
	rig_card = ""
	await _card_popup(c)
	await _apply_card(p, String(c["id"]))


func _card_icon(id: String) -> Texture2D:
	match id:
		"trophy_minigame":
			return BoardWorld.ICONS["minigame"]
		"trophy_thief":
			return TROPHY_TEX
		"warp":
			return BoardWorld.ICONS["portal"]
		"lucky_spaces":
			return BoardWorld.ICONS["coin_plus"]
		"trap_spaces":
			return BoardWorld.ICONS["coin_minus"]
		"roll_again":
			return DICE_ATLAS
		"heal":
			return HEART_TEX
		"shield":
			return SHIELD_TEX
		"bait":
			return BoardWorld.ICONS["boss"]
		"harpoon":
			return BoardWorld.ICONS["harpoon"]
		"trap":
			return BoardWorld.ICONS["trap"]
		"vampire":
			return BoardWorld.ICONS["jelly"]
	return COIN_TEX


## 카드가 날아와 뒤집히면 앞면에 내용
func _card_popup(c: Dictionary) -> void:
	Audio.play("card_draw")
	var v := get_viewport().get_visible_rect().size
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_root.add_child(holder)
	var size := Vector2(280, 384)
	var back := TextureRect.new()
	back.texture = CARD_TEX
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.size = size
	back.pivot_offset = size * 0.5
	back.position = Vector2(v.x * 0.5 - size.x * 0.5, v.y + 40)
	holder.add_child(back)
	# 앞면
	var front := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("fff6df")
	st.border_color = Color("f4b43a")
	st.set_border_width_all(8)
	st.set_corner_radius_all(26)
	st.set_content_margin_all(22)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 16
	front.add_theme_stylebox_override("panel", st)
	front.custom_minimum_size = size
	front.size = size
	front.pivot_offset = size * 0.5
	front.position = Vector2(v.x * 0.5 - size.x * 0.5, v.y * 0.5 - size.y * 0.5)
	front.scale = Vector2(0.05, 1.0)
	front.visible = false
	holder.add_child(front)
	var fv := VBoxContainer.new()
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	fv.add_theme_constant_override("separation", 14)
	front.add_child(fv)
	var head := Label.new()
	head.text = "CHANCE CARD!"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("c9821c"))
	fv.add_child(head)
	var id := String(c["id"])
	if id in ["warp", "trophy_minigame", "lucky_spaces", "trap_spaces"]:
		var kinds := {"warp": "portal", "trophy_minigame": "minigame", "lucky_spaces": "coin_plus", "trap_spaces": "coin_minus"}
		var kind: String = kinds[id]
		var sw := _kind_swatch(kind, 110)
		sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		fv.add_child(sw)
	else:
		var tex := _card_icon(id)
		if id == "roll_again":
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(256 * 2, 0, 256, 256)
			tex = at
		var ic := _icon(tex, 110)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		fv.add_child(ic)
	var t1 := Label.new()
	t1.text = c["title"]
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t1.add_theme_font_size_override("font_size", 30)
	t1.add_theme_color_override("font_color", Color("3a2a10"))
	fv.add_child(t1)
	var t2 := Label.new()
	t2.text = c["text"]
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t2.custom_minimum_size = Vector2(size.x - 50, 0)
	t2.add_theme_font_size_override("font_size", 18)
	t2.add_theme_color_override("font_color", Color("6a5536"))
	fv.add_child(t2)
	# 뒷면이 천천히 올라와 잠깐 멈춤 (두근) → 천천히 뒤집혀 앞면
	var t := create_tween()
	t.tween_property(back, "position:y", v.y * 0.5 - size.y * 0.5, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(back, "rotation", TAU, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(back, "scale", Vector2(1.06, 1.06), 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(back, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_interval(0.25)
	t.tween_callback(func() -> void: Audio.play("card_flip"))
	t.tween_property(back, "scale:x", 0.05, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		back.visible = false
		front.visible = true)
	t.tween_property(front, "scale:x", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	shot_hint = "42_card_" + id
	await get_tree().create_timer(2.6, false).timeout
	var t3 := create_tween()
	t3.tween_property(holder, "modulate:a", 0.0, 0.3)
	await t3.finished
	holder.queue_free()


func _others(p: Dictionary) -> Array:
	var out := []
	for q in _pawns:
		if q != p and bool(q.get("alive", true)) and (String(p["team"]) == "" or q["team"] != p["team"]):
			out.append(q)
	return out


func _apply_card(p: Dictionary, id: String) -> void:
	match id:
		"coins5":
			_add_coins(p, 5)
			await get_tree().create_timer(0.8, false).timeout
		"coins10":
			_add_coins(p, 10)
			await get_tree().create_timer(0.8, false).timeout
		"roll_again":
			await _play_turn(p)
			if not _game_over:
				await _tile_effect(p)
		"lucky_spaces":
			await _spawn_coin_spaces(p, "coin_plus")
		"trap_spaces":
			await _spawn_coin_spaces(p, "coin_minus")
		"pickpocket":
			var cands := _others(p)
			if cands.is_empty():
				return
			var target: Dictionary = await _pick_player(p, cands, tr("Who do you take %d coins from?") % Rules.STEAL_COINS, "coins")
			var amount := mini(Rules.STEAL_COINS, int(target["coins"]))
			_add_coins(target, -amount)
			await get_tree().create_timer(0.3, false).timeout
			_add_coins(p, amount)
			await get_tree().create_timer(0.8, false).timeout
		"warp":
			var t: int = await _pick_tile(p)
			if t >= 0 and t != int(p["tile"]):
				await _warp_to(p, t)
				if t == world.trophy_tile:
					await _offer_trophy(p)
		"heal":
			await _heal(p, 1)
		"shield":
			p["shield"] = int(p.get("shield", 0)) + 1
			_refresh_chip(p)
			Audio.play("toggle_on")
			_float_text(p, "+1", Color("bfe9ff"), SHIELD_TEX)
			await get_tree().create_timer(0.8, false).timeout
		"bait":
			var cands := _others(p)
			if cands.is_empty():
				return
			var target: Dictionary = await _pick_player(p, cands, tr("Who do you throw the bait at?"), "hearts")
			await _bait(target)
		"harpoon":
			await _harpoon(p, true)
		"trap":
			await _set_trap(p)
		"vampire":
			await _vampire(p)
		"trophy_minigame":
			await _run_minigame(p, true)
		"trophy_thief":
			var cands := []
			for q in _others(p):
				if int(q["trophies"]) > 0:
					cands.append(q)
			if cands.is_empty():
				await _banner(tr("NO LUCK!"), tr("Nobody has a trophy to steal yet."), 1.0)
				return
			var target: Dictionary = await _pick_player(p, cands, tr("Whose trophy do you steal?"), "trophies")
			_add_trophy(target, -1)
			await get_tree().create_timer(0.3, false).timeout
			_add_trophy(p, 1)
			await get_tree().create_timer(0.8, false).timeout


## 미끼: 그 사람 칸을 크라켄이 노림 (게임이 덮어씀)
func _bait(_target: Dictionary) -> void:
	pass


## 찬스 카드: 보드 곳곳에 +5 / -5 동전 칸이 생김
func _spawn_coin_spaces(p: Dictionary, kind: String) -> void:
	var pool := []
	for i in world.regular_tiles():
		if not _tile_mods.has(i) and i != world.trophy_tile and String(world.spaces[i]["kind"]) != "chance":
			pool.append(i)
	_shuffle(pool)
	_follow = null
	_move_camera(world.overview, world.overview_zoom, 1.0)
	await get_tree().create_timer(1.05, false).timeout
	_legend_add(kind)
	for k in mini(Rules.COIN_SPACES_PER_CARD, pool.size()):
		var i: int = pool[k]
		_tile_mods[i] = kind
		world.set_tile_look(i, kind)
		Audio.play("toast")
		await get_tree().create_timer(0.35, false).timeout
	shot_hint = "44_" + kind
	await get_tree().create_timer(1.0, false).timeout
	focus_on(p, 0.8)
	await get_tree().create_timer(0.8, false).timeout
	_follow = p["node"]


# ── 상점 ─────────────────────────────────────────────────────
## 들를 때마다 가끔 트로피가 진열됨 (다른 상품은 나중에)
## 나무 가게가 문을 여는 화면: 차양이 내려오고 간판이 흔들리고 덧문이 양쪽으로 열려요
func _open_shop(p: Dictionary) -> void:
	var dim := _modal_dim()
	dim.color = Color(0, 0.03, 0.03, 0.0)
	create_tween().tween_property(dim, "color:a", 0.55, 0.25)
	var stall := Control.new()
	stall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stall.size = Vector2(1240, 960)
	dim.add_child(stall)
	var vp := get_viewport().get_visible_rect().size
	var sc := minf(vp.x / 1320.0, vp.y / 1020.0)
	stall.scale = Vector2.ONE * sc
	stall.position = (vp - stall.size * sc) * 0.5

	# 나무 벽 + 진열 칸 (덧문 뒤에 숨어 있다가 열림)
	var wall_box := Control.new()
	wall_box.clip_contents = true
	wall_box.position = Vector2(70, 230)
	wall_box.size = Vector2(1100, 690)
	wall_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stall.add_child(wall_box)
	wall_box.add_child(_tex_rect(SHOP_TEX["wall"], Vector2.ZERO, Vector2(1100, 690)))
	_shop_buy = null
	# 진열칸 4개: 들를 때마다 아이템 7가지 중 4가지가 무작위로 진열됨 (모두 같은 _rng → 온라인도 같은 진열)
	var stock: Array = Rules.ITEM_ORDER.duplicate()
	_shuffle(stock)
	stock = stock.slice(0, 4)
	if not force_shop_stock.is_empty():   # 점검 · 촬영용
		stock = force_shop_stock.duplicate()
		force_shop_stock = []
	stock.sort_custom(func(a: String, b: String) -> bool: return Rules.ITEM_ORDER.find(a) < Rules.ITEM_ORDER.find(b))
	# 사진 위에 마우스를 올리면 아래 계산대에 설명
	var desc_ref := [null]
	# 설명 말풍선: 마우스를 올린 아이템 바로 위에 뜸
	var tip := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.1, 0.055, 0.02, 0.95)
	tsb.border_color = Color(0.95, 0.75, 0.4)
	tsb.set_border_width_all(3)
	tsb.set_corner_radius_all(14)
	tsb.content_margin_left = 18
	tsb.content_margin_right = 18
	tsb.content_margin_top = 10
	tsb.content_margin_bottom = 12
	tsb.shadow_color = Color(0, 0, 0, 0.5)
	tsb.shadow_size = 10
	tip.add_theme_stylebox_override("panel", tsb)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 20
	tip.visible = false
	var tipv := VBoxContainer.new()
	tipv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tipv.add_theme_constant_override("separation", 4)
	tip.add_child(tipv)
	var tip_t := Label.new()
	tip_t.add_theme_font_size_override("font_size", 24)
	tip_t.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	tipv.add_child(tip_t)
	var tip_d := Label.new()
	tip_d.autowrap_mode = TextServer.AUTOWRAP_WORD    # 낱말 단위로만 줄바꿈 (한국어가 글자 중간에서 끊기지 않게)
	tip_d.custom_minimum_size = Vector2(340, 0)
	tip_d.add_theme_font_size_override("font_size", 21)
	tip_d.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	tipv.add_child(tip_d)
	var bag_ref := [null]
	_shop_buys = []
	var refresh := func() -> void:
		var full := (p["items"] as Array).size() >= Rules.BAG_SIZE
		for bb in _shop_buys:
			var bt: Button = bb[0]
			bt.disabled = full or int(p["coins"]) < int(bb[2])
			bt.text = "BAG FULL" if full else "BUY"
		if bag_ref[0]:
			(bag_ref[0] as Label).text = tr("Bag %d/%d") % [(p["items"] as Array).size(), Rules.BAG_SIZE]
	for k in stock.size():
		var x := 45.0 + k * 260.0
		var y := 130.0
		wall_box.add_child(_tex_rect(SHOP_TEX["slot"], Vector2(x + 15, y), Vector2(200, 190)))
		var gid: String = stock[k]
		var it: Dictionary = Rules.ITEMS[gid]
		var cost: int = int(it["price"]) * shop_price_mult
		var ic := _icon(ITEM_TEX[gid], 176)
		ic.position = Vector2(x + 27, y + 7)
		ic.size = Vector2(176, 176)
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		wall_box.add_child(ic)
		var nm := Label.new()
		nm.text = String(it["title"])
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 이름표: 짙은 나무색 명판 위에 밝은 글씨 (나무 무늬 위에서도 또렷하게)
		nm.position = Vector2(x + 10, y + 192)
		nm.size = Vector2(210, 36)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 22)
		nm.add_theme_color_override("font_color", Color(1.0, 0.95, 0.84))
		nm.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.01))
		nm.add_theme_constant_override("outline_size", 6)
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(0.13, 0.07, 0.03, 0.9)
		plate.border_color = Color(0.55, 0.38, 0.18)
		plate.set_border_width_all(2)
		plate.set_corner_radius_all(8)
		nm.add_theme_stylebox_override("normal", plate)
		wall_box.add_child(nm)
		var tag := _tex_rect(SHOP_TEX["tag"], Vector2(x + 45, y + 232), Vector2(140, 52))
		wall_box.add_child(tag)
		var price := HBoxContainer.new()
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.alignment = BoxContainer.ALIGNMENT_CENTER
		price.position = Vector2(x + 75, y + 232)
		price.size = Vector2(100, 52)
		price.add_theme_constant_override("separation", 6)
		wall_box.add_child(price)
		price.add_child(_icon(COIN_TEX, 24))
		var pl := Label.new()
		pl.text = str(cost)
		pl.add_theme_font_size_override("font_size", 22)
		pl.add_theme_color_override("font_color", Color(0.75, 0.08, 0.06) if shop_price_mult > 1 else Color(0.28, 0.16, 0.08))
		price.add_child(pl)
		var buy := _wood_button("BUY", Vector2(180, 56))
		buy.position = Vector2(x + 25, y + 296)
		wall_box.add_child(buy)
		_shop_buys.append([buy, gid, cost])
		if _shop_buy == null:
			_shop_buy = buy
		var tip_x := x + 115.0
		var tip_y := y
		var show_desc := func() -> void:
			tip_t.text = tr(String(it["title"]))
			tip_d.text = _keep_words(tr(String(it["text"])))
			tip.size = Vector2.ZERO
			tip.visible = true
			await get_tree().process_frame
			if is_instance_valid(tip):
				tip.position = Vector2(clampf(tip_x - tip.size.x * 0.5, 0.0, 1100.0 - tip.size.x), tip_y - tip.size.y - 6.0)
		var hide_desc := func() -> void:
			tip.visible = false
		ic.mouse_entered.connect(show_desc)
		buy.mouse_entered.connect(show_desc)
		ic.mouse_exited.connect(hide_desc)
		buy.mouse_exited.connect(hide_desc)
		buy.pressed.connect(func() -> void:
			if buy.disabled:
				return
			_put_dec(p, gid)
			_add_coins(p, -cost)
			(p["items"] as Array).append(gid)
			_refresh_chip(p)
			_pop(p["chip"])
			Audio.play("equip")
			refresh.call())
	# 덧문 두 짝
	var left := _tex_rect(SHOP_TEX["shutter"], Vector2.ZERO, Vector2(550, 690))
	var right := _tex_rect(SHOP_TEX["shutter"], Vector2(550, 0), Vector2(550, 690))
	right.flip_h = true
	left.flip_h = false
	wall_box.add_child(left)
	wall_box.add_child(right)
	var awn_shadow := _tex_rect(SHOP_TEX["awning_shadow"], Vector2(-70, 60), Vector2(1240, 120))
	awn_shadow.modulate.a = 0.0
	wall_box.add_child(awn_shadow)

	# 계산대 + 안내 + 닫기
	stall.add_child(_tex_rect(SHOP_TEX["counter"], Vector2(30, 780), Vector2(1180, 180)))
	wall_box.add_child(tip)
	var msg_text := "Point at an item to see what it does"
	if shop_price_mult > 1:
		msg_text = "The kraken scared the merchant — prices are doubled!"
	var msg := _outlined_label(msg_text, 30)
	msg.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	msg.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	msg.add_theme_constant_override("outline_size", 10)
	msg.position = Vector2(30, 806)
	msg.size = Vector2(1180, 48)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stall.add_child(msg)
	desc_ref[0] = msg
	var bag_l := _outlined_label("", 28)
	bag_l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58))
	bag_l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	bag_l.add_theme_constant_override("outline_size", 9)
	bag_l.position = Vector2(860, 890)
	bag_l.size = Vector2(300, 40)
	stall.add_child(bag_l)
	bag_ref[0] = bag_l
	refresh.call()
	var close := _wood_button("CLOSE", Vector2(250, 74))
	close.position = Vector2(495, 870)
	close.set_meta("sfx", "back")
	stall.add_child(close)
	# 차양 · 간판
	var awn := _tex_rect(SHOP_TEX["awning"], Vector2(0, -260), Vector2(1240, 210))
	stall.add_child(awn)
	var board_sign := _tex_rect(SHOP_TEX["sign"], Vector2(400, -220), Vector2(440, 190))
	board_sign.pivot_offset = Vector2(220, 0)
	stall.add_child(board_sign)
	var sh := HBoxContainer.new()
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	sh.add_theme_constant_override("separation", 14)
	sh.position = Vector2(0, 62)
	sh.size = Vector2(440, 120)
	board_sign.add_child(sh)
	var title := Label.new()
	title.text = "SHOP"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 64)
	# 나무 간판 위에 또렷하게: 흰 글씨 + 짙은 갈색 굵은 테두리 + 그림자
	title.add_theme_color_override("font_color", Color(1.0, 0.98, 0.93))
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.03))
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	sh.add_child(title)

	var lamps := []
	for lx in [24.0, 1116.0]:
		var glow := _tex_rect(SHOP_TEX["glow"], Vector2(lx - 130, 230), Vector2(360, 360))
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add_mat
		glow.modulate = Color(1, 1, 1, 0.0)
		stall.add_child(glow)
		var lamp := _tex_rect(SHOP_TEX["lantern"], Vector2(lx, -200), Vector2(100, 173))
		lamp.pivot_offset = Vector2(50, 0)
		stall.add_child(lamp)
		lamps.append([lamp, glow])
	_shop_panel = dim
	_shop_close = close
	_shop_open = true
	close.pressed.connect(_close_shop)
	# 문 여는 연출
	Audio.play("toast")
	var t := create_tween()
	t.tween_property(awn, "position:y", 150.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(board_sign, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	t.parallel().tween_property(awn_shadow, "modulate:a", 1.0, 0.4).set_delay(0.2)
	for lg in lamps:
		t.parallel().tween_property(lg[0], "position:y", 300.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.2)
		t.parallel().tween_property(lg[1], "modulate:a", 0.55, 0.5).set_delay(0.35)
	t.tween_callback(func() -> void: Audio.play("tab"))
	t.tween_property(left, "position:x", -560.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(right, "position:x", 1110.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var swing := board_sign.create_tween().set_loops(3)
	swing.tween_property(board_sign, "rotation", 0.05, 0.35).set_trans(Tween.TRANS_SINE)
	swing.tween_property(board_sign, "rotation", -0.04, 0.35).set_trans(Tween.TRANS_SINE)
	# 등불: 살랑 흔들리고 불빛이 깜빡임
	for lg in lamps:
		var lamp: Control = lg[0]
		var glow: Control = lg[1]
		var sway := lamp.create_tween().set_loops()
		sway.tween_property(lamp, "rotation", 0.06, 0.9).set_trans(Tween.TRANS_SINE)
		sway.tween_property(lamp, "rotation", -0.06, 0.9).set_trans(Tween.TRANS_SINE)
		var flick := glow.create_tween().set_loops()
		flick.tween_property(glow, "modulate:a", 0.45, 0.13).set_delay(0.9)
		flick.tween_property(glow, "modulate:a", 0.6, 0.18)
		flick.tween_property(glow, "modulate:a", 0.5, 0.25)
	await t.finished
	shot_hint = "45_shop"
	_shop_p = p
	if _is_remote(p):
		# 다른 PC 사람의 쇼핑을 그대로 따라 보여줌
		_block(_shop_panel)
		while _shop_open:
			var d = await _get_dec(p)
			if String(d) == "close":
				_close_shop()
			else:
				for bb in _shop_buys:
					if bb[1] == String(d) and not (bb[0] as Button).disabled:
						(bb[0] as Button).pressed.emit()
						break
		return
	if _is_auto(p):
		await get_tree().create_timer(1.4, false).timeout
		var keep := _use_aux(p)
		var wants := _cpu_shop_wants(p)
		_rng = keep
		for want in wants:
			for bb in _shop_buys:
				if bb[1] == want:
					var b0: Button = bb[0]
					if not b0.disabled:
						b0.pressed.emit()
						await get_tree().create_timer(0.8, false).timeout
					break
		_close_shop()
	while _shop_open:
		await get_tree().process_frame


var _shop_p: Dictionary = {}


func _close_shop() -> void:
	if not _shop_open:
		return
	if not _shop_p.is_empty() and not _is_remote(_shop_p):
		_put_dec(_shop_p, "close")
	_shop_open = false
	if is_instance_valid(_shop_panel):
		var panel := _shop_panel
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := create_tween()
		t.tween_property(panel, "modulate:a", 0.0, 0.25)
		t.tween_callback(panel.queue_free)


func _tex_rect(tex: Texture2D, pos: Vector2, size_: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = pos
	r.size = size_
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 나무 판자 버튼
func _wood_button(text: String, size_: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size = size_
	b.custom_minimum_size = size_
	b.pivot_offset = size_ * 0.5
	b.add_theme_font_size_override("font_size", 24)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color(1.0, 0.95, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(0.85, 0.78, 0.7, 0.6))
	b.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
	b.add_theme_constant_override("outline_size", 6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st := StyleBoxTexture.new()
		st.texture = SHOP_TEX["button"]
		st.texture_margin_left = 30
		st.texture_margin_right = 30
		st.texture_margin_top = 24
		st.texture_margin_bottom = 24
		match state:
			"hover":
				st.modulate_color = Color(1.15, 1.12, 1.05)
			"pressed":
				st.modulate_color = Color(0.85, 0.82, 0.78)
			"disabled":
				st.modulate_color = Color(0.55, 0.5, 0.48)
		b.add_theme_stylebox_override(state, st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.06, 0.1))
	b.mouse_exited.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
	return b


# ── 창 · 고르기 ──────────────────────────────────────────────
func _modal_dim() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0, 0.04, 0.04, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_root.add_child(dim)
	return dim


func _modal_panel(dim: Control, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := _glass(Color(0.03, 0.17, 0.16, 0.96), border, 3, 26)
	st.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", st)
	dim.add_child(panel)
	return panel


func _show_modal(panel: Control) -> void:
	await get_tree().process_frame
	panel.position = (get_viewport().get_visible_rect().size - panel.size) * 0.5
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * 0.6
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _icon(tex: Texture2D, px: int) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _dot(c: Color, px: int) -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = c
	ds.set_corner_radius_all(px / 2)
	dot.add_theme_stylebox_override("panel", ds)
	return dot


## 물어보는 창 → 고른 버튼 번호. 자동이면 auto_choice 를 잠깐 뒤에 고름. locked 번호는 못 누름 (튜토리얼)
func _ask(p: Dictionary, title: String, body: String, options: Array, auto_choice: int, icon: Texture2D = null, locked: Array = []) -> int:
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(GOLD, 0.8))
	_dialog_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	if icon:
		var ic := _icon(icon, 80)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var t := Label.new()
	t.text = title
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_color_override("font_color", Color(PEARL, 0.85))
	v.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_dialog_buttons = []
	_dialog_choice = -1
	for k in options.size():
		var btn := _glass_button(options[k])
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		btn.custom_minimum_size = Vector2(190, 58)
		btn.disabled = k in locked
		var idx := k
		btn.pressed.connect(func() -> void: _dialog_choice = idx)
		row.add_child(btn)
		_dialog_buttons.append(btn)
	_dialog_open = true
	await _show_modal(panel)
	if _is_remote(p):
		_block(panel)
		_dialog_choice = int(await _get_dec(p))
		await get_tree().create_timer(0.4, false).timeout
	elif _is_auto(p):
		await get_tree().create_timer(1.5, false).timeout
		_dialog_choice = auto_choice
	while _dialog_choice < 0:
		await get_tree().process_frame
	if not _is_remote(p):
		_put_dec(p, _dialog_choice)
	_dialog_open = false
	_dialog_buttons = []
	dim.queue_free()
	return _dialog_choice


## 다른 PC 사람이 고르는 창: 보이기만 하고 누를 수 없게
func _block(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	var blk := Control.new()
	blk.mouse_filter = Control.MOUSE_FILTER_STOP
	blk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(blk)
	for b in panel.find_children("*", "BaseButton", true, false):
		(b as BaseButton).mouse_filter = Control.MOUSE_FILTER_IGNORE


## 열린 창의 버튼 누르기 (튜토리얼 자동 점검용)
func _press_dialog(i: int) -> void:
	if i < _dialog_buttons.size():
		(_dialog_buttons[i] as Button).pressed.emit()


func _dialog_button(i: int) -> Control:
	return _dialog_buttons[i] if i < _dialog_buttons.size() else null


## 사람 고르기 (동전 뺏기 · 트로피 뺏기)
func _pick_player(p: Dictionary, cands: Array, prompt: String, by: String) -> Dictionary:
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(AQUA, 0.7))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = prompt
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	v.add_child(t)
	_dialog_buttons = []
	_dialog_choice = -1
	for k in cands.size():
		var q: Dictionary = cands[k]
		var btn := _glass_button("")
		btn.custom_minimum_size = Vector2(440, 66)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 12)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 20
		btn.add_child(h)
		h.add_child(_dot(q["color"], 24))
		var n := Label.new()
		n.text = q["name"]
		n.custom_minimum_size = Vector2(170, 0)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(n)
		for key in _stat_keys():
			h.add_child(_icon(_stat_tex(key), 26))
			var m := Label.new()
			m.text = str(q[key])
			m.custom_minimum_size = Vector2(44, 0)
			m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			m.add_theme_color_override("font_color", GOLD)
			h.add_child(m)
		var idx := k
		btn.pressed.connect(func() -> void: _dialog_choice = idx)
		v.add_child(btn)
		_dialog_buttons.append(btn)
	_dialog_open = true
	await _show_modal(panel)
	shot_hint = "46_pick_player"
	if _is_remote(p):
		_block(panel)
		_dialog_choice = int(await _get_dec(p))
		await get_tree().create_timer(0.4, false).timeout
	elif _is_auto(p):
		await get_tree().create_timer(1.5, false).timeout
		var best := 0
		for k in cands.size():
			if int(cands[k][by]) > int(cands[best][by]):
				best = k
		_dialog_choice = best
	while _dialog_choice < 0:
		await get_tree().process_frame
	if not _is_remote(p):
		_put_dec(p, _dialog_choice)
	_dialog_open = false
	_dialog_buttons = []
	dim.queue_free()
	return cands[_dialog_choice]


## 원하는 칸 고르기 (순간이동 카드): 보드 전체를 보여주고 칸을 클릭
func _pick_tile(p: Dictionary, text: String = "", auto_tile: int = -1, shot: String = "47_pick_tile", secret: bool = false) -> int:
	_follow = null
	_move_camera(world.overview, world.overview_zoom * 1.06, 1.0)
	await get_tree().create_timer(1.0, false).timeout
	# secret: 남이 고르는 칸은 보여 주지 않음 (곰덫)
	var hide := secret and _ctl(p) != "me"
	var prompt := _outlined_label(text if text != "" else tr("Click the space you want to warp to!"), 34)
	prompt.visible = not hide
	prompt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.position.y = 140
	_popup_root.add_child(prompt)
	if not _pick_marker:
		var tm := TorusMesh.new()
		tm.inner_radius = 1.2
		tm.outer_radius = 1.45
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = AQUA
		_pick_marker = MeshInstance3D.new()
		_pick_marker.mesh = tm
		_pick_marker.material_override = mm
		add_child(_pick_marker)
	_pick_marker.visible = false
	_picked_tile = -1
	_hover_tile = -1
	shot_hint = shot
	if _is_remote(p):
		var rt := int(await _get_dec(p))
		if not hide:
			_show_pick_marker(rt)
		await get_tree().create_timer(0.6, false).timeout
		_picked_tile = rt
	elif _is_auto(p):
		await get_tree().create_timer(1.2, false).timeout
		var t := auto_tile if auto_tile >= 0 else world.trophy_tile
		if t < 0 or t == int(p["tile"]):
			var pool: Array = world.regular_tiles()
			var keep := _use_aux(p)
			t = pool[_rng.randi() % pool.size()]
			_rng = keep
		if not hide:
			_show_pick_marker(t)
		await get_tree().create_timer(0.6, false).timeout
		_picked_tile = t
	else:
		_tile_catcher = Control.new()
		_tile_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tile_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		_tile_catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_tile_catcher.gui_input.connect(_on_pick_input)
		_popup_root.add_child(_tile_catcher)
		_picking_tile = true
		while _picked_tile < 0:
			await get_tree().process_frame
		_picking_tile = false
		_tile_catcher.queue_free()
	if not _is_remote(p):
		_put_dec(p, _picked_tile)
	prompt.queue_free()
	_pick_marker.visible = false
	return _picked_tile


func _on_pick_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var best := -1
		var bd := 70.0
		for i in world.spaces.size():
			var wp: Vector3 = world.spaces[i]["pos"]
			if _camera.is_position_behind(wp) or i == world.start_index or not world.in_play(i):
				continue
			if not _pick_allowed.is_empty() and not (i in _pick_allowed):
				continue
			var d := _camera.unproject_position(wp).distance_to(mm.position)
			if d < bd:
				bd = d
				best = i
		if best != _hover_tile:
			_hover_tile = best
			if best >= 0:
				_show_pick_marker(best)
				Audio.play("hover", 0.05)
			else:
				_pick_marker.visible = false
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _hover_tile >= 0:
		Audio.play("click")
		_picked_tile = _hover_tile


func _show_pick_marker(i: int) -> void:
	_pick_marker.visible = true
	_pick_marker.position = (world.spaces[i]["pos"] as Vector3) + Vector3(0, 0.15, 0)


# ── 결과 화면 ────────────────────────────────────────────────
func _ranking() -> Array:
	var order := _pawns.duplicate()
	if survival():
		# 오래 살아남은 순 (탈락 라운드가 늦을수록 위) → 하트 → 동전
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var la := 999 if bool(a["alive"]) else int(a.get("out_round", 0))
			var lb := 999 if bool(b["alive"]) else int(b.get("out_round", 0))
			if la != lb:
				return la > lb
			if int(a["hearts"]) != int(b["hearts"]):
				return int(a["hearts"]) > int(b["hearts"])
			return int(a["coins"]) > int(b["coins"]))
		return order
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _team_trophies(a) != _team_trophies(b):
			return _team_trophies(a) > _team_trophies(b)
		if int(a["trophies"]) != int(b["trophies"]):
			return int(a["trophies"]) > int(b["trophies"])
		return int(a["coins"]) > int(b["coins"]))
	return order


var _ended := false   ## 결과 화면까지 옴


func _show_results() -> void:
	_ended = true
	Audio.play_music(0.3, "results")
	if _winner.is_empty():
		_winner = _ranking()[0]
	var w := _winner
	_follow = null
	_move_camera((w["node"] as Node3D).position, 1.1, 1.2)
	await get_tree().create_timer(1.2, false).timeout
	for k in 3:
		world.bubbles_at((w["node"] as Node3D).position + Vector3(0, 0.5, 0), 30, 0.8, true)
		world.portal_burst((w["node"] as Node3D).position)
		await get_tree().create_timer(0.25, false).timeout
	var head: String = tr("%s WINS!") % w["name"]
	if String(w["team"]) != "":
		head = tr("TEAM %s WINS!") % w["team"]
	elif int(w["slot"]) == GameState.my_slot and not w["cpu"]:
		head = tr("YOU WIN!")
	await _banner(head, "", 1.6)
	var dim := _modal_dim()
	var panel := _modal_panel(dim, Color(GOLD, 0.9))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = head
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	var order := _ranking()
	for k in order.size():
		var q: Dictionary = order[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var r := Label.new()
		r.text = str(k + 1)
		r.custom_minimum_size = Vector2(36, 0)
		r.add_theme_font_size_override("font_size", 30)
		row.add_child(r)
		row.add_child(_dot(q["color"], 24))
		var n := Label.new()
		n.text = ("%s · %s" % [q["team"], q["name"]]) if String(q["team"]) != "" else String(q["name"])
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.custom_minimum_size = Vector2(200, 0)
		n.add_theme_font_size_override("font_size", 24)
		row.add_child(n)
		var keys := _stat_keys().duplicate()
		keys.reverse()
		for key in keys:
			row.add_child(_icon(_stat_tex(key), 30))
			var m := Label.new()
			m.text = str(q[key])
			m.custom_minimum_size = Vector2(50, 0)
			m.add_theme_font_size_override("font_size", 24)
			m.add_theme_color_override("font_color", GOLD)
			row.add_child(m)
		v.add_child(row)
	var back := _glass_button("BACK TO MENU")
	back.custom_minimum_size = Vector2(260, 58)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_exit_to_menu)
	v.add_child(back)
	await _show_modal(panel)
	shot_hint = "48_results"
	Audio.play("start")
	if GameState.debug_autoplay:
		await get_tree().create_timer(3.0, false).timeout
		_exit_to_menu()


# ── 튜토리얼 도우미 ──────────────────────────────────────────
## 칸 윗면 네 모서리의 화면 위치 (스포트라이트를 칸 모양에 딱 맞춤)
func _tile_quad(i: int) -> PackedVector2Array:
	var sp: Dictionary = world.spaces[i]
	var half: float = (BoardWorld.TILE + (0.2 if sp["kind"] == "junction" else 0.0)) * 0.5
	var b := Basis(Vector3.UP, float(sp["yaw"]))
	var top: Vector3 = sp["pos"]
	var out := PackedVector2Array()
	for c in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]:
		var wp: Vector3 = top + b * c
		if _camera.is_position_behind(wp):
			return PackedVector2Array()
		out.append(_camera.unproject_position(wp))
	return out


## 말이 선 칸으로 카메라를 늘 같은 거리에서 맞추고, 그 칸만 딱 밝힘
func _explain_tile(p: Dictionary, text: String, shot: String) -> void:
	var i: int = p["tile"]
	_follow = null
	_move_camera(world.spaces[i]["pos"], TILE_ZOOM, 0.7)
	await get_tree().create_timer(0.75, false).timeout
	await _say({"text": text, "quad": func() -> PackedVector2Array: return _tile_quad(i), "shot": shot})


## MY PAWN 버튼 안내 전에 카메라를 딴 데로 돌려 둠
func _look_away() -> void:
	_focused = false
	_follow = null
	_move_camera(Vector3(-6, 0, -8), 2.2, 0.8)


func _say(st: Dictionary) -> void:
	_overlay.show_step(st)
	await _overlay.step_done


func _wait_for(cond: Callable) -> void:
	while not cond.call():
		await get_tree().process_frame


## 지금 자리에서 target 칸까지 가는 길 (되돌아가기 없이) → {rig: 칸 수, forced: {칸: 다음 칸}}
func _plan(p: Dictionary, target: int) -> Dictionary:
	var start := [int(p["tile"]), int(p["prev"])]
	var seen := {}
	var queue := [[start[0], start[1], []]]
	while queue.size() > 0:
		var it: Array = queue.pop_front()
		var cur: int = it[0]
		var prev: int = it[1]
		var path: Array = it[2]
		if cur == target and path.size() > 0:
			var forced := {}
			var at: int = start[0]
			for nx in path:
				forced[at] = nx
				at = nx
			return {"rig": mini(path.size(), 6), "forced": forced}
		var key := "%d_%d" % [cur, prev]
		if seen.has(key) or path.size() >= 6:
			continue
		seen[key] = true
		for l in world.spaces[cur]["links"]:
			if int(l) == prev and world.spaces[cur]["links"].size() > 1:
				continue
			queue.append([int(l), cur, path + [int(l)]])
	return {"rig": 0, "forced": {}}


func _tile_near(x: float, z: float) -> int:
	var best := 0
	var bd := INF
	for i in world.spaces.size():
		if not world.in_play(i):
			continue
		var q: Vector3 = world.spaces[i]["base"]
		var d := Vector2(q.x - x, q.z - z).length()
		if d < bd:
			bd = d
			best = i
	return best


## 어떤 맵을 쓸지 (튜토리얼 · 게임이 덮어씀)
func map_id() -> String:
	return "tutorial"


# ── 들어가기 연출 ────────────────────────────────────────────
func _intro() -> void:
	# 1) 보드판처럼 위에서 내려다보기
	_focus = world.overview + Vector3(0, 0, 0.5)
	_zoom = world.zoom_max * 1.1
	_apply_camera()
	await get_tree().process_frame
	await get_tree().process_frame
	Audio.play_music(0.0, "board")   # 보드가 나타나는 순간 처음부터 (긴박한 보드 음악)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.7)
	t.parallel().tween_property(_title, "modulate:a", 1.0, 0.7)
	await get_tree().create_timer(1.8, false).timeout
	# 2) 판 속으로 쑥
	Audio.play("bubbles")
	create_tween().tween_property(_title, "modulate:a", 0.0, 0.5)
	var me: Dictionary = _my_pawn()
	_move_camera(me["spot"], 1.0, 2.6)
	await _cam_tween.finished
	# 3) 말들이 위에서 퐁퐁
	for i in _pawns.size():
		_drop_pawn(_pawns[i])
		await get_tree().create_timer(0.3, false).timeout
	await get_tree().create_timer(1.0, false).timeout
	_intro_done = true
	_my_pawn_btn.visible = true
	_after_intro()


func _drop_pawn(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	var spot: Vector3 = p["spot"]
	node.visible = true
	node.position = spot + Vector3(0, 9.0, 0)
	var t := create_tween()
	t.tween_property(node, "position", spot, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.45, false).timeout
	Audio.play("add")
	world.bubbles_at(spot + Vector3(0, 0.2, 0), 18, 0.5, true)


## 들어가기 연출이 끝나면 (상속해서 채움: 튜토리얼 / 게임 진행)
func _after_intro() -> void:
	pass


func _exit_to_menu(from_host: bool = false) -> void:
	get_tree().paused = false
	Audio.play_ambience("", -60.0, 0.4)
	if _fade.color.a > 0.5 and not _intro_done and not from_host:
		return
	GameState.tutorial_active = false
	if _online:
		_online = false
		if Net.is_host():
			# 방장이 나가면 모두 같은 방의 로비로
			Net.broadcast({"k": "bd_exit"})
			GameState.return_to = "lobby"
		elif (from_host or _ended) and Net.is_guest():
			# 게임이 끝난 뒤 나가면 방은 그대로 · 같은 방 로비에서 방장을 기다림
			GameState.return_to = "lobby"
		else:
			# 손님이 스스로 나감 → 방에서 나와 내 원래 말로
			Net.leave()
			var me := {"kind": "host", "color": 0}
			if not GameState.my_profile.is_empty():
				me.merge(GameState.my_profile, true)
				me["kind"] = "host"
			GameState.players = [me, {}, {}, {}]
			GameState.my_slot = 0
	GameState.board_online = false
	_fade.get_parent().move_child(_fade, -1)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.4)
	await t.finished
	get_tree().change_scene_to_file(MAIN_MENU)
