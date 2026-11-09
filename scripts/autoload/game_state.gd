extends Node
## 게임 전체에서 공유하는 상태 (선택한 모드, 참가 인원 등).
## 프로젝트 설정 > 자동 로드에 "GameState" 이름으로 등록되어 있어요.

enum Mode { FREE_FOR_ALL, TEAM_2V2, COOP }

const MAX_PLAYERS := 4

## 말 색 팔레트 (CUSTOMIZE 화면에서 고름). 바다 화면에 어울리게 채도를 살짝 낮춘 색들이에요.
## 같은 방에서 여러 명이 같은 색을 골라도 돼요. (CPU는 처음 들어올 때 안 겹치는 색을 받아요)
const PALETTE := [
	Color("ff7a6b"), Color("ffad7a"), Color("f0d49a"), Color("d6a560"), Color("b5e48c"), Color("4fe0c8"),
	Color("6cb8ff"), Color("3d7bd9"), Color("b49cff"), Color("e88aa8"), Color("eafffa"), Color("8a9bb0"),
]
const PALETTE_NAMES := ["Coral", "Peach", "Sand", "Amber", "Lime", "Mint", "Sky", "Ocean", "Lavender", "Rose", "Pearl", "Slate"]
## 자리별 기본 색 순서 (산호, 모래, 민트, 라벤더 ...)
const DEFAULT_COLOR_ORDER := [0, 2, 5, 8, 6, 9, 4, 1, 3, 7, 10, 11]

## 꾸미기 아이템. 종류마다 하나씩만 낄 수 있어요 (모자 하나 + 무늬 하나 + 장식품 하나 + 옷 하나).
const COSMETIC_CATEGORIES := ["hat", "pattern", "accessory", "outfit"]
const COSMETICS := {
	"hat": ["party_hat", "top_hat", "crown", "beanie"],
	"pattern": ["stripes", "diamond"],
	"accessory": ["scarf", "sunglasses", "pearl_necklace"],
	"outfit": ["red_cape", "swim_ring", "coat"],
}
const COSMETIC_NAMES := {
	"party_hat": "Birthday Hat", "top_hat": "Top Hat", "crown": "Crown", "beanie": "Beanie",
	"stripes": "Stripes", "diamond": "Diamond",
	"scarf": "Scarf", "sunglasses": "Sunglasses", "pearl_necklace": "Pearl Necklace",
	"red_cape": "Red Cape", "swim_ring": "Swim Ring", "coat": "Coat",
}
## true 로 바꾸면 종류와 상관없이 전체에서 아이템 하나만 낄 수 있어요
const ONE_ITEM_TOTAL := false

const MODE_NAMES := {
	Mode.FREE_FOR_ALL: "FREE-FOR-ALL",
	Mode.TEAM_2V2: "2 VS 2",
	Mode.COOP: "CO-OP",
}

## 메인화면에서 고른 모드 (Mode 값)
var selected_mode: int = Mode.FREE_FOR_ALL

## 로비 자리 4개. 빈자리는 {} (빈 딕셔너리)
##   {"kind": "host", "color": 0~11, "hat": "crown", ...}   방장(나), color = PALETTE 번호, 꾸미기는 종류별 아이템 id
##   {"kind": "cpu", "level": 0~2, "color": 0~11}   CPU (0 쉬움, 1 보통, 2 어려움)
##   {"kind": "friend", "name": "..."}  스팀 친구 (스팀 연동 후)
var players: Array[Dictionary] = [{}, {}, {}, {}]


func reset_lobby() -> void:
	# 내 색과 꾸미기는 방을 새로 만들어도 그대로
	var me := {"kind": "host", "color": 0}
	if not players[0].is_empty():
		me = players[0].duplicate()
		me["kind"] = "host"
	players = [me, {}, {}, {}]


func equip(slot: int, category: String, item_id: String) -> void:
	if ONE_ITEM_TOTAL:
		for c in COSMETIC_CATEGORIES:
			players[slot].erase(c)
	players[slot][category] = item_id


func unequip(slot: int, category: String) -> void:
	players[slot].erase(category)


func equipped(slot: int, category: String) -> String:
	return str(players[slot].get(category, ""))


## 말 그림에 넘길 꾸미기 정보 {"hat": "crown", ...}
func look(slot: int) -> Dictionary:
	var out := {}
	for c in COSMETIC_CATEGORIES:
		var v := equipped(slot, c)
		if v != "":
			out[c] = v
	return out


## 아직 아무도 안 쓰는 색 중 첫 번째 (기본 순서대로)
func first_free_color() -> int:
	for c in DEFAULT_COLOR_ORDER:
		if color_owner(c) == -1:
			return c
	return 0


## 그 색을 쓰는 자리 번호 (없으면 -1)
func color_owner(color_idx: int) -> int:
	for i in players.size():
		if not players[i].is_empty() and int(players[i].get("color", -1)) == color_idx:
			return i
	return -1


func filled_count() -> int:
	var n := 0
	for p in players:
		if not p.is_empty():
			n += 1
	return n


## 시작할 수 있는지: 개인전·협동은 2명 이상, 2:2 팀전은 4명 모두
func can_start() -> bool:
	if selected_mode == Mode.TEAM_2V2:
		return filled_count() == MAX_PLAYERS
	return filled_count() >= 2


func set_mode(mode: int) -> void:
	selected_mode = mode


func get_mode_name(mode: int = -1) -> String:
	if mode < 0:
		mode = selected_mode
	return MODE_NAMES.get(mode, "?")


func player_color(slot: int) -> Color:
	var p: Dictionary = players[slot]
	if p.is_empty():
		return PALETTE[DEFAULT_COLOR_ORDER[slot]]
	return PALETTE[int(p.get("color", 0)) % PALETTE.size()]
