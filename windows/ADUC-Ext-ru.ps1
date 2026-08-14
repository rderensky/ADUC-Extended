<#
.SYNOPSIS
    ADUC-Ext — управление учётными записями Active Directory (WPF).

.DESCRIPTION
    При запуске приложение запрашивает учётные данные и выполняет все операции
    с каталогом от имени указанной учётной записи.

    Возможности:
      - поиск и просмотр свойств пользователей;
      - навигация по подразделениям (OU);
      - создание учётных записей;
      - включение, отключение и разблокировка;
      - сброс пароля;
      - управление членством в группах;
      - перемещение между подразделениями;
      - изменение атрибутов.

.REQUIREMENTS
      - Windows с модулем ActiveDirectory (RSAT); при отсутствии приложение
        предложит установить его автоматически.
      - Учётная запись с правами на соответствующие операции в каталоге.
      - Windows PowerShell 5.1, запуск в STA-режиме.

.NOTES
    Запуск:
        powershell.exe -ExecutionPolicy Bypass -STA -File .\ADUC-Ext-ru.ps1
#>

#region ------------------------- Инициализация -------------------------------

# Загрузка сборок WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Русский язык для встроенных строк WPF (например, подсказка DatePicker),
# независимо от языка интерфейса ОС.
[System.Threading.Thread]::CurrentThread.CurrentUICulture =
    [System.Globalization.CultureInfo]::GetCultureInfo('ru-RU')

$ErrorActionPreference = 'Stop'

# Глобальное состояние подключения
$Global:ADConnection = [pscustomobject]@{
    Credential = $null   # [PSCredential]
    Server     = $null   # имя DC / домена
    UserName   = $null   # отображаемое имя подключённого пользователя
    BaseDN     = $null   # DistinguishedName домена (для дерева OU)
    DnsRoot    = $null   # DNS-имя домена
}

