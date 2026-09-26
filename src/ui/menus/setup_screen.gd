class_name SetupScreen
extends MenuPage
## 赛前设置：左侧「赛事 / 车库」两个标签页，右侧 3D 车库实时预览 + 赛车六维属性 + 开始按钮。
## params.kind："quick" 快速比赛（竞速 / 道具）、"time" 计时赛（固定 3 圈）、"gp" 大奖赛（杯赛 + 规则）。
## params.tab：初始标签页（0 赛事 / 1 车库）。

const MODE_NAMES := {"speed": "竞速赛", "item": "道具赛", "time": "计时赛"}
const MODE_NOTES := {
	"speed": "漂移集气、释放氮气，和 7 位 AI 对手比拼纯速度。",
	"item": "撞碎道具箱获得道具，用导弹、水炸弹、香蕉皮扰乱对手。",
	"time": "独自冲刺最快成绩，最佳一局会作为幽灵车陪你跑。",
	"gp": "同一杯赛连跑 4 场，按名次得分（10 / 8 / 6 / 5 / 4 / 3 / 2 / 1），总分最高者夺冠。",
}
const TITLES := {"quick": "快速比赛", "time": "计时赛", "gp": "大奖赛"}
const LEFT_W := 1100.0
const RIGHT_MAX_W := 780.0

var kind := "quick"
var sel: Dictionary = {}
var tab := 0
var start_button: Widgets.PopButton

var _tab_btns: Array[Button] = []
var _pages: Array[Control] = []
var _track_cards: Dictionary = {}
var _cup_cards: Dictionary = {}
var _char_cards: Dictionary = {}
var _kart_cards: Dictionary = {}
var _paint_cards: Dictionary = {}
var _mode_note: Label
var _track_note: Label
var _char_name: Label
var _ghost_badge: Label
var _preview: Control
var _kart_title: Label
var _kart_en: Label
var _kart_tag: Label
var _kart_blurb: Label
var _stat_bars: Array[Widgets.StatBar] = []
var _summary: Label
var _summary_sub: Label
var _content_tw: Tween


func build() -> void:
	kind = str(params.get("kind", "quick"))
	tab = int(params.get("tab", 0))
	sel = Store.selection.duplicate()
	match kind:
		"time":
			sel["mode"] = "time"
			sel["laps"] = 3
		"gp":
			sel["mode"] = sel.get("gp_rule", "speed")
		_:
			if not sel.get("mode", "speed") in ["speed", "item"]:
				sel["mode"] = "speed"

	var m := margin_box()
	var root_row := HBoxContainer.new()
	root_row.add_theme_constant_override("separation", 40)
	root_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(root_row)

	# ———— 左栏 ————
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	left.add_theme_constant_override("separation", 16)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_row.add_child(left)
	left.add_child(top_bar(str(TITLES.get(kind, "快速比赛")), "单人挑战" if kind == "time" else ("四场积分" if kind == "gp" else "")))
	var panel := Widgets.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 16)
	panel.add_child(pv)
	pv.add_child(_build_tabs())
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.clip_contents = false
	pv.add_child(stack)
	var race_page := _build_race_tab()
	var garage_page := _build_garage_tab()
	for p: Control in [race_page, garage_page]:
		stack.add_child(p)
		Widgets.fill(p)
		_pages.append(p)
	var hints := Widgets.hint_bar([["←|→|↑|↓", "", "选择"], ["Enter", "A", "确定"], ["Q|E", "LB", "切换标签"], ["Esc", "B", "返回"]])
	hints.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(hints)

	# ———— 右栏：预览 + 属性 + 开始 ————
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 18)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_row.add_child(right)
	_preview = Control.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 右侧 3D 预览：按住鼠标左键左右拖动旋转车手与赛车
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_preview.gui_input.connect(_on_preview_input)
	_preview.resized.connect(func() -> void: root.refresh_view.call_deferred())
	right.add_child(_preview)
	var info := _build_info_card()
	right.add_child(info)
	start_button = Widgets.button("开始比赛" if kind != "gp" else "开始大奖赛", "primary", "flag", UiTheme.WHITE)
	start_button.custom_minimum_size = Vector2(0, 112)
	start_button.add_theme_font_size_override("font_size", 46)
	start_button.click_sound = "ui_confirm"
	start_button.pressed.connect(_start)
	right.add_child(start_button)
	# 带鱼屏上右栏很宽：属性卡与开始按钮限宽居中，预览区仍占满
	var clamp_w := func() -> void:
		var w := minf(right.size.x, RIGHT_MAX_W)
		for c: Control in [info, start_button]:
			c.custom_minimum_size.x = w
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.resized.connect(clamp_w)

	_set_tab(tab, false)
	_refresh()


