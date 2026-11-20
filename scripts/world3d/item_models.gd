class_name ItemModels
## 상점 아이템 3D 모델 (실물처럼: 유리 · 나무 · 쇠 · 상아 · 양피지 · 조개 · 밧줄 재질)
## 판 위 연출(사용할 때 말 머리 위에 떠오름, 그물 던지기)과 아이콘 그림(tools/render_item_icons.gd) 둘 다 이걸 씀.
## 크기: 대략 높이 1 m 안팎, 원점 = 바닥 가운데

const ORDER := ["potion", "shield", "dice", "scroll", "conch", "oxygen", "net"]


static func make(id: String) -> Node3D:
	match id:
		"potion":
			return _potion()
		"shield":
			return _shield()
		"dice":
			return _dice()
		"scroll":
			return _scroll()
		"conch":
			return _conch()
		"oxygen":
			return _oxygen()
		"net":
			return _net_bundle()
	return Node3D.new()


# ── 재질 ────────────────────────────────────────────────────
static func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## 결이 있는 재질: 노이즈로 색 얼룩 + 울퉁불퉁한 노멀 (나무 · 양피지 · 밧줄 · 녹슨 쇠)
static func _grain(c: Color, rough: float, freq: Vector2, contrast: float, bump: float, metal: float = 0.0, seed_: int = 1) -> StandardMaterial3D:
	var m := _mat(c, rough, metal)
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, c.darkened(contrast))
	g.set_color(1, c.lightened(contrast * 0.6))
	tex.color_ramp = g
	m.albedo_color = Color.WHITE
	m.albedo_texture = tex
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0 * bump
	nt.noise = n
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = bump
	m.uv1_scale = Vector3(freq.x, freq.y, 1.0)
	return m


static func _glass(tint: Color) -> StandardMaterial3D:
	var m := _mat(Color(tint, 0.38), 0.04)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


