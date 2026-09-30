**中文** | [English](README_EN.md)

<p align="center"><img src="Resources/icon-1024.png" width="96" alt="成长小金库"></p>

# 成长小金库 · points-deck

**孩子的每一分努力，涨成看得见的房子。**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

给孩子做的：11 档市值映射 5 个时代的插画，「住什么房看得见」，整页配色从插画采样派生。家长密码永不落盘——能自己给自己加分的积分系统，第二天就会变成刷分游戏。升档只庆不罚，回落一声不吭。

<table><tr>
<td align="center" width="25%"><img src="docs/screenshots/01-sim-064957.png" alt="开屏：挣的每一分都在这本账上——整页配色跟着当前住的房子走"><br><sub>开屏：挣的每一分都在这本账上——整页配色跟着当前住的房子走</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/02-tab1.png" alt="走势：积分市值像股票一样有曲线，最高最低、今天刷题还能得几分"><br><sub>走势：积分市值像股票一样有曲线，最高最低、今天刷题还能得几分</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/03-tab2.png" alt="兑换：冰淇淋、多玩 30 分钟、满足一个心愿——花自己挣的分，不许透支"><br><sub>兑换：冰淇淋、多玩 30 分钟、满足一个心愿——花自己挣的分，不许透支</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/04-parent.png" alt="家长记一笔：选规则、看预览、输密码；撤销最近的直接删，走势图上当它没发生过"><br><sub>家长记一笔：选规则、看预览、输密码；撤销最近的直接删，走势图上当它没发生过</sub></td>
</tr></table>

<details><summary>更多截图</summary><table><tr>
<td align="center" width="25%"><img src="docs/screenshots/05-palette.png" alt="五个时代的插画与从中采样派生的整页配色"><br><sub>五个时代的插画与从中采样派生的整页配色</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/06-widget.png" alt="Widget 视图预览（App 内渲染）：市值常驻，还差多少升下一档"><br><sub>Widget 视图预览（App 内渲染）：市值常驻，还差多少升下一档</sub></td>
</tr></table></details>

## 它做什么

| 功能 | 说明 |
|---|---|
| **努力涨成看得见的房子** | 11 档市值映射 5 个时代的插画，从贫民窟到金碧辉煌。整页配色从当前那张插画采样派生——升档换房，整个 app 跟着换气质。升档只庆不罚，回落一声不吭。 |
| **像股票盘面一样看自己的账** | 走势、涨跌、最高最低——账本长成孩子看得懂又觉得酷的样子。余额用每条流水自带的快照，端上不自己累加，两边永远对得上。 |
| **家长密码永不落盘** | 能自己给自己加分的积分系统，第二天就会变成刷分游戏。所以家长密码每次现输、只在内存、切后台就没了——孩子拿到解锁的手机也加不了分。分值一律服务端算，客户端连一个加号都没有。 |

## 怎么拿到

