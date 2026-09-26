extends SceneTree
## 渲染应用图标：糖果色渐变底 + 3/4 视角的卡丁车特写，输出 1024×1024 的 assets/icon.png。
## godot --path . -s tests/tools/make_icon.gd

const SIZE := 1024


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(SIZE, SIZE))
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#D8ECFF")
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.2
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	vp.add_child(sun)
	var model := KartModel.create("bolt", "male-a", "oodi")
	model.rotation_degrees.y = 205.0
	vp.add_child(model)
	model.set_wheel_state(0.35, 0.0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(-4.1, 2.9, -6.4), Vector3(0.0, 0.8, 0.05))
	for i in 20:
		await process_frame
	var kart_img := vp.get_texture().get_image()
	kart_img.convert(Image.FORMAT_RGBA8)
	# 合成：圆角渐变底板 + 墨蓝描边 + 车
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var top := Color("#3EC6FF")
	var bottom := Color("#FFC93C")
	var ink := Color("#1B1F3B")
	var r := 200.0
	var m := 40.0
	for y in SIZE:
		for x in SIZE:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, m + r, SIZE - m - r)
			var cy := clampf(px.y, m + r, SIZE - m - r)
			var d := px.distance_to(Vector2(cx, cy)) - r
			if d > 0.5:
				continue
			var t := clampf((px.y - m) / (SIZE - 2.0 * m), 0.0, 1.0)
			var bg := top.lerp(Color("#9FE3FF"), t * 1.4) if t < 0.62 else Color("#9FE3FF").lerp(bottom, (t - 0.62) / 0.38)
			# 放射光芒
			var ang := atan2(px.y - SIZE * 0.55, px.x - SIZE * 0.5)
			if fposmod(ang * 6.0 / PI, 1.0) < 0.5:
				bg = bg.lightened(0.08)
			var col := bg
			# 车只画在描边以内
			var ky := y - 30
			if ky >= 0 and ky < SIZE:
				var kc := kart_img.get_pixel(x, ky)
				col = col.lerp(Color(kc.r, kc.g, kc.b), kc.a)
			if d > -26.0:
				col = ink
			col.a = clampf(0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, col)
	img.save_png("res://assets/icon.png")
	print("图标已保存 assets/icon.png")
	quit()
