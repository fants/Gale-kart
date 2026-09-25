class_name RaceSim
extends RefCounted
## 比赛流程：发车格、倒计时、起步加速 / 抢跑、固定子步物理、车车碰撞、尾流、圈数与名次、道具、幽灵车录制。
## 移植自参考版 race.js。

const SUBSTEP := 1.0 / 120.0
const INTRO_TIME := 3.2
## 3.6 → 0：3、2、1 分别在剩余 3 / 2 / 1 秒时出现
const COUNTDOWN_TIME := 3.6
const GHOST_RATE := 10.0
const MAX_SUBSTEPS := 12
## 尾流判定：前方距离范围（米）、横向容差、最低速度
const DRAFT_MIN := 3.0
const DRAFT_MAX := 14.0
const DRAFT_LAT := 2.6
const DRAFT_SPEED := 15.0

var opts: Dictionary
var track: TrackData
var mode := "speed"
var item_mode := false
var laps := 3
var diff: Dictionary
var rng := RandomNumberGenerator.new()
var events: Array[Dictionary] = []
## 从 GO 开始计时
var time := 0.0
## 总时钟
var clock := 0.0
var phase := "intro"
var phase_time := 0.0
var countdown := COUNTDOWN_TIME
var last_count := 4
var accumulator := 0.0
## 插值系数 = accumulator / SUBSTEP
var alpha := 0.0
var ghost_rec := PackedFloat32Array()
var ghost_timer := 0.0
var player_finished_at := -1.0
var karts: Array[KartSim] = []
var player: KartSim
var ranking: Array[KartSim] = []
var items: ItemSystem = null
## 回放录制器（可选，由外部挂上）
var recorder: RefCounted = null
## 当前子步是否是本帧的第一个（边沿输入只在第一个子步消费）
var _first := true


## opts: {track, mode, laps, difficulty, player:{kart_id, character_id, paint_id}, ai_count, seed,
##        auto_instant, all_ai, skip_intro, ai_roster:[{character_id, kart_id, paint_id}]}
func _init(p_opts: Dictionary) -> void:
	opts = p_opts
	track = opts["track"]
	mode = opts.get("mode", "speed")
	item_mode = mode == "item"
	laps = int(opts.get("laps", 3))
	diff = KartsData.DIFFICULTIES.get(opts.get("difficulty", "normal"), KartsData.DIFFICULTIES["normal"])
	var seed: int = int(opts.get("seed", 12345))
	rng.seed = seed
	phase = "countdown" if opts.get("skip_intro", false) else "intro"

	var psel: Dictionary = opts.get("player", {})
	var pk := KartsData.kart_by_id(psel.get("kart_id", "marshmallow"))
	var pc := KartsData.character_by_id(psel.get("character_id", "male-a"))
	var pp := KartsData.paint_by_id(psel.get("paint_id", "oodi"))
	player = KartSim.new(0, "你", true, pk, pc, pp)
	player.auto_instant = bool(opts.get("auto_instant", false))

	var ai_count: int = 0 if mode == "time" else int(opts.get("ai_count", 7))
	# AI 车手：从其余角色中随机挑选，名字即角色名
	var chars: Array[Dictionary] = []
	for c in KartsData.CHARACTERS:
		if c["id"] != pc["id"]:
			chars.append(c)
	_shuffle(chars)
	var paints: Array[Dictionary] = []
	for pt in KartsData.PAINTS:
		if pt["id"] != pp["id"]:
			paints.append(pt)
	var all: Array[KartSim] = [player]
	# 可选：固定的 AI 阵容（大奖赛各场保持一致）[{character_id, kart_id, paint_id}, ...]
	var roster: Array = opts.get("ai_roster", [])
	for i in ai_count:
		var kd: Dictionary = KartsData.KARTS[(i + 1) % KartsData.KARTS.size()]
		var ch: Dictionary = chars[i % chars.size()]
		var pt: Dictionary = paints[i % paints.size()]
		if i < roster.size():
			var r: Dictionary = roster[i]
			kd = KartsData.kart_by_id(r.get("kart_id", kd["id"]))
			ch = KartsData.character_by_id(r.get("character_id", ch["id"]))
			pt = KartsData.paint_by_id(r.get("paint_id", pt["id"]))
		var k := KartSim.new(i + 1, ch["name"], false, kd, ch, pt)
		k.ai = AIDriver.new(k, diff, seed * 31 + i * 977)
		all.append(k)
	if opts.get("all_ai", false):
		player.ai = AIDriver.new(player, KartsData.DIFFICULTIES["hard"], 4242, true)

	# 发车：玩家在中后位置（第 6 格），与原作体验一致
	var order: Array[KartSim] = all.duplicate()
	order.remove_at(0)
	var player_slot := 5 if ai_count >= 5 else ai_count
	order.insert(player_slot, player)
	for i in order.size():
		var k := order[i]
		var slot: Dictionary = track.grid[i]
		k.reset(slot)
		k.track_hint = -1
		var pr := track.project(k.x, k.y, k.z, -1, k.proj)
		k.track_hint = pr.idx
		k.s = pr.s
		k.last_idx = int(pr.s)
		k.progress = k.s - track.n
		k.lap = 0
	karts = all
	ranking = all.duplicate()
	_update_ranking()
	if item_mode:
		items = ItemSystem.new(self)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func is_locked() -> bool:
	return phase == "intro" or phase == "countdown"


