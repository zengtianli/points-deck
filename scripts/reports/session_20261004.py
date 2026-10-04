#!/usr/bin/env python3
"""Build the offline, evidence-backed Points session report requested by the user."""
from pathlib import Path
import base64
import datetime as dt
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, '/Users/tianli/Dev/tools/dev/lib')
from html_shell import esc, shared_head, shared_footer

SESSION = '01a10635-15a4-76a1-93fb-63d403b8852f'
SOURCE = 'c8c72e0b33de8cff6d5b9a3c48f7c74eb0880bc59ccae60f1507f4dd9cf4c323'
GENERATED = dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat(timespec='seconds')
OUT = ROOT / 'docs/reports/points-session-20261004.html'


def load(path):
    return json.loads((ROOT / path).read_text())


def proof(path, title):
    original = ROOT / path
    data = json.loads(original.read_text())
    digest = hashlib.sha256(original.read_bytes()).hexdigest()
    return (f'<details class="evidence"><summary>{esc(title)}</summary>'
            f'<p class="path">{esc(path)}</p><p class="path">SHA256 {digest}</p>'
            f'<pre>{esc(json.dumps(data, ensure_ascii=False, indent=2))}</pre></details>')


def photo(path, title, note):
    raw = (ROOT / path).read_bytes()
    src = 'data:image/png;base64,' + base64.b64encode(raw).decode()
    return (f'<figure><img src="{src}" alt="{esc(title)}" loading="lazy">'
            f'<figcaption><strong>{esc(title)}</strong><span>{esc(note)}</span>'
            f'<small>{esc(path)}</small></figcaption></figure>')


