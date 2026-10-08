# 2026-10-08 Mini Codex：账号补丁与发行接续

## 第三轮（根因诊断与本地提交，禁止推送）

**账号仍1/17，仅email_delivery有完整原件；停在账号门，未发版。调度方本轮明确授权先保住已验证补丁的本地提交，替代第二轮“门全绿后才提交”的接续顺序；不推送、不升版、不归档、不上传或提审。**

- 手机发码直接失败原因：旧XCTest点击先收键盘，iPad居中sheet下移201.5点，动作未执行；绑定事件y660对失败时按钮中心861.5，注册y404对605.5。enabled=true、手机号完整输入已通过，后端0个phone_send、真实短信0。测试增加单独收键盘/等待几何稳定/前台可点击定位；只类型检查，未执行合成输入。尚未证明普通手指首击不受同一iPadOS行为影响，不能断言产品手机流程完整。
- 密码登录确认为产品Cookie落盘竞态：生产Api在原生进程内Cookie存在、非session-only且有expiry；立即_exit后新进程Cookie缺失/state401，等8秒后恢复200。Api.request收到Set-Cookie后await URLSession.shared.flush，才返回界面。没有复制Cookie/新增存储/延时。Mac与iPadOS27生产Api独立进程回归均通过，每个平台四进程含错密拒绝、正确登录、立即退出恢复、登出立即退出后保持401；两次有效验证后停止。诊断bundle不是完整SwiftUI账号流程。
- 政策旧helper在嵌套同名按钮和dismiss过渡期间fallback到不可点击背景目标，日志明确Computed hit point {-1,-1}；修前台Form定位、hittable和政策关闭后等待。邮件后两次验证与手机同因，y505对按钮中心706.5，无email_verify；首个邮箱候选另有未等回执就读收码队列的IndexError，第二轮已加回执等待。未重跑这些原UI断言，保持pending。
- 原sop.test、functionality/recovery/privacy、共享vendor字节检查和账号测试Swift类型检查均通过。UI测试SDK构建只遇到负载36.9≥12的准入75，没有开始构建，未放宽门。生产Cookie无界面诊断的准备故障（签名资源位置、PATH缺sysctl、iPadOS27需scene）原件保留；任何login请求前的支架失败不冒称产品失败或成功。
- 原account_lifecycle门当前退出75：16流程、真实phone通道、第三轮Api变更后的当前输入绑定仍缺，共18条issues。部分索引保留第二轮hash与email原件，不手改hash凑绿。完整账号通过数仍1/17，当前候选未取得完整原生绑定。
- 本轮真实短信/邮件新增0/0；累计0/3，上限20/20。phone_change仍缺第二个本人授权号码，本轮跳过，不猜号码。
- 本机全局post-commit会自动经git_follow推送到另一台Mac；本次提交单次用仓外local-hooks，pre-commit链接原凭证扫描，post-commit只留本地git-lfs。未改全局hooks、永久Git配置或macmini技能。限定原12路径及本轮两份Cookie回归文件，共14路径；不纳入project.yaml、原acceptance或其他dirty文件。
- 原件与三处定性：`/Users/tianli/mac-pair/tasks/points-account-release-20261008/output/round3/root-causes.md`；验证分别在`session-mac-verify1/proof.json`、`session-ipad-scene/proof.json`。本地提交号、最终无关字节/HEAD/index回读在原`output/receipt.md`第三轮和`round3/final-verification.json`。

## 第二轮（已收束，停在账号门）

**当前结论：停在第 3 步，尚未提审。隐私、生产存储、Watch 联动、原回归和核心原生 UI 已通过；账号 17 项仅 email_delivery 完整通过，另外 16 项待齐。未提交、未推送、未升版、未归档或上传。**

