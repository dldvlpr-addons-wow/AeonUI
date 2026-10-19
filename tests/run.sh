#!/usr/bin/env bash
# Vérification hors du jeu :
#   1. syntaxe de tous les fichiers Lua
#   2. suite headless
#   3. MuscaUI.toc liste exactement les .lua du dépôt (hors tests/, tools/ et MuscaUI/, dossier de publication)
#
# Prérequis : lua5.1 (ou lua) dans le PATH. Surcharge : LUA=... tests/run.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

LUA="${LUA:-}"
if [ -z "$LUA" ]; then
    for candidate in lua5.1 lua5.4 lua luajit; do
        if command -v "$candidate" >/dev/null 2>&1; then LUA="$candidate"; break; fi
    done
fi
if [ -z "$LUA" ]; then
    echo "aucun interpréteur Lua trouvé (installe lua5.1)" >&2
    exit 2
fi

status=0
syntax_log="${TMPDIR:-/tmp}/muscaui-syntax.$$"

echo "== syntaxe"
while IFS= read -r file; do
    if ! "$LUA" -e "assert(loadfile('$file'))" 2>"$syntax_log"; then
        echo "  FAIL $file"
        sed 's/^/        /' "$syntax_log"
        status=1
    fi
done < <(find . -name '*.lua' -not -path './.git/*' -not -path './MuscaUI/*' | LC_ALL=C sort)
rm -f "$syntax_log"
[ "$status" -eq 0 ] && echo "  ok"

echo
echo "== suite headless"
if output=$("$LUA" tests/run_tests.lua 2>&1); then
    echo "  ok   $(printf '%s' "$output" | tail -n 1)"
else
    echo "  FAIL"
    printf '%s\n' "$output" | sed 's/^/        /'
    status=1
fi

echo
echo "== .toc"
# Cœur + addons MuscaUI_* : chaque ligne d'un toc enfant est préfixée de son dossier.
listed=$( {
    grep '\.lua[[:space:]]*$' MuscaUI.toc
    for toc in MuscaUI_*/MuscaUI_*.toc; do
        grep '\.lua[[:space:]]*$' "$toc" | sed "s#^#$(dirname "$toc")/#"
    done
} | tr -d '\r' | tr '\\' '/' | sed 's/[[:space:]]*$//' | sort)
for toc in MuscaUI_*/MuscaUI_*.toc; do
    if ! grep -q '^## Dependencies: MuscaUI[[:space:]]*$' "$toc"; then
        echo "  FAIL — $toc sans « ## Dependencies: MuscaUI »"
        status=1
    fi
    if grep -q '^local .*= \.\.\.[[:space:]]*$' "$(dirname "$toc")"/*.lua; then
        echo "  FAIL — $(dirname "$toc") : un fichier lit le vararg (NS privé en jeu), utiliser « local NS = MuscaUI »"
        status=1
    fi
done
shipped=$(find . -name '*.lua' -not -path './.git/*' -not -path './MuscaUI/*' | sed 's#^\./##' | grep -v '^tests/' | grep -v '^tools/' | sort)
if [ "$listed" = "$shipped" ]; then
    echo "  ok"
else
    echo "  FAIL — MuscaUI.toc et les fichiers du dépôt divergent :"
    diff <(printf '%s\n' "$listed") <(printf '%s\n' "$shipped") \
        | grep '^[<>]' | sed 's/^</        seulement dans le .toc :/;s/^>/        non listé dans le .toc :/'
    status=1
fi

echo
[ "$status" -eq 0 ] && echo "tout est vert." || echo "des vérifications ont échoué."
exit "$status"
