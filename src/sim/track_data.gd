class_name TrackData
extends RefCounted
## 赛道仿真数据：闭合 centripetal Catmull-Rom 样条按弧长均匀采样，
## 提供横向投影、赛车线、跳台 / 加速带 / 道具箱 / 发车格。移植自参考版 track.js。
## 扩展：逐采样路宽（窄路）、两侧边缘类型（护墙 / 岔路口 / 悬崖）、支路（小路：近道与悬崖下的绕行路，开放样条）。

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
## 全程最大半宽 / 护墙偏移（只需要保守值的地方用；逐点值见 hw / wo）
var half_width := 10.0
var shoulder := 3.5
var wall_offset := 13.5
## false：开放路段（支路），首尾不相接
var closed := true
var hw := PackedFloat32Array()
var wo := PackedFloat32Array()
## 两侧边缘：护墙 / 岔路口（没有墙，通往支路或主路）/ 悬崖（没有墙，掉下去）
const EDGE_WALL := 0
const EDGE_GAP := 1
const EDGE_CLIFF := 2
## 悬崖一侧：路面边缘外这么宽的土沿，再往外就是崖壁
const CLIFF_LIP := 2.0
var edge_l := PackedByteArray()
var edge_r := PackedByteArray()
## 岔路口通往的支路下标
var gap_owner_l := PackedInt32Array()
var gap_owner_r := PackedInt32Array()
## 支路。kind：shortcut 近道（主路开口进出），detour 绕行路（悬崖下，掉下去才会走）
var branches: Array[TrackData] = []
var kind := "main"
## 支路每个采样点对应的主路 s（单调不减，未取模），用于名次与圈数
var map_s := PackedFloat32Array()

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
## 路面：是否铺装；每个采样点的路面类型（见 SURFACES）
const SURFACES := ["asphalt", "dirt", "grass", "mud"]
var paved := true
var surface := PackedByteArray()
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
	var scale := float(d.get("scale", 1.0))
	var ctrl: Array[Vector3] = []
	for p: Array in d["points"]:
		ctrl.append(Vector3(p[0] * scale, p[2], p[1] * scale))
	_sample(ctrl)
	_frames()
	_widths(d.get("widths", []))
	_index()
	_build_features(d)
	for c: Array in d.get("cliffs", []):
		var a := int(float(c[0]) * n)
		var b := int(float(c[1]) * n)
		for i in range(a, b + 1):
			if str(c[2]) == "right":
				edge_r[posmod(i, n)] = EDGE_CLIFF
			else:
				edge_l[posmod(i, n)] = EDGE_CLIFF
	for bd: Dictionary in d.get("branches", []):
		branches.append(_make_branch(bd, scale))
		_link_branch(branches.size() - 1)


## 支路：开放样条，路面 / 宽度 / 表面单独定义，其余沿用主路
func _make_branch(bd: Dictionary, scale: float) -> TrackData:
	var b := TrackData.new()
	b.closed = false
	b.def = bd
	b.id = str(bd["id"])
	b.name = str(bd.get("name", bd["id"]))
	b.kind = str(bd.get("kind", "shortcut"))
	b.theme = theme
	b.grip = grip
	b.paved = paved
	b.half_width = float(bd["half_width"])
	b.shoulder = float(bd["shoulder"])
	var ctrl: Array[Vector3] = []
	for p: Array in bd["points"]:
		ctrl.append(Vector3(p[0] * scale, p[2], p[1] * scale))
	b._sample(ctrl)
	b._frames()
	b._widths(bd.get("widths", []))
	b._index()
	b.surface.resize(b.n)
	b.surface.fill(maxi(0, SURFACES.find(str(bd.get("surface", "dirt")))))
	b.racing_line.resize(b.n)
	b.racing_line.fill(0.0)
	b.rl_x = b.px.duplicate()
	b.rl_z = b.pz.duplicate()
	b.rl_curv.resize(b.n)
	for i in b.n:
		b.rl_curv[i] = absf(b.curv[i])
	return b


