class_name Widgets
extends RefCounted
## 糖果贴纸风控件工厂：面板、按钮、图标按钮、六维属性条、徽章、星级、分段选择、卡片、开关、
## 键帽、操作提示条、赛道线稿缩略图、奖杯。所有按钮悬停 / 聚焦时放大 1.05 并变亮（Tween）。

const INK := UiTheme.INK

## 程序性聚焦（打开页面时自动聚焦）期间不播放悬停音
static var quiet_until_ms := 0

## 赛道缩略图的采样点缓存：track_id → PackedVector2Array（x, z）
static var _track_pts: Dictionary = {}
static var _track_task := -1


# ———————————————————————— 按钮 ————————————————————————

## 悬停 / 聚焦时弹性放大并变亮，按下时压扁；鼠标移入即获得焦点（键鼠手柄统一高亮）
class PopButton extends Button:
	var pop := 1.05
	var click_sound := "ui_click"
	var _tw: Tween
	var _hot := false
	var _down := false

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _ready() -> void:
		_update_pivot()
		resized.connect(_update_pivot)
		focus_entered.connect(_set_hot.bind(true))
		focus_exited.connect(_set_hot.bind(false))
		mouse_entered.connect(_on_mouse_entered)
		button_down.connect(_on_down)
		button_up.connect(_on_up)
		pressed.connect(_on_pressed)
		set_process(false)

	func _update_pivot() -> void:
		pivot_offset = size / 2.0

	func _on_mouse_entered() -> void:
		if not disabled and focus_mode != Control.FOCUS_NONE and is_visible_in_tree():
			grab_focus()

	func _set_hot(on: bool) -> void:
		_hot = on
		if on:
			add_theme_stylebox_override("normal", get_theme_stylebox("hover"))
			add_theme_stylebox_override("pressed", get_theme_stylebox("hover_pressed"))
			if Time.get_ticks_msec() > Widgets.quiet_until_ms:
				AudioMgr.play("ui_hover")
		else:
			remove_theme_stylebox_override("normal")
			remove_theme_stylebox_override("pressed")
		_tween_to(pop if on else 1.0, 0.2)
		set_process(on)

	func _on_down() -> void:
		_down = true
		_tween_to(0.94, 0.06)

	func _on_up() -> void:
		_down = false
		_tween_to(pop if _hot else 1.0, 0.22)

	func _on_pressed() -> void:
		if click_sound != "":
			AudioMgr.play(click_sound)

	func _tween_to(s: float, dur: float) -> void:
		if _tw:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_property(self, "scale", Vector2.ONE * s, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	## 容器重新排版会把 scale 复位为 1：聚焦期间守住放大状态
	func _process(_dt: float) -> void:
		if _hot and not _down and (_tw == null or not _tw.is_running()) and not scale.is_equal_approx(Vector2.ONE * pop):
			scale = Vector2.ONE * pop


## 开关：自绘药丸形拨动开关
class ToggleSwitch extends PopButton:
	var knob := 0.0
	var _ktw: Tween

	func _init() -> void:
		super()
		toggle_mode = true
		theme_type_variation = "SwitchButton"
		custom_minimum_size = Vector2(116, 58)
		toggled.connect(_on_toggled)

	func set_on(on: bool) -> void:
		set_pressed_no_signal(on)
		knob = 1.0 if on else 0.0
		queue_redraw()

	func _on_toggled(on: bool) -> void:
		if _ktw:
			_ktw.kill()
		_ktw = create_tween()
		_ktw.tween_method(_set_knob, knob, 1.0 if on else 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _set_knob(v: float) -> void:
		knob = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 12))
		var h := r.size.y
		var col := UiTheme.GRAY.lerp(UiTheme.MINT, clampf(knob, 0.0, 1.0))
		var sb := UiTheme.box(col, int(h / 2.0), 3, INK, 4)
		draw_style_box(sb, r)
		var kx := lerpf(r.position.x + h / 2.0, r.end.x - h / 2.0, knob)
		var c := Vector2(kx, r.position.y + h / 2.0)
		draw_circle(c, h / 2.0 - 7.0, UiTheme.WHITE)
		draw_arc(c, h / 2.0 - 7.0, 0.0, TAU, 40, INK, 3.0, true)
		var f := UiTheme.font_cn()
		var txt := "开" if button_pressed else "关"
		var tx := r.position.x + 14.0 if button_pressed else r.end.x - 38.0
		draw_string(f, Vector2(tx, c.y + 9.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(INK, 0.75))


# ———————————————————————— 自绘小控件 ————————————————————————

## 矢量图标（贴纸风：墨线描边）
class Icon extends Control:
	var kind := ""
	var fill := UiTheme.SUN

	func _init(p_kind := "", p_size := 48.0, p_fill := UiTheme.SUN) -> void:
		kind = p_kind
		fill = p_fill
		custom_minimum_size = Vector2(p_size, p_size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		Widgets.draw_icon(self, kind, Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s)), fill)


