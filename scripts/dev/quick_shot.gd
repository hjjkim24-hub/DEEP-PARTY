extends Node
## 개발용: 보드 게임 화면 몇 장만 빨리 찍고 종료 (전체 투어는 30분, 이건 몇 분)
##   godot --path . -- --quick-shot=map,kraken --shots-dir=/절대/경로
## 찍을 수 있는 장면: map(맵 전체), kraken(크라켄 정면), eye(눈 클로즈업), tile(칸 가까이), village(마을), board(평소 게임 화면)

var _dir := "user://shots"
var _want: PackedStringArray = ["map"]


func _ready() -> void:
	Engine.physics_ticks_per_second = 20
	Engine.max_physics_steps_per_frame = 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.substr("--shots-dir=".length())
		elif a.begins_with("--quick-shot="):
			_want = a.substr("--quick-shot=".length()).split(",", false)
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func() -> void:
		print("QUICK SHOT TIMEOUT")
		get_tree().quit(2))
	_run()


## 게임이 shot_hint 를 차례로 내보낼 때마다 한 장씩
func _catch(g: Node, hints: Array, prefix: String) -> void:
	var got := {}
	var t0 := Time.get_ticks_msec()
	while got.size() < hints.size() and Time.get_ticks_msec() - t0 < 90000:
		var h := String(g.shot_hint)
		if hints.has(h) and not got.has(h):
			got[h] = true
			await _shot(prefix + h)
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("SHOT: ", path, " ", img.get_size())


## 메뉴 화면들 (메인 · 모드 · 로비 · 꾸미기 · 보드 선택 · 설정 · 튜토리얼 말풍선). lang = "en" / "ko"
func _menus(lang: String) -> void:
	Settings.language = lang
	Settings.apply_language()
	GameState.tutorial_active = false
	# 매번 메인화면을 새로 띄움 (앞 언어에서 열어 둔 튜토리얼이 남지 않게)
	var old := get_tree().current_scene
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	while get_tree().current_scene == null or get_tree().current_scene == old or get_tree().current_scene.name != "MainMenu":
		await get_tree().process_frame
	var m: Node = get_tree().current_scene
	await _wait_idle(m, "main", 7.0)
	await _shot("m_%s_01_main" % lang)
	m._show_page("mode")
	await _wait_idle(m, "mode")
	await _shot("m_%s_02_mode" % lang)
	m._open_lobby(0)
	await _wait_idle(m, "lobby")
	m._lobby_add_cpu(1)
	m._lobby_add_cpu(2)
	await get_tree().create_timer(1.0).timeout
	await _shot("m_%s_03_lobby" % lang)
	m._lobby_customize()
	await _wait_idle(m, "customize")
	await _shot("m_%s_04_customize" % lang)
	m._go_back()
	await _wait_idle(m, "lobby")
	m._on_lobby_start()
	await _wait_idle(m, "board")
	await _shot("m_%s_05_board" % lang)
	m._go_back()
	await _wait_idle(m, "lobby")
	m._go_back()
	await _wait_idle(m, "mode")
	m._go_back()
	await _wait_idle(m, "main")
	m._show_page("settings")
	await _wait_idle(m, "settings")
	await _shot("m_%s_06_settings" % lang)
	m._go_back()
	await _wait_idle(m, "main")
	m._start_tutorial()
	await get_tree().create_timer(3.0).timeout
	await _shot("m_%s_07_tutorial" % lang)


func _wait_idle(m: Node, page: String, extra: float = 2.0) -> void:
	var waited := 0.0
	while (m._current != page or m._busy) and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().create_timer(extra).timeout


