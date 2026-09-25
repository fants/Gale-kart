class_name TrackData
extends RefCounted
## 赛道仿真数据：闭合 centripetal Catmull-Rom 样条按弧长均匀采样，
## 提供横向投影、赛车线、跳台 / 加速带 / 道具箱 / 发车格。移植自参考版 track.js。

const SAMPLE_SPACING := 2.0
const GRID_CELL := 16.0
const ARC_DIVISIONS := 6000

var def: Dictionary
var id: String
var name: String
var theme: Dictionary
var grip := 1.0

var n := 0
var spacing := 2.0
var length := 0.0
var half_width := 10.0
var shoulder := 3.5
var wall_offset := 13.5

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pz := PackedFloat32Array()
var tx := PackedFloat32Array()
var tz := PackedFloat32Array()
var nx := PackedFloat32Array()
var nz := PackedFloat32Array()
## 有符号曲率（正 = 左转）
var curv := PackedFloat32Array()

var bounds := {}
var ramps: Array[Dictionary] = []
var boost_pads: Array[Dictionary] = []
var item_boxes: Array[Dictionary] = []
var grid: Array[Dictionary] = []
## 横穿赛道的河流：{s, width, pos(路面中心点), tx, tz(赛道切线，河道沿法线方向延伸), water_y}
var rivers: Array[Dictionary] = []

## 赛车线：相对中心线的横向偏移
var racing_line := PackedFloat32Array()
var rl_curv := PackedFloat32Array()
var rl_x := PackedFloat32Array()
var rl_z := PackedFloat32Array()

var _cells := {}


static func build(d: Dictionary) -> TrackData:
	var t := TrackData.new()
	t._build(d)
	return t


