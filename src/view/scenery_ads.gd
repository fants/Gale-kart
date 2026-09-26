class_name SceneryAds
extends RefCounted
## 赛道边的广告牌（虚构赞助商）与起点直道护墙上的横幅。贴图由 GPT Image 生成，在 assets/textures/ads/。
## 广告牌立在直道 / 缓弯的护墙外，斜对着来车方向；夜间主题的广告牌自发光。

const DIR := "res://assets/textures/ads/"
const DAY: Array[String] = ["ad_nitro", "ad_soda", "ad_tires", "ad_gp", "ad_marshmallow", "ad_banana", "ad_speed"]
const NIGHT: Array[String] = ["ad_neon", "ad_nitro", "ad_gp", "ad_tires", "ad_speed", "ad_soda"]
const BANNERS: Array[String] = ["banner_gp", "banner_creator", "banner_start"]
## 作者（bilibili）的广告牌：每条赛道第一块一定是它，之后每隔几块再出现一次
const CREATOR: Array[String] = ["ad_creator", "ad_creator_2"]
const BOARD_W := 9.0
const BOARD_H := 4.5
const BOARD_LIFT := 2.4
## 起点前后挂横幅的范围（米）
const BANNER_FROM := -44.0
const BANNER_TO := 56.0
const BANNER_W := 3.3


static func build(s: Scenery) -> void:
	var night: bool = s.theme.get("night", false)
	_billboards(s, night)
	_banners(s, night)


static func _mat(path: String, night: bool, cache: Dictionary) -> StandardMaterial3D:
	if cache.has(path):
		return cache[path]
	var tex: Texture2D = load(DIR + path + ".jpg")
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# 白天也带一点自发光，在阴影里不至于发黑；夜里亮起来
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.32 if night else 0.18
	cache[path] = m
	return m


## 某点离赛道其他路段、支路都够远（只允许靠近 i 附近这一段）
static func _clear(t: TrackData, i: int, p: Vector3, r: float) -> bool:
	for hit in t.nearest_all(p.x, p.z, t.wall_offset + r):
		var d := absi(int(hit["idx"]) - i)
		if mini(d, t.n - d) * t.spacing > 45.0:
			return false
		if float(hit["d"]) < t.wo[int(hit["idx"])] + 1.5:
			return false
	for b in t.branches:
		if not b.nearest(p.x, p.z, b.wall_offset + r).is_empty():
			return false
	return true