已支持邮箱注册与独立家庭账本；iOS 版已在 [App Store](https://apps.apple.com/app/id6806799638) 发布。2026-09-26 官方构建回读为 1.0（2），见[发行记录](perf/asc-release.json)；手机当前装机版本与运行性能仍待真机核验。

时代插画底图来自作者的 `~/Apps/edu/web` 内容库（构建时同步进包），账本后端 `edu.tianli.cyou`。没有那份内容库，构建会停在 preBuildScripts。

## 给 Agent 的命令行 · `treasury`

App 给人用，命令行给 Agent 用。`cli/treasury` 是同一个服务端（`edu.tianli.cyou` 的 `/api/*`，App 与网页用的同一套接口）的薄客户端，只用 Python 标准库；分值、档位解锁、透支、家长密码和并发锁全在服务端判，命令行里没有一行算分逻辑。

本机构建的 Mac 版 `.app` 自带这个命令：`Contents/Resources/bin/treasury`（`project.yml` 的构建阶段只在 macOS 的 build 里拷进去，随包签名）；iPhone/iPad 包和任何归档（App Store / TestFlight）都不带。

```bash
sh cli/install.sh          # 装了 Mac 版：按 bundle id 找到 .app，链到包里的命令；没装：链到本仓 cli/treasury（改源码即生效）
sh cli/install.sh --check  # 只核对；--uninstall 只删本产品入口的链接
```

凭据只从环境变量或 stdin 取，不落盘、不回显：`EDU_USER`（邮箱或用户名）、`EDU_PASSWORD`（或 `--password-stdin`）；家长操作要 `EDU_PARENT_PW`（或 `--parent-stdin`），同 App 的家长锁每次现取现发；`EDU_API_BASE` 默认 `https://edu.tianli.cyou`。

```bash
treasury state --json                          # 余额、住哪一档、还差多少升档、电视时间、心愿、今天刷题额度
treasury entries --limit 10 --json             # 流水（新的在前；服务端下发最近 400 笔）
treasury preview tr-show --json                # 服务端算分，不记账
printf '%s\n' "$PARENT" | treasury earn tr-show --parent-stdin --json
treasury spend sh-icecream --dry-run --json    # 先看能不能换
treasury config put shop --file shop.json --parent-stdin < parent.txt
```

读命令都支持 `--json`，输出 `{"ok": true, …}`；失败输出 `{"ok": false, "err": …}` 且退出码非 0（1 = 服务端拒绝或网络失败，2 = 用法错或缺凭据）。读命令不改任何状态；会写的命令都走服务端原有的校验、锁与幂等，记账/调账/撤销/兑换可先 `--dry-run`，删号与注销必须 `--yes`。

| App 里能做的 | 命令 |
|---|---|
| 账本首页 | `treasury state` |
| 流水 / 走势 | `treasury entries [--since 日期] [--cur pts\|tv\|wish]` / `treasury trend --span 14\|30\|100` |
| 兑换清单 / 兑换 | `treasury shop` / `treasury spend <商品>` |
| 家园阶梯 | `treasury tiers` |
| 家长：规则、预览、记账、撤销、调账 | `treasury rules` / `preview` / `earn` / `undo` / `adjust` |
| 管理规则 / 商品 / 档位 | `treasury config get` / `treasury config put rules\|shop\|tiers --file items.json` |
| 资料、账号密码、家长密码、注销 | `treasury profile` / `me` / `account passwd\|parent-password\|delete --yes` |
| 家长用户管理 | `treasury users list\|reset-password\|delete --yes` |

管理范围以服务端为准：`config get`、`config put`、`users list` 原样报告响应里的 `scope`（`site` 全站 / `account` 仅本账号）。服务端没返回 `scope` 时报 `unknown`：`users list` 只显示本账号自己这一行，`config put`、`users reset-password`、`users delete` 直接拒绝，不猜写入会落到哪里。

留在 App 的（纯界面）：家长锁倒计时、实时刷新推送、桌面/锁屏小组件、升档庆祝动画、配色与小组件预览。

回归：`python3 Tests/cli_treasury_test.py` —— 先核打包规则与 `install.sh`（临时 Applications 目录里的假 .app），再起一个隔离的本地服务端（临时目录 + 空闲端口），不碰线上账号；需要同一工作区的 `edu/web/points/server.py`，或用 `EDU_SERVER_PY` 指过去。

## 构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme PointsDeck -destination 'generic/platform=iOS Simulator' build
```

- 仓里的 `*.sh` 是作者本机舰队脚本的 shim（三平台构建 / 真机装机 / TestFlight），依赖 `~/Dev` 下的总部工具，不在本仓；没有那套工具时它们会明确退出。
- `Shared/PlatformCompat.swift` 是总部共享文件的逐字节副本（iOS-only SwiftUI 修饰符在 macOS 侧的同名 no-op），别在这里改它。
- `project.yml` 的 preBuildScripts 会跑 `sync-skins.sh`，从作者本机同步内容进包；没有那份内容时构建会停在这一步。

开发细节（回归、验证通道、约束）见 [DEVELOPING.md](DEVELOPING.md)。

## 相关

- 产品页：<https://apps.tianli.cyou/p/points-deck-ios.html>
- 舰队总览（10 个 app 怎么来的）：<https://apps.tianli.cyou/ios.html>
- 教程：[从零到 TestFlight：一个人做 iPhone app 的完整路径](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 曾田力 (Tianli Zeng)

<!-- lightweight:start -->
## 资源占用

安装包为 App Store 数据；内存、CPU 与启动时间为 iOS 模拟器实测，不是真机数值。

| 安装包 | 空闲内存 | 空闲 CPU | 模拟器冷启动到首屏就绪 |
|---|---|---|---|
| **3.1 MB**（装好后 4.0 MB） | **23.1 MB** | **0%** | **368 ms** |

体积按具体发行构建回读；真机尚未测量，内存、CPU 与启动时间先用 iOS 模拟器实测并标明环境。

<sub>v1.0.1 (8) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · TestFlight 1.0.1 (8)（App Store 在售仍为 1.0 (2)）；体积不含用户数据与后续缓存 · 2026-09-30。体积来自 Apple App Store Connect 对应构建的设备切片记录。内存、CPU 与启动时间是 iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2 上本地源码 Release 构建 v1.0.1 (1) 的实测（2026-09-30），只统计 App 进程，不等于真机数值；真机测量尚未完成。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->
