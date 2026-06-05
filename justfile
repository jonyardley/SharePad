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

# run unit tests
test: gen
    xcodebuild -project SharePad.xcodeproj -scheme SharePad -configuration Debug -destination 'platform=macOS' -derivedDataPath .build test

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
# No --deep: the bundle has no nested code yet; revisit when Sparkle is added.
sign:
    codesign --force --options runtime --timestamp \
        --entitlements Sources/SharePad/SharePad.entitlements \
        --sign "$SIGN_IDENTITY" \
        .build/Build/Products/Release/SharePad.app
    codesign --verify --strict --verbose=2 .build/Build/Products/Release/SharePad.app

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
