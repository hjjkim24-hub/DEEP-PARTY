extends "res://scripts/minigames/minigame_3d.gd"
## 돛대 오르기 (A/D 또는 ←/→ 번갈아 + 스페이스 꾹): 돛대 네 개짜리 범선을 옆에서 본 모습.
## 돛대마다 뱃전에서 비스듬히 올라가는 밧줄 사다리(줄사다리)를 타고 맨 꼭대기 깃발까지 (약 26m).
## 두 키를 번갈아 누를 때마다 한 칸씩 올라감. 같은 키를 두 번 누르면 발이 미끄러져 살짝 내려옴.
## 돌풍: 경고가 뜬 뒤 바람이 몰아침 → 그동안 스페이스를 꾹 눌러 붙잡고 있어야 함. 안 붙잡으면 쭉 미끄러져 내려옴.
## 갈매기: 옆에서 끼룩대며 가로질러 날아옴 → 그 높이에 있으면 부딪혀 떨어짐. 멈춰 기다리거나 먼저 지나쳐 올라가야 함.
## 꼭대기 깃발을 먼저 잡은 순서대로 순위 (시간이 다 되면 높이 올라간 순). 화면은 내 말을 따라 올라감.

const LANE_GAP := 5.6
const START_Y := 1.2            ## 뱃전 위 (오르기 시작하는 발 높이)
const TOP_Y := 26.6             ## 깃발을 잡는 발 높이
const TOP := TOP_Y - START_Y    ## 올라야 하는 높이
const STEP := 0.26
const SLIP := 0.2
const GUST_WARN := 1.4
const GUST_DUR := 1.6
## 줄사다리가 지나는 길 (y, 돛대에서 앞쪽으로 떨어진 거리 z): 뱃전 → 아래 망대 → 윗돛대 → 꼭대기
const ROUTE := [Vector2(1.2, 2.85), Vector2(9.8, 0.62), Vector2(10.05, 1.45), Vector2(18.4, 0.42), Vector2(18.65, 0.92), Vector2(26.0, 0.3), Vector2(26.7, 0.3)]
## 줄사다리 세 구간: [아래 y, 아래 z(첫 구간은 뱃전), 아래 반폭, 위 y, 위 z, 위 반폭, 세로줄 수]
const RUNG_GAP := 0.6
## 갈매기: 화면 옆 밖(±BIRD_X0)에서 나타나 반대쪽까지 가로질러 날아감
const BIRD_X0 := 17.0
const BIRD_V := 5.2
const BIRD_HIT_X := 0.75
const BIRD_HIT_Y := 0.7
const BIRD_DROP := 1.6

var _ship: Node3D
var _lanes := {}                ## slot → {x, h, shown, last, stun, done, time, pawn, mast, grip, slip, blown...}
var _elapsed := 0.0
var _ai := {}
var _done_n := 0
var _gust := {}                 ## {dir, t1, hit{}}
var _gust_t := 5.0
var _wind: CPUParticles3D
var _gust_label: Label
var _cam_y := 6.0
var _cam_x := 0.0
var _flutter := 5.0
var _birds: Array = []         ## {id, y, dir, t0, node, wl, wr, hit{}, cried}
var _bird_t := 3.5
var _bird_id := 0


func _init() -> void:
	title = "MAST CLIMB"
	how_to = "Press the two keys one after the other to climb the rope ladder to the flag! The same key twice makes you slip. When a GUST comes, hold SPACE to cling on. Seagulls fly across too - wait for them to pass, or hurry past first!"
	goal = "Grab the flag first!"
	controls = "ALT_KEYS_GRIP"
	duration = 50.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	env.fog_light_color = Color(0.66, 0.78, 0.88)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	ocean(-3.0, 300.0)
	sky_clouds(18, 220.0, 40.0)
	cam.fov = 46.0
	_place_cam(true)
	_ship = Node3D.new()
	world3.add_child(_ship)
	_build_ship()
	gulls(6, Vector3(0, 18, -20), 22.0, 26.0, 8)
	island(Vector3(-120, -3.5, -240), 26.0, 18.0, 5)
	var sb := sailboat(Color(0.9, 0.88, 0.8), world3)
	sb.scale = Vector3.ONE * 7.0
	sb.position = Vector3(90, -3.4, -180)
	sb.rotation.y = 2.6
	_build_wind()


# ── 배 ──────────────────────────────────────────────────────
func _u(x: float) -> float:
	return clampf((x - 1.0) / 17.0, -1.0, 1.0)


## 선체 반폭: 이물(+x)은 뾰족, 고물(-x)은 통통
func _hb(x: float) -> float:
	var u := _u(x)
	if u >= 0.0:
		return 3.3 * pow(maxf(0.0, 1.0 - pow(u, 2.2)), 0.55)
	return 3.3 * pow(maxf(0.0, 1.0 - pow(-u, 4.0)), 0.5)


## 뱃전 높이: 이물 · 고물 쪽으로 휘어 올라감
func _sheer(x: float) -> float:
	var u := _u(x)
	return 1.05 + 0.7 * u * u + (0.9 * u * u * u if u > 0.0 else -0.5 * u * u * u)


func _keel(x: float) -> float:
	var u := _u(x)
	return -4.3 + 2.4 * pow(maxf(0.0, absf(u) - 0.72) / 0.28, 2.0)


