extends Node3D
## 3D 튜토리얼 보드 세상 (말이 직접 들어가 걷는 바다 밑 보드).
## 전부 코드로 만들어요: 바닥, 칸, 길(돌길·계단·다리), 협곡 위 돌기둥 징검다리, 바위 아치 터널,
## 산호 언덕, 화산 분수, 다시마, 물방울, 빛줄기, 보드판 테두리.
##
## 지도 구조 (위에서 본 모습, 북쪽이 위):
##   가운데 START 광장에서 북·서·동 세 갈래 지름길
##   북→서: 산호 언덕 (계단으로 올라갔다 내려옴)
##   서→남: 바위 아치 터널
##   남→동: 협곡 위 나무다리
##   동→북: 협곡 위 돌기둥 징검다리 (칸 사이가 멀리 떨어짐)
##   골인 없음.
##
## 칸 종류 (kind):
##   plain    일반 칸 — 아무 일도 없음
##   chance   찬스 칸 — 랜덤 찬스 카드 (카드 내용은 나중에)
##   minigame 미니게임 칸 — 가장 많음
##   portal   포탈 칸 — 짝이 되는 반대편 포탈로 이동 (portal_partner())
##   shop     상점 칸 — 옆에 가게 노점 (상품은 나중에)
##   junction 갈림길, start 시작 광장
## 칸 배치는 아래 ROUTES 의 "tiles" 에서 길마다 순서대로 정해요.

const FloorShader := preload("res://shaders/sea_floor.gdshader")
const SandAlbedo := preload("res://textures/seabed/sand_albedo.png")
const SandNormal := preload("res://textures/seabed/sand_normal.png")
const StoneAlbedo := preload("res://textures/seabed/stone_albedo.png")
const StoneNormal := preload("res://textures/seabed/stone_normal.png")
const StructShader := preload("res://shaders/structure.gdshader")
const RockAlbedo := preload("res://textures/seabed/rock_albedo.png")
const RockNormal := preload("res://textures/seabed/rock_normal.png")
const TileShader := preload("res://shaders/tile_top.gdshader")
const KelpShader := preload("res://shaders/kelp3d.gdshader")
const RayShader := preload("res://shaders/light_ray.gdshader")
const PortalShader := preload("res://shaders/portal_top.gdshader")
const MeshKit := preload("res://scripts/world3d/mesh_kit.gd")
const ReefKit := preload("res://scripts/world3d/reef_kit.gd")
const SeagrassShader := preload("res://shaders/seagrass3d.gdshader")
const FishShader := preload("res://shaders/fish3d.gdshader")
const AnemoneShader := preload("res://shaders/anemone3d.gdshader")
const RockShader := preload("res://shaders/reef_rock.gdshader")
const BrainShader := preload("res://shaders/brain_coral.gdshader")
const SkyShader := preload("res://shaders/underwater_sky.gdshader")
const FAN_TEX := preload("res://textures/decor/sea_fan.png")
const KrakenArmShader := preload("res://shaders/kraken_arm.gdshader")
const KrakenBodyShader := preload("res://shaders/kraken_body.gdshader")
const KrakenEyeShader := preload("res://shaders/kraken_eye.gdshader")
const KRAKEN_BODY := preload("res://models/kraken_body.obj")
const DangerShader := preload("res://shaders/danger_mark.gdshader")
const ICONS := {
	"plain": preload("res://textures/tiles/icon_plain.png"),
	"chance": preload("res://textures/tiles/icon_chance.png"),
	"minigame": preload("res://textures/tiles/icon_minigame.png"),
	"portal": preload("res://textures/tiles/icon_portal.png"),
	"shop": preload("res://textures/tiles/icon_shop.png"),
	"junction": preload("res://textures/tiles/icon_arrows.png"),
	"start": preload("res://textures/tiles/icon_start.png"),
	"coin_plus": preload("res://textures/tiles/icon_coin_plus.png"),
	"coin_minus": preload("res://textures/tiles/icon_coin_minus.png"),
	"treasure": preload("res://textures/tiles/icon_treasure.png"),
	"supply": preload("res://textures/tiles/icon_supply.png"),
	"urchin": preload("res://textures/tiles/icon_urchin.png"),
	"whirlpool": preload("res://textures/tiles/icon_whirlpool.png"),
	"heal": preload("res://textures/tiles/icon_heal.png"),
	"boss": preload("res://textures/tiles/icon_boss.png"),
}
const BORDER_TEX := preload("res://textures/tiles/icon_border.png")
const CHANCE_CARD_TEX := preload("res://textures/tiles/card_chance.png")
const TILE_COLORS := {
	"plain": Color(0.84, 0.82, 0.72), "chance": Color(0.98, 0.72, 0.2), "minigame": Color(0.26, 0.58, 0.9),
	"portal": Color(0.58, 0.38, 0.92), "shop": Color(0.94, 0.43, 0.56),
	"junction": Color(0.8, 0.82, 0.77), "start": Color(0.5, 0.64, 0.62),
	"coin_plus": Color(0.3, 0.76, 0.4), "coin_minus": Color(0.86, 0.3, 0.32),
	"treasure": Color(0.96, 0.74, 0.22), "supply": Color(0.62, 0.44, 0.26), "urchin": Color(0.48, 0.2, 0.52),
	"whirlpool": Color(0.16, 0.48, 0.78), "heal": Color(0.36, 0.8, 0.74), "boss": Color(0.3, 0.06, 0.12),
}
const INK_COLORS := {
	"plain": Color(1, 1, 1), "chance": Color(1.0, 0.98, 0.9), "minigame": Color(0.95, 0.98, 1.0),
	"portal": Color(1, 1, 1), "shop": Color(1.0, 0.96, 0.97),
	"junction": Color(0.84, 0.63, 0.2), "start": Color(0.84, 0.63, 0.2),
	"coin_plus": Color(1, 1, 1), "coin_minus": Color(1, 1, 1),
	"treasure": Color(1.0, 0.98, 0.9), "supply": Color(1.0, 0.93, 0.8), "urchin": Color(1.0, 0.9, 1.0),
	"whirlpool": Color(0.9, 0.98, 1.0), "heal": Color(1, 1, 1), "boss": Color(1.0, 0.82, 0.3),
}
## 범례 순서 + 화면에 보일 이름 (번역 키)
const KIND_ORDER := ["plain", "chance", "minigame", "portal", "shop"]
const KIND_NAMES := {
	"plain": "Plain", "chance": "Chance", "minigame": "Minigame", "portal": "Portal", "shop": "Shop",
	"coin_plus": "Lucky +5", "coin_minus": "Trap -5",
	"treasure": "Treasure", "supply": "Supply Crate", "urchin": "Sea Urchin", "whirlpool": "Whirlpool",
	"heal": "Air Bubble", "boss": "Kraken's Lair",
}
## 협동 원정 범례 순서
const COOP_KIND_ORDER := ["plain", "treasure", "supply", "heal", "shop", "urchin", "whirlpool", "boss"]

const BoardMaps := preload("res://scripts/world3d/board_maps.gd")
const STEP := 0.5             ## 바닥 격자 간격
const TILE := 2.2
const TILE_H := 0.45
const PLAZA := 6.0

## 어떤 맵을 만들지 (add_child 전에 정함): "tutorial" / "sunken_island"
var map_id := "tutorial"
var cfg: Dictionary = {}
var half_w := 28.0            ## 판 가로 반
var half_d := 24.0            ## 판 세로 반
var spacing := 3.4
var start_pos := Vector3.ZERO
var plateaus: Array = []
var chasms: Array = []
var volcanoes: Array = []
var arches: Array = []
var zoom_max := 4.5           ## 카메라가 가장 멀리 (보드 전체)
var overview := Vector3(0, 0, 1.5)
var overview_zoom := 3.4

var spaces: Array = []        ## {pos: Vector3 (칸 윗면 가운데), kind, links: Array[int], yaw}
var start_index := 0
var _rng := RandomNumberGenerator.new()
var _mats := {}
var _blocked: Array = []      ## 장식을 놓지 않을 자리 [Vector2 중심, 반지름]
var _blocked_grid := {}
var _spinners: Array = []     ## 빙글빙글 도는 찬스 카드 {node, base_y, phase}
var _portal_fx: Array = []    ## 포탈 고리 {node, mat, light, phase}
var _critters: Array = []     ## 큰 원을 그리며 헤엄치는 바다거북 · 가오리
var _rotors: Array = []       ## 빙글빙글 도는 것 [Node3D, 속도] (등대 불빛 …)
var _glows: Array = []        ## 깜빡이며 빛나는 재질 [재질, 기본 세기, 위상]
var _jellies: Array = []      ## 해파리 {node, base, phase}
var trophy_tile := -1         ## 트로피가 떠 있는 칸 (-1 = 없음)
var _trophy_node: Node3D
var _meshes := {}
var _time := 0.0
var _grid := {}               ## 칸 빨리 찾기: 칸 좌표 → 칸 번호들
var _link_grid := {}          ## 길 빨리 찾기: 칸 좌표 → [a, b] 목록
const GRID := 8.0


func _ready() -> void:
	_rng.seed = 7
	cfg = BoardMaps.get_map(map_id)
	half_w = cfg["half"].x
	half_d = cfg["half"].y
	spacing = cfg["spacing"]
	start_pos = cfg["start"]
	plateaus = cfg["plateaus"]
	chasms = cfg["chasms"]
	volcanoes = cfg["volcanoes"]
	arches = cfg["arches"]
	zoom_max = cfg["zoom_max"]
	overview = cfg["overview"]
	overview_zoom = cfg["overview_zoom"]
	_build_spaces()
	_build_grids()
	_environment()
	_floor()
	_board_rim()
	_tiles()
	_connectors()
	_landmarks()
	_tile_props()
	_decor()
	_effects()
	_outer_seabed()
	_sea_life()


# ── 칸 배치 ──────────────────────────────────────────────────
func _catmull(pts: Array, per: int) -> Array:
	var out := []
	var p := [pts[0]] + pts + [pts[pts.size() - 1]]
	for i in range(1, p.size() - 2):
		var p0: Vector3 = p[i - 1]
		var p1: Vector3 = p[i]
		var p2: Vector3 = p[i + 1]
		var p3: Vector3 = p[i + 2]
		for s in per:
			var t := float(s) / per
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out


func _node_at(p: Vector3, kind: String, yaw: float) -> int:
	for i in spaces.size():
		var q: Vector3 = spaces[i]["base"]
		if Vector2(q.x - p.x, q.z - p.z).length() < 0.5:
			return i
	spaces.append({"base": p, "kind": kind, "links": [], "next": [], "yaw": yaw, "bridge": false})
	return spaces.size() - 1


func _build_spaces() -> void:
	_node_at(start_pos, "start", 0.0)
	var fill: Array = cfg["fill"]
	var routes: Array = cfg["routes"]
	for ri in routes.size():
		var r: Dictionary = routes[ri]
		var style: String = r.get("style", "")
		var rough := style == "rough"
		var wig: float = r.get("wiggle", 0.0)
		var kinds: Array = r.get("tiles", [])
		var k := 0
		var curve := _catmull(r["pts"], 24)
		var cum := [0.0]
		for i in range(1, curve.size()):
			var a: Vector3 = curve[i - 1]
			var b: Vector3 = curve[i]
			cum.append(cum[i - 1] + Vector2(b.x - a.x, b.z - a.z).length())
		var total: float = cum[cum.size() - 1]
		var sp: float = r.get("spacing", spacing)
		var n := maxi(1, int(round(total / sp)))
		var ids := []
		for j in n + 1:
			var d := total * j / n
			if rough and j != 0 and j != n:
				d += (_hash(ri, j, 1) - 0.5) * 0.9      # 험한 길은 간격도 들쭉날쭉
			var idx := 0
			while idx < cum.size() - 2 and cum[idx + 1] < d:
				idx += 1
			var seg_len: float = maxf(cum[idx + 1] - cum[idx], 0.0001)
			var f: float = (d - cum[idx]) / seg_len
			var p: Vector3 = (curve[idx] as Vector3).lerp(curve[idx + 1], f)
			var dir: Vector3 = (curve[mini(idx + 1, curve.size() - 1)] as Vector3) - (curve[idx] as Vector3)
			var yaw := atan2(dir.x, dir.z)
			if j == 0:
				p = r["pts"][0]
			elif j == n:
				p = r["pts"][r["pts"].size() - 1]
			elif Vector2(p.x - start_pos.x, p.z - start_pos.z).length() < PLAZA * 0.5 + 1.9:
				continue
			else:
				# 길 모양 흔들기 (구불구불 · 험한 길)
				var side := Vector3(dir.z, 0, -dir.x).normalized()
				var off := 0.0
				var dy := 0.0
				if wig > 0.0:
					off = wig * sin(j * 1.9 + ri)
				if rough:
					off = (_hash(ri, j, 2) - 0.5) * 1.4
					dy = _hash(ri, j, 3) * 1.1 - 0.2
					yaw += (_hash(ri, j, 4) - 0.5) * 0.7
				p += side * off + Vector3(0, dy, 0)
			# 배 갑판 위 칸은 갑판 높이에 딱 맞춤 (곡선이 살짝 출렁여도)
			if r.get("deck", false) and j != 0 and j != n:
				var dh := 0.0
				for q in r["pts"]:
					dh = maxf(dh, (q as Vector3).y)
				if p.y > dh - 0.8:
					p.y = dh
			var kind := "space"
			if j != 0 and j != n:
				if k < kinds.size():
					kind = kinds[k]
				elif r.has("fill"):
					var rf: Array = r["fill"]
					kind = rf[k % rf.size()]
				else:
					kind = fill[(k + ri * 3) % fill.size()]
				k += 1
			elif j == n and r.has("end"):
				kind = r["end"]
			var id := _node_at(p, kind, yaw)
			if r.get("bridge", false):
				spaces[id]["bridge"] = true
			if r.get("deck", false) and p.y > 1.0:
				spaces[id]["deck"] = true
			if rough and j != 0 and j != n:
				spaces[id]["rough"] = true
			ids.append(id)
		for j in ids.size() - 1:
			var a: int = ids[j]
			var b: int = ids[j + 1]
			if not spaces[a]["links"].has(b):
				spaces[a]["links"].append(b)
				spaces[b]["links"].append(a)
			if not spaces[a]["next"].has(b):
				spaces[a]["next"].append(b)      # 한 방향 길 (협동 원정: route 순서대로만 앞으로)
	for sp in spaces:
		if sp["kind"] == "space":
			sp["kind"] = "junction" if sp["links"].size() > 2 else "plain"
		if sp["kind"] != "start" and sp["kind"] != "boss" and sp["links"].size() > 2:
			sp["kind"] = "junction"
			sp["yaw"] = 0.0
		var top_h: float = PLAZA * 0.0 + (0.5 if sp["kind"] == "start" else TILE_H)
		sp["pos"] = (sp["base"] as Vector3) + Vector3(0, top_h, 0)
	# 맵이 정해 둔 특별 칸 (가장 가까운 평범한 칸을 바꿈)
	var pairs := {}
	for sp_def in cfg["specials"]:
		var at: Vector2 = sp_def["at"]
		var best := -1
		var bd := INF
		for i in spaces.size():
			var kd: String = spaces[i]["kind"]
			if kd == "start" or kd == "junction" or spaces[i].has("special"):
				continue
			var b: Vector3 = spaces[i]["base"]
			var d := Vector2(b.x - at.x, b.z - at.y).length()
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			spaces[best]["kind"] = sp_def["kind"]
			spaces[best]["special"] = true
			if sp_def.has("pair"):
				if not pairs.has(sp_def["pair"]):
					pairs[sp_def["pair"]] = []
				pairs[sp_def["pair"]].append(best)
	for k in pairs:
		var pr: Array = pairs[k]
		if pr.size() == 2:
			spaces[pr[0]]["partner"] = pr[1]
			spaces[pr[1]]["partner"] = pr[0]
	# 짝이 안 정해진 포탈은 나온 순서대로 둘씩 짝
	var loose := []
	for i in spaces_of_kind("portal"):
		if not spaces[i].has("partner"):
			loose.append(i)
	for i in range(0, loose.size() - 1, 2):
		spaces[loose[i]]["partner"] = loose[i + 1]
		spaces[loose[i + 1]]["partner"] = loose[i]


## 늘 같은 값이 나오는 0~1 난수 (맵 모양이 매번 같도록)
func _hash(a: int, b: int, k: int) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233 + k * 37.719) * 43758.5453, 1.0)


# ── 높이 ─────────────────────────────────────────────────────
func _noise2(x: float, z: float) -> float:
	return sin(x * 0.31 + sin(z * 0.17) * 1.3) * 0.5 + sin(z * 0.27 + sin(x * 0.21) * 1.7) * 0.5


func natural_height(x: float, z: float) -> float:
	var h := _noise2(x, z) * 0.35 + sin(x * 0.9 + z * 0.4) * 0.05
	# 언덕 · 섬
	for pl in plateaus:
		var c: Vector2 = pl["c"]
		var r: Vector2 = pl["r"]
		var pd := Vector2((x - c.x) / r.x, (z - c.y) / r.y).length()
		pd += _noise2(x * 2.0, z * 2.0) * 0.06
		h += float(pl["h"]) * smoothstep(1.08, 0.92, pd)
	# 협곡
	for ch in chasms:
		var cc: Vector2 = ch["c"]
		var rr: Vector2 = ch["r"]
		var cd := Vector2((x - cc.x) / rr.x, (z - cc.y) / rr.y).length() + _noise2(x * 2.3, z * 2.3) * 0.07
		h -= float(ch["depth"]) * smoothstep(1.05, 0.8, cd)
	# 화산
	for v in volcanoes:
		var at: Vector2 = v["at"]
		var vr: float = v["r"]
		var vd := Vector2(x - at.x, z - at.y).length()
		h += pow(clampf(1.0 - vd / vr, 0.0, 1.0), 1.3) * float(v["h"]) - exp(-pow(vd / (vr * 0.21), 2.0)) * float(v["h"]) * 0.64
	return h


func _in_chasm(x: float, z: float) -> bool:
	return natural_height(x, z) < -1.5


func ground_height(x: float, z: float) -> float:
	var h := natural_height(x, z)
	if h < -1.5:
		return h
	# 칸 근처는 칸 높이에 맞춰 평평하게, 칸 사이 길은 두 칸 높이를 잇는 경사로로 땅을 깎거나 돋움
	# (그래서 계단이 언덕에 박혀 있는 것처럼 자연스럽게 놓임). 배 갑판 위 칸은 제외
	var best_w := 0.0
	var target := 0.0
	for i in _near(x, z):
		var sp: Dictionary = spaces[i]
		if sp.get("deck", false):
			continue
		var b: Vector3 = sp["base"]
		var r := PLAZA * 0.75 if sp["kind"] == "start" else 2.4
		var d := Vector2(x - b.x, z - b.z).length()
		if d < r * 1.6:
			var w := smoothstep(r * 1.6, r * 0.7, d)
			if w > best_w:
				best_w = w
				target = b.y - 0.05
	for pair in _near_links(x, z):
		var sa: Dictionary = spaces[pair[0]]
		var sb: Dictionary = spaces[pair[1]]
		if sa.get("deck", false) or sb.get("deck", false):
			continue
		var a: Vector3 = sa["base"]
		var b: Vector3 = sb["base"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var t := clampf(Vector2(x - a.x, z - a.z).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := Vector2(x - a.x, z - a.z).distance_to(ab * t)
		var ty := lerpf(a.y, b.y, t) - 0.08
		# 깎아 내는 곳은 넓게 (계단이 언덕 속으로 파고듦), 메우는 곳은 좁게 (둑이 툭 튀어나오지 않게)
		var reach := 2.6 if ty < h else 1.7
		if d < reach:
			var w := smoothstep(reach, 0.85, d)
			if w > best_w:
				best_w = w
				target = ty
	return lerpf(h, target, best_w)


## 칸 · 길을 칸 좌표로 나눠 둠 (넓은 맵에서도 빠르게)
func _build_grids() -> void:
	_grid.clear()
	_link_grid.clear()
	for i in spaces.size():
		var b: Vector3 = spaces[i]["base"]
		var key := Vector2i(floori(b.x / GRID), floori(b.z / GRID))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)
		for j in spaces[i]["links"]:
			if j < i:
				continue
			var a2 := Vector2(b.x, b.z)
			var bb: Vector3 = spaces[j]["base"]
			var b2 := Vector2(bb.x, bb.z)
			var lo := Vector2i(floori(minf(a2.x, b2.x) / GRID), floori(minf(a2.y, b2.y) / GRID))
			var hi := Vector2i(floori(maxf(a2.x, b2.x) / GRID), floori(maxf(a2.y, b2.y) / GRID))
			for gx in range(lo.x, hi.x + 1):
				for gz in range(lo.y, hi.y + 1):
					var k2 := Vector2i(gx, gz)
					if not _link_grid.has(k2):
						_link_grid[k2] = []
					_link_grid[k2].append([i, j])


## (x, z) 근처(이웃 칸 좌표 포함) 칸 번호들
func _near(x: float, z: float) -> Array:
	var out := []
	var cx := floori(x / GRID)
	var cz := floori(z / GRID)
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var k := Vector2i(gx, gz)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


func _near_links(x: float, z: float) -> Array:
	var out := []
	var cx := floori(x / GRID)
	var cz := floori(z / GRID)
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var k := Vector2i(gx, gz)
			if _link_grid.has(k):
				out.append_array(_link_grid[k])
	return out


## (x, z) 에서 가장 가까운 길 위의 점과 그 길 방향 [Vector2 점, Vector2 방향]
func _path_point(x: float, z: float) -> Array:
	var best := Vector2(x, z)
	var bdir := Vector2(0, 1)
	var bd := INF
	for pair in _near_links(x, z):
		var a: Vector3 = spaces[pair[0]]["base"]
		var b: Vector3 = spaces[pair[1]]["base"]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((Vector2(x, z) - a2).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var q := a2 + ab * t
		var d := q.distance_to(Vector2(x, z))
		if d < bd:
			bd = d
			best = q
			bdir = ab.normalized()
	return [best, bdir]


# ── 재질 ─────────────────────────────────────────────────────
func _mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	# 매끈하지 않은 재질(돌 · 회벽 · 나무)은 풍화된 표면 결을 입힘 (세 방향에서 — UV 없는 도형에도 고르게)
	if rough >= 0.6 and metal < 0.5 and c.a >= 1.0:
		m.albedo_texture = _mip_tex(StoneAlbedo)
		m.normal_enabled = true
		m.normal_texture = _mip_tex(StoneNormal)
		m.normal_scale = 0.9
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE * 0.4
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## 구조물 · 장식품 재질 (shaders/structure.gdshader): 돌 결 + 종류별 무늬 + 이끼 · 물때
const SKIND := {"stone": 0, "masonry": 1, "wood": 2, "roof": 3, "column": 4, "bone": 5, "paint": 6, "coral": 7, "clay": 8, "iron": 9}
func _smat(c: Color, kind: String, radial: float = 0.0, moss_amt: float = 0.6) -> ShaderMaterial:
	var key := "s_%s_%s_%.2f_%.2f" % [c.to_html(), kind, radial, moss_amt]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = StructShader
	m.set_shader_parameter("base", c)
	m.set_shader_parameter("kind", int(SKIND[kind]))
	m.set_shader_parameter("radial", radial)
	m.set_shader_parameter("moss", moss_amt)
	m.set_shader_parameter("det_tex", _mip_tex(StoneAlbedo))
	m.set_shader_parameter("det_nrm", _mip_tex(StoneNormal))
	_mats[key] = m
	return m


## 통나무 · 통널 한 장 (틈 없이, 결이 axis 방향으로 흐름)
func _wood(c: Color, axis: Vector3, moss_amt: float = 0.3) -> ShaderMaterial:
	var key := "w_%s_%s_%.2f" % [c.to_html(), axis, moss_amt]
	if _mats.has(key):
		return _mats[key]
	var m := _smat(c, "wood", 0.0, moss_amt).duplicate() as ShaderMaterial
	m.set_shader_parameter("grain", axis)
	m.set_shader_parameter("plank_w", 0.0)
	_mats[key] = m
	return m


## 두 점을 잇는 막대 (밧줄 · 쇠막대)
func _rod(a: Vector3, b: Vector3, r: float, mat: Material, parent: Node = null, segs: int = 6, r2: float = -1.0) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	var z := x.cross(y)
	_mi(_cyl(r if r2 < 0.0 else r2, r, l, segs), mat, (a + b) * 0.5, Basis(x, y, z), parent)


## 세모 기둥 (박공벽): 길이 ln (x), 밑변 w (z), 높이 h (y)
func _prism(w: float, h: float, ln: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := ln * 0.5
	var a0 := Vector3(-hx, 0, -w * 0.5)
	var b0 := Vector3(-hx, 0, w * 0.5)
	var c0 := Vector3(-hx, h, 0)
	var a1 := Vector3(hx, 0, -w * 0.5)
	var b1 := Vector3(hx, 0, w * 0.5)
	var c1 := Vector3(hx, h, 0)
	ReefKit._tri(st, a0, b0, c0, Vector3(-1, 0, 0))
	ReefKit._tri(st, a1, b1, c1, Vector3(1, 0, 0))
	ReefKit._tri(st, a0, c0, c1, Vector3(0, 0.5, -1))
	ReefKit._tri(st, a0, c1, a1, Vector3(0, 0.5, -1))
	ReefKit._tri(st, b0, c0, c1, Vector3(0, 0.5, 1))
	ReefKit._tri(st, b0, c1, b1, Vector3(0, 0.5, 1))
	st.generate_normals()
	return st.commit()


func _mi(mesh: Mesh, mat: Material, pos: Vector3, basis_: Basis = Basis(), parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis_, pos)
	(parent if parent else self).add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r_top: float, r_bot: float, h: float, segs: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	# 둥근 것은 각져 보이지 않게 (4 · 6 · 7 각처럼 일부러 각진 것은 그대로)
	c.radial_segments = maxi(segs, 32) if segs >= 10 else segs
	c.rings = 2
	return c


# ── 환경 ─────────────────────────────────────────────────────
func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SkyShader
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.52, 0.56)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.22, 0.27)
	env.fog_density = float(cfg.get("fog", 0.012))
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	# 물속 뿌연 빛 (Forward+ 에서만 보임): 햇빛이 물 속에서 기둥처럼 비침
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0045
	env.volumetric_fog_albedo = Color(0.22, 0.5, 0.55)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_ambient_inject = 0.15
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.12
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_angular_distance = 1.5
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 0.8
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 70.0 if half_w < 30.0 else 110.0
	add_child(sun)
	# 그림자 쪽을 살짝 밝혀 주는 물빛 반사광
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.28
	fill.light_color = Color(0.45, 0.85, 0.85)
	add_child(fill)


# ── 바닥 ─────────────────────────────────────────────────────
func _floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(half_w * 2.0 / STEP)
	var nz := int(half_d * 2.0 / STEP)
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := -half_w + i * STEP
			var z := -half_d + j * STEP
			hs[j * (nx + 1) + i] = ground_height(x, z)
	for j in nz + 1:
		for i in nx + 1:
			var x := -half_w + i * STEP
			var z := -half_d + j * STEP
			var hl := hs[j * (nx + 1) + maxi(i - 1, 0)]
			var hr := hs[j * (nx + 1) + mini(i + 1, nx)]
			var hd := hs[maxi(j - 1, 0) * (nx + 1) + i]
			var hu := hs[mini(j + 1, nz) * (nx + 1) + i]
			st.set_normal(Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized())
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, hs[j * (nx + 1) + i], z))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)
	var m := ShaderMaterial.new()
	m.shader = FloorShader
	m.set_shader_parameter("path_mask", _path_mask())
	m.set_shader_parameter("board_rect", Vector4(-half_w, -half_d, half_w * 2.0, half_d * 2.0))
	_set_sand(m)
	_mi(st.commit(), m, Vector3.ZERO)


