<#
.SYNOPSIS
    ADUC-Ext — Active Directory account management (WPF).

.DESCRIPTION
    On startup the application prompts for credentials and performs all
    directory operations under the specified account.

    Features:
      - search and view user properties;
      - navigate organizational units (OUs);
      - create accounts;
      - enable, disable, and unlock;
      - reset password;
      - manage group membership;
      - move between organizational units;
      - edit attributes.

.REQUIREMENTS
      - Windows with the ActiveDirectory module (RSAT); if missing the app
        offers to install it automatically.
      - An account with rights for the corresponding directory operations.
      - Windows PowerShell 5.1, run in STA mode.

.NOTES
    Run:
        powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext.ps1
#>

#region ------------------------- Initialization -----------------------------

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Built-in WPF strings (e.g. the DatePicker watermark) follow the
# interface language; applied after the language is initialized.
function Set-UiCulture {
    [System.Threading.Thread]::CurrentThread.CurrentUICulture =
        [System.Globalization.CultureInfo]::GetCultureInfo((L 'en-US'))
}

$ErrorActionPreference = 'Stop'

# ============================================================================
#  Localization (EN / RU)
# ============================================================================
$Script:Lang = 'en'   # current interface language: 'en' or 'ru'

$Script:RuStrings = @{
    "en-US" = "ru-RU"
    "The PowerShell module 'ActiveDirectory' (RSAT) is not installed.`n`n" = "Модуль PowerShell 'ActiveDirectory' (RSAT) не установлен.`n`n"
    "Install it automatically now?`n" = "Установить его сейчас автоматически?`n"
    "Administrator rights and a Windows Update connection are required. " = "Потребуются права администратора и подключение к Windows Update. "
    "Installation may take a few minutes." = "Установка может занять несколько минут."
    "Checking dependencies" = "Проверка зависимостей"
    "The application cannot run without the ActiveDirectory module.`n`n" = "Без модуля ActiveDirectory приложение работать не может.`n`n"
    "Install RSAT manually (as administrator):`n" = "Установите RSAT вручную (от администратора):`n"
    "ActiveDirectory module missing" = "Отсутствует модуль ActiveDirectory"
    "Installing RSAT requires administrator rights.`n`n" = "Для установки RSAT нужны права администратора.`n`n"
    "Run the application as administrator or install it manually:`n" = "Запустите приложение от имени администратора либо установите вручную:`n"
    "Insufficient rights" = "Недостаточно прав"
    "ActiveDirectory module (RSAT) installed successfully." = "Модуль ActiveDirectory (RSAT) успешно установлен."
    "Failed to install RSAT automatically.`n`n" = "Не удалось установить RSAT автоматически.`n`n"
    "Install manually (as administrator):`n" = "Установите вручную (от администратора):`n"
    "On Windows Server:`n" = "На Windows Server:`n"
    "RSAT installation error" = "Ошибка установки RSAT"
    "Error" = "Ошибка"
    "Information" = "Информация"
    "Confirm" = "Подтверждение"
    "Connect to Active Directory" = "Подключение к Active Directory"
    "Enter credentials to connect to the domain" = "Введите учётные данные для подключения к домену"
    "Saved domain:" = "Сохранённый домен:"
    "Remove the selected domain from the list" = "Удалить выбранный домен из списка"
    "Domain / DC:" = "Домен / DC:"
    "For example: contoso.local or dc01.contoso.local (leave empty for the current domain)" = "Например: contoso.local или dc01.contoso.local (можно оставить пустым для текущего домена)"
    "User:" = "Пользователь:"
    "For example: CONTOSO\admin or admin@contoso.local" = "Например: CONTOSO\admin или admin@contoso.local"
    "Password:" = "Пароль:"
    "Save domain to the list" = "Сохранить домен в список"
    "Connect" = "Подключиться"
    "Cancel" = "Отмена"
    "Remove '{0}' from the domain list?" = "Удалить '{0}' из списка доменов?"
    "Checking connection..." = "Проверка подключения..."
    "Enter a user name and password." = "Укажите имя пользователя и пароль."
    "Failed to connect: {0}" = "Не удалось подключиться: {0}"
    "ADUC-Ext — Active Directory user management" = "ADUC-Ext — управление пользователями Active Directory"
    "Domain:" = "Домен:"
    "Select a saved domain or enter a controller/domain name" = "Выберите сохранённый домен или введите имя контроллера/домена"
    "Switch domain" = "Сменить домен"
    "Search:" = "Поиск:"
    "Name, login (sAMAccountName), e-mail, or part of a value" = "Имя, логин (sAMAccountName), e-mail или часть значения"
    "Find" = "Найти"
    "Refresh" = "Обновить"
    "Create user" = "Создать пользователя"
    "Show:" = "Показывать:"
    "Users" = "Пользователи"
    "Computers" = "Компьютеры"
    "Nested OUs" = "Вложенные OU"
    "Show objects from nested organizational units" = "Показывать объекты из вложенных подразделений"
    "Organizational units" = "Подразделения"
    "Name" = "Имя"
    "Login" = "Логин"
    "Description" = "Описание"
    "State" = "Состояние"
    "Copy login" = "Копировать логин"
    "Copy display name" = "Копировать отображаемое имя"
    "Copy e-mail" = "Копировать e-mail"
    "Copy UPN" = "Копировать UPN"
    "Copy DN" = "Копировать DN"
    "Copy all properties" = "Копировать все свойства"
    "Enable" = "Включить"
    "Disable" = "Отключить"
    "Unlock" = "Разблокировать"
    "Reset password..." = "Сбросить пароль..."
    "Password never expires" = "Срок действия пароля не ограничен"
    "Groups..." = "Группы..."
    "Move (OU)..." = "Переместить (OU)..."
    "Edit..." = "Изменить..."
    "Rename..." = "Переименовать..."
    "Delete" = "Удалить"
    "User properties" = "Свойства пользователя"
    "Select a user from the list" = "Выберите пользователя из списка"
    "Actions" = "Действия"
    "Reset password" = "Сбросить пароль"
    "Pwd never expires" = "Бессрочный пароль"
    "Set or clear the 'password never expires' flag" = "Установить или снять флаг «срок действия пароля не ограничен»"
    "Move (OU)" = "Переместить (OU)"
    "Locked" = "Заблокирован"
    "Disabled" = "Отключено"
    "Active" = "Активна"
    "First name:" = "Имя:"
    "(controller list unavailable: {0})" = "(список контроллеров недоступен: {0})"
    "Last name:" = "Фамилия:"
    "Display name:" = "Отображаемое имя:"
    "Login (sAM):" = "Логин (sAM):"
    "UPN suffix:" = "UPN-суффикс:"
    "For example: @contoso.local" = "Например: @contoso.local"
    "Description:" = "Описание:"
    "Organizational unit (OU):" = "Подразделение (OU):"
    "Browse…" = "Обзор…"
    "OU where the user will be created" = "Подразделение, где будет создан пользователь"
    "Expires:" = "Срок действия:"
    "Valid through (incl.):" = "Действует по (вкл.):"
    "Format: YYYY-MMM-DD" = "Формат: ДД МММ ГГГГ"
    "Groups on creation:" = "Группы доступа при создании:"
    "Select groups..." = "Выбрать группы..."
    "Remove selected" = "Убрать выбранные"
    "Change password at next logon" = "Сменить пароль при следующем входе"
    "Account enabled" = "Учётная запись включена"
    "Create" = "Создать"
    "Default groups not found: " = "Не найдены группы по умолчанию: "
    "Specify a login (sAMAccountName)." = "Укажите логин (sAMAccountName)."
    "Specify a password." = "Укажите пароль."
    "Enter an expiration date or clear the checkbox." = "Укажите дату срока действия или снимите галочку."
    "A user with login `"{0}`" already exists in the domain." = "Пользователь с логином «{0}» уже существует в домене."
    "User created, but not added to all groups:`n" = "Пользователь создан, но добавлен не во все группы:`n"
    "Error: {0}" = "Ошибка: {0}"
    "New password:" = "Новый пароль:"
    "Confirm:" = "Подтверждение:"
    "Unlock the account" = "Разблокировать учётную запись"
    "Apply" = "Применить"
    "User: {0} ({1})" = "Пользователь: {0} ({1})"
    "Enter a new password." = "Введите новый пароль."
    "Passwords do not match." = "Пароли не совпадают."
    "Move to organizational unit" = "Перемещение в подразделение"
    "Current location:" = "Текущее размещение:"
    "Target container (OU):" = "Целевой контейнер (OU):"
    "Move" = "Переместить"
    "Object: {0} ({1})" = "Объект: {0} ({1})"
    "Objects selected: {0} ({1})" = "Выбрано объектов: {0} ({1})"
    "(objects are in different containers)" = "(объекты в разных контейнерах)"
    "Specify a target container." = "Укажите целевой контейнер."
    "Moved: {0} of {1}.`r`n{2}" = "Перемещено: {0} из {1}.`r`n{2}"
    "Rename object" = "Переименование объекта"
    "New name:" = "Новое имя:"
    "Rename" = "Переименовать"
    "Object: {0}" = "Объект: {0}"
    "Enter a name." = "Введите имя."
    "Edit computer" = "Изменить компьютер"
    "Name:" = "Имя:"
    "DNS name:" = "DNS-имя:"
    "Save" = "Сохранить"
    "Select organizational unit (OU)" = "Выбор подразделения (OU)"
    "Select" = "Выбрать"
    "Select groups" = "Выбор групп доступа"
    "Filter:" = "Фильтр:"
    "Groups (Ctrl/Shift — multi-select):" = "Группы (Ctrl/Shift — множественный выбор):"
    "Failed to retrieve groups: {0}" = "Не удалось получить группы: {0}"
    "Group membership" = "Членство в группах"
    "Add..." = "Добавить..."
    "Remove from selected groups" = "Удалить из выбранных групп"
    "Close" = "Закрыть"
    "User groups: {0} ({1})" = "Группы пользователя: {0} ({1})"
    "Failed to retrieve the group list: {0}" = "Не удалось получить список групп: {0}"
    "Failed to add to group: {0}" = "Не удалось добавить в группу: {0}"
    "Remove the user from the selected groups ({0})?" = "Удалить пользователя из выбранных групп ({0})?"
    "Failed to remove from group '{0}': {1}" = "Не удалось удалить из группы '{0}': {1}"
    "'{0}': the object is no longer a member of this group — the list was outdated and has been refreshed." = "«{0}»: объект уже не является членом этой группы — список был устаревшим и обновлён."
    "Notice" = "Уведомление"
    "`n`nThe account was also tried as {0} — not accepted. With a trust between the domains, check that its direction lets the target domain authenticate this account and, with selective authentication, that `"Allowed to authenticate`" is granted on its domain controllers. For a domain in another forest without a trust choose `"Another account`" and enter a login of that domain." = "`n`nУчётная запись также была опробована как {0} — не принята. Если между доменами настроено доверие, проверьте, что его направление позволяет целевому домену проверять подлинность этой учётной записи, а при выборочной проверке подлинности — что на его контроллерах выдано право «Разрешена проверка подлинности». Для домена другого леса без доверия выберите «Другая учётная запись» и укажите логин этого домена."
    "`n`nBind attempts (variant — server reply):`n{0}" = "`n`nПопытки подключения (вариант — ответ сервера):`n{0}"
    "`nThe same details are appended to {0}." = "`nЭти же сведения дописаны в {0}."
    "All saved domains" = "Все сохранённые домены"
    "Domain" = "Домен"
    "scope: all saved domains" = "все сохранённые домены"
    "; unavailable: {0}" = "; недоступны: {0}"
    "Object from another domain" = "Объект из другого домена"
    '"{0}" belongs to domain {1}.`r`nActions are available only in the connected domain.`r`n`r`nSwitch to domain {1} now?' = '«{0}» принадлежит домену {1}.`r`nДействия доступны только в подключённом домене.`r`n`r`nПереключиться на домен {1} сейчас?'
    "The selection contains objects from other domains ({0}). Bulk actions apply only to the connected domain." = "В выделении есть объекты из других доменов ({0}). Массовые действия применяются только к подключённому домену."
    "The pending 'change password at next logon' requirement will be removed; the current password stays valid (same as in ADUC)." = "Стоящее требование смены пароля при следующем входе будет снято, и прежний пароль останется действительным (как в оснастке ADUC)."
    "The date is stored in the account ({0}); the flag is cleared by the app when the date is reached." = "Дата хранится в учётной записи ({0}); при её наступлении приложение снимает флаг."
    "Select a date." = "Выберите дату."
    "The date must be later than today." = "Дата должна быть позже сегодняшней."
    "`r`n`r`nThe flag will be cleared automatically on {0}." = "`r`n`r`nФлаг будет снят автоматически {0}."
    "Flag auto-clear date" = "Дата автоснятия флага"
    "'Password never expires' cleared (date reached): {0}" = "Снят флаг «срок пароля не ограничен» (дата наступила): {0}"
    "Password never expires: cleared automatically (date reached)" = "Срок действия пароля не ограничен: снято автоматически (дата наступила)"
    'Connect to domain "{0}" as:' = 'Подключиться к домену «{0}» как:'
    "Current account ({0})" = "Текущая учётная запись ({0})"
    "Enter the user name and password." = "Введите имя пользователя и пароль."
    "History..." = "История..."
    "Object history..." = "История объекта..."
    "Only this object: {0}" = "Только этот объект: {0}"
    "Records: {0} of {1}. File: {2}" = "Записей: {0} из {1}. Файл: {2}"
    "Enable account" = "Включение учётной записи"
    "Disable account" = "Отключение учётной записи"
    "Unlock account" = "Разблокировка учётной записи"
    "Password never expires: on" = "Срок действия пароля не ограничен: включено"
    "Password never expires: off" = "Срок действия пароля не ограничен: выключено"
    "Add to group" = "Добавление в группу"
    "Remove from group" = "Удаление из группы"
    "Edit properties" = "Изменение свойств"
    "Create group" = "Создание группы"
    "By domain controller (non-replicated attributes)" = "По контроллерам домена (нереплицируемые атрибуты)"
    "bad pwd" = "неверный пароль:"
    "DC" = "КД"
    "Logon" = "Вход"
    "Bad password" = "Неверный пароль"
    "Attempts" = "Попыток"
    "(unavailable)" = "(недоступен)"
    'An object named "{0}" already exists in the target container.`r`nEnter a new full name for the object being moved:' = 'В целевом контейнере уже есть объект с именем «{0}».`r`nВведите новое полное имя для перемещаемого объекта:'
    "Not moved: an object with this name already exists in the target container." = "Не перемещено: в целевом контейнере уже есть объект с таким именем."
    "Edit user properties" = "Изменение свойств пользователя"
    "Title:" = "Должность:"
    "Department:" = "Отдел:"
    "Company:" = "Компания:"
    "Office:" = "Кабинет:"
    "Phone:" = "Телефон:"
    "Group membership (Member Of):" = "Группы доступа (Member Of):"
    'Selected to add ({0}):' = 'Выбрано для добавления ({0}):'
    "Remove from the selected groups ({0})?" = "Удалить из выбранных групп ({0})?"
    "Connected to: {0}   |   User: {1}" = "Подключено к: {0}   |   Пользователь: {1}"
    "at next logon (change required)" = "при следующем входе (требуется смена)"
    "never (password does not expire)" = "никогда (пароль не истекает)"
    "never" = "никогда"
    " (expired)" = " (просрочен)"
    "Account name" = "Имя учётной записи"
    "DNS name" = "DNS-имя"
    "Operating system" = "Операционная система"
    "OS version" = "Версия ОС"
    "Last logon" = "Последний вход"
    "Created" = "Создан"
    "Display name" = "Отображаемое имя"
    "First name" = "Имя"
    "Last name" = "Фамилия"
    "Password..." = "Пароль…"
    "Length: {0}" = "Длина: {0}"
    "Select at least one character set." = "Выберите хотя бы один набор символов."
    "Password generated and copied to clipboard." = "Пароль создан и скопирован в буфер обмена."
    "Password inserted and copied to clipboard." = "Пароль подставлен и скопирован в буфер обмена."
    "E-mail addresses (Exchange)" = "Почтовые адреса (Exchange)"
    "primary" = "основной"
    "(no mailbox: the user has no Exchange addresses)" = "(почтового ящика нет: у пользователя нет адресов Exchange)"
    "Yes" = "Да"
    "No" = "Нет"
    "Title" = "Должность"
    "Department" = "Отдел"
    "Company" = "Компания"
    "Office" = "Кабинет"
    "Phone" = "Телефон"
    "Password last set" = "Пароль изменён"
    "Password change required" = "Требуется смена пароля"
    "Bad password attempts" = "Неверных попыток входа"
    "Last bad password" = "Последний неверный ввод"
    "Expires" = "Истекает"
    "Copy value ({0})" = "Копировать значение ({0})"
    "{0}   |   Copied" = "{0}   |   Скопировано"
    "{0} (+nested)" = "{0} (+вложенные)"
    "Connected to: {0}   |   " = "Подключено к: {0}   |   "
    "User: {0}   |   " = "Пользователь: {0}   |   "
    "Scope: {0}   |   Found: {1}" = "Область: {0}   |   Найдено: {1}"
    "Search error: {0}" = "Ошибка поиска: {0}"
    "This action applies to a single object.`r`nSelect exactly one item in the list." = "Это действие применимо к одному объекту.`r`nВыберите ровно один элемент списка."
    "Multiple objects selected" = "Выбрано несколько объектов"
    "Select a user in the list first." = "Сначала выберите пользователя в списке."
    "No user selected" = "Не выбран пользователь"
    "Select one or more objects in the list." = "Выберите один или несколько объектов в списке."
    "No object selected" = "Не выбран объект"
    "Computer properties" = "Свойства компьютера"
    "Select from the list or enter a domain/controller." = "Выберите из списка или введите домен/контроллер."
    "Access error: failed to connect to domain `"{0}`" " = "Ошибка доступа: не удалось подключиться к домену «{0}» "
    "with the current account ({0}).`n`n" = "под текущей учётной записью ({0}).`n`n"
    "Insufficient rights or the domain is unavailable:`n{0}" = "Недостаточно прав или домен недоступен:`n{0}"
    "User: {0}" = "Пользователь: {0}"
    "Connected to domain `"{0}`" as {1}." = "Подключено к домену «{0}» под учётной записью {1}."
    "Selected objects: {0}`r`n`r`nAvailable bulk actions:`r`nEnable / Disable / Move (OU)`r`nAdd to groups (users)" = "Выбрано объектов: {0}`r`n`r`nДоступные групповые действия:`r`nВключить / Отключить / Переместить (OU)`r`nДобавить в группы (пользователи)"
    "User created." = "Пользователь создан."
    "{0}: {1} of {2}.`r`n`r`nErrors:`r`n{3}" = "{0}: {1} из {2}.`r`n`r`nОшибки:`r`n{3}"
    "Partially completed" = "Выполнено частично"
    "Account enabled." = "Учётная запись включена."
    "Failed to enable: {0}" = "Не удалось включить: {0}"
    "Enable {0} accounts?" = "Включить учётные записи: {0}?"
    "Enabled" = "Включено"
    "Disable account '{0}'?" = "Отключить учётную запись '{0}'?"
    "Account disabled." = "Учётная запись отключена."
    "Failed to disable: {0}" = "Не удалось отключить: {0}"
    "Disable {0} accounts?" = "Отключить учётные записи: {0}?"
    "Account unlocked." = "Учётная запись разблокирована."
    "Failed to unlock: {0}" = "Не удалось разблокировать: {0}"
    "Password reset." = "Пароль сброшен."
    "Set the 'password never expires' flag for '{0}'?" = "Установить флаг «срок действия пароля не ограничен» у '{0}'?"
    "`r`n`r`nThe pending 'change password at next logon' requirement will be removed; the current password stays valid (same as in ADUC)." = "`r`n`r`nТребование смены пароля при следующем входе будет снято, и прежний пароль останется действительным (как в оснастке ADUC)."
    "Clear the 'password never expires' flag for '{0}'?`r`n`r`nThe password will expire per the domain policy." = "Снять флаг «срок действия пароля не ограничен» у '{0}'?`r`n`r`nПароль будет истекать по политике домена."
    "Flag set: the password never expires.`r`n`r`nThe 'change password at next logon' requirement was removed; the current password stays valid." = "Флаг установлен: срок действия пароля не ограничен.`r`n`r`nТребование смены пароля при следующем входе снято; прежний пароль остаётся действительным."
    "Flag set: the password never expires." = "Флаг установлен: срок действия пароля не ограничен."
    "Flag cleared: the password expires per the domain policy." = "Флаг снят: пароль истекает по политике домена."
    "Failed to change the flag: {0}" = "Не удалось изменить флаг: {0}"
    "Add {0} users to {1} group(s)?" = "Добавить пользователей ({0}) в группы ({1})?"
    "Added: {0}." = "Добавлено: {0}."
    "{0}`r`n`r`nErrors:`r`n{1}" = "{0}`r`n`r`nОшибки:`r`n{1}"
    "Object moved." = "Объект перемещён."
    "Objects moved: {0}." = "Объектов перемещено: {0}."
    "Changes saved." = "Изменения сохранены."
    "Object renamed." = "Объект переименован."
    "Delete object '{0}'?`r`n`r`nThis operation is irreversible." = "Удалить объект «{0}»?`r`n`r`nЭта операция необратима."
    "Object deleted." = "Объект удалён."
    "Failed to delete: {0}" = "Не удалось удалить: {0}"
    "Groups" = "Группы"
    "Group properties" = "Свойства группы"
    "Scope" = "Область"
    "Category" = "Категория"
    "Members" = "Участники"
    "Members..." = "Участники..."
    "Create group..." = "Создать группу..."
    "Global" = "Глобальная"
    "Domain local" = "Локальная в домене"
    "Universal" = "Универсальная"
    "Security" = "Безопасности"
    "Distribution" = "Рассылки"
    "Enter a group name." = "Укажите имя группы."
    "Group created." = "Группа создана."
    "Group: {0}" = "Группа: {0}"
    "Deleted: {0}." = "Удалено: {0}."
    "Removed: {0}." = "Удалено из группы: {0}."
    "Remove selected members ({0}) from the group?" = "Удалить выбранных участников ({0}) из группы?"
    "Delete {0} groups?`r`n`r`nThis operation is irreversible." = "Удалить группы ({0})?`r`n`r`nЭта операция необратима."
    "Selected objects: {0}`r`n`r`nAvailable bulk actions:`r`nMove (OU) / Delete" = "Выбрано объектов: {0}`r`n`r`nДоступные групповые действия:`r`nПереместить (OU) / Удалить"
    'Domain controller "{0}" is unreachable. Check the server name and network connectivity.' = 'Контроллер домена «{0}» недоступен. Проверьте имя сервера и сетевую доступность.'
}

