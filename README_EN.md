[中文](README.md) | **English**

<p align="center"><img src="Resources/icon-1024.png" width="96" alt="Growth Treasury"></p>

# Growth Treasury · 成长小金库



**Every point your child earns grows into a home they can see.**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018%2B%20·%20iPadOS%20·%20macOS%2015%2B%20·%20watchOS%2011%2B%20·%20visionOS%2026%2B-000?logo=apple) [![App Store](https://img.shields.io/badge/App%20Store-available-0D84FF?logo=apple)](https://apps.apple.com/app/id6806799638) ![License](https://img.shields.io/badge/License-MIT-green)

Made for children: 11 value tiers map to illustrations across 5 eras, making their “home” visible. The entire page palette is sampled from the illustration. The parent password is never written to disk: a points system that lets children award themselves points becomes a point-farming game by the next day. Moving up a tier is celebrated, never punished; moving down is silent.

<table><tr>
<td align="center" width="25%"><img src="docs/screenshots/01-sim-064957.png" alt="Opening screen: every earned point is in this ledger; the page palette follows the current home"><br><sub>Opening screen: every earned point is in this ledger; the page palette follows the current home</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/02-tab1.png" alt="Trends: point value follows a stock-like chart, with highs, lows, and how many more points practice can earn today"><br><sub>Trends: point value follows a stock-like chart, with highs, lows, and how many more points practice can earn today</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/03-tab2.png" alt="Redeem: ice cream, 30 extra minutes of play, or a wish fulfilled; spend earned points with no overdraft"><br><sub>Redeem: ice cream, 30 extra minutes of play, or a wish fulfilled; spend earned points with no overdraft</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/04-parent.png" alt="Parent entry: choose a rule, review the preview, enter the password; undoing the latest entry deletes it as though it never appeared on the chart"><br><sub>Parent entry: choose a rule, review the preview, enter the password; undoing the latest entry deletes it as though it never appeared on the chart</sub></td>
</tr></table>

<details><summary>More screenshots</summary><table><tr>
<td align="center" width="25%"><img src="docs/screenshots/05-palette.png" alt="Illustrations across five eras and the page palettes sampled from them"><br><sub>Illustrations across five eras and the page palettes sampled from them</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/06-widget.png" alt="Widget preview rendered inside the app: persistent value display and the remaining points needed for the next tier"><br><sub>Widget preview rendered inside the app: persistent value display and the remaining points needed for the next tier</sub></td>
</tr></table></details>

## What it does

| Feature | Description |
|---|---|
| **Turn effort into a visible home** | 11 value tiers map to illustrations across 5 eras, from a slum to a splendid residence. The page palette is sampled from the current illustration: moving up changes the home and the feel of the entire app. Upgrades are celebrated without punishment; downgrades stay silent. |
| **Read the ledger like a stock dashboard** | Trends, gains and losses, highs and lows make the ledger understandable and appealing to children. Balances use snapshots carried by each transaction rather than client-side addition, so both ends always agree. |
| **The parent password is never saved to disk** | A points system that lets children award themselves points soon becomes a farming game. Parents enter the password each time; it stays only in memory and disappears when the app moves to the background. Even an unlocked phone does not let the child add points. All values are calculated on the server; the client does not perform even a single addition. |

## One app, five platforms

One name, one icon, one ledger: iPhone, iPad, Mac and Apple Vision Pro are the same target, and Apple Watch is a watch app that installs with the iPhone package. The ledger lives on the server, so points booked on one device show up on the others on refresh or when the app returns to the foreground.

| Platform | What it looks like | Can you get it now? |
|---|---|---|
| iPhone | Four paged screens (ledger / trend / redeem / account) plus Lock Screen and Home Screen widgets | On the [App Store](https://apps.apple.com/app/id6806799638) |
| iPad | Wide layout: sidebar + ledger board (era banner, value, points to the next tier ‖ trend, stats, entries), parent booking in a side inspector; narrow Split View falls back to the iPhone layout | Same App Store package, but **this wide layout has not been released yet** (the version on sale shows the stretched iPhone layout on iPad) |
| Mac | Native macOS window with the same sidebar board; the parent lock closes after 10 idle minutes; ships the `treasury` command line inside the app | **Not on the App Store**; local builds only |
| Apple Watch | A glance at the current tier, balance, points to the next tier with progress, and the last 10 entries on the next page; four complications. Read-only: no redeeming or booking; the sign-in is handed over from the iPhone | **Not on the App Store** (the embedded watch app is not in any released build yet) |
| Apple Vision Pro | The same sidebar board in a system glass window; the era colour is an accent only | **Not on the App Store**; verified on the simulator only |

<table><tr>
<td align="center" width="50%"><img src="docs/screenshots/07-ipad.png" alt="iPad landscape: sidebar and ledger board"><br><sub>iPad landscape: sidebar and ledger board (simulator screenshot)</sub></td>
<td align="center" width="50%"><img src="docs/screenshots/08-mac.png" alt="Mac: parent booking in the right inspector, the balance stays visible on the left"><br><sub>Mac: parent booking in the right inspector, the balance stays visible on the left (local screenshot, inactive window)</sub></td>
</tr><tr>
<td align="center" width="50%"><img src="docs/screenshots/10-vision.png" alt="Apple Vision Pro: the ledger board in a glass window"><br><sub>Apple Vision Pro: the ledger board in a glass window (simulator screenshot, cropped)</sub></td>
<td align="center" width="50%"><img src="docs/screenshots/09-watch.png" width="208" alt="Apple Watch: current tier, balance, points to the next tier"><br><sub>Apple Watch: current tier, balance, points to the next tier (simulator screenshot)</sub></td>
</tr></table>

The account “小满” and its 30 days of entries in these screenshots are demo data (an isolated ledger that `scripts/demo/ledger.py` starts locally), not any real family's ledger.

### Resource use per platform (simulators, and natively on a Mac)

<!-- platforms:start -->
| Platform | Measured on | Package (zip) | Idle memory | Idle CPU | Cold launch to first data screen | Host load (1 / 5 / 15 min) | Target |
|---|---|---|---|---|---|---|---|
| iPhone | Simulator · iPhone 17 Pro · iOS 27.0 | 8.4 MB | 43.0 MB | 0% | 1.80 s | 14.2 / 46.4 / 54.6 | ≤ 150 MB · ≤ 0.5% |
| iPad | Simulator · iPad Pro 13-inch · iPadOS 27.0 | 8.4 MB | 39.0 MB | 0% | 0.50 s | 12.8 / 42.2 / 52.3 | ≤ 150 MB · ≤ 0.5% |
| Mac | Native · Mac16,12 / Apple M4 · macOS 27.2 | 4.7 MB | 51.0 MB | 0% | 0.29 s | 13.4 / 31.9 / 39.6 | ≤ 150 MB · ≤ 0.5% |
| Apple Watch | Simulator · Apple Watch Series 12 · watchOS 27.0 | 3.0 MB | 21.0 MB | 0% | 0.46 s | 14.0 / 47.9 / 73.4 | ≤ 25 MB · ≤ 10 MB package · ≤ 1.5 s |
| Apple Vision Pro | Simulator · Apple Vision Pro · visionOS 27.0 | 4.7 MB | 60.0 MB | 0.07% | 2.85 s | 13.1 / 37.9 / 50.2 | ≤ 60 MB |

<sub>**These numbers were measured on a heavily loaded host**: right before each lane's timed launches the 10-core host's load average was 12.8–14.2 (1 min), 31.9–47.9 (5 min) and 39.6–73.4 (15 min) (the "Host load" column), all above its core count; the measurement gate only requires the 1-minute load to be under 1.5× the cores. Cold launch is the number most sensitive to host load, so the launch times here are likely pessimistic (slow) and should come out lower when re-measured on an idle machine. Measured 2026-10-02; data in `perf/platforms/<platform>.json`. iPhone, iPad, Watch and Vision are Release builds on Xcode simulators, the Mac is a native local Release build; **none of these are real-device numbers, and the package sizes are not App Store slices** (the App Store iPhone size is under "Resource usage" below). Memory is the app process's phys_footprint; CPU is CPU time ÷ wall time over 60 s after a 45 s settle; cold launch is the median time from the launch request to the app's "first data-bearing screen" log (isolated local demo ledger, 5 runs, the first run after install discarded). Simulator launch times swing widely with host load: with memory tight on 2026-10-02, the same code on the iPhone lane measured 1.8–4.1 s at different times. Most of a Vision Pro cold launch is the simulator's own overhead (from process spawn to the app's first log line, plus visionOS scene and RealityKit setup), which stretches past ten seconds on a busy host; the app itself takes about 2 s from fetching the ledger to drawing its first screen.</sub>
<!-- platforms:end -->

## Availability

Email registration and separate family ledgers are supported. The iPhone / iPad edition is available on the [App Store](https://apps.apple.com/app/id6806799638); the Mac, Apple Watch and Apple Vision Pro editions are not on the App Store yet. The official build readback on 2026-09-26 identifies version 1.0 (2); see the [release record](perf/asc-release.json). The phone's current installed version and runtime performance still need physical-device verification.

The era illustration backgrounds come from the author’s `~/Apps/edu/web` content library and are synced into the package during builds. The ledger backend is `edu.tianli.cyou`. Without that content library, the build stops at preBuildScripts.

## Command line for agents · `treasury`

The app is for people; the command line is for agents. `cli/treasury` is a thin client of the same server the app and the website use (the `/api/*` endpoints of `edu.tianli.cyou`), written with the Python standard library only. Points, tier unlocks, overdraft rules, the parent password and concurrency locks are all decided on the server; the command line contains no scoring logic.

A locally built Mac edition carries the command inside its `.app` at `Contents/Resources/bin/treasury` (a `project.yml` build phase copies it only in macOS builds, before signing); iPhone/iPad packages and every archive (App Store / TestFlight) leave it out.

```bash
sh cli/install.sh          # Mac edition installed: finds the .app by bundle id and links to the command inside it; otherwise links to cli/treasury in this repo (source edits apply at once)
sh cli/install.sh --check  # verify only; --uninstall removes only this product's link
```

Credentials come only from environment variables or stdin and are never stored or echoed: `EDU_USER` (email or username), `EDU_PASSWORD` (or `--password-stdin`); parent actions need `EDU_PARENT_PW` (or `--parent-stdin`), sent per call like the app's parent lock; `EDU_API_BASE` defaults to `https://edu.tianli.cyou`.

```bash
treasury version --json                        # no sign-in: CLI version, the containing app's version, server reachable or not
treasury state --json                          # balance, current house tier, points to the next tier, TV time, wishes, today's practice allowance
treasury entries --limit 10 --json             # ledger entries, newest first (the server returns the latest 400)
treasury preview tr-show --json                # computed by the server, nothing recorded
printf '%s\n' "$PARENT" | treasury earn tr-show --parent-stdin --json
treasury spend sh-icecream --dry-run --json    # check before redeeming
treasury config put shop --file shop.json --parent-stdin < parent.txt
```

Every read command supports `--json` and prints `{"ok": true, …}`; failures print `{"ok": false, "err": …}` and exit non-zero (1 = refused by the server or network failure, 2 = usage error or missing credentials). Read commands never change state; write commands go through the server's existing validation, locks and idempotency. Earn/adjust/undo/spend accept `--dry-run`; deleting a user or the account requires `--yes`.

| In the app | Command |
|---|---|
| Ledger home | `treasury state` |
| Entries / trend | `treasury entries [--since DATE] [--cur pts\|tv\|wish]` / `treasury trend --span 14\|30\|100` |
| Shop / redeem | `treasury shop` / `treasury spend <item>` |
| Tier ladder | `treasury tiers` |
| Parent: rules, preview, record, undo, adjust | `treasury rules` / `preview` / `earn` / `undo` / `adjust` |
| Manage rules / shop / tiers | `treasury config get` / `treasury config put rules\|shop\|tiers --file items.json` |
| Profile, account password, parent password, account deletion | `treasury profile` / `me` / `account passwd\|parent-password\|delete --yes` |
| Family user admin | `treasury users list\|reset-password\|delete --yes` |

Admin scope is whatever the server says: `config get`, `config put` and `users list` report the `scope` field of the response (`site` = the whole site, `account` = this account only). When the server returns no `scope`, they report `unknown`: `users list` shows only the caller's own row, and `config put`, `users reset-password` and `users delete` refuse rather than guess where the write would land.

GUI-only (pure interface): the parent-lock countdown, live refresh pushes, home/lock-screen widgets, the tier-up celebration, and the palette and widget previews.

Regression: `python3 Tests/cli_treasury_test.py` first checks the packaging rule and `install.sh` (a fake .app in a temporary Applications folder), then starts an isolated local server (temporary directory, free port) and never touches live accounts; it needs `edu/web/points/server.py` from the same workspace, or `EDU_SERVER_PY` pointing to it.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme PointsDeck -destination 'generic/platform=iOS Simulator' build        # iPhone / iPad (with the embedded watch app)
xcodebuild -scheme PointsDeck -destination 'platform=macOS' build                        # Mac
xcodebuild -scheme PointsDeck -destination 'generic/platform=visionOS Simulator' build   # Apple Vision Pro
xcodebuild -scheme PointsDeckWatch -destination 'generic/platform=watchOS Simulator' build  # Apple Watch on its own
```

- The repository’s `*.sh` files are shims for the author’s local fleet scripts (three-platform builds / device installation / TestFlight). They depend on shared tools under `~/Dev` that are not in this repository and explicitly exit when those tools are unavailable.
- `Shared/PlatformCompat.swift` is a byte-for-byte copy of a shared file, providing same-name stand-ins on macOS / visionOS / watchOS for iOS-only SwiftUI modifiers. Do not edit it here.
- `bash Tests/check-platform-typecheck.sh`: a cheap compile lane for the watch and Vision targets (`swiftc -typecheck` over each target's source list in `project.yml`, no simulator).
- The preBuildScripts in `project.yml` run `sync-skins.sh` to sync content from the author’s machine into the package. The build stops at this step if that content is missing.

See [DEVELOPING.md](DEVELOPING.md) for development details, including regressions, verification channels, and constraints.

## Related

- Product page: <https://apps.tianli.cyou/p/points-deck-ios.html>
- Fleet overview (where the 10 apps came from): <https://apps.tianli.cyou/ios.html>
- Tutorial: [From Zero to TestFlight: The Complete Path to Building an iPhone App Solo](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 Tianli Zeng (曾田力)

<!-- lightweight:start -->
## Resource use

Download size is App Store data; memory, CPU and launch time are iOS Simulator measurements, not physical-device figures.

| Download | Idle memory | Idle CPU | Simulator cold launch to first data-bearing screen |
|---|---|---|---|
| **3.1 MB** (installed 4.0 MB) | **45.1 MB** | **0%** | **1.8 s** |

Sizes are read back for this exact distribution build. The physical device is not yet measured, so memory, CPU and launch time come from the iOS Simulator and are labelled as such.

<sub>v1.0.1 (8) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · TestFlight 1.0.1 (8) (App Store still sells 1.0 (2)); package sizes exclude user data and caches · measured 2026-09-30. Sizes come from Apple App Store Connect device slices for this build. Memory, CPU and launch time were measured on iPhone 17 Pro (iPhone-17-Pro) / iOS 27.0 Simulator with a local Release build v1.0.1 (1) (2026-10-02), App process only; these are not physical-device figures, which are still unmeasured. Memory uses phys_footprint; CPU is CPU time ÷ wall time over a 60-second sampling window; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->


## Configuration and app updates

New builds include a “Configuration and Updates” button below the main interface. The installed version and build come from the app bundle.

This app has no independent portable preference settings. Credentials, permissions, device identifiers and user content continue to use their existing entry points.

The iPhone and iPad update check reads the App Store release and opens this app's system store page. Network failures remain visible. App-version checking is separate from refreshing study materials or backend data.

A source version bump does not mean a new phone build has already been distributed; release and installation records identify the available build.
