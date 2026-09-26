class_name RaceWorld
extends Node3D
## 一场比赛的 3D 世界：环境（天空 / 雾 / 光）、地形、赛道、场景物件。

var track: TrackData
var terrain: TerrainData
var env: WorldEnvironment
var sun: DirectionalLight3D
var track_mesh: TrackMesh
var terrain_mesh: TerrainMesh
var scenery: Scenery
var build_log := {}


func build(p_track: TrackData, p_terrain: TerrainData, quality: String, _mode: String) -> void:
	var qp := EnvironmentFactory.quality_preset(quality)
	for step in _base_steps(p_track, p_terrain, quality, TerrainMesh.compute(p_track, p_terrain, qp["terrain_cell"])):
		step.call()
	var t2 := Time.get_ticks_msec()
	scenery = Scenery.new()
	add_child(scenery)
	scenery.build(track, terrain, quality)
	_done(t2)


## 分帧构建：terrain_data 为 TerrainMesh.compute 的结果（可在工作线程里预先算好）；
## 每步之后 await breath.call()，progress(0..1) 报告进度
func build_async(p_track: TrackData, p_terrain: TerrainData, quality: String, terrain_data: Dictionary,
		breath: Callable, progress: Callable) -> void:
	var base := _base_steps(p_track, p_terrain, quality, terrain_data)
	for i in base.size():
		base[i].call()
		progress.call(0.35 * float(i + 1) / base.size())
		await breath.call()
	var t2 := Time.get_ticks_msec()
	scenery = Scenery.new()
	add_child(scenery)
	var sc := scenery.prepare(track, terrain, quality)
	for i in sc.size():
		sc[i].call()
		progress.call(0.35 + 0.65 * float(i + 1) / sc.size())
		await breath.call()
	_done(t2)


var _t0 := 0


## 环境、地形、赛道（场景物件另算）
func _base_steps(p_track: TrackData, p_terrain: TerrainData, quality: String, terrain_data: Dictionary) -> Array[Callable]:
	name = "RaceWorld"
	track = p_track
	terrain = p_terrain
	_t0 = Time.get_ticks_msec()
	var steps: Array[Callable] = [
		func() -> void:
			var e := EnvironmentFactory.create(track.theme, quality)
			env = e["env"]
			sun = e["sun"]
			add_child(env)
			add_child(sun),
		func() -> void:
			terrain_mesh = TerrainMesh.new()
			add_child(terrain_mesh)
			terrain_mesh.apply(track, terrain, terrain_data)
			build_log["terrain_ms"] = terrain_mesh.build_ms,
	]
	# 赛道网格拆成多步
	track_mesh = TrackMesh.new()
	var tm_steps := track_mesh.steps(track, terrain)
	steps.append(func() -> void: add_child(track_mesh))
	for st in tm_steps:
		steps.append(func() -> void:
			var t1 := Time.get_ticks_usec()
			st.call()
			build_log["track_ms"] = int(build_log.get("track_ms", 0)) + (Time.get_ticks_usec() - t1) / 1000)
	return steps


func _done(scenery_t0: int) -> void:
	build_log["scenery_ms"] = Time.get_ticks_msec() - scenery_t0
	build_log["total_ms"] = Time.get_ticks_msec() - _t0


func update_view(dt: float, time: float, cam: Camera3D) -> void:
	scenery.update_view(dt, time, cam)
