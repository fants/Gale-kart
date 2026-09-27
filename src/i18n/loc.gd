class_name Loc
extends RefCounted
## 多语言：源文本是简体中文，EN 是英文对照表。
## 设置里的 language：auto（跟随系统：简体中文系统显示中文，其余英文）/ zh / en。
## 静态文字（Label / Button 的 text 直接是中文）由 Godot 自动翻译，切换语言时即时生效；
## 拼接 / 格式化 / 自绘的文字用 Loc.t() 先翻译格式串再填参数。

const LANGS: Array[String] = ["auto", "zh", "en"]

static var lang := "zh"
static var _registered := false


## 按设置选择语言并通知 TranslationServer
static func apply(setting: String) -> void:
	lang = resolve(setting)
	if not _registered:
		var tr := Translation.new()
		tr.locale = "en"
		for k: String in EN:
			tr.add_message(k, EN[k])
		TranslationServer.add_translation(tr)
		_registered = true
	TranslationServer.set_locale("en" if lang == "en" else "zh_CN")


static func resolve(setting: String) -> String:
	if setting == "zh" or setting == "en":
		return setting
	return system_lang()


## 系统语言：简体中文（zh_CN / zh_SG / zh_Hans…）→ zh，其余（含繁体）→ en
static func system_lang() -> String:
	var loc := OS.get_locale().replace("-", "_")
	var lower := loc.to_lower()
	if not lower.begins_with("zh"):
		return "en"
	if "hant" in lower or lower.ends_with("_tw") or lower.ends_with("_hk") or lower.ends_with("_mo"):
		return "en"
	return "zh"


static func is_en() -> bool:
	return lang == "en"


static func t(s: String) -> String:
	if lang == "en":
		return EN.get(s, s)
	return s


## 数据里的名字（赛道 / 车手 / 赛车 / 涂装 / 道具 / 杯赛）
static func name_of(d: Dictionary) -> String:
	return t(str(d.get("name", "")))


