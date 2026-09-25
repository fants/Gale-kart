extends Node
## 音频管理器：Music / SFX / Engine 三条总线，启动时预加载全部 OGG；
## 2D / 3D 音效播放器池、BGM 双播放器交叉淡化、玩家引擎声（引擎 + 漂移两层，越野时低通）。
## 所有公开函数在资源缺失、尚未进入场景树或 headless 下都安静降级，不报错。

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_NAMES: Array[String] = [
	"engine_loop", "drift_loop", "gauge_full", "nitro", "instant_boost", "instant_ready", "start_boost",
	"false_start", "boost_pad", "draft", "wall_hit", "kart_hit", "land", "countdown", "go", "lap",
	"final_lap", "finish", "win", "lose", "new_record", "item_roll", "item_get", "item_use",
	"missile_launch", "missile_lock", "explosion", "water_throw", "water_splash", "bubble", "banana",
	"spin", "shield", "shield_block", "cloud", "thunder", "magnet", "ufo", "water_fly", "respawn",
	"wrong_way", "ui_click", "ui_hover", "ui_back", "ui_confirm", "ui_pause",
]
const MUSIC_NAMES: Array[String] = ["menu", "village", "desert", "snow", "forest", "circuit", "city", "results"]
const LOOP_SFX: Array[String] = ["engine_loop", "drift_loop"]

## 音效文件都归一到 -1 dBFS，这里按用途拉开层次（dB，未列出的为 0）
const SFX_BASE_DB := {
	"ui_hover": -15.0, "ui_click": -9.0, "ui_back": -9.0, "ui_confirm": -8.0, "ui_pause": -8.0,
	"item_roll": -13.0, "item_get": -5.0, "item_use": -7.0, "missile_lock": -8.0, "gauge_full": -7.0,
	"instant_ready": -7.0, "draft": -6.0, "land": -4.0, "kart_hit": -3.0, "wall_hit": -2.0,
	"countdown": -4.0, "go": -3.0, "lap": -5.0, "final_lap": -4.0, "wrong_way": -6.0, "respawn": -6.0,
	"bubble": -6.0, "magnet": -6.0, "ufo": -6.0, "water_fly": -6.0, "shield": -5.0, "shield_block": -4.0,
	"cloud": -4.0, "banana": -4.0, "spin": -5.0, "water_throw": -5.0, "boost_pad": -3.0,
	"instant_boost": -3.0, "false_start": -4.0, "finish": -3.0, "lose": -3.0,
}

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_ENGINE := "Engine"
const POOL_2D := 24
const POOL_3D := 16
const REPEAT_GAP_MSEC := 30
const PAUSE_MUSIC_DB := -8.0
const SILENT_DB := -80.0
const DEFAULT_RANGE := 90.0
## 引擎与漂移层的基础音量（dB）
const ENGINE_BASE_DB := -8.0
const DRIFT_BASE_DB := -10.0
## 参数每秒趋近速率（指数平滑）
const ENGINE_SMOOTH := 10.0
const DRIFT_SMOOTH := 14.0
const OFFROAD_CUTOFF := 850.0
const OPEN_CUTOFF := 20000.0

var _inited := false
var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _warned: Dictionary = {}
var _last_play: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool3d_i := 0
var _paused_players: Array[Node] = []
var _engines_3d: Array[WeakRef] = []

var _music_players: Array[AudioStreamPlayer] = []
var _music_levels: Array[float] = [0.0, 0.0]
var _music_tweens: Array[Tween] = [null, null]
var _music_cur := 0
var _music_name := ""
var _music_tempo := 1.0

var _vol_music := 1.0
var _vol_sfx := 1.0
var _paused := false

var _engine: AudioStreamPlayer
var _drift: AudioStreamPlayer
var _lowpass: AudioEffectLowPassFilter
var _engine_on := false
var _engine_stopping := false
# 引擎参数：当前值每帧向目标值平滑
var _eng_pitch := 1.0
var _eng_pitch_t := 1.0
var _eng_vol := 0.0
var _eng_vol_t := 0.0
var _drift_vol := 0.0
var _drift_vol_t := 0.0
var _drift_pitch := 1.0
var _drift_pitch_t := 1.0
var _cutoff := OPEN_CUTOFF
var _cutoff_t := OPEN_CUTOFF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_init()


