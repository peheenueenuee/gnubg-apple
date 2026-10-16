/*
 * Native application boundary for GNU Backgammon.
 *
 * This header intentionally contains no GTK, GLib, Python, or platform UI
 * types.  The macOS and iOS front ends will use the same ABI through a C
 * module imported by Swift.
 *
 * GNU Backgammon is GPLv3.  Any distributable application embedding this
 * interface must preserve the licensing obligations of the engine.
 */

#ifndef GNUBG_NATIVE_H
#define GNUBG_NATIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GNUBG_NATIVE_API_VERSION 2
#define GNUBG_NATIVE_ANALYSIS_OUTPUTS 7

enum {
    GNUBG_NATIVE_ANALYSIS_WIN = 0,
    GNUBG_NATIVE_ANALYSIS_WIN_GAMMON = 1,
    GNUBG_NATIVE_ANALYSIS_WIN_BACKGAMMON = 2,
    GNUBG_NATIVE_ANALYSIS_LOSE_GAMMON = 3,
    GNUBG_NATIVE_ANALYSIS_LOSE_BACKGAMMON = 4,
    GNUBG_NATIVE_ANALYSIS_EQUITY = 5,
    GNUBG_NATIVE_ANALYSIS_CUBEFUL_EQUITY = 6
};

typedef struct gnubg_native gnubg_native;

typedef enum {
    GNUBG_NATIVE_OK = 0,
    GNUBG_NATIVE_INVALID_ARGUMENT = 1,
    GNUBG_NATIVE_NOT_READY = 2,
    GNUBG_NATIVE_ILLEGAL_MOVE = 3,
    GNUBG_NATIVE_ENGINE_ERROR = 4,
    GNUBG_NATIVE_CANCELLED = 5
} gnubg_native_result;

typedef enum {
    GNUBG_NATIVE_STANDARD = 0,
    GNUBG_NATIVE_NACKGAMMON = 1,
    GNUBG_NATIVE_HYPERGAMMON_1 = 2,
    GNUBG_NATIVE_HYPERGAMMON_2 = 3,
    GNUBG_NATIVE_HYPERGAMMON_3 = 4
} gnubg_native_variation;

typedef enum {
    GNUBG_NATIVE_HUMAN = 0,
    GNUBG_NATIVE_COMPUTER = 1
} gnubg_native_player;

typedef struct {
    /* Player indices are fixed identities, shared with score and turn.
     * Each player uses their own coordinates: point 23 toward point 0.
     * The adapter maps the engine's rotating board to these identities. */
    uint8_t points[2][24];
    uint8_t bar[2];
    uint8_t borne_off[2];
    uint8_t dice[2];
    int8_t turn;
    int8_t cube_owner;
    uint16_t cube_value;
    uint8_t doubled;
    uint8_t game_over;
    uint32_t score[2];
    uint32_t match_length;
    uint8_t match_over;
    uint8_t crawford;
    uint8_t resignation;
    uint8_t can_double;
    int8_t board_player;
    uint8_t computer_turn;
    uint32_t game_number;
} gnubg_native_position;

typedef struct {
    /* Engine coordinates: points 0..23, bar 24, borne off -1. */
    int8_t from;
    int8_t to;
} gnubg_native_step;

typedef struct {
    uint8_t step_count;
    gnubg_native_step steps[4];
} gnubg_native_move;

typedef struct {
    /* 0 requests normal evaluation; 1..1000000 requests a fresh rollout. */
    uint32_t trials;
    uint8_t plies;
    uint8_t deterministic;
} gnubg_native_analysis_settings;

typedef struct {
    int8_t player;
    uint8_t plies;
    uint32_t trials;
    float standard_errors[GNUBG_NATIVE_ANALYSIS_OUTPUTS];
    /* Indexed by GNUBG_NATIVE_ANALYSIS_* constants above. */
    float outputs[GNUBG_NATIVE_ANALYSIS_OUTPUTS];
} gnubg_native_analysis;

typedef struct {
    void (*message)(void *context, const char *message);
    void (*progress)(void *context, uint32_t completed, uint32_t total);
    void (*analysis)(void *context, const gnubg_native_analysis *analysis);
    void *context;
} gnubg_native_callbacks;

/* All calls except cancel must use the same OS thread as the first create,
 * including later handle creation. A serial GCD queue alone is insufficient.
 * The returned handle owns the active engine view and is not thread-safe.
 * The current upstream integration permits one active handle per process.
 * Destroy releases the match; evaluation resources remain process-owned and
 * are reused by later handles. Callbacks must not reenter (except cancel) or destroy a handle. */
gnubg_native *gnubg_native_create(gnubg_native_variation variation,
                                   const gnubg_native_callbacks *callbacks);
void gnubg_native_destroy(gnubg_native *engine);

gnubg_native_result gnubg_native_start_match(gnubg_native *engine,
                                             uint32_t match_length,
                                             gnubg_native_player player0,
                                             gnubg_native_player player1);
/* OK also includes a forced pass. Rolling twice or on a computer turn
 * returns NOT_READY; use the COMPUTER_TURN action for computer players. */
gnubg_native_result gnubg_native_roll(gnubg_native *engine);
gnubg_native_result gnubg_native_play(gnubg_native *engine,
                                      const gnubg_native_move *move);
typedef enum {
    GNUBG_NATIVE_DOUBLE = 0,
    GNUBG_NATIVE_TAKE = 1,
    GNUBG_NATIVE_DROP = 2,
    GNUBG_NATIVE_ACCEPT_RESIGNATION = 3,
    GNUBG_NATIVE_REJECT_RESIGNATION = 4,
    GNUBG_NATIVE_NEXT_GAME = 5,
    GNUBG_NATIVE_COMPUTER_TURN = 6
} gnubg_native_action;

gnubg_native_result gnubg_native_act(gnubg_native *engine, gnubg_native_action action);
gnubg_native_result gnubg_native_resign(gnubg_native *engine, uint8_t points);
/* count receives the required capacity. NULL moves with capacity 0 queries it.
 * Move coordinates are relative to the player on roll (board_player). */
gnubg_native_result gnubg_native_legal_moves(gnubg_native *engine,
    gnubg_native_move *moves, uint32_t capacity, uint32_t *count);
gnubg_native_result gnubg_native_hint(gnubg_native *engine,
                                      gnubg_native_move *move);
gnubg_native_result gnubg_native_analyse(gnubg_native *engine,
                                         const gnubg_native_analysis_settings *settings);
/* Synchronous analysis. Callbacks run on the calling thread; progress is
 * throttled by GNUbg (roughly every two seconds) plus initial/final updates.
 * Cancelled work emits no analysis result; the return code is terminal status.
 * Only cancel may run concurrently or from callbacks. Keep the handle alive
 * until analyse returns. Idle cancellation is a no-op. */
void gnubg_native_cancel(gnubg_native *engine);
gnubg_native_result gnubg_native_snapshot(const gnubg_native *engine,
                                          gnubg_native_position *position);

const char *gnubg_native_result_string(gnubg_native_result result);
const char *gnubg_native_version(void);

#ifdef __cplusplus
}
#endif

#endif /* GNUBG_NATIVE_H */