## 고해상도 모래 · 바위 텍스처 (밉맵을 직접 만들어서 멀리서도 지글거리지 않게)
var _tex_cache := {}
func _mip_tex(t: Texture2D) -> ImageTexture:
	if not _tex_cache.has(t):
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		_tex_cache[t] = ImageTexture.create_from_image(img)
	return _tex_cache[t]


func _set_sand(m: ShaderMaterial) -> void:
	m.set_shader_parameter("sand_albedo", _mip_tex(SandAlbedo))
	m.set_shader_parameter("sand_normal", _mip_tex(SandNormal))


## 바닥에 칠할 길 자국(R)과 칸 둘레 그늘(G) 그림. 1m 에 6 픽셀
func _path_mask() -> ImageTexture:
	const PX := 6.0
	var w := int(half_w * 2.0 * PX)
	var hgt := int(half_d * 2.0 * PX)
	var data := PackedByteArray()
	data.resize(w * hgt * 2)
	data.fill(0)
	var done := {}
	for i in spaces.size():
		var a: Vector3 = spaces[i]["base"]
		# 칸 둘레 그늘 (칸 방향으로 돌린 네모)
		var half := (PLAZA * 0.5 + 0.3) if spaces[i]["kind"] == "start" else (TILE * 0.5 + 0.18)
		var yaw: float = spaces[i]["yaw"]
		var cs := cos(yaw)
		var sn := sin(yaw)
		var reach := half * 1.42 + 0.8
		for py in range(maxi(0, int((a.z - reach + half_d) * PX)), mini(hgt, int((a.z + reach + half_d) * PX) + 1)):
			for px in range(maxi(0, int((a.x - reach + half_w) * PX)), mini(w, int((a.x + reach + half_w) * PX) + 1)):
				var dx := (px + 0.5) / PX - half_w - a.x
				var dz := (py + 0.5) / PX - half_d - a.z
				var lx := absf(dx * cs - dz * sn)
				var lz := absf(dx * sn + dz * cs)
				var db := maxf(lx, lz) - half
				var v := int(255.0 * smoothstep(0.8, -0.05, db))
				var k := (py * w + px) * 2 + 1
				if v > data[k]:
					data[k] = v
		for j in spaces[i]["links"]:
			var key := "%d_%d" % [mini(i, j), maxi(i, j)]
			if done.has(key):
				continue
			done[key] = true
			var b: Vector3 = spaces[j]["base"]
			if spaces[i].get("deck", false) and spaces[j].get("deck", false):
				continue
			var a2 := Vector2(a.x, a.z)
			var ab := Vector2(b.x, b.z) - a2
			var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(1.8, 1.8)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(1.8, 1.8)
			for py in range(maxi(0, int((lo.y + half_d) * PX)), mini(hgt, int((hi.y + half_d) * PX) + 1)):
				for px in range(maxi(0, int((lo.x + half_w) * PX)), mini(w, int((hi.x + half_w) * PX) + 1)):
					var q := Vector2((px + 0.5) / PX - half_w, (py + 0.5) / PX - half_d)
					var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
					var d := (q - a2).distance_to(ab * t)
					var v := int(255.0 * smoothstep(1.6, 0.7, d))
					var k := (py * w + px) * 2
					if v > data[k]:
						data[k] = v
	var img := Image.create_from_data(w, hgt, false, Image.FORMAT_RG8, data)
	return ImageTexture.create_from_image(img)


func _board_rim() -> void:
	var lacquer := _mat(Color(0.04, 0.2, 0.26), 0.22)
	var gold := _mat(Color(0.95, 0.76, 0.34), 0.25, 0.85)
	var t := 1.2
	for side in [[Vector3(0, 0.2, -half_d - t / 2), Vector3(half_w * 2 + t * 2, 1.6, t)],
			[Vector3(0, 0.2, half_d + t / 2), Vector3(half_w * 2 + t * 2, 1.6, t)],
			[Vector3(-half_w - t / 2, 0.2, 0), Vector3(t, 1.6, half_d * 2)],
			[Vector3(half_w + t / 2, 0.2, 0), Vector3(t, 1.6, half_d * 2)]]:
		_mi(_rbox(side[1], 0.18), lacquer, side[0])
		var inlay: Vector3 = side[1]
		inlay = Vector3(maxf(inlay.x - 0.6, 0.15) if inlay.x > 2 else 0.15, 0.05, maxf(inlay.z - 0.6, 0.15) if inlay.z > 2 else 0.15)
		_mi(_box(inlay), gold, (side[0] as Vector3) + Vector3(0, 0.81, 0))
	# 모서리 장식 구슬
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var sp := SphereMesh.new()
			sp.radius = 0.55
			sp.height = 1.1
			_mi(sp, gold, Vector3(cx * (half_w + t / 2), 1.3, cz * (half_d + t / 2)))
	# 판 아래 받침
	_mi(_box(Vector3(half_w * 2 + t * 2, 2.0, half_d * 2 + t * 2)), lacquer, Vector3(0, -8.0, 0))


# ── 칸 ───────────────────────────────────────────────────────
func _tile_top_mat(kind: String) -> ShaderMaterial:
	var key := "tile_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	if kind == "portal":
		m.shader = PortalShader
		m.set_shader_parameter("border_tex", BORDER_TEX)
		_mats[key] = m
		return m
	m.shader = TileShader
	m.set_shader_parameter("tile_color", TILE_COLORS[kind])
	m.set_shader_parameter("ink_color", INK_COLORS[kind])
	m.set_shader_parameter("icon_tex", _mip_tex(ICONS[kind]))
	m.set_shader_parameter("border_tex", _mip_tex(BORDER_TEX))
	m.set_shader_parameter("icon_scale", 0.8 if kind == "start" else 0.62)
	_mats[key] = m
	return m


## 둥근 상자 (같은 크기는 한 번만 만들어 씀)
func _rbox(size: Vector3, r: float) -> ArrayMesh:
	var key := "rb_%s_%.2f" % [size, r]
	if not _meshes.has(key):
		_meshes[key] = MeshKit.rounded_box(size, r, false, 3)
	return _meshes[key]


func _tiles() -> void:
	var foot_m := _mat(Color(0.6, 0.57, 0.5), 0.8)
	var foot2_m := _mat(Color(0.7, 0.67, 0.58), 0.75)
	var gold := _mat(Color(0.95, 0.76, 0.34), 0.25, 0.85)
	var stud := SphereMesh.new()
	stud.radius = 0.08
	stud.height = 0.12
	stud.radial_segments = 10
	stud.rings = 5
	var stud_x := []
	for sp in spaces:
		var base: Vector3 = sp["base"]
		var kind: String = sp["kind"]
		var b := Basis(Vector3.UP, sp["yaw"])
		if kind == "start":
			_mi(_rbox(Vector3(PLAZA, 0.5, PLAZA), 0.22), _mat(Color(0.5, 0.6, 0.58), 0.35), base + Vector3(0, 0.25, 0), b)
			_mi(_rbox(Vector3(PLAZA + 0.6, 0.2, PLAZA + 0.6), 0.08), foot_m, base + Vector3(0, 0.1, 0), b)
			var top := PlaneMesh.new()
			top.size = Vector2(PLAZA - 0.5, PLAZA - 0.5)
			_mi(top, _tile_top_mat("start"), base + Vector3(0, 0.505, 0), b)
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					stud_x.append(Transform3D(Basis(), base + b * Vector3(cx * (PLAZA * 0.5 + 0.15), 0.21, cz * (PLAZA * 0.5 + 0.15))))
			continue
		var size := TILE + (0.2 if kind == "junction" else 0.0)
		var body_c: Color = Color(0.82, 0.82, 0.77) if kind == "junction" else (TILE_COLORS[kind] as Color).darkened(0.2)
		# 유약 바른 도자기 같은 칸 몸통 + 크림색 받침 + 금 장식
		var glaze := _mat(body_c, 0.32)
		glaze.clearcoat_enabled = true
		glaze.clearcoat = 0.7
		glaze.clearcoat_roughness = 0.1
		glaze.rim_enabled = true
		glaze.rim = 0.25
		sp["body_mi"] = _mi(_rbox(Vector3(size, TILE_H, size), 0.15), glaze, base + Vector3(0, TILE_H * 0.5, 0), b)
		# 받침돌 2 단 (넓고 낮은 단 + 칸 바로 아래 단) + 몸통 아래를 두른 금 띠
		_mi(_rbox(Vector3(size + 0.5, 0.12, size + 0.5), 0.05), foot_m, base + Vector3(0, 0.04, 0), b)
		_mi(_rbox(Vector3(size + 0.26, 0.14, size + 0.26), 0.06), foot2_m, base + Vector3(0, 0.13, 0), b)
		_mi(_rbox(Vector3(size + 0.05, 0.07, size + 0.05), 0.03), gold, base + Vector3(0, 0.225, 0), b)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				stud_x.append(Transform3D(Basis(), base + b * Vector3(cx * (size * 0.5 + 0.17), 0.11, cz * (size * 0.5 + 0.17))))
		var plane := PlaneMesh.new()
		plane.size = Vector2(size - 0.3, size - 0.3)
		# 윗면은 칸과 같은 방향 (그림은 셰이더가 늘 똑바로 세워 줌)
		sp["top_mi"] = _mi(plane, _tile_top_mat(kind), base + Vector3(0, TILE_H + 0.004, 0), b)
		# 협곡 위 칸은 돌기둥이 받침
		if _in_chasm(base.x, base.z):
			var depth := base.y - natural_height(base.x, base.z) + 0.5
			_mi(_cyl(0.85, 1.05, depth, 16), _rock_mat(0), base - Vector3(0, depth * 0.5, 0))
			_mi(_cyl(1.25, 0.9, 0.35, 16), _rock_mat(1), base + Vector3(0, -0.15, 0))
	_multi(stud, gold, stud_x)


# ── 길 (돌길 / 계단 / 다리 / 징검다리) ────────────────────────
func _connectors() -> void:
	var step_ms := [_mat(Color(0.62, 0.6, 0.53), 0.75), _mat(Color(0.57, 0.56, 0.5), 0.8), _mat(Color(0.66, 0.62, 0.54), 0.7)]
	var curb_m := _mat(Color(0.5, 0.5, 0.45), 0.85)
	var moss := _mat(Color(0.3, 0.47, 0.33), 0.95)
	var wood := _mat(Color(0.48, 0.33, 0.2), 0.8)
	var rope := _mat(Color(0.78, 0.68, 0.48), 0.9)
	var lantern_glow := _glow_mat(Color(0.4, 1.0, 0.8), 1.6)
	var flag := CylinderMesh.new()       # 길에 반쯤 묻힌 납작한 판석
	flag.top_radius = 0.36
	flag.bottom_radius = 0.33
	flag.height = 0.14
	flag.radial_segments = 7
	flag.rings = 1
	var flag_cols := [Color(0.47, 0.46, 0.41), Color(0.53, 0.5, 0.43), Color(0.42, 0.45, 0.41), Color(0.5, 0.48, 0.45)]
	var fl_x := []
	var fl_c := []
	var done := {}
	for i in spaces.size():
		for j in spaces[i]["links"]:
			var key := "%d_%d" % [mini(i, j), maxi(i, j)]
			if done.has(key):
				continue
			done[key] = true
			var a: Vector3 = spaces[i]["base"]
			var b: Vector3 = spaces[j]["base"]
			var ra := PLAZA * 0.5 if spaces[i]["kind"] == "start" else TILE * 0.5 + 0.18
			var rb := PLAZA * 0.5 if spaces[j]["kind"] == "start" else TILE * 0.5 + 0.18
			var flat := Vector3(b.x - a.x, 0, b.z - a.z)
			var dist := flat.length()
			var dir := flat / dist
			var p0 := a + dir * ra
			var p1 := b - dir * rb
			var gap := (p1 - p0)
			var glen := Vector2(gap.x, gap.z).length()
			if glen < 0.05:
				continue
			var yaw := atan2(dir.x, dir.z)
			var bas := Basis(Vector3.UP, yaw)
			var mid := (p0 + p1) * 0.5
			var over_chasm := _in_chasm(mid.x, mid.z)
			var dy := b.y - a.y
			if over_chasm:
				if spaces[i]["bridge"] and spaces[j]["bridge"]:
					_bridge(p0, p1, bas, glen, wood, rope)
				# 아니면 징검다리 — 아무것도 없이 뚝 떨어져 있음
				continue
			var deck_link: bool = spaces[i].get("deck", false) or spaces[j].get("deck", false)
			if deck_link:
				if absf(dy) > 0.2:
					_gangway(p0, p1, a.y + 0.05, b.y + 0.05, bas, glen, wood, rope)
				continue    # 갑판 위 칸끼리는 갑판 널빤지가 길
			var rough_link: bool = spaces[i].get("rough", false) or spaces[j].get("rough", false)
			if rough_link:
				_rough_link(p0, p1, a.y + TILE_H, b.y + TILE_H, bas, glen)
				continue
			if absf(dy) > 0.3:
				# 경사로에 박힌 돌계단 (땅도 같은 경사로 깎여 있음) + 양옆 낮은 돌턱
				var n := maxi(2, int(ceil(absf(dy) / 0.26)))
				for s in n:
					var f := (float(s) + 0.5) / n
					var pos := p0.lerp(p1, f)
					var top := lerpf(a.y + TILE_H * 0.6, b.y + TILE_H * 0.6, (float(s) + 1.0) / n) if dy > 0 else lerpf(a.y + TILE_H * 0.6, b.y + TILE_H * 0.6, float(s) / n)
					var ramp := lerpf(a.y, b.y, f)
					var low := minf(ramp, top) - 0.45
					var hgt := top - low
					var w := 1.55 + _rng.randf_range(-0.06, 0.06)
					var sb := bas.rotated(Vector3.UP, _rng.randf_range(-0.03, 0.03))
					_mi(_rbox(Vector3(w, hgt, glen / n + 0.04), 0.05), step_ms[s % step_ms.size()], Vector3(pos.x, low + hgt * 0.5, pos.z), sb)
					if _rng.randf() < 0.25:
						_mi(_rbox(Vector3(0.4, 0.03, glen / n * 0.7), 0.01), moss, Vector3(pos.x, top + 0.01, pos.z) + bas.x * _rng.randf_range(-0.5, 0.5), sb)
				# 높은 계단만 양옆 돌턱 (낮은 턱은 계단 몇 개로 충분)
				if absf(dy) > 1.2:
					var slope_len := Vector3(gap.x, dy, gap.z).length()
					var pitch := -atan2(dy, glen)
					for sd: float in [-1.0, 1.0]:
						var cpos := mid + bas.x * sd * 0.9 + Vector3(0, (a.y + b.y) * 0.5 - mid.y + TILE_H * 0.3, 0)
						_mi(_rbox(Vector3(0.28, 0.42, slope_len - 0.1), 0.08), curb_m, cpos, bas * Basis(Vector3(1, 0, 0), pitch))
				# 높은 계단 아래위에는 작은 돌 등불
				if absf(dy) > 1.2:
					for e: float in [0.12, 0.88]:
						var lp: Vector3 = p0.lerp(p1, e) + bas.x * 1.3
						var gy := ground_height(lp.x, lp.z)
						# 돌 등불: 받침 · 기둥 · 불 놓는 단 · 네 기둥 사이 불빛 · 지붕
						var lst := _smat(Color(0.56, 0.55, 0.5), "stone", 0.0, 0.5)
						_mi(_rbox(Vector3(0.42, 0.12, 0.42), 0.03), lst, Vector3(lp.x, gy + 0.06, lp.z), bas)
						_mi(_cyl(0.08, 0.12, 0.62, 10), lst, Vector3(lp.x, gy + 0.43, lp.z))
						_mi(_rbox(Vector3(0.4, 0.07, 0.4), 0.02), lst, Vector3(lp.x, gy + 0.77, lp.z), bas)
						for cx: float in [-1.0, 1.0]:
							for cz: float in [-1.0, 1.0]:
								_mi(_box(Vector3(0.05, 0.26, 0.05)), lst, Vector3(lp.x, gy + 0.93, lp.z) + bas * Vector3(cx * 0.15, 0, cz * 0.15), bas)
						var orb := SphereMesh.new()
						orb.radius = 0.1
						orb.height = 0.2
						_mi(orb, lantern_glow, Vector3(lp.x, gy + 0.92, lp.z))
						_mi(_cyl(0.0, 0.36, 0.2, 4), lst, Vector3(lp.x, gy + 1.16, lp.z), bas * Basis(Vector3.UP, PI / 4))
						_block(Vector2(lp.x, lp.z), 0.4)
				continue
			# 평평한 길: 다져진 길 자국은 바닥 셰이더가 그림. 여기엔 땅에 반쯤 묻힌 판석만 몇 개
			var cnt := maxi(1, int(glen / 0.9))
			for s in cnt:
				if _rng.randf() < 0.6:
					continue
				var f := (float(s) + _rng.randf_range(0.25, 0.75)) / cnt
				var pp := p0.lerp(p1, f) + bas.x * _rng.randf_range(-0.35, 0.35)
				var gy := ground_height(pp.x, pp.z)
				var sc := _rng.randf_range(0.55, 0.95)
				var tb := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc * _rng.randf_range(0.8, 1.2), 1.0, sc))
				fl_x.append(Transform3D(tb, Vector3(pp.x, gy - 0.05, pp.z)))
				fl_c.append(flag_cols[_rng.randi() % flag_cols.size()])
	if fl_x.size() > 0:
		var vm := StandardMaterial3D.new()
		vm.vertex_color_use_as_albedo = true
		vm.roughness = 0.8
		_multi(flag, vm, fl_x, fl_c)


## 배로 오르내리는 나무 발판 (널빤지 + 밧줄 난간)
func _gangway(p0: Vector3, p1: Vector3, y0: float, y1: float, bas: Basis, glen: float, wood: Material, rope: Material) -> void:
	var n := maxi(3, int(glen / 0.45))
	var pitch := -atan2(y1 - y0, glen)
	var pb := bas * Basis(Vector3(1, 0, 0), pitch)
	for s in n:
		var f := (float(s) + 0.5) / n
		var pos := p0.lerp(p1, f)
		_mi(_box(Vector3(1.3, 0.08, glen / n * 0.85)), _wood(Color(0.46, 0.32, 0.2), Vector3(1, 0, 0)), Vector3(pos.x, lerpf(y0, y1, f), pos.z), pb)
	for sd: float in [-1.0, 1.0]:
		var c := (p0 + p1) * 0.5 + bas.x * sd * 0.62
		_mi(_box(Vector3(0.1, 0.12, Vector3(glen, y1 - y0, 0).length())), wood, Vector3(c.x, (y0 + y1) * 0.5 - 0.06, c.z), pb)
		for e: float in [0.0, 1.0]:
			var q := p0.lerp(p1, e) + bas.x * sd * 0.62
			var y := lerpf(y0, y1, e)
			var gy := ground_height(q.x, q.z)
			_mi(_cyl(0.06, 0.07, y - gy + 0.8, 8), wood, Vector3(q.x, (y + 0.8 + gy) * 0.5, q.z))
		_mi(_cyl(0.025, 0.025, Vector3(glen, y1 - y0, 0).length(), 6), rope, Vector3(c.x, (y0 + y1) * 0.5 + 0.72, c.z), pb * Basis(Vector3(1, 0, 0), PI / 2))


