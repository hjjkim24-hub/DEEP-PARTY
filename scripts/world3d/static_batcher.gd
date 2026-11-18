extends RefCounted
## 움직이지 않는 장식 메시를 재질별 · 구역별로 하나로 합쳐서 그리기 호출을 확 줄여요.
## (섬 하나에 MeshInstance3D 가 9천 개 넘게 있어서, 그림자까지 치면 프레임마다 2만 번 가까이 그렸음)
##
##   StaticBatcher.batch(root, owner_script_obj, cell)
##     root 의 바로 아래 자식 MeshInstance3D 중 안전한 것만 합침:
##       · 스크립트/자식 없음, 보임, 투명도·보이는 거리·인스턴스 셰이더 값 없음
##       · 재질이 StandardMaterial3D 이거나, vertex() 로 모양을 움직이지 않는 ShaderMaterial
##       · owner 의 스크립트 변수(배열 · 사전 포함)가 붙잡고 있지 않음 (나중에 움직이거나 바꾸는 것)
##     합친 메시는 원점에 놓으므로 월드 좌표를 쓰는 셰이더도 그대로 맞음.

const MIN_GROUP := 2


static var _rej := {}

static func batch(root: Node3D, owners: Array, cell: float = 18.0) -> Dictionary:
	var keep := {}
	for ow in owners:
		_collect_refs(ow, keep)
	var groups := {}       # key → [MeshInstance3D …]
	var mats := {}         # key → Material
	var shadow := {}       # key → cast_shadow
	var cand := 0
	var found: Array = []      # [MeshInstance3D, root 기준 변환]
	_gather(root, Transform3D.IDENTITY, keep, found)
	for f in found:
		var mi: MeshInstance3D = f[0]
		var rx: Transform3D = f[1]
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(si)
			if mat == null:
				mat = mesh.surface_get_material(si)
			if mat == null or not _mat_ok(mat):
				var why := "null" if mat == null else (mat.get_class() + ":" + ((mat as ShaderMaterial).shader.resource_path if mat is ShaderMaterial and (mat as ShaderMaterial).shader else ""))
				_rej[why] = int(_rej.get(why, 0)) + 1
				continue
			var o := rx.origin
			var key := "%s|%d|%d|%d|%d" % [_sig(mat), int(mi.cast_shadow), mi.layers, floori(o.x / cell), floori(o.z / cell)]
			if not groups.has(key):
				groups[key] = []
				mats[key] = _shared_mat(mat)
				shadow[key] = mi.cast_shadow
			(groups[key] as Array).append([mi, si, mat, rx])
		cand += 1
	var merged := {}     # MeshInstance3D → 합쳐진 면 수
	var made := 0
	for key in groups:
		var items: Array = groups[key]
		if items.size() < MIN_GROUP:
			continue
		var am := _merge(items)
		if am == null:
			continue
		var out := MeshInstance3D.new()
		out.mesh = am
		out.material_override = mats[key]
		out.cast_shadow = shadow[key]
		out.name = "Batched"
		root.add_child(out)
		made += 1
		for it in items:
			merged[it[0]] = int(merged.get(it[0], 0)) + 1
	# 모든 면이 합쳐진 것만 지움. 일부 면만 합쳐진 것은 합친 쪽에서 그 면을 빼야 하는데,
	# 그런 경우는 드물어서 _ok 단계에서 면이 하나인 것만 받도록 함
	var gone := 0
	var parents := {}
	for c in merged:
		var mi := c as MeshInstance3D
		if int(merged[c]) >= mi.mesh.get_surface_count():
			var par := mi.get_parent()
			if par != root:
				parents[par] = true
			par.remove_child(mi)
			mi.queue_free()
			gone += 1
	# 비어 버린 빈 껍데기 Node3D 정리
	for par in parents:
		var nd := par as Node
		while nd != root and is_instance_valid(nd) and nd.get_child_count() == 0:
			var up := nd.get_parent()
			up.remove_child(nd)
			nd.queue_free()
			nd = up
	var single := 0
	var sk := {}
	for key in groups:
		if (groups[key] as Array).size() < MIN_GROUP:
			single += 1
			var m0: Material = (groups[key] as Array)[0][2]
			var nm := m0.get_class() + ":" + ((m0 as ShaderMaterial).shader.resource_path if m0 is ShaderMaterial else "")
			sk[nm] = int(sk.get(nm, 0)) + 1
	return {"candidates": cand, "batches": made, "removed": gone}