func skip_intro() -> void:
	if phase == "intro":
		phase = "countdown"
		phase_time = 0.0


## 每帧调用。player_input 为玩家输入快照（含 *_pressed 边沿）。
func update(dt: float, player_input: KartInput) -> void:
	events.clear()
	dt = minf(dt, 1.0 / 20.0)
	if player_input != null and player.ai == null:
		player.input.copy_from(player_input, true)
	accumulator += dt
	_first = true
	var steps := 0
	while accumulator >= SUBSTEP and steps < MAX_SUBSTEPS:
		accumulator -= SUBSTEP
		_substep(SUBSTEP)
		_first = false
		steps += 1
	if steps >= MAX_SUBSTEPS:
		accumulator = 0.0
	alpha = clampf(accumulator / SUBSTEP, 0.0, 1.0)


func _substep(dt: float) -> void:
	clock += dt
	phase_time += dt
	var p := player
	for k in karts:
		k.snapshot_prev()

	# —— 流程 ——
	if phase == "intro" and phase_time >= INTRO_TIME:
		phase = "countdown"
		phase_time = 0.0
	if phase == "countdown":
		countdown = COUNTDOWN_TIME - phase_time
		var c := ceili(countdown)
		if c < last_count and c >= 1 and c <= 3:
			events.append({"type": "countdown", "value": c})
		last_count = c
		# 起步判定（玩家）：只看第一次"按下"边沿，从菜单按住带进来的不算。
		# 剩余 > 1 s：太早，只是没有起步加速；1 s ~ 0.35 s：抢跑，GO 时原地打滑；≤ 0.35 s：完美起步
		if _first and p.input.throttle_pressed and p.ai == null and p.start_boost_armed and p.start_press_at == -1.0:
			if countdown > 1.0:
				p.start_boost_armed = false
			elif countdown > 0.35:
				p.start_boost_armed = false
				p.start_press_at = -2.0
			else:
				p.start_press_at = countdown
		if countdown <= 0.0:
			_go()

	if phase == "racing" or phase == "finished":
		time += dt
		if time < 0.3 and _first and p.input.throttle_pressed and p.start_boost_armed and p.start_press_at == -1.0 and p.ai == null:
			p.start_boost_armed = false
			p.add_boost(1.3, 0.3, "start")
			events.append({"type": "start_boost", "kart": p})

	# —— AI 输入 ——
	for k in karts:
		if k.ai != null:
			k.ai.update(dt, self)

	# —— 橡皮筋 ——
	for k in karts:
		var mul := 1.0
		if k.ai != null and not k.ai.autopilot and not k.is_player:
			mul = float(diff["speed"]) * k.ai.personal_speed
			var gap := (k.progress - player.progress) * track.spacing
			var r := float(diff["rubber"])
			if gap > 0.0:
				mul *= 1.0 - clampf(gap / 450.0, 0.0, 1.0) * 0.12 * r
			else:
				mul *= 1.0 + clampf(-gap / 350.0, 0.0, 1.0) * 0.14 * r
		k.speed_mul = mul

	# —— 道具 / 氮气 / 复位 输入 ——
	for k in karts:
		var inp := k.input
		var edge := true if k.ai != null else _first
		if not edge:
			continue
		if inp.respawn_pressed and not is_locked() and not k.is_disabled():
			k.respawn(track, events)
		if is_locked() or (k.finished and k.ai == null):
			continue
		if inp.swap_pressed and k.items.size() == 2 and k.item_roll <= 0.0:
			k.items.reverse()
			events.append({"type": "item_swap", "kart": k})
		if inp.use_pressed and not k.is_disabled():
			if item_mode:
				if not k.items.is_empty() and k.item_roll <= 0.0 and k.ufo <= 0.0:
					items.use(k)
			elif k.nitros > 0 and not (k.boost_kind == "nitro" and k.boost_time > 0.4):
				k.nitros -= 1
				k.use_nitro(events)
	for k in karts:
		if k.item_roll > 0.0:
			k.item_roll = maxf(0.0, k.item_roll - dt)

	# —— 物理 ——
	var ctx := {"track": track, "dt": dt, "events": events, "locked": is_locked(), "item_mode": item_mode, "time": time, "speed_mul": 1.0}
	for k in karts:
		ctx["speed_mul"] = k.speed_mul
		k.step(ctx)
	# 边沿只保留一个子步
	if p.ai == null:
		p.input.clear_edges()

	_collide_karts()
	if not is_locked():
		_update_drafts(dt)
	if items != null:
		items.update(dt)

	# —— 圈数 ——
	if not is_locked():
		for k in karts:
			_update_lap(k)
	_update_ranking()

	# —— 幽灵车录制（计时赛） ——
	if mode == "time" and phase == "racing" and not p.finished:
		ghost_timer += dt
		if ghost_timer >= 1.0 / GHOST_RATE:
			ghost_timer -= 1.0 / GHOST_RATE
			ghost_rec.append_array([p.x, p.y, p.z, p.heading])
	if recorder != null:
		recorder.call("capture", self, dt)


