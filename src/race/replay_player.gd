class_name ReplayPlayer
extends Node3D
## 精彩回放：用录制数据驱动「木偶」车辆（只写字段、不跑物理），复用 KartView / ItemView / Effects / EventRouter。
## 机位：电视转播 / 追尾 / 环绕 / 俯瞰，默认自动切换；1–4 手动切换，←→ 换焦点车，空格暂停，[ ] 变速，H 隐藏界面，Esc 退出。

signal exit_requested

const SPEEDS := [0.25, 0.5, 1.0, 2.0]
const CAM_NAMES := {"auto": "自动导播", "tv": "转播机位", "chase": "追尾", "orbit": "环绕", "heli": "俯瞰"}

var data: Dictionary
var track: TrackData
var terrain: TerrainData
var world: RaceWorld
var puppets: Array[KartSim] = []
var kart_views: Array[KartView] = []
var items: ItemSystem = null
var effects: Effects
var item_view: ItemView
var camera: Camera3D
var rig: CameraRig
var tv: TvCameras
var router: EventRouter
var hud: Hud = null
var overlay: ReplayHud

var time_pos := 0.0
var start_pos := 0.0
var duration := 0.0
var speed_idx := 2
var paused := false
var focus := 0
## "auto" 或具体机位
var cam_mode := "auto"
var _auto_cam := "tv"
var _auto_left := 5.0
var _event_idx := 0
var _clock := 0.0
var _ui_visible := true
var _heli := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func start(p_data: Dictionary, quality := "high") -> void:
	data = p_data
	name = "Replay"
	track = TrackData.build(TracksData.track_by_id(data["track_id"]))
	terrain = TerrainData.create(track)
	world = RaceWorld.new()
	add_child(world)
	world.build(track, terrain, quality, data.get("mode", "speed"))
	effects = Effects.new()
	add_child(effects)
	effects.setup(quality, track.theme)
	item_view = ItemView.new()
	add_child(item_view)
	item_view.setup(track)
	if data.get("mode", "speed") == "item":
		items = ItemSystem.new(null)

	for meta: Dictionary in data["karts"]:
		var k := KartSim.new(int(meta["index"]), meta["name"], meta["is_player"],
			KartsData.kart_by_id(meta["kart_id"]), KartsData.character_by_id(meta["character_id"]), KartsData.paint_by_id(meta["paint_id"]))
		puppets.append(k)
		if k.is_player:
			focus = k.index
	for k in puppets:
		var v := KartView.new()
		add_child(v)
		v.setup(k, {"show_name": true, "night": track.theme.get("night", false), "engine_audio": true})
		kart_views.append(v)

	camera = Camera3D.new()
	camera.near = 0.15
	camera.far = 2500.0
	add_child(camera)
	camera.make_current()
	rig = CameraRig.new(camera)
	tv = TvCameras.new(track, terrain)
	router = EventRouter.new(self)
	router.replay = true
	overlay = ReplayHud.new()
	add_child(overlay)
	overlay.setup(track.name)
	EnvironmentFactory.apply_viewport_quality(get_viewport(), quality)

	duration = (data["frames"] as Array).size() / float(data["rate"])
	# 从 GO 前 2 秒开始播
	var go_rel: float = float(data.get("go_clock", -1.0)) - float(data.get("t0", 0.0))
	start_pos = clampf(go_rel - 2.0, 0.0, maxf(duration - 1.0, 0.0))
	_seek(start_pos)
	AudioMgr.play_music(track.def.get("music", "village"))
	AudioMgr.set_music_tempo(1.0)


func _exit_tree() -> void:
	for k in puppets:
		k.magnet_target = null


# ———————————————— EventRouter 需要的鸭子类型接口 ————————————————

func focus_kart() -> KartSim:
	return puppets[focus]


func all_karts() -> Array[KartSim]:
	return puppets


func vibrate(_w: float, _s: float, _d: float) -> void:
	pass


func on_player_finish(_e: Dictionary) -> void:
	pass


# ———————————————— 播放 ————————————————

