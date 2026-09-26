extends SceneTree
## 特效画廊：在一段赛道上依次触发每种 burst、持续特效、道具实体、车身状态与屏幕效果，各截一张图。
## godot --path . --fixed-fps 60 -s tests/tools/fx_gallery.gd -- --out=/abs/dir
##       [--track=village] [--only=explosion,shield] [--size=1600x900] [--quality=high]
## 不依赖自动加载单例（-s 模式下不可用）：自己搭 RaceWorld / RaceSim / Effects / ItemView / ScreenFx，车辆用简化替身。

const DT := 1.0 / 60.0


## KartView 的简化替身（KartView 引用了 AudioMgr，-s 模式下无法编译）：车模 + 状态特效 + 后轮 / 排气位置
class GalleryKart:
	extends Node3D
	var kart: KartSim
	var model: KartModel
	var status_fx: KartStatusFx

	func setup(k: KartSim) -> void:
		kart = k
		model = KartModel.create(k.kart_def["id"], k.character["id"], k.paint["id"])
		add_child(model)
		status_fx = KartStatusFx.new()
		add_child(status_fx)
		status_fx.setup(k)

	func update_view(dt: float, time: float, _alpha: float, _cam_pos: Vector3) -> void:
		var k := kart
		position = Vector3(k.x, k.y, k.z)
		rotation = Vector3(0.0, k.heading, 0.0)
		var lift := 0.0
		var roll := 0.0
		var pitch := 0.0
		if k.bubble > 0.0:
			var u := 1.0 - k.bubble / 1.6
			lift = sin(minf(1.0, u * 3.0) * PI * 0.5) * 1.6 * (1.0 if u < 0.85 else (1.0 - u) / 0.15)
			roll = sin(time * 4.0) * 0.2
			pitch = cos(time * 3.0) * 0.15
		model.set_body_pose(roll, pitch, 0.0, lift)
		model.set_wheel_state(0.0, k.speed / 0.33 * dt)
		status_fx.update_view(dt, time, lift)

	func rear_world(side: int) -> Vector3:
		return global_transform * model.rear_local(side)

	func exhaust_world(i: int) -> Vector3:
		return global_transform * model.exhaust_local(i)


var out_dir := ""
var only: PackedStringArray = []
var quality := "high"
var track: TrackData
var race: RaceSim
var world: RaceWorld
var effects: Effects
var item_view: ItemView
var screen_fx: ScreenFx
var cam: Camera3D
var rig: CameraRig
var views: Array[GalleryKart] = []
var time := 0.0
var show_items := false
var focus: KartSim = null
var chase := false
var stage_s := 0.0
var _emit_karts: Array[KartSim] = []
var _moving := {}
var _shot_count := 0
## 上一帧画廊逻辑（车辆 / 道具 / 特效更新与发射）耗时
var _logic_ms := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := "village"
	var size := Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--track="):
			track_id = a.substr(8)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--quality="):
			quality = a.substr(10)
		elif a.begins_with("--size="):
			var wh := a.substr(7).split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("fx_gallery")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(size)

	track = TrackData.build(TracksData.track_by_id(track_id))
	var terrain := TerrainData.create(track)
	world = RaceWorld.new()
	root.add_child(world)
	world.build(track, terrain, quality, "item")
	race = RaceSim.new({"track": track, "mode": "item", "laps": 3, "difficulty": "normal",
		"player": {}, "seed": 7, "all_ai": true, "skip_intro": true})
	effects = Effects.new()
	root.add_child(effects)
	effects.setup(quality, track.theme)
	item_view = ItemView.new()
	root.add_child(item_view)
	item_view.setup(track)
	for k in race.karts:
		var v := GalleryKart.new()
		root.add_child(v)
		v.setup(k)
		v.visible = false
		views.append(v)
	cam = Camera3D.new()
	cam.near = 0.15
	cam.far = 2500.0
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()
	rig = CameraRig.new(cam)
	screen_fx = ScreenFx.new()
	root.add_child(screen_fx)
	screen_fx.setup()
	EnvironmentFactory.apply_viewport_quality(root, quality)
	stage_s = _find_straight()
	print("画廊：赛道 %s，舞台 s=%.1f，输出 %s" % [track_id, stage_s, out_dir])
	for i in 10:
		await process_frame

	for kind: String in ["boost", "instant", "wall", "kart", "land", "shards", "explosion", "splash", "banana",
			"shield", "thunder", "respawn", "confetti", "spark_hit"]:
		if _want("burst_" + kind):
			await _shot_burst(kind)
	for kind: String in ["drift", "drift_blue", "nitro", "pad", "dust", "wind"]:
		if _want("cont_" + kind):
			await _shot_continuous(kind)
	for kind: String in ["boxes", "missile", "water_bomb", "water_zone", "banana", "water_fly"]:
		if _want("item_" + kind):
			await _shot_item(kind)
	for kind: String in ["shield", "bubble", "dizzy", "cloud", "ufo", "magnet", "locked", "lineup"]:
		if _want("status_" + kind):
			await _shot_status(kind)
	for kind: String in ["nitro", "lock", "cloud", "bubble", "cruise"]:
		if _want("screen_" + kind):
			await _shot_screen(kind)
	if _want("stress"):
		await _shot_stress()
	print("画廊完成：%d 张" % _shot_count)
	quit()


