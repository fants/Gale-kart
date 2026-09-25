# 疾风卡丁 GALE KART（Godot 版）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Godot 4.7 做一个完成度超过网页版参考项目的跑跑卡丁车式 3D 赛车游戏。

**Architecture:** 仿真层（`src/sim`，纯 RefCounted，120 Hz 固定子步，可无界面运行）移植自参考版 `~/Workspaces/AI/opus5.5-test/src/sim/*.js`；表现层（`src/view`）读取仿真状态，并在两个子步之间插值渲染；`RaceController` 把仿真、表现、HUD、音频粘在一起，并分发事件；`Game` 自动加载单例负责菜单和比赛之间的流程切换。

**Tech Stack:** Godot 4.7.2 / GDScript（静态类型）/ Forward+ / Kenney CC0 GLB / Python3 + numpy + ffmpeg（离线合成音频）

**Spec:** `docs/superpowers/specs/2026-09-26-gale-kart-godot-design.md`

**参考源码（移植依据）：** `~/Workspaces/AI/opus5.5-test/src/`：`sim/{math,track,kart,ai,race,items,terrain}.js`、`data/{karts,tracks}.js`、`view/*.js`、`audio/*.js`、`ui/*.js`。移植时保持数值和算法一致，只改命名（camelCase → snake_case）和语言习惯。

## Global Constraints

- 引擎 Godot 4.7.2，渲染器 `forward_plus`；GDScript 全部写静态类型；缩进用 Tab。
- 全部面向用户的文字用中文；代码注释用中文。
- 坐标：Y 向上，米；forward = (sinθ, 0, cosθ)，right = (−cosθ, 0, sinθ)，θ 增大为左转；节点 `rotation.y = heading`。
- 物理子步 `SUBSTEP = 1.0 / 120.0`；`INTRO_TIME = 3.2`；`COUNTDOWN_TIME = 3.6`；`GRAVITY = 25.0`；`KART_RADIUS = 1.0`；`MAX_NITROS = 2`。
- 显示时速 = m/s × 3.6 × 1.4。
- 不用 Ctrl 键（macOS 冲突）。
- 模型只用 Kenney CC0 包；字体只用 OFL（ZCOOL KuaiLe、Bungee）；音频全部由 `tools/gen_audio.py` 生成。
- 糖果色：墨蓝 #1B1F3B、阳光黄 #FFC93C、泡泡蓝 #3EC6FF、赛车红 #FF4D5E、薄荷绿 #45E3A6、云白 #F7FAFF。
- 项目根目录 `~/Workspaces/godot/kart-racer`；测试命令 `godot --headless --path . -s tests/run_tests.gd`（退出码 = 失败数）。
- 素材源（已下载）：`/private/tmp/claude-502/-Users-fants-Workspaces-godot-godot-test/a693acae-4408-47ee-a8a4-5c949e84eb02/scratchpad/kenney/`。

## Review Focus

1. **窗口尺寸与比例**（16:10 的 Mac 屏、带鱼屏、小窗口）：HUD 和菜单要按锚点自适应，不溢出、不被裁掉。→ Task 6、Task 10 截图检查时覆盖 1280×800、1920×1080、2560×1080 三种尺寸。
2. **暂停与失焦**（倒计时中按 Esc、比赛中切走窗口）：仿真停止，按键状态清空，不会卡住油门。→ Task 6 在 `RaceController` 里处理 `NOTIFICATION_APPLICATION_FOCUS_OUT`，测试用例模拟失焦后输入归零。
3. **跨状态按住的按键**（从菜单按住空格或 ↑ 进入比赛）：不会误放氮气，也不会误判起步加速。→ Task 3 的 `test_race.gd` 覆盖「倒计时开始前就按住 ↑」不触发起步加速、不算抢跑。
4. **掉帧与卡顿**（加载后第一帧 dt 很大）：dt 限幅，子步上限，车不能穿墙。→ Task 3 测试把 0.5 s 的 dt 喂进 `RaceSim.update`，车仍在护墙内。
5. **存档缺失、损坏或来自旧版本**：回退默认值，不崩溃。→ Task 13 的 `test_store.gd` 分别写入空文件、非法 JSON、缺字段 JSON 三种情况。

---

## 文件结构（锁定）

```
project.godot  README.md  .gitignore
assets/models/karts/        kart-oobi|oodi|ooli|oopi|oozi.glb, wheel-*.glb, debris-spoiler-a|b.glb, debris-bumper.glb, Textures/colormap.png
assets/models/characters/   character-{female,male}-{a..f}.glb, Textures/colormap.png
assets/models/racing/       Racing Kit 选用的 GLB
assets/models/nature/       Nature Kit 选用的 GLB
assets/models/city/         City Kit Commercial 的 GLB + Textures/colormap.png
assets/audio/sfx/*.ogg  assets/audio/music/*.ogg
assets/fonts/ZCOOLKuaiLe-Regular.ttf  assets/fonts/Bungee-Regular.ttf
assets/shaders/*.gdshader
src/autoload/game.gd  store.gd  audio_manager.gd
src/data/karts_data.gd  tracks_data.gd  themes_data.gd  items_data.gd
src/sim/mathx.gd  track_data.gd  track_proj.gd  terrain_data.gd  kart_input.gd  kart_sim.gd
        ai_driver.gd  item_system.gd  race_sim.gd  replay_recorder.gd
src/view/race_world.gd  track_mesh.gd  terrain_mesh.gd  environment_factory.gd  scenery.gd
         kart_model.gd  kart_view.gd  item_view.gd  effects.gd  skid_marks.gd  camera_rig.gd
         tv_cameras.gd  ghost_view.gd  screen_fx.gd
src/race/race_controller.gd  player_input.gd  event_router.gd  replay_player.gd
src/ui/hud/hud.gd  minimap.gd  speedometer.gd
src/ui/menus/menu_root.gd  title_screen.gd  main_menu.gd  setup_screen.gd  garage_stage.gd
             settings_panel.gd  pause_menu.gd  results_screen.gd  podium_stage.gd  records_screen.gd
             help_screen.gd  loading_screen.gd  gp_standings.gd  replay_hud.gd
src/ui/theme/ui_theme.gd（代码生成 Theme）  widgets.gd（通用控件工厂）
scenes/main.tscn（入口，只挂 Main 节点）
tests/run_tests.gd  test_util.gd  test_track.gd  test_race.gd  test_items.gd  test_replay.gd  test_store.gd
tests/tools/sim_race.gd  handling.gd  screenshot.gd
tools/gen_audio.py
```

