# SharePad task runner. Run `just` to list recipes.

# list available recipes
default:
    @just --list

# regenerate the Xcode project from project.yml (run after editing project.yml)
gen:
    xcodegen generate

# build (Debug)
build: gen
    xcodebuild -project SharePad.xcodeproj -scheme SharePad -configuration Debug -destination 'platform=macOS' -derivedDataPath .build build

# build, then launch the menu-bar app
run: build
    open .build/Build/Products/Debug/SharePad.app

# open the generated project in Xcode
open: gen
    open SharePad.xcodeproj

# format sources (run before commit)
fmt:
    swiftformat .

# lint sources (run before push)
lint:
    swiftlint
    swiftformat --lint .

# run unit tests (with code coverage; see `just coverage` for the report)
test: gen
    xcodebuild -project SharePad.xcodeproj -scheme SharePad -configuration Debug -destination 'platform=macOS' -derivedDataPath .build -enableCodeCoverage YES test

# print the per-target coverage summary from the latest `just test` run
coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    RESULT=$(ls -td .build/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)
    [ -n "$RESULT" ] || { echo "no .xcresult found — run 'just test' first" >&2; exit 1; }
    xcrun xccov view --report --only-targets "$RESULT"

# assert the built app keeps its load-bearing invariants — camera-only (no mic) and
# un-sandboxed (Non-Negotiable 5 / DESIGN.md §6). A regression here otherwise only
# surfaces live, as a surprise mic prompt or an empty device list.
verify-app app=".build/Build/Products/Debug/SharePad.app":
    #!/usr/bin/env bash
    set -euo pipefail
    APP="{{ app }}"
    PLIST="$APP/Contents/Info.plist"
    [ -d "$APP" ] || { echo "app not found at $APP — build it first" >&2; exit 1; }
    fail=0
    note() { echo "  ✗ $1" >&2; fail=1; }
    plutil -extract NSCameraUsageDescription raw "$PLIST" >/dev/null 2>&1 \
        || note "NSCameraUsageDescription missing from Info.plist"
    if plutil -extract NSMicrophoneUsageDescription raw "$PLIST" >/dev/null 2>&1; then
        note "NSMicrophoneUsageDescription present — the app must stay mic-free"
    fi
    ENT=$(codesign -d --entitlements - "$APP" 2>/dev/null || true)
    [ -n "$ENT" ] || note "could not read entitlements from $APP" # else absence checks pass vacuously
    case "$ENT" in *com.apple.security.app-sandbox*) note "app-sandbox entitlement present — must stay un-sandboxed" ;; esac
    case "$ENT" in *com.apple.security.device.audio-input*) note "audio-input entitlement present — must stay mic-free" ;; esac
    case "$ENT" in *com.apple.security.device.camera*) : ;; *) note "camera entitlement missing" ;; esac
    if [ "$fail" -eq 0 ]; then echo "verify-app OK: $APP"; else echo "verify-app FAILED" >&2; exit 1; fi

# post-notarization smoke check (CI runs it before publishing): the signed+stapled
# DMG and app pass Gatekeeper and the appcast is well-formed + EdDSA-signed, so a
# broken release can't reach the auto-updater. Needs a completed `just release`.
verify-release:
    #!/usr/bin/env bash
    set -euo pipefail
    APP=.build/Build/Products/Release/SharePad.app
    DMG=.build/SharePad.dmg
    APPCAST=.build/appcast/appcast.xml
    echo "→ Gatekeeper assessment (app)"; spctl -a -vvv "$APP"
    echo "→ staple validation (app)"; xcrun stapler validate "$APP"
    echo "→ staple validation (dmg)"; xcrun stapler validate "$DMG"
    echo "→ appcast well-formed"; xmllint --noout "$APPCAST"
    grep -q 'sparkle:edSignature' "$APPCAST" || { echo "appcast missing EdDSA signature" >&2; exit 1; }
    echo "verify-release OK"

# scan full git history for committed secrets (same check CI runs)
scan:
    gitleaks git --config .gitleaks.toml --redact --no-banner --verbose .

# verify the Ed25519 signing key pairs with the app's embedded public key.
# Same check CI runs pre-deploy. Reads the key from the file Jon stores locally;
# only the derived public key is printed, never the private key.
check-pairing:
    ED25519_PRIVATE_KEY="$(cat ~/.sharepad-ed25519-private-key.txt)" node scripts/check-key-pairing.mjs

