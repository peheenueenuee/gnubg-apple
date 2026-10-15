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

## Current status

The platform-neutral C boundary is defined in
[`native/include/gnubg_native.h`](native/include/gnubg_native.h). The next
step is implementing its adapter around the existing engine, followed by a
GTK-free arm64 macOS smoke test.
