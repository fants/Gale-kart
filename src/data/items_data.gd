class_name ItemsData
extends RefCounted
## 道具静态数据与按名次加权的发放表。图标在 assets/ui/items/<id>.png（tools/key_icons.py 抠图生成）。

const ITEMS: Dictionary = {
	"nitro": {"name": "氮气", "color": "#3EC6FF", "desc": "立即加速 2 秒。"},
	"missile": {"name": "导弹", "color": "#FF4D5E", "desc": "锁定前一名并追踪，命中后对方翻车。"},
	"water": {"name": "水炸弹", "color": "#3E8BFF", "desc": "抛向前方形成水柱，困住驶入的车。"},
	"banana": {"name": "香蕉皮", "color": "#FFD84A", "desc": "丢在身后，碰到的车会打转。"},
	"shield": {"name": "天使护盾", "color": "#FFF3A8", "desc": "3.5 秒内免疫所有攻击。"},
	"cloud": {"name": "乌云", "color": "#5A5F7A", "desc": "飘到第一名头顶，减速并遮挡视线。"},
	"magnet": {"name": "磁铁", "color": "#FF6B6B", "desc": "吸向前车并获得加速。"},
	"thunder": {"name": "雷暴", "color": "#FFE14A", "desc": "所有领先于你的车都会眩晕（仅落后时可得）。"},
	"ufo": {"name": "飞碟", "color": "#B98CFF", "desc": "飞到第一名头顶：它无法使用道具，速度下降。"},
	"water_fly": {"name": "水苍蝇", "color": "#45C8FF", "desc": "追踪第一名，命中后把它困在水泡里。"},
}

## 按名次比例（0 = 第一名，1 = 最后一名）在三档之间插值
const ITEM_WEIGHTS: Dictionary = {
	"first": {"banana": 34, "shield": 24, "water": 20, "nitro": 10, "missile": 12},
	"middle": {"missile": 24, "water": 16, "nitro": 18, "banana": 10, "magnet": 10, "cloud": 8, "shield": 6, "ufo": 6, "water_fly": 4},
	"last": {"nitro": 22, "missile": 18, "magnet": 18, "cloud": 10, "thunder": 12, "water": 8, "ufo": 10, "water_fly": 10},
}


static var _icons := {}


## 道具图标（缓存）
static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = load("res://assets/ui/items/%s.png" % id)
	return _icons[id]


static func weights_for(rank_frac: float) -> Dictionary:
	var a: Dictionary = ITEM_WEIGHTS["first"] if rank_frac < 0.5 else ITEM_WEIGHTS["middle"]
	var b: Dictionary = ITEM_WEIGHTS["middle"] if rank_frac < 0.5 else ITEM_WEIGHTS["last"]
	var t := rank_frac * 2.0 if rank_frac < 0.5 else (rank_frac - 0.5) * 2.0
	var out := {}
	for k: String in ITEMS:
		var w := float(a.get(k, 0)) * (1.0 - t) + float(b.get(k, 0)) * t
		if w > 0.001:
			out[k] = w
	return out
