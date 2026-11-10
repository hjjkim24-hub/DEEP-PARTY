extends RefCounted
## 보드 맵 정의. board_world.gd 가 이걸 읽어서 세상을 만들어요.
##   routes:   길 (지나가는 점들 x,높이,z). tiles = 칸 종류 (없으면 fill 패턴), bridge/spacing/deck 옵션
##   specials: 그 좌표에서 가장 가까운 칸을 이 종류로 (포탈은 pair 번호끼리 짝)
##   plateaus / chasms / volcanoes / arches: 지형
##   landmarks: 맵마다 특별한 볼거리 (신전, 난파선, 고래 뼈, 거대 조개 …)
##   나머지: 꾸미기 · 물고기 · 해파리 · 카메라

const TUT_S := Vector3(0, 0, 0)
const TUT_N := Vector3(0, 0, -11)
const TUT_W := Vector3(-15, 0, 0)
const TUT_E := Vector3(15, 0, 0)
const TUT_SO := Vector3(0, 0, 12)


static func get_map(id: String) -> Dictionary:
	if id == "sunken_island":
		return _sunken_island()
	return _tutorial()


# ── 튜토리얼 보드 (작음) ─────────────────────────────────────
static func _tutorial() -> Dictionary:
	var S := TUT_S
	var N := TUT_N
	var W := TUT_W
	var E := TUT_E
	var SO := TUT_SO
	return {
		"half": Vector2(28, 24),
		"spacing": 3.4,
		"start": S,
		"routes": [
			{"pts": [S, N], "tiles": ["minigame"]},
			{"pts": [S, W], "tiles": ["minigame", "chance"]},
			{"pts": [S, E], "tiles": ["minigame", "plain"]},
			{"pts": [N, Vector3(-4, 0, -14), Vector3(-8, 2.0, -16.5), Vector3(-12.5, 4.0, -16), Vector3(-16.5, 4.0, -12),
					Vector3(-18, 4.0, -7.5), Vector3(-17.5, 2.0, -3.5), W],
				"tiles": ["plain", "minigame", "chance", "minigame", "shop", "minigame", "plain", "chance", "minigame"]},
			{"pts": [W, Vector3(-16.5, 0, 5), Vector3(-12.5, 0, 9.5), Vector3(-6.5, 0, 12.5), SO],
				"tiles": ["plain", "portal", "minigame", "chance", "minigame", "plain"], "end": "minigame"},
			{"pts": [SO, Vector3(5, 0, 13.5), Vector3(8.8, 1.3, 11.2), Vector3(12, 1.3, 8.2), Vector3(15, 0, 5), E], "bridge": true,
				"tiles": ["plain", "shop", "minigame", "chance", "minigame", "plain"]},
			{"pts": [E, Vector3(16.5, 0, -4), Vector3(14.2, 0.9, -8), Vector3(10.2, 0.9, -11.2), Vector3(5, 0, -13.5), N], "spacing": 4.6,
				"tiles": ["minigame", "portal", "minigame", "chance", "minigame"]},
		],
		"fill": ["minigame", "plain", "minigame", "chance"],
		"specials": [],
		"plateaus": [{"c": Vector2(-15.5, -12.0), "r": Vector2(5.8, 6.2), "h": 4.0}],
		"chasms": [
			{"c": Vector2(12.2, -9.6), "r": Vector2(3.4, 3.9), "depth": 6.5},
			{"c": Vector2(10.4, 9.7), "r": Vector2(3.6, 3.2), "depth": 6.5},
		],
		"volcanoes": [{"at": Vector2(21.0, -16.0), "r": 7.5, "h": 5.0}],
		"arches": [{"at": Vector2(-12.5, 9.5), "dir": Vector2(10.0, 7.5).normalized()}],
		"landmarks": [],
		"decor_zones": [[Vector2(-15.5, -12.0), 6.0, 20], [Vector2(-22, -18), 4.0, 8], [Vector2(20, 17), 5.0, 10], [Vector2(-6, 18), 4.0, 7],
			[Vector2(22, 4), 3.0, 5], [Vector2(-4, -20), 4.0, 7], [Vector2(6, 4), 3.0, 4], [Vector2(-7, -5), 3.0, 4],
			[Vector2(8, -18), 3.5, 6], [Vector2(-24, 6), 3.0, 5], [Vector2(24, -10), 3.0, 5]],
		"kelp_forests": [[Vector2(-21, 15), Vector2(3.5, 4.0), 46]],
		"kelp_edge": 40,
		"seagrass": 22,
		"scatter": {"star": 34, "shell": 40, "pebble": 420},
		"rocks": 40,
		"fish": [
			[Vector3(-15.5, 7.5, -12.0), 6.5, 24, 0.22, 0.45, Color(1.0, 0.82, 0.25), Color(0.3, 0.62, 1.0)],
			[Vector3(19.0, 3.2, 13.0), 4.5, 16, -0.3, 0.42, Color(1.0, 0.55, 0.2), Color(0.98, 0.96, 0.92)],
			[Vector3(-20.0, 3.8, 14.0), 4.5, 18, 0.26, 0.4, Color(0.7, 0.85, 0.95), Color(0.35, 0.85, 0.78)],
			[Vector3(0.0, 9.0, 0.0), 19.0, 32, -0.07, 0.6, Color(0.98, 0.5, 0.7), Color(0.6, 0.5, 0.98)],
		],
		"jellies": [Vector3(-24, 6.5, -10), Vector3(24, 7.5, -4), Vector3(-10, 8.5, 21), Vector3(14, 6.0, 20), Vector3(4, 9.0, -21), Vector3(-25, 7.0, 20)],
		"treasures": [Vector2(22.0, 3.0)],
		"amphoras": [Vector2(-6.0, 5.5), Vector2(5.5, -5.5), Vector2(-21.0, -2.0)],
		"rays": 9,
		"zoom_max": 4.5,
		"overview": Vector3(0, 0, 1.5),
		"overview_zoom": 3.4,
		"fog": 0.012,
	}


