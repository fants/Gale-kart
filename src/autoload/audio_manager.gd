extends Node
## 音频管理器（桩）：Task 7 会替换成完整实现。接口在这里先固定下来，调用方可以放心使用。


func play(_name: String, _opts := {}) -> void:
	pass


func play_at(_name: String, _pos: Vector3, _listener: Transform3D, _opts := {}) -> void:
	pass


func play_music(_name: String, _fade := 0.8) -> void:
	pass


func stop_music(_fade := 0.5) -> void:
	pass


func set_music_tempo(_scale: float) -> void:
	pass


func set_paused(_p: bool) -> void:
	pass


func set_volumes(_music: float, _sfx: float) -> void:
	pass


func set_muted(_m: bool) -> void:
	pass


func update_engine(_p: Dictionary) -> void:
	pass


func stop_engine() -> void:
	pass


func make_engine_3d() -> AudioStreamPlayer3D:
	return null