场景全部由代码搭建，`.tscn` 只保留入口。原因：代码生成的节点树更容易在任务之间保持接口一致，也方便测试。

---

## 共享接口（所有任务以此为准）

### 数据层 `src/data`

```gdscript
class_name KartsData
const KARTS: Array[Dictionary] = [...]      # {id, name, en, blurb, stats:{speed,accel,handling,drift,boost,weight}, look:{spoiler:"", wheels:"", scale:1.0, exhaust:false, bumper:false}}
# id: marshmallow 棉花糖 / bolt 闪电 / whirl 旋风 / rocket 火箭 / ironclad 铁甲
const CHARACTERS: Array[Dictionary] = [...] # {id, name, model, color}
# female-a 琪琪 / female-b 小桃 / female-c 花婆婆 / female-d 安娜 / female-e 小雪 / female-f 露露
# male-a 阿飞 / male-b 大熊 / male-c 警长 / male-d 金老板 / male-e 博士 / male-f 小虎
const PAINTS: Array[Dictionary] = [...]     # {id, name, model, color}
# oobi 葡萄紫 / oodi 樱桃粉 / ooli 阳光黄 / oopi 薄荷青 / oozi 奶茶米
const DIFFICULTIES: Dictionary = {...}      # easy/normal/hard，字段同参考版 + draft_skill
const STAT_LABELS: Array = [["speed","极速"],["accel","加速"],["handling","操控"],["drift","漂移"],["boost","氮气"],["weight","重量"]]
static func kart_params(stats: Dictionary) -> Dictionary   # 公式同参考版 kartParams，键为 snake_case
static func kart_by_id(id: String) -> Dictionary
static func character_by_id(id: String) -> Dictionary
static func paint_by_id(id: String) -> Dictionary

class_name TracksData
const TRACKS: Array[Dictionary] = [...]     # {id,name,en,blurb,difficulty,theme,half_width,shoulder,scale,grip,terrain:"follow"|"flat",points:[[x,z,y],...],ramps:[{at,len,height}],boost_pads:[{at,lateral}],item_rows:[...],music,cup}
# id: village / desert / snow / forest / circuit / city
const CUPS: Array[Dictionary] = [{id="star",name="新星杯",tracks=["village","desert","snow"]},{id="gale",name="疾风杯",tracks=["forest","circuit","city"]}]
static func track_by_id(id: String) -> Dictionary

class_name ThemesData
const THEMES: Dictionary = {...}            # 键为主题 id；字段同参考版 THEMES（颜色用 Color）+ weather:"none"|"snow"|"leaves"|"dust"|"embers" + time:"day"|"sunset"|"night"

class_name ItemsData
const ITEMS: Dictionary = {...}             # nitro missile water banana shield cloud magnet thunder ufo water_fly → {name,color,glyph,desc}
const ITEM_WEIGHTS: Dictionary = {first={...}, middle={...}, last={...}}
static func weights_for(rank_frac: float) -> Dictionary
```

### 仿真层 `src/sim`

