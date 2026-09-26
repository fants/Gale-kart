class_name SceneryRural
extends RefCounted
## 阳光小镇 / 黄金沙漠 / 冰雪乐园 的物件摆放。


# ———————————————— 阳光小镇 ————————————————

static func build_village(s: Scenery) -> void:
	var P := s.placer
	var trees := [
		s.kind("nature/tree_default", Scenery.BIG_TINT), s.kind("nature/tree_oak", Scenery.BIG_TINT),
		s.kind("nature/tree_detailed", Scenery.BIG_TINT), s.kind("nature/tree_fat", Scenery.BIG_TINT),
		s.kind("nature/tree_plateau", Scenery.BIG_TINT), s.kind("nature/tree_cone", Scenery.BIG_TINT),
		s.kind("nature/tree_tall", Scenery.BIG_TINT),
	]
	var fall := [s.kind("nature/tree_default_fall", Scenery.BIG_TINT), s.kind("nature/tree_oak_fall", Scenery.BIG_TINT)]

	# 看台（起点附近）与风车（一座在开场航拍的画面里）
	_small_stand(s)
	_windmills(s, 3)

	# 红顶小屋村落：每处 2~3 栋，门口朝赛道，附近有围栏和干草垛
	# 三种屋顶颜色各一种网格（颜色烘焙进顶点色，不用实例色，免得墙也被染色）
	var houses: Array = []
	for rc: String in ["#E8414B", "#FF6A3D", "#3E8BFF"]:
		houses.append(s.kind_mesh("house" + rc, SceneryProps.house_mesh("village", Color("#FFF3DC"), Color(rc)), Scenery.BIG))
	var hay := s.kind_mesh("hay", SceneryProps.hay_mesh(), Scenery.MID_TINT)
	var fence := s.kind("nature/fence_simple", {"shadow": true, "center": true})
	for c in P.band(s.dn(6), 14, 46, 16.0, true, false):
		var center := Vector3(c.x, c.y, c.z)
		for h in P.cluster(center, s.rng.randi_range(2, 3), 15.0, 5.5, true, true):
			var house: String = houses[0] if s.rng.randf() < 0.55 else (houses[1] if s.rng.randf() < 0.75 else houses[2])
			s.put(house, Vector3(h.x, h.y - 0.3, h.z), P.facing(h.x, h.z) + s.rf(-0.35, 0.35), Vector3.ONE * s.rf(0.9, 1.15))
		_fence_line(s, fence, center, 7)
		for b in P.cluster(center + Vector3(s.rf(-10, 10), 0, s.rf(-10, 10)), 4, 9.0, 1.5, false, true):
			s.put(hay, Vector3(b.x, b.y - 0.1, b.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(0.85, 1.1), s.tint(Color("#F2C94C"), 0.15))
	for b in P.band(s.dn(24), 4, 40, 1.6):
		s.put(hay, Vector3(b.x, b.y - 0.1, b.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(0.85, 1.1), s.tint(Color("#F2C94C"), 0.15))

	# 花田：几块成行的郁金香田，每行一种颜色
	for f in P.band(s.dn(4), 7, 30, 13.0, false, true):
		_flower_field(s, f)

	# 树：路边一圈 + 成片树林 + 远处零散
	var tree_spots := P.band(s.dn(260), 6, 30, 2.6, true)
	tree_spots.append_array(P.band(s.dn(160), 30, 70, 2.6, true))
	for g in P.scatter(s.dn(14), 26, 60, 280, true, false):
		tree_spots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 20, 26.0, 2.6, true, true))
	tree_spots.append_array(P.scatter(s.dn(160), 2.6, 90, 420, true))
	for p in tree_spots:
		var k: String = s.pick(fall) if s.rng.randf() < 0.1 else s.pick(trees)
		var sc := s.rf(6.0, 9.0)
		s.put(k, Vector3(p.x, p.y - 0.15, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.2), sc), s.tint())

	# 灌木、花丛、草丛、石头
	var bushes := [s.kind("nature/plant_bushDetailed", Scenery.MID_TINT), s.kind("nature/plant_bushLarge", Scenery.MID_TINT), s.kind("nature/plant_bush", Scenery.MID_TINT)]
	s.scatter_kinds(bushes, P.band(s.dn(380), 0.5, 36, 1.6), 5.0, 8.0, true, 0.1)
	var patches: Array = []
	var sets := [["flower_redA", "flower_redB", "flower_yellowA"], ["flower_yellowA", "flower_yellowB", "flower_purpleA"], ["flower_purpleA", "flower_purpleB", "flower_redA", "flower_yellowC"]]
	for i in sets.size():
		patches.append(s.kind_mesh("fpatch%d" % i, SceneryProps.flower_patch("village", sets[i], s.rng, 8, 1.7, 5.5), Scenery.SMALL))
	s.scatter_kinds(patches, P.band(s.dn(260), 0.3, 30, 1.8, false, false), 0.9, 1.1, false, 0.05, Vector2(1, 1))
	var grass := s.kind_mesh("gpatch", SceneryProps.flower_patch("village", ["grass", "grass_large", "grass_leafsLarge"], s.rng, 5, 1.3, 4.0), Scenery.SMALL_TINT)
	s.scatter_kinds([grass], P.band(s.dn(700), 0.0, 38, 1.2, false, false), 0.9, 1.2, true, 0.05)
	var rocks := [s.kind("nature/rock_largeB", Scenery.MID), s.kind("nature/rock_largeD", Scenery.MID), s.kind("nature/rock_tallE", Scenery.MID)]
	s.scatter_kinds(rocks, P.band(s.dn(80), 1, 40, 2.0), 3.0, 5.5, false, 0.3)

	# 热气球
	var palettes: Array = [[Color("#FF5A5F"), Color("#FFD23F")], [Color("#3EC6FF"), Color("#FFFFFF")], [Color("#A06BFF"), Color("#FF8AD8")]]
	var b := s.track.bounds
	var mid := Vector3((b["min_x"] + b["max_x"]) * 0.5, 0, (b["min_z"] + b["max_z"]) * 0.5)
	for i in 3:
		var a := s.rng.randf() * TAU
		var cols: Array[Color] = []
		cols.assign(palettes[i])
		var bl := SceneryProps.balloon(cols)
		var pos := mid + Vector3(cos(a), 0, sin(a)) * s.rf(150, 260)
		s.add_node(bl, Vector3(pos.x, s.terrain.height_at(pos.x, pos.z) + s.rf(45, 75), pos.z), s.rng.randf() * TAU)
		s.add_bobber(bl)