# Проверка наличия модуля ActiveDirectory (с попыткой авто-установки RSAT)
function Test-IsAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Install-RSAT {
    # Пытается установить RSAT: ActiveDirectory. Возвращает $true при успехе.
    # Windows 10/11 (клиент) — через Add-WindowsCapability
    try {
        $caps = Get-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools*' -ErrorAction Stop
        if ($caps) {
            foreach ($c in ($caps | Where-Object { $_.State -ne 'Installed' })) {
                Add-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null
            }
            if (Get-Module -ListAvailable -Name ActiveDirectory) { return $true }
        }
    } catch { }
    # Windows Server — через роль/фичу
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

    # Модуль не найден — предложить установку
    $ans = [System.Windows.MessageBox]::Show(
        "Модуль PowerShell 'ActiveDirectory' (RSAT) не установлен.`n`n" +
        "Установить его сейчас автоматически?`n" +
        "Потребуются права администратора и подключение к Windows Update. " +
        "Установка может занять несколько минут.",
        "Проверка зависимостей",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)

    if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
        [System.Windows.MessageBox]::Show(
            "Без модуля ActiveDirectory приложение работать не может.`n`n" +
            "Установите RSAT вручную (от администратора):`n" +
            "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
            "Отсутствует модуль ActiveDirectory",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
        return $false
    }

    if (-not (Test-IsAdmin)) {
        [System.Windows.MessageBox]::Show(
            "Для установки RSAT нужны права администратора.`n`n" +
            "Запустите приложение от имени администратора либо установите вручную:`n" +
            "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
            "Недостаточно прав",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return $false
    }

    if (Install-RSAT) {
        Import-Module ActiveDirectory -ErrorAction Stop
        Show-Info "Модуль ActiveDirectory (RSAT) успешно установлен."
        return $true
    }

    [System.Windows.MessageBox]::Show(
        "Не удалось установить RSAT автоматически.`n`n" +
        "Установите вручную (от администратора):`n" +
        "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`n`n" +
        "На Windows Server:`n" +
        "  Install-WindowsFeature RSAT-AD-PowerShell",
        "Ошибка установки RSAT",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
    return $false
}

# Единая обёртка для сообщений об ошибках
function Show-Error {
    param([string]$Message, [string]$Title = "Ошибка")
    [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
}

function Show-Info {
    param([string]$Message, [string]$Title = "Информация")
    [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information) | Out-Null
}

function Confirm-Action {
    param([string]$Message, [string]$Title = "Подтверждение")
    $r = [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    return ($r -eq [System.Windows.MessageBoxResult]::Yes)
}

# Общие параметры для всех вызовов AD-командлетов (credential + server)
function Get-ADParams {
    $p = @{ Credential = $Global:ADConnection.Credential }
    if ($Global:ADConnection.Server) { $p['Server'] = $Global:ADConnection.Server }
    return $p
}

# --- Выбор групп: имя подразделения и группы по умолчанию ---
# Имя OU, из которого выбираются группы. Пусто = все группы домена.
$Global:AccessGroupsOUName = ""
# Группы, автоматически добавляемые при создании пользователя. По умолчанию пусто.
$Global:DefaultCreateGroups = @()
$Global:AccessGroupsDN = $null
$Global:AccessGroupsResolved = $false

function Get-AccessGroupsDN {
    # DN подразделения из $Global:AccessGroupsOUName. $null, если имя не задано
    # или подразделение не найдено. Кэшируется до нового подключения.
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

# --- Хранение списка доменов (пароли НЕ сохраняются) ---
function Get-ConfigDir {
    $dir = Join-Path $env:APPDATA 'ADUC-Ext-ru'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-ConfigPath {
    return (Join-Path (Get-ConfigDir) 'domains.json')
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

#region -------------------- Окно ввода учётных данных -------------------------

[xml]$LoginXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Подключение к Active Directory"
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

        <TextBlock Grid.Row="0" Grid.ColumnSpan="2" Text="Введите учётные данные для подключения к домену"
                   TextWrapping="Wrap" Margin="0,0,0,15" FontWeight="SemiBold"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Сохранённый домен:" VerticalAlignment="Center"/>
        <DockPanel Grid.Row="1" Grid.Column="1" Margin="0,4">
            <Button DockPanel.Dock="Right" Name="BtnDelDomain" Content="✕" Width="28" Margin="4,0,0,0"
                    ToolTip="Удалить выбранный домен из списка"/>
            <ComboBox Name="CmbSaved" Padding="4"/>
        </DockPanel>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Домен / DC:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="TxtDomain" Margin="0,4" Padding="4"
                   ToolTip="Например: contoso.local или dc01.contoso.local (можно оставить пустым для текущего домена)"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Text="Пользователь:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="TxtUser" Margin="0,4" Padding="4"
                   ToolTip="Например: CONTOSO\admin или admin@contoso.local"/>

        <TextBlock Grid.Row="4" Grid.Column="0" Text="Пароль:" VerticalAlignment="Center"/>
        <PasswordBox Grid.Row="4" Grid.Column="1" Name="TxtPass" Margin="0,4" Padding="4"/>

        <CheckBox Grid.Row="5" Grid.Column="1" Name="ChkSave" Content="Сохранить домен в список"
                  IsChecked="True" Margin="0,8,0,0"/>

        <TextBlock Grid.Row="6" Grid.ColumnSpan="2" Name="LblStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,8,0,0"/>

        <StackPanel Grid.Row="8" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,15,0,0">
            <Button Name="BtnConnect" Content="Подключиться" Width="120" Height="32" Margin="0,0,10,0"
                    IsDefault="True"/>
            <Button Name="BtnCancel"  Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-LoginWindow {
    param(
        [object]$Owner,
        [string]$Preselect
    )
    $reader = New-Object System.Xml.XmlNodeReader $LoginXaml
    $win    = [Windows.Markup.XamlReader]::Load($reader)
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

    # Загрузка сохранённых доменов в выпадающий список
    $script:LoginDomains = @(Get-SavedDomains)
    $fillCombo = {
        $cmbSaved.Items.Clear()
        foreach ($d in $script:LoginDomains) { $cmbSaved.Items.Add($d.Name) | Out-Null }
    }
    & $fillCombo

    # Заполнение полей из выбранного профиля
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

    # Удаление домена из списка
    $btnDelDom.Add_Click({
        $name = $cmbSaved.SelectedItem
        if (-not $name) { return }
        $prof = $script:LoginDomains | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($prof -and (Confirm-Action "Удалить '$name' из списка доменов?")) {
            $script:LoginDomains = @(Remove-SavedDomain -Server $prof.Server)
            & $fillCombo
            $txtDomain.Clear(); $txtUser.Clear()
        }
    })

    # Предвыбор / предзаполнение
    if ($Preselect -and ($script:LoginDomains | Where-Object { $_.Name -eq $Preselect })) {
        $cmbSaved.SelectedItem = $Preselect
    }
    elseif (-not $txtDomain.Text -and $env:USERDNSDOMAIN) {
        $txtDomain.Text = $env:USERDNSDOMAIN
    }

    $script:LoginSuccess = $false

    $btnConn.Add_Click({
        $lblStatus.Text = "Проверка подключения..."
        $win.Dispatcher.Invoke([action]{}, "Render")

        $user = $txtUser.Text.Trim()
        $pass = $txtPass.Password

        if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
            $lblStatus.Text = "Укажите имя пользователя и пароль."
            return
        }

        try {
            $secPass = ConvertTo-SecureString $pass -AsPlainText -Force
            $cred    = New-Object System.Management.Automation.PSCredential($user, $secPass)
            $server  = $txtDomain.Text.Trim()

            $testParams = @{ Credential = $cred; ErrorAction = 'Stop' }
            if ($server) { $testParams['Server'] = $server }

            # Пробное обращение к AD для проверки учётных данных
            $domainInfo = Get-ADDomain @testParams

            $resolvedServer = if ($server) { $server } else { $domainInfo.DNSRoot }
            $Global:ADConnection.Credential = $cred
            $Global:ADConnection.Server     = $resolvedServer
            $Global:ADConnection.UserName   = $user
            $Global:ADConnection.BaseDN     = $domainInfo.DistinguishedName
            $Global:ADConnection.DnsRoot    = $domainInfo.DNSRoot
            # Сброс кэша OU групп доступа при новом подключении
            $Global:AccessGroupsResolved    = $false
            $Global:AccessGroupsDN          = $null

            # Сохранить домен в список
            if ($chkSave.IsChecked) {
                Add-SavedDomain -Server $resolvedServer -Username $user | Out-Null
            }

            $script:LoginSuccess = $true
            $win.Close()
        }
        catch {
            $lblStatus.Text = "Не удалось подключиться: $($_.Exception.Message)"
        }
    })

    $btnCancel.Add_Click({ $script:LoginSuccess = $false; $win.Close() })

    $win.ShowDialog() | Out-Null
    return $script:LoginSuccess
}

#endregion

#region ----------------------- Главное окно (XAML) ----------------------------

[xml]$MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ADUC-Ext — управление пользователями Active Directory"
        Height="640" Width="1180"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13">
    <DockPanel>
        <!-- Верхняя панель поиска -->
        <Border DockPanel.Dock="Top" Background="#F3F3F3" Padding="10">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="Домен:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox Name="CmbDomain" Width="170" VerticalAlignment="Center" IsEditable="True"
                              ToolTip="Выберите сохранённый домен или введите имя контроллера/домена"/>
                    <Button Name="BtnSwitchDomain" Content="Сменить домен" Width="130" Height="30" Margin="8,0,0,0"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Поиск:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBox Name="TxtSearch" Width="220" Padding="4" VerticalAlignment="Center"
                             ToolTip="Имя, логин (sAMAccountName), e-mail или часть значения"/>
                    <Button Name="BtnSearch" Content="Найти" Width="70" Height="30" Margin="8,0,0,0"/>
                    <Button Name="BtnRefresh" Content="Обновить" Width="80" Height="30" Margin="8,0,0,0"/>
                    <Button Name="BtnCreate" Content="Создать пользователя" Width="160" Height="30" Margin="12,0,0,0"/>
                    <CheckBox Name="ChkSubtree" Content="Вложенные OU" VerticalAlignment="Center"
                              Margin="12,0,0,0" ToolTip="Показывать пользователей из вложенных подразделений"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Нижняя строка состояния -->
        <Border DockPanel.Dock="Bottom" Background="#F3F3F3" Padding="8,4">
            <TextBlock Name="LblConn" Text="" Foreground="#333"/>
        </Border>

        <!-- Основная область: дерево OU | список пользователей | свойства/действия -->
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.3*"/>
                <ColumnDefinition Width="5" />
                <ColumnDefinition Width="2.4*"/>
                <ColumnDefinition Width="5" />
                <ColumnDefinition Width="1.5*"/>
            </Grid.ColumnDefinitions>

            <!-- Дерево подразделений (OU) -->
            <DockPanel Grid.Column="0" Margin="10">
                <TextBlock DockPanel.Dock="Top" Text="Подразделения" FontWeight="SemiBold"
                           Margin="0,0,0,4"/>
                <TreeView Name="TreeOU"/>
            </DockPanel>

            <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Stretch"
                          Background="#DDD"/>

            <DataGrid Name="GridUsers" Grid.Column="2" Margin="0,10"
                      AutoGenerateColumns="False" IsReadOnly="True"
                      SelectionMode="Single" HeadersVisibility="Column"
                      GridLinesVisibility="Horizontal" CanUserResizeRows="False">
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Имя" Binding="{Binding Name}" Width="1.6*"/>
                    <DataGridTextColumn Header="Логин" Binding="{Binding SamAccountName}" Width="1.2*"/>
                    <DataGridTextColumn Header="E-mail" Binding="{Binding Mail}" Width="1.6*"/>
                    <DataGridTextColumn Header="Состояние" Binding="{Binding State}" Width="1*"/>
                </DataGrid.Columns>
            </DataGrid>

            <GridSplitter Grid.Column="3" Width="5" HorizontalAlignment="Stretch"
                          Background="#DDD"/>

            <Grid Grid.Column="4" Margin="0,10,10,10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <GroupBox Grid.Row="0" Header="Свойства пользователя">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PanelProps" Margin="6">
                            <TextBlock Text="Выберите пользователя из списка" Foreground="#888"
                                       FontStyle="Italic"/>
                        </StackPanel>
                    </ScrollViewer>
                </GroupBox>

                <GroupBox Grid.Row="1" Header="Действия" Margin="0,10,0,0">
                    <WrapPanel Name="PanelActions" Margin="6">
                        <Button Name="BtnEnable"   Content="Включить"        Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnDisable"  Content="Отключить"       Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnUnlock"   Content="Разблокировать"  Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnResetPwd" Content="Сбросить пароль" Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnGroups"   Content="Группы..."       Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnMove"     Content="Переместить (OU)" Width="130" Height="32" Margin="4"/>
                        <Button Name="BtnEdit"     Content="Изменить..."     Width="130" Height="32" Margin="4"/>
                    </WrapPanel>
                </GroupBox>
            </Grid>
        </Grid>
    </DockPanel>
</Window>
"@

#endregion

#region --------------------- Вспомогательные функции AD -----------------------

# Свойства, запрашиваемые у пользователя
$Script:UserProps = @(
    'DisplayName','SamAccountName','UserPrincipalName','GivenName','Surname',
    'Mail','Enabled','LockedOut','Description','Title','Department','Company',
    'Office','TelephoneNumber','DistinguishedName','whenCreated',
    'PasswordLastSet','LastLogonDate','AccountExpirationDate',
    'PasswordNeverExpires','PasswordExpired','msDS-UserPasswordExpiryTimeComputed',
    'badPwdCount','LastBadPasswordAttempt'
)

function Get-UserState {
    param($u)
    if ($u.LockedOut)       { return "Заблокирован" }
    if (-not $u.Enabled)    { return "Отключён" }
    return "Активен"
}

function Search-ADUsers {
    param(
        [string]$Query,
        [string]$SearchBase,
        [string]$Scope = 'Subtree'   # Base | OneLevel | Subtree
    )
    $p = Get-ADParams
    $p['Properties'] = $Script:UserProps
    # ResultSetSize не задаём => модуль AD возвращает ВСЕ записи (с авто-пагинацией)
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
            State             = Get-UserState $_
            DistinguishedName = $_.DistinguishedName
            _AD               = $_
        }
    }
}

#endregion

#region ------------------------ Диалоги действий ------------------------------

# --- Создание пользователя ---
[xml]$CreateXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Создание пользователя" Height="760" Width="480"
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

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Имя:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="0" Grid.Column="1" Name="CGiven" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="Фамилия:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="1" Grid.Column="1" Name="CSur" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Отображаемое имя:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="CDisplay" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="Логин (sAM):" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="CSam" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="UPN-суффикс:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="4" Grid.Column="1" Name="CUpn" Margin="0,4" Padding="3"
                   ToolTip="Например: @contoso.local"/>
        <TextBlock Grid.Row="5" Grid.Column="0" Text="E-mail:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="5" Grid.Column="1" Name="CMail" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="6" Grid.Column="0" Text="Описание:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="6" Grid.Column="1" Name="CDesc" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="7" Grid.Column="0" Text="Пароль:" VerticalAlignment="Center"/>
        <PasswordBox Grid.Row="7" Grid.Column="1" Name="CPass" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="8" Grid.Column="0" Text="Подразделение (OU):" VerticalAlignment="Center"/>
        <DockPanel Grid.Row="8" Grid.Column="1" Margin="0,4">
            <Button DockPanel.Dock="Right" Name="CBrowseOu" Content="Обзор…" Width="70" Margin="6,0,0,0"/>
            <ComboBox Name="COu" Padding="3" IsEditable="True"
                      ToolTip="Подразделение, где будет создан пользователь"/>
        </DockPanel>
        <TextBlock Grid.Row="9" Grid.Column="0" Text="Срок действия:" VerticalAlignment="Center"/>
        <StackPanel Grid.Row="9" Grid.Column="1" Orientation="Horizontal" Margin="0,4">
            <CheckBox Name="CExpEnable" Content="Действует по (вкл.):" VerticalAlignment="Center"/>
            <DatePicker Name="CExpDate" Width="150" Margin="8,0,0,0" IsEnabled="False"
                        Language="ru-RU" SelectedDateFormat="Short"
                        ToolTip="Формат: ДД МММ ГГГГ"/>
        </StackPanel>

        <TextBlock Grid.Row="10" Grid.ColumnSpan="2" Text="Группы доступа при создании:"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="11" Grid.ColumnSpan="2" Name="CGroups" SelectionMode="Extended"/>
        <StackPanel Grid.Row="12" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="CPick" Content="Выбрать группы..." Width="150" Height="30"/>
            <Button Name="CUnpick" Content="Убрать выбранные" Width="160" Height="30" Margin="8,0,0,0"/>
        </StackPanel>

        <CheckBox  Grid.Row="13" Grid.Column="1" Name="CChangePwd" Content="Сменить пароль при следующем входе"
                   Margin="0,10,0,0" IsChecked="True"/>
        <CheckBox  Grid.Row="14" Grid.Column="1" Name="CEnabled" Content="Учётная запись включена"
                   Margin="0,6,0,0" IsChecked="True"/>

        <TextBlock Grid.Row="15" Grid.ColumnSpan="2" Name="CStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,8,0,0"/>
        <StackPanel Grid.Row="16" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="COk" Content="Создать" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="CCancel" Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-CreateUserDialog {
    param($Owner, $DefaultOU)
    $reader = New-Object System.Xml.XmlNodeReader $CreateXaml
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

    # Переключатель поля даты срока действия
    $expEnable.Add_Click({ $expDate.IsEnabled = [bool]$expEnable.IsChecked })
    # Показывать выбранную дату в формате ДД-ММ-ГГГГ
    $expDate.Add_SelectedDateChanged({
        try {
            if ($expDate.SelectedDate) {
                $tb = $expDate.Template.FindName('PART_TextBox', $expDate)
                if ($tb) { $tb.Text = Format-AdDate ([DateTime]$expDate.SelectedDate) }
            }
        } catch { }
    })

    # Автозаполнение отображаемого имени
    $updateDisplay = { if (-not $d.Text) { $d.Text = ("$($g.Text) $($s.Text)").Trim() } }
    $g.Add_LostFocus($updateDisplay); $s.Add_LostFocus($updateDisplay)

    # Предзаполнить UPN-суффикс
    if ($Global:ADConnection.DnsRoot) {
        $upn.Text = "@" + $Global:ADConnection.DnsRoot
    } elseif ($Global:ADConnection.Server -and $Global:ADConnection.Server -match '\.') {
        $upn.Text = "@" + ($Global:ADConnection.Server -replace '^[^.]+\.', '')
    }

    # Список подразделений (OU) + выбор по умолчанию
    $choices = @(Get-OUChoices)
    foreach ($c in $choices) { $ou.Items.Add($c) | Out-Null }
    $defOu = $null
    if ($DefaultOU -and ($choices -contains $DefaultOU)) { $defOu = $DefaultOU }
    if (-not $defOu) { $defOu = $choices | Where-Object { $_ -match '^CN=Users,' } | Select-Object -First 1 }
    if (-not $defOu -and $Global:ADConnection.BaseDN) { $defOu = $Global:ADConnection.BaseDN }
    if ($defOu) { $ou.Text = $defOu }

    # Обзор дерева домена для выбора OU
    $browse.Add_Click({
        $picked = Show-OUTreePicker -Owner $w -Initial $ou.Text
        if ($picked) { $ou.Text = $picked }
    })

    # Автоматически добавить группы по умолчанию
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
        $st.Text = "Не найдены группы по умолчанию: " + ($missing -join ', ')
    }

    # Выбор групп доступа при создании
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
        if ([string]::IsNullOrWhiteSpace($samVal)) { $st.Text = "Укажите логин (sAMAccountName)."; return }
        if ([string]::IsNullOrWhiteSpace($pass.Password)) { $st.Text = "Укажите пароль."; return }

        # Проверка срока действия
        $expValue = $null
        if ($expEnable.IsChecked) {
            if ($null -eq $expDate.SelectedDate) { $st.Text = "Укажите дату срока действия или снимите галочку."; return }
            # Действует ПО указанную дату включительно => истекает на следующий день
            $expValue = ([DateTime]$expDate.SelectedDate).Date.AddDays(1)
        }

        # Проверка, что логин ещё не занят в домене
        try {
            $pc = Get-ADParams
            $dup = Get-ADUser @pc -Identity $samVal -ErrorAction Stop
            if ($dup) { $st.Text = "Пользователь с логином «$samVal» уже существует в домене."; return }
        } catch {
            # Не найден — это нормально, продолжаем создание
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

            # Добавить в выбранные группы доступа
            $errs = @()
            foreach ($it in $glist.Items) {
                try {
                    $pg = Get-ADParams
                    Add-ADGroupMember @pg -Identity ([string]$it.Tag) -Members $newUser.DistinguishedName
                } catch { $errs += "$($it.Content): $($_.Exception.Message)" }
            }
            if ($errs.Count -gt 0) {
                Show-Error ("Пользователь создан, но добавлен не во все группы:`n" + ($errs -join "`n"))
            }

            $script:CreateOk = $true
            $w.Close()
        }
        catch { $st.Text = "Ошибка: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:CreateOk
}

# --- Сброс пароля ---
[xml]$PwdXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Сброс пароля" Height="270" Width="400"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="PLbl" Text="" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,12"/>
        <TextBlock Text="Новый пароль:"/>
        <PasswordBox Name="PNew" Margin="0,4,0,8" Padding="3"/>
        <TextBlock Text="Подтверждение:"/>
        <PasswordBox Name="PConfirm" Margin="0,4,0,8" Padding="3"/>
        <CheckBox Name="PChange" Content="Сменить пароль при следующем входе" IsChecked="True"/>
        <CheckBox Name="PUnlock" Content="Разблокировать учётную запись" IsChecked="True" Margin="0,6,0,0"/>
        <TextBlock Name="PStatus" Foreground="#B00020" TextWrapping="Wrap" Margin="0,8,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button Name="POk" Content="Применить" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="PCancel" Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

function Show-ResetPasswordDialog {
    param($Owner, $User)
    $reader = New-Object System.Xml.XmlNodeReader $PwdXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("PLbl").Text = "Пользователь: $($User.Name) ($($User.SamAccountName))"
    $new=$w.FindName("PNew"); $conf=$w.FindName("PConfirm")
    $chg=$w.FindName("PChange"); $unlock=$w.FindName("PUnlock")
    $st=$w.FindName("PStatus"); $ok=$w.FindName("POk"); $cancel=$w.FindName("PCancel")

    $script:PwdOk = $false
    $ok.Add_Click({
        $st.Text = ""
        if ([string]::IsNullOrWhiteSpace($new.Password)) { $st.Text="Введите новый пароль."; return }
        if ($new.Password -ne $conf.Password) { $st.Text="Пароли не совпадают."; return }
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
            $script:PwdOk = $true
            $w.Close()
        }
        catch { $st.Text = "Ошибка: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:PwdOk
}

# --- Перемещение в другой OU ---
[xml]$MoveXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Перемещение в подразделение" Height="240" Width="560"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="MLbl" Text="" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <TextBlock Text="Текущее размещение:"/>
        <TextBox Name="MCurrent" IsReadOnly="True" Margin="0,4,0,10" Padding="3" Background="#F5F5F5"/>
        <TextBlock Text="Целевой контейнер (OU):"/>
        <DockPanel Margin="0,4,0,4">
            <Button DockPanel.Dock="Right" Name="MBrowse" Content="Обзор…" Width="80" Margin="6,0,0,0"/>
            <ComboBox Name="MTarget" IsEditable="True" Padding="3"/>
        </DockPanel>
        <TextBlock Name="MStatus" Foreground="#B00020" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="MOk" Content="Переместить" Width="120" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="MCancel" Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

function Show-MoveDialog {
    param($Owner, $User)
    $reader = New-Object System.Xml.XmlNodeReader $MoveXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("MLbl").Text = "Пользователь: $($User.Name) ($($User.SamAccountName))"
    $current = $w.FindName("MCurrent")
    $target  = $w.FindName("MTarget")
    $browse  = $w.FindName("MBrowse")
    $st=$w.FindName("MStatus"); $ok=$w.FindName("MOk"); $cancel=$w.FindName("MCancel")

    # Текущий родительский контейнер
    $parentDN = ($User.DistinguishedName -replace '^CN=.*?(?<!\\),','')
    $current.Text = $parentDN

    # Заполнить список доступных OU
    try {
        $p = Get-ADParams
        Get-ADOrganizationalUnit @p -Filter * |
            Sort-Object DistinguishedName |
            ForEach-Object { $target.Items.Add($_.DistinguishedName) | Out-Null }
    } catch { }

    # Обзор дерева домена для выбора OU
    $browse.Add_Click({
        $picked = Show-OUTreePicker -Owner $w -Initial $target.Text
        if ($picked) { $target.Text = $picked }
    })

    $script:MoveOk = $false
    $ok.Add_Click({
        $st.Text = ""
        $dest = $target.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($dest)) { $st.Text="Укажите целевой контейнер."; return }
        try {
            $p = Get-ADParams
            Move-ADObject @p -Identity $User.DistinguishedName -TargetPath $dest
            $script:MoveOk = $true
            $w.Close()
        }
        catch { $st.Text = "Ошибка: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:MoveOk
}

# --- Выбор подразделения (OU) навигацией по дереву ---
[xml]$OUPickXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Выбор подразделения (OU)" Height="480" Width="430"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TreeView Grid.Row="0" Name="OUTree"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="OUOk" Content="Выбрать" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="OUCancel" Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-OUTreePicker {
    param($Owner, [string]$Initial)
    $reader = New-Object System.Xml.XmlNodeReader $OUPickXaml
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

# --- Список подразделений (OU) для выбора при создании ---
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

# --- Выбор групп доступа из справочника ---
[xml]$GroupPickXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Выбор групп доступа" Height="480" Width="520"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13">
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal">
            <TextBlock Text="Фильтр:" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <TextBox Name="GPSearch" Width="320" Padding="3"/>
            <Button Name="GPFind" Content="Найти" Width="80" Height="28" Margin="8,0,0,0"/>
        </StackPanel>
        <TextBlock Grid.Row="1" Text="Группы (Ctrl/Shift — множественный выбор):"
                   Margin="0,10,0,4"/>
        <ListBox Grid.Row="2" Name="GPList" SelectionMode="Extended"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right"
                    Margin="0,12,0,0">
            <Button Name="GPOk" Content="Выбрать" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="GPCancel" Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupPickerDialog {
    param($Owner, [string[]]$ExcludeDNs)
    $reader = New-Object System.Xml.XmlNodeReader $GroupPickXaml
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
        } catch { Show-Error "Не удалось получить группы: $($_.Exception.Message)" }
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

# --- Управление группами ---
[xml]$GroupsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Членство в группах" Height="480" Width="560"
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
            <Button Name="GAdd" Content="Добавить..." Width="150" Height="30"/>
        </StackPanel>
        <Button Grid.Row="3" Name="GRemove" Content="Удалить из выбранных групп" Width="240" Height="30"
                HorizontalAlignment="Left" Margin="0,10,0,0"/>
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button Name="GClose" Content="Закрыть" Width="100" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-GroupsDialog {
    param($Owner, $User)
    $reader = New-Object System.Xml.XmlNodeReader $GroupsXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("GLbl").Text = "Группы пользователя: $($User.Name) ($($User.SamAccountName))"
    $list=$w.FindName("GList")
    $add=$w.FindName("GAdd"); $remove=$w.FindName("GRemove"); $close=$w.FindName("GClose")

    $reload = {
        $list.Items.Clear()
        try {
            $p = Get-ADParams
            Get-ADPrincipalGroupMembership @p -Identity $User.DistinguishedName |
                Sort-Object name | ForEach-Object {
                    $it = New-Object System.Windows.Controls.ListBoxItem
                    $it.Content = $_.name
                    $it.Tag = $_.distinguishedName
                    $list.Items.Add($it) | Out-Null
                }
        } catch { Show-Error "Не удалось получить список групп: $($_.Exception.Message)" }
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
                $added++
            } catch { Show-Error "Не удалось добавить в группу: $($_.Exception.Message)" }
        }
        if ($added) { & $reload }
    })

    $remove.Add_Click({
        $sel = @($list.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action "Удалить пользователя из выбранных групп ($($sel.Count))?")) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $User.DistinguishedName -Confirm:$false
            } catch { Show-Error "Не удалось удалить из группы '$($it.Content)': $($_.Exception.Message)" }
        }
        & $reload
    })

    $close.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
}

# --- Изменение свойств ---
[xml]$EditXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Изменение свойств пользователя" Height="660" Width="480"
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
            <RowDefinition Height="140"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Отображаемое имя:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="0" Grid.Column="1" Name="EDisplay" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="E-mail:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="1" Grid.Column="1" Name="EMail" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Должность:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="ETitle" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="Отдел:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="EDept" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="Компания:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="4" Grid.Column="1" Name="ECompany" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="5" Grid.Column="0" Text="Кабинет:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="5" Grid.Column="1" Name="EOffice" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="6" Grid.Column="0" Text="Телефон:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="6" Grid.Column="1" Name="EPhone" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="7" Grid.Column="0" Text="Описание:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="7" Grid.Column="1" Name="EDesc" Margin="0,4" Padding="3"/>

        <TextBlock Grid.Row="8" Grid.ColumnSpan="2" Text="Группы доступа (Member Of):"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="9" Grid.ColumnSpan="2" Name="EGroups" SelectionMode="Extended"/>
        <StackPanel Grid.Row="10" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="EGAdd" Content="Добавить..." Width="130" Height="30"/>
            <Button Name="EGRemove" Content="Убрать выбранные" Width="170" Height="30" Margin="8,0,0,0"/>
        </StackPanel>

        <TextBlock Grid.Row="11" Grid.ColumnSpan="2" Name="EStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,10,0,0"/>

        <StackPanel Grid.Row="12" Grid.ColumnSpan="2" Orientation="Horizontal"
                    HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="EOk" Content="Сохранить" Width="110" Height="32" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="ECancel" Content="Отмена" Width="90" Height="32" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-EditDialog {
    param($Owner, $User)
    $ad = $User._AD
    $reader = New-Object System.Xml.XmlNodeReader $EditXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $disp=$w.FindName("EDisplay"); $mail=$w.FindName("EMail"); $title=$w.FindName("ETitle")
    $dept=$w.FindName("EDept"); $company=$w.FindName("ECompany"); $office=$w.FindName("EOffice")
    $phone=$w.FindName("EPhone"); $desc=$w.FindName("EDesc")
    $egroups=$w.FindName("EGroups"); $egAdd=$w.FindName("EGAdd"); $egRemove=$w.FindName("EGRemove")
    $st=$w.FindName("EStatus"); $ok=$w.FindName("EOk"); $cancel=$w.FindName("ECancel")

    $disp.Text    = [string]$ad.DisplayName
    $mail.Text    = [string]$ad.Mail
    $title.Text   = [string]$ad.Title
    $dept.Text    = [string]$ad.Department
    $company.Text = [string]$ad.Company
    $office.Text  = [string]$ad.Office
    $phone.Text   = [string]$ad.TelephoneNumber
    $desc.Text    = [string]$ad.Description

    # Группы доступа (Member Of) — изменения применяются сразу
    $reloadGroups = {
        $egroups.Items.Clear()
        try {
            $p = Get-ADParams
            Get-ADPrincipalGroupMembership @p -Identity $User.DistinguishedName |
                Sort-Object name | ForEach-Object {
                    $it = New-Object System.Windows.Controls.ListBoxItem
                    $it.Content = $_.name
                    $it.Tag = $_.distinguishedName
                    $egroups.Items.Add($it) | Out-Null
                }
        } catch { Show-Error "Не удалось получить группы: $($_.Exception.Message)" }
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
                $added++
            } catch { Show-Error "Не удалось добавить в группу: $($_.Exception.Message)" }
        }
        if ($added) { & $reloadGroups }
    })

    $egRemove.Add_Click({
        $sel = @($egroups.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action "Удалить из выбранных групп ($($sel.Count))?")) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $User.DistinguishedName -Confirm:$false
            } catch { Show-Error "Не удалось удалить из группы '$($it.Content)': $($_.Exception.Message)" }
        }
        & $reloadGroups
    })

    $script:EditOk = $false
    $ok.Add_Click({
        $st.Text = ""
        try {
            $p = Get-ADParams
            $p['Identity'] = $User.DistinguishedName
            $p['DisplayName']     = $disp.Text
            $p['EmailAddress']    = $mail.Text
            $p['Title']           = $title.Text
            $p['Department']      = $dept.Text
            $p['Company']         = $company.Text
            $p['Office']          = $office.Text
            $p['OfficePhone']     = $phone.Text
            $p['Description']     = $desc.Text
            Set-ADUser @p
            $script:EditOk = $true
            $w.Close()
        }
        catch { $st.Text = "Ошибка: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:EditOk
}

#endregion

#region ------------------------- Запуск приложения ----------------------------

# 1. Проверить модуль AD
if (-not (Test-ADModule)) { return }

# 2. Запросить учётные данные
if (-not (Show-LoginWindow)) { return }   # отмена — выходим

# 3. Построить главное окно
$reader   = New-Object System.Xml.XmlNodeReader $MainXaml
$MainWin  = [Windows.Markup.XamlReader]::Load($reader)

$TxtSearch = $MainWin.FindName("TxtSearch")
$BtnSearch = $MainWin.FindName("BtnSearch")
$BtnRefresh= $MainWin.FindName("BtnRefresh")
$BtnCreate = $MainWin.FindName("BtnCreate")
$GridUsers = $MainWin.FindName("GridUsers")
$PanelProps= $MainWin.FindName("PanelProps")
$LblConn   = $MainWin.FindName("LblConn")
$CmbDomain      = $MainWin.FindName("CmbDomain")
$BtnSwitchDomain= $MainWin.FindName("BtnSwitchDomain")
$TreeOU         = $MainWin.FindName("TreeOU")
$ChkSubtree     = $MainWin.FindName("ChkSubtree")

$BtnEnable  = $MainWin.FindName("BtnEnable")
$BtnDisable = $MainWin.FindName("BtnDisable")
$BtnUnlock  = $MainWin.FindName("BtnUnlock")
$BtnResetPwd= $MainWin.FindName("BtnResetPwd")
$BtnGroups  = $MainWin.FindName("BtnGroups")
$BtnMove    = $MainWin.FindName("BtnMove")
$BtnEdit    = $MainWin.FindName("BtnEdit")

$LblConn.Text = "Подключено к: $($Global:ADConnection.Server)   |   Пользователь: $($Global:ADConnection.UserName)"

# Формат даты/времени как DD MMM YYYY (например, 14 авг 2026).
$Script:RuMonths = @('янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек')
function Format-AdDate {
    param([datetime]$Dt, [switch]$WithTime)
    $mon = $Script:RuMonths[$Dt.Month - 1]
    $s = '{0:D2} {1} {2:D4}' -f $Dt.Day, $mon, $Dt.Year
    if ($WithTime) { $s += (' {0:D2}:{1:D2}' -f $Dt.Hour, $Dt.Minute) }
    return $s
}

# --- Когда должна быть произведена смена пароля ---
function Get-PwdExpiryText {
    param($ad)
    if (-not $ad.PasswordLastSet) { return "при следующем входе (требуется смена)" }
    if ($ad.PasswordNeverExpires) { return "никогда (пароль не истекает)" }
    $exp = $ad.'msDS-UserPasswordExpiryTimeComputed'
    if ($null -eq $exp) { return "" }
    if ([Int64]$exp -le 0 -or [Int64]$exp -ge 9223372036854775807) { return "никогда" }
    try {
        $dt = [DateTime]::FromFileTime([Int64]$exp)
        $txt = Format-AdDate $dt -WithTime
        if ($dt -lt (Get-Date)) { $txt += " (просрочен)" }
        return $txt
    } catch { return "" }
}

# --- Отрисовка свойств выбранного пользователя ---
function Update-PropsPanel {
    param($User)
    $PanelProps.Children.Clear()
    if (-not $User) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Выберите пользователя из списка"
        $tb.Foreground = 'Gray'; $tb.FontStyle = 'Italic'
        $PanelProps.Children.Add($tb) | Out-Null
        return
    }
    $ad = $User._AD
    $rows = [ordered]@{
        "Отображаемое имя" = $ad.DisplayName
        "Логин"            = $ad.SamAccountName
        "UPN"              = $ad.UserPrincipalName
        "Имя"              = $ad.GivenName
        "Фамилия"          = $ad.Surname
        "E-mail"           = $ad.Mail
        "Состояние"        = (Get-UserState $ad)
        "Заблокирован"     = if ($ad.LockedOut) { "Да" } else { "Нет" }
        "Описание"         = $ad.Description
        "Должность"        = $ad.Title
        "Отдел"            = $ad.Department
        "Компания"         = $ad.Company
        "Кабинет"          = $ad.Office
        "Телефон"          = $ad.TelephoneNumber
        "Пароль изменён"        = $ad.PasswordLastSet
        "Требуется смена пароля" = (Get-PwdExpiryText $ad)
        "Неверных попыток входа" = $ad.badPwdCount
        "Последний неверный ввод"= $ad.LastBadPasswordAttempt
        "Последний вход"   = $ad.LastLogonDate
        "Создан"           = $ad.whenCreated
        "Истекает"         = $ad.AccountExpirationDate
        "DN"               = $ad.DistinguishedName
    }
    foreach ($k in $rows.Keys) {
        $raw = $rows[$k]
        if ($raw -is [datetime]) {
            $val = Format-AdDate $raw -WithTime
        } else {
            $val = [string]$raw
        }
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = '0,0,0,6'
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $k; $lbl.FontWeight = 'SemiBold'; $lbl.Foreground = '#555'
        $lbl.FontSize = 11
        $v = New-Object System.Windows.Controls.TextBlock
        $v.Text = $val; $v.TextWrapping = 'Wrap'
        $sp.Children.Add($lbl) | Out-Null
        $sp.Children.Add($v)   | Out-Null
        $PanelProps.Children.Add($sp) | Out-Null
    }
}

# --- Построение дерева подразделений (OU) ---
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
        # Стандартные контейнеры верхнего уровня (CN=Users, CN=Computers, CN=Builtin и т.п.)
        $p2 = Get-ADParams
        $conts = @(Get-ADObject @p2 -SearchBase $baseDN -SearchScope OneLevel `
                     -LDAPFilter '(|(objectClass=container)(objectClass=builtinDomain))' |
                   Select-Object -ExpandProperty DistinguishedName)
    }
    catch { $ous = @(); $conts = @() }

    $all = @($ous + $conts) | Where-Object { $_ -and ($_.ToLower() -ne $baseDN.ToLower()) }
    # Сортировка по глубине (кол-во запятых), затем по алфавиту — родитель раньше ребёнка
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

    # Выбрать корень (вызовет Invoke-Search через обработчик SelectedItemChanged)
    $rootItem.IsSelected = $true
}

# --- Выполнить поиск и заполнить таблицу ---
function Invoke-Search {
    $MainWin.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $base = $null
        $sel = $TreeOU.SelectedItem
        if ($sel -and $sel.Tag) { $base = [string]$sel.Tag }

        $text = $TxtSearch.Text
        $subtree = (-not [string]::IsNullOrWhiteSpace($text)) -or $ChkSubtree.IsChecked
        $scope = if ($subtree) { 'Subtree' } else { 'OneLevel' }

        $results = @(Search-ADUsers -Query $text -SearchBase $base -Scope $scope)
        $GridUsers.ItemsSource = $results

        $scopeTxt = if ($sel -and $sel.Header) { [string]$sel.Header } else { $Global:ADConnection.DnsRoot }
        if ($subtree) { $scopeTxt = "$scopeTxt (+вложенные)" }
        $LblConn.Text = "Подключено к: $($Global:ADConnection.Server)   |   " +
                        "Пользователь: $($Global:ADConnection.UserName)   |   " +
                        "Область: $scopeTxt   |   Найдено: $($results.Count)"
    }
    catch { Show-Error "Ошибка поиска: $($_.Exception.Message)" }
    finally { $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow }
}

# --- Получить выбранного пользователя ---
function Get-SelectedUser {
    $u = $GridUsers.SelectedItem
    if (-not $u) { Show-Info "Сначала выберите пользователя в списке." "Не выбран пользователь"; return $null }
    return $u
}

# --- Перечитать выбранного пользователя из AD и обновить панель ---
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
            State             = Get-UserState $ad
            DistinguishedName = $ad.DistinguishedName
            _AD               = $ad
        }
        Update-PropsPanel $obj
    } catch { }
}

# --- Переключение доменов ---
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
        Show-Info "Выберите из списка или введите домен/контроллер."
        return
    }
    if ($target.ToLower() -eq ("$($Global:ADConnection.Server)").ToLower()) { return }

    $MainWin.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        # Смена домена под учётными данными активной сессии
        $info = Get-ADDomain -Server $target -Credential $Global:ADConnection.Credential -ErrorAction Stop
    }
    catch {
        $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow
        Show-Error ("Ошибка доступа: не удалось подключиться к домену «$target» " +
                    "под текущей учётной записью ($($Global:ADConnection.UserName)).`n`n" +
                    "Недостаточно прав или домен недоступен:`n$($_.Exception.Message)")
        return
    }
    finally { $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow }

    # Обновить активное подключение (учётные данные сессии сохраняются)
    $Global:ADConnection.Server  = $target
    $Global:ADConnection.BaseDN  = $info.DistinguishedName
    $Global:ADConnection.DnsRoot = $info.DNSRoot
    $Global:AccessGroupsResolved = $false
    $Global:AccessGroupsDN       = $null

    Add-SavedDomain -Server $target -Username $Global:ADConnection.UserName | Out-Null

    $LblConn.Text = "Подключено к: $($Global:ADConnection.Server)   |   " +
                    "Пользователь: $($Global:ADConnection.UserName)"
    Update-DomainCombo
    $TxtSearch.Text = ""
    $PanelProps.Children.Clear()
    Load-OUTree
    Show-Info "Подключено к домену «$($Global:ADConnection.Server)» под учётной записью $($Global:ADConnection.UserName)."
})

