class_name SceneryWeather
extends RefCounted
## 天气粒子：一个 GPUParticles3D 常驻在相机周围的盒子里（处理着色器按相机位置取模绕回），
## 飘雪 / 落叶 / 沙尘 / 萤火虫；另有瀑布水雾（内置粒子材质）。

const PROCESS_SHADER := preload("res://assets/shaders/weather.gdshader")
const DRAW_SHADER := preload("res://assets/shaders/weather_draw.gdshader")

## 各天气的参数：count 为「高」画质粒子数（再乘画质预设的 particles 系数）
const PRESETS := {
	"snow": {"mode": 0, "shape": 0, "count": 4200, "box": Vector3(90, 44, 90), "y": 10.0, "fall": 2.4, "size": Vector2(0.07, 0.17),
		"wind": Vector3(0.8, 0.0, 0.3), "a": Color(1, 1, 1, 0.95), "b": Color(0.88, 0.94, 1.0, 0.8)},
	"leaves": {"mode": 1, "shape": 1, "count": 260, "box": Vector3(110, 36, 110), "y": 8.0, "fall": 1.3, "size": Vector2(0.18, 0.3),
		"wind": Vector3(1.2, 0.0, 0.5), "a": Color("#7CC24A"), "b": Color("#F2A93B")},
	"dust": {"mode": 2, "shape": 2, "count": 260, "box": Vector3(150, 8, 150), "y": -2.5, "fall": 0.0, "size": Vector2(1.6, 4.0),
		"wind": Vector3(4.5, 0.0, 1.8), "a": Color(0.96, 0.83, 0.6, 0.11), "b": Color(0.9, 0.74, 0.5, 0.07)},
	"fireflies": {"mode": 3, "shape": 3, "count": 520, "box": Vector3(90, 12, 90), "y": 1.0, "fall": 0.0, "size": Vector2(0.07, 0.13),
		"wind": Vector3.ZERO, "a": Color("#FFE27A"), "b": Color("#C9FF6A")},
}

var node: GPUParticles3D
var _mat: ShaderMaterial
var _y := 0.0


## 返回 null 表示该主题没有天气
static func create(kind: String, particles_k: float) -> SceneryWeather:
	if not PRESETS.has(kind):
		return null
	var w := SceneryWeather.new()
	w._build(PRESETS[kind], particles_k)
	return w


func _build(p: Dictionary, k: float) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = PROCESS_SHADER
	var box: Vector3 = p["box"]
	var size: Vector2 = p["size"]
	_mat.set_shader_parameter("mode", p["mode"])
	_mat.set_shader_parameter("box_size", box)
	_mat.set_shader_parameter("wind", p["wind"])
	_mat.set_shader_parameter("fall_speed", p["fall"])
	_mat.set_shader_parameter("size_min", size.x)
	_mat.set_shader_parameter("size_max", size.y)
	_mat.set_shader_parameter("color_a", p["a"])
	_mat.set_shader_parameter("color_b", p["b"])
	_y = p["y"]
	var draw := ShaderMaterial.new()
	draw.shader = DRAW_SHADER
	draw.set_shader_parameter("shape", p["shape"])
	draw.set_shader_parameter("glow", 4.0)
	draw.set_shader_parameter("near_fade", 3.0 if p["shape"] == 2 else 1.2)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.material = draw
	node = GPUParticles3D.new()
	node.name = "Weather"
	node.amount = maxi(16, roundi(float(p["count"]) * k))
	node.lifetime = 3600.0
	node.explosiveness = 1.0
	node.fixed_fps = 0
	node.local_coords = false
	node.process_material = _mat
	node.draw_pass_1 = quad
	node.visibility_aabb = AABB(-box * 0.5 - Vector3(4, 4, 4), box + Vector3(8, 8, 8))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 每帧：盒子中心放到相机前方一点（车在往前跑，前方更需要粒子）
func follow(cam: Camera3D) -> void:
	var t := cam.global_transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	var c := t.origin + fwd.normalized() * 12.0 + Vector3(0, _y, 0)
	node.global_position = c
	_mat.set_shader_parameter("center", c)


## 瀑布底部的水雾：向上向外翻涌的白色柔团
static func mist(width: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.5, 1.5)
	pm.direction = Vector3(0, 1, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 1.6
	pm.scale_max = 3.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.15, Color(0.95, 1.0, 1.0, 0.42))
	grad.add_point(0.6, Color(0.9, 0.97, 1.0, 0.22))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var draw := ShaderMaterial.new()
	draw.shader = DRAW_SHADER
	draw.set_shader_parameter("shape", 2)
	draw.set_shader_parameter("use_custom_size", false)
	draw.set_shader_parameter("near_fade", 2.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.material = draw
	var p := GPUParticles3D.new()
	p.name = "Mist"
	p.amount = 90
	p.lifetime = 3.2
	p.preprocess = 3.0
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-width, -4, -8), Vector3(width * 2.0, 20, 24))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
