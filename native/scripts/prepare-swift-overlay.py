#!/usr/bin/env python3
"""Hide a duplicate SwiftBridging definition in a build-local VFS overlay.

Some CLT upgrades leave module.modulemap beside its replacement,
bridging.modulemap. Do not alter the installed toolchain.
"""
import json
from pathlib import Path
import subprocess
import sys

build = Path(sys.argv[1]).resolve()
compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
headers = compiler.parent.parent / "include" / "swift"
legacy = headers / "module.modulemap"
current = headers / "bridging.modulemap"
roots = []
if all(path.is_file() and "module SwiftBridging" in path.read_text() for path in (legacy, current)):
    empty = build / "empty.modulemap"
    empty.write_text("// Stale SwiftBridging definition hidden for this build only.\n")
    roots.append({"type": "file", "name": str(legacy), "external-contents": str(empty)})
(build / "toolchain-overlay.json").write_text(json.dumps({"version": 0, "roots": roots}))
if roots:
    print("Using build-local overlay for duplicate CLT SwiftBridging module maps")
