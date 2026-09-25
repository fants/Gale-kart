class_name PauseMenu
extends CanvasLayer
## 暂停菜单（比赛上方的覆盖层）：继续、重新开始、设置、退出比赛。
## Esc / P / 手柄 Start 再按一次继续；设置子面板里按返回键回到暂停菜单。

signal resumed
signal restart_requested
signal quit_requested

const BLUR_SHADER := preload("res://assets/shaders/ui_blur.gdshader")

var ctl: RaceController
var gp: Dictionary
var ui: Control
var blur_mat: ShaderMaterial
var main_panel: PanelContainer
var settings_box: PanelContainer
var settings: SettingsPanel
var _first: Control
var _settings_btn: Control
var _closing := false
var _in_settings := false
var _confirm: Control = null


func setup(p_ctl: RaceController, p_gp: Dictionary) -> void:
	ctl = p_ctl
	gp = p_gp
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.build()
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ui)
	var blur := ColorRect.new()
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur_mat = ShaderMaterial.new()
	blur_mat.shader = BLUR_SHADER
	blur_mat.set_shader_parameter("amount", 0.0)
	blur_mat.set_shader_parameter("tint_alpha", 0.45)
	blur.material = blur_mat
	ui.add_child(blur)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)

	# 主面板
	main_panel = Widgets.panel()
	main_panel.custom_minimum_size = Vector2(660, 0)
	center.add_child(main_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	main_panel.add_child(v)
	var t := Widgets.title("暂停", 84, UiTheme.SUN, false, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 10)
	v.add_child(info)
	var race := ctl.race
	var mode_name: String = {"speed": "竞速赛", "item": "道具赛", "time": "计时赛"}.get(race.mode, "竞速赛")
	info.add_child(Widgets.badge(ctl.track.name, UiTheme.SUN, 24))
	info.add_child(Widgets.badge(mode_name, UiTheme.BUBBLE, 24))
	var lap := clampi(race.player.lap, 1, race.laps)
	info.add_child(Widgets.badge("第 %d / %d 圈" % [lap, race.laps], UiTheme.WHITE, 24))
	if race.karts.size() > 1:
		info.add_child(Widgets.badge("第 %d 名" % race.player.rank, UiTheme.MINT, 24))
	if not gp.is_empty():
		var tracks: Array = gp["tracks"]
		var gl := Widgets.label("%s · 第 %d / %d 场" % [gp["cup_name"], int(gp["index"]) + 1, tracks.size()], 24, UiTheme.INK_2)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(gl)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	var resume := Widgets.button("继续比赛", "primary", "play", UiTheme.WHITE)
	resume.click_sound = "ui_confirm"
	resume.pressed.connect(close)
	var restart := Widgets.button("重新开始", "normal", "retry", UiTheme.BUBBLE)
	restart.pressed.connect(_ask_restart)
	var st := Widgets.button("设置", "normal", "gear", UiTheme.MINT)
	st.pressed.connect(_open_settings)
	var quit := Widgets.button("退出比赛", "danger", "exit", UiTheme.SUN_LIGHT)
	quit.click_sound = "ui_back"
	quit.pressed.connect(_ask_quit)
	for b: Button in [resume, restart, st, quit]:
		b.custom_minimum_size = Vector2(0, 84)
		v.add_child(b)
	_first = resume
	_settings_btn = st
	var hints := Widgets.hint_bar([["Esc", "Start", "继续"], ["Enter", "A", "确认"]])
	hints.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(hints)

	# 设置子面板
	settings_box = Widgets.panel()
	settings_box.custom_minimum_size = Vector2(1000, 0)
	settings_box.visible = false
	center.add_child(settings_box)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 16)
	settings_box.add_child(sv)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 16)
	sv.add_child(sh)
	sh.add_child(Widgets.Icon.new("gear", 56.0, UiTheme.MINT))
	sh.add_child(Widgets.title("设置", 54, UiTheme.SUN))
	settings = SettingsPanel.new()
	sv.add_child(settings)
	var done := Widgets.button("返回", "primary", "back", UiTheme.WHITE)
	done.click_sound = "ui_back"
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.custom_minimum_size = Vector2(220, 0)
	done.pressed.connect(_close_settings)
	sv.add_child(done)

	# 入场
	var tw := create_tween().set_parallel()
	tw.tween_method(_set_blur, 0.0, 1.0, 0.22)
	main_panel.pivot_offset = Vector2(330, 300)
	main_panel.scale = Vector2.ONE * 0.85
	main_panel.modulate.a = 0.0
	tw.tween_property(main_panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(main_panel, "modulate:a", 1.0, 0.16)
	Widgets.focus_quiet.call_deferred(_first)


func _set_blur(v: float) -> void:
	blur_mat.set_shader_parameter("amount", v)


func _unhandled_input(ev: InputEvent) -> void:
	if _closing or ev.is_echo():
		return
	if _confirm:
		if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause"):
			_close_confirm()
			get_viewport().set_input_as_handled()
		return
	if _in_settings:
		if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause"):
			_close_settings()
			AudioMgr.play("ui_back")
			get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("pause") or ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if get_viewport().gui_get_focus_owner() == null:
		for a in ["ui_up", "ui_down", "ui_accept"]:
			if ev.is_action_pressed(a):
				Widgets.focus_quiet(_first)
				get_viewport().set_input_as_handled()
				return


## 继续比赛：面板收起后再恢复（避免同一次按键又触发比赛里的暂停）
func close() -> void:
	if _closing:
		return
	_closing = true
	AudioMgr.play("ui_back")
	var tw := create_tween().set_parallel()
	tw.tween_method(_set_blur, 1.0, 0.0, 0.18)
	tw.tween_property(main_panel, "scale", Vector2.ONE * 0.9, 0.16)
	tw.tween_property(main_panel, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(func() -> void:
		resumed.emit()
		queue_free())


func _open_settings() -> void:
	_in_settings = true
	main_panel.visible = false
	settings_box.visible = true
	settings_box.pivot_offset = settings_box.size / 2.0
	Widgets.stagger_in(settings.get_children(), 0.03)
	Widgets.focus_quiet.call_deferred(settings.first)


func _close_settings() -> void:
	_in_settings = false
	settings_box.visible = false
	main_panel.visible = true
	Widgets.focus_quiet.call_deferred(_settings_btn)


func _ask_restart() -> void:
	_show_confirm("重新开始本场比赛？", "重新开始", func() -> void:
		_closing = true
		restart_requested.emit())


func _ask_quit() -> void:
	var text := "退出大奖赛？本杯赛的积分将不会保存。" if not gp.is_empty() else "退出比赛，回到主菜单？"
	_show_confirm(text, "退出", func() -> void:
		_closing = true
		quit_requested.emit())


func _show_confirm(text: String, yes_text: String, on_yes: Callable) -> void:
	var prev := ui.get_viewport().gui_get_focus_owner()
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var p := Widgets.panel()
	p.custom_minimum_size = Vector2(620, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 28)
	p.add_child(v)
	var l := Widgets.label(text, 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var no := Widgets.button("取消")
	no.custom_minimum_size = Vector2(200, 0)
	no.click_sound = "ui_back"
	var yes := Widgets.button(yes_text, "danger")
	yes.custom_minimum_size = Vector2(200, 0)
	row.add_child(no)
	row.add_child(yes)
	Widgets.trap_focus([no, yes])
	_confirm = shade
	shade.set_meta("prev", prev)
	no.pressed.connect(_close_confirm)
	yes.pressed.connect(func() -> void:
		_close_confirm()
		on_yes.call())
	Widgets.focus_quiet.call_deferred(no)


func _close_confirm() -> void:
	if _confirm == null:
		return
	var prev: Variant = _confirm.get_meta("prev")
	_confirm.queue_free()
	_confirm = null
	if prev is Control and is_instance_valid(prev):
		Widgets.focus_quiet(prev as Control)
