class_name SceneryProps
extends RefCounted
## 程序化地标与小物件（Godot 基础网格拼装，统一低多边形卡通风格）：
## 风车、红顶小屋、干草垛、金字塔、雪人、冰晶、热气球、起点拱门、路灯、霓虹招牌框、轮胎堆、花丛 / 草丛组合。

const PYRAMID_SHADER := preload("res://assets/shaders/pyramid.gdshader")
const FONT_CN := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const FONT_EN := preload("res://assets/fonts/Bungee-Regular.ttf")


# ———————————————— 基础形状 ————————————————

static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sphere(r: float, seg := 12, rings := 8) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


static func xf(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos)


# ———————————————— 村庄 ————————————————

## 风车：塔身 + 帽 + 门窗，叶轮节点（meta "hub"）在 update_view 里绕本地 Z 轴旋转。正面朝 +Z。
static func windmill(accent: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Windmill"
	var cream := SceneryLib.flat_mat(Color("#FFF4DE"))
	var red := SceneryLib.flat_mat(accent)
	var wood := SceneryLib.flat_mat(Color("#8E5F39"))
	var glass := SceneryLib.flat_mat(Color("#5DB6EA"), 0.0, 0.3)
	var body := MeshInstance3D.new()
	body.mesh = SceneryLib.merge([
		[cyl(1.7, 2.7, 11.0, 8), xf(Vector3(0, 5.5, 0)), cream],
		[cyl(3.0, 3.1, 0.6, 8), xf(Vector3(0, 0.3, 0)), wood],
		[cyl(2.35, 2.35, 0.35, 8), xf(Vector3(0, 7.4, 0)), red],
		[cyl(0.05, 2.3, 3.4, 8), xf(Vector3(0, 12.7, 0)), red],
		[box(Vector3(1.3, 2.3, 0.5)), xf(Vector3(0, 1.3, 2.5)), wood],
		[box(Vector3(0.8, 1.0, 0.4)), xf(Vector3(0, 4.6, 2.2)), glass],
		[box(Vector3(0.7, 0.9, 0.4)), xf(Vector3(0, 9.0, 1.85)), glass],
		[box(Vector3(0.8, 1.0, 0.4)), xf(Vector3(2.2, 4.0, 0), Vector3(0, PI / 2, 0)), glass],
	])
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)
	var hub := Node3D.new()
	hub.name = "Hub"
	hub.position = Vector3(0, 10.6, 2.25)
	var parts: Array = []
	for i in 4:
		var rot := Transform3D(Basis(Vector3.BACK, i * PI / 2.0), Vector3.ZERO)
		parts.append([box(Vector3(0.28, 7.0, 0.22)), rot * xf(Vector3(0, 3.6, 0)), wood])
		parts.append([box(Vector3(1.7, 5.6, 0.1)), rot * xf(Vector3(0.95, 4.0, 0.06)), cream])
		parts.append([box(Vector3(0.12, 5.6, 0.14)), rot * xf(Vector3(1.8, 4.0, 0.06)), red])
	parts.append([sphere(0.55, 10, 6), xf(Vector3(0, 0, 0.1)), red])
	var blades := MeshInstance3D.new()
	blades.mesh = SceneryLib.merge(parts)
	blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	hub.add_child(blades)
	root.add_child(hub)
	root.set_meta("hub", hub)
	return root


