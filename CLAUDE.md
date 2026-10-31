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
- Every change the player asks for goes through `SetEntry`, `MakeMacro`, `RenameMacro` or
  `DeleteMacro` (and `PickupMacro`, which makes Favorites' macro), and every automatic write
  (separating copies) through `ns.Sync` (Macros.lua); every macro read or write through
  MacroStore.lua; every UI refresh through `ns.Changed()` (a view registers its refresh with
  `ns.RegisterView`, Core.lua), except the grid's own redraws (a search, a filter, the filter reset,
  a tab, scrolling, the redraw right after opening a gift wrap, the retry after a held mouse
  button, and the mount ridden or the pet that's out changing), which don't go through
  `ns.Changed`: they redraw the grid by calling its refresh (Grid.lua `ChangedList`,
  `ShowSection`, `ScrollBar_OnScroll`, `RefreshIfShown`, `Refresh`), and the panel isn't
  refreshed. The menu of an entry, in the grid and the panel, is `ns.OpenEntryMenu`
  (Menu.lua). An entry's (a toy's, mount's, pet's, spell's or item's) name, sort order, icon,
  tooltip, cooldown, owned and usable test, star and secure action are its kind's owner file's
  (Toys.lua, Mounts.lua, Pets.lua, Spells.lua, Items.lua), reached through Entries.lua, for the
  panel, the drawers, the macro buttons and the grid alike; which entries a macro holds is
  `ns.MacroEntries` (Macros.lua).
- Refusals return `nil, reason`; the caller shows the reason.
- Extend the owning file's `ns` API rather than reaching into another file's locals. A new
  concern gets a new file, added to the `.toc`.

**Don't break players' bars or data.**
- A macro is the only copy of its items. Clicky has no saved variables.
- Every macro's line is `/click [btn:2]ClickyP<code>;Clicky<code>`, 36 characters: the code is
  four random consonants (`BCDFGHJKLMNPQRSTVWXZ`). Favorites' is `/click [btn:2]ClickyPFVRT;ClickyFVRT`
  (`FVRT` is reserved, no macro is given it), and its macro is found by that line, not its name.
  Never rename the `Clicky<code>` or `ClickyP<code>` buttons or change that line, except to give
  a copied macro its own code (both buttons). Any other `/click` line isn't a Clicky macro's.
- Changing the `#clicky` format means a new format version in Codec.lua. Macros are written in
  format 6 (with a checksum), the only format read; anything else reads as damaged. An unreleased
  format may change in place. Favorites' macro has no `#clicky` line.
- **A release never breaks players' macros.** Every later version reads format 6 and the places in
  `ToyList.lua`; a new format is read alongside format 6, never instead of it. Earlier formats read
  as damaged, with no migration.
- An entry's number in a macro (a toy, mount, pet look, spell or item: Entries.lua) is its place in
  `ToyList.lua`, which only grows at the end (`tools/update_toys.py` appends;
  `tests/check_toylist.py` checks against every tagged release). Never reorder it or remove from it.
- A macro Clicky can't read has no items and takes no changes. It must not read as other items.

**Debuggability.** Log every state change with `ns.Trace(format, ...)` (guard costly arguments
with `ns.IsTracing()`). New state gets a line in `/clicky debug`. Comments explain WoW
constraints and non-obvious reasons, not what the code does.

## Tests