# --- Обработчики событий ---
$BtnSearch.Add_Click({ Invoke-Search })
$TxtSearch.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-Search } })
$BtnRefresh.Add_Click({ Invoke-Search })
$ChkSubtree.Add_Click({ Invoke-Search })
$TreeOU.Add_SelectedItemChanged({ Invoke-Search })

$GridUsers.Add_SelectionChanged({ Update-PropsPanel $GridUsers.SelectedItem })

$BtnCreate.Add_Click({
    $defOu = $null
    $selNode = $TreeOU.SelectedItem
    if ($selNode -and $selNode.Tag) { $defOu = [string]$selNode.Tag }
    if (Show-CreateUserDialog -Owner $MainWin -DefaultOU $defOu) {
        Show-Info "Пользователь создан."
        Invoke-Search
    }
})

$BtnEnable.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    try {
        $p = Get-ADParams
        Enable-ADAccount @p -Identity $u.DistinguishedName
        Show-Info "Учётная запись включена."
        Invoke-Search
    } catch { Show-Error "Не удалось включить: $($_.Exception.Message)" }
})

$BtnDisable.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (-not (Confirm-Action "Отключить учётную запись '$($u.SamAccountName)'?")) { return }
    try {
        $p = Get-ADParams
        Disable-ADAccount @p -Identity $u.DistinguishedName
        Show-Info "Учётная запись отключена."
        Invoke-Search
    } catch { Show-Error "Не удалось отключить: $($_.Exception.Message)" }
})

$BtnUnlock.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    try {
        $p = Get-ADParams
        Unlock-ADAccount @p -Identity $u.DistinguishedName
        Show-Info "Учётная запись разблокирована."
        Invoke-Search
    } catch { Show-Error "Не удалось разблокировать: $($_.Exception.Message)" }
})

$BtnResetPwd.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-ResetPasswordDialog -Owner $MainWin -User $u) {
        Show-Info "Пароль сброшен."
        Refresh-SelectedUser $u.DistinguishedName
    }
})

$BtnGroups.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    Show-GroupsDialog -Owner $MainWin -User $u
})

$BtnMove.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-MoveDialog -Owner $MainWin -User $u) {
        Show-Info "Пользователь перемещён."
        Invoke-Search
    }
})

$BtnEdit.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-EditDialog -Owner $MainWin -User $u) {
        Show-Info "Изменения сохранены."
        Invoke-Search
    }
})

# Начальная загрузка: дерево OU (выбор корня запустит поиск)
$MainWin.Add_ContentRendered({ Load-OUTree })

# Показать главное окно
$MainWin.ShowDialog() | Out-Null

#endregion
