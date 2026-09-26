class_name ResultsScreen
extends MenuPage
## 结算页：左侧 3D 颁奖台（前三名）+ 大号名次与标题 + 徽章；右侧成绩表 + 按钮。
## 按钮：精彩回放（summary.replay 非空才显示）、再来一局、下一赛道、返回菜单；大奖赛中为「查看积分榜」。

const PANEL_W := 1000.0
const TITLES: Array[String] = ["冠军！", "亚军！", "季军！"]
const MODE_NAMES := {"speed": "竞速赛", "item": "道具赛", "time": "计时赛"}

var summary: Dictionary = {}
var in_gp := false
var _first: Control
var _rows: Array[Control] = []
var _head: Control
var _rank_label: Label
var _panel: Control


func build() -> void:
	stage = "podium"
	add_child(Widgets.pin(Widgets.creator_badge(1.0), Control.PRESET_BOTTOM_LEFT, Vector2(70, 40)))
	summary = params.get("summary", {})
	in_gp = not Game.gp.is_empty()
	var solo: bool = summary.get("solo", false)
	var rank: int = summary.get("rank", 1)
	var mode: String = summary.get("mode", "speed")

	# ———— 左上：名次 + 标题 + 徽章 ————
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	head.offset_left = 70
	head.offset_top = 36
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	_head = head
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 26)
	head.add_child(hrow)
	var rank_text := "★" if solo else str(rank)
	var rank_col := UiTheme.SUN if solo else UiTheme.rank_color(rank)
	if not solo and rank > 3:
		rank_col = UiTheme.CLOUD
	_rank_label = Widgets.title(rank_text, 170, rank_col, not solo, 20)
	_rank_label.add_theme_constant_override("shadow_offset_y", 12)
	_rank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(_rank_label)
	var tcol := VBoxContainer.new()
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", 4)
	hrow.add_child(tcol)
	var title_text := "完成挑战！" if solo else (TITLES[rank - 1] if rank >= 1 and rank <= 3 else "第 %d 名" % rank)
	tcol.add_child(Widgets.title(title_text, 92, UiTheme.SUN if (solo or rank <= 3) else UiTheme.CLOUD, false, 16))
	var sub := "%s · %s · %d 圈" % [MODE_NAMES.get(mode, "竞速赛"), summary.get("track_name", ""), int(summary.get("laps", 3))]
	if in_gp:
		var tracks: Array = Game.gp["tracks"]
		sub = "%s 第 %d / %d 场 · %s" % [Game.gp["cup_name"], int(Game.gp["index"]) + 1, tracks.size(), sub]
	var sl := Widgets.label(sub, 30, UiTheme.INK)
	sl.add_theme_color_override("font_outline_color", UiTheme.CLOUD)
	sl.add_theme_constant_override("outline_size", 10)
	tcol.add_child(sl)
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 12)
	head.add_child(badges)
	badges.add_child(Widgets.badge("总用时  %s" % MathX.format_time(float(summary.get("total", -1.0))), UiTheme.WHITE, 26))
	var bl: float = summary.get("best_lap", INF)
	badges.add_child(Widgets.badge("最快单圈  %s" % (MathX.format_time(bl) if is_finite(bl) else "—"), UiTheme.WHITE, 26))
	var badges2 := HBoxContainer.new()
	badges2.add_theme_constant_override("separation", 12)
	head.add_child(badges2)
	var rec: Dictionary = summary.get("record", {})
	if rec.get("new_best_total", false):
		badges2.add_child(Widgets.badge("新纪录：总用时", UiTheme.SUN, 26))
	if rec.get("new_best_lap", false):
		badges2.add_child(Widgets.badge("新纪录：最快单圈", UiTheme.SUN, 26))
	var ghost: float = summary.get("ghost_total", -1.0)
	if mode == "time" and ghost > 0.0:
		var diff := float(summary.get("total", 0.0)) - ghost
		if diff <= 0.0:
			badges2.add_child(Widgets.badge("比幽灵车快 %.3f 秒" % absf(diff), UiTheme.MINT, 26))
		else:
			badges2.add_child(Widgets.badge("比幽灵车慢 %.3f 秒" % diff, Color("#FFB3BC"), 26))
	elif mode == "time":
		badges2.add_child(Widgets.badge("已保存为幽灵车", UiTheme.MINT, 26))
	if in_gp:
		var gain: int = (Game.gp["gains"] as Dictionary).get(_player_cid(), 0)
		badges2.add_child(Widgets.badge("本场积分 +%d" % gain, UiTheme.MINT, 26))

	# ———— 右侧：成绩表 + 按钮 ————
	var panel := Widgets.panel()
	if solo:
		# 计时赛只有一两行：面板按内容高度垂直居中
		panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		panel.offset_left = -56 - PANEL_W
		panel.offset_right = -56
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		panel.offset_left = -56 - PANEL_W
		panel.offset_right = -56
		panel.offset_top = 40
		panel.offset_bottom = -40
	add_child(panel)
	_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 14)
	v.add_child(ph)
	ph.add_child(Widgets.Icon.new("flag", 46.0))
	var pt := Widgets.title("比赛成绩", 46, UiTheme.SUN, false, 10)
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pt)
	var tb := Widgets.badge(str(summary.get("track_name", "")), UiTheme.SKY_PALE, 24)
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(tb)
	v.add_child(_table_header())
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	var rows: Array = summary.get("rows", [])
	for r: Dictionary in rows:
		var row := _row(r)
		list.add_child(row)
		_rows.append(row)
	if solo and ghost > 0.0:
		var gr := _row({"rank": 0, "name": "幽灵车", "is_player": false, "kart_id": "", "kart_name": "最佳纪录",
			"character_id": "", "paint_id": "", "time": ghost, "estimated": false, "best_lap": INF}, true)
		list.add_child(gr)
		_rows.append(gr)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btns)
	btns.child_entered_tree.connect(func(n: Node) -> void:
		(n as Control).add_theme_font_size_override("font_size", 30))
	var replay: Dictionary = summary.get("replay", {})
	if not replay.is_empty():
		var rb := Widgets.button("精彩回放", "normal", "replay", UiTheme.BUBBLE)
		rb.pressed.connect(func() -> void: Game.start_replay(replay))
		btns.add_child(rb)
	if in_gp:
		var sb := Widgets.button("查看积分榜", "primary", "trophy", UiTheme.WHITE)
		sb.click_sound = "ui_confirm"
		sb.pressed.connect(func() -> void: root.replace("gp_standings"))
		btns.add_child(sb)
		_first = sb
	else:
		var again := Widgets.button("再来一局", "primary", "retry", UiTheme.WHITE)
		again.click_sound = "ui_confirm"
		again.pressed.connect(func() -> void: Game.restart_race())
		btns.add_child(again)
		var nx := Widgets.button("下一赛道", "normal", "next", UiTheme.MINT)
		nx.pressed.connect(func() -> void: Game.next_track())
		btns.add_child(nx)
		var home := Widgets.button("返回菜单", "normal", "home", UiTheme.SUN)
		home.click_sound = "ui_back"
		home.pressed.connect(func() -> void: Game.goto_menu("main"))
		btns.add_child(home)
		_first = again