func _seek(t: float) -> void:
	time_pos = clampf(t, 0.0, duration)
	# 事件指针定位到当前时间
	var events: Array = data["events"]
	var t0: float = data.get("t0", 0.0)
	_event_idx = 0
	while _event_idx < events.size() and float(events[_event_idx]["t"]) - t0 <= time_pos:
		_event_idx += 1
	_apply_frame()
	rig.initialized = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) and not (event is InputEventJoypadButton and event.pressed):
		return
	var handled := true
	if event.is_action("pause") or event.is_action("ui_cancel"):
		exit_requested.emit()
	elif event is InputEventKey:
		match (event as InputEventKey).physical_keycode:
			KEY_1: cam_mode = "tv"
			KEY_2: cam_mode = "chase"
			KEY_3: cam_mode = "orbit"
			KEY_4: cam_mode = "heli"
			KEY_0, KEY_5: cam_mode = "auto"
			KEY_LEFT, KEY_A: _cycle_focus(-1)
			KEY_RIGHT, KEY_D: _cycle_focus(1)
			KEY_SPACE: paused = not paused
			KEY_BRACKETLEFT: speed_idx = maxi(0, speed_idx - 1)
			KEY_BRACKETRIGHT: speed_idx = mini(SPEEDS.size() - 1, speed_idx + 1)
			KEY_H:
				_ui_visible = not _ui_visible
				overlay.set_ui_visible(_ui_visible)
			KEY_HOME: _seek(start_pos)
			_: handled = false
	elif event is InputEventJoypadButton:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_LEFT: _cycle_focus(-1)
			JOY_BUTTON_DPAD_RIGHT: _cycle_focus(1)
			JOY_BUTTON_A: paused = not paused
			JOY_BUTTON_Y: cam_mode = ["auto", "tv", "chase", "orbit", "heli"][(["auto", "tv", "chase", "orbit", "heli"].find(cam_mode) + 1) % 5]
			_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _cycle_focus(d: int) -> void:
	focus = posmod(focus + d, puppets.size())
	rig.initialized = false
	tv.current = -1


func _process(dt: float) -> void:
	if data.is_empty():
		return
	dt = minf(dt, 0.1)
	_clock += dt
	var step := 0.0 if paused else dt * float(SPEEDS[speed_idx])
	if step > 0.0:
		var prev := time_pos
		time_pos += step
		if time_pos >= duration:
			# 播完从头循环
			_seek(start_pos)
		else:
			_dispatch_events(prev, time_pos)
	_apply_frame()
	var vdt := step if step > 0.0 else 0.0
	var cam_pos := camera.global_position
	for v in kart_views:
		v.update_view(maxf(vdt, 0.0001), _clock, 1.0, cam_pos)
	item_view.update_view(vdt, _clock, items, effects)
	if vdt > 0.0:
		ContinuousFx.emit(effects, kart_views, cam_pos, track.grip < 1.0, vdt)
	world.update_view(dt, _clock, camera)
	_update_camera(dt)
	overlay.update_view((time_pos - start_pos) / maxf(duration - start_pos, 0.01), puppets[focus], CAM_NAMES[cam_mode] if cam_mode != "auto" else "%s · %s" % [CAM_NAMES["auto"], CAM_NAMES[_auto_cam]], SPEEDS[speed_idx], paused)


func _dispatch_events(from: float, to: float) -> void:
	var events: Array = data["events"]
	var t0: float = data.get("t0", 0.0)
	var batch: Array[Dictionary] = []
	while _event_idx < events.size():
		var ev: Dictionary = events[_event_idx]
		var et: float = float(ev["t"]) - t0
		if et > to:
			break
		if et > from:
			batch.append(_restore(ev["e"]))
		_event_idx += 1
	if not batch.is_empty():
		router.handle(batch)


## 事件里的车辆编号还原成木偶车
func _restore(e: Dictionary) -> Dictionary:
	var out := {}
	for key: String in e:
		var v: Variant = e[key]
		if v is Dictionary and (v as Dictionary).has("kart_ref"):
			out[key] = puppets[int(v["kart_ref"])]
		else:
			out[key] = v
	return out


