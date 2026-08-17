#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ADUC-Ext — управление учётными записями Active Directory.

Графическое приложение для macOS, подключающееся к каталогу Active Directory
по протоколу LDAP/LDAPS. При запуске запрашиваются учётные данные, и все
операции выполняются от имени указанной учётной записи.

Возможности:
    - поиск и просмотр свойств пользователей;
    - навигация по подразделениям (OU);
    - создание учётных записей;
    - включение, отключение и разблокировка;
    - сброс пароля;
    - управление членством в группах;
    - перемещение между подразделениями;
    - изменение атрибутов.

Требования: Python 3.8+ с Tkinter и пакет ldap3 (устанавливается автоматически
при первом запуске).

Запуск:
    python3 aduc_ext_ru.py
"""

import os
import sys
import ssl
import json
import calendar
import datetime
import subprocess
import importlib

# Tkinter обязателен для интерфейса
try:
    import tkinter as tk
    from tkinter import ttk, messagebox, simpledialog
except ImportError:
    sys.stderr.write(
        "Не найден модуль Tkinter (нужен для графического интерфейса).\n"
        "Установите его: brew install python-tk  — либо используйте Python с python.org.\n")
    raise SystemExit(1)


# --- Проверка и автоматическая установка зависимостей ---
REQUIRED_PACKAGES = [
    # (имя для импорта, имя пакета для pip)
    ("ldap3", "ldap3"),
]


def _pip_install(package):
    """Пытается установить пакет несколькими способами. Возвращает True при успехе."""
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
    """Проверяет наличие требуемых пакетов и при отсутствии предлагает установку.
    Возвращает список пакетов, которые установить не удалось."""
    missing = []
    for mod_name, pip_name in REQUIRED_PACKAGES:
        try:
            importlib.import_module(mod_name)
        except ImportError:
            missing.append((mod_name, pip_name))

    if not missing:
        return []

    # Небольшое окно-уведомление на время установки
    splash = tk.Tk()
    splash.title("Проверка зависимостей")
    splash.geometry("420x150")
    splash.resizable(False, False)
    names = ", ".join(p for _, p in missing)
    lbl = tk.Label(
        splash, padx=20, pady=20, justify="left", font=("", 13),
        text=f"Не установлены компоненты: {names}\n\nВыполняется установка, подождите…")
    lbl.pack(expand=True, fill="both")
    splash.update()

    still_missing = []
    for mod_name, pip_name in missing:
        lbl.config(text=f"Устанавливается компонент: {pip_name}\nПодождите…")
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
        "Не удалось установить зависимости",
        "Не удалось автоматически установить: " + ", ".join(_failed) + "\n\n"
        "Установите вручную в терминале:\n"
        "    pip3 install " + " ".join(_failed) + "\n\n"
        "Если pip не найден:\n"
        "    python3 -m ensurepip --upgrade")
    raise SystemExit(1)

from ldap3 import (
    Server, Connection, ALL, SUBTREE, LEVEL, MODIFY_REPLACE, MODIFY_ADD,
    MODIFY_DELETE, Tls,
)
from ldap3.core.exceptions import LDAPException


# --- Атрибуты пользователя, запрашиваемые из AD ---
USER_ATTRS = [
    'displayName', 'sAMAccountName', 'userPrincipalName', 'givenName', 'sn',
    'mail', 'userAccountControl', 'msDS-User-Account-Control-Computed',
    'lockoutTime', 'description', 'title', 'department', 'company',
    'physicalDeliveryOfficeName', 'telephoneNumber', 'distinguishedName',
    'whenCreated', 'pwdLastSet', 'lastLogonTimestamp', 'accountExpires',
    'msDS-UserPasswordExpiryTimeComputed', 'badPwdCount', 'badPasswordTime',
]

# Биты userAccountControl
UAC_DISABLED = 0x0002          # ACCOUNTDISABLE
UAC_NORMAL_ACCOUNT = 0x0200    # NORMAL_ACCOUNT
UAC_DONT_EXPIRE_PASSWORD = 0x10000
# Бит блокировки в msDS-User-Account-Control-Computed
UF_LOCKOUT = 0x0010

# Имя подразделения (OU), из которого выбираются группы. Если оставить пустым,
# при выборе групп показываются все группы домена.
ACCESS_GROUPS_OU_NAME = ""

# Группы, автоматически добавляемые при создании пользователя. По умолчанию пусто.
DEFAULT_CREATE_GROUPS = []


# ============================================================================
#  Хранение списка доменов (конфиг)
# ============================================================================
class ConfigStore:
    """Список доменов в JSON-файле (пароли НЕ сохраняются)."""

    def __init__(self, path=None):
        self.path = path or os.path.join(
            os.path.expanduser("~"), ".aduc_ext_ru_domains.json")

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
        """Добавить/обновить профиль домена по полю host."""
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
#  Слой доступа к AD
# ============================================================================
class ADClient:
    """Обёртка над ldap3 для операций с пользователями AD."""

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
        """Устанавливает соединение и проверяет учётные данные (bind)."""
        if port is None:
            port = 636 if use_ssl else 389

        tls = None
        if use_ssl:
            validate = ssl.CERT_REQUIRED if verify_cert else ssl.CERT_NONE
            tls = Tls(validate=validate, version=ssl.PROTOCOL_TLS_CLIENT
                      if hasattr(ssl, 'PROTOCOL_TLS_CLIENT') else ssl.PROTOCOL_TLS)

        self.server = Server(host, port=port, use_ssl=use_ssl,
                             get_info=ALL, tls=tls, connect_timeout=10)
        # SIMPLE bind; auto_bind поднимет исключение при неверных данных
        # raise_exceptions=False: ошибки операций проверяем через self._check(),
        # а неверные учётные данные всё равно поднимут исключение через auto_bind.
        self.conn = Connection(
            self.server, user=username, password=password,
            authentication='SIMPLE', auto_bind=True, raise_exceptions=False)

        # Определить базовый DN домена из RootDSE
        self.base_dn = self.server.info.other.get(
            'defaultNamingContext', [None])[0]
        if not self.base_dn:
            # Резерв: собрать из имени домена
            self.base_dn = ','.join('dc=' + p for p in host.split('.')
                                    if '.' in host)
        self.host = host
        # Сохранить учётные данные активной сессии (для смены домена без
        # повторного ввода). Сохраняем только после успешного bind.
        self.username = username
        self._password = password
        self._use_ssl = use_ssl
        self._verify = verify_cert
        # Сброс кэша OU групп доступа при новом подключении
        self._access_ou = None
        self._access_ou_done = False
        # UPN-суффикс из base_dn (dc=corp,dc=local -> corp.local)
        parts = [x.split('=')[1] for x in self.base_dn.split(',')
                 if x.lower().startswith('dc=')]
        self.upn_suffix = '.'.join(parts) if parts else host
        return True

    def switch_server(self, host, use_ssl=None, verify_cert=None):
        """Переподключение к другому домену/контроллеру под учётными данными
        текущей сессии. Поднимает исключение при неуспехе (нет доступа/прав)."""
        if not self.username:
            raise RuntimeError("Нет активной сессии для смены домена.")
        if use_ssl is None:
            use_ssl = self._use_ssl
        if verify_cert is None:
            verify_cert = self._verify
        return self.connect(host, self.username, self._password,
                            use_ssl=use_ssl, verify_cert=verify_cert)

    def is_ssl(self):
        return bool(self.server and self.server.ssl)

    # ---- Постраничная выборка (снимает лимит AD в 1000 записей) ----
    def _paged_search(self, base, flt, attributes, scope=SUBTREE,
                      page_size=1000):
        all_entries = []
        cookie = None
        while True:
            ok = self.conn.search(base, flt, search_scope=scope,
                                  attributes=attributes,
                                  paged_size=page_size, paged_cookie=cookie)
            if not ok and not self.conn.entries:
                # Проверить, не ошибка ли (например, неверный base)
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

    # ---- Поиск пользователей ----
    def search_users(self, query=None, base=None, scope=SUBTREE):
        """query — строка поиска; base — DN контейнера/OU; scope — LEVEL/SUBTREE.
        Возвращает всех подходящих пользователей (постранично, без лимита)."""
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
            scope = SUBTREE  # поиск по тексту — всегда во всём поддереве base
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
            state = "Заблокирован"
        elif not enabled:
            state = "Отключён"
        else:
            state = "Активен"

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

    # ---- Список OU и групп ----
    def list_ous(self):
        """Только organizationalUnit — для выбора целевого контейнера."""
        entries = self._paged_search(
            self.base_dn, "(objectClass=organizationalUnit)",
            ['distinguishedName'], SUBTREE)
        ous = [str(e.entry_dn) for e in entries]
        ous.sort()
        return ous

    def list_tree_nodes(self):
        """OU + стандартные контейнеры (CN=Users, CN=Computers и т.п.) —
        для построения дерева, как в оснастке ADUC."""
        flt = ("(|(objectClass=organizationalUnit)"
               "(objectClass=container)(objectClass=builtinDomain))")
        entries = self._paged_search(
            self.base_dn, flt, ['distinguishedName', 'objectClass'], SUBTREE)
        nodes = [str(e.entry_dn) for e in entries
                 if str(e.entry_dn).lower() != self.base_dn.lower()]
        # Сортировка по глубине (число запятых), затем по алфавиту
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
            return name  # уже DN
        q = _escape_filter(name)
        flt = f"(&(objectClass=group)(|(cn={q})(sAMAccountName={q})))"
        self.conn.search(self.base_dn, flt, search_scope=SUBTREE,
                         attributes=['distinguishedName'])
        if self.conn.entries:
            return str(self.conn.entries[0].entry_dn)
        return None

    def get_access_groups_dn(self):
        """DN подразделения, заданного в ACCESS_GROUPS_OU_NAME. Возвращает None,
        если имя не задано или подразделение не найдено. Кэшируется."""
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
        """Список групп (с фильтром по подстроке). Если задано подразделение
        ACCESS_GROUPS_OU_NAME — поиск ограничен им, иначе по всему домену."""
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

    # ---- Операции изменения ----
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
        # lockoutTime = 0 разблокирует учётную запись
        self.conn.modify(dn, {'lockoutTime': [(MODIFY_REPLACE, [0])]})
        self._check()

    def reset_password(self, dn, new_password, unlock=True,
                       change_at_logon=True):
        if not self.is_ssl():
            raise RuntimeError(
                "Сброс пароля требует защищённого соединения (LDAPS). "
                "Переподключитесь по LDAPS (порт 636).")
        # Смена пароля администратором: замена unicodePwd
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

    def add_to_group(self, user_dn, group_name):
        gdn = self.find_group_dn(group_name)
        if not gdn:
            raise RuntimeError(f"Группа '{group_name}' не найдена.")
        self.conn.modify(gdn, {'member': [(MODIFY_ADD, [user_dn])]})
        self._check()

    def remove_from_group(self, user_dn, group_dn):
        self.conn.modify(group_dn, {'member': [(MODIFY_DELETE, [user_dn])]})
        self._check()

    def update_attributes(self, dn, attrs):
        """attrs: dict имя_ldap -> значение (пустая строка = удалить)."""
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
        """Проверка, есть ли уже пользователь с таким логином (sAMAccountName)."""
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
            'userAccountControl': UAC_NORMAL_ACCOUNT | UAC_DISABLED,  # сначала выключен
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
            # Действует ПО указанную дату включительно => истекает в начале
            # следующего дня. accountExpires хранится как filetime (100нс с 1601).
            dt = datetime.datetime(expire_date.year, expire_date.month,
                                   expire_date.day) + datetime.timedelta(days=1)
            attrs['accountExpires'] = _datetime_to_filetime(dt)

        self.conn.add(dn, attributes=attrs)
        self._check()

        # Установить пароль (нужен LDAPS)
        if password:
            if not self.is_ssl():
                raise RuntimeError(
                    "Пользователь создан, но задать пароль без LDAPS нельзя. "
                    "Переподключитесь по LDAPS для установки пароля.")
            pwd_val = ('"%s"' % password).encode('utf-16-le')
            self.conn.modify(dn, {'unicodePwd': [(MODIFY_REPLACE, [pwd_val])]})
            self._check()

        # Включить учётную запись
        if enabled and password:
            self.conn.modify(dn, {'userAccountControl':
                                  [(MODIFY_REPLACE, [UAC_NORMAL_ACCOUNT])]})
            self._check()

        # Смена пароля при следующем входе (0 = требовать смену, -1 = не требовать)
        if password:
            pls = 0 if change_at_logon else -1
            self.conn.modify(dn, {'pwdLastSet': [(MODIFY_REPLACE, [pls])]})
            self._check()

        return dn


def _escape_filter(s):
    """Экранирование спецсимволов в LDAP-фильтре (RFC 4515)."""
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
    """Экранирование спецсимволов в компоненте DN."""
    for ch in ['\\', ',', '+', '"', '<', '>', ';', '=']:
        s = s.replace(ch, '\\' + ch)
    return s


# Русские сокращённые названия месяцев для формата DD MMM YYYY.
MONTH_ABBR = ['янв', 'фев', 'мар', 'апр', 'май', 'июн',
              'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']
DATE_HINT = "ДД МММ ГГГГ"


def fmt_date(dt, with_time=True):
    """Формат даты/времени как DD MMM YYYY (например, 14 авг 2026)."""
    s = f"{dt.day:02d} {MONTH_ABBR[dt.month - 1]} {dt.year:04d}"
    if with_time and isinstance(dt, datetime.datetime):
        s += f" {dt.hour:02d}:{dt.minute:02d}"
    return s


def parse_date(txt):
    """Разбор строки DD MMM YYYY (или DD MM YYYY) в datetime.date."""
    parts = txt.strip().lower().replace('-', ' ').replace('.', ' ').split()
    if len(parts) != 3:
        raise ValueError("bad date")
    day = int(parts[0])
    mon_part = parts[1]
    if mon_part.isdigit():
        month = int(mon_part)
    else:
        month = MONTH_ABBR.index(mon_part[:3]) + 1
    year = int(parts[2])
    return datetime.date(year, month, day)


def filetime_to_str(val):
    """Конвертация AD-времени (100нс с 1601 или generalizedTime) в строку."""
    if val is None or val == '':
        return ''
    if isinstance(val, datetime.datetime):
        return fmt_date(val)
    try:
        num = int(val)
    except (ValueError, TypeError):
        return str(val)
    if num == 0:
        return 'никогда / не задано'
    if num >= 0x7FFFFFFFFFFFFFFF:
        return 'никогда'
    try:
        secs = num / 10_000_000 - 11644473600
        return fmt_date(datetime.datetime.fromtimestamp(secs))
    except (ValueError, OverflowError, OSError):
        return str(val)


def _datetime_to_filetime(dt):
    """datetime -> AD filetime (100нс с 1601-01-01)."""
    epoch = datetime.datetime(1601, 1, 1)
    return int((dt - epoch).total_seconds() * 10_000_000)


def pwd_expiry_text(u):
    """Когда должна быть произведена смена пароля."""
    pls = u.get('pwdLastSet')
    try:
        pls_i = int(pls)
    except (TypeError, ValueError):
        pls_i = None
    if pls_i == 0:
        return "при следующем входе (требуется смена)"
    if u.get('dontExpire'):
        return "никогда (пароль не истекает)"
    exp = u.get('pwdExpiry')
    try:
        n = int(exp)
    except (TypeError, ValueError):
        return ''
    if n == 0:
        return ''
    if n >= 0x7FFFFFFFFFFFFFFF:
        return "никогда"
    txt = filetime_to_str(n)
    # Отметить, если срок уже прошёл
    try:
        secs = n / 10_000_000 - 11644473600
        if datetime.datetime.fromtimestamp(secs) < datetime.datetime.now():
            txt += " (просрочен)"
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
    """Окно запроса учётных данных с выбором сохранённого домена."""

    def __init__(self, master, client, config=None, preselect=None):
        super().__init__(master)
        self.client = client
        self.config = config
        self.success = False
        self.title("Подключение к Active Directory")
        self.resizable(False, False)
        self.grab_set()

        frm = ttk.Frame(self, padding=18)
        frm.grid()

        ttk.Label(frm, text="Подключение к домену Active Directory",
                  font=('', 13, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 12))

        # Выбор сохранённого домена
        ttk.Label(frm, text="Сохранённый домен:").grid(row=1, column=0,
                                                       sticky='w', pady=4)
        dom_row = ttk.Frame(frm)
        dom_row.grid(row=1, column=1, sticky='ew', pady=4)
        self.cmb_domain = ttk.Combobox(dom_row, width=27, state='readonly')
        self.cmb_domain.grid(row=0, column=0)
        self.cmb_domain.bind('<<ComboboxSelected>>', self._on_pick)
        ttk.Button(dom_row, text="✕", width=3,
                   command=self._delete_profile).grid(row=0, column=1, padx=(4, 0))

        ttk.Label(frm, text="Сервер / DC:").grid(row=2, column=0, sticky='w', pady=4)
        self.e_host = ttk.Entry(frm, width=34)
        self.e_host.grid(row=2, column=1, pady=4)

        ttk.Label(frm, text="Пользователь:").grid(row=3, column=0, sticky='w', pady=4)
        self.e_user = ttk.Entry(frm, width=34)
        self.e_user.grid(row=3, column=1, pady=4)

        ttk.Label(frm, text="Пароль:").grid(row=4, column=0, sticky='w', pady=4)
        self.e_pass = ttk.Entry(frm, width=34, show='•')
        self.e_pass.grid(row=4, column=1, pady=4)

        self.use_ssl = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="LDAPS (шифрование, порт 636)",
                        variable=self.use_ssl).grid(
            row=5, column=1, sticky='w', pady=(8, 0))

        self.verify = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm, text="Проверять сертификат сервера",
                        variable=self.verify).grid(
            row=6, column=1, sticky='w')

        self.save_domain = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="Сохранить домен в список",
                        variable=self.save_domain).grid(
            row=7, column=1, sticky='w')

        self.lbl_status = ttk.Label(frm, text="", foreground='#B00020',
                                    wraplength=340)
        self.lbl_status.grid(row=8, column=0, columnspan=2, sticky='w',
                             pady=(10, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=9, column=0, columnspan=2, sticky='e', pady=(14, 0))
        ttk.Button(btns, text="Подключиться",
                   command=self._connect).grid(row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена",
                   command=self._cancel).grid(row=0, column=1)

        # Загрузка списка доменов
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
            # первое подключение — подсказки
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
                "Удаление домена",
                f"Удалить '{self._profile_label(d)}' из списка?"):
            return
        self._profiles = self.config.remove(d.get('host'))
        self.cmb_domain.set('')
        self._refresh_combo()

    def _connect(self):
        host = self.e_host.get().strip()
        user = self.e_user.get().strip()
        pwd = self.e_pass.get()
        if not host or not user or not pwd:
            self.lbl_status.config(text="Заполните сервер, пользователя и пароль.")
            return
        self.lbl_status.config(text="Подключение...")
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
            self.lbl_status.config(text=f"Не удалось подключиться: {ex}")
        except Exception as ex:
            self.lbl_status.config(text=f"Ошибка: {ex}")

    def _cancel(self):
        self.success = False
        self.destroy()


class MainWindow(ttk.Frame):
    """Главное окно приложения."""

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

    # --- Панель поиска ---
    def _build_toolbar(self):
        bar = ttk.Frame(self, padding=8)
        bar.grid(row=0, column=0, sticky='ew')
        bar.columnconfigure(5, weight=1)  # распорка между поиском и доменом
        ttk.Label(bar, text="Поиск:").grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(bar, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self.do_search())
        ttk.Button(bar, text="Найти", command=self.do_search).grid(
            row=0, column=2, padx=6)
        ttk.Button(bar, text="Обновить", command=self.do_search).grid(
            row=0, column=3)
        ttk.Button(bar, text="Создать пользователя",
                   command=self.on_create).grid(row=0, column=4, padx=(20, 0))

        # Переключатель доменов (справа)
        ttk.Label(bar, text="Домен:").grid(row=0, column=6, padx=(0, 6))
        self.cmb_dom = ttk.Combobox(bar, width=24)  # редактируемый: можно ввести новый
        self.cmb_dom.grid(row=0, column=7)
        self.cmb_dom.bind('<Return>', lambda e: self.on_switch_domain())
        ttk.Button(bar, text="Сменить домен",
                   command=self.on_switch_domain).grid(row=0, column=8, padx=(6, 0))
        self._domain_profiles = []
        self._reload_domains()

        # Вложенные OU
        self.include_subtree = tk.BooleanVar(value=False)
        ttk.Checkbutton(
            bar, text="Показывать пользователей из вложенных OU",
            variable=self.include_subtree,
            command=self.do_search).grid(row=1, column=0, columnspan=5,
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
            messagebox.showinfo("Домен не выбран",
                                "Выберите из списка или введите домен/контроллер.")
            return
        if host.lower() == (self.client.host or '').lower():
            return  # тот же домен — ничего не делаем

        # Параметры соединения из сохранённого профиля (если есть)
        profiles = self.config.load() if self.config else []
        prof = next((d for d in profiles
                     if (d.get('name') or d.get('host')) == host
                     or d.get('host') == host), None)
        use_ssl = prof.get('use_ssl', self.client._use_ssl) if prof else self.client._use_ssl
        verify = prof.get('verify', self.client._verify) if prof else self.client._verify

        self.master.config(cursor='watch')
        self.update_idletasks()
        try:
            # Смена домена под учётными данными активной сессии
            self.client.switch_server(host, use_ssl=use_ssl, verify_cert=verify)
        except Exception as ex:
            self.master.config(cursor='')
            messagebox.showerror(
                "Ошибка доступа",
                f"Не удалось подключиться к домену «{host}» под текущей "
                f"учётной записью ({self.client.username}).\n\n"
                f"Недостаточно прав или домен недоступен:\n{ex}")
            return
        finally:
            self.master.config(cursor='')

        # Сохранить домен под текущим пользователем
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
            "Домен изменён",
            f"Подключено к домену «{self.client.host}» под учётной записью "
            f"{self.client.username}.")

    # --- Основная область ---
    def _build_body(self):
        body = ttk.Panedwindow(self, orient='horizontal')
        body.grid(row=1, column=0, sticky='nsew', padx=8, pady=(0, 8))

        # Дерево подразделений (OU) — как в оснастке ADUC
        ou_frame = ttk.Frame(body)
        ou_frame.rowconfigure(1, weight=1)
        ou_frame.columnconfigure(0, weight=1)
        ttk.Label(ou_frame, text="Подразделения").grid(
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

        # Список пользователей
        left = ttk.Frame(body)
        left.rowconfigure(0, weight=1)
        left.columnconfigure(0, weight=1)
        cols = ('name', 'sam', 'mail', 'desc', 'state')
        self.tree = ttk.Treeview(left, columns=cols, show='headings',
                                 selectmode='browse')
        self.tree.heading('name', text='Имя')
        self.tree.heading('sam', text='Логин')
        self.tree.heading('mail', text='E-mail')
        self.tree.heading('desc', text='Описание')
        self.tree.heading('state', text='Состояние')
        self.tree.column('name', width=200)
        self.tree.column('sam', width=130)
        self.tree.column('mail', width=200)
        self.tree.column('desc', width=180)
        self.tree.column('state', width=100)
        self.tree.grid(row=0, column=0, sticky='nsew')
        sb = ttk.Scrollbar(left, orient='vertical', command=self.tree.yview)
        sb.grid(row=0, column=1, sticky='ns')
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.bind('<<TreeviewSelect>>', self.on_select)
        # Контекстное меню списка пользователей (правый клик / Ctrl-клик на macOS)
        self.tree.bind('<Button-2>', self._show_user_menu)
        self.tree.bind('<Button-3>', self._show_user_menu)
        self.tree.bind('<Control-Button-1>', self._show_user_menu)
        # Cmd+C / Ctrl+C в списке копирует строку выбранного пользователя
        for seq in ('<<Copy>>', '<Command-Key-c>', '<Command-Key-C>',
                    '<Control-Key-c>', '<Control-Key-C>'):
            self.tree.bind(seq, lambda e: self._copy_selected_row())
        body.add(left, weight=3)

        # Правая панель: свойства + действия
        right = ttk.Frame(body)
        right.rowconfigure(0, weight=1)
        right.columnconfigure(0, weight=1)

        prop_group = ttk.LabelFrame(right, text="Свойства пользователя")
        prop_group.grid(row=0, column=0, sticky='nsew')
        prop_group.rowconfigure(0, weight=1)
        prop_group.columnconfigure(0, weight=1)
        # Виджет включён (без state='disabled'), чтобы получать фокус клавиатуры и
        # чтобы работало штатное Cmd+C/Ctrl+C; редактирование блокирует _block_edit.
        self.props = tk.Text(prop_group, width=44, height=18, wrap='word',
                             relief='flat', font=('Menlo', 11),
                             insertwidth=0, exportselection=True)
        self.props.grid(row=0, column=0, sticky='nsew', padx=4, pady=4)
        # Блокировать любое изменение текста (выделение/копирование работают)
        self.props.bind('<Key>', self._block_edit)
        self.props.bind('<<Paste>>', lambda e: 'break')
        self.props.bind('<<Cut>>', lambda e: 'break')
        self.props.bind('<Delete>', lambda e: 'break')
        self.props.bind('<BackSpace>', lambda e: 'break')
        # Контекстное меню панели свойств
        self.props.bind('<Button-2>', self._show_props_menu)
        self.props.bind('<Button-3>', self._show_props_menu)
        self.props.bind('<Control-Button-1>', self._show_props_menu)
        # Фокус клавиатуры по клику, чтобы горячие клавиши доходили до панели
        self.props.bind('<Button-1>', lambda e: self.props.focus_set())
        # Автокопирование при выделении мышью: отпускание кнопки после протяжки
        # копирует выделенный текст (работает, даже если Cmd+C до нас не доходит).
        self.props.bind('<ButtonRelease-1>', self._props_autocopy)

        act_group = ttk.LabelFrame(right, text="Действия")
        act_group.grid(row=1, column=0, sticky='ew', pady=(8, 0))
        actions = [
            ("Включить", self.on_enable),
            ("Отключить", self.on_disable),
            ("Разблокировать", self.on_unlock),
            ("Сбросить пароль", self.on_reset),
            ("Группы...", self.on_groups),
            ("Переместить (OU)", self.on_move),
            ("Изменить...", self.on_edit),
        ]
        for i, (label, cmd) in enumerate(actions):
            ttk.Button(act_group, text=label, command=cmd, width=18).grid(
                row=i // 2, column=i % 2, padx=4, pady=4, sticky='ew')
        body.add(right, weight=2)

    def _build_statusbar(self):
        self.status = ttk.Label(self, text="", padding=(8, 4),
                                relief='sunken', anchor='w')
        self.status.grid(row=2, column=0, sticky='ew')
        self._update_status()

    def _update_status(self, extra=''):
        proto = "LDAPS" if self.client.is_ssl() else "LDAP"
        base = (f"Подключено: {self.client.host} ({proto})   |   "
                f"База: {self.client.base_dn}")
        self.status.config(text=base + ('   |   ' + extra if extra else ''))

    # --- Дерево подразделений ---
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
            return self.client.upn_suffix or 'домен'
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

    # --- Поиск ---
    def do_search(self):
        self.master.config(cursor='watch')
        self.update_idletasks()
        try:
            base = self._current_base()
            text = self.e_search.get().strip()
            subtree = bool(text) or self.include_subtree.get()
            scope = SUBTREE if subtree else LEVEL
            self.users = self.client.search_users(
                query=text, base=base, scope=scope)
            self.tree.delete(*self.tree.get_children())
            for i, u in enumerate(self.users):
                self.tree.insert('', 'end', iid=str(i), values=(
                    u['name'], u['sAMAccountName'], u['mail'], u['description'], u['state']))
            scope_txt = self._short_dn(base)
            if subtree:
                scope_txt += " (+вложенные)"
            self._update_status(
                f"Найдено: {len(self.users)}  |  область: {scope_txt}")
        except Exception as ex:
            messagebox.showerror("Ошибка поиска", str(ex))
        finally:
            self.master.config(cursor='')

    def _selected_user(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("Не выбран пользователь",
                                "Сначала выберите пользователя в списке.")
            return None
        return self.users[int(sel[0])]

    def on_select(self, event=None):
        sel = self.tree.selection()
        if not sel:
            return
        u = self.users[int(sel[0])]
        self._show_props(u)

    def _refresh_selected(self, dn):
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
            ("Отображаемое имя", u['displayName']),
            ("Логин", u['sAMAccountName']),
            ("UPN", u['userPrincipalName']),
            ("Имя", u['givenName']),
            ("Фамилия", u['sn']),
            ("E-mail", u['mail']),
            ("Состояние", u['state']),
            ("Заблокирован", "Да" if u['locked'] else "Нет"),
            ("Описание", u['description']),
            ("Должность", u['title']),
            ("Отдел", u['department']),
            ("Компания", u['company']),
            ("Кабинет", u['office']),
            ("Телефон", u['phone']),
            ("Пароль изменён", filetime_to_str(u['pwdLastSet'])),
            ("Требуется смена пароля", pwd_expiry_text(u)),
            ("Неверных попыток входа",
             '' if u.get('badPwdCount') in (None, '') else str(u.get('badPwdCount'))),
            ("Последний неверный ввод", filetime_to_str(u.get('badPwdTime'))),
            ("Последний вход", filetime_to_str(u['lastLogon'])),
            ("Создан", filetime_to_str(u['whenCreated'])),
            ("Истекает", filetime_to_str(u['accountExpires'])),
            ("DN", u['dn']),
        ]
        self._prop_rows = [(k, v) for k, v in rows if v not in (None, '')]
        self.props.delete('1.0', 'end')
        for k, val in self._prop_rows:
            self.props.insert('end', f"{k}:\n", ('label',))
            self.props.insert('end', f"{val}\n\n")
        self.props.tag_config('label', foreground='#555',
                              font=('Menlo', 10, 'bold'))

    # --- Буфер обмена / контекстные меню ---
    def _copy_text(self, text):
        if text is None:
            return
        set_clipboard(self.master, str(text))
        self._update_status("Скопировано в буфер обмена")

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
        """Пропускать навигацию/выделение/копирование, блокировать всё, что меняет текст."""
        # Пропустить комбинации с Cmd/Ctrl (копирование, выделить всё) и модификаторы
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
        """Копировать выбранную строку списка (имя, логин, e-mail, состояние) через табуляцию."""
        sel = self.tree.selection()
        if not sel:
            return 'break'
        u = self.users[int(sel[0])]
        self._copy_text("\t".join(str(x or '') for x in (
            u['name'], u['sAMAccountName'], u['mail'], u['description'], u['state'])))
        return 'break'

    def _show_user_menu(self, event):
        # Сначала выделить строку под курсором
        iid = self.tree.identify_row(event.y)
        if iid:
            self.tree.selection_set(iid)
            self.tree.focus(iid)
        sel = self.tree.selection()
        if not sel:
            return 'break'
        u = self.users[int(sel[0])]

        m = tk.Menu(self, tearoff=0)
        m.add_command(label="Копировать логин",
                      command=lambda: self._copy_text(u['sAMAccountName']))
        m.add_command(label="Копировать отображаемое имя",
                      command=lambda: self._copy_text(u['name']))
        m.add_command(label="Копировать e-mail",
                      command=lambda: self._copy_text(u['mail']),
                      state='normal' if u.get('mail') else 'disabled')
        m.add_command(label="Копировать UPN",
                      command=lambda: self._copy_text(u['userPrincipalName']),
                      state='normal' if u.get('userPrincipalName') else 'disabled')
        m.add_command(label="Копировать DN",
                      command=lambda: self._copy_text(u['dn']))
        m.add_command(label="Копировать все свойства",
                      command=self._copy_all_props)
        m.add_separator()
        m.add_command(label="Включить", command=self.on_enable)
        m.add_command(label="Отключить", command=self.on_disable)
        m.add_command(label="Разблокировать", command=self.on_unlock)
        m.add_command(label="Сбросить пароль...", command=self.on_reset)
        m.add_separator()
        m.add_command(label="Группы...", command=self.on_groups)
        m.add_command(label="Переместить (OU)...", command=self.on_move)
        m.add_command(label="Изменить...", command=self.on_edit)
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
        # Определить, на какой строке свойства стоит курсор
        idx = self.props.index(f"@{event.x},{event.y}")
        line = int(idx.split('.')[0])
        row_val = None
        row_key = None
        cur = 1
        for k, v in rows:
            # каждое свойство занимает 3 строки: название, значение, пустая
            if line in (cur, cur + 1):
                row_key, row_val = k, v
                break
            cur += 3

        m = tk.Menu(self, tearoff=0)
        m.add_command(label="Копировать выделенное",
                      command=self._copy_props_selection,
                      state='normal' if has_sel else 'disabled')
        if row_val is not None:
            m.add_command(label=f"Копировать значение ({row_key})",
                          command=lambda v=row_val: self._copy_text(v))
        m.add_command(label="Копировать все свойства", command=self._copy_all_props)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()
        return 'break'

    # --- Действия ---
    def on_enable(self):
        u = self._selected_user()
        if not u:
            return
        try:
            self.client.enable_account(u['dn'])
            messagebox.showinfo("Готово", "Учётная запись включена.")
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror("Ошибка", str(ex))

    def on_disable(self):
        u = self._selected_user()
        if not u:
            return
        if not messagebox.askyesno(
                "Подтверждение",
                f"Отключить учётную запись '{u['sAMAccountName']}'?"):
            return
        try:
            self.client.disable_account(u['dn'])
            messagebox.showinfo("Готово", "Учётная запись отключена.")
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror("Ошибка", str(ex))

    def on_unlock(self):
        u = self._selected_user()
        if not u:
            return
        try:
            self.client.unlock_account(u['dn'])
            messagebox.showinfo("Готово", "Учётная запись разблокирована.")
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror("Ошибка", str(ex))

    def on_reset(self):
        u = self._selected_user()
        if not u:
            return
        ResetPasswordDialog(self.master, self.client, u,
                            on_done=lambda: self._refresh_selected(u['dn']))

    def on_groups(self):
        u = self._selected_user()
        if not u:
            return
        GroupsDialog(self.master, self.client, u)

    def on_move(self):
        u = self._selected_user()
        if not u:
            return
        MoveDialog(self.master, self.client, u,
                   on_done=self.do_search)

    def on_edit(self):
        u = self._selected_user()
        if not u:
            return
        EditDialog(self.master, self.client, u,
                   on_done=lambda: self._refresh_selected(u['dn']))

    def on_create(self):
        CreateDialog(self.master, self.client, on_done=self.do_search,
                     default_ou=self._current_base())


class ResetPasswordDialog(tk.Toplevel):
    def __init__(self, master, client, user, on_done=None):
        super().__init__(master)
        self.client = client
        self.user = user
        self.on_done = on_done
        self.title("Сброс пароля")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text=f"Пользователь: {user['name']} "
                            f"({user['sAMAccountName']})",
                  font=('', 12, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 12))
        ttk.Label(frm, text="Новый пароль:").grid(row=1, column=0, sticky='w')
        self.e1 = ttk.Entry(frm, width=30, show='•')
        self.e1.grid(row=1, column=1, pady=4)
        ttk.Label(frm, text="Подтверждение:").grid(row=2, column=0, sticky='w')
        self.e2 = ttk.Entry(frm, width=30, show='•')
        self.e2.grid(row=2, column=1, pady=4)
        self.v_change = tk.BooleanVar(value=True)
        self.v_unlock = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="Сменить пароль при следующем входе",
                        variable=self.v_change).grid(
            row=3, column=0, columnspan=2, sticky='w', pady=(8, 0))
        ttk.Checkbutton(frm, text="Разблокировать учётную запись",
                        variable=self.v_unlock).grid(
            row=4, column=0, columnspan=2, sticky='w')
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=300)
        self.lbl.grid(row=5, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, columnspan=2, sticky='e', pady=(12, 0))
        ttk.Button(btns, text="Применить", command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена", command=self.destroy).grid(
            row=0, column=1)
        self.e1.focus_set()

    def _apply(self):
        if not self.e1.get():
            self.lbl.config(text="Введите новый пароль.")
            return
        if self.e1.get() != self.e2.get():
            self.lbl.config(text="Пароли не совпадают.")
            return
        try:
            self.client.reset_password(
                self.user['dn'], self.e1.get(),
                unlock=self.v_unlock.get(),
                change_at_logon=self.v_change.get())
            messagebox.showinfo("Готово", "Пароль сброшен.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class MoveDialog(tk.Toplevel):
    def __init__(self, master, client, user, on_done=None):
        super().__init__(master)
        self.client = client
        self.user = user
        self.on_done = on_done
        self.title("Перемещение в подразделение")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text=f"Пользователь: {user['name']} "
                            f"({user['sAMAccountName']})",
                  font=('', 12, 'bold')).grid(row=0, column=0, sticky='w',
                                              pady=(0, 10))
        parent = user['dn'].split(',', 1)[1] if ',' in user['dn'] else ''
        ttk.Label(frm, text="Текущее размещение:").grid(row=1, column=0,
                                                        sticky='w')
        cur = ttk.Entry(frm, width=60)
        cur.insert(0, parent)
        cur.config(state='readonly')
        cur.grid(row=2, column=0, sticky='ew', pady=(2, 8))
        ttk.Label(frm, text="Целевой контейнер (OU):").grid(row=3, column=0,
                                                            sticky='w')
        dest_row = ttk.Frame(frm)
        dest_row.grid(row=4, column=0, sticky='ew', pady=2)
        dest_row.columnconfigure(0, weight=1)
        self.combo = ttk.Combobox(dest_row, width=52)
        self.combo.grid(row=0, column=0, sticky='ew')
        ttk.Button(dest_row, text="Обзор…", width=8,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))
        try:
            self.combo['values'] = self.client.list_ous()
        except Exception:
            pass
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=5, column=0, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, sticky='e', pady=(12, 0))
        ttk.Button(btns, text="Переместить", command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена", command=self.destroy).grid(
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
            self.lbl.config(text="Укажите целевой контейнер.")
            return
        try:
            self.client.move_user(self.user['dn'], dest)
            messagebox.showinfo("Готово", "Пользователь перемещён.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class GroupPickerDialog(tk.Toplevel):
    """Выбор одной или нескольких групп доступа из справочника AD."""

    def __init__(self, master, client, exclude_dns=None):
        super().__init__(master)
        self.client = client
        self.exclude = set((d or '').lower() for d in (exclude_dns or []))
        self.selected = []
        self.title("Выбор групп доступа")
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
        ttk.Label(top, text="Фильтр:").grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(top, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self._load())
        ttk.Button(top, text="Найти", command=self._load).grid(
            row=0, column=2, padx=(6, 0))

        scope = (f"Группы из подразделения «{ACCESS_GROUPS_OU_NAME}»"
                 if ACCESS_GROUPS_OU_NAME else "Группы домена")
        ttk.Label(
            frm,
            text=f"{scope} (Cmd-клик — множественный выбор):").grid(
            row=1, column=0, columnspan=2, sticky='w', pady=(10, 4))
        self.listbox = tk.Listbox(frm, selectmode='extended')
        self.listbox.grid(row=2, column=0, sticky='nsew')
        sb = ttk.Scrollbar(frm, orient='vertical', command=self.listbox.yview)
        sb.grid(row=2, column=1, sticky='ns')
        self.listbox.config(yscrollcommand=sb.set)

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Выбрать", command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена", command=self.destroy).grid(
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
            messagebox.showerror("Ошибка", str(ex))
            self._all = []
        finally:
            self.config(cursor='')
        self.listbox.delete(0, 'end')
        for g in self._all:
            self.listbox.insert('end', g['cn'])
        if not self._all:
            self.listbox.insert('end', "(групп не найдено)")
            self.listbox.itemconfig(0, foreground='gray')

    def _ok(self):
        # Пропускаем строку-заглушку, если групп нет
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
        self.title("Членство в группах")
        self.grab_set()
        frm = ttk.Frame(self, padding=16)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(1, weight=1)
        frm.columnconfigure(0, weight=1)
        ttk.Label(frm, text=f"Группы: {user['name']} ({user['sAMAccountName']})",
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
        ttk.Button(btns, text="Добавить...", command=self._add).grid(
            row=0, column=0)
        ttk.Button(btns, text="Убрать выбранные", command=self._remove).grid(
            row=0, column=1, padx=(8, 0))
        ttk.Button(btns, text="Закрыть", command=self.destroy).grid(
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
            messagebox.showerror("Ошибка", str(ex))

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
                messagebox.showerror("Ошибка", f"{g['cn']}: {ex}")
        if added:
            self._reload()

    def _remove(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        if not messagebox.askyesno("Подтверждение",
                                   f"Удалить из выбранных групп ({len(sel)})?"):
            return
        for i in sel:
            try:
                self.client.remove_from_group(self.user['dn'],
                                              self.groups[i]['dn'])
            except Exception as ex:
                messagebox.showerror("Ошибка",
                                     f"{self.groups[i]['cn']}: {ex}")
        self._reload()


class EditDialog(tk.Toplevel):
    FIELDS = [
        ("Отображаемое имя", 'displayName'),
        ("E-mail", 'mail'),
        ("Должность", 'title'),
        ("Отдел", 'department'),
        ("Компания", 'company'),
        ("Кабинет", 'physicalDeliveryOfficeName'),
        ("Телефон", 'telephoneNumber'),
        ("Описание", 'description'),
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
        self.title("Изменение свойств")
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
        # Группы доступа (Member Of) — применяются сразу
        grp = ttk.LabelFrame(frm, text="Группы доступа (Member Of)")
        grp.grid(row=r, column=0, columnspan=2, sticky='ew', pady=(10, 0))
        grp.columnconfigure(0, weight=1)
        self.grp_list = tk.Listbox(grp, height=6, selectmode='extended')
        self.grp_list.grid(row=0, column=0, sticky='ew', padx=6, pady=6)
        gsb = ttk.Scrollbar(grp, orient='vertical', command=self.grp_list.yview)
        gsb.grid(row=0, column=1, sticky='ns')
        self.grp_list.config(yscrollcommand=gsb.set)
        gbtns = ttk.Frame(grp)
        gbtns.grid(row=1, column=0, columnspan=2, sticky='w', padx=6, pady=(0, 6))
        ttk.Button(gbtns, text="Добавить...", command=self._add_groups).grid(
            row=0, column=0)
        ttk.Button(gbtns, text="Убрать выбранные",
                   command=self._remove_groups).grid(row=0, column=1, padx=(8, 0))
        self.groups = []
        self._reload_groups()

        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=r + 1, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=r + 2, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Сохранить", command=self._save).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена", command=self.destroy).grid(
            row=0, column=1)

    def _reload_groups(self):
        self.grp_list.delete(0, 'end')
        try:
            self.groups = self.client.get_user_groups(self.user['dn'])
            for g in self.groups:
                self.grp_list.insert('end', g['cn'])
        except Exception as ex:
            messagebox.showerror("Ошибка", str(ex))

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
                messagebox.showerror("Ошибка", f"{g['cn']}: {ex}")
        if added:
            self._reload_groups()

    def _remove_groups(self):
        sel = self.grp_list.curselection()
        if not sel:
            return
        if not messagebox.askyesno("Подтверждение",
                                   f"Удалить из выбранных групп ({len(sel)})?"):
            return
        for i in sel:
            try:
                self.client.remove_from_group(self.user['dn'],
                                              self.groups[i]['dn'])
            except Exception as ex:
                messagebox.showerror("Ошибка", f"{self.groups[i]['cn']}: {ex}")
        self._reload_groups()

    def _save(self):
        attrs = {attr: e.get() for attr, e in self.entries.items()}
        try:
            self.client.update_attributes(self.user['dn'], attrs)
            messagebox.showinfo("Готово", "Изменения сохранены.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class OUTreePickerDialog(tk.Toplevel):
    """Выбор подразделения (OU) навигацией по дереву домена."""

    def __init__(self, master, client, initial=None):
        super().__init__(master)
        self.client = client
        self.selected_dn = None
        self.title("Выбор подразделения (OU)")
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
        ttk.Button(btns, text="Выбрать", command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена", command=self.destroy).grid(
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
    """Компактный виджет выбора даты (без внешних зависимостей).
    Возвращает дату через колбэк on_pick(datetime.date)."""

    MONTHS = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль',
              'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь']
    WEEKDAYS = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']

    def __init__(self, master, initial=None, on_pick=None):
        super().__init__(master)
        self.on_pick = on_pick
        self.title("Выбор даты")
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

        cal = calendar.Calendar(firstweekday=0)  # понедельник первый
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
        self.title("Создание пользователя")
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()

        def row(r, label):
            ttk.Label(frm, text=label).grid(row=r, column=0, sticky='w', pady=3)
            e = ttk.Entry(frm, width=36)
            e.grid(row=r, column=1, pady=3)
            return e

        self.e_given = row(0, "Имя:")
        self.e_sur = row(1, "Фамилия:")
        self.e_display = row(2, "Отображаемое имя:")
        self.e_sam = row(3, "Логин (sAMAccountName):")
        self.e_upn = row(4, "UPN-суффикс:")
        self.e_mail = row(5, "E-mail:")
        self.e_desc = row(6, "Описание:")
        ttk.Label(frm, text="Пароль:").grid(row=7, column=0, sticky='w', pady=3)
        self.e_pass = ttk.Entry(frm, width=36, show='•')
        self.e_pass.grid(row=7, column=1, pady=3)

        # Выбор подразделения (OU), где будет создан пользователь
        ttk.Label(frm, text="Подразделение (OU):").grid(
            row=8, column=0, sticky='w', pady=3)
        ou_row = ttk.Frame(frm)
        ou_row.grid(row=8, column=1, sticky='ew', pady=3)
        self.cmb_ou = ttk.Combobox(ou_row, width=27)
        self.cmb_ou.grid(row=0, column=0)
        ttk.Button(ou_row, text="Обзор…", width=8,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))
        self._fill_ou(default_ou)

        # Срок действия учётной записи
        ttk.Label(frm, text="Срок действия:").grid(
            row=9, column=0, sticky='w', pady=3)
        exp_row = ttk.Frame(frm)
        exp_row.grid(row=9, column=1, sticky='w', pady=3)
        self.v_expire = tk.BooleanVar(value=False)
        ttk.Checkbutton(exp_row, text="Действует по (вкл.):",
                        variable=self.v_expire,
                        command=self._toggle_expire).grid(row=0, column=0)
        self.e_expire = ttk.Entry(exp_row, width=12)
        self.e_expire.grid(row=0, column=1, padx=(6, 0))
        self.e_expire.insert(0, DATE_HINT)
        self.e_expire.config(state='disabled')
        self.btn_cal = ttk.Button(exp_row, text="📅", width=3,
                                  command=self._open_calendar, state='disabled')
        self.btn_cal.grid(row=0, column=2, padx=(4, 0))

        # Группы доступа при создании
        grp = ttk.LabelFrame(frm, text="Группы доступа при создании")
        grp.grid(row=10, column=0, columnspan=2, sticky='ew', pady=(8, 0))
        grp.columnconfigure(0, weight=1)
        self.grp_list = tk.Listbox(grp, height=4, selectmode='extended')
        self.grp_list.grid(row=0, column=0, sticky='ew', padx=6, pady=6)
        gsb = ttk.Scrollbar(grp, orient='vertical', command=self.grp_list.yview)
        gsb.grid(row=0, column=1, sticky='ns')
        self.grp_list.config(yscrollcommand=gsb.set)
        gb = ttk.Frame(grp)
        gb.grid(row=1, column=0, columnspan=2, sticky='w', padx=6, pady=(0, 6))
        ttk.Button(gb, text="Выбрать группы...", command=self._pick_groups).grid(
            row=0, column=0)
        ttk.Button(gb, text="Убрать выбранные", command=self._unpick).grid(
            row=0, column=1, padx=(8, 0))

        self.v_change = tk.BooleanVar(value=True)
        self.v_enabled = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text="Сменить пароль при следующем входе",
                        variable=self.v_change).grid(
            row=11, column=1, sticky='w', pady=(6, 0))
        ttk.Checkbutton(frm, text="Учётная запись включена",
                        variable=self.v_enabled).grid(
            row=12, column=1, sticky='w')

        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=13, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=14, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text="Создать", command=self._create).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text="Отмена", command=self.destroy).grid(
            row=0, column=1)

        # Предзаполнить UPN-суффикс
        self.e_upn.insert(0, '@' + (client.upn_suffix or ''))

        # Автоматически добавить группы по умолчанию
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
                text="Не найдены группы по умолчанию: " + ", ".join(missing))

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
            self.lbl.config(text="Укажите логин (sAMAccountName).")
            return
        if not self.e_pass.get():
            self.lbl.config(text="Укажите пароль.")
            return

        # Срок действия учётной записи
        expire = None
        if self.v_expire.get():
            txt = self.e_expire.get().strip()
            try:
                expire = parse_date(txt)
            except ValueError:
                self.lbl.config(
                    text=f"Срок действия: укажите дату в формате {DATE_HINT}.")
                return

        # Проверка, что логин ещё не занят в домене
        try:
            if self.client.user_exists(sam):
                self.lbl.config(
                    text=f"Пользователь с логином «{sam}» уже существует в домене.")
                return
        except Exception:
            pass  # если проверка не удалась — попытаемся создать, AD сам отклонит дубликат

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
                    "Пользователь создан, но не во все группы",
                    "\n".join(errs))
            else:
                messagebox.showinfo("Готово", "Пользователь создан.")
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


def _install_mac_keybindings(root):
    """Горячие клавиши в стиле macOS: Cmd-удаление слова в полях ввода
    и Cmd-клик для множественного выбора в списках."""
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
    root.withdraw()  # скрыть до успешного входа

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
    edit_menu.add_command(label="Вырезать", accelerator="Cmd+X",
                          command=lambda: root.focus_get() and
                          root.focus_get().event_generate('<<Cut>>'))
    edit_menu.add_command(label="Копировать", accelerator="Cmd+C",
                          command=win._on_copy_shortcut)
    edit_menu.add_command(label="Вставить", accelerator="Cmd+V",
                          command=lambda: root.focus_get() and
                          root.focus_get().event_generate('<<Paste>>'))
    edit_menu.add_separator()
    edit_menu.add_command(label="Выделить всё", accelerator="Cmd+A",
                          command=win._on_select_all)
    menubar.add_cascade(label="Правка", menu=edit_menu)
    root.config(menu=menubar)

    root.mainloop()


if __name__ == '__main__':
    main()
