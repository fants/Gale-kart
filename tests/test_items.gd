extends RefCounted
## 道具：权重表、道具箱拾取与刷新、各道具效果、护盾、飞碟禁用道具、道具赛整场完赛。

const DT := 1.0 / 60.0


func run(t: TestUtil) -> void:
	_test_weights(t)
	_test_box(t)
	_test_effects(t)
	_test_full_item_race(t)
	t.done()


func _test_weights(t: TestUtil) -> void:
	for frac: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var w := ItemsData.weights_for(frac)
		var total := 0.0
		var known := true
		for k: String in w:
			total += float(w[k])
			if not ItemsData.ITEMS.has(k):
				known = false
		t.check(total > 0.0 and known, "名次比例 %.2f 的权重表合法" % frac)
	t.check(ItemsData.ITEMS.size() == 10, "共 10 种道具")


## 受控场景：所有车关闭 AI，按给定距离（米）摆在村庄起点直道上
func _scene(dists: Array, mode := "item") -> RaceSim:
	var race := RaceSim.new({"track": TrackData.build(TracksData.track_by_id("village")), "mode": mode,
		"laps": 3, "ai_count": dists.size() - 1, "skip_intro": true, "seed": 3})
	var inp := KartInput.new()
	while race.phase != "racing":
		race.update(DT, inp)
	var tr := race.track
	for i in dists.size():
		var k := race.karts[i]
		k.ai = null
		var s: float = float(dists[i]) / tr.spacing
		k.reset({"pos": tr.point_at(s, 0.0), "heading": tr.heading_at(s), "s": s})
		k.track_hint = int(s)
		k.last_idx = int(s)
		k.lap = 1
		k.max_lap = 1
		k.progress = s
		k.invuln = 0.0
	race.update(DT, KartInput.new())
	return race


func _steps(race: RaceSim, seconds: float, watch: Callable = Callable()) -> void:
	var inp := KartInput.new()
	for i in int(seconds / DT):
		race.update(DT, inp)
		if watch.is_valid():
			watch.call()


func _test_box(t: TestUtil) -> void:
	var race := _scene([0.0, 40.0])
	var p := race.player
	var box: Dictionary = race.items.boxes[0]
	var bp: Vector3 = box["pos"]
	p.x = bp.x
	p.z = bp.z
	race.update(DT, KartInput.new())
	t.check(p.items.size() == 1 and p.item_roll > 0.0, "拾取道具箱后得到 1 个道具并开始轮盘")
	t.check(not box["active"], "道具箱被拾取后消失")
	var away := race.track.point_at(0.0, 0.0)
	p.x = away.x
	p.z = away.z
	_steps(race, 2.7)
	t.check(box["active"], "道具箱 2.6 s 后恢复")
	# 第一名永远拿不到雷暴、水苍蝇、飞碟
	var leader_bad := 0
	for i in 300:
		var w := ItemsData.weights_for(0.0)
		w.erase("thunder")
		w.erase("water_fly")
		w.erase("ufo")
		var it := MathX.weighted_pick(w, race.rng)
		if it in ["thunder", "water_fly", "ufo"]:
			leader_bad += 1
	race.dispose()
	race = _scene([0.0, 140.0])
	var lead := race.karts[1]
	t.check(lead.rank == 1, "领先车排名第 1")
	for i in 60:
		lead.items.clear()
		lead.item_roll = 0.0
		var b2: Dictionary = race.items.boxes[1]
		b2["active"] = true
		var b2p: Vector3 = b2["pos"]
		lead.x = b2p.x
		lead.z = b2p.z
		lead.y = b2p.y
		race.items.update(DT)
		if not lead.items.is_empty() and lead.items[0] in ["thunder", "water_fly", "ufo"]:
			leader_bad += 1
	t.check(leader_bad == 0, "第一名拿不到雷暴 / 水苍蝇 / 飞碟")
	race.dispose()