## root 아래로 내려가며 후보 모으기. 중간 부모는 스크립트 없는 맨 Node3D 이고 아무도 붙잡고 있지 않을 때만 안으로 들어감
static func _gather(node: Node, xf: Transform3D, keep: Dictionary, out: Array) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			if _ok(c as MeshInstance3D, keep):
				out.append([c, xf * (c as Node3D).transform])
		elif c.get_class() == "Node3D" and c.get_script() == null and not keep.has(c) \
				and (c as Node3D).visible and not (c as Node3D).top_level:
			_gather(c, xf * (c as Node3D).transform, keep, out)


static func _ok(mi: MeshInstance3D, keep: Dictionary) -> bool:
	if keep.has(mi) or mi.get_script() != null or mi.get_child_count() > 0 or not mi.visible or mi.top_level:
		return false
	if mi.mesh == null or mi.transparency > 0.0 or mi.visibility_range_end > 0.0 or mi.visibility_range_begin > 0.0:
		return false
	if mi.custom_aabb.size != Vector3.ZERO or mi.skeleton != NodePath("") and mi.skin != null:
		return false
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
		return false
	# 면이 하나인 것만 (여러 면짜리는 일부만 합쳐져 두 번 그려질 수 있음)
	if mi.mesh.get_surface_count() != 1:
		return false
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	return true


static var _shader_ok := {}

static func _mat_ok(m: Material) -> bool:
	if m.next_pass != null:
		return false
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		return sm.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and not sm.use_point_size
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		if sh == null:
			return false
		var id := sh.get_instance_id()
		if not _shader_ok.has(id):
			var code := sh.code
			if code.find("uniform bool batched") >= 0:
				_shader_ok[id] = true
				return true
			# vertex() 가 있어도 VERTEX 를 바꾸지 않으면(월드 좌표만 계산) 괜찮음
			var vtx := ""
			var vi := code.find("void vertex")
			if vi >= 0:
				var fi := code.find("void fragment")
				vtx = code.substr(vi, (fi - vi) if fi > vi else -1)
			var re := RegEx.new()
			re.compile("\\b(VERTEX|POSITION|MODELVIEW_MATRIX|NORMAL)(\\.[xyzw]+)?\\s*[-+*/]?=[^=]")
			var moves := re.search(vtx) != null or vtx.find("INSTANCE_CUSTOM") >= 0
			# 로컬 좌표(VERTEX)를 그대로 무늬·색에 쓰면 합친 뒤 달라짐 → 월드 좌표로 바꾸는 것만 허용
			var rest := vtx.replace("MODEL_MATRIX * vec4(VERTEX, 1.0)", "").replace("MODEL_MATRIX*vec4(VERTEX,1.0)", "") \
					.replace("mat3(MODEL_MATRIX) * NORMAL", "").replace("MODEL_MATRIX * vec4(NORMAL, 0.0)", "")
			var ok := not moves and rest.find("VERTEX") < 0 and rest.find("NORMAL") < 0
			for bad in ["instance uniform", "NODE_POSITION", "skip_vertex_transform", "world_vertex_coords", "billboard"]:
				if code.find(bad) >= 0:
					ok = false
			_shader_ok[id] = ok
		return _shader_ok[id]
	return false


