class_name ItemView
extends Node3D
## 道具实体表现：道具箱（MultiMesh 彩虹立方 + 软阴影）、导弹、水炸弹、水柱、香蕉皮、水苍蝇。
## 仿真层的实体都是 Dictionary，按 "id" 跟踪：数组里出现新 id 就从节点池取一个，消失的 id 回收。

const BOX_SHADER := preload("res://assets/shaders/item_box.gdshader")
const BLOB_SHADER := preload("res://assets/shaders/fx_blob.gdshader")
const BOX_SIZE := 1.7
## 道具箱悬浮高度（相对路面）
const BOX_LIFT := 1.3


## 按 id 复用的节点池
class EntityPool:
	var parent: Node3D
	var factory: Callable
	var active := {}
	var free: Array[Node3D] = []
	var seen := {}

	func _init(p_parent: Node3D, p_factory: Callable) -> void:
		parent = p_parent
		factory = p_factory

	## 取得 id 对应的节点；新取出的节点带 meta "fresh" = true
	func acquire(id: int) -> Node3D:
		var o: Node3D = active.get(id)
		if o == null:
			if free.is_empty():
				o = Node3D.new()
				o.add_child(factory.call())
				parent.add_child(o)
			else:
				o = free.pop_back()
			o.visible = true
			o.set_meta("fresh", true)
			active[id] = o
		else:
			o.set_meta("fresh", false)
		seen[id] = true
		return o

	func sweep() -> void:
		for id: int in active.keys():
			if not seen.has(id):
				var o: Node3D = active[id]
				o.visible = false
				active.erase(id)
				free.append(o)
		seen.clear()

	func hide_all() -> void:
		seen.clear()
		sweep()


var track: TrackData
var _missiles: EntityPool
var _bombs: EntityPool
var _zones: EntityPool
var _bananas: EntityPool
var _flies: EntityPool
var _box_mm: MultiMeshInstance3D
var _blob_mm: MultiMeshInstance3D
var _box_scale := PackedFloat32Array()
var _box_vel := PackedFloat32Array()
var _box_was_active: Array[bool] = []
var _acc := {}
## 着色器预热：道具赛第一帧在相机前放一组极小的道具模型与状态特效，几帧后删除
var _warm: Node3D = null
var _warm_frames := 0
var _warmed := false


func setup(p_track: TrackData) -> void:
	name = "ItemView"
	track = p_track
	_missiles = EntityPool.new(self, FxModels.missile)
	_bombs = EntityPool.new(self, FxModels.water_bomb)
	_zones = EntityPool.new(self, FxModels.water_zone)
	_bananas = EntityPool.new(self, FxModels.banana)
	_flies = EntityPool.new(self, FxModels.water_fly)


func _build_boxes(count: int) -> void:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * BOX_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = BOX_SHADER
	mat.set_shader_parameter("half_size", BOX_SIZE * 0.5)
	box_mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box_mesh
	mm.instance_count = count
	_box_mm = MultiMeshInstance3D.new()
	_box_mm.name = "ItemBoxes"
	_box_mm.multimesh = mm
	_box_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box_mm.custom_aabb = AABB(Vector3(-6000, -1000, -6000), Vector3(12000, 3000, 12000))
	add_child(_box_mm)

	var blob := PlaneMesh.new()
	blob.size = Vector2(2.3, 2.3)
	var bmat := ShaderMaterial.new()
	bmat.shader = BLOB_SHADER
	blob.material = bmat
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.use_custom_data = true
	bm.mesh = blob
	bm.instance_count = count
	_blob_mm = MultiMeshInstance3D.new()
	_blob_mm.name = "ItemBoxShadows"
	_blob_mm.multimesh = bm
	_blob_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob_mm.custom_aabb = _box_mm.custom_aabb
	add_child(_blob_mm)

	_box_scale.resize(count)
	_box_scale.fill(1.0)
	_box_vel.resize(count)
	_box_vel.fill(0.0)
	_box_was_active.resize(count)
	_box_was_active.fill(true)


