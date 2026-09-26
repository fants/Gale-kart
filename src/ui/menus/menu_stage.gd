class_name MenuStage
extends Node3D
## 菜单 3D 舞台的公共部分（车库、颁奖台共用）：
## 画布背景（渐变 + 旋转光芒，BG_CANVAS 画在 3D 后面）、影棚灯光、圆形展台、
## 相机取景——把主体放进屏幕上指定的矩形（用视锥偏移实现，不同页面平滑切换机位）。

const BG_SHADER := preload("res://assets/shaders/ui_stage_bg.gdshader")

var camera: Camera3D
var env: WorldEnvironment
var key_light: DirectionalLight3D
var bg_layer: CanvasLayer
var bg_mat: ShaderMaterial
var platform: Node3D
var time := 0.0

## 注视点与主体包围球半径（决定取景距离）
var target := Vector3(0.0, 0.8, 0.0)
var subject_radius := 2.6
## 相机环绕：yaw 自动增加；sway > 0 时改为左右摆动（颁奖台用）
var yaw := 0.5
var yaw_speed := 0.1
var sway := 0.0
var sway_center := 0.0
var pitch := 0.22
var fov := 30.0
## 主体在屏幕上的矩形（占视口的比例），平滑过渡
var view_rect := Rect2(0.5, 0.1, 0.45, 0.8)
var _rect := Rect2(0.5, 0.1, 0.45, 0.8)
var _rect_ready := false
## 取景时主体占矩形的比例
var fill := 0.92


func _build_stage(top: Color, bottom: Color, floor_color: Color, floor_radius := 4.4, side_color := UiTheme.BUBBLE, art := "") -> void:
	# 画布背景：CanvasLayer 放在负层，Environment 用 BG_CANVAS 把它画在 3D 之后
	bg_layer = CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = BG_SHADER
	bg_mat.set_shader_parameter("top_color", top)
	bg_mat.set_shader_parameter("bottom_color", bottom)
	var art_tex := UiArt.menu_bg(art) if art != "" else null
	if art_tex != null:
		bg_mat.set_shader_parameter("use_art", true)
		bg_mat.set_shader_parameter("art", art_tex)
		bg_mat.set_shader_parameter("art_aspect", float(art_tex.get_width()) / art_tex.get_height())
	bg.material = bg_mat
	bg_layer.add_child(bg)

	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.background_canvas_max_layer = -1
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#EAF4FF")
	e.ambient_light_energy = 0.75
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.ssr_enabled = true
	e.ssr_max_steps = 64
	e.ssr_fade_in = 0.1
	e.ssr_fade_out = 2.0
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.4
	e.glow_enabled = true
	e.glow_intensity = 0.22
	e.glow_hdr_threshold = 1.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	env = WorldEnvironment.new()
	env.environment = e
	add_child(env)

	key_light = DirectionalLight3D.new()
	key_light.light_color = Color("#FFF3E0")
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.5
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key_light.directional_shadow_max_distance = 40.0
	add_child(key_light)
	key_light.look_at_from_position(Vector3(6, 10, 7), Vector3.ZERO)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#FF9FE0")
	rim.light_energy = 0.7
	add_child(rim)
	rim.look_at_from_position(Vector3(-6, 4, -7), Vector3.ZERO)
	var fill_l := DirectionalLight3D.new()
	fill_l.light_color = Color("#9FD8FF")
	fill_l.light_energy = 0.35
	add_child(fill_l)
	fill_l.look_at_from_position(Vector3(-7, 3, 5), Vector3.ZERO)

	# 圆形展台：光滑台面（屏幕空间反射出倒影）+ 彩色侧边 + 墨线描边
	platform = Node3D.new()
	platform.name = "Platform"
	add_child(platform)
	var side := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = floor_radius
	sm.bottom_radius = floor_radius * 0.94
	sm.height = 0.9
	sm.radial_segments = 96
	side.mesh = sm
	side.position.y = -0.62
	side.material_override = toon_mat(side_color, 0.5)
	platform.add_child(side)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = floor_radius
	cm.bottom_radius = floor_radius
	cm.height = 0.14
	cm.radial_segments = 96
	disc.mesh = cm
	disc.position.y = -0.1
	var dm := StandardMaterial3D.new()
	dm.albedo_color = floor_color
	dm.roughness = 0.22
	dm.metallic_specular = 0.35
	disc.material_override = dm
	platform.add_child(disc)
	platform.add_child(ring(floor_radius, 0.07, UiTheme.INK, -0.03))
	platform.add_child(ring(floor_radius * 0.94, 0.07, UiTheme.INK, -1.07))

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.near = 0.3
	camera.far = 200.0
	add_child(camera)
	camera.make_current()