- 生产存储已在 Mini 合法 GUI 登录上下文跑绿，无需 Air 代跑：SSH 的最小 SecItemAdd 为 -25308；同一源程序在临时 `gui/502` 作业且禁止认证交互时 add/read/cleanup 均为 0。随后原 `scripts/accept/storage.py` 四个独立进程、11 条断言退出 0，证明生产缓存、交易日志、Snapshot 保存恢复和清理。未解锁或修改钥匙串设置；两个临时 GUI 作业已 bootout。原件 `output/round2/mini-gui-storage/gate/proof.json` 和 `receipt.json`。下文早期“需 Air”判断已被这次实证替代。
- 本轮正式新增部分账号索引 `perf/account/account-lifecycle.json`，绑定 `6828717745552e3ad694f55a530fb53bd0c76644b47eb9add102d1c0b5e1239c`。只有 email_delivery 为 passed；原生真实发送、SMTP 接受及授权 Mailu IMAP 收件的仓内原件为 `perf/account/raw/round2-20261008/email-delivery.json`，SHA256 `052d4302d98d0ef3517d6e99f18ce6984107fb9a9b12cfa0f876dbf25fce25f0`。父邮箱测试的后续校验失败仍明确保留，不能把投递当注册/核验通过。
- 原账号门最新退出 75，17 条缺口（真实 phone 通道加 16 项流程），未改门、白名单或豁免。本人已登记号码仅 1 个，phone_change 没有第二个授权号码，门没有豁免。
- 账号实际执行 10 次原生候选测试、1 次准入负载推迟；实际短信 0 条、真实邮件 3 封，其中 2 封在 IMAP 确认收到。政策导航失败 2 次、后续邮箱校验失败 2 次后停止；旧账号绑定 2 次、独立注册 1 次均未发出 phone_send。共同短信发码断言实际累计 3 次，超过用户同类失败最多 2 次要求：不能按流程名重置失败预算。已停止，并在本轮仓外调度器按共同断言合并计数，禁止继续发送或重试。完整次数见 `round2/account-attempts.json`。
- 独立 PasswordLogin 测试执行 2 次，均退出 1：首次停在替换旧密码的原生输入断言；全选删除后，第二次实际验证错密拒绝、账号输入保留及正确密码登录（login 401→200、state 200，原账本 1,133 分）。约 1 秒后立即终止重启，state 401、账户按钮未出现；不是协调器校验误报。根因尚未确定，不能把完整 login 标绿，也未增加第三次执行。原核心 UI 的较晚重开仍通过，两种条件差异保留。原件 `round2/account-PasswordLogin-1791454019/evidence.json`、`native/ui.log`、`native/ui.xcresult`。
- XCTest 发码/校验的事件坐标与失败后的控件位置存在偏移，服务端没有收到相应 phone_send/email_verify；中心坐标方案也未解决。根因仍未定，不宣称已修产品或已证明纯测试问题。原核心 UI 用同一新 SDK 包回归通过（106.3 秒），保留测试条件差异。
- 新 SDK、共享字节检查、sop.test、functionality/recovery、privacy、Watch/Vision 原类型检查均通过；Watch 本轮只补跑原入口 1 次并成功。Watch 业务源码未改，首轮瞬时时序没有被证明；本轮真实 WC 登录/退出成功不等于已反推首轮根因。
- 首轮 `codex.log` 当前无凭据残留，保留 90 处旧脱敏标记；Mini 未找到对应 `.stversions` 历史。本轮 `round2/product.log` 曾再次回显同一类 GitHub PAT，现已脱敏 600。Syncthing 元数据证明 Air M4 持有当前脱敏 codex.log；原含凭据版本是否曾同步及 Air 历史副本未直接回读，不能声称已清空。macbook 名称解析失败后，按新鲜 Syncthing 地址保持原严格主机指纹再连接，SSH 超时，无远端写入；原件 `round2/air-log-audit-execution.json`。建议轮换 GitHub PAT（GH_TOKEN / HOMEBREW_GITHUB_API_TOKEN），不打印值、不自动撤销。
- 收尾扫描本任务129份文本日志，另发现本轮完整调度输出 `output/points2.log` 也含同次PAT，已原地脱敏600；其他128份无需新改，token模式残留0。points2.log含凭据版本是否已同步Air及历史残留未证实；Air审计脚本已覆盖两轮日志，见 `round2/log-audit-all-task.json`。
- 最终同步只读回读 `round2/log-sync-final.json` 再次确认Air持有当前脱敏codex.log；points2.log仍活动增长、索引大小落后，不能宣称Air该日志已完整脱敏。
- Mini 无 HQ ASC 客户端要求的 P8 私钥；Air 当前凭据可用性尚未实查。下一轮必须先完成 16 项原生实际流程、当前输入原门，再沿正式版本与 cloud 工具链门发行。版本改动会改变 account 输入绑定，不能只手改 hash 凑绿。精确 Air 存储复验、历史日志检查、条件满足后的提交/推送/发行命令写在 receipt 第二轮。
- 回执 `/Users/tianli/mac-pair/tasks/points-account-release-20261008/output/receipt.md`；限定变更补丁及 SHA 见 `round2/authorized-changes.patch` / `authorized-changes.json`。原有 266 个无关未提交文件逐个 SHA 未变，Git index 空、HEAD 仍 cf49b5a。保留本轮原件；所有本轮模拟器/演示服务已由原入口关闭。

