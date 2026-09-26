class_name SceneryForest
extends RefCounted
## 森林峡谷：巨型松树 / 橡树林、峭壁、原木、蘑菇、树桩；河流水面（贴合河床，不会漫出地面）、
## 河一端是峭壁瀑布（滚动水帘 + 水雾），另一端是带睡莲的水潭；公路跨河处加木桩支架。

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const FALL_SHADER := preload("res://assets/shaders/waterfall.gdshader")


static func build(s: Scenery) -> void:
	for rv in s.track.rivers:
		_river(s, rv)
	_trees(s)
	_ground_detail(s)


# ———————————————— 河流 ————————————————

static func _water_mat(flow: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("flow_dir", Vector2(flow.x, flow.z).normalized())
	return m


static func _river(s: Scenery, rv: Dictionary) -> void:
	var c: Vector3 = rv["pos"]
	var along := Vector3(float(rv["nx"]), 0, float(rv["nz"])).normalized()
	var across := Vector3(float(rv["tx"]), 0, float(rv["tz"])).normalized()
	var w: float = rv["width"]
	var wy: float = rv["water_y"]
	var ext_pos: float = rv["ext_pos"]
	var ext_neg: float = rv["ext_neg"]
	# 地势高的一端做瀑布，另一端做水潭；水流方向从瀑布流向水潭
	var hp := s.terrain.height_at(c.x + along.x * (ext_pos + 12.0), c.z + along.z * (ext_pos + 12.0))
	var hn := s.terrain.height_at(c.x - along.x * (ext_neg + 12.0), c.z - along.z * (ext_neg + 12.0))
	var sg := 1.0 if hp >= hn else -1.0
	var fall_a := sg * ((ext_pos if sg > 0.0 else ext_neg) - 8.0)
	var pool_a := -sg * ((ext_neg if sg > 0.0 else ext_pos) - 2.0)
	var flow := -along * sg
	var mat := _water_mat(flow)

	# 水面条带：每个顶点取 min(河面高度, 地面 + 0.35)，低洼处贴地成浅溪，岸边自然没入地下
	var a_lo := minf(fall_a, pool_a) - (4.0 if sg > 0.0 else 0.0)
	var a_hi := maxf(fall_a, pool_a) + (4.0 if sg < 0.0 else 0.0)
	var half := w * 0.5 + 3.0
	var cols := [-half, -half * 0.6, -half * 0.3, 0.0, half * 0.3, half * 0.6, half]
	var rows := ceili((a_hi - a_lo) / 2.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows + 1:
		var a := a_lo + (a_hi - a_lo) * r / rows
		for cc: float in cols:
			var q := c + along * a + across * cc
			var y := minf(wy, s.terrain.height_at(q.x, q.z) + 0.35)
			st.set_uv(Vector2(cc, a))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, y, q.z))
	# 三角形 (i0, i1, i2) 的两条边是 across、along；Godot 以顺时针为正面，
	# 从上往下看顺时针 ⇔ across × along 朝下，否则交换顶点顺序
	var flip := across.cross(along).y > 0.0
	var nc := cols.size()
	for r in rows:
		for k in nc - 1:
			var i0 := r * nc + k
			var i1 := i0 + 1
			var i2 := i0 + nc
			var i3 := i2 + 1
			for tri: Array in [[i0, i1, i2], [i1, i3, i2]]:
				st.add_index(tri[0])
				st.add_index(tri[2] if flip else tri[1])
				st.add_index(tri[1] if flip else tri[2])
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(mi)

	_waterfall(s, c, along, across, sg, fall_a, w, wy)
	_pool(s, c + along * pool_a, flow, wy)
	_trestle(s, rv, w)
	_canyon(s, c, along, across, sg, fall_a, w)


