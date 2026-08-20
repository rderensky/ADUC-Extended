<div align="center">

<img src="assets/aduc_ext_icon_1024.png" width="128" alt="ADUC-Extended"/>

# ADUC-Extended

GUI application for managing Active Directory accounts — Windows (PowerShell + WPF)
and macOS (Python + Tkinter).

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-blue)
![Windows](https://img.shields.io/badge/Windows-PowerShell%205.1-5391FE?logo=powershell&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-Python%203.8%2B-3776AB?logo=python&logoColor=white)
![Version](https://img.shields.io/badge/version-1.0.2-orange)

**English** · [Русская версия](README_ru.md)

💛 **На развитие проекта:** https://dalink.to/rderensky

</div>

---

Both platform builds ship an **English** and a **Russian** variant. On startup the
app prompts for credentials and performs all operations under the specified account.

## Features

- Search and view user properties (including password details: last set date,
  change required, bad password attempts).
- Computer objects (Users / Computers mode toggle): search, properties, rename,
  move between OUs, edit description, enable/disable, delete.
- Navigation of the organizational unit (OU) tree.
- Account creation: name, login, UPN, e-mail, description, password, OU selection
  via the tree, expiration date, group selection; duplicate-login check.
- Enable, disable, and unlock accounts.
- Password reset.
- Group membership management, including bulk add of selected users to groups.
- Move accounts between organizational units.
- Multi-select with bulk actions: enable, disable, move to an OU.
- Manage the "password never expires" flag (like ADUC, enabling it also
  cancels a pending change-at-next-logon requirement).
- Attribute editing; double-click on a list row opens the edit dialog.
- Domain list with switching; a domain switch uses the active session credentials.

## Repository layout

```
ADUC-Ext/
├── windows/                 # Windows version (PowerShell + WPF)
│   ├── ADUC-Ext.ps1         # English
│   ├── ADUC-Ext-ru.ps1      # Russian
│   ├── build_exe.ps1        # build .exe (English)
│   ├── build_exe_ru.ps1     # build .exe (Russian)
│   └── aduc_ext.ico
├── macos/                   # macOS version (Python + Tkinter)
│   ├── aduc_ext.py          # English
│   ├── aduc_ext_ru.py       # Russian
│   ├── build_app.sh         # build .app (English)
│   ├── build_app_ru.sh      # build .app (Russian)
│   └── aduc_ext.icns
├── assets/                  # icon
├── README.md · README_ru.md
└── RELEASE_NOTES.md
```

## Quick start

### Windows

```powershell
cd windows
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext.ps1      # English
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext-ru.ps1   # Russian
```

Requires Windows PowerShell 5.1 and the **ActiveDirectory** module (RSAT). If the
module is missing, the app offers to install RSAT automatically (administrator
rights required). Build a standalone `.exe` with `build_exe.ps1` / `build_exe_ru.ps1`.

### macOS

```bash
cd macos
python3 aduc_ext.py      # English
python3 aduc_ext_ru.py   # Russian
```

Requires Python 3.8+ with Tkinter; the `ldap3` package is installed automatically
on first run. LDAPS (port 636) is recommended — password changes and creating an
account with a password require a secure connection. Build a `.app` with
`build_app.sh` / `build_app_ru.sh`.

## Configuration

At the top of each source file you can set:

- **OU for group selection** — empty by default (all domain groups are shown):
  - Windows: `$Global:AccessGroupsOUName = "OU name"`
  - macOS: `ACCESS_GROUPS_OU_NAME = "OU name"`
- **Groups added automatically on user creation** — empty by default:
  - Windows: `$Global:DefaultCreateGroups = @('group1','group2')`
  - macOS: `DEFAULT_CREATE_GROUPS = ['group1', 'group2']`

## Settings storage

The domain list is stored locally (passwords are never saved):

| Version | Windows | macOS |
|---|---|---|
| English | `%APPDATA%\ADUC-Ext\domains.json` | `~/.aduc_ext_domains.json` |
| Russian | `%APPDATA%\ADUC-Ext-ru\domains.json` | `~/.aduc_ext_ru_domains.json` |

## Security notes

- The password is kept only in process memory for the duration of the session.
- Use an account with the minimum required rights.
- Some operations require the corresponding directory rights; without them the
  operation ends with an access-denied message.

## Distribution

Provided as-is for internal use. No public license is granted; all rights reserved.

## Support the project · На развитие проекта

💛 https://dalink.to/rderensky
