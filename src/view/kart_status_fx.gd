class_name KartStatusFx
extends Node3D
## 车身状态特效：护盾（金色泡泡 + 光环 + 天使翅膀）、水泡、眩晕星星、乌云（雨丝 + 闪电）、
## 飞碟（碟形 + 锥形光束）、磁铁（吸力环 + 吸引线 + 头顶磁铁）、被锁定（头顶红色准星）。
## KartView 每帧调用 update_view；本节点跟随车的位置与朝向（本地原点在车底中心，+Z 为车头）。
## 各部件第一次需要时才创建，之后只切换显隐。

const SHIELD_SHADER := preload("res://assets/shaders/shield.gdshader")
const BUBBLE_SHADER := preload("res://assets/shaders/bubble.gdshader")
const CLOUD_SHADER := preload("res://assets/shaders/cloud.gdshader")
const RAIN_SHADER := preload("res://assets/shaders/fx_rain.gdshader")
const BEAM_SHADER := preload("res://assets/shaders/fx_beam.gdshader")
const RETICLE_SHADER := preload("res://assets/shaders/fx_reticle.gdshader")
const WING_SHADER := preload("res://assets/shaders/fx_wing.gdshader")

const SHIELD_TIME := 3.6
const BUBBLE_TIME := 1.6
const CLOUD_TIME := 5.0
const UFO_TIME := 3.0
const UFO_HEIGHT := 5.2

static var _rain_mesh: ArrayMesh
static var _bolt_mesh: ArrayMesh
static var _magnet_mesh: ArrayMesh

var kart: KartSim
var _parts := {}
var _mats := {}
var _seed := 0.0


func setup(p_kart: KartSim) -> void:
	kart = p_kart
	_seed = float(kart.index) * 0.618


func update_view(dt: float, time: float, lift: float) -> void:
	var k := kart
	if k == null:
		return
	_update_shield(k, time)
	_update_bubble(k, time, lift)
	_update_dizzy(k, time)
	_update_cloud(k, time)
	_update_ufo(k, time)
	_update_magnet(k, time)
	_update_lock(k, time, dt)


## 一次性建好并显示全部部件（预热着色器用：ItemView 在比赛开始时放一份在相机前的极小尺寸，
## 让所有材质提前编译，避免第一次出现时卡顿）
func build_all() -> void:
	if not _parts.has("Shield"):
		_parts["Shield"] = _build_shield()
	if not _parts.has("Cloud"):
		_parts["Cloud"] = _build_cloud()
	if not _parts.has("Ufo"):
		_parts["Ufo"] = _build_ufo()
	if not _parts.has("Magnet"):
		_parts["Magnet"] = _build_magnet()
	var fake := KartSim.new(0, "", false, KartsData.KARTS[0], KartsData.CHARACTERS[0], KartsData.PAINTS[0])
	fake.bubble = 1.0
	fake.dizzy = 1.0
	fake.locked_by = 1.0
	_update_bubble(fake, 0.0, 0.0)
	_update_dizzy(fake, 0.0)
	_update_lock(fake, 0.0, 1.0)
	for part: String in _parts:
		(_parts[part] as Node3D).visible = true
	# 雨丝的尺寸不随节点缩放，预热时设为全透明
	(_mats["rain"] as ShaderMaterial).set_shader_parameter("amount", 0.0)


func _hide(part: String) -> void:
	var n: Node3D = _parts.get(part)
	if n and n.visible:
		n.visible = false


static func _ease_out_back(u: float) -> float:
	var c := 1.9
	var v := u - 1.0
	return 1.0 + (c + 1.0) * v * v * v + c * v * v