func _player_cid() -> String:
	for r: Dictionary in summary.get("rows", []):
		if r.get("is_player", false):
			return str(r["character_id"])
	return ""


## 列宽：名次、车手、赛车、总用时、最快单圈
const COLS: Array[float] = [64.0, 260.0, 170.0, 180.0, 150.0]


func _table_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var names: Array[String] = ["名次", "车手", "赛车", "总用时", "最快单圈"]
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_child(h)
	for i in names.size():
		var l := Widgets.label(names[i], 22, UiTheme.INK_2)
		l.custom_minimum_size = Vector2(COLS[i], 0)
		if i >= 3:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if i == 1:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return m


func _row(r: Dictionary, ghost := false) -> Control:
	var is_p: bool = r.get("is_player", false)
	var p := PanelContainer.new()
	var bg := UiTheme.SUN_LIGHT if is_p else (Color("#E8FBF4") if ghost else UiTheme.WHITE)
	p.add_theme_stylebox_override("panel", UiTheme.box(bg, 14, 3 if is_p else 2, UiTheme.INK if is_p else Color(UiTheme.INK, 0.25), 3 if is_p else 0, Vector4(16, 4, 16, 4)))
	p.custom_minimum_size = Vector2(0, 64)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var rank: int = r.get("rank", 0)
	var rc := Control.new()
	rc.custom_minimum_size = Vector2(COLS[0], 52)
	var rtext := "★" if ghost else str(rank)
	var rcol := UiTheme.MINT if ghost else UiTheme.rank_color(rank)
	rc.draw.connect(func() -> void:
		var c := Vector2(26, rc.size.y / 2.0)
		Widgets.draw_disc(rc, c, 22.0, rcol, 3.0)
		var f := UiTheme.font_num()
		var w := f.get_string_size(rtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		rc.draw_string(f, c + Vector2(-w / 2.0, 9.0), rtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiTheme.INK))
	h.add_child(rc)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.custom_minimum_size = Vector2(COLS[1], 0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(who)
	var cid: String = r.get("character_id", "")
	if cid != "":
		var av := PortraitBaker.Avatar.new(cid, 50.0)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.add_child(av)
		var ch := KartsData.character_by_id(cid)
		var nm := ("%s（你）" % ch["name"]) if is_p else str(r.get("name", ch["name"]))
		var nl := Widgets.label(nm, 28)
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.add_child(nl)
	else:
		var gi := Widgets.Icon.new("eye", 50.0, UiTheme.MINT)
		who.add_child(gi)
		var nl2 := Widgets.label(str(r.get("name", "")), 28)
		nl2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.add_child(nl2)
	var kart := HBoxContainer.new()
	kart.add_theme_constant_override("separation", 8)
	kart.custom_minimum_size = Vector2(COLS[2], 0)
	h.add_child(kart)
	var pid: String = r.get("paint_id", "")
	if pid != "":
		var d := Widgets.dot(Color(str(KartsData.paint_by_id(pid)["color"])), 20.0)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kart.add_child(d)
	var kl := Widgets.label(str(r.get("kart_name", "")), 24, UiTheme.INK_2)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kart.add_child(kl)
	var t: float = r.get("time", -1.0)
	var est: bool = r.get("estimated", false)
	var tl := Widgets.label(("约 " if est else "") + MathX.format_time(t), 26, UiTheme.INK_2 if est else UiTheme.INK, not est)
	if est:
		tl.add_theme_font_override("font", UiTheme.font_cn())
	tl.custom_minimum_size = Vector2(COLS[3], 0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	var bl: float = r.get("best_lap", INF)
	var bll := Widgets.label(MathX.format_time(bl) if is_finite(bl) else "—", 22, UiTheme.INK_2, true)
	bll.custom_minimum_size = Vector2(COLS[4], 0)
	bll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bll)
	return p


func on_enter() -> void:
	# 名次数字弹入，成绩行依次滑入
	_rank_label.pivot_offset = Vector2(60, 100)
	_rank_label.scale = Vector2.ONE * 0.2
	var tw := _rank_label.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_rank_label, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Widgets.stagger_in(_rows, 0.06, 0.3)


func default_focus() -> Control:
	return _first


func on_back() -> bool:
	if in_gp:
		root.replace("gp_standings")
	else:
		Game.goto_menu("main")
	return true


func view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var right := vp.x - 56.0 - PANEL_W - 30.0
	return Rect2(0.02, 0.33, maxf(0.2, right / vp.x - 0.02), 0.64)


func podium_rows() -> Array:
	var rows: Array = summary.get("rows", [])
	return rows.slice(0, 3)


func podium_solo() -> bool:
	return summary.get("solo", false)
