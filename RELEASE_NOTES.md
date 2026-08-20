# ADUC-Extended v1.1.0

## What's new

- **One bilingual application** instead of separate English and Russian
  builds: `aduc_ext.py` (macOS) and `ADUC-Ext.ps1` (Windows) now contain
  both languages.
- **Language switching on the fly** — an EN/RU selector in the login window
  and in the main window; the interface rebuilds instantly, no restart
  required. The choice is remembered in the settings file.
- Dates follow the language: `YYYY-MMM-DD` (EN) or `DD MMM YYYY` (RU), the
  date-picker calendar included.
- Unified settings: one file per platform for the domain list and language
  (`%APPDATA%\ADUC-Ext\domains.json` on Windows, `~/.aduc_ext_domains.json`
  on macOS). Passwords are never saved.
- Includes all v1.0.2 functionality: computer objects, multi-select bulk
  actions, "password never expires" management, double-click editing.

## Downloads

Each application contains **both English and Russian**; the language switches
inside the app.

| Platform | Source | Binaries |
|---|---|---|
| Windows | `ADUC-Ext-1.1.0-windows.zip` | `ADUC-Ext-1.1.0-win-exe.zip` |
| macOS   | `ADUC-Ext-1.1.0-macos.zip`   | `ADUC-Ext-1.1.0-mac-app.zip` |

## Requirements
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if it is missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## Upgrade notes
- The Russian variants (`aduc_ext_ru.py`, `ADUC-Ext-ru.ps1`) are gone; run the
  unified app and pick the language in the interface.
- A previously saved Russian-variant domain list is not migrated: the unified
  app reads the English variant's settings path (see above).

## SHA-256 (source archives)
```
a5db5be8eec4149406faf058d65e725294d2dae124d338599747d925b5f6c63c  ADUC-Ext-1.1.0-windows.zip
736a0dd2b25b15b2f442c27cbccf1df8e948d29a0430746bb597459cf5302369  ADUC-Ext-1.1.0-macos.zip
```
