# 成长小金库 1.0.2 已提交审核 · 2026-10-09

**线上状态（ASC 回读 2026-10-09 01:36）：1.0.2 (12) `WAITING_FOR_REVIEW`，提交 `a3f4a35b-e56a-45b1-8384-0442f0e0c9fc`；在售仍是 1.0。** 回读原件 `~/mac-pair/tasks/points-account-release-20261008/output/release/submission-readback.json`。

## 经过
- 本人 2026-10-09 01:2x 决定：“别搞了，就直接上架好了”。账号 17 项原生验收停止，**账号门未通过即送审，是本人放行**；正式索引 `perf/account/account-lifecycle.json` 仍是旧的 4/17，未更新。
- 归档与上传在 Air 本机完成（总部 `push-testflight.sh --no-wait points-deck`，放进 Air 图形会话的一次性 launchd 任务跑；经 SSH 直接跑会在签名处报 `errSecInternalComponent`）。没有推送 origin/main，没有触发 Xcode Cloud；origin 落后于已送审源码（HEAD `7aa33ad` 及之后的本地提交）。
- 商店版本由 1.0.1（DEVELOPER_REJECTED）改名为 1.0.2，更新说明已改写；因包内带手表 App，补传 1 张 Apple Watch 截图（`shots/appstore/watch/01-balance.png`，已登记进 `products.yaml` 的 store.shots）。

## 验收做到哪（停止时）
- 原生账号 UI 测试改到 iPhone 模拟器并修通：6 个用例全部离线跑通（0 短信）。`Tests/AccountUITests.swift`、`scripts/accept/platform_ui.py`（加 `--platform iphone`）已随本次提交。
- 真实通道只完成：手机绑定（通过）、密码登录（通过）；手机全流程走到短信登录后被停。10-09 凌晨共发短信 7 条（其中 1 条到第二号码），累计 14 条。
- 调度脚本与证据在仓外 `~/mac-pair/tasks/points-account-release-20261008/output/round5/`（`account_native.py`、`index_round7.py`、`contract.json` 已标停止）。

## 留给下一轮（都不需要发版）
1. **后端缺陷**：输错短信验证码时返回 503“短信核验服务暂不可用”，应为“验证码不正确”。原因在 `aliyun_sms.py` 的 `call_body` 把供应商对错码的拒绝当成服务异常，`account_phone.verify_phone` 映射成 503。错码确实被拒、未发放授权。
2. **换绑手机未验**：第二个号码的短信不转发到本人 Mac，读不到验证码。
3. 数字键盘没有“完成”键：换绑页上键盘会盖住“获取短信验证码”，要先滑动页面。
4. 商店隐私标签是否已含“手机号”需在 ASC 网页核对（接口查不了）；iPhone 商店截图仍是旧版界面（含“家长模式”字样）。
5. 真实短信取码：Mini 终端没有读“信息”库的权限，Air 有；本轮经 `ssh macbook` 调 `sms_otp.py`。