# install the repo git hooks (pre-commit secret scan). Run once per clone/worktree.
install-hooks:
    git config core.hooksPath .githooks
    @echo "git hooks installed (core.hooksPath -> .githooks). Needs: brew install gitleaks"

# ── Analytics ──
# Report GitHub Release download counts: the DMG (installs) and appcast.xml (Sparkle
# update-checks, a proxy for active installs). Read-only; needs `gh` authenticated.
# Only release assets are counted — the versioned DMGs served from sharepad.co
# (GitHub Pages) have no download logs, so they're not included.
downloads:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO="${GH_REPO:-jonyardley/SharePad}"
    echo "→ GitHub Release downloads ($REPO)"
    echo
    gh api "repos/$REPO/releases" --paginate \
        --jq '.[] | .tag_name as $t | (.assets[]? | [$t, .name, (.download_count|tostring)] | @tsv)' \
        | awk -F'\t' '
            { printf "  %-10s %-38s %6s\n", $1, $2, $3
              if ($2 ~ /\.dmg$/)  dmg     += $3
              if ($2 ~ /appcast/) appcast += $3 }
            END {
              print  "  --------------------------------------------------------"
              printf "  DMG downloads (all releases):          %6d\n", dmg
              printf "  appcast.xml fetches (update checks):    %6d\n", appcast }'

# Active installs + version adoption from the appcast Worker's Analytics Engine
# dataset (specs/appcast-analytics.md). Needs CLOUDFLARE_API_TOKEN with the
# "Account Analytics: Read" permission — the wrangler OAuth login does NOT carry it,
# so mint a scoped token (or just read the same data in the Cloudflare dashboard).
# Optional: CF_ACCOUNT_ID (defaults to the SharePad account) and DAYS (default 7).
appcast-stats days="7":
    #!/usr/bin/env bash
    set -euo pipefail
    : "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN (needs 'Account Analytics: Read')}"
    ACCOUNT="${CF_ACCOUNT_ID:-b232fe74d0fd6056b69aeaa6a79c51b7}"
    DAYS="{{ days }}"
    SQL="SELECT blob1 AS version, SUM(_sample_interval) AS checks
         FROM sharepad_appcast
         WHERE timestamp > NOW() - INTERVAL '$DAYS' DAY
         GROUP BY version ORDER BY checks DESC"
    echo "→ appcast update-checks, last $DAYS days (by app version)"
    curl -sS "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/analytics_engine/sql" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-binary "$SQL" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); d.get('success',True) or sys.exit('  query failed: %s'%d.get('errors',d)); rows=d.get('data') or []; t=sum(int(float(r['checks'])) for r in rows); [print('  %-12s %6d'%(r['version'],int(float(r['checks'])))) for r in rows] or print('  (no data yet)'); rows and print('  ------------------\n  %-12s %6d'%('total',t))"

# ── Release / distribution ──
# See specs/distribution.md. `release-build` is ad-hoc and credential-free (enough
# for the Step 1 on-iPad camera check); `sign`/`notarize`/`dmg` need a Developer ID
# cert + an App Store Connect API key supplied via the env vars noted on each.

# build Release with Hardened Runtime, ad-hoc signed.
# CI sets BUILD_NUMBER (monotonic, from the run number) and RELEASE_VERSION (from
# the git tag) so the released version always matches the tag. Local builds fall
# back to the project.yml values.
release-build: gen
    xcodebuild -project SharePad.xcodeproj -scheme SharePad -configuration Release -destination 'platform=macOS' -derivedDataPath .build CURRENT_PROJECT_VERSION={{ env_var_or_default("BUILD_NUMBER", "1") }} MARKETING_VERSION={{ env_var_or_default("RELEASE_VERSION", "1.0.0") }} build

