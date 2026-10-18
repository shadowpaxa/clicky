# Clicky

A World of Warcraft retail addon (Interface 120105, Midnight 12.x): toy buttons for Toy Box
favorites and for toy macros the player makes. A click uses a random toy from the macro; a
right-click opens a drawer of its toys, and clicking one there uses it.

- `docs/macros-user-journeys.md`: what players see and do. Check every change against it.
- `README.md`: for players. `docs/architecture.md`: the design, for people reading the code.
  Keep both true when behavior or design changes. Neither is repeated here.
- Each `.lua` file's header lists its `ns` API (and which functions are there only for tests).
  Keep those lists current; they're the code map.

Players see only "macros", never "sets"; that older name survives only in the `ClickySet<id>`
button names, which bars depend on.

## Rules

**Never change the player's settings.** Clicky changes only its own macros, its own buttons and a
toy's star when the player picks that from its menu. Never Toy Box filters,
CVars or any other game setting: they're the player's, saved by WoW, and outlive the addon. An
earlier Clicky "restored" the Toy Box filters and left a player's Toy Box empty. The test "Never
changes the player's settings" fails on any such call.

**One code path per behavior.**
- Every change the player asks for goes through `SetToy`, `MakeMacro`, `RenameMacro` or
  `DeleteMacro` (and `PickupMacro`, which makes Favorites' macro), and every automatic write (re-saves, separating copies) through `ns.Sync`
  (Macros.lua); every macro read or write through MacroStore.lua; every UI refresh through
  `ns.Changed()`.
  Both toy menus share `AddMacroEntries` (Menu.lua).
- Refusals return `nil, reason`; the caller shows the reason.
- Extend the owning file's `ns` API rather than reaching into another file's locals. A new
  concern gets a new file, added to the `.toc`.

**Don't break players' bars or data.**
- A macro is the only copy of its toys. Clicky has no saved variables.
- Every macro's line is `/click [btn:2]ClickyP<id>;ClickySet<id>` (Favorites:
  `/click [btn:2]ClickyP0;ClickyButton`, and its macro is found by that line, not its name).
  Never rename the `ClickyButton`, `ClickySet<id>` or `ClickyP<id>` buttons or change that line,
  except to give a copied macro its own id (both buttons).
- Changing the `#clicky` format means a new format version in Codec.lua. Macros are written in
  format 4 (with a checksum); 1 to 3 read as damaged. An unreleased format may change in place. Favorites' macro has no `#clicky` line. No
  migration code while Clicky is in alpha: alpha releases may break macros, and players make them
  again.
- A macro Clicky can't read has no toys and takes no changes. It must not read as other toys.

**Debuggability.** Log every state change with `ns.Trace(format, ...)` (guard costly arguments
with `ns.IsTracing()`). New state gets a line in `/clicky debug`. Comments explain WoW
constraints and non-obvious reasons, not what the code does.

## Tests

