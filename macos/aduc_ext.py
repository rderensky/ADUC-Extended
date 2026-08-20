#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ADUC-Ext — Active Directory account management.

A macOS GUI application that connects to Active Directory
over LDAP/LDAPS. On startup it prompts for credentials, and all
operations are performed under the specified account.

Features:
    - search and view user properties;
    - navigate organizational units (OUs);
    - create accounts;
    - enable, disable, and unlock;
    - reset password;
    - manage group membership;
    - move between organizational units;
    - edit attributes.

Requirements: Python 3.8+ with Tkinter and the ldap3 package (installed automatically
on first run).

Run:
    python3 aduc_ext.py
"""

import os
import sys
import ssl
import json
import calendar
import datetime
import subprocess
import importlib

# Tkinter is required for the GUI
try:
    import tkinter as tk
    from tkinter import ttk, messagebox, simpledialog
except ImportError:
    sys.stderr.write(
        "Tkinter module not found (required for the GUI).\n"
        "Install it: brew install python-tk, or use Python from python.org.\n")
    raise SystemExit(1)


# --- Dependency check and automatic installation ---
REQUIRED_PACKAGES = [
    # (import name, pip package name)
    ("ldap3", "ldap3"),
]


def _pip_install(package):
    """Tries to install the package several ways. Returns True on success."""
    attempts = [
        [sys.executable, "-m", "pip", "install", package],
        [sys.executable, "-m", "pip", "install", "--user", package],
        [sys.executable, "-m", "pip", "install", "--break-system-packages", package],
    ]
    for cmd in attempts:
        try:
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                return True
        except Exception:
            continue
    return False


def ensure_dependencies():
    """Checks for required packages and installs any that are missing.
    Returns the list of packages that could not be installed."""
    missing = []
    for mod_name, pip_name in REQUIRED_PACKAGES:
        try:
            importlib.import_module(mod_name)
        except ImportError:
            missing.append((mod_name, pip_name))

    if not missing:
        return []

    # Small notification window shown during installation
    splash = tk.Tk()
    splash.title("Checking dependencies")
    splash.geometry("420x150")
    splash.resizable(False, False)
    names = ", ".join(p for _, p in missing)
    lbl = tk.Label(
        splash, padx=20, pady=20, justify="left", font=("", 13),
        text=f"Missing components: {names}\n\nInstalling, please wait…")
    lbl.pack(expand=True, fill="both")
    splash.update()

    still_missing = []
    for mod_name, pip_name in missing:
        lbl.config(text=f"Installing component: {pip_name}\nPlease wait…")
        splash.update()
        ok = _pip_install(pip_name)
        importlib.invalidate_caches()
        try:
            importlib.import_module(mod_name)
        except ImportError:
            ok = False
        if not ok:
            still_missing.append(pip_name)

    splash.destroy()
    return still_missing


_failed = ensure_dependencies()
if _failed:
    _r = tk.Tk(); _r.withdraw()
    messagebox.showerror(
        "Failed to install dependencies",
        "Could not install automatically: " + ", ".join(_failed) + "\n\n"
        "Install manually in a terminal:\n"
        "    pip3 install " + " ".join(_failed) + "\n\n"
        "If pip is not found:\n"
        "    python3 -m ensurepip --upgrade")
    raise SystemExit(1)

from ldap3 import (
    Server, Connection, ALL, SUBTREE, LEVEL, MODIFY_REPLACE, MODIFY_ADD,
    MODIFY_DELETE, Tls, RESTARTABLE,
)
from ldap3.core.exceptions import LDAPException


# --- User attributes requested from AD ---
USER_ATTRS = [
    'displayName', 'sAMAccountName', 'userPrincipalName', 'givenName', 'sn',
    'mail', 'userAccountControl', 'msDS-User-Account-Control-Computed',
    'lockoutTime', 'description', 'title', 'department', 'company',
    'physicalDeliveryOfficeName', 'telephoneNumber', 'distinguishedName',
    'whenCreated', 'pwdLastSet', 'lastLogonTimestamp', 'accountExpires',
    'msDS-UserPasswordExpiryTimeComputed', 'badPwdCount', 'badPasswordTime',
]

# --- Computer attributes requested from AD ---
COMPUTER_ATTRS = [
    'cn', 'name', 'sAMAccountName', 'dNSHostName', 'operatingSystem',
    'operatingSystemVersion', 'description', 'userAccountControl',
    'distinguishedName', 'whenCreated', 'lastLogonTimestamp',
]

# userAccountControl bits
UAC_DISABLED = 0x0002          # ACCOUNTDISABLE
UAC_NORMAL_ACCOUNT = 0x0200    # NORMAL_ACCOUNT
UAC_DONT_EXPIRE_PASSWORD = 0x10000
# Lockout bit in msDS-User-Account-Control-Computed
UF_LOCKOUT = 0x0010

# Organizational unit (OU) to pick groups from. If left empty,
# the group picker shows all groups in the domain.
ACCESS_GROUPS_OU_NAME = ""

# Groups added automatically when creating a user. Empty by default.
DEFAULT_CREATE_GROUPS = []


# ============================================================================
#  Domain list storage (config)
# ============================================================================
class ConfigStore:
    """Domain list stored in a JSON file (passwords are NOT saved)."""

    def __init__(self, path=None):
        self.path = path or os.path.join(
            os.path.expanduser("~"), ".aduc_ext_domains.json")

    def load(self):
        try:
            with open(self.path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            return data.get('domains', []) if isinstance(data, dict) else []
        except Exception:
            return []

    def save(self, domains):
        try:
            with open(self.path, 'w', encoding='utf-8') as f:
                json.dump({'domains': domains}, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def upsert(self, profile):
        """Add or update a domain profile by its host field."""
        domains = [d for d in self.load() if d.get('host') != profile.get('host')]
        domains.append(profile)
        domains.sort(key=lambda d: (d.get('name') or d.get('host') or '').lower())
        self.save(domains)
        return domains

    def remove(self, host):
        domains = [d for d in self.load() if d.get('host') != host]
        self.save(domains)
        return domains


# ============================================================================
#  AD access layer
# ============================================================================
class ADClient:
    """ldap3 wrapper for AD user operations."""

    def __init__(self):
        self.conn = None
        self.server = None
        self.base_dn = None
        self.upn_suffix = None
        self.host = None
        self.username = None
        self._password = None
        self._use_ssl = True
        self._verify = False
        self._access_ou = None
        self._access_ou_done = False

    def connect(self, host, username, password, use_ssl=True,
                port=None, verify_cert=True):
        """Establishes a connection and verifies credentials (bind)."""
        if port is None:
            port = 636 if use_ssl else 389

        tls = None
        if use_ssl:
            validate = ssl.CERT_REQUIRED if verify_cert else ssl.CERT_NONE
            tls = Tls(validate=validate, version=ssl.PROTOCOL_TLS_CLIENT
                      if hasattr(ssl, 'PROTOCOL_TLS_CLIENT') else ssl.PROTOCOL_TLS)

        self.server = Server(host, port=port, use_ssl=use_ssl,
                             get_info=ALL, tls=tls, connect_timeout=10)
        # SIMPLE bind; auto_bind raises on invalid credentials
        # raise_exceptions=False: operation errors are checked via self._check(),
        # invalid credentials still raise through auto_bind.
        # RESTARTABLE: if the DC or a firewall drops an idle connection
        # ("Broken pipe" after inactivity), ldap3 transparently reconnects,
        # re-binds with the same credentials and retries the operation.
        self.conn = Connection(
            self.server, user=username, password=password,
            authentication='SIMPLE', auto_bind=True, raise_exceptions=False,
            client_strategy=RESTARTABLE)
        # Keep retries short so the UI never hangs on a genuinely dead server
        try:
            self.conn.strategy.restartable_tries = 2
            self.conn.strategy.restartable_sleep_time = 1
        except Exception:
            pass

        # Determine the domain base DN from RootDSE
        self.base_dn = self.server.info.other.get(
            'defaultNamingContext', [None])[0]
        if not self.base_dn:
            # Fallback: build it from the domain name
            self.base_dn = ','.join('dc=' + p for p in host.split('.')
                                    if '.' in host)
        self.host = host
        # Store the active session credentials (to switch domains without
        # re-entering them). Stored only after a successful bind.
        self.username = username
        self._password = password
        self._use_ssl = use_ssl
        self._verify = verify_cert
        # Reset the groups OU cache on a new connection
        self._access_ou = None
        self._access_ou_done = False
        # UPN suffix from base_dn (dc=corp,dc=local -> corp.local)
        parts = [x.split('=')[1] for x in self.base_dn.split(',')
                 if x.lower().startswith('dc=')]
        self.upn_suffix = '.'.join(parts) if parts else host
        return True

    def switch_server(self, host, use_ssl=None, verify_cert=None):
        """Reconnect to another domain/controller using the credentials
        of the current session. Raises on failure (no access/rights)."""
        if not self.username:
            raise RuntimeError("No active session to switch domains.")
        if use_ssl is None:
            use_ssl = self._use_ssl
        if verify_cert is None:
            verify_cert = self._verify
        return self.connect(host, self.username, self._password,
                            use_ssl=use_ssl, verify_cert=verify_cert)

    def is_ssl(self):
        return bool(self.server and self.server.ssl)

    # ---- Paged search (removes the AD 1000-record limit) ----
    def _paged_search(self, base, flt, attributes, scope=SUBTREE,
                      page_size=1000):
        all_entries = []
        cookie = None
        while True:
            ok = self.conn.search(base, flt, search_scope=scope,
                                  attributes=attributes,
                                  paged_size=page_size, paged_cookie=cookie)
            if not ok and not self.conn.entries:
                # Check whether it is an error (e.g. an invalid base)
                self._check()
            all_entries.extend(self.conn.entries)
            try:
                ctrl = self.conn.result['controls']['1.2.840.113556.1.4.319']
                cookie = ctrl['value']['cookie']
            except (KeyError, TypeError):
                cookie = None
            if not cookie:
                break
        return all_entries

    # ---- User search ----
    def search_users(self, query=None, base=None, scope=SUBTREE):
        """query — search text; base — container/OU DN; scope — LEVEL/SUBTREE.
        Returns all matching users (paged, no limit)."""
        base = base or self.base_dn
        query = (query or '').strip().replace('*', '')
        if query:
            q = _escape_filter(query)
            flt = (
                "(&(objectCategory=person)(objectClass=user)"
                f"(|(cn=*{q}*)(sAMAccountName=*{q}*)(mail=*{q}*)"
                f"(displayName=*{q}*)(givenName=*{q}*)(sn=*{q}*)"
                f"(userPrincipalName=*{q}*)))"
            )
            scope = SUBTREE  # text search always spans the whole base subtree
        else:
            flt = "(&(objectCategory=person)(objectClass=user))"

        entries = self._paged_search(base, flt, USER_ATTRS, scope)
        result = [self._entry_to_dict(e) for e in entries]
        result.sort(key=lambda x: (x.get('name') or '').lower())
        return result

    def get_user(self, dn):
        self.conn.search(dn, "(objectClass=user)", search_scope='BASE',
                         attributes=USER_ATTRS)
        if not self.conn.entries:
            return None
        return self._entry_to_dict(self.conn.entries[0])

    def _entry_to_dict(self, e):
        def v(attr, default=''):
            try:
                val = e[attr].value
                return val if val is not None else default
            except Exception:
                return default

        uac = v('userAccountControl', 0) or 0
        try:
            uac = int(uac)
        except (ValueError, TypeError):
            uac = 0
        computed = v('msDS-User-Account-Control-Computed', 0) or 0
        try:
            computed = int(computed)
        except (ValueError, TypeError):
            computed = 0

        enabled = not (uac & UAC_DISABLED)
        locked = bool(computed & UF_LOCKOUT)
        if locked:
            state = "Locked"
        elif not enabled:
            state = "Disabled"
        else:
            state = "Active"

        return {
            'name': v('displayName') or str(e.entry_dn).split(',')[0][3:],
            'displayName': v('displayName'),
            'sAMAccountName': v('sAMAccountName'),
            'userPrincipalName': v('userPrincipalName'),
            'givenName': v('givenName'),
            'sn': v('sn'),
            'mail': v('mail'),
            'description': v('description'),
            'title': v('title'),
            'department': v('department'),
            'company': v('company'),
            'office': v('physicalDeliveryOfficeName'),
            'phone': v('telephoneNumber'),
            'enabled': enabled,
            'locked': locked,
            'state': state,
            'dn': str(e.entry_dn),
            'whenCreated': v('whenCreated'),
            'pwdLastSet': v('pwdLastSet'),
            'lastLogon': v('lastLogonTimestamp'),
            'accountExpires': v('accountExpires'),
            'pwdExpiry': v('msDS-UserPasswordExpiryTimeComputed'),
            'badPwdCount': v('badPwdCount'),
            'badPwdTime': v('badPasswordTime'),
            'dontExpire': bool(uac & UAC_DONT_EXPIRE_PASSWORD),
            'uac': uac,
        }

    # ---- OU and group listing ----
    def list_ous(self):
        """organizationalUnit only — for choosing the target container."""
        entries = self._paged_search(
            self.base_dn, "(objectClass=organizationalUnit)",
            ['distinguishedName'], SUBTREE)
        ous = [str(e.entry_dn) for e in entries]
        ous.sort()
        return ous

    def list_tree_nodes(self):
        """OUs plus standard containers (CN=Users, CN=Computers, etc.) —
        for building the tree, like the ADUC snap-in."""
        flt = ("(|(objectClass=organizationalUnit)"
               "(objectClass=container)(objectClass=builtinDomain))")
        entries = self._paged_search(
            self.base_dn, flt, ['distinguishedName', 'objectClass'], SUBTREE)
        nodes = [str(e.entry_dn) for e in entries
                 if str(e.entry_dn).lower() != self.base_dn.lower()]
        # Sort by depth (comma count), then alphabetically
        nodes.sort(key=lambda dn: (dn.count(','), dn.lower()))
        return nodes

    def get_user_groups(self, dn):
        self.conn.search(dn, "(objectClass=user)", search_scope='BASE',
                         attributes=['memberOf'])
        if not self.conn.entries:
            return []
        member_of = self.conn.entries[0]['memberOf'].value
        if member_of is None:
            return []
        if isinstance(member_of, str):
            member_of = [member_of]
        groups = []
        for gdn in member_of:
            cn = gdn.split(',')[0]
            cn = cn[3:] if cn.lower().startswith('cn=') else cn
            groups.append({'cn': cn, 'dn': gdn})
        groups.sort(key=lambda g: g['cn'].lower())
        return groups

    def find_group_dn(self, name):
        name = name.strip()
        if name.lower().startswith('cn=') and ',' in name:
            return name  # already a DN
        q = _escape_filter(name)
        flt = f"(&(objectClass=group)(|(cn={q})(sAMAccountName={q})))"
        self.conn.search(self.base_dn, flt, search_scope=SUBTREE,
                         attributes=['distinguishedName'])
        if self.conn.entries:
            return str(self.conn.entries[0].entry_dn)
        return None

    def get_access_groups_dn(self):
        """DN of the OU set in ACCESS_GROUPS_OU_NAME. Returns None
        if the name is not set or the OU is not found. Cached."""
        if not self._access_ou_done:
            self._access_ou_done = True
            self._access_ou = None
            if ACCESS_GROUPS_OU_NAME:
                try:
                    name = _escape_filter(ACCESS_GROUPS_OU_NAME)
                    entries = self._paged_search(
                        self.base_dn,
                        f"(&(objectClass=organizationalUnit)(ou={name}))",
                        ['distinguishedName'], SUBTREE)
                    if entries:
                        self._access_ou = str(entries[0].entry_dn)
                except Exception:
                    self._access_ou = None
        return self._access_ou

    def list_groups(self, query=None):
        """List of groups (with substring filter). If an OU is set in
        ACCESS_GROUPS_OU_NAME the search is limited to it, otherwise the whole domain."""
        base = self.get_access_groups_dn() or self.base_dn
        query = (query or '').strip().replace('*', '')
        if query:
            q = _escape_filter(query)
            flt = ("(&(objectClass=group)"
                   f"(|(cn=*{q}*)(sAMAccountName=*{q}*)(description=*{q}*)))")
        else:
            flt = "(objectClass=group)"
        entries = self._paged_search(
            base, flt,
            ['cn', 'sAMAccountName', 'distinguishedName', 'description'], SUBTREE)
        groups = []
        for e in entries:
            dn = str(e.entry_dn)
            cn = dn.split(',', 1)[0]
            cn = cn[3:] if cn.lower().startswith('cn=') else cn
            desc = ''
            try:
                desc = e['description'].value or ''
            except Exception:
                pass
            groups.append({'cn': cn, 'dn': dn, 'description': desc})
        groups.sort(key=lambda g: g['cn'].lower())
        return groups

    # ---- Modifying operations ----
    def _check(self):
        r = self.conn.result
        if r['result'] != 0:
            raise RuntimeError(f"LDAP: {r.get('description')} — "
                               f"{r.get('message') or ''}".strip())

    def enable_account(self, dn):
        user = self.get_user(dn)
        new_uac = (user['uac'] & ~UAC_DISABLED) or UAC_NORMAL_ACCOUNT
        self.conn.modify(dn, {'userAccountControl': [(MODIFY_REPLACE, [new_uac])]})
        self._check()

    def disable_account(self, dn):
        user = self.get_user(dn)
        new_uac = user['uac'] | UAC_DISABLED
        self.conn.modify(dn, {'userAccountControl': [(MODIFY_REPLACE, [new_uac])]})
        self._check()

    def unlock_account(self, dn):
        # lockoutTime = 0 unlocks the account
        self.conn.modify(dn, {'lockoutTime': [(MODIFY_REPLACE, [0])]})
        self._check()

    def set_password_never_expires(self, dn, enable):
        """Set or clear the 'password never expires' flag (UAC bit 0x10000).

        Like the ADUC snap-in: enabling the flag also cancels a pending
        'must change password at next logon' requirement (pwdLastSet 0 -> -1),
        so the current password stays valid. Returns True if that
        requirement was cancelled as part of the change."""
        user = self.get_user(dn)
        if enable:
            new_uac = user['uac'] | UAC_DONT_EXPIRE_PASSWORD
        else:
            new_uac = user['uac'] & ~UAC_DONT_EXPIRE_PASSWORD
        if new_uac != user['uac']:
            self.conn.modify(dn, {'userAccountControl':
                                  [(MODIFY_REPLACE, [new_uac])]})
            self._check()
        cleared_must_change = False
        if enable:
            # Raw pwdLastSet == 0 means 'must change password at next logon'
            self.conn.search(dn, "(objectClass=user)", search_scope='BASE',
                             attributes=['pwdLastSet'])
            try:
                raw = self.conn.entries[0]['pwdLastSet'].raw_values
                is_zero = bool(raw) and raw[0].strip() == b'0'
            except Exception:
                is_zero = False
            if is_zero:
                # -1 = do not require a change (pwdLastSet := now)
                self.conn.modify(dn, {'pwdLastSet': [(MODIFY_REPLACE, [-1])]})
                self._check()
                cleared_must_change = True
        return cleared_must_change

    def reset_password(self, dn, new_password, unlock=True,
                       change_at_logon=True):
        if not self.is_ssl():
            raise RuntimeError(
                "Password reset requires a secure connection (LDAPS). "
                "Reconnect using LDAPS (port 636).")
        # Administrative password reset: replace unicodePwd
        pwd_val = ('"%s"' % new_password).encode('utf-16-le')
        self.conn.modify(dn, {'unicodePwd': [(MODIFY_REPLACE, [pwd_val])]})
        self._check()
        if unlock:
            self.conn.modify(dn, {'lockoutTime': [(MODIFY_REPLACE, [0])]})
            self._check()
        if change_at_logon:
            self.conn.modify(dn, {'pwdLastSet': [(MODIFY_REPLACE, [0])]})
            self._check()

    def move_user(self, dn, target_ou):
        rdn = dn.split(',', 1)[0]
        self.conn.modify_dn(dn, rdn, new_superior=target_ou)
        self._check()

    # ---- Computer operations ----
    def search_computers(self, query=None, base=None, scope=SUBTREE):
        """query — search text; base — container/OU DN; scope — LEVEL/SUBTREE.
        Returns all matching computer objects (paged, no limit)."""
        base = base or self.base_dn
        query = (query or '').strip().replace('*', '')
        if query:
            q = _escape_filter(query)
            flt = (
                "(&(objectCategory=computer)"
                f"(|(cn=*{q}*)(name=*{q}*)(sAMAccountName=*{q}*)"
                f"(dNSHostName=*{q}*)(operatingSystem=*{q}*)"
                f"(description=*{q}*)))"
            )
            scope = SUBTREE  # text search always spans the whole base subtree
        else:
            flt = "(objectCategory=computer)"

        entries = self._paged_search(base, flt, COMPUTER_ATTRS, scope)
        result = [self._computer_to_dict(e) for e in entries]
        result.sort(key=lambda x: (x.get('name') or '').lower())
        return result

    def get_computer(self, dn):
        self.conn.search(dn, "(objectClass=computer)", search_scope='BASE',
                         attributes=COMPUTER_ATTRS)
        if not self.conn.entries:
            return None
        return self._computer_to_dict(self.conn.entries[0])

    def _computer_to_dict(self, e):
        def v(attr, default=''):
            try:
                val = e[attr].value
                return val if val is not None else default
            except Exception:
                return default

        uac = v('userAccountControl', 0) or 0
        try:
            uac = int(uac)
        except (ValueError, TypeError):
            uac = 0
        enabled = not (uac & UAC_DISABLED)
        state = "Active" if enabled else "Disabled"

        name = v('name') or v('cn') or str(e.entry_dn).split(',')[0][3:]
        os_name = v('operatingSystem')
        os_ver = v('operatingSystemVersion')
        os_full = (f"{os_name} ({os_ver})" if os_name and os_ver
                   else os_name or os_ver)
        return {
            'name': name,
            'cn': v('cn') or name,
            'sAMAccountName': v('sAMAccountName'),
            'dnsHostName': v('dNSHostName'),
            'os': os_name,
            'osVersion': os_ver,
            'osFull': os_full,
            'description': v('description'),
            'enabled': enabled,
            'state': state,
            'dn': str(e.entry_dn),
            'whenCreated': v('whenCreated'),
            'lastLogon': v('lastLogonTimestamp'),
            'uac': uac,
            'is_computer': True,
        }

    def rename_object(self, dn, new_name):
        """Rename an object (change its CN/RDN) within the same container."""
        new_rdn = "CN=" + _escape_dn((new_name or '').strip())
        self.conn.modify_dn(dn, new_rdn)
        self._check()
        # Return the resulting DN
        parent = dn.split(',', 1)[1] if ',' in dn else ''
        return f"{new_rdn},{parent}" if parent else new_rdn

    def delete_object(self, dn):
        """Delete an object from the directory."""
        self.conn.delete(dn)
        self._check()

    def add_to_group(self, user_dn, group_name):
        gdn = self.find_group_dn(group_name)
        if not gdn:
            raise RuntimeError(f"Group '{group_name}' not found.")
        self.conn.modify(gdn, {'member': [(MODIFY_ADD, [user_dn])]})
        self._check()

    def remove_from_group(self, user_dn, group_dn):
        self.conn.modify(group_dn, {'member': [(MODIFY_DELETE, [user_dn])]})
        self._check()

    def update_attributes(self, dn, attrs):
        """attrs: dict ldap_name -> value (empty string = delete)."""
        changes = {}
        for k, val in attrs.items():
            val = (val or '').strip()
            if val:
                changes[k] = [(MODIFY_REPLACE, [val])]
            else:
                changes[k] = [(MODIFY_REPLACE, [])]
        if changes:
            self.conn.modify(dn, changes)
            self._check()

    def user_exists(self, sam):
        """Check whether a user with this login (sAMAccountName) already exists."""
        q = _escape_filter((sam or '').strip())
        if not q:
            return False
        self.conn.search(
            self.base_dn, f"(&(objectClass=user)(sAMAccountName={q}))",
            search_scope=SUBTREE, attributes=['distinguishedName'])
        return bool(self.conn.entries)

    def create_user(self, ou, cn, sam, upn, display, given, sn, mail,
                    password, enabled=True, change_at_logon=True,
                    description=None, expire_date=None):
        if not ou:
            ou = "CN=Users," + self.base_dn
        dn = f"CN={_escape_dn(cn)},{ou}"
        attrs = {
            'objectClass': ['top', 'person', 'organizationalPerson', 'user'],
            'sAMAccountName': sam,
            'userAccountControl': UAC_NORMAL_ACCOUNT | UAC_DISABLED,  # disabled at first
        }
        if upn:
            attrs['userPrincipalName'] = upn
        if display:
            attrs['displayName'] = display
        if given:
            attrs['givenName'] = given
        if sn:
            attrs['sn'] = sn
        if mail:
            attrs['mail'] = mail
        if description:
            attrs['description'] = description
        if expire_date is not None:
            # Valid THROUGH the given date inclusive => expires at the start
            # of the next day. accountExpires is stored as a filetime (100ns since 1601).
            dt = datetime.datetime(expire_date.year, expire_date.month,
                                   expire_date.day) + datetime.timedelta(days=1)
            attrs['accountExpires'] = _datetime_to_filetime(dt)

        self.conn.add(dn, attributes=attrs)
        self._check()

        # Set the password (LDAPS required)
        if password:
            if not self.is_ssl():
                raise RuntimeError(
                    "User created, but the password cannot be set without LDAPS. "
                    "Reconnect using LDAPS to set the password.")
            pwd_val = ('"%s"' % password).encode('utf-16-le')
            self.conn.modify(dn, {'unicodePwd': [(MODIFY_REPLACE, [pwd_val])]})
            self._check()

        # Enable the account
        if enabled and password:
            self.conn.modify(dn, {'userAccountControl':
                                  [(MODIFY_REPLACE, [UAC_NORMAL_ACCOUNT])]})
            self._check()

        # Change password at next logon (0 = require change, -1 = do not require)
        if password:
            pls = 0 if change_at_logon else -1
            self.conn.modify(dn, {'pwdLastSet': [(MODIFY_REPLACE, [pls])]})
            self._check()

        return dn


def _escape_filter(s):
    """Escape special characters in an LDAP filter (RFC 4515)."""
    out = []
    for ch in s:
        if ch == '*':
            out.append('\\2a')
        elif ch == '(':
            out.append('\\28')
        elif ch == ')':
            out.append('\\29')
        elif ch == '\\':
            out.append('\\5c')
        elif ch == '\x00':
            out.append('\\00')
        else:
            out.append(ch)
    return ''.join(out)


def _escape_dn(s):
    """Escape special characters in a DN component."""
    for ch in ['\\', ',', '+', '"', '<', '>', ';', '=']:
        s = s.replace(ch, '\\' + ch)
    return s


# Lowercase English month abbreviations for the YYYY-mmm-DD date format.
MONTH_ABBR = ['jan', 'feb', 'mar', 'apr', 'may', 'jun',
              'jul', 'aug', 'sep', 'oct', 'nov', 'dec']
DATE_HINT = "YYYY-MMM-DD"


def fmt_date(dt, with_time=True):
    """Format a date/datetime as YYYY-mmm-DD (e.g. 2026-aug-14)."""
    s = f"{dt.year:04d}-{MONTH_ABBR[dt.month - 1]}-{dt.day:02d}"
    if with_time and isinstance(dt, datetime.datetime):
        s += f" {dt.hour:02d}:{dt.minute:02d}"
    return s


def parse_date(txt):
    """Parse a YYYY-mmm-DD (or YYYY-MM-DD) string into a datetime.date."""
    parts = txt.strip().lower().split('-')
    if len(parts) != 3:
        raise ValueError("bad date")
    year = int(parts[0])
    mon_part = parts[1]
    if mon_part.isdigit():
        month = int(mon_part)
    else:
        month = MONTH_ABBR.index(mon_part[:3]) + 1
    day = int(parts[2])
    return datetime.date(year, month, day)


def filetime_to_str(val):
    """Convert AD time (100ns since 1601 or generalizedTime) to a string."""
    if val is None or val == '':
        return ''
    if isinstance(val, datetime.datetime):
        return fmt_date(val)
    try:
        num = int(val)
    except (ValueError, TypeError):
        return str(val)
    if num == 0:
        return 'never / not set'
    if num >= 0x7FFFFFFFFFFFFFFF:
        return 'never'
    try:
        secs = num / 10_000_000 - 11644473600
        return fmt_date(datetime.datetime.fromtimestamp(secs))
    except (ValueError, OverflowError, OSError):
        return str(val)


def _datetime_to_filetime(dt):
    """datetime -> AD filetime (100ns since 1601-01-01)."""
    epoch = datetime.datetime(1601, 1, 1)
    return int((dt - epoch).total_seconds() * 10_000_000)


def pwd_expiry_text(u):
    """When the password must be changed."""
    pls = u.get('pwdLastSet')
    try:
        pls_i = int(pls)
    except (TypeError, ValueError):
        pls_i = None
    if pls_i == 0:
        return "at next logon (change required)"
    if u.get('dontExpire'):
        return "never (password does not expire)"
    exp = u.get('pwdExpiry')
    try:
        n = int(exp)
    except (TypeError, ValueError):
        return ''
    if n == 0:
        return ''
    if n >= 0x7FFFFFFFFFFFFFFF:
        return "never"
    txt = filetime_to_str(n)
    # Mark if the date has already passed
    try:
        secs = n / 10_000_000 - 11644473600
        if datetime.datetime.fromtimestamp(secs) < datetime.datetime.now():
            txt += " (expired)"
    except (ValueError, OverflowError, OSError):
        pass
    return txt


# ============================================================================
#  GUI
# ============================================================================
def set_clipboard(root, text):
    """Put text on the system clipboard. On macOS use pbcopy (reliable with
    Tk 9, where Tk's own clipboard path is broken); elsewhere use Tk."""
    text = '' if text is None else str(text)
    if sys.platform == 'darwin':
        try:
            subprocess.run(['pbcopy'], input=text.encode('utf-8'), check=True)
            return True
        except Exception:
            pass
    try:
        root.clipboard_clear()
        root.clipboard_append(text)
        root.update()
        return True
    except Exception:
        return False


class LoginDialog(tk.Toplevel):
    """Credentials dialog with saved-domain selection."""

    def __init__(self, master, client, config=None, preselect=None):
        super().__init__(master)
        self.client = client
        self.config = config
        self.success = False
        self.title("Connect to Active Directory")
        self.resizable(False, False)
        self.grab_set()

        frm = ttk.Frame(self, padding=18)
        frm.grid()

        ttk.Label(frm, text="Connect to the Active Directory domain",
                  font=('', 13, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 12))

        # Saved-domain selection
        ttk.Label(frm, text="Saved domain:").grid(row=1, column=0,
                                                       sticky='w', pady=4)
        dom_row = ttk.Frame(frm)
        dom_row.grid(row=1, column=1, sticky='ew', pady=4)
        self.cmb_domain = ttk.Combobox(dom_row, width=27, state='readonly')
        self.cmb_domain.grid(row=0, column=0)
        self.cmb_domain.bind('<<ComboboxSelected>>', self._on_pick)
        ttk.Button(dom_row, text="✕", width=3,
                   command=self._delete_profile).grid(row=0, column=1, padx=(4, 0))

        ttk.Label(frm, text="Server / DC:").grid(row=2, column=0, sticky='w', pady=4)
        self.e_host = ttk.Entry(frm, width=34)
        self.e_host.grid(row=2, column=1, pady=4)

        ttk.Label(frm, text="User:").grid(row=3, column=0, sticky='w', pady=4)
        self.e_user = ttk.Entry(frm, width=34)
        self.e_user.grid(row=3, column=1, pady=4)

        ttk.Label(frm, text="Password:").grid(row=4, column=0, sticky='w', pady=4)
        self.e_pass = ttk.Entry(frm, width=34, show='•')
        self.e_pass.grid(row=4, column=1, pady=4)

        self.use_ssl = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="LDAPS (encryption, port 636)",
                        variable=self.use_ssl).grid(
            row=5, column=1, sticky='w', pady=(8, 0))

        self.verify = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm, text="Validate server certificate",
                        variable=self.verify).grid(
            row=6, column=1, sticky='w')

        self.save_domain = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="Save domain to the list",
                        variable=self.save_domain).grid(
            row=7, column=1, sticky='w')

        self.lbl_status = ttk.Label(frm, text="", foreground='#B00020',
                                    wraplength=340)
        self.lbl_status.grid(row=8, column=0, columnspan=2, sticky='w',
                             pady=(10, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=9, column=0, columnspan=2, sticky='e', pady=(14, 0))
        ttk.Button(btns, text="Connect",
                   command=self._connect).grid(row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel",
                   command=self._cancel).grid(row=0, column=1)

        # Load the domain list
        self._profiles = self.config.load() if self.config else []
        self._refresh_combo(preselect)

        self.e_pass.bind('<Return>', lambda e: self._connect())
        self.protocol("WM_DELETE_WINDOW", self._cancel)

    def _profile_label(self, d):
        return d.get('name') or d.get('host') or ''

    def _refresh_combo(self, preselect=None):
        names = [self._profile_label(d) for d in self._profiles]
        self.cmb_domain['values'] = names
        picked = None
        if preselect and preselect in names:
            self.cmb_domain.current(names.index(preselect))
            picked = self._profiles[names.index(preselect)]
        if picked:
            self._fill_from_profile(picked)
        elif not self._profiles:
            # first connection — hints
            if not self.e_host.get():
                self.e_host.insert(0, "dc01.example.local")
            if not self.e_user.get():
                self.e_user.insert(0, "user@example.local")
            self.e_host.focus_set()

    def _fill_from_profile(self, d):
        self.e_host.delete(0, 'end'); self.e_host.insert(0, d.get('host', ''))
        self.e_user.delete(0, 'end'); self.e_user.insert(0, d.get('username', ''))
        self.use_ssl.set(d.get('use_ssl', True))
        self.verify.set(d.get('verify', False))
        self.e_pass.delete(0, 'end')
        self.e_pass.focus_set()

    def _on_pick(self, event=None):
        i = self.cmb_domain.current()
        if 0 <= i < len(self._profiles):
            self._fill_from_profile(self._profiles[i])

    def _delete_profile(self):
        i = self.cmb_domain.current()
        if not (self.config and 0 <= i < len(self._profiles)):
            return
        d = self._profiles[i]
        if not messagebox.askyesno(
                "Remove domain",
                f"Remove '{self._profile_label(d)}' from the list?"):
            return
        self._profiles = self.config.remove(d.get('host'))
        self.cmb_domain.set('')
        self._refresh_combo()

    def _connect(self):
        host = self.e_host.get().strip()
        user = self.e_user.get().strip()
        pwd = self.e_pass.get()
        if not host or not user or not pwd:
            self.lbl_status.config(text="Fill in server, user, and password.")
            return
        self.lbl_status.config(text="Connecting...")
        self.update_idletasks()
        try:
            self.client.connect(
                host, user, pwd,
                use_ssl=self.use_ssl.get(),
                verify_cert=self.verify.get())
            if self.config and self.save_domain.get():
                self.config.upsert({
                    'name': host,
                    'host': host,
                    'username': user,
                    'use_ssl': self.use_ssl.get(),
                    'verify': self.verify.get(),
                })
            self.success = True
            self.destroy()
        except LDAPException as ex:
            self.lbl_status.config(text=f"Failed to connect: {ex}")
        except Exception as ex:
            self.lbl_status.config(text=f"Error: {ex}")

    def _cancel(self):
        self.success = False
        self.destroy()


class MainWindow(ttk.Frame):
    """Main application window."""

    def __init__(self, master, client, config=None):
        super().__init__(master, padding=0)
        self.client = client
        self.config = config
        self.users = []
        self.grid(sticky='nsew')
        master.columnconfigure(0, weight=1)
        master.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        self._build_toolbar()
        self._build_body()
        self._build_statusbar()
        # Global copy shortcut (works even where Tk's own <<Copy>> is broken)
        for seq in ('<Command-Key-c>', '<Command-Key-C>',
                    '<Control-Key-c>', '<Control-Key-C>'):
            self.master.bind_all(seq, self._on_copy_shortcut, add='+')

        self.after(150, self._post_login)

    def _post_login(self):
        self._load_ou_tree()
        self.do_search()

    # --- Search bar ---
    def _build_toolbar(self):
        bar = ttk.Frame(self, padding=8)
        bar.grid(row=0, column=0, sticky='ew')
        bar.columnconfigure(5, weight=1)  # spacer between search and domain
        ttk.Label(bar, text="Search:").grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(bar, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self.do_search())
        ttk.Button(bar, text="Find", command=self.do_search).grid(
            row=0, column=2, padx=6)
        ttk.Button(bar, text="Refresh", command=self.do_search).grid(
            row=0, column=3)
        self.btn_create = ttk.Button(bar, text="Create user",
                                     command=self.on_create)
        self.btn_create.grid(row=0, column=4, padx=(20, 0))

        # Domain switcher (right)
        ttk.Label(bar, text="Domain:").grid(row=0, column=6, padx=(0, 6))
        self.cmb_dom = ttk.Combobox(bar, width=24)  # editable: a new one can be typed
        self.cmb_dom.grid(row=0, column=7)
        self.cmb_dom.bind('<Return>', lambda e: self.on_switch_domain())
        ttk.Button(bar, text="Switch domain",
                   command=self.on_switch_domain).grid(row=0, column=8, padx=(6, 0))
        self._domain_profiles = []
        self._reload_domains()

        # Object type: users / computers
        self.mode_var = tk.StringVar(value='users')
        mode_row = ttk.Frame(bar)
        mode_row.grid(row=1, column=0, columnspan=5, sticky='w', pady=(6, 0))
        ttk.Label(mode_row, text="Show:").grid(row=0, column=0, padx=(0, 6))
        ttk.Radiobutton(mode_row, text="Users", value='users',
                        variable=self.mode_var,
                        command=self.on_mode_change).grid(row=0, column=1)
        ttk.Radiobutton(mode_row, text="Computers", value='computers',
                        variable=self.mode_var,
                        command=self.on_mode_change).grid(row=0, column=2,
                                                          padx=(8, 0))

        # Nested OUs
        self.include_subtree = tk.BooleanVar(value=False)
        self.chk_subtree = ttk.Checkbutton(
            bar, text="Show from nested OUs",
            variable=self.include_subtree,
            command=self.do_search)
        self.chk_subtree.grid(row=2, column=0, columnspan=5,
                              sticky='w', pady=(6, 0))

    def _reload_domains(self):
        profiles = self.config.load() if self.config else []
        self._domain_profiles = profiles
        names = [d.get('name') or d.get('host') for d in profiles]
        self.cmb_dom['values'] = names
        cur = self.client.host
        if cur in names:
            self.cmb_dom.current(names.index(cur))
        elif names:
            self.cmb_dom.set(cur or '')

    def on_switch_domain(self):
        host = self.cmb_dom.get().strip()
        if not host:
            messagebox.showinfo("No domain selected",
                                "Select from the list or enter a domain/controller.")
            return
        if host.lower() == (self.client.host or '').lower():
            return  # same domain — nothing to do

        # Connection parameters from the saved profile (if any)
        profiles = self.config.load() if self.config else []
        prof = next((d for d in profiles
                     if (d.get('name') or d.get('host')) == host
                     or d.get('host') == host), None)
        use_ssl = prof.get('use_ssl', self.client._use_ssl) if prof else self.client._use_ssl
        verify = prof.get('verify', self.client._verify) if prof else self.client._verify

        self.master.config(cursor='watch')
        self.update_idletasks()
        try:
            # Switch domain using the active session credentials
            self.client.switch_server(host, use_ssl=use_ssl, verify_cert=verify)
        except Exception as ex:
            self.master.config(cursor='')
            messagebox.showerror(
                "Access error",
                f"Failed to connect to domain \"{host}\" with the current "
                f"account ({self.client.username}).\n\n"
                f"Insufficient rights or the domain is unavailable:\n{ex}")
            return
        finally:
            self.master.config(cursor='')

        # Save the domain under the current user
        if self.config:
            self.config.upsert({
                'name': host, 'host': host, 'username': self.client.username,
                'use_ssl': use_ssl, 'verify': verify,
            })
        self._reload_domains()
        self.e_search.delete(0, 'end')
        self.props.delete('1.0', 'end')
        self._load_ou_tree()
        self.do_search()
        messagebox.showinfo(
            "Domain changed",
            f"Connected to domain \"{self.client.host}\" as "
            f"{self.client.username}.")

    # --- Main area ---
    def _build_body(self):
        body = ttk.Panedwindow(self, orient='horizontal')
        body.grid(row=1, column=0, sticky='nsew', padx=8, pady=(0, 8))

        # Organizational unit (OU) tree — like the ADUC snap-in
        ou_frame = ttk.Frame(body)
        ou_frame.rowconfigure(1, weight=1)
        ou_frame.columnconfigure(0, weight=1)
        ttk.Label(ou_frame, text="Organizational units").grid(
            row=0, column=0, sticky='w', pady=(0, 4))
        self.ou_tree = ttk.Treeview(ou_frame, show='tree', selectmode='browse')
        self.ou_tree.grid(row=1, column=0, sticky='nsew')
        ou_sb = ttk.Scrollbar(ou_frame, orient='vertical',
                              command=self.ou_tree.yview)
        ou_sb.grid(row=1, column=1, sticky='ns')
        self.ou_tree.configure(yscrollcommand=ou_sb.set)
        self.ou_tree.bind('<<TreeviewSelect>>', self.on_ou_select)
        self._ou_dn_by_item = {}
        self._item_by_dn = {}
        self._loading_tree = False
        body.add(ou_frame, weight=2)

        # User list
        left = ttk.Frame(body)
        left.rowconfigure(0, weight=1)
        left.columnconfigure(0, weight=1)
        self.tree = ttk.Treeview(left, show='headings', selectmode='extended')
        self._apply_columns()
        self.tree.grid(row=0, column=0, sticky='nsew')
        sb = ttk.Scrollbar(left, orient='vertical', command=self.tree.yview)
        sb.grid(row=0, column=1, sticky='ns')
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.bind('<<TreeviewSelect>>', self.on_select)
        # Context menu on the user list (right-click / Ctrl-click on macOS)
        self.tree.bind('<Button-2>', self._show_user_menu)
        self.tree.bind('<Button-3>', self._show_user_menu)
        self.tree.bind('<Control-Button-1>', self._show_user_menu)
        # Cmd+C / Ctrl+C on the list copies the selected user's row
        for seq in ('<<Copy>>', '<Command-Key-c>', '<Command-Key-C>',
                    '<Control-Key-c>', '<Control-Key-C>'):
            self.tree.bind(seq, lambda e: self._copy_selected_row())
        # Double-click opens the edit dialog (users and computers alike)
        self.tree.bind('<Double-1>', self._on_tree_double)
        body.add(left, weight=3)

        # Right panel: properties + actions
        right = ttk.Frame(body)
        right.rowconfigure(0, weight=1)
        right.columnconfigure(0, weight=1)

        self.prop_group = prop_group = ttk.LabelFrame(right,
                                                      text="User properties")
        prop_group.grid(row=0, column=0, sticky='nsew')
        prop_group.rowconfigure(0, weight=1)
        prop_group.columnconfigure(0, weight=1)
        # Enabled (not 'disabled') so it can take keyboard focus and native
        # Cmd+C/Ctrl+C works; editing is blocked by _block_edit below.
        self.props = tk.Text(prop_group, width=44, height=18, wrap='word',
                             relief='flat', font=('Menlo', 11),
                             insertwidth=0, exportselection=True)
        self.props.grid(row=0, column=0, sticky='nsew', padx=4, pady=4)
        # Block any text modification (keeps selection/copy working)
        self.props.bind('<Key>', self._block_edit)
        self.props.bind('<<Paste>>', lambda e: 'break')
        self.props.bind('<<Cut>>', lambda e: 'break')
        self.props.bind('<Delete>', lambda e: 'break')
        self.props.bind('<BackSpace>', lambda e: 'break')
        # Context menu on the properties panel
        self.props.bind('<Button-2>', self._show_props_menu)
        self.props.bind('<Button-3>', self._show_props_menu)
        self.props.bind('<Control-Button-1>', self._show_props_menu)
        # Give the widget keyboard focus on click so shortcuts reach it
        self.props.bind('<Button-1>', lambda e: self.props.focus_set())
        # Auto-copy on mouse selection: releasing the button after dragging
        # copies the selected text (works even if Cmd+C never reaches us).
        self.props.bind('<ButtonRelease-1>', self._props_autocopy)

        self.act_group = ttk.LabelFrame(right, text="Actions")
        self.act_group.grid(row=1, column=0, sticky='ew', pady=(8, 0))
        self._build_actions()
        body.add(right, weight=2)

    def _apply_columns(self):
        """Configure list columns for the current mode (users/computers)."""
        if getattr(self, 'mode_var', None) and self.mode_var.get() == 'computers':
            spec = [
                ('name', 'Name', 190),
                ('dns', 'DNS name', 200),
                ('os', 'Operating system', 190),
                ('desc', 'Description', 150),
                ('state', 'State', 90),
            ]
        else:
            spec = [
                ('name', 'Name', 200),
                ('sam', 'Login', 130),
                ('mail', 'E-mail', 200),
                ('desc', 'Description', 180),
                ('state', 'State', 100),
            ]
        cols = tuple(c[0] for c in spec)
        self.tree.configure(columns=cols)
        for key, title, width in spec:
            self.tree.heading(key, text=title)
            self.tree.column(key, width=width)

    def _build_actions(self):
        """(Re)build the action buttons for the current mode."""
        for w in self.act_group.winfo_children():
            w.destroy()
        if self.mode_var.get() == 'computers':
            actions = [
                ("Enable", self.on_enable),
                ("Disable", self.on_disable),
                ("Rename...", self.on_rename),
                ("Move (OU)", self.on_move),
                ("Edit...", self.on_edit),
                ("Delete", self.on_delete),
            ]
        else:
            actions = [
                ("Enable", self.on_enable),
                ("Disable", self.on_disable),
                ("Unlock", self.on_unlock),
                ("Reset password", self.on_reset),
                ("Pwd never expires", self.on_pwd_never_expires),
                ("Groups...", self.on_groups),
                ("Move (OU)", self.on_move),
                ("Edit...", self.on_edit),
            ]
        for i, (label, cmd) in enumerate(actions):
            ttk.Button(self.act_group, text=label, command=cmd, width=18).grid(
                row=i // 2, column=i % 2, padx=4, pady=4, sticky='ew')

    def on_mode_change(self):
        """Switch between users and computers."""
        computers = self.mode_var.get() == 'computers'
        self.e_search.delete(0, 'end')
        self.props.delete('1.0', 'end')
        self._prop_rows = []
        self._apply_columns()
        self._build_actions()
        self.prop_group.config(
            text="Computer properties" if computers else "User properties")
        self.chk_subtree.config(
            text="Show from nested OUs")
        if computers:
            self.btn_create.grid_remove()
        else:
            self.btn_create.grid()
        self.do_search()

    def _build_statusbar(self):
        self.status = ttk.Label(self, text="", padding=(8, 4),
                                relief='sunken', anchor='w')
        self.status.grid(row=2, column=0, sticky='ew')
        self._update_status()

    def _update_status(self, extra=''):
        proto = "LDAPS" if self.client.is_ssl() else "LDAP"
        base = (f"Connected: {self.client.host} ({proto})   |   "
                f"Base: {self.client.base_dn}")
        self.status.config(text=base + ('   |   ' + extra if extra else ''))

    # --- Organizational unit tree ---
    def _load_ou_tree(self):
        self._loading_tree = True
        self.ou_tree.delete(*self.ou_tree.get_children())
        self._ou_dn_by_item = {}
        self._item_by_dn = {}
        root_label = self.client.upn_suffix or self.client.base_dn
        root = self.ou_tree.insert('', 'end', text=root_label, open=True)
        self._ou_dn_by_item[root] = self.client.base_dn
        self._item_by_dn[self.client.base_dn.lower()] = root
        try:
            nodes = self.client.list_tree_nodes()
        except Exception:
            nodes = []
        for dn in nodes:
            parent_dn = dn.split(',', 1)[1] if ',' in dn else ''
            parent_item = self._item_by_dn.get(parent_dn.lower(), root)
            rdn = dn.split(',', 1)[0]
            label = rdn.split('=', 1)[1] if '=' in rdn else rdn
            item = self.ou_tree.insert(parent_item, 'end', text=label)
            self._ou_dn_by_item[item] = dn
            self._item_by_dn[dn.lower()] = item
        self.ou_tree.selection_set(root)
        self._loading_tree = False

    def _current_base(self):
        sel = self.ou_tree.selection()
        if sel and sel[0] in self._ou_dn_by_item:
            return self._ou_dn_by_item[sel[0]]
        return self.client.base_dn

    def _short_dn(self, dn):
        if not dn or dn.lower() == self.client.base_dn.lower():
            return self.client.upn_suffix or 'domain'
        parts = []
        for comp in dn.split(','):
            low = comp.lower()
            if low.startswith(('ou=', 'cn=')):
                parts.append(comp.split('=', 1)[1])
            elif low.startswith('dc='):
                break
        return ' / '.join(reversed(parts)) if parts else dn

    def on_ou_select(self, event=None):
        if getattr(self, '_loading_tree', False):
            return
        self.do_search()

    # --- Search ---
    def do_search(self):
        self.master.config(cursor='watch')
        self.update_idletasks()
        try:
            base = self._current_base()
            text = self.e_search.get().strip()
            subtree = bool(text) or self.include_subtree.get()
            scope = SUBTREE if subtree else LEVEL
            computers = self.mode_var.get() == 'computers'
            if computers:
                self.users = self.client.search_computers(
                    query=text, base=base, scope=scope)
            else:
                self.users = self.client.search_users(
                    query=text, base=base, scope=scope)
            self.tree.delete(*self.tree.get_children())
            for i, u in enumerate(self.users):
                if computers:
                    vals = (u['name'], u.get('dnsHostName', ''),
                            u.get('osFull', ''), u['description'], u['state'])
                else:
                    vals = (u['name'], u['sAMAccountName'], u['mail'],
                            u['description'], u['state'])
                self.tree.insert('', 'end', iid=str(i), values=vals)
            scope_txt = self._short_dn(base)
            if subtree:
                scope_txt += " (+nested)"
            self._update_status(
                f"Found: {len(self.users)}  |  scope: {scope_txt}")
        except Exception as ex:
            messagebox.showerror("Search error", str(ex))
        finally:
            self.master.config(cursor='')

    def _selected_users(self):
        """All selected objects (multi-select aware)."""
        return [self.users[int(i)] for i in self.tree.selection()]

    def _selected_user(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("No user selected",
                                "Select a user in the list first.")
            return None
        if len(sel) > 1:
            messagebox.showinfo(
                "Multiple objects selected",
                "This action applies to a single object.\n"
                "Select exactly one item in the list.")
            return None
        return self.users[int(sel[0])]

    def on_select(self, event=None):
        sel = self.tree.selection()
        if not sel:
            return
        if len(sel) > 1:
            self.props.delete('1.0', 'end')
            self.props.insert(
                'end',
                f"Selected objects: {len(sel)}\n\n"
                f"Available bulk actions:\n"
                f"  Enable / Disable / Move (OU)\n"
                f"  Add to groups (users)")
            return
        u = self.users[int(sel[0])]
        if u.get('is_computer'):
            self._show_computer_props(u)
        else:
            self._show_props(u)

    def _refresh_selected(self, dn):
        if self.mode_var.get() == 'computers':
            # Computer list uses different columns; re-run the search and
            # keep the same row selected if it is still present.
            self.do_search()
            for iid in self.tree.get_children():
                if self.users[int(iid)]['dn'].lower() == dn.lower():
                    self.tree.selection_set(iid)
                    self.tree.focus(iid)
                    self.on_select()
                    break
            return
        try:
            fresh = self.client.get_user(dn)
            if fresh:
                sel = self.tree.selection()
                if sel:
                    idx = int(sel[0])
                    self.users[idx] = fresh
                    self.tree.item(sel[0], values=(
                        fresh['name'], fresh['sAMAccountName'],
                        fresh['mail'], fresh['description'], fresh['state']))
                self._show_props(fresh)
        except Exception:
            pass

    def _show_props(self, u):
        rows = [
            ("Display name", u['displayName']),
            ("Login", u['sAMAccountName']),
            ("UPN", u['userPrincipalName']),
            ("First name", u['givenName']),
            ("Last name", u['sn']),
            ("E-mail", u['mail']),
            ("State", u['state']),
            ("Locked", "Yes" if u['locked'] else "No"),
            ("Description", u['description']),
            ("Title", u['title']),
            ("Department", u['department']),
            ("Company", u['company']),
            ("Office", u['office']),
            ("Phone", u['phone']),
            ("Password last set", filetime_to_str(u['pwdLastSet'])),
            ("Password never expires", "Yes" if u.get('dontExpire') else "No"),
            ("Password change required", pwd_expiry_text(u)),
            ("Bad password attempts",
             '' if u.get('badPwdCount') in (None, '') else str(u.get('badPwdCount'))),
            ("Last bad password", filetime_to_str(u.get('badPwdTime'))),
            ("Last logon", filetime_to_str(u['lastLogon'])),
            ("Created", filetime_to_str(u['whenCreated'])),
            ("Expires", filetime_to_str(u['accountExpires'])),
            ("DN", u['dn']),
        ]
        self._prop_rows = [(k, v) for k, v in rows if v not in (None, '')]
        self.props.delete('1.0', 'end')
        for k, val in self._prop_rows:
            self.props.insert('end', f"{k}:\n", ('label',))
            self.props.insert('end', f"{val}\n\n")
        self.props.tag_config('label', foreground='#555',
                              font=('Menlo', 10, 'bold'))

    def _show_computer_props(self, c):
        rows = [
            ("Name", c['name']),
            ("Account name", c['sAMAccountName']),
            ("DNS name", c['dnsHostName']),
            ("Operating system", c['os']),
            ("OS version", c['osVersion']),
            ("State", c['state']),
            ("Description", c['description']),
            ("Last logon", filetime_to_str(c['lastLogon'])),
            ("Created", filetime_to_str(c['whenCreated'])),
            ("DN", c['dn']),
        ]
        self._prop_rows = [(k, v) for k, v in rows if v not in (None, '')]
        self.props.delete('1.0', 'end')
        for k, val in self._prop_rows:
            self.props.insert('end', f"{k}:\n", ('label',))
            self.props.insert('end', f"{val}\n\n")
        self.props.tag_config('label', foreground='#555',
                              font=('Menlo', 10, 'bold'))

    # --- Clipboard / context menus ---
    def _copy_text(self, text):
        if text is None:
            return
        set_clipboard(self.master, str(text))
        self._update_status("Copied to clipboard")

    def _on_copy_shortcut(self, event=None):
        """Application-wide Cmd+C / Ctrl+C: copy from whichever widget has focus.
        Bypasses Tk's built-in <<Copy>> (broken on macOS with Tk 9)."""
        try:
            w = self.master.focus_get()
        except Exception:
            w = None
        if w is self.props:
            return self._copy_props_selection()
        if w is self.tree:
            return self._copy_selected_row()
        # Any Entry-like widget: copy its selection natively
        try:
            if w is not None and w.selection_present():
                self._copy_text(w.selection_get())
                return 'break'
        except Exception:
            pass
        return None

    def _on_select_all(self, event=None):
        """Select all text in the focused widget (properties panel or entry)."""
        try:
            w = self.master.focus_get()
        except Exception:
            w = None
        if w is self.props:
            self.props.tag_add('sel', '1.0', 'end-1c')
            return 'break'
        try:
            if w is not None:
                w.select_range(0, 'end')
                return 'break'
        except Exception:
            pass
        return None

    def _props_autocopy(self, event=None):
        """Copy the current mouse selection in the properties panel, if any."""
        try:
            rng = self.props.tag_ranges('sel')
            if rng:
                txt = self.props.get(rng[0], rng[1])
                if txt.strip():
                    self._copy_text(txt)
        except tk.TclError:
            pass
        return None

    def _block_edit(self, event):
        """Allow navigation/selection/copy keys, block anything that edits text."""
        # Let Cmd/Ctrl combos (copy, select-all) and pure modifiers through
        if event.state & 0x8 or event.state & 0x4:   # Command (macOS) / Control
            return None
        nav = {'Left', 'Right', 'Up', 'Down', 'Home', 'End', 'Prior', 'Next',
               'Shift_L', 'Shift_R', 'Control_L', 'Control_R', 'Meta_L', 'Meta_R',
               'Alt_L', 'Alt_R', 'Escape', 'Tab', 'Caps_Lock'}
        if event.keysym in nav:
            return None
        return 'break'

    def _copy_props_selection(self, event=None):
        sel = ''
        try:
            rng = self.props.tag_ranges('sel')
            if rng:
                sel = self.props.get(rng[0], rng[1])
        except tk.TclError:
            sel = ''
        if sel:
            self._copy_text(sel)
        return 'break'

    def _copy_all_props(self):
        rows = getattr(self, '_prop_rows', [])
        if rows:
            self._copy_text("\n".join(f"{k}: {v}" for k, v in rows))

    def _copy_selected_row(self):
        """Copy the selected list rows (tab-separated, one per line)."""
        sel = self.tree.selection()
        if not sel:
            return 'break'
        lines = []
        for iid in sel:
            u = self.users[int(iid)]
            if u.get('is_computer'):
                fields = (u['name'], u.get('dnsHostName', ''),
                          u.get('osFull', ''), u['description'], u['state'])
            else:
                fields = (u['name'], u['sAMAccountName'], u['mail'],
                          u['description'], u['state'])
            lines.append("\t".join(str(x or '') for x in fields))
        self._copy_text("\n".join(lines))
        return 'break'

    def _show_user_menu(self, event):
        # Select the row under the cursor, keeping an existing multi-selection
        # if the click lands inside it
        iid = self.tree.identify_row(event.y)
        if iid and iid not in self.tree.selection():
            self.tree.selection_set(iid)
            self.tree.focus(iid)
        sel = self.tree.selection()
        if not sel:
            return 'break'
        if len(sel) > 1:
            m = tk.Menu(self, tearoff=0)
            m.add_command(label=f"Selected: {len(sel)}", state='disabled')
            m.add_separator()
            m.add_command(label="Enable", command=self.on_enable)
            m.add_command(label="Disable", command=self.on_disable)
            m.add_command(label="Move (OU)...", command=self.on_move)
            if self.mode_var.get() != 'computers':
                m.add_command(label="Add to groups...",
                              command=self.on_groups)
            m.add_separator()
            m.add_command(label="Copy rows",
                          command=self._copy_selected_row)
            try:
                m.tk_popup(event.x_root, event.y_root)
            finally:
                m.grab_release()
            return 'break'
        u = self.users[int(sel[0])]

        if u.get('is_computer'):
            return self._show_computer_menu(event, u)

        m = tk.Menu(self, tearoff=0)
        m.add_command(label="Copy login",
                      command=lambda: self._copy_text(u['sAMAccountName']))
        m.add_command(label="Copy display name",
                      command=lambda: self._copy_text(u['name']))
        m.add_command(label="Copy e-mail",
                      command=lambda: self._copy_text(u['mail']),
                      state='normal' if u.get('mail') else 'disabled')
        m.add_command(label="Copy UPN",
                      command=lambda: self._copy_text(u['userPrincipalName']),
                      state='normal' if u.get('userPrincipalName') else 'disabled')
        m.add_command(label="Copy DN",
                      command=lambda: self._copy_text(u['dn']))
        m.add_command(label="Copy all properties",
                      command=self._copy_all_props)
        m.add_separator()
        m.add_command(label="Enable", command=self.on_enable)
        m.add_command(label="Disable", command=self.on_disable)
        m.add_command(label="Unlock", command=self.on_unlock)
        m.add_command(label="Reset password...", command=self.on_reset)
        m.add_command(
            label=("Password never expires  ✓" if u.get('dontExpire')
                   else "Password never expires"),
            command=self.on_pwd_never_expires)
        m.add_separator()
        m.add_command(label="Groups...", command=self.on_groups)
        m.add_command(label="Move (OU)...", command=self.on_move)
        m.add_command(label="Edit...", command=self.on_edit)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()
        return 'break'

    def _show_computer_menu(self, event, c):
        m = tk.Menu(self, tearoff=0)
        m.add_command(label="Copy name",
                      command=lambda: self._copy_text(c['name']))
        m.add_command(label="Copy DNS name",
                      command=lambda: self._copy_text(c['dnsHostName']),
                      state='normal' if c.get('dnsHostName') else 'disabled')
        m.add_command(label="Copy account name",
                      command=lambda: self._copy_text(c['sAMAccountName']))
        m.add_command(label="Copy DN",
                      command=lambda: self._copy_text(c['dn']))
        m.add_command(label="Copy all properties",
                      command=self._copy_all_props)
        m.add_separator()
        m.add_command(label="Enable", command=self.on_enable)
        m.add_command(label="Disable", command=self.on_disable)
        m.add_separator()
        m.add_command(label="Rename...", command=self.on_rename)
        m.add_command(label="Move (OU)...", command=self.on_move)
        m.add_command(label="Edit...", command=self.on_edit)
        m.add_command(label="Delete", command=self.on_delete)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()
        return 'break'

    def _show_props_menu(self, event):
        rows = getattr(self, '_prop_rows', [])
        if not rows:
            return 'break'
        try:
            has_sel = bool(self.props.tag_ranges('sel'))
        except tk.TclError:
            has_sel = False
        # Determine which property line the cursor is on
        idx = self.props.index(f"@{event.x},{event.y}")
        line = int(idx.split('.')[0])
        row_val = None
        row_key = None
        cur = 1
        for k, v in rows:
            # each row occupies 3 lines: label, value, blank
            if line in (cur, cur + 1):
                row_key, row_val = k, v
                break
            cur += 3

        m = tk.Menu(self, tearoff=0)
        m.add_command(label="Copy selection",
                      command=self._copy_props_selection,
                      state='normal' if has_sel else 'disabled')
        if row_val is not None:
            m.add_command(label=f"Copy value ({row_key})",
                          command=lambda v=row_val: self._copy_text(v))
        m.add_command(label="Copy all properties", command=self._copy_all_props)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()
        return 'break'

    # --- Actions ---
    def _bulk_apply(self, objs, fn, done_msg):
        """Apply fn(dn) to each object; show a summary of failures."""
        errors = []
        self.master.config(cursor='watch')
        self.update_idletasks()
        try:
            for o in objs:
                try:
                    fn(o['dn'])
                except Exception as ex:
                    errors.append(f"{o.get('name') or o.get('sAMAccountName')}"
                                  f": {ex}")
        finally:
            self.master.config(cursor='')
        ok = len(objs) - len(errors)
        if errors:
            messagebox.showwarning(
                "Partially completed",
                f"{done_msg}: {ok} of {len(objs)}.\n\nErrors:\n"
                + "\n".join(errors[:10])
                + ("\n..." if len(errors) > 10 else ""))
        else:
            messagebox.showinfo("Done", f"{done_msg}: {ok}.")
        self.do_search()

    def on_enable(self):
        objs = self._selected_users()
        if not objs:
            messagebox.showinfo("No object selected",
                                "Select one or more objects in the list.")
            return
        if len(objs) == 1:
            try:
                self.client.enable_account(objs[0]['dn'])
                messagebox.showinfo("Done", "Account enabled.")
                self._refresh_selected(objs[0]['dn'])
            except Exception as ex:
                messagebox.showerror("Error", str(ex))
            return
        if not messagebox.askyesno(
                "Confirm", f"Enable {len(objs)} accounts?"):
            return
        self._bulk_apply(objs, self.client.enable_account, "Enabled")

    def on_disable(self):
        objs = self._selected_users()
        if not objs:
            messagebox.showinfo("No object selected",
                                "Select one or more objects in the list.")
            return
        if len(objs) == 1:
            u = objs[0]
            if not messagebox.askyesno(
                    "Confirm",
                    f"Disable account '{u['sAMAccountName']}'?"):
                return
            try:
                self.client.disable_account(u['dn'])
                messagebox.showinfo("Done", "Account disabled.")
                self._refresh_selected(u['dn'])
            except Exception as ex:
                messagebox.showerror("Error", str(ex))
            return
        if not messagebox.askyesno(
                "Confirm", f"Disable {len(objs)} accounts?"):
            return
        self._bulk_apply(objs, self.client.disable_account, "Disabled")

    def on_unlock(self):
        u = self._selected_user()
        if not u:
            return
        try:
            self.client.unlock_account(u['dn'])
            messagebox.showinfo("Done", "Account unlocked.")
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror("Error", str(ex))

    def on_reset(self):
        u = self._selected_user()
        if not u:
            return
        ResetPasswordDialog(self.master, self.client, u,
                            on_done=lambda: self._refresh_selected(u['dn']))

    def on_pwd_never_expires(self):
        """Toggle the 'password never expires' flag for the selected user."""
        u = self._selected_user()
        if not u or u.get('is_computer'):
            return
        cur = bool(u.get('dontExpire'))
        if cur:
            msg = (f"Clear the 'password never expires' flag for "
                   f"'{u['sAMAccountName']}'?\n\n"
                   f"The password will expire per the domain policy.")
        else:
            msg = (f"Set the 'password never expires' flag for "
                   f"'{u['sAMAccountName']}'?\n\n"
                   f"If a password change at next logon is pending, the "
                   f"requirement will be removed and the current password "
                   f"stays valid (same as in ADUC).")
        if not messagebox.askyesno("Password never expires", msg):
            return
        try:
            cleared = self.client.set_password_never_expires(u['dn'], not cur)
            if cur:
                done = "Flag cleared: the password expires per the domain policy."
            else:
                done = "Flag set: the password never expires."
                if cleared:
                    done += ("\n\nThe 'change password at next logon' "
                             "requirement was removed; the current password "
                             "stays valid.")
            messagebox.showinfo("Done", done)
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror("Error", str(ex))

    def on_groups(self):
        objs = [o for o in self._selected_users()
                if not o.get('is_computer')]
        if not objs:
            messagebox.showinfo("No user selected",
                                "Select one or more users in the list.")
            return
        if len(objs) == 1:
            GroupsDialog(self.master, self.client, objs[0])
            return
        # Bulk: add all selected users to the chosen groups
        picker = GroupPickerDialog(self.master, self.client)
        self.wait_window(picker)
        groups = picker.selected
        if not groups:
            return
        gnames = ", ".join(g['cn'] for g in groups[:5])
        if len(groups) > 5:
            gnames += ", ..."
        if not messagebox.askyesno(
                "Add to groups",
                f"Add {len(objs)} users to {len(groups)} group(s)?\n\n"
                f"Groups: {gnames}"):
            return
        added, skipped, errors = 0, 0, []
        self.master.config(cursor='watch')
        self.update_idletasks()
        try:
            for g in groups:
                for u in objs:
                    try:
                        self.client.add_to_group(u['dn'], g['dn'])
                        added += 1
                    except Exception as ex:
                        msg = str(ex)
                        if 'entryalreadyexists' in msg.lower().replace(' ', ''):
                            skipped += 1  # already a member
                        else:
                            errors.append(
                                f"{u['sAMAccountName']} -> {g['cn']}: {msg}")
        finally:
            self.master.config(cursor='')
        summary = f"Added: {added}."
        if skipped:
            summary += f"\nAlready members (skipped): {skipped}."
        if errors:
            summary += ("\n\nErrors:\n" + "\n".join(errors[:10])
                        + ("\n..." if len(errors) > 10 else ""))
            messagebox.showwarning("Partially completed", summary)
        else:
            messagebox.showinfo("Done", summary)

    def on_move(self):
        objs = self._selected_users()
        if not objs:
            messagebox.showinfo("No object selected",
                                "Select one or more objects in the list.")
            return
        MoveDialog(self.master, self.client, objs,
                   on_done=self.do_search)

    def _on_tree_double(self, event):
        """Double-click on a list row opens the edit dialog."""
        row = self.tree.identify_row(event.y)
        if not row:
            return
        self.tree.selection_set(row)
        self.tree.focus(row)
        self.on_edit()
        return 'break'

    def on_edit(self):
        u = self._selected_user()
        if not u:
            return
        if u.get('is_computer'):
            ComputerEditDialog(self.master, self.client, u,
                               on_done=lambda: self._refresh_selected(u['dn']))
        else:
            EditDialog(self.master, self.client, u,
                       on_done=lambda: self._refresh_selected(u['dn']))

    def on_rename(self):
        c = self._selected_user()
        if not c:
            return
        RenameDialog(self.master, self.client, c,
                     on_done=lambda dn: self._refresh_selected(dn))

    def on_delete(self):
        c = self._selected_user()
        if not c:
            return
        label = c.get('name') or c.get('sAMAccountName') or c['dn']
        if not messagebox.askyesno(
                "Confirm deletion",
                f"Delete object '{label}'?\n\nThis operation is irreversible."):
            return
        try:
            self.client.delete_object(c['dn'])
            messagebox.showinfo("Done", "Object deleted.")
            self.do_search()
            self.props.delete('1.0', 'end')
            self._prop_rows = []
        except Exception as ex:
            messagebox.showerror("Error", str(ex))

    def on_create(self):
        CreateDialog(self.master, self.client, on_done=self.do_search,
                     default_ou=self._current_base())


class ResetPasswordDialog(tk.Toplevel):
    def __init__(self, master, client, user, on_done=None):
        super().__init__(master)
        self.client = client
        self.user = user
        self.on_done = on_done
        self.title("Reset password")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text=f"User: {user['name']} "
                            f"({user['sAMAccountName']})",
                  font=('', 12, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 12))
        ttk.Label(frm, text="New password:").grid(row=1, column=0, sticky='w')
        self.e1 = ttk.Entry(frm, width=30, show='•')
        self.e1.grid(row=1, column=1, pady=4)
        ttk.Label(frm, text="Confirm:").grid(row=2, column=0, sticky='w')
        self.e2 = ttk.Entry(frm, width=30, show='•')
        self.e2.grid(row=2, column=1, pady=4)
        self.v_change = tk.BooleanVar(value=True)
        self.v_unlock = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="Change password at next logon",
                        variable=self.v_change).grid(
            row=3, column=0, columnspan=2, sticky='w', pady=(8, 0))
        ttk.Checkbutton(frm, text="Unlock the account",
                        variable=self.v_unlock).grid(
            row=4, column=0, columnspan=2, sticky='w')
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=300)
        self.lbl.grid(row=5, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, columnspan=2, sticky='e', pady=(12, 0))
        ttk.Button(btns, text="Apply", command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)
        self.e1.focus_set()

    def _apply(self):
        if not self.e1.get():
            self.lbl.config(text="Enter a new password.")
            return
        if self.e1.get() != self.e2.get():
            self.lbl.config(text="Passwords do not match.")
            return
        try:
            self.client.reset_password(
                self.user['dn'], self.e1.get(),
                unlock=self.v_unlock.get(),
                change_at_logon=self.v_change.get())
            messagebox.showinfo("Done", "Password reset.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class MoveDialog(tk.Toplevel):
    def __init__(self, master, client, user, on_done=None):
        """user — a single object dict or a list of them (bulk move)."""
        super().__init__(master)
        self.client = client
        self.users_list = user if isinstance(user, list) else [user]
        user = self.users_list[0]
        self.on_done = on_done
        self.title("Move to organizational unit")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        if len(self.users_list) == 1:
            hdr = f"Object: {user['name']} ({user['sAMAccountName']})"
        else:
            names = ", ".join(o['name'] for o in self.users_list[:3])
            if len(self.users_list) > 3:
                names += ", ..."
            hdr = f"Objects selected: {len(self.users_list)} ({names})"
        ttk.Label(frm, text=hdr, font=('', 12, 'bold'),
                  wraplength=420).grid(row=0, column=0, sticky='w',
                                       pady=(0, 10))
        parent = user['dn'].split(',', 1)[1] if ',' in user['dn'] else ''
        parents = {o['dn'].split(',', 1)[1].lower() if ',' in o['dn'] else ''
                   for o in self.users_list}
        if len(parents) > 1:
            parent = "(objects are in different containers)"
        ttk.Label(frm, text="Current location:").grid(row=1, column=0,
                                                        sticky='w')
        cur = ttk.Entry(frm, width=60)
        cur.insert(0, parent)
        cur.config(state='readonly')
        cur.grid(row=2, column=0, sticky='ew', pady=(2, 8))
        ttk.Label(frm, text="Target container (OU):").grid(row=3, column=0,
                                                            sticky='w')
        dest_row = ttk.Frame(frm)
        dest_row.grid(row=4, column=0, sticky='ew', pady=2)
        dest_row.columnconfigure(0, weight=1)
        self.combo = ttk.Combobox(dest_row, width=52)
        self.combo.grid(row=0, column=0, sticky='ew')
        ttk.Button(dest_row, text="Browse…", width=8,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))
        try:
            self.combo['values'] = self.client.list_ous()
        except Exception:
            pass
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=5, column=0, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, sticky='e', pady=(12, 0))
        ttk.Button(btns, text="Move", command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)

    def _browse_ou(self):
        picker = OUTreePickerDialog(
            self, self.client, initial=self.combo.get().strip() or None)
        self.wait_window(picker)
        if picker.selected_dn:
            self.combo.set(picker.selected_dn)

    def _apply(self):
        dest = self.combo.get().strip()
        if not dest:
            self.lbl.config(text="Specify a target container.")
            return
        if len(self.users_list) == 1:
            try:
                self.client.move_user(self.users_list[0]['dn'], dest)
                messagebox.showinfo("Done", "Object moved.")
                if self.on_done:
                    self.on_done()
                self.destroy()
            except Exception as ex:
                self.lbl.config(text=str(ex))
            return
        errors = []
        for o in self.users_list:
            try:
                self.client.move_user(o['dn'], dest)
            except Exception as ex:
                errors.append(f"{o.get('name')}: {ex}")
        ok = len(self.users_list) - len(errors)
        if errors:
            messagebox.showwarning(
                "Partially completed",
                f"Moved: {ok} of {len(self.users_list)}.\n\nErrors:\n"
                + "\n".join(errors[:10])
                + ("\n..." if len(errors) > 10 else ""))
        else:
            messagebox.showinfo("Done", f"Objects moved: {ok}.")
        if self.on_done:
            self.on_done()
        self.destroy()


