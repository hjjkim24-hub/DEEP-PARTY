extends "res://scripts/minigames/minigame_3d.gd"
## 돛대 오르기 (A/D 또는 ←/→ 번갈아 + 스페이스 꾹): 돛대 네 개짜리 범선을 옆에서 본 모습.
## 돛대마다 뱃전에서 비스듬히 올라가는 밧줄 사다리(줄사다리)를 타고 맨 꼭대기 깃발까지 (약 26m).
## 두 키를 번갈아 누를 때마다 한 칸씩 올라감. 같은 키를 두 번 누르면 발이 미끄러져 살짝 내려옴.
## 팔 힘: 한 번 오를 때마다 줄어듦 → 바닥나면 매달려 헉헉 (잠깐 못 오름). 손을 쉬면 다시 참 (망대 위에서 쉬면 더 빨리).
## 돌풍: 경고가 뜬 뒤 바람이 몰아침 → 그동안 스페이스를 꾹 눌러 붙잡고 있어야 함 (붙잡는 동안 힘이 줄어듦).
##       안 붙잡았거나 힘이 바닥나면 쭉 미끄러져 내려옴 (높이 있을수록 많이).
## 꼭대기 깃발을 먼저 잡은 순서대로 순위 (시간이 다 되면 높이 올라간 순). 화면은 내 말을 따라 올라감.

const LANE_GAP := 5.6
const START_Y := 1.2            ## 뱃전 위 (오르기 시작하는 발 높이)
const TOP_Y := 26.6             ## 깃발을 잡는 발 높이
const TOP := TOP_Y - START_Y    ## 올라야 하는 높이
const STEP := 0.26
const SLIP := 0.2
const COST := 0.03              ## 한 번 오를 때 쓰는 힘
const REGEN := 0.55             ## 쉴 때 초당 차는 힘
const TIRED_T := 1.6            ## 힘이 바닥나면 매달려 숨 고르는 시간
const GRIP_COST := 0.2          ## 붙잡는 동안 초당 쓰는 힘
const GUST_WARN := 1.4
const GUST_DUR := 1.6
## 줄사다리가 지나는 길 (y, 돛대에서 앞쪽으로 떨어진 거리 z): 뱃전 → 아래 망대 → 윗돛대 → 꼭대기
const ROUTE := [Vector2(1.2, 2.85), Vector2(9.8, 0.62), Vector2(10.05, 1.45), Vector2(18.4, 0.42), Vector2(18.65, 0.92), Vector2(26.0, 0.3), Vector2(26.7, 0.3)]
const REST_YS := [10.05, 18.65]  ## 망대 (쉬면 힘이 더 빨리 참)
## 줄사다리 세 구간: [아래 y, 아래 z(첫 구간은 뱃전), 아래 반폭, 위 y, 위 z, 위 반폭, 세로줄 수]
const RUNG_GAP := 0.6
const WORN_N := 6               ## 판마다 낡은 디딤줄 수 (네 돛대 모두 같은 높이)
const CAREFUL := 0.45           ## 낡은 줄 밟기 직전 이만큼 멈췄으면 버팀
const SNAP_DROP := 1.2

var _ship: Node3D
var _lanes := {}                ## slot → {x, h, shown, last, stun, done, time, pawn, mast, st, tired, grip, idle, bar...}
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
var _worn: Array = []          ## 낡은 디딤줄 높이 (발 기준 y)


func _init() -> void:
	title = "MAST CLIMB"
	how_to = "Climb the rope ladder to the flag at the very top of the mast! Press the two keys one after the other to climb - the same key twice makes you slip. Every pull uses arm strength: if it runs out you'll hang there catching your breath, so rest a moment before it empties. Some rungs are old and frayed: pause for a moment before stepping on them or they'll snap! When a GUST is coming, hold SPACE to cling on or you'll be blown down!"
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
	var worn := {}
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
			var wi := _worn_index(y)
			if wi < 0:
				_rod(Vector3(-w, y, z + 0.01), Vector3(w, y, z + 0.01), 0.022, lad, root)
			else:
				worn[wi] = _worn_rung(root, w, y, z + 0.01)
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
	return {"root": root, "flag": flag, "fm": fm, "segs": segs, "skull": sk, "z0": z0, "worn": worn}


func _worn_index(y: float) -> int:
	for i in _worn.size():
		if absf(float(_worn[i]) - y) < 0.01:
			return i
	return -1


## 모든 디딤줄 높이
func _rung_ys() -> Array:
	var out := []
	for sc: Array in [[START_Y, 9.8], [10.05, 18.4], [18.65, 26.0]]:
		var y := float(sc[0]) + RUNG_GAP
		while y < float(sc[1]) - 0.1:
			out.append(y)
			y += RUNG_GAP
	return out


