#!/bin/bash
# 把 ~/Edu 的练习页组装进 app bundle（构建前跑）。
#
# 为什么不把页面提交进本仓：页面的 SSOT 在 ~/Edu(那边有 curriculum.yaml、题库、
# 渲染门、PII 门)。这边只是**取一份装进 bundle**，加了课重跑一次即可。
# 仓里存一份副本就是第二份，改了课两边会漂 —— 和底图那条一样的道理。
#
# 为什么必须挂在构建前：漏同步的表现是**编译通过、装上能跑、只是那一课点不开**，
# 或者更坏——做的是上一版的题。这种缺陷不报错，只会被当成「设计就这样」。
#
# 组装/剥离/PII 全在 ~/Edu/engine/app_pack.py（与上线共用同一道 PII 门）：
# 包发到设备上和发到公网，对 archive/ 里的姓名、成绩、试卷原图是同一种暴露。
set -euo pipefail

EDU="${EDU_HOME:-$HOME/Edu}"
DST="$(cd "$(dirname "$0")" && pwd)/Resources/Lessons"
PACK="$EDU/engine/app_pack.py"

[ -f "$PACK" ] || { echo "❌ 找不到组装器 $PACK —— ~/Edu 不在？" >&2; exit 1; }

python3 "$PACK" "$DST"

# 组装器会先 rmtree 目标目录 —— 连这个 README 一起清掉。
# 它必须在:clone 之后 Resources/Lessons/ 若不存在，xcodegen 会因
# 「missing source directory」直接拒绝生成工程，**而那时 preBuildScripts 还没轮到跑**,
# 于是「跑一下构建就好了」这条自救路是断的。所以每次组装完补回来。
cat > "$DST/README.md" <<'MD'
# Resources/Lessons

**除了这个文件，目录是空的才正常。** 练习页由 `sync-lessons.sh` 在每次构建前
从 `~/Edu` 组装进来（`~/Edu/engine/app_pack.py`：剥会话 chrome → 过与上线同一道
PII 门 → 写 manifest.json）。

SSOT 在 `~/Edu`（`curriculum.yaml` + 各 `.practice.md` + 题库），不在这个仓。
这里存一份副本就是第二份，加了课两边会漂。对账门：
`python3 ~/Edu/engine/app_pack.py <这个目录> --check`（已挂进 `~/Edu` 的 check_all）。

这个 README 进仓只为让目录存在。组装器每次都会清空目录再重建，
所以它由 `sync-lessons.sh` 在组装之后写回 —— 别手改，改了下次构建就没了。
MD

# 组装器自己是 fail-closed 的，这里再钉一次「产物真的在」——
# 空集不报绿：manifest 没了或一课都没有却 exit 0，就是那种哑掉的守卫。
[ -f "$DST/manifest.json" ] || { echo "❌ 没产出 manifest.json" >&2; exit 1; }
n=$(python3 -c "import json,sys;print(len(json.load(open('$DST/manifest.json'))['lessons']))")
[ "$n" -ge 1 ] || { echo "❌ manifest 里一课都没有" >&2; exit 1; }
echo "   → bundle 里 $n 课"
du -sh "$DST" | sed 's/^/   /'
