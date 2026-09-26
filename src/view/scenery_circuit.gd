class_name SceneryCircuit
extends RefCounted
## 疾风赛车场（夕阳）：起点门架（赛车包 overheadLights + 横幅塔）、起终点直道外侧连排看台、内侧维修区与维修通道、
## 直道上的灯柱 / 广告牌 / 横幅塔、弯道外侧轮胎堆、围场帐篷与摄影塔、远处树林。


static func build(s: Scenery) -> void:
	for step in steps(s):
		step.call()


static func steps(s: Scenery) -> Array[Callable]:
	return [
		func() -> void: _start_gantry(s),
		func() -> void: _grandstands(s),
		func() -> void: _pits(s),
		func() -> void: _corner_stands(s),
		func() -> void: _straights(s),
		func() -> void: _tire_stacks(s),
		func() -> void: _trees(s),
	]


## 模型 +Z 朝向赛道时的朝向角（side：物件在赛道哪一侧，+1 为法线方向）
static func _yaw_facing(s: Scenery, i: int, side: float) -> float:
	return atan2(-s.track.nx[i] * side, -s.track.nz[i] * side)


## 采样 i 附近是否直道（前后 range 米内曲率都很小）
static func _straight(s: Scenery, i: int, range_m := 30.0) -> bool:
	var k := ceili(range_m / s.track.spacing)
	for j in range(-k, k + 1, 2):
		if absf(s.track.curv[posmod(i + j, s.track.n)]) > 0.004:
			return false
	return true


# ———————————————— 起点门架 ————————————————

static func _start_gantry(s: Scenery) -> void:
	var t := s.track
	var f := s.track_frame(0.0, 0.0, t.center_y(0.0))
	var gantry := s.kind("racing/overheadLights", Scenery.BIG)
	var ab := s.aabb_of(gantry)
	# 模型门腿内侧在 |x| = 0.5（外侧 0.63）：横向缩放到门腿内侧落在护墙外 1.2 m
	var sx := (t.wall_offset + 1.2) / 0.5
	s.put_xf(gantry, f * Transform3D(Basis.from_scale(Vector3(sx, 13.0, 11.0)), Vector3(0, -0.2, 0)))
	var tower := s.kind("racing/bannerTowerRed", Scenery.BIG)
	for sd: float in [-1.0, 1.0]:
		s.put_xf(tower, f * Transform3D(Basis(Vector3.UP, PI * 0.5 * sd) * Basis.from_scale(Vector3.ONE * 10.0), Vector3(sd * (0.63 * sx + 3.5), -0.2, 3.0)))
	# 门架上的赛道名
	var root := Node3D.new()
	root.name = "GantryText"
	s.add_child(root)
	root.transform = f
	var h := ab.size.y * 13.0 - 1.6
	for face: float in [-1.0, 1.0]:
		root.add_child(SceneryProps.label("GALE CIRCUIT", SceneryProps.FONT_EN, 160, Color(1, 1, 1), Vector3(0, h, face * 1.2), PI if face < 0.0 else 0.0, 0.012))


# ———————————————— 看台 ————————————————

## 起终点直道外侧（远离内场的一侧）连排看台，中段有顶棚
static func _grandstands(s: Scenery) -> void:
	var t := s.track
	var side := _outside(s, 0)
	var covered := s.kind("racing/grandStandCovered", Scenery.BIG)
	var open := s.kind("racing/grandStand", Scenery.BIG)
	var awning := s.kind("racing/grandStandAwning", Scenery.BIG)
	var sc := 10.0
	var lat := side * (t.wall_offset + 5.0 + sc * 0.5)
	var dist := -44.0
	var n := 0
	while dist < 150.0:
		# 起点门架两侧的横幅塔附近留空
		if absf(dist) < 14.0:
			dist += sc
			continue
		var ss := dist / t.spacing
		var p := t.point_at(ss, lat)
		var i := int(t.wrap_s(ss))
		if s.placer.clear_of_track(p.x, p.z, sc * 0.5, 1.0):
			var k: String = covered if absf(dist - 50.0) < 45.0 else (awning if n % 5 == 2 else open)
			s.put(k, Vector3(p.x, s.placer.ground(p.x, p.z, 4.0) - 0.15, p.z), _yaw_facing(s, i, side), Vector3.ONE * sc)
			s.placer.mark(p.x, p.z, sc * 0.72)
			n += 1
		dist += sc
	# 看台后面一排旗杆
	var flags := [s.kind("racing/flagRed", Scenery.BIG), s.kind("racing/flagGreen", Scenery.BIG), s.kind("racing/flagCheckers", Scenery.BIG)]
	var dd := -36.0
	while dd < 140.0:
		var ss := dd / t.spacing
		var p := t.point_at(ss, side * (t.wall_offset + 5.0 + sc + 2.5))
		if s.placer.clear_of_track(p.x, p.z, 1.0, 1.0):
			s.put(s.pick(flags), Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.1, p.z), _yaw_facing(s, int(t.wrap_s(ss)), side), Vector3.ONE * 9.0)
		dd += 12.0


