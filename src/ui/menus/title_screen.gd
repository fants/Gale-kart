class_name TitleScreen
extends MenuPage
## 标题页：弹跳入场、逐字起伏的大 Logo「疾风卡丁 / GALE KART」，「按任意键开始」闪烁。

const LOGO := "疾风卡丁"
const CHAR_W := 188.0

var _chars: Array[Label] = []
var _logo: Control
var _en: Label
var _tag: Label
var _press: Control
var _t := 0.0
var _accept_after := 0.7
var _done := false


func build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 130
	col.offset_top = -400
	col.offset_right = 130 + 860
	col.offset_bottom = 400
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	# Logo：每个字单独一个 Label，手动排版（容器会复位旋转和缩放）
	_logo = Control.new()
	_logo.custom_minimum_size = Vector2(CHAR_W * LOGO.length() + 40, 250)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_logo)
	var colors: Array[Color] = [UiTheme.SUN, UiTheme.SUN, UiTheme.SUN, UiTheme.SUN]
	for i in LOGO.length():
		var l := Widgets.title(LOGO[i], 210, colors[i], false, 18)
		l.add_theme_constant_override("shadow_offset_y", 14)
		l.add_theme_constant_override("shadow_offset_x", 6)
		l.position = Vector2(i * CHAR_W, 0)
		l.size = Vector2(CHAR_W + 40, 250)
		l.pivot_offset = Vector2(CHAR_W / 2.0, 200)
		_logo.add_child(l)
		_chars.append(l)

	var en_wrap := Control.new()
	en_wrap.custom_minimum_size = Vector2(760, 96)
	en_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(en_wrap)
	_en = Widgets.title("G A L E   K A R T", 70, UiTheme.CLOUD, true, 12)
	_en.position = Vector2(14, 0)
	en_wrap.add_child(_en)

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


func on_enter() -> void:
	_t = 0.0
	# 逐字从天而降并弹跳
	for i in _chars.size():
		var l := _chars[i]
		l.modulate.a = 0.0
		l.position.y = -260.0
		l.rotation = randf_range(-0.4, 0.4)
		var tw := l.create_tween()
		tw.tween_interval(0.15 + i * 0.09)
		tw.tween_property(l, "modulate:a", 1.0, 0.1)
		tw.parallel().tween_property(l, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_logo.rotation = deg_to_rad(-4.0)
	_logo.pivot_offset = Vector2(0, 250)
	_en.modulate.a = 0.0
	_en.position.x = -120.0
	var t2 := _en.create_tween()
	t2.tween_interval(0.7)
	t2.tween_property(_en, "modulate:a", 1.0, 0.25)
	t2.parallel().tween_property(_en, "position:x", 14.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tag.modulate.a = 0.0
	var t3 := _tag.create_tween()
	t3.tween_interval(0.95)
	t3.tween_property(_tag, "modulate:a", 1.0, 0.4)
	_press.modulate.a = 0.0


func view_rect() -> Rect2:
	return Rect2(0.5, 0.12, 0.46, 0.78)


func _process(dt: float) -> void:
	_t += dt
	# 逐字起伏（入场结束后）
	if _t > 1.0:
		for i in _chars.size():
			var l := _chars[i]
			l.position.y = sin(_t * 2.2 + i * 0.75) * 9.0
			l.rotation = sin(_t * 1.6 + i * 1.1) * 0.035
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
