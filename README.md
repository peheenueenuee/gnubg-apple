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

操作や機能の要望は [要望.txt](要望.txt) に1要望1行で追記できます。
対応状況は [操作改善の記録](macos/INTERACTION.md) を参照してください。

## Run the macOS app

```sh
native/scripts/build-macos-app.sh
open ".build/macos/GNUbg Apple.app"
```

Local development build for Apple silicon and macOS 15+. It uses the current
Homebrew libraries; distribution packaging is deferred. See
[native/docs/build-macos.md](native/docs/build-macos.md) for setup and checks.

The UI follows the macOS language preference and supports Japanese and English.
Quit and reopen the app after rebuilding to load the updated language resources.
See [localization notes and terminology](macos/LOCALIZATION.md).

## Current status

The C boundary supports match play, legal move queries, hints, normal evaluation,
rollout progress and cancellation, computer turns, cube decisions, resignations
and next games. Match state and callbacks are exposed through
[`native/include/gnubg_native.h`](native/include/gnubg_native.h).

The SwiftUI app adds a board with checker selection and move confirmation,
a legal-move list, local human/computer opponents, match controls and analysis.
The board includes a graphical bar, opponent-move highlights, dice on each
player's side, legal-move hover previews and alternating/selectable player colors.
The engine runs on one dedicated OS thread; cancellation can come from the UI.
One active handle is supported, with process-owned evaluation resources.

C regressions, Swift bundled-engine match execution and UI model tests pass.
The user confirmed GUI launch and gameplay for the first app. New interaction
changes pass model checks; their rendered layout and mouse/keyboard behavior
still need visible verification because the agent environment cannot register
GUI applications.
