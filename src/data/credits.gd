class_name Credits
extends RefCounted
## 作者署名（首页、菜单、加载页、结算、颁奖、暂停、比赛 HUD、回放水印、赛道广告牌与横幅）。
## 改名字：改这里的 NAME，再运行 python3 tools/make_promo.py 重新生成广告牌 / 横幅贴图。

const PLATFORM := "bilibili"
const NAME := "铂金小鸟"
## bilibili 品牌粉 / 蓝
const PINK := Color("#FB7299")
const BLUE := Color("#00AEEC")


static func tag() -> String:
	return "%s @%s" % [PLATFORM, NAME]
