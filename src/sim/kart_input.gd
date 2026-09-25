class_name KartInput
extends RefCounted
## 一辆车的输入快照。*_pressed 为按下边沿，要保留到被某个物理子步消费为止。

var throttle := 0.0
var brake := 0.0
## -1 左 .. 1 右
var steer := 0.0
var drift := false
var use := false
var throttle_pressed := false
var use_pressed := false
var swap_pressed := false
var respawn_pressed := false


## 复制连续量；边沿与已有的边沿取或（高刷新率下一帧可能不足一个子步）
func copy_from(o: KartInput, keep_edges := true) -> void:
	throttle = o.throttle
	brake = o.brake
	steer = o.steer
	drift = o.drift
	use = o.use
	if keep_edges:
		throttle_pressed = throttle_pressed or o.throttle_pressed
		use_pressed = use_pressed or o.use_pressed
		swap_pressed = swap_pressed or o.swap_pressed
		respawn_pressed = respawn_pressed or o.respawn_pressed
	else:
		throttle_pressed = o.throttle_pressed
		use_pressed = o.use_pressed
		swap_pressed = o.swap_pressed
		respawn_pressed = o.respawn_pressed


func clear_edges() -> void:
	throttle_pressed = false
	use_pressed = false
	swap_pressed = false
	respawn_pressed = false


func clear_all() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	drift = false
	use = false
	clear_edges()
