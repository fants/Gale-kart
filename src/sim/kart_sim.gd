class_name KartSim
extends RefCounted
## 街机式卡丁车物理：前向/侧向速度分解、漂移集气、瞬间加速、竖直弹道、护墙碰撞、状态效果。
## 移植自参考版 kart.js（数值保持一致），新增：渲染插值、尾流、抢跑、飞碟状态、小喷窗口事件。

const KART_RADIUS := 1.0
const GRAVITY := 25.0
const MAX_NITROS := 2
## 小喷：漂移至少持续这么久，松开后的窗口时长
const INSTANT_MIN_DRIFT := 0.35
const INSTANT_WINDOW := 0.42

var index := 0
var name := ""
var is_player := false
var kart_def: Dictionary
var character: Dictionary
var paint: Dictionary
var params: Dictionary
var input := KartInput.new()
var ai: AIDriver = null
var proj := TrackProj.new()
var auto_instant := false
var speed_mul := 1.0

# —— 运动状态 ——
var x := 0.0
var y := 0.0
var z := 0.0
var heading := 0.0
var vx := 0.0
var vz := 0.0
var vy := 0.0
var yaw_rate := 0.0
var steer := 0.0
var grip := 11.0
var on_ground := true
var air_time := 0.0
var last_ground_y := 0.0
var speed := 0.0
var forward_speed := 0.0
var slope := 0.0

# —— 插值用的上一子步状态 ——
var prev_x := 0.0
var prev_y := 0.0
var prev_z := 0.0
var prev_heading := 0.0
var prev_visual_drift := 0.0

# —— 漂移 / 加速 ——
var drifting := false
var drift_dir := 0.0
var drift_time := 0.0
var drift_intensity := 0.0
## -1..1，表现层用的车身侧滑角度提示
var visual_drift := 0.0
## AI 的视觉漂移方向
var fake_drift := 0.0
var instant_window := 0.0
var gauge := 0.0
var nitros := 0
var boost_time := 0.0
var boost_power := 0.0
var boost_kind := ""
var pad_cooldown := 0.0
var draft_time := 0.0
var draft_cooldown := 0.0
## 前方是否有可以借尾流的车（由 RaceSim 每个子步写入，表现层画风线）
var in_draft := false
var false_start := 0.0

# —— 受击 / 道具状态（剩余秒数） ——
var spin := 0.0
var flip := 0.0
var bubble := 0.0
var dizzy := 0.0
var cloud := 0.0
var ufo := 0.0
var shield := 0.0
var invuln := 0.0
var magnet := 0.0
var magnet_target: KartSim = null
var hit_kind := ""
var hit_time := 0.0
var items: Array[String] = []
var item_roll := 0.0
## 被导弹 / 水苍蝇锁定的剩余提示时间
var locked_by := 0.0

# —— 比赛进度 ——
var track_hint := -1
var s := 0.0
var lateral := 0.0
var lap := 0
var max_lap := 0
var last_idx := -1
var progress := 0.0
var finished := false
var finish_time := 0.0
var lap_start := 0.0
var lap_times: Array[float] = []
var best_lap := INF
var rank := 0
var offroad := false
var wrong_way := 0.0
var stuck_time := 0.0
var start_boost_armed := true
## 倒计时里第一次按下油门时的剩余倒计时；-1 表示还没按
var start_press_at := -1.0


func _init(p_index: int, p_name: String, p_is_player: bool, p_kart_def: Dictionary, p_character: Dictionary, p_paint: Dictionary) -> void:
	index = p_index
	name = p_name
	is_player = p_is_player
	kart_def = p_kart_def
	character = p_character
	paint = p_paint
	params = KartsData.kart_params(kart_def["stats"])
	reset({"pos": Vector3.ZERO, "heading": 0.0, "s": 0.0})