## 小屋：墙身 + 三角屋顶 + 门窗烟囱。正面（门）朝 +Z。冰雪主题屋顶积雪
static func house_mesh(theme_id: String, wall: Color, roof_color: Color) -> ArrayMesh:
	var walls := SceneryLib.themed_mat(theme_id, wall, 0.0)
	var roof := SceneryLib.themed_mat(theme_id, roof_color, 1.0)
	var wood := SceneryLib.flat_mat(Color("#8E5F39"))
	var stone := SceneryLib.themed_mat(theme_id, Color("#B9B2A8"), 0.6)
	var glass := SceneryLib.flat_mat(Color("#8FD3FF"), 0.35, 0.3)
	var roof_prism := PrismMesh.new()
	roof_prism.size = Vector3(6.0, 2.6, 7.0)
	var parts: Array = [
		[box(Vector3(6.0, 4.0, 5.0)), xf(Vector3(0, 2.0, 0)), walls],
		[box(Vector3(6.4, 0.5, 5.4)), xf(Vector3(0, 0.25, 0)), stone],
		[roof_prism, xf(Vector3(0, 5.3, 0), Vector3(0, PI / 2, 0)), roof],
		[box(Vector3(0.8, 2.0, 0.8)), xf(Vector3(1.7, 5.6, -0.9)), stone],
		[box(Vector3(1.2, 2.2, 0.2)), xf(Vector3(0, 1.1, 2.52)), wood],
	]
	for wx: float in [-1.9, 1.9]:
		parts.append([box(Vector3(1.1, 1.1, 0.16)), xf(Vector3(wx, 2.5, 2.52)), glass])
		parts.append([box(Vector3(1.1, 1.1, 0.16)), xf(Vector3(wx, 2.5, -2.52)), glass])
		parts.append([box(Vector3(1.3, 0.18, 0.3)), xf(Vector3(wx, 1.9, 2.6)), wood])
	for sx: float in [-3.02, 3.02]:
		parts.append([box(Vector3(0.16, 1.1, 1.1)), xf(Vector3(sx, 2.5, 0)), glass])
	return SceneryLib.merge(parts)


## 干草垛（横躺的圆柱），实例色控制深浅
static func hay_mesh() -> ArrayMesh:
	var hay := SceneryLib.flat_mat(Color(1, 1, 1), 0.0, 0.95, true)
	var band := SceneryLib.flat_mat(Color("#C98E2E"))
	return SceneryLib.merge([
		[cyl(1.1, 1.1, 1.6, 12), xf(Vector3(0, 1.1, 0), Vector3(0, 0, PI / 2)), hay],
		[cyl(1.13, 1.13, 0.12, 12), xf(Vector3(0.4, 1.1, 0), Vector3(0, 0, PI / 2)), band],
		[cyl(1.13, 1.13, 0.12, 12), xf(Vector3(-0.4, 1.1, 0), Vector3(0, 0, PI / 2)), band],
	])


## 热气球：条纹气囊（小贴图条纹）+ 吊篮
static func balloon(colors: Array[Color]) -> Node3D:
	var root := Node3D.new()
	root.name = "Balloon"
	var img := Image.create(12, 1, false, Image.FORMAT_RGBA8)
	for i in 12:
		img.set_pixel(i, 0, colors[i % colors.size()])
	var tex := ImageTexture.create_from_image(img)
	var env_mat := StandardMaterial3D.new()
	env_mat.albedo_texture = tex
	env_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	env_mat.roughness = 0.8
	var env := MeshInstance3D.new()
	env.mesh = sphere(5.0, 12, 10)
	env.material_override = env_mat
	env.scale = Vector3(1, 1.2, 1)
	env.position = Vector3(0, 8.0, 0)
	env.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(env)
	var wood := SceneryLib.flat_mat(Color("#8E5F39"))
	var rope := SceneryLib.flat_mat(Color("#5E4A3A"))
	var parts: Array = [[box(Vector3(1.8, 1.4, 1.8)), xf(Vector3(0, 0.7, 0)), wood]]
	for c: Vector2 in [Vector2(0.8, 0.8), Vector2(-0.8, 0.8), Vector2(0.8, -0.8), Vector2(-0.8, -0.8)]:
		parts.append([cyl(0.04, 0.04, 3.4), xf(Vector3(c.x * 1.4, 3.0, c.y * 1.4), Vector3(c.y * 0.25, 0, -c.x * 0.25)), rope])
	var basket := MeshInstance3D.new()
	basket.mesh = SceneryLib.merge(parts)
	basket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(basket)
	return root


# ———————————————— 沙漠 ————————————————

