# ADUC-Extended v1.2.1

## What's new

- **Editing shortcuts** in all input fields:
  - macOS: Cmd+Backspace deletes the line (to its start), Ctrl+Backspace
    deletes one word;
  - Windows: Shift+Backspace deletes the line, Ctrl+Backspace deletes one
    word; in the password field Shift+Backspace clears it.
- **Esc closes the active modal dialog** (as Cancel); the main window is
  never closed by Esc.

## Downloads

Each application contains **both English and Russian**; the language switches
inside the app.

| Platform | Source | Binaries |
|---|---|---|
| Windows | `ADUC-Ext-1.2.1-windows.zip` | `ADUC-Ext-1.2.1-win-exe.zip` |
| macOS   | `ADUC-Ext-1.2.1-macos.zip`   | `ADUC-Ext-1.2.1-mac-app.zip` |

## Requirements
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if it is missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
70b86bd07c660dfabfb6840ffeb06d4bc01770738811776153baeae92433a425  ADUC-Ext-1.2.1-windows.zip
af5dcb6de556e80d313e07b13c9876de2ce580a87fe4a4ac109d573fde6710ed  ADUC-Ext-1.2.1-macos.zip
```
