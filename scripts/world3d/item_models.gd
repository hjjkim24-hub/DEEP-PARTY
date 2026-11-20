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
	# 판자 다섯 장: 이음매 홈이 방패 끝에서 끝까지 (원 모양에 맞춰 길이가 다름)
	var dark := _mat(Color(0.12, 0.08, 0.05), 0.9)
	for x in [-0.288, -0.096, 0.096, 0.288]:
		var h := 2.0 * sqrt(maxf(0.465 * 0.465 - x * x, 0.0))
		var bm := BoxMesh.new()
		bm.size = Vector3(0.014, 0.064, h)
		_mi(bm, dark, Vector3(x, 0.0, 0), face)
	var iron := _grain(Color(0.33, 0.3, 0.28), 0.55, Vector2(4, 4), 0.4, 0.8, 0.75, 21)
	_mi(_torus(0.45, 0.52, 48), iron, Vector3.ZERO, face, Basis.from_scale(Vector3(1, 0.5, 1)))
	_mi(_sph(0.13, 0.12), iron, Vector3(0, 0.03, 0), face)
	for a in 8:   # 테두리 징
		var t := TAU * a / 8
		_mi(_sph(0.022), iron, Vector3(cos(t) * 0.42, 0.04, sin(t) * 0.42), face)
	# 따개비: 실제처럼 '군락'으로 붙음 — 물에 늘 잠기는 아래쪽 테두리와 판자 이음매를 따라
	# 가운데에 오래된 큰 것, 바깥으로 갈수록 작은 것이 빽빽하게 서로 기대어 자라고 바깥쪽으로 기움.
	# 군락 밑에는 갈색 물때 얼룩, 떨어져 나간 자리엔 하얀 밑판 자국
	var bmesh := _barnacle_mesh()
	var shells := [_grain(Color(0.6, 0.57, 0.5), 0.9, Vector2(2, 2), 0.35, 1.0, 0.0, 31),
		_grain(Color(0.5, 0.48, 0.43), 0.9, Vector2(2, 2), 0.4, 1.0, 0.0, 32),
		_grain(Color(0.68, 0.65, 0.58), 0.85, Vector2(2, 2), 0.3, 1.0, 0.0, 33)]
	var crater := _mat(Color(0.08, 0.07, 0.06), 0.9)
	var stain := _mat(Color(0.26, 0.21, 0.13, 0.22), 0.95)
	stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := []
	# 군락 중심 (얼굴 기준 좌표 x, z: z+ 가 화면 아래쪽). 아래 테두리에 크게, 이음매 따라 작게
	var colonies := [[Vector2(-0.1, 0.33), 0.17, 0.064], [Vector2(0.2, 0.3), 0.14, 0.058], [Vector2(0.34, 0.08), 0.1, 0.05],
		[Vector2(-0.33, 0.14), 0.11, 0.05], [Vector2(-0.096, -0.12), 0.07, 0.038], [Vector2(0.096, 0.16), 0.06, 0.034]]
	for col in colonies:
		var c: Vector2 = col[0]
		var R: float = col[1]
		var big: float = col[2]
		# 군락 밑 물때
		for e in 4:
			var o := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * R * 0.4
			_mi(_cyl(R * rng.randf_range(0.45, 0.75), R * rng.randf_range(0.45, 0.75), 0.002, 18), stain,
				Vector3(c.x + o.x, 0.031 + e * 0.0005, c.y + o.y), face, Basis.from_scale(Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))))
		var tries := 0
		var n_here := 0
		while tries < 900 and n_here < int(R * 260):
			tries += 1
			var d := sqrt(rng.randf()) * R
			var a := rng.randf() * TAU
			var pos2 := c + Vector2(cos(a), sin(a)) * d
			if pos2.length() > 0.445 or pos2.length() < 0.15:
				continue
			# 가운데일수록 크고, 가장자리로 갈수록 작음 (+ 들쭉날쭉)
			var sz := big * pow(1.0 - d / R, 0.6) * rng.randf_range(0.7, 1.05) + 0.008
			var ok := true
			for q in placed:
				if pos2.distance_to(q[0]) < (sz + float(q[1])) * 0.78:
					ok = false
					break
			if not ok:
				continue
			placed.append([pos2, sz])
			n_here += 1
			var lean := (pos2 - c).normalized() * clampf(d / R, 0.0, 1.0) * 0.35 if d > 0.001 else Vector2.ZERO
			var bs := Basis(Vector3(lean.y, 0, -lean.x).normalized() if lean.length() > 0.01 else Vector3.RIGHT, lean.length()) \
				* Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sz, sz * rng.randf_range(0.8, 1.25), sz * rng.randf_range(0.85, 1.0)))
			_mi(bmesh, shells[rng.randi() % shells.size()], Vector3(pos2.x, 0.03, pos2.y), face, bs)
			_mi(_cyl(sz * 0.32, sz * 0.32, 0.004, 7), crater, Vector3(pos2.x, 0.03, pos2.y) + bs * Vector3(0, 0.62, 0), face, bs.orthonormalized())
	# 떨어져 나간 자리: 하얀 밑판 자국 몇 개
	var scar := _mat(Color(0.88, 0.86, 0.8), 0.8)
	for k in 5:
		var a := rng.randf_range(0.2, 2.9)
		var r := rng.randf_range(0.3, 0.42)
		_mi(_cyl(0.02, 0.02, 0.002, 10), scar, Vector3(cos(a) * r, 0.031, sin(a) * r), face)
	return root