$Script:XamlRu = @{
    "Title=`"Connect to Active Directory`"" = "Title=`"Подключение к Active Directory`""
    "Text=`"Enter credentials to connect to the domain`"" = "Text=`"Введите учётные данные для подключения к домену`""
    "Text=`"Saved domain:`"" = "Text=`"Сохранённый домен:`""
    "ToolTip=`"Remove the selected domain from the list`"" = "ToolTip=`"Удалить выбранный домен из списка`""
    "Text=`"Domain / DC:`"" = "Text=`"Домен / DC:`""
    "ToolTip=`"For example: contoso.local or dc01.contoso.local (leave empty for the current domain)`"" = "ToolTip=`"Например: contoso.local или dc01.contoso.local (можно оставить пустым для текущего домена)`""
    "Text=`"User:`"" = "Text=`"Пользователь:`""
    "ToolTip=`"For example: CONTOSO\admin or admin@contoso.local`"" = "ToolTip=`"Например: CONTOSO\admin или admin@contoso.local`""
    "Text=`"Password:`"" = "Text=`"Пароль:`""
    "Content=`"Save domain to the list`"" = "Content=`"Сохранить домен в список`""
    "Content=`"Connect`"" = "Content=`"Подключиться`""
    "Content=`"Cancel`"" = "Content=`"Отмена`""
    "Title=`"ADUC-Ext — Active Directory user management`"" = "Title=`"ADUC-Ext — управление пользователями Active Directory`""
    "Text=`"Domain:`"" = "Text=`"Домен:`""
    "ToolTip=`"Select a saved domain or enter a controller/domain name`"" = "ToolTip=`"Выберите сохранённый домен или введите имя контроллера/домена`""
    "Content=`"Switch domain`"" = "Content=`"Сменить домен`""
    "Text=`"Search:`"" = "Text=`"Поиск:`""
    "ToolTip=`"Name, login (sAMAccountName), e-mail, or part of a value`"" = "ToolTip=`"Имя, логин (sAMAccountName), e-mail или часть значения`""
    "Content=`"Find`"" = "Content=`"Найти`""
    "Content=`"Refresh`"" = "Content=`"Обновить`""
    "Content=`"Create user`"" = "Content=`"Создать пользователя`""
    "Text=`"Show:`"" = "Text=`"Показывать:`""
    "Content=`"Users`"" = "Content=`"Пользователи`""
    "Content=`"Computers`"" = "Content=`"Компьютеры`""
    "Content=`"Nested OUs`"" = "Content=`"Вложенные OU`""
    "ToolTip=`"Show objects from nested organizational units`"" = "ToolTip=`"Показывать объекты из вложенных подразделений`""
    "Text=`"Organizational units`"" = "Text=`"Подразделения`""
    "Header=`"Name`"" = "Header=`"Имя`""
    "Header=`"Login`"" = "Header=`"Логин`""
    "Header=`"Description`"" = "Header=`"Описание`""
    "Header=`"State`"" = "Header=`"Состояние`""
    "Header=`"Copy login`"" = "Header=`"Копировать логин`""
    "Header=`"Copy display name`"" = "Header=`"Копировать отображаемое имя`""
    "Header=`"Copy e-mail`"" = "Header=`"Копировать e-mail`""
    "Header=`"Copy UPN`"" = "Header=`"Копировать UPN`""
    "Header=`"Copy DN`"" = "Header=`"Копировать DN`""
    "Header=`"Copy all properties`"" = "Header=`"Копировать все свойства`""
    "Header=`"Enable`"" = "Header=`"Включить`""
    "Header=`"Disable`"" = "Header=`"Отключить`""
    "Header=`"Unlock`"" = "Header=`"Разблокировать`""
    "Header=`"Reset password...`"" = "Header=`"Сбросить пароль...`""
    "Header=`"Password never expires`"" = "Header=`"Срок действия пароля не ограничен`""
    "Header=`"Groups...`"" = "Header=`"Группы...`""
    "Header=`"Move (OU)...`"" = "Header=`"Переместить (OU)...`""
    "Header=`"Edit...`"" = "Header=`"Изменить...`""
    "Header=`"Rename...`"" = "Header=`"Переименовать...`""
    "Header=`"Delete`"" = "Header=`"Удалить`""
    "Header=`"User properties`"" = "Header=`"Свойства пользователя`""
    "Text=`"Select a user from the list`"" = "Text=`"Выберите пользователя из списка`""
    "Header=`"Actions`"" = "Header=`"Действия`""
    "Content=`"Enable`"" = "Content=`"Включить`""
    "Content=`"Disable`"" = "Content=`"Отключить`""
    "Content=`"Unlock`"" = "Content=`"Разблокировать`""
    "Content=`"Reset password`"" = "Content=`"Сбросить пароль`""
    "Content=`"Pwd never expires`"" = "Content=`"Бессрочный пароль`""
    "ToolTip=`"Set or clear the 'password never expires' flag`"" = "ToolTip=`"Установить или снять флаг «срок действия пароля не ограничен»`""
    "Content=`"Groups...`"" = "Content=`"Группы...`""
    "Content=`"Move (OU)`"" = "Content=`"Переместить (OU)`""
    "Content=`"Edit...`"" = "Content=`"Изменить...`""
    "Content=`"Rename...`"" = "Content=`"Переименовать...`""
    "Content=`"Delete`"" = "Content=`"Удалить`""
    "Title=`"Create user`"" = "Title=`"Создание пользователя`""
    "Text=`"First name:`"" = "Text=`"Имя:`""
    "Text=`"Last name:`"" = "Text=`"Фамилия:`""
    "Text=`"Display name:`"" = "Text=`"Отображаемое имя:`""
    "Text=`"Login (sAM):`"" = "Text=`"Логин (sAM):`""
    "Text=`"UPN suffix:`"" = "Text=`"UPN-суффикс:`""
    "ToolTip=`"For example: @contoso.local`"" = "ToolTip=`"Например: @contoso.local`""
    "Text=`"Description:`"" = "Text=`"Описание:`""
    "Text=`"Organizational unit (OU):`"" = "Text=`"Подразделение (OU):`""
    "Content=`"Browse…`"" = "Content=`"Обзор…`""
    "ToolTip=`"OU where the user will be created`"" = "ToolTip=`"Подразделение, где будет создан пользователь`""
    "Text=`"Expires:`"" = "Text=`"Срок действия:`""
    "Content=`"Valid through (incl.):`"" = "Content=`"Действует по (вкл.):`""
    "Language=`"en-US`"" = "Language=`"ru-RU`""
    "ToolTip=`"Format: YYYY-MMM-DD`"" = "ToolTip=`"Формат: ДД МММ ГГГГ`""
    "Text=`"Groups on creation:`"" = "Text=`"Группы доступа при создании:`""
    "Content=`"Select groups...`"" = "Content=`"Выбрать группы...`""
    "Content=`"Remove selected`"" = "Content=`"Убрать выбранные`""
    "Content=`"Change password at next logon`"" = "Content=`"Сменить пароль при следующем входе`""
    "Content=`"Account enabled`"" = "Content=`"Учётная запись включена`""
    "Content=`"Create`"" = "Content=`"Создать`""
    "Title=`"Reset password`"" = "Title=`"Сброс пароля`""
    "Text=`"New password:`"" = "Text=`"Новый пароль:`""
    "Text=`"Confirm:`"" = "Text=`"Подтверждение:`""
    "Content=`"Unlock the account`"" = "Content=`"Разблокировать учётную запись`""
    "Content=`"Apply`"" = "Content=`"Применить`""
    "Title=`"Move to organizational unit`"" = "Title=`"Перемещение в подразделение`""
    "Text=`"Current location:`"" = "Text=`"Текущее размещение:`""
    "Text=`"Target container (OU):`"" = "Text=`"Целевой контейнер (OU):`""
    "Content=`"Move`"" = "Content=`"Переместить`""
    "Title=`"Rename object`"" = "Title=`"Переименование объекта`""
    "Text=`"New name:`"" = "Text=`"Новое имя:`""
    "Content=`"Rename`"" = "Content=`"Переименовать`""
    "Title=`"Edit computer`"" = "Title=`"Изменить компьютер`""
    "Text=`"Name:`"" = "Text=`"Имя:`""
    "Text=`"DNS name:`"" = "Text=`"DNS-имя:`""
    "Content=`"Save`"" = "Content=`"Сохранить`""
    "Title=`"Select organizational unit (OU)`"" = "Title=`"Выбор подразделения (OU)`""
    "Content=`"Select`"" = "Content=`"Выбрать`""
    "Title=`"Select groups`"" = "Title=`"Выбор групп доступа`""
    "Text=`"Filter:`"" = "Text=`"Фильтр:`""
    "Text=`"Groups (Ctrl/Shift — multi-select):`"" = "Text=`"Группы (Ctrl/Shift — множественный выбор):`""
    "Title=`"Group membership`"" = "Title=`"Членство в группах`""
    "Content=`"Add...`"" = "Content=`"Добавить...`""
    "Content=`"Remove from selected groups`"" = "Content=`"Удалить из выбранных групп`""
    "Content=`"Close`"" = "Content=`"Закрыть`""
    "Title=`"Password generator`"" = "Title=`"Генератор паролей`""
    "Content=`"Lowercase letters (a-z)`"" = "Content=`"Строчные буквы (a-z)`""
    "Content=`"Uppercase letters (A-Z)`"" = "Content=`"Заглавные буквы (A-Z)`""
    "Content=`"Digits (0-9)`"" = "Content=`"Цифры (0-9)`""
    "Content=`"Special characters (!@#$%^&amp;*-_=+?)`"" = "Content=`"Спецсимволы (!@#$%^&amp;*-_=+?)`""
    "Content=`"Exclude look-alike characters (O/0, I/l/1, S/5, Z/2, B/8)`"" = "Content=`"Исключить похожие символы (O/0, I/l/1, S/5, Z/2, B/8)`""
    "Content=`"Generate`"" = "Content=`"Создать`""
    "Content=`"Generate...`"" = "Content=`"Создать…`""
    "Content=`"Copy`"" = "Content=`"Копировать`""
    "Content=`"Use`"" = "Content=`"Использовать`""
    "Content=`"Password...`"" = "Content=`"Пароль…`""
    "Title=`"Edit user properties`"" = "Title=`"Изменение свойств пользователя`""
    "Text=`"Title:`"" = "Text=`"Должность:`""
    "Text=`"Department:`"" = "Text=`"Отдел:`""
    "Text=`"Company:`"" = "Text=`"Компания:`""
    "Text=`"Office:`"" = "Text=`"Кабинет:`""
    "Text=`"Phone:`"" = "Text=`"Телефон:`""
    "Content=`"Password never expires`"" = "Content=`"Срок действия пароля не ограничен`""
    "Text=`"Group membership (Member Of):`"" = "Text=`"Группы доступа (Member Of):`""
    "Text=`"Member of (groups):`"" = "Text=`"Член групп:`""
    "Title=`"Name conflict`"" = "Title=`"Совпадение имени`""
    "Content=`"All saved domains`"" = "Content=`"Все сохранённые домены`""
    "ToolTip=`"Search users in every saved domain (results carry a Domain column)`"" = "ToolTip=`"Искать пользователей во всех сохранённых доменах (в результатах появится столбец «Домен»)`""
    "Title=`"Password never expires`"" = "Title=`"Срок действия пароля не ограничен`""
    "Content=`"Clear the flag automatically on:`"" = "Content=`"Снять флаг автоматически:`""
    "Content=`"Set`"" = "Content=`"Установить`""
    "Title=`"Switch domain`"" = "Title=`"Смена домена`""
    "Content=`"Another account:`"" = "Content=`"Другая учётная запись:`""
    "Title=`"Change history`"" = "Title=`"История изменений`""
    "Content=`"History...`"" = "Content=`"История...`""
    "Header=`"Object history...`"" = "Header=`"История объекта...`""
    "Content=`"Only this object`"" = "Content=`"Только этот объект`""
    "Header=`"Time`"" = "Header=`"Время`""
    "Header=`"Action`"" = "Header=`"Действие`""
    "Header=`"Object`"" = "Header=`"Объект`""
    "Header=`"Performed by`"" = "Header=`"Выполнил`""
    "Header=`"Details`"" = "Header=`"Подробности`""
    "Content=`"Groups`"" = "Content=`"Группы`""
    "Content=`"Create group...`"" = "Content=`"Создать группу...`""
    "Content=`"Members...`"" = "Content=`"Участники...`""
    "Header=`"Members...`"" = "Header=`"Участники...`""
    "Title=`"Create group`"" = "Title=`"Создание группы`""
    "Text=`"Group name:`"" = "Text=`"Имя группы:`""
    "Text=`"Login (sAMAccountName):`"" = "Text=`"Логин (sAMAccountName):`""
    "Text=`"Scope:`"" = "Text=`"Область:`""
    "Text=`"Category:`"" = "Text=`"Категория:`""
    "Text=`"Container (OU):`"" = "Text=`"Контейнер (OU):`""
    "Content=`"Browse...`"" = "Content=`"Обзор...`""
    "Title=`"Edit group`"" = "Title=`"Изменить группу`""
    "Text=`"Login:`"" = "Text=`"Логин:`""
    "Title=`"Select users`"" = "Title=`"Выбор пользователей`""
    "Title=`"Group members`"" = "Title=`"Участники группы`""
    "Text=`"Container on the left — its users on the right; the search spans the whole subtree.`"" = "Text=`"Слева контейнер — справа его пользователи; поиск идёт по всему поддереву.`""
    "Text=`"Container on the left — its users on the right; the search spans the whole subtree. Double-click adds a user to the list below; repeat the search or switch OUs to collect users from different places.`"" = "Text=`"Слева контейнер — справа его пользователи; поиск идёт по всему поддереву. Двойной клик добавляет пользователя в список ниже; повторяйте поиск или переключайте OU, чтобы собрать пользователей из разных мест.`""
    "Text=`"Selected to add (0):`"" = "Text=`"Выбрано для добавления (0):`""
    "Content=`"Add`"" = "Content=`"Добавить`""
}

function L {
    param([string]$s)
    if ($Script:Lang -eq 'ru' -and $Script:RuStrings.ContainsKey($s)) {
        return $Script:RuStrings[$s]
    }
    return $s
}

function Localize-Xaml {
    param([string]$Raw)
    if ($Script:Lang -ne 'ru') { return $Raw }
    foreach ($k in $Script:XamlRu.Keys) {
        $Raw = $Raw.Replace($k, $Script:XamlRu[$k])
    }
    return $Raw
}


# Global connection state
$Global:ADConnection = [pscustomobject]@{
    Credential = $null   # [PSCredential]
    Server     = $null   # DC / domain name
    UserName   = $null   # display name of the connected user
    BaseDN     = $null   # domain DistinguishedName (for the OU tree)
    DnsRoot    = $null   # domain DNS name
    NetBIOSName = $null  # domain NetBIOS (pre-Windows 2000) name
}

# Check for the ActiveDirectory module (with automatic RSAT install attempt)
function Test-IsAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Install-RSAT {
    # Tries to install RSAT: ActiveDirectory. Returns $true on success.
    # Windows 10/11 (client) — via Add-WindowsCapability
    try {
        $caps = Get-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools*' -ErrorAction Stop
        if ($caps) {
            foreach ($c in ($caps | Where-Object { $_.State -ne 'Installed' })) {
                Add-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null
            }
            if (Get-Module -ListAvailable -Name ActiveDirectory) { return $true }
        }
    } catch { }
    # Windows Server — via the feature/role
    try {
        Import-Module ServerManager -ErrorAction Stop
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
        if (Get-Module -ListAvailable -Name ActiveDirectory) { return $true }
    } catch { }
    return $false
}

function Test-ADModule {
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }

    # Module not found — offer to install
    $ans = [System.Windows.MessageBox]::Show(
        (L "The PowerShell module 'ActiveDirectory' (RSAT) is not installed.`n`n") +
        (L "Install it automatically now?`n") +
        (L "Administrator rights and a Windows Update connection are required. ") +
        (L "Installation may take a few minutes."),
        (L "Checking dependencies"),
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)

    if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
        [System.Windows.MessageBox]::Show(
            (L "The application cannot run without the ActiveDirectory module.`n`n") +
            (L "Install RSAT manually (as administrator):`n") +
            "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
            (L "ActiveDirectory module missing"),
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
        return $false
    }

    if (-not (Test-IsAdmin)) {
        [System.Windows.MessageBox]::Show(
            (L "Installing RSAT requires administrator rights.`n`n") +
            (L "Run the application as administrator or install it manually:`n") +
            "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
            (L "Insufficient rights"),
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return $false
    }

    if (Install-RSAT) {
        Import-Module ActiveDirectory -ErrorAction Stop
        Show-Info (L "ActiveDirectory module (RSAT) installed successfully.")
        return $true
    }

    [System.Windows.MessageBox]::Show(
        (L "Failed to install RSAT automatically.`n`n") +
        (L "Install manually (as administrator):`n") +
        "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`n`n" +
        (L "On Windows Server:`n") +
        "  Install-WindowsFeature RSAT-AD-PowerShell",
        (L "RSAT installation error"),
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
    return $false
}

# Unified wrapper for error messages
function Show-Error {
    param([string]$Message, [string]$Title = (L "Error"))
    [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
}

function Show-Info {
    param([string]$Message, [string]$Title = (L "Information"))
    [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information) | Out-Null
}

function Confirm-Action {
    param([string]$Message, [string]$Title = (L "Confirm"))
    $r = [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    return ($r -eq [System.Windows.MessageBoxResult]::Yes)
}

function Test-ADNotMemberError {
    # AD 0x561 / 1377 (ERROR_MEMBER_NOT_IN_ALIAS): the object is not a member
    # of the group any more — the list shown was already outdated (removed
    # elsewhere, or replication had not caught up).
    param($Ex)
    try { if ($Ex.ErrorCode -eq 1377) { return $true } } catch { }
    $m = "$($Ex.Message) $($Ex.ServerErrorMessage)"
    return ($m -match '00000561|not a member of the group|не является членом')
}

function Test-ADNameConflictError {
    # AD 0x2071 / 8305 (ERROR_DS_OBJ_STRING_NAME_EXISTS) / LDAP entryAlreadyExists:
    # an object with the same name (CN) already exists in the target container.
    param($Ex)
    try { if ($Ex.ErrorCode -eq 8305) { return $true } } catch { }
    $m = "$($Ex.Message) $($Ex.ServerErrorMessage)"
    return ($m -match '00002071|already in use|already exists|уже существует|уже используется')
}

function Show-RemoveMemberError {
    # Group-removal failure: a stale membership is a notice, the rest an error
    param([string]$GroupName, $Ex)
    if (Test-ADNotMemberError -Ex $Ex) {
        Show-Info ((L "'{0}': the object is no longer a member of this group — the list was outdated and has been refreshed.") -f $GroupName) (L "Notice")
    } else {
        Show-Error ((L "Failed to remove from group '{0}': {1}") -f $GroupName, ($Ex.Message))
    }
}

# Common parameters for all AD cmdlet calls (credential + server)
# Fast reachability probe: without it an unreachable DC makes the AD
# cmdlets wait for minutes with no way to cancel. ADWS port 9389.
function Test-DCReachable {
    param([string]$Server, [int]$TimeoutMs = 5000)
    if ([string]::IsNullOrWhiteSpace($Server)) { return $true }  # current domain
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $t = $c.BeginConnect($Server, 9389, $null, $null)
        if (-not $t.AsyncWaitHandle.WaitOne($TimeoutMs)) { $c.Close(); return $false }
        $c.EndConnect($t)
        $c.Close()
        return $true
    } catch { return $false }
}

function Get-ADParams {
    $p = @{ Credential = $Global:ADConnection.Credential }
    if ($Global:ADConnection.Server) { $p['Server'] = $Global:ADConnection.Server }
    return $p
}


# Common parameters for all AD cmdlet calls (credential + server)
# Fast reachability probe: without it an unreachable DC makes the AD
# cmdlets wait for minutes with no way to cancel. ADWS port 9389.
function Test-DCReachable {
    param([string]$Server, [int]$TimeoutMs = 5000)
    if ([string]::IsNullOrWhiteSpace($Server)) { return $true }  # current domain
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $t = $c.BeginConnect($Server, 9389, $null, $null)
        if (-not $t.AsyncWaitHandle.WaitOne($TimeoutMs)) { $c.Close(); return $false }
        $c.EndConnect($t)
        $c.Close()
        return $true
    } catch { return $false }
}

function Get-ADParams {
    $p = @{ Credential = $Global:ADConnection.Credential }
    if ($Global:ADConnection.Server) { $p['Server'] = $Global:ADConnection.Server }
    return $p
}

# --- Group selection: OU name and default groups ---
# OU to pick groups from. Empty = all groups in the domain.
$Global:AccessGroupsOUName = ""
# Groups added automatically when creating a user. Empty by default.
$Global:DefaultCreateGroups = @()
# AD attribute that stores the date when the 'password never expires' flag must
# be cleared automatically (set together with the flag). Must be a writable
# string attribute of the user object; adminDescription is free on standard
# schemas. Value format: yyyy-MM-dd.
$Global:PwdNeverExpiresUntilAttr = 'adminDescription'
$Global:AccessGroupsDN = $null
$Global:AccessGroupsResolved = $false

function Get-AccessGroupsDN {
    # OU DN from $Global:AccessGroupsOUName. $null if the name is not set
    # or the OU is not found. Cached until the next connection.
    if (-not $Global:AccessGroupsResolved) {
        $Global:AccessGroupsResolved = $true
        $Global:AccessGroupsDN = $null
        if (-not [string]::IsNullOrWhiteSpace($Global:AccessGroupsOUName)) {
            try {
                $p = Get-ADParams
                $ou = Get-ADOrganizationalUnit @p -Filter "Name -eq '$($Global:AccessGroupsOUName)'" `
                        -ErrorAction Stop | Select-Object -First 1
                if ($ou) { $Global:AccessGroupsDN = $ou.DistinguishedName }
            } catch { $Global:AccessGroupsDN = $null }
        }
    }
    return $Global:AccessGroupsDN
}

# --- Domain list storage (passwords are NOT saved) ---
function Get-ConfigDir {
    $dir = Join-Path $env:APPDATA 'ADUC-Ext'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-ConfigPath {
    return (Join-Path (Get-ConfigDir) 'domains.json')
}

# --- Change history (who did what, when) — local JSON-lines file ---
$Script:HistoryActions = @{
    'enable'                = 'Enable account'
    'disable'               = 'Disable account'
    'unlock'                = 'Unlock account'
    'reset_password'        = 'Reset password'
    'pwd_never_expires_on'  = 'Password never expires: on'
    'pwd_never_expires_off' = 'Password never expires: off'
    'pwd_never_expires_auto' = 'Password never expires: cleared automatically (date reached)'
    'edit'                  = 'Edit properties'
    'move'                  = 'Move'
    'rename'                = 'Rename'
    'create_user'           = 'Create user'
    'create_group'          = 'Create group'
    'delete'                = 'Delete'
    'group_add'             = 'Add to group'
    'group_remove'          = 'Remove from group'
}

function Get-HistoryPath {
    return (Join-Path (Get-ConfigDir) 'history.jsonl')
}

function Get-DnLeaf {
    # Value of the first RDN of a DN (the object's name)
    param([string]$Dn)
    if (-not $Dn) { return '' }
    $m = [regex]::Match($Dn, '^[^=]+=((?:\\.|[^,\\])*)')
    if ($m.Success) { return ($m.Groups[1].Value -replace '\\(.)', '$1') }
    return $Dn
}

function Add-HistoryEntry {
    # Record a successful change in the local history. Never throws.
    param([string]$Action, [string]$Dn, [string]$Details = '')
    try {
        $rec = [ordered]@{
            ts      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            actor   = [string]$Global:ADConnection.UserName
            domain  = [string]($(if ($Global:ADConnection.DnsRoot) { $Global:ADConnection.DnsRoot } else { $Global:ADConnection.Server }))
            action  = $Action
            object  = (Get-DnLeaf $Dn)
            dn      = [string]$Dn
            details = [string]$Details
        }
        $line = ($rec | ConvertTo-Json -Compress) + "`n"
        [System.IO.File]::AppendAllText((Get-HistoryPath), $line, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Get-HistoryRecords {
    # All records, oldest first; unreadable lines are skipped
    $path = Get-HistoryPath
    if (-not (Test-Path $path)) { return @() }
    $out = @()
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $out += ($line | ConvertFrom-Json) } catch { }
    }
    return $out
}

function Get-AppLang {
    try {
        $p = Join-Path (Get-ConfigDir) 'lang.txt'
        if (Test-Path $p) {
            $v = ([System.IO.File]::ReadAllText($p)).Trim()
            if ($v -in @('en', 'ru')) { return $v }
        }
    } catch { }
    return $null
}

function Set-AppLang {
    param([string]$LangValue)
    try {
        $p = Join-Path (Get-ConfigDir) 'lang.txt'
        [System.IO.File]::WriteAllText($p, $LangValue)
    } catch { }
}

function Get-SavedDomains {
    $path = Get-ConfigPath
    if (-not (Test-Path $path)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        if ($raw) { $raw = $raw.TrimStart([char]0xFEFF) }
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { return @() }
        return @($data)
    } catch { return @() }
}

function Save-Domains {
    param($Domains)
    $path = Get-ConfigPath
    try {
        $arr = @($Domains)
        if ($arr.Count -eq 0) {
            $json = '[]'
        } elseif ($arr.Count -eq 1) {
            $json = '[' + ($arr[0] | ConvertTo-Json -Depth 5 -Compress) + ']'
        } else {
            $json = $arr | ConvertTo-Json -Depth 5
        }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, [string]$json, $enc)
    } catch { }
}

function Add-SavedDomain {
    param([string]$Server, [string]$Username)
    $domains = @(Get-SavedDomains | Where-Object { $_.Server -ne $Server })
    $domains += [pscustomobject]@{
        Name = $Server; Server = $Server; Username = $Username
    }
    $domains = @($domains | Sort-Object Name)
    Save-Domains $domains
    return $domains
}

function Remove-SavedDomain {
    param([string]$Server)
    $domains = @(Get-SavedDomains | Where-Object { $_.Server -ne $Server })
    Save-Domains $domains
    return $domains
}

#endregion

#region -------------------- Credentials window ------------------------------

$LoginXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Connect to Active Directory"
        Height="400" Width="450"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="130"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Row="0" Grid.ColumnSpan="2" Text="Enter credentials to connect to the domain"
                   TextWrapping="Wrap" Margin="0,0,0,15" FontWeight="SemiBold"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Saved domain:" VerticalAlignment="Center"/>
        <DockPanel Grid.Row="1" Grid.Column="1" Margin="0,4">
            <Button DockPanel.Dock="Right" Name="BtnDelDomain" Content="✕" Width="28" Margin="4,0,0,0"
                    ToolTip="Remove the selected domain from the list"/>
            <ComboBox Name="CmbSaved" Padding="4"/>
        </DockPanel>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Domain / DC:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="TxtDomain" Margin="0,4" Padding="4"
                   ToolTip="For example: contoso.local or dc01.contoso.local (leave empty for the current domain)"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Text="User:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="TxtUser" Margin="0,4" Padding="4"
                   ToolTip="For example: CONTOSO\admin or admin@contoso.local"/>

        <TextBlock Grid.Row="4" Grid.Column="0" Text="Password:" VerticalAlignment="Center"/>
        <PasswordBox Grid.Row="4" Grid.Column="1" Name="TxtPass" Margin="0,4" Padding="4"/>

        <CheckBox Grid.Row="5" Grid.Column="1" Name="ChkSave" Content="Save domain to the list"
                  IsChecked="True" Margin="0,8,0,0"/>

        <TextBlock Grid.Row="6" Grid.ColumnSpan="2" Name="LblStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,8,0,0"/>

        <StackPanel Grid.Row="8" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,15,0,0">
            <ComboBox Name="CmbLoginLang" Width="55" Height="28" Margin="0,0,14,0" VerticalAlignment="Center"/>
            <Button Name="BtnConnect" Content="Connect" Width="120" Height="32" Margin="0,0,10,0"
                    IsDefault="True"/>
            <Button Name="BtnCancel"  Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-LoginWindow {
    param(
        [object]$Owner,
        [string]$Preselect
    )
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $LoginXaml))
    $win    = [Windows.Markup.XamlReader]::Load($reader)

    # Interface language switcher: saves the choice and reopens the dialog
    $script:LoginAgain = $false
    $cmbL = $win.FindName('CmbLoginLang')
    if ($cmbL) {
        [void]$cmbL.Items.Add('EN'); [void]$cmbL.Items.Add('RU')
        $cmbL.SelectedItem = if ($Script:Lang -eq 'ru') { 'RU' } else { 'EN' }
        $cmbL.Add_SelectionChanged({
            $new = if ($cmbL.SelectedItem -eq 'RU') { 'ru' } else { 'en' }
            if ($new -ne $Script:Lang) {
                $Script:Lang = $new
                Set-AppLang $new
                Set-UiCulture
                $script:LoginAgain = $true
                $win.Close()
            }
        })
    }
    if ($Owner) { $win.Owner = $Owner }

    $cmbSaved  = $win.FindName("CmbSaved")
    $btnDelDom = $win.FindName("BtnDelDomain")
    $txtDomain = $win.FindName("TxtDomain")
    $txtUser   = $win.FindName("TxtUser")
    $txtPass   = $win.FindName("TxtPass")
    $chkSave   = $win.FindName("ChkSave")
    $lblStatus = $win.FindName("LblStatus")
    $btnConn   = $win.FindName("BtnConnect")
    $btnCancel = $win.FindName("BtnCancel")

    # Load saved domains into the dropdown
    $script:LoginDomains = @(Get-SavedDomains)
    $fillCombo = {
        $cmbSaved.Items.Clear()
        foreach ($d in $script:LoginDomains) { $cmbSaved.Items.Add($d.Name) | Out-Null }
    }
    & $fillCombo

    # Fill fields from the selected profile
    $cmbSaved.Add_SelectionChanged({
        $name = $cmbSaved.SelectedItem
        if ($name) {
            $prof = $script:LoginDomains | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($prof) {
                $txtDomain.Text = [string]$prof.Server
                $txtUser.Text   = [string]$prof.Username
                $txtPass.Clear()
                $txtPass.Focus() | Out-Null
            }
        }
    })

    # Remove a domain from the list
    $btnDelDom.Add_Click({
        $name = $cmbSaved.SelectedItem
        if (-not $name) { return }
        $prof = $script:LoginDomains | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($prof -and (Confirm-Action ((L "Remove '{0}' from the domain list?") -f ($name)))) {
            $script:LoginDomains = @(Remove-SavedDomain -Server $prof.Server)
            & $fillCombo
            $txtDomain.Clear(); $txtUser.Clear()
        }
    })

    # Preselect / prefill
    if ($Preselect -and ($script:LoginDomains | Where-Object { $_.Name -eq $Preselect })) {
        $cmbSaved.SelectedItem = $Preselect
    }
    elseif (-not $txtDomain.Text -and $env:USERDNSDOMAIN) {
        $txtDomain.Text = $env:USERDNSDOMAIN
    }

    $script:LoginSuccess = $false

    $btnConn.Add_Click({
        $lblStatus.Text = (L "Checking connection...")
        $win.Dispatcher.Invoke([action]{}, "Render")

        $user = $txtUser.Text.Trim()
        $pass = $txtPass.Password

        if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
            $lblStatus.Text = (L "Enter a user name and password.")
            return
        }

        try {
            $secPass = ConvertTo-SecureString $pass -AsPlainText -Force
            $cred    = New-Object System.Management.Automation.PSCredential($user, $secPass)
            $server  = $txtDomain.Text.Trim()

            $testParams = @{ Credential = $cred; ErrorAction = 'Stop' }
            if ($server) { $testParams['Server'] = $server }

            # Fail fast when the directory server is unreachable
            if (-not (Test-DCReachable $server)) {
                $lblStatus.Text = ((L 'Domain controller "{0}" is unreachable. Check the server name and network connectivity.') -f ($server))
                return
            }

            # Test AD call to verify the credentials
            $domainInfo = Get-ADDomain @testParams

            $resolvedServer = if ($server) { $server } else { $domainInfo.DNSRoot }
            $Global:ADConnection.Credential = $cred
            $Global:ADConnection.Server     = $resolvedServer
            $Global:ADConnection.UserName   = $user
            $Global:ADConnection.BaseDN     = $domainInfo.DistinguishedName
            $Global:ADConnection.DnsRoot    = $domainInfo.DNSRoot
            $Global:ADConnection.NetBIOSName = $domainInfo.NetBIOSName
            # Reset the groups OU cache on a new connection
            $Global:AccessGroupsResolved    = $false
            $Global:AccessGroupsDN          = $null

            # Save the domain to the list
            if ($chkSave.IsChecked) {
                Add-SavedDomain -Server $resolvedServer -Username $user | Out-Null
            }

            $script:LoginSuccess = $true
            $win.Close()
        }
        catch {
            $lblStatus.Text = ((L "Failed to connect: {0}") -f ($_.Exception.Message))
        }
    })

    $btnCancel.Add_Click({ $script:LoginSuccess = $false; $win.Close() })

    $win.ShowDialog() | Out-Null
    if ($script:LoginAgain) { return 'again' }
    return $script:LoginSuccess
}

#endregion

#region ----------------------- Main window (XAML) ----------------------------

$MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ADUC-Ext — Active Directory user management"
        Height="660" Width="1320"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13">
    <DockPanel>
        <!-- Top search bar -->
        <Border DockPanel.Dock="Top" Background="#F3F3F3" Padding="10">
            <StackPanel>
                <!-- Three groups (search / actions / domain) in a WrapPanel: on a
                     narrow window the groups wrap onto the next line instead of
                     being cut off -->
                <WrapPanel Orientation="Horizontal">
                    <StackPanel Orientation="Horizontal" Margin="0,0,16,4">
                        <TextBlock Name="LblSearchCap" Text="Search:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBox Name="TxtSearch" Width="220" Padding="4" VerticalAlignment="Center"
                                 ToolTip="Name, login (sAMAccountName), e-mail, or part of a value"/>
                        <Button Name="BtnSearch" Content="Find" Width="70" Height="30" Margin="8,0,0,0"/>
                        <Button Name="BtnRefresh" Content="Refresh" Width="80" Height="30" Margin="8,0,0,0"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,0,16,4">
                        <Button Name="BtnCreate" Content="Create user" Width="160" Height="30"/>
                        <Button Name="BtnHistory" Content="History..." Width="120" Height="30" Margin="8,0,0,0"/>
                        <Button Name="BtnPwdGen" Content="Password..." Width="100" Height="30" Margin="8,0,0,0"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                        <TextBlock Name="LblDomainCap" Text="Domain:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <ComboBox Name="CmbDomain" Width="170" VerticalAlignment="Center" IsEditable="True"
                                  ToolTip="Select a saved domain or enter a controller/domain name"/>
                        <Button Name="BtnSwitchDomain" Content="Switch domain" Width="130" Height="30" Margin="8,0,0,0"/>
                        <ComboBox Name="CmbLang" Width="55" Height="30" Margin="10,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                </WrapPanel>
                <WrapPanel Orientation="Horizontal" Margin="0,4,0,0">
                    <TextBlock Name="LblShowCap" Text="Show:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <RadioButton Name="RbUsers" Content="Users" GroupName="ObjMode" IsChecked="True"
                                 VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <RadioButton Name="RbComputers" Content="Computers" GroupName="ObjMode"
                                 VerticalAlignment="Center"/>
                    <RadioButton Name="RbGroups" Content="Groups" GroupName="ObjMode"
                                 VerticalAlignment="Center" Margin="10,0,0,0"/>
                    <CheckBox Name="ChkSubtree" Content="Nested OUs" VerticalAlignment="Center"
                              Margin="24,0,0,0" ToolTip="Show objects from nested organizational units"/>
                    <CheckBox Name="ChkAllDomains" Content="All saved domains" VerticalAlignment="Center"
                              Margin="24,0,0,0" ToolTip="Search users in every saved domain (results carry a Domain column)"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- Bottom status bar -->
        <Border DockPanel.Dock="Bottom" Background="#F3F3F3" Padding="8,4">
            <TextBlock Name="LblConn" Text="" Foreground="#333"/>
        </Border>

        <!-- Main area: OU tree | user list | properties/actions -->
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.3*"/>
                <ColumnDefinition Width="5" />
                <ColumnDefinition Width="2.4*"/>
                <ColumnDefinition Width="5" />
                <ColumnDefinition Width="1.5*"/>
            </Grid.ColumnDefinitions>

            <!-- Organizational unit (OU) tree -->
            <DockPanel Grid.Column="0" Margin="10">
                <TextBlock Name="LblOuCap" DockPanel.Dock="Top" Text="Organizational units" FontWeight="SemiBold"
                           Margin="0,0,0,4"/>
                <TreeView Name="TreeOU"/>
            </DockPanel>

            <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Stretch"
                          Background="#DDD"/>

            <DataGrid Name="GridUsers" Grid.Column="2" Margin="0,10"
                      AutoGenerateColumns="False" IsReadOnly="True"
                      SelectionMode="Extended" HeadersVisibility="Column"
                      GridLinesVisibility="Horizontal" CanUserResizeRows="False">
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="1.6*"/>
                    <DataGridTextColumn Header="Login" Binding="{Binding SamAccountName}" Width="1.2*"/>
                    <DataGridTextColumn Header="E-mail" Binding="{Binding Mail}" Width="1.6*"/>
                    <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="1.6*"/>
                    <DataGridTextColumn Header="State" Binding="{Binding State}" Width="1*"/>
                </DataGrid.Columns>
                <DataGrid.ContextMenu>
                    <ContextMenu>
                        <MenuItem Name="CmCopyLogin"   Header="Copy login"/>
                        <MenuItem Name="CmCopyName"    Header="Copy display name"/>
                        <MenuItem Name="CmCopyMail"    Header="Copy e-mail"/>
                        <MenuItem Name="CmCopyUpn"     Header="Copy UPN"/>
                        <MenuItem Name="CmCopyDn"      Header="Copy DN"/>
                        <MenuItem Name="CmCopyAll"     Header="Copy all properties"/>
                        <Separator/>
                        <MenuItem Name="CmEnable"      Header="Enable"/>
                        <MenuItem Name="CmDisable"     Header="Disable"/>
                        <MenuItem Name="CmUnlock"      Header="Unlock"/>
                        <MenuItem Name="CmResetPwd"    Header="Reset password..."/>
                        <MenuItem Name="CmPwdNoExpire" Header="Password never expires" IsCheckable="True"/>
                        <Separator/>
                        <MenuItem Name="CmGroups"      Header="Groups..."/>
                        <MenuItem Name="CmMove"        Header="Move (OU)..."/>
                        <MenuItem Name="CmEdit"        Header="Edit..."/>
                        <MenuItem Name="CmMembers"     Header="Members..." Visibility="Collapsed"/>
                        <MenuItem Name="CmRename"      Header="Rename..." Visibility="Collapsed"/>
                        <MenuItem Name="CmDelete"      Header="Delete" Visibility="Collapsed"/>
                        <Separator/>
                        <MenuItem Name="CmHistory"     Header="Object history..."/>
                    </ContextMenu>
                </DataGrid.ContextMenu>
            </DataGrid>

            <GridSplitter Grid.Column="3" Width="5" HorizontalAlignment="Stretch"
                          Background="#DDD"/>

            <Grid Grid.Column="4" Margin="0,10,10,10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <GroupBox Grid.Row="0" Name="GrpProps" Header="User properties">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PanelProps" Margin="6">
                            <TextBlock Text="Select a user from the list" Foreground="#888"
                                       FontStyle="Italic"/>
                        </StackPanel>
                    </ScrollViewer>
                </GroupBox>

                <GroupBox Grid.Row="1" Name="GrpActions" Header="Actions" Margin="0,10,0,0">
                    <WrapPanel Name="PanelActions" Margin="6">
                        <Button Name="BtnEnable"   Content="Enable"          Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnDisable"  Content="Disable"         Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnUnlock"   Content="Unlock"          Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnResetPwd" Content="Reset password"  Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnPwdNoExpire" Content="Pwd never expires" Width="130" Height="32" Margin="4"
                                ToolTip="Set or clear the 'password never expires' flag"/>
                        <Button Name="BtnGroups"   Content="Groups..."       Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnMove"     Content="Move (OU)"        Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnEdit"     Content="Edit..."          Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnRename"   Content="Rename..."        Width="130" Height="32" Margin="4" Visibility="Collapsed"/>
                        <Button Name="BtnCreateGroup" Content="Create group..." Width="130" Height="32" Margin="4" Visibility="Collapsed"/>
                        <Button Name="BtnMembers"  Content="Members..."       Width="130" Height="32" Margin="4" Visibility="Collapsed"/>
                        <Button Name="BtnDelete"   Content="Delete"           Width="130" Height="32" Margin="4" Visibility="Collapsed"/>
                    </WrapPanel>
                </GroupBox>
            </Grid>
        </Grid>
    </DockPanel>
</Window>
"@

#endregion

#region --------------------- AD helper functions -----------------------------

# Properties requested for a user
$Script:UserProps = @(
    'DisplayName','SamAccountName','UserPrincipalName','GivenName','Surname',
    'Mail','Enabled','LockedOut','Description','Title','Department','Company',
    'Office','TelephoneNumber','DistinguishedName','whenCreated',
    'PasswordLastSet','LastLogonDate','AccountExpirationDate',
    'PasswordNeverExpires','PasswordExpired','msDS-UserPasswordExpiryTimeComputed',
    'badPwdCount','LastBadPasswordAttempt', $Global:PwdNeverExpiresUntilAttr,
    'proxyAddresses'
)

# --- Exchange addresses: every address of a recipient is kept in the
# multi-valued AD attribute proxyAddresses as 'TYPE:address'; an upper-case
# type marks the primary (reply) address of that type ---
$Script:ExchangePresent = @{}
function Test-ExchangePresent {
    # True when the forest of the given (or current) server has an Exchange
    # organization: the 'Microsoft Exchange' services container exists in the
    # configuration partition. Cached per server.
    param([string]$Server)
    $srv = if ($Server) { $Server } else { [string]$Global:ADConnection.Server }
    $k = $srv.ToLower()
    if ($Script:ExchangePresent.ContainsKey($k)) { return $Script:ExchangePresent[$k] }
    $present = $false
    try {
        $p = Get-ADParams
        if ($Server) { $p['Server'] = $Server }
        $root = Get-ADRootDSE @p
        $obj = Get-ADObject @p -Identity ("CN=Microsoft Exchange,CN=Services," + $root.configurationNamingContext) -ErrorAction Stop
        $present = [bool]$obj
    } catch { $present = $false }
    $Script:ExchangePresent[$k] = $present
    return $present
}

function Format-ProxyAddresses {
    # Aligned lines: primary SMTP first, then secondary smtp, other types, X500 last
    param($Values)
    $rows = @()
    foreach ($raw in @($Values)) {
        $txt = ("$raw").Trim()
        if (-not $txt) { continue }
        $i = $txt.IndexOf(':')
        if ($i -ge 0) { $typ = $txt.Substring(0, $i); $addr = $txt.Substring($i + 1) } else { $typ = ''; $addr = $txt }
        $rank = if ($typ -ceq 'SMTP') { 0 } elseif ($typ.ToLower() -eq 'smtp') { 1 } elseif ($typ.ToUpper() -eq 'X500') { 3 } else { 2 }
        $rows += [pscustomobject]@{ Typ = $typ; Addr = $addr; Rank = $rank }
    }
    if ($rows.Count -eq 0) { return '' }
    $rows = @($rows | Sort-Object Rank, { $_.Typ.ToLower() }, { $_.Addr.ToLower() })
    $w = ($rows | ForEach-Object { $_.Typ.Length } | Measure-Object -Maximum).Maximum
    $lines = foreach ($r in $rows) {
        $line = if ($r.Typ) { $r.Typ.PadRight($w) + '  ' + $r.Addr } else { $r.Addr }
        if ($r.Typ -ceq 'SMTP') { $line += '  (' + (L "primary") + ')' }
        $line
    }
    return ($lines -join "`r`n")
}

function Get-MailAddressesText {
    # Row text for the properties panel: the addresses, a 'no mailbox' note when
    # the forest has Exchange but the user has no addresses, or '' (row hidden)
    # when there is no Exchange organization at all.
    param($Ad, [string]$Server)
    $vals = @()
    try { $vals = @($Ad.proxyAddresses | ForEach-Object { [string]$_ }) } catch { $vals = @() }
    $txt = Format-ProxyAddresses $vals
    if ($txt) { return $txt }
    if (Test-ExchangePresent -Server $Server) { return (L "(no mailbox: the user has no Exchange addresses)") }
    return ''
}

function Get-UserState {
    param($u)
    if ($u.LockedOut)       { return (L "Locked") }
    if (-not $u.Enabled)    { return (L "Disabled") }
    return (L "Active")
}

function Search-ADUsers {
    param(
        [string]$Query,
        [string]$SearchBase,
        [string]$Scope = 'Subtree',   # Base | OneLevel | Subtree
        [string]$Server,              # another domain/controller (all-domains search)
        [string]$DomainLabel
    )
    $p = Get-ADParams
    if ($Server) { $p['Server'] = $Server }
    $isForeign = [bool]($Server -and ($Server.ToLower() -ne ("$($Global:ADConnection.Server)").ToLower()))
    $label = if ($DomainLabel) { $DomainLabel } elseif ($Server) { $Server } else { [string]$Global:ADConnection.DnsRoot }
    $p['Properties'] = $Script:UserProps
    # ResultSetSize left unset => the AD module returns ALL records (auto-paged)
    if ($SearchBase) { $p['SearchBase'] = $SearchBase }
    if ($Scope)      { $p['SearchScope'] = $Scope }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        $p['Filter'] = '*'
    }
    else {
        $q = $Query.Replace('*','').Trim()
        $wild = "*$q*"
        $p['Filter'] = {
            (Name -like $wild) -or (SamAccountName -like $wild) -or
            (Mail -like $wild) -or (DisplayName -like $wild) -or
            (GivenName -like $wild) -or (Surname -like $wild) -or
            (UserPrincipalName -like $wild)
        }.GetNewClosure()
    }

    Get-ADUser @p | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name              = if ($_.DisplayName) { $_.DisplayName } else { $_.Name }
            SamAccountName    = $_.SamAccountName
            Mail              = $_.Mail
            Description       = $_.Description
            State             = Get-UserState $_
            DistinguishedName = $_.DistinguishedName
            Domain            = $label
            _Host             = $(if ($Server) { $Server } else { [string]$Global:ADConnection.Server })
            _Foreign          = $isForeign
            _AD               = $_
        }
    }
}

