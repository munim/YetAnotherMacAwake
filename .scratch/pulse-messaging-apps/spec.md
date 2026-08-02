# Spec: Pulse for messaging apps (replace Teams-only gate)

Status: ready-for-agent
Type: spec

## Problem Statement

The activity pulse — the fake input (silent F-key or mouse jiggle) that resets the
system idle timer — is gated on **Microsoft Teams specifically**. When
`settings.teamsOnly` is on (the default), `pulse()` skips unless a process with
bundle ID `com.microsoft.teams` or `com.microsoft.teams2` is running. The
underlying problem is not Teams-specific: every messaging app (Slack, Discord,
Zoom Workplace, Telegram, …) flips presence to Away after a period of idle, and
the mechanism that prevents it is identical. A user who keeps Slack open gets no
benefit, and the product is Teams-locked throughout — the `teamsOnly` setting,
the status suffix "· Teams may go Away", the skip log, and the About copy.

Separately, the gate defaults **on**, so out of the box the pulse only fires when
Teams happens to be running. The desired default is the opposite: keep the user
active unconditionally, and let them opt into app-gated pulsing in Settings.

## Solution

Replace the single Teams-only gate with a **multi-select list of known messaging
apps** in Settings. The pulse gates on *any checked app being running*.

- The known list ships with four verified apps: **Teams, Slack, Discord, Zoom**.
  Each entry is a checkbox. Teams detection keeps matching both classic
  (`com.microsoft.teams`) and new (`com.microsoft.teams2`) clients.
- **Default: nothing checked = always pulse.** There is no separate gate switch
  and no "never pulse" state; an empty selection simply means the pulse fires
  whenever the engine is active. Checking one or more apps makes the pulse fire
  only while *at least one* of those apps is running (any-of matching).
- The gate is re-evaluated on every pulse, so launching or quitting an app takes
  effect on the next interval (no extra polling, no manual refresh).
- **No migration.** The old `settings.teamsOnly` key is removed from
  `SettingsKey`, the Settings UI, and the `UserDefaults.register` defaults; any
  stale value left in `UserDefaults` is ignored. Everyone — existing and new
  users — lands on the new default: always pulse.
- Status text: the menu suffix "· Teams may go Away" becomes "· Presence may go
  Away". The skip log becomes "pulse skipped: no selected messaging app
  running". About copy becomes "keeps you Available in your messaging apps
  (Teams, Slack, Discord, Zoom)".
- Everything else is unchanged: pulse method (silent key / jiggle), pulse
  interval, screen-off mode, the screen-off pulse override, and the AC-only rule
  all keep their current semantics.

## User Stories

