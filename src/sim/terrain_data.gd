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
## 每条支路 64 m 内的网格
var _branch_cells: Array[Dictionary] = []
## 地形网格缓存：地形网格算好后填入，之后 height_at 直接在网格三角形上插值（与渲染出来的地面完全一致，且快得多）
var _grid := PackedFloat32Array()
var _gx0 := 0.0
var _gz0 := 0.0
var _gcell := 1.0
var _gw := 0
var _gh := 0
## 立交：上下两层赛道交叉处的中心（xz）。附近的地形跟随下层路面，上层成桥
var crossings: Array[Vector2] = []
const CROSS_R := 70.0
const CROSS_FADE := 30.0


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
	for br in t.branches:
		var cells := {}
		for i in br.n:
			var cx := floori(br.px[i] / TrackData.GRID_CELL)
			var cz := floori(br.pz[i] / TrackData.GRID_CELL)
			for gx in range(cx - r, cx + r + 1):
				for gz in range(cz - r, cz + r + 1):
					cells[Vector2i(gx, gz)] = true
					td._near_cells[Vector2i(gx, gz)] = true
		td._branch_cells.append(cells)
	td._find_crossings()
	return td


func _find_crossings() -> void:
	var t := track
	var gap := ceili(100.0 / t.spacing)
	for i in range(0, t.n, 2):
		for hit in t.nearest_all(t.px[i], t.pz[i], t.wall_offset * 2.0):
			var j: int = hit["idx"]
			var di := absi(i - j)
			if mini(di, t.n - di) < gap or float(hit["y"]) > t.py[i] - 4.0:
				continue
			var c := Vector2((t.px[i] + t.px[j]) * 0.5, (t.pz[i] + t.pz[j]) * 0.5)
			var dup := false
			for o in crossings:
				if o.distance_to(c) < 30.0:
					dup = true
					break
			if not dup:
				crossings.append(c)


## 立交影响权重：中心 CROSS_R 内为 1，再往外 CROSS_FADE 内渐隐
func _crossing_weight(x: float, z: float) -> float:
	var f := 0.0
	for c in crossings:
		var d := Vector2(x, z).distance_to(c)
		f = maxf(f, 1.0 - MathX.smooth(CROSS_R, CROSS_R + CROSS_FADE, d))
	return f


## 与 near 不同层（高差 > 4 m 且沿赛道相距够远）的最近采样
func _other_layer(x: float, z: float, near: Dictionary) -> Dictionary:
	var gap := ceili(100.0 / track.spacing)
	var ni: int = near["idx"]
	var ny: float = near["y"]
	var best := {}
	for hit in track.nearest_all(x, z, 64.0):
		var j: int = hit["idx"]
		var di := absi(ni - j)
		if mini(di, track.n - di) < gap or absf(float(hit["y"]) - ny) < 4.0:
			continue
		if best.is_empty() or float(hit["d"]) < float(best["d"]):
			best = hit
	return best


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


## 填入地形网格（heights 为 w×h，行优先，z 方向为行），与 TerrainMesh 的三角剖分一致
func set_grid(heights: PackedFloat32Array, x0: float, z0: float, cell: float, w: int, h: int) -> void:
	_grid = heights
	_gx0 = x0
	_gz0 = z0
	_gcell = cell
	_gw = w
	_gh = h


func height_at(x: float, z: float) -> float:
	if not _grid.is_empty():
		var fx := (x - _gx0) / _gcell
		var fz := (z - _gz0) / _gcell
		var ix := floori(fx)
		var iz := floori(fz)
		if ix >= 0 and iz >= 0 and ix < _gw - 1 and iz < _gh - 1:
			fx -= ix
			fz -= iz
			var a := iz * _gw + ix
			var ha := _grid[a]
			var hb := _grid[a + 1]
			var hc := _grid[a + _gw]
			var hd := _grid[a + _gw + 1]
			# 两个三角形：(a, b, c) 与 (b, d, c)
			if fx + fz <= 1.0:
				return ha + (hb - ha) * fx + (hc - ha) * fz
			return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)
	return height_exact(x, z)


