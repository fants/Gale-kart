class_name Hud
extends CanvasLayer
## 比赛 HUD（桩）：Task 6 实现完整版。


func setup(_race: RaceSim) -> void:
	name = "Hud"


func update_view(_dt: float, _race: RaceSim) -> void:
	pass


## 中央大字（倒计时、GO、最后一圈、FINISH）；opts: {hold: bool, cn: bool, color: Color}
func big(_text: String, _opts := {}) -> void:
	pass


## 中央小字提示
func sub(_text: String, _color := Color.WHITE) -> void:
	pass


## 全屏闪白（雷暴）
func flash() -> void:
	pass


func add_lap_time(_lap: int, _time: float, _best: bool) -> void:
	pass


func set_hud_visible(_v: bool) -> void:
	pass


## 小喷提示（松开漂移后的窗口内显示「↑」）
func show_instant_cue(_on: bool) -> void:
	pass
