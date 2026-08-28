# CLAUDE.md · points-deck（京宝积分随身版）

`~/Edu` 那本积分账本的 iOS 客户端。**不是套壳网页**，也**不是第二个账本**。

## 三条不可越过的线

1. **不做后端** —— 服务端是 `~/Edu/points/server.py`（线上 `edu.tianli.cyou`）。
   这里只发请求。
2. **不复刻算分** —— 分值一律服务端算，预览也走 `/api/preview`。
   两边各算各的迟早算出不同的数，而家长看到的是预览、孩子拿到的是记账。
   **`Sources/` 里不许出现任何一条规则的分值。**
3. **不写第二份档位阈值** —— 「多少分算哪一档」的 SSOT 是
   `~/Edu/points/skins/skins.json` 的 `tiers`，随 `/api/state` 的 `house` 下发。
   `Skin.swift` 只管「拿到 era 之后长什么样」。加一档要改两处就是漂移。

## 跑起来

```bash
bash sim-run.sh                      # 模拟器：xcodegen → 编 → 装 → 起 → 截图(总部 SSOT)
bash install-to-iphone.sh            # 真机(总部 SSOT，默认走 WiFi)
```

**对着本地账本验**（不碰线上数据）：

```bash
SCRATCH=/tmp/edu-points-home
lsof -ti :8788 | xargs -r kill -9                      # 起之前清端口
cd ~/Edu/points
EDU_POINTS_HOME=$SCRATCH EDU_POINTS_PORT=8788 python3 server.py init
EDU_POINTS_HOME=$SCRATCH EDU_POINTS_PORT=8788 python3 server.py seed 30 --force
EDU_POINTS_HOME=$SCRATCH EDU_POINTS_PORT=8788 python3 server.py serve &

cd ~/Apps/ios/points-deck
SIM_LAUNCH_ARGS="-api_base http://127.0.0.1:8788 -dev_user jingbao -dev_pw 160912" bash sim-run.sh
```

`-api_base` / `-dev_user` / `-dev_pw` 是 launch 参数（进 UserDefaults），
**只在显式传了才生效**，生产路径上永远是 nil。

## 文件

| | |
|---|---|
| `Api.swift` | 账本客户端 + `/api/state` 的投影。**字段名照着 server.py 第 498-504 行对的** —— 第一版猜了 `what`/`t`，跑出来整列事由是「—」而其余一切正常，界面看着毫无异样 |
| `Store.swift` | 会话状态机（checking / loggedOut / loggedIn）。开屏探测超时 6s 而非 20s：它挡在任何界面之前，没网时干等 20 秒就是「app 坏了」的观感 |
| `Skin.swift` | 五个时代的配色 + 数字滚动。**无阈值** |
| `LoginView.swift` / `DeckView.swift` | 登录 / 孩子面第一屏 |

## 还没做

家长面（记一笔 / 撤销 / 调账，Face ID 包住管理密码不落 cookie）· 走势图 · 兑换 ·
锁屏 Widget · 相机直连错题。方案见
`~/Dev/wiki/handoffs/dev/ios-fleet-landing/05-积分app方案.md`。

**按付费档规格开发**（2026-08-28 用户钦定）：不为「同时 3 个自签」的上限做妥协设计。
