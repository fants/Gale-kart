class_name SceneryTown
extends RefCounted
## 城镇手指：赛道两侧是彩色的二三层联排小楼（门面朝赛道，底层有条纹遮阳篷），外圈是 City Kit 的日间楼宇；
## 起点附近一座钟楼，街角有喷泉广场；手指之间的空隙里是行道树、花坛、遮阳伞和路灯；发卡弯外侧立红白箭头牌。

const WALLS := ["#F6E3C4", "#FFD9C2", "#DDEBF7", "#F4F1E8", "#FFE9A8", "#E6F4D8"]
const ROOFS := ["#C8553D", "#8E3B2A", "#3E6BFF", "#4A7A3A", "#6B4A8E"]
const AWNINGS := ["#FF4D5E", "#3EC6FF", "#45E3A6", "#FFC93C"]
const CITY_NEAR := ["building-a", "building-b", "building-c", "building-d", "building-f", "building-g", "building-h", "building-i"]
const CITY_FAR := ["building-e", "building-j", "building-k", "building-n", "building-l", "building-m", "building-skyscraper-a", "building-skyscraper-c"]


static func build(s: Scenery) -> void:
	_townhouses(s)
	_clock_tower(s)
	_fountains(s)
	_city_blocks(s)
	_street_props(s)
	_greenery(s)
	SceneryMushroom.add_hairpin_signs(s, Color("#FF4D5E"), Color("#F7FAFF"))


## 联排小楼：墙身 + 坡屋顶 + 窗格 + 门 + 底层条纹遮阳篷。门面朝 +Z
static func townhouse_mesh(wall: Color, roof: Color, awning: Color, floors: int) -> ArrayMesh:
	var h := 3.2 * floors
	var w := 7.0
	var d := 6.0
	var walls := SceneryLib.flat_mat(wall, 0.0, 0.9)
	var roof_m := SceneryLib.flat_mat(roof, 0.0, 0.7)
	var trim := SceneryLib.flat_mat(Color("#FFFFFF"), 0.0, 0.8)
	var glass := SceneryLib.flat_mat(Color("#8FC9EE"), 0.12, 0.25)
	var wood := SceneryLib.flat_mat(Color("#7A4E2E"))
	var aw_a := SceneryLib.flat_mat(awning, 0.0, 0.7)
	var aw_b := SceneryLib.flat_mat(Color("#FFFFFF"), 0.0, 0.7)
	var roof_prism := PrismMesh.new()
	roof_prism.size = Vector3(d + 0.6, 2.4, w + 0.4)
	var parts: Array = [
		[SceneryProps.box(Vector3(w, h, d)), SceneryProps.xf(Vector3(0, h * 0.5, 0)), walls],
		[SceneryProps.box(Vector3(w + 0.3, 0.3, d + 0.3)), SceneryProps.xf(Vector3(0, h, 0)), trim],
		[roof_prism, SceneryProps.xf(Vector3(0, h + 1.2, 0), Vector3(0, PI / 2, 0)), roof_m],
		[SceneryProps.box(Vector3(0.9, 2.2, 0.8)), SceneryProps.xf(Vector3(2.2, h + 1.4, -1.2)), roof_m],
		[SceneryProps.box(Vector3(1.4, 2.3, 0.2)), SceneryProps.xf(Vector3(-2.2, 1.15, d * 0.5 + 0.05)), wood],
		[SceneryProps.box(Vector3(2.6, 1.6, 0.15)), SceneryProps.xf(Vector3(1.4, 1.35, d * 0.5 + 0.04)), glass],
	]
	# 底层遮阳篷：红白 / 蓝白条纹（5 条交替的小斜板）
	for i in 5:
		var x := 0.35 + (i - 2) * 0.62
		parts.append([SceneryProps.box(Vector3(0.62, 0.08, 1.3)), SceneryProps.xf(Vector3(x + 1.0, 2.55, d * 0.5 + 0.6), Vector3(0.45, 0, 0)), aw_a if i % 2 == 0 else aw_b])
	# 楼上窗格
	for f in range(1, floors):
		for wx: float in [-2.3, 0.0, 2.3]:
			var y := f * 3.2 + 1.5
			parts.append([SceneryProps.box(Vector3(1.2, 1.4, 0.12)), SceneryProps.xf(Vector3(wx, y, d * 0.5 + 0.03)), glass])
			parts.append([SceneryProps.box(Vector3(1.45, 0.14, 0.35)), SceneryProps.xf(Vector3(wx, y - 0.78, d * 0.5 + 0.12)), trim])
			parts.append([SceneryProps.box(Vector3(1.2, 1.4, 0.12)), SceneryProps.xf(Vector3(wx, y, -d * 0.5 - 0.03)), glass])
	return SceneryLib.merge(parts)


