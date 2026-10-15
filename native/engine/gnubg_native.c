/*
 * First native engine adapter.
 *
 * GNU Backgammon's current upstream entry point owns the engine state in
 * process-wide globals.  Until that is refactored upstream, this translation
 * unit deliberately exposes one active handle only.  It gives the Apple
 * front end a real lifecycle and snapshot boundary without pretending that
 * the old global state is already re-entrant.
 */

#include "../include/gnubg_native.h"

/* Keep the upstream CLI entry point out of the native target.  Including the
 * source here is temporary integration glue; the eventual target will use a
 * small upstream core library after initialization is extracted there. */
#ifndef LOCALEDIR
#define LOCALEDIR "."
#endif
#define main gnubg_cli_main
#include "../../Vendor/gnubg/gnubg.c"
#undef main

#include <string.h>

struct gnubg_native {
    gnubg_native_callbacks callbacks;
};

static gnubg_native *active_engine;
static int engine_initialized;

typedef struct {
    gnubg_native_move *move;
    int found;
} native_hint_context;

static int
native_hint_record(procrecorddata *record)
{
    native_hint_context *context = record->pvUserData;
    movelist *moves = record->avOutputData[PROCREC_HINT_ARGOUT_MOVELIST];
    int index = (int) (ptrdiff_t) record->avOutputData[PROCREC_HINT_ARGOUT_INDEX];
    int step;

    if (!context || !moves || index < 0 || (unsigned int) index >= moves->cMoves)
        return FALSE;

    context->move->step_count = 0;
    for (step = 0; step < 4 && moves->amMoves[index].anMove[step * 2] >= 0; step++) {
        context->move->steps[step].from = (int8_t) moves->amMoves[index].anMove[step * 2];
        context->move->steps[step].to = (int8_t) moves->amMoves[index].anMove[step * 2 + 1];
        context->move->step_count++;
    }
    context->found = context->move->step_count > 0;
    return FALSE;
}

static int
native_checkers(bgvariation variation)
{
    switch (variation) {
    case VARIATION_HYPERGAMMON_1:
        return 1;
    case VARIATION_HYPERGAMMON_2:
        return 2;
    case VARIATION_HYPERGAMMON_3:
        return 3;
    default:
        return 15;
    }
}

static void
native_message(const gnubg_native *engine, const char *message)
{
    if (engine && engine->callbacks.message)
        engine->callbacks.message(engine->callbacks.context, message);
}

static gnubg_native_result
native_bootstrap(const gnubg_native *engine)
{
    char *met;

    if (engine_initialized)
        return GNUBG_NATIVE_OK;

    default_import_folder = g_strdup(".");
    default_export_folder = g_strdup(".");
    default_sgf_folder = g_strdup(".");

    output_initialize();
    init_defaults();
    DefaultDBSettings();

    /* Desktop builds use the Autotools data directory. Apple targets pass
     * their app bundle or resource directory explicitly. */
    {
        const gchar *data_dir = g_getenv("GNUBG_NATIVE_DATA_DIR");
        if (data_dir && *data_dir)
            pkg_datadir = g_strdup(data_dir);
    }

    /* The Apple UI owns rendering, progress, preferences, and sound. */
    fInteractive = FALSE;
    fShowProgress = FALSE;
    fDisplay = FALSE;
    fQuiet = TRUE;
    fAutoMove = FALSE;
    fAutoRoll = FALSE;
    fAutoBearoff = FALSE;
    fAutoGame = FALSE;

    init_rng();

    met = BuildFilename2("met", "Kazaross-XG2.xml");
    if (!g_file_test(met, G_FILE_TEST_EXISTS)) {
        g_free(met);
        native_message(engine, "GNU Backgammon match equity table is missing");
        return GNUBG_NATIVE_ENGINE_ERROR;
    }
    InitMatchEquity(met);
    g_free(met);

    init_nets(FALSE);
    MT_InitThreads();
#if defined(USE_MULTITHREAD)
    MT_StartThreads();
#endif
    SetExitSoundOff();

    engine_initialized = TRUE;
    return GNUBG_NATIVE_OK;
}

