class_name Effects
extends Node3D
## 粒子特效：三个 GPUParticles3D 池（烟尘 / 普通混合 / 叠加发光），emitting = false，
## 全部用 emit_particle() 在任意位置发射单个粒子。每个粒子的寿命、尺寸变化、重力、阻尼、颜色渐变、
## 形状（柔光点 / 烟团 / 星星 / 火花 / 圆环 …）与朝向模式（公告板 / 沿速度拉伸 / 翻滚 / 贴地 / 光柱）
## 都编码进发射参数，由 fx_particles.gdshader 解码（见该文件开头的约定）；这样三次绘制就能画出全部特效。
## 另有少量点光源用于爆炸、雷暴的闪光。

# —— 形状（与 fx_sprite.gdshaderinc 对应） ——
const SOFT := 0
const PUFF := 1
const STAR := 2
const STREAK := 3
const RING := 4
const DROP := 5
const SHARD := 6
const CONFETTI := 7
const FLARE := 8
const FIRE := 9
const BOLT := 10
const BEAM := 11
const LINE := 12
const DEBRIS := 13
const PETAL := 14
const GLINT := 15
# —— 朝向模式（形状码 = 形状 + 模式） ——
const M_BILL := 0
const M_STRETCH := 16
const M_TUMBLE := 32
const M_FLAT := 48
const M_BEAM := 64

const NO_FLOOR := -99.0
const EMIT_FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE \
		| GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM
const PROCESS_SHADER := preload("res://assets/shaders/fx_particles.gdshader")
const MIX_SHADER := preload("res://assets/shaders/fx_sprite_mix.gdshader")
const ADD_SHADER := preload("res://assets/shaders/fx_sprite_add.gdshader")
## 池容量（「高」画质；按画质的 particles 系数缩放）
const SMOKE_CAP := 2400
const MIX_CAP := 2400
const ADD_CAP := 3200
const MAX_LIFE := 4.0

const CONFETTI_COLORS: Array[Color] = [
	Color("#FF4D5E"), Color("#FFC93C"), Color("#3EC6FF"), Color("#45E3A6"),
	Color("#FF7FD1"), Color("#9B6BFF"), Color("#FFFFFF"),
]

var skids: SkidMarks
## 画质粒子系数（low 0.5 / medium 0.8 / high 1.0）
var density := 1.0
var _rate_acc := {}
var _smoke: GPUParticles3D
var _mix: GPUParticles3D
var _add: GPUParticles3D
var _night := false
var _smoke_c0 := Color(0.95, 0.96, 0.98, 0.5)
var _smoke_c1 := Color(0.76, 0.79, 0.86)
var _dust_c := Color("#D8C49A")
var _lights: Array[OmniLight3D] = []
var _light_t: Array[float] = []
var _light_dur: Array[float] = []
var _light_e: Array[float] = []
var _generation := 0.0
var _clock := 0.0
## 最近的尾焰发射点（xyz + 时刻），用来在同一排气口两次发射之间补点
var _flame_recent: Array[Vector4] = []


func setup(quality: String, theme: Dictionary) -> void:
	name = "Effects"
	density = float(EnvironmentFactory.quality_preset(quality)["particles"])
	skids = SkidMarks.new()
	skids.name = "SkidMarks"
	add_child(skids)
	var tid: String = theme.get("id", "village")
	_night = theme.get("night", false)
	skids.configure(tid, _night)

	# 主题配色：冰雪的漂移烟是雪粉，夜城的烟压暗（粒子不受光照）
	match tid:
		"snow":
			_smoke_c0 = Color(0.97, 0.99, 1.0, 0.62)
			_smoke_c1 = Color(0.84, 0.91, 1.0)
		"desert":
			_smoke_c0 = Color(0.98, 0.95, 0.88, 0.5)
			_smoke_c1 = Color(0.86, 0.78, 0.64)
		"city":
			_smoke_c0 = Color(0.4, 0.42, 0.58, 0.3)
			_smoke_c1 = Color(0.24, 0.25, 0.38)
		_:
			_smoke_c0 = Color(0.95, 0.96, 0.98, 0.5)
			_smoke_c1 = Color(0.76, 0.79, 0.86)
	if tid == "snow":
		_dust_c = Color(0.95, 0.97, 1.0)
	else:
		# 路肩色混一点土黄，草地上扬起的也是泥土
		_dust_c = Color(theme.get("shoulder", "#D8C49A")).lerp(Color("#C9A677"), 0.6)
		if _night:
			_dust_c = _dust_c.lightened(0.15)

	_smoke = _make_pool("Smoke", SMOKE_CAP, MIX_SHADER, 0)
	_mix = _make_pool("Mix", MIX_CAP, MIX_SHADER, 0)
	_add = _make_pool("Glow", ADD_CAP, ADD_SHADER, 1)
	# 每个池先发一个全透明粒子，让绘制管线在比赛开始前就编译好
	for p: GPUParticles3D in [_smoke, _mix, _add]:
		_emit(p, Vector3.ZERO, Vector3.ZERO, 0.5, 0.01, 0.01, Color(0, 0, 0, 0), Color(0, 0, 0), 0.0, 0.0, 0.0, SOFT)

	for i in 4:
		var l := OmniLight3D.new()
		l.name = "Flash%d" % i
		l.visible = false
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		add_child(l)
		_lights.append(l)
		_light_t.append(0.0)
		_light_dur.append(1.0)
		_light_e.append(0.0)


