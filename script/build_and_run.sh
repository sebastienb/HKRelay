#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="HomeKitLink"
BUNDLE_ID="org.homekitrestbridge.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/App/HomeKitRESTBridge.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.derived-data"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-maccatalyst/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  else
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

pkill -f "/HomeKit REST Bridge.app/Contents/MacOS/HomeKit REST Bridge" >/dev/null 2>&1 || true
pkill -f "/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true

# HomeKit requires a signed build. Use local signing configuration when present;
# explicitly set HKBRIDGE_CODE_SIGNING=NO only for unsigned UI/API smoke tests.
DEFAULT_CODE_SIGNING=NO
if [[ -f "$ROOT_DIR/App/Config/Local.xcconfig" ]]; then
  DEFAULT_CODE_SIGNING=YES
fi
if [[ "${HKBRIDGE_CODE_SIGNING:-$DEFAULT_CODE_SIGNING}" == "YES" ]]; then
  xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme HomeKitRESTBridge \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED_DATA" \
    build
else
  xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme HomeKitRESTBridge \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Built app executable not found: $APP_BINARY" >&2
  exit 1
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_process() {
  local attempt
  for attempt in {1..20}; do
    if pgrep -f "$APP_BINARY" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not remain running after launch." >&2
  return 1
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    verify_process
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    verify_process
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_process
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
