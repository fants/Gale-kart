class_name ItemSystem
extends RefCounted
## 道具系统（仿真层）：道具箱、导弹、水炸弹、香蕉皮、水苍蝇，以及即时生效类道具。
## 移植自参考版 items.js；新增飞碟、水苍蝇。所有实体都是 Dictionary，表现层按 id 跟踪。

const BOX_RESPAWN := 2.6
const MISSILE_SPEED := 64.0
const WATER_FLY_SPEED := 70.0
const WATER_FLIGHT := 0.75
const ROLL_TIME := 0.65

var race: RaceSim
var track: TrackData
var boxes: Array[Dictionary] = []
var missiles: Array[Dictionary] = []
## 飞行中的水炸弹
var water_bombs: Array[Dictionary] = []
## 落地后的水柱
var water_zones: Array[Dictionary] = []
var bananas: Array[Dictionary] = []
var water_flies: Array[Dictionary] = []
var _next_id := 1


## p_race 为 null 时是回放用的「木偶」实例：只承载实体数组，不做仿真
func _init(p_race: RaceSim) -> void:
	race = p_race
	if race == null:
		return
	track = race.track
	if race.item_mode:
		for b in track.item_boxes:
			var box := b.duplicate()
			box["active"] = true
			box["timer"] = 0.0
			box["id"] = _new_id()
			boxes.append(box)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func update(dt: float) -> void:
	var events := race.events

	# —— 道具箱 ——
	for b in boxes:
		if not b["active"]:
			b["timer"] -= dt
			if b["timer"] <= 0.0:
				b["active"] = true
			continue
		var bp: Vector3 = b["pos"]
		for k in race.karts:
			if k.finished:
				continue
			var dx := k.x - bp.x
			var dz := k.z - bp.z
			if dx * dx + dz * dz < 2.5 * 2.5 and absf(k.y + 0.8 - (bp.y + 1.2)) < 2.8:
				b["active"] = false
				b["timer"] = BOX_RESPAWN
				events.append({"type": "item_box", "kart": k, "box": b})
				if k.items.size() < 2:
					var cnt := race.karts.size()
					var frac := float(k.rank - 1) / (cnt - 1) if cnt > 1 else 0.5
					var weights := ItemsData.weights_for(frac)
					# 第一名拿不到雷暴和水苍蝇；雷暴只给明显落后的人
					weights.erase("thunder")
					if frac > 0.6:
						weights["thunder"] = 12.0 if frac > 0.85 else 6.0
					if k.rank == 1:
						weights.erase("water_fly")
						weights.erase("ufo")
					var item := MathX.weighted_pick(weights, race.rng)
					k.items.append(item)
					k.item_roll = ROLL_TIME
					events.append({"type": "item_get", "kart": k, "item": item})
				break

	_update_homing(missiles, MISSILE_SPEED, dt, "flip", false)
	_update_homing(water_flies, WATER_FLY_SPEED, dt, "bubble", true)

	# —— 水炸弹飞行 ——
	for i in range(water_bombs.size() - 1, -1, -1):
		var w := water_bombs[i]
		w["t"] += dt
		var u := clampf(w["t"] / WATER_FLIGHT, 0.0, 1.0)
		var sp: Vector3 = w["start"]
		var ep: Vector3 = w["end"]
		var pos := sp.lerp(ep, u)
		pos.y += sin(u * PI) * 6.0
		w["pos"] = pos
		if u >= 1.0:
			water_bombs.remove_at(i)
			var zone := {"id": _new_id(), "pos": ep, "s": w["es"], "lateral": w["el"], "radius": 4.4, "life": 3.2, "age": 0.0, "caught": [], "owner": w["owner"]}
			water_zones.append(zone)
			events.append({"type": "water_splash", "pos": ep, "zone": zone})
	for i in range(water_zones.size() - 1, -1, -1):
		var zn := water_zones[i]
		zn["life"] -= dt
		zn["age"] += dt
		if zn["life"] <= 0.0:
			water_zones.remove_at(i)
			continue
		var zp: Vector3 = zn["pos"]
		var caught: Array = zn["caught"]
		for k in race.karts:
			# 丢出者对自己的水柱免疫（否则会恰好开进自己扔的水柱里）
			if k == zn["owner"] or caught.has(k) or k.bubble > 0.0:
				continue
			var dx := k.x - zp.x
			var dz := k.z - zp.z
			if dx * dx + dz * dz < zn["radius"] * zn["radius"] and absf(k.y - zp.y) < 3.5:
				caught.append(k)
				if k.apply_hit("bubble", events, zn["owner"]):
					events.append({"type": "bubble", "kart": k})

	# —— 香蕉皮 ——
	for i in range(bananas.size() - 1, -1, -1):
		var b := bananas[i]
		b["life"] -= dt
		b["age"] += dt
		if b["life"] <= 0.0:
			bananas.remove_at(i)
			continue
		var bp: Vector3 = b["pos"]
		for k in race.karts:
			if k == b["owner"] and b["age"] < 0.8:
				continue
			if k.bubble > 0.0 or k.flip > 0.0:
				continue
			var dx := k.x - bp.x
			var dz := k.z - bp.z
			if dx * dx + dz * dz < 1.9 * 1.9 and absf(k.y - bp.y) < 2.0:
				bananas.remove_at(i)
				var ok := k.apply_hit("spin", events, b["owner"])
				events.append({"type": "banana_hit", "kart": k, "pos": bp, "blocked": not ok})
				break


