extends RefCounted
## 미니게임 목록. 새 미니게임을 만들면 여기에 한 줄 추가하면 보드에서 랜덤으로 나와요.

const LIST := {
	"pearl_pop": preload("res://scripts/minigames/pearl_pop.gd"),
	"timing_stop": preload("res://scripts/minigames/timing_stop.gd"),
	"shell_game": preload("res://scripts/minigames/shell_game.gd"),
	"jelly_dodge": preload("res://scripts/minigames/jelly_dodge.gd"),
}
const NAMES := {
	"pearl_pop": "PearlPop", "timing_stop": "TimingStop", "shell_game": "ShellGame", "jelly_dodge": "JellyDodge",
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
