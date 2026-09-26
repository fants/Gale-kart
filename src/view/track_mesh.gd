class_name TrackMesh
extends Node3D
## 赛道表现：路面、路缘、路肩、主题护墙、发车格、加速带、跳台、高架桥面与桥墩、悬崖崖壁、支路（小路）。
## 参考版 trackView.js 的 Godot 实现（道具箱由 ItemView 负责，起点门架由 Scenery 负责）。
## 路宽逐采样变化：条带的横向位置用 Callable(i) 按采样点计算；护墙在岔路口 / 悬崖处断开。

const ROAD_SHADER := preload("res://assets/shaders/road.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/ground.gdshader")
const CURB_SHADER := preload("res://assets/shaders/curb.gdshader")
const WALL_SHADER := preload("res://assets/shaders/wall.gdshader")
const PAD_SHADER := preload("res://assets/shaders/boost_pad.gdshader")
const RAMP_SHADER := preload("res://assets/shaders/ramp.gdshader")
const MARK_SHADER := preload("res://assets/shaders/checker_marks.gdshader")

const WALL_H := 1.15
const WALL_T := 0.55
const CURB_W := 1.1
const WALL_STYLES := {"fence": 0, "stone": 1, "ice": 2, "neon": 3, "log": 4, "tire": 5, "rail": 6}
## 主题 → 地面着色器 kind
const GROUND_KIND := {"village": 0, "desert": 1, "snow": 2, "city": 3, "forest": 4, "circuit": 0}

## 主路
var main: TrackData
## 正在生成的路（主路或某条支路）
var track: TrackData
var terrain: TerrainData
var theme: Dictionary


func build(p_track: TrackData, p_terrain: TerrainData) -> void:
	main = p_track
	track = main
	terrain = p_terrain
	theme = track.theme
	name = "TrackMesh"
	_build_road()
	_build_walls()
	_build_grid_marks()
	_build_pads()
	_build_ramps()
	_build_bridges()
	_build_cliffs()
	for b in main.branches:
		track = b
		_build_road()
		_build_walls()
	track = main


# ———————————————— 工具 ————————————————

