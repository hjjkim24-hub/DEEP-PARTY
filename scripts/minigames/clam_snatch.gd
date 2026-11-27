extends "res://scripts/minigames/minigame_3d.gd"
## 조개 낚아채기 (클릭): 바닷속 바위밭에 큰 조개 9개. 조개가 입을 벌리면 안에 진주(1점) · 황금 진주(3점)가 반짝여요.
## 먼저 클릭한 사람이 가져가요! 단, 집게발을 든 게가 숨어 있는 조개를 누르면 -2점 + 잠깐 못 누름. 30초.

const COLS := 3
const ROWS := 3
const GAP := 3.0

var _clams: Array = []       ## {root, lid, pos, state(closed/open), t, kind(pearl/gold/crab), item, owner}
var _spawn := 0.5
var _elapsed := 0.0
var _stun := {}
var _ai := {}


func _init() -> void:
	auto_bake = true
	title = "CLAM SNATCH"
	how_to = "Giant clams snap open with pearls inside - click one first to grab it! Golden pearls are worth 3. But if a crab is hiding inside, you lose 2 points!"
	goal = "Most pearls wins!"
	controls = "MOUSE"
	duration = 30.0


func _build_stage() -> void:
	env_underwater()
	cam.fov = 46.0
	cam.position = Vector3(0, 11.0, 9.0)
	cam.look_at(Vector3(0, 0, 0.3))
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/mg_sand.gdshader")
	sm.set_shader_parameter("sand_albedo", kit._mip_tex(load("res://textures/seabed/sand_albedo.png")))
	sm.set_shader_parameter("sand_normal", kit._mip_tex(load("res://textures/seabed/sand_normal.png")))
	add_mesh(pm, sm, Vector3.ZERO)
	seed(23)
	var rr := RandomNumberGenerator.new()
	rr.seed = 8
	var cols := [Color(1.0, 0.4, 0.38), Color(0.76, 0.42, 0.98), Color(1.0, 0.6, 0.28), Color(0.35, 0.85, 0.8), Color(1.0, 0.84, 0.38)]
	for k in 18:
		var a := TAU * k / 18.0
		var r := rr.randf_range(6.3, 7.6)
		reef("rock", Vector3(cos(a) * r * 1.25, -0.3, sin(a) * r), Color.WHITE, rr.randf_range(1.2, 2.0))
	for k in 16:
		var a := TAU * (k + 0.5) / 16.0
		reef(["coral", "anemone", "fan", "brain", "sponge"][k % 5], Vector3(cos(a) * 6.0 * 1.2, 0, sin(a) * 5.2), cols[k % 5], 0.9)
	underwater_fx(12.0, 10.0)
	fish_school(Vector3(0, 5.0, -4.0), 7.0, 22, 0.3, 0.45, Color(1.0, 0.75, 0.3), Color(0.95, 0.95, 1.0))
	jelly(Vector3(-5.0, 4.0, -3.0), Color(0.8, 0.5, 1.0))
	jelly(Vector3(5.5, 3.5, -2.0), Color(0.5, 0.85, 1.0))
	for j in ROWS:
		for i in COLS:
			var p := Vector3((i - 1) * GAP * 1.25, 0, (j - 1) * GAP)
			_clams.append(_make_clam(p))


## 큰 가리비: 두께 있는 골진 두 껍데기(위는 뒤 경첩으로 열림) · 진주빛 안쪽 · 하얀 관자 · 주황 생식소 · 눈점 박힌 외투막
const SHELL_PAL := [Color(0.86, 0.76, 0.6), Color(0.84, 0.5, 0.3), Color(0.78, 0.62, 0.38), Color(0.82, 0.56, 0.52), Color(0.72, 0.58, 0.48)]
const HINGE := Vector3(0, 0.25, -0.95)


