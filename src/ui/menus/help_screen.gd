class_name HelpScreen
extends MenuPage
## 操作说明：三个标签页——操作（键盘 / 手柄对照表）、技巧、道具图鉴（10 种）。

const KEYS: Array[Array] = [
	["加速 / 刹车", "↑|↓", "或", "W|S", "RT|LT"],
	["转向", "←|→", "或", "A|D", "左摇杆|十字键"],
	["漂移", "Shift", "或", "J", "B|RB"],
	["氮气 / 道具", "空格", "或", "K", "A"],
	["交换道具", "Q", "或", "E", "X"],
	["复位", "R", "", "", "Y"],
	["切换视角", "C", "", "", "Back"],
	["暂停", "Esc", "或", "P", "Start"],
	["隐藏 HUD", "H", "", "", ""],
	["静音", "M", "", "", ""],
	["全屏", "F11", "", "", ""],
]

const TIPS: Array[Array] = [
	["bolt", "漂移", "转弯时按住 Shift，车尾甩出、转向更急；松开即结束漂移。"],
	["flag", "集气与氮气", "竞速赛中漂移会积攒集气条，满一格得到一个氮气（最多 2 个），按空格释放。"],
	["next", "瞬间加速（小喷）", "漂移超过 0.35 秒后松开，火花变蓝、出现 ↑ 提示时再按一次 ↑。"],
	["play", "起步加速", "倒计时 GO 出现的瞬间按下 ↑ 获得起步加速；提前按住会抢跑打滑。"],
	["eye", "尾流", "紧跟前车正后方约 1 秒，出现风线后获得短暂的尾流加速。"],
	["star", "加速带与跳台", "橙色箭头地块驶过即加速；跳台可以飞越，落地时注意方向。"],
	["trophy", "道具赛", "撞碎彩色「?」箱获得道具：领先多拿防守道具，落后多拿进攻道具；Q 交换两个槽位。"],
	["retry", "复位与录像", "卡住了按 R 复位；C 切换远 / 近视角；H 隐藏 HUD，方便录制视频。"],
]

var _tab_btns: Array[Button] = []
var _pages: Array[Control] = []
var _tab := 0


func build() -> void:
	dim = 1.0
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := Widgets.panel()
	card.custom_minimum_size = Vector2(1480, 900)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	head.add_child(Widgets.Icon.new("pad", 64.0, UiTheme.BUBBLE))
	head.add_child(Widgets.title("操作说明", 60, UiTheme.SUN))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var tp := Widgets.panel("TabsPanel")
	tp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tp)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	tp.add_child(tr)
	var q := Widgets.keycap("Q", false, 20)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(q)
	var group := ButtonGroup.new()
	var names: Array[String] = ["操作", "技巧", "道具"]
	var icons: Array[String] = ["pad", "star", "bolt"]
	for i in names.size():
		var b := Widgets.button(names[i], "tab", icons[i], [UiTheme.BUBBLE, UiTheme.SUN, UiTheme.PINK][i])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(170, 60)
		var idx := i
		b.pressed.connect(func() -> void: _set_tab(idx))
		b.focus_entered.connect(func() -> void:
			if _tab != idx:
				_set_tab(idx))
		tr.add_child(b)
		_tab_btns.append(b)
	var e := Widgets.keycap("E", false, 20)
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(e)
	var close := Widgets.icon_button("check", "关闭", 68.0, UiTheme.MINT)
	close.click_sound = "ui_back"
	close.focus_mode = Control.FOCUS_CLICK
	close.pressed.connect(func() -> void: root.back())
	head.add_child(close)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stack)
	for p: Control in [_build_keys(), _build_tips(), _build_items()]:
		stack.add_child(p)
		Widgets.fill(p)
		_pages.append(p)
	var hints := Widgets.hint_bar([["←|→", "", "切换"], ["Q|E", "LB", "切换"], ["Esc", "B", "返回"]])
	hints.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(hints)
	_set_tab(clampi(int(params.get("tab", 0)), 0, _pages.size() - 1))


func _set_tab(i: int) -> void:
	_tab = i
	for j in _tab_btns.size():
		_tab_btns[j].set_pressed_no_signal(j == i)
	for j in _pages.size():
		_pages[j].visible = j == i
	var items: Array = []
	var page := _pages[i]
	for c in page.get_children():
		if c is GridContainer or c is VBoxContainer:
			items.append_array(c.get_children())
		else:
			items.append(c)
	if is_inside_tree():
		Widgets.stagger_in(items, 0.025)


