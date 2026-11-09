extends Node
## 게임 설정 저장/불러오기/적용 (user://settings.cfg 에 저장).
## 프로젝트 설정 > 자동 로드에 "Settings" 이름으로 등록되어 있어요.

const SAVE_PATH := "user://settings.cfg"

## 창 모드: 0 창 / 1 전체 화면(독점) / 2 테두리 없는 창(화면을 꽉 채운 창)
const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless"]
const RESOLUTIONS := [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
]
## 0 = 제한 없음
const FPS_LIMITS := [30, 60, 120, 144, 165, 240, 0]
## [로케일 코드, 그 언어로 쓴 이름]
const LANGUAGES := [["en", "English"], ["ko", "한국어"]]

# ---- 기본값
const DEFAULTS := {
	"master_volume": 0.8, "music_volume": 0.7, "sfx_volume": 0.8,
	"window_mode": 0, "resolution": Vector2i(1920, 1080), "max_fps": 0, "vsync": true,
}

var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.8
var window_mode := 0
var resolution := Vector2i(1920, 1080)
var max_fps := 0
var vsync := true
var language := "en"


func _ready() -> void:
	_ensure_audio_buses()
	language = _system_language()
	load_settings()
	apply_all()


# ---------------------------------------------------------------- 저장 / 불러오기

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	window_mode = clampi(cfg.get_value("video", "window_mode", window_mode), 0, WINDOW_MODES.size() - 1)
	resolution = cfg.get_value("video", "resolution", resolution)
	max_fps = cfg.get_value("video", "max_fps", max_fps)
	vsync = cfg.get_value("video", "vsync", vsync)
	language = cfg.get_value("general", "language", language)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("general", "language", language)
	cfg.save(SAVE_PATH)


func reset_defaults() -> void:
	master_volume = DEFAULTS["master_volume"]
	music_volume = DEFAULTS["music_volume"]
	sfx_volume = DEFAULTS["sfx_volume"]
	window_mode = DEFAULTS["window_mode"]
	resolution = DEFAULTS["resolution"]
	max_fps = DEFAULTS["max_fps"]
	vsync = DEFAULTS["vsync"]
	apply_all()
	save_settings()


# ---------------------------------------------------------------- 적용

func apply_all() -> void:
	apply_audio()
	apply_video()
	apply_language()


func apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


func apply_video() -> void:
	match window_mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var screen := DisplayServer.window_get_current_screen()
			var screen_size := DisplayServer.screen_get_size(screen)
			var win := Vector2i(mini(resolution.x, screen_size.x), mini(resolution.y, screen_size.y))
			DisplayServer.window_set_size(win)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + (screen_size - win) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


func apply_language() -> void:
	TranslationServer.set_locale(language)


# ---------------------------------------------------------------- 도우미

## 모니터보다 큰 해상도는 빼고 보여줘요
func available_resolutions() -> Array[Vector2i]:
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out: Array[Vector2i] = []
	for r in RESOLUTIONS:
		var rv: Vector2i = r
		if rv.x <= screen_size.x and rv.y <= screen_size.y:
			out.append(rv)
	if out.is_empty():
		out.append(Vector2i(1280, 720))
	if not out.has(resolution):
		out.append(resolution)
	return out


func _set_bus(bus_name: String, volume: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)


## 음악/효과음 버스가 없으면 만들어요 (음악 재생 노드는 bus = "Music", 효과음은 bus = "SFX" 로 설정하세요)
func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


## 처음 실행할 때는 컴퓨터 언어를 따라가요 (지원하지 않으면 영어)
func _system_language() -> String:
	var sys := OS.get_locale_language()
	for l in LANGUAGES:
		if l[0] == sys:
			return sys
	return "en"