function Test-AllDomainsOn {
    return [bool]($ChkAllDomains -and $ChkAllDomains.IsChecked -and (Get-CurrentMode) -eq 'users')
}

function Search-OtherDomains {
    # Same text search in every other saved domain with the session credentials.
    # Unreachable domains are collected in $Script:OtherDomainErrors.
    param([string]$Query)
    $Script:OtherDomainErrors = @()
    $out = @()
    $cur = ("$($Global:ADConnection.Server)").ToLower()
    $seenHosts = @{ $cur = $true }
    # Several saved profiles may point to the SAME domain (domain name,
    # controller names...): dedupe by the domain's base DN as well
    $seenBases = @{ ("$($Global:ADConnection.BaseDN)").ToLower() = $true }
    foreach ($d in @(Get-SavedDomains)) {
        $host = ("$($d.Server)").Trim()
        if (-not $host) { $host = ("$($d.Name)").Trim() }
        if (-not $host -or $seenHosts.ContainsKey($host.ToLower())) { continue }
        $seenHosts[$host.ToLower()] = $true
        try {
            if (-not (Test-DCReachable $host)) { throw "unreachable" }
            $info = Get-ADDomain -Server $host -Credential $Global:ADConnection.Credential -ErrorAction Stop
            $base = ("$($info.DistinguishedName)").ToLower()
            if ($base -and $seenBases.ContainsKey($base)) { continue }   # same domain, another name
            if ($base) { $seenBases[$base] = $true }
            $out += @(Search-ADUsers -Query $Query -Scope 'Subtree' -Server $host -DomainLabel ([string]$info.DNSRoot))
        } catch { $Script:OtherDomainErrors += $host }
    }
    # Final safety net: one row per object (by DN)
    $seenDn = @{}; $uniq = @()
    foreach ($u in $out) {
        $k = ("$($u.DistinguishedName)").ToLower()
        if ($seenDn.ContainsKey($k)) { continue }
        $seenDn[$k] = $true; $uniq += $u
    }
    return $uniq
}

# Properties requested for a computer
$Script:ComputerProps = @(
    'Name','DNSHostName','OperatingSystem','OperatingSystemVersion',
    'Description','Enabled','DistinguishedName','whenCreated',
    'LastLogonDate','SamAccountName'
)

function Get-ComputerState {
    param($c)
    if (-not $c.Enabled) { return (L "Disabled") }
    return (L "Active")
}

function Search-ADComputers {
    param(
        [string]$Query,
        [string]$SearchBase,
        [string]$Scope = 'Subtree'   # Base | OneLevel | Subtree
    )
    $p = Get-ADParams
    $p['Properties'] = $Script:ComputerProps
    if ($SearchBase) { $p['SearchBase'] = $SearchBase }
    if ($Scope)      { $p['SearchScope'] = $Scope }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        $p['Filter'] = '*'
    }
    else {
        $q = $Query.Replace('*','').Trim()
        $wild = "*$q*"
        $p['Filter'] = {
            (Name -like $wild) -or (DNSHostName -like $wild) -or
            (SamAccountName -like $wild) -or (OperatingSystem -like $wild) -or
            (Description -like $wild)
        }.GetNewClosure()
    }

    Get-ADComputer @p | Sort-Object Name | ForEach-Object {
        $osFull = if ($_.OperatingSystem -and $_.OperatingSystemVersion) {
            "$($_.OperatingSystem) ($($_.OperatingSystemVersion))"
        } elseif ($_.OperatingSystem) { $_.OperatingSystem } else { $_.OperatingSystemVersion }
        [pscustomobject]@{
            Name              = $_.Name
            DnsHostName       = $_.DNSHostName
            OS                = $osFull
            Description       = $_.Description
            State             = Get-ComputerState $_
            DistinguishedName = $_.DistinguishedName
            _AD               = $_
            _IsComputer       = $true
        }
    }
}

# --- Groups ---
$Script:GroupProps = @(
    'Name','SamAccountName','Description','GroupScope','GroupCategory',
    'DistinguishedName','whenCreated','mail'
)

function Get-GroupScopeLabel {
    param($g)
    switch ("$($g.GroupScope)") {
        'Global'      { return (L 'Global') }
        'DomainLocal' { return (L 'Domain local') }
        'Universal'   { return (L 'Universal') }
        default       { return "$($g.GroupScope)" }
    }
}

function Get-GroupCategoryLabel {
    param($g)
    if ("$($g.GroupCategory)" -eq 'Distribution') { return (L 'Distribution') }
    return (L 'Security')
}

function Search-ADGroupsList {
    param(
        [string]$Query,
        [string]$SearchBase,
        [string]$Scope = 'Subtree'   # Base | OneLevel | Subtree
    )
    $p = Get-ADParams
    $p['Properties'] = $Script:GroupProps
    if ($SearchBase) { $p['SearchBase'] = $SearchBase }
    if ($Scope)      { $p['SearchScope'] = $Scope }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        $p['Filter'] = '*'
    }
    else {
        $q = $Query.Replace('*','').Trim()
        $wild = "*$q*"
        $p['Filter'] = {
            (Name -like $wild) -or (SamAccountName -like $wild) -or
            (Description -like $wild)
        }.GetNewClosure()
    }

    Get-ADGroup @p | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name              = $_.Name
            SamAccountName    = $_.SamAccountName
            Scope             = Get-GroupScopeLabel $_
            Category          = Get-GroupCategoryLabel $_
            Description       = $_.Description
            DistinguishedName = $_.DistinguishedName
            _AD               = $_
            _IsGroup          = $true
        }
    }
}

function Get-GroupMemberList {
    # Group members as @{Name; Dn} read from the 'member' attribute
    # (works with explicit credentials, unlike Get-ADGroupMember in some setups)
    param([string]$Dn)
    $p = Get-ADParams
    $g = Get-ADGroup @p -Identity $Dn -Properties member
    @($g.member) | Where-Object { $_ } | ForEach-Object {
        $mdn = [string]$_
        $m = [regex]::Match($mdn, '^CN=((?:\\.|[^,\\])*)')
        $nm = if ($m.Success) { $m.Groups[1].Value -replace '\\(.)', '$1' } else { $mdn }
        [pscustomobject]@{ Name = $nm; Dn = $mdn }
    } | Sort-Object Name
}

#endregion

#region ------------------------ Action dialogs -------------------------------

