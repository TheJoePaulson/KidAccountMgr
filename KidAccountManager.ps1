#Requires -Version 7.0
<#
.SYNOPSIS
 GUI-first Windows 11 local child account policy manager.
.NOTES
 Version 2.5.0. Run elevated in PowerShell 7 on Windows 11 Pro.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Version='2.5.0'; $Product='Windows Kid Account Manager'

# Fail fast before creating folders, logs, loading WPF, or querying accounts.
function Test-ElevatedSession {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-ElevatedSession)) {
    Write-Host ''
    Write-Host 'Windows Kid Account Manager requires an elevated PowerShell session.' -ForegroundColor Yellow
    Write-Host 'Open PowerShell 7 using "Run as Administrator", then run this script again.' -ForegroundColor White
    Write-Host ''
    return
}
$Base='C:\Temp\KidLockdownManager'; $Logs=Join-Path $Base Logs; $Backups=Join-Path $Base Backups; $Reports=Join-Path $Base Reports
foreach($p in @($Base,$Logs,$Backups,$Reports,(Join-Path $Base Config))){if(-not(Test-Path $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}}
$LogFile=Join-Path $Logs ("KidAccountManager_{0}.log" -f (Get-Date -Format yyyyMMdd_HHmmss))
$script:Ui=@{}; $script:Rows=@(); $script:WebsiteRows=@(); $script:LoadedBackup=$null; $script:LoadedBackupPath=$null; $script:Cancel=$false
$AiSites=@('*://copilot.microsoft.com/*','*://chat.openai.com/*','*://chatgpt.com/*','*://claude.ai/*','*://gemini.google.com/*','*://perplexity.ai/*','*://huggingface.co/chat/*')
$Dns=[ordered]@{'No change'=@();'CleanBrowsing Family'=@('185.228.168.168','185.228.169.168');'OpenDNS FamilyShield'=@('208.67.222.123','208.67.220.123');'Cloudflare Family'=@('1.1.1.3','1.0.0.3');'Automatic (DHCP)'=@('DHCP')}
$Hidden='hide:activation;appsfeatures;developers;deviceencryption;optionalfeatures;otherusers;recovery;remotedesktop;signinoptions;windowsdefender;windowsinsider;windowsupdate;workplace'
$Catalog=@(
 [pscustomobject]@{Id='RestrictSettings';Cat='Windows';Name='Hide sensitive Settings pages';Path='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';Value='SettingsPageVisibility';Type='String';On=$Hidden;Default=$true;Restart='Sign out';Note='Leaves normal Settings available.'}
 [pscustomobject]@{Id='BlockControlPanel';Cat='Windows';Name='Block Control Panel and Settings';Path='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';Value='NoControlPanel';Type='DWord';On=1;Default=$false;Restart='Sign out';Note='More restrictive than hiding pages.'}
 [pscustomobject]@{Id='BlockCmd';Cat='Windows';Name='Block Command Prompt';Path='Software\Policies\Microsoft\Windows\System';Value='DisableCMD';Type='DWord';On=1;Default=$true;Restart='Sign out';Note='Blocks cmd.exe.'}
 [pscustomobject]@{Id='BlockRegedit';Cat='Windows';Name='Block Registry Editor';Path='Software\Microsoft\Windows\CurrentVersion\Policies\System';Value='DisableRegistryTools';Type='DWord';On=1;Default=$true;Restart='Sign out';Note='Blocks Regedit.'}
 [pscustomobject]@{Id='BlockTaskMgr';Cat='Windows';Name='Block Task Manager';Path='Software\Microsoft\Windows\CurrentVersion\Policies\System';Value='DisableTaskMgr';Type='DWord';On=1;Default=$false;Restart='Sign out';Note='Off by default for troubleshooting.'}
 [pscustomobject]@{Id='BlockRun';Cat='Windows';Name='Remove Run command';Path='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';Value='NoRun';Type='DWord';On=1;Default=$true;Restart='Sign out';Note='Removes Run.'}
 [pscustomobject]@{Id='BlockStore';Cat='Windows';Name='Block Microsoft Store';Path='Software\Policies\Microsoft\WindowsStore';Value='RemoveWindowsStore';Type='DWord';On=1;Default=$true;Restart='Sign out';Note='Per-user policy only. Use the Microsoft Store panel for a device-wide block.'}
 [pscustomobject]@{Id='BlockUsb';Cat='Windows';Name='Block removable storage';Path='Software\Policies\Microsoft\Windows\RemovableStorageDevices';Value='Deny_All';Type='DWord';On=1;Default=$false;Restart='Restart';Note='May affect school USB devices.'}
 [pscustomobject]@{Id='BlockExt';Cat='Edge';Name='Block all extensions';Path='Software\Policies\Microsoft\Edge\ExtensionInstallBlocklist';Value='1';Type='String';On='*';Default=$true;Restart='Restart Edge';Note='Blocks extension installation.'}
 [pscustomobject]@{Id='BlockDev';Cat='Edge';Name='Block Developer Tools';Path='Software\Policies\Microsoft\Edge';Value='DeveloperToolsAvailability';Type='DWord';On=2;Default=$true;Restart='Restart Edge';Note='Prevents DevTools.'}
 [pscustomobject]@{Id='BlockPrivate';Cat='Edge';Name='Block InPrivate browsing';Path='Software\Policies\Microsoft\Edge';Value='InPrivateModeAvailability';Type='DWord';On=1;Default=$true;Restart='Restart Edge';Note='Disables InPrivate.'}
 [pscustomobject]@{Id='BlockSignIn';Cat='Edge';Name='Block profile sign-in';Path='Software\Policies\Microsoft\Edge';Value='BrowserSignin';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='Supports local-only accounts.'}
 [pscustomobject]@{Id='BlockSync';Cat='Edge';Name='Block synchronization';Path='Software\Policies\Microsoft\Edge';Value='SyncDisabled';Type='DWord';On=1;Default=$true;Restart='Restart Edge';Note='Disables browser sync.'}
 [pscustomobject]@{Id='BlockPwd';Cat='Edge';Name='Disable password manager';Path='Software\Policies\Microsoft\Edge';Value='PasswordManagerEnabled';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='Disables password saving.'}
 [pscustomobject]@{Id='SmartScreen';Cat='Edge';Name='Require SmartScreen';Path='Software\Policies\Microsoft\Edge';Value='SmartScreenEnabled';Type='DWord';On=1;Default=$true;Restart='Restart Edge';Note='Keeps SmartScreen enabled.'}
 [pscustomobject]@{Id='Pua';Cat='Edge';Name='Require PUA protection';Path='Software\Policies\Microsoft\Edge';Value='SmartScreenPuaEnabled';Type='DWord';On=1;Default=$true;Restart='Restart Edge';Note='Blocks potentially unwanted apps.'}
 [pscustomobject]@{Id='CopilotIcon';Cat='Edge AI';Name='Hide Copilot toolbar icon';Path='Software\Policies\Microsoft\Edge';Value='Microsoft365CopilotChatIconEnabled';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='For supported Edge for Business profiles.'}
 [pscustomobject]@{Id='Sidebar';Cat='Edge AI';Name='Disable Edge sidebar';Path='Software\Policies\Microsoft\Edge';Value='HubsSidebarEnabled';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='Removes the Edge sidebar.'}
 [pscustomobject]@{Id='PageContext';Cat='Edge AI';Name='Disable Copilot page content access';Path='Software\Policies\Microsoft\Edge';Value='CopilotPageContext';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='Applies to Microsoft Entra ID profiles.'}
 [pscustomobject]@{Id='EntraContext';Cat='Edge AI';Name='Disable Entra Copilot browsing context';Path='Software\Policies\Microsoft\Edge';Value='EdgeEntraCopilotPageContext';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='Blocks page, history, and video transcript context for Entra profiles.'}
 [pscustomobject]@{Id='AiWriting';Cat='Edge AI';Name='Disable Copilot writing assistance';Path='Software\Policies\Microsoft\Edge';Value='ComposeInlineEnabled';Type='DWord';On=0;Default=$true;Restart='Restart Edge';Note='Applies to Edge for Business Entra profiles.'}
)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic
function Log([string]$m,[string]$l='INFO'){$line="[{0}] [{1}] {2}"-f(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$l,$m;Add-Content $LogFile $line;if($script:Ui.ContainsKey('log')){$script:Ui.log.AppendText("$line`r`n");$script:Ui.log.ScrollToEnd();$script:Ui.status.Text=$line;[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{},'Background')}}
function Msg($m,$t=$Product,$icon='Information'){[System.Windows.MessageBox]::Show($m,$t,'OK',$icon)|Out-Null}
function Admin-Sids{$set=[Collections.Generic.HashSet[string]]::new();try{Get-LocalGroupMember Administrators -ErrorAction Stop|%{if($_.SID){[void]$set.Add($_.SID.Value)}}}catch{Log "Admin group lookup warning: $($_.Exception.Message)" WARN};$set}
function Accounts {
    $admins = Admin-Sids
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue)

    foreach ($localUser in Get-LocalUser -ErrorAction Stop) {
        if ($localUser.SID.Value -notmatch '^S-1-5-21-') { continue }

        $profile = $profiles |
            Where-Object { $_.SID -eq $localUser.SID.Value } |
            Select-Object -First 1

        [pscustomobject]@{
            Use     = $false
            UserName = $localUser.Name
            SID      = $localUser.SID.Value
            Enabled  = [bool]$localUser.Enabled
            Admin    = $admins.Contains($localUser.SID.Value)
            Profile  = if ($null -ne $profile) { $profile.LocalPath } else { '' }
            Loaded   = if ($null -ne $profile) { [bool]$profile.Loaded } else { $false }
        }
    }
}
function Selected{@($script:Ui.accounts.ItemsSource|? Use)}
function Mount-Hive($u){$root="Registry::HKEY_USERS\$($u.SID)";if(Test-Path $root){return [pscustomobject]@{Root=$root;Mounted=$false;Name=''}};if([string]::IsNullOrWhiteSpace($u.Profile)){throw "Profile missing for $($u.UserName). Sign in once and sign out."};$n='KidMgr_'+($u.SID-replace'[^A-Za-z0-9]','_');$o=&reg.exe load "HKU\$n" (Join-Path $u.Profile NTUSER.DAT) 2>&1;if($LASTEXITCODE){throw ($o-join' ')};[pscustomobject]@{Root="Registry::HKEY_USERS\$n";Mounted=$true;Name=$n}}
function Unmount-Hive($h){if($h -and $h.Mounted){[GC]::Collect();[GC]::WaitForPendingFinalizers();Start-Sleep -Milliseconds 200;&reg.exe unload "HKU\$($h.Name)"|Out-Null}}
function Reg-State($p,$n){if(-not(Test-Path $p)){return [pscustomobject]@{Exists=$false;Value=$null;Type=$null}};try{$k=Get-Item $p;[pscustomobject]@{Exists=$true;Value=$k.GetValue($n,$null,'DoNotExpandEnvironmentNames');Type=$k.GetValueKind($n).ToString()}}catch{[pscustomobject]@{Exists=$false;Value=$null;Type=$null}}}
function Set-Reg($p,$n,$v,$t){if(-not(Test-Path $p)){New-Item $p -Force|Out-Null};New-ItemProperty $p -Name $n -Value $v -PropertyType $t -Force|Out-Null}
function Remove-Reg($p,$n){if((Reg-State $p $n).Exists){Remove-ItemProperty $p -Name $n -Force}}
function Set-List($path,[string[]]$values){if(-not(Test-Path $path)){New-Item $path -Force|Out-Null};$k=Get-Item $path;foreach($n in $k.GetValueNames()){if($n-match'^\d+$'){Remove-ItemProperty $path -Name $n -Force}};$i=1;foreach($v in $values){Set-Reg $path ([string]$i) $v String;$i++}}
function Get-RegListValues {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $key = Get-Item -LiteralPath $Path
    return @($key.GetValueNames() | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ } | ForEach-Object { [string]$key.GetValue($_) } | Where-Object { $_ })
}
function Normalize-WebsitePattern {
    param([string]$Value)
    $v = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    if ($v -notmatch '^[a-zA-Z*][a-zA-Z0-9+.-]*://') { $v = '*://' + $v }
    if ($v -notmatch '/\*$' -and $v -notmatch '\*$') { $v = $v.TrimEnd('/') + '/*' }
    return $v
}
function Get-DesiredWebsiteValues {
    param([ValidateSet('Blocked','Allowed')][string]$ListType)
    $grid = if ($ListType -eq 'Blocked') { $script:Ui.blockGrid } else { $script:Ui.allowGrid }
    return @($grid.ItemsSource | Where-Object Desired | ForEach-Object URL | Select-Object -Unique)
}
function Refresh-WebsiteGrid {
    $users = Selected
    if (-not $users.Count) { return }
    $all = [Collections.Generic.List[object]]::new()
    foreach ($u in $users) {
        if ($u.Admin) { continue }
        $h = $null
        try {
            $h = Mount-Hive $u
            foreach ($type in @('Blocked','Allowed')) {
                $sub = if ($type -eq 'Blocked') { 'URLBlocklist' } else { 'URLAllowlist' }
                $path = Join-Path $h.Root "Software\Policies\Microsoft\Edge\$sub"
                foreach ($url in Get-RegListValues $path) {
                    if (-not ($all | Where-Object { $_.ListType -eq $type -and $_.URL -eq $url })) {
                        $all.Add([pscustomobject]@{ListType=$type;URL=$url;Current=$true;Desired=$true;Status='MATCH';Source='Current policy'})
                    }
                }
            }
        } catch { Log "Website audit failed for $($u.UserName): $($_.Exception.Message)" ERROR }
        finally { Unmount-Hive $h }
    }
    if ($script:Ui.blockAi.IsChecked) {
        foreach ($url in $AiSites) {
            $existing=$all|Where-Object {$_.ListType -eq 'Blocked' -and $_.URL -eq $url}|Select-Object -First 1
            if ($existing) { $existing.Desired=$true; $existing.Source='AI preset' }
            else { $all.Add([pscustomobject]@{ListType='Blocked';URL=$url;Current=$false;Desired=$true;Status='ADD';Source='AI preset'}) }
        }
    }
    $script:WebsiteRows=@($all)
    $script:Ui.blockGrid.ItemsSource=@($script:WebsiteRows|Where-Object ListType -eq 'Blocked')
    $script:Ui.allowGrid.ItemsSource=@($script:WebsiteRows|Where-Object ListType -eq 'Allowed')
    Update-WebsiteStatuses
    Log "Website lists refreshed: $(@($script:Ui.blockGrid.ItemsSource).Count) blocked and $(@($script:Ui.allowGrid.ItemsSource).Count) allowed entries." INFO
}
function Close-GridEdit {
    param($Grid)
    if ($null -eq $Grid) { return }
    # A DataGrid keeps an open AddNew/EditItem transaction while a cell or row is
    # being edited. Items.Refresh() throws if called during that transaction, so
    # every pending edit must be committed (or cancelled) first.
    try { [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) } catch { }
    try { [void]$Grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) } catch { }
    if ($Grid.Items.IsAddingNew -or $Grid.Items.IsEditingItem) {
        try { $Grid.Items.CancelEdit() } catch { }
        try { $Grid.Items.CancelNew() } catch { }
    }
}
function Update-WebsiteStatuses {
    foreach ($row in @($script:Ui.blockGrid.ItemsSource)+@($script:Ui.allowGrid.ItemsSource)) {
        $row.Status = if ($row.Current -and $row.Desired) {'MATCH'} elseif (-not $row.Current -and $row.Desired) {'ADD'} elseif ($row.Current -and -not $row.Desired) {'REMOVE'} else {'NONE'}
    }
    foreach ($grid in @($script:Ui.blockGrid, $script:Ui.allowGrid)) {
        Close-GridEdit $grid
        try { $grid.Items.Refresh() }
        catch { Log "Grid refresh deferred: $($_.Exception.Message)" DEBUG }
    }
    $adds=@($script:WebsiteRows|Where-Object Status -eq 'ADD').Count
    $removes=@($script:WebsiteRows|Where-Object Status -eq 'REMOVE').Count
    $script:Ui.webSummary.Text="$adds URL(s) to add; $removes URL(s) to remove"
}
function Add-WebsiteEntry {
    param([ValidateSet('Blocked','Allowed')][string]$ListType)
    Close-GridEdit $script:Ui.blockGrid; Close-GridEdit $script:Ui.allowGrid
    $raw=[Microsoft.VisualBasic.Interaction]::InputBox("Enter a website or Edge URL pattern to add to the $ListType list:","Add $ListType website",'')
    $url=Normalize-WebsitePattern $raw
    if (-not $url) { return }
    $grid=if($ListType -eq 'Blocked'){$script:Ui.blockGrid}else{$script:Ui.allowGrid}
    $rows=@($grid.ItemsSource)
    $existing=$rows|Where-Object URL -eq $url|Select-Object -First 1
    if($existing){$existing.Desired=$true;Log "$url marked to remain in the $ListType list." INFO}
    else{$new=[pscustomobject]@{ListType=$ListType;URL=$url;Current=$false;Desired=$true;Status='ADD';Source='Manual'};$script:WebsiteRows=@($script:WebsiteRows+$new);$grid.ItemsSource=@($script:WebsiteRows|Where-Object ListType -eq $ListType);Log "$url queued for addition to the $ListType list." SUCCESS}
    Update-WebsiteStatuses
}
function Remove-WebsiteEntry {
    param([ValidateSet('Blocked','Allowed')][string]$ListType)
    Close-GridEdit $script:Ui.blockGrid; Close-GridEdit $script:Ui.allowGrid
    $grid=if($ListType -eq 'Blocked'){$script:Ui.blockGrid}else{$script:Ui.allowGrid}
    $selected=@($grid.SelectedItems)
    if(-not $selected.Count){Msg 'Select one or more website rows first.' 'Nothing selected' Warning;return}
    foreach($row in $selected){$row.Desired=$false;Log "$($row.URL) queued for removal from the $ListType list." WARN}
    Update-WebsiteStatuses
}
function Import-WebsiteText {
    param([ValidateSet('Blocked','Allowed')][string]$ListType)
    Close-GridEdit $script:Ui.blockGrid; Close-GridEdit $script:Ui.allowGrid
    $d=New-Object Microsoft.Win32.OpenFileDialog;$d.Filter='Text files (*.txt)|*.txt|All files (*.*)|*.*'
    if($d.ShowDialog() -ne $true){return}
    $count=0
    foreach($line in Get-Content -LiteralPath $d.FileName){$url=Normalize-WebsitePattern $line;if (-not $url) { continue };$grid=if($ListType -eq 'Blocked'){$script:Ui.blockGrid}else{$script:Ui.allowGrid};$existing=@($grid.ItemsSource)|Where-Object URL -eq $url|Select-Object -First 1;if($existing){$existing.Desired=$true}else{$new=[pscustomobject]@{ListType=$ListType;URL=$url;Current=$false;Desired=$true;Status='ADD';Source='TXT import'};$script:WebsiteRows=@($script:WebsiteRows+$new)};$count++}
    $script:Ui.blockGrid.ItemsSource=@($script:WebsiteRows|Where-Object ListType -eq 'Blocked');$script:Ui.allowGrid.ItemsSource=@($script:WebsiteRows|Where-Object ListType -eq 'Allowed');Update-WebsiteStatuses;Log "Imported $count $ListType website value(s) from $($d.FileName)." SUCCESS
}
function Export-WebsiteText {
    param([ValidateSet('Blocked','Allowed')][string]$ListType)
    $d=New-Object Microsoft.Win32.SaveFileDialog;$d.Filter='Text files (*.txt)|*.txt';$d.InitialDirectory=$Reports;$d.FileName="${ListType}Websites_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
    if($d.ShowDialog() -ne $true){return}
    Get-DesiredWebsiteValues $ListType|Set-Content -LiteralPath $d.FileName -Encoding utf8
    Log "$ListType website list exported to $($d.FileName)." SUCCESS
}
function Desired{$m=@{};foreach($c in $Catalog){$m[$c.Id]=[bool]$script:Ui["opt_$($c.Id)"].IsChecked};$m}
function Read-Rows($users,$map){$list=[Collections.Generic.List[object]]::new();foreach($u in $users){if($u.Admin){Log "Skipped administrator $($u.UserName)" WARN;continue};$h=$null;try{$h=Mount-Hive $u;foreach($c in $Catalog){$p=Join-Path $h.Root $c.Path;$st=Reg-State $p $c.Value;$want=[bool]$map[$c.Id];$match=if($want){$st.Exists -and ([string]$st.Value -eq [string]$c.On)}else{-not $st.Exists};$list.Add([pscustomobject]@{Target=$u.UserName;SID=$u.SID;Category=$c.Cat;Setting=$c.Name;Current=if($st.Exists){[string]$st.Value}else{'<not configured>'};Desired=if($want){[string]$c.On}else{'<not configured>'};Status=if($match){'MATCH'}else{'CHANGE'};Exists=$st.Exists;Type=if($st.Type){$st.Type}else{$c.Type};Path=$c.Path;ValueName=$c.Value;PolicyId=$c.Id;Restart=$c.Restart;Notes=$c.Note})}}catch{Log "Read failed for $($u.UserName): $($_.Exception.Message)" ERROR}finally{Unmount-Hive $h}};@($list)}
function Refresh-Accounts{$script:Ui.accounts.ItemsSource=@(Accounts);Log 'Local accounts refreshed.' SUCCESS}
function Refresh-Grid{$u=Selected;if(-not $u.Count){Msg 'Select at least one standard local account.' 'No target' Warning;return};$script:Rows=Read-Rows $u (Desired);$script:Ui.grid.ItemsSource=$script:Rows;Refresh-WebsiteGrid;Log "Configuration refreshed: $(@($script:Rows|? Status -eq 'CHANGE').Count) change(s)."}
function Network-Rows{Get-NetAdapter -Physical -ea SilentlyContinue|%{$d=Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ea SilentlyContinue;[pscustomobject]@{Adapter=$_.Name;Index=$_.ifIndex;Status=$_.Status;Dns=($d.ServerAddresses-join', ')}}}
function Backup-Now{Refresh-Grid;if (-not $script:Rows.Count) { return };$path=Join-Path $Backups ("RestorablePolicyBackup_{0}_{1}.json"-f$env:COMPUTERNAME,(Get-Date -Format yyyyMMdd_HHmmss));$pkg=[ordered]@{SchemaName='KidAccountManager.ConfigurationBackup';SchemaVersion='1.0';ToolVersion=$Version;Computer=$env:COMPUTERNAME;ExportDate=(Get-Date).ToString('o');Settings=@($script:Rows|%{[pscustomobject]@{UserName=$_.Target;SID=$_.SID;PolicyId=$_.PolicyId;Exists=$_.Exists;Value=if($_.Exists){$_.Current}else{$null};Type=$_.Type}});Websites=@($script:WebsiteRows|%{[pscustomobject]@{ListType=$_.ListType;URL=$_.URL;Current=$_.Current;Desired=$_.Desired;Status=$_.Status;Source=$_.Source}});Dns=@(Network-Rows)};$pkg|ConvertTo-Json -Depth 8|Set-Content $path -Encoding utf8;Log "Backup saved: $path" SUCCESS;$path}
function Load-Backup{$d=New-Object Microsoft.Win32.OpenFileDialog;$d.InitialDirectory=$Backups;$d.Filter='JSON backup (*.json)|*.json';if($d.ShowDialog() -ne $true){return$false};$p=Get-Content $d.FileName -Raw|ConvertFrom-Json -Depth 20;if($p.SchemaName -ne 'KidAccountManager.ConfigurationBackup'){throw'Invalid backup schema.'};$script:LoadedBackup=$p;$script:LoadedBackupPath=$d.FileName;Log "Backup loaded: $($d.FileName)" SUCCESS;return$true}
function Compare-Backup{if(-not $script:LoadedBackup){if(-not(Load-Backup)){return}};$u=Selected;if(-not $u.Count){throw'Select accounts first.'};$cur=Read-Rows $u (Desired);foreach($r in $cur){$sav=$script:LoadedBackup.Settings|?{($_.SID -eq $r.SID -or $_.UserName -eq $r.Target) -and $_.PolicyId -eq $r.PolicyId}|select -First 1;if($sav){$r.Desired=if($sav.Exists){[string]$sav.Value}else{'<not configured>'};$r.Status=if($r.Current -eq $r.Desired){'MATCH'}else{'DIFFERENT'};$r.Notes="Compared with $script:LoadedBackupPath"}else{$r.Status='NOT FOUND'}};$script:Rows=$cur;$script:Ui.grid.ItemsSource=$cur;Log 'Backup comparison completed.'}
function Restore-Backup{if(-not $script:LoadedBackup){if(-not(Load-Backup)){return}};$u=Selected;if(-not $u.Count){throw'Select accounts first.'};[void](Backup-Now);if([System.Windows.MessageBox]::Show('Restore loaded backup to selected accounts?','Confirm','YesNo','Warning')-ne'Yes'){return};foreach($a in $u){if($a.Admin){continue};$h=$null;try{$h=Mount-Hive $a;foreach($e in @($script:LoadedBackup.Settings|?{$_.SID -eq $a.SID -or $_.UserName -eq $a.UserName})){$c=$Catalog|? Id -eq $e.PolicyId|select -First 1;if(-not $c){continue};$p=Join-Path $h.Root $c.Path;if($e.Exists){$v=if($c.Type -eq 'DWord'){[int]$e.Value}else{[string]$e.Value};Set-Reg $p $c.Value $v $c.Type}else{Remove-Reg $p $c.Value}};Log "Restored $($a.UserName)." SUCCESS}finally{Unmount-Hive $h}};Refresh-Grid}
function Apply-Policy{$u=Selected;if(-not $u.Count){throw'Select accounts first.'};$desiredBlocked=@(Get-DesiredWebsiteValues Blocked);$desiredAllowed=@(Get-DesiredWebsiteValues Allowed);[void](Backup-Now);if([System.Windows.MessageBox]::Show('Apply desired controls to selected accounts?','Confirm','YesNo','Warning')-ne'Yes'){return};$map=Desired;foreach($a in $u){if($a.Admin){continue};$h=$null;try{$h=Mount-Hive $a;foreach($c in $Catalog){$p=Join-Path $h.Root $c.Path;if($map[$c.Id]){Set-Reg $p $c.Value $c.On $c.Type}else{Remove-Reg $p $c.Value}};$beforeBlocked=@(Get-RegListValues (Join-Path $h.Root 'Software\Policies\Microsoft\Edge\URLBlocklist'));$beforeAllowed=@(Get-RegListValues (Join-Path $h.Root 'Software\Policies\Microsoft\Edge\URLAllowlist'));$urls=@($desiredBlocked);$allowedUrls=@($desiredAllowed);Set-List (Join-Path $h.Root 'Software\Policies\Microsoft\Edge\URLBlocklist') $urls;Set-List (Join-Path $h.Root 'Software\Policies\Microsoft\Edge\URLAllowlist') $allowedUrls;foreach($url in @($urls|Where-Object {$_ -notin $beforeBlocked})){Log "Added blocked website for $($a.UserName): $url" SUCCESS};foreach($url in @($beforeBlocked|Where-Object {$_ -notin $urls})){Log "Removed blocked website for $($a.UserName): $url" WARN};foreach($url in @($allowedUrls|Where-Object {$_ -notin $beforeAllowed})){Log "Added allowed website for $($a.UserName): $url" SUCCESS};foreach($url in @($beforeAllowed|Where-Object {$_ -notin $allowedUrls})){Log "Removed allowed website for $($a.UserName): $url" WARN};Log "Applied controls to $($a.UserName)." SUCCESS}finally{Unmount-Hive $h}};Refresh-Grid}
function Set-Profile($name){$ids=@('CopilotIcon','Sidebar','PageContext','EntraContext','AiWriting');if($name -eq 'Kid Safe'){$ids|%{$script:Ui["opt_$_"].IsChecked=$true};$script:Ui.blockAi.IsChecked=$true;$script:Ui.opt_BlockSignIn.IsChecked=$true;$script:Ui.opt_BlockSync.IsChecked=$true}elseif($name -eq 'Student'){$ids|%{$script:Ui["opt_$_"].IsChecked=$false};$script:Ui.blockAi.IsChecked=$false};Log "$name profile loaded into desired controls; use Apply Selected to write changes."}
function Apply-Dns{$name=[string]$script:Ui.dns.SelectedItem;if($name -eq 'No change'){return};if (-not $script:Ui.dnsAck.IsChecked){throw'Acknowledge that DNS is device-wide.'};Network-Rows|ConvertTo-Json|Set-Content (Join-Path $Backups ("Dns_{0}.json"-f(Get-Date -Format yyyyMMdd_HHmmss)));Get-NetAdapter -Physical|? Status -ne 'Disabled'|%{if($name -eq 'Automatic (DHCP)'){Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses}else{Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $Dns[$name]}};Clear-DnsClientCache;Log "DNS applied: $name" SUCCESS}
function Export-Xlsx{if(-not(Get-Module -ListAvailable ImportExcel)){throw'ImportExcel is not installed.'};Import-Module ImportExcel;Refresh-Grid;$f=Join-Path $Reports ("KidConfig_{0}_{1}.xlsx"-f$env:COMPUTERNAME,(Get-Date -Format yyyyMMdd_HHmmss));$script:Rows|Export-Excel $f -WorksheetName Configuration -TableName Configuration -AutoSize -FreezeTopRow -AutoFilter -TableStyle Medium2;@($script:Rows|? Status -ne 'MATCH')|Export-Excel $f -WorksheetName Differences -TableName Differences -AutoSize -FreezeTopRow -AutoFilter -Append -TableStyle Medium4;@($script:Ui.blockGrid.ItemsSource)|Select-Object URL,Current,Desired,Status,Source|Export-Excel $f -WorksheetName 'Blocked URLs' -TableName BlockedURLs -AutoSize -FreezeTopRow -AutoFilter -Append -TableStyle Medium4;@($script:Ui.allowGrid.ItemsSource)|Select-Object URL,Current,Desired,Status,Source|Export-Excel $f -WorksheetName 'Allowed URLs' -TableName AllowedURLs -AutoSize -FreezeTopRow -AutoFilter -Append -TableStyle Medium2;Network-Rows|Export-Excel $f -WorksheetName 'Network and DNS' -AutoSize -Append;Log "Excel exported: $f" SUCCESS;Msg "Saved:`n$f" 'Export complete'}

