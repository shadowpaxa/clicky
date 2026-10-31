#!/bin/sh
# Releases Clicky: tools/release.sh v1.1.0
# Updates ToyList.lua from the live game build, checks CHANGELOG.md's top section is this
# version's, runs the tests, commits ToyList.lua and CHANGELOG.md if either changed, pushes, then
# tags and pushes the tag, which makes GitHub run CI and upload to Wago
# (.github/workflows/release.yml). Runs only on main, and stops at the first failure. Write the
# CHANGELOG.md section and commit everything else first.
set -e
cd "$(dirname "$0")/.."

tag="$1"
if ! echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)[0-9]+)?$'; then
	echo "usage: tools/release.sh v1.1.0 (a tag like v1.2.3, v1.2.3-alpha1 or v1.2.3-beta2)" >&2
	exit 1
fi
version="${tag#v}"
version="${version%%-*}"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
	echo "$tag already exists" >&2
	exit 1
fi
# The release commit holds only ToyList.lua and CHANGELOG.md, so anything else changed would be
# left out of the tag.
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != main ]; then
	echo "release from main, not $branch" >&2
	exit 1
fi
others=$(git status --porcelain | grep -v -e ' ToyList\.lua$' -e ' CHANGELOG\.md$' || true)
if [ -n "$others" ]; then
	echo "commit these first:" >&2
	echo "$others" >&2
	exit 1
fi

python3 tools/update_toys.py

heading=$(grep -m1 '^## ' CHANGELOG.md || true)
case "$heading" in
	"## $version" | "## $version "*) ;;
	*)
		echo "CHANGELOG.md's top section is \"$heading\", not \"## $version\"" >&2
		exit 1
		;;
esac

tests/run.sh

git add ToyList.lua CHANGELOG.md
# Both may already be committed (no new toys, and the changelog committed with the rest).
if ! git diff --cached --quiet; then
	git commit -m "Clicky $version"
fi
git push
git tag -a "$tag" -m "$tag"
git push origin "$tag"
