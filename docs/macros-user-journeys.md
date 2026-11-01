# Clicky macros: user journeys

Players group toys, mounts, pets, spells and items from their bags into their own macros. Clicking
a macro uses a random one of them, and right-clicking it opens a drawer of what it holds to choose
from. Macros are managed from the right-click menu of a toy, mount, pet, spell or item in Clicky's
grid, which takes the place of the Toy Box's own, and from a Clicky panel docked to the Toy Box's
right edge.
Favorites (the Toy Box star) is always first; it holds the starred toys, and only toys.
Messages, panel counts and these journeys call everything a macro holds an *item*; the grid's
**Items** tab lists the things in the bags or worn. Favorites' messages say toys.

## Decisions

Product decisions, so a change doesn't quietly undo one. Reviews check the code against them.
- 2026-10-17: No Random/Pick switch and no saved pick. Every macro is random on a click and has a
  drawer on a right-click. The point is less code.
- 2026-10-17: Favorites works like any other macro, with as few exceptions as possible.
- 2026-10-30: A release never breaks players' macros: every later version reads format 1 and an
  entry's place in Clicky's list.
- 2026-10-31: MIT license (LICENSE). Since 2026-10-29, help and bug reports go to the comments
  on Clicky's Wago page.
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
  only hides the Toy Box's. It started with toys only; spells and items followed, then mounts and
  pets (below).
- 2026-10-25: A macro mixes toys, spells and bag items (entries), up to 100 of any mix. Players add
  them in the same grid, in sections after the toys: the spells the character knows that Clicky's
  list has (the spellbook's flyouts and the Professions book included), then the usable items in
  the bags or worn that the list has. The word for what a macro holds is "items" in messages,
  panel counts and the README; Favorites holds only toys, so its messages say "toys". The grid has no "in a macro" filter or
  section; the check mark is the only sign. Favorites holds toys only: it is the Toy Box's stars,
  which only toys have. An item that can be worn is chosen only from the drawer: the game's item
  action wears it if it isn't worn instead of using it, so a click on the macro never picks it.
- 2026-10-28: The grid's toys, spells and items are on tabs (Toys, Spells, Items), Blizzard's own,
  each with its count, as Appearances has Items and Sets; a tab shows its own entries, and the
  search looks at every tab. The filters are the toys' only, on the Toys tab (since 2026-10-29
  Mounts and Pets have their own, below). Favorites come first
  with the Toy Box's star and run straight into the rest, as in the Toy Box; the check mark leaves
  out Favorites, whose toys have their star. Not Collected lists the same toys as the Toy Box's.
- 2026-10-29: Mounts and pets go in macros too, in the same list, with a tab each after Toys (Toys,
  Mounts, Pets, Spells, Items). A mount is one entry. A pet entry is a species and one of its looks
  (colors), not one particular pet: three Cats in three colors are three entries, two Cats of one
  color are one. A click summons one of the player's pets of that look that isn't out, a starred one
  first; the pet that's out isn't picked, as summoning it again would put it away (in combat, a pet
  that came out mid-fight can be). A pet can have a look no game table gives its species (seen in
  play), so each species also has one entry for its pets whose look Clicky's list doesn't have. Once
  the player has none left (a Clicky update listed their look), that entry stands for all the
  species' pets, so a macro holding it keeps working. A species whose pets take a random look each
  summon has only that one entry. The tabs list starred first, with the journal's star, which the
  menu can set as it can a toy's. Favorites stays the Toy Box's stars, toys only: the game has its
  own random favorite mount and pet buttons.
- 2026-10-29: Toys, Mounts and Pets each have their own Filter menu, the same as the Toy Box's, the
  Mount Journal's and the Pet Journal's (entries, order, labels, the sources and types offered),
  each tab keeping its own settings as those windows do; Blizzard's code and the game's API are
  followed wherever they answer, and nothing is invented that they don't need. Not Collected
  lists what the journals would: not the mounts and pet species the game's tables mark as shown
  only once collected, the same way the toys' list matches the Toy Box. On Pets it lists one entry
  per species the player owns none of, as the Pet Journal does.
- 2026-10-29: The search finds more than Blizzard's Heirlooms search, which doesn't look at tooltips
  ("rested" found none of the heirlooms whose set bonus mentions rested experience, seen in play): a
  name, a source, an expansion, a mount type or a pet family as the filter menus call them, or any
  text in the tooltip.

A Clicky macro is an ordinary general macro (in /macro) whose items are written into it, so it
follows the player to any computer they play on, like the rest of their macros. Every macro follows
the same fixed rule: it holds up to 100 items, in any mix (Favorites, whose toys are the stars, has
no limit). Clicky carries its own list of every toy, mount, pet look, spell and item in the game
that a macro can hold, which only grows at the end, so a patch never changes which items a macro
holds.

