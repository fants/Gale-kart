class_name LoadingScreen
extends CanvasLayer
## 加载页：赛道主题色条纹背景、赛道名 / 英文名 / 难度、赛道线稿随进度逐段画出、转动的轮胎、随机小贴士。
## 显示入场动画后发出 shown；构建期间 set_progress 报告真实进度；构建完成后调用 finish() 走满进度并淡出。

signal shown

const TIPS: Array[String] = [
	"漂移后松开，趁提示出现时再按一次 ↑，触发瞬间加速（小喷）！",
	"倒计时 GO 出现的瞬间按下 ↑ 起步加速；提前按住会抢跑哦。",
	"紧跟在前车正后方一会儿，就能获得尾流加速。",
	"道具赛中按 Q 可以交换两个道具槽里的道具。",
	"竞速赛里漂移会积攒集气条，满一格得到一个氮气，最多存 2 个。",
	"橙色箭头是加速带，压上去立刻提速；跳台可以飞越障碍。",
	"被导弹锁定时屏幕边缘会泛红，赶紧用天使护盾挡住！",
	"卡住了？按 R 复位回到赛道上。",
	"按 C 切换远 / 近视角，按 H 隐藏 HUD，录视频更干净。",
	"冰雪乐园的路面很滑，提前漂移入弯更稳。",
	"计时赛会保存你的最佳一局，下次作为幽灵车陪你跑。",
	"雷暴只有落后时才可能抽到，能让领先的车全部眩晕。",
]

var ui: Control
var thumb: Widgets.TrackThumb
var bar: ProgressBar
var pct: Label
var wheel: Control
var _p := 0.0
var _target := 0.03
var _t := 0.0
var _finishing := false


## Tire 轮胎图标（转动）
class Tire extends Control:
	var angle := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(76, 76)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 3.0
		draw_circle(c, r, UiTheme.INK)
		draw_circle(c, r - 4.0, Color("#3A3F52"))
		for i in 12:
			var a := angle + TAU * i / 12.0
			draw_line(c + Vector2(cos(a), sin(a)) * (r - 11.0), c + Vector2(cos(a), sin(a)) * (r - 4.0), UiTheme.INK, 3.0, true)
		Widgets.draw_disc(self, c, r * 0.52, UiTheme.SUN, 3.0)
		for i in 5:
			var a := angle + TAU * i / 5.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.5, UiTheme.INK, 4.0, true)
		Widgets.draw_disc(self, c, r * 0.16, UiTheme.RED, 3.0)