static func _townhouses(s: Scenery) -> void:
	var P := s.placer
	var kinds: Array = []
	for i in 8:
		var floors := 2 + (i % 2)
		kinds.append(s.kind_mesh("townhouse%d" % i, townhouse_mesh(Color(WALLS[i % WALLS.size()]), Color(ROOFS[(i * 3) % ROOFS.size()]),
			Color(AWNINGS[i % AWNINGS.size()]), floors), Scenery.BIG))
	# 近处一排（门面朝赛道），外面再一排
	for p in P.band(s.dn(110), 3, 16, 5.0, true):
		s.put(s.pick(kinds), Vector3(p.x, p.y - 0.25, p.z), P.facing(p.x, p.z), Vector3.ONE * s.rf(0.95, 1.12))
	for p in P.band(s.dn(90), 18, 55, 5.0, true):
		s.put(s.pick(kinds), Vector3(p.x, p.y - 0.25, p.z), P.facing(p.x, p.z) + s.rf(-0.3, 0.3), Vector3.ONE * s.rf(0.95, 1.2))


## 钟楼：方塔 + 四面钟盘 + 尖顶。放在起点前方路边，开场航拍能看到
static func _clock_tower(s: Scenery) -> void:
	var t := s.track
	var stone := SceneryLib.flat_mat(Color("#E8D8BC"), 0.0, 0.9)
	var brick := SceneryLib.flat_mat(Color("#C8553D"), 0.0, 0.85)
	var roof := SceneryLib.flat_mat(Color("#2F5F8E"), 0.0, 0.6)
	var face := SceneryLib.flat_mat(Color("#FFFBF0"), 0.25, 0.5)
	var hand := SceneryLib.flat_mat(Color("#1B1F3B"))
	var gold := SceneryLib.flat_mat(Color("#FFC93C"), 0.4, 0.4)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 4.4
	spire.height = 9.0
	spire.radial_segments = 4
	var parts: Array = [
		[SceneryProps.box(Vector3(7, 3, 7)), SceneryProps.xf(Vector3(0, 1.5, 0)), stone],
		[SceneryProps.box(Vector3(5.6, 20, 5.6)), SceneryProps.xf(Vector3(0, 11, 0)), brick],
		[SceneryProps.box(Vector3(6.4, 0.6, 6.4)), SceneryProps.xf(Vector3(0, 15.2, 0)), stone],
		[SceneryProps.box(Vector3(6.4, 0.6, 6.4)), SceneryProps.xf(Vector3(0, 21.2, 0)), stone],
		[spire, SceneryProps.xf(Vector3(0, 26.0, 0), Vector3(0, PI / 4, 0)), roof],
		[SceneryProps.sphere(0.45, 8, 6), SceneryProps.xf(Vector3(0, 30.8, 0)), gold],
	]
	for k in 4:
		var yaw := k * PI * 0.5
		var b := Basis(Vector3.UP, yaw)
		var c := b * Vector3(0, 18.2, 2.85)
		parts.append([SceneryProps.cyl(2.0, 2.0, 0.2, 20), Transform3D(b * Basis(Vector3.RIGHT, PI / 2), c), face])
		parts.append([SceneryProps.box(Vector3(0.18, 1.5, 0.1)), Transform3D(b, c + b * Vector3(0, 0.6, 0.14)), hand])
		parts.append([SceneryProps.box(Vector3(1.1, 0.16, 0.1)), Transform3D(b * Basis(Vector3.BACK, 0.5), c + b * Vector3(0.4, 0.2, 0.15)), hand])
	var mi := MeshInstance3D.new()
	mi.name = "ClockTower"
	mi.mesh = SceneryLib.merge(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 起点前方 60–120 m 的路边找一个空地
	for tries in 40:
		var sm := s.rf(60.0, 140.0) / t.spacing
		var side := -1.0 if tries % 2 == 0 else 1.0
		var p := t.point_at(sm, side * (t.wall_offset + s.rf(12.0, 22.0)))
		if s.placer.clear_of_track(p.x, p.z, 5.0, 3.0) and s.placer.is_free(p.x, p.z, 5.0):
			s.placer.mark(p.x, p.z, 6.0)
			s.add_node(mi, Vector3(p.x, s.placer.ground(p.x, p.z, 4.0) - 0.3, p.z), s.placer.facing(p.x, p.z))
			return


## 喷泉广场：圆形水池 + 中央两层水盘，周围一圈花坛
static func _fountains(s: Scenery) -> void:
	var stone := SceneryLib.flat_mat(Color("#E3D8C6"), 0.0, 0.8)
	var water := SceneryLib.flat_mat(Color("#5FC8FF"), 0.25, 0.1)
	var plaza := SceneryLib.flat_mat(Color("#D9C8A8"), 0.0, 0.95)
	var parts: Array = [
		[SceneryProps.cyl(9.0, 9.0, 0.2, 28), SceneryProps.xf(Vector3(0, 0.1, 0)), plaza],
		[SceneryProps.cyl(4.2, 4.4, 0.9, 24), SceneryProps.xf(Vector3(0, 0.45, 0)), stone],
		[SceneryProps.cyl(3.8, 3.8, 0.1, 24), SceneryProps.xf(Vector3(0, 0.82, 0)), water],
		[SceneryProps.cyl(0.35, 0.5, 2.6, 10), SceneryProps.xf(Vector3(0, 1.3, 0)), stone],
		[SceneryProps.cyl(1.8, 1.2, 0.35, 16), SceneryProps.xf(Vector3(0, 2.4, 0)), stone],
		[SceneryProps.cyl(1.6, 1.6, 0.08, 16), SceneryProps.xf(Vector3(0, 2.6, 0)), water],
		[SceneryProps.cyl(0.9, 0.6, 0.3, 12), SceneryProps.xf(Vector3(0, 3.4, 0)), stone],
		[SceneryProps.cyl(0.15, 0.3, 1.2, 8), SceneryProps.xf(Vector3(0, 3.9, 0)), water],
	]
	var k := s.kind_mesh("fountain", SceneryLib.merge(parts), Scenery.BIG)
	for p in s.placer.band(s.dn(4), 4, 30, 9.5, true):
		s.put(k, Vector3(p.x, p.y - 0.05, p.z), s.rng.randf() * TAU, Vector3.ONE)


## 外圈：City Kit 日间楼宇（原贴图，不点亮窗户）
static func _city_blocks(s: Scenery) -> void:
	var P := s.placer
	var b := s.track.bounds
	var step := 36.0
	var x: float = b["min_x"] - 380.0
	while x < b["max_x"] + 380.0:
		var z: float = b["min_z"] - 380.0
		while z < b["max_z"] + 380.0:
			var px := x + s.rf(-5.0, 5.0)
			var pz := z + s.rf(-5.0, 5.0)
			z += step
			var d := P.approx_dist(px, pz)
			if d < 75.0 or d > 420.0 or s.rng.randf() > 0.35 + 0.55 * s.density:
				continue
			var nm: String = s.pick(CITY_NEAR) if d < 170.0 else s.pick(CITY_FAR)
			var k := s.kind("city/" + nm, {"shadow": d < 170.0, "center": true})
			var ab := s.aabb_of(k)
			var sc := s.rf(11.0, 14.0) if d < 170.0 else s.rf(14.0, 18.0)
			var r := maxf(ab.size.x, ab.size.z) * sc * 0.6
			if not P.ok(px, pz, r, true, true):
				continue
			P.mark(px, pz, r)
			s.put(k, Vector3(px, P.ground(px, pz, r) - 0.4, pz), snappedf(P.facing(px, pz), PI * 0.5), Vector3(sc, sc * s.rf(0.9, 1.2), sc))
		x += step


## 街边小物：路灯、遮阳伞、花坛、长椅般的木箱
static func _street_props(s: Scenery) -> void:
	var P := s.placer
	var lamp := s.kind_mesh("townlamp", SceneryProps.lamp_mesh(Color("#FFE7B0")), {"shadow": false})
	var t := s.track
	var step := roundi(34.0 / t.spacing)
	var sd := 1.0
	for i in range(0, t.n, step):
		sd = -sd
		var p := t.point_at(float(i), sd * (t.wall_offset + 0.28))
		var yaw := atan2(-t.nx[i] * sd, -t.nz[i] * sd)
		s.put(lamp, Vector3(p.x, t.py[i] + 1.15, p.z), yaw, Vector3.ONE)
	var umbrellas: Array = []
	for nm in ["detail-parasol-a", "detail-parasol-b"]:
		umbrellas.append(s.kind("city/" + nm, {"shadow": true, "center": true}))
	for p in P.band(s.dn(40), 0.5, 12, 1.8):
		var k: String = s.pick(umbrellas)
		var ab := s.aabb_of(k)
		var sc := 3.2 / maxf(ab.size.y, 0.01)
		s.put(k, Vector3(p.x, p.y, p.z), s.rng.randf() * TAU, Vector3.ONE * sc)
	var patches: Array = []
	var sets := [["flower_redA", "flower_redB", "flower_yellowA"], ["flower_purpleA", "flower_purpleB", "flower_yellowC"]]
	for i in sets.size():
		patches.append(s.kind_mesh("tpatch%d" % i, SceneryProps.flower_patch("village", sets[i], s.rng, 8, 1.5, 5.0), Scenery.SMALL))
	s.scatter_kinds(patches, P.band(s.dn(160), 0.3, 20, 1.6, false, false), 0.9, 1.1, false, 0.05, Vector2(1, 1))


## 行道树与远处树林、草丛
static func _greenery(s: Scenery) -> void:
	var P := s.placer
	var trees := [s.kind("nature/tree_default", Scenery.BIG_TINT), s.kind("nature/tree_cone", Scenery.BIG_TINT),
		s.kind("nature/tree_oak", Scenery.BIG_TINT), s.kind("nature/tree_small", Scenery.BIG_TINT)]
	for p in P.band(s.dn(140), 0.5, 14, 2.2, true):
		var sc := s.rf(4.5, 6.5)
		s.put(s.pick(trees), Vector3(p.x, p.y - 0.1, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.95, 1.2), sc), s.tint())
	for p in P.scatter(s.dn(140), 2.6, 90, 420, true):
		var sc := s.rf(6.0, 9.0)
		s.put(s.pick(trees), Vector3(p.x, p.y - 0.15, p.z), s.rng.randf() * TAU, Vector3(sc, sc * s.rf(0.9, 1.2), sc), s.tint())
	var grass := s.kind_mesh("tgpatch", SceneryProps.flower_patch("village", ["grass", "grass_large"], s.rng, 5, 1.3, 4.0), Scenery.SMALL_TINT)
	s.scatter_kinds([grass], P.band(s.dn(420), 0.0, 36, 1.2, false, false), 0.9, 1.2, true, 0.05)
