class_name UiTheme
extends RefCounted
## 糖果贴纸风全局主题：配色、字体、StyleBox 工厂，以及代码生成的 Theme。
## 墨蓝粗描边 + 大圆角 + 硬投影（向下偏移的墨蓝阴影）；中文用 ZCOOL KuaiLe，数字与英文标题用 Bungee。

const INK := Color("#1B1F3B")
const INK_2 := Color("#3A3F66")
const SUN := Color("#FFC93C")
const SUN_DEEP := Color("#F2A81D")
const SUN_LIGHT := Color("#FFF1C2")
const BUBBLE := Color("#3EC6FF")
const BUBBLE_LIGHT := Color("#8FDEFF")
const RED := Color("#FF4D5E")
const MINT := Color("#45E3A6")
const CLOUD := Color("#F7FAFF")
const SKY_PALE := Color("#E3F5FF")
const PINK := Color("#FF7FD1")
const GRAPE := Color("#9B6BFF")
const WHITE := Color("#FFFFFF")
const GRAY := Color("#C9D2E3")
const LINE := Color(0.106, 0.122, 0.231, 0.14)

## 名次配色：金 / 银 / 铜
const GOLD := Color("#FFC93C")
const SILVER := Color("#CFDDEE")
const BRONZE := Color("#F0A96B")

const FONT_CN_PATH := "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"
const FONT_NUM_PATH := "res://assets/fonts/Bungee-Regular.ttf"

## 描边粗细、圆角、投影（基准分辨率 1920×1080）
const BORDER := 3
const RADIUS := 18
const SHADOW := 5

static var _theme: Theme = null
static var _font_cn: Font = null
static var _font_num: Font = null


static func font_cn() -> Font:
	if _font_cn == null:
		_font_cn = load(FONT_CN_PATH) as Font
	return _font_cn


static func font_num() -> Font:
	if _font_num == null:
		_font_num = load(FONT_NUM_PATH) as Font
	return _font_num


