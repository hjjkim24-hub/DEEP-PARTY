extends RefCounted
## 바다 밑 꾸미기용 모양들 (코드로 만듦): 물고기, 불가사리, 조개, 해초 덤불, 다시마 잎, 말미잘.
## 전부 static — ReefKit.fish_mesh() 처럼 써요.


## 삼각형 하나를 바깥(out) 쪽이 앞면이 되게 넣기 (Godot: 바깥에서 볼 때 시계 방향)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, uv: Array = []) -> void:
	var u0 := Vector2.ZERO
	var u1 := Vector2.ZERO
	var u2 := Vector2.ZERO
	if uv.size() == 3:
		u0 = uv[0]
		u1 = uv[1]
		u2 = uv[2]
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tu := u1
		u1 = u2
		u2 = tu
	st.set_uv(u0)
	st.add_vertex(a)
	st.set_uv(u1)
	st.add_vertex(b)
	st.set_uv(u2)
	st.add_vertex(c)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	st.generate_normals()
	return st.commit()


## 물고기 (머리가 +Z). UV.y: 0=꼬리 … 1=머리 (꼬리 흔들기에 씀)
static func fish_mesh(length: float = 0.5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var nz := 9
	var na := 10
	for i in nz + 1:
		var t := float(i) / nz
		var z := lerpf(-0.42, 0.5, t) * length
		var r := sin(clampf(t, 0.0, 1.0) * PI) * 0.17 * length * (0.55 + 0.45 * t)
		r = maxf(r, 0.004)
		var ring := []
		for j in na:
			var a := TAU * j / na
			ring.append(Vector3(cos(a) * r * 0.55, sin(a) * r, z))
		rings.append(ring)
	for i in nz:
		for j in na:
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][(j + 1) % na]
			var c: Vector3 = rings[i + 1][(j + 1) % na]
			var d: Vector3 = rings[i + 1][j]
			var out := ((a + c) * 0.5) * Vector3(1, 1, 0)
			var v0 := float(i) / nz
			var v1 := float(i + 1) / nz
			_tri(st, a, b, c, out, [Vector2(0, v0), Vector2(0, v0), Vector2(0, v1)])
			_tri(st, a, c, d, out, [Vector2(0, v0), Vector2(0, v1), Vector2(0, v1)])
	# 꼬리지느러미 (세로, 양면)
	var tz := -0.42 * length
	var tail := [Vector3(0, 0, tz + 0.02 * length), Vector3(0, 0.2 * length, tz - 0.26 * length), Vector3(0, -0.2 * length, tz - 0.26 * length)]
	_tri(st, tail[0], tail[1], tail[2], Vector3(1, 0, 0), [Vector2(0, 0.05), Vector2(0, 0), Vector2(0, 0)])
	# 등지느러미
	var dz := 0.05 * length
	var dorsal := [Vector3(0, 0.15 * length, dz + 0.12 * length), Vector3(0, 0.27 * length, dz - 0.06 * length), Vector3(0, 0.12 * length, dz - 0.16 * length)]
	_tri(st, dorsal[0], dorsal[1], dorsal[2], Vector3(1, 0, 0), [Vector2(0, 0.6), Vector2(0, 0.5), Vector2(0, 0.45)])
	return _finish(st)


## 불가사리 (반지름 1, 납작)
static func starfish_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 0.16, 0)
	var pts := []
	for k in 10:
		var a := TAU * k / 10.0 - PI / 2.0
		var r := 1.0 if k % 2 == 0 else 0.42
		pts.append(Vector3(cos(a) * r, 0.03 if k % 2 == 0 else 0.07, sin(a) * r))
	for k in 10:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 10]
		_tri(st, top, a, b, Vector3.UP)
		_tri(st, a, b, Vector3(a.x, 0, a.z), (a + b) * Vector3(1, 0, 1))
		_tri(st, b, Vector3(b.x, 0, b.z), Vector3(a.x, 0, a.z), (a + b) * Vector3(1, 0, 1))
	return _finish(st)


