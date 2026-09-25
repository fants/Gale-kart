class_name ReplayRecorder
extends RefCounted
## 精彩回放录制：每 1/30 s 记录所有车的表现状态与道具实体快照；离散事件带时间戳（车辆引用转成编号）。
## RaceSim 每个子步调用 capture()；RaceController 每帧在 race.update() 之后调用 capture_events()。

const RATE := 30.0
## 每辆车每帧的浮点数个数
const K := 31
const BOOST_KINDS := ["", "nitro", "instant", "pad", "start", "magnet", "draft"]
## flags 位
const F_DRIFTING := 1
const F_GROUND := 2
const F_FINISHED := 4
const F_OFFROAD := 8
const F_DRAFT := 16

var kart_count := 0
var karts_meta: Array[Dictionary] = []
## 每帧一个 PackedFloat32Array（kart_count × K）
var frames: Array[PackedFloat32Array] = []
## 每帧的道具实体快照（道具赛才有）
var item_frames: Array[Dictionary] = []
## [{t, e}]，e 为已转换的事件
var events: Array[Dictionary] = []
## 第一帧对应的比赛总时钟
var t0 := -1.0
var go_clock := -1.0
var track_id := ""
var mode := ""
var laps := 3
var _next := 0.0
var _index := {}


func _init(race: RaceSim) -> void:
	kart_count = race.karts.size()
	track_id = race.track.id
	mode = race.mode
	laps = race.laps
	for k in race.karts:
		_index[k] = k.index
		karts_meta.append({"index": k.index, "name": k.name, "is_player": k.is_player,
			"kart_id": k.kart_def["id"], "character_id": k.character["id"], "paint_id": k.paint["id"]})


func capture(race: RaceSim, _dt: float) -> void:
	if go_clock < 0.0 and race.phase in ["racing", "finished"]:
		go_clock = race.clock - race.time
	if race.clock + 1e-6 < _next:
		return
	if t0 < 0.0:
		t0 = race.clock
	_next = t0 + (frames.size() + 1) / RATE
	var f := PackedFloat32Array()
	f.resize(kart_count * K)
	for k in race.karts:
		var o := k.index * K
		var flags := 0
		if k.drifting:
			flags |= F_DRIFTING
		if k.on_ground:
			flags |= F_GROUND
		if k.finished:
			flags |= F_FINISHED
		if k.offroad:
			flags |= F_OFFROAD
		if k.in_draft:
			flags |= F_DRAFT
		f[o] = k.x; f[o + 1] = k.y; f[o + 2] = k.z; f[o + 3] = k.heading
		f[o + 4] = k.visual_drift; f[o + 5] = k.steer; f[o + 6] = k.speed; f[o + 7] = k.forward_speed
		f[o + 8] = k.vx; f[o + 9] = k.vz; f[o + 10] = k.vy; f[o + 11] = k.slope
		f[o + 12] = k.fake_drift; f[o + 13] = k.drift_dir; f[o + 14] = flags
		f[o + 15] = BOOST_KINDS.find(k.boost_kind) if k.is_boosting() else 0
		f[o + 16] = k.spin; f[o + 17] = k.flip; f[o + 18] = k.bubble; f[o + 19] = k.dizzy
		f[o + 20] = k.cloud; f[o + 21] = k.ufo; f[o + 22] = k.shield; f[o + 23] = k.magnet
		f[o + 24] = k.invuln; f[o + 25] = k.locked_by; f[o + 26] = k.rank; f[o + 27] = k.lap
		f[o + 28] = k.progress; f[o + 29] = k.drift_time
		f[o + 30] = k.magnet_target.index if k.magnet_target != null and k.magnet > 0.0 else -1
	frames.append(f)
	if race.items != null:
		item_frames.append(_snapshot_items(race.items))


func _snapshot_items(items: ItemSystem) -> Dictionary:
	var boxes := PackedByteArray()
	for b in items.boxes:
		boxes.append(1 if b["active"] else 0)
	return {
		"boxes": boxes,
		"missiles": _pack(items.missiles, "homing"),
		"flies": _pack(items.water_flies, "homing"),
		"bombs": _pack(items.water_bombs, ""),
		"zones": _pack(items.water_zones, "zone"),
		"bananas": _pack(items.bananas, "banana"),
	}


## 实体数组 → 扁平浮点数组：[id, x, y, z, 额外字段...]
func _pack(list: Array[Dictionary], kind: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in list:
		var p: Vector3 = e["pos"]
		out.append_array([float(e["id"]), p.x, p.y, p.z])
		match kind:
			"homing":
				var q: Vector3 = e["prev_pos"]
				out.append_array([q.x, q.y, q.z])
			"zone":
				out.append_array([float(e["radius"]), float(e["life"]), float(e["age"])])
			"banana":
				out.append_array([float(e["spin"]), float(e["age"])])
	return out


## 记录本帧事件（车辆引用 → {"kart_ref": 编号}，道具实体 → 只保留位置）
func capture_events(evs: Array[Dictionary], clock: float) -> void:
	for e in evs:
		var c := {}
		for key: String in e:
			var v: Variant = e[key]
			if v is KartSim:
				c[key] = {"kart_ref": (v as KartSim).index}
			elif v is Dictionary:
				var d: Dictionary = v
				c[key] = {"pos": d.get("pos", Vector3.ZERO)}
			else:
				c[key] = v
		events.append({"t": clock, "e": c})


func duration() -> float:
	return frames.size() / RATE


func to_data() -> Dictionary:
	return {
		"rate": RATE, "k": K, "kart_count": kart_count, "karts": karts_meta, "frames": frames,
		"items": item_frames, "events": events, "t0": t0, "go_clock": go_clock,
		"track_id": track_id, "mode": mode, "laps": laps,
	}


## 采样第 i 辆车在回放时间 t（秒，从第一帧算起）的状态；角度走最短弧
static func sample(data: Dictionary, t: float, i: int) -> PackedFloat32Array:
	var fr: Array = data["frames"]
	var k: int = data["k"]
	var out := PackedFloat32Array()
	out.resize(k)
	if fr.is_empty():
		return out
	var ft := clampf(t * float(data["rate"]), 0.0, fr.size() - 1.0)
	var a := int(ft)
	var b := mini(a + 1, fr.size() - 1)
	var u := ft - a
	var fa: PackedFloat32Array = fr[a]
	var fb: PackedFloat32Array = fr[b]
	var o := i * k
	for j in k:
		var va := fa[o + j]
		var vb := fb[o + j]
		if j == 3:
			out[j] = MathX.lerp_angle_short(va, vb, u)
		elif j in [14, 15, 26, 27, 30]:
			# 离散量取最近帧
			out[j] = va if u < 0.5 else vb
		else:
			out[j] = lerpf(va, vb, u)
	return out
