class_name SceneryMushroom
extends RefCounted
## 森林发卡（蘑菇森林）：阔叶林为主的明亮森林，路边和林间长满童话风巨型蘑菇（红伞白点 / 橙伞 / 紫伞），
## 几座蘑菇小屋；急弯外侧的木栏杆上挂一排黄底黑箭头的导向板；路边草丛与野花；地面细节沿用森林峡谷（石头、原木、树桩、灌木、蕨）。

const CAPS := ["#E8413C", "#FF8A3D", "#B066E8", "#E8413C", "#F2C94C"]


static func build(s: Scenery) -> void:
	for step in steps(s):
		step.call()


static func steps(s: Scenery) -> Array[Callable]:
	var out: Array[Callable] = _tree_steps(s)
	out.append_array([
		func() -> void: _mushrooms(s),
		func() -> void: _mushroom_houses(s),
	])
	out.append_array(SceneryForest.ground_detail_steps(s))
	out.append_array([
		func() -> void: _verges(s),
		func() -> void: _cliff_edge(s),
		func() -> void: add_fence_chevrons(s, Color("#FFC21A"), Color("#1A1A1A")),
	])
	return out


static func _trees(s: Scenery) -> void:
	for step in _tree_steps(s):
		step.call()


## 树林拆成几步：先分批找位置，最后统一摆放（随机数顺序与一次做完相同）
static func _tree_steps(s: Scenery) -> Array[Callable]:
	var P := s.placer
	var spots: Array[Vector4] = []
	return [
		func() -> void:
			spots.append_array(P.band(s.dn(380), 6, 30, 2.8, true))
			spots.append_array(P.band(s.dn(260), 30, 75, 2.8, true)),
		func() -> void:
			for g in P.scatter(s.dn(20), 26, 50, 300, true, false):
				spots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 22, 28.0, 2.8, true, true)),
		func() -> void:
			spots.append_array(P.scatter(s.dn(220), 2.8, 90, 420, true)),
		func() -> void:
			var broad := [
				s.kind("nature/tree_oak", Scenery.BIG_TINT), s.kind("nature/tree_default", Scenery.BIG_TINT),
				s.kind("nature/tree_detailed", Scenery.BIG_TINT), s.kind("nature/tree_fat", Scenery.BIG_TINT),
				s.kind("nature/tree_plateau", Scenery.BIG_TINT), s.kind("nature/tree_oak_dark", Scenery.BIG_TINT),
			]
			var pines := [s.kind("nature/tree_pineRoundA", Scenery.BIG_TINT), s.kind("nature/tree_pineRoundC", Scenery.BIG_TINT), s.kind("nature/tree_pineTallB_detailed", Scenery.BIG_TINT)]
			var fall := [s.kind("nature/tree_oak_fall", Scenery.BIG_TINT), s.kind("nature/tree_default_fall", Scenery.BIG_TINT)]
			for p in spots:
				var roll := s.rng.randf()
				var k: String = s.pick(pines) if roll < 0.18 else (s.pick(fall) if roll < 0.26 else s.pick(broad))
				var sc := s.rf(7.0, 10.5)
				s.put(k, Vector3(p.x, p.y - 0.2, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.95, 1.25), sc), s.tint(Color(1.0, 1.04, 0.92), 0.14)),
	]


## 单位蘑菇（高约 1.4）：菌柄 + 半球菌伞 + 白点
static func mushroom_mesh(cap_color: Color, dots: bool, rng: RandomNumberGenerator) -> ArrayMesh:
	var stem := SceneryLib.flat_mat(Color("#F4EAD2"), 0.0, 0.8)
	var gill := SceneryLib.flat_mat(Color("#E3D2B0"), 0.0, 0.9)
	var cap := SceneryLib.flat_mat(cap_color, 0.0, 0.55)
	var dot := SceneryLib.flat_mat(Color("#FFFBF2"), 0.0, 0.6)
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.95
	cap_mesh.height = 0.95
	cap_mesh.is_hemisphere = true
	cap_mesh.radial_segments = 18
	cap_mesh.rings = 6
	var parts: Array = [
		[SceneryProps.cyl(0.32, 0.42, 1.0, 12), SceneryProps.xf(Vector3(0, 0.5, 0)), stem],
		[SceneryProps.cyl(0.9, 0.9, 0.08, 18), SceneryProps.xf(Vector3(0, 0.96, 0)), gill],
		[cap_mesh, SceneryProps.xf(Vector3(0, 0.98, 0), Vector3.ZERO, Vector3(1.0, 0.62, 1.0)), cap],
	]
	if dots:
		for i in 9:
			var a := rng.randf() * TAU
			var el := rng.randf_range(0.25, 1.1)
			var dir := Vector3(cos(a) * cos(el), sin(el) * 0.62, sin(a) * cos(el)).normalized()
			var pos := Vector3(0, 0.98, 0) + Vector3(dir.x * 0.95, dir.y * 0.95, dir.z * 0.95)
			parts.append([SceneryProps.sphere(rng.randf_range(0.08, 0.14), 8, 5), SceneryProps.xf(pos, Vector3.ZERO, Vector3(1, 0.45, 1)), dot])
	return SceneryLib.merge(parts)


