class_name Hud
extends CanvasLayer
## 比赛 HUD：名次、圈数、计时（总 / 本圈 / 最佳 + 各圈）、实时排名、小地图、速度表、集气条与氮气罐 / 道具槽、
## 中央大字与提示、小喷提示、逆行与锁定警告、计时赛幽灵差距、FPS。所有元素按锚点自适应窗口。

const INK := Color("#1B1F3B")
const YELLOW := Color("#FFC93C")
const BLUE := Color("#3EC6FF")
const RED := Color("#FF4D5E")
const MINT := Color("#45E3A6")
const WHITE := Color("#F7FAFF")

var race: RaceSim
var root: Control
var _num_font: Font
var _cn_font: Font

var _rank_label: Label
var _rank_total: Label
var _lap_label: Label
var _time_total: Label
var _time_lap: Label
var _time_best: Label
var _lap_list: VBoxContainer
var _ranking_box: VBoxContainer
var _rank_rows: Array[Dictionary] = []
var _minimap: Minimap
var _speedo: Speedometer
var _gauge_panel: Control
var _gauge_fill: ColorRect
var _gauge_glow: ColorRect
var _slots: Array[Panel] = []
var _slot_labels: Array[Label] = []
var _big: Label
var _sub: Label
var _cue: Label
var _warn: Label
var _ghost: Label
var _fps: Label
var _flash: ColorRect
var _big_tween: Tween
var _sub_tween: Tween
var _sub_queue: Array = []
var _sub_time := 0.0
var _cue_time := 0.0
var _last_rank := 0
var _roll_t := 0.0
var ghost_diff := INF
var _all_visible := true
var _last_nitros := 0
var _last_items := 0
var _rank_hold := 0.0
## 等待确认的超越名次（保持 0.4 s 才提示）
var _pending_rank := 0
## 已经提示过的最好名次，避免来回超越时重复提示
var _best_announced := 99


func setup(p_race: RaceSim) -> void:
	name = "Hud"
	layer = 5
	race = p_race
	_num_font = load("res://assets/fonts/Bungee-Regular.ttf")
	_cn_font = load("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_rank()
	_build_times()
	_build_ranking()
	_build_minimap()
	_build_speedo()
	_build_gauge()
	_build_center()
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)


# ———————————————— 构建 ————————————————

