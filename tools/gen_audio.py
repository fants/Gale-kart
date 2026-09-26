#!/usr/bin/env python3
"""疾风卡丁 GALE KART 音频离线合成：全部音效与 BGM 由本脚本用 numpy 生成，再用 ffmpeg 编码为 OGG Vorbis。

用法：
    python3 tools/gen_audio.py                 # 生成全部
    python3 tools/gen_audio.py --only nitro,village
环境变量：
    FFMPEG          指定 ffmpeg 路径（需带 libvorbis 编码器）
    AUDIO_WORK_DIR  中间 WAV 的存放目录（默认系统临时目录）

音效：44.1 kHz 单声道，峰值 -1 dBFS，首尾 4 ms 淡入淡出；engine_loop / drift_loop 为 1.0 s 无缝循环。
音乐：44.1 kHz 立体声，峰值 -3 dBFS、RMS 约 -18 dBFS，首尾 1 拍交叉淡化后无缝循环。
音色与编曲思路参考网页版 src/audio/audio.js、src/audio/music.js。
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")

SFX_PEAK_DB = -1.0
MUSIC_PEAK_DB = -3.0
MUSIC_RMS_DB = -18.0


# ============================================================ 基础工具

def secs(t):
    """秒 → 采样数。"""
    return int(round(t * SR))


def db_to_lin(db):
    return 10.0 ** (db / 20.0)


def lin_to_db(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def seeded(name):
    """按名字生成确定性随机数发生器，保证每次生成结果一致。"""
    h = 2166136261
    for ch in name.encode("utf-8"):
        h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
    return np.random.default_rng(h)


def glide(f0, f1, n, slide):
    """仿 WebAudio exponentialRampToValueAtTime：slide 秒内从 f0 指数滑到 f1，之后保持。"""
    t = np.arange(n) / SR
    if f1 is None or f1 == f0:
        return np.full(n, float(f0))
    k = np.clip(t / max(slide, 1e-4), 0.0, 1.0)
    return f0 * (max(f1, 1e-3) / f0) ** k


def polyblep(t, dt):
    """PolyBLEP 残差，用来抑制锯齿波 / 方波跳变处的混叠。t 为 0..1 的相位，dt 为每采样相位增量。"""
    r = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    r[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    r[m] = x * x + x + x + 1.0
    return r


def osc(kind, freq, n=None, duty=0.5, phase0=0.0):
    """振荡器。freq 可以是标量或逐采样数组（Hz）。kind：sine saw square pulse tri。"""
    if np.isscalar(freq):
        freq = np.full(n, float(freq))
    ph = phase0 + np.cumsum(freq) / SR
    if kind == "sine":
        return np.sin(2.0 * np.pi * ph)
    t = ph % 1.0
    dt = np.clip(freq / SR, 1e-9, 0.5)
    if kind == "saw":
        return 2.0 * t - 1.0 - polyblep(t, dt)
    if kind in ("square", "pulse"):
        d = duty if kind == "square" else (duty if duty != 0.5 else 0.25)
        y = np.where(t < d, 1.0, -1.0) + polyblep(t, dt) - polyblep((t - d) % 1.0, dt)
        return y - (2.0 * d - 1.0)
    if kind == "tri":
        return 1.0 - 4.0 * np.abs(((t + 0.25) % 1.0) - 0.5)
    raise ValueError(kind)


def biquad(x, kind, freq, q=0.707):
    """RBJ 二阶滤波器，freq 可逐采样变化（时变截止频率）。kind：lowpass highpass bandpass。"""
    n = len(x)
    f = np.clip(np.broadcast_to(np.asarray(freq, float), (n,)), 10.0, SR * 0.49)
    w0 = 2.0 * np.pi * f / SR
    cw = np.cos(w0)
    alpha = np.sin(w0) / (2.0 * max(q, 1e-3))
    a0 = 1.0 + alpha
    if kind == "lowpass":
        b0 = (1.0 - cw) / 2.0
        b1 = 1.0 - cw
        b2 = b0
    elif kind == "highpass":
        b0 = (1.0 + cw) / 2.0
        b1 = -(1.0 + cw)
        b2 = b0
    elif kind == "bandpass":
        b0 = alpha
        b1 = np.zeros(n)
        b2 = -alpha
    else:
        raise ValueError(kind)
    a1 = -2.0 * cw / a0
    a2 = (1.0 - alpha) / a0
    b0 = np.broadcast_to(b0 / a0, (n,)).tolist()
    b1 = np.broadcast_to(b1 / a0, (n,)).tolist()
    b2 = np.broadcast_to(b2 / a0, (n,)).tolist()
    a1 = np.broadcast_to(a1, (n,)).tolist()
    a2 = np.broadcast_to(a2, (n,)).tolist()
    xs = x.tolist()
    y = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        xi = xs[i]
        yi = b0[i] * xi + b1[i] * x1 + b2[i] * x2 - a1[i] * y1 - a2[i] * y2
        x2 = x1
        x1 = xi
        y2 = y1
        y1 = yi
        y[i] = yi
    return np.asarray(y)


def fft_filter(x, resp, circular=False):
    """零相位频域滤波。resp(freqs) 返回每个频率的增益。circular=True 时按循环卷积处理（用于无缝循环素材）。"""
    n = len(x)
    size = n if circular else int(2 ** np.ceil(np.log2(n + SR)))
    spec = np.fft.rfft(x, size)
    freqs = np.fft.rfftfreq(size, 1.0 / SR)
    return np.fft.irfft(spec * resp(freqs), size)[:n]


def lp_resp(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp_resp(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def bp_resp(fc, width_oct):
    """以 fc 为中心、宽度约 width_oct 个八度的高斯形带通。"""
    return lambda f: np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / (width_oct / 2.0)) ** 2)


def fade_edges(x, ms=4.0):
    n = min(secs(ms / 1000.0), len(x) // 2)
    if n > 0:
        w = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n))
        x[:n] *= w
        x[-n:] *= w[::-1]
    return x


def trim_tail(x, rel_db=-70.0):
    """裁掉尾部低于峰值 rel_db 的静音。"""
    peak = np.max(np.abs(x))
    if peak <= 0:
        return x[: secs(0.05)]
    idx = np.nonzero(np.abs(x) > peak * db_to_lin(rel_db))[0]
    return x[: idx[-1] + 1] if len(idx) else x


# ============================================================ 编码与测量

def find_ffmpeg():
    cands = [os.environ.get("FFMPEG"), shutil.which("ffmpeg"),
             "/usr/local/opt/ffmpeg-full/bin/ffmpeg", "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"]
    for c in cands:
        if not c or not os.path.exists(c):
            continue
        out = subprocess.run([c, "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
        if "libvorbis" in out:
            return c
    sys.exit("找不到带 libvorbis 编码器的 ffmpeg；可用环境变量 FFMPEG 指定路径。")


def write_wav(path, data):
    """data：单声道 (n,) 或立体声 (n, 2) 的 float 数组，写 16 位 PCM（TPDF 抖动）。"""
    ch = 1 if data.ndim == 1 else data.shape[1]
    rng = np.random.default_rng(1)
    dither = (rng.random(data.shape) - rng.random(data.shape)) / 32768.0
    pcm = np.clip(np.round((data + dither) * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode_ogg(ffmpeg, wav_path, ogg_path):
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", wav_path,
                    "-c:a", "libvorbis", "-q:a", "5", ogg_path], check=True)


def decode_ogg(ffmpeg, ogg_path, channels):
    raw = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", ogg_path,
                          "-f", "f32le", "-ac", str(channels), "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    d = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return d if channels == 1 else d.reshape(-1, channels)


def seam_ratio(x):
    """循环点跳变 / 平均相邻采样差：≈1 表示循环点和普通位置一样平滑。"""
    m = x if x.ndim == 1 else x.mean(axis=1)
    typical = np.mean(np.abs(np.diff(m))) + 1e-12
    return abs(m[0] - m[-1]) / typical


def export(ffmpeg, work, out_dir, name, data, peak_db, loop=False):
    """写 WAV → 编码 OGG → 解码回来测峰值；若有损编码把峰值顶过目标，就按超出量缩小后重编码。"""
    channels = 1 if data.ndim == 1 else 2
    wav_path = os.path.join(work, name + ".wav")
    ogg_path = os.path.join(out_dir, name + ".ogg")
    target = db_to_lin(peak_db + 0.05)
    for _ in range(4):
        write_wav(wav_path, data)
        encode_ogg(ffmpeg, wav_path, ogg_path)
        dec = decode_ogg(ffmpeg, ogg_path, channels)
        peak = np.max(np.abs(dec))
        if peak <= target:
            break
        data = data * (db_to_lin(peak_db - 0.1) / peak)
    info = {
        "name": name,
        "dur": len(dec) / SR,
        "samples": len(dec),
        "peak_db": lin_to_db(np.max(np.abs(dec))),
        "rms_db": lin_to_db(np.sqrt(np.mean(dec ** 2))),
        "bytes": os.path.getsize(ogg_path),
    }
    if loop:
        info["seam_src"] = seam_ratio(data)
        info["seam_ogg"] = seam_ratio(dec)
    return info


# ============================================================ 音效积木（仿 audio.js 的 tone / noise / arp）

N = {"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.0, "A4": 440.0, "Bb4": 466.16,
     "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99, "A5": 880.0,
     "B5": 987.77, "C6": 1046.5, "D6": 1174.66, "E6": 1318.5, "G6": 1568.0, "A6": 1760.0, "B6": 1975.5,
     "C7": 2093.0, "D7": 2349.3, "E7": 2637.0}


def env_tone(n, peak, attack, dur, release):
    """线性起音到峰值，保持到 dur - release，再以 release/3 为时间常数指数衰减（同 WebAudio setTargetAtTime）。"""
    t = np.arange(n) / SR
    a = max(attack, 1e-4)
    start = max(a, dur - release)
    tau = max(release / 3.0, 1e-4)
    e = np.where(t < a, t / a, 1.0)
    dec = t >= start
    e[dec] = np.exp(-(t[dec] - start) / tau)
    return e * peak


class Sfx:
    """一次性音效的混音缓冲。"""

    def __init__(self, name):
        self.x = np.zeros(secs(1.0))
        self.rng = seeded(name)

    def add(self, sig, delay=0.0, gain=1.0):
        i = secs(delay)
        end = i + len(sig)
        if end > len(self.x):
            self.x = np.concatenate([self.x, np.zeros(end - len(self.x))])
        self.x[i:end] += sig * gain

    def tone(self, freq, dur, type="sine", to=None, slide=None, gain=0.2, attack=0.005, release=None, delay=0.0,
             vibrato=0.0, vib_depth=None, filter=None, cutoff=1200.0, cutoff_to=None, q=0.707, duty=0.5,
             am=0.0, am_depth=0.0):
        n = secs(dur + 0.12)
        t = np.arange(n) / SR
        f = glide(freq, to, n, dur if slide is None else slide)
        if vibrato:
            depth = freq * 0.05 if vib_depth is None else vib_depth
            f = f + depth * np.sin(2.0 * np.pi * vibrato * t)
        y = osc(type, np.maximum(f, 5.0), duty=duty)
        if filter:
            fc = glide(cutoff, cutoff_to, n, dur) if cutoff_to else cutoff
            y = biquad(y, filter, fc, q)
        if am:
            y *= 1.0 - am_depth * (0.5 + 0.5 * np.sin(2.0 * np.pi * am * t))
        y *= env_tone(n, gain, attack, dur, dur * 0.6 if release is None else release)
        self.add(y, delay)

    def noise(self, dur, filter="lowpass", freq=1000.0, to=None, q=0.8, gain=0.2, attack=0.005, delay=0.0):
        n = secs(dur + 0.12)
        t = np.arange(n) / SR
        fc = glide(freq, to, n, dur) if to else freq
        y = biquad(self.rng.uniform(-1.0, 1.0, n), filter, fc, q)
        a = max(attack, 1e-4)
        tau = max((dur - a) / 3.0, 1e-3)
        e = np.where(t < a, t / a, np.exp(-(t - a) / tau))
        self.add(y * e * gain, delay)

    def arp(self, freqs, step, length=None, delay=0.0, **o):
        for i, f in enumerate(freqs):
            self.tone(f, step * 1.6 if length is None else length, delay=delay + i * step, **o)

    def brass(self, freq, dur, delay=0.0, gain=0.1):
        """小号感：锯齿 + 方波，低通截止频率随起音张开再回落，尾段带颤音。"""
        n = secs(dur + 0.15)
        t = np.arange(n) / SR
        vib = 1.0 + 0.006 * np.clip((t - 0.15) / 0.2, 0.0, 1.0) * np.sin(2.0 * np.pi * 5.5 * t)
        f = freq * vib
        y = 0.7 * osc("saw", f) + 0.3 * osc("square", f * 1.003)
        fc = 700.0 + 3400.0 * np.clip(t / 0.04, 0.0, 1.0) * np.exp(-np.maximum(t - 0.04, 0.0) / 0.35) + 1300.0
        y = biquad(y, "lowpass", fc, 1.2)
        e = np.clip(t / 0.018, 0.0, 1.0) * (0.8 + 0.2 * np.exp(-t / 0.12))
        rel = t > dur
        e[rel] *= np.exp(-(t[rel] - dur) / 0.05)
        self.add(y * e * gain, delay)

    def blip(self, f0, f1, dur, gain, delay):
        self.tone(f0, dur, "sine", to=f1, gain=gain, delay=delay)


def sfx_gauge_full(s):
    s.arp([N["C6"], N["E6"], N["G6"], N["C7"]], 0.045, type="sine", gain=0.14)
    s.arp([N["C6"], N["E6"], N["G6"], N["C7"]], 0.045, type="tri", gain=0.05)
    s.tone(N["C7"], 0.3, "sine", gain=0.07, delay=0.18, vibrato=7, vib_depth=12)


def sfx_nitro(s):
    s.noise(1.1, "bandpass", 700, to=4000, q=0.9, gain=0.4, attack=0.03)
    s.noise(0.45, "lowpass", 380, gain=0.25)
    s.tone(90, 1.0, "saw", to=200, gain=0.12, filter="lowpass", cutoff=900)


def sfx_instant_boost(s):
    s.noise(0.28, "highpass", 1800, gain=0.3)
    s.tone(300, 0.16, "square", to=900, gain=0.08)


def sfx_instant_ready(s):
    s.tone(N["E6"], 0.07, "tri", gain=0.14)
    s.tone(N["A6"], 0.14, "tri", gain=0.14, delay=0.06)
    s.tone(N["A6"] * 2, 0.1, "sine", gain=0.04, delay=0.06)


def sfx_start_boost(s):
    s.noise(0.7, "bandpass", 500, to=3500, q=1.2, gain=0.35)
    s.tone(110, 0.6, "saw", to=440, gain=0.12, filter="lowpass", cutoff=1500)
    s.noise(0.2, "lowpass", 300, gain=0.25)


def sfx_false_start(s):
    s.tone(220, 0.5, "square", to=70, gain=0.1, vibrato=9, vib_depth=25, filter="lowpass", cutoff=1400)
    s.tone(140, 0.4, "saw", gain=0.06, filter="lowpass", cutoff=900, delay=0.02)
    for d in (0.0, 0.16, 0.34):
        s.noise(0.07, "lowpass", 650, gain=0.35, delay=d)


def sfx_boost_pad(s):
    s.tone(400, 0.32, "sine", to=1700, gain=0.18)
    s.tone(800, 0.3, "square", to=2400, gain=0.035, delay=0.03)
    s.noise(0.25, "bandpass", 2500, q=2, gain=0.15)


def sfx_draft(s):
    s.noise(0.75, "bandpass", 600, to=2200, q=1.2, gain=0.3, attack=0.25)
    s.tone(880, 0.6, "sine", to=1320, gain=0.03, attack=0.2)


def sfx_wall_hit(s):
    s.noise(0.18, "lowpass", 800, gain=0.55)
    s.tone(90, 0.18, "sine", to=40, gain=0.5)
    s.tone(420, 0.12, "square", to=300, gain=0.05, filter="lowpass", cutoff=2000)


def sfx_kart_hit(s):
    s.tone(240, 0.12, "square", to=120, gain=0.22)
    s.tone(160, 0.1, "sine", to=80, gain=0.2)
    s.noise(0.1, "bandpass", 1300, q=2, gain=0.3)


def sfx_land(s):
    s.noise(0.15, "lowpass", 320, gain=0.4)
    s.tone(70, 0.15, "sine", to=45, gain=0.25)


def sfx_countdown(s):
    s.tone(N["A4"], 0.2, "square", gain=0.16, release=0.08)
    s.tone(N["A5"], 0.2, "tri", gain=0.06, release=0.08)


def sfx_go(s):
    s.tone(N["A5"], 0.7, "square", gain=0.16, release=0.4)
    s.tone(N["E6"], 0.7, "tri", gain=0.1, release=0.4)
    s.tone(N["A6"], 0.5, "sine", gain=0.03, release=0.3)


def sfx_lap(s):
    s.arp([N["G5"], N["C6"]], 0.12, type="square", gain=0.1)


def sfx_final_lap(s):
    s.arp([N["C5"], N["E5"], N["G5"], N["C6"]], 0.11, length=0.3, type="saw", gain=0.07,
          filter="lowpass", cutoff=2600)
    s.tone(N["C6"], 0.5, "square", gain=0.05, delay=0.44)


def sfx_finish(s):
    s.arp([N["C5"], N["E5"], N["G5"], N["C6"], N["E6"]], 0.08, type="square", gain=0.09)
    for f in (N["C5"], N["E5"], N["G5"]):
        s.tone(f, 1.2, "tri", gain=0.07, delay=0.42)


def sfx_win(s):
    mel = [(N["G5"], 0.0, 0.13), (N["G5"], 0.15, 0.13), (N["C6"], 0.3, 0.28), (N["B5"], 0.6, 0.13),
           (N["C6"], 0.75, 0.13), (N["E6"], 0.9, 0.28), (N["G6"], 1.2, 1.1)]
    for f, d, l in mel:
        s.brass(f, l, delay=d, gain=0.09)
        s.tone(f, l, "square", gain=0.025, delay=d)
    for f, d in ((N["C4"], 0.0), (N["G4"], 0.6), (N["C5"], 1.2)):
        s.tone(f, 0.55 if d < 1.2 else 1.1, "tri", gain=0.14, delay=d)
    for f in (N["E5"], N["G5"]):
        s.brass(f, 1.1, delay=1.2, gain=0.04)
    s.noise(1.2, "highpass", 5000, gain=0.07, delay=1.2)


def sfx_lose(s):
    notes = [N["C5"], N["B4"], N["Bb4"], N["A4"]]
    for i, f in enumerate(notes):
        last = i == 3
        s.tone(f, 0.7 if last else 0.35, "tri", gain=0.12, delay=i * 0.28, vibrato=6 if last else 0, vib_depth=8)
        s.tone(f / 2, 0.7 if last else 0.3, "pulse", gain=0.025, delay=i * 0.28)


def sfx_new_record(s):
    s.arp([N["C6"], N["D6"], N["E6"], N["G6"], N["A6"], N["C7"], N["D7"], N["E7"]], 0.045, type="tri", gain=0.08)
    fan = [(N["G5"], 0.45, 0.1), (N["C6"], 0.58, 0.1), (N["E6"], 0.71, 0.1), (N["G6"], 0.84, 1.0)]
    for f, d, l in fan:
        s.brass(f, l, delay=d, gain=0.09)
    for f in (N["C5"], N["E5"], N["G5"]):
        s.tone(f, 1.0, "tri", gain=0.06, delay=0.84)
    s.tone(N["C4"], 1.0, "tri", gain=0.12, delay=0.84)
    s.noise(1.1, "highpass", 5000, gain=0.07, delay=0.84)
    s.arp([N["C7"], N["E7"]], 0.08, type="sine", gain=0.04, delay=1.3)


def sfx_item_roll(s):
    s.tone(1150, 0.035, "square", gain=0.05)


def sfx_item_get(s):
    s.noise(0.22, "highpass", 3000, gain=0.12)
    s.arp([N["G5"], N["C6"], N["E6"]], 0.05, type="tri", gain=0.14)


def sfx_item_use(s):
    s.tone(600, 0.09, "square", to=950, gain=0.08)
    s.noise(0.08, "highpass", 2000, gain=0.05)


def sfx_missile_launch(s):
    s.noise(0.12, "lowpass", 300, gain=0.3)
    s.noise(0.55, "bandpass", 900, to=3200, q=1.5, gain=0.3)
    s.tone(200, 0.45, "saw", to=820, gain=0.08, filter="lowpass", cutoff=2000)


def sfx_missile_lock(s):
    for d in (0.0, 0.1):
        s.tone(1760, 0.06, "square", gain=0.1, delay=d)


def sfx_explosion(s):
    s.noise(0.08, "highpass", 1000, gain=0.3)
    s.noise(1.4, "lowpass", 1400, to=90, gain=1.6)
    s.noise(0.5, "bandpass", 700, to=200, q=0.7, gain=0.5)
    s.tone(90, 0.8, "sine", to=28, gain=0.3)
    for i in range(10):
        d = 0.08 + i * 0.07 + s.rng.random() * 0.05
        s.noise(0.03, "highpass", 1800, gain=0.12 * (1.0 - i / 11.0), delay=d)


def sfx_water_throw(s):
    s.tone(300, 0.25, "sine", to=700, gain=0.12)
    s.noise(0.3, "bandpass", 1200, q=1.5, gain=0.12)


def sfx_water_splash(s):
    s.noise(0.7, "bandpass", 1600, to=400, q=0.9, gain=0.35)
    s.noise(0.15, "lowpass", 400, gain=0.2)
    for i in range(6):
        s.blip(350 + s.rng.random() * 600, 900 + s.rng.random() * 600, 0.08, 0.08, 0.05 + i * 0.06)


def sfx_bubble(s):
    for i in range(8):
        s.blip(300 + i * 60 + s.rng.random() * 80, 700 + i * 80, 0.07, 0.09, i * 0.11)


def sfx_banana(s):
    s.tone(520, 0.22, "tri", to=260, gain=0.14, vibrato=18, vib_depth=30)
    s.noise(0.1, "bandpass", 900, q=3, gain=0.12)


def sfx_spin(s):
    s.tone(900, 0.85, "sine", to=180, gain=0.14, vibrato=12, vib_depth=60)
    s.tone(1350, 0.85, "tri", to=270, gain=0.04, vibrato=12, vib_depth=90)


def sfx_shield(s):
    for i, f in enumerate((N["C5"], N["E5"], N["G5"], N["C6"])):
        s.tone(f, 0.9, "sine", gain=0.07, attack=0.08 + i * 0.03, delay=i * 0.02)
    s.tone(N["C7"], 0.9, "sine", gain=0.025, attack=0.2, vibrato=7, vib_depth=20)


def sfx_shield_block(s):
    s.noise(0.05, "highpass", 4000, gain=0.1)
    s.tone(N["C7"], 0.35, "sine", gain=0.14)
    s.tone(3136, 0.3, "sine", gain=0.07, delay=0.03)
    s.tone(N["G6"], 0.25, "tri", gain=0.04)


def sfx_cloud(s):
    s.noise(1.3, "lowpass", 320, gain=0.35, attack=0.1)
    s.tone(55, 1.2, "sine", gain=0.2, attack=0.1)
    s.tone(110, 1.2, "saw", gain=0.05, attack=0.2, filter="lowpass", cutoff=250, vibrato=3, vib_depth=3)


def sfx_thunder(s):
    s.noise(1.6, "lowpass", 2600, to=160, gain=0.9)
    s.noise(0.2, "highpass", 3000, gain=0.25, delay=0.05)
    s.tone(60, 1.2, "sine", to=30, gain=0.3)
    s.noise(1.2, "lowpass", 420, to=100, gain=0.9, delay=0.35, attack=0.08)


def sfx_magnet(s):
    s.tone(200, 0.6, "saw", to=620, gain=0.08, filter="lowpass", cutoff=1600, vibrato=22, vib_depth=25)
    s.tone(400, 0.6, "sine", to=1240, gain=0.04, vibrato=22, vib_depth=50)


def sfx_ufo(s):
    s.tone(700, 1.2, "sine", to=1000, gain=0.12, attack=0.05, release=0.4, vibrato=9, vib_depth=180)
    s.tone(1050, 1.2, "tri", to=1500, gain=0.04, attack=0.05, release=0.4, vibrato=9, vib_depth=270)
    s.noise(1.2, "bandpass", 3000, q=4, gain=0.04, attack=0.3)


def sfx_water_fly(s):
    s.tone(190, 1.0, "saw", gain=0.1, attack=0.05, release=0.3, vibrato=26, vib_depth=25,
           filter="lowpass", cutoff=1800, am=31, am_depth=0.5)
    s.tone(380, 1.0, "square", gain=0.025, attack=0.05, release=0.3, vibrato=26, vib_depth=50, am=31, am_depth=0.5)
    for i in range(3):
        s.blip(500 + i * 120, 1100 + i * 150, 0.07, 0.05, 0.2 + i * 0.22)


def sfx_respawn(s):
    s.tone(400, 0.4, "sine", to=1200, gain=0.12)
    s.arp([N["C6"], N["E6"], N["G6"]], 0.06, type="tri", gain=0.05, delay=0.25)


def sfx_wrong_way(s):
    for d in (0.0, 0.2):
        s.tone(330, 0.14, "square", gain=0.09, delay=d)
        s.tone(165, 0.14, "tri", gain=0.08, delay=d)


def sfx_ui_click(s):
    s.tone(880, 0.05, "square", gain=0.1)
    s.tone(1320, 0.05, "tri", gain=0.08, delay=0.02)


def sfx_ui_hover(s):
    s.tone(1250, 0.03, "sine", gain=0.04)


def sfx_ui_back(s):
    s.arp([N["E5"], N["C5"]], 0.05, length=0.06, type="tri", gain=0.12)


def sfx_ui_confirm(s):
    s.arp([N["C5"], N["E5"], N["G5"]], 0.035, length=0.05, type="tri", gain=0.12)
    s.tone(N["C6"], 0.05, "sine", gain=0.04, delay=0.07)


def sfx_ui_pause(s):
    s.tone(660, 0.1, "tri", to=440, gain=0.12)


# 名字 → (合成函数, 最大时长秒；None 表示按自然衰减裁静音)
ONESHOTS = {
    "gauge_full": (sfx_gauge_full, None), "nitro": (sfx_nitro, None), "instant_boost": (sfx_instant_boost, None),
    "instant_ready": (sfx_instant_ready, None), "start_boost": (sfx_start_boost, None),
    "false_start": (sfx_false_start, None), "boost_pad": (sfx_boost_pad, None), "draft": (sfx_draft, None),
    "wall_hit": (sfx_wall_hit, None), "kart_hit": (sfx_kart_hit, None), "land": (sfx_land, None),
    "countdown": (sfx_countdown, 0.35), "go": (sfx_go, None), "lap": (sfx_lap, None),
    "final_lap": (sfx_final_lap, None), "finish": (sfx_finish, None), "win": (sfx_win, None),
    "lose": (sfx_lose, None), "new_record": (sfx_new_record, None), "item_roll": (sfx_item_roll, 0.08),
    "item_get": (sfx_item_get, None), "item_use": (sfx_item_use, None),
    "missile_launch": (sfx_missile_launch, None), "missile_lock": (sfx_missile_lock, None),
    "explosion": (sfx_explosion, None), "water_throw": (sfx_water_throw, None),
    "water_splash": (sfx_water_splash, None), "bubble": (sfx_bubble, None), "banana": (sfx_banana, None),
    "spin": (sfx_spin, None), "shield": (sfx_shield, None), "shield_block": (sfx_shield_block, None),
    "cloud": (sfx_cloud, None), "thunder": (sfx_thunder, None), "magnet": (sfx_magnet, None),
    "ufo": (sfx_ufo, None), "water_fly": (sfx_water_fly, None), "respawn": (sfx_respawn, None),
    "wrong_way": (sfx_wrong_way, None), "ui_click": (sfx_ui_click, 0.12), "ui_hover": (sfx_ui_hover, 0.07),
    "ui_back": (sfx_ui_back, 0.14), "ui_confirm": (sfx_ui_confirm, 0.14), "ui_pause": (sfx_ui_pause, 0.14),
}


def render_oneshot(name):
    fn, max_len = ONESHOTS[name]
    s = Sfx(name)
    fn(s)
    # 按 -60 dB 裁尾，最长 2.2 s
    x = trim_tail(s.x, -60.0)[: secs(2.2)]
    if max_len:
        x = x[: secs(max_len)]
    x = fade_edges(x.copy(), 4.0)
    return x / np.max(np.abs(x)) * db_to_lin(SFX_PEAK_DB)


# ============================================================ 循环音效

def periodic_noise(rng, n, resp):
    """在频域直接构造的周期噪声：长度 n 的循环缓冲首尾天然衔接。"""
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    spec = np.exp(2j * np.pi * rng.random(len(freqs))) * resp(freqs)
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    return y / np.sqrt(np.mean(y ** 2))


def gen_engine_loop():
    """1.0 s 卡丁车引擎循环：56 Hz 锯齿 + 脉冲 + 28 Hz 次谐波 + 与点火同步的排气噪声。
    所有分量都是整数赫兹，滤波用循环卷积，因此 1 s 缓冲首尾严格周期对齐。"""
    n = SR
    t = np.arange(n) / SR
    rng = seeded("engine_loop")
    f0 = 56.0
    saw = osc("saw", f0, n, phase0=0.5)
    pulse = osc("square", f0, n, duty=0.3, phase0=0.13)
    sub = np.sin(2.0 * np.pi * f0 / 2.0 * t + 0.4)
    sub_tri = osc("tri", f0 / 2.0, n, phase0=0.1)
    x = 0.55 * saw + 0.4 * pulse + 0.3 * sub + 0.15 * sub_tri
    # 排气共振：~180 Hz、~450 Hz、~1.1 kHz 三个共振峰，2.8 kHz 以上滚降；压低 60 Hz 以下，免得小音箱上只剩闷响
    formant = lambda f: (0.6 + 1.0 * bp_resp(180.0, 1.2)(f) + 2.2 * bp_resp(450.0, 1.2)(f)
                         + 1.2 * bp_resp(1100.0, 1.0)(f)) * lp_resp(2800.0, 2)(f) \
        * (0.35 + 0.65 * hp_resp(60.0, 2)(f)) * hp_resp(22.0, 2)(f)
    x = fft_filter(x, formant, circular=True)
    # 每个点火周期一个噪声爆发（|sin|^8 的包络与基频同步）
    burst = np.abs(np.sin(np.pi * f0 * t)) ** 8
    hiss = periodic_noise(rng, n, lambda f: bp_resp(1400.0, 2.5)(f))
    x = x / np.sqrt(np.mean(x ** 2)) + 0.22 * hiss * burst
    # “突突”调幅（14 Hz = 基频 / 4）与缓慢的随机起伏（整数赫兹正弦叠加）
    lump = 0.82 + 0.18 * (0.5 + 0.5 * np.cos(2.0 * np.pi * 14.0 * t)) ** 2
    wob = np.zeros(n)
    for k in range(3, 28, 2):
        wob += np.sin(2.0 * np.pi * k * t + rng.random() * 6.283) / k
    x *= lump * (1.0 + 0.06 * wob / np.max(np.abs(wob)))
    x -= np.mean(x)
    return x / np.max(np.abs(x)) * db_to_lin(SFX_PEAK_DB)


def gen_drift_loop():
    """1.0 s 轮胎摩擦尖叫：带通噪声 + 带颤音的尖叫音调。噪声多生成 0.1 s，首尾等功率交叉淡化成无缝循环；
    音调与颤动都用整数赫兹，本身就是 1 s 周期。"""
    n = SR
    xf = secs(0.1)
    rng = seeded("drift_loop")
    raw = rng.uniform(-1.0, 1.0, n + xf + secs(0.05))
    nz = biquad(raw, "bandpass", 1900.0, 5.0) + 0.5 * biquad(raw, "bandpass", 3200.0, 7.0) \
        + 0.25 * biquad(raw, "bandpass", 900.0, 2.0)
    nz = nz[secs(0.05):]
    w = np.linspace(0.0, 1.0, xf)
    out = nz[:n].copy()
    out[:xf] = nz[:xf] * np.sin(0.5 * np.pi * w) + nz[n:n + xf] * np.cos(0.5 * np.pi * w)
    out /= np.sqrt(np.mean(out ** 2))
    t = np.arange(n) / SR
    f = 1850.0 + 60.0 * np.sin(2.0 * np.pi * 6.0 * t)
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    squeal = np.sin(ph) + 0.35 * np.sin(2.0 * ph + 0.5) + 0.12 * np.sin(3.0 * ph + 1.1)
    x = 0.9 * out + 0.55 * squeal
    trem = 1.0 + 0.22 * np.sin(2.0 * np.pi * 11.0 * t) + 0.12 * np.sin(2.0 * np.pi * 17.0 * t + 1.3)
    x *= trem
    x -= np.mean(x)
    return x / np.max(np.abs(x)) * db_to_lin(SFX_PEAK_DB)


LOOPS = {"engine_loop": gen_engine_loop, "drift_loop": gen_drift_loop}

SFX_NAMES = ["engine_loop", "drift_loop", "gauge_full", "nitro", "instant_boost", "instant_ready", "start_boost",
             "false_start", "boost_pad", "draft", "wall_hit", "kart_hit", "land", "countdown", "go", "lap",
             "final_lap", "finish", "win", "lose", "new_record", "item_roll", "item_get", "item_use",
             "missile_launch", "missile_lock", "explosion", "water_throw", "water_splash", "bubble", "banana",
             "spin", "shield", "shield_block", "cloud", "thunder", "magnet", "ufo", "water_fly", "respawn",
             "wrong_way", "ui_click", "ui_hover", "ui_back", "ui_confirm", "ui_pause"]


# ============================================================ BGM 合成器

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
LYDIAN = [0, 2, 4, 6, 7, 9, 11]
PHRYG_DOM = [0, 1, 4, 5, 7, 8, 10]
MIXO = [0, 2, 4, 5, 7, 9, 10]

ARP_DEG = [0, 2, 4, 7, 9]  # 琶音字符 0..4 → 和弦根音起的音阶级数（根 / 三 / 五 / 八度 / 十度）

# 声像：-1 左 … +1 右
PANS = {"lead": -0.12, "harm": 0.35, "echo": 0.0, "arp": 0.4, "padL": -0.6, "padR": 0.6, "bass": 0.0,
        "kick": 0.0, "snare": 0.06, "hat": 0.3, "crash": -0.25}


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def parse_mel(text, bars=8):
    """旋律记法：空格分隔的「级数/时值(16 分音符)」，级数 . 表示休止。"""
    notes, pos = [], 0
    for tok in text.split():
        d, length = tok.split("/")
        if d != ".":
            notes.append((pos, int(d), int(length)))
        pos += int(length)
    assert pos == bars * 16, "旋律长度 %d ≠ %d：%s" % (pos, bars * 16, text)
    return notes


def env_note(n, dur, attack, decay, sustain, release):
    """线性起音 → 以 dur*decay 为时间常数衰减到 sustain → dur 之后按 release 时间常数淡出。"""
    t = np.arange(n) / SR
    tau = max(dur * decay, 1e-3)
    e = np.where(t < attack, t / attack, sustain + (1.0 - sustain) * np.exp(-(t - attack) / tau))
    v = dur / attack if dur < attack else sustain + (1.0 - sustain) * np.exp(-(dur - attack) / tau)
    rel = t > dur
    e[rel] = v * np.exp(-(t[rel] - dur) / release)
    return e


def instrument(wave, freq, dur, vib=False, duty=0.5, attack=0.005, decay=0.4, sustain=0.7, release=0.03,
               detune_cents=0.0):
    """渲染单个音符（单声道）。wave：square pulse saw tri sine bell wood。"""
    freq *= 2.0 ** (detune_cents / 1200.0)
    if wave == "bell":
        n = secs(dur + 1.2)
    else:
        n = secs(dur + release * 7.0)
    t = np.arange(n) / SR
    f = np.full(n, freq)
    if vib and dur > 0.25:
        f = f + np.clip(t / dur, 0.0, 1.0) * freq * 0.008 * np.sin(2.0 * np.pi * 5.5 * t)
    if wave == "bell":
        # FM 铃铛：非整数调制比 3.5 产生金属泛音，调制指数与振幅都指数衰减
        ph = 2.0 * np.pi * np.cumsum(f) / SR
        index = 2.0 * np.exp(-t / 0.2)
        y = 0.8 * np.sin(ph + index * np.sin(3.5 * ph)) + 0.2 * np.sin(2.0 * ph)
        e = np.clip(t / 0.002, 0.0, 1.0) * np.exp(-t / (0.3 + dur * 0.6))
        return y * e
    if wave == "wood":
        # 木管感：以奇次谐波为主、带少量偶次谐波的加法合成（类似单簧管 / 陶笛）
        ph = 2.0 * np.pi * np.cumsum(f) / SR
        y = sum(np.sin(k * ph) / k ** 1.5 for k in (1, 3, 5, 7, 9)) + 0.12 * np.sin(2 * ph) + 0.05 * np.sin(4 * ph)
    else:
        y = osc(wave, f, duty=duty)
    return y * env_note(n, dur, attack, decay, sustain, release)


def drum_kit(seed):
    """一次性渲染整首歌用的鼓组采样（确定性随机），各自峰值归一到 1。"""
    rng = seeded(seed)
    kit = {}
    n = secs(0.3)
    t = np.arange(n) / SR
    f = 150.0 * (45.0 / 150.0) ** np.clip(t / 0.12, 0.0, 1.0)
    kick = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.06)
    kick += 0.35 * biquad(rng.uniform(-1, 1, n), "lowpass", 3000.0) * np.exp(-t / 0.004)
    kit["kick"] = kick
    n = secs(0.25)
    t = np.arange(n) / SR
    nz = biquad(rng.uniform(-1, 1, n), "bandpass", 1800.0, 0.8)
    nz /= np.sqrt(np.mean(nz[: secs(0.05)] ** 2))
    kit["snare"] = 0.7 * nz * np.exp(-t / 0.055) + 0.4 * np.sin(2.0 * np.pi * 190.0 * t) * np.exp(-t / 0.035)
    n = secs(0.08)
    t = np.arange(n) / SR
    kit["hat"] = biquad(rng.uniform(-1, 1, n), "highpass", 7000.0) * np.exp(-t / 0.012)
    n = secs(0.35)
    t = np.arange(n) / SR
    kit["ohat"] = biquad(rng.uniform(-1, 1, n), "highpass", 6000.0) * np.exp(-t / 0.08)
    n = secs(1.6)
    t = np.arange(n) / SR
    c = rng.uniform(-1, 1, n)
    crash = biquad(c, "highpass", 4500.0) + 0.5 * biquad(c, "bandpass", 7000.0, 1.5)
    kit["crash"] = crash * np.exp(-t / 0.45) * np.clip(t / 0.002, 0.0, 1.0)
    for k in kit:
        kit[k] = kit[k] / np.max(np.abs(kit[k]))
    return kit


def fft_convolve(x, ir, size):
    m = int(2 ** np.ceil(np.log2(size + len(ir))))
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:size]


def pan_gains(p):
    a = (p + 1.0) * np.pi / 4.0
    return np.cos(a), np.sin(a)


def limit_circular(x, thr):
    """循环缓冲上的简易峰值限制器：按 64 采样块求所需增益，循环地取邻域最小值再平滑，首尾增益一致。"""
    blk = 64
    n = x.shape[0]
    nb = int(np.ceil(n / blk))
    pad = np.zeros((nb * blk, x.shape[1]))
    pad[:n] = x
    peaks = np.max(np.abs(pad).reshape(nb, blk, -1), axis=(1, 2))
    g = np.minimum(1.0, thr / np.maximum(peaks, 1e-9))
    for _ in range(3):  # 前后各扩展 3 块（≈4 ms）
        g = np.minimum(g, np.minimum(np.roll(g, 1), np.roll(g, -1)))
    k = 16  # 约 23 ms 的循环移动平均，释放平滑
    g = np.minimum(g, np.convolve(np.concatenate([g[-k:], g, g[:k]]), np.ones(2 * k + 1) / (2 * k + 1), "same")[k:-k])
    gs = np.interp(np.arange(nb * blk), np.arange(nb) * blk + blk / 2, g, period=nb * blk)[:n]
    return x * gs[:, None]


def render_song(song, stats=None):
    """渲染一首循环 BGM，返回 (立体声数组, 小节数)。stats 若给定，写入各声部的 RMS（dBFS，归一化前）供调混音参考。"""
    bpm = song["bpm"]
    step = 60.0 / bpm / 4.0
    form = song["form"]
    bars = 8 * len(form)
    loop_n = secs(bars * 16 * step)
    beat_n = secs(4 * step)
    size = loop_n + beat_n + secs(3.0)
    sections = {k: dict(v, notes=parse_mel(v["mel"])) for k, v in song["sections"].items()}
    kit = drum_kit(song["name"])
    tr = {k: np.zeros(size) for k in PANS}

    def put(name, sig, at_step, gain):
        i = int(round(at_step * step * SR))
        if i >= size:
            return
        end = min(size, i + len(sig))
        tr[name][i:end] += sig[: end - i] * gain

    def deg(d):
        sc = song["scale"]
        return song["root"] + sc[d % 7] + 12 * (d // 7)

    lead = song["lead"]
    drums = song["drums"]
    # 多渲染一小节（下一轮开头），供首尾 1 拍交叉淡化
    for gb in range(bars + 1):
        si = (gb // 8) % len(form)
        bi = gb % 8
        key, var = form[si]
        sec = sections[key]
        chord = sec["prog"][bi]
        s0 = gb * 16
        brk = var == "break"
        # —— 鼓
        for s in range(16):
            fill = bi == 7 and s >= 12
            if drums["kick"][s] == "x" and (not brk or s in (0, 8)):
                put("kick", kit["kick"], s0 + s, drums.get("kick_gain", 0.55))
            if fill and (not brk or s >= 12):
                put("snare", kit["snare"], s0 + s, drums.get("snare_gain", 0.6) * (0.45 + 0.15 * (s - 12)))
            elif drums["snare"][s] == "x" and not brk:
                put("snare", kit["snare"], s0 + s, drums.get("snare_gain", 0.6))
            h = drums["hat"][s]
            hg = drums.get("hat_gain", 0.22) * (0.6 if brk else 1.0) * (1.0 if s % 4 == 0 else 0.7)
            if h == "x":
                put("hat", kit["hat"], s0 + s, hg)
            elif h == "o":
                put("hat", kit["ohat"], s0 + s, hg * 0.9)
        if bi == 0:
            put("crash", kit["crash"], s0, drums.get("crash_gain", 0.18))
        # —— 贝斯
        bass = song["bass"]
        pat = "R-------O-------" if brk else bass["pattern"]
        for s, ch in enumerate(pat):
            if ch not in "ROF":
                continue
            m = {"R": deg(chord) - 24, "O": deg(chord) - 12, "F": deg(chord + 4) - 24}[ch]
            j = s + 1
            while j < 16 and pat[j] == "-":
                j += 1
            dur = (j - s) * step * 0.92 if j > s + 1 else step * 1.6
            f = mtof(m)
            sig = instrument(bass.get("wave", "tri"), f, dur, attack=0.004, decay=0.8, sustain=0.8, release=0.03)
            if bass.get("layer"):
                sig = sig + bass["layer"][1] * instrument(bass["layer"][0], f, dur, attack=0.004, decay=0.3,
                                                          sustain=0.5, release=0.03)
            put("bass", sig, s0 + s, bass.get("gain", 0.42))
        # —— 琶音
        arp = song.get("arp")
        if arp:
            for s, ch in enumerate(arp["pattern"]):
                if ch.isdigit():
                    m = deg(chord + ARP_DEG[int(ch)]) + arp.get("oct", 12)
                    sig = instrument(arp["wave"], mtof(m), step * 0.9, attack=0.003, decay=0.3, sustain=0.4,
                                     release=0.03)
                    put("arp", sig, s0 + s, arp["gain"] * (1.6 if brk else 1.0))
        # —— 和弦垫：左右各一组相互失谐的柔和锯齿
        pad = song["pad"]
        for d in (0, 2, 4):
            f = mtof(deg(chord + d) + pad.get("oct", 0))
            for name, cents in (("padL", -8.0), ("padR", 8.0)):
                sig = instrument(pad.get("wave", "saw"), f, 16 * step * 0.97, attack=0.12, decay=1.5, sustain=0.75,
                                 release=0.12, detune_cents=cents)
                put(name, sig, s0, pad["gain"])
        # —— 主旋律（break 段换成高八度的音乐盒音色）
        for pos, d, length in sec["notes"]:
            if not (bi * 16 <= pos < (bi + 1) * 16):
                continue
            at = gb * 16 + (pos - bi * 16)
            dur = length * step * (0.8 if length == 1 else 0.9)
            f = mtof(deg(d) + lead.get("oct", 0))
            if brk:
                sig = instrument(song.get("break_wave", "bell"), f * 2.0, dur, attack=0.003, decay=0.3,
                                 sustain=0.3, release=0.08)
                put("lead", sig, at, lead["gain"] * 0.6)
                continue
            sig = instrument(lead["wave"], f, dur, vib=True, duty=lead.get("duty", 0.5),
                             attack=lead.get("attack", 0.005), decay=lead.get("decay", 0.4),
                             sustain=lead.get("sustain", 0.7), release=lead.get("release", 0.03))
            put("lead", sig, at, lead["gain"])
            if var == "harm":
                fh = mtof(deg(d - 2) + lead.get("oct", 0))
                sig = instrument(song.get("harm_wave", "tri"), fh, dur, vib=True, duty=0.25, attack=0.01,
                                 decay=0.5, sustain=0.7, release=0.04)
                put("harm", sig, at, lead["gain"] * song.get("harm_gain", 0.5))

    # —— 音色修饰：频域滤波
    tr["padL"] = fft_filter(tr["padL"], lp_resp(pad.get("cut", 1400.0), 2))
    tr["padR"] = fft_filter(tr["padR"], lp_resp(pad.get("cut", 1400.0), 2))
    tr["bass"] = fft_filter(tr["bass"], lp_resp(song["bass"].get("cut", 2500.0), 2))
    tr["lead"] = fft_filter(tr["lead"], lp_resp(lead.get("cut", 7000.0), 1))
    # —— 主旋律乒乓回声（附点八分，逐次衰减、偏暗）
    d = int(round(3 * step * SR))
    fb, wet = song.get("echo", (0.35, 0.22))
    ir_l = np.zeros(d * 6 + 1)
    ir_r = np.zeros(d * 6 + 1)
    for k in range(1, 7):
        (ir_r if k % 2 else ir_l)[d * k] = wet * fb ** (k - 1)
    src = tr["lead"] + 0.5 * tr["harm"]
    src = fft_filter(src, lp_resp(3500.0, 1))
    echo_l = fft_convolve(src, ir_l, size)
    echo_r = fft_convolve(src, ir_r, size)
    if stats is not None:
        for name, sig in tr.items():
            stats[name] = lin_to_db(np.sqrt(np.mean(sig[:loop_n] ** 2)))
        stats["echo"] = lin_to_db(np.sqrt(np.mean(echo_l[:loop_n] ** 2 + echo_r[:loop_n] ** 2)))
    # —— 混到立体声
    mix = np.zeros((size, 2))
    for name, sig in tr.items():
        gl, gr = pan_gains(PANS[name])
        mix[:, 0] += sig * gl
        mix[:, 1] += sig * gr
    mix[:, 0] += echo_l
    mix[:, 1] += echo_r
    mix -= mix.mean(axis=0)
    # —— 首尾 1 拍交叉淡化：开头这一拍从「上一轮的尾音 + 本轮开头」过渡到「只有本轮开头」
    out = mix[:loop_n].copy()
    w = (0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, beat_n)))[:, None]
    out[:beat_n] = mix[:beat_n] * w + mix[loop_n:loop_n + beat_n] * (1.0 - w)
    # —— 响度：RMS -18 dBFS，限制峰值到 -3 dBFS
    thr = db_to_lin(MUSIC_PEAK_DB - 0.15)
    for _ in range(3):
        out *= db_to_lin(MUSIC_RMS_DB) / np.sqrt(np.mean(out ** 2))
        out = limit_circular(out, thr)
    out *= min(1.0, thr / np.max(np.abs(out)))
    return out, bars


# ============================================================ 曲目
# 旋律用「音阶级数/16 分音符时值」书写，级数相对曲目主音（0 = 主音，7 = 高八度主音）；
# 每段 8 小节，prog 为每小节和弦（音阶级数，三和弦）。B 段最后一小节都落在属 / 导向和弦上，回到 A 段开头的主和弦。
FORM5 = [("A", ""), ("B", ""), ("A", "break"), ("A", "harm"), ("B", "harm")]

SONGS = [
    {   # 菜单：轻快大调
        "name": "menu", "bpm": 120, "root": 60, "scale": MAJOR,
        "lead": {"wave": "square", "gain": 0.26, "oct": 0},
        "harm_wave": "pulse", "break_wave": "bell",
        "bass": {"pattern": "R...O.R.F...O...", "gain": 0.36},
        "arp": {"pattern": "0.1.2.1.0.1.2.1.", "wave": "tri", "gain": 0.16},
        "pad": {"gain": 0.06, "cut": 1300.0},
        "drums": {"kick": "x.......x.x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.o."},
        "sections": {
            "A": {"prog": [0, 5, 3, 4, 0, 5, 1, 4],
                  "mel": "2/2 4/2 7/4 6/2 4/2 2/4  5/2 7/2 9/4 8/2 7/2 5/4  3/2 5/2 7/4 5/2 7/2 8/2 7/2  6/6 5/2 4/8 "
                         "2/2 4/2 7/4 6/2 4/2 2/4  5/2 7/2 9/4 8/2 7/2 9/2 10/2  8/4 7/2 5/2 3/4 5/4  6/2 7/2 8/4 6/4 ./4"},
            "B": {"prog": [3, 4, 2, 5, 1, 4, 0, 4],
                  "mel": "7/6 8/2 7/4 5/4  6/6 7/2 6/4 4/4  4/4 6/4 9/6 8/2  7/8 ./4 5/2 7/2 "
                         "8/6 9/2 8/4 7/4  6/4 8/4 11/8  9/4 7/4 4/4 2/4  4/2 5/2 6/2 8/2 11/8"},
        },
        "form": FORM5,
    },
    {   # 村庄：明亮大调
        "name": "village", "bpm": 132, "root": 62, "scale": MAJOR,
        "lead": {"wave": "square", "gain": 0.26, "oct": 0},
        "harm_wave": "tri", "break_wave": "bell",
        "bass": {"pattern": "R.R.O.R.F.R.O.R.", "gain": 0.36},
        "arp": {"pattern": "0.1.2.1.0.1.2.1.", "wave": "tri", "gain": 0.144, "oct": 12},
        "pad": {"gain": 0.05, "cut": 1500.0},
        "drums": {"kick": "x...x...x...x...", "snare": "....x.......x..x", "hat": "x.x.x.x.x.x.x.x."},
        "sections": {
            "A": {"prog": [0, 4, 5, 3, 0, 4, 3, 4],
                  "mel": "0/2 2/2 4/2 7/2 4/4 2/2 4/2  4/2 6/2 8/4 6/2 4/2 1/4  5/2 7/2 9/4 8/2 7/2 5/4  3/4 5/4 7/6 6/2 "
                         "7/2 9/2 11/4 9/2 7/2 4/4  8/2 6/2 4/4 6/2 8/2 11/4  10/2 9/2 7/2 5/2 3/4 5/4  6/4 5/2 6/2 4/8"},
            "B": {"prog": [3, 4, 2, 5, 3, 4, 5, 4],
                  "mel": "7/3 7/3 7/2 8/4 7/4  6/3 6/3 6/2 8/4 6/4  4/3 4/3 4/2 6/2 5/2 2/4  5/8 ./4 4/2 5/2 "
                         "7/3 7/3 7/2 10/4 9/4  8/3 8/3 8/2 11/4 10/4  9/4 8/2 7/2 5/4 7/4  8/4 6/4 4/4 ./4"},
        },
        "form": FORM5,
    },
    {   # 沙漠：弗里吉亚属调式（阿拉伯风），bII → I 终止
        "name": "desert", "bpm": 124, "root": 57, "scale": PHRYG_DOM,
        "lead": {"wave": "pulse", "duty": 0.25, "gain": 0.26, "oct": 12},
        "harm_wave": "tri", "break_wave": "bell",
        "bass": {"pattern": "R..R..O.R..R..F.", "gain": 0.36},
        "arp": {"pattern": "0...2...1...2...", "wave": "tri", "gain": 0.144, "oct": 12},
        "pad": {"gain": 0.05, "cut": 1200.0},
        "drums": {"kick": "x..x..x...x..x..", "snare": "....x.......x...", "hat": "..x...x.x.x...x."},
        "sections": {
            "A": {"prog": [0, 0, 1, 0, 3, 3, 1, 0],
                  "mel": "4/3 5/1 4/2 3/2 2/2 1/2 2/4  0/6 1/2 2/4 4/4  5/3 4/1 5/2 7/2 5/2 4/2 3/4  4/8 ./4 2/2 4/2 "
                         "7/3 8/1 7/2 5/2 3/2 5/2 7/4  8/4 7/2 5/2 3/8  5/2 4/2 5/2 4/2 3/2 2/2 1/4  2/2 1/2 0/12"},
            "B": {"prog": [6, 6, 0, 0, 3, 1, 6, 1],
                  "mel": "6/2 7/2 8/2 7/2 6/4 3/4  8/2 7/2 6/2 5/2 6/8  7/2 8/2 9/2 8/2 7/4 4/4  9/2 8/2 7/2 6/2 7/8 "
                         "10/4 9/2 8/2 7/4 5/4  8/4 7/2 5/2 4/4 3/4  6/3 5/1 4/2 3/2 2/2 1/2 0/4  1/4 2/4 4/4 5/4"},
        },
        "form": FORM5,
    },
    {   # 雪山：利底亚调式，铃铛音色
        "name": "snow", "bpm": 118, "root": 64, "scale": LYDIAN,
        "lead": {"wave": "bell", "gain": 0.34, "oct": 0},
        "harm_wave": "tri", "break_wave": "tri",
        "bass": {"pattern": "R...F...O...F...", "gain": 0.36},
        "arp": {"pattern": "0121012101210121", "wave": "sine", "gain": 0.112, "oct": 24},
        "pad": {"gain": 0.065, "cut": 1100.0},
        "drums": {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "x...x...x...x.o.", "hat_gain": 0.18},
        "echo": (0.4, 0.26),
        "sections": {
            "A": {"prog": [0, 1, 0, 1, 5, 4, 1, 4],
                  "mel": "4/4 7/4 6/2 4/2 2/4  3/4 5/4 8/6 7/2  6/2 7/2 9/4 7/4 4/4  8/8 ./4 3/2 4/2 "
                         "5/4 7/4 9/2 8/2 7/4  6/4 8/4 11/8  10/2 9/2 8/2 7/2 8/4 10/4  11/6 10/2 8/8"},
            "B": {"prog": [5, 2, 1, 0, 5, 2, 1, 4],
                  "mel": "9/8 8/4 7/4  6/8 4/4 6/4  5/4 3/4 5/4 8/4  7/12 ./4 "
                         "9/4 11/4 12/4 11/4  13/8 11/4 9/4  10/6 8/2 10/4 12/4  11/16"},
        },
        "form": FORM5,
    },
    {   # 森林：多利亚调式，木管感方波
        "name": "forest", "bpm": 126, "root": 62, "scale": DORIAN,
        "lead": {"wave": "wood", "gain": 0.34, "oct": 0, "attack": 0.025, "sustain": 0.85, "decay": 0.6,
                 "release": 0.05},
        "harm_wave": "pulse", "break_wave": "bell",
        "bass": {"pattern": "R..O..F.R..O..F.", "gain": 0.36},
        "arp": {"pattern": "0.2.1.2.0.2.1.2.", "wave": "tri", "gain": 0.128, "oct": 12},
        "pad": {"gain": 0.055, "cut": 1200.0},
        "drums": {"kick": "x.....x...x.....", "snare": "....x.......x...", "hat": "x.xxx.xxx.xxx.xx", "hat_gain": 0.17},
        "sections": {
            "A": {"prog": [0, 3, 0, 3, 6, 2, 3, 4],
                  "mel": "4/2 7/2 6/2 7/2 4/4 2/2 3/2  5/4 4/2 3/2 1/4 ./2 3/2  4/2 7/2 6/2 7/2 9/4 8/2 7/2  8/6 7/2 5/8 "
                         "6/2 7/2 8/2 9/2 8/4 6/4  9/2 8/2 7/2 6/2 7/4 9/4  10/4 9/2 8/2 7/2 5/2 3/4  4/6 3/2 4/8"},
            "B": {"prog": [2, 6, 0, 3, 2, 6, 3, 4],
                  "mel": "9/2 9/2 8/2 7/2 6/4 4/4  6/2 6/2 7/2 8/2 7/8  7/2 9/2 11/4 9/2 7/2 4/4  5/6 6/2 7/8 "
                         "9/2 11/2 10/2 9/2 8/4 9/4  8/2 7/2 6/2 4/2 6/8  5/4 7/4 10/4 8/4  7/4 6/4 4/8"},
        },
        "form": FORM5,
    },
    {   # 赛车场：有推进感的摇滚合成器
        "name": "circuit", "bpm": 140, "root": 64, "scale": MINOR,
        "lead": {"wave": "saw", "gain": 0.42, "oct": 0, "cut": 5000.0},
        "harm_wave": "square", "harm_gain": 0.3, "break_wave": "bell",
        "bass": {"pattern": "R.R.R.R.R.R.O.R.", "gain": 0.34, "layer": ("saw", 0.35), "cut": 1400.0},
        "arp": {"pattern": "4.2.0.2.4.2.0.2.", "wave": "square", "gain": 0.08, "oct": 12},
        "pad": {"gain": 0.06, "cut": 2200.0, "oct": -12},
        "drums": {"kick": "x.....x.x.....x.", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
                  "kick_gain": 0.6, "snare_gain": 0.65},
        "sections": {
            "A": {"prog": [0, 5, 2, 6, 0, 5, 2, 6],
                  "mel": "7/2 7/2 6/2 7/4 9/2 7/2 6/2  4/6 5/2 4/4 2/4  4/2 4/2 5/2 6/4 7/2 6/2 4/2  6/6 5/2 3/8 "
                         "7/2 7/2 6/2 7/4 9/2 11/4  12/6 11/2 9/4 7/4  9/4 8/2 9/2 11/4 13/4  13/2 12/2 11/2 10/2 8/8"},
            "B": {"prog": [3, 0, 5, 6, 3, 0, 5, 6],
                  "mel": "3/3 5/3 7/2 5/3 3/3 5/2  4/3 7/3 4/2 2/8  5/3 7/3 9/2 7/3 5/3 7/2  8/8 6/4 8/4 "
                         "10/3 9/3 7/2 10/3 9/3 7/2  11/6 9/2 7/8  12/4 11/4 9/4 7/4  8/4 6/4 8/4 10/4"},
        },
        "form": FORM5,
    },
    {   # 城市夜景：合成器浪潮小调，琶音
        "name": "city", "bpm": 128, "root": 57, "scale": MINOR,
        "lead": {"wave": "saw", "gain": 0.42, "oct": 12, "cut": 3800.0, "attack": 0.012, "release": 0.08},
        "harm_wave": "pulse", "harm_gain": 0.3, "break_wave": "bell",
        "bass": {"pattern": "R.O.R.O.R.O.F.O.", "gain": 0.34, "layer": ("saw", 0.3), "cut": 1100.0},
        "arp": {"pattern": "0123012301230123", "wave": "square", "gain": 0.072, "oct": 12},
        "pad": {"gain": 0.075, "cut": 1600.0},
        "drums": {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "..x...x...x...x.", "hat_gain": 0.26},
        "echo": (0.42, 0.28),
        "sections": {
            "A": {"prog": [0, 5, 2, 6, 0, 5, 2, 6],
                  "mel": "4/4 7/4 6/6 4/2  5/12 4/2 2/2  4/4 7/4 9/6 8/2  6/12 ./4 "
                         "4/4 7/4 6/6 4/2  5/4 7/4 9/6 10/2  11/6 9/2 7/8  8/8 6/8"},
            "B": {"prog": [5, 6, 4, 0, 5, 6, 2, 6],
                  "mel": "5/2 5/2 7/2 5/2 9/4 8/4  6/2 6/2 8/2 6/2 10/4 9/4  7/6 6/2 4/8  4/4 2/4 0/8 "
                         "9/2 9/2 11/2 9/2 12/4 11/4  10/2 10/2 12/2 10/2 13/4 12/4  11/8 9/4 7/4  8/8 6/4 8/4"},
        },
        "form": FORM5,
    },
    {   # 城镇手指：F 大调，轻快的街头风
        "name": "town", "bpm": 128, "root": 65, "scale": MAJOR,
        "lead": {"wave": "square", "gain": 0.24, "oct": 0},
        "harm_wave": "pulse", "break_wave": "bell",
        "bass": {"pattern": "R...O.R.F.R.O...", "gain": 0.36},
        "arp": {"pattern": "0.2.1.2.0.2.1.2.", "wave": "tri", "gain": 0.14, "oct": 12},
        "pad": {"gain": 0.05, "cut": 1500.0},
        "drums": {"kick": "x.......x.x.....", "snare": "....x.......x...", "hat": "x.xxx.xxx.xxx.x."},
        "sections": {
            "A": {"prog": [0, 5, 3, 4, 0, 2, 3, 4],
                  "mel": "4/2 4/2 4/2 7/2 9/4 7/4  9/2 8/2 7/2 5/2 4/8  3/2 5/2 7/4 8/2 7/2 5/4  6/4 4/4 8/6 ./2 "
                         "4/2 4/2 4/2 7/2 9/4 11/4  11/2 10/2 9/2 8/2 9/8  10/4 9/2 7/2 5/4 7/4  8/6 6/2 4/8"},
            "B": {"prog": [3, 4, 2, 5, 1, 4, 0, 4],
                  "mel": "7/3 7/3 7/2 10/4 9/4  8/3 8/3 8/2 11/4 10/4  9/4 8/2 6/2 4/8  5/4 7/4 9/8 "
                         "8/3 8/3 8/2 10/4 8/4  11/6 10/2 8/8  7/2 9/2 11/2 14/2 11/4 9/4  8/4 6/4 4/8"},
        },
        "form": FORM5,
    },
    {   # 森林发卡：G 混合利底亚，冒险感的盘山路
        "name": "hairpin", "bpm": 142, "root": 55, "scale": MIXO,
        "lead": {"wave": "pulse", "duty": 0.25, "gain": 0.26, "oct": 12},
        "harm_wave": "tri", "break_wave": "wood",
        "bass": {"pattern": "R.R.O.R.R.R.F.O.", "gain": 0.36},
        "arp": {"pattern": "0.1.2.1.0.1.2.1.", "wave": "square", "gain": 0.08, "oct": 12},
        "pad": {"gain": 0.055, "cut": 1400.0},
        "drums": {"kick": "x...x...x...x.x.", "snare": "....x.......x...", "hat": "x.x.xxx.x.x.xxx."},
        "sections": {
            "A": {"prog": [0, 6, 3, 0, 0, 6, 3, 4],
                  "mel": "7/2 9/2 11/4 9/2 7/2 4/4  6/2 8/2 10/4 8/2 6/2 3/4  5/2 7/2 10/4 9/2 7/2 5/4  4/6 2/2 0/8 "
                         "7/2 9/2 11/4 12/2 11/2 9/4  10/2 11/2 13/4 11/2 10/2 8/4  10/4 12/4 14/4 12/4  11/6 10/2 8/8"},
            "B": {"prog": [5, 3, 0, 6, 5, 3, 1, 4],
                  "mel": "9/3 9/3 9/2 12/4 11/4  10/3 10/3 10/2 12/4 10/4  9/4 7/4 11/8  10/4 8/4 6/8 "
                         "12/2 11/2 9/2 7/2 9/4 12/4  14/6 12/2 10/8  8/2 10/2 12/4 10/2 8/2 5/4  8/4 6/4 4/4 6/4"},
        },
        "form": FORM5,
    },
    {   # 结算：凯旋，可循环
        "name": "results", "bpm": 110, "root": 60, "scale": MAJOR,
        "lead": {"wave": "square", "gain": 0.26, "oct": 0},
        "harm_wave": "pulse", "break_wave": "bell",
        "bass": {"pattern": "R...O...F...O...", "gain": 0.36},
        "arp": {"pattern": "0.1.2.1.0.1.2.1.", "wave": "tri", "gain": 0.144, "oct": 12},
        "pad": {"gain": 0.06, "cut": 1400.0},
        "drums": {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."},
        "sections": {
            "A": {"prog": [0, 3, 4, 0, 5, 3, 1, 4],
                  "mel": "0/2 0/1 0/1 4/4 4/2 4/1 4/1 7/4  5/6 3/2 5/4 7/4  6/4 8/4 11/6 8/2  7/12 ./4 "
                         "9/2 9/1 9/1 7/4 5/4 7/4  10/6 9/2 8/4 7/4  8/4 10/4 12/4 10/4  11/12 ./4"},
            "B": {"prog": [3, 4, 2, 5, 3, 4, 0, 4],
                  "mel": "7/4 9/4 10/4 12/4  11/6 10/2 8/8  9/4 11/4 13/4 11/4  12/8 9/8 "
                         "10/4 12/4 14/4 12/4  13/4 11/4 8/4 6/4  7/2 9/2 11/2 14/2 11/4 9/4  8/4 6/4 4/8"},
        },
        "form": [("A", ""), ("B", ""), ("A", "harm"), ("B", "harm")],
    },
]
MUSIC_NAMES = [s["name"] for s in SONGS]


# ============================================================ 主程序

def main():
    ap = argparse.ArgumentParser(description="合成 GALE KART 的全部音效与 BGM")
    ap.add_argument("--only", default="", help="逗号分隔的名字，只生成这些")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    ffmpeg = find_ffmpeg()
    work = os.environ.get("AUDIO_WORK_DIR") or tempfile.mkdtemp(prefix="gale_audio_")
    os.makedirs(work, exist_ok=True)
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)
    print("ffmpeg: %s\n中间文件: %s" % (ffmpeg, work))

    rows = []
    for name in SFX_NAMES:
        if only and name not in only:
            continue
        loop = name in LOOPS
        data = LOOPS[name]() if loop else render_oneshot(name)
        rows.append(("sfx", export(ffmpeg, work, SFX_DIR, name, data, SFX_PEAK_DB, loop=loop)))
    for song in SONGS:
        if only and song["name"] not in only:
            continue
        data, bars = render_song(song)
        info = export(ffmpeg, work, MUSIC_DIR, song["name"], data, MUSIC_PEAK_DB, loop=True)
        info["bpm"] = song["bpm"]
        info["bars"] = bars
        rows.append(("music", info))

    print("\n%-6s %-15s %9s %8s %8s %8s %9s %s" % ("类型", "名字", "时长(s)", "峰值dB", "RMS dB", "KB", "循环跳变", "备注"))
    problems = []
    total = 0
    for kind, r in rows:
        total += r["bytes"]
        seam = "%.2f/%.2f" % (r["seam_src"], r["seam_ogg"]) if "seam_src" in r else ""
        note = "%d BPM × %d 小节" % (r["bpm"], r["bars"]) if kind == "music" else ""
        print("%-6s %-15s %9.3f %8.2f %8.2f %8.1f %9s %s" % (kind, r["name"], r["dur"], r["peak_db"], r["rms_db"],
                                                          r["bytes"] / 1024.0, seam, note))
        limit = SFX_PEAK_DB if kind == "sfx" else MUSIC_PEAK_DB
        if r["peak_db"] > limit + 0.1:
            problems.append("%s 峰值 %.2f dBFS 超标" % (r["name"], r["peak_db"]))
        if r["name"] in LOOPS and r["samples"] != SR:
            problems.append("%s 长度 %d 采样，不是 1.0 s" % (r["name"], r["samples"]))
        if "seam_src" in r and r["seam_src"] > 3.0:
            problems.append("%s 循环点跳变偏大（%.2f）" % (r["name"], r["seam_src"]))
    print("\n共 %d 个文件，%.1f KB" % (len(rows), total / 1024.0))
    print("循环跳变 = |首采样 - 尾采样| / 平均相邻采样差（源 / OGG 解码），≈1 表示与普通位置一样平滑")
    if problems:
        print("\n问题：\n  " + "\n  ".join(problems))
        sys.exit(1)
    print("全部检查通过")


if __name__ == "__main__":
    main()