## 瀑布：横跨河谷尽头的一排峭壁块（中间留出水口）、竖直水帘、崖顶水面、底部水潭与水雾
static func _waterfall(s: Scenery, c: Vector3, along: Vector3, across: Vector3, sg: float, fall_a: float, w: float, wy: float) -> void:
	var W := c + along * fall_a
	var base_y := minf(wy, s.terrain.height_at(W.x, W.z) + 0.35)
	var behind := W + along * sg * 16.0
	var top_y := clampf(s.terrain.height_at(behind.x, behind.z) + 1.5, base_y + 7.0, base_y + 13.0)
	var block := s.kind("nature/cliff_block_rock", {"shadow": true, "center": true})
	var spires := [s.kind("nature/rock_tallA", Scenery.BIG), s.kind("nature/rock_tallB", Scenery.BIG), s.kind("nature/rock_tallH", Scenery.BIG), s.kind("nature/rock_tallI", Scenery.BIG)]
	var yaw := atan2(along.x * sg, along.z * sg)
	var fall_w := w * 0.75
	# 峭壁核心：水口一列略矮（水从这里漫过），两侧各两列到崖顶
	for k in range(-2, 3):
		var d := float(k) * 6.5
		var q := W + across * d + along * sg * 4.2
		if not s.placer.clear_of_track(q.x, q.z, 4.5, 6.0):
			continue
		var g := s.terrain.height_at(q.x, q.z)
		var h := top_y - g + (-0.9 if k == 0 else 0.8 + absf(float(k)) * 0.9)
		s.put(block, Vector3(q.x, g - 1.0, q.z), yaw, Vector3(6.8, h + 1.0, 8.4))
		s.placer.mark(q.x, q.z, 4.5)
	# 外侧用高耸的岩柱堆出山体轮廓，挡住方块的边角
	for k in 16:
		var side := -1.0 if k % 2 == 0 else 1.0
		var d := side * s.rf(fall_w * 0.5 + 2.5, 22.0)
		var q := W + across * d + along * sg * s.rf(-1.0, 9.0)
		if not s.placer.clear_of_track(q.x, q.z, 4.0, 6.0):
			continue
		var g := s.terrain.height_at(q.x, q.z)
		var hs := (top_y - g) * s.rf(0.9, 1.5) + 2.0
		var sc := s.rf(7.0, 11.0)
		s.put(s.pick(spires), Vector3(q.x, g - 0.8, q.z), s.rng.randf() * TAU, Vector3(sc, maxf(hs, 4.0), sc))
		s.placer.mark(q.x, q.z, 4.0)
	# 水帘
	var fall_h := top_y - 0.9 - base_y + 0.4
	var quad := QuadMesh.new()
	quad.size = Vector2(fall_w, fall_h)
	var fmat := ShaderMaterial.new()
	fmat.shader = FALL_SHADER
	fmat.set_shader_parameter("width_m", fall_w)
	fmat.set_shader_parameter("height_m", fall_h)
	var curtain := MeshInstance3D.new()
	curtain.name = "Waterfall"
	curtain.mesh = quad
	curtain.material_override = fmat
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_node(curtain, Vector3(W.x, base_y - 0.3 + fall_h * 0.5, W.z) - along * sg * 0.15, atan2(-along.x * sg, -along.z * sg))
	# 水帘略微前倾：底部离崖壁更远
	curtain.rotate_object_local(Vector3.RIGHT, -0.08)
	# 崖顶水面（向山体里延伸，被地形挡住的部分自然看不到）
	var top := MeshInstance3D.new()
	top.name = "FallTop"
	var pm := PlaneMesh.new()
	pm.size = Vector2(fall_w + 1.0, 16.0)
	top.mesh = pm
	top.material_override = _water_mat(-along * sg)
	s.add_node(top, W + along * sg * 8.0 + Vector3(0, top_y - 0.75 - W.y, 0), yaw)
	# 瀑布下的水潭
	var pool := MeshInstance3D.new()
	pool.name = "FallPool"
	pool.mesh = _disc(w * 0.5 + 6.0)
	pool.material_override = _water_mat(-along * sg)
	s.add_node(pool, Vector3(W.x, base_y + 0.02, W.z) - along * sg * 5.0)
	s.placer.mark(pool.position.x, pool.position.z, w * 0.5 + 6.0)
	# 水雾
	var mist := SceneryWeather.mist(fall_w)
	s.add_node(mist, Vector3(W.x, base_y + 0.5, W.z) - along * sg * 1.5, atan2(-along.x * sg, -along.z * sg))
	# 水口两侧的大石头
	var rocks := [s.kind("nature/rock_tallA", Scenery.BIG), s.kind("nature/rock_tallB", Scenery.BIG), s.kind("nature/rock_largeD", Scenery.BIG)]
	for k in 7:
		var d := (fall_w * 0.5 + s.rf(1.5, 7.0)) * (-1.0 if k % 2 == 0 else 1.0)
		var q := W + across * d - along * sg * s.rf(1.0, 8.0)
		s.put(s.pick(rocks), Vector3(q.x, s.terrain.height_at(q.x, q.z) - 0.4, q.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(3.5, 6.5))


## 河的另一端：一片圆形水潭 + 睡莲 + 芦苇 + 石头
static func _pool(s: Scenery, p: Vector3, flow: Vector3, wy: float) -> void:
	var y := minf(wy, s.terrain.height_at(p.x, p.z) + 0.4)
	var pool := MeshInstance3D.new()
	pool.name = "Pond"
	pool.mesh = _disc(15.0)
	pool.material_override = _water_mat(flow)
	s.add_node(pool, Vector3(p.x, y + 0.01, p.z))
	var lily := [s.kind("nature/lily_large", Scenery.SMALL), s.kind("nature/lily_small", Scenery.SMALL)]
	for k in s.dn(26):
		var a := s.rng.randf() * TAU
		var d := s.rf(3.0, 13.0)
		var q := p + Vector3(cos(a) * d, 0, sin(a) * d)
		if s.terrain.height_at(q.x, q.z) > y - 0.15:
			continue
		s.put(s.pick(lily), Vector3(q.x, y + 0.04, q.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(7, 11))
	var reed := s.kind_mesh("reeds", SceneryProps.flower_patch("forest", ["grass_large", "crops_bambooStageA", "grass"], s.rng, 6, 1.4, 6.0), Scenery.SMALL_TINT)
	var rocks := [s.kind("nature/rock_largeA", Scenery.MID), s.kind("nature/rock_largeC", Scenery.MID)]
	for k in 18:
		var a := TAU * k / 18.0 + s.rf(-0.1, 0.1)
		var q := p + Vector3(cos(a), 0, sin(a)) * s.rf(13.0, 17.0)
		if not s.placer.ok(q.x, q.z, 1.0, false, false):
			continue
		if k % 3 == 0:
			s.put(s.pick(rocks), Vector3(q.x, s.terrain.height_at(q.x, q.z) - 0.3, q.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(3, 5))
		else:
			s.put(reed, Vector3(q.x, s.terrain.height_at(q.x, q.z) - 0.1, q.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(0.9, 1.3), s.tint())
	s.placer.mark(p.x, p.z, 17.0)


static func _disc(r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		# 从上往下看顺时针
		for v: Vector3 in [Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)) * r, Vector3(cos(a1), 0, sin(a1)) * r]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	return st.commit()


## 公路跨河处的木桩支架：河两岸各一排原木立柱 + 横梁 + 斜撑，托住桥面
static func _trestle(s: Scenery, rv: Dictionary, w: float) -> void:
	var t := s.track
	var rs: float = rv["s"]
	var deck_y := t.center_y(rs) - 1.3
	var wood := SceneryLib.palette_mat("forest", "woodBark")
	var dark := SceneryLib.palette_mat("forest", "woodBarkDark")
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		var ss := rs + side * (w * 0.5 + 1.2) / t.spacing
		var tops: Array[Vector3] = []
		for lat: float in [-t.half_width * 0.8, -t.half_width * 0.27, t.half_width * 0.27, t.half_width * 0.8]:
			var p := t.point_at(ss, lat)
			var g := s.terrain.height_at(p.x, p.z) - 0.5
			var h := deck_y - g
			if h < 0.5:
				continue
			parts.append([SceneryProps.cyl(0.45, 0.5, h, 8), SceneryProps.xf(Vector3(p.x, g + h * 0.5, p.z)), wood])
			tops.append(Vector3(p.x, deck_y, p.z))
		if tops.size() < 2:
			continue
		parts.append(_beam(tops[0], tops[tops.size() - 1], 0.85, dark, 0.8))
		for j in tops.size() - 1:
			var down := Vector3(0, -3.0, 0)
			if j % 2 == 0:
				parts.append(_beam(tops[j] + Vector3(0, -0.6, 0), tops[j + 1] + down, 0.3, dark))
			else:
				parts.append(_beam(tops[j] + down, tops[j + 1] + Vector3(0, -0.6, 0), 0.3, dark))
	if parts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Trestle"
	mi.mesh = SceneryLib.merge(parts)
	s.add_child(mi)


## 两点之间的方木梁（extra 为两端各伸出的长度）
static func _beam(a: Vector3, b: Vector3, thick: float, mat: Material, extra := 0.0) -> Array:
	var dir := b - a
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	return [SceneryProps.box(Vector3(thick, thick, dir.length() + extra * 2.0)), Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5), mat]


## 河谷两岸的岩柱峭壁（离赛道足够远的河段），越靠近瀑布越高，形成峡谷
static func _canyon(s: Scenery, c: Vector3, along: Vector3, across: Vector3, sg: float, fall_a: float, w: float) -> void:
	var kinds := [s.kind("nature/rock_tallA", Scenery.BIG), s.kind("nature/rock_tallB", Scenery.BIG), s.kind("nature/rock_tallC", Scenery.BIG),
		s.kind("nature/rock_tallG", Scenery.BIG), s.kind("nature/rock_tallH", Scenery.BIG), s.kind("nature/rock_tallI", Scenery.BIG)]
	var a := fall_a - sg * 10.0
	while absf(a) > 18.0 and signf(a) == sg:
		var k := clampf(absf(a) / absf(fall_a), 0.6, 1.0)
		for side: float in [-1.0, 1.0]:
			var d := side * (w * 0.5 + s.rf(7.0, 12.0))
			var q := c + along * a + across * d
			if not s.placer.ok(q.x, q.z, 3.5, true, true):
				continue
			var g := s.terrain.height_at(q.x, q.z)
			var sc := s.rf(7.0, 10.0)
			s.put(s.pick(kinds), Vector3(q.x, g - 0.8, q.z), s.rng.randf() * TAU, Vector3(sc, s.rf(11.0, 20.0) * k, sc))
			s.placer.mark(q.x, q.z, 3.8)
		a -= sg * s.rf(5.0, 7.5)


# ———————————————— 植被 ————————————————

static func _trees(s: Scenery) -> void:
	var P := s.placer
	var pines := [
		s.kind("nature/tree_pineTallA_detailed", Scenery.BIG_TINT), s.kind("nature/tree_pineTallB_detailed", Scenery.BIG_TINT),
		s.kind("nature/tree_pineTallC_detailed", Scenery.BIG_TINT), s.kind("nature/tree_pineTallD_detailed", Scenery.BIG_TINT),
		s.kind("nature/tree_pineRoundA", Scenery.BIG_TINT), s.kind("nature/tree_pineRoundF", Scenery.BIG_TINT),
	]
	var broad := [s.kind("nature/tree_oak_dark", Scenery.BIG_TINT), s.kind("nature/tree_detailed_dark", Scenery.BIG_TINT), s.kind("nature/tree_default_dark", Scenery.BIG_TINT)]
	var spots := P.band(s.dn(420), 6, 30, 2.8, true)
	spots.append_array(P.band(s.dn(280), 30, 75, 2.8, true))
	for g in P.scatter(s.dn(22), 26, 50, 300, true, false):
		spots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 24, 28.0, 2.8, true, true))
	spots.append_array(P.scatter(s.dn(240), 2.8, 90, 420, true))
	for p in spots:
		if s.rng.randf() < 0.65:
			var sc := s.rf(7.5, 11.5)
			s.put(s.pick(pines), Vector3(p.x, p.y - 0.2, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.95, 1.3), sc), s.tint())
		else:
			var sc := s.rf(7.0, 10.0)
			s.put(s.pick(broad), Vector3(p.x, p.y - 0.2, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.2), sc), s.tint())


