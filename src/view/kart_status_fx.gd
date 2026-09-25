class_name KartStatusFx
extends Node3D
## 车身状态特效（桩）：护盾、水泡、眩晕星星、乌云、飞碟、磁铁、锁定标记等。Task 9 实现完整版。
## KartView 每帧调用 update_view；lift 为车身当前抬升高度（水泡上浮）。

var kart: KartSim


func setup(p_kart: KartSim) -> void:
	kart = p_kart


func update_view(_dt: float, _time: float, _lift: float) -> void:
	pass