func _hull_col(y: float, top: float) -> Color:
	if top - y < 0.16:
		return Color(0.46, 0.31, 0.19)        # 뱃전 난간 (나무)
	if y < -3.12:
		return Color(0.45, 0.17, 0.1)         # 물밑 붉은 칠
	if y < -2.95:
		return Color(0.88, 0.87, 0.8)         # 흘수선 흰 줄
	if y > -0.6 and y < 0.08:
		return Color(0.8, 0.62, 0.3)          # 포문 띠 (황토)
	return Color(0.07, 0.07, 0.08)            # 검은 선체


func _build_ship() -> void:
	# 선체: 단면을 이물에서 고물까지 이어 붙인 곡면
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs: Array = []
	var n_st := 70
	for i in n_st + 1:
		xs.append(lerpf(-15.9, 17.9, float(i) / n_st))
	var M := 44
	var rows: Array = []   # rows[i][j] = [pos(+z 쪽), normal]
	for x: float in xs:
		var b := maxf(_hb(x), 0.12)
		var top := _sheer(x)
		var kl := _keel(x)
		var row := []
		for j in M + 1:
			var a := float(j) / M * PI * 0.5
			var a2 := a + 0.01
			var p1 := Vector2(top - (top - kl) * sin(a), b * pow(cos(a), 0.4))
			var p2 := Vector2(top - (top - kl) * sin(a2), b * pow(maxf(cos(a2), 0.0), 0.4))
			var t := p2 - p1
			var nrm := Vector3(0, t.y, -t.x).normalized()
			row.append([Vector3(x, p1.x, p1.y), nrm])
		rows.append(row)
	for side: float in [1.0, -1.0]:
		for i in n_st:
			for j in M:
				var q := [rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]]
				var order := [0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2]
				for k: int in order:
					var v: Vector3 = q[k][0]
					var nn: Vector3 = q[k][1]
					v.z *= side
					nn.z *= side
					st.set_color(_hull_col(v.y, _sheer(v.x)))
					st.set_normal(nn)
					st.add_vertex(v)
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.roughness = 0.55
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hull := MeshInstance3D.new()
	hull.mesh = st.commit()
	hull.material_override = hm
	_ship.add_child(hull)
	# 고물 판 (뒤 끝을 막음)
	var tr_ := box(Vector3(0.12, _sheer(-15.9) - _keel(-15.9), _hb(-15.9) * 2.0 + 0.1), std_mat(Color(0.07, 0.07, 0.08), 0.6),
		Vector3(-15.95, (_sheer(-15.9) + _keel(-15.9)) * 0.5, 0), Basis(), _ship)
	tr_.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 갑판 (구간마다 선체 폭에 맞춘 널판)
	var cols := [Color(0.5, 0.38, 0.26), Color(0.54, 0.41, 0.28), Color(0.47, 0.35, 0.24)]
	var x0 := -15.4
	var k := 0
	while x0 < 17.0:
		var x1 := minf(x0 + 1.4, 17.4)
		var w := minf(_hb(x0), _hb(x1)) * 2.0 - 0.2
		var xm := (x0 + x1) * 0.5
		box(Vector3(x1 - x0 + 0.02, 0.2, w), wood_mat(cols[k % 3], Vector3(1, 0, 0), 0.05), Vector3(xm, _sheer(xm) - 1.1, 0), Basis(), _ship)
		x0 = x1
		k += 1
	# 포문 (황토 띠 위 검은 네모, 가까운 쪽)
	var port := std_mat(Color(0.03, 0.03, 0.03), 0.7)
	var lid := std_mat(Color(0.6, 0.18, 0.1), 0.7)
	var px := -12.5
	while px < 14.0:
		var top := _sheer(px)
		var kl := _keel(px)
		var a := asin(clampf((top - (-0.26)) / (top - kl), 0.0, 1.0))
		var z := _hb(px) * pow(cos(a), 0.4)
		box(Vector3(0.52, 0.44, 0.06), port, Vector3(px, -0.26, z + 0.01), Basis(), _ship)
		box(Vector3(0.6, 0.06, 0.08), lid, Vector3(px, 0.0, z + 0.02), Basis(), _ship)
		px += 2.3
	# 뱃머리 돛대(바우스프릿) + 앞 밧줄
	var wood := wood_mat(Color(0.47, 0.32, 0.19), Vector3(0, 1, 0), 0.08)
	_rod(Vector3(16.6, 1.8, 0), Vector3(26.0, 4.9, 0), 0.22, wood, _ship)
	_rod(Vector3(25.5, 4.75, 0), Vector3(31.5, 6.4, 0), 0.11, wood, _ship)
	# 갑판 위 잡동사니
	deck_clutter(_ship, [Vector3(-12.6, _sheer(-12.6) - 1.0, 1.2), Vector3(12.8, _sheer(12.8) - 1.0, 0.9), Vector3(-5.6, -0.0, -1.6), Vector3(0.0, 0.0, -1.8)], 23)


## a → b 를 잇는 막대 / 밧줄
func _rod(a: Vector3, b: Vector3, r: float, mat: Material, parent: Node3D) -> MeshInstance3D:
	var d := b - a
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = d.length()
	c.radial_segments = 6 if r < 0.05 else 12
	c.rings = 1
	var mi := add_mesh(c, mat, (a + b) * 0.5, Basis(Quaternion(Vector3.UP, d.normalized())), parent)
	if r < 0.05:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 줄사다리 위 높이 y 에서 돛대 앞쪽 거리
