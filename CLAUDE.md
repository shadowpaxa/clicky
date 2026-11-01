# Clicky

A World of Warcraft retail addon (Interface 120105, Midnight 12.x): buttons for Toy Box favorites
and for macros the player makes of toys, mounts, pets, spells and items from the bags. A click uses
a random one from the macro; a right-click opens a drawer of what it holds, and clicking one there
uses it.

- `docs/macros-user-journeys.md`: what players see and do. Check every change against it.
- `README.md`: for players. Keep it true when behavior changes; it isn't repeated here.
- Each `.lua` file's header lists its `ns` API (and which functions are there only for tests).
  Keep those lists current; they're the code map.

Players see only "macros", never "sets". Messages, panel counts and README call what a macro holds
"items" (a toy, a mount, a pet, a spell or a thing from the bags); Favorites holds only toys, so its
messages say "toys" (`ns.MacroNoun`).

## Rules

**Never change the player's settings.** Clicky changes only its own macros, its own buttons, a
toy's, mount's or pet's star when the player picks that from its menu, and a toy's gift wrap when
the player clicks the toy to open it, as the Toy Box does. Never Toy Box, Mount Journal or Pet
Journal filters, CVars or any other game setting: they're the player's, saved by WoW, and outlive
the addon. An earlier Clicky "restored" the Toy Box filters and left a player's Toy Box empty. The
test "Never changes the player's settings" fails on any such call.

**One code path per behavior.**
- Every change the player asks for goes through `SetEntry`, `MakeMacro`, `RenameMacro`,
  `SetMacroIcon` or `DeleteMacro` (and `PickupMacro`, which makes Favorites' macro), and every
  automatic write (separating copies) through `ns.Sync` (Macros.lua); every macro read or write
  through MacroStore.lua; every UI refresh through `ns.Changed()` (a view registers its refresh with
  `ns.RegisterView`, Core.lua), except the grid's own redraws (Grid.lua's header lists them),
  which redraw only the grid. An entry's menu is `ns.OpenEntryMenu` in the grid and
  `ns.OpenMacroEntryMenu` for an item under a macro in the panel (Menu.lua). An entry's (a toy's,
  mount's, pet's, spell's or item's) name, sort order, icon, tooltip, cooldown, owned and usable
  test, star and secure action are its kind's owner file's (Toys.lua, Mounts.lua, Pets.lua,
  Spells.lua, Items.lua), reached through Entries.lua, for the panel, the drawers, the macro
  buttons and the grid alike; which entries a macro holds is `ns.MacroEntries` (Macros.lua).
- Refusals return `nil, reason`; the caller shows the reason.
- Extend the owning file's `ns` API rather than reaching into another file's locals. A new
  concern gets a new file, added to the `.toc`.

**Don't break players' bars or data.**
- A macro is the only copy of its items. Clicky has no saved variables.
- Every macro's line is `/click [btn:2]ClickyP<code>;Clicky<code>`, 36 characters: the code is
  four random consonants (`BCDFGHJKLMNPQRSTVWXZ`). Favorites' is
  `/click [btn:2]ClickyPFVRT;ClickyFVRT` (`FVRT` is reserved, no macro is given it), and its macro
  is found by that line, not its name.
  Never rename the `Clicky<code>` or `ClickyP<code>` buttons or change that line, except to give
  a copied macro its own code (both buttons). Any other `/click` line isn't a Clicky macro's.
- Changing the `#clicky` format means a new format version in Codec.lua. Macros are written in
  format 1 (with a checksum), the only format read; a later format reads as saved by a newer
  Clicky, anything else as damaged. A later format keeps the first character as its number and the
  checksum at the end: that's how an earlier release tells it from a damaged line. An unreleased
  format may change in place. Favorites' macro has no `#clicky` line.
- **A release never breaks players' macros.** Every later version reads format 1 and the places in
  `ToyList.lua`; a new format is read alongside format 1, never instead of it.
- An entry's number in a macro (a toy, mount, pet look, spell or item: Entries.lua) is its place in
  `ToyList.lua`, which only grows at the end (`tools/update_toys.py` appends;
  `tests/check_toylist.py` checks against every release tag from v1.0.0 on). Never reorder it or
  remove from it.