func _want(shot_name: String) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if shot_name.contains(o):
			return true
	return false


## 找一段比较直、地势平的路段做舞台
func _find_straight() -> float:
	var best := 0.0
	var best_c := INF
	var step := maxi(1, int(track.n / 80.0))
	for i in range(0, track.n, step):
		var c := 0.0
		for j in 12:
			c += absf(track.curv[(i + j * 2) % track.n])
		if c < best_c:
			best_c = c
			best = float(i)
	return best + 4.0


# —————————————————— 舞台坐标 ——————————————————

## 舞台局部坐标（x 右、y 上、z 沿赛道前进）→ 世界坐标，贴着路面
func _stage(local: Vector3, s_off := 0.0) -> Vector3:
	var s := stage_s + s_off + local.z / track.spacing
	var p := track.point_at(s, local.x)
	return p + Vector3(0.0, local.y, 0.0)


func _stage_heading(s_off := 0.0) -> float:
	return track.heading_at(stage_s + s_off)


func _look(from_local: Vector3, at_local: Vector3, fov := 60.0) -> void:
	chase = false
	cam.fov = fov
	cam.global_position = _stage(from_local)
	cam.look_at(_stage(at_local), Vector3.UP)


func _place(k: KartSim, local: Vector3, yaw_off := 0.0) -> void:
	var p := _stage(local)
	k.x = p.x
	k.y = p.y
	k.z = p.z
	k.heading = _stage_heading(local.z / track.spacing) + yaw_off
	k.prev_x = k.x
	k.prev_y = k.y
	k.prev_z = k.z
	k.prev_heading = k.heading
	k.vx = 0.0
	k.vz = 0.0
	k.speed = 0.0
	k.on_ground = true
	views[k.index].visible = true


func _reset_scene() -> void:
	effects.clear()
	screen_fx.reset()
	show_items = false
	focus = null
	chase = false
	_emit_karts.clear()
	_moving.clear()
	var it := race.items
	it.missiles.clear()
	it.water_bombs.clear()
	it.water_zones.clear()
	it.bananas.clear()
	it.water_flies.clear()
	for k in race.karts:
		k.shield = 0.0
		k.bubble = 0.0
		k.dizzy = 0.0
		k.cloud = 0.0
		k.ufo = 0.0
		k.magnet = 0.0
		k.magnet_target = null
		k.locked_by = 0.0
		k.spin = 0.0
		k.flip = 0.0
		k.invuln = 0.0
		k.boost_time = 0.0
		k.boost_kind = ""
		k.drifting = false
		k.fake_drift = 0.0
		k.drift_dir = 0.0
		k.drift_time = 0.0
		k.offroad = false
		k.in_draft = false
		k.speed = 0.0
		views[k.index].visible = false


