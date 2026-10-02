"""Runs the VHSHappiness Lua tests in a Lua 5.1 runtime (the dialect Project
Zomboid's Kahlua engine follows).

Requires lupa:  pip install lupa
Usage:          python3 tests/run_tests.py
"""

import pathlib
import sys

from lupa import lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent
B41_FILE = ROOT / "VHSHappiness/media/lua/client/VHSHappiness.lua"
B42_FILE = ROOT / "VHSHappiness/42/media/lua/client/VHSHappiness.lua"


def main():
    if B41_FILE.read_bytes() != B42_FILE.read_bytes():
        print(f"FAIL  Build 41 and Build 42 copies differ:\n      {B41_FILE}\n      {B42_FILE}")
        return 1

    lua = lua51.LuaRuntime()
    lua.globals().MOD_ROOT = str(ROOT)
    failed = lua.execute((ROOT / "tests/test_vhs_happiness.lua").read_text())
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
