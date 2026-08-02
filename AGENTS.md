# AGENTS.md

## What this is

YetAnotherMacAwake (display: "Yet Another Mac Awake") — a macOS menu bar app (SwiftUI `MenuBarExtra`, macOS 14+) that keeps the
screen awake and keeps you **Available in your messaging apps** (Teams, Slack, Discord, Zoom) during configurable
per-day windows.

No third-party dependencies. Swift Package Manager executable target. Ad-hoc
signed, distributed as a local `.app` bundle. No Dock icon (`LSUIElement`).

## Session bootstrap (do first)

Load skills before coding:

1. `karpathy-guidelines` — think before coding, simplicity, surgical diffs, verifiable goals
2. `caveman` — terse replies (full default); off only on `stop caveman` / `normal mode`
3. `caveman-commit` — when user asks for commit message or to commit

## Architecture (file map)

```
Package.swift                          # SPM, macOS 14+, no deps
Info.plist                             # LSUIElement=true (menu bar only)
build.sh                               # release build → YetAnotherMacAwake.app + ad-hoc codesign
Sources/YetAnotherMacAwake/
├── YetAnotherMacAwakeApp.swift        # @main, MenuBarExtra menu, AppDelegate, CLI selftest
├── AppState.swift                     # single source of truth: mode/schedule → engine (30 s poll)
├── AwakeEngine.swift                  # IOPM assertions + activity pulse; SettingsKey, PulseMethod, PulseKey, MessagingApp
├── ScheduleStore.swift                # per-day windows, Codable → UserDefaults; Mode, DaySchedule
├── AccessibilityMonitor.swift         # AXIsProcessTrusted poll (2 s) + grant flow
└── SettingsView.swift                 # Settings scene: Schedule / Behavior / Permissions tabs
```

Layering: UI (`*View`, `YetAnotherMacAwakeApp`) → `AppState` → `AwakeEngine` /
`ScheduleStore`. `ScheduleStore` and `AccessibilityMonitor` are also
`ObservableObject`s consumed by UI. Singletons via `static let shared`.

## Commands

```bash
swift build                 # dev build (debug)
swift run                   # run raw binary (launch-at-login will not work; needs bundle)
./build.sh                        # release → YetAnotherMacAwake.app in repo root
open YetAnotherMacAwake.app       # run the bundle
./build.sh && open YetAnotherMacAwake.app   # normal rebuild+run cycle
```

### Verify (do this after each feature)

```bash
./.build/debug/YetAnotherMacAwake --selftest          # schedule logic, exit 0 = pass (44 cases)
./.build/debug/YetAnotherMacAwake --force-on          # activate without UI (for testing)
./.build/debug/YetAnotherMacAwake --pulse-now         # fire one pulse, print idle before/after, exit
pmset -g assertions | grep -i yetanothermacawake      # both display+system assertions; screen-off mode shows only the system assertion
log stream --predicate 'composedMessage CONTAINS "YetAnotherMacAwake"'   # live pulse logs
```

Expected log lines: `YetAnotherMacAwake pulse: silent key` | `YetAnotherMacAwake pulse: mouse jiggle`
| `YetAnotherMacAwake pulse: screen off override` | `YetAnotherMacAwake pulse skipped: no selected messaging app running`
| `YetAnotherMacAwake pulse skipped: screen off mode` | `YetAnotherMacAwake pulse skipped: on battery, sleep allowed`.

## Domain gotchas (learned the hard way — respect these)

- **Pulse key must be inert.** F11 (`0x67`) is "Show Desktop" — never use it.
  Default is **F20 (`0x5A`)**: no default action on macOS, not bound by
  Aerospace. User runs Aerospace (i3-like), which may bind F13–F19 — that's why
  the Silent key picker exists in Settings.
