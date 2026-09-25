class_name EnvironmentFactory
extends RefCounted
## 按主题与画质创建 WorldEnvironment（天空、雾、色调映射、辉光、SSAO）和太阳光。

const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")

## 画质预设：阴影距离、SSAO、辉光、体积雾、MSAA、渲染缩放
const QUALITY := {
	"low": {"shadow_dist": 120.0, "shadow_size": 2048, "ssao": false, "glow": true, "volumetric": false, "msaa": Viewport.MSAA_DISABLED, "fxaa": true, "scale": 0.8, "terrain_cell": 8.0, "scenery": 0.4, "particles": 0.5},
	"medium": {"shadow_dist": 160.0, "shadow_size": 4096, "ssao": false, "glow": true, "volumetric": false, "msaa": Viewport.MSAA_2X, "fxaa": false, "scale": 1.0, "terrain_cell": 6.0, "scenery": 0.7, "particles": 0.8},
	"high": {"shadow_dist": 220.0, "shadow_size": 4096, "ssao": true, "glow": true, "volumetric": true, "msaa": Viewport.MSAA_2X, "fxaa": false, "scale": 1.0, "terrain_cell": 4.0, "scenery": 1.0, "particles": 1.0},
}


static func quality_preset(q: String) -> Dictionary:
	return QUALITY.get(q, QUALITY["high"])


## 返回 {"env": WorldEnvironment, "sun": DirectionalLight3D}，调用方负责加入场景树
static func create(theme: Dictionary, quality: String) -> Dictionary:
	var qp := quality_preset(quality)
	var night: bool = theme.get("night", false)
	var sunset: bool = theme.get("time", "day") == "sunset"

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", Color(theme["sky"]["top"]))
	sky_mat.set_shader_parameter("horizon_color", Color(theme["sky"]["horizon"]))
	sky_mat.set_shader_parameter("ground_color", Color(theme["ground"]["far"]).darkened(0.2))
	sky_mat.set_shader_parameter("sun_color", Color(theme["sky"]["sun"]))
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("cloud_amount", 0.0 if night else (0.55 if sunset else 0.42))
	sky_mat.set_shader_parameter("cloud_color", Color("#FFD2B0") if sunset else Color(1, 1, 1))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if night else Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(theme["light"]["ambient"])
	e.ambient_light_sky_contribution = 0.55
	e.ambient_light_energy = float(theme["light"]["ambient_energy"]) * 1.6
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0 if not night else 1.15
	e.tonemap_white = 6.0
	# 雾：按主题的起止距离做深度雾
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(theme["fog"]["color"])
	e.fog_depth_begin = float(theme["fog"]["near"])
	e.fog_depth_end = float(theme["fog"]["far"])
	e.fog_depth_curve = 1.4
	e.fog_sky_affect = 0.25
	e.fog_density = 1.0
	# 辉光
	e.glow_enabled = qp["glow"]
	e.glow_intensity = 0.9 if night else 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.05 if night else 0.02
	e.glow_hdr_threshold = 0.95 if night else 1.2
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.3)
	# SSAO
	e.ssao_enabled = qp["ssao"]
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssao_power = 1.4
	# 体积雾（夜城、森林）
	if qp["volumetric"] and (night or theme["id"] == "forest"):
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.012 if night else 0.006
		e.volumetric_fog_albedo = Color(theme["fog"]["color"])
		e.volumetric_fog_emission = Color(theme["fog"]["color"]) * (0.05 if night else 0.0)
		e.volumetric_fog_length = 140.0
		e.volumetric_fog_anisotropy = 0.4
		e.volumetric_fog_sky_affect = 0.0
	# 色彩调整：略微提饱和，卡通感更强
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18 if not night else 1.1
	e.adjustment_contrast = 1.06
	e.adjustment_brightness = 1.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = e

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var sd: Array = theme["light"]["sun_dir"]
	var dir := Vector3(sd[0], sd[1], sd[2]).normalized()
	sun.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = Color(theme["light"]["sun"])
	sun.light_energy = float(theme["light"]["sun_energy"])
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = qp["shadow_dist"]
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.light_angular_distance = 1.2
	return {"env": we, "sun": sun}


## 把画质设置应用到视口（MSAA、FXAA、缩放）
static func apply_viewport_quality(vp: Viewport, quality: String) -> void:
	var qp := quality_preset(quality)
	vp.msaa_3d = qp["msaa"]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if qp["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = qp["scale"]
	RenderingServer.directional_shadow_atlas_set_size(qp["shadow_size"], true)
