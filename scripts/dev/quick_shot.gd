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
		for a in ["barrage", "spines", "surge"]:
			Engine.time_scale = 0.25
			gk._kraken_card(a)
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
	env.fog_density = 0.03
	env.fog_light_color = Color(0.02, 0.13, 0.15)
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.tonemap_exposure = 0.75
	env.ambient_light_energy = 0.3
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
	# ── 1) 촉수 폭풍: 붉게 빛나는 칸들 위로 거대한 촉수들이 몸을 젖히고, 하나는 막 내려꽂힘 ──
	for i in picks:
		w.mark_danger(i)
	var poses := [[-0.55, 1.4, 0.0, -0.8], [-0.35, 1.1, 0.0, -0.5], [0.5, 0.0, 1.2, 1.0], [-0.7, 1.6, 0.0, -1.0]]
	var stage := []
	for k in picks.size():
		var tp: Vector3 = w.spaces[picks[k]]["pos"]
		var dirv := (tp - c).normalized() if k != 2 else -side
		if dirv.length() < 0.1:
			dirv = side
		var tn: Dictionary = w.make_tentacle(1, 1.25 if k != 2 else 1.1, 10.0 if k != 2 else 7.5, -dirv)
		var m: ShaderMaterial = tn["mat"]
		var pz: Array = poses[k]
		m.set_shader_parameter("tip", 0.2)
		m.set_shader_parameter("hook_at", 0.2)
		m.set_shader_parameter("pitch", pz[0])
		m.set_shader_parameter("curl", pz[1])
		m.set_shader_parameter("hook", pz[2])
		m.set_shader_parameter("tipback", pz[3])
		m.set_shader_parameter("glow", 0.35)
		var root: Node3D = tn["root"]
		w.add_child(root)
		root.position = tp + dirv * 3.0 + Vector3(0, -0.9, 0)
		stage.append(root)
	# 내려꽂힌 칸에 흙먼지 · 충격
	w.bubbles_at(w.spaces[picks[2]]["pos"], 30, 1.4, true)
	cam.fov = 52.0
	g._cinematic(c - to_k * 10.5 + Vector3(0, 1.6, 0) + side * 1.5, c + to_k * 6.0 + Vector3(0, 4.2, 0), 1.0, 0.01)
	await get_tree().create_timer(0.9).timeout
	await _shot("il_storm_a")
	g._cinematic(c - to_k * 7.0 + Vector3(0, 0.8, 0) - side * 3.0, c + to_k * 4.0 + Vector3(0, 3.0, 0), 1.0, 0.01)
	await get_tree().create_timer(0.6).timeout
	await _shot("il_storm_b")
	for r in stage:
		(r as Node3D).queue_free()
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
	spm.emission_energy_multiplier = 0.35
	spm.rim_enabled = true
	spm.rim = 0.6
	var spike_root := Node3D.new()
	w.add_child(spike_root)
	var rr := RandomNumberGenerator.new()
	rr.seed = 11
	for k in 70:
		var a := rr.randf() * TAU
		var d := sqrt(rr.randf()) * 1.05
		var base := sp + Vector3(cos(a) * d, 0.42, sin(a) * d)
		var outw := Vector3(cos(a), 0, sin(a)) * d * 0.7
		var up := (Vector3.UP * 1.0 + outw + Vector3(rr.randf_range(-0.2, 0.2), 0, rr.randf_range(-0.2, 0.2))).normalized()
		var x := up.cross(Vector3(0, 0, 1)).normalized()
		var bz := x.cross(up)
		_neon_cone(spike_root, base, Basis(x, up, bz), rr.randf_range(0.05, 0.11), rr.randf_range(0.6, 2.0) * (1.2 - d * 0.5), spm)
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
	pl.light_energy = 3.0
	pl.omni_range = 6.0
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
	g._cinematic(sp - to_k * 5.2 + Vector3(0, 1.3, 0) + side * 1.2, sp + Vector3(0, 1.0, 0), 1.0, 0.01)
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
	var tn2: Dictionary = w.make_tentacle(1, 1.1, 9.0, to_k)
	var m2: ShaderMaterial = tn2["mat"]
	m2.set_shader_parameter("tip", 0.2)
	m2.set_shader_parameter("hook_at", 0.25)
	m2.set_shader_parameter("pitch", -0.2)
	m2.set_shader_parameter("curl", 1.2)
	m2.set_shader_parameter("hook", 1.0)
	m2.set_shader_parameter("tipback", -0.3)
	m2.set_shader_parameter("glow", 0.3)
	var r2: Node3D = tn2["root"]
	w.add_child(r2)
	r2.position = spos + to_k * 3.2 + side * 1.5 + Vector3(0, -0.8, 0)
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
	var tag := Label3D.new()
	tag.text = "×2"
	tag.font_size = 220
	tag.outline_size = 40
	tag.modulate = Color(0.95, 0.12, 0.08)
	tag.outline_modulate = Color(1.0, 0.92, 0.75)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	coin_root.add_child(tag)
	tag.global_position = spos + Vector3(0, 2.6, 0) - to_k * 0.5
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