```gdscript
class_name MathX   # 静态函数：damp(cur,target,rate,dt) approach(cur,target,max_delta) wrap_angle(a) damp_angle(cur,target,rate,dt)
                   # weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String   format_time(t: float, digits:=3) -> String

class_name TrackProj extends RefCounted   # idx:int t:float dist2:float s:float lateral:float nx nz tx tz road_y y:float

class_name TrackData extends RefCounted
const SAMPLE_SPACING := 2.0
static func build(def: Dictionary) -> TrackData
var def: Dictionary; var id: String; var theme: Dictionary; var grip: float
var n: int; var spacing: float; var length: float; var half_width: float; var shoulder: float; var wall_offset: float
var px, py, pz, tx, tz, nx, nz, curv: PackedFloat32Array
var bounds: Dictionary          # min_x max_x min_z max_z min_y max_y
var ramps: Array[Dictionary]    # {s, len_s, height, len}
var boost_pads: Array[Dictionary]  # {s, lateral, half_len_s, half_width, len}
var item_boxes: Array[Dictionary]  # {s, lateral, pos: Vector3}
var grid: Array[Dictionary]     # {pos: Vector3, heading, s, lateral}
var racing_line, rl_curv, rl_x, rl_z: PackedFloat32Array
func wrap_s(s: float) -> float
func point_at(s: float, lateral := 0.0) -> Vector3
func heading_at(s: float) -> float
func center_y(s: float) -> float
func ramp_height(s: float, lateral: float) -> float
func nearest(x: float, z: float, max_dist := 60.0) -> Dictionary   # {} 或 {d, idx, y}
func nearest_all(x: float, z: float, max_dist := 30.0) -> Array[Dictionary]
func project(x: float, y: float, z: float, hint: int, out: TrackProj) -> TrackProj
static func stats(track: TrackData) -> Dictionary   # 同参考版 trackStats

class_name TerrainData extends RefCounted
static func create(track: TrackData, seed := 11) -> TerrainData
var bounds: Dictionary; var flat: bool
func height_at(x: float, z: float) -> float

class_name KartInput extends RefCounted
var throttle := 0.0; var brake := 0.0; var steer := 0.0; var drift := false; var use := false
var throttle_pressed := false; var use_pressed := false; var swap_pressed := false; var respawn_pressed := false
func copy_from(o: KartInput, keep_edges := true) -> void   # 边沿取或，直到被子步消费
func clear_edges() -> void

class_name KartSim extends RefCounted
# 字段：参考版 Kart 全部字段的 snake_case 版本，另加：
#   prev_x prev_y prev_z prev_heading prev_visual_drift（插值用）、draft_time（尾流累计）、ufo（飞碟剩余时间）
#   kart_def character paint: Dictionary、speed_mul、auto_instant、instant_ready（小喷窗口打开的当帧为 true）
func _init(index: int, name: String, is_player: bool, kart_def: Dictionary, character: Dictionary, paint: Dictionary) -> void
func reset(slot: Dictionary) -> void
func is_disabled() -> bool
func is_boosting() -> bool
func add_boost(time: float, power: float, kind: String) -> void   # kind: nitro instant pad start magnet draft
func end_drift(events: Array, allow_instant := true) -> void
func trigger_instant(events: Array) -> void
func use_nitro(events: Array) -> void
func apply_hit(kind: String, events: Array, source: KartSim = null) -> bool   # spin flip bubble dizzy
func respawn(track: TrackData, events: Array) -> void
func step(ctx: Dictionary) -> void   # ctx: {track, dt, events, locked, speed_mul, item_mode, time, race}
func charge_gauge(gain: float, events: Array) -> void
func snapshot_prev() -> void          # 每个子步开始时保存 prev_*

class_name AIDriver extends RefCounted
func _init(kart: KartSim, diff: Dictionary, seed: int, autopilot := false) -> void
func update(dt: float, race: RaceSim) -> void

class_name ItemSystem extends RefCounted
var boxes, missiles, water_bombs, water_zones, bananas, water_flies: Array[Dictionary]
func _init(race: RaceSim) -> void
func update(dt: float) -> void
func use(k: KartSim) -> void
func hazard_ahead(k: KartSim, range_s: float, lat_tol: float) -> Dictionary

class_name RaceSim extends RefCounted
const SUBSTEP := 1.0 / 120.0
const INTRO_TIME := 3.2
const COUNTDOWN_TIME := 3.6
# opts: {track: TrackData, mode:"speed"|"item"|"time", laps:int, difficulty:"easy"|"normal"|"hard",
#        player:{kart_id, character_id, paint_id}, ai_count:int(默认7), seed:int, auto_instant:bool, all_ai:bool, skip_intro:bool,
#        ghost:Dictionary(可选)}
func _init(opts: Dictionary) -> void
var track: TrackData; var mode: String; var item_mode: bool; var laps: int; var diff: Dictionary
var rng: RandomNumberGenerator; var events: Array[Dictionary]; var time: float; var clock: float
var phase: String   # intro countdown racing finished
var phase_time: float; var countdown: float; var karts: Array[KartSim]; var player: KartSim; var ranking: Array[KartSim]
var items: ItemSystem  # 非道具赛为 null
var alpha: float       # 插值系数 = accumulator / SUBSTEP
var ghost_rec: PackedFloat32Array
var recorder: ReplayRecorder
func update(dt: float, player_input: KartInput) -> void
func skip_intro() -> void
func is_locked() -> bool
func kart_ahead(k: KartSim) -> KartSim
func kart_behind(k: KartSim) -> KartSim
func gap_meters(a: KartSim, b: KartSim) -> float
func results() -> Array[Dictionary]   # {kart, time, estimated, best_lap, rank}
func all_finished() -> bool
```

**事件**（`race.events` 中的 Dictionary，`type` 为 snake_case）：
`countdown{value}` `go` `start_boost{kart}` `false_start{kart}` `nitro{kart}` `instant_ready{kart}` `instant_boost{kart}` `boost_pad{kart}` `draft{kart}` `gauge_full{kart}` `drift_start{kart}` `wall_hit{kart,strength,side}` `kart_hit{a,b,strength,pos}` `land{kart,strength}` `item_box{kart,box}` `item_get{kart,item}` `item_use{kart,item}` `item_swap{kart}` `missile_launch{kart,target,missile}` `explosion{pos,kart,blocked}` `water_throw{kart}` `water_splash{pos,zone}` `bubble{kart}` `banana_drop{kart}` `banana_hit{kart,pos,blocked}` `hit{kart,kind,source}` `shield{kart}` `shield_block{kart}` `cloud{kart,source}` `thunder{kart}` `magnet{kart,target}` `ufo{kart,target}` `water_fly_launch{kart,target,fly}` `lap{kart,lap,time,final}` `finish{kart,time}` `respawn{kart}`

### 表现层 `src/view`