func _build(d: Dictionary) -> void:
	def = d
	id = d["id"]
	name = d["name"]
	theme = ThemesData.get_theme(d["theme"])
	grip = float(d.get("grip", 1.0))
	half_width = float(d["half_width"])
	shoulder = float(d["shoulder"])
	wall_offset = half_width + shoulder

	var scale := float(d.get("scale", 1.0))
	var ctrl: Array[Vector3] = []
	for p: Array in d["points"]:
		ctrl.append(Vector3(p[0] * scale, p[2], p[1] * scale))

	# 弧长表：在曲线参数 t 上均匀取 ARC_DIVISIONS 段，累计长度
	var arc := PackedFloat32Array()
	arc.resize(ARC_DIVISIONS + 1)
	var prev := _catmull(ctrl, 0.0)
	arc[0] = 0.0
	for i in range(1, ARC_DIVISIONS + 1):
		var p := _catmull(ctrl, float(i) / ARC_DIVISIONS)
		arc[i] = arc[i - 1] + p.distance_to(prev)
		prev = p
	length = arc[ARC_DIVISIONS]
	n = maxi(64, roundi(length / SAMPLE_SPACING))
	spacing = length / n

	px.resize(n); py.resize(n); pz.resize(n)
	var seg := 0
	for i in n:
		var target := float(i) / n * length
		while seg < ARC_DIVISIONS - 1 and arc[seg + 1] < target:
			seg += 1
		var seg_len := arc[seg + 1] - arc[seg]
		var frac := 0.0 if seg_len <= 0.0 else (target - arc[seg]) / seg_len
		var u := (seg + frac) / ARC_DIVISIONS
		var p := _catmull(ctrl, u)
		px[i] = p.x; py[i] = p.y; pz[i] = p.z

	tx.resize(n); tz.resize(n); nx.resize(n); nz.resize(n)
	for i in n:
		var a := (i - 1 + n) % n
		var b := (i + 1) % n
		var dx := px[b] - px[a]
		var dz := pz[b] - pz[a]
		var l := sqrt(dx * dx + dz * dz)
		if l == 0.0:
			l = 1.0
		dx /= l; dz /= l
		tx[i] = dx; tz[i] = dz
		# right = (-tz, tx)
		nx[i] = -dz; nz[i] = dx

	curv.resize(n)
	var k := 3
	for i in n:
		var a := (i - k + n) % n
		var b := (i + k) % n
		var cross := tx[a] * tz[b] - tz[a] * tx[b]
		var dot := tx[a] * tx[b] + tz[a] * tz[b]
		curv[i] = -atan2(cross, dot) / (2.0 * k * spacing)

	bounds = {"min_x": INF, "max_x": -INF, "min_z": INF, "max_z": -INF, "min_y": INF, "max_y": -INF}
	for i in n:
		bounds["min_x"] = minf(bounds["min_x"], px[i]); bounds["max_x"] = maxf(bounds["max_x"], px[i])
		bounds["min_z"] = minf(bounds["min_z"], pz[i]); bounds["max_z"] = maxf(bounds["max_z"], pz[i])
		bounds["min_y"] = minf(bounds["min_y"], py[i]); bounds["max_y"] = maxf(bounds["max_y"], py[i])

	for i in n:
		var key := Vector2i(floori(px[i] / GRID_CELL), floori(pz[i] / GRID_CELL))
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		var arr: PackedInt32Array = _cells[key]
		arr.append(i)
		_cells[key] = arr

	for r: Dictionary in d.get("ramps", []):
		ramps.append({"s": float(r["at"]) * n, "len_s": float(r["len"]) / spacing, "height": float(r["height"]), "len": float(r["len"])})
	for rv: Dictionary in d.get("rivers", []):
		var rs := float(rv["at"]) * n
		var ri := int(rs) % n
		var rp := point_at(rs, 0.0)
		var river := {"s": rs, "width": float(rv["width"]), "pos": rp, "tx": tx[ri], "tz": tz[ri], "nx": nx[ri], "nz": nz[ri], "water_y": rp.y - 3.4}
		# 沿法线两侧延伸，直到接近其他路段或 260 m 为止（端点由场景做成瀑布 / 水潭）
		for side: float in [1.0, -1.0]:
			var ext := 20.0
			while ext < 260.0:
				var q := rp + Vector3(nx[ri], 0.0, nz[ri]) * side * (ext + 4.0)
				var near_other := false
				for hit in nearest_all(q.x, q.z, wall_offset + float(rv["width"]) + 14.0):
					var ds := absf(float(hit["idx"]) - rs)
					if minf(ds, n - ds) * spacing > 60.0:
						near_other = true
						break
				if near_other:
					break
				ext += 4.0
			river["ext_pos" if side > 0.0 else "ext_neg"] = ext
		rivers.append(river)
	for p: Dictionary in d.get("boost_pads", []):
		boost_pads.append({"s": float(p["at"]) * n, "lateral": float(p["lateral"]), "half_len_s": 3.0 / spacing, "half_width": 2.6, "len": 6.0})
	for at: float in d.get("item_rows", []):
		var s := at * n
		var cols := [-0.66, -0.22, 0.22, 0.66] if half_width >= 9.5 else [-0.6, -0.2, 0.2, 0.6]
		for c: float in cols:
			var lat := c * half_width
			item_boxes.append({"s": s, "lateral": lat, "pos": point_at(s, lat)})

	# 发车格：起点线后方交错两列
	for kk in 8:
		var row := kk / 2
		var col := kk % 2
		var back := 8.0 + row * 8.0 + col * 4.0
		var s := wrap_s(-back / spacing)
		var lat := (-1.0 if col == 0 else 1.0) * minf(3.6, half_width * 0.4)
		grid.append({"pos": point_at(s, lat), "heading": heading_at(s), "s": s, "lateral": lat})

	_compute_racing_line()


## three.js CatmullRomCurve3（closed, centripetal）的 getPoint
static func _catmull(pts: Array[Vector3], t: float) -> Vector3:
	var l := pts.size()
	var p := l * t
	var ip := floori(p)
	var w := p - ip
	if ip <= 0:
		ip += (floori(absf(ip) / l) + 1) * l
	var p0 := pts[(ip - 1) % l]
	var p1 := pts[ip % l]
	var p2 := pts[(ip + 1) % l]
	var p3 := pts[(ip + 2) % l]
	var dt0 := pow(p0.distance_squared_to(p1), 0.25)
	var dt1 := pow(p1.distance_squared_to(p2), 0.25)
	var dt2 := pow(p2.distance_squared_to(p3), 0.25)
	if dt1 < 1e-4:
		dt1 = 1.0
	if dt0 < 1e-4:
		dt0 = dt1
	if dt2 < 1e-4:
		dt2 = dt1
	return Vector3(
		_nonuniform(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2, w),
		_nonuniform(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2, w),
		_nonuniform(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2, w))