## 起点处哪一侧是外侧：法线方向上离其他路段更远的一侧
static func _outside(s: Scenery, i: int) -> float:
	var best := 1.0
	var best_d := -1.0
	for sd: float in [1.0, -1.0]:
		var p := s.track.point_at(float(i), sd * 120.0)
		var d := s.placer.approx_dist(p.x, p.z)
		if d > best_d:
			best_d = d
			best = sd
	return best


## 最急的几个弯外侧放小看台（三联）+ 旗帜，面向弯心
static func _corner_stands(s: Scenery) -> void:
	var t := s.track
	var stand := s.kind("racing/grandStand", Scenery.BIG)
	var awning := s.kind("racing/grandStandAwning", Scenery.BIG)
	var flags := [s.kind("racing/flagRed", Scenery.BIG), s.kind("racing/flagGreen", Scenery.BIG), s.kind("racing/flagCheckers", Scenery.BIG)]
	# 找曲率局部最大的弯（彼此相隔 120 m 以上）
	var peaks: Array[int] = []
	var order: Array[int] = []
	for i in t.n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return absf(t.curv[a]) > absf(t.curv[b]))
	for i in order:
		if absf(t.curv[i]) < 0.02 or peaks.size() >= 4:
			break
		var far := true
		for q in peaks:
			var d := absi(q - i)
			if minf(d, t.n - d) * t.spacing < 120.0:
				far = false
		if far:
			peaks.append(i)
	var sc := 8.0
	for i in peaks:
		var sd := 1.0 if t.curv[i] > 0.0 else -1.0
		var placed := 0
		for k: int in [-1, 0, 1]:
			var ss := float(i) + k * sc / t.spacing
			var p := t.point_at(ss, sd * (t.wall_offset + 6.0 + sc * 0.5))
			if not s.placer.ok(p.x, p.z, sc * 0.55, false, true):
				continue
			var ii := int(t.wrap_s(ss))
			s.put(awning if k == 0 else stand, Vector3(p.x, s.placer.ground(p.x, p.z, 3.5) - 0.15, p.z), _yaw_facing(s, ii, sd), Vector3.ONE * sc)
			s.placer.mark(p.x, p.z, sc * 0.7)
			placed += 1
		if placed == 0:
			continue
		for k: int in [-2, 2]:
			var ss := float(i) + k * sc / t.spacing
			var p := t.point_at(ss, sd * (t.wall_offset + 3.0))
			if s.placer.clear_of_track(p.x, p.z, 0.5, 0.5):
				s.put(s.pick(flags), Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.1, p.z), _yaw_facing(s, int(t.wrap_s(ss)), sd), Vector3.ONE * 9.0)


# ———————————————— 维修区 ————————————————