## 1. Discover macros
*Goal: find out how to make a macro.*
1. Type /clicky (or open the Toy Box).

*Result:* the Toy Box opens showing Clicky's grid (journey 15) and the Clicky panel, titled
**Macros**, listing Favorites, collapsed, and the hint "Right-click a toy, mount, pet, spell or item
to make one.", shown while Favorites is the only macro. In a fight, `/clicky` says "Can't open the
Toy Box in combat." instead. An arrow beside the grid's Filter button hides the panel and brings it
back, as the world map's arrow does its quest log; the panel is shown again
each session.

## 2. Dress up in a few clicks
*Goal: look like a random costumed character, then add random extras on top.*
1. Click the **Illusion** macro on the action bar → a random costume toy is used.
2. Click the **Illusion mod** macro → a random hat, wings, etc. is added.
3. Click either again to reroll.

*Result:* a new random look in two clicks. A click doesn't use the item the macro used last, unless
it's the only one that can be used. Items that can't be used right now are skipped (and so is gear
that can be worn: journey 14), and if none can be used the player sees "No usable items in
Illusion." A macro with nothing in it says how to add some: "Illusion has no items. Right-click a
toy, mount, pet, spell or item in the Toy Box to add it." Favorites says toys, as it holds only
toys: "Favorites has no toys. Star toys in the Toy Box to add them." and "No usable toys in
Favorites." An item that only turns out to fail when it's used shows WoW's error, and the next click
picks again.

In combat macros keep working, picking from the items that were ready when the fight started.
That list can't change until the fight ends: an item that comes off cooldown during the fight waits
until it's over, and one that goes on cooldown during the fight can still come up, and that
click shows WoW's error. A pet that comes out during the fight can still come up too, and that
click puts it away.

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
1. Right-click a toy the player owns in the Toy Box. (A mount or a pet in the grid has the same
   menu; a spell or an item has it without the star.)
2. Below **Set Favorite** (or **Remove Favorite**), under **Clicky macros**, tick **Illusion**.
   The menu stays open with Illusion ticked.
3. Tick **Illusion mod** too if the toy belongs there as well.

*Result:* the toy is in both macros, and the panel shows them updated. A macro that already has 100
items, in any mix of toys, mounts, pets, spells and items, refuses another with "Illusion is full: a
macro holds up to 100 items." The limit never changes as the collection grows. If the player has
added so many lines of their own to the macro in /macro that a change no longer fits, it's refused
with "That macro is too long to update. Remove your own lines from it in /macro."

In combat, macros can't be changed. Making, renaming or deleting one, or adding or removing an item,
says "Can't change macros in combat." Dragging one from the panel says "Can't drag macros in
combat."

## 5. See what's in a macro
*Goal: check what Illusion contains.*
1. In the Clicky panel, click **Illusion**. Click it again to hide what it holds.

*Result:* its items are listed alphabetically under it, whatever their kind, the ones the player
doesn't have (a toy not owned, a mount not collected, a pet look the player has no pet of, a spell
not known, an item not carried) greyed out (they can still be removed), and hovering over one shows
its tooltip. Every macro's items are hidden by default; each macro shows its item count. An open
macro with nothing in it says "Right-click a toy, mount, pet, spell or item to add it." (Favorites:
"Star toys to add them."). Hovering over a macro's icon says to drag it to a bar and right-click it
there, and, for a macro that has items and exists in /macro, that right-clicking one of its items
changes the icon.

Right-clicking an item in an open macro offers only what concerns that macro: **Use as icon for
Illusion** and **Remove from Illusion** (journey 6); the grid's menu holds the star and every
macro. **Use as icon for Illusion** sets the macro's icon to that item's. The icon is the macro's
own in /macro, so later changes to the macro keep it and other computers get it with the macro. It
is refused in combat. Favorites offers it once its macro exists.

## 6. Remove an item from a macro
*Goal: take a toy (or mount, pet, spell or item) the player is tired of out of Illusion.*
1. Right-click it in the panel and choose **Remove from Illusion** (or right-click it in the grid
   and untick **Illusion**).

*Result:* it is gone from Illusion and stays in any other macros it's in. For Favorites, **Remove
from Favorites** takes the toy's star off, as unstarring it in the Toy Box does, and works in
combat like the star.

## 7. Put a macro on an action bar
*Goal: get an Illusion button.*
1. In the Clicky panel, drag Illusion's icon onto an action bar (or drag it from /macro).

