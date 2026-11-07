#!/usr/bin/env bash
# Verify local Markdown links and fenced-code pairing without network access.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

missing=0
while IFS= read -r doc; do
    doc_dir=$(dirname "$doc")
    fences=$(grep -c '^```' "$doc" || true)
    if [ $((fences % 2)) -ne 0 ]; then
        echo "FAIL: unmatched fenced code block in $doc" >&2
        missing=1
    fi

    while IFS= read -r target; do
        case "$target" in
            http://*|https://*|mailto:*|'#'*) continue ;;
        esac
        clean=${target%%#*}
        [ -z "$clean" ] && continue
        if [ ! -e "${doc_dir}/${clean}" ]; then
            echo "FAIL: $doc links to missing path: $target" >&2
            missing=1
        fi
    done < <(
        perl -ne 'while (/\]\(([^)]+)\)/g) { print "$1\n" }' "$doc"
    )
done < <(find . -type f -name '*.md' -not -path './.git/*' | sort)

if [ "$missing" -ne 0 ]; then
    exit 1
fi
echo "PASS: local Markdown links and fenced code blocks"
