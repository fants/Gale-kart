class_name SettingsPanel
extends VBoxContainer
## 设置项列表（设置页与暂停菜单共用）：修改即时保存（Store.save_settings），音量 / 全屏 / 垂直同步立即生效。

var first: Control
var _pct: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var s := Store.settings
	_slider_row("音乐音量", "music", "music", float(s["music"]), UiTheme.PINK)
	_slider_row("音效音量", "speaker", "sfx", float(s["sfx"]), UiTheme.BUBBLE)
	_row("画质", "低画质更流畅；下一场比赛生效", "monitor", UiTheme.BUBBLE,
		Widgets.segmented([["low", "低"], ["medium", "中"], ["high", "高"]], str(s["quality"]),
			func(v: Variant) -> void: Game.apply_settings({"quality": str(v)}), 96.0))
	var fs := bool(s["fullscreen"])
	if DisplayServer.get_name() != "headless":
		fs = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_row("全屏", "也可以随时按 F11 切换", "monitor", UiTheme.MINT,
		Widgets.toggle(fs, func(v: bool) -> void: Game.apply_settings({"fullscreen": v})))
	_row("垂直同步", "避免画面撕裂", "bolt", UiTheme.SUN,
		Widgets.toggle(bool(s["vsync"]), func(v: bool) -> void: Game.apply_settings({"vsync": v})))
	_row("视角", "比赛中按 C 也能切换", "camera", UiTheme.SUN,
		Widgets.segmented([["far", "远"], ["near", "近"]], str(s["camera"]),
			func(v: Variant) -> void: Game.apply_settings({"camera": str(v)}), 96.0))
	_row("自动小喷", "漂移结束时自动触发瞬间加速", "bolt", UiTheme.BUBBLE,
		Widgets.toggle(bool(s["auto_instant"]), func(v: bool) -> void: Game.apply_settings({"auto_instant": v})))
	_row("显示 FPS", "比赛画面底部显示帧率", "fps", UiTheme.MINT,
		Widgets.toggle(bool(s["show_fps"]), func(v: bool) -> void: Game.apply_settings({"show_fps": v})))


func _row(text: String, sub: String, icon: String, icon_fill: Color, control: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.WHITE, 16, 3, UiTheme.INK, 0, Vector4(18, 8, 18, 8)))
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var ic := Widgets.Icon.new(icon, 46.0, icon_fill)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -2)
	row.add_child(col)
	col.add_child(Widgets.label(text, 30))
	if sub != "":
		col.add_child(Widgets.label(sub, 20, UiTheme.INK_2))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	# 行内控件获得焦点时整行描边变成泡泡蓝
	var normal := UiTheme.box(UiTheme.WHITE, 16, 3, UiTheme.INK, 0, Vector4(18, 8, 18, 8))
	var hot := UiTheme.box(UiTheme.SKY_PALE, 16, 4, UiTheme.BUBBLE, 0, Vector4(18, 8, 18, 8))
	for c in _focusables(control):
		c.focus_entered.connect(func() -> void: p.add_theme_stylebox_override("panel", hot))
		c.focus_exited.connect(func() -> void: p.add_theme_stylebox_override("panel", normal))
	if first == null:
		first = control if not control is HBoxContainer else control.get_child(0) as Control


func _focusables(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control and (n as Control).focus_mode == Control.FOCUS_ALL:
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_focusables(c))
	return out


func _slider_row(text: String, icon: String, key: String, value: float, icon_fill: Color) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	var sl := Widgets.slider(value, func(v: float) -> void:
		Game.apply_settings({key: v})
		(_pct[key] as Label).text = "%d%%" % int(round(v * 100.0)))
	sl.custom_minimum_size = Vector2(380, 48)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if key == "sfx":
		sl.drag_ended.connect(func(_changed: bool) -> void: AudioMgr.play("ui_click"))
	box.add_child(sl)
	var pl := Widgets.label("%d%%" % int(round(value * 100.0)), 26, UiTheme.INK, true)
	pl.custom_minimum_size = Vector2(86, 0)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(pl)
	_pct[key] = pl
	_row(text, "", icon, icon_fill, box)
	if first == box:
		first = sl
