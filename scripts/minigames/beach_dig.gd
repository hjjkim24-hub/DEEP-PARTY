extends "res://scripts/minigames/minigame_3d.gd"
## 모래사장 보물찾기 (WASD 이동 · 스페이스 = 파기): 무인도 해변에서 금속탐지기로 모래 속 보물을 찾아 파내기.
## 탐지기는 파묻힌 쇠붙이에 가까울수록 "삑…삑삑삑" 빨라짐 (내 것만 들림) + 손잡이 불빛 · 모래 위 신호 고리.
## 스페이스 = 탐지기 코일 아래를 팜 (파는 동안 못 움직임, 큰 보물일수록 오래). 금화 주머니 1점 · 보석함 2점 · 보물상자 3점.
## 녹슨 깡통(0점)도 쇠라서 똑같이 삑삑댐. 빈 곳을 파면 가끔 게가 튀어나와 꼬집음 (잠깐 휘청).
## 누가 파는 중이어도 다른 사람이 먼저 파내면 뺏김. 파낸 만큼 새 보물이 다른 곳에 묻힘. 60초 동안 점수가 가장 높은 사람이 승리.

const AX := 10.0                 ## 다닐 수 있는 곳 (좌우 반폭)
const AZ0 := -6.0                ## 뒤 (숲 앞)
const AZ1 := 5.6                 ## 앞 (젖은 모래 앞)
const SHORE_Z := 6.6
const DET_RANGE := 5.5
const DIG_R := 0.9
const COIL := 0.68               ## 몸에서 탐지기 코일까지
const WALK := 4.4
const N_BURIED := 7
const KINDS := {
	"coins": {"val": 1, "dig": 1.4, "w": 45},
	"jewels": {"val": 2, "dig": 1.9, "w": 25},
	"chest": {"val": 3, "dig": 2.6, "w": 12},
	"can": {"val": 0, "dig": 1.4, "w": 18},
}

var _buried: Array = []          ## {id, kind, pos Vector2}
var _holes: Array = []           ## Vector2
var _dig := {}                   ## slot → {t, dur, at Vector2}
var _stun := {}
var _next_id := 0
var _elapsed := 0.0
var _ai := {}
var _det := {}                   ## slot → {root, led_mat, spade, phase}
var _beep_t := 0.0
var _rings: Array = []           ## 신호 고리 {node, t}
var _sand_tex: Texture2D
var _hole_mat: StandardMaterial3D
var _hole_in_mat: StandardMaterial3D
var _hole_tex: GradientTexture2D
var _junk: Array = []            ## 파낸 깡통 (모래 위에 남음)
var _crabs: Array = []           ## {node, vel, t}
var _leaf_mat: StandardMaterial3D
var _trunk_mat: ShaderMaterial


func _init() -> void:
	title = "BEACH DIG"
	how_to = "Find treasure buried in the sand with your metal detector! The closer you get, the faster it beeps. SPACE digs under the detector - bigger treasure takes longer. Coin pouch 1, jewel box 2, treasure chest 3. Rusty cans beep too, and an empty hole may hide a pinching crab! Others can dig up your find first."
	goal = "Dig up the most treasure!"
	controls = "KEYS_DIG"
	duration = 60.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.66)   # 그늘이 하늘빛으로 너무 파래지지 않게
	env.ambient_light_energy = 0.55
	env.fog_density = 0.0028
	var sea := ocean(-0.62, 260.0, 0.0)
	var sm: ShaderMaterial = sea.material_override
	sm.set_shader_parameter("amp", 0.16)
	sm.set_shader_parameter("edge_foam", 1.4)
	sea.position.z = 0.0
	sky_clouds(14, 190.0, 30.0)
	gulls(3, Vector3(0, 0, -6), 18.0, 10.0, 41)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 32.0
	island(Vector3(-110, -1.5, 150), 22.0, 13.0, 8)
	cam.fov = 46.0
	var xf := Transform3D(Basis(), Vector3(0, 13.2, 11.6))
	xf = xf.looking_at(Vector3(0, 0, 0.6), Vector3.UP)
	cam.transform = xf
	cam_base = xf
	_sand_tex = kit._mip_tex(load("res://textures/seabed/sand_albedo.png"))
	# 모래밭 (놀이 구역 + 바다로 내려가는 경사 + 뒤 모래언덕)
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 44)
	pm.subdivide_width = 150
	pm.subdivide_depth = 110
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/beach_sand.gdshader")
	bm.set_shader_parameter("sand_albedo", _sand_tex)
	bm.set_shader_parameter("sand_normal", kit._mip_tex(load("res://textures/seabed/sand_normal.png")))
	bm.set_shader_parameter("foam_tex", load("res://textures/ocean/foam.png"))
	bm.set_shader_parameter("shore_z", SHORE_Z)
	add_mesh(pm, bm, Vector3(0, 0, 2.0))
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.albedo_texture = _sand_tex
	_hole_mat.albedo_color = Color(0.74, 0.61, 0.44)   # 퍼 올린 모래 (살짝 축축)
	_hole_mat.uv1_triplanar = true
	_hole_mat.uv1_scale = Vector3(0.21, 0.21, 0.21)
	_hole_mat.roughness = 0.95
	_hole_in_mat = _hole_mat.duplicate()
	_hole_in_mat.albedo_color = Color(0.5, 0.42, 0.32)
	_hole_in_mat.roughness = 0.5
	_build_decor()


