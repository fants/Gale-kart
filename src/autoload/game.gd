extends Node
## 全局流程：标题 → 主菜单 → 赛前设置 → 加载 → 比赛 → 结算（颁奖台）→ 回放 / 再来一局 / 下一赛道 / 返回；
## 暂停菜单、大奖赛（四场积分 + 积分榜 + 杯赛颁奖）、计时赛。全局 F11 切换全屏。
## 命令行（调试 / 截图 / 演示）：
##   godot --path . -- --race=village [--mode=speed|item|time] [--autopilot] [--quality=high]
##         [--laps=3] [--shots=4,10,20] [--out=/abs/dir] [--quit-after=25] [--size=1920x1080] [--skip-intro]
##   godot --path . -- --menu=title|main|setup|settings|records|help|results-demo|gp-demo|gp-award-demo|pause-demo|loading-demo
##         [--kind=quick|gp|time] [--tab=0|1] [--shots=1,2] [--out=/abs/dir] [--quit-after=3] [--size=1920x1080]
##   godot --path . -- --flow=smoke [--out=/abs/dir] [--size=1280x800]
##         自动操作一遍：标题 → 主菜单 → 赛前设置 → 开始比赛（自动驾驶 1 圈）→ 冲线 → 结算页，然后退出

## 大奖赛积分（按名次）
const GP_POINTS: Array[int] = [10, 8, 6, 5, 4, 3, 2, 1]

var main: Node
var current: Node = null
var race_ctl: RaceController = null
var menu: MenuRoot = null
var pause_menu: PauseMenu = null
var loading: LoadingScreen = null
var curtain: Curtain = null
var args := {}
## 上一场比赛的选择与选项（再来一局 / 下一赛道 / 重新开始）
var last_sel := {}
var last_opts := {}
var last_summary := {}
## 大奖赛进度（空字典表示不在大奖赛中）
var gp := {}

var _shots: Array[float] = []
var _shot_t := 0.0
var _clock := false
var _quit_after := -1.0
var _starting := false
var _flow: Array = []
var _flow_t := 0.0
## 拖拽流程用：模拟鼠标位置、拖动开始时的转台角度
var _flow_mouse := Vector2.ZERO
var _flow_yaw0 := 0.0


func _ready() -> void:
	InputSetup.setup()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_language()
	_apply_display_settings()


## 语言：设置里的 language，调试时可用 --lang=zh / en 覆盖
func _apply_language() -> void:
	Loc.apply(str(args.get("lang", Store.settings.get("language", "auto"))))


const MIN_WINDOW := Vector2i(1280, 720)


func _apply_display_settings() -> void:
	var s := Store.settings
	AudioMgr.set_volumes(s.get("music", 0.55), s.get("sfx", 0.85))
	AudioMgr.set_muted(s.get("muted", false))
	if DisplayServer.get_name() == "headless":
		return
	# 窗口最小尺寸：再小的话界面（按 1920×1080 布局等比缩放）的文字就看不清了
	get_window().min_size = MIN_WINDOW
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if s.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	if args.has("size"):
		var wh: PackedStringArray = str(args["size"]).split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	elif s.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func boot(main_node: Node) -> void:
	main = main_node
	curtain = Curtain.new()
	main.add_child(curtain)
	if args.has("shots"):
		for t in str(args["shots"]).split(","):
			_shots.append(float(t))
	_quit_after = float(args.get("quit-after", "-1"))
	# 调试 / 截图 / 演示 / 冒烟时存档写到单独的文件，不污染玩家存档
	if args.has("race") or args.has("menu") or args.has("flow"):
		Store.save_path = "user://demo_save.json"
		Store.load_from_disk()
		_apply_language()
	if args.has("race"):
		var sel := Store.selection.duplicate()
		sel["track_id"] = args["race"]
		sel["mode"] = args.get("mode", "speed")
		sel["laps"] = int(args.get("laps", "3"))
		for key in ["character_id", "kart_id", "paint_id", "difficulty"]:
			if args.has(key):
				sel[key] = args[key]
		start_race(sel, {"autopilot": args.has("autopilot"), "quality": args.get("quality", Store.settings.get("quality", "high")),
			"skip_intro": args.has("skip-intro"), "seed": 7, "record": args.has("record")})
		return
	if args.has("menu"):
		_clock = true
		_boot_demo(str(args["menu"]))
		return
	if args.has("flow"):
		_clock = true
		_boot_flow()
		return
	goto_title()


