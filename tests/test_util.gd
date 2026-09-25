class_name TestUtil
extends RefCounted
## 极简断言工具：统计失败数，打印每条结果。

var failures := 0
var passes := 0
var suite := ""
var verbose := false


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		if verbose:
			print("  PASS: ", msg)
	else:
		failures += 1
		printerr("  FAIL [%s]: %s" % [suite, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (%.4f vs %.4f)" % [msg, a, b])
