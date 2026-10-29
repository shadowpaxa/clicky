# Clicky macros: user journeys

Players group toys, spells and items from their bags into their own macros. Clicking a macro uses
a random one of them, and right-clicking it opens a drawer of what it holds to choose from.
Macros are managed from the right-click menu of a toy, spell or item in Clicky's grid, which takes
the place of the Toy Box's own, and from a Clicky panel docked to the Toy Box's right edge.
Favorites (the Toy Box star) is always first; it holds the starred toys, and only toys.
Messages, panel counts and these journeys call everything a macro holds an *item*; the grid's
**Items** tab lists the things in the bags or worn. Favorites' messages say toys.

## Decisions

Product decisions, so a change doesn't quietly undo one. Reviews check the code against them.
- 2026-10-17: No Random/Pick switch and no saved pick. Every macro is random on a click and has a
  drawer on a right-click. The point is less code.
- 2026-10-17: Favorites works like any other macro, with as few exceptions as possible.
- 2026-10-17: Alpha releases may break players' macros, with no migration code; full releases
  must not. 2026-10-25: no compatibility work at all (no migration, no reading of old formats,
  nothing for older Clicky versions) until spells and items in macros work and seem sane; the
  format this work ships with is the first one later versions keep reading. The one conversion
  Clicky had, of macros saved by 0.4.0, is gone: they read as damaged.
- 2026-10-17: No license, and no bug-report route for now.
- 2026-10-18: No saved variables: a macro is the only copy of its items.
- 2026-10-18: Nothing in the repo states what the code or a cited source doesn't confirm.
- 2026-10-18: The launch bar is "not embarrassing", not best practice.
- 2026-10-24: Clicky ships its own list instead of building one from the game at login (toys, and
  since 2026-10-25 spells and items too, in the one list). The list only grows at the end, and an
  entry's number is its place in it, so a patch can't shift the items in players' macros. An item
  added by a patch can be put in macros once Clicky is updated for that patch; one taken out of the
  game keeps its place.
- 2026-10-24: Clicky's own toy grid takes the place of the Toy Box's, so Clicky can grow into
  more than toys. The Toy Box's filters are the player's settings, so the grid has its own and
  only hides the Toy Box's. It started with toys only; spells and items followed (below), mounts and
  pets come later.
