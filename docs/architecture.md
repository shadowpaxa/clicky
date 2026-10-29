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
`ClickyP0;ClickyButton`). Clicky reads a macro with that line and a `#clicky` line, with the number
as its id, only to show it as damaged like any other: it never rewrites its line or body, and
leaves extra macros with the same number alone. Favorites' old line has no `#clicky` line, so it
isn't a Clicky macro, and Favorites' macro is found only by its own line.

`/click` with no mouse button sends a left click, and the line goes through WoW's macro
conditionals, so a right-click goes to `ClickyP<code>`, which opens the macro's drawer, and
anything else to `Clicky<code>`, which uses a random entry.

### Entries

What a macro holds is entries: a toy, a spell or an item (a bag or worn item), each named by a
key, which is its entry in ToyList.lua (a toy's item ID, `"s"` and a spell ID, `"i"` and an item
ID). Each kind has one owner file, which registers with Entries.lua what the kind does: its name,
icon, tooltip, cooldown, whether the player has it, whether it can be used, and its secure
action. Toys.lua, Spells.lua and Items.lua are the owners, so the panel, the drawers and the macro
buttons treat a spell as they treat a toy.

A secure button uses an entry by setting its `type` to the action and the attribute that action
reads to the entry (SECURE_ACTIONS in Blizzard_FrameXML/SecureTemplates.lua):

| entry | `type` | attribute |
| --- | --- | --- |
| toy | `toy` | `toy` = the item ID |
| spell | `spell` | `spell` = the spell ID |
| item | `item` | `item` = `"item:"` and the item ID |

An item's value is not the bare ID because the item action reads a bare number as an inventory
slot (`SecureCmdItemParse`, ChatFrameUtil.lua). The same action wears an item that can be worn and
isn't worn, instead of using it, so such an item is drawer-only: a click on the macro never picks
it, and clicking it in the drawer wears it, or uses it once it is worn.

A spell's start and duration are secret values when the game restricts addons, which Clicky
doesn't compare or hand to a cooldown frame; the spell counts as on cooldown while its cooldown is
active and its duration is secret, and shows no swipe (Spells.lua has the sources).

### Random entries

Out of combat, just before the click goes through, Clicky sets the button's action to a random
pick from the macro.

```
you press the macro
  -> it clicks its hidden button
  -> Clicky puts a random entry's action on the button
  -> the button uses the entry
```

Picks skip entries you don't have, can't use here, that are on cooldown or are drawer-only, and
avoid repeating the last entry. The entry counted as used is read from the button's `entry`
attribute after the click.

In combat Clicky's own code can't set secure attributes, so on `PLAYER_REGEN_DISABLED` (the last
moment before the lockdown) it hands each button the list of entries ready then, as attributes:
for each, its key and the type, attribute and value of its action. A secure snippet wrapped around
the button's click picks from that list with `random`, also avoiding the last entry, sets the
button's `type` and that attribute, only when `SecureCmdOptionParse("[combat]1")` says the player
is in combat; out of combat the pick above stays in charge. The list can't change until combat
ends, so cooldowns during the fight aren't seen. Code: `CreateButton` and `GetCandidates` in
Macros.lua.

### Drawers

`ClickyP<code>`'s secure snippet opens the macro's drawer at the cursor: a grid of secure buttons,
one per entry in the macro the player has (Favorites: per owned starred toy), in the panel's order,
with cooldowns. Each button uses its entry, with the action of its kind. The drawer hides on a
choice, on Escape, on a second right-click and when the mouse leaves, in combat too.

Protected frames can't be created in combat and buttons can't be destroyed, so drawers are made
with the macro's button and their buttons are reused. Filling one makes a button per entry the
player has (up to 100; Favorites has no limit), so drawers are filled a few at a time after login
and after combat, when opened out of combat, and all of them on `PLAYER_REGEN_DISABLED`. Code:
Drawer.lua and EntryButton.lua (the buttons).

## The grid

