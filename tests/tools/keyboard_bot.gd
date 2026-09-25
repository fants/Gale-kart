extends SceneTree
## 模拟键盘玩家：只用数字转向（-1 / 0 / 1）+ 漂移键 + 油门，跑 3 圈，统计用时、撞墙次数、漂移次数、小喷次数。
## godot --headless --path . -s tests/tools/keyboard_bot.gd


func _initialize() -> void:
	for def: Dictionary in TracksData.TRACKS:
		var race := RaceSim.new({"track": TrackData.build(def), "mode": "time", "laps": 3, "skip_intro": true, "seed": 3})
		var p := race.player
		var tr := race.track
		var inp := KartInput.new()
		var t := 0.0
		var walls := 0
		var hard_walls := 0
		var drifts := 0
		var instants := 0
		var prev_throttle := 0.0
		while t < 400.0 and not p.finished:
			# 目标点：赛车线前方
			var look := 8.0 + p.speed * 0.45
			var ts := p.s + look / tr.spacing
			var ti := int(tr.wrap_s(ts))
			var pt := tr.point_at(ts, tr.racing_line[ti] * 0.8)
			var desired := atan2(pt.x - p.x, pt.z - p.z)
			var diff := MathX.wrap_angle(desired - p.heading)
			inp.steer = 0.0
			if absf(diff) > 0.04:
				inp.steer = -signf(diff)
			# 前方弯道急时漂移（按住）
			var ahead_curv := 0.0
			for j in range(2, 22, 2):
				ahead_curv = maxf(ahead_curv, tr.rl_curv[(int(p.s) + j) % tr.n])
			inp.drift = ahead_curv > 1.0 / 42.0 and p.speed > 20.0 and absf(diff) > 0.12
			inp.throttle = 1.0
			inp.brake = 0.0
			if absf(diff) > 0.9:
				inp.throttle = 0.0
				inp.brake = 0.6
			# 松开漂移后重新点一下油门（小喷）
			inp.throttle_pressed = false
			if p.instant_window > 0.0 and prev_throttle > 0.0:
				inp.throttle = 0.0
			elif p.instant_window > 0.0:
				inp.throttle = 1.0
				inp.throttle_pressed = true
			prev_throttle = inp.throttle
			inp.use_pressed = p.nitros > 0 and not p.is_boosting() and ahead_curv < 1.0 / 120.0
			race.update(1.0 / 60.0, inp)
			for e in race.events:
				match e["type"]:
					"wall_hit":
						walls += 1
						if float(e["strength"]) > 0.4:
							hard_walls += 1
					"drift_start": drifts += 1
					"instant_boost": instants += 1
			t += 1.0 / 60.0
		print("%-6s %s  用时 %s  撞墙 %d（重 %d）  漂移 %d  小喷 %d  最快圈 %s" % [def["id"], "完赛" if p.finished else "未完赛", MathX.format_time(p.finish_time if p.finished else t), walls, hard_walls, drifts, instants, MathX.format_time(p.best_lap)])
		race.dispose()
	quit()