- 2026-10-25: A macro mixes toys, spells and bag items (entries), up to 100 of any mix. Players add
  them in the same grid, in sections after the toys: the spells the character knows that Clicky's
  list has (the spellbook's flyouts included), then the usable items in the bags or worn that the
  list has. The word for what a macro holds is "items" in messages, panel counts and the README;
  Favorites holds only toys, so its messages say "toys". The grid has no "in a macro" filter or
  section; the check mark is the only sign. Favorites holds toys only: it is the Toy Box's stars,
  which only toys have. An item that can be worn is chosen only from the drawer: the game's item
  action wears it if it isn't worn instead of using it, so a click on the macro never picks it.
- 2026-10-28: The grid's toys, spells and items are on tabs (Toys, Spells, Items), Blizzard's own,
  each with its count, as Appearances has Items and Sets; a tab shows its own entries, and the
  search looks at every tab. The filters are the toys' only, on the Toys tab. Favorites come first
  with the Toy Box's star and run straight into the rest, as in the Toy Box; the check mark leaves
  out Favorites, whose toys have their star. Not Collected lists the same toys as the Toy Box's.

A Clicky macro is an ordinary general macro (in /macro) whose items are written into it, so it
follows the player to any computer they play on, like the rest of their macros. Every macro
follows the same fixed rule: it holds up to 100 items, in any mix (Favorites, whose toys are the
stars, has no limit). Clicky carries its own list of every toy, spell and item in the game that
a macro can hold, which only grows at the end, so a patch never changes which items a macro holds.

## 1. Discover macros
*Goal: find out how to make a macro.*
1. Type /clicky (or open the Toy Box).

*Result:* the Toy Box opens showing Clicky's grid (journey 15) and the Clicky panel listing
Favorites, collapsed, and the hint "Right-click a toy, spell or item to make one.", shown while
Favorites is the only macro. In a fight, `/clicky` says "Can't open the Toy Box in combat."
instead.

## 2. Dress up in a few clicks
*Goal: look like a random costumed character, then add random extras on top.*
1. Click the **Illusion** macro on the action bar → a random costume toy is used.
2. Click the **Illusion mod** macro → a random hat, wings, etc. is added.
3. Click either again to reroll.

*Result:* a new random look in two clicks. A click doesn't use the item the macro used last, unless
it's the only one that can be used. Items that can't be used right now are skipped (and so is gear
that can be worn: journey 14), and if none can be used the player sees "No usable items in
Illusion." A macro with nothing in it says how to add some: "Illusion has no items. Right-click a
toy, spell or item in the Toy Box to add it." Favorites says toys, as it holds only toys: "Favorites
has no toys. Star toys in the Toy Box to add them." and "No usable toys in Favorites." An item that
only turns out to fail when it's used shows WoW's error, and the next click picks again.

In combat macros keep working, picking from the items that were ready when the fight started.
That list can't change until the fight ends: an item that comes off cooldown during the fight waits
until it's over, and one that goes on cooldown during the fight can still come up, and that
click shows WoW's error.

## 3. Make a macro
*Goal: start an "Illusion" macro.*
1. Open the Toy Box and right-click a costume toy the player owns.
2. Choose **Add to new macro...**, type "Illusion", and confirm.

*Result:* an Illusion general macro exists (in /macro too) with that toy's icon, and Illusion
appears in the Clicky panel, expanded to show that toy. Names are cut to WoW's 16-character macro
name limit. A name another Clicky macro has is refused, and so is a new macro when all general
macro slots are full; the dialog stays open with the reason.

## 4. Add items to macros
*Goal: fill Illusion, and put some items in more than one macro.*
1. Right-click a toy the player owns in the Toy Box. (A spell or an item in the grid has the same
   menu, without the star.)
2. Below **Set Favorite** (or **Remove Favorite**), under **Clicky macros**, tick **Illusion**.
   The menu stays open with Illusion ticked.
3. Tick **Illusion mod** too if the toy belongs there as well.

*Result:* the toy is in both macros, and the panel shows them updated. A macro that already has 100
items, in any mix of toys, spells and items, refuses another with "Illusion is full: a macro holds
up to 100 items." The limit never changes as the collection grows. If the player has added so many
lines of their own to the macro in /macro that a change no longer fits, it's refused with "That
macro is too long to update. Remove your own lines from it in /macro."

In combat, macros can't be changed. Making, renaming or deleting one, or adding or removing an item,
says "Can't change macros in combat." Dragging one from the panel says "Can't drag macros in
combat."

## 5. See what's in a macro
*Goal: check what Illusion contains.*
1. In the Clicky panel, click **Illusion**. Click it again to hide what it holds.

*Result:* its items are listed alphabetically under it, whatever their kind, the ones the player
doesn't have (a toy not owned, a spell not known, an item not carried) greyed out (they can still
be removed), and hovering over one shows its tooltip. Every macro's items are hidden by default;
each macro shows its item count. An open macro with nothing in it says "Right-click a toy, spell or
item to add it." (Favorites: "Star toys to add them."). Hovering over a macro's icon says to drag
it to a bar and right-click it there.

## 6. Remove an item from a macro
*Goal: take a toy (or spell, or item) the player is tired of out of Illusion.*
1. Right-click it in the panel (or in the grid) and untick **Illusion**.

*Result:* it is gone from Illusion and stays in any other macros it's in.

## 7. Put a macro on an action bar
*Goal: get an Illusion button.*
1. In the Clicky panel, drag Illusion's icon onto an action bar (or drag it from /macro).

*Result:* an Illusion button on the bar. Other characters can put the same macro on their own
bars. Favorites' macro ("Favorites") is made the first time it's dragged or renamed; if all
general macro slots are full, a message says so.
To use a macro's items from a macro of the player's own, its right-click menu in the panel has
**Copy /click line**, which shows `/click Clicky<code>` selected to copy. The code is four random
capital letters (consonants only), different from every other macro's; Favorites' is `FVRT`, so
its line is `/click ClickyFVRT`.

## 8. Rename or delete a macro
*Goal: tidy up macros.*
1. Right-click the macro in the panel and choose **Rename** or **Delete**.

*Result:* a renamed macro keeps working on the bars. Deleting asks for confirmation, then removes
the macro and its bar buttons. Favorites can be renamed and deleted too; once its macro is
deleted, Favorites stays in the panel, called Favorites again, and its macro is made again when
it's next dragged.
Renaming or deleting the macro in /macro does the same, and the panel follows.

## 9. Play on another computer
*Goal: use Illusion on a laptop.*
1. Install Clicky on the laptop and log in.