## 圆角描边盒子；shadow > 0 时画向下偏移的硬投影
static func box(bg: Color, radius := RADIUS, border := BORDER, border_color := INK, shadow := SHADOW,
		margin := Vector4(20, 12, 20, 14)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.set_border_width_all(border)
	s.border_color = border_color
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = INK
		s.shadow_size = 1
		s.shadow_offset = Vector2(0, shadow)
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	return s


## 聚焦框：泡泡蓝外圈
static func focus_ring(radius := RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_border_width_all(4)
	s.border_color = BUBBLE
	s.set_corner_radius_all(radius + 7)
	s.corner_detail = 10
	s.set_expand_margin_all(7)
	s.anti_aliasing = true
	return s


static func empty(margin := 0.0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


## 带墨线描边的实心圆（滑条把手）
static func circle_texture(d: int, fill: Color, border: Color, bw: float) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var outer := clampf(c - r + 0.5, 0.0, 1.0)
			var inner := clampf(c - bw - r + 0.5, 0.0, 1.0)
			var col := border.lerp(fill, inner)
			col.a *= outer
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## 名次颜色（1 金 / 2 银 / 3 铜，其余云白）
static func rank_color(rank: int) -> Color:
	match rank:
		1:
			return GOLD
		2:
			return SILVER
		3:
			return BRONZE
	return WHITE


## 按钮类主题：normal / hover / pressed / hover_pressed / disabled / focus 六种状态
static func _button_type(t: Theme, type: String, base: String, bg: Color, hover: Color, pressed: Color,
		radius: int, shadow: int, margin: Vector4, font_size: int, pressed_border := BORDER) -> void:
	if base != "":
		t.set_type_variation(type, base)
	t.set_stylebox("normal", type, box(bg, radius, BORDER, INK, shadow, margin))
	t.set_stylebox("hover", type, box(hover, radius, BORDER, INK, shadow, margin))
	t.set_stylebox("pressed", type, box(pressed, radius, pressed_border, INK, shadow, margin))
	t.set_stylebox("hover_pressed", type, box(pressed.lightened(0.12), radius, pressed_border, INK, shadow, margin))
	var dis := box(Color("#E4E9F2"), radius, BORDER, Color(INK, 0.35), 0, margin)
	t.set_stylebox("disabled", type, dis)
	t.set_stylebox("focus", type, focus_ring(radius))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, INK)
	t.set_color("font_disabled_color", type, Color(INK, 0.35))
	t.set_font_size("font_size", type, font_size)
	t.set_constant("h_separation", type, 14)
	t.set_constant("icon_max_width", type, 0)


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font_cn()
	t.default_font_size = 26

	# ———— 按钮 ————
	_button_type(t, "Button", "", WHITE, SKY_PALE, SUN, RADIUS, SHADOW, Vector4(26, 12, 26, 15), 32)
	_button_type(t, "PrimaryButton", "Button", SUN, Color("#FFD766"), SUN_DEEP, RADIUS, SHADOW, Vector4(30, 14, 30, 17), 36)
	_button_type(t, "DangerButton", "Button", Color("#FFE1E4"), Color("#FFC9CF"), RED, RADIUS, SHADOW, Vector4(26, 12, 26, 15), 32)
	_button_type(t, "ChipButton", "Button", WHITE, SKY_PALE, BUBBLE, 40, 4, Vector4(24, 9, 24, 12), 28)
	_button_type(t, "CardButton", "Button", WHITE, SKY_PALE, SUN_LIGHT, 20, SHADOW, Vector4(12, 12, 12, 12), 26, 4)
	_button_type(t, "IconButton", "Button", WHITE, SKY_PALE, SUN, 16, 4, Vector4(10, 10, 10, 10), 28)
	_button_type(t, "TabButton", "Button", Color(WHITE, 0.0), Color(WHITE, 0.6), SUN, 14, 0, Vector4(26, 8, 26, 10), 30)
	# 标签页未选中时没有描边
	t.set_stylebox("normal", "TabButton", box(Color(WHITE, 0.0), 14, 0, INK, 0, Vector4(26, 8, 26, 10)))
	t.set_stylebox("hover", "TabButton", box(Color(WHITE, 0.75), 14, 0, INK, 0, Vector4(26, 8, 26, 10)))
	t.set_color("font_color", "TabButton", INK_2)
	# 开关：自绘，只保留聚焦框
	t.set_type_variation("SwitchButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "SwitchButton", empty())
	t.set_stylebox("focus", "SwitchButton", focus_ring(28))

	# ———— 面板 ————
	var panel := box(CLOUD, 26, BORDER, INK, 8, Vector4(28, 24, 28, 28))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", box(WHITE, 20, BORDER, INK, SHADOW, Vector4(18, 14, 18, 16)))
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", box(SKY_PALE, 18, BORDER, INK, 0, Vector4(16, 12, 16, 12)))
	t.set_type_variation("InkPanel", "PanelContainer")
	t.set_stylebox("panel", "InkPanel", box(Color(INK, 0.86), 18, 0, INK, 0, Vector4(18, 10, 18, 12)))
	t.set_type_variation("TabsPanel", "PanelContainer")
	t.set_stylebox("panel", "TabsPanel", box(SKY_PALE, 18, BORDER, INK, 0, Vector4(6, 6, 6, 6)))
	t.set_type_variation("GlassPanel", "PanelContainer")
	t.set_stylebox("panel", "GlassPanel", box(Color(CLOUD, 0.9), 26, BORDER, INK, 8, Vector4(28, 24, 28, 28)))

	# ———— 文字 ————
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 26)
	t.set_constant("line_spacing", "Label", 4)
	_label_type(t, "TitleLabel", 72, SUN, 14, 7)
	_label_type(t, "HeadingLabel", 48, CLOUD, 12, 6)
	_label_type(t, "LightLabel", 30, CLOUD, 9, 4)
	t.set_type_variation("SectionLabel", "Label")
	t.set_font_size("font_size", "SectionLabel", 30)
	t.set_color("font_color", "SectionLabel", INK)
	t.set_type_variation("NoteLabel", "Label")
	t.set_font_size("font_size", "NoteLabel", 22)
	t.set_color("font_color", "NoteLabel", INK_2)
	t.set_type_variation("NumLabel", "Label")
	t.set_font("font", "NumLabel", font_num())
	t.set_font_size("font_size", "NumLabel", 28)
	t.set_color("font_color", "NumLabel", INK)

	# ———— 滑条 ————
	t.set_stylebox("slider", "HSlider", box(WHITE, 40, BORDER, INK, 0, Vector4(0, 9, 0, 9)))
	t.set_stylebox("grabber_area", "HSlider", box(BUBBLE, 40, BORDER, INK, 0, Vector4(0, 9, 0, 9)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(BUBBLE_LIGHT, 40, BORDER, INK, 0, Vector4(0, 9, 0, 9)))
	t.set_icon("grabber", "HSlider", circle_texture(44, SUN, INK, 3.5))
	t.set_icon("grabber_highlight", "HSlider", circle_texture(48, Color("#FFE08A"), INK, 3.5))
	t.set_icon("grabber_disabled", "HSlider", circle_texture(44, GRAY, INK, 3.5))
	t.set_stylebox("focus", "HSlider", focus_ring(24))

	# ———— 进度条 ————
	t.set_stylebox("background", "ProgressBar", box(WHITE, 40, BORDER, INK, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", box(SUN, 40, BORDER, INK, 0, Vector4(0, 0, 0, 0)))
	t.set_font_size("font_size", "ProgressBar", 1)

	# ———— 滚动条 ————
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(INK, 0.08)
	sc.set_corner_radius_all(8)
	sc.content_margin_left = 6
	sc.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", sc)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(INK, 0.45)
	grab.set_corner_radius_all(8)
	grab.content_margin_left = 6
	grab.content_margin_right = 6
	t.set_stylebox("grabber", "VScrollBar", grab)
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(INK, 0.7)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	# ———— 提示框 ————
	t.set_stylebox("panel", "TooltipPanel", box(INK, 12, 0, INK, 0, Vector4(12, 8, 12, 10)))
	t.set_color("font_color", "TooltipLabel", CLOUD)
	t.set_font_size("font_size", "TooltipLabel", 22)

	_theme = t
	return t


static func _label_type(t: Theme, type: String, size: int, color: Color, outline: int, shadow: int) -> void:
	t.set_type_variation(type, "Label")
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, color)
	t.set_color("font_outline_color", type, INK)
	t.set_constant("outline_size", type, outline)
	t.set_color("font_shadow_color", type, INK)
	t.set_constant("shadow_offset_x", type, 0)
	t.set_constant("shadow_offset_y", type, shadow)
	t.set_constant("shadow_outline_size", type, outline)
