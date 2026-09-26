class_name Scenery
extends Node3D
## 场景物件与主题装饰：Kenney 模型按主题批量摆放（每种模型一个 MultiMesh，小物件分块 + 可见距离），
## 程序化地标（风车、小屋、金字塔、雪人、冰晶、霓虹招牌……）、起点门架、天气粒子、河流瀑布、夜城灯光。
## 各主题的具体摆放在 scenery_rural / scenery_forest / scenery_circuit / scenery_city 里，这里提供公共工具与每帧更新。

## 物件尺寸类别 → MultiMesh 设置
const BIG := {"shadow": true}
const BIG_TINT := {"shadow": true, "colors": true}
const MID := {"shadow": false}
const MID_TINT := {"shadow": false, "colors": true}
const SMALL := {"shadow": false, "vis_end": 210.0, "chunk": 160.0}
const SMALL_TINT := {"shadow": false, "vis_end": 210.0, "chunk": 160.0, "colors": true}

var track: TrackData
var terrain: TerrainData
var theme: Dictionary
var theme_id := ""
## 主题自己的 id（派生主题与 theme_id 不同）
var variant := ""
var quality := "high"
## 密度系数（画质预设 scenery：0.4 / 0.7 / 1.0）
var density := 1.0
var particles_k := 1.0
var rng := RandomNumberGenerator.new()
var placer: SceneryPlacer
var batch: SceneryBatch
## 统计（调试 / 报告用）
var stats := {}

## 动画对象
var spinners: Array[Node3D] = []
var spin_speed: Array[float] = []
var bobbers: Array[Node3D] = []
var bob_base: Array[float] = []
var weather: SceneryWeather
## 夜城路灯：灯头位置 + 灯光池（按离相机距离分配）
var lamp_heads := PackedVector3Array()
var lamp_pool: Array[OmniLight3D] = []
var _lamp_timer := 0.0
## 霓虹闪烁的材质
var neon_mats: Array[StandardMaterial3D] = []
var neon_base: Array[float] = []

var _aabbs := {}
var _t0 := 0


func build(p_track: TrackData, p_terrain: TerrainData, p_quality: String, seed := 3) -> void:
	for step in prepare(p_track, p_terrain, p_quality, seed):
		step.call()


## 分帧构建：每步之间调用 breath（由调用方决定要不要让出一帧）
func build_async(p_track: TrackData, p_terrain: TerrainData, p_quality: String, breath: Callable, seed := 3) -> void:
	for step in prepare(p_track, p_terrain, p_quality, seed):
		step.call()
		await breath.call()


## 初始化并返回构建步骤（按顺序执行）
func prepare(p_track: TrackData, p_terrain: TerrainData, p_quality: String, seed := 3) -> Array[Callable]:
	name = "Scenery"
	_t0 = Time.get_ticks_usec()
	track = p_track
	terrain = p_terrain
	theme = track.theme
	# 派生主题（城镇 / 蘑菇森林）按基础主题取调色板与物件风格，自己的专属布景在 variant 分支里
	theme_id = ThemesData.base_of(theme)
	variant = str(theme["id"])
	quality = p_quality
	var qp := EnvironmentFactory.quality_preset(quality)
	density = qp["scenery"]
	particles_k = qp["particles"]
	rng.seed = seed * 7919 + track.n
	placer = SceneryPlacer.new(track, terrain, rng)
	batch = SceneryBatch.new(self)

	# 广告牌先占位，再铺主题布景
	var steps: Array[Callable] = [func() -> void: SceneryAds.build(self)]
	match variant:
		"town":
			steps.append_array(SceneryTown.steps(self))
		"mushroom":
			steps.append_array(SceneryMushroom.steps(self))
		"village":
			steps.append_array(SceneryRural.village_steps(self))
		"desert":
			steps.append_array(SceneryRural.desert_steps(self))
		"snow":
			steps.append_array(SceneryRural.snow_steps(self))
		"forest":
			steps.append_array(SceneryForest.steps(self))
		"circuit":
			steps.append_array(SceneryCircuit.steps(self))
		"city":
			steps.append_array(SceneryCity.steps(self))
	steps.append(_finish)
	return steps


func _finish() -> void:
	if theme_id != "circuit":
		_build_start_arch()
	batch.commit()
	weather = SceneryWeather.create(theme.get("weather", "none"), particles_k)
	if weather:
		add_child(weather.node)
	stats["instances"] = batch.instance_count
	stats["multimeshes"] = batch.multimesh_count
	stats["build_ms"] = (Time.get_ticks_usec() - _t0) / 1000.0


func update_view(dt: float, time: float, cam: Camera3D) -> void:
	for i in spinners.size():
		spinners[i].rotate_object_local(Vector3.BACK, spin_speed[i] * dt)
	for i in bobbers.size():
		bobbers[i].position.y = bob_base[i] + sin(time * 0.45 + i * 2.1) * 2.5
	if cam == null:
		return
	if weather:
		weather.follow(cam)
	if not lamp_pool.is_empty():
		_lamp_timer -= dt
		if _lamp_timer <= 0.0:
			_lamp_timer = 0.12
			_assign_lamps(cam.global_position)
	if not neon_mats.is_empty():
		for i in neon_mats.size():
			# 霓虹呼吸 + 偶尔的电流闪烁
			var ph := i * 1.7
			var k := 0.85 + sin(time * 2.2 + ph) * 0.15
			if sin(time * 17.0 + ph * 5.0) > 0.985:
				k *= 0.35
			neon_mats[i].emission_energy_multiplier = neon_base[i] * k