# ── 해변 꾸미기 ─────────────────────────────────────────────
func _build_decor() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 17
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_texture = _leaf_tex()
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.5
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 0.75
	_leaf_mat.backlight_enabled = true
	_leaf_mat.backlight = Color(0.25, 0.35, 0.1)
	_trunk_mat = ShaderMaterial.new()
	_trunk_mat.shader = _trunk_shader()
	# 뒤쪽 야자수 숲 (안쪽으로 기울어 바다를 향함) + 양옆 몇 그루
	var spots := []
	var x := -15.0
	while x < 15.5:
		spots.append(Vector3(x + rr.randf_range(-0.8, 0.8), 0.0, AZ0 - 2.2 - rr.randf_range(0.0, 3.5)))
		x += rr.randf_range(2.4, 3.6)
	spots.append(Vector3(-AX - 2.4, 0, -1.5))
	spots.append(Vector3(AX + 2.6, 0, 0.8))
	spots.append(Vector3(-AX - 3.4, 0, 3.6))
	for p: Vector3 in spots:
		var h := rr.randf_range(4.8, 7.2)
		var lean := Vector3(-p.x * 0.04 + rr.randf_range(-0.25, 0.25), 0, rr.randf_range(0.25, 0.6)).normalized()
		_palm(p + Vector3(0, _ground(p), 0), h, lean, rr)
	# 낮은 덤불 (야자 새순) · 바위
	for k in 16:
		var p := Vector3(rr.randf_range(-16, 16), 0, AZ0 - rr.randf_range(0.8, 4.5))
		if absf(p.x) < AX + 1.0 and p.z > AZ0 - 1.0:
			continue
		_bush(p + Vector3(0, _ground(p), 0), rr)
	var rock := stone_mat(Color(0.45, 0.42, 0.38), "stone", 0.2)
	for k in 7:
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := Vector3(side * rr.randf_range(AX + 1.2, AX + 4.5), 0, rr.randf_range(-6.0, 7.5))
		var s := SphereMesh.new()
		var r := rr.randf_range(0.5, 1.3)
		s.radius = r
		s.height = r * 1.6
		var mi := add_mesh(s, rock, p + Vector3(0, _ground(p) + r * 0.2, 0), Basis(Vector3.UP, rr.randf() * TAU))
		mi.scale = Vector3(1.0, rr.randf_range(0.6, 0.9), rr.randf_range(0.8, 1.2))
	# 떠밀려 온 나무 · 반쯤 묻힌 낡은 쪽배 · 조개 · 불가사리
	var drift := wood_mat(Color(0.62, 0.58, 0.52), Vector3(0, 0, 1), 0.0)
	var dl := CylinderMesh.new()
	dl.top_radius = 0.13
	dl.bottom_radius = 0.2
	dl.height = 3.2
	add_mesh(dl, drift, Vector3(-AX - 0.8, 0.08, 6.2), Basis(Vector3.UP, 0.9) * Basis(Vector3.RIGHT, PI / 2))
	add_mesh(dl, drift, Vector3(AX + 1.4, 0.1, -4.6), Basis(Vector3.UP, -0.5) * Basis(Vector3.RIGHT, PI / 2))
	var boat := sailboat(Color(0.8, 0.76, 0.66), world3, 2.4, 0.95, 0.5)
	boat.scale = Vector3.ONE * 1.6
	boat.position = Vector3(AX + 2.3, -0.25, 4.2)
	boat.rotation = Vector3(0.0, 2.3, 0.32)
	for c in boat.get_children():
		if c is Node3D and (c as Node3D).position.y > 0.6:
			(c as Node3D).visible = false   # 돛 · 돛대는 없음 (버려진 쪽배)
	var shell := std_mat(Color(0.95, 0.88, 0.8), 0.5)
	var star := std_mat(Color(0.88, 0.45, 0.25), 0.8)
	for k in 12:
		var p := Vector3(rr.randf_range(-AX - 2.0, AX + 2.0), 0.0, rr.randf_range(3.0, 7.5))
		if rr.randf() < 0.7:
			var sp := SphereMesh.new()
			sp.radius = rr.randf_range(0.05, 0.09)
			sp.height = sp.radius
			add_mesh(sp, shell, p + Vector3(0, _ground(p) + 0.01, 0), Basis(Vector3.UP, rr.randf() * TAU)).scale = Vector3(1.0, 1.0, 1.3)
		else:
			var st := Node3D.new()
			st.position = p + Vector3(0, _ground(p) + 0.015, 0)
			st.rotation.y = rr.randf() * TAU
			world3.add_child(st)
			for a in 5:
				var arm := BoxMesh.new()
				arm.size = Vector3(0.05, 0.025, 0.16)
				add_mesh(arm, star, Vector3(sin(a * TAU / 5) * 0.07, 0, cos(a * TAU / 5) * 0.07), Basis(Vector3.UP, a * TAU / 5), st)
	_no_shadow_small(world3)
	# 바다 위로 보이는 먼 바위섬 두어 개
	for k in 2:
		var s := SphereMesh.new()
		s.radius = 3.0
		s.height = 4.0
		add_mesh(s, rock, Vector3(-30 + k * 55, -0.8, 38 + k * 10), Basis()).scale = Vector3(1.6, 0.8, 1.0)


func _ground(p: Vector3) -> float:
	# beach_sand.gdshader 의 높이와 대략 같게 (꾸밈 놓을 높이)
	var down := -smoothstep(4.8, 10.0, p.z) * 1.7
	var dune := smoothstep(-6.8, -11.0, p.z) * 1.2
	return down + dune


