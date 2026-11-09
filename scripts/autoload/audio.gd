extends Node
## 배경음악 + 효과음.
##   Audio.play("click")      효과음 (audio/sfx/<이름>.wav)
##   Audio.play_music()        메뉴 음악 시작 (서서히 커짐, 끝없이 반복)
## 모든 버튼은 자동으로 마우스 올리면 "hover", 누르면 "click" 소리가 납니다.
## 버튼마다 누를 때 다른 소리를 내려면  button.set_meta("sfx", "back")  (누르는 소리 없음은 "")
## 음악은 "Music" 버스, 효과음은 "SFX" 버스 → 설정의 음량 슬라이더가 그대로 적용돼요.

const MUSIC_PATH := "res://audio/music/menu_theme.ogg"
const SFX_DIR := "res://audio/sfx/"
const SFX_NAMES := [
	"hover", "click", "back", "toggle_on", "toggle_off", "tick", "tab", "color",
	"equip", "unequip", "add", "remove", "start", "toast", "bubbles",
]
## 소리별 음량(dB). 자주 나는 소리는 작게.
const SFX_DB := {
	"hover": -14.0, "tick": -10.0, "click": -5.0, "back": -5.0, "tab": -6.0,
	"color": -5.0, "equip": -4.0, "unequip": -5.0, "add": -3.0, "remove": -4.0,
	"start": -2.0, "toast": -6.0, "toggle_on": -6.0, "toggle_off": -6.0, "bubbles": -16.0,
}
const PITCH_JITTER := {"hover": 0.08, "click": 0.05, "tick": 0.06, "bubbles": 0.15, "color": 0.03}
const MIN_INTERVAL_MS := 40
const VOICES := 10
const MUSIC_DB := -4.0

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _music: AudioStreamPlayer
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in SFX_NAMES:
		var path: String = SFX_DIR + n + ".wav"
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	get_tree().node_added.connect(_on_node_added)


func play(sfx_name: String, min_interval_ms: int = MIN_INTERVAL_MS) -> void:
	if not _streams.has(sfx_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(sfx_name, -100000)) < min_interval_ms:
		return
	_last[sfx_name] = now
	var p: AudioStreamPlayer = null
	for i in VOICES:   # 쉬고 있는 재생기 찾기, 없으면 가장 오래된 것
		var cand := _players[(_next + i) % VOICES]
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _players[_next]
	_next = (_players.find(p) + 1) % VOICES
	p.stream = _streams[sfx_name]
	p.volume_db = float(SFX_DB.get(sfx_name, -4.0))
	var j: float = PITCH_JITTER.get(sfx_name, 0.0)
	p.pitch_scale = 1.0 + randf_range(-j, j)
	p.play()


func play_music(fade_time: float = 2.0) -> void:
	if _music.playing:
		return
	var stream := load(MUSIC_PATH) as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = true
	_music.stream = stream
	_music.volume_db = -40.0
	_music.play()
	_fade_music(MUSIC_DB, fade_time)


func stop_music(fade_time: float = 0.6) -> void:
	if not _music.playing:
		return
	_fade_music(-40.0, fade_time)
	await _music_tween.finished
	_music.stop()


func _fade_music(target_db: float, time: float) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target_db, time).set_trans(Tween.TRANS_SINE)


# ── 모든 버튼에 자동으로 소리 달기 ────────────────────────────
func _on_node_added(node: Node) -> void:
	var b := node as BaseButton
	if b == null or b.has_meta("_sfx_hooked"):
		return
	b.set_meta("_sfx_hooked", true)
	b.mouse_entered.connect(_on_button_hover.bind(b))
	b.pressed.connect(_on_button_pressed.bind(b))


func _on_button_hover(b: BaseButton) -> void:
	if not b.disabled:
		play("hover")


func _on_button_pressed(b: BaseButton) -> void:
	var s := "click"
	if b.has_meta("sfx"):
		s = String(b.get_meta("sfx"))
	if s != "":
		play(s)
