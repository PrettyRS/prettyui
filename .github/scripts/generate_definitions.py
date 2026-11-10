#!/usr/bin/env python3
"""Generate LuaLS declarations from PrettyUI's Lua source and editor/api.json.

This reads source text, never loads the runtime (which requires the game client).
Metadata refines signatures and supplies semantic types that cannot be inferred
safely from Lua expressions; new exports and methods are discovered automatically.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
IDENT = r"[A-Za-z_][A-Za-z_0-9]*"
IDENTIFIER = re.compile(rf"^{IDENT}$")
SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
FUNCTION = re.compile(rf"\bfunction\s+({IDENT})([.:])({IDENT})\s*\(([^()]*)\)")
ASSIGNED_FUNCTION = re.compile(rf"\b({IDENT})\.({IDENT})\s*=\s*function\s*\(([^()]*)\)")
ALIAS_FUNCTION = re.compile(rf"\b({IDENT})\.({IDENT})\s*=\s*({IDENT})\.({IDENT})\b")
OPTIONS = re.compile(r"\boptions\.([A-Za-z_][A-Za-z_0-9]*)|\boptions\[['\"]([A-Za-z_][A-Za-z_0-9]*)['\"]\]")
LONG_BRACKET = re.compile(r"\[(=*)\[")
HIDDEN_STATIC = {"Shutdown", "Start", "getSize", "flowOptions", "SetDefaultSprite"}


@dataclass
class Method:
    params: list[str] = field(default_factory=list)
    returns: list[str] = field(default_factory=list)
    static: bool = False
    source: str = ""
    description: str = ""
    param_types: dict[str, str] = field(default_factory=dict)


@dataclass
class Definition:
    name: str
    source: str = ""
    options: dict[str, str] = field(default_factory=dict)
    fields: dict[str, str] = field(default_factory=dict)
    methods: dict[str, Method] = field(default_factory=dict)
    bases: list[str] = field(default_factory=list)
    description: str = ""
    exported: bool = False


def mask_lua(text: str) -> str:
    """Hide Lua strings/comments while retaining offsets and newlines."""
    result = list(text)
    i = 0
    while i < len(text):
        start = i
        long = LONG_BRACKET.match(text, i)
        if text.startswith("--", i):
            long = LONG_BRACKET.match(text, i + 2)
            if long:
                end_marker = "]" + long.group(1) + "]"
                end = text.find(end_marker, i + 2 + len(long.group()))
                i = len(text) if end < 0 else end + len(end_marker)
            else:
                end = text.find("\n", i)
                i = len(text) if end < 0 else end
        elif long:
            end_marker = "]" + long.group(1) + "]"
            end = text.find(end_marker, i + len(long.group()))
            i = len(text) if end < 0 else end + len(end_marker)
        elif text[i] in "'\"":
            quote = text[i]
            i += 1
            while i < len(text):
                if text[i] == "\\":
                    i += 2
                elif text[i] == quote:
                    i += 1
                    break
                else:
                    i += 1
        else:
            i += 1
            continue
        for pos in range(start, min(i, len(text))):
            if result[pos] != "\n":
                result[pos] = " "
    return "".join(result)


def table_at(mask: str, opening: int) -> tuple[int, int]:
    if mask[opening] != "{":
        raise ValueError("expected Lua table")
    depth = 0
    for pos in range(opening, len(mask)):
        if mask[pos] == "{":
            depth += 1
        elif mask[pos] == "}":
            depth -= 1
            if depth == 0:
                return opening, pos + 1
    raise ValueError("unclosed Lua table")


def table_entries(text: str, opening: int) -> list[str]:
    """Split table entries without splitting nested tables, strings or function calls."""
    mask = mask_lua(text)
    _, end = table_at(mask, opening)
    entries: list[str] = []
    start = opening + 1
    braces = parentheses = brackets = 0
    for pos in range(start, end - 1):
        char = mask[pos]
        if char == "{":
            braces += 1
        elif char == "}":
            braces -= 1
        elif char == "(":
            parentheses += 1
        elif char == ")":
            parentheses -= 1
        elif char == "[":
            brackets += 1
        elif char == "]":
            brackets -= 1
        elif char == "," and braces == parentheses == brackets == 0:
            entries.append(text[start:pos].strip())
            start = pos + 1
    if text[start : end - 1].strip():
        entries.append(text[start : end - 1].strip())
    return entries


def keyed_entries(text: str, opening: int) -> dict[str, str]:
    result = {}
    for entry in table_entries(text, opening):
        match = re.match(rf"\s*({IDENT})\s*=", mask_lua(entry))
        if match:
            result[match.group(1)] = entry[match.end():].strip()
    return result


def lua_source(path: Path) -> tuple[str, str]:
    text = path.read_text(encoding="utf-8")
    return text, mask_lua(text)


def source_location(path: Path, text: str, offset: int) -> str:
    return f"{path.relative_to(ROOT).as_posix()}:{text.count(chr(10), 0, offset) + 1}"


def function_map(path: Path) -> dict[str, dict[str, Method]]:
    text, masked = lua_source(path)
    methods: dict[str, dict[str, Method]] = {}
    for match in FUNCTION.finditer(masked):
        owner, call, name, args = match.groups()
        params = [arg.strip() for arg in args.split(",") if arg.strip()]
        if call == ":" and params and params[0] == "self":
            params.pop(0)
        if name.startswith("_") or (call == "." and name in HIDDEN_STATIC):
            continue
        methods.setdefault(owner, {})[name] = Method(
            params=params, static=call == ".", source=source_location(path, text, match.start())
        )
    for match in ASSIGNED_FUNCTION.finditer(masked):
        owner, name, args = match.groups()
        if name.startswith("_") or name in HIDDEN_STATIC:
            continue
        params = [arg.strip() for arg in args.split(",") if arg.strip()]
        static = not params or params[0] != "self"
        if not static:
            params.pop(0)
        methods.setdefault(owner, {})[name] = Method(
            params=params, static=static, source=source_location(path, text, match.start())
        )
    return methods


def resolve_module(module: str) -> Path:
    path = ROOT / f"{module}.lua"
    if not path.is_file():
        raise ValueError(f"module {module!r} does not exist")
    return path


def resolve_alias(module: str) -> str:
    visited = set()
    while True:
        if module in visited:
            raise ValueError(f"circular module alias: {module}")
        visited.add(module)
        text = resolve_module(module).read_text(encoding="utf-8")
        alias = re.fullmatch(r"\s*return\s+require\s*\(\s*['\"]([^'\"]+)['\"]\s*\)\s*;?\s*", text)
        if not alias:
            return module
        module = alias.group(1)


def exports_from_main(text: str, masked: str) -> tuple[dict[str, tuple[str, str | None]], str]:
    locals_ = dict(re.findall(rf"\blocal\s+({IDENT})\s*=\s*require\s*\(\s*['\"]([^'\"]+)['\"]\s*\)", text))
    table = re.search(r"\blocal\s+PrettyUI\s*=\s*\{", masked)
    if table is None:
        raise ValueError("main.lua must declare a PrettyUI export table")
    exports: dict[str, tuple[str, str | None]] = {}
    for name, expression in keyed_entries(text, table.end() - 1).items():
        required = re.fullmatch(r"require\s*\(\s*['\"]([^'\"]+)['\"]\s*\)", expression)
        ref = re.fullmatch(rf"({IDENT})(?:\.({IDENT}))?", expression)
        if required:
            exports[name] = (required.group(1), None)
        elif ref and ref.group(1) in locals_:
            exports[name] = (locals_[ref.group(1)], ref.group(2))
        else:
            raise ValueError(f"unknown PrettyUI export {name} = {expression}")
    version = re.search(r"\bPrettyUI\.version\s*=\s*['\"]([^'\"]+)['\"]", text)
    if not version:
        raise ValueError("main.lua must declare PrettyUI.version")
    return exports, version.group(1)


def infer_option_keys(text: str, masked: str) -> set[str]:
    # Match quoted keys in the original text, but require the access itself to
    # survive masking so comments and string contents cannot invent options.
    return {
        key
        for match in OPTIONS.finditer(text)
        if masked[match.start():match.start() + len("options")] == "options"
        for key in match.groups()
        if key and not key.startswith("_")
    }


def add_source_methods(definition: Definition, methods: dict[str, Method]) -> None:
    for name, method in methods.items():
        definition.methods[name] = Method(
            params=method.params.copy(), returns=method.returns.copy(), static=method.static,
            source=method.source, description=method.description,
        )


def merge_forwarded_methods(definition: Definition, methods: dict[str, Method]) -> None:
    for name, method in methods.items():
        if name != "new" and not method.static and name not in definition.methods:
            definition.methods[name] = Method(params=method.params.copy(), static=False, source=method.source)


def registry_specs(text: str, masked: str) -> list[dict[str, str]]:
    registry = re.search(r"\blocal\s+COMPONENTS\s*=\s*\{", masked)
    if not registry:
        raise ValueError("content_methods.lua has no COMPONENTS registry")
    specs = []
    for entry in table_entries(text, registry.end() - 1):
        if entry.startswith("{"):
            specs.append(keyed_entries(entry, 0))
    return specs


def value_string(value: str) -> str | None:
    match = re.fullmatch(r"['\"]([^'\"]+)['\"]", value)
    return match.group(1) if match else None


def dynamic_methods(
    exports: dict[str, tuple[str, str | None]], source_methods: dict[str, dict[str, Method]]
) -> dict[str, Method]:
    path = ROOT / "src/core/content_methods.lua"
    text, masked = lua_source(path)
    result: dict[str, Method] = {}
    for spec in registry_specs(text, masked):
        name = value_string(spec.get("method", ""))
        if not name:
            raise ValueError(f"component registry entry missing method: {spec}")
        if "textTitle" in spec:
            result[name] = Method(params=["value"], returns=["any"], source=source_location(path, text, text.find('method = "' + name + '"')))
            continue
        module = value_string(spec.get("module", ""))
        if not module:
            raise ValueError(f"component registry {name} has no module")
        component = value_string(spec.get("export", ""))
        matches = [key for key, (path_, owner) in exports.items() if resolve_alias(path_) == resolve_alias(module) and owner == component]
        preferred = name[3:] if name.startswith("Add") else name
        result_name = preferred if preferred in matches else matches[0] if matches else (component or Path(module).name.title().replace("_", ""))
        constructor = source_methods.get(result_name, {}).get("new")
        index = int(spec.get("optionsIndex", "1"))
        # A registry's optionsIndex accounts for the parent passed by addSingle.
        params = constructor.params[1:index] if constructor else [f"arg{i}" for i in range(1, index)]
        params = [*params, "options"]
        result[name] = Method(
            params=params, returns=[f"PrettyUI.{result_name}"],
            source=source_location(path, text, text.find('method = "' + name + '"')),
            param_types={"options": f"PrettyUI.{result_name}Options?"},
        )
    return result


def enrich_with_metadata(definitions: dict[str, Definition], metadata_path: Path) -> None:
    if not metadata_path.is_file():
        return
    payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    classes = payload.get("classes", {})
    if not isinstance(classes, dict):
        raise ValueError("editor/api.json: classes must be an object")
    for name, details in classes.items():
        if not IDENTIFIER.fullmatch(name) or not isinstance(details, dict):
            raise ValueError(f"editor/api.json: invalid class {name!r}")
        definition = definitions.setdefault(name, Definition(name))
        definition.description = details.get("description", definition.description)
        if name.endswith("Options") and not definition.exported and not definition.methods:
            definition.options.update(details.get("fields", {}))
        else:
            definition.fields.update(details.get("fields", {}))
        definition.options.update(details.get("options", {}))
        definition.bases = details.get("bases", definition.bases)
        for method_name, override in details.get("methods", {}).items():
            if not IDENTIFIER.fullmatch(method_name) or not isinstance(override, dict):
                raise ValueError(f"editor/api.json: invalid method {name}.{method_name}")
            method = definition.methods.setdefault(method_name, Method(static=method_name == "new"))
            if "params" in override:
                method.params = list(override["params"])
                method.param_types = dict(override["params"])
            if "returns" in override:
                method.returns = list(override["returns"])
            if "description" in override:
                method.description = override["description"]
            if "static" in override:
                method.static = override["static"]
    # A helper called XOptions may refine X's source-discovered options (for
    # example MiniMenuOptions); emit one declaration rather than two classes.
    for name, helper in list(definitions.items()):
        if not name.endswith("Options") or helper.exported or helper.methods or helper.fields:
            continue
        owner = definitions.get(name[:-7])
        if owner is not None and owner.options:
            owner.options.update(helper.options)
            del definitions[name]

    # Constructor signatures also describe the Add... forwarding APIs. Match
    # their arguments by position, since panel overrides may use other names.
    for definition in definitions.values():
        for name, method in definition.methods.items():
            if not name.startswith("Add") or name[3:] not in definitions:
                continue
            constructor = definitions[name[3:]].methods.get("new")
            if constructor is None:
                continue
            for parameter, forwarded in zip(method.params, constructor.params[1:]):
                constructor_type = constructor.param_types.get(forwarded)
                generated_option = f"PrettyUI.{name[3:]}Options?"
                if constructor_type and method.param_types.get(parameter) in (None, generated_option):
                    method.param_types[parameter] = constructor_type
            if name in {"AddText", "AddTitle"} and "value" in method.params:
                method.param_types["value"] = "string|PrettyUI.TextOptions"
    # Paired panel controls expose the concrete control API but also carry two
    # native instances. Their type must preserve both the methods and surfaces.
    panel = definitions.get("Panel")
    if panel is not None:
        for name, method in panel.methods.items():
            if not name.startswith("Add") or len(method.returns) != 1:
                continue
            target_type = method.returns[0]
            if not target_type.startswith("PrettyUI."):
                continue
            target = target_type.removeprefix("PrettyUI.")
            if target not in definitions or not definitions[target].exported:
                continue
            proxy_name = f"Panel{target}Proxy"
            proxy = definitions.setdefault(proxy_name, Definition(proxy_name, bases=[target]))
            proxy.fields.setdefault("dock", target_type)
            proxy.fields.setdefault("overlay", target_type)
            method.returns = [f"PrettyUI.{proxy_name}"]
            if target == "Tabs" and "TabPage" in definitions:
                page_proxy = definitions.setdefault(
                    "PanelTabPageProxy", Definition("PanelTabPageProxy", bases=["TabPage"])
                )
                page_proxy.fields.setdefault("dock", "PrettyUI.TabPage")
                page_proxy.fields.setdefault("overlay", "PrettyUI.TabPage")
                getter = definitions["Tabs"].methods.get("GetPage")
                proxy.methods["GetPage"] = Method(
                    params=getter.params.copy() if getter else ["index"],
                    param_types=getter.param_types.copy() if getter else {"index": "integer"},
                    returns=["PrettyUI.PanelTabPageProxy|nil"],
                    source=getter.source if getter else "",
                )




def collect_definitions(exports: dict[str, tuple[str, str | None]]) -> dict[str, Definition]:
    definitions: dict[str, Definition] = {}
    module_cache: dict[str, tuple[str, str, dict[str, dict[str, Method]]]] = {}
    for name, (module, selected) in exports.items():
        target = resolve_alias(module)
        if target not in module_cache:
            path = resolve_module(target)
            text, masked = lua_source(path)
            module_cache[target] = text, masked, function_map(path)
        text, masked, methods = module_cache[target]
        path = resolve_module(target)
        definition = Definition(name=name, source=path.relative_to(ROOT).as_posix(), exported=True)
        owner = selected or re.search(rf"\breturn\s+({IDENT})\s*$", masked)
        if isinstance(owner, re.Match):
            owner = owner.group(1)
        if selected:
            # Shared modules may return a table of wrapper constructors with a
            # common private instance class (selection_button.lua).
            wrapper = re.search(rf"\b{re.escape(selected)}\s*=\s*\{{", masked)
            if wrapper:
                body = text[wrapper.end() - 1 : table_at(masked, wrapper.end() - 1)[1]]
                ctor = re.search(r"\bnew\s*=\s*function\s*\(([^()]*)\)", body)
                if ctor:
                    definition.methods["new"] = Method(
                        params=[arg.strip() for arg in ctor.group(1).split(",") if arg.strip()],
                        static=True, source=source_location(path, text, wrapper.start() + ctor.start()),
                    )
                inherited = methods.get("SelectionButton", {})
                merge_forwarded_methods(definition, inherited)
                definition.options.update({key: "any" for key in infer_option_keys(text, masked)})
        if isinstance(owner, str):
            add_source_methods(definition, methods.get(owner, {}))
        # A class table can inherit another module's implementation, including
        # inherited instance methods not redeclared on a renderer subclass.
        parent = re.search(rf"\b{re.escape(str(owner))}\s*=\s*setmetatable\s*\(\s*\{{\s*\}}\s*,\s*\{{\s*__index\s*=\s*({IDENT})", masked)
        if parent and parent.group(1) not in methods:
            for required in re.finditer(rf"\blocal\s+{re.escape(parent.group(1))}\s*=\s*require\s*\(\s*['\"]([^'\"]+)['\"]", text):
                inherited_path = resolve_module(required.group(1))
                parent_methods = function_map(inherited_path)
                parent_owner = re.search(rf"\breturn\s+({IDENT})\s*$", mask_lua(inherited_path.read_text(encoding="utf-8")))
                if parent_owner:
                    merge_forwarded_methods(definition, parent_methods.get(parent_owner.group(1), {}))
        if isinstance(owner, str):
            for match in ALIAS_FUNCTION.finditer(masked):
                if match.group(1) != owner or match.group(2).startswith("_") or match.group(2) in HIDDEN_STATIC:
                    continue
                source_owner, source_name = match.group(3), match.group(4)
                if source_owner in methods and source_name in methods[source_owner]:
                    referenced = methods[source_owner][source_name]
                else:
                    referenced = None
                    for required in re.finditer(rf"\blocal\s+{re.escape(source_owner)}\s*=\s*require\s*\(\s*['\"]([^'\"]+)['\"]", text):
                        foreign_methods = function_map(resolve_module(required.group(1)))
                        referenced = foreign_methods.get(source_owner, {}).get(source_name)
                if referenced:
                    definition.methods[match.group(2)] = Method(
                        params=referenced.params.copy(), static=referenced.static,
                        source=source_location(path, text, match.start()),
                    )
        if "new" in definition.methods:
            definition.methods["new"].returns = [
                "PrettyUI.Dialog" if name == "Confirm" else "any" if name == "Text" else f"PrettyUI.{name}"
            ]
        if name == "Sprites":
            declaration = re.search(r"\blocal\s+Sprites\s*=\s*\{", masked)
            if declaration:
                for key, value in keyed_entries(text, declaration.end() - 1).items():
                    definition.fields[key] = "number" if value.startswith("id.Sprite.") else "table"
            for assignment in re.finditer(rf"\bSprites\.({IDENT})\s*=\s*\{{", masked):
                definition.fields[assignment.group(1)] = "table"
        elif "new" in definition.methods or name in {"BuffBar", "MiniMenu"}:
            definition.options.update({key: "any" for key in infer_option_keys(text, masked)})
        definitions[name] = definition

    # Source-driven common host methods; preserve explicit overrides in hosts.
    content_path = ROOT / "src/core/content_methods.lua"
    dynamic = dynamic_methods(exports, {name: value.methods for name, value in definitions.items()})
    for name, definition in definitions.items():
        source = resolve_module(resolve_alias(exports[name][0]))
        text = source.read_text(encoding="utf-8")
        installed = bool(re.search(rf"ContentMethods\.install(?:Single|Paired)\(\s*{name}\b", text))
        for method_name, method in dynamic.items():
            if installed and not (name == "Panel" and method_name == "AddPanel"):
                definition.methods.setdefault(method_name, deepcopy(method))
            existing = definition.methods.get(method_name)
            if existing is not None and not existing.returns and method_name.startswith("Add"):
                existing.returns = method.returns.copy()
                if "options" in existing.params:
                    existing.param_types.update(method.param_types)
        if name in {"Window", "SimpleView", "NisPanel"}:
            scroll = function_map(ROOT / "src/core/scroll.lua").get("Scroll", {})
            # Only Scroll.install's public host API is forwarded, not controller internals.
            merge_forwarded_methods(definition, {
                method: scroll[method]
                for method in ("SetContentHeight", "SetScrollPosition", "ScrollBy", "ScrollToChild", "SetScrollable")
                if method in scroll
            })
        if name in {"Window", "SimpleView", "NisPanel", "Panel", "Tabs"}:
            # Layout.configure consumes the nested layout/textLayout/contentLayout
            # table, not top-level component options.
            if "layout" in definition.options or "textLayout" in definition.options:
                definition.options.setdefault("layout", "PrettyUI.LayoutOptions")
                definition.options.setdefault("textLayout", "PrettyUI.LayoutOptions")
            if "contentLayout" in definition.options:
                definition.options["contentLayout"] = "PrettyUI.LayoutOptions"
    for helper, module, owner in (("TabPage", "src/tabs", "TabPage"), ("BuffHandle", "src/buff_bar", "Handle")):
        path = resolve_module(module)
        text = path.read_text(encoding="utf-8")
        definition = Definition(helper, path.relative_to(ROOT).as_posix())
        add_source_methods(definition, function_map(path).get(owner, {}))
        if helper == "TabPage":
            definition.methods.update({name: deepcopy(method) for name, method in dynamic.items() if name not in definition.methods})
            scroll_methods = function_map(ROOT / "src/core/scroll.lua").get("Scroll", {})
            for method_name in ("SetContentHeight", "SetScrollPosition", "ScrollBy", "ScrollToChild", "SetScrollable"):
                if method_name in scroll_methods:
                    definition.methods.setdefault(method_name, scroll_methods[method_name])
        definitions[helper] = definition
    # Options forwarded to every Add... control by Layout.place, and to the
    # owner's nested layout options by Layout.configure.
    _, layout_mask = lua_source(ROOT / "src/core/layout.lua")
    configured = layout_mask.split("function Layout.configure", 1)[1].split("\nend", 1)[0]
    layout_options = {key: "any" for key in infer_option_keys(configured, configured)}
    definitions["LayoutOptions"] = Definition("LayoutOptions", "src/core/layout.lua", options=layout_options)
    placement = layout_mask.split("function Layout.place", 1)[1].split("\nend", 1)[0]
    placement_keys = infer_option_keys(placement, placement)
    _, backgrounds = lua_source(ROOT / "src/core/row_backgrounds.lua")
    placement_keys.update(re.findall(r"\bplacement\.(rowBackground(?:Group)?)\b", backgrounds))
    for spec in registry_specs(*lua_source(content_path)):
        method_name = value_string(spec.get("method", ""))
        if not method_name:
            continue
        module = "src/text" if "textTitle" in spec else value_string(spec.get("module", ""))
        selected = value_string(spec.get("export", ""))
        for name, (export_module, export_selected) in exports.items():
            if resolve_alias(export_module) == resolve_alias(module) and export_selected == selected:
                for key in placement_keys:
                    definitions[name].options.setdefault(key, "any")
    return definitions


def annotation_type(value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"invalid annotation type {value!r}")
    return value.strip()


def emit_method(name: str, method: Method, owner: str, exported: bool) -> list[str]:
    rows: list[str] = []
    if method.description:
        rows.extend("---" + line for line in method.description.splitlines())
    elif method.source:
        rows.append(f"---Source: {method.source}")
    for arg in method.params:
        typ = annotation_type(method.param_types.get(arg, "any"))
        rows.append(f"---@param {arg} {typ}")
    for returned in method.returns or ["any"]:
        rows.append(f"---@return {annotation_type(returned)}")
    colon = "." if method.static else ":"
    target = f"prettyui.{owner}" if exported else owner
    rows.append(f"function {target}{colon}{name}({', '.join(method.params)}) end")
    return rows


def emit(definitions: dict[str, Definition], version: str) -> str:
    rows = ["---@meta", ""]
    rows.extend("-- " + line for line in (ROOT / "LICENSE").read_text(encoding="utf-8").splitlines())
    rows.extend(["", "---PrettyUI editor definitions (not executable).", f"---Source version: {version}", "---@class PrettyUI", "---@field version string"])
    exported = sorted(name for name, definition in definitions.items() if definition.exported)
    rows.extend(f"---@field {name} PrettyUI.{name}" for name in exported)
    rows.extend(("prettyui = {}", ""))
    for name in sorted(definitions):
        definition = definitions[name]
        option_name = name if name.endswith("Options") else name + "Options"
        if definition.options:
            rows.append(f"---Options for {name}. Source: {definition.source or 'editor/api.json'}")
            rows.append(f"---@class PrettyUI.{option_name}")
            for key, typ in sorted(definition.options.items()):
                if not IDENTIFIER.fullmatch(key):
                    raise ValueError(f"invalid option key {name}.{key}")
                rows.append(f"---@field {key}? {annotation_type(typ)}")
            rows.append("")
        if name.endswith("Options") and not definition.exported and not definition.methods and not definition.fields and definition.options:
            continue
        if definition.description:
            rows.extend("---" + line for line in definition.description.splitlines())
        elif definition.source:
            rows.append(f"---Source: {definition.source}")
        bases = [base if base.startswith("PrettyUI.") else "PrettyUI." + base for base in definition.bases]
        rows.append(f"---@class PrettyUI.{name}" + (": " + ", ".join(bases) if bases else ""))
        for key, typ in sorted(definition.fields.items()):
            if not IDENTIFIER.fullmatch(key):
                raise ValueError(f"invalid field {name}.{key}")
            rows.append(f"---@field {key} {annotation_type(typ)}")
        rows.append(f"prettyui.{name} = {{}}" if definition.exported else f"local {name} = {{}}")
        for method_name in sorted(definition.methods):
            method = definition.methods[method_name]
            if not IDENTIFIER.fullmatch(method_name):
                raise ValueError(f"invalid method {name}.{method_name}")
            if "options" in method.params and "options" not in method.param_types:
                component = method_name[3:] if method_name.startswith("Add") else name
                option_class = component if component.endswith("Options") else component + "Options"
                if component in exported and definitions[component].options or component == name and definition.options:
                    method.param_types["options"] = f"PrettyUI.{option_class}?"
            rows.extend(emit_method(method_name, method, name, definition.exported))
        rows.append("")
    return "\n".join(rows).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="directory for prettyui-definitions.lua")
    parser.add_argument("--version", help="release version (defaults to main.lua version)")
    args = parser.parse_args()
    source, masked = lua_source(ROOT / "main.lua")
    exports, source_version = exports_from_main(source, masked)
    version = args.version or source_version
    if not SEMVER.fullmatch(version):
        parser.error(f"invalid version {version!r} (expected semver, e.g. 1.2.1)")
    if not SEMVER.fullmatch(source_version):
        parser.error(f"invalid main.lua version {source_version!r}")
    definitions = collect_definitions(exports)
    enrich_with_metadata(definitions, ROOT / "editor/api.json")
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "prettyui-definitions.lua").write_text(emit(definitions, version), encoding="utf-8")


if __name__ == "__main__":
    main()
