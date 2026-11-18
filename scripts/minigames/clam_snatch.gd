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
	title = "CLAM SNATCH"
	how_to = "Giant clams snap open with pearls inside - click one first to grab it! Golden pearls are worth 3. But if a crab is hiding inside, you lose 2 points!"
	goal = "Most pearls wins!"
	controls = "MOUSE"
	duration = 30.0


func _build_stage() -> void:
	env_underwater()
	env.ambient_light_energy = 0.5
	env.tonemap_exposure = 0.82
	env.background_color = Color(0.02, 0.15, 0.21)
	env.fog_light_color = Color(0.03, 0.2, 0.26)
	env.fog_density = 0.03
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


## 큰 조개: 골이 진 두 껍데기 (아래는 고정, 위는 뒤 경첩으로 열림) + 안쪽 진주빛 살
func _make_clam(p: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = rng.randf_range(-0.2, 0.2)
	world3.add_child(root)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color.WHITE
	shell.vertex_color_use_as_albedo = true
	shell.roughness = 0.6
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.86, 0.5, 0.58)
	inner.roughness = 0.2
	inner.metallic = 0.3
	inner.clearcoat_enabled = true
	var bottom := _shell_mesh(false)
	add_mesh(bottom, shell, Vector3(0, 0.25, -0.95), Basis(), root)
	var flesh := SphereMesh.new()
	flesh.radius = 0.68
	flesh.height = 0.16
	add_mesh(flesh, inner, Vector3(0, 0.25, 0.1), Basis(), root).scale = Vector3(1.0, 1.0, 1.15)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.27, -0.95)
	root.add_child(lid)
	add_mesh(_shell_mesh(true), shell, Vector3.ZERO, Basis(), lid)
	return {"root": root, "lid": lid, "pos": p, "state": "closed", "t": 0.0, "kind": "", "item": null, "open_for": 0.0, "seq": 0}


## 부채꼴 골이 진 반쪽 껍데기
func _shell_mesh(top: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 24
	var nv := 10
	var R := 1.95
	var pts := []
	for j in nv + 1:
		var v := float(j) / nv
		var row := []
		for i in nu + 1:
			var u := float(i) / nu
			var a := lerpf(-0.95, 0.95, u)
			var r := R * v
			var ribs := 1.0 + 0.06 * absf(sin(u * PI * 9.0)) * v
			var x := sin(a) * r * ribs
			var z := cos(a) * r * ribs
			var bulge := 0.5 * pow(sin(v * PI * 0.92), 0.8) * (0.55 + 0.45 * cos(a * 1.6)) + 0.04 * absf(sin(u * PI * 9.0)) * v
			var y := bulge * (1.0 if top else -0.55)
			# 골은 진하고 마루는 밝게, 가장자리로 갈수록 갈색 띠 (실제 대왕조개 무늬)
			var rib := absf(sin(u * PI * 9.0))
			var band := 0.5 + 0.5 * sin(v * 22.0)
			var col := Color(0.62, 0.5, 0.42).lerp(Color(0.86, 0.8, 0.72), rib * 0.7).lerp(Color(0.42, 0.3, 0.25), band * 0.25 * v)
			row.append([Vector3(x, y, z), col])
		pts.append(row)
	for j in nv:
		for i in nu:
			var a: Array = pts[j][i]
			var b: Array = pts[j][i + 1]
			var c: Array = pts[j + 1][i]
			var d: Array = pts[j + 1][i + 1]
			for v in ([a, c, b, b, c, d] if top else [a, b, c, b, d, c]):
				st.set_color(v[1])
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
	if _spawn <= 0.0:
		_open_one(pr)
		_spawn = lerpf(0.75, 0.3, pr) * rng.randf_range(0.8, 1.2)
	for c in _clams:
		if c["state"] == "open":
			c["t"] = float(c["t"]) + delta
			if float(c["t"]) >= float(c["open_for"]):
				_close(c, "")
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
	c["kind"] = "crab" if roll < crab_p else ("gold" if roll < crab_p + 0.12 else "pearl")
	c["state"] = "open"
	c["t"] = 0.0
	c["seq"] = int(c.get("seq", 0)) + 1
	c["open_for"] = lerpf(1.6, 0.75, pr) * rng.randf_range(0.85, 1.15)
	var lid: Node3D = c["lid"]
	create_tween().tween_property(lid, "rotation:x", -0.85, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var root: Node3D = c["root"]
	var item: Node3D
	if c["kind"] == "crab":
		item = _crab()
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
	item.position = Vector3(0, 0.55, 0.05)
	item.scale = Vector3.ONE * 0.01
	create_tween().tween_property(item, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c["item"] = item
	sfx("bubbles", 80)


func _crab() -> Node3D:
	var root := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.25, 0.15)
	red.roughness = 0.4
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 0.36
	add_mesh(body, red, Vector3.ZERO, Basis(), root).scale = Vector3(1.3, 0.7, 1.0)
	for sd: float in [-1.0, 1.0]:
		var claw := SphereMesh.new()
		claw.radius = 0.16
		claw.height = 0.26
		add_mesh(claw, red, Vector3(sd * 0.42, 0.18, 0.22), Basis(Vector3(0, 0, 1), sd * 0.5), root).scale = Vector3(1.0, 0.7, 1.3)
		var eye := SphereMesh.new()
		eye.radius = 0.05
		eye.height = 0.1
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.02, 0.02, 0.02)
		add_mesh(eye, em, Vector3(sd * 0.1, 0.24, 0.2), Basis(), root)
	return root


func _close(c: Dictionary, _why: String) -> void:
	c["state"] = "closing"
	var lid: Node3D = c["lid"]
	var t := create_tween()
	t.tween_property(lid, "rotation:x", 0.0, 0.1)
	t.tween_callback(func() -> void:
		if c["item"] and is_instance_valid(c["item"]):
			(c["item"] as Node3D).queue_free()
		c["item"] = null
		c["state"] = "closed")


func _click(s: int, idx: int) -> void:
	if float(_stun[s]) > 0.0 or idx < 0:
		return
	var c: Dictionary = _clams[idx]
	if c["state"] != "open":
		return
	var p := player_by_slot(s)
	var at: Vector3 = (c["pos"] as Vector3) + Vector3(0, 1.4, 0)
	if c["kind"] == "crab":
		scores[s] = int(scores[s]) - 2
		_stun[s] = 0.8
		sfx("remove")
		float_at(at, "-2", Color(1.0, 0.4, 0.35), 46)
		if is_human(p):
			shake(0.35)
		var item: Node3D = c["item"]
		var tw := create_tween()
		tw.tween_property(item, "position:y", 0.8, 0.08)
		tw.tween_property(item, "position:y", 0.55, 0.12)
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
	for p in players:
		if is_human(p):
			_click(int(p["slot"]), _clam_under_mouse())


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
