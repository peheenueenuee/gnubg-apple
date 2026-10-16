# GNUbg Apple roadmap

Updated: 2026-10-16

## Goal and working agreement

Build a lightweight, offline Apple-native GNU Backgammon application. Reuse
GNUbg for rules and analysis, keep the UI in SwiftUI, and expose the engine
through `native/include/gnubg_native.h`.

The current direction is to proceed locally through milestone 5: a usable
macOS application that can complete a match and run analysis. Continue routine
implementation, fixes, validation, and local commits without asking at each
milestone. The user handles pushes; do not push unless asked. Revisit scope
when a product decision or an external dependency blocks progress.

## Milestones

| Milestone | Scope | Completion criteria | Status |
| --- | --- | --- | --- |
| 1. Engine integration | Pin GNUbg; build a GTK-free macOS arm64 engine; introduce the C boundary | Build and execute the real engine through the adapter | Complete |
| 2. Basic operation and safety | Match start, roll, hint, move, snapshot, normal evaluation; input validation and handle recreation | Existing smoke and regression checks pass | Complete; match coverage extended in milestone 4 |
| 3. Analysis | Rollout, progress, cancellation, failure reporting | Start analysis, observe progress, cancel, then successfully analyse again without changing the match | Complete |
| 4. Complete match lifecycle | Computer turns, cube offer/take/drop, resignation and response, next game and match end | A client can complete a match through the C API with correct scores and terminal states | Complete |
| 5. First usable macOS app | Swift integration, serialized engine execution, SwiftUI board and checker interaction, hints and analysis | Launch a native app, complete a local match, and run/cancel analysis while the UI stays responsive | Implemented; GUI launch and visual/interaction checks pending |
| 6. Records and usability | Save/load, history navigation, analysis presentation, preferences | Close and reopen a saved match and navigate its record | Later |
| 7. iPhone and iPad | iOS engine build and bundled resources, touch input and adaptive layout | Run the same rules and analysis on physical iOS/iPadOS devices | Later |
| 8. Distribution | Size and performance work, signing, distribution and license review | Another user can install and run the application with the required resources | Later |

## Current baseline

- Native milestones 3 and 4: `694386b` (`Add cancellable rollout analysis and complete native match actions`).
- GNUbg submodule: `0143cad3c8f7826f4cd33c6627c9c5485bf1b0ae`.
- `native/scripts/build-native-smoke-macos.sh` passes, including rollout progress,
  cross-thread cancellation, recovery, unchanged match state, cube take/drop,
  resignation responses, next games and a computer match through completion.
- Wrong-thread operations and later creation on another OS thread are rejected.
- The macOS app builds with `native/scripts/build-macos-app.sh`; output is
  `.build/macos/GNUbg Apple.app`. Current local target: Apple silicon/macOS 15+.
- Swift's bundled-engine `--smoke` completes a computer match. `--model-smoke`
  covers checker selection/application, evaluation/rollout, cancellation and
  recovery, and a match completed via resignation using the UI's observable model.
- SwiftUI provides a board, move confirmation, legal-move list, match controls,
  local human/computer play, hints and analysis. Computer responses are scheduled
  by the UI after each engine snapshot.
- GUI verification is still pending: this execution environment aborts in
  `NSApplication` registration, and LaunchServices reports -10827. A successful
  build/model test does not verify rendered layout, mouse input or keyboard input.
- Validation logs are retained under `.build/logs/` after this implementation run.

## Remaining acceptance work for milestone 5

1. Launch the `.app` in a normal GUI session and inspect its board and controls.
2. Exercise click-based checker selection, bearing off, undo selection and move
   confirmation; check resizing, labels, disabled controls and keyboard actions.
3. Play a human/computer match to completion and verify cube, resignation,
   next-game and final-match presentation.
4. Run/cancel/restart a rollout while interacting with the window and confirm
   that the UI remains responsive. Fix issues revealed by these visible checks.

## Design constraints and deferred work

- Keep one active engine handle on a fixed dedicated OS thread. A serial GCD
  queue is insufficient because GNUbg uses thread-local buffers. Only cancellation
  may run concurrently or reenter from callbacks; the handle must remain alive.
- Multiple handles and parallel independent analyses are deferred until a
  real need justifies separating GNUbg's process-global state.
- Retain the existing upstream source boundary. The current inclusion of
  `gnubg.c` is temporary adapter glue, not the final reusable core library.
- The local build still links Homebrew desktop dependencies and audio frameworks.
  Engine sound is explicitly disabled, but this is not yet an iOS-ready or
  self-contained distribution build.
- This Mac has Command Line Tools and Swift, with no Xcode app under
  `/Applications`. The local app uses a script-driven Swift target and ad hoc
  signing; a build-local VFS overlay handles duplicate CLT SwiftBridging maps.
- Automated checks establish the cases they cover; complete match regressions
  pass, while visible UI checks and device validation remain outstanding.

Update this document as milestones are completed or scope changes.
