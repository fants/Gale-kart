# 疾风卡丁 GALE KART（Godot 版）

仿照跑跑卡丁车的 3D 卡丁车竞速游戏，用 Godot 4.7 制作：漂移、集气、氮气、瞬间加速（小喷）、起步加速、尾流、跳台飞跃、加速带、道具战，另有精彩回放。

## 运行

1. 安装 Godot 4.7（`brew install --cask godot`）。
2. 双击 `开始游戏.command`，或在终端运行 `godot --path .`；也可以用 Godot 编辑器打开项目后按 F5。

## 内容

- **4 种模式**：竞速赛（漂移集气放氮气）、道具赛（10 种道具）、计时赛（最佳一局保存为幽灵车，实时显示差距）、大奖赛（新星杯 / 疾风杯，各 3 场，积分制）
- **6 条赛道**：阳光小镇 ★、黄金沙漠 ★★（沙丘 + 两处跳台）、冰雪乐园 ★★（冰面低抓地）、森林峡谷 ★★（大落差 + 飞越河流的大跳台）、疾风赛车场 ★★（夕阳下的正规赛道）、霓虹夜城 ★★★（8 字立交）
- **5 款赛车**（极速 / 加速 / 操控 / 漂移 / 氮气 / 重量各不相同）× **12 位车手** × **5 种涂装**
- **7 位 AI 对手**，简单 / 普通 / 困难三档，1 / 3 / 5 圈
- **道具**：氮气、导弹、水炸弹、香蕉皮、天使护盾、乌云、磁铁、雷暴、飞碟、水苍蝇；按名次加权发放
- **精彩回放**：电视转播 / 追尾 / 环绕 / 俯瞰机位，自动导播，可变速、暂停、切换焦点车，一键隐藏界面，方便录视频
- 全部音效与 8 首 BGM 离线合成；模型来自 Kenney（CC0），字体 ZCOOL KuaiLe / Bungee（OFL）

## 操作

| 动作 | 键盘 | 手柄 |
|---|---|---|
| 加速 / 刹车·倒车 | ↑ ↓ 或 W S | RT / LT |
| 转向 | ← → 或 A D | 左摇杆 / 十字键 |
| 漂移 | Shift 或 J | B / RB |
| 氮气 / 道具 | 空格 或 K | A |
| 交换道具 | Q 或 E | X |
| 复位 | R | Y |
| 切换视角 | C | Back |
| 暂停 | Esc 或 P | Start |
| 隐藏 HUD | H | — |
| 静音 | M | — |
| 全屏 | F11 | — |

技巧：
- **瞬间加速（小喷）**：漂移超过 0.35 秒后松开 Shift，屏幕出现「↑」时松开再按一次 ↑。设置里可以开「自动小喷」。
- **起步加速**：倒计时 GO 出现前 0.35 秒内或 GO 之后 0.3 秒内第一次按下 ↑；在最后 1 秒里按早了会抢跑打滑。
- **尾流**：紧跟前车（正后方 3–14 米）约 1 秒会获得一次尾流加速。

回放操作：1–4 切换机位（0 自动导播）、← → 切换焦点车、空格暂停、[ ] 变速、H 隐藏界面、Esc 退出。

## 开发

```bash
godot --headless --path . --import                 # 首次导入素材
godot --headless --path . -s tests/run_tests.gd    # 全部自动化测试（退出码 = 失败数）
godot --headless --path . -s tests/tools/sim_race.gd -- --track=all --mode=speed   # 无界面整场 AI 比赛
godot --headless --path . -s tests/tools/handling.gd      # 每款车的操控数据
godot --headless --path . -s tests/tools/keyboard_bot.gd  # 模拟键盘玩家跑完所有赛道
python3 tools/gen_audio.py                                # 重新合成全部音效与音乐

# 调试 / 截图 / 演示：直接开一场无人驾驶的比赛并定时截图
godot --path . --fixed-fps 60 -- --race=forest --mode=item --autopilot --shots=5,20 --out=/tmp/shots --quit-after=21 --size=1920x1080
```

结构：`src/sim/` 是与渲染无关的仿真层（120 Hz 固定子步，可无界面运行，移植自网页版参考实现），`src/view/` 是 3D 表现层，`src/race/` 是比赛总控、事件分发与回放，`src/ui/` 是 HUD 与菜单，`src/autoload/` 是全局流程、存档、音频。设计文档见 `docs/superpowers/specs/2026-09-26-gale-kart-godot-design.md`。