class RenameDialog(tk.Toplevel):
    """Rename an object (change its name/CN) within the same container."""

    def __init__(self, master, client, obj, on_done=None):
        super().__init__(master)
        self.client = client
        self.obj = obj
        self.on_done = on_done
        self.title("Rename object")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        cur_name = obj.get('name') or obj.get('cn') or ''
        ttk.Label(frm, text=f"Object: {cur_name}",
                  font=('', 12, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 10))
        ttk.Label(frm, text="New name:").grid(row=1, column=0, sticky='w')
        self.e_name = ttk.Entry(frm, width=36)
        self.e_name.insert(0, cur_name)
        self.e_name.grid(row=1, column=1, pady=4, padx=(6, 0))
        self.e_name.focus_set()
        self.e_name.select_range(0, 'end')
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=340)
        self.lbl.grid(row=2, column=0, columnspan=2, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, sticky='e', pady=(12, 0))
        ttk.Button(btns, text="Rename", command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)
        self.e_name.bind('<Return>', lambda e: self._apply())

    def _apply(self):
        new_name = self.e_name.get().strip()
        if not new_name:
            self.lbl.config(text="Enter a name.")
            return
        cur_name = self.obj.get('name') or self.obj.get('cn') or ''
        if new_name == cur_name:
            self.destroy()
            return
        try:
            new_dn = self.client.rename_object(self.obj['dn'], new_name)
            messagebox.showinfo("Done", "Object renamed.")
            if self.on_done:
                self.on_done(new_dn)
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class GroupPickerDialog(tk.Toplevel):
    """Select one or more groups from the AD directory."""

    def __init__(self, master, client, exclude_dns=None):
        super().__init__(master)
        self.client = client
        self.exclude = set((d or '').lower() for d in (exclude_dns or []))
        self.selected = []
        self.title("Select groups")
        self.grab_set()
        self.geometry("520x460")
        frm = ttk.Frame(self, padding=14)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(2, weight=1)
        frm.columnconfigure(0, weight=1)

        top = ttk.Frame(frm)
        top.grid(row=0, column=0, columnspan=2, sticky='ew')
        ttk.Label(top, text="Filter:").grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(top, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self._load())
        ttk.Button(top, text="Find", command=self._load).grid(
            row=0, column=2, padx=(6, 0))

        scope = (f"Groups from OU \"{ACCESS_GROUPS_OU_NAME}\""
                 if ACCESS_GROUPS_OU_NAME else "Domain groups")
        ttk.Label(
            frm,
            text=f"{scope} (Cmd-click — multi-select):").grid(
            row=1, column=0, columnspan=2, sticky='w', pady=(10, 4))
        self.listbox = tk.Listbox(frm, selectmode='extended')
        self.listbox.grid(row=2, column=0, sticky='nsew')
        sb = ttk.Scrollbar(frm, orient='vertical', command=self.listbox.yview)
        sb.grid(row=2, column=1, sticky='ns')
        self.listbox.config(yscrollcommand=sb.set)

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Select", command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)

        self._all = []
        self._load()

    def _load(self):
        self.config(cursor='watch')
        self.update_idletasks()
        try:
            groups = self.client.list_groups(self.e_search.get())
            self._all = [g for g in groups
                         if g['dn'].lower() not in self.exclude]
        except Exception as ex:
            messagebox.showerror("Error", str(ex))
            self._all = []
        finally:
            self.config(cursor='')
        self.listbox.delete(0, 'end')
        for g in self._all:
            self.listbox.insert('end', g['cn'])
        if not self._all:
            self.listbox.insert('end', "(no groups found)")
            self.listbox.itemconfig(0, foreground='gray')

    def _ok(self):
        # Skip the placeholder row when there are no groups
        if not self._all:
            self.selected = []
        else:
            self.selected = [self._all[i]
                             for i in self.listbox.curselection()
                             if i < len(self._all)]
        self.destroy()


