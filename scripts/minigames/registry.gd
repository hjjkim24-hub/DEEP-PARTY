extends RefCounted
## 미니게임 목록 (모두 3D · 크라켄과 바다가 무대). 새 미니게임을 만들면 여기에 한 줄 추가하면 보드에서 랜덤으로 나와요.

const LIST := {
	"tentacle_dodge": preload("res://scripts/minigames/tentacle_dodge.gd"),
	"cannon_volley": preload("res://scripts/minigames/cannon_volley.gd"),
	"treasure_dive": preload("res://scripts/minigames/treasure_dive.gd"),
	"chest_shuffle": preload("res://scripts/minigames/chest_shuffle.gd"),
	"tentacle_tug": preload("res://scripts/minigames/tentacle_tug.gd"),
	"powder_keg": preload("res://scripts/minigames/powder_keg.gd"),
	"anchor_drop": preload("res://scripts/minigames/anchor_drop.gd"),
	"ink_paint": preload("res://scripts/minigames/ink_paint.gd"),
	"clam_snatch": preload("res://scripts/minigames/clam_snatch.gd"),
	"slippery_deck": preload("res://scripts/minigames/slippery_deck.gd"),
	"mast_climb": preload("res://scripts/minigames/mast_climb.gd"),
	"water_cannon": preload("res://scripts/minigames/water_cannon.gd"),
	"cave_run": preload("res://scripts/minigames/cave_run.gd"),
	"tilting_raft": preload("res://scripts/minigames/tilting_raft.gd"),
	"cargo_haul": preload("res://scripts/minigames/cargo_haul.gd"),
	"beach_dig": preload("res://scripts/minigames/beach_dig.gd"),
}
const NAMES := {
	"tentacle_dodge": "TentacleDodge", "cannon_volley": "CannonVolley",
	"treasure_dive": "TreasureDive", "chest_shuffle": "ChestShuffle",
	"tentacle_tug": "TentacleTug", "powder_keg": "PowderKeg", "anchor_drop": "AnchorDrop", "ink_paint": "InkPaint", "clam_snatch": "ClamSnatch",
	"slippery_deck": "SlipperyDeck", "mast_climb": "MastClimb", "water_cannon": "WaterCannon", "cave_run": "CaveRun", "tilting_raft": "TiltingRaft", "cargo_haul": "CargoHaul", "beach_dig": "BeachDig",
}


static func ids() -> Array:
	return LIST.keys()


## id 가 "" 이거나 없는 이름이면 랜덤으로 하나
static func pick(id: String, rng: RandomNumberGenerator) -> String:
	if id == "" or not LIST.has(id):
		var keys := LIST.keys()
		return keys[rng.randi() % keys.size()]
	return id


static func create(id: String, rng: RandomNumberGenerator) -> Control:
	id = pick(id, rng)
	var mg: Control = (LIST[id] as GDScript).new()
	mg.name = NAMES[id]
	return mg