### 第二轮过程记录（以下为当时状态）

- 2026-10-08 16:41（上海）开工，120 分钟预算，18:41 截止；同因失败最多 2 次，Watch 原入口至多补跑 2 次。用户授权保持：Agent 验收并发版，门不放宽。存储若证实为 SSH 钥匙串环境问题则移交 Air，发版前必须绿。
- 已完整读取首轮 receipt 和本 handoff。原待提交补丁保留，有限范围为共享生命周期正式同步、Watch 原缺陷/时序诊断、17 项原生账号实际证据、日志凭据检查、必要回归和条件满足后的发行。
- 共享生命周期经总部 `vendor-lifecycle.py --platform ios --target-source-dir .../Shared` 正式同步，`--check` 通过；原 `run.sh privacy` 已退出 0。原静态门允许仅逐字节匹配责任源的官方版本元数据域名，无门或白名单修改。
- 双机 claims 已按产品具体文件和本任务 output 声明；`.stversions` 范围推导为 mac-pair 项目会与 Air 其他任务相撞，未越过该准入，Mini 未找到本任务对应历史文件。
- 最小无产品依赖钥匙串诊断：SecItemAdd 返回 -25308 / User interaction is not allowed，读取及清理均 -25300（条目未创建）；security show-keychain-info 同为不可交互。证明首轮 Mac 存储门环境受阻；未解锁、未改钥匙串设置。此门必须 Air 登录会话原样重跑。
- 新 Release SDK 包由原 platform_ui.py product 入口构建，干净非秘密环境下退出 0。直接继承 shell 的首次尝试仍因失效 CC/CXX 失败，错误里带 GitHub PAT；本轮读取错误再次回显，已脱敏 round2/product.log，必须建议轮换 GitHub PAT。后续构建/测试只传必要环境。
- Watch 第二轮原入口只补跑 1 次，退出 0，190.8 秒；原真实配对、无 cookie/context/dev 参数注入，收到 WatchHome ready；原始退出后截图已目视为“在 iPhone 上登录”。WatchLink / 接收端源码未改；首轮具体瞬时时序未能反推，当前没有可复现的业务源码缺陷。证据 round2/watch-1/。
- 原生账号补证沿原 XCTest production bundle 车道新增 Tests/AccountUITests.swift；不替换 Api/Store/存储。邮箱完整候选两次停在重叠政策弹窗的 XCTest 控件定位，均 0 邮件/0 短信，保留失败原件，停止重复该段。剩余邮件实际流程与手机流程分项接续，局部通过不创建完整 account_lifecycle PASS。
- 本人登记手机号去重只有 1 个，phone_change 无第二个授权号码，现行门没有豁免。真实 Mailu IMAP TLS 登录通过，沿既有 hi+treasury-* 本人测试别名；所有发送合计受 20 短信/20 邮件限制。
- Mini 原 ASC 预检缺 pyjwt；uv 官方依赖补足后证实本机无 ASC P8 私钥，不能在 Mini 执行正式 ASC 核验/提审。Air 登录会话才可接续；不复制或打印凭据。所有原门未齐前不提交/推送。

