class_name GpAward
extends MenuPage
## 杯赛颁奖：颁奖台放总积分前三；右侧奖杯（金 / 银 / 铜）+ 最终积分榜；提交大奖赛成绩（Store.submit_gp）。

const PANEL_W := 920.0
const TITLES: Array[String] = ["冠军！", "亚军！", "季军！"]

var _first: Control
var _trophy: Control
var _rows: Array[Control] = []
var _final: Dictionary = {}


func build() -> void:
	stage = "podium"
	_final = Game.gp_finish()
	var gp := Game.gp
	var rank: int = _final.get("rank", 8)
	var pts: int = _final.get("points", 0)

	# 左上：杯赛名 + 名次
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	head.offset_left = 70
	head.offset_top = 40
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var cup_l := Widgets.label("%s · %s规则" % [gp.get("cup_name", "大奖赛"), "道具" if str(gp.get("rule", "speed")) == "item" else "竞速"], 34)
	cup_l.add_theme_color_override("font_outline_color", UiTheme.CLOUD)
	cup_l.add_theme_constant_override("outline_size", 10)
	head.add_child(cup_l)
	var t := Widgets.title("总成绩 " + (TITLES[rank - 1] if rank <= 3 else "第 %d 名" % rank), 96,
		UiTheme.SUN if rank <= 3 else UiTheme.CLOUD, false, 16)
	head.add_child(t)
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 12)
	head.add_child(badges)
	badges.add_child(Widgets.badge("总积分 %d 分" % pts, UiTheme.WHITE, 28))
	if _final.get("improved", false):
		badges.add_child(Widgets.badge("新纪录：最好名次", UiTheme.SUN, 28))

	# 右侧：奖杯 + 最终积分
	var panel := Widgets.panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -56 - PANEL_W
	panel.offset_right = -56
	panel.offset_top = 40
	panel.offset_bottom = -40
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	v.add_child(top)
	if rank <= 3:
		var tr := Widgets.Trophy.new(UiTheme.rank_color(rank))
		tr.custom_minimum_size = Vector2(230, 250)
		top.add_child(tr)
		_trophy = tr
	else:
		var md := Widgets.Icon.new("star", 200.0, UiTheme.BUBBLE)
		top.add_child(md)
		_trophy = md
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 8)
	top.add_child(tv)
	var cup_names: Array[String] = ["金杯", "银杯", "铜杯"]
	tv.add_child(Widgets.title(cup_names[rank - 1] if rank <= 3 else "再接再厉！", 64, UiTheme.rank_color(rank) if rank <= 3 else UiTheme.BUBBLE, false, 12))
	var msg := "恭喜夺得%s！" % gp.get("cup_name", "") if rank == 1 else ("登上领奖台，下次冲击冠军！" if rank <= 3 else "前三名才能拿到奖杯，再来一次吧。")
	var ml := Widgets.label(msg, 26, UiTheme.INK_2)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(ml)
	var rec: Dictionary = Store.gp_records.get(str(gp.get("cup_id", "")), {})
	if not rec.is_empty():
		tv.add_child(Widgets.label("本杯最好：第 %d 名 · %d 分 · 夺冠 %d 次" % [int(rec["best_rank"]), int(rec["best_points"]), int(rec["wins"])], 22, UiTheme.INK_2))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	var st := Game.gp_standings()
	for i in st.size():
		var row := _row(st[i], i + 1)
		list.add_child(row)
		_rows.append(row)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	btns.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btns)
	var again := Widgets.button("再战一次", "normal", "retry", UiTheme.BUBBLE)
	again.pressed.connect(func() -> void: Game.gp_restart())
	btns.add_child(again)
	var home := Widgets.button("返回菜单", "primary", "home", UiTheme.WHITE)
	home.click_sound = "ui_back"
	home.pressed.connect(func() -> void: Game.goto_menu("main"))
	btns.add_child(home)
	_first = home
	AudioMgr.play("win" if rank <= 3 else "lose")


func _row(r: Dictionary, rank: int) -> Control:
	var is_p: bool = r["is_player"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SUN_LIGHT if is_p else UiTheme.WHITE, 12, 3 if is_p else 2,
		UiTheme.INK if is_p else Color(UiTheme.INK, 0.25), 3 if is_p else 0, Vector4(14, 2, 14, 2)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var rc := Control.new()
	rc.custom_minimum_size = Vector2(48, 44)
	rc.draw.connect(func() -> void:
		var c := Vector2(22, rc.size.y / 2.0)
		Widgets.draw_disc(rc, c, 18.0, UiTheme.rank_color(rank), 3.0)
		var f := UiTheme.font_num()
		var s := str(rank)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		rc.draw_string(f, c + Vector2(-w / 2.0, 7.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.INK))
	h.add_child(rc)
	var av := PortraitBaker.Avatar.new(str(r["character_id"]), 42.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var nm := Widgets.label(("%s（你）" % r["name"]) if is_p else str(r["name"]), 26)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var pl := Widgets.label("%d 分" % int(r["points"]), 26, UiTheme.INK, true)
	pl.add_theme_font_override("font", UiTheme.font_cn())
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pl)
	return p


func on_enter() -> void:
	if _trophy:
		_trophy.pivot_offset = _trophy.custom_minimum_size / 2.0
		_trophy.scale = Vector2.ONE * 0.2
		_trophy.rotation = -0.6
		var tw := _trophy.create_tween().set_parallel()
		tw.tween_property(_trophy, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(0.3)
		tw.tween_property(_trophy, "rotation", 0.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)
	Widgets.stagger_in(_rows, 0.05, 0.5)


func default_focus() -> Control:
	return _first


func on_back() -> bool:
	Game.goto_menu("main")
	return true


func view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var right := vp.x - 56.0 - PANEL_W - 30.0
	return Rect2(0.02, 0.3, maxf(0.2, right / vp.x - 0.02), 0.68)


func podium_rows() -> Array:
	return Game.gp_standings().slice(0, 3)