# ———————————————————————— 标签页 ————————————————————————

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var tp := Widgets.panel("TabsPanel")
	row.add_child(tp)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	tp.add_child(tr)
	var q := Widgets.keycap("Q", false, 20)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(q)
	var group := ButtonGroup.new()
	var names: Array[String] = ["赛事", "车库"]
	var icons: Array[String] = ["flag", "gear"]
	for i in 2:
		var b := Widgets.button(names[i], "tab", icons[i], UiTheme.SUN if i == 0 else UiTheme.MINT)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(190, 62)
		var idx := i
		b.pressed.connect(func() -> void: _set_tab(idx, false))
		tr.add_child(b)
		_tab_btns.append(b)
	var e := Widgets.keycap("E", false, 20)
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(e)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	return row


func _set_tab(i: int, focus_content := true) -> void:
	tab = clampi(i, 0, _pages.size() - 1)
	for j in _tab_btns.size():
		_tab_btns[j].set_pressed_no_signal(j == tab)
	for j in _pages.size():
		_pages[j].visible = j == tab
	var page := _pages[tab]
	if _content_tw:
		_content_tw.kill()
	# 布局完成前改 position 会按最小尺寸重算偏移，所以只在已布局时做滑动
	var parent := page.get_parent() as Control
	if parent != null and parent.size.x >= 1.0:
		page.modulate.a = 0.0
		page.position.x = 40.0
		_content_tw = page.create_tween().set_parallel()
		_content_tw.tween_property(page, "modulate:a", 1.0, 0.18)
		_content_tw.tween_property(page, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if focus_content:
		Widgets.focus_quiet(default_focus())


func on_tab(dir: int) -> void:
	var n := (tab + dir + _pages.size()) % _pages.size()
	if n != tab:
		AudioMgr.play("ui_click")
		_set_tab(n, true)


# ———————————————————————— 赛事 ————————————————————————

func _build_race_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 44)
	v.add_child(row)
	match kind:
		"time":
			row.add_child(_option_block("模式", Widgets.badge("计时赛 · 单人", UiTheme.MINT, 26)))
			row.add_child(_option_block("圈数", Widgets.badge("3 圈（固定）", UiTheme.WHITE, 26)))
			var gb := Widgets.badge("暂无幽灵车", UiTheme.SKY_PALE, 26)
			_ghost_badge = gb.get_child(0) as Label
			row.add_child(_option_block("幽灵车", gb))
		"gp":
			var on_rule := func(v2: Variant) -> void:
				_pick_quiet("gp_rule", str(v2))
				_pick("mode", str(v2))
			row.add_child(_option_block("规则", Widgets.segmented([["speed", "竞速"], ["item", "道具"]], str(sel["mode"]), on_rule, 120.0)))
			row.add_child(_option_block("难度", _difficulty_seg()))
			row.add_child(_option_block("圈数", _laps_seg()))
		_:
			row.add_child(_option_block("模式", Widgets.segmented([["speed", "竞速赛"], ["item", "道具赛"]], str(sel["mode"]),
				func(v2: Variant) -> void: _pick("mode", str(v2)), 140.0)))
			row.add_child(_option_block("难度", _difficulty_seg()))
			row.add_child(_option_block("圈数", _laps_seg()))
	_mode_note = Widgets.note("", 22)
	v.add_child(_mode_note)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	head.add_child(Widgets.section("杯赛" if kind == "gp" else "赛道"))
	_track_note = Widgets.label("", 22, UiTheme.INK_2)
	_track_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_track_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_track_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_track_note)

	if kind == "gp":
		var cups := HBoxContainer.new()
		cups.add_theme_constant_override("separation", 20)
		v.add_child(cups)
		var group := ButtonGroup.new()
		for cup in TracksData.CUPS:
			var c := _cup_card(cup)
			c.button_group = group
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cups.add_child(c)
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 16)
		v.add_child(grid)
		var group := ButtonGroup.new()
		for t in TracksData.TRACKS:
			var c := _track_card(t)
			c.button_group = group
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(c)
	return v


