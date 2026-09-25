class_name ContinuousFx
extends RefCounted
## 持续特效（比赛与回放共用）：漂移烟与胎痕、漂移火花、尾焰、越野尘土、尾流风线。


static func emit(effects: Effects, kart_views: Array[KartView], cam: Vector3, ice: bool, dt: float) -> void:
	for kv in kart_views:
		var k := kv.kart
		var kp := Vector3(k.x, k.y, k.z)
		var near := kp.distance_squared_to(cam) < 130.0 * 130.0
		var drifting := (k.drifting or k.fake_drift != 0.0) and k.on_ground and k.speed > 8.0
		var id := k.index * 2
		var fwd := Vector3(sin(k.heading), 0.0, cos(k.heading))
		if near and drifting:
			var rate := 34.0 if k.drifting else 18.0
			for side: int in [-1, 1]:
				var rp := kv.rear_world(side)
				for i in effects.rate_count("s%d%d" % [id, side], rate, dt):
					effects.smoke(rp, Vector3(k.vx, 0.0, k.vz), 1.2 if ice else 1.0)
				effects.skids.add(id + (1 if side > 0 else 0), rp + Vector3(0, 0.04, 0), fwd, 0.34, true)
			# 漂移火花：白色，满 0.35 s 后变蓝（可以小喷）
			if k.drifting:
				var sp := kv.rear_world(int(k.drift_dir))
				var tier := 1 if k.drift_time > KartSim.INSTANT_MIN_DRIFT else 0
				for i in effects.rate_count("ds%d" % id, 30.0, dt):
					effects.drift_spark(sp + Vector3(0, 0.1, 0), tier)
		else:
			effects.skids.add(id, Vector3.ZERO, Vector3.ZERO, 0.0, false)
			effects.skids.add(id + 1, Vector3.ZERO, Vector3.ZERO, 0.0, false)
		if near and k.is_boosting():
			for e in 2:
				var ep := kv.exhaust_world(e)
				for i in effects.rate_count("f%d%d" % [id, e], 40.0, dt):
					effects.flame(ep, -fwd, k.boost_kind)
		if near and k.offroad and k.on_ground and k.speed > 6.0:
			var rp2 := kv.rear_world(1)
			for i in effects.rate_count("d%d" % id, 16.0, dt):
				effects.dust(rp2, Vector3(k.vx, 0.0, k.vz))
		if near and k.in_draft and k.speed > 15.0:
			for i in effects.rate_count("w%d" % id, 14.0, dt):
				effects.wind(kp + Vector3(0, 0.8, 0) + fwd * 1.5, fwd)