1. As a user on Slack, I want the activity pulse to keep my Slack presence Available, so I stop flipping to Away during long runs.
2. As a user on Discord or Zoom, I want the same idle-reset behavior I get on Teams, so my presence stays green on any platform.
3. As a new user, I want the app to pulse always out of the box, so I'm kept active with zero setup.
4. As a user who wants pulsing only while a specific app runs, I want to check that app in Settings, so fake input doesn't fire when nothing relevant is running.
5. As a user with several apps checked, I want the pulse to fire when any one of them is running, so having Slack open is enough even when Discord is closed.
6. As a user with all apps unchecked, I want the pulse to always fire, so an empty selection means "no gate" rather than "never pulse".
7. As a user, I want the app list in Settings to show readable names (Teams, Slack, Discord, Zoom), so I can recognize what I'm selecting.
8. As a Teams user, I want both the classic and new Teams clients detected, so my presence stays Available whichever client I run.
9. As a user who quits every checked app, I want the pulse to skip with the generic log "pulse skipped: no selected messaging app running", so the log says why without naming a specific vendor.
10. As a user who checks an app and then launches it, I want the next pulse to fire immediately, so gating reacts to app launch without a restart.
11. As a user who unchecks every box, I want gating to turn off on the next pulse, so the change to always-pulse is immediate.
12. As a user in screen-off mode with at least one app checked and no override, I want the menu to say "· Presence may go Away", so I know the pulse is paused and my presence is at risk.
13. As a user in screen-off mode with no apps checked, I want no presence warning, so I'm not warned about a mode I opted out of.
14. As a user with the screen-off pulse override enabled, I want the presence warning to disappear, so the menu reflects that the pulse will keep firing.
15. As an existing user upgrading, I want my old Teams-only setting to be ignored cleanly with no migration prompt, so the update just works.
16. As a user, I want my app selection to persist across relaunches, so I don't re-configure each launch.
17. As a user, I want the pulse method, interval, screen-off mode, and AC-only rule to behave exactly as before, so this change only affects *which apps gate the pulse*.
18. As a user with the screen-off override on and the AC-only rule on, I want the override to still respect the battery rule, so the screen-off override keeps its current contract.
19. As a user, I want no new permissions or prompts, so gating still relies on the same bundle-ID detection that needs no extra access.
20. As a maintainer, I want the gate decision isolated as a pure function, so the `--selftest` CLI can cover pulse-vs-skip without instantiating singletons or posting events.
21. As a maintainer, I want adding a future app to be a one-case change in the known-app enum, so the list is trivially extensible.
22. As a user, I want the About text to stop claiming Teams-only support, so the product description matches what the app actually does.
23. As a user with Telegram installed, I want it listed as an easy future addition (verified bundle ID exists), even though it's not shipped in this change.
24. As a user, I want the presence warning and skip logs to use one consistent "presence" vocabulary, so the app no longer mentions Teams in status copy.


## Implementation Decisions

- **Known-app model**: a new `MessagingApp` enum in the engine module, cases
  `teams`, `slack`, `discord`, `zoom`. Each case exposes a display name and a
  bundle-ID set. Teams carries both `com.microsoft.teams` and
  `com.microsoft.teams2`. Bundle IDs were verified against the Mac App Store
  (Slack: `com.tinyspeck.slackmacgap`) and Homebrew cask definitions (Discord:
  `com.hnc.Discord`, Zoom: `us.zoom.xos`); the Teams pair was already in the
  codebase. Telegram (`ru.keepcoder.Telegram`) verified but deliberately not
  shipped in v1. Google Chat has no native macOS bundle ID (Chrome PWA only) and
  is excluded.
- **Persistence**: a new `SettingsKey.pulseApps` holding an array of
  `MessagingApp` raw values, default empty (= always pulse). `settings.teamsOnly`
  is removed from `SettingsKey`, `SettingsView`, and the
  `UserDefaults.register` defaults. Per the existing drift rule, the
  `@AppStorage` default and the `register` default must stay in sync. The exact
  array encoding (JSON `Data` vs delimited string) is settled at implementation;
  both keep the same default.
- **Gate logic**: `pulse()` reads `pulseApps` each time it fires. If the
  selection is empty it proceeds unconditionally. Otherwise it collects the
  bundle IDs of running apps from `NSWorkspace.shared.runningApplications` and
  delegates the pulse-vs-skip decision to a pure function
  `pulseGate(selected:runningBundleIDs:) -> Bool`: true when the selection is
  empty or any selected app's bundle IDs intersect the running set. On false it
  logs "pulse skipped: no selected messaging app running" and returns.
  `TeamsDetection` is replaced by this generalized running-app check.
- **Status suffix**: the pure `menuStatusText` formatter's boolean parameter is
  renamed `teamsPulsePaused` → `presencePulsePaused` and its output string
  becomes "· Presence may go Away". `AppState.stateText` computes that boolean as
  screen-off enabled AND the `pulseApps` selection is non-empty AND the screen-off
  pulse override is off — deliberately mirroring the old `teamsOnly`-on
  condition, so the warning only appears when the user has opted into app gating.
- **Settings UI**: the Behavior tab's "Teams only" toggle is replaced by a
  "Pulse only when one of these apps is running" section with one checkbox per
  known app, default all unchecked.
- **No migration**: the old key is simply never read; stale persisted values are
  inert.

## Testing Decisions

