# CLAUDE.md · points-deck（京宝积分随身版）

`~/Edu` 那本积分账本的 iOS 客户端。**不是套壳网页**，也**不是第二个账本**。

## 三条不可越过的线

1. **不做后端** —— 服务端是 `~/Edu/points/server.py`（线上 `edu.tianli.cyou`）。这里只发请求。
2. **不复刻算分** —— 分值一律服务端算，预览也走 `/api/preview`。
   两边各算各的迟早算出不同的数，而家长看到的是预览、孩子拿到的是记账。
   **`Sources/` 里不许出现任何一条规则的分值。**
3. **不写第二份档位阈值** —— 「多少分算哪一档」的 SSOT 是
   `~/Edu/points/skins/skins.json` 的 `tiers`，随 `/api/state` 的 `house` 下发。
   `Skin.swift` 只管「拿到 era 之后长什么样」。
4. **不存第二份底图** —— 图的 SSOT 也在 `~/Edu/points/skins/`（那边有生图 prompt、
   seed、皮肤清单门）。这里的 `Resources/Skins/` 是构建时同步来的副本，不进 git。

## 配色是从插画里算出来的，不是写死的

「背景要跟着木屋的背景变」（2026-08-28 用户钦定）。所以 `Era.palette` 从
`Resources/Skins/<era>.jpg` 采样：**上三分之一 = 天空色、下三分之一 = 地面色**，
各自压暗到能压住白字（原图天空是米白，直接当背景白字就没了），accent 取地面色相提亮。
色相留原图的，那才是「跟着变」的那部分；明度/饱和钳死，那是可读性的底线。

五档实际效果：贫民窟冷灰褐 · 普通人家暖褐夕阳 · 小康之家橄榄绿 · 豪宅深蓝夜 ·
金碧辉煌金褐。`-palette 1` 一屏看全五档。

⚠ **11 档房名只有 5 张图**（`skins.json` 的 era 映射）——「小木屋」和「砖瓦房」
共用 cottage 那张，「金碧辉煌宫殿」和「云端天堂」共用 golden 那张。
那是 `~/Edu` 既定的美术分档，**不在端上另立一套**。要一档一图得回 `~/Edu` 加图 + 改 skins.json。

## 界面

| | |
|---|---|
| 账本 | **时代底图带**（住什么房得看得见）· 市值大字（滚动动画）· **还差 N 分升级到 X** + 进度条 · 最近流水 |
| 走势 | 曲线 + 涨跌/最高/最低/今日刷题余额。用每条流水自带的 `bal` 快照，**不在端上累加求余额** |
| 兑换 | 商店。花的是孩子自己的分，**不需要家长密码**（服务端如此），不许透支。未到档位的显示锁 + 「要住进 X 才能换」 |
| 账户 | 头像/昵称 · **等级卡 → 等级总览页（11 档全摊开带待遇）** · 资产 · 设置 · 退出登录 |
| 家长（右上角锁盾） | 选规则 → 填输入 → 服务端预览 → 点「记这一笔」→ **输密码解锁** → 之后连着记不再问；撤销最近 5 笔 |
| Widget | 锁屏/主屏常驻「市值 + 还差 N 分升 X」。读共享 keychain 快照（不是 App Group，理由见 Snapshot.swift），**自己不联网** |
| 升档庆祝 | 「乔迁新居」+ 彩带 + success 触感。**只庆不罚**：回落一声不吭 |

## 家长模式：怎么解锁（2026-08-28 改成会话式，Face ID 已删）

**密码是 `Tianli@2026`**（首字母大写；全大写的 `TIANLI@2026` 是错的，实测 403）。
它存在服务端 `config.json` 的 `parent`（scrypt salt+hash，取不出明文），
**和 `jingbao` 的登录密码不是一个东西**。

操作顺序：

1. **账户页 → 设置 → 家长模式 → 「解锁」** → 输 `Tianli@2026`
   （拿只读接口 `/api/verify_parent` 验，验过才置位；密码对不对只有服务端说了算）
2. 解锁后连着记多少笔都不再问；那一行显示「已解锁 · N 笔」
3. 解锁状态下多出一行「**管理规则 / 商品 / 档位**」，改的就是服务器那份配置
4. 记完点「**上锁**」

也可以走老路子：主界面右上角 🔒 → 选规则 → 填数值 → 点「记这一笔」时顺带弹密码框。

> 2026-08-28 修掉的交互缺陷：原先 `askPassword` **只**在 `earn()` 里置位，
> 于是「想单纯解锁一下」必须先凑出一笔账来 —— 找不到的入口等于不存在
> （用户第一句话就是「怎么解锁家长模式？」，那就是入口不成立的证据）。
> 现在 `AccountView.settings` 里有独立的解锁按钮。

## 家长密码为什么不能「记住」

`~/Edu` 的设计是「家长密码每次现输、不发 cookie」——
理由是**孩子拿到已登录的平板也加不了分**。能自己给自己加分的积分系统，第二天就变成刷分游戏。

