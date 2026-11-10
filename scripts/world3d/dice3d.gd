extends Node3D
## 3D 주사위. 말 머리 위에 떠서 빙글빙글 돌다가, roll_to(n) 하면 n 이 위로 오게 멈춰요.
##   show_at(pos)   나타나기 (뿅)
##   roll_to(n)     굴리기 (await 가능) — 결과는 미리 정해 줌 (튜토리얼은 정해진 숫자, 보통은 랜덤)
##   hide_dice()    사라지기

const MeshKit := preload("res://scripts/world3d/mesh_kit.gd")
const ATLAS := preload("res://textures/dice/dice_atlas.png")
const SIZE := 1.15

## 눈 n 이 위(+Y)로 오게 하는 회전
static func face_up(n: int) -> Basis:
	match n:
		2: return Basis(Vector3(1, 0, 0), -PI / 2)
		3: return Basis(Vector3(0, 0, 1), PI / 2)
		4: return Basis(Vector3(0, 0, 1), -PI / 2)
		5: return Basis(Vector3(1, 0, 0), PI / 2)
		6: return Basis(Vector3(1, 0, 0), PI)
	return Basis()


var spinning := false
var _body: MeshInstance3D
var _spin_axis := Vector3(0.6, 1.0, 0.3).normalized()
var _spin_speed := 4.0
var _bob := 0.0
var _anchor := Vector3.ZERO


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = MeshKit.rounded_box(Vector3.ONE * SIZE, SIZE * 0.17, true, 4)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ATLAS
	m.roughness = 0.22
	m.metallic_specular = 0.6
	m.rim_enabled = true
	m.rim = 0.25
	m.emission_enabled = true
	m.emission = Color(0.12, 0.16, 0.15)
	_body.material_override = m
	add_child(_body)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_bob += delta
	position = _anchor + Vector3(0, sin(_bob * 2.4) * 0.12, 0)
	if spinning:
		_body.basis = (Basis(_spin_axis, delta * _spin_speed) * _body.basis).orthonormalized()
		_spin_axis = _spin_axis.rotated(Vector3.UP, delta * 0.7).normalized()


func show_at(p: Vector3) -> void:
	_anchor = p
	position = p
	visible = true
	spinning = true
	_spin_speed = 4.0
	scale = Vector3.ONE * 0.01
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func move_anchor(p: Vector3) -> void:
	_anchor = p


## n 이 위로 오게 멈추기. 멈추는 순간 살짝 통통.
func roll_to(n: int) -> void:
	_spin_speed = 16.0
	var t0 := create_tween()
	t0.tween_property(self, "_anchor", _anchor + Vector3(0, 0.7, 0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t0.tween_property(self, "_anchor", _anchor, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await get_tree().create_timer(0.55).timeout
	spinning = false
	# 위로 온 면이 카메라 쪽(남쪽)으로 살짝 기울어 보이게
	var target := Basis(Vector3(1, 0, 0), 0.42) * Basis(Vector3.UP, 0.35) * face_up(clampi(n, 1, 6))
	var from := _body.basis.get_rotation_quaternion()
	var to := target.get_rotation_quaternion()
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void: _body.basis = Basis(from.slerp(to, f)), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector3.ONE * 1.25, 0.1)
	pop.tween_property(self, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	await pop.finished


func hide_dice() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await t.finished
	visible = false
	spinning = false


## 화면에서 주사위가 차지하는 네모 (클릭 영역·튜토리얼 표시용)
func screen_rect(cam: Camera3D) -> Rect2:
	var r := Rect2()
	var first := true
	var s := SIZE * 0.75 * scale.x
	for c in [Vector3(-s, -s, 0), Vector3(s, -s, 0), Vector3(-s, s, 0), Vector3(s, s, 0), Vector3(0, 0, -s), Vector3(0, 0, s)]:
		var wp: Vector3 = global_position + c
		if cam.is_position_behind(wp):
			continue
		var p := cam.unproject_position(wp)
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	return r
