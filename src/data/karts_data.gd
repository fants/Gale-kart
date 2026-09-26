class_name KartsData
extends RefCounted
## 赛车、车手、涂装与难度的静态数据。

## look：外观差异（KartModel 使用）
##   spoiler: "" | "debris-spoiler-a" | "debris-spoiler-b"
##   wheels: "" 表示原车轮 | "wheel-racing" | "wheel-truck" | "wheel-dark"
##   scale: 车身整体缩放系数；exhaust: 是否加双排气火箭筒；bumper: 是否加前保险杠
const KARTS: Array[Dictionary] = [
	{
		"id": "marshmallow", "name": "棉花糖", "en": "MARSHMALLOW",
		"blurb": "各项均衡，新手首选。",
		"stats": {"speed": 3, "accel": 3, "handling": 3, "drift": 3, "boost": 3, "weight": 3},
		"look": {"spoiler": "", "wheels": "", "scale": 1.0, "exhaust": false, "bumper": false},
	},
	{
		"id": "bolt", "name": "闪电", "en": "BOLT",
		"blurb": "极速最高，起步偏慢，适合长直道。",
		"stats": {"speed": 5, "accel": 2, "handling": 2, "drift": 3, "boost": 3, "weight": 3},
		"look": {"spoiler": "debris-spoiler-a", "wheels": "wheel-racing", "scale": 1.0, "exhaust": false, "bumper": false},
	},
	{
		"id": "whirl", "name": "旋风", "en": "WHIRL",
		"blurb": "转向灵敏、集气快，连续弯道之王。",
		"stats": {"speed": 3, "accel": 4, "handling": 5, "drift": 4, "boost": 2, "weight": 2},
		"look": {"spoiler": "debris-spoiler-b", "wheels": "wheel-dark", "scale": 0.95, "exhaust": false, "bumper": false},
	},
	{
		"id": "rocket", "name": "火箭", "en": "ROCKET",
		"blurb": "氮气威力最强，转向较笨重。",
		"stats": {"speed": 4, "accel": 3, "handling": 2, "drift": 2, "boost": 5, "weight": 3},
		"look": {"spoiler": "", "wheels": "wheel-racing", "scale": 1.0, "exhaust": true, "bumper": false},
	},
	{
		"id": "ironclad", "name": "铁甲", "en": "IRONCLAD",
		"blurb": "车身沉重，碰撞中稳如泰山。",
		"stats": {"speed": 3, "accel": 2, "handling": 3, "drift": 3, "boost": 3, "weight": 5},
		"look": {"spoiler": "", "wheels": "wheel-truck", "scale": 1.06, "exhaust": false, "bumper": true},
	},
]

const STAT_LABELS: Array = [
	["speed", "极速"], ["accel", "加速"], ["handling", "操控"],
	["drift", "漂移"], ["boost", "氮气"], ["weight", "重量"],
]

## model：assets/models/characters/ 下的文件名（不含扩展名）；color：UI 上的代表色
const CHARACTERS: Array[Dictionary] = [
	{"id": "male-a", "name": "阿飞", "model": "character-male-a", "color": "#45E3A6"},
	{"id": "female-b", "name": "小桃", "model": "character-female-b", "color": "#FFC93C"},
	{"id": "male-b", "name": "大熊", "model": "character-male-b", "color": "#FF8A3D"},
	{"id": "female-a", "name": "琪琪", "model": "character-female-a", "color": "#9B6BFF"},
	{"id": "male-c", "name": "警长", "model": "character-male-c", "color": "#3E6BFF"},
	{"id": "female-e", "name": "小雪", "model": "character-female-e", "color": "#F7FAFF"},
	{"id": "male-e", "name": "博士", "model": "character-male-e", "color": "#FFD84A"},
	{"id": "female-c", "name": "花婆婆", "model": "character-female-c", "color": "#FF4D5E"},
	{"id": "male-d", "name": "金老板", "model": "character-male-d", "color": "#2D2D3A"},
	{"id": "female-d", "name": "安娜", "model": "character-female-d", "color": "#8A8FA8"},
	{"id": "male-f", "name": "小虎", "model": "character-male-f", "color": "#3EC6FF"},
	{"id": "female-f", "name": "露露", "model": "character-female-f", "color": "#B98CFF"},
]

## model：assets/models/karts/ 下的卡丁车配色版本
const PAINTS: Array[Dictionary] = [
	{"id": "oobi", "name": "葡萄紫", "model": "kart-oobi", "color": "#9B8CFF"},
	{"id": "oodi", "name": "樱桃粉", "model": "kart-oodi", "color": "#FF7FA8"},
	{"id": "ooli", "name": "阳光黄", "model": "kart-ooli", "color": "#FFC93C"},
	{"id": "oopi", "name": "薄荷青", "model": "kart-oopi", "color": "#3FC7B8"},
	{"id": "oozi", "name": "奶茶米", "model": "kart-oozi", "color": "#E3B89A"},
]

## speed：极速系数；line：走线精度；aggression：道具积极性；rubber：橡皮筋强度；
## start_boost：起步加速概率；mistakes：失误概率；instant：出弯小喷概率；shortcut：走近道的概率
const DIFFICULTIES: Dictionary = {
	"easy": {"id": "easy", "name": "简单", "speed": 0.88, "line": 0.55, "aggression": 0.35, "rubber": 0.6, "start_boost": 0.15, "mistakes": 0.3, "instant": 0.0, "shortcut": 0.1},
	"normal": {"id": "normal", "name": "普通", "speed": 0.955, "line": 0.8, "aggression": 0.6, "rubber": 0.45, "start_boost": 0.35, "mistakes": 0.12, "instant": 0.2, "shortcut": 0.35},
	"hard": {"id": "hard", "name": "困难", "speed": 1.0, "line": 1.0, "aggression": 0.9, "rubber": 0.3, "start_boost": 0.6, "mistakes": 0.03, "instant": 0.5, "shortcut": 0.6},
}


## 由 1–5 星属性计算物理参数（与参考版 kartParams 一致）
static func kart_params(stats: Dictionary) -> Dictionary:
	return {
		"max_speed": 33.6 + stats["speed"] * 0.9,
		"accel": 12.0 + stats["accel"] * 2.4,
		"brake": 32.0,
		"reverse_max": 9.0,
		"turn_rate": 1.5 + stats["handling"] * 0.08,
		"grip": 11.0,
		"drift_grip": 1.75 + stats["handling"] * 0.05,
		"drift_turn": 1.25 + stats["drift"] * 0.04,
		"drift_charge": 0.27 + stats["drift"] * 0.025,
		"drift_drag": 2.3 - stats["drift"] * 0.25,
		"boost_power": 0.3 + stats["boost"] * 0.025,
		"nitro_time": 2.0 + stats["boost"] * 0.1,
		"mass": 0.8 + stats["weight"] * 0.1,
	}


static func kart_by_id(id: String) -> Dictionary:
	for k in KARTS:
		if k["id"] == id:
			return k
	return KARTS[0]


static func character_by_id(id: String) -> Dictionary:
	for c in CHARACTERS:
		if c["id"] == id:
			return c
	return CHARACTERS[0]


static func paint_by_id(id: String) -> Dictionary:
	for p in PAINTS:
		if p["id"] == id:
			return p
	return PAINTS[0]