func _option_block(title: String, control: Control) -> Control:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 10)
	b.add_child(Widgets.label(title, 26, UiTheme.INK_2))
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_child(control)
	return b


func _difficulty_seg() -> Control:
	return Widgets.segmented([["easy", "简单"], ["normal", "普通"], ["hard", "困难"]], str(sel.get("difficulty", "normal")),
		func(v: Variant) -> void: _pick("difficulty", str(v)), 96.0)


func _laps_seg() -> Control:
	return Widgets.segmented([[1, "1 圈"], [3, "3 圈"], [5, "5 圈"]], int(sel.get("laps", 3)),
		func(v: Variant) -> void: _pick("laps", int(v)), 96.0)


func _track_card(t: Dictionary) -> Widgets.PopButton:
	var id := str(t["id"])
	var theme := ThemesData.get_theme(str(t["theme"]))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var thumb := Widgets.TrackThumb.new(id)
	thumb.custom_minimum_size = Vector2(0, 112)
	thumb.bg_color = Color(str((theme["ground"] as Dictionary)["base"]))
	thumb.line_color = Color(str((theme["road"] as Dictionary)["base"])).lightened(0.4)
	thumb.line_w = 6.0
	thumb.pad = 12.0
	v.add_child(thumb)
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	var nm := Widgets.label(str(t["name"]), 26)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(nm)
	var stars := Widgets.star_rating(int(t["difficulty"]), 3, 18.0)
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(stars)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	var en := Widgets.label(str(t["en"]), 15, UiTheme.INK_2, true)
	en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	en.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(en)
	var best := Widgets.label("", 18, UiTheme.INK, true)
	best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(best)
	var c := Widgets.card(v, Vector2(240, 212))
	c.set_meta("best", best)
	c.pressed.connect(func() -> void: _pick("track_id", id))
	_track_cards[id] = c
	return c


func _cup_card(cup: Dictionary) -> Widgets.PopButton:
	var id := str(cup["id"])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(Widgets.Icon.new("cup_" + id, 72.0, UiTheme.SUN if id == "star" else UiTheme.BUBBLE))
	var nm := Widgets.label(str(cup["name"]), 40)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	var rec: Dictionary = Store.gp_records.get(id, {})
	var best_text := "尚未参赛"
	if not rec.is_empty():
		best_text = "最好第 %d 名 · %d 分" % [int(rec["best_rank"]), int(rec["best_points"])]
	var bb := Widgets.badge(best_text, UiTheme.SUN_LIGHT if rec.is_empty() else UiTheme.SUN, 20)
	bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bb)
	var tracks := HBoxContainer.new()
	tracks.add_theme_constant_override("separation", 12)
	v.add_child(tracks)
	var ids: Array = cup["tracks"]
	for i in ids.size():
		var t := TracksData.track_by_id(str(ids[i]))
		var theme := ThemesData.get_theme(str(t["theme"]))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 4)
		tracks.add_child(tv)
		var th := Widgets.TrackThumb.new(str(t["id"]))
		th.custom_minimum_size = Vector2(0, 150)
		th.bg_color = Color(str((theme["ground"] as Dictionary)["base"]))
		th.line_color = Color(str((theme["road"] as Dictionary)["base"])).lightened(0.4)
		th.line_w = 5.0
		th.pad = 10.0
		tv.add_child(th)
		var tl := Widgets.label("%d. %s" % [i + 1, t["name"]], 20)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(tl)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	v.add_child(foot)
	for col: Color in [UiTheme.GOLD, UiTheme.SILVER, UiTheme.BRONZE]:
		foot.add_child(Widgets.Icon.new("trophy", 38.0, col))
	var fl := Widgets.label("%d 场总分前三名登上领奖台" % ids.size(), 22, UiTheme.INK_2)
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(fl)
	var c := Widgets.card(v, Vector2(500, 380))
	c.pressed.connect(func() -> void: _pick("cup_id", id))
	_cup_cards[id] = c
	return c