func _panel_style(bg: Color, radius := 18, border := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = INK
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(INK, 0.55)
	sb.shadow_offset = Vector2(0, 5)
	sb.shadow_size = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(text: String, size: int, color := WHITE, num := false, outline := 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _num_font if num else _cn_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _anchor(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	root.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	c.position += offset


func _build_rank() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_rank_label = _label("1", 110, YELLOW, true, 14)
	_rank_total = _label("/8", 40, WHITE, true, 10)
	_rank_total.size_flags_vertical = Control.SIZE_SHRINK_END
	box.add_child(_rank_label)
	box.add_child(_rank_total)
	box.position = Vector2(34, 10)
	root.add_child(box)
	_lap_label = _label("LAP 1/3", 36, WHITE, true, 9)
	_lap_label.position = Vector2(40, 150)
	root.add_child(_lap_label)
	if race.karts.size() == 1:
		_rank_label.visible = false
		_rank_total.visible = false
		_lap_label.position = Vector2(40, 30)


func _build_times() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(INK, 0.72)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	_time_total = _label("0:00.000", 40, WHITE, true, 8)
	_time_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_time_total)
	var h1 := HBoxContainer.new()
	var t1 := _label("本圈", 20, Color(WHITE, 0.75), false, 5)
	t1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_lap = _label("0:00.000", 22, WHITE, true, 5)
	h1.add_child(t1)
	h1.add_child(_time_lap)
	v.add_child(h1)
	var h2 := HBoxContainer.new()
	var t2 := _label("最佳", 20, Color(YELLOW, 0.9), false, 5)
	t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_best = _label("--:--.---", 22, YELLOW, true, 5)
	h2.add_child(t2)
	h2.add_child(_time_best)
	v.add_child(h2)
	_lap_list = VBoxContainer.new()
	_lap_list.add_theme_constant_override("separation", 0)
	v.add_child(_lap_list)
	panel.custom_minimum_size = Vector2(300, 0)
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -330
	panel.offset_right = -30
	panel.offset_top = 24
	_ghost = _label("", 30, MINT, true, 8)
	_ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_ghost)
	_ghost.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ghost.offset_left = -330
	_ghost.offset_right = -30
	_ghost.offset_top = 250
	_fps = _label("", 18, WHITE, true, 4)
	root.add_child(_fps)
	_fps.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fps.offset_left = 12
	_fps.offset_top = -30


func _build_ranking() -> void:
	_ranking_box = VBoxContainer.new()
	_ranking_box.add_theme_constant_override("separation", 4)
	_ranking_box.position = Vector2(30, 214)
	root.add_child(_ranking_box)
	if race.karts.size() <= 1:
		_ranking_box.visible = false
		return
	for i in race.karts.size():
		var row := PanelContainer.new()
		var sb := _panel_style(Color(INK, 0.6), 12, 2)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 8
		sb.shadow_offset = Vector2(0, 3)
		row.add_theme_stylebox_override("panel", sb)
		row.custom_minimum_size = Vector2(200, 0)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		var num := _label(str(i + 1), 20, WHITE, true, 5)
		num.custom_minimum_size = Vector2(26, 0)
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(12, 12)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nm := _label("", 22, WHITE, false, 5)
		h.add_child(num)
		h.add_child(chip)
		h.add_child(nm)
		_ranking_box.add_child(row)
		_rank_rows.append({"row": row, "style": sb, "num": num, "chip": chip, "name": nm})


func _build_minimap() -> void:
	_minimap = Minimap.new()
	root.add_child(_minimap)
	_minimap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_minimap.offset_left = -330
	_minimap.offset_right = -30
	_minimap.offset_top = -120
	_minimap.offset_bottom = 180
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.setup(race)


func _build_speedo() -> void:
	_speedo = Speedometer.new()
	root.add_child(_speedo)
	_speedo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speedo.offset_left = -290
	_speedo.offset_right = -30
	_speedo.offset_top = -280
	_speedo.offset_bottom = -20
	_speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_gauge() -> void:
	_gauge_panel = Control.new()
	root.add_child(_gauge_panel)
	_gauge_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge_panel.offset_left = -300
	_gauge_panel.offset_right = 300
	_gauge_panel.offset_top = -150
	_gauge_panel.offset_bottom = -24
	_gauge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 两个槽位（氮气罐 / 道具）
	for i in 2:
		var slot := Panel.new()
		var big := i == 0
		var sz := 96.0 if big else 70.0
		slot.size = Vector2(sz, sz)
		slot.position = Vector2(300 - sz - 8 + (0 if big else -sz - 14), 0 if big else 26)
		if race.item_mode:
			slot.position = Vector2(300 - sz * 0.5 + (0.0 if big else 96.0), 0.0 if big else 26.0)
		var sb := _panel_style(Color(INK, 0.7), 22, 3)
		slot.add_theme_stylebox_override("panel", sb)
		_gauge_panel.add_child(slot)
		var lb := _label("", 40 if big else 30, WHITE, false, 7)
		lb.set_anchors_preset(Control.PRESET_FULL_RECT)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(lb)
		_slots.append(slot)
		_slot_labels.append(lb)
	if race.item_mode:
		return
	# 集气条
	var bar := Panel.new()
	var bsb := _panel_style(Color(INK, 0.75), 14, 3)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.position = Vector2(0, 104)
	bar.size = Vector2(600, 24)
	_gauge_panel.add_child(bar)
	_gauge_fill = ColorRect.new()
	_gauge_fill.color = BLUE
	_gauge_fill.position = Vector2(5, 5)
	_gauge_fill.size = Vector2(0, 14)
	bar.add_child(_gauge_fill)
	_gauge_glow = ColorRect.new()
	_gauge_glow.color = Color(1, 1, 1, 0.35)
	_gauge_glow.position = Vector2(5, 5)
	_gauge_glow.size = Vector2(0, 5)
	bar.add_child(_gauge_glow)
	# 两个氮气槽放在集气条右上方，靠中间排列
	_slots[0].size = Vector2(84, 84)
	_slots[1].size = Vector2(84, 84)
	_slots[0].position = Vector2(300 - 92, 8)
	_slots[1].position = Vector2(300 + 8, 8)


func _build_center() -> void:
	_big = _label("", 150, WHITE, true, 18)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(_big)
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.offset_left = -600
	_big.offset_right = 600
	_big.offset_top = -260
	_big.offset_bottom = -40
	_big.pivot_offset = Vector2(600, 110)
	_sub = _label("", 44, WHITE, false, 10)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_sub)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_sub.offset_left = -600
	_sub.offset_right = 600
	_sub.offset_top = -40
	_sub.offset_bottom = 20
	_sub.pivot_offset = Vector2(600, 30)
	_cue = _label("↑", 72, BLUE, true, 12)
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_cue)
	_cue.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_cue.offset_left = -60
	_cue.offset_right = 60
	_cue.offset_top = 40
	_cue.offset_bottom = 130
	_cue.visible = false
	_warn = _label("", 46, RED, false, 10)
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_warn)
	_warn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_warn.offset_left = -500
	_warn.offset_right = 500
	_warn.offset_top = 150
	_warn.offset_bottom = 210


