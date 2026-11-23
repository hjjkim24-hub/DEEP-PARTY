class_name CardModels
extends ItemModels
## 찬스 카드 그림용 3D 소품 (tools/render_card_art.gd 가 바닷속 작은 무대에 세워 사진처럼 찍음)
## 원점 = 바닥 가운데, 크기 대략 1~2 m


## 동전 무더기: 몇 줄 쌓인 탑 + 바닥에 흩어지고 기대어 선 동전들
static func coin_pile(n: int, bad: bool, seed_: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var r := 0.3
	var th := r * 0.15
	var placed := 0
	# 탑
	var towers := [[Vector2(-0.15, -0.1), 5], [Vector2(0.42, -0.25), 3]] if n >= 8 else [[Vector2(-0.05, -0.05), 3]]
	for tw in towers:
		var base: Vector2 = tw[0]
		for k in int(tw[1]):
			var c := coin(r, bad)
			c.position = Vector3(base.x + rng.randf_range(-0.02, 0.02), th + k * th * 2.05, base.y + rng.randf_range(-0.02, 0.02))
			c.rotation = Vector3(rng.randf_range(-0.03, 0.03), rng.randf() * TAU, rng.randf_range(-0.03, 0.03))
			root.add_child(c)
			placed += 1
	# 흩어진 동전 (누운 것 · 비스듬히 기댄 것)
	var spots := [Vector2(0.45, 0.35), Vector2(-0.6, 0.3), Vector2(0.05, 0.55), Vector2(-0.55, -0.45), Vector2(0.85, 0.1),
		Vector2(-0.95, 0.0), Vector2(0.3, 0.8), Vector2(-0.25, 0.85)]
	var i := 0
	while placed < n and i < spots.size():
		var sp: Vector2 = spots[i]
		var c := coin(r, bad)
		var tilt := 0.0 if i % 3 != 1 else rng.randf_range(0.35, 0.6)
		c.position = Vector3(sp.x, th + sin(tilt) * r * 0.9, sp.y)
		c.rotation = Vector3(tilt, rng.randf() * TAU, 0)
		c.rotation_order = EULER_ORDER_YXZ
		root.add_child(c)
		placed += 1
		i += 1
	return root


## 정육면체 주사위 (상아 · 둥근 모서리 · 1~6 눈, 1은 붉은 큰 눈)
static func die6(size: float = 0.5) -> Node3D:
	var cube := Node3D.new()
	var ivory := _grain(Color(0.84, 0.8, 0.7), 0.32, Vector2(2, 2), 0.14, 0.2, 0.0, 43)
	var h := size * 0.5
	var rr := size * 0.1
	var bm := BoxMesh.new()
	bm.size = Vector3(size - rr * 2, size, size - rr * 2)
	_mi(bm, ivory, Vector3.ZERO, cube)
	bm = BoxMesh.new()
	bm.size = Vector3(size, size - rr * 2, size - rr * 2)
	_mi(bm, ivory, Vector3.ZERO, cube)
	bm = BoxMesh.new()
	bm.size = Vector3(size - rr * 2, size - rr * 2, size)
	_mi(bm, ivory, Vector3.ZERO, cube)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_mi(_sph(rr, -1.0, 12), ivory, Vector3(sx, sy, sz) * (h - rr), cube)
			_mi(_cyl(rr, rr, size - rr * 2, 14), ivory, Vector3(sx * (h - rr), 0, sy * (h - rr)), cube)
			_mi(_cyl(rr, rr, size - rr * 2, 14), ivory, Vector3(sx * (h - rr), sy * (h - rr), 0), cube, Basis(Vector3(1, 0, 0), PI / 2))
			_mi(_cyl(rr, rr, size - rr * 2, 14), ivory, Vector3(0, sx * (h - rr), sy * (h - rr)), cube, Basis(Vector3(0, 0, 1), PI / 2))
	var pip := _mat(Color(0.06, 0.05, 0.05), 0.6)
	var red := _mat(Color(0.62, 0.05, 0.05), 0.45)
	var g := size * 0.25
	var layout := {
		1: [Vector2.ZERO], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]}
	var faces := [[Vector3.UP, 1], [Vector3.DOWN, 6], [Vector3.RIGHT, 3], [Vector3.LEFT, 4], [Vector3.BACK, 2], [Vector3.FORWARD, 5]]
	for f in faces:
		var n: Vector3 = f[0]
		var u := n.cross(Vector3.BACK if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u)
		var val := int(f[1])
		for s in layout[val]:
			var big := val == 1
			var pr := size * (0.11 if big else 0.075)
			var p: Vector3 = n * (h - pr * 0.25) + (u * s.x + v * s.y) * g
			_mi(_sph(pr, pr * 0.7, 14), red if big else pip, p, cube, Basis(Quaternion(Vector3.UP, n)))
	return cube