## 낡은 디딤줄: 색 바래고 가운데가 축 처짐 + 해진 올. 끊어지면 양쪽에 반 토막씩 대롱대롱
func _worn_rung(root: Node3D, w: float, y: float, z: float) -> Dictionary:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.48, 0.38)
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.15)
	m.emission_energy_multiplier = 0.0
	var whole := Node3D.new()
	root.add_child(whole)
	var mid := Vector3(0.05, y - 0.13, z)
	_rod(Vector3(-w, y, z), mid, 0.03, m, whole)
	_rod(mid, Vector3(w, y, z), 0.03, m, whole)
	for k in 3:   # 해진 올
		var fx := -w * 0.5 + k * w * 0.45
		_rod(Vector3(fx, y - 0.05 - absf(fx) * 0.03, z), Vector3(fx + 0.05, y - 0.18, z + 0.02), 0.01, m, whole)
	var broken := Node3D.new()
	broken.visible = false
	root.add_child(broken)
	_rod(Vector3(-w, y, z), Vector3(-w + 0.1, y - 0.4, z + 0.03), 0.017, m, broken)
	_rod(Vector3(w, y, z), Vector3(w - 0.08, y - 0.34, z + 0.03), 0.017, m, broken)
	return {"whole": whole, "broken": broken, "mat": m, "y": y}


## 힘 게이지 (말 옆 세로 막대, 항상 화면 앞쪽에 보임)
func _make_bar() -> Dictionary:
	var root := Node3D.new()
	_ship.add_child(root)
	var bg_m := StandardMaterial3D.new()
	bg_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_m.albedo_color = Color(0.05, 0.06, 0.08, 0.75)
	bg_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_m.no_depth_test = true
	bg_m.render_priority = 2
	var q := QuadMesh.new()
	q.size = Vector2(0.24, 1.3)
	add_mesh(q, bg_m, Vector3.ZERO, Basis(), root)
	var fill_m := StandardMaterial3D.new()
	fill_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_m.no_depth_test = true
	fill_m.render_priority = 3
	var fq := QuadMesh.new()
	fq.size = Vector2(0.17, 1.2)
	var fill := add_mesh(fq, fill_m, Vector3(0, 0, 0.01), Basis(), root)
	return {"root": root, "fill": fill, "mat": fill_m}


func _setup_game() -> void:
	var wr := RandomNumberGenerator.new()
	wr.seed = rng.randi()
	var cand: Array = _rung_ys().filter(func(y: float) -> bool: return y > START_Y + 2.0 and y < TOP_Y - 1.5 and absf(y - 10.05) > 0.7 and absf(y - 18.65) > 0.7)
	_worn.clear()
	var guard := 0
	while _worn.size() < WORN_N and guard < 200:
		guard += 1
		var y: float = cand[wr.randi() % cand.size()]
		var ok := true
		for o: float in _worn:
			if absf(o - y) < 2.6:
				ok = false
		if ok:
			_worn.append(y)
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
			"mast": mast, "pulse": 0.0, "slip": 0.0, "st": 1.0, "tired": 0.0, "grip": false, "idle": 1.0, "bar": _make_bar(),
			"blown": 0.0, "broken": {}}
		_ai[s] = {"next": rng.randf_range(0.2, 0.5), "rest": false, "grip_from": INF, "grip_to": -INF}
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


## 방장: 한 발. 번갈아 누르면 위로 (힘 씀), 같은 키 두 번이면 미끄러짐. 붙잡는 중 · 헉헉 중엔 못 오름
func _step(s: int, side: int) -> void:
	var L: Dictionary = _lanes.get(s, {})
	if L.is_empty() or L["done"] or float(L["stun"]) > 0.0 or float(L["tired"]) > 0.0 or L["grip"]:
		return
	var waited := float(L["idle"])
	L["idle"] = 0.0
	if int(L["last"]) != side:
		var y0 := START_Y + float(L["h"])
		var wi := _worn_cross(L, y0, y0 + STEP)
		if wi >= 0:
			if waited >= CAREFUL:
				net_call("_creak_fx", [s, wi])
			else:
				# 툭! 끊어져 떨어짐
				L["broken"][wi] = true
				L["h"] = maxf(0.0, float(L["h"]) - SNAP_DROP)
				L["stun"] = 0.6
				L["last"] = -1
				net_call("_snap_fx", [s, wi])
				return
	if int(L["last"]) == side:
		L["h"] = maxf(0.0, float(L["h"]) - SLIP)
		L["stun"] = 0.22
		net_call("_slip_fx", [s])
	else:
		L["h"] = float(L["h"]) + STEP
		L["pulse"] = 1.0
		L["st"] = float(L["st"]) - COST
		if float(L["h"]) >= TOP:
			L["h"] = TOP
			net_call("_finish", [s, _elapsed])
		elif float(L["st"]) <= 0.0:
			L["st"] = 0.0
			L["tired"] = TIRED_T
			net_call("_tired_fx", [s])
	L["last"] = side