static func _mushrooms(s: Scenery) -> void:
	var P := s.placer
	var kinds: Array = []
	for i in CAPS.size():
		kinds.append(s.kind_mesh("shroom%d" % i, mushroom_mesh(Color(CAPS[i]), i != 1, s.rng), Scenery.BIG))
	# 路边一圈中型蘑菇（追尾镜头里最显眼）
	for p in P.band(s.dn(70), 1.5, 22, 3.0, true):
		var sc := s.rf(3.5, 7.0)
		s.put(s.pick(kinds), Vector3(p.x, p.y - 0.1, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.3), sc))
	# 林间成簇的巨型蘑菇
	for g in P.scatter(s.dn(18), 10, 30, 260, true, false):
		for q in P.cluster(Vector3(g.x, g.y, g.z), s.rng.randi_range(2, 5), 16.0, 5.0, true, true):
			var sc := s.rf(8.0, 16.0)
			s.put(s.pick(kinds), Vector3(q.x, q.y - 0.2, q.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.35), sc))


## 蘑菇小屋：粗菌柄当房子，开门开窗，红伞白点当屋顶
static func _house_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var wall := SceneryLib.flat_mat(Color("#F6E7C8"), 0.0, 0.85)
	var cap := SceneryLib.flat_mat(Color("#E8413C"), 0.0, 0.55)
	var dot := SceneryLib.flat_mat(Color("#FFFBF2"))
	var wood := SceneryLib.flat_mat(Color("#8E5F39"))
	var glass := SceneryLib.flat_mat(Color("#FFD27A"), 0.6, 0.3)
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 1.0
	cap_mesh.height = 1.0
	cap_mesh.is_hemisphere = true
	cap_mesh.radial_segments = 20
	cap_mesh.rings = 7
	var parts: Array = [
		[SceneryProps.cyl(2.2, 2.6, 4.2, 16), SceneryProps.xf(Vector3(0, 2.1, 0)), wall],
		[cap_mesh, SceneryProps.xf(Vector3(0, 4.0, 0), Vector3.ZERO, Vector3(4.3, 2.8, 4.3)), cap],
		[SceneryProps.box(Vector3(1.2, 2.0, 0.3)), SceneryProps.xf(Vector3(0, 1.0, 2.45)), wood],
		[SceneryProps.box(Vector3(0.8, 0.8, 0.2)), SceneryProps.xf(Vector3(1.3, 2.6, 2.05), Vector3(0, 0.55, 0)), glass],
		[SceneryProps.box(Vector3(0.8, 0.8, 0.2)), SceneryProps.xf(Vector3(-1.3, 2.6, 2.05), Vector3(0, -0.55, 0)), glass],
	]
	for i in 12:
		var a := rng.randf() * TAU
		var el := rng.randf_range(0.2, 1.2)
		var d := Vector3(cos(a) * cos(el) * 4.3, sin(el) * 2.8, sin(a) * cos(el) * 4.3)
		parts.append([SceneryProps.sphere(rng.randf_range(0.35, 0.55), 8, 5), SceneryProps.xf(Vector3(0, 4.0, 0) + d, Vector3.ZERO, Vector3(1, 0.45, 1)), dot])
	return SceneryLib.merge(parts)


static func _mushroom_houses(s: Scenery) -> void:
	var P := s.placer
	var k := s.kind_mesh("shroomhouse", _house_mesh(s.rng), Scenery.BIG)
	for p in P.band(s.dn(7), 8, 36, 6.0, true):
		s.put(k, Vector3(p.x, p.y - 0.2, p.z), P.facing(p.x, p.z), Vector3.ONE * s.rf(0.9, 1.2))


