# How Clicky works

For anyone reading or changing the code. Player-facing behavior is in
[macros-user-journeys.md](macros-user-journeys.md).

## Hidden buttons

WoW only lets a toy be used from a player's click, so addons can't use toys directly. Every
Clicky macro has the same line, which clicks hidden secure buttons:

```
/click [btn:2]ClickyP<code>;Clicky<code>      (Favorites: ClickyPFVRT;ClickyFVRT)
```

The code is four random consonants (`BCDFGHJKLMNPQRSTVWXZ`), so the line is always 36 characters.
Clicky draws one that no macro it has read uses, and never `FVRT`, which Favorites keeps. It
keeps no saved data, so it can't know the code of a macro that was deleted: a later macro could,
rarely, draw it again. Macros 0.4.0 wrote have a number instead (`ClickyP4;ClickySet4`, Favorites:
`ClickyP0;ClickyButton`); the sync writes the code into the macro together with its toys in the
new format, and rewrites Favorites' line (remove with the format 4 conversion).

`/click` with no mouse button sends a left click, and the line goes through WoW's macro
conditionals, so a right-click goes to `ClickyP<code>`, which opens the macro's drawer, and
anything else to `Clicky<code>` (`type` = `toy`), which uses a random toy.

### Random toys

Out of combat, just before the click goes through, Clicky sets the button's toy to a random pick
from the macro, and straight after, it picks the next one.

```
you press the macro
  -> it clicks its hidden button
  -> Clicky puts a random toy on the button
  -> the button uses the toy
  -> Clicky puts the next toy on the button
```

Picks skip toys you don't own, can't use here, or that are on cooldown, and avoid repeating the
last toy. The toy counted as used is read from the button's attribute after the click.

In combat Clicky's own code can't set secure attributes, so on `PLAYER_REGEN_DISABLED` (the last
moment before the lockdown) it hands each button the list of toys ready then, as attributes. A
secure snippet wrapped around the button's click picks from that list with `random`, also
avoiding the last toy, only when `SecureCmdOptionParse("[combat]1")` says the player is in
combat; out of combat the pick above stays in charge. The list can't change until combat ends, so
cooldowns during the fight aren't seen. Code: `CreateButton`, `LineUpToy` and
`GetCandidates` in Macros.lua.

### Drawers

`ClickyP<code>`'s secure snippet opens the macro's drawer at the cursor: a grid of secure toy
buttons, one per owned toy in the macro (Favorites: per owned starred toy), in the panel's order, with
cooldowns. Each toy button uses its toy. The drawer hides on a choice, on Escape, on a second
right-click and when the mouse leaves, in combat too.

Protected frames can't be created in combat and buttons can't be destroyed, so drawers are made
with the macro's button and their toy buttons are reused. Filling one makes a button per owned toy
(up to 150; Favorites has no limit), so drawers are filled a few at a time after login and after
combat, when opened out of combat, and all of them on `PLAYER_REGEN_DISABLED`. Code: Drawer.lua.

## Where the toys are stored

WoW saves macros on Blizzard's servers and syncs them to every computer, while addon saved data
stays on one computer. So a macro's toys are stored in the macro, in a `#clicky` line that WoW
skips when running the macro:

```
/click [btn:2]ClickyPBCDF;ClickyBCDF
#clicky rAvTtd…
```

A macro body is limited to 255 characters, and up to 150 toys have to fit. Clicky ships a list of
every toy in the game (ToyList.lua, item IDs), numbers each toy by its place in the list, stores
the numbers of the macro's toys, and compresses the gaps between them.

The list only ever grows at the end, so a toy's number never changes: a patch changes no macro,
and a toy taken out of the game keeps its place and stays in its macros until the player removes
it. `tools/update_toys.py` writes the list from the game's Toy table
for the live build (wago.tools), and `tests/check_toylist.py`, which `tests/run.sh` runs, checks
that it still starts with the list at every earlier release tag. A toy the game has and the list doesn't can't
be put in a macro until Clicky is updated ("Clicky doesn't know this toy yet"), and a macro that
holds a toy past the end of this Clicky's list reads as saved by a newer Clicky.