func _route_z(y: float, z0: float) -> float:
	var pts: Array = ROUTE.duplicate()
	pts[0] = Vector2(START_Y, z0)
	if y <= pts[0].x:
		return pts[0].y
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if y <= b.x:
			return lerpf(a.y, b.y, (y - a.x) / maxf(b.x - a.x, 0.001))
	return (pts[pts.size() - 1] as Vector2).y


## 돛대 (아래 · 윗 · 꼭대기 세 토막) + 망대 + 활대에 말아 묶은 돛 + 줄사다리 + 깃발
func _mast(x: float) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(x, 0, 0)
	_ship.add_child(root)
	var wood := wood_mat(Color(0.47, 0.32, 0.19), Vector3(0, 1, 0), 0.08)
	var dark := wood_mat(Color(0.3, 0.2, 0.12), Vector3(0, 1, 0), 0.1)
	var iron := std_mat(Color(0.18, 0.17, 0.16), 0.45, 0.7)
	var rope := std_mat(Color(0.2, 0.15, 0.1), 0.9)
	var deck := _sheer(x) - 1.0
	# 세 토막 (위로 갈수록 가늘게, 겹치는 부분이 보이게)
	for seg: Array in [[deck - 0.3, 10.9, 0.34, 0.27, 0.0], [9.0, 19.5, 0.22, 0.17, -0.05], [17.6, 27.9, 0.14, 0.07, -0.08]]:
		var m := CylinderMesh.new()
		m.bottom_radius = seg[2]
		m.top_radius = seg[3]
		m.height = float(seg[1]) - float(seg[0])
		m.radial_segments = 16
		add_mesh(m, wood, Vector3(0, (float(seg[0]) + float(seg[1])) * 0.5, float(seg[4])), Basis(), root)
		var bands := int((float(seg[1]) - float(seg[0])) / 2.0)
		for k in bands:
			var y := float(seg[0]) + 1.0 + k * 2.0
			var bm := CylinderMesh.new()
			var r := lerpf(seg[2], seg[3], (y - float(seg[0])) / (float(seg[1]) - float(seg[0]))) + 0.012
			bm.top_radius = r
			bm.bottom_radius = r
			bm.height = 0.08
			add_mesh(bm, iron, Vector3(0, y, float(seg[4])), Basis(), root)
	# 아래 망대 (둥근 발판) · 위 십자 받침
	var top := CylinderMesh.new()
	top.top_radius = 1.35
	top.bottom_radius = 1.25
	top.height = 0.16
	add_mesh(top, dark, Vector3(0, 9.9, 0.35), Basis(), root)
	for k in 3:
		box(Vector3(0.12, 0.12, 2.0), dark, Vector3(-0.5 + k * 0.5, 18.5, 0.2), Basis(), root)
	box(Vector3(1.6, 0.1, 0.12), dark, Vector3(0, 18.55, 0.2), Basis(), root)
	var truck := SphereMesh.new()
	truck.radius = 0.13
	truck.height = 0.2
	add_mesh(truck, dark, Vector3(0, 27.95, -0.08), Basis(), root)
	# 활대 + 말아 묶은 돛: 비스듬히 돌려(돛 방향) 옆에서도 보이게
	var sail := std_mat(Color(0.88, 0.85, 0.75), 0.95)
	var tie_m := std_mat(Color(0.55, 0.45, 0.3), 0.95)
	var brace := Basis(Vector3.UP, 0.95)
	for yd: Array in [[8.9, 9.0], [12.6, 8.2], [15.8, 7.4], [21.0, 5.8], [24.2, 4.6]]:
		var y := float(yd[0])
		var ln := float(yd[1])
		var yard := CylinderMesh.new()
		yard.top_radius = 0.06
		yard.bottom_radius = 0.11
		yard.height = ln * 0.5
		yard.radial_segments = 10
		for sd: float in [-1.0, 1.0]:
			var off := brace * Vector3(0, 0, sd * ln * 0.25)
			add_mesh(yard, wood, Vector3(0, y, -0.25) + off, brace * Basis(Vector3.RIGHT, sd * PI / 2), root)
		var furl := CylinderMesh.new()
		furl.top_radius = 0.19
		furl.bottom_radius = 0.19
		furl.height = ln * 0.86
		furl.radial_segments = 12
		var fp := Vector3(0, y - 0.2, -0.35)
		var fi := add_mesh(furl, sail, fp, brace * Basis(Vector3.RIGHT, PI / 2), root)
		fi.scale = Vector3(1.0, 1.0, 0.85)
		var ties := int(ln / 1.1)
		for k in ties:
			var tz := lerpf(-ln * 0.4, ln * 0.4, float(k) / maxf(ties - 1, 1))
			var tie := TorusMesh.new()
			tie.inner_radius = 0.18
			tie.outer_radius = 0.22
			add_mesh(tie, tie_m, fp + brace * Vector3(0, 0, tz), brace * Basis(Vector3.RIGHT, PI / 2), root)
	# 줄사다리: 뱃전에서 망대까지 굵은 밧줄 여러 가닥 + 가로 디딤줄
	var lad := std_mat(Color(0.32, 0.25, 0.17), 0.95)
	var z0 := _hb(x) - 0.12
	var secs := [[START_Y, z0, 1.2, 9.8, 0.62, 0.5, 4], [10.05, 1.45, 0.8, 18.4, 0.42, 0.35, 3], [18.65, 0.92, 0.5, 26.0, 0.3, 0.2, 3]]
	for sc: Array in secs:
		var y0 := float(sc[0])
		var y1 := float(sc[3])
		var zz0 := float(sc[1])
		var zz1 := float(sc[4])
		var w0 := float(sc[2])
		var w1 := float(sc[5])
		var n := int(sc[6])
		for i in n:
			var f := float(i) / (n - 1) * 2.0 - 1.0
			_rod(Vector3(f * w0, y0, zz0), Vector3(f * w1, y1, zz1), 0.035, lad, root)
			# 아래 끝 도르래 눈(데드아이)
			var de := CylinderMesh.new()
			de.top_radius = 0.09
			de.bottom_radius = 0.09
			de.height = 0.06
			add_mesh(de, dark, Vector3(f * w0, y0 + 0.05, zz0), Basis(Vector3.RIGHT, PI / 2), root)
		var y := y0 + RUNG_GAP
		while y < y1 - 0.1:
			var t := (y - y0) / (y1 - y0)
			var w := lerpf(w0, w1, t)
			var z := lerpf(zz0, zz1, t)
			_rod(Vector3(-w, y, z + 0.01), Vector3(w, y, z + 0.01), 0.022, lad, root)
			y += RUNG_GAP
	# 깃발: 깃대 + 펄럭이는 천 (처음엔 해골 흑기, 잡으면 그 사람 색)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.045
	pole.height = 1.5
	add_mesh(pole, wood, Vector3(0, 28.7, -0.08), Basis(), root)
	var flag := Node3D.new()
	flag.position = Vector3(0.05, 29.1, -0.08)
	root.add_child(flag)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.08, 0.09)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.roughness = 0.9
	var segs := []
	for k in 6:
		var q := QuadMesh.new()
		q.size = Vector2(0.24, 0.75)
		segs.append(add_mesh(q, fm, Vector3(0.12 + k * 0.24, 0, 0), Basis(), flag))
	var bone := std_mat(Color(0.92, 0.9, 0.84), 0.8)
	var skull := SphereMesh.new()
	skull.radius = 0.12
	skull.height = 0.22
	var sk := add_mesh(skull, bone, Vector3(0.72, 0.05, 0.012), Basis(), flag)
	sk.scale = Vector3(1, 1, 0.15)
	return {"root": root, "flag": flag, "fm": fm, "segs": segs, "skull": sk, "z0": z0}


