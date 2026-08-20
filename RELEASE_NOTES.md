# ADUC-Extended v1.0.2

## What's new

- **Computer objects** — a Users / Computers mode toggle: search, properties,
  rename, move between OUs, edit description, enable/disable, delete.
- **Multi-select** in the list with bulk actions: enable, disable, move to an
  OU, and bulk add of selected users to access groups.
- **"Password never expires"** flag management: an action button, a checkable
  context-menu item, and a checkbox in the edit dialog. Like ADUC, enabling
  the flag also cancels a pending change-at-next-logon requirement, so the
  current password stays valid.
- **Double-click** on a list row opens the edit dialog (users and computers).
- macOS: automatic reconnect after an idle LDAP timeout (no more "Broken
  pipe" errors after the app sits unused).
- Windows: fixed a crash on connect (context-menu wiring) and a toolbar
  layout issue where the mode toggle was clipped.

## Downloads

Each asset contains **both English and Russian** versions and READMEs in both
languages.

| Platform | Source | Binaries |
|---|---|---|
| Windows | `ADUC-Ext-1.0.2-windows.zip` | `ADUC-Ext-1.0.2-win-exe.zip` |
| macOS   | `ADUC-Ext-1.0.2-macos.zip`   | `ADUC-Ext-1.0.2-mac-app-en.zip`, `ADUC-Ext-1.0.2-mac-app-ru.zip` |

## Requirements
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if it is missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
2a78c18b171e03160cd0a20c90f595a3b9f8bdc86974bdb3d8fae4774d2be8dd  ADUC-Ext-1.0.2-windows.zip
e3cbc3f4b9bfa6b8174983eb46297f7d87d37e63114becfb0f71cff2154ea295  ADUC-Ext-1.0.2-macos.zip
```
