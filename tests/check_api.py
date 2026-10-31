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
    global_docs = ""  # the documentation files of global functions (a System with no Namespace)
    docs_dir = os.path.join(UI, "AddOns", "Blizzard_APIDocumentationGenerated")
    for name in os.listdir(docs_dir):
        with open(os.path.join(docs_dir, name), encoding="utf-8", errors="replace") as f:
            text = f.read()
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
    for namespace, text in list(blizzard_docs.items()) + [(None, global_docs)]:
        for m in re.finditer(r'\n\t\t\{\n\t\t\tName = "(\w+)",\n\t\t\tType = "Function",(.*?)\n\t\t\},', text, re.S):
            keys = sorted({k for k in re.findall(r"\n\t\t\t(\w*Secret\w*) =", m.group(2))
                           if not k.startswith("SecretArguments") and not k.endswith("NeverSecret")})
            if keys:
                secret[f"{namespace}.{m.group(1)}" if namespace else m.group(1)] = keys
    calls = set(re.findall(r"\b(C_\w+\.\w+)\b", addon))
    calls |= {name for name in re.findall(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(", addon) if name in secret}
    for call in sorted(calls):
        if secret.get(call) != HANDLED_SECRET.get(call) and (call in secret or call in HANDLED_SECRET):
            problems.append(f"{call}: Blizzard's docs mark its returns {secret.get(call) or 'not secret'}, "
                            f"Clicky handles {HANDLED_SECRET.get(call) or 'none'}")

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