# ———————————————— 更新 ————————————————

func update_view(dt: float, p_race: RaceSim) -> void:
	race = p_race
	var p := race.player
	var n := race.karts.size()
	# 名次（变化时弹跳）
	if p.rank != _last_rank:
		# 比赛进行 3 s 后名次提升：记下来，保持 0.4 s 后再提示（避免并排时来回闪）
		if _last_rank != 0 and p.rank < _last_rank and race.phase == "racing" and race.time > 3.0 and not p.finished:
			_pending_rank = p.rank
			_rank_hold = 0.4
		if _last_rank != 0:
			var tw := create_tween()
			_rank_label.pivot_offset = _rank_label.size * 0.5
			tw.tween_property(_rank_label, "scale", Vector2(1.3, 1.3), 0.08)
			tw.tween_property(_rank_label, "scale", Vector2.ONE, 0.18)
		_last_rank = p.rank
		_rank_label.text = str(p.rank)
		_rank_label.add_theme_color_override("font_color", YELLOW if p.rank == 1 else (WHITE if p.rank <= 3 else Color("#C9D2F0")))
	if _pending_rank > 0:
		_rank_hold -= dt
		if p.rank > _pending_rank:
			_pending_rank = 0
		elif _rank_hold <= 0.0:
			if _pending_rank < _best_announced or _pending_rank <= 3:
				sub("超越！第 %d 名" % _pending_rank, MINT)
			_best_announced = mini(_best_announced, _pending_rank)
			_pending_rank = 0
	_rank_total.text = "/%d" % n
	var lap := clampi(maxi(p.lap, 1), 1, race.laps)
	_lap_label.text = "LAP %d/%d" % [lap, race.laps]
	if race.laps > 1 and lap == race.laps:
		_lap_label.add_theme_color_override("font_color", YELLOW)

	var racing := race.phase == "racing" or race.phase == "finished"
	var total := p.finish_time if p.finished else (race.time if racing else 0.0)
	_time_total.text = MathX.format_time(total)
	_time_lap.text = MathX.format_time((race.time - p.lap_start) if racing and not p.finished else 0.0)
	_time_best.text = MathX.format_time(p.best_lap) if is_finite(p.best_lap) else "--:--.---"

	# 实时排名
	for i in _rank_rows.size():
		var k: KartSim = race.ranking[i] if i < race.ranking.size() else null
		var row: Dictionary = _rank_rows[i]
		if k == null:
			continue
		(row["name"] as Label).text = k.name
		(row["chip"] as ColorRect).color = Color(k.character.get("color", "#FFFFFF"))
		var sb: StyleBoxFlat = row["style"]
		sb.bg_color = Color(YELLOW, 0.95) if k.is_player else Color(INK, 0.6)
		(row["name"] as Label).add_theme_color_override("font_color", INK if k.is_player else WHITE)
		(row["name"] as Label).add_theme_constant_override("outline_size", 0 if k.is_player else 5)

	_speedo.set_speed(p.speed, p.is_boosting())
	_update_slots(dt, p)

	# 中央提示队列
	_sub_time -= dt
	if _sub_time <= 0.0 and not _sub_queue.is_empty():
		var item: Array = _sub_queue.pop_front()
		_show_sub(item[0], item[1])
	if _cue.visible:
		_cue_time -= dt
		_cue.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.03)
		if _cue_time <= 0.0 or p.instant_window <= 0.0:
			_cue.visible = false

	# 警告
	var warn := ""
	if p.locked_by > 0.0:
		warn = "⚠ 被锁定！"
	elif p.wrong_way > 1.2:
		warn = "逆行！按 R 复位"
	_warn.text = warn
	_warn.visible = warn != ""
	if _warn.visible:
		_warn.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.008))

	# 幽灵差距
	if race.mode == "time" and is_finite(ghost_diff) and racing:
		_ghost.visible = true
		_ghost.text = ("-%.2f" if ghost_diff <= 0.0 else "+%.2f") % absf(ghost_diff)
		_ghost.add_theme_color_override("font_color", MINT if ghost_diff <= 0.0 else RED)
	else:
		_ghost.visible = false

	_fps.visible = Store.settings.get("show_fps", false)
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(0.0, _flash.color.a - dt * 2.5)


