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
import socket
import json
import calendar
import datetime
import subprocess
import importlib


# ============================================================================
#  Localization (EN / RU)
# ============================================================================
LANG = 'en'   # current interface language: 'en' or 'ru'

def T(s):
    """Translate an interface string into the current language."""
    if LANG == 'ru':
        return RU_STRINGS.get(s, s)
    return s


def set_lang(lang):
    global LANG
    LANG = 'ru' if lang == 'ru' else 'en'


RU_STRINGS = {
    "Tkinter module not found (required for the GUI).\nInstall it: brew install python-tk, or use Python from python.org.\n": "Не найден модуль Tkinter (нужен для графического интерфейса).\nУстановите его: brew install python-tk  — либо используйте Python с python.org.\n",
    "Checking dependencies": "Проверка зависимостей",
    "Missing components: {a0}\n\nInstalling, please wait…": "Не установлены компоненты: {a0}\n\nВыполняется установка, подождите…",
    "Installing component: {a0}\nPlease wait…": "Устанавливается компонент: {a0}\nПодождите…",
    "Failed to install dependencies": "Не удалось установить зависимости",
    "Could not install automatically: ": "Не удалось автоматически установить: ",
    "\n\nInstall manually in a terminal:\n    pip3 install ": "\n\nУстановите вручную в терминале:\n    pip3 install ",
    "\n\nIf pip is not found:\n    python3 -m ensurepip --upgrade": "\n\nЕсли pip не найден:\n    python3 -m ensurepip --upgrade",
    "No active session to switch domains.": "Нет активной сессии для смены домена.",
    "Locked": "Заблокирован",
    "Disabled": "Отключено",
    "Active": "Активна",
    "Password reset requires a secure connection (LDAPS). Reconnect using LDAPS (port 636).": "Сброс пароля требует защищённого соединения (LDAPS). Переподключитесь по LDAPS (порт 636).",
    "Group '{a0}' not found.": "Группа '{a0}' не найдена.",
    "User created, but the password cannot be set without LDAPS. Reconnect using LDAPS to set the password.": "Пользователь создан, но задать пароль без LDAPS нельзя. Переподключитесь по LDAPS для установки пароля.",
    "never / not set": "никогда / не задано",
    "never": "никогда",
    "at next logon (change required)": "при следующем входе (требуется смена)",
    "never (password does not expire)": "никогда (пароль не истекает)",
    " (expired)": " (просрочен)",
    "Connect to Active Directory": "Подключение к Active Directory",
    "Connect to the Active Directory domain": "Подключение к домену Active Directory",
    "Saved domain:": "Сохранённый домен:",
    "Server / DC:": "Сервер / DC:",
    "User:": "Пользователь:",
    "Password:": "Пароль:",
    "LDAPS (encryption, port 636)": "LDAPS (шифрование, порт 636)",
    "Validate server certificate": "Проверять сертификат сервера",
    "Save domain to the list": "Сохранить домен в список",
    "Connect": "Подключиться",
    "Cancel": "Отмена",
    "Remove domain": "Удаление домена",
    "Remove '{a0}' from the list?": "Удалить '{a0}' из списка?",
    "Fill in server, user, and password.": "Заполните сервер, пользователя и пароль.",
    "Connecting...": "Подключение...",
    "Failed to connect: {a0}": "Не удалось подключиться: {a0}",
    "Error: {a0}": "Ошибка: {a0}",
    "Search:": "Поиск:",
    "Find": "Найти",
    "Refresh": "Обновить",
    "Create user": "Создание пользователя",
    "Domain:": "Домен:",
    "Switch domain": "Сменить домен",
    "Show:": "Показывать:",
    "Users": "Пользователи",
    "Computers": "Компьютеры",
    "Show from nested OUs": "Показывать из вложенных OU",
    "No domain selected": "Домен не выбран",
    "Select from the list or enter a domain/controller.": "Выберите из списка или введите домен/контроллер.",
    "Access error": "Ошибка доступа",
    "Failed to connect to domain \"{a0}\" with the current account ({a1}).\n\nInsufficient rights or the domain is unavailable:\n{a2}": "Не удалось подключиться к домену «{a0}» под текущей учётной записью ({a1}).\n\nНедостаточно прав или домен недоступен:\n{a2}",
    "Domain changed": "Домен изменён",
    "Connected to domain \"{a0}\" as {a1}.": "Подключено к домену «{a0}» под учётной записью {a1}.",
    "Organizational units": "Подразделения",
    "User properties": "Свойства пользователя",
    "Actions": "Действия",
    "Name": "Имя",
    "DNS name": "DNS-имя",
    "Operating system": "Операционная система",
    "Description": "Описание",
    "State": "Состояние",
    "Login": "Логин",
    "Enable": "Включить",
    "Disable": "Отключить",
    "Rename...": "Переименовать...",
    "Move (OU)": "Переместить (OU)",
    "Edit...": "Изменить...",
    "Delete": "Удалить",
    "Unlock": "Разблокировать",
    "Reset password": "Сброс пароля",
    "Pwd never expires": "Бессрочный пароль",
    "Groups...": "Группы...",
    "Computer properties": "Свойства компьютера",
    "Connected: {a0} ({a1})   |   Base: {a2}": "Подключено: {a0} ({a1})   |   База: {a2}",
    "domain": "домен",
    " (+nested)": " (+вложенные)",
    "Found: {a0}  |  scope: {a1}": "Найдено: {a0}  |  область: {a1}",
    "Search error": "Ошибка поиска",
    "No user selected": "Не выбран пользователь",
    "Select a user in the list first.": "Сначала выберите пользователя в списке.",
    "Multiple objects selected": "Выбрано несколько объектов",
    "This action applies to a single object.\nSelect exactly one item in the list.": "Это действие применимо к одному объекту.\nВыберите ровно один элемент списка.",
    "Selected objects: {a0}\n\nAvailable bulk actions:\n  Enable / Disable / Move (OU)\n  Add to groups (users)": "Выбрано объектов: {a0}\n\nДоступные групповые действия:\n  Включить / Отключить / Переместить (OU)\n  Добавить в группы (пользователи)",
    "Display name": "Отображаемое имя",
    "First name": "Имя",
    "Last name": "Фамилия",
    "Yes": "Да",
    "No": "Нет",
    "Title": "Должность",
    "Department": "Отдел",
    "Company": "Компания",
    "Office": "Кабинет",
    "Phone": "Телефон",
    "Password last set": "Пароль изменён",
    "Password never expires": "Срок действия пароля не ограничен",
    "Password change required": "Требуется смена пароля",
    "Bad password attempts": "Неверных попыток входа",
    "Last bad password": "Последний неверный ввод",
    "Last logon": "Последний вход",
    "Created": "Создан",
    "Expires": "Истекает",
    "Account name": "Имя учётной записи",
    "OS version": "Версия ОС",
    "Copied to clipboard": "Скопировано в буфер обмена",
    "Selected: {a0}": "Выбрано: {a0}",
    "Move (OU)...": "Переместить (OU)...",
    "Add to groups...": "Добавить в группы...",
    "Copy rows": "Копировать строки",
    "Copy login": "Копировать логин",
    "Copy display name": "Копировать отображаемое имя",
    "Copy e-mail": "Копировать e-mail",
    "Copy UPN": "Копировать UPN",
    "Copy DN": "Копировать DN",
    "Copy all properties": "Копировать все свойства",
    "Reset password...": "Сбросить пароль...",
    "Password never expires  ✓": "Срок действия пароля не ограничен  ✓",
    "Copy name": "Копировать имя",
    "Copy DNS name": "Копировать DNS-имя",
    "Copy account name": "Копировать имя учётной записи",
    "Copy selection": "Копировать выделенное",
    "Copy value ({a0})": "Копировать значение ({a0})",
    "Partially completed": "Выполнено частично",
    "{a0}: {a1} of {a2}.\n\nErrors:\n": "{a0}: {a1} из {a2}.\n\nОшибки:\n",
    "Done": "Готово",
    "No object selected": "Не выбран объект",
    "Select one or more objects in the list.": "Выберите один или несколько объектов в списке.",
    "Account enabled.": "Учётная запись включена.",
    "Error": "Ошибка",
    "Confirm": "Подтверждение",
    "Enable {a0} accounts?": "Включить учётные записи: {a0}?",
    "Enabled": "Включено",
    "Disable account '{a0}'?": "Отключить учётную запись '{a0}'?",
    "Account disabled.": "Учётная запись отключена.",
    "Disable {a0} accounts?": "Отключить учётные записи: {a0}?",
    "Account unlocked.": "Учётная запись разблокирована.",
    "Clear the 'password never expires' flag for '{a0}'?\n\nThe password will expire per the domain policy.": "Снять флаг «срок действия пароля не ограничен» у '{a0}'?\n\nПароль будет истекать по политике домена.",
    "Set the 'password never expires' flag for '{a0}'?\n\nIf a password change at next logon is pending, the requirement will be removed and the current password stays valid (same as in ADUC).": "Установить флаг «срок действия пароля не ограничен» у '{a0}'?\n\nЕсли у пользователя стоит требование смены пароля при следующем входе, оно будет снято, и прежний пароль останется действительным (как в оснастке ADUC).",
    "Flag cleared: the password expires per the domain policy.": "Флаг снят: пароль истекает по политике домена.",
    "Flag set: the password never expires.": "Флаг установлен: срок действия пароля не ограничен.",
    "\n\nThe 'change password at next logon' requirement was removed; the current password stays valid.": "\n\nТребование смены пароля при следующем входе снято; прежний пароль остаётся действительным.",
    "Select one or more users in the list.": "Выберите одного или нескольких пользователей в списке.",
    "Add to groups": "Добавление в группы",
    "Add {a0} users to {a1} group(s)?\n\nGroups: {a2}": "Добавить пользователей ({a0}) в группы ({a1})?\n\nГруппы: {a2}",
    "Added: {a0}.": "Добавлено: {a0}.",
    "\nAlready members (skipped): {a0}.": "\nУже состояли (пропущено): {a0}.",
    "\n\nErrors:\n": "\n\nОшибки:\n",
    "Confirm deletion": "Подтверждение удаления",
    "Delete object '{a0}'?\n\nThis operation is irreversible.": "Удалить объект «{a0}»?\n\nЭта операция необратима.",
    "Object deleted.": "Объект удалён.",
    "User: {a0} ({a1})": "Пользователь: {a0} ({a1})",
    "New password:": "Новый пароль:",
    "Confirm:": "Подтверждение:",
    "Change password at next logon": "Сменить пароль при следующем входе",
    "Unlock the account": "Разблокировать учётную запись",
    "Apply": "Применить",
    "Enter a new password.": "Введите новый пароль.",
    "Passwords do not match.": "Пароли не совпадают.",
    "Password reset.": "Пароль сброшен.",
    "Move to organizational unit": "Перемещение в подразделение",
    "Object: {a0} ({a1})": "Объект: {a0} ({a1})",
    "Objects selected: {a0} ({a1})": "Выбрано объектов: {a0} ({a1})",
    "(objects are in different containers)": "(объекты в разных контейнерах)",
    "Current location:": "Текущее размещение:",
    "Target container (OU):": "Целевой контейнер (OU):",
    "Browse…": "Обзор…",
    "Move": "Переместить",
    "Specify a target container.": "Укажите целевой контейнер.",
    "Object moved.": "Объект перемещён.",
    "Moved: {a0} of {a1}.\n\nErrors:\n": "Перемещено: {a0} из {a1}.\n\nОшибки:\n",
    "Objects moved: {a0}.": "Объектов перемещено: {a0}.",
    "Rename object": "Переименование объекта",
    "Object: {a0}": "Объект: {a0}",
    "New name:": "Новое имя:",
    "Rename": "Переименовать",
    "Enter a name.": "Введите имя.",
    "Object renamed.": "Объект переименован.",
    "Select groups": "Выбор групп доступа",
    "Filter:": "Фильтр:",
    "Groups from OU \"{a0}\"": "Группы из подразделения «{a0}»",
    "Domain groups": "Группы домена",
    "{a0} (Cmd-click — multi-select):": "{a0} (Cmd-клик — множественный выбор):",
    "Select": "Выбрать",
    "(no groups found)": "(групп не найдено)",
    "Group membership": "Членство в группах",
    "Groups: {a0} ({a1})": "Группы: {a0} ({a1})",
    "Add...": "Добавить...",
    "Remove selected": "Убрать выбранные",
    "Close": "Закрыть",
    "Remove from the selected groups ({a0})?": "Удалить из выбранных групп ({a0})?",
    "Edit computer": "Изменить компьютер",
    "Name:": "Имя:",
    "DNS name:": "DNS-имя:",
    "Description:": "Описание:",
    "Save": "Сохранить",
    "Edit properties": "Изменение свойств",
    "Group membership (Member Of)": "Группы доступа (Member Of)",
    "Changes saved.": "Изменения сохранены.",
    "Select organizational unit (OU)": "Выбор подразделения (OU)",
    "January": "Январь",
    "February": "Февраль",
    "March": "Март",
    "April": "Апрель",
    "May": "Май",
    "June": "Июнь",
    "July": "Июль",
    "August": "Август",
    "September": "Сентябрь",
    "October": "Октябрь",
    "November": "Ноябрь",
    "December": "Декабрь",
    "Mon": "Пн",
    "Tue": "Вт",
    "Wed": "Ср",
    "Thu": "Чт",
    "Fri": "Пт",
    "Sat": "Сб",
    "Sun": "Вс",
    "Select date": "Выбор даты",
    "First name:": "Имя:",
    "Last name:": "Фамилия:",
    "Display name:": "Отображаемое имя:",
    "Login (sAMAccountName):": "Логин (sAMAccountName):",
    "UPN suffix:": "UPN-суффикс:",
    "Organizational unit (OU):": "Подразделение (OU):",
    "Expires:": "Срок действия:",
    "Valid through (incl.):": "Действует по (вкл.):",
    "Groups on creation": "Группы доступа при создании",
    "Select groups...": "Выбрать группы...",
    "Account enabled": "Учётная запись включена",
    "Create": "Создать",
    "Default groups not found: ": "Не найдены группы по умолчанию: ",
    "Specify a login (sAMAccountName).": "Укажите логин (sAMAccountName).",
    "Specify a password.": "Укажите пароль.",
    "Expiration: enter a date in {a0} format.": "Срок действия: укажите дату в формате {a0}.",
    "A user with login \"{a0}\" already exists in the domain.": "Пользователь с логином «{a0}» уже существует в домене.",
    "User created, but not added to all groups": "Пользователь создан, но не во все группы",
    "User created.": "Пользователь создан.",
    "Cut": "Вырезать",
    "Copy": "Копировать",
    "Paste": "Вставить",
    "Select All": "Выделить всё",
    "Edit": "Правка",
    'Container on the left — its users on the right; the search spans the whole subtree. Cmd-click — multi-select.':
        'Слева контейнер — справа его пользователи; поиск идёт по всему поддереву. Cmd-клик — множественный выбор.',
    'Domain controller "{a0}" is unreachable (port {a1}).\n'
    'Check the server name and network connectivity.':
        'Контроллер домена «{a0}» недоступен (порт {a1}).\n'
        'Проверьте имя сервера и сетевую доступность.',
    '(no users found)': '(пользователи не найдены)',
    'Category': 'Категория',
    'Category:': 'Категория:',
    'Container (OU):': 'Контейнер (OU):',
    'Create group': 'Создание группы',
    'Create group...': 'Создать группу...',
    'Delete {a0} groups?\n\nThis operation is irreversible.': 'Удалить группы ({a0})?\n\nЭта операция необратима.',
    'Deleted: {a0}.': 'Удалено: {a0}.',
    'Distribution': 'Рассылки',
    'Domain local': 'Локальная в домене',
    'Edit group': 'Изменить группу',
    'Enter a group name.': 'Укажите имя группы.',
    'Global': 'Глобальная',
    'Group created.': 'Группа создана.',
    'Group members': 'Участники группы',
    'Group name:': 'Имя группы:',
    'Group properties': 'Свойства группы',
    'Group: {a0}': 'Группа: {a0}',
    'Groups': 'Группы',
    'Login:': 'Логин:',
    'Members': 'Участники',
    'Members...': 'Участники...',
    'Remove selected members ({a0}) from the group?': 'Удалить выбранных участников ({a0}) из группы?',
    'Removed: {a0}.': 'Удалено из группы: {a0}.',
    'Scope': 'Область',
    'Scope:': 'Область:',
    'Security': 'Безопасности',
    'Select users': 'Выбор пользователей',
    'Selected objects: {a0}\n\nAvailable bulk actions:\n  Move (OU) / Delete': 'Выбрано объектов: {a0}\n\nДоступные групповые действия:\n  Переместить (OU) / Удалить',
    'Universal': 'Универсальная',
    'Users (Cmd-click — multi-select):': 'Пользователи (Cmd-клик — множественный выбор):',
}