- 原任务：`20261008-1130-points-account-readonly`；发行任务：`points-account-release-20261008`。
- 开始：2026-10-08 16:17（上海）；预算 90 分钟，截止 17:47；同因失败最多 2 次。
- 授权：Agent 代替本人验收并提交/发行；测试门、发行门原样保留，前一步不过不进入下一步。
- 输入 HEAD `cf49b5a8cb99fc6bca592dc56ec8ef0f6fd9166f`，声明版本 `1.0.2 (9)`。五份待改源码 SHA256 与原回执一致。
- 写入范围：`Sources/Api.swift`、`Sources/Store.swift`、`Sources/PhoneAccountView.swift`、`Sources/AccountSecurityView.swift`、`Sources/AccountView.swift`、本交接；仓外证据为 `/Users/tianli/mac-pair/tasks/points-account-release-20261008/output/`。
- 仓内原有 project.yaml、perf/acceptance、perf/account 等未提交内容保留；不覆盖、不夹带。版本号仅在验收通过后进入发行时修改。
- 阶段：①规则/回执/claims；②SHA核对与3组最小补丁；③9+9隔离场景、原回归、类型检查、真实SDK构建、可自动原生验收、account_lifecycle原门；④限定pathspec提交与原流程推送；⑤正式版本/工具链门、归档签名上传与提审；⑥回执与交接。
- 本机可能的原生验收沿原 `scripts/accept/platform_ui.py` / `storage.py`、`sim_lane`，不合成界面输入，不发送未经原授权的真实短信/邮件。
- 阶段①②完成：五份基线一致，补丁已落入业务工作树；无相关文件的其他未提交改动。
- 阶段③：重新编译18个隔离观察，9缺陷消除/9正常行为保留；原 `sop.test`、iPhone 34源类型检查、功能/恢复、3项账号补充回归通过。Release模拟器SDK构建通过（Xcode27.0/27A266a，1.0.2/9，主App/Widget/Watch/Watch Widget各5张图）。原XCTest iPad生产包的新建项目/奖励、服务端保存回读、重开恢复、退出与密码重新登录通过；只证明这个隔离模拟器范围。
- 未通过：`scripts/accept/run.sh privacy` 返回4；共享 `AppLifecycle.swift`、`AppConfiguration.swift` 与总部责任源不同，官方更新域名随之被拒。未改这两份共享副本或隐私门；在补丁前HEAD的五份源码对照中也有相同4项错误。
- 未通过：原 `scripts/accept/storage.py` 返回1，`FAIL: production snapshot written and read`。`security show-keychain-info` 返回 `User interaction is not allowed.`；未改钥匙串权限、未将内存替身称为实际存储通过。
- 原账号门返回75，23条缺口、17项完整原生证据仍不齐；当前 `expected_account_input_sha256=bf9065b1312d7c8c0eb8ee3b9e226d05c62bc300e24f7b3104512dad818f27c9`。没有创建伪索引、没有撤暂缓。
- Watch首次因原负载门19.0≥12返回75；实际条件恢复8.1<12后原入口补一次真实配对检查，退出1：`RuntimeError: real WC never entered WatchHome; no injected login fallback`。实际新建配对记录active、手机端原XCTest登录/退出128.019秒通过；Watch未到主页，整体联动失败。未注入Watch凭据或放宽门，不再重试。原入口已关闭自己设备。
- iPad六张原始截图已导出并目视；有顶部黑区和右侧截取，不能据此宣称完整平板布局/商店截图通过。
- 首次构建因继承不存在的LLVM编译器路径失败；只清理本次子进程的编译/敏感环境后第二次成功。首错日志回显凭据后已脱敏、权限600；没有将凭据放入交接或回执正文。
- 阶段④⑤不得进入：按本人“前一步不过不进下一步”，保留已验证最小补丁，未提交/推送/升版/归档/上传/提审。HEAD仍cf49b5a，版本1.0.2(9)。这不是等待本人批准；需恢复具体测试条件与补齐原生真实双通道证据。
- 证据与最终回执：`/Users/tianli/mac-pair/tasks/points-account-release-20261008/output/receipt.md`；持久补丁 `account-fix.patch` SHA256 `115f64ce1edee7180b716ce74236ca62f697988ee94adc9b7ff3760b2fa66360`。没有派Air队列，也没有修改macmini交接脚本。
- 收束：约16:35，约18分钟。原有266个未提交文件SHA全部未变，5份补丁仍与候选逐字节一致，diff检查通过、Git index及HEAD未变。所有本轮模拟器已关机，两份演示账本服务已停，私有合成夹具移至 `/tmp/points-account-release-20261008/private-fixtures/`。未进入正式签名/ASC能力探测，不能断言发行能力只在Air；没有可供Air上传的归档。原17项缺口和Air先重读测试门的精确命令已列在receipt。