# --- Create user ---
$CreateXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Create user" Height="760" Width="480"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="18">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="150"/><ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="100"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="First name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="0" Grid.Column="1" Name="CGiven" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="Last name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="1" Grid.Column="1" Name="CSur" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Display name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="CDisplay" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="Login (sAM):" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="CSam" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="UPN suffix:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="4" Grid.Column="1" Name="CUpn" Margin="0,4" Padding="3"
                   ToolTip="For example: @contoso.local"/>
        <TextBlock Grid.Row="5" Grid.Column="0" Text="E-mail:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="5" Grid.Column="1" Name="CMail" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="6" Grid.Column="0" Text="Description:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="6" Grid.Column="1" Name="CDesc" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="7" Grid.Column="0" Text="Password:" VerticalAlignment="Center"/>
        <DockPanel Grid.Row="7" Grid.Column="1" Margin="0,4">
            <Button DockPanel.Dock="Right" Name="CGen" Content="Generate..." Width="90" Margin="6,0,0,0"/>
            <PasswordBox Name="CPass" Padding="3"/>
        </DockPanel>
        <TextBlock Grid.Row="8" Grid.Column="0" Text="Organizational unit (OU):" VerticalAlignment="Center"/>
        <DockPanel Grid.Row="8" Grid.Column="1" Margin="0,4">
            <Button DockPanel.Dock="Right" Name="CBrowseOu" Content="Browse…" Width="70" Margin="6,0,0,0"/>
            <ComboBox Name="COu" Padding="3" IsEditable="True"
                      ToolTip="OU where the user will be created"/>
        </DockPanel>
        <TextBlock Grid.Row="9" Grid.Column="0" Text="Expires:" VerticalAlignment="Center"/>
        <StackPanel Grid.Row="9" Grid.Column="1" Orientation="Horizontal" Margin="0,4">
            <CheckBox Name="CExpEnable" Content="Valid through (incl.):" VerticalAlignment="Center"/>
            <DatePicker Name="CExpDate" Width="150" Margin="8,0,0,0" IsEnabled="False"
                        Language="en-US" SelectedDateFormat="Short"
                        ToolTip="Format: YYYY-MMM-DD"/>
        </StackPanel>

        <TextBlock Grid.Row="10" Grid.ColumnSpan="2" Text="Groups on creation:"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="11" Grid.ColumnSpan="2" Name="CGroups" SelectionMode="Extended"/>
        <StackPanel Grid.Row="12" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="CPick" Content="Select groups..." Width="150" Height="30"/>
            <Button Name="CUnpick" Content="Remove selected" Width="160" Height="30" Margin="8,0,0,0"/>
        </StackPanel>

        <CheckBox  Grid.Row="13" Grid.Column="1" Name="CChangePwd" Content="Change password at next logon"
                   Margin="0,10,0,0" IsChecked="True"/>
        <CheckBox  Grid.Row="14" Grid.Column="1" Name="CEnabled" Content="Account enabled"
                   Margin="0,6,0,0" IsChecked="True"/>

        <TextBlock Grid.Row="15" Grid.ColumnSpan="2" Name="CStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,8,0,0"/>
        <StackPanel Grid.Row="16" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="COk" Content="Create" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="CCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-CreateUserDialog {
    param($Owner, $DefaultOU)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $CreateXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner

    $g=$w.FindName("CGiven"); $s=$w.FindName("CSur"); $d=$w.FindName("CDisplay")
    $sam=$w.FindName("CSam"); $upn=$w.FindName("CUpn"); $mail=$w.FindName("CMail")
    $desc=$w.FindName("CDesc")
    $pass=$w.FindName("CPass"); $ou=$w.FindName("COu"); $chg=$w.FindName("CChangePwd")
    $en=$w.FindName("CEnabled"); $st=$w.FindName("CStatus")
    $expEnable=$w.FindName("CExpEnable"); $expDate=$w.FindName("CExpDate")
    $glist=$w.FindName("CGroups"); $pick=$w.FindName("CPick"); $unpick=$w.FindName("CUnpick")
    $browse=$w.FindName("CBrowseOu")
    $ok=$w.FindName("COk"); $cancel=$w.FindName("CCancel")
    $w.FindName("CGen").Add_Click({
        $g = Show-PasswordGeneratorDialog -Owner $w -WithUse
        if ($g) { $pass.Password = $g; $st.Foreground = '#2E7D32'; $st.Text = (L "Password inserted and copied to clipboard.") }
    })

    # Toggle for the expiration date field
    $expEnable.Add_Click({ $expDate.IsEnabled = [bool]$expEnable.IsChecked })
    # Show the selected date in DD-MM-YYYY format
    $expDate.Add_SelectedDateChanged({
        try {
            if ($expDate.SelectedDate) {
                $tb = $expDate.Template.FindName('PART_TextBox', $expDate)
                if ($tb) { $tb.Text = Format-AdDate ([DateTime]$expDate.SelectedDate) }
            }
        } catch { }
    })

    # Auto-fill the display name
    $updateDisplay = { if (-not $d.Text) { $d.Text = ("$($g.Text) $($s.Text)").Trim() } }
    $g.Add_LostFocus($updateDisplay); $s.Add_LostFocus($updateDisplay)

    # Prefill the UPN suffix
    if ($Global:ADConnection.DnsRoot) {
        $upn.Text = "@" + $Global:ADConnection.DnsRoot
    } elseif ($Global:ADConnection.Server -and $Global:ADConnection.Server -match '\.') {
        $upn.Text = "@" + ($Global:ADConnection.Server -replace '^[^.]+\.', '')
    }

    # OU list + default selection
    $choices = @(Get-OUChoices)
    foreach ($c in $choices) { $ou.Items.Add($c) | Out-Null }
    $defOu = $null
    if ($DefaultOU -and ($choices -contains $DefaultOU)) { $defOu = $DefaultOU }
    if (-not $defOu) { $defOu = $choices | Where-Object { $_ -match '^CN=Users,' } | Select-Object -First 1 }
    if (-not $defOu -and $Global:ADConnection.BaseDN) { $defOu = $Global:ADConnection.BaseDN }
    if ($defOu) { $ou.Text = $defOu }

    # Browse the domain tree to pick an OU
    $browse.Add_Click({
        $picked = Show-OUTreePicker -Owner $w -Initial $ou.Text
        if ($picked) { $ou.Text = $picked }
    })

    # Automatically add the default groups
    $missing = @()
    foreach ($gn in $Global:DefaultCreateGroups) {
        $gdn = $null
        try {
            $pg = Get-ADParams
            $base = Get-AccessGroupsDN
            if ($base) { $pg['SearchBase'] = $base }
            $grp = Get-ADGroup @pg -Filter "Name -eq '$gn' -or SamAccountName -eq '$gn'" -ErrorAction Stop |
                   Select-Object -First 1
            if (-not $grp -and $base) {
                $pg2 = Get-ADParams
                $grp = Get-ADGroup @pg2 -Filter "Name -eq '$gn' -or SamAccountName -eq '$gn'" -ErrorAction Stop |
                       Select-Object -First 1
            }
            if ($grp) { $gdn = $grp.DistinguishedName }
        } catch { }
        if ($gdn) {
            $li = New-Object System.Windows.Controls.ListBoxItem
            $li.Content = $gn; $li.Tag = $gdn
            $glist.Items.Add($li) | Out-Null
        } else { $missing += $gn }
    }
    if ($missing.Count -gt 0) {
        $st.Text = (L "Default groups not found: ") + ($missing -join ', ')
    }

    # Group selection on creation
    $pick.Add_Click({
        $exclude = @()
        foreach ($it in $glist.Items) { $exclude += [string]$it.Tag }
        $picked = Show-GroupPickerDialog -Owner $w -ExcludeDNs $exclude
        foreach ($gdn in $picked) {
            $exists = $false
            foreach ($it in $glist.Items) { if ([string]$it.Tag -eq $gdn) { $exists = $true; break } }
            if (-not $exists) {
                $cn = ($gdn -split ',',2)[0] -replace '^CN=',''
                $li = New-Object System.Windows.Controls.ListBoxItem
                $li.Content = $cn; $li.Tag = $gdn
                $glist.Items.Add($li) | Out-Null
            }
        }
    })
    $unpick.Add_Click({
        foreach ($it in @($glist.SelectedItems)) { $glist.Items.Remove($it) }
    })

    $script:CreateOk = $false
    $ok.Add_Click({
        $st.Text = ""
        $samVal = $sam.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($samVal)) { $st.Text = (L "Specify a login (sAMAccountName)."); return }
        if ([string]::IsNullOrWhiteSpace($pass.Password)) { $st.Text = (L "Specify a password."); return }

        # Validate the expiration date
        $expValue = $null
        if ($expEnable.IsChecked) {
            if ($null -eq $expDate.SelectedDate) { $st.Text = (L "Enter an expiration date or clear the checkbox."); return }
            # Valid THROUGH the given date inclusive => expires the next day
            $expValue = ([DateTime]$expDate.SelectedDate).Date.AddDays(1)
        }

        # Check that the login is not already taken in the domain
        try {
            $pc = Get-ADParams
            $dup = Get-ADUser @pc -Identity $samVal -ErrorAction Stop
            if ($dup) { $st.Text = ((L "A user with login `"{0}`" already exists in the domain.") -f ($samVal)); return }
        } catch {
            # Not found — that is fine, continue creating
        }

        try {
            $p = Get-ADParams
            $name = if ($d.Text) { $d.Text } else { $samVal }
            $p['Name']            = $name
            $p['SamAccountName']  = $samVal
            $p['AccountPassword'] = (ConvertTo-SecureString $pass.Password -AsPlainText -Force)
            $p['Enabled']         = [bool]$en.IsChecked
            $p['ChangePasswordAtLogon'] = [bool]$chg.IsChecked
            if ($g.Text)    { $p['GivenName']   = $g.Text.Trim() }
            if ($s.Text)    { $p['Surname']     = $s.Text.Trim() }
            if ($d.Text)    { $p['DisplayName'] = $d.Text.Trim() }
            if ($mail.Text) { $p['EmailAddress']= $mail.Text.Trim() }
            if ($desc.Text) { $p['Description'] = $desc.Text.Trim() }
            if ($expValue)  { $p['AccountExpirationDate'] = $expValue }
            if ($upn.Text)  {
                $suffix = $upn.Text.Trim()
                if ($suffix -notlike '@*') { $suffix = "@$suffix" }
                $p['UserPrincipalName'] = "$samVal$suffix"
            }
            $ouVal = $ou.Text.Trim()
            if ($ouVal) { $p['Path'] = $ouVal }

            $newUser = New-ADUser @p -PassThru
            Add-HistoryEntry -Action 'create_user' -Dn $newUser.DistinguishedName

            # Add to the selected groups
            $errs = @()
            foreach ($it in $glist.Items) {
                try {
                    $pg = Get-ADParams
                    Add-ADGroupMember @pg -Identity ([string]$it.Tag) -Members $newUser.DistinguishedName
                    Add-HistoryEntry -Action 'group_add' -Dn $newUser.DistinguishedName -Details (Get-DnLeaf ([string]$it.Tag))
                } catch { $errs += "$($it.Content): $($_.Exception.Message)" }
            }
            if ($errs.Count -gt 0) {
                Show-Error ((L "User created, but not added to all groups:`n") + ($errs -join "`n"))
            }

            $script:CreateOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:CreateOk
}

# --- Reset password ---
# --- Password generator ---
$Script:PwSpecial = '!@#$%^&*-_=+?'
$Script:PwSimilar = 'O0oIl1|S5Z2B8'   # easy to confuse in print / on screen
$Script:PwSettings = @{ Length = 12; Lower = $true; Upper = $true; Digits = $true; Special = $false; Similar = $false }

function New-GeneratedPassword {
    # Cryptographically random password: at least one character from every
    # enabled set, the rest drawn from their union, then shuffled.
    param([int]$Length = 12, [bool]$Lower = $true, [bool]$Upper = $true,
          [bool]$Digits = $true, [bool]$Special = $false, [bool]$ExcludeSimilar = $false)
    if ($Length -lt 8) { $Length = 8 }; if ($Length -gt 20) { $Length = 20 }
    $sets = @()
    foreach ($pair in @(@($Lower, 'abcdefghijklmnopqrstuvwxyz'), @($Upper, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
                        @($Digits, '0123456789'), @($Special, $Script:PwSpecial))) {
        if (-not $pair[0]) { continue }
        $chars = [string]$pair[1]
        if ($ExcludeSimilar) { $chars = -join ($chars.ToCharArray() | Where-Object { $Script:PwSimilar.IndexOf($_) -lt 0 }) }
        if ($chars) { $sets += $chars }
    }
    if ($sets.Count -eq 0) { throw (L "Select at least one character set.") }
    $pool = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] 4
    $rand = { param($n) $rng.GetBytes($buf); return [int]([BitConverter]::ToUInt32($buf, 0) % [uint32]$n) }
    $out = New-Object System.Collections.Generic.List[char]
    foreach ($cs in $sets) { $out.Add($cs[(& $rand $cs.Length)]) }
    while ($out.Count -lt $Length) { $out.Add($pool[(& $rand $pool.Length)]) }
    for ($i = $out.Count - 1; $i -gt 0; $i--) {
        $j = & $rand ($i + 1)
        $t = $out[$i]; $out[$i] = $out[$j]; $out[$j] = $t
    }
    $rng.Dispose()
    return (-join $out.ToArray())
}

$PwGenXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Password generator" Height="400" Width="460"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <DockPanel>
            <TextBlock Name="GLen" DockPanel.Dock="Left" Width="90" VerticalAlignment="Center"/>
            <Slider Name="GSlider" Minimum="8" Maximum="20" Value="12" IsSnapToTickEnabled="True"
                    TickFrequency="1" TickPlacement="BottomRight" VerticalAlignment="Center"/>
        </DockPanel>
        <CheckBox Name="GLower" Content="Lowercase letters (a-z)" Margin="0,8,0,0"/>
        <CheckBox Name="GUpper" Content="Uppercase letters (A-Z)" Margin="0,4,0,0"/>
        <CheckBox Name="GDigits" Content="Digits (0-9)" Margin="0,4,0,0"/>
        <CheckBox Name="GSpecial" Content="Special characters (!@#$%^&amp;*-_=+?)" Margin="0,4,0,0"/>
        <CheckBox Name="GSimilar" Content="Exclude look-alike characters (O/0, I/l/1, S/5, Z/2, B/8)" Margin="0,4,0,0"/>
        <TextBox Name="GPwd" FontFamily="Consolas" FontSize="16" Padding="4" Margin="0,12,0,4" IsReadOnly="True"/>
        <TextBlock Name="GStatus" Foreground="#2E7D32" TextWrapping="Wrap" MinHeight="20"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="GGen" Content="Generate" Width="100" Height="30" Margin="0,0,8,0"/>
            <Button Name="GCopy" Content="Copy" Width="100" Height="30" Margin="0,0,8,0"/>
            <Button Name="GUse" Content="Use" Width="110" Height="30" Margin="0,0,8,0" IsDefault="True"/>
            <Button Name="GClose" Content="Close" Width="90" Height="30" IsCancel="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

function Show-PasswordGeneratorDialog {
    # Returns the password when 'Use' was pressed (also copied to the clipboard),
    # otherwise $null. Without -WithUse the 'Use' button is hidden (standalone tool).
    param($Owner, [switch]$WithUse)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $PwGenXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $len=$w.FindName("GLen"); $sl=$w.FindName("GSlider"); $pwd=$w.FindName("GPwd"); $st=$w.FindName("GStatus")
    $cLower=$w.FindName("GLower"); $cUpper=$w.FindName("GUpper"); $cDigits=$w.FindName("GDigits")
    $cSpecial=$w.FindName("GSpecial"); $cSimilar=$w.FindName("GSimilar")
    $bGen=$w.FindName("GGen"); $bCopy=$w.FindName("GCopy"); $bUse=$w.FindName("GUse"); $bClose=$w.FindName("GClose")
    $cfg = $Script:PwSettings
    $sl.Value = $cfg.Length
    $cLower.IsChecked = $cfg.Lower; $cUpper.IsChecked = $cfg.Upper; $cDigits.IsChecked = $cfg.Digits
    $cSpecial.IsChecked = $cfg.Special; $cSimilar.IsChecked = $cfg.Similar
    if (-not $WithUse) { $bUse.Visibility = 'Collapsed'; $bGen.IsDefault = $true }
    $script:PwGenResult = $null
    $gen = {
        $Script:PwSettings.Length = [int][math]::Round($sl.Value)
        $Script:PwSettings.Lower = [bool]$cLower.IsChecked; $Script:PwSettings.Upper = [bool]$cUpper.IsChecked
        $Script:PwSettings.Digits = [bool]$cDigits.IsChecked; $Script:PwSettings.Special = [bool]$cSpecial.IsChecked
        $Script:PwSettings.Similar = [bool]$cSimilar.IsChecked
        $len.Text = ((L "Length: {0}") -f $Script:PwSettings.Length)
        $st.Text = ''; $st.Foreground = '#2E7D32'
        try {
            $pwd.Text = New-GeneratedPassword -Length $Script:PwSettings.Length -Lower $Script:PwSettings.Lower -Upper $Script:PwSettings.Upper `
                -Digits $Script:PwSettings.Digits -Special $Script:PwSettings.Special -ExcludeSimilar $Script:PwSettings.Similar
        } catch { $pwd.Text = ''; $st.Foreground = '#B00020'; $st.Text = $_.Exception.Message }
    }
    $sl.Add_ValueChanged({ & $gen })
    foreach ($cb in @($cLower, $cUpper, $cDigits, $cSpecial, $cSimilar)) { $cb.Add_Click({ & $gen }) }
    $bGen.Add_Click({ & $gen })
    $bCopy.Add_Click({
        if ($pwd.Text) { Set-ClipboardText $pwd.Text; $st.Foreground = '#2E7D32'; $st.Text = (L "Password generated and copied to clipboard.") }
    })
    $bUse.Add_Click({
        if (-not $pwd.Text) { return }
        Set-ClipboardText $pwd.Text
        $script:PwGenResult = $pwd.Text
        $w.Close()
    })
    $bClose.Add_Click({ $w.Close() })
    & $gen
    $w.ShowDialog() | Out-Null
    return $script:PwGenResult
}

$PwdXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Reset password" Height="270" Width="400"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="PLbl" Text="" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,12"/>
        <TextBlock Text="New password:"/>
        <DockPanel Margin="0,4,0,8">
            <Button DockPanel.Dock="Right" Name="PGen" Content="Generate..." Width="90" Margin="6,0,0,0"/>
            <PasswordBox Name="PNew" Padding="3"/>
        </DockPanel>
        <TextBlock Text="Confirm:"/>
        <PasswordBox Name="PConfirm" Margin="0,4,0,8" Padding="3"/>
        <CheckBox Name="PChange" Content="Change password at next logon" IsChecked="True"/>
        <CheckBox Name="PUnlock" Content="Unlock the account" IsChecked="True" Margin="0,6,0,0"/>
        <TextBlock Name="PStatus" Foreground="#B00020" TextWrapping="Wrap" Margin="0,8,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button Name="POk" Content="Apply" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="PCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

function Show-ResetPasswordDialog {
    param($Owner, $User)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $PwdXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("PLbl").Text = ((L "User: {0} ({1})") -f ($User.Name), ($User.SamAccountName))
    $new=$w.FindName("PNew"); $conf=$w.FindName("PConfirm")
    $chg=$w.FindName("PChange"); $unlock=$w.FindName("PUnlock")
    $st=$w.FindName("PStatus"); $ok=$w.FindName("POk"); $cancel=$w.FindName("PCancel")
    $w.FindName("PGen").Add_Click({
        $g = Show-PasswordGeneratorDialog -Owner $w -WithUse
        if ($g) { $new.Password = $g; $conf.Password = $g; $st.Foreground = '#2E7D32'; $st.Text = (L "Password inserted and copied to clipboard.") }
    })

    $script:PwdOk = $false
    $ok.Add_Click({
        $st.Text = ""; $st.Foreground = '#B00020'
        if ([string]::IsNullOrWhiteSpace($new.Password)) { $st.Text=(L "Enter a new password."); return }
        if ($new.Password -ne $conf.Password) { $st.Text=(L "Passwords do not match."); return }
        try {
            $p = Get-ADParams
            Set-ADAccountPassword @p -Identity $User.DistinguishedName -Reset `
                -NewPassword (ConvertTo-SecureString $new.Password -AsPlainText -Force)

            if ($unlock.IsChecked) {
                $pu = Get-ADParams
                Unlock-ADAccount @pu -Identity $User.DistinguishedName
            }
            if ($chg.IsChecked) {
                $pc = Get-ADParams
                Set-ADUser @pc -Identity $User.DistinguishedName -ChangePasswordAtLogon $true
            }
            Add-HistoryEntry -Action 'reset_password' -Dn $User.DistinguishedName
            $script:PwdOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:PwdOk
}

# --- Move to another OU ---
$MoveXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Move to organizational unit" Height="240" Width="560"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="MLbl" Text="" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <TextBlock Text="Current location:"/>
        <TextBox Name="MCurrent" IsReadOnly="True" Margin="0,4,0,10" Padding="3" Background="#F5F5F5"/>
        <TextBlock Text="Target container (OU):"/>
        <DockPanel Margin="0,4,0,4">
            <Button DockPanel.Dock="Right" Name="MBrowse" Content="Browse…" Width="80" Margin="6,0,0,0"/>
            <ComboBox Name="MTarget" IsEditable="True" Padding="3"/>
        </DockPanel>
        <TextBlock Name="MStatus" Foreground="#B00020" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="MOk" Content="Move" Width="120" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="MCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

# --- Change history: who changed what and when (local journal) ---
$HistoryXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Change history" Height="560" Width="960"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DockPanel Grid.Row="0" Margin="0,0,0,8">
            <TextBlock DockPanel.Dock="Left" Text="Filter:" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <CheckBox DockPanel.Dock="Right" Name="HsOnly" Content="Only this object" VerticalAlignment="Center" Margin="12,0,0,0"/>
            <TextBox Name="HsFilter" Padding="4"/>
        </DockPanel>
        <DataGrid Grid.Row="1" Name="HsGrid" AutoGenerateColumns="False" IsReadOnly="True"
                  SelectionMode="Extended" HeadersVisibility="Column"
                  GridLinesVisibility="Horizontal" CanUserResizeRows="False">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Time" Binding="{Binding Ts}" Width="150"/>
                <DataGridTextColumn Header="Action" Binding="{Binding Action}" Width="210"/>
                <DataGridTextColumn Header="Object" Binding="{Binding Object}" Width="1.2*"/>
                <DataGridTextColumn Header="Performed by" Binding="{Binding Actor}" Width="160"/>
                <DataGridTextColumn Header="Details" Binding="{Binding Details}" Width="1.5*"/>
            </DataGrid.Columns>
        </DataGrid>
        <TextBlock Grid.Row="2" Name="HsStatus" Foreground="#555555" TextWrapping="Wrap" Margin="0,8,0,0"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="HsRefresh" Content="Refresh" Width="110" Height="32" Margin="0,0,10,0"/>
            <Button Name="HsClose" Content="Close" Width="100" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-HistoryDialog {
    # $Obj (optional): the selected list row — enables the "only this object" filter
    param($Owner, $Obj)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $HistoryXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $filter=$w.FindName("HsFilter"); $only=$w.FindName("HsOnly"); $grid=$w.FindName("HsGrid")
    $st=$w.FindName("HsStatus"); $refresh=$w.FindName("HsRefresh"); $close=$w.FindName("HsClose")
    $objDn = ''; $objName = ''
    if ($Obj) {
        $objDn = ([string]$Obj.DistinguishedName).ToLower()
        $objName = ([string]$Obj.Name).ToLower()
        $only.Content = ((L "Only this object: {0}") -f ([string]$Obj.Name))
        $only.IsChecked = $true
    } else {
        $only.Visibility = 'Collapsed'
    }
    $script:HsRecords = @()
    $render = {
        $q = $filter.Text.Trim().ToLower()
        $rows = @()
        foreach ($r in $script:HsRecords) {
            if ($Obj -and $only.IsChecked) {
                $rdn = ([string]$r.dn).ToLower(); $rname = ([string]$r.object).ToLower()
                if (-not (($objDn -and $rdn -eq $objDn) -or ($objName -and $rname -eq $objName))) { continue }
            }
            $label = $Script:HistoryActions[[string]$r.action]
            if (-not $label) { $label = [string]$r.action }
            $ts = [string]$r.ts
            try { $ts = Format-AdDate ([DateTime]::ParseExact($ts, 'yyyy-MM-ddTHH:mm:ss', $null)) -WithTime } catch { }
            $row = [pscustomobject]@{
                Ts = $ts; Action = (L $label); Object = [string]$r.object
                Actor = [string]$r.actor; Details = [string]$r.details
            }
            if ($q) {
                $hay = ("$($row.Ts) $($row.Action) $($row.Object) $($row.Actor) $($row.Details) $($r.dn)").ToLower()
                if (-not $hay.Contains($q)) { continue }
            }
            $rows += $row
        }
        $grid.ItemsSource = $rows
        $st.Text = ((L "Records: {0} of {1}. File: {2}") -f ($rows.Count), ($script:HsRecords.Count), (Get-HistoryPath))
    }
    $load = {
        $all = @(Get-HistoryRecords)
        [array]::Reverse($all)   # newest first
        $script:HsRecords = $all
        & $render
    }
    & $load
    $filter.Add_TextChanged({ & $render })
    $only.Add_Click({ & $render })
    $refresh.Add_Click({ & $load })
    $close.Add_Click({ $w.Close() })
    $w.Add_Loaded({ $filter.Focus() })
    $w.ShowDialog() | Out-Null
}

function Get-LoginVariantsForDomain {
    # Same account name written for another domain: for 'CORP\ivanov',
    # 'ivanov@corp.local' or 'ivanov' and target host 'dc1.other.local'
    # returns 'ivanov@dc1.other.local','DC1\ivanov','ivanov@other.local','OTHER\ivanov'
    # (a host is either a DC or the domain itself, so both are tried).
    param([string]$Login, [string]$TargetHost)
    $out = @()
    $login = ("$Login").Trim()
    if (-not $login -or $login.ToLower().StartsWith('cn=')) { return $out }
    $name = if ($login.Contains('\')) { $login.Split('\', 2)[1] } else { $login.Split('@', 2)[0] }
    if (-not $name) { return $out }
    $parts = @(("$TargetHost").Trim().ToLower().Split('.') | Where-Object { $_ })
    if ($parts.Count -lt 2) { return $out }
    $doms = @(($parts -join '.'), (($parts | Select-Object -Skip 1) -join '.')) | Select-Object -Unique
    foreach ($dom in $doms) {
        if ($dom -and $dom.Contains('.')) {
            $out += "$name@$dom"
            $out += ($dom.Split('.')[0].ToUpper() + '\' + $name)
        }
    }
    return @($out | Where-Object { $_.ToLower() -ne $login.ToLower() } | Select-Object -Unique)
}

function Get-SwitchLogPath { return (Join-Path (Get-ConfigDir) 'switch.log') }
function Add-SwitchLog {
    # Domain-switch diagnostics (no passwords) for analysing a failed switch
    param([string[]]$Lines)
    try {
        $p = Get-SwitchLogPath
        $dir = Split-Path $p -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        foreach ($l in $Lines) { Add-Content -Path $p -Value "$stamp $l" -Encoding UTF8 }
    } catch { }
}

function Get-LoginVariantsForHome {
    # The session account qualified with its HOME domain: for a bare 'ivanov'
    # logged on to corp.local returns 'CORP\ivanov','ivanov@corp.local'. A DC of a
    # *trusting* domain resolves such names through the trust, whereas a bare
    # name is looked up in the target domain itself.
    param([string]$Login, [string]$DnsRoot, [string]$NetBIOSName)
    $out = @()
    $login = ("$Login").Trim()
    if (-not $login -or $login.ToLower().StartsWith('cn=')) { return $out }
    $name = if ($login.Contains('\')) { $login.Split('\', 2)[1] } else { $login.Split('@', 2)[0] }
    $dom = ("$DnsRoot").Trim().ToLower()
    if (-not $name -or -not $dom) { return $out }
    $nb = ("$NetBIOSName").Trim()
    if (-not $nb) { $nb = $dom.Split('.')[0] }
    $out += ($nb.ToUpper() + '\' + $name)
    $out += "$name@$dom"
    return @($out | Where-Object { $_.ToLower() -ne $login.ToLower() } | Select-Object -Unique)
}

# --- Domain switch: keep the active account or enter another one ---
$SwitchCredXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Switch domain" Height="300" Width="460" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="110"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Grid.ColumnSpan="2" Name="ScLbl" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <RadioButton Grid.Row="1" Grid.ColumnSpan="2" Name="ScCurrent" IsChecked="True" GroupName="sc"/>
        <RadioButton Grid.Row="2" Grid.ColumnSpan="2" Name="ScOther" Content="Another account:" GroupName="sc" Margin="0,6,0,2"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="User:" VerticalAlignment="Center" Margin="24,0,8,0"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="ScUser" Padding="4" Margin="0,3" IsEnabled="False"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="Password:" VerticalAlignment="Center" Margin="24,0,8,0"/>
        <PasswordBox Grid.Row="4" Grid.Column="1" Name="ScPass" Padding="4" Margin="0,3" IsEnabled="False"/>
        <TextBlock Grid.Row="5" Grid.ColumnSpan="2" Name="ScStatus" Foreground="#B00020" TextWrapping="Wrap" Margin="0,6,0,0"/>
        <StackPanel Grid.Row="6" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="ScOk" Content="Connect" Width="130" Height="30" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="ScCancel" Content="Cancel" Width="90" Height="30" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-SwitchCredentialsDialog {
    # Returns $null (cancelled), @{ Mode='current' } or @{ Mode='other'; Credential=[PSCredential] }
    param($Owner, [string]$Target, [string]$CurrentUser)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $SwitchCredXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $w.FindName("ScLbl").Text = ((L 'Connect to domain "{0}" as:') -f $Target)
    $rCur=$w.FindName("ScCurrent"); $rOther=$w.FindName("ScOther")
    $user=$w.FindName("ScUser"); $pass=$w.FindName("ScPass"); $st=$w.FindName("ScStatus")
    $ok=$w.FindName("ScOk"); $cancel=$w.FindName("ScCancel")
    $rCur.Content = ((L "Current account ({0})") -f $CurrentUser)
    $toggle = {
        $on = [bool]$rOther.IsChecked
        $user.IsEnabled = $on; $pass.IsEnabled = $on
        if ($on) { $user.Focus() } else { $ok.Focus() }
    }
    $rCur.Add_Checked({ & $toggle }); $rOther.Add_Checked({ & $toggle })
    # "Current account" is preselected: focus Connect so a single Enter switches
    $w.Add_Loaded({ if (-not $rOther.IsChecked) { $ok.Focus() } })
    $user.Add_KeyDown({ if ($_.Key -eq 'Return') { $pass.Focus(); $_.Handled = $true } })
    $script:SwitchCredResult = $null
    $ok.Add_Click({
        $st.Text = ""
        if (-not $rOther.IsChecked) { $script:SwitchCredResult = @{ Mode = 'current' }; $w.Close(); return }
        $u = $user.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($u) -or [string]::IsNullOrEmpty($pass.Password)) {
            $st.Text = (L "Enter the user name and password."); return
        }
        $cred = New-Object System.Management.Automation.PSCredential($u, (ConvertTo-SecureString $pass.Password -AsPlainText -Force))
        $script:SwitchCredResult = @{ Mode = 'other'; Credential = $cred }
        $w.Close()
    })
    $cancel.Add_Click({ $script:SwitchCredResult = $null; $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:SwitchCredResult
}

# --- 'Password never expires' with an auto-clear date ---
function Get-PwdNeverExpiresUntil {
    # Stored auto-clear date of a user (yyyy-MM-dd in the configured attribute), or $null
    param($Ad)
    try {
        $raw = [string]$Ad.($Global:PwdNeverExpiresUntilAttr)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return [DateTime]::ParseExact($raw.Substring(0, 10), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch { return $null }
}

function Clear-ExpiredNeverExpires {
    # Clear the flag on every user whose stored auto-clear date has passed.
    # Returns the sAMAccountNames processed.
    $done = @()
    try {
        $p = Get-ADParams
        $attr = $Global:PwdNeverExpiresUntilAttr
        $flt = "(&(objectClass=user)(objectCategory=person)($attr=*)(userAccountControl:1.2.840.113556.1.4.803:=65536))"
        $users = @(Get-ADUser @p -LDAPFilter $flt -Properties $attr, SamAccountName -ErrorAction Stop)
    } catch { return $done }
    $today = (Get-Date).Date
    foreach ($u in $users) {
        try {
            $until = Get-PwdNeverExpiresUntil $u
            if (-not $until -or $until.Date -gt $today) { continue }
            $p = Get-ADParams
            Set-ADUser @p -Identity $u.DistinguishedName -PasswordNeverExpires $false -Clear $attr -ErrorAction Stop
            Add-HistoryEntry -Action 'pwd_never_expires_auto' -Dn $u.DistinguishedName -Details $until.ToString('yyyy-MM-dd')
            $done += [string]$u.SamAccountName
        } catch { }
    }
    return $done
}

$Script:NeverExpiresTimer = $null
function Start-NeverExpiresSweep {
    # At start and then once an hour
    $run = {
        $names = @(Clear-ExpiredNeverExpires)
        if ($names.Count -gt 0) {
            $txt = ($names | Select-Object -First 10) -join ', '
            if ($names.Count -gt 10) { $txt += ', ...' }
            try { $LblConn.Text = $LblConn.Text + '   |   ' + ((L "'Password never expires' cleared (date reached): {0}") -f $txt) } catch { }
            try { Invoke-Search } catch { }
        }
    }
    & $run
    if (-not $Script:NeverExpiresTimer) {
        $Script:NeverExpiresTimer = New-Object System.Windows.Threading.DispatcherTimer
        $Script:NeverExpiresTimer.Interval = [TimeSpan]::FromHours(1)
        $Script:NeverExpiresTimer.Add_Tick($run)
        $Script:NeverExpiresTimer.Start()
    }
}

$NeverExpiresUntilXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Password never expires" Height="300" Width="520" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Name="NeLbl" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,0,0,8"/>
        <TextBlock Grid.Row="1" Name="NeNote" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal">
            <CheckBox Name="NeUntil" Content="Clear the flag automatically on:" VerticalAlignment="Center"/>
            <DatePicker Name="NeDate" Width="150" Margin="8,0,0,0" IsEnabled="False"/>
        </StackPanel>
        <TextBlock Grid.Row="3" Name="NeHint" Foreground="#555555" TextWrapping="Wrap" Margin="0,6,0,0"/>
        <TextBlock Grid.Row="4" Name="NeStatus" Foreground="#B00020" TextWrapping="Wrap" Margin="0,6,0,0"/>
        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="NeOk" Content="Set" Width="120" Height="30" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="NeCancel" Content="Cancel" Width="90" Height="30" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-NeverExpiresUntilDialog {
    # Returns $null (cancelled) or @{ Until = [DateTime] or $null }
    param($Owner, [string]$Login, [bool]$MustChange)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $NeverExpiresUntilXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $w.FindName("NeLbl").Text = ((L "Set the 'password never expires' flag for '{0}'?") -f $Login)
    $note = $w.FindName("NeNote")
    $note.Text = if ($MustChange) { (L "The pending 'change password at next logon' requirement will be removed; the current password stays valid (same as in ADUC).") } else { '' }
    if (-not $MustChange) { $note.Visibility = 'Collapsed' }
    $w.FindName("NeHint").Text = ((L "The date is stored in the account ({0}); the flag is cleared by the app when the date is reached.") -f $Global:PwdNeverExpiresUntilAttr)
    $chk=$w.FindName("NeUntil"); $dp=$w.FindName("NeDate"); $st=$w.FindName("NeStatus")
    $ok=$w.FindName("NeOk"); $cancel=$w.FindName("NeCancel")
    $chk.Add_Click({
        $dp.IsEnabled = [bool]$chk.IsChecked
        if ($chk.IsChecked -and -not $dp.SelectedDate) { $dp.SelectedDate = (Get-Date).Date.AddDays(90) }
    })
    $script:NeResult = $null
    $ok.Add_Click({
        $st.Text = ""
        $until = $null
        if ($chk.IsChecked) {
            if (-not $dp.SelectedDate) { $st.Text = (L "Select a date."); return }
            $until = ([DateTime]$dp.SelectedDate).Date
            if ($until -le (Get-Date).Date) { $st.Text = (L "The date must be later than today."); return }
        }
        $script:NeResult = @{ Until = $until }
        $w.Close()
    })
    $cancel.Add_Click({ $script:NeResult = $null; $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:NeResult
}

$NamePromptXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Name conflict" Height="230" Width="480" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Name="NpMsg" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <TextBox Grid.Row="1" Name="NpName" Padding="4"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="NpOk" Content="OK" Width="110" Height="30" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="NpCancel" Content="Cancel" Width="90" Height="30" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-NamePromptDialog {
    # Ask for a (new) name; returns $null when cancelled
    param($Owner, [string]$Message, [string]$Default)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $NamePromptXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $w.FindName("NpMsg").Text = $Message
    $name = $w.FindName("NpName"); $ok = $w.FindName("NpOk"); $cancel = $w.FindName("NpCancel")
    $name.Text = $Default
    $w.Add_Loaded({ $name.SelectAll(); $name.Focus() })
    $script:NamePromptValue = $null
    $ok.Add_Click({
        $v = $name.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($v)) { return }
        $script:NamePromptValue = $v
        $w.Close()
    })
    $cancel.Add_Click({ $script:NamePromptValue = $null; $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:NamePromptValue
}

function Move-ADObjectWithRename {
    # Move one object; when the target container already holds an object with
    # the same full name, ask for a new name (like ADUC), rename, then move.
    param($Owner, $Obj, [string]$Dest)
    $dn = $Obj.DistinguishedName
    $curName = [string]$Obj.Name
    while ($true) {
        try {
            $p = Get-ADParams
            Move-ADObject @p -Identity $dn -TargetPath $Dest
            Add-HistoryEntry -Action 'move' -Dn $dn -Details $Dest
            return
        } catch {
            if (-not (Test-ADNameConflictError -Ex $_.Exception)) { throw }
            $new = Show-NamePromptDialog -Owner $Owner -Default $curName -Message ((L 'An object named "{0}" already exists in the target container.`r`nEnter a new full name for the object being moved:') -f $curName)
            if (-not $new -or $new -eq $curName) {
                throw (New-Object System.Exception ((L "Not moved: an object with this name already exists in the target container.")))
            }
            $p = Get-ADParams
            $renamed = Rename-ADObject @p -Identity $dn -NewName $new -PassThru
            Add-HistoryEntry -Action 'rename' -Dn $dn -Details $new
            $dn = [string]$renamed.DistinguishedName
            $curName = $new
        }
    }
}

function Show-MoveDialog {
    param($Owner, $User, $Users)
    # $Users (array) — bulk move; $User — single object (back-compat)
    $items = if ($Users) { @($Users) } else { @($User) }
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $MoveXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    if ($items.Count -eq 1) {
        $w.FindName("MLbl").Text = ((L "Object: {0} ({1})") -f ($items[0].Name), ($items[0].SamAccountName))
    } else {
        $names = ($items | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ", "
        if ($items.Count -gt 3) { $names += ", ..." }
        $w.FindName("MLbl").Text = ((L "Objects selected: {0} ({1})") -f ($items.Count), ($names))
    }
    $current = $w.FindName("MCurrent")
    $target  = $w.FindName("MTarget")
    $browse  = $w.FindName("MBrowse")
    $st=$w.FindName("MStatus"); $ok=$w.FindName("MOk"); $cancel=$w.FindName("MCancel")

    # Current parent container
    $parents = @($items | ForEach-Object { ($_.DistinguishedName -replace '^CN=.*?(?<!\\),','') } | Sort-Object -Unique)
    $current.Text = if ($parents.Count -gt 1) { (L "(objects are in different containers)") } else { $parents[0] }

    # Populate the list of available OUs
    try {
        $p = Get-ADParams
        Get-ADOrganizationalUnit @p -Filter * |
            Sort-Object DistinguishedName |
            ForEach-Object { $target.Items.Add($_.DistinguishedName) | Out-Null }
    } catch { }

    # Browse the domain tree to pick an OU
    $browse.Add_Click({
        $picked = Show-OUTreePicker -Owner $w -Initial $target.Text
        if ($picked) { $target.Text = $picked }
    })

    $script:MoveOk = $false
    $script:MoveErrors = @()
    $ok.Add_Click({
        $st.Text = ""
        $dest = $target.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($dest)) { $st.Text=(L "Specify a target container."); return }
        if ($items.Count -eq 1) {
            try {
                Move-ADObjectWithRename -Owner $w -Obj $items[0] -Dest $dest
                $script:MoveOk = $true
                $w.Close()
            }
            catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
            return
        }
        $errors = @()
        foreach ($o in $items) {
            try {
                Move-ADObjectWithRename -Owner $w -Obj $o -Dest $dest
            } catch { $errors += "$($o.Name): $($_.Exception.Message)" }
        }
        $script:MoveOk = ($errors.Count -lt $items.Count)
        $script:MoveErrors = $errors
        if ($errors.Count -gt 0) {
            $okCnt = $items.Count - $errors.Count
            $txt = ($errors | Select-Object -First 10) -join "`r`n"
            if ($errors.Count -gt 10) { $txt += "`r`n..." }
            $st.Text = ((L "Moved: {0} of {1}.`r`n{2}") -f ($okCnt), ($items.Count), ($txt))
            return
        }
        $w.Close()
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:MoveOk
}

# --- Create a group ---
$GroupCreateXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Create group" Height="360" Width="500" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="150"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Grid.Column="0" Name="GcLblName" Text="Group name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="0" Grid.Column="1" Name="GcName" Margin="0,4" Padding="4"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Name="GcLblSam" Text="Login (sAMAccountName):" VerticalAlignment="Center" TextWrapping="Wrap"/>
        <TextBox   Grid.Row="1" Grid.Column="1" Name="GcSam" Margin="0,4" Padding="4"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Name="GcLblDesc" Text="Description:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="GcDesc" Margin="0,4" Padding="4"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Name="GcLblScope" Text="Scope:" VerticalAlignment="Center"/>
        <ComboBox  Grid.Row="3" Grid.Column="1" Name="GcScope" Margin="0,4"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Name="GcLblCat" Text="Category:" VerticalAlignment="Center"/>
        <ComboBox  Grid.Row="4" Grid.Column="1" Name="GcCat" Margin="0,4"/>
        <TextBlock Grid.Row="5" Grid.Column="0" Name="GcLblOu" Text="Container (OU):" VerticalAlignment="Center"/>
        <DockPanel Grid.Row="5" Grid.Column="1" Margin="0,4">
            <Button DockPanel.Dock="Right" Name="GcBrowse" Content="Browse..." Width="90" Margin="6,0,0,0"/>
            <TextBox Name="GcOu" Padding="4"/>
        </DockPanel>
        <TextBlock Grid.Row="6" Grid.ColumnSpan="2" Name="GcStatus" Foreground="Firebrick"
                   TextWrapping="Wrap" Margin="0,6,0,0"/>
        <StackPanel Grid.Row="7" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="GcOk" Content="Create" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="GcCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupCreateDialog {
    param($Owner, [string]$DefaultOU)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $GroupCreateXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $name=$w.FindName("GcName"); $sam=$w.FindName("GcSam"); $desc=$w.FindName("GcDesc")
    $scope=$w.FindName("GcScope"); $cat=$w.FindName("GcCat")
    $ou=$w.FindName("GcOu"); $browse=$w.FindName("GcBrowse")
    $st=$w.FindName("GcStatus"); $ok=$w.FindName("GcOk"); $cancel=$w.FindName("GcCancel")

    foreach ($v in @((L 'Global'), (L 'Domain local'), (L 'Universal'))) { [void]$scope.Items.Add($v) }
    $scope.SelectedIndex = 0
    foreach ($v in @((L 'Security'), (L 'Distribution'))) { [void]$cat.Items.Add($v) }
    $cat.SelectedIndex = 0
    if ($DefaultOU) { $ou.Text = $DefaultOU }

    $script:GcSamEdited = $false
    $sam.Add_PreviewKeyDown({ $script:GcSamEdited = $true })
    $name.Add_TextChanged({ if (-not $script:GcSamEdited) { $sam.Text = $name.Text } })
    $browse.Add_Click({
        $picked = Show-OUTreePicker -Owner $w -Initial $ou.Text
        if ($picked) { $ou.Text = $picked }
    })

    $script:GroupCreateOk = $false
    $ok.Add_Click({
        $st.Text = ""
        $n = $name.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($n)) { $st.Text = (L "Enter a group name."); return }
        try {
            $p = Get-ADParams
            $p['Name'] = $n
            $p['SamAccountName'] = if ($sam.Text.Trim()) { $sam.Text.Trim() } else { $n }
            $p['GroupScope'] = switch ($scope.SelectedIndex) {
                1 { 'DomainLocal' } 2 { 'Universal' } default { 'Global' } }
            $p['GroupCategory'] = if ($cat.SelectedIndex -eq 1) { 'Distribution' } else { 'Security' }
            if ($ou.Text.Trim()) { $p['Path'] = $ou.Text.Trim() }
            if ($desc.Text.Trim()) { $p['Description'] = $desc.Text.Trim() }
            $newGrp = New-ADGroup @p -PassThru
            Add-HistoryEntry -Action 'create_group' -Dn $newGrp.DistinguishedName
            $script:GroupCreateOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:GroupCreateOk
}

# --- Edit group attributes (description, e-mail) ---
$GroupEditXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit group" Height="500" Width="470" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="110"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="140"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Grid.Column="0" Name="GeLblName" Text="Name:" Margin="0,0,10,6"/>
        <TextBlock Grid.Row="0" Grid.Column="1" Name="GeName" Margin="0,0,0,6"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Name="GeLblSam" Text="Login:" Margin="0,0,10,6"/>
        <TextBlock Grid.Row="1" Grid.Column="1" Name="GeSam" Margin="0,0,0,6"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Name="GeLblDesc" Text="Description:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="GeDesc" Margin="0,4" Padding="4"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="E-mail:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="GeMail" Margin="0,4" Padding="4"/>
        <TextBlock Grid.Row="4" Grid.ColumnSpan="2" Text="Member of (groups):"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="5" Grid.ColumnSpan="2" Name="GeMemberOf" SelectionMode="Extended"/>
        <StackPanel Grid.Row="6" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="GeMoAdd" Content="Add..." Width="130" Height="30"/>
            <Button Name="GeMoRemove" Content="Remove selected" Width="170" Height="30" Margin="8,0,0,0"/>
        </StackPanel>
        <TextBlock Grid.Row="7" Grid.ColumnSpan="2" Name="GeStatus" Foreground="Firebrick"
                   TextWrapping="Wrap" Margin="0,6,0,0"/>
        <StackPanel Grid.Row="8" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="GeOk" Content="Save" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="GeCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupEditDialog {
    param($Owner, $Group)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $GroupEditXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $ad = $Group._AD
    $w.FindName("GeName").Text = [string]$ad.Name
    $w.FindName("GeSam").Text  = [string]$ad.SamAccountName
    $desc = $w.FindName("GeDesc"); $mail = $w.FindName("GeMail")
    $st=$w.FindName("GeStatus"); $ok=$w.FindName("GeOk"); $cancel=$w.FindName("GeCancel")
    $desc.Text = [string]$ad.Description
    $mail.Text = [string]$ad.mail

    # Member Of — groups this group belongs to (like the ADUC "Member Of"
    # tab for a group); changes are applied immediately
    $moList = $w.FindName("GeMemberOf")
    $moAdd = $w.FindName("GeMoAdd"); $moRemove = $w.FindName("GeMoRemove")
    $reloadMo = {
        $moList.Items.Clear()
        try {
            $p = Get-ADParams
            $adg = Get-ADGroup @p -Identity $Group.DistinguishedName -Properties memberOf
            @($adg.memberOf) | Where-Object { $_ } | ForEach-Object {
                $gdn = [string]$_
                $m = [regex]::Match($gdn, '^CN=((?:\\.|[^,\\])*)')
                $gname = if ($m.Success) { $m.Groups[1].Value -replace '\\(.)', '$1' } else { $gdn }
                [pscustomobject]@{ Name = $gname; Dn = $gdn }
            } | Sort-Object Name | ForEach-Object {
                    $it = New-Object System.Windows.Controls.ListBoxItem
                    $it.Content = $_.Name
                    $it.Tag = $_.Dn
                    $moList.Items.Add($it) | Out-Null
                }
        } catch { Show-Error ((L "Failed to retrieve groups: {0}") -f ($_.Exception.Message)) }
    }
    & $reloadMo

    $moAdd.Add_Click({
        $exclude = @($Group.DistinguishedName)
        foreach ($it in $moList.Items) { $exclude += [string]$it.Tag }
        $picked = Show-GroupPickerDialog -Owner $w -ExcludeDNs $exclude
        $added = 0
        foreach ($gdn in $picked) {
            try {
                $p = Get-ADParams
                Add-ADGroupMember @p -Identity $gdn -Members $Group.DistinguishedName
                Add-HistoryEntry -Action 'group_add' -Dn $Group.DistinguishedName -Details (Get-DnLeaf $gdn)
                $added++
            } catch { Show-Error ((L "Failed to add to group: {0}") -f ($_.Exception.Message)) }
        }
        if ($added) { & $reloadMo }
    })

    $moRemove.Add_Click({
        $sel = @($moList.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action ((L "Remove from the selected groups ({0})?") -f ($sel.Count)))) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $Group.DistinguishedName -Confirm:$false
                Add-HistoryEntry -Action 'group_remove' -Dn $Group.DistinguishedName -Details (Get-DnLeaf ([string]$it.Tag))
            } catch { Show-RemoveMemberError -GroupName ([string]$it.Content) -Ex $_.Exception }
        }
        & $reloadMo
    })

    $script:GroupEditOk = $false
    $ok.Add_Click({
        $st.Text = ""
        try {
            $p = Get-ADParams
            $d = $desc.Text.Trim()
            if ($d) { Set-ADGroup @p -Identity $Group.DistinguishedName -Description $d }
            else    { Set-ADGroup @p -Identity $Group.DistinguishedName -Clear description }
            $m = $mail.Text.Trim()
            if ($m) { Set-ADGroup @p -Identity $Group.DistinguishedName -Replace @{mail=$m} }
            else    { try { Set-ADGroup @p -Identity $Group.DistinguishedName -Clear mail } catch { } }
            Add-HistoryEntry -Action 'edit' -Dn $Group.DistinguishedName -Details 'description, mail'
            $script:GroupEditOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:GroupEditOk
}

# --- Pick users (search + multi-select) ---
$UserPickXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select users" Height="660" Width="760"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="110"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DockPanel Grid.Row="0" Margin="0,0,0,6">
            <Button DockPanel.Dock="Right" Name="UpFind" Content="Find" Width="80" Margin="6,0,0,0"/>
            <TextBox Name="UpSearch" Padding="4"/>
        </DockPanel>
        <TextBlock Grid.Row="1" Name="UpHint"
                   Text="Container on the left — its users on the right; the search spans the whole subtree. Double-click adds a user to the list below; repeat the search or switch OUs to collect users from different places."
                   Foreground="#666" TextWrapping="Wrap" Margin="0,0,0,6"/>
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.1*"/>
                <ColumnDefinition Width="5"/>
                <ColumnDefinition Width="2*"/>
            </Grid.ColumnDefinitions>
            <TreeView Grid.Column="0" Name="UpTree"/>
            <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Stretch" Background="#DDD"/>
            <ListBox Grid.Column="2" Name="UpList" SelectionMode="Extended"/>
        </Grid>
        <TextBlock Grid.Row="3" Name="UpPickedLbl" Text="Selected to add (0):"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="4" Name="UpPicked" SelectionMode="Extended"/>
        <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="UpUnpick" Content="Remove selected" Width="170" Height="30"/>
        </StackPanel>
        <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="UpOk" Content="Add" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="UpCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-UserPickerDialog {
    param($Owner, [string[]]$ExcludeDNs)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $UserPickXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $search=$w.FindName("UpSearch"); $find=$w.FindName("UpFind")
    $list=$w.FindName("UpList"); $ok=$w.FindName("UpOk"); $cancel=$w.FindName("UpCancel")
    $tree=$w.FindName("UpTree")
    $picked=$w.FindName("UpPicked"); $pickedLbl=$w.FindName("UpPickedLbl")
    $unpick=$w.FindName("UpUnpick")

    $exclude = @{}
    foreach ($d in $ExcludeDNs) { if ($d) { $exclude[$d.ToLower()] = $true } }

    # AD hierarchy (OUs + standard containers), same data as the main tree
    $script:UpTreeLoading = $true
    $baseDN = $Global:ADConnection.BaseDN
    $rootItem = New-Object System.Windows.Controls.TreeViewItem
    $rootItem.Header = if ($Global:ADConnection.DnsRoot) { $Global:ADConnection.DnsRoot } else { $baseDN }
    $rootItem.Tag = $baseDN
    $rootItem.IsExpanded = $true
    $tree.Items.Add($rootItem) | Out-Null
    $map = @{}; $map[$baseDN.ToLower()] = $rootItem
    try {
        $p1 = Get-ADParams
        $ous = @(Get-ADOrganizationalUnit @p1 -Filter * |
                 Select-Object -ExpandProperty DistinguishedName)
        $p2 = Get-ADParams
        $conts = @(Get-ADObject @p2 -SearchBase $baseDN -SearchScope OneLevel `
                     -LDAPFilter '(|(objectClass=container)(objectClass=builtinDomain))' |
                   Select-Object -ExpandProperty DistinguishedName)
    }
    catch { $ous = @(); $conts = @() }
    $all = @($ous + $conts) | Where-Object { $_ -and ($_.ToLower() -ne $baseDN.ToLower()) }
    $all = $all | Sort-Object @{ Expression = { ($_ -split ',').Count } }, @{ Expression = { $_ } }
    foreach ($dn in $all) {
        $parentDN = ($dn -split ',', 2)[1]
        $parentItem = $map[$parentDN.ToLower()]
        if (-not $parentItem) { $parentItem = $rootItem }
        $rdn = ($dn -split ',', 2)[0]
        $label = ($rdn -split '=', 2)[1]
        $item = New-Object System.Windows.Controls.TreeViewItem
        $item.Header = $label
        $item.Tag = $dn
        $parentItem.Items.Add($item) | Out-Null
        $map[$dn.ToLower()] = $item
    }
    $rootItem.IsSelected = $true
    $script:UpTreeLoading = $false

    $load = {
        $list.Items.Clear()
        try {
            $base = $null
            $sel = $tree.SelectedItem
            if ($sel -and $sel.Tag) { $base = [string]$sel.Tag }
            $text = $search.Text
            # Browsing shows the container's users; a search spans the subtree
            $scope = if ([string]::IsNullOrWhiteSpace($text)) { 'OneLevel' } else { 'Subtree' }
            foreach ($u in @(Search-ADUsers -Query $text -SearchBase $base -Scope $scope)) {
                if ($exclude.ContainsKey($u.DistinguishedName.ToLower())) { continue }
                # Disabled accounts are not offered for membership
                if ($u._AD.Enabled -eq $false) { continue }
                $it = New-Object System.Windows.Controls.ListBoxItem
                $it.Content = "$($u.Name) ($($u.SamAccountName))"
                $it.Tag = $u.DistinguishedName
                $list.Items.Add($it) | Out-Null
            }
        } catch { Show-Error ((L "Search error: {0}") -f ($_.Exception.Message)) }
    }
    & $load
    $find.Add_Click({ & $load })
    $search.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { & $load } })
    $tree.Add_SelectedItemChanged({
        if ($script:UpTreeLoading) { return }
        $search.Text = ""
        & $load
    })

    # The basket: users collected for adding (double-click; any OU/search)
    $updatePickedLbl = {
        $pickedLbl.Text = ((L 'Selected to add ({0}):') -f ($picked.Items.Count))
    }
    $pickOne = {
        param($srcItem)
        if (-not $srcItem) { return }
        $dn = [string]$srcItem.Tag
        foreach ($it in $picked.Items) {
            if ([string]$it.Tag -ieq $dn) { return }
        }
        $it = New-Object System.Windows.Controls.ListBoxItem
        $it.Content = [string]$srcItem.Content
        $it.Tag = $dn
        $picked.Items.Add($it) | Out-Null
        & $updatePickedLbl
    }
    $list.Add_MouseDoubleClick({ & $pickOne $list.SelectedItem })
    $picked.Add_MouseDoubleClick({
        $it = $picked.SelectedItem
        if ($it) { $picked.Items.Remove($it); & $updatePickedLbl }
    })
    $unpick.Add_Click({
        $sel = @($picked.SelectedItems)
        foreach ($it in $sel) { $picked.Items.Remove($it) }
        & $updatePickedLbl
    })

    $script:PickedUsers = @()
    $ok.Add_Click({
        # The basket plus whatever is highlighted in the results (the old
        # flow — highlight and press Add — still works)
        $res = @()
        $have = @{}
        foreach ($it in $picked.Items) {
            $dn = [string]$it.Tag
            if (-not $have.ContainsKey($dn.ToLower())) {
                $res += $dn; $have[$dn.ToLower()] = $true
            }
        }
        foreach ($it in @($list.SelectedItems)) {
            $dn = [string]$it.Tag
            if (-not $have.ContainsKey($dn.ToLower())) {
                $res += $dn; $have[$dn.ToLower()] = $true
            }
        }
        $script:PickedUsers = $res
        $w.Close()
    })
    $cancel.Add_Click({ $script:PickedUsers = @(); $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:PickedUsers
}

# --- Group members (view, add, remove — multi-select) ---
$MembersXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Group members" Height="500" Width="560"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Name="MbLbl" Text="" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <ListBox Grid.Row="1" Name="MbList" SelectionMode="Extended"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
            <Button Name="MbAdd" Content="Add..." Width="150" Height="30"/>
            <Button Name="MbRemove" Content="Remove selected" Width="200" Height="30" Margin="10,0,0,0"/>
        </StackPanel>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="MbClose" Content="Close" Width="100" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupMembersDialog {
    param($Owner, $Group)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $MembersXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $lbl=$w.FindName("MbLbl"); $list=$w.FindName("MbList")
    $add=$w.FindName("MbAdd"); $remove=$w.FindName("MbRemove"); $close=$w.FindName("MbClose")

    $reload = {
        $list.Items.Clear()
        try {
            $script:MbMembers = @(Get-GroupMemberList -Dn $Group.DistinguishedName)
        } catch {
            $script:MbMembers = @()
            Show-Error ((L "Failed to retrieve groups: {0}") -f ($_.Exception.Message))
        }
        foreach ($m in $script:MbMembers) {
            $it = New-Object System.Windows.Controls.ListBoxItem
            $it.Content = $m.Name
            $it.Tag = $m.Dn
            $list.Items.Add($it) | Out-Null
        }
        $lbl.Text = ((L "Group: {0}") -f ($Group.Name)) + "   (" + $script:MbMembers.Count + ")"
    }
    & $reload

    $add.Add_Click({
        $exclude = @($script:MbMembers | ForEach-Object { $_.Dn })
        $picked = @(Show-UserPickerDialog -Owner $w -ExcludeDNs $exclude)
        if (-not $picked -or $picked.Count -eq 0) { return }
        $added = 0; $errors = @()
        foreach ($udn in $picked) {
            try {
                $p = Get-ADParams
                Add-ADGroupMember @p -Identity $Group.DistinguishedName -Members $udn
                Add-HistoryEntry -Action 'group_add' -Dn $udn -Details (Get-DnLeaf $Group.DistinguishedName)
                $added++
            } catch { $errors += "${udn}: $($_.Exception.Message)" }
        }
        if ($errors.Count -gt 0) {
            $txt = ($errors | Select-Object -First 10) -join "`r`n"
            Show-Error (((L "Added: {0}.") -f ($added)) + "`r`n`r`n" + $txt) (L "Partially completed")
        }
        & $reload
    })

    $remove.Add_Click({
        $sel = @($list.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action ((L "Remove selected members ({0}) from the group?") -f ($sel.Count)))) { return }
        $removed = 0; $errors = @()
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity $Group.DistinguishedName -Members ([string]$it.Tag) -Confirm:$false
                Add-HistoryEntry -Action 'group_remove' -Dn ([string]$it.Tag) -Details (Get-DnLeaf $Group.DistinguishedName)
                $removed++
            } catch {
                if (Test-ADNotMemberError -Ex $_.Exception) {
                    $errors += ((L "'{0}': the object is no longer a member of this group — the list was outdated and has been refreshed.") -f ($it.Content))
                } else { $errors += "$($it.Content): $($_.Exception.Message)" }
            }
        }
        if ($errors.Count -gt 0) {
            $txt = ($errors | Select-Object -First 10) -join "`r`n"
            Show-Error (((L "Removed: {0}.") -f ($removed)) + "`r`n`r`n" + $txt) (L "Partially completed")
        }
        & $reload
    })

    $close.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
}

