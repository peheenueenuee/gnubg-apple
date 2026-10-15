#include "../include/gnubg_native.h"

#include <stdio.h>

static void
message(void *context, const char *text)
{
    (void) context;
    fprintf(stderr, "engine: %s\n", text);
}

int
main(void)
{
    gnubg_native_callbacks callbacks = {
        .message = message,
        .progress = NULL,
        .context = NULL
    };
    gnubg_native_position position;
    gnubg_native_move move;
    gnubg_native *engine;
    unsigned int checkers[2] = {0, 0};
    unsigned int player;
    unsigned int point;
    unsigned int attempts;
    gnubg_native_result roll_result = GNUBG_NATIVE_ENGINE_ERROR;

    engine = gnubg_native_create(GNUBG_NATIVE_STANDARD, &callbacks);
    if (!engine) {
        fprintf(stderr, "failed to create native engine\n");
        return 1;
    }

    if (gnubg_native_start_match(engine, 1, GNUBG_NATIVE_HUMAN,
                                 GNUBG_NATIVE_HUMAN) != GNUBG_NATIVE_OK)
        return 2;

    if (gnubg_native_snapshot(engine, &position) != GNUBG_NATIVE_OK)
        return 3;

    for (player = 0; player < 2; player++) {
        checkers[player] = position.bar[player] + position.borne_off[player];
        for (point = 0; point < 24; point++)
            checkers[player] += position.points[player][point];
    }

    printf("turn=%d match_length=%u cube=%u checkers=%u/%u\n",
           position.turn, position.match_length, position.cube_value,
           checkers[0], checkers[1]);

    for (attempts = 0; attempts < 100; attempts++) {
        roll_result = gnubg_native_roll(engine);
        if (roll_result == GNUBG_NATIVE_OK)
            break;
    }
    if (roll_result != GNUBG_NATIVE_OK)
        return 4;
    if (gnubg_native_hint(engine, &move) != GNUBG_NATIVE_OK)
        return 5;
    if (gnubg_native_play(engine, &move) != GNUBG_NATIVE_OK)
        return 6;
    if (gnubg_native_snapshot(engine, &position) != GNUBG_NATIVE_OK ||
        position.dice[0] || position.dice[1])
        return 7;

    printf("played_steps=%u next_turn=%d\n", move.step_count, position.turn);

    gnubg_native_destroy(engine);
    return 0;
}
