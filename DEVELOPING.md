# points-deck · 成长小金库

`~/Edu` 积分账本（<https://edu.tianli.cyou>）的 iOS 原生客户端。

| | |
|---|---|
| 孩子面 | **时代插画底图**（住什么房看得见）· 总市值 · 还差多少升级 · 走势 · 兑换 · 等级权益 |
| 换装 | 整页配色**从插画采样派生**，五档各不相同；升档弹「乔迁新居」+ 触感，回落不吭声 |
| 家长面 | Face ID 取出管理密码记一笔 —— 保住「孩子拿到已登录的手机也加不了分」，同时不必每次手输 |
| Widget | 锁屏/主屏常驻「市值 + 还差 N 分升 X」 |

> **学习那一摊在另一个 app**：做题、错题本、离线课页 → `~/Apps/ios/wrong-book`（错题本）。
> 2026-08-28 用户拍板「分开2个app，一个关注错题，一个关注积分」。两个 app 共用
> edu.tianli.cyou 的同一套账号，但各装各的、各登各的。

## 状态

| | |
|---|---|
| 全部界面 + Widget + 底图/派生配色 | ✅ 模拟器实测通过，逐屏截图核对 |
| 升档庆祝 | ✅ 双向验过（跨档弹庆祝、回落不弹） |
| 记账 / 撤销 / 兑换 | ✅ 对本地账本跑通全链路（含错密码被拒、撤销后余额归位） |
| 真机装机 | ⬜ 等 Apple Developer membership 转 active |
| Face ID 真机验证 | ⬜ 模拟器无 Face ID 硬件，只能上真机看 |

## 跑

```bash
bash sim-run.sh              # 模拟器
bash sync-skins.sh           # 同步时代底图(构建会自动跑)
bash install-to-iphone.sh    # 真机(默认走 WiFi)
```

底图的 SSOT 在 `~/Edu/points/skins/`，不进本仓 —— clone 之后跑一次 `sync-skins.sh`。

开发约定、本地验证方法、踩过的坑见 `CLAUDE.md`。
