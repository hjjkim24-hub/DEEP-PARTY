extends "res://scripts/minigames/minigame_3d.gd"
## 화물 옮기기 (WASD 이동 · 스페이스 하나): 항구 부두 한가운데 쌓인 화물을 들어서 내 구역(네 귀퉁이)으로 나르기.
## 스페이스 = 화물 옆이면 번쩍 들기 / 들고 있으면 내려놓기 / 빈손이면 몸통 박치기 (들고 있던 사람은 화물을 떨어뜨림).
## 상자 · 술통 · 자루는 1점, 가끔 나오는 보물상자는 3점 (무거워서 느림). 남의 구역에 놓인 화물도 훔쳐 올 수 있음.
## 크레인이 그물에 싸 온 새 화물을 가운데에 주기적으로 떨굼. 시간이 끝났을 때 내 구역 화물 점수가 가장 높은 사람이 승리.
## 화물이 내 구역 안에 놓여 있어야 점수 (들고 있는 건 안 셈).

const HX := 10.5                ## 부두 반 너비
const HZ := 7.2                 ## 부두 반 길이
const ZONE_HALF := Vector2(2.3, 1.8)
const WALK := 4.8
const SHOVE_CD := 0.9
const PICK_R := 1.05
const CARRY_Y := 1.42
const DROP_AT := [8.0, 17.0, 26.0, 35.0, 44.0]
const NET_Y := 4.6
const KINDS := {
	"crate": {"val": 1, "r": 0.42, "speed": 3.5},
	"barrel": {"val": 1, "r": 0.36, "speed": 3.6},
	"sack": {"val": 1, "r": 0.36, "speed": 3.8},
	"chest": {"val": 3, "r": 0.5, "speed": 2.5},
}

var _deck: Node3D
var _items: Array = []          ## {id, kind, pos Vector3, vel Vector3, vy, carrier, node, yaw, in_net, landed}
var _next_id := 0
var _zones := {}                ## slot → Vector2 (구역 가운데)
var _carry := {}                ## slot → item id (-1 빈손)
var _shove_cd := {}
var _ai := {}
var _elapsed := 0.0
var _drop_i := 0
var _net_node: Node3D           ## 크레인 그물 뭉치
var _hook: Node3D
var _hook_rope: MeshInstance3D
var _crane_t := -1.0             ## 그물이 내려오는 중 (경과 시간), -1 = 쉬는 중
var _flags := {}                ## slot → 깃발 천 조각들
var _zone_mats := {}


func _init() -> void:
	title = "CARGO HAUL"
	how_to = "Haul the cargo from the middle of the wharf to your corner! SPACE picks it up and puts it down. With empty hands SPACE shoves - whoever's hit drops their cargo. Treasure chests are worth 3! You can steal from other corners too."
	goal = "Haul the most cargo to your corner!"
	controls = "KEYS_ACT"
	duration = 60.0


func _build_stage() -> void:
	env_sea_day()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	env.fog_density = 0.0035
	var sea := ocean(-0.95, 240.0, 15.0)
	(sea.material_override as ShaderMaterial).set_shader_parameter("amp", 0.3)
	sky_clouds(14, 190.0, 30.0)
	gulls(4, Vector3(0, 0, -16), 24.0, 9.0, 12)
	island(Vector3(120, -1.5, -170), 24.0, 14.0, 4)
	sea_debris(8, 18.0, 40.0, -0.9, 31)
	cam.fov = 46.0
	var xf := Transform3D(Basis(), Vector3(0, 15.5, 12.2))
	xf = xf.looking_at(Vector3(0, 0, 0.9), Vector3.UP)
	cam.transform = xf
	cam_base = xf
	_deck = Node3D.new()
	world3.add_child(_deck)
	_build_wharf()


