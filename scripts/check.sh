#!/usr/bin/env bash
# Full local gate: syntax, lint, strict types (mvp/), Rojo builds, headless tests.
# Override tool paths with LUAU_BIN / LUAU_COMPILE_BIN / LUAU_ANALYZE_BIN / ROJO_BIN.
set -uo pipefail

cd "$(dirname "$0")/.."

LUAU_BIN="${LUAU_BIN:-luau}"
LUAU_COMPILE_BIN="${LUAU_COMPILE_BIN:-luau-compile}"
LUAU_ANALYZE_BIN="${LUAU_ANALYZE_BIN:-luau-analyze}"
ROJO_BIN="${ROJO_BIN:-rojo}"

status=0
step() { printf '\n=== %s ===\n' "$1"; }
fail() { echo "FAILED: $1"; status=1; }

sources=$(find src mvp tests -name '*.luau' | sort)

step "syntax (luau-compile)"
for file in $sources; do
	if ! output=$("$LUAU_COMPILE_BIN" --binary "$file" 2>&1 >/dev/null) || [ -n "$output" ]; then
		echo "$file: $output"
		fail "syntax"
	fi
done
[ "$status" -eq 0 ] && echo "ok ($(echo "$sources" | wc -l) files)"

step "lint (luau-analyze)"
# Roblox globals are unknown to the standalone analyzer, so only real lints are surfaced.
noise="Unknown global|Unknown require|Unknown type|Cannot find|TypeError|Type '"
lint=$("$LUAU_ANALYZE_BIN" --mode=nonstrict $(find src -name '*.luau' | sort) 2>&1 \
	| grep -viE "$noise" || true)
# The test harness deliberately installs globals and shadows typeof, so those lints are expected there.
harness_noise="$noise|BuiltinGlobalWrite|FunctionUnused|GlobalUsedAsLocal"
lint_tests=$("$LUAU_ANALYZE_BIN" --mode=nonstrict $(find tests -name '*.luau' | sort) 2>&1 \
	| grep -viE "$harness_noise" || true)
if [ -n "$lint" ] || [ -n "$lint_tests" ]; then
	[ -n "$lint" ] && echo "$lint"
	[ -n "$lint_tests" ] && echo "$lint_tests"
	fail "lint"
else
	echo "ok"
fi

step "strict types, mvp/ (tools/strict-check.sh)"
if ! LUAU_ANALYZE_BIN="$LUAU_ANALYZE_BIN" tools/strict-check.sh; then
	fail "strict types"
fi

step "rojo build"
if "$ROJO_BIN" build default.project.json --output /tmp/ricochet-check.rbxlx \
	&& "$ROJO_BIN" build mvp.project.json --output /tmp/ricochet-mvp-check.rbxlx; then
	echo "ok"
else
	fail "rojo build"
fi

step "headless tests"
if LUAU_BIN="$LUAU_BIN" python3 tests/run.py; then
	echo "ok"
else
	fail "tests"
fi

printf '\n'
if [ "$status" -eq 0 ]; then
	echo "ALL CHECKS PASSED"
else
	echo "CHECKS FAILED"
fi
exit "$status"
