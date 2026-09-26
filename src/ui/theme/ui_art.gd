class_name UiArt
extends RefCounted
## 生图素材（GPT Image 生成、tools/key_icons.py 抠图）：Logo、菜单图标、奖杯奖牌、赛道插画、菜单背景。
## 找不到对应图片时返回 null，调用方退回原来的矢量画法。

const ICON_DIR := "res://assets/ui/icons/"
const TRACK_DIR := "res://assets/ui/tracks/"

static var _cache := {}


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func logo() -> Texture2D:
	return _load("res://assets/ui/logo.png")


## 菜单背景：day 白天（车库 / 菜单），golden 黄昏（颁奖台）
static func menu_bg(kind: String) -> Texture2D:
	return _load("res://assets/ui/bg/menu_%s.jpg" % kind)


static func track_art(track_id: String) -> Texture2D:
	return _load(TRACK_DIR + track_id + ".jpg")


## 图标：奖杯 / 奖牌按填充色选金银铜；其余按名字找图片
static func icon(kind: String, fill := Color.WHITE) -> Texture2D:
	var name := kind
	if kind == "trophy" or kind == "medal":
		name = kind + "_" + _metal(fill)
	return _load(ICON_DIR + name + ".png")


static func _metal(fill: Color) -> String:
	if fill.is_equal_approx(UiTheme.SILVER):
		return "silver"
	if fill.is_equal_approx(UiTheme.BRONZE):
		return "bronze"
	return "gold"