## 清除所有粒子、胎痕与闪光（重开比赛 / 回放跳转时用）
func clear() -> void:
	_generation += 1.0
	for p: GPUParticles3D in [_smoke, _mix, _add]:
		(p.process_material as ShaderMaterial).set_shader_parameter("generation", _generation)
	skids.clear()
	for i in _lights.size():
		_lights[i].visible = false
		_light_t[i] = 0.0


## 注意：不用 DRAW_ORDER_VIEW_DEPTH——粒子着色器用到 USERDATA 时，Godot 4.7 的视深排序路径会把粒子数据读乱
## （出现大片破碎三角形），所以一律按发射顺序绘制。
func _make_pool(pool_name: String, cap: int, draw_shader: Shader, priority: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = pool_name
	p.emitting = false
	p.amount = maxi(64, int(cap * density))
	p.lifetime = MAX_LIFE
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.fixed_fps = 0
	p.interpolate = false
	p.fract_delta = false
	p.visibility_aabb = AABB(Vector3(-6000, -1000, -6000), Vector3(12000, 3000, 12000))
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var pm := ShaderMaterial.new()
	pm.shader = PROCESS_SHADER
	p.process_material = pm
	var dm := ShaderMaterial.new()
	dm.shader = draw_shader
	dm.render_priority = priority
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = dm
	p.draw_pass_1 = quad
	add_child(p)
	return p


## 发射单个粒子。c0 / c1：起止颜色（c0.a 为最大不透明度）；fade >= 0 为淡入比例，< 0 为保持到 1 + fade 再淡出
func _emit(pool: GPUParticles3D, pos: Vector3, vel: Vector3, life: float, s0: float, s1: float,
		c0: Color, c1: Color, grav: float, drag: float, spin: float, code: int,
		stretch := 0.0, floor_off := NO_FLOOR, fade := 0.12) -> void:
	var b := Basis(Vector3(life, s0, s1), Vector3(grav, drag, spin), Vector3(float(code), stretch, floor_off))
	pool.emit_particle(Transform3D(b, pos), vel, c0, Color(c1.r, c1.g, c1.b, fade), EMIT_FLAGS)


func _n(c: float) -> int:
	return maxi(1, roundi(c * density))


static func _rand_dir() -> Vector3:
	var z := randf_range(-1.0, 1.0)
	var a := randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


static func _rand_h() -> Vector3:
	var a := randf() * TAU
	return Vector3(cos(a), 0.0, sin(a))


static func _up_dir(min_y: float) -> Vector3:
	var d := _rand_dir()
	d.y = absf(d.y) * (1.0 - min_y) + min_y
	return d.normalized()


static func _hdr(c: Color, k: float, a := 1.0) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, a)


func _process(dt: float) -> void:
	_clock += dt
	for i in _lights.size():
		if _light_t[i] <= 0.0:
			continue
		_light_t[i] -= dt
		var l := _lights[i]
		if _light_t[i] <= 0.0:
			l.visible = false
			continue
		var u := _light_t[i] / _light_dur[i]
		l.light_energy = _light_e[i] * u * u


## 点光源闪光（爆炸、雷暴）：取剩余时间最短的一盏复用
func _flash(pos: Vector3, color: Color, energy: float, light_range: float, dur: float) -> void:
	if _lights.is_empty():
		return
	var best := 0
	for i in _lights.size():
		if _light_t[i] < _light_t[best]:
			best = i
	var l := _lights[best]
	l.global_position = pos
	l.light_color = color
	l.omni_range = light_range
	l.light_energy = energy
	l.visible = true
	_light_t[best] = dur
	_light_dur[best] = dur
	_light_e[best] = energy * (1.6 if _night else 1.0)


## kind: boost wall kart land shards explosion splash banana shield thunder respawn confetti instant spark_hit
## opts: strength（0..1）、count
func burst(kind: String, pos: Vector3, opts := {}) -> void:
	var st := clampf(float(opts.get("strength", 1.0)), 0.0, 1.0)
	match kind:
		"boost":
			_burst_boost(pos, 1.0)
		"instant":
			_burst_boost(pos, 0.6)
		"wall":
			_burst_wall(pos, st)
		"kart":
			_burst_kart(pos)
		"land":
			_burst_land(pos, st)
		"shards":
			_burst_shards(pos)
		"explosion":
			_burst_explosion(pos)
		"splash":
			_burst_splash(pos)
		"banana":
			_burst_banana(pos)
		"shield":
			_burst_shield(pos)
		"thunder":
			_burst_thunder(pos)
		"respawn":
			_burst_respawn(pos)
		"confetti":
			_burst_confetti(pos, int(opts.get("count", 90)))
		"spark_hit":
			var c := pos + Vector3(0.0, 0.5, 0.0)
			_glow(c, _hdr(Color(1.0, 0.82, 0.5), 2.4), 2.0, 0.6, 0.12)
			_sparks(c, _n(12 + 12 * st), 6.0, 14.0, _hdr(Color(1.0, 0.86, 0.4), 2.6), Color(1.0, 0.35, 0.08), 0.1, -0.45)
			_ring(c, _hdr(Color(1.0, 0.8, 0.4), 1.4), 0.4, 2.4, 0.2)