# --- Rename an object (change its name/CN) ---
$RenameXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rename object" Height="180" Width="420" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Name="RnLbl" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <TextBlock Grid.Row="1" Text="New name:" Margin="0,0,0,4"/>
        <TextBox Grid.Row="2" Name="RnName" Padding="4"/>
        <TextBlock Grid.Row="2" Name="RnStatus" Foreground="#B00020" Margin="0,40,0,0" TextWrapping="Wrap"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="RnOk" Content="Rename" Width="130" Height="30" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="RnCancel" Content="Cancel" Width="90" Height="30" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-RenameDialog {
    param($Owner, $Obj)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $RenameXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $curName = [string]$Obj.Name
    $w.FindName("RnLbl").Text = ((L "Object: {0}") -f ($curName))
    $name = $w.FindName("RnName")
    $st   = $w.FindName("RnStatus")
    $ok   = $w.FindName("RnOk"); $cancel = $w.FindName("RnCancel")
    $name.Text = $curName
    $w.Add_Loaded({ $name.SelectAll(); $name.Focus() })

    $script:RenameOk = $false
    $ok.Add_Click({
        $st.Text = ""
        $new = $name.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($new)) { $st.Text = (L "Enter a name."); return }
        if ($new -eq $curName) { $w.Close(); return }
        try {
            $p = Get-ADParams
            Rename-ADObject @p -Identity $Obj.DistinguishedName -NewName $new
            Add-HistoryEntry -Action 'rename' -Dn $Obj.DistinguishedName -Details $new
            $script:RenameOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:RenameOk
}

# --- Edit computer attributes (description) ---
$CompEditXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit computer" Height="240" Width="460" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Grid.Column="0" Text="Name:" Margin="0,0,10,6"/>
        <TextBlock Grid.Row="0" Grid.Column="1" Name="CeName" Margin="0,0,0,6"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="DNS name:" Margin="0,0,10,6"/>
        <TextBlock Grid.Row="1" Grid.Column="1" Name="CeDns" Margin="0,0,0,6"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Description:" Margin="0,4,10,0"/>
        <TextBox Grid.Row="2" Grid.Column="1" Name="CeDesc" Height="26"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" Name="CeStatus"
                   Foreground="Firebrick" TextWrapping="Wrap" Margin="0,8,0,0"/>
        <StackPanel Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button Name="CeOk" Content="Save" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="CeCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-ComputerEditDialog {
    param($Owner, $Comp)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $CompEditXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $ad = $Comp._AD
    $w.FindName("CeName").Text = [string]$ad.Name
    $w.FindName("CeDns").Text  = if ($ad.DNSHostName) { [string]$ad.DNSHostName } else { "-" }
    $desc = $w.FindName("CeDesc"); $st = $w.FindName("CeStatus")
    $ok = $w.FindName("CeOk"); $cancel = $w.FindName("CeCancel")
    $desc.Text = [string]$ad.Description

    $script:CompEditOk = $false
    $ok.Add_Click({
        $st.Text = ""
        try {
            $p = Get-ADParams
            $val = $desc.Text.Trim()
            if ($val) {
                Set-ADComputer @p -Identity $Comp.DistinguishedName -Description $val
            } else {
                Set-ADComputer @p -Identity $Comp.DistinguishedName -Clear description
            }
            Add-HistoryEntry -Action 'edit' -Dn $Comp.DistinguishedName -Details 'description'
            $script:CompEditOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:CompEditOk
}

# --- Select an organizational unit (OU) by tree navigation ---
$OUPickXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select organizational unit (OU)" Height="480" Width="430"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TreeView Grid.Row="0" Name="OUTree"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="OUOk" Content="Select" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="OUCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-OUTreePicker {
    param($Owner, [string]$Initial)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $OUPickXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $tree=$w.FindName("OUTree"); $ok=$w.FindName("OUOk"); $cancel=$w.FindName("OUCancel")

    $baseDN = $Global:ADConnection.BaseDN
    $rootLabel = if ($Global:ADConnection.DnsRoot) { $Global:ADConnection.DnsRoot } else { $baseDN }
    $rootItem = New-Object System.Windows.Controls.TreeViewItem
    $rootItem.Header = $rootLabel; $rootItem.Tag = $baseDN; $rootItem.IsExpanded = $true
    $tree.Items.Add($rootItem) | Out-Null
    $map = @{}; $map[$baseDN.ToLower()] = $rootItem

    try {
        $p1 = Get-ADParams
        $ous = @(Get-ADOrganizationalUnit @p1 -Filter * | Select-Object -ExpandProperty DistinguishedName)
        $p2 = Get-ADParams
        $conts = @(Get-ADObject @p2 -SearchBase $baseDN -SearchScope OneLevel `
                     -LDAPFilter '(|(objectClass=container)(objectClass=builtinDomain))' |
                   Select-Object -ExpandProperty DistinguishedName)
    } catch { $ous=@(); $conts=@() }

    $all = @($ous + $conts) | Where-Object { $_ -and ($_.ToLower() -ne $baseDN.ToLower()) }
    $all = $all | Sort-Object @{ Expression = { ($_ -split ',').Count } }, @{ Expression = { $_ } }

    foreach ($dn in $all) {
        $parentDN = ($dn -split ',', 2)[1]
        $parentItem = $map[$parentDN.ToLower()]
        if (-not $parentItem) { $parentItem = $rootItem }
        $rdn = ($dn -split ',', 2)[0]
        $label = ($rdn -split '=', 2)[1]
        $item = New-Object System.Windows.Controls.TreeViewItem
        $item.Header = $label; $item.Tag = $dn
        if ($Initial -and ($dn.ToLower() -eq $Initial.ToLower())) {
            $item.IsSelected = $true; $parentItem.IsExpanded = $true
        }
        $parentItem.Items.Add($item) | Out-Null
        $map[$dn.ToLower()] = $item
    }

    $script:OUPicked = $null
    $ok.Add_Click({
        $sel = $tree.SelectedItem
        if ($sel -and $sel.Tag) { $script:OUPicked = [string]$sel.Tag }
        $w.Close()
    })
    $cancel.Add_Click({ $script:OUPicked = $null; $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:OUPicked
}

# --- OU list for selection during creation ---
function Get-OUChoices {
    $result = @()
    $base = $Global:ADConnection.BaseDN
    if ($base) { $result += $base }
    try {
        $p1 = Get-ADParams
        $result += @(Get-ADOrganizationalUnit @p1 -Filter * |
                     Select-Object -ExpandProperty DistinguishedName | Sort-Object)
        $p2 = Get-ADParams
        $result += @(Get-ADObject @p2 -SearchBase $base -SearchScope OneLevel `
                       -LDAPFilter '(objectClass=container)' |
                     Select-Object -ExpandProperty DistinguishedName)
    } catch { }
    return $result
}

# --- Group selection from the directory ---
$GroupPickXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select groups" Height="480" Width="520"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal">
            <TextBlock Text="Filter:" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <TextBox Name="GPSearch" Width="320" Padding="3"/>
            <Button Name="GPFind" Content="Find" Width="80" Height="28" Margin="8,0,0,0"/>
        </StackPanel>
        <TextBlock Grid.Row="1" Text="Groups (Ctrl/Shift — multi-select):"
                   Margin="0,10,0,4"/>
        <ListBox Grid.Row="2" Name="GPList" SelectionMode="Extended"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right"
                    Margin="0,12,0,0">
            <Button Name="GPOk" Content="Select" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="GPCancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupPickerDialog {
    param($Owner, [string[]]$ExcludeDNs)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $GroupPickXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $w.Owner = $Owner }
    $search=$w.FindName("GPSearch"); $find=$w.FindName("GPFind")
    $list=$w.FindName("GPList"); $ok=$w.FindName("GPOk"); $cancel=$w.FindName("GPCancel")

    $exclude = @{}
    foreach ($d in $ExcludeDNs) { if ($d) { $exclude[$d.ToLower()] = $true } }

    $script:PickedGroups = @()

    $load = {
        $list.Items.Clear()
        try {
            $p = Get-ADParams
            $base = Get-AccessGroupsDN
            if ($base) { $p['SearchBase'] = $base }
            $q = $search.Text.Trim()
            if ($q) {
                $groups = Get-ADGroup @p -Filter "Name -like '*$q*' -or SamAccountName -like '*$q*'"
            } else {
                $groups = Get-ADGroup @p -Filter *
            }
            foreach ($grp in ($groups | Sort-Object Name)) {
                if ($exclude.ContainsKey($grp.DistinguishedName.ToLower())) { continue }
                $it = New-Object System.Windows.Controls.ListBoxItem
                $it.Content = $grp.Name
                $it.Tag = $grp.DistinguishedName
                $list.Items.Add($it) | Out-Null
            }
        } catch { Show-Error ((L "Failed to retrieve groups: {0}") -f ($_.Exception.Message)) }
    }
    & $load

    $find.Add_Click({ & $load })
    $search.Add_KeyDown({ if ($_.Key -eq 'Return') { & $load } })
    $ok.Add_Click({
        $dns = @()
        foreach ($it in $list.SelectedItems) { $dns += [string]$it.Tag }
        $script:PickedGroups = $dns
        $w.Close()
    })
    $cancel.Add_Click({ $script:PickedGroups = @(); $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:PickedGroups
}

# --- Group management ---
$GroupsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Group membership" Height="480" Width="560"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Name="GLbl" Text="" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <ListBox Grid.Row="1" Name="GList" SelectionMode="Extended"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
            <Button Name="GAdd" Content="Add..." Width="150" Height="30"/>
        </StackPanel>
        <Button Grid.Row="3" Name="GRemove" Content="Remove from selected groups" Width="240" Height="30"
                HorizontalAlignment="Left" Margin="0,10,0,0"/>
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="GClose" Content="Close" Width="100" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupsDialog {
    param($Owner, $User)
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $GroupsXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("GLbl").Text = ((L "User groups: {0} ({1})") -f ($User.Name), ($User.SamAccountName))
    $list=$w.FindName("GList")
    $add=$w.FindName("GAdd"); $remove=$w.FindName("GRemove"); $close=$w.FindName("GClose")

    $reload = {
        $list.Items.Clear()
        try {
            $p = Get-ADParams
            # memberOf via Get-ADUser: unlike the group-membership cmdlet, this
            # honors -Credential (no "user has not been authenticated" error
            # from non-domain-joined machines).
            $adu = Get-ADUser @p -Identity $User.DistinguishedName -Properties memberOf
            @($adu.memberOf) | Where-Object { $_ } | ForEach-Object {
                $gdn = [string]$_
                $m = [regex]::Match($gdn, '^CN=((?:\\.|[^,\\])*)')
                $gname = if ($m.Success) { $m.Groups[1].Value -replace '\\(.)', '$1' } else { $gdn }
                [pscustomobject]@{ Name = $gname; Dn = $gdn }
            } | Sort-Object Name | ForEach-Object {
                    $it = New-Object System.Windows.Controls.ListBoxItem
                    $it.Content = $_.Name
                    $it.Tag = $_.Dn
                    $list.Items.Add($it) | Out-Null
                }
        } catch { Show-Error ((L "Failed to retrieve the group list: {0}") -f ($_.Exception.Message)) }
    }
    & $reload

    $add.Add_Click({
        $exclude = @()
        foreach ($it in $list.Items) { $exclude += [string]$it.Tag }
        $picked = Show-GroupPickerDialog -Owner $w -ExcludeDNs $exclude
        $added = 0
        foreach ($gdn in $picked) {
            try {
                $p = Get-ADParams
                Add-ADGroupMember @p -Identity $gdn -Members $User.DistinguishedName
                Add-HistoryEntry -Action 'group_add' -Dn $User.DistinguishedName -Details (Get-DnLeaf $gdn)
                $added++
            } catch { Show-Error ((L "Failed to add to group: {0}") -f ($_.Exception.Message)) }
        }
        if ($added) { & $reload }
    })

    $remove.Add_Click({
        $sel = @($list.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action ((L "Remove the user from the selected groups ({0})?") -f ($sel.Count)))) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $User.DistinguishedName -Confirm:$false
                Add-HistoryEntry -Action 'group_remove' -Dn $User.DistinguishedName -Details (Get-DnLeaf ([string]$it.Tag))
            } catch { Show-RemoveMemberError -GroupName ([string]$it.Content) -Ex $_.Exception }
        }
        & $reload
    })

    $close.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
}

# --- Edit properties ---
$EditXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit user properties" Height="760" Width="480"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="18">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="150"/><ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="140"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="First name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="0" Grid.Column="1" Name="EGiven" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="Last name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="1" Grid.Column="1" Name="ESurname" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Display name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="EDisplay" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="E-mail:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="EMail" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="Title:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="4" Grid.Column="1" Name="ETitle" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="5" Grid.Column="0" Text="Department:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="5" Grid.Column="1" Name="EDept" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="6" Grid.Column="0" Text="Company:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="6" Grid.Column="1" Name="ECompany" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="7" Grid.Column="0" Text="Office:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="7" Grid.Column="1" Name="EOffice" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="8" Grid.Column="0" Text="Phone:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="8" Grid.Column="1" Name="EPhone" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="9" Grid.Column="0" Text="Description:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="9" Grid.Column="1" Name="EDesc" Margin="0,4" Padding="3"/>

        <CheckBox Grid.Row="10" Grid.ColumnSpan="2" Name="EPwdNoExpire"
                  Content="Password never expires" Margin="0,8,0,0"/>
        <StackPanel Grid.Row="11" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="24,4,0,0">
            <CheckBox Name="EPneUntil" Content="Clear the flag automatically on:" VerticalAlignment="Center"/>
            <DatePicker Name="EPneDate" Width="150" Margin="8,0,0,0" IsEnabled="False"/>
        </StackPanel>

        <TextBlock Grid.Row="12" Grid.ColumnSpan="2" Text="Group membership (Member Of):"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="13" Grid.ColumnSpan="2" Name="EGroups" SelectionMode="Extended"/>
        <StackPanel Grid.Row="14" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="EGAdd" Content="Add..." Width="130" Height="30"/>
            <Button Name="EGRemove" Content="Remove selected" Width="170" Height="30" Margin="8,0,0,0"/>
        </StackPanel>

        <TextBlock Grid.Row="15" Grid.ColumnSpan="2" Name="EStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,10,0,0"/>

        <StackPanel Grid.Row="16" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="EOk" Content="Save" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="ECancel" Content="Cancel" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-EditDialog {
    param($Owner, $User)
    $ad = $User._AD
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $EditXaml))
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $given=$w.FindName("EGiven"); $surname=$w.FindName("ESurname")
    $disp=$w.FindName("EDisplay"); $mail=$w.FindName("EMail"); $title=$w.FindName("ETitle")
    $dept=$w.FindName("EDept"); $company=$w.FindName("ECompany"); $office=$w.FindName("EOffice")
    $phone=$w.FindName("EPhone"); $desc=$w.FindName("EDesc")
    $egroups=$w.FindName("EGroups"); $egAdd=$w.FindName("EGAdd"); $egRemove=$w.FindName("EGRemove")
    $st=$w.FindName("EStatus"); $ok=$w.FindName("EOk"); $cancel=$w.FindName("ECancel")
    $pwdNoExp = $w.FindName("EPwdNoExpire")
    $pwdNoExp.IsChecked = [bool]$ad.PasswordNeverExpires
    # Optional auto-clear date for the flag (stored in $Global:PwdNeverExpiresUntilAttr)
    $pneUntil = $w.FindName("EPneUntil"); $pneDate = $w.FindName("EPneDate")
    $script:EditInitialUntil = Get-PwdNeverExpiresUntil $ad
    if ($script:EditInitialUntil) { $pneUntil.IsChecked = $true; $pneDate.SelectedDate = $script:EditInitialUntil }
    $togglePne = {
        $on = [bool]$pwdNoExp.IsChecked
        $pneUntil.IsEnabled = $on
        $pneDate.IsEnabled = ($on -and [bool]$pneUntil.IsChecked)
        if ($pneDate.IsEnabled -and -not $pneDate.SelectedDate) { $pneDate.SelectedDate = (Get-Date).Date.AddDays(90) }
    }
    & $togglePne
    $pwdNoExp.Add_Click({ & $togglePne }); $pneUntil.Add_Click({ & $togglePne })

    $given.Text   = [string]$ad.GivenName
    $surname.Text = [string]$ad.Surname
    $disp.Text    = [string]$ad.DisplayName
    $mail.Text    = [string]$ad.Mail
    $title.Text   = [string]$ad.Title
    $dept.Text    = [string]$ad.Department
    $company.Text = [string]$ad.Company
    $office.Text  = [string]$ad.Office
    $phone.Text   = [string]$ad.TelephoneNumber
    $desc.Text    = [string]$ad.Description

    # Group membership (Member Of) — changes are applied immediately
    $reloadGroups = {
        $egroups.Items.Clear()
        try {
            $p = Get-ADParams
            # memberOf via Get-ADUser: unlike the group-membership cmdlet, this
            # honors -Credential (no "user has not been authenticated" error
            # from non-domain-joined machines).
            $adu = Get-ADUser @p -Identity $User.DistinguishedName -Properties memberOf
            @($adu.memberOf) | Where-Object { $_ } | ForEach-Object {
                $gdn = [string]$_
                $m = [regex]::Match($gdn, '^CN=((?:\\.|[^,\\])*)')
                $gname = if ($m.Success) { $m.Groups[1].Value -replace '\\(.)', '$1' } else { $gdn }
                [pscustomobject]@{ Name = $gname; Dn = $gdn }
            } | Sort-Object Name | ForEach-Object {
                    $it = New-Object System.Windows.Controls.ListBoxItem
                    $it.Content = $_.Name
                    $it.Tag = $_.Dn
                    $egroups.Items.Add($it) | Out-Null
                }
        } catch { Show-Error ((L "Failed to retrieve groups: {0}") -f ($_.Exception.Message)) }
    }
    & $reloadGroups

    $egAdd.Add_Click({
        $exclude = @()
        foreach ($it in $egroups.Items) { $exclude += [string]$it.Tag }
        $picked = Show-GroupPickerDialog -Owner $w -ExcludeDNs $exclude
        $added = 0
        foreach ($gdn in $picked) {
            try {
                $p = Get-ADParams
                Add-ADGroupMember @p -Identity $gdn -Members $User.DistinguishedName
                Add-HistoryEntry -Action 'group_add' -Dn $User.DistinguishedName -Details (Get-DnLeaf $gdn)
                $added++
            } catch { Show-Error ((L "Failed to add to group: {0}") -f ($_.Exception.Message)) }
        }
        if ($added) { & $reloadGroups }
    })

    $egRemove.Add_Click({
        $sel = @($egroups.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action ((L "Remove from the selected groups ({0})?") -f ($sel.Count)))) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $User.DistinguishedName -Confirm:$false
                Add-HistoryEntry -Action 'group_remove' -Dn $User.DistinguishedName -Details (Get-DnLeaf ([string]$it.Tag))
            } catch { Show-RemoveMemberError -GroupName ([string]$it.Content) -Ex $_.Exception }
        }
        & $reloadGroups
    })

    $script:EditOk = $false
    $ok.Add_Click({
        $st.Text = ""
        try {
            $p = Get-ADParams
            $p['Identity'] = $User.DistinguishedName
            $p['GivenName']       = $given.Text.Trim()
            $p['Surname']         = $surname.Text.Trim()
            $p['DisplayName']     = $disp.Text
            $p['EmailAddress']    = $mail.Text
            $p['Title']           = $title.Text
            $p['Department']      = $dept.Text
            $p['Company']         = $company.Text
            $p['Office']          = $office.Text
            $p['OfficePhone']     = $phone.Text
            $p['Description']     = $desc.Text
            $p['PasswordNeverExpires'] = [bool]$pwdNoExp.IsChecked
            # Like ADUC: enabling the flag cancels a pending 'change password
            # at next logon' requirement (PasswordLastSet = $null means pending).
            if ([bool]$pwdNoExp.IsChecked -and -not $User._AD.PasswordLastSet) {
                $p['ChangePasswordAtLogon'] = $false
            }
            # Auto-clear date: store with the flag, clear when unset or the flag is off
            $attr = $Global:PwdNeverExpiresUntilAttr
            $until = $null
            if ([bool]$pwdNoExp.IsChecked -and [bool]$pneUntil.IsChecked) {
                if (-not $pneDate.SelectedDate) { $st.Text = (L "Select a date."); return }
                $until = ([DateTime]$pneDate.SelectedDate).Date
                if ($until -le (Get-Date).Date) { $st.Text = (L "The date must be later than today."); return }
                $p['Replace'] = @{ $attr = $until.ToString('yyyy-MM-dd') }
            } elseif ($script:EditInitialUntil) {
                $p['Clear'] = $attr
            }
            Set-ADUser @p
            if ([bool]$pwdNoExp.IsChecked -ne [bool]$ad.PasswordNeverExpires) {
                Add-HistoryEntry -Action $(if ($pwdNoExp.IsChecked) { 'pwd_never_expires_on' } else { 'pwd_never_expires_off' }) -Dn $User.DistinguishedName -Details $(if ($until) { $until.ToString('yyyy-MM-dd') } else { '' })
            }
            Add-HistoryEntry -Action 'edit' -Dn $User.DistinguishedName -Details ((@($p.Keys | Where-Object { $_ -notin @('Identity','Credential','Server') }) | Sort-Object) -join ', ')
            $script:EditOk = $true
            $w.Close()
        }
        catch { $st.Text = ((L "Error: {0}") -f ($_.Exception.Message)) }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:EditOk
}

#endregion

#region ------------------------- Application startup -------------------------

# --- Text-editing shortcuts in all input fields ---
# Shift+Backspace deletes the line (to its start); Ctrl+Backspace deletes
# one word (built into WPF TextBox). Registered as a class handler so every
# TextBox — including editable ComboBox editors — gets the behavior.
$__editKeyHandler = [System.Windows.Input.KeyEventHandler]{
    param($s, $e)
    if ($e.Key -ne [System.Windows.Input.Key]::Back) { return }
    $mods = [System.Windows.Input.Keyboard]::Modifiers
    if (-not ($mods -band [System.Windows.Input.ModifierKeys]::Shift)) { return }
    $tb = $s
    try {
        $i = $tb.CaretIndex
        $ls = 0
        try {
            $line = $tb.GetLineIndexFromCharacterIndex($i)
            if ($line -ge 0) { $ls = $tb.GetCharacterIndexFromLineIndex($line) }
        } catch { $ls = 0 }
        if ($i -gt $ls) {
            $tb.Select($ls, $i - $ls)
            $tb.SelectedText = ''
            $tb.CaretIndex = $ls
        }
        $e.Handled = $true
    } catch { }
}
[System.Windows.EventManager]::RegisterClassHandler(
    [System.Windows.Controls.TextBox],
    [System.Windows.UIElement]::PreviewKeyDownEvent,
    $__editKeyHandler)

# PasswordBox has no caret API: Shift+Backspace clears the whole field
$__pwdKeyHandler = [System.Windows.Input.KeyEventHandler]{
    param($s, $e)
    if ($e.Key -ne [System.Windows.Input.Key]::Back) { return }
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) {
        try { $s.Clear() } catch { }
        $e.Handled = $true
    }
}
[System.Windows.EventManager]::RegisterClassHandler(
    [System.Windows.Controls.PasswordBox],
    [System.Windows.UIElement]::PreviewKeyDownEvent,
    $__pwdKeyHandler)