func _setup_game() -> void:
	var n := players.size()
	var xs: Array = []
	for i in n:
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var x := (float(i) - (n - 1) * 0.5) * LANE_GAP
		xs.append(x)
		var mast := _mast(x)
		var pawn := make_pawn(p)
		pawn.reparent(_ship, false)
		pawn.rotation.y = PI
		_lanes[s] = {"x": x, "h": 0.0, "shown": 0.0, "last": -1, "stun": 0.0, "done": false, "time": 0.0, "pawn": pawn,
			"mast": mast, "pulse": 0.0, "slip": 0.0, "grip": false, "blown": 0.0}
		_ai[s] = {"next": rng.randf_range(0.2, 0.5), "grip_from": INF, "grip_to": -INF}
		scores[s] = 0.0
	# 돛대끼리 앞뒤로 이은 밧줄 + 맨 앞 돛대 → 바우스프릿
	var rope := std_mat(Color(0.2, 0.15, 0.1), 0.9)
	xs.sort()
	for i in xs.size() - 1:
		var a: float = xs[i]
		var b: float = xs[i + 1]
		_rod(Vector3(a, 18.3, 0), Vector3(b, 10.4, 0), 0.03, rope, _ship)
	if not xs.is_empty():
		var f: float = xs[xs.size() - 1]
		_rod(Vector3(f, 18.3, 0), Vector3(25.8, 4.85, 0), 0.03, rope, _ship)
	_place(0.0)
	_place_cam(true)


func _start_game() -> void:
	_elapsed = 0.0
	_gust_t = 5.0
	_bird_t = 3.5
	if OS.get_environment("MC_GUST_AT") != "":   # 점검용: 첫 돌풍 시각
		_gust_t = float(OS.get_environment("MC_GUST_AT"))


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k == null or k.echo:
		return
	if k.physical_keycode == KEY_SPACE:
		net_input("grip", [1 if k.pressed else 0])
		return
	if not k.pressed:
		return
	var side := -1
	match k.physical_keycode:
		KEY_A, KEY_LEFT:
			side = 0
		KEY_D, KEY_RIGHT:
			side = 1
	if side >= 0:
		net_input("step", [side])


func _net_input(slot: int, action: String, args: Array) -> void:
	if not playing or args.is_empty():
		return
	if action == "step":
		_step(slot, int(args[0]))
	elif action == "grip" and _lanes.has(slot):
		_lanes[slot]["grip"] = int(args[0]) == 1


## 방장: 한 발. 번갈아 누르면 위로, 같은 키 두 번이면 미끄러짐. 붙잡는 중 · 부딪혀 휘청이는 중엔 못 오름
func _step(s: int, side: int) -> void:
	var L: Dictionary = _lanes.get(s, {})
	if L.is_empty() or L["done"] or float(L["stun"]) > 0.0 or L["grip"]:
		return
	if int(L["last"]) == side:
		L["h"] = maxf(0.0, float(L["h"]) - SLIP)
		L["stun"] = 0.22
		net_call("_slip_fx", [s])
	else:
		L["h"] = float(L["h"]) + STEP
		L["pulse"] = 1.0
		if float(L["h"]) >= TOP:
			L["h"] = TOP
			net_call("_finish", [s, _elapsed])
	L["last"] = side


