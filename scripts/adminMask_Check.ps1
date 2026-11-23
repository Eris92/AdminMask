[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [ValidateSet('Inventory','LinkedGpo','Rsop')][string]$Mode = 'Inventory',
    [string]$HostName
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
. (Join-Path $PSScriptRoot 'AdminMask.Common.ps1')
Initialize-AdminMaskConfig -ProjectRoot $ProjectRoot
Import-Module ActiveDirectory -ErrorAction Stop

$hosts = @(Get-AdminMaskHosts -ProjectRoot $ProjectRoot)
if ($HostName) { $hosts = @($hosts | Where-Object { $_.Host -ieq $HostName }) }
if ($HostName -and $hosts.Count -eq 0) { throw "Host not found in hosts.csv: $HostName" }
if ($Mode -ne 'Inventory') { Import-Module GroupPolicy -ErrorAction Stop }

foreach ($item in $hosts) {
    $name = [string]$item.Host
    try {
        $ad = Get-ADComputer -Identity $name -Properties Enabled,DistinguishedName,DNSHostName -ErrorAction Stop
        Write-Output "HOST=$name STATUS=FOUND ENABLED=$($ad.Enabled) DN=$($ad.DistinguishedName)"
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Output "HOST=$name STATUS=NOT_FOUND"
        continue
    }
    if ($Mode -eq 'Inventory') { continue }

    if ($Mode -eq 'LinkedGpo') {
        $target = [string]$ad.DistinguishedName
        $target = $target.Substring($target.IndexOf(',') + 1)
        Write-Output "  OU=$target"
        try {
            $inheritance = Get-GPInheritance -Target $target -ErrorAction Stop
            $links = @($inheritance.GpoLinks) + @($inheritance.InheritedGpoLinks)
            $links = @($links | Where-Object { $_ -ne $null } | Sort-Object DisplayName,Target -Unique)
            if ($links.Count -eq 0) { Write-Output '  LINKED_GPO=NONE_FROM_OU_INHERITANCE_QUERY' }
            foreach ($link in $links) {
                Write-Output "  LINKED_GPO=$($link.DisplayName) ENABLED=$($link.Enabled) ENFORCED=$($link.Enforced) TARGET=$($link.Target)"
            }
            Write-Output '  NOTE=OU_LINKS_ONLY_NOT_CONFIRMED_APPLIED_POLICY'
        }
        catch { Write-Output "  LINKED_GPO_QUERY_FAILED=$($_.Exception.Message)" }
        continue
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("AdminMask-RSoP-{0}-{1}.html" -f ($name -replace '[^A-Za-z0-9_-]','_'),(Get-Date -Format 'yyyyMMddHHmmss'))
    try {
        Get-GPResultantSetOfPolicy -Computer $name -ReportType Html -Path $temp -ErrorAction Stop | Out-Null
        Write-Output "  RSOP_REPORT=$temp"
        Write-Output '  NOTE=RSoP_REPORT_REVIEW_APPLIED_COMPUTER_POLICIES'
    }
    catch { Write-Output "  RSOP_FAILED=$($_.Exception.Message)" }
}
