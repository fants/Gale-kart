class_name SceneryMushroom
extends RefCounted
## 森林发卡（蘑菇森林）：阔叶林为主的明亮森林，路边和林间长满童话风巨型蘑菇（红伞白点 / 橙伞 / 紫伞），
## 几座蘑菇小屋；每个发卡弯外侧立黄黑箭头的急弯指示牌；地面细节沿用森林峡谷（石头、原木、树桩、灌木、蕨）。

const CAPS := ["#E8413C", "#FF8A3D", "#B066E8", "#E8413C", "#F2C94C"]


static func build(s: Scenery) -> void:
	_trees(s)
	_mushrooms(s)
	_mushroom_houses(s)
	SceneryForest._ground_detail(s)
	add_hairpin_signs(s, Color("#FFC93C"), Color("#1B1F3B"))


static func _trees(s: Scenery) -> void:
	var P := s.placer
	var broad := [
		s.kind("nature/tree_oak", Scenery.BIG_TINT), s.kind("nature/tree_default", Scenery.BIG_TINT),
		s.kind("nature/tree_detailed", Scenery.BIG_TINT), s.kind("nature/tree_fat", Scenery.BIG_TINT),
		s.kind("nature/tree_plateau", Scenery.BIG_TINT), s.kind("nature/tree_oak_dark", Scenery.BIG_TINT),
	]
	var pines := [s.kind("nature/tree_pineRoundA", Scenery.BIG_TINT), s.kind("nature/tree_pineRoundC", Scenery.BIG_TINT), s.kind("nature/tree_pineTallB_detailed", Scenery.BIG_TINT)]
	var fall := [s.kind("nature/tree_oak_fall", Scenery.BIG_TINT), s.kind("nature/tree_default_fall", Scenery.BIG_TINT)]
	var spots := P.band(s.dn(380), 6, 30, 2.8, true)
	spots.append_array(P.band(s.dn(260), 30, 75, 2.8, true))
	for g in P.scatter(s.dn(20), 26, 50, 300, true, false):
		spots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 22, 28.0, 2.8, true, true))
	spots.append_array(P.scatter(s.dn(220), 2.8, 90, 420, true))
	for p in spots:
		var roll := s.rng.randf()
		var k: String = s.pick(pines) if roll < 0.18 else (s.pick(fall) if roll < 0.26 else s.pick(broad))
		var sc := s.rf(7.0, 10.5)
		s.put(k, Vector3(p.x, p.y - 0.2, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.95, 1.25), sc), s.tint(Color(1.0, 1.04, 0.92), 0.14))


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
