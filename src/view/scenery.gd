class_name Scenery
extends Node3D
## 场景物件与主题装饰（桩）：Task 8 实现完整版（Kenney 模型 MultiMesh 批量摆放、地标、起点门架、天气粒子、河流水面等）。


func build(_track: TrackData, _terrain: TerrainData, _quality: String, _seed := 3) -> void:
	name = "Scenery"


func update_view(_dt: float, _time: float, _cam: Camera3D) -> void:
	pass
