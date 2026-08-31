<div align="center">

# Usage HUD

**A tiny, private macOS heads-up display for your Codex, Claude, and Kimi subscription limits.**

Know how much of your 5-hour and weekly usage windows is left
without leaving your editor or asking the CLI.

[![Latest release](https://img.shields.io/github/v/release/SmoothLayers/usagehud?label=release&color=2EF2A9)](https://github.com/SmoothLayers/usagehud/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/SmoothLayers/usagehud/total?color=3FB6FF)](https://github.com/SmoothLayers/usagehud/releases)
![Platform](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20silicon-FF8A4A)
![Made with Swift](https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-9B6DFF)](LICENSE)

<img src="artifacts/usage-hud-no-shadow-preview.png" alt="Usage HUD showing Codex and Claude remaining usage side by side" width="760">

</div>

## What is this?

If you code with Codex CLI, Claude Code, or Kimi Code on a subscription plan, your usage is
metered in rolling windows: a short 5-hour window plus a weekly one. The only built-in way to
check them is to ask each tool individually. Usage HUD puts all the meters in one small panel:

- Remaining percentage for each provider's current window, with a live countdown to the next reset
- The weekly window right next to it
- An optional menu bar readout like `C72 · A39 · K84`, so you don't even need the panel open
- An optional notch mode, where a tray of provider rings slides out when you point at the notch
- Local notifications when you're running low and when a window resets

Everything runs on your Mac. No server, no account, no analytics, no separate API key. It reuses
the CLI sign-ins you already have.

## What's new in v0.7

- Notch mode. Point at the camera housing and a tray of provider rings slides out from under it.
  See [below](#notch-mode).
- A design pass on the tray: hairline gauge rings with a droplet riding the leading edge of each
  arc, and slimmer detail bars.
- Launch at Login now survives rebuilds and pending approval.

## Install

1. Download the zip from the [latest release](https://github.com/SmoothLayers/usagehud/releases/latest)
2. Unzip and open Usage HUD.app
3. This personal build is ad-hoc signed but not Apple-notarized, so on first launch
   control-click the app and choose Open, or allow it under System Settings → Privacy & Security

A three-step setup assistant checks for the Codex, Claude, and Kimi CLIs, lets you pick providers
and a layout, and optionally enables notifications. Requires macOS 14+ on Apple silicon, with at
least one supported CLI installed and signed in.

> The first Claude refresh may trigger a macOS Keychain prompt. Choose **Always Allow** so the
> HUD can refresh in the background.

## How it works

| Provider | Source |
|----------|--------|
| Codex | Your installed `codex` CLI's `app-server` interface (`account/rateLimits/read`) |
| Claude | Your existing Claude Code sign-in from its scoped Keychain item, legacy Keychain item, or credentials file, sent only to Anthropic's own usage endpoint |
| Kimi | Your existing Kimi Code sign-in from `~/.kimi-code/credentials/kimi-code.json`, refreshed through Kimi's OAuth endpoint and sent only to Kimi's coding usage endpoint |

Kimi starts out hidden for existing installations, so an update doesn't add an error card for
people who don't use it. After signing in with `kimi`, enable Kimi under *Settings → Display*.

**Privacy.** Credentials never leave your Mac except inside each provider's own authenticated
request. Usage HUD does not store or log tokens. Diagnostic logs stay local
(`~/Library/Application Support/Usage HUD/usage-hud.log`, rotated at 1 MB, never containing
credentials or response bodies) and open from *Settings → Maintenance*.

**Polling.** Each provider refreshes on its own schedule (Codex every 2 minutes, Claude and Kimi
every 5 by default), so one provider can never delay another. Hidden providers aren't polled.
If Claude rate-limits the usage endpoint, the HUD honors the `Retry-After` header, falls back to
a conservative backoff otherwise, keeps the last good reading visible with a STALE marker, and
remembers the cooldown across restarts. Ordinary failed readings expire after 30 minutes; a
rate-limited reading can stay visible for up to 24 hours while the required cooldown is active.
When menu bar percentages are on, a trailing `!` marks retained stale Claude data.

**Live Claude Updates.** For fresher Claude data without extra usage-endpoint requests, Settings
offers an opt-in feed. It installs a silent local Claude Code status-line command, accepts only
token-protected loopback requests, and extracts only the `rate_limits` windows. If you already
use `ccstatusline`, Usage HUD chains it and preserves its visible output; other custom status
lines are left alone. Turning the option off restores the original `ccstatusline` entry.

## Everyday use

- Move the HUD by dragging any empty area and resize from any edge. Expanded and compact modes
  each remember their own size and position.
- Compact mode shrinks each provider to a slim strip, stacked vertically or side by side.
- Always on Top keeps the HUD above other windows, including full-screen apps. Turn it off to
  pin the HUD to the desktop behind normal app windows.
- Lock HUD pins it in place; Click Through passes mouse input to whatever is underneath.
- Hide it anytime. The gauge icon in the menu bar brings it back, and repairs the window if it
  ever ends up off-screen.

## Notch mode

Turn on Notch Mode (menu bar menu, or Settings › Display) and the HUD gets a second home. Point
at the camera housing and a tray slides out from under it with a hairline gauge ring per
provider: its mark in the middle, the remaining percentage below, and a bright droplet riding
the leading edge of each arc. Move away and it retracts.

<div align="center">
<img src="artifacts/notch-tray.png" alt="The notch tray expanded, showing Codex, Claude, and Kimi rings with remaining percentages" width="500">
</div>

Hover a ring and the tray morphs in place. The ring slides aside and its session and weekly
meters unfold next to it, each with a live countdown to its reset. Click any ring to bring the
full HUD forward.

<div align="center">
<img src="artifacts/notch-detail.png" alt="The notch tray with the Claude ring hovered, showing session and weekly bars with reset countdowns" width="500">
</div>

- Nothing is drawn while it is retracted, and it ignores the pointer, so the menu bar behaves
  normally
- Macs without a notch get the same tray from a hot zone at the top centre of the screen, marked
  by a hairline of provider colour
- It follows the pointer across displays and re-measures when you rearrange them
- Stale data desaturates its ring and pins an amber bead to the track, so you can spot a stuck
  meter without opening anything
- Reduce Motion swaps the drop animation for a plain cut
- On macOS 26 and later the tray is Liquid Glass; older versions get a flat black panel

## Compact mode

Choose a narrow vertical stack or place enabled providers side by side:

<div align="center">
<p><strong>Vertical</strong></p>
<img src="artifacts/compact-vertical.png" alt="Usage HUD compact mode with Codex and Claude stacked vertically" width="350">

<p><strong>Horizontal</strong></p>
<img src="artifacts/compact-horizontal.png" alt="Usage HUD compact mode with Codex and Claude side by side" width="650">
</div>

## Make it yours

<div align="center">
<img src="artifacts/v030-expanded-custom.png" alt="Usage HUD with customized accent colors, showing reset and refresh countdowns" width="760">
</div>

Settings covers text size, meter thickness, corner radius, opacity, an independent accent color
per provider, reset/refresh countdown toggles, and the menu bar readout. Usage alerts support a
separate warning threshold (off to 30%) for each provider's current and weekly windows, plus
automatic reset detection. Animations are restrained, and the app honors macOS Reduce Motion.

[Sparkle](https://sparkle-project.org) delivers updates: checked daily, verified with a
dedicated Ed25519 signature before extraction, and installed automatically. You can turn that
off, or use Check Now in Settings.

## Build from source

At least one of `codex`, `claude`, or `kimi` should already be signed in.

```sh
./scripts/build-app.sh
open "dist/Usage HUD.app"
```

Run the tests with `swift test`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| CLI not found | Install `codex`, `claude`, or `kimi`. The app finds Homebrew, `~/.local/bin`, NVM, and login-shell `PATH` setups on its own |
| "Sign in" message | Run `codex login`, `claude auth login`, or `kimi`, then Refresh Now from the menu bar |
| Claude login expired | Open Claude Code once and complete its login flow |
| Unexpected refresh behavior | *Settings → Maintenance → Open Logs* shows every refresh, HTTP status, `Retry-After` value, and backoff decision |

## License

[MIT](LICENSE)
