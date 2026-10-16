/* Internal fixtures deliberately share the adapter translation unit. */
#include "../engine/gnubg_native.c"
#include <assert.h>

static gnubg_native *
new_match(gnubg_native_variation variation)
{
    gnubg_native *engine = gnubg_native_create(variation, NULL);
    assert(engine);
    assert(!gnubg_native_create(variation, NULL));
    assert(gnubg_native_start_match(engine, 3, GNUBG_NATIVE_HUMAN,
                                   GNUBG_NATIVE_HUMAN) == GNUBG_NATIVE_OK);
    return engine;
}

static gpointer wrong_thread(gpointer engine)
{
    gnubg_native_position position;
    if (engine)
        assert(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_INVALID_ARGUMENT);
    assert(!gnubg_native_create(GNUBG_NATIVE_STANDARD, NULL));
    return NULL;
}

static unsigned int progress_calls, results;
static GThread *canceller;
static int cancel_enabled;
static gpointer cancel_worker(gpointer engine)
{
    g_usleep(100000);
    gnubg_native_cancel(engine);
    return NULL;
}
static void progress(void *engine, uint32_t completed, uint32_t total)
{
    assert(completed <= total);
    progress_calls++;
    if (cancel_enabled && !canceller)
        canceller = g_thread_new("cancel-test", cancel_worker, engine);
}
static void result_callback(void *context, const gnubg_native_analysis *result)
{
    (void) context;
    assert(result->outputs[0] >= 0 && result->outputs[0] <= 1);
    results++;
}