func _slip_fx(s: int) -> void:
	var L: Dictionary = _lanes[s]
	L["slip"] = 0.3
	if is_local(player_by_slot(s)):
		sfx("thud", 80)


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	if not is_client():
		_think(delta)
		_gust_t -= delta
		if _gust_t <= 0.0 and _gust.is_empty():
			net_call("_gust_go", [1.0 if rng.randf() < 0.5 else -1.0, _elapsed + GUST_WARN])
			_gust_t = rng.randf_range(5.5, 8.0) + GUST_WARN + GUST_DUR
		_bird_t -= delta
		if _bird_t <= 0.0:
			_spawn_bird()
		for s in _lanes:
			_lanes[s]["stun"] = maxf(0.0, float(_lanes[s]["stun"]) - delta)
			scores[s] = float(_lanes[s]["h"])
		_gust_check()
		_bird_check()
	_update_gust(delta)
	_update_birds(delta)
	# 배가 천천히 출렁
	_ship.rotation = Vector3(sin(_t3 * 0.45) * 0.01, 0, sin(_t3 * 0.31) * 0.006)
	_place(delta)
	_place_cam(false, delta)


# ── 돌풍 ────────────────────────────────────────────────────
func _gust_go(dir: float, t1: float) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("GUST go el=%.2f t1=%.2f" % [_elapsed, t1])
	_gust = {"dir": dir, "t1": t1, "hit": {}, "warned": false, "blew": false}


## 방장: 돌풍이 부는 동안 안 붙잡은 사람은 쭉 미끄러져 내려옴
func _gust_check() -> void:
	if _gust.is_empty():
		return
	var t := _elapsed - float(_gust["t1"])
	if t < 0.15 or t > GUST_DUR:
		return
	var hit: Dictionary = _gust["hit"]
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		if hit.has(s) or L["done"] or float(L["h"]) < 0.3:
			continue
		if not L["grip"]:
			hit[s] = true
			var drop := lerpf(1.4, 3.6, float(L["h"]) / TOP)
			L["h"] = maxf(0.0, float(L["h"]) - drop)
			L["stun"] = 1.0
			L["last"] = -1
			net_call("_gust_hit", [s, drop])


func _gust_hit(s: int, drop: float) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("GUST hit s=%d drop=%.1f el=%.2f" % [s, drop, _elapsed])
	var L: Dictionary = _lanes[s]
	L["slip"] = 1.0
	L["blown"] = 1.0
	var pawn: Node3D = L["pawn"]
	sfx("thud", 70)
	if is_local(player_by_slot(s)):
		shake(0.35)


func _build_wind() -> void:
	var streak := QuadMesh.new()
	streak.size = Vector2(3.4, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0, 0.5)
	g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.6, Color(1, 1, 1, 0.8))
	g.gradient = gr
	m.albedo_texture = g
	streak.material = m
	_wind = CPUParticles3D.new()
	_wind.amount = 160
	_wind.lifetime = 0.7
	_wind.local_coords = false
	_wind.emitting = false
	_wind.mesh = streak
	_wind.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wind.emission_box_extents = Vector3(2.0, 8.0, 4.0)
	_wind.spread = 2.0
	_wind.gravity = Vector3.ZERO
	_wind.initial_velocity_min = 30.0
	_wind.initial_velocity_max = 42.0
	_wind.scale_amount_min = 0.6
	_wind.scale_amount_max = 1.4
	_wind.visibility_aabb = AABB(Vector3(-60, -20, -20), Vector3(120, 40, 40))
	world3.add_child(_wind)


func _update_gust(delta: float) -> void:
	var target_flutter := 5.0
	if not _gust.is_empty():
		var t := _elapsed - float(_gust["t1"])
		var dir := float(_gust["dir"])
		if _gust_label == null:
			_gust_label = outlined("", 64)
			_gust_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
			_gust_label.offset_left = 0.0
			_gust_label.offset_right = 0.0
			_gust_label.offset_top = 105.0
			_gust_label.offset_bottom = 195.0
			_gust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_gust_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_overlay.add_child(_gust_label)
		_gust_label.visible = true
		if t < 0.0:
			if not _gust["warned"]:
				_gust["warned"] = true
				sfx("whoosh", 40)
			_gust_label.text = tr("Gust warning!")
			_gust_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.4, 0.25), 0.5 + 0.5 * sin(_elapsed * 18.0)))
		elif t < GUST_DUR:
			if not _gust["blew"]:
				_gust["blew"] = true
				sfx("whoosh", 120)
				sfx("spray", 60)
			_gust_label.visible = false
			target_flutter = 16.0
			_wind.emitting = true
			_wind.direction = Vector3(dir, -0.03, 0)
			_wind.position = Vector3(_cam_x - dir * 20.0, _cam_y, 5.0)
			if t < 0.3:
				shake(0.12)
		else:
			_gust = {}
			_gust_label.visible = false
			_wind.emitting = false
	_flutter = lerpf(_flutter, target_flutter, clampf(delta * 4.0, 0.0, 1.0))


