#!/usr/bin/env bash
# Counts the lines a change adds against BASE (default origin/main), leaving out
# lock files and the generated docs pages. Over the limit it fails, unless the
# pull request description (PR_BODY) has a "## Size" section with text under it.
# Without PR_BODY set (a local run) it reports the count and never fails.
# With HEAD given it counts BASE...HEAD (committed changes, as CI sees them);
# without it, it counts the working tree against the merge base, so uncommitted
# edits to tracked files count too. Untracked files are not counted.
# Usage: scripts/pr-size.sh [BASE] [HEAD]
set -euo pipefail

base="${1:-origin/main}"
limit="${PR_SIZE_LIMIT:-800}"
if [ -n "${2:-}" ]; then
    range="$base...$2"
else
    range="$(git merge-base "$base" HEAD)"
fi

# Left out of the count: npm and Swift package lock files (the workers and
# packages can gain them) and the docs/ pages build-site.mjs renders from site/.
skip='(^|/)(package-lock[.]json|Package[.]resolved)$|^docs/[^/]+[.]html$'

# -z keeps paths unquoted, so the skip list matches names with spaces or
# non-ASCII characters. Written to a file first so a git failure stops the run.
numstat="$(mktemp)"
trap 'rm -f "$numstat"' EXIT
git diff -z --numstat --no-renames "$range" >"$numstat"

added=0
while IFS=$'\t' read -r -d '' plus _ path; do
    [ "$plus" = "-" ] && continue
    [[ $path =~ $skip ]] && continue
    added=$((added + plus))
done <"$numstat"

echo "pr-size: $added added lines against $base (limit $limit, lock files and generated docs pages left out)"
[ "$added" -le "$limit" ] && exit 0

if [ -z "${PR_BODY+set}" ]; then
    echo "pr-size: over $limit; the pull request description needs a \"## Size\" section saying why"
    exit 0
fi

# A "## Size" heading (any case), then at least one non-blank line before the
# next heading of level one or two; "###" subheadings stay inside the section.
if printf '%s\n' "$PR_BODY" | tr -d '\r' | awk '
    tolower($0) ~ /^##[[:space:]]+size[[:space:]]*$/ { inside = 1; next }
    inside && /^##?([[:space:]]|$)/ { inside = 0 }
    inside && NF { found = 1 }
    END { exit !found }'; then
    echo "pr-size: over $limit, explained in the \"## Size\" section"
    exit 0
fi

echo "::error::This pull request adds $added lines, over $limit. Split it, or add a \"## Size\" section to the description saying why it cannot be split."
exit 1