func _apply_frame() -> void:
	for k in puppets:
		var f := ReplayRecorder.sample(data, time_pos, k.index)
		k.x = f[0]; k.y = f[1]; k.z = f[2]; k.heading = f[3]
		k.visual_drift = f[4]; k.steer = f[5]; k.speed = f[6]; k.forward_speed = f[7]
		k.vx = f[8]; k.vz = f[9]; k.vy = f[10]; k.slope = f[11]
		k.fake_drift = f[12]; k.drift_dir = f[13]
		var flags := int(f[14])
		k.drifting = flags & ReplayRecorder.F_DRIFTING != 0
		k.on_ground = flags & ReplayRecorder.F_GROUND != 0
		k.finished = flags & ReplayRecorder.F_FINISHED != 0
		k.offroad = flags & ReplayRecorder.F_OFFROAD != 0
		k.in_draft = flags & ReplayRecorder.F_DRAFT != 0
		var bk := int(f[15])
		k.boost_kind = ReplayRecorder.BOOST_KINDS[bk] if bk > 0 and bk < ReplayRecorder.BOOST_KINDS.size() else ""
		k.boost_time = 1.0 if bk > 0 else 0.0
		k.spin = f[16]; k.flip = f[17]; k.bubble = f[18]; k.dizzy = f[19]
		k.cloud = f[20]; k.ufo = f[21]; k.shield = f[22]; k.magnet = f[23]
		k.invuln = f[24]; k.locked_by = f[25]; k.rank = int(f[26]); k.lap = int(f[27])
		k.progress = f[28]; k.drift_time = f[29]
		var mt := int(f[30])
		k.magnet_target = puppets[mt] if mt >= 0 and mt < puppets.size() else null
		k.snapshot_prev()
		var pr := track.project(k.x, k.y, k.z, k.track_hint, k.proj)
		k.track_hint = pr.idx
		k.s = pr.s
		k.lateral = pr.lateral
	if items != null:
		_apply_items()


func _apply_items() -> void:
	var ifr: Array = data["items"]
	if ifr.is_empty():
		return
	var idx := clampi(int(time_pos * float(data["rate"])), 0, ifr.size() - 1)
	var snap: Dictionary = ifr[idx]
	if items.boxes.is_empty():
		var bid := 1
		for b in track.item_boxes:
			items.boxes.append({"id": bid, "pos": b["pos"], "active": true, "s": b["s"], "lateral": b["lateral"]})
			bid += 1
	var flags: PackedByteArray = snap["boxes"]
	for i in mini(flags.size(), items.boxes.size()):
		items.boxes[i]["active"] = flags[i] == 1
	items.missiles = _unpack(snap["missiles"], 7, "homing")
	items.water_flies = _unpack(snap["flies"], 7, "homing")
	items.water_bombs = _unpack(snap["bombs"], 4, "")
	items.water_zones = _unpack(snap["zones"], 7, "zone")
	items.bananas = _unpack(snap["bananas"], 6, "banana")


func _unpack(arr: PackedFloat32Array, stride: int, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i + stride <= arr.size():
		var e := {"id": int(arr[i]), "pos": Vector3(arr[i + 1], arr[i + 2], arr[i + 3]), "age": 1.0, "target": null}
		match kind:
			"homing":
				e["prev_pos"] = Vector3(arr[i + 4], arr[i + 5], arr[i + 6])
			"zone":
				e["radius"] = arr[i + 4]
				e["life"] = arr[i + 5]
				e["age"] = arr[i + 6]
			"banana":
				e["spin"] = arr[i + 4]
				e["age"] = arr[i + 5]
		out.append(e)
		i += stride
	return out


# ———————————————— 机位 ————————————————

func _update_camera(dt: float) -> void:
	var k := puppets[focus]
	var mode := cam_mode
	if mode == "auto":
		_auto_left -= dt
		if _auto_left <= 0.0:
			var order := ["tv", "chase", "tv", "orbit", "tv", "heli"]
			_auto_cam = order[(order.find(_auto_cam) + 1 + _rng.randi_range(0, 2)) % order.size()]
			_auto_left = _rng.randf_range(4.0, 7.0)
			rig.initialized = false
			tv.current = -1
		mode = _auto_cam
	var kp := Vector3(k.x, k.y, k.z)
	match mode:
		"tv":
			var c := tv.pick(k.s)
			var cp: Vector3 = c.get("pos", kp + Vector3(0, 6, -10))
			var dist := cp.distance_to(kp)
			var fov := clampf(rad_to_deg(2.0 * atan(6.5 / maxf(dist, 1.0))), 14.0, 62.0)
			var target := kp + Vector3(sin(k.heading), 0.0, cos(k.heading)) * minf(k.speed * 0.12, 4.0) + Vector3(0, 0.8, 0)
			if rig.initialized:
				target = rig.look.lerp(target, 1.0 - exp(-10.0 * dt))
				fov = lerpf(rig.fov, fov, 1.0 - exp(-4.0 * dt))
			rig.set_view(cp, target, fov, dt)
		"chase":
			rig.chase(k, dt, 1.0)
		"orbit":
			rig.orbit(k, _clock, dt)
		"heli":
			var fwd := Vector3(sin(k.heading), 0.0, cos(k.heading))
			var want := kp - fwd * 14.0 + Vector3(0, 16.0, 0)
			_heli = want if not rig.initialized else _heli.lerp(want, 1.0 - exp(-3.0 * dt))
			rig.set_view(_heli, kp + fwd * 5.0, 50.0, dt)
