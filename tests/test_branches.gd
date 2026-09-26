extends RefCounted
## 支路（小路）：森林发卡的崖下绕行路与山顶近道——结构、地形、掉崖落到小路再绕回主路、AI 走近道。

const DT := 1.0 / 60.0


func run(t: TestUtil) -> void:
	var tr := TrackData.build(TracksData.track_by_id("hairpin"))
	_test_structure(t, tr)
	_test_terrain(t, tr)
	_test_cliff_fall(t)
	_test_shortcut(t)
	t.done()


func _branch(tr: TrackData, kind: String) -> int:
	for i in tr.branches.size():
		if tr.branches[i].kind == kind:
			return i
	return -1


func _make(extra := {}) -> RaceSim:
	var o := {"track": TrackData.build(TracksData.track_by_id("hairpin")), "mode": "speed", "laps": 3,
		"difficulty": "hard", "skip_intro": true, "seed": 3, "all_ai": true}
	o.merge(extra, true)
	return RaceSim.new(o)


func _test_structure(t: TestUtil, tr: TrackData) -> void:
	var di := _branch(tr, "detour")
	var si := _branch(tr, "shortcut")
	t.check(di >= 0 and si >= 0, "森林发卡有崖下小路和山顶近道")
	var cliff := 0
	var gaps := {}
	var narrow := INF
	for i in tr.n:
		narrow = minf(narrow, tr.hw[i])
		for side: float in [-1.0, 1.0]:
			var e := tr.edge_at(i, side)
			if e == TrackData.EDGE_CLIFF:
				cliff += 1
			elif e == TrackData.EDGE_GAP:
				gaps[tr.gap_owner(i, side)] = gaps.get(tr.gap_owner(i, side), 0) + 1
	t.check(cliff * tr.spacing > 120.0, "悬崖路长度 %.0f m" % (cliff * tr.spacing))
	t.check(narrow <= 4.0, "最窄处半宽 %.1f m" % narrow)
	for bi in tr.branches.size():
		var b := tr.branches[bi]
		var mono := true
		for k in range(1, b.n):
			mono = mono and b.map_s[k] >= b.map_s[k - 1]
		t.check(mono and b.map_s[b.n - 1] > b.map_s[0], "%s：到主路的进度映射单调（%.3f → %.3f）" % [b.id, b.map_s[0] / tr.n, b.map_s[b.n - 1] / tr.n])
		# 近道两头、绕行路尾端在主路上开口
		var need := 2 if b.kind == "shortcut" else 1
		t.check(int(gaps.get(bi, 0)) * tr.spacing >= need * 8.0, "%s：主路上的开口 %.0f m" % [b.id, int(gaps.get(bi, 0)) * tr.spacing])
		var min_r := INF
		var max_slope := 0.0
		for k in range(3, b.n - 3):
			min_r = minf(min_r, 1.0 / maxf(absf(b.curv[k]), 1e-6))
			max_slope = maxf(max_slope, absf(b.py[k + 1] - b.py[k]) / b.spacing)
		t.check(min_r >= b.wall_offset + 2.0 and max_slope <= 0.18, "%s：最小半径 %.1f，最大坡度 %.3f" % [b.id, min_r, max_slope])
	# 绕行路比主路对应段更长（掉下去要吃亏）
	var d := tr.branches[di]
	var main_len := (d.map_s[d.n - 1] - d.map_s[0]) * tr.spacing
	t.check(d.length > main_len + 20.0, "崖下小路 %.0f m，主路对应段 %.0f m" % [d.length, main_len])


func _test_terrain(t: TestUtil, tr: TrackData) -> void:
	var td := TerrainData.create(tr)
	# 悬崖：崖边外 6 m 处比路面低 6 m 以上
	var min_drop := INF
	for i in tr.n:
		if tr.edge_r[i] != TrackData.EDGE_CLIFF:
			continue
		var p := tr.point_at(float(i), tr.hw[i] + TrackData.CLIFF_LIP + 6.0)
		min_drop = minf(min_drop, tr.py[i] - td.height_at(p.x, p.z))
	t.check(min_drop > 6.0, "悬崖落差至少 %.1f m" % min_drop)
	# 支路两侧地形贴合支路路面
	for b in tr.branches:
		var worst := 0.0
		for k in range(0, b.n, 3):
			for side: float in [-1.0, 1.0]:
				if b.edge_at(k, side) != TrackData.EDGE_WALL:
					continue
				var p := b.point_at(float(k), side * (b.wo[k] + 0.6))
				worst = maxf(worst, absf(td.height_at(p.x, p.z) - (b.py[k] - 0.45)))
		t.check(worst < 1.2, "%s：护墙外侧地形贴合（最大偏差 %.2f m）" % [b.id, worst])


