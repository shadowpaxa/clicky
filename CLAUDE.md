# Clicky

A World of Warcraft retail addon (Interface 120105, Midnight 12.x): random-toy buttons for
Toy Box favorites and for toy macros the player makes.

- `docs/macros-user-journeys.md`: what players see and do. Check every change against it.
- `README.md`: for players. `docs/architecture.md`: the design, for people reading the code.
  Keep both true when behavior or design changes. Neither is repeated here.
- Each `.lua` file's header lists its `ns` API (and which functions are there only for tests).
  Keep those lists current; they're the code map.

Players see only "macros", never "sets"; that older name survives only in the `ClickySet<id>`
button names, which bars depend on.

## Rules

**Never change the player's settings.** Clicky changes only its own macros, its own buttons, its
own saved data, and a toy's star when the player picks that from its menu. Never Toy Box filters,
CVars or any other game setting: they're the player's, saved by WoW, and outlive the addon. An
earlier Clicky "restored" the Toy Box filters and left a player's Toy Box empty. The test "Never
changes the player's settings" fails on any such call.

**One code path per behavior.**
- Every macro change goes through `SetToy`, `MakeMacro`, `RenameMacro` or `DeleteMacro`
  (Macros.lua); every write to WoW through MacroStore.lua; every UI refresh through `ns.Changed()`.
  Both toy menus share `AddMacroEntries` (Menu.lua).
- Refusals return `nil, reason`; the caller shows the reason.
- Extend the owning file's `ns` API rather than reaching into another file's locals. A new
  concern gets a new file, added to the `.toc`.

**Don't break players' bars or data.**
- A macro is the only copy of its toys; nothing that defines them goes in `ClickyDB`.
- Never rename the `ClickyButton` / `ClickySet<id>` buttons or change the
  `/click [nocombat] <button>` line, except to give a copied macro its own id.
- Changing the `#clicky` format means a new format version in Codec.lua that still reads the old
  ones (3 is current; 2 is read and re-saved as 3; 1 reads as damaged).
- Changing `ClickyDB`'s shape means bumping `DB_VERSION` and adding `migrations[DB_VERSION]` in
  DB.lua. Unversioned data is version 0. Never rename existing keys.
- A macro Clicky can't read has no toys and takes no changes. It must not read as other toys.

**Debuggability.** Log every state change with `ns.Trace(format, ...)` (guard costly arguments
with `ns.IsTracing()`). New state gets a line in `/clicky debug`. Comments explain WoW
constraints and non-obvious reasons, not what the code does.

## Tests

`tests/run.sh` must pass before every commit (setup is in its header); CI runs it on every push
and before each release (`.github/workflows/ci.yml`). It runs luacheck (`.luacheckrc`: a WoW
global Clicky starts using goes in its `read_globals`), `tests/test_journeys.lua` (busted under LuaJIT, which is Lua 5.1 like WoW), `tests/test_docs.lua`
(README.md's limits, commands, messages and labels against the code) and
`tests/check_api.py` (lua-language-server with Ketho's annotations, plus every Blizzard name
Clicky uses checked against Blizzard's live UI source; `tests/fetch.sh` refreshes both).

- Tests are named after the journeys and call what the UI is built on: the Macros API,
  `ns.PanelRows`, `ns.ToyMenuEntries`. `tests/wow.lua` stubs only game state Clicky relies on,
  citing Blizzard's documentation or source; keep it one file. A second computer on the same
  account is `wow.New({ account = world.account })`; `world:AddToy` adds a toy to the game.
- Blizzard's UI (Toy Box, menus, dialogs, tooltips) isn't stubbed. How Clicky's UI looks and
  responds is checked by playing; say so instead of claiming it works.
- Test what playing can't easily show: the format and catch-up maths, sync across computers,
  patches, combat, refusals and their reasons, picks.
- Assert on Clicky's results (macro bodies, button attributes, errors via `world:TakeErrors()`,
  return values), not on what the stubs did.
- A logic change updates its tests in the same commit. A bug fix gets a test that fails without
  the fix. Break the code once to see a new test fail before trusting it.
- Logic worth testing lives in plain functions on `ns`, marked "for tests" in the file header.

WoW runs Lua 5.1: no `goto`, `//`, bitwise operators or other 5.2+ syntax.

## WoW constraints

- `UseToy()` is protected, so each macro `/click`s a hidden `SecureActionButtonTemplate` button
  (`type` = `toy`). `useOnKeyDown` is false because `/click` sends an up click.
- Macro bodies hold 255 characters (MacroFrameText `letters="255"`; EditMacro truncates), names
  16; 120 general and 30 character macros per account (MacroConstantsDocumentation.lua). Lines
  starting with `#` aren't run. `|` is WoW's escape character, so it never appears in data.
- In combat, secure attributes can't be set, macros can't be created, edited or deleted, and
  protected frames can't be created. Macro changes are refused in combat; re-saves, separating
  copies, and making or emptying buttons wait for `PLAYER_REGEN_ENABLED`. Buttons can't be
  destroyed, so a deleted macro's button is emptied.
- Macros may not be readable at `ADDON_LOADED`. Until they are, nothing is read or written;
  `UPDATE_MACROS` syncs when they arrive.
- The game's toy list comes from `C_ToyBox.GetToyLink` on every item ID, stopping 50,000 IDs past
  the last toy found (the widest gap between toys is 11,406).
- `Blizzard_Collections` (the Toy Box) is load-on-demand: Panel.lua waits for its
  `ADDON_LOADED`; `/clicky` opens it with `SetCollectionsJournalShown(true,
  COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)`.
- Addons can't filter the Toy Box grid, so macros are listed in Clicky's own panel. Toy Box
  right-click entries hook `Menu.ModifyMenu("MENU_TOYBOX_FAVORITE", ...)`.
- Event handlers registered with `ns.RegisterEvent` run in `.toc` order, so DB.lua migrates
  `ClickyDB` before Toys.lua and Macros.lua read it.
- `UI_ERROR_MESSAGE`'s payload can be secret in Midnight instances, so only its timing is used.