func setup(sel: Dictionary, gp: Dictionary) -> void:
	layer = 40
	var def := TracksData.track_by_id(str(sel.get("track_id", "village")))
	var theme := ThemesData.get_theme(str(def["theme"]))
	var sky: Dictionary = theme["sky"]
	var ground: Dictionary = theme["ground"]
	var road: Dictionary = theme["road"]

	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.build()
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ui)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/ui_loading.gdshader")
	mat.set_shader_parameter("color_a", Color(str(sky["top"])))
	mat.set_shader_parameter("color_b", Color(str(sky["horizon"])))
	var art := UiArt.track_art(str(def["id"]))
	if art != null:
		mat.set_shader_parameter("use_art", true)
		mat.set_shader_parameter("art", art)
		mat.set_shader_parameter("art_aspect", float(art.get_width()) / art.get_height())
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	# 左：赛道信息
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 110
	left.offset_right = 110 + 860
	left.offset_top = -330
	left.offset_bottom = 230
	left.add_theme_constant_override("separation", 14)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(left)
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 12)
	left.add_child(badges)
	var mode := str(sel.get("mode", "speed"))
	var mode_name: String = {"speed": "竞速赛", "item": "道具赛", "time": "计时赛"}.get(mode, "竞速赛")
	if not gp.is_empty():
		var tracks: Array = gp["tracks"]
		badges.add_child(Widgets.badge(Loc.t("%s · 第 %d / %d 场") % [Loc.t(str(gp["cup_name"])), int(gp["index"]) + 1, tracks.size()], UiTheme.SUN, 26))
	badges.add_child(Widgets.badge(mode_name, UiTheme.BUBBLE if mode == "speed" else (UiTheme.PINK if mode == "item" else UiTheme.MINT), 26))
	badges.add_child(Widgets.badge(Loc.t("%d 圈") % int(sel.get("laps", 3)), UiTheme.WHITE, 26))
	var name_l := Widgets.title(str(def["name"]), 128, UiTheme.SUN, false, 18)
	name_l.add_theme_constant_override("shadow_offset_y", 11)
	left.add_child(name_l)
	var en := Widgets.title("" if Loc.is_en() else str(def["en"]), 46, UiTheme.CLOUD, true, 10)
	left.add_child(en)
	var stars_row := HBoxContainer.new()
	stars_row.add_theme_constant_override("separation", 14)
	left.add_child(stars_row)
	stars_row.add_child(Widgets.label("难度", 30, UiTheme.CLOUD))
	(stars_row.get_child(0) as Label).add_theme_color_override("font_outline_color", UiTheme.INK)
	(stars_row.get_child(0) as Label).add_theme_constant_override("outline_size", 8)
	stars_row.add_child(Widgets.star_rating(int(def["difficulty"]), 3, 40.0))
	var blurb := Widgets.panel("GlassPanel")
	blurb.custom_minimum_size = Vector2(760, 0)
	blurb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bl := Widgets.label(str(def["blurb"]), 30)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_child(bl)
	left.add_child(blurb)

	# 右：赛道线稿
	var card := Widgets.panel("CardPanel")
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	card.offset_left = -110 - 720
	card.offset_right = -110
	card.offset_top = -320
	card.offset_bottom = 200
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.rotation = deg_to_rad(2.0)
	ui.add_child(card)
	thumb = Widgets.TrackThumb.new(str(def["id"]))
	thumb.bg_color = Color(str(ground["base"]))
	thumb.line_color = Color(str(road["base"])).lightened(0.35)
	thumb.line_w = 14.0
	thumb.pad = 40.0
	thumb.progress = 0.0
	card.add_child(thumb)

	ui.add_child(Widgets.pin(Widgets.creator_badge(1.1), Control.PRESET_TOP_RIGHT, Vector2(110, 56)))

	# 底部：小贴士 + 进度
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 110
	bottom.offset_right = -110
	bottom.offset_top = -200
	bottom.offset_bottom = -70
	bottom.add_theme_constant_override("separation", 40)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	var tip := Widgets.panel("GlassPanel")
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(tip)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 20)
	tip.add_child(trow)
	var tb := Widgets.badge("小贴士", UiTheme.SUN, 26)
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(tb)
	var tip_text := TIPS[randi() % TIPS.size()]
	if randf() < 0.25:
		tip_text = Loc.t("关注 %s，看更多疾风卡丁的比赛视频！") % Credits.tag()
	var tl := Widgets.label(tip_text, 30)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(tl)

	var prog := VBoxContainer.new()
	prog.custom_minimum_size = Vector2(480, 0)
	prog.alignment = BoxContainer.ALIGNMENT_CENTER
	prog.add_theme_constant_override("separation", 10)
	bottom.add_child(prog)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 16)
	prog.add_child(prow)
	wheel = Tire.new()
	prow.add_child(wheel)
	var ll := Widgets.title("赛道加载中…", 40, UiTheme.CLOUD, false, 10)
	ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(ll)
	pct = Widgets.title("0%", 34, UiTheme.SUN, true, 9)
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pct)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(480, 30)
	bar.max_value = 100.0
	prog.add_child(bar)

	# 入场：整体淡入，左右两块滑入
	ui.modulate.a = 0.0
	left.position.x -= 80
	card.position.x += 80
	var tw := create_tween().set_parallel()
	tw.tween_property(ui, "modulate:a", 1.0, 0.25)
	tw.tween_property(left, "position:x", left.position.x + 80, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position:x", card.position.x - 80, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.05)
	tw.chain().tween_callback(func() -> void: shown.emit())


func _process(dt: float) -> void:
	_t += dt
	var speed := 2.4 if _finishing else 1.2
	_p = move_toward(_p, _target, dt * speed)
	if thumb:
		thumb.progress = _p
		thumb.queue_redraw()
	if bar:
		bar.value = _p * 100.0
		pct.text = "%d%%" % int(round(_p * 100.0))
	if wheel:
		(wheel as Tire).angle += dt * 9.0
		wheel.queue_redraw()


## 构建进度（0..1，只增不减）；显示值平滑追赶
func set_progress(p: float) -> void:
	_target = maxf(_target, clampf(p, 0.0, 1.0) * 0.97)


## 构建完成：进度走满后淡出并销毁
func finish() -> void:
	_finishing = true
	_target = 1.0
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(ui, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
