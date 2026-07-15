# Usage HUD

A private macOS heads-up display for Codex and Claude subscription limits. It floats above normal windows and full-screen apps, refreshes automatically, and lives in the menu bar when hidden.

![Usage HUD showing Codex and Claude usage](artifacts/usage-hud-no-shadow-preview.png)

## What it reads

- **Codex:** the installed `codex app-server` interface and its `account/rateLimits/read` request.
- **Claude:** the existing Claude Code login in macOS Keychain and Claude's account usage endpoint.

Credentials never leave your Mac except in the provider's own authenticated request. Usage HUD does not store or log tokens.

Diagnostic logs are stored locally at `~/Library/Application Support/Usage HUD/usage-hud.log`. Choose **Open Logs…** from the menu-bar gauge to inspect refreshes, HTTP status codes, `Retry-After` values, and backoff decisions. Logs rotate at 1 MB and never include credentials or response bodies.

Codex and Claude use independent timers and refresh every two minutes. Each provider schedules independently, so one cannot delay the other. If Claude returns a rate limit, Usage HUD logs the raw `Retry-After` value, replaces its normal timer with a one-shot retry for that delay, and leaves Codex's timer untouched. During the cooldown, the HUD keeps the last successful Claude reading visible with a **STALE** marker. If no usable `Retry-After` value is supplied—including a zero-second value that would cause a rapid retry loop—Usage HUD uses a conservative fallback backoff.

## Install

Download the macOS zip from the [latest release](https://github.com/SmoothLayers/usagehud/releases/latest), unzip it, and open **Usage HUD.app**. This personal build is ad-hoc signed but not Apple-notarized, so macOS may ask you to control-click the app and choose **Open** on first launch.

## Build and run

Both `codex` and `claude` should already be signed in.

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Usage HUD.app"
```

The first Claude refresh may trigger a macOS Keychain permission prompt. Choose **Always Allow** so the HUD can refresh in the background.

Drag the HUD from any empty area. Usage HUD remembers its position and restores it the next time it opens; if a display is disconnected, the window is moved onto a visible screen. Use the top-right controls to refresh, switch to compact mode, or hide it. Compact mode shows Codex and Claude as two floating meter strips; toggle **Compact Mode** from the gauge menu to expand again. Clicking a strip does not hide or resize the HUD. If the window is ever off-screen, **Show Usage HUD** repairs its size and moves it back onto a visible display. Once hidden, use the gauge icon in the menu bar to show it again. The menu also contains **Launch at Login**.

## Troubleshooting

- **CLI not found:** make sure `codex` and `claude` are installed. NVM installations are detected automatically.
- **`env: node: No such file or directory`:** rebuild the app with the latest source. Usage HUD now carries the detected NVM binary directory into Codex's environment when launched from Finder.
- **Sign in message:** run `codex login` or `claude auth login`, then choose **Refresh Now** in the menu bar.
- **Claude login expired:** open Claude Code once and complete its login flow.
- **Unexpected refresh behavior:** choose **Open Logs…** from the gauge menu and inspect the latest Claude or Codex entries.

This app targets macOS 14 or newer and stays local; it does not require a server or separate API keys.