# ============================================================
# MICROSOFT STORE BLOCKING (layered, device-wide)
# Windows Pro does not honor the RemoveWindowsStore registry policy on
# its own (documented as by-design), and the "Turn off the Store
# application" policy is deprecated on Windows 11 24H2 and later.
# A durable block therefore uses an AppLocker packaged-app deny rule as
# the primary layer, with the registry policy kept as defense in depth.
# ============================================================
$StorePublisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
$StoreRegPath   = 'Registry::HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\WindowsStore'

function Get-StoreBlockState {
    $reg = Get-RegState $StoreRegPath 'RemoveWindowsStore'
    $svc = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    $ruleFound = $false
    $enforced  = $false
    try {
        [xml]$pol = Get-AppLockerPolicy -Local -Xml -ErrorAction Stop
        $appx = @($pol.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq 'Appx' })
        if ($appx.Count) {
            $enforced = [bool](@($appx | Where-Object { $_.EnforcementMode -eq 'Enabled' }).Count)
            $ruleFound = [bool](@($appx.FilePublisherRule | Where-Object {
                $_.Action -eq 'Deny' -and $_.OuterXml -match 'WindowsStore'
            }).Count)
        }
    } catch { }
    [pscustomobject]@{
        RegistryPolicy = ($reg.Exists -and [string]$reg.Value -eq '1')
        DenyRule       = $ruleFound
        Enforced       = $enforced
        ServiceMode    = if ($svc) { $svc.StartType.ToString() } else { 'Missing' }
        ServiceRunning = [bool]($svc -and $svc.Status -eq 'Running')
    }
}

