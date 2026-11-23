Set-StrictMode -Version Latest

function Get-AdminMaskSettings {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/settings.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{MaskAttribute=''}
    }
    $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($settings.PSObject.Properties.Name -contains 'MaskAttribute')) {
        return [pscustomobject]@{MaskAttribute=''}
    }
    return $settings
}

function Set-AdminMaskAttribute {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Attribute)
    $attributeName = $Attribute.Trim()
    if ($attributeName -notmatch '^[A-Za-z][A-Za-z0-9-]{0,127}$') {
        throw 'Specify a valid LDAP attribute name; it must be the actual AD computer attribute.'
    }
    $settings = Get-AdminMaskSettings -ProjectRoot $ProjectRoot
    $settings.MaskAttribute = $attributeName
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'settings.json'
    $json = $settings | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $ProjectRoot 'config/settings.json'),$json,(New-Object Text.UTF8Encoding($false)))
}

function Get-AdminMaskOuMappings {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config/ou-tiers.csv'
    if (Test-Path -LiteralPath $path) {
        return @(Import-Csv -LiteralPath $path -Encoding UTF8 | Where-Object { $_.OU })
    }
    $old = Get-AdminMaskOus -ProjectRoot $ProjectRoot
    return @($old | ForEach-Object { [pscustomobject]@{OU=[string]$_;Tier=''} })
}

function Save-AdminMaskOuMappings {
    param([Parameter(Mandatory)][string]$ProjectRoot,[AllowEmptyCollection()][object[]]$Items = @())
    $seen = @{}
    $rows = @()
    foreach ($item in $Items) {
        $dn = ([string]$item.OU).Trim()
        if (-not $dn) { continue }
        Test-AdminMaskDn -Dn $dn
        $tier = ([string]$item.Tier).Trim()
        if ($tier -notin @('','0','1','2')) {
            throw "Invalid Tier for OU $dn"
        }
        $key = $dn.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate OU: $dn" }
        $seen[$key] = $true
        $rows += [pscustomobject]@{OU=$dn;Tier=$tier}
    }
    $path = Join-Path $ProjectRoot 'config/ou-tiers.csv'
    Backup-AdminMaskConfig -ProjectRoot $ProjectRoot -Name 'ou-tiers.csv'
    $csv = if ($rows.Count) { ($rows | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine }
           else { 'OU,Tier' }
    [IO.File]::WriteAllText($path,$csv+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
}

function Resolve-AdminMaskTier {
    param([Parameter(Mandatory)][string]$ComputerDn,[object[]]$Mappings=@())
    $ordered = @($Mappings | Sort-Object { ([string]$_.OU).Length } -Descending)
    foreach ($mapping in $ordered) {
        $dn = ([string]$mapping.OU).Trim()
        if (-not $dn) { continue }
        if ($ComputerDn.EndsWith(','+$dn,[StringComparison]::OrdinalIgnoreCase)) {
            return [string]$mapping.Tier
        }
    }
    return ''
}

function Get-AdminMaskDirectoryComputers {
    param(
        [Parameter(Mandatory)][string]$SearchBase,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Recursive
    )
    Import-Module ActiveDirectory -ErrorAction Stop
    $settings = Get-AdminMaskSettings -ProjectRoot $ProjectRoot
    $attribute = ([string]$settings.MaskAttribute).Trim()
    if ($attribute -and $attribute -notmatch '^[A-Za-z][A-Za-z0-9-]{0,127}$') {
        throw "Invalid configured LDAP attribute: $attribute"
    }
    $properties = @('DistinguishedName','Enabled','DNSHostName')
    if ($attribute) { $properties += $attribute }
    $params = @{SearchBase=$SearchBase;Filter='*';Properties=$properties;ErrorAction='Stop'}
    if (-not $Recursive) { $params.SearchScope='OneLevel' }
    $mappings = @(Get-AdminMaskOuMappings -ProjectRoot $ProjectRoot)
    foreach ($computer in (Get-ADComputer @params)) {
        $mask = ''
        if ($attribute) {
            $property = $computer.PSObject.Properties[$attribute]
            if ($null -ne $property -and $null -ne $property.Value) {
                $raw = @($property.Value)
                if ($raw.Count -ne 1) {
                    throw "Multiple mask values on $($computer.Name); cannot map to one bitmask."
                }
                $mask = ([string]$raw[0]).Trim()
                if ($mask -and $mask -notmatch '^[0-9]+$') {
                    throw "Non-numeric mask on $($computer.Name): $mask"
                }
            }
        }
        [pscustomobject]@{
            Host = [string]$computer.Name
            Maska = $mask
            Tier = Resolve-AdminMaskTier -ComputerDn $computer.DistinguishedName -Mappings $mappings
            OU = $SearchBase
            DistinguishedName = [string]$computer.DistinguishedName
        }
    }
}
