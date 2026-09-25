class_name PodiumStage
extends MenuStage
## 颁奖台：前三名的车停在 1 / 2 / 3 号台上（冠军台最高），彩带飘落 + 开场礼花，
## 车手点头庆祝（emote-yes），冠军车不时蹦一下，镜头从高处俯冲进来后左右环绕。

## 台子：x 位置、高度、颜色、编号（顺序即名次）
const SLOTS: Array[Dictionary] = [
	{"x": 0.0, "h": 1.7, "num": "1"},
	{"x": -3.9, "h": 1.15, "num": "2"},
	{"x": 3.9, "h": 0.8, "num": "3"},
]
const BLOCK_R := 1.75
const INTRO_TIME := 2.6

var karts: Array[KartModel] = []
var _blocks: Array[Node3D] = []
var _emote_t: Array[float] = []
var _emote_left: Array[float] = []
var _rows_key := ""
var _intro := 0.0
var _burst: GPUParticles3D
var _rain: GPUParticles3D


func _ready() -> void:
	name = "PodiumStage"
	_build_stage(Color("#8FB8FF"), Color("#FFE6C2"), Color("#FFF4E0"), 7.6, UiTheme.PINK)
	bg_mat.set_shader_parameter("ray_color", Color("#FFF3C0"))
	bg_mat.set_shader_parameter("ray_alpha", 0.22)
	bg_mat.set_shader_parameter("rays", 16.0)
	target = Vector3(0.0, 1.7, 0.0)
	subject_radius = 5.4
	pitch = 0.14
	sway = 0.38
	fill = 0.98
	for i in SLOTS.size():
		_blocks.append(_build_block(i))
	_build_lights()
	_build_confetti()


func _build_block(i: int) -> Node3D:
	var s: Dictionary = SLOTS[i]
	var h: float = s["h"]
	var col := UiTheme.rank_color(i + 1)
	var b := Node3D.new()
	b.position = Vector3(float(s["x"]), 0.0, 0.0)
	add_child(b)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = BLOCK_R
	cm.bottom_radius = BLOCK_R
	cm.height = h
	cm.radial_segments = 64
	mi.mesh = cm
	mi.position.y = h / 2.0
	var m := toon_mat(col, 0.35)
	m.metallic = 0.25
	mi.material_override = m
	b.add_child(mi)
	b.add_child(ring(BLOCK_R, 0.06, UiTheme.INK, h))
	b.add_child(ring(BLOCK_R, 0.06, UiTheme.INK, 0.02))
	b.add_child(ring(BLOCK_R + 0.01, 0.045, UiTheme.WHITE, h - 0.16))
	var num := Label3D.new()
	num.text = str(s["num"])
	num.font = UiTheme.font_num()
	num.font_size = 160
	# 编号放在底边与顶部白环之间
	var lo := 0.08
	var hi := h - 0.22
	var glyph := minf(0.9, (hi - lo) * 0.82)
	num.pixel_size = glyph / 112.0
	num.outline_size = 30
	num.outline_modulate = UiTheme.INK
	num.modulate = UiTheme.WHITE
	num.position = Vector3(0.0, (lo + hi) / 2.0, BLOCK_R + 0.07)
	b.add_child(num)
	return b


func _build_lights() -> void:
	var spot := SpotLight3D.new()
	spot.light_color = Color("#FFE9B8")
	spot.light_energy = 6.0
	spot.spot_range = 16.0
	spot.spot_angle = 22.0
	spot.shadow_enabled = true
	add_child(spot)
	spot.look_at_from_position(Vector3(0.0, 9.0, 4.0), Vector3(0.0, 1.6, 0.0))
	for sx: float in [-3.9, 3.9]:
		var s2 := SpotLight3D.new()
		s2.light_color = Color("#CDE8FF")
		s2.light_energy = 2.5
		s2.spot_range = 14.0
		s2.spot_angle = 20.0
		add_child(s2)
		s2.look_at_from_position(Vector3(sx * 1.4, 8.0, 4.0), Vector3(sx, 1.0, 0.0))


func _confetti_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	g.colors = PackedColorArray([UiTheme.SUN, UiTheme.BUBBLE, UiTheme.RED, UiTheme.MINT, UiTheme.PINK])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _confetti_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.12)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = mat
	return q