CSS = r'''
:root{--bg:#f8f7f2;--panel:#fff;--border:#e5e7e2;--fg:#25352f;--mute:#6e7772;
 --link:#257f70;--green:#257f70;--amber:#906617;--red:#ab493f;--purple:#257f70;--cc-tbg:#fff}
html{scroll-behavior:smooth;scroll-padding-top:92px}body{font-size:16px;line-height:1.75}
.wrap{max-width:none;padding:0 clamp(18px,4vw,68px) 60px;margin:0 auto}
h1,h2,h3,h4{color:var(--fg)}h1{font-size:clamp(30px,4vw,52px);border:0;letter-spacing:-1px;line-height:1.25;margin:14px 0}
h2{border:0;padding:0;margin:0 0 18px;font-size:25px}h3{margin:0 0 10px;font-size:19px}
p{margin:9px 0 15px}.eyebrow{color:var(--green);font-weight:650;font-size:13px;letter-spacing:1px}
.hero{padding:40px 0 24px}.intro{font-size:18px;max-width:1000px;color:var(--mute)}
.pills{display:flex;flex-wrap:wrap;gap:8px;margin:22px 0}.pill{display:inline-block;border-radius:30px;padding:6px 13px;font-size:13px;background:#e8f1ed;color:#257f70}
.pill.pending{background:#f7eedc;color:#906617}.pill.neutral{background:#eef0ec;color:#65716a}
nav{position:sticky;top:0;z-index:20;background:rgba(248,247,242,.96);padding:10px 0 14px;border-bottom:1px solid var(--border)}
nav .segments{display:flex;gap:4px;flex-wrap:wrap;background:#eeefea;border-radius:22px;padding:5px;width:fit-content;max-width:100%}
nav a{padding:7px 18px;border-radius:18px;color:var(--fg);font-size:14px;font-weight:650}nav a:hover,nav a:focus{background:#fff;text-decoration:none;color:var(--green)}
section{padding:32px 0;border-bottom:1px solid var(--border)}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}.grid.two{grid-template-columns:repeat(2,minmax(0,1fr))}
.card{background:#fff;border:1px solid var(--border);border-radius:22px;padding:24px;min-width:0}
.big{font-size:34px;font-weight:750;line-height:1.2;margin:12px 0;color:var(--green)}.sub{font-size:14px;color:var(--mute)}
.callout{border-left:4px solid var(--green);background:#edf4ef;border-radius:0 14px 14px 0;padding:18px 22px;margin:18px 0}
.callout.amber{border-color:#b98a38;background:#fbf3e5}.callout p:last-child{margin-bottom:0}
.list{padding-left:21px;margin:10px 0}.list li{margin:7px 0}.status{color:var(--green);font-weight:700}.pending-text{color:var(--amber);font-weight:700}
.table-scroll{overflow:auto}table{min-width:670px;background:white;border-radius:16px;overflow:hidden;border:1px solid var(--border)}
th,td{padding:15px 18px;border:0;border-bottom:1px solid var(--border)}th{color:var(--mute);background:#f0f2ed}td small{display:block;color:var(--mute)}
code{color:var(--green);background:#eef3ef;border-radius:6px;overflow-wrap:anywhere}pre{color:var(--fg);background:#f5f7f3;white-space:pre-wrap;overflow-wrap:anywhere;max-height:440px;overflow:auto}
.gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.gallery figure{margin:0;min-width:0;background:white;border:1px solid var(--border);border-radius:22px;overflow:hidden}
.gallery img{display:block;width:100%;height:380px;object-fit:contain;background:#f0f2ee;padding:12px}.gallery figure:first-child{grid-row:span 2}.gallery figure:first-child img{height:780px}
figcaption{padding:17px 20px}figcaption span,figcaption small{display:block;color:var(--mute);font-size:13px;margin-top:5px}figcaption small{font-size:11px;overflow-wrap:anywhere}
.timeline{display:grid;gap:0;margin:20px 0}.event{display:grid;grid-template-columns:80px 1fr;gap:16px;padding:16px 0;border-bottom:1px solid var(--border)}.event time{color:var(--green);font-variant-numeric:tabular-nums;font-weight:700}.event strong{display:block}.event p{margin:3px 0;color:var(--mute);font-size:14px}
.evidence{background:#fff;border:1px solid var(--border);border-radius:15px;padding:14px 19px;margin:11px 0}.evidence summary{cursor:pointer;font-weight:650}.path{font-size:12px;overflow-wrap:anywhere;color:var(--mute);margin:8px 0}
#cc-session-footer{background:white;border:1px solid var(--border);border-top:2px solid var(--green);border-radius:16px;color:var(--mute);font-size:11px;overflow-wrap:anywhere}
#cc-session-footer .label{color:var(--green)}#cc-session-footer code{background:#eef3ef;color:var(--fg)}
@media(max-width:760px){.grid,.grid.two,.gallery{grid-template-columns:1fr}.gallery figure:first-child{grid-row:auto}.gallery figure:first-child img{height:440px}.gallery img{height:300px}.card{padding:19px}nav a{padding:6px 10px;font-size:13px}.event{grid-template-columns:64px 1fr;gap:10px}.hero{padding-top:25px}}
@media print{nav{position:static}details{break-inside:avoid}.wrap{padding:0}.card,figure{break-inside:avoid}}
'''

release = load('perf/asc-release.json')
assert release['build'] == '11' and release['processing_state'] == 'VALID'
assert load('perf/platform-validation/current-test.json')['input_stable'] is True
assert load('perf/platform-validation/current-launches.json')['ok'] is True
metrics = []
for lane, label in [('ipad', 'iPad'), ('mac', 'Mac'), ('watch', 'Watch'), ('vision', 'Vision')]:
    d = load(f'perf/platforms/{lane}.json')
    assert d['input_sha256'] == SOURCE
    raw = ROOT / d['runtime_measurement']['evidence']
    assert hashlib.sha256(raw.read_bytes()).hexdigest() == d['runtime_measurement']['evidence_sha256']
    metrics.append(f'<tr><td>{label}<small>{"本机原生" if lane == "mac" else "模拟器"}</small></td>'
                   f'<td>{d["idle"]["memory_mb"]:g} MiB</td><td>{d["idle"]["cpu_pct"]:g}%</td>'
                   f'<td>{d["speed"]["cold_launch_ms"]/1000:.3f} s</td>'
                   f'<td>{d["size"]["download_mb"]:.2f} / {d["size"]["installed_mb"]:.2f} MB</td></tr>')

