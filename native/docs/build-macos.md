# GTK-free engine smoke test on Apple silicon

The pinned upstream tree can be configured without GTK, Python, SQLite, and
the 3D board:

```sh
cd Vendor/gnubg
./autogen.sh
./configure --with-gtk=no --with-board3d=no --with-python=no --with-sqlite=no
make -j4
./gnubg --version
```

The current upstream checkout requires GNU Bison 3.x to regenerate
`sgf_y.c` and `external_y.c`. The macOS Command Line Tools provide an older
Bison, so a clean checkout must either use a newer Bison in `PATH` or use the
versioned generated parser sources supplied by the engine build environment.
Do not treat a successful `make` as sufficient: the arm64 executable must also
pass `./gnubg --version`.
