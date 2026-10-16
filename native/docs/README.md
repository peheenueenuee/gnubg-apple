# Native engine boundary

`native/include/gnubg_native.h` is the platform-neutral C ABI. It contains no
GTK, GLib or Swift types. The adapter currently includes upstream `gnubg.c` as
temporary integration glue; it is not yet an independently extracted core.

## Lifetime and threading

One active handle is allowed per process. Every operation, including later
handle creation, must run on the **same OS thread as the first create**.
GNUbg allocates thread-local move buffers during bootstrap; serial GCD queues
can switch OS threads and are insufficient. Wrong-thread calls are rejected.
The macOS app therefore owns a persistent dedicated `Thread` and job queue.

Destroy releases the match. Evaluation resources and GNUbg worker threads
remain process-owned and can be reused by the next handle on that OS thread.
Callbacks execute on the calling engine thread and may only reenter `cancel`.
Do not destroy the handle until the current operation returns.

`gnubg_native_cancel` is the sole operation permitted from another thread.
It interrupts active analysis; idle cancellation does nothing. The adapter
requires GNUbg to be built with multithreading enabled.

## Positions and matches

Snapshot arrays use fixed player identities, matching `score`. Each player's
points run from 23 toward 0, with bar 24 and borne-off destination -1 in moves.
`board_player` identifies the player on roll; `turn` can instead identify a
cube or resignation responder. `computer_turn` identifies a pending computer
action, and `can_double` includes cube ownership, Crawford and dead-cube rules.

The API supports match start, roll (including forced passes), legal move list
query/copy, full move validation/application, hints, explicit computer turns,
cube offer/take/drop, resignation offer/accept/reject, and next game.
Automatic computer turns and next games are owned by the client, so snapshots
remain visible at decision and game boundaries. Initial computer evaluations
use 0-ply; adjustable computer strength is deferred.

## Analysis

`trials == 0` requests normal evaluation; `1..1000000` requests a fresh rollout.
Settings apply to both players' rollout evaluations. Deterministic rollouts
use a fixed seed. Rollouts currently run full games, with GNUbg's variance
reduction and applicable bearoff database shortcuts.

Analysis is synchronous. Run it on the engine thread, never the UI thread.
Rollouts provide initial, periodic (approximately two-second) and final
progress callbacks. Successful analysis emits seven outputs and rollout
standard errors. Trial count is zero for normal evaluations.

The return code supplies terminal status: OK, CANCELLED or ENGINE_ERROR.
Cancelled work emits no final analysis callback or partial result. Worker
completion is awaited and interrupt state cleared before returning, so the
next analysis or match action can run safely. Analysis does not mutate the
match. Cube and resignation decisions must be resolved before analysis.

## Deferred work

Multiple independent handles, core-library extraction, iOS builds, saved
records and distribution packaging remain separate roadmap milestones.
The local build still links desktop libraries and audio frameworks, but
engine-owned sound is disabled during bootstrap.


## Completed turn presentation (API version 3)

`gnubg_native_last_turn` returns the most recent completed checker turn for a
specified player in the current game, including exact dice and canonical steps.
A forced pass has zero steps and still includes dice. Querying a player before
their first completed turn returns NOT_READY. Cube decisions and analysis do not
erase turn history; a new game or match starts with no completed turns.

The query uses the same fixed engine thread as snapshots. It reads the engine's
actual move records, so clients need not infer dice or moves from board changes.