# —————————————————— 持续特效 ——————————————————

## 漂移轮胎烟：vel 为车速，烟带一点车速后迅速减速、向后散开并缓缓上升；big 为大小倍数（冰面 1.2）
func smoke(pos: Vector3, vel: Vector3, big := 1.0) -> void:
	var r := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var v := vel * 0.16 + r * 1.3 + Vector3(0.0, randf_range(0.7, 1.7), 0.0)
	var c0 := _smoke_c0
	c0.a *= randf_range(0.8, 1.0)
	_emit(_smoke, pos + Vector3(0.0, 0.18, 0.0) + r * 0.12, v, randf_range(0.55, 0.9),
		0.55 * big, randf_range(1.6, 2.3) * big, c0, _smoke_c1, -0.6, 2.4, randf_range(-1.5, 1.5), PUFF, 0.0, NO_FLOOR, 0.1)


## 漂移火花：tier 0 白黄 / 1 蓝（可以小喷）
func drift_spark(pos: Vector3, tier: int) -> void:
	var blue := tier >= 1
	var c0 := _hdr(Color(0.3, 0.66, 1.0), 1.7) if blue else _hdr(Color(1.0, 0.86, 0.4), 1.8)
	var c1 := Color(0.12, 0.3, 1.0) if blue else Color(1.0, 0.42, 0.08)
	for i in 2:
		var v := Vector3(randf_range(-3.5, 3.5), randf_range(2.5, 6.5), randf_range(-3.5, 3.5))
		_emit(_mix, pos, v, randf_range(0.2, 0.34), 0.11 if blue else 0.09, 0.04, c0, c1, 16.0, 1.5, 0.0,
			STREAK + M_STRETCH, 0.07, -0.12, 0.0)
	# 轮边的亮点（每次都发一个短命光点，连起来像一团持续的火花）
	_emit(_add, pos + Vector3(0.0, 0.05, 0.0), Vector3.ZERO, 0.06, 0.95 if blue else 0.7, 0.4, _hdr(c0, 0.55, 0.9), c1,
		0.0, 0.0, 0.0, SOFT, 0.0, NO_FLOOR, 0.0)
	if blue and randf() < 0.5:
		_emit(_mix, pos + Vector3(0.0, 0.1, 0.0), Vector3(0.0, 1.0, 0.0), 0.12, 0.5, 0.1, _hdr(Color(0.45, 0.78, 1.0), 1.8), c1,
			0.0, 0.0, randf_range(-6.0, 6.0), FLARE, 0.0, NO_FLOOR, 0.0)


## 尾焰粒子：dir 为车尾方向。nitro / start / instant 蓝白，pad 橙，draft 淡紫，magnet 粉
## 每个粒子是从排气口向后伸出的一段柔光条，前后相连成一条连续的火舌
func flame(pos: Vector3, dir: Vector3, kind: String) -> void:
	var c0: Color
	var c1: Color
	var size := 0.5
	match kind:
		"nitro", "start":
			c0 = _hdr(Color(0.4, 0.75, 1.0), 2.2)
			c1 = Color(0.15, 0.25, 1.0)
			size = 0.6
		"instant":
			c0 = _hdr(Color(0.6, 0.88, 1.0), 2.4)
			c1 = Color(0.25, 0.4, 1.0)
			size = 0.45
		"pad":
			c0 = _hdr(Color(1.0, 0.72, 0.3), 2.6)
			c1 = Color(1.0, 0.2, 0.06)
		"draft":
			c0 = _hdr(Color(0.86, 0.74, 1.0), 2.0)
			c1 = Color(0.55, 0.35, 1.0)
			size = 0.4
		"magnet":
			c0 = _hdr(Color(1.0, 0.62, 0.88), 2.4)
			c1 = Color(1.0, 0.25, 0.62)
			size = 0.45
		_:
			c0 = _hdr(Color(1.0, 0.72, 0.3), 2.6)
			c1 = Color(1.0, 0.2, 0.06)
	# 高速时两次发射之间车已前进 1 m 以上：沿上一次发射点补点，火舌才连贯
	var prev := _flame_prev(pos, dir)
	var gap := prev.distance_to(pos)
	var fills := clampi(int(gap / 0.45), 0, 5)
	for k in fills + 1:
		var p := prev.lerp(pos, float(k + 1) / (fills + 1))
		var j := _rand_dir()
		var v := dir * randf_range(5.0, 7.5) + j * 0.5 + Vector3(0.0, 0.3, 0.0)
		_emit(_add, p + j * 0.04, v, randf_range(0.12, 0.2), size * randf_range(0.85, 1.1), size * 0.2, c0, c1,
			0.0, 2.0, 0.0, SOFT + M_STRETCH, -0.14, NO_FLOOR, 0.0)
	var v0 := dir * 6.0
	# 白热内核
	if kind in ["nitro", "start", "pad"] and randf() < 0.7:
		_emit(_add, pos, v0 * 0.9, 0.08, size * 0.45, 0.1, _hdr(Color(0.95, 0.98, 1.0), 2.6), c1,
			0.0, 2.0, 0.0, SOFT + M_STRETCH, -0.1, NO_FLOOR, 0.0)


