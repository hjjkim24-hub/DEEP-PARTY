extends Control
## 시작 로고 화면: Godot 로고 → MS 로고 → 메인화면.
##
## Godot 기본 부트 스플래시는 꺼 두고(project.godot), 엔진과 창이 다 뜬 뒤에
## 이 장면에서 로고를 보여 줍니다. 그래서 로딩 중에 휙 지나가서 못 보는 일이 없어요.
## 로고가 나오는 동안 메인화면은 뒤에서 미리 불러 둡니다.
## 화면을 클릭하면 지금 로고를 건너뜁니다.

const NEXT_SCENE := "res://scenes/main_menu.tscn"
const LOGOS := [
	preload("res://textures/splash/godot_logo.png"),
	preload("res://textures/splash/ms_logo.png"),
]
const LOGO_BOX := Vector2(900, 420)   # 1920x1080 기준 로고 최대 크기

const READY_FRAMES := 4      # 창이 실제로 그려지기 시작한 뒤 기다릴 프레임 수
const READY_DELAY := 0.4     # 그 뒤 검은 화면으로 잠깐 쉬는 시간
const FADE_IN := 0.7
const HOLD := 1.6
const FADE_OUT := 0.6
const GAP := 0.3             # 로고 사이 검은 화면
const SKIP_FADE := 0.25      # 클릭으로 건너뛸 때 사라지는 시간
const MAX_DELTA := 1.0 / 30.0  # 첫 프레임 끊김 때문에 페이드가 건너뛰어지지 않게

enum Phase { WAIT_READY, FADE_IN, HOLD, FADE_OUT, GAP, LOADING, DONE }

var _phase := Phase.WAIT_READY
var _t := 0.0
var _frames := 0
var _index := 0
var _fade_out_time := FADE_OUT
var _logo: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.offset_left = -LOGO_BOX.x * 0.5
	_logo.offset_right = LOGO_BOX.x * 0.5
	_logo.offset_top = -LOGO_BOX.y * 0.5
	_logo.offset_bottom = LOGO_BOX.y * 0.5
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_logo.modulate.a = 0.0
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

	ResourceLoader.load_threaded_request(NEXT_SCENE)

	# 개발용 자동 점검 (GitHub 빌드에서만 사용)
	if "--smoke-test" in OS.get_cmdline_user_args():
		var tester: Node = load("res://scripts/dev/smoke_test.gd").new()
		get_tree().root.add_child.call_deferred(tester)


func _process(delta: float) -> void:
	delta = minf(delta, MAX_DELTA)
	_t += delta
	match _phase:
		Phase.WAIT_READY:
			_frames += 1
			if _frames >= READY_FRAMES and _t >= READY_DELAY:
				_start_logo(0)
		Phase.FADE_IN:
			_logo.modulate.a = _ease(_t / FADE_IN)
			if _t >= FADE_IN:
				_set_phase(Phase.HOLD)
		Phase.HOLD:
			_logo.modulate.a = 1.0
			if _t >= HOLD:
				_begin_fade_out(FADE_OUT)
		Phase.FADE_OUT:
			_logo.modulate.a = minf(_logo.modulate.a, 1.0 - _ease(_t / _fade_out_time))
			if _t >= _fade_out_time:
				_logo.modulate.a = 0.0
				_set_phase(Phase.GAP)
		Phase.GAP:
			if _t >= GAP:
				if _index + 1 < LOGOS.size():
					_start_logo(_index + 1)
				else:
					_set_phase(Phase.LOADING)
		Phase.LOADING:
			_try_finish()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if _phase == Phase.FADE_IN or _phase == Phase.HOLD:
		_begin_fade_out(SKIP_FADE)
	accept_event()


func _start_logo(i: int) -> void:
	_index = i
	_logo.texture = LOGOS[i] as Texture2D
	_logo.modulate.a = 0.0
	_set_phase(Phase.FADE_IN)


func _begin_fade_out(duration: float) -> void:
	_fade_out_time = duration
	_set_phase(Phase.FADE_OUT)


func _set_phase(p: Phase) -> void:
	_phase = p
	_t = 0.0


func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _try_finish() -> void:
	var status := ResourceLoader.load_threaded_get_status(NEXT_SCENE)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return   # 아직 불러오는 중이면 검은 화면으로 조금 더 기다림
	_phase = Phase.DONE
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed := ResourceLoader.load_threaded_get(NEXT_SCENE) as PackedScene
		if packed:
			get_tree().change_scene_to_packed(packed)
			return
	get_tree().change_scene_to_file(NEXT_SCENE)
