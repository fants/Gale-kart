class_name FirstLaunch
extends CanvasLayer
## 首次启动提示：3D 渲染器（Forward+）第一次启动要编译大量着色器（Intel Mac 上可达 40 秒以上），
## 编译期间引擎画不出任何东西。所以项目默认用轻量的兼容渲染器（OpenGL，1 秒内出窗口）启动，
## 这里显示「正在准备 3D 图形」，同时以 Forward+ 启动游戏本体（子进程）；
## 本体初始化完成后会写 user://graphics.cfg（GRAPHICS_CFG），这边看到后关闭自己。
## 之后的启动读到 graphics.cfg 直接用 Forward+，不再经过这里。
## 显卡不支持 Forward+ 时引擎会让本体退回兼容渲染器，本体会在 graphics.cfg 里记下 gale/compat_only，
## 这边同样看到文件更新后退出，以后也直接用兼容渲染器启动。

const GRAPHICS_CFG := "user://graphics.cfg"
const POLL := 0.25
## 本体窗口出来后再停留一会儿再退出，免得两个窗口之间闪黑
const HANDOFF := 1.2

var _pid := -1
var _t := 0.0
var _poll_t := 0.0
var _started_at := 0
var _done_t := -1.0
var _failed := false
var _time_label: Label
var _status: Label
var _wheel: Control


func _ready() -> void:
	layer = 50
	_build()
	_started_at = int(Time.get_unix_time_from_system())
	# 已经有 graphics.cfg（比如被删了渲染器设置以外的内容）也照样重新走一遍
	_spawn()


## 以 Forward+ 启动游戏本体：保留原来的命令行（开发时的 --path 等）和 -- 之后的用户参数
func _spawn() -> void:
	var args: Array[String] = []
	for a in OS.get_cmdline_args():
		if a.begins_with("-psn_") or a == "--rendering-method" or a == "forward_plus" or a == "gl_compatibility":
			continue
		args.append(a)
	args.append_array(["--rendering-method", "forward_plus", "--"])
	args.append_array(OS.get_cmdline_user_args())
	# 标明是本体：即使引擎退回兼容渲染器也不会再当启动器（见 Game._ready）
	args.append("--child")
	_pid = OS.create_process(OS.get_executable_path(), args)
	if _pid <= 0:
		_fail()


var _shot_done := false


func _process(dt: float) -> void:
	_t += dt
	# 调试：--launcher-shot=目录 在 3 秒时截一张图
	if not _shot_done and _t > 3.0 and Game.args.has("launcher-shot"):
		_shot_done = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(str(Game.args["launcher-shot"]).path_join("first_launch_%s.png" % Loc.lang))
		print("首次启动提示：已截图，子进程 pid=%d" % _pid)
	if _wheel:
		_wheel.rotation += dt * 6.0
	if _time_label and _done_t < 0.0 and not _failed:
		_time_label.text = Loc.t("已等待 %d 秒") % int(_t)
	if _done_t >= 0.0:
		_done_t += dt
		if _done_t > HANDOFF:
			get_tree().quit()
		return
	if _failed:
		return
	_poll_t += dt
	if _poll_t < POLL:
		return
	_poll_t = 0.0
	if _child_ready():
		_done_t = 0.0
		_status.text = Loc.t("准备完成，马上开始！")
	elif _pid > 0 and not OS.is_process_running(_pid):
		# 本体退出了却没写完成标记：3D 渲染器起不来
		if not _child_ready():
			_fail()


func _child_ready() -> bool:
	if not FileAccess.file_exists(GRAPHICS_CFG):
		return false
	return FileAccess.get_modified_time(GRAPHICS_CFG) >= _started_at


func _fail() -> void:
	_failed = true
	_status.text = Loc.t("3D 图形启动失败，请更新显卡驱动后重试。")
	_time_label.text = ""


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("#1B1F3B")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/hero/sunny.jpg")
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.55, 0.58, 0.72)
	root.add_child(art)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	center.add_child(v)
	var logo := TextureRect.new()
	logo.texture = UiArt.logo()
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(760, 330)
	v.add_child(logo)

	var card := Widgets.panel()
	card.custom_minimum_size = Vector2(1080, 0)
	v.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	card.add_child(cv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(row)
	_wheel = _Spinner.new()
	_wheel.custom_minimum_size = Vector2(72, 72)
	_wheel.pivot_offset = Vector2(36, 36)
	_wheel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_wheel)
	_status = Widgets.title(Loc.t("首次启动，正在准备 3D 图形…"), 46, UiTheme.SUN, false, 10)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status)
	var note := Widgets.label(Loc.t("只有第一次需要，大约 30～60 秒，之后启动就很快了。请稍候，不要关闭窗口。"), 26, UiTheme.INK_2)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(note)
	_time_label = Widgets.label("", 24, UiTheme.INK_2)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_time_label)


## 转圈的轮胎
class _Spinner extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 3.0
		draw_circle(c, r, UiTheme.INK)
		draw_circle(c, r - 5.0, Color("#3A3F52"))
		Widgets.draw_disc(self, c, r * 0.5, UiTheme.SUN, 3.0)
		for i in 5:
			var a := TAU * i / 5.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.48, UiTheme.INK, 4.0, true)
		Widgets.draw_disc(self, c, r * 0.15, UiTheme.RED, 3.0)
