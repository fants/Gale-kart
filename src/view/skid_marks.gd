class_name SkidMarks
extends Node3D
## 漂移胎痕：每条胎痕（id = 车序号 × 2 + 左右）一个环形缓冲 ArrayMesh，最多 SEGMENTS 段。
## 新的一段只把 4 个顶点写进 GPU（surface_update_vertex_region / attribute_region），不重建网格。
## 顶点 UV.x 记录生成时刻，着色器按「现在 - 生成时刻」淡出（FADE_TIME 秒）。

const SEGMENTS := 600
const FADE_TIME := 8.0
## 两次落点之间的最小 / 最大距离（米）：太近不加段，太远视为断开（复位、传送）
const MIN_STEP := 0.5
const MAX_STEP := 6.0
const SHADER := preload("res://assets/shaders/fx_skid.gdshader")

var _mat: ShaderMaterial
var _marks := {}
var _now := 0.0
var _indices := PackedInt32Array()
var _vstride := 12
var _astride := 16


func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("fade_time", FADE_TIME)
	configure("village", false)
	_indices.resize(SEGMENTS * 6)
	for i in SEGMENTS:
		var v := i * 4
		var o := i * 6
		_indices[o] = v
		_indices[o + 1] = v + 2
		_indices[o + 2] = v + 1
		_indices[o + 3] = v + 1
		_indices[o + 4] = v + 2
		_indices[o + 5] = v + 3


## 按主题设置胎痕颜色：冰面浅（压出来的雪槽），夜城更深
func configure(theme_id: String, night: bool) -> void:
	var c := Color(0.07, 0.07, 0.09, 0.42)
	match theme_id:
		"snow":
			c = Color(0.5, 0.62, 0.78, 0.34)
		"desert":
			c = Color(0.24, 0.17, 0.12, 0.36)
		"forest":
			c = Color(0.1, 0.08, 0.06, 0.4)
	if night:
		c = Color(0.02, 0.02, 0.04, 0.5)
	_mat.set_shader_parameter("mark_color", c)
	# 先建一条空胎痕（全是零面积三角形），让材质在第一次漂移前就编译好
	if is_inside_tree():
		_get_mark(-1)


func _process(dt: float) -> void:
	_now += dt
	_mat.set_shader_parameter("now", _now)


func _get_mark(id: int) -> Dictionary:
	if _marks.has(id):
		return _marks[id]
	var verts := PackedVector3Array()
	verts.resize(SEGMENTS * 4)
	var uvs := PackedVector2Array()
	uvs.resize(SEGMENTS * 4)
	uvs.fill(Vector2(-1000.0, 0.0))
	var uv2 := PackedVector2Array()
	uv2.resize(SEGMENTS * 4)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var fmt := mesh.surface_get_format(0)
	_vstride = RenderingServer.mesh_surface_get_format_vertex_stride(fmt, SEGMENTS * 4)
	_astride = RenderingServer.mesh_surface_get_format_attribute_stride(fmt, SEGMENTS * 4)
	var mi := MeshInstance3D.new()
	mi.name = "Skid%d" % id
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(Vector3(-6000, -1000, -6000), Vector3(12000, 3000, 12000))
	add_child(mi)
	var m := {"mesh": mesh, "next": 0, "has_last": false, "last": Vector3.ZERO, "side": Vector3.ZERO, "t": 0.0, "dist": 0.0}
	_marks[id] = m
	return m


## 每帧每条胎痕调用一次；on = false 表示断开（下一次从新的起点开始）
func add(id: int, pos: Vector3, dir: Vector3, width: float, on: bool) -> void:
	if not on:
		if _marks.has(id):
			_marks[id]["has_last"] = false
		return
	var m := _get_mark(id)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 1e-6:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var side := Vector3(-flat.z, 0.0, flat.x) * (width * 0.5)
	if not m["has_last"]:
		m["has_last"] = true
		m["last"] = pos
		m["side"] = side
		m["t"] = _now
		return
	var last: Vector3 = m["last"]
	var d := pos.distance_to(last)
	if d < MIN_STEP:
		return
	if d > MAX_STEP:
		m["last"] = pos
		m["side"] = side
		m["t"] = _now
		return
	var ls: Vector3 = m["side"]
	var t0: float = m["t"]
	var d0: float = m["dist"]
	var d1 := d0 + d
	var seg: int = m["next"]
	m["next"] = (seg + 1) % SEGMENTS
	var a := last - ls
	var b := last + ls
	var c := pos - side
	var e := pos + side
	var vf := PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, e.x, e.y, e.z])
	var af := PackedFloat32Array([t0, 0.0, d0, 0.0, t0, 1.0, d0, 0.0, _now, 0.0, d1, 0.0, _now, 1.0, d1, 0.0])
	var mesh: ArrayMesh = m["mesh"]
	mesh.surface_update_vertex_region(0, seg * 4 * _vstride, vf.to_byte_array())
	mesh.surface_update_attribute_region(0, seg * 4 * _astride, af.to_byte_array())
	m["last"] = pos
	m["side"] = side
	m["t"] = _now
	m["dist"] = fmod(d1, 1000.0)


## 清除全部胎痕（重开比赛 / 回放跳转时用）
func clear() -> void:
	for id: int in _marks:
		var m: Dictionary = _marks[id]
		m["has_last"] = false
	for c in get_children():
		c.queue_free()
	_marks.clear()
