# Recovered design references

Source task: `019ff41a-7643-7f83-98d7-8ab46d1d69e6`

Recovered from the Codex task history on 2026-08-11 after the original task ended with a connection error. These files are durable project references; do not depend on the original `/var/folders/.../codex-clipboard-*` paths.

## Current product direction

Sched is the intervention layer for the Mac: a user decides what future-them needs to encounter, and Sched makes the Mac intervene when that moment arrives. Plan, Calendar, Timer, Limits, Actions, and optional AI are inputs into that intervention system rather than separate product identities.

Interaction maturity is the primary standard: preserve context, support keyboard/mouse/trackpad/menus together, prefer reversible actions, keep feedback proportional, and avoid explanatory UI where the interaction can be learned naturally.

## Locked full-screen target

The visual source of truth is [08-fullscreen-wallpaper-locked-target.png](08-fullscreen-wallpaper-locked-target.png), interpreted with the user's final corrections:

- Show the user's wallpaper first, replacing the visible workspace, then fade it in slowly.
- Remove the top Sched label and any outgoing reminder bubble/time divider shown in earlier explorations.
- Bring in two large incoming message bubbles in close succession.
- Keep the composition dense and intentional rather than a sparse chat window.
- Use a commitment composer in the form `I will ...`.
- A large translucent three-dimensional Sched mark may live in the wallpaper treatment; it is backdrop, not interface chrome.
- Full-screen, corner, and banner interventions are intentionally different formats.

[07-fullscreen-wallpaper-layout-annotated.png](07-fullscreen-wallpaper-layout-annotated.png) is useful for the translucent Sched mark and wallpaper treatment, but its outgoing bubble, time divider, and top label are not part of the locked design.

## Recovered files

| File | Purpose |
| --- | --- |
| `01-messages-interaction-reference.png` | Apple Messages interaction and continuity reference. |
| `02-fullscreen-sparse-before.png` | Rejected sparse full-screen implementation. |
| `03-classic-macos-notification-reference.png` | Required native-notification proportions and app identity for corner/banner alerts. |
| `04-message-bubble-detail.png` | Bubble silhouette and tail detail. |
| `05-fullscreen-flat-before.png` | Rejected flat, empty full-screen implementation. |
| `06-macos-hello-wallpaper-reference.png` | Wallpaper-led, slow-arrival atmosphere reference. |
| `07-fullscreen-wallpaper-layout-annotated.png` | Wallpaper/3D-logo exploration with superseded top content. |
| `08-fullscreen-wallpaper-locked-target.png` | Current full-screen visual target, subject to the corrections above. |
| `09-sound-control-regression.png` | The sound popup plus detached preview button is the interaction regression to replace. |
| `10-calendar-interaction-reference.png` | Mature calendar navigation, spatial event editor, and hierarchy reference. |
| `11-sound-control-fixed-full.jpeg` | Live Plan editor after restoring the explicit blue Preview Sound action. |
| `12-sound-control-fixed-crop.jpeg` | Focused crop of the repaired sound interaction. |
| `13-sound-control-comparison.png` | Side-by-side evidence for the sound-control repair. |

## Earlier images already preserved elsewhere

The other user-supplied images from the recovered task were already copied into these audit folders before the connection failure:

- `docs/audit-2026-08-11/`: plan cutoff, wide-plan cutoff, old corner alert, bubble shapes, full-app reference, and banner/gesture references.
- `docs/audit-2026-08-11-corrective/`: bad corner alert, top-fade/wrapping problem, inspector contrast, timer clipping, and bubble target.

Those images remain evidence of problems or earlier directions. They do not override the locked full-screen target above.
