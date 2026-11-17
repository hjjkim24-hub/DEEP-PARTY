extends Node
## 배경음악 + 효과음.
##   Audio.play("click")      효과음 (audio/sfx/<이름>.wav)
##   Audio.play_music()        메뉴 음악 시작 (서서히 커짐, 끝없이 반복)
## 모든 버튼은 자동으로 마우스 올리면 "hover", 누르면 "click" 소리가 납니다.
## 버튼마다 누를 때 다른 소리를 내려면  button.set_meta("sfx", "back")  (누르는 소리 없음은 "")
## 음악은 "Music" 버스, 효과음은 "SFX" 버스 → 설정의 음량 슬라이더가 그대로 적용돼요.

const MUSIC_PATH := "res://audio/music/menu_theme.ogg"
## 배경음악 목록 (tools/make_audio.py · tools/make_music.py 로 만듦)
const TRACKS := {
	"menu": "res://audio/music/menu_theme.ogg",
	"board": "res://audio/music/board_theme.ogg",
	"mg_intro": "res://audio/music/mg_intro.ogg",
	"pearl_pop": "res://audio/music/mg_pearl_pop.ogg",
	"timing_stop": "res://audio/music/mg_timing_stop.ogg",
	"shell_game": "res://audio/music/mg_shell_game.ogg",
	"jelly_dodge": "res://audio/music/mg_jelly_dodge.ogg",
}
const SFX_DIR := "res://audio/sfx/"
const SFX_NAMES := [
	"hover", "click", "back", "toggle_on", "toggle_off", "tick", "tab", "color",
	"equip", "unequip", "add", "remove", "start", "toast", "bubbles",
	"box_rumble", "box_burst", "box_whoosh",
	"cannon", "explode", "whoosh", "portal", "card_spin", "card_flip", "coins", "roar", "thud", "creak",
]
## 소리별 음량(dB). 자주 나는 소리는 작게.
const SFX_DB := {
	"hover": -14.0, "tick": -10.0, "click": -5.0, "back": -5.0, "tab": -6.0,
	"color": -5.0, "equip": -4.0, "unequip": -5.0, "add": -3.0, "remove": -4.0,
	"start": -2.0, "toast": -6.0, "toggle_on": -6.0, "toggle_off": -6.0, "bubbles": -16.0,
	"box_rumble": -4.0, "box_burst": -2.0, "box_whoosh": -3.0,
	"cannon": -1.0, "explode": -3.0, "whoosh": -6.0, "portal": -5.0, "card_spin": -7.0, "card_flip": -5.0,
	"coins": -5.0, "roar": -2.0, "thud": -6.0, "creak": -8.0,
}
## 반복되는 배경 소리 (크라켄의 배 위 바람 등)
const AMBIENCE := {"wind": "res://audio/sfx/wind.wav"}
const PITCH_JITTER := {"hover": 0.08, "click": 0.05, "tick": 0.06, "bubbles": 0.15, "color": 0.03, "thud": 0.1, "coins": 0.05,
	"cannon": 0.05, "explode": 0.06}
const MIN_INTERVAL_MS := 40
const VOICES := 10
const MUSIC_DB := -4.0
var _stopping := false
var _track := ""

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _music: AudioStreamPlayer
var _music_tween: Tween
var _amb: AudioStreamPlayer
var _amb_tween: Tween


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
	_amb = AudioStreamPlayer.new()
	_amb.bus = "SFX"
	add_child(_amb)
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


## 배경음악: 화면이 나타나는 순간 불러서 첫 박부터 들리게 (fade_time 0 = 바로 제 소리)
func play_music(fade_time: float = 0.0, track: String = "menu") -> void:
	if _music.playing and not _stopping and track == _track:
		return
	_stopping = false
	_track = track
	if _music_tween:
		_music_tween.kill()
	var stream := load(TRACKS.get(track, MUSIC_PATH)) as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = true
	_music.stop()
	_music.stream = stream
	if fade_time <= 0.05:
		_music.volume_db = MUSIC_DB
		_music.play()
	else:
		_music.volume_db = -40.0
		_music.play()
		_fade_music(MUSIC_DB, fade_time)


func stop_music(fade_time: float = 0.6) -> void:
	if not _music.playing:
		return
	_stopping = true
	_fade_music(-40.0, fade_time)
	var tw := _music_tween
	await tw.finished
	# 끄는 동안 다른 화면에서 다시 틀었으면 끄지 않음
	if _stopping and tw == _music_tween:
		_music.stop()
		_stopping = false


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


# 게임을 끌 때 재생 중인 소리를 정리 (종료 시 리소스 누수 경고 방지)
func _exit_tree() -> void:
	if _music_tween:
		_music_tween.kill()
	if _music:
		_music.stop()
		_music.stream = null
	for p in _players:
		p.stop()
		p.stream = null
	_streams.clear()



## 배경 소리 (끝없이 반복): name = "" 이면 서서히 끔
func play_ambience(amb_name: String, db: float = -10.0, fade_time: float = 1.5) -> void:
	if _amb_tween:
		_amb_tween.kill()
	_amb_tween = create_tween()
	if amb_name == "" or not AMBIENCE.has(amb_name):
		if _amb.playing:
			_amb_tween.tween_property(_amb, "volume_db", -60.0, fade_time)
			_amb_tween.tween_callback(_amb.stop)
		return
	var st := load(AMBIENCE[amb_name]) as AudioStreamWAV
	if st == null:
		return
	st = st.duplicate() as AudioStreamWAV
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)
	_amb.stream = st
	_amb.volume_db = -60.0
	_amb.play()
	_amb_tween.tween_property(_amb, "volume_db", db, fade_time)