## 找同一排气口上一次的发射点：在尾焰反方向（车头方向）上、横向偏差最小的近期发射点
func _flame_prev(pos: Vector3, dir: Vector3) -> Vector3:
	for i in range(_flame_recent.size() - 1, -1, -1):
		if _clock - _flame_recent[i].w > 0.08:
			_flame_recent.remove_at(i)
	var best := -1
	var best_lat := 0.3
	for i in _flame_recent.size():
		var e := _flame_recent[i]
		var d := pos - Vector3(e.x, e.y, e.z)
		var along := -d.dot(dir)
		if along < 0.05 or along > 4.0:
			continue
		var lat := (d + dir * along).length()
		if lat < best_lat:
			best_lat = lat
			best = i
	var prev := pos
	if best >= 0:
		var b := _flame_recent[best]
		prev = Vector3(b.x, b.y, b.z)
		_flame_recent.remove_at(best)
	_flame_recent.append(Vector4(pos.x, pos.y, pos.z, _clock))
	return prev


## 越野尘土
func dust(pos: Vector3, vel: Vector3) -> void:
	var r := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var v := vel * 0.12 + r * 1.6 + Vector3(0.0, randf_range(0.7, 1.6), 0.0)
	_emit(_smoke, pos + Vector3(0.0, 0.2, 0.0), v, randf_range(0.65, 1.0), 0.9, randf_range(2.8, 3.5), Color(_dust_c, 0.72),
		_dust_c.darkened(0.12), -0.3, 2.0, randf_range(-1.2, 1.2), PUFF, 0.0, NO_FLOOR, 0.1)
	# 甩起的土块
	var d := _up_dir(0.5)
	_emit(_mix, pos + Vector3(0.0, 0.15, 0.0), vel * 0.3 + d * randf_range(2.0, 4.5), randf_range(0.4, 0.6), randf_range(0.1, 0.16), 0.08,
		_dust_c.darkened(0.35), _dust_c.darkened(0.45), 18.0, 0.5, randf_range(6.0, 12.0), DEBRIS + M_TUMBLE, 0.0, -0.1, -0.3)


## 尾流风线：细长半透明白线，绕开车身，沿 dir 前进但比车慢（看起来快速后掠）
func wind(pos: Vector3, dir: Vector3) -> void:
	var side := Vector3(dir.z, 0.0, -dir.x).normalized()
	for i in 2:
		var off := randf_range(0.8, 1.9) * (1.0 if randf() < 0.5 else -1.0)
		var p := pos + side * off + Vector3(0.0, randf_range(-0.55, 1.0), 0.0) + dir * randf_range(-0.5, 1.5)
		var v := dir * randf_range(12.0, 18.0)
		_emit(_mix, p, v, randf_range(0.3, 0.42), 0.055, 0.035, Color(1.0, 1.0, 1.0, 0.75), Color(0.85, 0.8, 1.0),
			0.0, 0.0, 0.0, LINE + M_STRETCH, 0.2, NO_FLOOR, 0.25)


## 按速率（个/秒）计算本帧应发射的粒子数（带小数累积，按画质系数缩放）
func rate_count(key: String, rate: float, dt: float) -> int:
	var acc: float = _rate_acc.get(key, 0.0) + rate * dt * density
	var c := int(acc)
	_rate_acc[key] = acc - c
	return c


# —————————————————— 道具表现用的小工具（ItemView 调用） ——————————————————

## 导弹尾迹：一段橙色火舌 + 一团灰烟。back 为导弹尾部朝向（单位向量）
func missile_trail(pos: Vector3, back: Vector3) -> void:
	_emit(_add, pos, back * 5.0, 0.1, 0.4, 0.12, _hdr(Color(1.0, 0.75, 0.35), 2.6), Color(1.0, 0.3, 0.1),
		0.0, 2.0, 0.0, SOFT + M_STRETCH, -0.1, NO_FLOOR, 0.0)
	var r := _rand_dir()
	var c0 := Color(0.92, 0.92, 0.95, 0.6) if not _night else Color(0.45, 0.46, 0.58, 0.5)
	_emit(_smoke, pos + r * 0.1, r * 0.5 + back * 1.5 + Vector3(0.0, 0.4, 0.0), randf_range(0.6, 0.9), 0.4, randf_range(1.2, 1.6),
		c0, c0.darkened(0.2), -0.3, 2.2, randf_range(-1.0, 1.0), PUFF, 0.0, NO_FLOOR, 0.06)


