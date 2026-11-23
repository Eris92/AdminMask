#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Launch Windows PowerShell in STA mode.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root = $PSScriptRoot
. (Join-Path $root 'scripts/AdminMask.Common.ps1')
Initialize-AdminMaskConfig -ProjectRoot $root
$script:hostRows = @()
$script:roles = @()
$script:ignoreFilters = $false
$script:selectedComputer = ''

function Make-Button([Windows.Forms.Control]$parent,[string]$caption,[int]$x,[int]$y,[int]$w=125) {
    $b=New-Object Windows.Forms.Button
    $b.Text=$caption
    $b.SetBounds($x,$y,$w,28)
    $parent.Controls.Add($b)
    return $b
}
function Make-Label([Windows.Forms.Control]$parent,[string]$caption,[int]$x,[int]$y,[int]$w=70) {
    $l=New-Object Windows.Forms.Label
    $l.Text=$caption
    $l.SetBounds($x,$y,$w,22)
    $parent.Controls.Add($l)
    return $l
}
function Make-Text([Windows.Forms.Control]$parent,[int]$x,[int]$y,[int]$w=160) {
    $t=New-Object Windows.Forms.TextBox
    $t.SetBounds($x,$y,$w,25)
    $parent.Controls.Add($t)
    return $t
}
function Make-Combo([Windows.Forms.Control]$parent,[int]$x,[int]$y,[int]$w=130) {
    $c=New-Object Windows.Forms.ComboBox
    $c.DropDownStyle='DropDownList'
    $c.IntegralHeight=$false
    $c.DropDownHeight=260
    $c.SetBounds($x,$y,$w,25)
    $parent.Controls.Add($c)
    return $c
}
function Fail([string]$message) {
    [Windows.Forms.MessageBox]::Show($message,'AdminMask',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
function Confirm([string]$message) {
    return [Windows.Forms.MessageBox]::Show($message,'AdminMask','YesNo','Question') -eq 'Yes'
}
function Select-Combo([Windows.Forms.ComboBox]$combo,[string]$wanted,[string]$fallback='All') {
    if ($combo.Items.Contains($wanted)) { $combo.SelectedItem=$wanted }
    elseif ($combo.Items.Contains($fallback)) { $combo.SelectedItem=$fallback }
    elseif ($combo.Items.Count -gt 0) { $combo.SelectedIndex=0 }
}
function Reset-Combo([Windows.Forms.ComboBox]$combo,[object[]]$items,[string]$fallback='All') {
    $old=[string]$combo.SelectedItem
    $combo.Items.Clear()
    foreach ($i in $items) { [void]$combo.Items.Add([string]$i) }
    Select-Combo $combo $old $fallback
}
function Set-PageLayout {
    param([Windows.Forms.TabPage]$Page, [Windows.Forms.Control]$Header, [Windows.Forms.Control]$Body, [int]$HeaderHeight)
    $Page.Controls.Remove($Header)
    $Page.Controls.Remove($Body)
    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 2
    $layout.Margin = New-Object Windows.Forms.Padding(0)
    $layout.Padding = New-Object Windows.Forms.Padding(0)
    $layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,[single]$HeaderHeight))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100))) | Out-Null
    $Header.Dock = 'Fill'
    $Body.Dock = 'Fill'
    $layout.Controls.Add($Header,0,0)
    $layout.Controls.Add($Body,0,1)
    $Page.Controls.Add($layout)
}
function New-Grid([Windows.Forms.Control]$parent) {
    $g=New-Object Windows.Forms.DataGridView
    $g.Dock='Fill'
    $g.ReadOnly=$true
    $g.MultiSelect=$false
    $g.SelectionMode='FullRowSelect'
    $g.AllowUserToAddRows=$false
    $g.AllowUserToDeleteRows=$false
    $g.AutoSizeColumnsMode='Fill'
    $g.RowHeadersVisible=$false
    $g.BackgroundColor=[Drawing.Color]::White
    $parent.Controls.Add($g)
    return $g
}
function Set-Grid([Windows.Forms.DataGridView]$grid,[object[]]$rows,[string[]]$cols) {
    $dt=New-Object System.Data.DataTable
    foreach($c in $cols){[void]$dt.Columns.Add($c,[string])}
    foreach($item in $rows) {
        $r=$dt.NewRow()
        foreach($c in $cols){$r[$c]=[string]$item.$c}
        $dt.Rows.Add($r)
    }
    $grid.DataSource=$dt
    $grid.ClearSelection()
}
function Grid-Value([Windows.Forms.DataGridView]$grid,[string]$column) {
    if ($grid.SelectedRows.Count -ne 1) { return '' }
    return [string]$grid.SelectedRows[0].Cells[$column].Value
}
function Run-Check([string]$mode,[string]$hostName='') {
    try {
        $script=Join-Path $root 'scripts/adminMask_Check.ps1'
        $output=@(& $script -ProjectRoot $root -Mode $mode -HostName $hostName 2>&1 | Out-String -Width 220)
        if ($output.Count -eq 0 -or [string]::IsNullOrWhiteSpace($output[0])) { $output=@('No records found.') }
        $outputBox.Text=($output -join [Environment]::NewLine)
        $tabs.SelectedTab=$opsPage
    } catch { Fail $_.Exception.Message }
}

