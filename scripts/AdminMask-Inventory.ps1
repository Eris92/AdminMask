[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$SearchBase,
    [string]$OutputCsv,
    [switch]$Recursive
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop
$results = foreach ($ou in $SearchBase) {
    $params = @{SearchBase=$ou;Filter='*';Properties=@('DistinguishedName','Enabled','DNSHostName');ErrorAction='Stop'}
    if (-not $Recursive) { $params.SearchScope = 'OneLevel' }
    Get-ADComputer @params | Select-Object @{n='Host';e={$_.Name}}, DNSHostName, Enabled, DistinguishedName
}
$results = @($results | Sort-Object DistinguishedName -Unique)
if ($OutputCsv) { $results | Export-Csv -LiteralPath $OutputCsv -Encoding UTF8 -NoTypeInformation }
$results
