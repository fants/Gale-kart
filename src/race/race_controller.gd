class_name RaceController
extends Node3D
## 一场比赛的总控：构建赛道 / 世界 / 仿真 / 车辆表现 / 相机 / HUD，每帧推进仿真并分发事件。

## 冲线 3.4 s 后发出，summary 见 build_summary()
signal race_finished(summary: Dictionary)
## 暂停菜单等界面发出的请求："resume" / "restart" / "quit"
signal request(action: String)

const RESULTS_DELAY := 3.4

var sel: Dictionary
var quality := "high"
var track: TrackData
var terrain: TerrainData
var world: RaceWorld
var race: RaceSim
var kart_views: Array[KartView] = []
var effects: Effects
var item_view: ItemView
var screen_fx: ScreenFx
var hud: Hud
var camera: Camera3D
var rig: CameraRig
var player_input: PlayerInput
var router: EventRouter
var recorder: ReplayRecorder
var ghost_view: Node3D = null
var ghost_data: Dictionary = {}
## 幽灵车每帧的赛道进度（已展开圈数，单位采样），用于实时差距
var ghost_prog := PackedFloat32Array()

var time := 0.0
var paused := false
var finish_t := -1.0
var results_sent := false
var hud_visible := true
var record_result := {}
## 无人值守模式（截图 / 演示）：玩家也由 AI 驾驶
var autopilot := false
## 无人值守时也提交成绩（调试：生成计时赛幽灵车）
var record_even_autopilot := false
## 构建完成前不跑比赛逻辑（start 是分帧的协程）
var _built := false
## 分帧构建：每段工作超过这么多微秒就让出一帧，让加载页动画保持流畅
const BUILD_SLICE_US := 20000
var _slice_t := 0
var _progress := Callable()


## sel: {mode, track_id, character_id, kart_id, paint_id, difficulty, laps}
## opts: {quality, autopilot, skip_intro, seed, ai_roster, record}
## 协程：赛道 / 地形数据和地形网格在工作线程里算，其余在主线程分帧构建；progress(0..1) 报告真实进度
func start(p_sel: Dictionary, opts := {}, progress := Callable()) -> void:
	sel = p_sel.duplicate()
	quality = opts.get("quality", Store.settings.get("quality", "high"))
	autopilot = opts.get("autopilot", false)
	record_even_autopilot = opts.get("record", false)
	name = "Race"
	_progress = progress
	_slice_t = Time.get_ticks_usec()
	var def := TracksData.track_by_id(sel.get("track_id", "village"))
	var cell: float = EnvironmentFactory.quality_preset(quality)["terrain_cell"]
	var job := {}
	var task := WorkerThreadPool.add_task(func() -> void:
		var tr := TrackData.build(def)
		var td := TerrainData.create(tr)
		job["track"] = tr
		job["terrain"] = td
		job["terrain_mesh"] = TerrainMesh.compute(tr, td, cell), false, "构建赛道数据")
	var waited := 0.0
	while not WorkerThreadPool.is_task_completed(task):
		# 线程里的进度不可知：按经验时长缓慢推进到 45%
		waited += get_process_delta_time()
		_report(minf(0.45, 0.05 + waited * 0.3))
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_slice_t = Time.get_ticks_usec()
	track = job["track"]
	terrain = job["terrain"]
	_report(0.45)

	world = RaceWorld.new()
	add_child(world)
	await world.build_async(track, terrain, quality, job["terrain_mesh"], _breath, func(p: float) -> void: _report(0.45 + 0.4 * p))

	race = RaceSim.new({
		"track": track, "mode": sel.get("mode", "speed"), "laps": int(sel.get("laps", 3)),
		"difficulty": sel.get("difficulty", "normal"),
		"player": {"kart_id": sel.get("kart_id"), "character_id": sel.get("character_id"), "paint_id": sel.get("paint_id")},
		"seed": int(opts.get("seed", Time.get_ticks_usec() % 100000 + 1)),
		"auto_instant": Store.settings.get("auto_instant", false),
		"all_ai": autopilot, "skip_intro": opts.get("skip_intro", false),
		"ai_roster": opts.get("ai_roster", []),
	})

	recorder = ReplayRecorder.new(race)
	race.recorder = recorder
	_report(0.88)
	await _breath()

	effects = Effects.new()
	add_child(effects)
	effects.setup(quality, track.theme)
	item_view = ItemView.new()
	add_child(item_view)
	item_view.setup(track)

	for k in race.karts:
		var v := KartView.new()
		add_child(v)
		v.setup(k, {"show_name": not k.is_player, "night": track.theme.get("night", false), "engine_audio": not k.is_player})
		kart_views.append(v)
		await _breath()

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.15
	camera.far = 2500.0
	camera.fov = 68.0
	add_child(camera)
	camera.make_current()
	rig = CameraRig.new(camera)
	rig.far = Store.settings.get("camera", "far") != "near"

	player_input = PlayerInput.new()
	player_input.name = "PlayerInput"
	add_child(player_input)

	screen_fx = ScreenFx.new()
	add_child(screen_fx)
	screen_fx.setup()
	hud = Hud.new()
	add_child(hud)
	hud.setup(race)
	router = EventRouter.new(self)

	if race.mode == "time":
		_setup_ghost()
	EnvironmentFactory.apply_viewport_quality(get_viewport(), quality)
	AudioMgr.play_music(track.def.get("music", "village"))
	AudioMgr.set_music_tempo(1.0)
	_report(1.0)
	_built = true


