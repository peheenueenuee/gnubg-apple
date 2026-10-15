# Engine pinning

The Apple front end tracks GNU Backgammon as an upstream dependency. The
working checkout currently used for adapter development is:

```text
upstream commit: 0143cad3
upstream tree:   /Users/y-shirai/Nopaid/bg/gnubg
```

The engine is pinned as the `Vendor/gnubg` Git submodule at the commit above.
Initialize it with `git submodule update --init`. Build products remain inside
that upstream checkout and are not application source changes.

## Update procedure

1. Fetch the upstream repository.
2. Review the new commit and its license/build requirements.
3. Update the submodule commit.
4. Build the GTK-free adapter and run the native smoke test on arm64 macOS.
5. Record the upstream commit in this file and in the application changelog.

Only changes required for the platform-neutral engine boundary should be
considered for contribution back upstream. Apple UI code stays in this
repository.