Macros are saved in format 5, which ends with two checksum characters, so a hand-edited line reads
as damaged rather than as other toys. Formats 1 to 3 read as damaged. Format 4 (0.4.0) numbered
the toys the game reported when the macro was saved, and stored that list's length, its highest
item ID and 16 check numbers of it. Clicky reads format 4 only to convert it, and the code is
marked for removal before the first full release: it scans the game for toys (Toys.lua, asking
`C_ToyBox.GetToyLink` about every item ID, only when a format 4 macro needs reading), and if the
toys up to the macro's highest item ID give exactly its length and check numbers, and every toy in
it is in Clicky's list, it keeps the macro's toys and saves it in format 5. A macro 0.4.0 has loaded
since the last patch that changed those toys passes, because 0.4.0 saved a macro again whenever its
list differed from the game's. Anything else reads as unreadable instead of guessing. Favorites' toys are the stars, so its macro has no
`#clicky` line.
Code: the list is built in Toys.lua, the format is in [Codec.lua](../Codec.lua) (its header
explains it, and why 150 toys fit), and macro bodies are read and written in MacroStore.lua.

## Keeping up with changes

Clicky keeps no copy of its own. It re-reads every macro on login, whenever macros change, and
when combat ends:

```
read every Clicky macro
  -> a copied macro clicks the same button?  give the copy its own button, read again
                                            (the macro the button was bound to keeps it: same
                                            name, else same index; at login, before anything is
                                            bound, the first listed; macros are sorted by name)
  -> read each macro's toys and set up its button
  -> saved by 0.4.0 (format 4)?  save it in format 5, read again
  -> refresh the panel
```

Macros can't be created, edited or deleted in combat (warcraft.wiki.gg API EditMacro, CreateMacro,
DeleteMacro: nocombat), so saving waits until combat is over; when it ends, Clicky syncs. Until a format 4
macro is converted it behaves as it did before. Code: `ns.Sync` in Macros.lua.

## Files

```
Commands.lua   /clicky commands       \
Menu.lua       right-click menus       |
Panel.lua      the Toy Box panel        >  use  Macros.lua   reads macros, sets up buttons,
Drawer.lua     right-click drawers     /                     picks toys, makes changes
                                                    |
                         MacroStore.lua   reads and writes WoW macros
                         Toys.lua         Clicky's toy list
                         ToyList.lua      every toy as an item ID (generated)
                         Codec.lua        packs toys into text
```

Every file also uses Core.lua (shared names, messages and events). Clicky keeps no saved data.

## Tests

`tests/run.sh` runs luacheck, then runs the addon in a simulated game with toys, macros shared between computers,
combat and patches, checks every WoW function Clicky calls against Blizzard's current code, and
checks that ToyList.lua only grew since each release.
The top of the script lists what to install. The panel and menus aren't simulated, so check
those by playing. GitHub runs the same script on every push.

## Releasing

`tools/release.sh <tag>` does it all, for a tag like `v0.5.0-alpha1`:

```
write the section for 0.5.0 at the top of CHANGELOG.md, commit everything else, then
tools/release.sh v0.5.0-alpha1
```

It runs `tools/update_toys.py` (which appends toys that patches added to ToyList.lua; the list
only grows), checks CHANGELOG.md's top section is `## 0.5.0`, runs `tests/run.sh`, commits
ToyList.lua and CHANGELOG.md as "Clicky 0.5.0" if either changed, pushes, then creates the
annotated tag and pushes it. It runs only on `main` and stops at the first failure.

Pushing a tag makes GitHub run the tests, then build a zip of the addon and upload it to Wago.
Tags with `alpha` or `beta` in the name are released as alpha or beta; any other tag is a full
release (BigWigsMods packager, release.sh), and the `## X-Wago-ID:` line in `Clicky.toc` names the
Wago project (packager README).
The release notes are CHANGELOG.md (`.pkgmeta`). The Wago API key is the GitHub secret
`WAGO_API_TOKEN` (`release.yml`).
