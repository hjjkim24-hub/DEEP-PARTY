extends Node3D
## 개발용: 꾸미기 아이템 12가지를 낀 말을 한 줄로 세워 보는 화면 (스크린샷 점검용)

const Pawn3D := preload("res://scripts/world3d/pawn3d.gd")
const SkyShader := preload("res://shaders/underwater_sky.gdshader")
const LOOKS := [
	{}, {"hat": "party_hat"}, {"hat": "top_hat"}, {"hat": "crown"}, {"hat": "beanie"},
	{"pattern": "stripes"}, {"pattern": "diamond"},
	{"accessory": "scarf"}, {"accessory": "sunglasses"}, {"accessory": "pearl_necklace"},
	{"outfit": "red_cape"}, {"outfit": "swim_ring"}, {"outfit": "coat"},
]
const COLORS := [Color("ff7a6b"), Color("f0d49a"), Color("4fe0c8"), Color("b49cff"), Color("6cb8ff"), Color("e88aa8")]

var pawns: Array = []
var cam: Camera3D


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SkyShader
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.6, 0.6)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.7, 0.66, 0.52)
	floor_mi.material_override = fm
	add_child(floor_mi)
	for i in LOOKS.size():
		var p := Pawn3D.new()
		p.color = COLORS[i % COLORS.size()]
		p.look = LOOKS[i]
		p.scale = Vector3.ONE * 1.7
		var row := 0 if i < 7 else 1
		var col := i if i < 7 else i - 7
		var n := 7 if row == 0 else 6
		p.position = Vector3((col - (n - 1) * 0.5) * 1.55, 0, row * 2.6)
		add_child(p)
		pawns.append(p)
	cam = Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(0, 3.6, 11.5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 1.3))
	cam.make_current()


## 모두 뒤돌기 (뒷모습 점검)
func turn_around() -> void:
	for p in pawns:
		p.rotation.y = PI
