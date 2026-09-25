extends SceneTree
## 打印每条赛道的几何数据与直道区段，用于设计赛道和摆放跳台 / 加速带。
## godot --headless --path . -s tests/tools/track_stats.gd [-- --track=forest]


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			only = a.substr(8)
	for def: Dictionary in TracksData.TRACKS:
		if only != "" and def["id"] != only:
			continue
		var tr := TrackData.build(def)
		var st := TrackData.stats(tr)
		print("== %s  长度 %.0f m  n=%d  墙偏移 %.1f" % [tr.id, tr.length, tr.n, tr.wall_offset])
		print("   最小半径 %.1f @%.3f   最小间距 %.1f @%.3f/%.3f   最大坡度 %.3f   高度 %.1f..%.1f" % [
			st["min_radius"], float(st["min_radius_idx"]) / tr.n, st["min_sep"],
			float(st["min_sep_pair"][0]) / tr.n, float(st["min_sep_pair"][1]) / tr.n, st["max_slope"],
			tr.bounds["min_y"], tr.bounds["max_y"]])
		print("   包围盒 x %.0f..%.0f  z %.0f..%.0f" % [tr.bounds["min_x"], tr.bounds["max_x"], tr.bounds["min_z"], tr.bounds["max_z"]])
		# 直道：|曲率| < 1/180 连续 ≥ 60 m
		var i := 0
		var runs: Array = []
		var start := -1
		for k in tr.n + 1:
			var idx := k % tr.n
			var straight := absf(tr.curv[idx]) < 1.0 / 180.0 and k < tr.n
			if straight and start < 0:
				start = k
			elif not straight and start >= 0:
				var len := (k - start) * tr.spacing
				if len >= 60.0:
					runs.append("%.3f–%.3f (%.0f m)" % [float(start) / tr.n, float(k) / tr.n, len])
				start = -1
		print("   直道：", ", ".join(runs))
		# 急弯：半径 < 40 m 的区段
		var tight: Array = []
		start = -1
		for k in tr.n + 1:
			var idx := k % tr.n
			var sharp := k < tr.n and 1.0 / maxf(absf(tr.curv[idx]), 1e-6) < 40.0
			if sharp and start < 0:
				start = k
			elif not sharp and start >= 0:
				var rmin := INF
				for q in range(start, k):
					rmin = minf(rmin, 1.0 / maxf(absf(tr.curv[q % tr.n]), 1e-6))
				tight.append("%.3f–%.3f (R%.0f)" % [float(start) / tr.n, float(k) / tr.n, rmin])
				start = -1
		print("   急弯：", ", ".join(tight))
	quit()