- A good test asserts only external behavior: *does the pulse fire or skip given
  a selection and a set of running apps*, and *what exact status text does the
  menu show*. It never asserts view layout, IOKit calls, or internal helper
  structure.
- **Modules tested**: the engine's new pure `pulseGate` function (sole new unit
  seam, mirroring the `assertionProfile` precedent) and the existing pure
  `menuStatusText` formatter (existing seam, extended). Both run through the
  single existing `--selftest` CLI — no new test infrastructure, no XCTest.
- **Prior art**: the `--selftest` CLI already covers schedule-window logic,
  `activeNow`, `nextBoundary`, the `assertionProfile` matrix, and the
  `menuStatusText` suffix cases from the `menu-screen-toggle` and
  `sleep-prevention-clarity` features. New cases extend those two seams.
- Concrete new `pulseGate` cases: empty selection + any running apps → pulse;
  one app selected and running → pulse; one selected and not running → skip;
  two selected, one running → pulse (any-of); two selected, none running → skip;
  Teams selected with classic bundle running → pulse; Teams selected with new
  bundle running → pulse; Teams selected with neither running → skip; selection
  empty while unrelated apps run → pulse.
- Concrete new `menuStatusText` cases: existing cases stay green with the renamed
  parameter and updated "· Presence may go Away" string; screen-may-sleep +
  presence pulsing → "Awake: On · Screen off · Presence may go Away"; all three
  suffixes still compose in order; override on → no presence suffix; paused →
  countdown untouched.
- Manual verify (unchanged surface): `--pulse-now` prints the skip log when the
  gate is on and no checked app is running, and pulses when a checked app runs;
  `pmset -g assertions | grep -i yetanothermacawake` is unaffected (gating never
  changes assertions); `log stream` shows the generic skip message.

## Out of Scope

- Adding Google Chat, Telegram, Mattermost, or any other app to the v1 list
  (Telegram's verified bundle ID is a one-case follow-up; Google Chat has no
  native bundle ID and would need browser-tab detection, which is rejected).
- User-entered/custom bundle IDs.
- Browser-tab or PWA detection of any kind.
- Per-app Away thresholds (each app gets its own pulse interval) — the global
  interval stays.
- Changing pulse method, default interval, screen-off mode, the screen-off
  override trade-off, or the AC-only rule semantics.
- Any change to IOKit assertion logic or power physics.
- Migrating or mapping the old `settings.teamsOnly` value (deliberately rejected).
- Restyling the Settings window, menu cards, or radios.
- The Accessibility grant flow or Permissions tab.
- UI test infrastructure of any kind.

## Further Notes

- Design was sharpened through a grilling session; decisions settled: scope
  (generalize the gate), shape (multi-select checkboxes, no gate switch), v1
  list (Teams, Slack, Discord, Zoom after bundle-ID verification), default
  (empty selection = always pulse), migration (none), and copy ("Presence may go
  Away", generic skip log, generic About text).
- Bundle-ID verification sources: Mac App Store lookup API (Slack, Telegram) and
  Homebrew cask definitions (Discord, Zoom). Google Chat was dropped after the
  App Store search returned only third-party wrappers, confirming no official
  native macOS client.
- No ADRs exist in the repo. This spec deliberately introduces a vocabulary
  shift from "Teams" to "messaging apps"/"presence"; AGENTS.md and any
  domain-glossary copy should be refreshed in the same change so the repo's
  language matches the feature.
- Consequence of the no-migration + empty-default decision: upgraded Teams users
  silently switch from Teams-gated pulsing to always-pulse, and fresh installs
  show no presence warning in screen-off mode until they check an app. This is
  intentional.
- Accessibility grant resets on every rebuild (ad-hoc signing) — re-grant in
  System Settings before keyboard-testing the pulse.
- Verify after implementation: `swift build` clean, `--selftest` green (existing
  cases updated, new gate cases added), `./build.sh` bundle builds, and
  `--pulse-now` / `log stream` show the generic skip message under the expected
  selection/running combinations.



