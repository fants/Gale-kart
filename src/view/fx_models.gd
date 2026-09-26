class_name FxModels
extends RefCounted
## 特效用的程序化小模型与共享材质：导弹、水炸弹、水柱、香蕉皮、水苍蝇、星星、乌云、飞碟等。
## 材质按 key 缓存，同类实体共用；模型本地坐标 +Z 为前方。

const BUBBLE_SHADER := preload("res://assets/shaders/bubble.gdshader")
const WATER_SHADER := preload("res://assets/shaders/fx_water.gdshader")
const RIPPLE_SHADER := preload("res://assets/shaders/fx_ripple.gdshader")

static var _mats := {}
static var _meshes := {}


## 卡通材质（带轮廓光）；emission > 0 时自发光
static func toon(color: Color, emission := 0.0, rough := 0.55) -> StandardMaterial3D:
	var key := "toon_%s_%.2f_%.2f" % [color.to_html(), emission, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.4
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


## 不受光照的纯色材质；add = 叠加混合（火焰、光线）
static func unlit(color: Color, add := false, energy := 1.0) -> StandardMaterial3D:
	var key := "unlit_%s_%s_%.2f" % [color.to_html(), add, energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if color.a < 1.0 or add:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.disable_receive_shadows = true
	_mats[key] = m
	return m


## 水体材质（水炸弹、水苍蝇身体）：泡泡着色器的蓝色版本
static func water_mat() -> ShaderMaterial:
	if _mats.has("water"):
		return _mats["water"]
	var m := ShaderMaterial.new()
	m.shader = BUBBLE_SHADER
	m.set_shader_parameter("tint", Color(0.25, 0.62, 1.0))
	m.set_shader_parameter("base_alpha", 0.55)
	m.set_shader_parameter("rim_alpha", 0.95)
	m.set_shader_parameter("iridescence", 0.15)
	m.set_shader_parameter("wobble", 0.0)
	_mats["water"] = m
	return m


## 球内均匀随机点
static func rand_ball(r: float) -> Vector3:
	var z := randf_range(-1.0, 1.0)
	var a := randf() * TAU
	var rr := sqrt(1.0 - z * z)
	return Vector3(rr * cos(a), z, rr * sin(a)) * r * pow(randf(), 1.0 / 3.0)


## 水平圆盘内均匀随机点
static func rand_disc(r: float) -> Vector3:
	var a := randf() * TAU
	var rr := sqrt(randf()) * r
	return Vector3(cos(a) * rr, 0.0, sin(a) * rr)


static func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if node_name != "":
		mi.name = node_name
	return mi


static func _sphere(r: float, segs := 16) -> SphereMesh:
	var key := "sphere_%.3f_%d" % [r, segs]
	if _meshes.has(key):
		return _meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs >> 1)
	_meshes[key] = m
	return m


static func _cyl(top: float, bottom: float, h: float, segs := 12) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f_%d" % [top, bottom, h, segs]
	if _meshes.has(key):
		return _meshes[key]
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	_meshes[key] = m
	return m


static func _box(size: Vector3) -> BoxMesh:
	var key := "box_%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var m := BoxMesh.new()
	m.size = size
	_meshes[key] = m
	return m


static func _torus(inner: float, outer: float, rings := 24, ring_segs := 8) -> TorusMesh:
	var key := "torus_%.3f_%.3f_%d" % [inner, outer, rings]
	if _meshes.has(key):
		return _meshes[key]
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = ring_segs
	_meshes[key] = m
	return m


## 沿折线生成管子（平行移动标架），radii 为每个点的半径；两端封口。
## flatten < 1 时截面压扁成椭圆（宽度方向为起点处与路径、世界上方都垂直的方向）
static func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides := 8, flatten := 1.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := pts.size()
	var nrm := Vector3.ZERO
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i == 0:
			nrm = t.cross(Vector3.UP) if absf(t.dot(Vector3.UP)) < 0.9 else t.cross(Vector3.RIGHT)
		else:
			nrm = nrm - t * nrm.dot(t)
		nrm = nrm.normalized()
		var bin := t.cross(nrm)
		for s in sides:
			var a := float(s) / sides * TAU
			verts.append(pts[i] + (nrm * cos(a) + bin * sin(a) * flatten) * radii[i])
			norms.append((nrm * cos(a) * flatten + bin * sin(a)).normalized())
	for i in n - 1:
		for s in sides:
			var a0 := i * sides + s
			var a1 := i * sides + (s + 1) % sides
			var b0 := a0 + sides
			var b1 := a1 + sides
			idx.append_array(PackedInt32Array([a0, b0, a1, a1, b0, b1]))
	# 封口
	for end in 2:
		var ci := verts.size()
		var pi := 0 if end == 0 else n - 1
		var t2 := (pts[1] - pts[0]).normalized() if end == 0 else (pts[n - 1] - pts[n - 2]).normalized()
		verts.append(pts[pi])
		norms.append(-t2 if end == 0 else t2)
		var base := pi * sides
		for s in sides:
			var s1 := (s + 1) % sides
			if end == 0:
				idx.append_array(PackedInt32Array([ci, base + s1, base + s]))
			else:
				idx.append_array(PackedInt32Array([ci, base + s, base + s1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 立体五角星（XY 平面，两面鼓起），用于眩晕星星
static func star_mesh() -> ArrayMesh:
	if _meshes.has("star"):
		return _meshes["star"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := PI / 2.0 + float(i) / 10.0 * TAU
		var r := 0.2 if i % 2 == 0 else 0.09
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	var front := Vector3(0, 0, 0.07)
	var back := Vector3(0, 0, -0.07)
	for i in 10:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 10]
		st.add_vertex(front)
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(back)
		st.add_vertex(a)
		st.add_vertex(b)
	st.generate_normals()
	var m := st.commit()
	_meshes["star"] = m
	return m


# —————————————————— 道具实体 ——————————————————

## 导弹：白色弹体 + 红色弹头 / 尾翼 + 喷口火焰（子节点 "Flame"）
static func missile() -> Node3D:
	var g := Node3D.new()
	var white := toon(Color("#F7FAFF"), 0.0, 0.35)
	var red := toon(Color("#FF4D5E"), 0.0, 0.45)
	var dark := toon(Color("#3A3F5C"))
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.35
	cap.radial_segments = 14
	cap.rings = 6
	g.add_child(_mi(cap, white, Vector3.ZERO, Vector3(PI / 2, 0, 0)))
	g.add_child(_mi(_cyl(0.0, 0.245, 0.5, 14), red, Vector3(0, 0, 0.78), Vector3(PI / 2, 0, 0)))
	g.add_child(_mi(_cyl(0.25, 0.25, 0.12, 14), red, Vector3(0, 0, 0.2), Vector3(PI / 2, 0, 0)))
	g.add_child(_mi(_cyl(0.17, 0.2, 0.22, 12), dark, Vector3(0, 0, -0.72), Vector3(PI / 2, 0, 0)))
	for i in 4:
		var fin := Node3D.new()
		fin.rotation.z = i * PI / 2.0
		fin.add_child(_mi(_box(Vector3(0.05, 0.36, 0.38)), red, Vector3(0, 0.3, -0.46)))
		g.add_child(fin)
	g.add_child(_mi(_sphere(0.06, 8), unlit(Color(1.0, 0.3, 0.3), false, 3.0), Vector3(0, 0.2, 0.45)))
	var flame := Node3D.new()
	flame.name = "Flame"
	flame.position = Vector3(0, 0, -0.85)
	flame.add_child(_mi(_cyl(0.0, 0.2, 0.9, 10), unlit(Color(1.0, 0.62, 0.25, 0.9), true, 2.2), Vector3(0, 0, -0.45), Vector3(-PI / 2, 0, 0)))
	flame.add_child(_mi(_cyl(0.0, 0.11, 0.55, 8), unlit(Color(1.0, 0.95, 0.75, 1.0), true, 2.5), Vector3(0, 0, -0.27), Vector3(-PI / 2, 0, 0)))
	g.add_child(flame)
	g.scale = Vector3.ONE * 1.25
	return g


## 水炸弹：蓝色水球 + 顶部扎口 + 高光（子节点 "Ball"）
static func water_bomb() -> Node3D:
	var g := Node3D.new()
	var ball := Node3D.new()
	ball.name = "Ball"
	g.add_child(ball)
	ball.add_child(_mi(_sphere(0.6, 20), water_mat()))
	ball.add_child(_mi(_cyl(0.05, 0.16, 0.22, 10), toon(Color("#2F7BE8")), Vector3(0, 0.66, 0)))
	ball.add_child(_mi(_torus(0.04, 0.09, 12, 6), toon(Color("#2F7BE8")), Vector3(0, 0.8, 0), Vector3(PI / 2, 0, 0)))
	ball.add_child(_mi(_sphere(0.13, 8), unlit(Color(1, 1, 1, 0.85)), Vector3(-0.25, 0.28, 0.4), Vector3.ZERO, Vector3(1.0, 0.7, 0.5)))
	return g


## 水柱：外壁（双面两遍）+ 顶部水冠 + 地面水洼（子节点 "Column" "Cap" "Pool"）
static func water_zone() -> Node3D:
	var g := Node3D.new()
	var outer := ShaderMaterial.new()
	outer.shader = WATER_SHADER
	var inner := ShaderMaterial.new()
	inner.shader = WATER_SHADER
	inner.set_shader_parameter("inner", 1.0)
	inner.next_pass = outer
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 3.3
	col_mesh.bottom_radius = 4.3
	col_mesh.height = 7.0
	col_mesh.radial_segments = 40
	col_mesh.rings = 10
	col_mesh.cap_top = false
	col_mesh.cap_bottom = false
	var col := _mi(col_mesh, inner, Vector3(0, 3.5, 0), Vector3.ZERO, Vector3.ONE, "Column")
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(col)
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 3.3
	cap_mesh.height = 2.6
	cap_mesh.is_hemisphere = true
	cap_mesh.radial_segments = 40
	cap_mesh.rings = 8
	var cap_mat := ShaderMaterial.new()
	cap_mat.shader = WATER_SHADER
	cap_mat.set_shader_parameter("cap", 1.0)
	var cap := _mi(cap_mesh, cap_mat, Vector3(0, 7.0, 0), Vector3.ZERO, Vector3(1.0, 0.55, 1.0), "Cap")
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(cap)
	var pool_mesh := PlaneMesh.new()
	pool_mesh.size = Vector2(11.0, 11.0)
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = RIPPLE_SHADER
	var pool := _mi(pool_mesh, pool_mat, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3.ONE, "Pool")
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(pool)
	g.set_meta("mats", [inner, outer, cap_mat, pool_mat])
	return g


## 香蕉皮：立着的一截黄色香蕉（顶端果柄）+ 四片摊在地上、末端微翘的宽果皮
static func banana() -> Node3D:
	var g := Node3D.new()
	var peel := toon(Color("#FFD84A"), 0.15, 0.5)
	var brown := toon(Color("#7A4A26"))
	var body := Node3D.new()
	body.name = "Body"
	g.add_child(body)
	var stub := _meshes.get("banana_stub") as ArrayMesh
	if stub == null:
		var sp := PackedVector3Array()
		var sr := PackedFloat32Array()
		for i in 7:
			var u := i / 6.0
			sp.append(Vector3(0.0, 0.08 + u * 0.62, sin(u * 1.4) * 0.06))
			sr.append(lerpf(0.19, 0.09, u * u))
		stub = tube(sp, sr, 10)
		_meshes["banana_stub"] = stub
	body.add_child(_mi(stub, peel))
	body.add_child(_mi(_cyl(0.045, 0.065, 0.16, 6), brown, Vector3(0, 0.76, 0.06)))
	var petal := _meshes.get("banana_petal") as ArrayMesh
	if petal == null:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 10:
			var u := i / 9.0
			# 从香蕉中部向外垂到地面，末端微微翘起
			var y := 0.42 * pow(1.0 - u, 1.6) + 0.05 + (0.08 * smoothstep(0.75, 1.0, u))
			pts.append(Vector3(0.0, y, 0.12 + u * 0.72))
			radii.append(lerpf(0.17, 0.08, u) * (1.0 - 0.3 * smoothstep(0.85, 1.0, u)))
		petal = tube(pts, radii, 10, 0.32)
		_meshes["banana_petal"] = petal
	for i in 4:
		var p := Node3D.new()
		p.rotation.y = i * PI / 2.0 + 0.4 + (0.15 if i % 2 == 0 else -0.1)
		p.add_child(_mi(petal, peel))
		p.add_child(_mi(_sphere(0.06, 8), brown, Vector3(0.0, 0.12, 0.84), Vector3.ZERO, Vector3(1.4, 0.6, 1.0)))
		body.add_child(p)
	g.scale = Vector3.ONE * 1.35
	return g


## 水苍蝇：水滴身体 + 大眼睛 + 两对快速扇动的翅膀（子节点 "Body" "WingL" "WingR" "WingL2" "WingR2"）
static func water_fly() -> Node3D:
	var g := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	g.add_child(body)
	var water := water_mat()
	body.add_child(_mi(_sphere(0.38, 18), water, Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 0.9, 1.05)))
	body.add_child(_mi(_cyl(0.0, 0.3, 0.6, 14), water, Vector3(0, 0.02, -0.46), Vector3(-PI / 2, 0, 0)))
	var white := toon(Color(1, 1, 1), 0.2, 0.3)
	var black := toon(Color("#1B1F3B"), 0.0, 0.2)
	for sx: float in [-1.0, 1.0]:
		body.add_child(_mi(_sphere(0.13, 10), white, Vector3(0.14 * sx, 0.14, 0.28)))
		body.add_child(_mi(_sphere(0.065, 8), black, Vector3(0.15 * sx, 0.15, 0.39)))
	var wing_mat := toon(Color(0.86, 0.95, 1.0), 0.6, 0.3)
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var pivot := Node3D.new()
		pivot.name = ["WingL", "WingR", "WingL2", "WingR2"][i]
		pivot.position = Vector3(0.08 * sx, 0.3, 0.05 if i < 2 else -0.17)
		var w := _mi(_sphere(0.36, 10), wing_mat, Vector3(0.34 * sx, 0.0, 0.0), Vector3(0.0, 0.25 * sx if i < 2 else -0.3 * sx, 0.0),
			Vector3(1.0, 0.07, 0.5 if i < 2 else 0.38))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(w)
		body.add_child(pivot)
	g.scale = Vector3.ONE * 1.35
	return g
