# How Clicky works

For anyone reading or changing the code. Player-facing behavior is in
[macros-user-journeys.md](macros-user-journeys.md).

## Hidden buttons

WoW only lets a toy be used from a player's click, so addons can't use toys directly. Every
Clicky macro has the same line, which clicks hidden secure buttons:

```
/click [btn:2]ClickyP<id>;ClickySet<id>       (Favorites: ClickyP0;ClickyButton)
```

`/click` with no mouse button sends a left click, and the line goes through WoW's macro
conditionals, so a right-click goes to `ClickyP<id>`, which opens the macro's drawer, and
anything else to `ClickySet<id>` (`type` = `toy`), which uses a random toy.

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

`ClickyP<id>`'s secure snippet opens the macro's drawer at the cursor: a grid of secure toy
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
/click [btn:2]ClickyP3;ClickySet3
#clicky gAAlgAwAPxGL…
```

A macro body is limited to 255 characters, and up to 150 toys have to fit. Clicky numbers every
toy in the game in item ID order (found by asking the game about every item ID; the answer doesn't
depend on which toys the player owns), stores the numbers of the macro's toys, and compresses the gaps
between them.

Because a patch can change that list, the line also stores the list's length, its highest item ID
and 16 check numbers. New toys almost always have higher item IDs and don't matter. If an old
item becomes a toy, or a toy is removed from the game, the check numbers let Clicky work out
which ones (up to 16 either way), read the macro correctly and save it again. Anything beyond
that marks the macro unreadable instead of guessing.

Macros are saved in format 4, which ends with two checksum characters, so a hand-edited line reads
as damaged rather than as other toys. Formats 1 to 3 read as damaged. Favorites' toys are the
stars, so its macro has no `#clicky` line.
Code: the toy list is built in Toys.lua, the format and the maths are in [Codec.lua](../Codec.lua)
(its header explains both, and why 150 toys fit), and macro bodies are read and written in
MacroStore.lua.

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
  -> saved before a patch changed the toy list?  save it again, read again
  -> refresh the panel
```

Macros can't be created, edited or deleted in combat (warcraft.wiki.gg API EditMacro, CreateMacro,
DeleteMacro: nocombat), so saving waits until combat is over; when it ends, Clicky syncs. Code: `ns.Sync` in
Macros.lua.

## Files

```
Commands.lua   /clicky commands       \
Menu.lua       right-click menus       |
Panel.lua      the Toy Box panel        >  use  Macros.lua   reads macros, sets up buttons,
Drawer.lua     right-click drawers     /                     picks toys, makes changes
                                                    |
                         MacroStore.lua   reads and writes WoW macros
                         Toys.lua         the game's toy list
                         Codec.lua        packs toys into text
```

Every file also uses Core.lua (shared names, messages and events). Clicky keeps no saved data.

## Tests

`tests/run.sh` runs luacheck, then runs the addon in a simulated game with toys, macros shared between computers,
combat and patches, and checks every WoW function Clicky calls against Blizzard's current code.
The top of the script lists what to install. The panel and menus aren't simulated, so check
those by playing. GitHub runs the same script on every push.

## Releasing

Pushing a tag makes GitHub run the tests, then build a zip of the addon and upload it to Wago:

```
git tag -a v0.3.1-alpha1 -m v0.3.1-alpha1 && git push --tags
```

Tags with `alpha` or `beta` in the name are released as alpha or beta; any other tag is a full
release (BigWigsMods packager, release.sh), and the `## X-Wago-ID:` line in `Clicky.toc` names the
Wago project (packager README).
The release notes are CHANGELOG.md (`.pkgmeta`), so add a section to it before tagging. The Wago
API key is the GitHub secret `WAGO_API_TOKEN` (`release.yml`).