## 分帧：本段工作超过 BUILD_SLICE_US 就让出一帧
func _breath() -> void:
	if Time.get_ticks_usec() - _slice_t > BUILD_SLICE_US:
		await get_tree().process_frame
		_slice_t = Time.get_ticks_usec()


func _report(p: float) -> void:
	if _progress.is_valid():
		_progress.call(p)


func _exit_tree() -> void:
	AudioMgr.stop_engine()
	if race:
		race.dispose()


## 当前镜头 / 音效的焦点车（比赛中是玩家）
func focus_kart() -> KartSim:
	return race.player


func all_karts() -> Array[KartSim]:
	return race.karts


func vibrate(weak: float, strong: float, dur: float) -> void:
	if player_input and not autopilot:
		player_input.vibrate(weak, strong, dur)


func set_paused(p: bool) -> void:
	paused = p
	AudioMgr.set_paused(p)
	if p:
		player_input.input.clear_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _built and race and not paused and race.phase != "finished" and not autopilot:
		# 切到后台自动暂停
		request.emit("pause")


func _process(dt: float) -> void:
	if not _built or race == null or paused:
		return
	dt = minf(dt, 0.1)
	time += dt
	var inp := player_input.poll()
	if player_input.camera_pressed:
		rig.far = not rig.far
		Store.save_settings({"camera": "far" if rig.far else "near"})
	if player_input.hide_hud_pressed:
		hud_visible = not hud_visible
		hud.set_hud_visible(hud_visible)
	if player_input.mute_pressed:
		var m: bool = not Store.settings.get("muted", false)
		Store.save_settings({"muted": m})
		AudioMgr.set_muted(m)
	if player_input.pause_pressed and race.phase != "finished":
		request.emit("pause")
		return
	if race.phase == "intro" and (inp.throttle_pressed or inp.use_pressed or player_input.drift_pressed):
		race.skip_intro()
		# 跳过航拍的这次按键不计入起步判定
		inp.throttle_pressed = false
		inp.use_pressed = false

	race.update(dt, inp)
	if race.phase == "racing" and Game.args.has("warp") and not _warped:
		_debug_warp()
	if race.phase == "racing" and Game.args.has("give"):
		_debug_give()
	if not results_sent:
		recorder.capture_events(race.events, race.clock)
	router.handle(race.events)
	_update_views(dt)

	if race.phase == "intro":
		rig.intro(track, race.player, race.phase_time / RaceSim.INTRO_TIME, dt)
	elif race.player.finished and finish_t > 1.0:
		rig.orbit(race.player, time, dt)
	else:
		rig.chase(race.player, dt, race.alpha)
	screen_fx.update_view(dt, time, race.player)
	_update_engine_audio()
	if not ghost_prog.is_empty():
		hud.set_ghost_diff(_ghost_diff())
	hud.update_view(dt, race)

	if finish_t >= 0.0:
		finish_t += dt
		if finish_t > RESULTS_DELAY and not results_sent:
			var summary := build_summary()
			results_sent = true
			race.recorder = null
			race_finished.emit(summary)


