class_name ScreenFx
extends CanvasLayer
## 屏幕效果（layer 1，HUD 在更上层）：两张全屏 ColorRect。
##   Warp（radial_blur.gdshader，读屏幕纹理）：氮气径向模糊、水泡波动折射、乌云时镜头水珠；
##   Overlay（speed_lines.gdshader）：速度线、氮气边缘蓝光、乌云压暗 + 雨丝、水泡泛蓝、导弹锁定红边。
## 各强度按玩家状态平滑过渡；不需要时整层隐藏（Warp 隐藏时没有屏幕拷贝开销）。

const OVERLAY_SHADER := preload("res://assets/shaders/speed_lines.gdshader")
const WARP_SHADER := preload("res://assets/shaders/radial_blur.gdshader")

var _warp: ColorRect
var _overlay: ColorRect
var _wmat: ShaderMaterial
var _omat: ShaderMaterial
var _speed := 0.0
var _boost := 0.0
var _blur := 0.0
var _lock := 0.0
var _cloud := 0.0
var _bubble := 0.0
## 前几帧让两层都显示一次（强度为 0，画面不变），提前编译着色器
var _warm := 3


func setup() -> void:
	name = "ScreenFx"
	layer = 1
	_warp = _make_rect("Warp", WARP_SHADER)
	_wmat = _warp.material as ShaderMaterial
	_overlay = _make_rect("Overlay", OVERLAY_SHADER)
	_omat = _overlay.material as ShaderMaterial


func _make_rect(rect_name: String, shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	r.name = rect_name
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	r.visible = false
	add_child(r)
	return r


## player 为玩家赛车（为 null 时所有效果淡出）
func update_view(dt: float, _time: float, player: KartSim) -> void:
	var speed_t := 0.0
	var boost_t := 0.0
	var blur_t := 0.0
	var lock_t := 0.0
	var cloud_t := 0.0
	var bubble_t := 0.0
	if player != null:
		# 普通极速（约 36 m/s）时速度线几乎看不见，加速时明显
		speed_t = clampf((player.speed - 27.0) / 22.0, 0.0, 1.0) * 0.45
		if player.is_boosting():
			match player.boost_kind:
				"nitro", "start":
					speed_t = maxf(speed_t, 1.0)
					boost_t = 1.0
					blur_t = 1.0
				"pad":
					speed_t = maxf(speed_t, 0.75)
					blur_t = 0.45
				"instant":
					speed_t = maxf(speed_t, 0.6)
					boost_t = 0.5
				"magnet":
					speed_t = maxf(speed_t, 0.6)
				_:
					speed_t = maxf(speed_t, 0.5)
		if player.is_disabled() or player.finished:
			speed_t *= 0.3
			blur_t = 0.0
		lock_t = 1.0 if player.locked_by > 0.0 else 0.0
		if player.cloud > 0.0:
			cloud_t = clampf(player.cloud / 0.6, 0.0, 1.0)
		if player.bubble > 0.0:
			bubble_t = clampf(player.bubble / 0.15, 0.0, 1.0)
	_speed = MathX.damp(_speed, speed_t, 7.0 if speed_t > _speed else 3.0, dt)
	_boost = MathX.damp(_boost, boost_t, 6.0 if boost_t > _boost else 3.0, dt)
	_blur = MathX.damp(_blur, blur_t, 6.0 if blur_t > _blur else 4.0, dt)
	_lock = MathX.damp(_lock, lock_t, 10.0 if lock_t > _lock else 4.0, dt)
	_cloud = MathX.damp(_cloud, cloud_t, 3.0 if cloud_t > _cloud else 2.0, dt)
	_bubble = MathX.damp(_bubble, bubble_t, 8.0 if bubble_t > _bubble else 5.0, dt)

	var warming := _warm > 0
	_warm = maxi(_warm - 1, 0)
	var warp_on := _blur > 0.01 or _bubble > 0.01 or _cloud > 0.01 or warming
	_warp.visible = warp_on
	if warp_on:
		_wmat.set_shader_parameter("blur_amt", _blur)
		_wmat.set_shader_parameter("bubble_amt", _bubble)
		_wmat.set_shader_parameter("rain_amt", _cloud)
	var over_on := _speed > 0.01 or _boost > 0.01 or _lock > 0.01 or _cloud > 0.01 or _bubble > 0.01 or warming
	_overlay.visible = over_on
	if over_on:
		_omat.set_shader_parameter("speed_amt", _speed)
		_omat.set_shader_parameter("boost_amt", _boost)
		_omat.set_shader_parameter("lock_amt", _lock)
		_omat.set_shader_parameter("cloud_amt", _cloud)
		_omat.set_shader_parameter("bubble_amt", _bubble)


## 立即清除所有效果（切换镜头 / 回放跳转时用）
func reset() -> void:
	_speed = 0.0
	_boost = 0.0
	_blur = 0.0
	_lock = 0.0
	_cloud = 0.0
	_bubble = 0.0
	_warp.visible = false
	_overlay.visible = false
