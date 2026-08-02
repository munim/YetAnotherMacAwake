# Yet Another Mac Awake

<p align="center"><img src="assets/logo.png" alt="Yet Another Mac Awake logo" width="180"/></p>

<p align="center">
  <b>A macOS menu bar app that keeps your screen awake — and keeps you Available in Teams, Slack, Discord, and Zoom.</b><br>
  <br>
  Three modes, per-day schedules, a silent presence pulse, and a two-axis sleep model.<br>
  Native Swift, no third-party dependencies, open source.
</p>

<p align="center">
  <a href="https://github.com/munim/YetAnotherMacAwake/releases/latest">Download</a> · <a href="https://github.com/munim/YetAnotherMacAwake/issues">Report an issue</a>
</p>

<!-- <p align="center"><img src="assets/preview.png" alt="menu bar + settings preview" width="700"/></p> -->

---

### Why Yet Another Mac Awake?

- **Screen awake *and* presence green** — most keep-awake tools only stop the display sleeping. This also sends an invisible pulse of activity so your messaging apps don't flip you to Away during a long coding-agent run, a meeting that isn't yours, or a coffee break.
- **Three modes from the menu** — Always On, Off, or Follow Schedule. No settings dive for everyday use.
- **Per-day schedule windows** — Monday through Sunday, including overnight windows like 22:00–02:00.
- **Two-axis sleep model** — "Screen Stays On" holds the display + system assertions; "Screen Can Sleep" keeps only the system one (like `caffeinate -s`), so the Mac stays up with the lid closed on AC while the display is free to sleep.
- **Silent, Aerospace-safe pulse** — taps F20 by default (no default macOS action, not bound by Aerospace), with a 1px mouse-jiggle fallback when Accessibility isn't granted.
- **Lightweight & native** — lives in your menu bar, no Dock icon. Built with Swift and SwiftUI, not a web view in disguise.

---

## Install

**From a release:**

Download the latest universal `.dmg` (or `.zip`) from [Releases](https://github.com/munim/YetAnotherMacAwake/releases), open it, drag **YetAnotherMacAwake.app** to `/Applications`. SHA-256 checksums are published alongside each asset.

**Build from source** (needs Xcode or the Swift Command Line Tools):

```bash
git clone https://github.com/munim/YetAnotherMacAwake.git
cd YetAnotherMacAwake
./build.sh && open YetAnotherMacAwake.app
```

---

## Quick Start

1. Launch it — a flame icon appears in your menu bar.
2. Click it and pick a mode: **Always On**, **Off**, or **Follow Schedule**.
3. Open **Settings → Schedule** to set your daily windows (and toggle which days are enabled).
4. On the first silent-key pulse, grant **Accessibility** in System Settings — or let it fall back to a subtle mouse jiggle.

---

<details>
<summary><b>All Features</b></summary>

### Modes & schedule
- **Always On** — holds the sleep assertions indefinitely.
- **Off** — releases them; the Mac sleeps normally.
- **Follow Schedule** — awake on/off per the windows you set for each day.
- **Per-day windows** — enable days individually, set a start/end per day; overnight windows wrap past midnight.
- **Live status** — the menu shows the current state and the next boundary (e.g. "Awake: On · until 18:00").

### Presence pulse
- **Silent key by default** — F20 has no default action on macOS and isn't bound by Aerospace. A picker offers F13–F20 or mouse-only.
- **Mouse-jiggle fallback** — a 1px move out and back from the real cursor position, used when Accessibility isn't granted or the key is set to "Mouse only".
- **App gating** — choose Teams, Slack, Discord, Zoom. The pulse fires only while at least one selected app is running. Default is all four; uncheck every app to pause the pulse entirely.
- **Pulse method** — Auto (silent key when allowed, else jiggle) or Always mouse jiggle.
- **Pulse interval** — 30–600 seconds, default 120 s.

### Sleep model
- **Screen Stays On** — display + system sleep assertions (like `caffeinate -d`).
- **Screen Can Sleep** — system assertion only (like `caffeinate -s`); survives a closed lid on AC power while the display can sleep.
- **AC-only rule** — keep awake only when plugged in; on battery the assertions drop.
- **Pulse while screen can sleep** — off by default (any fake activity keeps the display awake); opt in to trade display sleep for presence availability.

### Menu
- **Mode cards** — Always On / Off / Follow Schedule.
- **Screen On / Screen Can Sleep** radios.
- **Disable for…** — timed pause of 1 / 5 / 10 / 15 / 30 / 60 minutes with a live countdown; ephemeral, clears on relaunch.
- **Resume now** — end a pause early.
- **Settings… / Quit**.

### Settings
- **Schedule** tab — per-day enable + time windows.
- **Behavior** tab — AC-only, pulse apps, method, interval, key, launch at login, screen-sleep mode.
- **Permissions** tab — Accessibility status and grant flow.
- **About** tab — version and author.

</details>

---

<details>
<summary><b>For tinkerers — build, test, CLI</b></summary>

```bash
swift build                                       # dev build
./.build/debug/YetAnotherMacAwake --selftest      # schedule + pulse logic; exit 0 = pass
./.build/debug/YetAnotherMacAwake --force-on      # activate without the UI
./.build/debug/YetAnotherMacAwake --pulse-now     # fire one pulse, print idle before/after
```

The codebase is small and lives in `Sources/YetAnotherMacAwake/`. `AGENTS.md` at the repo root documents the architecture and the domain gotchas worth knowing before you change anything.

</details>

---

## Permissions

The silent-key method needs **Accessibility** access (System Settings → Privacy & Security → Accessibility). Without it, the app falls back to a subtle mouse jiggle, so it still works.

One caveat when building from source: ad-hoc signing changes on every rebuild, so macOS may ask you to re-grant Accessibility after each `./build.sh`.

---

## Contributing

Issues and pull requests are welcome. Starring the repo, reporting bugs, or sending a PR is more than enough. 🙏

---

## Requirements

macOS 14 (Sonoma) or later.

## Limitations

- Closing the lid or sleeping the Mac manually always wins. That's by design, not a bug.
- On battery power the screen-can-sleep assertion is ignored, and some Macs still sleep with the lid closed unless an external display is attached.

## License

[MIT](LICENSE)

