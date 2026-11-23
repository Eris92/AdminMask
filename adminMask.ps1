#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Start with Windows PowerShell in STA mode.'
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$root = $PSScriptRoot
. (Join-Path $root 'scripts/AdminMask.Common.ps1')
Initialize-AdminMaskConfig -ProjectRoot $root

$form = New-Object Windows.Forms.Form
$form.Text = 'AdminMask - OU GUI'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(1050,720)
$form.MinimumSize = New-Object Drawing.Size(880,600)
$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

function New-Page([string]$name) {
    $page = New-Object Windows.Forms.TabPage
    $page.Text = $name
    $tabs.TabPages.Add($page) | Out-Null
    return $page
}
function New-Button([Windows.Forms.Control]$parent,[string]$name,[int]$x,[int]$y,[int]$width=120) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $name
    $button.Location = New-Object Drawing.Point($x,$y)
    $button.Size = New-Object Drawing.Size($width,29)
    $button.Anchor = 'Top,Left'
    $parent.Controls.Add($button)
    return $button
}
function New-Label([Windows.Forms.Control]$parent,[string]$name,[int]$x,[int]$y,[int]$width=100) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $name
    $label.Location = New-Object Drawing.Point($x,$y)
    $label.Size = New-Object Drawing.Size($width,22)
    $parent.Controls.Add($label)
    return $label
}
function New-Textbox([Windows.Forms.Control]$parent,[int]$x,[int]$y,[int]$width=200) {
    $input = New-Object Windows.Forms.TextBox
    $input.Location = New-Object Drawing.Point($x,$y)
    $input.Size = New-Object Drawing.Size($width,25)
    $parent.Controls.Add($input)
    return $input
}
function New-Combo([Windows.Forms.Control]$parent,[int]$x,[int]$y,[int]$width=125) {
    $combo = New-Object Windows.Forms.ComboBox
    $combo.Location = New-Object Drawing.Point($x,$y)
    $combo.Size = New-Object Drawing.Size($width,26)
    $combo.DropDownStyle = 'DropDownList'
    $parent.Controls.Add($combo)
    return $combo
}
function Show-Failure([string]$message) {
    [Windows.Forms.MessageBox]::Show($message,'AdminMask',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
function Confirm-Action([string]$message) {
    return ([Windows.Forms.MessageBox]::Show($message,'AdminMask',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question) -eq 'Yes')
}
function New-Grid([Windows.Forms.Control]$parent) {
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Location = New-Object Drawing.Point(12,92)
    $grid.Size = New-Object Drawing.Size(990,450)
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.ReadOnly = $true
    $grid.MultiSelect = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AllowUserToAddRows = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $parent.Controls.Add($grid)
    return $grid
}
function Set-GridData([Windows.Forms.DataGridView]$grid,[object[]]$rows,[string[]]$columns) {
    $table = New-Object System.Data.DataTable
    foreach ($c in $columns) { $null = $table.Columns.Add($c,[string]) }
    foreach ($item in $rows) {
        $record = $table.NewRow()
        foreach ($c in $columns) { $record[$c] = [string]$item.$c }
        $table.Rows.Add($record)
    }
    $grid.DataSource = $table
}
function Selected-GridValue([Windows.Forms.DataGridView]$grid,[string]$column) {
    if ($grid.SelectedRows.Count -lt 1) { return '' }
    return [string]$grid.SelectedRows[0].Cells[$column].Value
}
function Invoke-External([string]$scriptPath,[string[]]$arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = "$PSHOME\powershell.exe"
    $psi.Arguments = '-NoProfile -File "' + $scriptPath + '" ' + ($arguments -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $msg = ($stdout + [Environment]::NewLine + $stderr).Trim()
    if ($process.ExitCode -ne 0) { Show-Failure $msg } else {
        [Windows.Forms.MessageBox]::Show($msg,'AdminMask') | Out-Null
    }
}
$hostsPage = New-Page 'Hosts'
$ouPage = New-Page 'AD OUs'
$maskPage = New-Page 'Mask Calculator'
$opsPage = New-Page 'Operations'

New-Label $hostsPage 'Host' 12 16 45 | Out-Null
$hostInput = New-Textbox $hostsPage 62 12 160
New-Label $hostsPage 'Maska' 234 16 50 | Out-Null
$maskCombo = New-Combo $hostsPage 290 12 115
New-Label $hostsPage 'Tier' 416 16 34 | Out-Null
$tierCombo = New-Combo $hostsPage 455 12 95
foreach ($tier in @('0','1','2','3')) { $null = $tierCombo.Items.Add($tier) }
$tierCombo.SelectedIndex = 0
New-Label $hostsPage 'OU' 560 16 30 | Out-Null
$ouCombo = New-Combo $hostsPage 593 12 375
$addHost = New-Button $hostsPage 'Add / Update' 12 52 130
$removeHost = New-Button $hostsPage 'Remove' 150 52 100
$reloadHost = New-Button $hostsPage 'Reload' 257 52 100
$hostGrid = New-Grid $hostsPage

function Refresh-OuCombo {
    $selected = [string]$ouCombo.Text
    $ouCombo.Items.Clear()
    $null = $ouCombo.Items.Add('')
    foreach ($dn in (Get-AdminMaskOus -ProjectRoot $root)) { $null = $ouCombo.Items.Add($dn) }
    if ($ouCombo.Items.Contains($selected)) { $ouCombo.SelectedItem = $selected } else { $ouCombo.SelectedIndex = 0 }
}
function Refresh-Hosts {
    Set-GridData $hostGrid (Get-AdminMaskHosts -ProjectRoot $root) @('Host','Maska','Tier','OU')
}
function Refresh-Roles {
    $maskCombo.Items.Clear()
    $null = $maskCombo.Items.Add('0')
    foreach ($role in (Get-AdminMaskRoles -ProjectRoot $root)) {
        if (-not $maskCombo.Items.Contains([string]$role.Value)) { $null = $maskCombo.Items.Add([string]$role.Value) }
    }
    $maskCombo.SelectedIndex = 0
}
$hostGrid.Add_SelectionChanged({
    if ($hostGrid.SelectedRows.Count -ne 1) { return }
    $hostInput.Text = Selected-GridValue $hostGrid 'Host'
    foreach ($pair in @(@($maskCombo,'Maska'),@($tierCombo,'Tier'),@($ouCombo,'OU'))) {
        $value = Selected-GridValue $hostGrid $pair[1]
        if ($pair[0].Items.Contains($value)) { $pair[0].SelectedItem = $value }
    }
})
$reloadHost.Add_Click({ Refresh-Hosts; Refresh-Roles; Refresh-OuCombo })
$addHost.Add_Click({
    try {
        $hostName = $hostInput.Text.Trim()
        if ($hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,253}$') { throw 'Invalid hostname.' }
        $mask = Test-AdminMaskValue -Value ([string]$maskCombo.Text) -Roles (Get-AdminMaskRoles -ProjectRoot $root)
        $items = @(Get-AdminMaskHosts -ProjectRoot $root | Where-Object { $_.Host -ine $hostName })
        $items += [pscustomobject]@{Host=$hostName;Maska=[string]$mask;Tier=[string]$tierCombo.Text;OU=[string]$ouCombo.Text}
        Save-AdminMaskHosts -ProjectRoot $root -Items $items
        Refresh-Hosts
    } catch { Show-Failure $_.Exception.Message }
})
$removeHost.Add_Click({
    try {
        $hostName = Selected-GridValue $hostGrid 'Host'
        if (-not $hostName) { return }
        if (-not (Confirm-Action "Remove host $hostName from CSV?")) { return }
        $items = @(Get-AdminMaskHosts -ProjectRoot $root | Where-Object { $_.Host -ine $hostName })
        Save-AdminMaskHosts -ProjectRoot $root -Items $items
        Refresh-Hosts
    } catch { Show-Failure $_.Exception.Message }
})
New-Label $ouPage 'OU distinguished name' 12 16 180 | Out-Null
$ouInput = New-Textbox $ouPage 195 12 775
$addOu = New-Button $ouPage 'Add / Update' 12 52 130
$removeOu = New-Button $ouPage 'Remove' 150 52 100
$discoverOu = New-Button $ouPage 'Discover recursive' 258 52 170
$reloadOu = New-Button $ouPage 'Reload' 437 52 100
$ouGrid = New-Grid $ouPage
function Refresh-Ous {
    $rows = @(Get-AdminMaskOus -ProjectRoot $root | ForEach-Object { [pscustomobject]@{OU = $_} })
    Set-GridData $ouGrid $rows @('OU')
    Refresh-OuCombo
}
$ouGrid.Add_SelectionChanged({
    $ouInput.Text = Selected-GridValue $ouGrid 'OU'
})
$reloadOu.Add_Click({Refresh-Ous})
$addOu.Add_Click({
    try {
        $dn = $ouInput.Text.Trim()
        Test-AdminMaskDn $dn
        $old = Selected-GridValue $ouGrid 'OU'
        $items = @(Get-AdminMaskOus -ProjectRoot $root | Where-Object { $_ -ine $old -or -not $old })
        $items += $dn
        Save-AdminMaskOus -ProjectRoot $root -Items $items
        Refresh-Ous
    } catch { Show-Failure $_.Exception.Message }
})
$removeOu.Add_Click({
    try {
        $dn = Selected-GridValue $ouGrid 'OU'
        if (-not $dn -or -not (Confirm-Action "Remove OU from configuration?`n$dn")) { return }
        $items = @(Get-AdminMaskOus -ProjectRoot $root | Where-Object { $_ -ine $dn })
        Save-AdminMaskOus -ProjectRoot $root -Items $items
        Refresh-Ous
    } catch { Show-Failure $_.Exception.Message }
})
$discoverOu.Add_Click({
    try {
        $dn = $ouInput.Text.Trim()
        Test-AdminMaskDn $dn
        $raw = & (Join-Path $root 'scripts/AdminMask-Inventory.ps1') -SearchBase @($dn) -Recursive
        $known = @(Get-AdminMaskHosts -ProjectRoot $root)
        $added = 0
        foreach ($computer in $raw) {
            if (@($known | Where-Object { $_.Host -ieq $computer.Host }).Count -gt 0) { continue }
            $known += [pscustomobject]@{Host=$computer.Host;Maska='0';Tier='2';OU=$dn}
            $added++
        }
        if ($added -gt 0 -and (Confirm-Action "Import $added new hosts? Existing records remain unchanged.")) {
            Save-AdminMaskHosts -ProjectRoot $root -Items $known
            Refresh-Hosts
        }
        [Windows.Forms.MessageBox]::Show("Discovered $(@($raw).Count), new $added.") | Out-Null
    } catch { Show-Failure $_.Exception.Message }
})

$maskValue = New-Label $maskPage 'Mask: 0' 12 15 320
$maskValue.Font = New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold)
$rolePanel = New-Object Windows.Forms.FlowLayoutPanel
$rolePanel.Location = New-Object Drawing.Point(12,55)
$rolePanel.Size = New-Object Drawing.Size(970,410)
$rolePanel.Anchor = 'Top,Bottom,Left,Right'
$rolePanel.FlowDirection = 'TopDown'
$rolePanel.WrapContents = $false
$rolePanel.AutoScroll = $true
$maskPage.Controls.Add($rolePanel)
function Update-Calculator {
    $value = 0
    foreach ($c in $rolePanel.Controls) {
        if ($c -is [Windows.Forms.CheckBox] -and $c.Checked) { $value = $value -bor [int]$c.Tag }
    }
    $maskValue.Text = "Mask: $value"
}
function Refresh-Calculator {
    $rolePanel.Controls.Clear()
    foreach ($role in (Get-AdminMaskRoles -ProjectRoot $root)) {
        $value = [int]$role.Value
        if ($value -eq 0) { continue }
        $c = New-Object Windows.Forms.CheckBox
        $c.Text = "$($role.Name) ($value)"
        $c.Tag = $value
        $c.Width = 400
        $c.Add_CheckedChanged({Update-Calculator})
        $rolePanel.Controls.Add($c)
    }
    Update-Calculator
}
$copyMask = New-Button $maskPage 'Copy mask' 12 480 120
$copyMask.Anchor = 'Bottom,Left'
$copyMask.Add_Click({
    [Windows.Forms.Clipboard]::SetText(($maskValue.Text -replace '^Mask: ',''))
})

$opsText = New-Object Windows.Forms.TextBox
$opsText.Location = New-Object Drawing.Point(12,16)
$opsText.Size = New-Object Drawing.Size(950,110)
$opsText.Multiline = $true
$opsText.ReadOnly = $true
$opsText.Text = "AD discovery and check are read-only.
Apply generates a validation report only; no AD changes are performed.
Effective GPO check and AD write mapping require original implementation details."
$opsText.Anchor = 'Top,Left,Right'
$opsPage.Controls.Add($opsText)
$checkBtn = New-Button $opsPage 'Check AD' 12 145 150
$applyBtn = New-Button $opsPage 'Apply (plan only)' 175 145 175
$folderBtn = New-Button $opsPage 'Open config folder' 363 145 165
$checkBtn.Add_Click({
    try { Invoke-External (Join-Path $root 'scripts/adminMask_Check.ps1') @() } catch { Show-Failure $_.Exception.Message }
})
$applyBtn.Add_Click({
    try { Invoke-External (Join-Path $root 'scripts/adminMask_Run.ps1') @() } catch { Show-Failure $_.Exception.Message }
})
$folderBtn.Add_Click({ Start-Process explorer.exe (Join-Path $root 'config') })
Refresh-Roles
Refresh-Ous
Refresh-Hosts
Refresh-Calculator
[void]$form.ShowDialog()
