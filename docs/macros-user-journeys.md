# Clicky macros: user journeys

Players group toys into their own macros. Clicking a macro uses a random toy from it, and
right-clicking it opens a drawer of its toys to choose one from. Macros are managed from a toy's
right-click menu in the Toy Box and from a Clicky panel docked to the Toy Box's right edge.
Favorites (the Toy Box star) is always first; its toys are the starred ones.

## Decisions

Product decisions, so a change doesn't quietly undo one. Reviews check the code against them.
- 2026-10-17: No Random/Pick switch and no saved pick. Every macro is random on a click and has a
  drawer on a right-click. The point is less code.
- 2026-10-17: Favorites works like any other macro, with as few exceptions as possible.
- 2026-10-17: Alpha releases may break players' macros, with no migration code; full releases
  must not.
- 2026-10-17: No license, and no bug-report route for now.
- 2026-10-18: No saved variables: a macro is the only copy of its toys.
- 2026-10-18: Nothing in the repo states what the code or a cited source doesn't confirm.
- 2026-10-18: The launch bar is "not embarrassing", not best practice.

A Clicky macro is an ordinary general macro (in /macro) whose toys are written into it, so it
follows the player to any computer they play on, like the rest of their macros. Every macro
follows the same fixed rule: it holds up to 150 toys (Favorites, whose toys are the stars, has no
limit), and it catches up on up to 16 toys a patch adds among the toys it was saved with (old
items turned into toys) or takes out of the game.

## 1. Discover macros
*Goal: find out how to make a macro.*
1. Type /clicky (or open the Toy Box).

*Result:* the Toy Box opens with the Clicky panel listing Favorites, collapsed, and the hint
"Right-click a toy to make one."

## 2. Dress up in a few clicks
*Goal: look like a random costumed character, then add random extras on top.*
1. Click the **Illusion** macro on the action bar → a random costume toy is used.
2. Click the **Illusion mod** macro → a random hat, wings, etc. is added.
3. Click either again to reroll.