```gdscript
class_name KartModel extends Node3D     # 纯外观，车库、颁奖台、回放、幽灵车都复用
static func create(kart_id: String, character_id: String, paint_id: String) -> KartModel
func set_wheel_state(steer_angle: float, spin_delta: float) -> void
func set_body_pose(roll: float, pitch: float, drift_yaw: float, bounce: float) -> void
func set_driver_lean(lean: float) -> void
func rear_local(side: int) -> Vector3   # 后轮着地点（本地坐标），side -1 左 / 1 右
func exhaust_local(i: int) -> Vector3
func set_ghost(on: bool) -> void

class_name KartView extends Node3D
func setup(kart: KartSim, opts: Dictionary) -> void   # opts: {show_name, night, engine_audio}
func update_view(dt: float, time: float, alpha: float, cam_pos: Vector3) -> void
func rear_world(side: int) -> Vector3
func exhaust_world(i: int) -> Vector3

class_name Effects extends Node3D
func setup(quality: String, theme: Dictionary) -> void
func burst(kind: String, pos: Vector3, opts := {}) -> void
# kind: boost wall kart land shards explosion splash banana shield thunder respawn confetti instant spark_hit
func smoke(pos: Vector3, vel: Vector3, scale := 1.0) -> void
func drift_spark(pos: Vector3, tier: int) -> void   # tier 0 白 / 1 蓝
func flame(pos: Vector3, dir: Vector3, kind: String) -> void   # nitro instant pad start draft
func dust(pos: Vector3, vel: Vector3) -> void
func wind(pos: Vector3, dir: Vector3) -> void
func rate_count(key: String, rate: float, dt: float) -> int
var skids: SkidMarks   # add(id: int, pos: Vector3, dir: Vector3, width: float, on: bool)

class_name ItemView extends Node3D
func setup(track: TrackData) -> void
func update_view(dt: float, time: float, items: ItemSystem, effects: Effects) -> void

class_name CameraRig extends RefCounted
func _init(cam: Camera3D) -> void
var far := true
func chase(k: KartSim, dt: float, alpha: float) -> void
func intro(track: TrackData, k: KartSim, u: float, dt: float) -> void
func orbit(k: KartSim, time: float, dt: float) -> void
func shake(amount: float) -> void

class_name RaceWorld extends Node3D
func build(track: TrackData, terrain: TerrainData, quality: String, mode: String) -> void
func update_view(dt: float, time: float, cam: Camera3D) -> void
```

### 自动加载

```gdscript
# Store（store.gd）
var settings: Dictionary  # music sfx quality fullscreen vsync camera auto_instant show_fps muted
var selection: Dictionary # mode track_id character_id kart_id paint_id difficulty laps gp_rule
func save_settings(patch: Dictionary) -> void
func save_selection(patch: Dictionary) -> void
func record(track_id: String, mode: String) -> Dictionary
func submit(track_id: String, mode: String, laps: int, total: float, best_lap: float, ghost: Dictionary) -> Dictionary  # {new_best_total,new_best_lap}
func ghost(track_id: String) -> Dictionary
func submit_gp(cup_id: String, rank: int, points: int) -> bool

# AudioMgr（audio_manager.gd）
func play(name: String, opts := {}) -> void           # opts: volume pitch pan strength
func play_at(name: String, pos: Vector3, listener: Transform3D, opts := {}) -> void   # 距离衰减 + 声像
func play_music(name: String, fade := 0.8) -> void    # menu village desert snow forest circuit city results
func stop_music(fade := 0.5) -> void
func set_music_tempo(scale: float) -> void
func set_paused(p: bool) -> void
func set_volumes(music: float, sfx: float) -> void
func set_muted(m: bool) -> void
func update_engine(p: Dictionary) -> void   # speed01 throttle boosting drifting drift_intensity airborne offroad surface
func stop_engine() -> void
func make_engine_3d() -> AudioStreamPlayer3D

# Game（game.gd）
func goto_title() -> void
func goto_menu(screen := "main") -> void
func start_race(sel: Dictionary) -> void
func start_gp(cup_id: String, sel: Dictionary) -> void
func start_replay(replay: Dictionary) -> void
```

音效名：`engine_loop drift_loop gauge_full nitro instant_boost instant_ready start_boost false_start boost_pad draft wall_hit kart_hit land countdown go lap final_lap finish win lose new_record item_roll item_get item_use missile_launch missile_lock explosion water_throw water_splash bubble banana spin shield shield_block cloud thunder magnet ufo water_fly respawn wrong_way ui_click ui_hover ui_back ui_confirm ui_pause`

---

## 任务

### Task 1：工程骨架与素材

**Files:** Create `project.godot` `.gitignore` `scenes/main.tscn` `src/autoload/{game,store,audio_manager}.gd`（桩）`tests/run_tests.gd` `tests/test_util.gd` `assets/**`

- [ ] 从素材目录拷贝：karts（5 个 kart GLB、wheel-default/racing/dark/truck、debris-spoiler-a/b、debris-bumper、Textures）、characters（12 个角色 + Textures）、racing（bannerTowerGreen/Red barrierRed/White/Wall billboard* flag* grandStand* lightPost* overhead* pitsGarage* pitsOffice* tent* treeLarge/Small pylon rail railDouble radarEquipment）、nature（树/松/棕榈/仙人掌/岩石/石头/花草/蘑菇/原木/树桩/桥/悬崖/栅栏/帐篷/雕像）、city（全部）。
- [ ] 下载字体到 `assets/fonts/`。
- [ ] `project.godot`：名称「疾风卡丁 GALE KART」、forward_plus、窗口 1600×900、stretch canvas_items + expand、`physics/common/physics_ticks_per_second` 保持默认（仿真不用物理引擎）、输入映射（accelerate brake steer_left steer_right drift use_item swap_item respawn camera pause hide_hud mute fullscreen，键盘 + 手柄）、自动加载 Game Store AudioMgr、默认字体 ZCOOL KuaiLe。
- [ ] `tests/run_tests.gd`：`extends SceneTree`，依次加载 `tests/test_*.gd`（每个是 `RefCounted`，提供 `run(t: TestUtil)`），`TestUtil.check(cond, msg)` 统计失败，结束时打印汇总并 `quit(failures)`。
- [ ] 验证：`godot --headless --path . --import` 无错误；`godot --headless --path . -s tests/run_tests.gd` 输出「0 failures」。
- [ ] Commit：`chore: 工程骨架、素材、输入映射、测试框架`

