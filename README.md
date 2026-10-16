# gnubg-apple

Lightweight native GNU Backgammon front end for Apple platforms.

The project targets:

- iOS and iPadOS
- macOS on Apple silicon

The game and analysis engine will be reused from GNU Backgammon, while the
user interface will be implemented independently with SwiftUI and native
Apple rendering APIs. The first release is offline-first and intentionally
small: 2D board, local play, hints, analysis, and game record storage.

## Repository relationship

This is an application repository, not a replacement for the upstream GNU
Backgammon source tree. The upstream engine will be pinned here as a separate
dependency so that engine updates and Apple UI changes remain reviewable
independently.

Suggested remotes for the engine checkout:

```text
upstream = git://git.git.savannah.gnu.org/gnubg.git
```

GNU Backgammon is GPLv3. Distribution of an application embedding or
modifying the engine must comply with that license.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for completed work, milestone acceptance criteria,
and the current target: a usable macOS app through milestone 5.

## Current status

The platform-neutral C boundary is defined in
[`native/include/gnubg_native.h`](native/include/gnubg_native.h). A first
single-handle adapter now starts the real engine, creates a match, and
returns immutable position snapshots. It also rolls, obtains a real GNUbg
hint, validates a move against GNUbg's legal move list, and applies it.
It can also return a synchronous normal evaluation through a C callback. The
next step is rollout analysis and cancellation/progress handling, followed by
extracting the upstream initialization so multiple app-owned handles are
possible.

Snapshots expose board arrays in fixed player identity order, matching scores.
The adapter validates complete moves before changing the live position and
reports forced passes as successful rolls. Only human turns can currently be
rolled through the API; computer turn execution is still pending.

One active handle is supported. Handles can be destroyed and recreated, but
engine evaluation resources are retained for the process lifetime because the
upstream shutdown path is not safe for repeated initialization.
