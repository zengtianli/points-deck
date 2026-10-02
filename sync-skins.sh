#!/bin/bash
# 把 ~/Apps/edu/web/points/skins/ 的时代底图与阈值表同步进 app bundle。
#
# 为什么是脚本不是手工拷：底图的 SSOT 在 ~/Apps/edu/web(那边有生图 prompt、seed、
# 皮肤清单门 skin_check.py 盯着)。这边只是**取一份副本装进 bundle**，
# 换了图重跑一次即可,不用记得手工再拷一遍。
#
# 为什么装进 bundle 而不是运行时下载：底图是离线资产(~/Apps/edu/web 的既定规矩)，
# 运行时零外部请求；图缺了自动退回纯色主题(fail-soft，见 Skin.swift)。
#
# 每个打包 Resources/Skins 的 target（主 app、两个小组件、手表 app）各自在构建最前面跑一次
# （project.yml 的 BundlesSkins 模板），所以它会被**并发**调用：
#   · 内容没变的文件不重写（cmp），同一次构建里第二次起什么都不动；
#   · 要写就先写临时文件再 mv —— rename 是原子的，别的 target 正在拷的那份永远是完整的图；
#   · 云端 / 新 clone 的固定导出包解到本次独占的临时目录，不和并发的另一份抢同一组文件。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="${EDU_SKINS:-$HOME/Apps/edu/web/points/skins}"
DST="$ROOT/Resources/Skins"

# Cloud/new checkouts consume a pinned export of the source artwork.
# The release contains only five illustrations and the runtime skin config.
unpacked=""
trap '[ -n "$unpacked" ] && rm -rf "$unpacked"' EXIT
if [ -z "${EDU_SKINS:-}" ] && { [ "${CI:-}" = "TRUE" ] || [ ! -d "$SRC" ]; }; then
  mkdir -p "$ROOT/.build-inputs"
  read -r digest url < "$ROOT/ci_scripts/skins.lock"
  archive="$ROOT/.build-inputs/skins.tar.gz"
  if [ ! -f "$archive" ]; then
    part="$archive.part.$$"
    curl --fail --location --retry 2 "$url" -o "$part"
    printf '%s  %s\n' "$digest" "$part" | shasum -a 256 -c -
    mv -f "$part" "$archive"
  fi
  printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -
  unpacked="$(mktemp -d "$ROOT/.build-inputs/skins.XXXXXX")"
  tar -xzf "$archive" -C "$unpacked"
  SRC="$unpacked"
fi

[ -d "$SRC" ] || { echo "❌ 找不到皮肤源 $SRC" >&2; exit 1; }
mkdir -p "$DST"

# 内容一样就不碰；不一样先写临时文件再原子替换（见文件头：本脚本会被几个 target 并发调用）
put() {
  if ! cmp -s "$1" "$2"; then
    cp "$1" "$2.tmp.$$"
    mv -f "$2.tmp.$$" "$2"
  fi
}

n=0
for era in slum cottage garden manor golden; do
  f="$SRC/$era/bg.jpg"
  if [ ! -f "$f" ]; then
    echo "❌ 缺 $f —— 皮肤源不完整，别装一半上去" >&2
    exit 1
  fi
  put "$f" "$DST/$era.jpg"
  n=$((n + 1))
done
put "$SRC/skins.json" "$DST/skins.json"

# 空集不报绿：一张都没同步却 exit 0，就是那种「哑掉的守卫」
[ "$n" -eq 5 ] || { echo "❌ 只同步了 $n 张，期望 5 张" >&2; exit 1; }
echo "✅ 同步 $n 张底图 + skins.json → Resources/Skins/"
du -sh "$DST" | sed 's/^/   /'
