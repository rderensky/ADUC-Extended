# ADUC-Extended v1.2.0

## What's new

- **Group administration** — a third mode in the Users / Computers / Groups
  toggle:
  - search groups with Name / Login / Scope / Category / Description columns;
  - create groups (name, login, description, scope, category, target OU);
  - edit description and e-mail; rename; move between OUs;
  - delete groups, including several selected at once;
  - **member management**: the member list opens on double-click; members are
    added either by browsing the AD hierarchy tree or by search
    (multi-select; disabled accounts are excluded), removal is multi-select
    too.
- **Fast failure on an unreachable domain controller**: a 5-second TCP probe
  shows a clear connection error instead of hanging (login, domain switch,
  and mid-session reconnects).

## Downloads

Each application contains **both English and Russian**; the language switches
inside the app.

| Platform | Source | Binaries |
|---|---|---|
| Windows | `ADUC-Ext-1.2.0-windows.zip` | `ADUC-Ext-1.2.0-win-exe.zip` |
| macOS   | `ADUC-Ext-1.2.0-macos.zip`   | `ADUC-Ext-1.2.0-mac-app.zip` |

## Requirements
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if it is missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
84d464013349228313e522d5787cb90cea98a4b160bd7993d6f0d054d0b34f83  ADUC-Ext-1.2.0-windows.zip
f072d84265d318124559de0681810267789228ae41ee7f79c0927e799de243fb  ADUC-Ext-1.2.0-macos.zip
```