## 推进若干帧：更新车辆表现、道具表现、持续特效、屏幕效果
func _step(frames: int, per_frame := Callable()) -> void:
	for i in frames:
		var t0 := Time.get_ticks_usec()
		time += DT
		if per_frame.is_valid():
			per_frame.call(DT)
		for k in race.karts:
			_tick_status(k, DT)
		for k: KartSim in _moving:
			_advance(k, _moving[k], DT)
		for v in views:
			if v.visible:
				v.update_view(DT, time, 1.0, cam.global_position)
		item_view.update_view(DT, time, race.items if show_items else null, effects)
		_emit_continuous(DT)
		if chase and focus:
			rig.chase(focus, DT, 1.0)
		world.update_view(DT, time, cam)
		screen_fx.update_view(DT, time, focus)
		_logic_ms = (Time.get_ticks_usec() - t0) / 1000.0
		await process_frame


## 状态计时照常流逝（这样才有出现动画），但不低于展示用的下限
func _tick_status(k: KartSim, dt: float) -> void:
	if k.shield > 0.0:
		k.shield = maxf(k.shield - dt, 2.0)
	if k.bubble > 0.0:
		k.bubble = maxf(k.bubble - dt, 0.5)
	if k.dizzy > 0.0:
		k.dizzy = maxf(k.dizzy - dt, 1.0)
	if k.cloud > 0.0:
		k.cloud = maxf(k.cloud - dt, 2.0)
	if k.ufo > 0.0:
		k.ufo = maxf(k.ufo - dt, 1.2)
	if k.magnet > 0.0:
		k.magnet = maxf(k.magnet - dt, 1.0)
	if k.locked_by > 0.0:
		k.locked_by = 0.25


## 让车沿赛道匀速前进（lat 为横向偏移，右正）
func _advance(k: KartSim, spec: Dictionary, dt: float) -> void:
	var sp: float = spec["speed"]
	var s: float = spec["s"] + sp * dt / track.spacing
	spec["s"] = s
	var lat: float = spec.get("lat", 0.0)
	if spec.has("weave"):
		lat += sin(time * 1.3) * float(spec["weave"])
	var p := track.point_at(s, lat)
	k.prev_x = k.x
	k.prev_y = k.y
	k.prev_z = k.z
	k.prev_heading = k.heading
	k.x = p.x
	k.y = p.y
	k.z = p.z
	k.heading = track.heading_at(s) + float(spec.get("yaw", 0.0))
	var fwd := Vector3(sin(track.heading_at(s)), 0.0, cos(track.heading_at(s)))
	k.vx = fwd.x * sp
	k.vz = fwd.z * sp
	k.speed = sp
	k.forward_speed = sp


## 与 RaceController._emit_continuous 相同的持续特效发射
func _emit_continuous(dt: float) -> void:
	for k in _emit_karts:
		var kv := views[k.index]
		var kp := Vector3(k.x, k.y, k.z)
		var drifting := (k.drifting or k.fake_drift != 0.0) and k.on_ground and k.speed > 8.0
		var id := k.index * 2
		var fwd := Vector3(sin(k.heading), 0.0, cos(k.heading))
		if drifting:
			var rate := 34.0 if k.drifting else 18.0
			for side: int in [-1, 1]:
				var rp := kv.rear_world(side)
				for i in effects.rate_count("s%d%d" % [id, side], rate, dt):
					effects.smoke(rp, Vector3(k.vx, 0.0, k.vz), 1.2 if track.grip < 1.0 else 1.0)
				effects.skids.add(id + (1 if side > 0 else 0), rp + Vector3(0, 0.04, 0), fwd, 0.34, true)
			if k.drifting:
				var sp := kv.rear_world(int(k.drift_dir))
				var tier := 1 if k.drift_time > KartSim.INSTANT_MIN_DRIFT else 0
				for i in effects.rate_count("ds%d" % id, 30.0, dt):
					effects.drift_spark(sp + Vector3(0, 0.1, 0), tier)
		else:
			effects.skids.add(id, Vector3.ZERO, Vector3.ZERO, 0.0, false)
			effects.skids.add(id + 1, Vector3.ZERO, Vector3.ZERO, 0.0, false)
		if k.is_boosting():
			for e in 2:
				var ep := kv.exhaust_world(e)
				for i in effects.rate_count("f%d%d" % [id, e], 40.0, dt):
					effects.flame(ep, -fwd, k.boost_kind)
		if k.offroad and k.on_ground and k.speed > 6.0:
			var rp2 := kv.rear_world(1)
			for i in effects.rate_count("d%d" % id, 16.0, dt):
				effects.dust(rp2, Vector3(k.vx, 0.0, k.vz))
		if k.in_draft and k.speed > 15.0:
			for i in effects.rate_count("w%d" % id, 14.0, dt):
				effects.wind(kp + Vector3(0, 0.8, 0) + fwd * 1.5, fwd)