## 沿赛道追踪目标的飞行道具。导弹路上碰到谁炸谁；水苍蝇从其他车头顶飞过，只命中目标。
func _update_homing(list: Array[Dictionary], speed: float, dt: float, hit_kind: String, target_only: bool) -> void:
	var events := race.events
	for i in range(list.size() - 1, -1, -1):
		var m := list[i]
		m["life"] -= dt
		m["age"] += dt
		var t: KartSim = m["target"]
		m["s_abs"] += speed * dt / track.spacing
		if t != null and not t.finished:
			m["lateral"] += (t.lateral - m["lateral"]) * minf(1.0, dt * (5.0 if m["age"] > 0.4 else 1.5))
			var gap: float = t.progress - m["s_abs"]
			if gap < 60.0 / track.spacing and gap > -2.0:
				t.locked_by = maxf(t.locked_by, 0.25)
		var p := track.point_at(fposmod(m["s_abs"], track.n), m["lateral"])
		# 目标在支路（近道 / 悬崖下）上：追近后直接朝它飞
		if t != null and t.branch >= 0 and absf(t.progress - float(m["s_abs"])) < 50.0 / track.spacing:
			var cur: Vector3 = m["pos"] - Vector3(0, 1.0, 0)
			var dv := Vector3(t.x, t.y, t.z) - cur
			var stp := speed * dt
			p = Vector3(t.x, t.y, t.z) if dv.length() <= stp else cur + dv.normalized() * stp
		m["prev_pos"] = m["pos"]
		m["pos"] = Vector3(p.x, p.y + 1.0, p.z)
		var mp: Vector3 = m["pos"]
		var hit: KartSim = null
		for k in race.karts:
			if k == m["owner"] and m["age"] < 1.0:
				continue
			if target_only and k != t:
				continue
			var dx := k.x - mp.x
			var dz := k.z - mp.z
			var dy := k.y + 0.6 - mp.y
			if dx * dx + dz * dz < 2.4 * 2.4 and absf(dy) < 3.0:
				hit = k
				break
		if hit != null:
			var ok := hit.apply_hit(hit_kind, events, m["owner"])
			if hit_kind == "flip":
				events.append({"type": "explosion", "pos": mp, "kart": hit, "blocked": not ok})
			else:
				events.append({"type": "water_splash", "pos": mp, "zone": {}})
				if ok:
					events.append({"type": "bubble", "kart": hit})
			list.remove_at(i)
			continue
		if m["life"] <= 0.0 or (t != null and t.finished):
			if hit_kind == "flip":
				events.append({"type": "explosion", "pos": mp, "kart": null, "blocked": true})
			else:
				events.append({"type": "water_splash", "pos": mp, "zone": {}})
			list.remove_at(i)


func _leader_other_than(k: KartSim) -> KartSim:
	var ranked := race.ranking
	var target: KartSim = ranked[0] if ranked[0] != k else (ranked[1] if ranked.size() > 1 else null)
	if target != null and target.finished:
		return null
	return target