func _pop_slot(i: int) -> void:
	var slot := _slots[i]
	slot.pivot_offset = slot.size * 0.5
	var tw := create_tween()
	tw.tween_property(slot, "scale", Vector2(1.35, 1.35), 0.08).set_trans(Tween.TRANS_BACK)
	tw.tween_property(slot, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slot.modulate = Color(2.2, 2.2, 2.2)
	create_tween().tween_property(slot, "modulate", Color.WHITE, 0.4)


func _update_slots(dt: float, p: KartSim) -> void:
	if p.nitros > _last_nitros and not race.item_mode:
		_pop_slot(clampi(p.nitros - 1, 0, 1))
	_last_nitros = p.nitros
	if race.item_mode and p.items.size() != _last_items:
		if p.items.size() > _last_items:
			_pop_slot(clampi(p.items.size() - 1, 0, 1))
		_last_items = p.items.size()
	if race.item_mode:
		_roll_t += dt
		for i in 2:
			var lb := _slot_labels[i]
			var sb := _slots[i].get_theme_stylebox("panel") as StyleBoxFlat
			if p.item_roll > 0.0 and i == p.items.size() - 1:
				# 轮盘：快速切换图标
				var keys := ItemsData.ITEMS.keys()
				var k: String = keys[int(_roll_t * 14.0) % keys.size()]
				lb.text = ItemsData.ITEMS[k]["glyph"]
				sb.bg_color = Color(ItemsData.ITEMS[k]["color"]).darkened(0.3)
			elif i < p.items.size():
				var it: Dictionary = ItemsData.ITEMS[p.items[i]]
				lb.text = it["glyph"]
				sb.bg_color = Color(it["color"])
				if p.ufo > 0.0:
					sb.bg_color = sb.bg_color.darkened(0.6)
			else:
				lb.text = ""
				sb.bg_color = Color(INK, 0.7)
		return
	# 竞速赛：集气条 + 氮气罐
	var g := clampf(p.gauge, 0.0, 1.0)
	_gauge_fill.size.x = 590.0 * g
	_gauge_glow.size.x = 590.0 * g
	_gauge_fill.color = BLUE.lerp(Color("#9FF0FF"), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)) if p.drifting else BLUE
	for i in 2:
		var sb := _slots[i].get_theme_stylebox("panel") as StyleBoxFlat
		var has := i < p.nitros
		_slot_labels[i].text = "N₂O" if has else ""
		_slot_labels[i].add_theme_font_size_override("font_size", 30)
		sb.bg_color = BLUE if has else Color(INK, 0.6)


## 中央大字；opts: {hold: bool, cn: bool, color: Color}
func big(text: String, opts := {}) -> void:
	_big.text = text
	_big.add_theme_font_override("font", _cn_font if opts.get("cn", false) else _num_font)
	_big.add_theme_font_size_override("font_size", 120 if opts.get("cn", false) else 150)
	_big.add_theme_color_override("font_color", opts.get("color", WHITE))
	_big.visible = true
	_big.modulate.a = 1.0
	_big.scale = Vector2(1.8, 1.8)
	if _big_tween:
		_big_tween.kill()
	_big_tween = create_tween()
	_big_tween.tween_property(_big, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not opts.get("hold", false):
		_big_tween.tween_interval(0.6)
		_big_tween.tween_property(_big, "modulate:a", 0.0, 0.25)


## 中央小字提示（短时间内的多条会排队显示）
func sub(text: String, color := WHITE) -> void:
	if _sub_time > 0.0:
		if _sub_queue.size() < 3:
			_sub_queue.append([text, color])
		return
	_show_sub(text, color)


func _show_sub(text: String, color: Color) -> void:
	_sub.text = text
	_sub.add_theme_color_override("font_color", color)
	_sub.modulate.a = 1.0
	_sub.scale = Vector2(0.6, 0.6)
	_sub_time = 0.9
	if _sub_tween:
		_sub_tween.kill()
	_sub_tween = create_tween()
	_sub_tween.tween_property(_sub, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sub_tween.tween_interval(0.9)
	_sub_tween.tween_property(_sub, "modulate:a", 0.0, 0.3)


## 全屏闪白（雷暴）
func flash() -> void:
	_flash.color.a = 0.85


func add_lap_time(lap: int, time: float, best: bool) -> void:
	var l := _label("L%d  %s" % [lap, MathX.format_time(time)], 18, YELLOW if best else Color(WHITE, 0.8), true, 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lap_list.add_child(l)
	while _lap_list.get_child_count() > 5:
		_lap_list.get_child(0).queue_free()
		_lap_list.remove_child(_lap_list.get_child(0))


## 小喷提示（松开漂移后的窗口内显示「↑」）
func show_instant_cue(on: bool) -> void:
	_cue.visible = on
	_cue_time = KartSim.INSTANT_WINDOW


func set_ghost_diff(d: float) -> void:
	ghost_diff = d


func set_hud_visible(v: bool) -> void:
	_all_visible = v
	root.visible = v
