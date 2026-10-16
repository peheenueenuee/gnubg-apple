# GTK-free engine smoke test on Apple silicon

The pinned upstream tree can be configured without GTK, Python, SQLite, and
the 3D board with the repository build script:

```sh
native/scripts/build-engine-macos.sh
```

Use `GNUBG_BUILD_JOBS=4` to limit parallelism. The script checks that the
result is an arm64 Mach-O executable and runs `gnubg --version`.

The first native C boundary can be linked and exercised with:

```sh
native/scripts/build-native-smoke-macos.sh
```

This currently validates one real engine handle, starting a one-point match,
rolling, obtaining a hint, applying that legal move, running a normal
evaluation callback, and taking a position snapshot. It is intentionally a
single-handle smoke test while upstream's process-global initialization is
being separated.

The current upstream checkout requires GNU Bison 3.x to regenerate
`sgf_y.c` and `external_y.c`. The macOS Command Line Tools provide an older
Bison, so a clean checkout must either use a newer Bison in `PATH` or use the
versioned generated parser sources supplied by the engine build environment.
Do not treat a successful `make` as sufficient: the arm64 executable must also
pass `./gnubg --version`.

The script also runs internal regression fixtures for handle recreation, all
five variation checker counts, fixed player identities, rejection of a legal
move prefix followed by an invalid step, forced passes, and roll preconditions.
These fixtures use engine internals without exposing test hooks in the C ABI.

## SwiftUI macOS application

Build the local Apple silicon app with Command Line Tools and Swift:

```sh
native/scripts/build-macos-app.sh
open ".build/macos/GNUbg Apple.app"
```

The current build targets macOS 15 and later, matching the engine objects on
this development machine. It embeds neural-network weights, bearoff databases
and the match equity table. Homebrew dynamic libraries remain external: this
is a local development app, not a portable distribution bundle. The script
applies an ad hoc signature. No Xcode project or Swift Package is required.

If an older `swift/module.modulemap` remains beside `bridging.modulemap` in the
selected Command Line Tools, `prepare-swift-overlay.py` creates a build-local
VFS overlay to hide the duplicate SwiftBridging definition. Installed toolchain
files are never edited. The overlay is empty on unaffected installations.

Additional validation modes:

```sh
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --smoke
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --model-smoke
".build/macos/GNUbg Apple.app/Contents/MacOS/GNUbgApple" --ui-smoke
```

`--smoke` completes a computer match through Swift using bundled resources.
`--model-smoke` exercises checker selection and application, evaluation,
rollout, cross-thread cancellation and recovery, and resignation through match
completion, using the same observable model as the UI. Both passed locally.

`--ui-smoke` additionally opens a window and writes `/tmp/gnubg-apple-preview.png`
(or `GNUBG_PREVIEW_PATH`). It requires a working GUI session. The current agent
execution environment aborts during `NSApplication` registration; LaunchServices
also returns -10827. Compilation and model tests do not establish visual layout
or actual mouse/keyboard behavior. Those checks remain pending.
