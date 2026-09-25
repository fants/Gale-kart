class_name MathX
extends RefCounted
## 通用数学工具（仿真层与表现层共用）。


## 帧率无关的指数趋近：rate 越大越快
static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


static func damp_v3(current: Vector3, target: Vector3, rate: float, dt: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-rate * dt))


## 线性趋近，每次最多变化 max_delta
static func approach(current: float, target: float, max_delta: float) -> float:
	if current < target:
		return minf(current + max_delta, target)
	return maxf(current - max_delta, target)


## 把角度规范到 (-PI, PI]
static func wrap_angle(a: float) -> float:
	a = fmod(a + PI, TAU)
	if a < 0.0:
		a += TAU
	return a - PI


static func damp_angle(current: float, target: float, rate: float, dt: float) -> float:
	return current + wrap_angle(target - current) * (1.0 - exp(-rate * dt))


## 最短弧插值
static func lerp_angle_short(a: float, b: float, t: float) -> float:
	return a + wrap_angle(b - a) * t


static func sgn(v: float) -> float:
	return 1.0 if v > 0.0 else (-1.0 if v < 0.0 else 0.0)


static func smooth(a: float, b: float, v: float) -> float:
	var t := clampf((v - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func rng_range(rng: RandomNumberGenerator, a: float, b: float) -> float:
	return a + (b - a) * rng.randf()


## 按权重表 {key: weight} 抽取一个 key
static func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k: String in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]


## 秒 → "1:23.456"
static func format_time(t: float, digits := 3) -> String:
	if not is_finite(t) or t < 0.0:
		return "--:--.---"
	var m := int(floor(t / 60.0))
	var s := t - m * 60.0
	var ss := String.num(s, digits)
	if digits > 0 and not "." in ss:
		ss += "." + "0".repeat(digits)
	var dot := ss.find(".")
	if dot >= 0 and ss.length() - dot - 1 < digits:
		ss += "0".repeat(digits - (ss.length() - dot - 1))
	return "%d:%s" % [m, ss.pad_zeros(2)]
