# Tickbyte

<img src="AppStore/Screenshots/Tickbyte-1440x900-v5.png" alt="Tickbyte: live BTC and ETH in the Mac menu bar" width="720" />

A macOS **menu bar** app for live Bitcoin and Ethereum prices. Trades arrive over the Binance WebSocket — no polling, no account, no main window.

The **Glance** (status item) shows both prices. Click it for the **Board**: one focused coin as a large Space Mono price with today’s sparkline, the other as a compact row. Click the compact row to promote it.

## Features

- Live BTC and ETH via Binance `@trade` streams
- Menu-bar glance plus a custom dropdown (not a system menu)
- Focused coin + compact row; tap to switch
- Today’s move as a signed percent and a sparkline on the hero
- No account, ads, or analytics

## Install

- **Mac App Store** — search Tickbyte, or use the listing once 1.1 is live
- **GitHub** — download `Tickbyte.zip` from the [latest release](https://github.com/AttackOnMorty/tickbyte/releases), move the app to Applications. On first launch: **System Settings → Privacy & Security → Open Anyway**

## Requirements

macOS 13 or later. Internet connection for Binance market data.

## Build

Open `Tickbyte.xcodeproj` in Xcode and Run. Logic tests (no live sockets):

```bash
swift test
```
