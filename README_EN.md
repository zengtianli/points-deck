[中文](README.md) | **English**

<p align="center"><img src="Resources/icon-1024.png" width="96" alt="Growth Treasury"></p>

# Growth Treasury · points-deck



**Every point your child earns grows into a home they can see.**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

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

## Availability

Email registration and separate family ledgers are supported. The iOS edition is preparing for App Store release and is not yet publicly downloadable.

The era illustration backgrounds come from the author’s `~/Edu` content library and are synced into the package during builds. The ledger backend is `edu.tianli.cyou`. Without that content library, the build stops at preBuildScripts.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme PointsDeck -destination 'generic/platform=iOS Simulator' build
```

- The repository’s `*.sh` files are shims for the author’s local fleet scripts (three-platform builds / device installation / TestFlight). They depend on shared tools under `~/Dev` that are not in this repository and explicitly exit when those tools are unavailable.
- `Shared/PlatformCompat.swift` is a byte-for-byte copy of a shared file, providing same-name no-ops on macOS for iOS-only SwiftUI modifiers. Do not edit it here.
- The preBuildScripts in `project.yml` run `sync-skins.sh` to sync content from the author’s machine into the package. The build stops at this step if that content is missing.

See [DEVELOPING.md](DEVELOPING.md) for development details, including regressions, verification channels, and constraints.

## Related

- Product page: <https://apps.tianli.cyou/p/points-deck-ios.html>
- Fleet overview (where the 10 apps came from): <https://apps.tianli.cyou/ios.html>
- Tutorial: [From Zero to TestFlight: The Complete Path to Building an iPhone App Solo](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 Tianli Zeng (曾田力)
