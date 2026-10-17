# Clicky

Clicky turns your toys into random-toy buttons. Star toys in the Toy Box and the Favorites
button picks one of them each time you click it. Or group toys into your own macros, such as
costumes or hearthstones, and give each group its own button. Your macros work on every computer
you play on.

## Installation

- **WowUp:** use the Wago edition of [WowUp](https://wowup.io). Set the addon channel to
  **Alpha**, since Clicky only has alpha releases so far, then search for Clicky.
- **By hand:** unzip Clicky into `World of Warcraft/_retail_/Interface/AddOns`, so that you have
  an `AddOns/Clicky` folder.

## Getting started

1. Type `/clicky`. The Toy Box opens with the Clicky panel on its right.
2. Right-click a toy, choose **Add to new macro...**, and name the macro.
3. Drag the macro's icon from the panel onto an action bar.
4. Click it to use a random toy from the macro.

## Using Clicky

### Favorites

Favorites is always at the top of the panel. It picks from the toys you've starred in the Toy
Box, so starring or unstarring a toy changes it straight away. Drag it to a bar like any other
macro.

### Adding and removing toys

Right-click a toy in the Toy Box. Under **Set Favorite** you'll see **Add to** followed by each
macro's name, or **Remove from** for macros the toy is already in. The menu stays open, so you
can put one toy in several macros. Right-clicking a toy in the Clicky panel gives the same
choices.

### Seeing a macro's toys

Click a macro in the panel to list its toys, and click it again to hide them. Hover over a toy
for its tooltip.

### Renaming and deleting

Right-click a macro in the panel and choose **Rename** or **Delete**. A renamed macro keeps
working on your bars. Deleting asks you to confirm, then removes the macro from your bars too.
Renaming or deleting it in `/macro` works the same way. Favorites can't be renamed or deleted.

### Copying a macro

Make a new general macro in `/macro` and paste in the old macro's text. From then on the two are
separate, so changing one leaves the other alone. The text works on your other WoW accounts too.

### Playing on another computer

Install Clicky and log in. Your macros and their toys are already there.

## Slash commands

| Command | What it does |
|---|---|
| `/clicky` | Opens the Toy Box with the Clicky panel |
| `/clicky status` | Shows how many of each macro's toys you own, and how many you can use where you are |
| `/clicky debug` | Prints Clicky's full state, to include when reporting a problem |
| `/clicky trace` | Prints each pick and change as it happens, until you reload or log out |

## Limits

- 150 toys per macro.
- Macro names up to 16 characters, and no two Clicky macros can have the same name.
- Each macro takes one of WoW's 120 general macro slots.
- Macros don't work in combat, and you can't change them in combat.

## Troubleshooting

**I clicked and nothing happened.**
Either you're in combat, or none of the macro's toys can be used right now. Clicky leaves out
toys you don't own, toys on cooldown and toys that can't be used where you are. When nothing is
left, you'll see "No usable toys in" and the macro's name.

**Clicky keeps skipping a toy.**
When a toy fails to work, Clicky leaves it out until you change zones.

**A macro is greyed out with "?" for its toy count.**
Clicky can't read that macro's toys. Hover over it for the reason:

- *Too many toys were added to the game since it was saved.* Delete it and make it again.
- *It was saved by a newer version of Clicky.* Update Clicky.
- *Its data is damaged, or a patch took more than two toys out of the game since it was saved.*
  Delete it and make it again.

You can still rename it, delete it or move it on your bars.

## How it works

**Where are my macros' toys stored?**
In the macros. WoW keeps your macros on Blizzard's servers and copies them to each computer you
play on, while addon settings stay on one computer. So Clicky writes each macro's toys into the
macro as a line starting with `#clicky`. WoW skips lines that start with `#` when it runs a
macro.

**Can I edit a Clicky macro in `/macro`?**
Yes. You can add your own lines and Clicky keeps them. Leave the `/click` line and the `#clicky`
line as they are: your bars rely on the first, and the second holds the toys.

**Why does each macro click something called ClickySet?**
WoW only lets a toy be used when you click something, not when an addon asks. So each macro
clicks a hidden button called `ClickySet` plus a number, and Clicky puts a random toy on that
button just before your click reaches it.

**What happens to a toy I no longer own?**
It stays in the macro and is picked again if you get it back.

**What happens when a patch adds or removes toys?**
Your macros keep their toys (except any taken out of the game), and Clicky updates them for the new list when you log in. If a patch
changes too much for an old macro to be worked out, it shows greyed out (see Troubleshooting).

## Development

[docs/architecture.md](docs/architecture.md) covers how the code fits together, running the
tests, and making releases.