## 따개비 하나 (반지름 1 · 높이 1 기준): 넓은 밑동 · 가파른 옆면(7 조각 판) · 꼭대기 분화구
static func _barnacle_mesh() -> ArrayMesh:
	return _lathe([Vector2(0.0, 0.6), Vector2(0.22, 0.66), Vector2(0.3, 0.9), Vector2(0.36, 0.98), Vector2(0.42, 0.95),
		Vector2(0.55, 0.82), Vector2(0.8, 0.5), Vector2(0.97, 0.18), Vector2(1.0, 0.0)], 7)


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


# ── 덫 탐지 소라: 진짜 소라껍데기 (뾰족한 나선탑 · 어깨 돌기 · 넓게 벌어진 분홍 입구)
##    꼭대기에 묶은 꼰 끈이 늘어져 놋쇠 고리에 이어짐
static func _conch() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.rotation = Vector3(0.0, -0.35, 1.25)     # 해변에 누운 소라: 나선탑은 왼쪽 위, 분홍 입구는 비스듬히
	body.position = Vector3(0.1, 0.12, 0)
	root.add_child(body)
	var turns := 5.0
	var U := turns * TAU
	var b := log(1.8) / TAU          # 한 바퀴에 1.8 배씩 커짐 → 나선탑이 뾰족하게 높이 솟음
	var su := 140
	var sv := 28
	var pos_at := func(u: float, v: float, inner: bool) -> Vector3:
		var g := exp(b * (u - U))
		var flare := 1.0 + smoothstep(U - TAU * 0.4, U, u) * 0.12   # 마지막 반 바퀴: 입구가 살짝 벌어짐
		var R := 0.12 * g
		var rho := 0.15 * g * flare * (0.97 if inner else 1.0)
		var cy := 0.9 - 0.85 * g
		var radial := Vector3(cos(u), 0, sin(u))
		# 단면: 바깥쪽 위 어깨가 각진 물방울 모양 + 어깨 돌기
		var bump := 0.0
		if not inner:
			# 어깨의 뿔 돌기: 한 바퀴에 여러 개, 아래 큰 몸통일수록 뚜렷
			bump = maxf(0.0, cos(v - 1.05)) ** 8.0 * (0.12 + 0.6 * maxf(0.0, sin(u * 3.0)) ** 6.0)
		var rr := rho * (1.0 + bump)
		return Vector3(0, cy, 0) + radial * (R + rr * cos(v)) + Vector3(0, rr * 1.35 * sin(v), 0)
	var col_at := func(u: float, v: float) -> Color:
		var cream := Color(0.86, 0.78, 0.63)
		var brown := Color(0.6, 0.36, 0.2)
		# 가는 나선 줄무늬 + 성장선 (얼룩 대신)
		var cords := smoothstep(0.75, 0.95, sin(v * 16.0))
		var growth := smoothstep(0.85, 0.98, sin(u * 11.0 + sin(v * 3.0) * 0.6))
		var c := cream.lerp(brown, cords * 0.35 + growth * 0.4)
		c = c.lerp(Color(0.86, 0.72, 0.52), smoothstep(0.3, 1.0, sin(v * 2.0 + u * 0.3)) * 0.35)
		c = c.lerp(Color(0.9, 0.6, 0.52), smoothstep(U - TAU * 0.25, U, u) * smoothstep(-0.2, -1.2, cos(v)))
		return c
	for layer in 2:
		var inner := layer == 1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var u0 := 0.0 if not inner else U - TAU * 0.55
		for i in su:
			var ua := lerpf(u0, U, float(i) / su)
			var ub := lerpf(u0, U, float(i + 1) / su)
			for k in sv:
				var va := TAU * k / sv
				var vb := TAU * (k + 1) / sv
				var quad := [[ua, va], [ub, va], [ub, vb], [ua, va], [ub, vb], [ua, vb]]
				if inner:
					quad = [[ua, va], [ub, vb], [ub, va], [ua, va], [ua, vb], [ub, vb]]
				for q in quad:
					st.set_color(Color(0.84, 0.52, 0.46) if inner else col_at.call(q[0], q[1]))
					st.set_uv(Vector2(q[1] / TAU, q[0] / TAU))
					st.add_vertex(pos_at.call(q[0], q[1], inner))
		st.generate_normals()
		var m := _mat(Color.WHITE, 0.3 if inner else 0.45)
		m.vertex_color_use_as_albedo = true
		if not inner:
			var n := FastNoiseLite.new()
			n.seed = 9
			n.frequency = 0.06
			var nt := NoiseTexture2D.new()
			nt.width = 256
			nt.height = 256
			nt.seamless = true
			nt.as_normal_map = true
			nt.bump_strength = 2.0
			nt.noise = n
			m.normal_enabled = true
			m.normal_texture = nt
			m.normal_scale = 0.18
			m.uv1_scale = Vector3(3, 2, 1)
		else:
			m.clearcoat_enabled = true
			m.clearcoat = 0.3
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		body.add_child(mi)
	# 꼰 끈: 나선탑 꼭대기에 감겨서 늘어지다가 놋쇠 고리로
	var cord := _grain(Color(0.45, 0.3, 0.18), 0.95, Vector2(12, 1), 0.35, 0.8, 0.0, 91)
	_mi(_torus(0.03, 0.05, 20), cord, Vector3(0, 0.89, 0), body)
	# 끈과 고리는 바깥(root) 기준: 꼭대기에서 화면 오른쪽 앞으로 늘어져 바닥의 고리로
	var top := body.transform * Vector3(0, 0.93, 0)
	var ring_c := Vector3(-0.3, 0.0, 0.3)
	var p0 := top + Vector3(0.04, 0.0, 0.0)
	var c1 := top + Vector3(-0.15, 0.1, 0.15)
	var c2 := ring_c + Vector3(0.0, 0.3, 0.0)
	var p3 := ring_c + Vector3(-0.02, 0.17, 0.0)
	var prev := p0
	for k in range(1, 25):
		var t := float(k) / 24
		var q := p0 * pow(1 - t, 3) + c1 * 3 * t * pow(1 - t, 2) + c2 * 3 * t * t * (1 - t) + p3 * pow(t, 3)
		var v := q - prev
		_mi(_cyl(0.014, 0.014, v.length() * 1.2, 6), cord, prev + v * 0.5, root, Basis(Quaternion(Vector3.UP, v.normalized())))
		prev = q
	var brass := _grain(Color(0.78, 0.6, 0.3), 0.3, Vector2(3, 3), 0.25, 0.4, 1.0, 92)
	_mi(_torus(0.12, 0.155, 40), brass, ring_c + Vector3(0, 0.02, 0), root, Basis(Vector3(1, 0, 0), PI * 0.5 - 0.15) * Basis(Vector3.UP, 0.0))
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
	# 고무 띠: 통 표면에 딱 붙은 얇은 띠 (같은 회전체로 반지름만 아주 조금 크게)
	for y in [0.18, 0.56]:
		_mi(_lathe([Vector2(0.2005, y - 0.032), Vector2(0.207, y - 0.026), Vector2(0.207, y + 0.026), Vector2(0.2005, y + 0.032)], 36), rubber, Vector3.ZERO, root)
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