*Result:* Illusion is there with its items, in the panel and on the bars, as WoW brings the
player's macros to every computer. Nothing needs copying; it works as soon as the laptop has
loaded the player's toys.

## 10. New toys
*Goal: keep playing after learning toys, and after patches add toys to the game.*
1. Learn a toy, with Clicky running or not (the addon disabled, or another computer without it).
2. Log in after a patch that added toys to the game.

*Result:* every macro keeps its items, here and on every other computer. Learning a toy (or a
spell, or picking up an item) changes nothing: a macro's items come from Clicky's list of every
toy, spell and item in the game that a macro can hold, not from the player's collection. A patch
changes no macro. A toy, spell or item it adds can be put in macros, and shows in Clicky's grid
(journey 15), once Clicky is updated for that patch; until then it isn't in the grid, so it can't
be added. A macro that holds such an item shows as made by a newer version on a computer whose
Clicky is older (journey 11).

Macros saved by Clicky 0.5.0 can't be read (journey 11): the player deletes them and makes them
again. Favorites' macro has no items in it, so it isn't affected. A computer still on 0.5.0 shows a
macro this version made as saved by a newer version (journey 11), so Clicky needs updating there
too.

Macros saved by Clicky 0.4.0 are no longer converted: they read as damaged (journey 11), like
0.5.0's. Their `/click` lines (`ClickyP<number>;ClickySet<number>`) are still recognized so the
macro has a row, greyed out; Clicky never rewrites their line or body. The player deletes them and
makes them again. 0.4.0's Favorites macro (its line is `ClickyP0;ClickyButton`, with no `#clicky`
line) is not Favorites' macro and has no row: its button on a bar does nothing (`/click` with no
button of that name does nothing, SlashCommands.lua), and dragging Favorites makes a macro of its
own, leaving the old one in /macro.

## 11. A macro whose items can't be read
*Goal: understand a macro Clicky can't use.*
1. Look at the macro in the panel, hover over it, or click it.

*Result:* the macro's icon is greyed out with a small warning mark, and its item count shows "?".
Hovering over it, and clicking it (in the panel or on a bar), says why:
- It was saved by a newer Clicky, including one with items this Clicky's list doesn't have yet:
  "This macro was saved by a newer version of Clicky. Update Clicky to use it."
- Its `#clicky` line was changed (in /macro, say), or it was saved by Clicky 0.4.0 or 0.5.0:
  "Clicky can't read this macro's items. Delete it and make it again."

It never uses items that weren't put in it. Its items can't be changed, but it can be renamed,
deleted or put on a bar.

A macro whose `#clicky` line or `/click` line is removed is no longer a Clicky macro. It leaves the
panel and no longer uses items.

## 12. Copy a macro
*Goal: make a variant of Illusion by copying its macro in /macro.*
1. Make a new general macro in /macro and paste Illusion's text into it. (Character macros
   aren't read: a copy there just clicks Illusion's buttons.)

*Result:* the copy is a Clicky macro of its own, with the same items, its own random picks and its
own item list from then on: changing one never changes the other. With Clicky running when the copy
is made, the macro it was copied from keeps its buttons, whatever the copy is called. Pasted on
another WoW account, it works there too (every account has the same game toys, spells and items),
with the items that account has, as long as that account's Clicky is the same version or newer.

## 13. An item leaves
*Goal: keep playing after a toy leaves the collection or the game, a spell is forgotten, or an item
is no longer carried.*
1. Log in after the patch, or on a character that doesn't know the spell or carry the item.

*Result:* a toy the player no longer owns, a spell the character doesn't know and an item that isn't
in the bags or worn stay in their macros, greyed out in the panel and left out of the drawer, and
are never picked; they are picked again if they come back. One taken out of the game's data stays
in its macros too, and the player can remove it in the panel.

## 14. Use the drawer
*Goal: use a particular item from a macro: a hearthstone that's off cooldown, or the portal toy to
where the player is going.*
1. Right-click the Hearthstones button on the action bar. A drawer opens at the mouse with every
   item in Hearthstones the player has, in the panel's order, showing their cooldowns.
2. Click one to use it right away; if it's on cooldown or can't be used here, the player sees
   the game's error, as with any toy.

*Result:* the drawer closes once an item is chosen, and on Escape, a second right-click, or when the
mouse leaves it. Nothing is saved: a left click on the button still uses a random item. This works
in combat too. Gear that can be worn is only in the drawer: clicking it there wears it if it isn't
worn, and uses it once it is. If the macro has no items the player has, the right-click shows the
same message as a left click (journey 2).

