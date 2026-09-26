class_name Speedometer
extends Control
## 弧形速度表：底色弧 + 渐变填充弧 + 数字（km/h，街机式夸张读数）。

const KMH := 3.6 * 1.4
const MAX_KMH := 280.0
const START_ANGLE := deg_to_rad(150.0)
const SWEEP := deg_to_rad(240.0)

var speed_kmh := 0.0
var boosting := false
var _shown := 0.0
var _font: Font


func _ready() -> void:
	_font = load("res://assets/fonts/Bungee-Tabular.ttf")  # 等宽数字：跑秒 / 速度不抖
	custom_minimum_size = Vector2(230, 230)


func set_speed(mps: float, p_boosting: bool) -> void:
	speed_kmh = maxf(0.0, mps * KMH)
	boosting = p_boosting


func _process(dt: float) -> void:
	_shown = MathX.damp(_shown, speed_kmh, 12.0, dt)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var ink := Color("#1B1F3B")
	# 底盘
	draw_circle(c + Vector2(0, 5), r + 16, Color(ink, 0.55))
	draw_circle(c, r + 16, Color(ink, 0.82))
	draw_arc(c, r + 16, 0, TAU, 64, Color("#F7FAFF", 0.9), 3.0, true)
	# 刻度
	for i in 15:
		var a := START_ANGLE + SWEEP * i / 14.0
		var dir := Vector2(cos(a), sin(a))
		var long := i % 2 == 0
		draw_line(c + dir * (r - (14.0 if long else 8.0)), c + dir * (r - 2.0), Color("#F7FAFF", 0.8 if long else 0.45), 3.0 if long else 2.0, true)
	# 底色弧与填充弧
	draw_arc(c, r + 6, START_ANGLE, START_ANGLE + SWEEP, 64, Color(1, 1, 1, 0.14), 11.0, true)
	var frac := clampf(_shown / MAX_KMH, 0.0, 1.0)
	if frac > 0.002:
		var segs := maxi(2, int(64 * frac))
		var col_a := Color("#45E3A6")
		var col_b := Color("#FFC93C")
		var col_c := Color("#FF4D5E")
		var prev := START_ANGLE
		for i in segs:
			var t := float(i + 1) / segs
			var a := START_ANGLE + SWEEP * frac * t
			var tt := frac * t
			var col := col_a.lerp(col_b, clampf(tt / 0.6, 0.0, 1.0)) if tt < 0.6 else col_b.lerp(col_c, clampf((tt - 0.6) / 0.4, 0.0, 1.0))
			if boosting:
				col = col.lerp(Color("#3EC6FF"), 0.6)
			draw_arc(c, r + 6, prev, a + 0.01, 4, col, 11.0, true)
			prev = a
	# 指针
	var pa := START_ANGLE + SWEEP * frac
	var pd := Vector2(cos(pa), sin(pa))
	draw_line(c, c + pd * (r - 16), Color("#FF4D5E"), 5.0, true)
	draw_circle(c, 9, Color("#F7FAFF"))
	# 数字
	var txt := str(int(round(_shown)))
	var fs := 46
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string_outline(_font, c + Vector2(-w * 0.5, r * 0.62), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, ink)
	draw_string(_font, c + Vector2(-w * 0.5, r * 0.62), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#3EC6FF") if boosting else Color("#F7FAFF"))
	var unit := "KM/H"
	var uw := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
	draw_string(_font, c + Vector2(-uw * 0.5, r * 0.62 + 24), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#F7FAFF", 0.7))
