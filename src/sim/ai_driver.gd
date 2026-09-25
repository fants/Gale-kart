class_name AIDriver
extends RefCounted
## AI 车手：赛车线跟随 + 曲率速度规划 + 避障 + 道具策略。只写 kart.input，不直接改物理。
## 移植自参考版 ai.js；新增：困难档出弯小喷、利用尾流（贴近前车走线）、飞碟 / 水苍蝇道具策略。

## AI 规划用的侧向加速度上限（m/s²）
const LAT_ACCEL := 25.0
const BRAKE_DECEL := 22.0

var kart: KartSim
var diff: Dictionary
var rng := RandomNumberGenerator.new()
var autopilot := false
var skill := 1.0
var lane_bias := 0.0
var phase := 0.0
var personal_speed := 1.0
var avoid := 0.0
var avoid_target := 0.0
var item_delay := 0.0
var nitro_delay := 0.0
var wobble := 0.0
var mistake_timer := 0.0
var hold_time := 0.0
var fake_drift_time := 0.0


func _init(p_kart: KartSim, p_diff: Dictionary, seed: int, p_autopilot := false) -> void:
	kart = p_kart
	diff = p_diff
	rng.seed = seed
	autopilot = p_autopilot
	skill = clampf(float(diff["line"]) * MathX.rng_range(rng, 0.92, 1.06), 0.3, 1.05)
	lane_bias = MathX.rng_range(rng, -1.0, 1.0)
	phase = rng.randf() * 100.0
	personal_speed = MathX.rng_range(rng, 0.975, 1.02)
	item_delay = MathX.rng_range(rng, 1.0, 3.0)
	nitro_delay = MathX.rng_range(rng, 0.3, 1.2)
	mistake_timer = MathX.rng_range(rng, 4.0, 10.0)


func update(dt: float, race: RaceSim) -> void:
	var k := kart
	var track := race.track
	var inp := k.input
	var n := track.n
	var spacing := track.spacing
	var half_width := track.half_width
	inp.throttle_pressed = false
	inp.use_pressed = false
	inp.swap_pressed = false
	inp.respawn_pressed = false
	inp.drift = false

	var spd := maxf(k.forward_speed, 0.0)
	var idx := int(k.s) % n

	# —— 失误：偶尔走线摇摆 ——
	mistake_timer -= dt
	if mistake_timer <= 0.0:
		mistake_timer = MathX.rng_range(rng, 5.0, 12.0)
		if rng.randf() < float(diff["mistakes"]):
			wobble = MathX.rng_range(rng, 0.6, 1.3)
	if wobble > 0.0:
		wobble -= dt

	# —— 避障：前方车辆与危险物 ——
	avoid_target = 0.0
	var look_s := 14.0 / spacing
	var draft_lat := INF
	for o in race.karts:
		if o == k or o.finished:
			continue
		var ds := o.s - k.s
		if ds < -n / 2.0:
			ds += n
		if ds > n / 2.0:
			ds -= n
		if ds > 0.0 and ds < look_s and absf(o.lateral - k.lateral) < 2.6 and o.speed < k.speed + 2.0:
			var room := -1.0 if o.lateral > 0.0 else 1.0
			avoid_target = room * 3.2
			break
		# 尾流：前方 16–40 m 的车，稍微向它的走线靠拢
		if ds * spacing > 16.0 and ds * spacing < 40.0 and absf(o.lateral - k.lateral) < 5.0:
			draft_lat = o.lateral
	if race.items != null:
		var hz := race.items.hazard_ahead(k, 36.0 / spacing, 2.8)
		if not hz.is_empty():
			avoid_target = (-1.0 if float(hz["lateral"]) > k.lateral else 1.0) * 3.6
	avoid += (avoid_target - avoid) * minf(1.0, dt * 2.5)

	# —— 目标点 ——
	var look := 7.0 + spd * 0.5
	var ts := k.s + look / spacing
	var ti := int(track.wrap_s(ts))
	var wobble_off := sin(race.time * 6.0 + phase) * 3.5 if wobble > 0.0 else 0.0
	var slow_noise := sin(race.time * 0.23 + phase) * 0.35
	var line := track.racing_line[ti] * skill
	var bias := (lane_bias * 0.5 + slow_noise) * (half_width * 0.45) * (1.0 - skill * 0.5)
	if is_finite(draft_lat) and absf(avoid_target) < 0.01:
		bias = lerpf(bias, draft_lat - line, 0.35 * skill)
	var lat := clampf(line + bias + avoid + wobble_off, -(half_width - 1.3), half_width - 1.3)
	var p := track.point_at(ts, lat)
	var desired := atan2(p.x - k.x, p.z - k.z)
	var diff_a := MathX.wrap_angle(desired - k.heading)
	var steer := clampf(-diff_a * 2.4, -1.0, 1.0)

	# 严重偏离（被撞歪 / 逆行）时直接朝赛道方向
	var along := cos(MathX.wrap_angle(k.heading - track.heading_at(k.s)))
	if along < 0.0:
		steer = MathX.sgn(-diff_a) if diff_a != 0.0 else 1.0

	# —— 速度规划 ——
	var a_lat := LAT_ACCEL * (0.85 + 0.15 * skill)
	var target: float = k.params["max_speed"] * 1.6
	var horizon := ceili((30.0 + spd * 1.4) / spacing)
	var j := 2
	while j < horizon:
		var c := track.rl_curv[(idx + j) % n]
		if c >= 1e-4:
			var v_corner := sqrt(a_lat / c)
			var d := j * spacing
			var v_allowed := sqrt(v_corner * v_corner + 2.0 * BRAKE_DECEL * d)
			if v_allowed < target:
				target = v_allowed
		j += 2
	# 冰面更早减速
	if track.grip < 1.0:
		target *= 0.95

	var throttle := 1.0
	var brake := 0.0
	if spd > target + 1.5:
		throttle = 0.0
		brake = clampf((spd - target) / 6.0, 0.2, 1.0)
	elif spd > target - 0.5:
		throttle = 0.4
	if k.is_disabled():
		throttle = 0.0
		brake = 0.0
	inp.steer = steer
	inp.throttle = throttle
	inp.brake = brake

	# —— 视觉漂移 + 集气（AI 不使用真实漂移物理，保证走线稳定） ——
	var cornering := absf(steer) > 0.55 and spd > 17.0 and k.on_ground and not k.is_disabled()
	var prev_fake := fake_drift_time
	if cornering:
		fake_drift_time += dt
	else:
		fake_drift_time = maxf(0.0, fake_drift_time - dt * 3.0)
	var fd := MathX.sgn(steer) if fake_drift_time > 0.15 else 0.0
	# 出弯小喷：视觉漂移持续够久后结束的那一刻，按难度概率触发
	if k.fake_drift != 0.0 and fd == 0.0 and prev_fake > KartSim.INSTANT_MIN_DRIFT + 0.15 and not k.is_disabled():
		if rng.randf() < float(diff.get("instant", 0.0)):
			k.trigger_instant(race.events)
	k.fake_drift = fd
	if fd != 0.0 and not race.item_mode:
		k.charge_gauge(k.params["drift_charge"] * 0.8 * dt, race.events)

	# —— 氮气（竞速赛） ——
	if not race.item_mode and k.nitros > 0 and not k.is_boosting():
		nitro_delay -= dt
		if nitro_delay <= 0.0 and straight_ahead(track, idx, 60.0):
			inp.use_pressed = true
			nitro_delay = MathX.rng_range(rng, 0.4, 2.2) / (0.5 + float(diff["aggression"]))

	# —— 道具（道具赛） ——
	if race.item_mode and not k.items.is_empty() and k.item_roll <= 0.0:
		decide_item(dt, race)

	# —— 卡住自救 ——
	if not race.is_locked() and not k.is_disabled() and spd < 1.5 and not k.finished:
		k.stuck_time += dt
	else:
		k.stuck_time = maxf(0.0, k.stuck_time - dt)
	if k.stuck_time > 2.5 or k.wrong_way > 2.5:
		inp.respawn_pressed = true
		k.stuck_time = 0.0


