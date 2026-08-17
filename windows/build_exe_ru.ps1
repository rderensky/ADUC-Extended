<#
    build_exe_ru.ps1 — сборка ADUC-Ext-ru.exe из ADUC-Ext-ru.ps1 через PS2EXE.
    Запускать на Windows (Windows PowerShell 5.1).

    Использование:
        powershell.exe -ExecutionPolicy Bypass -File .\build_exe_ru.ps1
#>
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$src = Join-Path $PSScriptRoot 'ADUC-Ext-ru.ps1'
$out = Join-Path $PSScriptRoot 'ADUC-Ext-ru.exe'
if (-not (Test-Path $src)) { Write-Host "Не найден ADUC-Ext-ru.ps1"; exit 1 }

# TLS 1.2 — для доступа к PowerShell Gallery на старых системах
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Провайдер NuGet (нужен для Install-Module)
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Устанавливаю провайдер NuGet..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
}

# Модуль PS2EXE
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Устанавливаю модуль ps2exe..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

Write-Host "Компилирую ADUC-Ext-ru.exe..."
$params = @{
    inputFile   = $src
    outputFile  = $out
    noConsole   = $true          # GUI-приложение: не показывать окно консоли
    STA         = $true          # обязательно для WPF
    title       = 'ADUC-Ext'
    description = 'Управление пользователями Active Directory'
    product     = 'ADUC-Ext'
    version     = '1.0.1'
    # requireAdmin = $true       # раскомментируйте, если нужна установка RSAT из приложения
}

# Иконка приложения
$icon = Join-Path $PSScriptRoot 'aduc_ext.ico'
if (Test-Path $icon) { $params['iconFile'] = $icon }

Invoke-ps2exe @params

if (Test-Path $out) {
    Write-Host ""
    Write-Host "Готово: $out"
} else {
    Write-Host "Сборка не удалась."
    exit 1
}
