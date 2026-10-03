#!/usr/bin/env bash
# Godot 启动包装。做两件事：
#
#   1) 把 Godot 的用户目录指到工作区内的 .ghome，避免写入
#      ~/Library/Application Support（沙箱 / CI 下会被拒绝并导致引擎崩溃）。
#
#   2) **首次运行时先补一次 --import。**
#      新 clone 没有 .godot/，Godot 还没索引 class_name 全局类，
#      直接跑 --script 会报 "Identifier not declared"。
#      这个坑本地永远撞不到（本地一直带着 .godot/），只有别人 clone 下来才会遇到 ——
#      实测过：干净 clone 直接跑 137 项测试会 parse error，补一次 --import 就全过。
#
# 用法：
#   ./tools/godot.sh --headless --script res://tools/balance_sim.gd
#   ./tools/godot.sh --headless --script res://tools/run_tests.gd
#   ./tools/godot.sh --headless --import
#   ./tools/godot.sh                        # 直接跑游戏

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 找 Godot：优先 $GODOT_BIN，其次几个常见安装位置。
# 硬编码单一平台路径会让别人 clone 下来第一步就跑不动。
find_godot() {
  if [ -n "${GODOT_BIN:-}" ]; then
    printf '%s' "$GODOT_BIN"
    return
  fi
  local candidates=(
    "/Applications/Godot.app/Contents/MacOS/Godot"
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
    "/usr/local/bin/godot"
    "/opt/homebrew/bin/godot"
    "/usr/bin/godot"
    "$HOME/.local/bin/godot"
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return; fi
  done
  # 最后试 PATH
  command -v godot 2>/dev/null || true
}

GODOT_BIN="$(find_godot)"

if [ -z "$GODOT_BIN" ] || [ ! -x "$GODOT_BIN" ]; then
  cat >&2 <<'MSG'
找不到 Godot 可执行文件。请二选一：
  1) 装好 Godot 4.7+ 并放进 PATH
  2) 用环境变量指定：GODOT_BIN=/path/to/godot ./tools/godot.sh ...
MSG
  exit 1
fi

mkdir -p "$PROJECT_DIR/.ghome"

# 所有调用都走同一套环境变量，别写两遍 —— 写两遍迟早漏一处
# HOME 会被 Godot 用来拼 user:// 路径（macOS 上即 $HOME/Library/Application Support/Godot）
run_godot() {
  HOME="$PROJECT_DIR/.ghome" \
  XDG_DATA_HOME="$PROJECT_DIR/.ghome/data" \
  XDG_CONFIG_HOME="$PROJECT_DIR/.ghome/config" \
    "$GODOT_BIN" --path "$PROJECT_DIR" "$@"
}

# --------------------------------------------- 首次运行先建索引
# 判据用 global_script_class_cache.cfg：它正是 class_name 全局类的索引文件，
# 比只看 .godot/ 目录在不在更准（空目录会被误判成"已索引"）。
wants_import=0
for arg in "$@"; do
  [ "$arg" = "--import" ] && wants_import=1
done

if [ "$wants_import" -eq 0 ] && [ ! -f "$PROJECT_DIR/.godot/global_script_class_cache.cfg" ]; then
  echo "[godot.sh] 首次运行：正在生成项目索引（--import）……" >&2
  run_godot --headless --import >/dev/null 2>&1 || true
fi

run_godot "$@"
