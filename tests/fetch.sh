#!/bin/sh
# Fetches (or updates) the sources tests/check_api.py checks against, into tests/.cache.
#   wow-ui-source: Blizzard's UI code, live branch (github.com/Gethe/wow-ui-source)
#   vscode-wow-api: Ketho's WoW API annotations for lua-language-server
set -e
cd "$(dirname "$0")"
mkdir -p .cache
fetch() {
	if [ -d ".cache/$1/.git" ]; then
		git -C ".cache/$1" fetch -q --depth 1 origin "$3" && git -C ".cache/$1" reset -q --hard FETCH_HEAD
	else
		git clone -q --depth 1 --branch "$3" "$2" ".cache/$1"
	fi
	echo "$1: $(git -C ".cache/$1" log -1 --format='%h %cd' --date=short)"
}
fetch wow-ui-source https://github.com/Gethe/wow-ui-source.git live
fetch vscode-wow-api https://github.com/Ketho/vscode-wow-api.git master