## 水滴（水炸弹 / 水苍蝇尾迹、水柱周围的溅射）
func water_drop(pos: Vector3, vel: Vector3, size := 0.14) -> void:
	_emit(_mix, pos, vel, randf_range(0.45, 0.7), size, size * 0.6, Color(0.66, 0.9, 1.0, 0.92), Color(0.3, 0.6, 1.0),
		22.0, 0.3, 0.0, DROP + M_STRETCH, 0.035, -1.2, 0.05)


## 闪光点（十字星，叠加发光）
func sparkle(pos: Vector3, color: Color, size := 0.5, life := 0.4) -> void:
	_emit(_add, pos, Vector3(0.0, 0.6, 0.0), life, size, 0.05, _hdr(color, 2.2), color, 0.0, 1.0, randf_range(-3.0, 3.0), FLARE, 0.0, NO_FLOOR, 0.1)


# —————————————————— 爆发用的小工具 ——————————————————

## 冲击环（普通混合，内白外彩，越扩越细）；flat = 贴地水平
func _ring(pos: Vector3, color: Color, s0: float, s1: float, life: float, flat := false, alpha := 0.95) -> void:
	_emit(_mix, pos, Vector3.ZERO, life, s0, s1, Color(color, alpha), color, 0.0, 0.0, 0.0,
		RING + (M_FLAT if flat else M_BILL), 0.0, NO_FLOOR, 0.0)


## 叠加柔光（闪光）
func _glow(pos: Vector3, color: Color, s0: float, s1: float, life: float) -> void:
	_emit(_add, pos, Vector3.ZERO, life, s0, s1, color, color, 0.0, 0.0, 0.0, SOFT, 0.0, NO_FLOOR, 0.0)


## 放射火花：沿速度拉伸的亮线（普通混合 + HDR 颜色，亮背景上也清楚，同时触发辉光）
func _sparks(pos: Vector3, count: int, v_min: float, v_max: float, c0: Color, c1: Color, width: float, floor_off: float,
		up_bias := 0.25, life_min := 0.25, life_max := 0.55) -> void:
	for i in count:
		var d := _rand_dir()
		d.y = absf(d.y) * (1.0 - up_bias) + up_bias
		_emit(_mix, pos, d.normalized() * randf_range(v_min, v_max), randf_range(life_min, life_max), width, width * 0.45,
			c0, c1, 18.0, 1.2, 0.0, STREAK + M_STRETCH, 0.035, floor_off, 0.0)


## 十字闪光（普通混合）
func _flares(center: Vector3, count: int, radius: float, color: Color, size: float, speed: float) -> void:
	for i in count:
		var d := _rand_dir()
		_emit(_mix, center + d * radius, d * speed + Vector3(0.0, 0.8, 0.0), randf_range(0.4, 0.7), size * randf_range(0.8, 1.2), 0.05,
			color, color, 0.0, 2.0, randf_range(-3.0, 3.0), FLARE, 0.0, NO_FLOOR, 0.08)


# —————————————————— 各类爆发 ——————————————————

func _burst_boost(pos: Vector3, k: float) -> void:
	var c := pos + Vector3(0.0, 0.8, 0.0)
	_glow(c, _hdr(Color(0.7, 0.92, 1.0), 2.4, 0.9), 3.6 * k, 1.2, 0.18)
	_ring(c, _hdr(Color(0.3, 0.72, 1.0), 1.7), 1.0 * k, 6.5 * k, 0.36)
	_ring(pos + Vector3(0.0, 0.12, 0.0), _hdr(Color(0.35, 0.75, 1.0), 1.5), 1.2, 8.5 * k, 0.45, true, 0.85)
	for i in _n(18 * k):
		var d := _rand_h()
		var v := d * randf_range(8.0, 15.0) * (0.6 + 0.4 * k) + Vector3(0.0, randf_range(1.0, 5.0), 0.0)
		_emit(_mix, c + d * 0.4, v, randf_range(0.3, 0.5), 0.1, 0.04, _hdr(Color(0.6, 0.9, 1.0), 2.6), Color(0.2, 0.45, 1.0),
			9.0, 1.6, 0.0, STREAK + M_STRETCH, 0.045, -0.75, 0.0)
	_flares(c, _n(6 * k), 1.2, _hdr(Color(0.75, 0.93, 1.0), 2.2), 0.7, 1.5)


func _burst_wall(pos: Vector3, st: float) -> void:
	var c := pos + Vector3(0.0, 0.5, 0.0)
	var k := 0.5 + 0.5 * st
	_glow(c, _hdr(Color(1.0, 0.8, 0.45), 2.4), 2.8 * k, 0.8, 0.12)
	_ring(c, _hdr(Color(1.0, 0.75, 0.35), 1.5), 0.4, 3.0 * k, 0.2)
	_sparks(c, _n(10 + 24 * st), 6.0 * k, 15.0 * k, _hdr(Color(1.0, 0.86, 0.4), 2.6), Color(1.0, 0.35, 0.08), 0.1, -0.45)
	for i in _n(3 + 6 * st):
		var d := _up_dir(0.3)
		var gray := randf_range(0.35, 0.6)
		_emit(_mix, c, d * randf_range(3.0, 7.5), randf_range(0.6, 0.9), randf_range(0.18, 0.3), 0.16, Color(gray, gray * 0.95, gray * 0.9), Color(gray, gray, gray),
			20.0, 0.8, randf_range(8.0, 16.0), DEBRIS + M_TUMBLE, 0.0, -0.45, -0.3)
	for i in _n(2 + 3 * st):
		smoke(pos, Vector3.ZERO, 0.9 + st * 0.5)


