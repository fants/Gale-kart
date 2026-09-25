#!/bin/zsh
# 双击启动「疾风卡丁 GALE KART」（需要已安装 Godot 4.7：brew install --cask godot）
cd "$(dirname "$0")"
GODOT="$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)"
exec "$GODOT" --path . "$@"