## 从悬崖冲出去：落到崖下小路，速度打折，AI 顺着小路开回主路，全程不重生
func _test_cliff_fall(t: TestUtil) -> void:
	var race := _make()
	while race.phase != "racing":
		race.update(DT, null)
	var tr := race.track
	var di := _branch(tr, "detour")
	var k := race.karts[0]
	var s := 0.45 * tr.n
	var h := tr.heading_at(s) - 0.5          # 已经冲到崖边土沿外，朝右前方（悬崖一侧；航向减小为右转）
	var p0 := tr.point_at(s, tr.hw_at(s) + TrackData.CLIFF_LIP + 0.3)
	k.reset({"pos": p0, "heading": h, "s": s})
	k.track_hint = int(s)
	k.vx = sin(h) * 22.0
	k.vz = cos(h) * 22.0
	k.lap = 1
	k.last_idx = int(s)
	var fell := false
	var landed_branch := -2
	var respawns := 0
	var back := false
	var tt := 0.0
	var min_y := INF
	while tt < 40.0 and not back:
		race.update(DT, null)
		tt += DT
		min_y = minf(min_y, k.y)
		for e: Dictionary in race.events:
			if e.get("kart") == k:
				if e["type"] == "cliff_fall":
					fell = true
				elif e["type"] == "respawn":
					respawns += 1
		if landed_branch == -2 and fell and k.on_ground:
			landed_branch = k.branch
		if landed_branch == di and k.branch == -1:
			back = true
	t.check(fell, "冲出崖边触发掉落")
	t.check(landed_branch == di, "落到崖下小路上（branch=%d，最低 y=%.1f）" % [landed_branch, min_y])
	t.check(back and respawns == 0, "AI 沿小路开回主路（%.1f s，重生 %d 次）" % [tt, respawns])
	var d := tr.branches[di]
	t.check(k.s > d.map_s[d.n - 1] - 25.0 / tr.spacing and k.s < d.map_s[d.n - 1] + 60.0 / tr.spacing, "回到主路的位置在汇入口附近（%.3f）" % (k.s / tr.n))


## AI 选择走近道：从开口进去，从另一头开回主路；进度一路向前
func _test_shortcut(t: TestUtil) -> void:
	var race := _make()
	while race.phase != "racing":
		race.update(DT, null)
	var tr := race.track
	var si := _branch(tr, "shortcut")
	var b := tr.branches[si]
	var k := race.karts[0]
	var s := b.map_s[0] - 40.0 / tr.spacing
	var h := tr.heading_at(s)
	k.reset({"pos": tr.point_at(s, 0.0), "heading": h, "s": s})
	k.track_hint = int(s)
	k.vx = sin(h) * 20.0
	k.vz = cos(h) * 20.0
	k.lap = 1
	k.last_idx = int(s)
	k.ai.route = si
	k.ai._decided = si
	var on_cut := false
	var back := false
	var tt := 0.0
	var prev := k.s
	var backwards := 0.0
	var walls := 0
	while tt < 15.0 and not back:
		race.update(DT, null)
		tt += DT
		var ds := k.s - prev
		if ds < -tr.n * 0.5:
			ds += tr.n
		if ds < 0.0:
			backwards -= ds
		prev = k.s
		for e: Dictionary in race.events:
			if e.get("kart") == k and e["type"] == "wall_hit":
				walls += 1
		if k.branch == si:
			on_cut = true
		elif on_cut and k.branch == -1:
			back = true
	t.check(on_cut, "AI 开进山顶近道")
	t.check(back, "从近道另一头开回主路（%.1f s，撞墙 %d 次）" % [tt, walls])
	t.check(backwards * tr.spacing < 3.0, "进度没有倒退（倒退 %.1f m）" % (backwards * tr.spacing))