## 水平圆环（墨线描边 / 彩色边条）
static func ring(radius: float, thick: float, color: Color, y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - thick
	tm.outer_radius = radius + thick
	tm.rings = 96
	tm.ring_segments = 8
	mi.mesh = tm
	mi.position.y = y
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	mi.material_override = m
	return mi


static func toon_mat(color: Color, rough := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


## 五角星棱柱（漂浮装饰、颁奖台）
static func star_mesh(r_outer: float, r_inner: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	for i in 10:
		var a := PI / 2.0 + i * PI / 5.0
		var r := r_outer if i % 2 == 0 else r_inner
		pts.append(Vector2(cos(a), sin(a)) * r)
	var hz := depth / 2.0
	for face: float in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, face))
		for i in 10:
			var a := pts[i]
			var b := pts[(i + 1) % 10]
			var c := Vector3(0, 0, hz * face * 1.4)
			if face > 0.0:
				st.add_vertex(c)
				st.add_vertex(Vector3(a.x, a.y, hz * face))
				st.add_vertex(Vector3(b.x, b.y, hz * face))
			else:
				st.add_vertex(c)
				st.add_vertex(Vector3(b.x, b.y, hz * face))
				st.add_vertex(Vector3(a.x, a.y, hz * face))
	for i in 10:
		var a := pts[i]
		var b := pts[(i + 1) % 10]
		var n := Vector3(b.y - a.y, -(b.x - a.x), 0).normalized()
		st.set_normal(n)
		st.add_vertex(Vector3(a.x, a.y, hz))
		st.add_vertex(Vector3(a.x, a.y, -hz))
		st.add_vertex(Vector3(b.x, b.y, hz))
		st.add_vertex(Vector3(b.x, b.y, hz))
		st.add_vertex(Vector3(a.x, a.y, -hz))
		st.add_vertex(Vector3(b.x, b.y, -hz))
	st.generate_normals()
	return st.commit()


## 设置主体在屏幕上的矩形（视口比例）；instant 为 true 时不做过渡
func set_view_rect(r: Rect2, instant := false) -> void:
	view_rect = r
	if instant or not _rect_ready:
		_rect = r
		_rect_ready = true


func _process(dt: float) -> void:
	time += dt
	_update_camera(dt)


func _update_camera(dt: float) -> void:
	if camera == null:
		return
	var k := 1.0 - exp(-dt * 4.0)
	_rect = Rect2(_rect.position.lerp(view_rect.position, k), _rect.size.lerp(view_rect.size, k))
	if sway > 0.0:
		yaw = sway_center + sin(time * 0.3) * sway
	else:
		yaw += yaw_speed * dt
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var t := tan(deg_to_rad(fov) / 2.0)
	var span := minf(_rect.size.y, _rect.size.x * aspect)
	var dist := subject_radius / (fill * t * maxf(span, 0.05))
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = target + dir * dist
	camera.look_at(target, Vector3.UP)
	# 视锥偏移：主体投影到矩形中心
	var s := 2.0 * camera.near * t
	var c := _rect.get_center()
	camera.size = s
	camera.frustum_offset = Vector2(-(c.x - 0.5) * s * aspect, (c.y - 0.5) * s)
	if bg_mat:
		bg_mat.set_shader_parameter("aspect", aspect)
		bg_mat.set_shader_parameter("center", c)