static func _pits(s: Scenery) -> void:
	var t := s.track
	var side := -_outside(s, 0)
	var garage := s.kind("racing/pitsGarage", Scenery.BIG)
	var closed := s.kind("racing/pitsGarageClosed", Scenery.BIG)
	var office := s.kind("racing/pitsOffice", Scenery.BIG)
	var roof := s.kind("racing/pitsOfficeRoof", Scenery.BIG)
	var sc := 10.0
	var lane_in := t.wall_offset + 1.0
	var lane_out := t.wall_offset + 11.0
	var lat := side * (lane_out + sc * 0.5)
	var from := 16.0
	var to := 160.0
	var dist := from
	var j := 0
	while dist <= to:
		var ss := dist / t.spacing
		var p := t.point_at(ss, lat)
		var i := int(t.wrap_s(ss))
		if s.placer.clear_of_track(p.x, p.z, sc * 0.5, 1.0):
			var k: String = office if (dist == from or dist + sc > to) else (roof if j == 7 else (closed if j % 4 == 3 else garage))
			s.put(k, Vector3(p.x, s.placer.ground(p.x, p.z, 4.0) - 0.1, p.z), _yaw_facing(s, i, side), Vector3.ONE * sc)
			s.placer.mark(p.x, p.z, sc * 0.72)
		dist += sc
		j += 1
	# 维修通道：护墙与车库之间的一条沥青带 + 白色分道线
	var asphalt := SceneryLib.flat_mat(Color("#4A4F5C"), 0.0, 0.95)
	var white := SceneryLib.flat_mat(Color("#EDEDED"), 0.0, 0.8)
	var a0 := int((from - sc * 0.5) / t.spacing)
	var a1 := int((to + sc * 0.5) / t.spacing)
	var mi := MeshInstance3D.new()
	mi.name = "PitLane"
	mi.mesh = SceneryLib.merge([
		[_lane(s, a0, a1, side * lane_in, side * lane_out, 0.06), Transform3D.IDENTITY, asphalt],
		[_lane(s, a0, a1, side * (lane_in + 3.2), side * (lane_in + 3.5), 0.09), Transform3D.IDENTITY, white],
	])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(mi)
	# 维修区后面的围场：帐篷、雷达、卡车一样的小屋
	var tents := [s.kind("racing/tentLong", Scenery.BIG), s.kind("racing/tentClosedLong", Scenery.BIG), s.kind("racing/tentRoofDouble", Scenery.BIG)]
	var radar := s.kind("racing/radarEquipment", Scenery.BIG)
	var d2 := from + 4.0
	while d2 < to:
		var ss := d2 / t.spacing
		var p := t.point_at(ss, side * (lane_out + sc + s.rf(10.0, 24.0)))
		if s.placer.ok(p.x, p.z, 5.0, false, true):
			s.put(s.pick(tents), Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.1, p.z), _yaw_facing(s, int(t.wrap_s(ss)), side) + s.pick([0.0, PI * 0.5]), Vector3.ONE * s.rf(7.0, 9.0))
			s.placer.mark(p.x, p.z, 5.5)
		d2 += s.rf(12.0, 20.0)
	var rp := t.point_at((from + 30.0) / t.spacing, side * (lane_out + sc + 34.0))
	if s.placer.ok(rp.x, rp.z, 4.0, false, true):
		s.put(radar, Vector3(rp.x, s.terrain.height_at(rp.x, rp.z) - 0.1, rp.z), s.rng.randf() * TAU, Vector3.ONE * 10.0)


## 沿赛道的一条平带（地面高度取地形与路面的较高者，略抬高避免闪烁）
static func _lane(s: Scenery, a0: int, a1: int, l0: float, l1: float, dy: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := minf(l0, l1)
	var hi := maxf(l0, l1)
	for k in range(a0, a1 + 1):
		for lat: float in [lo, hi]:
			var p := s.track.point_at(float(k), lat)
			var y := maxf(s.terrain.height_at(p.x, p.z), s.track.center_y(float(k)) - 0.4) + dy
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.z))
	for k in a1 - a0:
		var o := k * 2
		# 列 = 横向（向右），行 = 前进：与 TrackMesh 相同的顺时针正面
		st.add_index(o); st.add_index(o + 2); st.add_index(o + 1)
		st.add_index(o + 1); st.add_index(o + 2); st.add_index(o + 3)
	return st.commit()


# ———————————————— 直道装饰 ————————————————