### Task 2：数据层 + 赛道仿真

**Files:** Create `src/data/*.gd` `src/sim/{mathx,track_proj,track_data,terrain_data}.gd` `tests/test_track.gd`

- [ ] 写 `tests/test_track.gd`：对 `TracksData.TRACKS` 的每条赛道 `TrackData.build()`，断言：n ≥ 200；首尾闭合（点 0 到点 n−1 的距离 < 1.5 × spacing）；`stats().min_radius ≥ wall_offset + 2`；`stats().min_sep ≥ wall_offset × 2 + 4`（立交高度差 ≥ 6 m 除外）；`max_slope ≤ 0.18`；8 个发车格和所有道具箱 `abs(lateral) < half_width`；跳台之间、跳台与加速带之间弧长间隔 ≥ 30 m；`project()` 对 `point_at(s, lat)` 能还原 s（误差 < 0.05 × n 取模）和 lateral（误差 < 0.05）。
- [ ] 运行，确认失败（类不存在）。
- [ ] 移植 `math.js`（用 Godot 的 `RandomNumberGenerator`，噪声用 `FastNoiseLite`）、`track.js`（Catmull-Rom centripetal 自己实现：弧长表 6000 段，按弧长均匀采样）、`terrain.js`、`data/karts.js`、`data/tracks.js`；数据补全 12 名车手、5 种涂装、10 种道具、6 个主题（forest、circuit 为新主题），新赛道 forest、circuit 的控制点。
- [ ] 新赛道设计要求：forest 约 1.3 km，海拔落差 ≥ 12 m，有一处 len 14 / height 3.2 的大跳台，跳台落点之后是一段直道（在视觉上飞越河流，河流由 scenery 放置）；circuit 约 1.5 km，含 2 条 ≥ 250 m 的长直道、1 个发卡弯（半径 ≈ wall_offset + 6），平坦（terrain "follow"，y 全为 0~2）。
- [ ] 运行测试直到全部通过；另写 `tests/tools/track_stats.gd` 打印每条赛道的长度、最小半径、最小间距。
- [ ] Commit：`feat(sim): 数据层与赛道仿真`

### Task 3：赛车物理 + 比赛流程 + AI

**Files:** Create `src/sim/{kart_input,kart_sim,ai_driver,race_sim}.gd` `tests/test_race.gd` `tests/tools/{sim_race,handling}.gd`

- [ ] 写 `tests/test_race.gd`：
  - 每条赛道 `RaceSim.new({track, mode:"speed", laps:3, difficulty:"hard", all_ai:true, skip_intro:true, seed:7})`，以 1/60 s 步进最多 900 s 仿真时间：8 辆车全部 finished；每辆车任意 3 s 窗口内至少前进 5 m（不卡死）；单圈时间在 `track.length / 36` 到 `track.length / 16` 秒之间。
  - 冒烟：玩家直线全油门 3 s 后速度 > 20 m/s；按住漂移 + 转向 2 s 后 gauge > 0.3 或 nitros ≥ 1；nitros=1 时按 use 后 `is_boosting()` 且 boost_kind == "nitro"；漂移 0.5 s 后松开，窗口内 throttle_pressed 触发 instant_boost 事件。
  - 起步：倒计时开始前就按住 ↑（throttle=1、throttle_pressed 只在第一帧）→ 不触发 start_boost；在 countdown ∈ (0, 0.3] 时首次按下 → go 后 boost_kind == "start"；在 countdown > 0.35 时按下 → false_start 事件。
  - 尾流：玩家以相同速度跟在 AI 正后方 6 m 处 1.2 s → 触发 draft 事件并且 boost_kind == "draft"。
  - 大 dt：把 dt = 0.5 喂给 `update()`，所有车 `abs(lateral) ≤ wall_offset`。
- [ ] 运行，确认失败。
- [ ] 移植 `kart.js`、`ai.js`、`race.js`（保持数值一致），并加入：`snapshot_prev()`、`alpha` 插值系数、尾流（前方 3–14 m、横向差 < 2.2 m、速度 > 15 m/s 时累计 draft_time，满 1.0 s 触发 add_boost(1.2, 0.12, "draft")，冷却 2 s）、`instant_ready` 事件、`false_start` 事件（抢跑：起步时原地打滑 0.8 s，vmax × 0.3）、困难档 AI 在出弯时小喷（概率 = diff.line × 0.5）、飞碟状态 `ufo`（vmax × 0.85，不能使用道具）。
- [ ] 写 `tests/tools/sim_race.gd`（打印每条赛道的完赛表）和 `handling.gd`（0→100 km/h 显示速度的时间、极速、最小转弯半径、漂移 2 s 集气量）。
- [ ] 运行测试直到全部通过。
- [ ] Commit：`feat(sim): 赛车物理、比赛流程、AI`