Clicky's grid (Grid.lua) takes the place of the Toy Box's grid. The Toy Box's filters are the
player's saved settings, which Clicky never changes, so the grid has its own search and filters
(Collected, Not Collected, Usable Only), and the Toy Box's grid, paging, search box, filter button
and progress bar are only hidden. The grid's frame is the icons frame's own template
(`CollectionsBackgroundTemplate`), with its top corners hidden under the tabs, as Appearances hides
its own. On the Toy Box tab the window's title says Clicky: the Collections window sets its title
after showing a tab, then triggers `CollectionsJournal.TabSet`, on which the grid sets it; another
tab sets its own. The grid lists Clicky's own toy list, so a toy a patch adds shows once Clicky is
updated for that patch.

The toys, the spells the character knows and the items it carries or wears are on three tabs,
Blizzard's top tabs placed and driven as Appearances drives its Items and Sets
(`PanelTemplates_SetNumTabs`, `PanelTemplates_SetTab`); Blizzard keeps the selected one on the
grid's frame. Each tab says its count, after the search and the filters, and a click shows its
entries from the top. The search looks at every tab; the filters are the toys', and their button
shows on the Toys tab only. Only entries in ToyList.lua are listed, because a macro can't hold any
other. A toy whose Flags in the Toy table have the 2 bit (ToyList.lua's `TOY_HIDDEN`) is listed only
when owned, which matches the Toy Box: with Not Collected on, its list and the grid were seen in
play to hold the same 1076 toys. 72226, whose item has no name in the game's tables, is one. Spells
are the spellbook's: the active spells on its skill lines and the known spells in its flyouts, not
passive, not off-spec (`ns.KnownSpellEntries`, Spells.lua). Items are those in the bags (the
backpack, the equipped bags and the reagent bag) and in the worn slots; the bank isn't looked at
(`ns.CarriedItemEntries`, Items.lua). `ns.GridSections` makes the sections (`toys`, `spells`,
`items`, each with how many of its names are still loading) and `ns.GridRows` the rows of the one
shown. Favorites come first and run straight into the rest, as in the Toy Box; each has the Toy
Box's star, in the Toy Box's place. The check mark is for the player's own macros, not Favorites,
whose toys have their star. Only toys have a gift wrap, a NEW label and a star, so those stay on
toys. A click, a right-click, a shift-click and a drag work on every kind through Entries.lua (a
left click is the kind's secure action, an item that can be worn is worn instead of used when it
isn't worn, a link and a pickup are the kind's own calls). The grid redraws when the spellbook, the
bags or the worn items change (`SPELLS_CHANGED`, `BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED`,
through `ns.Changed`), and refreshes cooldowns on `SPELL_UPDATE_COOLDOWN` and `BAG_UPDATE_COOLDOWN`.

A name still loading is empty and sorts first, and its entry moves when the name arrives. After
logging in or a reload no name is loaded, so the grid's first draw waits until every name it would
list is in (each arrival refreshes it: Toys.lua, Spells.lua, Items.lua) or for 5 seconds, a load
that fails bringing no name; a name that arrives after that moves its entry. Later redraws don't
wait, so a filter or a search shows at once.

Addon code can't use a toy, so every entry in view is a secure button (`EntryButton.lua`, also what
the drawers are made of). The grid makes 12 columns by 9 rows of them once, out of combat, in a
board frame, and as it scrolls it re-points them at other entries: each button's entry, icon,
cooldown, check mark, star and place. The numbers come from Blizzard's layout (the Collections
window is 703 by 606, the Toy Box's icons frame is inset from it) and from the icon size and gap:
12 by 9 keeps the grid clear of the frame's corners, as the Toy Box's own buttons are. The grid
scrolls whole rows: the rows (`ns.GridRows`) and the 9 rows in view from the top row
(`ns.GridView`) are plain functions, and a `MinimalScrollBar` is driven directly, the way
Blizzard drives one for a message frame: it snaps to one position per first row
(`EnableSnapToInterval`), and a notch of the mouse wheel over the grid steps three rows. A burst of
changes redraws the grid once, after a short delay. A redraw waits while a mouse button is held, so
a button isn't re-pointed between a press and its release; it asks again on the grid's own timer
(one timer, however many redraws wait), not through `ns.Changed`. A wheel turn while a mouse button
is held is dropped, not queued. Opening a gift wrap redraws the grid at once, so the next click on
the toy uses it.