# 1. Check the AD module
if (-not (Test-ADModule)) { return }

# Interface language: saved choice, otherwise the system locale
$Script:Lang = Get-AppLang
if (-not $Script:Lang) {
    $Script:Lang = if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru') { 'ru' } else { 'en' }
}
Set-UiCulture

# 2. Request credentials
# The login dialog can switch the language; it then asks to be reopened.
# NOTE: compare as strings — ($true -eq 'again') is $true in PowerShell
# because the right operand is coerced to [bool].
while ($true) {
    $r = Show-LoginWindow
    if ("$r" -eq 'again') { continue }
    if (-not $r) { return }   # cancelled — exit
    break
}

# 3. Build the main window
$reader   = New-Object System.Xml.XmlNodeReader ([xml](Localize-Xaml $MainXaml))
$MainWin  = [Windows.Markup.XamlReader]::Load($reader)

$TxtSearch = $MainWin.FindName("TxtSearch")
$BtnSearch = $MainWin.FindName("BtnSearch")
$BtnRefresh= $MainWin.FindName("BtnRefresh")
$BtnCreate = $MainWin.FindName("BtnCreate")
$BtnHistory = $MainWin.FindName("BtnHistory")
$BtnHistory.Add_Click({ Show-HistoryDialog -Owner $MainWin })
$BtnPwdGen = $MainWin.FindName("BtnPwdGen")
$BtnPwdGen.Add_Click({ Show-PasswordGeneratorDialog -Owner $MainWin | Out-Null })
$GridUsers = $MainWin.FindName("GridUsers")
$PanelProps= $MainWin.FindName("PanelProps")
$LblConn   = $MainWin.FindName("LblConn")
$CmbDomain      = $MainWin.FindName("CmbDomain")
$BtnSwitchDomain= $MainWin.FindName("BtnSwitchDomain")
$TreeOU         = $MainWin.FindName("TreeOU")
$ChkSubtree     = $MainWin.FindName("ChkSubtree")
$ChkAllDomains  = $MainWin.FindName("ChkAllDomains")
$Script:OtherDomainErrors = @()
$Script:PendingSelectDn = $null

$BtnEnable  = $MainWin.FindName("BtnEnable")
$BtnDisable = $MainWin.FindName("BtnDisable")
$BtnUnlock  = $MainWin.FindName("BtnUnlock")
$BtnResetPwd= $MainWin.FindName("BtnResetPwd")
$BtnGroups  = $MainWin.FindName("BtnGroups")
$BtnMove    = $MainWin.FindName("BtnMove")
$BtnEdit    = $MainWin.FindName("BtnEdit")
$BtnRename  = $MainWin.FindName("BtnRename")
$BtnDelete  = $MainWin.FindName("BtnDelete")
$BtnCreateGroup = $MainWin.FindName("BtnCreateGroup")
$BtnMembers = $MainWin.FindName("BtnMembers")
$RbGroups   = $MainWin.FindName("RbGroups")
$BtnPwdNoExpire = $MainWin.FindName("BtnPwdNoExpire")
$RbUsers    = $MainWin.FindName("RbUsers")
$RbComputers= $MainWin.FindName("RbComputers")
$GrpProps   = $MainWin.FindName("GrpProps")
$GrpActions = $MainWin.FindName("GrpActions")
$CmbLang    = $MainWin.FindName("CmbLang")
$LblSearchCap = $MainWin.FindName("LblSearchCap")
$LblDomainCap = $MainWin.FindName("LblDomainCap")
$LblShowCap   = $MainWin.FindName("LblShowCap")
$LblOuCap     = $MainWin.FindName("LblOuCap")

$LblConn.Text = ((L "Connected to: {0}   |   User: {1}") -f ($Global:ADConnection.Server), ($Global:ADConnection.UserName))

# Format a date/datetime as yyyy-mmm-dd (e.g. 2026-aug-14), month lowercased.
$Script:RuMonths = @('янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек')

function Format-AdDate {
    param([datetime]$Dt, [switch]$WithTime)
    # AD can hand back UTC-kind timestamps (GMT+0); show them in the local
    # time zone of the machine running the app.
    if ($Dt.Kind -eq [System.DateTimeKind]::Utc) { $Dt = $Dt.ToLocalTime() }
    if ($Script:Lang -eq 'ru') {
        $mon = $Script:RuMonths[$Dt.Month - 1]
        $s = '{0:D2} {1} {2:D4}' -f $Dt.Day, $mon, $Dt.Year
        if ($WithTime) { $s += (' {0:D2}:{1:D2}' -f $Dt.Hour, $Dt.Minute) }
        return $s
    }
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    $fmt = if ($WithTime) { 'yyyy-MMM-dd HH:mm' } else { 'yyyy-MMM-dd' }
    return $Dt.ToString($fmt, $ci).ToLower()
}

# --- When the password must be changed ---
function Get-PwdExpiryText {
    param($ad)
    if (-not $ad.PasswordLastSet) { return (L "at next logon (change required)") }
    if ($ad.PasswordNeverExpires) { return (L "never (password does not expire)") }
    $exp = $ad.'msDS-UserPasswordExpiryTimeComputed'
    if ($null -eq $exp) { return "" }
    if ([Int64]$exp -le 0 -or [Int64]$exp -ge 9223372036854775807) { return (L "never") }
    try {
        $dt = [DateTime]::FromFileTime([Int64]$exp)
        $txt = Format-AdDate $dt -WithTime
        if ($dt -lt (Get-Date)) { $txt += (L " (expired)") }
        return $txt
    } catch { return "" }
}

# --- Render properties of the selected user ---

function Get-DcHostList {
    # DNS names of all domain controllers (cached per server connection once
    # known). Three sources are tried, because a restricted account may be
    # denied one of them: Get-ADDomainController, the computer objects in
    # OU=Domain Controllers, and the server objects of the forest Sites
    # container that belong to this domain. Failures are not cached — the
    # next call tries again; the last error is kept in $Script:DcHostListError.
    # -Server: controllers of ANOTHER domain (an object found by the all-domains
    # search), queried with the session credentials through the trust.
    param([string]$Server)
    $srv = if ($Server) { $Server } else { [string]$Global:ADConnection.Server }
    if ($Script:DcHostList -and $Script:DcHostList.Count -gt 0 -and $Script:DcHostListSrv -eq $srv) {
        return $Script:DcHostList
    }
    $Script:DcHostListError = ''
    $errors = @()
    $dcs = @()
    $p = Get-ADParams
    $baseDn = [string]$Global:ADConnection.BaseDN
    if ($Server) {
        $p['Server'] = $Server
        try { $baseDn = [string](Get-ADDomain @p).DistinguishedName } catch { $errors += "domain: $($_.Exception.Message)" }
    }
    try {
        $dcs = @(Get-ADDomainController @p -Filter * | ForEach-Object { [string]$_.HostName } | Where-Object { $_ })
    } catch { $errors += "dc: $($_.Exception.Message)" }
    if ($dcs.Count -eq 0) {
        try {
            $dcs = @(Get-ADComputer @p -SearchBase ("OU=Domain Controllers," + $baseDn) -Filter * -Properties DNSHostName |
                     ForEach-Object { if ($_.DNSHostName) { [string]$_.DNSHostName } else { [string]$_.Name } } | Where-Object { $_ })
        } catch { $errors += "ou: $($_.Exception.Message)" }
    }
    if ($dcs.Count -eq 0) {
        try {
            $root = Get-ADRootDSE @p
            $baseLow = $baseDn.ToLower() -replace ', ', ','
            $dcs = @(Get-ADObject @p -SearchBase ("CN=Sites," + $root.configurationNamingContext) -LDAPFilter '(&(objectClass=server)(dNSHostName=*))' -Properties dNSHostName, serverReference |
                     Where-Object {
                         $ref = ([string]$_.serverReference).ToLower() -replace ', ', ','
                         $k = $ref.IndexOf('dc=')
                         (-not $ref) -or ($k -ge 0 -and $ref.Substring($k) -eq $baseLow)
                     } | ForEach-Object { [string]$_.dNSHostName } | Where-Object { $_ })
        } catch { $errors += "sites: $($_.Exception.Message)" }
    }
    $dcs = @($dcs | Sort-Object -Unique)
    if ($errors.Count -gt 0) {
        $Script:DcHostListError = ($errors -join '; ')
        Add-SwitchLog @("dc list ($srv): $($dcs.Count) found; $($Script:DcHostListError)")
    }
    $Script:DcHostListSrv = $srv
    if ($dcs.Count -gt 0) { $Script:DcHostList = $dcs } else { $Script:DcHostList = $null }
    return $dcs
}

