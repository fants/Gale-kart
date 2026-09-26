class_name GarageStage
extends MenuStage
## 菜单车库：转台上的卡丁车（KartModel），影棚灯光 + 渐变光芒背景 + 光滑展台倒影，相机缓慢环绕。
## 切换车 / 车手 / 涂装时车子弹跳换装并撒星星；车手偶尔点头（emote-yes）。

const GARAGE_SCALE := 1.45

var table: Node3D
var model: KartModel
var sel_key := ""
var spin_boost := 0.0
var _hop := 0.0
var _emote_t := 5.0
var _emote_left := 0.0
var _floaters: Array[Dictionary] = []
## 漂浮装饰挂在随相机转动的支点上，始终位于主体后方
var _float_pivot: Node3D
var _boxes: Array[MeshInstance3D] = []
var _burst: CPUParticles3D
## 鼠标拖拽旋转转台（只绕竖直轴）：每像素转动的弧度、松手后的惯性、停手后暂停自动旋转的时长
const DRAG_RAD_PER_PX := 0.011
const DRAG_HOLD := 2.5
var dragging := false
var _drag_accum := 0.0
var _drag_vel := 0.0
var _drag_hold := 0.0


func _ready() -> void:
	name = "GarageStage"
	add_to_group("garage_stage")
	_build_stage(Color("#7FD6FF"), Color("#FFE3F1"), Color("#CDEBFF"), 0.0, UiTheme.BUBBLE, "day")
	target = Vector3(0.0, 0.45, 0.0)
	subject_radius = 2.35
	bg_mat.set_shader_parameter("art_blur", 2.6)
	bg_mat.set_shader_parameter("art_wash", 0.12)
	fill = 0.96
	pitch = 0.26
	_build_table()
	_build_floaters()
	_build_burst()


func _build_table() -> void:
	table = Node3D.new()
	table.name = "Turntable"
	add_child(table)
	# 不要实体转台：地上一团柔和的接触阴影 + 一圈随转台转动的发光圆环
	var shadow := MeshInstance3D.new()
	var sq := PlaneMesh.new()
	sq.size = Vector2(5.4, 5.4)
	shadow.mesh = sq
	shadow.position.y = 0.01
	var grad := Gradient.new()
	grad.set_color(0, Color(0.06, 0.08, 0.2, 0.55))
	grad.set_color(1, Color(0.06, 0.08, 0.2, 0.0))
	grad.add_point(0.45, Color(0.06, 0.08, 0.2, 0.32))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = gt
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.render_priority = -1
	shadow.material_override = sm
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	var ring_mi := MeshInstance3D.new()
	var rq := PlaneMesh.new()
	rq.size = Vector2(6.0, 6.0)
	ring_mi.mesh = rq
	ring_mi.position.y = 0.02
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://assets/shaders/garage_ring.gdshader")
	ring_mi.material_override = rm
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	table.add_child(ring_mi)

## 漂浮装饰：半透明彩虹道具箱与星星
func _build_floaters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var star := star_mesh(0.42, 0.2, 0.18)
	var colors: Array[Color] = [UiTheme.SUN, UiTheme.PINK, UiTheme.MINT, UiTheme.BUBBLE]
	_float_pivot = Node3D.new()
	add_child(_float_pivot)
	# 局部坐标 -Z 指向远离相机的方向
	var spots: Array[Vector3] = [
		Vector3(-17, 7.5, -16), Vector3(-9, 9.5, -22), Vector3(2, 10.5, -26), Vector3(12, 8.5, -20),
		Vector3(21, 6.0, -18), Vector3(-23, 2.5, -24), Vector3(26, 1.5, -28), Vector3(-6, 4.0, -30), Vector3(15, 3.0, -32),
	]
	for i in spots.size():
		var is_box := i % 3 == 0
		var m := MeshInstance3D.new()
		if is_box:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.9
			m.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1, 1, 1, 0.72)
			mat.emission_enabled = true
			mat.emission_energy_multiplier = 0.35
			mat.roughness = 0.2
			m.material_override = mat
			var q := Label3D.new()
			q.text = "?"
			q.font = UiTheme.font_num()
			q.font_size = 96
			q.pixel_size = 0.006
			q.outline_size = 22
			q.outline_modulate = UiTheme.INK
			q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			q.no_depth_test = false
			m.add_child(q)
			_boxes.append(m)
		else:
			m.mesh = star
			m.material_override = toon_mat(colors[i % colors.size()], 0.35)
		m.position = spots[i]
		m.scale = Vector3.ONE * (2.2 + rng.randf() * 0.8)
		_float_pivot.add_child(m)
		_floaters.append({"node": m, "y": m.position.y, "ph": rng.randf() * TAU, "spin": 0.5 + rng.randf() * 0.6})