# re-sign the Release build with Developer ID (Hardened Runtime + secure timestamp).
# Needs SIGN_IDENTITY, e.g. "Developer ID Application: Your Name (TEAMID)".
# Sparkle's nested XPC services + helpers are only ad-hoc signed by the build; since
# we sign manually (not via Xcode export), we must re-sign them inside-out with
# -o runtime and NEVER --deep, or hardened runtime/notarization rejects them.
# (https://sparkle-project.org/documentation/sandboxing — "Manually Re-sign…")
sign:
    #!/usr/bin/env bash
    set -euo pipefail
    APP=.build/Build/Products/Release/SharePad.app
    FW="$APP/Contents/Frameworks/Sparkle.framework"
    if [ -d "$FW" ]; then
        V="$FW/Versions/B"
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$V/XPCServices/Installer.xpc"
        codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$V/XPCServices/Downloader.xpc"
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$V/Autoupdate"
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$V/Updater.app"
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$FW"
    fi
    codesign --force --options runtime --timestamp \
        --entitlements Sources/SharePad/SharePad.entitlements \
        --sign "$SIGN_IDENTITY" \
        "$APP"
    codesign --verify --strict --verbose=2 "$APP"

# notarize + staple the signed app. Needs AC_API_KEY_PATH (.p8), AC_API_KEY_ID,
# AC_API_ISSUER_ID (App Store Connect API key).
notarize:
    ditto -c -k --keepParent .build/Build/Products/Release/SharePad.app .build/SharePad.zip
    xcrun notarytool submit .build/SharePad.zip --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID" --wait
    xcrun stapler staple .build/Build/Products/Release/SharePad.app

# package the signed+stapled app into a DMG, then notarize + staple the DMG.
# Needs create-dmg (brew install create-dmg) + the same notarytool env as above.
# NOTE(specs/distribution.md §11.7): create-dmg can exit non-zero in headless CI
# even on success — verify on the first real release before trusting the exit code.
dmg:
    rm -rf .build/dmg .build/SharePad.dmg
    mkdir -p .build/dmg
    cp -R .build/Build/Products/Release/SharePad.app .build/dmg/
    create-dmg --volname SharePad --app-drop-link 420 180 --icon "SharePad.app" 140 180 .build/SharePad.dmg .build/dmg
    xcrun notarytool submit .build/SharePad.dmg --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID" --wait
    xcrun stapler staple .build/SharePad.dmg

# full release pipeline: build → sign → notarize app → package + notarize DMG
release: release-build sign notarize dmg
    @echo "Release DMG: .build/SharePad.dmg"

# generate + EdDSA-sign the Sparkle appcast from the notarized DMG into .build/appcast/.
# CI publishes it (with the DMG) to the gh-pages branch, served at sharepad.co/appcast.xml,
# so there's no push to the protected main branch. The app fetches it via the
# appcast.sharepad.co logging-proxy Worker (specs/appcast-analytics.md). Needs
# SPARKLE_ED_KEY_PATH (the private key file), DOWNLOAD_URL_PREFIX (the gh-pages base
# URL, https://sharepad.co/, trailing slash), and RELEASE_VERSION (tag without the
# leading v) for the versioned DMG filename;
# generate_appcast reads the version from the app inside the DMG and writes appcast.xml.
sparkle-appcast:
    #!/usr/bin/env bash
    set -euo pipefail
    GEN=$(find .build/SourcePackages/artifacts -path '*Sparkle*' -name generate_appcast | head -1)
    [ -n "$GEN" ] || { echo "generate_appcast not found — run a build first to resolve Sparkle" >&2; exit 1; }
    VERSION="${RELEASE_VERSION:?set RELEASE_VERSION (the tag without the leading v)}"
    # Versioned + content-hashed filename so the guessable SharePad.dmg URL 404s and
    # shared links rot each release (see specs/download-url-hardening.md). The EdDSA
    # signature signs DMG *content*, not the name, so renaming is signature-safe.
    HASH=$(shasum -a 256 .build/SharePad.dmg | cut -c1-8)
    DMG_NAME="SharePad-${VERSION}-${HASH}.dmg"
    rm -rf .build/appcast && mkdir -p .build/appcast
    cp .build/SharePad.dmg ".build/appcast/${DMG_NAME}"
    # generate_appcast matches the notes file to the DMG by basename, so the .md must
    # share the versioned basename or --embed-release-notes silently drops the notes.
    if [ -f CHANGELOG.md ]; then awk '/^## /{n++} n==1' CHANGELOG.md > ".build/appcast/SharePad-${VERSION}-${HASH}.md"; fi
    "$GEN" --ed-key-file "$SPARKLE_ED_KEY_PATH" --download-url-prefix "$DOWNLOAD_URL_PREFIX" --embed-release-notes .build/appcast
    echo "Appcast written to .build/appcast/appcast.xml (DMG: ${DMG_NAME})"
