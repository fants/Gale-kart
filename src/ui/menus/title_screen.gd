class_name TitleScreen
extends MenuPage
## 标题页：从天而降弹跳入场、轻轻浮动的大 Logo「疾风卡丁 / GALE KART」（生图艺术字），「按任意键开始」闪烁。

const LOGO_W := 840.0

var _logo: Control
var _logo_img: Control
var _tag: Label
var _press: Control
var _t := 0.0
var _accept_after := 0.7
var _done := false


func build() -> void:
	stage = "hero"
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 130
	col.offset_top = -400
	col.offset_right = 130 + 860
	col.offset_bottom = 400
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	# Logo：艺术字图片（没有图片时退回文字）
	_logo = Control.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_logo)
	var tex := UiArt.logo()
	if tex != null:
		var h := LOGO_W * tex.get_height() / tex.get_width()
		_logo.custom_minimum_size = Vector2(LOGO_W, h)
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		img.size = Vector2(LOGO_W, h)
		img.pivot_offset = Vector2(LOGO_W / 2.0, h / 2.0)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logo.add_child(img)
		_logo_img = img
	else:
		_logo.custom_minimum_size = Vector2(LOGO_W, 250)
		var l := Widgets.title("疾风卡丁", 210, UiTheme.SUN, false, 18)
		_logo.add_child(l)
		_logo_img = l

	_tag = Widgets.label("漂移 · 集气 · 氮气加速 —— 和 7 位对手一决高下！", 32, UiTheme.INK)
	_tag.add_theme_color_override("font_outline_color", UiTheme.CLOUD)
	_tag.add_theme_constant_override("outline_size", 10)
	col.add_child(_tag)

	# 按任意键开始（左栏 Logo 下方）
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 50)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	var press := Widgets.title("按任意键开始", 56, UiTheme.CLOUD, false, 12)
	bottom.add_child(press)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 10)
	keys.add_child(Widgets.keycap("Enter"))
	keys.add_child(Widgets.label("/", 22, UiTheme.INK_2))
	keys.add_child(Widgets.keycap("A", true))
	keys.add_child(Widgets.label("/", 22, UiTheme.INK_2))
	keys.add_child(Widgets.label("鼠标点击", 24, UiTheme.INK))
	bottom.add_child(keys)
	_press = bottom

	var ver := Widgets.label("GALE KART  ·  Godot 4.7  ·  v1.0", 20, Color(UiTheme.INK, 0.55), true)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -520
	ver.offset_top = -56
	ver.offset_right = -40
	ver.offset_bottom = -26
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	add_child(Widgets.pin(Widgets.creator_badge(1.3), Control.PRESET_BOTTOM_RIGHT, Vector2(40, 70)))


func on_enter() -> void:
	_t = 0.0
	# Logo 从天而降、弹跳落定
	var l := _logo_img
	l.modulate.a = 0.0
	l.position.y = -320.0
	l.rotation = -0.25
	l.scale = Vector2.ONE * 0.7
	var tw := l.create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(l, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(l, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "rotation", 0.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tag.modulate.a = 0.0
	var t3 := _tag.create_tween()
	t3.tween_interval(0.95)
	t3.tween_property(_tag, "modulate:a", 1.0, 0.4)
	_press.modulate.a = 0.0


func view_rect() -> Rect2:
	return Rect2(0.5, 0.12, 0.46, 0.78)


func _process(dt: float) -> void:
	_t += dt
	# 入场结束后轻轻浮动、摇摆
	if _t > 1.0:
		_logo_img.position.y = sin(_t * 2.0) * 8.0
		_logo_img.rotation = sin(_t * 1.3) * 0.02
		var pulse := 1.0 + 0.012 * sin(_t * 3.1)
		_logo_img.scale = Vector2(pulse, pulse)
	if _t > 1.2:
		_press.modulate.a = 0.55 + 0.45 * sin((_t - 1.2) * 4.0)


func _unhandled_input(ev: InputEvent) -> void:
	if _done or _t < _accept_after or root.busy:
		return
	var go := false
	if ev is InputEventKey and ev.is_pressed() and not ev.is_echo():
		go = true
	elif ev is InputEventMouseButton and ev.is_pressed():
		go = true
	elif ev is InputEventJoypadButton and ev.is_pressed():
		go = true
	if go:
		_done = true
		get_viewport().set_input_as_handled()
		AudioMgr.play("ui_confirm")
		root.push("main")


func on_resume() -> void:
	_done = false
	_t = 1.0