static var _sig_cache := {}
const _SKIP := {"albedo_color": true, "resource_name": true, "resource_path": true, "resource_local_to_scene": true,
	"script": true, "vertex_color_use_as_albedo": true, "vertex_color_is_srgb": true}

## 같은 모양으로 그려지는 재질끼리 같은 값. StandardMaterial3D 는 색(albedo_color)만 다른 건 같은 걸로 침 (색은 꼭짓점 색으로 구움)
static func _sig(m: Material) -> String:
	var id := m.get_instance_id()
	if _sig_cache.has(id):
		return _sig_cache[id]
	var parts := PackedStringArray([m.get_class()])
	if m is ShaderMaterial:
		parts.append(str((m as ShaderMaterial).shader.get_instance_id()))
		for u in RenderingServer.get_shader_parameter_list((m as ShaderMaterial).shader.get_rid()):
			var v = (m as ShaderMaterial).get_shader_parameter(u["name"])
			parts.append("%s=%s" % [u["name"], str(v.get_instance_id()) if v is Object else str(v)])
	else:
		for p in m.get_property_list():
			if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE) or _SKIP.has(p["name"]):
				continue
			var v = m.get(p["name"])
			parts.append("%s=%s" % [p["name"], str(v.get_instance_id()) if v is Object else str(v)])
		# 꼭짓점 색을 쓰는 재질인지는 구울 때 따로 처리하므로 모양에는 안 넣음
	var sg := str(hash("|".join(parts)))
	_sig_cache[id] = sg
	return sg


