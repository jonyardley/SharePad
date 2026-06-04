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
