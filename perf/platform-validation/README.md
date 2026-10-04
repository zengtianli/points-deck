# Points · 其他 Apple 平台验收

本轮源码：`39ea345`。**iPad、Mac、Apple Watch、Apple Vision Pro 的必要平台功能验收已完成。** 构建、实际启动和界面、核心行为、保存恢复、适用隐私均有通过证据。iPad、Watch、Vision 使用 Xcode 27 模拟器；Mac 使用本机原生客户端。

| 平台 | 实际行为证据 | 必要验收 |
|---|---|---|
| iPad | 原生新建项目和奖励、服务器保存、会话重开、退出与密码登录；2752×2064 真横屏；最大辅助字号 | 通过 |
| Mac | 原生五页、760×540 最小窗、Cmd-W 菜单映射及实际窗口关闭；包内 CLI 对真实隔离 HTTP 服务读取账本与配置 | 通过 |
| Apple Watch | 原生配对、激活与连接；手机登录后真实 WC 收到 1133 分摘要；手机退出后手表回到登录提示 | 通过 |
| Apple Vision Pro | 原生窗口五页、键盘输入、新建与服务器保存、存储会话重开、实际窗口滚动；修复后原生退出和密码登录通过 | 通过 |

观察原件分别见 [iPad](ipad/proof.json)、[Mac](mac/hosted-proof.json)、[当前包内 CLI](mac/current-bundled-cli.json)、[Watch](watch/proof.json) 、[真实配对](watch/actual-pair.json) 和 [Vision 当前 UI](vision/proof.json)。截图记录位于各平台的 `captures/capture.json` 与 `store-shots.json`；原失败与原绑定保留，未改成新源码通过结果。

`39ea345` 仅修改 `TreasuryChoice` 的 visionOS 分支，为选项保留独立无障碍名称，组名放入提示；其他平台实现未改变，核对见 [修改范围](vision/accessibility-fix.json)。这些端的原行为观察继续适用，原绑定保持不变。四端当前 SDK 见 [构建记录](builds/manifest.json)，当前 Chapter 实际启动全部通过，见 [启动记录](current-launches.json)。

共享功能、恢复、隐私沿原 Chapter 验收全部通过，见 [原件索引](current-shared-acceptance.json)；[注册测试](current-test.json) 的 `ok` 与 `input_stable` 均为 true。另有 [生产存储原件](storage/proof.json)：四个独立 Mac 进程实际验证 Keychain、账本缓存、待确认请求与摘要保存／清理，共 11 条断言；该原件的范围为 Mac Keychain。

额外资源采样独立留证，不再作为本次功能交付的前置：当前输入的 [iPad](ipad/current-resource.json)、[Watch](watch/current-resource.json)、[Mac](mac/current-resource.json) 已通过。分别为 31／23／42 MiB，闲置 CPU 均为 0.0%，五次冷启动中位 897／773／454 ms。[Vision 原后台采样](vision/current-resource.json) 于 22:53:58 自然完成：49 MiB、0.05%、7477 ms；此结果在 22:45 功能交付结案之后读取，没有重启验收。Chapter 整体状态原样保留于 `current-chapter-platforms.json`，不等同于本次五项必要验收结论。

邮箱生产投递已有真实 Mailu 原件。阿里云短信尚未完成云端配置及真实投递，本报告不将账号完整闭环或全部发布 SOP 标为通过。移动端运行数字只代表模拟器；Mac 资源只统计 App 宿主。TestFlight 分发另由 ASC 回读确认，本报告不代表设备已安装更新或其他平台已上架。

当前 [Mac 本地包证据](mac/current-artifact.json) 已核深签名和可执行文件，测试包位于 `build/accept/mac/Growth Treasury.app`；TestFlight **1.0.2（11）** 已回读 VALID / IN_BETA_TESTING，family 组有 2 位测试成员，主包、Watch、小组件真实归档均为 build 11。原件见 [发行记录](../raw/testflight-1.0.2-11.json)。

用户要求的 [本会话 HTML 汇报](../../docs/reports/points-session-20261004.html) 包含实际改动、真实截图、必要修复、额外耗时与未完成项。网站只同步了账号协议和部分操作，完整视觉未与原生 App 统一；这是明确交付缺项，不计入已完成结论。

用户再次明确先理解需求、核清底座再做，并强调时间对工作有直接影响。[需求与底座诊断](../../docs/reports/points-next-scope-20261004.md) 已列出原规则、具体脚本缺口、最小修法、下一轮顺序和停止条件；该诊断不触发已通过平台重测，也不等同于底座代码已经修复。