# ———————————————————————— 车库 ————————————————————————

func _build_garage_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(Widgets.section("车手"))
	_char_name = Widgets.label("", 24, UiTheme.INK_2)
	_char_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_char_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_char_name)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var cg := ButtonGroup.new()
	for ch in KartsData.CHARACTERS:
		var id := str(ch["id"])
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		var av := PortraitBaker.Avatar.new(id, 92.0)
		av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(av)
		var nl := Widgets.label(str(ch["name"]), 24)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nl)
		var c := Widgets.card(cv, Vector2(160, 144))
		c.button_group = cg
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.pressed.connect(func() -> void: _pick("character_id", id))
		grid.add_child(c)
		_char_cards[id] = c

	v.add_child(Widgets.section("赛车"))
	var karts := HBoxContainer.new()
	karts.add_theme_constant_override("separation", 14)
	v.add_child(karts)
	var kg := ButtonGroup.new()
	for kd in KartsData.KARTS:
		var id := str(kd["id"])
		var kv := VBoxContainer.new()
		kv.add_theme_constant_override("separation", 0)
		kv.alignment = BoxContainer.ALIGNMENT_CENTER
		var nl := Widgets.label(str(kd["name"]), 32)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kv.add_child(nl)
		var el := Widgets.label(str(kd["en"]), 14, UiTheme.INK_2, true)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kv.add_child(el)
		var tag := Widgets.badge(kart_tag(kd), UiTheme.MINT, 18)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		kv.add_child(tag)
		var c := Widgets.card(kv, Vector2(190, 124))
		c.button_group = kg
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.pressed.connect(func() -> void: _pick("kart_id", id))
		karts.add_child(c)
		_kart_cards[id] = c

	v.add_child(Widgets.section("涂装"))
	var paints := HBoxContainer.new()
	paints.add_theme_constant_override("separation", 14)
	v.add_child(paints)
	var pg := ButtonGroup.new()
	for pt in KartsData.PAINTS:
		var id := str(pt["id"])
		var pr := HBoxContainer.new()
		pr.alignment = BoxContainer.ALIGNMENT_CENTER
		pr.add_theme_constant_override("separation", 10)
		var d := Widgets.dot(Color(str(pt["color"])), 38.0)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.add_child(d)
		var nl := Widgets.label(str(pt["name"]), 26)
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.add_child(nl)
		var c := Widgets.card(pr, Vector2(190, 76))
		c.button_group = pg
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.pressed.connect(func() -> void: _pick("paint_id", id))
		paints.add_child(c)
		_paint_cards[id] = c
	return v


## 赛车的特点标签：最高的属性（全部相同则为「均衡」）
static func kart_tag(kd: Dictionary) -> String:
	var stats: Dictionary = kd["stats"]
	var best_v := -1
	var best_l := ""
	var all_same := true
	var first := -1
	for pair: Array in KartsData.STAT_LABELS:
		var v: int = stats[pair[0]]
		if first < 0:
			first = v
		elif v != first:
			all_same = false
		if v > best_v:
			best_v = v
			best_l = str(pair[1])
	return "均衡型" if all_same else "%s型" % best_l


# ———————————————————————— 右栏 ————————————————————————