## 把灯光池分配给离相机最近的路灯（只开最近的，最多 lamp_pool.size() 盏）
func _assign_lamps(cp: Vector3) -> void:
	var n := lamp_heads.size()
	var d := PackedFloat32Array()
	d.resize(n)
	var idx: Array[int] = []
	for i in n:
		d[i] = cp.distance_squared_to(lamp_heads[i])
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return d[a] < d[b])
	for k in lamp_pool.size():
		var l := lamp_pool[k]
		if k < n and d[idx[k]] < 160.0 * 160.0:
			l.visible = true
			l.global_position = lamp_heads[idx[k]] + Vector3(0, -0.6, 0)
		else:
			l.visible = false


# ———————————————— 公共工具（供各主题脚本使用） ————————————————

## 注册一种 Kenney 模型并返回它的批量键。short 形如 "nature/tree_oak"；opts 同 SceneryBatch.register，外加 center
func kind(short: String, opts := {}) -> String:
	if batch.has(short):
		return short
	var parts := short.split("/")
	var dir: String = {"nature": SceneryLib.NATURE, "racing": SceneryLib.RACING, "city": SceneryLib.CITY}[parts[0]]
	var m: Dictionary = SceneryLib.model(theme_id, dir + parts[1] + ".glb", {"center": opts.get("center", parts[0] != "nature")})
	batch.register(short, m["mesh"], opts)
	_aabbs[short] = m["aabb"]
	return short


## 注册程序化网格
func kind_mesh(key: String, mesh: Mesh, opts := {}) -> String:
	if not batch.has(key):
		batch.register(key, mesh, opts)
		_aabbs[key] = mesh.get_aabb()
	return key


func aabb_of(k: String) -> AABB:
	return _aabbs.get(k, AABB())


func put(k: String, pos: Vector3, yaw: float, scale: Vector3, color := Color(1, 1, 1)) -> void:
	batch.add(k, SceneryPlacer.xform(pos, yaw, scale), color)


func put_xf(k: String, xform: Transform3D, color := Color(1, 1, 1)) -> void:
	batch.add(k, xform, color)


func pick(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]


func rf(a: float, b: float) -> float:
	return a + rng.randf() * (b - a)


## 数量 × 密度
func dn(count: float) -> int:
	return maxi(0, roundi(count * density))


## 实例染色：在白色附近轻微抖动明暗与色相（树叶、花等），base 可指定主色
func tint(base := Color(1, 1, 1), amount := 0.12) -> Color:
	var v := 1.0 - rng.randf() * amount
	return Color(base.r * v * rf(0.94, 1.04), base.g * v * rf(0.96, 1.04), base.b * v * rf(0.92, 1.04))


## 批量摆放：spots 里每个点随机选一种模型、随机朝向和缩放
func scatter_kinds(kinds: Array, spots: Array[Vector4], smin: float, smax: float, tinted := false, sink := 0.12, yscale := Vector2(0.9, 1.15)) -> void:
	for p in spots:
		var k: String = pick(kinds)
		var s := rf(smin, smax)
		put(k, Vector3(p.x, p.y - sink, p.z), rng.randf() * TAU, Vector3(s, s * rf(yscale.x, yscale.y), s), tint() if tinted else Color(1, 1, 1))


## 加一个普通节点（程序化地标）
func add_node(n: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	add_child(n)
	n.position = pos
	n.rotation.y = yaw
	return n


func add_spinner(n: Node3D, speed: float) -> void:
	spinners.append(n)
	spin_speed.append(speed)


func add_bobber(n: Node3D) -> void:
	bobbers.append(n)
	bob_base.append(n.position.y)


## 沿赛道的局部坐标系：原点在 (s, lateral) 处的路面，+Z 为前进方向，+X 为左侧（与赛道法线相反）
func track_frame(s: float, lateral: float, y := INF) -> Transform3D:
	var p := track.point_at(s, lateral)
	var i := int(track.wrap_s(s))
	var fwd := Vector3(track.tx[i], 0, track.tz[i]).normalized()
	var right := Vector3(track.nx[i], 0, track.nz[i]).normalized()
	# 基向量：x = -right 使 (x, y, z) 为右手系且 +Z 朝前
	var b := Basis(-right, Vector3.UP, fwd)
	return Transform3D(b, Vector3(p.x, p.y if y == INF else y, p.z))


## 让模型 +Z 朝向赛道：返回绕 Y 的角度
func yaw_to_track(x: float, z: float) -> float:
	return placer.facing(x, z)


# ———————————————— 起点门架（circuit 以外） ————————————————

func _build_start_arch() -> void:
	var arch := SceneryProps.start_arch(track, theme)
	var f := track_frame(0.0, 0.0, track.center_y(0.0))
	add_child(arch)
	arch.transform = f
	# 柱脚落到地面：柱子向下延伸，差多少补多少
	var span := track.wall_offset + 2.2
	var lowest := INF
	for sd: float in [-1.0, 1.0]:
		var p := f * Vector3(sd * span, 0, 0)
		lowest = minf(lowest, terrain.height_at(p.x, p.z))
	var drop := f.origin.y - lowest
	if drop > 0.8:
		var ext := MeshInstance3D.new()
		var mat := SceneryLib.themed_mat(theme_id, Color("#1B1F3B"), 0.0)
		var parts: Array = []
		for sd: float in [-1.0, 1.0]:
			parts.append([SceneryProps.box(Vector3(1.6, drop + 1.0, 1.6)), SceneryProps.xf(Vector3(sd * span, -drop * 0.5 - 0.5, 0)), mat])
		ext.mesh = SceneryLib.merge(parts)
		arch.add_child(ext)
