class_name InputSetup
extends RefCounted
## 在代码里注册输入映射（键盘 + 手柄），便于集中维护。
## 刻意不用 Ctrl：macOS 上 Ctrl+方向键会切换桌面。

const KEYS := {
	"accelerate": [KEY_UP, KEY_W],
	"brake": [KEY_DOWN, KEY_S],
	"steer_left": [KEY_LEFT, KEY_A],
	"steer_right": [KEY_RIGHT, KEY_D],
	"drift": [KEY_SHIFT, KEY_J],
	"use_item": [KEY_SPACE, KEY_K],
	"swap_item": [KEY_Q, KEY_E],
	"respawn": [KEY_R],
	"camera": [KEY_C],
	"pause": [KEY_ESCAPE, KEY_P],
	"hide_hud": [KEY_H],
	"mute": [KEY_M],
	"fullscreen": [KEY_F11],
}

const PAD_BUTTONS := {
	"accelerate": [],
	"brake": [],
	"steer_left": [JOY_BUTTON_DPAD_LEFT],
	"steer_right": [JOY_BUTTON_DPAD_RIGHT],
	"drift": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER],
	"use_item": [JOY_BUTTON_A],
	"swap_item": [JOY_BUTTON_X],
	"respawn": [JOY_BUTTON_Y],
	"camera": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}

## [动作, 轴, 方向]
const PAD_AXES := [
	["accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0],
	["brake", JOY_AXIS_TRIGGER_LEFT, 1.0],
	["steer_left", JOY_AXIS_LEFT_X, -1.0],
	["steer_right", JOY_AXIS_LEFT_X, 1.0],
]


static func setup() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.2)
		for code: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
		for btn: JoyButton in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			jb.device = -1
			InputMap.action_add_event(action, jb)
	for a: Array in PAD_AXES:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[1]
		jm.axis_value = a[2]
		jm.device = -1
		InputMap.action_add_event(a[0], jm)
	# 菜单里的确认 / 返回也接受手柄
	_add_pad_button("ui_accept", JOY_BUTTON_A)
	_add_pad_button("ui_cancel", JOY_BUTTON_B)


static func _add_pad_button(action: String, btn: JoyButton) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == btn:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = btn
	jb.device = -1
	InputMap.action_add_event(action, jb)