func _build_info_card() -> Control:
	var card := Widgets.panel("GlassPanel")
	card.size_flags_horizontal = Control.SIZE_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_kart_title = Widgets.title("", 50, UiTheme.SUN, false, 10)
	head.add_child(_kart_title)
	_kart_en = Widgets.label("", 20, UiTheme.INK_2, true)
	_kart_en.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kart_en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kart_en)
	var tag := Widgets.badge("", UiTheme.MINT, 22)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kart_tag = tag.get_child(0) as Label
	head.add_child(tag)
	_kart_blurb = Widgets.label("", 22, UiTheme.INK_2)
	v.add_child(_kart_blurb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for pair: Array in KartsData.STAT_LABELS:
		var sb := Widgets.stat_bar(str(pair[1]), 0)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.custom_minimum_size = Vector2(260, 34)
		grid.add_child(sb)
		_stat_bars.append(sb)
	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.custom_minimum_size = Vector2(0, 3)
	v.add_child(line)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	v.add_child(srow)
	var ic := Widgets.Icon.new("flag", 40.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(ic)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -2)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sv)
	_summary = Widgets.label("", 28)
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sv.add_child(_summary)
	_summary_sub = Widgets.label("", 22, UiTheme.INK_2)
	_summary_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sv.add_child(_summary_sub)
	return card


# ———————————————————————— 选择与刷新 ————————————————————————

func _pick(key: String, value: Variant) -> void:
	sel[key] = value
	_save(key, value)
	_refresh()
	if key in ["character_id", "kart_id", "paint_id"]:
		root.show_selection(sel)


func _pick_quiet(key: String, value: Variant) -> void:
	sel[key] = value
	_save(key, value)


func _save(key: String, value: Variant) -> void:
	if kind == "time" and key in ["mode", "laps"]:
		return
	if kind == "gp" and key == "mode":
		return
	Store.save_selection({key: value})


func _refresh() -> void:
	var mode := str(sel.get("mode", "speed"))
	var tid := str(sel.get("track_id", "village"))
	for id: String in _track_cards:
		var c: Button = _track_cards[id]
		c.set_pressed_no_signal(id == tid)
		var best: Label = c.get_meta("best")
		var r := Store.record(id, mode)
		if r.get("best_total") != null:
			best.text = MathX.format_time(float(r["best_total"]))
			best.add_theme_color_override("font_color", UiTheme.INK)
		elif r.get("best_lap") != null:
			best.text = "圈 " + MathX.format_time(float(r["best_lap"]))
			best.add_theme_color_override("font_color", UiTheme.INK)
		else:
			best.text = "—"
			best.add_theme_color_override("font_color", UiTheme.INK_2)
	var cup_id := str(sel.get("cup_id", "star"))
	for id: String in _cup_cards:
		(_cup_cards[id] as Button).set_pressed_no_signal(id == cup_id)
	var cid := str(sel.get("character_id", "male-a"))
	for id: String in _char_cards:
		(_char_cards[id] as Button).set_pressed_no_signal(id == cid)
	var kid := str(sel.get("kart_id", "marshmallow"))
	for id: String in _kart_cards:
		(_kart_cards[id] as Button).set_pressed_no_signal(id == kid)
	var pid := str(sel.get("paint_id", "oodi"))
	for id: String in _paint_cards:
		(_paint_cards[id] as Button).set_pressed_no_signal(id == pid)

	_mode_note.text = str(MODE_NOTES.get("gp" if kind == "gp" else mode, ""))
	var ch := KartsData.character_by_id(cid)
	var kd := KartsData.kart_by_id(kid)
	var pt := KartsData.paint_by_id(pid)
	_char_name.text = "%s · %s涂装" % [ch["name"], pt["name"]]
	if kind == "gp":
		var cup := TracksData.cup_by_id(cup_id)
		var names: Array[String] = []
		for t: Variant in cup["tracks"]:
			names.append(str(TracksData.track_by_id(str(t))["name"]))
		_track_note.text = " → ".join(names)
	else:
		_track_note.text = str(TracksData.track_by_id(tid)["blurb"])
	if _ghost_badge:
		var g := Store.ghost(tid)
		_ghost_badge.text = "最佳 %s" % MathX.format_time(float(g["total"])) if not g.is_empty() else "暂无幽灵车"

	_kart_title.text = str(kd["name"])
	_kart_en.text = str(kd["en"])
	_kart_tag.text = kart_tag(kd)
	_kart_blurb.text = str(kd["blurb"])
	var stats: Dictionary = kd["stats"]
	for i in _stat_bars.size():
		var key: String = KartsData.STAT_LABELS[i][0]
		_stat_bars[i].set_value(int(stats[key]))

	var diff: Dictionary = KartsData.DIFFICULTIES.get(str(sel.get("difficulty", "normal")), KartsData.DIFFICULTIES["normal"])
	match kind:
		"time":
			_summary.text = "计时赛 · %s · 3 圈" % TracksData.track_by_id(tid)["name"]
		"gp":
			_summary.text = "%s · %s规则 · %s · %d 圈" % [TracksData.cup_by_id(cup_id)["name"], "道具" if mode == "item" else "竞速", diff["name"], int(sel.get("laps", 3))]
		_:
			_summary.text = "%s · %s · %s · %d 圈" % [MODE_NAMES.get(mode, "竞速赛"), TracksData.track_by_id(tid)["name"], diff["name"], int(sel.get("laps", 3))]
	_summary_sub.text = "%s 驾驶 %s（%s涂装）" % [ch["name"], kd["name"], pt["name"]]