static void
native_snapshot_position(gnubg_native_position *position)
{
    int player;
    int point;

    memset(position, 0, sizeof(*position));
    for (player = 0; player < 2; player++) {
        /* Board side 1 belongs to fMove, even during cube decisions. */
        int side = ms.fMove < 0 ? player : (player == ms.fMove ? 1 : 0);
        unsigned int occupied = ms.anBoard[side][24];

        position->bar[player] = (uint8_t) occupied;
        for (point = 0; point < 24; point++) {
            position->points[player][point] = (uint8_t) ms.anBoard[side][point];
            occupied += ms.anBoard[side][point];
        }
        position->borne_off[player] = (uint8_t) MAX(0, native_checkers(ms.bgv) - (int) occupied);
        position->score[player] = (uint32_t) MAX(0, ms.anScore[player]);
    }

    position->dice[0] = (uint8_t) ms.anDice[0];
    position->dice[1] = (uint8_t) ms.anDice[1];
    position->turn = (int8_t) ms.fTurn;
    position->cube_owner = (int8_t) ms.fCubeOwner;
    position->cube_value = (uint16_t) ms.nCube;
    position->doubled = (uint8_t) ms.fDoubled;
    position->game_over = (uint8_t) (ms.gs != GAME_PLAYING);
    position->match_length = (uint32_t) MAX(0, ms.nMatchTo);
}

gnubg_native *
gnubg_native_create(gnubg_native_variation variation,
                    const gnubg_native_callbacks *callbacks)
{
    gnubg_native *engine;

    if (active_engine || variation < GNUBG_NATIVE_STANDARD ||
        variation > GNUBG_NATIVE_HYPERGAMMON_3)
        return NULL;

    engine = g_new0(gnubg_native, 1);
    if (callbacks)
        engine->callbacks = *callbacks;

    bgvDefault = (bgvariation) variation;
    if (native_bootstrap(engine) != GNUBG_NATIVE_OK) {
        g_free(engine);
        return NULL;
    }

    active_engine = engine;
    return engine;
}

void
gnubg_native_destroy(gnubg_native *engine)
{
    if (!engine || engine != active_engine)
        return;

    /* Upstream Shutdown is terminal: bearoff globals retain freed pointers.
     * Keep evaluation resources alive for the process and release only the
     * match here, so subsequent handles can safely reuse initialization. */
    FreeMatch();
    ClearMatch();
    ms.gs = GAME_NONE;
    ms.fMove = ms.fTurn = -1;
    ms.anDice[0] = ms.anDice[1] = 0;
    active_engine = NULL;
    g_free(engine);
}

gnubg_native_result
gnubg_native_start_match(gnubg_native *engine,
                         uint32_t match_length,
                         gnubg_native_player player0,
                         gnubg_native_player player1)
{
    char length[32];

    if (!engine || engine != active_engine)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if ((player0 != GNUBG_NATIVE_HUMAN && player0 != GNUBG_NATIVE_COMPUTER) ||
        (player1 != GNUBG_NATIVE_HUMAN && player1 != GNUBG_NATIVE_COMPUTER) ||
        !match_length || match_length > MAXSCORE)
        return GNUBG_NATIVE_INVALID_ARGUMENT;

    ap[0].pt = player0 == GNUBG_NATIVE_COMPUTER ? PLAYER_GNU : PLAYER_HUMAN;
    ap[1].pt = player1 == GNUBG_NATIVE_COMPUTER ? PLAYER_GNU : PLAYER_HUMAN;
    snprintf(length, sizeof(length), "%u", match_length);
    outputoff();
    CommandNewMatch(length);
    outputon();
    return ms.gs == GAME_PLAYING ? GNUBG_NATIVE_OK : GNUBG_NATIVE_ENGINE_ERROR;
}

gnubg_native_result
gnubg_native_roll(gnubg_native *engine)
{
    int previous_turn;

    if (!engine || engine != active_engine)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING)
        return GNUBG_NATIVE_NOT_READY;

    if (ms.anDice[0] || ms.fDoubled || ms.fResigned ||
        ap[ms.fTurn].pt != PLAYER_HUMAN)
        return GNUBG_NATIVE_NOT_READY;

    previous_turn = ms.fTurn;
    outputoff();
    CommandRoll(NULL);
    outputon();
    return ms.anDice[0] || ms.fTurn != previous_turn || ms.gs != GAME_PLAYING
        ? GNUBG_NATIVE_OK : GNUBG_NATIVE_ENGINE_ERROR;
}