func _burst_kart(pos: Vector3) -> void:
	var c := pos + Vector3(0.0, 0.9, 0.0)
	var gold := Color("#FFE14A")
	for i in _n(8):
		var d := _rand_h()
		var v := d * randf_range(3.0, 6.0) + Vector3(0.0, randf_range(4.0, 7.5), 0.0)
		_emit(_mix, c + d * 0.3, v, randf_range(0.7, 0.9), randf_range(0.7, 0.85), 0.45, _hdr(gold, 1.4), Color("#FFB020"),
			12.0, 1.4, randf_range(-9.0, 9.0), STAR, 0.0, NO_FLOOR, -0.35)
	_glow(c, _hdr(Color(1.0, 0.97, 0.8), 2.4), 2.8, 1.0, 0.12)
	_ring(c, _hdr(Color(1.0, 0.85, 0.35), 1.5), 0.5, 3.6, 0.26)
	_sparks(c, _n(10), 4.0, 10.0, _hdr(Color(1.0, 0.97, 0.8), 2.4), gold, 0.08, -0.85)


func _burst_land(pos: Vector3, st: float) -> void:
	var cnt := _n(10 + 14 * st)
	for i in cnt:
		var a := float(i) / cnt * TAU + randf() * 0.3
		var d := Vector3(cos(a), 0.0, sin(a))
		_emit(_smoke, pos + d * 0.9 + Vector3(0.0, 0.15, 0.0), d * randf_range(3.0, 4.0 + 4.0 * st) + Vector3(0.0, 0.5, 0.0),
			randf_range(0.5, 0.8), 0.9, 2.2 + 1.4 * st, Color(_dust_c, 0.62), _dust_c.darkened(0.1), -0.2, 3.0,
			randf_range(-1.0, 1.0), PUFF, 0.0, NO_FLOOR, 0.1)
	if st > 0.4:
		_ring(pos + Vector3(0.0, 0.08, 0.0), _dust_c.lightened(0.2), 1.0, 6.0 + 3.0 * st, 0.45, true, 0.5)


func _burst_shards(pos: Vector3) -> void:
	var cnt := _n(30)
	for i in cnt:
		var col := Color.from_hsv(float(i) / cnt + randf() * 0.05, 0.62, 1.0)
		var d := _rand_dir()
		d.y = d.y * 0.6 + 0.4
		_emit(_mix, pos + d * 0.4, d * randf_range(6.0, 11.0), randf_range(0.7, 1.05), randf_range(0.42, 0.58), 0.25,
			_hdr(col, 1.5), col, 16.0, 0.9, randf_range(8.0, 18.0), SHARD + M_TUMBLE, 0.0, -1.25, -0.3)
	for i in _n(12):
		var d2 := _rand_dir()
		_emit(_mix, pos + d2 * 0.5, d2 * randf_range(2.0, 5.0), randf_range(0.35, 0.6), 0.75, 0.05,
			_hdr(Color.from_hsv(randf(), 0.3, 1.0), 2.2), Color(1, 1, 1), 0.0, 2.0, randf_range(-4.0, 4.0), FLARE, 0.0, NO_FLOOR, 0.05)
	_glow(pos, _hdr(Color(1, 1, 1), 2.0, 0.9), 3.8, 1.2, 0.16)
	_ring(pos, _hdr(Color(0.8, 0.9, 1.0), 1.4), 1.0, 3.4, 0.3)


