extends RefCounted
## 精彩回放录制：帧数 ≈ 时长 × 30、采样插值（角度走最短弧）、事件时间单调、车辆引用已转成编号、道具快照。

const DT := 1.0 / 60.0


func run(t: TestUtil) -> void:
	var race := RaceSim.new({"track": TrackData.build(TracksData.track_by_id("desert")), "mode": "item", "laps": 1,
		"difficulty": "hard", "all_ai": true, "skip_intro": true, "seed": 5})
	var rec := ReplayRecorder.new(race)
	race.recorder = rec
	var sim_t := 0.0
	while sim_t < 200.0 and not race.all_finished():
		race.update(DT, null)
		rec.capture_events(race.events, race.clock)
		sim_t += DT
	var data := rec.to_data()
	var frames: Array = data["frames"]
	var expect := race.clock - rec.t0
	t.check(absi(frames.size() - roundi(expect * ReplayRecorder.RATE)) <= 2, "帧数 %d ≈ 时长 %.1f s × 30" % [frames.size(), expect])
	t.check(data["kart_count"] == 8 and (data["karts"] as Array).size() == 8, "记录 8 辆车的元数据")
	t.check((data["items"] as Array).size() == frames.size(), "道具赛每帧都有道具快照")
	t.check(data["go_clock"] > 0.0, "记录了 GO 的时刻")
	# 事件
	var mono := true
	var refs_ok := true
	var last := -1.0
	for ev in data["events"]:
		if ev["t"] < last:
			mono = false
		last = ev["t"]
		for key: String in ev["e"]:
			if ev["e"][key] is KartSim:
				refs_ok = false
	t.check(mono and (data["events"] as Array).size() > 20, "事件时间单调递增（%d 个）" % (data["events"] as Array).size())
	t.check(refs_ok, "事件里没有残留 KartSim 引用")
	# 采样：帧上的值精确，帧间线性插值
	var f10: PackedFloat32Array = frames[10]
	var f11: PackedFloat32Array = frames[11]
	var s10 := ReplayRecorder.sample(data, 10.0 / 30.0, 2)
	var smid := ReplayRecorder.sample(data, 10.5 / 30.0, 2)
	var o := 2 * ReplayRecorder.K
	t.near(s10[0], f10[o], 1e-4, "帧上采样 x 精确")
	t.near(smid[0], (f10[o] + f11[o]) * 0.5, 1e-3, "帧间采样 x 线性插值")
	# 角度最短弧：构造一个跨越 ±PI 的数据
	var fake := {"frames": [PackedFloat32Array(), PackedFloat32Array()], "k": ReplayRecorder.K, "rate": 30.0}
	for fi in 2:
		var arr := PackedFloat32Array()
		arr.resize(ReplayRecorder.K)
		arr[3] = 3.1 if fi == 0 else -3.1
		fake["frames"][fi] = arr
	var sa := ReplayRecorder.sample(fake, 0.5 / 30.0, 0)
	t.check(absf(absf(sa[3]) - PI) < 0.05, "朝向插值走最短弧（%.3f）" % sa[3])
	race.dispose()
	t.done()