## 험한 길: 울퉁불퉁한 바위 디딤돌이 칸 사이를 이어 줌 (높이 차가 크면 바위 계단)
func _rough_link(p0: Vector3, p1: Vector3, y0: float, y1: float, bas: Basis, glen: float) -> void:
	# 칸 받침과 겹치지 않게 양 끝을 조금 띄우고, 칸 윗면보다 살짝 낮게
	var inset := minf(0.3, glen * 0.2)
	var dirv := (p1 - p0).normalized()
	p0 += dirv * inset
	p1 -= dirv * inset
	glen = maxf(glen - inset * 2.0, 0.3)
	var n := maxi(1, int(ceil(glen / 0.8)))
	for s2 in n:
		var f := (float(s2) + 0.5) / n
		var pos := p0.lerp(p1, f)
		var top := lerpf(y0, y1, f) - 0.16
		var low := minf(natural_height(pos.x, pos.z), top - 0.3) - 0.2
		var hgt := top - low
		var w := _rng.randf_range(1.0, 1.45)
		var dd := glen / n * _rng.randf_range(0.82, 0.96)
		var jitter := bas.x * _rng.randf_range(-0.18, 0.18)
		var b := bas.rotated(Vector3.UP, _rng.randf_range(-0.12, 0.12))
		_mi(_rbox(Vector3(w, hgt, dd), 0.12), _rock_mat(s2 % 3), Vector3(pos.x, low + hgt * 0.5, pos.z) + jitter, b)


func _bridge(p0: Vector3, p1: Vector3, bas: Basis, glen: float, _wood: Material, _rope: Material) -> void:
	# 협곡을 건너는 나무다리: 굵은 들보 두 줄 위에 널을 깔고, 네 귀퉁이 말뚝 사이로 밧줄 난간이 늘어짐
	var wd := _wood(Color(0.5, 0.35, 0.22), Vector3(1, 0, 0), 0.2)      # 널: 다리를 가로질러 길게
	var wd2 := _wood(Color(0.4, 0.27, 0.17), Vector3(1, 0, 0), 0.2)
	var beam := _wood(Color(0.27, 0.18, 0.11), Vector3(0, 0, 1), 0.25)   # 들보: 다리 방향
	var dk := _wood(Color(0.27, 0.18, 0.11), Vector3(0, 1, 0), 0.25)     # 말뚝: 세로
	var rp := _mat(Color(0.7, 0.6, 0.4), 0.9)
	var top0 := p0 + Vector3(0, TILE_H - 0.14, 0)
	var top1 := p1 + Vector3(0, TILE_H - 0.14, 0)
	var pitch := -atan2(p1.y - p0.y, glen)
	var pb := bas * Basis(Vector3(1, 0, 0), pitch)
	var span := (top1 - top0).length()
	var mid := (top0 + top1) * 0.5
	for sd: float in [-0.5, 0.5]:
		_mi(_rbox(Vector3(0.16, 0.18, span + 0.3), 0.03), beam, mid + bas.x * sd + Vector3(0, -0.12, 0), pb)
	# 널: 가로로 긴 두툼한 널빤지를 틈을 조금씩 두고 촘촘히 (길이 · 두께 · 각도가 조금씩 다름)
	var n := maxi(3, int(round(span / 0.34)))
	for k in n:
		var f := (float(k) + 0.5) / n
		var pos := top0.lerp(top1, f) + bas.x * _rng.randf_range(-0.03, 0.03)
		var pw := 1.62 + _rng.randf_range(-0.09, 0.09)
		_mi(_rbox(Vector3(pw, 0.09, span / n * 0.9), 0.025), wd if k % 3 != 1 else wd2, pos + Vector3(0, _rng.randf_range(0.0, 0.012), 0),
			pb * Basis(Vector3.UP, _rng.randf_range(-0.035, 0.035)))
	for sd: float in [-0.84, 0.84]:
		var tops := []
		for e: float in [0.0, 1.0]:
			var q := top0.lerp(top1, e) + bas.x * sd + bas.z * (0.1 if e < 0.5 else -0.1)
			_mi(_cyl(0.075, 0.09, 1.15, 10), dk, q + Vector3(0, 0.32, 0), Basis(Vector3(0, 0, 1), sd * -0.04))
			var cap := SphereMesh.new()
			cap.radius = 0.1
			cap.height = 0.16
			_mi(cap, dk, q + Vector3(0, 0.91, 0))
			_mi(_torus_mesh(0.09, 0.022), rp, q + Vector3(0, 0.74, 0))
			_mi(_torus_mesh(0.09, 0.022), rp, q + Vector3(0, 0.36, 0))
			tops.append(q)
		# 밧줄 두 줄 (위 · 아래) — 가운데가 살짝 처짐
		for rail: Array in [[0.74, 0.14], [0.36, 0.08]]:
			var seg := 6
			var prev: Vector3 = tops[0] + Vector3(0, float(rail[0]), 0)
			for k in seg:
				var t := float(k + 1) / seg
				var nx: Vector3 = (tops[0] as Vector3).lerp(tops[1], t) + Vector3(0, float(rail[0]) - sin(t * PI) * float(rail[1]), 0)
				_rod(prev, nx, 0.022, rp)
				prev = nx


# ── 볼거리 ───────────────────────────────────────────────────
func _landmarks() -> void:
	var stone := _mat(Color(0.76, 0.74, 0.67), 0.6)
	var moss := _mat(Color(0.36, 0.6, 0.38), 0.9)
	var sp0 := start_pos
	# START 광장 둘레 부서진 기둥
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for k in corners.size():
		var c: Vector2 = corners[k] * (PLAZA * 0.5 + 1.0)
		var hgt: float = [3.2, 2.1, 1.4, 2.7][k]
		var p := sp0 + Vector3(c.x, 0, c.y)
		_mi(_box(Vector3(1.3, 0.35, 1.3)), stone, p + Vector3(0, 0.17, 0))
		_mi(_cyl(0.45, 0.5, hgt, 16), stone, p + Vector3(0, 0.35 + hgt * 0.5, 0))
		_mi(_cyl(0.47, 0.47, 0.08, 16), moss, p + Vector3(0, 0.35 + hgt, 0), Basis(Vector3(1, 0, 0), 0.15))
		_block(Vector2(p.x, p.z), 1.0)
	# 쓰러진 기둥
	var fallen := sp0 + Vector3(-PLAZA * 0.5 - 2.6, 0.4, PLAZA * 0.5 - 0.6)
	if _free_spot(fallen.x, fallen.z, 1.2):
		_mi(_cyl(0.45, 0.45, 3.2, 16), stone, fallen, Basis(Vector3(0, 0, 1), PI / 2).rotated(Vector3.UP, 0.4))
		_block(Vector2(fallen.x, fallen.z), 1.8)

	# 바위 아치 터널 (길 위)
	var rock := _rock_mat(2)
	for ar in arches:
		var snap := _path_point(ar["at"].x, ar["at"].y)
		var at: Vector2 = snap[0]
		var dir: Vector2 = snap[1]
		ar["at"] = at
		var yaw := atan2(dir.x, dir.y)
		for k in 3:
			var off := (k - 1) * 1.3
			var p := Vector3(at.x + dir.x * off, ground_height(at.x, at.y) - 0.3, at.y + dir.y * off)
			var t := TorusMesh.new()
			t.inner_radius = 2.3
			t.outer_radius = 3.5 - k * 0.15
			t.rings = 24
			t.ring_segments = 10
			# 고리를 세워서 길과 수직으로
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI / 2)
			_mi(t, rock, p, b)
		_coral(Vector3(at.x, ground_height(at.x, at.y) + 3.0, at.y), Color(1.0, 0.45, 0.55), 0.7)

	# 화산 분수 안쪽 불빛
	for v in volcanoes:
		var at: Vector2 = v["at"]
		var vr: float = v["r"]
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.55, 0.25)
		glow.light_energy = 3.0
		glow.omni_range = vr
		glow.position = Vector3(at.x, natural_height(at.x, at.y) + 1.0, at.y)
		add_child(glow)
		var lava := StandardMaterial3D.new()
		lava.albedo_color = Color(1.0, 0.45, 0.15)
		lava.emission_enabled = true
		lava.emission = Color(1.0, 0.45, 0.15)
		lava.emission_energy_multiplier = 2.5
		_mi(_cyl(vr * 0.13, vr * 0.13, 0.1, 16), lava, Vector3(at.x, natural_height(at.x, at.y) + 0.2, at.y))

	# 맵마다 특별한 볼거리
	for lm in cfg.get("landmarks", []):
		match String(lm["type"]):
			"temple":
				_temple(lm["at"], float(lm["r"]))
			"gate":
				_gate(lm["at"])
			"shipwreck":
				_shipwreck(lm["at"], float(lm["len"]), float(lm["deck"]))
			"whale":
				_whale(lm["at"], lm["dir"])
			"clam":
				_giant_clam(lm["at"])
			"kraken_lair":
				_kraken_lair(lm["at"])
			"village":
				_village(lm["at"])
			"lighthouse":
				_lighthouse(lm["at"])
			"colossus":
				_colossus(lm["at"])
			"hand":
				_giant_hand(lm["at"])
			"crystals":
				_crystals(lm["at"])
			"vents":
				_vents(lm["at"])
			"trident":
				_trident(lm["at"])
			"anchor":
				_anchor(lm["at"])
			"cargo":
				_cargo(lm["at"])
			"obelisk":
				_obelisk(lm["at"])


# ── 맵 볼거리: 신전 · 문 · 난파선 · 고래 뼈 · 거대 조개 ─────────
func _temple(at: Vector2, r: float) -> void:
	var stone := _smat(Color(0.76, 0.74, 0.66), "stone")
	var col_m := _smat(Color(0.78, 0.76, 0.68), "column")
	var dark := _smat(Color(0.7, 0.68, 0.6), "masonry")
	var moss := _mat(Color(0.34, 0.58, 0.4), 0.9)
	for q in 4:
		var tops := []
		for k in 3:
			var a := deg_to_rad(45.0 + 90.0 * q + (k - 1) * 22.0)
			var x := at.x + cos(a) * r
			var z := at.y + sin(a) * r
			if not _free_spot(x, z, 0.6):
				tops.append(null)
				continue
			var y := ground_height(x, z)
			var hgt: float = [4.6, 4.6, 2.2, 3.4, 1.3][(q * 3 + k) % 5]
			_mi(_rbox(Vector3(1.5, 0.4, 1.5), 0.06), dark, Vector3(x, y + 0.2, z))
			# 홈 파인 기둥
			_mi(_cyl(0.5, 0.56, hgt, 12), col_m, Vector3(x, y + 0.4 + hgt * 0.5, z))
			if hgt > 4.0:
				_mi(_rbox(Vector3(1.4, 0.35, 1.4), 0.05), stone, Vector3(x, y + 0.4 + hgt + 0.17, z))
				tops.append(Vector3(x, y + 0.4 + hgt + 0.35, z))
			else:
				tops.append(null)
				# 무너진 조각
				var fx := x + cos(a + 1.2) * 1.4
				var fz := z + sin(a + 1.2) * 1.4
				if _free_spot(fx, fz, 0.5):
					_mi(_cyl(0.48, 0.48, 1.1, 12), col_m, Vector3(fx, ground_height(fx, fz) + 0.45, fz), Basis(Vector3(0, 0, 1), PI / 2).rotated(Vector3.UP, a))
					_block(Vector2(fx, fz), 0.8)
			_block(Vector2(x, z), 1.0)
		# 이웃한 두 기둥 위 들보
		for k in 2:
			if tops[k] != null and tops[k + 1] != null:
				var a3: Vector3 = tops[k]
				var b3: Vector3 = tops[k + 1]
				var mid := (a3 + b3) * 0.5 + Vector3(0, 0.3, 0)
				var d := b3 - a3
				_mi(_rbox(Vector3(0.9, 0.6, Vector2(d.x, d.z).length() + 1.2), 0.08), stone, mid, Basis(Vector3.UP, atan2(d.x, d.z)))
		# 에메랄드 화로
		var ba := deg_to_rad(45.0 + 90.0 * q)
		var bx := at.x + cos(ba) * r * 0.55
		var bz := at.y + sin(ba) * r * 0.55
		if _free_spot(bx, bz, 0.6):
			var by := ground_height(bx, bz)
			_mi(_cyl(0.25, 0.35, 1.0, 10), dark, Vector3(bx, by + 0.5, bz))
			_mi(_cyl(0.55, 0.3, 0.35, 14), stone, Vector3(bx, by + 1.15, bz))
			var fl := SphereMesh.new()
			fl.radius = 0.32
			fl.height = 0.7
			_mi(fl, _unshaded(Color(0.35, 1.0, 0.75), 2.5), Vector3(bx, by + 1.5, bz))
			var l := OmniLight3D.new()
			l.light_color = Color(0.4, 1.0, 0.8)
			l.light_energy = 1.6
			l.omni_range = 5.0
			l.position = Vector3(bx, by + 1.8, bz)
			add_child(l)
			_block(Vector2(bx, bz), 0.9)


func _gate(at0: Vector2) -> void:
	var snap := _path_point(at0.x, at0.y)
	var at: Vector2 = snap[0]
	var gdir: Vector2 = snap[1]
	var gside := Vector3(gdir.y, 0, -gdir.x)
	var gb := Basis(Vector3.UP, atan2(gdir.x, gdir.y))
	var stone := _smat(Color(0.74, 0.72, 0.64), "masonry")
	var gold := _mat(Color(0.95, 0.76, 0.34), 0.25, 0.85)
	var top := 0.0
	for side: float in [-1.0, 1.0]:
		var x: float = at.x + gside.x * side * 2.5
		var z: float = at.y + gside.z * side * 2.5
		var y := ground_height(x, z)
		_mi(_rbox(Vector3(1.4, 0.5, 1.4), 0.06), stone, Vector3(x, y + 0.25, z), gb)
		_mi(_rbox(Vector3(1.0, 4.6, 1.0), 0.1), stone, Vector3(x, y + 2.8, z), gb)
		top = maxf(top, y + 5.1)
		_block(Vector2(x, z), 1.0)
	var c := Vector3(at.x, 0, at.y)
	_mi(_rbox(Vector3(7.2, 0.7, 1.4), 0.12), stone, c + Vector3(0, top + 0.35, 0), gb)
	_mi(_rbox(Vector3(6.0, 0.4, 1.1), 0.08), stone, c + Vector3(0, top + 0.95, 0), gb)
	_mi(_box(Vector3(6.4, 0.08, 1.46)), gold, c + Vector3(0, top + 0.1, 0), gb)
	var gem := SphereMesh.new()
	gem.radius = 0.38
	gem.height = 0.76
	_mi(gem, _unshaded(Color(0.3, 1.0, 0.72), 2.0), c + Vector3(0, top + 0.35, 0) + Vector3(gdir.x, 0, gdir.y) * 0.72)


func _shipwreck(at: Vector2, length: float, deck: float) -> void:
	# 갑판 위 칸들에 맞춰 배 방향을 정함
	var on := []
	for sp in spaces:
		if sp.get("deck", false) and (sp["base"] as Vector3).y > deck - 0.2:
			on.append(sp["base"])
	var axis := Vector3(0, 0, 1)
	var center := Vector3(at.x, 0, at.y)
	if on.size() >= 2:
		var a: Vector3 = on[0]
		var b: Vector3 = on[0]
		for p in on:
			if (p as Vector3).z < a.z:
				a = p
			if (p as Vector3).z > b.z:
				b = p
		axis = Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		center = Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5)
		length = Vector2(b.x - a.x, b.z - a.z).length() + 2.8
	var bas := Basis(Vector3.UP, atan2(axis.x, axis.z))
	var side := bas.x
	var wood := _smat(Color(0.36, 0.24, 0.15), "wood")
	var dark := _smat(Color(0.2, 0.13, 0.09), "wood")
	var plank := _smat(Color(0.5, 0.36, 0.23), "wood")
	var moss := _mat(Color(0.3, 0.52, 0.36), 0.9)
	var w := 5.8
	var hull_h := deck + 0.9
	# 두 동강 난 배: 가운데 몸통 (길이 양 끝으로 드나듦) + 떨어져 나간 뱃머리
	_mi(_rbox(Vector3(w, hull_h, length), 0.6), wood, center + Vector3(0, deck - hull_h * 0.5, 0), bas)
	_mi(_rbox(Vector3(w * 0.6, 1.0, length * 0.9), 0.3), dark, center + Vector3(0, -0.4, 0), bas)
	# 부러진 끝 — 길 양옆에만 삐죽삐죽한 판자
	for e: float in [-1.0, 1.0]:
		for sd: float in [-1.0, 1.0]:
			for k in 4:
				var hgt := _rng.randf_range(0.5, 1.6)
				var pp := center + axis * (e * (length * 0.5 - 0.1)) + side * sd * (w * 0.5 - 0.25 - k * 0.32) + Vector3(0, deck + hgt * 0.5 - 0.2, 0)
				_mi(_box(Vector3(0.28, hgt, 0.14)), dark if k % 2 == 0 else wood, pp, bas.rotated(axis, _rng.randf_range(-0.25, 0.25)))
	var away := 1.0 if side.dot(center) > 0.0 else -1.0
	var bow := center + side * away * (w + 2.6) + axis * (length * 0.2)
	if _free_spot(bow.x, bow.z, 2.6):
		var bb := bas.rotated(Vector3.UP, 0.5 * away)
		var tilt_b := Basis(bb * Vector3(0, 0, 1), 0.35 * away) * bb
		var bh := deck + 0.4
		_mi(_rbox(Vector3(w * 0.9, bh, 4.0), 0.2), wood, bow + Vector3(0, bh * 0.5 - 0.6, 0), tilt_b)
		var s2 := w * 0.9 / sqrt(2.0)
		_mi(_rbox(Vector3(s2, bh, s2), 0.18), wood, bow + tilt_b * Vector3(0, 0, 2.0) + Vector3(0, bh * 0.5 - 0.6, 0), tilt_b * Basis(Vector3.UP, PI / 4))
		# 뱃머리 판자 줄 · 갑판 · 부러진 단면
		for sd2: float in [-1.0, 1.0]:
			for k2 in 3:
				_mi(_box(Vector3(0.05, 0.1, 3.8)), dark, bow + tilt_b * Vector3(sd2 * (w * 0.45 + 0.01), bh - 1.1 - k2 * 0.6, 0) + Vector3(0, -0.6, 0), tilt_b)
		_mi(_box(Vector3(w * 0.8, 0.06, 3.8)), plank, bow + tilt_b * Vector3(0, bh - 0.58, 0) + Vector3(0, -0.6, 0) + Vector3(0, 0.01, 0), tilt_b)
		for k2 in 6:
			var hh2 := _rng.randf_range(0.4, 1.2)
			_mi(_box(Vector3(w * 0.13, hh2, 0.14)), dark if k2 % 2 == 0 else wood, bow + tilt_b * Vector3(-w * 0.38 + k2 * w * 0.15, bh - 0.6 + hh2 * 0.5 - 0.1, -2.0) + Vector3(0, -0.6, 0), tilt_b)
		# 뱃머리 장식 (뿔처럼 뻗은 기둥)
		_mi(_cyl(0.08, 0.2, 3.0, 8), wood, bow + tilt_b * Vector3(0, bh * 0.6, 4.2), tilt_b * Basis(Vector3(1, 0, 0), PI / 2 - 0.5))
		_block(Vector2(bow.x, bow.z), 3.4)
	# 선체 옆 판자 줄 · 구멍
	for sd: float in [-1.0, 1.0]:
		for k in 3:
			_mi(_box(Vector3(0.06, 0.12, length * 0.96)), dark, center + side * sd * (w * 0.5 + 0.01) + Vector3(0, deck - 0.5 - k * 0.75, 0), bas)
		var hole := center + side * sd * (w * 0.5 + 0.02) + axis * (length * 0.15 * sd) + Vector3(0, deck - 1.3, 0)
		_mi(_rbox(Vector3(0.05, 0.9, 1.6), 0.04), _mat(Color(0.03, 0.05, 0.06), 1.0), hole, bas)
	# 갑판 널빤지
	var n := int(length / 0.55)
	for k in n:
		var f := (float(k) + 0.5) / n - 0.5
		_mi(_box(Vector3(w - 0.5, 0.06, 0.5)), _wood(Color(0.5, 0.36, 0.23), Vector3(1, 0, 0)) if k % 3 != 0 else _wood(Color(0.36, 0.24, 0.15), Vector3(1, 0, 0)), center + axis * (f * length) + Vector3(0, deck + 0.01, 0), bas)
	# 난간 (군데군데 부서짐)
	for sd: float in [-1.0, 1.0]:
		var seg := 0.0
		while seg < length - 1.0:
			var ln := _rng.randf_range(1.5, 3.2)
			if _rng.randf() < 0.75:
				var c := center + axis * (seg - length * 0.5 + ln * 0.5) + side * sd * (w * 0.5 - 0.15) + Vector3(0, deck + 0.7, 0)
				_mi(_box(Vector3(0.12, 0.1, ln)), wood, c, bas)
				for e: float in [-0.5, 0.5]:
					_mi(_box(Vector3(0.12, 0.7, 0.12)), wood, c + axis * (e * ln) - Vector3(0, 0.35, 0), bas)
			seg += ln + _rng.randf_range(0.2, 0.9)
	# 부러진 돛대 + 찢어진 돛
	var mbase := center + side * (w * 0.5 - 0.6) + axis * (-length * 0.12) + Vector3(0, deck, 0)
	var tilt := Basis(axis, -0.28)
	_mi(_cyl(0.2, 0.28, 6.5, 12), wood, mbase + tilt * Vector3(0, 3.25, 0), tilt)
	_mi(_box(Vector3(4.2, 0.18, 0.18)), wood, mbase + tilt * Vector3(0, 5.2, 0), tilt * bas)
	var sail := QuadMesh.new()
	sail.size = Vector2(3.6, 2.6)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.86, 0.8, 0.66, 0.85)
	cloth.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 0.9
	_mi(sail, cloth, mbase + tilt * Vector3(0, 3.8, 0.12), tilt * bas)
	# 떨어져 나간 돛대 윗부분
	var fall := center + side * (w * 0.5 + 3.0) + axis * (length * 0.1)
	if _free_spot(fall.x, fall.z, 1.0):
		_mi(_cyl(0.18, 0.2, 4.2, 10), wood, Vector3(fall.x, ground_height(fall.x, fall.z) + 0.15, fall.z), Basis(axis, PI / 2.2) * bas)
		_block(Vector2(fall.x, fall.z), 2.0)
	# 이끼 · 산호가 붙은 선체
	for k in 6:
		var f := _rng.randf_range(-0.45, 0.45)
		var sd := -1.0 if k % 2 == 0 else 1.0
		var p := center + axis * (f * length) + side * sd * (w * 0.5 + 0.4)
		var mp := SphereMesh.new()
		mp.radius = _rng.randf_range(0.5, 0.9)
		mp.height = mp.radius
		_mi(mp, moss, Vector3(p.x, ground_height(p.x, p.z) + 0.1, p.z))
		if k < 3:
			_coral(Vector3(p.x, ground_height(p.x, p.z), p.z), Color(1.0, 0.5, 0.45).lerp(Color(0.8, 0.45, 1.0), k / 3.0), 0.9)
	# 갑판 아래 경사길 칸 받침 (나무 기둥)
	for sp in spaces:
		var b3: Vector3 = sp["base"]
		if sp.get("deck", false) and b3.y < deck - 0.2:
			for o: Vector3 in [Vector3(-0.8, 0, -0.8), Vector3(0.8, 0, 0.8), Vector3(-0.8, 0, 0.8), Vector3(0.8, 0, -0.8)]:
				var q := b3 + o
				var gy := natural_height(q.x, q.z)
				if b3.y - gy > 0.2:
					_mi(_cyl(0.13, 0.15, b3.y - gy + 0.2, 8), wood, Vector3(q.x, (b3.y + gy) * 0.5, q.z))
	for k in 7:
		var f := (float(k) / 6.0 - 0.5) * length
		var c := center + axis * f
		_block(Vector2(c.x, c.z), w * 0.5 + 0.6)


