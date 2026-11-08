#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="HKRelay"
BUNDLE_ID="org.homekitrestbridge.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/App/HKRelay.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.derived-data"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-maccatalyst/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--build-only|--install) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only|--install]" >&2
    exit 2
    ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  else
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

# HomeKit requires a signed build. Use local signing configuration when present;
# explicitly set HKBRIDGE_CODE_SIGNING=NO only for unsigned UI/API smoke tests.
DEFAULT_CODE_SIGNING=NO
if [[ -f "$ROOT_DIR/App/Config/Local.xcconfig" ]]; then
  DEFAULT_CODE_SIGNING=YES
fi
if [[ "${HKBRIDGE_CODE_SIGNING:-$DEFAULT_CODE_SIGNING}" == "YES" ]]; then
  xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme HKRelay \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED_DATA" \
    build
else
  xcodebuild -quiet \
    -project "$PROJECT" \
    -scheme HKRelay \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Built app executable not found: $APP_BINARY" >&2
  exit 1
fi

if [[ "$MODE" == "--build-only" ]]; then
  exit 0
fi

if [[ "$MODE" == "--install" ]]; then
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  INSTALLED_APP="/Applications/$APP_NAME.app"
  BUILT_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")
  if [[ -d "$INSTALLED_APP" ]]; then
    INSTALLED_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")
    if [[ "$BUILT_IDENTIFIER" != "$INSTALLED_IDENTIFIER" ]]; then
      echo "Refusing to replace an app with a different bundle identifier." >&2
      exit 1
    fi
  fi
  INSTALL_WORK=$(mktemp -d "$DERIVED_DATA/install.XXXXXX")
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_WORK/$APP_NAME.app"
  /usr/bin/codesign --verify --deep --strict "$INSTALL_WORK/$APP_NAME.app"
fi

# Keep the working app available until the replacement has built successfully.
pkill -f "/HomeKit REST Bridge.app/Contents/MacOS/HomeKit REST Bridge" >/dev/null 2>&1 || true
pkill -f "/HomeKitLink.app/Contents/MacOS/HomeKitLink" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
for attempt in {1..20}; do
  if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi
  sleep 0.25
done
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "$APP_NAME did not stop; leaving the installed app unchanged." >&2
  exit 1
fi

if [[ "$MODE" == "--install" ]]; then
  if [[ -d "$INSTALLED_APP" ]]; then
    mv "$INSTALLED_APP" "$INSTALL_WORK/previous.app"
  fi
  if ! mv "$INSTALL_WORK/$APP_NAME.app" "$INSTALLED_APP"; then
    if [[ -d "$INSTALL_WORK/previous.app" ]]; then
      mv "$INSTALL_WORK/previous.app" "$INSTALLED_APP"
    fi
    exit 1
  fi
  APP_BUNDLE="$INSTALLED_APP"
  APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  echo "Installed $APP_BUNDLE; previous build retained in $INSTALL_WORK/previous.app"
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
  --verify|verify|--install)
    open_app
    verify_process
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