## 가죽 돈주머니: 볼록한 몸통 · 졸라맨 목 · 주름진 입구 · 늘어진 끈 + 쏟아진 동전
static func pouch() -> Node3D:
	var root := Node3D.new()
	var leather := _grain(Color(0.42, 0.25, 0.13), 0.75, Vector2(3, 2), 0.35, 0.8, 0.0, 61)
	var prof := [Vector2(0.0, 0.0), Vector2(0.25, 0.02), Vector2(0.42, 0.12), Vector2(0.5, 0.3), Vector2(0.48, 0.5),
		Vector2(0.36, 0.68), Vector2(0.16, 0.8), Vector2(0.13, 0.84), Vector2(0.16, 0.9), Vector2(0.2, 0.96), Vector2(0.23, 1.0), Vector2(0.21, 1.01)]
	var body := _mi(_lathe(prof, 40), leather, Vector3.ZERO, root)
	body.scale = Vector3(1.0, 0.95, 0.9)
	body.rotation = Vector3(0, 0, -0.22)   # 옆으로 기울어 입구가 앞을 봄
	body.position = Vector3(-0.15, 0, 0)
	var lining := _mat(Color(0.12, 0.06, 0.03), 0.9)
	lining.cull_mode = BaseMaterial3D.CULL_FRONT
	var inner := _mi(_lathe(prof, 40), lining, Vector3.ZERO, body)
	inner.scale = Vector3.ONE * 0.97
	# 졸라맨 끈 + 늘어진 끝 + 매듭
	var cord := _grain(Color(0.66, 0.55, 0.38), 0.9, Vector2(8, 1), 0.25, 0.5, 0.0, 62)
	_mi(_torus(0.13, 0.17, 24), cord, Vector3(0, 0.82, 0), body)
	# 매듭 + 짧게 늘어진 끈 두 가닥 (몸통에 붙어 내려옴)
	_mi(_sph(0.045, -1.0, 10), cord, Vector3(0.0, 0.82, 0.16), body)
	for sgn in [-1.0, 1.0]:
		var prev := Vector3(0.0, 0.82, 0.17)
		for k in 5:
			var t := (k + 1) / 5.0
			var q := Vector3(sgn * 0.05 * t, 0.82 - t * 0.2, 0.17 + sin(t * PI) * 0.05 + t * 0.12)
			var dv := q - prev
			_mi(_cyl(0.014, 0.014, dv.length() + 0.01, 6), cord, (q + prev) * 0.5, body, Basis(Quaternion(Vector3.UP, dv.normalized())))
			prev = q
	# 바느질 자국
	var stitch := _mat(Color(0.8, 0.72, 0.55), 0.8)
	for k in 16:
		var y := 0.1 + k * 0.035
		_mi(_box3(Vector3(0.012, 0.022, 0.006)), stitch, Vector3(0, y, -0.48 + absf(y - 0.35) * 0.3), body)
	# 쏟아진 동전 (입구에서 앞쪽 바닥으로)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var spill := [Vector3(0.45, 0.06, 0.25), Vector3(0.68, 0.04, 0.45), Vector3(0.3, 0.04, 0.6), Vector3(0.85, 0.05, 0.1),
		Vector3(0.55, 0.12, 0.05), Vector3(0.95, 0.04, 0.55)]
	for k in spill.size():
		var c := coin(0.17)
		c.position = spill[k]
		c.rotation = Vector3(rng.randf_range(-0.4, 0.4) if k % 2 else 0.0, rng.randf() * TAU, rng.randf_range(-0.3, 0.3) if k == 4 else 0.0)
		root.add_child(c)
	return root