func _whale(at: Vector2, dir: Vector2) -> void:
	var bone := _smat(Color(0.84, 0.81, 0.73), "bone")
	var axis := Vector3(dir.x, 0, dir.y).normalized()
	var side := Vector3(-axis.z, 0, axis.x)
	var yaw := atan2(axis.x, axis.z)
	var ribs := 8
	var spine := []
	for k in ribs:
		var f := float(k) / (ribs - 1) - 0.5
		var want := Vector3(at.x, 0, at.y) + axis * (f * 15.0)
		var snap := _path_point(want.x, want.z)
		var p2: Vector2 = snap[0]
		var d2: Vector2 = snap[1]
		var p := Vector3(p2.x, 0, p2.y)
		var rside := Vector3(-d2.y, 0, d2.x)
		var r_in := 2.6 + 0.5 * sin((1.0 - (f + 0.5)) * PI * 0.9)
		var y := ground_height(p.x, p.z) - 0.7
		var t := TorusMesh.new()
		t.inner_radius = r_in
		t.outer_radius = r_in + 0.32
		t.rings = 28
		t.ring_segments = 8
		_mi(t, bone, Vector3(p.x, y, p.z), Basis(Vector3.UP, atan2(d2.x, d2.y)) * Basis(Vector3(1, 0, 0), PI / 2))
		spine.append(Vector3(p.x, y + r_in + 0.4, p.z))
		for sd: float in [-1.0, 1.0]:
			var foot := p + rside * sd * (r_in + 0.16)
			_block(Vector2(foot.x, foot.z), 0.6)
	# 등뼈 (마디마디)
	for k in spine.size() - 1:
		var a: Vector3 = spine[k]
		var b: Vector3 = spine[k + 1]
		var mid := (a + b) * 0.5
		var d := b - a
		_mi(_cyl(0.26, 0.26, d.length() * 0.62, 10), bone, mid, Basis(Quaternion(Vector3.UP, d.normalized())))
		var v := SphereMesh.new()
		v.radius = 0.42
		v.height = 0.7
		_mi(v, bone, a)
	# 꼬리 쪽 작은 뼈 · 머리뼈 (길 옆에)
	var tail: Vector3 = spine[spine.size() - 1]
	for k in 4:
		var q := tail + axis * (1.0 + k * 0.9)
		var gy := ground_height(q.x, q.z)
		var v := SphereMesh.new()
		v.radius = 0.32 - k * 0.05
		v.height = v.radius * 1.6
		_mi(v, bone, Vector3(q.x, maxf(gy + 0.2, tail.y - (k + 1) * 0.9), q.z))
	var head := Vector3(at.x, 0, at.y) - axis * 10.5 + side * 3.6
	var hp := _find_free(head.x, head.z, 1.6, 1.0)
	if hp.x != INF:
		var sk := SphereMesh.new()
		sk.radius = 1.0
		sk.height = 2.0
		var skull := _mi(sk, bone, hp + Vector3(0, 0.25, 0), Basis(Vector3.UP, yaw))
		skull.scale = Vector3(1.4, 0.7, 2.6)
		for sd: float in [-1.0, 1.0]:
			var jaw := _mi(_cyl(0.16, 0.24, 4.4, 8), bone, hp + side * sd * 1.1 - axis * 2.4 + Vector3(0, 0.2, 0),
				Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI / 2 - 0.08))
			jaw.rotation.y += sd * 0.12
		_block(Vector2(hp.x, hp.z), 3.0)


func _giant_clam(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 2.2, 1.5)
	if p.x == INF:
		return
	var shell_m := _mat(Color(0.98, 0.78, 0.82), 0.35)
	var inner := _mat(Color(0.75, 0.55, 0.95), 0.3)
	var yaw := _rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	shell_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	inner.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flip := b * Basis(Vector3(0, 0, 1), PI)
	var low := _mi(ReefKit.shell_mesh(), shell_m, p + b * Vector3(0, 0.45, -1.2), flip)
	low.scale = Vector3(2.2, 1.6, 2.4)
	var lip := _mi(ReefKit.shell_mesh(), inner, p + b * Vector3(0, 0.5, -1.1), flip)
	lip.scale = Vector3(2.0, 0.9, 2.2)
	var up := _mi(ReefKit.shell_mesh(), shell_m, p + b * Vector3(0, 0.55, -1.2), b * Basis(Vector3(1, 0, 0), -0.9))
	up.scale = Vector3(2.2, 1.6, 2.4)
	var pearl := SphereMesh.new()
	pearl.radius = 0.55
	pearl.height = 1.1
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.98, 0.96, 1.0)
	pm.roughness = 0.08
	pm.metallic = 0.3
	pm.emission_enabled = true
	pm.emission = Color(0.85, 0.95, 1.0)
	pm.emission_energy_multiplier = 0.9
	_mi(pearl, pm, p + b * Vector3(0, 0.55, -0.1))
	var l := OmniLight3D.new()
	l.light_color = Color(0.85, 0.95, 1.0)
	l.light_energy = 1.4
	l.omni_range = 4.0
	l.position = p + Vector3(0, 1.2, 0)
	add_child(l)
	bubbles_at(p + Vector3(0, 0.8, 0), 10, 0.4)
	_block(Vector2(p.x, p.z), 3.0)


# ── 크라켄 굴: 판 북쪽 끝 깊은 골짜기 속 빛나는 눈 + 잠든 촉수 ─────
signal tentacle_slammed           ## 촉수가 칸을 내려친 순간
const KRAKEN_SCALE := 10.0
const KRAKEN_TILT := 0.35          ## 앞으로 숙인 각도 (판을 내려다보게)
const KRAKEN_SLEEP_Y := -75.0      ## 잠들어 있을 때 (깊이 잠김)
const KRAKEN_AWAKE_Y := 15.0        ## 깨어나면: 판 북쪽 끝 위로 몸을 숙여 판을 내려다봄
var kraken_coils: Array = []      ## {tn, ph, y(뿌리 깊이), g(움켜쥔 정도), dir}
var kraken_body_mat: ShaderMaterial
var kraken_eyes: Array = []       ## 깨어날 때 연출용 (MeshInstance3D)
var kraken_arms: Array = []       ## [Node3D 뿌리, 기본 회전]
var kraken_root: Node3D


func _kraken_lair(at: Vector2) -> void:
	# 골짜기 속에 몸을 숨긴 크라켄: 머리(외투막) 꼭대기만 바위처럼 보이다가, 깨어나면 솟아올라 눈을 뜸
	# 판 북쪽 바깥 심연에 몸을 숨긴 거대 크라켄 (판만 한 크기). 처음엔 깊이 잠겨 있다가 솟아오름
	kraken_root = Node3D.new()
	kraken_root.position = Vector3(at.x, KRAKEN_SLEEP_Y, at.y - 17.0)
	kraken_root.basis = Basis(Vector3.RIGHT, KRAKEN_TILT).scaled(Vector3.ONE * KRAKEN_SCALE)
	add_child(kraken_root)
	# 몸통: 외투막 · 머리 · 눈두덩 · 팔 뿌리가 하나로 이어진 조각 (tools/make_kraken.py)
	var bm := ShaderMaterial.new()
	bm.shader = KrakenBodyShader
	bm.set_shader_parameter("pattern_scale", 1.2)
	var body := MeshInstance3D.new()
	body.mesh = KRAKEN_BODY
	body.material_override = bm
	kraken_root.add_child(body)
	kraken_body_mat = bm
	# 눈: 눈두덩 구멍 속에 반쯤 묻힌 실제 문어 눈 (빛나지 않음)
	var em := ShaderMaterial.new()
	em.shader = KrakenEyeShader
	for sd: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.36
		eye.height = 0.72
		eye.radial_segments = 48
		eye.rings = 24
		var e := _mi(eye, em, Vector3(sd * 1.57, 0.74, 1.3), Basis(Vector3.UP, sd * 0.72), kraken_root)
		kraken_eyes.append(e)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.45, 1.0, 0.35)
	gl.light_energy = 0.0
	gl.omni_range = 70.0
	gl.position = Vector3(0, 1.5, 4.0)
	kraken_root.add_child(gl)
	kraken_eyes.append(gl)
	# 독 안개: 머리 둘레로 피어오르는 초록 독기
	_poison_mist(kraken_root, Vector3(0, 2.0, 0), 4.0, 70)
	# 판을 둘러싼 거대한 촉수 고리들 (바깥 바닷속에서 솟아 아치를 그리며 다시 들어감)
	_kraken_coils()
	# 골짜기 둘레 부서진 바위 · 뼈
	for k in 12:
		var x := at.x + _rng.randf_range(-11, 11)
		var z := at.y + _rng.randf_range(2.5, 4.5)
		if _free_spot(x, z, 0.8):
			_rock(Vector3(x, ground_height(x, z) - 0.3, z), _rng.randf_range(0.6, 1.3))
			_block(Vector2(x, z), 1.0)


## 촉수 하나: 길이 1 짜리 곧은 관을 셰이더가 휘게 만듦 (마디 없이 매끈). 뿌리에서 +Y 로 뻗고 dir 쪽(+Z)으로 휨
## 돌려줌: {"root": MeshInstance3D, "mat": ShaderMaterial}
var _tube: ArrayMesh


func _tube_mesh() -> ArrayMesh:
	if _tube:
		return _tube
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 90
	var rad := 32
	for j in rings + 1:
		var y := float(j) / rings * 0.985
		for k in rad + 1:
			var a := float(k) / rad * TAU
			st.set_normal(Vector3(sin(a), 0, cos(a)))
			st.set_uv(Vector2(float(k) / rad, y))
			st.add_vertex(Vector3(sin(a), y, cos(a)))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(Vector3(0, 1.0, 0))
	var apex := (rings + 1) * (rad + 1)
	var w := rad + 1
	for j in rings:
		for k in rad:
			var i0 := j * w + k
			var i1 := i0 + 1
			var i3 := i0 + w
			var i2 := i3 + 1
			st.add_index(i0); st.add_index(i2); st.add_index(i1)
			st.add_index(i0); st.add_index(i3); st.add_index(i2)
	for k in rad:
		var i0 := rings * w + k
		st.add_index(i0); st.add_index(apex); st.add_index(i0 + 1)
	_tube = st.commit()
	return _tube


## 빨판 하나 (컵 모양, 반지름 1): 바깥으로 말린 두툼한 테 + 깊게 파인 안쪽. UV.x = 안쪽(0)~테두리(1), UV2.x = 1 (빨판 표시)
var _sucker: ArrayMesh


func _sucker_mesh() -> ArrayMesh:
	if _sucker:
		return _sucker
	var prof := [Vector2(0.0, -0.16), Vector2(0.16, -0.15), Vector2(0.32, -0.1), Vector2(0.46, 0.0), Vector2(0.58, 0.1),
		Vector2(0.7, 0.16), Vector2(0.82, 0.17), Vector2(0.92, 0.12), Vector2(1.02, 0.02), Vector2(1.12, -0.1), Vector2(1.22, -0.35)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var w := seg + 1
	for k in prof.size():
		var pr: Vector2 = prof[k]
		for j in w:
			var a := TAU * j / seg
			st.set_uv(Vector2(clampf(pr.x / 0.8, 0.0, 1.0), 0.0))
			st.set_uv2(Vector2(1.0, 0.0))
			st.add_vertex(Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x))
	for k in prof.size() - 1:
		for j in seg:
			var i0 := k * w + j
			var i1 := i0 + 1
			var i2 := i0 + w
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i3)
			st.add_index(i0); st.add_index(i3); st.add_index(i2)
	st.generate_normals()
	_sucker = st.commit()
	return _sucker