body = r'''
<body><main class="wrap">
<header class="hero"><div class="eyebrow">POINTS · 成长小金库 / 2026 年 10 月 4 日 · 会话工作汇报</div>
<h1>这一轮，做了什么？</h1>
<p class="intro">你要的是按 PRD 改好 App、用好已有底座、尽快测试，并完成其他平台验收。这页展示实际交付、真截图、必要修复和多花时间的环节。</p>
<div class="pills"><span class="pill">新版 App 可测试</span><span class="pill">其他四端必要功能验收通过</span><span class="pill">网页本地主题与五栏已统一</span><span class="pill pending">网页本轮修复未部署</span><span class="pill pending">真实短信投递未验</span></div>
<div class="callout"><strong>这次修复的边界</strong><p>只改 Points 自己的执行脚本与教育站积分页面，避开其他 Codex 已声明的 Chapter、HARNESS 和共享 skills。排锁、准备、执行和清理现在共用总时限；不选平台会拒绝执行，功能模式不再重复等性能门。网页三页本地统一暖白、绿色和五栏目，真实隔离账本操作已检查。此前 Apple 平台验收沿用，没有重跑模拟器或性能采样。</p></div>
</header>
<nav aria-label="汇报导航"><div class="segments"><a href="#delivery">交付</a><a href="#changes">改动</a><a href="#screens">真截图</a><a href="#time">为什么慢</a><a href="#evidence">未完与证据</a></div></nav>

<section id="delivery"><h2>现在能拿到什么</h2><div class="grid">
<article class="card"><h3>iPhone / iPad</h3><div class="big">1.0.2（11）</div><p>TestFlight 的 family 内测组已包含新构建，Apple 状态为 VALID / IN_BETA_TESTING。</p><p class="sub">主 App、Watch、小组件归档均为 build 11。手机是否已更新，尚未实机回读。</p></article>
<article class="card"><h3>Mac</h3><div class="big">本地测试包</div><p>Release 包已核深度签名，包内 <code>treasury</code> 对真实隔离后台读取版本、账本、配置通过。</p><p class="path">build/accept/mac/Growth Treasury.app</p><p class="sub">本地构建 1.0.2（9），与 TestFlight 编号分别记录。</p></article>
<article class="card"><h3>共享后端与邮件</h3><div class="big">已上线 / 已收信</div><p>沿现有 VPS 部署服务和三份 Web 页面；真实 Mailu 发信、收信、账号通知已有原件。</p><p class="sub">部署前后原账本文件汇总 SHA256 一致；公网原账号只读回归通过。</p></article>
</div><p class="sub">商店在售仍为旧版 1.0（2）；本轮 TestFlight 发布没有另送商店审核。其他平台不等于已上架。</p></section>

<section id="changes"><h2>实际改了哪些功能</h2><div class="grid two">
<article class="card"><h3>家长日常操作</h3><ul class="list"><li>iPhone／iPad 五栏目：账本、走势、加分、兑换、账户；Mac／Vision 同顺序侧栏。</li><li>浅色大卡片，一键固定分、参数预览、临时加减分、五秒撤销和账本详情撤销。</li><li>项目／奖励就地新建、编辑、排序、归档；旧复杂规则与历史保留。</li><li>新奖励默认无等级门槛，兑换检查价格、条件版本与余额。</li></ul></article>
<article class="card"><h3>数据与账号</h3><ul class="list"><li>稳定请求标识、超时查询、重复撤销幂等；未确认交易存本设备钥匙串。</li><li>配置 revision 冲突检查；离线账本缓存；退出和账号失效清理快照与会话。</li><li>邮箱验证码注册、绑定／换绑、改密、未登录找回、注销及回执入口。</li><li>手机账号入口、后端与 CLI 已接线；云端短信配置及真实投递仍未完成。</li></ul></article>
</div><div class="callout"><strong>复用了哪些现成底座</strong><p>Chapter 管注册验收与任务队列；sim_lane 管严格构建缓存、真实 SDK 与模拟器车道；<code>treasury</code> CLI、Swift API 和 Web 共用教育平台接口；邮件复用 VPS Mailu，短信接已有 AliyunSmsAuth。没有给 Points 新建另一套生产账号服务。</p></div>
<h3>测试中发现并修好的产品问题</h3><div class="table-scroll"><table data-no-sort data-no-ui><thead><tr><th>问题</th><th>实际修复与结果</th><th>源码提交</th></tr></thead><tbody>
<tr><td>iPad 点新建后，编辑字段没有呈现</td><td>新建／管理及正负类型交给同一个弹窗状态；原生新项目与奖励保存、服务器读回通过。</td><td><code>1502eab</code></td></tr>
<tr><td>Vision 白卡内文字及分段选择难以读清</td><td>显式深色正文；六处选择使用白底深字、选中绿底白字。实际图与后续 UI 流程复核。</td><td><code>c5c2f43</code><br><code>001c161</code></td></tr>
<tr><td>Vision 两个登录选项都被读为「登录方式」</td><td>每个按钮保留独立无障碍名称；退出后真实具名密码登录流程通过。</td><td><code>39ea345</code></td></tr>
</tbody></table></div><p class="sub">QA 的键盘完整值等待、真实窗口滚动、实际 iPad 旋转和 Watch 配对等待，是测试工具修正；与上面的产品功能修复分别记录。</p></section>

<section id="screens"><h2>真实画面与验收范围</h2><p>下列图片来自本轮运行原件，使用隔离的合成测试家庭；不同操作阶段的余额随实际测试操作变化。图片证明本次界面与流程。</p><div class="gallery">__PHOTOS__</div>
<div class="table-scroll"><table data-no-sort data-no-ui><thead><tr><th>平台</th><th>实际验收</th><th>环境与限制</th></tr></thead><tbody>
<tr><td><span class="status">iPad · 通过</span></td><td>新项目／奖励保存、服务器读回、存储会话重开、退出与密码登录；真横屏、最大辅助字号。</td><td>iPadOS 27 模拟器。</td></tr>
<tr><td><span class="status">Mac · 通过</span></td><td>五页面、760×540 最小窗、Cmd-W 菜单映射及实际窗口关闭；包内真实 CLI。</td><td>本机离屏原生窗；没有把全局前台按键操作冒充该测试。</td></tr>
<tr><td><span class="status">Watch · 通过</span></td><td>真正配对／连接；手机登录后 WC 接收摘要；手机退出后手表显示登录提示。</td><td>watchOS 27 配对模拟器；未给 Watch 注入账号凭据或 context。</td></tr>
<tr><td><span class="status">Vision · 通过</span></td><td>原生键盘、新建保存、重开会话、实际窗口滚动、退出及密码登录。</td><td>visionOS 27 模拟器，普通窗口；截图为窗口区域。</td></tr>
</tbody></table></div><p class="sub">四端构建与当前 Chapter 启动全部通过。共享 API 功能／恢复／隐私通过；生产存储检查为四个独立 Mac 进程、11 条断言。未把它扩大为所有设备的全部账号与存储验收。</p></section>

<section id="time"><h2>为什么拖长了</h2><div class="grid two">
<article class="card"><h3>必要投入</h3><p>其他四平台是你明确要求继续完成的工作。真实测试发现了 iPad 编辑页缺失、Vision 可读性和登录选项命名问题，这些需要修产品并复验。Watch 的真正 WC 联动也需要实际手机登录／退出验证。</p></article>
<article class="card"><h3>我的收尾判断有问题</h3><p>我把完整资源复测、反复绑定新输入、全帧商店素材也挂成了交付前置。负载准入和串行车道造成等待；Vision 独有修改又触发了其他端全输入更新。必要结果已有以后，仍在等额外资源，这是拖长交付的主要决策问题。</p></article>
</div><div class="timeline">
<div class="event"><time>19:22</time><div><strong>TestFlight 10 首次可测试</strong><p>新版五栏目进入 family 组；之后实际发现的新建页修复尚未包含在此构建。</p></div></div>
<div class="event"><time>20:37</time><div><strong>修复 iPad 新建弹窗</strong><p>属于真实产品问题，后续原生保存及服务器读回通过。</p></div></div>
<div class="event"><time>21:34</time><div><strong>真实 Watch 登录／退出联动已完成</strong><p>此前配对数据库同步迟到的失败保留；后续同一对设备复验通过。</p></div></div>
<div class="event"><time>22:02</time><div><strong>修复 Vision 登录选项无障碍名称</strong><p>没有用位置点击掩盖重复名称。</p></div></div>
<div class="event"><time>22:17</time><div><strong>最后一端核心 UI 与 TestFlight 11 已完成</strong><p>Vision 退出／密码登录完整通过，修复进入 build 11。此后以当前启动和共享最终记录收尾即可。</p></div></div>
<div class="event"><time>22:34</time><div><strong>当前四端 Chapter 启动全部完成</strong><p>共享最终功能／恢复／隐私以及输入冻结测试也已有通过记录。</p></div></div>
<div class="event"><time>22:45</time><div><strong>必要功能交付结案</strong><p>报告、README 和真实截图提交 50fb685；停止本人隔离服务，保留原后台采样自然结束。</p></div></div>
<div class="event"><time>22:53</time><div><strong>额外 Vision 资源后台自然完成</strong><p>从已有原件读取本页最新数字，没有重新启动平台验收。</p></div></div>
</div><p class="sub">时间来自提交、交接与原作业记录。没有完整逐分钟活动账，无法把这些时间差精确拆成「浪费了多少分钟」，也不把等待时间算成 App 启动耗时。</p>
<details class="evidence"><summary>查看额外资源最终数字</summary><p class="sub">绑定生产输入 c8c72e0b…；本地 Release 1.0.2（9）。内存为 App 宿主 phys_footprint；闲置 CPU 为 60 秒窗口；冷启为五次中位，不是 TF 包或真机数字。</p><div class="table-scroll"><table data-no-sort data-no-ui><thead><tr><th>平台／环境</th><th>内存</th><th>闲置 CPU</th><th>冷启中位</th><th>zip / 安装</th></tr></thead><tbody>__METRICS__</tbody></table></div></details>
</section>

<section id="evidence"><h2>仍未完成的，明确写在这里</h2><div class="grid two">
<article class="card"><h3>网站本地修复已完成，线上待同步</h3><p>本地三页已统一原生的 <code>#F8F7F2</code> 暖白与 <code>#257F70</code> 绿色、圆角卡片、账本／走势／加分／兑换／账户五栏。手机账本改为记录卡片，加减分分段，积分入口的登录页显示 Growth Treasury／成长小金库。</p><p>Chrome 实测加分 +10、扣分 −2、兑换 −200，余额从 1,133 到 941，真实服务端记录回读一致；390px 下三页无横向溢出。<a href="http://127.0.0.1:53137/points.html#earn">打开本机隔离预览</a>。这是测试账本，本轮没有部署线上；完整网页项目管理及生产短信投递不由这次主题修复冒充完成。</p><p class="sub">平台输入依赖范围仍需与正在维护 Chapter 的另一个会话对齐；本轮保留原登记和旧原件，不改共享实现、不伪造新摘要。</p></article>
<article class="card"><h3 class="pending-text">账号与发行的剩余项</h3><ul class="list"><li>短信云端配置与真实投递尚未完成；手机身份业务测试使用 PNVS 替身。</li><li>所有原生账号变更表单的完整邮件／短信端到端覆盖尚未全部验完。</li><li>iPhone 实装版本及物理设备运行资源没有核验。</li><li>Mac／Vision 的商店上架，以及官网和产品卡的全面视觉与素材同步未完成。</li></ul></article>
</div><div class="callout"><strong>可测试、必要平台功能通过，有明确范围。</strong><p>这不等于整套 PRD、全部账号闭环、网站体验及全发布 SOP 已完成。此前汇报把这些范围说得不够清楚，本页按真实证据标记。</p></div>
<h3>展开原件，直接核对</h3><p class="sub">以下 JSON 已嵌在文件里；页面与图片可离线查看，不需要登录、CDN 或外部脚本。原文件路径和 SHA256 一并保留。</p>__PROOFS__
</section><p class="sub">生产核心提交：f8aea7e；最终修复：39ea345；功能交付记录：50fb685。本页是会话事实快照，不是产品网站。</p>
__FOOTER__</main></body></html>
'''

