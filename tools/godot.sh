#!/usr/bin/env bash
# Godot 启动包装：把 Godot 的用户目录指到工作区内的 .ghome，
# 避免写入 ~/Library/Application Support（在沙箱 / CI 下会被拒绝并导致引擎崩溃）。
#
# 用法：
#   ./tools/godot.sh --headless --script res://tools/balance_sim.gd
#   ./tools/godot.sh --headless --script res://tools/run_tests.gd
#   ./tools/godot.sh --headless --import

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

# HOME 会被 Godot 用来拼 user:// 路径（macOS 上即 $HOME/Library/Application Support/Godot）
HOME="$PROJECT_DIR/.ghome" \
XDG_DATA_HOME="$PROJECT_DIR/.ghome/data" \
XDG_CONFIG_HOME="$PROJECT_DIR/.ghome/config" \
  exec "$GODOT_BIN" --path "$PROJECT_DIR" "$@"
