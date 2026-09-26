class_name SceneryPlacer
extends RefCounted
## 摆放器：生成候选点并检查规则——离赛道中心线 > wall_offset + 半径 + 间隙（高大物件间隙 6 m，其余 2 m）、
## 不在河道里、不与已占位物件重叠、在地形范围内；贴地高度取占地范围内的最低点（大物件不悬空）。

const OCC_CELL := 12.0

var track: TrackData
var terrain: TerrainData
var rng: RandomNumberGenerator
var _occ := {}
var _bmin := Vector2.ZERO
var _bmax := Vector2.ZERO
## 起点附近的「航拍净空区」：半径内不放高物件，免得挡开场航拍
var start_pos := Vector3.ZERO
var start_clear := 35.0
## 稀疏采样的中心线（每 8 个取 1），用于远距离的粗略距离 / 朝向查询
var _sub := PackedVector3Array()


func _init(p_track: TrackData, p_terrain: TerrainData, p_rng: RandomNumberGenerator) -> void:
	track = p_track
	terrain = p_terrain
	rng = p_rng
	var b := terrain.bounds
	_bmin = Vector2(b["min_x"] + 20.0, b["min_z"] + 20.0)
	_bmax = Vector2(b["max_x"] - 20.0, b["max_z"] - 20.0)
	start_pos = track.point_at(0.0, 0.0)
	for i in range(0, track.n, 8):
		_sub.append(Vector3(track.px[i], float(i), track.pz[i]))


# ———————————————— 规则 ————————————————

## 离所有路段（含支路）足够远（间隙从护墙外侧算起）
func clear_of_track(x: float, z: float, r: float, gap := 2.0) -> bool:
	if not track.nearest(x, z, track.wall_offset + r + gap).is_empty():
		return false
	for b in track.branches:
		if not b.nearest(x, z, b.wall_offset + r + gap).is_empty():
			return false
	return true


## 不在河道（含两岸 margin 米）里
func clear_of_rivers(x: float, z: float, r: float, margin := 3.5) -> bool:
	for rv in track.rivers:
		var p: Vector3 = rv["pos"]
		var across := absf((x - p.x) * float(rv["tx"]) + (z - p.z) * float(rv["tz"]))
		var along: float = (x - p.x) * float(rv["nx"]) + (z - p.z) * float(rv["nz"])
		var ext: float = rv["ext_pos"] if along > 0.0 else rv["ext_neg"]
		if across < float(rv["width"]) * 0.5 + r + margin and absf(along) < ext + 14.0:
			return false
	return true


func in_bounds(x: float, z: float) -> bool:
	return x > _bmin.x and x < _bmax.x and z > _bmin.y and z < _bmax.y


func is_free(x: float, z: float, r: float) -> bool:
	var cx := floori(x / OCC_CELL)
	var cz := floori(z / OCC_CELL)
	var span := ceili(r / OCC_CELL) + 1
	for gx in range(cx - span, cx + span + 1):
		for gz in range(cz - span, cz + span + 1):
			var arr: Variant = _occ.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for o: Vector3 in (arr as PackedVector3Array):
				var dx := o.x - x
				var dz := o.y - z
				var rr := o.z + r
				if dx * dx + dz * dz < rr * rr:
					return false
	return true


func mark(x: float, z: float, r: float) -> void:
	var key := Vector2i(floori(x / OCC_CELL), floori(z / OCC_CELL))
	var arr: PackedVector3Array = _occ.get(key, PackedVector3Array())
	arr.append(Vector3(x, z, r))
	_occ[key] = arr


## 综合检查。tall: 高大物件（护墙外 6 m 间隙、避开航拍净空区）
func ok(x: float, z: float, r: float, tall := false, check_free := true) -> bool:
	if not in_bounds(x, z):
		return false
	if tall and Vector2(x - start_pos.x, z - start_pos.z).length() < start_clear:
		return false
	if not clear_of_track(x, z, r, 6.0 if tall else 2.0):
		return false
	if not clear_of_rivers(x, z, r):
		return false
	return not check_free or is_free(x, z, r)