static func _nonuniform(x0: float, x1: float, x2: float, x3: float, dt0: float, dt1: float, dt2: float, t: float) -> float:
	var t1 := (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
	var t2 := (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
	t1 *= dt1
	t2 *= dt1
	var c0 := x1
	var c1 := t1
	var c2 := -3.0 * x1 + 3.0 * x2 - 2.0 * t1 - t2
	var c3 := 2.0 * x1 - 2.0 * x2 + t1 + t2
	return c0 + c1 * t + c2 * t * t + c3 * t * t * t


func wrap_s(s: float) -> float:
	return fposmod(s, float(n))


## s（采样单位，可为小数）处的位置，lateral 为右侧偏移
func point_at(s: float, lateral := 0.0) -> Vector3:
	s = wrap_s(s)
	var i := int(s)
	var j := (i + 1) % n
	var t := s - i
	var cx := lerpf(px[i], px[j], t)
	var cz := lerpf(pz[i], pz[j], t)
	var nnx := lerpf(nx[i], nx[j], t)
	var nnz := lerpf(nz[i], nz[j], t)
	var l := sqrt(nnx * nnx + nnz * nnz)
	if l == 0.0:
		l = 1.0
	nnx /= l; nnz /= l
	return Vector3(cx + nnx * lateral, lerpf(py[i], py[j], t) + ramp_height(s, lateral), cz + nnz * lateral)


func heading_at(s: float) -> float:
	s = wrap_s(s)
	var i := int(s)
	var j := (i + 1) % n
	var t := s - i
	return atan2(lerpf(tx[i], tx[j], t), lerpf(tz[i], tz[j], t))


func center_y(s: float) -> float:
	s = wrap_s(s)
	var i := int(s)
	return lerpf(py[i], py[(i + 1) % n], s - i)


## 跳台叠加高度（楔形：线性上升，末端垂直落差）
func ramp_height(s: float, lateral: float) -> float:
	if ramps.is_empty() or absf(lateral) > half_width + 0.5:
		return 0.0
	for r in ramps:
		var ds: float = s - r["s"]
		if ds < 0.0:
			ds += n
		if ds >= 0.0 and ds < r["len_s"]:
			return r["height"] * (ds / r["len_s"])
	return 0.0


## XZ 平面上最近的采样点（max_dist 以内）；没有返回 {}
func nearest(x: float, z: float, max_dist := 60.0) -> Dictionary:
	var r := ceili(max_dist / GRID_CELL)
	var cx := floori(x / GRID_CELL)
	var cz := floori(z / GRID_CELL)
	var best := max_dist * max_dist
	var bi := -1
	for gx in range(cx - r, cx + r + 1):
		for gz in range(cz - r, cz + r + 1):
			var arr: Variant = _cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for i: int in arr:
				var dx := px[i] - x
				var dz := pz[i] - z
				var dd := dx * dx + dz * dz
				if dd < best:
					best = dd
					bi = i
	if bi < 0:
		return {}
	return {"d": sqrt(best), "idx": bi, "y": py[bi]}


## max_dist 内的所有采样（立交处可能有多层）
func nearest_all(x: float, z: float, max_dist := 30.0) -> Array[Dictionary]:
	var r := ceili(max_dist / GRID_CELL)
	var cx := floori(x / GRID_CELL)
	var cz := floori(z / GRID_CELL)
	var res: Array[Dictionary] = []
	var md := max_dist * max_dist
	for gx in range(cx - r, cx + r + 1):
		for gz in range(cz - r, cz + r + 1):
			var arr: Variant = _cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for i: int in arr:
				var dx := px[i] - x
				var dz := pz[i] - z
				var dd := dx * dx + dz * dz
				if dd < md:
					res.append({"d": sqrt(dd), "idx": i, "y": py[i]})
	return res


func _project_range(x: float, y: float, z: float, from: int, count: int, out: TrackProj) -> void:
	var best := INF
	var bi := from
	var bt := 0.0
	for kk in count:
		var i := posmod(from + kk, n)
		var j := (i + 1) % n
		var ax := px[i]
		var az := pz[i]
		var dx := px[j] - ax
		var dz := pz[j] - az
		var len2 := dx * dx + dz * dz
		if len2 == 0.0:
			len2 = 1.0
		var t := clampf(((x - ax) * dx + (z - az) * dz) / len2, 0.0, 1.0)
		var qx := ax + dx * t - x
		var qz := az + dz * t - z
		var qy := py[i] + (py[j] - py[i]) * t - y
		var d := qx * qx + qz * qz + qy * qy * 0.6
		if d < best:
			best = d
			bi = i
			bt = t
	out.idx = bi
	out.t = bt
	out.dist2 = best


## 把世界坐标投影到赛道。hint 为上次的 idx；hint < 0 时全局搜索。
func project(x: float, y: float, z: float, hint: int, out: TrackProj) -> TrackProj:
	var w := 14
	if hint >= 0:
		_project_range(x, y, z, hint - w, w * 2 + 1, out)
		var rel := posmod(out.idx - (hint - w), n)
		if rel <= 1 or rel >= w * 2 - 1 or out.dist2 > (wall_offset + 6.0) * (wall_offset + 6.0):
			_project_range(x, y, z, 0, n, out)
	else:
		_project_range(x, y, z, 0, n, out)
	var i := out.idx
	var j := (i + 1) % n
	var t := out.t
	var cx := px[i] + (px[j] - px[i]) * t
	var cz := pz[i] + (pz[j] - pz[i]) * t
	var nnx := nx[i] + (nx[j] - nx[i]) * t
	var nnz := nz[i] + (nz[j] - nz[i]) * t
	var l := sqrt(nnx * nnx + nnz * nnz)
	if l == 0.0:
		l = 1.0
	nnx /= l; nnz /= l
	out.s = i + t
	out.lateral = (x - cx) * nnx + (z - cz) * nnz
	out.nx = nnx
	out.nz = nnz
	# right = (-tz, tx) ⇒ tangent = (nz, -nx)
	out.tx = nnz
	out.tz = -nnx
	out.road_y = py[i] + (py[j] - py[i]) * t
	out.y = out.road_y + ramp_height(out.s, out.lateral)
	return out


## 弹性带平滑：让线路在路宽内尽量拉直，得到入弯外—弯心内—出弯外的走线
func _compute_racing_line() -> void:
	racing_line.resize(n)
	racing_line.fill(0.0)
	var limit := half_width - 2.4
	var kk := 7
	var tmp := PackedFloat32Array()
	tmp.resize(n)
	for _iter in 160:
		for i in n:
			var a := (i - kk + n) % n
			var b := (i + kk) % n
			var ax := px[a] + nx[a] * racing_line[a]
			var az := pz[a] + nz[a] * racing_line[a]
			var bx := px[b] + nx[b] * racing_line[b]
			var bz := pz[b] + nz[b] * racing_line[b]
			var mx := (ax + bx) * 0.5 - px[i]
			var mz := (az + bz) * 0.5 - pz[i]
			var desired := mx * nx[i] + mz * nz[i]
			tmp[i] = clampf(lerpf(racing_line[i], desired, 0.6), -limit, limit)
		racing_line = tmp.duplicate()
	for _pass in 3:
		for i in n:
			tmp[i] = (racing_line[(i - 1 + n) % n] + racing_line[i] * 2.0 + racing_line[(i + 1) % n]) / 4.0
		racing_line = tmp.duplicate()
	rl_x.resize(n)
	rl_z.resize(n)
	for i in n:
		rl_x[i] = px[i] + nx[i] * racing_line[i]
		rl_z[i] = pz[i] + nz[i] * racing_line[i]
	rl_curv.resize(n)
	var k2 := 4
	for i in n:
		var a := (i - k2 + n) % n
		var b := (i + k2) % n
		var d1x := rl_x[i] - rl_x[a]
		var d1z := rl_z[i] - rl_z[a]
		var d2x := rl_x[b] - rl_x[i]
		var d2z := rl_z[b] - rl_z[i]
		var ang := atan2(d1x * d2z - d1z * d2x, d1x * d2x + d1z * d2z)
		var dist := (sqrt(d1x * d1x + d1z * d1z) + sqrt(d2x * d2x + d2z * d2z)) * 0.5
		rl_curv[i] = absf(ang) / maxf(dist, 0.1)


## 赛道几何统计（测试与调参用）
static func stats(track: TrackData) -> Dictionary:
	var min_radius := INF
	var min_radius_idx := 0
	for i in track.n:
		var r := 1.0 / maxf(absf(track.curv[i]), 1e-6)
		if r < min_radius:
			min_radius = r
			min_radius_idx = i
	var skip := ceili(track.wall_offset * 4.0 / track.spacing)
	var min_sep := INF
	var min_sep_pair := [0, 0]
	var i := 0
	while i < track.n:
		var j := i + skip
		while j < track.n:
			var around := track.n - (j - i)
			if around >= skip and absf(track.py[i] - track.py[j]) < 6.0:
				var dx := track.px[i] - track.px[j]
				var dz := track.pz[i] - track.pz[j]
				var d := sqrt(dx * dx + dz * dz)
				if d < min_sep:
					min_sep = d
					min_sep_pair = [i, j]
			j += 2
		i += 2
	var max_slope := 0.0
	for k in track.n:
		var j := (k + 1) % track.n
		max_slope = maxf(max_slope, absf(track.py[j] - track.py[k]) / track.spacing)
	return {
		"length": track.length, "n": track.n, "min_radius": min_radius, "min_radius_idx": min_radius_idx,
		"min_sep": min_sep, "min_sep_pair": min_sep_pair, "max_slope": max_slope, "wall_offset": track.wall_offset,
	}