## 가리비 조개 (부채꼴, 골이 있음). 경첩이 원점, +Z 쪽으로 펼쳐짐
static func shell_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hinge := Vector3(0, 0.05, 0)
	var n := 16
	var arc := []
	for k in n + 1:
		var a := lerpf(-1.15, 1.15, float(k) / n)
		var ridge := 0.2 if k % 2 == 0 else 0.11
		arc.append(Vector3(sin(a), ridge, cos(a)))
	for k in n:
		var a: Vector3 = arc[k]
		var b: Vector3 = arc[k + 1]
		var mid := (a + b) * 0.5 * 0.55 + Vector3(0, 0.22, 0)
		_tri(st, hinge, a, mid, Vector3.UP)
		_tri(st, hinge, mid, b, Vector3.UP)
		_tri(st, mid, a, b, Vector3.UP + (a + b) * 0.3)
		_tri(st, a, b, Vector3(b.x, 0, b.z), (a + b) * Vector3(1, 0, 1))
		_tri(st, a, Vector3(b.x, 0, b.z), Vector3(a.x, 0, a.z), (a + b) * Vector3(1, 0, 1))
	# 경첩 날개
	for side in [-1.0, 1.0]:
		_tri(st, hinge, Vector3(side * 0.32, 0.03, -0.08), Vector3(side * 0.28, 0.04, 0.12), Vector3.UP)
	return _finish(st)