static func _sphere(r: float, segs: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = segs >> 1
	return m


static func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# —————————————————— 护盾 ——————————————————

func _build_shield() -> Node3D:
	var g := Node3D.new()
	g.name = "Shield"
	var mat := ShaderMaterial.new()
	mat.shader = SHIELD_SHADER
	_mats["shield"] = mat
	var bubble := _mi(_sphere(1.0, 40), mat, Vector3(0, 0.95, 0))
	bubble.name = "Bubble"
	bubble.scale = Vector3(1.45, 1.25, 1.8)
	g.add_child(bubble)
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.3
	halo_mesh.outer_radius = 0.4
	halo_mesh.rings = 28
	halo_mesh.ring_segments = 8
	var halo := _mi(halo_mesh, FxModels.unlit(Color(1.0, 0.86, 0.35), false, 2.2), Vector3(0, 2.45, -0.1))
	halo.name = "Halo"
	halo.rotation.x = 0.15
	g.add_child(halo)
	var wmat := ShaderMaterial.new()
	wmat.shader = WING_SHADER
	_mats["wing"] = wmat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.1)
	quad.center_offset = Vector3(0.75, 0.0, 0.0)
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if side < 0.0 else "WingR"
		pivot.position = Vector3(0.35 * side, 1.35, -0.55)
		var w := _mi(quad, wmat)
		# 右翅膀翅根在 +X；左翅膀镜像
		w.scale = Vector3(side, 1.0, 1.0)
		pivot.add_child(w)
		g.add_child(pivot)
	add_child(g)
	return g


func _update_shield(k: KartSim, time: float) -> void:
	if k.shield <= 0.0:
		_hide("Shield")
		return
	var g: Node3D = _parts.get("Shield")
	if g == null:
		g = _build_shield()
		_parts["Shield"] = g
	g.visible = true
	var age := SHIELD_TIME - k.shield
	var pop := _ease_out_back(clampf(age / 0.3, 0.0, 1.0))
	var strength := 0.9 + sin(time * 10.0) * 0.1
	if k.shield < 1.0 and sin(time * 30.0) < 0.0:
		strength = 0.3
	strength *= clampf(k.shield / 0.12, 0.0, 1.0)
	(_mats["shield"] as ShaderMaterial).set_shader_parameter("strength", strength)
	(_mats["wing"] as ShaderMaterial).set_shader_parameter("alpha", clampf(strength * 1.1, 0.0, 1.0))
	var bubble := g.get_node("Bubble") as Node3D
	bubble.scale = Vector3(1.45, 1.25, 1.8) * maxf(pop, 0.05)
	var halo := g.get_node("Halo") as Node3D
	halo.position.y = 2.45 + sin(time * 4.0) * 0.08
	halo.scale = Vector3.ONE * maxf(pop, 0.05)
	var flap := sin(time * 7.0) * 0.35
	(g.get_node("WingL") as Node3D).rotation = Vector3(0.0, -0.55 - flap, 0.25)
	(g.get_node("WingR") as Node3D).rotation = Vector3(0.0, 0.55 + flap, -0.25)
	(g.get_node("WingL") as Node3D).scale = Vector3.ONE * maxf(pop, 0.05)
	(g.get_node("WingR") as Node3D).scale = Vector3.ONE * maxf(pop, 0.05)


# —————————————————— 水泡 ——————————————————

func _update_bubble(k: KartSim, time: float, lift: float) -> void:
	if k.bubble <= 0.0:
		_hide("Bubble")
		return
	var b: MeshInstance3D = _parts.get("Bubble")
	if b == null:
		var mat := ShaderMaterial.new()
		mat.shader = BUBBLE_SHADER
		mat.set_shader_parameter("wobble", 0.035)
		_mats["bubble"] = mat
		b = _mi(_sphere(1.0, 40), mat)
		b.name = "Bubble"
		add_child(b)
		_parts["Bubble"] = b
	b.visible = true
	var age := BUBBLE_TIME - k.bubble
	var s := _ease_out_back(clampf(age / 0.22, 0.0, 1.0))
	var fade := 1.0
	# 快结束时泡泡胀大后破掉
	if k.bubble < 0.14:
		var u := 1.0 - k.bubble / 0.14
		s *= 1.0 + u * 0.35
		fade = 1.0 - u
	var wob := sin(time * 7.0) * 0.07
	b.position = Vector3(0.0, 0.95 + lift, 0.0)
	b.scale = Vector3(1.75 + wob, 1.6 - wob, 1.95 + wob) * maxf(s, 0.05)
	b.rotation.y = time * 0.6
	(_mats["bubble"] as ShaderMaterial).set_shader_parameter("fade", fade)


