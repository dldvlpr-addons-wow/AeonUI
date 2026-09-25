#!/usr/bin/env bash
# Vérification hors du jeu :
#   1. syntaxe de tous les fichiers Lua
#   2. suite headless
#   3. AeonUI.toc liste exactement les .lua du dépôt (hors tests/, tools/ et AeonUI/, dossier de publication)
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

echo "== syntaxe"
while IFS= read -r file; do
    if ! "$LUA" -e "assert(loadfile('$file'))" 2>/tmp/aeonui-syntax.$$; then
        echo "  FAIL $file"
        sed 's/^/        /' /tmp/aeonui-syntax.$$
        status=1
    fi
done < <(find . -name '*.lua' -not -path './.git/*' -not -path './AeonUI/*' | LC_ALL=C sort)
rm -f /tmp/aeonui-syntax.$$
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
listed=$(grep '\.lua[[:space:]]*$' AeonUI.toc | tr -d '\r' | tr '\\' '/' | sed 's/[[:space:]]*$//' | sort)
shipped=$(find . -name '*.lua' -not -path './.git/*' -not -path './AeonUI/*' | sed 's#^\./##' | grep -v '^tests/' | grep -v '^tools/' | sort)
if [ "$listed" = "$shipped" ]; then
    echo "  ok"
else
    echo "  FAIL — AeonUI.toc et les fichiers du dépôt divergent :"
    diff <(printf '%s\n' "$listed") <(printf '%s\n' "$shipped") \
        | grep '^[<>]' | sed 's/^</        seulement dans le .toc :/;s/^>/        non listé dans le .toc :/'
    status=1
fi

echo
[ "$status" -eq 0 ] && echo "tout est vert." || echo "des vérifications ont échoué."
exit "$status"
