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

What a macro holds is entries: a toy, a mount, a pet, a spell or an item (a bag or worn item), each
named by a key, which is its entry in ToyList.lua (a toy's item ID, `"s"` and a spell ID, `"i"` and
an item ID, `"m"` and a mount ID, `"p"`, a pet species ID, `":"` and the display ID of one of its
looks, or 0 for its pets whose look the list doesn't have, or all its pets when there are none). Each kind has one owner file, which
registers with Entries.lua what the kind does: its name, icon, tooltip, cooldown, whether the player
has it, whether it can be used, its star if it has one, and its secure action. Toys.lua, Mounts.lua,
Pets.lua, Spells.lua and Items.lua are the owners, so the panel, the drawers, the macro buttons and
the grid treat a spell as they treat a toy.

A secure button uses an entry by setting its `type` to the action and the attribute that action
reads to the entry (SECURE_ACTIONS in Blizzard_FrameXML/SecureTemplates.lua):

| entry | `type` | attribute |
| --- | --- | --- |
| toy | `toy` | `toy` = the item ID |
| spell | `spell` | `spell` = the spell ID |
| item | `item` | `item` = `"item:"` and the item ID |
| mount | `spell` | `spell` = the name of the mount's spell |
| pet | `macro` | `macrotext` = `"/summonpet "` and a pet's GUID |

An item's value is not the bare ID because the item action reads a bare number as an inventory
slot (`SecureCmdItemParse`, ChatFrameUtil.lua). The same action wears an item that can be worn and
isn't worn, instead of using it, so such an item is drawer-only: a click on the macro never picks
it, and clicking it in the drawer wears it, or uses it once it is worn.

There is no secure action for a mount or a pet. A mount is cast as its spell, by name, as `/cast`
does (`CastSpellByName`): cast by its ID it wasn't summoned (seen in play), and the Mount Journal's
own `C_MountJournal.SummonByID` has no secure action. A pet runs `/summonpet` with its GUID, which
calls `C_PetJournal.SummonPetByGUID` (SlashCommands.lua). A pet entry stands for every pet the
player owns of that species and look; the one used is one that isn't out and can be summoned, a
starred one first, because summoning the pet that's out puts it away (`/dismisspet` does just that).
A click on a macro never picks a look whose only summonable pet is out; the drawer then uses the pet
that's out, which puts it away. Pets.lua reads the player's pets (`GetOwnedPetIDs`, whatever the Pet
Journal's filters) once per `PET_JOURNAL_LIST_UPDATE`; which one is out is read at each use, and
the grid redraws the buttons in view at once when it changes (`COMPANION_UPDATE`, Grid.lua, which
also marks the mount ridden), so a second click on a look in the grid summons its other pet. In a
fight a macro picks from the list handed over when it started, which can hold a pet that has come
out since.

The stars of toys, mounts and pets are the game's favorites, set only when the player picks
Favorite in an entry's menu. The game stars and picks up a mount only by its place in the Mount
Journal's list (`C_MountJournal.SetIsFavorite` and `Pickup` take a display index), which the
journal's filters decide; Mounts.lua finds that place, and a mount the filters hide has no star in
the menu and can't be dragged. A pet look is starred if any of its pets is; starring it stars the
pet it uses, and unstarring clears all of its pets.

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

The toys, the mounts and pets collected, the spells the character knows and the items it carries or
wears are on five tabs, Blizzard's top tabs placed and driven as Appearances drives its Items and
Sets (`PanelTemplates_SetNumTabs`, `PanelTemplates_SetTab`); Blizzard keeps the selected one on the
grid's frame. Each tab says its count, after the search and the filters, and a click shows its
entries from the top. The search looks at every tab and matches an entry's name, its filter labels
(`ns.EntryFilterLabels`, GridFilters.lua) or its tooltip's text (`ns.EntryTooltipText`, from each
kind's `C_TooltipInfo` call), each tooltip read once when first needed and kept (Search.lua); Toys,
Mounts and Pets each have their own filters, as the Toy Box and the journals do, and their button
shows on those tabs. A tab switch sets the button's reset state again (`ValidateResetState`, as
Blizzard's menu guide does for filters changed outside the menu). Each kind says what the grid may
list (`ns.ListedToyEntries`, `ns.ListedMountEntries`, `ns.ListedPetEntries`): what the player has,
and with Not Collected the rest, less `MOUNT_HIDDEN` (the Mount table's Flags 0x40, unnamed
anywhere: its mounts are mostly retired ones) and `PET_HIDDEN` (the species with
`Enum.BattlePetSpeciesFlags` HideFromJournal or HideUntilLearned); a pet species not owned is one
entry, as in the Pet Journal. Each tab's menu is its Blizzard window's, built in GridFilters.lua as
Blizzard builds them (the same global strings and order, and the game's own checks of which sources,
types and expansions to offer: `IsToySourceValid`, `IsValidSourceFilter`, `IsValidTypeFilter`,
`GetNumExpansions`). Blizzard filters inside the game, behind the windows' own settings, so Clicky
decides which entries pass: the data comes from the game's API where it has it (a toy's expansion
from `C_Item.GetItemInfo`, a mount's source from `GetMountInfoByID`, its type from
`GetMountInfoExtraByID`'s mountTypeID, a pet's family and whether it battles from
`GetPetInfoBySpeciesID`, its level and rarity from `GetPetInfoByPetID` and `GetPetStats`), and from
ToyList.lua where it doesn't (`TOY_SOURCE`, `PET_SOURCE`, `MOUNT_TYPE`: each mount type's Type in
the MountType table, read as `Enum.MountTypeFlag` flags, which its values fit though nothing
documents it). Not in Blizzard's source, and so checked in the game: a source's menu number being
its `Enum.BattlePetSources` value plus one for toys and pets, and a mount's `sourceType` itself (it
counts from 1: the Mount Journal with Sources 5 unticked kept the profession mounts, `sourceType`
4, seen in play), an entry without a source passing the source filters, a mount with several types
showing while any is ticked, Sort By's directions, and the defaults. `/clicky debug` also checks the
numbering against every mount's and species' source text (the journals' "Drop: ..."), counting how
many agree with Clicky's numbering and with the numbering one lower or higher: a source text often
doesn't name a source ("Legacy", "Zone: ..."), so the numbering is right when its count is the
highest, and a patch that renumbers sources shows there.
`/clicky debug` checks each tab against its Blizzard window by itself (BlizzardCheck.lua): it reads
the window's filters as the player left them (read-only: `C_ToyBox.GetCollectedShown` and the like),
lists Clicky's tab with the same filters, and compares that with what the window lists
(`GetToyFromIndex`, `GetDisplayedMountID`, `GetPetInfoByIndex`), naming every entry that differs;
pets are compared by species, as the Pet Journal lists them. When a window says it's on Blizzard's
defaults (`IsUsingDefaultFilters`), its settings are compared with Clicky's defaults too. A window
with a search typed in isn't checked. Only entries in ToyList.lua
are listed, because a macro can't hold any other. A toy whose Flags in the Toy table have the 2 bit
(ToyList.lua's `TOY_HIDDEN`) is listed only when owned, which matches the Toy Box: with Not
Collected on, its list and the grid were seen in play to hold the same 1076 toys. 72226, whose item
has no name in the game's tables, is one. Spells are the spellbook's: the active spells on its skill
lines and the known spells in its flyouts, not passive, not off-spec (`ns.KnownSpellEntries`,
Spells.lua). Items are those in the bags (the backpack, the equipped bags and the reagent bag) and
in the worn slots; the bank isn't looked at (`ns.CarriedItemEntries`, Items.lua). Mounts never
include those the game hides on this character (Mounts.lua, from `GetMountIDs`, whatever the Mount
Journal's filters); owned pets are one entry per look (Pets.lua, from `GetOwnedPetIDs`).
`ns.GridSections` makes the sections (`toys`, `mounts`, `pets`, `spells`, `items`) and `ns.GridRows`
the rows of the one shown. On every tab favorites come first and run straight into the rest, as in
the Toy Box; each has the Toy Box's star, in the Toy Box's place. The check mark is for the player's
own macros, not Favorites, whose toys have their star. Only toys, mounts and pets have a star, and
only toys a gift wrap and a NEW label. The mount ridden and a look whose pet is out are marked as
the journals mark them (`ActiveTexture`, drawn by EntryButton.lua, so the drawers have it too).
A pet look shows the cooldown of whichever of its pets ends last (`GetPetCooldownByGUID`), as the
Pet Journal shows each pet's: after a summon the game gives its global cooldown to some pets and not
others, so some show a swipe and some don't, in the Pet Journal too (seen in play). The Mount
Journal draws no cooldown on its mounts, and neither does Clicky. A click, a right-click, a
shift-click and a drag work on every kind through Entries.lua (a left click is the kind's secure
action, an item that can be worn is worn instead of used when it isn't worn, a link and a pickup are
the kind's own calls). The grid redraws when the spellbook, the bags, the worn items, the mounts or
the pets change (`SPELLS_CHANGED`, `BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED`,
`NEW_MOUNT_ADDED`, `MOUNT_JOURNAL_USABILITY_CHANGED`, `PET_JOURNAL_LIST_UPDATE`, through
`ns.Changed`), redraws only the buttons in view, at once, when the mount ridden or the pet that's
out changes (`COMPANION_UPDATE`), and refreshes cooldowns on `SPELL_UPDATE_COOLDOWN` and
`BAG_UPDATE_COOLDOWN`.

A name still loading is empty and sorts first, and its entry moves when the name arrives (each
arrival refreshes the grid: Toys.lua, Spells.lua, Items.lua).

Addon code can't use a toy, so every entry in view is a secure button (`EntryButton.lua`, also what
the drawers are made of). The grid makes 12 columns by 8 rows of them once, out of combat, in a
board frame, and as it scrolls it re-points them at other entries: each button's entry, icon,
cooldown, check mark, star and place. The numbers come from Blizzard's layout (the Collections
window is 703 by 606, the Toy Box's icons frame is inset from it) and from the icon size and gap:
12 by 9 keeps the grid clear of the frame's corners, as the Toy Box's own buttons are. The grid
scrolls whole rows: the rows (`ns.GridRows`) and the 8 rows in view from the top row
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

A macro body is limited to 255 characters, and up to 100 entries have to fit. Clicky ships a list of
every toy in the game (ToyList.lua, item IDs, followed by spells, items, mounts and pets: the spells
a character can learn: those the game's skill lines teach, SkillLineAbility, a specialization's own,
SpecializationSpells, the talents, TraitDefinition (with the spell a talent replaces or shows as),
and the PvP talents, PvpTalent; and the items with a "Use:" effect, ItemXItemEffect and ItemEffect's
TriggerType 0, unless the spell's text is shown only to characters who know another spell, as the
Earthen's gem eating is; less the toys; every mount, Mount; and each look of each pet species,
BattlePetSpecies with the display IDs of its creature in Creature and CreatureXDisplayInfo and the
looks BattlePetDisplayOverride gives it, and 0 for each), numbers each entry by its place in the
list, stores the numbers of the macro's entries, and compresses the gaps between them.

The list only ever grows at the end, so an entry's number never changes: a patch changes no macro,
and a toy taken out of the game keeps its place and stays in its macros until the player removes it.
`tools/update_toys.py` writes the list from the game's Toy, SkillLineAbility, SpecializationSpells,
TraitDefinition, PvpTalent, ItemXItemEffect, ItemEffect, Spell, Mount, MountType, BattlePetSpecies,
Creature, CreatureXDisplayInfo and BattlePetDisplayOverride tables for the live build (wago.tools),
and stops, writing nothing, if one comes back empty; `tests/check_toylist.py`, which
`tests/run.sh` runs, checks that it still starts with the list at every earlier release tag. After
the list it writes `TOY_HIDDEN`, the toys whose Toy table Flags have the 2 bit, which the grid
lists only when owned (see "The grid"), and the mounts and pet species listed only when the player
has them, the pet species whose looks are random, the toys' and pets' sources and the mount types'
flags (`MOUNT_HIDDEN`, `PET_HIDDEN`, `PET_RANDOM_LOOK`, `TOY_SOURCE`, `PET_SOURCE`,
`MOUNT_TYPE`); that part is written whole each time, the list itself untouched. A toy the game has and the list doesn't isn't in Clicky's
grid, so it can't be put in a macro until Clicky is updated (the Macros API refuses it too), and a
macro that holds an entry past the end of this Clicky's list reads as saved by a newer Clicky. A
place that holds a spell, an item, a mount or a pet look reads as that entry. A pet whose look the
list doesn't have isn't on the Pets tab as its own entry: it's under its species' look 0. A later
list can add that look, which moves the pet to it; once no pet is left under the 0, it stands for
all the species' pets (Pets.lua), so a macro holding it still has them rather than none. `/clicky
debug` counts such pets and names their looks. In play, the Creature table alone missed looks that 3
of a player's pets had; CreatureXDisplayInfo and BattlePetDisplayOverride had two of them, and no
table had the third. `/clicky debug` also asks the game for every listed species' looks
(`C_PetJournal.GetNumDisplays`, `GetDisplayIDByIndex`, which answer for species not owned) and names
those the list lacks.

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
learned or starred, the spellbook, the bags, the worn items, the mounts or the pets changing, or a
toy's, spell's or item's name arriving. A burst of changes refreshes a view once, after a delay the
view chooses (toy names arrive one event at a time), and a view that isn't shown isn't refreshed; it
draws itself when it's shown. The grid's own redraws (a search, a filter, the filter reset, a tab,
scrolling, the redraw right after opening a gift wrap, the retry after a held mouse button, and
the mount ridden or the pet that's out changing, which redraws only the buttons in view)
don't go through `ns.Changed`: they change only what the grid shows, so they redraw the grid
directly and leave the panel alone.

Macros can't be created, edited or deleted in combat (warcraft.wiki.gg API EditMacro, CreateMacro,
DeleteMacro: nocombat), so saving waits until combat is over; when it ends, Clicky syncs. Code:
`ns.Sync` in Macros.lua.

## Files

```
Commands.lua   /clicky commands       \
Menu.lua       right-click menus       |
Panel.lua      the Toy Box panel       |
Grid.lua       the grid                 >  use  Macros.lua   reads macros, sets up buttons,
GridFilters.lua its Filter menus       |
Search.lua     its search              |
BlizzardCheck.lua tabs vs Blizzard's   |
Debug.lua      the debug window        |
Drawer.lua     right-click drawers     /                     picks entries, makes changes
                                                    |
                         MacroStore.lua   reads and writes WoW macros
                         Entries.lua      what a macro holds, by kind:
                           Toys.lua       toys, and Clicky's list of every entry
                           Mounts.lua     mounts
                           Pets.lua       pets
                           Spells.lua     spells
                           Items.lua      bag and worn items
                         EntryButton.lua    the secure button that uses an entry
                         ToyList.lua      toys, spells, items, mounts and pets (generated)
                         Codec.lua        packs entries into text
```

Every file also uses Core.lua (shared names, messages, events and views). Debug.lua is the window
`/clicky debug` opens: Clicky's state then, and under it the trace (`ns.Trace`, the newest 1000
lines, recorded while its Trace box is ticked), in text that can be copied, which chat's can't. It
opens without taking the keyboard, as Blizzard's script errors window does. Panel.lua widens the
Collections window by the panel's width while it's shown (the window's `extraWidth`, which the
window manager takes only out of combat, so in a fight it waits for the fight's end); the arrow
beside the grid's Filter button hides and shows the panel, in combat too. Event handlers run in
`.toc` order, and an error in one goes to the error handler without stopping the ones after it.
Entries.lua dispatches what every view does with an entry (its name, icon, tooltip and cooldown)
to the file that owns its kind, so the panel, the drawers and the grid show every kind the same
way, and EntryButton.lua makes the secure button that uses an entry, for the drawers
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