# ── 부두 ────────────────────────────────────────────────────
func _build_wharf() -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	# 바닥: 가로로 깐 널판 (결 · 이음 셰이더) + 가장자리 굵은 각목 테
	var deck_m := wood_mat(Color(0.52, 0.42, 0.31), Vector3(1, 0, 0), 0.08)
	deck_m.set_shader_parameter("plank_w", 0.28)
	box(Vector3(HX * 2.0 + 0.6, 0.3, HZ * 2.0 + 0.6), deck_m, Vector3(0, -0.15, 0), Basis(), _deck)
	var beam_m := wood_mat(Color(0.32, 0.24, 0.17), Vector3(1, 0, 0), 0.2)
	var beam_mz := wood_mat(Color(0.32, 0.24, 0.17), Vector3(0, 0, 1), 0.2)
	for sz: float in [-1.0, 1.0]:
		box(Vector3(HX * 2.0 + 1.1, 0.42, 0.32), beam_m, Vector3(0, -0.06, sz * (HZ + 0.42)), Basis(), _deck)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(0.32, 0.42, HZ * 2.0 + 1.1), beam_mz, Vector3(sx * (HX + 0.42), -0.06, 0), Basis(), _deck)
	# 물속에 박힌 기둥 (따개비 · 물때 낀 아랫부분)
	var pile_m := stone_mat(Color(0.34, 0.27, 0.2), "stone", 0.55)
	var pile := CylinderMesh.new()
	pile.top_radius = 0.26
	pile.bottom_radius = 0.3
	pile.height = 3.4
	pile.radial_segments = 14
	var px := -HX - 0.45
	while px <= HX + 0.5:
		for sz: float in [-1.0, 1.0]:
			add_mesh(pile, pile_m, Vector3(px + rr.randf_range(-0.1, 0.1), -1.65, sz * (HZ + 0.62)), Basis(Vector3.UP, rr.randf() * TAU), _deck)
		px += 3.0
	var pz := -HZ + 2.4
	while pz < HZ - 1.0:
		for sx: float in [-1.0, 1.0]:
			add_mesh(pile, pile_m, Vector3(sx * (HX + 0.62), -1.65, pz), Basis(Vector3.UP, rr.randf() * TAU), _deck)
		pz += 3.2
	# 뒤쪽 가장자리: 쇠말뚝(볼라드) + 배에 맨 밧줄
	var iron := std_mat(Color(0.12, 0.12, 0.13), 0.55, 0.7)
	var rope := std_mat(Color(0.55, 0.46, 0.32), 0.95)
	for bx: float in [-6.5, 6.5]:
		var bp := Vector3(bx, 0.14, -HZ - 0.42)
		var prof := [Vector2(0.17, 0.0), Vector2(0.15, 0.2), Vector2(0.12, 0.35), Vector2(0.17, 0.48), Vector2(0.18, 0.55), Vector2(0.0, 0.58)]
		add_mesh(lathe_mesh(prof, 18), iron, bp, Basis(), _deck)
		for k in 3:
			var t := TorusMesh.new()
			t.inner_radius = 0.13
			t.outer_radius = 0.19
			add_mesh(t, rope, bp + Vector3(0, 0.12 + k * 0.07, 0), Basis(Vector3.RIGHT, 0.15 * (k - 1)), _deck)
		_rod(bp + Vector3(0, 0.3, -0.1), Vector3(bx * 0.75, 1.6, -HZ - 4.0), 0.035, rope)
	# 정박한 배 (뒤)
	var ship := sailboat(Color(0.88, 0.84, 0.74), world3, 3.0, 1.1, 0.6)
	ship.scale = Vector3.ONE * 4.2
	ship.rotation.y = 0.0   # 부두와 나란히
	ship.position = Vector3(-1.5, -1.0, -HZ - 3.9)
	# 크레인: 뒤쪽 가운데 기둥 + 가운데 위로 뻗은 팔 + 밧줄 · 갈고리 · 그물 뭉치
	var crane_m := wood_mat(Color(0.36, 0.27, 0.18), Vector3(0, 1, 0), 0.15)
	var post_at := Vector3(0, 0, -HZ - 0.1)
	box(Vector3(0.5, 6.2, 0.5), crane_m, post_at + Vector3(0, 3.1, 0), Basis(), _deck)
	box(Vector3(1.3, 0.3, 1.3), beam_m, post_at + Vector3(0, 0.15, 0), Basis(), _deck)
	var boom_a := post_at + Vector3(0, 5.9, 0)
	var boom_b := Vector3(0, 6.6, 0.2)
	_beam(boom_a, boom_b, 0.18, crane_m)
	_beam(post_at + Vector3(0, 3.2, 0.2), boom_a.lerp(boom_b, 0.5), 0.09, crane_m)   # 받침대
	_rod(post_at + Vector3(0, 6.2, 0), boom_b, 0.03, rope)
	_hook_rope = MeshInstance3D.new()
	var hr := CylinderMesh.new()
	hr.top_radius = 0.025
	hr.bottom_radius = 0.025
	hr.height = 1.0
	_hook_rope.mesh = hr
	_hook_rope.material_override = rope
	_deck.add_child(_hook_rope)
	_hook = Node3D.new()
	_deck.add_child(_hook)
	_net_node = Node3D.new()
	_hook.add_child(_net_node)
	var net_m := std_mat(Color(0.5, 0.42, 0.3), 0.95)
	net_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var bag := SphereMesh.new()
	bag.radius = 0.9
	bag.height = 1.5
	var nt := _net_tex()
	net_m.albedo_texture = nt
	net_m.uv1_scale = Vector3(6, 4, 1)
	net_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_mesh(bag, net_m, Vector3(0, -0.85, 0), Basis(), _net_node)
	var inner := BoxMesh.new()
	inner.size = Vector3(1.0, 0.9, 1.0)
	add_mesh(inner, wood_mat(Color(0.5, 0.38, 0.25), Vector3(1, 0, 0), 0.1), Vector3(0, -0.95, 0), Basis(Vector3.UP, 0.4), _net_node)
	_net_node.visible = false
	_place_hook(0.0)
	# 가로등 (양옆)
	for lx: float in [-HX - 0.42, HX + 0.42]:
		lantern(_deck, Vector3(lx, 0.15, 0.0))
	# 잡동사니: 감은 밧줄 · 그물 더미 · 빈 나무통 (가장자리 바깥 테 위)
	for k in 2:
		var cx: float = [-HX - 0.42, HX + 0.42][k]
		for j in 3:
			var t := TorusMesh.new()
			t.inner_radius = 0.18 - j * 0.02
			t.outer_radius = 0.26 - j * 0.02
			add_mesh(t, rope, Vector3(cx, 0.2 + j * 0.05, HZ - 1.6), Basis(), _deck)