*Result:* a new random look in two clicks. Toys that can't be used right now are skipped, and if
none can be used the player sees "No usable toys in Illusion." A macro with no toys at all says how
to add some: "Illusion has no toys. Right-click toys in the Toy Box to add them." (Favorites: "Star
toys in the Toy Box to add them."). A toy that only turns out to fail when it's used shows WoW's
error, and the next click picks again.

In combat macros keep working, picking from the toys that were ready when the fight started.
That list can't change until the fight ends: a toy that comes off cooldown during the fight waits
until it's over, and a toy that goes on cooldown during the fight can still come up, and that
click shows WoW's error.

## 3. Make a macro
*Goal: start an "Illusion" macro.*
1. Open the Toy Box and right-click a costume toy the player owns.
2. Choose **Add to new macro...**, type "Illusion", and confirm.

*Result:* an Illusion general macro exists (in /macro too) with that toy's icon, and Illusion
appears in the Clicky panel, expanded to show that toy. Names are cut to WoW's 16-character macro
name limit. A name another Clicky macro has is refused, and so is a new macro when all general
macro slots are full; the dialog stays open with the reason.

## 4. Add toys to macros
*Goal: fill Illusion, and put some toys in more than one macro.*
1. Right-click a toy the player owns in the Toy Box.
2. Below **Set Favorite** (or **Remove Favorite**), choose **Add to Illusion**. The menu stays
   open and the entry now reads **Remove from Illusion**.
3. Choose **Add to Illusion mod** too if the toy belongs there as well.

*Result:* the toy is in both macros, and the panel shows them updated. A macro that already has
150 toys refuses another with "Illusion is full: a macro holds up to 150 toys." The limit never
changes as the collection grows. If the player has added so many lines of their own to the macro
in /macro that a change no longer fits, it's refused with "That macro is too long to update.
Remove your own lines from it in /macro."

## 5. See what's in a macro
*Goal: check what Illusion contains.*
1. In the Clicky panel, click **Illusion**. Click it again to hide its toys.

*Result:* its toys are listed alphabetically under it, the ones the player doesn't own greyed out
(they can still be removed), and hovering over one shows its tooltip. Every macro's toys are
hidden by default; each macro shows its toy count. Hovering over a macro's icon says to drag it to a bar and right-click it there.

## 6. Remove a toy from a macro
*Goal: take a toy the player is tired of out of Illusion.*
1. Right-click the toy in the panel (or in the Toy Box) and choose **Remove from Illusion**.

*Result:* the toy is gone from Illusion and stays in any other macros it's in.

## 7. Put a macro on an action bar
*Goal: get an Illusion button.*
1. In the Clicky panel, drag Illusion's icon onto an action bar (or drag it from /macro).

*Result:* an Illusion button on the bar. Other characters can put the same macro on their own
bars. Favorites' macro ("Favorites") is made the first time it's dragged or renamed; if all
general macro slots are full, a message says so.
To use a macro's toys from a macro of the player's own, its right-click menu in the panel has
**Copy /click line**, which shows `/click ClickySet<id>` selected to copy.

## 8. Rename or delete a macro
*Goal: tidy up macros.*
1. Right-click the macro in the panel and choose **Rename** or **Delete**.

*Result:* a renamed macro keeps working on the bars. Deleting asks for confirmation, then removes
the macro and its bar buttons. Favorites can be renamed and deleted too; once its macro is
deleted, Favorites stays in the panel and its macro is made again when it's next dragged.
Renaming or deleting the macro in /macro does the same, and the panel follows.

## 9. Play on another computer
*Goal: use Illusion on a laptop.*
1. Install Clicky on the laptop and log in.

*Result:* Illusion is there with its toys, in the panel and on the bars, as WoW brings the
player's macros to every computer. Nothing needs copying; it works as soon as the laptop has
loaded the player's toys.

## 10. New toys
*Goal: keep playing after learning toys, and after patches add toys to the game.*
1. Learn a toy, with Clicky running or not (the addon disabled, or another computer without it).
2. Log in after a patch that added toys to the game.

*Result:* every macro keeps its toys, here and on every other computer. Learning a toy changes
nothing: a macro's toys are written against every toy in the game, not the player's collection.
After a patch, Clicky re-saves its macros for the new toys. Clicky expects a patch's new toys to
have higher item IDs than the existing ones, and those change nothing; an old item turned into a
toy lands among them, and Clicky catches up on up to 16 of those per macro. More than 16 and the macro says so (journey 11).

## 11. A macro whose toys can't be read
*Goal: understand a macro Clicky can't use.*
1. Look at the macro in the panel, hover over it, or click it.

*Result:* the macro's icon is greyed out with a small warning mark, and its toy count shows "?".
Hovering over it, and clicking it (in the panel or on a bar), says why:
- Patches added more than 16 toys among the toys it was saved with: "Clicky can't work out which
  toys this macro holds: 17 toys were added to the game since it was saved, more than the 16 it
  can catch up on. Delete it and make it again."
- It was saved by a newer Clicky: "This macro was saved by a newer version of Clicky. Update
  Clicky to use it."
- Its `#clicky` line was changed (in /macro, say), or patches changed the game's toys more than
  Clicky can work out since it was saved (more than 16 taken out, or an old item turned into a
  toy while another was taken out):
  "Clicky can't read this macro's toys. Delete it and make it again."

It never uses toys that weren't put in it. Its toys can't be changed, but it can be renamed,
deleted or put on a bar.

## 12. Copy a macro
*Goal: make a variant of Illusion by copying its macro in /macro.*
1. Make a new general macro in /macro and paste Illusion's text into it. (Character macros
   aren't read: a copy there just clicks Illusion's buttons.)

*Result:* the copy is a Clicky macro of its own, with the same toys, its own random picks and its
own toy list from then on: changing one never changes the other. With Clicky running when the
copy is made, the macro it was copied from keeps its buttons, whatever the copy is called. Pasted
on another WoW account, it works there too (every account has the same game toys), with the toys that account
owns.

## 13. A toy leaves
*Goal: keep playing after a toy leaves the collection or the game.*
1. Log in after the patch.

*Result:* a toy the player no longer owns stays in its macros, greyed out in the panel and left out
of the drawer, and is never picked; it's picked again if it comes back. A toy taken out of the game's
data is dropped from its macros: Clicky works out up to 16 such toys per macro and re-saves it
without them. A macro saved before a patch that took out more than 16 can't be read (journey 11).

## 14. Use the drawer
*Goal: use a particular toy from a macro.*
1. Right-click the Hearthstones button on the action bar. A drawer opens at the mouse with every
   toy in Hearthstones the player owns, in the panel's order, showing their cooldowns.
2. Click a toy to use it right away; if it's on cooldown or can't be used here, the player sees
   the game's error, as with any toy.

*Result:* the drawer closes once a toy is chosen, and on Escape, a second right-click, or when the
mouse leaves it. Nothing is saved: a left click on the button still uses a random toy. This works
in combat too.

## Later
- Adding many toys at once.
- An icon that shows the next toy.