Each button's only secure action is a plain left click's (`type1`); a click with a modifier key
held, or a right click, looks up other attributes, which are unset. What those clicks do (the
menu, a chat link, as in the Toy Box) is plain Lua in the button's `PostClick`, as is opening a toy
still in its gift wrap, which its first click does instead of using it
(`C_ToyBoxInfo.ClearFanfare`); a wrapped toy's button has no `type1` until the next refresh.
The grid is built into a hidden frame and becomes the grid, and the Toy Box's own grid is hidden,
only when the build has finished, so an error while building leaves the Toy Box as it was. It is
drawn when made, so showing the Toy Box tab for the first time in combat finds it drawn. The Toy
Box's grid, paging, search box, filter button and progress bar are hidden once, and its mouse wheel
is turned off, so a wheel over the Toy Box outside the grid doesn't turn its hidden pages. If the
Toy Box lacks one of the first four, nothing is made or hidden, and the Toy Box keeps its own grid.

In combat the grid's buttons keep the entries they had, which still work; the scroll bar is turned
off when combat starts (`PLAYER_REGEN_DISABLED`), and a tab changes nothing; and the list is not
redrawn (a search, a filter, a toy learned or starred) until combat ends, when the grid is redrawn once through `ns.Changed`. A
toy used in combat shows its cooldown swipe, and hovering over a toy learned this session clears its
NEW label. The click's plain Lua (the menu, a chat link, opening a gift wrap) works in combat. If
the Collections window loads in combat, the grid is made when combat ends. Why a protected button
can't be changed in combat, and what Blizzard's source says about the parts inside it, is in
CLAUDE.md's WoW constraints and the comment above `ShowFrom` in Grid.lua.

## Where the entries are stored

WoW saves macros on Blizzard's servers and syncs them to every computer, while addon saved data
stays on one computer. So a macro's entries are stored in the macro, in a `#clicky` line that WoW
skips when running the macro:

```
/click [btn:2]ClickyPBCDF;ClickyBCDF
#clicky wDAvT1t
```

A macro body is limited to 255 characters, and up to 100 entries have to fit. Clicky ships a list
of every toy in the game (ToyList.lua, item IDs, followed by spells and items: the spells a
character can learn: those the game's skill lines teach, SkillLineAbility, a specialization's own,
SpecializationSpells, the talents, TraitDefinition (with the spell a talent replaces or shows as),
and the PvP talents, PvpTalent; and the items with a "Use:" effect, ItemXItemEffect
and ItemEffect's TriggerType 0, unless the spell's text is shown only to characters who know
another spell, as the Earthen's gem eating is; less the toys), numbers each entry by its place in
the list, stores the numbers of the macro's entries, and compresses the gaps between them.

The list only ever grows at the end, so an entry's number never changes: a patch changes no macro,
and a toy taken out of the game keeps its place and stays in its macros until the player removes it.
`tools/update_toys.py` writes the list from the game's Toy, SkillLineAbility, SpecializationSpells,
TraitDefinition, PvpTalent, ItemXItemEffect, ItemEffect and Spell tables for the live build
(wago.tools), and `tests/check_toylist.py`, which `tests/run.sh` runs, checks that it still starts
with the list at every earlier release tag. After the list it writes `TOY_HIDDEN`, the toys whose
Toy table Flags have the 2 bit, which the grid lists only when owned (see "The grid"); that part is
written whole each time, the list itself untouched. A toy the game has and the list doesn't isn't in
Clicky's grid, so it can't be put in a macro until Clicky is updated (the Macros API refuses it
too), and a macro that holds an entry past the end of this Clicky's list reads as saved by a newer
Clicky. A place that holds a spell or an item reads as that entry.

Macros are saved in format 6, which ends with two checksum characters, so a hand-edited line reads
as damaged rather than as other entries. Its first character says the format, and leaves room for
15 later ones, which read as saved by a newer Clicky; Clicky 0.5.0 reads format 6 that way too.
Every earlier format (formats 1 to 5: 0.4.0's format 4 and 0.5.0's format 5 included, so those
macros show as damaged) reads as damaged; Clicky keeps no compatibility code while it's in alpha.
Favorites' toys are the stars, so its macro has no `#clicky` line. Code: the list is built in
Toys.lua, the format is in [Codec.lua](../Codec.lua) (its header explains it, and why 100 entries
fit), and macro bodies are read and written in MacroStore.lua.

## Keeping up with changes

Clicky keeps no copy of its own. It re-reads every macro on login, whenever macros change, and
when combat ends:

```
read every Clicky macro
  -> a copied macro clicks the same button?  give the copy its own button, read again
                                            (the macro the button was bound to keeps it: same
                                            name, else same index; at login, before anything is
                                            bound, the first listed; macros are sorted by name)
  -> read each macro's entries and set up its button
  -> ns.Changed: refresh the panel and the grid, whichever is shown
```

Everything on screen that shows Clicky's state is a view: the panel and the grid register with
Core.lua (`ns.RegisterView`), and every refresh goes through `ns.Changed`, from a sync, a toy being
learned or starred, the spellbook, the bags or the worn items changing, or a toy's, spell's or
item's name arriving. A burst of changes refreshes a view once, after a delay the view chooses (toy
names arrive one event at a time), and a view that isn't shown isn't refreshed; it draws itself
when it's shown. The grid's own redraws (a search, a filter, the filter reset, a tab, scrolling, the
redraw right after opening a gift wrap, the retry after a held mouse button, and the end of the
first draw's wait for names) don't go through
`ns.Changed`: they change only what the grid shows, so they redraw the grid directly and leave the
panel alone.

Macros can't be created, edited or deleted in combat (warcraft.wiki.gg API EditMacro, CreateMacro,
DeleteMacro: nocombat), so saving waits until combat is over; when it ends, Clicky syncs. Code:
`ns.Sync` in Macros.lua.