# --- Per-DC non-replicated attributes (lastLogon / badPasswordTime /
# badPwdCount are kept per controller and never replicated), fetched in a
# background runspace so the UI stays responsive ---
$Script:DcPropsJob = $null
$Script:DcPropsTimer = $null
$Script:DcPropsWantDn = $null

function Add-DcPropsRows {
    # Render the per-DC values as an aligned monospaced table
    param($Rows)
    $table = @(,@((L "DC"), (L "Logon"), (L "Bad password"), (L "Attempts")))
    foreach ($r in $Rows) {
        $dcShort = ([string]$r.Dc -split '\.')[0]
        if ($r.Error) { $table += ,@($dcShort, (L "(unavailable)"), '', ''); continue }
        $ll = if ($r.LastLogon -and [int64]$r.LastLogon -gt 0) { Format-AdDate ([DateTime]::FromFileTime([int64]$r.LastLogon)) -WithTime } else { (L "never") }
        $bp = if ($r.BadPwdTime -and [int64]$r.BadPwdTime -gt 0) { Format-AdDate ([DateTime]::FromFileTime([int64]$r.BadPwdTime)) -WithTime } else { (L "never") }
        $cnt = if ($null -ne $r.BadPwdCount -and "$($r.BadPwdCount)" -ne '') { "$($r.BadPwdCount)" } else { '' }
        $table += ,@($dcShort, $ll, $bp, $cnt)
    }
    if ($table.Count -le 1) { return }
    $widths = @(0, 0, 0, 0)
    foreach ($row in $table) {
        for ($i = 0; $i -lt 4; $i++) {
            if ($row[$i].Length -gt $widths[$i]) { $widths[$i] = $row[$i].Length }
        }
    }
    $lines = foreach ($row in $table) {
        ((0..3 | ForEach-Object { ([string]$row[$_]).PadRight($widths[$_]) }) -join '  ').TrimEnd()
    }
    $k = (L "By domain controller (non-replicated attributes)")
    $val = $lines -join "`r`n"
    $Script:PropRows += "${k}: $val"
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '0,0,0,6'
    $lblTb = New-Object System.Windows.Controls.TextBlock
    $lblTb.Text = "${k}:"
    $lblTb.FontWeight = 'SemiBold'
    $lblTb.Foreground = '#555555'
    $vTb = New-Object System.Windows.Controls.TextBox
    $vTb.Text = $val; $vTb.IsReadOnly = $true
    $vTb.FontFamily = 'Consolas'
    $vTb.BorderThickness = '0'; $vTb.Background = 'Transparent'; $vTb.Padding = '0'
    $vTb.HorizontalScrollBarVisibility = 'Auto'
    $sp.Children.Add($lblTb) | Out-Null
    $sp.Children.Add($vTb) | Out-Null
    $PanelProps.Children.Add($sp) | Out-Null
}

function Start-DcPropsQuery {
    param([string]$Dn, [string]$Server)
    $Script:DcPropsWantDn = $Dn
    $Script:DcPropsWantServer = $Server
    if ($Script:DcPropsJob) { return }   # busy: the timer re-fires for the latest DN
    $dcs = @(Get-DcHostList -Server $Server)
    if ($dcs.Count -lt 2) {
        if ($Script:DcHostListError) {
            $k = (L "By domain controller (non-replicated attributes)")
            $val = ((L "(controller list unavailable: {0})") -f $Script:DcHostListError)
            $Script:PropRows += "${k}: $val"
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Margin = '0,0,0,6'
            $lblTb = New-Object System.Windows.Controls.TextBlock
            $lblTb.Text = "${k}:"; $lblTb.FontWeight = 'SemiBold'; $lblTb.Foreground = '#555555'
            $vTb = New-Object System.Windows.Controls.TextBlock
            $vTb.Text = $val; $vTb.TextWrapping = 'Wrap'
            $sp.Children.Add($lblTb) | Out-Null
            $sp.Children.Add($vTb) | Out-Null
            $PanelProps.Children.Add($sp) | Out-Null
        }
        return
    }
    $cred = $Global:ADConnection.Credential
    if (-not $cred) { return }
    # Against the controllers of another domain a bare login would be looked up
    # there; qualify it with the home domain so the trust is used.
    $bindUser = [string]$cred.UserName
    if ($Server -and $bindUser -notmatch '[\\@]') {
        $v = @(Get-LoginVariantsForHome -Login $bindUser -DnsRoot $Global:ADConnection.DnsRoot -NetBIOSName $Global:ADConnection.NetBIOSName)
        if ($v.Count -gt 0) { $bindUser = $v[0] }
    }
    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($Dcs, $Dn, $User, $Pass)
        $out = @()
        $adsDn = $Dn -replace '/', '\/'
        foreach ($dc in $Dcs) {
            $r = [pscustomobject]@{ Dc = $dc; LastLogon = $null; BadPwdTime = $null; BadPwdCount = $null; Error = $null }
            try {
                $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$dc/$adsDn", $User, $Pass)
                $s = New-Object System.DirectoryServices.DirectorySearcher($root, '(objectClass=*)', @('lastLogon','badPasswordTime','badPwdCount'), 'Base')
                $s.ClientTimeout = [TimeSpan]::FromSeconds(7)
                $res = $s.FindOne()
                if ($res) {
                    if ($res.Properties['lastlogon'].Count)       { $r.LastLogon   = [int64]$res.Properties['lastlogon'][0] }
                    if ($res.Properties['badpasswordtime'].Count) { $r.BadPwdTime  = [int64]$res.Properties['badpasswordtime'][0] }
                    if ($res.Properties['badpwdcount'].Count)     { $r.BadPwdCount = [int]$res.Properties['badpwdcount'][0] }
                } else { $r.Error = 'not found' }
            } catch { $r.Error = $_.Exception.Message }
            $out += $r
        }
        return $out
    }).AddArgument($dcs).AddArgument($Dn).AddArgument($bindUser).AddArgument($cred.GetNetworkCredential().Password)
    $Script:DcPropsJob = @{ PS = $ps; Handle = $ps.BeginInvoke(); Dn = $Dn }
    if (-not $Script:DcPropsTimer) {
        $Script:DcPropsTimer = New-Object System.Windows.Threading.DispatcherTimer
        $Script:DcPropsTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $Script:DcPropsTimer.Add_Tick({
            $job = $Script:DcPropsJob
            if (-not $job) { $Script:DcPropsTimer.Stop(); return }
            if (-not $job.Handle.IsCompleted) { return }
            $rows = @()
            try { $rows = @($job.PS.EndInvoke($job.Handle)) } catch { $rows = @() }
            try { $job.PS.Dispose() } catch { }
            $Script:DcPropsJob = $null
            if ([string]$job.Dn -eq [string]$Script:DcPropsWantDn) {
                $Script:DcPropsTimer.Stop()
                $sel = $GridUsers.SelectedItem
                if ($sel -and [string]$sel.DistinguishedName -eq [string]$job.Dn -and $rows.Count) {
                    Add-DcPropsRows -Rows $rows
                }
            } else {
                Start-DcPropsQuery -Dn ([string]$Script:DcPropsWantDn) -Server ([string]$Script:DcPropsWantServer)
            }
        })
    }
    $Script:DcPropsTimer.Stop(); $Script:DcPropsTimer.Start()
}

function Update-PropsPanel {
    param($User)
    $PanelProps.Children.Clear()
    if (-not $User) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = (L "Select a user from the list")
        $tb.Foreground = 'Gray'; $tb.FontStyle = 'Italic'
        $PanelProps.Children.Add($tb) | Out-Null
        return
    }
    $ad = $User._AD
    if ($User._IsGroup) {
        $memberCount = ''
        try {
            $memberCount = @(Get-GroupMemberList -Dn $ad.DistinguishedName).Count
        } catch { }
        $rows = [ordered]@{
            (L "Name")        = $ad.Name
            (L "Login")       = $ad.SamAccountName
            (L "Scope")       = (Get-GroupScopeLabel $ad)
            (L "Category")    = (Get-GroupCategoryLabel $ad)
            (L "Description") = $ad.Description
            "E-mail"          = $ad.mail
            (L "Members")     = $memberCount
            (L "Created")     = $ad.whenCreated
            "DN"              = $ad.DistinguishedName
        }
    }
    elseif ($User._IsComputer) {
        $rows = [ordered]@{
            (L "Name")             = $ad.Name
            (L "Account name")     = $ad.SamAccountName
            (L "DNS name")         = $ad.DNSHostName
            (L "Operating system") = $ad.OperatingSystem
            (L "OS version")       = $ad.OperatingSystemVersion
            (L "State")            = (Get-ComputerState $ad)
            (L "Description")      = $ad.Description
            (L "Last logon")       = $ad.LastLogonDate
            (L "Created")          = $ad.whenCreated
            "DN"               = $ad.DistinguishedName
        }
    }
    else {
    $rows = [ordered]@{
        (L "Display name")    = $ad.DisplayName
        (L "Login")           = $ad.SamAccountName
        "UPN"              = $ad.UserPrincipalName
        (L "First name")      = $ad.GivenName
        (L "Last name")       = $ad.Surname
        "E-mail"           = $ad.Mail
        (L "E-mail addresses (Exchange)") = (Get-MailAddressesText $ad $(if ($User._Foreign) { [string]$User._Host } else { '' }))
        (L "State")           = (Get-UserState $ad)
        (L "Locked")          = if ($ad.LockedOut) { (L "Yes") } else { (L "No") }
        (L "Description")      = $ad.Description
        (L "Title")           = $ad.Title
        (L "Department")      = $ad.Department
        (L "Company")         = $ad.Company
        (L "Office")          = $ad.Office
        (L "Phone")          = $ad.TelephoneNumber
        (L "Password last set")     = $ad.PasswordLastSet
        (L "Password never expires") = if ($ad.PasswordNeverExpires) { (L "Yes") } else { (L "No") }
        (L "Flag auto-clear date") = $(if ($d = Get-PwdNeverExpiresUntil $ad) { Format-AdDate $d } else { '' })
        (L "Password change required") = (Get-PwdExpiryText $ad)
        (L "Bad password attempts") = $ad.badPwdCount
        (L "Last bad password")     = $ad.LastBadPasswordAttempt
        (L "Last logon")      = $ad.LastLogonDate
        (L "Created")         = $ad.whenCreated
        (L "Expires")        = $ad.AccountExpirationDate
        "DN"               = $ad.DistinguishedName
    }
    }
    $Script:PropRows = @()
    foreach ($k in $rows.Keys) {
        $raw = $rows[$k]
        if ($raw -is [datetime]) {
            $val = Format-AdDate $raw -WithTime
        } else {
            $val = [string]$raw
        }
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        $Script:PropRows += "${k}: $val"

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = '0,0,0,6'
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $k; $lbl.FontWeight = 'SemiBold'; $lbl.Foreground = '#555'
        $lbl.FontSize = 11
        # Read-only, selectable TextBox so the value can be highlighted and copied
        $v = New-Object System.Windows.Controls.TextBox
        $v.Text = $val; $v.TextWrapping = 'Wrap'
        $v.IsReadOnly = $true; $v.BorderThickness = '0'; $v.Background = 'Transparent'
        $v.Padding = '0'
        if ($k -eq (L "E-mail addresses (Exchange)") -and $val.Contains("`n")) { $v.FontFamily = 'Consolas'; $v.TextWrapping = 'NoWrap'; $v.HorizontalScrollBarVisibility = 'Auto' }
        # Context menu: copy this value / copy all
        $cm = New-Object System.Windows.Controls.ContextMenu
        $miVal = New-Object System.Windows.Controls.MenuItem
        $miVal.Header = ((L "Copy value ({0})") -f ($k))
        $miVal.Tag = $val
        $miVal.Add_Click({ Set-ClipboardText ([string]$this.Tag) })
        $miAll = New-Object System.Windows.Controls.MenuItem
        $miAll.Header = (L "Copy all properties")
        $miAll.Add_Click({ Set-ClipboardText ($Script:PropRows -join "`r`n") })
        $cm.Items.Add($miVal) | Out-Null
        $cm.Items.Add($miAll) | Out-Null
        $v.ContextMenu = $cm

        $sp.Children.Add($lbl) | Out-Null
        $sp.Children.Add($v)   | Out-Null
        $PanelProps.Children.Add($sp) | Out-Null
    }
    if (-not $User._IsGroup -and -not $User._IsComputer) {
        # For an object of another domain (all-domains search) the controllers
        # of THAT domain are asked, with the session credentials.
        $srv = if ($User._Foreign) { [string]$User._Host } else { '' }
        Start-DcPropsQuery -Dn ([string]$ad.DistinguishedName) -Server $srv
    }
}

# --- Clipboard helper ---
function Set-ClipboardText {
    param([string]$Text)
    if ($null -eq $Text) { return }
    try {
        [System.Windows.Clipboard]::SetText($Text)
        if ($LblConn) { $LblConn.Text = ((L "{0}   |   Copied") -f ($LblConn.Text)) }
    } catch { }
}

# --- Build the organizational unit (OU) tree ---
function Load-OUTree {
    $TreeOU.Items.Clear()
    $baseDN = $Global:ADConnection.BaseDN
    if (-not $baseDN) { return }
    $rootLabel = if ($Global:ADConnection.DnsRoot) { $Global:ADConnection.DnsRoot } else { $baseDN }

    $rootItem = New-Object System.Windows.Controls.TreeViewItem
    $rootItem.Header = $rootLabel
    $rootItem.Tag = $baseDN
    $rootItem.IsExpanded = $true
    $TreeOU.Items.Add($rootItem) | Out-Null

    $map = @{}
    $map[$baseDN.ToLower()] = $rootItem

    try {
        $p1 = Get-ADParams
        $ous = @(Get-ADOrganizationalUnit @p1 -Filter * |
                 Select-Object -ExpandProperty DistinguishedName)
        # Standard top-level containers (CN=Users, CN=Computers, CN=Builtin, etc.)
        $p2 = Get-ADParams
        $conts = @(Get-ADObject @p2 -SearchBase $baseDN -SearchScope OneLevel `
                     -LDAPFilter '(|(objectClass=container)(objectClass=builtinDomain))' |
                   Select-Object -ExpandProperty DistinguishedName)
    }
    catch { $ous = @(); $conts = @() }

    $all = @($ous + $conts) | Where-Object { $_ -and ($_.ToLower() -ne $baseDN.ToLower()) }
    # Sort by depth (comma count), then alphabetically — parent before child
    $all = $all | Sort-Object @{ Expression = { ($_ -split ',').Count } }, @{ Expression = { $_ } }

    foreach ($dn in $all) {
        $parentDN = ($dn -split ',', 2)[1]
        $parentItem = $map[$parentDN.ToLower()]
        if (-not $parentItem) { $parentItem = $rootItem }
        $rdn = ($dn -split ',', 2)[0]
        $label = ($rdn -split '=', 2)[1]
        $item = New-Object System.Windows.Controls.TreeViewItem
        $item.Header = $label
        $item.Tag = $dn
        $parentItem.Items.Add($item) | Out-Null
        $map[$dn.ToLower()] = $item
    }

    # Select the root (triggers Invoke-Search via the SelectedItemChanged handler)
    $rootItem.IsSelected = $true
}

# --- Run the search and fill the table ---
function Invoke-Search {
    $MainWin.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $base = $null
        $sel = $TreeOU.SelectedItem
        if ($sel -and $sel.Tag) { $base = [string]$sel.Tag }

        $text = $TxtSearch.Text
        $subtree = (-not [string]::IsNullOrWhiteSpace($text)) -or $ChkSubtree.IsChecked
        $scope = if ($subtree) { 'Subtree' } else { 'OneLevel' }

        if ($RbComputers.IsChecked) {
            $results = @(Search-ADComputers -Query $text -SearchBase $base -Scope $scope)
        } elseif ($RbGroups -and $RbGroups.IsChecked) {
            $results = @(Search-ADGroupsList -Query $text -SearchBase $base -Scope $scope)
        } else {
            $results = @(Search-ADUsers -Query $text -SearchBase $base -Scope $scope)
            if ((Test-AllDomainsOn) -and -not [string]::IsNullOrWhiteSpace($text)) {
                $own = @{}
                foreach ($r in $results) { $own[("$($r.DistinguishedName)").ToLower()] = $true }
                $others = @(Search-OtherDomains -Query $text | Where-Object { -not $own.ContainsKey(("$($_.DistinguishedName)").ToLower()) })
                $results = @($results + $others | Sort-Object Name, Domain)
            }
        }
        $GridUsers.ItemsSource = $results

        $scopeTxt = if ($sel -and $sel.Header) { [string]$sel.Header } else { $Global:ADConnection.DnsRoot }
        if ($subtree) { $scopeTxt = ((L "{0} (+nested)") -f ($scopeTxt)) }
        if ((Test-AllDomainsOn) -and -not [string]::IsNullOrWhiteSpace($text)) {
            $scopeTxt = (L "scope: all saved domains")
            if ($Script:OtherDomainErrors.Count -gt 0) { $scopeTxt += ((L "; unavailable: {0}") -f ($Script:OtherDomainErrors -join ', ')) }
        }
        $LblConn.Text = ((L "Connected to: {0}   |   ") -f ($Global:ADConnection.Server)) +
                        ((L "User: {0}   |   ") -f ($Global:ADConnection.UserName)) +
                        ((L "Scope: {0}   |   Found: {1}") -f ($scopeTxt), ($results.Count))
    }
    catch { Show-Error ((L "Search error: {0}") -f ($_.Exception.Message)) }
    finally { $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow }
}

# --- Get the selected user ---
function Offer-SwitchToObjectDomain {
    # An object from another domain was chosen for an action: offer to switch to
    # that domain (same search text, the object re-selected after the switch)
    param($U)
    $label = if ($U.Name) { $U.Name } else { $U.SamAccountName }
    $dom = if ($U.Domain) { $U.Domain } else { $U._Host }
    if (Confirm-Action ((L '"{0}" belongs to domain {1}.`r`nActions are available only in the connected domain.`r`n`r`nSwitch to domain {1} now?') -f $label, $dom) (L "Object from another domain")) {
        $Script:PendingSelectDn = [string]$U.DistinguishedName
        $CmbDomain.Text = [string]$U._Host
        $BtnSwitchDomain.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    }
}

function Get-SelectedUser {
    param([switch]$AllowForeign)
    if ($GridUsers.SelectedItems.Count -gt 1) {
        Show-Info (L "This action applies to a single object.`r`nSelect exactly one item in the list.") (L "Multiple objects selected")
        return $null
    }
    $u = $GridUsers.SelectedItem
    if (-not $u) { Show-Info (L "Select a user in the list first.") (L "No user selected"); return $null }
    if ($u._Foreign -and -not $AllowForeign) { Offer-SwitchToObjectDomain $u; return $null }
    return $u
}

function Get-SelectedUsers {
    # All selected objects (multi-select aware)
    param([switch]$AllowForeign)
    $items = @($GridUsers.SelectedItems)
    if (-not $items -or $items.Count -eq 0) {
        Show-Info (L "Select one or more objects in the list.") (L "No object selected")
        return @()
    }
    if (-not $AllowForeign) {
        $foreign = @($items | Where-Object { $_._Foreign })
        if ($foreign.Count -gt 0) {
            if ($items.Count -eq 1) { Offer-SwitchToObjectDomain $foreign[0] }
            else {
                $doms = ($foreign | ForEach-Object { [string]$_.Domain } | Sort-Object -Unique) -join ', '
                Show-Info ((L "The selection contains objects from other domains ({0}). Bulk actions apply only to the connected domain.") -f $doms) (L "Object from another domain")
            }
            return @()
        }
    }
    return $items
}

# --- Re-read the selected user from AD and refresh the panel ---
function Refresh-SelectedUser {
    param($Dn)
    try {
        $p = Get-ADParams
        $p['Identity'] = $Dn
        $p['Properties'] = $Script:UserProps
        $ad = Get-ADUser @p
        $obj = [pscustomobject]@{
            Name              = if ($ad.DisplayName) { $ad.DisplayName } else { $ad.Name }
            SamAccountName    = $ad.SamAccountName
            Mail              = $ad.Mail
            Description       = $ad.Description
            State             = Get-UserState $ad
            DistinguishedName = $ad.DistinguishedName
            _AD               = $ad
        }
        Update-PropsPanel $obj
    } catch { }
}

# --- Set list columns for the current mode (users / computers) ---
function Set-GridColumns {
    param([switch]$Computers, [switch]$Groups)
    $GridUsers.Columns.Clear()
    $mk = {
        param($header, $bind, $wStar)
        $col = New-Object System.Windows.Controls.DataGridTextColumn
        $col.Header = $header
        $col.Binding = New-Object System.Windows.Data.Binding $bind
        $col.Width = New-Object System.Windows.Controls.DataGridLength($wStar, [System.Windows.Controls.DataGridLengthUnitType]::Star)
        return $col
    }
    if ($Computers) {
        $GridUsers.Columns.Add((& $mk (L 'Name') 'Name' 1.4)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'DNS name') 'DnsHostName' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Operating system') 'OS' 1.5)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Description') 'Description' 1.4)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'State') 'State' 1.0)) | Out-Null
    } elseif ($Groups) {
        $GridUsers.Columns.Add((& $mk (L 'Name') 'Name' 1.7)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Login') 'SamAccountName' 1.2)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Scope') 'Scope' 1.0)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Category') 'Category' 1.0)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Description') 'Description' 1.7)) | Out-Null
    } else {
        $GridUsers.Columns.Add((& $mk (L 'Name') 'Name' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Login') 'SamAccountName' 1.2)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'E-mail' 'Mail' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'Description') 'Description' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk (L 'State') 'State' 1.0)) | Out-Null
        if (Test-AllDomainsOn) { $GridUsers.Columns.Add((& $mk (L 'Domain') 'Domain' 1.1)) | Out-Null }
    }
}

# --- Switch between users and computers ---
function Get-CurrentMode {
    if ($RbComputers -and $RbComputers.IsChecked) { return 'computers' }
    if ($RbGroups -and $RbGroups.IsChecked) { return 'groups' }
    return 'users'
}

function Switch-Mode {
    $mode = Get-CurrentMode
    $computers = ($mode -eq 'computers')
    $groups = ($mode -eq 'groups')
    $TxtSearch.Text = ""
    $PanelProps.Children.Clear()
    $Script:PropRows = @()
    Set-GridColumns -Computers:$computers -Groups:$groups
    if ($ChkAllDomains) { $ChkAllDomains.Visibility = $(if ($mode -eq 'users') { 'Visible' } else { 'Collapsed' }) }
    $GrpProps.Header = switch ($mode) {
        'computers' { (L "Computer properties") }
        'groups'    { (L "Group properties") }
        default     { (L "User properties") }
    }

    # Action buttons (Edit stays visible in every mode — it routes by object type)
    $userBtns  = @($BtnUnlock, $BtnResetPwd, $BtnPwdNoExpire, $BtnGroups)
    $acctBtns  = @($BtnEnable, $BtnDisable)          # users + computers
    $renBtns   = @($BtnRename, $BtnDelete)           # computers + groups
    $grpBtns   = @($BtnCreateGroup, $BtnMembers)     # groups only
    foreach ($b in $userBtns) { if ($b) { $b.Visibility = if ($mode -eq 'users') { 'Visible' } else { 'Collapsed' } } }
    foreach ($b in $acctBtns) { if ($b) { $b.Visibility = if ($groups) { 'Collapsed' } else { 'Visible' } } }
    foreach ($b in $renBtns)  { if ($b) { $b.Visibility = if ($mode -eq 'users') { 'Collapsed' } else { 'Visible' } } }
    foreach ($b in $grpBtns)  { if ($b) { $b.Visibility = if ($groups) { 'Visible' } else { 'Collapsed' } } }
    if ($BtnCreate) { $BtnCreate.Visibility = if ($mode -eq 'users') { 'Visible' } else { 'Collapsed' } }

    # Context-menu items
    $cm = $GridUsers.ContextMenu
    $userItems = @('CmCopyMail','CmCopyUpn','CmUnlock','CmResetPwd','CmPwdNoExpire','CmGroups')
    $acctItems = @('CmEnable','CmDisable')
    $renItems  = @('CmRename','CmDelete')
    $grpItems  = @('CmMembers')
    foreach ($n in $userItems) { $mi = Get-CmItem($n); if ($mi) { $mi.Visibility = if ($mode -eq 'users') { 'Visible' } else { 'Collapsed' } } }
    foreach ($n in $acctItems) { $mi = Get-CmItem($n); if ($mi) { $mi.Visibility = if ($groups) { 'Collapsed' } else { 'Visible' } } }
    foreach ($n in $renItems)  { $mi = Get-CmItem($n); if ($mi) { $mi.Visibility = if ($mode -eq 'users') { 'Collapsed' } else { 'Visible' } } }
    foreach ($n in $grpItems)  { $mi = Get-CmItem($n); if ($mi) { $mi.Visibility = if ($groups) { 'Visible' } else { 'Collapsed' } } }

    Invoke-Search
}

# --- Domain switching ---
function Update-DomainCombo {
    $CmbDomain.Items.Clear()
    foreach ($d in (Get-SavedDomains)) { $CmbDomain.Items.Add($d.Name) | Out-Null }
    $cur = $Global:ADConnection.Server
    if ($cur -and $CmbDomain.Items.Contains($cur)) {
        $CmbDomain.SelectedItem = $cur
    }
}
Update-DomainCombo

$BtnSwitchDomain.Add_Click({
    $target = $CmbDomain.Text
    if ([string]::IsNullOrWhiteSpace($target)) { $target = [string]$CmbDomain.SelectedItem }
    $target = ("$target").Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        Show-Info (L "Select from the list or enter a domain/controller.")
        return
    }
    if ($target.ToLower() -eq ("$($Global:ADConnection.Server)").ToLower()) { return }

    if (-not (Test-DCReachable $target)) {
        Show-Error ((L 'Domain controller "{0}" is unreachable. Check the server name and network connectivity.') -f ($target))
        return
    }

    # Which account: the active session (default) or another one
    $choice = Show-SwitchCredentialsDialog -Owner $MainWin -Target $target -CurrentUser $Global:ADConnection.UserName
    if (-not $choice) { return }
    $cred = $Global:ADConnection.Credential
    $userLabel = [string]$Global:ADConnection.UserName
    if ($choice.Mode -eq 'other') { $cred = $choice.Credential; $userLabel = $cred.UserName }

    $MainWin.Cursor = [System.Windows.Input.Cursors]::Wait
    $info = $null
    $triedVariants = @()
    $bindResults = @()
    Add-SwitchLog @("switch $($Global:ADConnection.Server) -> $target account mode=$($choice.Mode)")
    try {
        try {
            $info = Get-ADDomain -Server $target -Credential $cred -ErrorAction Stop
            Add-SwitchLog @("  $($cred.UserName): OK")
        } catch {
            $firstErr = $_
            $bindResults += "$($cred.UserName) — $($firstErr.Exception.Message)"
            Add-SwitchLog @("  $($cred.UserName): $($firstErr.Exception.Message)")
            # Session account rejected by the target DC. Retry the same password with
            # 1) the account qualified with its HOME domain (HOME\user, user@home) — a
            #    bare name is looked up by the target DC in ITS domain, the qualified
            #    form is forwarded through the trust; 2) the account re-qualified with
            #    the TARGET domain, in case a same-named account exists there (no trust).
            $isAuth = ($firstErr.Exception.Message -match 'credential|logon|authentic|password|denied|учетн|пароль|провер|отказ')
            if ($choice.Mode -eq 'current' -and $isAuth) {
                $pwd = $cred.Password
                $variants = @(Get-LoginVariantsForHome -Login $cred.UserName -DnsRoot $Global:ADConnection.DnsRoot -NetBIOSName $Global:ADConnection.NetBIOSName)
                $variants += @(Get-LoginVariantsForDomain -Login $cred.UserName -TargetHost $target)
                $variants = @($variants | Where-Object { $_ -and $_.ToLower() -ne ("$($cred.UserName)").ToLower() } | Select-Object -Unique)
                foreach ($v in $variants) {
                    $triedVariants += $v
                    try {
                        $c2 = New-Object System.Management.Automation.PSCredential($v, $pwd)
                        $info = Get-ADDomain -Server $target -Credential $c2 -ErrorAction Stop
                        $cred = $c2; $userLabel = $v
                        Add-SwitchLog @("  ${v}: OK")
                        break
                    } catch {
                        $bindResults += "$v — $($_.Exception.Message)"
                        Add-SwitchLog @("  ${v}: $($_.Exception.Message)")
                    }
                }
            }
            if (-not $info) { throw $firstErr }
        }
    }
    catch {
        $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow
        $msg = (((L "Access error: failed to connect to domain `"{0}`" ") -f ($target)) +
                ((L "with the current account ({0}).`n`n") -f ($userLabel)) +
                ((L "Insufficient rights or the domain is unavailable:`n{0}") -f ($_.Exception.Message)))
        if ($bindResults.Count -gt 1) {
            $msg += ((L "`n`nBind attempts (variant — server reply):`n{0}") -f (($bindResults | ForEach-Object { "  $_" }) -join "`n"))
        }
        if ($triedVariants.Count -gt 0) {
            $msg += ((L "`n`nThe account was also tried as {0} — not accepted. With a trust between the domains, check that its direction lets the target domain authenticate this account and, with selective authentication, that `"Allowed to authenticate`" is granted on its domain controllers. For a domain in another forest without a trust choose `"Another account`" and enter a login of that domain.") -f ($triedVariants -join ', '))
        }
        $msg += ((L "`nThe same details are appended to {0}.") -f (Get-SwitchLogPath))
        Show-Error $msg
        return
    }
    finally { $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow }

    # Update the active connection (the chosen account becomes the session account)
    $Global:ADConnection.Server     = $target
    $Global:ADConnection.BaseDN     = $info.DistinguishedName
    $Global:ADConnection.DnsRoot    = $info.DNSRoot
    $Global:ADConnection.NetBIOSName = $info.NetBIOSName
    $Global:ADConnection.Credential = $cred
    $Global:ADConnection.UserName   = $userLabel
    $Script:DcHostList = $null
    $Global:AccessGroupsResolved = $false
    $Global:AccessGroupsDN       = $null

    Add-SavedDomain -Server $target -Username $Global:ADConnection.UserName | Out-Null

    $LblConn.Text = ((L "Connected to: {0}   |   ") -f ($Global:ADConnection.Server)) +
                    ((L "User: {0}") -f ($Global:ADConnection.UserName))
    Update-DomainCombo
    $pending = $Script:PendingSelectDn
    $Script:PendingSelectDn = $null
    if (-not $pending) { $TxtSearch.Text = "" }
    $PanelProps.Children.Clear()
    Load-OUTree
    if ($pending) {
        Invoke-Search
        foreach ($row in @($GridUsers.ItemsSource)) {
            if (([string]$row.DistinguishedName).ToLower() -eq $pending.ToLower()) {
                $GridUsers.SelectedItem = $row; $GridUsers.ScrollIntoView($row); break
            }
        }
    }
    Show-Info ((L "Connected to domain `"{0}`" as {1}.") -f ($Global:ADConnection.Server), ($Global:ADConnection.UserName))
})

# --- Event handlers ---
$BtnSearch.Add_Click({ Invoke-Search })
$TxtSearch.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-Search } })
$BtnRefresh.Add_Click({ Invoke-Search })
$ChkSubtree.Add_Click({ Invoke-Search })
$ChkAllDomains.Add_Click({ Set-GridColumns; Invoke-Search })
$TreeOU.Add_SelectedItemChanged({ Invoke-Search })

$GridUsers.Add_SelectionChanged({
    if ($GridUsers.SelectedItems.Count -gt 1) {
        $PanelProps.Children.Clear()
        $Script:PropRows = @()
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = if ((Get-CurrentMode) -eq 'groups') {
            ((L "Selected objects: {0}`r`n`r`nAvailable bulk actions:`r`nMove (OU) / Delete") -f ($GridUsers.SelectedItems.Count))
        } else {
            ((L "Selected objects: {0}`r`n`r`nAvailable bulk actions:`r`nEnable / Disable / Move (OU)`r`nAdd to groups (users)") -f ($GridUsers.SelectedItems.Count))
        }
        $tb.TextWrapping = 'Wrap'
        $PanelProps.Children.Add($tb) | Out-Null
    } else {
        Update-PropsPanel $GridUsers.SelectedItem
    }
})
# Ctrl+C on the list copies the selected row (name, login, e-mail, state) tab-separated
$GridUsers.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq 'C' -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $items = @($GridUsers.SelectedItems)
        if ($items.Count -gt 0) {
            $lines = foreach ($u in $items) {
                if ($u._IsComputer) {
                    @([string]$u.Name, [string]$u.DnsHostName, [string]$u.OS, [string]$u.Description, [string]$u.State) -join "`t"
                } else {
                    @([string]$u.Name, [string]$u.SamAccountName, [string]$u.Mail, [string]$u.Description, [string]$u.State) -join "`t"
                }
            }
            Set-ClipboardText ($lines -join "`r`n")
        }
        $e.Handled = $true
    }
})