## 야자수 잎 무늬: 가운데 잎맥에서 비스듬히 갈라진 작은 잎 (사이는 뚫림), 끝으로 갈수록 좁고 누렇게
func _leaf_tex() -> ImageTexture:
	var W := 64
	var H := 256
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		var v := float(y) / H
		var width := sin(v * PI * 0.92 + 0.1) * 0.5
		for x in W:
			var u := (float(x) / W - 0.5) * 2.0
			var a := 0.0
			if absf(u) < width:
				# 비스듬한 작은 잎 (잎 사이 틈)
				var k := fmod(v * 46.0 + absf(u) * 2.2, 1.0)
				a = 1.0 if k < 0.8 or absf(u) < 0.05 else 0.0
				if absf(u) > width * 0.92 and fmod(v * 46.0, 1.0) > 0.5:
					a = 0.0
			var g := Color(0.22, 0.42, 0.13).lerp(Color(0.5, 0.55, 0.2), v * 0.7)
			if absf(u) < 0.05:
				g = Color(0.55, 0.55, 0.3)
			g = g.darkened((1.0 - absf(u)) * 0.12)
			img.set_pixel(x, y, Color(g.r, g.g, g.b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _trunk_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
// 야자 줄기: 잎이 떨어진 자리마다 고리 마디 + 세로 섬유 결
varying vec3 lp;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 x) { vec2 i = floor(x); vec2 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	float ring = fract(UV.x * 5.5 + n(vec2(UV.y * 6.0, UV.x * 2.0)) * 0.15);
	float band = smoothstep(0.0, 0.12, ring) * smoothstep(1.0, 0.72, ring);
	float fib = n(vec2(UV.y * 40.0, UV.x * 3.0));
	vec3 c = mix(vec3(0.32, 0.26, 0.19), vec3(0.58, 0.5, 0.4), band * 0.8 + fib * 0.2);
	c *= mix(0.9, 1.05, n(vec2(UV.x * 0.8, UV.y * 2.0)));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	NORMAL = normalize(NORMAL + (TANGENT * (ring < 0.12 ? -0.4 : 0.0)));
}
"""
	return sh


func _tube(pts: Array, radii: Array, seg: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var acc := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var fwd: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := fwd.cross(Vector3.FORWARD if absf(fwd.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(fwd).normalized()
		if i > 0:
			acc += p.distance_to(pts[i - 1])
		for j in seg + 1:
			var a := float(j) / seg * TAU
			var d := side * cos(a) + up * sin(a)
			v.append(p + d * float(radii[i]))
			nrm.append(d)
			tan.append_array([fwd.x, fwd.y, fwd.z, 1.0])
			uv.append(Vector2(acc, float(j) / seg))
	for i in pts.size() - 1:
		for j in seg:
			var a0 := i * (seg + 1) + j
			var b0 := a0 + seg + 1
			idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## 야자수 잎 하나: 줄기 끝에서 뻗어 나가 아치를 그리며 처지는 띠 (가운데가 살짝 접힘). 나무 한 그루의 잎은 한 덩어리로 모아 그림
func _frond(origin: Vector3, dir: Vector3, length: float, droop: float, st: SurfaceTool) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var n := 12
	var width := length * 0.36
	var rows := []
	for i in n + 1:
		var t := float(i) / n
		var p := origin + dir * length * t + Vector3(0, length * (0.32 * t - droop * t * t), 0)
		var fold := 0.12 * width
		var row := []
		for k in 3:
			var u := float(k) / 2.0 * 2.0 - 1.0
			row.append([p + side * u * width * 0.5 + Vector3(0, -absf(u) * fold + (0.0 if k != 1 else 0.02), 0), Vector2(float(k) / 2.0, t)])
		rows.append(row)
	for i in n:
		for k in 2:
			for q: Array in [[i, k], [i + 1, k], [i, k + 1], [i, k + 1], [i + 1, k], [i + 1, k + 1]]:
				var vv: Array = rows[int(q[0])][int(q[1])]
				st.set_normal(Vector3.UP)
				st.set_uv(vv[1])
				st.add_vertex(vv[0])


func _leaf_mesh(st: SurfaceTool, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _leaf_mat
	parent.add_child(mi)


func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _palm(base: Vector3, h: float, lean: Vector3, rr: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	world3.add_child(root)
	var pts := []
	var rad := []
	var n := 14
	for i in n:
		var t := float(i) / (n - 1)
		# 밑은 곧게 서다 위로 갈수록 바다 쪽으로 휨
		pts.append(base + Vector3(0, h * t, 0) + lean * h * 0.3 * t * t)
		rad.append(lerpf(0.21, 0.13, t) * (1.15 if i == 0 else 1.0))
	var tm := MeshInstance3D.new()
	tm.mesh = _tube(pts, rad, 10)
	tm.material_override = _trunk_mat
	root.add_child(tm)
	var top: Vector3 = pts[n - 1]
	var nf := rr.randi_range(9, 12)
	var st := _new_st()
	for k in nf:
		var a := float(k) / nf * TAU + rr.randf_range(-0.2, 0.2)
		var up := rr.randf_range(-0.1, 0.45)
		var d := Vector3(cos(a), up, sin(a)).normalized()
		_frond(top, d, rr.randf_range(2.3, 3.2), rr.randf_range(0.7, 1.1), st)
	# 마른 잎 두엇 (축 처짐)
	for k in 2:
		var a := rr.randf() * TAU
		_frond(top + Vector3(0, -0.15, 0), Vector3(cos(a), -0.7, sin(a)).normalized(), 1.8, 0.3, st)
	_leaf_mesh(st, root)
	# 코코넛
	var nut := std_mat(Color(0.33, 0.3, 0.14), 0.7)
	for k in rr.randi_range(3, 5):
		var a := rr.randf() * TAU
		var s := SphereMesh.new()
		s.radius = 0.13
		s.height = 0.26
		add_mesh(s, nut, top + Vector3(cos(a) * 0.18, -0.2 - rr.randf() * 0.1, sin(a) * 0.18), Basis(), root)


func _bush(p: Vector3, rr: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	world3.add_child(root)
	var st := _new_st()
	for k in rr.randi_range(6, 9):
		var a := rr.randf() * TAU
		_frond(p + Vector3(0, 0.05, 0), Vector3(cos(a), rr.randf_range(0.6, 1.2), sin(a)).normalized(), rr.randf_range(1.0, 1.6), 1.1, st)
	_leaf_mesh(st, root)


# ── 탐지기 · 삽 (각 말에 달림) ──────────────────────────────
func _make_detector(pawn: Node3D) -> Dictionary:
	var root := Node3D.new()
	pawn.add_child(root)
	var metal := std_mat(Color(0.7, 0.72, 0.75), 0.35, 0.8)
	var black := std_mat(Color(0.08, 0.08, 0.09), 0.6)
	var yellow := std_mat(Color(0.95, 0.75, 0.15), 0.5)
	# 손잡이 → 코일 (말 기준 좌표, 앞 = +z)
	var a := Vector3(0.2, 0.55, 0.12)
	var b := Vector3(0.12, 0.06, COIL / PAWN_SCALE)
	var d := b - a
	var rod := CylinderMesh.new()
	rod.top_radius = 0.012
	rod.bottom_radius = 0.012
	rod.height = d.length()
	add_mesh(rod, metal, (a + b) * 0.5, Basis(Quaternion(Vector3.UP, d.normalized())), root)
	var boxm := BoxMesh.new()
	boxm.size = Vector3(0.06, 0.05, 0.1)
	var ctrl := add_mesh(boxm, yellow, a + d * 0.22, Basis(Quaternion(Vector3.UP, d.normalized())), root)
	var led_m := StandardMaterial3D.new()
	led_m.albedo_color = Color(0.2, 0.05, 0.03)
	led_m.emission_enabled = true
	led_m.emission = Color(1.0, 0.2, 0.1)
	led_m.emission_energy_multiplier = 0.0
	var led := SphereMesh.new()
	led.radius = 0.014
	led.height = 0.028
	add_mesh(led, led_m, ctrl.position + Vector3(0, 0.032, 0), Basis(), root)
	var coil := TorusMesh.new()
	coil.inner_radius = 0.085
	coil.outer_radius = 0.11
	add_mesh(coil, black, b, Basis(), root)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.09
	disc.bottom_radius = 0.09
	disc.height = 0.01
	add_mesh(disc, std_mat(Color(0.2, 0.2, 0.22), 0.5), b, Basis(), root)
	# 삽 (팔 때만 보임)
	var spade := Node3D.new()
	spade.position = Vector3(-0.05, 0.45, 0.25)
	spade.visible = false
	pawn.add_child(spade)
	var wood := std_mat(Color(0.5, 0.36, 0.22), 0.8)
	var sh := CylinderMesh.new()
	sh.top_radius = 0.014
	sh.bottom_radius = 0.014
	sh.height = 0.55
	add_mesh(sh, wood, Vector3(0, 0, 0), Basis(), spade)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.13, 0.17, 0.012)
	add_mesh(blade, metal, Vector3(0, -0.34, 0), Basis(), spade)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"root": root, "led": led_m, "spade": spade, "flash": 0.0, "bt": 0.0}


# ── 묻힌 것 · 파낸 것 모양 ──────────────────────────────────
func _item_node(kind: String, seed_: int) -> Node3D:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_ * 7 + 3
	var root := Node3D.new()
	world3.add_child(root)
	var gold := std_mat(Color(0.95, 0.74, 0.3), 0.25, 0.95)
	match kind:
		"coins":
			var leather := std_mat(Color(0.42, 0.24, 0.14), 0.85)
			var s := SphereMesh.new()
			s.radius = 0.17
			s.height = 0.3
			add_mesh(s, leather, Vector3(0, 0.12, 0), Basis(), root).scale = Vector3(1, 0.9, 1)
			var tie := TorusMesh.new()
			tie.inner_radius = 0.04
			tie.outer_radius = 0.06
			add_mesh(tie, std_mat(Color(0.6, 0.5, 0.3), 0.9), Vector3(0, 0.26, 0), Basis(), root)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.012
			for k in 6:
				add_mesh(cm, gold, Vector3(rr.randf_range(-0.22, 0.22), 0.01 + k * 0.004, rr.randf_range(-0.22, 0.22)), Basis(Vector3.RIGHT, rr.randf_range(-0.3, 0.3)), root)
		"jewels":
			var wood := wood_mat(Color(0.35, 0.18, 0.1), Vector3(1, 0, 0), 0.0)
			box(Vector3(0.36, 0.2, 0.26), wood, Vector3(0, 0.1, 0), Basis(), root)
			box(Vector3(0.38, 0.03, 0.28), gold, Vector3(0, 0.21, 0), Basis(), root)
			for k in 4:
				var g := SphereMesh.new()
				g.radius = 0.04
				g.height = 0.08
				var gm := std_mat([Color(0.9, 0.1, 0.2), Color(0.1, 0.6, 0.95), Color(0.15, 0.85, 0.35), Color(0.7, 0.2, 0.9)][k], 0.1, 0.3)
				gm.emission_enabled = true
				gm.emission = gm.albedo_color * 0.4
				add_mesh(g, gm, Vector3(-0.12 + k * 0.08, 0.25, rr.randf_range(-0.05, 0.05)), Basis(), root)
		"chest":
			treasure_chest(0.62, 0.4, 0.42, root)
		"can":
			var rust := std_mat(Color(0.45, 0.24, 0.12), 0.95, 0.3)
			var c := CylinderMesh.new()
			c.top_radius = 0.07
			c.bottom_radius = 0.075
			c.height = 0.2
			var mi := add_mesh(c, rust, Vector3(0, 0.1, 0), Basis(Vector3.BACK, 1.3) * Basis(Vector3.RIGHT, 0.2), root)
			mi.scale = Vector3(1.4, 1.4, 1.1)   # 찌그러짐
	return root


func _crab_node() -> Node3D:
	var root := Node3D.new()
	world3.add_child(root)
	var shell := std_mat(Color(0.85, 0.32, 0.12), 0.5)
	var dark := std_mat(Color(0.55, 0.18, 0.08), 0.6)
	var b := SphereMesh.new()
	b.radius = 0.16
	b.height = 0.18
	add_mesh(b, shell, Vector3(0, 0.1, 0), Basis(), root).scale = Vector3(1.3, 0.6, 1.0)
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			var leg := BoxMesh.new()
			leg.size = Vector3(0.18, 0.02, 0.02)
			add_mesh(leg, dark, Vector3(sx * 0.2, 0.06, -0.06 + k * 0.06), Basis(Vector3.BACK, sx * -0.5), root)
		var claw := SphereMesh.new()
		claw.radius = 0.06
		claw.height = 0.1
		add_mesh(claw, shell, Vector3(sx * 0.17, 0.12, 0.17), Basis(), root).scale = Vector3(1.0, 0.7, 1.4)
		var eye := SphereMesh.new()
		eye.radius = 0.02
		eye.height = 0.04
		add_mesh(eye, std_mat(Color(0.05, 0.05, 0.05), 0.3), Vector3(sx * 0.05, 0.19, 0.1), Basis(), root)
	return root


func _hole(at: Vector2) -> void:
	# 파낸 구덩이: 가운데는 축축하고 어둡게 파인 구멍(그림 판) + 둘레로 퍼 올린 모래 둔덕
	if _hole_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.2, 0.15, 0.1, 1.0))
		g.set_color(1, Color(0.6, 0.5, 0.36, 0.0))   # (점을 더하기 전에 양 끝부터 — 더하면 번호가 바뀜)
		g.add_point(0.45, Color(0.33, 0.26, 0.18, 1.0))
		g.add_point(0.72, Color(0.5, 0.41, 0.29, 0.85))
		_hole_tex = GradientTexture2D.new()
		_hole_tex.gradient = g
		_hole_tex.fill = GradientTexture2D.FILL_RADIAL
		_hole_tex.fill_from = Vector2(0.5, 0.5)
		_hole_tex.fill_to = Vector2(0.5, 0.0)
		_hole_tex.width = 64
		_hole_tex.height = 64
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = _hole_tex
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 0.6
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 0.95)
	q.orientation = PlaneMesh.FACE_Y
	var dmi := add_mesh(q, dm, Vector3(at.x, 0.03, at.y), Basis(Vector3.UP, randf() * TAU))
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.scale = Vector3(1.0, 1.0, randf_range(0.8, 1.0))
	var prof := [Vector2(0.27, 0.0), Vector2(0.35, 0.1), Vector2(0.47, 0.16), Vector2(0.62, 0.11), Vector2(0.86, 0.02), Vector2(0.96, -0.03)]
	var m := add_mesh(lathe_mesh(prof, 20), _hole_mat, Vector3(at.x, 0.0, at.y), Basis(Vector3.UP, randf() * TAU))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(1.0, 1.0, randf_range(0.85, 1.1))
	_holes.append(at)


# ── 시작 ────────────────────────────────────────────────────
func _setup_game() -> void:
	walk_radius = 999.0
	var spots := [Vector2(-6, -3), Vector2(6, 3), Vector2(6, -3), Vector2(-6, 3)]
	for i in players.size():
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var sp: Vector2 = spots[i % 4]
		var w := add_walker(p, Vector3(sp.x, 0, sp.y), WALK)
		w["face"] = atan2(-sp.x, -sp.y)
		_det[s] = _make_detector(w["node"])
		_stun[s] = 0.0
		_ai[s] = {"t": 0.0, "goal": Vector3(sp.x, 0, sp.y), "est": Vector2.ZERO, "est_id": -1, "est_t": 0.0}
		scores[s] = 0


func _start_game() -> void:
	_elapsed = 0.0
	if not is_client():
		for k in N_BURIED:
			_bury_random(k < 2)


## 방장: 아무도 없고 · 다른 보물 · 구덩이와 떨어진 곳에 하나 묻음
func _bury_random(can: bool = false) -> void:
	var kind := "can"
	if not can:
		var tot := 0
		for k in KINDS:
			tot += int(KINDS[k]["w"])
		var r := rng.randi() % tot
		for k in KINDS:
			r -= int(KINDS[k]["w"])
			if r < 0:
				kind = k
				break
	# 깡통은 늘 두 개까지만 (보물이 깡통으로 바뀌어 쌓이지 않게)
	var cans := 0
	for b: Dictionary in _buried:
		if String(b["kind"]) == "can":
			cans += 1
	if kind == "can" and cans >= 2:
		kind = "coins"
	elif kind != "can" and can:
		kind = "can"
	var best := Vector2.ZERO
	var bv := -INF
	for t in 24:
		var c := Vector2(rng.randf_range(-AX + 0.8, AX - 0.8), rng.randf_range(AZ0 + 0.8, AZ1 - 0.6))
		var near := 99.0
		for s in walkers:
			var wp: Vector3 = walkers[s]["pos"]
			near = minf(near, c.distance_to(Vector2(wp.x, wp.z)))
		for b: Dictionary in _buried:
			near = minf(near, c.distance_to(b["pos"]) * 1.2)
		for h: Vector2 in _holes:
			near = minf(near, c.distance_to(h) * 2.0)
		var v := minf(near, 4.0) + rng.randf() * 0.5
		if v > bv:
			bv = v
			best = c
	_next_id += 1
	net_call("_bury", [_next_id, kind, best.x, best.y])


func _bury(id: int, kind: String, x: float, z: float) -> void:
	_buried.append({"id": id, "kind": kind, "pos": Vector2(x, z)})
	_next_id = maxi(_next_id, id)


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
		net_input("dig")


func _net_input(slot: int, action: String, _args: Array) -> void:
	if action == "dig" and playing:
		_try_dig(slot)


func _coil(s: int) -> Vector2:
	var w: Dictionary = walkers[s]
	var p: Vector3 = w["pos"]
	var f := float(w["face"])
	return Vector2(p.x + sin(f) * COIL, p.z + cos(f) * COIL)


func _nearest(at: Vector2, max_d: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for b: Dictionary in _buried:
		var d := at.distance_to(b["pos"])
		if d < bd:
			bd = d
			best = b
	return best


## 방장: 파기 시작 (코일 아래. 거기 묻힌 게 있으면 그만큼 오래)
func _try_dig(s: int) -> void:
	if not walkers.has(s) or _dig.has(s) or float(_stun.get(s, 0.0)) > 0.0:
		return
	var at := _coil(s)
	at.x = clampf(at.x, -AX - 0.3, AX + 0.3)
	at.y = clampf(at.y, AZ0 - 0.3, AZ1 + 0.4)
	var tg := _nearest(at, DIG_R)
	var dur := float(KINDS[tg["kind"]]["dig"]) if not tg.is_empty() else 1.1
	net_call("_dig_start", [s, at.x, at.y, dur])


func _dig_start(s: int, x: float, z: float, dur: float) -> void:
	_dig[s] = {"t": 0.0, "dur": dur, "at": Vector2(x, z), "fx": 0.0}
	if walkers.has(s):
		walkers[s]["speed"] = 0.0
		walkers[s]["target"] = walkers[s]["pos"]
		var w: Dictionary = walkers[s]
		w["face"] = atan2(x - (w["pos"] as Vector3).x, z - (w["pos"] as Vector3).z)
	(_det[s]["spade"] as Node3D).visible = true


## 방장: 다 팠음 → 그 자리에 아직 묻힌 게 있으면 내 것 (누가 먼저 파 갔으면 빈 구덩이). 빈 곳이면 가끔 게
func _dig_done(s: int) -> void:
	var d: Dictionary = _dig[s]
	var at: Vector2 = d["at"]
	var tg := _nearest(at, DIG_R)
	if not tg.is_empty():
		net_call("_dig_end", [s, at.x, at.y, int(tg["id"]), String(tg["kind"]), false])
		_bury_random(false)
	else:
		net_call("_dig_end", [s, at.x, at.y, -1, "", rng.randf() < 0.3])


func _dig_end(s: int, x: float, z: float, id: int, kind: String, crab: bool) -> void:
	_dig.erase(s)
	var at := Vector2(x, z)
	_hole(at)
	if walkers.has(s):
		walkers[s]["speed"] = WALK
	(_det[s]["spade"] as Node3D).visible = false
	if OS.get_environment("MG_DEBUG") != "":
		print("BD dig s=%d kind=%s crab=%s t=%.1f sc=%s" % [s, kind, str(crab), _elapsed, str(scores)])
	if id >= 0:
		for i in range(_buried.size() - 1, -1, -1):
			if int(_buried[i]["id"]) == id:
				_buried.remove_at(i)
		var val := int(KINDS[kind]["val"])
		scores[s] = int(scores.get(s, 0)) + val
		var node := _item_node(kind, id)
		node.position = Vector3(x, -0.15, z)
		if kind == "can":
			# 꽝: 녹슨 깡통이 툭 튀어나와 옆에 떨어짐
			sfx("thud", 40)
			var tw := create_tween()
			tw.tween_property(node, "position", Vector3(x + 0.5, 0.0, z + 0.2), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_junk.append(node)
		else:
			sfx("coins", 60)
			if val >= 3:
				sfx("box_burst", 60)
			var tw := create_tween()
			tw.tween_property(node, "position", Vector3(x, 1.4, z), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(node, "rotation:y", TAU, 0.9)
			tw.tween_interval(0.35)
			if walkers.has(s):
				var pn: Node3D = walkers[s]["node"]
				tw.tween_method(func(f: float) -> void:
					node.position = Vector3(x, 1.4, z).lerp(pn.position + Vector3(0, 0.9, 0), f)
					node.scale = Vector3.ONE * (1.0 - f * 0.8), 0.0, 1.0, 0.3)
			tw.tween_callback(node.queue_free)
			_sparkle(Vector3(x, 0.4, z), val)
	elif crab:
		# 빈 구덩이에서 게가 튀어나와 꼬집고 바다로 도망
		var c := _crab_node()
		c.position = Vector3(x, 0.0, z)
		var to_sea := Vector3(randf_range(-0.4, 0.4), 0, 1.0).normalized()
		_crabs.append({"node": c, "vel": to_sea * 2.4, "t": 0.0})
		_stun[s] = 1.0
		if walkers.has(s):
			walkers[s]["speed"] = 0.0
			var pn: Node3D = walkers[s]["node"]
			var tw := create_tween()
			tw.tween_property(pn, "position:y", 0.45, 0.12)
			tw.tween_property(pn, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE)
		sfx("snap", 60)
		if is_local(player_by_slot(s)):
			shake(0.25)
	else:
		sfx("thud", 40)


func _sparkle(at: Vector3, val: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10 + val * 8
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -4, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.4)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	q.material = m
	p.mesh = q
	p.position = at
	world3.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_elapsed += delta
	if not is_client():
		_think(delta)
	for s in _stun:
		if float(_stun[s]) > 0.0:
			_stun[s] = float(_stun[s]) - delta
			if float(_stun[s]) <= 0.0 and not _dig.has(s) and walkers.has(s):
				walkers[s]["speed"] = WALK
	step_walkers(delta)
	_keep_in_area()
	for s in _dig.keys():
		var d: Dictionary = _dig[s]
		d["t"] = float(d["t"]) + delta
		d["fx"] = float(d["fx"]) - delta
		if float(d["fx"]) <= 0.0:
			d["fx"] = 0.42
			var at: Vector2 = d["at"]
			debris(Vector3(at.x, 0.1, at.y), Color(0.9, 0.8, 0.6), 7)
			if is_local(player_by_slot(s)) or demo:
				sfx("dig_sand", 120)
			elif walkers.has(s):
				sfx("dig_sand", 300)
		if not is_client() and float(d["t"]) >= float(d["dur"]):
			_dig_done(s)
	_pose_tools(delta)
	_detectors(delta)
	_update_fx(delta)


func _keep_in_area() -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w.has("net_pos"):
			continue
		var p: Vector3 = w["pos"]
		p.x = clampf(p.x, -AX, AX)
		p.z = clampf(p.z, AZ0, AZ1)
		w["pos"] = p
		(w["node"] as Node3D).position.x = p.x
		(w["node"] as Node3D).position.z = p.z


## 탐지기 훑기 · 파는 몸짓 (삽질)
func _pose_tools(_delta: float) -> void:
	for s in _det:
		var dt: Dictionary = _det[s]
		var root: Node3D = dt["root"]
		var n: Node3D = walkers[s]["node"]
		if _dig.has(s):
			var t := float(_dig[s]["t"])
			root.rotation = Vector3(0, 0.9, 0)   # 탐지기는 옆으로 치움
			var sp: Node3D = dt["spade"]
			var ph := fmod(t / 0.42, 1.0)
			sp.rotation = Vector3(lerpf(-0.2, 0.9, sin(ph * PI)), 0, 0.1)
			sp.position = Vector3(-0.05, 0.42 - sin(ph * PI) * 0.12, 0.28)
			n.rotation.x = 0.28 + sin(ph * TAU) * 0.08
		else:
			root.rotation = Vector3(0, sin(_t3 * 2.7 + s) * 0.35, 0)


## 탐지기: 묻힌 쇠붙이(보물 · 깡통)까지 거리로 신호. 내 것은 삑 소리 + 신호 고리, 모두의 손잡이 불빛이 깜빡
func _detectors(delta: float) -> void:
	var me := local_slot()
	for s in _det:
		if not walkers.has(s):
			continue
		var dt: Dictionary = _det[s]
		var at := _coil(s)
		var tg := _nearest(at, DET_RANGE)
		var st := 0.0
		if not tg.is_empty():
			st = 1.0 - at.distance_to(tg["pos"]) / DET_RANGE
		var digging := _dig.has(s)
		dt["bt"] = float(dt["bt"]) - delta
		if st > 0.0 and not digging and float(dt["bt"]) <= 0.0:
			dt["bt"] = lerpf(1.0, 0.075, pow(st, 1.25))
			dt["flash"] = 0.06
			if s == me and is_local(walkers[s]["p"]) and not demo:
				sfx("det_ping" if st > 0.86 else "det_beep", 0)
				_ring(Vector3(at.x, 0.03, at.y), st)
		dt["flash"] = maxf(0.0, float(dt["flash"]) - delta)
		(dt["led"] as StandardMaterial3D).emission_energy_multiplier = 4.0 if float(dt["flash"]) > 0.0 else 0.0


func _ring(at: Vector3, st: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.2
	t.outer_radius = 0.24
	t.rings = 24
	t.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.4, 0.2).lerp(Color(1.0, 0.9, 0.3), st)
	var mi := add_mesh(t, m, at, Basis())
	mi.scale = Vector3(1.0, 0.1, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings.append({"node": mi, "t": 0.0, "mat": m})


func _update_fx(delta: float) -> void:
	for i in range(_rings.size() - 1, -1, -1):
		var r: Dictionary = _rings[i]
		r["t"] = float(r["t"]) + delta
		var f := float(r["t"]) / 0.45
		var n: Node3D = r["node"]
		if f >= 1.0:
			n.queue_free()
			_rings.remove_at(i)
			continue
		n.scale = Vector3(1.0 + f * 2.2, 0.1, 1.0 + f * 2.2)
		var m: StandardMaterial3D = r["mat"]
		m.albedo_color.a = (1.0 - f) * 0.8
	for i in range(_crabs.size() - 1, -1, -1):
		var c: Dictionary = _crabs[i]
		c["t"] = float(c["t"]) + delta
		var n: Node3D = c["node"]
		n.position += (c["vel"] as Vector3) * delta
		n.position.y = absf(sin(float(c["t"]) * 22.0)) * 0.03
		n.rotation.y = atan2((c["vel"] as Vector3).x, (c["vel"] as Vector3).z) + PI / 2 + sin(float(c["t"]) * 18.0) * 0.15
		if float(c["t"]) > 4.5:
			n.queue_free()
			_crabs.remove_at(i)


# ── CPU ─────────────────────────────────────────────────────
## 탐지기 신호가 잡히는 거리 안의 쇠붙이로 다가감 (실력이 낮을수록 짐작이 빗나감). 코일이 짐작한 자리 위에 오면 팜.
## 신호가 없으면 아직 안 가 본 쪽으로 훑으며 걸어 다님. 남이 이미 파고 있는 곳은 피함
func _think(delta: float) -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p) or _dig.has(s) or float(_stun.get(s, 0.0)) > 0.0:
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p) / 2.0
		var pos: Vector3 = w["pos"]
		var at := _coil(s)
		# 파기 전에 잠깐 서서 탐지기로 훑어 봄
		if float(a.get("hold", 0.0)) > 0.0:
			a["hold"] = float(a["hold"]) - delta
			w["target"] = pos
			if float(a["hold"]) <= 0.0:
				_try_dig(s)
				a["est_id"] = -1
				a["t"] = 0.0
			continue
		a["t"] = float(a["t"]) - delta
		a["est_t"] = float(a["est_t"]) - delta
		if float(a["t"]) <= 0.0:
			a["t"] = lerpf(0.4, 0.15, sk)
			var best := {}
			var bd := lerpf(3.0, 4.8, sk)   # 신호를 알아듣는 거리
			for b: Dictionary in _buried:
				var d := at.distance_to(b["pos"])
				var taken := false
				for o in _dig:
					if o != s and (_dig[o]["at"] as Vector2).distance_to(b["pos"]) < DIG_R:
						taken = true
				for o in walkers:
					if o != s and Vector2((walkers[o]["pos"] as Vector3).x, (walkers[o]["pos"] as Vector3).z).distance_to(b["pos"]) < d * 0.6 - 0.5:
						taken = true   # 남이 훨씬 가까움
				if not taken and d < bd:
					bd = d
					best = b
			if not best.is_empty():
				# 짐작: 가까워질수록 정확해짐 (실력이 낮으면 크게 빗나감)
				if int(a["est_id"]) != int(best["id"]) or float(a["est_t"]) <= 0.0:
					a["est_id"] = int(best["id"])
					a["est_t"] = 0.8
					var err := lerpf(1.3, 0.45, sk) * clampf(bd / 2.5, 0.4, 1.0)
					var ang := rng.randf() * TAU
					a["est"] = (best["pos"] as Vector2) + Vector2(cos(ang), sin(ang)) * err * rng.randf()
				var est: Vector2 = a["est"]
				a["goal"] = Vector3(est.x, 0, est.y)
			else:
				a["est_id"] = -1
				var g: Vector3 = a["goal"]
				if Vector2(pos.x, pos.z).distance_to(Vector2(g.x, g.z)) < 1.0 or rng.randf() < 0.05:
					a["goal"] = Vector3(rng.randf_range(-AX + 1, AX - 1), 0, rng.randf_range(AZ0 + 1, AZ1 - 1))
		var goal: Vector3 = a["goal"]
		w["target"] = goal
		if int(a["est_id"]) >= 0:
			var est2: Vector2 = a["est"]
			if at.distance_to(est2) < lerpf(0.55, 0.35, sk) or Vector2(pos.x, pos.z).distance_to(est2) < 0.35:
				w["face"] = atan2(est2.x - pos.x, est2.y - pos.z)
				w["target"] = pos
				a["hold"] = rng.randf_range(lerpf(0.7, 0.3, sk), lerpf(1.4, 0.7, sk))


func _is_done() -> bool:
	return time_left <= 0.0


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(scores.get(int(a["slot"]), 0)) > int(scores.get(int(b["slot"]), 0)))
	return order


func _net_state() -> Dictionary:
	return {"el": _elapsed, "sc": scores}


func _net_apply(st: Dictionary) -> void:
	_elapsed = float(st.get("el", _elapsed))
	var sc: Dictionary = st.get("sc", {})
	for s in sc:
		scores[int(s)] = int(sc[s])


func _score_text(p: Dictionary) -> String:
	return tr("%d pts") % int(scores.get(int(p["slot"]), 0))


## 작은 것들(조개 · 불가사리 · 코코넛 · 돌 부스러기)은 그림자를 안 드리움 — 그리기 횟수 줄임
func _no_shadow_small(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var sz := m.mesh.get_aabb().size * m.global_transform.basis.get_scale()
		if maxf(sz.x, maxf(sz.y, sz.z)) < 0.45:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