func _build_confetti() -> void:
	# 持续飘落的彩带
	_rain = GPUParticles3D.new()
	_rain.amount = 320
	_rain.lifetime = 7.0
	_rain.preprocess = 4.0
	_rain.visibility_aabb = AABB(Vector3(-14, -12, -8), Vector3(28, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 0.5, 4.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -1.5, 0)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -280.0
	pm.angular_velocity_max = 280.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.14
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color_initial_ramp = _confetti_ramp()
	_rain.process_material = pm
	_rain.draw_pass_1 = _confetti_mesh()
	_rain.position = Vector3(0, 10.0, 0)
	add_child(_rain)
	# 开场礼花：从冠军台喷出
	_burst = GPUParticles3D.new()
	_burst.amount = 160
	_burst.lifetime = 3.2
	_burst.one_shot = true
	_burst.explosiveness = 0.92
	_burst.emitting = false
	_burst.visibility_aabb = AABB(Vector3(-14, -4, -10), Vector3(28, 20, 20))
	var bm := ParticleProcessMaterial.new()
	bm.direction = Vector3(0, 1, 0)
	bm.spread = 38.0
	bm.initial_velocity_min = 7.0
	bm.initial_velocity_max = 12.0
	bm.gravity = Vector3(0, -7.0, 0)
	bm.damping_min = 1.5
	bm.damping_max = 2.5
	bm.angle_min = 0.0
	bm.angle_max = 360.0
	bm.angular_velocity_min = -400.0
	bm.angular_velocity_max = 400.0
	bm.scale_min = 0.8
	bm.scale_max = 1.4
	bm.color_initial_ramp = _confetti_ramp()
	_burst.process_material = bm
	_burst.draw_pass_1 = _confetti_mesh()
	_burst.position = Vector3(0, 2.0, 0.5)
	add_child(_burst)


## 放上前三名（rows 按名次排序，字段：character_id kart_id paint_id name is_player）；solo 时只有冠军台有车
func setup(rows: Array, solo := false) -> void:
	var key := str(solo)
	for r: Dictionary in rows:
		key += "|%s%s%s" % [r.get("character_id", ""), r.get("kart_id", ""), r.get("paint_id", "")]
	if key == _rows_key:
		return
	_rows_key = key
	for k in karts:
		k.queue_free()
	karts.clear()
	_emote_t.clear()
	_emote_left.clear()
	for c in get_children():
		if c.has_meta("name_tag"):
			c.queue_free()
	for i in SLOTS.size():
		_blocks[i].visible = not solo or i == 0
	var n := mini(rows.size(), 1 if solo else 3)
	for i in n:
		var r: Dictionary = rows[i]
		var s: Dictionary = SLOTS[i]
		var km := KartModel.create(str(r.get("kart_id", "marshmallow")), str(r.get("character_id", "male-a")), str(r.get("paint_id", "oodi")))
		km.position = Vector3(float(s["x"]), float(s["h"]), 0.0)
		km.rotation.y = [0.0, 0.32, -0.32][i]
		add_child(km)
		km.play_driver_anim("emote-yes" if i == 0 else "drive")
		karts.append(km)
		_emote_t.append(0.8 + i * 1.1)
		_emote_left.append(0.0)
		var tag := Label3D.new()
		tag.set_meta("name_tag", true)
		var is_p: bool = r.get("is_player", false)
		var ch := KartsData.character_by_id(str(r.get("character_id", "")))
		tag.text = ("%s（你）" % ch["name"]) if is_p else str(ch["name"])
		tag.font = UiTheme.font_cn()
		tag.font_size = 96
		tag.pixel_size = 0.0042
		tag.outline_size = 26
		tag.outline_modulate = UiTheme.INK
		tag.modulate = UiTheme.SUN if is_p else UiTheme.WHITE
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(float(s["x"]), float(s["h"]) + 2.55, 0.0)
		add_child(tag)
	_intro = 0.0
	_burst.restart()


func _process(dt: float) -> void:
	_intro = minf(_intro + dt, INTRO_TIME)
	var u := _intro / INTRO_TIME
	var e := 1.0 - pow(1.0 - u, 3.0)
	# 开场：从高处远景俯冲到正常机位
	subject_radius = 5.4 * lerpf(1.7, 1.0, e)
	pitch = lerpf(0.55, 0.14, e)
	super(dt)
	for i in karts.size():
		var k := karts[i]
		var s: Dictionary = SLOTS[i]
		var base_y: float = s["h"]
		if i == 0:
			# 冠军车不时蹦一下
			var ph := fmod(time, 2.4)
			k.position.y = base_y + (sin(ph / 0.45 * PI) * 0.35 if ph < 0.45 else 0.0)
			continue
		if _emote_left[i] > 0.0:
			_emote_left[i] -= dt
			if _emote_left[i] <= 0.0:
				k.play_driver_anim("drive")
		else:
			_emote_t[i] -= dt
			if _emote_t[i] <= 0.0:
				k.play_driver_anim("emote-yes")
				_emote_left[i] = 1.33
				_emote_t[i] = 2.5 + randf() * 2.5
