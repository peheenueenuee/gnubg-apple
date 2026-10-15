# Native front end

This directory is the platform-neutral boundary for the lightweight native
application planned for GNU Backgammon.

## Targets

- macOS arm64: SwiftUI desktop application
- iOS arm64: SwiftUI application
- GNU Backgammon engine: C, built as a static library for each target

The UI must not include GTK headers or call GTK functions.  It talks to the
engine only through `native/include/gnubg_native.h`, receives immutable
position snapshots, and renders the board itself.  A single-threaded engine
handle keeps the first version simple; analysis can later run on a worker
queue and publish snapshots back to the UI thread.

## Deliberate first-version exclusions

The native front end initially excludes GTK, the 3D board, Python, SQLite,
and engine-owned audio.  Those are desktop concerns or platform adapters,
and keeping them out of the core is what makes the arm64 macOS/iOS build
small and deterministic.

The existing GTK application remains the reference desktop application while
the native boundary is implemented incrementally.  No existing generated
Autotools files should be regenerated as part of this work.

## Implementation order

1. Separate the upstream process-oriented initialization from the reusable
   engine state, then add an adapter that owns it behind `gnubg_native`.
2. Move board updates and user-visible messages to callbacks/snapshots.
3. Build a C smoke test without GTK.
4. Add a Swift Package/Xcode target for macOS arm64.
5. Add the iOS SwiftUI board and touch interaction using the same C target.

The ABI is intentionally C-compatible so Swift can import it directly and
so the macOS and iOS targets cannot accidentally grow different game rules.

The first adapter keeps the existing engine state process-wide and therefore
allows one active handle at a time. Match start, dice rolling, immutable
snapshots, hint generation, and legal move application are wired through to
the real engine. Move coordinates use GNUbg's engine points directly: `0..23`
for points, `24` for the bar, and `-1` for borne off. Analysis remains
explicitly `GNUBG_NATIVE_NOT_READY` until its callback contract is
implemented. This limitation is deliberate while the upstream initialization
lifecycle is being extracted.
