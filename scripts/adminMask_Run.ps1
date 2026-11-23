[CmdletBinding(SupportsShouldProcess)]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AdminMask.Common.ps1')
Initialize-AdminMaskConfig -ProjectRoot $ProjectRoot
$roles = Get-AdminMaskRoles -ProjectRoot $ProjectRoot
$hosts = Get-AdminMaskHosts -ProjectRoot $ProjectRoot
foreach ($item in $hosts) {
    $null = Test-AdminMaskValue -Value $item.Maska -Roles $roles
}
Write-Output "Precheck OK. Hosts: $($hosts.Count)."
Write-Output 'No AD changes made. The original AD write target, mask semantics and Tier mapping are not available.'
Write-Output 'Implement the validated AD/GPO application logic here before enabling deployment.'
