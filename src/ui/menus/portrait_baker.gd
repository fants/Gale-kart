class_name PortraitBaker
extends Node
## 车手头像：12 个 Mini Character 放在同一个独立 3D 世界里，每人一个透明背景的 SubViewport
## 用正交相机拍一次头像，读回为 ImageTexture 缓存（整个游戏只烘焙一次）。

signal baked

const CELL := 192
const SPACING := 3.0

static var textures: Dictionary = {}
static var _instance: PortraitBaker = null


## 需要头像时调用：已有缓存或无界面模式返回 null，否则返回正在烘焙的节点（等待 baked 信号）
static func ensure(host: Node) -> PortraitBaker:
	if not textures.is_empty() or DisplayServer.get_name() == "headless":
		return null
	if _instance == null or not is_instance_valid(_instance):
		_instance = PortraitBaker.new()
		host.get_tree().root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	name = "PortraitBaker"
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#EAF4FF")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	var views: Array[SubViewport] = []
	var ids: Array[String] = []
	for i in KartsData.CHARACTERS.size():
		var ch: Dictionary = KartsData.CHARACTERS[i]
		var sv := SubViewport.new()
		sv.size = Vector2i(CELL, CELL)
		sv.transparent_bg = true
		sv.world_3d = world
		sv.msaa_3d = Viewport.MSAA_4X
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(sv)
		var x := i * SPACING
		var model: Node3D = (load("res://assets/models/characters/%s.glb" % ch["model"]) as PackedScene).instantiate()
		model.position = Vector3(x, 0, 0)
		model.rotation.y = 0.32
		sv.add_child(model)
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("idle"):
			ap.play("idle")
			ap.seek(0.35, true)
			ap.pause()
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.5
		sv.add_child(cam)
		cam.look_at_from_position(Vector3(x + 0.03, 0.62, 3.0), Vector3(x, 0.5, 0.0))
		cam.current = true
		if i == 0:
			var key := DirectionalLight3D.new()
			key.light_color = Color("#FFF3E0")
			key.light_energy = 1.1
			sv.add_child(key)
			key.look_at_from_position(Vector3(2, 4, 5), Vector3.ZERO)
			var rim := DirectionalLight3D.new()
			rim.light_color = Color("#FF9FE0")
			rim.light_energy = 0.5
			sv.add_child(rim)
			rim.look_at_from_position(Vector3(-4, 2, -3), Vector3.ZERO)
		views.append(sv)
		ids.append(str(ch["id"]))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for i in views.size():
		var img := views[i].get_texture().get_image()
		textures[ids[i]] = ImageTexture.create_from_image(img)
	baked.emit()
	queue_free()


## 头像控件：代表色圆牌 + 头像（未烘焙完成时显示名字首字）
class Avatar extends Control:
	var cid := ""
	var color := UiTheme.SUN
	var tex: Texture2D = null
	var initial := ""

	func _init(p_cid: String, d := 96.0) -> void:
		cid = p_cid
		var ch := KartsData.character_by_id(p_cid)
		color = Color(str(ch["color"]))
		initial = str(ch["name"]).substr(0, 1)
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex = PortraitBaker.textures.get(cid)
		if tex == null:
			var tree := Engine.get_main_loop() as SceneTree
			var b := PortraitBaker.ensure(tree.root) if tree else null
			if b:
				b.baked.connect(_on_baked)

	func _on_baked() -> void:
		tex = PortraitBaker.textures.get(cid)
		queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var c := size / 2.0
		draw_circle(c, r, UiTheme.INK)
		draw_circle(c, r - 3.0, color)
		draw_circle(c + Vector2(0, r * 0.35), r * 0.62, color.lightened(0.25))
		if tex:
			var s := r * 2.1
			draw_texture_rect(tex, Rect2(c - Vector2(s, s) / 2.0 + Vector2(0, -r * 0.06), Vector2(s, s)), false)
		else:
			var f := UiTheme.font_cn()
			var fs := int(r * 0.9)
			var w := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-w / 2.0, fs * 0.35), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.INK)
		draw_arc(c, r - 1.5, 0.0, TAU, 64, UiTheme.INK, 3.0, true)
