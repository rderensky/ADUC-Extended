# ADUC-Extended v1.0.1

## What's new / Что нового

- **Context menu** on the user list (right-click): copy login / display name /
  e-mail / UPN / DN / all properties, plus quick actions (enable, disable, unlock,
  reset password, groups, move, edit).
  **Контекстное меню** в списке пользователей: копирование логина / имени / e-mail /
  UPN / DN / всех свойств и быстрые действия.
- **Copy to clipboard** from the properties panel: select text and press Cmd+C /
  Ctrl+C, use the context menu, or (macOS) simply select with the mouse.
  **Копирование в буфер** из панели свойств: выделить и Cmd+C / Ctrl+C, через
  контекстное меню или (macOS) простым выделением мышью.
- Cmd+C / Ctrl+C on a selected list row copies the row (name, login, e-mail,
  description, state).
  Cmd+C / Ctrl+C на строке списка копирует строку.
- **Description** column added to the user list.
  Добавлена колонка **«Описание»** в список пользователей.
- macOS: Edit menu (Cut / Copy / Paste / Select All); reliable clipboard on Tk 9.
  macOS: меню «Правка»; надёжное копирование на Tk 9.

## Downloads / Загрузки

Each asset contains **both English and Russian** versions and READMEs in both
languages. / Каждый архив содержит **английскую и русскую** версии и README на
двух языках.

| Platform / Платформа | Source / Исходники | Binaries / Бинарники |
|---|---|---|
| Windows | `ADUC-Ext-1.0.1-windows.zip` | `ADUC-Ext-1.0.1-win-exe.zip` |
| macOS   | `ADUC-Ext-1.0.1-macos.zip`   | `ADUC-Ext-1.0.1-mac-app-en.zip`, `ADUC-Ext-1.0.1-mac-app-ru.zip` |

## Requirements / Требования
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
9dc2fb2ec066c74da3d8ba330107c2c8199da5829cceb2762ae189b68779971a  ADUC-Ext-1.0.1-windows.zip
72f7630d93efaa0390cb78b57397b8934c4d0a59a6f89ee8fd46e0aa14394d34  ADUC-Ext-1.0.1-macos.zip
```