photos = [
    ('perf/platform-validation/ipad/captures/tab-0.png', 'iPad · 当前账本', '暖白、大留白、绿色强调、五栏目；模拟器真实画面。'),
    ('perf/platform-validation/ipad/captures/landscape-score.png', 'iPad · 真横屏加分', '原 LaneRotator 旋转后 2752×2064；未把仅请求旋转的图片算作横屏。'),
    ('perf/platform-validation/mac/captures/minimum-score.png', 'Mac · 最小窗口', '760×540 原生窗口；未激活的真实截图。'),
    ('perf/platform-validation/watch/watch-signed-in.png', 'Watch · 实际 WC 收到摘要', '配对手机登录后显示 1,133；没有注入手表会话。'),
    ('perf/platform-validation/vision/ui-captures/ledger.png', 'Vision · 原生 UI 流程', '真实 UI 测试中的窗口区域截图，不冒充全帧商店图。'),
]
records = [
    ('perf/asc-release.json', 'TestFlight 11 与商店实际状态'),
    ('perf/platform-validation/current-launches.json', '四端当前构建的真实启动'),
    ('perf/platform-validation/ipad/proof.json', 'iPad 原生 UI'),
    ('perf/platform-validation/mac/hosted-proof.json', 'Mac 真实原生窗和菜单'),
    ('perf/platform-validation/mac/current-bundled-cli.json', 'Mac 当前包内 CLI'),
    ('perf/platform-validation/watch/proof.json', 'Watch 真正配对 WC 联动'),
    ('perf/platform-validation/vision/proof.json', 'Vision 当前原生 UI'),
    ('perf/platform-validation/vision/accessibility-fix.json', 'Vision 独有修复及其他端原证据适用范围'),
    ('perf/platform-validation/current-shared-acceptance.json', '共享功能、恢复、隐私'),
    ('perf/platform-validation/current-test.json', '注册测试与输入稳定检查'),
    ('perf/platform-validation/storage/proof.json', '生产存储跨进程保存、恢复与清理'),
    ('docs/reports/points-fixes-20261004.validation.json', '本次脚本与网页修复的独立验证'),
]
body = body.replace('__PHOTOS__', ''.join(photo(*p) for p in photos))
body = body.replace('__METRICS__', ''.join(metrics))
body = body.replace('__PROOFS__', ''.join(proof(*p) for p in records))
body = body.replace('__FOOTER__', shared_footer(session_uuid=SESSION, generated=GENERATED,
    script_name='scripts/reports/session_20261004.py', cwd=str(ROOT),
    rerun_cmd='python3 scripts/reports/session_20261004.py'))
head = shared_head(title='Points · 这一轮做了什么', session_uuid=SESSION,
                   generated=GENERATED, cwd=str(ROOT), extra_css=CSS)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(head + body, encoding='utf-8')
print(json.dumps({'html': str(OUT), 'bytes': OUT.stat().st_size,
                  'photos': len(photos), 'evidence_records': len(records)}, ensure_ascii=False))
