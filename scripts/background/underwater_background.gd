extends Control
## 메인화면 배경: 에메랄드빛 바다 밑, 모래에 가라앉은 보드게임 판.
##   1) Water        - 물 색과 수면 쪽 빛무늬 (셰이더)
##   2) Seabed       - 미리 렌더링한 바다 밑 장면 (tools/render_seabed.py 로 만듦) + 움직이는 빛무늬
##   3) SeaLife      - 흔들리는 해초, 헤엄치는 물고기 떼
##   4) Bubbles      - 물방울, 부유물, 보드판 밑에서 새어 나오는 공기방울
##   5) LightRays / Vignette
## 다른 화면에서도 scenes/underwater_background.tscn 을 그대로 재사용하면 돼요.

const WaterShader := preload("res://shaders/water_background.gdshader")
const CausticShader := preload("res://shaders/seabed_caustics.gdshader")
const RaysShader := preload("res://shaders/god_rays.gdshader")
const VignetteShader := preload("res://shaders/vignette.gdshader")
const SceneTex := preload("res://textures/seabed_scene.png")
const PosTex := preload("res://textures/seabed_caustic_pos.png")
const MaskTex := preload("res://textures/seabed_caustic_mask.png")
const SeaLife := preload("res://scripts/background/sea_life.gd")
const Bubbles := preload("res://scripts/background/bubbles.gd")

const BASE_SIZE := Vector2(1920, 1080)
## 보드판 밑에서 공기방울이 새어 나오는 곳 (1920x1080 기준, 렌더러가 알려준 위치)
const VENTS := [Vector2(1560, 512), Vector2(1050, 372), Vector2(1428, 318)]

@export var show_seabed := true
@export var parallax_strength := 26.0

var _water: ColorRect
var _seabed: TextureRect
var _life: SeaLife
var _rays: ColorRect
var _vignette: ColorRect
var _bubbles_back: Bubbles
var _bubbles_front: Bubbles
var _parallax := Vector2.ZERO
var _cover_scale := 1.0
var _cover_offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water = _make_shader_rect(WaterShader, "Water")

	_bubbles_back = Bubbles.new()
	_bubbles_back.name = "BubblesBack"
	_bubbles_back.ambient_rate = 3.0
	_bubbles_back.snow_count = 60
	add_child(_bubbles_back)

	if show_seabed:
		_seabed = TextureRect.new()
		_seabed.name = "Seabed"
		_seabed.texture = SceneTex
		_seabed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_seabed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_seabed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = CausticShader
		m.set_shader_parameter("pos_tex", PosTex)
		m.set_shader_parameter("mask_tex", MaskTex)
		_seabed.material = m
		add_child(_seabed)
		_seabed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		_life = SeaLife.new()
		_life.name = "SeaLife"
		add_child(_life)

	_bubbles_front = Bubbles.new()
	_bubbles_front.name = "BubblesFront"
	_bubbles_front.ambient_rate = 2.0
	_bubbles_front.snow_count = 30
	add_child(_bubbles_front)

	_rays = _make_shader_rect(RaysShader, "LightRays")
	_vignette = _make_shader_rect(VignetteShader, "Vignette")

	resized.connect(_on_resized)
	_on_resized()


func _make_shader_rect(shader: Shader, node_name: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = node_name
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


func _on_resized() -> void:
	if size.y <= 0.0:
		return
	var aspect := Vector2(size.x / size.y, 1.0)
	(_water.material as ShaderMaterial).set_shader_parameter("aspect", aspect)
	(_rays.material as ShaderMaterial).set_shader_parameter("aspect", aspect)
	_bubbles_back.area_size = size
	_bubbles_front.area_size = size
	# 장면 그림과 같은 방식(화면을 꽉 채우게)으로 1920x1080 좌표를 화면 좌표로 바꾸는 값
	_cover_scale = maxf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)
	_cover_offset = (size - BASE_SIZE * _cover_scale) * 0.5
	var vents: Array[Vector2] = []
	for v in VENTS:
		vents.append(_cover_offset + (v as Vector2) * _cover_scale)
	_bubbles_front.vents = vents


func _process(delta: float) -> void:
	var target := Vector2.ZERO
	if size.x > 0.0 and size.y > 0.0:
		target = (get_local_mouse_position() / size - Vector2(0.5, 0.5)) * 2.0
		target = target.clamp(Vector2(-1, -1), Vector2(1, 1))
	_parallax = _parallax.lerp(target, 1.0 - exp(-delta * 2.5))
	(_water.material as ShaderMaterial).set_shader_parameter("parallax", _parallax)
	_bubbles_back.position = -_parallax * parallax_strength * 0.3
	_bubbles_front.position = -_parallax * parallax_strength * 0.9
	if _life:
		_life.scale = Vector2.ONE * _cover_scale
		_life.position = _cover_offset - _parallax * parallax_strength * 0.6


## 화면의 특정 위치(전역 좌표)에서 물방울을 뿜어요
func burst_bubbles(global_pos: Vector2, count: int = 8) -> void:
	_bubbles_front.burst(_bubbles_front.to_local(global_pos), count)
