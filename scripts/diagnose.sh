#!/usr/bin/env bash
# diagnose.sh — 复现「为什么打不出来」的取证流程
#
#   ./scripts/diagnose.sh                 # 自动发现打印机，做基础体检
#   ./scripts/diagnose.sh 192.168.31.194  # 指定 IP
#   ./scripts/diagnose.sh --probe         # 额外做「固件接受哪些打印语言」探测
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST=""
PROBE=0
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"
OK=0; BAD=0

c_ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
c_bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }
c_info() { printf '  · %s\n' "$*"; }
h()      { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
pass()   { OK=$((OK+1)); c_ok "$*"; }
fail()   { BAD=$((BAD+1)); c_bad "$*"; }

for a in "$@"; do
  case "$a" in
    --probe) PROBE=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) HOST="$a" ;;
  esac
done

# ---------------------------------------------------------------- 1. 发现
h "1. 打印机发现（Bonjour / mDNS）"
URIS="$(hp105w_ipp_uris 4 || true)"
[ -n "$URIS" ] && printf '%s\n' "$URIS" | sed 's/^/  · /'
if [ -z "$HOST" ]; then
  HOST="$(hp105w_discover_host 4 || true)"
fi
if [ -z "$HOST" ]; then
  fail "没发现任何 IPP 打印机。检查：打印机与 Mac 是否同一 Wi-Fi"
  exit 1
fi
pass "使用打印机地址: $HOST"

# ---------------------------------------------------------------- 2. 端口
h "2. 网络可达性"
for p in 80 515 631 9100; do
  if nc -z -G 2 "$HOST" "$p" >/dev/null 2>&1; then pass "端口 $p 开放"; else c_info "端口 $p 未开放"; fi
done

# ---------------------------------------------------------------- 3. IPP
h "3. IPP 身份与状态"
ATTR="$(ipptool -tv "ipp://$HOST:631/ipp/print" \
        /usr/share/cups/ipptool/get-printer-attributes.test 2>/dev/null || true)"
if [ -z "$ATTR" ]; then
  fail "IPP 无响应（打印机可能不在 IPP 模式）"
else
  for k in "printer-make-and-model" "printer-state " "printer-state-reasons" \
           "document-format-supported" "printer-device-id" "marker-levels"; do
    v="$(printf '%s\n' "$ATTR" | grep -F "$k" | head -1 | sed 's/^ *//')"
    [ -n "$v" ] && printf '  · %s\n' "$v"
  done
  printf '%s\n' "$ATTR" | grep -q "printer-state (enum) = idle" \
    && pass "打印机空闲、可接受作业" || fail "打印机不在 idle 状态"

  DEV_ID="$(printf '%s\n' "$ATTR" | grep -F "printer-device-id" | head -1)"
  case "$DEV_ID" in
    *SPL3*|*SPL,*) pass "固件打印语言含 SPL（三星 QPDL 机芯）" ;;
    *) c_info "device-id 未声明 SPL，仍可能是 HP 定制固件" ;;
  esac
  case "$DEV_ID" in
    *PCL5*|*PCLXL*|*PCL6*) c_info "固件声明支持 PCL —— 通用 PCL 驱动可能可用" ;;
  esac
  DT="$(printf '%s\n' "$ATTR" | grep -F "document-format-supported" | head -1)"
  c_info "固件声明接受的格式: ${DT#*= }"
fi

# ---------------------------------------------------------------- 4. 计数器
h "4. 页计数器（判断是否真的出纸的唯一硬指标）"
CNT="$(snmpwalk -v1 -c public -t 3 -r 1 "$HOST" 1.3.6.1.2.1.43.10.2.1.4 2>/dev/null \
       | tail -1 | grep -oE '[0-9]+$' || true)"
if [ -n "${CNT:-}" ]; then
  pass "prtMarkerLifeCount = ${CNT}（打印前后对比这个数字）"