func make_tentacle(n: int, r0: float, seg_len: float, dir: Vector3 = Vector3(0, 0, 1)) -> Dictionary:
	var length := n * seg_len
	var mat := ShaderMaterial.new()
	mat.shader = KrakenArmShader
	mat.set_shader_parameter("arm_len", length)
	mat.set_shader_parameter("radius", r0)
	mat.set_shader_parameter("tip", 0.1)
	mat.set_shader_parameter("segs", float(n))
	mat.set_shader_parameter("pattern_scale", 1.6 / maxf(r0, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = _tube_mesh()
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-length, -length, -length) * 1.1, Vector3(length, length, length) * 2.2)
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		d = Vector3(0, 0, 1)
	mi.basis = Basis.looking_at(-d.normalized(), Vector3.UP)
	# 빨판 두 줄 (배 쪽, 엇갈려서). 끝으로 갈수록 작고 촘촘
	var cups := []
	var u := 0.05
	var row := 0
	while u < 0.96:
		var r := r0 * lerpf(1.0, 0.1, pow(u, 0.85))
		# 줄이 살짝 구불구불하고, 크기도 조금씩 달라서 찍어낸 느낌이 안 나게
		var ang := (0.4 if row % 2 == 0 else -0.4) + sin(u * 23.0) * 0.06 + _rng.randf_range(-0.05, 0.05)
		cups.append(Vector3(u, ang, 0.3 * _rng.randf_range(0.82, 1.12)))
		u += r * 0.46 / length
		row += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _sucker_mesh()
	mm.instance_count = cups.size()
	for k in cups.size():
		var c: Vector3 = cups[k]
		mm.set_instance_transform(k, Transform3D.IDENTITY)
		mm.set_instance_custom_data(k, Color(c.x, c.y, c.z, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = mi.custom_aabb
	mi.add_child(mmi)
	return {"root": mi, "mat": mat}


## 촉수 자세: 뿌리를 pitch 만큼 기울이고(dir 쪽 +), 끝으로 갈수록 curl 만큼 더 말기 (+ 출렁임)
func _pose_tentacle(tn: Dictionary, _axis: Vector3, pitch: float, curl: float, wave: float, t: float) -> void:
	var m: ShaderMaterial = tn["mat"]
	m.set_shader_parameter("pitch", pitch)
	m.set_shader_parameter("curl", curl)
	m.set_shader_parameter("wave", wave)
	m.set_shader_parameter("wtime", t)


# ── 크라켄이 노린 칸 표시: 바닥에 번지는 붉은 빛 + 칸 옆 땅에서 꿈틀대는 촉수 끝 ──────────
var _dangers := {}      ## 칸 → {"mark": MeshInstance3D, "tn": 촉수, "dir": 칸 쪽 방향, "root": 뿌리 위치, "t0": 시작 시간}


func mark_danger(i: int) -> void:
	if _dangers.has(i):
		return
	var top: Vector3 = spaces[i]["pos"]
	var q := QuadMesh.new()
	q.size = Vector2(TILE * 2.4, TILE * 2.4)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = DangerShader
	var mark := _mi(q, m, top + Vector3(0, 0.3, 0))
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 칸 윗면에도 붉은 빛 (받침이 높아 바닥 빛만으로는 멀리서 안 보임)
	var q2 := QuadMesh.new()
	q2.size = Vector2(TILE * 1.08, TILE * 1.08)
	q2.orientation = PlaneMesh.FACE_Y
	var m2 := ShaderMaterial.new()
	m2.shader = DangerShader
	m2.set_shader_parameter("fill_k", 0.75)
	var on_top := _mi(q2, m2, Vector3(0, TILE_H - 0.3 + 0.02, 0), Basis(Vector3.UP, float(spaces[i]["yaw"])), mark)
	on_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.18, 0.1)
	lt.light_energy = 0.0
	lt.omni_range = 3.4
	lt.position = Vector3(0, 0.9, 0)
	lt.omni_range = 4.0
	mark.add_child(lt)
	var lp := create_tween().set_loops()
	lp.tween_property(lt, "light_energy", 2.6, 0.45).set_trans(Tween.TRANS_SINE)
	lp.tween_property(lt, "light_energy", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	mark.tree_exiting.connect(lp.kill)
	m.set_shader_parameter("strength", 0.0)
	create_tween().tween_method(func(v: float) -> void:
		m.set_shader_parameter("strength", v)
		m2.set_shader_parameter("strength", v), 0.0, 1.0, 0.5)
	# 칸 옆 땅 (길 바깥쪽)에서 촉수 끝이 삐죽
	var side := Basis(Vector3.UP, float(spaces[i]["yaw"])).x
	var best := top + side * 3.0
	for sd: float in [1.0, -1.0]:
		var c := top + side * sd * 3.0
		if _free_spot(c.x, c.z, 0.3):
			best = c
			break
	best.y = ground_height(best.x, best.z) - 0.25
	var dir := Vector3(top.x - best.x, 0, top.z - best.z).normalized()
	var tn := make_tentacle(7, 0.5, 0.55, dir)
	var root: Node3D = tn["root"]
	root.position = best + Vector3(0, -4.5, 0)
	add_child(root)
	var axis := Vector3.UP.cross(dir).normalized()
	_dangers[i] = {"mark": mark, "tn": tn, "dir": dir, "axis": axis, "root": best, "t0": _time}
	_pose_tentacle(tn, axis, -0.15, -0.35, 0.3, _time)
	create_tween().tween_property(root, "position:y", best.y, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bubbles_at(best, 14, 0.4, true)
	_dust(best, 0.6)


func danger_tiles() -> Array:
	return _dangers.keys()


func _clear_danger(i: int) -> void:
	if not _dangers.has(i):
		return
	var d: Dictionary = _dangers[i]
	_dangers.erase(i)
	var mark: MeshInstance3D = d["mark"]
	var m := mark.material_override as ShaderMaterial
	var t := create_tween()
	t.tween_method(func(v: float) -> void: m.set_shader_parameter("strength", v), 1.0, 0.0, 0.4)
	t.tween_callback(mark.queue_free)


## 노린 칸을 내려침: 촉수가 땅에서 솟구쳐 뒤로 젖혔다가 칸 위로 쾅. await 가능, 끝나면 들어감
func tentacle_strike(i: int) -> void:
	var top: Vector3 = spaces[i]["pos"]
	var d: Dictionary
	if _dangers.has(i):
		d = _dangers[i]
		(d["tn"]["root"] as Node3D).queue_free()
	else:
		var side := Basis(Vector3.UP, float(spaces[i]["yaw"])).x
		var b := top + side * 3.0
		b.y = ground_height(b.x, b.z) - 0.25
		var dir0 := Vector3(top.x - b.x, 0, top.z - b.z).normalized()
		d = {"root": b, "dir": dir0, "axis": Vector3.UP.cross(dir0).normalized()}
	_clear_danger(i)
	var base: Vector3 = d["root"]
	var axis: Vector3 = d["axis"]
	var tn := make_tentacle(9, 1.35, 1.2, d["dir"])
	base.y = top.y + 0.5      # 눕혔을 때 칸 윗면을 덮게
	var root: Node3D = tn["root"]
	root.position = base + Vector3(0, -12.0, 0)
	add_child(root)
	var mat: ShaderMaterial = tn["mat"]
	# 1) 땅이 터지며 솟구침 (뒤로 젖혀 말림)
	_dust(base, 1.2)
	bubbles_at(base, 30, 0.8, true)
	var rise := create_tween().set_parallel(true)
	rise.tween_property(root, "position:y", base.y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.tween_method(func(f: float) -> void:
		_pose_tentacle(tn, axis, lerpf(0.0, -0.35, f), lerpf(0.0, -0.32, f), 0.25, _time)
		mat.set_shader_parameter("glow", f * 0.6), 0.0, 1.0, 0.55)
	await rise.finished
	# 2) 잠깐 버팀 (출렁)
	var hold := create_tween()
	hold.tween_method(func(f: float) -> void: _pose_tentacle(tn, axis, -0.35 - f * 0.12, -0.32 - f * 0.06, 0.35, _time), 0.0, 1.0, 0.32)
	await hold.finished
	# 3) 내려침: 칸 쪽으로 넘어지며 쫙 펴짐 (끝이 칸을 덮음)
	var slam := create_tween()
	slam.tween_method(func(f: float) -> void:
		var e := f * f
		_pose_tentacle(tn, axis, lerpf(-0.47, PI * 0.5 - 0.05, e), lerpf(-0.38, 0.02, e), 0.0, _time), 0.0, 1.0, 0.2)
	await slam.finished
	_dust(top, 1.6)
	bubbles_at(top, 40, 1.0, true)
	_impact_ring(top)
	tentacle_slammed.emit()
	# 4) 꿈틀대다가 땅속으로 쑥
	var wr := create_tween()
	wr.tween_method(func(f: float) -> void:
		_pose_tentacle(tn, axis, PI * 0.5 - 0.05 - f * 0.2, 0.02 + sin(f * 9.0) * 0.04, 0.0, _time)
		mat.set_shader_parameter("glow", 0.6 * (1.0 - f)), 0.0, 1.0, 0.5)
	await wr.finished
	var back := create_tween().set_parallel(true)
	back.tween_method(func(f: float) -> void: _pose_tentacle(tn, axis, lerpf(PI * 0.5 - 0.25, 0.0, f), lerpf(0.0, -0.4, f), 0.2, _time), 0.0, 1.0, 0.35)
	back.tween_property(root, "position:y", base.y - 13.0, 0.6).set_delay(0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	back.finished.connect(root.queue_free)
	_dust(base, 0.7)


## 하트를 다 잃은 말: 촉수가 휘감아 땅속으로 끌고 감
func tentacle_drag(node: Node3D) -> void:
	var p := node.position
	var side := Vector3(1, 0, 0.3).normalized()
	var base := p + side * 1.7
	base.y = ground_height(base.x, base.z) - 0.2
	var dir := Vector3(p.x - base.x, 0, p.z - base.z).normalized()
	var axis := Vector3.UP.cross(dir).normalized()
	var tn := make_tentacle(9, 0.6, 0.7, dir)
	var root: Node3D = tn["root"]
	root.position = base + Vector3(0, -7.0, 0)
	add_child(root)
	_dust(base, 1.0)
	bubbles_at(base, 24, 0.7, true)
	var rise := create_tween().set_parallel(true)
	rise.tween_property(root, "position:y", base.y, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.tween_method(func(f: float) -> void: _pose_tentacle(tn, axis, lerpf(0.0, 0.25, f), lerpf(0.0, 0.55, f), 0.15, _time), 0.0, 1.0, 0.5)
	await rise.finished
	# 휘감기 (말 쪽으로 감겨 들어감) + 말이 버둥
	var wrap := create_tween().set_parallel(true)
	wrap.tween_method(func(f: float) -> void: _pose_tentacle(tn, axis, 0.25 + f * 0.25, 0.55 + f * 0.55, 0.1, _time), 0.0, 1.0, 0.45)
	wrap.tween_property(node, "rotation:z", 0.35, 0.12)
	await wrap.finished
	var wig := create_tween().set_loops(3)
	wig.tween_property(node, "rotation:z", -0.3, 0.08)
	wig.tween_property(node, "rotation:z", 0.3, 0.08)
	await get_tree().create_timer(0.5, false).timeout
	# 끌고 내려감
	bubbles_at(p, 40, 1.0, true)
	_dust(p, 1.4)
	var down := create_tween().set_parallel(true)
	down.tween_property(root, "position:y", base.y - 9.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down.tween_property(node, "position", base + Vector3(0, -4.0, 0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	down.tween_property(node, "rotation:y", node.rotation.y + TAU * 1.5, 0.75)
	await down.finished
	node.visible = false
	root.queue_free()


## 모래 먼지가 확 퍼짐
func _dust(p: Vector3, amount: float) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = int(40 * amount)
	cp.lifetime = 1.6
	cp.explosiveness = 0.9
	cp.direction = Vector3.UP
	cp.spread = 80.0
	cp.initial_velocity_min = 1.0 * amount
	cp.initial_velocity_max = 3.2 * amount
	cp.gravity = Vector3(0, -0.6, 0)
	cp.damping_min = 1.5
	cp.damping_max = 2.5
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.8
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.68, 0.56, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	cp.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	cp.color_ramp = g
	cp.position = p + Vector3(0, 0.2, 0)
	add_child(cp)
	cp.emitting = true
	cp.finished.connect(cp.queue_free)


## 내려친 자리에서 퍼지는 충격파 고리
func _impact_ring(p: Vector3) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.1
	t.rings = 32
	t.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := _mi(t, m, p + Vector3(0, 0.1, 0))
	mi.scale = Vector3(0.5, 0.3, 0.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(4.5, 0.15, 4.5), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.finished.connect(mi.queue_free)


## 판을 움켜쥔 촉수들: 판 바깥 깊은 곳에서 솟아 테두리를 넘어와 판 가장자리를 꽉 누름.
## 모양(크기 1 기준): 길이 44, 굵기 4.4, 뿌리는 테두리 10.3 바깥 · 6.9 아래, 끝은 판 안쪽 10 까지 착 붙음
const GRIP_LEN := 44.0
const GRIP_R := 4.4
const GRIP_OUT := 10.3
const GRIP_DEPTH := 6.9
const GRIP_POSE := {"pitch": -0.15, "curl": 0.0, "hook": 2.6, "tipback": 0.9}


func _kraken_coils() -> void:
	# [테두리 위 지점, 판 안쪽 방향, 크기]
	var defs := [
		[Vector2(-26.0, -half_d), Vector2(0.2, 1.0), 1.5], [Vector2(26.0, -half_d), Vector2(-0.2, 1.0), 1.5],
		[Vector2(-half_w, -30.0), Vector2(1.0, 0.15), 1.25], [Vector2(-half_w, 4.0), Vector2(1.0, -0.1), 1.1],
		[Vector2(half_w, -22.0), Vector2(-1.0, 0.1), 1.2], [Vector2(half_w, 10.0), Vector2(-1.0, -0.05), 1.3],
		[Vector2(-30.0, half_d), Vector2(0.15, -1.0), 1.0], [Vector2(22.0, half_d), Vector2(-0.1, -1.0), 1.15],
		[Vector2(-half_w + 2.0, half_d - 2.0), Vector2(1.0, -1.0), 1.0], [Vector2(half_w - 2.0, half_d - 2.0), Vector2(-1.0, -1.0), 0.95],
	]
	for k in defs.size():
		var edge: Vector2 = defs[k][0]
		var dir2: Vector2 = (defs[k][1] as Vector2).normalized()
		var sz: float = defs[k][2]
		var dir := Vector3(dir2.x, 0, dir2.y)
		var tn := make_tentacle(1, GRIP_R * sz, GRIP_LEN * sz, dir)
		var m: ShaderMaterial = tn["mat"]
		m.set_shader_parameter("pattern_scale", 0.4 / sz)
		m.set_shader_parameter("tip", 0.13)
		m.set_shader_parameter("hook_at", 0.32)
		var root: Node3D = tn["root"]
		var at := edge - dir2 * GRIP_OUT * sz
		root.position = Vector3(at.x, KRAKEN_SLEEP_Y, at.y)
		add_child(root)
		_poison_mist(root, Vector3(0, GRIP_DEPTH * sz, 0), 3.0 * sz, 14)
		var hit := edge + dir2 * 7.0 * sz
		kraken_coils.append({"tn": tn, "ph": k * 1.7, "y": -GRIP_DEPTH * sz, "g": 0.0, "dir": dir,
			"hit": Vector3(hit.x, 0.3, hit.y)})
		_pose_coil(kraken_coils[k], 0.0)


## 크라켄 두 눈 사이 (깨어난 자세 기준) — 카메라 연출용
func kraken_eye_pos() -> Vector3:
	var p := Vector3(kraken_root.position.x, KRAKEN_AWAKE_Y, kraken_root.position.z)
	return p + Basis(Vector3.RIGHT, KRAKEN_TILT).scaled(Vector3.ONE * KRAKEN_SCALE) * Vector3(0, 0.74, 1.3)


## g = 0: 곧게 선 촉수, 1: 판을 움켜쥔 자세. 움켜쥔 채로 천천히 조였다 풀었다
func _pose_coil(c: Dictionary, t: float) -> void:
	var g: float = c["g"]
	var ph: float = c["ph"]
	var m: ShaderMaterial = c["tn"]["mat"]
	var squeeze := sin(t * 0.45 + ph) * 0.5 + 0.5
	m.set_shader_parameter("pitch", lerpf(sin(t * 0.6 + ph) * 0.12, GRIP_POSE["pitch"], g))
	m.set_shader_parameter("curl", lerpf(0.15, GRIP_POSE["curl"], g))
	m.set_shader_parameter("hook", GRIP_POSE["hook"] * g + squeeze * 0.07 * g)
	m.set_shader_parameter("tipback", GRIP_POSE["tipback"] * g - squeeze * 0.06 * g)
	m.set_shader_parameter("wave", 0.25 * (1.0 - g))
	m.set_shader_parameter("wtime", t * 0.25 + ph)


## 가장자리가 부드럽게 사라지는 둥근 점 (입자가 네모로 보이지 않게)
var _soft: GradientTexture2D
func _soft_dot() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.5, Color(1, 1, 1, 0.35))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


## 초록 독 안개 (위로 피어오르며 흩어짐)
func _poison_mist(parent: Node3D, at: Vector3, spread: float, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.amount = amount
	cp.lifetime = 5.0
	cp.preprocess = 4.0
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.emission_sphere_radius = spread
	cp.direction = Vector3.UP
	cp.spread = 35.0
	cp.initial_velocity_min = 0.3
	cp.initial_velocity_max = 0.9
	cp.gravity = Vector3(0, 0.15, 0)
	cp.scale_amount_min = 1.5
	cp.scale_amount_max = 3.5
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.95, 0.2, 0.3)
	m.albedo_texture = _soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.3, 0.8, 0.1)
	q.material = m
	cp.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.25, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	cp.color_ramp = g
	cp.position = at
	parent.add_child(cp)


## 크라켄이 깨어남: 눈이 번쩍, 촉수가 솟아오름 (await 가능)
func kraken_awaken() -> void:
	if kraken_root == null:
		return
	for e in kraken_eyes:
		if e is OmniLight3D:
			create_tween().tween_property(e, "light_energy", 2.2, 2.0)
	if kraken_body_mat:
		var g := create_tween()
		g.tween_method(func(v: float) -> void: kraken_body_mat.set_shader_parameter("glow", v), 0.0, 0.8, 1.2)
		g.tween_method(func(v: float) -> void: kraken_body_mat.set_shader_parameter("glow", v), 0.8, 0.0, 1.6)
	var up := create_tween().set_parallel(true)
	up.tween_property(kraken_root, "position:y", KRAKEN_AWAKE_Y, 3.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 촉수들이 판 바깥에서 곧게 솟구쳤다가 → 테두리를 넘어 판을 콱 움켜쥠
	for k in kraken_coils.size():
		var c: Dictionary = kraken_coils[k]
		var root: Node3D = c["tn"]["root"]
		up.tween_property(root, "position:y", float(c["y"]), 2.0).set_delay(0.3 + k * 0.12).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		var grab := create_tween()
		grab.tween_interval(3.2 + k * 0.1)
		grab.tween_method(func(v: float) -> void: c["g"] = v, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		grab.tween_callback(func() -> void:
			_dust(c["hit"], 1.6)
			_impact_ring(c["hit"]))
	await up.finished


# ── 더 많은 볼거리 (가라앉은 섬) ─────────────────────────────
func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	_glows.append([m, energy, _rng.randf() * TAU])
	return m


func _light(p: Vector3, c: Color, energy: float, rng_: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng_
	l.position = p
	add_child(l)


## 무너진 바닷속 마을: 돌집 몇 채 + 우물 + 낮은 돌담
func _village(at: Vector2) -> void:
	var stone := _smat(Color(0.72, 0.68, 0.6), "masonry")
	var stone_r := _smat(Color(0.72, 0.68, 0.6), "masonry", 1.5)
	var wood := _smat(Color(0.42, 0.28, 0.17), "wood")
	var stone2 := _smat(Color(0.6, 0.58, 0.52), "stone")
	var roof := _smat(Color(0.74, 0.36, 0.25), "roof", 0.0, 0.5)
	var roof_r := _smat(Color(0.74, 0.36, 0.25), "roof", 1.2, 0.5)
	var dark := _mat(Color(0.05, 0.07, 0.08), 1.0)
	var moss := _mat(Color(0.32, 0.56, 0.38), 0.9)
	# 우물
	var wp := _find_free(at.x, at.y, 1.4, 1.0)
	if wp.x != INF:
		var ring := _cyl(1.0, 1.05, 0.9, 20)
		ring.cap_top = false
		var rm := _mat(Color(0.72, 0.68, 0.6), 0.8).duplicate() as StandardMaterial3D
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mi(ring, rm, wp + Vector3(0, 0.45, 0))
		_mi(_cyl(0.9, 0.9, 0.05, 20), _glow_mat(Color(0.25, 0.85, 0.8), 1.2), wp + Vector3(0, 0.6, 0))
		for sd: float in [-1.0, 1.0]:
			_mi(_box(Vector3(0.16, 2.0, 0.16)), wood, wp + Vector3(sd * 0.95, 1.0, 0))
		_mi(_box(Vector3(2.4, 0.12, 1.2)), roof, wp + Vector3(0, 2.05, 0), Basis(Vector3(1, 0, 0), 0.15))
		_block(Vector2(wp.x, wp.z), 1.6)
	# 돌집
	for k in 6:
		var a := TAU * k / 6.0 + 0.4
		var hp := _find_free(at.x + cos(a) * 5.5, at.y + sin(a) * 5.5, 1.9, 1.5)
		if hp.x == INF:
			continue
		var face := atan2(at.x - hp.x, at.y - hp.z)   # 문이 마을 가운데를 보게
		var b := Basis(Vector3.UP, face)
		var round_ := k % 2 == 0
		var wall_h := _rng.randf_range(1.8, 2.6)
		var broken := k % 3 == 1
		if round_:
			var wall := _cyl(1.45, 1.55, wall_h, 18)
			_mi(wall, stone_r, hp + Vector3(0, wall_h * 0.5, 0), b)
		else:
			_mi(_rbox(Vector3(2.8, wall_h, 2.6), 0.12), stone, hp + Vector3(0, wall_h * 0.5, 0), b)
		# 바닥 돌 단
		if round_:
			_mi(_cyl(1.68, 1.72, 0.3, 18), stone2, hp + Vector3(0, 0.15, 0), b)
		else:
			_mi(_rbox(Vector3(3.05, 0.3, 2.85), 0.06), stone2, hp + Vector3(0, 0.15, 0), b)
		# 문: 어두운 안쪽 + 돌 문틀 · 상인방 + 반쯤 열린 나무 문짝
		var dz := 1.52 if round_ else 1.3
		_mi(_rbox(Vector3(0.8, 1.3, 0.2), 0.04), dark, hp + b * Vector3(0, 0.65, dz - 0.02), b)
		for sd: float in [-1.0, 1.0]:
			_mi(_rbox(Vector3(0.18, 1.4, 0.3), 0.04), stone2, hp + b * Vector3(sd * 0.49, 0.7, dz), b)
		_mi(_rbox(Vector3(1.3, 0.22, 0.34), 0.05), stone2, hp + b * Vector3(0, 1.5, dz), b)
		_mi(_rbox(Vector3(0.74, 1.24, 0.07), 0.02), wood, hp + b * Vector3(-0.62, 0.64, dz + 0.42), b * Basis(Vector3.UP, -1.1))
		# 창문: 어두운 안쪽 + 돌 창턱 + 나무 살
		for sd: float in [-1.0, 1.0]:
			var wx := sd * (1.5 if round_ else 1.38)
			_mi(_box(Vector3(0.12, 0.45, 0.45)), dark, hp + b * Vector3(wx, wall_h * 0.62, 0), b)
			_mi(_rbox(Vector3(0.24, 0.1, 0.66), 0.03), stone2, hp + b * Vector3(wx + sd * 0.03, wall_h * 0.62 - 0.28, 0), b)
			_mi(_rbox(Vector3(0.22, 0.1, 0.66), 0.03), stone2, hp + b * Vector3(wx + sd * 0.03, wall_h * 0.62 + 0.28, 0), b)
			_mi(_box(Vector3(0.05, 0.45, 0.05)), wood, hp + b * Vector3(wx + sd * 0.06, wall_h * 0.62, 0), b)
		# 지붕 (몇 채는 무너짐)
		if broken:
			for q in 4:
				var rp := hp + b * Vector3(_rng.randf_range(-1.6, 1.6), 0.15, _rng.randf_range(1.8, 2.6))
				_mi(_box(Vector3(0.5, 0.3, 0.4)), stone2, rp, Basis(Vector3.UP, _rng.randf() * TAU))
			_mi(_cyl(0.0, 1.0, 0.9, 12), roof_r, hp + Vector3(1.6, 0.35, -1.4), Basis(Vector3(0, 0, 1), 1.9))
		elif round_:
			_mi(_cyl(0.0, 1.85, 1.5, 18), roof_r, hp + Vector3(0, wall_h + 0.75, 0))
			_mi(_cyl(1.6, 1.6, 0.06, 18), moss, hp + Vector3(0, wall_h + 0.03, 0))
		else:
			for sd: float in [-1.0, 1.0]:
				_mi(_box(Vector3(3.3, 0.14, 1.95)), roof, hp + b * Vector3(0, wall_h + 0.5, sd * 0.74), b * Basis(Vector3(1, 0, 0), sd * 0.62))
				# 박공벽 (지붕 아래 세모난 벽) 대신 굵은 들보
				_mi(_rbox(Vector3(0.16, 0.16, 2.9), 0.03), wood, hp + b * Vector3(sd * 1.3, wall_h + 0.08, 0), b)
			_mi(_rbox(Vector3(3.4, 0.2, 0.2), 0.05), wood, hp + b * Vector3(0, wall_h + 1.08, 0), b)   # 용마루
			_mi(_prism(2.6, 0.98, 2.76), stone, hp + b * Vector3(0, wall_h - 0.02, 0), b)             # 박공벽
			_mi(_box(Vector3(0.6, 0.9, 0.6)), stone2, hp + b * Vector3(0.8, wall_h + 0.8, -0.5), b)   # 굴뚝
		_block(Vector2(hp.x, hp.z), 2.3)
	# 마을을 두른 낮은 돌담 (군데군데 무너짐)
	for k in 26:
		var a := TAU * k / 26.0
		var x := at.x + cos(a) * 9.0
		var z := at.y + sin(a) * 8.0
		if _rng.randf() < 0.3 or not _free_spot(x, z, 0.5):
			continue
		var hgt := _rng.randf_range(0.35, 1.1)
		_mi(_rbox(Vector3(1.9, hgt, 0.6), 0.08), stone2, Vector3(x, ground_height(x, z) + hgt * 0.5, z), Basis(Vector3.UP, -a))
		_block(Vector2(x, z), 0.8)


## 기울어진 등대 + 빙글빙글 도는 불빛
func _lighthouse(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 2.6, 1.5)
	if p.x == INF:
		return
	_rock(p + Vector3(0, -0.6, 0), 3.0)
	var root := Node3D.new()
	root.position = p + Vector3(0, 0.6, 0)
	root.rotation = Vector3(0.07, 0.4, -0.05)
	add_child(root)
	var white := _smat(Color(0.93, 0.92, 0.88), "paint", 0.0, 0.35)
	var red := _smat(Color(0.74, 0.17, 0.18), "paint", 0.0, 0.35)
	var dark := _mat(Color(0.12, 0.14, 0.16), 0.4, 0.5)
	var h := 0.0
	var r := 1.7
	for k in 7:
		var seg_h := 1.6
		_mi(_cyl(r - 0.12, r, seg_h, 20), red if k % 2 == 1 else white, Vector3(0, h + seg_h * 0.5, 0), Basis(), root)
		h += seg_h
		r -= 0.12
	# 창문
	for k in 3:
		_mi(_rbox(Vector3(0.35, 0.6, 0.15), 0.05), dark, Vector3(0, 2.4 + k * 3.2, 1.62 - k * 0.38), Basis(), root)
	# 발코니 + 난간
	_mi(_cyl(r + 0.5, r + 0.3, 0.2, 20), dark, Vector3(0, h + 0.1, 0), Basis(), root)
	for k in 14:
		var a := TAU * k / 14.0
		_mi(_cyl(0.03, 0.03, 0.6, 6), dark, Vector3(cos(a) * (r + 0.42), h + 0.5, sin(a) * (r + 0.42)), Basis(), root)
	_mi(_torus_mesh(r + 0.42, 0.04), dark, Vector3(0, h + 0.8, 0), Basis(), root)
	# 등불 방
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.95, 0.7, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.9, 0.55)
	glass.emission_energy_multiplier = 2.2
	_mi(_cyl(r * 0.75, r * 0.75, 1.4, 16), glass, Vector3(0, h + 0.9, 0), Basis(), root)
	_mi(_cyl(0.0, r * 0.95, 1.0, 16), red, Vector3(0, h + 2.1, 0), Basis(), root)
	var ball := SphereMesh.new()
	ball.radius = 0.22
	ball.height = 0.44
	_mi(ball, _mat(Color(1.0, 0.8, 0.3), 0.2, 0.9), Vector3(0, h + 2.7, 0), Basis(), root)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.6)
	lamp.light_energy = 3.0
	lamp.omni_range = 14.0
	lamp.position = Vector3(0, h + 0.9, 0)
	root.add_child(lamp)
	# 도는 불빛 (양쪽으로 뻗는 빛기둥)
	var rot := Node3D.new()
	rot.position = Vector3(0, h + 0.9, 0)
	root.add_child(rot)
	var beam_m := StandardMaterial3D.new()
	beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_m.albedo_color = Color(1.0, 0.95, 0.7, 0.13)
	beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for sd: float in [-1.0, 1.0]:
		var beam := _cyl(0.25, 2.2, 16.0, 16)
		beam.cap_top = false
		beam.cap_bottom = false
		var bm := _mi(beam, beam_m, Vector3(sd * 8.2, 0, 0), Basis(Vector3(0, 0, 1), sd * PI / 2), rot)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotors.append([rot, 0.7])
	_block(Vector2(p.x, p.z), 3.6)


func _torus_mesh(ring_r: float, tube_r: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ring_r - tube_r
	t.outer_radius = ring_r + tube_r
	t.rings = 32
	t.ring_segments = 8
	return t


## 모래에 반쯤 묻힌 거대한 석상 머리 (눈이 에메랄드로 빛남)
func _colossus(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 3.6, 1.5)
	if p.x == INF:
		return
	var stone := _smat(Color(0.66, 0.66, 0.6), "stone", 0.0, 0.85)
	var moss := _mat(Color(0.3, 0.52, 0.36), 0.95)
	var root := Node3D.new()
	root.position = p + Vector3(0, -0.4, 0)
	root.rotation = Vector3(-0.12, 0.45, 0.14)   # 얼굴이 카메라(남쪽) 쪽을 보게
	add_child(root)
	_mi(_rbox(Vector3(4.6, 6.4, 4.0), 1.1), stone, Vector3(0, 3.0, 0), Basis(), root)              # 머리
	_mi(_rbox(Vector3(5.0, 1.0, 4.4), 0.3), stone, Vector3(0, 5.4, 0.1), Basis(), root)            # 머리띠
	_mi(_rbox(Vector3(4.8, 0.9, 1.2), 0.3), stone, Vector3(0, 4.3, 1.8), Basis(), root)            # 이마
	_mi(_rbox(Vector3(1.0, 2.2, 1.2), 0.3), stone, Vector3(0, 3.0, 2.2), Basis(Vector3(1, 0, 0), -0.12), root)   # 코
	_mi(_rbox(Vector3(2.6, 0.35, 0.5), 0.12), _mat(Color(0.3, 0.3, 0.3), 0.9), Vector3(0, 1.5, 2.0), Basis(), root)   # 입
	for sd: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.42
		eye.height = 0.6
		_mi(eye, _glow_mat(Color(0.3, 1.0, 0.75), 2.4), Vector3(sd * 1.1, 3.75, 1.86), Basis(), root)
		_mi(_rbox(Vector3(0.6, 2.4, 1.6), 0.25), stone, Vector3(sd * 2.45, 3.0, 0.2), Basis(), root)   # 귀
	var cap := SphereMesh.new()
	cap.radius = 2.4
	cap.height = 1.4
	cap.is_hemisphere = true
	_mi(cap, moss, Vector3(0, 5.9, -0.1), Basis(), root)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.4, 1.0, 0.8)
	gl.light_energy = 1.5
	gl.omni_range = 6.0
	gl.position = Vector3(0, 3.8, 3.0)
	root.add_child(gl)
	# 주변에 떨어진 돌덩이
	for k in 5:
		var q := _find_free(p.x + _rng.randf_range(-5, 5), p.z + _rng.randf_range(-5, 5), 0.8, 1.0)
		if q.x != INF:
			_mi(_rbox(Vector3(_rng.randf_range(0.8, 1.6), _rng.randf_range(0.5, 1.0), _rng.randf_range(0.8, 1.4)), 0.15), stone, q + Vector3(0, 0.3, 0), Basis(Vector3.UP, _rng.randf() * TAU))
			_block(Vector2(q.x, q.z), 1.0)
	_block(Vector2(p.x, p.z), 4.2)


## 모래에서 솟아오른 거대한 돌 손
func _giant_hand(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 2.2, 1.0)
	if p.x == INF:
		return
	var stone := _smat(Color(0.72, 0.7, 0.64), "stone", 0.0, 0.8)
	var root := Node3D.new()
	root.position = p + Vector3(0, -0.3, 0)
	root.rotation = Vector3(0.0, _rng.randf() * TAU, 0.15)
	add_child(root)
	_mi(_cyl(0.85, 1.1, 2.2, 14), stone, Vector3(0, 1.1, 0), Basis(), root)              # 손목
	_mi(_rbox(Vector3(2.1, 2.0, 1.0), 0.4), stone, Vector3(0, 3.0, 0), Basis(), root)     # 손바닥
	for k in 4:
		var x := -0.75 + k * 0.5
		var ln: float = [1.5, 1.9, 1.8, 1.3][k]
		var bend := 0.25 + k * 0.08
		var f1 := Vector3(x, 4.0 + ln * 0.25, 0)
		_mi(_cyl(0.2, 0.23, ln * 0.55, 10), stone, f1, Basis(Vector3(1, 0, 0), bend * 0.4), root)
		var tip := f1 + Basis(Vector3(1, 0, 0), bend * 0.4) * Vector3(0, ln * 0.27, 0)
		_mi(_cyl(0.17, 0.2, ln * 0.5, 10), stone, tip + Basis(Vector3(1, 0, 0), bend) * Vector3(0, ln * 0.24, 0), Basis(Vector3(1, 0, 0), bend), root)
	_mi(_cyl(0.22, 0.26, 1.3, 10), stone, Vector3(1.25, 3.0, 0.2), Basis(Vector3(0, 0, 1), -0.9), root)   # 엄지
	# 손바닥 위 빛나는 진주
	var pearl := SphereMesh.new()
	pearl.radius = 0.45
	pearl.height = 0.9
	_mi(pearl, _glow_mat(Color(0.82, 0.86, 0.95), 0.35), Vector3(0, 3.0, 0.85), Basis(), root)
	_block(Vector2(p.x, p.z), 2.6)


## 빛나는 수정 밭
func _crystals(at: Vector2) -> void:
	var cols := [Color(0.35, 0.95, 1.0), Color(0.7, 0.45, 1.0), Color(0.4, 1.0, 0.7)]
	for c in 7:
		var cp := _find_free(at.x + _rng.randfn(0.0, 3.5), at.y + _rng.randfn(0.0, 3.5), 1.2, 1.0)
		if cp.x == INF:
			continue
		var col: Color = cols[c % cols.size()]
		# 수정: 스스로 하얗게 타지 않고, 매끈한 면에 빛이 맺히며 속이 살짝 비침
		var m := _glow_mat(col.darkened(0.25), 0.45)
		m.albedo_color = Color(col.darkened(0.15), 0.82)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.25
		m.metallic_specular = 1.0
		m.rim_enabled = true
		m.rim = 0.8
		m.rim_tint = 0.4
		var n := _rng.randi_range(4, 7)
		for k in n:
			var hgt := _rng.randf_range(0.9, 2.8) * (1.4 if k == 0 else 1.0)
			var rad := hgt * 0.16
			var tilt := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3(1, 0, 0), 0.0 if k == 0 else _rng.randf_range(0.25, 0.7))
			var base := cp + tilt * Vector3(0, -0.2, 0)
			_mi(_cyl(rad, rad, hgt, 6), m, base + tilt * Vector3(0, hgt * 0.5, 0), tilt)
			_mi(_cyl(0.0, rad, hgt * 0.3, 6), m, base + tilt * Vector3(0, hgt + hgt * 0.15, 0), tilt)
		if c % 2 == 0:
			_light(cp + Vector3(0, 1.4, 0), col, 1.4, 5.0)
		_block(Vector2(cp.x, cp.z), 1.5)


## 뜨거운 물이 뿜어져 나오는 굴뚝
func _vents(at: Vector2) -> void:
	var rock := _smat(Color(0.36, 0.32, 0.29), "stone", 0.0, 0.2)
	for k in 4:
		var vp := _find_free(at.x + _rng.randfn(0.0, 2.2), at.y + _rng.randfn(0.0, 2.2), 0.9, 1.0)
		if vp.x == INF:
			continue
		var hgt := _rng.randf_range(1.5, 3.6)
		_rock(vp + Vector3(0, -0.25, 0), 1.25)
		var segs := 6
		for s2 in segs:
			var f := float(s2) / segs
			var f1 := f + 1.0 / segs
			# 아래는 넓게 퍼지고 마디마다 살짝 불룩한 굴뚝
			var r0 := lerpf(0.3, 0.8, pow(1.0 - f, 1.6)) * (1.08 if s2 % 2 == 0 else 1.0)
			var r1 := lerpf(0.3, 0.8, pow(1.0 - f1, 1.6))
			_mi(_cyl(r1, r0, hgt / segs + 0.02, 14), rock, vp + Vector3(_rng.randf_range(-0.08, 0.08), hgt * (f + 0.5 / segs), _rng.randf_range(-0.08, 0.08)))
		_mi(_cyl(0.28, 0.28, 0.06, 10), _glow_mat(Color(1.0, 0.5, 0.2), 2.5), vp + Vector3(0, hgt + 0.02, 0))
		var smoke := bubbles_at(vp + Vector3(0, hgt + 0.2, 0), 26, 0.15)
		smoke.initial_velocity_min = 1.4
		smoke.initial_velocity_max = 2.6
		_block(Vector2(vp.x, vp.z), 1.1)
	_light(Vector3(at.x, ground_height(at.x, at.y) + 2.0, at.y), Color(1.0, 0.55, 0.25), 1.6, 6.0)


## 땅에 꽂힌 거대한 황금 삼지창
func _trident(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 1.2, 1.0)
	if p.x == INF:
		return
	var gold := _mat(Color(1.0, 0.78, 0.3), 0.25, 0.9)
	var b := Basis(Vector3.UP, 0.6) * Basis(Vector3(0, 0, 1), 0.2)
	var base := p + Vector3(0, -0.5, 0)
	_mi(_cyl(0.18, 0.22, 9.0, 12), gold, base + b * Vector3(0, 4.5, 0), b)
	_mi(_box(Vector3(2.6, 0.3, 0.3)), gold, base + b * Vector3(0, 9.0, 0), b)
	for x: float in [-1.15, 0.0, 1.15]:
		var hh := 2.4 if x == 0.0 else 1.9
		_mi(_cyl(0.13, 0.16, hh, 10), gold, base + b * Vector3(x, 9.0 + hh * 0.5, 0), b)
		_mi(_cyl(0.0, 0.3, 0.7, 10), gold, base + b * Vector3(x, 9.0 + hh + 0.3, 0), b)
	var gem := SphereMesh.new()
	gem.radius = 0.35
	gem.height = 0.7
	_mi(gem, _glow_mat(Color(0.3, 1.0, 0.75), 2.2), base + b * Vector3(0, 9.0, 0.2))
	for k in 4:
		_rock(p + Vector3(cos(k * 1.6) * 1.0, -0.4, sin(k * 1.6) * 1.0), _rng.randf_range(0.6, 0.9))
	_block(Vector2(p.x, p.z), 2.0)


## 쇠사슬이 달린 거대한 닻 (모래에 누움)
func _anchor(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 2.5, 1.5)
	if p.x == INF:
		return
	var iron := _smat(Color(0.24, 0.23, 0.24), "iron", 0.0, 0.5)
	var yaw := _rng.randf() * TAU
	var root := Node3D.new()
	# 옆으로 쓰러진 닻: 몸대는 바닥에 눕고, 한쪽 갈고리는 모래에 박히고 다른 쪽은 위로 솟음
	root.position = p + Vector3(0, 0.26, 0)
	root.rotation = Vector3(0, yaw, PI / 2 - 0.06)
	add_child(root)
	# 몸대 (아래로 갈수록 굵음) + 고리 구멍 + 고리
	_mi(_cyl(0.19, 0.27, 6.0, 14), iron, Vector3(0, 0, 0), Basis(), root)
	_mi(_cyl(0.3, 0.3, 0.34, 14), iron, Vector3(0, 3.05, 0), Basis(Vector3(1, 0, 0), PI / 2), root)
	_mi(_torus_mesh(0.62, 0.11), iron, Vector3(0, 3.7, 0), Basis(Vector3(1, 0, 0), PI / 2) * Basis(Vector3(0, 0, 1), 0.3), root)
	# 가로대 (양 끝이 가늘고 둥근 마개)
	for sd: float in [-1.0, 1.0]:
		_rod(Vector3(0, 2.5, 0), Vector3(0, 2.5, sd * 1.7), 0.2, iron, root, 12, 0.12)
		var knob := SphereMesh.new()
		knob.radius = 0.19
		knob.height = 0.38
		_mi(knob, iron, Vector3(0, 2.5, sd * 1.7), Basis(), root)
	# 둥글게 휘어 올라간 팔 + 잎 모양 갈고리 날
	var crown := SphereMesh.new()
	crown.radius = 0.36
	crown.height = 0.72
	_mi(crown, iron, Vector3(0, -3.0, 0), Basis(), root)
	for sd: float in [-1.0, 1.0]:
		var prev := Vector3(0, -3.0, 0)
		var steps := 7
		for k in steps:
			var t := 1.3 * float(k + 1) / steps
			var nx := Vector3(sd * 2.0 * sin(t), -3.0 + 1.7 * (1.0 - cos(t)), 0)
			var r0 := lerpf(0.27, 0.16, float(k) / steps)
			var r1 := lerpf(0.27, 0.16, float(k + 1) / steps)
			_rod(prev, nx, r0, iron, root, 12, r1)
			var joint := SphereMesh.new()
			joint.radius = r1
			joint.height = r1 * 2.0
			_mi(joint, iron, nx, Basis(), root)
			prev = nx
		var fluke := SphereMesh.new()
		fluke.radius = 0.5
		fluke.height = 1.0
		var fm := _mi(fluke, iron, prev + Vector3(sd * -0.12, -0.1, 0), Basis(Vector3(0, 0, 1), sd * -0.5), root)
		fm.scale = Vector3(0.62, 1.0, 0.16)
	# 쇠사슬: 고리에서 풀려 모래 위에 늘어짐
	var ring_at := Basis(Vector3.UP, yaw) * Vector3(-4.2, 0, 0)
	var dir := (Basis(Vector3.UP, yaw + 0.5) * Vector3(-1, 0, 0)).normalized()
	var cp := p + ring_at
	for k in 16:
		var q := cp + dir * (k * 0.4) + Vector3(-dir.z, 0, dir.x) * sin(k * 0.5) * 0.4
		var gy := ground_height(q.x, q.z)
		var link := _torus_mesh(0.2, 0.055)
		var lb := Basis(Vector3.UP, atan2(dir.x, dir.z) + cos(k * 0.5) * 0.4) * (Basis(Vector3(0, 0, 1), PI / 2 - 0.5) if k % 2 == 0 else Basis())
		_mi(link, iron, Vector3(q.x, gy + (0.14 if k % 2 == 0 else 0.05), q.z), lb * Basis(Vector3(1, 0, 0), PI / 2))
	_block(Vector2(p.x, p.z), 3.5)


## 가라앉은 화물: 대포 · 나무통 · 상자
func _cargo(at: Vector2) -> void:
	var wood := _smat(Color(0.5, 0.34, 0.2), "wood")
	var dark := _smat(Color(0.3, 0.2, 0.12), "wood")
	var iron := _smat(Color(0.2, 0.2, 0.22), "iron", 0.0, 0.3)
	var band := _mat(Color(0.35, 0.33, 0.3), 0.5, 0.6)
	for k in 3:
		var cp := _find_free(at.x + _rng.randfn(0.0, 3.0), at.y + _rng.randfn(0.0, 3.0), 1.3, 1.0)
		if cp.x == INF:
			continue
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		_mi(_cyl(0.22, 0.36, 2.6, 14), iron, cp + Vector3(0, 0.62, 0) + b * Vector3(0, 0, 0.2), b * Basis(Vector3(1, 0, 0), PI / 2 - 0.15))
		_mi(_torus_mesh(0.3, 0.07), iron, cp + Vector3(0, 0.75, 0) + b * Vector3(0, 0, 1.45), b)
		_mi(_rbox(Vector3(1.0, 0.45, 1.4), 0.06), dark, cp + Vector3(0, 0.22, -0.2), b)
		for sd: float in [-1.0, 1.0]:
			_mi(_cyl(0.32, 0.32, 0.1, 12), dark, cp + Vector3(0, 0.3, 0) + b * Vector3(sd * 0.55, 0, -0.2), b * Basis(Vector3(0, 0, 1), PI / 2))
		_block(Vector2(cp.x, cp.z), 1.6)
	for k in 8:
		var bp := _find_free(at.x + _rng.randfn(0.0, 3.5), at.y + _rng.randfn(0.0, 3.5), 0.6, 1.0)
		if bp.x == INF:
			continue
		if k % 3 == 0:
			_mi(_rbox(Vector3(1.1, 1.0, 1.1), 0.06), wood, bp + Vector3(0, 0.5, 0), Basis(Vector3.UP, _rng.randf() * TAU))
		else:
			var lying := k % 3 == 1
			var bb := Basis(Vector3.UP, _rng.randf() * TAU) * (Basis(Vector3(1, 0, 0), PI / 2) if lying else Basis())
			var c := bp + Vector3(0, 0.45 if lying else 0.6, 0)
			_mi(_cyl(0.42, 0.42, 1.2, 14), wood, c, bb)
			for e: float in [-0.35, 0.35]:
				_mi(_cyl(0.45, 0.45, 0.08, 14), band, c + bb * Vector3(0, e, 0), bb)
		_block(Vector2(bp.x, bp.z), 0.8)


## 금빛 무늬가 빛나는 오벨리스크
func _obelisk(at: Vector2) -> void:
	var p := _find_free(at.x, at.y, 1.0, 1.0)
	if p.x == INF:
		return
	var stone := _smat(Color(0.3, 0.34, 0.38), "stone", 0.0, 0.35)
	var b := Basis(Vector3.UP, PI / 4 + _rng.randf_range(-0.2, 0.2))
	_mi(_rbox(Vector3(2.0, 0.5, 2.0), 0.08), stone, p + Vector3(0, 0.25, 0), b)
	_mi(_cyl(0.55, 0.85, 5.5, 4), stone, p + Vector3(0, 0.5 + 2.75, 0), b)
	_mi(_cyl(0.0, 0.58, 0.9, 4), _mat(Color(1.0, 0.78, 0.3), 0.25, 0.9), p + Vector3(0, 6.0 + 0.45, 0), b)
	var rune := _glow_mat(Color(0.35, 1.0, 0.8), 1.8)
	for k in 3:
		var y := 1.8 + k * 1.4
		var rr := lerpf(0.85, 0.55, (y - 0.5) / 5.5) + 0.02
		_mi(_cyl(rr, rr, 0.12, 4), rune, p + Vector3(0, y, 0), b)
	_block(Vector2(p.x, p.z), 1.5)


func _free_spot(x: float, z: float, r: float) -> bool:
	if absf(x) > half_w - 1.5 or absf(z) > half_d - 1.5:
		return false
	if _in_chasm(x, z):
		return false
	for i in _near(x, z):
		var sp: Dictionary = spaces[i]
		var b: Vector3 = sp["base"]
		var rr := PLAZA * 0.5 + 1.5 if sp["kind"] == "start" else 2.2
		if Vector2(x - b.x, z - b.z).length() < rr + r:
			return false
	# 길 사이 (연결선) 근처도 피함
	for pair in _near_links(x, z):
		var a: Vector3 = spaces[pair[0]]["base"]
		var b: Vector3 = spaces[pair[1]]["base"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(x - a.x, z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (ap - ab * t).length() < 1.4 + r:
			return false
	for ar in arches:
		if Vector2(x, z).distance_to(ar["at"]) < 3.5 + r:
			return false
	return not _is_blocked(x, z, r)


func _is_blocked(x: float, z: float, r: float) -> bool:
	var cx := floori(x / GRID)
	var cz := floori(z / GRID)
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var k := Vector2i(gx, gz)
			if _blocked_grid.has(k):
				for bl in _blocked_grid[k]:
					if Vector2(x, z).distance_to(bl[0]) < float(bl[1]) + r:
						return true
	return false


## 장식을 놓지 않을 자리 기록
func _block(at: Vector2, r: float) -> void:
	_blocked.append([at, r])
	var k := Vector2i(floori(at.x / GRID), floori(at.y / GRID))
	if not _blocked_grid.has(k):
		_blocked_grid[k] = []
	_blocked_grid[k].append([at, r])


var _rock_meshes: Array = []

## 바위 모양 몇 가지를 미리 만들어 두고 돌려 씀 (여러 겹 울퉁불퉁 + 바닥은 평평하게 묻힘)
func _rock_mesh() -> Mesh:
	if _rock_meshes.is_empty():
		for v in 8:
			var fn := FastNoiseLite.new()
			fn.seed = 100 + v
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.fractal_type = FastNoiseLite.FRACTAL_RIDGED if v % 2 == 0 else FastNoiseLite.FRACTAL_FBM
			fn.fractal_octaves = 4
			fn.frequency = 0.9
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 32
			sm.rings = 18
			var arr := sm.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				var d := verts[i]
				var k := 1.0 + fn.get_noise_3dv(d * 1.2) * 0.32
				var q := d * k
				# 납작한 면 (깎인 바위 느낌)
				if q.y > 0.55:
					q.y = lerpf(q.y, 0.55 + (q.y - 0.55) * 0.35, 0.8)
				if q.y < -0.25:
					q.y = -0.25 + (q.y + 0.25) * 0.3
				verts[i] = q
			# 노멀: 같은 자리 꼭짓점끼리 면 노멀을 모아 평균 (구 이음새에 줄이 안 생기게)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var acc := {}
			for t in range(0, idx.size(), 3):
				var a3 := verts[idx[t]]
				var b3 := verts[idx[t + 1]]
				var c3 := verts[idx[t + 2]]
				var fnrm := (b3 - a3).cross(c3 - a3)
				for vi in [idx[t], idx[t + 1], idx[t + 2]]:
					var key := Vector3i((verts[vi] * 1000.0).round())
					acc[key] = (acc.get(key, Vector3.ZERO) as Vector3) + fnrm
			var norms := PackedVector3Array()
			norms.resize(verts.size())
			var sgn := 1.0
			for i in verts.size():
				var nn: Vector3 = (acc[Vector3i((verts[i] * 1000.0).round())] as Vector3).normalized()
				norms[i] = nn
			# 바깥을 보도록 방향 맞추기
			if norms[0].dot(verts[0]) < 0.0 and norms[verts.size() / 2].dot(verts[verts.size() / 2]) < 0.0:
				sgn = -1.0
			for i in verts.size():
				norms[i] *= sgn
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_TANGENT] = null
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			_rock_meshes.append(am)
	return _rock_meshes[_rng.randi() % _rock_meshes.size()]


func _rock(p: Vector3, r: float) -> void:
	# 비탈에서는 낮은 쪽에 맞춰 묻음 (한쪽이 허공에 뜨지 않게)
	var lo := p.y
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		lo = minf(lo, ground_height(p.x + d.x * r * 0.7, p.z + d.y * r * 0.7))
	p.y = minf(p.y, lo + r * 0.12)
	var mi := _mi(_rock_mesh(), _rock_mat(_rng.randi() % 3), p)
	mi.scale = Vector3(r * _rng.randf_range(0.9, 1.3), r * _rng.randf_range(0.6, 0.85), r * _rng.randf_range(0.9, 1.2))
	mi.rotation = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf() * TAU, _rng.randf_range(-0.12, 0.12))


func _coral(p: Vector3, c: Color, size: float) -> void:
	var m := _smat(c, "coral")
	var tip := _smat(c.lightened(0.25), "coral")
	var stack := [[p, Vector3.UP, 0.9 * size, 0.13 * size, 3]]
	for k in 2:
		stack.append([p, Vector3(_rng.randf_range(-0.5, 0.5), 1.0, _rng.randf_range(-0.5, 0.5)).normalized(), 0.8 * size, 0.11 * size, 3])
	while stack.size() > 0:
		var it: Array = stack.pop_back()
		var a: Vector3 = it[0]
		var d: Vector3 = it[1]
		var ln: float = it[2]
		var rad: float = it[3]
		var depth: int = it[4]
		var b := a + d * ln
		var q := Quaternion(Vector3.UP, d)
		_mi(_cyl(rad * 0.75, rad, ln, 8), m, (a + b) * 0.5, Basis(q))
		if depth == 0:
			var s := SphereMesh.new()
			s.radius = rad * 0.8
			s.height = rad * 1.6
			s.radial_segments = 8
			s.rings = 4
			_mi(s, tip, b)
			continue
		for side in [-1.0, 1.0]:
			var nd := (d + Vector3(side * _rng.randf_range(0.35, 0.7), _rng.randf_range(0.05, 0.3), _rng.randf_range(-0.5, 0.5))).normalized()
			stack.append([b, nd, ln * 0.74, rad * 0.74, depth - 1])


func _sponge(p: Vector3, c: Color) -> void:
	var m := _smat(c, "coral")
	var inner := _mat(c.darkened(0.6), 0.9)
	for k in _rng.randi_range(3, 5):
		var off := Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
		var h := _rng.randf_range(1.0, 2.2)
		var r := _rng.randf_range(0.18, 0.28)
		_mi(_cyl(r, r * 1.1, h, 12), m, p + off + Vector3(0, h * 0.5, 0))
		_mi(_cyl(r * 0.75, r * 0.75, 0.02, 12), inner, p + off + Vector3(0, h + 0.005, 0))


func _rock_mat(k: int) -> ShaderMaterial:
	var key := "rock_%d" % k
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = RockShader
		m.set_shader_parameter("rock_color", [Color(0.52, 0.52, 0.48), Color(0.47, 0.5, 0.47), Color(0.56, 0.52, 0.47)][k % 3])
		m.set_shader_parameter("rock_tex", _mip_tex(RockAlbedo))
		m.set_shader_parameter("rock_nrm", _mip_tex(RockNormal))
		_mats[key] = m
	return _mats[key]


func _kelp(p: Vector3, h: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = KelpShader
	m.set_shader_parameter("phase", _rng.randf() * TAU)
	m.set_shader_parameter("height", h)
	m.set_shader_parameter("tip_color", Color(0.62, 0.68, 0.22).lerp(Color(0.42, 0.66, 0.3), _rng.randf()))
	_mi(ReefKit.kelp_mesh(_rng, h), m, p, Basis(Vector3.UP, _rng.randf() * TAU))
	# 공기주머니
	var bl := SphereMesh.new()
	bl.radius = 0.09
	bl.height = 0.18
	bl.radial_segments = 8
	bl.rings = 4
	for k in 2:
		_mi(bl, _mat(Color(0.66, 0.6, 0.22), 0.3), p + Vector3(_rng.randf_range(-0.2, 0.2), h * _rng.randf_range(0.2, 0.5), _rng.randf_range(-0.2, 0.2)))


## 뇌산호
func _brain(p: Vector3, c: Color, size: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = BrainShader
	m.set_shader_parameter("color", c)
	var mi := _mi(ReefKit.brain_mesh(_rng), m, p - Vector3(0, 0.05, 0))
	mi.scale = Vector3(size, size, size) * _rng.randf_range(0.5, 0.8)


## 탁자산호 (줄기 위에 넓적한 판)
func _table_coral(p: Vector3, c: Color, size: float) -> void:
	var m := _smat(c, "coral")
	var h := 0.9 * size
	_mi(_cyl(0.12 * size, 0.2 * size, h, 10), m, p + Vector3(0, h * 0.5, 0))
	for k in 2:
		var r := (1.0 - k * 0.35) * size
		var plate := _cyl(r, r * 0.92, 0.1, 20)
		_mi(plate, m if k == 0 else _smat(c.lightened(0.2), "coral"), p + Vector3(_rng.randf_range(-0.2, 0.2), h + k * 0.35, _rng.randf_range(-0.2, 0.2)),
			Basis(Vector3(1, 0, 0), _rng.randf_range(-0.12, 0.12)))


## 부채산호 (그물 무늬 판, 양면)
func _fan_coral(p: Vector3, c: Color, size: float) -> void:
	var key := "fan_" + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = FAN_TEX
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.6
		m.emission_enabled = true
		m.emission = c * 0.15
		_mats[key] = m
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0) * size
	var mi := _mi(q, _mats[key], p + Vector3(0, size * 0.95, 0), Basis(Vector3.UP, _rng.randf() * TAU))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 말미잘
func _anemone(p: Vector3, c: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = AnemoneShader
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("tip_color", c.lightened(0.55))
	m.set_shader_parameter("phase", _rng.randf() * TAU)
	var mi := _mi(ReefKit.anemone_mesh(_rng), m, p)
	mi.scale = Vector3.ONE * _rng.randf_range(0.9, 1.4)


## 항아리 (옛날 배에서 떨어진)
func _amphora(p: Vector3, tipped: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := [Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.17, 0.02), Vector2(0.24, 0.1), Vector2(0.3, 0.2), Vector2(0.35, 0.32), Vector2(0.38, 0.44),
		Vector2(0.385, 0.54), Vector2(0.36, 0.66), Vector2(0.31, 0.77), Vector2(0.23, 0.87), Vector2(0.16, 0.94),
		Vector2(0.13, 0.98), Vector2(0.12, 1.15), Vector2(0.19, 1.22)]
	var n := 32
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for j in n:
			var t0 := TAU * j / n
			var t1 := TAU * (j + 1) / n
			var v := [Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x), Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x),
				Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x), Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)]
			var out := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = v[tri[0]]
				var B: Vector3 = v[tri[1]]
				var C: Vector3 = v[tri[2]]
				if (B - A).cross(C - A).dot(out) > 0.0:
					var tmp := B
					B = C
					C = tmp
				st.add_vertex(A)
				st.add_vertex(B)
				st.add_vertex(C)
	st.index()
	st.generate_normals()
	var b := Basis(Vector3.UP, _rng.randf() * TAU)
	if tipped:
		b = b * Basis(Vector3(0, 0, 1), PI / 2 - 0.15)
	var mi := _mi(st.commit(), _smat(Color(0.78, 0.45, 0.3), "clay"), p + (Vector3(0, 0.35, 0) if tipped else Vector3.ZERO), b)
	mi.scale = Vector3.ONE * 1.3


## 가라앉은 보물상자 (반짝반짝 금화)
func _treasure(p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = _rng.randf_range(-0.6, 0.6)
	add_child(root)
	var wood := _smat(Color(0.45, 0.27, 0.15), "wood", 0.0, 0.3)
	var gold := _mat(Color(1.0, 0.8, 0.3), 0.2, 0.9)
	_mi(_rbox(Vector3(1.6, 0.9, 1.0), 0.06), wood, Vector3(0, 0.45, 0), Basis(), root)
	for x in [-0.6, 0.0, 0.6]:
		_mi(_box(Vector3(0.12, 0.94, 1.04)), gold, Vector3(x, 0.45, 0), Basis(), root)
	# 열린 뚜껑
	var lid := _cyl(0.5, 0.5, 1.6, 16)
	var lid_mi := _mi(lid, wood, Vector3(0, 1.05, -0.55), Basis(Vector3(0, 0, 1), PI / 2), root)
	lid_mi.scale = Vector3(1, 1, 0.55)
	# 금화 무더기
	var coin := _cyl(0.13, 0.13, 0.03, 12)
	for k in 26:
		var a := _rng.randf() * TAU
		var r := _rng.randf() * 0.6
		var cp := Vector3(cos(a) * r * 0.9, 0.92 + _rng.randf() * 0.15, sin(a) * r * 0.5)
		if k > 16:
			cp = Vector3(_rng.randf_range(-1.4, 1.4), 0.03, _rng.randf_range(0.5, 1.3))
		_mi(coin, gold, cp, Basis(Vector3(1, 0, 0), _rng.randf_range(-0.5, 0.5)), root)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.82, 0.4)
	glow.light_energy = 1.2
	glow.omni_range = 3.5
	glow.position = Vector3(0, 1.3, 0.2)
	root.add_child(glow)
	_block(Vector2(p.x, p.z), 2.0)


## 여러 개를 한 번에 그리기 (MultiMesh)
func _multi(mesh: Mesh, mat: Material, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if colors.size() > 0:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


## 해초밭 (덤불 수백 개)
func _seagrass() -> void:
	var meshes := [ReefKit.grass_clump_mesh(_rng, 6, 0.8), ReefKit.grass_clump_mesh(_rng, 5, 1.1), ReefKit.grass_clump_mesh(_rng, 8, 0.6)]
	var m := ShaderMaterial.new()
	m.shader = SeagrassShader
	var lists := [[], [], []]
	for patch in int(cfg.get("seagrass", 22)):
		var cx := _rng.randf_range(-half_w + 3, half_w - 3)
		var cz := _rng.randf_range(-half_d + 3, half_d - 3)
		var rad := _rng.randf_range(1.5, 3.2)
		for k in 55:
			var x := cx + _rng.randfn(0.0, rad * 0.5)
			var z := cz + _rng.randfn(0.0, rad * 0.5)
			if not _free_spot(x, z, 0.1):
				continue
			var y := ground_height(x, z)
			if y < -1.0:
				continue
			var sc := _rng.randf_range(0.7, 1.3)
			var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, y - 0.03, z))
			lists[_rng.randi() % 3].append(t)
	# 길가 풀 (길 가장자리를 따라 듬성듬성)
	for i in spaces.size():
		var a: Vector3 = spaces[i]["base"]
		for j in spaces[i]["links"]:
			if j < i:
				continue
			var b: Vector3 = spaces[j]["base"]
			var dir := Vector3(b.x - a.x, 0, b.z - a.z)
			if dir.length() < 0.1:
				continue
			var side := Vector3(dir.z, 0, -dir.x).normalized()
			for k in 3:
				var p := a.lerp(b, _rng.randf_range(0.2, 0.8)) + side * (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(1.7, 2.3)
				if not _free_spot(p.x, p.z, 0.1):
					continue
				var y := ground_height(p.x, p.z)
				if y < -1.0:
					continue
				var sc := _rng.randf_range(0.5, 0.95)
				lists[_rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, y - 0.03, p.z)))
	for i in 3:
		if lists[i].size() > 0:
			_multi(meshes[i], m, lists[i])


## 바닥에 흩어진 불가사리·조개·자갈
func _scatter() -> void:
	var star_cols := [Color(1.0, 0.5, 0.25), Color(1.0, 0.42, 0.55), Color(0.62, 0.42, 0.95), Color(1.0, 0.78, 0.3)]
	var shell_cols := [Color(0.99, 0.92, 0.82), Color(1.0, 0.76, 0.66), Color(0.98, 0.7, 0.78)]
	var pebble_cols := [Color(0.72, 0.7, 0.64), Color(0.86, 0.83, 0.75), Color(0.6, 0.62, 0.6), Color(0.9, 0.78, 0.72)]
	var vm := StandardMaterial3D.new()
	vm.vertex_color_use_as_albedo = true
	vm.roughness = 0.5
	var sets := {"star": [[], []], "shell": [[], []], "pebble": [[], []]}
	var want: Dictionary = cfg.get("scatter", {"star": 34, "shell": 40, "pebble": 420})
	for kind in want:
		var n := 0
		var tries := 0
		while n < int(want[kind]) and tries < int(want[kind]) * 8:
			tries += 1
			var x := _rng.randf_range(-half_w + 1.5, half_w - 1.5)
			var z := _rng.randf_range(-half_d + 1.5, half_d - 1.5)
			if not _free_spot(x, z, 0.1):
				continue
			var y := ground_height(x, z)
			var sc := 0.0
			var col := Color.WHITE
			var b := Basis(Vector3.UP, _rng.randf() * TAU)
			match kind:
				"star":
					sc = _rng.randf_range(0.22, 0.36)
					col = star_cols[_rng.randi() % star_cols.size()]
				"shell":
					sc = _rng.randf_range(0.18, 0.3)
					col = shell_cols[_rng.randi() % shell_cols.size()]
				_:
					sc = _rng.randf_range(0.06, 0.16)
					col = pebble_cols[_rng.randi() % pebble_cols.size()]
					b = b.scaled(Vector3(1.0, 0.55, 1.0))
			sets[kind][0].append(Transform3D(b.scaled(Vector3.ONE * sc), Vector3(x, y + 0.01, z)))
			sets[kind][1].append(col)
			n += 1
	var pm := SphereMesh.new()
	pm.radius = 1.0
	pm.height = 2.0
	pm.radial_segments = 8
	pm.rings = 4
	_multi(ReefKit.starfish_mesh(), vm, sets["star"][0], sets["star"][1])
	_multi(ReefKit.shell_mesh(), vm, sets["shell"][0], sets["shell"][1])
	_multi(pm, vm, sets["pebble"][0], sets["pebble"][1])


## 물고기 떼 (셰이더가 헤엄치게 함)
func _fish_school(center: Vector3, radius: float, count: int, speed: float, length: float, col_a: Color, col_b: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = ReefKit.fish_mesh(length)
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(_rng.randfn(0.0, 0.35), _rng.randfn(0.0, 0.9), _rng.randfn(0.0, 0.6), _rng.randf()))
	var m := ShaderMaterial.new()
	m.shader = FishShader
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("color_a", col_a)
	m.set_shader_parameter("color_b", col_b)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## 해파리 (둥실둥실)
func _jelly(p: Vector3, c: Color) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.8
	m.roughness = 0.2
	var dome := SphereMesh.new()
	dome.radius = 0.55
	dome.height = 0.7
	dome.is_hemisphere = true
	dome.radial_segments = 20
	dome.rings = 8
	var bell := MeshInstance3D.new()
	bell.mesh = dome
	bell.material_override = m
	bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bell)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(c.lightened(0.3), 0.45)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.emission_enabled = true
	tm.emission = c.lightened(0.3)
	tm.emission_energy_multiplier = 0.6
	for k in 7:
		var a := TAU * k / 7.0
		var ln := _rng.randf_range(0.9, 1.6)
		var t := MeshInstance3D.new()
		t.mesh = _cyl(0.025, 0.012, ln, 5)
		t.material_override = tm
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.position = Vector3(cos(a) * 0.32, -ln * 0.5, sin(a) * 0.32)
		root.add_child(t)
	_jellies.append({"node": root, "base": p, "phase": _rng.randf() * TAU})


## 빈자리 찾기 (가까운 곳부터)
func _find_free(x: float, z: float, r: float, spread: float = 3.0) -> Vector3:
	for t in 60:
		var xx := x + (_rng.randfn(0.0, spread) if t > 0 else 0.0)
		var zz := z + (_rng.randfn(0.0, spread) if t > 0 else 0.0)
		if _free_spot(xx, zz, r):
			return Vector3(xx, ground_height(xx, zz), zz)
	return Vector3(INF, 0, 0)


func _decor() -> void:
	var coral_cols := [Color(1.0, 0.4, 0.38), Color(1.0, 0.6, 0.28), Color(0.76, 0.42, 0.98), Color(1.0, 0.38, 0.64), Color(1.0, 0.84, 0.38),
		Color(0.35, 0.85, 0.8)]
	# 보물상자 · 항아리 (먼저 자리 잡기)
	for at in cfg.get("treasures", []):
		var tp := _find_free(at.x, at.y, 1.5)
		if tp.x != INF:
			_treasure(tp)
	for at in cfg.get("amphoras", []):
		var ap := _find_free(at.x, at.y, 0.6, 1.5)
		if ap.x != INF:
			_amphora(ap, _rng.randf() < 0.5)
			_block(Vector2(ap.x, ap.z), 0.9)
	# 산호 무리
	for z in cfg.get("decor_zones", []):
		var c: Vector2 = z[0]
		for k in z[2]:
			for t in 20:
				var x: float = c.x + _rng.randfn(0.0, z[1])
				var zz: float = c.y + _rng.randfn(0.0, z[1])
				if _free_spot(x, zz, 0.8):
					var p := Vector3(x, ground_height(x, zz), zz)
					var col: Color = coral_cols[_rng.randi() % coral_cols.size()]
					var roll := _rng.randf()
					if roll < 0.32:
						_coral(p, col, _rng.randf_range(0.8, 1.4))
					elif roll < 0.47:
						_brain(p, col.lerp(Color(0.95, 0.85, 0.6), 0.4), _rng.randf_range(0.9, 1.4))
					elif roll < 0.6:
						_table_coral(p, col, _rng.randf_range(0.7, 1.1))
					elif roll < 0.74:
						_fan_coral(p, col, _rng.randf_range(0.8, 1.3))
					elif roll < 0.87:
						_anemone(p, col)
					else:
						_sponge(p, col)
					_block(Vector2(x, zz), 0.6)
					break
	# 바위
	for k in int(cfg.get("rocks", 40)):
		for t in 20:
			var x := _rng.randf_range(-half_w + 2, half_w - 2)
			var zz := _rng.randf_range(-half_d + 2, half_d - 2)
			var r := _rng.randf_range(0.5, 1.6) if _rng.randf() < 0.85 else _rng.randf_range(1.8, 2.8)
			if _free_spot(x, zz, r):
				_rock(Vector3(x, ground_height(x, zz) - r * 0.25, zz), r)
				_block(Vector2(x, zz), r * 0.8)
				break
	# 다시마 숲 + 판 가장자리 (가운데 길 쪽은 비워서 카메라를 가리지 않게)
	for kf in cfg.get("kelp_forests", []):
		var c: Vector2 = kf[0]
		var spread: Vector2 = kf[1]
		for k in int(kf[2]):
			for t in 10:
				var x := c.x + _rng.randfn(0.0, spread.x)
				var zz := c.y + _rng.randfn(0.0, spread.y)
				if _free_spot(x, zz, 0.4):
					_kelp(Vector3(x, ground_height(x, zz), zz), _rng.randf_range(4.0, 7.5))
					break
	for k in int(cfg.get("kelp_edge", 40)):
		for t in 10:
			var x := _rng.randf_range(-half_w + 1.5, half_w - 1.5)
			var zz := _rng.randf_range(-half_d + 1.5, half_d - 1.5)
			if absf(x) < half_w - 5.0 and absf(zz) < half_d - 4.0:
				continue
			if _free_spot(x, zz, 0.4):
				_kelp(Vector3(x, ground_height(x, zz), zz), _rng.randf_range(3.5, 6.5))
				break
	# 언덕 가장자리 바위 (절벽 아래가 맨땅으로 뚝 끊기지 않게)
	for pl in plateaus:
		var pc: Vector2 = pl["c"]
		var pr: Vector2 = pl["r"]
		var pn := int((pr.x + pr.y) * 1.7)
		for k in pn:
			var a := TAU * k / pn + _rng.randf_range(-0.12, 0.12)
			var f := _rng.randf_range(1.03, 1.2)
			var x := pc.x + cos(a) * pr.x * f
			var z := pc.y + sin(a) * pr.y * f
			var rr := _rng.randf_range(0.45, 1.25)
			if _free_spot(x, z, rr * 0.7):
				_rock(Vector3(x, ground_height(x, z) - rr * 0.3, z), rr)
				_block(Vector2(x, z), rr * 0.8)
	# 칸 받침 모서리에 자잘한 돌 · 풀 (칸이 땅에 붙어 있는 느낌)
	var peb := SphereMesh.new()
	peb.radius = 0.12
	peb.height = 0.12
	peb.radial_segments = 10
	peb.rings = 5
	var peb_cols := [Color(0.6, 0.58, 0.52), Color(0.7, 0.62, 0.55), Color(0.5, 0.56, 0.52), Color(0.66, 0.64, 0.6)]
	var px_list := []
	var pc_list := []
	for sp in spaces:
		if sp["kind"] == "start" or sp.get("deck", false) or _in_chasm((sp["base"] as Vector3).x, (sp["base"] as Vector3).z):
			continue
		var b3: Vector3 = sp["base"]
		var tb := Basis(Vector3.UP, sp["yaw"])
		var half := TILE * 0.5 + 0.3
		for corner in 4:
			if _rng.randf() < 0.55:
				continue
			var cx := -1.0 if corner % 2 == 0 else 1.0
			var cz := -1.0 if corner < 2 else 1.0
			var cp := b3 + tb * Vector3(cx * half, 0, cz * half)
			for q in _rng.randi_range(2, 4):
				var o := Vector3(_rng.randf_range(-0.35, 0.35), 0, _rng.randf_range(-0.35, 0.35))
				var pp := cp + o
				var sc := _rng.randf_range(0.6, 1.4)
				px_list.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * 0.7, sc * 1.2)), Vector3(pp.x, ground_height(pp.x, pp.z) + 0.02, pp.z)))
				pc_list.append(peb_cols[_rng.randi() % peb_cols.size()])
	if px_list.size() > 0:
		var pm := StandardMaterial3D.new()
		pm.vertex_color_use_as_albedo = true
		pm.roughness = 0.75
		_multi(peb, pm, px_list, pc_list)
	# 험한 길 옆 큰 바위들
	for sp in spaces:
		if not sp.get("rough", false):
			continue
		var b3: Vector3 = sp["base"]
		var side := Basis(Vector3.UP, sp["yaw"]).x
		for sd: float in [-1.0, 1.0]:
			if _rng.randf() < 0.45:
				continue
			var q := b3 + side * sd * _rng.randf_range(2.4, 3.2)
			var rr := _rng.randf_range(0.6, 1.2)
			if _free_spot(q.x, q.z, rr * 0.6):
				_rock(Vector3(q.x, ground_height(q.x, q.z) - rr * 0.2, q.z), rr)
				_block(Vector2(q.x, q.z), rr * 0.8)
	_seagrass()
	_scatter()
	# 물고기 떼
	for f in cfg.get("fish", []):
		_fish_school(f[0], f[1], f[2], f[3], f[4], f[5], f[6])
	# 해파리
	for jp in cfg.get("jellies", []):
		_jelly(jp, [Color(1.0, 0.55, 0.8), Color(0.65, 0.6, 1.0), Color(0.5, 0.95, 0.95)][_rng.randi() % 3])


