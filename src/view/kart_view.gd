class_name KartView
extends Node3D
## 驱动单辆车的表现：插值位置朝向、车身姿态（俯仰 / 侧倾 / 落地压缩 / 漂移甩角）、车轮、车手、
## 受击动画（打转 / 翻车 / 水泡上浮）、无敌闪烁、氮气尾焰、名牌、AI 引擎声。

const KMH := 3.6 * 1.4

var kart: KartSim
var model: KartModel
var status_fx: KartStatusFx
var name_tag: Label3D
var engine: AudioStreamPlayer3D
var flames: Array[MeshInstance3D] = []
var _flame_mat: StandardMaterial3D

var _pitch := 0.0
var _roll := 0.0
var _fake_yaw := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _prev_on_ground := true
var _hit_spin := 0.0
var _steer_vis := 0.0


## opts: {show_name: bool, night: bool, engine_audio: bool}
func setup(p_kart: KartSim, opts := {}) -> void:
	kart = p_kart
	name = "Kart_%d" % kart.index
	model = KartModel.create(kart.kart_def["id"], kart.character["id"], kart.paint["id"])
	add_child(model)
	status_fx = KartStatusFx.new()
	status_fx.name = "StatusFx"
	add_child(status_fx)
	status_fx.setup(kart)

	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.albedo_color = Color(0.45, 0.8, 1.0, 0.9)
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 2:
		var f := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.13
		cone.height = 0.8
		cone.radial_segments = 10
		f.mesh = cone
		f.material_override = _flame_mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		model.body.add_child(f)
		flames.append(f)

	if opts.get("show_name", false):
		name_tag = Label3D.new()
		name_tag.text = kart.name
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.fixed_size = false
		name_tag.pixel_size = 0.0042
		name_tag.font_size = 64
		name_tag.outline_size = 16
		name_tag.modulate = Color(0.75, 0.75, 0.85) if opts.get("night", false) else Color(1, 1, 1)
		name_tag.outline_modulate = Color("#1B1F3B")
		name_tag.position = Vector3(0, 2.9, 0)
		name_tag.no_depth_test = false
		name_tag.shaded = false
		add_child(name_tag)

	if opts.get("engine_audio", false):
		engine = AudioMgr.make_engine_3d()
		if engine:
			add_child(engine)
			engine.play()


func update_view(dt: float, time: float, alpha: float, cam_pos: Vector3) -> void:
	var k := kart
	var pos := Vector3(lerpf(k.prev_x, k.x, alpha), lerpf(k.prev_y, k.y, alpha), lerpf(k.prev_z, k.z, alpha))
	var heading := MathX.lerp_angle_short(k.prev_heading, k.heading, alpha)
	position = pos

	# AI 视觉漂移：车身偏转
	_fake_yaw = MathX.damp(_fake_yaw, 0.0 if k.drifting else k.fake_drift * 0.42, 5.0, dt)
	var yaw := heading + _fake_yaw
	# 被香蕉打转
	if k.spin > 0.0:
		_hit_spin += dt * 14.0 * minf(1.0, k.spin + 0.3)
	else:
		_hit_spin = MathX.damp(_hit_spin, roundf(_hit_spin / TAU) * TAU, 10.0, dt)
	yaw += _hit_spin
	rotation = Vector3(0.0, yaw, 0.0)

	# 俯仰：跟随坡度，腾空时按弹道
	var pitch_t := atan(k.slope)
	if not k.on_ground:
		pitch_t = clampf(atan2(k.vy, maxf(k.speed, 8.0)) * 0.7, -0.45, 0.5)
	_pitch = MathX.damp(_pitch, pitch_t, 12.0 if k.on_ground else 4.0, dt)
	var sp01 := clampf(k.speed / 36.0, 0.0, 1.4)
	var roll_t := k.steer * 0.07 * sp01 + (k.drift_dir * 0.08 if k.drifting else k.fake_drift * 0.06)
	_roll = MathX.damp(_roll, roll_t, 8.0, dt)

	# 落地压缩（弹簧阻尼）
	if k.on_ground and not _prev_on_ground:
		_squash_v -= 3.5
	_prev_on_ground = k.on_ground
	_squash_v += (-_squash * 180.0 - _squash_v * 14.0) * dt
	_squash += _squash_v * dt

	var flip_x := 0.0
	var lift := 0.0
	if k.flip > 0.0:
		var u := 1.0 - k.flip / 1.35
		flip_x = u * TAU
		lift = sin(u * PI) * 0.6
	if k.bubble > 0.0:
		var u := 1.0 - k.bubble / 1.6
		lift = sin(minf(1.0, u * 3.0) * PI * 0.5) * 1.6 * (1.0 if u < 0.85 else (1.0 - u) / 0.15)
	var rumble := sin(time * 30.0 + k.index) * 0.012 * sp01 * (1.0 if k.on_ground else 0.0)
	var roll := _roll
	var pitch := _pitch + flip_x
	if k.bubble > 0.0:
		roll += sin(time * 4.0) * 0.2
		pitch += cos(time * 3.0) * 0.15
	model.set_body_pose(roll, pitch, 0.0, lift + rumble + _squash * 0.3)
	model.body.scale = Vector3(1.0 - _squash * 0.5, 1.0 + _squash, 1.0 - _squash * 0.5)

	# 车轮与车手
	_steer_vis = MathX.damp(_steer_vis, k.steer, 14.0, dt)
	var steer_angle := -_steer_vis * 0.42 + (k.drift_dir * 0.28 if k.drifting else 0.0)
	model.set_wheel_state(steer_angle, (k.forward_speed / 0.33) * dt)
	model.set_driver_lean(_steer_vis)

	# 尾焰
	var boosting := k.is_boosting()
	for i in flames.size():
		var f := flames[i]
		f.visible = boosting
		if boosting:
			var nitro := k.boost_kind == "nitro" or k.boost_kind == "start"
			var s := (1.3 if nitro else 0.85) * randf_range(0.85, 1.15)
			f.scale = Vector3(s, s * randf_range(1.0, 1.5), s)
			f.position = model.exhaust_local(i) - model.body.position + Vector3(0, 0, -0.35 * s)
			f.rotation = Vector3(-PI / 2, 0, 0)
	_flame_mat.albedo_color = Color(0.45, 0.8, 1.0, 0.9) if k.boost_kind in ["nitro", "start", "instant"] else Color(1.0, 0.6, 0.2, 0.9)

	# 重生无敌闪烁
	model.visible = not (k.invuln > 0.0 and not k.is_disabled() and sin(time * 40.0) > 0.3) or k.shield > 0.0

	status_fx.update_view(dt, time, lift)

	if name_tag:
		var d := cam_pos.distance_to(pos)
		name_tag.visible = d < 70.0 and d > 7.0
		name_tag.modulate.a = clampf((70.0 - d) / 20.0, 0.0, 1.0) * clampf((d - 7.0) / 4.0, 0.0, 1.0)

	if engine:
		engine.pitch_scale = clampf(0.7 + sp01 * 1.3 + (0.15 if boosting else 0.0), 0.5, 2.6)


func rear_world(side: int) -> Vector3:
	return global_transform * model.rear_local(side)


func exhaust_world(i: int) -> Vector3:
	return global_transform * model.exhaust_local(i)
