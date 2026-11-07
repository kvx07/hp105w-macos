#!/usr/bin/env bash
# uninstall.sh — 移除系统队列与过滤器（保留 build/ 与源码，随时可重装）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRINTER="${HP105W_QUEUE:-HP_Laser_105w_SPL}"
FILTER_DIR="/usr/libexec/cups/filter"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

say "删除队列 $PRINTER"
lpadmin -x "$PRINTER" 2>/dev/null || true

for f in rastertoqpdl pstoqpdl; do
  if [ -e "$FILTER_DIR/$f" ]; then
    say "移除过滤器 $FILTER_DIR/${f}（需要管理员密码）"
    sudo rm -f "$FILTER_DIR/$f"
  fi
done

echo
say "剩余打印队列："
lpstat -p 2>&1 | head -10
