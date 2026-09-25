class_name Curtain
extends CanvasLayer
## 全屏转场：多色斜向色带扫过盖住画面（cover），切换场景后再扫开（reveal）。

const WIPE_SHADER := preload("res://assets/shaders/ui_wipe.gdshader")

var rect: ColorRect
var mat: ShaderMaterial
var _tw: Tween


func _ready() -> void:
	layer = 60
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = WIPE_SHADER
	mat.set_shader_parameter("progress", 0.0)
	rect.material = mat
	rect.visible = false
	add_child(rect)


func _set_p(v: float) -> void:
	var vp := rect.get_viewport_rect().size
	mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	mat.set_shader_parameter("progress", v)


## 盖住画面；可 await
func cover(dur := 0.45) -> void:
	if _tw:
		_tw.kill()
	rect.visible = true
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_tw = create_tween()
	_tw.tween_method(_set_p, 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await _tw.finished


## 揭开画面
func reveal(dur := 0.5) -> void:
	if _tw:
		_tw.kill()
	rect.visible = true
	_tw = create_tween()
	_tw.tween_interval(0.05)
	_tw.tween_method(_set_p, 1.0, 2.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(func() -> void:
		rect.visible = false
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)