## 이 발에 밟게 되는 (아직 안 끊긴) 낡은 줄
func _worn_cross(L: Dictionary, y_from: float, y_to: float) -> int:
	var br: Dictionary = L["broken"]
	for i in _worn.size():
		var wy := float(_worn[i])
		if not br.has(i) and y_from < wy and wy <= y_to:
			return i
	return -1


func _snap_fx(s: int, wi: int) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("MC snap s=%d wi=%d el=%.1f" % [s, wi, _elapsed])
	var L: Dictionary = _lanes[s]
	L["broken"][wi] = true
	L["slip"] = 0.8
	L["blown"] = 0.6
	var w: Dictionary = (L["mast"]["worn"] as Dictionary).get(wi, {})
	if not w.is_empty():
		(w["whole"] as Node3D).visible = false
		(w["broken"] as Node3D).visible = true
	var pawn: Node3D = L["pawn"]
	sfx("thud", 90)
	debris(pawn.global_position + Vector3(0, 0.4, 0.2), Color(0.66, 0.6, 0.5), 10)
	if is_local(player_by_slot(s)):
		shake(0.25)


func _creak_fx(s: int, _wi: int) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("MC creak s=%d el=%.1f" % [s, _elapsed])
	var pawn: Node3D = _lanes[s]["pawn"]
	if is_local(player_by_slot(s)):
		sfx("thud", 30)


func _slip_fx(s: int) -> void:
	var L: Dictionary = _lanes[s]
	L["slip"] = 0.3
	if is_local(player_by_slot(s)):
		sfx("thud", 80)


func _tired_fx(s: int) -> void:
	var L: Dictionary = _lanes[s]
	L["tired"] = TIRED_T
	var pawn: Node3D = L["pawn"]


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
		for s in _lanes:
			_stamina(s, delta)
			scores[s] = float(_lanes[s]["h"])
		_gust_check()
	_update_gust(delta)
	# 배가 천천히 출렁
	_ship.rotation = Vector3(sin(_t3 * 0.45) * 0.01, 0, sin(_t3 * 0.31) * 0.006)
	_place(delta)
	_place_cam(false, delta)


## 방장: 힘 (오르면 줄고, 쉬면 참 · 망대 위에선 더 빨리 · 붙잡는 동안 줄어듦)
func _stamina(s: int, delta: float) -> void:
	var L: Dictionary = _lanes[s]
	L["stun"] = maxf(0.0, float(L["stun"]) - delta)
	L["idle"] = float(L["idle"]) + delta
	if L["done"]:
		L["st"] = 1.0
		return
	if float(L["tired"]) > 0.0:
		L["tired"] = maxf(0.0, float(L["tired"]) - delta)
		L["st"] = minf(1.0, float(L["st"]) + REGEN * 0.8 * delta)
		return
	if L["grip"]:
		L["st"] = maxf(0.0, float(L["st"]) - GRIP_COST * delta)
		return
	if float(L["idle"]) > 0.3:
		var y := START_Y + float(L["h"])
		var bonus := 1.0
		for ry: float in REST_YS:
			if absf(y - ry) < 0.5:
				bonus = 2.0
		L["st"] = minf(1.0, float(L["st"]) + REGEN * bonus * delta)


# ── 돌풍 ────────────────────────────────────────────────────
func _gust_go(dir: float, t1: float) -> void:
	if OS.get_environment("MG_DEBUG") != "":
		print("GUST go el=%.2f t1=%.2f" % [_elapsed, t1])
	_gust = {"dir": dir, "t1": t1, "hit": {}, "warned": false, "blew": false}


