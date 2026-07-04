# TooDue for iOS

A native SwiftUI client for [TooDue](https://github.com/djedi/toodue), the fast,
self-hostable Todoist alternative. Stays close to the PWA's design — same
terracotta brand color, P1–P4 priorities, Inbox / Today / Upcoming / Projects
layout — but with a fully native iOS look and feel.

## Features

- **Hosted by default, self-hosted by choice** — signs into `app.toodue.com` out
  of the box; self-hosters tap the small "Logging in on:" link on the login
  screen (Bitwarden-style) to point the app at their own server, including
  plain-HTTP LAN addresses
- **Offline-first** — every change is applied locally and queued; the queue
  replays automatically when you're back online. Offline edits to the same task
  coalesce, and deleting a never-synced task cancels its queued creation entirely
- **Real-time** — subscribes to the server's SSE stream, so changes from the web
  app (or a housemate on a shared project) appear instantly
- **Full task model** — name, description, date + time, deadline, P1–P4 priority,
  project, sub-tasks, comments
- **Nested projects** with colors, shared-project indicators, active counts
- **Native niceties** — swipe to complete/delete, pull-to-refresh, sheets,
  haptic-friendly circular priority checkboxes, light/dark/system theme
- **Calendar feed** — copy your private iCal URL from Settings

## Requirements

- Xcode 16+ (developed against Xcode 26)
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`make bootstrap` installs it)

## Getting started

```sh
make bootstrap   # one-time: install xcodegen + xcbeautify
make run         # build and launch in the simulator
make test        # run the unit tests
make help        # everything else
```

`make open` generates and opens the Xcode project. The `.xcodeproj` is generated
from `project.yml` and not checked in — edit `project.yml`, not the project.

To run against a local backend: `make server` (starts the TooDue backend from a
sibling `../toodue` checkout via Docker), then tap "Logging in on:" at the
bottom of the login screen and enter `http://localhost:8080`.

## Architecture

```
TooDue/
  Models/       Codable structs matching the server's JSON wire format
  Networking/   APIClient (REST, cookie-session auth), SSEClient, PATCH payloads
  Storage/      LocalStore (JSON snapshot on disk), Mutation queue + compaction,
                SyncLogic (pure state transforms — fully unit-tested)
  State/        AppState — observable orchestrator: optimistic writes, queue
                replay with temp-id remapping, SSE handling, connectivity
  Views/        SwiftUI screens
TooDueTests/    Swift Testing suites for wire format, queue logic, overlay merge
```

### How offline sync works

1. Every write is applied to local state immediately and appended to a
   persistent mutation queue (`snapshot.json` in Application Support).
2. Tasks/projects created offline get **negative temp ids**; when their create
   replays, every queued mutation referencing the temp id is remapped to the
   server-assigned id.
3. On reconnect (NWPathMonitor): replay queue in order → refetch everything →
   overlay still-pending mutations on top → reconnect SSE.
4. Server 4xx rejections drop the mutation and surface the error in Settings;
   network failures leave the queue intact for the next attempt.

Auth is the server's `toodue_session` cookie, which URLSession stores and
persists automatically.

## License

Same spirit as the TooDue server — self-host and enjoy.
