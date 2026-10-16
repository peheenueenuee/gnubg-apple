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
| 2. Basic operation and safety | Match start, roll, hint, move, snapshot, normal evaluation; input validation and handle recreation | Existing smoke and regression checks pass | Complete for the current API; full match coverage remains in milestone 4 |
| 3. Analysis | Rollout, progress, cancellation, failure reporting | Start analysis, observe progress, cancel, then successfully analyse again without changing the match | Next |
| 4. Complete match lifecycle | Computer turns, cube offer/take/drop, resignation and response, next game and match end | A client can complete a match through the C API with correct scores and terminal states | Planned |
| 5. First usable macOS app | Swift integration, serialized engine execution, SwiftUI board and checker interaction, hints and analysis | Launch a native app, complete a local match, and run/cancel analysis while the UI stays responsive | Planned; current delivery target |
| 6. Records and usability | Save/load, history navigation, analysis presentation, preferences | Close and reopen a saved match and navigate its record | Later |
| 7. iPhone and iPad | iOS engine build and bundled resources, touch input and adaptive layout | Run the same rules and analysis on physical iOS/iPadOS devices | Later |
| 8. Distribution | Size and performance work, signing, distribution and license review | Another user can install and run the application with the required resources | Later |

## Current baseline

- Latest implementation commit: `0e7f5ab` (`Harden native move validation and handle lifecycle`).
- GNUbg submodule: `0143cad3c8f7826f4cd33c6627c9c5485bf1b0ae`.
- Verified on macOS arm64 with `native/scripts/build-native-smoke-macos.sh`.
- Smoke coverage: match start, opening dice, hint, legal move, snapshot and
  synchronous normal evaluation.
- Regression coverage: exclusive handle ownership, destruction/recreation,
  evaluation after recreation, all five checker-count variants, fixed player
  identity mapping, rejection of an invalid move suffix, forced pass, repeated
  roll and computer-roll preconditions, and invalid enum inputs.
- Snapshot board arrays use fixed player identities, matching scores; each
  player's point coordinates run from 23 toward 0.
- Evaluation resources and worker infrastructure remain alive for the process
  lifetime. Destroying a handle releases its match, allowing a new handle.
- Computer turn execution, cube/resignation actions and rollout are not yet
  public API operations. There is no Swift or Xcode target yet.

## Implementation order through milestone 5

1. Define analysis completion/cancellation semantics and callback threading.
   Connect GNUbg rollout with progress; test cancellation and recovery.
2. Complete match actions with explicit readiness checks and snapshots that
   expose pending decisions, game results and match completion. Exercise
   computer turns and whole matches, including forced passes and game changes.
3. Add a macOS Swift build target and package engine resources. Serialize all
   engine work on a dedicated execution queue; publish UI state on the main
   thread. Cancellation must remain possible while analysis occupies the queue.
4. Add the board and legal checker interaction, then match controls, hints,
   analysis progress/results and cancellation. Validate the launched app.

## Design constraints and deferred work

- Keep one active engine handle and serialize access. Callbacks must not
  reenter or destroy the handle. Define a separate safe cancellation path
  before introducing background analysis.
- Multiple handles and parallel independent analyses are deferred until a
  real need justifies separating GNUbg's process-global state.
- Retain the existing upstream source boundary. The current inclusion of
  `gnubg.c` is temporary adapter glue, not the final reusable core library.
- The current native smoke executable still links desktop dependencies,
  including audio frameworks. A GTK-free build does not establish that the
  engine is ready for iOS or is free of engine-owned audio paths.
- This Mac currently has Command Line Tools and Swift, but no Xcode app under
  `/Applications`. Recheck tooling before choosing app packaging or device
  validation steps.
- Automated checks establish the cases they cover; the current smoke does
  not prove complete match or UI correctness.

Update this document as milestones are completed or scope changes.
