# points-deck · 京宝积分随身版

`~/Edu` 积分账本（<https://edu.tianli.cyou>）的 iOS 原生客户端。

孩子面看总市值、住到哪一档、还差多少升级、最近流水；家长面（未完成）用 Face ID
包住管理密码记一笔 —— 保住「孩子拿到已登录的设备也加不了分」这条设计，同时不必每次手输。

## 状态

| | |
|---|---|
| 登录 + 孩子面第一屏 | ✅ 模拟器实测通过（市值 / 进度条 / 流水） |
| 家长面 · 走势图 · 兑换 · Widget | ⬜ 未开始 |
| 真机装机 | ⬜ 等 Apple Developer membership 转 active |

## 跑

```bash
bash sim-run.sh              # 模拟器
bash install-to-iphone.sh    # 真机(默认走 WiFi)
```

开发约定与本地验证方法见 `CLAUDE.md`。