static func _box3(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


## 순간이동 관문: 이끼 낀 돌 고리가 서 있고 안쪽은 보랏빛 소용돌이
static func portal() -> Node3D:
	var root := Node3D.new()
	var stone := _grain(Color(0.42, 0.44, 0.42), 0.85, Vector2(4, 1), 0.35, 1.0, 0.0, 71)
	var moss := _grain(Color(0.22, 0.34, 0.16), 0.95, Vector2(5, 2), 0.4, 0.6, 0.0, 72)
	var ring := Node3D.new()
	ring.position = Vector3(0, 1.0, 0)
	root.add_child(ring)
	# 돌 블록을 원 모양으로 쌓은 아치
	var blocks := 16
	for k in blocks:
		var a := TAU * k / blocks
		var b := _mi(_box3(Vector3(0.36, 0.26, 0.3)), stone, Vector3(cos(a) * 0.86, sin(a) * 0.86, 0), ring, Basis(Vector3.BACK, a + PI / 2))
		b.scale = Vector3(1.0, 1.0 + (k % 3) * 0.06, 1.0 + (k % 2) * 0.08)
		if k % 4 == 1:
			_mi(_sph(0.12, 0.08, 10), moss, Vector3(cos(a) * 0.86, sin(a) * 0.86 + 0.12, 0.05), ring)
	# 소용돌이: 반투명 원판 여러 장이 겹쳐 빛남
	for k in 4:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var gr := Gradient.new()
		gr.set_color(0, Color(0.95, 0.7, 1.0, 0.9))
		gr.set_color(1, Color(0.35, 0.1, 0.8, 0.0))
		gr.add_point(0.55, Color(0.7, 0.3, 1.0, 0.6))
		g.gradient = gr
		m.albedo_texture = g
		m.albedo_color = Color(0.8, 0.7, 1.0, 0.3 - k * 0.06)
		var q := QuadMesh.new()
		q.size = Vector2(1.5 - k * 0.15, 1.5 - k * 0.15)
		_mi(q, m, Vector3(0, 0, -0.04 + k * 0.03), ring, Basis(Vector3.BACK, k * 0.7))
	# 소용돌이 팔 (휘어진 빛줄기)
	var arm := StandardMaterial3D.new()
	arm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	arm.albedo_color = Color(0.85, 0.6, 1.0, 0.5)
	for s in 3:
		for k in 14:
			var t := k / 13.0
			var a := s * TAU / 3 + t * 4.0
			var rr := 0.08 + t * 0.6
			_mi(_sph(0.035 * (1.0 - t * 0.5), -1.0, 8), arm, Vector3(cos(a) * rr, sin(a) * rr, 0.02), ring)
	var l := OmniLight3D.new()
	l.light_color = Color(0.7, 0.35, 1.0)
	l.light_energy = 1.4
	l.omni_range = 2.6
	l.position = Vector3(0, 1.0, 0.4)
	root.add_child(l)
	# 받침 돌
	_mi(_box3(Vector3(0.7, 0.2, 0.45)), stone, Vector3(0, 0.1, 0), root)
	return root


## 판 위 돌 칸 한 장 (모서리 깎이고 이끼 낌) + 그 위에 동전 (금화 = 행운, 녹슨 동전 = 함정)
static func slab_with_coin(bad: bool) -> Node3D:
	var root := Node3D.new()
	var stone := _grain(Color(0.4, 0.39, 0.35), 0.9, Vector2(3, 3), 0.35, 1.0, 0.0, 81)
	_mi(_box3(Vector3(1.6, 0.2, 1.6)), stone, Vector3(0, 0.1, 0), root)
	_mi(_box3(Vector3(1.45, 0.08, 1.45)), stone, Vector3(0, 0.24, 0), root)
	var inlay := _mat(Color(0.75, 0.6, 0.25) if not bad else Color(0.45, 0.1, 0.08), 0.4, 0.6 if not bad else 0.0)
	_mi(_torus(0.5, 0.56, 40), inlay, Vector3(0, 0.28, 0), root, Basis.from_scale(Vector3(1, 0.3, 1)))
	var c := coin(0.42, bad)
	c.position = Vector3(0, 0.72, 0)
	c.rotation = Vector3(PI / 2 - 0.12, 0.3, 0)
	root.add_child(c)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.35) if not bad else Color(1.0, 0.2, 0.12)
	l.light_energy = 1.3
	l.omni_range = 2.0
	l.position = Vector3(0, 0.9, 0.5)
	root.add_child(l)
	return root