func _process(delta: float) -> void:
	if not _engine_on or _engine == null:
		return
	var k := 1.0 - exp(-ENGINE_SMOOTH * delta)
	var kd := 1.0 - exp(-DRIFT_SMOOTH * delta)
	_eng_pitch = lerpf(_eng_pitch, _eng_pitch_t, k)
	_eng_vol = lerpf(_eng_vol, _eng_vol_t, k)
	_drift_vol = lerpf(_drift_vol, _drift_vol_t, kd)
	_drift_pitch = lerpf(_drift_pitch, _drift_pitch_t, kd)
	_cutoff = exp(lerpf(log(_cutoff), log(_cutoff_t), k))
	_engine.pitch_scale = maxf(_eng_pitch, 0.05)
	_engine.volume_db = _lin_db(_eng_vol) + ENGINE_BASE_DB
	_drift.pitch_scale = maxf(_drift_pitch, 0.05)
	_drift.volume_db = _lin_db(_drift_vol) + DRIFT_BASE_DB
	if _lowpass:
		_lowpass.cutoff_hz = _cutoff
	if _engine_stopping and _eng_vol < 0.002 and _drift_vol < 0.002:
		_engine.stop()
		_drift.stop()
		_engine_on = false
		_engine_stopping = false


# ———————————————————————————————— 公开接口

## 播放 2D 音效。opts：volume（线性 0..1，默认 1）、pitch（默认 1）、strength（0..1，按强度调音量和音高）。
## pan 字段仅为兼容保留，2D 播放器不做声像；需要空间感请用 play_at。
func play(sfx_name: String, opts := {}) -> void:
	_ensure_init()
	if not is_inside_tree() or _pool.is_empty():
		return
	var stream := _get_sfx(sfx_name)
	if stream == null or _throttled(sfx_name):
		return
	var vp := _vol_pitch(sfx_name, opts)
	if vp.x <= 0.0001:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stop()
	p.stream = stream
	p.stream_paused = false
	p.volume_db = linear_to_db(vp.x) + float(SFX_BASE_DB.get(sfx_name, 0.0))
	p.pitch_scale = vp.y
	p.play()


## 在世界坐标 pos 播放 3D 音效（反平方衰减，声像由当前相机决定）。listener 用于距离剔除：超过 opts.range（默认 90 m）不播。
func play_at(sfx_name: String, pos: Vector3, listener: Transform3D, opts := {}) -> void:
	_ensure_init()
	if not is_inside_tree() or _pool3d.is_empty():
		return
	var range_m := maxf(_num(opts, "range", DEFAULT_RANGE), 1.0)
	var dist := pos.distance_to(listener.origin)
	if dist > range_m:
		return
	var viewport := get_viewport()
	if viewport == null or viewport.get_camera_3d() == null:
		# 没有 3D 相机时听不到 3D 声音：退化为按距离衰减的 2D 播放
		var o := opts.duplicate()
		o["volume"] = _num(opts, "volume", 1.0) / maxf(1.0, pow(dist / 8.0, 2.0))
		play(sfx_name, o)
		return
	var stream := _get_sfx(sfx_name)
	if stream == null or _throttled("3d:" + sfx_name):
		return
	var vp := _vol_pitch(sfx_name, opts)
	if vp.x <= 0.0001:
		return
	var p := _pool3d[_pool3d_i]
	_pool3d_i = (_pool3d_i + 1) % _pool3d.size()
	p.stop()
	p.stream = stream
	p.stream_paused = false
	p.max_distance = range_m
	p.volume_db = linear_to_db(vp.x) + float(SFX_BASE_DB.get(sfx_name, 0.0))
	p.pitch_scale = vp.y
	p.global_position = pos
	p.play()


## 切换 BGM：新旧两首交叉淡化 fade 秒；同名且正在播放时忽略。换曲时节奏复位为 1。
func play_music(music_name: String, fade := 0.8) -> void:
	_ensure_init()
	if not is_inside_tree() or _music_players.size() < 2:
		return
	if music_name == _music_name and _music_players[_music_cur].playing:
		return
	var stream: AudioStream = _music.get(music_name)
	if stream == null:
		_warn_once("music:" + music_name, "AudioMgr：找不到音乐 %s" % music_name)
		return
	_fade_music(_music_cur, 0.0, fade, true)
	_music_cur = 1 - _music_cur
	var p := _music_players[_music_cur]
	_music_name = music_name
	_music_tempo = 1.0
	p.stop()
	p.stream = stream
	p.pitch_scale = 1.0
	_set_music_level(0.0, _music_cur)
	p.play()
	_fade_music(_music_cur, 1.0, fade, false)


func stop_music(fade := 0.5) -> void:
	_ensure_init()
	_music_name = ""
	if not is_inside_tree():
		return
	for i in _music_players.size():
		if _music_players[i].playing:
			_fade_music(i, 0.0, fade, true)


## 调整 BGM 节奏（最后一圈 1.1），用 pitch_scale 实现。
func set_music_tempo(scale: float) -> void:
	_ensure_init()
	_music_tempo = clampf(scale, 0.5, 2.0)
	if _music_name != "" and _music_players.size() == 2:
		_music_players[_music_cur].pitch_scale = _music_tempo


