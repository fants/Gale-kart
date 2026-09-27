class_name SceneryCity
extends RefCounted
## 霓虹夜城：City Kit 楼宇（沿路一排中低层、往外是摩天楼、最外圈低模天际线），窗户夜间随机点亮；
## 临街立面挂霓虹招牌（发光边框 + 文字，呼吸闪烁）；护墙顶上的路灯（发光灯头 + 灯光池只点亮离相机最近的几盏）；
## 立交桥下的彩色地面灯光。

const WINDOW_SHADER := preload("res://assets/shaders/window_lights.gdshader")
const COLORMAP := preload("res://assets/models/city/Textures/colormap.png")
const NEAR_KINDS := ["building-a", "building-b", "building-c", "building-d", "building-f", "building-g", "building-h", "building-i"]
const TALL_KINDS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e", "building-l", "building-m"]
const WIDE_KINDS := ["building-e", "building-j", "building-k", "building-n"]
const FAR_KINDS := ["low-detail-building-a", "low-detail-building-b", "low-detail-building-c", "low-detail-building-d", "low-detail-building-f",
	"low-detail-building-h", "low-detail-building-j", "low-detail-building-l", "low-detail-building-wide-a", "low-detail-building-wide-b"]
const WORDS := ["疾风", "GALE", "KART", "24H", "拉面", "夜市", "电玩", "奶茶", "烧烤", "极速", "霓虹", "漂移", "HOTEL", "咖啡", "冲刺", "BAR"]
const VERTICAL := ["拉面", "夜市", "电玩", "奶茶", "烧烤", "咖啡"]
## 英文界面的招牌文字（顺序与中文一一对应，竖排的也是短词）
const WORDS_EN := ["GALE", "GALE", "KART", "24H", "RAMEN", "BAR", "ARCADE", "BOBA", "BBQ", "TURBO", "NEON", "DRIFT", "HOTEL", "CAFE", "NITRO", "BAR"]
const VERTICAL_EN := ["RAMEN", "BAR", "GAME", "BOBA", "BBQ", "CAFE"]


static func _words() -> Array:
	return WORDS_EN if Loc.is_en() else WORDS


static func _vertical() -> Array:
	return VERTICAL_EN if Loc.is_en() else VERTICAL
const NEON := ["#3EC6FF", "#FF4DC4", "#FFC93C", "#45E3A6", "#B98CFF", "#FF6B6B"]
## 灯光池大小（路灯）+ 立交桥下的固定彩灯，合计不超过 20 盏
const LAMP_POOL := 16
const UNDERPASS_MAX := 4


static func build(s: Scenery) -> void:
	for step in steps(s):
		step.call()


## 分帧构建用的步骤（顺序与一次做完相同）
static func steps(s: Scenery) -> Array[Callable]:
	var st := {}
	return [
		func() -> void:
			s.placer.start_clear = 40.0
			var win := ShaderMaterial.new()
			win.shader = WINDOW_SHADER
			win.set_shader_parameter("albedo_tex", COLORMAP)
			st["win"] = win
			st["street"] = _street_row(s, win),
		func() -> void: _blocks(s, st["win"]),
		func() -> void:
			var mats := _neon_mats(s)
			var parts: Array = []
			_neon_signs(s, st["street"], mats, parts)
			_neon_pylons(s, mats, parts)
			if not parts.is_empty():
				var mi := MeshInstance3D.new()
				mi.name = "NeonSigns"
				mi.mesh = SceneryLib.merge(parts)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				s.add_child(mi),
		func() -> void:
			_lamps(s)
			_underpass_lights(s),
	]


## City Kit 模型换成夜景窗户材质，注册为批量类型
static func _bkind(s: Scenery, nm: String, win: Material, shadow: bool) -> String:
	var key := "city/" + nm + ("#s" if shadow else "")
	if s.batch.has(key):
		return key
	var m: Dictionary = SceneryLib.model("city", SceneryLib.CITY + nm + ".glb", {"center": true})
	return s.kind_mesh(key, SceneryLib.merge([[m["mesh"], Transform3D.IDENTITY, win]]), {"shadow": shadow})