## 六维属性条：标签 + 5 格（数值变化时平滑填充）
class StatBar extends Control:
	var label := ""
	var shown := 0.0
	var target := 0
	var max_v := 5
	var label_w := 84.0
	var _tw: Tween

	func _init(p_label := "", value := 0) -> void:
		label = p_label
		target = value
		shown = float(value)
		custom_minimum_size = Vector2(300, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int, animate := true) -> void:
		target = v
		if _tw:
			_tw.kill()
		if not animate or not is_inside_tree():
			shown = float(v)
			queue_redraw()
			return
		_tw = create_tween()
		_tw.tween_method(_set_shown, shown, float(v), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _set_shown(v: float) -> void:
		shown = v
		queue_redraw()

	func _draw() -> void:
		var f := UiTheme.font_cn()
		var h := size.y
		draw_string(f, Vector2(0, h / 2.0 + 9.0), label, HORIZONTAL_ALIGNMENT_LEFT, label_w, 24, UiTheme.INK_2)
		var x0 := label_w
		var num_w := 34.0
		var gap := 6.0
		var seg_w := (size.x - x0 - num_w - gap * max_v) / max_v
		var seg_h := minf(20.0, h - 8.0)
		var y := (h - seg_h) / 2.0
		var fill_col := UiTheme.RED if target >= 5 else UiTheme.MINT
		for i in max_v:
			var r := Rect2(x0 + i * (seg_w + gap), y, seg_w, seg_h)
			draw_style_box(UiTheme.box(UiTheme.WHITE, 6, 0, INK, 0), r)
			var fr := clampf(shown - i, 0.0, 1.0)
			if fr > 0.0:
				draw_style_box(UiTheme.box(fill_col, 6, 0, INK, 0), Rect2(r.position, Vector2(r.size.x * fr, r.size.y)))
			draw_style_box(_outline(), r)
		var nf := UiTheme.font_num()
		draw_string(nf, Vector2(size.x - num_w + 8.0, h / 2.0 + 10.0), str(target), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)

	func _outline() -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.draw_center = false
		s.set_border_width_all(3)
		s.border_color = INK
		s.set_corner_radius_all(6)
		s.anti_aliasing = true
		return s


## 星级（实心阳光黄 + 空心）
class StarRating extends Control:
	var value := 0
	var max_v := 3
	var star := 26.0

	func _init(v := 0, p_max := 3, p_size := 26.0) -> void:
		value = v
		max_v = p_max
		star = p_size
		custom_minimum_size = Vector2(p_max * (p_size + 4.0), p_size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in max_v:
			var c := Vector2(i * (star + 4.0) + star / 2.0, size.y / 2.0)
			Widgets.draw_star(self, c, star / 2.0, UiTheme.SUN if i < value else Color(UiTheme.WHITE, 0.9), 2.5)


## 赛道线稿（TrackData 采样点）；progress < 1 时只画出一部分，加载页用来表示进度
class TrackThumb extends Control:
	var track_id := ""
	var progress := 1.0
	var line_color := UiTheme.WHITE
	var bg_color := Color(0, 0, 0, 0)
	var line_w := 7.0
	var pad := 14.0
	var show_start := true

	func _init(id := "") -> void:
		track_id = id
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(160, 100)
		resized.connect(queue_redraw)

	func _draw() -> void:
		if bg_color.a > 0.0:
			draw_style_box(UiTheme.box(bg_color, 14, 0, INK, 0), Rect2(Vector2.ZERO, size))
		var pts := Widgets.track_points(track_id)
		if pts.size() < 3:
			return
		var mn := pts[0]
		var mx := pts[0]
		for p in pts:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		var ext := mx - mn
		var avail := size - Vector2(pad, pad) * 2.0
		# 赛道形状与控件朝向不一致时旋转 90°，尽量填满
		var rot := (ext.y > ext.x) != (avail.y > avail.x)
		var e2 := Vector2(ext.y, ext.x) if rot else ext
		var k := minf(avail.x / maxf(e2.x, 1.0), avail.y / maxf(e2.y, 1.0))
		var off := (size - e2 * k) / 2.0
		var n := pts.size()
		var count := clampi(int(ceil(n * progress)), 0, n)
		var line := PackedVector2Array()
		for i in count:
			var p := pts[i]
			var q := Vector2(p.x - mn.x, mx.y - p.y)
			if rot:
				q = Vector2(mx.y - p.y, mx.x - p.x)
			line.append(off + q * k)
		if progress >= 1.0:
			line.append(line[0])
		if line.size() >= 2:
			draw_polyline(line, INK, line_w + 7.0, true)
			draw_polyline(line, line_color, line_w, true)
		if show_start and line.size() > 0:
			var s0 := line[0]
			draw_circle(s0, line_w * 0.9 + 3.0, INK)
			draw_circle(s0, line_w * 0.9, UiTheme.SUN)
		if progress < 1.0 and line.size() > 0:
			var head := line[line.size() - 1]
			draw_circle(head, line_w + 5.0, INK)
			draw_circle(head, line_w + 2.0, UiTheme.RED)


## 奖杯（金 / 银 / 铜），带高光扫过动画
class Trophy extends Control:
	var cup := UiTheme.GOLD
	var shine := 0.0

	func _init(color := UiTheme.GOLD) -> void:
		cup = color
		custom_minimum_size = Vector2(220, 240)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		shine = fmod(shine + dt * 0.45, 1.6)
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x / 220.0, size.y / 240.0)
		var o := (size - Vector2(220, 240) * s) / 2.0
		var tf := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
		var w := 4.0 * s
		var dark := cup.darkened(0.25)
		# 把手
		for side: float in [-1.0, 1.0]:
			var c: Vector2 = tf.call(110.0 + side * 70.0, 72.0)
			draw_arc(c, 26.0 * s, 0.0, TAU, 40, INK, 16.0 * s, true)
			draw_arc(c, 26.0 * s, 0.0, TAU, 40, cup, 9.0 * s, true)
		# 杯身
		var bowl := PackedVector2Array()
		bowl.append(tf.call(40.0, 30.0))
		bowl.append(tf.call(180.0, 30.0))
		for i in range(0, 13):
			var a := PI * float(i) / 12.0
			bowl.append(tf.call(110.0 + cos(a) * 70.0, 96.0 + sin(a) * 58.0))
		Widgets.draw_shape(self, bowl, cup, w)
		# 杯口
		Widgets.draw_shape(self, Widgets.rect_pts(tf.call(30.0, 20.0), tf.call(190.0, 38.0)), cup.lightened(0.2), w)
		# 杯柄与底座
		Widgets.draw_shape(self, Widgets.rect_pts(tf.call(96.0, 152.0), tf.call(124.0, 184.0)), dark, w)
		Widgets.draw_shape(self, Widgets.rect_pts(tf.call(70.0, 184.0), tf.call(150.0, 200.0)), cup, w)
		Widgets.draw_shape(self, Widgets.rect_pts(tf.call(52.0, 200.0), tf.call(168.0, 228.0)), dark, w)
		# 星星
		Widgets.draw_star(self, tf.call(110.0, 88.0), 30.0 * s, UiTheme.WHITE, w * 0.8)
		# 高光扫过
		var sx := lerpf(20.0, 220.0, shine)
		if shine < 1.0:
			var band := PackedVector2Array([tf.call(sx, 34.0), tf.call(sx + 22.0, 34.0), tf.call(sx - 18.0, 150.0), tf.call(sx - 40.0, 150.0)])
			var clip := Geometry2D.intersect_polygons(band, bowl)
			for poly in clip:
				draw_colored_polygon(poly, Color(1, 1, 1, 0.55))


# ———————————————————————— 工厂函数 ————————————————————————

static func panel(variation := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


## kind：normal / primary / danger / chip / card / icon / tab
static func button(text: String, kind := "normal", icon := "", icon_fill := UiTheme.SUN) -> PopButton:
	var b := PopButton.new()
	b.text = text
	match kind:
		"primary":
			b.theme_type_variation = "PrimaryButton"
		"danger":
			b.theme_type_variation = "DangerButton"
		"chip":
			b.theme_type_variation = "ChipButton"
		"card":
			b.theme_type_variation = "CardButton"
		"icon":
			b.theme_type_variation = "IconButton"
		"tab":
			b.theme_type_variation = "TabButton"
	if icon != "":
		_add_icon(b, icon, icon_fill)
	return b


## 菜单大按钮：左侧图标 + 主标题 + 副标题
static func menu_button(title: String, sub: String, icon: String, kind := "normal", icon_fill := UiTheme.SUN) -> PopButton:
	var b := button("", kind)
	b.custom_minimum_size = Vector2(0, 92)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -22
	row.add_theme_constant_override("separation", 18)
	b.add_child(row)
	var ic := Icon.new(icon, 54.0, icon_fill)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(label(title, 36))
	if sub != "":
		col.add_child(label(sub, 20, UiTheme.INK_2))
	ignore_mouse(row)
	return b


static func icon_button(icon: String, tooltip := "", size := 72.0, fill := UiTheme.SUN) -> PopButton:
	var b := button("", "icon")
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = tooltip
	var ic := Icon.new(icon, size - 26.0, fill)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 13
	ic.offset_top = 13
	ic.offset_right = -13
	ic.offset_bottom = -13
	b.add_child(ic)
	return b


## 图标 + 文字的按钮内容（居中）；按钮最小尺寸随内容自动调整
static func _add_icon(b: Button, icon: String, fill: Color) -> void:
	var text := b.text
	b.text = ""
	b.set_meta("label", text)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	var ic := Icon.new(icon, 40.0, fill)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := label(text, 32)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	ignore_mouse(row)
	var fit := func() -> void:
		l.add_theme_font_size_override("font_size", b.get_theme_font_size("font_size"))
		var sb := b.get_theme_stylebox("normal")
		var need := row.get_combined_minimum_size() + sb.get_minimum_size()
		b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, need.x), maxf(b.custom_minimum_size.y, need.y))
	b.ready.connect(fit)


