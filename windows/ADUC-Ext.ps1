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

# Use English for built-in WPF strings (e.g. the DatePicker watermark),
# regardless of the OS UI language.
[System.Threading.Thread]::CurrentThread.CurrentUICulture =
    [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

$ErrorActionPreference = 'Stop'

# Global connection state
$Global:ADConnection = [pscustomobject]@{
    Credential = $null   # [PSCredential]
    Server     = $null   # DC / domain name
    UserName   = $null   # display name of the connected user
    BaseDN     = $null   # domain DistinguishedName (for the OU tree)
    DnsRoot    = $null   # domain DNS name
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
        "The PowerShell module 'ActiveDirectory' (RSAT) is not installed.`n`n" +
        "Install it automatically now?`n" +
        "Administrator rights and a Windows Update connection are required. " +
        "Installation may take a few minutes.",
        "Checking dependencies",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)

    if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
        [System.Windows.MessageBox]::Show(
            "The application cannot run without the ActiveDirectory module.`n`n" +
            "Install RSAT manually (as administrator):`n" +
            "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
            "ActiveDirectory module missing",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
        return $false
    }

    if (-not (Test-IsAdmin)) {
        [System.Windows.MessageBox]::Show(
            "Installing RSAT requires administrator rights.`n`n" +
            "Run the application as administrator or install it manually:`n" +
            "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
            "Insufficient rights",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return $false
    }

    if (Install-RSAT) {
        Import-Module ActiveDirectory -ErrorAction Stop
        Show-Info "ActiveDirectory module (RSAT) installed successfully."
        return $true
    }

    [System.Windows.MessageBox]::Show(
        "Failed to install RSAT automatically.`n`n" +
        "Install manually (as administrator):`n" +
        "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`n`n" +
        "On Windows Server:`n" +
        "  Install-WindowsFeature RSAT-AD-PowerShell",
        "RSAT installation error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
    return $false
}

# Unified wrapper for error messages
function Show-Error {
    param([string]$Message, [string]$Title = "Error")
    [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
}

function Show-Info {
    param([string]$Message, [string]$Title = "Information")
    [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information) | Out-Null
}

function Confirm-Action {
    param([string]$Message, [string]$Title = "Confirm")
    $r = [System.Windows.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    return ($r -eq [System.Windows.MessageBoxResult]::Yes)
}

# Common parameters for all AD cmdlet calls (credential + server)
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

[xml]$LoginXaml = @"
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
        if ($prof -and (Confirm-Action "Remove '$name' from the domain list?")) {
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
        $lblStatus.Text = "Checking connection..."
        $win.Dispatcher.Invoke([action]{}, "Render")

        $user = $txtUser.Text.Trim()
        $pass = $txtPass.Password

        if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
            $lblStatus.Text = "Enter a user name and password."
            return
        }

        try {
            $secPass = ConvertTo-SecureString $pass -AsPlainText -Force
            $cred    = New-Object System.Management.Automation.PSCredential($user, $secPass)
            $server  = $txtDomain.Text.Trim()

            $testParams = @{ Credential = $cred; ErrorAction = 'Stop' }
            if ($server) { $testParams['Server'] = $server }

            # Test AD call to verify the credentials
            $domainInfo = Get-ADDomain @testParams

            $resolvedServer = if ($server) { $server } else { $domainInfo.DNSRoot }
            $Global:ADConnection.Credential = $cred
            $Global:ADConnection.Server     = $resolvedServer
            $Global:ADConnection.UserName   = $user
            $Global:ADConnection.BaseDN     = $domainInfo.DistinguishedName
            $Global:ADConnection.DnsRoot    = $domainInfo.DNSRoot
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
            $lblStatus.Text = "Failed to connect: $($_.Exception.Message)"
        }
    })

    $btnCancel.Add_Click({ $script:LoginSuccess = $false; $win.Close() })

    $win.ShowDialog() | Out-Null
    return $script:LoginSuccess
}

#endregion

#region ----------------------- Main window (XAML) ----------------------------

[xml]$MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ADUC-Ext — Active Directory user management"
        Height="660" Width="1320"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13">
    <DockPanel>
        <!-- Top search bar -->
        <Border DockPanel.Dock="Top" Background="#F3F3F3" Padding="10">
            <StackPanel>
                <DockPanel>
                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="Domain:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <ComboBox Name="CmbDomain" Width="170" VerticalAlignment="Center" IsEditable="True"
                                  ToolTip="Select a saved domain or enter a controller/domain name"/>
                        <Button Name="BtnSwitchDomain" Content="Switch domain" Width="130" Height="30" Margin="8,0,0,0"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Search:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBox Name="TxtSearch" Width="220" Padding="4" VerticalAlignment="Center"
                                 ToolTip="Name, login (sAMAccountName), e-mail, or part of a value"/>
                        <Button Name="BtnSearch" Content="Find" Width="70" Height="30" Margin="8,0,0,0"/>
                        <Button Name="BtnRefresh" Content="Refresh" Width="80" Height="30" Margin="8,0,0,0"/>
                        <Button Name="BtnCreate" Content="Create user" Width="160" Height="30" Margin="12,0,0,0"/>
                    </StackPanel>
                </DockPanel>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                    <TextBlock Text="Show:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <RadioButton Name="RbUsers" Content="Users" GroupName="ObjMode" IsChecked="True"
                                 VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <RadioButton Name="RbComputers" Content="Computers" GroupName="ObjMode"
                                 VerticalAlignment="Center"/>
                    <CheckBox Name="ChkSubtree" Content="Nested OUs" VerticalAlignment="Center"
                              Margin="24,0,0,0" ToolTip="Show objects from nested organizational units"/>
                </StackPanel>
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
                <TextBlock DockPanel.Dock="Top" Text="Organizational units" FontWeight="SemiBold"
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
                        <MenuItem Name="CmRename"      Header="Rename..." Visibility="Collapsed"/>
                        <MenuItem Name="CmDelete"      Header="Delete" Visibility="Collapsed"/>
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

                <GroupBox Grid.Row="1" Header="Actions" Margin="0,10,0,0">
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
    'badPwdCount','LastBadPasswordAttempt'
)

