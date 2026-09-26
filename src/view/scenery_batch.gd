class_name SceneryBatch
extends RefCounted
## 批量绘制：同一种网格的所有实例收集起来，最后每种网格一个 MultiMeshInstance3D。
## 小物件（花草、小石头）按 chunk 米分块，配合 visibility_range_end 远处整块剔除；大物件整张地图一个 MultiMesh。

var parent: Node3D
var _kinds := {}
var _order: Array[String] = []
## 统计：实例总数、MultiMesh 数
var instance_count := 0
var multimesh_count := 0


func _init(p_parent: Node3D) -> void:
	parent = p_parent


## 注册一种网格。opts: {shadow: bool, vis_end: float（0 = 不限）, chunk: float（0 = 不分块）, colors: bool}
func register(kind: String, mesh: Mesh, opts := {}) -> void:
	if _kinds.has(kind):
		return
	_kinds[kind] = {
		"mesh": mesh, "shadow": opts.get("shadow", false), "vis_end": float(opts.get("vis_end", 0.0)),
		"chunk": float(opts.get("chunk", 0.0)), "colors": opts.get("colors", false),
		"xforms": [] as Array[Transform3D], "cols": [] as Array[Color],
	}
	_order.append(kind)


func has(kind: String) -> bool:
	return _kinds.has(kind)


## color 为 sRGB（着色器里实例色按线性色相乘，这里先转换）
func add(kind: String, xf: Transform3D, color := Color(1, 1, 1)) -> void:
	var k: Dictionary = _kinds[kind]
	(k["xforms"] as Array[Transform3D]).append(xf)
	(k["cols"] as Array[Color]).append(color.srgb_to_linear())


func count(kind: String) -> int:
	return (_kinds[kind]["xforms"] as Array[Transform3D]).size() if _kinds.has(kind) else 0


## 生成节点
func commit() -> void:
	for kind in _order:
		var k: Dictionary = _kinds[kind]
		var xforms: Array[Transform3D] = k["xforms"]
		if xforms.is_empty():
			continue
		var cols: Array[Color] = k["cols"]
		var chunk: float = k["chunk"]
		var groups := {}
		if chunk > 0.0:
			for i in xforms.size():
				var o := xforms[i].origin
				var key := Vector2i(floori(o.x / chunk), floori(o.z / chunk))
				if not groups.has(key):
					groups[key] = PackedInt32Array()
				var arr: PackedInt32Array = groups[key]
				arr.append(i)
				groups[key] = arr
		else:
			var all := PackedInt32Array()
			all.resize(xforms.size())
			for i in xforms.size():
				all[i] = i
			groups[Vector2i.ZERO] = all
		for key: Vector2i in groups:
			var idx: PackedInt32Array = groups[key]
			_make("%s_%d_%d" % [kind.replace("/", "_"), key.x, key.y], k, xforms, cols, idx)


func _make(kind: String, k: Dictionary, xforms: Array[Transform3D], cols: Array[Color], idx: PackedInt32Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = k["colors"]
	mm.mesh = k["mesh"]
	mm.instance_count = idx.size()
	# 直接写缓冲区：每实例 12 个浮点（3x4 行主序）+ 可选 4 个颜色
	var stride := 16 if mm.use_colors else 12
	var buf := PackedFloat32Array()
	buf.resize(idx.size() * stride)
	var o := 0
	for i in idx:
		var t := xforms[i]
		var b := t.basis
		buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = t.origin.z
		if stride == 16:
			var c := cols[i]
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		o += stride
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = kind
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if k["vis_end"] > 0.0:
		mmi.visibility_range_end = k["vis_end"]
		mmi.visibility_range_end_margin = 10.0
	parent.add_child(mmi)
	instance_count += idx.size()
	multimesh_count += 1