## 해초 덤불 (가는 잎 여러 장). UV.y: 0=뿌리 1=끝
static func grass_clump_mesh(rng: RandomNumberGenerator, blades: int = 6, height: float = 0.8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var yaw := rng.randf() * TAU
		var lean := rng.randf_range(0.15, 0.55)
		var h := height * rng.randf_range(0.6, 1.2)
		var w := rng.randf_range(0.035, 0.06)
		var base := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var side := Vector3(cos(yaw), 0, -sin(yaw))
		var segs := 5
		var prev_l := base - side * w
		var prev_r := base + side * w
		for s in range(1, segs + 1):
			var t := float(s) / segs
			var c := base + Vector3(0, h * t, 0) + fwd * (lean * h * t * t)
			var ww := w * (1.0 - t * 0.9)
			var l := c - side * ww
			var r := c + side * ww
			var v0 := float(s - 1) / segs
			_tri(st, prev_l, prev_r, r, fwd, [Vector2(0, v0), Vector2(1, v0), Vector2(1, t)])
			_tri(st, prev_l, r, l, fwd, [Vector2(0, v0), Vector2(1, t), Vector2(0, t)])
			prev_l = l
			prev_r = r
	return _finish(st)


## 다시마 (넓적한 리본 잎 몇 장 + 공기주머니). UV.y: 0=뿌리 1=끝
static func kelp_mesh(rng: RandomNumberGenerator, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 3:
		var yaw := rng.randf() * TAU
		var hh := h * rng.randf_range(0.65, 1.0)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var side := Vector3(cos(yaw), 0, -sin(yaw))
		var base := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var segs := 14
		var ph := rng.randf() * TAU
		var prev_l := base
		var prev_r := base
		for s in range(1, segs + 1):
			var t := float(s) / segs
			var c := base + Vector3(0, hh * t, 0) + side * sin(t * 5.0 + ph) * 0.18 + fwd * t * 0.4
			var ww := (0.08 + 0.2 * sin(clampf(t * 1.15, 0.0, 1.0) * PI)) * (1.0 + 0.25 * sin(t * 23.0 + ph))
			var l := c - side * ww
			var r := c + side * ww
			var v0 := float(s - 1) / segs
			_tri(st, prev_l, prev_r, r, fwd, [Vector2(0, v0), Vector2(1, v0), Vector2(1, t)])
			_tri(st, prev_l, r, l, fwd, [Vector2(0, v0), Vector2(1, t), Vector2(0, t)])
			prev_l = l
			prev_r = r
	return _finish(st)


## 말미잘 (촉수 여러 개를 한 덩어리로). UV.y: 0=뿌리 1=끝
static func anemone_mesh(rng: RandomNumberGenerator, n: int = 54) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 몸통: 통통한 기둥 (아래가 살짝 퍼지고 위가 오므라듦)
	var prof := [Vector2(0.4, 0.0), Vector2(0.36, 0.06), Vector2(0.38, 0.16), Vector2(0.43, 0.26), Vector2(0.4, 0.34), Vector2(0.28, 0.39), Vector2(0.0, 0.4)]
	var col := 20
	for i in prof.size() - 1:
		var pa: Vector2 = prof[i]
		var pb: Vector2 = prof[i + 1]
		for j in col:
			var a0 := TAU * j / col
			var a1 := TAU * (j + 1) / col
			var p00 := Vector3(cos(a0) * pa.x, pa.y, sin(a0) * pa.x)
			var p01 := Vector3(cos(a1) * pa.x, pa.y, sin(a1) * pa.x)
			var p10 := Vector3(cos(a0) * pb.x, pb.y, sin(a0) * pb.x)
			var p11 := Vector3(cos(a1) * pb.x, pb.y, sin(a1) * pb.x)
			var out := Vector3(cos((a0 + a1) * 0.5), 0.3, sin((a0 + a1) * 0.5))
			_tri(st, p00, p01, p11, out)
			if pb.x > 0.001:
				_tri(st, p00, p11, p10, out)
	# 촉수: 바깥으로 휘어 늘어지는 가는 관 (끝으로 갈수록 가늘어짐)
	for k in n:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 0.34
		var base := Vector3(cos(a) * rr, 0.37, sin(a) * rr)
		var outw := Vector3(cos(a), 0, sin(a))
		var lean := 0.25 + rr * 2.2 + rng.randf_range(-0.15, 0.15)
		var ln := rng.randf_range(0.4, 0.68)
		var w := rng.randf_range(0.03, 0.042)
		var segs := 4
		var prev_c := base
		var prev_r := w
		for q in segs:
			var t1 := float(q + 1) / segs
			# 위로 뻗다가 바깥으로 휨
			var c1 := base + Vector3.UP * ln * t1 * (1.0 - 0.3 * lean * t1) + outw * ln * lean * t1 * t1 * 0.8
			var r1 := w * (1.0 - 0.75 * t1)
			var axis := (c1 - prev_c).normalized()
			var sx := axis.cross(outw + Vector3(0.01, 0.02, 0.03)).normalized()
			var sy := axis.cross(sx).normalized()
			for e in 4:
				var e0 := TAU * e / 4.0
				var e1 := TAU * (e + 1) / 4.0
				var d0 := sx * cos(e0) + sy * sin(e0)
				var d1 := sx * cos(e1) + sy * sin(e1)
				var v0 := float(q) / segs
				_tri(st, prev_c + d0 * prev_r, prev_c + d1 * prev_r, c1 + d1 * r1, d0 + d1, [Vector2(0, v0), Vector2(0, v0), Vector2(0, t1)])
				_tri(st, prev_c + d0 * prev_r, c1 + d1 * r1, c1 + d0 * r1, d0 + d1, [Vector2(0, v0), Vector2(0, t1), Vector2(0, t1)])
			prev_c = c1
			prev_r = r1
	return _finish(st)


## 뇌산호 (울퉁불퉁한 반구)
static func brain_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	sm.is_hemisphere = true
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var seed_ := rng.randf() * 10.0
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + 0.06 * sin(v.x * 7.0 + seed_) * sin(v.z * 6.0 + seed_ * 1.7) + 0.04 * sin(v.y * 9.0 + seed_)
		verts[i] = Vector3(v.x * k, maxf(v.y, 0.0) * k * 0.7, v.z * k)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()
