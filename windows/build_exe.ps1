<#
    build_exe.ps1 — build ADUC-Ext.exe from ADUC-Ext.ps1 using PS2EXE.
    Run on Windows (Windows PowerShell 5.1).

    Usage:
        powershell.exe -ExecutionPolicy Bypass -File .\build_exe.ps1
#>
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$src = Join-Path $PSScriptRoot 'ADUC-Ext.ps1'
$out = Join-Path $PSScriptRoot 'ADUC-Ext.exe'
if (-not (Test-Path $src)) { Write-Host "ADUC-Ext.ps1 not found"; exit 1 }

# TLS 1.2 — to reach the PowerShell Gallery on older systems
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# NuGet provider (required for Install-Module)
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing the NuGet provider..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
}

# PS2EXE module
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing the ps2exe module..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

Write-Host "Compiling ADUC-Ext.exe..."
$params = @{
    inputFile   = $src
    outputFile  = $out
    noConsole   = $true          # GUI application: hide the console window
    STA         = $true          # required for WPF
    title       = 'ADUC-Ext'
    description = 'Active Directory user management'
    product     = 'ADUC-Ext'
    version     = '1.2.1'
    # requireAdmin = $true       # uncomment if RSAT installation from the app is needed
}

# Application icon
$icon = Join-Path $PSScriptRoot 'aduc_ext.ico'
if (Test-Path $icon) { $params['iconFile'] = $icon }

Invoke-ps2exe @params

if (Test-Path $out) {
    Write-Host ""
    Write-Host "Done: $out"
} else {
    Write-Host "Build failed."
    exit 1
}