# —————————————————— 眩晕星星 ——————————————————

func _update_dizzy(k: KartSim, time: float) -> void:
	if k.dizzy <= 0.0:
		_hide("Dizzy")
		return
	var g: Node3D = _parts.get("Dizzy")
	if g == null:
		g = Node3D.new()
		g.name = "Dizzy"
		var mat := FxModels.toon(Color("#FFE14A"), 0.9, 0.4)
		for i in 5:
			var st := _mi(FxModels.star_mesh(), mat)
			st.scale = Vector3.ONE * 1.6
			g.add_child(st)
		add_child(g)
		_parts["Dizzy"] = g
	g.visible = true
	g.position = Vector3(0.0, 2.2 + sin(time * 3.0) * 0.06, -0.05)
	g.rotation = Vector3(sin(time * 2.2) * 0.22, 0.0, cos(time * 1.7) * 0.18)
	var fade := clampf(k.dizzy / 0.25, 0.0, 1.0)
	var n := g.get_child_count()
	for i in n:
		var st := g.get_child(i) as Node3D
		var a := time * 5.0 + float(i) / n * TAU
		st.position = Vector3(cos(a) * 0.7, sin(a * 2.0 + i) * 0.06, sin(a) * 0.7)
		st.rotation = Vector3(0.0, -a + PI / 2.0 + time * 3.0, 0.0)
		st.scale = Vector3.ONE * 1.6 * fade


# —————————————————— 乌云 ——————————————————

func _build_cloud() -> Node3D:
	var g := Node3D.new()
	g.name = "Cloud"
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	_mats["cloud"] = mat
	var puffs := Node3D.new()
	puffs.name = "Puffs"
	g.add_child(puffs)
	var layout: Array[Vector4] = [
		Vector4(0.0, 0.25, 0.0, 0.95), Vector4(-0.95, 0.0, 0.1, 0.75), Vector4(0.95, 0.05, -0.1, 0.78),
		Vector4(-0.45, 0.45, -0.35, 0.7), Vector4(0.5, 0.5, 0.3, 0.68), Vector4(-0.1, -0.05, 0.6, 0.72),
		Vector4(0.1, 0.0, -0.65, 0.72), Vector4(-1.55, -0.15, -0.2, 0.5), Vector4(1.55, -0.1, 0.2, 0.52),
	]
	var sph := _sphere(1.0, 20)
	for v in layout:
		var p := _mi(sph, mat, Vector3(v.x, v.y, v.z))
		p.scale = Vector3(v.w * 1.1, v.w * 0.9, v.w)
		puffs.add_child(p)
	if _bolt_mesh == null:
		var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.35, -0.8, 0.05), Vector3(-0.15, -1.3, -0.05),
			Vector3(0.3, -2.1, 0.0), Vector3(-0.1, -2.6, 0.05), Vector3(0.2, -3.5, 0.0)])
		var radii := PackedFloat32Array([0.11, 0.1, 0.09, 0.08, 0.06, 0.03])
		_bolt_mesh = FxModels.tube(pts, radii, 6)
	var bolt := _mi(_bolt_mesh, FxModels.unlit(Color(1.0, 0.95, 0.55), false, 3.0), Vector3(0.2, -0.4, 0.0))
	bolt.name = "Bolt"
	g.add_child(bolt)
	add_child(g)
	if _rain_mesh == null:
		_rain_mesh = _make_rain_mesh(44, 1.35)
	var rmat := ShaderMaterial.new()
	rmat.shader = RAIN_SHADER
	_mats["rain"] = rmat
	var rain := _mi(_rain_mesh, rmat)
	rain.name = "Rain"
	rain.custom_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 7, 6))
	add_child(rain)
	_parts["Rain"] = rain
	return g


