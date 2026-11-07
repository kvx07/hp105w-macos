#!/usr/bin/env bash
# build.sh — 下载并编译 QPDL 编码器（SpliX），生成 PPD
# 不写系统目录、不需要 sudo。产物落在 build/ 与 bin/vendor/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SPLIX_URL="https://codeload.github.com/OpenPrinting/splix/tar.gz/refs/heads/master"
# pinned: master @ 2026-08-20（更新时改这里并重新计算 sha256）
SPLIX_SHA256="759864d9d5bf3947b94504c085b375c433ed4d3368c766842ab4b5ad5858eebf"

CACHE="$ROOT/build/cache"
SRC="$ROOT/build/splix"
VENDOR="$ROOT/bin/vendor"
PPD_OUT="$ROOT/ppd/HP_Laser_105w.ppd"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 依赖检查
say "检查编译环境"
command -v cc >/dev/null || command -v clang >/dev/null || die "缺少 C/C++ 编译器（装 Xcode Command Line Tools：xcode-select --install）"
command -v make >/dev/null || die "缺少 make"
command -v curl >/dev/null || die "缺少 curl"

SDK_INC="$(xcrun --show-sdk-path 2>/dev/null || true)"
[ -f "${SDK_INC:-/nonexistent}/usr/include/cups/ppd.h" ] || die "找不到 CUPS 头文件（ppd.h）；需要 Xcode Command Line Tools"

# ---------------------------------------------------------------- 下载
mkdir -p "$CACHE" "$SRC" "$VENDOR"
TARBALL="$CACHE/splix-master.tar.gz"

if [ ! -f "$TARBALL" ]; then
  say "下载 SpliX 源码"
  curl -fsSL --retry 3 -m 120 "$SPLIX_URL" -o "$TARBALL.part"
  mv "$TARBALL.part" "$TARBALL"
fi

say "校验源码包 sha256"
ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL" != "$SPLIX_SHA256" ]; then
  die "sha256 不匹配
  期望: $SPLIX_SHA256
  实际: $ACTUAL
  上游分支已变动时，更新 scripts/build.sh 里的 SPLIX_SHA256。"
fi

if [ ! -f "$SRC/Makefile" ]; then
  say "解包"
  tar xzf "$TARBALL" -C "$SRC" --strip-components=1
fi

# ---------------------------------------------------------------- 编译
say "编译 rastertoqpdl / pstoqpdl（DISABLE_JBIG=1，去掉 libjbig 依赖）"
CPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
make -C "$SRC" clean >/dev/null 2>&1 || true
make -C "$SRC" -j"$CPU" DISABLE_JBIG=1 LDFLAGS="-lcups" >/tmp/hp105w-build.log 2>&1 \
  || { tail -30 /tmp/hp105w-build.log; die "编译失败，完整日志 /tmp/hp105w-build.log"; }

for b in rastertoqpdl pstoqpdl; do
  [ -x "$SRC/optimized/$b" ] || die "编译产物缺失: $SRC/optimized/$b"
  cp "$SRC/optimized/$b" "$VENDOR/$b"
  chmod 755 "$VENDOR/$b"
done
say "产物: $VENDOR/rastertoqpdl"

# ---------------------------------------------------------------- PPD
say "生成 PPD（基于同机芯的 ml2160.ppd）"
sed -e 's/^\*Product: "(ML-2160)"/\*Product: "(HP Laser 105w)"/' \
    -e 's/^\*Manufacturer: "Samsung"/\*Manufacturer: "HP"/' \
    -e 's/^\*ModelName: "Samsung ML-2160"/\*ModelName: "HP Laser 105w"/' \
    -e 's/^\*ShortNickName: "Samsung ML-2160"/\*ShortNickName: "HP Laser 105w"/' \
    -e 's/^\*NickName: "Samsung ML-2160, 2.0.0"/\*NickName: "HP Laser 105w (SPL\/QPDL), 1.0"/' \
    -e 's/^\*DefaultPageSize: Letter/\*DefaultPageSize: A4/' \
    "$SRC/ml2160.ppd" > "$PPD_OUT"

if command -v cupstestppd >/dev/null; then
  cupstestppd -q "$PPD_OUT" || die "生成的 PPD 未通过 cupstestppd 校验"
fi
say "PPD: $PPD_OUT"

say "完成。下一步： ./scripts/install.sh"