## 작살: 나무 자루(손때 · 가죽 손잡이 감김) + 미늘 달린 쇠촉 + 밧줄 묶음 + 바닥에 감긴 밧줄
static func harpoon() -> Node3D:
	var root := Node3D.new()
	var spear := Node3D.new()
	spear.position = Vector3(0.5, 0.95, 0)
	spear.rotation = Vector3(0.0, 0.35, -PI / 2 + 0.22)   # 막 던져져 물살을 가르며 날아가는 중
	root.add_child(spear)
	var wood := _grain(Color(0.45, 0.3, 0.17), 0.7, Vector2(1, 8), 0.35, 0.6, 0.0, 91)
	var iron := _grain(Color(0.5, 0.5, 0.5), 0.45, Vector2(2, 2), 0.3, 0.5, 0.9, 92)
	var grip := _grain(Color(0.25, 0.14, 0.08), 0.8, Vector2(4, 4), 0.3, 0.6, 0.0, 93)
	var L := 1.6
	spear.scale = Vector3.ONE * 1.35
	_mi(_cyl(0.04, 0.045, L, 12), wood, Vector3(0, -L * 0.5, 0), spear)
	for k in 9:
		_mi(_torus(0.034, 0.05, 14), grip, Vector3(0, -L * 0.72 - k * 0.035, 0), spear, Basis.from_scale(Vector3(1, 0.8, 1)))
	# 쇠촉: 소켓 + 긴 목 + 납작한 잎 모양 날 + 젖혀진 미늘 두 개
	_mi(_cyl(0.045, 0.04, 0.16, 12), iron, Vector3(0, 0.08, 0), spear)
	_mi(_cyl(0.022, 0.03, 0.3, 10), iron, Vector3(0, 0.3, 0), spear)
	var blade := _lathe([Vector2(0.0, 0.0), Vector2(0.09, 0.08), Vector2(0.07, 0.22), Vector2(0.0, 0.42)], 4)
	var b := _mi(blade, iron, Vector3(0, 0.44, 0), spear)
	b.scale = Vector3(1.0, 1.0, 0.25)
	for sgn in [-1.0, 1.0]:
		_mi(_cyl(0.0, 0.025, 0.2, 6), iron, Vector3(sgn * 0.08, 0.5, 0), spear, Basis(Vector3.BACK, sgn * 2.6))
	# 자루에 묶인 밧줄
	var rope := _grain(Color(0.7, 0.6, 0.42), 0.95, Vector2(10, 1), 0.3, 0.8, 0.0, 94)
	for k in 6:
		_mi(_torus(0.035, 0.06, 12), rope, Vector3(0, -L + 0.04 + k * 0.03, 0), spear, Basis(Vector3.BACK, 0.25 * (k % 2 * 2 - 1)))
	# 바닥에 둥글게 감긴 밧줄
	for k in 5:
		_mi(_torus(0.2 + k * 0.05, 0.25 + k * 0.05, 36), rope, Vector3(-1.5, 0.03 + (4 - k) * 0.02, 0.6), root, Basis.from_scale(Vector3(1, 0.5, 1)))
	# 밧줄이 코일에서 풀려 자루 끝까지 팽팽하게 이어짐
	var a := Vector3(-1.25, 0.06, 0.6)
	var bb := spear.transform * Vector3(0, -L, 0)
	for k in 10:
		var t0 := k / 10.0
		var t1 := (k + 1) / 10.0
		var p0 := a.lerp(bb, t0) + Vector3(0, -sin(t0 * PI) * 0.25, 0)
		var p1 := a.lerp(bb, t1) + Vector3(0, -sin(t1 * PI) * 0.25, 0)
		var dv := p1 - p0
		_mi(_cyl(0.022, 0.022, dv.length() + 0.01, 8), rope, (p0 + p1) * 0.5, root, Basis(Quaternion(Vector3.UP, dv.normalized())))
	return root


