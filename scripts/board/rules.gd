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
const MINIGAME_REWARDS := [7, 5, 3, 1]
const MINIGAME_LANDER_BONUS := 0     ## 모든 미니게임 보상 통일 (1~4등 7·5·3·1)

## 찬스 카드로 생기는 동전 칸
const COIN_SPACE_AMOUNT := 5
const COIN_SPACES_PER_CARD := 3
const STEAL_COINS := 5

## ── 크라켄 생존전 (개인전 · 2대2) ───────────────────────────
## 각자 하트 5개. 라운드가 끝날 때마다 크라켄이 움직여요:
##   1) 지난 라운드에 노려 둔 칸을 촉수로 내려침 → 그 칸에 서 있으면 하트 -1 (방패가 막아 줌)
##      내려친 칸은 성게 가시가 박힌 함정 칸이 됨 (멈추면 하트 -1)
##   2) 탈락한 사람(크라켄의 부하)이 노릴 칸을 하나씩 고름
##   3) 크라켄이 다음에 내려칠 칸을 새로 노림 (붉게 빛남 → 한 라운드 안에 피해야 함). 라운드가 갈수록 많아짐
## 마지막까지 살아남은 사람(팀)이 승리. ROUND_LIMIT 까지 가면 하트 → 동전 순.
const HEARTS_START := 5
const HEARTS_MAX := 5               ## 최대 체력은 5 로 고정 (물약으로도 5 를 넘지 않음)
## 크라켄 차례: KRAKEN_ATTACK_EVERY 라운드마다 라운드 끝에 아래 행동 중 하나를 무작위로
##   barrage: 많은 칸을 붉게 표시 → 다음 라운드 끝에 내려침
##   spines : 적은 칸을 2 라운드 동안 독가시 칸으로 (멈추면 하트 -1, 상점 · 포털 등도 바뀔 수 있음)
##   surge  : 2 라운드 동안 상점 가격 2 배
##   ship   : 모두의 발밑에 포탈이 열려 하늘을 나는 '크라켄의 배'로 2 라운드 (배에선 크라켄 공격 없음).
##            섬으로 돌아온 뒤부터 다음 크라켄 차례까지 다시 셈
const KRAKEN_ATTACK_EVERY := 2
## 처음 몇 라운드는 크라켄이 잠들어 있음: 모두 주사위를 이만큼 굴린 뒤(그 라운드 끝) 깨어나 바로 첫 차례
const KRAKEN_WAKE_ROUND := 2
const KRAKEN_ACTIONS := ["barrage", "spines", "surge", "ship"]
const SHIP_ROUNDS := 2              ## ship: 배 위에서 보내는 라운드 수
const KRAKEN_CHEST_WIN := 0.5       ## 크라켄의 보물상자 룰렛: 보물상자가 나올 확률
const CANNON_COINS := 5             ## 대포 칸: 맞은 상대가 잃는 동전
const KRAKEN_TARGETS_BASE := 40     ## barrage: 첫 공격에 노리는 칸 수 (판은 약 180칸)
const KRAKEN_TARGETS_GROW := 5.0    ## 크라켄 차례마다 늘어나는 수
const KRAKEN_TARGETS_MAX := 60
const KRAKEN_AIM_PER_PAWN := 2      ## barrage: 사람마다 앞 1~6 칸 안에서 반드시 노리는 칸 수
const KRAKEN_SPREAD_GAP := 5.0      ## barrage: 노린 칸끼리 최소 간격 (m, 칸 한 변 2.2 m · 칸 사이 약 3 m)
const KRAKEN_MASS_STRIKE := 5       ## 이보다 많이 내려칠 때는 한꺼번에 쾅 (하나씩 보여 주면 너무 길어서)
const KRAKEN_AIM_AT_PAWN := 0.6     ## 이 확률로 누군가 서 있는 칸 근처를 노림
const KRAKEN_SPINES_BASE := 3       ## spines: 독가시 칸 수
const KRAKEN_SPINES_MAX := 5
const KRAKEN_EFFECT_ROUNDS := 2     ## spines · surge 가 이어지는 라운드 수
const KRAKEN_SURGE_MULT := 2        ## surge: 상점 가격 배수
const POTION_PRICE := 12            ## 상점: 하트 +1
const SHIELD_PRICE := 8             ## 상점: 다음 피해 한 번 막기
const MINIGAME_WIN_HEAL := 1        ## 미니게임 1등은 하트 +1

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
	{"id": "heal", "weight": 8, "survival": true, "title": "SEA MEDIC", "text": "Get back 1 heart."},
	{"id": "shield", "weight": 8, "survival": true, "title": "BARNACLE SHIELD", "text": "Blocks the next hit you take."},
	{"id": "harpoon", "weight": 8, "survival": true, "title": "HARPOON", "text": "Throw a harpoon at a player of your choice. A hit costs them 1 heart."},
	{"id": "bait", "weight": 6, "survival": true, "title": "KRAKEN BAIT", "text": "The kraken will strike next to a player of your choice!"},
]
## 생존전에서 빠지는 카드 (트로피용)
const TROPHY_CARDS := ["trophy_minigame", "trophy_thief"]


static func card(id: String) -> Dictionary:
	for c in CARDS:
		if c["id"] == id:
			return c
	return CARDS[0]


static func random_card(rng: RandomNumberGenerator, survival: bool = false) -> Dictionary:
	var deck := []
	for c in CARDS:
		if survival and c["id"] in TROPHY_CARDS:
			continue
		if not survival and c.get("survival", false):
			continue
		deck.append(c)
	var total := 0
	for c in deck:
		total += int(c["weight"])
	var r := rng.randi_range(1, total)
	for c in deck:
		r -= int(c["weight"])
		if r <= 0:
			return c
	return deck[0]
