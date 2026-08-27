# ADUC-Extended v1.2.2

## What's new

- **Nested groups**: the group edit dialog now manages the groups the group
  itself belongs to (Member Of) — add and remove parent groups, like the
  ADUC snap-in.
- **Member picker with a selection basket**: double-click adds a user to
  the list at the bottom of the picker; repeat the search or switch OUs
  without leaving the window and add several members from different OUs
  at once.
- **macOS: clipboard and shortcuts overhaul (Tk 9)**:
  - Cmd+V / Cmd+C / Cmd+X / Cmd+Z / Cmd+A work in every input field, in
    both English and Russian keyboard layouts;
  - Cyrillic text is copied and pasted correctly;
  - the intermittent double paste is fixed;
  - Cmd+Z undoes the last typing or paste; Cmd+A selects the field;
  - right-click opens a Cut / Copy / Paste / Select All menu.

## Downloads

Each application contains **both English and Russian**; the language switches
inside the app.

| Platform | Source | Binaries |
|---|---|---|
| Windows | `ADUC-Ext-1.2.2-windows.zip` | `ADUC-Ext-1.2.2-win-exe.zip` |
| macOS   | `ADUC-Ext-1.2.2-macos.zip`   | `ADUC-Ext-1.2.2-mac-app.zip` |

## Requirements
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if it is missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
5b014d2f247df7d034e6ca5fcd5d4e90763bed1377c3ec4f17ebc83287a2db1e  ADUC-Ext-1.2.2-windows.zip
0fae1f2e2b5d686a96c122f84c1a8e4e133de38f274390926806ba6808278735  ADUC-Ext-1.2.2-macos.zip
```