## 곰덫: 녹슨 받침판 + 활짝 벌린 톱니 턱 둘 + 판스프링 + 쇠사슬 + 말뚝
static func bear_trap() -> Node3D:
	var root := Node3D.new()
	var iron := _grain(Color(0.28, 0.27, 0.26), 0.55, Vector2(3, 3), 0.35, 0.8, 0.85, 101)
	var rust := _grain(Color(0.45, 0.24, 0.12), 0.9, Vector2(4, 4), 0.45, 1.0, 0.2, 102)
	var R := 0.55
	_mi(_box3(Vector3(1.7, 0.05, 0.16)), rust, Vector3(0, 0.03, 0), root)
	_mi(_cyl(0.2, 0.22, 0.05, 20), rust, Vector3(0, 0.05, 0), root)          # 밟는 판
	_mi(_cyl(0.16, 0.16, 0.02, 20), iron, Vector3(0, 0.085, 0), root)
	for sgn in [-1.0, 1.0]:
		# 판스프링 (휘어진 띠)
		for k in 8:
			var t := k / 7.0
			var x: float = sgn * (0.62 + t * 0.32)
			_mi(_box3(Vector3(0.06, 0.03, 0.14)), iron, Vector3(x, 0.05 + sin(t * PI) * 0.12, 0), root, Basis(Vector3.BACK, cos(t * PI) * 0.6 * -sgn))
		# 턱: 반원 띠 + 이빨, 거의 수직으로 벌어짐
		var jaw := Node3D.new()
		jaw.position = Vector3(0, 0.06, 0)
		jaw.rotation = Vector3(-sgn * 1.2, 0, 0)
		root.add_child(jaw)
		var teeth := 9
		for k in teeth + 1:
			var a := PI * k / teeth
			var p := Vector3(cos(a) * R, 0, sgn * sin(a) * R)
			var a2 := PI * (k + 1) / teeth
			if k < teeth:
				var p2 := Vector3(cos(a2) * R, 0, sgn * sin(a2) * R)
				var dv := p2 - p
				var seg := _mi(_box3(Vector3(dv.length() + 0.02, 0.05, 0.035)), iron, (p + p2) * 0.5, jaw, Basis(Vector3.UP, -atan2(dv.z, dv.x)))
				seg.name = "j"
				# 이빨: 바깥 테에서 안쪽 위로 솟은 삼각 톱니
				var mid := (p + p2) * 0.5
				_mi(_cyl(0.0, 0.035, 0.12, 4), iron, mid + Vector3(0, 0.07, 0) - mid.normalized() * 0.01, jaw)
	# 쇠사슬 + 말뚝
	var prev := Vector3(-0.95, 0.04, 0)
	for k in 7:
		var p := prev + Vector3(-0.09, 0, 0.05 * sin(k * 1.3))
		_mi(_torus(0.022, 0.04, 14), iron, p, root, Basis(Vector3.RIGHT, PI / 2 * (k % 2)) * Basis.from_scale(Vector3(1.4, 1, 1)))
		prev = p
	_mi(_cyl(0.035, 0.015, 0.4, 8), iron, prev + Vector3(-0.08, 0.1, 0), root, Basis(Vector3.BACK, 0.25))
	_mi(_torus(0.03, 0.05, 12), iron, prev + Vector3(-0.05, 0.3, 0), root, Basis(Vector3.RIGHT, PI / 2))
	return root


