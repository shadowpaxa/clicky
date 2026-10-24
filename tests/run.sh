#!/bin/sh
# Runs everything: luacheck, the tests (busted under LuaJIT), the API check and the check that
# ToyList.lua only grew since the last tag (needs the tags: CI fetches them). CI runs this too
# (.github/workflows/ci.yml).
# One-time setup (macOS): brew install luajit luarocks lua-language-server luacheck
#   luarocks --lua-dir="$(brew --prefix luajit)" --lua-version=5.1 install --local busted
set -e
cd "$(dirname "$0")/.."
[ -d tests/.cache/wow-ui-source ] && [ -d tests/.cache/vscode-wow-api ] || tests/fetch.sh
luacheck -q .
BUSTED="${BUSTED:-$HOME/.luarocks/bin/busted}"
"$BUSTED"
python3 tests/check_api.py
python3 tests/check_toylist.py
