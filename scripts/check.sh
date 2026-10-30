#!/usr/bin/env bash
# The gate every commit and PR must pass: generate, lint, build both apps, run the unit tests.
# See TESTING.md section 3.
#
#   scripts/check.sh                 everything a PR needs
#   scripts/check.sh --ui            ...plus the iPhone UI smoke suite
#   scripts/check.sh --fast          iOS unit tests only (no lint, builds or watchOS tests)
#   scripts/check.sh --sim "iPhone 17" --watch-sim "Apple Watch Series 11 (42mm)"
#
# Extra xcodebuild arguments can be passed in XCODEBUILD_FLAGS (CI uses CODE_SIGNING_ALLOWED=NO).
set -euo pipefail

cd "$(dirname "$0")/.."

# Worktrees default to a different simulator pair from the main checkout, so they can test side by side.
if [[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]]; then
    sim="iPhone 17"
    watch_sim="Apple Watch Series 11 (42mm)"
else
    sim="iPhone 17 Pro"
    watch_sim="Apple Watch Series 11 (46mm)"
fi
run_ui=0
fast=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ui) run_ui=1 ;;
        --fast) fast=1 ;;
        --sim) sim="$2"; shift ;;
        --watch-sim) watch_sim="$2"; shift ;;
        -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# A simulator is a name, or "id=<UDID>" (CI picks by UDID).
destination() {
    if [[ "$2" == id=* ]]; then echo "platform=$1 Simulator,$2"; else echo "platform=$1 Simulator,name=$2"; fi
}
ios_destination="$(destination iOS "$sim")"
watch_destination="$(destination watchOS "$watch_sim")"
results=build/results
read -r -a extra_flags <<< "${XCODEBUILD_FLAGS:-}"

if command -v xcbeautify > /dev/null; then
    pretty=(xcbeautify --quiet --disable-logging)
else
    pretty=(cat)
fi

step() {
    printf '\n\033[1m==> %s\033[0m\n' "$*"
}

xcb() {
    xcodebuild -project Rootine.xcodeproj -derivedDataPath build ${extra_flags[@]+"${extra_flags[@]}"} "$@" | "${pretty[@]}"
}

run_tests() {
    local scheme="$1" destination="$2" name="$3"
    rm -rf "$results/$name.xcresult"
    if ! xcb -scheme "$scheme" -destination "$destination" -enableCodeCoverage YES \
        -resultBundlePath "$results/$name.xcresult" test; then
        report_failures "$results/$name.xcresult"
        return 1
    fi
}

# xcbeautify hides crashes and some failures; list them from the result bundle.
report_failures() {
    [[ -d "$1" ]] || return 0
    printf '\n\033[31mFailed tests:\033[0m\n'
    xcrun xcresulttool get test-results summary --path "$1" | python3 -c '
import json, sys
for failure in json.load(sys.stdin).get("testFailures", []):
    print("  " + failure["testIdentifierString"] + ": " + failure["failureText"])
'
}

coverage_summary() {
    local bundle="$1"
    step "Coverage of Shared/ (lowest first)"
    xcrun xccov view --report --json "$bundle" | python3 -c '
import json, sys
report = json.load(sys.stdin)
files = {}
for target in report["targets"]:
    for f in target["files"]:
        if "/Shared/" in f["path"]:
            files[f["path"].split("/Shared/")[1]] = f
covered = sum(f["coveredLines"] for f in files.values())
total = sum(f["executableLines"] for f in files.values())
for name, f in sorted(files.items(), key=lambda kv: kv[1]["lineCoverage"]):
    print("%5.1f%%  %4d/%-4d  %s" % (f["lineCoverage"] * 100, f["coveredLines"], f["executableLines"], name))
if total:
    print("%5.1f%%  %4d/%-4d  Shared/ overall" % (covered / total * 100, covered, total))
' | tee "$results/coverage.txt"
}

mkdir -p "$results"

step "Generate project"
xcodegen generate --quiet

if [[ $fast == 1 ]]; then
    step "iOS unit tests ($sim)"
    run_tests Rootine "$ios_destination" unit-ios
    exit 0
fi

step "Lint"
# Explicit config: in a worktree SwiftFormat would otherwise pick up the main checkout's config, which excludes .claude.
swiftformat --config .swiftformat --lint --quiet .
swiftlint lint --strict --quiet

step "Build iPhone app (embeds the Watch app)"
xcb -scheme Rootine -destination "$ios_destination" build

step "Build Watch app"
xcb -scheme RootineWatch -destination "$watch_destination" build

step "iOS unit tests ($sim)"
run_tests Rootine "$ios_destination" unit-ios

step "watchOS unit tests ($watch_sim)"
run_tests RootineWatch "$watch_destination" unit-watchos

if [[ $run_ui == 1 ]]; then
    step "iPhone UI smoke tests ($sim)"
    run_tests RootineUITests "$ios_destination" ui-ios
fi

coverage_summary "$results/unit-ios.xcresult"
step "All checks passed"