static func _straights(s: Scenery) -> void:
	var t := s.track
	var light := s.kind("racing/lightPostLarge", Scenery.BIG)
	var boards := [s.kind("racing/billboard", Scenery.BIG), s.kind("racing/billboardLow", Scenery.BIG)]
	var towers := [s.kind("racing/bannerTowerRed", Scenery.BIG), s.kind("racing/bannerTowerGreen", Scenery.BIG)]
	var cam := s.kind("racing/camera_exclusive", Scenery.BIG)
	var step := roundi(36.0 / t.spacing)
	var j := 0
	for i in range(0, t.n, step):
		j += 1
		if not _straight(s, i, 20.0):
			continue
		var sd := 1.0 if j % 2 == 0 else -1.0
		# 灯柱：紧贴护墙外侧，灯头朝赛道
		var p := t.point_at(float(i), sd * (t.wall_offset + 1.6))
		if s.placer.clear_of_track(p.x, p.z, 0.5, 0.8) and s.placer.is_free(p.x, p.z, 1.0):
			s.put(light, Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.1, p.z), _yaw_facing(s, i, sd) + PI * 0.5, Vector3.ONE * 11.0)
			s.placer.mark(p.x, p.z, 1.0)
		# 广告牌 / 横幅塔：另一侧稍远
		var q := t.point_at(float(i) + step * 0.5, -sd * (t.wall_offset + 6.0))
		var qi := int(t.wrap_s(float(i) + step * 0.5))
		if s.placer.ok(q.x, q.z, 4.5, false, true):
			if j % 3 == 0:
				s.put(s.pick(towers), Vector3(q.x, s.terrain.height_at(q.x, q.z) - 0.1, q.z), _yaw_facing(s, qi, -sd), Vector3.ONE * 10.0)
			else:
				s.put(s.pick(boards), Vector3(q.x, s.placer.ground(q.x, q.z, 3.0) - 0.1, q.z), _yaw_facing(s, qi, -sd), Vector3.ONE * 10.0)
			s.placer.mark(q.x, q.z, 5.0)
	# 弯心摄影塔
	for i in range(0, t.n, roundi(60.0 / t.spacing)):
		if absf(t.curv[i]) < 0.02:
			continue
		var sd := signf(t.curv[i]) * -1.0
		var p := t.point_at(float(i), -sd * (t.wall_offset + 5.0))
		if s.placer.ok(p.x, p.z, 2.0, false, true):
			s.put(cam, Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.1, p.z), _yaw_facing(s, i, -sd), Vector3.ONE * 14.0)
			s.placer.mark(p.x, p.z, 2.5)


## 弯道外侧的轮胎堆（红白相间的顶圈）
static func _tire_stacks(s: Scenery) -> void:
	var t := s.track
	var k := s.kind_mesh("tires", SceneryProps.tire_stack_mesh(), {"shadow": true, "colors": true})
	var j := 0
	for i in range(0, t.n, 3):
		if absf(t.curv[i]) < 0.014:
			continue
		# 左弯（curv > 0）的外侧是右侧（+法线）
		var sd := 1.0 if t.curv[i] > 0.0 else -1.0
		for m in 2:
			var p := t.point_at(float(i), sd * (t.wall_offset + 1.3 + m * 1.15))
			if not s.placer.clear_of_track(p.x, p.z, 0.6, 0.5):
				continue
			j += 1
			s.put(k, Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.05, p.z), s.rng.randf() * TAU, Vector3.ONE, Color("#E8414B") if j % 2 == 0 else Color("#F4F4F4"))


# ———————————————— 树与草 ————————————————

static func _trees(s: Scenery) -> void:
	var P := s.placer
	var trees := [s.kind("nature/tree_default", Scenery.BIG_TINT), s.kind("nature/tree_oak", Scenery.BIG_TINT), s.kind("nature/tree_cone", Scenery.BIG_TINT),
		s.kind("nature/tree_tall", Scenery.BIG_TINT), s.kind("nature/tree_default", Scenery.BIG_TINT), s.kind("nature/tree_default_fall", Scenery.BIG_TINT)]
	var spots := P.band(s.dn(200), 14, 70, 2.6, true)
	for g in P.scatter(s.dn(20), 24, 50, 320, true, false):
		spots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 18, 24.0, 2.6, true, true))
	spots.append_array(P.scatter(s.dn(160), 2.6, 90, 420, true))
	s.scatter_kinds(trees, spots, 6.0, 9.0, true, 0.15)
	var bushes := [s.kind("nature/plant_bushDetailed", Scenery.MID_TINT), s.kind("nature/plant_bushLarge", Scenery.MID_TINT)]
	s.scatter_kinds(bushes, P.band(s.dn(120), 3, 40, 1.6), 5.0, 7.5, true, 0.1)
	var grass := s.kind_mesh("gpatch", SceneryProps.flower_patch("circuit", ["grass", "grass_large"], s.rng, 5, 1.3, 4.0), Scenery.SMALL_TINT)
	s.scatter_kinds([grass], P.band(s.dn(380), 0.5, 40, 1.2, false, false), 0.9, 1.2, true, 0.05)