func update_view(dt: float, time: float, items: ItemSystem, effects: Effects) -> void:
	if items == null:
		if visible:
			visible = false
			for p: EntityPool in [_missiles, _bombs, _zones, _bananas, _flies]:
				p.hide_all()
		return
	visible = true
	_warm_up()
	_update_boxes(dt, time, items.boxes)
	_update_missiles(dt, time, items.missiles, effects)
	_update_flies(dt, time, items.water_flies, effects)
	_update_bombs(dt, time, items.water_bombs, effects)
	_update_zones(dt, time, items.water_zones, effects)
	_update_bananas(time, items.bananas)
	for p: EntityPool in [_missiles, _bombs, _zones, _bananas, _flies]:
		p.sweep()


func _warm_up() -> void:
	if _warmed:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _warm == null:
		_warm = Node3D.new()
		_warm.name = "ShaderWarmUp"
		for f: Callable in [FxModels.missile, FxModels.water_bomb, FxModels.water_zone, FxModels.banana, FxModels.water_fly]:
			_warm.add_child(f.call())
		var sfx := KartStatusFx.new()
		_warm.add_child(sfx)
		sfx.build_all()
		add_child(_warm)
	# 放在相机前 3 m、缩到几乎看不见（仍会被绘制，从而编译管线）
	_warm.global_transform = Transform3D(cam.global_basis.scaled(Vector3.ONE * 0.004), cam.global_position - cam.global_basis.z * 3.0)
	_warm_frames += 1
	if _warm_frames > 3:
		_warm.queue_free()
		_warm = null
		_warmed = true


func _rate(key: String, rate: float, dt: float) -> int:
	var a: float = _acc.get(key, 0.0) + rate * dt
	var n := int(a)
	_acc[key] = a - n
	return n


static func _ease_out_back(u: float) -> float:
	var c := 1.9
	var v := u - 1.0
	return 1.0 + (c + 1.0) * v * v * v + c * v * v


# —————————————————— 道具箱 ——————————————————

func _update_boxes(dt: float, time: float, boxes: Array[Dictionary]) -> void:
	if boxes.is_empty():
		return
	if _box_mm == null:
		_build_boxes(boxes.size())
	var mm := _box_mm.multimesh
	var bm := _blob_mm.multimesh
	var n := mini(boxes.size(), mm.instance_count)
	var tilt := Basis(Vector3(1.0, 0.0, 1.0).normalized(), 0.62)
	for i in n:
		var b := boxes[i]
		var active: bool = b["active"]
		# 拾取后迅速缩小；恢复时用弹簧弹出（略微过冲）
		var s := _box_scale[i]
		var sv := _box_vel[i]
		if active:
			if not _box_was_active[i]:
				s = 0.0
				sv = 9.0
			sv += (220.0 * (1.0 - s) - 13.0 * sv) * dt
			s += sv * dt
		else:
			s = move_toward(s, 0.0, dt * 9.0)
			sv = 0.0
		_box_was_active[i] = active
		_box_scale[i] = s
		_box_vel[i] = sv
		var bp: Vector3 = b["pos"]
		var ss := maxf(s, 0.0)
		var rot := Basis(Vector3.UP, time * 1.3 + i * 0.7) * tilt
		var pos := bp + Vector3(0.0, BOX_LIFT + sin(time * 2.5 + i) * 0.22, 0.0)
		mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3.ONE * maxf(ss, 0.001)), pos))
		mm.set_instance_custom_data(i, Color(float(i) * 0.137, clampf(ss * 1.5, 0.0, 1.0), 0.0, 0.0))
		bm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.6 + 0.4 * ss)), bp + Vector3(0.0, 0.06, 0.0)))
		bm.set_instance_custom_data(i, Color(clampf(ss, 0.0, 1.0), 0.0, 0.0, 0.0))


# —————————————————— 导弹 ——————————————————

