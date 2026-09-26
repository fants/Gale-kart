class_name MainMenu
extends MenuPage
## 主菜单：快速比赛、大奖赛、计时赛、最佳纪录、设置、操作说明、退出；右下角显示当前座驾。

var _first: Control
var _buttons: Array[Control] = []
var _ride_name: Label
var _ride_kart: Label
var _ride_dot: Control
var _ride_panel: Control


func build() -> void:
	stage = "hero"
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_top = 50
	col.offset_right = 90 + 620
	col.offset_bottom = -36
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	# 小 Logo
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(620, 190)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(logo)
	var tex := UiArt.logo()
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		img.size = Vector2(450, 450.0 * tex.get_height() / tex.get_width())
		img.position = Vector2(-10, 0)
		img.rotation = deg_to_rad(-2.0)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.add_child(img)
	else:
		var cn := Widgets.title("疾风卡丁", 124, UiTheme.SUN, false, 14)
		cn.rotation = deg_to_rad(-3.0)
		logo.add_child(cn)

	var quick := Widgets.menu_button("快速比赛", "竞速赛 · 道具赛  和 7 位 AI 一决高下", "flag", "primary", UiTheme.WHITE)
	quick.click_sound = "ui_confirm"
	quick.pressed.connect(func() -> void: root.push("setup", {"kind": "quick"}))
	var gp := Widgets.menu_button("大奖赛", "新星杯 · 疾风杯  四场积分定冠军", "trophy", "normal", UiTheme.SUN)
	gp.pressed.connect(func() -> void: root.push("setup", {"kind": "gp"}))
	var tt := Widgets.menu_button("计时赛", "单人冲刺  挑战自己的幽灵车", "clock", "normal", UiTheme.BUBBLE)
	tt.pressed.connect(func() -> void: root.push("setup", {"kind": "time"}))
	for b in [quick, gp, tt]:
		col.add_child(b)
		_buttons.append(b)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)
	var rec := Widgets.button("最佳纪录", "normal", "medal", UiTheme.SUN)
	rec.pressed.connect(func() -> void: root.push("records"))
	var st := Widgets.button("设置", "normal", "gear", UiTheme.MINT)
	st.pressed.connect(func() -> void: root.push("settings"))
	var hp := Widgets.button("操作说明", "normal", "pad", UiTheme.BUBBLE)
	hp.pressed.connect(func() -> void: root.push("help"))
	var ex := Widgets.button("退出游戏", "danger", "exit", UiTheme.SUN_LIGHT)
	ex.click_sound = "ui_back"
	ex.pressed.connect(_ask_quit)
	for b: Button in [rec, st, hp, ex]:
		b.custom_minimum_size = Vector2(302, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		_buttons.append(b)
	_first = quick

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var hints := Widgets.hint_bar([["↑|↓", "", "选择"], ["Enter", "A", "确认"], ["Esc", "B", "返回"]])
	hints.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(hints)

	# 右下角：当前座驾
	var ride := Widgets.panel("GlassPanel")
	ride.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ride.offset_left = -640
	ride.offset_top = -200
	ride.offset_right = -56
	ride.offset_bottom = -40
	ride.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ride.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(ride)
	_ride_panel = ride
	add_child(Widgets.pin(Widgets.creator_badge(1.1), Control.PRESET_TOP_RIGHT, Vector2(56, 44)))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 20)
	ride.add_child(rrow)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	rrow.add_child(info)
	info.add_child(Widgets.label("当前座驾", 22, UiTheme.INK_2))
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 12)
	info.add_child(nrow)
	_ride_dot = Widgets.dot(UiTheme.MINT, 26)
	_ride_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(_ride_dot)
	_ride_name = Widgets.label("", 40)
	nrow.add_child(_ride_name)
	_ride_kart = Widgets.label("", 24, UiTheme.INK_2)
	info.add_child(_ride_kart)
	var change := Widgets.button("换车", "normal", "gear", UiTheme.SUN)
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	change.pressed.connect(func() -> void: root.push("setup", {"kind": "quick", "tab": 1}))
	rrow.add_child(change)
	_buttons.append(change)
	_refresh_ride()


func _refresh_ride() -> void:
	var s := Store.selection
	var ch := KartsData.character_by_id(str(s.get("character_id", "")))
	var kd := KartsData.kart_by_id(str(s.get("kart_id", "")))
	var pt := KartsData.paint_by_id(str(s.get("paint_id", "")))
	_ride_name.text = str(ch["name"])
	_ride_kart.text = "%s · %s涂装" % [kd["name"], pt["name"]]
	_ride_dot.queue_free()
	_ride_dot = Widgets.dot(Color(str(ch["color"])), 26)
	_ride_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ride_name.get_parent().add_child(_ride_dot)
	_ride_name.get_parent().move_child(_ride_dot, 0)


func on_enter() -> void:
	Widgets.stagger_in(_buttons, 0.05, 0.12)


func on_resume() -> void:
	_refresh_ride()
	root.show_selection(Store.selection)


func default_focus() -> Control:
	return _first


func view_rect() -> Rect2:
	return Rect2(0.44, 0.1, 0.52, 0.62)


func on_back() -> bool:
	if root.stack.size() <= 1:
		_ask_quit()
		return true
	return false


func _ask_quit() -> void:
	root.confirm("要退出游戏吗？", "退出", func() -> void: Game.quit_game())
