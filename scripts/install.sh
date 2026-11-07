#!/usr/bin/env bash
# install.sh — 把自写驱动装成 macOS 打印队列（唯一需要 root 的一步）
#
#   ./scripts/install.sh                  # 自动发现打印机
#   ./scripts/install.sh 192.168.31.194   # 指定 IP / 主机名
#   ./scripts/install.sh --dry-run        # 只打印将执行的命令
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRINTER="HP_Laser_105w_SPL"
FILTER_DIR="/usr/libexec/cups/filter"
PPD="$ROOT/ppd/HP_Laser_105w.ppd"
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"
DRY=0
HOST=""

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '    [dry-run] %s\n' "$*"; else "$@"; fi; }

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) HOST="$arg" ;;
  esac
done

[ -x "$ROOT/bin/vendor/rastertoqpdl" ] || die "还没编译：先运行 ./scripts/build.sh"
[ -f "$PPD" ] || die "缺少 PPD：先运行 ./scripts/build.sh"

# ---------------------------------------------------------------- 发现打印机
if [ -z "$HOST" ]; then
  say "自动发现打印机（Bonjour）"
  HOST="$(hp105w_discover_host 4 || true)"
fi
[ -n "$HOST" ] || die "没发现打印机。请显式指定： ./scripts/install.sh <打印机IP>"

say "目标打印机: $HOST"
if ! nc -z -G 3 "$HOST" 9100 >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then
    printf '    [dry-run] 警告: 连不上 %s:9100（dry-run 仍继续）\n' "$HOST"
  else
    die "连不上 $HOST:9100 —— 确认打印机已开机并连到同一 Wi-Fi"
  fi
fi

# ---------------------------------------------------------------- 安装
say "1/4 安装 CUPS 过滤器到 ${FILTER_DIR}（需要管理员密码）"
run sudo install -o root -g wheel -m 0755 "$ROOT/bin/vendor/rastertoqpdl" "$FILTER_DIR/rastertoqpdl"
run sudo install -o root -g wheel -m 0755 "$ROOT/bin/vendor/pstoqpdl"    "$FILTER_DIR/pstoqpdl"

say "2/4 创建队列 $PRINTER"
run lpadmin -p "$PRINTER" -E -v "socket://$HOST:9100" -P "$PPD" \
      -D "HP Laser 105w (SPL/QPDL driver)" -L "LAN" \
      -o printer-is-shared=false -o media=A4

say "3/4 设为默认打印机"
run lpadmin -d "$PRINTER"
run lpoptions -d "$PRINTER"

say "4/4 打印自检页"
if [ "$DRY" = 1 ]; then
  printf '    [dry-run] lp -d %s -o media=A4 /tmp/hp105w-selftest.txt\n' "$PRINTER"
else
  printf 'HP Laser 105w  SPL/QPDL driver  installed %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
    > /tmp/hp105w-selftest.txt
  lp -d "$PRINTER" -o media=A4 -t "driver install selftest" /tmp/hp105w-selftest.txt
fi

echo
if [ "$DRY" = 1 ]; then
  say "dry-run 结束。去掉 --dry-run 真正安装。"
else
  say "完成。任何 App 的打印对话框里都能选到「HP Laser 105w (SPL/QPDL driver)」。"
  lpstat -p "$PRINTER" 2>&1 | head -2
fi