# ── 가라앉은 섬 (튜토리얼의 4배) ──────────────────────────────
## 바깥 큰 순환로 + 섬 꼭대기 십자 길 + 안쪽 고리길이 거미줄처럼 얽혀 있어요.
## 갈림길이 많고, 길마다 성격이 달라요 (난파선 갑판, 고래 뼈 터널, 징검다리, 흔들다리, 지그재그 골목, 언덕길 …)
static func _sunken_island() -> Dictionary:
	var S := Vector3(0, 0, 34)          # 남쪽 해변 START
	var JS := Vector3(0, 0, 24)         # START 위 광장 갈림길
	var T := Vector3(0, 6, -3)          # 섬 꼭대기 신전 (네 갈래)
	var JN := Vector3(0, 0, -27)        # 북쪽 갈림길
	var N := Vector3(0, 0, -40)
	var SW := Vector3(-30, 0, 26)
	var SE := Vector3(30, 0, 26)
	var W := Vector3(-44, 0, 0)
	var E := Vector3(44, 0, 0)
	var NW := Vector3(-30, 0, -32)
	var NE := Vector3(30, 0, -32)
	var JW := Vector3(-28, 0, -1)       # 서쪽 둑길 갈림길
	var JE := Vector3(28, 0, -1)
	var IW := Vector3(-20, 0, 14)       # 안쪽 고리 (마을 어귀)
	var IE := Vector3(20, 0, 14)        # 안쪽 고리 (등대 어귀)
	var INW := Vector3(-18, 0, -22)     # 안쪽 고리 (석상 골짜기)
	var INE := Vector3(18, 3.5, -22)    # 안쪽 고리 (수정 언덕 꼭대기)
	return {
		"half": Vector2(56, 48),
		"spacing": 3.5,
		"start": S,
		"routes": [
			# ── 가운데 십자 ──
			{"pts": [S, JS]},
			{"pts": [JS, Vector3(0, 0, 18), Vector3(0, 3, 13.5), Vector3(0, 6, 8.5), T]},           # 큰 계단 (문 아래로)
			{"pts": [T, Vector3(0, 6, -10), Vector3(0, 3, -15), Vector3(0, 0, -20), JN]},
			{"pts": [JN, Vector3(0, 0, -33), N]},
			{"pts": [W, Vector3(-36, 0, -0.5), JW]},
			{"pts": [JW, Vector3(-22, 0, -1.5), Vector3(-18, 3, -2), Vector3(-13, 6, -3), T]},
			{"pts": [E, Vector3(36, 0, -0.5), JE]},
			{"pts": [JE, Vector3(22, 0, -1.5), Vector3(18, 3, -2), Vector3(13, 6, -3), T]},
			# ── 바깥 순환로 ──
			{"pts": [S, Vector3(-10, 0, 38.5), Vector3(-20, 0, 37.5), Vector3(-26, 0, 33), SW]},
			{"pts": [S, Vector3(10, 0, 38.5), Vector3(20, 0, 37.5), Vector3(26, 0, 33), SE]},
			{"pts": [SW, Vector3(-37, 0, 22), Vector3(-44, 2.6, 16), Vector3(-46, 2.6, 10), Vector3(-46, 2.6, 4.5), W], "deck": true},   # 난파선 갑판
			{"pts": [W, Vector3(-47, 0, -8), Vector3(-45, 0, -16), Vector3(-38, 0, -25), NW]},          # 고래 뼈 터널
			{"pts": [NW, Vector3(-22, 1.0, -37), Vector3(-14, 1.0, -41), Vector3(-6, 1.0, -41.5), N], "spacing": 4.6},   # 협곡 징검다리
			{"pts": [N, Vector3(7, 1.3, -42), Vector3(16, 1.3, -41.5), Vector3(23, 0, -37), NE], "bridge": true},       # 협곡 흔들다리
			{"pts": [NE, Vector3(38, 0, -27), Vector3(45, 0, -18), Vector3(47, 0, -9), E]},             # 화산 옆
			{"pts": [E, Vector3(47, 0, 9), Vector3(43, 0, 18), Vector3(36, 0, 24), SE]},                # 바위 아치
			# ── 안쪽 고리 (서쪽: 마을 · 석상) ──
			{"pts": [SW, Vector3(-27, 0, 20), IW]},
			{"pts": [IW, Vector3(-15, 0, 21), Vector3(-10, 0, 18.5), Vector3(-5, 0, 22.5), JS]},         # 구불구불 골목
			{"pts": [IW, Vector3(-24, 0, 8), Vector3(-27, 0, 3), JW]},
			{"pts": [NW, Vector3(-25, 0, -27), INW]},
			{"pts": [INW, Vector3(-12, 0, -25), Vector3(-6, 0, -27), JN]},
			{"pts": [INW, Vector3(-22, 0, -14), Vector3(-26, 0, -7), JW]},                               # 석상 문 아래
			# ── 안쪽 고리 (동쪽: 등대 · 수정 언덕) ──
			{"pts": [SE, Vector3(27, 0, 20), IE]},
			{"pts": [IE, Vector3(14, 0.8, 19), Vector3(7, 0.8, 22.5), JS], "bridge": true},            # 바닷속 골짜기 흔들다리
			{"pts": [IE, Vector3(25.5, 0, 11.5), Vector3(23, 0, 7), Vector3(28, 0, 3.5), JE]},          # 지그재그
			{"pts": [NE, Vector3(25, 1.5, -28), INE]},                                                   # 언덕 오르막
			{"pts": [INE, Vector3(12, 2, -25), Vector3(6, 0, -27), JN]},
			{"pts": [INE, Vector3(22, 2, -15), Vector3(26, 0, -8), JE]},
		],
		"fill": ["minigame", "plain", "minigame", "chance", "minigame", "plain", "chance", "minigame", "plain", "minigame"],
		"specials": [
			{"at": Vector2(-46, 8), "kind": "portal", "pair": 0},
			{"at": Vector2(46, -13), "kind": "portal", "pair": 0},
			{"at": Vector2(-16, 37.5), "kind": "portal", "pair": 1},
			{"at": Vector2(16, -41.5), "kind": "portal", "pair": 1},
			{"at": Vector2(-25, -27), "kind": "portal", "pair": 2},
			{"at": Vector2(23, 7), "kind": "portal", "pair": 2},
			{"at": Vector2(0, 3), "kind": "shop"},
			{"at": Vector2(-37, 22), "kind": "shop"},
			{"at": Vector2(38, -27), "kind": "shop"},
			{"at": Vector2(-12, 19.5), "kind": "shop"},
		],
		"plateaus": [{"c": Vector2(0, -3), "r": Vector2(17, 13), "h": 6.0}, {"c": Vector2(18, -22), "r": Vector2(6.5, 6.0), "h": 3.5}],
		"chasms": [
			{"c": Vector2(-14, -38.5), "r": Vector2(7.0, 4.6), "depth": 8.0},
			{"c": Vector2(12, -40.5), "r": Vector2(6.5, 4.2), "depth": 8.0},
			{"c": Vector2(10.5, 20.8), "r": Vector2(4.2, 3.2), "depth": 7.0},
		],
		"volcanoes": [{"at": Vector2(47, -38), "r": 10.0, "h": 8.0}],
		"arches": [
			{"at": Vector2(46, 12.5), "dir": Vector2(-0.35, 1.0).normalized()},
			{"at": Vector2(-24, -10.5), "dir": Vector2(0, 1)},
			{"at": Vector2(9, -26), "dir": Vector2(1, 0)},
		],
		"landmarks": [
			{"type": "temple", "at": Vector2(0, -3), "r": 8.5},
			{"type": "gate", "at": Vector2(0, 5.0)},
			{"type": "shipwreck", "at": Vector2(-46, 10), "len": 21.0, "deck": 2.6},
			{"type": "whale", "at": Vector2(-46, -12), "dir": Vector2(0.15, -1.0).normalized()},
			{"type": "village", "at": Vector2(-35, 10)},
			{"type": "lighthouse", "at": Vector2(35, 9)},
			{"type": "colossus", "at": Vector2(-33, -15)},
			{"type": "hand", "at": Vector2(-9, -18)},
			{"type": "crystals", "at": Vector2(34, -15)},
			{"type": "vents", "at": Vector2(8, -16)},
			{"type": "trident", "at": Vector2(-10, -32.5)},
			{"type": "anchor", "at": Vector2(-36, 42)},
			{"type": "cargo", "at": Vector2(40, 38)},
			{"type": "obelisk", "at": Vector2(-9, 12)},
			{"type": "obelisk", "at": Vector2(9, 11)},
			{"type": "clam", "at": Vector2(-11, 29)},
		],
		"decor_zones": [[Vector2(0, -3), 7.0, 22], [Vector2(-28, 10), 5.0, 8], [Vector2(28, 10), 5.0, 8],
			[Vector2(-24, -18), 5.0, 10], [Vector2(24, -18), 5.0, 10], [Vector2(-40, 40), 4.0, 10], [Vector2(40, 30), 4.0, 8],
			[Vector2(0, 45), 5.0, 10], [Vector2(-50, -40), 4.0, 8], [Vector2(52, 24), 4.0, 8], [Vector2(-14, 26), 4.0, 8],
			[Vector2(14, 28), 4.0, 8], [Vector2(0, -32), 4.0, 6], [Vector2(-38, -6), 4.0, 6], [Vector2(38, -8), 4.0, 6],
			[Vector2(-20, -30), 3.5, 6], [Vector2(22, -30), 3.5, 6], [Vector2(-8, 30), 3.0, 5], [Vector2(8, 32), 3.0, 5],
			[Vector2(-52, -26), 3.0, 5], [Vector2(52, -28), 3.0, 4], [Vector2(-12, 6), 3.0, 5], [Vector2(12, 6), 3.0, 5]],
		"kelp_forests": [[Vector2(-48, 36), Vector2(5, 5), 60], [Vector2(-50, -40), Vector2(4, 4), 36], [Vector2(50, 40), Vector2(4, 4), 36],
			[Vector2(-30, -20), Vector2(3, 3), 18]],
		"kelp_edge": 80,
		"seagrass": 80,
		"scatter": {"star": 120, "shell": 140, "pebble": 1400},
		"rocks": 90,
		"fish": [
			[Vector3(0, 13.0, -3), 15.0, 40, 0.12, 0.5, Color(1.0, 0.82, 0.25), Color(0.3, 0.62, 1.0)],
			[Vector3(-40, 5.0, 26), 8.0, 24, -0.22, 0.42, Color(1.0, 0.55, 0.2), Color(0.98, 0.96, 0.92)],
			[Vector3(40, 5.0, -20), 8.0, 24, 0.2, 0.42, Color(0.7, 0.85, 0.95), Color(0.35, 0.85, 0.78)],
			[Vector3(-30, 4.5, -30), 7.0, 20, 0.24, 0.4, Color(0.95, 0.4, 0.5), Color(1.0, 0.9, 0.4)],
			[Vector3(30, 4.0, 32), 6.0, 18, -0.26, 0.4, Color(0.6, 0.9, 0.5), Color(0.98, 0.98, 0.9)],
			[Vector3(35, 14.0, 9), 5.0, 18, 0.3, 0.38, Color(1.0, 0.95, 0.6), Color(0.4, 0.8, 1.0)],
			[Vector3(0, 16.0, 0), 40.0, 56, -0.04, 0.65, Color(0.98, 0.5, 0.7), Color(0.6, 0.5, 0.98)],
		],
		"jellies": [Vector3(-50, 7, -20), Vector3(50, 8, 4), Vector3(-20, 9, 44), Vector3(28, 7, 44), Vector3(8, 10, -46), Vector3(-52, 8, 24),
			Vector3(-28, 11, -10), Vector3(28, 11, 8), Vector3(-6, 12, 22), Vector3(52, 9, -24), Vector3(-40, 9, -44), Vector3(14, 10, -20),
			Vector3(34, 10, -15), Vector3(-35, 9, 10)],
		"treasures": [Vector2(-40, 32), Vector2(52, -2), Vector2(-4, 46), Vector2(11, 30)],
		"amphoras": [Vector2(-9, -12), Vector2(9, -12), Vector2(-40, 14), Vector2(-50, 2), Vector2(-6, 42), Vector2(24, 34), Vector2(-30, 6), Vector2(30, -18)],
		"rays": 26,
		"zoom_max": 9.0,
		"overview": Vector3(0, 0, 3),
		"overview_zoom": 7.2,
		"fog": 0.006,
	}