func _go() -> void:
	phase = "racing"
	phase_time = 0.0
	time = 0.0
	events.append({"type": "go"})
	for k in karts:
		k.lap_start = 0.0
		if k.ai != null and not k.is_player:
			if rng.randf() < float(diff["start_boost"]):
				k.add_boost(1.3, 0.3, "start")
	var p := player
	if p.ai == null:
		if p.start_press_at == -2.0:
			# 抢跑：原地打滑一会儿
			p.false_start = 0.8
			events.append({"type": "false_start", "kart": p})
		elif p.start_boost_armed and p.start_press_at >= 0.0:
			p.start_boost_armed = false
			p.add_boost(1.3, 0.3, "start")
			events.append({"type": "start_boost", "kart": p})
	ghost_rec.append_array([p.x, p.y, p.z, p.heading])


## 尾流：前方 3–14 m、横向差 < 2.6 m 且速度够快
func _update_drafts(dt: float) -> void:
	for k in karts:
		var eligible := false
		if not k.finished and k.on_ground and k.speed > DRAFT_SPEED and not k.is_disabled():
			var fx := sin(k.heading)
			var fz := cos(k.heading)
			for o in karts:
				if o == k or o.is_disabled():
					continue
				var dx := o.x - k.x
				var dz := o.z - k.z
				var ahead := dx * fx + dz * fz
				if ahead < DRAFT_MIN or ahead > DRAFT_MAX:
					continue
				var side := absf(dx * fz - dz * fx)
				if side < DRAFT_LAT and absf(o.y - k.y) < 2.0:
					eligible = true
					break
		k.update_draft(dt, eligible, events)