# ── 물방울·빛줄기 ────────────────────────────────────────────
func _bubble_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 1.0, 0.97, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 0.65)
	m.emission_energy_multiplier = 0.4
	s.material = m
	return s


func bubbles_at(p: Vector3, amount: int, radius: float, one_shot: bool = false) -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.mesh = _bubble_mesh(0.09)
	c.amount = amount
	c.lifetime = 4.0
	c.one_shot = one_shot
	c.explosiveness = 0.9 if one_shot else 0.0
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	c.emission_sphere_radius = radius
	c.direction = Vector3.UP
	c.spread = 18.0
	c.gravity = Vector3(0, 1.4, 0)
	c.initial_velocity_min = 0.6
	c.initial_velocity_max = 1.6
	c.scale_amount_min = 0.5
	c.scale_amount_max = 2.2
	c.position = p
	add_child(c)
	c.emitting = true
	return c


func _effects() -> void:
	for v in volcanoes:
		var at: Vector2 = v["at"]
		bubbles_at(Vector3(at.x, natural_height(at.x, at.y) + 0.5, at.y), 40, 0.6)
	for c in chasms:
		var cc: Vector2 = c["c"]
		bubbles_at(Vector3(cc.x, -float(c["depth"]) + 0.5, cc.y), 14, 1.5)
	# 떠다니는 알갱이
	var snow := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 4
	sm.rings = 2
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 1.0, 0.95, 0.5)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	snow.mesh = sm
	snow.amount = int(400 * clampf(half_w * half_d / 400.0, 1.0, 5.0))
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(half_w, 4.0, half_d)
	snow.position = Vector3(0, 4.0, 0)
	snow.gravity = Vector3(0, -0.03, 0)
	snow.initial_velocity_min = 0.0
	snow.initial_velocity_max = 0.15
	snow.spread = 180.0
	add_child(snow)
	# 빛줄기
	for k in int(cfg.get("rays", 9)):
		var q := QuadMesh.new()
		q.size = Vector2(_rng.randf_range(2.0, 5.0), 34.0)
		var m := ShaderMaterial.new()
		m.shader = RayShader
		m.set_shader_parameter("phase", _rng.randf() * TAU)
		m.set_shader_parameter("strength", _rng.randf_range(0.025, 0.06))
		var p := Vector3(_rng.randf_range(-half_w, half_w), 14.0, _rng.randf_range(-half_d, half_d))
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3(0, 0, 1), deg_to_rad(18))
		_mi(q, m, p, b)