*Result:* an Illusion button on the bar. Other characters can put the same macro on their own
bars. Favorites' macro ("Favorites") is made the first time it's dragged or renamed; if all
general macro slots are full, a message says so.
To use a macro's items from a macro of the player's own, its right-click menu in the panel has
**Copy /click line**, which shows `/click Clicky<code>` selected to copy. The code is four random
capital letters (consonants only), different from every other macro's; Favorites' is `FVRT`, so
its line is `/click ClickyFVRT`. In the player's own macro, that line uses a random item whichever
mouse button the macro is clicked with (`/click` sends a left click when it names no button,
SlashCommands.lua), and `/click ClickyP<code>` opens the macro's drawer, on either button too.

## 8. Rename, delete or edit a macro
*Goal: tidy up macros.*
1. Right-click the macro in the panel and choose **Rename**, **Delete** or **Open in /macro**.

*Result:* a renamed macro keeps working on the bars. Deleting asks for confirmation, then removes
the macro and its bar buttons. Favorites can be renamed and deleted too; once its macro is
deleted, Favorites stays in the panel, called Favorites again, and its macro is made again when
it's next dragged.
Renaming or deleting the macro in /macro does the same, and the panel follows. A menu or dialog
left open on a macro deleted in /macro refuses to change it with "That macro is gone."
**Open in /macro** opens the /macro window on its General tab with the macro selected, for the
player to edit it there. Text the player typed in the macro selected there before is saved first,
as clicking another macro in /macro does. It's refused in combat, and Favorites has it once its
macro has been made.

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
toy, mount, pet look, spell and item in the game that a macro can hold, not from the player's
collection. A patch changes no macro. A toy, mount, pet look, spell or item it adds can be put in
macros, and shows in Clicky's grid
(journey 15), once Clicky is updated for that patch; until then it isn't in the grid, so it can't
be added. A macro that holds such an item shows as made by a newer version on a computer whose
Clicky is older (journey 11).

## 11. A macro whose items can't be read
*Goal: understand a macro Clicky can't use.*
1. Look at the macro in the panel, hover over it, or click it.

*Result:* the macro's icon is greyed out with a small warning mark, and its item count shows "?".
Hovering over it, and clicking it (in the panel or on a bar), says why:
- It was saved by a newer Clicky, including one with items this Clicky's list doesn't have yet:
  "This macro was saved by a newer version of Clicky. Update Clicky to use it."
- Its `#clicky` line was changed (in /macro, say):
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
another WoW account, it works there too (every account has the same game toys, mounts, pets, spells
and items), with the items that account has, as long as that account's Clicky is the same version or
newer.

A copy holding more than Clicky can write back (lines of the player's own in letters that take
more room, such as accented or non-Latin ones) is left as it is: it uses the original's items and
changes with it, and `/clicky debug` counts it under "waiting". Once the player shortens those
lines, it gets buttons of its own.

## 13. An item leaves
*Goal: keep playing after a toy leaves the collection or the game, a pet is caged or released, a
spell is forgotten, or an item is no longer carried.*
1. Log in after the patch, or on a character that doesn't know the spell or carry the item.

*Result:* a toy the player no longer owns, a pet look the player has no pet of any more, a spell the
character doesn't know and an item that isn't in the bags or worn stay in their macros, greyed out
in the panel and left out of the drawer, and are never picked; they are picked again if they come
back. One taken out of the game's data stays in its macros too, and the player can remove it in the
panel.

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