static func _ground_detail(s: Scenery) -> void:
	var P := s.placer
	# 大石头与山坡上的峭壁露头
	var big := [s.kind("nature/rock_largeA", Scenery.BIG), s.kind("nature/rock_largeD", Scenery.BIG), s.kind("nature/rock_tallA", Scenery.BIG), s.kind("nature/rock_tallH", Scenery.BIG)]
	s.scatter_kinds(big, P.band(s.dn(50), 2, 45, 3.0), 4.0, 8.0, false, 0.5)
	var spires := [s.kind("nature/rock_tallA", Scenery.BIG), s.kind("nature/rock_tallB", Scenery.BIG), s.kind("nature/rock_tallG", Scenery.BIG)]
	for o in P.scatter(s.dn(16), 9.0, 60, 320, true):
		for k in s.rng.randi_range(2, 4):
			var q := Vector3(o.x + s.rf(-7, 7), 0, o.z + s.rf(-7, 7))
			var g := s.terrain.height_at(q.x, q.z)
			var sc := s.rf(7, 11)
			s.put(s.pick(spires), Vector3(q.x, g - 1.0, q.z), s.rng.randf() * TAU, Vector3(sc, s.rf(8, 18), sc))
	# 原木、树桩、灌木
	var logs := [s.kind("nature/log_large", Scenery.MID), s.kind("nature/log", Scenery.MID), s.kind("nature/log_stack", Scenery.MID)]
	s.scatter_kinds(logs, P.band(s.dn(45), 1, 38, 2.5), 6.0, 8.0, false, 0.1, Vector2(1, 1))
	var stumps := [s.kind("nature/stump_old", Scenery.MID), s.kind("nature/stump_oldTall", Scenery.MID), s.kind("nature/stump_roundDetailed", Scenery.MID)]
	s.scatter_kinds(stumps, P.band(s.dn(50), 1, 38, 1.5), 6.0, 8.5, false, 0.1)
	var bushes := [s.kind("nature/plant_bushDetailed", Scenery.MID_TINT), s.kind("nature/plant_bushLarge", Scenery.MID_TINT)]
	s.scatter_kinds(bushes, P.band(s.dn(420), 0.5, 38, 1.6), 5.5, 8.5, true, 0.1)
	# 蘑菇：路边小簇 + 几朵童话般的巨型蘑菇
	var shrooms := [s.kind("nature/mushroom_redGroup", Scenery.SMALL), s.kind("nature/mushroom_tanGroup", Scenery.SMALL), s.kind("nature/mushroom_red", Scenery.SMALL)]
	s.scatter_kinds(shrooms, P.band(s.dn(160), 0.2, 30, 0.8, false, false), 6.0, 9.0, false, 0.02)
	var giant := [s.kind("nature/mushroom_redTall", Scenery.BIG), s.kind("nature/mushroom_red", Scenery.BIG), s.kind("nature/mushroom_tanTall", Scenery.BIG)]
	s.scatter_kinds(giant, P.band(s.dn(10), 3, 30, 3.0, true), 22.0, 32.0, false, 0.1)
	# 草丛 / 蕨
	var ferns := s.kind_mesh("ferns", SceneryProps.flower_patch("forest", ["grass_large", "grass_leafsLarge", "grass"], s.rng, 5, 1.2, 3.6), Scenery.SMALL_TINT)
	s.scatter_kinds([ferns], P.band(s.dn(700), 0.0, 40, 1.3, false, false), 0.9, 1.3, true, 0.05)
