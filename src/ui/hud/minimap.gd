class_name Minimap
extends Control
## 小地图：赛道轮廓（粗描边 + 路面色）、起点线、每辆车的彩色圆点，玩家为带朝向的箭头。

var race: RaceSim
var _poly := PackedVector2Array()
## 支路（小路）折线与种类
var _branch_polys: Array[PackedVector2Array] = []
var _branch_kinds: Array[String] = []
var _scale := 1.0
var _offset := Vector2.ZERO
var _center := Vector2.ZERO
var _rot := 0.0


func setup(p_race: RaceSim) -> void:
	race = p_race
	custom_minimum_size = Vector2(300, 300)
	resized.connect(_rebuild)
	_rebuild()


## 把赛道 XZ 坐标映射到控件内（x 向右、z 向下翻转为屏幕上方）
func _rebuild() -> void:
	if race == null:
		return
	var tr := race.track
	var b := tr.bounds
	var w: float = b["max_x"] - b["min_x"]
	var h: float = b["max_z"] - b["min_z"]
	var pad := 22.0
	_scale = minf((size.x - pad * 2.0) / maxf(w, 1.0), (size.y - pad * 2.0) / maxf(h, 1.0))
	_center = Vector2((b["min_x"] + b["max_x"]) * 0.5, (b["min_z"] + b["max_z"]) * 0.5)
	_poly.clear()
	var step := maxi(1, tr.n / 240)
	var i := 0
	while i < tr.n:
		_poly.append(_map(tr.px[i], tr.pz[i]))
		i += step
	_poly.append(_poly[0])
	_branch_polys.clear()
	_branch_kinds.clear()
	for br in tr.branches:
		var bp := PackedVector2Array()
		for k in range(0, br.n, 2):
			bp.append(_map(br.px[k], br.pz[k]))
		bp.append(_map(br.px[br.n - 1], br.pz[br.n - 1]))
		_branch_polys.append(bp)
		_branch_kinds.append(br.kind)
	queue_redraw()


func _map(x: float, z: float) -> Vector2:
	# 世界 +x 在屏幕上显示为向左（俯视时右手系 x 轴朝左），z 向上
	return size * 0.5 + Vector2(-(x - _center.x), -(z - _center.y)) * _scale


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if race == null or _poly.size() < 3:
		return
	var ink := Color("#1B1F3B")
	for k in _branch_polys.size():
		draw_polyline(_branch_polys[k], Color(ink, 0.7), 8.0, true)
		draw_polyline(_branch_polys[k], Color("#F2D48A", 0.9) if _branch_kinds[k] == "shortcut" else Color("#C9B79A", 0.8), 3.5, true)
	draw_polyline(_poly, Color(ink, 0.85), 13.0, true)
	draw_polyline(_poly, Color("#F7FAFF", 0.92), 7.0, true)
	# 起点线
	var tr := race.track
	var p0 := _map(tr.px[0], tr.pz[0])
	var nrm := Vector2(-tr.nx[0], -tr.nz[0]).normalized()
	draw_line(p0 - nrm * 9.0, p0 + nrm * 9.0, Color("#FF4D5E"), 4.0, true)
	# 其他车先画，玩家最后画在最上层
	for k in race.karts:
		if k.is_player:
			continue
		var p := _map(k.x, k.z)
		draw_circle(p, 7.5, ink)
		draw_circle(p, 5.5, Color(k.character.get("color", "#FFFFFF")))
	var pl := race.player
	var pp := _map(pl.x, pl.z)
	var fwd := Vector2(-sin(pl.heading), -cos(pl.heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([pp + fwd * 12.0, pp - fwd * 7.0 + side * 8.0, pp - fwd * 7.0 - side * 8.0])
	var tri_o := PackedVector2Array([pp + fwd * 15.0, pp - fwd * 9.5 + side * 10.5, pp - fwd * 9.5 - side * 10.5])
	draw_colored_polygon(tri_o, ink)
	draw_colored_polygon(tri, Color("#FFC93C"))