gnubg_native_result
gnubg_native_play(gnubg_native *engine, const gnubg_native_move *move)
{
    TanBoard next_board;
    movelist legal_moves;
    int engine_move[8];
    int step;
    char formatted[FORMATEDMOVESIZE];

    if (!engine || engine != active_engine)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (!move || move->step_count == 0 || move->step_count > 4)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING || !ms.anDice[0])
        return GNUBG_NATIVE_NOT_READY;

    for (step = 0; step < 8; step++)
        engine_move[step] = -1;
    for (step = 0; step < move->step_count; step++) {
        int from = move->steps[step].from;
        int to = move->steps[step].to;
        if (from < 0 || from > 24 || to < -1 || to > 23 || from == to)
            return GNUBG_NATIVE_INVALID_ARGUMENT;
        engine_move[step * 2] = from;
        engine_move[step * 2 + 1] = to;
    }

    memcpy(next_board, ms.anBoard, sizeof(next_board));
    if (ApplyMove(next_board, engine_move, FALSE) < 0)
        return GNUBG_NATIVE_ILLEGAL_MOVE;
    GenerateMoves(&legal_moves, msBoard(), ms.anDice[0], ms.anDice[1], FALSE);
    if (!board_in_list(&legal_moves, ms.anBoard, (ConstTanBoard) next_board, engine_move))
        return GNUBG_NATIVE_ILLEGAL_MOVE;

    FormatMove(formatted, ms.anBoard, engine_move);
    outputoff();
    CommandMove(formatted);
    outputon();
    return ms.anDice[0] ? GNUBG_NATIVE_ENGINE_ERROR : GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_hint(gnubg_native *engine, gnubg_native_move *move)
{
    native_hint_context context;
    procrecorddata record;
    char max_moves[] = "1";

    if (!engine || engine != active_engine)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (!move)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING || !ms.anDice[0])
        return GNUBG_NATIVE_NOT_READY;

    memset(move, 0, sizeof(*move));
    memset(&context, 0, sizeof(context));
    memset(&record, 0, sizeof(record));
    context.move = move;
    record.pfProcessRecord = native_hint_record;
    record.pvUserData = &context;
    record.avInputData[PROCREC_HINT_ARGIN_SHOWPROGRESS] = NULL;
    record.avInputData[PROCREC_HINT_ARGIN_MAXMOVES] = (void *) (ptrdiff_t) 1;

    outputoff();
    hint_move(max_moves, FALSE, &record);
    outputon();
    return context.found ? GNUBG_NATIVE_OK : GNUBG_NATIVE_ENGINE_ERROR;
}

gnubg_native_result
gnubg_native_analyse(gnubg_native *engine,
                     const gnubg_native_analysis_settings *settings)
{
    decisionData decision;
    cubeinfo cube;
    evalcontext evaluation;
    gnubg_native_analysis result;
    int plies;

    if (!engine || engine != active_engine)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (!settings || settings->plies > MAX_FILTER_PLIES)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (settings->trials)
        return GNUBG_NATIVE_NOT_READY;
    if (ms.gs != GAME_PLAYING)
        return GNUBG_NATIVE_NOT_READY;

    GetMatchStateCubeInfo(&cube, &ms);
    evaluation = GetEvalChequer()->ec;
    plies = settings->plies;
    evaluation.nPlies = (unsigned int) plies;
    evaluation.fUsePrune = plies > 0;
    evaluation.fDeterministic = settings->deterministic != 0;
    memset(&decision, 0, sizeof(decision));
    decision.pboard = msBoard();
    decision.pci = &cube;
    decision.pec = &evaluation;

    outputoff();
    if (RunAsyncProcess((AsyncFun) asyncMoveDecisionE, &decision,
                        _("Analysing position...")) != 0 || MT_SafeGet(&fInterrupt)) {
        outputon();
        ResetInterrupt();
        return GNUBG_NATIVE_ENGINE_ERROR;
    }
    outputon();

    memset(&result, 0, sizeof(result));
    result.player = (int8_t) ms.fTurn;
    result.plies = (uint8_t) plies;
    memcpy(result.outputs, decision.aarOutput[0], sizeof(result.outputs));
    if (engine->callbacks.analysis)
        engine->callbacks.analysis(engine->callbacks.context, &result);
    return GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_snapshot(const gnubg_native *engine,
                      gnubg_native_position *position)
{
    if (!engine || engine != active_engine || !position)
        return GNUBG_NATIVE_INVALID_ARGUMENT;

    native_snapshot_position(position);
    return GNUBG_NATIVE_OK;
}

const char *
gnubg_native_result_string(gnubg_native_result result)
{
    switch (result) {
    case GNUBG_NATIVE_OK:
        return "ok";
    case GNUBG_NATIVE_INVALID_ARGUMENT:
        return "invalid argument";
    case GNUBG_NATIVE_NOT_READY:
        return "not ready";
    case GNUBG_NATIVE_ILLEGAL_MOVE:
        return "illegal move";
    case GNUBG_NATIVE_ENGINE_ERROR:
        return "engine error";
    default:
        return "unknown result";
    }
}

const char *
gnubg_native_version(void)
{
    return PACKAGE_VERSION;
}
