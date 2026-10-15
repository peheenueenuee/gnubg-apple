# GTK-free engine smoke test on Apple silicon

The pinned upstream tree can be configured without GTK, Python, SQLite, and
the 3D board with the repository build script:

```sh
native/scripts/build-engine-macos.sh
```

Use `GNUBG_BUILD_JOBS=4` to limit parallelism. The script checks that the
result is an arm64 Mach-O executable and runs `gnubg --version`.

The first native C boundary can be linked and exercised with:

```sh
native/scripts/build-native-smoke-macos.sh
```

This currently validates one real engine handle, starting a one-point match,
and taking a position snapshot. It is intentionally a single-handle smoke
test while upstream's process-global initialization is being separated.

The current upstream checkout requires GNU Bison 3.x to regenerate
`sgf_y.c` and `external_y.c`. The macOS Command Line Tools provide an older
Bison, so a clean checkout must either use a newer Bison in `PATH` or use the
versioned generated parser sources supplied by the engine build environment.
Do not treat a successful `make` as sufficient: the arm64 executable must also
pass `./gnubg --version`.