function Write-StoreAppLockerRule {
    $allowId = [guid]::NewGuid().ToString()
    $denyId  = [guid]::NewGuid().ToString()
    $xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Appx" EnforcementMode="Enabled">
    <FilePublisherRule Id="$allowId" Name="Allow all signed packaged apps" Description="Keeps built-in Store apps working" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="*" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="$denyId" Name="Deny Microsoft Store" Description="Blocks the Microsoft Store app" UserOrGroupSid="S-1-1-0" Action="Deny">
      <Conditions>
        <FilePublisherCondition PublisherName="$StorePublisher" ProductName="Microsoft.WindowsStore" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    $file = Join-Path $Backups ("AppLocker_StoreBlock_{0}.xml" -f (Get-Date -Format yyyyMMdd_HHmmss))
    $xml | Set-Content -LiteralPath $file -Encoding utf8
    Set-AppLockerPolicy -XmlPolicy $file -Merge -ErrorAction Stop
    Log "AppLocker Store deny rule applied ($file)." SUCCESS
    return $file
}

function Enable-StoreBlock {
    $prompt = "Block the Microsoft Store on this computer?" + [Environment]::NewLine + [Environment]::NewLine +
              "This is device-wide and affects every account. Built-in apps such as Photos and Calculator keep working."
    if ([System.Windows.MessageBox]::Show($prompt,'Confirm Store block','YesNo','Warning') -ne 'Yes') { return }
    try {
        $before = Join-Path $Backups ("AppLocker_Before_{0}.xml" -f (Get-Date -Format yyyyMMdd_HHmmss))
        Get-AppLockerPolicy -Local -Xml | Set-Content -LiteralPath $before -Encoding utf8
        Log "Existing AppLocker policy backed up to $before" INFO
    } catch { Log "AppLocker backup skipped: $($_.Exception.Message)" WARN }
    try {
        Set-Reg $StoreRegPath 'RemoveWindowsStore' 1 'DWord'
        Log 'Device-wide Store registry policy set (HKLM RemoveWindowsStore=1).' SUCCESS
    } catch { Log "Registry Store policy failed: $($_.Exception.Message)" ERROR }
    try { [void](Write-StoreAppLockerRule) }
    catch { Log "AppLocker rule could not be applied: $($_.Exception.Message)" ERROR }
    try {
        Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction Stop
        if ((Get-Service AppIDSvc).Status -ne 'Running') { Start-Service AppIDSvc -ErrorAction Stop }
        Log 'Application Identity service set to Automatic and started.' SUCCESS
    } catch { Log "AppIDSvc could not be started now; a restart usually completes this: $($_.Exception.Message)" WARN }
    Test-StoreBlock
}