## 霓虹材质（每种颜色一个，登记到 Scenery 里做呼吸闪烁）
static func _neon_mats(s: Scenery) -> Array[StandardMaterial3D]:
	var mats: Array[StandardMaterial3D] = []
	for c: String in NEON:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c)
		m.emission_enabled = true
		m.emission = Color(c)
		m.emission_energy_multiplier = 3.2
		mats.append(m)
		s.neon_mats.append(m)
		s.neon_base.append(3.2)
	return mats


## 临街一排中低层楼，门面朝赛道；返回每栋楼的位置与尺寸（挂招牌用）
static func _street_row(s: Scenery, win: Material) -> Array[Dictionary]:
	var P := s.placer
	var out: Array[Dictionary] = []
	var tries := s.dn(90) * 5
	var want := s.dn(90)
	while out.size() < want and tries > 0:
		tries -= 1
		var nm: String = s.pick(NEAR_KINDS)
		var k := _bkind(s, nm, win, false)
		var ab := s.aabb_of(k)
		var sc := minf(s.rf(13.0, 16.0), 17.0 / maxf(ab.size.x, ab.size.z))
		var r := maxf(ab.size.x, ab.size.z) * sc * 0.62
		var spots := P.band(1, 3.0, 16.0, r, true)
		if spots.is_empty():
			continue
		var p := spots[0]
		var yaw := P.facing(p.x, p.z)
		var y := P.ground(p.x, p.z, r) - 0.3
		s.put(k, Vector3(p.x, y, p.z), yaw, Vector3.ONE * sc)
		out.append({"pos": Vector3(p.x, y, p.z), "yaw": yaw, "w": ab.size.x * sc, "d": ab.size.z * sc, "h": ab.size.y * sc})
	return out


## 往外按街区网格排楼：近处中高层与宽楼，中间摩天楼，最外圈低模天际线
static func _blocks(s: Scenery, win: Material) -> void:
	var P := s.placer
	var b := s.track.bounds
	var step := 34.0
	var x: float = b["min_x"] - 420.0
	while x < b["max_x"] + 420.0:
		var z: float = b["min_z"] - 420.0
		while z < b["max_z"] + 420.0:
			var px := x + s.rf(-4.0, 4.0)
			var pz := z + s.rf(-4.0, 4.0)
			z += step
			var d := P.approx_dist(px, pz)
			if d > 470.0 or d < 20.0:
				continue
			var nm: String
			var sc: float
			if d < 120.0:
				nm = s.pick(TALL_KINDS) if s.rng.randf() < 0.55 else s.pick(WIDE_KINDS)
				sc = s.rf(13.0, 17.0)
			elif d < 230.0:
				nm = s.pick(TALL_KINDS)
				sc = s.rf(15.0, 19.0)
			else:
				nm = s.pick(FAR_KINDS)
				sc = s.rf(22.0, 30.0)
			if s.rng.randf() < clampf((d - 300.0) / 400.0, 0.0, 0.5) or s.rng.randf() > 0.4 + 0.6 * s.density:
				continue
			var k := _bkind(s, nm, win, false)
			var ab := s.aabb_of(k)
			var r := maxf(ab.size.x, ab.size.z) * sc * 0.6
			if not P.ok(px, pz, r, true, true):
				continue
			P.mark(px, pz, r)
			var yaw: float = snappedf(P.facing(px, pz), PI * 0.5) if d < 230.0 else s.pick([0.0, PI * 0.5, PI, -PI * 0.5])
			s.put(k, Vector3(px, P.ground(px, pz, r) - 0.5, pz), yaw, Vector3(sc, sc * s.rf(0.9, 1.25), sc))
		x += step