func _update_missiles(dt: float, time: float, list: Array[Dictionary], effects: Effects) -> void:
	for m in list:
		var id: int = m["id"]
		var o := _missiles.acquire(id)
		var pos: Vector3 = m["pos"]
		var prev: Vector3 = m["prev_pos"]
		var dir: Vector3 = o.get_meta("dir", Vector3.FORWARD)
		var d := pos - prev
		if d.length_squared() > 1e-4:
			dir = dir.slerp(d.normalized(), minf(1.0, dt * 18.0)) if not o.get_meta("fresh") else d.normalized()
			o.set_meta("dir", dir)
		o.position = pos
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
		o.basis = Basis.looking_at(dir, up, true) * Basis(Vector3(0, 0, 1), time * 9.0)
		var model := o.get_child(0) as Node3D
		var flame := model.get_node("Flame") as Node3D
		flame.scale = Vector3(1.0, 1.0, randf_range(0.75, 1.35))
		if effects == null:
			continue
		# 尾迹：沿上一帧尾部到本帧尾部等距补点，快速飞行时也连贯
		var tail := pos - dir * 1.25
		var last: Vector3 = tail if o.get_meta("fresh") else o.get_meta("tail", tail)
		var dist := last.distance_to(tail)
		var steps := clampi(int(dist / 0.55), 1, 5)
		for k in steps:
			effects.missile_trail(last.lerp(tail, float(k + 1) / steps), -dir)
		o.set_meta("tail", tail)


# —————————————————— 水苍蝇 ——————————————————

func _update_flies(dt: float, time: float, list: Array[Dictionary], effects: Effects) -> void:
	for f in list:
		var id: int = f["id"]
		var o := _flies.acquire(id)
		var pos: Vector3 = f["pos"]
		var prev: Vector3 = f["prev_pos"]
		var dir: Vector3 = o.get_meta("dir", Vector3.FORWARD)
		var d := pos - prev
		if d.length_squared() > 1e-4:
			dir = dir.slerp(d.normalized(), minf(1.0, dt * 12.0)) if not o.get_meta("fresh") else d.normalized()
			o.set_meta("dir", dir)
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() < 1e-4:
			flat = Vector3.FORWARD
		o.position = pos + Vector3(0.0, 0.35 + sin(time * 9.0 + id) * 0.18, 0.0)
		o.basis = Basis.looking_at(flat.normalized(), Vector3.UP, true) * Basis(Vector3(1, 0, 0), -0.18 + sin(time * 6.0 + id) * 0.08)
		var body := o.get_child(0).get_node("Body") as Node3D
		var flap := sin(time * 55.0 + id)
		# 左翅根在 -X：绕 Z 轴负转为上扬
		for wn: String in ["WingL", "WingL2"]:
			(body.get_node(wn) as Node3D).rotation.z = -(0.4 + flap * 0.6)
		for wn: String in ["WingR", "WingR2"]:
			(body.get_node(wn) as Node3D).rotation.z = 0.4 + flap * 0.6
		body.scale = Vector3(1.0 + flap * 0.03, 1.0 - flap * 0.03, 1.0)
		if effects:
			for k in _rate("fly%d" % id, 30.0, dt):
				effects.water_drop(o.position - dir * 0.9 + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)),
					-dir * 3.0 + Vector3(0.0, 1.5, 0.0), 0.11)
			for k in _rate("flys%d" % id, 10.0, dt):
				effects.sparkle(o.position + Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.5), randf_range(-0.6, 0.6)), Color(0.6, 0.9, 1.0), 0.4, 0.3)


# —————————————————— 水炸弹 ——————————————————

func _update_bombs(dt: float, time: float, list: Array[Dictionary], effects: Effects) -> void:
	for w in list:
		var id: int = w["id"]
		var o := _bombs.acquire(id)
		var pos: Vector3 = w["pos"]
		o.position = pos
		var ball := o.get_child(0).get_node("Ball") as Node3D
		var wob := sin(time * 16.0 + id)
		ball.scale = Vector3(1.0 + wob * 0.1, 1.0 - wob * 0.12, 1.0 + wob * 0.1)
		ball.rotation = Vector3(time * 5.0, time * 2.0, 0.0)
		if effects:
			for k in _rate("bomb%d" % id, 24.0, dt):
				effects.water_drop(pos + FxModels.rand_ball(0.5), Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)), 0.12)