func _burst_explosion(pos: Vector3) -> void:
	var ground := -0.95
	_glow(pos, _hdr(Color(1.0, 0.85, 0.55), 1.8), 5.0, 2.5, 0.1)
	_emit(_mix, pos, Vector3.ZERO, 0.12, 5.5, 7.0, _hdr(Color(1.0, 0.95, 0.75), 2.0), Color(1.0, 0.6, 0.2), 0.0, 0.0, randf() * 3.0, FLARE, 0.0, NO_FLOOR, 0.0)
	# 火球：普通混合的卡通火团，中心黄白、边缘橙红，迅速膨胀后暗下去
	for i in _n(14):
		var d := _rand_dir()
		d.y = absf(d.y) * 0.8 + 0.2
		_emit(_mix, pos + d * randf_range(0.2, 1.2), d * randf_range(2.5, 7.0) + Vector3(0.0, 2.5, 0.0), randf_range(0.5, 0.8),
			randf_range(1.8, 2.4), randf_range(4.0, 5.2), _hdr(Color(1.0, 0.5, 0.1), 1.3), Color(0.45, 0.06, 0.03),
			-3.0, 3.2, randf_range(-2.0, 2.0), FIRE, 0.0, NO_FLOOR, 0.02)
	for i in _n(3):
		_emit(_add, pos + _rand_dir() * 0.5, Vector3(0.0, 2.0, 0.0), 0.22, randf_range(2.0, 2.6), 1.0,
			_hdr(Color(1.0, 0.75, 0.3), 1.2), Color(1.0, 0.3, 0.05), -2.0, 2.0, randf_range(-2.0, 2.0), FIRE, 0.0, NO_FLOOR, 0.0)
	# 黑烟（火球消退时浮现）
	for i in _n(16):
		var d := _rand_dir()
		d.y = absf(d.y)
		_emit(_smoke, pos + d * randf_range(0.3, 1.3), d * randf_range(1.5, 4.0) + Vector3(0.0, randf_range(2.0, 5.0), 0.0),
			randf_range(1.4, 2.1), randf_range(1.6, 2.1), randf_range(4.8, 6.0), Color(0.16, 0.15, 0.18, 0.9), Color(0.38, 0.38, 0.43),
			-1.4, 1.8, randf_range(-1.0, 1.0), PUFF, 0.0, NO_FLOOR, 0.35)
	# 火花与碎屑
	_sparks(pos, _n(34), 12.0, 26.0, _hdr(Color(1.0, 0.84, 0.42), 2.6), Color(1.0, 0.3, 0.05), 0.12, ground, 0.15, 0.45, 0.9)
	for i in _n(12):
		var d := _up_dir(0.35)
		var g := randf_range(0.12, 0.28)
		_emit(_mix, pos, d * randf_range(6.0, 12.0), randf_range(1.0, 1.4), randf_range(0.24, 0.4), 0.22, Color(g, g, g * 1.1), Color(g, g, g),
			22.0, 0.6, randf_range(8.0, 16.0), DEBRIS + M_TUMBLE, 0.0, ground, -0.2)
	# 冲击波：贴地环 + 面向相机的环
	_ring(pos + Vector3(0.0, ground + 0.12, 0.0), _hdr(Color(1.0, 0.72, 0.4), 1.5), 2.0, 17.0, 0.5, true, 0.9)
	_ring(pos, _hdr(Color(1.0, 0.8, 0.5), 1.4), 1.5, 8.5, 0.3)
	_flash(pos + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.62, 0.3), 12.0, 18.0, 0.45)


func _burst_splash(pos: Vector3) -> void:
	var c := pos + Vector3(0.0, 0.4, 0.0)
	for i in _n(46):
		var d := _rand_h()
		var v := d * randf_range(2.0, 7.5) + Vector3(0.0, randf_range(6.0, 14.0), 0.0)
		_emit(_mix, c + d * randf_range(0.2, 1.2), v, randf_range(0.8, 1.25), randf_range(0.2, 0.28), 0.12,
			Color(0.42, 0.76, 1.0, 0.95), Color(0.18, 0.48, 1.0), 22.0, 0.35, 0.0, DROP + M_STRETCH, 0.03, -0.35, 0.03)
	for i in _n(12):
		var d := _rand_h()
		_emit(_mix, c + d * 0.4, Vector3(0.0, randf_range(15.0, 21.0), 0.0) + d * 1.8, randf_range(0.6, 0.9), 0.36, 0.22,
			Color(0.62, 0.87, 1.0, 0.92), Color(0.3, 0.6, 1.0), 26.0, 0.5, 0.0, DROP + M_STRETCH, 0.05, -0.35, 0.03)
	for i in _n(12):
		var d := _rand_h()
		_emit(_smoke, c + d * 0.8, d * randf_range(2.5, 5.0) + Vector3(0.0, randf_range(1.0, 3.0), 0.0), randf_range(0.6, 0.9),
			1.2, 3.6, Color(0.6, 0.83, 1.0, 0.6), Color(0.45, 0.7, 1.0), -0.5, 2.5, randf_range(-1.0, 1.0), PUFF, 0.0, NO_FLOOR, 0.1)
	_ring(pos + Vector3(0.0, 0.08, 0.0), _hdr(Color(0.35, 0.7, 1.0), 1.3), 1.2, 10.0, 0.65, true, 0.9)


func _burst_banana(pos: Vector3) -> void:
	var c := pos + Vector3(0.0, 0.3, 0.0)
	var yellow := Color("#FFD84A")
	for i in _n(12):
		var d := _rand_h()
		_emit(_mix, c, d * randf_range(2.0, 5.0) + Vector3(0.0, randf_range(4.0, 8.0), 0.0), randf_range(0.7, 0.95), randf_range(0.45, 0.6), 0.35,
			_hdr(yellow, 1.25), Color("#E0A020"), 18.0, 0.8, randf_range(8.0, 14.0), PETAL + M_TUMBLE, 0.0, -0.27, -0.25)
	for i in _n(5):
		var d := _rand_h()
		_emit(_mix, c + Vector3(0.0, 0.5, 0.0), d * randf_range(2.0, 3.5) + Vector3(0.0, 5.0, 0.0), 0.65, 0.6, 0.35, _hdr(yellow, 1.4), Color("#FFB020"),
			10.0, 1.5, randf_range(-8.0, 8.0), STAR, 0.0, NO_FLOOR, -0.35)
	_glow(c, _hdr(Color(1.0, 0.95, 0.6), 2.0), 2.2, 0.6, 0.14)
	_ring(c, _hdr(Color(1.0, 0.88, 0.3), 1.4), 0.4, 3.2, 0.25)