# ── 그물 (상점 · 가방): 장대에 널어 말리는 진짜 고기잡이 그물
##    마름모 그물코 · 주름지며 늘어진 그물 · 위쪽 뜸줄의 코르크 찌 · 아래 발줄의 납추가 바닥에 쌓임
static func _net_bundle() -> Node3D:
	var root := Node3D.new()
	var rope := _grain(Color(0.68, 0.6, 0.44), 0.95, Vector2(10, 1), 0.3, 0.7, 0.0, 71)
	var thick := _grain(Color(0.5, 0.4, 0.26), 0.95, Vector2(14, 1), 0.35, 0.8, 0.0, 73)
	var W := 1.0
	var H := 0.95
	# 그물 면: s (가로 0~1) · t (위 0 → 아래 1). 장대에 걸려 아래로 늘어지며 주름, 아래 끝은 바닥에 쌓여 앞으로 접힘
	var surf := func(s_: float, t: float) -> Vector3:
		var x := (s_ - 0.5) * W * (1.0 - 0.12 * t)
		var y := 1.0 - t * H
		var z := 0.07 * sin(s_ * 5.5 * PI) * (0.3 + t) + 0.05 * sin(s_ * 13.0 + t * 4.0) * t
		if y < 0.12:
			z += (0.12 - y) * 1.6
			y = 0.12 - (0.12 - y) * 0.15
		return Vector3(x, y, z)
	var lines := 13
	var samples := 18
	for dir in [1.0, -1.0]:
		for k in range(-lines, lines + 1):
			var c := float(k) / lines
			var prev = null
			for q in samples + 1:
				var t := float(q) / samples
				var s_: float = c + dir * t * 0.9 * 0.5 + 0.5 - 0.25 * dir
				if s_ < 0.0 or s_ > 1.0:
					prev = null
					continue
				var p: Vector3 = surf.call(s_, t)
				if prev != null:
					var v: Vector3 = p - prev
					if v.length() > 0.001:
						_mi(_cyl(0.006, 0.006, v.length() * 1.05, 4), rope, prev + v * 0.5, root, Basis(Quaternion(Vector3.UP, v.normalized())))
				prev = p
	# 장대 (뜸줄이 감김) + 찌
	var wood := _grain(Color(0.42, 0.3, 0.18), 0.8, Vector2(1, 6), 0.4, 0.8, 0.0, 74)
	_mi(_cyl(0.03, 0.03, W + 0.35, 12), wood, Vector3(0, 1.02, 0), root, Basis(Vector3(0, 0, 1), PI * 0.5))
	_mi(_cyl(0.014, 0.014, W, 8), thick, Vector3(0, 0.995, 0.0), root, Basis(Vector3(0, 0, 1), PI * 0.5))
	var cork := _grain(Color(0.8, 0.5, 0.24), 0.9, Vector2(3, 3), 0.35, 0.9, 0.0, 72)
	var paint := _mat(Color(0.82, 0.15, 0.08), 0.6)
	for k in 5:
		var x := -0.4 + k * 0.2
		_mi(_cyl(0.045, 0.045, 0.11, 14), cork, Vector3(x, 0.97, 0.03), root, Basis(Vector3(0, 0, 1), PI * 0.5))
		if k % 2 == 0:
			_mi(_cyl(0.047, 0.047, 0.03, 14), paint, Vector3(x, 0.97, 0.03), root, Basis(Vector3(0, 0, 1), PI * 0.5))
	# 발줄 납추 (바닥에 쌓인 그물 끝)
	var lead := _mat(Color(0.36, 0.37, 0.4), 0.45, 0.7)
	for k in 6:
		var p: Vector3 = surf.call(0.08 + k * 0.17, 1.0)
		_mi(_sph(0.03, 0.05, 10), lead, p + Vector3(0, 0.01, 0.02), root, Basis(Vector3(0, 0, 1), PI * 0.5))
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
	# 투망: 둘레에 납추가 촘촘히 달려 펼쳐지며 떨어짐 + 꼭대기에 손잡이 줄
	var lead := _mat(Color(0.36, 0.37, 0.4), 0.45, 0.7)
	for m in meridians * 2:
		var a := TAU * m / (meridians * 2)
		_mi(_sph(0.04, 0.07, 8), lead, Vector3(cos(a) * radius, 0.0, sin(a) * radius), root)
	_mi(_cyl(0.015, 0.015, 0.6, 6), rope, Vector3(0, height + 0.3, 0), root)
	return root
