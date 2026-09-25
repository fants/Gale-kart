extends RefCounted
## 比赛仿真：每条赛道 8 辆 AI 跑完 3 圈；玩家操作冒烟（加速、漂移集气、氮气、小喷）；
## 起步加速 / 抢跑 / 太早按不罚；尾流；大 dt 不穿墙。

const DT := 1.0 / 60.0


func run(t: TestUtil) -> void:
	_test_full_races(t)
	_test_player_smoke(t)
	_test_start(t)
	_test_draft(t)
	_test_big_dt(t)
	t.done()


func _make(track_id: String, extra := {}) -> RaceSim:
	var o := {"track": TrackData.build(TracksData.track_by_id(track_id)), "mode": "speed", "laps": 3,
		"difficulty": "normal", "skip_intro": true, "seed": 7}
	o.merge(extra, true)
	return RaceSim.new(o)


## 把车摆到赛道 s 处（米）的中线上，朝向赛道方向，给定速度
func _place(race: RaceSim, k: KartSim, meters: float, speed: float, heading := INF, lateral := 0.0) -> void:
	var tr := race.track
	var s := meters / tr.spacing
	var h := tr.heading_at(s) if heading == INF else heading
	k.reset({"pos": tr.point_at(s, lateral), "heading": h, "s": s})
	k.track_hint = int(s)
	k.vx = sin(h) * speed
	k.vz = cos(h) * speed


func _until_racing(race: RaceSim, inp: KartInput) -> void:
	var guard := 0
	while race.phase != "racing" and guard < 2000:
		race.update(DT, inp)
		inp.clear_edges()
		guard += 1


func _test_full_races(t: TestUtil) -> void:
	for def: Dictionary in TracksData.TRACKS:
		var id: String = def["id"]
		var race := _make(id, {"difficulty": "hard", "all_ai": true})
		var t0 := Time.get_ticks_msec()
		var sim_t := 0.0
		# 卡死检测：每 0.5 s 记录一次进度，任意 3 s 窗口前进 < 5 m 视为卡死
		var hist := {}
		var stuck := {}
		var sample_t := 0.0
		while sim_t < 900.0 and not race.all_finished():
			race.update(DT, null)
			sim_t += DT
			if race.phase == "racing" or race.phase == "finished":
				sample_t += DT
				if sample_t >= 0.5:
					sample_t = 0.0
					for k in race.karts:
						if k.finished:
							continue
						var h: Array = hist.get(k.index, [])
						h.append(k.progress)
						if h.size() > 7:
							h.pop_front()
							if (h[6] - h[0]) * race.track.spacing < 5.0 and race.time > 4.0:
								stuck[k.index] = true
						hist[k.index] = h
		var ms := Time.get_ticks_msec() - t0
		var finished := 0
		var lo := INF
		var hi := 0.0
		for k in race.karts:
			if k.finished:
				finished += 1
			for lt in k.lap_times:
				lo = minf(lo, lt)
				hi = maxf(hi, lt)
		t.check(finished == race.karts.size(), "%s：%d/%d 辆车完赛" % [id, finished, race.karts.size()])
		t.check(stuck.is_empty(), "%s：没有车卡死 %s" % [id, str(stuck.keys())])
		var min_ok := race.track.length / 48.0
		var max_ok := race.track.length / 16.0
		t.check(lo >= min_ok and hi <= max_ok, "%s：单圈 %.1f–%.1f s 在 [%.1f, %.1f] 内" % [id, lo, hi, min_ok, max_ok])
		var winner := race.ranking[0]
		print("  %s：冠军 %s %.2f s，末名 %.2f s，仿真 %.0f s 用时 %d ms" % [id, winner.name, winner.finish_time, race.ranking[-1].finish_time, sim_t, ms])
		race.dispose()


func _test_player_smoke(t: TestUtil) -> void:
	var race := _make("village", {"ai_count": 0})
	var inp := KartInput.new()
	_until_racing(race, inp)
	var p := race.player
	# 直线加速 3 s
	inp.throttle = 1.0
	for i in 180:
		race.update(DT, inp)
	t.check(p.speed > 20.0, "直线全油门 3 s 后速度 %.1f > 20 m/s" % p.speed)
	# 漂移集气 1 s（村庄起点直道 196 m，每个子测试前摆回直道起点）
	_place(race, p, 10.0, 26.0)
	inp.drift = true
	inp.steer = -0.6
	var gauge0 := p.gauge
	for i in 60:
		race.update(DT, inp)
	t.check(p.gauge - gauge0 > 0.12, "漂移 1 s 集气 %.2f" % (p.gauge - gauge0))
	# 氮气
	inp.drift = false
	inp.steer = 0.0
	_place(race, p, 10.0, 26.0)
	p.nitros = 1
	inp.use_pressed = true
	race.update(DT, inp)
	inp.use_pressed = false
	t.check(p.is_boosting() and p.boost_kind == "nitro", "按氮气后进入氮气加速（%s）" % p.boost_kind)
	# 小喷：漂移 0.5 s → 松开 → 窗口内重新按下油门
	_place(race, p, 10.0, 26.0)
	inp.drift = true
	inp.steer = 1.0
	for i in 30:
		race.update(DT, inp)
	t.check(p.drifting, "进入漂移")
	inp.drift = false
	inp.steer = 0.0
	var ready := false
	race.update(DT, inp)
	for e in race.events:
		if e["type"] == "instant_ready":
			ready = true
	t.check(ready, "松开漂移后出现小喷窗口（instant_ready）")
	inp.throttle = 0.0
	race.update(DT, inp)
	inp.throttle = 1.0
	inp.throttle_pressed = true
	var instant := false
	race.update(DT, inp)
	for e in race.events:
		if e["type"] == "instant_boost":
			instant = true
	t.check(instant and p.boost_kind == "instant", "窗口内按下油门触发小喷")