## 방장: 돌풍이 부는 동안 안 붙잡았거나 힘이 바닥난 사람은 쭉 미끄러져 내려옴
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
		if not L["grip"] or float(L["st"]) <= 0.0:
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
		if is_client():
			L["tired"] = maxf(0.0, float(L["tired"]) - delta)
		var x: float = L["x"]
		var y := START_Y + float(L["shown"])
		var z := _route_z(y, float(mast["z0"])) + 0.3
		if L["done"]:
			# 꼭대기에서 깃대 붙잡고 방방
			pawn.position = Vector3(x + 0.05, TOP_Y + absf(sin(_t3 * 6.0)) * 0.2, 0.42)
			pawn.rotation = Vector3(0, PI + sin(_t3 * 3.0) * 0.5, 0)
		else:
			# 줄사다리 기울기만큼 몸을 기댐. 한 발마다 좌우로 흔들 · 헉헉이면 축 늘어짐 · 붙잡으면 바짝 붙음 · 날리면 휘청
			var z_up := _route_z(y + 0.3, float(mast["z0"])) + 0.3
			var tilt := atan2(z - z_up, 0.3)
			var sway := sin(float(L["shown"]) / STEP * PI) * 0.16
			var tired := float(L["tired"]) > 0.0
			var grip: bool = L["grip"]
			if grip:
				z -= 0.12
				sway *= 0.2
			var gust_lean := gdir * 0.25 if (blowing and grip) else 0.0
			var flail := sin(_t3 * 26.0) * 0.35 * float(L["blown"])
			pawn.position = Vector3(x + sway * 0.4 + gdir * float(L["blown"]) * 0.5, y + float(L["pulse"]) * 0.05 - (0.08 if tired else 0.0), z)
			pawn.rotation = Vector3(-tilt * 0.8 - float(L["slip"]) * 0.6 + (0.25 if tired else 0.0), PI, sway + gust_lean + flail + (sin(_t3 * 3.0) * 0.08 if tired else 0.0))
		# 낡은 줄 경고: 발 바로 위(한 발~두 발 거리)에 있으면 주황빛으로 깜빡
		var wd: Dictionary = mast["worn"]
		for wi in wd:
			var wm: StandardMaterial3D = wd[wi]["mat"]
			var gap := float(wd[wi]["y"]) - (START_Y + float(L["shown"]))
			var near: bool = gap > 0.0 and gap < 0.9 and not L["done"]
			wm.emission_energy_multiplier = (1.2 + 1.0 * sin(_t3 * 14.0)) if near else 0.0
		# 힘 게이지: 말 오른쪽 옆
		var bar: Dictionary = L["bar"]
		var br: Node3D = bar["root"]
		br.visible = not L["done"]
		br.position = pawn.position + Vector3(0.62, 0.75, 0.25)
		var st := float(L["st"])
		var fill: Node3D = bar["fill"]
		fill.scale = Vector3(1, maxf(st, 0.001), 1)
		fill.position = Vector3(0, -0.6 * (1.0 - st), 0.01)
		var col := Color(0.95, 0.25, 0.2).lerp(Color(1.0, 0.8, 0.2), clampf(st * 2.0, 0.0, 1.0)).lerp(Color(0.35, 0.9, 0.4), clampf(st * 2.0 - 1.0, 0.0, 1.0))
		if float(L["tired"]) > 0.0 and fmod(_t3, 0.3) < 0.15:
			col = Color(1, 1, 1)
		(bar["mat"] as StandardMaterial3D).albedo_color = col
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
## 실력만큼 빠르게 번갈아 누름 (가끔 같은 키 실수). 힘이 떨어지면 쉬어 감 (실력이 낮으면 바닥날 때까지 몰아붙이기도).
## 돌풍 경고가 뜨면 실력만큼 알아채고 제때 스페이스로 붙잡음
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
		# 쉬기: 실력 좋으면 미리 쉼 · 돌풍 앞두고 힘 아껴 둠
		var lo := lerpf(-0.05, 0.22, sk)
		var hi := lerpf(0.55, 0.92, sk)
		var gust_soon := not _gust.is_empty() and float(_gust["t1"]) - _elapsed < 1.2 and sk > 0.4
		if float(L["st"]) < lo or (gust_soon and float(L["st"]) < 0.45):
			a["rest"] = true
		if a["rest"] and float(L["st"]) >= hi:
			a["rest"] = false
		if a["rest"] or float(L["tired"]) > 0.0:
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
			var y0 := START_Y + float(L["h"])
			var wi := _worn_cross(L, y0, y0 + STEP)
			if wi >= 0 and int(a.get("worn_seen", -1)) != wi:
				a["worn_seen"] = wi
				if rng.randf() < lerpf(0.45, 0.95, sk):
					a["next"] = float(a["next"]) + CAREFUL + rng.randf_range(0.05, 0.2)
					break
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


## 온라인: 줄마다 높이 · 기절 · 힘 · 헉헉 · 붙잡기 (방장 → 손님)
func _net_state() -> Dictionary:
	var hs := {}
	for s in _lanes:
		var L: Dictionary = _lanes[s]
		hs[s] = [float(L["h"]), float(L["stun"]), float(L["st"]), float(L["tired"]), 1 if L["grip"] else 0]
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
			if v.size() >= 5:
				L["st"] = float(v[2])
				L["tired"] = float(v[3])
				L["grip"] = int(v[4]) == 1
	_elapsed = float(st.get("el", _elapsed))


func _score_text(p: Dictionary) -> String:
	var L: Dictionary = _lanes[int(p["slot"])]
	if L["done"]:
		return "%.1fs" % float(L["time"])
	return "%dm" % int(round(float(L["h"])))
