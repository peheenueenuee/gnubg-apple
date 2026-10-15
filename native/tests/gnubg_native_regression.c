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

int
main(void)
{
    gnubg_native_position position;
    gnubg_native *engine;
    TanBoard original;
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
    ap[1].pt = PLAYER_GNU;
    assert(gnubg_native_roll(engine) == GNUBG_NATIVE_NOT_READY);
    gnubg_native_destroy(engine);
    puts("native regression: lifecycle, variants, identities, illegal move, forced pass OK");
    return 0;
}
