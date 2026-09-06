#!/bin/bash
# 把 ~/Edu/points/skins/ 的时代底图与阈值表同步进 app bundle。
#
# 为什么是脚本不是手工拷：底图的 SSOT 在 ~/Edu(那边有生图 prompt、seed、
# 皮肤清单门 skin_check.py 盯着)。这边只是**取一份副本装进 bundle**，
# 换了图重跑一次即可,不用记得手工再拷一遍。
#
# 为什么装进 bundle 而不是运行时下载：底图是离线资产(~/Edu 的既定规矩)，
# 运行时零外部请求；图缺了自动退回纯色主题(fail-soft，见 Skin.swift)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="${EDU_SKINS:-$HOME/Edu/points/skins}"
DST="$ROOT/Resources/Skins"

# Cloud/new checkouts consume a pinned export of the source artwork.
# The release contains only five illustrations and the runtime skin config.
if [ -z "${EDU_SKINS:-}" ] && { [ "${CI:-}" = "TRUE" ] || [ ! -d "$SRC" ]; }; then
  SRC="$ROOT/.build-inputs/skins"
  mkdir -p "$SRC"
  read -r digest url < "$ROOT/ci_scripts/skins.lock"
  archive="$ROOT/.build-inputs/skins.tar.gz"
  if [ ! -f "$archive" ]; then
    curl --fail --location --retry 2 "$url" -o "$archive.part"
    printf '%s  %s\n' "$digest" "$archive.part" | shasum -a 256 -c -
    mv "$archive.part" "$archive"
  fi
  printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -
  tar -xzf "$archive" -C "$SRC"
fi

[ -d "$SRC" ] || { echo "❌ 找不到皮肤源 $SRC" >&2; exit 1; }
mkdir -p "$DST"

n=0
for era in slum cottage garden manor golden; do
  f="$SRC/$era/bg.jpg"
  if [ ! -f "$f" ]; then
    echo "❌ 缺 $f —— 皮肤源不完整，别装一半上去" >&2
    exit 1
  fi
  cp "$f" "$DST/$era.jpg"
  n=$((n + 1))
done
cp "$SRC/skins.json" "$DST/skins.json"

# 空集不报绿：一张都没同步却 exit 0，就是那种「哑掉的守卫」
[ "$n" -eq 5 ] || { echo "❌ 只同步了 $n 张，期望 5 张" >&2; exit 1; }
echo "✅ 同步 $n 张底图 + skins.json → Resources/Skins/"
du -sh "$DST" | sed 's/^/   /'
