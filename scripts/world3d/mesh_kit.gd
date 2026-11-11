extends RefCounted
## 코드로 만드는 모양들 (둥근 상자 등). 주사위·칸·장식이 같이 씀.


## 모서리가 둥근 상자. atlas=true 면 면마다 3x2 그림판의 칸을 씀 (주사위)
##   그림판 칸: 0=+Y(1) 1=+Z(2) 2=+X(3) 3=-X(4) 4=-Z(5) 5=-Y(6)
static func rounded_box(size: Vector3, radius: float, atlas: bool = false, edge_steps: int = 4) -> ArrayMesh:
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.98)
	var inner := h - Vector3(r, r, r)
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK, 0],
		[Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 1],
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN, 2],
		[Vector3.LEFT, Vector3.BACK, Vector3.DOWN, 3],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN, 4],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, 5],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var cell: int = f[3]
		var hn := absf(h.dot(n))
		var hu := absf(h.dot(u))
		var hv := absf(h.dot(v))
		var cu := _coords(hu, r, edge_steps)
		var cv := _coords(hv, r, edge_steps)
		for j in cv.size():
			for i in cu.size():
				var p: Vector3 = n * hn + u * cu[i] + v * cv[j]
				var ip := p.clamp(-inner, inner)
				var d := p - ip
				var nn := d.normalized() if d.length() > 0.00001 else n
				var q := ip + nn * r
				var a: float = cu[i] / hu * 0.5 + 0.5
				var b: float = cv[j] / hv * 0.5 + 0.5
				var uv := Vector2(a, b)
				if atlas:
					uv = Vector2((float(cell % 3) + a) / 3.0, (float(cell / 3) + b) / 2.0)
				st.set_normal(nn)
				st.set_uv(uv)
				st.add_vertex(q)
		# 앞면 방향 맞추기 (Godot 은 바깥에서 볼 때 시계 방향이 앞면)
		var flip := u.cross(v).dot(n) > 0.0
		var w := cu.size()
		for j in cv.size() - 1:
			for i in w - 1:
				var i0 := base + j * w + i
				var i1 := i0 + 1
				var i2 := i0 + w + 1
				var i3 := i0 + w
				if flip:
					st.add_index(i0); st.add_index(i2); st.add_index(i1)
					st.add_index(i0); st.add_index(i3); st.add_index(i2)
				else:
					st.add_index(i0); st.add_index(i1); st.add_index(i2)
					st.add_index(i0); st.add_index(i2); st.add_index(i3)
		base += w * cv.size()
	if atlas:
		st.generate_tangents()    # 주사위 노멀맵용
	return st.commit()


static func _coords(half: float, r: float, steps: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in steps + 1:
		var t := float(k) / steps
		out.append(-half + r * (1.0 - cos(t * PI * 0.5)))
	for k in range(steps, -1, -1):
		var t := float(k) / steps
		out.append(half - r * (1.0 - cos(t * PI * 0.5)))
	return out