## 雨丝网格：count 个四边形，UV2 = 水平位置，COLOR.r = 下落相位
static func _make_rain_mesh(count: int, radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in count:
		var a := randf() * TAU
		var r := sqrt(randf()) * radius
		var c := Vector2(cos(a) * r, sin(a) * r)
		var ph := randf()
		var base := verts.size()
		for q: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			verts.append(Vector3(c.x, 2.0, c.y))
			uv.append(q)
			uv2.append(c)
			cols.append(Color(ph, 0.0, 0.0))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _update_cloud(k: KartSim, time: float) -> void:
	if k.cloud <= 0.0:
		_hide("Cloud")
		_hide("Rain")
		return
	var g: Node3D = _parts.get("Cloud")
	if g == null:
		g = _build_cloud()
		_parts["Cloud"] = g
	var rain := _parts["Rain"] as Node3D
	g.visible = true
	rain.visible = true
	var age := CLOUD_TIME - k.cloud
	var s := _ease_out_back(clampf(age / 0.4, 0.0, 1.0)) * clampf(k.cloud / 0.35, 0.0, 1.0)
	g.position = Vector3(0.0, 4.4 + sin(time * 1.6 + _seed) * 0.12, 0.0)
	# 云不跟着车身转（车被香蕉打转时也保持稳定），只慢慢自转
	g.global_basis = Basis(Vector3.UP, time * 0.35 + _seed).scaled(Vector3.ONE * maxf(s, 0.02))
	(_mats["rain"] as ShaderMaterial).set_shader_parameter("amount", clampf(s, 0.0, 1.0))
	# 偶尔打闪电：云体提亮 + 闪电条
	var ph := fposmod(time * 0.62 + _seed * 3.1, 1.0)
	var flash := ph < 0.09 and age > 0.4
	var bolt := g.get_node("Bolt") as Node3D
	bolt.visible = flash and fposmod(ph * 40.0, 1.0) < 0.7
	bolt.rotation.y = floorf(time * 0.62 + _seed * 3.1) * 2.1
	(_mats["cloud"] as ShaderMaterial).set_shader_parameter("flash", 0.55 if flash else 0.0)


# —————————————————— 飞碟 ——————————————————

func _build_ufo() -> Node3D:
	var g := Node3D.new()
	g.name = "Ufo"
	var body := Node3D.new()
	body.name = "Body"
	g.add_child(body)
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color("#CFD3EC")
	hull.metallic = 0.65
	hull.roughness = 0.28
	hull.rim_enabled = true
	hull.rim = 0.4
	var saucer := _mi(_sphere(1.55, 32), hull)
	saucer.scale = Vector3(1.0, 0.3, 1.0)
	body.add_child(saucer)
	var under := _mi(_sphere(0.8, 20), FxModels.toon(Color("#6C5BD8"), 0.4))
	under.scale = Vector3(1.0, 0.35, 1.0)
	under.position.y = -0.2
	body.add_child(under)
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 1.42
	rim_mesh.outer_radius = 1.62
	rim_mesh.rings = 40
	rim_mesh.ring_segments = 8
	body.add_child(_mi(rim_mesh, FxModels.toon(Color("#9B6BFF"), 0.6, 0.35)))
	var glass := FxModels.unlit(Color(0.6, 0.95, 1.0, 0.45))
	var dome := _mi(_sphere(0.72, 24), glass, Vector3(0, 0.3, 0))
	dome.scale = Vector3(1.0, 0.85, 1.0)
	body.add_child(dome)
	# 驾驶舱里的小外星人
	var alien := FxModels.toon(Color("#6BE36B"), 0.2)
	body.add_child(_mi(_sphere(0.3, 14), alien, Vector3(0, 0.45, 0)))
	var black := FxModels.toon(Color("#1B1F3B"), 0.0, 0.2)
	for sx: float in [-1.0, 1.0]:
		var eye := _mi(_sphere(0.1, 10), black, Vector3(0.12 * sx, 0.5, 0.24))
		eye.scale = Vector3(1.0, 1.3, 0.6)
		body.add_child(eye)
	# 边缘一圈闪烁的灯（两组交替）
	var lamp_a := FxModels.unlit(Color(1.0, 0.95, 0.5), false, 2.5)
	var lamp_b := FxModels.unlit(Color(0.45, 1.0, 0.95), false, 2.5)
	var lamps := Node3D.new()
	lamps.name = "Lamps"
	body.add_child(lamps)
	for i in 10:
		var a := float(i) / 10.0 * TAU
		var l := _mi(_sphere(0.1, 8), lamp_a if i % 2 == 0 else lamp_b, Vector3(cos(a) * 1.52, 0.02, sin(a) * 1.52))
		lamps.add_child(l)
	add_child(g)
	# 光束（从碟底到地面，挂在本节点下，按飞碟高度伸缩）
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.7
	beam_mesh.bottom_radius = 2.2
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 32
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	var bmat := ShaderMaterial.new()
	bmat.shader = BEAM_SHADER
	bmat.set_shader_parameter("color", Color(0.72, 0.62, 1.0))
	_mats["beam"] = bmat
	var beam := _mi(beam_mesh, bmat)
	beam.name = "UfoBeam"
	add_child(beam)
	_parts["UfoBeam"] = beam
	return g


func _update_ufo(k: KartSim, time: float) -> void:
	if k.ufo <= 0.0:
		_hide("Ufo")
		_hide("UfoBeam")
		return
	var g: Node3D = _parts.get("Ufo")
	if g == null:
		g = _build_ufo()
		_parts["Ufo"] = g
	var beam := _parts["UfoBeam"] as MeshInstance3D
	g.visible = true
	var age := UFO_TIME - k.ufo
	# 从高处降下，结束时升空离开
	var arrive := 1.0 - pow(1.0 - clampf(age / 0.6, 0.0, 1.0), 3.0)
	var leave := clampf((0.5 - k.ufo) / 0.5, 0.0, 1.0)
	var h := UFO_HEIGHT + (1.0 - arrive) * 11.0 + leave * leave * 12.0 + sin(time * 2.4 + _seed) * 0.18
	g.position = Vector3(0.0, h, 0.0)
	g.global_basis = Basis(Vector3.UP, time * 1.1 + _seed) * Basis(Vector3(1, 0, 0), sin(time * 1.9) * 0.1) * Basis(Vector3(0, 0, 1), cos(time * 1.5) * 0.08)
	var lamps := g.get_node("Body/Lamps") as Node3D
	lamps.rotation.y = time * 2.5
	var blink := fposmod(time * 4.0, 1.0) < 0.5
	for i in lamps.get_child_count():
		(lamps.get_child(i) as Node3D).visible = (i % 2 == 0) == blink
	var beam_on := arrive > 0.8 and leave < 0.6
	beam.visible = beam_on
	if beam_on:
		var top := h - 0.35
		var bottom := 0.05
		beam.position = Vector3(0.0, (top + bottom) * 0.5, 0.0)
		beam.scale = Vector3(1.0, top - bottom, 1.0)
		(_mats["beam"] as ShaderMaterial).set_shader_parameter("energy", (0.9 + sin(time * 12.0) * 0.12) * (1.0 - leave / 0.6))


# —————————————————— 磁铁 ——————————————————

func _build_magnet() -> Node3D:
	var g := Node3D.new()
	g.name = "Magnet"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.05
	ring_mesh.rings = 36
	ring_mesh.ring_segments = 6
	var ring_mat := FxModels.unlit(Color(1.0, 0.42, 0.72, 0.85), true, 1.8)
	for i in 3:
		var r := _mi(ring_mesh, ring_mat)
		r.name = "Ring%d" % i
		r.rotation.x = PI / 2.0
		g.add_child(r)
	# 吸引线：沿 Y 轴的细圆柱，按目标位置拉伸
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.09
	line_mesh.bottom_radius = 0.09
	line_mesh.height = 1.0
	line_mesh.radial_segments = 8
	line_mesh.rings = 1
	line_mesh.cap_top = false
	line_mesh.cap_bottom = false
	var lmat := ShaderMaterial.new()
	lmat.shader = BEAM_SHADER
	lmat.set_shader_parameter("mode", 1)
	lmat.set_shader_parameter("color", Color(1.0, 0.45, 0.75))
	lmat.set_shader_parameter("energy", 1.6)
	_mats["magnet_line"] = lmat
	var line := _mi(line_mesh, lmat)
	line.name = "Line"
	g.add_child(line)
	# 头顶的 U 形磁铁
	if _magnet_mesh == null:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		pts.append(Vector3(-0.24, 0.3, 0.0))
		radii.append(0.09)
		for i in 9:
			var a := PI + float(i) / 8.0 * PI
			pts.append(Vector3(cos(a) * 0.24, sin(a) * 0.24, 0.0))
			radii.append(0.09)
		pts.append(Vector3(0.24, 0.3, 0.0))
		radii.append(0.09)
		_magnet_mesh = FxModels.tube(pts, radii, 10)
	var icon := Node3D.new()
	icon.name = "Icon"
	icon.add_child(_mi(_magnet_mesh, FxModels.toon(Color("#FF4D5E"), 0.35, 0.35)))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.1
	tip.bottom_radius = 0.1
	tip.height = 0.14
	for sx: float in [-1.0, 1.0]:
		icon.add_child(_mi(tip, FxModels.toon(Color("#E8ECF7"), 0.3, 0.25), Vector3(0.24 * sx, 0.36, 0.0)))
	g.add_child(icon)
	add_child(g)
	return g


func _update_magnet(k: KartSim, time: float) -> void:
	if k.magnet <= 0.0:
		_hide("Magnet")
		return
	var g: Node3D = _parts.get("Magnet")
	if g == null:
		g = _build_magnet()
		_parts["Magnet"] = g
	g.visible = true
	# 吸力环：从车头向前扩散、变大、变淡
	for i in 3:
		var r := g.get_node("Ring%d" % i) as MeshInstance3D
		var ph := fposmod(time * 1.5 + float(i) / 3.0, 1.0)
		r.position = Vector3(0.0, 1.0, 1.3 + ph * 4.2)
		r.scale = Vector3.ONE * (0.4 + ph * 0.55)
		r.transparency = ph
	var icon := g.get_node("Icon") as Node3D
	icon.position = Vector3(0.0, 2.45 + sin(time * 5.0) * 0.07, -0.05)
	icon.rotation = Vector3(0.0, time * 2.2, sin(time * 9.0) * 0.12)
	var line := g.get_node("Line") as MeshInstance3D
	var t := k.magnet_target
	if t == null:
		line.visible = false
		return
	var a := Vector3(0.0, 0.8, 1.2)
	var b := to_local(Vector3(t.x, t.y + 0.8, t.z))
	var d := b - a
	var dist := d.length()
	line.visible = dist > 1.0
	if dist > 1.0:
		var y := d / dist
		var x := y.cross(Vector3.UP)
		if x.length_squared() < 1e-4:
			x = Vector3.RIGHT
		x = x.normalized()
		var z := x.cross(y)
		line.transform = Transform3D(Basis(x, y * dist, z), (a + b) * 0.5)
		(_mats["magnet_line"] as ShaderMaterial).set_shader_parameter("length_m", dist)


# —————————————————— 被锁定 ——————————————————

func _update_lock(k: KartSim, time: float, dt: float) -> void:
	var r: MeshInstance3D = _parts.get("Lock")
	if k.locked_by <= 0.0:
		if r and r.visible:
			var a: float = r.get_meta("a", 0.0) - dt * 6.0
			r.set_meta("a", a)
			if a <= 0.0:
				r.visible = false
			else:
				(_mats["lock"] as ShaderMaterial).set_shader_parameter("amount", a)
		return
	if r == null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = RETICLE_SHADER
		mat.render_priority = 2
		_mats["lock"] = mat
		r = _mi(quad, mat)
		r.name = "Lock"
		add_child(r)
		_parts["Lock"] = r
	var a2: float = minf(1.0, r.get_meta("a", 0.0) + dt * 6.0) if r.visible else 0.2
	r.set_meta("a", a2)
	r.visible = true
	r.position = Vector3(0.0, 3.75, 0.0)
	var pulse := 1.0 + sin(time * 12.0) * 0.1
	r.scale = Vector3.ONE * 1.5 * pulse * (1.6 - 0.6 * a2)
	(_mats["lock"] as ShaderMaterial).set_shader_parameter("amount", a2)