func _snap(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("%s.png" % shot_name)
	img.save_png(path)
	_shot_count += 1
	print("  %s  (FPS %d, t=%.1fs)" % [path, Engine.get_frames_per_second(), Time.get_ticks_msec() / 1000.0])


# —————————————————— 各类镜头 ——————————————————

func _shot_burst(kind: String) -> void:
	_reset_scene()
	var at := Vector3(0.0, 0.0, 0.0)
	var frames := 5
	var cam_from := Vector3(-5.0, 2.6, 5.5)
	var look_at := Vector3(0.0, 1.2, 0.0)
	var opts := {}
	match kind:
		"boost", "instant", "shield", "thunder", "respawn", "kart", "banana":
			_place(race.karts[0], Vector3.ZERO)
			frames = 6
		"wall":
			at = Vector3(2.0, 0.0, 0.0)
			opts = {"strength": 1.0}
			frames = 4
		"land":
			_place(race.karts[0], Vector3.ZERO)
			opts = {"strength": 1.0}
			frames = 8
		"shards":
			at = Vector3(0.0, 1.3, 0.0)
			frames = 7
		"explosion":
			at = Vector3(0.0, 1.0, 0.0)
			cam_from = Vector3(-8.0, 3.5, 9.5)
			look_at = Vector3(0.0, 2.0, 0.0)
			frames = 7
		"splash":
			cam_from = Vector3(-8.0, 3.5, 9.5)
			look_at = Vector3(0.0, 2.5, 0.0)
			frames = 14
		"confetti":
			_place(race.karts[0], Vector3.ZERO)
			opts = {"count": 140}
			cam_from = Vector3(-8.0, 3.5, 10.0)
			look_at = Vector3(0.0, 3.0, 0.0)
			frames = 40
		"respawn":
			frames = 10
	if kind == "thunder":
		race.karts[0].dizzy = 2.0
	_look(cam_from, look_at)
	await _step(3)
	var p := _stage(at)
	if kind in ["boost", "instant", "shield", "thunder", "kart", "land", "confetti"]:
		p = Vector3(race.karts[0].x, race.karts[0].y, race.karts[0].z)
	if kind == "respawn":
		p += Vector3(0.0, 0.6, 0.0)
	effects.burst(kind, p, opts)
	await _step(frames)
	await _snap("burst_%s" % kind)
	if kind in ["explosion", "splash", "confetti", "shards"]:
		await _step(22 if kind != "confetti" else 70)
		await _snap("burst_%s_late" % kind)


func _shot_continuous(kind: String) -> void:
	_reset_scene()
	var k := race.karts[1]
	_place(k, Vector3(0.0, 0.0, 0.0), 0.0)
	_emit_karts.append(k)
	var spec := {"s": stage_s, "speed": 24.0, "lat": 0.0}
	match kind:
		"drift", "drift_blue":
			k.drifting = true
			k.drift_dir = 1.0
			k.drift_time = 0.1 if kind == "drift" else 1.0
			spec["yaw"] = 0.45
			spec["weave"] = 2.5
		"nitro":
			k.boost_time = 99.0
			k.boost_kind = "nitro"
			spec["speed"] = 40.0
		"pad":
			k.boost_time = 99.0
			k.boost_kind = "pad"
			spec["speed"] = 36.0
		"dust":
			k.offroad = true
			spec["lat"] = -(track.half_width + 1.5)
		"wind":
			k.in_draft = true
			spec["speed"] = 34.0
	_moving[k] = spec
	focus = k
	chase = true
	rig.initialized = false
	await _step(70)
	# 从侧后方看
	chase = false
	var kp := Vector3(k.x, k.y, k.z)
	var fwd := Vector3(sin(k.heading), 0.0, cos(k.heading))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	cam.fov = 62.0
	# 从右后方看（越野尘土那一幕车在左侧路外，相机在赛道内侧，不会被护墙挡住）
	var side := 3.5
	cam.global_position = kp - fwd * 7.5 + right * side + Vector3(0.0, 2.6, 0.0)
	cam.look_at(kp + fwd * 1.5 + Vector3(0.0, 0.7, 0.0), Vector3.UP)
	await _step(2, func(_dt: float) -> void:
		var kp2 := Vector3(k.x, k.y, k.z)
		var f2 := Vector3(sin(k.heading), 0.0, cos(k.heading))
		var r2 := Vector3(-f2.z, 0.0, f2.x)
		cam.global_position = kp2 - f2 * 7.5 + r2 * side + Vector3(0.0, 2.6, 0.0)
		cam.look_at(kp2 + f2 * 1.5 + Vector3(0.0, 0.7, 0.0), Vector3.UP))
	await _snap("cont_%s" % kind)


func _shot_item(kind: String) -> void:
	_reset_scene()
	show_items = true
	var it := race.items
	match kind:
		"boxes":
			var b: Dictionary = it.boxes[0]
			var bp: Vector3 = b["pos"]
			var s0: float = b["s"]
			var h := track.heading_at(s0)
			var fwd := Vector3(sin(h), 0.0, cos(h))
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			chase = false
			cam.fov = 60.0
			cam.global_position = bp - fwd * 6.0 + right * 1.5 + Vector3(0.0, 2.4, 0.0)
			cam.look_at(bp + Vector3(0.0, 1.3, 0.0), Vector3.UP)
			# 第 2 个箱子刚被拾取，第 3 个在弹出
			if it.boxes.size() > 2:
				it.boxes[1]["active"] = false
			await _step(40)
			if it.boxes.size() > 2:
				it.boxes[2]["active"] = false
			await _step(20)
			if it.boxes.size() > 2:
				it.boxes[2]["active"] = true
			await _step(5)
			await _snap("item_boxes")
			for bb in it.boxes:
				bb["active"] = true
			return
		"missile":
			var m := {"id": 9001, "pos": _stage(Vector3(0, 1, -30)), "prev_pos": _stage(Vector3(0, 1, -31)), "target": null, "age": 0.0}
			it.missiles.append(m)
			_look(Vector3(-3.5, 1.8, 2.0), Vector3(0.0, 1.1, -4.0))
			var st := {"z": -30.0}
			await _step(46, func(dt: float) -> void:
				var z: float = st["z"] + 40.0 * dt
				st["z"] = z
				m["prev_pos"] = m["pos"]
				m["pos"] = _stage(Vector3(sin(z * 0.15) * 1.5, 1.0, z))
				m["age"] = float(m["age"]) + dt)
			await _snap("item_missile")
		"water_bomb":
			var w := {"id": 9002, "pos": _stage(Vector3(0, 2, 0))}
			it.water_bombs.append(w)
			_look(Vector3(-4.5, 2.5, -4.0), Vector3(0.0, 2.2, 1.0))
			var st2 := {"u": 0.0}
			await _step(24, func(dt: float) -> void:
				var u: float = st2["u"] + dt / 0.75
				st2["u"] = u
				w["pos"] = _stage(Vector3(0.0, 1.2 + sin(clampf(u, 0.0, 1.0) * PI) * 2.0, -4.0 + u * 8.0)))
			await _snap("item_water_bomb")
		"water_zone":
			var zn := {"id": 9003, "pos": _stage(Vector3.ZERO), "radius": 4.4, "life": 3.2, "age": 0.0}
			it.water_zones.append(zn)
			_look(Vector3(-9.0, 4.5, -14.0), Vector3(0.0, 3.2, 0.0))
			await _step(50, func(dt: float) -> void:
				zn["age"] = float(zn["age"]) + dt
				zn["life"] = float(zn["life"]) - dt)
			await _snap("item_water_zone")
		"banana":
			for i in 3:
				it.bananas.append({"id": 9010 + i, "pos": _stage(Vector3(-2.5 + i * 2.5, 0.0, i * 1.5)), "spin": i * 2.0, "age": 1.0})
			_look(Vector3(-2.0, 2.0, -5.0), Vector3(0.0, 0.3, 1.0))
			await _step(10)
			await _snap("item_banana")
		"water_fly":
			var f := {"id": 9020, "pos": _stage(Vector3(0, 1, -20)), "prev_pos": _stage(Vector3(0, 1, -21)), "target": null, "age": 0.0}
			it.water_flies.append(f)
			_look(Vector3(-3.0, 2.0, 2.0), Vector3(0.0, 1.3, -3.0))
			var st3 := {"z": -20.0}
			await _step(46, func(dt: float) -> void:
				var z2: float = st3["z"] + 20.0 * dt
				st3["z"] = z2
				f["prev_pos"] = f["pos"]
				f["pos"] = _stage(Vector3(sin(z2 * 0.2), 1.0, z2)))
			await _snap("item_water_fly")


func _shot_status(kind: String) -> void:
	_reset_scene()
	var k := race.karts[2]
	_place(k, Vector3.ZERO)
	var cam_from := Vector3(-5.5, 2.6, 5.5)
	var look_at := Vector3(0.0, 1.4, 0.0)
	var frames := 30
	match kind:
		"shield":
			k.shield = 3.6
		"bubble":
			k.bubble = 1.6
			frames = 30
		"dizzy":
			k.dizzy = 2.0
		"cloud":
			k.cloud = 5.0
			cam_from = Vector3(-6.5, 3.2, 7.0)
			look_at = Vector3(0.0, 2.6, 0.0)
			frames = 40
		"ufo":
			k.ufo = 3.0
			cam_from = Vector3(-8.0, 3.0, 8.5)
			look_at = Vector3(0.0, 3.2, 0.0)
			frames = 60
		"magnet":
			var t := race.karts[3]
			_place(t, Vector3(0.5, 0.0, 12.0))
			k.magnet = 3.0
			k.magnet_target = t
			k.boost_time = 3.0
			k.boost_kind = "magnet"
			_emit_karts.append(k)
			cam_from = Vector3(-6.0, 3.5, -5.0)
			look_at = Vector3(0.0, 1.0, 5.0)
		"locked":
			k.locked_by = 0.25
		"lineup":
			await _shot_lineup()
			return
	_look(cam_from, look_at)
	await _step(frames, func(_dt: float) -> void:
		if kind == "locked":
			k.locked_by = 0.25
		if kind == "bubble":
			k.bubble = maxf(0.3, k.bubble - _dt))
	await _snap("status_%s" % kind)


## 所有状态并排：护盾 水泡 眩晕 乌云 飞碟 磁铁 锁定
func _shot_lineup() -> void:
	var names := ["shield", "bubble", "dizzy", "cloud", "ufo", "magnet", "locked"]
	for i in names.size():
		var k := race.karts[i]
		_place(k, Vector3(-9.0 + i * 3.0, 0.0, 0.0))
		match names[i]:
			"shield": k.shield = 3.6
			"bubble": k.bubble = 1.6
			"dizzy": k.dizzy = 2.0
			"cloud": k.cloud = 5.0
			"ufo": k.ufo = 3.0
			"magnet":
				k.magnet = 3.0
				k.magnet_target = race.karts[7]
			"locked": k.locked_by = 0.25
	_place(race.karts[7], Vector3(12.0, 0.0, 16.0))
	_look(Vector3(0.0, 4.5, 17.0), Vector3(0.0, 2.2, 0.0), 70.0)
	await _step(40, func(_dt: float) -> void:
		race.karts[1].bubble = maxf(0.4, race.karts[1].bubble - _dt)
		race.karts[6].locked_by = 0.25)
	await _snap("status_lineup")


func _shot_screen(kind: String) -> void:
	_reset_scene()
	var k := race.karts[0]
	_place(k, Vector3.ZERO)
	_emit_karts.append(k)
	var spec := {"s": stage_s - 20.0, "speed": 30.0, "lat": 0.0}
	match kind:
		"nitro":
			k.boost_time = 99.0
			k.boost_kind = "nitro"
			spec["speed"] = 46.0
		"lock":
			k.locked_by = 0.25
		"cloud":
			k.cloud = 5.0
		"bubble":
			k.bubble = 1.6
			spec["speed"] = 3.0
		"cruise":
			spec["speed"] = 36.0
	# 前面放一辆车做参照
	var other := race.karts[4]
	_place(other, Vector3(2.0, 0.0, 0.0))
	_moving[other] = {"s": stage_s - 20.0 + 12.0 / track.spacing, "speed": spec["speed"] * 0.97, "lat": 2.5}
	_emit_karts.append(other)
	_moving[k] = spec
	focus = k
	chase = true
	rig.initialized = false
	await _step(60, func(_dt: float) -> void:
		if kind == "lock":
			k.locked_by = 0.25
		if kind == "bubble":
			k.bubble = maxf(0.5, k.bubble - _dt))
	await _snap("screen_%s" % kind)


## 压力测试：8 辆车同屏漂移 + 加速，道具实体与各种爆发不停触发，统计真实帧时间
func _shot_stress() -> void:
	_reset_scene()
	show_items = true
	var it := race.items
	for i in race.karts.size():
		var k := race.karts[i]
		_place(k, Vector3((i % 3 - 1) * 3.5, 0.0, -floorf(i / 3.0) * 6.0))
		_emit_karts.append(k)
		k.drifting = i % 2 == 0
		k.drift_dir = 1.0
		k.drift_time = 1.0
		k.fake_drift = 0.0 if k.drifting else 1.0
		k.boost_time = 99.0
		k.boost_kind = ["nitro", "pad", "instant", "magnet"][i % 4]
		k.in_draft = i % 3 == 0
		_moving[k] = {"s": stage_s - floorf(i / 3.0) * 6.0 / track.spacing, "speed": 30.0, "lat": (i % 3 - 1) * 3.5, "yaw": 0.35 if k.drifting else 0.0, "weave": 1.0}
	race.karts[1].shield = 3.6
	race.karts[2].bubble = 1.6
	race.karts[3].cloud = 5.0
	race.karts[4].ufo = 3.0
	race.karts[5].dizzy = 2.0
	race.karts[6].magnet = 3.0
	race.karts[6].magnet_target = race.karts[0]
	race.karts[7].locked_by = 0.25
	focus = race.karts[0]
	chase = true
	rig.initialized = false
	var frame := {"n": 0}
	var times: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var last := {"t": Time.get_ticks_usec()}
	await _step(240, func(_dt: float) -> void:
		var n: int = frame["n"]
		frame["n"] = n + 1
		var now := Time.get_ticks_usec()
		if n > 30:
			times.append((now - int(last["t"])) / 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(_logic_ms)
		last["t"] = now
		var lead := race.karts[0]
		var ahead := Vector3(lead.x, lead.y, lead.z) + Vector3(sin(lead.heading), 0.0, cos(lead.heading)) * 14.0
		if n % 20 == 0:
			effects.burst("explosion", ahead + Vector3(randf_range(-4, 4), 1.0, 0.0))
		if n % 30 == 5:
			effects.burst("splash", ahead)
			it.water_zones.append({"id": 9500 + n, "pos": ahead, "radius": 4.4, "life": 3.2, "age": 0.0})
		if n % 25 == 10:
			effects.burst("confetti", ahead, {"count": 90})
		if n % 8 == 0:
			effects.burst(["wall", "kart", "land", "shards", "boost", "shield", "thunder", "banana"][int(n / 8.0) % 8], ahead + Vector3(randf_range(-3, 3), 0.5, randf_range(-3, 3)))
		for z in it.water_zones:
			z["age"] = float(z["age"]) + _dt
			z["life"] = float(z["life"]) - _dt
		for i in range(it.water_zones.size() - 1, -1, -1):
			if float(it.water_zones[i]["life"]) <= 0.0:
				it.water_zones.remove_at(i)
		race.karts[7].locked_by = 0.25)
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	gpu.sort()
	cpu.sort()
	var gsum := 0.0
	for g in gpu:
		gsum += g
	var csum := 0.0
	for c in cpu:
		csum += c
	print("  压力测试：%d 帧，帧间隔 平均 %.1f ms / p95 %.1f ms / 最长 %.1f ms；GPU 平均 %.1f ms / p95 %.1f ms；特效逻辑（GDScript）平均 %.1f ms / p95 %.1f ms" % [
		times.size(), sum / times.size(), times[int(times.size() * 0.95)], times[-1],
		gsum / gpu.size(), gpu[int(gpu.size() * 0.95)], csum / cpu.size(), cpu[int(cpu.size() * 0.95)]])
	RenderingServer.viewport_set_measure_render_time(vp, false)
	await _snap("stress")
