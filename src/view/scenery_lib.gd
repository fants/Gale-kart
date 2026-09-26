class_name SceneryLib
extends RefCounted
## 场景模型库：加载 Kenney GLB，把所有 MeshInstance3D 连同本地变换合并成一个 ArrayMesh，
## 并按主题调色板替换材质（Kenney 自然包的 GLB 材质是金属度 1、偏青的颜色，直接用会发灰发蓝）。
## 纯色材质烘焙进顶点色、共用一个材质，所以大多数模型只有一个表面（MultiMesh 一次绘制）；贴图 / 玻璃 / 水 / 自发光保留独立表面。
## 结果按「主题 + 路径」缓存，同一主题再次开赛不用重新合并。

const NATURE := "res://assets/models/nature/"
const RACING := "res://assets/models/racing/"
const CITY := "res://assets/models/city/"
const SNOW_SHADER := preload("res://assets/shaders/snow_cover.gdshader")

## 通用调色板：Kenney 材质名 → 颜色
const BASE_PALETTE := {
	"grass": "#6DBE45", "dirt": "#B68457", "dirtDark": "#8A623F", "stone": "#B9BFC7", "stoneDark": "#8D95A1",
	"leafsGreen": "#5DBB46", "leafsDark": "#2F8246", "leafsFall": "#F29A38",
	"woodBark": "#8A5A3A", "woodBarkDark": "#5F402B", "woodBirch": "#EFE8DC", "wood": "#C68D57", "woodDark": "#8E5F39",
	"woodInner": "#EAC98F", "water": "#4FC3E8",
	"colorRed": "#FF5A5F", "colorRedDark": "#C9393F", "colorYellow": "#FFD23F", "colorPurple": "#A06BFF",
	"colorWhite": "#FFFFFF", "colorTan": "#E8C39A", "corn": "#F7D35A", "_defaultMat": "#ECE7E0",
	# 赛车包
	"grey": "#F1F2F5", "red": "#E8414B", "road": "#474C59", "bark": "#C9A26B", "glass": "#8CC8EE", "pylon": "#FF8A2A",
	"net": "#FFFFFF",
}

## 各主题对调色板的覆盖
const THEME_PALETTE := {
	"village": {},
	"desert": {
		"stone": "#E3B878", "stoneDark": "#C99458", "dirt": "#D8A15F", "dirtDark": "#B98147", "grass": "#9DBB5A",
		"leafsGreen": "#4FAE5A", "colorRed": "#D9A066", "colorRedDark": "#B37A45", "_defaultMat": "#F2DDB5",
	},
	"snow": {
		"leafsDark": "#2B6B55", "leafsGreen": "#3D8A5E", "grass": "#8FBF9A", "stone": "#AFC0D2", "stoneDark": "#8EA2B8",
		"dirt": "#9C8B80", "_defaultMat": "#F4F8FC",
	},
	"forest": {
		"leafsDark": "#2C6B3A", "leafsGreen": "#4C9A3C", "grass": "#5FA043", "dirt": "#8D7056", "dirtDark": "#6E5642",
		"stone": "#A3A7AD", "stoneDark": "#7E848D", "woodBarkDark": "#553A28",
	},
	"circuit": {"leafsGreen": "#5DAF46", "leafsDark": "#347F45"},
	"city": {"leafsGreen": "#3E8F5A", "leafsDark": "#2A6A4A", "grey": "#5A5F7A", "red": "#FF4DC4"},
}

static var _mesh_cache := {}
static var _mat_cache := {}
## surface_get_arrays 要从渲染服务器解码（较慢），同一网格表面只取一次
static var _arrays_cache := {}


## 取合并后的网格。opts: {center: bool（把包围盒底面中心移到原点）}
## 返回 {"mesh": ArrayMesh, "aabb": AABB}
static func model(theme_id: String, path: String, opts := {}) -> Dictionary:
	var key := theme_id + "|" + path + "|" + str(opts.get("center", false))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var ps: PackedScene = load(path)
	var root := ps.instantiate()
	var parts: Array[Array] = []
	var aabb := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		var xf := _rel_xform(mi, root)
		parts.append([mi.mesh, xf, mi])
		var a: AABB = xf * mi.mesh.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var shift := Vector3.ZERO
	if opts.get("center", false):
		shift = Vector3(-(aabb.position.x + aabb.size.x * 0.5), -aabb.position.y, -(aabb.position.z + aabb.size.z * 0.5))
	var mparts: Array = []
	for part in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var mi: MeshInstance3D = part[2]
		xf.origin += shift
		for sidx in mesh.get_surface_count():
			mparts.append([mesh, xf, material_for(theme_id, mi.get_active_material(sidx)), sidx])
	var out := merge(mparts)
	root.free()
	var res := {"mesh": out, "aabb": AABB(aabb.position + shift, aabb.size)}
	_mesh_cache[key] = res
	return res