# ── 칸 소품 (포탈 고리 · 상점 노점 · 찬스 카드) ───────────────
func _unshaded(c: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _tile_props() -> void:
	for i in spaces.size():
		match String(spaces[i]["kind"]):
			"portal":
				_portal_gate(i)
			"shop":
				_shop_stall(i)
			"chance":
				_chance_card(i)


## 포탈: 칸 위에 서 있는 빛나는 고리 (말이 그 사이를 지나감) + 반짝이 + 보라 불빛
func _portal_gate(i: int) -> void:
	var sp: Dictionary = spaces[i]
	var top: Vector3 = sp["pos"]
	var yaw := _path_yaw(i)
	var ring_mat := _unshaded(Color(0.72, 0.48, 1.0), 2.2)
	var t := TorusMesh.new()
	t.inner_radius = 1.04
	t.outer_radius = 1.26
	t.rings = 40
	t.ring_segments = 12
	var pivot := Node3D.new()
	pivot.position = top + Vector3(0, 1.3, 0)
	pivot.basis = Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI / 2)
	add_child(pivot)
	var ring := MeshInstance3D.new()
	ring.mesh = t
	ring.material_override = ring_mat
	pivot.add_child(ring)
	# 고리 바깥 돌테
	var t2 := TorusMesh.new()
	t2.inner_radius = 1.24
	t2.outer_radius = 1.4
	t2.rings = 40
	t2.ring_segments = 8
	var frame := MeshInstance3D.new()
	frame.mesh = t2
	frame.material_override = _mat(Color(0.36, 0.3, 0.46), 0.6, 0.2)
	pivot.add_child(frame)
	# 받침돌 두 개
	var side := Basis(Vector3.UP, yaw).x
	for sgn in [-1.0, 1.0]:
		_mi(_rbox(Vector3(0.42, 0.34, 0.5), 0.09), _mat(Color(0.4, 0.34, 0.5), 0.45, 0.3), top + side * (1.18 * sgn) + Vector3(0, 0.12, 0), Basis(Vector3.UP, yaw))
	# 고리 둘레 반짝이
	var sparks := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _unshaded(Color(0.92, 0.8, 1.0), 3.0)
	sparks.mesh = sm
	sparks.amount = 36
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3(0, 1, 0)   # 고리 축 (피벗 기준)
	sparks.emission_ring_radius = 1.15
	sparks.emission_ring_inner_radius = 0.9
	sparks.emission_ring_height = 0.1
	sparks.direction = Vector3(0, 0, 0)
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 0.05
	sparks.initial_velocity_max = 0.3
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 1.2
	pivot.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.45, 1.0)
	light.light_energy = 1.6
	light.omni_range = 5.5
	light.position = top + Vector3(0, 1.0, 0)
	add_child(light)
	_portal_fx.append({"node": pivot, "mat": ring_mat, "light": light, "phase": float(i)})
	_block(Vector2(top.x, top.z), 2.0)