# ── 모습 ────────────────────────────────────────────────────
func _place(delta: float) -> void:
	var gdir := float(_gust.get("dir", 0.0))
	var blowing := not _gust.is_empty() and _elapsed >= float(_gust["t1"])
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		var pawn: Node3D = L["pawn"]
		var mast: Dictionary = L["mast"]
		L["shown"] = lerpf(float(L["shown"]), float(L["h"]), clampf(delta * 12.0, 0.0, 1.0)) if delta > 0.0 else float(L["h"])
		L["pulse"] = maxf(0.0, float(L["pulse"]) - delta * 6.0)
		L["slip"] = maxf(0.0, float(L["slip"]) - delta)
		L["blown"] = maxf(0.0, float(L["blown"]) - delta)
		var x: float = L["x"]
		var y := START_Y + float(L["shown"])
		var z := _route_z(y, float(mast["z0"])) + 0.3
		if L["done"]:
			# 꼭대기에서 깃대 붙잡고 방방
			pawn.position = Vector3(x + 0.05, TOP_Y + absf(sin(_t3 * 6.0)) * 0.2, 0.42)
			pawn.rotation = Vector3(0, PI + sin(_t3 * 3.0) * 0.5, 0)
		else:
			# 줄사다리 기울기만큼 몸을 기댐. 한 발마다 좌우로 흔들 · 붙잡으면 바짝 붙음 · 날리면 휘청
			var z_up := _route_z(y + 0.3, float(mast["z0"])) + 0.3
			var tilt := atan2(z - z_up, 0.3)
			var sway := sin(float(L["shown"]) / STEP * PI) * 0.16
			var grip: bool = L["grip"]
			if grip:
				z -= 0.12
				sway *= 0.2
			var gust_lean := gdir * 0.25 if (blowing and grip) else 0.0
			var flail := sin(_t3 * 26.0) * 0.35 * float(L["blown"])
			pawn.position = Vector3(x + sway * 0.4 + float(L.get("bdir", gdir)) * float(L["blown"]) * 0.5, y + float(L["pulse"]) * 0.05, z)
			pawn.rotation = Vector3(-tilt * 0.8 - float(L["slip"]) * 0.6, PI, sway + gust_lean + flail)
		# 깃발 펄럭임 (돌풍 땐 세차게)
		var segs: Array = mast["segs"]
		for k in segs.size():
			var seg: Node3D = segs[k]
			seg.position.z = sin(_t3 * _flutter - k * 0.8 + s) * 0.06 * k
			seg.rotation.y = cos(_t3 * _flutter - k * 0.8 + s) * 0.35


## 화면: 내 말 높이를 따라 올라감 (자동이면 선두). 옆으로는 살짝만 따라가 돛대 넷이 다 보이게
func _place_cam(snap: bool = false, delta: float = 0.0) -> void:
	var fy := 3.6
	var fx := 0.0
	var me := local_slot()
	if _lanes.has(me) and is_local(player_by_slot(me)):
		fy = START_Y + float(_lanes[me]["shown"])
		fx = float(_lanes[me]["x"]) * 0.22
	elif not _lanes.is_empty():
		var best := -1.0
		for s in _lanes:
			if not _lanes[s]["done"] and float(_lanes[s]["shown"]) > best:
				best = float(_lanes[s]["shown"])
		fy = START_Y + (best if best >= 0.0 else TOP)
	fy = clampf(fy + 0.8, 3.6, TOP_Y - 1.2)
	if snap:
		_cam_y = fy
		_cam_x = fx
	else:
		_cam_y = lerpf(_cam_y, fy, clampf(delta * 3.0, 0.0, 1.0))
		_cam_x = lerpf(_cam_x, fx, clampf(delta * 2.0, 0.0, 1.0))
	var xf := Transform3D(Basis(), Vector3(_cam_x, _cam_y + 1.4, 18.0))
	xf = xf.looking_at(Vector3(_cam_x, _cam_y, 0), Vector3.UP)
	cam_base = xf
	cam.transform = xf


func _finish(s: int, t: float) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("MC finish s=%d t=%.1f" % [s, t])
	var L: Dictionary = _lanes[s]
	if L["done"]:
		return
	L["done"] = true
	L["time"] = t
	L["h"] = TOP
	L["grip"] = false
	_done_n += 1
	var p := player_by_slot(s)
	var mast: Dictionary = L["mast"]
	(mast["fm"] as StandardMaterial3D).albedo_color = (p["color"] as Color)
	(mast["skull"] as Node3D).visible = false
	sfx("start")
	var fl: Node3D = mast["flag"]
	splash(fl.global_position, 30, 0.6)


