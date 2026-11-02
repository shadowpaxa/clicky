#!/usr/bin/env python3
"""Checks that Clicky only uses WoW API that exists, against current sources rather than memory.

1. lua-language-server with Ketho's WoW API annotations (tests/.cache/vscode-wow-api) checks the
   game's C API and widget API: names, argument counts and types. Any diagnostic fails, except
   undefined globals, which go to step 2.
2. Blizzard's UI code (tests/.cache/wow-ui-source, live branch) checks what the annotations don't
   cover: Blizzard Lua globals (StaticPopup_Show, ScrollBoxConstants, GlobalStrings...),
   CreateFrame templates, events, the Toy Box child frames Clicky reads, and methods Clicky calls
   on Blizzard objects (ScrollBox, menus, dialogs). A global counts if Blizzard's code defines it
   or uses it.

3. Events: for each system in Blizzard's generated API docs that Clicky calls a function of, every
   event it documents that Clicky doesn't register must be in REVIEWED_EVENTS with the reason
   Clicky doesn't need it, so a patch that adds one fails here until someone looks.

Steps 2h and 3 cover only what the generated docs list: C_ToyBox, most of the C_PetJournal
functions Clicky calls and the macro API (CreateMacro, EditMacro, GetMacroInfo) aren't there. For
those, Blizzard's own windows (Blizzard_ToyBox.lua, Blizzard_PetCollection.lua, Blizzard_MacroUI)
were compared by hand.

Run tests/fetch.sh first. Exits non-zero on any problem.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("CLICKY_ROOT", HERE)  # another checkout to check, e.g. to test this script
CACHE = os.path.join(HERE, "tests", ".cache")
UI = os.path.join(CACHE, "wow-ui-source", "Interface")
ANNOTATIONS = os.path.join(CACHE, "vscode-wow-api", "Annotations")
ADDON = ROOT

problems = []


# Step 3: the events of the systems Clicky calls into that it doesn't register, each reviewed:
# {system (the documentation file's name less Documentation.lua): [events]}, a reason per group.
REVIEWED_EVENTS = {
    "AddOns": [
        "ADDONS_UNLOADING", "SAVED_VARIABLES_TOO_LARGE",  # Clicky has no saved variables (Clicky.toc)
    ],
    "Container": [
        # Items.lua redraws on BAG_UPDATE_DELAYED, not on each bag's or slot's change.
        "BAG_UPDATE", "BAG_CONTAINER_UPDATE", "BAG_NEW_ITEMS_UPDATED", "BAG_SLOT_FLAGS_UPDATED",
        # Clicky shows no bag window, bag bar, bag search or locked item.
        "BAG_OPEN", "BAG_CLOSED", "EXPAND_BAG_BAR_CHANGED", "USE_COMBINED_BAGS_CHANGED",
        "INVENTORY_SEARCH_UPDATE", "ITEM_LOCK_CHANGED", "ITEM_LOCKED", "ITEM_UNLOCKED",
        # Prompts and notices of Blizzard's bags; Clicky shows and answers none.
        "BAG_OVERFLOW_WITH_FULL_INVENTORY", "EQUIP_BIND_REFUNDABLE_CONFIRM", "EQUIP_BIND_TRADEABLE_CONFIRM",
    ],
    "Expansion": [
        # GridFilters.lua reads GetNumExpansions when it builds the Expansion menu.
        "MAX_EXPANSION_LEVEL_UPDATED", "MIN_EXPANSION_LEVEL_UPDATED",
        "SHOW_SUBSCRIPTION_INTERSTITIAL",  # a Blizzard prompt
    ],
    "Item": [
        # Confirmation prompts and bind notices of Blizzard's UI; Clicky shows and answers none.
        "ACTION_WILL_BIND_ITEM", "BIND_ENCHANT", "CONFIRM_BEFORE_USE", "CONVERT_TO_BIND_TO_ACCOUNT_CONFIRM",
        "DELETE_ITEM_CONFIRM", "END_BOUND_TRADEABLE", "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", "REPLACE_ENCHANT",
        "REPLACE_TRADESKILL_ENCHANT", "TRADE_REPLACE_ENCHANT", "USE_BIND_CONFIRM", "USE_NO_REFUND_CONFIRM",
        # Clicky shows no item conversion, character fixup, weapon enchant, count or changed link; it
        # reads an item's link when it is shift-clicked and whether it is owned on a redraw (Items.lua).
        "CHARACTER_ITEM_FIXUP_NOTIFICATION", "ITEM_CONVERSION_DATA_READY", "WEAPON_ENCHANT_CHANGED",
        "ITEM_CHANGED", "ITEM_COUNT_CHANGED",
    ],
    "MountJournal": [
        "MOUNT_EQUIPMENT_APPLY_RESULT",  # Clicky applies no mount equipment
        "MOUNT_JOURNAL_SEARCH_UPDATED",  # the Mount Journal's own search; Clicky's grid has its own
    ],
    "PetJournalInfo": [
        # Battle loadout, trap level and name prompts; Clicky shows none of them.
        "BATTLEPET_FORCE_NAME_DECLENSION", "PET_JOURNAL_AUTO_SLOTTED_PET", "PET_JOURNAL_NEW_BATTLE_SLOT",
        "PET_JOURNAL_TRAP_LEVEL_SET", "UPDATE_SUMMONPETS_ACTION",
        # The Pet Journal redraws its battle loadout on it (Blizzard_PetCollection.lua:260); Clicky
        # shows no battle loadout or health. Pets.lua's Summonable asks PetIsSummonable at each click.
        "PET_JOURNAL_PETS_HEALED",
        # The Pet Journal only clears a pending cage on it (:258); the pet stays.
        "PET_JOURNAL_CAGE_FAILED",
        # No Blizzard window in the UI source handles these.
        "PET_JOURNAL_PET_RESTORED", "PET_JOURNAL_PET_REVOKED",
        # Learned and unlearned companions: Blizzard's Collections button and Mount Journal redraw on
        # them (MainMenuBarMicroButtons.lua:1433, Blizzard_MountCollection.lua:414); Clicky takes what
        # was learned from NEW_MOUNT_ADDED and NEW_PET_ADDED, and reads a mount's state from the game
        # when it draws (Mounts.lua keeps none), so an unlearned mount shows as such at the next redraw.
        "COMPANION_LEARNED", "COMPANION_UNLEARNED",
    ],
    "RestrictedActions": [
        # Blizzard's reports of blocked actions; Clicky checks InCombatLockdown before acting.
        "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN",
        # No Blizzard window handles it. Spells.lua asks issecretvalue at every read, and the grid
        # redraws cooldowns on SPELL_UPDATE_COOLDOWN (Grid.lua), as the Toy Box does.
        "ADDON_RESTRICTION_STATE_CHANGED",
    ],
    "SpellBook": [
        # Cast, auto-repeat and totem state; Clicky shows none.
        "CURRENT_SPELL_CAST_CHANGED", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_TOTEM_UPDATE",
        "MAX_SPELL_START_RECOVERY_OFFSET_CHANGED",
        # Spells.lua redraws on SPELLS_CHANGED, and walks the spellbook and its flyouts when the grid is built.
        "LEARNED_SPELL_IN_SKILL_LINE", "SPELL_FLYOUT_UPDATE",
        # Action bar placement; Clicky has no action bar.
        "SPELL_PUSHED_TO_ACTIONBAR", "SPELL_PUSHED_TO_FLYOUT_ON_ACTIONBAR",
        # Charges, uses and usability: Clicky shows none live. It asks whether a spell is usable when a
        # macro's button picks (Macros.lua GetCandidates); the grid's usable filters are only for toys
        # and mounts (GridFilters.lua).
        "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES", "SPELL_UPDATE_USABLE",
        "UPDATE_SHAPESHIFT_COOLDOWN", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
        "UPDATE_SHAPESHIFT_USABLE",
        # The action button redraws its icon on it (ActionButton.lua:1025). Clicky reads a spell's icon
        # (GetSpellTexture) whenever a view is drawn and has no button that stays up between draws; no
        # source shows a spell in Clicky's list changing its icon.
        "SPELL_UPDATE_ICON",
    ],
    "Spell": [
        # Enchanting's target item.
        "ENCHANT_SPELL_COMPLETED", "ENCHANT_SPELL_SELECTED", "UPDATE_SPELL_TARGET_ITEM_CONTEXT",
        "SPELL_RANGE_CHECK_UPDATE",  # only after EnableSpellRangeCheck, which Clicky doesn't call
        # Sent for the text of C_Spell.GetSpellDescription and GetSpellSubtext (SpellDocumentation.lua),
        # which Clicky doesn't call. Its spell text is the tooltip's (C_TooltipInfo.GetSpellByID), which
        # GameTooltip refreshes on TOOLTIP_DATA_UPDATE (GameTooltip.lua:970), as Search.lua does.
        "SPELL_TEXT_UPDATE",
    ],
    "TooltipInfo": [
        "HIDE_HYPERLINK_TOOLTIP", "SHOW_HYPERLINK_TOOLTIP",  # hovering a chat link; Clicky's tooltips are its own
    ],
}

FUNCTION = re.compile(r'\n\t\t\{\n\t\t\tName = "(\w+)",\n\t\t\tType = "Function",(.*?)\n\t\t\},', re.S)


def doc_functions(text):
    """(namespace, name, body) of each function a generated documentation file lists. The namespace
    is the file's, unless the function has its own Namespace: "" makes it a global in a namespaced
    file (InCombatLockdown in RestrictedActions's C_RestrictedActions)."""
    file_ns = re.search(r'\n\tNamespace = "(\w*)"', text)
    for m in FUNCTION.finditer(text):
        own = re.search(r'\n\t\t\tNamespace = "(\w*)"', m.group(2))
        found = own or file_ns
        yield found.group(1) if found else "", m.group(1), m.group(2)


def read_tree(base, exts):
    texts = []
    for dirpath, _, files in os.walk(base):
        for name in files:
            if name.endswith(exts):
                with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as f:
                    texts.append(f.read())
    return "\n".join(texts)


# The files Clicky.toc loads, as WoW does. Listing the folder instead would also pick up CI's
# LuaJIT install, which lives in a ".lua" directory.
def addon_sources():
    sources = {}
    with open(os.path.join(ADDON, "Clicky.toc"), encoding="utf-8") as toc:
        for line in toc:
            name = line.strip()
            if name.endswith(".lua"):
                with open(os.path.join(ADDON, name), encoding="utf-8") as f:
                    sources[name] = f.read()
    return sources


def strip_comments(lua):
    lua = re.sub(r"--\[\[.*?\]\]", "", lua, flags=re.S)
    return re.sub(r"--[^\n]*", "", lua)


# 1. lua-language-server.
def run_luals():
    logpath = os.path.join(CACHE, "luals-log")
    out = subprocess.run(
        ["lua-language-server", "--check=" + ROOT, "--checklevel=Information", "--logpath=" + logpath],
        capture_output=True, text=True).stdout
    out = re.sub(r"\x1b\[[0-9;]*m", "", out)
    undefined = {}
    # A diagnostic starts with "path:line:col [Level] message" and may run over several lines;
    # its code, "(undefined-global)", ends one of them.
    blocks = re.split(r"(?m)^(?=\S+\.lua:\d+:\d+ \[)", out)
    for block in blocks:
        m = re.match(r"(\S+\.lua):(\d+):\d+ \[\w+\] ([^\n]*)", block)
        if not m:
            continue
        path, lineno, message = m.groups()
        code = re.search(r"\(([a-z-]+)\)\s*$", block, re.M)
        code = code.group(1) if code else "unknown"
        g = re.match(r"Undefined global `(\w+)`", message)
        if code == "undefined-global" and g:
            undefined.setdefault(g.group(1), f"{path}:{lineno}")
        else:
            problems.append(f"{path}:{lineno}: {message.strip()} ({code})")
    if "Diagnosis complete" not in out and "no problems found" not in out.lower():
        problems.append("lua-language-server didn't run: " + out[-500:])
    return undefined


def main():
    for path in (UI, ANNOTATIONS):
        if not os.path.isdir(path):
            sys.exit(f"missing {path}; run tests/fetch.sh")

    blizzard_lua = strip_comments(read_tree(UI, (".lua",)))
    blizzard_xml = read_tree(UI, (".xml",))
    blizzard_docs = {}  # namespace -> its generated documentation file
    doc_texts = {}  # system (its file's name less Documentation.lua) -> the file
    global_docs = ""  # the documentation files of global functions (a System with no Namespace)
    docs_dir = os.path.join(UI, "AddOns", "Blizzard_APIDocumentationGenerated")
    for name in os.listdir(docs_dir):
        with open(os.path.join(docs_dir, name), encoding="utf-8", errors="replace") as f:
            text = f.read()
        if '\n\tType = "System"' in text:  # not ScriptObject: widget methods, called with ':'
            doc_texts[name.replace("Documentation.lua", "")] = text
        ns_name = re.search(r'Namespace = "(\w+)"', text)
        if ns_name:
            blizzard_docs[ns_name.group(1)] = blizzard_docs.get(ns_name.group(1), "") + text
        elif re.search(r'\n\tType = "System"', text):
            global_docs += text
    widget_api = read_tree(os.path.join(ANNOTATIONS, "Core"), (".lua",))
    sources = addon_sources()
    addon = "\n".join(strip_comments(s) for s in sources.values())

    # 2a. Globals the annotations don't know: Blizzard's code must define or use them as a
    #     bare name (not a field or method), or name a frame that way in XML, or be a global
    #     string XML shows (text="NEW_CAPS").
    blizzard_names = set(re.findall(r"(?<![\w.:])([A-Za-z_]\w*)", blizzard_lua))
    xml_frames = set(re.findall(r'name="(\w+)"', blizzard_xml))
    xml_frames |= set(re.findall(r'text="([A-Z][A-Z0-9_]+)"', blizzard_xml))
    for name, where in sorted(run_luals().items()):
        if name not in blizzard_names and name not in xml_frames:
            problems.append(f"{where}: `{name}` isn't defined or used anywhere in Blizzard's UI code")

    # 2b. CreateFrame templates.
    for template in sorted(set(re.findall(r'CreateFrame\([^)]*?"(\w+Template|\w+)"\s*\)', addon))):
        if template in ("Frame", "Button", "EventFrame"):
            continue
        if not re.search(rf'name="{template}"[^>]*virtual="true"|virtual="true"[^>]*name="{template}"', blizzard_xml):
            problems.append(f"template {template} isn't a virtual frame in Blizzard's XML")

    # 2c. Events.
    for event in sorted(set(re.findall(r'RegisterEvent\("(\w+)"', addon))):
        if not re.search(rf'LiteralName = "{event}"', blizzard_lua) and not re.search(rf'"{event}"', blizzard_lua):
            problems.append(f"event {event} isn't documented or used by Blizzard")

    # 2d. The Toy Box's child frames Clicky hides and anchors to: each must be a parentKey in
    #     Blizzard's XML.
    for key in sorted(set(re.findall(r"(?<![\w.])ToyBox\.(\w+)", addon))):
        if not re.search(rf'parentKey="{key}"', blizzard_xml):
            problems.append(f"ToyBox.{key} isn't a parentKey in Blizzard's XML")

    # 2e. Methods called with ':' that Clicky doesn't define itself: each must be widget API
    #     (annotations) or a method in Blizzard's code (mixins such as ScrollBox, menus, dialogs).
    own = set(re.findall(r"function\s+[\w.]+[:.](\w+)\s*\(", addon))
    own |= set(re.findall(r"\.(\w+)\s*=\s*function", addon))
    own |= set(re.findall(r"\b(\w+)\s*=\s*function", addon))
    lua_string_methods = {"format", "lower", "upper", "find", "match", "gsub", "sub", "byte", "len", "rep", "gmatch"}
    widget_methods = set(re.findall(r"function\s+\w+:(\w+)\s*\(", widget_api))
    blizzard_methods = set(re.findall(r"function\s+[\w.]+:(\w+)\s*\(", blizzard_lua))
    blizzard_methods |= set(re.findall(r"[\s.](\w+)\s*=\s*function", blizzard_lua))
    for method in sorted(set(re.findall(r":(\w+)\s*\(", addon))):
        if method in own or method in lua_string_methods:
            continue
        if method not in widget_methods and method not in blizzard_methods:
            problems.append(f"method :{method}() isn't widget API or a method in Blizzard's UI code")

    # 2f. C_ namespace functions (lua-language-server doesn't flag unknown fields on them): each
    #     must be annotated or documented in Blizzard's generated API docs.
    annotated = set(re.findall(r"function\s+(C_\w+\.\w+)\s*\(", widget_api))
    for call in sorted(set(re.findall(r"\b(C_\w+\.\w+)\b", addon))):
        namespace, fn = call.split(".")
        documented = re.search(rf'Namespace = "{namespace}".*?\bName = "{fn}"', blizzard_docs.get(namespace, ""), re.S)
        if call not in annotated and not documented:
            problems.append(f"{call} isn't in the WoW API annotations or Blizzard's API docs")

    # 2g. Fields read from Blizzard tables (Foo.Bar where Foo is a Blizzard global table).
    #     An Enum field also counts when Blizzard's API docs list it as that enumeration's field.
    for table, field in sorted(set(re.findall(r"\b(MenuResponse|ScrollBoxConstants|Enum\.\w+)\.(\w+)", addon))):
        documented = table.startswith("Enum.") and re.search(
            rf'Name = "{field}", Type = "{table[5:]}", EnumValue', blizzard_lua)
        if not re.search(rf"\b{field}\s*=", blizzard_lua) and not documented:
            problems.append(f"{table}.{field} isn't defined in Blizzard's UI code")

    # 2h. Secret values: a function whose documentation marks its returns secret, always or in some
    #     state (SecretReturns, SecretWhen..., ConditionalSecret...: the function-level keys with
    #     "Secret" in them, less those about arguments and NeverSecret), returns values Clicky can't
    #     compare or hand to most widgets. Each one Clicky calls, in a C_ namespace or global, must be
    #     in HANDLED_SECRET with exactly those keys, so a patch that marks another, or changes one's,
    #     fails here until Clicky handles it (CLAUDE.md, WoW constraints). Widget methods aren't
    #     checked: theirs are secret only on a frame given secret values (SecretReturnsForAspect),
    #     and Clicky gives its frames none.
    HANDLED_SECRET = {"C_Spell.GetSpellCooldown": ["SecretWhenCooldownsRestricted"]}  # Spells.lua
    secret = {}
    for text in doc_texts.values():
        for namespace, fn, body in doc_functions(text):
            keys = sorted({k for k in re.findall(r"\n\t\t\t(\w*Secret\w*) =", body)
                           if not k.startswith("SecretArguments") and not k.endswith("NeverSecret")})
            if keys:
                secret[f"{namespace}.{fn}" if namespace else fn] = keys
    calls = set(re.findall(r"\b(C_\w+\.\w+)\b", addon))
    calls |= {name for name in re.findall(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(", addon) if name in secret}
    for call in sorted(calls):
        if secret.get(call) != HANDLED_SECRET.get(call) and (call in secret or call in HANDLED_SECRET):
            problems.append(f"{call}: Blizzard's docs mark its returns {secret.get(call) or 'not secret'}, "
                            f"Clicky handles {HANDLED_SECRET.get(call) or 'none'}")

    # 3. Events of the systems Clicky calls into (see REVIEWED_EVENTS).
    bare = set(re.findall(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(", addon))
    registered = set(re.findall(r'RegisterEvent\("(\w+)"', addon))
    all_events = set()
    for system, text in sorted(doc_texts.items()):
        events = re.findall(r'LiteralName = "(\w+)"', text)
        all_events |= set(events)
        called = any((f"{namespace}.{fn}" in calls) if namespace else (fn in bare)
                     for namespace, fn, _ in doc_functions(text))
        reviewed = REVIEWED_EVENTS.get(system, [])
        if called:
            for event in events:
                if event not in registered and event not in reviewed:
                    problems.append(f"{system}: event {event} is neither registered by Clicky nor in REVIEWED_EVENTS")
        elif reviewed:
            problems.append(f"REVIEWED_EVENTS lists {system}, which Clicky calls nothing of")
        for event in reviewed:
            if event in registered:
                problems.append(f"{system}: {event} is in REVIEWED_EVENTS but Clicky registers it")
            elif event not in events:
                problems.append(f"{system}: {event} is in REVIEWED_EVENTS but the system doesn't document it")
    for system in REVIEWED_EVENTS:
        if system not in doc_texts:
            problems.append(f"REVIEWED_EVENTS lists {system}, which isn't a documentation file")

    with open(os.path.join(ADDON, "Clicky.toc"), encoding="utf-8") as f:
        interface = re.search(r"## Interface: (\d+)", f.read()).group(1)
    with open(os.path.join(UI, "..", "version.txt"), encoding="utf-8") as f:
        live = f.read().strip()
    print(f"checked against wow-ui-source {live}; Clicky.toc Interface {interface}")

    if problems:
        print("\n".join("API: " + p for p in problems))
        print(f"{len(problems)} API problem(s)")
        sys.exit(1)
    print("API check passed")


main()