## 把支路接到主路：算出主路一侧的开口、支路落在主路里的边、以及支路到主路 s 的映射
func _link_branch(bi: int) -> void:
	var b := branches[bi]
	var pr := TrackProj.new()
	var wpr := TrackProj.new()
	var hint := -1
	b.map_s.resize(b.n)
	var acc := 0.0
	var prev := 0.0
	for k in b.n:
		project(b.px[k], b.py[k], b.pz[k], hint, pr)
		hint = pr.idx
		if k == 0:
			acc = pr.s
		else:
			var ds := pr.s - prev
			if ds > n * 0.5:
				ds -= n
			elif ds < -n * 0.5:
				ds += n
			acc += ds
		prev = pr.s
		b.map_s[k] = acc if k == 0 else maxf(acc, b.map_s[k - 1])
		if absf(b.py[k] - pr.road_y) > 2.5:
			continue
		var lat := pr.lateral
		var mwo := wo_at(pr.s)
		# 支路跨过主路的墙线（外侧墙在主路墙外、内侧墙在主路墙内）：主路这一侧开口，
		# 开口两端正好接上支路外侧墙（支路外侧墙落在主路里的地方被去掉，由主路墙接管）
		if absf(lat) + b.wo[k] > mwo + 0.3 and absf(lat) - b.wo[k] < mwo:
			for q in range(-1, 2):
				var i := posmod(pr.idx + q, n)
				if lat >= 0.0:
					edge_r[i] = EDGE_GAP
					gap_owner_r[i] = bi
				else:
					edge_l[i] = EDGE_GAP
					gap_owner_l[i] = bi
		# 支路自己的墙若落在主路里，也不要
		var inside := absf(lat) < mwo + 0.3
		for sd: int in [-1, 1]:
			var wp := b.point_at(float(k), sd * b.wo[k])
			project(wp.x, wp.y, wp.z, hint, wpr)
			if inside or absf(wpr.lateral) < wo_at(wpr.s) + 0.3:
				if sd > 0:
					b.edge_r[k] = EDGE_GAP
				else:
					b.edge_l[k] = EDGE_GAP


## 样条按弧长均匀采样。闭合：n 个点首尾相接；开放：n 个点包含两个端点
func _sample(ctrl: Array[Vector3]) -> void:
	var arc := PackedFloat32Array()
	arc.resize(ARC_DIVISIONS + 1)
	var prev := _curve(ctrl, 0.0)
	arc[0] = 0.0
	for i in range(1, ARC_DIVISIONS + 1):
		var p := _curve(ctrl, float(i) / ARC_DIVISIONS)
		arc[i] = arc[i - 1] + p.distance_to(prev)
		prev = p
	length = arc[ARC_DIVISIONS]
	if closed:
		n = maxi(64, roundi(length / SAMPLE_SPACING))
		spacing = length / n
	else:
		n = maxi(8, roundi(length / SAMPLE_SPACING) + 1)
		spacing = length / (n - 1)
	px.resize(n); py.resize(n); pz.resize(n)
	var seg := 0
	for i in n:
		var target := float(i) * spacing
		while seg < ARC_DIVISIONS - 1 and arc[seg + 1] < target:
			seg += 1
		var seg_len := arc[seg + 1] - arc[seg]
		var frac := 0.0 if seg_len <= 0.0 else clampf((target - arc[seg]) / seg_len, 0.0, 1.0)
		var p := _curve(ctrl, (seg + frac) / ARC_DIVISIONS)
		px[i] = p.x; py[i] = p.y; pz[i] = p.z


func _curve(ctrl: Array[Vector3], u: float) -> Vector3:
	return _catmull(ctrl, u) if closed else _catmull_open(ctrl, u)


func _frames() -> void:
	tx.resize(n); tz.resize(n); nx.resize(n); nz.resize(n)
	for i in n:
		var a := _idx(i - 1)
		var b := _idx(i + 1)
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
		var a := _idx(i - k)
		var b := _idx(i + k)
		var cross := tx[a] * tz[b] - tz[a] * tx[b]
		var dot := tx[a] * tx[b] + tz[a] * tz[b]
		curv[i] = -atan2(cross, dot) / (maxf(1.0, float(b - a if not closed else 2 * k)) * spacing)
	edge_l.resize(n); edge_r.resize(n)
	edge_l.fill(EDGE_WALL); edge_r.fill(EDGE_WALL)
	gap_owner_l.resize(n); gap_owner_r.resize(n)
	gap_owner_l.fill(-1); gap_owner_r.fill(-1)


## 路宽关键帧 [[比例位置, 半宽], ...]，之间平滑过渡；没有则全程 half_width
func _widths(keys: Array) -> void:
	hw.resize(n)
	wo.resize(n)
	var base := half_width
	for i in n:
		var w := base
		if not keys.is_empty():
			var f := float(i) / (n if closed else n - 1)
			var cnt := keys.size()
			var k1 := 0
			while k1 < cnt and float(keys[k1][0]) <= f:
				k1 += 1
			var k0 := k1 - 1
			var a0: float
			var a1: float
			if k0 < 0:
				k0 = cnt - 1 if closed else 0
				a0 = float(keys[k0][0]) - (1.0 if closed else 0.0)
			else:
				a0 = float(keys[k0][0])
			if k1 >= cnt:
				k1 = 0 if closed else cnt - 1
				a1 = float(keys[k1][0]) + (1.0 if closed else 0.0)
			else:
				a1 = float(keys[k1][0])
			var t := 0.0 if a1 <= a0 else clampf((f - a0) / (a1 - a0), 0.0, 1.0)
			w = lerpf(float(keys[k0][1]), float(keys[k1][1]), t * t * (3.0 - 2.0 * t))
		hw[i] = w
		wo[i] = w + shoulder
	half_width = 0.0
	wall_offset = 0.0
	for i in n:
		half_width = maxf(half_width, hw[i])
		wall_offset = maxf(wall_offset, wo[i])