func reset(slot: Dictionary) -> void:
	var pos: Vector3 = slot["pos"]
	x = pos.x
	y = pos.y
	z = pos.z
	heading = slot["heading"]
	vx = 0.0; vz = 0.0; vy = 0.0
	yaw_rate = 0.0
	steer = 0.0
	grip = params["grip"]
	on_ground = true
	air_time = 0.0
	last_ground_y = pos.y
	drifting = false
	drift_dir = 0.0
	drift_time = 0.0
	drift_intensity = 0.0
	visual_drift = 0.0
	fake_drift = 0.0
	instant_window = 0.0
	gauge = 0.0
	nitros = 0
	boost_time = 0.0
	boost_power = 0.0
	boost_kind = ""
	pad_cooldown = 0.0
	draft_time = 0.0
	draft_cooldown = 0.0
	in_draft = false
	false_start = 0.0
	spin = 0.0; flip = 0.0; bubble = 0.0; dizzy = 0.0; cloud = 0.0; ufo = 0.0
	shield = 0.0; invuln = 0.0; magnet = 0.0
	magnet_target = null
	hit_kind = ""
	hit_time = 0.0
	items.clear()
	item_roll = 0.0
	locked_by = 0.0
	track_hint = -1
	s = float(slot.get("s", 0.0))
	lateral = 0.0
	lap = 0
	max_lap = 0
	last_idx = -1
	progress = 0.0
	finished = false
	finish_time = 0.0
	lap_start = 0.0
	lap_times.clear()
	best_lap = INF
	rank = 0
	offroad = false
	wrong_way = 0.0
	speed = 0.0
	forward_speed = 0.0
	stuck_time = 0.0
	slope = 0.0
	start_boost_armed = true
	start_press_at = -1.0
	snapshot_prev()


func snapshot_prev() -> void:
	prev_x = x
	prev_y = y
	prev_z = z
	prev_heading = heading
	prev_visual_drift = visual_drift


## 是否处于失控状态（不接受操作）
func is_disabled() -> bool:
	return spin > 0.0 or flip > 0.0 or bubble > 0.0


func is_boosting() -> bool:
	return boost_time > 0.0


func add_boost(time: float, power: float, kind: String) -> void:
	# 先判断"原本是否在加速"，否则力度会永远沿用历史最大值
	var was := is_boosting()
	boost_time = maxf(boost_time, time)
	boost_power = maxf(boost_power if was else 0.0, power)
	boost_kind = kind


func end_drift(events: Array, allow_instant := true) -> void:
	if not drifting:
		return
	var long_drift := drift_time > INSTANT_MIN_DRIFT
	drifting = false
	drift_dir = 0.0
	if allow_instant and long_drift:
		instant_window = INSTANT_WINDOW
		events.append({"type": "instant_ready", "kart": self})
		if auto_instant:
			trigger_instant(events)
	drift_time = 0.0


func trigger_instant(events: Array) -> void:
	instant_window = 0.0
	add_boost(0.6, 0.2, "instant")
	events.append({"type": "instant_boost", "kart": self})


func use_nitro(events: Array) -> void:
	add_boost(params["nitro_time"], params["boost_power"], "nitro")
	events.append({"type": "nitro", "kart": self})


## 受到攻击。返回 true 表示命中生效，false 表示被护盾 / 无敌挡下。kind: spin flip bubble dizzy
func apply_hit(kind: String, events: Array, source: KartSim = null) -> bool:
	if finished:
		return false
	if shield > 0.0:
		events.append({"type": "shield_block", "kart": self})
		return false
	if invuln > 0.0:
		return false
	end_drift(events, false)
	boost_time = 0.0
	magnet = 0.0
	match kind:
		"spin":
			spin = 1.05
			scale_velocity(0.42)
		"flip":
			flip = 1.35
			scale_velocity(0.18)
			vy = 8.5
			on_ground = false
		"bubble":
			bubble = 1.6
			scale_velocity(0.15)
		"dizzy":
			dizzy = 2.0
			scale_velocity(0.6)
	hit_kind = kind
	hit_time = 0.0
	events.append({"type": "hit", "kart": self, "kind": kind, "source": source})
	return true


func scale_velocity(k: float) -> void:
	vx *= k
	vz *= k