## press_at：在剩余倒计时多少秒时第一次按下油门（< 0 表示倒计时开始前就按住）
func _start_case(press_at: float) -> Dictionary:
	var race := _make("village", {"ai_count": 0})
	var inp := KartInput.new()
	var pressed := false
	var evs: Array[String] = []
	if press_at < 0.0:
		inp.throttle = 1.0
		inp.throttle_pressed = true
		pressed = true
	var guard := 0
	while guard < 400:
		guard += 1
		if not pressed and race.phase == "countdown" and race.countdown <= press_at:
			inp.throttle = 1.0
			inp.throttle_pressed = true
			pressed = true
		race.update(DT, inp)
		inp.clear_edges()
		for e in race.events:
			evs.append(e["type"])
		if race.phase == "racing" and race.time > 0.5:
			break
	return {"events": evs, "kind": race.player.boost_kind, "false_start": race.player.false_start}


func _test_start(t: TestUtil) -> void:
	var early := _start_case(-1.0)
	t.check(not "start_boost" in early["events"] and not "false_start" in early["events"], "倒计时前就按住油门：不加速也不算抢跑 %s" % str(early["events"]))
	var too_early := _start_case(2.5)
	t.check(not "start_boost" in too_early["events"] and not "false_start" in too_early["events"], "剩 2.5 s 按下：只是没有起步加速")
	var perfect := _start_case(0.2)
	t.check("start_boost" in perfect["events"] and perfect["kind"] == "start", "剩 0.2 s 按下：完美起步")
	var jump := _start_case(0.6)
	t.check("false_start" in jump["events"] and not "start_boost" in jump["events"], "剩 0.6 s 按下：抢跑 %s" % str(jump["events"]))
	# GO 之后 0.3 s 内按下也算完美起步
	var race := _make("village", {"ai_count": 0})
	var inp := KartInput.new()
	_until_racing(race, inp)
	inp.throttle = 1.0
	inp.throttle_pressed = true
	race.update(DT, inp)
	var got := false
	for e in race.events:
		if e["type"] == "start_boost":
			got = true
	t.check(got, "GO 之后 0.1 s 内按下：完美起步")


func _test_draft(t: TestUtil) -> void:
	var race := _make("village", {"ai_count": 1})
	var inp := KartInput.new()
	_until_racing(race, inp)
	var p := race.player
	var o := race.karts[1]
	o.ai = null
	var tr := race.track
	# 两车朝向完全一致，前车在正前方 6 m
	_place(race, p, 20.0, 25.0)
	var h := p.heading
	var ahead := Vector3(p.x, p.y, p.z) + Vector3(sin(h), 0.0, cos(h)) * 6.0
	var pr := tr.project(ahead.x, ahead.y, ahead.z, -1, TrackProj.new())
	o.reset({"pos": Vector3(ahead.x, pr.y, ahead.z), "heading": h, "s": pr.s})
	o.track_hint = pr.idx
	o.vx = sin(h) * 25.0
	o.vz = cos(h) * 25.0
	o.input.throttle = 0.6
	inp.throttle = 0.6
	var got := false
	for i in 90:
		race.update(DT, inp)
		for e in race.events:
			if e["type"] == "draft" and e["kart"] == p:
				got = true
	t.check(got and p.boost_kind == "draft", "紧跟前车 1.5 s 内触发尾流加速（%s，间距 %.1f m）" % [p.boost_kind, (o.progress - p.progress) * tr.spacing])


func _test_big_dt(t: TestUtil) -> void:
	var race := _make("snow", {"all_ai": true})
	for i in 300:
		race.update(DT, null)
	for i in 20:
		race.update(0.5, null)
	var ok := true
	for k in race.karts:
		if absf(k.lateral) > race.track.wall_offset + 0.01:
			ok = false
	t.check(ok, "喂入 0.5 s 的大 dt 后所有车仍在护墙内")
