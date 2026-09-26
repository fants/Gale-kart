class_name EventRouter
extends RefCounted
## 仿真事件 → HUD 文字、音效（2D / 3D）、特效、相机震动、手柄震动。映射同参考版 main.js 的 handleEvents。

## RaceController 或 ReplayPlayer（鸭子类型：需要 focus_kart() all_karts() vibrate() on_player_finish()
## 与 effects hud rig camera 成员）
var ctl
## 回放模式：只触发特效和音效，不改 HUD、不震动手柄
var replay := false


func _init(p_ctl: Node) -> void:
	ctl = p_ctl


func _sfx_at(name: String, pos: Vector3, opts := {}) -> void:
	var cam: Camera3D = ctl.camera
	AudioMgr.play_at(name, pos, cam.global_transform, opts)


func _kpos(k: KartSim) -> Vector3:
	return Vector3(k.x, k.y, k.z)


func handle(events: Array[Dictionary]) -> void:
	var p: KartSim = ctl.focus_kart()
	var fx: Effects = ctl.effects
	var hud: Hud = ctl.hud
	for e in events:
		var k: KartSim = e.get("kart")
		var me := k != null and k == p
		match e["type"]:
			"countdown":
				if not replay:
					hud.big(str(e["value"]))
				AudioMgr.play("countdown")
			"go":
				if not replay:
					hud.big("GO!", {"color": Color("#45E3A6")})
				AudioMgr.play("go")
			"start_boost":
				if me:
					if not replay:
						hud.sub("完美起步！", Color("#45E3A6"))
					AudioMgr.play("start_boost")
					fx.burst("boost", _kpos(k))
					ctl.vibrate(0.3, 0.2, 0.25)
			"false_start":
				if me:
					if not replay:
						hud.sub("抢跑了！", Color("#FF4D5E"))
					AudioMgr.play("false_start")
			"nitro":
				if me:
					AudioMgr.play("nitro")
					ctl.rig.shake(0.25)
					fx.burst("boost", _kpos(k))
					ctl.vibrate(0.4, 0.3, 0.3)
				else:
					_sfx_at("nitro", _kpos(k), {"volume": 0.45, "range": 60.0})
			"instant_ready":
				if me and not replay:
					hud.show_instant_cue(true)
					AudioMgr.play("instant_ready", {"volume": 0.6})
			"instant_boost":
				if me:
					if not replay:
						hud.show_instant_cue(false)
						hud.sub("瞬间加速！", Color("#3EC6FF"))
					AudioMgr.play("instant_boost")
					fx.burst("instant", _kpos(k))
					ctl.vibrate(0.25, 0.1, 0.15)
			"boost_pad":
				if me:
					AudioMgr.play("boost_pad")
					ctl.vibrate(0.3, 0.1, 0.2)
				else:
					_sfx_at("boost_pad", _kpos(k), {"volume": 0.4, "range": 50.0})
				fx.burst("boost", _kpos(k))
			"draft":
				if me:
					if not replay:
						hud.sub("尾流加速！", Color("#B98CFF"))
					AudioMgr.play("draft")
			"cliff_fall":
				if me:
					if not replay:
						hud.sub("掉下悬崖！走崖下小路绕回去", Color("#FF8A5B"))
					AudioMgr.play("wrong_way")
					ctl.rig.shake(0.3)
			"gauge_full":
				if me:
					AudioMgr.play("gauge_full")
			"drift_start":
				pass
			"wall_hit":
				var side: float = e["side"]
				var wp := _kpos(k) + Vector3(k.proj.nx, 0.0, k.proj.nz) * side * 1.0
				fx.burst("wall", wp, {"strength": e["strength"]})
				if me:
					AudioMgr.play("wall_hit", {"strength": e["strength"]})
					ctl.rig.shake(float(e["strength"]) * 0.7)
					ctl.vibrate(0.2, float(e["strength"]) * 0.7, 0.15)
				else:
					_sfx_at("wall_hit", wp, {"strength": e["strength"], "volume": 0.6, "range": 50.0})
			"kart_hit":
				var pos: Vector3 = e["pos"]
				fx.burst("kart", pos)
				if e["a"] == p or e["b"] == p:
					AudioMgr.play("kart_hit", {"strength": e["strength"]})
					ctl.rig.shake(float(e["strength"]) * 0.5)
					ctl.vibrate(0.3, float(e["strength"]) * 0.5, 0.15)
				else:
					_sfx_at("kart_hit", pos, {"strength": e["strength"], "volume": 0.6, "range": 50.0})
			"land":
				fx.burst("land", _kpos(k), {"strength": e["strength"]})
				if me:
					AudioMgr.play("land", {"strength": e["strength"]})
					ctl.rig.shake(float(e["strength"]) * 0.4)
					ctl.vibrate(0.2, float(e["strength"]) * 0.6, 0.18)
			"item_box":
				var bp: Vector3 = e["box"]["pos"]
				fx.burst("shards", bp + Vector3(0, 1.0, 0))
				if me:
					AudioMgr.play("item_get", {"volume": 0.5})
				else:
					_sfx_at("item_use", bp, {"volume": 0.4, "range": 40.0})
			"item_use":
				if me:
					AudioMgr.play("item_use")
			"item_swap":
				if me:
					AudioMgr.play("ui_click")
			"missile_launch":
				_sfx_at("missile_launch", _kpos(k), {"range": 80.0})
				if e["target"] == p and not replay:
					hud.sub("导弹来袭！", Color("#FF4D5E"))
			"water_fly_launch":
				_sfx_at("water_fly", _kpos(k), {"range": 80.0})
				if e["target"] == p and not replay:
					hud.sub("水苍蝇来袭！", Color("#45C8FF"))
			"explosion":
				var ep: Vector3 = e["pos"]
				fx.burst("explosion", ep)
				_sfx_at("explosion", ep, {"strength": 1.0, "range": 120.0})
				var d := ep.distance_to(_kpos(p))
				if d < 40.0:
					ctl.rig.shake((1.0 - d / 40.0) * 1.1)
					ctl.vibrate(0.5, (1.0 - d / 40.0), 0.3)
			"water_throw":
				_sfx_at("water_throw", _kpos(k), {"range": 60.0})
			"water_splash":
				var sp: Vector3 = e["pos"]
				fx.burst("splash", sp)
				_sfx_at("water_splash", sp, {"range": 80.0})
			"bubble":
				if me:
					if not replay:
						hud.sub("被水泡困住了！", Color("#3EC6FF"))
					AudioMgr.play("bubble")
			"banana_drop":
				_sfx_at("banana", _kpos(k), {"volume": 0.7, "range": 50.0})
			"banana_hit":
				var bp2: Vector3 = e["pos"]
				fx.burst("banana", bp2)
				_sfx_at("spin", bp2, {"range": 60.0})
			"hit":
				var src: KartSim = e.get("source")
				if me and not replay:
					match e["kind"]:
						"spin": hud.sub("哎呀，打滑了！", Color("#FFC93C"))
						"flip": hud.sub("被导弹击中！", Color("#FF4D5E"))
						"dizzy": hud.sub("被雷暴击晕！", Color("#FFE14A"))
					ctl.vibrate(0.6, 0.8, 0.4)
				elif src == p and src != null and not replay:
					hud.sub("命中 %s！" % k.name, Color("#45E3A6"))
			"shield":
				fx.burst("shield", _kpos(k))
				_sfx_at("shield", _kpos(k), {"range": 60.0})
			"shield_block":
				fx.burst("shield", _kpos(k))
				_sfx_at("shield_block", _kpos(k), {"range": 70.0})
				if me and not replay:
					hud.sub("护盾挡住了攻击！", Color("#FFF3A8"))
			"cloud":
				var src2: KartSim = e.get("source")
				if me:
					if not replay:
						hud.sub("乌云笼罩！", Color("#8A8FA8"))
					AudioMgr.play("cloud")
				elif src2 == p:
					if not replay:
						hud.sub("乌云飘向 %s" % k.name)
					AudioMgr.play("cloud", {"volume": 0.5})
			"ufo":
				var src3: KartSim = e.get("source")
				if me:
					if not replay:
						hud.sub("飞碟来了，道具被封印！", Color("#B98CFF"))
					AudioMgr.play("ufo")
				elif src3 == p:
					if not replay:
						hud.sub("飞碟飞向 %s" % k.name)
					AudioMgr.play("ufo", {"volume": 0.5})
			"thunder":
				if not replay:
					hud.flash()
				AudioMgr.play("thunder")
				for o: KartSim in ctl.all_karts():
					if o.dizzy > 1.9:
						fx.burst("thunder", _kpos(o))
				if not me and p.dizzy > 0.0:
					ctl.rig.shake(0.8)
			"magnet":
				if me:
					AudioMgr.play("magnet")
			"lap":
				if me and not replay:
					var done: int = int(e["lap"]) - 1
					hud.add_lap_time(done, e["time"], float(e["time"]) <= k.best_lap + 1e-6)
					if e["final"]:
						hud.big("最后一圈！", {"cn": true, "color": Color("#FFC93C")})
						AudioMgr.play("final_lap")
						AudioMgr.set_music_tempo(1.06)
					else:
						hud.sub("第 %d 圈  %s" % [e["lap"], MathX.format_time(e["time"])])
						AudioMgr.play("lap")
			"finish":
				if me and not replay:
					ctl.on_player_finish(e)
			"respawn":
				fx.burst("respawn", _kpos(k))
				if me:
					AudioMgr.play("respawn")