func _rod(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var d := b - a
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = d.length()
	c.radial_segments = 8
	add_mesh(c, mat, (a + b) * 0.5, Basis(Quaternion(Vector3.UP, d.normalized())), _deck)


func _beam(a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var d := b - a
	var bx := BoxMesh.new()
	bx.size = Vector3(w, d.length(), w)
	add_mesh(bx, mat, (a + b) * 0.5, Basis(Quaternion(Vector3.UP, d.normalized())), _deck)


## 그물 눈 무늬 (격자 — 줄만 보이고 사이는 뚫림)
func _net_tex() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 64:
			var u := (x + y) % 16
			var v := (x - y + 64) % 16
			if u < 3 or v < 3:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


## 갈고리 · 그물 위치 (f: 0 = 위로 감아올림, 1 = 다 내려옴)
func _place_hook(f: float) -> void:
	var y := lerpf(NET_Y + 1.2, 2.7, f)
	_hook.position = Vector3(0, y, 0.2)
	# 팔 끝에서 갈고리까지 늘어진 밧줄
	var top := 6.55
	_hook_rope.scale = Vector3(1, maxf(top - y, 0.05), 1)
	_hook_rope.position = Vector3(0, (top + y) * 0.5, 0.2)


# ── 화물 모양 ───────────────────────────────────────────────
func _make_item_node(kind: String, seed_: int) -> Node3D:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_ * 31 + 7
	var root := Node3D.new()
	_deck.add_child(root)
	match kind:
		"crate":
			var s := 0.74
			var wm := wood_mat(Color(0.58, 0.45, 0.29).darkened(rr.randf_range(0.0, 0.18)), Vector3(1, 0, 0), 0.05)
			var edge := wood_mat(Color(0.36, 0.27, 0.17), Vector3(0, 1, 0), 0.05)
			box(Vector3(s, s, s), wm, Vector3(0, s * 0.5, 0), Basis(), root)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					box(Vector3(0.07, s + 0.02, 0.07), edge, Vector3(sx * s * 0.5, s * 0.5, sz * s * 0.5), Basis(), root)
			for sz: float in [-1.0, 1.0]:
				box(Vector3(s + 0.02, 0.07, 0.07), edge, Vector3(0, s, sz * s * 0.5), Basis(), root)
				box(Vector3(s + 0.02, 0.07, 0.07), edge, Vector3(0, 0.035, sz * s * 0.5), Basis(), root)
				# 대각선 버팀 널
				box(Vector3(s * 1.25, 0.06, 0.02), edge, Vector3(0, s * 0.5, sz * (s * 0.5 + 0.01)), Basis(Vector3.BACK, 0.78), root)
		"barrel":
			barrel(root, Vector3.ZERO, 0.34, 0.86, [Color(0.44, 0.29, 0.17), Color(0.4, 0.27, 0.15), Color(0.48, 0.32, 0.18)][seed_ % 3])
		"sack":
			var burlap := std_mat(Color(0.47, 0.38, 0.25).darkened(rr.randf_range(0.0, 0.12)), 1.0)
			var sm := SphereMesh.new()
			sm.radius = 0.4
			sm.height = 0.7
			sm.radial_segments = 14
			sm.rings = 8
			var body := add_mesh(sm, burlap, Vector3(0, 0.3, 0), Basis(), root)
			body.scale = Vector3(1.05, 0.85, 0.82)
			var neck := CylinderMesh.new()
			neck.top_radius = 0.07
			neck.bottom_radius = 0.12
			neck.height = 0.22
			add_mesh(neck, burlap, Vector3(0, 0.62, 0), Basis(), root)
			var tie := TorusMesh.new()
			tie.inner_radius = 0.07
			tie.outer_radius = 0.1
			add_mesh(tie, std_mat(Color(0.35, 0.27, 0.18), 0.9), Vector3(0, 0.6, 0), Basis(), root)
			var flap := CylinderMesh.new()
			flap.top_radius = 0.15
			flap.bottom_radius = 0.05
			flap.height = 0.1
			add_mesh(flap, burlap, Vector3(0, 0.76, 0), Basis(), root)
		"chest":
			var ch := treasure_chest(0.92, 0.5, 0.6, root)
			var lid := ch.get("lid") as Node3D
			if lid:
				lid.rotation.x = 0.0
			# 빛나는 금 테두리 (멀리서도 보물상자인 줄 알게)
			var glint := OmniLight3D.new()
			glint.light_color = Color(1.0, 0.82, 0.45)
			glint.light_energy = 0.6
			glint.omni_range = 1.6
			glint.position = Vector3(0, 0.8, 0)
			root.add_child(glint)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


# ── 시작 ────────────────────────────────────────────────────
func _setup_game() -> void:
	walk_radius = 999.0
	var corners := [Vector2(-1, -1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1)]
	for i in players.size():
		var p: Dictionary = players[i]
		var s := int(p["slot"])
		var c: Vector2 = corners[i % 4]
		var zc := Vector2(c.x * (HX - ZONE_HALF.x - 0.75), c.y * (HZ - ZONE_HALF.y - 0.6))
		_zones[s] = zc
		_build_zone(s, zc, p["color"])
		var w := add_walker(p, Vector3(zc.x, 0, zc.y), WALK)
		w["face"] = atan2(-zc.x, -zc.y)
		_carry[s] = -1
		_shove_cd[s] = 0.0
		_ai[s] = {"t": 0.0, "item": -1, "spot": Vector3(zc.x, 0, zc.y), "shove_t": 0.0}
		scores[s] = 0
	# 가운데 화물 더미 (모두 같은 자리 — 고정된 모양)
	var rr := RandomNumberGenerator.new()
	rr.seed = 1234
	_add_item("chest", Vector3(0, 0, 0.1), rr.randf() * TAU)
	var kinds := ["crate", "barrel", "sack", "crate", "barrel", "sack", "crate", "crate", "barrel", "sack", "crate", "barrel"]
	for k in kinds.size():
		var a := float(k) / kinds.size() * TAU + rr.randf_range(-0.2, 0.2)
		var rad := 1.5 + (k % 2) * 1.0 + rr.randf_range(-0.2, 0.2)
		_add_item(kinds[k], Vector3(cos(a) * rad * 1.3, 0, sin(a) * rad), rr.randf() * TAU)


func _add_item(kind: String, pos: Vector3, yaw: float, in_net: bool = false) -> Dictionary:
	var it := {"id": _next_id, "kind": kind, "pos": pos, "vel": Vector3.ZERO, "vy": 0.0, "carrier": -1,
		"node": _make_item_node(kind, _next_id), "yaw": yaw, "in_net": in_net, "seen": pos}
	_next_id += 1
	(it["node"] as Node3D).position = pos
	(it["node"] as Node3D).rotation.y = yaw
	(it["node"] as Node3D).visible = not in_net
	_items.append(it)
	return it


## 구역: 플레이어 색 페인트 테두리 (닳은 느낌) + 옅은 바닥 색 + 귀퉁이 깃대 · 펄럭이는 깃발
func _build_zone(s: int, zc: Vector2, col: Color) -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(col.r, col.g, col.b, 0.85)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.roughness = 0.9
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(col.r, col.g, col.b, 0.13)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_mats[s] = tint
	var q := QuadMesh.new()
	q.size = ZONE_HALF * 2.0
	q.orientation = PlaneMesh.FACE_Y
	add_mesh(q, tint, Vector3(zc.x, 0.012, zc.y), Basis(), _deck).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lw := 0.12
	for sz: float in [-1.0, 1.0]:
		var e := add_mesh(_quad(Vector2(ZONE_HALF.x * 2.0 + lw, lw)), paint, Vector3(zc.x, 0.015, zc.y + sz * ZONE_HALF.y), Basis(), _deck)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx: float in [-1.0, 1.0]:
		var e := add_mesh(_quad(Vector2(lw, ZONE_HALF.y * 2.0 + lw)), paint, Vector3(zc.x + sx * ZONE_HALF.x, 0.015, zc.y), Basis(), _deck)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 깃대 (부두 바깥 귀퉁이 쪽)
	var cx := signf(zc.x) * (HX + 0.42)
	var cz := signf(zc.y) * (HZ + 0.42)
	var pole_m := std_mat(Color(0.32, 0.24, 0.17), 0.8)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.06
	pole.height = 3.2
	add_mesh(pole, pole_m, Vector3(cx, 1.75, cz), Basis(), _deck)
	var cloth := std_mat(col, 0.85)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flag := Node3D.new()
	flag.position = Vector3(cx, 3.05, cz)
	_deck.add_child(flag)
	var segs := []
	for k in 5:
		var fq := QuadMesh.new()
		fq.size = Vector2(0.2, 0.62 - k * 0.06)
		segs.append(add_mesh(fq, cloth, Vector3(0.1 + k * 0.2, 0, 0), Basis(), flag))
	flag.rotation.y = 0.0 if zc.x < 0 else PI
	_flags[s] = segs


func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	return q


func _start_game() -> void:
	_elapsed = 0.0


# ── 조작 ────────────────────────────────────────────────────
func _input(e: InputEvent) -> void:
	if not playing or demo:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
		net_input("act")


func _net_input(slot: int, action: String, _args: Array) -> void:
	if action == "act" and playing:
		_act(slot)


func _item(id: int) -> Dictionary:
	for it: Dictionary in _items:
		if int(it["id"]) == id:
			return it
	return {}


func _face_dir(s: int) -> Vector3:
	var f := float(walkers[s]["face"])
	return Vector3(sin(f), 0, cos(f))


## 방장: 스페이스 — 들고 있으면 내려놓기, 옆에 화물 있으면 들기, 아니면 박치기
func _act(s: int) -> void:
	if not walkers.has(s):
		return
	var w: Dictionary = walkers[s]
	var pos: Vector3 = w["pos"]
	var cid := int(_carry.get(s, -1))
	if cid >= 0:
		var it := _item(cid)
		if not it.is_empty():
			var at := _clamp_deck(pos + _face_dir(s) * 0.85, float(KINDS[it["kind"]]["r"]))
			it["pos"] = Vector3(at.x, CARRY_Y * 0.7, at.z)
			it["vel"] = _face_dir(s) * 1.2
			it["vy"] = 0.5
			it["carrier"] = -1
		_carry[s] = -1
		w["speed"] = WALK
		net_call("_act_fx", [s, 0])
		return
	# 가까운 화물 (앞쪽을 조금 더 쳐줌)
	var best := {}
	var bd := INF
	for it: Dictionary in _items:
		if int(it["carrier"]) >= 0 or it["in_net"] or (it["pos"] as Vector3).y > 0.6:
			continue
		var d: Vector3 = (it["pos"] as Vector3) - pos
		d.y = 0.0
		var reach := PICK_R + float(KINDS[it["kind"]]["r"]) * 0.5
		if d.length() > reach:
			continue
		var score := d.length() - (d.normalized().dot(_face_dir(s)) * 0.3 if d.length() > 0.01 else 0.0)
		if score < bd:
			bd = score
			best = it
	if not best.is_empty():
		best["carrier"] = s
		best["vel"] = Vector3.ZERO
		_carry[s] = int(best["id"])
		w["speed"] = float(KINDS[best["kind"]]["speed"])
		net_call("_act_fx", [s, 1])
		return
	# 박치기
	if float(_shove_cd.get(s, 0.0)) > 0.0:
		return
	_shove_cd[s] = SHOVE_CD
	var dir := _face_dir(s)
	net_push(s, dir * 6.5)
	var hit := -1
	for o in walkers:
		if o == s:
			continue
		var d: Vector3 = (walkers[o]["pos"] as Vector3) - pos
		d.y = 0.0
		if d.length() < 1.6 and d.length() > 0.01 and d.normalized().dot(dir) > 0.45:
			hit = o
			break
	if hit >= 0:
		var oc := int(_carry.get(hit, -1))
		if oc >= 0:
			var it2 := _item(oc)
			if not it2.is_empty():
				it2["carrier"] = -1
				it2["pos"] = Vector3((walkers[hit]["pos"] as Vector3).x, CARRY_Y, (walkers[hit]["pos"] as Vector3).z)
				it2["vel"] = dir * 2.6 + Vector3(-dir.z, 0, dir.x) * rng.randf_range(-1.5, 1.5)
				it2["vy"] = 2.5
			_carry[hit] = -1
			walkers[hit]["speed"] = WALK
		net_push(hit, dir * 5.5, 0.55)
		net_call("_act_fx", [s, 3, hit])
	else:
		net_call("_act_fx", [s, 2])


## 모두: 소리 · 몸짓 (0 내려놓기, 1 들기, 2 헛박치기, 3 박치기 맞힘)
func _act_fx(s: int, what: int, hit: int = -1) -> void:
	if not walkers.has(s):
		return
	var n: Node3D = walkers[s]["node"]
	match what:
		0:
			sfx("thud", 60)
		1:
			sfx("box_whoosh", 60)
			var tw := create_tween()
			tw.tween_property(n, "scale", Vector3(PAWN_SCALE * 1.08, PAWN_SCALE * 0.88, PAWN_SCALE * 1.08), 0.08)
			tw.tween_property(n, "scale", Vector3.ONE * PAWN_SCALE, 0.14)
		2:
			sfx("whoosh", 60)
		3:
			sfx("thud", 30)
			sfx("whoosh", 60)
			if walkers.has(hit):
				var hp: Vector3 = walkers[hit]["pos"]
				debris(hp + Vector3(0, 0.8, 0), Color(0.75, 0.7, 0.6), 6)
				if is_local(walkers[hit]["p"]):
					shake(0.25)


# ── 매 프레임 ───────────────────────────────────────────────
func _tick(delta: float) -> void:
	_elapsed += delta
	if not is_client():
		for s in _shove_cd:
			_shove_cd[s] = maxf(0.0, float(_shove_cd[s]) - delta)
		_think(delta)
		_crane_sched()
	step_walkers(delta)
	_keep_on_deck()
	if not is_client():
		_items_sim(delta)
	_show_items(delta)
	_show_crane(delta)
	_score_all()
	_show_flags()
	if OS.get_environment("MG_DEBUG") != "" and not is_client() and fmod(_elapsed, 5.0) < delta:
		var free := 0
		for it: Dictionary in _items:
			if _zone_of(it["pos"]) < 0 and int(it["carrier"]) < 0:
				free += 1
		print("CH t=%.0f scores=%s carry=%s items=%d free=%d" % [_elapsed, str(scores), str(_carry), _items.size(), free])


func _clamp_deck(p: Vector3, r: float) -> Vector3:
	p.x = clampf(p.x, -HX + r, HX - r)
	p.z = clampf(p.z, -HZ + r, HZ - r)
	return p


func _keep_on_deck() -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		if w.has("net_pos"):
			continue
		var pos := _clamp_deck(w["pos"], 0.3)
		# 크레인 기둥
		var d := Vector2(pos.x, pos.z - (-HZ - 0.1))
		if d.length() < 0.75:
			d = d.normalized() * 0.75 if d.length() > 0.01 else Vector2(0, 0.75)
			pos.x = d.x
			pos.z = d.y + (-HZ - 0.1)
		w["pos"] = pos
		(w["node"] as Node3D).position.x = pos.x
		(w["node"] as Node3D).position.z = pos.z


## 방장: 화물 움직임 — 들려 있으면 그 사람 머리 위, 떨어지면 통 튀고 미끄러짐, 서로 · 사람과 부딪히면 밀림
func _items_sim(delta: float) -> void:
	for it: Dictionary in _items:
		if it["in_net"]:
			continue
		var c := int(it["carrier"])
		if c >= 0 and walkers.has(c):
			var wp: Vector3 = walkers[c]["pos"]
			it["pos"] = Vector3(wp.x, CARRY_Y, wp.z)
			it["yaw"] = lerp_angle(float(it["yaw"]), float(walkers[c]["face"]), clampf(delta * 8.0, 0.0, 1.0))
			continue
		var p: Vector3 = it["pos"]
		var v: Vector3 = it["vel"]
		var r := float(KINDS[it["kind"]]["r"])
		# 높이 (던져지거나 크레인에서 떨어짐)
		if p.y > 0.0 or float(it["vy"]) > 0.0:
			it["vy"] = float(it["vy"]) - 20.0 * delta
			p.y += float(it["vy"]) * delta
			if p.y <= 0.0:
				p.y = 0.0
				var hit_v := -float(it["vy"])
				it["vy"] = hit_v * 0.25 if hit_v > 3.0 else 0.0
				if hit_v > 3.0:
					net_call("_land_fx", [Vector3(p.x, 0, p.z), minf(hit_v / 10.0, 1.0)])
					# 떨어지는 화물에 맞으면 휘청
					for s in walkers:
						var dd: Vector3 = (walkers[s]["pos"] as Vector3) - p
						dd.y = 0.0
						if dd.length() < r + 0.4 and hit_v > 6.0:
							net_push(s, dd.normalized() * 4.0 if dd.length() > 0.01 else Vector3(1, 0, 0) * 4.0, 0.7)
		p += v * delta
		v *= exp(-(4.0 if p.y <= 0.0 else 0.3) * delta)
		# 사람이 밀고 지나가면 살짝 밀림
		if p.y < 0.4:
			for s in walkers:
				var d: Vector3 = p - (walkers[s]["pos"] as Vector3)
				d.y = 0.0
				var mind := r + 0.32
				if d.length() < mind and d.length() > 0.001:
					var o := (mind - d.length())
					p += d.normalized() * o * 0.6
					v += d.normalized() * o * 3.0
		p = _clamp_deck(p, r)
		it["pos"] = p
		it["vel"] = v
	# 화물끼리 겹치지 않게
	for i in _items.size():
		var a: Dictionary = _items[i]
		if int(a["carrier"]) >= 0 or a["in_net"]:
			continue
		for j in range(i + 1, _items.size()):
			var b: Dictionary = _items[j]
			if int(b["carrier"]) >= 0 or b["in_net"]:
				continue
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			if absf(pa.y - pb.y) > 0.6:
				continue
			var d := Vector3(pb.x - pa.x, 0, pb.z - pa.z)
			var mind := float(KINDS[a["kind"]]["r"]) + float(KINDS[b["kind"]]["r"])
			if d.length() < mind:
				var n := d.normalized() if d.length() > 0.001 else Vector3(1, 0, 0)
				var o := (mind - d.length()) * 0.5
				a["pos"] = pa - n * o
				b["pos"] = pb + n * o


func _land_fx(at: Vector3, power: float) -> void:
	sfx("thud", 40)
	debris(at + Vector3(0, 0.1, 0), Color(0.62, 0.55, 0.45), int(6 + power * 10))
	if power > 0.6:
		shake(0.12)


## 모두: 화물 모습 (손님은 받은 자리로 부드럽게)
func _show_items(delta: float) -> void:
	for it: Dictionary in _items:
		var n: Node3D = it["node"]
		if it["in_net"]:
			n.visible = false
			continue
		n.visible = true
		var p: Vector3 = it["pos"]
		var c := int(it["carrier"])
		if c >= 0 and walkers.has(c):
			# 들고 가는 화물: 그 말 머리 위 (걸음마다 살짝 출렁)
			var pn: Node3D = walkers[c]["node"]
			n.position = pn.position + Vector3(0, CARRY_Y - 0.02 + sin(float(walkers[c]["bob"]) * 2.0) * 0.03, 0)
			n.rotation = Vector3(0, float(it["yaw"]), sin(float(walkers[c]["bob"])) * 0.06)
			continue
		if is_client():
			n.position = n.position.lerp(p, clampf(delta * 14.0, 0.0, 1.0))
		else:
			n.position = p
		n.rotation = Vector3(0, float(it["yaw"]), 0)


func _score_all() -> void:
	for s in _zones:
		var zc: Vector2 = _zones[s]
		var sum := 0
		for it: Dictionary in _items:
			if int(it["carrier"]) >= 0 or it["in_net"]:
				continue
			var p: Vector3 = it["pos"]
			if absf(p.x - zc.x) < ZONE_HALF.x and absf(p.z - zc.y) < ZONE_HALF.y:
				sum += int(KINDS[it["kind"]]["val"])
		scores[s] = sum


func _show_flags() -> void:
	for s in _flags:
		var segs: Array = _flags[s]
		for k in segs.size():
			var sg: Node3D = segs[k]
			sg.position.z = sin(_t3 * 6.0 - k * 0.8 + s) * 0.05 * k
			sg.rotation.y = cos(_t3 * 6.0 - k * 0.8 + s) * 0.35


# ── 크레인 ──────────────────────────────────────────────────
func _crane_sched() -> void:
	if _drop_i >= DROP_AT.size() or _elapsed < float(DROP_AT[_drop_i]):
		return
	_drop_i += 1
	var n := 3
	var kinds := []
	for k in n:
		kinds.append(["crate", "barrel", "sack"][rng.randi() % 3])
	if rng.randf() < 0.45:
		kinds[0] = "chest"
	var offs := []
	for k in n:
		var a := rng.randf() * TAU
		var rad := rng.randf_range(0.6, 2.2)
		offs.append(Vector2(cos(a) * rad * 1.2, sin(a) * rad))
	net_call("_crane_go", [_next_id, kinds, offs])


## 모두: 그물에 싼 화물이 내려옴 → 풀려서 떨어짐
func _crane_go(id0: int, kinds: Array, offs: Array) -> void:
	_next_id = id0
	for k in kinds.size():
		var o: Vector2 = offs[k]
		var it := _add_item(kinds[k], Vector3(o.x, 3.0, o.y + 0.2), randf() * TAU, true)
		it["drop_off"] = o
	_crane_t = 0.0
	sfx("creak", 60)


func _show_crane(delta: float) -> void:
	if _crane_t < 0.0:
		_place_hook(0.0)
		_net_node.visible = false
		return
	_crane_t += delta
	var t := _crane_t
	_net_node.visible = t < 1.6
	if t < 1.4:
		_place_hook(clampf(t / 1.4, 0.0, 1.0))
		_net_node.rotation.y = sin(t * 3.0) * 0.2
	elif t < 3.2:
		_place_hook(1.0 - clampf((t - 1.6) / 1.6, 0.0, 1.0))
	else:
		_crane_t = -1.0
	if t >= 1.4 and t - delta < 1.4:
		# 그물이 풀리며 화물이 쏟아짐
		sfx("box_burst", 80)
		for it: Dictionary in _items:
			if it["in_net"]:
				it["in_net"] = false
				var o: Vector2 = it.get("drop_off", Vector2.ZERO)
				it["pos"] = Vector3(o.x * 0.3, 2.7, o.y * 0.3 + 0.2)
				it["vel"] = Vector3(o.x, 0, o.y) * 1.1
				it["vy"] = 1.5


# ── CPU ─────────────────────────────────────────────────────
## 빈손: 내 구역 밖에 있는 화물 중 값어치 · 거리로 골라 가서 듦 (실력이 좋을수록 보물상자 · 남의 구역도 노림)
## 들고 있으면: 내 구역 안쪽 빈자리로 가서 내려놓음. 근처에 화물 든 상대가 있으면 박치기
func _think(delta: float) -> void:
	for s in walkers:
		var w: Dictionary = walkers[s]
		var p: Dictionary = w["p"]
		if is_human(p):
			continue
		var a: Dictionary = _ai[s]
		var sk := skill(p) / 2.0
		var pos: Vector3 = w["pos"]
		var zc: Vector2 = _zones[s]
		a["t"] = float(a["t"]) - delta
		a["shove_t"] = float(a["shove_t"]) - delta
		# 박치기: 화물 든 상대가 바로 앞에 있으면
		if int(_carry[s]) < 0 and float(_shove_cd[s]) <= 0.0 and float(a["shove_t"]) <= 0.0:
			for o in walkers:
				if o == s or int(_carry.get(o, -1)) < 0:
					continue
				var d: Vector3 = (walkers[o]["pos"] as Vector3) - pos
				d.y = 0.0
				if d.length() < 1.5:
					a["shove_t"] = lerpf(0.9, 0.3, sk)
					if rng.randf() < lerpf(0.35, 0.85, sk):
						w["face"] = atan2(d.x, d.z)
						_act(s)
					break
		if int(_carry[s]) >= 0:
			# 내 구역으로
			var spot: Vector3 = a["spot"]
			if float(a["t"]) <= 0.0 or absf(spot.x - zc.x) > ZONE_HALF.x:
				a["t"] = 2.0
				spot = _free_spot(zc)
				a["spot"] = spot
			w["target"] = spot
			var inside := absf(pos.x - zc.x) < ZONE_HALF.x - 0.6 and absf(pos.z - zc.y) < ZONE_HALF.y - 0.5
			if inside and pos.distance_to(spot) < 0.9:
				_act(s)
				a["item"] = -1
			continue
		# 빈손: 고를 화물
		if float(a["t"]) <= 0.0 or _item(int(a["item"])).is_empty() or int(_item(int(a["item"]))["carrier"]) >= 0:
			a["t"] = lerpf(0.8, 0.35, sk) + rng.randf_range(0.0, 0.2)
			var best := -1
			var bv := INF
			for it: Dictionary in _items:
				if int(it["carrier"]) >= 0 or it["in_net"]:
					continue
				var ip: Vector3 = it["pos"]
				if absf(ip.x - zc.x) < ZONE_HALF.x and absf(ip.z - zc.y) < ZONE_HALF.y:
					continue   # 이미 내 구역
				var owner := _zone_of(ip)
				var v := pos.distance_to(ip) + Vector2(ip.x, ip.z).distance_to(zc) * 0.5 - float(KINDS[it["kind"]]["val"]) * lerpf(1.0, 3.0, sk)
				if owner >= 0:
					v += lerpf(4.0, 0.5, sk)   # 훔치기 (실력이 좋을수록 과감)
				v += rng.randf_range(0.0, lerpf(3.0, 0.6, sk))
				if v < bv:
					bv = v
					best = int(it["id"])
			a["item"] = best
		var tgt := _item(int(a["item"]))
		if tgt.is_empty():
			w["target"] = Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
			continue
		var ip2: Vector3 = tgt["pos"]
		w["target"] = Vector3(ip2.x, 0, ip2.z)
		var dd := Vector3(ip2.x - pos.x, 0, ip2.z - pos.z)
		if dd.length() < PICK_R + float(KINDS[tgt["kind"]]["r"]) * 0.4 and ip2.y < 0.5:
			w["face"] = atan2(dd.x, dd.z)
			_act(s)


## 구역 안 빈자리 (이미 놓인 화물과 겹치지 않게, 바깥 귀퉁이부터)
func _free_spot(zc: Vector2) -> Vector3:
	var best := Vector3(zc.x, 0, zc.y)
	var bv := INF
	for k in 14:
		var c := Vector3(zc.x + rng.randf_range(-ZONE_HALF.x + 0.7, ZONE_HALF.x - 0.7), 0, zc.y + rng.randf_range(-ZONE_HALF.y + 0.6, ZONE_HALF.y - 0.6))
		var crowd := 0.0
		for it: Dictionary in _items:
			if int(it["carrier"]) < 0 and not it["in_net"]:
				var dd := Vector2((it["pos"] as Vector3).x - c.x, (it["pos"] as Vector3).z - c.z).length()
				crowd += maxf(0.0, 1.2 - dd)
		var v := crowd * 3.0 + Vector2(c.x - zc.x, c.z - zc.y).length() * 0.25
		if v < bv:
			bv = v
			best = c
	return best


func _zone_of(p: Vector3) -> int:
	for s in _zones:
		var zc: Vector2 = _zones[s]
		if absf(p.x - zc.x) < ZONE_HALF.x and absf(p.z - zc.y) < ZONE_HALF.y:
			return s
	return -1


func _is_done() -> bool:
	return time_left <= 0.0


func _ranking() -> Array:
	var order := players.duplicate()
	order.shuffle()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(scores.get(int(a["slot"]), 0)) > int(scores.get(int(b["slot"]), 0)))
	return order


## 온라인: 화물마다 [x, y, z, 든 사람, 방향, 그물 속] + 각자 든 화물 (방장 → 손님)
func _net_state() -> Dictionary:
	var its := []
	for it: Dictionary in _items:
		var p: Vector3 = it["pos"]
		its.append([int(it["id"]), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), int(it["carrier"]), snappedf(float(it["yaw"]), 0.01), 1 if it["in_net"] else 0])
	return {"el": _elapsed, "it": its, "ca": _carry}


func _net_apply(st: Dictionary) -> void:
	_elapsed = float(st.get("el", _elapsed))
	for v: Array in st.get("it", []):
		var it := _item(int(v[0]))
		if it.is_empty():
			continue
		it["pos"] = Vector3(float(v[1]), float(v[2]), float(v[3]))
		it["carrier"] = int(v[4])
		it["yaw"] = float(v[5])
		it["in_net"] = int(v[6]) == 1
	var ca: Dictionary = st.get("ca", {})
	for s in ca:
		_carry[int(s)] = int(ca[s])
		if walkers.has(int(s)):
			var cid := int(ca[s])
			var it2 := _item(cid)
			walkers[int(s)]["speed"] = float(KINDS[it2["kind"]]["speed"]) if not it2.is_empty() else WALK


func _score_text(p: Dictionary) -> String:
	return tr("%d pts") % int(scores.get(int(p["slot"]), 0))