# —————————————————— 水柱 ——————————————————

func _update_zones(dt: float, time: float, list: Array[Dictionary], effects: Effects) -> void:
	for z in list:
		var id: int = z["id"]
		var o := _zones.acquire(id)
		var pos: Vector3 = z["pos"]
		var age: float = z["age"]
		var life: float = z["life"]
		var radius: float = z.get("radius", 4.4)
		var grow := _ease_out_back(clampf(age / 0.4, 0.0, 1.0))
		var shrink := clampf(life / 0.5, 0.0, 1.0)
		var k := radius / 4.4
		o.position = pos
		var model := o.get_child(0) as Node3D
		var col := model.get_node("Column") as Node3D
		var cap := model.get_node("Cap") as Node3D
		var pool := model.get_node("Pool") as Node3D
		var hy := maxf(0.02, grow * shrink)
		var wob := 1.0 + sin(time * 9.0) * 0.03
		col.scale = Vector3(k * (0.75 + 0.25 * shrink) * wob, hy, k * (0.75 + 0.25 * shrink) * wob)
		col.position.y = 3.5 * hy
		cap.scale = Vector3(k * (0.75 + 0.25 * shrink), 0.55 * clampf(grow, 0.0, 1.2) * (0.5 + 0.5 * shrink), k * (0.75 + 0.25 * shrink))
		cap.position.y = 7.0 * hy
		pool.scale = Vector3.ONE * k * clampf(age / 0.25, 0.2, 1.0)
		for mat: ShaderMaterial in o.get_child(0).get_meta("mats"):
			mat.set_shader_parameter("fade", shrink)
		if effects == null:
			continue
		# 顶部向外翻落的水花 + 底部溅起的水滴 + 柱内上升的气泡
		for n in _rate("zt%d" % id, 55.0 * shrink, dt):
			var a := randf() * TAU
			var dvec := Vector3(cos(a), 0.0, sin(a))
			effects.water_drop(pos + dvec * 3.2 * k + Vector3(0.0, 7.0 * hy, 0.0), dvec * randf_range(2.0, 4.5) + Vector3(0.0, randf_range(1.0, 4.0), 0.0), 0.2)
		for n in _rate("zb%d" % id, 40.0 * shrink, dt):
			var a2 := randf() * TAU
			var dvec2 := Vector3(cos(a2), 0.0, sin(a2))
			effects.water_drop(pos + dvec2 * 4.3 * k + Vector3(0.0, 0.2, 0.0), dvec2 * randf_range(1.5, 3.5) + Vector3(0.0, randf_range(3.0, 6.0), 0.0), 0.16)
		for n in _rate("zu%d" % id, 16.0 * shrink, dt):
			effects.sparkle(pos + FxModels.rand_disc(3.0 * k) + Vector3(0.0, randf_range(0.5, 5.5) * hy, 0.0), Color(0.75, 0.93, 1.0), 0.35, 0.5)


# —————————————————— 香蕉皮 ——————————————————

func _update_bananas(time: float, list: Array[Dictionary]) -> void:
	for b in list:
		var id: int = b["id"]
		var o := _bananas.acquire(id)
		var pos: Vector3 = b["pos"]
		var age: float = b.get("age", 1.0)
		var spin: float = b.get("spin", 0.0)
		o.position = pos + Vector3(0.0, 0.02, 0.0)
		o.rotation = Vector3(0.0, spin + time * 0.6, 0.0)
		var s := _ease_out_back(clampf(age / 0.3, 0.0, 1.0))
		o.scale = Vector3.ONE * maxf(s, 0.01)
		var body := o.get_child(0).get_node("Body") as Node3D
		body.position.y = maxf(0.0, (1.0 - clampf(age / 0.3, 0.0, 1.0))) * 0.8