## 按地形函数精确计算（不走网格缓存）
func height_exact(x: float, z: float) -> float:
	if flat:
		var far := MathX.smooth(80.0, 340.0, _outside(x, z))
		return -0.3 + far * (4.0 + _flat_far.get_noise_2d(x / 70.0, z / 70.0) * 6.0)
	var h := _base(x, z)
	var near := {}
	if _near_cells.has(Vector2i(floori(x / TrackData.GRID_CELL), floori(z / TrackData.GRID_CELL))):
		near = track.nearest(x, z, 64.0)
	if not near.is_empty():
		var base := h
		var w := MathX.smooth(track.wall_offset + 1.5, track.wall_offset + 52.0, near["d"])
		h = lerpf(float(near["y"]) - 0.45, base, w)
		var f := _crossing_weight(x, z) if not crossings.is_empty() else 0.0
		if f > 0.0:
			var other := _other_layer(x, z, near)
			if not other.is_empty():
				var low := near if float(near["y"]) < float(other["y"]) else other
				var up := other if low == near else near
				var h_up := lerpf(float(up["y"]) - 0.45, base, MathX.smooth(track.wall_offset + 1.5, track.wall_offset + 52.0, up["d"]))
				# 下层路两侧 20 m 内挖出路堑，上层在其上方成桥
				var h_lay := lerpf(float(low["y"]) - 0.45, h_up, MathX.smooth(track.wall_offset + 1.5, track.wall_offset + 20.0, low["d"]))
				h = lerpf(h, h_lay, f)
	h = _branches(x, z, h, near)
	return _carve_rivers(x, z, h)


## 支路：近道两侧贴合路面；悬崖下的绕行路挖出谷底，主路崖边到谷底之间是上陡下缓的崖壁
func _branches(x: float, z: float, h: float, near: Dictionary) -> float:
	var cell := Vector2i(floori(x / TrackData.GRID_CELL), floori(z / TrackData.GRID_CELL))
	for k in track.branches.size():
		if not _branch_cells[k].has(cell):
			continue
		var b := track.branches[k]
		var nb := b.nearest(x, z, 64.0)
		if nb.is_empty():
			continue
		var bi: int = nb["idx"]
		var by := float(nb["y"]) - 0.45
		if b.kind == "detour" and not near.is_empty() and _facing(b, bi, x, z, near):
			var i: int = near["idx"]
			var side := 1.0 if (x - track.px[i]) * track.nx[i] + (z - track.pz[i]) * track.nz[i] >= 0.0 else -1.0
			var core := track.hw[i] + TrackData.CLIFF_LIP if track.edge_at(i, side) == TrackData.EDGE_CLIFF else track.wo[i] + 1.5
			var u := maxf(0.0, float(near["d"]) - core)
			var v := maxf(0.0, float(nb["d"]) - b.wo[bi])
			var t := u / maxf(u + v, 0.001)
			h = lerpf(float(near["y"]) - 0.45, by, 1.0 - pow(1.0 - t, 3.0))
		else:
			var band := 10.0 if b.kind == "detour" else 16.0
			h = lerpf(by, h, MathX.smooth(b.wo[bi] + 0.5, b.wo[bi] + band, nb["d"]))
	return h


## 点位于主路朝向支路的一侧，且在支路朝向主路的一侧（两路之间）
func _facing(b: TrackData, bi: int, x: float, z: float, near: Dictionary) -> bool:
	var i: int = near["idx"]
	var t := track
	var pl := (x - t.px[i]) * t.nx[i] + (z - t.pz[i]) * t.nz[i]
	var bl := (b.px[bi] - t.px[i]) * t.nx[i] + (b.pz[bi] - t.pz[i]) * t.nz[i]
	if pl * bl <= 0.0 or absf(bl) > 45.0:
		return false
	var ql := (x - b.px[bi]) * b.nx[bi] + (z - b.pz[bi]) * b.nz[bi]
	var ml := (t.px[i] - b.px[bi]) * b.nx[bi] + (t.pz[i] - b.pz[bi]) * b.nz[bi]
	return ql * ml > 0.0


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