function Disable-StoreBlock {
    if ([System.Windows.MessageBox]::Show('Remove the Microsoft Store block from this computer?','Confirm unblock','YesNo','Warning') -ne 'Yes') { return }
    try { Remove-Reg $StoreRegPath 'RemoveWindowsStore'; Log 'Store registry policy removed.' SUCCESS }
    catch { Log $_.Exception.Message ERROR }
    try {
        $clear = Join-Path $Backups 'AppLocker_Clear.xml'
        '<AppLockerPolicy Version="1"><RuleCollection Type="Appx" EnforcementMode="NotConfigured" /></AppLockerPolicy>' | Set-Content -LiteralPath $clear -Encoding utf8
        Set-AppLockerPolicy -XmlPolicy $clear -ErrorAction Stop
        Log 'AppLocker packaged-app rules cleared.' SUCCESS
    } catch { Log "AppLocker rules could not be cleared: $($_.Exception.Message)" WARN }
    Test-StoreBlock
}

function Test-StoreBlock {
    $st = Get-StoreBlockState
    Log ("Store registry policy : " + $(if($st.RegistryPolicy){'Configured'}else{'Not configured'})) $(if($st.RegistryPolicy){'SUCCESS'}else{'WARN'})
    Log ("AppLocker deny rule   : " + $(if($st.DenyRule){'Present'}else{'Not detected'}) + ", enforcement=" + $(if($st.Enforced){'Enabled'}else{'Not enabled'})) $(if($st.DenyRule -and $st.Enforced){'SUCCESS'}else{'WARN'})
    Log ("Application Identity  : " + $st.ServiceMode + ", running=" + $st.ServiceRunning) $(if($st.ServiceRunning){'SUCCESS'}else{'WARN'})
    if ($st.DenyRule -and $st.Enforced -and $st.ServiceRunning) {
        $script:Ui.storeState.Text = 'Store: BLOCKED (AppLocker enforced)'
        $script:Ui.storeState.Foreground = [System.Windows.Media.Brushes]::LightGreen
    } elseif ($st.DenyRule -or $st.RegistryPolicy) {
        $script:Ui.storeState.Text = 'Store: Partially blocked - sign out or restart to finish'
        $script:Ui.storeState.Foreground = [System.Windows.Media.Brushes]::Khaki
    } else {
        $script:Ui.storeState.Text = 'Store: Not blocked'
        $script:Ui.storeState.Foreground = [System.Windows.Media.Brushes]::LightSalmon
    }
}

