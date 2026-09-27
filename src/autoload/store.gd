extends Node
## 本地存档：设置、上次的选择、各赛道最佳成绩、计时赛幽灵车、大奖赛成绩。
## 读取时逐项校验类型，文件缺失、损坏或来自旧版本时回退到默认值。

const SAVE_PATH := "user://save.json"
const VERSION := 1

const DEFAULT_SETTINGS := {
	"music": 0.55,
	"sfx": 0.85,
	"quality": "high",
	"fullscreen": false,
	"vsync": true,
	"camera": "far",
	"auto_instant": false,
	"show_fps": false,
	"muted": false,
	## auto：跟随系统语言（简体中文 → 中文，其余 → 英文）
	"language": "auto",
}

const DEFAULT_SELECTION := {
	"mode": "speed",
	"track_id": "village",
	"character_id": "male-a",
	"kart_id": "marshmallow",
	"paint_id": "oodi",
	"difficulty": "normal",
	"laps": 3,
	"gp_rule": "speed",
	"cup_id": "star",
}

var settings: Dictionary = {}
var selection: Dictionary = {}
## 键为 "track_id:mode"，值为 {best_total, best_lap, races, ghost}
var records: Dictionary = {}
## 键为 cup_id，值为 {best_rank, best_points, wins}
var gp_records: Dictionary = {}

## 测试时可改成别的路径，避免覆盖真实存档
var save_path := SAVE_PATH


func _ready() -> void:
	load_from_disk()


func load_from_disk() -> void:
	var data: Variant = null
	if FileAccess.file_exists(save_path):
		var text := FileAccess.get_file_as_string(save_path)
		var json := JSON.new()
		if not text.is_empty() and json.parse(text) == OK:
			data = json.data
	if not data is Dictionary:
		data = {}
	settings = _merge_typed(DEFAULT_SETTINGS, data.get("settings"))
	selection = _merge_typed(DEFAULT_SELECTION, data.get("selection"))
	records = _sanitize_records(data.get("records"))
	gp_records = _sanitize_gp(data.get("gp"))


## 以默认值为模板合并，只接受类型相同（int/float 互通）的字段
func _merge_typed(defaults: Dictionary, src: Variant) -> Dictionary:
	var out := defaults.duplicate(true)
	if not src is Dictionary:
		return out
	for key: String in defaults:
		if not src.has(key):
			continue
		var v: Variant = src[key]
		var want := typeof(defaults[key])
		if typeof(v) == want:
			out[key] = v
		elif want == TYPE_INT and typeof(v) == TYPE_FLOAT:
			out[key] = int(v)
		elif want == TYPE_FLOAT and typeof(v) == TYPE_INT:
			out[key] = float(v)
	return out


func _sanitize_records(src: Variant) -> Dictionary:
	var out := {}
	if not src is Dictionary:
		return out
	for key: Variant in src:
		var r: Variant = src[key]
		if not (key is String and r is Dictionary):
			continue
		var clean := {
			"best_total": _num_or_null(r.get("best_total")),
			"best_lap": _num_or_null(r.get("best_lap")),
			"races": int(r.get("races", 0)) if _is_num(r.get("races", 0)) else 0,
			"ghost": null,
		}
		var g: Variant = r.get("ghost")
		if g is Dictionary and g.get("frames") is Array and _is_num(g.get("total")):
			clean["ghost"] = g
		out[key] = clean
	return out


func _sanitize_gp(src: Variant) -> Dictionary:
	var out := {}
	if not src is Dictionary:
		return out
	for key: Variant in src:
		var r: Variant = src[key]
		if key is String and r is Dictionary and _is_num(r.get("best_rank")) and _is_num(r.get("best_points")):
			out[key] = {
				"best_rank": int(r["best_rank"]),
				"best_points": int(r["best_points"]),
				"wins": int(r.get("wins", 0)) if _is_num(r.get("wins", 0)) else 0,
			}
	return out


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _num_or_null(v: Variant) -> Variant:
	return float(v) if _is_num(v) else null


func write_to_disk() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败：%s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({
		"version": VERSION,
		"settings": settings,
		"selection": selection,
		"records": records,
		"gp": gp_records,
	}))


func save_settings(patch: Dictionary) -> void:
	settings = _merge_typed(settings, patch)
	write_to_disk()


func save_selection(patch: Dictionary) -> void:
	selection = _merge_typed(selection, patch)
	write_to_disk()


func record(track_id: String, mode: String) -> Dictionary:
	return records.get("%s:%s" % [track_id, mode], {})


## 提交一局成绩。只有 3 圈的成绩计入总用时纪录（幽灵车也只按 3 圈保存）。
func submit(track_id: String, mode: String, laps: int, total: float, best_lap: float, ghost: Dictionary) -> Dictionary:
	var key := "%s:%s" % [track_id, mode]
	var r: Dictionary = records.get(key, {"best_total": null, "best_lap": null, "races": 0, "ghost": null})
	var res := {"new_best_total": false, "new_best_lap": false}
	r["races"] = int(r.get("races", 0)) + 1
	if laps == 3 and (r["best_total"] == null or total < float(r["best_total"])):
		r["best_total"] = total
		res["new_best_total"] = true
		if not ghost.is_empty():
			r["ghost"] = ghost
	if is_finite(best_lap) and (r["best_lap"] == null or best_lap < float(r["best_lap"])):
		r["best_lap"] = best_lap
		res["new_best_lap"] = true
	records[key] = r
	write_to_disk()
	return res


func ghost(track_id: String) -> Dictionary:
	var g: Variant = records.get("%s:time" % track_id, {}).get("ghost")
	return g if g is Dictionary else {}


## 提交大奖赛结果，返回是否刷新了该杯赛的最好名次
func submit_gp(cup_id: String, rank: int, points: int) -> bool:
	var r: Dictionary = gp_records.get(cup_id, {"best_rank": 99, "best_points": 0, "wins": 0})
	var improved := rank < int(r["best_rank"]) or (rank == int(r["best_rank"]) and points > int(r["best_points"]))
	if improved:
		r["best_rank"] = rank
		r["best_points"] = points
	if rank == 1:
		r["wins"] = int(r["wins"]) + 1
	gp_records[cup_id] = r
	write_to_disk()
	return improved
