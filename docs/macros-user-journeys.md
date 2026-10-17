# Clicky macros: user journeys

Players group toys into their own macros. Each macro uses a random toy from its toys. Macros are
managed from a toy's right-click menu in the Toy Box and from a Clicky panel docked to the Toy
Box's right edge. Favorites (the Toy Box star) is always first.

A Clicky macro is an ordinary general macro (in /macro) whose toys are written into it, so it
follows the player to any computer they play on, like the rest of their macros. Every macro
follows the same fixed rule: it holds up to 150 toys, and it catches up on up to 16 toys a patch
adds among the toys it was saved with (old items turned into toys). Both are guaranteed while the
game has up to 2,900 toys (it has about 1,200).

## 1. Discover macros
*Goal: find out how to make a macro.*
1. Type /clicky (or open the Toy Box).

*Result:* the Toy Box opens with the Clicky panel listing Favorites, collapsed, and the hint
"Right-click a toy, then Add to new macro...".

## 2. Dress up in a few clicks
*Goal: look like a random costumed character, then add random extras on top.*
1. Click the **Illusion** macro on the action bar → a random costume toy is used.
2. Click the **Illusion mod** macro → a random hat, wings, etc. is added.
3. Click either again to reroll.

*Result:* a new random look in two clicks. Toys that can't be used right now are skipped, and if
none can be used the player sees "No usable toys in Illusion." Macros do nothing in combat.

## 3. Make a macro
*Goal: start an "Illusion" macro.*
1. Open the Toy Box and right-click a costume toy.
2. Choose **Add to new macro...**, type "Illusion", and confirm.

*Result:* an Illusion general macro exists (in /macro too) with that toy's icon, and Illusion
appears in the Clicky panel, expanded to show that toy. Names are cut to WoW's 16-character macro
name limit. A name another Clicky macro has is refused, and so is a new macro when all general
macro slots are full; the dialog stays open with the reason.

## 4. Add toys to macros
*Goal: fill Illusion, and put some toys in more than one macro.*
1. Right-click a toy in the Toy Box.
2. Under **Set Favorite**, choose **Add to Illusion**. The menu stays open and the entry now
   reads **Remove from Illusion**.
3. Choose **Add to Illusion mod** too if the toy belongs there as well.

*Result:* the toy is in both macros, and the panel shows them updated. A macro that already has
150 toys refuses another with "Illusion is full: a macro holds up to 150 toys." The limit never
changes as the collection grows. If the player has added so many lines of their own to the macro
in /macro that a change no longer fits, it's refused with the reason.

## 5. See what's in a macro
*Goal: check what Illusion contains.*
1. In the Clicky panel, click **Illusion**. Click it again to hide its toys.

*Result:* its toys are listed alphabetically under it, and hovering over one shows its tooltip.
Every macro's toys are hidden by default; each macro shows its toy count.

## 6. Remove a toy from a macro
*Goal: take a toy the player is tired of out of Illusion.*
1. Right-click the toy in the panel (or in the Toy Box) and choose **Remove from Illusion**.

*Result:* the toy is gone from Illusion and stays in any other macros it's in.

## 7. Put a macro on an action bar
*Goal: get an Illusion button.*
1. In the Clicky panel, drag Illusion's icon onto an action bar (or drag it from /macro).

*Result:* an Illusion button on the bar. Other characters can put the same macro on their own
bars. Favorites' macro ("Clicky") is made the first time it's dragged; if all general macro
slots are full, a message says so.

## 8. Rename or delete a macro
*Goal: tidy up macros.*
1. Right-click the macro in the panel and choose **Rename** or **Delete**.

*Result:* a renamed macro keeps working on the bars. Deleting asks for confirmation, then removes
the macro and its bar buttons. Favorites can't be renamed or deleted. Renaming or deleting the
macro in /macro does the same, and the panel follows.

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
After a patch, Clicky re-saves its macros for the new toys. A patch's new toys come after the
existing ones and change nothing; an old item turned into a toy (Dalaran Hearthstone, for one)
lands among them, and Clicky catches up on up to 16 of those per macro. More than 16 and the
macro says so (journey 11).

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
- Its data is damaged, or a patch took more than two of the game's toys out since it was saved:
  "Clicky can't read this macro's toys. Delete it and make it again."

It never uses toys that weren't put in it. Its toys can't be changed, but it can be renamed,
deleted or put on a bar.

## 12. Copy a macro
*Goal: make a variant of Illusion by copying its macro in /macro.*
1. Make a new general macro in /macro and paste Illusion's text into it. (Character macros
   aren't read: a copy there just clicks Illusion's button.)

*Result:* the copy is a Clicky macro of its own, with the same toys, its own random picks and its
own toy list from then on: changing one never changes the other. Pasted on another WoW account,
it works there too (every account has the same game toys), with the toys that account owns.

## 13. A toy leaves
*Goal: keep playing after a toy leaves the collection (Blizzard moved The Warband Map to
Everywhere All At Once out of the Toy Box in 11.0.5) or the game.*
1. Log in after the patch.

*Result:* a toy the player no longer owns stays in its macros and is just never picked, and is
picked again if it comes back. A toy taken out of the game's data is dropped from its macros:
Clicky works out one or two such toys per macro and re-saves it without them. A macro saved
before a patch that took out more than two can't be read (journey 11).

## Later
- Adding many toys at once.
- An icon that shows the next toy.