## 风车：第一座放在起点附近（开场航拍能看见），其余沿赛道
static func _windmills(s: Scenery, count: int) -> void:
	var P := s.placer
	var spots: Array[Vector4] = []
	for t in 60:
		var ds := s.rf(-30.0, 60.0) / s.track.spacing
		var sd := -1.0 if s.rng.randf() < 0.5 else 1.0
		var p := s.track.point_at(ds, sd * s.rf(52.0, 78.0))
		if P.clear_of_track(p.x, p.z, 7.0, 8.0) and P.is_free(p.x, p.z, 7.0):
			P.mark(p.x, p.z, 7.0)
			spots.append(Vector4(p.x, P.ground(p.x, p.z, 3.0), p.z, 0))
			break
	spots.append_array(P.band(count - spots.size(), 14, 60, 7.0, true))
	for p in spots:
		var w := SceneryProps.windmill(Color("#E8414B"))
		s.add_node(w, Vector3(p.x, p.y - 0.2, p.z), P.facing(p.x, p.z) + s.rf(-0.4, 0.4))
		s.add_spinner(w.get_meta("hub"), s.rf(0.7, 1.1))


## 起点旁的小看台（Kenney grandStand 三联）
static func _small_stand(s: Scenery) -> void:
	var k := s.kind("racing/grandStand", Scenery.BIG)
	var sc := 6.5
	for sd: float in [1.0, -1.0]:
		var lat := sd * (s.track.wall_offset + 2.5 + sc * 0.5)
		var ok := true
		var pts: Array[Vector3] = []
		for ds: float in [-50.0, -43.5, -37.0]:
			var p := s.track.point_at(ds / s.track.spacing, lat)
			if not s.placer.clear_of_track(p.x, p.z, sc * 0.5 - 0.5, 1.0):
				ok = false
			pts.append(p)
		if not ok:
			continue
		for p in pts:
			var y := s.placer.ground(p.x, p.z, 3.0)
			var i := int(s.track.wrap_s(-43.5 / s.track.spacing))
			var yaw := atan2(-s.track.nx[i] * sd, -s.track.nz[i] * sd)
			s.put(k, Vector3(p.x, y - 0.1, p.z), yaw, Vector3.ONE * sc)
			s.placer.mark(p.x, p.z, sc * 0.75)
		return


