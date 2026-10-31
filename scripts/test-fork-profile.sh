#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-fork-profile.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
for variant in github appstore; do
    flags=(-swift-version 5)
    if [ "$variant" = appstore ]; then flags+=(-D APPSTORE); fi
    swiftc -module-cache-path "$TEST_DIR/cache" "${flags[@]}" \
        NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
        NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
        NotchBuddy/Sources/CoucouKit/PillColors.swift \
        NotchBuddy/Sources/CoucouKit/PillCatalog.swift \
        tests/ForkProfileTests.swift -o "$TEST_DIR/profile-$variant"
    "$TEST_DIR/profile-$variant"
done