## 调试 / 截图：--warp=比例 把玩家车挪到赛道该处；--fall 顺势冲下悬崖；--route=支路 id 让自动驾驶走那条近道
var _warped := false


func _debug_warp() -> void:
	_warped = true
	var k := race.player
	var s := float(Game.args["warp"]) * track.n
	var h := track.heading_at(s)
	var pos := track.point_at(s, 0.0)
	var v := 24.0
	if Game.args.has("fall"):
		h -= 0.45
		pos = track.point_at(s, track.hw_at(s) + TrackData.CLIFF_LIP - 0.5)
	k.reset({"pos": pos, "heading": h, "s": s})
	k.track_hint = int(s)
	k.vx = sin(h) * v
	k.vz = cos(h) * v
	k.lap = 1
	k.last_idx = int(s)
	if Game.args.has("route") and k.ai != null:
		for bi in track.branches.size():
			if track.branches[bi].id == str(Game.args["route"]):
				k.ai.route = bi
				k.ai._decided = bi
	rig.snap_behind(k)


## 调试 / 截图：--give=missile,shield 让玩家一直拿着这些道具（竞速赛里 --give=nitro 给满两罐氮气），--roll 第二格一直在转轮盘
func _debug_give() -> void:
	var k := race.player
	var ids := str(Game.args["give"]).split(",")
	if race.item_mode:
		k.items.clear()
		for id in ids:
			if ItemsData.ITEMS.has(id) and k.items.size() < 2:
				k.items.append(id)
		k.item_roll = 1.0 if Game.args.has("roll") else 0.0
		if k.ai != null:
			k.ai.item_delay = 999.0
	elif "nitro" in ids:
		k.nitros = 2


func _update_views(dt: float) -> void:
	var cam_pos := camera.global_position
	for v in kart_views:
		v.update_view(dt, time, race.alpha, cam_pos)
	item_view.update_view(dt, time, race.items, effects)
	ContinuousFx.emit(effects, kart_views, cam_pos, track.grip < 1.0, dt)
	world.update_view(dt, time, camera)
	_update_ghost()


func _update_engine_audio() -> void:
	var p := race.player
	if p.finished and finish_t > 2.0:
		AudioMgr.stop_engine()
		return
	AudioMgr.update_engine({
		"speed01": p.speed / 36.0,
		"throttle": p.input.throttle,
		"boosting": p.is_boosting(),
		"drifting": p.drifting,
		"drift_intensity": p.drift_intensity,
		"airborne": not p.on_ground,
		"offroad": p.offroad,
		"surface": "ice" if track.grip < 1.0 else "asphalt",
	})


func on_player_finish(e: Dictionary) -> void:
	finish_t = 0.0
	var p := race.player
	if not p.lap_times.is_empty():
		var last: float = p.lap_times[-1]
		hud.add_lap_time(p.lap_times.size(), last, last <= p.best_lap + 1e-6)
	hud.big("FINISH!", {"hold": true, "color": Color("#FFC93C")})
	AudioMgr.play("finish")
	effects.burst("confetti", Vector3(p.x, p.y, p.z), {"count": 140})
	vibrate(0.5, 0.5, 0.5)
	if autopilot and not record_even_autopilot:
		return
	var ghost := {}
	if race.mode == "time":
		ghost = {"frames": Array(race.ghost_rec), "kart_id": p.kart_def["id"], "character_id": p.character["id"],
			"paint_id": p.paint["id"], "total": float(e["time"]), "laps": race.laps}
	record_result = Store.submit(track.id, race.mode, race.laps, float(e["time"]), p.best_lap, ghost)


