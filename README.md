<div align="center">

<img src="assets/aduc_ext_icon_1024.png" width="128" alt="ADUC-Extended"/>

# ADUC-Extended

GUI application for everyday Active Directory administration — Windows (PowerShell + WPF)
and macOS (Python + Tkinter).

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-blue)
![Windows](https://img.shields.io/badge/Windows-PowerShell%205.1-5391FE?logo=powershell&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-Python%203.8%2B-3776AB?logo=python&logoColor=white)
![Version](https://img.shields.io/badge/version-1.2.9-orange)

**English** · [Русская версия](README_ru.md)

💛 **На развитие проекта:** https://dalink.to/rderensky

</div>

---

ADUC-Extended is a lightweight alternative to the "Active Directory Users and
Computers" snap-in for the tasks a help desk and system administrators perform
every day. The same application exists for Windows and macOS, is bilingual
(**English / Русский**, switchable on the fly), and runs under the account you
sign in with — nothing is stored or executed on the server side.

## What it does

**Users.** Search by name, login or e-mail; a properties panel with account and
password state; creation with all the usual attributes; enable, disable and
unlock; password reset with a built-in generator; the "password never expires"
flag with an optional automatic clearing date; attribute editing; moving between
organizational units.

**Computers and groups.** The same window switches to computer objects and to
groups: search, properties, creation, renaming, moving, enabling/disabling,
deletion. Group membership is managed from both sides — the user's groups and the
group's members (including nested groups), with a picker that collects members
from several OUs or searches into one list.

**Working at scale.** Multi-selection with bulk actions, an OU tree for
navigation and for choosing targets, name-conflict handling on move, and a
local change journal that records every change made through the application
and who made it.

**Several domains.** A list of saved domains with quick switching (under the
current or another account) and a search that spans all saved domains at once,
with actions on objects from other domains.

**Exchange attributes.** All e-mail addresses kept for a user are read straight
from the directory — no access to the Exchange server is required.

**Interface.** Keyboard shortcuts and a right-click menu in every field, a
responsive toolbar for narrow windows, dates in the format of the selected
language, and a clipboard that works reliably on macOS in both keyboard layouts.

Details of each feature and the changes in every version are in the
[release notes](RELEASE_NOTES.md).

## Repository layout

```
ADUC-Ext/
├── windows/                 # Windows version (PowerShell + WPF)
│   ├── ADUC-Ext.ps1         # bilingual (EN/RU)
│   ├── build_exe.ps1        # build .exe
│   └── aduc_ext.ico
├── macos/                   # macOS version (Python + Tkinter)
│   ├── aduc_ext.py          # bilingual (EN/RU)
│   ├── build_app.sh         # build .app
│   └── aduc_ext.icns
├── assets/                  # icon
├── README.md · README_ru.md
└── RELEASE_NOTES.md · RELEASE_NOTES_ru.md
```

## Quick start

### Windows

```powershell
cd windows
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext.ps1
```

Requires Windows PowerShell 5.1 and the **ActiveDirectory** module (RSAT). If the
module is missing, the app offers to install RSAT automatically (administrator
rights required). Build a standalone `.exe` with `build_exe.ps1`.

### macOS

```bash
cd macos
python3 aduc_ext.py
```

Requires Python 3.8+ with Tkinter; the `ldap3` package is installed automatically
on first run. LDAPS (port 636) is recommended — password changes and creating an
account with a password require a secure connection. Build a `.app` with `build_app.sh`.

## Configuration

At the top of each source file you can set:

- **OU for group selection** — empty by default (all domain groups are shown):
  - Windows: `$Global:AccessGroupsOUName = "OU name"`
  - macOS: `ACCESS_GROUPS_OU_NAME = "OU name"`
- **Groups added automatically on user creation** — empty by default:
  - Windows: `$Global:DefaultCreateGroups = @('group1','group2')`
  - macOS: `DEFAULT_CREATE_GROUPS = ['group1', 'group2']`
- **Attribute for the "password never expires" auto-clear date** —
  `adminDescription` by default:
  - Windows: `$Global:PwdNeverExpiresUntilAttr = 'adminDescription'`
  - macOS: `PWD_NEVER_EXPIRES_UNTIL_ATTR = "adminDescription"`

## Settings storage

The domain list, the interface language and the change journal are stored
locally; passwords are never saved.

| Windows | macOS |
|---|---|
| `%APPDATA%\ADUC-Ext\domains.json` | `~/.aduc_ext_domains.json` |
| `%APPDATA%\ADUC-Ext\history.jsonl` (change history) | `~/.aduc_ext_history.jsonl` (change history) |

## Security notes

- The password is kept only in process memory for the duration of the session.
- Use an account with the minimum required rights.
- Some operations require the corresponding directory rights; without them the
  operation ends with an access-denied message.

## Distribution

Provided as-is for internal use. No public license is granted; all rights reserved.

## Support the project · На развитие проекта

💛 https://dalink.to/rderensky