## 占地范围内的最低地面高度（大物件四角取最低，免得一侧悬空）
func ground(x: float, z: float, r := 0.0) -> float:
	var h := terrain.height_at(x, z)
	if r >= 1.5:
		var k := r * 0.7
		h = minf(h, minf(minf(terrain.height_at(x + k, z), terrain.height_at(x - k, z)), minf(terrain.height_at(x, z + k), terrain.height_at(x, z - k))))
	return h


## 到中心线的粗略距离（稀疏采样，误差 < 10 m），远处物件用
func approx_dist(x: float, z: float) -> float:
	return sqrt(_approx(x, z).y)


## 最近的稀疏采样：返回 Vector2(采样序号, 距离平方)
func _approx(x: float, z: float) -> Vector2:
	var best := INF
	var bi := 0.0
	for p in _sub:
		var dx := p.x - x
		var dz := p.z - z
		var dd := dx * dx + dz * dz
		if dd < best:
			best = dd
			bi = p.y
	return Vector2(bi, best)


## 最近的中心线采样序号（近处精确，远处用稀疏采样）
func nearest_idx(x: float, z: float) -> int:
	var nr := track.nearest(x, z, 48.0)
	return int(_approx(x, z).x) if nr.is_empty() else int(nr["idx"])


## 朝向最近路段的角度（绕 Y，模型 +Z 朝向赛道）
func facing(x: float, z: float) -> float:
	var i := nearest_idx(x, z)
	return atan2(track.px[i] - x, track.pz[i] - z)


# ———————————————— 候选点生成 ————————————————

## 赛道两侧的带状区域：离护墙 min_off..max_off 米。返回 [Vector4(x, y, z, s)]（s 为采样位置）
func band(count: int, min_off: float, max_off: float, r: float, tall := false, do_mark := true, side := 0) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var tries := count * 6
	while out.size() < count and tries > 0:
		tries -= 1
		var s := rng.randf() * track.n
		var sd := float(side) if side != 0 else (-1.0 if rng.randf() < 0.5 else 1.0)
		var off := track.wall_offset + min_off + r + rng.randf() * (max_off - min_off)
		var p := track.point_at(s, sd * off)
		if not ok(p.x, p.z, r, tall):
			continue
		if do_mark:
			mark(p.x, p.z, r)
		out.append(Vector4(p.x, ground(p.x, p.z, r), p.z, s))
	return out


## 自由散布：到赛道距离在 [min_d, max_d]（从中心线算）。返回 [Vector4(x, y, z, 0)]
func scatter(count: int, r: float, min_d: float, max_d: float, tall := false, do_mark := true) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var b := track.bounds
	var pad := minf(max_d, 360.0)
	var x0: float = maxf(b["min_x"] - pad, _bmin.x)
	var x1: float = minf(b["max_x"] + pad, _bmax.x)
	var z0: float = maxf(b["min_z"] - pad, _bmin.y)
	var z1: float = minf(b["max_z"] + pad, _bmax.y)
	var tries := count * 10
	while out.size() < count and tries > 0:
		tries -= 1
		var x := x0 + rng.randf() * (x1 - x0)
		var z := z0 + rng.randf() * (z1 - z0)
		if not track.nearest(x, z, maxf(min_d, track.wall_offset + r + (6.0 if tall else 2.0))).is_empty():
			continue
		if max_d < 2000.0 and approx_dist(x, z) > max_d:
			continue
		if not ok(x, z, r, tall):
			continue
		if do_mark:
			mark(x, z, r)
		out.append(Vector4(x, ground(x, z, r), z, 0.0))
	return out


## 在 center 周围 radius 内撒 count 个点（成簇的花丛、树林、石堆）
func cluster(center: Vector3, count: int, radius: float, r: float, tall := false, do_mark := false) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var tries := count * 4
	while out.size() < count and tries > 0:
		tries -= 1
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		if not ok(x, z, r, tall, do_mark):
			continue
		if do_mark:
			mark(x, z, r)
		out.append(Vector4(x, ground(x, z, r), z, 0.0))
	return out


## 常用变换：位置 + 绕 Y 旋转 + 缩放
static func xform(pos: Vector3, yaw: float, scale: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), pos)