static func _rel_xform(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## 按主题替换材质：有贴图的保留原材质（广告牌、旗帜、城市贴图集），其余按名字映射到调色板
static func material_for(theme_id: String, src: Material) -> Material:
	var mname := src.resource_name if src else "_defaultMat"
	var tex_mat := src as StandardMaterial3D
	if tex_mat and tex_mat.albedo_texture:
		var tkey := theme_id + "|tex|" + str(src.get_instance_id())
		if not _mat_cache.has(tkey):
			var m := tex_mat.duplicate() as StandardMaterial3D
			m.metallic = 0.0
			m.roughness = 0.9
			m.metallic_specular = 0.3
			_mat_cache[tkey] = m
		return _mat_cache[tkey]
	return palette_mat(theme_id, mname)


static func palette_color(theme_id: String, mname: String) -> Color:
	var over: Dictionary = THEME_PALETTE.get(theme_id, {})
	if over.has(mname):
		return Color(str(over[mname]))
	return Color(str(BASE_PALETTE.get(mname, "#DDDDDD")))


## 调色板材质：玻璃 / 水是独立材质，其余都是「烘焙色」——合并网格时颜色写进顶点色，
## 整个模型只剩一个表面、共用一个材质（一种模型一次绘制）。冰雪主题里彩色布料 / 花不积雪
static func palette_mat(theme_id: String, mname: String) -> Material:
	var key := theme_id + "|" + mname
	if _mat_cache.has(key):
		return _mat_cache[key]
	var col := palette_color(theme_id, mname)
	var mat: Material
	if mname == "glass":
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.25
		m.metallic = 0.35
		m.metallic_specular = 0.6
		mat = m
	elif mname == "water":
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.1
		m.emission_enabled = true
		m.emission = col * 0.25
		mat = m
	else:
		mat = bake_mat(theme_id, col, 0.0 if mname.begins_with("color") else 1.0)
	_mat_cache[key] = mat
	return mat


## 烘焙色占位材质：merge() 时换成 vcol_mat(vcol) 并把颜色（线性）写进顶点色，alpha 为积雪量
static func bake_mat(theme_id: String, color: Color, snow := 1.0) -> Material:
	# 只有冰雪主题需要不同的共享材质（积雪着色器）
	var vcol := "snow" if theme_id == "snow" else ""
	var key := "bake|%s|%s|%.2f" % [vcol, color.to_html(), snow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	var lin := color.srgb_to_linear()
	lin.a = snow
	m.set_meta("bake", lin)
	m.set_meta("vcol", vcol)
	_mat_cache[key] = m
	return m


## 顶点色共享材质（每主题一个；冰雪主题是积雪着色器，顶点色 alpha 控制积雪量）
static func vcol_mat(vcol: String) -> Material:
	var key := "vcol|" + vcol
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat: Material
	if vcol == "snow":
		var sm := ShaderMaterial.new()
		sm.shader = SNOW_SHADER
		sm.set_shader_parameter("base_color", Color(1, 1, 1))
		sm.set_shader_parameter("use_vertex_color", true)
		mat = sm
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1)
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.88
		m.metallic_specular = 0.25
		mat = m
	_mat_cache[key] = mat
	return mat


## 纯色材质（程序化物件用）：普通纯色走烘焙；emit > 0 自发光、tint = 乘 MultiMesh 实例色、或特殊粗糙度的是独立材质
static func flat_mat(color: Color, emit := 0.0, rough := 0.85, tint := false) -> Material:
	if emit <= 0.0 and not tint and rough >= 0.6:
		return bake_mat("", color, 0.0)
	var key := "flat|%s|%.2f|%.2f|%s" % [color.to_html(), emit, rough, tint]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic_specular = 0.3
	m.vertex_color_use_as_albedo = tint
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mat_cache[key] = m
	return m


## 按主题的纯色：冰雪主题朝上的面积雪（snow 为积雪量）。tint = 乘 MultiMesh 实例色（独立材质，如屋顶）
static func themed_mat(theme_id: String, color: Color, snow := 1.0, tint := false) -> Material:
	if not tint:
		return bake_mat(theme_id, color, snow)
	if theme_id != "snow" or snow <= 0.0:
		return flat_mat(color, 0.0, 0.85, true)
	var key := "snowflat|%s|%.2f" % [color.to_html(), snow]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = SNOW_SHADER
	sm.set_shader_parameter("base_color", color)
	sm.set_shader_parameter("snow_amount", snow)
	sm.set_shader_parameter("use_instance_color", true)
	_mat_cache[key] = sm
	return sm


## 把若干 [Mesh, Transform3D, Material(, 表面序号)] 合并成一个 ArrayMesh（同材质一个表面）；
## Material 为 null 时沿用各表面自己的材质；给了表面序号则只取该表面；烘焙色材质换成共享的顶点色材质。
## 直接拼接数组（比 SurfaceTool.append_from 快一个数量级）
## 基础网格的形状签名：类名 + 所有存储属性（材质除外）
static var _prim_props := {}


static func primitive_key(m: PrimitiveMesh, sidx: int) -> String:
	var cls := m.get_class()
	if not _prim_props.has(cls):
		var names: Array[String] = []
		for pr in m.get_property_list():
			var nm: String = pr["name"]
			if int(pr["usage"]) & PROPERTY_USAGE_STORAGE and nm != "material" and not nm.begins_with("resource_") and nm != "script":
				names.append(nm)
		_prim_props[cls] = names
	var key := "%s#%d" % [cls, sidx]
	for nm: String in _prim_props[cls]:
		key += "|" + str(m.get(nm))
	return key


static func merge(parts: Array) -> ArrayMesh:
	var groups := {}
	var order: Array[Material] = []
	for p: Array in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
		var surfaces: Array = [p[3]] if p.size() > 3 else range(mesh.get_surface_count())
		for sidx: int in surfaces:
			var mat: Material = p[2] if p[2] != null else mesh.surface_get_material(sidx)
			var bake := Color(1, 1, 1, 1)
			var baked := mat != null and mat.has_meta("bake")
			if baked:
				bake = mat.get_meta("bake")
				mat = vcol_mat(str(mat.get_meta("vcol")))
			if not groups.has(mat):
				groups[mat] = {"v": [], "n": [], "uv": [], "i": [], "c": [], "count": 0, "baked": baked}
				order.append(mat)
			var g: Dictionary = groups[mat]
			# 基础网格（盒子、圆柱等）按形状参数缓存顶点数组：surface_get_arrays 会先把网格传到 GPU，
			# 同样尺寸的盒子成百上千个时非常慢；模型网格按实例缓存
			var arr: Array
			if mesh is PrimitiveMesh:
				var pkey := primitive_key(mesh as PrimitiveMesh, sidx)
				if not _arrays_cache.has(pkey):
					_arrays_cache[pkey] = mesh.surface_get_arrays(sidx)
				arr = _arrays_cache[pkey]
			else:
				var akey := Vector2i(mesh.get_instance_id(), sidx)
				if not _arrays_cache.has(akey):
					_arrays_cache[akey] = mesh.surface_get_arrays(sidx)
				arr = _arrays_cache[akey]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nv := verts.size()
			(g["v"] as Array).append(xf * verts)
			var nrm := PackedVector3Array()
			if arr[Mesh.ARRAY_NORMAL] != null:
				nrm = nxf * (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array)
				for k in nrm.size():
					nrm[k] = nrm[k].normalized()
			else:
				nrm.resize(nv)
				nrm.fill(Vector3.UP)
			(g["n"] as Array).append(nrm)
			var uv := PackedVector2Array()
			if arr[Mesh.ARRAY_TEX_UV] != null:
				uv = arr[Mesh.ARRAY_TEX_UV]
			else:
				uv.resize(nv)
			(g["uv"] as Array).append(uv)
			# 顶点色：烘焙色；或源网格已经带顶点色（二次合并）；否则白色
			var cols := PackedColorArray()
			if not baked and arr[Mesh.ARRAY_COLOR] != null:
				cols = arr[Mesh.ARRAY_COLOR]
				g["baked"] = true
			else:
				cols.resize(nv)
				cols.fill(bake)
			(g["c"] as Array).append(cols)
			var base: int = g["count"]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				# 缓存里的数组是共享的，先复制再改偏移
				idx = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
				for k in idx.size():
					idx[k] += base
			else:
				idx.resize(nv)
				for k in nv:
					idx[k] = base + k
			(g["i"] as Array).append(idx)
			g["count"] = base + nv
	var out := ArrayMesh.new()
	for mat in order:
		var g: Dictionary = groups[mat]
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for a: PackedVector3Array in g["v"]:
			verts.append_array(a)
		for a: PackedVector3Array in g["n"]:
			nrms.append_array(a)
		for a: PackedVector2Array in g["uv"]:
			uvs.append_array(a)
		for a: PackedColorArray in g["c"]:
			cols.append_array(a)
		for a: PackedInt32Array in g["i"]:
			idx.append_array(a)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		if g["baked"]:
			arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
