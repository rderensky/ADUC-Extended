# ADUC-Extended v1.0.0

GUI application for managing Active Directory accounts / Графическое приложение
для управления учётными записями Active Directory.

Each asset below contains **both English and Russian** versions and READMEs in
both languages. / Каждый архив содержит **английскую и русскую** версии и README
на двух языках.

## Downloads / Загрузки

| Platform / Платформа | Asset / Архив |
|---|---|
| Windows (PowerShell + WPF) | `ADUC-Ext-1.0.0-windows.zip` |
| macOS (Python + Tkinter)   | `ADUC-Ext-1.0.0-macos.zip` |

### Windows package contents / Состав архива Windows
- `ADUC-Ext.ps1` — English version
- `ADUC-Ext-ru.ps1` — русская версия
- `build_exe.ps1`, `build_exe_ru.ps1` — build to .exe / сборка в .exe
- `aduc_ext.ico` — icon / иконка
- `README.md`, `README_ru.md`

### macOS package contents / Состав архива macOS
- `aduc_ext.py` — English version
- `aduc_ext_ru.py` — русская версия
- `build_app.sh`, `build_app_ru.sh` — build to .app / сборка в .app
- `aduc_ext.icns` — icon / иконка
- `README.md`, `README_ru.md`

## Quick start / Быстрый старт

**Windows**
```powershell
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext.ps1      # English
powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext-ru.ps1   # Русский
```

**macOS**
```bash
python3 aduc_ext.py      # English
python3 aduc_ext_ru.py   # Русский
```

## Requirements / Требования
- Windows: PowerShell 5.1 + модуль ActiveDirectory (RSAT); приложение предложит
  установку RSAT при отсутствии.
- macOS: Python 3.8+ c Tkinter; пакет `ldap3` ставится автоматически.

## SHA-256
```
cef6255b13c08eb6457d8158574b65dc8c02aa599d3a2f7cbf8d1cad0d3b69c1  ADUC-Ext-1.0.0-windows.zip
b003e6ad019b28538ffd981fb7bd788b59833bb03a1ed60adace5c9f99bf0c2c  ADUC-Ext-1.0.0-macos.zip
```