## 합친 메시가 쓸 재질: StandardMaterial3D 면 색을 꼭짓점 색으로 받도록 복사본
static func _batchable_shader(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.code.find("uniform bool batched") >= 0


static func _shared_mat(m: Material) -> Material:
	if _batchable_shader(m):
		var b := (m as ShaderMaterial).duplicate() as ShaderMaterial
		b.set_shader_parameter("batched", true)
		return b
	if not (m is StandardMaterial3D):
		return m
	var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
	d.albedo_color = Color.WHITE
	d.vertex_color_use_as_albedo = true
	d.vertex_color_is_srgb = true
	return d


## 원래 재질로 그렸을 때와 같은 색이 나오게 꼭짓점 색 계산 (sRGB 로 저장)
static func _bake_col(m: Material, vc: Variant) -> Color:
	var sm := m as StandardMaterial3D
	var lin := sm.albedo_color.srgb_to_linear()
	if sm.vertex_color_use_as_albedo and vc != null:
		var c: Color = vc
		var cl := c.srgb_to_linear() if sm.vertex_color_is_srgb else c
		lin = Color(lin.r * cl.r, lin.g * cl.g, lin.b * cl.b, lin.a * cl.a)
	var out := lin.linear_to_srgb()
	out.a = lin.a
	return out


static func _merge(items: Array) -> ArrayMesh:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var T := PackedFloat32Array()
	var C := PackedColorArray()
	var U := PackedVector2Array()
	var I := PackedInt32Array()
	var any_col := false
	var any_tan := false
	var any_uv := false
	var parts := []
	var std: bool = items[0][2] is StandardMaterial3D
	var bat: bool = _batchable_shader(items[0][2])
	var C0 := PackedFloat32Array()
	var C1 := PackedFloat32Array()
	var C2 := PackedFloat32Array()
	var C3 := PackedFloat32Array()
	for it in items:
		var mi: MeshInstance3D = it[0]
		var a: Array = mi.mesh.surface_get_arrays(int(it[1]))
		parts.append([it[3], a, it[2]])
		any_col = any_col or a[Mesh.ARRAY_COLOR] != null or std
		any_tan = any_tan or a[Mesh.ARRAY_TANGENT] != null
		any_uv = any_uv or a[Mesh.ARRAY_TEX_UV] != null
	for pt in parts:
		var xf: Transform3D = pt[0]
		var a: Array = pt[1]
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		var base := V.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n = a[Mesh.ARRAY_NORMAL]
		for k in v.size():
			V.append(xf * v[k])
		if n != null:
			for k in v.size():
				N.append((nb * (n as PackedVector3Array)[k]).normalized())
		else:
			for k in v.size():
				N.append(Vector3.UP)
		if any_tan:
			var t = a[Mesh.ARRAY_TANGENT]
			for k in v.size():
				if t != null:
					var tv := Vector3(t[k * 4], t[k * 4 + 1], t[k * 4 + 2])
					tv = (xf.basis * tv).normalized()
					T.append_array([tv.x, tv.y, tv.z, t[k * 4 + 3]])
				else:
					T.append_array([1.0, 0.0, 0.0, 1.0])
		if any_col:
			var col = a[Mesh.ARRAY_COLOR]
			if std:
				var m0: Material = pt[2]
				if col == null:
					var bc := _bake_col(m0, null)
					for k in v.size():
						C.append(bc)
				else:
					for k in v.size():
						C.append(_bake_col(m0, (col as PackedColorArray)[k]))
			else:
				for k in v.size():
					C.append((col as PackedColorArray)[k] if col != null else Color.WHITE)
		if any_uv:
			var uv = a[Mesh.ARRAY_TEX_UV]
			for k in v.size():
				U.append((uv as PackedVector2Array)[k] if uv != null else Vector2.ZERO)
		if bat:
			var o := xf.origin
			var oid := fposmod(sin(o.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)
			var bx := xf.basis.x
			var by := xf.basis.y
			var bz := xf.basis.z
			for k in v.size():
				var ln: Vector3 = (n as PackedVector3Array)[k] if n != null else Vector3.UP
				C0.append_array([v[k].x, v[k].y, v[k].z, oid])
				C1.append_array([bx.x, bx.y, bx.z, ln.x])
				C2.append_array([by.x, by.y, by.z, ln.y])
				C3.append_array([bz.x, bz.y, bz.z, ln.z])
		var idx = a[Mesh.ARRAY_INDEX]
		if idx != null:
			var ii: PackedInt32Array = idx
			if flip:
				for k in range(0, ii.size(), 3):
					I.append_array([base + ii[k], base + ii[k + 2], base + ii[k + 1]])
			else:
				for k in ii.size():
					I.append(base + ii[k])
		else:
			for k in range(0, v.size(), 3):
				if flip:
					I.append_array([base + k, base + k + 2, base + k + 1])
				else:
					I.append_array([base + k, base + k + 1, base + k + 2])
	if V.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	if any_tan:
		arr[Mesh.ARRAY_TANGENT] = T
	if any_col:
		arr[Mesh.ARRAY_COLOR] = C
	if any_uv:
		arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_INDEX] = I
	var flags := 0
	if bat:
		arr[Mesh.ARRAY_CUSTOM0] = C0
		arr[Mesh.ARRAY_CUSTOM1] = C1
		arr[Mesh.ARRAY_CUSTOM2] = C2
		arr[Mesh.ARRAY_CUSTOM3] = C3
		var f := Mesh.ARRAY_CUSTOM_RGBA_FLOAT
		flags = (f << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (f << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
				| (f << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (f << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return am


## owner 의 스크립트 변수들이 붙잡고 있는 노드는 합치지 않음 (나중에 움직이거나 재질을 바꿀 수 있으니)
static func _collect_refs(owner: Object, out: Dictionary) -> void:
	for p in owner.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_walk(owner.get(p["name"]), out, 0)


static func _walk(v: Variant, out: Dictionary, depth: int) -> void:
	if depth > 4:
		return
	if v is Node:
		out[v] = true
	elif v is Array:
		for e in v:
			_walk(e, out, depth + 1)
	elif v is Dictionary:
		for k in v:
			_walk(k, out, depth + 1)
			_walk(v[k], out, depth + 1)