[xml]$x=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="$Product v$Version" Width="1450" Height="950" MinWidth="1150" MinHeight="700" WindowStartupLocation="CenterScreen" Background="#1e1e2e" Foreground="#cdd6f4" FontFamily="Segoe UI" FontSize="13">
<Window.Resources>
<Style x:Key="Btn" TargetType="Button"><Setter Property="Height" Value="38"/><Setter Property="Margin" Value="4"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="White"/><Setter Property="Background" Value="#313244"/><Setter Property="BorderBrush" Value="#585b70"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#3D4052"/><Setter TargetName="b" Property="BorderBrush" Value="#89B4FA"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="#52576B"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType="GroupBox"><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="BorderBrush" Value="#45475a"/><Setter Property="Margin" Value="6"/><Setter Property="Padding" Value="6"/></Style><Style TargetType="CheckBox"><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="Margin" Value="4"/></Style><Style TargetType="TextBox"><Setter Property="Background" Value="#181825"/><Setter Property="Foreground" Value="#cdd6f4"/></Style><Style TargetType="DataGrid"><Setter Property="Background" Value="#181825"/><Setter Property="Foreground" Value="#cdd6f4"/><Setter Property="RowBackground" Value="#181825"/><Setter Property="AlternatingRowBackground" Value="#1e1e2e"/><Setter Property="AutoGenerateColumns" Value="False"/></Style><Style TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#89b4fa"/><Setter Property="Foreground" Value="#181825"/><Setter Property="FontWeight" Value="Bold"/></Style>
</Window.Resources><DockPanel><Border DockPanel.Dock="Top" Background="#181825" Padding="12"><DockPanel><StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button x:Name="refresh" Content="Refresh" Style="{StaticResource Btn}"/><Button x:Name="export" Content="Export Current Configuration" Style="{StaticResource Btn}"/></StackPanel><StackPanel><TextBlock Text="$Product v$Version" FontSize="20" FontWeight="Bold" Foreground="#89b4fa"/><TextBlock Text="$env:COMPUTERNAME" Foreground="#a6adc8"/></StackPanel></DockPanel></Border><TextBlock x:Name="status" DockPanel.Dock="Bottom" Background="#181825" Foreground="#a6adc8" Padding="8" Text="Ready"/><ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False"><Grid MinHeight="950"><Grid.ColumnDefinitions><ColumnDefinition Width="320"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><ScrollViewer Grid.Column="0"><StackPanel><GroupBox Header="Target accounts"><StackPanel><DataGrid x:Name="accounts" Height="230" HorizontalScrollBarVisibility="Auto"><DataGrid.Columns><DataGridCheckBoxColumn Header="Use" Binding="{Binding Use,Mode=TwoWay}" Width="50"/><DataGridTextColumn Header="Account" Binding="{Binding UserName}" Width="165" MinWidth="120"/><DataGridCheckBoxColumn Header="Admin" Binding="{Binding Admin}" Width="70"/></DataGrid.Columns></DataGrid><Button x:Name="users" Content="Refresh Accounts" Style="{StaticResource Btn}"/></StackPanel></GroupBox><GroupBox Header="Device-wide DNS"><StackPanel><ComboBox x:Name="dns" Height="30"/><CheckBox x:Name="dnsAck" Content="I understand DNS is device-wide"/><Button x:Name="applyDns" Content="Apply DNS" Style="{StaticResource Btn}"/></StackPanel></GroupBox><GroupBox Header="Microsoft Store"><StackPanel><TextBlock x:Name="storeState" Text="Store: not checked" TextWrapping="Wrap" Margin="2,0,2,4"/><TextBlock Text="Device-wide. Uses AppLocker plus registry policy." Foreground="#a6adc8" TextWrapping="Wrap" FontSize="11" Margin="2,0,2,4"/><Button x:Name="storeBlock" Content="Block Store (All Users)" Style="{StaticResource Btn}"/><Button x:Name="storeCheck" Content="Check Store Status" Style="{StaticResource Btn}"/><Button x:Name="storeUnblock" Content="Unblock Store" Style="{StaticResource Btn}"/></StackPanel></GroupBox><GroupBox Header="Folders"><StackPanel><Button x:Name="openLogs" Content="Open Logs" Style="{StaticResource Btn}"/><Button x:Name="openBackups" Content="Open Backups" Style="{StaticResource Btn}"/><Button x:Name="openReports" Content="Open Reports" Style="{StaticResource Btn}"/></StackPanel></GroupBox></StackPanel></ScrollViewer><Grid Grid.Column="1"><Grid.RowDefinitions><RowDefinition Height="360"/><RowDefinition Height="360"/><RowDefinition Height="Auto"/><RowDefinition Height="155"/></Grid.RowDefinitions><TabControl Grid.Row="0" Margin="6" Background="#1e1e2e"><TabItem Header="Windows"><ScrollViewer><UniformGrid x:Name="win" Columns="2" Rows="5" Margin="8" VerticalAlignment="Top"/></ScrollViewer></TabItem><TabItem Header="Edge"><ScrollViewer><UniformGrid x:Name="edge" Columns="2" Rows="5" Margin="8" VerticalAlignment="Top"/></ScrollViewer></TabItem><TabItem Header="Edge AI"><Grid Margin="8"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Orientation="Horizontal"><ComboBox x:Name="profile" Width="140"/><Button x:Name="profileApply" Content="Load Profile" Style="{StaticResource Btn}"/><CheckBox x:Name="blockAi" Content="Block popular AI sites" IsChecked="True"/></StackPanel><ScrollViewer Grid.Row="1"><UniformGrid x:Name="ai" Columns="2" Rows="3" VerticalAlignment="Top"/></ScrollViewer></Grid></TabItem><TabItem Header="Website Management"><Grid Margin="8" MinHeight="296"><Grid.RowDefinitions><RowDefinition Height="230"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><GroupBox Header="Blocked URLs"><DockPanel><WrapPanel DockPanel.Dock="Top"><Button x:Name="addBlock" Content="Add URL" Style="{StaticResource Btn}"/><Button x:Name="removeBlock" Content="Remove Selected" Style="{StaticResource Btn}"/><Button x:Name="importBlock" Content="Import TXT" Style="{StaticResource Btn}"/><Button x:Name="exportBlock" Content="Export TXT" Style="{StaticResource Btn}"/></WrapPanel><DataGrid x:Name="blockGrid" SelectionMode="Extended" IsReadOnly="False" MinHeight="160" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"><DataGrid.Columns><DataGridCheckBoxColumn Header="Desired" Binding="{Binding Desired,Mode=TwoWay}" Width="70"/><DataGridTextColumn Header="URL" Binding="{Binding URL}" Width="260" MinWidth="200" IsReadOnly="True"/><DataGridCheckBoxColumn Header="Current" Binding="{Binding Current}" Width="70" IsReadOnly="True"/><DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="85" IsReadOnly="True"/><DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="110" IsReadOnly="True"/></DataGrid.Columns></DataGrid></DockPanel></GroupBox><GroupBox Grid.Column="1" Header="Allowed URLs"><DockPanel><WrapPanel DockPanel.Dock="Top"><Button x:Name="addAllow" Content="Add URL" Style="{StaticResource Btn}"/><Button x:Name="removeAllow" Content="Remove Selected" Style="{StaticResource Btn}"/><Button x:Name="importAllow" Content="Import TXT" Style="{StaticResource Btn}"/><Button x:Name="exportAllow" Content="Export TXT" Style="{StaticResource Btn}"/></WrapPanel><DataGrid x:Name="allowGrid" SelectionMode="Extended" IsReadOnly="False" MinHeight="160" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"><DataGrid.Columns><DataGridCheckBoxColumn Header="Desired" Binding="{Binding Desired,Mode=TwoWay}" Width="70"/><DataGridTextColumn Header="URL" Binding="{Binding URL}" Width="260" MinWidth="200" IsReadOnly="True"/><DataGridCheckBoxColumn Header="Current" Binding="{Binding Current}" Width="70" IsReadOnly="True"/><DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="85" IsReadOnly="True"/><DataGridTextColumn Header="Source" Binding="{Binding Source}" Width="110" IsReadOnly="True"/></DataGrid.Columns></DataGrid></DockPanel></GroupBox></Grid><Grid Grid.Row="1" Margin="8,6"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="webSummary" Grid.Row="0" Text="No pending website changes" Foreground="#f9e2af" HorizontalAlignment="Center" Margin="0,0,0,4"/><Button x:Name="refreshWeb" Grid.Row="1" Content="Refresh Lists" Style="{StaticResource Btn}" Width="125" Height="30" Padding="8,2" HorizontalAlignment="Center"/></Grid></Grid></TabItem></TabControl><GroupBox Grid.Row="1" Header="Current versus desired"><DataGrid x:Name="grid" IsReadOnly="True" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"><DataGrid.Columns><DataGridTextColumn Header="Target" Binding="{Binding Target}" Width="110" MinWidth="90"/><DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="100" MinWidth="80"/><DataGridTextColumn Header="Setting" Binding="{Binding Setting}" Width="260" MinWidth="200"/><DataGridTextColumn Header="Current" Binding="{Binding Current}" Width="190" MinWidth="140"/><DataGridTextColumn Header="Desired" Binding="{Binding Desired}" Width="190" MinWidth="140"/><DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="100" MinWidth="80"/><DataGridTextColumn Header="Notes" Binding="{Binding Notes}" Width="320" MinWidth="220"/></DataGrid.Columns></DataGrid></GroupBox><WrapPanel Grid.Row="2" HorizontalAlignment="Center"><Button x:Name="audit" Content="Audit / Preview" Style="{StaticResource Btn}"/><Button x:Name="apply" Content="Apply Selected" Style="{StaticResource Btn}"/><Button x:Name="backup" Content="Backup Current" Style="{StaticResource Btn}"/><Button x:Name="load" Content="Load JSON" Style="{StaticResource Btn}"/><Button x:Name="compare" Content="Compare JSON" Style="{StaticResource Btn}"/><Button x:Name="restore" Content="Restore JSON" Style="{StaticResource Btn}"/></WrapPanel><GroupBox Grid.Row="3" Header="Output Log"><TextBox x:Name="log" IsReadOnly="True" FontFamily="Consolas" VerticalScrollBarVisibility="Auto"/></GroupBox></Grid></Grid></ScrollViewer></DockPanel></Window>
"@
$r=[Xml.XmlNodeReader]::new($x);$w=[Windows.Markup.XamlReader]::Load($r);$names=@('status','refresh','export','accounts','users','dns','dnsAck','applyDns','storeState','storeBlock','storeCheck','storeUnblock','openLogs','openBackups','openReports','win','edge','ai','profile','profileApply','blockAi','blockGrid','allowGrid','addBlock','removeBlock','importBlock','exportBlock','addAllow','removeAllow','importAllow','exportAllow','refreshWeb','webSummary','grid','audit','apply','backup','load','compare','restore','log');foreach($n in $names){$script:Ui[$n]=$w.FindName($n);if($null -eq $script:Ui[$n]){throw"Missing control $n"}}
foreach($c in $Catalog){$cb=New-Object Windows.Controls.CheckBox;$cb.Name="opt_$($c.Id)";$cb.Content=$c.Name;$cb.IsChecked=$c.Default;$cb.ToolTip=$c.Note;$script:Ui[$cb.Name]=$cb;if($c.Cat -eq 'Windows'){[void]$script:Ui.win.Children.Add($cb)}elseif($c.Cat -eq 'Edge AI'){[void]$script:Ui.ai.Children.Add($cb)}else{[void]$script:Ui.edge.Children.Add($cb)}}
$Dns.Keys|%{[void]$script:Ui.dns.Items.Add($_)};$script:Ui.dns.SelectedIndex=0;@('Kid Safe','Student','Custom')|%{[void]$script:Ui.profile.Items.Add($_)};$script:Ui.profile.SelectedIndex=0
$script:Ui.addBlock.Add_Click({try{Add-WebsiteEntry Blocked}catch{Log $_.Exception.Message ERROR}});$script:Ui.removeBlock.Add_Click({try{Remove-WebsiteEntry Blocked}catch{Log $_.Exception.Message ERROR}});$script:Ui.importBlock.Add_Click({try{Import-WebsiteText Blocked}catch{Log $_.Exception.Message ERROR}});$script:Ui.exportBlock.Add_Click({try{Export-WebsiteText Blocked}catch{Log $_.Exception.Message ERROR}});$script:Ui.addAllow.Add_Click({try{Add-WebsiteEntry Allowed}catch{Log $_.Exception.Message ERROR}});$script:Ui.removeAllow.Add_Click({try{Remove-WebsiteEntry Allowed}catch{Log $_.Exception.Message ERROR}});$script:Ui.importAllow.Add_Click({try{Import-WebsiteText Allowed}catch{Log $_.Exception.Message ERROR}});$script:Ui.exportAllow.Add_Click({try{Export-WebsiteText Allowed}catch{Log $_.Exception.Message ERROR}});$script:Ui.refreshWeb.Add_Click({try{Refresh-WebsiteGrid}catch{Log $_.Exception.Message ERROR}});$script:Ui.blockGrid.Add_CellEditEnding({$script:Ui.blockGrid.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,[action]{try{Update-WebsiteStatuses}catch{Log $_.Exception.Message DEBUG}})|Out-Null});$script:Ui.allowGrid.Add_CellEditEnding({$script:Ui.allowGrid.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,[action]{try{Update-WebsiteStatuses}catch{Log $_.Exception.Message DEBUG}})|Out-Null});
$script:Ui.storeBlock.Add_Click({try{Enable-StoreBlock}catch{Log $_.Exception.Message ERROR;Msg $_.Exception.Message 'Store block failed' Error}});$script:Ui.storeCheck.Add_Click({try{Test-StoreBlock}catch{Log $_.Exception.Message ERROR}});$script:Ui.storeUnblock.Add_Click({try{Disable-StoreBlock}catch{Log $_.Exception.Message ERROR}});
$script:Ui.users.Add_Click({try{Refresh-Accounts}catch{Log $_.Exception.Message ERROR}});$script:Ui.refresh.Add_Click({try{Refresh-Accounts;Refresh-Grid}catch{Log $_.Exception.Message ERROR}});$script:Ui.audit.Add_Click({try{Refresh-Grid}catch{Log $_.Exception.Message ERROR}});$script:Ui.apply.Add_Click({try{Apply-Policy}catch{Log $_.Exception.Message ERROR;Msg $_.Exception.Message Error Error}});$script:Ui.backup.Add_Click({try{[void](Backup-Now)}catch{Log $_.Exception.Message ERROR}});$script:Ui.load.Add_Click({try{[void](Load-Backup)}catch{Log $_.Exception.Message ERROR}});$script:Ui.compare.Add_Click({try{Compare-Backup}catch{Log $_.Exception.Message ERROR}});$script:Ui.restore.Add_Click({try{Restore-Backup}catch{Log $_.Exception.Message ERROR}});$script:Ui.applyDns.Add_Click({try{Apply-Dns}catch{Log $_.Exception.Message ERROR}});$script:Ui.export.Add_Click({try{Export-Xlsx}catch{Log $_.Exception.Message ERROR;Msg $_.Exception.Message 'Export failed' Error}});$script:Ui.profileApply.Add_Click({try{Set-Profile ([string]$script:Ui.profile.SelectedItem)}catch{Log $_.Exception.Message ERROR}})
foreach($pair in @(@('openLogs',$Logs),@('openBackups',$Backups),@('openReports',$Reports))){$script:Ui[$pair[0]].Tag=$pair[1];$script:Ui[$pair[0]].Add_Click({param($s,$e)Start-Process explorer.exe $s.Tag})}
try{Refresh-Accounts;try{Test-StoreBlock}catch{Log "Store status check skipped: $($_.Exception.Message)" WARN};Log "$Product v$Version initialized." SUCCESS}catch{Log $_.Exception.Message WARN};$w.ShowDialog()|Out-Null
