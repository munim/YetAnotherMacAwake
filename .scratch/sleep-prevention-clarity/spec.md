# Spec: Sleep-prevention settings clarity (two-axis model)

Status: ready-for-agent
Type: spec

## Problem Statement

The Settings → Behavior → "Sleep prevention" section is confusing. It hides one
orthogonal decision behind a double-negative toggle and expresses a power
restriction as a behavior promise:

- `"Allow display to sleep while awake"` — readers cannot tell what "awake"
  refers to (the app? the system? the user?). It is a screen-vs-system decision
  buried in negated phrasing.
- `"Prevent sleep only on AC power"` — reads like a promise ("prevent sleep")
  when it is actually a restriction ("drop keep-awake on battery").

The section also conflates three independent concerns: **what stays awake**
(screen vs system), **power policy** (AC vs battery), and **Teams
availability** (the activity pulse). Two functional gaps hide behind the
wording:

- Screen-may-sleep mode silently pauses the Teams pulse, so "Available in
  Teams" silently becomes "Away" with no warning and no opt-out.
- When the AC-only rule drops assertions on battery, nothing tells the user why
  their screen is sleeping.

## Solution

Restructure sleep-prevention settings around an explicit two-axis model,
keeping the existing Mode (Always / Follow schedule / Off) as the "when" axis
and adding a clearly-worded "what stays awake" axis:

- **Axis 2 — "What stays awake?"** becomes a first-class, mutually exclusive
  picker with exactly two options: **"Screen and system"** (default, display
  stays awake) and **"System only — screen may sleep"** (display sleeps on its
  normal timer, system keeps running; `PreventSystemSleep`, survives a closed
  lid on AC). This replaces the `"Allow display to sleep while awake"` toggle.
  The persisted key is unchanged, so no migration.
- The power restriction is reworded in the positive: **"On battery, allow
  sleep"** (was "Prevent sleep only on AC power"), with a caption that states
  the consequence: on battery the Mac may sleep and Teams may go Away.
- The Teams pulse conflict becomes visible and optional: an inline warning in
  Settings when screen-may-sleep + Teams pulse are both on, plus a new opt-out
  toggle **"Keep Teams Available even when the screen may sleep"** that
  re-enables the pulse in screen-off mode (accepting the display may wake
  briefly or never sleep).
- The menu bar status line reports dropped state: it keeps the existing
  "· Screen off" suffix and adds "· On battery — sleep allowed" when the AC
  rule drops assertions, and "· Teams may go Away" when the pulse conflict is
  live. The pause countdown text stays untouched.
- Settings sections are reordered by dependency: **Awake behavior → Power →
  Teams availability → Startup**. "Activity pulse" is renamed "Teams
  availability".

## User Stories