$form=New-Object Windows.Forms.Form
$form.Text='AdminMask - OU GUI'
$form.StartPosition='CenterScreen'
$form.ClientSize=New-Object Drawing.Size(1100,720)
$form.MinimumSize=New-Object Drawing.Size(990,620)
$form.AutoScroll=$false
$form.KeyPreview=$false
$tabs=New-Object Windows.Forms.TabControl
$tabs.Dock='Fill'
$form.Controls.Add($tabs)
function New-Page([string]$caption) {
    $p=New-Object Windows.Forms.TabPage
    $p.Text=$caption
    $p.AutoScroll=$false
    [void]$tabs.TabPages.Add($p)
    return $p
}
$hostsPage=New-Page 'Hosts'
$ouPage=New-Page 'AD OUs'
$calcPage=New-Page 'Mask Calculator'
$opsPage=New-Page 'Operations'

# Hosts: separate edit controls and filtering controls
$hostHead=New-Object Windows.Forms.Panel
$hostHead.Dock='Top'
$hostHead.Height=139
$hostsPage.Controls.Add($hostHead)
$hostsGrid=New-Grid $hostsPage
Set-PageLayout -Page $hostsPage -Header $hostHead -Body $hostsGrid -HeaderHeight 139

Make-Label $hostHead 'Host' 12 12 45 | Out-Null
$hostName=Make-Text $hostHead 62 8 150
Make-Label $hostHead 'Mask' 223 12 42 | Out-Null
$editMask=Make-Combo $hostHead 267 8 140
Make-Label $hostHead 'Tier' 418 12 35 | Out-Null
$editTier=Make-Combo $hostHead 454 8 95
Reset-Combo $editTier @('0','1','2') '2'
Make-Label $hostHead 'OU' 561 12 30 | Out-Null
$editOu=Make-Combo $hostHead 595 8 490
$hostSave=Make-Button $hostHead 'Add / Update' 12 44 130
$hostRemove=Make-Button $hostHead 'Remove' 150 44 105
$hostReload=Make-Button $hostHead 'Reload' 263 44 105
$hostCheck=Make-Button $hostHead 'Check selected AD' 376 44 155

Make-Label $hostHead 'FILTERS' 12 100 62 | Out-Null
Make-Label $hostHead 'Host' 78 100 38 | Out-Null
$filterHost=Make-Text $hostHead 118 96 160
Make-Label $hostHead 'Mask' 289 100 42 | Out-Null
$filterMask=Make-Combo $hostHead 333 96 130
Make-Label $hostHead 'Tier' 476 100 32 | Out-Null
$filterTier=Make-Combo $hostHead 509 96 100
Make-Label $hostHead 'OU' 619 100 24 | Out-Null
$filterOu=Make-Combo $hostHead 647 96 330
$resetFilters=Make-Button $hostHead 'Clear' 984 96 98