## 金字塔（底面 ±1、高 1，按实例缩放）；着色器画石块层与金色塔尖
static func pyramid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(0, 1, 0)
	var c := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var nrm := (b - a).cross(apex - a).normalized()
		if nrm.dot(a + b) < 0.0:
			nrm = -nrm
		# Godot 以顺时针为正面：从外面看 a → b → 塔尖 为顺时针
		for v: Vector3 in [a, b, apex]:
			st.set_normal(nrm)
			st.set_uv(Vector2(v.x * 0.5 + 0.5, v.y))
			st.add_vertex(v)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = PYRAMID_SHADER
	mesh.surface_set_material(0, mat)
	return mesh


# ———————————————— 冰雪 ————————————————

## 雪人：三个雪球 + 礼帽 + 胡萝卜鼻 + 围巾 + 树枝手臂。正面朝 +Z
static func snowman_mesh() -> ArrayMesh:
	var snow := SceneryLib.flat_mat(Color("#F7FBFF"), 0.0, 0.7)
	var black := SceneryLib.flat_mat(Color("#1E2233"))
	var carrot := SceneryLib.flat_mat(Color("#FF8A2A"))
	var scarf := SceneryLib.flat_mat(Color("#FF4D5E"))
	var stick := SceneryLib.flat_mat(Color("#6B4A33"))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.78
	torus.rings = 12
	torus.ring_segments = 6
	var parts: Array = [
		[sphere(1.25, 14, 9), xf(Vector3(0, 1.1, 0)), snow],
		[sphere(0.9, 14, 9), xf(Vector3(0, 2.7, 0)), snow],
		[sphere(0.62, 12, 8), xf(Vector3(0, 3.85, 0)), snow],
		[cyl(0.46, 0.46, 0.75, 12), xf(Vector3(0, 4.75, 0)), black],
		[cyl(0.75, 0.75, 0.08, 12), xf(Vector3(0, 4.4, 0)), black],
		[cyl(0.47, 0.47, 0.14, 12), xf(Vector3(0, 4.5, 0)), scarf],
		[cyl(0.0, 0.13, 0.7, 8), xf(Vector3(0, 3.85, 0.85), Vector3(PI / 2, 0, 0)), carrot],
		[torus, xf(Vector3(0, 3.28, 0)), scarf],
		[box(Vector3(0.28, 0.9, 0.1)), xf(Vector3(0.35, 2.95, 0.72), Vector3(0.3, 0, 0.2)), scarf],
		[cyl(0.05, 0.07, 1.8, 5), xf(Vector3(1.4, 3.0, 0), Vector3(0, 0, 1.0)), stick],
		[cyl(0.05, 0.07, 1.8, 5), xf(Vector3(-1.4, 3.0, 0), Vector3(0, 0, -1.0)), stick],
	]
	for e: float in [-0.22, 0.22]:
		parts.append([sphere(0.08, 6, 4), xf(Vector3(e, 4.0, 0.55)), black])
	for b: float in [2.45, 2.85]:
		parts.append([sphere(0.1, 6, 4), xf(Vector3(0, b, 0.88)), black])
	return SceneryLib.merge(parts)


## 冰屋：半球穹顶 + 半埋的拱形入口 + 冰砖接缝
static func igloo_mesh() -> ArrayMesh:
	var snow := SceneryLib.flat_mat(Color("#EEF6FF"), 0.0, 0.6)
	var seam := SceneryLib.flat_mat(Color("#C9DDF2"), 0.0, 0.6)
	var dark := SceneryLib.flat_mat(Color("#2A3450"))
	var dome := sphere(3.2, 16, 6)
	dome.height = 3.2
	dome.is_hemisphere = true
	var parts: Array = [
		[dome, xf(Vector3.ZERO), snow],
		[cyl(1.35, 1.35, 2.8, 12), xf(Vector3(0, 0, 3.0), Vector3(PI / 2, 0, 0)), snow],
		[box(Vector3(1.1, 1.2, 0.2)), xf(Vector3(0, 0.45, 4.35)), dark],
	]
	for h: float in [0.8, 1.6, 2.3, 2.85]:
		var r := sqrt(3.2 * 3.2 - h * h) + 0.03
		parts.append([cyl(r, r, 0.07, 16), xf(Vector3(0, h, 0)), seam])
	return SceneryLib.merge(parts)