# ── CPU ─────────────────────────────────────────────────────
## 실력만큼 빠르게 번갈아 누름 (가끔 같은 키 실수). 돌풍 경고가 뜨면 실력만큼 알아채고 제때 스페이스로 붙잡음.
## 갈매기가 내 높이로 날아오면 실력만큼 알아채고 그 아래에서 멈춰 기다림
func _think(delta: float) -> void:
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		var p := player_by_slot(s)
		if is_human(p) or L["done"]:
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p) / 2.0
		# 돌풍: 경고 때 한 번 정함 (잡을지 · 언제부터)
		if not _gust.is_empty() and not a.has("gust_seen_%d" % int(float(_gust["t1"]) * 100.0)):
			a["gust_seen_%d" % int(float(_gust["t1"]) * 100.0)] = true
			if rng.randf() < lerpf(0.55, 0.97, sk):
				a["grip_from"] = float(_gust["t1"]) - lerpf(0.05, 0.35, sk) + rng.randf_range(-0.05, 0.1)
				a["grip_to"] = float(_gust["t1"]) + GUST_DUR + 0.1
			else:
				a["grip_from"] = float(_gust["t1"]) + rng.randf_range(0.3, 1.2)   # 늦게 알아챔
				a["grip_to"] = float(_gust["t1"]) + GUST_DUR + 0.1
		L["grip"] = _elapsed >= float(a["grip_from"]) and _elapsed <= float(a["grip_to"])
		if L["grip"]:
			continue
		if _bird_wait(s, L, a, sk):
			a["next"] = maxf(float(a["next"]), 0.05)
			continue
		a["next"] = float(a["next"]) - delta
		var guard := 0
		while float(a["next"]) <= 0.0 and guard < 6 and not L["done"]:
			guard += 1
			var cps := lerpf(5.8, 8.8, sk) * (0.85 + 0.2 * sin(_t3 * 1.1 + s)) * rng.randf_range(0.85, 1.15)
			a["next"] = float(a["next"]) + 1.0 / maxf(cps, 1.0)
			var side := 1 - maxi(int(L["last"]), 0)
			if rng.randf() < lerpf(0.1, 0.02, sk):
				side = maxi(int(L["last"]), 0)   # 실수
			_step(s, side)


func _is_done() -> bool:
	if time_left <= 0.0:
		return true
	for s in _lanes:
		if not _lanes[s]["done"]:
			return false
	return true


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	var key := func(p: Dictionary) -> float:
		var L: Dictionary = _lanes[int(p["slot"])]
		if L["done"]:
			return 1000.0 - float(L["time"])
		return float(L["h"])
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	return order


## 온라인: 줄마다 높이 · 기절 · 붙잡기 (방장 → 손님)
func _net_state() -> Dictionary:
	var hs := {}
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		hs[s] = [float(L["h"]), float(L["stun"]), 1 if L["grip"] else 0]
	return {"hs": hs, "el": _elapsed}


func _net_apply(st: Dictionary) -> void:
	var hs: Dictionary = st.get("hs", {})
	for s in hs:
		if _lanes.has(int(s)):
			var L: Dictionary = _lanes[int(s)]
			var v: Array = hs[s]
			if float(v[0]) > float(L["h"]) + 0.05:
				L["pulse"] = 1.0
			L["h"] = float(v[0])
			L["stun"] = float(v[1])
			if v.size() >= 3:
				L["grip"] = int(v[2]) == 1
	_elapsed = float(st.get("el", _elapsed))


func _score_text(p: Dictionary) -> String:
	var L: Dictionary = _lanes[int(p["slot"])]
	if L["done"]:
		return "%.1fs" % float(L["time"])
	return "%dm" % int(round(float(L["h"])))


# ── 갈매기 ──────────────────────────────────────────────────
## 방장: 아직 오르는 중인 누군가의 머리 조금 위 높이로 갈매기 한 마리를 보냄
func _spawn_bird() -> void:
	_bird_t = rng.randf_range(2.4, 3.8)
	var climbing := []
	for s in _lanes:
		if not _lanes[s]["done"] and float(_lanes[s]["h"]) < TOP - 2.0:
			climbing.append(s)
	if climbing.is_empty():
		return
	var tgt: Dictionary = _lanes[climbing[rng.randi() % climbing.size()]]
	var by := clampf(START_Y + float(tgt["h"]) + rng.randf_range(1.3, 3.2), START_Y + 1.6, TOP_Y - 0.9)
	_bird_id += 1
	net_call("_bird_go", [_bird_id, by, 1.0 if rng.randf() < 0.5 else -1.0, _elapsed])


func _bird_go(id: int, y: float, dir: float, t0: float) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("MC bird id=%d y=%.1f dir=%d el=%.1f" % [id, y, int(dir), _elapsed])
	var n := Node3D.new()
	_ship.add_child(n)
	var white := std_mat(Color(0.96, 0.96, 0.94), 0.75)
	var grey := std_mat(Color(0.5, 0.53, 0.57), 0.7)
	var black := std_mat(Color(0.08, 0.08, 0.09), 0.6)
	var beak := std_mat(Color(0.98, 0.78, 0.22), 0.45)
	# 몸통 · 머리 · 부리 · 꼬리 (옆에서 보이게, 진행 방향 = +x)
	var body := SphereMesh.new()
	body.radius = 0.2
	body.height = 0.4
	add_mesh(body, white, Vector3.ZERO, Basis(), n).scale = Vector3(2.3, 0.95, 1.0)
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	add_mesh(head, white, Vector3(0.44, 0.12, 0), Basis(), n)
	var bk := CylinderMesh.new()
	bk.top_radius = 0.0
	bk.bottom_radius = 0.045
	bk.height = 0.2
	add_mesh(bk, beak, Vector3(0.64, 0.1, 0), Basis(Vector3.BACK, -PI / 2), n)
	var eye := SphereMesh.new()
	eye.radius = 0.025
	eye.height = 0.05
	add_mesh(eye, black, Vector3(0.52, 0.17, 0.11), Basis(), n)
	add_mesh(eye, black, Vector3(0.52, 0.17, -0.11), Basis(), n)
	var tail := PrismMesh.new()
	tail.size = Vector3(0.3, 0.32, 0.04)
	add_mesh(tail, grey, Vector3(-0.5, 0.0, 0), Basis(Vector3.BACK, PI / 2) * Basis(Vector3.RIGHT, PI / 2), n)
	# 날개 (어깨에서 위아래로 퍼덕, 끝은 검은 깃)
	var wl := Node3D.new()
	var wr := Node3D.new()
	wl.position = Vector3(0.08, 0.08, 0.14)
	wr.position = Vector3(0.08, 0.08, -0.14)
	n.add_child(wl)
	n.add_child(wr)
	for sd: float in [1.0, -1.0]:
		var w: Node3D = wl if sd > 0.0 else wr
		box(Vector3(0.34, 0.03, 0.62), grey, Vector3(0, 0, sd * 0.31), Basis(), w)
		box(Vector3(0.24, 0.025, 0.42), grey, Vector3(-0.06, 0, sd * 0.82), Basis(Vector3.UP, sd * 0.25), w)
		box(Vector3(0.16, 0.022, 0.2), black, Vector3(-0.1, 0, sd * 1.1), Basis(Vector3.UP, sd * 0.4), w)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.scale = Vector3.ONE * 1.5
	n.rotation.y = 0.0 if dir > 0.0 else PI
	n.visible = false
	_birds.append({"id": id, "y": y, "dir": dir, "t0": t0, "node": n, "wl": wl, "wr": wr, "hit": {}, "cried": false})