## 急弯指示牌：半径 < 45 m 的弯道外侧，每 ~11 m 一块，箭头指向转弯方向，面朝来车
static func add_hairpin_signs(s: Scenery, arrow: Color, board: Color) -> void:
	var t := s.track
	var board_mat := SceneryLib.flat_mat(board, 0.0, 0.7)
	var arrow_mat := SceneryLib.flat_mat(arrow, 0.35, 0.5)
	var post_mat := SceneryLib.flat_mat(Color("#5A5F7A"), 0.0, 0.6)
	var parts: Array = []
	var step := maxi(1, roundi(11.0 / t.spacing))
	var i := 0
	var count := 0
	while i < t.n:
		var c := t.curv[i]
		if 1.0 / maxf(absf(c), 1e-6) < 45.0:
			# 外侧：左转（曲率为正）时在右侧
			var side := 1.0 if c > 0.0 else -1.0
			var p := t.point_at(float(i), side * (t.wall_offset + 1.3))
			var fwd := Vector3(t.tx[i], 0, t.tz[i]).normalized()
			# 牌面 +Z 朝向来车（-前进方向）；牌面 +X 即车手的右手边
			var basis := Basis.looking_at(fwd, Vector3.UP)
			var base := Vector3(p.x, t.py[i], p.z)
			for px: float in [-1.2, 1.2]:
				parts.append([SceneryProps.box(Vector3(0.14, 1.4, 0.14)), Transform3D(basis, base + basis * Vector3(px, 0.7, -0.05)), post_mat])
			parts.append([SceneryProps.box(Vector3(3.2, 1.3, 0.14)), Transform3D(basis, base + basis * Vector3(0, 1.95, 0)), board_mat])
			# 三个箭头「<」或「>」：左转指向车手左边（-X）
			var dir := -1.0 if c > 0.0 else 1.0
			for k in 3:
				var cx := (k - 1) * 0.95
				# 箭尖在 cx + dir*0.22，两臂各向开口方向斜 45°
				for arm: float in [-1.0, 1.0]:
					var ang := -arm * 0.78 * dir
					var arm_center := Vector3(cx, 1.95 + arm * 0.22, 0.09)
					parts.append([SceneryProps.box(Vector3(0.62, 0.16, 0.06)), Transform3D(basis * Basis(Vector3.BACK, ang), base + basis * arm_center), arrow_mat])
			count += 1
			i += step
		else:
			i += 1
	if parts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "HairpinSigns"
	mi.mesh = SceneryLib.merge(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	s.add_child(mi)
	s.stats["hairpin_signs"] = count


## 路边草带：路面与栏杆之间的草丛和野花，栏杆外侧一圈花丛
static func _verges(s: Scenery) -> void:
	var t := s.track
	var tufts := s.kind_mesh("verge_grass", SceneryProps.flower_patch("forest", ["grass_large", "grass", "grass_leafsLarge"], s.rng, 6, 0.9, 2.4), Scenery.SMALL_TINT)
	var flowers: Array = []
	for i in 3:
		flowers.append(s.kind_mesh("verge_flowers%d" % i, SceneryProps.flower_patch("forest", [["flower_yellowA", "flower_yellowB", "grass"], ["flower_redA", "flower_redB", "grass_large"], ["flower_purpleA", "flower_purpleC", "grass"]][i], s.rng, 7, 1.0, 3.0), Scenery.SMALL))
	var roads: Array[TrackData] = [t]
	roads.append_array(t.branches)
	for rd in roads:
		for k in s.dn(rd.n * 2):
			var si := s.rng.randf() * (rd.n - 1)
			var side := -1.0 if s.rng.randf() < 0.5 else 1.0
			if rd.edge_at(int(si), side) != TrackData.EDGE_WALL:
				continue
			var p := rd.point_at(si, side * s.rf(rd.hw_at(si) + 1.1, maxf(rd.hw_at(si) + 1.2, rd.wo_at(si) - 0.4)))
			var flower := s.rng.randf() < 0.3
			var sc := s.rf(0.6, 1.0)
			s.put(s.pick(flowers) if flower else tufts, Vector3(p.x, rd.center_y(si) - 0.02, p.z), s.rng.randf() * TAU, Vector3(sc, sc, sc), Color(1, 1, 1) if flower else s.tint())
	# 栏杆外侧
	for p in s.placer.band(s.dn(260), 0.2, 6, 1.0, false, false):
		var sc := s.rf(0.9, 1.4)
		s.put(s.pick(flowers), Vector3(p.x, p.y - 0.05, p.z), s.rng.randf() * TAU, Vector3(sc, sc, sc))


## 悬崖边：崖边土沿上稀疏的黄黑警示桩和碎石，崖壁上嵌几块大石头，谷底散落落石
static func _cliff_edge(s: Scenery) -> void:
	var t := s.track
	var post := SceneryLib.merge([
		[SceneryProps.box(Vector3(0.22, 1.0, 0.22)), SceneryProps.xf(Vector3(0, 0.5, 0)), SceneryLib.flat_mat(Color("#1A1A1A"))],
		[SceneryProps.box(Vector3(0.24, 0.22, 0.24)), SceneryProps.xf(Vector3(0, 0.78, 0)), SceneryLib.flat_mat(Color("#FFC21A"), 0.2, 0.5)],
		[SceneryProps.box(Vector3(0.24, 0.22, 0.24)), SceneryProps.xf(Vector3(0, 0.36, 0)), SceneryLib.flat_mat(Color("#FFC21A"), 0.2, 0.5)],
	])
	var post_k := s.kind_mesh("cliff_post", post, Scenery.SMALL)
	var small := [s.kind("nature/rock_smallA", Scenery.SMALL), s.kind("nature/rock_smallC", Scenery.SMALL), s.kind("nature/rock_smallFlatA", Scenery.SMALL), s.kind("nature/rock_smallG", Scenery.SMALL)]
	var big := [s.kind("nature/rock_largeA", Scenery.MID), s.kind("nature/rock_largeC", Scenery.MID), s.kind("nature/rock_tallB", Scenery.MID)]
	var step := maxi(1, roundi(8.0 / t.spacing))
	var i := 0
	while i < t.n:
		for side: float in [-1.0, 1.0]:
			if t.edge_at(i, side) != TrackData.EDGE_CLIFF:
				continue
			var lip := t.hw[i] + TrackData.CLIFF_LIP
			var p := t.point_at(float(i) + s.rf(-0.5, 0.5), side * (lip - 0.25))
			s.put(post_k, Vector3(p.x, t.py[i] - 0.05, p.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(0.9, 1.1))
			for k in 2:
				var q := t.point_at(float(i) + s.rf(0.0, float(step)), side * (lip - s.rf(0.1, 0.9)))
				var sc := s.rf(1.2, 2.2)
				s.put(s.pick(small), Vector3(q.x, t.py[i] - 0.1, q.z), s.rng.randf() * TAU, Vector3(sc, sc * 0.7, sc))
			# 崖壁上半嵌的大石头
			if s.rng.randf() < 0.6:
				var r := t.point_at(float(i), side * (lip + s.rf(1.2, 3.0)))
				var g := s.terrain.height_at(r.x, r.z)
				var sc2 := s.rf(3.0, 5.5)
				s.put(s.pick(big), Vector3(r.x, g - 0.5, r.z), s.rng.randf() * TAU, Vector3(sc2, sc2 * s.rf(0.8, 1.4), sc2))
		i += step


## 栏杆导向板：半径 < 50 m 的弯道外侧，护墙内面每个采样挂一块黄底黑箭头板，箭头指向行进方向
static func add_fence_chevrons(s: Scenery, board: Color, arrow: Color) -> void:
	var t := s.track
	var board_mat := SceneryLib.flat_mat(board, 0.1, 0.6)
	var arrow_mat := SceneryLib.flat_mat(arrow, 0.0, 0.7)
	var parts: Array = []
	var count := 0
	var k0 := maxi(1, roundi(6.0 / t.spacing))
	for i in t.n:
		# 前后各 6 m 内最急的曲率：弯道前后多挂几块
		var c := 0.0
		for k in range(-k0, k0 + 1):
			var ck := t.curv[posmod(i + k, t.n)]
			if absf(ck) > absf(c):
				c = ck
		if 1.0 / maxf(absf(c), 1e-6) > 50.0:
			continue
		var side := 1.0 if c > 0.0 else -1.0
		if t.edge_at(i, side) != TrackData.EDGE_WALL:
			continue
		var p := t.point_at(float(i), side * (t.wo[i] - 0.06))
		var fwd := Vector3(t.tx[i], 0, t.tz[i]).normalized()
		var inward := Vector3(t.nx[i], 0, t.nz[i]).normalized() * -side
		var xa := Vector3.UP.cross(inward)
		var basis := Basis(xa, Vector3.UP, inward)
		var dir := signf(xa.dot(fwd))
		var base := Vector3(p.x, t.py[i], p.z)
		parts.append([SceneryProps.box(Vector3(1.55, 0.95, 0.06)), Transform3D(basis, base + basis * Vector3(0, 0.62, 0)), board_mat])
		for arm: float in [-1.0, 1.0]:
			var ang := -arm * 0.85 * dir
			parts.append([SceneryProps.box(Vector3(0.62, 0.2, 0.04)), Transform3D(basis * Basis(Vector3.BACK, ang), base + basis * Vector3(0.0, 0.62 + arm * 0.19, 0.045)), arrow_mat])
		count += 1
	if parts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "FenceChevrons"
	mi.mesh = SceneryLib.merge(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	s.add_child(mi)
	s.stats["fence_chevrons"] = count
