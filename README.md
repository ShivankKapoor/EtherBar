# EtherBar

A lightweight macOS menu bar app that monitors your Ethernet connection and network traffic in real time.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.0-orange)

## Features

- **Ethernet status** — menu bar icon dims when no Ethernet is detected
- **Live traffic rates** — per-interface Mbps displayed as animated bars for Ethernet and Wi-Fi
- **Traffic split** — shows the percentage of traffic across both interfaces when both are active
- **Wi-Fi toggle** — enable or disable Wi-Fi directly from the menu bar
- **Zero Dock presence** — lives entirely in the menu bar, no Dock icon

## Screenshot

> *(Add a screenshot here)*

## Installation

### Download (easiest)

1. Download the latest `EtherBar.app` from the [Releases](../../releases) page
2. Drag `EtherBar.app` into your `/Applications` folder
3. Double-click to open

> **First launch:** macOS may show a security warning because the app is not from the App Store.
> Right-click `EtherBar.app` → **Open** → **Open** to dismiss it once. It will open normally from then on.
>
> Alternatively, run in Terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/EtherBar.app
> ```

### Build from source

Requirements: Xcode 16+, macOS 13+

```bash
git clone https://github.com/yourname/EtherBar.git
cd EtherBar
open EtherBar.xcodeproj
```

Then in Xcode: **Product → Run** (⌘R) or **Product → Archive** for a release build.

## Usage

| Element | Description |
|---|---|
| Menu bar icon | Bright = Ethernet connected, Dimmed = no Ethernet |
| Ethernet row | Live download+upload rate on the wired interface |
| Wi-Fi row | Live download+upload rate on the wireless interface |
| Split bar | Traffic share between Ethernet and Wi-Fi |
| Wi-Fi toggle | Turn Wi-Fi on or off |

## Permissions

EtherBar requires no special permissions beyond network access. It uses:

- `networksetup` — to detect interface names and toggle Wi-Fi
- `/dev/bpf*` or `/proc/net` equivalents — traffic sampling via system APIs

No data ever leaves your machine.

## Credits

- <a href="https://www.flaticon.com/free-icons/ethernet" title="ethernet icons">Ethernet icons created by Freepik - Flaticon</a>

## License

[MIT](LICENSE)
