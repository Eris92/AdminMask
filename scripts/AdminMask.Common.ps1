Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-AdminMaskConfig {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $config = Join-Path $ProjectRoot 'config'
    if (-not (Test-Path -LiteralPath $config)) {
        New-Item -ItemType Directory -Path $config -Force | Out-Null
    }
    foreach ($name in @('hosts.csv','roles.csv','ad-ous.txt')) {
        $target = Join-Path $config $name
        $example = Join-Path $config ($name -replace '\.(csv|txt)$', '.example.$1')
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $example -Destination $target
        }
    }
}
function Backup-AdminMaskConfig {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Name)
    $src = Join-Path (Join-Path $ProjectRoot 'config') $Name
    if (-not (Test-Path -LiteralPath $src)) { return }
    $dir = Join-Path $ProjectRoot 'backups'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-ffff'
    Copy-Item -LiteralPath $src -Destination (Join-Path $dir "$stamp-$Name") -ErrorAction Stop
}
function Get-AdminMaskHosts {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/hosts.csv'
    @((Import-Csv -LiteralPath $path -Encoding UTF8) | Where-Object { $_.Host })
}
function Get-AdminMaskRoles {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/roles.csv'
    @((Import-Csv -LiteralPath $path -Encoding UTF8) | Where-Object { $_.Name })
}
function Get-AdminMaskOus {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/ad-ous.txt'
    @((Get-Content -LiteralPath $path -Encoding UTF8) | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Unique)
}
function Save-AdminMaskHosts {
    param([string]$ProjectRoot,[object[]]$Items)
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'hosts.csv'
    $path = Join-Path $ProjectRoot 'config/hosts.csv'
    $rows = @($Items | ForEach-Object {
        [pscustomobject]@{Host=[string]$_.Host;Maska=[string]$_.Maska;Tier=[string]$_.Tier;OU=[string]$_.OU}
    })
    if ($rows.Count -eq 0) {
        [System.IO.File]::WriteAllText($path,"Host,Maska,Tier,OU" + [Environment]::NewLine,(New-Object System.Text.UTF8Encoding($false)))
    } else {
        $rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    }
}
function Save-AdminMaskOus {
    param([string]$ProjectRoot,[string[]]$Items)
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'ad-ous.txt'
    $path = Join-Path $ProjectRoot 'config/ad-ous.txt'
    [System.IO.File]::WriteAllLines($path,[string[]]@($Items | Where-Object { $_ } | Select-Object -Unique),(New-Object System.Text.UTF8Encoding($false)))
}
function Test-AdminMaskValue {
    param([string]$Value,[object[]]$Roles)
    $number = 0
    if (-not [int]::TryParse($Value,[ref]$number) -or $number -lt 0) {
        throw "Invalid mask: $Value"
    }
    $allowed = 0
    foreach ($role in $Roles) { $allowed = $allowed -bor [int]$role.Value }
    if (($number -band (-bnot $allowed)) -ne 0) { throw "Unknown role bits in mask: $Value" }
    return $number
}
function Test-AdminMaskDn {
    param([string]$Dn)
    if ($Dn -notmatch '^(OU|CN)=.+,DC=.+') { throw "Invalid OU distinguished name: $Dn" }
}