## 暂停：暂停正在播放的音效与引擎声，音乐压低 8 dB；恢复时还原。暂停期间新播放的音效（菜单音）照常发声。
func set_paused(p: bool) -> void:
	_ensure_init()
	if p == _paused:
		return
	_paused = p
	if p:
		_paused_players.clear()
		for pl in _pool:
			_pause_player(pl)
		for pl in _pool3d:
			_pause_player(pl)
		for w in _engines_3d:
			var e := w.get_ref() as AudioStreamPlayer3D
			if e != null:
				_pause_player(e)
	else:
		for pl in _paused_players:
			if is_instance_valid(pl):
				pl.set("stream_paused", false)
		_paused_players.clear()
	if _engine_on:
		_engine.stream_paused = p
		_drift.stream_paused = p
	_apply_volumes()


## 音乐 / 音效音量，线性 0..1；0 时静音对应总线。
func set_volumes(music: float, sfx: float) -> void:
	_ensure_init()
	_vol_music = clampf(music, 0.0, 1.0)
	_vol_sfx = clampf(sfx, 0.0, 1.0)
	_apply_volumes()


func set_muted(m: bool) -> void:
	_ensure_init()
	AudioServer.set_bus_mute(0, m)


## 玩家引擎声。p：speed01（0..1.4）throttle（0..1）boosting drifting drift_intensity airborne offroad surface（"asphalt"|"ice"）。
## 第一次调用时开始循环播放；参数在 _process 里逐帧平滑。
func update_engine(p: Dictionary) -> void:
	_ensure_init()
	if not is_inside_tree() or _engine == null or _engine.stream == null:
		return
	var sp := clampf(_num(p, "speed01", 0.0), 0.0, 1.4)
	var th := clampf(_num(p, "throttle", 0.0), 0.0, 1.0)
	var boosting := _flag(p, "boosting")
	var air := _flag(p, "airborne")
	var offroad := _flag(p, "offroad")
	var di := clampf(_num(p, "drift_intensity", 0.0), 0.0, 1.0)
	var ice := str(p.get("surface", "asphalt")) == "ice"
	var pitch := 0.7 + sp * 1.3
	var vol := 0.5 + 0.35 * th + 0.15 * minf(sp, 1.0)
	if boosting:
		pitch += 0.15
		vol *= 1.12
	if air:
		pitch += 0.2
		vol *= 0.6
	if ice:
		pitch *= 1.04
		vol *= 0.85
	_eng_pitch_t = clampf(pitch, 0.6, 2.4)
	_eng_vol_t = vol
	var dv := 0.0
	if _flag(p, "drifting") and not air:
		dv = 0.3 + 0.7 * di
		if ice:
			dv *= 0.6
		if offroad:
			dv *= 0.35
	_drift_vol_t = dv
	_drift_pitch_t = (1.12 if ice else 1.0) + 0.08 * di
	_cutoff_t = OFFROAD_CUTOFF if offroad and not air else OPEN_CUTOFF
	_engine_stopping = false
	if not _engine_on:
		_engine_on = true
		_eng_pitch = _eng_pitch_t
		_eng_vol = 0.0
		_drift_pitch = _drift_pitch_t
		_drift_vol = 0.0
		_cutoff = _cutoff_t
		_engine.pitch_scale = _eng_pitch
		_engine.volume_db = SILENT_DB
		_engine.play()
		_engine.stream_paused = _paused
		if _drift.stream != null:
			_drift.pitch_scale = _drift_pitch
			_drift.volume_db = SILENT_DB
			_drift.play()
			_drift.stream_paused = _paused


## 引擎声淡出后停止。
func stop_engine() -> void:
	if not _engine_on:
		return
	_eng_vol_t = 0.0
	_drift_vol_t = 0.0
	_engine_stopping = true


## 给 AI 车用的 3D 引擎声：已设置 engine_loop（循环）、unit_size 6、max_distance 70、-6 dB、SFX 总线。
## 由调用方加到车辆节点下，自行调 pitch_scale 并 play()。
func make_engine_3d() -> AudioStreamPlayer3D:
	_ensure_init()
	var p := AudioStreamPlayer3D.new()
	p.name = "EngineAudio"
	p.stream = _sfx.get("engine_loop") as AudioStream
	p.unit_size = 6.0
	p.max_distance = 70.0
	p.volume_db = -6.0
	p.bus = BUS_SFX
	for i in range(_engines_3d.size() - 1, -1, -1):
		if _engines_3d[i].get_ref() == null:
			_engines_3d.remove_at(i)
	_engines_3d.append(weakref(p))
	return p


# ———————————————————————————————— 内部

func _ensure_init() -> void:
	if _inited:
		return
	_inited = true
	_setup_buses()
	_load_streams()
	_make_players()
	_apply_volumes()


