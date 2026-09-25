extends RefCounted
## 赛道几何校验：闭合、转弯半径、路段间距、坡度、发车格 / 道具箱在路面内、特殊路段不重叠、投影可还原。


func run(t: TestUtil) -> void:
	for def: Dictionary in TracksData.TRACKS:
		var t0 := Time.get_ticks_msec()
		var tr := TrackData.build(def)
		var ms := Time.get_ticks_msec() - t0
		var id := tr.id
		var st := TrackData.stats(tr)
		t.check(tr.n >= 200, "%s：采样数 %d ≥ 200" % [id, tr.n])
		var close := Vector3(tr.px[0], tr.py[0], tr.pz[0]).distance_to(Vector3(tr.px[tr.n - 1], tr.py[tr.n - 1], tr.pz[tr.n - 1]))
		t.check(close < tr.spacing * 1.5, "%s：首尾闭合 (%.2f m)" % [id, close])
		t.check(st["min_radius"] >= tr.wall_offset + 2.0, "%s：最小转弯半径 %.1f ≥ %.1f（在 %.2f 处）" % [id, st["min_radius"], tr.wall_offset + 2.0, float(st["min_radius_idx"]) / tr.n])
		t.check(st["min_sep"] >= tr.wall_offset * 2.0 + 4.0, "%s：非相邻路段最小间距 %.1f ≥ %.1f（%.2f / %.2f）" % [id, st["min_sep"], tr.wall_offset * 2.0 + 4.0, float(st["min_sep_pair"][0]) / tr.n, float(st["min_sep_pair"][1]) / tr.n])
		t.check(st["max_slope"] <= 0.18, "%s：最大坡度 %.3f ≤ 0.18" % [id, st["max_slope"]])
		for g in tr.grid:
			t.check(absf(g["lateral"]) < tr.half_width, "%s：发车格在路面内" % id)
		for b in tr.item_boxes:
			t.check(absf(b["lateral"]) < tr.half_width, "%s：道具箱在路面内" % id)
		# 跳台之间、跳台与加速带之间至少间隔 30 m
		var specials: Array = []
		for r in tr.ramps:
			specials.append(["ramp", r["s"]])
		for p in tr.boost_pads:
			specials.append(["pad", p["s"]])
		for i in specials.size():
			for j in range(i + 1, specials.size()):
				if specials[i][0] == "pad" and specials[j][0] == "pad":
					continue
				var ds := absf(specials[i][1] - specials[j][1])
				ds = minf(ds, tr.n - ds) * tr.spacing
				t.check(ds >= 30.0 or (specials[i][0] != specials[j][0] and ds >= 18.0), "%s：%s 与 %s 间隔 %.0f m" % [id, specials[i][0], specials[j][0], ds])
		# 投影还原
		var proj := TrackProj.new()
		var worst_s := 0.0
		var worst_l := 0.0
		for k in 40:
			var s := float(k) / 40.0 * tr.n + 0.37
			var lat := (float(k % 7) / 6.0 * 2.0 - 1.0) * tr.half_width * 0.9
			var p := tr.point_at(s, lat)
			tr.project(p.x, p.y, p.z, -1, proj)
			var ds := absf(proj.s - s)
			ds = minf(ds, tr.n - ds)
			worst_s = maxf(worst_s, ds)
			worst_l = maxf(worst_l, absf(proj.lateral - lat))
		t.check(worst_s < 0.05 * tr.n and worst_l < 0.05, "%s：投影还原（s 误差 %.3f，lateral 误差 %.3f）" % [id, worst_s, worst_l])
		# 地形：赛道旁贴合路面；有河流的赛道，河道处明显低于路面（渲染成桥）
		var terrain := TerrainData.create(tr)
		var worst_follow := 0.0
		for k in 30:
			var s := float(k) / 30.0 * tr.n + 0.5
			var skip := false
			for rv in tr.rivers:
				var dd := absf(s - float(rv["s"]))
				if minf(dd, tr.n - dd) * tr.spacing < rv["width"] + 16.0:
					skip = true
			if skip:
				continue
			var edge := tr.point_at(s, tr.wall_offset + 1.0)
			var road_y := tr.center_y(s)
			worst_follow = maxf(worst_follow, absf(terrain.height_at(edge.x, edge.z) - (road_y - 0.45)))
		if not terrain.flat:
			t.check(worst_follow < 1.2, "%s：护墙外侧地形贴合路面（最大偏差 %.2f m）" % [id, worst_follow])
		for rv in tr.rivers:
			t.check(rv["ext_pos"] >= 60.0 and rv["ext_neg"] >= 60.0, "%s：河流两侧各延伸 ≥ 60 m（%.0f / %.0f）" % [id, rv["ext_pos"], rv["ext_neg"]])
			var rp: Vector3 = rv["pos"]
			var hh := terrain.height_at(rp.x, rp.z)
			t.check(hh < rp.y - 4.0, "%s：河道处地形 %.1f 比路面 %.1f 低 4 m 以上" % [id, hh, rp.y])
			var ramp_end := -1.0
			for r in tr.ramps:
				ramp_end = r["s"] + r["len_s"]
			t.check(ramp_end > 0.0 and float(rv["s"]) > ramp_end and (float(rv["s"]) - ramp_end) * tr.spacing < 20.0, "%s：河流紧跟在跳台之后（间隔 %.1f m）" % [id, (float(rv["s"]) - ramp_end) * tr.spacing])
		print("  %s: %.0f m, n=%d, build %d ms" % [id, tr.length, tr.n, ms])
	t.done()
