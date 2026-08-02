# Spec: Menu Screen On/Off radios

Status: ready-for-agent
Type: spec

## Problem Statement

I keep the system awake and my Teams status Available during configured windows, but sometimes I want the *display* to sleep while the system keeps working (screen-off mode). Today the only way to switch between "screen stays on" and "screen may sleep" is to open Settings → Behavior and flip "Allow display to sleep while awake". The menu bar dropdown already controls awake mode, pause, and schedule — but display behavior is missing, so I have to dig into Settings every time.

## Solution

The menu bar dropdown gets a new always-visible row directly below the three mode cards: two side-by-side radio buttons, **Screen On** and **Screen Off**.

- **Screen On** (default): the display stays awake — current behavior.
- **Screen Off**: the display sleeps on its normal timer while the system stays awake, so Teams stays Available. Identical to the existing "Allow display to sleep while awake" setting, which stays in sync.

The active radio shows a filled circle; the status line appends "· Screen off" when Screen Off is active, so the menu never contradicts itself. The choice persists across relaunches and pre-arms the behavior for whenever the engine becomes active.

## User Stories

1. As a user, I want two side-by-side radio buttons — Screen On and Screen Off — in the menu bar dropdown, so I can switch display behavior without opening Settings.
2. As a user, I want Screen On selected by default, so existing behavior (display stays awake) is unchanged on first run.
3. As a user, I want the active radio to show a filled circle, so I can tell current state at a glance.
4. As a user, I want the Screen On/Off row always visible, so I can find it without digging into submenus or Settings.
5. As a user, I want Screen Off to let the display sleep on its normal timer while the system stays awake, so Teams stays Available without a bright screen.
6. As a user, I want Screen Off to survive a closed lid while on AC power (system assertion only), so a laptop can sit closed and keep working.
7. As a user, I want the radio selection to persist across relaunches, so I don't have to reset it each time.
8. As a user, I want the status line to show "· Screen off" when Screen Off is active, so the mode cards and display state never contradict each other.
9. As a user, I want the status line unchanged when Screen On is active, so no new noise in the common case.
10. As a user, I want the radios always enabled, so I can pre-arm my preference even when the engine is inactive (mode Off or paused).
11. As a user, I want toggling a radio to take effect immediately, so the assertion types swap without waiting for the 30-second poll.
12. As a user, I want the Settings → Behavior toggle and the menu radios to stay in sync, so there is one source of truth and no drift.
13. As a user running with Screen Off, I want the activity pulse to keep pausing, so the display can actually turn off instead of being reset by fake activity.
14. As a user with mode Off, I want Screen On/Off to still accept a selection, so the preference is ready when I turn the engine on.
15. As a user on battery with Screen Off, I want graceful degradation (battery ignores the system assertion), so the display sleeps naturally without errors.
16. As a user using "Prevent sleep only on AC power", I want Screen Off to remain subject to that rule, so AC/battery behavior stays consistent.
17. As a user with a paused state, I want the status line to keep showing the "Disabled · mm:ss" countdown without the Screen Off suffix, so pause state stays unambiguous.
18. As a user, I want the Screen On/Off row visually separated from the awake-mode cards by a divider, so I don't confuse display behavior with awake mode.
19. As a user, I want the radio pair to use a circle + icon + label layout, so it reads as a radio control and is identifiable at a glance.
20. As a user, I want toggling Screen On to hold both display and system assertions, so the display stays awake as before.
21. As a user, I want no confirmation dialogs on toggle, so the menu stays fast to use.
22. As a user with scheduled mode, I want Screen Off to apply inside awake windows, so display behavior follows my preference during scheduled awake time.

## Implementation Decisions

- The feature lives entirely in the menu layer (menu content view + status-line text). No changes to the engine, the schedule store, or the persistence schema — the setting key already exists and the engine already re-reads it on every recheck.
- The radio pair is a custom SwiftUI row of two buttons (not native NSMenu radio items) because the menu is a `MenuBarExtra` with `.menu` style rendering custom SwiftUI views, and the buttons must sit side by side.
- Selected state is shown with a filled circle glyph tinted with the accent color; unselected uses a hollow circle. Each button pairs the circle with an SF Symbol (sun.max.fill for Screen On, moon.fill for Screen Off) and a label.
- Selecting a radio writes the existing setting key and triggers the existing immediate re-evaluation path, so assertion types swap right away — no 30-second poll wait.
- The status-line suffix is computed by a pure, dependency-free function (status text for the current mode + a screen-off flag). It appends " · Screen off" to the normal mode-driven status text only; the pause countdown text is untouched.
- The Settings tab keeps its existing toggle bound to the same key. Both entry points write the same persisted value — single source of truth.
- The radios are always enabled. Screen On/Off is a persistent preference, pre-armed for whenever the engine becomes active; no gray-out for mode Off or pause.
- Default remains unchanged (setting off → Screen On selected).
- The suffix function is isolated so the CLI self-test seam can exercise it without instantiating singletons.

## Testing Decisions

- A good test asserts only external, user-visible behavior — the computed menu status text for each mode × screen-off combination. It never asserts button internals, layout, or rendering.
- The only module with new logic is the status-line text computation; that is the sole unit seam and it is exercised through the existing `--selftest` CLI.
- Prior art: the repo has no XCTest; the established test seam is the `--selftest` CLI self-test (schedule-window logic, mode `activeNow`, next-boundary cases). New cases extend that same seam rather than adding a new one.
- Concrete new cases: mode on + screen on → no suffix; mode on + screen off → "· Screen off"; scheduled active + screen off → suffix; mode off + screen off → suffix; paused + screen off → no suffix (countdown text unchanged); paused + screen on → unchanged.
- Menu radio rendering and the assertion swap are not unit-testable in this codebase; they stay covered by the existing manual verify commands (`pmset -g assertions | grep`, visual menu check via the built bundle).

## Out of Scope

- Any change to engine assertion logic (the `PreventSystemSleep` swap for screen-off mode already exists).
- Any change to pulse behavior in screen-off mode (pulse stays paused).
- Replacing or restyling the existing three-card awake-mode row.
- Native NSMenu radio items or segmented-control styling.
- New persistence schema — reuses the existing setting key.
- Battery / lid-close behavior changes.
- Warning UI for battery or AC-only edge cases (deliberately rejected during design).
- Graying out the radios when the engine is inactive or paused (deliberately rejected during design).
- UI test infrastructure of any kind.
- Any change to the Accessibility grant flow or permissions.

## Further Notes

- Design was sharpened through a grilling session; five decisions were settled: semantics (Screen Off = existing display-sleep mode), placement (own divider row under the mode cards), feedback (status-line suffix), enabled-state (always enabled, persistent preference), and visuals (radio circle + SF Symbol + label).
- No ADRs exist in the repo; no domain glossary file exists. This spec uses the vocabulary from AGENTS.md: "screen-off mode", "display-sleep mode", "Mode" (off/on/scheduled), "pulse", "assertion", "PreventSystemSleep", "Teams Available", "pause".
- After implementation, the Accessibility grant resets on every rebuild (ad-hoc signing) — re-grant in System Settings before keyboard-testing the radio row.
- The existing menu already presents three side-by-side mode cards; the new row sits below them under its own divider, so display behavior is visually distinct from awake mode.
- Verify after implementation: `swift build`, `--selftest` green, `./build.sh` bundle, and `pmset -g assertions | grep -i yetanothermacawake` shows only the system assertion when Screen Off is selected.
