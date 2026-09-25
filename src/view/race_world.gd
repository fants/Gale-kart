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
	name = "RaceWorld"
	track = p_track
	terrain = p_terrain
	var qp := EnvironmentFactory.quality_preset(quality)
	var t0 := Time.get_ticks_msec()
	var e := EnvironmentFactory.create(track.theme, quality)
	env = e["env"]
	sun = e["sun"]
	add_child(env)
	add_child(sun)
	terrain_mesh = TerrainMesh.new()
	add_child(terrain_mesh)
	terrain_mesh.build(track, terrain, qp["terrain_cell"])
	build_log["terrain_ms"] = terrain_mesh.build_ms
	var t1 := Time.get_ticks_msec()
	track_mesh = TrackMesh.new()
	add_child(track_mesh)
	track_mesh.build(track, terrain)
	build_log["track_ms"] = Time.get_ticks_msec() - t1
	var t2 := Time.get_ticks_msec()
	scenery = Scenery.new()
	add_child(scenery)
	scenery.build(track, terrain, quality)
	build_log["scenery_ms"] = Time.get_ticks_msec() - t2
	build_log["total_ms"] = Time.get_ticks_msec() - t0


func update_view(dt: float, time: float, cam: Camera3D) -> void:
	scenery.update_view(dt, time, cam)