else
  c_info "SNMP 未响应，无法读取页计数器（不影响打印）"
fi

# ---------------------------------------------------------------- 5. 本机队列
h "5. 本机 CUPS 队列"
lpstat -p 2>/dev/null | sed 's/^/  /'
DEF_NAME="$(lpstat -d 2>/dev/null | sed -n 's/.*：//p')"
if [ -n "${DEF_NAME:-}" ]; then pass "默认打印机: ${DEF_NAME}"; else c_info "没有设置默认打印机"; fi
if lpstat -p 2>/dev/null | grep -q "HP_Laser_105w_SPL"; then
  URI="$(lpstat -v HP_Laser_105w_SPL 2>/dev/null | sed 's/.*：//')"
  pass "自写驱动队列存在: $URI"
  [ -e /usr/libexec/cups/filter/rastertoqpdl ] \
    && pass "过滤器已安装: /usr/libexec/cups/filter/rastertoqpdl" \
    || fail "过滤器缺失 —— 重新执行 ./scripts/install.sh"
else
  c_info "未安装自写驱动队列（运行 ./scripts/install.sh 安装）"
fi

# ---------------------------------------------------------------- 6. 探测
if [ "$PROBE" = 1 ]; then
  h "6. 固件接受哪些打印语言（逐个投递）"
  [ -x "$ROOT/bin/vendor/rastertoqpdl" ] || { fail "缺少编码器，跳过探测（先 ./scripts/build.sh）"; }
  if [ -x "$ROOT/bin/vendor/rastertoqpdl" ]; then
    W="$(mktemp -d "${TMPDIR:-/tmp}/hp105w-probe.XXXXXX")"
    printf 'HP Laser 105w format probe\n' > "$W/p.txt"
    cupsfilter -i text/plain -m application/pdf "$W/p.txt" > "$W/p.pdf" 2>/dev/null
    cupsfilter -p "$ROOT/ppd/HP_Laser_105w.ppd" -m application/vnd.cups-raster \
      -o media=A4 -o Resolution=300dpi "$W/p.pdf" > "$W/p.raster" 2>/dev/null
    /usr/libexec/cups/filter/rastertourf 1 "$(id -un)" p 1 "" "$W/p.raster" > "$W/p.urf" 2>/dev/null
    /usr/libexec/cups/filter/rastertopwg  1 "$(id -un)" p 1 "" "$W/p.raster" > "$W/p.pwg" 2>/dev/null

    probe() { # format file
      [ -s "$2" ] || { c_info "$1（样本生成失败，跳过）"; return; }
      r="$(ipptool -tv -d filetype="$1" -f "$2" "ipp://$HOST/ipp/print" \
            /usr/share/cups/ipptool/print-job.test 2>/dev/null \
            | grep -oE 'client-error[a-z-]*|successful-ok[a-z-]*' | head -1)"
      case "$r" in
        successful-ok*) pass "$1 被接受" ;;
        *)             fail "$1 → ${r:-无响应}" ;;
      esac
    }
    probe application/pdf        "$W/p.pdf"
    probe image/urf              "$W/p.urf"
    probe image/pwg-raster       "$W/p.pwg"
    rm -rf "$W"
    c_info "以上全部被拒 = 固件只认 SPL/QPDL，与本项目方案一致"
  fi
fi

# ---------------------------------------------------------------- 结论
h "结论"
printf '  通过 %d 项，异常 %d 项\n' "$OK" "$BAD"
if [ "$BAD" -eq 0 ]; then
  printf '  \033[1;32m链路正常。\033[0m 若仍不出纸：确认队列是否为 HP_Laser_105w_SPL，并看页计数器是否 +1。\n'
else
  printf '  \033[1;33m有异常项。\033[0m 先解决网络/队列问题；若网络正常但格式全被拒，属于 PDL 不匹配，用本项目驱动。\n'
fi
exit 0
