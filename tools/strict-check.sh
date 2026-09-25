#!/usr/bin/env bash
# Strict type check of mvp/ against the real Roblox API, under both Luau type solvers.
#
# Uses luau-lsp with Roblox's definitions and a Rojo sourcemap of mvp.project.json, so instance
# requires (script.Parent.X, ReplicatedStorage.Source.X) resolve the way they do in Studio.
# luau-lsp and the definitions are pinned and fetched once into .cache/luau-lsp/ (gitignored).
# Override with LUAU_LSP_BIN and ROBLOX_DEFS to use local copies.
#
# Every file in mvp/ must start with --!strict.
set -uo pipefail

cd "$(dirname "$0")/.."
ROJO_BIN="${ROJO_BIN:-rojo}"
LSP_VERSION="1.70.0"
CACHE=".cache/luau-lsp/$LSP_VERSION"

fetch() { # url dest
	curl -fsSL --retry 2 --max-time 120 -o "$2" "$1"
}

lsp="${LUAU_LSP_BIN:-}"
if [ -z "$lsp" ]; then
	lsp="$CACHE/luau-lsp"
	if [ ! -x "$lsp" ]; then
		case "$(uname -s)-$(uname -m)" in
			Darwin-*) asset="luau-lsp-macos.zip" ;;
			Linux-x86_64) asset="luau-lsp-linux-x86_64.zip" ;;
			Linux-aarch64 | Linux-arm64) asset="luau-lsp-linux-arm64.zip" ;;
			*) echo "no luau-lsp build for $(uname -s)-$(uname -m); set LUAU_LSP_BIN"; exit 1 ;;
		esac
		mkdir -p "$CACHE"
		echo "fetching luau-lsp $LSP_VERSION ($asset)"
		if ! fetch "https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LSP_VERSION/$asset" "$CACHE/lsp.zip" \
			|| ! unzip -o -q "$CACHE/lsp.zip" -d "$CACHE"; then
			echo "could not fetch luau-lsp; set LUAU_LSP_BIN to a local luau-lsp"
			exit 1
		fi
		rm -f "$CACHE/lsp.zip"
		chmod +x "$lsp"
	fi
fi

defs="${ROBLOX_DEFS:-$CACHE/globalTypes.d.luau}"
if [ ! -s "$defs" ]; then
	mkdir -p "$(dirname "$defs")"
	echo "fetching Roblox definitions for luau-lsp $LSP_VERSION"
	if ! fetch "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$LSP_VERSION/scripts/globalTypes.None.d.luau" "$defs"; then
		echo "could not fetch the Roblox definitions; set ROBLOX_DEFS"
		exit 1
	fi
fi

files=$(find mvp -name '*.luau' | sort)
for file in $files; do
	head -1 "$file" | grep -q '^--!strict' || { echo "$file: missing --!strict"; exit 1; }
done

sourcemap=$(mktemp)
trap 'rm -f "$sourcemap"' EXIT
"$ROJO_BIN" sourcemap mvp.project.json --output "$sourcemap" >/dev/null || { echo "rojo sourcemap failed"; exit 1; }

status=0
for solver in new old; do
	flag=$([ "$solver" = new ] && echo true || echo false)
	# shellcheck disable=SC2086
	output=$("$lsp" analyze --platform=roblox --sourcemap="$sourcemap" --definitions=@roblox="$defs" \
		--flag:LuauSolverV2="$flag" $files 2>&1 | grep -vE '^\[(INFO|WARN)\]')
	if [ -n "$output" ]; then
		echo "[$solver solver]"
		echo "$output"
		status=1
	fi
done

if [ "$status" -eq 0 ]; then
	echo "ok ($(echo "$files" | wc -l | tr -d ' ') files, new + old solver, luau-lsp $LSP_VERSION)"
fi
exit "$status"