func _burst_shield(pos: Vector3) -> void:
	var c := pos + Vector3(0.0, 1.0, 0.0)
	var gold := Color(1.0, 0.84, 0.3)
	_glow(c, _hdr(Color(1.0, 0.95, 0.75), 2.0, 0.85), 3.4, 1.2, 0.18)
	_ring(c, _hdr(gold, 1.7), 1.6, 7.0, 0.45)
	_ring(pos + Vector3(0.0, 0.1, 0.0), _hdr(gold, 1.5), 1.2, 8.0, 0.55, true, 0.85)
	_flares(c, _n(18), 1.7, _hdr(Color(1.0, 0.9, 0.5), 2.4), 0.7, 2.2)


func _burst_thunder(pos: Vector3) -> void:
	var c := pos + Vector3(0.0, 1.2, 0.0)
	var bolt_c := _hdr(Color(0.85, 0.9, 1.0), 3.0)
	# 从天而降的闪电（两道交错）
	for i in 2:
		var off := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		var w := 1.4 - i * 0.45
		_emit(_add, pos + off, Vector3.ZERO, 0.3, w, w, bolt_c, Color(0.6, 0.7, 1.0), 0.0, 0.0, 0.0,
			BOLT + M_BEAM, 16.0 / w, NO_FLOOR, 0.0)
	_glow(c, _hdr(Color(0.95, 0.97, 1.0), 2.6), 8.0, 3.0, 0.22)
	# 电火花
	for i in _n(16):
		var d := _rand_dir()
		_emit(_add, c + d * 0.3, d * randf_range(5.0, 11.0), randf_range(0.18, 0.32), 0.26, 0.14, bolt_c, Color(1.0, 0.9, 0.4),
			0.0, 3.0, 0.0, BOLT + M_STRETCH, 0.07, NO_FLOOR, 0.0)
	_sparks(c, _n(14), 5.0, 12.0, _hdr(Color(1.0, 0.95, 0.6), 2.6), Color(1.0, 0.8, 0.2), 0.08, -1.1)
	_ring(pos + Vector3(0.0, 0.1, 0.0), _hdr(Color(0.8, 0.88, 1.0), 1.5), 1.0, 8.5, 0.4, true, 0.9)
	_flash(c + Vector3(0.0, 1.5, 0.0), Color(0.75, 0.82, 1.0), 10.0, 16.0, 0.3)


func _burst_respawn(pos: Vector3) -> void:
	var cyan := Color(0.62, 0.92, 1.0)
	_emit(_add, pos, Vector3.ZERO, 0.95, 2.8, 1.6, _hdr(cyan, 1.4, 0.85), Color(0.4, 0.7, 1.0), 0.0, 0.0, 0.0,
		BEAM + M_BEAM, 6.0, NO_FLOOR, 0.08)
	_emit(_add, pos, Vector3.ZERO, 0.8, 1.0, 0.5, _hdr(Color(0.9, 0.98, 1.0), 2.0, 0.9), cyan, 0.0, 0.0, 0.0,
		BEAM + M_BEAM, 16.0, NO_FLOOR, 0.05)
	for i in _n(18):
		var p := pos + _rand_h() * randf_range(0.2, 1.3) + Vector3(0.0, randf_range(1.5, 9.0), 0.0)
		_emit(_mix, p, Vector3(0.0, -randf_range(2.0, 6.0), 0.0), randf_range(0.5, 0.9), randf_range(0.45, 0.65), 0.05,
			_hdr(Color(0.8, 0.96, 1.0), 2.2), cyan, 0.0, 0.5, randf_range(-3.0, 3.0), FLARE, 0.0, NO_FLOOR, 0.1)
	_ring(pos + Vector3(0.0, 0.08 - 0.5, 0.0), _hdr(cyan, 1.5), 1.0, 6.0, 0.6, true, 0.9)


func _burst_confetti(pos: Vector3, count: int) -> void:
	for i in _n(count):
		var col: Color = CONFETTI_COLORS[i % CONFETTI_COLORS.size()]
		var h := randf_range(3.0, 6.0)
		var p := pos + _rand_h() * randf_range(0.0, 3.5) + Vector3(0.0, h, 0.0)
		var v := _rand_h() * randf_range(1.0, 5.0) + Vector3(0.0, randf_range(4.0, 11.0), 0.0)
		_emit(_mix, p, v, randf_range(2.6, 3.7), randf_range(0.3, 0.4), 0.3, _hdr(col, 1.15), col,
			7.0, 1.7, randf_range(6.0, 14.0), CONFETTI + M_TUMBLE, 0.0, 0.05 - h, -0.2)
	_flares(pos + Vector3(0.0, 4.5, 0.0), _n(count * 0.15), 3.0, _hdr(Color(1.0, 0.9, 0.5), 2.2), 0.7, 1.0)
