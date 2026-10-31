#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-toolbox.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export COUCOU_TOOLBOX_SUPPORT_DIR="$TEST_DIR/support"
swift test --package-path Toolbox "$@"
