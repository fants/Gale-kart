extends SceneTree
## 测试入口：godot --headless --path . -s tests/run_tests.gd [-- --only=track,race --verbose]
## 依次运行 tests/test_*.gd（每个脚本提供 run(t: TestUtil)），退出码 = 失败数。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var only: PackedStringArray = []
	var t := TestUtil.new()
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--verbose":
			t.verbose = true
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_util.gd":
			var name := f.trim_prefix("test_").trim_suffix(".gd")
			if only.is_empty() or name in only:
				files.append(f)
	files.sort()
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var suite: Object = script.new()
		t.suite = f.trim_suffix(".gd")
		var before := t.failures
		var s0 := Time.get_ticks_msec()
		await suite.run(t)
		print("[%s] %s  (%d ms)" % ["OK" if t.failures == before else "FAILED", t.suite, Time.get_ticks_msec() - s0])
	print("\n%d passed, %d failures (%.1f s)" % [t.passes, t.failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(t.failures)
