extends Node
## 全局流程：菜单 ↔ 比赛的切换、暂停、结算、大奖赛进度。
## 命令行（调试 / 截图 / 演示）：
##   godot --path . -- --race=village [--mode=speed|item|time] [--autopilot] [--quality=high]
##         [--laps=3] [--shots=4,10,20] [--out=/abs/dir] [--quit-after=25] [--size=1920x1080] [--skip-intro]

var main: Node
var current: Node = null
var race_ctl: RaceController = null
var args := {}
var _shots: Array[float] = []
var _shot_t := 0.0
var _quit_after := -1.0


func _ready() -> void:
	InputSetup.setup()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_display_settings()


func _apply_display_settings() -> void:
	var s := Store.settings
	AudioMgr.set_volumes(s.get("music", 0.55), s.get("sfx", 0.85))
	AudioMgr.set_muted(s.get("muted", false))
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if s.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	if args.has("size"):
		var wh: PackedStringArray = str(args["size"]).split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	elif s.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func boot(main_node: Node) -> void:
	main = main_node
	if args.has("race"):
		var sel := Store.selection.duplicate()
		sel["track_id"] = args["race"]
		sel["mode"] = args.get("mode", "speed")
		sel["laps"] = int(args.get("laps", "3"))
		for key in ["character_id", "kart_id", "paint_id", "difficulty"]:
			if args.has(key):
				sel[key] = args[key]
		if args.has("shots"):
			for t in str(args["shots"]).split(","):
				_shots.append(float(t))
		_quit_after = float(args.get("quit-after", "-1"))
		start_race(sel, {"autopilot": args.has("autopilot"), "quality": args.get("quality", Store.settings.get("quality", "high")),
			"skip_intro": args.has("skip-intro"), "seed": 7, "record": args.has("record")})
		return
	goto_title()


func _clear_current() -> void:
	if current and is_instance_valid(current):
		current.queue_free()
	current = null
	race_ctl = null
	get_tree().paused = false


func goto_title() -> void:
	goto_menu("title")


## 菜单界面（Task 10 实现 MenuRoot 之前，先直接开一场比赛）
func goto_menu(_screen := "main") -> void:
	_clear_current()
	start_race(Store.selection.duplicate())


func start_race(sel: Dictionary, opts := {}) -> void:
	_clear_current()
	var ctl := RaceController.new()
	main.add_child(ctl)
	ctl.start(sel, opts)
	ctl.race_finished.connect(_on_race_finished)
	ctl.request.connect(_on_race_request)
	current = ctl
	race_ctl = ctl


func start_gp(_cup_id: String, sel: Dictionary) -> void:
	start_race(sel)


func start_replay(replay: Dictionary) -> void:
	if replay.is_empty():
		return
	_clear_current()
	var rp := ReplayPlayer.new()
	main.add_child(rp)
	rp.start(replay, Store.settings.get("quality", "high"))
	rp.exit_requested.connect(func() -> void: goto_menu("main"))
	current = rp


func _on_race_finished(summary: Dictionary) -> void:
	print("比赛结束：第 %d 名，总用时 %s" % [summary["rank"], MathX.format_time(summary["total"])])
	if args.has("then-replay"):
		start_replay(summary["replay"])


func _on_race_request(action: String) -> void:
	match action:
		"pause":
			race_ctl.set_paused(not race_ctl.paused)


func _process(dt: float) -> void:
	if current == null or not is_instance_valid(current):
		return
	_shot_t += dt
	if not _shots.is_empty() and _shot_t >= _shots[0]:
		var t: float = _shots.pop_front()
		_save_shot("%s_%s_%02d.png" % [args.get("race", "race"), args.get("mode", "speed"), int(t)])
	if _quit_after > 0.0 and _shot_t >= _quit_after:
		get_tree().quit()


func _save_shot(file: String) -> void:
	var dir: String = args.get("out", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(file))
	var fps := Engine.get_frames_per_second()
	print("截图 %s（FPS %d）" % [dir.path_join(file), fps])
	if race_ctl and is_instance_valid(race_ctl) and args.has("debug-cam"):
		var p := race_ctl.race.player
		var cp := race_ctl.camera.global_position
		print("  玩家 %s %s pos=(%.1f,%.1f,%.1f) heading=%.2f 速度=%.1f  相机=(%.1f,%.1f,%.1f) 距离=%.1f" % [p.kart_def["id"], p.character["id"], p.x, p.y, p.z, p.heading, p.speed, cp.x, cp.y, cp.z, cp.distance_to(Vector3(p.x, p.y, p.z))])
	if race_ctl and is_instance_valid(race_ctl) and race_ctl.world:
		print("  构建耗时 ", race_ctl.world.build_log)
