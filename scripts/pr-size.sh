#!/usr/bin/env bash
# Counts the lines a change adds against BASE (default origin/main), leaving out
# lock files, fixtures and generated files. Over the limit it fails, unless the
# pull request description (PR_BODY) has a "## Size" section with text under it.
# Without PR_BODY set (a local run) it reports the count and never fails.
# Usage: scripts/pr-size.sh [BASE] [HEAD]
set -euo pipefail

base="${1:-origin/main}"
head="${2:-HEAD}"
limit="${PR_SIZE_LIMIT:-800}"

# Left out of the count: lock files, fixtures, the docs/ pages build-site.mjs
# renders from site/, the generated Xcode project and the spike's probe runs.
skip='(^|/)(package-lock[.]json|Package[.]resolved|[^/]*[.]lock|pnpm-lock[.]yaml)$|(^|/)[Ff]ixtures/|^docs/[^/]+[.]html$|[.]xcodeproj/|^spike/.*/runs/'

added="$(git diff --numstat --no-renames "$base...$head" |
    awk -F'\t' -v skip="$skip" '$1 != "-" && $3 !~ skip { n += $1 } END { print n + 0 }')"

echo "pr-size: $added added lines against $base (limit $limit, lock, fixture and generated files left out)"
[ "$added" -le "$limit" ] && exit 0

if [ -z "${PR_BODY+set}" ]; then
    echo "pr-size: over $limit; the pull request description needs a \"## Size\" section saying why"
    exit 0
fi

# A "## Size" heading, then at least one non-blank line before the next heading.
if printf '%s\n' "$PR_BODY" | tr -d '\r' | awk '
    /^##[[:space:]]+Size[[:space:]]*$/ { inside = 1; next }
    inside && /^#/ { inside = 0 }
    inside && NF { found = 1 }
    END { exit !found }'; then
    echo "pr-size: over $limit, explained in the \"## Size\" section"
    exit 0
fi

echo "::error::This pull request adds $added lines, over $limit. Split it, or add a \"## Size\" section to the description saying why it cannot be split."
exit 1