## 换装时撒出的星星
func _build_burst() -> void:
	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 26
	_burst.lifetime = 1.1
	_burst.explosiveness = 0.95
	_burst.mesh = star_mesh(0.14, 0.065, 0.05)
	_burst.direction = Vector3.UP
	_burst.spread = 70.0
	_burst.initial_velocity_min = 3.5
	_burst.initial_velocity_max = 6.5
	_burst.gravity = Vector3(0, -9.0, 0)
	_burst.angular_velocity_min = -360.0
	_burst.angular_velocity_max = 360.0
	_burst.scale_amount_min = 0.7
	_burst.scale_amount_max = 1.3
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([UiTheme.SUN, UiTheme.PINK, UiTheme.MINT, UiTheme.BUBBLE, UiTheme.SUN])
	_burst.color_initial_ramp = grad
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	_burst.material_override = mat
	_burst.position = Vector3(0, 1.0, 0)
	add_child(_burst)


## 展示指定的车 / 车手 / 涂装（与当前不同时重建模型并播放弹跳）
func show_kart(kart_id: String, character_id: String, paint_id: String) -> void:
	var key := "%s|%s|%s" % [kart_id, character_id, paint_id]
	if key == sel_key:
		return
	var old_char := ""
	if model:
		old_char = model.character_id
		model.queue_free()
	var first := sel_key == ""
	sel_key = key
	model = KartModel.create(kart_id, character_id, paint_id)
	model.scale = Vector3.ONE * GARAGE_SCALE
	model.position.y = 0.16
	table.add_child(model)
	model.play_driver_anim("drive")
	if first:
		return
	spin_boost = 4.0
	_hop = 0.42
	_burst.restart()
	if old_char != character_id:
		_start_emote()


func drag_begin() -> void:
	dragging = true
	_drag_accum = 0.0
	_drag_vel = 0.0
	spin_boost = 0.0


## dx 为鼠标水平移动的像素（向右为正：转台近侧跟着向右转）
func drag_by(dx: float) -> void:
	if dragging:
		_drag_accum += dx * DRAG_RAD_PER_PX


func drag_end() -> void:
	if not dragging:
		return
	dragging = false
	_drag_vel = clampf(_drag_vel, -8.0, 8.0)
	_drag_hold = DRAG_HOLD


func _start_emote() -> void:
	if model == null:
		return
	model.play_driver_anim("emote-yes")
	_emote_left = 1.3
	_emote_t = 7.0 + randf() * 5.0


func _process(dt: float) -> void:
	super(dt)
	spin_boost *= exp(-dt * 3.0)
	if dragging:
		# 拖动中：转台完全跟手，同时估计角速度供松手后的惯性使用
		table.rotation.y += _drag_accum
		_drag_vel = lerpf(_drag_vel, _drag_accum / maxf(dt, 0.001), 0.5)
		_drag_accum = 0.0
	else:
		_drag_vel *= exp(-dt * 3.5)
		_drag_hold = maxf(0.0, _drag_hold - dt)
		# 停手一段时间后自动旋转慢慢恢复
		var auto := 1.0 - clampf(_drag_hold / 1.0, 0.0, 1.0)
		table.rotation.y += dt * (0.3 * auto + spin_boost + _drag_vel)
	if model:
		_hop = maxf(0.0, _hop - dt)
		var u := 1.0 - _hop / 0.42
		model.position.y = 0.16 + (sin(minf(u, 1.0) * PI) * 0.65 if _hop > 0.0 else 0.0)
		# 落地时压扁回弹
		var squash := 1.0 + sin(clampf(u * 1.4, 0.0, 1.0) * PI * 2.0) * 0.06 * float(_hop > 0.0)
		model.scale = Vector3(GARAGE_SCALE / sqrt(squash), GARAGE_SCALE * squash, GARAGE_SCALE / sqrt(squash))
		model.body.position.y = sin(time * 20.0) * 0.006
		if _emote_left > 0.0:
			_emote_left -= dt
			if _emote_left <= 0.0:
				model.play_driver_anim("drive")
		else:
			_emote_t -= dt
			if _emote_t <= 0.0:
				_start_emote()
	_float_pivot.rotation.y = yaw
	for f in _floaters:
		var n: MeshInstance3D = f["node"]
		var ph: float = f["ph"]
		var y0: float = f["y"]
		var sp: float = f["spin"]
		n.position.y = y0 + sin(time * 1.1 + ph) * 0.6
		n.rotation.y += dt * sp
		n.rotation.x = sin(time * 0.7 + ph) * 0.4
	# 道具箱彩虹变色
	for i in _boxes.size():
		var mat := _boxes[i].material_override as StandardMaterial3D
		var c := Color.from_hsv(fmod(time * 0.08 + i * 0.3, 1.0), 0.45, 1.0, 0.72)
		mat.albedo_color = c
		mat.emission = c