func _make_clam(p: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = rng.randf_range(-0.2, 0.2)
	world3.add_child(root)
	var base: Color = SHELL_PAL[rng.randi() % SHELL_PAL.size()]
	var shell := StandardMaterial3D.new()
	# 조개마다 살짝 다른 색 (메시는 같은 색끼리 공유 → 재질로 물들임)
	shell.albedo_color = Color.WHITE.lerp(Color(rng.randf(), rng.randf(), rng.randf()).lightened(0.4), 0.08)
	shell.vertex_color_use_as_albedo = true
	shell.roughness = 0.55
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.clearcoat_enabled = true
	shell.clearcoat = 0.15
	add_mesh(_shell_mesh(false, base), shell, HINGE, Basis(), root)
	# 속살 (아래 껍데기 안에 놓임)
	var flesh := Node3D.new()
	flesh.position = HINGE
	root.add_child(flesh)
	var muscle := StandardMaterial3D.new()
	muscle.albedo_color = Color(0.82, 0.76, 0.66)
	muscle.roughness = 0.25
	muscle.clearcoat_enabled = true
	var mus := SphereMesh.new()
	mus.radius = 0.36
	mus.height = 0.2
	add_mesh(mus, muscle, Vector3(0, -0.12, 1.0), Basis(), flesh).scale = Vector3(1.0, 1.0, 0.95)
	var roe := StandardMaterial3D.new()
	roe.albedo_color = Color(0.95, 0.45, 0.2)
	roe.roughness = 0.3
	roe.clearcoat_enabled = true
	var gon := SphereMesh.new()
	gon.radius = 0.24
	gon.height = 0.14
	add_mesh(gon, roe, Vector3(0.3, -0.13, 0.62), Basis(Vector3.UP, 0.6), flesh).scale = Vector3(1.5, 1.0, 0.8)
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.roughness = 0.35
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_mesh(_mantle_mesh(), mm, Vector3.ZERO, Basis(), flesh)
	# 외투막 가장자리의 작은 파란 눈들
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.05, 0.12, 0.35)
	eye.roughness = 0.05
	eye.metallic_specular = 1.0
	var em := SphereMesh.new()
	em.radius = 0.028
	em.height = 0.056
	em.radial_segments = 8
	em.rings = 4
	for i in 17:
		var u := (i + 0.5) / 17.0
		var q := _shell_pt(u, 0.88, false) + Vector3(0, 0.1, 0)
		add_mesh(em, eye, q, Basis(), flesh)
	var lid := Node3D.new()
	lid.position = HINGE
	root.add_child(lid)
	add_mesh(_shell_mesh(true, base), shell, Vector3.ZERO, Basis(), lid)
	return {"root": root, "lid": lid, "pos": p, "state": "closed", "t": 0.0, "kind": "", "item": null, "open_for": 0.0, "seq": 0}


## 껍데기 겉면의 한 점 (u = 부채 각도 0..1, v = 경첩 0 → 가장자리 1)
static func _shell_pt(u: float, v: float, top: bool, inset: float = 0.0) -> Vector3:
	var R := 1.95
	var a := lerpf(-0.95, 0.95, u)
	var rib := absf(sin(u * PI * 13.0))
	var r := R * v * (1.0 + 0.045 * rib * v) - inset * 0.6
	var bulge := 0.55 * pow(sin(v * PI), 0.7) * (0.55 + 0.45 * cos(a * 1.6)) + 0.03 * rib * v
	var y := bulge * (1.0 if top else -0.55)
	y += (-inset if top else inset)
	return Vector3(sin(a) * r, y, cos(a) * r)


static var _shell_cache := {}
static var _mantle_cache: ArrayMesh


func _shell_mesh(top: bool, base: Color) -> ArrayMesh:
	var key := "%s|%s" % [top, base.to_html()]
	if not _shell_cache.has(key):
		_shell_cache[key] = _shell_make(top, base)
	return _shell_cache[key]