# Tkinter is required for the GUI
try:
    import tkinter as tk
    from tkinter import ttk, messagebox, simpledialog
except ImportError:
    sys.stderr.write(
        T('Tkinter module not found (required for the GUI).\nInstall it: brew install python-tk, or use Python from python.org.\n'))
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
    splash.title(T('Checking dependencies'))
    splash.geometry("420x150")
    splash.resizable(False, False)
    names = ", ".join(p for _, p in missing)
    lbl = tk.Label(
        splash, padx=20, pady=20, justify="left", font=("", 13),
        text=T('Missing components: {a0}\n\nInstalling, please wait…').format(a0=(names)))
    lbl.pack(expand=True, fill="both")
    splash.update()

    still_missing = []
    for mod_name, pip_name in missing:
        lbl.config(text=T('Installing component: {a0}\nPlease wait…').format(a0=(pip_name)))
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
        T('Failed to install dependencies'),
        T('Could not install automatically: ') + ", ".join(_failed) + T('\n\nInstall manually in a terminal:\n    pip3 install ') + " ".join(_failed) + T('\n\nIf pip is not found:\n    python3 -m ensurepip --upgrade'))
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

GROUP_ATTRS = [
    'cn', 'name', 'sAMAccountName', 'description', 'groupType',
    'distinguishedName', 'whenCreated', 'mail',
]