func _race_sel() -> Dictionary:
	return {
		"mode": str(sel.get("mode", "speed")), "track_id": str(sel.get("track_id", "village")),
		"character_id": str(sel.get("character_id", "male-a")), "kart_id": str(sel.get("kart_id", "marshmallow")),
		"paint_id": str(sel.get("paint_id", "oodi")), "difficulty": str(sel.get("difficulty", "normal")),
		"laps": 3 if kind == "time" else int(sel.get("laps", 3)),
	}


func _start() -> void:
	if root.busy:
		return
	var s := _race_sel()
	if kind == "gp":
		s["gp_rule"] = str(sel.get("mode", "speed"))
		Game.start_gp(str(sel.get("cup_id", "star")), s)
	else:
		Game.start_single(s)


# ———————————————————————— MenuPage ————————————————————————

func on_enter() -> void:
	var items: Array = []
	items.append_array(_pages[tab].get_children())
	Widgets.stagger_in(items, 0.04, 0.1)


func on_resume() -> void:
	_refresh()
	root.show_selection(sel)


func default_focus() -> Control:
	if tab == 0:
		if kind == "gp":
			return _cup_cards.get(str(sel.get("cup_id", "star")))
		return _track_cards.get(str(sel.get("track_id", "village")))
	return _char_cards.get(str(sel.get("character_id", "male-a")))


func garage_selection() -> Dictionary:
	return sel


## 预览区的鼠标拖拽 → 车库转台左右旋转
func _on_preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			get_tree().call_group("garage_stage", "drag_begin")
		else:
			get_tree().call_group("garage_stage", "drag_end")
		_preview.accept_event()
	elif ev is InputEventMouseMotion and ((ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		get_tree().call_group("garage_stage", "drag_by", (ev as InputEventMouseMotion).relative.x)
		_preview.accept_event()


func _exit_tree() -> void:
	# 离开页面时如果还按着鼠标，结束拖拽，避免转台停在拖拽状态
	if is_inside_tree():
		get_tree().call_group("garage_stage", "drag_end")


## 车库人物往下挪的距离（界面按 1920×1080 布局；默认 1600×900 窗口里正好 50 像素）
const PREVIEW_DROP := 60.0


func view_rect() -> Rect2:
	if _preview == null or _preview.size.x < 10.0:
		return Rect2(0.64, 0.06 + PREVIEW_DROP / 1080.0, 0.33, 0.42)
	var vp := get_viewport_rect().size
	var r := _preview.get_global_rect()
	r.position.x -= position.x
	r.position.y += PREVIEW_DROP
	return Rect2(r.position / vp, r.size / vp)

