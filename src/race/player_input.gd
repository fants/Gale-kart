class_name PlayerInput
extends Node
## 玩家输入：InputMap（键盘 + 手柄）→ KartInput。手柄摇杆有死区与响应曲线；窗口失焦时清空；手柄震动。

const STICK_DEADZONE := 0.12
const STICK_EXPONENT := 1.4

var input := KartInput.new()
var focused := true
## 本帧的界面类边沿
var camera_pressed := false
var pause_pressed := false
var hide_hud_pressed := false
var mute_pressed := false
var drift_pressed := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		input.clear_all()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true


## 每帧调用一次，返回本帧输入快照
func poll() -> KartInput:
	camera_pressed = false
	pause_pressed = false
	hide_hud_pressed = false
	mute_pressed = false
	drift_pressed = false
	if not focused:
		input.clear_all()
		return input
	input.throttle = Input.get_action_strength("accelerate")
	input.brake = Input.get_action_strength("brake")
	var digital := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
		digital -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
		digital += 1.0
	var analog := 0.0
	for dev in Input.get_connected_joypads():
		var raw := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
		if absf(raw) > STICK_DEADZONE:
			var m := (absf(raw) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
			analog = signf(raw) * pow(clampf(m, 0.0, 1.0), STICK_EXPONENT)
			break
	input.steer = clampf(digital if digital != 0.0 else analog, -1.0, 1.0)
	input.drift = Input.is_action_pressed("drift")
	input.use = Input.is_action_pressed("use_item")
	input.throttle_pressed = Input.is_action_just_pressed("accelerate")
	input.use_pressed = Input.is_action_just_pressed("use_item")
	input.swap_pressed = Input.is_action_just_pressed("swap_item")
	input.respawn_pressed = Input.is_action_just_pressed("respawn")
	drift_pressed = Input.is_action_just_pressed("drift")
	camera_pressed = Input.is_action_just_pressed("camera")
	pause_pressed = Input.is_action_just_pressed("pause")
	hide_hud_pressed = Input.is_action_just_pressed("hide_hud")
	mute_pressed = Input.is_action_just_pressed("mute")
	return input


## 手柄震动（weak / strong 为 0..1，dur 秒）
func vibrate(weak: float, strong: float, dur: float) -> void:
	for dev in Input.get_connected_joypads():
		Input.start_joy_vibration(dev, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), dur)
