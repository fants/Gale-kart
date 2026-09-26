class_name GpStandings
extends MenuPage
## 大奖赛积分榜：先按本场之前的积分排好，依次弹出「+N」并滚动加分，再动画重新排序。
## 按钮：下一场（显示下一条赛道）或颁奖典礼；退出大奖赛（确认）。

const PANEL_W := 920.0
const ROW_H := 70.0
const ROW_GAP := 8.0

var _rows: Dictionary = {}          # character_id → {panel, pts_label, gain, rank_draw, from, to, shown}
var _list: Control
var _first: Control
var _anim_t := -1.0
var _sorted := false
var _new_order: Array[Dictionary] = []


func build() -> void:
	stage = "podium"
	add_child(Widgets.pin(Widgets.creator_badge(1.0), Control.PRESET_BOTTOM_LEFT, Vector2(70, 40)))
	var gp := Game.gp
	var tracks: Array = gp.get("tracks", [])
	var done := int(gp.get("index", 0)) + 1

	# 左上标题
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	head.offset_left = 70
	head.offset_top = 40
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 18)
	head.add_child(hr)
	hr.add_child(Widgets.Icon.new("cup_" + str(gp.get("cup_id", "star")), 110.0, UiTheme.SUN))
	hr.add_child(Widgets.title(str(gp.get("cup_name", "大奖赛")), 96, UiTheme.SUN, false, 16))
	var sub := Widgets.label("第 %d / %d 场结束 · 积分榜" % [done, tracks.size()], 32)
	sub.add_theme_color_override("font_outline_color", UiTheme.CLOUD)
	sub.add_theme_constant_override("outline_size", 10)
	head.add_child(sub)
	var prog := HBoxContainer.new()
	prog.add_theme_constant_override("separation", 10)
	head.add_child(prog)
	var results: Array = gp.get("results", [])
	for i in tracks.size():
		var tname := str(TracksData.track_by_id(str(tracks[i]))["name"])
		var txt := tname
		var col := UiTheme.WHITE
		if i < results.size():
			var rr: Dictionary = results[i]
			txt = "%s  第 %d 名" % [tname, int(rr["rank"])]
			col = UiTheme.MINT
		elif i == done:
			txt = "下一场：" + tname
			col = UiTheme.SUN
		prog.add_child(Widgets.badge(txt, col, 22))

	# 右侧积分表
	var panel := Widgets.panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -56 - PANEL_W
	panel.offset_right = -56
	panel.offset_top = 40
	panel.offset_bottom = -40
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 14)
	v.add_child(ph)
	ph.add_child(Widgets.Icon.new("medal", 46.0))
	var pt := Widgets.title("车手积分", 46, UiTheme.SUN, false, 10)
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pt)
	var pb := Widgets.badge("10 / 8 / 6 / 5 / 4 / 3 / 2 / 1", UiTheme.SKY_PALE, 20)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(pb)

	var prev := Game.gp_standings(true)
	_new_order = Game.gp_standings(false)
	_list = Control.new()
	_list.custom_minimum_size = Vector2(0, prev.size() * (ROW_H + ROW_GAP))
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_list)
	var prev_pts: Dictionary = gp.get("prev_points", {})
	for i in prev.size():
		var r: Dictionary = prev[i]
		var cid: String = r["character_id"]
		var row := _row(r, i + 1, int(prev_pts.get(cid, 0)))
		_list.add_child(row["panel"] as Control)
		(row["panel"] as Control).position = Vector2(0, i * (ROW_H + ROW_GAP))
		_rows[cid] = row

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	btns.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btns)
	var quit := Widgets.button("退出大奖赛", "danger", "exit", UiTheme.SUN_LIGHT)
	quit.click_sound = "ui_back"
	quit.pressed.connect(_ask_quit)
	btns.add_child(quit)
	if Game.gp_is_last_race():
		var award := Widgets.button("颁奖典礼", "primary", "trophy", UiTheme.WHITE)
		award.click_sound = "ui_confirm"
		award.pressed.connect(func() -> void: root.replace("gp_award"))
		btns.add_child(award)
		_first = award
	else:
		var next_id := str(tracks[done]) if done < tracks.size() else ""
		var nx := Widgets.button("下一场：%s" % TracksData.track_by_id(next_id)["name"], "primary", "next", UiTheme.WHITE)
		nx.click_sound = "ui_confirm"
		nx.pressed.connect(func() -> void: Game.gp_next())
		btns.add_child(nx)
		_first = nx