func _bird_x(b: Dictionary, t: float) -> float:
	return -float(b["dir"]) * BIRD_X0 + float(b["dir"]) * BIRD_V * (t - float(b["t0"]))


## 방장: 갈매기에 부딪힌 사람은 휘청이며 미끄러져 내려옴
func _bird_check() -> void:
	for b: Dictionary in _birds:
		var bx := _bird_x(b, _elapsed)
		var hit: Dictionary = b["hit"]
		for s in _lanes:
			var L: Dictionary = _lanes[s]
			if hit.has(s) or L["done"]:
				continue
			if absf(bx - float(L["x"])) < BIRD_HIT_X and absf(START_Y + float(L["h"]) + 0.55 - float(b["y"])) < BIRD_HIT_Y:
				hit[s] = true
				L["h"] = maxf(0.0, float(L["h"]) - BIRD_DROP)
				L["stun"] = 0.9
				L["last"] = -1
				net_call("_bird_hit", [s, int(b["id"])])


func _bird_hit(s: int, id: int) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("MC bird hit s=%d id=%d el=%.1f" % [s, id, _elapsed])
	var L: Dictionary = _lanes[s]
	L["slip"] = 0.8
	L["blown"] = 0.8
	for b: Dictionary in _birds:
		if int(b["id"]) == id:
			L["bdir"] = float(b["dir"])
			(b["hit"] as Dictionary)[s] = true
			var feather := (b["node"] as Node3D).global_position
			debris(feather, Color(0.95, 0.95, 0.93), 10)
	sfx("gull", 70)
	sfx("thud", 70)
	if is_local(player_by_slot(s)):
		shake(0.3)


## 모두: 날갯짓 · 위치. 화면에 들어올 즈음 끼룩. 반대편 밖으로 나가면 지움
func _update_birds(_delta: float) -> void:
	for i in range(_birds.size() - 1, -1, -1):
		var b: Dictionary = _birds[i]
		var bx := _bird_x(b, _elapsed)
		var n: Node3D = b["node"]
		var age := _elapsed - float(b["t0"])
		if absf(bx) > BIRD_X0 + 1.0 and age > 1.0:
			n.queue_free()
			_birds.remove_at(i)
			continue
		n.visible = true
		var flap := sin(_elapsed * 11.0 + float(b["id"]))
		n.position = Vector3(bx, float(b["y"]) - flap * 0.08 + sin(age * 1.7) * 0.06, 0.9)
		n.rotation.z = (0.08 if float(b["dir"]) > 0.0 else -0.08) * flap
		(b["wl"] as Node3D).rotation.x = -0.55 * flap - 0.1
		(b["wr"] as Node3D).rotation.x = 0.55 * flap + 0.1
		if not b["cried"] and absf(bx - _cam_x) < 16.0 and absf(float(b["y"]) - _cam_y) < 9.0:
			b["cried"] = true
			sfx("gull", 55)


## CPU: 이 갈매기가 곧 내 높이를 지나가면 그 아래에서 기다림 (갈매기마다 알아챌지 한 번 정함)
func _bird_wait(s: int, L: Dictionary, a: Dictionary, sk: float) -> bool:
	var my := START_Y + float(L["h"]) + 0.55
	var rate := lerpf(5.8, 8.8, sk) * STEP
	for b: Dictionary in _birds:
		if (b["hit"] as Dictionary).has(s):
			continue
		var key := "bird_%d" % int(b["id"])
		if not a.has(key):
			a[key] = rng.randf() < lerpf(0.5, 0.95, sk)
		if not a[key]:
			continue
		var bx := _bird_x(b, _elapsed)
		var tl := (float(L["x"]) - bx) / (float(b["dir"]) * BIRD_V)
		if tl < -0.2 or tl > 2.2:
			continue
		var gap := float(b["y"]) - my
		# 지나가기 전에 그 높이에 닿겠으면 멈춤. 이미 갈매기 위로 지나쳤으면 그냥 감
		if gap > -BIRD_HIT_Y - 0.1 and gap < BIRD_HIT_Y + 0.25 + rate * maxf(tl, 0.0):
			return true
	return false