func on_tab(dir: int) -> void:
	var n := (_tab + dir + _pages.size()) % _pages.size()
	AudioMgr.play("ui_click")
	Widgets.focus_quiet(_tab_btns[n])
	_set_tab(n)


func _build_keys() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hdr := HBoxContainer.new()
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 20)
	hm.add_theme_constant_override("margin_right", 20)
	hm.add_child(hdr)
	v.add_child(hm)
	var cols: Array[String] = ["功能", "键盘", "手柄"]
	var widths: Array[float] = [320.0, 560.0, 400.0]
	for i in 3:
		var l := Widgets.label(cols[i], 24, UiTheme.INK_2)
		l.custom_minimum_size = Vector2(widths[i], 0)
		hdr.add_child(l)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	v.add_child(list)
	for k: Array in KEYS:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.WHITE, 14, 2, Color(UiTheme.INK, 0.25), 0, Vector4(20, 5, 20, 5)))
		var h := HBoxContainer.new()
		p.add_child(h)
		var name_l := Widgets.label(str(k[0]), 28)
		name_l.custom_minimum_size = Vector2(widths[0], 0)
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(name_l)
		var kb := HBoxContainer.new()
		kb.custom_minimum_size = Vector2(widths[1], 0)
		kb.add_theme_constant_override("separation", 8)
		h.add_child(kb)
		_keys_into(kb, str(k[1]), false)
		if str(k[2]) != "":
			var ol := Widgets.label(str(k[2]), 22, UiTheme.INK_2)
			ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			kb.add_child(ol)
			_keys_into(kb, str(k[3]), false)
		var pb := HBoxContainer.new()
		pb.custom_minimum_size = Vector2(widths[2], 0)
		pb.add_theme_constant_override("separation", 8)
		h.add_child(pb)
		if str(k[4]) == "":
			pb.add_child(Widgets.label("—", 24, UiTheme.INK_2))
		else:
			_keys_into(pb, str(k[4]), true)
		list.add_child(p)
	return v


func _keys_into(box: HBoxContainer, keys: String, pad: bool) -> void:
	var parts := keys.split("|")
	for i in parts.size():
		var t := parts[i]
		if pad and t.length() > 3 and not t in ["Back", "Start"]:
			var l := Widgets.label(t, 24)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(l)
		else:
			var kc := Widgets.keycap(t, pad, 22)
			kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(kc)
		if pad and i < parts.size() - 1:
			var sl := Widgets.label("/", 22, UiTheme.INK_2)
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(sl)


func _build_tips() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fills: Array[Color] = [UiTheme.BUBBLE, UiTheme.SUN, UiTheme.MINT, UiTheme.PINK]
	for i in TIPS.size():
		var tip: Array = TIPS[i]
		var p := Widgets.panel("CardPanel")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(0, 150)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		p.add_child(h)
		var ic := Widgets.Icon.new(str(tip[0]), 64.0, fills[i % fills.size()])
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_theme_constant_override("separation", 4)
		h.add_child(tv)
		tv.add_child(Widgets.label(str(tip[1]), 32))
		tv.add_child(Widgets.note(str(tip[2]), 22))
		grid.add_child(p)
	return grid


func _build_items() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: String in ItemsData.ITEMS:
		var it: Dictionary = ItemsData.ITEMS[id]
		var p := Widgets.panel("CardPanel")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(0, 118)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		p.add_child(h)
		h.add_child(_item_icon(id))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.add_theme_constant_override("separation", 2)
		h.add_child(tv)
		tv.add_child(Widgets.label(str(it["name"]), 30))
		tv.add_child(Widgets.note(str(it["desc"]), 22))
		grid.add_child(p)
	return grid


## 道具图标：道具色深底圆角方块 + 图标
func _item_icon(id: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(88, 88)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := Color(str(ItemsData.ITEMS[id]["color"]))
	var tex := ItemsData.icon(id)
	c.draw.connect(func() -> void:
		var r := Rect2(Vector2(2, 2), c.size - Vector2(4, 8))
		c.draw_style_box(UiTheme.box(col.darkened(0.55), 18, 3, col.lightened(0.1), 4), r)
		c.draw_texture_rect(tex, r.grow(-6), false))
	return c


func default_focus() -> Control:
	return _tab_btns[_tab]


func view_rect() -> Rect2:
	return Rect2(0.3, 0.15, 0.4, 0.7)
