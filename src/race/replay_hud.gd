class_name ReplayHud
extends CanvasLayer
## 回放界面：闪烁的 REPLAY 标记、赛道名、焦点车手信息、机位与速度、进度条、操作提示。

const INK := Color("#1B1F3B")
const RED := Color("#FF4D5E")
const WHITE := Color("#F7FAFF")
const YELLOW := Color("#FFC93C")

var root: Control
var _rec: Label
var _info: Label
var _mode: Label
var _hint: Label
var _bar_bg: ColorRect
var _bar: ColorRect
var _num_font: Font


func setup(track_name: String) -> void:
	name = "ReplayHud"
	layer = 6
	_num_font = load("res://assets/fonts/Bungee-Tabular.ttf")  # 等宽数字：跑秒 / 速度不抖
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# 上下电影黑边
	for top: bool in [true, false]:
		var band := ColorRect.new()
		band.color = Color(0, 0, 0, 0.85)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(band)
		band.anchor_left = 0.0
		band.anchor_right = 1.0
		band.anchor_top = 0.0 if top else 1.0
		band.anchor_bottom = 0.0 if top else 1.0
		band.offset_left = 0.0
		band.offset_right = 0.0
		band.offset_top = 0.0 if top else -70.0
		band.offset_bottom = 70.0 if top else 0.0
	root.add_child(Widgets.pin(Widgets.creator_badge(0.85, false), Control.PRESET_CENTER_TOP, Vector2(0, 8)))
	_rec = _label("● REPLAY", 34, RED, true)
	_rec.position = Vector2(40, 14)
	root.add_child(_rec)
	var tn := _label(track_name, 30, WHITE, false)
	tn.position = Vector2(290, 18)
	root.add_child(tn)
	_mode = _label("", 26, YELLOW, false)
	_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_mode)
	_mode.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mode.offset_left = -640
	_mode.offset_right = -40
	_mode.offset_top = 20
	_info = _label("", 30, WHITE, false)
	root.add_child(_info)
	_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info.offset_left = 40
	_info.offset_top = -62
	_info.offset_right = 900
	_hint = _label("1–4 机位 · ←→ 切换车手 · 空格 暂停 · [ ] 速度 · H 隐藏 · Esc 退出", 20, Color(WHITE, 0.75), false)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_hint)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -900
	_hint.offset_right = -40
	_hint.offset_top = -52
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.15)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_bg)
	_bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bg.offset_top = -72
	_bar_bg.offset_bottom = -68
	_bar = ColorRect.new()
	_bar.color = RED
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar)


func _label(text: String, size: int, color: Color, num: bool) -> Label:
	var l := Label.new()
	l.text = text
	if num:
		l.add_theme_font_override("font", _num_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func update_view(progress: float, focus: KartSim, cam_name: String, speed: float, paused: bool) -> void:
	_rec.modulate.a = 1.0 if paused else (0.45 + 0.55 * absf(sin(Time.get_ticks_msec() * 0.004)))
	_rec.text = "❚❚ PAUSED" if paused else "● REPLAY"
	_mode.text = "%s   ×%s" % [cam_name, str(speed) if speed != int(speed) else str(int(speed))]
	if focus:
		_info.text = "%s · 第 %d 名 · %d km/h" % [focus.name, focus.rank, int(focus.speed * 3.6 * 1.4)]
	_bar.size = Vector2(_bar_bg.size.x * clampf(progress, 0.0, 1.0), 4)


func set_ui_visible(v: bool) -> void:
	root.visible = v