func _update_lap(k: KartSim) -> void:
	var n := track.n
	var idx := int(k.s)
	if k.last_idx >= 0:
		var d := idx - k.last_idx
		if d < -n / 2:
			k.lap += 1
		elif d > n / 2:
			k.lap -= 1
	k.last_idx = idx
	# lap 0 = 起点线前（负值）
	k.progress = (k.lap - 1) * n + k.s
	if k.finished:
		return
	if k.lap > k.max_lap:
		k.max_lap = k.lap
		if k.lap >= 2:
			var lt := time - k.lap_start
			k.lap_times.append(lt)
			if lt < k.best_lap:
				k.best_lap = lt
			k.lap_start = time
			if k.lap > laps:
				k.finished = true
				k.finish_time = time
				events.append({"type": "finish", "kart": k, "time": time})
				if k.is_player:
					player_finished_at = time
					phase = "finished"
					# 冲线后交给自动驾驶继续跑
					if k.ai == null:
						k.ai = AIDriver.new(k, KartsData.DIFFICULTIES["normal"], 99, true)
			else:
				events.append({"type": "lap", "kart": k, "lap": k.lap, "time": lt, "final": k.lap == laps})


func _collide_karts() -> void:
	var r2 := KartSim.KART_RADIUS * 2.1
	for i in karts.size():
		var a := karts[i]
		if a.bubble > 0.0:
			continue
		for j in range(i + 1, karts.size()):
			var b := karts[j]
			if b.bubble > 0.0:
				continue
			var dx := b.x - a.x
			var dz := b.z - a.z
			var d2 := dx * dx + dz * dz
			if d2 >= r2 * r2 or absf(a.y - b.y) > 1.8:
				continue
			var d := sqrt(d2)
			if d == 0.0:
				d = 0.001
			var nx := dx / d
			var nz := dz / d
			var ia := 1.0 / float(a.params["mass"])
			var ib := 1.0 / float(b.params["mass"])
			var sum := ia + ib
			var overlap := r2 - d
			a.x -= nx * overlap * (ia / sum)
			a.z -= nz * overlap * (ia / sum)
			b.x += nx * overlap * (ib / sum)
			b.z += nz * overlap * (ib / sum)
			var vrel := (b.vx - a.vx) * nx + (b.vz - a.vz) * nz
			if vrel < 0.0:
				var jimp := (-(1.0 + 0.35) * vrel) / sum
				a.vx -= jimp * ia * nx
				a.vz -= jimp * ia * nz
				b.vx += jimp * ib * nx
				b.vz += jimp * ib * nz
				if -vrel > 2.5:
					events.append({"type": "kart_hit", "a": a, "b": b, "strength": clampf(-vrel / 14.0, 0.0, 1.0),
						"pos": Vector3((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0)})


func _update_ranking() -> void:
	ranking.sort_custom(func(a: KartSim, b: KartSim) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return a.progress > b.progress)
	for i in ranking.size():
		ranking[i].rank = i + 1


func kart_ahead(k: KartSim) -> KartSim:
	return ranking[k.rank - 2] if k.rank > 1 else null


func kart_behind(k: KartSim) -> KartSim:
	return ranking[k.rank] if k.rank < ranking.size() else null


## a 在 b 之后多少米（b 领先为正）
func gap_meters(a: KartSim, b: KartSim) -> float:
	return (b.progress - a.progress) * track.spacing


## 结算用：未完赛者按剩余距离估算完赛时间
func results() -> Array[Dictionary]:
	var n := track.n
	var total_s := laps * n
	var out: Array[Dictionary] = []
	for k in ranking:
		var t := k.finish_time
		var estimated := false
		if not k.finished:
			var done := maxf(0.0, k.progress)
			var remain := maxf(0.0, total_s - done) * track.spacing
			var avg := (done * track.spacing) / time if done > 0.0 and time > 1.0 else 25.0
			t = time + remain / maxf(avg, 12.0)
			estimated = true
		out.append({"kart": k, "time": t, "estimated": estimated, "best_lap": k.best_lap, "rank": k.rank})
	return out


## 断开 KartSim ↔ AIDriver、道具实体 ↔ KartSim 之间的循环引用，比赛结束后调用
## 当前 AI 阵容（用于大奖赛后续场次保持一致）
func ai_roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in karts:
		if not k.is_player:
			out.append({"character_id": k.character["id"], "kart_id": k.kart_def["id"], "paint_id": k.paint["id"]})
	return out


func dispose() -> void:
	for k in karts:
		k.ai = null
		k.magnet_target = null
	items = null
	recorder = null
	ranking.clear()
	karts.clear()
	events.clear()
	player = null


func all_finished() -> bool:
	for k in karts:
		if not k.finished:
			return false
	return true
