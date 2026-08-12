# Sched 1.0.3

Sched 1.0.3 is a compactness, calendar interoperability, menu-bar, and long-running lifecycle release.

## macOS 27 stabilization

- Repairs the clean Swift 6 build and removes the temporary Swift 5 language-mode fallback.
- Keeps the warm light canvas legible when macOS itself is in Dark Mode.
- Uses native interactive glass where supported while preserving a stable fallback on older systems.
- Makes custom navigation and reminder cards keyboard-operable and visible to VoiceOver.
- Rebuilds interventions as three deliberately different message formats: movable corner message, edge banner, and full-screen conversation.
- Removes corner/banner Snooze and Done controls in favor of an outward swipe to snooze and press-and-hold to complete, with keyboard, VoiceOver, and context-menu equivalents.
- Makes alert surfaces opaque while keeping the utility window's native glass treatment.
- Adds a fixed-depth bottom fade to the Plan list so compact and wide windows end consistently instead of cutting a card.
- Adds an optional AI convenience page for provider/key/endpoint detection, on-demand Ollama or LM Studio controls, and secret-free packet export.
- Treats dismissing a macOS banner separately from completing the underlying reminder.
- Replaces permanent app-limit polling with workspace events and one threshold timer.
- Stops display timers when their panel, utility, or paused timer no longer needs live updates.
- Makes icon packaging deterministic in CI and prevents development builds from terminating installed copies.

## Compact utility window

- Restores a deliberately smaller default window (820×560 pt) with a 720×500 pt minimum.
- Caps the utility window at a practical size instead of stretching reminder cards across a display.
- Uses a new frame-autosave identity so oversized frames saved by earlier builds do not carry forward.
- Reminder titles fade at the trailing edge and expose the complete title on hover.
- Reminder descriptions wrap naturally and can use the full card height rather than being horizontally clipped.
- Reminder notes support substantially more text and use a multiline editor in the inspector.

## Calendar interoperability

- Calendar now has first-class `Today`, `+ Event`, and `+ Reminder` actions.
- Adds a native Calendar event editor with title, date/time, all-day mode, writable calendar selection, location, and notes.
- Sched reminders can be pushed into Calendar from Plan or Calendar context menus.
- Calendar events can be converted into Sched reminders with their title, start time, location, and notes carried over.
- Sched remembers the EventKit identifier for events created from reminders so future builds can deepen the relationship without guessing.
- Calendar refreshes on Sched store changes, EventKit store changes, app activation, wake, clock changes, and time-zone changes.
- Agenda titles use trailing fade/hover behavior and detail text wraps instead of escaping the row.
- Empty Calendar days explicitly surface the event/reminder creation path.

## Menu bar

### Clock / Calendar utility

- Keeps the Clock and Timer as separate status items.
- The clock menu includes a clickable compact month calendar.
- Clicking a day opens that exact date in Sched Calendar.
- Upcoming one-time reminders remain visible at the root.
- Daily reminders live in a dedicated Dailies submenu.
- All enabled reminders remain reachable from an All Reminders submenu.
- Reminder rows open the exact reminder and its inspector, not merely the Plan section.
- Shows today's Calendar events and opens the corresponding date.
- Adds New Event and New Reminder actions directly to the clock menu.
- Clock updates are aligned to the next second/minute boundary and stop entirely while the status item is disabled.

### Timer utility

- Replaces the preset-only idle menu with a compact native quick-start control.
- Keeps 5, 25, and 50 minute one-click starts while adding a numeric custom-duration field and stepper.
- Saved durations remain available in a submenu.
- The status item only runs a one-second display timer while a non-paused timer is actively counting down.

## Background and headless operation

- Adds a Dock presence preference: Always, While the window is open, or Never.
- Sched can remain alive with no visible window, no Dock icon, and both menu-bar utilities disabled.
- Background scheduling, timer state, app limits, notifications, and alarm audio are owned by app services rather than the main window.
- Opening Sched again always restores the GUI even when the process was already running headlessly.
- Wake, system clock, and time-zone changes re-evaluate scheduling and Calendar state.
- Hidden status items stop unnecessary refresh timers for better long-running behavior.

## Routing and interaction

- Notification clicks open the exact reminder when an alarm identifier is available.
- Adds semantic URL routes for opening sections, exact reminders, and Calendar dates.
- `sched://` remains the preferred URL scheme while `keen://` compatibility is retained.
- Plan cards support double-click edit and context actions including Add to Calendar.

## Compatibility

- Marketing version: `1.0.3`
- Build: `103`
- Minimum macOS: 14.0
- Existing Sched data and legacy Keen migrations remain supported.