`tests/run.sh` must pass before every commit (setup is in its header); CI runs it on every push
and before each release (`.github/workflows/ci.yml`). It runs luacheck (`.luacheckrc`: a WoW
global Clicky starts using goes in its `read_globals`), `tests/test_journeys.lua` (busted under
LuaJIT, which is Lua 5.1 like WoW), `tests/test_docs.lua` (README.md's limits, commands, messages and labels against the code) and
`tests/check_api.py` (lua-language-server with Ketho's annotations, plus every Blizzard name
Clicky uses checked against Blizzard's live UI source; `tests/fetch.sh` refreshes both).

- Tests are named after the journeys and call what the UI is built on: the Macros API,
  `ns.PanelRows`, `ns.ToyMenuEntries`. `tests/wow.lua` stubs only game state Clicky relies on,
  citing Blizzard's documentation or source; keep it one file. A second computer on the same
  account is `wow.New({ account = world.account })`; `world:AddToy` adds a toy to the game.
- Blizzard's UI (Toy Box, menus, dialogs, tooltips) isn't stubbed. How Clicky's UI looks and
  responds is checked by playing; say so instead of claiming it works.
- Test what playing can't easily show: the format and catch-up maths, sync across computers,
  patches, combat, refusals and their reasons.
- Assert on Clicky's results (macro bodies, button attributes, errors via `world:TakeErrors()`,
  return values), not on what the stubs did.
- A logic change updates its tests in the same commit. A bug fix gets a test that fails without
  the fix. Break the code once to see a new test fail before trusting it.
- Logic worth testing lives in plain functions on `ns`, marked "for tests" in the file header.

WoW runs Lua 5.1: no `goto`, `//`, bitwise operators or other 5.2+ syntax.

## Commits and releases

- `main` is on GitHub (private `shadowpaxa/clicky`). Add new commits; don't amend or force-push
  pushed history. Commits are authored `shadowpaxa <shadowpaxa@gmail.com>` (set in this clone's
  `.git/config`; set it in any new clone). Nothing personal beyond that goes in the repo.
- Release: add a section to the top of `CHANGELOG.md` (`.pkgmeta`'s manual-changelog makes it the
  release notes), commit, push, then push an annotated tag: `v0.3.1-alpha1` style.
  A tag with `alpha` or `beta` releases as that; any other tag as a full release (BigWigsMods
  packager, release.sh). The tag runs CI, then `.github/workflows/release.yml` packages and uploads to Wago (project `j6jAEMNR`,
  secret `WAGO_API_TOKEN`). Check the run with `gh run list -R shadowpaxa/clicky`.
- Compatibility: alpha releases may break players' macros; full releases must not.

## WoW constraints

- `UseToy()` is protected (warcraft.wiki.gg API UseToy), so each macro `/click`s a hidden
  `SecureActionButtonTemplate` button (`type` = `toy`). `useOnKeyDown` is false because `/click`
  sends an up click (SlashCommands.lua).
- Macro bodies hold 255 characters (MacroFrameText `letters="255"`; EditMacro saves only the first
  255, warcraft.wiki.gg API EditMacro), names 16 (the name box has `letters="16"`); 120 general
  macros per account and 30 per character (MacroConstantsDocumentation.lua). General macros are
  sorted by name (warcraft.wiki.gg API EditMacro), so creating or renaming one can move others,
  and a copy can be listed before its original. The `#clicky` line does nothing when the macro
  runs (seen in play). `|` is WoW's escape character, so it never appears in data.
- In combat, secure attributes can't be set from addon code, macros can't be created, edited or
  deleted (warcraft.wiki.gg API CreateMacro, EditMacro, DeleteMacro: nocombat), and protected
  frames can't be created. Macro changes (toys, name) are refused in
  combat; re-saves, separating copies, making or emptying buttons, and making or filling drawers
  wait for `PLAYER_REGEN_ENABLED`. Buttons can't be destroyed, so a deleted macro's button is
  emptied and drawer buttons are reused.
- Macros and drawers work in combat through secure snippets: a macro's button picks with
  `random` from a list handed to it as attributes, and the drawer opens and hides in secure code.
  `PLAYER_REGEN_DISABLED` is the last chance to hand those lists over and fill the drawers
  (it's synchronous, UnitDocumentation.lua, and SecureStateDriver.lua sets attributes on it).
- If macros aren't readable at `ADDON_LOADED`, nothing is read or written until `UPDATE_MACROS`.
- The game's toy list comes from `C_ToyBox.GetToyLink` on every item ID, stopping 50,000 IDs past
  the last toy found.
- `Blizzard_Collections` (the Toy Box) is load-on-demand: Panel.lua waits for its
  `ADDON_LOADED`; `/clicky` opens it with `SetCollectionsJournalShown(true,
  COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)`.
- The Toy Box grid's filters are the player's saved settings (see the first rule), so macros are
  listed in Clicky's own panel. Toy Box
  right-click entries hook `Menu.ModifyMenu("MENU_TOYBOX_FAVORITE", ...)`.
- Event handlers registered with `ns.RegisterEvent` run in `.toc` order (Core.lua).
