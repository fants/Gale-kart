class_name KartModel
extends Node3D
## 赛车外观：Kenney 卡丁车（涂装版本）+ Mini Characters 车手（drive 动画）+ 车型配件。
## 纯外观节点，车库、颁奖台、回放、幽灵车都复用。本地坐标：+Z 为车头，原点在车底中心。

## 整体缩放：Kenney 卡丁车原长约 1.43 m，放大后约 2.2 m
const BASE_SCALE := 1.55
const WHEEL_R := 0.21
## 车手相对卡丁车的缩放（Kenney 原车手略大于 Mini Character）
const DRIVER_SCALE := 1.12

var kart_id := ""
var character_id := ""
var paint_id := ""

## 车身（随侧倾 / 俯仰 / 漂移甩角旋转）
var body: Node3D
## Kenney 卡丁车实例
var kart_root: Node3D
var driver: Node3D
var driver_anim: AnimationPlayer
var wheels: Array[Node3D] = []   # 顺序：前左、前右、后左、后右
var _wheel_spin := 0.0
var _exhausts: Array[Vector3] = []
var _ghost := false


static func create(p_kart_id: String, p_character_id: String, p_paint_id: String) -> KartModel:
	var m := KartModel.new()
	m._build(p_kart_id, p_character_id, p_paint_id)
	return m


func _build(p_kart_id: String, p_character_id: String, p_paint_id: String) -> void:
	kart_id = p_kart_id
	character_id = p_character_id
	paint_id = p_paint_id
	name = "KartModel"
	var kd := KartsData.kart_by_id(kart_id)
	var look: Dictionary = kd["look"]
	var paint := KartsData.paint_by_id(paint_id)
	var ch := KartsData.character_by_id(character_id)

	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var scale_k := BASE_SCALE * float(look.get("scale", 1.0))

	kart_root = (load("res://assets/models/karts/%s.glb" % paint["model"]) as PackedScene).instantiate()
	kart_root.scale = Vector3.ONE * scale_k
	body.add_child(kart_root)
	# 原车手（外星宇航员）隐藏，换成 Mini Character
	var orig := kart_root.find_child("character", true, false)
	if orig:
		orig.visible = false
	for wn in ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]:
		var w := kart_root.find_child(wn, true, false) as Node3D
		wheels.append(w)

	# 换车轮：Car Kit 的车轮半径 0.3，缩到 0.21；左右轮毂朝外
	var wheel_model: String = look.get("wheels", "")
	if wheel_model != "":
		var wscene := load("res://assets/models/karts/%s.glb" % wheel_model) as PackedScene
		for i in wheels.size():
			var w := wheels[i] as MeshInstance3D
			if w == null:
				continue
			w.mesh = null
			var nw: Node3D = wscene.instantiate()
			var left := i % 2 == 0
			nw.scale = Vector3.ONE * (WHEEL_R / 0.3)
			nw.position = Vector3(0.1 if left else -0.1, 0.0, 0.0)
			if not left:
				nw.rotation.y = PI
			w.add_child(nw)

	# 尾翼
	var spoiler: String = look.get("spoiler", "")
	if spoiler != "":
		var sp: Node3D = (load("res://assets/models/karts/%s.glb" % spoiler) as PackedScene).instantiate()
		sp.scale = Vector3.ONE * 0.78
		sp.position = Vector3(0.0, 0.5, -0.62)
		kart_root.add_child(sp)
	# 前保险杠
	if look.get("bumper", false):
		var bp: Node3D = (load("res://assets/models/karts/debris-bumper.glb") as PackedScene).instantiate()
		bp.scale = Vector3.ONE * 0.74
		bp.position = Vector3(0.0, 0.08, 0.72)
		kart_root.add_child(bp)
	# 双排气火箭筒
	_exhausts = [Vector3(-0.2, 0.36, -0.66), Vector3(0.2, 0.36, -0.66)]
	if look.get("exhaust", false):
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color("#5A5F7A")
		metal.metallic = 0.7
		metal.roughness = 0.35
		var ring := StandardMaterial3D.new()
		ring.albedo_color = Color("#FF4D5E")
		for sx: float in [-0.2, 0.2]:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.075
			cm.bottom_radius = 0.09
			cm.height = 0.42
			c.mesh = cm
			c.material_override = metal
			c.rotation.x = PI / 2
			c.position = Vector3(sx, 0.4, -0.58)
			kart_root.add_child(c)
			var r := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.08
			tm.outer_radius = 0.11
			r.mesh = tm
			r.material_override = ring
			r.rotation.x = PI / 2
			r.position = Vector3(sx, 0.4, -0.78)
			kart_root.add_child(r)
		_exhausts = [Vector3(-0.2, 0.4, -0.82), Vector3(0.2, 0.4, -0.82)]

	# 车手
	driver = (load("res://assets/models/characters/%s.glb" % ch["model"]) as PackedScene).instantiate()
	driver.scale = Vector3.ONE * DRIVER_SCALE
	driver.position = Vector3(0.0, 0.265, -0.1)
	kart_root.add_child(driver)
	driver_anim = driver.find_child("AnimationPlayer", true, false) as AnimationPlayer
	play_driver_anim("drive")

	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func play_driver_anim(anim: String) -> void:
	if driver_anim and driver_anim.has_animation(anim):
		var a := driver_anim.get_animation(anim)
		a.loop_mode = Animation.LOOP_LINEAR
		driver_anim.play(anim)


## steer_angle：前轮转角（弧度，正为左）；spin_delta：本帧车轮转过的角度
func set_wheel_state(steer_angle: float, spin_delta: float) -> void:
	_wheel_spin = fmod(_wheel_spin + spin_delta, TAU)
	for i in wheels.size():
		var w := wheels[i]
		if w == null:
			continue
		var steer := steer_angle if i < 2 else 0.0
		w.basis = Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, _wheel_spin)


## roll：侧倾（弧度，正为向右倾）；pitch：俯仰（正为抬头）；drift_yaw：车身相对行驶方向的甩角；bounce：竖直位移（米）
func set_body_pose(roll: float, pitch: float, drift_yaw: float, bounce: float) -> void:
	body.basis = Basis(Vector3.UP, drift_yaw) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, roll)
	body.position = Vector3(0.0, bounce, 0.0)


## 车手随转向侧身（-1..1）
func set_driver_lean(lean: float) -> void:
	if driver:
		driver.rotation = Vector3(0.0, -lean * 0.25, lean * 0.18)


## 后轮着地点（本地坐标，含车身姿态）
func rear_local(side: int) -> Vector3:
	var p := Vector3(0.3 * side, 0.02, -0.36) * kart_root.scale.x
	return body.transform * p


func exhaust_local(i: int) -> Vector3:
	return body.transform * exhaust_body(i)


## 排气口在车身节点（body）坐标系下的位置
func exhaust_body(i: int) -> Vector3:
	return _exhausts[clampi(i, 0, _exhausts.size() - 1)] * kart_root.scale.x


## 幽灵车：半透明青色
func set_ghost(on: bool) -> void:
	_ghost = on
	var mat: StandardMaterial3D = null
	if on:
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.6, 0.95, 1.0, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.8, 1.0)
		mat.emission_energy_multiplier = 0.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for gi in find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