static func _billboards(s: Scenery, night: bool) -> void:
	var t := s.track
	var ids := NIGHT if night else DAY
	var cache := {}
	var frame := SceneryLib.flat_mat(Color("#1B1F3B") if night else Color("#F4F1EA"), 0.2, 0.6)
	var post := SceneryLib.flat_mat(Color("#3A3F52"), 0.4, 0.5)
	var want := clampi(int(t.length / 150.0), 5, 11)
	var placed := 0
	var used: Array[Vector3] = []
	# 第一块（作者广告）从起点前方 70 m 开始找位置，开局就能看到
	var pos := 70.0 / t.spacing
	var tries := 0
	while placed < want and tries < 60:
		tries += 1
		pos += (s.rf(90.0, 140.0) if placed > 0 or tries > 6 else 12.0 * float(tries > 1)) / t.spacing
		var i := int(fposmod(pos, t.n))
		if absf(t.curv[i]) > 1.0 / 55.0:
			continue
		# 弯道外侧优先（进弯时正对车头），直道随机一侧
		var side := (1.0 if t.curv[i] > 0.0 else -1.0) if absf(t.curv[i]) > 1.0 / 250.0 else (1.0 if s.rng.randf() < 0.5 else -1.0)
		if t.edge_at(i, side) != TrackData.EDGE_WALL:
			side = -side
			if t.edge_at(i, side) != TrackData.EDGE_WALL:
				continue
		var p := t.point_at(float(i), side * (t.wo[i] + 5.5))
		if Vector2(p.x - s.placer.start_pos.x, p.z - s.placer.start_pos.z).length() < 40.0:
			continue
		if not s.placer.in_bounds(p.x, p.z) or not s.placer.clear_of_rivers(p.x, p.z, 5.0) or not _clear(t, i, p, 5.5):
			continue
		var near_other := false
		for u in used:
			if u.distance_to(p) < 60.0:
				near_other = true
		if near_other:
			continue
		used.append(p)
		# 牌面朝向：迎着来车，向赛道内侧转一点
		var fwd := Vector3(t.tx[i], 0.0, t.tz[i]).normalized()
		var inward := Vector3(t.nx[i], 0.0, t.nz[i]).normalized() * -side
		var face := (-fwd * 0.75 + inward * 0.66).normalized()
		var basis := Basis.looking_at(-face, Vector3.UP)
		var g := s.placer.ground(p.x, p.z, 3.0)
		var base := Vector3(p.x, g, p.z)
		var node := Node3D.new()
		node.name = "Billboard"
		var parts: Array = []
		var cy := BOARD_LIFT + BOARD_H * 0.5
		# 外框 + 背板（深色），两根立柱
		parts.append([SceneryProps.box(Vector3(BOARD_W + 0.5, BOARD_H + 0.5, 0.3)), Transform3D(Basis(), Vector3(0, cy, -0.12)), frame])
		for px: float in [-BOARD_W * 0.3, BOARD_W * 0.3]:
			parts.append([SceneryProps.cyl(0.18, 0.22, cy, 8), Transform3D(Basis(), Vector3(px, cy * 0.5, -0.25)), post])
		var body := MeshInstance3D.new()
		body.mesh = SceneryLib.merge(parts)
		node.add_child(body)
		var face_mesh := QuadMesh.new()
		face_mesh.size = Vector2(BOARD_W, BOARD_H)
		var fm := MeshInstance3D.new()
		fm.mesh = face_mesh
		var ad := ids[placed % ids.size()]
		if placed % 4 == 0:
			ad = CREATOR[(placed / 4) % CREATOR.size()]
		fm.material_override = _mat(ad, night, cache)
		fm.position = Vector3(0, cy, 0.05)
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(fm)
		s.add_child(node)
		node.transform = Transform3D(basis, base)
		s.placer.mark(p.x, p.z, BOARD_W * 0.6)
		placed += 1
	s.stats["billboards"] = placed


## 起点前后的护墙内侧挂一排横幅（GALE KART / START FINISH 交替）
static func _banners(s: Scenery, night: bool) -> void:
	var t := s.track
	var cache := {}
	var quad := QuadMesh.new()
	quad.size = Vector2(BANNER_W, BANNER_W / 3.0)
	var root := Node3D.new()
	root.name = "Banners"
	s.add_child(root)
	var step := BANNER_W + 0.25
	var k := 0
	var m := BANNER_FROM
	while m < BANNER_TO:
		var sf := t.wrap_s(m / t.spacing)
		var i := int(sf)
		# 急弯外侧的护墙可能挂着导向板，只在直道 / 缓弯上挂横幅
		if absf(t.curv[i]) > 1.0 / 55.0:
			k += 1
			m += step
			continue
		for side: float in [-1.0, 1.0]:
			if t.edge_at(i, side) != TrackData.EDGE_WALL:
				continue
			var p := t.point_at(sf, side * (t.wo_at(sf) - 0.04))
			var inward := Vector3(t.nx[i], 0.0, t.nz[i]).normalized() * -side
			var basis := Basis(Vector3.UP.cross(inward), Vector3.UP, inward)
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = _mat(BANNERS[(k + (1 if side > 0.0 else 0)) % BANNERS.size()], night, cache)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			mi.transform = Transform3D(basis, Vector3(p.x, t.center_y(sf) + quad.size.y * 0.5 + 0.02, p.z))
		k += 1
		m += step
