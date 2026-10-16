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

#ifndef USE_MULTITHREAD
#error "Native cancellation requires a multithreaded GNUbg build"
#endif

#include <string.h>

struct gnubg_native {
    gnubg_native_callbacks callbacks;
    GMutex interrupt_lock;
    int analysing;
    int cancelled;
};

static gnubg_native *active_engine;
static int engine_initialized;
static GThread *engine_thread;

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
    fConfirmNew = FALSE;
    fTutor = FALSE;
    fSound = FALSE;

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

    engine_thread = g_thread_ref(g_thread_self());
    engine_initialized = TRUE;
    return GNUBG_NATIVE_OK;
}

static int
native_match_over(void)
{
    return ms.nMatchTo > 0 &&
        (ms.anScore[0] >= ms.nMatchTo || ms.anScore[1] >= ms.nMatchTo);
}

static int
native_can_double(void)
{
    return ms.gs == GAME_PLAYING && !ms.anDice[0] && !ms.fDoubled &&
        !ms.fResigned && ms.fMove == ms.fTurn && ms.fCubeUse && !ms.fCrawford &&
        (ms.fCubeOwner < 0 || ms.fCubeOwner == ms.fTurn) &&
        ms.nCube < MAXSCORE && ms.nCube < ms.nMatchTo - ms.anScore[ms.fTurn];
}

static void
native_settle(void)
{
    /* Finalize scores/Crawford without automatically executing another player. */
    StopAutomaticPlay();
    if (fNextTurn)
        NextTurn(FALSE);
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
    position->match_over = native_match_over();
    position->crawford = ms.fCrawford;
    position->resignation = ms.gs == GAME_PLAYING ? MAX(0, ms.fResigned) : 0;
    position->can_double = native_can_double();
    position->board_player = ms.fMove;
    position->computer_turn = ms.gs == GAME_PLAYING && ap[ms.fTurn].pt == PLAYER_GNU;
    position->game_number = ms.cGames + 1;
}

gnubg_native *
gnubg_native_create(gnubg_native_variation variation,
                    const gnubg_native_callbacks *callbacks)
{
    gnubg_native *engine;

    if ((engine_thread && engine_thread != g_thread_self()) || active_engine || variation < GNUBG_NATIVE_STANDARD ||
        variation > GNUBG_NATIVE_HYPERGAMMON_3)
        return NULL;

    engine = g_new0(gnubg_native, 1);
    g_mutex_init(&engine->interrupt_lock);
    if (callbacks)
        engine->callbacks = *callbacks;

    bgvDefault = (bgvariation) variation;
    if (native_bootstrap(engine) != GNUBG_NATIVE_OK) {
        g_mutex_clear(&engine->interrupt_lock);
        g_free(engine);
        return NULL;
    }

    active_engine = engine;
    return engine;
}

void
gnubg_native_destroy(gnubg_native *engine)
{
    if (!engine || engine != active_engine || engine_thread != g_thread_self())
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
    g_mutex_clear(&engine->interrupt_lock);
    g_free(engine);
}

gnubg_native_result
gnubg_native_start_match(gnubg_native *engine,
                         uint32_t match_length,
                         gnubg_native_player player0,
                         gnubg_native_player player1)
{
    char length[32];

    if (!engine || engine != active_engine || engine_thread != g_thread_self())
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if ((player0 != GNUBG_NATIVE_HUMAN && player0 != GNUBG_NATIVE_COMPUTER) ||
        (player1 != GNUBG_NATIVE_HUMAN && player1 != GNUBG_NATIVE_COMPUTER) ||
        !match_length || match_length > MAXSCORE)
        return GNUBG_NATIVE_INVALID_ARGUMENT;

    /* StartNewGame otherwise executes an opening computer turn implicitly. */
    ap[0].pt = ap[1].pt = PLAYER_HUMAN;
    snprintf(length, sizeof(length), "%u", match_length);
    outputoff();
    CommandNewMatch(length);
    native_settle();
    ap[0].pt = player0 == GNUBG_NATIVE_COMPUTER ? PLAYER_GNU : PLAYER_HUMAN;
    ap[1].pt = player1 == GNUBG_NATIVE_COMPUTER ? PLAYER_GNU : PLAYER_HUMAN;
    for (int player = 0; player < 2; player++) {
        ap[player].esChequer.ec.nPlies = 0;
        ap[player].esCube.ec.nPlies = 0;
    }
    outputon();
    return ms.gs == GAME_PLAYING ? GNUBG_NATIVE_OK : GNUBG_NATIVE_ENGINE_ERROR;
}