## Files

```
Commands.lua   /clicky commands       \
Menu.lua       right-click menus       |
Panel.lua      the Toy Box panel       |
Grid.lua       the grid                 >  use  Macros.lua   reads macros, sets up buttons,
Drawer.lua     right-click drawers     /                     picks entries, makes changes
                                                    |
                         MacroStore.lua   reads and writes WoW macros
                         Entries.lua      what a macro holds, by kind:
                           Toys.lua       toys, and Clicky's list of every entry
                           Spells.lua     spells
                           Items.lua      bag and worn items
                         EntryButton.lua    the secure button that uses an entry
                         ToyList.lua      toys, spells and items (generated)
                         Codec.lua        packs entries into text
```

Every file also uses Core.lua (shared names, messages, events and views). Event handlers run in
`.toc` order, and an error in one goes to the error handler without stopping the ones after it.
Entries.lua dispatches what every view does with an entry (its name, icon, tooltip and cooldown)
to the file that owns its kind, so the panel, the drawers and the grid show a toy, a spell and an
item the same way, and EntryButton.lua makes the secure button that uses an entry, for the drawers
and the grid. Clicky keeps no saved data.

## Tests

`tests/run.sh` runs luacheck, then runs the addon in a simulated game with toys, macros shared
between computers, combat and patches, checks every WoW function Clicky calls against Blizzard's
current code, and checks that ToyList.lua only grew since each release. The top of the script lists
what to install. UI behavior is shown by tests (`tests/wow.lua` stubs the Blizzard frames and
widgets Clicky relies on, citing Blizzard's source: the Toy Box's frames, scroll bar and list,
filter menu, tooltip and the combat lock on protected frames) or relies only on behavior Blizzard's
source shows. GitHub runs the same script on every push.

## Releasing

`tools/release.sh <tag>` does it all, for a tag like `v0.5.0-alpha1`:

```
write the section for 0.5.0 at the top of CHANGELOG.md, commit everything else, then
tools/release.sh v0.5.0-alpha1
```

It runs `tools/update_toys.py` (which appends what patches added to ToyList.lua; the list
only grows), checks CHANGELOG.md's top section is `## 0.5.0`, runs `tests/run.sh`, commits
ToyList.lua and CHANGELOG.md as "Clicky 0.5.0" if either changed, pushes, then creates the
annotated tag and pushes it. It runs only on `main` and stops at the first failure.

Pushing a tag makes GitHub run the tests, then build a zip of the addon and upload it to Wago.
Tags with `alpha` or `beta` in the name are released as alpha or beta; any other tag is a full
release (BigWigsMods packager, release.sh), and the `## X-Wago-ID:` line in `Clicky.toc` names the
Wago project (packager README).
The release notes are CHANGELOG.md (`.pkgmeta`). The Wago API key is the GitHub secret
`WAGO_API_TOKEN` (`release.yml`).
