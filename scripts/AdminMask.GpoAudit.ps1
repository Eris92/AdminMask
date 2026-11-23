[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string[]]$ComputerName = @(),
    [switch]$IncludeRsop
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
. (Join-Path $PSScriptRoot 'AdminMask.Common.ps1')
. (Join-Path $PSScriptRoot 'AdminMask.Directory.ps1')
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop
Initialize-AdminMaskConfig -ProjectRoot $ProjectRoot

$settings = Get-AdminMaskSettings -ProjectRoot $ProjectRoot
$attributeName = [string]$settings.MaskAttribute
$hosts = @(Get-AdminMaskHosts -ProjectRoot $ProjectRoot)
if ($ComputerName.Count -gt 0) {
    $selected = @{}
    foreach ($name in $ComputerName) { $selected[$name] = $true }
    $hosts = @($hosts | Where-Object { $selected.ContainsKey([string]$_.Host) })
}
if ($hosts.Count -eq 0) { throw 'No hosts selected for GPO audit.' }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportDir = Join-Path $ProjectRoot 'reports'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]

# A GPO report can prove a configured reference exists, but cannot prove it applied.
$gpoIndex = New-Object System.Collections.Generic.List[object]
$allGpos = @(Get-GPO -All -ErrorAction Stop)
foreach ($gpo in $allGpos) {
    try {
        $xmlText = Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop
        $matchesMask = -not [string]::IsNullOrWhiteSpace($attributeName) -and
            $xmlText.IndexOf($attributeName,[StringComparison]::OrdinalIgnoreCase) -ge 0
        $matchesGroups = $xmlText.IndexOf('investaAdminGroups',[StringComparison]::OrdinalIgnoreCase) -ge 0
        if ($matchesMask -or $matchesGroups) {
            $gpoIndex.Add([pscustomobject]@{
                Name = [string]$gpo.DisplayName
                Id = [string]$gpo.Id
                MaskReference = [bool]$matchesMask
                GroupsReference = [bool]$matchesGroups
            })
        }
    }
    catch {
        Write-Warning ("Cannot read GPO report for {0}: {1}" -f $gpo.DisplayName,$_.Exception.Message)
    }
}
Write-Output ("GPO_SCAN total={0} relevant={1} attribute={2}" -f $allGpos.Count,$gpoIndex.Count,$attributeName)
foreach ($policy in $gpoIndex) {
    Write-Output ("GPO_REFERENCE Name={0} GUID={1} maskAttribute={2} groupsAttribute={3}" -f $policy.Name,$policy.Id,$policy.MaskReference,$policy.GroupsReference)
}
if ($gpoIndex.Count -eq 0) {
    Write-Output 'WARNING: No scanned GPO report contains the configured attribute string. GPO extensions or external scripts may still use it.'
}

foreach ($row in $hosts) {
    $computerName = [string]$row.Host
    $status = 'UNKNOWN'
    $adMask = ''
    $adDn = ''
    $policyCount = 0
    $message = ''
    try {
        $computer = Get-ADComputer -Identity $computerName -Properties @($attributeName,'DistinguishedName','Enabled') -ErrorAction Stop
        $adDn = [string]$computer.DistinguishedName
        $prop = $computer.PSObject.Properties[$attributeName]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            $adMask = [string]$prop.Value
        }
        $status = if ([string]$row.Maska -eq $adMask) { 'AD_MATCH' } else { 'AD_MISMATCH' }

        $targetOu = $adDn.Substring($adDn.IndexOf(',')+1)
        $inheritance = Get-GPInheritance -Target $targetOu -ErrorAction Stop
        $links = @($inheritance.GpoLinks) + @($inheritance.InheritedGpoLinks)
        $policyIds = @{}
        foreach ($link in $links) {
            if ($null -ne $link -and [string]$link.Enabled -eq 'True') {
                $policyIds[[string]$link.GpoId] = $true
            }
        }
        foreach ($policy in $gpoIndex) {
            if ($policyIds.ContainsKey([string]$policy.Id)) {
                $policyCount++
            }
        }
        if ($IncludeRsop) {
            $safeName = $computerName -replace '[^A-Za-z0-9_-]','_'
            $htmlPath = Join-Path $reportDir ("RSoP-{0}-{1}.html" -f $safeName,$timestamp)
            try {
                Get-GPResultantSetOfPolicy -Computer $computerName -ReportType Html -Path $htmlPath -ErrorAction Stop | Out-Null
                $message = "RSOP_REPORT=$htmlPath"
            }
            catch {
                $message = "RSOP_FAILED=$($_.Exception.Message)"
            }
        }
    }
    catch {
        $status = 'ERROR'
        $message = $_.Exception.Message
    }
    $results.Add([pscustomobject]@{
        Host = $computerName
        CsvMask = [string]$row.Maska
        AdMask = $adMask
        AdComparison = $status
        LinkedGposWithReference = $policyCount
        DistinguishedName = $adDn
        Evidence = $message
    })
}
$csvPath = Join-Path $reportDir "AdminMask-GpoAudit-$timestamp.csv"
$results | Export-Csv -LiteralPath $csvPath -Encoding UTF8 -NoTypeInformation
$results | Format-Table Host,CsvMask,AdMask,AdComparison,LinkedGposWithReference -AutoSize | Out-String -Width 220 | Write-Output
Write-Output "REPORT=$csvPath"
Write-Output 'IMPORTANT: Reference in a GPO XML or an enabled OU link is not proof of client-side processing. Security filtering, WMI, GPP targeting and actual effective application must be verified separately.'
