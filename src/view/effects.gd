class_name Effects
extends Node3D
## 粒子特效（桩）：Task 9 实现完整版（GPUParticles3D + emit_particle）。

var skids: SkidMarks
var _rate_acc := {}


func setup(_quality: String, _theme: Dictionary) -> void:
	name = "Effects"
	skids = SkidMarks.new()
	skids.name = "SkidMarks"
	add_child(skids)


## kind: boost wall kart land shards explosion splash banana shield thunder respawn confetti instant spark_hit
func burst(_kind: String, _pos: Vector3, _opts := {}) -> void:
	pass


func smoke(_pos: Vector3, _vel: Vector3, _scale := 1.0) -> void:
	pass


## tier 0 白 / 1 蓝
func drift_spark(_pos: Vector3, _tier: int) -> void:
	pass


## kind: nitro instant pad start draft magnet
func flame(_pos: Vector3, _dir: Vector3, _kind: String) -> void:
	pass


func dust(_pos: Vector3, _vel: Vector3) -> void:
	pass


func wind(_pos: Vector3, _dir: Vector3) -> void:
	pass


## 按速率（个/秒）计算本帧应发射的粒子数（带小数累积）
func rate_count(key: String, rate: float, dt: float) -> int:
	var acc: float = _rate_acc.get(key, 0.0) + rate * dt
	var c := int(acc)
	_rate_acc[key] = acc - c
	return c
