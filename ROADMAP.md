# GNUbg Apple roadmap

Updated: 2026-10-20

## Goal and working agreement

Build a lightweight, offline Apple-native GNU Backgammon application. Reuse
GNUbg for rules and analysis, keep the UI in SwiftUI, and expose the engine
through `native/include/gnubg_native.h`.

The current direction is to proceed locally through milestone 5: a usable
macOS application that can complete a match and run analysis. Continue routine
implementation, fixes, validation, and local commits without asking at each
milestone. The user handles pushes; do not push unless asked. Revisit scope
when a product decision or an external dependency blocks progress.

The user subsequently requested Japanese support in the future roadmap.
After asking to proceed, the current follow-on implementation is milestone 5.1. Put
localization immediately after the first macOS app; this roadmap update does
not by itself authorize implementing all later milestones.

## Milestones

| Milestone | Scope | Completion criteria | Status |
| --- | --- | --- | --- |
| 1. Engine integration | Pin GNUbg; build a GTK-free macOS arm64 engine; introduce the C boundary | Build and execute the real engine through the adapter | Complete |
| 2. Basic operation and safety | Match start, roll, hint, move, snapshot, normal evaluation; input validation and handle recreation | Existing smoke and regression checks pass | Complete; match coverage extended in milestone 4 |
| 3. Analysis | Rollout, progress, cancellation, failure reporting | Start analysis, observe progress, cancel, then successfully analyse again without changing the match | Complete |
| 4. Complete match lifecycle | Computer turns, cube offer/take/drop, resignation and response, next game and match end | A client can complete a match through the C API with correct scores and terminal states | Complete |
| 5. First usable macOS app | Swift integration, serialized engine execution, SwiftUI board and checker interaction, hints and analysis | Launch a native app, complete a local match, and run/cancel analysis while the UI stays responsive | User confirmed GUI launch and gameplay; remaining acceptance checks below |
| 5.1. Japanese localization | Japanese UI, consistent backgammon terms, localized status/errors and analysis labels; retain English | Follow the system language, with readable Japanese across match and analysis flows and English fallback | Implemented; language/model checks pass, visual text layout pending |
| 5.2. Interaction polish | Clearer move guidance, undoing staged selections, board orientation/labels, resizing and accessibility | Common and edge-case game actions are understandable and usable in both languages | Four passes implemented from user requests; latest step-switch/tray layout awaits visible feedback |
| 6. Records and usability | Save/load, history navigation, analysis presentation, preferences | Close and reopen a saved match and navigate its record | Later |
| 6.1. Analysis and opponent settings | Adjustable computer strength, evaluation depth, rollout options and clearer result explanations | Settings affect actual engine behavior; clients can understand the result perspective and accuracy/cost tradeoffs | Planned |
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
- On 2026-10-16, the user confirmed successful GUI launch and gameplay. This
  resolves the basic launch/play uncertainty. Specific edge cases, complete-match
  presentation and rollout cancellation/responsiveness in the visible UI have
  not yet been individually confirmed.
- Agent-side GUI automation remains unavailable: this execution environment
  aborts in `NSApplication` registration and LaunchServices reports -10827.
- Japanese and English localization is implemented with 97 resource keys.
  System-language selection, explicit Japanese/English, unsupported-language
  fallback and model smoke checks pass. This Mac selects Japanese by default.
  Localized visual wrapping and truncation remain to be checked in the GUI.
- The first interaction-polish pass implements all six current requests:
  graphical bar, opponent move highlights, prominent left/right dice, roll button
  above the dice, hover previews and alternating/selectable player colors.
  See `macos/INTERACTION.md` for per-request status and remaining visible checks.
- The 2026-10-20 follow-up fixes checker dimensions, overlaps/counts crowded
  stacks, overlays roll controls only when actionable, and shows other controls
  according to game/selection/analysis state. New-match preferences live in a
  popover instead of the permanent toolbar. Visual verification remains pending.
- The 2026-10-20 second follow-up adds the central cube/ownership indicator,
  non-overlapping five-checker stacks, staged dice usage and four dice for doubles,
  explicit match win/loss messages, and a consolidated status card. Japanese and
  English model tests cover dice assignment (including bearoff) and both outcomes.
  New visual layout and pointer behavior still await GUI feedback.
- The next follow-up replaces full-move lists and hover previews with individual
  legal step switches sharing the board selection and confirmation state, removes
  the bottom instruction area, and adds a right-edge borne-off storage tray.
  This follow-up is build-checked; new behavior and layout await user feedback.
- Validation logs are retained under `.build/logs/` after this implementation run.

## Remaining acceptance work for milestone 5

1. Basic GUI launch and gameplay: confirmed by the user on 2026-10-16.
2. Exercise click-based checker selection, bearing off, undo selection and move
   confirmation; check resizing, labels, disabled controls and keyboard actions.
3. Play a human/computer match to completion and verify cube, resignation,
   next-game and final-match presentation.
4. Run/cancel/restart a rollout while interacting with the window and confirm
   that the UI remains responsive. Fix issues revealed by these visible checks.

## User feedback workflow

The user writes requests freely in `要望.txt`, one request per line; no numbering
or template is required. Read it before interaction-polish work. The user wants
to shape that milestone collaboratively: make small, reviewable changes and
incorporate their feedback. Keep the user's original lines intact; record
implementation status separately rather than rewriting or deleting requests.

## Japanese localization scope and next priorities

Work in this order: finish the remaining milestone 5 checks alongside Japanese
localization, polish interactions, add records, expand analysis/opponent settings,
then move to iOS and distribution.

Japanese localization includes:

- Match controls, dialogs, board instructions, legal move descriptions, status,
  analysis progress/results and user-facing error messages.
- Consistent terminology: ヒント, キューブ, テイク, ドロップ, 投了, ギャモン,
  バックギャモン and ロールアウト. Keep terminology in one documented glossary.
- Move user-visible strings out of Swift source into localization resources;
  map C result codes to localized app messages rather than exposing raw English
  engine messages as the primary UI. Preserve diagnostic details in logs.
- Follow the macOS language preference by default; retain English resources and
  fallback. A per-app language picker can be added with later preferences work.
- Check dynamic numbers, interpolation, wrapping and truncation in both languages,
  including narrow windows, confirmations and long error/progress messages.

Save/load and history should precede deeper analysis work so users can preserve
and revisit useful positions. Distribution and iOS stay later because they need
additional dependency packaging and platform validation.

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
  pass, and basic GUI gameplay is user-confirmed; detailed UI checks and device
  validation remain outstanding.

Update this document as milestones are completed or scope changes.