static func _mi(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


static func _cyl(r_top: float, r_bot: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _sph(r: float, h: float = -1.0, seg := 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0 else r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


static func _torus(r_in: float, r_out: float, seg := 32) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = seg
	t.ring_segments = 10
	return t


## 회전체 (profile = [반지름, 높이] 아래→위)
static func _lathe(profile: Array, seg := 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			var u0 := float(k) / seg
			var u1 := float(k + 1) / seg
			var v0 := float(i) / (profile.size() - 1)
			var v1 := float(i + 1) / (profile.size() - 1)
			for q in [[p00, u0, v0], [p10, u0, v1], [p11, u1, v1], [p00, u0, v0], [p11, u1, v1], [p01, u1, v0]]:
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	st.generate_normals()
	return st.commit()


# ── 물약: 둥근 바닥 유리 플라스크 + 붉은 약 + 코르크 마개 + 목에 감은 끈 ─────
static func _potion() -> Node3D:
	var root := Node3D.new()
	var prof := []
	for k in 13:
		var a := -PI * 0.5 + PI * 0.86 * k / 12.0
		prof.append(Vector2(cos(a) * 0.3, 0.3 + sin(a) * 0.3))
	prof.append(Vector2(0.075, 0.68))
	prof.append(Vector2(0.075, 0.86))
	prof.append(Vector2(0.095, 0.88))
	prof.append(Vector2(0.095, 0.9))
	_mi(_lathe(prof), _glass(Color(0.85, 0.95, 0.95)), Vector3.ZERO, root)
	# 약: 반쯤 찬 붉은 액체 (속이 살짝 빛남) + 수면
	var liq := _mat(Color(0.75, 0.05, 0.12), 0.15)
	liq.emission_enabled = true
	liq.emission = Color(0.6, 0.02, 0.08)
	liq.emission_energy_multiplier = 0.5
	var lp := []
	for k in 8:
		var a := -PI * 0.5 + (PI * 0.5 + 0.35) * k / 7.0
		lp.append(Vector2(cos(a) * 0.285, 0.3 + sin(a) * 0.285))
	lp.append(Vector2(0.0, 0.3 + sin(0.35) * 0.285))
	_mi(_lathe(lp), liq, Vector3.ZERO, root)
	# 코르크 + 끈
	_mi(_cyl(0.088, 0.07, 0.14, 16), _grain(Color(0.62, 0.45, 0.28), 0.9, Vector2(3, 3), 0.35, 0.8, 0.0, 3), Vector3(0, 0.93, 0), root)
	_mi(_torus(0.074, 0.092, 24), _grain(Color(0.7, 0.62, 0.45), 0.95, Vector2(8, 1), 0.3, 0.6, 0.0, 5), Vector3(0, 0.74, 0), root)
	# 바닥 빛 반사 (유리 속 하이라이트)
	return root


# ── 따개비 방패: 판자를 이은 둥근 나무 방패 + 쇠테 · 가운데 쇠 돌기 + 따개비가 다닥다닥 ─────
static func _shield() -> Node3D:
	var root := Node3D.new()
	var face := Node3D.new()
	face.rotation.x = PI * 0.5 - 0.25        # 거의 세워서 앞(+Z)을 봄
	face.position = Vector3(0, 0.5, 0)
	root.add_child(face)
	var wood := _grain(Color(0.4, 0.27, 0.16), 0.85, Vector2(1, 6), 0.45, 1.0, 0.0, 11)
	_mi(_cyl(0.48, 0.48, 0.06, 40), wood, Vector3.ZERO, face)
	# 판자 사이 홈
	var dark := _mat(Color(0.12, 0.08, 0.05), 0.9)
	for x in [-0.24, 0.0, 0.24]:
		var h := 2.0 * sqrt(maxf(0.48 * 0.48 - x * x, 0.0)) - 0.04
		var bm := BoxMesh.new()
		bm.size = Vector3(0.012, 0.062, h)
		_mi(bm, dark, Vector3(x + 0.12, 0.0, 0), face)
	var iron := _grain(Color(0.33, 0.3, 0.28), 0.55, Vector2(4, 4), 0.4, 0.8, 0.75, 21)
	_mi(_torus(0.45, 0.52, 48), iron, Vector3.ZERO, face, Basis.from_scale(Vector3(1, 0.5, 1)))
	_mi(_sph(0.13, 0.12), iron, Vector3(0, 0.03, 0), face)
	for a in 8:   # 테두리 징
		var t := TAU * a / 8
		_mi(_sph(0.022), iron, Vector3(cos(t) * 0.42, 0.04, sin(t) * 0.42), face)
	# 따개비: 화산 모양 껍데기 무더기 (가장자리 · 아래쪽에 몰림)
	var shell := _grain(Color(0.7, 0.67, 0.6), 0.85, Vector2(2, 2), 0.3, 0.9, 0.0, 31)
	var hole := _mat(Color(0.36, 0.3, 0.26), 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 34:
		var t := rng.randf_range(-PI * 0.95, PI * 0.15)
		var r := rng.randf_range(0.18, 0.44)
		var s := rng.randf_range(0.025, 0.055)
		var pos := Vector3(cos(t) * r, 0.03 + s * 0.4, sin(t) * r)
		_mi(_cyl(s * 0.45, s, s * 1.1, 8), shell, pos, face)
		_mi(_cyl(s * 0.18, s * 0.18, 0.004, 6), hole, pos + Vector3(0, s * 0.56, 0), face)
	# 초록 물때 얼룩
	var slime := _mat(Color(0.2, 0.32, 0.18, 0.55), 0.9)
	slime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mi(_cyl(0.3, 0.3, 0.002, 24), slime, Vector3(-0.08, 0.032, -0.14), face, Basis.from_scale(Vector3(1.0, 1, 0.6)))
	return root


# ── 추가 주사위: 손때 묻은 상아 주사위 (1 · 2 · 3 눈이 두 번씩), 모서리 둥글게 ─────
static func _dice() -> Node3D:
	var root := Node3D.new()
	var cube := Node3D.new()
	cube.position = Vector3(0, 0.3, 0)
	cube.rotation = Vector3(0.35, 0.6, 0.1)
	root.add_child(cube)
	var ivory := _grain(Color(0.86, 0.8, 0.66), 0.42, Vector2(2, 2), 0.22, 0.3, 0.0, 41)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	_mi(bm, ivory, Vector3.ZERO, cube)
	# 둥근 모서리 흉내: 모서리마다 살짝 큰 원기둥
	for ax in 3:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var c := _cyl(0.035, 0.035, 0.5, 10)
				var p := Vector3.ZERO
				var b := Basis()
				match ax:
					0:
						p = Vector3(0, sx * 0.232, sy * 0.232)
						b = Basis(Vector3(0, 0, 1), PI * 0.5)
					1:
						p = Vector3(sx * 0.232, 0, sy * 0.232)
					2:
						p = Vector3(sx * 0.232, sy * 0.232, 0)
						b = Basis(Vector3(1, 0, 0), PI * 0.5)
				_mi(c, ivory, p, cube, b)
	var pip := _mat(Color(0.45, 0.06, 0.05), 0.5)
	var faces := [[Vector3(0, 1, 0), 1], [Vector3(0, -1, 0), 1], [Vector3(1, 0, 0), 2], [Vector3(-1, 0, 0), 2], [Vector3(0, 0, 1), 3], [Vector3(0, 0, -1), 3]]
	for f in faces:
		var n: Vector3 = f[0]
		var u := n.cross(Vector3(0, 0, 1) if absf(n.z) < 0.9 else Vector3(1, 0, 0)).normalized()
		var v := n.cross(u)
		var spots := []
		match int(f[1]):
			1:
				spots = [Vector2.ZERO]
			2:
				spots = [Vector2(-0.12, -0.12), Vector2(0.12, 0.12)]
			3:
				spots = [Vector2(-0.13, -0.13), Vector2.ZERO, Vector2(0.13, 0.13)]
		for s in spots:
			var pos: Vector3 = n * 0.245 + u * s.x + v * s.y
			_mi(_sph(0.045, 0.03, 12), pip, pos, cube, Basis(Quaternion(Vector3.UP, n)))
	return root


# ── 순간이동서: 돌돌 만 양피지 + 나무 축 손잡이 + 끈 · 붉은 밀랍 봉인 ─────
static func _scroll() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.position = Vector3(0, 0.2, 0)
	body.rotation = Vector3(0, 0.5, PI * 0.5)
	root.add_child(body)
	var parch := _grain(Color(0.78, 0.66, 0.46), 0.9, Vector2(2, 3), 0.3, 0.6, 0.0, 51)
	_mi(_cyl(0.15, 0.15, 0.78, 32), parch, Vector3.ZERO, body)
	# 겉장이 살짝 풀려 겹친 자국
	_mi(_cyl(0.156, 0.156, 0.76, 32), _grain(Color(0.8, 0.68, 0.48), 0.9, Vector2(2, 3), 0.35, 0.6, 0.0, 52), Vector3(0.006, 0, 0.004), body)
	var wood := _grain(Color(0.32, 0.2, 0.12), 0.6, Vector2(1, 3), 0.4, 0.6, 0.0, 53)
	for y in [-0.43, 0.43]:
		_mi(_cyl(0.05, 0.05, 0.12, 16), wood, Vector3(0, y, 0), body)
		_mi(_sph(0.065), wood, Vector3(0, y * 1.2, 0), body)
	# 끈 + 밀랍 봉인
	var cord := _grain(Color(0.55, 0.12, 0.1), 0.9, Vector2(6, 1), 0.3, 0.5, 0.0, 54)
	_mi(_torus(0.15, 0.17, 32), cord, Vector3.ZERO, body)
	var wax := _mat(Color(0.62, 0.05, 0.06), 0.35)
	_mi(_cyl(0.075, 0.08, 0.03, 20), wax, Vector3(0.17, 0, 0), body, Basis(Vector3(0, 0, 1), -PI * 0.5))
	_mi(_cyl(0.035, 0.035, 0.012, 16), _mat(Color(0.5, 0.03, 0.05), 0.4), Vector3(0.188, 0, 0), body, Basis(Vector3(0, 0, 1), -PI * 0.5))
	return root


# ── 덫 탐지 소라: 뾰족한 나선 꼭대기 · 어깨에 돌기 · 크림색 바탕에 갈색 띠 · 분홍빛 넓은 입구 ─────
static func _conch() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.rotation = Vector3(0.0, 0.0, -1.15)        # 비스듬히 눕힘
	body.position = Vector3(0.05, 0.3, 0)
	root.add_child(body)
	var prof := [Vector2(0.0, -0.3), Vector2(0.04, -0.26), Vector2(0.07, -0.12), Vector2(0.15, 0.05), Vector2(0.24, 0.22),
		Vector2(0.28, 0.33), Vector2(0.27, 0.4), Vector2(0.2, 0.47), Vector2(0.15, 0.52), Vector2(0.13, 0.56),
		Vector2(0.09, 0.6), Vector2(0.075, 0.64), Vector2(0.045, 0.69), Vector2(0.03, 0.72), Vector2(0.0, 0.76)]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.24, 0.42, 0.48, 0.62, 0.66, 0.8, 0.84, 1.0])
	g.colors = PackedColorArray([Color(0.92, 0.84, 0.7), Color(0.9, 0.8, 0.64), Color(0.6, 0.35, 0.2), Color(0.92, 0.82, 0.66),
		Color(0.66, 0.4, 0.22), Color(0.93, 0.84, 0.68), Color(0.62, 0.38, 0.22), Color(0.92, 0.83, 0.67), Color(0.7, 0.45, 0.28), Color(0.85, 0.76, 0.62)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var shell := _mat(Color.WHITE, 0.42)
	shell.albedo_texture = gt
	var n := FastNoiseLite.new()
	n.seed = 9
	n.frequency = 0.05
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.noise = n
	shell.normal_enabled = true
	shell.normal_texture = nt
	shell.normal_scale = 0.6
	_mi(_lathe(prof, 40), shell, Vector3.ZERO, body)
	# 꼭대기 나선 골: 아래로 내려갈수록 굵어지는 나선 띠
	var ridge := _mat(Color(0.84, 0.72, 0.56), 0.5)
	var steps := 70
	for k in steps:
		var t := float(k) / steps
		var y := 0.74 - t * 0.27
		var r := lerpf(0.02, 0.15, t) + 0.005
		var a := t * TAU * 3.2
		var p0 := Vector3(cos(a) * r, y, sin(a) * r)
		var t1 := float(k + 1) / steps
		var a1 := t1 * TAU * 3.2
		var r1 := lerpf(0.02, 0.15, t1) + 0.005
		var p1 := Vector3(cos(a1) * r1, 0.74 - t1 * 0.27, sin(a1) * r1)
		var v := p1 - p0
		_mi(_cyl(0.008 + t * 0.012, 0.008 + t * 0.012, v.length() * 1.15, 6), ridge, p0 + v * 0.5, body, Basis(Quaternion(Vector3.UP, v.normalized())))
	# 어깨 돌기
	for k in 9:
		var a := TAU * k / 9.0
		var p := Vector3(cos(a) * 0.27, 0.37, sin(a) * 0.27)
		_mi(_cyl(0.0, 0.035, 0.09, 8), _mat(Color(0.9, 0.82, 0.68), 0.5), p + p.normalized() * 0.02 + Vector3(0, 0.04, 0), body,
			Basis(Quaternion(Vector3.UP, (p.normalized() + Vector3(0, 0.9, 0)).normalized())))
	# 입구: 넓게 벌어진 분홍 입술 + 안쪽 짙은 분홍
	var lip := _mat(Color(0.95, 0.62, 0.58), 0.22)
	lip.clearcoat_enabled = true
	lip.clearcoat = 0.8
	_mi(_sph(0.5, 1.0, 24), lip, Vector3(0.0, 0.1, 0.16), body, Basis.from_scale(Vector3(0.24, 0.5, 0.1)))
	_mi(_sph(0.5, 1.0, 20), _mat(Color(0.7, 0.3, 0.33), 0.3), Vector3(0.0, 0.11, 0.2), body, Basis.from_scale(Vector3(0.14, 0.36, 0.05)))
	return root


# ── 산소통: 노랗게 칠한 강철 잠수통 (칠 벗겨짐) + 크롬 밸브 · 손잡이 + 압력계 + 검은 고무 띠 ─────
static func _oxygen() -> Node3D:
	var root := Node3D.new()
	var paint := _grain(Color(0.92, 0.68, 0.08), 0.38, Vector2(2, 2), 0.18, 0.25, 0.25, 61)
	var prof := [Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.19, 0.03), Vector2(0.2, 0.08), Vector2(0.2, 0.72)]
	for k in 7:
		var a := PI * 0.5 * (k + 1) / 7.0
		prof.append(Vector2(0.2 * cos(a) + 0.0, 0.72 + 0.16 * sin(a)))
	_mi(_lathe(prof, 36), paint, Vector3.ZERO, root)
	var rubber := _mat(Color(0.06, 0.06, 0.07), 0.8)
	for y in [0.18, 0.56]:
		_mi(_torus(0.188, 0.222, 40), rubber, Vector3(0, y, 0), root, Basis.from_scale(Vector3(1, 1.6, 1)))
	var chrome := _mat(Color(0.86, 0.87, 0.9), 0.12, 1.0)
	_mi(_cyl(0.05, 0.06, 0.1, 16), chrome, Vector3(0, 0.92, 0), root)
	_mi(_cyl(0.045, 0.045, 0.16, 16), chrome, Vector3(0, 1.0, 0), root, Basis(Vector3(0, 0, 1), PI * 0.5))
	_mi(_torus(0.04, 0.07, 20), _mat(Color(0.1, 0.1, 0.12), 0.6), Vector3(0, 1.08, 0), root)
	# 압력계: 크롬 테 + 흰 판 + 바늘 + 유리
	var g := Node3D.new()
	g.position = Vector3(0.14, 1.0, 0)
	g.rotation = Vector3(0, 0, -PI * 0.5)
	root.add_child(g)
	_mi(_cyl(0.07, 0.07, 0.04, 24), chrome, Vector3.ZERO, g)
	_mi(_cyl(0.058, 0.058, 0.005, 24), _mat(Color(0.95, 0.95, 0.92), 0.5), Vector3(0, 0.021, 0), g)
	var nd := BoxMesh.new()
	nd.size = Vector3(0.006, 0.004, 0.05)
	_mi(nd, _mat(Color(0.8, 0.05, 0.05), 0.5), Vector3(0.01, 0.025, 0.012), g, Basis(Vector3.UP, 0.7))
	_mi(_cyl(0.06, 0.06, 0.004, 24), _glass(Color.WHITE), Vector3(0, 0.026, 0), g)
	# 긁힌 자국 (칠 벗겨져 쇠가 보임)
	var bare := _mat(Color(0.55, 0.55, 0.56), 0.4, 0.9)
	for k in 4:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.004, 0.04 + k * 0.02, 0.012)
		_mi(bm, bare, Vector3(cos(k * 1.3) * 0.201, 0.3 + k * 0.08, sin(k * 1.3) * 0.201), root, Basis(Vector3.UP, -k * 1.3))
	return root


# ── 그물 (상점 · 가방): 둘둘 뭉친 밧줄 그물 + 코르크 찌 + 납추 ─────
static func _net_bundle() -> Node3D:
	var root := Node3D.new()
	var rope := _grain(Color(0.7, 0.6, 0.42), 0.95, Vector2(10, 1), 0.3, 0.7, 0.0, 71)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# 뭉친 그물: 여러 방향으로 기운 고리들
	for k in 16:
		var r := rng.randf_range(0.18, 0.32)
		var b := Basis.from_euler(Vector3(rng.randf_range(0, PI), rng.randf_range(0, PI), rng.randf_range(0, PI)))
		_mi(_torus(r - 0.012, r + 0.012, 28), rope, Vector3(rng.randf_range(-0.05, 0.05), 0.32 + rng.randf_range(-0.04, 0.04), rng.randf_range(-0.05, 0.05)), root, b.scaled(Vector3(1.15, 0.85, 1.0)))
	# 매듭 (그물코 교차점)
	for k in 40:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 1), rng.randf_range(-1, 1)).normalized()
		_mi(_sph(0.018, 0.03, 8), rope, Vector3(0, 0.32, 0) + d * rng.randf_range(0.2, 0.3), root)
	# 코르크 찌 + 납추
	var cork := _grain(Color(0.78, 0.5, 0.25), 0.9, Vector2(3, 3), 0.35, 0.9, 0.0, 72)
	var paint := _mat(Color(0.8, 0.12, 0.08), 0.6)
	for k in 3:
		var a := TAU * k / 3 + 0.4
		var p := Vector3(cos(a) * 0.3, 0.12 + k * 0.08, sin(a) * 0.3)
		_mi(_sph(0.07, 0.11), cork, p, root)
		_mi(_cyl(0.071, 0.071, 0.03, 16), paint, p, root)
	_mi(_sph(0.05, 0.08, 12), _mat(Color(0.35, 0.36, 0.38), 0.4, 0.8), Vector3(0.05, 0.04, 0.28), root)
	return root


## 던지는 그물 (펼쳐진 반구 모양): 날실 · 씨실 + 아래 둘레에 찌
static func spread_net(radius: float = 0.85, height: float = 1.5) -> Node3D:
	var root := Node3D.new()
	var rope := _grain(Color(0.72, 0.62, 0.44), 0.95, Vector2(10, 1), 0.3, 0.7, 0.0, 81)
	var meridians := 14
	var segs := 7
	var pt := func(m: int, s: int) -> Vector3:
		var a := TAU * m / meridians
		var f := float(s) / segs
		var r := radius * sin(f * PI * 0.5)
		return Vector3(cos(a) * r, height * cos(f * PI * 0.5), sin(a) * r)
	for m in meridians:
		for s in segs:
			var p0: Vector3 = pt.call(m, s)
			var p1: Vector3 = pt.call(m, s + 1)
			var v := p1 - p0
			var L := v.length()
			if L < 0.001:
				continue
			_mi(_cyl(0.012, 0.012, L, 5), rope, p0 + v * 0.5, root, Basis(Quaternion(Vector3.UP, v / L)))
	for s in range(1, segs + 1):
		var f := float(s) / segs
		var r := radius * sin(f * PI * 0.5)
		_mi(_torus(r - 0.012, r + 0.012, 40), rope, Vector3(0, height * cos(f * PI * 0.5), 0), root)
	var cork := _grain(Color(0.78, 0.5, 0.25), 0.9, Vector2(3, 3), 0.35, 0.9, 0.0, 82)
	var paint := _mat(Color(0.8, 0.12, 0.08), 0.6)
	for m in range(0, meridians, 2):
		var p: Vector3 = pt.call(m, segs)
		_mi(_sph(0.06, 0.09, 10), cork, p, root)
		_mi(_cyl(0.061, 0.061, 0.025, 12), paint, p, root)
	return root
