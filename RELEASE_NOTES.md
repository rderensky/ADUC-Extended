# ADUC-Extended v1.0.2

## What's new / Что нового

- **Computer objects** — a Users / Computers mode toggle: search, properties,
  rename, move between OUs, edit description, enable/disable, delete.
  **Компьютеры** — переключатель «Пользователи / Компьютеры»: поиск, свойства,
  переименование, перенос между OU, изменение описания, включение/отключение,
  удаление.
- **Multi-select** in the list with bulk actions: enable, disable, move to an
  OU, and bulk add of selected users to access groups.
  **Множественный выбор** в списке с групповыми действиями: включить,
  отключить, переместить в OU, а также групповое добавление пользователей
  в группы доступа.
- **"Password never expires"** flag management: action button, checkable
  context-menu item, and a checkbox in the edit dialog. Like ADUC, enabling
  the flag also cancels a pending change-at-next-logon requirement.
  Управление флагом **«срок действия пароля не ограничен»**: кнопка действия,
  отмечаемый пункт контекстного меню и чекбокс в окне изменения. Как в ADUC,
  установка флага снимает требование смены пароля при следующем входе.
- **Double-click** on a list row opens the edit dialog (users and computers).
  **Двойной клик** по строке списка открывает окно редактирования.
- macOS: automatic reconnect after an idle LDAP timeout (no more "Broken
  pipe" after the app sits unused).
  macOS: автоматическое переподключение после простоя LDAP-соединения.
- Windows: fixed a crash on connect (context-menu wiring) and a toolbar
  layout where the mode toggle was clipped.
  Windows: исправлены падение при подключении (привязка контекстного меню)
  и вёрстка панели, где переключатель режимов обрезался.

## Downloads / Загрузки

Each asset contains **both English and Russian** versions and READMEs in both
languages. / Каждый архив содержит **английскую и русскую** версии и README на
двух языках.

| Platform / Платформа | Source / Исходники | Binaries / Бинарники |
|---|---|---|
| Windows | `ADUC-Ext-1.0.2-windows.zip` | `ADUC-Ext-1.0.2-win-exe.zip` |
| macOS   | `ADUC-Ext-1.0.2-macos.zip`   | `ADUC-Ext-1.0.2-mac-app-en.zip`, `ADUC-Ext-1.0.2-mac-app-ru.zip` |

## Requirements / Требования
- Windows: PowerShell 5.1 + ActiveDirectory module (RSAT); the app offers to
  install RSAT if missing.
- macOS: Python 3.8+ with Tkinter; `ldap3` is installed automatically.

## SHA-256 (source archives)
```
2a78c18b171e03160cd0a20c90f595a3b9f8bdc86974bdb3d8fae4774d2be8dd  ADUC-Ext-1.0.2-windows.zip
e3cbc3f4b9bfa6b8174983eb46297f7d87d37e63114becfb0f71cff2154ea295  ADUC-Ext-1.0.2-macos.zip
```
