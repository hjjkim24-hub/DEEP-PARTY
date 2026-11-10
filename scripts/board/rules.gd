extends RefCounted
## DEEP PARTY 보드 규칙 숫자 모음. 여기만 바꾸면 게임 전체에 적용돼요.
##
## 목표: 트로피를 TROPHIES_TO_WIN 개 먼저 모으면 바로 우승 (2대2는 팀원 둘 합계)
## 돈: 동전

const START_COINS := 10
const TROPHIES_TO_WIN := 5
const ROUND_LIMIT := 30            ## 이때까지 아무도 못 모으면 트로피 → 동전 순으로 우승

const START_BONUS := 3             ## START 광장을 지나가거나 멈추면

## 트로피 칸: TROPHY_FIRST_ROUND 라운드 시작 때 랜덤 칸에 처음 생김.
## 지나가기만 해도 살 수 있음 (멈춰서 물어본 뒤 남은 칸 이동). 누가 사면 TROPHY_RESPAWN_ROUNDS 라운드 뒤 다른 칸에 다시 생김.
const TROPHY_PRICE := 20
const TROPHY_FIRST_ROUND := 4      ## = 3라운드가 끝난 뒤
const TROPHY_RESPAWN_ROUNDS := 2

## 상점: 들를 때마다 이 확률로 트로피가 진열됨
const SHOP_TROPHY_CHANCE := 0.10
const SHOP_TROPHY_PRICE := 40

## 미니게임: 순위별 동전, 칸을 밟은 사람은 보너스
const MINIGAME_REWARDS := [10, 6, 3, 1]
const MINIGAME_LANDER_BONUS := 2

## 찬스 카드로 생기는 동전 칸
const COIN_SPACE_AMOUNT := 5
const COIN_SPACES_PER_CARD := 3
const STEAL_COINS := 5

## 찬스 카드 (weight 가 클수록 자주 나옴)
const CARDS := [
	{"id": "coins5", "weight": 22, "title": "+5 COINS", "text": "Get 5 coins."},
	{"id": "coins10", "weight": 12, "title": "+10 COINS", "text": "Get 10 coins."},
	{"id": "roll_again", "weight": 12, "title": "ROLL AGAIN", "text": "Roll the dice one more time, right now!"},
	{"id": "lucky_spaces", "weight": 10, "title": "LUCKY SPACES", "text": "Lucky spaces (+5 coins) pop up around the board!"},
	{"id": "trap_spaces", "weight": 10, "title": "COIN TRAPS", "text": "Trap spaces (-5 coins) pop up around the board!"},
	{"id": "pickpocket", "weight": 12, "title": "PICKPOCKET", "text": "Take 5 coins from a player of your choice."},
	{"id": "warp", "weight": 4, "title": "WARP", "text": "Warp to any space you like!"},
	{"id": "trophy_minigame", "weight": 4, "title": "TROPHY MINIGAME", "text": "Everyone plays a minigame. The winner gets a trophy!"},
	{"id": "trophy_thief", "weight": 3, "title": "TROPHY THIEF", "text": "Steal a trophy from a player of your choice!"},
]


static func card(id: String) -> Dictionary:
	for c in CARDS:
		if c["id"] == id:
			return c
	return CARDS[0]


static func random_card(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0
	for c in CARDS:
		total += int(c["weight"])
	var r := rng.randi_range(1, total)
	for c in CARDS:
		r -= int(c["weight"])
		if r <= 0:
			return c
	return CARDS[0]
