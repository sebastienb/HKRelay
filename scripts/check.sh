#!/bin/sh

set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"

./scripts/check-secrets.sh
swift test

if [ -n "${DEVELOPER_DIR:-}" ]; then
    XCODE_DEVELOPER_DIR=$DEVELOPER_DIR
elif [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
    XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
else
    XCODE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

env DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
    xcodebuild \
    -project App/HKRelay.xcodeproj \
    -scheme HKRelay \
    -configuration Release \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath .derived-data \
    CODE_SIGNING_ALLOWED=NO \
    build