- **Jiggle must use absolute coordinates from the real cursor.**
  `NSEvent.mouseLocation` is bottom-left origin; CGEvent positions are
  top-left. Convert, then post 1px out and back. NEVER post `mouseCursorPosition:
  .zero` with delta fields — macOS may ignore deltas and teleport the cursor to
  (0,0) (this shipped once; it's a regression).
- **`NSEvent.mouseLocation` → CG conversion**: flip Y against the primary
  screen's height (`NSScreen.screens.first(where: { $0.frame.origin == .zero })`).
- **Pulse interval vs presence threshold.** Teams flips to Away at ~5 min of idle.
  Default pulse interval 120 s (range 30–600). 240 s is the outer safe bound —
  do not raise the default.
- **Messaging-app detection is bundle-ID based**: Teams `com.microsoft.teams`
  (classic) and `com.microsoft.teams2` (new), Slack `com.tinyspeck.slackmacgap`,
  Discord `com.hnc.Discord`, Zoom `us.zoom.xos`. An app counts as running when
  any of its bundle IDs matches.
- **Accessibility grant resets on every rebuild** (ad-hoc signing changes the
  code hash). Re-grant in System Settings after `./build.sh`. UI must poll
  (`AccessibilityMonitor`) rather than read once at launch.
- **No XCTest available** (Command Line Tools environment). Tests are a CLI
  self-test inside `AppDelegate.runSelfTest()` run via `--selftest`. Keep it
  green; add cases there.
- **macOS 26 dropped `NSWorkspace` power-change notifications** — poll power
  state with a 30 s `Timer` in the engine.
- **Launch-at-login (`SMAppService.mainApp`)** only works from a bundled,
  signed `.app`. Revert-toggle to `SMAppService.mainApp.status` on failure.
- **Lid close / manual sleep always wins** — by design, do not "fix". The one
  exception is screen-off mode (`settings.allowDisplaySleep`): it swaps the
  system assertion to `PreventSystemSleep` (`caffeinate -s`), which survives a
  closed lid while on AC power. Battery power ignores the assertion, and some
  Macs still sleep on lid-close without an external display (clamshell).
- Pulse fires only when `settings.pulseApps` is non-empty AND at least one
  selected app is running; an empty selection always pulses. The sleep assertion
  still holds regardless (screen stays awake even if pulse is skipped).
- **Screen-off mode pauses the pulse by default.** Any fake activity (F20/jiggle)
  resets the idle timer, which keeps the display from ever sleeping. When
  `settings.allowDisplaySleep` is on, `pulse()` early-returns and the engine
  holds only `PreventSystemSleep` (no display assertion) — unless
  `settings.pulseWhenScreenOff` opts back in, trading display sleep for presence
  availability.
- **"Disable for N" pause is ephemeral and overrides everything.** `AppState`
  holds `pausedUntil`/`pausedMinutes` in memory only (reset on relaunch, never
  persisted). While paused, `evaluate()` forces the engine off regardless of
  mode/schedule/AC rule; a 1 s ticker counts down and clears the pause the
  moment it expires, then `evaluate()` restores mode/schedule state. Mode card
  clicks still land during a pause but apply only after it ends.

## Persistence (UserDefaults keys)

All keys are string constants in `SettingsKey` (`settings.onlyOnAC`,
`settings.pulseApps`, `settings.pulseMethod`, `settings.pulseIntervalSeconds`,
`settings.pulseKey`, `settings.launchAtLogin`, `settings.allowDisplaySleep`,
`settings.pulseWhenScreenOff`) and
`ScheduleStore` (`schedule.mode`, `schedule.days`). `ScheduleStore` persists
`[DaySchedule]` (7, Monday=0…Sunday=6) as JSON under `schedule.days`, mode under
`schedule.mode`. Keep `@AppStorage` defaults and `UserDefaults.register`
in `AppDelegate.applicationDidFinishLaunching` in sync — drift between them
caused a real bug.

## Code conventions

- Swift 5.9, 4-space indent, no semicolons, `#if` only when needed.
- `final class` singletons (`static let shared`); `@Published` for UI state.
- Enums with raw values for settings/options (`Mode`, `PulseMethod`,
  `PulseKey`) + a `label` for display.
- `NSLog("YetAnotherMacAwake …")` (not `print`) for runtime diagnostics so they show in
  Console; `print` only for CLI/self-test output.
- Comments explain *why* (especially around CoreGraphics/IOKit quirks), not what.
- Use `private init()` for singletons; keep timer invalidation explicit.
- No third-party deps; if you think one is needed, ask first.

## Workflow

### Align before big work

Ambiguous or multi-path tasks: ask with **numbered choices** (recommend one),
wait for pick. Loop until aligned. No silent pick of architecture, scope, or UX.
Trivial one-file fixes can skip.

### Commits

Only when user asks. Message via caveman-commit rules: Conventional Commits,
subject ≤50 chars when possible, body only for non-obvious why. No AI
attribution fluff. Stage only intended files; never commit secrets or real
`config.json` paths (none exist — keep it that way). `AGENTS.md` is tracked
intentionally; `.gitignore` already covers `.build/`, `*.app`, `.DS_Store`.
Commit feature by feature — one logical change per commit.

### Verify before committing

`swift build` clean, `--selftest` green, bundle builds via `./build.sh`, and
any behavior change smoke-tested with the verify commands above.




## Agent skills

### Issue tracker

Specs and issues live as local markdown under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels, same strings as the skills: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` + `docs/adr/` at the repo root when they exist. See `docs/agents/domain.md`.
