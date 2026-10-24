# Clicky

Clicky turns your toys into action bar buttons. Star toys in the Toy Box and the Favorites button
uses one of them each time you click it. Or group toys into your own macros, such as costumes or
hearthstones, and give each group its own button. Click a button for a random toy from it, or
right-click it for a drawer of its toys and choose one. Your macros follow you to every computer
you play on.

## Installation

Clicky is on [Wago](https://addons.wago.io/addons/clicky), not CurseForge. It only has alpha
releases so far, so if your addon manager hides alpha releases, turn them on for Clicky. To
install by hand, download it from Wago and unzip it into
`World of Warcraft/_retail_/Interface/AddOns`, so that you have an `AddOns/Clicky` folder.

## Getting started

1. Type `/clicky`. The Toy Box opens with the Clicky panel on its right.
2. Right-click a toy you own, choose **Add to new macro...**, and name the macro.
3. Right-click more toys and choose **Add to** followed by your macro's name.
4. Drag the macro's icon from the panel onto an action bar.
5. Click it to use a random toy from the macro. Right-click it to choose one from its drawer.

![The Clicky panel beside the Toy Box, with the Pet macro open](docs/images/panel.png)

## Using Clicky

### Favorites

Favorites is always at the top of the panel. It uses the toys you've starred in the Toy Box, so
starring or unstarring a toy changes it straight away. Drag it to a bar like any other macro; its
macro, called Favorites, is made the first time you do. You can rename it and delete it like your
own macros.

### Adding and removing toys

Right-click a toy you own in the Toy Box. Below **Set Favorite** (or **Remove Favorite**) you'll
see **Add to** followed by each macro's name, or **Remove from** for macros the toy is already in.
The menu stays open, so you can put one toy in several macros. Right-clicking a toy in the Clicky
panel gives the same choices.

If you've added so many lines of your own to a macro in `/macro` that another toy doesn't fit,
adding one says "That macro is too long to update. Remove your own lines from it in /macro."

### The drawer

Right-click a macro's button for its drawer: every toy in the macro you own, in the panel's
order, with their cooldowns. Click a toy to use it. The drawer closes when you choose a toy, press
Escape, right-click again or move the mouse away.

![A drawer open above the Portal and Hearthstone buttons](docs/images/drawer.png)

### In combat

A click picks from the toys that were ready when the fight started: a toy that comes off cooldown
mid-fight waits until the fight ends, and one that goes on cooldown mid-fight can still come up,
showing WoW's error for that click.

You can't make, rename or delete macros, add or remove their toys, or drag macros from the panel
in combat.

### Seeing a macro's toys

Click a macro in the panel to list its toys, and click it again to hide them. Toys you don't own
are greyed out; you can still remove them. Hover over a toy for its tooltip.

### Renaming and deleting

Right-click a macro in the panel and choose **Rename** or **Delete**. Deleting asks you to confirm, then removes the macro from your bars too.
Renaming or deleting it in `/macro` works the same way. Deleting Favorites' macro leaves
Favorites in the panel, ready to drag again.

### Using a macro's toys from your own macros

Right-click a macro in the Clicky panel, choose **Copy /click line** and copy the line it shows.
Paste it into a macro of your own to use a random toy from the Clicky macro there too:

```
/click ClickyBCDF
/say Surprise!
```

### Copying a macro

Make a new general macro in `/macro` and paste in the old macro's text. From then on the two are
separate, so changing one leaves the other alone. The text works on your other WoW accounts too.

## Slash commands

| Command | What it does |
|---|---|
| `/clicky` | Opens the Toy Box with the Clicky panel |
| `/clicky status` | Shows how many of each macro's toys you own, and how many are ready to use where you are |
| `/clicky debug` | Prints Clicky's full state |
| `/clicky trace` | Prints each pick and change as it happens. Type it again to stop; it also stops when you reload or log out |

## Limits

- 150 toys per macro (Favorites has no limit).
- Macro names up to 16 characters. Clicky won't give a macro a name another Clicky macro has.
- Each macro takes one of WoW's 120 general macro slots.
- You can't change macros in combat.

## Troubleshooting

**I clicked and nothing happened.**
If the macro has no toys, you'll see that it has none and how to add some. Otherwise none of its
toys can be used right now. Clicky leaves out toys you don't own, toys on cooldown and toys that
can't be used where you are. When nothing is left, you'll see "No usable toys in" and the macro's
name.

**A toy showed an error.**
Some toys pass Clicky's checks and still can't be used where you are; WoW shows its error. Your
next click picks again.

**A macro does nothing on another computer, and isn't in its Clicky panel.**
That computer is still on Clicky 0.4.0, which doesn't recognize macros made or converted by a
newer Clicky. Update Clicky there.

**A macro's icon is greyed out with "?" for its toy count.**
Clicky can't read that macro's toys. Hover over it for the reason:

- "This macro was saved by a newer version of Clicky": update Clicky.
- "Clicky can't read this macro's toys": its `#clicky` line was changed, or it was saved by
  Clicky 0.4.0 and couldn't be converted. Delete it and make it again.

You can still rename it, delete it or move it on your bars.

**I can't add a toy from the latest patch.**
You'll see "Clicky doesn't know this toy yet. Update Clicky." Clicky carries its own list of the
game's toys, and a patch's new toys join it when Clicky is updated for that patch.

## How it works

**Where are my macros' toys stored?**
In the macros. WoW keeps your macros on Blizzard's servers and copies them to each computer you
play on, while addon settings stay on one computer. So Clicky writes each macro's toys into the
macro as a line starting with `#clicky`, which does nothing when the macro runs.

**Can I edit a Clicky macro in `/macro`?**
Yes. You can add your own lines and Clicky keeps them. Leave the `/click` line and the `#clicky`
line as they are: your bars rely on the first, and the second holds the toys. If the `#clicky`
line is changed, Clicky shows the macro greyed out with "?" rather than guess its toys; delete it
and make it again.

![A Clicky macro in /macro: its /click line and its #clicky line](docs/images/macro.png)

**Why does each macro click something called Clicky plus four letters?**
WoW only lets a toy be used when you click something, not when an addon asks. So each macro
clicks a hidden button called `Clicky` plus four random letters, which holds the random toy your
click uses. A right-click goes to a second hidden button, `ClickyP` plus the same four letters,
which opens the drawer.

**What happens to a toy I no longer own?**
It stays in the macro, greyed out in the panel and left out of the drawer, and is used again if
you get it back.

**What happens when a patch adds or removes toys?**
Your macros keep their toys: Clicky carries its own list of the game's toys, so a patch can't
change which toys a macro holds. You can add a patch's new toys once Clicky is updated for that
patch. A toy taken out of the game stays in your macros; you can remove it in the panel.

**What happens if I remove Clicky?**
Its macros stay in `/macro` and do nothing when clicked. Delete them there, or install Clicky
again and they work as before.

## Development

[docs/architecture.md](docs/architecture.md) covers how the code fits together, running the
tests, and making releases.
