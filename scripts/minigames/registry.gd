extends RefCounted
## 미니게임 목록 (모두 3D · 크라켄과 바다가 무대). 새 미니게임을 만들면 여기에 한 줄 추가하면 보드에서 랜덤으로 나와요.

const LIST := {
	"tentacle_dodge": preload("res://scripts/minigames/tentacle_dodge.gd"),
	"cannon_volley": preload("res://scripts/minigames/cannon_volley.gd"),
	"treasure_dive": preload("res://scripts/minigames/treasure_dive.gd"),
	"chest_shuffle": preload("res://scripts/minigames/chest_shuffle.gd"),
}
const NAMES := {
	"tentacle_dodge": "TentacleDodge", "cannon_volley": "CannonVolley",
	"treasure_dive": "TreasureDive", "chest_shuffle": "ChestShuffle",
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