## 흡혈 해파리: 물결치는 가장자리의 반투명 갓 + 속에서 빛나는 붉은 심장 + 리본 같은 입팔 + 가는 촉수
static func jelly() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.position = Vector3(0, 1.45, 0)
	root.add_child(body)
	var bell := StandardMaterial3D.new()
	bell.albedo_color = Color(1.0, 0.55, 0.8, 0.42)
	bell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bell.roughness = 0.15
	bell.metallic_specular = 0.9
	bell.rim_enabled = true
	bell.rim = 0.8
	bell.rim_tint = 0.3
	bell.emission_enabled = true
	bell.emission = Color(0.9, 0.2, 0.55)
	bell.emission_energy_multiplier = 0.6
	bell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var prof := [Vector2(0.62, -0.08), Vector2(0.6, 0.02), Vector2(0.56, 0.15), Vector2(0.46, 0.3), Vector2(0.32, 0.4), Vector2(0.15, 0.45), Vector2(0.0, 0.46)]
	_mi(_lathe(prof, 48), bell, Vector3.ZERO, body)
	# 물결 가장자리 (작은 꽃잎들)
	for k in 16:
		var a := TAU * k / 16
		var f := _mi(_sph(0.1, 0.06, 10), bell, Vector3(cos(a) * 0.6, -0.1, sin(a) * 0.6), body)
		f.scale = Vector3(1.0, 1.0, 0.5)
		f.rotation.y = -a
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(0.9, 0.08, 0.2)
	core.emission_enabled = true
	core.emission = Color(1.0, 0.1, 0.25)
	core.emission_energy_multiplier = 2.5
	for k in 4:
		var a := TAU * k / 4
		var g := _mi(_torus(0.06, 0.11, 16), core, Vector3(cos(a) * 0.14, 0.22, sin(a) * 0.14), body)
		g.scale = Vector3(1, 0.6, 1)
	# 입팔: 넓적하게 꼬이며 내려가는 리본
	var arm := StandardMaterial3D.new()
	arm.albedo_color = Color(1.0, 0.45, 0.7, 0.6)
	arm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arm.emission_enabled = true
	arm.emission = Color(1.0, 0.25, 0.55)
	arm.emission_energy_multiplier = 0.8
	arm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in 4:
		var a0 := TAU * s / 4 + 0.4
		for k in 14:
			var t := k / 13.0
			var p := Vector3(cos(a0) * (0.08 + 0.08 * sin(t * 6.0 + s)), -0.1 - t * 1.0, sin(a0) * (0.08 + 0.08 * cos(t * 6.0 + s)))
			var q := _mi(_box3(Vector3(0.12 * (1.0 - t * 0.5), 0.09, 0.015)), arm, p, body, Basis(Vector3.UP, t * 5.0 + a0))
			q.name = "arm"
	# 가는 촉수: 갓 가장자리에서 길게, 물결치며
	var tent := StandardMaterial3D.new()
	tent.albedo_color = Color(1.0, 0.7, 0.88, 0.55)
	tent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tent.emission_enabled = true
	tent.emission = Color(1.0, 0.4, 0.75)
	tent.emission_energy_multiplier = 1.0
	for k in 12:
		var a := TAU * k / 12
		var prev := Vector3(cos(a) * 0.55, -0.1, sin(a) * 0.55)
		var L := 1.0 + 0.35 * ((k * 7) % 3)
		var n := 16
		for j in n:
			var t := (j + 1.0) / n
			var q := Vector3(cos(a) * (0.55 - t * 0.15) + sin(t * 7.0 + k) * 0.06, -0.1 - t * L, sin(a) * (0.55 - t * 0.15) + cos(t * 6.0 + k) * 0.06)
			var dv := q - prev
			_mi(_cyl(0.006, 0.009, dv.length() + 0.005, 5), tent, (q + prev) * 0.5, body, Basis(Quaternion(Vector3.UP, dv.normalized())))
			prev = q
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.6)
	l.light_energy = 2.0
	l.omni_range = 3.0
	l.position = Vector3(0, 0.1, 0.3)
	body.add_child(l)
	return root


