class_name ScreenFx
extends CanvasLayer
## 屏幕效果（桩）：Task 9 实现速度线、氮气径向模糊、锁定红边、乌云遮挡、水泡泛蓝。


func setup() -> void:
	name = "ScreenFx"
	layer = 1


## player 为玩家赛车；fov_boost 为相机当前 FOV 相对基准的增量（用于强度）
func update_view(_dt: float, _time: float, _player: KartSim) -> void:
	pass