- A macro Clicky can't read has no items and takes no changes. It must not read as other items.

**Debuggability.** Log every state change with `ns.Trace(format, ...)` (guard costly arguments
with `ns.IsTracing()`). New state gets a line in `/clicky debug`. Comments explain WoW
constraints and non-obvious reasons, not what the code does.

## Tests

`tests/run.sh` must pass before every commit (setup is in its header); CI runs it on every push,
before each release and weekly, so a patch is checked without a push (`.github/workflows/ci.yml`).
It runs luacheck (`.luacheckrc`: a WoW global Clicky starts using goes in its `read_globals`),
`tests/test_journeys.lua` (busted under LuaJIT, which is Lua 5.1 like WoW), `tests/test_docs.lua`
(README.md's limits, commands, messages and labels against the code), `tests/test_toylist.lua`
(the list's append-only check and the update script), `tests/test_random_play.lua` and
`tests/test_random_play_accounts.lua` (fixed-seed random sequences of what a player does, on one
computer and on two, checking after every step that macros, buttons, drawers and the grid agree,
and that each macro made through Clicky holds what the player put in it, from macros of a few
items to dozens), `tests/check_api.py` (lua-language-server with Ketho's annotations, plus every
Blizzard name Clicky uses checked against Blizzard's live UI source, and every `C_` or global
function Clicky calls whose returns Blizzard marks secret against the list of those Clicky
handles; `tests/fetch.sh` refreshes both) and `tests/check_toylist.py` (ToyList.lua against every
release tag from v1.0.0 on that the commit contains, so CI fetches tags).

- Tests are named after the journeys and call what the UI is built on: the Macros API,
  `ns.PanelRows`, `ns.OpenEntryMenu`, `ns.OpenMacroEntryMenu`, `ns.GridSections`, `ns.GridRows`,
  `ns.GridView`, the grid's buttons (`world.env.ClickyGrid.buttons`), the panel's rows
  (`world.scrollList.rows`) and the drawers' buttons, clicked through `World:MouseClick` or by
  calling their scripts. `tests/wow.lua` stubs only the game state and the Blizzard frames and
  widgets Clicky relies on, citing Blizzard's documentation or source; keep it one file. Its
  header says how a test builds a world (a second computer, Clicky's toy list as an older or newer
  Clicky has it), changes the game and answers menus and dialogs.
- UI behavior is shown by tests or relies only on behavior Blizzard's source shows. A widget method
  no stub defines is missing, so calling one is an error, as in the game; one Clicky calls only for
  looks goes in `LOOKS`.
- Test what a look at the UI wouldn't show: the format and its size maths, sync across computers,
  patches, combat, refusals and their reasons.
- Assert on Clicky's results (macro bodies, button attributes, errors via `world:TakeErrors()`,
  return values), not on what the stubs did.
- A logic change updates its tests in the same commit. A bug fix gets a test that fails without
  the fix. Break the code once to see a new test fail before trusting it.
- Logic worth testing lives in plain functions on `ns`, marked "for tests" in the file header.

WoW runs Lua 5.1: no `goto`, `//`, bitwise operators or other 5.2+ syntax.

## Commits and releases

- `main` is on GitHub (public `shadowpaxa/clicky`). Add new commits; don't amend or force-push
  pushed history. Commits are authored `shadowpaxa <shadowpaxa@gmail.com>` and pushed as the
  shadowpaxa GitHub account (this clone's `.git/config` sets both, with `gh auth git-credential`
  as GitHub's credential helper; set them in any new clone). The repo is public: nothing personal
  beyond that goes in it.
- Release: add a section to the top of `CHANGELOG.md` (`.pkgmeta`'s manual-changelog makes it the
  release notes) and commit everything else, then run `tools/release.sh v1.1.0` (its header says
  what it does; it runs only on `main`). A tag with `alpha` or `beta` releases as that; any other
  tag as a full release (BigWigsMods packager, release.sh). The tag runs CI, then
  `.github/workflows/release.yml` packages and uploads to Wago (project `mKOa3ENx`, secret
  `WAGO_API_TOKEN`) and CurseForge (project `1777128`, secret `CF_API_TOKEN`). Check the run
  with `gh run list -R shadowpaxa/clicky`.

## README

README.md is for players, and short: about 100 lines. Review step 4 checks it against these rules:

- **Every sentence is one a player needs.** Ask of each: would a player using Clicky miss it? If
  not, it goes: what the UI already shows (labels, counts, highlights, how scrolling works), rare
  cases, history and old versions, and how Clicky works inside. The journeys hold the full
  behavior; README isn't a copy of them.
- **Written like a person.** Explain Clicky as you would to a friend: plain, connected sentences,
  "you" for the player, no internal terms. Say a thing once.
- **The first screen gets a player going:** what Clicky does in a few sentences, a picture, which
  WoW it's for (the `.toc`'s Interface), how to install it, and the steps to a working button.
- **Troubleshooting only for what the game doesn't explain.** A message that already says what to
  do needs no entry. It ends with where to get help: the comments on Clicky's Wago page.
- **Limits are one line each:** the number, and what to do about it.
- **Its facts are tested.** Each limit, message, command and label README gives has a check in
  tests/test_docs.lua. Each picture's file exists and has alt text (tested); a release review
  checks the pictures show the current UI.

## Reviews

Review before every commit of a change and before every release, against a base (the last
release tag from v1.0.0 on for a release, and none for 1.0.0 itself: the whole addon; `HEAD` for a
commit). Do every step; write each finding down; fix; then
start again from step 1. Done means one full pass with no findings.

1. **What the player sees.** Make a list of every difference a player can see or do, by walking
   each journey in docs/macros-user-journeys.md at the base and now, and by diffing every string
   the player can see (messages, refusals, labels, tooltips, slash command output) between the
   base and now. Include what changed for Favorites, for other computers, for older and newer
   Clicky versions, in combat, and across patches.
2. **The changelog.** The release's `CHANGELOG.md` section is short: what a player has to do
   (remake macros, update other computers), what they lose (a limit lowered, a feature removed),
   the new features, one bullet each, and fixes to bugs a player would have hit. Details that
   playing shows (labels, scrolling, combat edge cases, debug output) stay in the journeys, not
   the changelog. Every changelog sentence is true of the code being released,
   including what an older Clicky does with new macros (read that version's code at its tag).
3. **The docs.** Each item from step 1 is said once, where it belongs: what a player sees in the
   journeys; a rule, or a WoW constraint more than one file meets, in CLAUDE.md; what one file does
   in its header and comments. README.md says it only if a player needs it (the README rules
   above). Grep for every name, message, number and term the change removed or renamed: no stale
   mention is left.
4. **Readable prose.** Read each changed passage of the changelog, README.md and the journeys as
   a player would. Each changelog bullet leads with what the player notices, then says what to
   do, if anything. Sentences are short and plain; one idea per bullet; no internal terms
   (formats, function names, code) in player-facing text. A change in behavior says what it was
   and what it is now. Then read the whole section in one go: no two bullets seem to contradict,
   and each says where it applies (this computer, other computers, older versions). README.md
   meets every rule under "README" above: write down each sentence a player wouldn't miss, and
   cut it.
5. **Every claim.** For each sentence added to docs, comments and the changelog, name where it's
   confirmed: a line of code, a test, or a cited Blizzard source. Game behavior not seen in play
   and not in Blizzard's source comes out. Names and examples given to players (a toy, a mount,
   the README's Ideas) aren't claims to check: they're from play. Look hardest at absolutes,
   reasons and claims about other versions.
6. **Tests.**
   - Each new or changed behavior has a test that checks its result, seen to fail with the code
     broken the way changes here go wrong: a macro losing, gaining or swapping an item, the
     255-character limit off by one, another computer or a copy reading it differently, combat, a
     refusal.
   - Tests read state through Clicky's `ns` API, not `/clicky debug` or trace text, unless that
     text is what's tested.
   - Each stub behavior a test relies on cites Blizzard's source, and a stub added or changed does
     what that source does, not less (a click that skipped the button's `OnClick` hid a bug).
   - No stub, helper or test that nothing needs. A test of an improbable case goes if it breaks on
     unrelated changes and getting the case wrong would lose no items, break no bar and raise no
     Lua error.
   - A function `tests/check_api.py` asks to add to `HANDLED_SECRET` is added only once the code
     neither compares its secret returns nor hands them to a widget that refuses them.
7. **Scripts and edge cases.** Run every changed script, or its logic in a throwaway repository or
   on temporary files, including: nothing to do, running twice, the wrong branch, missing or bad
   input.
8. **Each commit on its own.** Its code, tests, docs and numbers agree with each other without
   the next commit.

## WoW constraints

Each file's comments explain the constraints only it meets; these are met across files.

- `UseToy()` is protected (warcraft.wiki.gg API UseToy), so each macro `/click`s a hidden
  `SecureActionButtonTemplate` button that does the entry's secure action (SECURE_ACTIONS in
  SecureTemplates.lua). There's none for mounts or pets; each kind's file says what its button does
  (Toys.lua, Mounts.lua, Pets.lua, Spells.lua, Items.lua), and EntryButton.lua why it acts on an up
  click.
- Macro bodies hold 255 characters (MacroFrameText `letters="255"`; EditMacro saves only the first
  255, warcraft.wiki.gg API EditMacro), names 16 (the name box has `letters="16"`); 120 general
  macros per account and 30 per character (MacroConstantsDocumentation.lua). General macros are
  sorted by name (warcraft.wiki.gg API EditMacro), so creating or renaming one can move others,
  and a copy can be listed before its original. The `#clicky` line does nothing when the macro
  runs (seen in play). `|` is WoW's escape character, so it never appears in data.
- In combat, secure attributes can't be set from addon code, macros can't be created, edited or
  deleted (warcraft.wiki.gg API CreateMacro, EditMacro, DeleteMacro: nocombat), and protected
  frames can't be created. The player's macro changes (making, renaming or deleting a macro, adding
  or removing an item, dragging it) are refused in combat; separating copies, making or emptying
  buttons, making or filling drawers, and making the grid and refreshing it wait for
  `PLAYER_REGEN_ENABLED`. Buttons can't be destroyed, so a deleted macro's button is emptied
  and drawer buttons are reused. Addon code can't set a protected frame's attributes or move,
  resize, show or hide it, and the lock spreads to its parents and to the frames it is anchored to
  (warcraft.wiki.gg Secure Execution and Tainting); Grid.lua says what that keeps still.
- Macros and drawers work in combat through secure snippets: a macro's button picks with
  `random` from a list handed to it as attributes (each entry's key and its secure action's type,
  attribute and value), and the drawer opens and hides in secure code. `PLAYER_REGEN_DISABLED` is
  the last chance to hand those lists over and fill the drawers (it's synchronous,
  UnitDocumentation.lua, and SecureStateDriver.lua sets attributes on it).
- Some functions return secret values when the game restricts addons (Blizzard's documentation
  marks them, as `C_Spell.GetSpellCooldown`'s `SecretWhenCooldownsRestricted`). Clicky doesn't
  compare them or hand them to a widget that refuses them; `tests/check_api.py`'s `HANDLED_SECRET`
  lists each one Clicky calls, and the file that calls it says what it shows instead.
- The grid (Grid.lua) lists only entries in ToyList.lua, since a macro can't hold any other; each
  kind's file says which of its entries a player can add and what changes them.
- If macros aren't readable at `ADDON_LOADED`, nothing is read or written until `UPDATE_MACROS`.
- Clicky's toy list is shipped (ToyList.lua), written from the game's tables for the live build via
  wago.tools (`tools/update_toys.py` names them), not read from the game at login.
- `Blizzard_Collections` (the Toy Box) is load-on-demand: Panel.lua and Grid.lua wait for it with
  `EventUtil.ContinueOnAddOnLoaded` (Blizzard_SharedXML/EventUtil.lua); `/clicky` opens it with
  `SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)`.
- The Toy Box's filters are the player's saved settings (see the first rule), so Clicky's grid
  (Grid.lua) has its own search and filters and only hides the Toy Box's grid, paging, search box,
  filter button and progress bar. Macros are listed in Clicky's own panel.
