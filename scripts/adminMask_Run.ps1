[CmdletBinding(SupportsShouldProcess)]
param([string]$ProjectRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
. (Join-Path $PSScriptRoot 'AdminMask.Common.ps1')
Initialize-AdminMaskConfig -ProjectRoot $ProjectRoot
$roles = @(Get-AdminMaskRoles -ProjectRoot $ProjectRoot)
$hosts = @(Get-AdminMaskHosts -ProjectRoot $ProjectRoot)
foreach ($item in $hosts) {
    $null = Test-AdminMaskValue -Value $item.Maska -Roles $roles
}
Write-Output "Precheck OK. Hosts: $($hosts.Count)."
Write-Output 'PLAN ONLY. No AD/GPO modifications are implemented; original attribute and policy mapping must be restored first.'
