# How Clicky works

For anyone reading or changing the code. Player-facing behavior is in
[macros-user-journeys.md](macros-user-journeys.md).

## Hidden buttons

WoW only lets a toy be used from a player's click, so addons can't use toys directly. Each Clicky
macro runs `/click [nocombat] ClickySet<id>`, which clicks a hidden secure button. Just before
the click goes through, Clicky sets that button's toy to a random pick from the macro, and
straight after, it picks the next one.

```
you press the macro
  -> it clicks its hidden button
  -> Clicky puts a random toy on the button
  -> the button uses the toy
  -> Clicky puts the next toy on the button
```

Picks skip toys you don't own, can't use here, or that are on cooldown, and avoid repeating the
last toy. A toy that fails right after a click is skipped until you change zones. During combat
nothing on the button can change. Code: `CreateButton`, `LineUpToy` and `GetCandidates` in
Macros.lua.

## Where the toys are stored

WoW saves macros on Blizzard's servers and syncs them to every computer, while addon saved data
stays on one computer. So a macro's toys are stored in the macro, in a `#clicky` line that WoW
skips when running the macro:

```
/click [nocombat] ClickySet3
#clicky dIv2Bf9…
```

A macro body is limited to 255 characters, and up to 150 toys have to fit. Clicky numbers every
toy in the game in item ID order (found by asking the game about every item ID, so it's the same
for every player on a patch), stores the numbers of the macro's toys, and compresses the gaps
between them.

Because a patch can change that list, the line also stores the list's length, its highest item ID
and 16 check numbers. New toys almost always have higher item IDs and don't matter. If an old
item becomes a toy, or a toy is removed from the game, the check numbers let Clicky work out
which ones (up to 16 added or 2 removed), read the macro correctly and save it again. Anything
beyond that marks the macro unreadable instead of guessing. Code: the toy list is built in
Toys.lua, the format and the maths are in [Codec.lua](../Codec.lua) (its header explains both),
and macro bodies are read and written in MacroStore.lua.

## Keeping up with changes

Clicky keeps no copy of its own. It re-reads every macro on login, whenever macros change, and
when combat ends:

```
read every Clicky macro
  -> a copied macro clicks the same button?  give the copy its own button, read again
  -> read each macro's toys and set up its button
  -> saved before a patch changed the toy list?  save it again, read again
  -> refresh the panel
```

Macros can't be edited in combat, so saving waits until combat is over. Code: `ns.Sync` in
Macros.lua.

## Files

```
Commands.lua   /clicky commands      \
Menu.lua       right-click menus      >  use  Macros.lua   reads macros, sets up buttons,
Panel.lua      the Toy Box panel     /                     picks toys, makes changes
                                                  |
                       MacroStore.lua   reads and writes WoW macros
                       Toys.lua         the game's toy list
                       Codec.lua        packs toys into text
```

Every file also uses Core.lua (shared names, messages and events) and DB.lua (saved settings).

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
release. The release notes come from CHANGELOG.md, so add a section to it before tagging. Uploads need the
`## X-Wago-ID:` line in `Clicky.toc` and the Wago API key saved in GitHub as a secret named
`WAGO_API_TOKEN`.
