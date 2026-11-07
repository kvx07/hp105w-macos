#!/usr/bin/env bash
# make-app.sh — 由 AppleScript 源编译出可拖拽的 .app（无需 root）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/HP105w-Print.app"
SRC="$ROOT/app/HP105w-Print.applescript"

[ -f "$SRC" ] || { echo "缺少 $SRC" >&2; exit 1; }
rm -rf "$OUT"
osacompile -o "$OUT" "$SRC"
echo "已生成: ${OUT}（可拖到「应用程序」或程序坞）"
