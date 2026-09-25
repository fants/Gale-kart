class_name TracksData
extends RefCounted
## 赛道定义：闭合样条控制点 [x, z, y]（米；x、z 会乘以 scale），第一个点即起终点线。
## ramps / boost_pads / item_rows 的 at 为一圈中的比例位置（0..1）。

const TRACKS: Array[Dictionary] = [
	{
		"id": "village", "name": "阳光小镇", "en": "SUNNY VILLAGE",
		"blurb": "风车与红顶小屋之间的宽阔环线，适合练习漂移。",
		"difficulty": 1, "theme": "village", "cup": "star", "music": "village",
		"half_width": 10.0, "shoulder": 3.5, "scale": 1.3, "grip": 1.0, "terrain": "follow",
		"points": [
			[0, -40, 0], [0, 60, 0], [22, 138, 0], [90, 172, 2], [160, 142, 4.5],
			[182, 72, 4.5], [142, 12, 3], [168, -52, 2], [232, -92, 1], [236, -172, 0],
			[176, -232, 0], [84, -236, 0], [22, -196, 0], [0, -120, 0],
		],
		"ramps": [],
		"boost_pads": [{"at": 0.36, "lateral": 0.0}, {"at": 0.8, "lateral": -3.0}],
		"item_rows": [0.1, 0.33, 0.56, 0.78],
	},
	{
		"id": "desert", "name": "黄金沙漠", "en": "GOLDEN DUNES",
		"blurb": "穿越金字塔的起伏沙丘，两处跳台可以飞越。",
		"difficulty": 2, "theme": "desert", "cup": "star", "music": "desert",
		"half_width": 9.5, "shoulder": 3.5, "scale": 1.25, "grip": 1.0, "terrain": "follow",
		"points": [
			[0, -40, 0], [0, 100, 0], [30, 182, 3], [110, 214, 6], [192, 172, 9],
			[214, 92, 6], [172, 38, 3], [104, 36, 0], [62, -12, 0], [92, -72, 0],
			[172, -84, 2], [252, -42, 5], [304, -100, 8], [284, -190, 4], [202, -232, 0],
			[102, -224, 0], [30, -184, 0], [0, -112, 0],
		],
		"ramps": [{"at": 0.075, "len": 11.0, "height": 2.4}, {"at": 0.64, "len": 10.0, "height": 2.2}],
		"boost_pads": [{"at": 0.05, "lateral": 0.0}, {"at": 0.62, "lateral": 0.0}, {"at": 0.86, "lateral": 3.0}],
		"item_rows": [0.16, 0.38, 0.54, 0.76, 0.93],
	},
	{
		"id": "snow", "name": "冰雪乐园", "en": "FROSTY PARK",
		"blurb": "雪松林中的冰面赛道，抓地力更低，漂移更滑。",
		"difficulty": 2, "theme": "snow", "cup": "star", "music": "snow",
		"half_width": 9.5, "shoulder": 3.5, "scale": 1.25, "grip": 0.7, "terrain": "follow",
		"points": [
			[0, -40, 0], [0, 80, 0], [40, 152, 2], [120, 164, 5], [172, 112, 6],
			[152, 42, 4], [202, -10, 3], [272, 22, 6], [322, -30, 8], [302, -122, 5],
			[222, -162, 3], [142, -122, 1], [82, -172, 0], [20, -164, 0], [0, -104, 0],
		],
		"ramps": [{"at": 0.47, "len": 10.0, "height": 1.8}],
		"boost_pads": [{"at": 0.2, "lateral": 0.0}, {"at": 0.72, "lateral": -2.0}],
		"item_rows": [0.12, 0.3, 0.52, 0.7, 0.88],
	},
	{
		"id": "forest", "name": "森林峡谷", "en": "TIMBER GORGE",
		"blurb": "穿过巨木与峭壁的山路，大跳台飞越河流。",
		"difficulty": 2, "theme": "forest", "cup": "gale", "music": "forest",
		"half_width": 9.0, "shoulder": 3.0, "scale": 1.25, "grip": 1.0, "terrain": "follow",
		"points": [
			[0, -40, 0], [0, 70, 0], [22, 140, 3], [82, 178, 7], [150, 166, 11],
			[188, 114, 14], [166, 58, 15], [108, 40, 13], [78, -8, 10], [104, -52, 8],
			[160, -64, 6.5], [220, -68, 5], [272, -92, 3], [270, -160, 1], [210, -206, 0],
			[130, -214, 0], [60, -200, 0], [18, -156, 0], [0, -104, 0],
		],
		"ramps": [{"at": 0.535, "len": 14.0, "height": 3.2}],
		"rivers": [{"at": 0.553, "width": 14.0}],
		"boost_pads": [{"at": 0.513, "lateral": 0.0}, {"at": 0.3, "lateral": 2.0}],
		"item_rows": [0.12, 0.32, 0.46, 0.7, 0.86],
	},
	{
		"id": "circuit", "name": "疾风赛车场", "en": "GALE CIRCUIT",
		"blurb": "夕阳下的正规赛车场，两条长直道和一个发卡弯。",
		"difficulty": 2, "theme": "circuit", "cup": "gale", "music": "circuit",
		"half_width": 11.0, "shoulder": 4.0, "scale": 1.0, "grip": 1.0, "terrain": "follow",
		"points": [
			[0, -120, 0], [0, 40, 0], [0, 150, 0], [22, 208, 0], [80, 232, 0],
			[140, 214, 0.5], [190, 236, 1], [248, 222, 1], [292, 176, 1], [300, 110, 1],
			[300, -40, 1], [300, -150, 1], [284, -206, 0.5], [236, -224, 0], [200, -192, 0],
			[192, -140, 0], [160, -108, 0], [118, -126, 0], [88, -178, 0], [50, -214, 0],
			[10, -200, 0],
		],
		"ramps": [],
		"boost_pads": [{"at": 0.02, "lateral": 0.0}, {"at": 0.45, "lateral": 0.0}],
		"item_rows": [0.14, 0.34, 0.5, 0.68, 0.88],
	},
	{
		"id": "city", "name": "霓虹夜城", "en": "NEON NIGHT",
		"blurb": "霓虹楼宇间的 8 字立交，窄路连弯，考验走线。",
		"difficulty": 3, "theme": "city", "cup": "gale", "music": "city",
		"half_width": 8.5, "shoulder": 2.5, "scale": 1.2, "grip": 1.0, "terrain": "flat",
		"points": [
			[-70, -70, 0], [0, 0, 0], [70, 70, 0], [120, 150, 1], [200, 172, 3],
			[262, 122, 5], [252, 30, 7], [172, -58, 8.5], [100, -100, 9.5], [50, -50, 9.5],
			[0, 0, 9.5], [-50, 50, 9.5], [-100, 100, 9], [-180, 132, 6], [-252, 90, 3.5],
			[-262, 10, 1], [-212, -70, 0], [-140, -110, 0],
		],
		"ramps": [],
		"boost_pads": [{"at": 0.03, "lateral": 0.0}, {"at": 0.5, "lateral": 0.0}, {"at": 0.78, "lateral": 2.0}],
		"item_rows": [0.12, 0.3, 0.46, 0.64, 0.86],
	},
]

const CUPS: Array[Dictionary] = [
	{"id": "star", "name": "新星杯", "tracks": ["village", "desert", "snow"]},
	{"id": "gale", "name": "疾风杯", "tracks": ["forest", "circuit", "city"]},
]


static func track_by_id(id: String) -> Dictionary:
	for t in TRACKS:
		if t["id"] == id:
			return t
	return TRACKS[0]


static func cup_by_id(id: String) -> Dictionary:
	for c in CUPS:
		if c["id"] == id:
			return c
	return CUPS[0]
