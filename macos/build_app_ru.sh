#!/bin/bash
# ============================================================================
#  Сборка macOS-приложения ADUC-Ext-ru (.app) из aduc_ext_ru.py
#  через PyInstaller. Запускать на macOS.
#
#  Использование:
#      chmod +x build_app_ru.sh
#      ./build_app_ru.sh
#
#  Результат: dist/ADUC-Ext-ru.app
# ============================================================================
set -e

APP_NAME="ADUC-Ext-ru"
APP_VERSION="1.0.2"
SCRIPT="aduc_ext_ru.py"
ICON="aduc_ext.icns"   # иконка приложения (.icns)

cd "$(dirname "$0")"

if [ ! -f "$SCRIPT" ]; then
    echo "Не найден $SCRIPT рядом со скриптом сборки."
    exit 1
fi

echo "==> Проверяю Python и Tkinter..."
python3 -c "import tkinter" 2>/dev/null || {
    echo "Tkinter не найден. Установите: brew install python-tk"
    exit 1
}

echo "==> Устанавливаю PyInstaller и ldap3..."
python3 -m pip install --user pyinstaller ldap3 2>/dev/null \
  || python3 -m pip install --user --break-system-packages pyinstaller ldap3

ICON_ARG=""
if [ -n "$ICON" ] && [ -f "$ICON" ]; then
    ICON_ARG="--icon $ICON"
fi

echo "==> Собираю приложение..."
python3 -m PyInstaller --windowed --noconfirm --clean \
    --name "$APP_NAME" \
    --hidden-import ldap3 \
    --hidden-import pyasn1 \
    $ICON_ARG \
    "$SCRIPT"

echo "==> Прописываю версию в Info.plist..."
PLIST="dist/$APP_NAME.app/Contents/Info.plist"
if [ -f "$PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$PLIST" || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_VERSION" "$PLIST" || true
fi

echo "==> Ad-hoc подпись приложения (нужна для запуска на Apple Silicon)..."
codesign --force --deep --sign - "dist/$APP_NAME.app"

echo "==> Упаковываю в zip для переноса (сохраняет права и подпись)..."
ditto -c -k --sequesterRsrc --keepParent "dist/$APP_NAME.app" "dist/$APP_NAME.zip"

echo ""
echo "==> Готово:"
echo "     dist/$APP_NAME.app   — приложение"
echo "     dist/$APP_NAME.zip   — переносите на другие Mac ИМЕННО этот архив"
