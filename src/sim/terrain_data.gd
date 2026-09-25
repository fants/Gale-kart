class_name TerrainData
extends RefCounted
## 地形高度函数：靠近赛道处贴合路面，远处平滑过渡到噪声丘陵，外圈隆起成山。移植自参考版 terrain.js。

const TERRAIN_MARGIN := 380.0

var track: TrackData
var bounds := {}
var flat := false
var _rolling := FastNoiseLite.new()
var _mount := FastNoiseLite.new()
var _flat_far := FastNoiseLite.new()
## 距赛道 64 m 以内可能出现的 16 m 网格（膨胀后的赛道占用格），不在其中的点跳过最近点查询
var _near_cells := {}


static func create(t: TrackData, seed := 11) -> TerrainData:
	var td := TerrainData.new()
	td.track = t
	var b := t.bounds
	td.bounds = {
		"min_x": b["min_x"] - TERRAIN_MARGIN, "max_x": b["max_x"] + TERRAIN_MARGIN,
		"min_z": b["min_z"] - TERRAIN_MARGIN, "max_z": b["max_z"] + TERRAIN_MARGIN,
	}
	td.flat = t.def.get("terrain", "follow") == "flat"
	for nz: FastNoiseLite in [td._rolling, td._mount, td._flat_far]:
		nz.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		nz.frequency = 1.0
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	td._rolling.seed = seed + t.n
	td._rolling.fractal_octaves = 3
	td._mount.seed = seed + t.n + 17
	td._mount.fractal_octaves = 4
	td._flat_far.seed = seed + t.n + 31
	td._flat_far.fractal_octaves = 3
	var r := ceili(64.0 / TrackData.GRID_CELL) + 1
	for i in t.n:
		var cx := floori(t.px[i] / TrackData.GRID_CELL)
		var cz := floori(t.pz[i] / TrackData.GRID_CELL)
		for gx in range(cx - r, cx + r + 1):
			for gz in range(cz - r, cz + r + 1):
				td._near_cells[Vector2i(gx, gz)] = true
	return td


## 赛道包围盒外的距离 → 远山
func _outside(x: float, z: float) -> float:
	var b := track.bounds
	var dx := maxf(maxf(b["min_x"] - x, 0.0), x - b["max_x"])
	var dz := maxf(maxf(b["min_z"] - z, 0.0), z - b["max_z"])
	return sqrt(dx * dx + dz * dz)


func _base(x: float, z: float) -> float:
	var rolling := _rolling.get_noise_2d(x / 160.0, z / 160.0) * 9.0
	var far := MathX.smooth(40.0, 300.0, _outside(x, z))
	var mountains := far * (26.0 + _mount.get_noise_2d(x / 90.0 + 17.0, z / 90.0 - 5.0) * 34.0)
	return rolling + mountains


func height_at(x: float, z: float) -> float:
	if flat:
		var far := MathX.smooth(80.0, 340.0, _outside(x, z))
		return -0.3 + far * (4.0 + _flat_far.get_noise_2d(x / 70.0, z / 70.0) * 6.0)
	var h := _base(x, z)
	var near := {}
	if _near_cells.has(Vector2i(floori(x / TrackData.GRID_CELL), floori(z / TrackData.GRID_CELL))):
		near = track.nearest(x, z, 64.0)
	if not near.is_empty():
		var w := MathX.smooth(track.wall_offset + 1.5, track.wall_offset + 52.0, near["d"])
		h = lerpf(float(near["y"]) - 0.45, h, w)
	return _carve_rivers(x, z, h)


## 河道：沿赛道法线方向的一条直线河谷，河床比水面低 1.6 m，两岸 12 m 缓坡
func _carve_rivers(x: float, z: float, h: float) -> float:
	for rv: Dictionary in track.rivers:
		var p: Vector3 = rv["pos"]
		var d := absf((x - p.x) * float(rv["tx"]) + (z - p.z) * float(rv["tz"]))
		var half: float = rv["width"] * 0.5
		if d > half + 12.0:
			continue
		# 沿河方向的位置：超出两端后河谷逐渐收拢消失
		var a: float = (x - p.x) * float(rv["nx"]) + (z - p.z) * float(rv["nz"])
		var ext: float = rv["ext_pos"] if a > 0.0 else rv["ext_neg"]
		var end_k := 1.0 - MathX.smooth(ext - 6.0, ext + 10.0, absf(a))
		if end_k <= 0.0:
			continue
		var bed: float = rv["water_y"] - 1.6
		var carved := lerpf(bed, maxf(h, bed), MathX.smooth(half - 1.0, half + 12.0, d))
		h = minf(h, lerpf(h, carved, end_k))
	return h
