# points-deck · 京宝积分随身版

`~/Edu` 积分账本（<https://edu.tianli.cyou>）的 iOS 原生客户端。

| | |
|---|---|
| 孩子面 | 总市值 · 还差多少升级 · 走势 · 兑换 · 拍错题 |
| 家长面 | Face ID 取出管理密码记一笔 —— 保住「孩子拿到已登录的手机也加不了分」，同时不必每次手输 |
| Widget | 锁屏/主屏常驻「市值 + 还差 N 分升 X」 |

## 状态

| | |
|---|---|
| 全部界面 + Widget | ✅ 模拟器实测通过，逐屏截图核对 |
| 记账 / 撤销 / 兑换 / 错题上传 | ✅ 对本地账本跑通全链路（含错密码被拒、撤销后余额归位） |
| 真机装机 | ⬜ 等 Apple Developer membership 转 active |
| Face ID 真机验证 | ⬜ 模拟器无 Face ID 硬件，只能上真机看 |

## 跑

```bash
bash sim-run.sh              # 模拟器
bash install-to-iphone.sh    # 真机(默认走 WiFi)
```

开发约定、本地验证方法、踩过的坑见 `CLAUDE.md`。