## 크라켄 미끼: 낚싯줄에 매달린 커다란 쇠 갈고리에 꿰인 물고기 + 피처럼 번지는 붉은 빛
static func bait() -> Node3D:
	var root := Node3D.new()
	var iron := _grain(Color(0.35, 0.34, 0.33), 0.45, Vector2(2, 2), 0.3, 0.6, 0.9, 111)
	var hook := Node3D.new()
	hook.position = Vector3(0, 0.55, 0)
	root.add_child(hook)
	# 갈고리: 위 고리 + 곧은 자루 + J 곡선 + 미늘
	_mi(_torus(0.06, 0.1, 16), iron, Vector3(0, 1.35, 0), hook, Basis(Vector3.RIGHT, PI / 2))
	_mi(_cyl(0.04, 0.04, 1.0, 10), iron, Vector3(0, 0.8, 0), hook)
	var prev := Vector3(0, 0.3, 0)
	for k in 14:
		var a := PI * (k + 1) / 14.0 * 1.15
		var q := Vector3(0.28 - cos(a) * 0.28, 0.3 - sin(a) * 0.3, 0)
		q.x = -q.x + 0.0
		q = Vector3(0.28 - cos(a) * 0.28, 0.3 - sin(a) * 0.32, 0)
		var dv := q - prev
		_mi(_cyl(0.04 - k * 0.0015, 0.04 - k * 0.0015, dv.length() + 0.02, 10), iron, (q + prev) * 0.5, hook, Basis(Quaternion(Vector3.UP, dv.normalized())))
		prev = q
	_mi(_cyl(0.0, 0.03, 0.14, 8), iron, prev + Vector3(0.0, 0.08, 0), hook)
	_mi(_cyl(0.0, 0.022, 0.1, 6), iron, prev + Vector3(-0.05, 0.0, 0), hook, Basis(Vector3.BACK, 0.7))
	# 낚싯줄
	var line := _mat(Color(0.85, 0.85, 0.8), 0.4)
	_mi(_cyl(0.006, 0.006, 2.0, 5), line, Vector3(0, 2.4, 0), hook).set_meta("nofit", true)
	# 물고기: 옆으로 납작한 몸통 + 꼬리 · 등 · 배지느러미 + 눈 (갈고리가 몸을 꿰뚫음)
	var fish := Node3D.new()
	fish.position = Vector3(0.3, 0.12, 0)
	fish.rotation = Vector3(0, 0, -1.25)
	hook.add_child(fish)
	var scales := _grain(Color(0.55, 0.62, 0.66), 0.35, Vector2(6, 3), 0.35, 0.8, 0.4, 112)
	var belly := _mat(Color(0.88, 0.86, 0.8), 0.4, 0.2)
	var fprof := [Vector2(0.0, -0.5), Vector2(0.08, -0.42), Vector2(0.16, -0.25), Vector2(0.2, -0.05), Vector2(0.19, 0.12),
		Vector2(0.14, 0.3), Vector2(0.06, 0.45), Vector2(0.0, 0.5)]
	var fb := _mi(_lathe(fprof, 28), scales, Vector3.ZERO, fish)
	fb.scale = Vector3(1.0, 1.0, 0.45)
	var bl := _mi(_lathe(fprof, 28), belly, Vector3(0.025, 0.02, 0), fish)
	bl.scale = Vector3(0.9, 0.9, 0.42)
	var fin := _mat(Color(0.45, 0.5, 0.55, 0.85), 0.5)
	fin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fin.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 갈라진 꼬리 (얇은 삼각 지느러미 둘)
	for sgn in [-1.0, 1.0]:
		var tf := _mi(_cyl(0.0, 0.13, 0.3, 3), fin, Vector3(sgn * 0.07, -0.6, 0), fish, Basis(Vector3.BACK, PI - sgn * 0.45))
		tf.scale = Vector3(1.0, 1.0, 0.12)
	# 등지느러미 · 배지느러미
	var df := _mi(_cyl(0.0, 0.12, 0.26, 3), fin, Vector3(-0.17, 0.0, 0), fish, Basis(Vector3.BACK, PI / 2 + 0.3))
	df.scale = Vector3(1.0, 1.0, 0.1)
	var vf := _mi(_cyl(0.0, 0.07, 0.16, 3), fin, Vector3(0.17, -0.1, 0), fish, Basis(Vector3.BACK, -PI / 2 - 0.4))
	vf.scale = Vector3(1.0, 1.0, 0.1)
	var eye := _mat(Color(0.02, 0.02, 0.02), 0.1)
	var eyer := _mat(Color(0.85, 0.75, 0.4), 0.3, 0.5)
	for sgn in [-1.0, 1.0]:
		_mi(_sph(0.045, -1.0, 12), eyer, Vector3(-0.02, 0.33, sgn * 0.06), fish)
		_mi(_sph(0.028, -1.0, 10), eye, Vector3(-0.02, 0.33, sgn * 0.085), fish)
	# 아가미 선
	_mi(_torus(0.1, 0.115, 20), _mat(Color(0.3, 0.32, 0.35), 0.5), Vector3(0, 0.22, 0), fish, Basis.from_scale(Vector3(1.4, 1, 0.5)) * Basis(Vector3.RIGHT, PI / 2))
	# 피처럼 번지는 붉은 안개
	var blood := StandardMaterial3D.new()
	blood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blood.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blood.albedo_color = Color(0.6, 0.02, 0.04, 0.07)
	for k in 5:
		_mi(_sph(0.1 + k * 0.05, -1.0, 12), blood, Vector3(0.35 + k * 0.08, 0.1 - k * 0.12, -0.1), hook).set_meta("nofit", true)
	return root
