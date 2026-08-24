# ADUC-Extended v1.2.1

## Что нового

- **Горячие клавиши редактирования** во всех полях ввода:
  - macOS: Cmd+Backspace удаляет строку (до её начала), Ctrl+Backspace —
    одно слово;
  - Windows: Shift+Backspace удаляет строку, Ctrl+Backspace — одно слово;
    в поле пароля Shift+Backspace очищает его целиком.
- **Esc закрывает активное модальное окно** (как «Отмена»); главное окно
  по Esc не закрывается.

## Загрузки

Каждое приложение содержит **английский и русский** языки; переключение —
внутри приложения.

| Платформа | Исходники | Бинарники |
|---|---|---|
| Windows | `ADUC-Ext-1.2.1-windows.zip` | `ADUC-Ext-1.2.1-win-exe.zip` |
| macOS   | `ADUC-Ext-1.2.1-macos.zip`   | `ADUC-Ext-1.2.1-mac-app.zip` |

## Требования
- Windows: PowerShell 5.1 + модуль ActiveDirectory (RSAT); при отсутствии
  приложение предложит установить RSAT.
- macOS: Python 3.8+ с Tkinter; `ldap3` ставится автоматически.

## SHA-256 (архивы исходников)
```
70b86bd07c660dfabfb6840ffeb06d4bc01770738811776153baeae92433a425  ADUC-Ext-1.2.1-windows.zip
af5dcb6de556e80d313e07b13c9876de2ce580a87fe4a4ac109d573fde6710ed  ADUC-Ext-1.2.1-macos.zip
```
