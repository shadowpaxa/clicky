# Clicky

Clicky turns your toys, spells and items into action bar buttons. Star toys in the Toy Box and the
Favorites button uses one of them each time you click it. Or group toys, spells and things from
your bags into your own macros, such as costumes, hearthstones or portals, and give each group its
own button. Click a button for a random one from it, or right-click it for a drawer of what it
holds and choose one. Your macros follow you to every computer you play on.

![Clicky's grid of toys in the Toy Box, with the Clicky panel beside it and the Portal macro open](docs/images/panel.png)

## Installation

Clicky is on [Wago](https://addons.wago.io/addons/clicky), not CurseForge. It only has alpha
releases so far, so if your addon manager hides alpha releases, turn them on for Clicky. To
install by hand, download it from Wago and unzip it into
`World of Warcraft/_retail_/Interface/AddOns`, so that you have an `AddOns/Clicky` folder.

## Getting started

1. Type `/clicky`. The Toy Box opens, showing Clicky's grid and the Clicky panel on its right.
2. Right-click a toy, a spell or an item you own, choose **Add to new macro...**, and name the
   macro.
3. Right-click more and tick your macro's name.
4. Drag the macro's icon from the panel onto an action bar.
5. Click it to use a random one from the macro. It skips the one it used last, unless that's the
   only one ready. Right-click it to choose one from its drawer.

Clicky's messages call everything a macro holds an *item*: a toy, a spell, or something in your
bags or that you're wearing. Favorites holds only toys, so its messages say toys.

## What you can do

**Dress up at random.** Make an **Illusion** macro with your costume toys, and an **Illusion mod**
macro with hats, wings and other toys that add to your look. Click Illusion for a random costume,
then Illusion mod for a random extra on top. Click either again for a new look.

**Take whichever hearthstone is ready.** Put your hearthstone toys in a **Hearthstones** macro. A
click uses a random one that isn't on cooldown. Right-click for its drawer, which shows each one's
cooldown, and click the one you want.

![The Hearthstone macro's drawer, open above its button](docs/images/drawer.png)

**Keep your portals on one button.** Put your portal toys, your "Path of the ..." spells and a
teleport cloak from your bags in a **Portal** macro. Click for a random toy or spell, or
right-click and pick where you're going from the drawer. The cloak is only in the drawer: a click
never picks gear (see "Wearable items" below).

**Put your favorite toys on one button.** Star toys in the Toy Box and drag **Favorites** from the
Clicky panel to a bar. It uses a random starred toy. Star or unstar a toy and it changes straight
away.

**Add a line of your own.** Paste a macro's `/click` line into a macro of yours, with a `/say`
line, and you say something each time you click it (see "Using a macro's items from your own
macros" below).

**Play on another computer.** Install Clicky there and your macros are in the panel and on your
bars, with what they hold. Nothing needs copying.

## Using Clicky

### The grid

Clicky shows its own grid in place of the Toy Box's, with a tab each for **Toys**, **Spells** and
**Items**. Each tab says how many it lists, as **Toys (809)**, and the counts follow the search.

The **Toys** tab lists your favorites first, each with the Toy Box's star, then the rest of your
toys, then the toys you don't have if you've ticked **Not Collected**. Each group is sorted by name.
Not Collected lists the same toys as the Toy Box's own Not Collected. Click a toy to use it, drag
it to an action bar, or shift-click it to link it in chat. Hover over a toy to see its name. A
check mark means the toy, spell or item is in one of your Clicky macros. Favorites' toys have their
star instead.

The **Spells** tab lists the spells you know, and the **Items** tab the items in your bags or worn,
each sorted by name. The Items tab lists only items with a "Use:" effect that Clicky's own list has
(see "How it works"). Click a spell to cast it and an item to use it; gear you aren't wearing is
worn when you click it. Drag, shift-click and right-click work as on toys. Spells and items have no
star, so Favorites stays toys only. The grid follows what you learn, pick up, put away or wear.

Scroll the grid with the mouse wheel or the scroll bar. It scrolls in whole rows; a wheel notch
moves three. A search, a filter or another tab takes you back to the top.

A toy you've just learned says NEW until you hover over it. A toy still in its gift wrap says NEW
until you click it, and that click unwraps it, without the Toy Box's animation.

Search by name in the search box; it looks at every tab. On the Toys tab, the **Filter** menu shows
toys you've collected and toys you haven't, and **Usable Only** hides toys you have but this
character can't use right now. It starts with collected toys only. These are Clicky's own: your Toy
Box's filters stay as you set them.

### Favorites

Favorites is always at the top of the panel. It uses the toys you've starred in the Toy Box, so
starring or unstarring a toy changes it straight away. Drag it to a bar like any other macro; its
macro, called Favorites, is made the first time you drag or rename it. You can rename it and
delete it like your own macros.

### Adding and removing items

Right-click a toy, spell or item you own in the grid. Under **Clicky macros** (below **Set
Favorite** or **Remove Favorite** on a toy), each macro has a checkbox with its name, ticked if the
item is in it. Click one to put the item in that macro or take it out. The menu stays open, so you
can put one item in several macros. Right-clicking an item in the Clicky panel gives the same
choices. Only a toy has Set Favorite.

### The drawer

Right-click a macro's button for its drawer: everything in the macro you have, in the panel's
order, with cooldowns. Click one to use it. The drawer closes when you choose, press Escape,
right-click again or move the mouse away. If you have none of the macro's items, a right-click
says so, as a click does.

### Wearable items

A click on a macro never picks gear that can be worn, such as a teleport cloak. WoW's item action
wears gear that isn't worn instead of using it, so a random pick could change your equipment.
Choose it from the drawer: clicking it there wears it if it isn't worn, and uses it once it is.
In the grid, clicking gear works the same way.

### Seeing a macro's items

Click a macro in the panel to list what it holds, and click it again to hide it. Items you don't
have (a toy you don't own, a spell you don't know, something no longer in your bags) are greyed
out; you can still remove them. Hover over one for its tooltip.

### Renaming and deleting

Right-click a macro in the panel and choose **Rename** or **Delete**. Deleting asks you to confirm,
then removes the macro from your bars too. Renaming or deleting it in `/macro` works the same way.
Deleting Favorites' macro leaves Favorites in the panel, named Favorites again and ready to drag.
Two Clicky macros can't have the same name.

### Using a macro's items from your own macros

Right-click a macro in the Clicky panel, choose **Copy /click line** and copy the line it shows.
Paste it into a macro of your own to use a random item from the Clicky macro there too:

```
/click ClickyBCDF
/say Surprise!
```

### Copying a macro

Make a new general macro in `/macro` and paste in the old macro's text. From then on the two are
separate, so changing one leaves the other alone. The text works on your other WoW accounts too.

## In combat

Your buttons and drawers work in a fight. A click picks from the items that were ready when the
fight started: an item that comes off cooldown mid-fight waits until the fight ends, and one that
goes on cooldown mid-fight can still come up, showing WoW's error for that click.

WoW doesn't let addons make or change macros in a fight, so you can't make, rename or delete
macros, add or remove their items, or drag macros from the panel until it ends.

`/clicky` in combat says "Can't open the Toy Box in combat." Open the Toy Box before the fight.

The grid still uses toys, spells and items in a fight. Shift-click and right-click work too, and a
toy still in its gift wrap opens when you click it (use it after the fight). A toy you use shows
its cooldown, and hovering over a toy you learned this session clears NEW (a toy in its gift wrap
keeps NEW until you click it). Otherwise the grid stays as it is: the scroll bar is off, the tabs
don't change, and a search, a filter or something you learn, pick up or star shows when the fight
ends. If you first
open the Collections window in a fight, the Toy Box shows its own grid until the fight ends.

## Limits

- 100 items per macro, in any mix of toys, spells and items. A WoW macro holds 255 characters, and
  Clicky keeps a macro's items in the macro itself (see "How it works"). 100 is the most that
  always fits, whichever you choose. For more, make a second macro. Favorites has no limit: its
  toys are your Toy Box stars, which WoW keeps for you, so its macro holds none.
- Macro names up to 16 characters, the most WoW's macro name box holds. A longer name is cut short.
- 120 general macros, shared by your whole account. Each Clicky macro is a general macro, so it's
  on every character on your account and takes one of those 120. Delete macros you no longer use
  in `/macro` to make room.
- No changes to macros in combat, because WoW doesn't allow them then (see "In combat").

## Slash commands

| Command | What it does |
|---|---|
| `/clicky` | Opens the Toy Box, with Clicky's grid and panel |
| `/clicky status` | Shows how many toys you own, then how many of each macro's items you have and how many are ready to use where you are |
| `/clicky debug` | Prints Clicky's full state |
| `/clicky trace` | Prints each pick and change as it happens. Type it again to stop; it also stops when you reload or log out |

## Troubleshooting

**I clicked and nothing happened.**
If the macro has no items, you'll see that it has none and how to add some. Otherwise none of its
items can be used right now. Clicky leaves out items you don't have, items on cooldown, gear that
can be worn (it's in the drawer only) and items that can't be used where you are. When nothing is
left, you'll see "No usable items in" and the macro's name (Favorites says "toys").

**An item showed an error.**
Some items pass Clicky's checks and still can't be used where you are; WoW shows its error. Your
next click picks again.

**Adding an item says the macro is too long.**
If you've added so many lines of your own to a macro in `/macro` that another item doesn't fit,
adding one says "That macro is too long to update. Remove your own lines from it in /macro."

**Adding an item says the macro is full.**
A macro holds up to 100 items (see "Limits"), and adding one more says "Illusion is full: a macro
holds up to 100 items." with your macro's name. Make a second macro for the rest.

**Making a macro says your general macros are full.**
WoW allows 120 general macros per account, and each Clicky macro is one of them. Making another
says "Your general macros are full. Delete one in /macro and try again."

**A change says "Can't change macros in combat."**
WoW doesn't let addons change macros in a fight. Make the change once it ends. Dragging a macro
from the panel in a fight says "Can't drag macros in combat."; drag it once the fight ends.

**`/clicky` says "Can't open the Toy Box in combat."**
WoW doesn't let addons open the Collections window in a fight. Open it once the fight ends, or
before the next one.

**Making or renaming a macro says "There's already a macro called" and its name.**
Two Clicky macros can't share a name. Choose another name.

**A macro does nothing on another computer, and isn't in its Clicky panel.**
That computer is still on Clicky 0.4.0, which doesn't recognize macros made by a
newer Clicky. Update Clicky there.

**A macro from Clicky 0.4.0 is greyed out in the panel.**
This version doesn't read macros Clicky 0.4.0 made. Delete it and make it again. Favorites'
button from 0.4.0 does nothing and has no row in the panel: drag Favorites from the panel to your
bar again; the old macro stays in /macro until you delete it.

**A macro's icon is greyed out with "?" for its item count.**
Clicky can't read that macro's items. Hover over it for the reason:

- "This macro was saved by a newer version of Clicky": update Clicky.
- "Clicky can't read this macro's items": its `#clicky` line was changed, or it was saved by
  Clicky 0.4.0 or 0.5.0. Delete it and make it again.

You can still rename it, delete it or move it on your bars.

**A toy, spell or item from the latest patch isn't in the grid.**
Clicky carries its own list of the game's toys, spells and items, and a patch's new ones join it
when Clicky is updated for that patch. Until then it isn't in Clicky's grid, so you can't add it
to a macro. The grid also lists a spell or item only while you know it or carry it.

## How it works

**Where are my macros' items stored?**
In the macros. WoW keeps your macros on Blizzard's servers and copies them to each computer you
play on, while addon settings stay on one computer. So Clicky writes each macro's items into the
macro as a line starting with `#clicky`, which does nothing when the macro runs. That line shares
the macro's 255 characters with the `/click` line and any lines you add, which is why a macro
holds up to 100 items.

**Can I edit a Clicky macro in `/macro`?**
Yes. You can add your own lines and Clicky keeps them. Leave the `/click` line and the `#clicky`
line as they are: your bars rely on the first, and the second holds the items. If the `#clicky`
line is changed, Clicky shows the macro greyed out with "?" rather than guess its items; delete it
and make it again. If either line is removed, the macro is no longer a Clicky macro: it leaves the
panel and no longer uses items.

![The Hearthstone macro in /macro: its /click line and its #clicky line](docs/images/macro.png)

**Why does each macro click something called Clicky plus four letters?** WoW only lets a toy be
used when you click something, not when an addon asks. So each macro clicks a hidden button called
`Clicky` plus four random letters, which holds the random item your click uses (a spell or an item
goes through the same button). A right-click goes to a second hidden button, `ClickyP` plus the
same four letters, which opens the drawer.

**Does Clicky change my settings?**
No. It changes only its own macros and buttons, a toy's star when you choose that from the toy's
menu, and a toy's gift wrap when you click the toy to open it, as the Toy Box does. Your Toy Box
filters and other settings stay as you set them.

**What happens to an item I no longer have?**
It stays in the macro, greyed out in the panel and left out of the drawer, and is used again if
you get it back.

**What happens when a patch adds or removes toys, spells or items?**
Your macros keep what they hold: Clicky carries its own list of the game's toys, spells and items,
so a patch can't change which a macro holds. You can add a patch's new ones once Clicky is updated
for that patch. One taken out of the game stays in your macros; you can remove it in the panel.

**What happens if I remove Clicky?**
Its macros stay in `/macro` and do nothing when clicked. Delete them there, or install Clicky
again and they work as before.

## Development

[docs/architecture.md](docs/architecture.md) covers how the code fits together, running the
tests, and making releases.