func respawn(track: TrackData, events: Array) -> void:
	var rs := track.wrap_s(s - 2.0)
	var p := track.point_at(rs, clampf(lateral, -track.half_width * 0.4, track.half_width * 0.4))
	x = p.x
	z = p.z
	y = p.y + 0.6
	heading = track.heading_at(rs)
	vx = 0.0; vz = 0.0; vy = 0.0
	yaw_rate = 0.0
	drifting = false
	spin = 0.0; flip = 0.0; bubble = 0.0; dizzy = 0.0
	boost_time = 0.0
	invuln = 1.6
	wrong_way = 0.0
	stuck_time = 0.0
	track_hint = int(rs)
	on_ground = false
	snapshot_prev()
	events.append({"type": "respawn", "kart": self})


func _tick(v: float, dt: float) -> float:
	return maxf(0.0, v - dt) if v > 0.0 else v


## 单个物理子步。ctx: {track, dt, events, locked, speed_mul, item_mode, time}
func step(ctx: Dictionary) -> void:
	var track: TrackData = ctx["track"]
	var dt: float = ctx["dt"]
	var events: Array = ctx["events"]
	var p := params
	var inp := input

	# —— 计时器 ——
	var was_disabled := is_disabled()
	spin = _tick(spin, dt); flip = _tick(flip, dt); bubble = _tick(bubble, dt)
	dizzy = _tick(dizzy, dt); cloud = _tick(cloud, dt); ufo = _tick(ufo, dt)
	shield = _tick(shield, dt); invuln = _tick(invuln, dt); magnet = _tick(magnet, dt)
	boost_time = _tick(boost_time, dt); pad_cooldown = _tick(pad_cooldown, dt)
	locked_by = _tick(locked_by, dt); draft_cooldown = _tick(draft_cooldown, dt)
	false_start = _tick(false_start, dt)
	if was_disabled and not is_disabled():
		invuln = maxf(invuln, 0.7)
	hit_time += dt

	var locked: bool = ctx["locked"]
	var disabled := is_disabled() or locked or (finished and ai == null)
	var air := not on_ground

	# —— 转向输入平滑 ——
	var steer_target := 0.0 if disabled else clampf(inp.steer, -1.0, 1.0)
	var growing := absf(steer_target) > absf(steer) and MathX.sgn(steer_target) == MathX.sgn(steer if steer != 0.0 else steer_target)
	steer = MathX.approach(steer, steer_target, (6.5 if growing else 11.0) * dt)

	# —— 分解速度 ——
	var fx := sin(heading)
	var fz := cos(heading)
	var rx := -fz
	var rz := fx
	var vf := vx * fx + vz * fz
	var vl := vx * rx + vz * rz

	# —— 有效极速 ——
	var vmax: float = p["max_speed"] * float(ctx.get("speed_mul", 1.0))
	if offroad:
		vmax *= 0.6
	if dizzy > 0.0:
		vmax *= 0.55
	if cloud > 0.0:
		vmax *= 0.8
	if ufo > 0.0:
		vmax *= 0.85
	if false_start > 0.0:
		vmax *= 0.3
	if is_boosting():
		vmax *= 1.0 + boost_power
	if magnet > 0.0:
		vmax *= 1.22

	# —— 漂移状态机 ——
	if not disabled and not air and inp.drift and not drifting and absf(inp.steer) > 0.2 and vf > 11.0:
		drifting = true
		drift_dir = MathX.sgn(inp.steer)
		drift_time = 0.0
		events.append({"type": "drift_start", "kart": self})
	if drifting and (not inp.drift or vf < 7.0 or disabled):
		end_drift(events, not disabled)
	if drifting:
		drift_time += dt

	if instant_window > 0.0:
		instant_window = maxf(0.0, instant_window - dt)
		if inp.throttle_pressed and not disabled:
			trigger_instant(events)

	# —— 油门 / 刹车 ——
	if not disabled and not air:
		if inp.throttle > 0.0 and vf < vmax:
			var k := clampf(1.0 - vf / vmax, 0.0, 1.0)
			vf += p["accel"] * inp.throttle * (0.22 + 0.78 * k) * dt
		elif inp.brake > 0.0:
			if vf > 0.5:
				vf -= p["brake"] * inp.brake * dt
			else:
				vf = maxf(vf - 14.0 * dt, -p["reverse_max"])
		if inp.throttle <= 0.0 and inp.brake <= 0.0:
			vf -= MathX.sgn(vf) * minf(absf(vf), (1.6 + absf(vf) * 0.035) * dt)
	elif not air:
		# 失控：强摩擦
		var kk := 7.0 if bubble > 0.0 else (1.6 if spin > 0.0 else 0.6)
		vf *= exp(-kk * dt)
		vl *= exp(-kk * dt)
	if is_boosting() and vf < vmax and not is_disabled():
		vf += 34.0 * dt
	if vf > vmax:
		vf = maxf(vmax, vf - ((vf - vmax) * 1.6 + 1.5) * dt)
	if drifting:
		vf -= p["drift_drag"] * (0.4 + drift_intensity) * dt

	# 用旧朝向重建世界速度
	var wx := fx * vf + rx * vl
	var wz := fz * vf + rz * vl

	# —— 偏航 ——
	var abs_v := absf(vf)
	var sf := clampf(abs_v / 8.0, 0.0, 1.0) * (1.0 - 0.5 * clampf(abs_v / p["max_speed"], 0.0, 1.3))
	var surface_turn := 0.92 if track.grip < 1.0 else 1.0
	var yaw_target: float
	if drifting:
		var u := drift_dir * 0.62 + steer * 0.55
		yaw_target = -u * p["turn_rate"] * p["drift_turn"] * maxf(sf, 0.45)
	else:
		yaw_target = -steer * p["turn_rate"] * sf * (-1.0 if vf < -0.5 else 1.0)
	yaw_target *= surface_turn
	if air:
		yaw_target *= 0.35
	if disabled:
		yaw_target = 0.0
	yaw_rate = MathX.damp(yaw_rate, yaw_target, 7.0 if drifting else 11.0, dt)
	heading = MathX.wrap_angle(heading + yaw_rate * dt)

	# 新朝向下重新分解
	fx = sin(heading)
	fz = cos(heading)
	rx = -fz
	rz = fx
	vf = wx * fx + wz * fz
	vl = wx * rx + wz * rz

	# —— 侧向抓地 ——
	var grip_target: float = p["drift_grip"] if drifting else p["grip"]
	grip_target *= track.grip
	if air:
		grip_target = 0.25
	if offroad:
		grip_target *= 0.85
	if spin > 0.0:
		grip_target = 2.5
	grip = MathX.damp(grip, grip_target, 12.0 if drifting else 3.2, dt)
	var sp2 := vf * vf + vl * vl
	var new_vl := vl * exp(-grip * dt)
	if vf > 0.5 and not disabled:
		var cons := sqrt(maxf(0.0, sp2 - new_vl * new_vl))
		var eff := 0.74 if drifting else 0.92
		vf += (cons - vf) * eff
	vl = new_vl

	var slip := atan2(absf(vl), maxf(absf(vf), 1.0))
	drift_intensity = clampf(slip / 0.45, 0.0, 1.0)

	# —— 集气（道具赛不集气） ——
	if drifting and not air and not ctx["item_mode"]:
		var gain: float = p["drift_charge"] * clampf(vf / 26.0, 0.0, 1.2) * (0.35 + 0.65 * drift_intensity) * dt
		charge_gauge(gain, events)

	vx = fx * vf + rx * vl
	vz = fz * vf + rz * vl
	forward_speed = vf

	# —— 磁铁牵引 ——
	if magnet > 0.0 and magnet_target != null and not disabled:
		var t := magnet_target
		var dx := t.x - x
		var dz := t.z - z
		var d := sqrt(dx * dx + dz * dz)
		if d > 3.0 and d < 90.0:
			var want := atan2(dx, dz)
			heading = MathX.damp_angle(heading, want, 2.2, dt)
			vx += (dx / d) * 10.0 * dt
			vz += (dz / d) * 10.0 * dt

	# —— 积分位置 ——
	if locked:
		vx = 0.0
		vz = 0.0
	x += vx * dt
	z += vz * dt

	# —— 投影到赛道 ——
	var pr := track.project(x, y, z, track_hint, proj)
	track_hint = pr.idx
	s = pr.s
	lateral = pr.lateral
	offroad = absf(pr.lateral) > track.half_width + 0.3

	# —— 护墙 ——
	var lim := track.wall_offset - KART_RADIUS
	if absf(pr.lateral) > lim:
		var side := MathX.sgn(pr.lateral)
		var pen := absf(pr.lateral) - lim
		x -= pr.nx * side * pen
		z -= pr.nz * side * pen
		var vn := (vx * pr.nx + vz * pr.nz) * side
		if vn > 0.0:
			vx -= pr.nx * side * vn * 1.3
			vz -= pr.nz * side * vn * 1.3
			var loss := clampf(vn / 30.0, 0.0, 0.45)
			vx *= 1.0 - loss
			vz *= 1.0 - loss
			if vn > 2.5:
				events.append({"type": "wall_hit", "kart": self, "strength": clampf(vn / 18.0, 0.0, 1.0), "side": side})
			if vn > 9.0:
				end_drift(events, false)
			# 贴墙时车头顺着墙
			var tang_h := atan2(pr.tx, pr.tz)
			var facing := tang_h if cos(MathX.wrap_angle(heading - tang_h)) >= 0.0 else MathX.wrap_angle(tang_h + PI)
			heading = MathX.damp_angle(heading, facing, 5.0, dt)
		lateral = side * lim

	# —— 竖直方向 ——
	var ground_y := pr.y
	vy -= GRAVITY * dt
	y += vy * dt
	if y <= ground_y:
		if not on_ground and air_time > 0.22:
			events.append({"type": "land", "kart": self, "strength": clampf(-vy / 16.0, 0.1, 1.0)})
		var ground_vy := (ground_y - last_ground_y) / dt
		y = ground_y
		vy = clampf(ground_vy, -20.0, 20.0)
		on_ground = true
		air_time = 0.0
	elif y > ground_y + 0.06:
		on_ground = false
		air_time += dt
	last_ground_y = ground_y
	var ahead_y := track.center_y(pr.s + 1.5) + track.ramp_height(track.wrap_s(pr.s + 1.5), pr.lateral)
	var behind_y := track.center_y(pr.s - 1.5) + track.ramp_height(track.wrap_s(pr.s - 1.5), pr.lateral)
	slope = (ahead_y - behind_y) / (3.0 * track.spacing)

	# —— 加速带 ——
	if pad_cooldown <= 0.0 and on_ground:
		for pad in track.boost_pads:
			var ds: float = pr.s - pad["s"]
			if ds > track.n / 2.0:
				ds -= track.n
			if ds < -track.n / 2.0:
				ds += track.n
			if absf(ds) < pad["half_len_s"] and absf(pr.lateral - pad["lateral"]) < pad["half_width"]:
				add_boost(1.25, 0.34, "pad")
				pad_cooldown = 0.8
				events.append({"type": "boost_pad", "kart": self})
				break

	# —— 逆行检测 ——
	var along := fx * pr.tx + fz * pr.tz
	var spd := sqrt(vx * vx + vz * vz)
	speed = spd
	if along < -0.25 and spd > 4.0 and not disabled:
		wrong_way += dt
	else:
		wrong_way = maxf(0.0, wrong_way - dt * 2.0)

	# 表现层漂移角提示
	var vd_target := drift_dir * (0.55 + 0.45 * drift_intensity) if drifting else fake_drift * 0.5
	visual_drift = MathX.damp(visual_drift, vd_target, 6.0 if drifting else 4.0, dt)


## 尾流：前方有可借力的车时累计，满 0.9 s 触发一次加速（冷却 2 s）
func update_draft(dt: float, eligible: bool, events: Array) -> void:
	in_draft = eligible
	if eligible and draft_cooldown <= 0.0 and not is_boosting():
		draft_time += dt
		if draft_time >= 0.9:
			draft_time = 0.0
			draft_cooldown = 2.0
			add_boost(1.2, 0.12, "draft")
			events.append({"type": "draft", "kart": self})
	else:
		draft_time = maxf(0.0, draft_time - dt * 1.5)


func charge_gauge(gain: float, events: Array) -> void:
	if nitros >= MAX_NITROS:
		gauge = minf(1.0, gauge + gain)
		return
	gauge += gain
	if gauge >= 1.0:
		gauge -= 1.0
		nitros += 1
		events.append({"type": "gauge_full", "kart": self})