## 冰晶簇：几根六棱尖柱向外倾斜，自发光冰蓝
static func crystal_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#9FE6FF")
	mat.roughness = 0.08
	mat.metallic = 0.2
	mat.metallic_specular = 0.9
	mat.emission_enabled = true
	mat.emission = Color("#6FD2FF")
	mat.emission_energy_multiplier = 1.6
	mat.rim_enabled = true
	mat.rim = 0.6
	var parts: Array = []
	var n := 5
	for i in n:
		var h := 2.2 + rng.randf() * 2.6 if i > 0 else 5.2
		var r := 0.35 + rng.randf() * 0.25 if i > 0 else 0.6
		var a := TAU * i / n + rng.randf() * 0.5
		var tilt := 0.0 if i == 0 else 0.3 + rng.randf() * 0.35
		var base := Vector3(cos(a), 0, sin(a)) * (0.0 if i == 0 else 0.7)
		var bas := Basis(Vector3(-sin(a), 0, cos(a)), tilt) if i > 0 else Basis()
		parts.append([cyl(r, r * 0.9, h, 6), Transform3D(bas, base) * xf(Vector3(0, h * 0.5 - 0.3, 0)), mat])
		parts.append([cyl(0.0, r, h * 0.35, 6), Transform3D(bas, base) * xf(Vector3(0, h - 0.3 + h * 0.175, 0)), mat])
	return SceneryLib.merge(parts)


# ———————————————— 通用 ————————————————

## 花丛：几朵不同颜色的 Kenney 花拼成一簇（减少实例数）
static func flower_patch(theme_id: String, names: Array, rng: RandomNumberGenerator, count := 7, radius := 1.6, scale := 5.0) -> ArrayMesh:
	var parts: Array = []
	for i in count:
		var nm: String = names[rng.randi() % names.size()]
		var m: Dictionary = SceneryLib.model(theme_id, SceneryLib.NATURE + nm + ".glb")
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var s := scale * (0.8 + rng.randf() * 0.45)
		parts.append([m["mesh"], xf(Vector3(cos(a) * d, 0, sin(a) * d), Vector3(0, rng.randf() * TAU, 0), Vector3(s, s, s)), null])
	return SceneryLib.merge(parts)


