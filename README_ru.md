<div align="center">

<img src="assets/aduc_ext_icon_1024.png" width="128" alt="ADUC-Extended"/>

# ADUC-Extended

Графическое приложение для управления учётными записями Active Directory —
Windows (PowerShell + WPF) и macOS (Python + Tkinter).

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-blue)
![Windows](https://img.shields.io/badge/Windows-PowerShell%205.1-5391FE?logo=powershell&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-Python%203.8%2B-3776AB?logo=python&logoColor=white)
![Version](https://img.shields.io/badge/version-1.0.0-orange)

[English](README.md) · **Русская версия**

## На развитие проекта

💛 https://dalink.to/rderensky

</div>

---

Обе сборки содержат **английский** и **русский** варианты. При запуске приложение
запрашивает учётные данные и выполняет все операции от имени указанной учётной записи.

## Возможности

- Поиск и просмотр свойств пользователей (в т.ч. сведения о пароле: дата
  изменения, требуемая смена, число неверных попыток входа).
- Навигация по дереву подразделений (OU).
- Создание учётных записей: имя, логин, UPN, e-mail, описание, пароль, выбор
  OU по дереву, срок действия, выбор групп; проверка на уже существующий логин.
- Включение, отключение, разблокировка учётных записей.
- Сброс пароля.
- Управление членством в группах.
- Перемещение учётных записей между подразделениями.
- Изменение атрибутов.
- Список доменов с переключением; смена домена под учётными данными активной сессии.

Даты в русской версии — в формате `ДД МММ ГГГГ` (например, `14 авг 2026`).

## Структура репозитория

```
ADUC-Ext/
├── windows/                 # Версия для Windows (PowerShell + WPF)
│   ├── ADUC-Ext.ps1         # английская
│   ├── ADUC-Ext-ru.ps1      # русская
│   ├── build_exe.ps1        # сборка .exe (английская)
│   ├── build_exe_ru.ps1     # сборка .exe (русская)
│   └── aduc_ext.ico
├── macos/                   # Версия для macOS (Python + Tkinter)
│   ├── aduc_ext.py          # английская
│   ├── aduc_ext_ru.py       # русская
│   ├── build_app.sh         # сборка .app (английская)
│   ├── build_app_ru.sh      # сборка .app (русская)
│   └── aduc_ext.icns
├── assets/                  # иконка
├── README.md · README_ru.md
└── RELEASE_NOTES.md
```

## Быстрый старт

### Windows

```powershell
cd windows
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext-ru.ps1   # русская
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext.ps1      # английская
```

Нужны Windows PowerShell 5.1 и модуль **ActiveDirectory** (RSAT). При его отсутствии
приложение предложит установить RSAT автоматически (нужны права администратора).
Сборка `.exe` — скриптами `build_exe_ru.ps1` / `build_exe.ps1`.

### macOS

```bash
cd macos
python3 aduc_ext_ru.py   # русская
python3 aduc_ext.py      # английская
```

Нужен Python 3.8+ с Tkinter; пакет `ldap3` ставится автоматически при первом
запуске. Рекомендуется LDAPS (порт 636): смена пароля и создание учётной записи
с паролем требуют защищённого соединения. Сборка `.app` — `build_app_ru.sh` /
`build_app.sh`.

## Настройка

В начале каждого файла можно задать:

- **Подразделение (OU) для выбора групп** — по умолчанию не задано (показываются все
  группы домена):
  - Windows: `$Global:AccessGroupsOUName = "Имя OU"`
  - macOS: `ACCESS_GROUPS_OU_NAME = "Имя OU"`
- **Группы, добавляемые автоматически при создании** — по умолчанию пусто:
  - Windows: `$Global:DefaultCreateGroups = @('group1','group2')`
  - macOS: `DEFAULT_CREATE_GROUPS = ['group1', 'group2']`

## Хранение настроек

Список доменов сохраняется локально (пароли не хранятся):

| Версия | Windows | macOS |
|---|---|---|
| Английская | `%APPDATA%\ADUC-Ext\domains.json` | `~/.aduc_ext_domains.json` |
| Русская | `%APPDATA%\ADUC-Ext-ru\domains.json` | `~/.aduc_ext_ru_domains.json` |

## Безопасность

- Пароль хранится только в памяти процесса на время сессии.
- Используйте учётную запись с минимально необходимыми правами.
- Часть операций требует соответствующих прав в каталоге; при их отсутствии
  операция завершится сообщением об отказе в доступе.

## Распространение

Предоставляется «как есть» для внутреннего использования. Публичная лицензия
не предоставляется; все права защищены.

## На развитие проекта

💛 https://dalink.to/rderensky