## 15. Browse and use toys, spells and items
*Goal: find a toy, spell or item and use it, or put it on a bar.*
1. Open the Toy Box. The window says **Clicky**. Clicky's grid has a tab each for **Toys**,
   **Spells** and **Items**, each with how many it lists, and starts on Toys: favorites first, each
   with the Toy Box's star, then the rest the player owns, then (with **Not Collected** ticked) the
   ones they don't. Each group is sorted by name. The Spells tab lists the spells the character
   knows that Clicky has (the spellbook's flyouts included), the Items tab the items in the bags or
   worn that it has, each by name. A check mark shows an entry is in one of the player's Clicky
   macros; Favorites' toys have their star instead.
2. Hover over a toy for its name. Click it to use it (a spell is cast, an item used; an item that
   can be worn and isn't is worn). Drag it to an action bar for a button of its own, or shift-click
   it to link it in chat. Right-click one the player owns for its menu (journey 4).
3. Scroll with the mouse wheel or the scroll bar. The grid scrolls in whole rows; a wheel notch
   moves three. A search, a filter or another tab goes back to the top; anything else that refreshes
   the grid keeps the place.
4. Type in the search box to narrow the grid by name. The search looks at every tab, and each tab's
   count follows it. On the Toys tab the **Filter** menu has **Collected**, **Not Collected** and
   **Usable Only**, which hides collected toys this character can't use now; it starts with
   collected toys only, and its reset button puts that back. The Spells and Items tabs have no
   filters. Toys the player doesn't own are greyed out. Not Collected lists the same toys as the Toy
   Box's own Not Collected. A toy the game has no data for on this computer isn't listed, and
   neither is a spell or item Clicky's list doesn't have.

*Result:* the entry is used, on a bar, or linked. The first time the grid shows after logging in or
a reload, it waits for the names it lists to load, up to 5 seconds, so its entries don't move as the
names arrive; a name that takes longer moves its entry when it comes. A spell learned or an item
picked up, put away or worn shows in the grid. Only toys have a star, a NEW label or a gift wrap. A
toy learned this session says NEW until it's hovered over; one still in its gift wrap says NEW until
it's clicked, and that click unwraps it (without the Toy Box's animation) instead of using it. In
combat the grid still uses toys, spells and items. Shift-click and right-click work too, and a toy
still in its gift wrap opens when it's clicked (to be used after the fight). A toy used shows its
cooldown, and hovering over a toy learned this session clears NEW (a toy in its gift wrap keeps NEW
until it's clicked). Otherwise the grid stays as it is: the scroll bar is off, the tabs don't
change, and a search, a filter or something the player learns, picks up or stars shows when the
fight ends. If the player first opens the Collections window in a fight, the Toy Box shows its own
grid until the fight ends. The Toy Box's own filters are never changed; its progress bar is hidden,
the Toys tab giving the count.

## 16. Portals: toys, spells and a cloak in one macro
*Goal: one button for everything that takes the player somewhere: portal toys, "Path of the ..."
spells and a teleport cloak from the bags.*
1. Right-click a portal toy in the grid, choose **Add to new macro...**, type "Portal", and confirm.
2. Open the **Spells** tab and right-click a "Path of the ..." spell the character knows. Under
   **Clicky macros** tick **Portal**. Do the same for the other teleport spells.
3. On the **Items** tab, right-click the teleport cloak (in the bags or worn) and tick **Portal**.
4. Drag Portal onto an action bar.

*Result:* the panel lists Portal's toys, spells and items together, alphabetically (journey 5). A
click on the bar uses a random toy or spell that is ready. It never picks the cloak, which can be
worn: the cloak is in the drawer (right-click the button), where clicking it wears it, or uses it
once it is worn (journey 14). A spell the character doesn't know, on another character, is greyed
out in the panel and left out of the drawer and the clicks (journey 13). A macro made this way is a
macro like any other: it follows the player to other computers (journey 9).

## Later
- Adding many toys at once.
- An icon that shows the next toy.
- The Toy Box's source and expansion filters in Clicky's grid.
- Mounts and pets in macros and in the grid. A mount would be one entry each; a pet entry would be
  one species and look (its display ID), never "any pet of a species". A pet would be summoned by a
  secure button running the `/summonpet` macro text: the secure "macro" action runs macro text
  (SECURE_ACTIONS.macro, SecureTemplates.lua), and `/summonpet` calls
  `C_PetJournal.SummonPetByGUID` (SlashCommands.lua). Whether that works in combat hasn't been
  checked.