func _run() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	if "menus" in _want:
		await _menus("en")
		await _menus("ko")
		get_tree().quit(0)
		return
	GameState.debug_autoplay = true
	GameState.debug_auto_minigames = true
	GameState.selected_mode = GameState.Mode.FREE_FOR_ALL
	GameState.selected_board = "sunken_island"
	GameState.players[1] = {"kind": "cpu", "level": 1, "color": 2}
	GameState.players[2] = {"kind": "cpu", "level": 1, "color": 5}
	get_tree().change_scene_to_file("res://scenes/board.tscn")
	# wake: 크라켄이 깨어나는 장면을 일정 간격으로 촬영
	if "wake" in _want:
		var g0: Node = null
		while g0 == null or not ("world" in g0) or g0.world == null or g0.world.kraken_root == null:
			await get_tree().process_frame
			g0 = get_tree().current_scene
		while g0.world.kraken_root.position.y <= g0.world.KRAKEN_SLEEP_Y + 0.5:
			await get_tree().process_frame
		await get_tree().create_timer(0.6).timeout
		for k in 12:
			await _shot("w_%d" % k)
			await get_tree().create_timer(0.95).timeout
		get_tree().quit(0)
		return
	# storm: 촉수 폭풍을 바로 일으켜 표시 장면 · 내려치는 장면 촬영 (게임 흐름과 별개로)
	if "storm" in _want:
		var gs: Node = null
		while gs == null or not ("hold_loop" in gs):
			await get_tree().process_frame
			gs = get_tree().current_scene
		gs.hold_loop = true
		while String(gs.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(5.0).timeout
		var t1 := Time.get_ticks_msec()
		gs._attacks = 1
		await gs._kraken_barrage(0)
		await get_tree().create_timer(1.0).timeout
		print("STORM marked=", gs.world.danger_tiles().size(), " t=", (Time.get_ticks_msec() - t1) / 1000.0)
		var ds: Array = gs.world.danger_tiles()
		var mins := []
		var adj := 0
		for a0 in ds:
			var pa: Vector3 = gs.world.spaces[a0]["pos"]
			var md := INF
			for b0 in ds:
				if a0 != b0:
					var pb: Vector3 = gs.world.spaces[b0]["pos"]
					md = minf(md, Vector2(pa.x - pb.x, pa.z - pb.z).length())
			mins.append(md)
			for l in gs.world.spaces[a0]["links"]:
				if ds.has(int(l)):
					adj += 1
		mins.sort()
		print("STORM spacing min=", mins[0], " median=", mins[mins.size() / 2], " adjacent_pairs=", adj / 2)
		for q in gs._alive_pawns():
			var near: Array = gs._reachable(int(q["tile"]), 1, 6)
			print("STORM pawn ", q["name"], " reach=", near.size(), " marked_in_reach=", near.filter(func(i: int) -> bool: return ds.has(i)).size())
		await _shot("s_marked")
		var tg: Array = gs.world.danger_tiles()
		if "close" in _want:
			# 한 칸만 가까이서: 솟구침 → 버팀 → 내려침 → 들어감을 여러 장
			var t0i: int = tg[0]
			var tp: Vector3 = gs.world.spaces[t0i]["pos"]
			gs._move_camera(tp, 1.6, 0.01)
			await get_tree().create_timer(0.5).timeout
			var dd: Dictionary = gs.world._dangers[t0i]
			var dv: Vector3 = dd["dir"]
			var sideways := Vector3(-dv.z, 0, dv.x)
			gs._cinematic(tp + sideways * 11.0 - dv * 1.0 + Vector3(0, 4.0, 0), tp - dv * 1.2 + Vector3(0, 1.6, 0), 1.0, 0.01)
			await get_tree().create_timer(0.5).timeout
			# 한 번 먼저 내려쳐서 셰이더를 준비 (첫 프레임이 느려 동작이 건너뛰지 않게)
			gs.world.tentacle_strike(int(tg[tg.size() - 1]))
			await get_tree().create_timer(4.0).timeout
			gs.world.strike_slow = 12.0
			gs.world.tentacle_strike(t0i)
			var t3 := Time.get_ticks_msec()
			for k in 12:
				if is_instance_valid(gs.world.last_strike):
					print("RISE k=", k, " real=", (Time.get_ticks_msec() - t3) / 1000.0, " y=", gs.world.last_strike.position.y, " fps=", Engine.get_frames_per_second())
				await _shot("c_%02d" % k)
				await get_tree().create_timer(1.5).timeout
			Engine.time_scale = 1.0
			get_tree().quit(0)
			return
		gs.call("_mass_strike", tg)
		while String(gs.shot_hint) != "49b_kraken_strike" and Time.get_ticks_msec() - t1 < 120000:
			await get_tree().process_frame
		await _shot("s_strike")
		print("STORM struck t=", (Time.get_ticks_msec() - t1) / 1000.0, " fps=", Engine.get_frames_per_second())
		get_tree().quit(0)
		return
	# ship: 크라켄의 배 (밤하늘) 여러 각도
	if "ship" in _want:
		var gp: Node = null
		while gp == null or not ("hold_loop" in gp):
			await get_tree().process_frame
			gp = get_tree().current_scene
		gp.hold_loop = true
		while String(gp.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(3.0).timeout
		var ws: Node = gp.world
		ws.enter_ship()
		for q in gp._pawns:
			(q["node"] as Node3D).visible = false
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		var at: Vector3 = ws.ship.AT
		gp._cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.01)
		gp._move_camera(ws.overview, ws.overview_zoom, 0.01)
		await get_tree().create_timer(2.0).timeout
		await _shot("ship_overview")
		var views := {"ship_side": [Vector3(9, 15, 165), Vector3(4, 15, 0)], "ship_bow": [Vector3(138, 39, 87), Vector3(6, 12, 0)],
			"ship_stern": [Vector3(-126, 36, 72), Vector3(-33, 12, 0)], "ship_top": [Vector3(-15, 51, 39), Vector3(-21, 23, 0)],
			"ship_deck": [Vector3(3, 18, 45), Vector3(6, 0, 3)], "ship_idol": [Vector3(-24, 11, 14), Vector3(-34, 5, 0)],
			"ship_arm": [Vector3(-2, 6, 40), Vector3(-12, -3, 12)], "ship_mast": [Vector3(38, 12, 22), Vector3(26, 8, 0)]}
		for k in views:
			gp._cinematic(at + views[k][0], at + views[k][1], 1.0, 0.01)
			await get_tree().create_timer(1.2).timeout
			await _shot(k)
		get_tree().quit(0)
		return
	# shipart: '크라켄의 배' 카드 일러스트 (달빛 아래 하늘을 나는 배 + 하늘에 열린 포탈에서 떨어지는 말)
	if "shipart" in _want:
		var gq: Node = null
		while gq == null or not ("hold_loop" in gq):
			await get_tree().process_frame
			gq = get_tree().current_scene
		gq.hold_loop = true
		while String(gq.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(3.0).timeout
		var wq: Node = gq.world
		wq.enter_ship()
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		get_viewport().msaa_3d = Viewport.MSAA_8X
		get_viewport().scaling_3d_scale = 2.0
		var atq: Vector3 = wq.ship.AT
		var tiles: Array = wq.ship.drop_tiles
		for k in gq._pawns.size():
			var pn: Node3D = gq._pawns[k]["node"]
			pn.visible = k < 2
			var tp: Vector3 = wq.spaces[tiles[k % tiles.size()]]["pos"]
			pn.position = tp + Vector3(0, 3.4 + k * 1.5, 0)
			pn.rotation = Vector3(0.3, 0.6 + k, 0.2)
			if k < 2:
				wq.drop_portal(tp + Vector3(0, 7.5 + k * 1.5, 0), true)
		gq._camera.fov = 44.0
		gq._cinematic(atq + Vector3(60.0, 24.0, 104.0), atq + Vector3(-3.0, 11.0, 0.0), 1.0, 0.01)
		await get_tree().create_timer(2.5).timeout
		await _shot("il_ship")
		gq._cinematic(atq + Vector3(24.0, 21.0, 177.0), atq + Vector3(-3.0, 28.0, 0.0), 1.0, 0.01)
		await get_tree().create_timer(1.5).timeout
		await _shot("il_ship_b")
		get_tree().quit(0)
		return
	# shipdrop: 실제 게임 흐름으로 '크라켄의 배' 카드 → 포탈 → 배 → 섬으로 귀환
	if "shipdrop" in _want:
		var gd: Node = null
		while gd == null or not ("hold_loop" in gd):
			await get_tree().process_frame
			gd = get_tree().current_scene
		gd.hold_loop = true
		while String(gd.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(4.0).timeout
		gd._round = 1
		gd._update_round_label()
		gd.rig_kraken = "ship"
		gd._kraken_turn(1)
		await _catch(gd, ["60_kraken_card_ship", "60b_ship_portals", "60c_ship_reveal", "60d_ship_drop", "60_kraken_ship"], "sd_")
		await get_tree().create_timer(2.5).timeout
		gd._round = 2
		gd._update_round_label()
		gd.focus_on(gd._my_pawn())
		await get_tree().create_timer(1.5).timeout
		await _shot("sd_play")
		print("SHIP tiles=", gd.world.regular_tiles().size(), " my tile=", gd._my_pawn()["tile"], " opts=", gd._next_options(gd._my_pawn()))
		gd._round = 3
		gd._kraken_phase(3)
		await _catch(gd, ["60e_ship_leave"], "sd_")
		while gd.world.on_ship or gd._ship_until >= 0:
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		await _shot("sd_back")
		get_tree().quit(0)
		return
	# chest: 크라켄의 배 뱃머리 '크라켄의 보물상자' 칸 · 상자 · 베팅 창 · 룰렛 · 결과
	if "chest" in _want:
		var gc: Node = null
		while gc == null or not ("hold_loop" in gc):
			await get_tree().process_frame
			gc = get_tree().current_scene
		gc.hold_loop = true
		while String(gc.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(4.0).timeout
		await gc._kraken_ship(1)
		var wc: Node = gc.world
		var ct: int = wc.ship.ids["F3"]
		var me: Dictionary = gc._my_pawn()
		me["tile"] = ct
		(me["node"] as Node3D).position = gc._spot_on(ct, me)
		me["coins"] = 30
		gc._refresh_chip(me)
		var tp: Vector3 = wc.spaces[ct]["pos"]
		gc._cinematic(tp + Vector3(-7.0, 6.0, 6.0), tp + Vector3(3.0, 0.5, 0.0), 1.0, 0.01)
		await get_tree().create_timer(1.5).timeout
		await _shot("ch_tile")
		gc._cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.01)
		gc.rig_chest = 1
		gc._kraken_chest(me)
		await _catch(gc, ["62a_chest_bet", "62b_chest_spin", "62c_chest_win"], "ch_")
		await get_tree().create_timer(4.0).timeout
		gc.rig_chest = 0
		gc._kraken_chest(me)
		await _catch(gc, ["62d_chest_kraken"], "ch_")
		await get_tree().create_timer(1.0).timeout
		print("CHEST coins=", me["coins"], " hearts=", me["hearts"])
		get_tree().quit(0)
		return
	# backmap: 카드 뒷면용 SUNKEN ISLAND 판 전체 (글씨 · 말 없이, 거의 위에서)
	if "backmap" in _want:
		var gb: Node = null
		while gb == null or not ("hold_loop" in gb):
			await get_tree().process_frame
			gb = get_tree().current_scene
		gb.hold_loop = true
		while String(gb.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(4.0).timeout
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		var wb: Node = gb.world
		for q in gb._pawns:
			(q["node"] as Node3D).visible = false
		for mi0 in wb.find_children("*", "MeshInstance3D", true, false):
			var mo := (mi0 as MeshInstance3D).material_override
			if mo is ShaderMaterial and (mo as ShaderMaterial).shader == wb.RayShader:
				(mi0 as MeshInstance3D).visible = false
		get_viewport().msaa_3d = Viewport.MSAA_8X
		get_viewport().scaling_3d_scale = 2.0
		gb._camera.fov = 40.0
		# 세로 카드에 맞게: 판을 거의 위에서, 크라켄이 위쪽에 오도록
		gb._cinematic(Vector3(0, w_h(wb), wb.half_d * 0.95), Vector3(0, 0, -wb.half_d * 0.12), 1.0, 0.01)
		await get_tree().create_timer(1.5).timeout
		await _shot("back_map")
		get_tree().quit(0)
		return
	# illust: 크라켄 행동 카드 일러스트용 연출 장면 (게임 화면이 아닌, 실제 3D 모델로 꾸민 클로즈업)
	if "illust" in _want:
		await _illust()
		get_tree().quit(0)
		return
	# kcards: 크라켄 행동 카드 (뒷면 · 앞면 3 장)
	if "kcards" in _want:
		var gk: Node = null
		while gk == null or not ("hold_loop" in gk):
			await get_tree().process_frame
			gk = get_tree().current_scene
		gk.hold_loop = true
		while String(gk.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(4.0).timeout
		for a in ["barrage", "spines", "surge", "ship"]:
			Engine.time_scale = 0.25
			gk._kraken_card(a)
			if a == "barrage":
				for q in 4:
					await get_tree().create_timer(0.35).timeout
					await _shot("kc_spin_%d" % q)
			while String(gk.shot_hint) != "60_kraken_card_" + a:
				await get_tree().process_frame
			await _shot("kc_" + a)
			Engine.time_scale = 1.0
			await get_tree().create_timer(3.0).timeout
		get_tree().quit(0)
		return
	# cardart: 크라켄 행동 카드에 넣을 그림을 게임 화면에서 찍음
	if "cardart" in _want:
		var ga: Node = null
		while ga == null or not ("hold_loop" in ga):
			await get_tree().process_frame
			ga = get_tree().current_scene
		ga.hold_loop = true
		while String(ga.shot_hint) != "34_kraken_awakens":
			await get_tree().process_frame
		await get_tree().create_timer(5.0).timeout
		var wa: Node = ga.world
		for q in ga._pawns:
			(q["node"] as Node3D).visible = false
		# 화면 글씨 · 버튼 숨기기 (그림만)
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		# 구조물이 적은 탁 트인 칸 찾기 (주변 6 m 안에 장식이 적은 곳)
		var open_tiles := []
		for i in wa.spaces.size():
			var pp: Vector3 = wa.spaces[i]["pos"]
			if i != wa.start_index and String(wa.spaces[i]["kind"]) in ["plain", "minigame", "chance"] and absf(pp.y) < 0.6:
				open_tiles.append(i)
		# 1) 촉수 폭풍: 위에서 비스듬히 내려다본 길 위로 붉은 칸 4 개, 촉수가 차례로 내려침
		var anchor: int = open_tiles[open_tiles.size() / 3]
		var ap: Vector3 = wa.spaces[anchor]["pos"]
		var picks := []
		var near_sorted := open_tiles.duplicate()
		near_sorted.sort_custom(func(a: int, b: int) -> bool: return (wa.spaces[a]["pos"] as Vector3).distance_to(ap) < (wa.spaces[b]["pos"] as Vector3).distance_to(ap))
		for i in near_sorted:
			var ok := true
			for j in picks:
				if (wa.spaces[i]["pos"] as Vector3).distance_to(wa.spaces[j]["pos"]) < 4.5:
					ok = false
			if ok:
				picks.append(i)
			if picks.size() >= 4:
				break
		var c := Vector3.ZERO
		for i in picks:
			wa.mark_danger(i)
			c += wa.spaces[i]["pos"]
		c /= picks.size()
		var to_k := (Vector3(wa.kraken_root.position.x, 0, wa.kraken_root.position.z) - Vector3(c.x, 0, c.z)).normalized()
		var cam := c - to_k * 13.0 + Vector3(0, 12.0, 0)
		ga._cinematic(cam, c + to_k * 2.0, 1.0, 0.01)
		await get_tree().create_timer(2.0).timeout
		await _shot("art_marked")
		wa.strike_slow = 5.0
		for k in picks.size():
			wa.tentacle_strike(picks[k], k * 0.5)
		for k in 7:
			await get_tree().create_timer(1.0).timeout
			await _shot("art_storm_%d" % k)
		await get_tree().create_timer(9.0).timeout
		# 2) 독 가시: 보라색 가시 칸 가까이 (위에서 비스듬히)
		for i in picks:
			wa.set_tile_look(i, "urchin")
		await get_tree().create_timer(1.0).timeout
		var tp: Vector3 = wa.spaces[picks[0]]["pos"]
		ga._cinematic(tp - to_k * 3.2 + Vector3(0, 4.2, 0), tp + to_k * 0.3, 1.0, 0.01)
		await get_tree().create_timer(1.5).timeout
		await _shot("art_spines_0")
		ga._cinematic(c - to_k * 9.0 + Vector3(0, 8.0, 0), c, 1.0, 0.01)
		await get_tree().create_timer(1.5).timeout
		await _shot("art_spines_1")
		# 3) 상점 대혼란: 위에서 본 상점 칸 + 촉수가 상점을 내려침
		var shops: Array = wa.spaces_of_kind("shop")
		for st0 in shops:
			var st: int = int(st0)
			var spos: Vector3 = wa.spaces[st]["pos"]
			ga._cinematic(spos + Vector3(3.5, 7.0, 6.0), spos + Vector3(0, 0.8, 0), 1.0, 0.01)
			await get_tree().create_timer(1.2).timeout
			await _shot("art_shop%d_0" % st)
		var sb: int = 135 if shops.has(135) else int(shops[shops.size() - 1])
		var sbp: Vector3 = wa.spaces[sb]["pos"]
		ga._cinematic(sbp + Vector3(3.0, 8.0, 9.0), sbp + Vector3(0, 1.5, 0), 1.0, 0.01)
		await get_tree().create_timer(1.0).timeout
		wa.strike_slow = 5.0
		wa.tentacle_strike(sb)
		for k in 10:
			await get_tree().create_timer(0.6).timeout
			await _shot("art_shop_hit_%d" % k)
		# 4) 카드 뒷면용: 크라켄 눈
		var eye: Vector3 = wa.kraken_eye_pos() + Vector3(1.57 * wa.KRAKEN_SCALE, 0, 0)
		ga._cinematic(eye + Vector3(6.0, -1.0, 9.0), eye, 1.0, 0.01)
		await get_tree().create_timer(2.0).timeout
		await _shot("art_eye")
		get_tree().quit(0)
		return
	# count: 맵의 칸 수 (종류별)
	if "count" in _want:
		var gc: Node = null
		while gc == null or not ("world" in gc) or gc.world == null or gc.world.spaces.is_empty():
			await get_tree().process_frame
			gc = get_tree().current_scene
		var kinds := {}
		for sp in gc.world.spaces:
			kinds[String(sp["kind"])] = int(kinds.get(String(sp["kind"]), 0)) + 1
		print("SPACES total=", gc.world.spaces.size(), " ", kinds)
		get_tree().quit(0)
		return
	# 크라켄이 다 솟아오를 때까지
	var g: Node = null
	while true:
		await get_tree().process_frame
		g = get_tree().current_scene
		if g and "world" in g and g.world and g.world.kraken_root \
				and g.world.kraken_root.position.y >= g.world.KRAKEN_AWAKE_Y - 0.3:
			break
	# 등장 연출이 끝나고 첫 라운드가 시작될 때까지
	while not String(g.shot_hint).begins_with("39_round"):
		await get_tree().process_frame
	await get_tree().create_timer(2.5).timeout
	var w: Node = g.world
	# turns: 자동 진행하며 크라켄 차례 행동을 하나씩 강제로 → 장면마다 촬영
	if "turns" in _want:
		var order := ["barrage", "spines", "surge"]
		var seen := {}
		var t0 := Time.get_ticks_msec()
		g.rig_kraken = order[0]
		Engine.time_scale = 4.0
		while Time.get_ticks_msec() - t0 < 900000 and seen.size() < 4:
			await get_tree().process_frame
			if not is_instance_valid(g):
				print("TURNS: game node gone at ", (Time.get_ticks_msec() - t0) / 1000.0)
				break
			if int(g._round) != int(seen.get("_r", -1)):
				seen["_r"] = int(g._round)
				print("TURNS: round ", g._round, " attacks=", g._attacks, " cd=", g._attack_cd, " t=", (Time.get_ticks_msec() - t0) / 1000.0, " hint=", g.shot_hint)
			var k: int = int(g._attacks)
			if k < order.size():
				g.rig_kraken = order[k]
			# 장면이 아니라 상태로 판단 (느린 화면에서는 잠깐 지나가는 장면을 놓침)
			var h := ""
			if w.danger_tiles().size() >= 5:
				h = "barrage"
			elif not g._spines.is_empty():
				h = "spines"
			elif int(g.shop_price_mult) > 1:
				h = "surge"
			var key := "%s_r%d" % [h, int(g._round)]
			if h != "" and not seen.has(h):
				seen[h] = true
				await get_tree().create_timer(1.0).timeout
				await _shot("t_" + key)
				print("TURN SHOT ", key, " label=", g._round_label.text.replace("\n", " | "), " mult=", g.shop_price_mult)
		print("TURNS: done t=", (Time.get_ticks_msec() - t0) / 1000.0)
		get_tree().quit(0)
		return
	var sc: float = w.KRAKEN_SCALE
	var eye: Vector3 = w.kraken_eye_pos()
	# all: 볼거리마다 한 장씩 + 다리 · 계단
	if "all" in _want:
		for lm in w.cfg.get("landmarks", []):
			var at: Vector2 = lm["at"]
			var gy: float = w.ground_height(at.x, at.y)
			var r: float = {"temple": 17.0, "shipwreck": 20.0, "whale": 15.0, "village": 15.0, "lighthouse": 15.0, "colossus": 11.0, "kraken_lair": 0.0}.get(String(lm["type"]), 9.0)
			if r <= 0.0:
				continue
			g._cinematic(Vector3(at.x + r * 0.55, gy + r * 0.5, at.y + r * 0.8), Vector3(at.x, gy + r * 0.16, at.y), 1.0, 0.01)
			await get_tree().create_timer(1.2).timeout
			await _shot("lm_%s_%d" % [String(lm["type"]), int(at.x)])
		var nb := 0
		var ns := 0
		for i in w.spaces.size():
			var sp: Dictionary = w.spaces[i]
			for j in sp["links"]:
				if j < i:
					continue
				var a: Vector3 = sp["pos"]
				var b2: Vector3 = w.spaces[j]["pos"]
				var is_bridge: bool = sp.get("bridge", false) and w.spaces[j].get("bridge", false)
				var is_stair: bool = absf(a.y - b2.y) > 1.2
				if (is_bridge and nb < 3) or (is_stair and not is_bridge and ns < 3):
					var mid := (a + b2) * 0.5
					var side := (b2 - a).cross(Vector3.UP).normalized()
					g._cinematic(mid + side * 5.5 + Vector3(0, 3.2, 0) + (b2 - a).normalized() * 2.5, mid, 1.0, 0.01)
					await get_tree().create_timer(1.2).timeout
					await _shot(("br_%d" % nb) if is_bridge else ("st_%d" % ns))
					if is_bridge:
						nb += 1
					else:
						ns += 1
		for kind in ["portal", "shop", "chance"]:
			var ks: Array = w.spaces_of_kind(kind)
			if ks.size() > 0:
				var tp2: Vector3 = w.spaces[int(ks[0])]["pos"]
				g._cinematic(tp2 + Vector3(3.0, 3.0, 5.5), tp2 + Vector3(0, 1.0, 0), 1.0, 0.01)
				await get_tree().create_timer(1.2).timeout
				await _shot("k_" + kind)
		get_tree().quit(0)
		return
	for s in _want:
		match s:
			"map":
				g._cinematic(Vector3(0, 0.95 * w.half_d + 40.0, w.half_d + 52.0), Vector3(0, 2.0, -w.half_d * 0.22), 1.0, 0.01)
			"kraken":
				g._cinematic(Vector3(eye.x - 16.0, 20.0, -w.half_d + 46.0), eye + Vector3(0, 2.0, -6.0), 1.0, 0.01)
			"eye":
				var e2 := eye + Vector3(1.57 * sc, 0, 0)
				g._cinematic(e2 + Vector3(10.0, -4.0, 16.0), e2, 1.0, 0.01)
			"danger":
				var ts: Array = w.spaces_of_kind("minigame")
				for k in mini(8, ts.size()):
					w.mark_danger(int(ts[k]))
				g._cinematic(Vector3(0, 0.95 * w.half_d + 40.0, w.half_d + 52.0), Vector3(0, 2.0, -w.half_d * 0.22), 1.0, 0.01)
			"coil":
				var c3: Dictionary = w.kraken_coils[3]
				var hit: Vector3 = c3["hit"]
				var dd: Vector3 = c3["dir"]
				g._cinematic(hit + dd * 10.0 + Vector3(0, 9.0, 0) + Vector3(-dd.z, 0, dd.x) * 12.0, hit - dd * 6.0 + Vector3(0, 4.0, 0), 1.0, 0.01)
			"tile":
				var sp: Dictionary = w.spaces[int(w.spaces[w.start_index]["links"][0])]
				var tp: Vector3 = sp["pos"]
				g._cinematic(tp + Vector3(2.6, 2.4, 4.6), tp + Vector3(-0.6, 0.0, -0.8), 1.0, 0.01)
			"temple":
				g._cinematic(Vector3(13.0, 11.0, 15.0), Vector3(0.0, 2.5, -2.0), 1.0, 0.01)
			"wreck":
				g._cinematic(Vector3(-32.0, 11.0, 24.0), Vector3(-46.0, 2.0, 10.0), 1.0, 0.01)
			"light":
				g._cinematic(Vector3(24.0, 8.0, 14.0), Vector3(35.0, 5.0, 4.0), 1.0, 0.01)
			"village":
				g._cinematic(Vector3(-30.0, 9.0, 10.0), Vector3(-36.0, 0.5, -1.0), 1.0, 0.01)
			_:
				g._cinematic(Vector3.ZERO, Vector3.ZERO, 0.0, 0.01)
		await get_tree().create_timer(2.0).timeout
		await _shot("q_" + s)
	get_tree().quit(0)


func _neon_cone(parent: Node, pos: Vector3, basis_: Basis, r: float, h: float, mat: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_transform = Transform3D(basis_, pos) * Transform3D(Basis(), Vector3(0, h * 0.5, 0))


func _illust() -> void:
	var g: Node = null
	while g == null or not ("hold_loop" in g):
		await get_tree().process_frame
		g = get_tree().current_scene
	g.hold_loop = true
	while String(g.shot_hint) != "34_kraken_awakens":
		await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var w: Node = g.world
	for q in g._pawns:
		(q["node"] as Node3D).visible = false
	var env: Environment = w.world_env
	# 영화 같은 심해 분위기: 어둡고 깊은 안개, 약한 해, 대상에만 강한 빛
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.12, 0.14)
	env.fog_enabled = true
	env.fog_density = 0.045
	env.fog_light_color = Color(0.01, 0.09, 0.1)
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ambient_light_energy = 0.32
	env.adjustment_contrast = 1.18
	env.adjustment_saturation = 1.05
	for dl in w.find_children("*", "DirectionalLight3D", true, false):
		(dl as DirectionalLight3D).light_energy *= 0.75
	# 화질: 2 배로 그려서 줄이기 + 계단 현상 없애기
	get_viewport().msaa_3d = Viewport.MSAA_8X
	get_viewport().scaling_3d_scale = 2.0
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var cam: Camera3D = g._camera
	var kpos: Vector3 = w.kraken_root.position
	# 탁 트인 일반 칸들
	var open_tiles := []
	for i in w.spaces.size():
		var pp: Vector3 = w.spaces[i]["pos"]
		if i != w.start_index and String(w.spaces[i]["kind"]) in ["plain", "minigame", "chance"] and absf(pp.y) < 0.6 and pp.z > -w.half_d * 0.2:
			open_tiles.append(i)
	var anchor: int = open_tiles[open_tiles.size() / 2]
	var ap: Vector3 = w.spaces[anchor]["pos"]
	var near_sorted := open_tiles.duplicate()
	near_sorted.sort_custom(func(a: int, b: int) -> bool: return (w.spaces[a]["pos"] as Vector3).distance_to(ap) < (w.spaces[b]["pos"] as Vector3).distance_to(ap))
	var picks := []
	for i in near_sorted:
		var ok := true
		for j in picks:
			if (w.spaces[i]["pos"] as Vector3).distance_to(w.spaces[j]["pos"]) < 4.0:
				ok = false
		if ok:
			picks.append(i)
		if picks.size() >= 4:
			break
	var c := Vector3.ZERO
	for i in picks:
		c += w.spaces[i]["pos"]
	c /= picks.size()
	var to_k := (Vector3(kpos.x, 0, kpos.z) - Vector3(c.x, 0, c.z)).normalized()
	var side := Vector3(-to_k.z, 0, to_k.x)
	# 물속 빛기둥 판 · 떠 있는 찬스 카드 숨기기 (가까이서 보면 납작한 판으로 보임)
	for mi0 in w.find_children("*", "MeshInstance3D", true, false):
		var mo := (mi0 as MeshInstance3D).material_override
		if mo is ShaderMaterial and (mo as ShaderMaterial).shader == w.RayShader:
			(mi0 as MeshInstance3D).visible = false
	# ── 1) 촉수 폭풍: 바닥에서 올려다본 붉은 칸, 그 위로 막 내려꽂히는 촉수, 뒤로 몸을 젖힌 촉수들, 안개 속 크라켄 눈 ──
	var T: int = picks[0]
	var tp0: Vector3 = w.spaces[T]["pos"]
	for i in picks:
		w.mark_danger(i, true)
	await get_tree().create_timer(0.6).timeout
	for i in picks:
		var mk: MeshInstance3D = w._dangers[i]["mark"]
		(mk.material_override as ShaderMaterial).set_shader_parameter("strength", 0.55)
	var stage := []
	var mk_t := func(at: Vector3, dirv: Vector3, r0: float, ln: float, pz: Array, glow_v: float) -> void:
		var tn: Dictionary = w.make_tentacle(1, r0, ln, dirv)
		var m: ShaderMaterial = tn["mat"]
		m.set_shader_parameter("tip", 0.18)
		m.set_shader_parameter("hook_at", 0.2)
		m.set_shader_parameter("pitch", pz[0])
		m.set_shader_parameter("curl", pz[1])
		m.set_shader_parameter("hook", pz[2])
		m.set_shader_parameter("tipback", pz[3])
		m.set_shader_parameter("glow", glow_v)
		var root: Node3D = tn["root"]
		w.add_child(root)
		root.position = at
		stage.append(root)
		var rim := OmniLight3D.new()
		rim.light_color = Color(0.45, 1.0, 0.3)
		rim.light_energy = 3.0
		rim.omni_range = 7.0
		w.add_child(rim)
		rim.position = at + Vector3(0, ln * 0.45, 0) + to_k * 2.5
		stage.append(rim)
	# 앞: 붉은 칸을 향해 휘어 내려오는 촉수 (내려치기 직전)
	mk_t.call(tp0 + side * 3.2 + Vector3(0, -0.9, 0), -side, 1.15, 7.5, [0.15, 0.7, 0.75, 0.3], 0.5)
	# 뒤: 몸을 크게 젖힌 촉수 둘
	for k in range(1, mini(3, picks.size())):
		var tpk: Vector3 = w.spaces[picks[k]]["pos"]
		var dk := (tpk - tp0)
		dk.y = 0
		mk_t.call(tpk + dk.normalized() * 2.5 + to_k * 1.5 + Vector3(0, -1.0, 0), -dk.normalized(), 1.5, 11.0, [-0.55, 1.5, 0.0, -0.9], 0.35)
	# 안개 속 크라켄의 두 눈
	var eye_m := StandardMaterial3D.new()
	eye_m.albedo_color = Color(1.0, 0.85, 0.25)
	eye_m.emission_enabled = true
	eye_m.emission = Color(1.0, 0.8, 0.2)
	eye_m.emission_energy_multiplier = 6.0
	eye_m.disable_fog = true
	for sd: float in [-1.0, 1.0]:
		var es := SphereMesh.new()
		es.radius = 0.5
		es.height = 0.6
		var emi := MeshInstance3D.new()
		emi.mesh = es
		emi.material_override = eye_m
		w.add_child(emi)
		emi.position = tp0 + to_k * 26.0 + side * sd * 2.6 + Vector3(0, 9.0, 0)
		stage.append(emi)
	w.bubbles_at(tp0 + Vector3(0, 0.5, 0), 40, 1.2, true)
	cam.fov = 58.0
	g._cinematic(tp0 - to_k * 6.0 - side * 1.2 + Vector3(0, 0.75, 0), tp0 + to_k * 4.0 + Vector3(0, 3.4, 0), 1.0, 0.01)
	await get_tree().create_timer(1.0).timeout
	await _shot("il_storm_a")
	g._cinematic(tp0 - to_k * 7.5 + side * 2.5 + Vector3(0, 1.4, 0), tp0 + to_k * 3.0 + Vector3(0, 2.8, 0), 1.0, 0.01)
	await get_tree().create_timer(0.6).timeout
	await _shot("il_storm_b")
	for r in stage:
		(r as Node).queue_free()
	for i in picks:
		w._clear_danger(i)
	# ── 2) 독 가시: 칸이 보라색 독 가시 덩어리로 터져 오름 ──
	var st_i: int = picks[0]
	var sp: Vector3 = w.spaces[st_i]["pos"]
	w.set_tile_look(st_i, "urchin")
	var spm := StandardMaterial3D.new()
	spm.albedo_color = Color(0.32, 0.1, 0.45)
	spm.roughness = 0.22
	spm.metallic = 0.3
	spm.emission_enabled = true
	spm.emission = Color(0.55, 0.15, 0.8)
	spm.emission_energy_multiplier = 0.25
	spm.rim_enabled = true
	spm.rim = 0.6
	var spike_root := Node3D.new()
	w.add_child(spike_root)
	var rr := RandomNumberGenerator.new()
	rr.seed = 11
	# 칸 윗면에서 바로 돋아난 가시 (밑동은 칸 속에 박힘) — 짧고 굵은 가시가 밑을 빽빽이 채움
	for k in 140:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * 1.15
		var short := k >= 70
		var base := sp + Vector3(cos(a) * d, 0.38, sin(a) * d)
		var outw := Vector3(cos(a), 0, sin(a)) * d * 0.8
		var up := (Vector3.UP * 1.0 + outw + Vector3(rr.randf_range(-0.2, 0.2), 0, rr.randf_range(-0.2, 0.2))).normalized()
		var x := up.cross(Vector3(0, 0, 1)).normalized()
		var bz := x.cross(up)
		var hh := rr.randf_range(0.25, 0.6) if short else rr.randf_range(0.7, 2.1) * (1.25 - d * 0.5)
		_neon_cone(spike_root, base, Basis(x, up, bz), rr.randf_range(0.07, 0.13) if short else rr.randf_range(0.06, 0.12), hh, spm)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.4, 1.0, 0.3)
	dm.emission_enabled = true
	dm.emission = Color(0.4, 1.0, 0.25)
	dm.emission_energy_multiplier = 0.8
	for k in 26:
		var s3 := SphereMesh.new()
		s3.radius = rr.randf_range(0.02, 0.05)
		s3.height = s3.radius * 2.6
		var mi := MeshInstance3D.new()
		mi.mesh = s3
		mi.material_override = dm
		spike_root.add_child(mi)
		mi.global_position = sp + Vector3(rr.randf_range(-1.4, 1.4), rr.randf_range(0.6, 2.6), rr.randf_range(-1.4, 1.4))
	var pl := OmniLight3D.new()
	pl.light_color = Color(0.7, 0.25, 1.0)
	pl.light_energy = 4.0
	pl.omni_range = 7.0
	spike_root.add_child(pl)
	pl.global_position = sp + Vector3(0, 1.2, 0)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.4, 1.0, 0.3)
	gl.light_energy = 1.5
	gl.omni_range = 5.0
	spike_root.add_child(gl)
	gl.global_position = sp + Vector3(0, 2.2, 0) - to_k * 1.0
	w._poison_mist(spike_root, sp + Vector3(0, 0.6, 0), 1.6, 30)
	cam.fov = 45.0
	g._cinematic(sp - to_k * 4.4 + Vector3(0, 2.3, 0) + side * 1.0, sp + Vector3(0, 0.9, 0), 1.0, 0.01)
	await get_tree().create_timer(1.6).timeout
	await _shot("il_spines_a")
	g._cinematic(sp - to_k * 4.0 + Vector3(0, 0.55, 0) - side * 1.8, sp + Vector3(0, 1.2, 0), 1.0, 0.01)
	await get_tree().create_timer(0.6).timeout
	await _shot("il_spines_b")
	spike_root.queue_free()
	# ── 3) 상점 대혼란: 촉수가 노점을 휘감고 동전이 쏟아짐 ──
	var shops: Array = w.spaces_of_kind("shop")
	var sb: int = 135 if shops.has(135) else int(shops[shops.size() - 1])
	var spos: Vector3 = w.spaces[sb]["pos"]
	var stall := spos
	var best_d := INF
	for n in w.get_children():
		if n is Node3D and (n as Node3D).global_position.distance_to(spos) < 6.0 and (n as Node3D).global_position.distance_to(spos) > 1.0:
			pass
	var tn2: Dictionary = w.make_tentacle(1, 1.25, 10.0, -to_k)
	var m2: ShaderMaterial = tn2["mat"]
	m2.set_shader_parameter("tip", 0.2)
	m2.set_shader_parameter("hook_at", 0.4)
	m2.set_shader_parameter("pitch", -0.15)
	m2.set_shader_parameter("curl", 0.5)
	m2.set_shader_parameter("hook", 1.5)
	m2.set_shader_parameter("tipback", -0.6)
	m2.set_shader_parameter("glow", 0.3)
	var r2: Node3D = tn2["root"]
	var coin_root_pre := Node3D.new()
	w.add_child(coin_root_pre)
	w.add_child(r2)
	r2.position = spos + to_k * 3.6 + side * 1.8 + Vector3(0, -0.9, 0)
	var rim2 := OmniLight3D.new()
	rim2.light_color = Color(0.45, 1.0, 0.3)
	rim2.light_energy = 3.0
	rim2.omni_range = 8.0
	coin_root_pre.add_child(rim2)
	rim2.global_position = spos + to_k * 5.0 + Vector3(0, 4.0, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1.0, 0.76, 0.25)
	gm.metallic = 0.4
	gm.roughness = 0.3
	gm.emission_enabled = true
	gm.emission = Color(0.9, 0.62, 0.15)
	gm.emission_energy_multiplier = 0.55
	var coin_root := Node3D.new()
	w.add_child(coin_root)
	for k in 30:
		var cy := CylinderMesh.new()
		cy.top_radius = 0.16
		cy.bottom_radius = 0.16
		cy.height = 0.04
		var mi2 := MeshInstance3D.new()
		mi2.mesh = cy
		mi2.material_override = gm
		coin_root.add_child(mi2)
		mi2.global_position = spos + Vector3(rr.randf_range(-2.4, 2.4), rr.randf_range(0.4, 3.2), rr.randf_range(-2.0, 2.0))
		mi2.rotation = Vector3(rr.randf() * TAU, rr.randf() * TAU, rr.randf() * TAU)
	var cl2 := OmniLight3D.new()
	cl2.light_color = Color(1.0, 0.85, 0.5)
	cl2.light_energy = 2.0
	cl2.omni_range = 6.0
	coin_root.add_child(cl2)
	cl2.global_position = spos + Vector3(0, 2.0, 0) - to_k * 2.0
	cam.fov = 48.0
	g._cinematic(spos - to_k * 6.5 + Vector3(0, 1.8, 0) - side * 1.0, spos + Vector3(0, 1.6, 0) + to_k * 0.8, 1.0, 0.01)
	await get_tree().create_timer(0.8).timeout
	await _shot("il_surge_a")
	g._cinematic(spos - to_k * 5.0 + Vector3(0, 2.8, 0) + side * 2.5, spos + Vector3(0, 1.4, 0), 1.0, 0.01)
	await get_tree().create_timer(0.6).timeout
	await _shot("il_surge_b")


func w_h(wb: Node) -> float:
	return float(wb.half_d) * 2.6 + 30.0