gnubg_native_result
gnubg_native_roll(gnubg_native *engine)
{
    int previous_turn;

    if (!engine || engine != active_engine || engine_thread != g_thread_self())
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING)
        return GNUBG_NATIVE_NOT_READY;

    if (ms.anDice[0] || ms.fDoubled || ms.fResigned ||
        ap[ms.fTurn].pt != PLAYER_HUMAN)
        return GNUBG_NATIVE_NOT_READY;

    previous_turn = ms.fTurn;
    outputoff();
    CommandRoll(NULL);
    native_settle();
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

    if (!engine || engine != active_engine || engine_thread != g_thread_self())
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (!move || move->step_count == 0 || move->step_count > 4)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING || !ms.anDice[0] || ms.fDoubled || ms.fResigned)
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
    native_settle();
    outputon();
    return ms.anDice[0] ? GNUBG_NATIVE_ENGINE_ERROR : GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_hint(gnubg_native *engine, gnubg_native_move *move)
{
    native_hint_context context;
    procrecorddata record;
    char max_moves[] = "1";

    if (!engine || engine != active_engine || engine_thread != g_thread_self())
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (!move)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING || !ms.anDice[0] || ms.fDoubled || ms.fResigned)
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
gnubg_native_legal_moves(gnubg_native *engine, gnubg_native_move *moves,
                         uint32_t capacity, uint32_t *count)
{
    movelist legal;
    if (!engine || engine != active_engine || engine_thread != g_thread_self() || !count || (!moves && capacity))
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    *count = 0;
    if (ms.gs != GAME_PLAYING || !ms.anDice[0] || ms.fDoubled || ms.fResigned)
        return GNUBG_NATIVE_NOT_READY;
    GenerateMoves(&legal, msBoard(), ms.anDice[0], ms.anDice[1], FALSE);
    *count = legal.cMoves;
    if (!moves && !capacity)
        return GNUBG_NATIVE_OK;
    if (capacity < legal.cMoves)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    for (unsigned int i = 0; i < legal.cMoves; i++) {
        memset(&moves[i], 0, sizeof(moves[i]));
        for (int step = 0; step < 4 && legal.amMoves[i].anMove[step * 2] >= 0; step++) {
            moves[i].steps[step].from = legal.amMoves[i].anMove[step * 2];
            moves[i].steps[step].to = legal.amMoves[i].anMove[step * 2 + 1];
            moves[i].step_count++;
        }
    }
    return GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_act(gnubg_native *engine, gnubg_native_action action)
{
    if (!engine || engine != active_engine || engine_thread != g_thread_self())
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (action < GNUBG_NATIVE_DOUBLE || action > GNUBG_NATIVE_COMPUTER_TURN)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (action == GNUBG_NATIVE_NEXT_GAME) {
        if (ms.gs == GAME_PLAYING || ms.gs == GAME_NONE || native_match_over())
            return GNUBG_NATIVE_NOT_READY;
    } else if (ms.gs != GAME_PLAYING ||
               (action != GNUBG_NATIVE_COMPUTER_TURN && ap[ms.fTurn].pt != PLAYER_HUMAN))
        return GNUBG_NATIVE_NOT_READY;
    if ((action == GNUBG_NATIVE_DOUBLE && !native_can_double()) ||
        ((action == GNUBG_NATIVE_TAKE || action == GNUBG_NATIVE_DROP) && !ms.fDoubled) ||
        ((action == GNUBG_NATIVE_ACCEPT_RESIGNATION || action == GNUBG_NATIVE_REJECT_RESIGNATION) && !ms.fResigned) ||
        (action == GNUBG_NATIVE_COMPUTER_TURN && ap[ms.fTurn].pt != PLAYER_GNU))
        return GNUBG_NATIVE_NOT_READY;
    ResetInterrupt();
    outputoff();
    switch (action) {
    case GNUBG_NATIVE_DOUBLE: CommandDouble(NULL); break;
    case GNUBG_NATIVE_TAKE: CommandTake(NULL); break;
    case GNUBG_NATIVE_DROP: CommandDrop(NULL); break;
    case GNUBG_NATIVE_ACCEPT_RESIGNATION: CommandAccept(NULL); break;
    case GNUBG_NATIVE_REJECT_RESIGNATION: CommandReject(NULL); break;
    case GNUBG_NATIVE_COMPUTER_TURN: CommandPlay(NULL); break;
    case GNUBG_NATIVE_NEXT_GAME: {
        playertype saved[2] = {ap[0].pt, ap[1].pt};
        ap[0].pt = ap[1].pt = PLAYER_HUMAN;
        CommandNewGame(NULL);
        ap[0].pt = saved[0]; ap[1].pt = saved[1];
        break;
    }
    }
    native_settle();
    outputon();
    return GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_resign(gnubg_native *engine, uint8_t points)
{
    char value[2] = { (char) ('0' + points), 0 };
    if (!engine || engine != active_engine || engine_thread != g_thread_self() || points < 1 || points > 3)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING || ms.fDoubled || ms.fResigned ||
        ap[ms.fTurn].pt != PLAYER_HUMAN || points <= ms.fResignationDeclined)
        return GNUBG_NATIVE_NOT_READY;
    outputoff();
    CommandResign(value);
    native_settle();
    outputon();
    return ms.fResigned ? GNUBG_NATIVE_OK : GNUBG_NATIVE_ENGINE_ERROR;
}

static void
native_rollout_progress(float outputs[][NUM_ROLLOUT_OUTPUTS],
                        float errors[][NUM_ROLLOUT_OUTPUTS],
                        const rolloutcontext *context, const cubeinfo cubes[],
                        unsigned int initial, int game, int alternative,
                        int rank, float jsd, int stopped, int show_ranks,
                        int cube_rollout, void *data)
{
    gnubg_native *engine = data;
    (void) outputs; (void) errors; (void) cubes; (void) initial;
    (void) alternative; (void) rank; (void) jsd; (void) stopped;
    (void) show_ranks; (void) cube_rollout;
    if (engine->callbacks.progress)
        engine->callbacks.progress(engine->callbacks.context,
            game < 0 ? 0 : MIN((uint32_t) game + 1, context->nTrials),
            context->nTrials);
}

void
gnubg_native_cancel(gnubg_native *engine)
{
    /* The caller guarantees lifetime; do not race on active_engine. */
    if (!engine)
        return;
    g_mutex_lock(&engine->interrupt_lock);
    if (engine->analysing) {
        engine->cancelled = TRUE;
        /* The macOS adapter requires GNUbg's multithreaded engine build. */
        g_atomic_int_set(&fInterrupt, TRUE);
    }
    g_mutex_unlock(&engine->interrupt_lock);
}

gnubg_native_result
gnubg_native_analyse(gnubg_native *engine,
                     const gnubg_native_analysis_settings *settings)
{
    decisionData decision;
    cubeinfo cube;
    evalcontext evaluation;
    gnubg_native_analysis result;
    int status, cancelled;
    int saved_progress = fShowProgress;

    if (!engine || engine != active_engine || engine_thread != g_thread_self())
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (!settings || settings->plies > MAX_FILTER_PLIES || settings->trials > 1000000)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    if (ms.gs != GAME_PLAYING || ms.fDoubled || ms.fResigned)
        return GNUBG_NATIVE_NOT_READY;

    GetMatchStateCubeInfo(&cube, &ms);
    evaluation = GetEvalChequer()->ec;
    evaluation.nPlies = settings->plies;
    evaluation.fUsePrune = settings->plies > 0;
    evaluation.fDeterministic = settings->deterministic != 0;
    evaluation.rNoise = 0;
    memset(&result, 0, sizeof(result));
    result.player = (int8_t) ms.fMove;
    result.plies = settings->plies;
    result.trials = settings->trials;

    g_mutex_lock(&engine->interrupt_lock);
    ResetInterrupt();
    engine->cancelled = FALSE;
    engine->analysing = TRUE;
    g_mutex_unlock(&engine->interrupt_lock);
    outputoff();
    if (settings->trials) {
        rolloutcontext saved_rollout = rcRollout;
        rolloutcontext rollout = rcRollout;
        TanBoard board;
        int player;
        memcpy(board, ms.anBoard, sizeof(board));
        rollout.nTrials = settings->trials;
        rollout.nGamesDone = 0;
        rollout.nSkip = 0;
        rollout.fStopOnSTD = rollout.fStopOnJsd = rollout.fStopMoveOnJsd = FALSE;
        rollout.fInitial = FALSE;
        rollout.fLateEvals = FALSE;
        rollout.fDoTruncate = FALSE;
        rollout.nSeed = settings->deterministic ? 1 : (unsigned long) g_get_real_time();
        for (player = 0; player < 2; player++) {
            rollout.aecCube[player] = evaluation;
            rollout.aecChequer[player] = evaluation;
        }
        fShowProgress = TRUE; /* GNUbg gates its callback on this flag. */
        rcRollout = rollout; /* Upstream also reads the global trial budget. */
        status = GeneralEvaluationR(result.outputs, result.standard_errors, NULL,
                    board, &cube, &rollout, native_rollout_progress, engine);
        rcRollout = saved_rollout;
    } else {
        memset(&decision, 0, sizeof(decision));
        decision.pboard = msBoard();
        decision.pci = &cube;
        decision.pec = &evaluation;
        status = RunAsyncProcess((AsyncFun) asyncMoveDecisionE, &decision,
                                 _("Analysing position..."));
        memcpy(result.outputs, decision.aarOutput[0], sizeof(result.outputs));
    }
    fShowProgress = saved_progress;
    outputon();
    g_mutex_lock(&engine->interrupt_lock);
    cancelled = engine->cancelled;
    engine->analysing = FALSE;
    ResetInterrupt();
    g_mutex_unlock(&engine->interrupt_lock);
    if (cancelled)
        return GNUBG_NATIVE_CANCELLED;
    if (status != 0) {
        native_message(engine, "Position analysis failed");
        return GNUBG_NATIVE_ENGINE_ERROR;
    }
    if (engine->callbacks.analysis)
        engine->callbacks.analysis(engine->callbacks.context, &result);
    return GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_snapshot(const gnubg_native *engine,
                      gnubg_native_position *position)
{
    if (!engine || engine != active_engine || engine_thread != g_thread_self() || !position)
        return GNUBG_NATIVE_INVALID_ARGUMENT;

    native_snapshot_position(position);
    return GNUBG_NATIVE_OK;
}

gnubg_native_result
gnubg_native_last_turn(const gnubg_native *engine, int8_t player,
                        gnubg_native_turn *turn)
{
    if (!engine || engine != active_engine || engine_thread != g_thread_self() ||
        !turn || player < 0 || player > 1)
        return GNUBG_NATIVE_INVALID_ARGUMENT;
    memset(turn, 0, sizeof(*turn));
    if (ms.gs == GAME_NONE || !plGame || !plLastMove)
        return GNUBG_NATIVE_NOT_READY;
    for (const listOLD *entry = plLastMove; entry != plGame; entry = entry->plPrev) {
        const moverecord *record = entry->p;
        if (!record || record->mt == MOVE_GAMEINFO)
            break;
        if (record->mt != MOVE_NORMAL || record->fPlayer != player)
            continue;
        turn->player = player;
        turn->dice[0] = record->anDice[0];
        turn->dice[1] = record->anDice[1];
        for (int step = 0; step < 4 && record->n.anMove[step * 2] >= 0; step++) {
            turn->move.steps[step].from = record->n.anMove[step * 2];
            turn->move.steps[step].to = record->n.anMove[step * 2 + 1];
            turn->move.step_count++;
        }
        return GNUBG_NATIVE_OK;
    }
    return GNUBG_NATIVE_NOT_READY;
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
    case GNUBG_NATIVE_CANCELLED:
        return "cancelled";
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