## 使用道具槽第一个道具
func use(k: KartSim) -> void:
	var events := race.events
	if k.items.is_empty():
		return
	var item: String = k.items.pop_front()
	events.append({"type": "item_use", "kart": k, "item": item})
	match item:
		"nitro":
			k.add_boost(2.2, k.params["boost_power"], "nitro")
			events.append({"type": "nitro", "kart": k})
		"missile":
			var target := race.kart_ahead(k)
			var gap := race.gap_meters(k, target) if target != null else INF
			var locked := gap < 260.0
			var m := {
				"id": _new_id(), "owner": k, "target": target if locked else null,
				"s_abs": k.progress + 2.0 / track.spacing, "lateral": k.lateral,
				"pos": Vector3(k.x, k.y + 1.0, k.z), "prev_pos": Vector3(k.x, k.y + 1.0, k.z),
				"life": 7.0 if locked else 2.5, "age": 0.0,
			}
			missiles.append(m)
			events.append({"type": "missile_launch", "kart": k, "target": m["target"], "missile": m})
		"water_fly":
			var target := _leader_other_than(k)
			var fly := {
				"id": _new_id(), "owner": k, "target": target,
				"s_abs": k.progress + 2.0 / track.spacing, "lateral": k.lateral,
				"pos": Vector3(k.x, k.y + 1.0, k.z), "prev_pos": Vector3(k.x, k.y + 1.0, k.z),
				"life": 8.0, "age": 0.0,
			}
			water_flies.append(fly)
			events.append({"type": "water_fly_launch", "kart": k, "target": target, "fly": fly})
		"water":
			var road := _road(k)
			var rs := road.wrap_s(_road_s(k) + 30.0 / road.spacing)
			var el := clampf(k.lateral, -road.hw_at(rs) + 3.0, road.hw_at(rs) - 3.0)
			var e := road.point_at(rs, el)
			var es := rs if road == track else road.map_to_main(rs, track.n)
			water_bombs.append({
				"id": _new_id(), "owner": k, "t": 0.0,
				"start": Vector3(k.x, k.y + 1.2, k.z), "end": e, "es": es, "el": el,
				"pos": Vector3(k.x, k.y + 1.2, k.z),
			})
			events.append({"type": "water_throw", "kart": k})
		"banana":
			var road := _road(k)
			var rs := road.wrap_s(_road_s(k) - 2.8 / road.spacing)
			var bl := clampf(k.lateral, -road.hw_at(rs) + 1.0, road.hw_at(rs) - 1.0)
			var bp := road.point_at(rs, bl)
			var bs := rs if road == track else road.map_to_main(rs, track.n)
			bananas.append({"id": _new_id(), "owner": k, "pos": bp, "s": bs, "lateral": bl, "life": 40.0, "age": 0.0, "spin": race.rng.randf() * 6.0})
			events.append({"type": "banana_drop", "kart": k})
		"shield":
			k.shield = 3.6
			events.append({"type": "shield", "kart": k})
		"cloud":
			var target := _leader_other_than(k)
			if target != null:
				if target.shield > 0.0:
					events.append({"type": "shield_block", "kart": target})
				else:
					target.cloud = 5.0
					events.append({"type": "cloud", "kart": target, "source": k})
		"ufo":
			var target := _leader_other_than(k)
			if target != null:
				if target.shield > 0.0:
					events.append({"type": "shield_block", "kart": target})
				else:
					target.ufo = 3.0
					events.append({"type": "ufo", "kart": target, "source": k})
		"thunder":
			events.append({"type": "thunder", "kart": k})
			for o in race.karts:
				if o != k and o.rank < k.rank and not o.finished:
					o.apply_hit("dizzy", events, k)
		"magnet":
			var target := race.kart_ahead(k)
			if target != null and race.gap_meters(k, target) < 110.0:
				k.magnet = 3.0
				k.magnet_target = target
				k.add_boost(3.0, 0.12, "magnet")
				events.append({"type": "magnet", "kart": k, "target": target})
			else:
				k.add_boost(1.4, 0.2, "magnet")
				events.append({"type": "magnet", "kart": k, "target": null})


## 车所在的路（主路或支路）与其上的位置
func _road(k: KartSim) -> TrackData:
	return track if k.branch < 0 else track.branches[k.branch]


func _road_s(k: KartSim) -> float:
	return k.s if k.branch < 0 else k.branch_s


## AI 避障：前方 range_s 采样内、横向 lat_tol 内的危险物
func hazard_ahead(k: KartSim, range_s: float, lat_tol: float) -> Dictionary:
	var n := track.n
	for list: Array[Dictionary] in [bananas, water_zones]:
		for h in list:
			var ds: float = h["s"] - k.s
			if ds < -n / 2.0:
				ds += n
			if ds > n / 2.0:
				ds -= n
			if ds > 0.0 and ds < range_s and absf(float(h["lateral"]) - k.lateral) < lat_tol:
				return h
	return {}