class GroupsDialog(tk.Toplevel):
    def __init__(self, master, client, user):
        super().__init__(master)
        self.client = client
        self.user = user
        self.title("Group membership")
        self.grab_set()
        frm = ttk.Frame(self, padding=16)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(1, weight=1)
        frm.columnconfigure(0, weight=1)
        ttk.Label(frm, text=f"Groups: {user['name']} ({user['sAMAccountName']})",
                  font=('', 12, 'bold')).grid(row=0, column=0, sticky='w',
                                              pady=(0, 8))
        self.listbox = tk.Listbox(frm, height=14, selectmode='extended',
                                  width=60)
        self.listbox.grid(row=1, column=0, sticky='nsew')
        sb = ttk.Scrollbar(frm, orient='vertical', command=self.listbox.yview)
        sb.grid(row=1, column=1, sticky='ns')
        self.listbox.config(yscrollcommand=sb.set)

        btns = ttk.Frame(frm)
        btns.grid(row=2, column=0, columnspan=2, sticky='ew', pady=(10, 0))
        ttk.Button(btns, text="Add...", command=self._add).grid(
            row=0, column=0)
        ttk.Button(btns, text="Remove selected", command=self._remove).grid(
            row=0, column=1, padx=(8, 0))
        ttk.Button(btns, text="Close", command=self.destroy).grid(
            row=0, column=2, padx=(8, 0))
        self.groups = []
        self._reload()

    def _reload(self):
        self.listbox.delete(0, 'end')
        try:
            self.groups = self.client.get_user_groups(self.user['dn'])
            for g in self.groups:
                self.listbox.insert('end', g['cn'])
        except Exception as ex:
            messagebox.showerror("Error", str(ex))

    def _add(self):
        exclude = [g['dn'] for g in self.groups]
        picker = GroupPickerDialog(self, self.client, exclude_dns=exclude)
        self.wait_window(picker)
        added = 0
        for g in picker.selected:
            try:
                self.client.add_to_group(self.user['dn'], g['dn'])
                added += 1
            except Exception as ex:
                messagebox.showerror("Error", f"{g['cn']}: {ex}")
        if added:
            self._reload()

    def _remove(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        if not messagebox.askyesno("Confirm",
                                   f"Remove from the selected groups ({len(sel)})?"):
            return
        for i in sel:
            try:
                self.client.remove_from_group(self.user['dn'],
                                              self.groups[i]['dn'])
            except Exception as ex:
                messagebox.showerror("Error",
                                     f"{self.groups[i]['cn']}: {ex}")
        self._reload()


class ComputerEditDialog(tk.Toplevel):
    """Edit computer attributes (description, location)."""

    def __init__(self, master, client, comp, on_done=None):
        super().__init__(master)
        self.client = client
        self.comp = comp
        self.on_done = on_done
        self.title("Edit computer")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text="Name:").grid(row=0, column=0, sticky='w', pady=3)
        ttk.Label(frm, text=comp.get('name') or '').grid(
            row=0, column=1, sticky='w', pady=3)
        ttk.Label(frm, text="DNS name:").grid(row=1, column=0, sticky='w',
                                              pady=3)
        ttk.Label(frm, text=comp.get('dnsHostName') or '—').grid(
            row=1, column=1, sticky='w', pady=3)
        ttk.Label(frm, text="Description:").grid(row=2, column=0, sticky='w',
                                                 pady=3)
        self.e_desc = ttk.Entry(frm, width=38)
        self.e_desc.insert(0, comp.get('description', '') or '')
        self.e_desc.grid(row=2, column=1, pady=3)
        self.lbl = ttk.Label(frm, text="", foreground='#b00')
        self.lbl.grid(row=3, column=0, columnspan=2, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=4, column=0, columnspan=2, pady=(12, 0))
        ttk.Button(btns, text="Save", command=self._save).grid(row=0, column=0)
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1, padx=(8, 0))

    def _save(self):
        try:
            self.client.update_attributes(
                self.comp['dn'], {'description': self.e_desc.get()})
            self.destroy()
            if self.on_done:
                self.on_done()
        except Exception as ex:
            self.lbl.config(text=f"Error: {ex}")


