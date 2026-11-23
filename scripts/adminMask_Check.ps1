[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AdminMask.Common.ps1')
Initialize-AdminMaskConfig -ProjectRoot $ProjectRoot
Import-Module ActiveDirectory -ErrorAction Stop
$rows = foreach ($item in (Get-AdminMaskHosts -ProjectRoot $ProjectRoot)) {
    $safeName = $item.Host.Replace("'","''")
    $ad = @(Get-ADComputer -Filter "Name -eq '$safeName'" -Properties Enabled,DistinguishedName -ErrorAction Stop)
    [pscustomobject]@{
        Host = $item.Host
        Found = ($ad.Count -eq 1)
        Enabled = if ($ad.Count -eq 1) { $ad[0].Enabled } else { $null }
        Mask = $item.Maska
        Tier = $item.Tier
        DistinguishedName = if ($ad.Count -eq 1) { $ad[0].DistinguishedName } else { '' }
        Status = if ($ad.Count -eq 0) { 'NOT_FOUND' } elseif ($ad.Count -gt 1) { 'AMBIGUOUS' } else { 'FOUND' }
    }
}
$rows | Format-Table -AutoSize | Out-String -Width 240 | Write-Output
# No GPO/AD changes: this checks AD computer inventory, not effective GPO.
