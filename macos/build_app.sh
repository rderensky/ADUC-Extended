#!/bin/bash
# ============================================================================
#  Build the macOS application ADUC-Ext (.app) from aduc_ext.py
#  using PyInstaller. Run on macOS.
#
#  Usage:
#      chmod +x build_app.sh
#      ./build_app.sh
#
#  Result: dist/ADUC-Ext.app
# ============================================================================
set -e

APP_NAME="ADUC-Ext"
APP_VERSION="1.2.1"
SCRIPT="aduc_ext.py"
ICON="aduc_ext.icns"   # application icon (.icns)

cd "$(dirname "$0")"

if [ ! -f "$SCRIPT" ]; then
    echo "$SCRIPT not found next to the build script."
    exit 1
fi

echo "==> Checking Python and Tkinter..."
python3 -c "import tkinter" 2>/dev/null || {
    echo "Tkinter not found. Install it: brew install python-tk"
    exit 1
}

echo "==> Installing PyInstaller and ldap3..."
# On newer macOS the system Python requires --break-system-packages
python3 -m pip install --user pyinstaller ldap3 2>/dev/null \
  || python3 -m pip install --user --break-system-packages pyinstaller ldap3

ICON_ARG=""
if [ -n "$ICON" ] && [ -f "$ICON" ]; then
    ICON_ARG="--icon $ICON"
fi

echo "==> Building the application..."
python3 -m PyInstaller --windowed --noconfirm --clean \
    --name "$APP_NAME" \
    --hidden-import ldap3 \
    --hidden-import pyasn1 \
    $ICON_ARG \
    "$SCRIPT"

echo "==> Writing the version into Info.plist..."
PLIST="dist/$APP_NAME.app/Contents/Info.plist"
if [ -f "$PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$PLIST" || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_VERSION" "$PLIST" || true
fi

echo "==> Ad-hoc signing the application (required to run on Apple Silicon)..."
codesign --force --deep --sign - "dist/$APP_NAME.app"

echo "==> Packaging into a zip for transfer (preserves permissions and signature)..."
# ditto preserves the bundle structure correctly, unlike a plain copy
ditto -c -k --sequesterRsrc --keepParent "dist/$APP_NAME.app" "dist/$APP_NAME.zip"

echo ""
echo "==> Done:"
echo "     dist/$APP_NAME.app   — the application"
echo "     dist/$APP_NAME.zip   — transfer THIS archive to other Macs"
echo ""
echo "Show the binary architecture (arm64 / x86_64):"
echo "     file \"dist/$APP_NAME.app/Contents/MacOS/$APP_NAME\""
echo ""
echo "On ANOTHER Mac after unzipping, if it will not open:"
echo "     xattr -cr \"$APP_NAME.app\""
echo "     codesign --force --deep --sign - \"$APP_NAME.app\""
echo "  then right-click -> Open -> Open."
