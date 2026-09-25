extends RefCounted
## 存档容错：空文件、非法 JSON、缺字段、类型错误都要回退默认值，且之后能正常提交成绩。

const TMP := "user://test_save.json"


func run(t: TestUtil) -> void:
	var store: Node = load("res://src/autoload/store.gd").new()
	store.save_path = TMP
	var cases := {
		"文件不存在": null,
		"空文件": "",
		"非法 JSON": "{not json",
		"缺字段": "{\"version\": 1}",
		"类型错误": "{\"settings\": {\"music\": \"loud\", \"quality\": 3, \"laps\": \"x\"}, \"selection\": [1,2], \"records\": {\"a:speed\": 5, \"b:speed\": {\"best_total\": \"x\", \"races\": \"y\"}}, \"gp\": {\"star\": {\"best_rank\": \"1\"}}}",
		"整数写成浮点": "{\"selection\": {\"laps\": 5.0}, \"settings\": {\"music\": 1}}",
	}
	for name: String in cases:
		if FileAccess.file_exists(TMP):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
		var content: Variant = cases[name]
		if content != null:
			var f := FileAccess.open(TMP, FileAccess.WRITE)
			f.store_string(content)
			f.close()
		store.load_from_disk()
		t.check(store.settings.size() == store.DEFAULT_SETTINGS.size(), "%s：设置字段齐全" % name)
		t.check(store.settings["quality"] is String, "%s：quality 是字符串" % name)
		t.check(store.settings["music"] is float, "%s：music 是浮点" % name)
		t.check(store.selection["laps"] is int, "%s：laps 是整数" % name)
		for key: String in store.records:
			var r: Dictionary = store.records[key]
			t.check(r["best_total"] == null or r["best_total"] is float, "%s：纪录 best_total 类型正确" % name)
		t.check(store.gp_records.is_empty(), "%s：非法大奖赛纪录被丢弃" % name)
		var res: Dictionary = store.submit("village", "speed", 3, 95.5, 30.1, {})
		t.check(res["new_best_total"] and res["new_best_lap"], "%s：提交成绩成功" % name)
		t.check(store.record("village", "speed")["best_total"] == 95.5, "%s：成绩被记录" % name)
	# 整数/浮点互通
	t.check(store.selection["laps"] == 3 or store.selection["laps"] == 5, "laps 保留为整数值")
	# 写盘后能读回
	store.save_selection({"track_id": "desert", "laps": 5})
	store.load_from_disk()
	t.check(store.selection["track_id"] == "desert" and store.selection["laps"] == 5, "写盘后能读回")
	t.check(store.submit_gp("star", 2, 40), "大奖赛首次成绩算刷新")
	t.check(not store.submit_gp("star", 3, 50), "名次更差不算刷新")
	t.check(store.submit_gp("star", 1, 44), "拿到冠军算刷新")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	store.free()
	t.done()