### Task 4：道具系统

**Files:** Create `src/sim/item_system.gd` `tests/test_items.gd`

- [ ] 写 `tests/test_items.gd`：权重表每档之和 > 0 且只含已定义道具；第一名永远抽不到 thunder 和 water_fly；拾取道具箱后 items.size() == 1 且 item_roll > 0，箱子 2.6 s 后恢复；导弹命中前车 → flip > 0；护盾期间被导弹命中 → shield_block 事件且 flip == 0；香蕉命中 → spin > 0；水柱困住 → bubble > 0，且丢出者免疫；乌云落到第一名；磁铁生效；雷暴只影响排名更靠前的车；飞碟让第一名 ufo > 0 且 use_pressed 无效；水苍蝇追上第一名 → bubble > 0；8 辆 AI 在道具赛里跑完 3 圈。
- [ ] 运行，确认失败。
- [ ] 移植 `items.js`，新增 ufo（立即作用：目标 = 第一名（自己是第一名时为第二名），ufo = 3.0 s，事件 `ufo`）和 water_fly（实体：沿赛道以 70 m/s 追踪第一名，逻辑同导弹，命中时 apply_hit("bubble")，寿命 8 s）；权重表加入 ufo（middle 6、last 10）、water_fly（middle 4、last 10）。AI 道具策略：ufo / water_fly 拿到后 0.8 s 使用。
- [ ] 运行测试直到全部通过。
- [ ] Commit：`feat(sim): 道具系统（10 种道具）`

### Task 5：基础表现（能开车）

**Files:** Create `src/view/{track_mesh,terrain_mesh,environment_factory,kart_model,kart_view,camera_rig,race_world}.gd` `src/race/{race_controller,player_input}.gd` `assets/shaders/{road,terrain,wall}.gdshader` `tests/tools/screenshot.gd`

- [ ] `TrackMesh`：路面条带（每个采样点左右各 1 个顶点，UV：u 横向 0..1，v 为累计米数 / 10）、路肩条带、弯道路缘（|curv| > 0.012 的段落，红白 2 m 交替）、护墙（按 theme.wall.style 生成：fence 白柱 + 蓝横板；stone 石块；ice 半透明冰；neon 发光条；tire 轮胎墙）、起终点格子、加速带箭头（发光着色器，箭头向前滚动）、跳台斜面（黄黑 V 字）、立交桥柱（py > 地形高 + 3 处每 12 m 一根）。
- [ ] `TerrainMesh`：按 TerrainData 生成网格（高画质 4 m 格、中 6 m、低 8 m），顶点色按高度与噪声混合 ground.base / alt / far；外圈加 4 km 大平面防止穿帮。
- [ ] `EnvironmentFactory.create(theme, quality)`：WorldEnvironment（天空渐变着色器用 theme.sky、雾、AgX 色调映射、辉光、高画质开 SSAO）、DirectionalLight3D（阴影，PSSM 4 split，最大距离 220 m）。
- [ ] `KartModel`：按 5.3 节组装 Kenney 卡丁车 + 角色（隐藏原车手 `character` 网格，Mini Character 播放 `drive` 动画，挂到座椅位置，缩放 1.15），整体缩放 1.55；车型外观：spoiler / wheels / scale / exhaust / bumper。
- [ ] `KartView`：插值位置朝向；车身侧倾 = −lat_accel × 0.02（限幅 0.12 rad），俯仰 = −long_accel × 0.012 + slope；落地回弹（弹簧阻尼）；漂移甩角 = visual_drift × 0.55 rad；前轮转角 = steer × 0.45；轮子转速 = forward_speed / 0.33；状态动画：spin 旋转、flip 翻滚、bubble 上浮、invuln 闪烁；AI 头顶 Label3D 名牌。
- [ ] `CameraRig`：移植 cameraRig.js，并加入插值、落地和碰撞震动。
- [ ] `PlayerInput`：从 InputMap 读取 → KartInput；手柄转向死区 0.12、指数 1.4；失焦时清空；手柄震动 `vibrate(weak, strong, dur)`。
- [ ] `RaceController`：`start(sel)` 构建 TrackData → TerrainData → RaceWorld → RaceSim → KartViews → CameraRig；`_process` 调 `race.update(dt, input)`，更新视图；Esc 暂停（此任务先做最简暂停）。
- [ ] `tests/tools/screenshot.gd`：`godot --path . -s tests/tools/screenshot.gd -- --track=village --t=6 --out=/path.png` 以 all_ai 模式跑 t 秒后截图。
- [ ] 验证：6 条赛道各截图一张，人工检查赛道、护墙、地形、车模、光照；比赛视角下实测帧率。
- [ ] Commit：`feat(view): 赛道、地形、赛车模型、相机，可以开车`

### Task 6：HUD 与比赛流程

**Files:** Create `src/ui/hud/{hud,minimap,speedometer}.gd` `src/race/event_router.gd` `src/ui/theme/{ui_theme,widgets}.gd`；Modify `src/race/race_controller.gd`

