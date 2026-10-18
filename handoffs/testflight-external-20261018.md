# 成长小金库 · iOS TestFlight 外部测试 · 2026-10-18

**1.0.3 (13) 已提交 Beta 审核，最终回读为 `WAITING_FOR_REVIEW`，三位指定测试员均在独立外部组，`autoNotifyEnabled=true`。** 最终回读时间：2026-10-18 14:47:52（上海）。复用 ASC 已有最新 `IOS / VALID / expired=false` 包，没有构建或重传。正式 App Store 1.0.3 仍为 `PREPARE_FOR_SUBMISSION`；未提交、重提或回复正式审核。

本轮完成外部测试配置与 Beta 排队。Apple 尚未批准本包的外部测试，不能据此声称外部邀请已送达、测试员已安装本包或已取得反馈。等待 Beta 审核属于 Apple 队列状态，不记本轮任务受阻。

## 范围、身份和对象

遵循 [Mac 批次 SOP 第 3–7 步](/Users/tianli/Apps/keyscope/handoffs/2026-10-18-app-review/testflight-mac-batch.md)，平台为 IOS，仅处理本产品。执行机为 `TianliMac-Mini.local`，API 沿共享 `asc.py`、`asc_release.all_pages` 与原凭证加载，不创建团队用户或扩大 ASC 团队权限。

本地仅写本记录及 [同名证据目录](testflight-external-20261018/)。复用 Chapter 精确身份 `--pid 32970 --session chapter-task:ea00a6ec028749e49e77b24bb8426d4b`，写前使用原 `claims.py check` 核对，不另开声明，不释放 Chapter 声明。共享资源仅使用 ASC API；本轮不使用构建槽、模拟器、性能测量或装机资源。保留其他会话的源码、暂存、性能资料和后台。

完成条件：已有最新有效 IOS build 关联独立外部组，三位测试员、审核联系人、演示条件、测试说明、自动通知与 Beta submission 均有回读，正式审核对象前后未变，本记录和证据本地提交。后续推送交 Chapter，本轮不执行 `git push`。

| 对象 | 实际值 |
| --- | --- |
| ASC App / Bundle | `6806799638` / `cyou.tianli.pointsdeck` |
| 平台 / 营销版本 / build | `IOS` / `1.0.3` / `13` |
| Build ID | `8ce9e986-bd65-450f-b2fc-62ddba43ea28` |
| 上传时间 | `2026-10-17T04:06:18-07:00` |
| 过期时间 | `2027-01-15T03:06:18-08:00` |
| 外部组 | `Growth Treasury iOS Beta` / `1e40b808-d775-4bbd-9f0a-f96c6cfc3eec` |
| Beta submission | `8ce9e986-bd65-450f-b2fc-62ddba43ea28` |
| Beta 提交时间 | `2026-10-17T23:47:31-07:00`（上海 2026-10-18 14:47:31） |
| 正式资料来源版本 | `604a9480-62ed-4102-80b5-b5f3666a6210`（1.0.3） |
| 正式审核 detail | `3a3ea26e-d57c-447c-9684-0c86cdfe6152` |
| 本轮开始时源码 HEAD | `498349cd6da5a4a1b3db1d1b1388920c3487503e` |

源码 HEAD 仅标识本轮管理操作所在仓库，不充当上传包的源码绑定或本轮功能验收证据。

## 第 3 步：独立外部组和测试员

完整分页查询 IOS build，共 12 条；按上传时间选择最新 VALID、未过期包，确认 preReleaseVersion 为 IOS / 1.0.3。原 ASC 只有内部 `family` 组，本轮创建独立外部组，GET 回读 `isInternalGroup=false`、`publicLinkEnabled=false`。没有改动内部组或其他平台 build。

| 上海时间 | 操作回执与回读 |
| --- | --- |
| 14:46:37 | 核对已有 1.0.3 (13)，VALID、未过期；全部 IOS build 清单保存在 `steps.json` 的 `validate_existing_build` |
| 14:46:42 | 创建外部组，回读组 ID、名称与 `isInternalGroup=false` |
| 14:46:48 | 按本 App + 邮箱查询复用第一位 tester；加入组关系返回 204，再 GET 确认成员 |
| 14:46:55 | 第二位 tester 在本 App 中不存在，按本组关系创建，再 GET 确认成员 |
| 14:47:02 | 第三位 tester 同法创建，再 GET 确认成员 |

| 邮箱 | 本 App tester ID | 最终 API state |
| --- | --- | --- |
| zengtianli1@126.com | `87c40bc0-87d2-4091-aae0-2d01ee9e9334` | `INSTALLED`（既有 App 级状态） |
| zengtianli2@126.com | `b488aca7-2413-415c-ac18-f1ecbb653abd` | `NOT_INVITED` |
| zengtianli3@126.com | `4fd76541-7a5e-4edf-abe2-9febaa5be90b` | `NOT_INVITED` |

