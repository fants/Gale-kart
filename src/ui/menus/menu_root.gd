class_name MenuRoot
extends Node
## 菜单总管：3D 背景舞台（车库 / 颁奖台）+ 页面栈 + 转场（淡入 + 滑动）+ 返回键 + 确认框。
## Esc / 手柄 B 返回上一页；Q / E、LB / RB 切换标签；页面打开时默认聚焦第一个按钮。

const BLUR_SHADER := preload("res://assets/shaders/ui_blur.gdshader")
const SLIDE := 90.0

var garage: GarageStage
var podium: PodiumStage
var layer: CanvasLayer
var holder: Control
var dimmer: ColorRect
var stack: Array[MenuPage] = []
var busy := false
var _dim_mat: ShaderMaterial
var _dim := 0.0
var _dim_tw: Tween
var _modal: Control = null
var _modal_prev_focus: Control = null


func _ready() -> void:
	name = "MenuRoot"
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	holder = Control.new()
	holder.name = "Pages"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme = UiTheme.build()
	layer.add_child(holder)
	dimmer = ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = BLUR_SHADER
	_dim_mat.set_shader_parameter("amount", 0.0)
	dimmer.material = _dim_mat
	dimmer.visible = false
	holder.add_child(dimmer)
	Widgets.prewarm_tracks()
	get_viewport().size_changed.connect(_on_resized)


func current() -> MenuPage:
	return stack[-1] if not stack.is_empty() else null


## 清空页面栈并打开页面；base 为垫在下面的页面（返回时回到这些页面）
func open(page_name: String, params := {}, base: Array[String] = []) -> void:
	for p in stack:
		p.queue_free()
	stack.clear()
	for b in base:
		var bp := _make(b, {})
		bp.visible = false
		stack.append(bp)
	var page := _make(page_name, params)
	stack.append(page)
	_enter(page, null, 1)


func push(page_name: String, params := {}) -> void:
	if busy:
		return
	var from := current()
	var page := _make(page_name, params)
	stack.append(page)
	_enter(page, from, 1)


## 替换栈顶页面（结算 → 积分榜 → 颁奖）
func replace(page_name: String, params := {}) -> void:
	if busy:
		return
	var from := current()
	if from:
		stack.pop_back()
	var page := _make(page_name, params)
	stack.append(page)
	_enter(page, from, 1, true)


func pop() -> void:
	if busy or stack.size() <= 1:
		return
	var from: MenuPage = stack.pop_back()
	var to := current()
	to.visible = true
	if not to.has_meta("entered"):
		to.on_enter()
	_enter(to, from, -1, true, true)
	to.on_resume()


## 返回键：页面自己处理，否则出栈
func back() -> void:
	if busy:
		return
	var page := current()
	if page and page.on_back():
		return
	if stack.size() > 1:
		AudioMgr.play("ui_back")
		pop()


func _make(page_name: String, params: Dictionary) -> MenuPage:
	var page: MenuPage
	match page_name:
		"title":
			page = TitleScreen.new()
		"main":
			page = MainMenu.new()
		"setup":
			page = SetupScreen.new()
		"settings":
			page = SettingsScreen.new()
		"records":
			page = RecordsScreen.new()
		"help":
			page = HelpScreen.new()
		"results":
			page = ResultsScreen.new()
		"gp_standings":
			page = GpStandings.new()
		"gp_award":
			page = GpAward.new()
		_:
			push_error("未知页面：%s" % page_name)
			page = MainMenu.new()
	page.name = page_name.capitalize().replace(" ", "")
	page.root = self
	page.params = params
	holder.add_child(page)
	page.build()
	return page


## 转场：旧页面滑出淡出，新页面滑入淡入；dir = 1 前进，-1 后退
func _enter(page: MenuPage, from: MenuPage, dir: int, free_from := false, resumed := false) -> void:
	busy = true
	_apply_stage(page)
	if from:
		var tw := from.create_tween().set_parallel()
		tw.tween_property(from, "modulate:a", 0.0, 0.18)
		tw.tween_property(from, "position:x", -SLIDE * dir, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func() -> void:
			if free_from:
				from.queue_free()
			else:
				from.visible = false
			from.position.x = 0.0)
	page.visible = true
	page.modulate.a = 0.0
	page.position.x = SLIDE * dir
	var tw2 := page.create_tween().set_parallel()
	tw2.tween_property(page, "modulate:a", 1.0, 0.26).set_delay(0.1 if from else 0.0)
	tw2.tween_property(page, "position:x", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.1 if from else 0.0)
	tw2.chain().tween_callback(func() -> void:
		busy = false
		focus_default())
	if not resumed:
		page.set_meta("entered", true)
		page.on_enter()


func focus_default() -> void:
	var page := current()
	if page == null or _modal != null:
		return
	var f := page.default_focus()
	if f:
		Widgets.focus_quiet(f)