## 15. Browse and use toys, mounts, pets, spells and items
*Goal: find a toy, mount, pet, spell or item and use it, or put it on a bar.*
1. Open the Toy Box. The window says **Clicky**. Clicky's grid has a tab each for **Toys**,
   **Mounts**, **Pets**, **Spells** and **Items**, each with how many it lists, and starts on Toys:
   favorites first, each with the Toy Box's star, then the rest the player owns, then (with **Not
   Collected** ticked) the ones they don't. Each group is sorted by name. The Mounts tab lists the
   mounts the player has collected, less the ones the game hides on this character
   (`shouldHideOnChar`),
   and the Pets tab one entry per species and look the player owns; each lists the starred ones
   first, with the journal's star, then the rest, by name. The Spells tab lists the spells the
   character knows that Clicky has (the spellbook's flyouts and the Professions book included), the
   Items tab the items in
   the bags or worn that it has, each by name. A check mark shows an entry is in one of the
   player's Clicky macros; Favorites' toys have their star instead.
2. Hover over a toy for its name. Click it to use it (a mount is summoned, a pet summoned, a spell
   cast, an item used; an item that can be worn and isn't is worn). Drag it to an action bar for a
   button of its own, or shift-click it to link it in chat. Right-click one the player owns for its
   menu (journey 4), which on a toy, a mount or a pet stars it or takes its star away, as the Toy
   Box and the journals do. The game finds a mount to star or drag by its place in the Mount
   Journal's list, so a mount the Mount Journal's filters hide can't be starred or dragged from
   Clicky's grid; it can still be clicked and put in macros.
3. Scroll with the mouse wheel or the scroll bar. The grid scrolls in whole rows; a wheel notch
   moves three. A search, a filter or another tab goes back to the top; anything else that refreshes
   the grid keeps the place.
4. Type in the search box to narrow the grid by name, source, expansion, mount type, pet family or
   any tooltip text (a pet not owned has no tooltip). The search looks at every tab, and each tab's
   count follows it. On the Toys, Mounts and Pets tabs the **Filter** menu is the Toy Box's, the
   Mount Journal's or the Pet Journal's: Toys has **Collected**, **Not Collected**, **Usable Only**
   and **Sources** and **Expansion** submenus; Mounts has Collected, Not Collected, **Unusable**
   (unticked, it hides collected mounts that can't be used here), a checkbox per mount **Type** and
   Sources; Pets has Collected, Not Collected, **Battle Pets**, **Non-Combat Pets**, **Pet
   Families**, Sources and **Sort By** (name, level, rarity or family). Each tab has its own, starts
   with collected ones only, and its reset button puts that back. A toy or pet without a source, or
   a toy whose expansion hasn't loaded, isn't hidden by those. A mount with several types shows
   while any of them is ticked. The Spells and Items tabs have no filters. What the player doesn't
   have is greyed out; a pet species not owned is one entry, which summons nothing. Not Collected
   lists the same toys as the Toy Box's own Not Collected; on Mounts and Pets it leaves out what the
   journals show only once collected. A toy, mount or pet species the game has no data for on this
   computer isn't listed, and neither is a mount, pet look, spell or item Clicky's list doesn't
   have.

*Result:* the entry is used, on a bar, or linked. A name that hasn't loaded yet (after logging in or
a reload) moves its entry into place when it arrives. A spell learned or an item
picked up, put away or worn, and a mount or pet learned, shows in the grid. Only toys, mounts and
pets have a star and a gift wrap. The mount the player is on and the pet that's out are
highlighted, in the grid and the drawers, as in the journals, and a pet shows its cooldown as in
the Pet Journal. A toy, mount or pet still in its gift wrap says NEW until it's clicked (a mount or
pet shows the gift in place of its icon, as the journals do), and that click opens it (without the
journals' animation) instead of using it. A pet look says NEW while any of its pets is wrapped, and
the click opens them all. Until it's opened, a wrapped mount or pet has no star in its menu. Only a
gift wrap makes NEW: something learned without one doesn't say it. In combat the grid's buttons
still work. Shift-click and right-click work too, and a toy, mount or pet still in its gift wrap
opens when it's clicked (to be used after the fight). A toy used shows its cooldown. Otherwise the
grid stays as it is: the scroll bar is off, the tabs don't change, and a search, a filter or
something the player learns, picks up or stars shows when the fight ends. If the player first opens
the Collections window in a fight, the Toy Box shows its own grid until the fight ends. The Toy Box's own filters are never changed; its progress bar is hidden,
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

## 17. Laser Pointer pets
*Goal: one button that brings out a pet that plays with the Laser Pointer toy.*
1. Open the **Pets** tab. Right-click one of the player's cats, choose **Add to new macro...**,
   type "Laser", and confirm.
2. Right-click each other pet that chases the pointer and tick **Laser**. A species owned in
   three colors shows three times; tick the colors wanted.
3. Add the Laser Pointer toy itself from the **Toys** tab if wanted, and drag Laser onto a bar.

*Result:* a click summons a random one of those pets (or uses the Laser Pointer). Each entry is a
species in one color, which stands for every pet of that color the player owns: the click summons
one that isn't out and can be summoned, a starred one first, so starring a pet in the Pet Journal
picks which of two same-colored cats comes out. The pet already out isn't picked, since summoning it
again would put it away (in a fight, see journey 2). A color on cooldown isn't picked either, as
with toys. In the grid, clicking a color again summons its other pet. In the drawer, clicking a
color whose only pet is out puts it away, as the Pet Journal's Summon button does. Caging or
releasing a pet leaves its color in the macro while the player has another pet of it; with none
left, the color stays greyed out (journey
13). A copy of the macro on another account summons that account's pets of the same colors (journey
12).

## 18. Ride a random mount
*Goal: a button that summons one of a few chosen mounts.*
1. Open the **Mounts** tab, right-click a mount, choose **Add to new macro...**, type "Ride", and
   confirm; tick **Ride** on a few more mounts.
2. Drag Ride onto a bar.

*Result:* a click summons a random one of its mounts that can be used where the player is: a mount
the game says can't be used there is skipped, and with none usable the player sees "No usable items
in Ride." The drawer shows them all to choose from.

## Later
- Adding many toys at once.
- An icon that shows the next toy.