1. As a user, I want the double-negative "Allow display to sleep while awake" replaced by a clear "What stays awake?" choice, so I understand what the setting actually controls.
2. As a user, I want exactly two mutually exclusive options — "Screen and system" and "System only — screen may sleep" — so I can never express an invalid combination like "screen on but system sleeping".
3. As a user with an existing configuration, I want the default and persisted value unchanged ("Screen and system"), so updating the app changes no behavior.
4. As a user, I want selecting "System only — screen may sleep" to write the same persisted key as today, so no settings migration or data loss occurs.
5. As a user, I want the display-behavior choice to apply immediately when changed, so assertion types swap without waiting for the 30-second poll.
6. As a user, I want the display-behavior choice settable even when Mode is Off or paused, so the preference pre-arms for when awake starts.
7. As a user, I want "Prevent sleep only on AC power" renamed to "On battery, allow sleep", so the effect is stated positively and unambiguously.
8. As a user considering the battery rule, I want a caption that says on battery the Mac may sleep and Teams may go Away, so I know the trade-off before enabling it.
9. As a user running screen-may-sleep with Teams pulsing, I want an inline warning in Settings that the pulse pauses and Teams may go Away, so the silent behavior becomes visible.
10. As a user running screen-may-sleep with Teams pulsing, I want an opt-out toggle "Keep Teams Available even when the screen may sleep", so I can keep both behaviors when the display trade-off is acceptable.
11. As a user enabling that opt-out, I want a caption warning that the display may wake briefly or never sleep, so I accept the trade-off knowingly.
12. As a user enabling that opt-out, I want the pulse to still respect the Teams-running check and the AC-only rule, so constraints compose instead of overriding each other.
13. As a user, I want the "Activity pulse" section renamed to "Teams availability", so its purpose is obvious at a glance.
14. As a user, I want the Settings sections ordered Awake behavior → Power → Teams availability → Startup, so the settings read top-to-bottom as a decision story.
15. As a user, I want the menu bar radios ("Screen Stays On" / "Screen Can Sleep") to stay in sync with the new Settings picker via the same key, so the two entry points never drift.
16. As a user, I want the menu status line to keep the existing "· Screen off" suffix in screen-may-sleep mode, so the menu matches Settings.
17. As a user on battery with the AC rule on and awake active, I want the menu status line to show "· On battery — sleep allowed", so I understand why my screen is sleeping.
18. As a user in a pause, I want the "Disabled · mm:ss" countdown text left completely untouched by the new suffixes, so pause state stays unambiguous.
19. As a user running screen-may-sleep + Teams pulse with no override, I want the menu status line to show "· Teams may go Away", so the warning is visible without opening Settings.
20. As a user running screen-may-sleep + Teams pulse with the override on, I want the "Teams may go Away" warning to disappear, so the status line reflects the actual behavior.
21. As a user, I want the awake-mode cards (Always / Follow schedule / Off) unchanged, so the top-level mental model stays intact.
22. As a user, I want all existing settings keys and their default values preserved, so the update is safe for anyone who installed the app before.
23. As a user, I want `pmset -g assertions | grep -i yetanothermacawake` to still show exactly the promised assertions for each combination, so I can verify behavior after the change.
24. As a user, I want the closed-lid-on-AC behavior of screen-off mode (system assertion only) to keep working, so nothing regresses from the menu screen-toggle feature.
25. As a developer, I want every combination of (active, battery rule, power state, screen behavior) covered by a pure-function self-test, so regressions are caught without a CI infrastructure.

## Implementation Decisions

- **No schema migration.** `settings.allowDisplaySleep` and `settings.onlyOnAC`
  keep their meaning and defaults (`false`). A new key
  `settings.pulseWhenScreenOff` (default `false`) gates the Teams-pulse override
  in screen-may-sleep mode. `@AppStorage` defaults and `UserDefaults.register`
  in the app delegate must stay in sync as before.
