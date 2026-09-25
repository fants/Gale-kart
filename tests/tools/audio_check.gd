extends SceneTree
## 音频自检：检查全部音频流可加载并打印时长，再依次调用 AudioMgr 的所有公开接口。
## godot --headless --path . --import 之后运行：godot --headless --path . -s tests/tools/audio_check.gd

const MGR_PATH := "res://src/autoload/audio_manager.gd"

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var consts := (load(MGR_PATH) as GDScript).get_script_constant_map()
	var sfx_names: Array = consts["SFX_NAMES"]
	var music_names: Array = consts["MUSIC_NAMES"]

	print("== 音频流")
	for n: String in sfx_names:
		_check_stream(consts["SFX_DIR"] + n + ".ogg", n)
	for n: String in music_names:
		_check_stream(consts["MUSIC_DIR"] + n + ".ogg", n)

	# 未进场景树、未初始化的实例：所有接口都应安静返回
	print("== 未入树实例")
	var bare: Node = load(MGR_PATH).new()
	bare.play("nitro")
	bare.play_at("explosion", Vector3.ZERO, Transform3D.IDENTITY)
	bare.play_music("menu")
	bare.set_music_tempo(1.1)
	bare.stop_music()
	bare.update_engine({"speed01": 0.5})
	bare.stop_engine()
	bare.set_paused(true)
	bare.set_paused(false)
	var e3 := bare.make_engine_3d() as AudioStreamPlayer3D
	_expect(e3 != null, "未入树实例 make_engine_3d 返回 null")
	if e3:
		e3.free()
	bare.free()

	var mgr: Node = root.get_node_or_null("AudioMgr")
	if mgr == null:
		print("（-s 模式下没有 AudioMgr 单例，手动实例化）")
		mgr = load(MGR_PATH).new()
		mgr.name = "AudioMgr"
		root.add_child(mgr)
	await process_frame

	print("== 总线")
	for i in AudioServer.bus_count:
		print("  %d %-7s -> %s" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)])
	for b in ["Music", "SFX", "Engine"]:
		_expect(AudioServer.get_bus_index(b) >= 0, "缺少总线 " + b)

	print("== play 全部音效")
	for n: String in sfx_names:
		mgr.play(n)
		mgr.play(n, {"volume": 0.5, "pitch": 1.2, "strength": 0.3})  # 30 ms 内重复，应被忽略
		await process_frame
	mgr.play("wall_hit", {"strength": 0.2, "pan": -0.5})
	mgr.play("no_such_sound")  # 只应给出一次警告

	print("== play_at")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var listener := Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))
	mgr.play_at("explosion", Vector3(10, 0, 5), listener)
	mgr.play_at("kart_hit", Vector3(3, 0, -4), listener, {"strength": 0.6, "range": 40.0})
	mgr.play_at("thunder", Vector3(500, 0, 0), listener)  # 超出范围，不播
	await process_frame
	cam.queue_free()
	await process_frame
	mgr.play_at("land", Vector3(2, 0, 0), listener, {"volume": 0.8})  # 无相机时退化为 2D

	print("== play_music")
	for n: String in music_names:
		mgr.play_music(n, 0.1)
		mgr.play_music(n, 0.1)  # 同名正在播放，忽略
		for i in 3:
			await process_frame
	mgr.set_music_tempo(1.1)
	mgr.play_music("results", 0.0)
	mgr.stop_music(0.05)
	mgr.play_music("menu")

	print("== 引擎")
	var states: Array[Dictionary] = [
		{"speed01": 0.0, "throttle": 0.0},
		{"speed01": 0.4, "throttle": 1.0},
		{"speed01": 1.0, "throttle": 1.0, "boosting": true},
		{"speed01": 1.4, "throttle": 1.0, "drifting": true, "drift_intensity": 0.8},
		{"speed01": 0.9, "throttle": 0.5, "airborne": true},
		{"speed01": 0.7, "throttle": 1.0, "offroad": true, "drifting": true, "drift_intensity": 0.3},
		{"speed01": 0.8, "throttle": 1.0, "surface": "ice", "drifting": true, "drift_intensity": 1.0},
		{"speed01": "bad", "throttle": null, "boosting": 1},
	]
	for st in states:
		mgr.update_engine(st)
		for i in 4:
			await process_frame
	var eng: AudioStreamPlayer = mgr.get_node_or_null("Engine")
	_expect(eng != null and eng.playing, "引擎声没有开始播放")
	if eng:
		print("  引擎 pitch_scale=%.2f volume_db=%.1f" % [eng.pitch_scale, eng.volume_db])

	print("== 暂停 / 音量 / 静音")
	mgr.set_paused(true)
	mgr.play("ui_pause")
	await process_frame
	_expect(eng == null or eng.stream_paused, "暂停后引擎声没有暂停")
	print("  暂停时 Music 总线 %.1f dB" % AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	mgr.set_paused(false)
	_expect(eng == null or not eng.stream_paused, "恢复后引擎声仍在暂停")
	mgr.set_volumes(0.5, 0.8)
	print("  set_volumes(0.5, 0.8)：Music %.1f dB，SFX %.1f dB" % [
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))])
	mgr.set_volumes(0.0, 0.0)
	_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "音乐音量为 0 时总线没有静音")
	mgr.set_volumes(1.0, 1.0)
	mgr.set_muted(true)
	_expect(AudioServer.is_bus_mute(0), "set_muted(true) 没有静音 Master")
	mgr.set_muted(false)

	print("== stop_engine")
	mgr.stop_engine()
	var waited := 0
	while eng != null and eng.playing and waited < 240:
		await process_frame
		waited += 1
	_expect(eng == null or not eng.playing, "stop_engine 后引擎声没有停止")
	print("  %d 帧后停止" % waited)

	print("== make_engine_3d")
	var holder := Node3D.new()
	root.add_child(holder)
	var ai := mgr.make_engine_3d() as AudioStreamPlayer3D
	_expect(ai != null and ai.stream != null, "make_engine_3d 没有设置引擎流")
	if ai:
		print("  unit_size=%.0f max_distance=%.0f volume_db=%.0f bus=%s loop=%s" % [
			ai.unit_size, ai.max_distance, ai.volume_db, ai.bus, ai.stream.get("loop")])
		holder.add_child(ai)
		ai.pitch_scale = 1.3
		ai.play()
		mgr.set_paused(true)
		mgr.set_paused(false)
	await process_frame
	holder.queue_free()
	mgr.stop_music(0.0)
	# 停掉所有播放器并等音频线程回收播放实例，避免退出时报「资源仍在使用」
	for c in mgr.get_children():
		if c.has_method("stop"):
			c.call("stop")
	await create_timer(0.5).timeout

	if _fails.is_empty():
		print("AUDIO CHECK OK")
		quit(0)
	else:
		for f in _fails:
			printerr("失败：" + f)
		quit(1)


func _check_stream(path: String, n: String) -> void:
	var s := load(path) as AudioStream
	if s == null:
		_fails.append("无法加载 " + path)
		print("  %-15s 缺失" % n)
		return
	print("  %-15s %7.3f s" % [n, s.get_length()])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