func _shell_make(top: bool, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 52
	var nv := 14
	var T := 0.07
	var outer := []
	var inner := []
	for j in nv + 1:
		var v := float(j) / nv
		var ro := []
		var ri := []
		for i in nu + 1:
			var u := float(i) / nu
			var rib := absf(sin(u * PI * 13.0))
			var growth := 0.5 + 0.5 * sin(v * 46.0 + sin(u * 9.0) * 0.6)
			var band := smoothstep(0.55, 0.9, sin(v * 9.0 + 1.3) * 0.5 + 0.5)
			var col := base.darkened(0.32).lerp(base.lightened(0.18), rib)
			col = col.lerp(base.darkened(0.45), band * 0.35 * v)
			col = col.darkened(growth * 0.08 * v)
			col = col.lerp(Color(0.93, 0.9, 0.84), (1.0 - v) * 0.35)
			ro.append([_shell_pt(u, v, top), col])
			# 안쪽: 진주빛 흰 바탕, 경첩 쪽에 보랏빛 얼룩, 가장자리로 갈수록 바깥 색이 비침
			var nac := Color(0.6, 0.58, 0.58).lerp(Color(0.5, 0.42, 0.5), (1.0 - smoothstep(0.0, 0.35, v)) * 0.6)
			nac = nac.lerp(base, smoothstep(0.8, 1.0, v) * 0.6)
			ri.append([_shell_pt(u, v * 0.985, top, T * smoothstep(0.0, 0.15, v)), nac])
		outer.append(ro)
		inner.append(ri)
	var quad := func(a: Array, b: Array, c: Array, d: Array, flip: bool) -> void:
		for vtx in ([a, c, b, b, c, d] if flip else [a, b, c, b, d, c]):
			st.set_color(vtx[1])
			st.add_vertex(vtx[0])
	for j in nv:
		for i in nu:
			quad.call(outer[j][i], outer[j][i + 1], outer[j + 1][i], outer[j + 1][i + 1], top)
			quad.call(inner[j][i], inner[j][i + 1], inner[j + 1][i], inner[j + 1][i + 1], not top)
	# 가장자리 두께 띠
	for i in nu:
		var a: Array = outer[nv][i]
		var b: Array = outer[nv][i + 1]
		var c: Array = [inner[nv][i][0], (a[1] as Color).darkened(0.25)]
		var d: Array = [inner[nv][i + 1][0], (b[1] as Color).darkened(0.25)]
		quad.call(a, b, c, d, not top)
	st.generate_normals()
	return st.commit()


## 아래 껍데기 가장자리를 따라 너울거리는 외투막 띠 (주황 · 갈색, 끝은 술 모양)
func _mantle_mesh() -> ArrayMesh:
	if _mantle_cache == null:
		_mantle_cache = _mantle_make()
	return _mantle_cache


func _mantle_make() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 60
	var rows := [0.74, 0.86, 0.95]
	var cols := [Color(0.85, 0.55, 0.35), Color(0.62, 0.36, 0.22), Color(0.4, 0.22, 0.14)]
	var pts := []
	for k in rows.size():
		var row := []
		for i in nu + 1:
			var u := float(i) / nu
			var q := _shell_pt(u, rows[k], false, 0.07)
			q.y += 0.04 + sin(u * 70.0 + k) * 0.025 * k
			row.append(q)
		pts.append(row)
	for k in rows.size() - 1:
		for i in nu:
			var a: Vector3 = pts[k][i]
			var b: Vector3 = pts[k][i + 1]
			var c: Vector3 = pts[k + 1][i]
			var d: Vector3 = pts[k + 1][i + 1]
			for v in [[a, k], [c, k + 1], [b, k], [b, k], [c, k + 1], [d, k + 1]]:
				st.set_color(cols[v[1]])
				st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()


func _setup_game() -> void:
	for p in players:
		scores[int(p["slot"])] = 0
		_stun[int(p["slot"])] = 0.0
		_ai[int(p["slot"])] = {"t": rng.randf_range(0.3, 0.8)}


func _tick(delta: float) -> void:
	_elapsed += delta
	_t3 += delta
	var pr := pressure()
	_spawn -= delta
	if _spawn <= 0.0 and not is_client():
		_open_one(pr)
		_spawn = lerpf(0.75, 0.3, pr) * rng.randf_range(0.8, 1.2)
	for k in _clams.size():
		var c: Dictionary = _clams[k]
		if c["state"] == "open":
			c["t"] = float(c["t"]) + delta
			if float(c["t"]) >= float(c["open_for"]) and not is_client():
				net_call("_close_idx", [k])
		if c["item"] and is_instance_valid(c["item"]):
			(c["item"] as Node3D).rotation.y += delta * 2.0
	for s in _stun:
		_stun[s] = maxf(0.0, float(_stun[s]) - delta)
	_think(delta)


func _open_one(pr: float) -> void:
	var closed := _clams.filter(func(c: Dictionary) -> bool: return c["state"] == "closed")
	if closed.is_empty():
		return
	var c: Dictionary = closed[rng.randi() % closed.size()]
	var roll := rng.randf()
	var crab_p := lerpf(0.15, 0.4, pr)
	var kind := "crab" if roll < crab_p else ("gold" if roll < crab_p + 0.12 else "pearl")
	net_call("_open_do", [_clams.find(c), kind, lerpf(1.6, 0.75, pr) * rng.randf_range(0.85, 1.15)])


## 조개 하나가 열림 (방장이 정한 대로 모두 같게)
func _open_do(idx: int, kind: String, open_for: float) -> void:
	var c: Dictionary = _clams[idx]
	if c["state"] != "closed":
		if c["item"] and is_instance_valid(c["item"]):
			(c["item"] as Node3D).queue_free()
		c["item"] = null
	c["kind"] = kind
	c["state"] = "open"
	c["t"] = 0.0
	c["seq"] = int(c.get("seq", 0)) + 1
	c["open_for"] = open_for
	var lid: Node3D = c["lid"]
	create_tween().tween_property(lid, "rotation:x", -0.85, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var root: Node3D = c["root"]
	var item: Node3D
	if c["kind"] == "crab":
		item = _crab()
		item.scale = Vector3.ONE * 0.85
	else:
		var s := SphereMesh.new()
		s.radius = 0.24 if c["kind"] == "pearl" else 0.3
		s.height = s.radius * 2.0
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.96, 0.95, 1.0) if c["kind"] == "pearl" else Color(1.0, 0.8, 0.3)
		m.roughness = 0.06
		m.metallic = 0.0 if c["kind"] == "pearl" else 0.8
		m.clearcoat_enabled = true
		m.rim_enabled = true
		m.rim = 0.7
		m.emission_enabled = true
		m.emission = Color(0.3, 0.32, 0.36) if c["kind"] == "pearl" else Color(0.7, 0.45, 0.08)
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		item = mi
		var gl := OmniLight3D.new()
		gl.light_color = Color(1.0, 0.9, 0.7) if c["kind"] == "gold" else Color(0.85, 0.95, 1.0)
		gl.light_energy = 1.2
		gl.omni_range = 2.0
		gl.position = Vector3(0, 0.3, 0)
		mi.add_child(gl)
	root.add_child(item)
	item.position = HINGE + Vector3(0, 0.12 if c["kind"] != "crab" else 0.1, 1.0)
	var full := item.scale
	item.scale = Vector3.ONE * 0.01
	create_tween().tween_property(item, "scale", full, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c["item"] = item
	sfx("bubbles", 80)


func _crab() -> Node3D:
	var root := Node3D.new()
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.82, 0.24, 0.12)
	shell.roughness = 0.35
	shell.clearcoat_enabled = true
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color(0.95, 0.78, 0.62)
	pale.roughness = 0.5
	var tipm := StandardMaterial3D.new()
	tipm.albedo_color = Color(0.15, 0.08, 0.06)
	tipm.roughness = 0.3
	# 등딱지: 납작한 타원 + 앞쪽 톱니 · 아래 연한 배
	var body := SphereMesh.new()
	body.radius = 0.34
	body.height = 0.3
	add_mesh(body, shell, Vector3(0, 0.02, 0), Basis(), root).scale = Vector3(1.3, 0.75, 1.0)
	add_mesh(body, pale, Vector3(0, -0.04, 0), Basis(), root).scale = Vector3(1.15, 0.45, 0.88)
	for k in 5:
		var t := CylinderMesh.new()
		t.top_radius = 0.0
		t.bottom_radius = 0.035
		t.height = 0.07
		t.radial_segments = 5
		var ax := lerpf(-0.9, 0.9, k / 4.0)
		add_mesh(t, shell, Vector3(sin(ax) * 0.4, 0.06, cos(ax) * 0.3), Basis(Vector3(1, 0, 0), PI / 2) * Basis(Vector3(0, 0, 1), -ax), root)
	var seg := func(a: Vector3, b: Vector3, r: float, m: Material) -> void:
		var d := b - a
		var c := CylinderMesh.new()
		c.top_radius = r * 0.8
		c.bottom_radius = r
		c.height = d.length()
		c.radial_segments = 6
		var y := d.normalized()
		var x := y.cross(Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)).normalized()
		add_mesh(c, m, (a + b) * 0.5, Basis(x, y, x.cross(y)), root)
	for sd: float in [-1.0, 1.0]:
		# 다리 3쌍 (무릎에서 꺾여 바닥을 짚음)
		for k in 3:
			var z := 0.05 - k * 0.14
			var hip := Vector3(sd * 0.36, 0.0, z)
			var knee := Vector3(sd * 0.62, 0.14, z - 0.04)
			var foot := Vector3(sd * 0.78, -0.12, z - 0.08)
			seg.call(hip, knee, 0.04, shell)
			seg.call(knee, foot, 0.032, shell)
		# 집게: 팔 두 마디 + 큰 집게 몸 + 위아래 집게발
		var sh := Vector3(sd * 0.3, 0.02, 0.24)
		var el := Vector3(sd * 0.5, 0.12, 0.42)
		var wr := Vector3(sd * 0.36, 0.14, 0.62)
		seg.call(sh, el, 0.05, shell)
		seg.call(el, wr, 0.06, shell)
		var palm := SphereMesh.new()
		palm.radius = 0.12
		palm.height = 0.2
		add_mesh(palm, shell, wr, Basis(Vector3.UP, sd * 0.4), root).scale = Vector3(0.9, 0.8, 1.4)
		seg.call(wr + Vector3(0, 0.03, 0.1), wr + Vector3(-sd * 0.06, 0.06, 0.28), 0.035, tipm)
		seg.call(wr + Vector3(0, -0.03, 0.1), wr + Vector3(-sd * 0.04, -0.02, 0.26), 0.03, tipm)
		# 자루 눈
		seg.call(Vector3(sd * 0.08, 0.1, 0.24), Vector3(sd * 0.1, 0.24, 0.28), 0.018, shell)
		var eye := SphereMesh.new()
		eye.radius = 0.04
		eye.height = 0.08
		add_mesh(eye, tipm, Vector3(sd * 0.1, 0.26, 0.28), Basis(), root)
	return root


