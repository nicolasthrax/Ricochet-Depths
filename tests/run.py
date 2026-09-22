#!/usr/bin/env python3
"""Bundles production Luau modules with the Roblox stub so they run under the plain Luau CLI.

Roblox `require(Instance)` calls are rewritten to `__require("ModuleName")`, and `os.clock`
is rewritten to the harness virtual clock. Game source is never modified.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
TESTS = os.path.join(ROOT, "tests")
HARNESS = os.path.join(TESTS, "harness")
LUAU = os.environ.get("LUAU_BIN", "luau")


def collect_modules():
    """ModuleScripts only: .server/.client files are entry points with side effects."""
    modules = {}
    for dirpath, _, filenames in os.walk(SRC):
        for filename in sorted(filenames):
            if not filename.endswith(".luau"):
                continue
            stem = filename[: -len(".luau")]
            if stem.endswith(".server") or stem.endswith(".client"):
                continue
            if stem in modules:
                raise SystemExit(f"duplicate module name {stem!r}; module names must be unique")
            modules[stem] = os.path.join(dirpath, filename)
    return modules


def extract_module_name(expr):
    """Pull the module name out of a Roblox require target expression."""
    quoted = re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"', expr)
    if quoted:
        return quoted[-1]
    dotted = re.findall(r"[.:]\s*([A-Za-z_][A-Za-z0-9_]*)\s*$", expr.strip())
    if dotted:
        return dotted[-1]
    bare = expr.strip()
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", bare):
        return bare
    raise SystemExit(f"cannot resolve require target: {expr!r}")


def rewrite_requires(source, known):
    out, index = [], 0
    while True:
        match = re.compile(r"\brequire\s*\(").search(source, index)
        if not match:
            out.append(source[index:])
            break
        out.append(source[index : match.start()])
        depth, cursor = 1, match.end()
        while cursor < len(source) and depth:
            if source[cursor] == "(":
                depth += 1
            elif source[cursor] == ")":
                depth -= 1
            cursor += 1
        name = extract_module_name(source[match.end() : cursor - 1])
        if name not in known:
            raise SystemExit(f"require target {name!r} is not a known module")
        out.append(f'__require("{name}")')
        index = cursor
    return "".join(out)


def build_bundle(test_files):
    modules = collect_modules()
    # RobloxStub must come first (it installs the globals everything else builds on), then the
    # runner, then any remaining harness helpers.
    ordered = ["RobloxStub.luau", "TestRunner.luau"]
    ordered += sorted(f for f in os.listdir(HARNESS) if f.endswith(".luau") and f not in ordered)
    chunks = [open(os.path.join(HARNESS, name)).read() for name in ordered]
    chunks.append(
        "local __factories = {}\n"
        "local __cache = {}\n"
        "function __require(name)\n"
        "\tif __cache[name] ~= nil then return __cache[name] end\n"
        '\tlocal factory = __factories[name] or error("no such module: " .. tostring(name))\n'
        "\tlocal value = factory()\n"
        "\t__cache[name] = value\n"
        "\treturn value\n"
        "end\n"
        "function __resetModules()\n"
        "\ttable.clear(__cache)\n"
        "end\n"
        "script = { Name = 'TestScript' }\n"
    )
    for name, path in modules.items():
        source = open(path).read()
        source = rewrite_requires(source, modules)
        source = re.sub(r"\bos\.clock\b", "__clock", source)
        chunks.append(f"__factories[{name!r}] = function()\n{source}\nend\n")
    for path in test_files:
        chunks.append(f"-- ==== {os.path.relpath(path, ROOT)} ====\n" + open(path).read() + "\n")
    chunks.append("__finishTests()\n")
    return "\n".join(chunks), modules


def main():
    args = sys.argv[1:]
    if args:
        test_files = [a if os.path.isabs(a) else os.path.join(ROOT, a) for a in args]
    else:
        test_files = sorted(
            os.path.join(TESTS, f) for f in os.listdir(TESTS) if f.endswith(".test.luau")
        )
    if not test_files:
        print("no test files found")
        return 1

    bundle, modules = build_bundle(test_files)
    out_dir = os.environ.get("TEST_OUT_DIR", os.path.join(ROOT, ".test-build"))
    os.makedirs(out_dir, exist_ok=True)
    bundle_path = os.path.join(out_dir, "bundle.luau")
    with open(bundle_path, "w") as handle:
        handle.write(bundle)

    print(f"bundled {len(modules)} modules + {len(test_files)} test file(s)")
    result = subprocess.run([LUAU, bundle_path])
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
