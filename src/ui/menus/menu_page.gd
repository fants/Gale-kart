class_name MenuPage
extends Control
## 菜单页面基类：由 MenuRoot 创建、压栈、转场。子类在 build() 里搭界面。

var root: MenuRoot
var params: Dictionary = {}
## 背景："hero" 首页大图 / "garage" 3D 车库 / "podium" 3D 颁奖台
var stage := "garage"
## 3D 背景压暗（0..1，模糊 + 墨蓝色调）
var dim := 0.0
## 页面内容的外边距（基准 1920×1080）
const MARGIN := Vector4(56, 40, 56, 36)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 搭建界面（只调用一次，此时 params 与 root 已就绪）
func build() -> void:
	pass


## 页面显示时（首次进入）
func on_enter() -> void:
	pass


## 从上层页面返回到本页时
func on_resume() -> void:
	pass


## 默认聚焦的控件
func default_focus() -> Control:
	return null


## 返回键（Esc / 手柄 B）；返回 true 表示已处理，否则由 MenuRoot 出栈
func on_back() -> bool:
	return false


## Q / E、手柄 LB / RB 切换标签页
func on_tab(_dir: int) -> void:
	pass


## 3D 主体在屏幕上的矩形（视口比例）
func view_rect() -> Rect2:
	return Rect2(0.5, 0.12, 0.45, 0.78)


## 颁奖台上的前三名（按名次排序：character_id kart_id paint_id is_player）
func podium_rows() -> Array:
	return []


## 颁奖台只放冠军（计时赛）
func podium_solo() -> bool:
	return false


## 车库展示的车 / 车手 / 涂装
func garage_selection() -> Dictionary:
	return Store.selection


## 带外边距的全屏容器
func margin_box() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(MARGIN.x))
	m.add_theme_constant_override("margin_top", int(MARGIN.y))
	m.add_theme_constant_override("margin_right", int(MARGIN.z))
	m.add_theme_constant_override("margin_bottom", int(MARGIN.w))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	return m


## 顶部标题栏：返回按钮 + 标题
func top_bar(text: String, sub := "") -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 22)
	var back := Widgets.icon_button("back", "返回", 72.0, UiTheme.SUN)
	back.click_sound = "ui_back"
	back.focus_mode = Control.FOCUS_CLICK
	back.pressed.connect(func() -> void: root.back())
	bar.add_child(back)
	var t := Widgets.title(text, 64, UiTheme.CLOUD)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(t)
	if sub != "":
		var s := Widgets.badge(sub, UiTheme.SUN, 24)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(s)
	return bar


## 可见区域大小（基准分辨率下的画布尺寸）
func canvas_size() -> Vector2:
	return get_viewport_rect().size