func _row(r: Dictionary, rank: int, pts: int) -> Dictionary:
	var is_p: bool = r["is_player"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SUN_LIGHT if is_p else UiTheme.WHITE, 14, 3 if is_p else 2,
		UiTheme.INK if is_p else Color(UiTheme.INK, 0.25), 3 if is_p else 0, Vector4(16, 4, 16, 4)))
	p.size = Vector2(PANEL_W - 56.0, ROW_H)
	p.custom_minimum_size = Vector2(PANEL_W - 56.0, ROW_H)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var rc := Control.new()
	rc.custom_minimum_size = Vector2(56, 56)
	rc.set_meta("rank", rank)
	rc.draw.connect(func() -> void:
		var rk: int = rc.get_meta("rank")
		var c := Vector2(26, rc.size.y / 2.0)
		Widgets.draw_disc(rc, c, 23.0, UiTheme.rank_color(rk), 3.0)
		var f := UiTheme.font_num()
		var s := str(rk)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		rc.draw_string(f, c + Vector2(-w / 2.0, 9.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiTheme.INK))
	h.add_child(rc)
	var cid: String = r["character_id"]
	var av := PortraitBaker.Avatar.new(cid, 54.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var nm := Widgets.label(("%s（你）" % r["name"]) if is_p else str(r["name"]), 30)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var kd := KartsData.kart_by_id(str(r["kart_id"]))
	var kl := Widgets.label(str(kd["name"]), 22, UiTheme.INK_2)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(kl)
	var gain: int = r["gain"]
	var gb := Widgets.badge("+%d" % gain, UiTheme.MINT, 24)
	gb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gb.modulate.a = 0.0
	gb.custom_minimum_size = Vector2(70, 0)
	h.add_child(gb)
	var pl := Widgets.label(str(pts), 36, UiTheme.INK, true)
	pl.custom_minimum_size = Vector2(80, 0)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pl)
	var unit := Widgets.label("分", 22, UiTheme.INK_2)
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(unit)
	return {"panel": p, "pts": pl, "gain_badge": gb, "rank": rc, "from": pts, "to": pts + gain, "gain": gain}


func on_enter() -> void:
	var panels: Array = []
	for cid: String in _rows:
		panels.append(_rows[cid]["panel"])
	Widgets.stagger_in(panels, 0.05, 0.25)
	_anim_t = 0.0


func _process(dt: float) -> void:
	if _anim_t < 0.0:
		return
	_anim_t += dt
	# 1) 依次弹出 +N 并滚动加分
	var i := 0
	for cid: String in _rows:
		var row: Dictionary = _rows[cid]
		var start := 0.9 + i * 0.09
		var gb: Control = row["gain_badge"]
		if _anim_t >= start and gb.modulate.a == 0.0 and int(row["gain"]) > 0:
			gb.modulate.a = 1.0
			gb.pivot_offset = gb.size / 2.0
			gb.scale = Vector2.ONE * 0.3
			gb.create_tween().tween_property(gb, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			AudioMgr.play("ui_hover", {"pitch": 1.0 + i * 0.06})
		var u := clampf((_anim_t - start) / 0.7, 0.0, 1.0)
		var shown := int(round(lerpf(float(row["from"]), float(row["to"]), u)))
		(row["pts"] as Label).text = str(shown)
		i += 1
	# 2) 重新排序
	if not _sorted and _anim_t > 2.2:
		_sorted = true
		for k in _new_order.size():
			var cid: String = _new_order[k]["character_id"]
			if not _rows.has(cid):
				continue
			var p: Control = _rows[cid]["panel"]
			var tw := p.create_tween()
			tw.tween_property(p, "position:y", k * (ROW_H + ROW_GAP), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var rc: Control = _rows[cid]["rank"]
			rc.set_meta("rank", k + 1)
			rc.queue_redraw()
		AudioMgr.play("ui_confirm")
	if _anim_t > 3.0:
		_anim_t = -1.0


func _ask_quit() -> void:
	root.confirm("退出大奖赛？本杯赛的积分将不会保存。", "退出", func() -> void: Game.quit_race())


func default_focus() -> Control:
	return _first


func on_back() -> bool:
	_ask_quit()
	return true


func view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var right := vp.x - 56.0 - PANEL_W - 30.0
	return Rect2(0.02, 0.36, maxf(0.2, right / vp.x - 0.02), 0.62)


## 颁奖台上放当前积分前三
func podium_rows() -> Array:
	var st := Game.gp_standings(false)
	return st.slice(0, 3)