const EN := {
	# —— 通用 ——
	"疾风卡丁": "Gale Kart",
	"你": "You",
	"%s（你）": "%s (You)",
	"确认": "Confirm", "确定": "OK", "返回": "Back", "取消": "Cancel", "关闭": "Close", "完成": "Done",
	"选择": "Select", "切换": "Switch", "调节": "Adjust", "滚动": "Scroll", "切换标签": "Tabs",
	"退出": "Quit", "开": "ON", "关": "OFF", "或": "or",
	"竞速赛": "Speed Race", "道具赛": "Item Race", "计时赛": "Time Trial",
	"竞速": "Speed", "道具": "Items",
	"简单": "Easy", "普通": "Normal", "困难": "Hard",
	"%d 圈": "Laps %d", "1 圈": "1", "3 圈": "3", "5 圈": "5",
	"第 %d 名": "#%d", "%d 分": "%d pts", "分": "pts",
	"冠军！": "Champion!", "亚军！": "2nd Place!", "季军！": "3rd Place!",
	"—": "—",
	# —— 标题 / 主菜单 ——
	"漂移 · 集气 · 氮气加速 —— 和 7 位对手一决高下！": "Drift · Charge · Nitro — race 7 rivals to the finish!",
	"按任意键开始": "Press any key",
	"鼠标点击": "Click",
	"快速比赛": "Quick Race",
	"竞速赛 · 道具赛  和 7 位 AI 一决高下": "Speed or Items — take on 7 AI racers",
	"大奖赛": "Grand Prix",
	"新星杯 · 疾风杯  四场积分定冠军": "Rising Star · Gale Cup — 4 races, points decide",
	"单人冲刺  挑战自己的幽灵车": "Solo sprint — beat your own ghost",
	"最佳纪录": "Records",
	"设置": "Settings",
	"操作说明": "How to Play",
	"退出游戏": "Quit Game",
	"当前座驾": "Current ride",
	"换车": "Garage",
	"%s · %s涂装": "%s · %s paint",
	"要退出游戏吗？": "Quit the game?",
	# —— 赛前设置 / 车库 ——
	"漂移集气、释放氮气，和 7 位 AI 对手比拼纯速度。": "Drift to charge nitro and outrun 7 AI rivals in a pure speed race.",
	"撞碎道具箱获得道具，用导弹、水炸弹、香蕉皮扰乱对手。": "Smash item boxes and mess with rivals using missiles, water bombs and bananas.",
	"独自冲刺最快成绩，最佳一局会作为幽灵车陪你跑。": "Race alone for your best time — your best run returns as a ghost.",
	"同一杯赛连跑 4 场，按名次得分（10 / 8 / 6 / 5 / 4 / 3 / 2 / 1），总分最高者夺冠。": "Race 4 tracks in a row and score by position (10 / 8 / 6 / 5 / 4 / 3 / 2 / 1). Most points wins the cup.",
	"单人挑战": "Solo",
	"四场积分": "4 Races",
	"开始比赛": "Start Race",
	"开始大奖赛": "Start Grand Prix",
	"赛事": "Race",
	"车库": "Garage",
	"模式": "Mode",
	"圈数": "Laps",
	"难度": "Difficulty",
	"规则": "Rules",
	"幽灵车": "Ghost",
	"计时赛 · 单人": "Time Trial · Solo",
	"3 圈（固定）": "3 Laps (fixed)",
	"暂无幽灵车": "No ghost yet",
	"杯赛": "Cups",
	"赛道": "Tracks",
	"尚未参赛": "Not raced",
	"最好第 %d 名 · %d 分": "Best #%d · %d pts",
	"%d 场总分前三名登上领奖台": "Top 3 after %d races take the podium",
	"车手": "Driver",
	"赛车": "Kart",
	"涂装": "Paint",
	"均衡型": "All-Round",
	"%s型": "%s",
	"圈 ": "Lap ",
	"最佳 %s": "Best %s",
	"计时赛 · %s · 3 圈": "Time Trial · %s · 3 Laps",
	"%s · %s规则 · %s · %d 圈": "%s · %s · %s · Laps %d",
	"%s · %s · %s · %d 圈": "%s · %s · %s · Laps %d",
	"%s 驾驶 %s（%s涂装）": "%s driving %s (%s paint)",
	# —— 赛车属性 ——
	"极速": "Speed", "加速": "Accel", "操控": "Turn", "漂移": "Drift", "氮气": "Nitro", "重量": "Weight",
	# —— 加载页 ——
	"小贴士": "TIP",
	"赛道加载中…": "Loading track…",
	"%s · 第 %d / %d 场": "%s · Race %d / %d",
	"关注 %s，看更多疾风卡丁的比赛视频！": "Follow %s for more Gale Kart racing videos!",
	"漂移后松开，趁提示出现时再按一次 ↑，触发瞬间加速（小喷）！": "Release a drift, then tap ↑ when the cue appears for an instant boost!",
	"倒计时 GO 出现的瞬间按下 ↑ 起步加速；提前按住会抢跑哦。": "Press ↑ right as GO appears for a start boost — holding it early is a false start.",
	"紧跟在前车正后方一会儿，就能获得尾流加速。": "Stay right behind another kart for a moment to get a draft boost.",
	"道具赛中按 Q 可以交换两个道具槽里的道具。": "In Item Races, press Q to swap your two item slots.",
	"竞速赛里漂移会积攒集气条，满一格得到一个氮气，最多存 2 个。": "Drifting fills the gauge in Speed Races — each full bar gives a nitro (up to 2).",
	"橙色箭头是加速带，压上去立刻提速；跳台可以飞越障碍。": "Orange arrows are boost pads; ramps let you fly over obstacles.",
	"被导弹锁定时屏幕边缘会泛红，赶紧用天使护盾挡住！": "The screen edge glows red when a missile locks on — use an Angel Shield!",
	"卡住了？按 R 复位回到赛道上。": "Stuck? Press R to respawn on the track.",
	"按 C 切换远 / 近视角，按 H 隐藏 HUD，录视频更干净。": "Press C to switch camera, H to hide the HUD for clean recordings.",
	"冰雪乐园的路面很滑，提前漂移入弯更稳。": "Frosty Park is slippery — start your drifts early.",
	"计时赛会保存你的最佳一局，下次作为幽灵车陪你跑。": "Time Trial saves your best run as a ghost to race next time.",
	"雷暴只有落后时才可能抽到，能让领先的车全部眩晕。": "Thunder only drops when you're behind — it stuns everyone ahead.",
	# —— 比赛 HUD / 事件 ——
	"本圈": "LAP", "最佳": "BEST",
	"超越！第 %d 名": "Overtake! #%d",
	"⚠ 被锁定！": "⚠ LOCKED ON!",
	"逆行！按 R 复位": "Wrong way! Press R",
	"完美起步！": "Perfect start!",
	"抢跑了！": "False start!",
	"瞬间加速！": "Instant boost!",
	"尾流加速！": "Draft boost!",
	"掉下悬崖！走崖下小路绕回去": "Off the cliff! Take the path below back up",
	"导弹来袭！": "Missile incoming!",
	"水苍蝇来袭！": "Water fly incoming!",
	"被水泡困住了！": "Trapped in a bubble!",
	"哎呀，打滑了！": "Whoa, spun out!",
	"被导弹击中！": "Hit by a missile!",
	"被雷暴击晕！": "Stunned by thunder!",
	"命中 %s！": "Hit %s!",
	"护盾挡住了攻击！": "Shield blocked it!",
	"乌云笼罩！": "Under a storm cloud!",
	"乌云飘向 %s": "Storm cloud → %s",
	"飞碟来了，道具被封印！": "UFO! Your items are sealed!",
	"飞碟飞向 %s": "UFO → %s",
	"最后一圈！": "Final lap!",
	"第 %d 圈  %s": "Lap %d  %s",
	# —— 回放 ——
	"1–4 机位 · ←→ 切换车手 · 空格 暂停 · [ ] 速度 · H 隐藏 · Esc 退出": "1–4 Camera · ←→ Driver · Space Pause · [ ] Speed · H Hide · Esc Exit",
	"%s · 第 %d 名 · %d km/h": "%s · #%d · %d km/h",
	"自动导播": "Auto Director", "转播机位": "TV Camera", "追尾": "Chase", "环绕": "Orbit", "俯瞰": "Aerial",
	# —— 暂停 ——
	"暂停": "Paused",
	"第 %d / %d 圈": "Lap %d / %d",
	"继续比赛": "Resume",
	"重新开始": "Restart",
	"退出比赛": "Quit Race",
	"继续": "Resume",
	"重新开始本场比赛？": "Restart this race?",
	"退出大奖赛？本杯赛的积分将不会保存。": "Quit the Grand Prix? Points for this cup won't be saved.",
	"退出比赛，回到主菜单？": "Quit the race and return to the main menu?",
	# —— 结算 ——
	"完成挑战！": "Finished!",
	"%s · %s · %d 圈": "%s · %s · Laps %d",
	"%s 第 %d / %d 场 · %s": "%s %d/%d · %s",
	"总用时  %s": "Total  %s",
	"最快单圈  %s": "Best lap  %s",
	"新纪录：总用时": "New record: total",
	"新纪录：最快单圈": "New record: best lap",
	"比幽灵车快 %.3f 秒": "%.3f s ahead of ghost",
	"比幽灵车慢 %.3f 秒": "%.3f s behind ghost",
	"已保存为幽灵车": "Saved as ghost",
	"本场积分 +%d": "Points +%d",
	"比赛成绩": "Results",
	"精彩回放": "Replay",
	"查看积分榜": "Standings",
	"再来一局": "Retry",
	"下一赛道": "Next",
	"返回菜单": "Menu",
	"名次": "Pos", "总用时": "Total", "最快单圈": "Best Lap",
	"约 ": "≈ ",
	# —— 大奖赛 ——
	"第 %d / %d 场结束 · 积分榜": "Race %d / %d done · Standings",
	"%s  第 %d 名": "%s  #%d",
	"下一场：": "Next: ",
	"下一场：%s": "Next: %s",
	"车手积分": "Driver Points",
	"退出大奖赛": "Quit Grand Prix",
	"颁奖典礼": "Award Ceremony",
	"%s · %s规则": "%s · %s",
	"总成绩 ": "Overall ",
	"总积分 %d 分": "Total %d pts",
	"新纪录：最好名次": "New record: best finish",
	"金杯": "Gold Cup", "银杯": "Silver Cup", "铜杯": "Bronze Cup",
	"再接再厉！": "Keep going!",
	"恭喜夺得%s！": "You won the %s!",
	"登上领奖台，下次冲击冠军！": "On the podium — go for the win next time!",
	"前三名才能拿到奖杯，再来一次吧。": "Only the top 3 get a trophy. Try again!",
	"本杯最好：第 %d 名 · %d 分 · 夺冠 %d 次": "Cup best: #%d · %d pts · %d wins",
	"再战一次": "Try Again",
	# —— 最佳纪录 ——
	"纪录保存在本机存档中；3 圈成绩计入总用时纪录，计时赛同时保存最佳一局的幽灵车。": "Records are saved locally. 3-lap races count toward total time; Time Trial also saves your best run as a ghost.",
	"最快单圈 %s": "Best lap %s",
	"暂无纪录": "No record",
	" · %d 场": " · %d races",
	"夺冠 %d 次": "%d wins",
	# —— 设置 ——
	"音乐音量": "Music Volume",
	"音效音量": "Sound Volume",
	"画质": "Graphics",
	"低画质更流畅；下一场比赛生效": "Lower is smoother; applies next race",
	"低": "Low", "中": "Med", "高": "High",
	"全屏": "Fullscreen",
	"也可以随时按 F11 切换": "Press F11 anytime",
	"垂直同步": "V-Sync",
	"避免画面撕裂": "Prevents screen tearing",
	"视角": "Camera",
	"比赛中按 C 也能切换": "Press C during a race",
	"远": "Far", "近": "Near",
	"自动小喷": "Auto Instant Boost",
	"漂移结束时自动触发瞬间加速": "Trigger instant boost automatically after drifts",
	"显示 FPS": "Show FPS",
	"比赛画面底部显示帧率": "Show frame rate during races",
	"语言": "Language",
	"跟随系统：简体中文系统显示中文，其余英文": "Auto: Chinese on Simplified Chinese systems, English otherwise",
	"自动": "Auto",
	"中文": "中文",
	# —— 操作说明 ——
	"操作": "Controls", "技巧": "Tips",
	"功能": "Action", "键盘": "Keyboard", "手柄": "Gamepad",
	"加速 / 刹车": "Accelerate / Brake",
	"转向": "Steer",
	"氮气 / 道具": "Nitro / Item",
	"交换道具": "Swap Items",
	"复位": "Respawn",
	"切换视角": "Camera",
	"隐藏 HUD": "Hide HUD",
	"静音": "Mute",
	"空格": "Space",
	"左摇杆": "L-Stick", "十字键": "D-Pad",
	"转弯时按住 Shift，车尾甩出、转向更急；松开即结束漂移。": "Hold Shift while turning to swing the tail out and turn sharper; release to stop drifting.",
	"集气与氮气": "Gauge & Nitro",
	"竞速赛中漂移会积攒集气条，满一格得到一个氮气（最多 2 个），按空格释放。": "In Speed Races, drifting fills the gauge. Each full bar gives a nitro (up to 2) — press Space to fire.",
	"瞬间加速（小喷）": "Instant Boost",
	"漂移超过 0.35 秒后松开，火花变蓝、出现 ↑ 提示时再按一次 ↑。": "Drift for over 0.35 s, release, and tap ↑ when the sparks turn blue and the cue appears.",
	"起步加速": "Start Boost",
	"倒计时 GO 出现的瞬间按下 ↑ 获得起步加速；提前按住会抢跑打滑。": "Press ↑ right as GO appears for a start boost; holding it early causes a false start.",
	"尾流": "Draft",
	"紧跟前车正后方约 1 秒，出现风线后获得短暂的尾流加速。": "Stay right behind a kart for about 1 s — wind lines appear and you get a short boost.",
	"加速带与跳台": "Boost Pads & Ramps",
	"橙色箭头地块驶过即加速；跳台可以飞越，落地时注意方向。": "Drive over orange arrows to boost; ramps launch you — watch your landing.",
	"撞碎彩色「?」箱获得道具：领先多拿防守道具，落后多拿进攻道具；Q 交换两个槽位。": "Smash \"?\" boxes for items: leaders get defensive items, those behind get attacks. Q swaps slots.",
	"复位与录像": "Respawn & Recording",
	"卡住了按 R 复位；C 切换远 / 近视角；H 隐藏 HUD，方便录制视频。": "Press R when stuck; C switches camera; H hides the HUD for recording.",
	# —— 赛道 ——
	"阳光小镇": "Sunny Village",
	"城镇手指": "Town Fingers",
	"黄金沙漠": "Golden Dunes",
	"冰雪乐园": "Frosty Park",
	"森林发卡": "Forest Hairpin",
	"森林峡谷": "Timber Gorge",
	"疾风赛车场": "Gale Circuit",
	"霓虹夜城": "Neon Night",
	"新星杯": "Rising Star Cup",
	"疾风杯": "Gale Cup",
	"风车与红顶小屋之间的宽阔环线，适合练习漂移。": "A wide loop among windmills and red-roofed cottages — perfect for drift practice.",
	"像手掌一样来回折返的城镇街道，连续发卡弯考验漂移。": "Town streets that fold back and forth like fingers — back-to-back hairpins test your drifting.",
	"穿越金字塔的起伏沙丘，两处跳台可以飞越。": "Rolling dunes past the pyramids, with two jumps to fly over.",
	"雪松林中的冰面赛道，抓地力更低，漂移更滑。": "An icy track through snowy pines — less grip, longer slides.",
	"蘑菇森林里的窄土路：六连急发卡、没有护栏的悬崖路（掉下去只能走崖下小路绕回）、泥泞谷底、桥下穿行、山顶近道。": "Narrow dirt roads through a mushroom forest: six tight hairpins, an unguarded cliff road (fall off and take the path below), a muddy valley, an underpass and a summit shortcut.",
	"穿过巨木与峭壁的山路，大跳台飞越河流。": "A mountain road past giant trees and cliffs, with a big jump over the river.",
	"夕阳下的正规赛车场，两条长直道和一个发卡弯。": "A real racing circuit at sunset — two long straights and a hairpin.",
	"霓虹楼宇间的 8 字立交，窄路连弯，考验走线。": "A figure-8 overpass among neon towers — narrow, twisty and all about racing lines.",
	# —— 赛车 / 车手 / 涂装 ——
	"棉花糖": "Marshmallow", "闪电": "Bolt", "旋风": "Whirl", "火箭": "Rocket", "铁甲": "Ironclad",
	"各项均衡，新手首选。": "Well balanced — great for beginners.",
	"极速最高，起步偏慢，适合长直道。": "Highest top speed, slower start — loves long straights.",
	"转向灵敏、集气快，连续弯道之王。": "Nimble steering and fast charging — king of twisty tracks.",
	"氮气威力最强，转向较笨重。": "Strongest nitro, but heavy steering.",
	"车身沉重，碰撞中稳如泰山。": "Heavy body — rock steady in collisions.",
	"阿飞": "Ace", "小桃": "Peach", "大熊": "Bear", "琪琪": "Kiki", "警长": "Sheriff", "小雪": "Snowy",
	"博士": "Doc", "花婆婆": "Granny", "金老板": "Boss Gold", "安娜": "Anna", "小虎": "Tiger", "露露": "Lulu",
	"葡萄紫": "Grape", "樱桃粉": "Cherry", "阳光黄": "Sunshine", "薄荷青": "Mint", "奶茶米": "Milk Tea",
	# —— 道具 ——
	"导弹": "Missile", "水炸弹": "Water Bomb", "香蕉皮": "Banana", "天使护盾": "Angel Shield",
	"乌云": "Storm Cloud", "磁铁": "Magnet", "雷暴": "Thunder", "飞碟": "UFO", "水苍蝇": "Water Fly",
	"立即加速 2 秒。": "Boost for 2 seconds.",
	"锁定前一名并追踪，命中后对方翻车。": "Locks onto the kart ahead and flips it over.",
	"抛向前方形成水柱，困住驶入的车。": "Lobbed ahead into a water column that traps karts.",
	"丢在身后，碰到的车会打转。": "Dropped behind you — karts that hit it spin out.",
	"3.5 秒内免疫所有攻击。": "Blocks all attacks for 3.5 seconds.",
	"飘到第一名头顶，减速并遮挡视线。": "Floats over the leader, slowing them and blocking their view.",
	"吸向前车并获得加速。": "Pulls you toward the kart ahead with a boost.",
	"所有领先于你的车都会眩晕（仅落后时可得）。": "Stuns every kart ahead of you (only when you're behind).",
	"飞到第一名头顶：它无法使用道具，速度下降。": "Hovers over the leader: they can't use items and slow down.",
	"追踪第一名，命中后把它困在水泡里。": "Chases the leader and traps them in a bubble.",
	# —— 首次启动 ——
	"首次启动，正在准备 3D 图形…": "First launch: preparing 3D graphics…",
	"只有第一次需要，可能要 1～2 分钟，之后启动就很快了。请稍候，不要关闭窗口。": "This only happens once and may take 1–2 minutes. Later launches are fast — please don't close the window.",
	"已等待 %d 秒": "Waiting %d s",
	"准备完成，马上开始！": "Ready — starting now!",
	"3D 图形启动失败，请更新显卡驱动后重试。": "3D graphics failed to start. Please update your graphics driver and try again.",
	# —— 作者 ——
	"关注我 · 看更多赛车视频！": "Follow me for more racing videos!",
}