$BtnCreate.Add_Click({
    $defOu = $null
    $selNode = $TreeOU.SelectedItem
    if ($selNode -and $selNode.Tag) { $defOu = [string]$selNode.Tag }
    if (Show-CreateUserDialog -Owner $MainWin -DefaultOU $defOu) {
        Show-Info (L "User created.")
        Invoke-Search
    }
})

# Apply an account operation to every selected object; show an error summary
function Invoke-BulkAccountAction {
    param($Items, [scriptblock]$Action, [string]$DoneMsg)
    $errors = @()
    foreach ($o in $Items) {
        try { & $Action $o } catch { $errors += "$($o.Name): $($_.Exception.Message)" }
    }
    $ok = $Items.Count - $errors.Count
    if ($errors.Count -gt 0) {
        $txt = ($errors | Select-Object -First 10) -join "`r`n"
        if ($errors.Count -gt 10) { $txt += "`r`n..." }
        Show-Error ((L "{0}: {1} of {2}.`r`n`r`nErrors:`r`n{3}") -f (${DoneMsg}), ($ok), ($Items.Count), ($txt)) (L "Partially completed")
    } else {
        Show-Info "${DoneMsg}: $ok."
    }
    Invoke-Search
}

$BtnEnable.Add_Click({
    $items = Get-SelectedUsers; if (-not $items -or $items.Count -eq 0) { return }
    if ($items.Count -eq 1) {
        try {
            $p = Get-ADParams
            Enable-ADAccount @p -Identity $items[0].DistinguishedName
            Add-HistoryEntry -Action 'enable' -Dn $items[0].DistinguishedName
            Show-Info (L "Account enabled.")
            Invoke-Search
        } catch { Show-Error ((L "Failed to enable: {0}") -f ($_.Exception.Message)) }
        return
    }
    if (-not (Confirm-Action ((L "Enable {0} accounts?") -f ($items.Count)))) { return }
    Invoke-BulkAccountAction $items { param($o) $p = Get-ADParams; Enable-ADAccount @p -Identity $o.DistinguishedName; Add-HistoryEntry -Action 'enable' -Dn $o.DistinguishedName } (L "Enabled")
})

$BtnDisable.Add_Click({
    $items = Get-SelectedUsers; if (-not $items -or $items.Count -eq 0) { return }
    if ($items.Count -eq 1) {
        $u = $items[0]
        if (-not (Confirm-Action ((L "Disable account '{0}'?") -f ($u.SamAccountName)))) { return }
        try {
            $p = Get-ADParams
            Disable-ADAccount @p -Identity $u.DistinguishedName
            Add-HistoryEntry -Action 'disable' -Dn $u.DistinguishedName
            Show-Info (L "Account disabled.")
            Invoke-Search
        } catch { Show-Error ((L "Failed to disable: {0}") -f ($_.Exception.Message)) }
        return
    }
    if (-not (Confirm-Action ((L "Disable {0} accounts?") -f ($items.Count)))) { return }
    Invoke-BulkAccountAction $items { param($o) $p = Get-ADParams; Disable-ADAccount @p -Identity $o.DistinguishedName; Add-HistoryEntry -Action 'disable' -Dn $o.DistinguishedName } (L "Disabled")
})

$BtnUnlock.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    try {
        $p = Get-ADParams
        Unlock-ADAccount @p -Identity $u.DistinguishedName
        Add-HistoryEntry -Action 'unlock' -Dn $u.DistinguishedName
        Show-Info (L "Account unlocked.")
        Invoke-Search
    } catch { Show-Error ((L "Failed to unlock: {0}") -f ($_.Exception.Message)) }
})

$BtnResetPwd.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-ResetPasswordDialog -Owner $MainWin -User $u) {
        Show-Info (L "Password reset.")
        Refresh-SelectedUser $u.DistinguishedName
    }
})

$BtnPwdNoExpire.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if ($u._IsComputer) { return }
    $cur = [bool]$u._AD.PasswordNeverExpires
    $new = -not $cur
    # PasswordLastSet = $null means 'must change password at next logon'
    $mustChange = ($new -and -not $u._AD.PasswordLastSet)
    $until = $null
    if ($new) {
        $choice = Show-NeverExpiresUntilDialog -Owner $MainWin -Login $u.SamAccountName -MustChange:$mustChange
        if (-not $choice) { return }
        $until = $choice.Until
    } else {
        $msg = ((L "Clear the 'password never expires' flag for '{0}'?`r`n`r`nThe password will expire per the domain policy.") -f ($u.SamAccountName))
        if (-not (Confirm-Action $msg)) { return }
    }
    try {
        $p = Get-ADParams
        $attr = $Global:PwdNeverExpiresUntilAttr
        if ($new) {
            $extra = @{}
            # Like ADUC: enabling the flag also cancels the pending change
            # requirement, so the current password stays valid.
            if ($mustChange) { $extra['ChangePasswordAtLogon'] = $false }
            if ($until) { $extra['Replace'] = @{ $attr = $until.ToString('yyyy-MM-dd') } }
            elseif (Get-PwdNeverExpiresUntil $u._AD) { $extra['Clear'] = $attr }
            Set-ADUser @p -Identity $u.DistinguishedName -PasswordNeverExpires $true @extra
            Add-HistoryEntry -Action 'pwd_never_expires_on' -Dn $u.DistinguishedName -Details $(if ($until) { $until.ToString('yyyy-MM-dd') } else { '' })
            $txt = (L "Flag set: the password never expires.")
            if ($mustChange) { $txt += (L "`r`n`r`nThe 'change password at next logon' requirement was removed; the current password stays valid.") }
            if ($until) { $txt += ((L "`r`n`r`nThe flag will be cleared automatically on {0}.") -f (Format-AdDate $until)) }
            Show-Info $txt
        } else {
            $extra = @{}
            if (Get-PwdNeverExpiresUntil $u._AD) { $extra['Clear'] = $attr }
            Set-ADUser @p -Identity $u.DistinguishedName -PasswordNeverExpires $false @extra
            Add-HistoryEntry -Action 'pwd_never_expires_off' -Dn $u.DistinguishedName
            Show-Info (L "Flag cleared: the password expires per the domain policy.")
        }
        Invoke-Search
    } catch { Show-Error ((L "Failed to change the flag: {0}") -f ($_.Exception.Message)) }
})

$BtnGroups.Add_Click({
    $items = @((Get-SelectedUsers) | Where-Object { -not $_._IsComputer })
    if (-not $items -or $items.Count -eq 0) { return }
    if ($items.Count -eq 1) {
        Show-GroupsDialog -Owner $MainWin -User $items[0]
        return
    }
    # Bulk: add all selected users to the chosen groups
    $picked = @(Show-GroupPickerDialog -Owner $MainWin)
    if (-not $picked -or $picked.Count -eq 0) { return }
    if (-not (Confirm-Action ((L "Add {0} users to {1} group(s)?") -f ($items.Count), ($picked.Count)))) { return }
    $added = 0; $errors = @()
    foreach ($gdn in $picked) {
        foreach ($u in $items) {
            try {
                $p = Get-ADParams
                Add-ADGroupMember @p -Identity $gdn -Members $u.DistinguishedName
                Add-HistoryEntry -Action 'group_add' -Dn $u.DistinguishedName -Details (Get-DnLeaf $gdn)
                $added++
            } catch {
                $gcn = ($gdn -split ',')[0] -replace '^CN=',''
                $errors += "$($u.SamAccountName) -> ${gcn}: $($_.Exception.Message)"
            }
        }
    }
    $summary = ((L "Added: {0}.") -f ($added))
    if ($errors.Count -gt 0) {
        $txt = ($errors | Select-Object -First 10) -join "`r`n"
        if ($errors.Count -gt 10) { $txt += "`r`n..." }
        Show-Error ((L "{0}`r`n`r`nErrors:`r`n{1}") -f ($summary), ($txt)) (L "Partially completed")
    } else {
        Show-Info $summary
    }
})

$BtnMove.Add_Click({
    $items = Get-SelectedUsers; if (-not $items -or $items.Count -eq 0) { return }
    if (Show-MoveDialog -Owner $MainWin -Users $items) {
        if ($items.Count -eq 1) { Show-Info (L "Object moved.") }
        elseif ($script:MoveErrors.Count -eq 0) { Show-Info ((L "Objects moved: {0}.") -f ($items.Count)) }
        Invoke-Search
    }
})

$BtnEdit.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if ($u._IsGroup) {
        if (Show-GroupEditDialog -Owner $MainWin -Group $u) {
            Show-Info (L "Changes saved.")
            Invoke-Search
        }
    }
    elseif ($u._IsComputer) {
        if (Show-ComputerEditDialog -Owner $MainWin -Comp $u) {
            Show-Info (L "Changes saved.")
            Invoke-Search
        }
    }
    elseif (Show-EditDialog -Owner $MainWin -User $u) {
        Show-Info (L "Changes saved.")
        Invoke-Search
    }
})

$BtnCreateGroup.Add_Click({
    $base = $null
    $sel = $TreeOU.SelectedItem
    if ($sel -and $sel.Tag) { $base = [string]$sel.Tag }
    if (Show-GroupCreateDialog -Owner $MainWin -DefaultOU $base) {
        Show-Info (L "Group created.")
        Invoke-Search
    }
})

$BtnMembers.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (-not $u._IsGroup) { return }
    Show-GroupMembersDialog -Owner $MainWin -Group $u
    Invoke-Search
})

# Double-click on a grid row opens the edit dialog (users and computers)
$GridUsers.Add_MouseDoubleClick({
    param($s, $e)
    # Only react to double-clicks on an actual row (not the header)
    $dep = $e.OriginalSource
    $isRow = $false
    try {
        while ($dep) {
            if ($dep -is [System.Windows.Controls.DataGridRow]) { $isRow = $true; break }
            if ($dep -is [System.Windows.Media.Visual] -or
                $dep -is [System.Windows.Media.Media3D.Visual3D]) {
                $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
            } else {
                $dep = [System.Windows.LogicalTreeHelper]::GetParent($dep)
            }
        }
    } catch { $isRow = [bool]$GridUsers.SelectedItem }
    if ($isRow -and $GridUsers.SelectedItem) {
        if ($GridUsers.SelectedItem._IsGroup) {
            # Double-click on a group opens its member list
            $BtnMembers.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        } else {
            $BtnEdit.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
    }
})

$BtnRename.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-RenameDialog -Owner $MainWin -Obj $u) {
        Show-Info (L "Object renamed.")
        Invoke-Search
    }
})

$BtnDelete.Add_Click({
    # Groups mode: allow deleting several selected groups at once
    if ((Get-CurrentMode) -eq 'groups' -and $GridUsers.SelectedItems.Count -gt 1) {
        $items = @($GridUsers.SelectedItems)
        if (-not (Confirm-Action ((L "Delete {0} groups?`r`n`r`nThis operation is irreversible.") -f ($items.Count)))) { return }
        $errors = @()
        foreach ($g in $items) {
            try {
                $p = Get-ADParams
                Remove-ADObject @p -Identity $g.DistinguishedName -Confirm:$false
                Add-HistoryEntry -Action 'delete' -Dn $g.DistinguishedName
            } catch { $errors += "$($g.Name): $($_.Exception.Message)" }
        }
        $PanelProps.Children.Clear(); $Script:PropRows = @()
        Invoke-Search
        if ($errors.Count -gt 0) {
            Show-Error (((L "Deleted: {0}.") -f ($items.Count - $errors.Count)) + "`r`n`r`n" + (($errors | Select-Object -First 10) -join "`r`n")) (L "Partially completed")
        } else {
            Show-Info ((L "Deleted: {0}.") -f ($items.Count))
        }
        return
    }
    $u = Get-SelectedUser; if (-not $u) { return }
    $label = if ($u.Name) { $u.Name } else { $u.SamAccountName }
    if (-not (Confirm-Action ((L "Delete object '{0}'?`r`n`r`nThis operation is irreversible.") -f ($label)))) { return }
    try {
        $p = Get-ADParams
        Remove-ADObject @p -Identity $u.DistinguishedName -Confirm:$false
        Add-HistoryEntry -Action 'delete' -Dn $u.DistinguishedName
        Show-Info (L "Object deleted.")
        $PanelProps.Children.Clear()
        $Script:PropRows = @()
        Invoke-Search
    } catch { Show-Error ((L "Failed to delete: {0}") -f ($_.Exception.Message)) }
})

# Object type switch
$RbUsers.Add_Checked({ if ($GridUsers) { Switch-Mode } })
$RbComputers.Add_Checked({ if ($GridUsers) { Switch-Mode } })
if ($RbGroups) { $RbGroups.Add_Checked({ if ($GridUsers) { Switch-Mode } }) }

# --- Context menu of the user list ---
$cmGrid = $GridUsers.ContextMenu
# Find a context-menu item by name (FindName on a ContextMenu does not
# work: the menu has its own name scope outside the window's tree)
function Get-CmItem {
    param([string]$Name)
    if (-not $cmGrid) { return $null }
    foreach ($it in $cmGrid.Items) {
        if ($it -is [System.Windows.Controls.MenuItem] -and $it.Name -eq $Name) { return $it }
    }
    return $null
}

# --- Re-apply all main-window texts in the current language ---
function Apply-MainLanguage {
    $MainWin.Title = (L 'ADUC-Ext — Active Directory user management')
    if ($LblSearchCap) { $LblSearchCap.Text = (L 'Search:') }
    if ($LblDomainCap) { $LblDomainCap.Text = (L 'Domain:') }
    if ($LblShowCap)   { $LblShowCap.Text   = (L 'Show:') }
    if ($LblOuCap)     { $LblOuCap.Text     = (L 'Organizational units') }
    $TxtSearch.ToolTip = (L 'Name, login (sAMAccountName), e-mail, or part of a value')
    $CmbDomain.ToolTip = (L 'Select a saved domain or enter a controller/domain name')
    $BtnSearch.Content = (L 'Find')
    $BtnRefresh.Content = (L 'Refresh')
    $BtnCreate.Content = (L 'Create user')
    if ($BtnHistory) { $BtnHistory.Content = (L 'History...') }
    if ($BtnPwdGen) { $BtnPwdGen.Content = (L 'Password...') }
    $BtnSwitchDomain.Content = (L 'Switch domain')
    $BtnEnable.Content = (L 'Enable')
    $BtnDisable.Content = (L 'Disable')
    $BtnUnlock.Content = (L 'Unlock')
    $BtnResetPwd.Content = (L 'Reset password')
    $BtnPwdNoExpire.Content = (L 'Pwd never expires')
    $BtnPwdNoExpire.ToolTip = (L "Set or clear the 'password never expires' flag")
    $BtnGroups.Content = (L 'Groups...')
    $BtnMove.Content = (L 'Move (OU)')
    $BtnEdit.Content = (L 'Edit...')
    $BtnRename.Content = (L 'Rename...')
    $BtnDelete.Content = (L 'Delete')
    $RbUsers.Content = (L 'Users')
    $RbComputers.Content = (L 'Computers')
    if ($RbGroups) { $RbGroups.Content = (L 'Groups') }
    if ($BtnCreateGroup) { $BtnCreateGroup.Content = (L 'Create group...') }
    if ($BtnMembers) { $BtnMembers.Content = (L 'Members...') }
    $ChkSubtree.Content = (L 'Nested OUs')
    if ($ChkAllDomains) { $ChkAllDomains.Content = (L 'All saved domains') }
    $ChkSubtree.ToolTip = (L 'Show objects from nested organizational units')
    if ($GrpActions) { $GrpActions.Header = (L 'Actions') }
    $computers = [bool]$RbComputers.IsChecked
    $GrpProps.Header = if ($computers) { (L 'Computer properties') } else { (L 'User properties') }
    foreach ($pair in @(
        @('CmCopyLogin',  'Copy login'),
        @('CmCopyName',   'Copy display name'),
        @('CmCopyMail',   'Copy e-mail'),
        @('CmCopyUpn',    'Copy UPN'),
        @('CmCopyDn',     'Copy DN'),
        @('CmCopyAll',    'Copy all properties'),
        @('CmEnable',     'Enable'),
        @('CmDisable',    'Disable'),
        @('CmUnlock',     'Unlock'),
        @('CmResetPwd',   'Reset password...'),
        @('CmPwdNoExpire','Password never expires'),
        @('CmGroups',     'Groups...'),
        @('CmMove',       'Move (OU)...'),
        @('CmEdit',       'Edit...'),
        @('CmHistory',    'Object history...'),
        @('CmMembers',    'Members...'),
        @('CmRename',     'Rename...'),
        @('CmDelete',     'Delete'))) {
        $mi = Get-CmItem $pair[0]
        if ($mi) { $mi.Header = (L $pair[1]) }
    }
    Set-GridColumns -Computers:$computers
    Invoke-Search
    $LblConn.Text = ((L "Connected to: {0}   |   User: {1}") -f ($Global:ADConnection.Server), ($Global:ADConnection.UserName))
    Update-PropsPanel $GridUsers.SelectedItem
}

# --- Interface language switcher ---
if ($CmbLang) {
    [void]$CmbLang.Items.Add('EN'); [void]$CmbLang.Items.Add('RU')
    $CmbLang.SelectedItem = if ($Script:Lang -eq 'ru') { 'RU' } else { 'EN' }
    $CmbLang.Add_SelectionChanged({
        $new = if ($CmbLang.SelectedItem -eq 'RU') { 'ru' } else { 'en' }
        if ($new -ne $Script:Lang) {
            $Script:Lang = $new
            Set-AppLang $new
            Set-UiCulture
            Apply-MainLanguage
        }
    })
}

# Select the row under the cursor on right-click so the menu applies to it
$GridUsers.Add_PreviewMouseRightButtonDown({
    param($s, $e)
    $dep = $e.OriginalSource
    while ($dep -and -not ($dep -is [System.Windows.Controls.DataGridRow])) {
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($dep) { $dep.IsSelected = $true }
})
# Enable/disable "copy" items depending on available data
$cmGrid.Add_Opened({
    $u = $GridUsers.SelectedItem
    $has = [bool]$u
    $multi = ($GridUsers.SelectedItems.Count -gt 1)
    if ($multi) {
        $mode = Get-CurrentMode
        # Multi-selection: only bulk actions apply
        foreach ($n in 'CmCopyLogin','CmCopyName','CmCopyMail','CmCopyUpn','CmCopyDn','CmCopyAll','CmUnlock','CmResetPwd','CmPwdNoExpire','CmGroups','CmMembers','CmEdit','CmRename','CmDelete') {
            $mi = Get-CmItem($n); if ($mi) { $mi.IsEnabled = $false }
        }
        foreach ($n in 'CmEnable','CmDisable','CmMove') {
            $mi = Get-CmItem($n); if ($mi) { $mi.IsEnabled = ($mode -ne 'groups') }
        }
        $mi = Get-CmItem('CmMove'); if ($mi) { $mi.IsEnabled = $true }
        # Groups mode: bulk delete of the selected groups
        $mi = Get-CmItem('CmDelete'); if ($mi) { $mi.IsEnabled = ($mode -eq 'groups') }
        # Bulk add-to-groups is available for users only
        $mi = Get-CmItem('CmGroups')
        if ($mi) { $mi.IsEnabled = ($mode -eq 'users') }
        $mi = Get-CmItem('CmPwdNoExpire'); if ($mi) { $mi.IsChecked = $false }
        return
    }
    foreach ($n in 'CmCopyLogin','CmCopyName','CmCopyDn','CmCopyAll','CmEnable','CmDisable','CmUnlock','CmResetPwd','CmPwdNoExpire','CmGroups','CmMembers','CmMove','CmEdit','CmRename','CmDelete') {
        $mi = Get-CmItem($n); if ($mi) { $mi.IsEnabled = $has }
    }
    $mi = Get-CmItem('CmCopyMail'); if ($mi) { $mi.IsEnabled = ($has -and -not [string]::IsNullOrEmpty([string]$u.Mail)) }
    $mi = Get-CmItem('CmCopyUpn');  if ($mi) { $mi.IsEnabled = ($has -and -not [string]::IsNullOrEmpty([string]$u._AD.UserPrincipalName)) }
    # Reflect the current flag state on the checkable item
    $mi = Get-CmItem('CmPwdNoExpire')
    if ($mi) { $mi.IsChecked = ($has -and -not $u._IsComputer -and [bool]$u._AD.PasswordNeverExpires) }
})
$mi = Get-CmItem 'CmCopyLogin'; if ($mi) { $mi.Add_Click({ $u=$GridUsers.SelectedItem; if($u){ Set-ClipboardText ([string]$u.SamAccountName) } }) }
$mi = Get-CmItem 'CmCopyName'; if ($mi) { $mi.Add_Click( { $u=$GridUsers.SelectedItem; if($u){ Set-ClipboardText ([string]$u.Name) } }) }
$mi = Get-CmItem 'CmCopyMail'; if ($mi) { $mi.Add_Click( { $u=$GridUsers.SelectedItem; if($u){ Set-ClipboardText ([string]$u.Mail) } }) }
$mi = Get-CmItem 'CmCopyUpn'; if ($mi) { $mi.Add_Click(  { $u=$GridUsers.SelectedItem; if($u){ Set-ClipboardText ([string]$u._AD.UserPrincipalName) } }) }
$mi = Get-CmItem 'CmCopyDn'; if ($mi) { $mi.Add_Click(   { $u=$GridUsers.SelectedItem; if($u){ Set-ClipboardText ([string]$u.DistinguishedName) } }) }
$mi = Get-CmItem 'CmHistory'; if ($mi) { $mi.Add_Click( { $sel = $GridUsers.SelectedItem; if ($sel) { Show-HistoryDialog -Owner $MainWin -Obj $sel } else { Show-HistoryDialog -Owner $MainWin } }) }
$mi = Get-CmItem 'CmCopyAll'; if ($mi) { $mi.Add_Click(  { if ($Script:PropRows) { Set-ClipboardText ($Script:PropRows -join "`r`n") } }) }
$mi = Get-CmItem 'CmEnable'; if ($mi) { $mi.Add_Click(   { $BtnEnable.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmDisable'; if ($mi) { $mi.Add_Click(  { $BtnDisable.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmUnlock'; if ($mi) { $mi.Add_Click(   { $BtnUnlock.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmResetPwd'; if ($mi) { $mi.Add_Click( { $BtnResetPwd.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmPwdNoExpire'; if ($mi) { $mi.Add_Click({ $BtnPwdNoExpire.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmGroups'; if ($mi) { $mi.Add_Click(   { $BtnGroups.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmMove'; if ($mi) { $mi.Add_Click(     { $BtnMove.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmEdit'; if ($mi) { $mi.Add_Click(     { $BtnEdit.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmMembers'; if ($mi) { $mi.Add_Click( { $BtnMembers.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmRename'; if ($mi) { $mi.Add_Click(   { $BtnRename.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmDelete'; if ($mi) { $mi.Add_Click(   { $BtnDelete.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
# Initial load: OU tree (selecting the root triggers the search)
$MainWin.Add_ContentRendered({ Load-OUTree; Start-NeverExpiresSweep })

# Show the main window
$MainWin.ShowDialog() | Out-Null

#endregion