## 一块霓虹招牌：深色底板 + 发光边框（进 parts 合并）+ 文字（Label3D）。base 为招牌中心，yaw 为朝向
static func _sign(s: Scenery, word: String, vertical: bool, ci: int, base: Vector3, yaw: float, mats: Array[StandardMaterial3D], parts: Array, px := 0.02) -> void:
	var cn := word.unicode_at(0) >= 128
	var ch := 128.0 * px
	var sw := ch * 1.25 if vertical else (0.8 + word.length() * ch * (1.0 if cn else 0.72))
	var sh := (word.length() * ch * 1.02 + 0.6) if vertical else ch + 0.7
	var basis := Basis(Vector3.UP, yaw)
	parts.append([SceneryProps.box(Vector3(sw + 0.5, sh + 0.5, 0.3)), Transform3D(basis, base), SceneryLib.flat_mat(Color("#141726"), 0.0, 0.6)])
	var t := 0.16
	for e: Array in [[Vector3(sw + 0.5, t, t), Vector3(0, sh * 0.5 + 0.25, 0.2)], [Vector3(sw + 0.5, t, t), Vector3(0, -sh * 0.5 - 0.25, 0.2)],
			[Vector3(t, sh + 0.5, t), Vector3(sw * 0.5 + 0.25, 0, 0.2)], [Vector3(t, sh + 0.5, t), Vector3(-sw * 0.5 - 0.25, 0, 0.2)]]:
		parts.append([SceneryProps.box(e[0]), Transform3D(basis, base + basis * (e[1] as Vector3)), mats[ci]])
	var col := Color(NEON[ci])
	var text := "\n".join(word.split("")) if vertical else word
	var l := SceneryProps.label(text, SceneryProps.FONT_CN if cn else SceneryProps.FONT_EN, 128, Color(col.r * 1.8, col.g * 1.8, col.b * 1.8), base + basis * Vector3(0, 0, 0.2), yaw, px, 10)
	l.outline_modulate = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4)
	l.line_spacing = -10.0
	s.add_child(l)


## 临街楼立面上的招牌
static func _neon_signs(s: Scenery, street: Array[Dictionary], mats: Array[StandardMaterial3D], parts: Array) -> void:
	var n := mini(street.size(), s.dn(40))
	for i in n:
		var bld: Dictionary = street[i]
		if s.rng.randf() > 0.75:
			continue
		var word: String = _words()[i % WORDS.size()]
		var vertical := word in _vertical() and s.rng.randf() < 0.7
		var h: float = bld["h"]
		var y := clampf(s.rf(5.0, 10.0), 4.0, maxf(4.0, h - 5.0))
		var yaw: float = bld["yaw"]
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var base: Vector3 = bld["pos"] + fwd * (float(bld["d"]) * 0.5 + 0.35) + right * s.rf(-0.25, 0.25) * float(bld["w"]) + Vector3(0, y, 0)
		_sign(s, word, vertical, s.rng.randi() % NEON.size(), base, yaw, mats, parts, 0.026)


## 路边的霓虹灯箱立柱：护墙外侧，竖排文字朝向来车方向（斜 35°），追尾镜头里看得到
static func _neon_pylons(s: Scenery, mats: Array[StandardMaterial3D], parts: Array) -> void:
	var t := s.track
	var pole := SceneryLib.flat_mat(Color("#2A2E48"), 0.0, 0.5)
	var step := roundi(46.0 / t.spacing)
	var j := 0
	for i in range(step / 2, t.n, step):
		j += 1
		if j > s.dn(34):
			break
		var sd := 1.0 if j % 2 == 0 else -1.0
		var p := t.point_at(float(i), sd * (t.wall_offset + 2.6))
		if not s.placer.clear_of_track(p.x, p.z, 1.2, 1.0) or not s.placer.is_free(p.x, p.z, 1.5):
			continue
		# 桥下 / 其他路段上方不放
		var blocked := false
		for hit in t.nearest_all(p.x, p.z, t.wall_offset + 4.0):
			if absf(float(hit["idx"]) - i) > 20.0 and absf(float(hit["idx"]) - i) < t.n - 20.0:
				blocked = true
		if blocked:
			continue
		s.placer.mark(p.x, p.z, 1.5)
		var g := s.terrain.height_at(p.x, p.z)
		var word: String = _vertical()[j % VERTICAL.size()] if j % 3 != 0 else _words()[(j * 5) % WORDS.size()]
		var vertical := word in _vertical()
		# 面向来车：朝赛道并偏向后方（来车方向 = 赛道切线反方向）
		var dir := Vector3(-t.nx[i] * sd, 0, -t.nz[i] * sd) * 0.75 - Vector3(t.tx[i], 0, t.tz[i]) * 0.65
		var yaw := atan2(dir.x, dir.z)
		var ch := 128.0 * 0.024
		var sh := (word.length() * ch * 1.02 + 0.6) if vertical else ch + 0.7
		var top := 3.2 + sh + 0.5
		parts.append([SceneryProps.cyl(0.18, 0.22, top, 8), SceneryProps.xf(Vector3(p.x, g + top * 0.5, p.z)), pole])
		_sign(s, word, vertical, (j * 7) % NEON.size(), Vector3(p.x, g + 3.2 + sh * 0.5, p.z) + Vector3(sin(yaw), 0, cos(yaw)) * 0.3, yaw, mats, parts, 0.024)