func _index() -> void:
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



func _build_features(d: Dictionary) -> void:
	for r: Dictionary in d.get("ramps", []):
		ramps.append({"s": float(r["at"]) * n, "len_s": float(r["len"]) / spacing, "height": float(r["height"]), "len": float(r["len"])})
	paved = bool(d.get("paved", true))
	surface.resize(n)
	surface.fill(0 if paved else 1)
	var segs: Array = d.get("surfaces", [])
	for si in segs.size():
		var a := int(float(segs[si][0]) * n)
		var b := n if si == segs.size() - 1 else int(float(segs[si + 1][0]) * n)
		var kind := maxi(0, SURFACES.find(str(segs[si][1])))
		for i in range(a, mini(b, n)):
			surface[i] = kind
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
		var hws := hw_at(s)
		var cols := [-0.66, -0.22, 0.22, 0.66] if hws >= 9.5 else [-0.6, -0.2, 0.2, 0.6]
		for c: float in cols:
			var lat := c * hws
			item_boxes.append({"s": s, "lateral": lat, "pos": point_at(s, lat)})

	# 发车格：起点线后方交错两列
	for kk in 8:
		var row := kk / 2
		var col := kk % 2
		var back := 8.0 + row * 8.0 + col * 4.0
		var s := wrap_s(-back / spacing)
		var lat := (-1.0 if col == 0 else 1.0) * minf(3.6, hw_at(s) * 0.4)
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


## 开放样条：两端用镜像的虚拟点
static func _catmull_open(pts: Array[Vector3], t: float) -> Vector3:
	var l := pts.size()
	var p := (l - 1) * clampf(t, 0.0, 1.0)
	var ip := mini(floori(p), l - 2)
	var w := p - ip
	var p1 := pts[ip]
	var p2 := pts[ip + 1]
	var p0 := pts[ip - 1] if ip > 0 else p1 * 2.0 - p2
	var p3 := pts[ip + 2] if ip + 2 < l else p2 * 2.0 - p1
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


## s 处的路面类型（0 沥青 1 土路 2 草路 3 泥泞）
func surface_at(s: float) -> int:
	return surface[int(wrap_s(s)) % n]


func wrap_s(s: float) -> float:
	return fposmod(s, float(n)) if closed else clampf(s, 0.0, n - 1.0001)


## 采样下标：闭合取模，开放夹到两端
func _idx(i: int) -> int:
	return posmod(i, n) if closed else clampi(i, 0, n - 1)


func hw_at(s: float) -> float:
	s = wrap_s(s)
	var i := int(s)
	return lerpf(hw[i], hw[_idx(i + 1)], s - i)


func wo_at(s: float) -> float:
	s = wrap_s(s)
	var i := int(s)
	return lerpf(wo[i], wo[_idx(i + 1)], s - i)


## side > 0 右侧，否则左侧
func edge_at(i: int, side: float) -> int:
	return edge_r[i] if side > 0.0 else edge_l[i]


func gap_owner(i: int, side: float) -> int:
	return gap_owner_r[i] if side > 0.0 else gap_owner_l[i]


## 支路 s → 主路 s（取模后）
func map_to_main(s: float, main_n: int) -> float:
	s = wrap_s(s)
	var i := int(s)
	return fposmod(lerpf(map_s[i], map_s[_idx(i + 1)], s - i), float(main_n))


## s（采样单位，可为小数）处的位置，lateral 为右侧偏移
func point_at(s: float, lateral := 0.0) -> Vector3:
	s = wrap_s(s)
	var i := int(s)
	var j := _idx(i + 1)
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
	var j := _idx(i + 1)
	var t := s - i
	return atan2(lerpf(tx[i], tx[j], t), lerpf(tz[i], tz[j], t))


func center_y(s: float) -> float:
	s = wrap_s(s)
	var i := int(s)
	return lerpf(py[i], py[_idx(i + 1)], s - i)


## 跳台叠加高度（楔形：线性上升，末端垂直落差）
func ramp_height(s: float, lateral: float) -> float:
	if ramps.is_empty() or absf(lateral) > hw_at(s) + 0.5:
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
	var bi := from if closed else clampi(from, 0, n - 2)
	var bt := 0.0
	for kk in count:
		var i := posmod(from + kk, n)
		if not closed:
			i = from + kk
			if i < 0 or i >= n - 1:
				continue
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
		var rel := out.idx - (hint - w) if not closed else posmod(out.idx - (hint - w), n)
		var at_end := not closed and (out.idx <= 0 or out.idx >= n - 2)
		if (not at_end and (rel <= 1 or rel >= w * 2 - 1)) or out.dist2 > (wall_offset + 6.0) * (wall_offset + 6.0):
			_project_range(x, y, z, 0, n, out)
	else:
		_project_range(x, y, z, 0, n, out)
	var i := out.idx
	var j := _idx(i + 1)
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
			var limit := maxf(0.0, hw[i] - 2.4)
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
