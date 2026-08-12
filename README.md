# Sched

> Don't you just hate Shortcuts? Apple AI bugging you? A simple, free, open-code (and technically yours to do literally anything with as long as you're not doing anything for a corp) app for powerful automated reminders.

Sched is a small macOS app for reminders that actually interrupt you.... why send away sad notifications when these are paw-swipe resistant 
<img width="987" height="732" alt="image" src="https://github.com/user-attachments/assets/c394b0d6-599d-4a87-b17b-244e48cbda10" />

*charming little ui, eh? :3*


## Why

Notifications are polite. Sched is not.

- Corner messages, edge banners, and full-screen conversations — three levels of “hey.”
- Corner and banner alerts are gesture-first: swipe toward the nearest screen edge to snooze, or press and hold to complete.
- Daily plans, one-shots, and quick timers.
- Optionally run a Shortcut, open a link, or quit an app when you dismiss.
- Watch apps that eat your day and nudge you when they’ve been open too long.
- Keeps running when the window is closed.

No subscription, account, analytics, or required cloud. The optional AI page can identify common provider keys/endpoints and export a small, portable context packet; reminders never depend on it.

## Optional AI convenience

- Detects standard environment variables for OpenAI, Anthropic, Gemini, OpenRouter, Groq, Mistral, xAI, DeepSeek, Together, Perplexity, Cohere, Azure OpenAI, and LM Studio.
- Recognizes Ollama and LM Studio endpoints, including their default local ports.
- Stores pasted keys in macOS Keychain, never in `schedule.json` or exported packets.
- Starts or stops local servers only when asked. Sched only terminates an Ollama process it started itself.
- Exports `README.md`, `request.md`, and `sched-context.json` for any model or backend.

## Permissions

- **Notifications** — optional; Sched’s own interactive alerts work without it.
- **Calendars** — requested only when you enable Calendar access or create an event.
- **Automation** — may appear when a reminder runs a Shortcut.

Idle detection and app limits use macOS session/workspace APIs and do not require Accessibility access.

## Compatibility

- macOS 14 or newer.
- Native AppKit controls, opaque message alerts, and interactive glass in the main utility window on supported macOS releases.
- No account, subscription, analytics, or cloud service.

## License

Free and open for personal use. Fork it, break it, make it yours — if you're a person, of course.