func _close(c: Dictionary, _why: String) -> void:
	c["state"] = "closing"
	var seq := int(c.get("seq", 0))
	var lid: Node3D = c["lid"]
	var t := create_tween()
	t.tween_property(lid, "rotation:x", 0.0, 0.1)
	t.tween_callback(func() -> void:
		if int(c.get("seq", 0)) != seq:
			return   # 그새 다시 열렸음 (온라인에서 신호가 겹칠 때)
		if c["item"] and is_instance_valid(c["item"]):
			(c["item"] as Node3D).queue_free()
		c["item"] = null
		c["state"] = "closed")


func _close_idx(k: int) -> void:
	var c: Dictionary = _clams[k]
	if c["state"] == "open":
		_close(c, "")


## 누름 (방장 PC 가 판정 → 모두에게 결과)
func _click(s: int, idx: int) -> void:
	if float(_stun[s]) > 0.0 or idx < 0 or idx >= _clams.size():
		return
	var c: Dictionary = _clams[idx]
	if c["state"] != "open":
		return
	net_call("_take_do", [s, idx])


func _net_input(slot: int, action: String, args: Array) -> void:
	if action == "click" and playing and args.size() > 0:
		_click(slot, int(args[0]))


func _take_do(s: int, idx: int) -> void:
	var c: Dictionary = _clams[idx]
	if c["state"] != "open" or not (c["item"] and is_instance_valid(c["item"])):
		return
	var p := player_by_slot(s)
	var at: Vector3 = (c["pos"] as Vector3) + Vector3(0, 1.4, 0)
	if c["kind"] == "crab":
		scores[s] = int(scores[s]) - 2
		_stun[s] = 0.8
		sfx("remove")
		float_at(at, "-2", Color(1.0, 0.4, 0.35), 46)
		if is_local(p):
			shake(0.35)
		var item: Node3D = c["item"]
		var tw := create_tween()
		var y0 := item.position.y
		tw.tween_property(item, "position:y", y0 + 0.3, 0.08)
		tw.tween_property(item, "position:y", y0, 0.12)
		c["state"] = "taken"
		get_tree().create_timer(0.3).timeout.connect(func() -> void: _close(c, ""))
	else:
		var pts := 3 if c["kind"] == "gold" else 1
		scores[s] = int(scores[s]) + pts
		sfx("coins" if pts > 1 else "add", 40)
		float_at(at, "+%d" % pts, GOLD if pts > 1 else Color(p["color"]).lightened(0.3), 50 if pts > 1 else 40)
		c["state"] = "taken"
		var item: Node3D = c["item"]
		var tw := create_tween()
		tw.tween_property(item, "position:y", 2.5, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(item, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(func() -> void: _close(c, ""))


func _clam_under_mouse() -> int:
	var m := mouse_vp()
	var best := -1
	var bd := 110.0 * (float(vp.size.y) / 1080.0)
	for k in _clams.size():
		var sp := cam.unproject_position((_clams[k]["pos"] as Vector3) + Vector3(0, 0.3, 0))
		var d := sp.distance_to(m)
		if d < bd:
			bd = d
			best = k
	return best


func _gui_input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var k := _clam_under_mouse()
	if k >= 0:
		net_input("click", [k])


## CPU: 반응 시간 뒤 클릭 (실력이 높을수록 빠르고, 게는 잘 알아봄)
func _think(delta: float) -> void:
	var order := players.duplicate()
	order.shuffle()
	for p in order:
		if is_human(p):
			continue
		var s := int(p["slot"])
		var a: Dictionary = _ai[s]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) > 0.0:
			continue
		a["t"] = rng.randf_range(0.05, 0.12)
		var sk := skill(p)
		var react := lerpf(0.55, 0.28, sk / 2.0)
		for k in _clams.size():
			var c: Dictionary = _clams[k]
			# 조개마다 · 사람마다 반응 속도가 다름 (늘 같은 사람이 먼저 누르지 않게)
			var jit := 0.8 + 0.6 * fposmod(sin(float(k) * 12.9898 + float(s) * 78.233 + float(c["seq"]) * 3.7) * 43758.5453, 1.0)
			if c["state"] != "open" or float(c["t"]) < react * jit:
				continue
			if c["kind"] == "crab" and rng.randf() > lerpf(0.35, 0.08, sk / 2.0):
				continue
			_click(s, k)
			a["t"] = react * 0.6
			break


func _score_text(p: Dictionary) -> String:
	return str(int(scores[int(p["slot"])]))