## 상점: 칸 옆에 줄무늬 차양을 친 작은 노점
func _shop_stall(i: int) -> void:
	var sp: Dictionary = spaces[i]
	var base: Vector3 = sp["base"]
	var yaw := _path_yaw(i)
	var side := Basis(Vector3.UP, yaw).x
	var at := Vector3.ZERO
	var dir := 0.0
	for sgn in [1.0, -1.0]:
		var c: Vector3 = base + side * (2.9 * sgn)
		if _stall_ok(c, i):
			at = c
			dir = sgn
			break
	if dir == 0.0:
		at = base + side * 2.9
		dir = 1.0
	at.y = base.y
	# 노점 정면(+Z)이 칸을 보게
	var face := -side * dir
	var b := Basis(Vector3.UP, atan2(face.x, face.z))
	var root := Node3D.new()
	root.transform = Transform3D(b, at)
	add_child(root)
	var wood := _smat(Color(0.55, 0.36, 0.22), "wood", 0.0, 0.15)
	var light_wood := _smat(Color(0.78, 0.6, 0.4), "wood", 0.0, 0.1)
	var pink := _mat(Color(0.94, 0.43, 0.56), 0.55)
	var cream := _mat(Color(0.99, 0.95, 0.88), 0.55)
	# 받침 + 계산대
	_mi(_box(Vector3(2.3, 0.9, 1.7)), _mat(Color(0.6, 0.6, 0.56), 0.9), Vector3(0, -0.37, 0), Basis(), root)
	_mi(_box(Vector3(1.9, 0.9, 0.7)), wood, Vector3(0, 0.53, 0.35), Basis(), root)
	_mi(_box(Vector3(2.05, 0.08, 0.86)), light_wood, Vector3(0, 1.02, 0.35), Basis(), root)
	_mi(_box(Vector3(1.6, 0.12, 0.02)), pink, Vector3(0, 0.75, 0.71), Basis(), root)
	# 기둥
	for x in [-0.9, 0.9]:
		_mi(_cyl(0.06, 0.07, 2.5, 8), wood, Vector3(x, 1.3, -0.45), Basis(), root)
		_mi(_cyl(0.06, 0.07, 2.15, 8), wood, Vector3(x, 1.12, 0.66), Basis(), root)
	# 줄무늬 차양 (앞으로 기울어짐)
	var tilt := Basis(Vector3(1, 0, 0), 0.32)
	for k in 7:
		var x := -1.05 + 0.35 * k
		_mi(_box(Vector3(0.35, 0.05, 1.5)), pink if k % 2 == 0 else cream, Vector3(x + 0.175, 2.35, 0.12), tilt, root)
	# 차양 끝 물결 장식
	for k in 7:
		var x := -0.875 + 0.35 * k
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.2
		sph.radial_segments = 10
		sph.rings = 5
		_mi(sph, pink if k % 2 == 0 else cream, Vector3(x, 2.05, 0.86), Basis(), root)
	# 간판 (쇼핑백 그림)
	_mi(_box(Vector3(0.9, 0.9, 0.08)), pink, Vector3(0, 2.95, -0.2), Basis(), root)
	var q := QuadMesh.new()
	q.size = Vector2(0.72, 0.72)
	var icon_m := StandardMaterial3D.new()
	icon_m.albedo_texture = ICONS["shop"]
	icon_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	icon_m.alpha_scissor_threshold = 0.4
	icon_m.emission_enabled = true
	icon_m.emission = Color(0.4, 0.35, 0.35)
	_mi(q, icon_m, Vector3(0, 2.95, -0.155), Basis(), root)
	# 물건: 진주, 작은 보물상자, 병
	var pearl := SphereMesh.new()
	pearl.radius = 0.12
	pearl.height = 0.24
	for k in 3:
		_mi(pearl, _mat(Color(0.95, 0.93, 1.0).lerp(Color(1.0, 0.75, 0.85), k * 0.4), 0.15, 0.3), Vector3(-0.65 + k * 0.22, 1.18, 0.35), Basis(), root)
	_mi(_box(Vector3(0.42, 0.28, 0.3)), _mat(Color(0.6, 0.38, 0.18), 0.6), Vector3(0.25, 1.2, 0.3), Basis(), root)
	_mi(_box(Vector3(0.44, 0.06, 0.32)), _mat(Color(0.95, 0.75, 0.25), 0.3, 0.6), Vector3(0.25, 1.36, 0.3), Basis(), root)
	_mi(_cyl(0.08, 0.1, 0.36, 10), _mat(Color(0.35, 0.8, 0.7), 0.1), Vector3(0.7, 1.24, 0.38), Basis(), root)
	# 등불
	var lamp := SphereMesh.new()
	lamp.radius = 0.13
	lamp.height = 0.26
	_mi(lamp, _unshaded(Color(1.0, 0.8, 0.45), 2.5), Vector3(0.7, 1.95, 0.75), Basis(), root)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.5)
	l.light_energy = 1.0
	l.omni_range = 4.0
	l.position = Vector3(0.7, 1.9, 0.9)
	root.add_child(l)
	_block(Vector2(at.x, at.z), 1.8)


func _stall_ok(c: Vector3, own: int) -> bool:
	if _in_chasm(c.x, c.z) or absf(c.x) > half_w - 1.5 or absf(c.z) > half_d - 1.5:
		return false
	if absf(natural_height(c.x, c.z) - (spaces[own]["base"] as Vector3).y) > 0.9:
		return false
	if _is_blocked(c.x, c.z, 1.2):
		return false
	for j in spaces.size():
		if j == own:
			continue
		var b: Vector3 = spaces[j]["base"]
		var r := PLAZA * 0.5 + 1.0 if spaces[j]["kind"] == "start" else 2.4
		if Vector2(c.x - b.x, c.z - b.z).length() < r:
			return false
	for i in spaces.size():
		for j in spaces[i]["links"]:
			var a: Vector3 = spaces[i]["base"]
			var b: Vector3 = spaces[j]["base"]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := Vector2(c.x - a.x, c.z - a.z)
			var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if (ap - ab * t).length() < 1.7:
				return false
	return true


## 찬스: 칸 위에 떠서 빙글빙글 도는 ? 카드
func _chance_card(i: int) -> void:
	var top: Vector3 = spaces[i]["pos"]
	var pivot := Node3D.new()
	pivot.position = top + Vector3(0, 2.9, 0)
	add_child(pivot)
	var m := StandardMaterial3D.new()
	m.albedo_texture = CHANCE_CARD_TEX
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.emission_enabled = true
	m.emission_texture = CHANCE_CARD_TEX
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.45
	m.roughness = 0.35
	for back in [false, true]:
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.position = Vector3(0, 0, -0.012 if back else 0.012)
		mi.rotation.y = PI if back else 0.0
		pivot.add_child(mi)
	# 카드 아래 작은 빛
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.35)
	glow.light_energy = 0.8
	glow.omni_range = 3.0
	pivot.add_child(glow)
	_spinners.append({"node": pivot, "base_y": pivot.position.y, "phase": float(i) * 0.7})


## 칸에서 길이 나가는 방향 (yaw)
func _path_yaw(i: int) -> float:
	var sp: Dictionary = spaces[i]
	var links: Array = sp["links"]
	if links.size() >= 2:
		var a: Vector3 = spaces[links[0]]["base"]
		var b: Vector3 = spaces[links[1]]["base"]
		var d := b - a
		return atan2(d.x, d.z)
	return float(sp["yaw"])


func _process(delta: float) -> void:
	_time += delta
	for s in _spinners:
		var n: Node3D = s["node"]
		n.rotation.y += delta * 1.3
		n.position.y = float(s["base_y"]) + sin(_time * 2.0 + float(s["phase"])) * 0.15
	if _trophy_node:
		_trophy_node.rotation.y += delta * 1.2
		var cup := _trophy_node.get_child(0) as Node3D
		cup.position.y = 2.6 + sin(_time * 2.2) * 0.18
	for r in _rotors:
		(r[0] as Node3D).rotation.y += delta * float(r[1])
	for i in _dangers:
		var dd: Dictionary = _dangers[i]
		var dn: Dictionary = dd["tn"]
		if is_instance_valid(dn["root"]):
			_pose_tentacle(dn, dd["axis"], -0.15 + sin(_time * 1.3 + i) * 0.12, -0.35 + sin(_time * 2.1 + i) * 0.2, 0.35, _time)
	for c: Dictionary in kraken_coils:
		_pose_coil(c, _time)
	if kraken_root:
		kraken_root.basis = Basis(Vector3.UP, sin(_time * 0.2) * 0.05) * Basis(Vector3.RIGHT, KRAKEN_TILT + sin(_time * 0.31) * 0.03).scaled(Vector3.ONE * KRAKEN_SCALE)
	for k in kraken_arms.size():
		var arm: Node3D = kraken_arms[k][0]
		arm.rotation.z = sin(_time * 0.7 + k * 1.3) * 0.12
	for g in _glows:
		(g[0] as StandardMaterial3D).emission_energy_multiplier = float(g[1]) * (0.75 + 0.25 * sin(_time * 1.7 + float(g[2])))
	for j in _jellies:
		var jn: Node3D = j["node"]
		var ph: float = j["phase"]
		var pulse := 0.5 + 0.5 * sin(_time * 1.6 + ph)
		jn.position = (j["base"] as Vector3) + Vector3(sin(_time * 0.2 + ph) * 0.8, sin(_time * 0.8 + ph) * 0.6, cos(_time * 0.17 + ph) * 0.8)
		jn.scale = Vector3(1.0 + pulse * 0.12, 1.0 - pulse * 0.1, 1.0 + pulse * 0.12)
	for c in _critters:
		var cn: Node3D = c["node"]
		var ang: float = float(c["phase"]) + _time * float(c["speed"])
		var cen: Vector3 = c["center"]
		var rad: Vector2 = c["radius"]
		var pos := cen + Vector3(cos(ang) * rad.x, sin(_time * 0.3 + float(c["phase"])) * 0.8, sin(ang) * rad.y)
		var nxt := cen + Vector3(cos(ang + 0.05 * signf(float(c["speed"]))) * rad.x, 0, sin(ang + 0.05 * signf(float(c["speed"]))) * rad.y)
		cn.position = pos
		var fwd := Vector3(nxt.x - pos.x, 0, nxt.z - pos.z)
		if fwd.length() > 0.0001:
			cn.rotation.y = atan2(fwd.x, fwd.z)
		var flap := sin(_time * float(c["flap"]) + float(c["phase"]))
		for w in c["wings"]:
			var wn: Node3D = w[0]
			wn.rotation.z = float(w[1]) * (0.25 + flap * float(w[2]))
	for f in _portal_fx:
		var k := 0.5 + 0.5 * sin(_time * 3.0 + float(f["phase"]))
		(f["mat"] as StandardMaterial3D).emission_energy_multiplier = 1.6 + k * 1.6
		(f["light"] as OmniLight3D).light_energy = 1.2 + k * 0.9


# ── 판 바깥 바다 밑 (판이 허공에 떠 있지 않고 바다 속 세상 한가운데에 놓이게) ──
func _outer_seabed() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.035
	var ext := 75.0
	var st2 := 2.5
	var inner_w := half_w + 1.4
	var inner_d := half_d + 1.4
	var nx := int((half_w + ext) * 2.0 / st2)
	var nz := int((half_d + ext) * 2.0 / st2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hf := func(x: float, z: float) -> float:
		var out := maxf(absf(x) - inner_w, absf(z) - inner_d)
		var k := clampf(out / ext, 0.0, 1.0)
		return -0.4 - pow(k, 1.1) * 16.0 + noise.get_noise_2d(x, z) * (0.2 + k * 7.0)
	for j in nz:
		for i in nx:
			var x0 := -half_w - ext + i * st2
			var z0 := -half_d - ext + j * st2
			if x0 > -inner_w - st2 and x0 < inner_w and z0 > -inner_d - st2 and z0 < inner_d:
				continue
			var q := [Vector3(x0, 0, z0), Vector3(x0 + st2, 0, z0), Vector3(x0 + st2, 0, z0 + st2), Vector3(x0, 0, z0 + st2)]
			for v in q.size():
				var vv: Vector3 = q[v]
				vv.y = hf.call(vv.x, vv.z)
				q[v] = vv
			var n1 := ((q[2] as Vector3) - (q[0] as Vector3)).cross((q[1] as Vector3) - (q[0] as Vector3)).normalized()
			for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
				st.set_normal(n1)
				st.set_uv(Vector2((v as Vector3).x, (v as Vector3).z) * 0.25)
				st.add_vertex(v)
	var m := ShaderMaterial.new()
	m.shader = FloorShader
	m.set_shader_parameter("board_rect", Vector4(-half_w, -half_d, half_w * 2.0, half_d * 2.0))
	var blank := Image.create(1, 1, false, Image.FORMAT_RG8)
	blank.fill(Color(0, 0, 0))
	m.set_shader_parameter("path_mask", ImageTexture.create_from_image(blank))
	_set_sand(m)
	_mi(st.commit(), m, Vector3.ZERO)
	# 멀리 보이는 큰 바위 언덕 · 다시마 숲 실루엣
	for k in 46:
		var a := _rng.randf() * TAU
		var dist := _rng.randf_range(8.0, 50.0)
		var x := cos(a) * (half_w + dist)
		var z := sin(a) * (half_d + dist)
		if absf(x) < inner_w + 2.0 and absf(z) < inner_d + 2.0:
			continue
		var y: float = hf.call(x, z)
		var r := _rng.randf_range(2.5, 6.5) * (1.0 + dist / 50.0)
		_rock(Vector3(x, y - r * 0.35, z), r)
		if _rng.randf() < 0.6:
			for q in _rng.randi_range(3, 7):
				var kx := x + _rng.randf_range(-r, r) * 1.3
				var kz := z + _rng.randf_range(-r, r) * 1.3
				_kelp(Vector3(kx, hf.call(kx, kz), kz), _rng.randf_range(6.0, 12.0))
		elif _rng.randf() < 0.5:
			_coral(Vector3(x, y + r * 0.45, z), [Color(1.0, 0.45, 0.4), Color(0.8, 0.45, 1.0), Color(1.0, 0.75, 0.35)][_rng.randi() % 3], _rng.randf_range(1.2, 2.0))


# ── 바다 생물: 바다거북 · 쥐가오리 (판 위를 크게 돌며 헤엄) ─────
func _sea_life() -> void:
	var span := Vector2(half_w, half_d)
	_turtle(Vector3(0, 13.0, 0), span * 0.7, 0.07, 0.0)
	if half_w > 30.0:
		_turtle(Vector3(-10, 16.0, 6), span * 0.45, -0.09, 2.0)
		_manta(Vector3(6, 19.0, -4), span * 0.85, 0.05, 4.0)
	else:
		_manta(Vector3(0, 15.0, 0), span * 0.9, -0.08, 1.0)


func _turtle(center: Vector3, radius: Vector2, speed: float, phase: float) -> void:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()
	body.scale = Vector3.ONE * 1.5
	root.add_child(body)
	var shell := SphereMesh.new()
	shell.radius = 0.9
	shell.height = 0.8
	var shell_m := _mat(Color(0.36, 0.42, 0.22), 0.55)
	var sm := _mi(shell, shell_m, Vector3(0, 0.1, 0), Basis(), body)
	sm.scale = Vector3(1.0, 0.75, 1.25)
	# 등껍질 무늬 (육각 판)
	var plate_m := _mat(Color(0.52, 0.5, 0.26), 0.5)
	for k in 7:
		var a := TAU * k / 6.0
		var pp := Vector3(0, 0.38, 0) if k == 6 else Vector3(sin(a) * 0.48, 0.26, cos(a) * 0.6)
		var pl := _mi(_cyl(0.24, 0.26, 0.06, 6), plate_m, pp, Basis(), body)
		pl.rotation = Vector3(-pp.z * 0.5, 0, pp.x * 0.5)
	var skin := _mat(Color(0.55, 0.62, 0.42), 0.7)
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.5
	var hm := _mi(head, skin, Vector3(0, 0.08, 1.25), Basis(), body)
	hm.scale = Vector3(1.0, 0.85, 1.25)
	for sd: float in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.05
		eye.height = 0.1
		_mi(eye, _mat(Color(0.05, 0.05, 0.05), 0.2), Vector3(sd * 0.16, 0.16, 1.42), Basis(), body)
	var wings := []
	for fz: float in [0.45, -0.6]:
		for sd: float in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = Vector3(sd * 0.75, 0.05, fz)
			body.add_child(hinge)
			var fl := _mi(_rbox(Vector3(0.9 if fz > 0 else 0.5, 0.08, 0.38 if fz > 0 else 0.28), 0.04), skin, Vector3(sd * (0.45 if fz > 0 else 0.25), 0, 0), Basis(Vector3.UP, sd * (0.5 if fz > 0 else -0.4)), hinge)
			wings.append([hinge, sd, 0.6 if fz > 0 else 0.3])
	_critters.append({"node": root, "center": center, "radius": radius, "speed": speed, "phase": phase, "flap": 1.6, "wings": wings})


func _manta(center: Vector3, radius: Vector2, speed: float, phase: float) -> void:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()
	body.scale = Vector3.ONE * 1.6
	root.add_child(body)
	var top := _mat(Color(0.12, 0.16, 0.2), 0.5)
	var belly := _mat(Color(0.85, 0.88, 0.86), 0.6)
	var core := SphereMesh.new()
	core.radius = 0.6
	core.height = 0.4
	var cm := _mi(core, top, Vector3.ZERO, Basis(), body)
	cm.scale = Vector3(1.0, 1.0, 1.6)
	var wings := []
	for sd: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sd * 0.45, 0, 0)
		body.add_child(hinge)
		# 삼각형 날개 (위 · 아래 색이 다름)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := [Vector3(0, 0, 0.8), Vector3(sd * 2.6, 0, -0.2), Vector3(0, 0, -0.7)]
		for v in pts:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		var wm := top.duplicate() as StandardMaterial3D
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mi(st.commit(), wm, Vector3.ZERO, Basis(), hinge)
		_mi(st.commit(), belly, Vector3(0, -0.02, 0), Basis(), hinge)
		wings.append([hinge, sd, 0.45])
	# 꼬리 · 머리 지느러미
	_mi(_cyl(0.02, 0.06, 2.2, 6), top, Vector3(0, 0, -1.8), Basis(Vector3(1, 0, 0), PI / 2), body)
	for sd: float in [-1.0, 1.0]:
		_mi(_rbox(Vector3(0.12, 0.08, 0.5), 0.03), top, Vector3(sd * 0.3, 0, 1.0), Basis(Vector3.UP, sd * 0.3), body)
	_critters.append({"node": root, "center": center, "radius": radius, "speed": speed, "phase": phase, "flap": 1.1, "wings": wings})


# ── 다른 스크립트가 쓰는 것들 ─────────────────────────────────
## 트로피 칸이 될 수 있는 평범한 칸들 (갈림길·START·포탈·상점 제외)
func regular_tiles() -> Array:
	var out := []
	for i in spaces.size():
		if String(spaces[i]["kind"]) in ["plain", "minigame", "chance"]:
			out.append(i)
	return out


## 칸 모양 바꾸기 (찬스 카드로 생기는 +5 / -5 동전 칸)
func set_tile_look(i: int, kind: String) -> void:
	var sp: Dictionary = spaces[i]
	if not sp.has("top_mi"):
		return
	(sp["top_mi"] as MeshInstance3D).material_override = _tile_top_mat(kind)
	(sp["body_mi"] as MeshInstance3D).material_override = _mat((TILE_COLORS[kind] as Color).darkened(0.2), 0.25)
	var body := sp["body_mi"] as Node3D
	var top := sp["top_mi"] as Node3D
	for n in [body, top]:
		var t := create_tween()
		t.tween_property(n, "scale", Vector3(1.15, 1.6, 1.15), 0.12)
		t.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	bubbles_at(sp["pos"], 14, 0.6, true)


## 트로피를 칸 위에 띄우기 (금빛 기둥이 멀리서도 보임)
func show_trophy(i: int) -> void:
	hide_trophy(false)
	trophy_tile = i
	var top: Vector3 = spaces[i]["pos"]
	var root := Node3D.new()
	root.position = top
	add_child(root)
	var cup := Node3D.new()
	cup.position.y = 2.6
	root.add_child(cup)
	var gold := _mat(Color(1.0, 0.78, 0.25), 0.18, 0.95)
	# 컵 (돌림판 모양)
	var prof := [Vector2(0.0, -0.55), Vector2(0.3, -0.55), Vector2(0.3, -0.45), Vector2(0.08, -0.38), Vector2(0.07, -0.12),
		Vector2(0.18, -0.02), Vector2(0.36, 0.1), Vector2(0.44, 0.35), Vector2(0.46, 0.55), Vector2(0.4, 0.56), Vector2(0.0, 0.5)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for k in prof.size() - 1:
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		for j in n:
			var t0 := TAU * j / n
			var t1 := TAU * (j + 1) / n
			var v := [Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x), Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x),
				Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x), Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)]
			var out := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = v[tri[0]]
				var B: Vector3 = v[tri[1]]
				var C: Vector3 = v[tri[2]]
				if (B - A).cross(C - A).dot(out) > 0.0:
					var tmp := B
					B = C
					C = tmp
				st.add_vertex(A)
				st.add_vertex(B)
				st.add_vertex(C)
	st.index()
	st.generate_normals()
	_mi(st.commit(), gold, Vector3.ZERO, Basis(), cup)
	for sx in [-1.0, 1.0]:
		var h := TorusMesh.new()
		h.inner_radius = 0.1
		h.outer_radius = 0.17
		_mi(h, gold, Vector3(sx * 0.46, 0.28, 0), Basis(Vector3(1, 0, 0), PI / 2), cup)
	# 금빛 기둥 + 불빛 + 반짝이
	var beam_m := StandardMaterial3D.new()
	beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_m.albedo_color = Color(1.0, 0.8, 0.35, 0.16)
	var beam := _mi(_cyl(0.9, 1.1, 16.0, 24), beam_m, Vector3(0, 8.0, 0), Basis(), root)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 2.0
	l.omni_range = 5.0
	l.position = Vector3(0, 2.4, 0)
	root.add_child(l)
	_trophy_node = root
	root.scale = Vector3.ONE * 0.01
	var t := create_tween()
	t.tween_property(root, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	portal_burst(top)


func hide_trophy(burst: bool = true) -> void:
	if _trophy_node:
		if burst:
			portal_burst(_trophy_node.position)
		_trophy_node.queue_free()
		_trophy_node = null
	trophy_tile = -1

func spaces_of_kind(kind: String) -> Array:
	var out := []
	for i in spaces.size():
		if spaces[i]["kind"] == kind:
			out.append(i)
	return out


## 포탈 칸이면 짝 포탈 번호, 아니면 -1
func portal_partner(i: int) -> int:
	return int(spaces[i].get("partner", -1))


## p 에서 가장 가까운 그 종류 칸 번호
func nearest_of_kind(kind: String, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in spaces_of_kind(kind):
		var d := (spaces[i]["pos"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## 포탈 이동할 때 반짝 터지는 효과
func portal_burst(p: Vector3) -> void:
	var c := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _unshaded(Color(0.9, 0.75, 1.0), 3.0)
	c.mesh = sm
	c.amount = 60
	c.lifetime = 1.2
	c.one_shot = true
	c.explosiveness = 0.95
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	c.emission_sphere_radius = 0.6
	c.direction = Vector3.UP
	c.spread = 70.0
	c.gravity = Vector3(0, -1.0, 0)
	c.initial_velocity_min = 2.0
	c.initial_velocity_max = 4.5
	c.scale_amount_min = 0.6
	c.scale_amount_max = 1.6
	c.position = p + Vector3(0, 1.0, 0)
	add_child(c)
	c.emitting = true
	get_tree().create_timer(2.0).timeout.connect(c.queue_free)


## START 광장 위 말 세울 자리
func start_spots(n: int) -> Array:
	var top: Vector3 = spaces[start_index]["pos"]
	var offs := [Vector3(-1.1, 0, -0.9), Vector3(1.1, 0, -0.9), Vector3(-1.1, 0, 1.1), Vector3(1.1, 0, 1.1)]
	if n == 1:
		return [top]
	var out := []
	for i in n:
		out.append(top + offs[i % 4])
	return out