- [ ] `UiTheme.build() -> Theme`：糖果贴纸风（按钮圆角 18、2.5 px 墨蓝描边、投影、悬停放大）、字体（标题 ZCOOL KuaiLe，数字 Bungee）。`Widgets`：`panel()` `button(text)` `stat_bar(label, value)` `badge(text, gold)`。
- [ ] HUD：按规格第 11 节布局，锚点自适应；`setup(race)` `update_view(dt, race)` `big(text, opts)` `sub(text)` `flash()` `add_lap_time(lap, time, best)` `show_instant_cue(on)` `set_hud_visible(v)`；道具轮盘动画；逆行警告；导弹锁定红边；乌云遮挡；计时赛幽灵差距。
- [ ] `EventRouter.handle(events, ctx)`：事件 → HUD 文字、音效、特效、相机震动、手柄震动（映射同参考版 main.js handleEvents，外加新事件）。
- [ ] 比赛流程：开场航拍（按任意键跳过，跳过这一下不计入起步判定）→ 倒计时 → 比赛 → 冲线（FINISH、彩带、环绕相机）→ 3.4 s 后通知 Game 进入结算。
- [ ] 失焦暂停：`NOTIFICATION_APPLICATION_FOCUS_OUT` 时自动暂停并清空输入；测试：`tests/test_race.gd` 增加用例——PlayerInput 收到失焦后 throttle == 0。
- [ ] 截图检查 1280×800、1920×1080、2560×1080 三种尺寸下的 HUD。
- [ ] Commit：`feat(ui): HUD 与比赛流程`

### Task 7：音频（可并行）

**Files:** Create `tools/gen_audio.py` `assets/audio/**` `src/autoload/audio_manager.gd`

- [ ] `gen_audio.py`：numpy 合成 44.1 kHz 单声道，写 WAV 后用 ffmpeg 转 OGG（q 5）。音效清单见「共享接口」；音色参考 `audio/audio.js`。`engine_loop` 为 1 s 无缝循环（基频 55 Hz 锯齿 + 次谐波 + 噪声，运行时靠 pitch_scale 0.6–2.4 变化）；`drift_loop` 为 1 s 无缝循环的轮胎尖叫噪声。
- [ ] BGM 8 首（参考 `audio/music.js` 的调式与节奏）：每首 32–64 小节、无缝循环（首尾交叉淡化），芯片方波主旋律 + 三角波贝斯 + 噪声鼓 + 和弦垫，按主题调整 BPM 和调式；导入时设置 loop。
- [ ] `AudioMgr`：总线 Master / Music / SFX；SFX 播放器池 24 个；`play_at` 按距离衰减（range 默认 90 m）并按相机右向量计算声像；引擎：玩家两层（engine_loop 音高随速度变化，漂移时混入 drift_loop），AI 用 `make_engine_3d()`（AudioStreamPlayer3D，unit_size 6，max_distance 70）。
- [ ] 验证：运行一个脚本依次播放全部音效并打印时长；随机抽听 5 个（用 ffmpeg 生成波形图检查不削波）。
- [ ] Commit：`feat(audio): 合成音效与 BGM，音频管理器`

### Task 8：主题环境与场景物件（可并行）

**Files:** Create `src/view/scenery.gd` `assets/shaders/{snow_cover,water,sky_gradient}.gdshader`；Modify `src/view/environment_factory.gd`

- [ ] `Scenery.build(track, terrain, theme, quality, seed) -> Node3D`：按主题摆放 Kenney 物件，用 MultiMeshInstance3D 批量绘制（同一模型的所有实例一个 MultiMesh）；摆放规则：离赛道中心线距离 > wall_offset + 物件半径 + 2，贴地（height_at），随机旋转和缩放，密度按画质（低 0.4 / 中 0.7 / 高 1.0）。
- [ ] 主题物件：village（树、花、灌木、栅栏、风车〔程序化：塔身 + 4 叶旋转〕、红顶小屋〔程序化〕、干草）；desert（仙人掌、棕榈、岩石、方尖碑、金字塔〔程序化〕、骆驼色帐篷）；snow（松树 + 积雪着色器、雪人〔程序化〕、冰晶〔发光多面体〕、飘雪粒子）；forest（巨型松/橡树、峭壁、原木、蘑菇、瀑布〔滚动纹理平面 + 水雾粒子〕、河流水面、木桥护栏、萤火虫粒子）；circuit（看台 grandStand*、维修区 pits*、旗帜、广告牌、横幅塔、灯柱、轮胎墙、夕阳）；city（City Kit 楼宇〔夜间窗户自发光：着色器按 UV 随机点亮〕、霓虹招牌〔程序化发光条〕、路灯 OmniLight3D ≤ 24 盏且按距离开关、体积雾）。
- [ ] 起终点门架：circuit 用 overheadLights，其他主题用程序化拱门 + "START" 横幅（Label3D）。
- [ ] 验证：每个主题截图（开场全景 + 车后视角），帧率 ≥ 60。
- [ ] Commit：`feat(view): 主题环境与场景物件`

### Task 9：特效与道具表现（可并行）

**Files:** Create `src/view/{effects,skid_marks,item_view,screen_fx}.gd` `assets/shaders/{speed_lines,radial_blur,item_box,shield,bubble,cloud}.gdshader`

- [ ] `Effects`：每种粒子一个 GPUParticles3D（emitting = false，用 `emit_particle()` 在任意位置发射），实现「共享接口」里的全部 API；burst 各类型的外观参考 `view/effects.js`。
- [ ] `SkidMarks`：环形缓冲 ArrayMesh（每条胎痕最多 600 段，淡出）。
- [ ] `ItemView`：道具箱（旋转半透明彩虹立方 + 「?」）、导弹（火箭 + 尾焰）、水炸弹（抛物线水球）、水柱（圆柱水体动画）、香蕉、水苍蝇（带翅膀的水滴）、飞碟（碟形 + 光束，悬停在目标头顶）、乌云（体积云团 + 雨丝，跟随目标）、护盾（金色泡泡）、磁铁（吸引线）、雷暴（闪电）。
- [ ] `ScreenFx`（CanvasLayer + 全屏 ColorRect 着色器）：速度线（强度 = 速度与加速）、氮气径向模糊、导弹锁定红边、乌云遮挡、水泡时画面泛蓝。
- [ ] 验证：写 `tests/tools/fx_gallery.gd`，依次触发所有 burst 和道具实体并截图。
- [ ] Commit：`feat(view): 粒子特效、胎痕、道具表现、屏幕效果`

