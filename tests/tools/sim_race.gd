extends SceneTree
## 无界面整场 AI 比赛，打印完赛表。
## godot --headless --path . -s tests/tools/sim_race.gd -- [--track=all|village] [--mode=speed|item] [--difficulty=hard] [--laps=3]


func _initialize() -> void:
	var o := {"track": "all", "mode": "speed", "difficulty": "hard", "laps": "3"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=")
			o[kv[0]] = kv[1]
	for def: Dictionary in TracksData.TRACKS:
		if o["track"] != "all" and def["id"] != o["track"]:
			continue
		var race := RaceSim.new({"track": TrackData.build(def), "mode": o["mode"], "laps": int(o["laps"]),
			"difficulty": o["difficulty"], "all_ai": true, "skip_intro": true, "seed": 7})
		var t := 0.0
		var stat := {"cliff_fall": 0, "respawn": 0, "shortcut": 0}
		var on_branch := {}
		while t < 900.0 and not race.all_finished():
			race.update(1.0 / 60.0, null)
			t += 1.0 / 60.0
			for e: Dictionary in race.events:
				if stat.has(e["type"]):
					stat[e["type"]] += 1
			for k in race.karts:
				var b: int = on_branch.get(k.index, -1)
				if k.branch != b and k.branch >= 0 and race.track.branches[k.branch].kind == "shortcut":
					stat["shortcut"] += 1
				on_branch[k.index] = k.branch
		print("== %s（%s，%s）  掉崖 %d  重生 %d  走近道 %d" % [def["name"], o["mode"], o["difficulty"], stat["cliff_fall"], stat["respawn"], stat["shortcut"]])
		for r in race.results():
			var k: KartSim = r["kart"]
			print("  %d. %-4s %-4s %s  最快圈 %s%s" % [r["rank"], k.name, k.kart_def["name"], MathX.format_time(r["time"]), MathX.format_time(k.best_lap), "（估算）" if r["estimated"] else ""])
		race.dispose()
	quit()
