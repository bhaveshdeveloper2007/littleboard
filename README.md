<div align="center">

# Littleboard

**A native macOS desktop widget app — 50+ widgets that live on your desktop.**

Built in pure Swift/SwiftUI. No Electron, no web views for the chrome — real AppKit windows floating above your wallpaper.

</div>

Littleboard puts a library of desktop widgets on your Mac: clocks (analog, digital, minimal, world), live weather with day/night scenes, calendar with your real events, battery stats straight from IOKit, system activity with per-program CPU, network throughput, disk usage with eject, a full music player (any app — Music, Spotify, browsers), app launcher, toolbox with real system toggles, app time tracking, GitHub dashboard, and more.

Everything is tracked and rendered **locally**. The only network calls are the public data feeds you enable (weather, stocks, crypto, currencies, GitHub) — no accounts, no telemetry, no keys needed except an optional GitHub token stored in your Keychain.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ with the macOS SDK (for the Swift compiler — `xcode-select --install` is not enough)

## Build and run

```sh
git clone https://github.com/bhaveshdeveloper2007/littleboard.git
cd littleboard
./scripts/build-and-run.sh
```

That single script compiles the app in release mode, packages `build/Littleboard.app`, and opens it. Manual steps:

```sh
swift build -c release
./scripts/package-app.sh   # assembles build/Littleboard.app
open build/Littleboard.app
```

> **Unsigned app note:** the bundle is ad-hoc signed, not notarized. If macOS warns on first open, right-click the app → **Open**, or allow it in System Settings → Privacy & Security. Everything runs locally either way.

## The widget library

| Widget | What it does |
| --- | --- |
| Clock / Simple Clock / Flip Clock / Word Clock | Analog, digital, minimal and world styles at every size; themes, timezones, seconds |
| Weather | Live Open-Meteo conditions, hourly + 7-day forecast, day/night auto scenes, air quality |
| Calendar | Real EventKit events — agenda, month grid with event dots, per-calendar colors, click actions |
| World Clock | Your city list, day/night indicators, local-time offsets, mini analog faces |
| Reminders | Local checklist |
| Battery | IOKit stats — watts, health, cycles, temperature; Ring style; Bluetooth devices with connect/disconnect |
| Temperature | Battery sensor + thermal state (macOS gates the chip sensor for unsigned apps — reported honestly) |
| Network | Live download/upload from kernel counters, interface picker, MB/s or Mbit/s |
| Disks | Every mounted volume, free-space ring, eject on hover, red-pulse when nearly full |
| Activity | CPU chart, memory breakdown (App/Wired/Compressed), busiest programs |
| App Time | Hourly usage chart by category, per-app totals with real icons |
| Music | Now playing for **any** app (Music, Spotify, browsers) — artwork, progress, seek, transport |
| Stocks / Crypto / Currencies | Live market feeds, editable symbols |
| GitHub | Review/Issues/PRs/Inbox tiles, contribution heatmap, Actions build state |
| Apps | Your app launcher — Grid/Dock/List/Tiles looks, running indicators |
| Toolbox | Real toggles: stay awake, dark mode, hide icons, hidden files, mute, eject all, display off, screensaver, screenshot |
| Day Progress | Sky-coloured arc that tracks the sun, moon phase, whole-day or custom hours |
| Plus | Sticky notes, quotes, calculator, timers, pomodoro, stopwatch, countdown, world map, moon, starfield, clipboard, password generator, unit converter, web page, and more — 50+ widgets total |

## Universal design

One **Settings & Design** panel styles every widget at once: six glass styles (Frosted, Solid Dark, Solid Light, Clear, Liquid), corner radius, uniform colours, and theme presets with live preview tiles. Each widget also has its own settings — size (1×1 to 3×2 tiles), accent, transparency, placement with anchors, and position lock.

## Privacy

- Widget data, placement, and app-time history stay in `~/Library/Application Support/Littleboard`
- The GitHub token, if you add one, lives in the macOS **Keychain** — never in the board file
- Feeds: weather/air quality (Open-Meteo), markets (Yahoo Finance, CoinGecko), FX (Frankfurter/ECB), GitHub (public API or your token)
- macOS may ask permission for: Calendar (event widgets), Bluetooth (device batteries), Music/Spotify automation (playback controls), location (weather). Everything degrades gracefully if you decline.

## Diagnostics

```sh
build/Littleboard.app/Contents/MacOS/Littleboard --selftest
```

Runs the built-in suite — every feed, decoder, sensor reader and formatter prints PASS/FAIL and the process exits 0 when green.

## License

MIT — see [LICENSE](LICENSE).
