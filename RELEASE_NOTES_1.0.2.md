# Sched 1.0.2

This release is a maturity pass across the menu bar, timers, sounds, calendar interactions, limits, persistence, and internal naming.

## Menu bar

- Split the old combined menu-bar item into two independent utilities:
  - a clock/calendar item
  - a timer item
- Both utilities can be enabled independently in Preferences.
- The timer item can optionally hide itself while no timer is active.
- The clock menu now includes a compact month calendar, today's Calendar events and Sched reminders, reminder actions, and direct links back into Sched.
- The timer menu changes with timer state and exposes pause/resume, +5 minutes, finish, cancel, floating timer, and quick-start presets.
- Both status items have stable autosave names so macOS can retain their visibility/placement metadata.
- Added a conventional macOS application menu with Preferences, Services, Edit responder actions, section shortcuts, timer commands, and a real Window menu.

## Timers

- Added a shared `TimerService` so the main Timer view, menu bar, and floating timer operate on the same state.
- Added an optional floating timer utility window.
- Floating timer position is restored, closing it does not cancel the timer, and always-on-top behavior is configurable.
- The main Timer view now exposes active-state controls including pause/resume, +5 minutes, floating timer, and cancel.

## Sounds

- Added selectable macOS system sounds.
- Added per-reminder sound overrides, including an explicit silent override.
- Added managed short-sound imports. Files up to 5 seconds are copied into `~/Library/Application Support/Sched/Sounds`.
- Added linked audio for longer files. Linked files are not copied, so moving or deleting the source file intentionally breaks the link.
- Added volume, preview, and repeat-until-handled controls.
- Alert audio is now centralized so interventions, notification actions, previews, and dismiss operations agree about playback state.

## Calendar and Plan

- Fixed the custom month calendar's weekday/date column alignment.
- Added the Sched mark to the bottom of the navigation rail.
- Long agenda titles now truncate safely and retain their full text as a tooltip.
- Calendar reminder rows now expose contextual edit, snooze, disable, and delete actions.
- Menu-bar reminders open the exact reminder inspector instead of merely opening Plan.
- Plan reminder cards now expose contextual edit, move-later, duplicate, disable, and delete actions.

## Limits

- App limits now expose live runtime state, including current open duration and remaining time.
- The limits monitor publishes runtime updates to the UI instead of acting as a silent background rule engine.
- Newly created limits no longer silently attach a quit-app action; they use the configured intervention without a destructive follow-up by default.

## Reliability and migration

- Renamed the Swift package, executable target, source folder, test target, and internal `Keen*` types to `Sched*`.
- Existing data is migrated from `~/Library/Application Support/Keen` to `~/Library/Application Support/Sched` on first launch when needed.
- Added the `sched://` URL scheme while retaining `keen://` compatibility for existing shortcuts and links.
- Wake, system-clock, and time-zone changes force scheduler/menu-bar refreshes.
- Fixed idle detection so recent input is not masked by an older unused event type.
- Fixed daily reminders after long sleep/offline periods.
- Fixed alert dismissal so it does not hide the entire app.
- Fixed intervention target retention and narrowed notification actions to the alarm being acted on.

## Version

- Marketing version: `1.0.2`
- Build: `102`
- Minimum macOS: `14.0`