int
main(void)
{
    gnubg_native_position position;
    gnubg_native *engine;
    TanBoard original;
    gnubg_native_turn last_turn;
    int variant, player, point;

    assert(!gnubg_native_create((gnubg_native_variation) 99, NULL));
    for (variant = 0; variant <= GNUBG_NATIVE_HYPERGAMMON_3; variant++) {
        int expected = variant < 2 ? 15 : variant - 1;
        engine = new_match((gnubg_native_variation) variant);
        assert(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_OK);
        for (player = 0; player < 2; player++) {
            int total = position.bar[player] + position.borne_off[player];
            for (point = 0; point < 24; point++)
                total += position.points[player][point];
            assert(total == expected);
            assert(position.borne_off[player] == 0);
        }
        gnubg_native_destroy(engine);
    }

    engine = new_match(GNUBG_NATIVE_STANDARD);
    assert(gnubg_native_analyse(engine, &(gnubg_native_analysis_settings) {
        .plies = 0, .deterministic = 1
    }) == GNUBG_NATIVE_OK);
    assert(gnubg_native_start_match(engine, 3, (gnubg_native_player) 9,
                                   GNUBG_NATIVE_HUMAN) == GNUBG_NATIVE_INVALID_ARGUMENT);
    g_thread_join(g_thread_new("wrong-thread", wrong_thread, engine));
    /* Asymmetric board proves fixed identity mapping for either mover. */
    memset(ms.anBoard, 0, sizeof(ms.anBoard));
    ms.anBoard[1][5] = 1;
    ms.anBoard[0][10] = 2;
    for (player = 0; player < 2; player++) {
        ms.fMove = player;
        assert(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_OK);
        assert(position.points[player][5] == 1);
        assert(position.points[!player][10] == 2);
        assert(position.borne_off[player] == 14);
    }
    /* A legal prefix plus an invalid suffix must never become a legal move. */
    memset(ms.anBoard, 0, sizeof(ms.anBoard));
    ms.anBoard[1][0] = 1;
    ms.anBoard[0][23] = 15;
    ms.fMove = ms.fTurn = 0;
    ms.anDice[0] = 2;
    ms.anDice[1] = 1;
    memcpy(original, ms.anBoard, sizeof(original));
    assert(gnubg_native_play(engine, &(gnubg_native_move) {
        .step_count = 2, .steps = {{0, -1}, {5, 4}}
    }) == GNUBG_NATIVE_ILLEGAL_MOVE);
    assert(memcmp(original, ms.anBoard, sizeof(original)) == 0);
    assert(gnubg_native_roll(engine) == GNUBG_NATIVE_NOT_READY);
    gnubg_native_destroy(engine);

    engine = new_match(GNUBG_NATIVE_STANDARD);
    /* Block every entry point: any dice must produce a successful pass. */
    memset(ms.anBoard, 0, sizeof(ms.anBoard));
    ms.anBoard[1][24] = 15;
    for (point = 0; point < 6; point++)
        ms.anBoard[0][point] = 2;
    ms.anBoard[0][6] = 3;
    ms.fMove = ms.fTurn = 0;
    ms.anDice[0] = ms.anDice[1] = 0;
    assert(gnubg_native_roll(engine) == GNUBG_NATIVE_OK);
    assert(ms.fTurn == 1 && !ms.anDice[0]);
    assert(gnubg_native_last_turn(engine, 0, &last_turn) == GNUBG_NATIVE_OK);
    assert(last_turn.player == 0 && last_turn.move.step_count == 0);
    assert(last_turn.dice[0] >= 1 && last_turn.dice[0] <= 6);
    assert(gnubg_native_last_turn(engine, -1, &last_turn) == GNUBG_NATIVE_INVALID_ARGUMENT);
    ap[1].pt = PLAYER_GNU;
    assert(gnubg_native_roll(engine) == GNUBG_NATIVE_NOT_READY);
    gnubg_native_destroy(engine);
    engine = new_match(GNUBG_NATIVE_STANDARD);
    engine->callbacks.progress = progress;
    engine->callbacks.analysis = result_callback;
    engine->callbacks.context = engine;
    assert(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_OK);
    assert(gnubg_native_analyse(engine, &(gnubg_native_analysis_settings) {
        .trials = 4, .deterministic = 1
    }) == GNUBG_NATIVE_OK);
    assert(progress_calls >= 2 && results == 1);
    cancel_enabled = 1;
    assert(gnubg_native_analyse(engine, &(gnubg_native_analysis_settings) {
        .trials = 100000, .deterministic = 1
    }) == GNUBG_NATIVE_CANCELLED);
    assert(canceller);
    g_thread_join(canceller);
    assert(results == 1);
    gnubg_native_cancel(engine); /* idle cancellation must not poison work */
    assert(gnubg_native_analyse(engine, &(gnubg_native_analysis_settings) {
        .deterministic = 1
    }) == GNUBG_NATIVE_OK);
    assert(results == 2);
    gnubg_native_position after;
    assert(gnubg_native_snapshot(engine, &after) == GNUBG_NATIVE_OK);
    assert(memcmp(&position, &after, sizeof(position)) == 0);
    gnubg_native_destroy(engine);
    g_thread_join(g_thread_new("wrong-thread", wrong_thread, NULL));
    /* Whole matches through the public API, including next-game boundaries. */
    engine = new_match(GNUBG_NATIVE_STANDARD);
    for (int game = 0; game < 6; game++) {
        assert(gnubg_native_resign(engine, 1) == GNUBG_NATIVE_OK);
        assert(gnubg_native_act(engine, GNUBG_NATIVE_ACCEPT_RESIGNATION) == GNUBG_NATIVE_OK);
        assert(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_OK);
        assert(position.game_over);
        if (position.match_over) break;
        assert(gnubg_native_act(engine, GNUBG_NATIVE_NEXT_GAME) == GNUBG_NATIVE_OK);
        assert(gnubg_native_last_turn(engine, 0, &last_turn) == GNUBG_NATIVE_NOT_READY);
        assert(gnubg_native_last_turn(engine, 1, &last_turn) == GNUBG_NATIVE_NOT_READY);
    }
    assert(position.match_over);
    gnubg_native_destroy(engine);
    engine = new_match(GNUBG_NATIVE_STANDARD);
    assert(gnubg_native_resign(engine, 3) == GNUBG_NATIVE_OK);
    assert(gnubg_native_act(engine, GNUBG_NATIVE_REJECT_RESIGNATION) == GNUBG_NATIVE_OK);
    assert(!ms.fResigned);
    gnubg_native_destroy(engine);
    engine = new_match(GNUBG_NATIVE_STANDARD);
    gnubg_native_move choices[4096];
    uint32_t count;
    assert(gnubg_native_legal_moves(engine, choices, 4096, &count) == GNUBG_NATIVE_OK && count);
    int mover = ms.fMove;
    unsigned int dice0 = ms.anDice[0], dice1 = ms.anDice[1];
    assert(gnubg_native_play(engine, &choices[0]) == GNUBG_NATIVE_OK);
    assert(gnubg_native_last_turn(engine, mover, &last_turn) == GNUBG_NATIVE_OK);
    assert(last_turn.player == mover && last_turn.dice[0] == dice0 && last_turn.dice[1] == dice1);
    assert(last_turn.move.step_count == choices[0].step_count);
    assert(memcmp(last_turn.move.steps, choices[0].steps, sizeof(choices[0].steps)) == 0);
    assert(gnubg_native_act(engine, GNUBG_NATIVE_DOUBLE) == GNUBG_NATIVE_OK);
    /* A pending cube response must not erase checker history. */
    assert(gnubg_native_last_turn(engine, mover, &last_turn) == GNUBG_NATIVE_OK);
    int taker = ms.fTurn;
    assert(gnubg_native_act(engine, GNUBG_NATIVE_TAKE) == GNUBG_NATIVE_OK);
    assert(ms.nCube == 2 && ms.fCubeOwner == taker && !ms.fDoubled);
    gnubg_native_destroy(engine);
    engine = new_match(GNUBG_NATIVE_STANDARD);
    assert(gnubg_native_legal_moves(engine, choices, 4096, &count) == GNUBG_NATIVE_OK && count);
    assert(gnubg_native_play(engine, &choices[0]) == GNUBG_NATIVE_OK);
    assert(gnubg_native_act(engine, GNUBG_NATIVE_DOUBLE) == GNUBG_NATIVE_OK);
    assert(gnubg_native_act(engine, GNUBG_NATIVE_DROP) == GNUBG_NATIVE_OK);
    assert(ms.gs != GAME_PLAYING && ms.anScore[0] + ms.anScore[1] == 1);
    assert(gnubg_native_act(engine, GNUBG_NATIVE_NEXT_GAME) == GNUBG_NATIVE_OK);
    assert(gnubg_native_last_turn(engine, 0, &last_turn) == GNUBG_NATIVE_NOT_READY);
    assert(gnubg_native_last_turn(engine, 1, &last_turn) == GNUBG_NATIVE_NOT_READY);
    gnubg_native_destroy(engine);
    engine = gnubg_native_create(GNUBG_NATIVE_STANDARD, NULL);
    assert(gnubg_native_last_turn(engine, 0, &last_turn) == GNUBG_NATIVE_NOT_READY);
    assert(gnubg_native_start_match(engine, 1, GNUBG_NATIVE_COMPUTER,
                                   GNUBG_NATIVE_COMPUTER) == GNUBG_NATIVE_OK);
    int turns = 0;
    do {
        assert(gnubg_native_act(engine, GNUBG_NATIVE_COMPUTER_TURN) == GNUBG_NATIVE_OK);
        assert(gnubg_native_snapshot(engine, &position) == GNUBG_NATIVE_OK);
        assert(++turns < 2000);
    } while (!position.match_over);
    assert(position.game_over && (position.score[0] >= 1 || position.score[1] >= 1));
    assert(gnubg_native_act(engine, GNUBG_NATIVE_NEXT_GAME) == GNUBG_NATIVE_NOT_READY);
    gnubg_native_destroy(engine);
    puts("match: cube take/drop, resignation responses, next game, computer full match OK");
    puts("rollout: progress, cross-thread cancellation, recovery, unchanged match OK");
    puts("native regression: lifecycle, variants, identities, illegal move, forced pass OK");
    return 0;
}
