class_name TrackMesh
extends Node3D
## 赛道表现：路面、路缘、路肩、主题护墙、发车格、加速带、跳台、高架桥面与桥墩。
## 参考版 trackView.js 的 Godot 实现（道具箱由 ItemView 负责，起点门架由 Scenery 负责）。

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
const WALL_STYLES := {"fence": 0, "stone": 1, "ice": 2, "neon": 3, "log": 4, "tire": 5}
## 主题 → 地面着色器 kind
const GROUND_KIND := {"village": 0, "desert": 1, "snow": 2, "city": 3, "forest": 4, "circuit": 0}

var track: TrackData
var terrain: TerrainData
var theme: Dictionary


func build(p_track: TrackData, p_terrain: TerrainData) -> void:
	track = p_track
	terrain = p_terrain
	theme = track.theme
	name = "TrackMesh"
	_build_road()
	_build_walls()
	_build_grid_marks()
	_build_pads()
	_build_ramps()
	_build_bridges()


# ———————————————— 工具 ————————————————

## 沿赛道的横向条带。offsets: [[lateral, dy], ...] 从左到右（lateral 负为左）。
## u = 列序 / (列数 - 1)，v = 累计米数 × v_scale。from / to 为采样区间（to 可大于 n 表示绕回）。
func _ribbon(offsets: Array, v_scale: float, from := 0, to := -1, closed := true) -> ArrayMesh:
	var n := track.n
	if to < 0:
		to = n
	var cols := offsets.size()
	var count := to - from + (1 if closed else 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in count:
		var i := (from + k) % n
		var meters := (from + k) * track.spacing
		for c in cols:
			var lat: float = offsets[c][0]
			var dy: float = offsets[c][1]
			st.set_uv(Vector2(float(c) / (cols - 1), meters * v_scale))
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
	var hw := track.half_width
	var road_theme: Dictionary = theme["road"]
	var night: bool = theme.get("night", false)
	var road_mat := _shader_mat(ROAD_SHADER, {
		"base_color": Color(road_theme["base"]), "speck_color": Color(road_theme["speck"]),
		"line_color": Color(road_theme["line"]), "center_color": Color(road_theme["center"]),
		"half_width": hw, "track_length": track.length, "line_glow": 2.2 if night else 0.0,
		"wet": 0.35 if night else (0.15 if theme["id"] == "snow" else 0.0),
	})
	var road := _mesh(_ribbon([[-hw, 0.02], [-hw * 0.5, 0.02], [0.0, 0.02], [hw * 0.5, 0.02], [hw, 0.02]], 1.0), road_mat)
	road.name = "Road"

	var curb: Array = theme["curb"]
	var curb_mat := _shader_mat(CURB_SHADER, {"color_a": Color(curb[0]), "color_b": Color(curb[1]), "glow": 0.8 if night else 0.0})
	for side: float in [-1.0, 1.0]:
		var a := side * hw
		var b := side * (hw + CURB_W)
		var offs := [[b, 0.03], [a, 0.07]] if side < 0.0 else [[a, 0.07], [b, 0.03]]
		_mesh(_ribbon(offs, 1.0), curb_mat).name = "Curb"

	var sh_mat := _shader_mat(GROUND_SHADER, {"tint": Color(theme["shoulder"]), "use_vertex_color": false,
		"kind": GROUND_KIND.get(theme["id"], 0), "detail": 0.25})
	for side: float in [-1.0, 1.0]:
		var a := side * (hw + CURB_W)
		var b := side * (track.wall_offset + 0.2)
		var offs := [[b, 0.0], [a, 0.02]] if side < 0.0 else [[a, 0.02], [b, 0.0]]
		_mesh(_ribbon(offs, 1.0), sh_mat).name = "Shoulder"


# ———————————————— 护墙 ————————————————

func _build_walls() -> void:
	var w: Dictionary = theme["wall"]
	var style: int = WALL_STYLES.get(w["style"], 0)
	var mat := _shader_mat(WALL_SHADER, {"style": style, "color_a": Color(w["a"]), "color_b": Color(w["b"])})
	for side: float in [-1.0, 1.0]:
		_mesh(_wall_mesh(side), mat, true).name = "Wall"


## 护墙截面：内立面 + 顶面 + 外立面，底部下探 1.6 m 以盖住地形缝隙
func _wall_mesh(side: float) -> ArrayMesh:
	var n := track.n
	var inner := side * track.wall_offset
	var outer := side * (track.wall_offset + WALL_T)
	var bottom := -1.6
	# [lateral, dy, v]
	var prof := [
		[inner, bottom, bottom / WALL_H], [inner, WALL_H, 1.0],
		[inner, WALL_H, 1.0], [outer, WALL_H, 1.0],
		[outer, WALL_H, 1.0], [outer, bottom, bottom / WALL_H],
	]
	var pcount := prof.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n + 1:
		var i := k % n
		var u := k * track.spacing
		for c in pcount:
			var lat: float = prof[c][0]
			st.set_uv(Vector2(u, prof[c][2]))
			st.add_vertex(Vector3(track.px[i] + track.nx[i] * lat, track.py[i] + prof[c][1], track.pz[i] + track.nz[i] * lat))
	for k in n:
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
	var top_mat := _shader_mat(RAMP_SHADER, {"side": false})
	var side_mat := _shader_mat(RAMP_SHADER, {"side": true})
	side_mat.set_shader_parameter("side", true)
	var hw := track.half_width + 0.4
	for r in track.ramps:
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
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color("#3A3D57") if night else Color("#9A8F84")
	deck_mat.roughness = 0.85
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("#4A4E6E") if night else Color("#B8AEA2")
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
	var wo := track.wall_offset + WALL_T
	for run: Array in runs:
		_mesh(_ribbon([[wo, -1.3], [-wo, -1.3]], 0.1, run[0], run[1], false), deck_mat).name = "Deck"
		for side: float in [-1.0, 1.0]:
			var offs := [[side * wo, -0.2], [side * wo, -1.3]] if side > 0.0 else [[side * wo, -1.3], [side * wo, -0.2]]
			_mesh(_ribbon(offs, 0.1, run[0], run[1], false), deck_mat).name = "DeckSkirt"
			if night:
				var offs2 := [[side * (wo + 0.03), -0.55], [side * (wo + 0.03), -0.75]] if side > 0.0 else [[side * (wo + 0.03), -0.75], [side * (wo + 0.03), -0.55]]
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
			for lat: float in [-track.half_width * 0.55, track.half_width * 0.55]:
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
