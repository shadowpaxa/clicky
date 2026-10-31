#!/usr/bin/env python3
"""ToyList.lua only grows at the end: an entry's number in players' macros is its place in it.

With no arguments, compares ToyList.lua with the one at every release tag from v1.0.0 on that
this commit contains (`git tag --merged HEAD --list 'v[1-9]*'`): each of those lists must be a
prefix of this one. Every such tag, not just the newest, because the newest can be on this very
commit (a release's own CI run, or tools/release.sh before its commit). `--old FILE --new FILE`
compares two files instead (tests/test_toylist.lua uses it). Compares the entries (toys are item
IDs; spells, items and mounts are "s", "i" and "m" with an ID; pets are "p", a species and a
display ID), not the text.
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from update_toys import read_entries  # noqa: E402


KIND = {"": "toy", "s": "spell", "i": "item", "m": "mount", "p": "pet"}


def name(entry):
    kind, i = entry
    return "%s %s" % (KIND[kind], "%d:%d" % i if kind == "p" else i)


def problem(old, new):
    """Why `new` isn't `old` grown at the end, or None."""
    seen = set()
    for place, entry in enumerate(new):
        if entry in seen:
            return "%s is listed twice (second time at place %d)" % (name(entry), place)
        seen.add(entry)
    if len(new) < len(old):
        return "the list shrank from %d to %d entries" % (len(old), len(new))
    for place, entry in enumerate(old):
        if new[place] != entry:
            return "place %d held %s and now holds %s" % (place, name(entry), name(new[place]))
    return None


def git(*args):
    result = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--old")
    parser.add_argument("--new")
    args = parser.parse_args()
    if bool(args.old) != bool(args.new):
        parser.error("--old and --new go together")
    olds = []
    if args.old:
        with open(args.old, encoding="utf-8") as f:
            olds.append(("the old list", read_entries(f.read())))
    else:
        for tag in (git("tag", "--merged", "HEAD", "--list", "v[1-9]*") or "").split():
            olds.append((tag, read_entries(git("show", "%s:ToyList.lua" % tag))))
    with open(args.new or os.path.join(ROOT, "ToyList.lua"), encoding="utf-8") as f:
        new = read_entries(f.read())
    if not olds:
        why = problem([], new)
        if why:
            print("ToyList.lua: %s" % why)
            return 1
        print("ToyList.lua: %d entries, no tag has a list to compare" % len(new))
        return 0
    for where, old in olds:
        why = problem(old, new)
        if why:
            print("ToyList.lua must only grow at the end (compared with %s): %s" % (where, why))
            return 1
    print("ToyList.lua: %d entries, grown from %s" % (len(new), ", ".join(
        "%s's %d" % (where, len(old)) for where, old in olds)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
