# Ledger

An offline spending tracker for Android. You log expenses and subscriptions on the phone, scan
receipts with the camera, and get a short weekly analysis of where the money went.

The whole app is one HTML file (`www/index.html`) packaged as a native Android app with
[Capacitor](https://capacitorjs.com/). Data stays on the device. The app only goes online when you
scan a receipt or run the weekly analysis, and those calls go to the Anthropic API.

## Features

- Add expenses and recurring subscriptions, sorted by category
- **Scan receipt**: take a photo and Claude reads the total and line items
- **Analyze this week**: a short summary of your spending against your budget
- Daily reminder as a real Android notification, even when the app is closed
- Export and import your data as JSON

## API key

Receipt scanning and the weekly analysis need your own Anthropic API key. You paste it in the
app's settings and it is stored only in the app's local storage on your phone. No key is included
in this repository.

## Build the APK

```bash
./build-apk.sh
```

The script downloads Node, a JDK and the Android SDK into `.toolchain/` inside the project (no
Homebrew, no `sudo`), then builds `Ledger.apk`. The first run takes 10–20 minutes, mostly
downloads. `rm -rf .toolchain` removes everything it installed.

## Install on a phone

Over USB, with USB debugging enabled:

```bash
.toolchain/android-sdk/platform-tools/adb install -r Ledger.apk
```

Or copy `Ledger.apk` to the phone and open it. Android will ask you to allow installing apps
from that source.

## Project layout

| Path | What |
|---|---|
| `www/` | The app: `index.html`, manifest and icons |
| `android/` | Capacitor's Android project |
| `capacitor.config.json` | App id, name and plugin settings |
| `build-apk.sh` | One-command build |