class EditDialog(tk.Toplevel):
    FIELDS = [
        ("Display name", 'displayName'),
        ("E-mail", 'mail'),
        ("Title", 'title'),
        ("Department", 'department'),
        ("Company", 'company'),
        ("Office", 'physicalDeliveryOfficeName'),
        ("Phone", 'telephoneNumber'),
        ("Description", 'description'),
    ]
    SRC = {
        'displayName': 'displayName', 'mail': 'mail', 'title': 'title',
        'department': 'department', 'company': 'company',
        'physicalDeliveryOfficeName': 'office',
        'telephoneNumber': 'phone', 'description': 'description',
    }

    def __init__(self, master, client, user, on_done=None):
        super().__init__(master)
        self.client = client
        self.user = user
        self.on_done = on_done
        self.title("Edit properties")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        self.entries = {}
        for i, (label, attr) in enumerate(self.FIELDS):
            ttk.Label(frm, text=label + ":").grid(row=i, column=0, sticky='w',
                                                  pady=3)
            e = ttk.Entry(frm, width=38)
            e.insert(0, user.get(self.SRC[attr], '') or '')
            e.grid(row=i, column=1, pady=3)
            self.entries[attr] = e
        r = len(self.FIELDS)
        # Account option: password never expires (UAC bit)
        self.v_dont_expire = tk.BooleanVar(value=bool(user.get('dontExpire')))
        ttk.Checkbutton(frm, text="Password never expires",
                        variable=self.v_dont_expire).grid(
            row=r, column=0, columnspan=2, sticky='w', pady=(8, 0))
        r += 1
        # Group membership (Member Of) — applied immediately
        grp = ttk.LabelFrame(frm, text="Group membership (Member Of)")
        grp.grid(row=r, column=0, columnspan=2, sticky='ew', pady=(10, 0))
        grp.columnconfigure(0, weight=1)
        self.grp_list = tk.Listbox(grp, height=6, selectmode='extended')
        self.grp_list.grid(row=0, column=0, sticky='ew', padx=6, pady=6)
        gsb = ttk.Scrollbar(grp, orient='vertical', command=self.grp_list.yview)
        gsb.grid(row=0, column=1, sticky='ns')
        self.grp_list.config(yscrollcommand=gsb.set)
        gbtns = ttk.Frame(grp)
        gbtns.grid(row=1, column=0, columnspan=2, sticky='w', padx=6, pady=(0, 6))
        ttk.Button(gbtns, text="Add...", command=self._add_groups).grid(
            row=0, column=0)
        ttk.Button(gbtns, text="Remove selected",
                   command=self._remove_groups).grid(row=0, column=1, padx=(8, 0))
        self.groups = []
        self._reload_groups()

        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=r + 1, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=r + 2, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Save", command=self._save).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)

    def _reload_groups(self):
        self.grp_list.delete(0, 'end')
        try:
            self.groups = self.client.get_user_groups(self.user['dn'])
            for g in self.groups:
                self.grp_list.insert('end', g['cn'])
        except Exception as ex:
            messagebox.showerror("Error", str(ex))

    def _add_groups(self):
        exclude = [g['dn'] for g in self.groups]
        picker = GroupPickerDialog(self, self.client, exclude_dns=exclude)
        self.wait_window(picker)
        added = 0
        for g in picker.selected:
            try:
                self.client.add_to_group(self.user['dn'], g['dn'])
                added += 1
            except Exception as ex:
                messagebox.showerror("Error", f"{g['cn']}: {ex}")
        if added:
            self._reload_groups()

    def _remove_groups(self):
        sel = self.grp_list.curselection()
        if not sel:
            return
        if not messagebox.askyesno("Confirm",
                                   f"Remove from the selected groups ({len(sel)})?"):
            return
        for i in sel:
            try:
                self.client.remove_from_group(self.user['dn'],
                                              self.groups[i]['dn'])
            except Exception as ex:
                messagebox.showerror("Error", f"{self.groups[i]['cn']}: {ex}")
        self._reload_groups()

    def _save(self):
        attrs = {attr: e.get() for attr, e in self.entries.items()}
        try:
            self.client.update_attributes(self.user['dn'], attrs)
            if self.v_dont_expire.get() != bool(self.user.get('dontExpire')):
                self.client.set_password_never_expires(
                    self.user['dn'], self.v_dont_expire.get())
            messagebox.showinfo("Done", "Changes saved.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class OUTreePickerDialog(tk.Toplevel):
    """Select an organizational unit (OU) by navigating the domain tree."""

    def __init__(self, master, client, initial=None):
        super().__init__(master)
        self.client = client
        self.selected_dn = None
        self.title("Select organizational unit (OU)")
        self.grab_set()
        self.geometry("420x480")
        frm = ttk.Frame(self, padding=12)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(0, weight=1)
        frm.columnconfigure(0, weight=1)
        self.tree = ttk.Treeview(frm, show='tree', selectmode='browse')
        self.tree.grid(row=0, column=0, sticky='nsew')
        sb = ttk.Scrollbar(frm, orient='vertical', command=self.tree.yview)
        sb.grid(row=0, column=1, sticky='ns')
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.bind('<Double-1>', lambda e: self._ok())
        btns = ttk.Frame(frm)
        btns.grid(row=1, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Select", command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)
        self._dn_by_item = {}
        self._build(initial)

    def _build(self, initial):
        root_label = self.client.upn_suffix or self.client.base_dn
        root = self.tree.insert('', 'end', text=root_label, open=True)
        self._dn_by_item[root] = self.client.base_dn
        item_by_dn = {self.client.base_dn.lower(): root}
        try:
            nodes = self.client.list_tree_nodes()
        except Exception:
            nodes = []
        sel_item = None
        for dn in nodes:
            parent_dn = dn.split(',', 1)[1] if ',' in dn else ''
            parent = item_by_dn.get(parent_dn.lower(), root)
            rdn = dn.split(',', 1)[0]
            label = rdn.split('=', 1)[1] if '=' in rdn else rdn
            it = self.tree.insert(parent, 'end', text=label)
            self._dn_by_item[it] = dn
            item_by_dn[dn.lower()] = it
            if initial and dn.lower() == initial.lower():
                sel_item = it
        if sel_item:
            self.tree.selection_set(sel_item)
            self.tree.see(sel_item)
        else:
            self.tree.selection_set(root)

    def _ok(self):
        sel = self.tree.selection()
        if sel:
            self.selected_dn = self._dn_by_item.get(sel[0])
        self.destroy()


class CalendarPopup(tk.Toplevel):
    """Compact date picker widget (no external dependencies).
    Returns the date via the on_pick(datetime.date) callback."""

    MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
              'August', 'September', 'October', 'November', 'December']
    WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

    def __init__(self, master, initial=None, on_pick=None):
        super().__init__(master)
        self.on_pick = on_pick
        self.title("Select date")
        self.resizable(False, False)
        self.grab_set()
        cur = initial or datetime.date.today()
        self.year = cur.year
        self.month = cur.month
        self._selected = cur
        self._frame = ttk.Frame(self, padding=8)
        self._frame.grid()
        self._build()

    def _build(self):
        for w in self._frame.winfo_children():
            w.destroy()
        hdr = ttk.Frame(self._frame)
        hdr.grid(row=0, column=0, columnspan=7, sticky='ew', pady=(0, 6))
        hdr.columnconfigure(1, weight=1)
        ttk.Button(hdr, text="◀", width=3, command=self._prev).grid(row=0, column=0)
        ttk.Label(hdr, text=f"{self.MONTHS[self.month - 1]} {self.year}",
                  anchor='center', font=('', 12, 'bold')).grid(row=0, column=1,
                                                               sticky='ew')
        ttk.Button(hdr, text="▶", width=3, command=self._next).grid(row=0, column=2)

        for i, dname in enumerate(self.WEEKDAYS):
            ttk.Label(self._frame, text=dname, width=4, anchor='center',
                      foreground='#888').grid(row=1, column=i)

        cal = calendar.Calendar(firstweekday=0)  # Monday first
        today = datetime.date.today()
        r = 2
        for week in cal.monthdatescalendar(self.year, self.month):
            for c, day in enumerate(week):
                if day.month != self.month:
                    ttk.Label(self._frame, text=str(day.day), width=4,
                              anchor='center', foreground='#ccc').grid(
                        row=r, column=c)
                else:
                    style = {}
                    txt = str(day.day)
                    b = ttk.Button(self._frame, text=txt, width=4,
                                   command=lambda d=day: self._pick(d))
                    if day == today:
                        b.configure(text=f"[{day.day}]")
                    b.grid(row=r, column=c, padx=1, pady=1)
            r += 1

    def _prev(self):
        self.month -= 1
        if self.month < 1:
            self.month = 12
            self.year -= 1
        self._build()

    def _next(self):
        self.month += 1
        if self.month > 12:
            self.month = 1
            self.year += 1
        self._build()

    def _pick(self, d):
        if self.on_pick:
            self.on_pick(d)
        self.destroy()


class CreateDialog(tk.Toplevel):
    def __init__(self, master, client, on_done=None, default_ou=None):
        super().__init__(master)
        self.client = client
        self.on_done = on_done
        self.selected_groups = []
        self.title("Create user")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()

        def row(r, label):
            ttk.Label(frm, text=label).grid(row=r, column=0, sticky='w', pady=3)
            e = ttk.Entry(frm, width=36)
            e.grid(row=r, column=1, pady=3)
            return e

        self.e_given = row(0, "First name:")
        self.e_sur = row(1, "Last name:")
        self.e_display = row(2, "Display name:")
        self.e_sam = row(3, "Login (sAMAccountName):")
        self.e_upn = row(4, "UPN suffix:")
        self.e_mail = row(5, "E-mail:")
        self.e_desc = row(6, "Description:")
        ttk.Label(frm, text="Password:").grid(row=7, column=0, sticky='w', pady=3)
        self.e_pass = ttk.Entry(frm, width=36, show='•')
        self.e_pass.grid(row=7, column=1, pady=3)

        # Organizational unit (OU) where the user will be created
        ttk.Label(frm, text="Organizational unit (OU):").grid(
            row=8, column=0, sticky='w', pady=3)
        ou_row = ttk.Frame(frm)
        ou_row.grid(row=8, column=1, sticky='ew', pady=3)
        self.cmb_ou = ttk.Combobox(ou_row, width=27)
        self.cmb_ou.grid(row=0, column=0)
        ttk.Button(ou_row, text="Browse…", width=8,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))
        self._fill_ou(default_ou)

        # Account expiration
        ttk.Label(frm, text="Expires:").grid(
            row=9, column=0, sticky='w', pady=3)
        exp_row = ttk.Frame(frm)
        exp_row.grid(row=9, column=1, sticky='w', pady=3)
        self.v_expire = tk.BooleanVar(value=False)
        ttk.Checkbutton(exp_row, text="Valid through (incl.):",
                        variable=self.v_expire,
                        command=self._toggle_expire).grid(row=0, column=0)
        self.e_expire = ttk.Entry(exp_row, width=12)
        self.e_expire.grid(row=0, column=1, padx=(6, 0))
        self.e_expire.insert(0, DATE_HINT)
        self.e_expire.config(state='disabled')
        self.btn_cal = ttk.Button(exp_row, text="📅", width=3,
                                  command=self._open_calendar, state='disabled')
        self.btn_cal.grid(row=0, column=2, padx=(4, 0))

        # Groups to add on creation
        grp = ttk.LabelFrame(frm, text="Groups on creation")
        grp.grid(row=10, column=0, columnspan=2, sticky='ew', pady=(8, 0))
        grp.columnconfigure(0, weight=1)
        self.grp_list = tk.Listbox(grp, height=4, selectmode='extended')
        self.grp_list.grid(row=0, column=0, sticky='ew', padx=6, pady=6)
        gsb = ttk.Scrollbar(grp, orient='vertical', command=self.grp_list.yview)
        gsb.grid(row=0, column=1, sticky='ns')
        self.grp_list.config(yscrollcommand=gsb.set)
        gb = ttk.Frame(grp)
        gb.grid(row=1, column=0, columnspan=2, sticky='w', padx=6, pady=(0, 6))
        ttk.Button(gb, text="Select groups...", command=self._pick_groups).grid(
            row=0, column=0)
        ttk.Button(gb, text="Remove selected", command=self._unpick).grid(
            row=0, column=1, padx=(8, 0))

        self.v_change = tk.BooleanVar(value=True)
        self.v_enabled = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="Change password at next logon",
                        variable=self.v_change).grid(
            row=11, column=1, sticky='w', pady=(6, 0))
        ttk.Checkbutton(frm, text="Account enabled",
                        variable=self.v_enabled).grid(
            row=12, column=1, sticky='w')

        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=13, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=14, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Create", command=self._create).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Cancel", command=self.destroy).grid(
            row=0, column=1)

        # Pre-fill the UPN suffix
        self.e_upn.insert(0, '@' + (client.upn_suffix or ''))

        # Automatically add the default groups
        self._load_default_groups()

    def _browse_ou(self):
        picker = OUTreePickerDialog(
            self, self.client, initial=self.cmb_ou.get().strip() or None)
        self.wait_window(picker)
        if picker.selected_dn:
            self.cmb_ou.set(picker.selected_dn)

    def _load_default_groups(self):
        missing = []
        for name in DEFAULT_CREATE_GROUPS:
            try:
                dn = self.client.find_group_dn(name)
            except Exception:
                dn = None
            if dn:
                if dn.lower() not in [x['dn'].lower() for x in self.selected_groups]:
                    self.selected_groups.append({'cn': name, 'dn': dn})
            else:
                missing.append(name)
        self._refresh_groups()
        if missing:
            self.lbl.config(
                text="Default groups not found: " + ", ".join(missing))

    def _fill_ou(self, default_ou=None):
        try:
            nodes = self.client.list_tree_nodes()
        except Exception:
            nodes = []
        values = [self.client.base_dn] + nodes
        self.cmb_ou['values'] = values
        if default_ou and default_ou in values:
            self.cmb_ou.set(default_ou)
        else:
            users_dn = next(
                (d for d in values if d.lower().startswith('cn=users,')), None)
            self.cmb_ou.set(users_dn or self.client.base_dn)

    def _pick_groups(self):
        exclude = [g['dn'] for g in self.selected_groups]
        picker = GroupPickerDialog(self, self.client, exclude_dns=exclude)
        self.wait_window(picker)
        have = [x['dn'].lower() for x in self.selected_groups]
        for g in picker.selected:
            if g['dn'].lower() not in have:
                self.selected_groups.append(g)
        self._refresh_groups()

    def _unpick(self):
        for i in reversed(list(self.grp_list.curselection())):
            del self.selected_groups[i]
        self._refresh_groups()

    def _refresh_groups(self):
        self.grp_list.delete(0, 'end')
        for g in self.selected_groups:
            self.grp_list.insert('end', g['cn'])

    def _toggle_expire(self):
        if self.v_expire.get():
            self.e_expire.config(state='normal')
            self.btn_cal.config(state='normal')
            if self.e_expire.get() == DATE_HINT:
                self.e_expire.delete(0, 'end')
            self.e_expire.focus_set()
        else:
            self.e_expire.config(state='disabled')
            self.btn_cal.config(state='disabled')

    def _open_calendar(self):
        try:
            init = parse_date(self.e_expire.get())
        except ValueError:
            init = datetime.date.today()
        CalendarPopup(self, initial=init, on_pick=self._set_date)

    def _set_date(self, d):
        self.e_expire.config(state='normal')
        self.e_expire.delete(0, 'end')
        self.e_expire.insert(0, fmt_date(d, with_time=False))

    def _create(self):
        sam = self.e_sam.get().strip()
        if not sam:
            self.lbl.config(text="Specify a login (sAMAccountName).")
            return
        if not self.e_pass.get():
            self.lbl.config(text="Specify a password.")
            return

        # Account expiration
        expire = None
        if self.v_expire.get():
            txt = self.e_expire.get().strip()
            try:
                expire = parse_date(txt)
            except ValueError:
                self.lbl.config(
                    text=f"Expiration: enter a date in {DATE_HINT} format.")
                return

        # Check that the login is not already taken in the domain
        try:
            if self.client.user_exists(sam):
                self.lbl.config(
                    text=f"A user with login \"{sam}\" already exists in the domain.")
                return
        except Exception:
            pass  # if the check failed, try to create anyway; AD will reject duplicates

        display = self.e_display.get().strip() or \
            f"{self.e_given.get().strip()} {self.e_sur.get().strip()}".strip()
        cn = display or sam
        upn = None
        suffix = self.e_upn.get().strip()
        if suffix:
            if not suffix.startswith('@'):
                suffix = '@' + suffix
            upn = sam + suffix
        try:
            dn = self.client.create_user(
                ou=self.cmb_ou.get().strip(),
                cn=cn, sam=sam, upn=upn, display=display or None,
                given=self.e_given.get().strip() or None,
                sn=self.e_sur.get().strip() or None,
                mail=self.e_mail.get().strip() or None,
                password=self.e_pass.get(),
                enabled=self.v_enabled.get(),
                change_at_logon=self.v_change.get(),
                description=self.e_desc.get().strip() or None,
                expire_date=expire)
            errs = []
            for g in self.selected_groups:
                try:
                    self.client.add_to_group(dn, g['dn'])
                except Exception as ex:
                    errs.append(f"{g['cn']}: {ex}")
            if errs:
                messagebox.showwarning(
                    "User created, but not added to all groups",
                    "\n".join(errs))
            else:
                messagebox.showinfo("Done", "User created.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


def _install_mac_keybindings(root):
    """macOS-style shortcuts: Cmd-delete a word in text fields
    and Cmd-click for multi-select in lists."""
    def del_prev_word(event):
        w = event.widget
        try:
            pos = w.index('insert')
        except Exception:
            return None
        text = w.get()
        i = pos
        while i > 0 and text[i - 1].isspace():
            i -= 1
        while i > 0 and not text[i - 1].isspace():
            i -= 1
        if i < pos:
            w.delete(i, pos)
        return 'break'

    def del_next_word(event):
        w = event.widget
        try:
            pos = w.index('insert')
        except Exception:
            return None
        text = w.get()
        n = len(text)
        i = pos
        while i < n and text[i].isspace():
            i += 1
        while i < n and not text[i].isspace():
            i += 1
        if i > pos:
            w.delete(pos, i)
        return 'break'

    for cls in ('Entry', 'TEntry'):
        root.bind_class(cls, '<Command-BackSpace>', del_prev_word)
        root.bind_class(cls, '<Command-Delete>', del_next_word)

    def lb_cmd_click(event):
        lb = event.widget
        idx = lb.nearest(event.y)
        if idx < 0:
            return 'break'
        if idx in lb.curselection():
            lb.selection_clear(idx)
        else:
            lb.selection_set(idx)
        lb.activate(idx)
        return 'break'

    root.bind_class('Listbox', '<Command-Button-1>', lb_cmd_click)


def main():
    root = tk.Tk()
    root.title("ADUC-Ext (macOS)")
    root.geometry("1400x700")
    _install_mac_keybindings(root)
    root.withdraw()  # hidden until a successful login

    config = ConfigStore()
    client = ADClient()
    login = LoginDialog(root, client, config)
    root.wait_window(login)

    if not login.success:
        root.destroy()
        return

    root.deiconify()
    win = MainWindow(root, client, config)

    # macOS routes Cmd+C/Cmd+A through the application's Edit menu, so
    # provide one; its commands call our own copy logic (pbcopy on macOS).
    menubar = tk.Menu(root)
    edit_menu = tk.Menu(menubar, tearoff=0)
    edit_menu.add_command(label="Cut", accelerator="Cmd+X",
                          command=lambda: root.focus_get() and
                          root.focus_get().event_generate('<<Cut>>'))
    edit_menu.add_command(label="Copy", accelerator="Cmd+C",
                          command=win._on_copy_shortcut)
    edit_menu.add_command(label="Paste", accelerator="Cmd+V",
                          command=lambda: root.focus_get() and
                          root.focus_get().event_generate('<<Paste>>'))
    edit_menu.add_separator()
    edit_menu.add_command(label="Select All", accelerator="Cmd+A",
                          command=win._on_select_all)
    menubar.add_cascade(label="Edit", menu=edit_menu)
    root.config(menu=menubar)

    root.mainloop()


if __name__ == '__main__':
    main()