function Get-UserState {
    param($u)
    if ($u.LockedOut)       { return "Locked" }
    if (-not $u.Enabled)    { return "Disabled" }
    return "Active"
}

function Search-ADUsers {
    param(
        [string]$Query,
        [string]$SearchBase,
        [string]$Scope = 'Subtree'   # Base | OneLevel | Subtree
    )
    $p = Get-ADParams
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
            _AD               = $_
        }
    }
}

# Properties requested for a computer
$Script:ComputerProps = @(
    'Name','DNSHostName','OperatingSystem','OperatingSystemVersion',
    'Description','Enabled','DistinguishedName','whenCreated',
    'LastLogonDate','SamAccountName'
)

function Get-ComputerState {
    param($c)
    if (-not $c.Enabled) { return "Disabled" }
    return "Active"
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

#endregion

#region ------------------------ Action dialogs -------------------------------

# --- Create user ---
[xml]$CreateXaml = @"
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
        <PasswordBox Grid.Row="7" Grid.Column="1" Name="CPass" Margin="0,4" Padding="3"/>
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
        $st.Text = "Default groups not found: " + ($missing -join ', ')
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
        if ([string]::IsNullOrWhiteSpace($samVal)) { $st.Text = "Specify a login (sAMAccountName)."; return }
        if ([string]::IsNullOrWhiteSpace($pass.Password)) { $st.Text = "Specify a password."; return }

        # Validate the expiration date
        $expValue = $null
        if ($expEnable.IsChecked) {
            if ($null -eq $expDate.SelectedDate) { $st.Text = "Enter an expiration date or clear the checkbox."; return }
            # Valid THROUGH the given date inclusive => expires the next day
            $expValue = ([DateTime]$expDate.SelectedDate).Date.AddDays(1)
        }

        # Check that the login is not already taken in the domain
        try {
            $pc = Get-ADParams
            $dup = Get-ADUser @pc -Identity $samVal -ErrorAction Stop
            if ($dup) { $st.Text = "A user with login `"$samVal`" already exists in the domain."; return }
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

            # Add to the selected groups
            $errs = @()
            foreach ($it in $glist.Items) {
                try {
                    $pg = Get-ADParams
                    Add-ADGroupMember @pg -Identity ([string]$it.Tag) -Members $newUser.DistinguishedName
                } catch { $errs += "$($it.Content): $($_.Exception.Message)" }
            }
            if ($errs.Count -gt 0) {
                Show-Error ("User created, but not added to all groups:`n" + ($errs -join "`n"))
            }

            $script:CreateOk = $true
            $w.Close()
        }
        catch { $st.Text = "Error: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:CreateOk
}

# --- Reset password ---
[xml]$PwdXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Reset password" Height="270" Width="400"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="18">
        <TextBlock Name="PLbl" Text="" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,12"/>
        <TextBlock Text="New password:"/>
        <PasswordBox Name="PNew" Margin="0,4,0,8" Padding="3"/>
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
    $reader = New-Object System.Xml.XmlNodeReader $PwdXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("PLbl").Text = "User: $($User.Name) ($($User.SamAccountName))"
    $new=$w.FindName("PNew"); $conf=$w.FindName("PConfirm")
    $chg=$w.FindName("PChange"); $unlock=$w.FindName("PUnlock")
    $st=$w.FindName("PStatus"); $ok=$w.FindName("POk"); $cancel=$w.FindName("PCancel")

    $script:PwdOk = $false
    $ok.Add_Click({
        $st.Text = ""
        if ([string]::IsNullOrWhiteSpace($new.Password)) { $st.Text="Enter a new password."; return }
        if ($new.Password -ne $conf.Password) { $st.Text="Passwords do not match."; return }
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
        catch { $st.Text = "Error: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:PwdOk
}

# --- Move to another OU ---
[xml]$MoveXaml = @"
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

function Show-MoveDialog {
    param($Owner, $User, $Users)
    # $Users (array) — bulk move; $User — single object (back-compat)
    $items = if ($Users) { @($Users) } else { @($User) }
    $reader = New-Object System.Xml.XmlNodeReader $MoveXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    if ($items.Count -eq 1) {
        $w.FindName("MLbl").Text = "Object: $($items[0].Name) ($($items[0].SamAccountName))"
    } else {
        $names = ($items | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ", "
        if ($items.Count -gt 3) { $names += ", ..." }
        $w.FindName("MLbl").Text = "Objects selected: $($items.Count) ($names)"
    }
    $current = $w.FindName("MCurrent")
    $target  = $w.FindName("MTarget")
    $browse  = $w.FindName("MBrowse")
    $st=$w.FindName("MStatus"); $ok=$w.FindName("MOk"); $cancel=$w.FindName("MCancel")

    # Current parent container
    $parents = @($items | ForEach-Object { ($_.DistinguishedName -replace '^CN=.*?(?<!\\),','') } | Sort-Object -Unique)
    $current.Text = if ($parents.Count -gt 1) { "(objects are in different containers)" } else { $parents[0] }

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
        if ([string]::IsNullOrWhiteSpace($dest)) { $st.Text="Specify a target container."; return }
        if ($items.Count -eq 1) {
            try {
                $p = Get-ADParams
                Move-ADObject @p -Identity $items[0].DistinguishedName -TargetPath $dest
                $script:MoveOk = $true
                $w.Close()
            }
            catch { $st.Text = "Error: $($_.Exception.Message)" }
            return
        }
        $errors = @()
        foreach ($o in $items) {
            try {
                $p = Get-ADParams
                Move-ADObject @p -Identity $o.DistinguishedName -TargetPath $dest
            } catch { $errors += "$($o.Name): $($_.Exception.Message)" }
        }
        $script:MoveOk = ($errors.Count -lt $items.Count)
        $script:MoveErrors = $errors
        if ($errors.Count -gt 0) {
            $okCnt = $items.Count - $errors.Count
            $txt = ($errors | Select-Object -First 10) -join "`r`n"
            if ($errors.Count -gt 10) { $txt += "`r`n..." }
            $st.Text = "Moved: $okCnt of $($items.Count).`r`n$txt"
            return
        }
        $w.Close()
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:MoveOk
}

# --- Rename an object (change its name/CN) ---
[xml]$RenameXaml = @"
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
            <Button Name="RnOk" Content="Rename" Width="110" Height="30" Margin="0,0,10,0" IsDefault="True"/>
            <Button Name="RnCancel" Content="Cancel" Width="90" Height="30" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

function Show-RenameDialog {
    param($Owner, $Obj)
    $reader = New-Object System.Xml.XmlNodeReader $RenameXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $curName = [string]$Obj.Name
    $w.FindName("RnLbl").Text = "Object: $curName"
    $name = $w.FindName("RnName")
    $st   = $w.FindName("RnStatus")
    $ok   = $w.FindName("RnOk"); $cancel = $w.FindName("RnCancel")
    $name.Text = $curName
    $w.Add_Loaded({ $name.SelectAll(); $name.Focus() })

    $script:RenameOk = $false
    $ok.Add_Click({
        $st.Text = ""
        $new = $name.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($new)) { $st.Text = "Enter a name."; return }
        if ($new -eq $curName) { $w.Close(); return }
        try {
            $p = Get-ADParams
            Rename-ADObject @p -Identity $Obj.DistinguishedName -NewName $new
            $script:RenameOk = $true
            $w.Close()
        }
        catch { $st.Text = "Error: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:RenameOk
}

# --- Edit computer attributes (description) ---
[xml]$CompEditXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit computer" Height="240" Width="440" ResizeMode="NoResize"
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
    $reader = New-Object System.Xml.XmlNodeReader $CompEditXaml
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
            $script:CompEditOk = $true
            $w.Close()
        }
        catch { $st.Text = "Error: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:CompEditOk
}

# --- Select an organizational unit (OU) by tree navigation ---
[xml]$OUPickXaml = @"
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
[xml]$GroupPickXaml = @"
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
        } catch { Show-Error "Failed to retrieve groups: $($_.Exception.Message)" }
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
[xml]$GroupsXaml = @"
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
    $reader = New-Object System.Xml.XmlNodeReader $GroupsXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $w.FindName("GLbl").Text = "User groups: $($User.Name) ($($User.SamAccountName))"
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
        } catch { Show-Error "Failed to retrieve the group list: $($_.Exception.Message)" }
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
            } catch { Show-Error "Failed to add to group: $($_.Exception.Message)" }
        }
        if ($added) { & $reload }
    })

    $remove.Add_Click({
        $sel = @($list.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action "Remove the user from the selected groups ($($sel.Count))?")) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $User.DistinguishedName -Confirm:$false
            } catch { Show-Error "Failed to remove from group '$($it.Content)': $($_.Exception.Message)" }
        }
        & $reload
    })

    $close.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
}

# --- Edit properties ---
[xml]$EditXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit user properties" Height="660" Width="480"
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
            <RowDefinition Height="Auto"/><RowDefinition Height="140"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Display name:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="0" Grid.Column="1" Name="EDisplay" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="E-mail:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="1" Grid.Column="1" Name="EMail" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Title:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="2" Grid.Column="1" Name="ETitle" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="Department:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="3" Grid.Column="1" Name="EDept" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="Company:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="4" Grid.Column="1" Name="ECompany" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="5" Grid.Column="0" Text="Office:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="5" Grid.Column="1" Name="EOffice" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="6" Grid.Column="0" Text="Phone:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="6" Grid.Column="1" Name="EPhone" Margin="0,4" Padding="3"/>
        <TextBlock Grid.Row="7" Grid.Column="0" Text="Description:" VerticalAlignment="Center"/>
        <TextBox   Grid.Row="7" Grid.Column="1" Name="EDesc" Margin="0,4" Padding="3"/>

        <CheckBox Grid.Row="8" Grid.ColumnSpan="2" Name="EPwdNoExpire"
                  Content="Password never expires" Margin="0,8,0,0"/>

        <TextBlock Grid.Row="9" Grid.ColumnSpan="2" Text="Group membership (Member Of):"
                   FontWeight="SemiBold" Margin="0,10,0,4"/>
        <ListBox Grid.Row="10" Grid.ColumnSpan="2" Name="EGroups" SelectionMode="Extended"/>
        <StackPanel Grid.Row="11" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,6,0,0">
            <Button Name="EGAdd" Content="Add..." Width="130" Height="30"/>
            <Button Name="EGRemove" Content="Remove selected" Width="170" Height="30" Margin="8,0,0,0"/>
        </StackPanel>

        <TextBlock Grid.Row="12" Grid.ColumnSpan="2" Name="EStatus" Foreground="#B00020"
                   TextWrapping="Wrap" Margin="0,10,0,0"/>

        <StackPanel Grid.Row="13" Grid.ColumnSpan="2" Orientation="Horizontal"
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
    $reader = New-Object System.Xml.XmlNodeReader $EditXaml
    $w = [Windows.Markup.XamlReader]::Load($reader)
    $w.Owner = $Owner
    $disp=$w.FindName("EDisplay"); $mail=$w.FindName("EMail"); $title=$w.FindName("ETitle")
    $dept=$w.FindName("EDept"); $company=$w.FindName("ECompany"); $office=$w.FindName("EOffice")
    $phone=$w.FindName("EPhone"); $desc=$w.FindName("EDesc")
    $egroups=$w.FindName("EGroups"); $egAdd=$w.FindName("EGAdd"); $egRemove=$w.FindName("EGRemove")
    $st=$w.FindName("EStatus"); $ok=$w.FindName("EOk"); $cancel=$w.FindName("ECancel")
    $pwdNoExp = $w.FindName("EPwdNoExpire")
    $pwdNoExp.IsChecked = [bool]$ad.PasswordNeverExpires

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
            Get-ADPrincipalGroupMembership @p -Identity $User.DistinguishedName |
                Sort-Object name | ForEach-Object {
                    $it = New-Object System.Windows.Controls.ListBoxItem
                    $it.Content = $_.name
                    $it.Tag = $_.distinguishedName
                    $egroups.Items.Add($it) | Out-Null
                }
        } catch { Show-Error "Failed to retrieve groups: $($_.Exception.Message)" }
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
            } catch { Show-Error "Failed to add to group: $($_.Exception.Message)" }
        }
        if ($added) { & $reloadGroups }
    })

    $egRemove.Add_Click({
        $sel = @($egroups.SelectedItems)
        if ($sel.Count -eq 0) { return }
        if (-not (Confirm-Action "Remove from the selected groups ($($sel.Count))?")) { return }
        foreach ($it in $sel) {
            try {
                $p = Get-ADParams
                Remove-ADGroupMember @p -Identity ([string]$it.Tag) -Members $User.DistinguishedName -Confirm:$false
            } catch { Show-Error "Failed to remove from group '$($it.Content)': $($_.Exception.Message)" }
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
            $p['PasswordNeverExpires'] = [bool]$pwdNoExp.IsChecked
            # Like ADUC: enabling the flag cancels a pending 'change password
            # at next logon' requirement (PasswordLastSet = $null means pending).
            if ([bool]$pwdNoExp.IsChecked -and -not $User._AD.PasswordLastSet) {
                $p['ChangePasswordAtLogon'] = $false
            }
            Set-ADUser @p
            $script:EditOk = $true
            $w.Close()
        }
        catch { $st.Text = "Error: $($_.Exception.Message)" }
    })
    $cancel.Add_Click({ $w.Close() })
    $w.ShowDialog() | Out-Null
    return $script:EditOk
}

#endregion

#region ------------------------- Application startup -------------------------

# 1. Check the AD module
if (-not (Test-ADModule)) { return }

# 2. Request credentials
if (-not (Show-LoginWindow)) { return }   # cancelled — exit

# 3. Build the main window
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
$BtnRename  = $MainWin.FindName("BtnRename")
$BtnDelete  = $MainWin.FindName("BtnDelete")
$BtnPwdNoExpire = $MainWin.FindName("BtnPwdNoExpire")
$RbUsers    = $MainWin.FindName("RbUsers")
$RbComputers= $MainWin.FindName("RbComputers")
$GrpProps   = $MainWin.FindName("GrpProps")

$LblConn.Text = "Connected to: $($Global:ADConnection.Server)   |   User: $($Global:ADConnection.UserName)"

# Format a date/datetime as yyyy-mmm-dd (e.g. 2026-aug-14), month lowercased.
function Format-AdDate {
    param([datetime]$Dt, [switch]$WithTime)
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    $fmt = if ($WithTime) { 'yyyy-MMM-dd HH:mm' } else { 'yyyy-MMM-dd' }
    return $Dt.ToString($fmt, $ci).ToLower()
}

# --- When the password must be changed ---
function Get-PwdExpiryText {
    param($ad)
    if (-not $ad.PasswordLastSet) { return "at next logon (change required)" }
    if ($ad.PasswordNeverExpires) { return "never (password does not expire)" }
    $exp = $ad.'msDS-UserPasswordExpiryTimeComputed'
    if ($null -eq $exp) { return "" }
    if ([Int64]$exp -le 0 -or [Int64]$exp -ge 9223372036854775807) { return "never" }
    try {
        $dt = [DateTime]::FromFileTime([Int64]$exp)
        $txt = Format-AdDate $dt -WithTime
        if ($dt -lt (Get-Date)) { $txt += " (expired)" }
        return $txt
    } catch { return "" }
}

# --- Render properties of the selected user ---
function Update-PropsPanel {
    param($User)
    $PanelProps.Children.Clear()
    if (-not $User) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Select a user from the list"
        $tb.Foreground = 'Gray'; $tb.FontStyle = 'Italic'
        $PanelProps.Children.Add($tb) | Out-Null
        return
    }
    $ad = $User._AD
    if ($User._IsComputer) {
        $rows = [ordered]@{
            "Name"             = $ad.Name
            "Account name"     = $ad.SamAccountName
            "DNS name"         = $ad.DNSHostName
            "Operating system" = $ad.OperatingSystem
            "OS version"       = $ad.OperatingSystemVersion
            "State"            = (Get-ComputerState $ad)
            "Description"      = $ad.Description
            "Last logon"       = $ad.LastLogonDate
            "Created"          = $ad.whenCreated
            "DN"               = $ad.DistinguishedName
        }
    }
    else {
    $rows = [ordered]@{
        "Display name"    = $ad.DisplayName
        "Login"           = $ad.SamAccountName
        "UPN"              = $ad.UserPrincipalName
        "First name"      = $ad.GivenName
        "Last name"       = $ad.Surname
        "E-mail"           = $ad.Mail
        "State"           = (Get-UserState $ad)
        "Locked"          = if ($ad.LockedOut) { "Yes" } else { "No" }
        "Description"      = $ad.Description
        "Title"           = $ad.Title
        "Department"      = $ad.Department
        "Company"         = $ad.Company
        "Office"          = $ad.Office
        "Phone"          = $ad.TelephoneNumber
        "Password last set"     = $ad.PasswordLastSet
        "Password never expires" = if ($ad.PasswordNeverExpires) { "Yes" } else { "No" }
        "Password change required" = (Get-PwdExpiryText $ad)
        "Bad password attempts" = $ad.badPwdCount
        "Last bad password"     = $ad.LastBadPasswordAttempt
        "Last logon"      = $ad.LastLogonDate
        "Created"         = $ad.whenCreated
        "Expires"        = $ad.AccountExpirationDate
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
        # Context menu: copy this value / copy all
        $cm = New-Object System.Windows.Controls.ContextMenu
        $miVal = New-Object System.Windows.Controls.MenuItem
        $miVal.Header = "Copy value ($k)"
        $miVal.Tag = $val
        $miVal.Add_Click({ Set-ClipboardText ([string]$this.Tag) })
        $miAll = New-Object System.Windows.Controls.MenuItem
        $miAll.Header = "Copy all properties"
        $miAll.Add_Click({ Set-ClipboardText ($Script:PropRows -join "`r`n") })
        $cm.Items.Add($miVal) | Out-Null
        $cm.Items.Add($miAll) | Out-Null
        $v.ContextMenu = $cm

        $sp.Children.Add($lbl) | Out-Null
        $sp.Children.Add($v)   | Out-Null
        $PanelProps.Children.Add($sp) | Out-Null
    }
}

# --- Clipboard helper ---
function Set-ClipboardText {
    param([string]$Text)
    if ($null -eq $Text) { return }
    try {
        [System.Windows.Clipboard]::SetText($Text)
        if ($LblConn) { $LblConn.Text = "$($LblConn.Text)   |   Copied" }
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
        } else {
            $results = @(Search-ADUsers -Query $text -SearchBase $base -Scope $scope)
        }
        $GridUsers.ItemsSource = $results

        $scopeTxt = if ($sel -and $sel.Header) { [string]$sel.Header } else { $Global:ADConnection.DnsRoot }
        if ($subtree) { $scopeTxt = "$scopeTxt (+nested)" }
        $LblConn.Text = "Connected to: $($Global:ADConnection.Server)   |   " +
                        "User: $($Global:ADConnection.UserName)   |   " +
                        "Scope: $scopeTxt   |   Found: $($results.Count)"
    }
    catch { Show-Error "Search error: $($_.Exception.Message)" }
    finally { $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow }
}

# --- Get the selected user ---
function Get-SelectedUser {
    if ($GridUsers.SelectedItems.Count -gt 1) {
        Show-Info "This action applies to a single object.`r`nSelect exactly one item in the list." "Multiple objects selected"
        return $null
    }
    $u = $GridUsers.SelectedItem
    if (-not $u) { Show-Info "Select a user in the list first." "No user selected"; return $null }
    return $u
}

function Get-SelectedUsers {
    # All selected objects (multi-select aware)
    $items = @($GridUsers.SelectedItems)
    if (-not $items -or $items.Count -eq 0) {
        Show-Info "Select one or more objects in the list." "No object selected"
        return @()
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
    param([switch]$Computers)
    $GridUsers.Columns.Clear()
    $starU = [System.Windows.Controls.DataGridLengthUnitType]::Star
    $mk = {
        param($header, $bind, $wStar)
        $col = New-Object System.Windows.Controls.DataGridTextColumn
        $col.Header = $header
        $col.Binding = New-Object System.Windows.Data.Binding $bind
        $col.Width = New-Object System.Windows.Controls.DataGridLength($wStar, [System.Windows.Controls.DataGridLengthUnitType]::Star)
        return $col
    }
    if ($Computers) {
        $GridUsers.Columns.Add((& $mk 'Name' 'Name' 1.4)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'DNS name' 'DnsHostName' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'Operating system' 'OS' 1.5)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'Description' 'Description' 1.4)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'State' 'State' 1.0)) | Out-Null
    } else {
        $GridUsers.Columns.Add((& $mk 'Name' 'Name' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'Login' 'SamAccountName' 1.2)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'E-mail' 'Mail' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'Description' 'Description' 1.6)) | Out-Null
        $GridUsers.Columns.Add((& $mk 'State' 'State' 1.0)) | Out-Null
    }
}

# --- Switch between users and computers ---
function Switch-Mode {
    $computers = [bool]$RbComputers.IsChecked
    $TxtSearch.Text = ""
    $PanelProps.Children.Clear()
    $Script:PropRows = @()
    Set-GridColumns -Computers:$computers
    $GrpProps.Header = if ($computers) { "Computer properties" } else { "User properties" }

    # Action buttons (Edit stays visible in both modes — it routes by object type)
    $userBtns = @($BtnUnlock, $BtnResetPwd, $BtnPwdNoExpire, $BtnGroups)
    $compBtns = @($BtnRename, $BtnDelete)
    foreach ($b in $userBtns) { if ($b) { $b.Visibility = if ($computers) { 'Collapsed' } else { 'Visible' } } }
    foreach ($b in $compBtns) { if ($b) { $b.Visibility = if ($computers) { 'Visible' } else { 'Collapsed' } } }
    if ($BtnCreate) { $BtnCreate.Visibility = if ($computers) { 'Collapsed' } else { 'Visible' } }

    # Context-menu items
    $cm = $GridUsers.ContextMenu
    $userItems = @('CmCopyMail','CmCopyUpn','CmUnlock','CmResetPwd','CmPwdNoExpire','CmGroups')
    $compItems = @('CmRename','CmDelete')
    foreach ($n in $userItems) { $mi = Get-CmItem($n); if ($mi) { $mi.Visibility = if ($computers) { 'Collapsed' } else { 'Visible' } } }
    foreach ($n in $compItems) { $mi = Get-CmItem($n); if ($mi) { $mi.Visibility = if ($computers) { 'Visible' } else { 'Collapsed' } } }

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
        Show-Info "Select from the list or enter a domain/controller."
        return
    }
    if ($target.ToLower() -eq ("$($Global:ADConnection.Server)").ToLower()) { return }

    $MainWin.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        # Switch domain using the active session credentials
        $info = Get-ADDomain -Server $target -Credential $Global:ADConnection.Credential -ErrorAction Stop
    }
    catch {
        $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow
        Show-Error ("Access error: failed to connect to domain `"$target`" " +
                    "with the current account ($($Global:ADConnection.UserName)).`n`n" +
                    "Insufficient rights or the domain is unavailable:`n$($_.Exception.Message)")
        return
    }
    finally { $MainWin.Cursor = [System.Windows.Input.Cursors]::Arrow }

    # Update the active connection (session credentials are kept)
    $Global:ADConnection.Server  = $target
    $Global:ADConnection.BaseDN  = $info.DistinguishedName
    $Global:ADConnection.DnsRoot = $info.DNSRoot
    $Global:AccessGroupsResolved = $false
    $Global:AccessGroupsDN       = $null

    Add-SavedDomain -Server $target -Username $Global:ADConnection.UserName | Out-Null

    $LblConn.Text = "Connected to: $($Global:ADConnection.Server)   |   " +
                    "User: $($Global:ADConnection.UserName)"
    Update-DomainCombo
    $TxtSearch.Text = ""
    $PanelProps.Children.Clear()
    Load-OUTree
    Show-Info "Connected to domain `"$($Global:ADConnection.Server)`" as $($Global:ADConnection.UserName)."
})

# --- Event handlers ---
$BtnSearch.Add_Click({ Invoke-Search })
$TxtSearch.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-Search } })
$BtnRefresh.Add_Click({ Invoke-Search })
$ChkSubtree.Add_Click({ Invoke-Search })
$TreeOU.Add_SelectedItemChanged({ Invoke-Search })

$GridUsers.Add_SelectionChanged({
    if ($GridUsers.SelectedItems.Count -gt 1) {
        $PanelProps.Children.Clear()
        $Script:PropRows = @()
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "Selected objects: $($GridUsers.SelectedItems.Count)`r`n`r`nAvailable bulk actions:`r`nEnable / Disable / Move (OU)`r`nAdd to groups (users)"
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
        Show-Info "User created."
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
        Show-Error "${DoneMsg}: $ok of $($Items.Count).`r`n`r`nErrors:`r`n$txt" "Partially completed"
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
            Show-Info "Account enabled."
            Invoke-Search
        } catch { Show-Error "Failed to enable: $($_.Exception.Message)" }
        return
    }
    if (-not (Confirm-Action "Enable $($items.Count) accounts?")) { return }
    Invoke-BulkAccountAction $items { param($o) $p = Get-ADParams; Enable-ADAccount @p -Identity $o.DistinguishedName } "Enabled"
})

$BtnDisable.Add_Click({
    $items = Get-SelectedUsers; if (-not $items -or $items.Count -eq 0) { return }
    if ($items.Count -eq 1) {
        $u = $items[0]
        if (-not (Confirm-Action "Disable account '$($u.SamAccountName)'?")) { return }
        try {
            $p = Get-ADParams
            Disable-ADAccount @p -Identity $u.DistinguishedName
            Show-Info "Account disabled."
            Invoke-Search
        } catch { Show-Error "Failed to disable: $($_.Exception.Message)" }
        return
    }
    if (-not (Confirm-Action "Disable $($items.Count) accounts?")) { return }
    Invoke-BulkAccountAction $items { param($o) $p = Get-ADParams; Disable-ADAccount @p -Identity $o.DistinguishedName } "Disabled"
})

$BtnUnlock.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    try {
        $p = Get-ADParams
        Unlock-ADAccount @p -Identity $u.DistinguishedName
        Show-Info "Account unlocked."
        Invoke-Search
    } catch { Show-Error "Failed to unlock: $($_.Exception.Message)" }
})

$BtnResetPwd.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-ResetPasswordDialog -Owner $MainWin -User $u) {
        Show-Info "Password reset."
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
    $msg = if ($new) {
        $m = "Set the 'password never expires' flag for '$($u.SamAccountName)'?"
        if ($mustChange) {
            $m += "`r`n`r`nThe pending 'change password at next logon' requirement will be removed; the current password stays valid (same as in ADUC)."
        }
        $m
    } else {
        "Clear the 'password never expires' flag for '$($u.SamAccountName)'?`r`n`r`nThe password will expire per the domain policy."
    }
    if (-not (Confirm-Action $msg)) { return }
    try {
        $p = Get-ADParams
        if ($mustChange) {
            # Like ADUC: enabling the flag also cancels the pending change
            # requirement, so the current password stays valid.
            Set-ADUser @p -Identity $u.DistinguishedName -PasswordNeverExpires $true -ChangePasswordAtLogon $false
            Show-Info "Flag set: the password never expires.`r`n`r`nThe 'change password at next logon' requirement was removed; the current password stays valid."
        } else {
            Set-ADUser @p -Identity $u.DistinguishedName -PasswordNeverExpires $new
            if ($new) { Show-Info "Flag set: the password never expires." }
            else      { Show-Info "Flag cleared: the password expires per the domain policy." }
        }
        Invoke-Search
    } catch { Show-Error "Failed to change the flag: $($_.Exception.Message)" }
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
    if (-not (Confirm-Action "Add $($items.Count) users to $($picked.Count) group(s)?")) { return }
    $added = 0; $errors = @()
    foreach ($gdn in $picked) {
        foreach ($u in $items) {
            try {
                $p = Get-ADParams
                Add-ADGroupMember @p -Identity $gdn -Members $u.DistinguishedName
                $added++
            } catch {
                $gcn = ($gdn -split ',')[0] -replace '^CN=',''
                $errors += "$($u.SamAccountName) -> ${gcn}: $($_.Exception.Message)"
            }
        }
    }
    $summary = "Added: $added."
    if ($errors.Count -gt 0) {
        $txt = ($errors | Select-Object -First 10) -join "`r`n"
        if ($errors.Count -gt 10) { $txt += "`r`n..." }
        Show-Error "$summary`r`n`r`nErrors:`r`n$txt" "Partially completed"
    } else {
        Show-Info $summary
    }
})

$BtnMove.Add_Click({
    $items = Get-SelectedUsers; if (-not $items -or $items.Count -eq 0) { return }
    if (Show-MoveDialog -Owner $MainWin -Users $items) {
        if ($items.Count -eq 1) { Show-Info "Object moved." }
        elseif ($script:MoveErrors.Count -eq 0) { Show-Info "Objects moved: $($items.Count)." }
        Invoke-Search
    }
})

$BtnEdit.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if ($u._IsComputer) {
        if (Show-ComputerEditDialog -Owner $MainWin -Comp $u) {
            Show-Info "Changes saved."
            Invoke-Search
        }
    }
    elseif (Show-EditDialog -Owner $MainWin -User $u) {
        Show-Info "Changes saved."
        Invoke-Search
    }
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
        $BtnEdit.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    }
})

$BtnRename.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    if (Show-RenameDialog -Owner $MainWin -Obj $u) {
        Show-Info "Object renamed."
        Invoke-Search
    }
})

$BtnDelete.Add_Click({
    $u = Get-SelectedUser; if (-not $u) { return }
    $label = if ($u.Name) { $u.Name } else { $u.SamAccountName }
    if (-not (Confirm-Action "Delete object '$label'?`r`n`r`nThis operation is irreversible.")) { return }
    try {
        $p = Get-ADParams
        Remove-ADObject @p -Identity $u.DistinguishedName -Confirm:$false
        Show-Info "Object deleted."
        $PanelProps.Children.Clear()
        $Script:PropRows = @()
        Invoke-Search
    } catch { Show-Error "Failed to delete: $($_.Exception.Message)" }
})

# Object type switch
$RbUsers.Add_Checked({ if ($GridUsers) { Switch-Mode } })
$RbComputers.Add_Checked({ if ($GridUsers) { Switch-Mode } })

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
        # Multi-selection: only bulk actions (Enable / Disable / Move) apply
        foreach ($n in 'CmCopyLogin','CmCopyName','CmCopyMail','CmCopyUpn','CmCopyDn','CmCopyAll','CmUnlock','CmResetPwd','CmPwdNoExpire','CmGroups','CmEdit','CmRename','CmDelete') {
            $mi = Get-CmItem($n); if ($mi) { $mi.IsEnabled = $false }
        }
        foreach ($n in 'CmEnable','CmDisable','CmMove') {
            $mi = Get-CmItem($n); if ($mi) { $mi.IsEnabled = $true }
        }
        # Bulk add-to-groups is available for users (not in computers mode)
        $mi = Get-CmItem('CmGroups')
        if ($mi) { $mi.IsEnabled = (-not [bool]$RbComputers.IsChecked) }
        $mi = Get-CmItem('CmPwdNoExpire'); if ($mi) { $mi.IsChecked = $false }
        return
    }
    foreach ($n in 'CmCopyLogin','CmCopyName','CmCopyDn','CmCopyAll','CmEnable','CmDisable','CmUnlock','CmResetPwd','CmPwdNoExpire','CmGroups','CmMove','CmEdit','CmRename','CmDelete') {
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
$mi = Get-CmItem 'CmCopyAll'; if ($mi) { $mi.Add_Click(  { if ($Script:PropRows) { Set-ClipboardText ($Script:PropRows -join "`r`n") } }) }
$mi = Get-CmItem 'CmEnable'; if ($mi) { $mi.Add_Click(   { $BtnEnable.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmDisable'; if ($mi) { $mi.Add_Click(  { $BtnDisable.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmUnlock'; if ($mi) { $mi.Add_Click(   { $BtnUnlock.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmResetPwd'; if ($mi) { $mi.Add_Click( { $BtnResetPwd.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmPwdNoExpire'; if ($mi) { $mi.Add_Click({ $BtnPwdNoExpire.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmGroups'; if ($mi) { $mi.Add_Click(   { $BtnGroups.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmMove'; if ($mi) { $mi.Add_Click(     { $BtnMove.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmEdit'; if ($mi) { $mi.Add_Click(     { $BtnEdit.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmRename'; if ($mi) { $mi.Add_Click(   { $BtnRename.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
$mi = Get-CmItem 'CmDelete'; if ($mi) { $mi.Add_Click(   { $BtnDelete.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }) }
# Initial load: OU tree (selecting the root triggers the search)
$MainWin.Add_ContentRendered({ Load-OUTree })

# Show the main window
$MainWin.ShowDialog() | Out-Null

#endregion