## 结算数据：名次表、玩家成绩、纪录徽章
func build_summary() -> Dictionary:
	var rows: Array[Dictionary] = []
	for r in race.results():
		var k: KartSim = r["kart"]
		rows.append({
			"rank": r["rank"], "name": k.name, "is_player": k.is_player, "kart_id": k.kart_def["id"],
			"kart_name": k.kart_def["name"], "character_id": k.character["id"], "paint_id": k.paint["id"],
			"time": r["time"], "estimated": r["estimated"], "best_lap": r["best_lap"],
		})
	var p := race.player
	return {
		"track_id": track.id, "track_name": track.name, "mode": race.mode, "laps": race.laps,
		"rank": p.rank, "total": p.finish_time, "best_lap": p.best_lap, "rows": rows,
		"record": record_result, "ghost_total": ghost_data.get("total", -1.0),
		"solo": race.karts.size() == 1, "ai_roster": race.ai_roster(),
		# 精彩回放数据（为空时结算页不显示回放按钮）
		"replay": recorder.to_data() if recorder and recorder.frames.size() > 60 else {},
	}


# ———————————————— 计时赛幽灵车 ————————————————

func _setup_ghost() -> void:
	if race.laps != 3:
		return
	var g := Store.ghost(track.id)
	var frames: Array = g.get("frames", [])
	if frames.size() < 32:
		return
	ghost_data = g
	var model := KartModel.create(g.get("kart_id", "marshmallow"), g.get("character_id", "male-a"), g.get("paint_id", "oobi"))
	model.set_ghost(true)
	ghost_view = model
	add_child(model)
	# 预先把每帧投影到赛道，得到单调递增的进度
	var pr := TrackProj.new()
	var hint := -1
	var lap := -1
	var last_s := -1.0
	for i in frames.size() / 4:
		track.project(float(frames[i * 4]), float(frames[i * 4 + 1]), float(frames[i * 4 + 2]), hint, pr)
		hint = pr.idx
		if lap < 0:
			lap = 0 if pr.s > track.n * 0.5 else 1
		elif pr.s - last_s < -track.n * 0.5:
			lap += 1
		elif pr.s - last_s > track.n * 0.5:
			lap -= 1
		last_s = pr.s
		ghost_prog.append((lap - 1) * track.n + pr.s)


## 玩家与幽灵车的时间差（秒，负数表示领先）
func _ghost_diff() -> float:
	if ghost_prog.is_empty() or race.phase != "racing":
		return INF
	var target := race.player.progress
	var lo := 0
	var hi := ghost_prog.size() - 1
	if target > ghost_prog[hi]:
		return INF
	while lo < hi:
		var mid := (lo + hi) / 2
		if ghost_prog[mid] < target:
			lo = mid + 1
		else:
			hi = mid
	var t := float(lo)
	if lo > 0:
		var a := ghost_prog[lo - 1]
		var b := ghost_prog[lo]
		if b > a:
			t = lo - 1 + (target - a) / (b - a)
	return race.time - t / RaceSim.GHOST_RATE


func _update_ghost() -> void:
	if ghost_view == null:
		return
	var f: Array = ghost_data["frames"]
	var count := f.size() / 4
	var t := race.time * RaceSim.GHOST_RATE if race.phase in ["racing", "finished"] else 0.0
	var i := mini(count - 1, int(t))
	var j := mini(count - 1, i + 1)
	var u := minf(1.0, t - i)
	ghost_view.visible = t < count
	ghost_view.position = Vector3(
		lerpf(f[i * 4], f[j * 4], u), lerpf(f[i * 4 + 1], f[j * 4 + 1], u), lerpf(f[i * 4 + 2], f[j * 4 + 2], u))
	ghost_view.rotation.y = MathX.lerp_angle_short(f[i * 4 + 3], f[j * 4 + 3], u)
