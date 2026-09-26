class_name TerrainMesh
extends Node3D
## 地形网格：按 TerrainData 采样高度，顶点色混合主题地面色，外圈加远景地平面。

const GROUND_SHADER := preload("res://assets/shaders/ground.gdshader")

## 构建耗时（毫秒），调试用
var build_ms := 0


func build(track: TrackData, terrain: TerrainData, cell: float) -> void:
	name = "Terrain"
	var t0 := Time.get_ticks_msec()
	var theme := track.theme
	var b := terrain.bounds
	var nxs := ceili((b["max_x"] - b["min_x"]) / cell)
	var nzs := ceili((b["max_z"] - b["min_z"]) / cell)
	var x0: float = b["min_x"]
	var z0: float = b["min_z"]
	var w := nxs + 1
	var h := nzs + 1

	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for iz in h:
		var z := z0 + iz * cell
		for ix in w:
			heights[iz * w + ix] = terrain.height_at(x0 + ix * cell, z)

	var c_base := Color(theme["ground"]["base"])
	var c_alt := Color(theme["ground"]["alt"])
	var c_far := Color(theme["ground"]["far"])
	var noise := FastNoiseLite.new()
	noise.seed = 21
	noise.frequency = 1.0 / 60.0
	noise.fractal_octaves = 3

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * h)
	normals.resize(w * h)
	colors.resize(w * h)
	for iz in h:
		for ix in w:
			var idx := iz * w + ix
			var x := x0 + ix * cell
			var z := z0 + iz * cell
			var y := heights[idx]
			verts[idx] = Vector3(x, y, z)
			var hl := heights[iz * w + maxi(ix - 1, 0)]
			var hr := heights[iz * w + mini(ix + 1, w - 1)]
			var hd := heights[maxi(iz - 1, 0) * w + ix]
			var hu := heights[mini(iz + 1, h - 1) * w + ix]
			normals[idx] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			var nn := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var col := c_base.lerp(c_alt, nn)
			var high := clampf((y - 18.0) / 40.0, 0.0, 1.0)
			# 顶点色在着色器里按线性色使用，这里先把 sRGB 主题色转成线性
			colors[idx] = col.lerp(c_far, high * 0.8).srgb_to_linear()

	var indices := PackedInt32Array()
	indices.resize(nxs * nzs * 6)
	var o := 0
	for iz in nzs:
		for ix in nxs:
			var a := iz * w + ix
			var bb := a + 1
			var c := a + w
			var d := c + 1
			indices[o] = a; indices[o + 1] = bb; indices[o + 2] = c
			indices[o + 3] = bb; indices[o + 4] = d; indices[o + 5] = c
			o += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("kind", TrackMesh.GROUND_KIND.get(ThemesData.base_of(theme), 0))
	mat.set_shader_parameter("detail", 0.2)
	mat.set_shader_parameter("sparkle", 0.6 if ThemesData.base_of(theme) == "snow" else 0.0)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainSurface"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

	# 远景地平面：一个大圆环，挡住地形边缘外的空洞
	var far := MeshInstance3D.new()
	far.name = "FarGround"
	var cx: float = (b["min_x"] + b["max_x"]) * 0.5
	var cz: float = (b["min_z"] + b["max_z"]) * 0.5
	var inner_r := maxf(nxs, nzs) * cell * 0.45
	far.mesh = _ring(inner_r, 4000.0, 48)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = c_far
	fm.roughness = 1.0
	far.material_override = fm
	far.position = Vector3(cx, 2.0 if terrain.flat else 28.0, cz)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	build_ms = Time.get_ticks_msec() - t0


func _ring(r0: float, r1: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in seg + 1:
		var a := TAU * i / seg
		st.add_vertex(Vector3(sin(a) * r0, 0, cos(a) * r0))
		st.add_vertex(Vector3(sin(a) * r1, 0, cos(a) * r1))
	for i in seg:
		var o := i * 2
		st.add_index(o); st.add_index(o + 1); st.add_index(o + 2)
		st.add_index(o + 1); st.add_index(o + 3); st.add_index(o + 2)
	return st.commit()
