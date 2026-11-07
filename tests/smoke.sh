#!/usr/bin/env bash
# smoke.sh — 不需要打印机的自检（CI 也跑这个）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FAILED=0
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAILED=$((FAILED+1)); }
head_() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }

head_ "1. Bash 语法"
for f in bin/hp105w-print scripts/*.sh tests/smoke.sh; do
  if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f 语法错误"; bash -n "$f"; fi
done

head_ "2. shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -S warning bin/hp105w-print scripts/*.sh; then ok "shellcheck 通过"; else bad "shellcheck 有告警"; fi
else
  printf '  · 未安装 shellcheck，跳过（brew install shellcheck）\n'
fi

head_ "3. PPD 合法性"
if command -v cupstestppd >/dev/null; then
  if cupstestppd -q ppd/HP_Laser_105w.ppd; then ok "ppd/HP_Laser_105w.ppd"; else bad "PPD 未通过校验"; fi
else
  printf '  · 缺少 cupstestppd，跳过\n'
fi

head_ "4. CLI 基本行为"
V_OUT="$(./bin/hp105w-print --version 2>&1 || true)"
case "$V_OUT" in *hp105w-print*) ok "--version" ;; *) bad "--version" ;; esac

H_OUT="$(./bin/hp105w-print --help 2>&1 || true)"
case "$H_OUT" in *用法*) ok "--help" ;; *) bad "--help" ;; esac

./bin/hp105w-print >/dev/null 2>&1
[ $? -eq 2 ] && ok "无参数时返回 2" || bad "无参数退出码不对"

head_ "5. 转换链（不发给打印机）"
if [ -x bin/vendor/rastertoqpdl ]; then
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/hp105w-smoke.XXXXXX")"
  printf 'smoke test 自检\n' > "$TMP/a.txt"
  cupsfilter -i text/plain -m application/pdf "$TMP/a.txt" > "$TMP/a.pdf" 2>/dev/null
  OUT="$(./bin/hp105w-print -n "$TMP/a.pdf" 2>&1)"
  case "$OUT" in
    *"已生成"*) ok "PDF → QPDL 转换成功" ;;
    *) bad "转换失败: $OUT" ;;
  esac
  # 校验 QPDL 头部（PJL 起手 + SPL 数据）
  SPL="$(printf '%s\n' "$OUT" | sed -n 's/.*转换产物: //p' | head -1)"
  if [ -n "$SPL" ] && ls "$SPL"/*.spl >/dev/null 2>&1; then
    head -c 10 "$SPL"/*.spl | grep -q "%-12345X" && ok "产物以 PJL 头开始" || bad "产物头部异常"
  else
    printf '  · 未取到产物路径，跳过头部校验\n'
  fi
  rm -rf "$TMP"
else
  printf '  · 尚未编译（make build），跳过转换测试\n'
fi

head_ "6. 安装脚本 dry-run"
INST_OUT="$(./scripts/install.sh --dry-run 192.0.2.1 2>&1 || true)"
case "$INST_OUT" in
  *dry-run*) ok "install.sh --dry-run" ;;
  *)         bad "install.sh --dry-run" ;;
esac

echo
if [ "$FAILED" -eq 0 ]; then
  printf '\033[1;32m全部通过\033[0m\n'; exit 0
else
  printf '\033[1;31m%d 项失败\033[0m\n' "$FAILED"; exit 1
fi
