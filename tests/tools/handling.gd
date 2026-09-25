extends SceneTree
## 打印每款车的操控数据：0→100 km/h（显示速度）用时、极速、稳态转弯半径、漂移 2 s 集气量。
## godot --headless --path . -s tests/tools/handling.gd

const DT := 1.0 / 120.0
const KMH := 3.6 * 1.4


func _flat_track() -> TrackData:
	# 超大圆形赛道，便于测极速与转弯
	var pts: Array = []
	for i in 16:
		var a := TAU * i / 16.0
		pts.append([sin(a) * 900.0, cos(a) * 900.0, 0.0])
	return TrackData.build({"id": "test", "name": "test", "theme": "village", "half_width": 400.0, "shoulder": 5.0, "points": pts})


func _initialize() -> void:
	var tr := _flat_track()
	for kd: Dictionary in KartsData.KARTS:
		var k := KartSim.new(0, "t", true, kd, KartsData.CHARACTERS[0], KartsData.PAINTS[0])
		var p0 := tr.point_at(0.0, -300.0)
		k.reset({"pos": p0, "heading": tr.heading_at(0.0), "s": 0.0})
		var ctx := {"track": tr, "dt": DT, "events": [], "locked": false, "item_mode": false, "time": 0.0, "speed_mul": 1.0}
		k.input.throttle = 1.0
		var t := 0.0
		var t100 := -1.0
		while t < 20.0:
			k.step(ctx)
			t += DT
			if t100 < 0.0 and k.speed * KMH >= 100.0:
				t100 = t
		var vmax := k.speed
		# 稳态满舵转弯
		k.input.steer = 1.0
		for i in 600:
			k.step(ctx)
		var r_turn := k.speed / maxf(absf(k.yaw_rate), 1e-4)
		# 漂移 2 s
		k.input.steer = 0.0
		for i in 240:
			k.step(ctx)
		k.input.drift = true
		k.input.steer = 1.0
		var g0 := k.gauge + k.nitros
		for i in 240:
			k.step(ctx)
		var gain := k.gauge + k.nitros - g0
		print("%-4s 0→100 %.2f s  极速 %.1f m/s（显示 %d km/h）  满舵半径 %.1f m  漂移 2 s 集气 %.2f" % [kd["name"], t100, vmax, int(vmax * KMH), r_turn, gain])
	quit()
