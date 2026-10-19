# ADUC-Extended v1.2.9

## What's new

- **Password generator.** A **"Password..."** button on the toolbar opens
  a generator; the same generator is one click away ("Generate...") next
  to the password field in **Reset password** and **Create user**, where
  "Use" fills the field(s) and copies the password to the clipboard.
  - Default: lowercase + uppercase letters + digits, 12 characters.
  - Settings: length slider **8–20**, special characters
    (`!@#$%^&*-_=+?`) on/off, and **"Exclude look-alike characters"**
    (O/0, I/l/1, S/5, Z/2, B/8).
  - Every enabled set is guaranteed to appear at least once; the
    characters come from the OS cryptographic random generator. Settings
    are remembered for the session.
- **Responsive toolbar.** The search, action and domain groups of the
  toolbar re-flow onto two or three lines when the window is narrow, so
  no button is cut off any more; the search field stretches with the
  window.

## Changes carried over from the unpublished 1.2.8

- **All e-mail addresses of a user (Exchange).** The properties panel
  shows a new **"E-mail addresses (Exchange)"** row with every address
  Exchange keeps for the user — the primary SMTP address (marked
  *primary*), secondary smtp aliases and other types (SIP, X500 …) — the
  same list as the "email address" page of the Exchange admin center.
  The data comes straight from the directory (`proxyAddresses`), so no
  access to the Exchange server is needed, and it works for users of
  other domains found by the all-domains search as well.
  - **No Exchange?** The app checks whether the forest has an Exchange
    organization. Without one the row is simply not shown (nothing is
    queried from Exchange); with Exchange but no mailbox the row says
    *"no mailbox: the user has no Exchange addresses"*.

### From 1.2.7

- **First name / Last name in "Edit properties".** The user properties
  dialog now has **First name** (`givenName`) and **Last name** (`sn`)
  fields above Display name, as in the ADUC "New object" dialog; an
  emptied field clears the attribute. The full name (CN) is unchanged —
  renaming the object is still done via Move.
- **Search across all saved domains.** A new **"All saved domains"**
  checkbox next to the search field (users mode) runs the text search —
  by name / surname, login (sAMAccountName / UPN) or e-mail — in every
  domain from the saved-domain list, using the credentials of the
  current session.
  - Results from all domains are merged into the main list; a **Domain**
    column shows where each object was found. The status bar reports
    the scope and lists domains that could not be reached.
  - Objects from other domains are shown read-only: properties are
    displayed, history and (internal build) accesses work, but an action
    (edit, reset password, groups, move, …) offers to **switch to that
    domain** first — after the switch the same search is repeated and
    the object is re-selected. Bulk actions apply only to the connected
    domain.
  - Without a search text, or in Computers / Groups mode, the list
    behaves as before (connected domain only).
- **Domain switch to another domain / forest.** When the session account
  is reused and the target domain rejects it (`invalidCredentials`), the
  app retries with the same password and the account name written out in
  full: first qualified with its **home** domain (`HOME\user`,
  `user@home.domain` — a bare login accepted by the home DC is looked up
  by the target DC in *its* domain, so this is the form a trust needs),
  then re-qualified for the **target** domain (`TARGET\user`,
  `user@target.domain`) for a same-named account in another forest
  without a trust. The home NetBIOS name is read from the directory, not
  guessed from DNS. If every variant fails, the error lists them and
  points at trust direction / selective authentication or "Another
  account".
- **Bind diagnostics.** A failed logon or domain switch now shows the
  domain controller's own reply — including the AD `data` code
  (`52e` wrong name/password, `533` disabled, `775` locked out, `8232`
  LDAP signing required, …) with a plain-language explanation — for each
  login variant tried. The same lines are appended to
  `~/aduc_ext_switch.log` (macOS) / `%APPDATA%\ADUC-Ext\switch.log`
  (Windows); no passwords are written.
- **Per-DC table is more robust.** The list of domain controllers is
  discovered from three sources in turn (DC/RODC account bits, OU=Domain
  Controllers, the forest Sites container); a failed lookup is no longer
  cached for the session, and when the list still cannot be obtained the
  properties panel says so with the server error instead of silently
  showing a single controller.
- **Per-DC table for objects of other domains.** For a user found by the
  all-domains search the controllers of *that* domain are queried (with
  the session account, through the trust), so last logon / bad password
  data is shown per controller without switching the domain first.
- **Faster domain switch.** In the "Switch domain" dialog the **Connect**
  button has the focus when "Current account" is preselected, so Enter
  switches the domain at once; Escape cancels.

## Downloads

Each application contains **both English and Russian**; the language switches
inside the app.

| Platform | Source | Binaries |
|---|---|---|
| Windows | `ADUC-Ext-1.2.9-windows.zip` | `ADUC-Ext-1.2.9-win-exe.zip` |
| macOS   | `ADUC-Ext-1.2.9-macos.zip`   | `ADUC-Ext-1.2.9-mac-app.zip` |

## Requirements
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if it is missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
598d9eef4eabcfbaeb3d0012761a69cef0e87b6e957b04a0c2e3a11d71bba442  ADUC-Ext-1.2.9-windows.zip
f40762c60da3e142f4594043f053359dad8fb3923e2dfb2c37ee135e3d3fd811  ADUC-Ext-1.2.9-macos.zip
```
