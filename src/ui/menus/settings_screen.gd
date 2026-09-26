class_name SettingsScreen
extends MenuPage
## 设置页：音量、画质、全屏、垂直同步、视角、自动小喷、显示 FPS。

var panel: SettingsPanel


func build() -> void:
	stage = "hero"
	dim = 1.0
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := Widgets.panel()
	card.custom_minimum_size = Vector2(1040, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	var ic := Widgets.Icon.new("gear", 64.0, UiTheme.MINT)
	head.add_child(ic)
	var t := Widgets.title("设置", 60, UiTheme.SUN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var done_top := Widgets.icon_button("check", "完成", 68.0, UiTheme.MINT)
	done_top.focus_mode = Control.FOCUS_CLICK
	done_top.click_sound = "ui_back"
	done_top.pressed.connect(func() -> void: root.back())
	head.add_child(done_top)
	panel = SettingsPanel.new()
	v.add_child(panel)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	v.add_child(foot)
	var hints := Widgets.hint_bar([["↑|↓", "", "选择"], ["←|→", "", "调节"], ["Esc", "B", "返回"]])
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hints)
	var done := Widgets.button("完成", "primary", "check", UiTheme.WHITE)
	done.custom_minimum_size = Vector2(220, 0)
	done.click_sound = "ui_back"
	done.pressed.connect(func() -> void: root.back())
	foot.add_child(done)


func on_enter() -> void:
	Widgets.stagger_in(panel.get_children(), 0.035, 0.08)


func default_focus() -> Control:
	return panel.first


func view_rect() -> Rect2:
	return Rect2(0.3, 0.15, 0.4, 0.7)