### Task 10：菜单与车库（可并行）

**Files:** Create `src/ui/menus/*.gd`；Modify `src/autoload/game.gd` `scenes/main.tscn`

- [ ] `MenuRoot`：管理屏幕栈和转场（淡入 + 滑动）；背景是 `GarageStage`（3D：转台上的卡丁车、柔光、慢速环绕相机）。
- [ ] 标题页、主菜单、赛前设置（模式分段按钮；赛道卡片：缩略图〔用赛道采样点画的线稿〕、名称、难度星、最佳纪录；车手网格；赛车卡片 + 六维属性条；涂装色块；难度；圈数）、设置、操作说明、最佳纪录、加载页（进度条 + 随机小贴士）、暂停菜单、结算页（`PodiumStage`：3D 颁奖台上前三名车，车手播放 `emote-yes` / `idle`；成绩表；按钮：精彩回放 / 再来一局 / 下一赛道 / 返回菜单）、大奖赛积分榜。
- [ ] 键盘、手柄、鼠标都能操作；焦点有明显高亮；Esc / B 返回。
- [ ] 截图：每个页面在 1920×1080 和 1280×800 下各一张。
- [ ] Commit：`feat(ui): 菜单、车库、结算颁奖台`

### Task 11：集成

**Files:** Modify `src/race/race_controller.gd` `src/race/event_router.gd` `src/autoload/game.gd`

- [ ] 把 Task 7–10 的产出接入比赛：音效和引擎声、场景、特效和道具表现、屏幕效果、菜单流程（Game：标题 → 主菜单 → 设置 → 加载 → 比赛 → 结算 → 回放 / 再来 / 下一条 / 返回）。
- [ ] 全流程手动跑一遍（脚本驱动：all_ai 模式 + 自动点击按钮），截图每个阶段。
- [ ] Commit：`feat: 全流程集成`

### Task 12：精彩回放

**Files:** Create `src/sim/replay_recorder.gd` `src/race/replay_player.gd` `src/view/tv_cameras.gd` `src/ui/menus/replay_hud.gd` `tests/test_replay.gd`

- [ ] 写 `tests/test_replay.gd`：跑一场 all_ai 比赛并录制；帧数 ≈ 比赛时长 × 30（误差 ±2）；`sample(t)` 在帧之间线性插值，角度走最短弧；事件时间单调递增。
- [ ] `ReplayRecorder`：每 1/30 s 记录每辆车 `[x,y,z,heading,visual_drift,steer,speed,flags,rank]`（flags 位：drifting、boosting、boost_kind 编码、on_ground、spin、flip、bubble、dizzy、shield、cloud、ufo、invuln、finished）和道具实体快照；离散事件带时间戳。
- [ ] `ReplayPlayer`：用记录数据填充「回放用 KartSim」（只写字段、不跑物理），复用 KartView、ItemView、Effects、EventRouter（只触发特效和音效）；`TvCameras`：沿赛道每 60–90 m 放一个机位（路外侧 wall_offset + 6 m、高 3–8 m），选离焦点车最近且可见的机位，镜头平滑追踪并适度变焦；自动切镜（TV / 追尾 / 环绕，每 4–7 s）。
- [ ] 回放界面：1–4 切机位、←→ 换焦点车、空格暂停、[ ] 变速、H 隐藏界面、Esc 退出；左下角显示「REPLAY」与焦点车信息。
- [ ] Commit：`feat: 精彩回放`

### Task 13：大奖赛、计时赛、存档

**Files:** Modify `src/autoload/{game,store}.gd` `src/view/ghost_view.gd` `src/ui/menus/gp_standings.gd`；Create `tests/test_store.gd`

- [ ] 写 `tests/test_store.gd`：存档文件分别为空、非法 JSON、缺字段、字段类型错误时，`Store` 加载后等于默认值并且能正常 submit。
- [ ] Store 实现：`user://save.json`，版本号 1，所有读取做类型校验。
- [ ] 计时赛：幽灵车（10 Hz，存 3 圈最佳）、HUD 显示与幽灵的实时差距（按 progress 对齐）。
- [ ] 大奖赛：杯赛 3 场，积分、每场后积分榜、最终颁奖（杯赛奖杯）、纪录保存。
- [ ] Commit：`feat: 大奖赛、计时赛幽灵车、存档`

### Task 14：打磨与验收

- [ ] 手感调参：用 `handling.gd` 对比参考版数值；实际驾驶截图序列检查漂移角度、相机滞后、速度感。
- [ ] 画面调色：每个主题逐一截图对比，调整曝光、雾、辉光、饱和度。
- [ ] 性能：每条赛道「高」画质 30 s 平均帧率 / 最低帧率，低于 60 的地方做优化（MultiMesh、LOD、可见范围、阴影距离）。
- [ ] 全量测试通过；README（玩法、操作、内容、开发命令）；导出 macOS 应用（如导出模板可用）。
- [ ] Commit：`chore: 打磨、文档`