## 按当前页面切换 3D 舞台、机位、压暗
func _apply_stage(page: MenuPage) -> void:
	if page.stage == "podium":
		if garage:
			garage.visible = false
			garage.bg_layer.visible = false
			garage.set_process(false)
		if podium == null:
			podium = PodiumStage.new()
			add_child(podium)
			move_child(podium, 0)
		podium.visible = true
		podium.bg_layer.visible = true
		podium.set_process(true)
		podium.camera.make_current()
		podium.setup(page.podium_rows(), page.podium_solo())
	else:
		if podium:
			podium.visible = false
			podium.bg_layer.visible = false
			podium.set_process(false)
		if garage == null:
			garage = GarageStage.new()
			add_child(garage)
			move_child(garage, 0)
		garage.visible = true
		garage.bg_layer.visible = true
		garage.set_process(true)
		garage.camera.make_current()
		var s := page.garage_selection()
		garage.show_kart(str(s.get("kart_id", "marshmallow")), str(s.get("character_id", "male-a")), str(s.get("paint_id", "oodi")))
	var st: MenuStage = podium if page.stage == "podium" else garage
	st.set_view_rect(page.view_rect(), stack.size() <= 1 and page.modulate.a < 0.01 and st.time < 0.05)
	set_dim(page.dim)


func set_dim(v: float) -> void:
	if _dim_tw:
		_dim_tw.kill()
	dimmer.visible = true
	_dim_tw = create_tween()
	_dim_tw.tween_method(_set_dim_now, _dim, v, 0.3)
	if v <= 0.0:
		_dim_tw.tween_callback(func() -> void: dimmer.visible = false)


func _set_dim_now(v: float) -> void:
	_dim = v
	_dim_mat.set_shader_parameter("amount", v)


## 页面内容变化后刷新机位（例如设置页的右侧预览区域）
func refresh_view() -> void:
	var page := current()
	if page == null:
		return
	var st: MenuStage = podium if page.stage == "podium" else garage
	if st:
		st.set_view_rect(page.view_rect())


func _on_resized() -> void:
	refresh_view.call_deferred()


## 车库换装
func show_selection(sel: Dictionary) -> void:
	if garage:
		garage.show_kart(str(sel.get("kart_id", "marshmallow")), str(sel.get("character_id", "male-a")), str(sel.get("paint_id", "oodi")))


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_echo():
		return
	if _modal:
		if ev.is_action_pressed("ui_cancel"):
			close_modal()
			AudioMgr.play("ui_back")
			get_viewport().set_input_as_handled()
		return
	if busy:
		if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
		return
	var page := current()
	if page == null:
		return
	if ev.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()
		return
	var tab := _tab_dir(ev)
	if tab != 0:
		page.on_tab(tab)
		get_viewport().set_input_as_handled()
		return
	# 焦点丢失（鼠标点在空白处）时，方向键 / 确认键先找回默认焦点
	if get_viewport().gui_get_focus_owner() == null:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]:
			if ev.is_action_pressed(a):
				focus_default()
				get_viewport().set_input_as_handled()
				return


static func _tab_dir(ev: InputEvent) -> int:
	if ev is InputEventKey and ev.is_pressed():
		var k := (ev as InputEventKey).physical_keycode
		if k == KEY_Q:
			return -1
		if k == KEY_E:
			return 1
	elif ev is InputEventJoypadButton and ev.is_pressed():
		var b := (ev as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_LEFT_SHOULDER:
			return -1
		if b == JOY_BUTTON_RIGHT_SHOULDER:
			return 1
	return 0


# ———————————————— 确认框 ————————————————

func confirm(text: String, yes_text: String, on_yes: Callable, danger := true) -> void:
	_modal_prev_focus = get_viewport().gui_get_focus_owner()
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var p := Widgets.panel()
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 30)
	p.add_child(v)
	var l := Widgets.label(text, 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var no := Widgets.button("取消", "normal")
	no.custom_minimum_size = Vector2(200, 0)
	no.click_sound = "ui_back"
	var yes := Widgets.button(yes_text, "danger" if danger else "primary")
	yes.custom_minimum_size = Vector2(200, 0)
	row.add_child(no)
	row.add_child(yes)
	Widgets.trap_focus([no, yes])
	no.pressed.connect(close_modal)
	yes.pressed.connect(func() -> void:
		close_modal()
		on_yes.call())
	_modal = shade
	p.pivot_offset = Vector2(320, 100)
	p.scale = Vector2.ONE * 0.8
	shade.modulate.a = 0.0
	var tw := shade.create_tween().set_parallel()
	tw.tween_property(shade, "modulate:a", 1.0, 0.15)
	tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Widgets.focus_quiet.call_deferred(no)


func close_modal() -> void:
	if _modal == null:
		return
	_modal.queue_free()
	_modal = null
	if _modal_prev_focus and is_instance_valid(_modal_prev_focus):
		Widgets.focus_quiet(_modal_prev_focus)
	else:
		focus_default()