# groupType bits
GT_GLOBAL = 0x00000002
GT_DOMAIN_LOCAL = 0x00000004
GT_UNIVERSAL = 0x00000008
GT_SECURITY = 0x80000000

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

    def _read(self):
        try:
            with open(self.path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def load(self):
        return self._read().get('domains', [])

    def save(self, domains):
        data = self._read()
        data['domains'] = domains
        try:
            with open(self.path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def get_lang(self):
        """Saved interface language ('en'/'ru') or None."""
        lang = self._read().get('lang')
        return lang if lang in ('en', 'ru') else None

    def set_lang(self, lang):
        data = self._read()
        data['lang'] = 'ru' if lang == 'ru' else 'en'
        try:
            with open(self.path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
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

        # Fail fast when the directory server is unreachable: without this
        # probe the RESTARTABLE strategy would keep retrying for minutes.
        try:
            probe = socket.create_connection((host, port), timeout=5)
            probe.close()
        except OSError as ex:
            raise RuntimeError(
                T('Domain controller "{a0}" is unreachable (port {a1}).\nCheck the server name and network connectivity.').format(
                    a0=(host), a1=(port))) from ex

        # Bound automatic reconnect retries (defaults retry for a long time)
        try:
            from ldap3.utils.config import set_config_parameter
            set_config_parameter('RESTARTABLE_TRIES', 2)
            set_config_parameter('RESTARTABLE_SLEEPTIME', 1)
        except Exception:
            pass

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
            raise RuntimeError(T('No active session to switch domains.'))
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
            state = T('Locked')
        elif not enabled:
            state = T('Disabled')
        else:
            state = T('Active')

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
                T('Password reset requires a secure connection (LDAPS). Reconnect using LDAPS (port 636).'))
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
        state = T('Active') if enabled else T('Disabled')

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

    # ---- Group operations ----
    def search_ad_groups(self, query=None, base=None, scope=SUBTREE):
        """query — search text; base — container/OU DN; scope — LEVEL/SUBTREE.
        Returns all matching groups (paged, no limit)."""
        base = base or self.base_dn
        query = (query or '').strip().replace('*', '')
        if query:
            q = _escape_filter(query)
            flt = (
                "(&(objectCategory=group)"
                f"(|(cn=*{q}*)(name=*{q}*)(sAMAccountName=*{q}*)"
                f"(description=*{q}*)))"
            )
            scope = SUBTREE  # text search always spans the whole base subtree
        else:
            flt = "(objectCategory=group)"

        entries = self._paged_search(base, flt, GROUP_ATTRS, scope)
        result = [self._group_to_dict(e) for e in entries]
        result.sort(key=lambda x: (x.get('name') or '').lower())
        return result

    def get_group(self, dn):
        self.conn.search(dn, "(objectClass=group)", search_scope='BASE',
                         attributes=GROUP_ATTRS)
        if not self.conn.entries:
            return None
        return self._group_to_dict(self.conn.entries[0])

    def _group_to_dict(self, e):
        def v(attr, default=''):
            try:
                val = e[attr].value
                return val if val is not None else default
            except Exception:
                return default

        gt = v('groupType', 0) or 0
        try:
            gt = int(gt)
        except (ValueError, TypeError):
            gt = 0
        if gt < 0:
            gt += 2 ** 32
        if gt & GT_GLOBAL:
            scope = T('Global')
        elif gt & GT_DOMAIN_LOCAL:
            scope = T('Domain local')
        elif gt & GT_UNIVERSAL:
            scope = T('Universal')
        else:
            scope = ''
        category = T('Security') if gt & GT_SECURITY else T('Distribution')

        name = v('name') or v('cn') or str(e.entry_dn).split(',')[0][3:]
        return {
            'name': name,
            'cn': v('cn') or name,
            'sAMAccountName': v('sAMAccountName'),
            'description': v('description'),
            'mail': v('mail'),
            'scope': scope,
            'category': category,
            'groupType': gt,
            'dn': str(e.entry_dn),
            'whenCreated': v('whenCreated'),
            'is_group': True,
        }

    def get_group_members(self, dn):
        """Group members as [{'name', 'dn'}] read from the 'member' attribute."""
        self.conn.search(dn, "(objectClass=group)", search_scope='BASE',
                         attributes=['member'])
        if not self.conn.entries:
            return []
        member = self.conn.entries[0]['member'].value
        if member is None:
            return []
        if isinstance(member, str):
            member = [member]
        out = []
        for mdn in member:
            rdn = mdn.split(',', 1)[0]
            nm = rdn.split('=', 1)[1] if '=' in rdn else rdn
            nm = nm.replace('\\,', ',').replace('\\\\', '\\')
            out.append({'name': nm, 'dn': mdn})
        out.sort(key=lambda m: m['name'].lower())
        return out

    def create_group(self, ou, name, sam, description=None,
                     scope='global', security=True):
        """Create a group. scope: 'global' | 'domainlocal' | 'universal'."""
        if not ou:
            ou = "CN=Users," + self.base_dn
        dn = f"CN={_escape_dn(name)},{ou}"
        gt = {'global': GT_GLOBAL, 'domainlocal': GT_DOMAIN_LOCAL,
              'universal': GT_UNIVERSAL}.get(scope, GT_GLOBAL)
        if security:
            gt |= GT_SECURITY
        if gt >= 2 ** 31:
            gt -= 2 ** 32  # LDAP stores groupType as a signed 32-bit value
        attrs = {
            'objectClass': ['top', 'group'],
            'sAMAccountName': sam or name,
            'groupType': gt,
        }
        if description:
            attrs['description'] = description
        self.conn.add(dn, attributes=attrs)
        self._check()
        return dn

    def add_group_members(self, group_dn, user_dns):
        """Add users to a group one by one.
        Returns (added, already, errors[])."""
        added, already, errors = 0, 0, []
        for udn in user_dns:
            try:
                self.conn.modify(group_dn,
                                 {'member': [(MODIFY_ADD, [udn])]})
                self._check()
                added += 1
            except Exception as ex:
                msg = str(ex)
                if 'entryalreadyexists' in msg.lower().replace(' ', ''):
                    already += 1
                else:
                    errors.append(f"{udn}: {msg}")
        return added, already, errors

    def remove_group_members(self, group_dn, user_dns):
        """Remove users from a group one by one.
        Returns (removed, errors[])."""
        removed, errors = 0, []
        for udn in user_dns:
            try:
                self.conn.modify(group_dn,
                                 {'member': [(MODIFY_DELETE, [udn])]})
                self._check()
                removed += 1
            except Exception as ex:
                errors.append(f"{udn}: {ex}")
        return removed, errors

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
            raise RuntimeError(T("Group '{a0}' not found.").format(a0=(group_name)))
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
                    T('User created, but the password cannot be set without LDAPS. Reconnect using LDAPS to set the password.'))
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


MONTH_ABBR_EN = ['jan', 'feb', 'mar', 'apr', 'may', 'jun',
                 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']
MONTH_ABBR_RU = ['янв', 'фев', 'мар', 'апр', 'май', 'июн',
                 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']


def _month_abbr():
    """Month abbreviations for the current language."""
    return MONTH_ABBR_RU if LANG == 'ru' else MONTH_ABBR_EN


def date_hint():
    """Date format hint for the current language."""
    return "ДД МММ ГГГГ" if LANG == 'ru' else "YYYY-MMM-DD"


def fmt_date(dt, with_time=True):
    """Format a date/datetime as YYYY-mmm-DD (e.g. 2026-aug-14)."""
    if LANG == 'ru':
        s = f"{dt.day:02d} {_month_abbr()[dt.month - 1]} {dt.year:04d}"
    else:
        s = f"{dt.year:04d}-{_month_abbr()[dt.month - 1]}-{dt.day:02d}"
    if with_time and isinstance(dt, datetime.datetime):
        s += f" {dt.hour:02d}:{dt.minute:02d}"
    return s


def parse_date(txt):
    """Parse a date string in the current language format into datetime.date."""
    parts = txt.strip().lower().replace('-', ' ').replace('.', ' ').split()
    if len(parts) != 3:
        raise ValueError("bad date")
    mon_part = parts[1]
    if mon_part.isdigit():
        month = int(mon_part)
    else:
        month = _month_abbr().index(mon_part[:3]) + 1
    if LANG == 'ru':
        day, year = int(parts[0]), int(parts[2])
    else:
        year, day = int(parts[0]), int(parts[2])
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
        return T('never / not set')
    if num >= 0x7FFFFFFFFFFFFFFF:
        return T('never')
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
        return T('at next logon (change required)')
    if u.get('dontExpire'):
        return T('never (password does not expire)')
    exp = u.get('pwdExpiry')
    try:
        n = int(exp)
    except (TypeError, ValueError):
        return ''
    if n == 0:
        return ''
    if n >= 0x7FFFFFFFFFFFFFFF:
        return T('never')
    txt = filetime_to_str(n)
    # Mark if the date has already passed
    try:
        secs = n / 10_000_000 - 11644473600
        if datetime.datetime.fromtimestamp(secs) < datetime.datetime.now():
            txt += T(' (expired)')
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
        self.title(T('Connect to Active Directory'))
        self.resizable(False, False)
        # Take the grab and focus only after the window is actually mapped:
        # an immediate grab_set() on a not-yet-visible window silently fails
        # (fields would ignore input, e.g. after a language switch).
        self.after(150, self._grab_focus)

        frm = ttk.Frame(self, padding=18)
        frm.grid()

        ttk.Label(frm, text=T('Connect to the Active Directory domain'),
                  font=('', 13, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 12))

        # Saved-domain selection
        ttk.Label(frm, text=T('Saved domain:')).grid(row=1, column=0,
                                                       sticky='w', pady=4)
        dom_row = ttk.Frame(frm)
        dom_row.grid(row=1, column=1, sticky='ew', pady=4)
        self.cmb_domain = ttk.Combobox(dom_row, width=27, state='readonly')
        self.cmb_domain.grid(row=0, column=0)
        self.cmb_domain.bind('<<ComboboxSelected>>', self._on_pick)
        ttk.Button(dom_row, text="✕", width=3,
                   command=self._delete_profile).grid(row=0, column=1, padx=(4, 0))

        ttk.Label(frm, text=T('Server / DC:')).grid(row=2, column=0, sticky='w', pady=4)
        self.e_host = ttk.Entry(frm, width=34)
        self.e_host.grid(row=2, column=1, pady=4)

        ttk.Label(frm, text=T('User:')).grid(row=3, column=0, sticky='w', pady=4)
        self.e_user = ttk.Entry(frm, width=34)
        self.e_user.grid(row=3, column=1, pady=4)

        ttk.Label(frm, text=T('Password:')).grid(row=4, column=0, sticky='w', pady=4)
        self.e_pass = ttk.Entry(frm, width=34, show='•')
        self.e_pass.grid(row=4, column=1, pady=4)

        self.use_ssl = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text=T('LDAPS (encryption, port 636)'),
                        variable=self.use_ssl).grid(
            row=5, column=1, sticky='w', pady=(8, 0))

        self.verify = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm, text=T('Validate server certificate'),
                        variable=self.verify).grid(
            row=6, column=1, sticky='w')

        self.save_domain = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text=T('Save domain to the list'),
                        variable=self.save_domain).grid(
            row=7, column=1, sticky='w')

        self.lbl_status = ttk.Label(frm, text="", foreground='#B00020',
                                    wraplength=340)
        self.lbl_status.grid(row=8, column=0, columnspan=2, sticky='w',
                             pady=(10, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=9, column=0, columnspan=2, sticky='ew', pady=(14, 0))
        btns.columnconfigure(1, weight=1)
        # Interface language switcher (reopens the dialog)
        self.relaunch = False
        self.cmb_lang = ttk.Combobox(btns, width=4, state='readonly',
                                     values=('EN', 'RU'))
        self.cmb_lang.set('RU' if LANG == 'ru' else 'EN')
        self.cmb_lang.grid(row=0, column=0, sticky='w')
        self.cmb_lang.bind('<<ComboboxSelected>>', self._switch_lang)
        ttk.Button(btns, text=T('Connect'),
                   command=self._connect).grid(row=0, column=2, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'),
                   command=self._cancel).grid(row=0, column=3)

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
                T('Remove domain'),
                T("Remove '{a0}' from the list?").format(a0=(self._profile_label(d)))):
            return
        self._profiles = self.config.remove(d.get('host'))
        self.cmb_domain.set('')
        self._refresh_combo()

    def _connect(self):
        host = self.e_host.get().strip()
        user = self.e_user.get().strip()
        pwd = self.e_pass.get()
        if not host or not user or not pwd:
            self.lbl_status.config(text=T('Fill in server, user, and password.'))
            return
        self.lbl_status.config(text=T('Connecting...'))
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
            self.lbl_status.config(text=T('Failed to connect: {a0}').format(a0=(ex)))
        except Exception as ex:
            self.lbl_status.config(text=T('Error: {a0}').format(a0=(ex)))

    def _cancel(self):
        self.success = False
        self.destroy()

    def _grab_focus(self):
        """Deferred grab/focus once the window is mapped."""
        try:
            self.deiconify()
            self.lift()
            self.focus_force()
            self.grab_set()
            if not self.e_host.get().strip():
                self.e_host.focus_set()
            elif not self.e_user.get().strip():
                self.e_user.focus_set()
            else:
                self.e_pass.focus_set()
        except Exception:
            pass

    def _switch_lang(self, event=None):
        """Change the interface language and reopen the login dialog."""
        new = 'ru' if self.cmb_lang.get() == 'RU' else 'en'
        if new == LANG:
            return
        set_lang(new)
        if self.config:
            self.config.set_lang(new)
        self.success = False
        self.relaunch = True
        try:
            self.grab_release()
        except Exception:
            pass
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
        ttk.Label(bar, text=T('Search:')).grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(bar, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self.do_search())
        ttk.Button(bar, text=T('Find'), command=self.do_search).grid(
            row=0, column=2, padx=6)
        ttk.Button(bar, text=T('Refresh'), command=self.do_search).grid(
            row=0, column=3)
        self.btn_create = ttk.Button(bar, text=T('Create user'),
                                     command=self.on_create)
        self.btn_create.grid(row=0, column=4, padx=(20, 0))

        # Domain switcher (right)
        ttk.Label(bar, text=T('Domain:')).grid(row=0, column=6, padx=(0, 6))
        self.cmb_dom = ttk.Combobox(bar, width=24)  # editable: a new one can be typed
        self.cmb_dom.grid(row=0, column=7)
        self.cmb_dom.bind('<Return>', lambda e: self.on_switch_domain())
        ttk.Button(bar, text=T('Switch domain'),
                   command=self.on_switch_domain).grid(row=0, column=8, padx=(6, 0))
        self._domain_profiles = []
        self._reload_domains()

        # Interface language switcher
        self.cmb_lang = ttk.Combobox(bar, width=4, state='readonly',
                                     values=('EN', 'RU'))
        self.cmb_lang.set('RU' if LANG == 'ru' else 'EN')
        self.cmb_lang.grid(row=0, column=9, padx=(10, 0))
        self.cmb_lang.bind('<<ComboboxSelected>>', self._switch_lang)

        # Object type: users / computers
        self.mode_var = tk.StringVar(value='users')
        mode_row = ttk.Frame(bar)
        mode_row.grid(row=1, column=0, columnspan=5, sticky='w', pady=(6, 0))
        ttk.Label(mode_row, text=T('Show:')).grid(row=0, column=0, padx=(0, 6))
        ttk.Radiobutton(mode_row, text=T('Users'), value='users',
                        variable=self.mode_var,
                        command=self.on_mode_change).grid(row=0, column=1)
        ttk.Radiobutton(mode_row, text=T('Computers'), value='computers',
                        variable=self.mode_var,
                        command=self.on_mode_change).grid(row=0, column=2,
                                                          padx=(8, 0))
        ttk.Radiobutton(mode_row, text=T('Groups'), value='groups',
                        variable=self.mode_var,
                        command=self.on_mode_change).grid(row=0, column=3,
                                                          padx=(8, 0))

        # Nested OUs
        self.include_subtree = tk.BooleanVar(value=False)
        self.chk_subtree = ttk.Checkbutton(
            bar, text=T('Show from nested OUs'),
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
            messagebox.showinfo(T('No domain selected'),
                                T('Select from the list or enter a domain/controller.'))
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
                T('Access error'),
                T('Failed to connect to domain "{a0}" with the current account ({a1}).\n\nInsufficient rights or the domain is unavailable:\n{a2}').format(a0=(host), a1=(self.client.username), a2=(ex)))
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
            T('Domain changed'),
            T('Connected to domain "{a0}" as {a1}.').format(a0=(self.client.host), a1=(self.client.username)))

    # --- Main area ---
    def _build_body(self):
        body = ttk.Panedwindow(self, orient='horizontal')
        body.grid(row=1, column=0, sticky='nsew', padx=8, pady=(0, 8))

        # Organizational unit (OU) tree — like the ADUC snap-in
        ou_frame = ttk.Frame(body)
        ou_frame.rowconfigure(1, weight=1)
        ou_frame.columnconfigure(0, weight=1)
        ttk.Label(ou_frame, text=T('Organizational units')).grid(
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
                                                      text=T('User properties'))
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

        self.act_group = ttk.LabelFrame(right, text=T('Actions'))
        self.act_group.grid(row=1, column=0, sticky='ew', pady=(8, 0))
        self._build_actions()
        body.add(right, weight=2)

    def _apply_columns(self):
        """Configure list columns for the current mode (users/computers)."""
        mode = self.mode_var.get() if getattr(self, 'mode_var', None) else 'users'
        if mode == 'computers':
            spec = [
                ('name', T('Name'), 190),
                ('dns', T('DNS name'), 200),
                ('os', T('Operating system'), 190),
                ('desc', T('Description'), 150),
                ('state', T('State'), 90),
            ]
        elif mode == 'groups':
            spec = [
                ('name', T('Name'), 220),
                ('sam', T('Login'), 150),
                ('scope', T('Scope'), 120),
                ('category', T('Category'), 110),
                ('desc', T('Description'), 220),
            ]
        else:
            spec = [
                ('name', T('Name'), 200),
                ('sam', T('Login'), 130),
                ('mail', 'E-mail', 200),
                ('desc', T('Description'), 180),
                ('state', T('State'), 100),
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
        mode = self.mode_var.get()
        if mode == 'computers':
            actions = [
                (T('Enable'), self.on_enable),
                (T('Disable'), self.on_disable),
                (T('Rename...'), self.on_rename),
                (T('Move (OU)'), self.on_move),
                (T('Edit...'), self.on_edit),
                (T('Delete'), self.on_delete),
            ]
        elif mode == 'groups':
            actions = [
                (T('Create group...'), self.on_create_group),
                (T('Members...'), self.on_group_members),
                (T('Edit...'), self.on_edit),
                (T('Rename...'), self.on_rename),
                (T('Move (OU)'), self.on_move),
                (T('Delete'), self.on_delete),
            ]
        else:
            actions = [
                (T('Enable'), self.on_enable),
                (T('Disable'), self.on_disable),
                (T('Unlock'), self.on_unlock),
                (T('Reset password'), self.on_reset),
                (T('Pwd never expires'), self.on_pwd_never_expires),
                (T('Groups...'), self.on_groups),
                (T('Move (OU)'), self.on_move),
                (T('Edit...'), self.on_edit),
            ]
        for i, (label, cmd) in enumerate(actions):
            ttk.Button(self.act_group, text=label, command=cmd, width=18).grid(
                row=i // 2, column=i % 2, padx=4, pady=4, sticky='ew')

    def _switch_lang(self, event=None):
        """Switch the interface language and rebuild the main window."""
        new = 'ru' if self.cmb_lang.get() == 'RU' else 'en'
        if new == LANG:
            return
        set_lang(new)
        if self.config:
            self.config.set_lang(new)
        master, client, config = self.master, self.client, self.config
        self.destroy()
        win = MainWindow(master, client, config)
        # Rebuild the application menu with the new language
        rebuild_menu = getattr(master, '_build_app_menu', None)
        if rebuild_menu:
            rebuild_menu(win)

    def on_mode_change(self):
        """Switch between users, computers and groups."""
        mode = self.mode_var.get()
        self.e_search.delete(0, 'end')
        self.props.delete('1.0', 'end')
        self._prop_rows = []
        self._apply_columns()
        self._build_actions()
        titles = {'computers': T('Computer properties'),
                  'groups': T('Group properties')}
        self.prop_group.config(text=titles.get(mode, T('User properties')))
        if mode == 'users':
            self.btn_create.grid()
        else:
            self.btn_create.grid_remove()
        self.do_search()

    def _build_statusbar(self):
        self.status = ttk.Label(self, text="", padding=(8, 4),
                                relief='sunken', anchor='w')
        self.status.grid(row=2, column=0, sticky='ew')
        self._update_status()

    def _update_status(self, extra=''):
        proto = "LDAPS" if self.client.is_ssl() else "LDAP"
        base = (T('Connected: {a0} ({a1})   |   Base: {a2}').format(a0=(self.client.host), a1=(proto), a2=(self.client.base_dn)))
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
            return self.client.upn_suffix or T('domain')
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
            mode = self.mode_var.get()
            if mode == 'computers':
                self.users = self.client.search_computers(
                    query=text, base=base, scope=scope)
            elif mode == 'groups':
                self.users = self.client.search_ad_groups(
                    query=text, base=base, scope=scope)
            else:
                self.users = self.client.search_users(
                    query=text, base=base, scope=scope)
            self.tree.delete(*self.tree.get_children())
            for i, u in enumerate(self.users):
                if mode == 'computers':
                    vals = (u['name'], u.get('dnsHostName', ''),
                            u.get('osFull', ''), u['description'], u['state'])
                elif mode == 'groups':
                    vals = (u['name'], u['sAMAccountName'], u['scope'],
                            u['category'], u['description'])
                else:
                    vals = (u['name'], u['sAMAccountName'], u['mail'],
                            u['description'], u['state'])
                self.tree.insert('', 'end', iid=str(i), values=vals)
            scope_txt = self._short_dn(base)
            if subtree:
                scope_txt += T(' (+nested)')
            self._update_status(
                T('Found: {a0}  |  scope: {a1}').format(a0=(len(self.users)), a1=(scope_txt)))
        except Exception as ex:
            messagebox.showerror(T('Search error'), str(ex))
        finally:
            self.master.config(cursor='')

    def _selected_users(self):
        """All selected objects (multi-select aware)."""
        return [self.users[int(i)] for i in self.tree.selection()]

    def _selected_user(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo(T('No user selected'),
                                T('Select a user in the list first.'))
            return None
        if len(sel) > 1:
            messagebox.showinfo(
                T('Multiple objects selected'),
                T('This action applies to a single object.\nSelect exactly one item in the list.'))
            return None
        return self.users[int(sel[0])]

    def on_select(self, event=None):
        sel = self.tree.selection()
        if not sel:
            return
        if len(sel) > 1:
            self.props.delete('1.0', 'end')
            if self.mode_var.get() == 'groups':
                txt = T('Selected objects: {a0}\n\nAvailable bulk actions:\n  Move (OU) / Delete').format(a0=(len(sel)))
            else:
                txt = T('Selected objects: {a0}\n\nAvailable bulk actions:\n  Enable / Disable / Move (OU)\n  Add to groups (users)').format(a0=(len(sel)))
            self.props.insert('end', txt)
            return
        u = self.users[int(sel[0])]
        if u.get('is_group'):
            self._show_group_props(u)
        elif u.get('is_computer'):
            self._show_computer_props(u)
        else:
            self._show_props(u)

    def _refresh_selected(self, dn):
        if self.mode_var.get() in ('computers', 'groups'):
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
            (T('Display name'), u['displayName']),
            (T('Login'), u['sAMAccountName']),
            ("UPN", u['userPrincipalName']),
            (T('First name'), u['givenName']),
            (T('Last name'), u['sn']),
            ("E-mail", u['mail']),
            (T('State'), u['state']),
            (T('Locked'), T('Yes') if u['locked'] else T('No')),
            (T('Description'), u['description']),
            (T('Title'), u['title']),
            (T('Department'), u['department']),
            (T('Company'), u['company']),
            (T('Office'), u['office']),
            (T('Phone'), u['phone']),
            (T('Password last set'), filetime_to_str(u['pwdLastSet'])),
            (T('Password never expires'), T('Yes') if u.get('dontExpire') else T('No')),
            (T('Password change required'), pwd_expiry_text(u)),
            (T('Bad password attempts'),
             '' if u.get('badPwdCount') in (None, '') else str(u.get('badPwdCount'))),
            (T('Last bad password'), filetime_to_str(u.get('badPwdTime'))),
            (T('Last logon'), filetime_to_str(u['lastLogon'])),
            (T('Created'), filetime_to_str(u['whenCreated'])),
            (T('Expires'), filetime_to_str(u['accountExpires'])),
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
            (T('Name'), c['name']),
            (T('Account name'), c['sAMAccountName']),
            (T('DNS name'), c['dnsHostName']),
            (T('Operating system'), c['os']),
            (T('OS version'), c['osVersion']),
            (T('State'), c['state']),
            (T('Description'), c['description']),
            (T('Last logon'), filetime_to_str(c['lastLogon'])),
            (T('Created'), filetime_to_str(c['whenCreated'])),
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
        self._update_status(T('Copied to clipboard'))

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
            m.add_command(label=T('Selected: {a0}').format(a0=(len(sel))), state='disabled')
            m.add_separator()
            if self.mode_var.get() == 'groups':
                m.add_command(label=T('Move (OU)...'), command=self.on_move)
                m.add_command(label=T('Delete'), command=self.on_delete)
            else:
                m.add_command(label=T('Enable'), command=self.on_enable)
                m.add_command(label=T('Disable'), command=self.on_disable)
                m.add_command(label=T('Move (OU)...'), command=self.on_move)
                if self.mode_var.get() != 'computers':
                    m.add_command(label=T('Add to groups...'),
                                  command=self.on_groups)
            m.add_separator()
            m.add_command(label=T('Copy rows'),
                          command=self._copy_selected_row)
            try:
                m.tk_popup(event.x_root, event.y_root)
            finally:
                m.grab_release()
            return 'break'
        u = self.users[int(sel[0])]

        if u.get('is_group'):
            return self._show_group_menu(event, u)
        if u.get('is_computer'):
            return self._show_computer_menu(event, u)

        m = tk.Menu(self, tearoff=0)
        m.add_command(label=T('Copy login'),
                      command=lambda: self._copy_text(u['sAMAccountName']))
        m.add_command(label=T('Copy display name'),
                      command=lambda: self._copy_text(u['name']))
        m.add_command(label=T('Copy e-mail'),
                      command=lambda: self._copy_text(u['mail']),
                      state='normal' if u.get('mail') else 'disabled')
        m.add_command(label=T('Copy UPN'),
                      command=lambda: self._copy_text(u['userPrincipalName']),
                      state='normal' if u.get('userPrincipalName') else 'disabled')
        m.add_command(label=T('Copy DN'),
                      command=lambda: self._copy_text(u['dn']))
        m.add_command(label=T('Copy all properties'),
                      command=self._copy_all_props)
        m.add_separator()
        m.add_command(label=T('Enable'), command=self.on_enable)
        m.add_command(label=T('Disable'), command=self.on_disable)
        m.add_command(label=T('Unlock'), command=self.on_unlock)
        m.add_command(label=T('Reset password...'), command=self.on_reset)
        m.add_command(
            label=(T('Password never expires  ✓') if u.get('dontExpire')
                   else T('Password never expires')),
            command=self.on_pwd_never_expires)
        m.add_separator()
        m.add_command(label=T('Groups...'), command=self.on_groups)
        m.add_command(label=T('Move (OU)...'), command=self.on_move)
        m.add_command(label=T('Edit...'), command=self.on_edit)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()
        return 'break'

    def _show_computer_menu(self, event, c):
        m = tk.Menu(self, tearoff=0)
        m.add_command(label=T('Copy name'),
                      command=lambda: self._copy_text(c['name']))
        m.add_command(label=T('Copy DNS name'),
                      command=lambda: self._copy_text(c['dnsHostName']),
                      state='normal' if c.get('dnsHostName') else 'disabled')
        m.add_command(label=T('Copy account name'),
                      command=lambda: self._copy_text(c['sAMAccountName']))
        m.add_command(label=T('Copy DN'),
                      command=lambda: self._copy_text(c['dn']))
        m.add_command(label=T('Copy all properties'),
                      command=self._copy_all_props)
        m.add_separator()
        m.add_command(label=T('Enable'), command=self.on_enable)
        m.add_command(label=T('Disable'), command=self.on_disable)
        m.add_separator()
        m.add_command(label=T('Rename...'), command=self.on_rename)
        m.add_command(label=T('Move (OU)...'), command=self.on_move)
        m.add_command(label=T('Edit...'), command=self.on_edit)
        m.add_command(label=T('Delete'), command=self.on_delete)
        try:
            m.tk_popup(event.x_root, event.y_root)
        finally:
            m.grab_release()
        return 'break'

    def _show_group_props(self, g):
        try:
            members = self.client.get_group_members(g['dn'])
        except Exception:
            members = []
        rows = [
            (T('Name'), g['name']),
            (T('Login'), g['sAMAccountName']),
            (T('Scope'), g['scope']),
            (T('Category'), g['category']),
            (T('Description'), g['description']),
            ('E-mail', g.get('mail', '')),
            (T('Members'), str(len(members))),
            (T('Created'), filetime_to_str(g['whenCreated'])),
            ("DN", g['dn']),
        ]
        self._prop_rows = [(k, v) for k, v in rows if v not in (None, '')]
        self.props.delete('1.0', 'end')
        for k, val in self._prop_rows:
            self.props.insert('end', f"{k}:\n", ('label',))
            self.props.insert('end', f"{val}\n\n")
        self.props.tag_config('label', foreground='#555',
                              font=('Menlo', 10, 'bold'))

    def _show_group_menu(self, event, g):
        m = tk.Menu(self, tearoff=0)
        m.add_command(label=T('Copy name'),
                      command=lambda: self._copy_text(g['name']))
        m.add_command(label=T('Copy login'),
                      command=lambda: self._copy_text(g['sAMAccountName']))
        m.add_command(label=T('Copy DN'),
                      command=lambda: self._copy_text(g['dn']))
        m.add_command(label=T('Copy all properties'),
                      command=self._copy_all_props)
        m.add_separator()
        m.add_command(label=T('Members...'), command=self.on_group_members)
        m.add_command(label=T('Edit...'), command=self.on_edit)
        m.add_command(label=T('Rename...'), command=self.on_rename)
        m.add_command(label=T('Move (OU)...'), command=self.on_move)
        m.add_command(label=T('Delete'), command=self.on_delete)
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
        m.add_command(label=T('Copy selection'),
                      command=self._copy_props_selection,
                      state='normal' if has_sel else 'disabled')
        if row_val is not None:
            m.add_command(label=T('Copy value ({a0})').format(a0=(row_key)),
                          command=lambda v=row_val: self._copy_text(v))
        m.add_command(label=T('Copy all properties'), command=self._copy_all_props)
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
                T('Partially completed'),
                T('{a0}: {a1} of {a2}.\n\nErrors:\n').format(a0=(done_msg), a1=(ok), a2=(len(objs)))
                + "\n".join(errors[:10])
                + ("\n..." if len(errors) > 10 else ""))
        else:
            messagebox.showinfo(T('Done'), f"{done_msg}: {ok}.")
        self.do_search()

    def on_enable(self):
        objs = self._selected_users()
        if not objs:
            messagebox.showinfo(T('No object selected'),
                                T('Select one or more objects in the list.'))
            return
        if len(objs) == 1:
            try:
                self.client.enable_account(objs[0]['dn'])
                messagebox.showinfo(T('Done'), T('Account enabled.'))
                self._refresh_selected(objs[0]['dn'])
            except Exception as ex:
                messagebox.showerror(T('Error'), str(ex))
            return
        if not messagebox.askyesno(
                T('Confirm'), T('Enable {a0} accounts?').format(a0=(len(objs)))):
            return
        self._bulk_apply(objs, self.client.enable_account, T('Enabled'))

    def on_disable(self):
        objs = self._selected_users()
        if not objs:
            messagebox.showinfo(T('No object selected'),
                                T('Select one or more objects in the list.'))
            return
        if len(objs) == 1:
            u = objs[0]
            if not messagebox.askyesno(
                    T('Confirm'),
                    T("Disable account '{a0}'?").format(a0=(u['sAMAccountName']))):
                return
            try:
                self.client.disable_account(u['dn'])
                messagebox.showinfo(T('Done'), T('Account disabled.'))
                self._refresh_selected(u['dn'])
            except Exception as ex:
                messagebox.showerror(T('Error'), str(ex))
            return
        if not messagebox.askyesno(
                T('Confirm'), T('Disable {a0} accounts?').format(a0=(len(objs)))):
            return
        self._bulk_apply(objs, self.client.disable_account, T('Disabled'))

    def on_unlock(self):
        u = self._selected_user()
        if not u:
            return
        try:
            self.client.unlock_account(u['dn'])
            messagebox.showinfo(T('Done'), T('Account unlocked.'))
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror(T('Error'), str(ex))

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
            msg = (T("Clear the 'password never expires' flag for '{a0}'?\n\nThe password will expire per the domain policy.").format(a0=(u['sAMAccountName'])))
        else:
            msg = (T("Set the 'password never expires' flag for '{a0}'?\n\nIf a password change at next logon is pending, the requirement will be removed and the current password stays valid (same as in ADUC).").format(a0=(u['sAMAccountName'])))
        if not messagebox.askyesno(T('Password never expires'), msg):
            return
        try:
            cleared = self.client.set_password_never_expires(u['dn'], not cur)
            if cur:
                done = T('Flag cleared: the password expires per the domain policy.')
            else:
                done = T('Flag set: the password never expires.')
                if cleared:
                    done += (T("\n\nThe 'change password at next logon' requirement was removed; the current password stays valid."))
            messagebox.showinfo(T('Done'), done)
            self._refresh_selected(u['dn'])
        except Exception as ex:
            messagebox.showerror(T('Error'), str(ex))

    def on_groups(self):
        objs = [o for o in self._selected_users()
                if not o.get('is_computer')]
        if not objs:
            messagebox.showinfo(T('No user selected'),
                                T('Select one or more users in the list.'))
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
                T('Add to groups'),
                T('Add {a0} users to {a1} group(s)?\n\nGroups: {a2}').format(a0=(len(objs)), a1=(len(groups)), a2=(gnames))):
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
        summary = T('Added: {a0}.').format(a0=(added))
        if skipped:
            summary += T('\nAlready members (skipped): {a0}.').format(a0=(skipped))
        if errors:
            summary += (T('\n\nErrors:\n') + "\n".join(errors[:10])
                        + ("\n..." if len(errors) > 10 else ""))
            messagebox.showwarning(T('Partially completed'), summary)
        else:
            messagebox.showinfo(T('Done'), summary)

    def on_move(self):
        objs = self._selected_users()
        if not objs:
            messagebox.showinfo(T('No object selected'),
                                T('Select one or more objects in the list.'))
            return
        MoveDialog(self.master, self.client, objs,
                   on_done=self.do_search)

    def _on_tree_double(self, event):
        """Double-click on a list row: edit dialog; for a group — its members."""
        row = self.tree.identify_row(event.y)
        if not row:
            return
        self.tree.selection_set(row)
        self.tree.focus(row)
        if self.mode_var.get() == 'groups':
            self.on_group_members()
        else:
            self.on_edit()
        return 'break'

    def on_edit(self):
        u = self._selected_user()
        if not u:
            return
        if u.get('is_group'):
            GroupEditDialog(self.master, self.client, u,
                            on_done=lambda: self._refresh_selected(u['dn']))
        elif u.get('is_computer'):
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
        # Groups mode supports deleting several selected groups at once
        if self.mode_var.get() == 'groups':
            objs = self._selected_users()
            if len(objs) > 1:
                if not messagebox.askyesno(
                        T('Confirm deletion'),
                        T('Delete {a0} groups?\n\nThis operation is irreversible.').format(a0=(len(objs)))):
                    return
                errors = []
                for g in objs:
                    try:
                        self.client.delete_object(g['dn'])
                    except Exception as ex:
                        errors.append(f"{g.get('name')}: {ex}")
                self.do_search()
                self.props.delete('1.0', 'end')
                self._prop_rows = []
                if errors:
                    messagebox.showwarning(
                        T('Partially completed'),
                        T('Deleted: {a0}.').format(a0=(len(objs) - len(errors)))
                        + '\n\n' + '\n'.join(errors[:10]))
                else:
                    messagebox.showinfo(
                        T('Done'),
                        T('Deleted: {a0}.').format(a0=(len(objs))))
                return
        c = self._selected_user()
        if not c:
            return
        label = c.get('name') or c.get('sAMAccountName') or c['dn']
        if not messagebox.askyesno(
                T('Confirm deletion'),
                T("Delete object '{a0}'?\n\nThis operation is irreversible.").format(a0=(label))):
            return
        try:
            self.client.delete_object(c['dn'])
            messagebox.showinfo(T('Done'), T('Object deleted.'))
            self.do_search()
            self.props.delete('1.0', 'end')
            self._prop_rows = []
        except Exception as ex:
            messagebox.showerror(T('Error'), str(ex))

    def on_create(self):
        CreateDialog(self.master, self.client, on_done=self.do_search,
                     default_ou=self._current_base())

    def on_create_group(self):
        GroupCreateDialog(self.master, self.client, on_done=self.do_search,
                          default_ou=self._current_base())

    def on_group_members(self):
        g = self._selected_user()
        if not g or not g.get('is_group'):
            return
        GroupMembersDialog(self.master, self.client, g,
                           on_done=lambda: self._refresh_selected(g['dn']))


class ResetPasswordDialog(tk.Toplevel):
    def __init__(self, master, client, user, on_done=None):
        super().__init__(master)
        self.client = client
        self.user = user
        self.on_done = on_done
        self.title(T('Reset password'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text=T('User: {a0} ({a1})').format(a0=(user['name']), a1=(user['sAMAccountName'])),
                  font=('', 12, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 12))
        ttk.Label(frm, text=T('New password:')).grid(row=1, column=0, sticky='w')
        self.e1 = ttk.Entry(frm, width=30, show='•')
        self.e1.grid(row=1, column=1, pady=4)
        ttk.Label(frm, text=T('Confirm:')).grid(row=2, column=0, sticky='w')
        self.e2 = ttk.Entry(frm, width=30, show='•')
        self.e2.grid(row=2, column=1, pady=4)
        self.v_change = tk.BooleanVar(value=True)
        self.v_unlock = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text=T('Change password at next logon'),
                        variable=self.v_change).grid(
            row=3, column=0, columnspan=2, sticky='w', pady=(8, 0))
        ttk.Checkbutton(frm, text=T('Unlock the account'),
                        variable=self.v_unlock).grid(
            row=4, column=0, columnspan=2, sticky='w')
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=300)
        self.lbl.grid(row=5, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, columnspan=2, sticky='e', pady=(12, 0))
        ttk.Button(btns, text=T('Apply'), command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1)
        self.e1.focus_set()

    def _apply(self):
        if not self.e1.get():
            self.lbl.config(text=T('Enter a new password.'))
            return
        if self.e1.get() != self.e2.get():
            self.lbl.config(text=T('Passwords do not match.'))
            return
        try:
            self.client.reset_password(
                self.user['dn'], self.e1.get(),
                unlock=self.v_unlock.get(),
                change_at_logon=self.v_change.get())
            messagebox.showinfo(T('Done'), T('Password reset.'))
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
        self.title(T('Move to organizational unit'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        if len(self.users_list) == 1:
            hdr = T('Object: {a0} ({a1})').format(a0=(user['name']), a1=(user['sAMAccountName']))
        else:
            names = ", ".join(o['name'] for o in self.users_list[:3])
            if len(self.users_list) > 3:
                names += ", ..."
            hdr = T('Objects selected: {a0} ({a1})').format(a0=(len(self.users_list)), a1=(names))
        ttk.Label(frm, text=hdr, font=('', 12, 'bold'),
                  wraplength=420).grid(row=0, column=0, sticky='w',
                                       pady=(0, 10))
        parent = user['dn'].split(',', 1)[1] if ',' in user['dn'] else ''
        parents = {o['dn'].split(',', 1)[1].lower() if ',' in o['dn'] else ''
                   for o in self.users_list}
        if len(parents) > 1:
            parent = T('(objects are in different containers)')
        ttk.Label(frm, text=T('Current location:')).grid(row=1, column=0,
                                                        sticky='w')
        cur = ttk.Entry(frm, width=60)
        cur.insert(0, parent)
        cur.config(state='readonly')
        cur.grid(row=2, column=0, sticky='ew', pady=(2, 8))
        ttk.Label(frm, text=T('Target container (OU):')).grid(row=3, column=0,
                                                            sticky='w')
        dest_row = ttk.Frame(frm)
        dest_row.grid(row=4, column=0, sticky='ew', pady=2)
        dest_row.columnconfigure(0, weight=1)
        self.combo = ttk.Combobox(dest_row, width=52)
        self.combo.grid(row=0, column=0, sticky='ew')
        ttk.Button(dest_row, text=T('Browse…'), width=8,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))
        try:
            self.combo['values'] = self.client.list_ous()
        except Exception:
            pass
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=5, column=0, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, sticky='e', pady=(12, 0))
        ttk.Button(btns, text=T('Move'), command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
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
            self.lbl.config(text=T('Specify a target container.'))
            return
        if len(self.users_list) == 1:
            try:
                self.client.move_user(self.users_list[0]['dn'], dest)
                messagebox.showinfo(T('Done'), T('Object moved.'))
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
                T('Partially completed'),
                T('Moved: {a0} of {a1}.\n\nErrors:\n').format(a0=(ok), a1=(len(self.users_list)))
                + "\n".join(errors[:10])
                + ("\n..." if len(errors) > 10 else ""))
        else:
            messagebox.showinfo(T('Done'), T('Objects moved: {a0}.').format(a0=(ok)))
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
        self.title(T('Rename object'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        cur_name = obj.get('name') or obj.get('cn') or ''
        ttk.Label(frm, text=T('Object: {a0}').format(a0=(cur_name)),
                  font=('', 12, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 10))
        ttk.Label(frm, text=T('New name:')).grid(row=1, column=0, sticky='w')
        self.e_name = ttk.Entry(frm, width=36)
        self.e_name.insert(0, cur_name)
        self.e_name.grid(row=1, column=1, pady=4, padx=(6, 0))
        self.e_name.focus_set()
        self.e_name.select_range(0, 'end')
        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=340)
        self.lbl.grid(row=2, column=0, columnspan=2, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, sticky='e', pady=(12, 0))
        ttk.Button(btns, text=T('Rename'), command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1)
        self.e_name.bind('<Return>', lambda e: self._apply())

    def _apply(self):
        new_name = self.e_name.get().strip()
        if not new_name:
            self.lbl.config(text=T('Enter a name.'))
            return
        cur_name = self.obj.get('name') or self.obj.get('cn') or ''
        if new_name == cur_name:
            self.destroy()
            return
        try:
            new_dn = self.client.rename_object(self.obj['dn'], new_name)
            messagebox.showinfo(T('Done'), T('Object renamed.'))
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
        self.title(T('Select groups'))
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
        ttk.Label(top, text=T('Filter:')).grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(top, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self._load())
        ttk.Button(top, text=T('Find'), command=self._load).grid(
            row=0, column=2, padx=(6, 0))

        scope = (T('Groups from OU "{a0}"').format(a0=(ACCESS_GROUPS_OU_NAME))
                 if ACCESS_GROUPS_OU_NAME else T('Domain groups'))
        ttk.Label(
            frm,
            text=T('{a0} (Cmd-click — multi-select):').format(a0=(scope))).grid(
            row=1, column=0, columnspan=2, sticky='w', pady=(10, 4))
        self.listbox = tk.Listbox(frm, selectmode='extended')
        self.listbox.grid(row=2, column=0, sticky='nsew')
        sb = ttk.Scrollbar(frm, orient='vertical', command=self.listbox.yview)
        sb.grid(row=2, column=1, sticky='ns')
        self.listbox.config(yscrollcommand=sb.set)

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text=T('Select'), command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
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
            messagebox.showerror(T('Error'), str(ex))
            self._all = []
        finally:
            self.config(cursor='')
        self.listbox.delete(0, 'end')
        for g in self._all:
            self.listbox.insert('end', g['cn'])
        if not self._all:
            self.listbox.insert('end', T('(no groups found)'))
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
        self.title(T('Group membership'))
        self.grab_set()
        frm = ttk.Frame(self, padding=16)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(1, weight=1)
        frm.columnconfigure(0, weight=1)
        ttk.Label(frm, text=T('Groups: {a0} ({a1})').format(a0=(user['name']), a1=(user['sAMAccountName'])),
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
        ttk.Button(btns, text=T('Add...'), command=self._add).grid(
            row=0, column=0)
        ttk.Button(btns, text=T('Remove selected'), command=self._remove).grid(
            row=0, column=1, padx=(8, 0))
        ttk.Button(btns, text=T('Close'), command=self.destroy).grid(
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
            messagebox.showerror(T('Error'), str(ex))

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
                messagebox.showerror(T('Error'), f"{g['cn']}: {ex}")
        if added:
            self._reload()

    def _remove(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        if not messagebox.askyesno(T('Confirm'),
                                   T('Remove from the selected groups ({a0})?').format(a0=(len(sel)))):
            return
        for i in sel:
            try:
                self.client.remove_from_group(self.user['dn'],
                                              self.groups[i]['dn'])
            except Exception as ex:
                messagebox.showerror(T('Error'),
                                     f"{self.groups[i]['cn']}: {ex}")
        self._reload()


class ComputerEditDialog(tk.Toplevel):
    """Edit computer attributes (description, location)."""

    def __init__(self, master, client, comp, on_done=None):
        super().__init__(master)
        self.client = client
        self.comp = comp
        self.on_done = on_done
        self.title(T('Edit computer'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text=T('Name:')).grid(row=0, column=0, sticky='w', pady=3)
        ttk.Label(frm, text=comp.get('name') or '').grid(
            row=0, column=1, sticky='w', pady=3)
        ttk.Label(frm, text=T('DNS name:')).grid(row=1, column=0, sticky='w',
                                              pady=3)
        ttk.Label(frm, text=comp.get('dnsHostName') or '—').grid(
            row=1, column=1, sticky='w', pady=3)
        ttk.Label(frm, text=T('Description:')).grid(row=2, column=0, sticky='w',
                                                 pady=3)
        self.e_desc = ttk.Entry(frm, width=38)
        self.e_desc.insert(0, comp.get('description', '') or '')
        self.e_desc.grid(row=2, column=1, pady=3)
        self.lbl = ttk.Label(frm, text="", foreground='#b00')
        self.lbl.grid(row=3, column=0, columnspan=2, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=4, column=0, columnspan=2, pady=(12, 0))
        ttk.Button(btns, text=T('Save'), command=self._save).grid(row=0, column=0)
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1, padx=(8, 0))

    def _save(self):
        try:
            self.client.update_attributes(
                self.comp['dn'], {'description': self.e_desc.get()})
            self.destroy()
            if self.on_done:
                self.on_done()
        except Exception as ex:
            self.lbl.config(text=T('Error: {a0}').format(a0=(ex)))


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
        self.title(T('Edit properties'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        self.entries = {}
        for i, (label, attr) in enumerate(self.FIELDS):
            ttk.Label(frm, text=T(label) + ":").grid(row=i, column=0, sticky='w',
                                                  pady=3)
            e = ttk.Entry(frm, width=38)
            e.insert(0, user.get(self.SRC[attr], '') or '')
            e.grid(row=i, column=1, pady=3)
            self.entries[attr] = e
        r = len(self.FIELDS)
        # Account option: password never expires (UAC bit)
        self.v_dont_expire = tk.BooleanVar(value=bool(user.get('dontExpire')))
        ttk.Checkbutton(frm, text=T('Password never expires'),
                        variable=self.v_dont_expire).grid(
            row=r, column=0, columnspan=2, sticky='w', pady=(8, 0))
        r += 1
        # Group membership (Member Of) — applied immediately
        grp = ttk.LabelFrame(frm, text=T('Group membership (Member Of)'))
        grp.grid(row=r, column=0, columnspan=2, sticky='ew', pady=(10, 0))
        grp.columnconfigure(0, weight=1)
        self.grp_list = tk.Listbox(grp, height=6, selectmode='extended')
        self.grp_list.grid(row=0, column=0, sticky='ew', padx=6, pady=6)
        gsb = ttk.Scrollbar(grp, orient='vertical', command=self.grp_list.yview)
        gsb.grid(row=0, column=1, sticky='ns')
        self.grp_list.config(yscrollcommand=gsb.set)
        gbtns = ttk.Frame(grp)
        gbtns.grid(row=1, column=0, columnspan=2, sticky='w', padx=6, pady=(0, 6))
        ttk.Button(gbtns, text=T('Add...'), command=self._add_groups).grid(
            row=0, column=0)
        ttk.Button(gbtns, text=T('Remove selected'),
                   command=self._remove_groups).grid(row=0, column=1, padx=(8, 0))
        self.groups = []
        self._reload_groups()

        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=r + 1, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=r + 2, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text=T('Save'), command=self._save).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1)

    def _reload_groups(self):
        self.grp_list.delete(0, 'end')
        try:
            self.groups = self.client.get_user_groups(self.user['dn'])
            for g in self.groups:
                self.grp_list.insert('end', g['cn'])
        except Exception as ex:
            messagebox.showerror(T('Error'), str(ex))

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
                messagebox.showerror(T('Error'), f"{g['cn']}: {ex}")
        if added:
            self._reload_groups()

    def _remove_groups(self):
        sel = self.grp_list.curselection()
        if not sel:
            return
        if not messagebox.askyesno(T('Confirm'),
                                   T('Remove from the selected groups ({a0})?').format(a0=(len(sel)))):
            return
        for i in sel:
            try:
                self.client.remove_from_group(self.user['dn'],
                                              self.groups[i]['dn'])
            except Exception as ex:
                messagebox.showerror(T('Error'), f"{self.groups[i]['cn']}: {ex}")
        self._reload_groups()

    def _save(self):
        attrs = {attr: e.get() for attr, e in self.entries.items()}
        try:
            self.client.update_attributes(self.user['dn'], attrs)
            if self.v_dont_expire.get() != bool(self.user.get('dontExpire')):
                self.client.set_password_never_expires(
                    self.user['dn'], self.v_dont_expire.get())
            messagebox.showinfo(T('Done'), T('Changes saved.'))
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class GroupCreateDialog(tk.Toplevel):
    """Create a new group: name, sAMAccountName, description, scope,
    category and target OU."""

    def __init__(self, master, client, on_done=None, default_ou=None):
        super().__init__(master)
        self.client = client
        self.on_done = on_done
        self.title(T('Create group'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()

        ttk.Label(frm, text=T('Group name:')).grid(row=0, column=0,
                                                   sticky='w', pady=3)
        self.e_name = ttk.Entry(frm, width=36)
        self.e_name.grid(row=0, column=1, pady=3, sticky='ew')
        self.e_name.bind('<KeyRelease>', self._sync_sam)

        ttk.Label(frm, text=T('Login (sAMAccountName):')).grid(
            row=1, column=0, sticky='w', pady=3)
        self.e_sam = ttk.Entry(frm, width=36)
        self.e_sam.grid(row=1, column=1, pady=3, sticky='ew')
        self._sam_edited = False
        self.e_sam.bind('<Key>', lambda e: setattr(self, '_sam_edited', True))

        ttk.Label(frm, text=T('Description:')).grid(row=2, column=0,
                                                    sticky='w', pady=3)
        self.e_desc = ttk.Entry(frm, width=36)
        self.e_desc.grid(row=2, column=1, pady=3, sticky='ew')

        ttk.Label(frm, text=T('Scope:')).grid(row=3, column=0,
                                              sticky='w', pady=3)
        self.v_scope = tk.StringVar(value='global')
        sc = ttk.Frame(frm)
        sc.grid(row=3, column=1, sticky='w')
        ttk.Radiobutton(sc, text=T('Global'), value='global',
                        variable=self.v_scope).grid(row=0, column=0)
        ttk.Radiobutton(sc, text=T('Domain local'), value='domainlocal',
                        variable=self.v_scope).grid(row=0, column=1,
                                                    padx=(8, 0))
        ttk.Radiobutton(sc, text=T('Universal'), value='universal',
                        variable=self.v_scope).grid(row=0, column=2,
                                                    padx=(8, 0))

        ttk.Label(frm, text=T('Category:')).grid(row=4, column=0,
                                                 sticky='w', pady=3)
        self.v_sec = tk.StringVar(value='security')
        ct = ttk.Frame(frm)
        ct.grid(row=4, column=1, sticky='w')
        ttk.Radiobutton(ct, text=T('Security'), value='security',
                        variable=self.v_sec).grid(row=0, column=0)
        ttk.Radiobutton(ct, text=T('Distribution'), value='distribution',
                        variable=self.v_sec).grid(row=0, column=1,
                                                  padx=(8, 0))

        ttk.Label(frm, text=T('Container (OU):')).grid(row=5, column=0,
                                                       sticky='w', pady=3)
        ou_row = ttk.Frame(frm)
        ou_row.grid(row=5, column=1, sticky='ew', pady=3)
        ou_row.columnconfigure(0, weight=1)
        self.e_ou = ttk.Entry(ou_row, width=28)
        if default_ou:
            self.e_ou.insert(0, default_ou)
        self.e_ou.grid(row=0, column=0, sticky='ew')
        ttk.Button(ou_row, text=T('Browse…'), width=9,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))

        self.lbl = ttk.Label(frm, text="", foreground='#B00020',
                             wraplength=380)
        self.lbl.grid(row=6, column=0, columnspan=2, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=7, column=0, columnspan=2, pady=(12, 0))
        ttk.Button(btns, text=T('Create'), command=self._apply).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1)

    def _sync_sam(self, event=None):
        if not self._sam_edited:
            self.e_sam.delete(0, 'end')
            self.e_sam.insert(0, self.e_name.get())

    def _browse_ou(self):
        picker = OUTreePickerDialog(
            self, self.client, initial=self.e_ou.get().strip() or None)
        self.wait_window(picker)
        if picker.selected_dn:
            self.e_ou.delete(0, 'end')
            self.e_ou.insert(0, picker.selected_dn)

    def _apply(self):
        name = self.e_name.get().strip()
        sam = self.e_sam.get().strip() or name
        if not name:
            self.lbl.config(text=T('Enter a group name.'))
            return
        try:
            self.client.create_group(
                self.e_ou.get().strip(), name, sam,
                description=self.e_desc.get().strip() or None,
                scope=self.v_scope.get(),
                security=(self.v_sec.get() == 'security'))
            messagebox.showinfo(T('Done'), T('Group created.'))
            if self.on_done:
                self.on_done()
            self.destroy()
        except Exception as ex:
            self.lbl.config(text=str(ex))


class GroupEditDialog(tk.Toplevel):
    """Edit group attributes (description, e-mail)."""

    def __init__(self, master, client, group, on_done=None):
        super().__init__(master)
        self.client = client
        self.group = group
        self.on_done = on_done
        self.title(T('Edit group'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()
        ttk.Label(frm, text=T('Name:')).grid(row=0, column=0, sticky='w',
                                             pady=3)
        ttk.Label(frm, text=group.get('name') or '').grid(
            row=0, column=1, sticky='w', pady=3)
        ttk.Label(frm, text=T('Login:')).grid(row=1, column=0, sticky='w',
                                              pady=3)
        ttk.Label(frm, text=group.get('sAMAccountName') or '—').grid(
            row=1, column=1, sticky='w', pady=3)
        ttk.Label(frm, text=T('Description:')).grid(row=2, column=0,
                                                    sticky='w', pady=3)
        self.e_desc = ttk.Entry(frm, width=38)
        self.e_desc.insert(0, group.get('description', '') or '')
        self.e_desc.grid(row=2, column=1, pady=3)
        ttk.Label(frm, text="E-mail:").grid(row=3, column=0, sticky='w',
                                            pady=3)
        self.e_mail = ttk.Entry(frm, width=38)
        self.e_mail.insert(0, group.get('mail', '') or '')
        self.e_mail.grid(row=3, column=1, pady=3)
        self.lbl = ttk.Label(frm, text="", foreground='#b00')
        self.lbl.grid(row=4, column=0, columnspan=2, sticky='w', pady=(6, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=5, column=0, columnspan=2, pady=(12, 0))
        ttk.Button(btns, text=T('Save'), command=self._save).grid(
            row=0, column=0)
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1, padx=(8, 0))

    def _save(self):
        try:
            self.client.update_attributes(
                self.group['dn'], {'description': self.e_desc.get(),
                                   'mail': self.e_mail.get()})
            self.destroy()
            if self.on_done:
                self.on_done()
        except Exception as ex:
            self.lbl.config(text=T('Error: {a0}').format(a0=(ex)))


class UserPickerDialog(tk.Toplevel):
    """Search and pick one or more users."""

    def __init__(self, master, client, exclude_dns=None):
        super().__init__(master)
        self.client = client
        self.exclude = set((d or '').lower() for d in (exclude_dns or []))
        self.selected = []
        self.title(T('Select users'))
        self.grab_set()
        self.geometry("760x500")
        frm = ttk.Frame(self, padding=14)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(2, weight=1)
        frm.columnconfigure(0, weight=1)

        top = ttk.Frame(frm)
        top.grid(row=0, column=0, sticky='ew')
        ttk.Label(top, text=T('Filter:')).grid(row=0, column=0, padx=(0, 6))
        self.e_search = ttk.Entry(top, width=34)
        self.e_search.grid(row=0, column=1)
        self.e_search.bind('<Return>', lambda e: self._load())
        ttk.Button(top, text=T('Find'), command=self._load).grid(
            row=0, column=2, padx=(6, 0))

        ttk.Label(frm, text=T('Container on the left — its users on the right; the search spans the whole subtree. Cmd-click — multi-select.'),
                  wraplength=700).grid(
            row=1, column=0, sticky='w', pady=(10, 4))

        body = ttk.Panedwindow(frm, orient='horizontal')
        body.grid(row=2, column=0, sticky='nsew')

        # AD hierarchy (like the main window's OU tree)
        tree_frame = ttk.Frame(body)
        tree_frame.rowconfigure(0, weight=1)
        tree_frame.columnconfigure(0, weight=1)
        self.ou_tree = ttk.Treeview(tree_frame, show='tree',
                                    selectmode='browse')
        self.ou_tree.grid(row=0, column=0, sticky='nsew')
        tsb = ttk.Scrollbar(tree_frame, orient='vertical',
                            command=self.ou_tree.yview)
        tsb.grid(row=0, column=1, sticky='ns')
        self.ou_tree.configure(yscrollcommand=tsb.set)
        self.ou_tree.bind('<<TreeviewSelect>>', self._on_ou_select)
        body.add(tree_frame, weight=2)

        list_frame = ttk.Frame(body)
        list_frame.rowconfigure(0, weight=1)
        list_frame.columnconfigure(0, weight=1)
        self.listbox = tk.Listbox(list_frame, selectmode='extended')
        self.listbox.grid(row=0, column=0, sticky='nsew')
        sb = ttk.Scrollbar(list_frame, orient='vertical',
                           command=self.listbox.yview)
        sb.grid(row=0, column=1, sticky='ns')
        self.listbox.config(yscrollcommand=sb.set)
        body.add(list_frame, weight=3)

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, sticky='e', pady=(10, 0))
        ttk.Button(btns, text=T('Select'), command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
            row=0, column=1)

        self._all = []
        self._ou_dn_by_item = {}
        self._loading_tree = False
        self._load_tree()
        self.e_search.focus_set()
        self._load()

    def _load_tree(self):
        """AD hierarchy: OUs and standard containers, like the main window."""
        self._loading_tree = True
        self.ou_tree.delete(*self.ou_tree.get_children())
        self._ou_dn_by_item = {}
        item_by_dn = {}
        root_label = self.client.upn_suffix or self.client.base_dn
        root = self.ou_tree.insert('', 'end', text=root_label, open=True)
        self._ou_dn_by_item[root] = self.client.base_dn
        item_by_dn[self.client.base_dn.lower()] = root
        try:
            nodes = self.client.list_tree_nodes()
        except Exception:
            nodes = []
        for dn in nodes:
            parent_dn = dn.split(',', 1)[1] if ',' in dn else ''
            parent_item = item_by_dn.get(parent_dn.lower(), root)
            rdn = dn.split(',', 1)[0]
            label = rdn.split('=', 1)[1] if '=' in rdn else rdn
            item = self.ou_tree.insert(parent_item, 'end', text=label)
            self._ou_dn_by_item[item] = dn
            item_by_dn[dn.lower()] = item
        self.ou_tree.selection_set(root)
        self._loading_tree = False

    def _picker_base(self):
        sel = self.ou_tree.selection()
        if sel and sel[0] in self._ou_dn_by_item:
            return self._ou_dn_by_item[sel[0]]
        return self.client.base_dn

    def _on_ou_select(self, event=None):
        if self._loading_tree:
            return
        # Browsing the hierarchy shows the container's users (one level)
        self.e_search.delete(0, 'end')
        self._load()

    def _load(self):
        self.config(cursor='watch')
        self.update_idletasks()
        try:
            text = self.e_search.get().strip()
            base = self._picker_base()
            scope = SUBTREE if text else LEVEL
            users = self.client.search_users(query=text, base=base,
                                             scope=scope)
            # Disabled accounts are not offered for membership
            self._all = [u for u in users
                         if u['dn'].lower() not in self.exclude
                         and u.get('enabled', True)]
        except Exception as ex:
            messagebox.showerror(T('Error'), str(ex))
            self._all = []
        finally:
            self.config(cursor='')
        self.listbox.delete(0, 'end')
        for u in self._all:
            self.listbox.insert(
                'end', f"{u['name']} ({u['sAMAccountName']})")
        if not self._all:
            self.listbox.insert('end', T('(no users found)'))
            self.listbox.itemconfig(0, foreground='gray')

    def _ok(self):
        if not self._all:
            self.selected = []
        else:
            self.selected = [self._all[i]
                             for i in self.listbox.curselection()
                             if i < len(self._all)]
        self.destroy()


class GroupMembersDialog(tk.Toplevel):
    """Group members: view, add (multi) and remove (multi)."""

    def __init__(self, master, client, group, on_done=None):
        super().__init__(master)
        self.client = client
        self.group = group
        self.on_done = on_done
        self.title(T('Group members'))
        self.grab_set()
        self.geometry("560x480")
        frm = ttk.Frame(self, padding=14)
        frm.grid(sticky='nsew')
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        frm.rowconfigure(1, weight=1)
        frm.columnconfigure(0, weight=1)

        ttk.Label(frm, text=T('Group: {a0}').format(a0=(group['name'])),
                  font=('', 12, 'bold')).grid(row=0, column=0, columnspan=2,
                                              sticky='w', pady=(0, 8))
        self.listbox = tk.Listbox(frm, selectmode='extended')
        self.listbox.grid(row=1, column=0, sticky='nsew')
        sb = ttk.Scrollbar(frm, orient='vertical', command=self.listbox.yview)
        sb.grid(row=1, column=1, sticky='ns')
        self.listbox.config(yscrollcommand=sb.set)

        btns = ttk.Frame(frm)
        btns.grid(row=2, column=0, columnspan=2, sticky='w', pady=(10, 0))
        ttk.Button(btns, text=T('Add...'), command=self._add).grid(
            row=0, column=0)
        ttk.Button(btns, text=T('Remove selected'),
                   command=self._remove).grid(row=0, column=1, padx=(8, 0))
        ttk.Button(btns, text=T('Close'), command=self._close).grid(
            row=0, column=2, padx=(24, 0))

        self.members = []
        self._reload()

    def _reload(self):
        try:
            self.members = self.client.get_group_members(self.group['dn'])
        except Exception as ex:
            messagebox.showerror(T('Error'), str(ex))
            self.members = []
        self.listbox.delete(0, 'end')
        for m in self.members:
            self.listbox.insert('end', m['name'])
        self.title(T('Group members') + f" ({len(self.members)})")

    def _add(self):
        picker = UserPickerDialog(
            self, self.client,
            exclude_dns=[m['dn'] for m in self.members])
        self.wait_window(picker)
        if not picker.selected:
            return
        added, already, errors = self.client.add_group_members(
            self.group['dn'], [u['dn'] for u in picker.selected])
        if errors:
            messagebox.showwarning(
                T('Partially completed'),
                T('Added: {a0}.').format(a0=(added)) + '\n\n'
                + '\n'.join(errors[:10]))
        self._reload()

    def _remove(self):
        idx = list(self.listbox.curselection())
        sel = [self.members[i] for i in idx if i < len(self.members)]
        if not sel:
            return
        if not messagebox.askyesno(
                T('Confirm'),
                T('Remove selected members ({a0}) from the group?').format(a0=(len(sel)))):
            return
        removed, errors = self.client.remove_group_members(
            self.group['dn'], [m['dn'] for m in sel])
        if errors:
            messagebox.showwarning(
                T('Partially completed'),
                T('Removed: {a0}.').format(a0=(removed)) + '\n\n'
                + '\n'.join(errors[:10]))
        self._reload()

    def _close(self):
        self.destroy()
        if self.on_done:
            self.on_done()


class OUTreePickerDialog(tk.Toplevel):
    """Select an organizational unit (OU) by navigating the domain tree."""

    def __init__(self, master, client, initial=None):
        super().__init__(master)
        self.client = client
        self.selected_dn = None
        self.title(T('Select organizational unit (OU)'))
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
        ttk.Button(btns, text=T('Select'), command=self._ok).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
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
        self.title(T('Select date'))
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
        ttk.Label(hdr, text=f"{T(self.MONTHS[self.month - 1])} {self.year}",
                  anchor='center', font=('', 12, 'bold')).grid(row=0, column=1,
                                                               sticky='ew')
        ttk.Button(hdr, text="▶", width=3, command=self._next).grid(row=0, column=2)

        for i, dname in enumerate(self.WEEKDAYS):
            ttk.Label(self._frame, text=T(dname), width=4, anchor='center',
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
        self.title(T('Create user'))
        self.resizable(False, False)
        self.grab_set()
        frm = ttk.Frame(self, padding=18)
        frm.grid()

        def row(r, label):
            ttk.Label(frm, text=label).grid(row=r, column=0, sticky='w', pady=3)
            e = ttk.Entry(frm, width=36)
            e.grid(row=r, column=1, pady=3)
            return e

        self.e_given = row(0, T('First name:'))
        self.e_sur = row(1, T('Last name:'))
        self.e_display = row(2, T('Display name:'))
        self.e_sam = row(3, T('Login (sAMAccountName):'))
        self.e_upn = row(4, T('UPN suffix:'))
        self.e_mail = row(5, "E-mail:")
        self.e_desc = row(6, T('Description:'))
        ttk.Label(frm, text=T('Password:')).grid(row=7, column=0, sticky='w', pady=3)
        self.e_pass = ttk.Entry(frm, width=36, show='•')
        self.e_pass.grid(row=7, column=1, pady=3)

        # Organizational unit (OU) where the user will be created
        ttk.Label(frm, text=T('Organizational unit (OU):')).grid(
            row=8, column=0, sticky='w', pady=3)
        ou_row = ttk.Frame(frm)
        ou_row.grid(row=8, column=1, sticky='ew', pady=3)
        self.cmb_ou = ttk.Combobox(ou_row, width=27)
        self.cmb_ou.grid(row=0, column=0)
        ttk.Button(ou_row, text=T('Browse…'), width=8,
                   command=self._browse_ou).grid(row=0, column=1, padx=(6, 0))
        self._fill_ou(default_ou)

        # Account expiration
        ttk.Label(frm, text=T('Expires:')).grid(
            row=9, column=0, sticky='w', pady=3)
        exp_row = ttk.Frame(frm)
        exp_row.grid(row=9, column=1, sticky='w', pady=3)
        self.v_expire = tk.BooleanVar(value=False)
        ttk.Checkbutton(exp_row, text=T('Valid through (incl.):'),
                        variable=self.v_expire,
                        command=self._toggle_expire).grid(row=0, column=0)
        self.e_expire = ttk.Entry(exp_row, width=12)
        self.e_expire.grid(row=0, column=1, padx=(6, 0))
        self.e_expire.insert(0, date_hint())
        self.e_expire.config(state='disabled')
        self.btn_cal = ttk.Button(exp_row, text="📅", width=3,
                                  command=self._open_calendar, state='disabled')
        self.btn_cal.grid(row=0, column=2, padx=(4, 0))

        # Groups to add on creation
        grp = ttk.LabelFrame(frm, text=T('Groups on creation'))
        grp.grid(row=10, column=0, columnspan=2, sticky='ew', pady=(8, 0))
        grp.columnconfigure(0, weight=1)
        self.grp_list = tk.Listbox(grp, height=4, selectmode='extended')
        self.grp_list.grid(row=0, column=0, sticky='ew', padx=6, pady=6)
        gsb = ttk.Scrollbar(grp, orient='vertical', command=self.grp_list.yview)
        gsb.grid(row=0, column=1, sticky='ns')
        self.grp_list.config(yscrollcommand=gsb.set)
        gb = ttk.Frame(grp)
        gb.grid(row=1, column=0, columnspan=2, sticky='w', padx=6, pady=(0, 6))
        ttk.Button(gb, text=T('Select groups...'), command=self._pick_groups).grid(
            row=0, column=0)
        ttk.Button(gb, text=T('Remove selected'), command=self._unpick).grid(
            row=0, column=1, padx=(8, 0))

        self.v_change = tk.BooleanVar(value=True)
        self.v_enabled = tk.BooleanVar(value=True)
        ttk.Checkbutton(frm, text=T('Change password at next logon'),
                        variable=self.v_change).grid(
            row=11, column=1, sticky='w', pady=(6, 0))
        ttk.Checkbutton(frm, text=T('Account enabled'),
                        variable=self.v_enabled).grid(
            row=12, column=1, sticky='w')

        self.lbl = ttk.Label(frm, text="", foreground='#B00020', wraplength=380)
        self.lbl.grid(row=13, column=0, columnspan=2, sticky='w', pady=(8, 0))
        btns = ttk.Frame(frm)
        btns.grid(row=14, column=0, columnspan=2, sticky='e', pady=(10, 0))
        ttk.Button(btns, text=T('Create'), command=self._create).grid(
            row=0, column=0, padx=(0, 8))
        ttk.Button(btns, text=T('Cancel'), command=self.destroy).grid(
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
                text=T('Default groups not found: ') + ", ".join(missing))

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
            if self.e_expire.get() == date_hint():
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
            self.lbl.config(text=T('Specify a login (sAMAccountName).'))
            return
        if not self.e_pass.get():
            self.lbl.config(text=T('Specify a password.'))
            return

        # Account expiration
        expire = None
        if self.v_expire.get():
            txt = self.e_expire.get().strip()
            try:
                expire = parse_date(txt)
            except ValueError:
                self.lbl.config(
                    text=T('Expiration: enter a date in {a0} format.').format(a0=(date_hint())))
                return

        # Check that the login is not already taken in the domain
        try:
            if self.client.user_exists(sam):
                self.lbl.config(
                    text=T('A user with login "{a0}" already exists in the domain.').format(a0=(sam)))
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
                    T('User created, but not added to all groups'),
                    "\n".join(errs))
            else:
                messagebox.showinfo(T('Done'), T('User created.'))
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
    root.title("ADUC-Ext")
    root.geometry("1400x700")
    _install_mac_keybindings(root)
    root.withdraw()  # hidden until a successful login

    config = ConfigStore()
    client = ADClient()

    # Interface language: saved choice, otherwise the system locale
    saved = config.get_lang()
    if saved:
        set_lang(saved)
    else:
        try:
            import locale
            loc = (locale.getlocale()[0] or
                   os.environ.get('LANG', '') or '')
            set_lang('ru' if loc.lower().startswith('ru') else 'en')
        except Exception:
            set_lang('en')

    # The login dialog can switch the language; it then asks to be reopened.
    while True:
        login = LoginDialog(root, client, config)
        root.wait_window(login)
        if getattr(login, 'relaunch', False):
            continue
        break

    if not login.success:
        root.destroy()
        return

    root.deiconify()
    win = MainWindow(root, client, config)

    # macOS routes Cmd+C/Cmd+A through the application's Edit menu, so
    # provide one; its commands call our own copy logic (pbcopy on macOS).
    def _build_app_menu(w):
        menubar = tk.Menu(root)
        edit_menu = tk.Menu(menubar, tearoff=0)
        edit_menu.add_command(label=T('Cut'), accelerator="Cmd+X",
                              command=lambda: root.focus_get() and
                              root.focus_get().event_generate('<<Cut>>'))
        edit_menu.add_command(label=T('Copy'), accelerator="Cmd+C",
                              command=w._on_copy_shortcut)
        edit_menu.add_command(label=T('Paste'), accelerator="Cmd+V",
                              command=lambda: root.focus_get() and
                              root.focus_get().event_generate('<<Paste>>'))
        edit_menu.add_separator()
        edit_menu.add_command(label=T('Select All'), accelerator="Cmd+A",
                              command=w._on_select_all)
        menubar.add_cascade(label=T('Edit'), menu=edit_menu)
        root.config(menu=menubar)

    root._build_app_menu = _build_app_menu
    _build_app_menu(win)

    root.mainloop()


if __name__ == '__main__':
    main()
