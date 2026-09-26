class_name HeroBackdrop
extends CanvasLayer
## 首页（标题 / 主菜单及其弹出页）的大图背景：几位车手飙车的特写插画（生图），盖在 3D 舞台之上、菜单之下。
## 每次启动随机选一张；显示 / 隐藏带淡入淡出，下面的车库舞台可以同时出现。

const ARTS: Array[String] = ["sunny", "forest", "sunset", "jump"]
const FADE := 0.35

var rect: ColorRect
var _tw: Tween
var shown := false


func _ready() -> void:
	layer = 1
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = load("res://assets/ui/hero/%s.jpg" % ARTS[randi() % ARTS.size()])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/ui_hero.gdshader")
	mat.set_shader_parameter("art", tex)
	mat.set_shader_parameter("art_aspect", float(tex.get_width()) / tex.get_height())
	rect.material = mat
	rect.modulate.a = 0.0
	add_child(rect)
	visible = false


## on：淡入 / 淡出；instant：直接切换（首次打开）；done：淡入结束后的回调
func set_shown(on: bool, instant := false, done := Callable()) -> void:
	if on == shown and not instant:
		return
	shown = on
	if _tw:
		_tw.kill()
	if on:
		visible = true
	if instant:
		rect.modulate.a = 1.0 if on else 0.0
		visible = on
		if done.is_valid():
			done.call()
		return
	_tw = create_tween()
	_tw.tween_property(rect, "modulate:a", 1.0 if on else 0.0, FADE)
	_tw.tween_callback(func() -> void:
		visible = on
		if done.is_valid():
			done.call())
