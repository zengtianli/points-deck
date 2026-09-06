# 时代底图（同步来的，不是手写的）

这里的 `*.jpg` 与 `skins.json` 由 `../../sync-skins.sh` 从
`~/Edu/points/skins/` 同步而来，**不进 git**：

- 图的 SSOT 在 `~/Edu`（那边有生图 prompt、seed、皮肤清单门 `skin_check.py` 盯着）
- 仓里存一份副本就是第二份，改了图两边会漂

**这个 README 进仓**，只为让目录存在 —— xcodegen 的 `sources` 引用一个不存在的
目录会直接拒，那时 preBuildScripts 还没轮到跑，全新 clone 会卡在一句
「missing source directory」上，而它不告诉你该干什么。

新机器上 clone 之后：

```bash
bash sync-skins.sh
```

Xcode Cloud 或没有本机 Edu 源的新 checkout，会下载 `ci_scripts/skins.lock`
锁定的 GitHub Release 导出包，并校验 SHA-256。包只含五张插画和运行时皮肤配置，
不含用户账号、账本或学习档案；图像和配置的原始来源仍是 Edu。
更新资源时用 `python3 ci_scripts/export_skins.py /path/to/Edu/points/skins output.tar.gz`
生成导出包，上传新版本 Release，再将输出摘要和下载 URL 写入 lock。

构建时也会自动跑一次（`project.yml` 的 preBuildScripts），缺源即失败 ——
漏同步的表现是**编译通过、装上能跑、只是没有背景**，那种缺陷不会报错，
只会被当成「设计就这样」。