这条不能破，所以这里不是「记住登录状态」，而是一段**有始有终的会话**（`ParentSession.swift`）：
密码只在**内存**里，上锁 / 退出 app / 切后台超过 10 分钟就没了，
每次记账仍然是「从内存取 → 随请求发一次」。孩子拿到手机时它一定是锁着的。

⚠ `unlockThenEarn()` 是**先拿这次记账让服务端验过密码，才算解锁** ——
不先验就解锁的话，错密码会让界面显示「已解锁」而每一笔都被拒，那种自相矛盾的状态最难查。

## 跑起来

```bash
bash sim-run.sh                      # 模拟器：xcodegen → 编 → 装 → 起 → 截图(总部 SSOT)
bash sync-skins.sh                   # 从 ~/Edu 同步时代底图（构建会自动跑一次）
bash install-to-iphone.sh            # 真机(总部 SSOT，默认走 WiFi)
python3 make_icon.py                 # 重画图标
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

**验证用的 launch 参数**（进 UserDefaults，**只在显式传了才生效**，生产路径上永远是 nil）：

| | |
|---|---|
| `-api_base <url>` | 指向本地 server |
| `-dev_user` / `-dev_pw` | 跳过手输登录 |
| `-tab 0..3` | 直接落到某个 tab |
| `-parent 1` | 直接打开家长面 |
| `-widgetpreview 1` | 把 Widget 的同一份 View 按各尺寸画出来看（拖 widget 到主屏 headless 做不到） |
| `-palette 1` | 五档插画 + 从它派生的配色并排看（一档一档跑要编译五次，而且没法比较） |

## 文件

| | |
|---|---|
| `Api.swift` | 账本客户端 + `/api/state` 投影 + `RuleInput`（按 kind 组装参数，**不算分**） |
| `Store.swift` | 会话状态机。开屏探测超时 6s 而非 20s；登录失败必须落回 `loggedOut` |
| `Skin.swift` | 五个时代的配色 + 数字滚动。**无阈值** |
| `Snapshot.swift` / `WidgetViews.swift` | 主 app 与 Widget **共用的同一份**数据契约与视图 |
| `AdminGate.swift` | Keychain + Face ID |
| `HomeView / DeckView / TrendView / ShopView / WrongView / ParentView` | 各屏 |

## 底图要在**两个** target 里各声明一次

`Resources/Skins` 在 `project.yml` 里对 `PointsDeck` 和 `PointsWidget` 各写了一次
（`type: folder` + `buildPhase: resources`）。widget extension 有自己的 bundle，
主 app 打了包不等于它也有。

**漏声明不会报错** —— widget 只是悄悄掉回 `fallbackColors`，锁屏上颜色和 app 里对不上，
而两边看起来都「正常」。核验方式（这个是确定性的，比看预览可靠）：

```bash
find .dd-sim/Build/Products/*/PointsDeck.app/PlugIns/PointsWidget.appex -name '*.jpg'
```

⚠ `-widgetpreview 1` 那个预览页是**主 app 在渲染 widget 的视图代码**，
它证明不了 widget 进程读得到资源 —— 上面那条 find 才证明得了。
真正的锁屏布局与刷新预算只能上真机看。

## 踩过的（别再踩）

- **字段名照 server.py 第 498-504 行对，不猜** —— 第一版猜了 `what`/`t`，
  跑出来整列事由是「—」而市值进度条一切正常，**界面看着毫无异样**。
- **`@main` 只能有一个** —— Widget 的视图与 Snapshot 要拆成共享文件，
  `Widget/PointsWidget.swift` 只留 Provider 和 `@main`。
- **xcodegen 的 `info.path` 是生成目标不是「用这个文件」** —— 手写一份 `Widget/Info.plist`
  会被直接覆盖。`NSExtension` 必须写在 `info.properties` 里，
  少了它的表现是**编译通过、装机报 `Invalid placeholder attributes`**。
- **`widgetFamily` 是只读环境值**，`.environment(\.widgetFamily,)` 编不过；
  预览用显式 `familyOverride` 参数。

## 升档庆祝为什么要存盘

`lastTier` 存 UserDefaults 而不是只放内存 —— 最常见的升档场景是
**「家长加分时孩子没开着 app，孩子后来才打开」**，只放内存的话那一次永远庆祝不了，
而那恰恰是最该被看见的一次。装完 app 第一次拿到状态时只记不庆（没有基准，谈不上「升」）。

用**档位序号**比对而不是房名：房名可能在 `skins.json` 里被改字，改名不该假装成一次升档。

回到前台会自动刷新一次（`scenePhase == .active`）—— 分是家长在别处加的，不刷就看不到。

## 还没做

真机装机（等 Apple Developer membership 转 active）· 兑换记录筛选。方案见
`~/Dev/wiki/handoffs/dev/ios-fleet-landing/05-积分app方案.md`。

**按付费档规格开发**（2026-08-28 用户钦定）：不为「同时 3 个自签」的上限做妥协设计。