func straight_ahead(track: TrackData, idx: int, meters: float) -> bool:
	var cnt := ceili(meters / track.spacing)
	var j := 0
	while j < cnt:
		if track.rl_curv[(idx + j) % track.n] > 1.0 / 90.0:
			return false
		j += 3
	return true


func decide_item(dt: float, race: RaceSim) -> void:
	var k := kart
	hold_time += dt
	item_delay -= dt
	if item_delay > 0.0:
		return
	var item: String = k.items[0]
	var agg := float(diff["aggression"])
	var ahead := race.kart_ahead(k)
	var behind := race.kart_behind(k)
	var gap_ahead := race.gap_meters(k, ahead) if ahead != null else INF
	var gap_behind := race.gap_meters(behind, k) if behind != null else INF
	var use := false
	match item:
		"nitro":
			use = straight_ahead(race.track, int(k.s), 45.0) or hold_time > 4.0
		"missile":
			use = gap_ahead > 6.0 and gap_ahead < 140.0
		"water":
			use = (gap_ahead > 4.0 and gap_ahead < 55.0) or hold_time > 9.0
		"banana":
			use = gap_behind < 22.0 or hold_time > 10.0
		"shield":
			use = k.locked_by > 0.0 or hold_time > 16.0
		"cloud", "thunder", "ufo", "water_fly":
			use = hold_time > 0.8
		"magnet":
			use = gap_ahead > 8.0 and gap_ahead < 70.0
		_:
			use = true
	# 被锁定时，如果护盾在第二格就立刻交换使用
	if not use and k.locked_by > 0.0 and k.items.size() > 1 and k.items[1] == "shield":
		k.input.swap_pressed = true
		item_delay = 0.1
		return
	if use and rng.randf() < 0.35 + agg * 0.65:
		k.input.use_pressed = true
		hold_time = 0.0
		item_delay = MathX.rng_range(rng, 0.6, 2.4) / (0.4 + agg)
	else:
		item_delay = 0.25