function Refresh-Hosts {
    $script:hostRows=@(Get-AdminMaskHosts -ProjectRoot $root)
    Refresh-HostFilters
}
function Apply-HostFilters {
    if ($script:ignoreFilters) { return }
    $pattern=$filterHost.Text.Trim()
    $mask=[string]$filterMask.SelectedItem
    $tier=[string]$filterTier.SelectedItem
    $ou=[string]$filterOu.SelectedItem
    $rows=@($script:hostRows | Where-Object {
        (!$pattern -or $_.Host.IndexOf($pattern,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and
        (!$mask -or $mask -eq 'All' -or [string]$_.Maska -eq $mask) -and
        (!$tier -or $tier -eq 'All' -or [string]$_.Tier -eq $tier) -and
        (!$ou -or $ou -eq 'All' -or [string]$_.OU -eq $ou)
    })
    Set-Grid $hostsGrid $rows @('Host','Maska','Tier','OU')
    $script:selectedComputer = ''
    $form.Text="AdminMask - OU GUI | Hosts: $($rows.Count) / $($script:hostRows.Count)"
}
function Refresh-HostFilters {
    $script:ignoreFilters=$true
    try {
        $maskValues=@('All') + @($script:hostRows | ForEach-Object { [string]$_.Maska } | Sort-Object -Unique)
        $ouValues=@('All') + @(Get-AdminMaskOus -ProjectRoot $root) + @($script:hostRows | ForEach-Object { [string]$_.OU } | Where-Object { $_ } | Sort-Object -Unique)
        Reset-Combo $filterMask @($maskValues | Select-Object -Unique)
        Reset-Combo $filterTier @('All','0','1','2')
        Reset-Combo $filterOu @($ouValues | Select-Object -Unique)
    } finally { $script:ignoreFilters=$false }
    Apply-HostFilters
}
function Refresh-Editor {
    $mask=[string]$editMask.Text
    $ou=[string]$editOu.Text
    $allMasks=@(Get-AdminMaskMaskOptions -Roles $script:roles)
    Reset-Combo $editMask $allMasks '0'
    if ($mask) { Select-Combo $editMask $mask '0' }
    Reset-Combo $editOu (@('All') + @(Get-AdminMaskOus -ProjectRoot $root)) 'All'
    if ($ou) { Select-Combo $editOu $ou 'All' }
}
$filterHost.Add_TextChanged({Apply-HostFilters})
$filterMask.Add_SelectedIndexChanged({Apply-HostFilters})
$filterTier.Add_SelectedIndexChanged({Apply-HostFilters})
$filterOu.Add_SelectedIndexChanged({Apply-HostFilters})
$resetFilters.Add_Click({
    $filterHost.Clear()
    Select-Combo $filterMask 'All'
    Select-Combo $filterTier 'All'
    Select-Combo $filterOu 'All'
    Apply-HostFilters
})
$hostReload.Add_Click({
    try {
        $script:roles=@(Get-AdminMaskRoles -ProjectRoot $root)
        Refresh-Editor
        Refresh-Hosts
        Refresh-Calculator
    } catch { Fail $_.Exception.Message }
})
$hostsGrid.Add_CellClick({
    if ($hostsGrid.SelectedRows.Count -ne 1) { return }
    $hostName.Text=Grid-Value $hostsGrid 'Host'
    $script:selectedComputer = $hostName.Text
    Select-Combo $editMask (Grid-Value $hostsGrid 'Maska') '0'
    Select-Combo $editTier (Grid-Value $hostsGrid 'Tier') '2'
    Select-Combo $editOu (Grid-Value $hostsGrid 'OU') 'All'
})
$hostSave.Add_Click({
    try {
        $name=$hostName.Text.Trim()
        if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,253}$') { throw 'Invalid host name.' }
        $mask=Test-AdminMaskValue -Value ([string]$editMask.SelectedItem) -Roles $script:roles
        $tier=[string]$editTier.SelectedItem
        if ($tier -notin @('0','1','2')) { throw 'Tier must be 0, 1 or 2.' }
        $ou=[string]$editOu.SelectedItem
        if ($ou -eq 'All') { $ou='' }
        $rows=@(Get-AdminMaskHosts -ProjectRoot $root | Where-Object {$_.Host -ine $name})
        $rows+= [pscustomobject]@{Host=$name;Maska=[string]$mask;Tier=$tier;OU=$ou}
        Save-AdminMaskHosts -ProjectRoot $root -Items $rows
        Refresh-Hosts
        $script:selectedComputer = $name
    } catch { Fail $_.Exception.Message }
})
$hostRemove.Add_Click({
    try {
        $name=Grid-Value $hostsGrid 'Host'
        if (-not $name -or -not (Confirm "Remove $name from CSV?")) { return }
        $rows=@(Get-AdminMaskHosts -ProjectRoot $root | Where-Object {$_.Host -ine $name})
        Save-AdminMaskHosts -ProjectRoot $root -Items $rows
        Refresh-Hosts
    } catch { Fail $_.Exception.Message }
})
$hostCheck.Add_Click({
    $name=Grid-Value $hostsGrid 'Host'
    if ($name) { Run-Check 'Inventory' $name }
    else { Fail 'Select a host first.' }
})

# OU management
$ouHead=New-Object Windows.Forms.Panel
$ouHead.Dock='Top'
$ouHead.Height=95
$ouPage.Controls.Add($ouHead)
$ouGrid=New-Grid $ouPage
Set-PageLayout -Page $ouPage -Header $ouHead -Body $ouGrid -HeaderHeight 95
Make-Label $ouHead 'OU DN' 12 14 65 | Out-Null
$ouInput=Make-Text $ouHead 80 10 905
$ouAdd=Make-Button $ouHead 'Add / Update' 12 49 130
$ouRemove=Make-Button $ouHead 'Remove' 150 49 110
$ouDiscover=Make-Button $ouHead 'Discover recursive' 268 49 168
$ouReload=Make-Button $ouHead 'Reload' 444 49 110
function Refresh-Ous {
    $rows=@(Get-AdminMaskOus -ProjectRoot $root | ForEach-Object {[pscustomobject]@{OU=$_}})
    Set-Grid $ouGrid $rows @('OU')
    Refresh-Editor
    Refresh-HostFilters
}
$ouGrid.Add_CellClick({$ouInput.Text=Grid-Value $ouGrid 'OU'})
$ouReload.Add_Click({try{Refresh-Ous}catch{Fail $_.Exception.Message}})
$ouAdd.Add_Click({
    try {
        $dn=$ouInput.Text.Trim()
        Test-AdminMaskDn $dn
        $old=Grid-Value $ouGrid 'OU'
        $items=@(Get-AdminMaskOus -ProjectRoot $root | Where-Object {(!$old) -or ($_ -ine $old)})
        $items+= $dn
        Save-AdminMaskOus -ProjectRoot $root -Items $items
        Refresh-Ous
    } catch {Fail $_.Exception.Message}
})
$ouRemove.Add_Click({
    try {
        $dn=Grid-Value $ouGrid 'OU'
        if (!$dn -or !(Confirm "Remove OU from config? $dn")) {return}
        $items=@(Get-AdminMaskOus -ProjectRoot $root | Where-Object {$_ -ine $dn})
        Save-AdminMaskOus -ProjectRoot $root -Items $items
        Refresh-Ous
    } catch {Fail $_.Exception.Message}
})
$ouDiscover.Add_Click({
    try {
        $dn=$ouInput.Text.Trim()
        Test-AdminMaskDn $dn
        $found=@(& (Join-Path $root 'scripts/AdminMask-Inventory.ps1') -SearchBase @($dn) -Recursive)
        $items=@(Get-AdminMaskHosts -ProjectRoot $root)
        $known=@{}
        foreach($h in $items){$known[[string]$h.Host]=$true}
        $added=0
        foreach($h in $found){
            if (!$known.ContainsKey([string]$h.Host)){
                $items+= [pscustomobject]@{Host=$h.Host;Maska='';Tier='';OU=$dn}
                $known[[string]$h.Host]=$true
                $added++
            }
        }
        if($added -gt 0 -and (Confirm "Import $added new hosts? Existing rows are preserved.")){
            Save-AdminMaskHosts -ProjectRoot $root -Items $items
            Refresh-Hosts
        }
        [Windows.Forms.MessageBox]::Show("Discovered $($found.Count) computers; new: $added.",'AdminMask')|Out-Null
    }catch{Fail $_.Exception.Message}
})

# Calculator + role additions
$calcHead=New-Object Windows.Forms.Panel
$calcHead.Dock='Top'
$calcHead.Height=114
$calcPage.Controls.Add($calcHead)
$calcPanel=New-Object Windows.Forms.FlowLayoutPanel
$calcPanel.Dock='Fill'
$calcPanel.FlowDirection='TopDown'
$calcPanel.WrapContents=$false
$calcPanel.AutoScroll=$true
$calcPage.Controls.Add($calcPanel)
Set-PageLayout -Page $calcPage -Header $calcHead -Body $calcPanel -HeaderHeight 124
$calcTitle=Make-Label $calcHead 'Mask: 0' 12 12 230
$calcTitle.Font=New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
$calcCopy=Make-Button $calcHead 'Copy mask' 235 8 120
$calcUse=Make-Button $calcHead 'Use for host' 362 8 130
Make-Label $calcHead 'New role' 12 69 75 | Out-Null
$newRoleName=Make-Text $calcHead 86 65 180
Make-Label $calcHead 'Bit' 275 69 32 | Out-Null
$newRoleBit=Make-Text $calcHead 310 65 90
$newRoleBit.ReadOnly=$true
$newRoleBit.TabStop=$false
$calcAdd=Make-Button $calcHead 'Add role' 410 64 115
$calcReload=Make-Button $calcHead 'Reload roles' 531 64 125
function Update-NextRoleBit {
    $highest = 0
    foreach ($role in $script:roles) {
        $current = [int]$role.Value
        if ($current -gt $highest) { $highest = $current }
    }
    $next = if ($highest -eq 0) { 1 } else { [long]$highest * 2 }
    if ($next -gt [int]::MaxValue) {
        $newRoleBit.Text = 'FULL'
        $calcAdd.Enabled = $false
    }
    else {
        $newRoleBit.Text = [string]$next
        $calcAdd.Enabled = $true
    }
}
function Calc-Value {
    $value=0
    foreach($control in $calcPanel.Controls){
        if($control -is [Windows.Forms.CheckBox] -and $control.Checked){$value=$value -bor [int]$control.Tag}
    }
    $calcTitle.Text="Mask: $value"
}
function Refresh-Calculator {
    $calcPanel.Controls.Clear()
    foreach($role in $script:roles) {
        $value=[int]$role.Value
        if($value -eq 0){continue}
        $c=New-Object Windows.Forms.CheckBox
        $c.Text="$($role.Name) ($value)"
        $c.Tag=$value
        $c.Width=650
        $c.Height=27
        $c.Add_CheckedChanged({Calc-Value})
        [void]$calcPanel.Controls.Add($c)
    }
    Calc-Value
    Update-NextRoleBit
}
$calcCopy.Add_Click({
    try{[Windows.Forms.Clipboard]::SetText($calcTitle.Text.Replace('Mask: ',''))}
    catch{Fail $_.Exception.Message}
})
$calcUse.Add_Click({
    try {
        $value = $calcTitle.Text.Replace('Mask: ','')
        Select-Combo $editMask $value '0'
        if ([string]$editMask.SelectedItem -ne $value) {
            throw "Calculated mask $value is missing from editor options."
        }
        $targetName = $script:selectedComputer
        if ([string]::IsNullOrWhiteSpace($targetName)) {
            $tabs.SelectedTab = $hostsPage
            [Windows.Forms.MessageBox]::Show('Mask selected in host editor. Select a host and click Add / Update to save.','AdminMask') | Out-Null
            return
        }
        $existing = @(Get-AdminMaskHosts -ProjectRoot $root | Where-Object { $_.Host -ieq $targetName })
        if ($existing.Count -ne 1) { throw "Host not found or duplicated in CSV: $targetName" }
        $previous = [string]$existing[0].Maska
        if (-not (Confirm "Update CSV mask for $targetName from '$previous' to '$value'? No AD/GPO change will be made.")) {
            $tabs.SelectedTab = $hostsPage
            return
        }
        $allRows = @(Get-AdminMaskHosts -ProjectRoot $root)
        foreach ($record in $allRows) {
            if ($record.Host -ieq $targetName) { $record.Maska = $value }
        }
        Save-AdminMaskHosts -ProjectRoot $root -Items $allRows
        Refresh-Hosts
        $tabs.SelectedTab = $hostsPage
    } catch { Fail $_.Exception.Message }
})
$calcAdd.Add_Click({
    try {
        $name=$newRoleName.Text.Trim()
        $bit=0
        if (-not [int]::TryParse($newRoleBit.Text.Trim(),[ref]$bit)) { throw 'Bit must be an integer.' }
        $items=@($script:roles)+@([pscustomobject]@{Name=$name;Value=$bit})
        Save-AdminMaskRoles -ProjectRoot $root -Items $items
        $script:roles=@(Get-AdminMaskRoles -ProjectRoot $root)
        Refresh-Calculator
        Refresh-Editor
        $newRoleName.Clear()
        Update-NextRoleBit
    }catch{Fail $_.Exception.Message}
})
$calcReload.Add_Click({
    try{
        $script:roles=@(Get-AdminMaskRoles -ProjectRoot $root)
        Refresh-Calculator
        Refresh-Editor
    }catch{Fail $_.Exception.Message}
})

# Operations: report output in a read-only textbox, no blocking MessageBox for long reports
$opsHead=New-Object Windows.Forms.Panel
$opsHead.Dock='Top'
$opsHead.Height=100
$opsPage.Controls.Add($opsHead)
$outputBox=New-Object Windows.Forms.TextBox
$outputBox.Multiline=$true
$outputBox.ReadOnly=$true
$outputBox.ScrollBars='Both'
$outputBox.WordWrap=$false
$outputBox.Dock='Fill'
$outputBox.Font=New-Object Drawing.Font('Consolas',9)
$opsPage.Controls.Add($outputBox)
Set-PageLayout -Page $opsPage -Header $opsHead -Body $outputBox -HeaderHeight 100
$opsInfo=Make-Label $opsHead 'Read-only checks. Linked GPOs are not proof of effective application; RSoP requires remote access and rights.' 12 10 1050
$opsAll=Make-Button $opsHead 'Check AD' 12 44 128
$opsLinks=Make-Button $opsHead 'Linked GPOs' 150 44 128
$opsRsop=Make-Button $opsHead 'RSoP (selected)' 289 44 148
$opsPlan=Make-Button $opsHead 'Apply (plan only)' 448 44 158
$opsOpen=Make-Button $opsHead 'Open config' 616 44 125
$opsAll.Add_Click({Run-Check 'Inventory'})
$opsLinks.Add_Click({Run-Check 'LinkedGpo'})
$opsRsop.Add_Click({
    $selectedComputer=Grid-Value $hostsGrid 'Host'
    if (!$selectedComputer) {Fail 'Select a host in Hosts first.';return}
    Run-Check 'Rsop' $selectedComputer
})
$opsPlan.Add_Click({
    try{
        $result=& (Join-Path $root 'scripts/adminMask_Run.ps1') -ProjectRoot $root 2>&1 | Out-String -Width 220
        $outputBox.Text=[string]$result
    }catch{Fail $_.Exception.Message}
})
$opsOpen.Add_Click({Start-Process explorer.exe -ArgumentList (Join-Path $root 'config')})

$script:roles=@(Get-AdminMaskRoles -ProjectRoot $root)
Refresh-Calculator
Refresh-Editor
Refresh-Ous
Refresh-Hosts
[void]$form.ShowDialog()