func _setup_buses() -> void:
	_ensure_bus(BUS_MUSIC, "Master")
	_ensure_bus(BUS_SFX, "Master")
	var idx := _ensure_bus(BUS_ENGINE, BUS_SFX)
	for i in AudioServer.get_bus_effect_count(idx):
		var e := AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectLowPassFilter:
			_lowpass = e as AudioEffectLowPassFilter
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(idx, _lowpass)


func _ensure_bus(bus_name: String, send: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	return idx


func _load_streams() -> void:
	for n in SFX_NAMES:
		var s := _load_stream(SFX_DIR + n + ".ogg", n in LOOP_SFX)
		if s != null:
			_sfx[n] = s
	for n in MUSIC_NAMES:
		var s := _load_stream(MUSIC_DIR + n + ".ogg", true)
		if s != null:
			_music[n] = s


func _load_stream(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("AudioMgr：缺少音频文件 %s" % path)
		return null
	var s := load(path) as AudioStream
	if s == null:
		push_warning("AudioMgr：无法加载 %s" % path)
		return null
	if loop:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return s


func _make_players() -> void:
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Sfx3D%d" % i
		p3.bus = BUS_SFX
		p3.unit_size = 8.0
		p3.max_distance = DEFAULT_RANGE
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		m.bus = BUS_MUSIC
		m.volume_db = SILENT_DB
		add_child(m)
		_music_players.append(m)
	_engine = AudioStreamPlayer.new()
	_engine.name = "Engine"
	_engine.bus = BUS_ENGINE
	_engine.stream = _sfx.get("engine_loop") as AudioStream
	add_child(_engine)
	_drift = AudioStreamPlayer.new()
	_drift.name = "Drift"
	_drift.bus = BUS_ENGINE
	_drift.stream = _sfx.get("drift_loop") as AudioStream
	add_child(_drift)


func _apply_volumes() -> void:
	var mi := AudioServer.get_bus_index(BUS_MUSIC)
	if mi >= 0:
		AudioServer.set_bus_mute(mi, _vol_music <= 0.0)
		AudioServer.set_bus_volume_db(mi, _lin_db(_vol_music) + (PAUSE_MUSIC_DB if _paused else 0.0))
	var si := AudioServer.get_bus_index(BUS_SFX)
	if si >= 0:
		AudioServer.set_bus_mute(si, _vol_sfx <= 0.0)
		AudioServer.set_bus_volume_db(si, _lin_db(_vol_sfx))


func _fade_music(i: int, to: float, time: float, stop_after: bool) -> void:
	var old := _music_tweens[i]
	if old != null and old.is_valid():
		old.kill()
	_music_tweens[i] = null
	var p := _music_players[i]
	if time <= 0.0 or not is_inside_tree():
		_set_music_level(to, i)
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_method(_set_music_level.bind(i), _music_levels[i], to, time)
	if stop_after:
		tw.tween_callback(p.stop)
	_music_tweens[i] = tw


func _set_music_level(level: float, i: int) -> void:
	_music_levels[i] = level
	_music_players[i].volume_db = _lin_db(level)


func _pause_player(pl: Node) -> void:
	if pl.get("playing") and not pl.get("stream_paused"):
		pl.set("stream_paused", true)
		_paused_players.append(pl)


func _get_sfx(sfx_name: String) -> AudioStream:
	var s: AudioStream = _sfx.get(sfx_name)
	if s == null:
		_warn_once("sfx:" + sfx_name, "AudioMgr：找不到音效 %s" % sfx_name)
	return s


## 同一音效 30 ms 内重复触发时忽略
func _throttled(key: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(key, -100000)) < REPEAT_GAP_MSEC:
		return true
	_last_play[key] = now
	return false


## 返回 (线性音量, 音高)
func _vol_pitch(sfx_name: String, opts: Dictionary) -> Vector2:
	var vol := maxf(_num(opts, "volume", 1.0), 0.0)
	var pitch := _num(opts, "pitch", 1.0)
	if opts.has("strength"):
		var s := clampf(_num(opts, "strength", 1.0), 0.0, 1.0)
		vol *= lerpf(0.35, 1.0, s)
		pitch *= lerpf(0.88, 1.06, s)
	if sfx_name == "item_roll" and not opts.has("pitch"):
		pitch *= randf_range(0.8, 1.2)
	return Vector2(vol, clampf(pitch, 0.05, 4.0))


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


static func _lin_db(v: float) -> float:
	return linear_to_db(v) if v > 0.0001 else SILENT_DB


static func _num(d: Dictionary, key: String, def: float) -> float:
	var v: Variant = d.get(key, def)
	if v is float or v is int:
		return float(v)
	return def


static func _flag(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key, false)
	if v is bool:
		return v
	if v is float or v is int:
		return float(v) != 0.0
	return false