func _clear_current() -> void:
	if current and is_instance_valid(current):
		current.queue_free()
	current = null
	race_ctl = null
	menu = null
	pause_menu = null
	get_tree().paused = false


func goto_title() -> void:
	goto_menu("title")


## 打开菜单页面（title main setup settings records help results gp_standings gp_award）
func goto_menu(screen := "main", params := {}) -> void:
	if screen in ["title", "main", "setup"]:
		gp = {}
	_clear_current()
	menu = MenuRoot.new()
	main.add_child(menu)
	current = menu
	var base: Array[String] = []
	if not screen in ["title", "main", "results", "gp_standings", "gp_award"]:
		base = ["main"]
	menu.open(screen, params, base)
	AudioMgr.play_music("results" if screen in ["results", "gp_standings", "gp_award"] else "menu")


## 开始一场比赛：先显示加载页，等 2 帧再构建比赛（构建约 1 s），然后淡出加载页
func start_race(sel: Dictionary, opts := {}) -> void:
	if _starting:
		return
	_starting = true
	last_sel = sel.duplicate()
	last_opts = opts.duplicate()
	if args.has("autopilot") and not opts.has("autopilot"):
		opts["autopilot"] = true
	# 加载期间菜单不再响应按键
	if menu:
		menu.busy = true
	loading = LoadingScreen.new()
	main.add_child(loading)
	loading.setup(sel, gp)
	await loading.shown
	_clear_current()
	AudioMgr.stop_music(0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	var ctl := RaceController.new()
	main.add_child(ctl)
	# 分帧构建（赛道 / 地形数据在工作线程里算），加载页动画不卡；进度条显示真实进度
	await ctl.start(sel, opts, loading.set_progress)
	ctl.race_finished.connect(_on_race_finished)
	ctl.request.connect(_on_race_request)
	current = ctl
	race_ctl = ctl
	if args.has("race"):
		_clock = true
	loading.finish()
	loading = null
	_starting = false


## 单场比赛（快速比赛 / 计时赛），会结束进行中的大奖赛
func start_single(sel: Dictionary) -> void:
	gp = {}
	start_race(sel)


## 再来一局（同样的选择；大奖赛中重新开始本场）
func restart_race() -> void:
	start_race(last_sel, last_opts)


## 下一条赛道（按赛道列表顺序）
func next_track() -> void:
	var s := last_sel.duplicate()
	var ids: Array[String] = []
	for t in TracksData.TRACKS:
		ids.append(str(t["id"]))
	var i := ids.find(str(s.get("track_id", "village")))
	s["track_id"] = ids[(i + 1) % ids.size()]
	var opts := last_opts.duplicate()
	opts.erase("ai_roster")
	if s.get("mode", "speed") != "time":
		Store.save_selection({"track_id": s["track_id"]})
	start_race(s, opts)


## 退出比赛回到主菜单（放弃大奖赛）
func quit_race() -> void:
	gp = {}
	goto_menu("main")


func quit_game() -> void:
	get_tree().quit()


## 精彩回放：播完 / 按 Esc 回到结算页
func start_replay(replay: Dictionary) -> void:
	if replay.is_empty():
		return
	await curtain.cover()
	_clear_current()
	var rp := ReplayPlayer.new()
	main.add_child(rp)
	rp.start(replay, Store.settings.get("quality", "high"))
	rp.exit_requested.connect(_on_replay_exit)
	current = rp
	curtain.reveal()


func _on_replay_exit() -> void:
	await curtain.cover()
	if last_summary.is_empty():
		goto_menu("main")
	else:
		goto_menu("results", {"summary": last_summary})
	curtain.reveal()


# ———————————————————————— 结算 ————————————————————————

func _on_race_finished(summary: Dictionary) -> void:
	print("比赛结束：第 %d 名，总用时 %s" % [summary["rank"], MathX.format_time(summary["total"])])
	last_summary = summary
	if not gp.is_empty():
		_gp_record(summary)
	if args.has("then-replay"):
		start_replay(summary["replay"])
		return
	await curtain.cover()
	show_results(summary)
	curtain.reveal()


func show_results(summary: Dictionary) -> void:
	goto_menu("results", {"summary": summary})
	var rec: Dictionary = summary.get("record", {})
	var solo: bool = summary.get("solo", false)
	var rank: int = summary.get("rank", 8)
	if rec.get("new_best_total", false) or rec.get("new_best_lap", false):
		AudioMgr.play("new_record")
	elif solo or rank <= 3:
		AudioMgr.play("win")
	else:
		AudioMgr.play("lose")


# ———————————————————————— 暂停 ————————————————————————

func _on_race_request(action: String) -> void:
	match action:
		"pause":
			open_pause()


func open_pause() -> void:
	if race_ctl == null or pause_menu != null or race_ctl.paused or _starting:
		return
	race_ctl.set_paused(true)
	AudioMgr.play("ui_pause")
	pause_menu = PauseMenu.new()
	race_ctl.add_child(pause_menu)
	pause_menu.setup(race_ctl, gp)
	pause_menu.resumed.connect(_on_resumed)
	pause_menu.restart_requested.connect(restart_race)
	pause_menu.quit_requested.connect(quit_race)


func _on_resumed() -> void:
	pause_menu = null
	if race_ctl:
		race_ctl.set_paused(false)


## 设置变化时即时生效的部分（音量、全屏、垂直同步、比赛中的视角）
func apply_settings(patch: Dictionary) -> void:
	Store.save_settings(patch)
	var s := Store.settings
	if patch.has("music") or patch.has("sfx"):
		AudioMgr.set_volumes(float(s["music"]), float(s["sfx"]))
	if patch.has("muted"):
		AudioMgr.set_muted(bool(s["muted"]))
	if DisplayServer.get_name() != "headless":
		if patch.has("fullscreen"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(s["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED)
		if patch.has("vsync"):
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(s["vsync"]) else DisplayServer.VSYNC_DISABLED)
	if patch.has("camera") and race_ctl and race_ctl.rig:
		race_ctl.rig.far = str(s["camera"]) != "near"
	if patch.has("language"):
		_apply_language()
		# 拼接出来的文字要重建页面才会换语言（静态文字自动切换；暂停菜单里的徽章下次打开时更新）
		if menu:
			menu.reload.call_deferred()


func _input(ev: InputEvent) -> void:
	if ev.is_action_pressed("fullscreen") and not ev.is_echo():
		var fs := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		apply_settings({"fullscreen": fs})
		get_viewport().set_input_as_handled()


# ———————————————————————— 大奖赛 ————————————————————————

func start_gp(cup_id: String, sel: Dictionary) -> void:
	var cup := TracksData.cup_by_id(cup_id)
	var tracks: Array = cup["tracks"]
	gp = {
		"cup_id": cup_id, "cup_name": cup["name"], "tracks": tracks.duplicate(), "index": 0,
		"sel": sel.duplicate(), "rule": str(sel.get("gp_rule", "speed")),
		"points": {}, "prev_points": {}, "gains": {}, "info": {}, "roster": [], "results": [], "final": {},
	}
	_start_gp_race()


func _start_gp_race() -> void:
	var s: Dictionary = (gp["sel"] as Dictionary).duplicate()
	var tracks: Array = gp["tracks"]
	var idx: int = gp["index"]
	s["track_id"] = tracks[idx]
	s["mode"] = gp["rule"]
	var opts := {}
	var roster: Array = gp["roster"]
	if not roster.is_empty():
		opts["ai_roster"] = roster
	start_race(s, opts)


## 记录一场大奖赛的积分；第一场保存 AI 阵容，后续场次保持一致
func _gp_record(summary: Dictionary) -> void:
	var points: Dictionary = gp["points"]
	gp["prev_points"] = points.duplicate()
	var roster: Array = gp["roster"]
	if roster.is_empty():
		gp["roster"] = summary.get("ai_roster", [])
	var gains := {}
	var info: Dictionary = gp["info"]
	for r: Dictionary in summary["rows"]:
		var cid: String = r["character_id"]
		var rank: int = r["rank"]
		var pts: int = GP_POINTS[rank - 1] if rank >= 1 and rank <= GP_POINTS.size() else 0
		gains[cid] = pts
		points[cid] = int(points.get(cid, 0)) + pts
		var ch := KartsData.character_by_id(cid)
		info[cid] = {"name": ch["name"], "color": ch["color"], "is_player": r["is_player"],
			"kart_id": r["kart_id"], "paint_id": r["paint_id"], "character_id": cid, "last_rank": rank}
	gp["gains"] = gains
	var results: Array = gp["results"]
	results.append({"track_id": summary["track_id"], "rank": summary["rank"]})


## 积分榜（按积分降序；同分时本场名次靠前者在前）
func gp_standings(use_prev := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if gp.is_empty():
		return out
	var pts: Dictionary = gp["prev_points"] if use_prev else gp["points"]
	var info: Dictionary = gp["info"]
	for cid: String in info:
		var row: Dictionary = (info[cid] as Dictionary).duplicate()
		row["points"] = int(pts.get(cid, 0))
		row["gain"] = int((gp["gains"] as Dictionary).get(cid, 0))
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return int(a["points"]) > int(b["points"])
		return int(a["last_rank"]) < int(b["last_rank"]))
	return out


func gp_is_last_race() -> bool:
	if gp.is_empty():
		return false
	var tracks: Array = gp["tracks"]
	return int(gp["index"]) >= tracks.size() - 1


## 积分榜的「下一场」
func gp_next() -> void:
	gp["index"] = int(gp["index"]) + 1
	_start_gp_race()


## 杯赛结束：提交成绩（只提交一次），返回 {rank, points, improved}
func gp_finish() -> Dictionary:
	var fin: Dictionary = gp.get("final", {})
	if not fin.is_empty():
		return fin
	var st := gp_standings()
	var rank := st.size()
	var pts := 0
	for i in st.size():
		if st[i]["is_player"]:
			rank = i + 1
			pts = int(st[i]["points"])
	var improved := Store.submit_gp(str(gp["cup_id"]), rank, pts)
	fin = {"rank": rank, "points": pts, "improved": improved}
	gp["final"] = fin
	return fin


## 再战一次（同一杯赛，重新计分）
func gp_restart() -> void:
	var cup_id: String = gp.get("cup_id", "star")
	var sel: Dictionary = gp.get("sel", Store.selection)
	start_gp(cup_id, sel)


# ———————————————————————— 命令行：截图 / 演示 / 冒烟 ————————————————————————

func _process(dt: float) -> void:
	if not _clock:
		return
	_shot_t += dt
	if not _shots.is_empty() and _shot_t >= _shots[0]:
		var t: float = _shots.pop_front()
		_save_shot(_shot_name(t))
	if _quit_after > 0.0 and _shot_t >= _quit_after:
		get_tree().quit()
	if not _flow.is_empty():
		_flow_step(dt)


func _shot_name(t: float) -> String:
	if args.has("race"):
		return "%s_%s_%02d.png" % [args.get("race", "race"), args.get("mode", "speed"), int(t)]
	var sz := str(args.get("size", "win"))
	var nm := str(args.get("menu", args.get("flow", "shot")))
	if args.has("kind"):
		nm += "-" + str(args["kind"])
	if args.has("tab"):
		nm += "-tab" + str(args["tab"])
	return "%s_%s_%s.png" % [nm, sz, str(snappedf(t, 0.1)).replace(".", "p")]


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
	if race_ctl and is_instance_valid(race_ctl) and race_ctl.world and args.has("race"):
		print("  构建耗时 ", race_ctl.world.build_log)


## 演示页面：用假数据展示结算、积分榜、颁奖，或在比赛中打开暂停菜单
## 调试：--menu=setup --dump-ui 打印页面里最小宽度超过 700 的控件（查排版溢出）
func _dump_ui() -> void:
	await get_tree().create_timer(2.0).timeout
	var page := menu.current()
	var out: Array[String] = []
	var walk := func(n: Node, depth: int, f: Callable) -> void:
		if n is Control and depth < 9:
			var c := n as Control
			var mw := c.get_combined_minimum_size().x
			if mw > 700.0:
				out.append("%s%s [%s] min=%.0f size=%.0f" % ["  ".repeat(depth), c.name, c.get_class(), mw, c.size.x])
		for ch in n.get_children():
			f.call(ch, depth + 1, f)
	walk.call(page, 0, walk)
	print("[UI]\n" + "\n".join(out))


func _boot_demo(which: String) -> void:
	match which:
		"results-demo":
			last_sel = {"mode": "speed", "track_id": "village", "laps": 3, "character_id": "male-a", "kart_id": "marshmallow", "paint_id": "oodi", "difficulty": "normal"}
			var demo := _demo_summary(2)
			if str(args.get("kind", "")) == "time":
				# 计时赛：单人 + 幽灵车对比
				var row: Dictionary = demo["rows"][1]
				row["rank"] = 1
				demo["rows"] = [row]
				demo["rank"] = 1
				demo["mode"] = "time"
				demo["solo"] = true
				demo["ghost_total"] = float(row["time"]) + 1.234
				demo["record"] = {"new_best_total": true, "new_best_lap": true}
				demo["replay"] = {}
				last_sel["mode"] = "time"
			show_results(demo)
		"gp-demo":
			_demo_gp(2)
			goto_menu("gp_standings")
		"gp-award-demo":
			_demo_gp(3)
			goto_menu("gp_award")
		"pause-demo":
			var sel := Store.selection.duplicate()
			sel["track_id"] = "village"
			sel["mode"] = "item"
			start_race(sel, {"autopilot": true, "skip_intro": true, "seed": 7})
			await get_tree().create_timer(4.5).timeout
			open_pause()
		"loading-demo":
			var sel2 := Store.selection.duplicate()
			sel2["track_id"] = str(args.get("track", "forest"))
			goto_menu("main")
			loading = LoadingScreen.new()
			main.add_child(loading)
			loading.setup(sel2, {})
		"setup":
			goto_menu("setup", {"kind": str(args.get("kind", "quick")), "tab": int(args.get("tab", "0"))})
			if args.has("dump-ui"):
				_dump_ui()
		"help":
			goto_menu("help", {"tab": int(args.get("tab", "0"))})
		_:
			goto_menu(which)


func _demo_summary(player_rank: int) -> Dictionary:
	var rows: Array[Dictionary] = []
	var chars: Array[String] = ["female-b", "male-b", "female-a", "male-c", "female-e", "male-e", "female-c"]
	var karts: Array[String] = ["bolt", "whirl", "rocket", "ironclad", "marshmallow", "bolt", "whirl"]
	var paints: Array[String] = ["ooli", "oopi", "oobi", "oozi", "ooli", "oopi", "oobi"]
	var t := 152.318
	var ai := 0
	for rank in range(1, 9):
		var is_p := rank == player_rank
		var cid := "male-a" if is_p else chars[ai]
		var kid := "marshmallow" if is_p else karts[ai]
		var pid := "oodi" if is_p else paints[ai]
		if not is_p:
			ai += 1
		var kd := KartsData.kart_by_id(kid)
		rows.append({"rank": rank, "name": "你" if is_p else str(KartsData.character_by_id(cid)["name"]), "is_player": is_p,
			"kart_id": kid, "kart_name": kd["name"], "character_id": cid, "paint_id": pid,
			"time": t, "estimated": rank >= 7, "best_lap": 49.8 + rank * 0.37})
		t += 1.2 + rank * 0.9
	var roster: Array[Dictionary] = []
	for i in chars.size():
		roster.append({"character_id": chars[i], "kart_id": karts[i], "paint_id": paints[i]})
	return {"track_id": "village", "track_name": "阳光小镇", "mode": "speed", "laps": 3, "rank": player_rank,
		"total": float(rows[player_rank - 1]["time"]), "best_lap": float(rows[player_rank - 1]["best_lap"]), "rows": rows,
		"record": {"new_best_total": false, "new_best_lap": true}, "ghost_total": -1.0, "solo": false,
		"ai_roster": roster, "replay": {"demo": true}}


func _demo_gp(races: int) -> void:
	var sel := Store.selection.duplicate()
	sel["gp_rule"] = "speed"
	var cup := TracksData.cup_by_id("star")
	var tracks: Array = cup["tracks"]
	gp = {"cup_id": "star", "cup_name": cup["name"], "tracks": tracks.duplicate(), "index": 0, "sel": sel, "rule": "speed",
		"points": {}, "prev_points": {}, "gains": {}, "info": {}, "roster": [], "results": [], "final": {}}
	var ranks: Array[int] = [3, 1, 2]
	for i in races:
		gp["index"] = i
		var s := _demo_summary(ranks[i])
		# 让各场名次有变化：把 AI 的顺序轮换一下
		var rows: Array = s["rows"]
		var ai_rows: Array = []
		for r: Dictionary in rows:
			if not r["is_player"]:
				ai_rows.append(r.duplicate())
		for k in i:
			ai_rows.push_back(ai_rows.pop_front())
		var ai_i := 0
		for j in rows.size():
			var r: Dictionary = rows[j]
			if not r["is_player"]:
				var src: Dictionary = ai_rows[ai_i]
				ai_i += 1
				for key in ["name", "kart_id", "kart_name", "character_id", "paint_id"]:
					r[key] = src[key]
		s["track_id"] = tracks[i]
		s["track_name"] = TracksData.track_by_id(str(tracks[i]))["name"]
		_gp_record(s)
		last_summary = s
	last_sel = sel


## 冒烟流程：按键模拟真实操作（键盘事件经过焦点系统与比赛输入）
##   smoke：标题 → 主菜单 → 赛前设置 → 开始比赛（自动驾驶 1 圈）→ 冲线 → 结算
##   pause：比赛中 Esc 暂停 → Esc 继续 → P 暂停 → 设置子面板 → 返回 → 退出比赛 → 确认 → 主菜单
##   gp：新星杯 4 场（自动驾驶 1 圈）→ 每场结算 → 积分榜 → 颁奖
##   garage：车库页在预览区按住鼠标左右拖动，检查转台旋转与松手惯性
##   records：最佳纪录页按下键滚动，检查能滚到底
##   replay：跑一场 → 结算 → 精彩回放
##   lang：设置页里切换中文 / 英文，页面即时重建
func _boot_flow() -> void:
	args["autopilot"] = "true"
	Store.selection["laps"] = 1
	Store.selection["mode"] = "speed"
	Store.selection["track_id"] = "village"
	var sel := Store.selection.duplicate()
	var which := str(args.get("flow", "smoke"))
	match which:
		"lang":
			# 设置页里切换语言：中文 → English → 中文，页面即时重建
			goto_menu("settings")
			_flow = [
				[0.1, "wait_page", "SettingsScreen"], [0.8, "shot", "lang_zh"],
				[0.1, "set_lang", "en"], [0.8, "check", "lang_en"], [0.1, "shot", "lang_en"],
				[0.1, "key", KEY_ESCAPE], [0.8, "shot", "lang_en_main"],
				[0.1, "set_lang", "zh"], [0.8, "check", "lang_zh"], [0.1, "shot", "lang_zh_main"],
				[0.1, "set_lang", "auto"], [0.3, "done"],
			]
		"records":
			# 最佳纪录：列表可滚动，按下键滚到底能看到大奖赛
			goto_menu("records")
			_flow = [[0.1, "wait_page", "RecordsScreen"], [0.8, "shot", "records_top"]]
			for i in 8:
				_flow.append([0.12, "key", KEY_DOWN])
			_flow.append([0.5, "check", "records_scrolled"])
			_flow.append([0.1, "shot", "records_bottom"])
			_flow.append([0.1, "done"])
		"garage":
			# 车库预览拖拽旋转：按下 → 分 6 次向右拖 300 像素 → 松开，检查转角与惯性
			goto_menu("setup", {"kind": "quick", "tab": 1})
			_flow = [
				[0.1, "wait_page", "SetupScreen"],
				[1.5, "shot", "garage_before"],
				[0.1, "drag", "down", 0.0],
			]
			for i in 6:
				_flow.append([0.05, "drag", "move", 50.0])
			_flow.append([0.05, "check", "garage_rotated"])
			_flow.append([0.0, "drag", "up", 0.0])
			_flow.append([0.4, "check", "garage_inertia"])
			_flow.append([0.1, "shot", "garage_after"])
			_flow.append([0.1, "done"])
		"pause":
			start_single(sel)
			_flow = [
				[0.1, "wait_race"],
				[2.5, "request_pause"],
				[0.6, "check", "paused"],
				[0.1, "shot", "pause"],
				[0.1, "key", KEY_ESCAPE],
				[0.6, "check", "running"],
				[1.0, "request_pause"],
				[0.6, "check", "paused"],
				[0.1, "key", KEY_DOWN],
				[0.1, "key", KEY_DOWN],
				[0.1, "key", KEY_ENTER],
				[0.5, "shot", "pause_settings"],
				[0.1, "key", KEY_ESCAPE],
				[0.4, "check", "paused"],
				[0.1, "key", KEY_DOWN],
				[0.1, "key", KEY_ENTER],
				[0.4, "shot", "pause_confirm"],
				[0.1, "key", KEY_RIGHT],
				[0.3, "shot", "pause_confirm_right"],
				[0.1, "key", KEY_ENTER],
				[1.0, "shot", "pause_after_quit"],
				[0.3, "wait_page", "MainMenu"],
				[1.0, "shot", "pause_back_main"],
				[0.1, "done"],
			]
		"gp":
			var gsel := sel.duplicate()
			gsel["gp_rule"] = "speed"
			start_gp("star", gsel)
			_flow = []
			for i in (TracksData.cup_by_id("star")["tracks"] as Array).size():
				_flow.append([0.1, "wait_page", "ResultsScreen"])
				_flow.append([2.0, "shot", "gp_results_%d" % (i + 1)])
				_flow.append([0.1, "key", KEY_ENTER])
				_flow.append([0.3, "wait_page", "GpStandings"])
				_flow.append([3.4, "shot", "gp_standings_%d" % (i + 1)])
				_flow.append([0.1, "key", KEY_ENTER])
			_flow.append([0.3, "wait_page", "GpAward"])
			_flow.append([2.6, "shot", "gp_award"])
			_flow.append([0.1, "check", "gp_final"])
			_flow.append([0.1, "done"])
		"replay":
			# 跑一场（自动驾驶 1 圈）→ 结算 → 精彩回放，截回放画面
			start_single(sel)
			_flow = [
				[0.1, "wait_race"],
				[0.1, "wait_results"],
				[1.0, "play_replay"],
				[4.0, "shot", "replay"],
				[0.5, "done"],
			]
		_:
			goto_title()
			_flow = [
				[1.4, "shot", "title"],
				[0.2, "key", KEY_ENTER],
				[1.2, "shot", "main"],
				[0.1, "key", KEY_ENTER],
				[1.4, "shot", "setup"],
				[0.1, "focus_start"],
				[0.3, "key", KEY_ENTER],
				[0.6, "shot", "loading"],
				[0.1, "wait_race"],
				[1.0, "shot", "race"],
				[0.1, "wait_results"],
				[2.0, "shot", "results"],
				[0.5, "done"],
			]
	_flow_t = 0.0


func _flow_fail(msg: String) -> void:
	print("流程冒烟：失败——", msg)
	get_tree().quit(1)
	_flow.clear()


func _flow_step(dt: float) -> void:
	var step: Array = _flow[0]
	_flow_t += dt
	var delay: float = step[0]
	if _flow_t < delay:
		return
	var kind: String = step[1]
	match kind:
		"shot":
			_save_shot("flow_%s_%s.png" % [str(step[2]), str(args.get("size", "win"))])
		"key":
			var code: Key = step[2]
			_press_key(code)
		"drag":
			_mouse_drag(str(step[2]), float(step[3]))
		"request_pause":
			# 与比赛里按 Esc / P / Start 走同一条路径（窗口没有焦点时 PlayerInput 不读按键）
			if race_ctl:
				race_ctl.request.emit("pause")
		"focus_start":
			if menu and menu.current() is SetupScreen:
				var ss := menu.current() as SetupScreen
				Widgets.focus_quiet(ss.start_button)
		"wait_race":
			if race_ctl == null or _starting:
				return
			print("流程冒烟：比赛已开始（%s）" % race_ctl.track.name)
		"wait_results":
			if menu == null or not (menu.current() is ResultsScreen):
				return
			print("流程冒烟：结算页已显示")
		"set_lang":
			apply_settings({"language": str(step[2])})
			print("流程冒烟：切换语言 %s" % str(step[2]))
		"play_replay":
			var rs := menu.current() as ResultsScreen if menu else null
			var rep: Dictionary = rs.summary.get("replay", {}) if rs else {}
			if rep.is_empty():
				_flow_fail("结算页没有回放数据")
				return
			start_replay(rep)
			print("流程冒烟：开始播放回放")
		"wait_page":
			var want := str(step[2])
			if menu == null or menu.current() == null or menu.busy:
				if _flow_t > 240.0:
					_flow_fail("等待页面 %s 超时" % want)
				return
			var got := (menu.current().get_script() as Script).get_global_name()
			if got != want:
				if _flow_t > 240.0:
					_flow_fail("等待页面 %s 超时（当前 %s）" % [want, got])
				return
			print("流程冒烟：进入页面 %s" % want)
		"check":
			var what := str(step[2])
			match what:
				"paused":
					if race_ctl == null or not race_ctl.paused or pause_menu == null:
						_flow_fail("应处于暂停状态")
						return
					print("流程冒烟：已暂停，暂停菜单打开")
				"running":
					if race_ctl == null or race_ctl.paused or pause_menu != null:
						_flow_fail("应已继续比赛")
						return
					print("流程冒烟：已继续比赛")
				"lang_en", "lang_zh":
					var want_en := what == "lang_en"
					if Loc.is_en() != want_en or TranslationServer.translate("设置") != ("Settings" if want_en else "设置"):
						_flow_fail("语言没有切换过去（%s）" % Loc.lang)
						return
					print("流程冒烟：当前语言 %s，页面 %s" % [Loc.lang, menu.current().name if menu and menu.current() else "?"])
				"records_scrolled":
					var rs := menu.current() as RecordsScreen if menu else null
					var sb := rs._scroll.get_v_scroll_bar() if rs else null
					if rs == null or sb == null or rs._scroll.scroll_vertical < int(sb.max_value - sb.page) - 2:
						_flow_fail("最佳纪录应能滚到底（当前 %d / %d）" % [rs._scroll.scroll_vertical if rs else -1, int(sb.max_value - sb.page) if sb else -1])
						return
					print("流程冒烟：最佳纪录已滚到底（%d 像素）" % rs._scroll.scroll_vertical)
				"garage_rotated":
					# 窗口里拖 300 像素（换算成页面像素）× 0.011 弧度 / 像素（拖动中自动旋转暂停）
					var g := menu.garage if menu else null
					var turned := g.table.rotation.y - _flow_yaw0 if g else 0.0
					var want := 300.0 / get_viewport().get_final_transform().x.x * GarageStage.DRAG_RAD_PER_PX
					if g == null or not g.dragging or absf(turned - want) > 0.35:
						_flow_fail("拖动后转台应转过约 %.2f 弧度（实际 %.2f，拖拽中 %s）" % [want, turned, str(g.dragging if g else false)])
						return
					print("流程冒烟：拖动 300 像素，转台转过 %.2f 弧度" % turned)
					_flow_yaw0 = g.table.rotation.y
				"garage_inertia":
					var g2 := menu.garage if menu else null
					var more := g2.table.rotation.y - _flow_yaw0 if g2 else 0.0
					if g2 == null or g2.dragging or more <= 0.05:
						_flow_fail("松手后应有同方向的惯性（实际 %.2f）" % more)
						return
					print("流程冒烟：松手后惯性继续转了 %.2f 弧度，已退出拖拽" % more)
				"gp_final":
					var fin: Dictionary = gp.get("final", {})
					if fin.is_empty():
						_flow_fail("大奖赛没有提交成绩")
						return
					print("流程冒烟：大奖赛完成 ", fin, " 积分榜 ", gp_standings().map(func(r: Dictionary) -> String: return "%s %d" % [r["name"], int(r["points"])]))
		"done":
			print("流程冒烟：完成")
			get_tree().quit()
	if not _flow.is_empty():
		_flow.pop_front()
	_flow_t = 0.0


## 模拟鼠标拖拽（车库预览区）：phase 为 down / move / up，dx 为水平移动像素
func _mouse_drag(phase: String, dx: float) -> void:
	var ss := menu.current() as SetupScreen if menu else null
	if ss == null:
		_flow_fail("当前不是赛前设置页")
		return
	# 模拟输入用窗口坐标：页面坐标经视口拉伸变换到窗口
	var xf := get_viewport().get_final_transform()
	if phase == "down":
		_flow_mouse = xf * ss._preview.get_global_rect().get_center()
		_flow_yaw0 = menu.garage.table.rotation.y if menu.garage else 0.0
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = true
		b.position = _flow_mouse
		b.global_position = _flow_mouse
		Input.parse_input_event(b)
	elif phase == "move":
		var m := InputEventMouseMotion.new()
		_flow_mouse += Vector2(dx, 0.0)
		m.position = _flow_mouse
		m.global_position = _flow_mouse
		m.relative = Vector2(dx, 0.0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
	else:
		var u := InputEventMouseButton.new()
		u.button_index = MOUSE_BUTTON_LEFT
		u.pressed = false
		u.position = _flow_mouse
		u.global_position = _flow_mouse
		Input.parse_input_event(u)


## 模拟按键：按下，0.05 s 后松开（比赛输入是逐帧轮询的）
func _press_key(code: Key) -> void:
	_key_event(code, true)
	get_tree().create_timer(0.05).timeout.connect(_key_event.bind(code, false))


func _key_event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
