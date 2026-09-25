class_name RecordsScreen
extends MenuPage
## 最佳纪录：每条赛道 × 竞速 / 道具 / 计时 的 3 圈最佳总用时与最快单圈，以及两个杯赛的大奖赛最好名次。

const MODES: Array[Array] = [["speed", "竞速赛", UiTheme.BUBBLE], ["item", "道具赛", UiTheme.PINK], ["time", "计时赛", UiTheme.MINT]]

var _close: Control
var _rows: Array[Control] = []


func build() -> void:
	dim = 1.0
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := Widgets.panel()
	card.custom_minimum_size = Vector2(1560, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	head.add_child(Widgets.Icon.new("medal", 64.0))
	var t := Widgets.title("最佳纪录", 60, UiTheme.SUN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Widgets.icon_button("check", "关闭", 68.0, UiTheme.MINT)
	close.click_sound = "ui_back"
	close.pressed.connect(func() -> void: root.back())
	head.add_child(close)
	_close = close

	# 表头
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 14)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 16)
	hm.add_theme_constant_override("margin_right", 16)
	hm.add_child(hdr)
	v.add_child(hm)
	var th := Widgets.label("赛道", 24, UiTheme.INK_2)
	th.custom_minimum_size = Vector2(380, 0)
	hdr.add_child(th)
	for m: Array in MODES:
		var hb := HBoxContainer.new()
		hb.custom_minimum_size = Vector2(330, 0)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(Widgets.badge(str(m[1]), m[2] as Color, 22))
		hdr.add_child(hb)

	for tdef in TracksData.TRACKS:
		var row := _track_row(tdef)
		v.add_child(row)
		_rows.append(row)

	# 大奖赛
	var gp_head := Widgets.section("大奖赛")
	v.add_child(gp_head)
	var cups := HBoxContainer.new()
	cups.add_theme_constant_override("separation", 16)
	v.add_child(cups)
	for cup in TracksData.CUPS:
		var cc := _cup_card(cup)
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cups.add_child(cc)
		_rows.append(cc)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	var note := Widgets.note("纪录保存在本机存档中；3 圈成绩计入总用时纪录，计时赛同时保存最佳一局的幽灵车。", 20)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(note)
	var hints := Widgets.hint_bar([["Esc", "B", "返回"]])
	foot.add_child(hints)


func _track_row(tdef: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.WHITE, 14, 2, Color(UiTheme.INK, 0.3), 0, Vector4(16, 6, 16, 6)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var name_box := HBoxContainer.new()
	name_box.custom_minimum_size = Vector2(380, 0)
	name_box.add_theme_constant_override("separation", 14)
	h.add_child(name_box)
	var theme := ThemesData.get_theme(str(tdef["theme"]))
	var thumb := Widgets.TrackThumb.new(str(tdef["id"]))
	thumb.custom_minimum_size = Vector2(110, 68)
	thumb.bg_color = Color(str((theme["ground"] as Dictionary)["base"]))
	thumb.line_color = Color(str((theme["road"] as Dictionary)["base"])).lightened(0.4)
	thumb.line_w = 3.5
	thumb.pad = 8.0
	thumb.show_start = false
	name_box.add_child(thumb)
	var nv := VBoxContainer.new()
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.add_theme_constant_override("separation", -2)
	name_box.add_child(nv)
	nv.add_child(Widgets.label(str(tdef["name"]), 30))
	nv.add_child(Widgets.label(str(tdef["en"]), 14, UiTheme.INK_2, true))
	for m: Array in MODES:
		var r := Store.record(str(tdef["id"]), str(m[0]))
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(330, 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 0)
		h.add_child(cell)
		var bt: Variant = r.get("best_total")
		var bl: Variant = r.get("best_lap")
		var tl := Widgets.label(MathX.format_time(float(bt)) if bt != null else "—", 28, UiTheme.INK if bt != null else UiTheme.GRAY, true)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(tl)
		var sub := "最快单圈 %s" % MathX.format_time(float(bl)) if bl != null else "暂无纪录"
		if bl != null and int(r.get("races", 0)) > 0:
			sub += " · %d 场" % int(r["races"])
		var sl := Widgets.label(sub, 18, UiTheme.INK_2)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(sl)
	return p


func _cup_card(cup: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.SKY_PALE, 16, 3, UiTheme.INK, 0, Vector4(18, 10, 18, 10)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	var rec: Dictionary = Store.gp_records.get(str(cup["id"]), {})
	var best := int(rec.get("best_rank", 99))
	h.add_child(Widgets.Icon.new("trophy", 64.0, UiTheme.rank_color(best) if best <= 3 else UiTheme.GRAY))
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 0)
	h.add_child(cv)
	cv.add_child(Widgets.label(str(cup["name"]), 32))
	var names: Array[String] = []
	for tid: Variant in cup["tracks"]:
		names.append(str(TracksData.track_by_id(str(tid))["name"]))
	cv.add_child(Widgets.label(" · ".join(names), 20, UiTheme.INK_2))
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(rv)
	if rec.is_empty():
		rv.add_child(Widgets.badge("尚未参赛", UiTheme.WHITE, 22))
	else:
		rv.add_child(Widgets.badge("最好第 %d 名 · %d 分" % [best, int(rec["best_points"])], UiTheme.rank_color(best) if best <= 3 else UiTheme.WHITE, 24))
		var wl := Widgets.label("夺冠 %d 次" % int(rec["wins"]), 20, UiTheme.INK_2)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rv.add_child(wl)
	return p


func on_enter() -> void:
	Widgets.stagger_in(_rows, 0.04, 0.1)


func default_focus() -> Control:
	return _close


func view_rect() -> Rect2:
	return Rect2(0.3, 0.15, 0.4, 0.7)
