# DeepSeek Monitor

A native macOS menu bar app for real-time DeepSeek API usage and billing monitoring.

<p align="center">
  <img src="Sources/DeepSeekMonitor/Resources/screenshot-panel.png" width="360" alt="Dashboard" />
  <br />
  <em>Dashboard: balance, model usage, and 7-day trend chart</em>
</p>

## Features

- **Balance Monitoring** — real-time account balance display (total balance, current month spend)
- **Token Usage** — per-model token consumption and cost tracking (V4 Flash / V4 Pro)
- **Usage Trends** — 7-day token consumption bar chart with daily breakdown
- **CSV Import** — manual and automatic import from DeepSeek usage exports (.csv / .zip)
- **Auto Export** — automated DeepSeek platform login via WKWebView with one-click usage export
- **Local Caching** — instant data display on app restart, no blank screens

<p align="center">
  <img src="Sources/DeepSeekMonitor/Resources/screenshot-settings.png" width="420" alt="Settings" />
  <br />
  <em>Settings: API key, refresh interval, usage import, and cache management</em>
</p>

## Installation

### Download

Download the latest DMG from [GitHub Releases](https://github.com/JayHome137/DeepSeekMonitor/releases) and drag the app into Applications.

### Build from Source

```bash
git clone https://github.com/JayHome137/DeepSeekMonitor.git
cd DeepSeekMonitor

# Generate app icon
./build.sh icon-png

# Build and launch
./build.sh restart

# Package as DMG
./build.sh dmg
```

## Usage

1. Click the menu bar icon → right-click **Settings** (设置)
2. Enter your [DeepSeek API Key](https://platform.deepseek.com/api_keys)
3. Click **Verify & Save** (验证并保存)
4. The dashboard automatically displays your balance and usage data

If the usage API endpoint is unavailable, import data manually via Settings → Usage Import — export a CSV from the [DeepSeek Usage page](https://platform.deepseek.com/usage) and import it directly.

## Tech Stack

| Layer | Technologies |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI + AppKit (NSStatusBar, NSWindow/NSPanel) |
| Networking | URLSession — DeepSeek API |
| Automation | WKWebView + JavaScript injection |
| State | Combine / ObservableObject / @Published |
| Storage | UserDefaults (LocalCache + API Key fallback) |
| File Monitoring | DispatchSourceFileSystemObject |
| Build | Swift Package Manager + Shell scripts |

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel (Universal Binary)
- A [DeepSeek API Key](https://platform.deepseek.com/api_keys)

## License

MIT
