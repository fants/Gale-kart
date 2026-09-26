class_name ThemesData
extends RefCounted
## 赛道主题：天空、雾、光照、地面、路面、路缘、护墙、天气。
## 颜色一律用 "#RRGGBB" 字符串存储，使用时 Color(str) 转换。
## base：派生主题所基于的主题 id（场景物件、地面、特效等按 base 处理，颜色 / 光照 / 护墙用自己的）。
## fog.near / fog.far 单位米（环境雾按此换算密度）；light.sun_dir 为指向太阳的方向。

const THEMES: Dictionary = {
	"village": {
		"id": "village", "time": "day", "weather": "leaves", "night": false,
		"sky": {"top": "#3F9FF0", "horizon": "#CFEBFF", "sun": "#FFF4D6"},
		"fog": {"color": "#CFE7FA", "near": 160.0, "far": 820.0},
		"light": {"sun": "#FFF0D2", "sun_energy": 1.35, "sun_dir": [0.55, 0.75, 0.35], "ambient": "#D4ECFF", "ambient_energy": 0.55},
		"ground": {"base": "#7CC35B", "alt": "#64AE47", "far": "#88C866"},
		"shoulder": "#9ACB62",
		"road": {"base": "#5E6572", "speck": "#6F7684", "line": "#FFFFFF", "center": "#FFD84A"},
		"curb": ["#FF4D5E", "#FFFFFF"],
		"wall": {"style": "fence", "a": "#FFFFFF", "b": "#3EC6FF"},
	},
	"desert": {
		"id": "desert", "time": "day", "weather": "dust", "night": false,
		"sky": {"top": "#2F8FDB", "horizon": "#FFE3B3", "sun": "#FFF1C4"},
		"fog": {"color": "#F5DDB0", "near": 150.0, "far": 780.0},
		"light": {"sun": "#FFE6BD", "sun_energy": 1.5, "sun_dir": [-0.4, 0.7, 0.5], "ambient": "#FFE9C7", "ambient_energy": 0.5},
		"ground": {"base": "#EBC47C", "alt": "#DDB06A", "far": "#F0CC8A"},
		"shoulder": "#E2B56E",
		"road": {"base": "#86705E", "speck": "#98806C", "line": "#FFF3DC", "center": "#FFB84A"},
		"curb": ["#FF7A3D", "#FFF3DC"],
		"wall": {"style": "stone", "a": "#D9A55B", "b": "#B98543"},
	},
	"snow": {
		"id": "snow", "time": "day", "weather": "snow", "night": false,
		"sky": {"top": "#6FA9E0", "horizon": "#EEF6FF", "sun": "#FFFFFF"},
		"fog": {"color": "#E4EEF8", "near": 130.0, "far": 700.0},
		"light": {"sun": "#FFFFFF", "sun_energy": 1.2, "sun_dir": [0.3, 0.6, -0.6], "ambient": "#E6F2FF", "ambient_energy": 0.65},
		"ground": {"base": "#F4F8FC", "alt": "#E3EDF7", "far": "#EEF4FA"},
		"shoulder": "#DCE8F4",
		"road": {"base": "#8EAAC6", "speck": "#A9C2DA", "line": "#FFFFFF", "center": "#7FD6FF"},
		"curb": ["#3E8BFF", "#FFFFFF"],
		"wall": {"style": "ice", "a": "#BFE8FF", "b": "#8FD0F5"},
	},
	"forest": {
		"id": "forest", "time": "day", "weather": "fireflies", "night": false,
		"sky": {"top": "#4E9BD8", "horizon": "#D6F0E4", "sun": "#FFF2C8"},
		"fog": {"color": "#BFD9C8", "near": 90.0, "far": 620.0},
		"light": {"sun": "#FFE8B8", "sun_energy": 1.3, "sun_dir": [-0.5, 0.62, -0.4], "ambient": "#CFE8D4", "ambient_energy": 0.5},
		"ground": {"base": "#4F9A45", "alt": "#3F8538", "far": "#5FA850"},
		"shoulder": "#7A9A4A",
		"road": {"base": "#6A5F55", "speck": "#7B7064", "line": "#FFF6E0", "center": "#FFD84A"},
		"curb": ["#E8A23C", "#FFF6E0"],
		"wall": {"style": "log", "a": "#8A5A34", "b": "#6B4428"},
	},
	"circuit": {
		"id": "circuit", "time": "sunset", "weather": "none", "night": false,
		"sky": {"top": "#3B4FA8", "horizon": "#FFB27A", "sun": "#FFD9A0"},
		"fog": {"color": "#F2B08C", "near": 180.0, "far": 900.0},
		"light": {"sun": "#FFC48A", "sun_energy": 1.25, "sun_dir": [0.8, 0.22, 0.2], "ambient": "#C9B6E8", "ambient_energy": 0.55},
		"ground": {"base": "#6FB24E", "alt": "#5E9F42", "far": "#7CB85A"},
		"shoulder": "#D9CFB8",
		"road": {"base": "#4A4F5C", "speck": "#5A606E", "line": "#FFFFFF", "center": "#FFFFFF"},
		"curb": ["#FF4D5E", "#FFFFFF"],
		"wall": {"style": "tire", "a": "#22252E", "b": "#FF4D5E"},
	},
	"town": {
		"id": "town", "base": "village", "time": "day", "weather": "leaves", "night": false,
		"sky": {"top": "#4FA6EE", "horizon": "#DDF0FF", "sun": "#FFF2D8"},
		"fog": {"color": "#D8EAF7", "near": 150.0, "far": 760.0},
		"light": {"sun": "#FFEFD6", "sun_energy": 1.35, "sun_dir": [-0.45, 0.72, 0.5], "ambient": "#DCEBFF", "ambient_energy": 0.55},
		"ground": {"base": "#86C55E", "alt": "#6FB24C", "far": "#8FCB6C"},
		"shoulder": "#C9B89A",
		"road": {"base": "#6B6670", "speck": "#7C7680", "line": "#FFFFFF", "center": "#FFD84A"},
		"curb": ["#E0533D", "#FFF3DC"],
		"wall": {"style": "stone", "a": "#C8553D", "b": "#8E3B2A"},
	},
	"mushroom": {
		"id": "mushroom", "base": "forest", "time": "day", "weather": "leaves", "night": false,
		"sky": {"top": "#5AA8E0", "horizon": "#F4E6C4", "sun": "#FFE3A8"},
		"fog": {"color": "#D9E4C0", "near": 110.0, "far": 640.0},
		"light": {"sun": "#FFD9A0", "sun_energy": 1.35, "sun_dir": [0.55, 0.5, -0.45], "ambient": "#E3E8C8", "ambient_energy": 0.5},
		"ground": {"base": "#6DAF3F", "alt": "#5A9A33", "far": "#7AB84E"},
		"shoulder": "#A08A5A",
		"road": {"base": "#7A6A58", "speck": "#8B7B68", "line": "#FFF6E0", "center": "#FFD84A"},
		"curb": ["#E24A3B", "#FFF6E0"],
		"wall": {"style": "fence", "a": "#F2DDB4", "b": "#A8703F"},
	},
	"city": {
		"id": "city", "time": "night", "weather": "none", "night": true,
		"sky": {"top": "#070B26", "horizon": "#46206A", "sun": "#FFB3F0"},
		"fog": {"color": "#1F1840", "near": 120.0, "far": 640.0},
		"light": {"sun": "#B7C2FF", "sun_energy": 0.45, "sun_dir": [0.3, 0.8, 0.4], "ambient": "#5A5CC8", "ambient_energy": 0.45},
		"ground": {"base": "#262840", "alt": "#1E2034", "far": "#23253B"},
		"shoulder": "#34374F",
		"road": {"base": "#2A2D3F", "speck": "#353849", "line": "#3EC6FF", "center": "#FF4DC4"},
		"curb": ["#FFC93C", "#1B1F3B"],
		"wall": {"style": "neon", "a": "#3EC6FF", "b": "#FF4DC4"},
	},
}


static func get_theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES["village"])


## 主题的基础类型（派生主题返回 base，否则返回自己的 id）
static func base_of(theme: Dictionary) -> String:
	return str(theme.get("base", theme.get("id", "village")))
