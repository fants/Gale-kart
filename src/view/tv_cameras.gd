class_name TvCameras
extends RefCounted
## 电视转播机位：沿赛道每 60–90 m 放一个，位于弯道外侧、护墙外 6–9 m、高 3–8 m。
## 回放时选离焦点车最近的前方机位，车驶过一段距离后切到下一个。

var track: TrackData
## [{s, pos: Vector3}]
var cams: Array[Dictionary] = []
var current := -1


func _init(p_track: TrackData, terrain: TerrainData) -> void:
	track = p_track
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var s := 0.0
	var side := 1.0
	while s < track.n:
		var i := int(s) % track.n
		# 放在弯道外侧：曲率正（左转）时外侧在右
		var c := track.curv[i]
		if absf(c) > 0.004:
			side = 1.0 if c > 0.0 else -1.0
		else:
			side = -side
		var lat := side * (track.wall_offset + rng.randf_range(6.0, 9.0))
		var p := track.point_at(s, lat)
		var ground := maxf(terrain.height_at(p.x, p.z), p.y)
		p.y = ground + rng.randf_range(3.0, 8.0)
		cams.append({"s": s, "pos": p})
		s += rng.randf_range(60.0, 90.0) / track.spacing


## 为位于赛道位置 ks 的车选机位：优先它前方最近的；车越过机位 25 m 后换下一个
func pick(ks: float) -> Dictionary:
	if cams.is_empty():
		return {}
	var n := float(track.n)
	if current >= 0:
		var ds := fposmod(float(cams[current]["s"]) - ks + n * 0.5, n) - n * 0.5
		if ds > -25.0 / track.spacing and ds < 110.0 / track.spacing:
			return cams[current]
	var best := 0
	var best_ds := INF
	for i in cams.size():
		var ds := fposmod(float(cams[i]["s"]) - ks, n)
		if ds < best_ds:
			best_ds = ds
			best = i
	current = best
	return cams[current]
