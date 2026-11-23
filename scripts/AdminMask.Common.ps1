Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-AdminMaskConfig {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $config = Join-Path $ProjectRoot 'config'
    if (-not (Test-Path -LiteralPath $config)) {
        New-Item -ItemType Directory -Path $config -Force | Out-Null
    }
    foreach ($name in @('hosts.csv', 'roles.csv', 'ad-ous.txt')) {
        $target = Join-Path $config $name
        $example = Join-Path $config ($name -replace '\.(csv|txt)$', '.example.$1')
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $example -Destination $target -ErrorAction Stop
        }
    }
}
function Backup-AdminMaskConfig {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$Name)
    $source = Join-Path (Join-Path $ProjectRoot 'config') $Name
    if (-not (Test-Path -LiteralPath $source)) { return }
    $directory = Join-Path $ProjectRoot 'backups'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-ffff'
    Copy-Item -LiteralPath $source -Destination (Join-Path $directory "$timestamp-$Name") -ErrorAction Stop
}
function Get-AdminMaskHosts {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/hosts.csv'
    return @(Import-Csv -LiteralPath $path -Encoding UTF8 | Where-Object { $_.Host })
}
function Get-AdminMaskRoles {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/roles.csv'
    return @(Import-Csv -LiteralPath $path -Encoding UTF8 | Where-Object { $_.Name })
}
function Get-AdminMaskOus {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/ad-ous.txt'
    return @(Get-Content -LiteralPath $path -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        Select-Object -Unique)
}
function Save-AdminMaskHosts {
    param([Parameter(Mandatory)][string]$ProjectRoot, [AllowEmptyCollection()][object[]]$Items = @())
    $path = Join-Path $ProjectRoot 'config/hosts.csv'
    $rows = @($Items | ForEach-Object {
        [pscustomobject]@{
            Host = [string]$_.Host
            Maska = [string]$_.Maska
            Tier = [string]$_.Tier
            OU = [string]$_.OU
        }
    })
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'hosts.csv'
    if ($rows.Count -eq 0) {
        [IO.File]::WriteAllText($path, "Host,Maska,Tier,OU" + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    }
    else {
        $csv = ($rows | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
        [IO.File]::WriteAllText($path, $csv + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    }
}
function Save-AdminMaskOus {
    param([Parameter(Mandatory)][string]$ProjectRoot, [AllowEmptyCollection()][string[]]$Items = @())
    $path = Join-Path $ProjectRoot 'config/ad-ous.txt'
    $lines = [string[]]@($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'ad-ous.txt'
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
}
function Test-AdminMaskValue {
    param([Parameter(Mandatory)][string]$Value, [object[]]$Roles = @())
    $number = 0
    if (-not [int]::TryParse($Value, [ref]$number) -or $number -lt 0) {
        throw "Invalid mask: $Value"
    }
    $allowed = 0
    foreach ($role in $Roles) { $allowed = $allowed -bor [int]$role.Value }
    if (($number -band (-bnot $allowed)) -ne 0) {
        throw "Unknown role bits in mask: $Value"
    }
    return $number
}
function Save-AdminMaskRoles {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][object[]]$Items)
    $names = @{}
    $bits = @{}
    $records = @()
    foreach ($item in $Items) {
        $name = ([string]$item.Name).Trim()
        $bit = 0
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,39}$' -or
            -not [int]::TryParse([string]$item.Value, [ref]$bit)) {
            throw 'Invalid role name or value.'
        }
        if ($bit -lt 0 -or ($bit -ne 0 -and (($bit -band ($bit - 1)) -ne 0))) {
            throw 'Role value must be zero or a single power of two.'
        }
        $key = $name.ToLowerInvariant()
        if ($names.ContainsKey($key) -or ($bit -ne 0 -and $bits.ContainsKey($bit))) {
            throw "Duplicate role name or bit: $name"
        }
        $names[$key] = $true
        if ($bit -ne 0) { $bits[$bit] = $true }
        $records += [pscustomobject]@{ Name = $name; Value = $bit }
    }
    if ($records.Count -eq 0) { throw 'Cannot save empty roles.' }
    $csv = ($records | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
    $path = Join-Path $ProjectRoot 'config/roles.csv'
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'roles.csv'
    [IO.File]::WriteAllText($path, $csv + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}
function Get-AdminMaskMaskOptions {
    param([object[]]$Roles = @())
    $values = @(0)
    foreach ($role in $Roles) {
        $bit = [int]$role.Value
        if ($bit -le 0) { continue }
        if ($values.Count -gt 4096) { throw 'Too many mask combinations for the dropdown.' }
        $combined = @($values)
        foreach ($current in $values) { $combined += ($current -bor $bit) }
        $values = @($combined | Sort-Object -Unique)
    }
    return @($values | Sort-Object)
}
function Test-AdminMaskDn {
    param([Parameter(Mandatory)][string]$Dn)
    if ($Dn -notmatch '^(OU|CN)=.+,DC=.+') {
        throw "Invalid OU distinguished name: $Dn"
    }
}
