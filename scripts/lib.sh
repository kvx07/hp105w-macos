#!/usr/bin/env bash
# lib.sh — 公用函数，被 bin/hp105w-print、scripts/install.sh、scripts/diagnose.sh source
# 兼容 macOS 自带 bash 3.2

HP105W_IPP_TEST="/usr/share/cups/ipptool/get-printer-attributes.test"

# 列出所有 IPP 打印机 URI（ippfind 的 -T 是超时秒数）
hp105w_ipp_uris() {
  command -v ippfind >/dev/null 2>&1 || return 1
  ippfind -T "${1:-4}" 2>/dev/null
}

# 取 URI 里的主机部分
hp105w_uri_host() {
  printf '%s' "$1" | sed -E 's#^ipps?://([^/:]+).*#\1#'
}

# 读打印机属性（失败输出空）
hp105w_attrs() {
  [ -f "$HP105W_IPP_TEST" ] || return 1
  ipptool -tv "ipp://$1:631/ipp/print" "$HP105W_IPP_TEST" 2>/dev/null
}

# 发现 HP Laser 105 系列打印机，输出主机名/IP；找不到返回 1
hp105w_discover_host() {
  local t="${1:-4}" uris uri host model first
  uris="$(hp105w_ipp_uris "$t" || true)"
  [ -n "$uris" ] || return 1
  for uri in $uris; do
    host="$(hp105w_uri_host "$uri")"
    [ -n "$host" ] || continue
    [ -n "${first:-}" ] || first="$host"
    model="$(hp105w_attrs "$host" | grep -F "printer-make-and-model" | head -1)"
    case "$model" in
      *"Laser 105"*) printf '%s' "$host"; return 0 ;;
    esac
  done
  [ -n "${first:-}" ] && { printf '%s' "$first"; return 0; }
  return 1
}

# 页计数器 prtMarkerLifeCount（判断是否真的出纸）
hp105w_page_count() {
  command -v snmpwalk >/dev/null 2>&1 || return 1
  snmpwalk -v1 -c public -t 2 -r 1 "$1" 1.3.6.1.2.1.43.10.2.1.4 2>/dev/null \
    | tail -1 | grep -oE '[0-9]+$'
}

# 等打印机空闲（raw 9100 在忙时会静默丢数据）
hp105w_wait_idle() {
  local host="$1" limit="${2:-60}" t=0 attrs st q
  [ -f "$HP105W_IPP_TEST" ] || return 0
  while [ "$t" -lt "$limit" ]; do
    attrs="$(hp105w_attrs "$host")" || true
    st="$(printf '%s\n' "$attrs" | grep -oE 'printer-state \(enum\) = [a-z]+' | head -1 | awk '{print $NF}')"
    q="$(printf '%s\n' "$attrs" | grep -oE 'queued-job-count \(integer\) = [0-9]+' | head -1 | awk '{print $NF}')"
    [ -z "${st:-}" ] && return 0
    [ "$st" = "idle" ] && [ "${q:-0}" = "0" ] && return 0
    sleep 2; t=$((t + 2))
  done
  return 0
}