## 路灯：立在护墙顶上，灯臂伸向路面，左右交替；灯光池按距离分配
static func _lamps(s: Scenery) -> void:
	var t := s.track
	var k := s.kind_mesh("lamp", SceneryProps.lamp_mesh(Color("#FFD9A0")), {"shadow": false})
	var step := roundi(30.0 / t.spacing)
	var sd := 1.0
	for i in range(0, t.n, step):
		sd = -sd
		var p := t.point_at(float(i), sd * (t.wall_offset + 0.28))
		var base_y := t.py[i] + 1.15
		# 立交处：灯杆不能戳穿上层桥面
		var blocked := false
		for hit in t.nearest_all(p.x, p.z, t.wall_offset + 3.0):
			var dy := float(hit["y"]) - base_y
			if dy > -2.0 and dy < 9.5 and absf(float(hit["idx"]) - i) > 20.0 and absf(float(hit["idx"]) - i) < t.n - 20.0:
				blocked = true
				break
		if blocked:
			continue
		var yaw := atan2(-t.nx[i] * sd, -t.nz[i] * sd)
		s.put(k, Vector3(p.x, base_y, p.z), yaw, Vector3.ONE)
		s.lamp_heads.append(Vector3(p.x, base_y, p.z) + Vector3(sin(yaw), 0, cos(yaw)) * 2.3 + Vector3(0, 7.2, 0))
	for j in LAMP_POOL:
		var l := OmniLight3D.new()
		l.name = "LampLight%d" % j
		l.light_color = Color("#FFC98A")
		l.light_energy = 2.4
		l.omni_range = 17.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.light_specular = 0.6
		l.visible = false
		s.add_child(l)
		s.lamp_pool.append(l)


## 立交桥下：下层路面上方放两盏彩色点光（青 / 粉），桥下被照亮
static func _underpass_lights(s: Scenery) -> void:
	var t := s.track
	var found: Array[Vector3] = []
	for i in range(0, t.n, 2):
		for hit in t.nearest_all(t.px[i], t.pz[i], 6.0):
			if float(hit["y"]) > t.py[i] + 5.0:
				var p := Vector3(t.px[i], t.py[i], t.pz[i])
				var dup := false
				for q in found:
					if q.distance_to(p) < 40.0:
						dup = true
				if not dup and found.size() * 2 < UNDERPASS_MAX:
					found.append(p)
					for sd: float in [-1.0, 1.0]:
						var l := OmniLight3D.new()
						l.name = "Underpass"
						l.light_color = Color("#3EC6FF") if sd < 0.0 else Color("#FF4DC4")
						l.light_energy = 5.0
						l.omni_range = 22.0
						l.shadow_enabled = false
						s.add_node(l, t.point_at(float(i), sd * t.half_width * 0.7) + Vector3(0, 3.5, 0))
				break