`tests/run.sh` must pass before every commit (setup is in its header); CI runs it on every push
and before each release (`.github/workflows/ci.yml`). It runs luacheck (`.luacheckrc`: a WoW
global Clicky starts using goes in its `read_globals`), `tests/test_journeys.lua` (busted under
LuaJIT, which is Lua 5.1 like WoW), `tests/test_docs.lua` (README.md's limits, commands, messages and labels against the code),
`tests/test_toylist.lua` (the list's append-only check and the update script),
`tests/test_random_play.lua` and `tests/test_random_play_accounts.lua` (fixed-seed random
sequences of what a player does, on one computer and on two, checking after every step that
macros, buttons, drawers and the grid agree),
`tests/check_api.py` (lua-language-server with Ketho's annotations, plus every Blizzard name
Clicky uses checked against Blizzard's live UI source; `tests/fetch.sh` refreshes both) and
`tests/check_toylist.py` (ToyList.lua against every tag the commit contains, so CI fetches tags).

- Tests are named after the journeys and call what the UI is built on: the Macros API,
  `ns.PanelRows`, `ns.OpenEntryMenu`, `ns.GridSections`, `ns.GridRows`, `ns.GridView`, the grid's
  buttons (`world.env.ClickyGrid.buttons`), the panel's rows (`world.scrollList.rows`) and the
  drawers' buttons, clicked through `World:MouseClick` or by calling their scripts. `tests/wow.lua`
  stubs only the game state and the Blizzard frames and widgets Clicky relies on, citing Blizzard's
  documentation or source; keep it one file. A second computer on the same account is `wow.New({
  account = world.account })`; `world:AddToy` adds a toy to the game, `world:AddSpell` a spell (on a
  spellbook skill line, in a flyout or a profession's), `world:AddItem` an item (in a bag or worn),
  `world:AddMount` a mount and `world:AddPet` (or `world:LearnPet`) a pet the player owns.
  Clicky's toy list (ToyList.lua) is `wow.New`'s `toyList` option: a toy's item ID, `"s<id>"` for a spell, `"i<id>"`
  for an item, `"m<id>"` for a mount, `"p<species>:<display>"` for a pet look; without it the list
  is the account's toys when the world is made; its `TOY_HIDDEN` is the `toyHidden` option. A test
  that adds or removes game toys passes it explicitly, so places don't move; a shorter or longer
  `toyList` is an older or newer Clicky.
- UI behavior is shown by tests (`tests/wow.lua` stubs the Blizzard frames and widgets Clicky relies
  on: the Toy Box's frames, `World:LoadCollections`, a scroll bar, a scroll list, a filter menu,
  frame sizes, anchors and visibility, and the combat lock on protected frames, each citing
  Blizzard's source) or relies only on behavior Blizzard's source shows. Menus and dialogs are
  Blizzard's own and aren't stubbed; a test replaces `ns.OpenEntryMenu` to see what opens.
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
  release notes) and commit everything else, then run `tools/release.sh v1.1.0`. It runs
  `tools/update_toys.py` (appends the toys patches added to ToyList.lua), checks the changelog's
  top section is `## 1.1.0`, runs `tests/run.sh`, commits ToyList.lua and CHANGELOG.md as
  "Clicky 1.1.0" if either changed, pushes, then pushes an annotated tag. It refuses to run off
  `main`.
  A tag with `alpha` or `beta` releases as that; any other tag as a full release (BigWigsMods
  packager, release.sh). The tag runs CI, then `.github/workflows/release.yml` packages and
  uploads to Wago (project `mKOa3ENx`, secret `WAGO_API_TOKEN`). Check the run with `gh run list -R shadowpaxa/clicky`.

## README

README.md is for players, and short: about 100 lines. Review step 4 checks it against these rules:

- **Every sentence is one a player needs.** Ask of each: would a player using Clicky miss it? If
  not, it goes: what the UI already shows (labels, counts, highlights, how scrolling works), rare
  cases, history and old versions, and how Clicky works inside. The journeys hold the full
  behavior; README isn't a copy of them.
- **Concise.** Short plain sentences, one fact each, no internal terms. Say a thing once.
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
release tag for a release, `HEAD` for a commit). Do every step; write each finding down; fix; then
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
3. **The docs.** The journeys, CLAUDE.md and each file's header say each item from step 1;
   README.md says it only if a player needs it (the README rules above). Grep for every name,
   message, number and term the change removed or renamed: no stale mention is left.
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
   and not in Blizzard's source comes out. Look hardest at absolutes, reasons and claims about
   other versions.
6. **Tests.** Each new behavior has a test that was seen to fail with the code broken, and no
   test relies on a stub behavior that `tests/wow.lua` doesn't cite.
7. **Scripts and edge cases.** Run every changed script, or its logic in a throwaway repository or
   on temporary files, including: nothing to do, running twice, the wrong branch, missing or bad
   input.
8. **Each commit on its own.** Its code, tests, docs and numbers agree with each other without
   the next commit.

## WoW constraints

- `UseToy()` is protected (warcraft.wiki.gg API UseToy), so each macro `/click`s a hidden
  `SecureActionButtonTemplate` button (`type` = `toy`, or `spell` / `item` for those entries, with
  the attribute of the same name: SECURE_ACTIONS in SecureTemplates.lua; an item's value is
  `"item:"` and its ID because a bare number there is an inventory slot, `SecureCmdItemParse`).
  There's no secure action for mounts or pets: a mount is `spell` with its spell's name, cast as
  `/cast` does (by ID it wasn't summoned, seen in play), a pet `macro` with `macrotext` `/summonpet
  <GUID>`, which calls `C_PetJournal.SummonPetByGUID` (SlashCommands.lua); summoning the pet that's
  out puts it away (`/dismisspet`, SlashCommands.lua), so a click never picks it (Pets.lua).
  `useOnKeyDown` is false because `/click` sends an up click (SlashCommands.lua).
- Macro bodies hold 255 characters (MacroFrameText `letters="255"`; EditMacro saves only the first
  255, warcraft.wiki.gg API EditMacro), names 16 (the name box has `letters="16"`); 120 general
  macros per account and 30 per character (MacroConstantsDocumentation.lua). General macros are
  sorted by name (warcraft.wiki.gg API EditMacro), so creating or renaming one can move others,
  and a copy can be listed before its original. The `#clicky` line does nothing when the macro
  runs (seen in play). `|` is WoW's escape character, so it never appears in data.
- In combat, secure attributes can't be set from addon code, macros can't be created, edited or
  deleted (warcraft.wiki.gg API CreateMacro, EditMacro, DeleteMacro: nocombat), and protected
  frames can't be created. Macro changes (items, name) are refused in
  combat; separating copies, making or emptying buttons, making or filling drawers, and
  making the grid and refreshing it wait for `PLAYER_REGEN_ENABLED`. Buttons can't be destroyed, so a deleted macro's button is
  emptied and drawer buttons are reused.
- Macros and drawers work in combat through secure snippets: a macro's button picks with
  `random` from a list handed to it as attributes (each entry's key and its secure action's type,
  attribute and value), and the drawer opens and hides in secure code. An item that can be worn
  is never in that list: the secure "item" action wears it if it isn't worn
  (SecureTemplates.lua), so it is drawer-only.
  `PLAYER_REGEN_DISABLED` is the last chance to hand those lists over and fill the drawers
  (it's synchronous, UnitDocumentation.lua, and SecureStateDriver.lua sets attributes on it).
- A spell's cooldown is secret when the game restricts addons (`C_Spell.GetSpellCooldown` is
  `SecretWhenCooldownsRestricted`, SpellDocumentation.lua): its start and duration are secret
  values, which Clicky doesn't compare or hand to a cooldown frame (`Cooldown:SetCooldown` takes
  secret arguments only from untainted code, FrameAPICooldownDocumentation.lua), but `isActive` is
  never secret (SpellSharedDocumentation.lua). So a spell whose cooldown is active and whose duration is secret
  counts as on cooldown and shows no swipe (Spells.lua).
- The grid lists, on tabs after the toys', the mounts, pets, spells and items a player can add
  (Grid.lua), only those in ToyList.lua, since a macro can't hold any other. Spells are the
  spellbook's: its skill lines' active spells and the known spells in its flyouts
  (`C_SpellBook.GetSpellBookSkillLineInfo` and `GetSpellBookItemInfo`; `GetFlyoutInfo` and
  `GetFlyoutSlotInfo`, which Blizzard's own spell search calls on flyouts,
  Blizzard_SpellSearchTextFilter.lua), and the professions' spells, as the Professions book
  finds them (`GetProfessions` and `GetProfessionInfo`'s spell count and offset,
  Blizzard_ProfessionsBook.lua), not passive and not off-spec. Items are those in the bags (the
  backpack, the equipped bags and the reagent bag: `0` to `NUM_TOTAL_EQUIPPED_BAG_SLOTS`,
  Constants.lua) and the worn ones (`INVSLOT_FIRST_EQUIPPED` to `INVSLOT_LAST_EQUIPPED`); the bank
  isn't looked at. Spells and items change with `SPELLS_CHANGED`, `BAG_UPDATE_DELAYED` and
  `PLAYER_EQUIPMENT_CHANGED` (through `ns.Changed`, so in combat the grid waits), and their
  cooldowns with `SPELL_UPDATE_COOLDOWN` and `BAG_UPDATE_COOLDOWN` (ContainerDocumentation.lua).
  Mounts are `C_MountJournal.GetMountIDs`' collected ones, less those hidden on this character; pets
  one entry per species and look (`displayID`) the player owns (`C_PetJournal.GetOwnedPetIDs`); both
  lists ignore the journals' filters. They change with `NEW_MOUNT_ADDED`,
  `MOUNT_JOURNAL_USABILITY_CHANGED` and `PET_JOURNAL_LIST_UPDATE`, and the mount ridden and the pet
  that's out with `COMPANION_UPDATE` (Grid.lua: only the buttons in view are redrawn, at once),
  which the drawers and the grid mark as the journals do (`ActiveTexture`). A pet shows its cooldown
  (`GetPetCooldownByGUID`) as the Pet Journal does, which after a summon the game gives some pets
  and not others, in the Pet Journal too (seen in play); a mount none, as in the Mount Journal. The
  game stars and picks up a mount only by its place in the Mount Journal's filtered list
  (`SetIsFavorite`, `Pickup`: displayIndex), so a mount the filters hide can't be starred or dragged
  from Clicky. Toys, Mounts and Pets each have their own Filter menu, built as the Toy Box's and the
  journals' (GridFilters.lua), with the game's API for each entry's data where it has it; Not
  Collected leaves out `MOUNT_HIDDEN` and `PET_HIDDEN` (ToyList.lua, from the tables' Flags) as the
  toys' leaves out `TOY_HIDDEN`. `/clicky debug` checks each tab against its Blizzard window, with
  that window's own filters, entry by entry, and its defaults when it's on them, and which Sources
  box a source number is under against every mount's and species' source text (BlizzardCheck.lua): a
  mount's `sourceType` counts from 1, as the boxes do, where `Enum.BattlePetSources` (the toys' and
  pets') counts from 0 (seen in play). Toys, mounts and pets have a star; only a toy a gift wrap and
  a NEW label; Favorites is the Toy Box's stars, so it takes toys only.
- If macros aren't readable at `ADDON_LOADED`, nothing is read or written until `UPDATE_MACROS`.
- Clicky's toy list is shipped (ToyList.lua), written from the game's Toy, SkillLineAbility,
  SpecializationSpells, TraitDefinition, PvpTalent, ItemXItemEffect, ItemEffect, Spell, Mount,
  MountType, BattlePetSpecies, Creature, CreatureXDisplayInfo and BattlePetDisplayOverride tables for the live
  build via wago.tools (`tools/update_toys.py`), not read from the game at login. The grid lists its
  `TOY_HIDDEN` (the Toy table's Flags 2 bit) only when owned, which matches the Toy Box: with Not
  Collected on, both were seen in play to list the same 1076.
- `Blizzard_Collections` (the Toy Box) is load-on-demand: Panel.lua and Grid.lua wait for it with
  `EventUtil.ContinueOnAddOnLoaded` (Blizzard_SharedXML/EventUtil.lua); `/clicky` opens it with `SetCollectionsJournalShown(true,
  COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)`.
- The Toy Box's filters are the player's saved settings (see the first rule), so Clicky's grid
  (Grid.lua) has its own search and filters and only hides the Toy Box's grid, paging, search box,
  filter button and progress bar. Macros are listed in Clicky's own panel. The grid's entries are
  fixed secure buttons (EntryButton.lua), made once out of combat and re-pointed as it scrolls by
  whole rows. In combat the game doesn't let addon code set a protected frame's attributes or move,
  resize, show or hide it, and the lock spreads to its parents and to the frames it is anchored to
  (warcraft.wiki.gg Secure Execution and Tainting): the board the buttons sit on, and, as the page
  doesn't say how far it goes, the grid. So in combat nothing sets an attribute on, moves, shows or
  hides a button, the board or the grid; the buttons keep their entries, which still work; the
  scroll bar is off from `PLAYER_REGEN_DISABLED` and a tab changes nothing; the grid is redrawn
  through `ns.Changed` when combat ends. What is inside a button isn't named by that page, so a toy
  used in combat shows its cooldown swipe and hovering over a NEW toy clears its label: Cooldown
  SetCooldown/Clear carry IsProtectedFunction (FrameAPICooldownDocumentation.lua), the same mark as
  SetPoint/SetHeight (SimpleScriptRegionResizingAPIDocumentation.lua), which are blocked only on
  protected frames; CooldownFrameTemplate isn't protected
  (Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3); the NEW label is a font string. Opening a gift
  wrap, a chat link and the menu are plain Lua with no combat restriction in Blizzard's source or on
  warcraft.wiki.gg (see Grid.lua), so they work in combat.
- Event handlers registered with `ns.RegisterEvent` run in `.toc` order (Core.lua); an error in one
  goes to the error handler (`geterrorhandler`) and the next handlers still run.