func _test_effects(t: TestUtil) -> void:
	# 导弹命中前车
	var race := _scene([20.0, 70.0])
	var p := race.player
	var o := race.karts[1]
	p.items.assign(["missile"])
	race.items.use(p)
	var st := {"flip": 0.0, "locked": false}
	_steps(race, 3.0, func() -> void:
		st["flip"] = maxf(st["flip"], o.flip)
		st["locked"] = st["locked"] or o.locked_by > 0.0)
	t.check(st["locked"], "导弹锁定目标时目标收到警报")
	t.check(st["flip"] > 0.0, "导弹命中前车后翻车")
	race.dispose()

	# 护盾挡导弹
	race = _scene([20.0, 70.0])
	p = race.player
	o = race.karts[1]
	o.shield = 5.0
	p.items.assign(["missile"])
	race.items.use(p)
	var st2 := {"flip": 0.0, "blocked": false}
	_steps(race, 3.0, func() -> void:
		st2["flip"] = maxf(st2["flip"], o.flip)
		for e in race.events:
			if e["type"] == "shield_block":
				st2["blocked"] = true)
	t.check(st2["blocked"] and st2["flip"] == 0.0, "护盾期间导弹被挡下")
	race.dispose()

	# 香蕉：后车撞上打转
	race = _scene([60.0, 30.0])
	p = race.player
	o = race.karts[1]
	p.items.assign(["banana"])
	race.items.use(p)
	o.x = race.items.bananas[0]["pos"].x
	o.z = race.items.bananas[0]["pos"].z
	var st3 := {"spin": 0.0}
	_steps(race, 0.5, func() -> void: st3["spin"] = maxf(st3["spin"], o.spin))
	t.check(st3["spin"] > 0.0, "碰到香蕉皮后打转")
	race.dispose()

	# 水炸弹：丢出者免疫，别人被困
	race = _scene([20.0, 10.0])
	p = race.player
	o = race.karts[1]
	p.items.assign(["water"])
	race.items.use(p)
	var throw_s := p.s
	_steps(race, ItemSystem.WATER_FLIGHT + 0.15)
	t.check(race.items.water_zones.size() == 1, "水炸弹落地形成水柱")
	var zs: float = race.items.water_zones[0]["s"]
	var w_ahead := fposmod(zs - throw_s, race.track.n) * race.track.spacing
	t.check(absf(w_ahead - ItemSystem.WATER_RANGE) < 3.0, "水炸弹落在丢出点前方 %.0f m" % w_ahead)
	var zp: Vector3 = race.items.water_zones[0]["pos"]
	p.x = zp.x; p.z = zp.z
	o.x = zp.x + 1.0; o.z = zp.z
	var st4 := {"p": 0.0, "o": 0.0}
	_steps(race, 0.2, func() -> void:
		st4["p"] = maxf(st4["p"], p.bubble)
		st4["o"] = maxf(st4["o"], o.bubble))
	t.check(st4["o"] > 0.0 and st4["p"] == 0.0, "水柱困住别人、丢出者免疫")
	race.dispose()

	# 乌云 / 飞碟落到第一名；飞碟期间不能使用道具
	race = _scene([10.0, 80.0, 40.0])
	p = race.player
	var leader := race.karts[1]
	p.items.assign(["cloud", "ufo"])
	race.items.use(p)
	race.items.use(p)
	t.check(leader.cloud > 0.0, "乌云落到第一名头顶")
	t.check(leader.ufo > 0.0, "飞碟落到第一名头顶")
	leader.items.assign(["nitro"])
	leader.input.use_pressed = true
	leader.ai = null
	race.update(DT, KartInput.new())
	t.check(leader.items.size() == 1, "飞碟期间第一名无法使用道具")
	race.dispose()

	# 雷暴只影响排名更靠前的车
	race = _scene([40.0, 80.0, 10.0])
	p = race.player
	var ahead := race.karts[1]
	var behind := race.karts[2]
	p.items.assign(["thunder"])
	race.items.use(p)
	t.check(ahead.dizzy > 0.0 and behind.dizzy == 0.0, "雷暴只让领先者眩晕")
	race.dispose()

	# 磁铁：吸向前车并加速
	race = _scene([20.0, 70.0])
	p = race.player
	p.items.assign(["magnet"])
	race.items.use(p)
	t.check(p.magnet > 0.0 and p.magnet_target == race.karts[1] and p.is_boosting(), "磁铁吸附前车并加速")
	race.dispose()

	# 水苍蝇追上第一名
	race = _scene([10.0, 90.0, 40.0])
	p = race.player
	leader = race.karts[1]
	p.items.assign(["water_fly"])
	race.items.use(p)
	var st5 := {"b": 0.0}
	_steps(race, 4.0, func() -> void: st5["b"] = maxf(st5["b"], leader.bubble))
	t.check(st5["b"] > 0.0, "水苍蝇追上第一名并困住它")
	race.dispose()


func _test_full_item_race(t: TestUtil) -> void:
	for id in ["village", "city"]:
		var race := RaceSim.new({"track": TrackData.build(TracksData.track_by_id(id)), "mode": "item", "laps": 3,
			"difficulty": "hard", "all_ai": true, "skip_intro": true, "seed": 11})
		var used := {}
		var sim_t := 0.0
		while sim_t < 900.0 and not race.all_finished():
			race.update(DT, null)
			sim_t += DT
			for e in race.events:
				if e["type"] == "item_use":
					used[e["item"]] = int(used.get(e["item"], 0)) + 1
		var fin := 0
		for k in race.karts:
			if k.finished:
				fin += 1
		t.check(fin == 8, "%s 道具赛：%d/8 完赛" % [id, fin])
		t.check(used.size() >= 6, "%s 道具赛：AI 用过 %d 种道具 %s" % [id, used.size(), str(used)])
		print("  %s 道具赛 %.0f s，道具使用 %s" % [id, race.time, str(used)])
		race.dispose()