## 围栏：村落和赛道之间一段沿赛道方向的木栅栏
static func _fence_line(s: Scenery, k: String, center: Vector3, segs: int) -> void:
	var i := s.placer.nearest_idx(center.x, center.z)
	var to_track := Vector3(s.track.px[i] - center.x, 0, s.track.pz[i] - center.z).normalized()
	var tan := Vector3(s.track.tx[i], 0, s.track.tz[i])
	var base := center + to_track * 11.0
	var yaw := atan2(-tan.z, tan.x)
	var seg := 3.0
	for j in segs:
		var p := base + tan * (float(j) - segs * 0.5 + 0.5) * seg
		if not s.placer.ok(p.x, p.z, 1.6, false, false):
			continue
		s.put(k, Vector3(p.x, s.terrain.height_at(p.x, p.z) - 0.05, p.z), yaw, Vector3(seg, 3.0, 3.0))


## 花田：沿赛道方向的矩形，6 行，每行一种颜色（整块合并成一个网格）
static func _flower_field(s: Scenery, f: Vector4) -> void:
	var i := int(s.track.wrap_s(f.w))
	var tan := Vector3(s.track.tx[i], 0, s.track.tz[i])
	var side := Vector3(-tan.z, 0, tan.x)
	var rows := ["flower_redA", "flower_yellowA", "flower_purpleA", "flower_redB", "flower_yellowB", "flower_redA"]
	var parts: Array = []
	var origin := Vector3(f.x, f.y, f.z)
	for row in rows.size():
		var mesh: Mesh = SceneryLib.model(s.theme_id, SceneryLib.NATURE + rows[row] + ".glb")["mesh"]
		for col in 16:
			var p := Vector3(f.x, 0, f.z) + tan * (col - 7.5) * 1.05 + side * (row - 2.5) * 1.7
			p += Vector3(s.rf(-0.2, 0.2), 0, s.rf(-0.2, 0.2))
			if not s.placer.ok(p.x, p.z, 0.5, false, false):
				continue
			p.y = s.terrain.height_at(p.x, p.z) - 0.05
			var sc := s.rf(5.0, 6.5)
			parts.append([mesh, SceneryProps.xf(p - origin, Vector3(0, s.rng.randf() * TAU, 0), Vector3(sc, sc, sc)), null])
	if parts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "FlowerField"
	mi.mesh = SceneryLib.merge(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 320.0
	s.add_node(mi, origin)


# ———————————————— 黄金沙漠 ————————————————

static func build_desert(s: Scenery) -> void:
	var P := s.placer
	_pyramids(s)

	# 方尖碑：成对立在路边
	var obelisk := s.kind("nature/statue_obelisk", Scenery.BIG)
	for o in P.band(s.dn(8), 5, 26, 2.5, true):
		var i := int(s.track.wrap_s(o.w))
		var tan := Vector3(s.track.tx[i], 0, s.track.tz[i])
		for d: float in [-5.0, 5.0]:
			var q := Vector3(o.x, 0, o.z) + tan * d
			if P.ok(q.x, q.z, 1.5, true, false):
				s.put(obelisk, Vector3(q.x, P.ground(q.x, q.z, 1.5) - 0.2, q.z), P.facing(q.x, q.z), Vector3(14, 15, 14))

	# 石柱遗迹
	var cols := [s.kind("nature/statue_column", Scenery.BIG), s.kind("nature/statue_columnDamaged", Scenery.BIG)]
	var block := s.kind("nature/statue_block", Scenery.MID)
	for r in P.band(s.dn(6), 8, 45, 8.0, true, true):
		var n := s.rng.randi_range(3, 6)
		for j in n:
			var a := TAU * j / n
			var q := Vector3(r.x + cos(a) * 6.0, 0, r.z + sin(a) * 6.0)
			if P.ok(q.x, q.z, 1.5, true, false):
				s.put(s.pick(cols), Vector3(q.x, P.ground(q.x, q.z, 1.5) - 0.2, q.z), s.rng.randf() * TAU, Vector3(9, s.rf(8, 11), 9))
		for j in 2:
			var q := Vector3(r.x + s.rf(-6, 6), 0, r.z + s.rf(-6, 6))
			if P.ok(q.x, q.z, 1.5, false, false):
				s.put(block, Vector3(q.x, P.ground(q.x, q.z) - 0.3, q.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(5, 7))

	# 仙人掌
	var cactus := [s.kind("nature/cactus_tall", Scenery.BIG_TINT), s.kind("nature/cactus_short", Scenery.BIG_TINT)]
	var cs := P.band(s.dn(150), 2, 32, 1.4)
	cs.append_array(P.scatter(s.dn(110), 1.4, 45, 320))
	s.scatter_kinds(cactus, cs, 5.0, 7.5, true, 0.1)

	# 绿洲：水塘 + 一圈棕榈 + 灌木
	var palms := [s.kind("nature/tree_palmTall", Scenery.BIG_TINT), s.kind("nature/tree_palm", Scenery.BIG_TINT), s.kind("nature/tree_palmBend", Scenery.BIG_TINT), s.kind("nature/tree_palmDetailedTall", Scenery.BIG_TINT)]
	var bush := s.kind("nature/plant_bushLarge", Scenery.MID_TINT)
	var pond := s.kind_mesh("pond", _pond_mesh(), {})
	var oases := 0
	for o in P.scatter(s.dn(12), 17.0, 40, 240, false, false):
		if oases >= s.dn(5) + 1:
			break
		if _roughness(s, o, 10.0) > 1.2:
			continue
		oases += 1
		P.mark(o.x, o.z, 17.0)
		var r := s.rf(6.5, 8.5)
		var y := _avg_height(s, o, r) + 0.08
		s.put(pond, Vector3(o.x, y, o.z), 0.0, Vector3(r, 1, r))
		var n := s.rng.randi_range(5, 7)
		for j in n:
			var a := TAU * j / n + s.rf(-0.3, 0.3)
			var q := Vector3(o.x + cos(a) * (r + s.rf(2.5, 5.0)), 0, o.z + sin(a) * (r + s.rf(2.5, 5.0)))
			if P.ok(q.x, q.z, 2.0, true, false):
				var sc := s.rf(6.0, 8.0)
				s.put(s.pick(palms), Vector3(q.x, s.terrain.height_at(q.x, q.z) - 0.15, q.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.2), sc), s.tint())
			var qb := Vector3(o.x + cos(a + 0.4) * (r + 1.5), 0, o.z + sin(a + 0.4) * (r + 1.5))
			s.put(bush, Vector3(qb.x, s.terrain.height_at(qb.x, qb.z) - 0.1, qb.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(5, 7), s.tint(Color(0.9, 1.0, 0.8)))
	s.scatter_kinds(palms, P.band(s.dn(40), 6, 36, 2.5, true), 6.0, 8.0, true, 0.15)

	# 岩石与远处台地
	var rocks := [s.kind("nature/stone_tallA", Scenery.MID), s.kind("nature/stone_tallC", Scenery.MID), s.kind("nature/stone_tallG", Scenery.MID),
		s.kind("nature/stone_largeB", Scenery.MID), s.kind("nature/stone_largeD", Scenery.MID)]
	var rs := P.band(s.dn(70), 2, 40, 2.5)
	rs.append_array(P.scatter(s.dn(60), 3, 45, 320))
	s.scatter_kinds(rocks, rs, 4.0, 8.0, false, 0.4)
	var big_mesa := [s.kind_mesh("mesaA", model_mesh(s, "nature/stone_tallA"), Scenery.BIG), s.kind_mesh("mesaB", model_mesh(s, "nature/stone_tallJ"), Scenery.BIG)]
	for m in P.scatter(s.dn(9), 26, 150, 440, true):
		var sc := s.rf(26, 40)
		s.put(s.pick(big_mesa), Vector3(m.x, m.y - 3.0, m.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.7, 1.1), sc))

	# 驼色帐篷营地
	var tents := [s.kind("nature/tent_detailedOpen", Scenery.BIG), s.kind("nature/tent_detailedClosed", Scenery.BIG), s.kind("nature/tent_smallOpen", Scenery.BIG)]
	var fire := s.kind("nature/campfire_stones", Scenery.SMALL)
	var logs := s.kind("nature/campfire_logs", Scenery.SMALL)
	for c in P.band(s.dn(4), 10, 40, 12.0, true, false):
		for t in P.cluster(Vector3(c.x, c.y, c.z), 3, 10.0, 3.5, true, true):
			s.put(s.pick(tents), Vector3(t.x, t.y - 0.1, t.z), P.facing(c.x, c.z) + s.rf(-0.8, 0.8), Vector3.ONE * s.rf(7, 8.5))
		s.put(fire, Vector3(c.x, c.y - 0.05, c.z), s.rng.randf() * TAU, Vector3.ONE * 5.0)
		s.put(logs, Vector3(c.x, c.y, c.z), s.rng.randf() * TAU, Vector3.ONE * 5.0)

	# 枯草、小灌木
	var dry := [s.kind("nature/plant_bushSmall", Scenery.SMALL_TINT), s.kind("nature/grass_leafsLarge", Scenery.SMALL_TINT)]
	for p in P.band(s.dn(160), 0, 36, 1.0, false, false):
		s.put(s.pick(dry), Vector3(p.x, p.y - 0.05, p.z), s.rng.randf() * TAU, Vector3.ONE * s.rf(4, 6), s.tint(Color(0.95, 0.85, 0.55), 0.2))


## 远处 2~3 座大金字塔：在离赛道足够远、地面较平的地方
static func _pyramids(s: Scenery) -> void:
	var pk := s.kind_mesh("pyramid", SceneryProps.pyramid_mesh(), Scenery.BIG)
	var sizes := [62.0, 46.0, 36.0]
	var placed: Array[Vector3] = []
	var b := s.track.bounds
	for r: float in sizes:
		var best := Vector4.ZERO
		var best_score := INF
		for t in 260:
			var x := s.rf(b["min_x"] - 200.0, b["max_x"] + 200.0)
			var z := s.rf(b["min_z"] - 200.0, b["max_z"] + 200.0)
			if not s.placer.in_bounds(x, z):
				continue
			if not s.track.nearest(x, z, r + s.track.wall_offset + 14.0).is_empty():
				continue
			var near_d := s.placer.approx_dist(x, z)
			if near_d > r + 170.0:
				continue
			var clash := false
			for q in placed:
				if Vector2(q.x - x, q.z - z).length() < q.y + r + 20.0:
					clash = true
			if clash:
				continue
			var v := Vector4(x, 0, z, 0)
			var score := _roughness(s, v, r * 0.8) + near_d * 0.02
			if score < best_score:
				best_score = score
				best = Vector4(x, 0, z, 1)
		if best.w == 0.0:
			continue
		placed.append(Vector3(best.x, r, best.z))
		s.placer.mark(best.x, best.z, r + 4.0)
		var y := _min_height(s, best, r * 0.85) - 1.5
		s.put(pk, Vector3(best.x, y, best.z), s.rng.randf() * 0.6, Vector3(r, r * 0.95, r))
		# 大金字塔前放一个石像头
		if r == sizes[0]:
			var ni := s.placer.nearest_idx(best.x, best.z)
			var dir := Vector3(s.track.px[ni] - best.x, 0, s.track.pz[ni] - best.z).normalized()
			var hp := Vector3(best.x, 0, best.z) + dir * (r + 12.0)
			if s.placer.ok(hp.x, hp.z, 6.0, false, false):
				var head := s.kind("nature/statue_head", Scenery.BIG)
				s.put(head, Vector3(hp.x, s.placer.ground(hp.x, hp.z, 5.0) - 0.5, hp.z), atan2(dir.x, dir.z), Vector3.ONE * 16.0)


static func _pond_mesh() -> ArrayMesh:
	var water := SceneryLib.flat_mat(Color("#3EC6E8"), 0.25, 0.08)
	var sand := SceneryLib.flat_mat(Color("#E9C98E"))
	return SceneryLib.merge([
		[SceneryProps.cyl(1.0, 1.0, 0.12, 20), SceneryProps.xf(Vector3(0, 0, 0)), water],
		[SceneryProps.cyl(1.18, 1.25, 0.1, 20), SceneryProps.xf(Vector3(0, -0.04, 0)), sand],
	])


## 某模型的网格（用于换一种批量设置，例如台地要投影）
static func model_mesh(s: Scenery, short: String) -> Mesh:
	var parts := short.split("/")
	return SceneryLib.model(s.theme_id, SceneryLib.NATURE + parts[1] + ".glb")["mesh"]


static func _roughness(s: Scenery, p: Vector4, r: float) -> float:
	var lo := INF
	var hi := -INF
	for k in 9:
		var a := TAU * k / 8.0
		var d := 0.0 if k == 8 else r
		var h := s.terrain.height_at(p.x + cos(a) * d, p.z + sin(a) * d)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


static func _avg_height(s: Scenery, p: Vector4, r: float) -> float:
	var sum := 0.0
	for k in 8:
		var a := TAU * k / 8.0
		sum += s.terrain.height_at(p.x + cos(a) * r, p.z + sin(a) * r)
	return (sum / 8.0 + s.terrain.height_at(p.x, p.z)) * 0.5


static func _min_height(s: Scenery, p: Vector4, r: float) -> float:
	var lo := s.terrain.height_at(p.x, p.z)
	for k in 8:
		var a := TAU * k / 8.0
		lo = minf(lo, s.terrain.height_at(p.x + cos(a) * r, p.z + sin(a) * r))
	return lo


# ———————————————— 冰雪乐园 ————————————————

static func build_snow(s: Scenery) -> void:
	var P := s.placer
	var pines := [
		s.kind("nature/tree_pineTallA_detailed", Scenery.BIG_TINT), s.kind("nature/tree_pineTallB_detailed", Scenery.BIG_TINT),
		s.kind("nature/tree_pineTallC_detailed", Scenery.BIG_TINT), s.kind("nature/tree_pineTallD_detailed", Scenery.BIG_TINT),
		s.kind("nature/tree_pineRoundA", Scenery.BIG_TINT), s.kind("nature/tree_pineDefaultA", Scenery.BIG_TINT),
	]
	# 木屋（屋顶积雪）
	var cabins: Array = []
	for rc: String in ["#E8414B", "#3E8BFF"]:
		cabins.append(s.kind_mesh("cabin" + rc, SceneryProps.house_mesh("snow", Color("#B9774A"), Color(rc)), Scenery.BIG))
	for c in P.band(s.dn(4), 12, 46, 14.0, true, false):
		for h in P.cluster(Vector3(c.x, c.y, c.z), 2, 12.0, 5.5, true, true):
			s.put(s.pick(cabins), Vector3(h.x, h.y - 0.3, h.z), P.facing(h.x, h.z) + s.rf(-0.3, 0.3), Vector3.ONE * s.rf(0.9, 1.1))
	# 冰屋
	var igloo := s.kind_mesh("igloo", SceneryProps.igloo_mesh(), Scenery.BIG)
	for p in P.band(s.dn(6), 5, 40, 4.5, true):
		s.put(igloo, Vector3(p.x, p.y - 0.2, p.z), P.facing(p.x, p.z) + s.rf(-0.5, 0.5), Vector3.ONE * s.rf(0.9, 1.2))
	# 雪人（面朝赛道）
	var snowman := s.kind_mesh("snowman", SceneryProps.snowman_mesh(), Scenery.BIG)
	for p in P.band(s.dn(10), 3, 30, 1.8):
		s.put(snowman, Vector3(p.x, p.y - 0.15, p.z), P.facing(p.x, p.z) + s.rf(-0.4, 0.4), Vector3.ONE * s.rf(0.9, 1.25))
	# 冰晶簇
	var crystals: Array = []
	for i in 3:
		crystals.append(s.kind_mesh("crystal%d" % i, SceneryProps.crystal_mesh(s.rng), Scenery.BIG))
	var cspots := P.band(s.dn(26), 1, 36, 2.2)
	for g in P.band(s.dn(5), 8, 40, 8.0, false, false):
		cspots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 4, 7.0, 2.0, false, true))
	for p in cspots:
		var sc := s.rf(0.8, 1.5)
		s.put(s.pick(crystals), Vector3(p.x, p.y - 0.2, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.3), sc))
	# 松树：路边 + 成片松林 + 远处
	var tree_spots := P.band(s.dn(260), 6, 30, 2.4, true)
	tree_spots.append_array(P.band(s.dn(160), 30, 70, 2.4, true))
	for g in P.scatter(s.dn(12), 24, 60, 280, true, false):
		tree_spots.append_array(P.cluster(Vector3(g.x, g.y, g.z), 20, 26.0, 2.4, true, true))
	tree_spots.append_array(P.scatter(s.dn(150), 2.4, 90, 400, true))
	s.scatter_kinds(pines, tree_spots, 5.5, 8.5, true, 0.2, Vector2(0.9, 1.25))
	# 小松树、石头
	var small := [s.kind("nature/tree_pineSmallA", Scenery.MID_TINT), s.kind("nature/tree_pineSmallC", Scenery.MID_TINT), s.kind("nature/tree_pineGroundA", Scenery.MID_TINT)]
	s.scatter_kinds(small, P.band(s.dn(90), 1, 36, 1.5), 4.0, 6.0, true, 0.1)
	var rocks := [s.kind("nature/stone_largeB", Scenery.MID), s.kind("nature/stone_largeD", Scenery.MID), s.kind("nature/stone_largeF", Scenery.MID), s.kind("nature/stone_tallB", Scenery.MID)]
	var rs := P.band(s.dn(36), 1, 40, 2.2)
	rs.append_array(P.scatter(s.dn(40), 3, 45, 300))
	s.scatter_kinds(rocks, rs, 3.0, 7.0, false, 0.4)