- **Two-axis model in Settings.** The display-behavior control changes from a
  toggle to a two-option picker ("Screen and system" / "System only — screen
  may sleep"). The battery control is reworded to "On battery, allow sleep".
  The Teams-pulse override is a new toggle gated to the screen-may-sleep case
  (hidden or irrelevant when "Screen and system" is selected). Sections
  reordered: Awake behavior → Power → Teams availability → Startup.
- **Single behavior seam: a pure assertion-profile function.** The decision
  currently scattered across `shouldHoldAssertions()`, `holdAssertions()` and
  `recheck()` collapses into one dependency-free static function (shape from
  the confirmed design):

  ```swift
  enum AssertionProfile { case none, screenAndSystem, systemOnly }

  static func assertionProfile(active: Bool, onlyOnAC: Bool,
                               onACPower: Bool, allowDisplaySleep: Bool) -> AssertionProfile {
      guard active else { return .none }
      if onlyOnAC && !onACPower { return .none }
      return allowDisplaySleep ? .systemOnly : .screenAndSystem
  }
  ```

  `recheck()` computes `want = assertionProfile(...) != .none` and the actual
  assertion set from the profile; the existing hold/release/swap machinery is
  unchanged. This function is the sole new unit-test seam.
- **Engine pulse gating becomes conditional.** The screen-off early return in
  `pulse()` pauses only when `pulseWhenScreenOff` is off. When the override is
  on and a pulse fires in screen-off mode, log
  `YetAnotherMacAwake pulse: screen off override` so the behavior is
  observable in `log stream`.
- **Status text rides the existing pure seam.** `menuStatusText` (the
  dependency-free formatter already extended for "· Screen off") gains the new
  state flags: battery-drop (shown when awake is active, the AC rule is on, and
  power is battery) and teams-pulse-paused (shown when screen-may-sleep and
  Teams pulsing are on without the override). The pause countdown branch is
  left byte-for-byte untouched.
- **Power state for the status line.** The engine already polls power; expose
  an observable AC-power value so `AppState` can feed the battery-drop flag into
  the status seam. The 30-second poll already exists; no new timer.
- **Menu bar.** The Screen On/Off radios keep their behavior and key; labels are
  aligned to the new vocabulary where they currently drift. Status suffixes are
  produced exclusively by the extended pure seam.
- **This spec reopens one earlier decision.** The prior `menu-screen-toggle`
  spec declared "pulse stays paused in screen-off mode" out of scope. That is
  intentionally reopened by this spec (the opt-out toggle) — the user asked for
  functional changes, and this is the only behavioral divergence from the
  shipped feature.

## Testing Decisions

- A good test asserts only external, user-visible behavior: which assertion
  profile results from each combination of user settings + power state, and
  what status text the menu shows. It never asserts IOKit calls, view layout,
  or internal helper structure.
- **Modules tested:** the new pure `assertionProfile` function (sole new unit
  seam, in the engine module) and the extended pure `menuStatusText` formatter
  (existing seam, in the app-state module). Both are exercised through the
  single existing `--selftest` CLI — no new test infrastructure, no XCTest.
- **Prior art:** the `--selftest` CLI already covers schedule-window logic,
  `activeNow`, `nextBoundary`, and the `menuStatusText` suffix cases from the
  `menu-screen-toggle` feature. New cases extend the same two seams.
- Concrete new cases for `assertionProfile`:
  - mode not active → `.none` regardless of all other inputs;
  - active, no battery rule, screen-and-system → `.screenAndSystem`;
  - active, screen-may-sleep → `.systemOnly`;
  - active, battery rule on, on AC → `.screenAndSystem` (or `.systemOnly`);
  - active, battery rule on, on battery → `.none`;
  - active, no battery rule, on battery → `.screenAndSystem` (battery allowed
    when the rule is off).
- Concrete new cases for `menuStatusText`: existing six cases must stay green
  (signature evolves, assertions updated); on-battery + AC rule + active →
  "· On battery — sleep allowed" suffix; paused + battery → countdown
  untouched; screen-may-sleep + Teams pulsing → "· Teams may go Away";
  screen-may-sleep + override on → no Teams suffix.
- The pulse override, assertion swap, and Settings UI are covered by the
  existing manual verify commands: `pmset -g assertions | grep -i
  yetanothermacawake`, `log stream --predicate 'composedMessage CONTAINS
  "YetAnotherMacAwake"'`, and a visual check of the built bundle.

## Out of Scope

- Redesigning the Mode cards (Always / Follow schedule / Off) or the Schedule
  tab.
- Changing IOKit assertion types or power physics (battery still ignores the
  system assertion; clamshell lid-close still sleeps without an external
  display).
- Changing any default value (`onlyOnAC=false`, `allowDisplaySleep=false`).
- A new persistence schema or data migration — all keys keep their meaning.
- Restyling menu bar radios, segmented controls, or the Settings window frame.
- The Accessibility grant flow or permissions tab.
- UI test infrastructure of any kind.
- Alert/popover confirmations when toggling screen behavior (deliberately
  rejected; an inline warning + status suffix is enough).

## Further Notes

- No ADRs exist in the repo; this spec uses the vocabulary from AGENTS.md:
  "screen-off mode", "display-sleep mode", "Mode" (off/on/scheduled), "pulse",
  "assertion", "PreventSystemSleep", "PreventUserIdleDisplaySleep", "Teams
  Available", "pause", "AC-only rule".
- The two-axis model keeps a direct mapping to the engine: `.screenAndSystem`
  holds `PreventUserIdleDisplaySleep` + `PreventUserIdleSystemSleep`;
  `.systemOnly` holds only `PreventSystemSleep`; `.none` releases everything.
- The `pulseWhenScreenOff` override intentionally trades display sleep for
  Teams availability; the caption must make that trade explicit, and the pulse
  still respects the Teams-running check and the AC-only rule.
- Verify after implementation: `swift build` clean, `--selftest` green,
  `./build.sh` bundle builds, `pmset -g assertions | grep -i
  yetanothermacawake` shows the expected assertion set per profile, and the menu
  status line reflects battery and Teams-pulse states.
- Accessibility grant resets on every rebuild (ad-hoc signing) — re-grant in
  System Settings before keyboard-testing the pulse override.
