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
. (Join-Path $root 'scripts/AdminMask.Directory.ps1')
Initialize-AdminMaskConfig -ProjectRoot $root
$script:hostRows = @()
$script:roles = @()
$script:ignoreFilters = $false
$script:selectedComputer = ''
$script:checkedHosts = @{}
$script:filterEmptyLabel = '[Empty]'
$script:renderingHosts = $false

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
    $g.ReadOnly=$false
    $g.MultiSelect=$false
    $g.SelectionMode='FullRowSelect'
    $g.AllowUserToAddRows=$false
    $g.AllowUserToDeleteRows=$false
    $g.AutoSizeColumnsMode='Fill'
    $g.RowHeadersVisible=$false
    $g.MultiSelect=$true
    $g.BackgroundColor=[Drawing.Color]::White
    $parent.Controls.Add($g)
    return $g
}
function Set-Grid([Windows.Forms.DataGridView]$grid,[object[]]$rows,[string[]]$cols) {
    $dt=New-Object System.Data.DataTable
    foreach($c in $cols){
        if ($c -eq 'Selected') { [void]$dt.Columns.Add($c,[bool]) }
        else { [void]$dt.Columns.Add($c,[string]) }
    }
    foreach($item in $rows) {
        $r=$dt.NewRow()
        foreach($c in $cols){
            if ($c -eq 'Selected') {$r[$c]=[bool]$item.Selected}
            else {$r[$c]=[string]$item.$c}
        }
        $dt.Rows.Add($r)
    }
    $grid.DataSource=$dt
    foreach ($column in $grid.Columns) { $column.ReadOnly = $true }
    $grid.ClearSelection()
}
function Format-AdminMaskRoles {
    param([string]$Mask,[object[]]$Roles)
    if ([string]::IsNullOrWhiteSpace($Mask)) { return '[Not configured]' }
    $number = 0
    if (-not [int]::TryParse($Mask,[ref]$number) -or $number -lt 0) { return '[Invalid mask]' }
    if ($number -eq 0) { return 'Default' }
    $labels = New-Object System.Collections.Generic.List[string]
    $covered = 0
    foreach ($role in $Roles) {
        $bit = [int]$role.Value
        if ($bit -le 0) { continue }
        if (($number -band $bit) -eq $bit) {
            $labels.Add([string]$role.Name)
            $covered = $covered -bor $bit
        }
    }
    if (($number -band (-bnot $covered)) -ne 0) {
        $labels.Add(('[Unknown bits: {0}]' -f ($number -band (-bnot $covered))))
    }
    return ($labels -join ', ')
}
function Grid-Value([Windows.Forms.DataGridView]$grid,[string]$column) {
    if ($grid.SelectedRows.Count -eq 1) {
        return [string]$grid.SelectedRows[0].Cells[$column].Value
    }
    if (-not [string]::IsNullOrWhiteSpace($script:selectedComputer)) {
        foreach ($row in $grid.Rows) {
            if ([string]$row.Cells['Host'].Value -eq $script:selectedComputer) {
                return [string]$row.Cells[$column].Value
            }
        }
    }
    return ''
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
$hostSync=Make-Button $hostHead 'Sync from AD' 540 44 140
$hostSync.Add_Click({try{Sync-HostsFromAD}catch{Fail $_.Exception.Message}})

Make-Label $hostHead 'FILTERS' 12 100 62 | Out-Null
Make-Label $hostHead 'Host' 78 100 38 | Out-Null
$filterHost=Make-Text $hostHead 118 96 160
Make-Label $hostHead 'Mask' 289 100 42 | Out-Null
$filterMask=Make-Combo $hostHead 333 96 130
Make-Label $hostHead 'Tier' 476 100 32 | Out-Null
$filterTier=Make-Combo $hostHead 509 96 100
Make-Label $hostHead 'OU' 619 100 24 | Out-Null
$filterOu=Make-Combo $hostHead 647 96 330
$hostSelectedLabel=Make-Label $hostHead 'Selected: 0' 705 49 260
$resetFilters=Make-Button $hostHead 'Clear' 984 96 98

function Refresh-Hosts {
    $script:hostRows=@(Get-AdminMaskHosts -ProjectRoot $root)
    Refresh-HostFilters
}
function Sync-HostsFromAD {
    $settings=Get-AdminMaskSettings -ProjectRoot $root
    if ([string]::IsNullOrWhiteSpace([string]$settings.MaskAttribute)) {
        throw 'Configure the actual AD computer mask attribute on the AD OUs tab first.'
    }
    $mappings=@(Get-AdminMaskOuMappings -ProjectRoot $root)
    if ($mappings.Count -eq 0) {throw 'Configure at least one OU.'}
    $rows=@(Get-AdminMaskHosts -ProjectRoot $root)
    $index=@{}
    foreach($record in $rows){$index[[string]$record.Host]=$record}
    $newCount=0
    $changed=0
    foreach($mapping in $mappings){
        $found=@(Get-AdminMaskDirectoryComputers -SearchBase ([string]$mapping.OU) -ProjectRoot $root -Recursive)
        foreach($adRecord in $found){
            $key=[string]$adRecord.Host
            if($index.ContainsKey($key)){
                $record=$index[$key]
                if ([string]$adRecord.Maska -ne '' -and $record.Maska -ne $adRecord.Maska) {
                    $record.Maska=[string]$adRecord.Maska
                    $changed++
                }
                if ([string]$adRecord.Tier -ne '' -and $record.Tier -ne $adRecord.Tier) {
                    $record.Tier=[string]$adRecord.Tier
                    $changed++
                }
                if ($record.OU -ne $mapping.OU){$record.OU=[string]$mapping.OU;$changed++}
            } else {
                $index[$key]=[pscustomobject]@{
                    Host=$key;Maska=[string]$adRecord.Maska;Tier=[string]$adRecord.Tier;OU=[string]$mapping.OU
                }
                $newCount++
            }
        }
    }
    if (($newCount+$changed) -gt 0) {
        if (Confirm "AD read completed. New: $newCount; changes: $changed. Save changes to hosts.csv?") {
            Save-AdminMaskHosts -ProjectRoot $root -Items @($index.Values)
        }
    }
    Refresh-Hosts
    [Windows.Forms.MessageBox]::Show("AD read completed. New: $newCount; changes: $changed.",'AdminMask')|Out-Null
}
function Get-CheckedHostNames {
    return @($script:checkedHosts.Keys | Where-Object { $script:checkedHosts[$_] } | Sort-Object)
}
function Refresh-HostCheckCount {
    $hostSelectedLabel.Text = 'Selected: ' + @(Get-CheckedHostNames).Count
}
function Apply-HostFilters {
    if ($script:ignoreFilters) { return }
    $pattern=$filterHost.Text.Trim()
    $mask=[string]$filterMask.SelectedItem
    $tier=[string]$filterTier.SelectedItem
    $ou=[string]$filterOu.SelectedItem
    $rows=@($script:hostRows | Where-Object {
        (!$pattern -or $_.Host.IndexOf($pattern,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and
        ($mask -eq 'All' -or ($mask -eq $script:filterEmptyLabel -and [string]::IsNullOrWhiteSpace([string]$_.Maska)) -or ($mask -ne $script:filterEmptyLabel -and [string]$_.Maska -eq $mask)) -and
        ($tier -eq 'All' -or ($tier -eq $script:filterEmptyLabel -and [string]::IsNullOrWhiteSpace([string]$_.Tier)) -or ($tier -ne $script:filterEmptyLabel -and [string]$_.Tier -eq $tier)) -and
        (!$ou -or $ou -eq 'All' -or [string]$_.OU -eq $ou)
    })
    $display = @($rows | ForEach-Object {
        [pscustomobject]@{
            Selected = [bool]$script:checkedHosts[[string]$_.Host]
            Host = [string]$_.Host
            Maska = [string]$_.Maska
            Roles = Format-AdminMaskRoles -Mask ([string]$_.Maska) -Roles $script:roles
            Tier = [string]$_.Tier
            OU = [string]$_.OU
        }
    })
    $script:renderingHosts = $true
    try {
        Set-Grid $hostsGrid $display @('Selected','Host','Maska','Roles','Tier','OU')
    } finally { $script:renderingHosts = $false }
    if ($hostsGrid.Columns['Selected'] -is [Windows.Forms.DataGridViewTextBoxColumn]) {
        $position = $hostsGrid.Columns['Selected'].Index
        $hostsGrid.Columns.RemoveAt($position)
        $checkColumn = New-Object Windows.Forms.DataGridViewCheckBoxColumn
        $checkColumn.Name = 'Selected'
        $checkColumn.DataPropertyName = 'Selected'
        $hostsGrid.Columns.Insert($position,$checkColumn)
    }
    $hostsGrid.Columns['Selected'].ReadOnly = $false
    $hostsGrid.Columns['Selected'].Width = 70
    $hostsGrid.Columns['Selected'].AutoSizeMode = 'None'
    $hostsGrid.Columns['Selected'].HeaderText = 'Select'
    Refresh-HostCheckCount
    $script:selectedComputer = ''
    $form.Text="AdminMask - OU GUI | Hosts: $($rows.Count) / $($script:hostRows.Count)"
}
function Refresh-HostFilters {
    $script:ignoreFilters=$true
    try {
        $maskValues=@('All',$script:filterEmptyLabel) + @($script:hostRows | ForEach-Object { [string]$_.Maska } | Where-Object { $_ -ne '' } | Sort-Object -Unique)
        $ouValues=@('All') + @(Get-AdminMaskOuMappings -ProjectRoot $root | ForEach-Object {$_.OU}) + @($script:hostRows | ForEach-Object { [string]$_.OU } | Where-Object { $_ } | Sort-Object -Unique)
        Reset-Combo $filterMask @($maskValues | Select-Object -Unique)
        Reset-Combo $filterTier @('All',$script:filterEmptyLabel,'0','1','2')
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
    Reset-Combo $editOu (@('All') + @(Get-AdminMaskOuMappings -ProjectRoot $root | ForEach-Object {$_.OU})) 'All'
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
$hostsGrid.Add_CurrentCellDirtyStateChanged({
    if ($hostsGrid.IsCurrentCellDirty -and $hostsGrid.CurrentCell.OwningColumn.Name -eq 'Selected') {
        $hostsGrid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
    }
})
$hostsGrid.Add_CellValueChanged({
    param($sender,$e)
    if ($script:renderingHosts -or $e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0) { return }
    if ($hostsGrid.Columns[$e.ColumnIndex].Name -ne 'Selected') { return }
    $row = $hostsGrid.Rows[$e.RowIndex]
    $name = [string]$row.Cells['Host'].Value
    if ($name) {
        $script:checkedHosts[$name] = [bool]$row.Cells['Selected'].Value
        Refresh-HostCheckCount
    }
})
$hostsGrid.Add_CellClick({
    param($sender,$e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0) { return }
    if ($hostsGrid.Columns[$e.ColumnIndex].Name -eq 'Selected') { return }
    $hostsGrid.Rows[$e.RowIndex].Selected = $true
    $hostName.Text=[string]$hostsGrid.Rows[$e.RowIndex].Cells['Host'].Value
    $script:selectedComputer = $hostName.Text
    Select-Combo $editMask ([string]$hostsGrid.Rows[$e.RowIndex].Cells['Maska'].Value) '0'
    Select-Combo $editTier ([string]$hostsGrid.Rows[$e.RowIndex].Cells['Tier'].Value) '2'
    Select-Combo $editOu ([string]$hostsGrid.Rows[$e.RowIndex].Cells['OU'].Value) 'All'
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
$ouHead.Height=137
$ouPage.Controls.Add($ouHead)
$ouGrid=New-Grid $ouPage
Set-PageLayout -Page $ouPage -Header $ouHead -Body $ouGrid -HeaderHeight 137
Make-Label $ouHead 'OU DN' 12 14 65 | Out-Null
$ouInput=Make-Text $ouHead 80 10 905
Make-Label $ouHead 'Tier' 12 49 55 | Out-Null
$ouTier=Make-Combo $ouHead 80 45 130
Reset-Combo $ouTier @('Unassigned','0','1','2') 'Unassigned'
Make-Label $ouHead 'Mask attribute' 230 49 105 | Out-Null
$maskAttribute=Make-Text $ouHead 342 45 220
$maskAttribute.Text=[string](Get-AdminMaskSettings -ProjectRoot $root).MaskAttribute
$saveAttribute=Make-Button $ouHead 'Save attribute' 575 44 130
$saveAttribute.Add_Click({
    try { Set-AdminMaskAttribute -ProjectRoot $root -Attribute $maskAttribute.Text }
    catch {Fail $_.Exception.Message}
})
$ouAdd=Make-Button $ouHead 'Add / Update' 12 93 130
$ouRemove=Make-Button $ouHead 'Remove' 150 93 110
$ouDiscover=Make-Button $ouHead 'Discover recursive' 268 93 168
$ouReload=Make-Button $ouHead 'Reload' 444 93 110
function Refresh-Ous {
    $rows=@(Get-AdminMaskOuMappings -ProjectRoot $root)
    Set-Grid $ouGrid $rows @('OU','Tier')
    Refresh-Editor
    Refresh-HostFilters
}
$ouGrid.Add_CellClick({
    $ouInput.Text=Grid-Value $ouGrid 'OU'
    $tierValue=Grid-Value $ouGrid 'Tier'
    if (!$tierValue) {$tierValue='Unassigned'}
    Select-Combo $ouTier $tierValue 'Unassigned'
})
$ouReload.Add_Click({try{Refresh-Ous}catch{Fail $_.Exception.Message}})
$ouAdd.Add_Click({
    try {
        $dn=$ouInput.Text.Trim()
        Test-AdminMaskDn $dn
        $old=Grid-Value $ouGrid 'OU'
        $tierValue=[string]$ouTier.SelectedItem
        if ($tierValue -eq 'Unassigned') {$tierValue=''}
        $items=@(Get-AdminMaskOuMappings -ProjectRoot $root | Where-Object {(!$old) -or ($_.OU -ine $old)})
        $items+= [pscustomobject]@{OU=$dn;Tier=$tierValue}
        Save-AdminMaskOuMappings -ProjectRoot $root -Items $items
        Refresh-Ous
    } catch {Fail $_.Exception.Message}
})
$ouRemove.Add_Click({
    try {
        $dn=Grid-Value $ouGrid 'OU'
        if (!$dn -or !(Confirm "Remove OU from config? $dn")) {return}
        $items=@(Get-AdminMaskOuMappings -ProjectRoot $root | Where-Object {$_.OU -ine $dn})
        Save-AdminMaskOuMappings -ProjectRoot $root -Items $items
        Refresh-Ous
    } catch {Fail $_.Exception.Message}
})
$ouDiscover.Text='Discover all OUs'
$ouDiscover.Add_Click({
    try {
        $found = @(Get-AdminMaskAllDirectoryComputers -ProjectRoot $root)
        $items = @(Get-AdminMaskHosts -ProjectRoot $root)
        $known = @{}
        foreach ($entry in $items) { $known[[string]$entry.Host] = $true }
        $added = 0
        foreach ($entry in $found) {
            if (-not $known.ContainsKey([string]$entry.Host)) {
                $items += [pscustomobject]@{
                    Host = [string]$entry.Host
                    Maska = [string]$entry.Maska
                    Tier = [string]$entry.Tier
                    OU = [string]$entry.OU
                }
                $known[[string]$entry.Host] = $true
                $added++
            }
        }
        if ($added -gt 0) {
            if (Confirm "Discovered $($found.Count) unique computers in all configured OUs. Import $added new hosts? Existing CSV records will not be overwritten.") {
                Save-AdminMaskHosts -ProjectRoot $root -Items $items
                Refresh-Hosts
            }
        }
        [Windows.Forms.MessageBox]::Show("Unique AD computers: $($found.Count). New hosts: $added. Existing hosts preserved.",'AdminMask') | Out-Null
    } catch { Fail $_.Exception.Message }
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
$calcPanel.Padding = New-Object Windows.Forms.Padding(16,18,8,8)
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
        $c.Font=New-Object Drawing.Font('Segoe UI',10)
        $c.Tag=$value
        $c.Width=580
        $c.Height=32
        $c.Margin=New-Object Windows.Forms.Padding(0,1,0,1)
        $c.AutoSize=$false
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

# Operations: AdminMask-focused checks with explicit evidence limitations.
$opsHead=New-Object Windows.Forms.Panel
$opsHead.Dock='Top'
$opsHead.Height=120
$opsPage.Controls.Add($opsHead)
$outputBox=New-Object Windows.Forms.TextBox
$outputBox.Multiline=$true
$outputBox.ReadOnly=$true
$outputBox.ScrollBars='Both'
$outputBox.WordWrap=$false
$outputBox.Dock='Fill'
$outputBox.Font=New-Object Drawing.Font('Consolas',9)
$opsPage.Controls.Add($outputBox)
Set-PageLayout -Page $opsPage -Header $opsHead -Body $outputBox -HeaderHeight 120
$opsInfo=Make-Label $opsHead 'Scope: checked hosts, otherwise all CSV hosts. GPO references/links do not guarantee effective application.' 12 10 1050
$opsAudit=Make-Button $opsHead 'Check Mask + GPO' 12 44 176
$opsRsop=Make-Button $opsHead 'Check + RSoP' 197 44 158
$opsCheck=Make-Button $opsHead 'Check AD' 364 44 120
$opsPlan=Make-Button $opsHead 'Apply (plan only)' 493 44 158
$opsOpen=Make-Button $opsHead 'Open reports' 660 44 135
$opsHint=Make-Label $opsHead 'GPO audit reads attribute references, linked GPOs and AD values. RSoP checks effective computer policy when accessible.' 12 86 1060

function Invoke-AdminMaskAudit {
    param([switch]$WithRsop)
    try {
        $names = @(Get-CheckedHostNames)
        $scope = if ($names.Count -eq 0) { 'all hosts in CSV' } else { "$($names.Count) checked hosts" }
        $outputBox.Text = "Checking $scope. This query may take time..."
        $outputBox.Refresh()
        $scriptPath = Join-Path $root 'scripts/AdminMask.GpoAudit.ps1'
        $params = @{ProjectRoot=$root}
        if ($names.Count -gt 0) { $params.ComputerName = [string[]]$names }
        if ($WithRsop) { $params.IncludeRsop = $true }
        $audit = & $scriptPath @params 2>&1 | Out-String -Width 240
        $outputBox.Text = [string]$audit
    }
    catch {
        $outputBox.Text = "Audit failed: $($_.Exception.Message)"
        Fail $_.Exception.Message
    }
}
$opsAudit.Add_Click({Invoke-AdminMaskAudit})
$opsRsop.Add_Click({Invoke-AdminMaskAudit -WithRsop})
$opsCheck.Add_Click({
    try {
        $checked = @(Get-CheckedHostNames)
        if ($checked.Count -eq 1) {Run-Check 'Inventory' $checked[0]}
        elseif ($checked.Count -eq 0) {Run-Check 'Inventory'}
        else {
            $lines = foreach ($computer in $checked) {
                & (Join-Path $root 'scripts/adminMask_Check.ps1') -ProjectRoot $root -Mode Inventory -HostName $computer
            }
            $outputBox.Text = ($lines | Out-String -Width 220)
        }
    }catch{Fail $_.Exception.Message}
})
$opsPlan.Add_Click({
    try {
        $result = & (Join-Path $root 'scripts/adminMask_Run.ps1') -ProjectRoot $root 2>&1 | Out-String -Width 220
        $outputBox.Text = [string]$result
    }catch{Fail $_.Exception.Message}
})
$opsOpen.Add_Click({
    $directory=Join-Path $root 'reports'
    if (-not (Test-Path -LiteralPath $directory)) {New-Item -Path $directory -ItemType Directory -Force | Out-Null}
    Start-Process explorer.exe -ArgumentList $directory
})

$script:roles=@(Get-AdminMaskRoles -ProjectRoot $root)
Refresh-Calculator
Refresh-Editor
Refresh-Ous
Refresh-Hosts
[void]$form.ShowDialog()