## 起点拱门：两根柱子（护墙外侧）+ 横梁 + 「START」「疾风卡丁」字样。本地 +Z = 赛道前进方向，原点在路面中心
static func start_arch(track: TrackData, theme: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "StartArch"
	var night: bool = theme.get("night", false)
	var theme_id: String = ThemesData.base_of(theme)
	var span := track.wall_offset + 2.2
	var accent := Color(theme["curb"][0])
	var pillar_col := Color(theme["wall"]["a"])
	var beam_col := Color("#1B1F3B") if night else accent
	match theme_id:
		"desert":
			pillar_col = Color("#E8C48A")
		"forest":
			pillar_col = Color("#8A5A34")
		"snow":
			pillar_col = Color("#CFEFFF")
	var pillar := SceneryLib.themed_mat(theme_id, pillar_col, 0.8)
	var beam := SceneryLib.themed_mat(theme_id, beam_col, 0.8)
	var trim := SceneryLib.flat_mat(Color(theme["wall"]["b"]), 1.2 if night else 0.0)
	var dark := SceneryLib.flat_mat(Color("#1B1F3B"))
	var h := 8.5
	var parts: Array = []
	for sd: float in [-1.0, 1.0]:
		var x := sd * span
		parts.append([box(Vector3(1.8, h, 1.8)), xf(Vector3(x, h * 0.5 - 1.0, 0)), pillar])
		parts.append([box(Vector3(2.4, 0.8, 2.4)), xf(Vector3(x, -0.2, 0)), dark])
		parts.append([box(Vector3(2.0, 0.35, 2.0)), xf(Vector3(x, h * 0.55, 0)), trim])
		parts.append([sphere(0.7, 10, 6), xf(Vector3(x, h + 1.4, 0)), trim])
	parts.append([box(Vector3(span * 2.0 + 2.6, 2.6, 1.4)), xf(Vector3(0, h + 0.3, 0)), beam])
	parts.append([box(Vector3(span * 2.0 + 2.8, 0.3, 1.6)), xf(Vector3(0, h - 1.1, 0)), trim])
	parts.append([box(Vector3(span * 2.0 + 2.8, 0.3, 1.6)), xf(Vector3(0, h + 1.7, 0)), trim])
	# 顶部标牌（有 Logo 图片时改为立在横梁上的艺术字剪影）
	var logo := UiArt.logo()
	if logo == null:
		parts.append([box(Vector3(12.0, 3.2, 0.9)), xf(Vector3(0, h + 3.3, 0)), dark])
		parts.append([box(Vector3(12.4, 0.25, 1.0)), xf(Vector3(0, h + 4.95, 0)), trim])
		parts.append([box(Vector3(12.4, 0.25, 1.0)), xf(Vector3(0, h + 1.75, 0)), trim])
	var mi := MeshInstance3D.new()
	mi.mesh = SceneryLib.merge(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	# 文字：两面各一份（单面显示，避免背面镜像）
	for face: float in [-1.0, 1.0]:
		var yaw := PI if face < 0.0 else 0.0
		var z := face * 0.72
		root.add_child(label("START", FONT_EN, 220, Color(1, 1, 1), Vector3(0, h + 0.3, z), yaw, 0.012))
		if logo == null:
			root.add_child(label("疾风卡丁", FONT_CN, 200, Color("#FFD84A"), Vector3(0, h + 3.35, face * 0.47), yaw, 0.0115))
			continue
		var sp := Sprite3D.new()
		sp.texture = logo
		sp.pixel_size = 11.0 / logo.get_width()
		sp.shaded = false
		sp.double_sided = false
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sp.position = Vector3(0, h + 1.6 + 11.0 * logo.get_height() / logo.get_width() * 0.5, face * 0.05)
		sp.rotation.y = yaw
		root.add_child(sp)
	return root


## Label3D 工具（单面，不受光照）
static func label(text: String, font: Font, size: int, color: Color, pos: Vector3, yaw: float, pixel := 0.01, outline := 18) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = outline
	l.outline_modulate = Color("#1B1F3B")
	l.position = pos
	l.rotation = Vector3(0, yaw, 0)
	l.double_sided = false
	l.shaded = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


## 轮胎堆（4 个叠起来，顶上一圈红白涂装）
static func tire_stack_mesh() -> ArrayMesh:
	var rubber := SceneryLib.flat_mat(Color("#23252C"), 0.0, 0.9)
	var paint := SceneryLib.flat_mat(Color(1, 1, 1), 0.0, 0.8, true)
	var parts: Array = []
	for i in 4:
		parts.append([cyl(0.55, 0.55, 0.36, 12), xf(Vector3(0, 0.18 + i * 0.37, 0)), rubber])
	parts.append([cyl(0.56, 0.56, 0.12, 12), xf(Vector3(0, 0.18 + 3 * 0.37 + 0.1, 0)), paint])
	parts.append([cyl(0.3, 0.3, 0.02, 10), xf(Vector3(0, 1.55, 0)), SceneryLib.flat_mat(Color("#0E0F12"))])
	return SceneryLib.merge(parts)


## 路灯：灯杆 + 横臂 + 发光灯头（灯头在本地 (0, 7.3, 2.3)，朝 +Z 伸出）
static func lamp_mesh(head_color: Color) -> ArrayMesh:
	var pole := SceneryLib.flat_mat(Color("#3A3E58"), 0.0, 0.5)
	var head := SceneryLib.flat_mat(head_color, 6.0)
	return SceneryLib.merge([
		[cyl(0.14, 0.2, 7.6, 8), xf(Vector3(0, 3.8, 0)), pole],
		[box(Vector3(0.2, 0.2, 2.7)), xf(Vector3(0, 7.5, 1.2)), pole],
		[box(Vector3(0.5, 0.5, 0.5)), xf(Vector3(0, 0.25, 0)), pole],
		[box(Vector3(0.9, 0.3, 1.5)), xf(Vector3(0, 7.55, 2.3)), pole],
		[box(Vector3(0.75, 0.12, 1.3)), xf(Vector3(0, 7.36, 2.3)), head],
	])