static func label(text: String, size := 26, color := UiTheme.INK, num := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color != UiTheme.INK:
		l.add_theme_color_override("font_color", color)
	if num:
		l.add_theme_font_override("font", UiTheme.font_num())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 描边标题字（糖果贴纸风：粗墨线描边 + 向下硬投影）
static func title(text: String, size := 72, color := UiTheme.SUN, num := false, outline := -1) -> Label:
	var l := label(text, size, color, num)
	var o := outline if outline >= 0 else maxi(6, int(size * 0.16))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", o)
	l.add_theme_color_override("font_shadow_color", INK)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, int(size * 0.085)))
	l.add_theme_constant_override("shadow_outline_size", o)
	return l


static func section(text: String) -> Label:
	var l := label(text, 30)
	l.theme_type_variation = "SectionLabel"
	return l


static func note(text: String, size := 22) -> Label:
	var l := label(text, size, UiTheme.INK_2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func stat_bar(text: String, value: int) -> StatBar:
	return StatBar.new(text, value)


static func star_rating(value: int, max_v := 3, size := 26.0) -> StarRating:
	return StarRating.new(value, max_v, size)


## 药丸形徽章
static func badge(text: String, color := UiTheme.MINT, size := 24, text_color := UiTheme.INK) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(color, 40, 3, INK, 4, Vector4(18, 6, 18, 9)))
	var l := label(text, size, text_color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 键帽（键盘）或手柄按键圆牌（pad：A 绿 / B 红 / X 蓝 / Y 黄）
static func keycap(text: String, pad := false, size := 22) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := UiTheme.WHITE
	var fg := INK
	if pad:
		match text:
			"A":
				bg = UiTheme.MINT
			"B":
				bg = UiTheme.RED
			"X":
				bg = UiTheme.BUBBLE
			"Y":
				bg = UiTheme.SUN
			_:
				bg = Color("#5A5F7A")
				fg = UiTheme.WHITE
	var sb := UiTheme.box(bg, 40 if pad else 9, 3, INK, 0, Vector4(10, 3, 10, 5) if not pad else Vector4(9, 3, 9, 5))
	sb.border_width_bottom = 3 if pad else 6
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, size, fg, _is_ascii(text))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(size * 0.9, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _is_ascii(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) > 127:
			return false
	return true


## 底部操作提示条：items = [[键盘键, 手柄键, 说明], ...]
static func hint_bar(items: Array) -> PanelContainer:
	var p := panel("InkPanel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	p.add_child(row)
	for it: Array in items:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var key: String = it[0]
		for k in key.split("|"):
			h.add_child(keycap(k, false, 20))
		var pad: String = it[1]
		if pad != "":
			var sl := label("/", 20, Color(UiTheme.CLOUD, 0.5))
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(sl)
			h.add_child(keycap(pad, true, 20))
		var t := label(str(it[2]), 22, UiTheme.CLOUD)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		row.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 分段选择：options = [[值, 文字], ...]，选中后回调 on_change(值)
static func segmented(options: Array, current: Variant, on_change: Callable, min_w := 0.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for opt: Array in options:
		var b := button(str(opt[1]), "chip")
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(min_w, 0)
		b.set_meta("value", opt[0])
		b.button_pressed = opt[0] == current
		var v: Variant = opt[0]
		b.pressed.connect(func() -> void: on_change.call(v))
		row.add_child(b)
	return row


## 选中分段中的某个值（不触发回调）
static func segmented_set(row: HBoxContainer, value: Variant) -> void:
	for c in row.get_children():
		var b := c as Button
		if b:
			b.set_pressed_no_signal(b.get_meta("value") == value)


## 卡片按钮：content 为卡片内部布局（鼠标事件穿透到按钮）
static func card(content: Control, min_size := Vector2.ZERO, selectable := true) -> PopButton:
	var b := button("", "card")
	b.toggle_mode = selectable
	b.custom_minimum_size = min_size
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		m.add_theme_constant_override(side, 12)
	m.add_child(content)
	b.add_child(m)
	ignore_mouse(m)
	return b


static func toggle(on: bool, on_change: Callable) -> ToggleSwitch:
	var t := ToggleSwitch.new()
	t.set_on(on)
	t.toggled.connect(func(v: bool) -> void: on_change.call(v))
	return t


static func slider(value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(360, 48)
	s.focus_mode = Control.FOCUS_ALL
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.value_changed.connect(func(v: float) -> void: on_change.call(v))
	s.mouse_entered.connect(func() -> void: s.grab_focus())
	return s


## 彩色圆点（车手代表色、涂装色）
static func dot(color: Color, d := 22.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(d, d)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var r := minf(c.size.x, c.size.y) / 2.0
		c.draw_circle(c.size / 2.0, r, INK)
		c.draw_circle(c.size / 2.0, r - 3.0, color))
	return c


## 铺满父控件（锚点 0..1，偏移清零；不受自身最小尺寸影响）
static func fill(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


## 子树全部不拦截鼠标（卡片内容）
static func ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		ignore_mouse(c)


## 模态对话框里的一排按钮：焦点只在这几个按钮之间循环，不会跑到被遮住的控件上
static func trap_focus(buttons: Array[Control]) -> void:
	var n := buttons.size()
	for i in n:
		var b := buttons[i]
		var left := buttons[(i - 1 + n) % n]
		var right := buttons[(i + 1) % n]
		b.focus_neighbor_left = b.get_path_to(left)
		b.focus_neighbor_right = b.get_path_to(right)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_previous = b.get_path_to(left)
		b.focus_next = b.get_path_to(right)


## 程序性聚焦：不播放悬停音
static func focus_quiet(c: Control) -> void:
	if c == null or not c.is_visible_in_tree():
		return
	quiet_until_ms = Time.get_ticks_msec() + 120
	c.grab_focus()


## 子控件依次弹入（缩放 + 淡入）
static func stagger_in(nodes: Array, delay := 0.05, start := 0.0) -> void:
	var i := 0
	for n: Variant in nodes:
		var c := n as Control
		if c == null:
			continue
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(start + i * delay)
		tw.tween_callback(func() -> void:
			c.pivot_offset = c.size / 2.0
			c.scale = Vector2.ONE * 0.85)
		tw.tween_property(c, "modulate:a", 1.0, 0.18)
		tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


# ———————————————————————— 赛道采样点 ————————————————————————

## 在后台线程预先构建全部赛道（每条约 70 ms），缩略图直接取采样点
static func prewarm_tracks() -> void:
	if _track_task >= 0 or not _track_pts.is_empty():
		return
	# 先在主线程加载好用到的脚本，避免工作线程里触发资源加载
	var warm := TrackData.SAMPLE_SPACING + float(TracksData.TRACKS.size()) + float(ThemesData.THEMES.size())
	if warm <= 0.0:
		return
	_track_task = WorkerThreadPool.add_task(_build_track_points, false, "赛道缩略图")


static func _build_track_points() -> void:
	var out := {}
	for d in TracksData.TRACKS:
		var td := TrackData.build(d)
		var pts := PackedVector2Array()
		var step := 3
		for i in range(0, td.n, step):
			pts.append(Vector2(td.px[i], td.pz[i]))
		out[d["id"]] = pts
	_track_pts = out


static func track_points(id: String) -> PackedVector2Array:
	if _track_pts.is_empty():
		if _track_task < 0:
			prewarm_tracks()
		WorkerThreadPool.wait_for_task_completion(_track_task)
		_track_task = -1
	if _track_pts.has(id):
		return _track_pts[id]
	return PackedVector2Array()


# ———————————————————————— 矢量绘制 ————————————————————————

static func rect_pts(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


## 填充多边形 + 墨线描边
static func draw_shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, INK, w, true)


static func draw_disc(ci: CanvasItem, c: Vector2, r: float, fill: Color, w: float) -> void:
	ci.draw_circle(c, r, fill)
	ci.draw_arc(c, r, 0.0, TAU, 48, INK, w, true)


static func star_pts(c: Vector2, r: float, inner := 0.46, rot := -PI / 2.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := rot + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * inner
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


static func draw_star(ci: CanvasItem, c: Vector2, r: float, fill: Color, w: float) -> void:
	draw_shape(ci, star_pts(c, r), fill, w)


## 图标：在 64×64 的设计空间里绘制，再缩放到 r
static func draw_icon(ci: CanvasItem, kind: String, r: Rect2, fill: Color) -> void:
	var k := r.size.x / 64.0
	var o := r.position
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var w := maxf(2.0, 3.2 * k)
	match kind:
		"flag":
			ci.draw_line(P.call(14.0, 58.0), P.call(14.0, 6.0), INK, 6.0 * k, true)
			var fl := rect_pts(P.call(16.0, 8.0), P.call(56.0, 36.0))
			ci.draw_colored_polygon(fl, UiTheme.WHITE)
			for cy in 4:
				for cx in 6:
					if (cx + cy) % 2 == 0:
						ci.draw_colored_polygon(rect_pts(P.call(16.0 + cx * 6.667, 8.0 + cy * 7.0), P.call(16.0 + (cx + 1) * 6.667, 8.0 + (cy + 1) * 7.0)), INK)
			var cl := fl.duplicate()
			cl.append(fl[0])
			ci.draw_polyline(cl, INK, w, true)
			draw_disc(ci, P.call(14.0, 6.0), 4.0 * k, fill, w * 0.7)
		"trophy":
			for side: float in [-1.0, 1.0]:
				ci.draw_arc(P.call(32.0 + side * 18.0, 20.0), 8.0 * k, 0.0, TAU, 24, INK, 7.0 * k, true)
				ci.draw_arc(P.call(32.0 + side * 18.0, 20.0), 8.0 * k, 0.0, TAU, 24, fill, 3.0 * k, true)
			var bowl := PackedVector2Array([P.call(14.0, 8.0), P.call(50.0, 8.0)])
			for i in range(0, 9):
				var a := PI * float(i) / 8.0
				bowl.append(P.call(32.0 + cos(a) * 18.0, 24.0 + sin(a) * 14.0))
			draw_shape(ci, bowl, fill, w)
			draw_shape(ci, rect_pts(P.call(28.0, 38.0), P.call(36.0, 47.0)), fill.darkened(0.2), w)
			draw_shape(ci, rect_pts(P.call(18.0, 47.0), P.call(46.0, 56.0)), fill.darkened(0.2), w)
			draw_star(ci, P.call(32.0, 21.0), 7.0 * k, UiTheme.WHITE, w * 0.6)
		"clock":
			draw_shape(ci, rect_pts(P.call(27.0, 5.0), P.call(37.0, 12.0)), fill, w)
			ci.draw_line(P.call(32.0, 12.0), P.call(32.0, 16.0), INK, w, true)
			draw_disc(ci, P.call(32.0, 37.0), 22.0 * k, UiTheme.WHITE, w)
			ci.draw_arc(P.call(32.0, 37.0), 15.0 * k, -PI / 2.0, 0.3, 24, fill, 8.0 * k, false)
			ci.draw_line(P.call(32.0, 37.0), P.call(32.0, 24.0), INK, w, true)
			ci.draw_line(P.call(32.0, 37.0), P.call(42.0, 42.0), INK, w, true)
			ci.draw_circle(P.call(32.0, 37.0), 3.0 * k, INK)
		"medal":
			draw_shape(ci, PackedVector2Array([P.call(16.0, 4.0), P.call(28.0, 4.0), P.call(36.0, 28.0), P.call(26.0, 30.0)]), UiTheme.BUBBLE, w)
			draw_shape(ci, PackedVector2Array([P.call(48.0, 4.0), P.call(36.0, 4.0), P.call(28.0, 28.0), P.call(38.0, 30.0)]), UiTheme.RED, w)
			draw_disc(ci, P.call(32.0, 42.0), 17.0 * k, fill, w)
			draw_star(ci, P.call(32.0, 42.0), 9.0 * k, UiTheme.WHITE, w * 0.6)
		"gear":
			var g := PackedVector2Array()
			for i in 48:
				var a := TAU * float(i) / 48.0
				var tooth := 1.0 if i % 6 < 3 else 0.0
				g.append(P.call(32.0 + cos(a) * (21.0 + tooth * 6.0), 32.0 + sin(a) * (21.0 + tooth * 6.0)))
			draw_shape(ci, g, fill, w)
			draw_disc(ci, P.call(32.0, 32.0), 9.0 * k, UiTheme.WHITE, w)
		"pad":
			var body := UiTheme.box(fill, int(14.0 * k), int(maxf(2.0, 3.0 * k)), INK, 0)
			body.draw(ci.get_canvas_item(), Rect2(P.call(4.0, 18.0), Vector2(56.0, 30.0) * k))
			ci.draw_line(P.call(16.0, 26.0), P.call(16.0, 40.0), INK, 5.0 * k, true)
			ci.draw_line(P.call(9.0, 33.0), P.call(23.0, 33.0), INK, 5.0 * k, true)
			draw_disc(ci, P.call(44.0, 28.0), 4.0 * k, UiTheme.MINT, w * 0.6)
			draw_disc(ci, P.call(51.0, 35.0), 4.0 * k, UiTheme.RED, w * 0.6)
			draw_disc(ci, P.call(37.0, 35.0), 4.0 * k, UiTheme.BUBBLE, w * 0.6)
			draw_disc(ci, P.call(44.0, 42.0), 4.0 * k, UiTheme.SUN, w * 0.6)
		"exit":
			draw_shape(ci, rect_pts(P.call(10.0, 6.0), P.call(36.0, 58.0)), fill, w)
			ci.draw_circle(P.call(30.0, 33.0), 3.0 * k, INK)
			draw_shape(ci, PackedVector2Array([P.call(34.0, 27.0), P.call(46.0, 27.0), P.call(46.0, 19.0), P.call(60.0, 32.0), P.call(46.0, 45.0), P.call(46.0, 37.0), P.call(34.0, 37.0)]), UiTheme.WHITE, w)
		"back":
			draw_shape(ci, PackedVector2Array([P.call(6.0, 32.0), P.call(28.0, 10.0), P.call(28.0, 23.0), P.call(56.0, 23.0), P.call(56.0, 41.0), P.call(28.0, 41.0), P.call(28.0, 54.0)]), fill, w)
		"next":
			draw_shape(ci, PackedVector2Array([P.call(58.0, 32.0), P.call(36.0, 10.0), P.call(36.0, 23.0), P.call(8.0, 23.0), P.call(8.0, 41.0), P.call(36.0, 41.0), P.call(36.0, 54.0)]), fill, w)
		"play":
			draw_shape(ci, PackedVector2Array([P.call(16.0, 8.0), P.call(54.0, 32.0), P.call(16.0, 56.0)]), fill, w)
		"star":
			draw_star(ci, P.call(32.0, 33.0), 27.0 * k, fill, w)
		"retry", "replay":
			ci.draw_arc(P.call(32.0, 34.0), 20.0 * k, -PI * 0.35, PI * 1.45, 32, INK, 13.0 * k, true)
			ci.draw_arc(P.call(32.0, 34.0), 20.0 * k, -PI * 0.35, PI * 1.45, 32, fill, 6.0 * k, true)
			draw_shape(ci, PackedVector2Array([P.call(40.0, 4.0), P.call(54.0, 17.0), P.call(36.0, 22.0)]), fill, w)
			if kind == "replay":
				draw_shape(ci, PackedVector2Array([P.call(27.0, 25.0), P.call(41.0, 34.0), P.call(27.0, 43.0)]), UiTheme.WHITE, w * 0.7)
		"home":
			draw_shape(ci, PackedVector2Array([P.call(32.0, 6.0), P.call(58.0, 30.0), P.call(50.0, 30.0), P.call(50.0, 56.0), P.call(14.0, 56.0), P.call(14.0, 30.0), P.call(6.0, 30.0)]), fill, w)
			draw_shape(ci, rect_pts(P.call(26.0, 38.0), P.call(38.0, 56.0)), UiTheme.WHITE, w)
		"book":
			draw_shape(ci, PackedVector2Array([P.call(32.0, 14.0), P.call(56.0, 8.0), P.call(56.0, 50.0), P.call(32.0, 56.0)]), UiTheme.WHITE, w)
			draw_shape(ci, PackedVector2Array([P.call(32.0, 14.0), P.call(8.0, 8.0), P.call(8.0, 50.0), P.call(32.0, 56.0)]), fill, w)
			for i in 3:
				ci.draw_line(P.call(38.0, 20.0 + i * 9.0), P.call(50.0, 17.0 + i * 9.0), Color(INK, 0.6), 2.5 * k, true)
		"check":
			ci.draw_polyline(PackedVector2Array([P.call(10.0, 34.0), P.call(26.0, 50.0), P.call(54.0, 16.0)]), INK, 14.0 * k, true)
			ci.draw_polyline(PackedVector2Array([P.call(10.0, 34.0), P.call(26.0, 50.0), P.call(54.0, 16.0)]), fill, 7.0 * k, true)
		"music":
			ci.draw_line(P.call(24.0, 46.0), P.call(24.0, 10.0), INK, 5.0 * k, true)
			ci.draw_line(P.call(48.0, 40.0), P.call(48.0, 6.0), INK, 5.0 * k, true)
			draw_shape(ci, PackedVector2Array([P.call(24.0, 10.0), P.call(48.0, 4.0), P.call(48.0, 14.0), P.call(24.0, 20.0)]), INK, 1.0)
			draw_disc(ci, P.call(17.0, 47.0), 9.0 * k, fill, w)
			draw_disc(ci, P.call(41.0, 41.0), 9.0 * k, fill, w)
		"speaker":
			draw_shape(ci, PackedVector2Array([P.call(6.0, 24.0), P.call(18.0, 24.0), P.call(34.0, 10.0), P.call(34.0, 54.0), P.call(18.0, 40.0), P.call(6.0, 40.0)]), fill, w)
			ci.draw_arc(P.call(34.0, 32.0), 12.0 * k, -0.9, 0.9, 12, INK, w, true)
			ci.draw_arc(P.call(34.0, 32.0), 21.0 * k, -0.9, 0.9, 16, INK, w, true)
		"eye":
			var e := PackedVector2Array()
			for i in 24:
				var a := TAU * float(i) / 24.0
				e.append(P.call(32.0 + cos(a) * 26.0, 32.0 + sin(a) * 15.0))
			draw_shape(ci, e, UiTheme.WHITE, w)
			draw_disc(ci, P.call(32.0, 32.0), 10.0 * k, fill, w)
			ci.draw_circle(P.call(32.0, 32.0), 4.0 * k, INK)
		"bolt":
			draw_shape(ci, PackedVector2Array([P.call(36.0, 4.0), P.call(12.0, 36.0), P.call(28.0, 36.0), P.call(24.0, 60.0), P.call(52.0, 24.0), P.call(35.0, 24.0)]), fill, w)
		"monitor":
			var scr := UiTheme.box(fill, int(6.0 * k), int(maxf(2.0, 3.0 * k)), INK, 0)
			scr.draw(ci.get_canvas_item(), Rect2(P.call(6.0, 8.0), Vector2(52.0, 36.0) * k))
			draw_shape(ci, rect_pts(P.call(28.0, 44.0), P.call(36.0, 52.0)), UiTheme.GRAY, w)
			draw_shape(ci, rect_pts(P.call(18.0, 52.0), P.call(46.0, 58.0)), UiTheme.GRAY, w)
		"camera":
			draw_shape(ci, rect_pts(P.call(6.0, 18.0), P.call(44.0, 50.0)), fill, w)
			draw_shape(ci, PackedVector2Array([P.call(44.0, 28.0), P.call(58.0, 20.0), P.call(58.0, 48.0), P.call(44.0, 40.0)]), fill.darkened(0.15), w)
			draw_disc(ci, P.call(25.0, 34.0), 8.0 * k, UiTheme.WHITE, w)
		"fps":
			ci.draw_arc(P.call(32.0, 40.0), 24.0 * k, PI, TAU, 24, INK, 11.0 * k, true)
			ci.draw_arc(P.call(32.0, 40.0), 24.0 * k, PI, TAU, 24, fill, 5.0 * k, true)
			ci.draw_line(P.call(32.0, 40.0), P.call(46.0, 24.0), INK, w * 1.3, true)
			ci.draw_circle(P.call(32.0, 40.0), 5.0 * k, INK)
		_:
			draw_disc(ci, P.call(32.0, 32.0), 24.0 * k, fill, w)