第一位的既有 INSTALLED 不证明本轮外部邀请已发或本轮安装了 1.0.3 (13)。

## 第 4 步：审核资料与 What to Test

14:47:09：Beta 审核联系人复制自本 App 正式 1.0.3 审核资料，PATCH 返回 200。四项联系人字段逐值回读一致。该产品需要登录，保留来源的 `demoAccountRequired=true`，并复制现有演示账号、密码和 Review Notes；八个字段全部逐值匹配。凭据只在内存和 ASC 专用字段传递，证据仅保存匹配布尔值，不保存凭据。

14:47:13：创建 `zh-Hans` Beta 描述，复用正式版本描述；反馈邮箱与正式审核联系人一致，隐私链接为 `https://app-ios-points-deck.tianli.cyou/privacy.html`，写后逐字段回读一致。

14:47:17 / 14:47:20：分别写入并精确回读中文、英文 `betaBuildLocalizations.whatsNew`。中文 What to Test：

> 请在 iPhone 或 iPad 上试用成长小金库的主要流程：手机号验证码或邮箱账号登录，查看账本与积分余额，记录固定项目和参数项目、临时加减分并撤销，查看积分走势，兑换奖励，管理项目与奖励，以及账户设置、退出和重新登录。请反馈无法完成的操作、余额或记录显示异常、看不懂的提示和不顺手之处；也请留意网络失败后的提示与输入保留。

英文对应相同流程；两种语言的完整文本、localization ID 与逐步回读均在 [steps.json](testflight-external-20261018/steps.json)。测试说明是请测试者覆盖的范围，不是本轮已完成客户端实测的声明。

## 第 5–6 步：关联 build、Beta 排队与通知

| 上海时间 | 操作回执与回读 |
| --- | --- |
| 14:47:23 | `buildBetaDetails.autoNotifyEnabled` 已为 true，本轮保留并 GET 确认；内部仍 `IN_BETA_TESTING` |
| 14:47:28 | 外部组关联 build 返回 204；GET 组 builds 确认含指定 build ID |
| 14:47:32 | 按指定 build 查询 Beta submission 为空后才 POST 创建；返回指定 submission ID 与 `WAITING_FOR_REVIEW` |
| 14:47:52 | 最终 GET 确认 `WAITING_FOR_REVIEW`、提交时间非空、外部 `WAITING_FOR_BETA_REVIEW`、自动通知 true、组 build 和三位成员完整 |

第 6 步判定：外部安装需等 Beta 批准；当前不重复发送邀请，也不把两个 `NOT_INVITED` 写成已通知。Apple 批准后自动通知已开启。后续只读回同一 submission、组与 tester 状态；仍有缺失时才补官方邀请，不重复提交或上传。本轮没有新安装、收件箱回执或外部反馈证据。

## 第 7 步：正式审核保护与交付核验

操作前后全量正式版本属性、正式 `reviewSubmissions` 和每个版本的 build 关系逐项相等；正式 1.0.3 审核 detail 全字段亦未改变。

- 1.0.3：`PREPARE_FOR_SUBMISSION`，仍关联 build 13。
- 1.0.2、1.0：保留 `READY_FOR_SALE` / `READY_FOR_DISTRIBUTION`。
- 三个原正式 submission 均保持 `COMPLETE`；没有新增正式 submission。
- Beta 操作与正式审核分开，未调用正式提交、重提或消息回复接口。

运行 `chapter xcode-cloud status --repo . --json`，本仓 `push_allowed=true`、`state=ok`，原回执在 [xcode-cloud.json](testflight-external-20261018/xcode-cloud.json)。该结果来自共享探针，本轮没有另改 Cloud workflow，也未推送；Chapter 实际推送前仍须经过当时的闸与原 pre-push 钩子。

本轮验收为实际 ASC 写入后的 GET 回读、正式对象前后比较、证据 JSON 与文档检查。没有改 App 源码、构建、上传、运行客户端测试或装机，不把旧性能/SOP 证据当作本包新验收。

证据索引：

- [preflight.json](testflight-external-20261018/preflight.json)：操作前对象、正式审核基线、来源资料字段是否存在。
- [steps.json](testflight-external-20261018/steps.json)：每步时间、返回对象/关系回执、最终回读与正式对象前后比较。
- [execute.py](testflight-external-20261018/execute.py)：本轮一次性 API 操作原文，写接口仅允许 Beta 资源，含原 claims check；不是构建或上传入口。已完成后不需重跑。
- [xcode-cloud.json](testflight-external-20261018/xcode-cloud.json)：本仓推送资格只读回执。

本记录及同名证据本地提交，推送由 Chapter 收尾。未推送不是本轮受阻。任务配置与回读已完成，后续 Beta 批准时间由 Apple 决定。