## 沿赛道的横向条带。offsets: [[lateral, dy], ...] 从左到右（lateral 负为左；可以是 Callable(i) -> float）。
## u = 列序 / (列数 - 1)，v = 累计米数 × v_scale，uv2 = (该点半宽, 护墙偏移)。from / to 为采样区间（to 可大于 n 表示绕回）。
func _ribbon(offsets: Array, v_scale: float, from := 0, to := -1, closed := true, colors := PackedColorArray()) -> ArrayMesh:
	var n := track.n
	if to < 0:
		to = n
	if not track.closed:
		closed = false
		to = mini(to, n)
	var cols := offsets.size()
	var count := to - from + (1 if closed else 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in count:
		var i := (from + k) % n
		var meters := (from + k) * track.spacing
		for c in cols:
			var lat := _lat(offsets[c][0], i)
			var dy: float = offsets[c][1]
			st.set_uv(Vector2(float(c) / (cols - 1), meters * v_scale))
			st.set_uv2(Vector2(track.hw[i], track.wo[i]))
			if not colors.is_empty():
				st.set_color(colors[i])
			st.add_vertex(Vector3(track.px[i] + track.nx[i] * lat, track.py[i] + dy, track.pz[i] + track.nz[i] * lat))
	for k in count - 1:
		for c in cols - 1:
			var a := k * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			# Godot 以顺时针为正面：从上往下看，列向右、行向前
			st.add_index(a); st.add_index(d); st.add_index(b)
			st.add_index(b); st.add_index(d); st.add_index(e)
	st.generate_normals()
	return st.commit()


func _lat(spec: Variant, i: int) -> float:
	if spec is Callable:
		var f: Callable = spec
		return float(f.call(i))
	return float(spec)


## 某侧路肩的外沿：悬崖处只到崖边土沿，其余到墙内侧
func _shoulder_out(i: int, side: float) -> float:
	if track.edge_at(i, side) == TrackData.EDGE_CLIFF:
		return side * (track.hw[i] + TrackData.CLIFF_LIP)
	return side * (track.wo[i] + 0.2)


## 支路落在主路路面里的采样：支路路面不画（避免与主路重叠闪烁）
func _hidden_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(track.n)
	if track == main:
		return m
	var pr := TrackProj.new()
	var hint := -1
	for i in track.n:
		main.project(track.px[i], track.py[i], track.pz[i], hint, pr)
		hint = pr.idx
		if absf(track.py[i] - pr.road_y) < 2.5 and absf(pr.lateral) < main.hw_at(pr.s) + 0.5:
			m[i] = 1
	return m


## 连续为 0 的区段 [from, to)，首尾各外扩 pad 个采样
func _runs(mask: PackedByteArray, pad: int) -> Array:
	var runs: Array = []
	var start := -1
	for k in track.n + 1:
		var on := k < track.n and mask[k] == 0
		if on and start < 0:
			start = k
		elif not on and start >= 0:
			runs.append([maxi(0, start - pad), mini(track.n, k + pad)])
			start = -1
	return runs


func _mesh(mesh: Mesh, mat: Material, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _shader_mat(shader: Shader, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


# ———————————————— 路面 / 路缘 / 路肩 ————————————————

func _build_road() -> void:
	if not track.paved:
		_build_dirt_road()
		return
	var t := track
	var road_theme: Dictionary = theme["road"]
	var night: bool = theme.get("night", false)
	var road_mat := _shader_mat(ROAD_SHADER, {
		"base_color": Color(road_theme["base"]), "speck_color": Color(road_theme["speck"]),
		"line_color": Color(road_theme["line"]), "center_color": Color(road_theme["center"]),
		"half_width": t.half_width, "track_length": t.length, "line_glow": 2.2 if night else 0.0,
		"wet": 0.35 if night else (0.15 if ThemesData.base_of(theme) == "snow" else 0.0),
		"checker": t == main,
	})
	var offs: Array = []
	for f: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		offs.append([func(i: int) -> float: return f * t.hw[i], 0.02])
	var hidden := _hidden_mask()
	for run: Array in _runs(hidden, 1):
		_mesh(_ribbon(offs, 1.0, run[0], run[1], run[0] == 0 and run[1] == t.n), road_mat).name = "Road"

	var curb: Array = theme["curb"]
	var curb_mat := _shader_mat(CURB_SHADER, {"color_a": Color(curb[0]), "color_b": Color(curb[1]), "glow": 0.8 if night else 0.0})
	for side: float in [-1.0, 1.0]:
		var a := func(i: int) -> float: return side * t.hw[i]
		var b := func(i: int) -> float: return side * (t.hw[i] + CURB_W)
		var co := [[b, 0.03], [a, 0.07]] if side < 0.0 else [[a, 0.07], [b, 0.03]]
		for run: Array in _runs(hidden, 0):
			_mesh(_ribbon(co, 1.0, run[0], run[1], run[0] == 0 and run[1] == t.n), curb_mat).name = "Curb"

	var sh_mat := _shader_mat(GROUND_SHADER, {"tint": Color(theme["shoulder"]), "use_vertex_color": false,
		"kind": GROUND_KIND.get(ThemesData.base_of(theme), 0), "detail": 0.25})
	for side: float in [-1.0, 1.0]:
		var a := func(i: int) -> float: return side * (t.hw[i] + CURB_W)
		var b := func(i: int) -> float: return _shoulder_out(i, side)
		var so := [[b, 0.0], [a, 0.02]] if side < 0.0 else [[a, 0.02], [b, 0.0]]
		for run: Array in _runs(hidden, 0):
			_mesh(_ribbon(so, 1.0, run[0], run[1], run[0] == 0 and run[1] == t.n), sh_mat).name = "Shoulder"


## 土路赛道：路面网格比可行驶区宽 VERGE m，边缘在着色器里不规则地过渡到草；没有路缘石，路肩是草地
const VERGE := 1.6


func _build_dirt_road() -> void:
	var t := track
	var un: Dictionary = theme.get("unpaved", {})
	var params := {
		"unpaved": true, "half_width": t.half_width + VERGE, "verge": VERGE, "track_length": t.length,
		"verge_color": Color(theme["shoulder"]), "checker": t == main,
	}
	for key: String in ["dirt_a", "dirt_b", "grass_a", "grass_b", "mud_a", "mud_b"]:
		if un.has(key):
			params[key] = Color(un[key])
	var road_mat := _shader_mat(ROAD_SHADER, params)
	var offs: Array = []
	for k in 9:
		var f := lerpf(-1.0, 1.0, k / 8.0)
		offs.append([func(i: int) -> float: return f * (t.hw[i] + VERGE), 0.02 if t == main else 0.04])
	var hidden := _hidden_mask()
	var weights := _surface_weights()
	for run: Array in _runs(hidden, 1):
		_mesh(_ribbon(offs, 1.0, run[0], run[1], run[0] == 0 and run[1] == t.n, weights), road_mat).name = "Road"
	var sh_mat := _shader_mat(GROUND_SHADER, {"tint": Color(theme["shoulder"]), "use_vertex_color": false,
		"kind": GROUND_KIND.get(ThemesData.base_of(theme), 0), "detail": 0.3})
	for side: float in [-1.0, 1.0]:
		var a := func(i: int) -> float: return side * (t.hw[i] + VERGE - 0.05)
		var b := func(i: int) -> float: return _shoulder_out(i, side)
		var so := [[b, 0.0], [a, 0.015]] if side < 0.0 else [[a, 0.015], [b, 0.0]]
		for run: Array in _runs(hidden, 0):
			_mesh(_ribbon(so, 1.0, run[0], run[1], run[0] == 0 and run[1] == t.n), sh_mat).name = "Shoulder"


## 每个采样点的路面权重（r 土路 / g 草路 / b 泥泞），前后 ±10 m 平滑过渡
func _surface_weights() -> PackedColorArray:
	var n := track.n
	var raw: Array[Vector3] = []
	raw.resize(n)
	for i in n:
		match track.surface[i]:
			2: raw[i] = Vector3(0, 1, 0)
			3: raw[i] = Vector3(0, 0, 1)
			_: raw[i] = Vector3(1, 0, 0)
	var r := maxi(1, roundi(10.0 / track.spacing))
	var out := PackedColorArray()
	out.resize(n)
	for i in n:
		var acc := Vector3.ZERO
		for k in range(-r, r + 1):
			acc += raw[track._idx(i + k)]
		acc /= float(2 * r + 1)
		out[i] = Color(acc.x, acc.y, acc.z)
	return out


# ———————————————— 护墙 ————————————————

func _build_walls() -> void:
	var w: Dictionary = theme["wall"]
	var style: int = WALL_STYLES.get(w["style"], 0)
	var mat := _shader_mat(WALL_SHADER, {"style": style, "color_a": Color(w["a"]), "color_b": Color(w["b"])})
	for side: float in [-1.0, 1.0]:
		var mask := PackedByteArray()
		mask.resize(track.n)
		var all_wall := true
		for i in track.n:
			mask[i] = 0 if track.edge_at(i, side) == TrackData.EDGE_WALL else 1
			all_wall = all_wall and mask[i] == 0
		if all_wall and track.closed:
			_mesh(_wall_mesh(side, 0, track.n + 1), mat, true).name = "Wall"
			continue
		var runs := _runs(mask, 0)
		# 闭合赛道：跨过起点的首尾两段接起来
		if track.closed and runs.size() > 1 and runs[0][0] == 0 and runs[-1][1] == track.n:
			var last: Array = runs.pop_back()
			runs[0] = [last[0], track.n + runs[0][1]]
		for run: Array in runs:
			if run[1] - run[0] >= 2:
				_mesh(_wall_mesh(side, run[0], run[1]), mat, true).name = "Wall"


## 一侧护墙，采样 [from, to)（to 可超过 n 绕回；整圈时 to = n + 1）。截面：内立面 + 顶面 + 外立面，底部下探 1.6 m 盖住地形缝隙
func _wall_mesh(side: float, from: int, to: int) -> ArrayMesh:
	var n := track.n
	var bottom := -1.6
	# [墙内侧往外的偏移, dy, v]：0 = 墙内侧（wo），WALL_T = 墙外侧
	var prof := [
		[0.0, bottom, bottom / WALL_H], [0.0, WALL_H, 1.0],
		[0.0, WALL_H, 1.0], [WALL_T, WALL_H, 1.0],
		[WALL_T, WALL_H, 1.0], [WALL_T, bottom, bottom / WALL_H],
	]
	var pcount := prof.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := to - from
	for k in rows:
		var i := (from + k) % n
		var u := (from + k) * track.spacing
		for c in pcount:
			var lat: float = side * (track.wo[i] + float(prof[c][0]))
			st.set_uv(Vector2(u, prof[c][2]))
			st.add_vertex(Vector3(track.px[i] + track.nx[i] * lat, track.py[i] + prof[c][1], track.pz[i] + track.nz[i] * lat))
	for k in rows - 1:
		for pair: Array in [[0, 1], [2, 3], [4, 5]]:
			var a: int = k * pcount + pair[0]
			var b: int = k * pcount + pair[1]
			var c := a + pcount
			var d := b + pcount
			if side > 0.0:
				st.add_index(a); st.add_index(c); st.add_index(b)
				st.add_index(b); st.add_index(c); st.add_index(d)
			else:
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals()
	return st.commit()


# ———————————————— 发车格 ————————————————

## 在赛道上铺一个四边形：s 区间 [sa, sb]，横向 [la, lb]，抬高 dy
func _quad(sa: float, sb: float, la: float, lb: float, dy: float, steps := 1) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in steps + 1:
		var s := sa + (sb - sa) * k / steps
		var a := track.point_at(s, la)
		var b := track.point_at(s, lb)
		st.set_uv(Vector2(0.0, float(k) / steps))
		st.add_vertex(a + Vector3(0, dy, 0))
		st.set_uv(Vector2(1.0, float(k) / steps))
		st.add_vertex(b + Vector3(0, dy, 0))
	for k in steps:
		var o := k * 2
		st.add_index(o); st.add_index(o + 2); st.add_index(o + 1)
		st.add_index(o + 1); st.add_index(o + 2); st.add_index(o + 3)
	st.generate_normals()
	return st.commit()


func _build_grid_marks() -> void:
	var mat := _shader_mat(MARK_SHADER)
	for slot in track.grid:
		var sp := track.spacing
		var mi := _mesh(_quad(slot["s"] - 1.6 / sp, slot["s"] + 1.8 / sp, slot["lateral"] - 1.25, slot["lateral"] + 1.25, 0.04), mat)
		mi.name = "GridMark"


# ———————————————— 加速带 / 跳台 ————————————————

func _build_pads() -> void:
	var mat := _shader_mat(PAD_SHADER)
	for pad in track.boost_pads:
		var s: float = pad["s"]
		var hl: float = pad["half_len_s"]
		var mi := _mesh(_quad(s - hl, s + hl, pad["lateral"] - pad["half_width"], pad["lateral"] + pad["half_width"], 0.05, 4), mat)
		mi.name = "BoostPad"


func _build_ramps() -> void:
	if track.ramps.is_empty():
		return
	var wooden := ThemesData.base_of(theme) == "forest"
	var top_mat := _shader_mat(RAMP_SHADER, {"side": false, "wood": wooden})
	var side_mat := _shader_mat(RAMP_SHADER, {"side": true, "wood": wooden})
	side_mat.set_shader_parameter("side", true)
	for r in track.ramps:
		var hw := track.hw_at(r["s"]) + 0.4
		var steps := maxi(4, ceili(r["len_s"]))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in steps + 1:
			var s: float = r["s"] + r["len_s"] * k / steps
			var h: float = r["height"] * k / steps
			var cy := track.center_y(s)
			var a := track.point_at(s, -hw)
			var b := track.point_at(s, hw)
			st.set_uv(Vector2(0.0, float(k) / steps))
			st.add_vertex(Vector3(a.x, cy + h + 0.04, a.z))
			st.set_uv(Vector2(1.0, float(k) / steps))
			st.add_vertex(Vector3(b.x, cy + h + 0.04, b.z))
		for k in steps:
			var o := k * 2
			st.add_index(o); st.add_index(o + 2); st.add_index(o + 1)
			st.add_index(o + 1); st.add_index(o + 2); st.add_index(o + 3)
		st.generate_normals()
		_mesh(st.commit(), top_mat, true).name = "RampTop"

		# 两侧立面与末端落差面
		var ss := SurfaceTool.new()
		ss.begin(Mesh.PRIMITIVE_TRIANGLES)
		var base := 0
		for lat: float in [-hw, hw]:
			for k in steps + 1:
				var s: float = r["s"] + r["len_s"] * k / steps
				var h: float = r["height"] * k / steps
				var p := track.point_at(s, lat)
				var cy := track.center_y(s)
				ss.set_uv(Vector2(float(k) / steps * 3.0, 0.0))
				ss.add_vertex(Vector3(p.x, cy - 0.2, p.z))
				ss.set_uv(Vector2(float(k) / steps * 3.0, 1.0))
				ss.add_vertex(Vector3(p.x, cy + h + 0.04, p.z))
			for k in steps:
				var o := base + k * 2
				ss.add_index(o); ss.add_index(o + 1); ss.add_index(o + 2)
				ss.add_index(o + 1); ss.add_index(o + 3); ss.add_index(o + 2)
			base += (steps + 1) * 2
		var s_end: float = r["s"] + r["len_s"]
		var e1 := track.point_at(s_end, -hw)
		var e2 := track.point_at(s_end, hw)
		var cye := track.center_y(s_end)
		var hh: float = r["height"]
		for v: Array in [[e1, cye - 0.2, Vector2(0, 0)], [e2, cye - 0.2, Vector2(6, 0)], [e1, cye + hh + 0.04, Vector2(0, 1)], [e2, cye + hh + 0.04, Vector2(6, 1)]]:
			var pv: Vector3 = v[0]
			ss.set_uv(v[2])
			ss.add_vertex(Vector3(pv.x, v[1], pv.z))
		ss.add_index(base); ss.add_index(base + 2); ss.add_index(base + 1)
		ss.add_index(base + 1); ss.add_index(base + 2); ss.add_index(base + 3)
		ss.generate_normals()
		_mesh(ss.commit(), side_mat, true).name = "RampSide"


# ———————————————— 高架 ————————————————

## 路面明显高于地形的区段：桥面底板、侧裙、桥墩（避开下层路面）
func _build_bridges() -> void:
	var n := track.n
	var elevated := PackedByteArray()
	elevated.resize(n)
	for i in n:
		var g := terrain.height_at(track.px[i], track.pz[i])
		elevated[i] = 1 if track.py[i] - g > 1.6 else 0
	var night: bool = theme.get("night", false)
	var wooden := ThemesData.base_of(theme) == "forest"
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color("#3A3D57") if night else (Color("#7A5436") if wooden else Color("#9A8F84"))
	deck_mat.roughness = 0.85
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("#4A4E6E") if night else (Color("#6B4A30") if wooden else Color("#B8AEA2"))
	pillar_mat.roughness = 0.8
	var light_mat := StandardMaterial3D.new()
	light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_mat.albedo_color = Color(theme["wall"]["a"])
	light_mat.emission_enabled = true
	light_mat.emission = Color(theme["wall"]["a"])
	light_mat.emission_energy_multiplier = 3.0

	# 连续高架区段（首尾外扩 3 个采样，盖住接缝）
	var runs: Array = []
	var start := -1
	for k in n + 1:
		var e := k < n and elevated[k] == 1
		if e and start < 0:
			start = k
		elif not e and start >= 0:
			runs.append([maxi(0, start - 3), mini(n, k + 3)])
			start = -1
	var t := track
	for run: Array in runs:
		var r_out := func(i: int) -> float: return t.wo[i] + WALL_T
		var l_out := func(i: int) -> float: return -(t.wo[i] + WALL_T)
		_mesh(_ribbon([[r_out, -1.3], [l_out, -1.3]], 0.1, run[0], run[1], false), deck_mat).name = "Deck"
		for side: float in [-1.0, 1.0]:
			var e := r_out if side > 0.0 else l_out
			var offs := [[e, -0.2], [e, -1.3]] if side > 0.0 else [[e, -1.3], [e, -0.2]]
			_mesh(_ribbon(offs, 0.1, run[0], run[1], false), deck_mat).name = "DeckSkirt"
			if night:
				var e2 := func(i: int) -> float: return side * (t.wo[i] + WALL_T + 0.03)
				var offs2 := [[e2, -0.55], [e2, -0.75]] if side > 0.0 else [[e2, -0.75], [e2, -0.55]]
				_mesh(_ribbon(offs2, 0.1, run[0], run[1], false), light_mat).name = "DeckLight"

	# 桥墩：每 ~18 m 一对，放在路面左右各 0.55 半宽处；若下方是另一段赛道则跳过
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.5
	cyl.height = 1.0
	cyl.radial_segments = 12
	var xforms: Array[Transform3D] = []
	var step := maxi(1, roundi(18.0 / track.spacing))
	var i := 0
	while i < n:
		if elevated[i] == 1:
			for lat: float in [-track.hw[i] * 0.55, track.hw[i] * 0.55]:
				var p := track.point_at(float(i), lat)
				var ground := terrain.height_at(p.x, p.z)
				var h := p.y - 1.3 - ground
				if h < 1.0:
					continue
				var blocked := false
				for hit in track.nearest_all(p.x, p.z, track.wall_offset + 2.5):
					if float(hit["y"]) < p.y - 4.0:
						blocked = true
						break
				for rv in track.rivers:
					var rp: Vector3 = rv["pos"]
					if absf((p.x - rp.x) * float(rv["tx"]) + (p.z - rp.z) * float(rv["tz"])) < float(rv["width"]) * 0.5 + 1.5:
						blocked = true
				if blocked:
					continue
				xforms.append(Transform3D(Basis().scaled(Vector3(1, h, 1)), Vector3(p.x, ground + h * 0.5, p.z)))
		i += step
	if not xforms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cyl
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Pillars"
		mmi.multimesh = mm
		mmi.material_override = pillar_mat
		add_child(mmi)


# ———————————————— 悬崖 ————————————————

## 悬崖一侧：崖边土沿外是一道岩壁，从路面高度直落到下面的地形
func _build_cliffs() -> void:
	var t := track
	var mat := _shader_mat(GROUND_SHADER, {"tint": Color("#5A4636"), "use_vertex_color": false, "kind": 5, "detail": 0.5})
	for side: float in [-1.0, 1.0]:
		var mask := PackedByteArray()
		mask.resize(t.n)
		for i in t.n:
			mask[i] = 0 if t.edge_at(i, side) == TrackData.EDGE_CLIFF else 1
		for run: Array in _runs(mask, 1):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var rows: int = run[1] - run[0]
			for k in rows:
				var i: int = (run[0] + k) % t.n
				var lip := t.hw[i] + TrackData.CLIFF_LIP
				var foot := t.point_at(float(i), side * (lip + 4.5))
				var bottom := terrain.height_at(foot.x, foot.z) - 1.5
				var y0 := t.py[i]
				# 上半段几乎垂直，下半段向外斜出一点
				var prof := [[lip - 0.05, y0 + 0.01], [lip + 0.35, lerpf(y0, bottom, 0.45)], [lip + 1.6, bottom]]
				for c in prof.size():
					var lat: float = side * float(prof[c][0])
					st.set_uv(Vector2(float(c) / 2.0, (run[0] + k) * t.spacing * 0.2))
					st.add_vertex(Vector3(t.px[i] + t.nx[i] * lat, float(prof[c][1]), t.pz[i] + t.nz[i] * lat))
			for k in rows - 1:
				for c in 2:
					var a := k * 3 + c
					var b := a + 1
					var d := a + 3
					var e := d + 1
					if side > 0.0:
						st.add_index(a); st.add_index(d); st.add_index(b)
						st.add_index(b); st.add_index(d); st.add_index(e)
					else:
						st.add_index(a); st.add_index(b); st.add_index(d)
						st.add_index(b); st.add_index(e); st.add_index(d)
			st.generate_normals()
			_mesh(st.commit(), mat, true).name = "Cliff"
