# Clicky

Clicky turns your toys, mounts, pets, spells and items into action bar buttons. Group them into
macros, such as costumes, hearthstones or portals: click a macro's button for a random one, or
right-click it to choose from a drawer. Favorites uses the toys you star in the Toy Box. Your
macros follow you to every computer you play on.

![Clicky's grid in the Toy Box, with its Toys, Mounts, Pets, Spells and Items tabs and a search for "fire", and the Macros panel beside it](https://raw.githubusercontent.com/shadowpaxa/clicky/main/docs/images/panel.png)

## Installation

Clicky is for World of Warcraft Retail (Midnight). Get it from
[Wago](https://addons.wago.io/addons/clicky), or download it there and unzip it into
`World of Warcraft/_retail_/Interface/AddOns`.

## Getting started

1. Type `/clicky`. The Toy Box opens with Clicky's grid and, beside it, the Clicky panel, titled
   **Macros**.
2. Right-click a toy, mount, pet, spell or item, choose **Add to new macro...**, and name the macro.
3. Right-click more and tick your macro's name.
4. Drag the macro's icon from the panel to an action bar.
5. Click it for a random one; it skips the one used last. Right-click it to choose from its drawer.

## Ideas

- **Illusion:** costume toys, for a random look each click.
- **Hearthstones:** a click uses one that's off cooldown.
- **Portal:** portal toys, "Path of the ..." spells and a teleport cloak.
- **Laser:** pets that chase the Laser Pointer. A click summons one that isn't already out.
- **Favorites:** star toys in the Toy Box and drag Favorites from the panel to a bar.

![The Hearthstone macro's drawer, open above its button](https://raw.githubusercontent.com/shadowpaxa/clicky/main/docs/images/drawer.png)

## Good to know

- The grid has a tab each for **Toys**, **Mounts**, **Pets**, **Spells** and **Items**. Toys,
  Mounts and Pets have their own **Filter** menus; your Toy Box and journal filters aren't changed.
- The search finds names, sources, expansions, mount types, pet families and words in the tooltip.
- A check mark in the grid means the item is in one of your macros.
- Right-click a macro in the panel to rename or delete it, or to copy its `/click` line into a
  macro of your own.
- A click on a macro never picks gear that can be worn, since WoW would equip it. Choose it from the
  drawer: clicking it there wears it if it isn't worn, and uses it once it is.
- A pet in a macro is a species in one color. Of your pets in that color, a click summons a starred
  one first.
- In combat your buttons and drawers work, but macros can't be changed.
- You can add your own lines to a Clicky macro in `/macro`. Leave its `/click` and `#clicky` lines
  as they are: they hold its button and its items.
- Clicky changes only its own macros and the stars you set from its menus. If you remove Clicky,
  its macros stay in `/macro` and do nothing.

## Limits

- 100 items per macro. A macro holds 255 characters, and Clicky stores the items in it. Make a
  second macro for more.
- 120 general macros, shared by your whole account. Each Clicky macro is one of them.
- Macro names up to 16 characters.

## Slash commands

| Command | What it does |
|---|---|
| `/clicky` | Opens the Toy Box with Clicky's grid and panel |
| `/clicky status` | Shows how many of each macro's items you have and can use here |
| `/clicky debug` | Opens Clicky's state to copy for a bug report. Tick **Trace** in it to record each pick and change |

## Troubleshooting

**A click does nothing but say "No usable items in" and the macro's name.** None of its items can
be used right now: you don't have them, they're on cooldown, they're gear, or they can't be used
here (Favorites says "toys").

**A macro is greyed out with "?" for its item count.** Hover over it to see why:

- "This macro was saved by a newer version of Clicky": update Clicky.
- "Clicky can't read this macro's items": its `#clicky` line was changed. Delete the macro and make
  it again.

**Something from the latest patch isn't in the grid.** Clicky lists it once it's updated for that
patch.

**Something else is wrong, or you have an idea.** Leave a comment on
[Clicky's Wago page](https://addons.wago.io/addons/clicky).

## Development

[CLAUDE.md](https://github.com/shadowpaxa/clicky/blob/main/CLAUDE.md) has the rules the code
follows, how to run the tests and how to release.
