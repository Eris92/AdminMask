# AdminMask

Windows PowerShell 5.1 / WinForms GUI for host inventory, role bitmask calculation and AD OU discovery.

> Reconstructed from the latest known AdminMask-OU-GUI-v2 functional requirements. This is not a byte-for-byte recovery of the original source. Production AD writes are intentionally disabled until mapping has been verified.

## Features

- Hosts: CSV-based inventory, add/update/remove
- Roles: bitmask configuration (Default=0, L1=1, Dev=2, BI=4, Sec=8, TST=16, FK=32, CRM=64)
- OU definitions and recursive AD computer discovery
- Checkbox mask calculator
- Backups before configuration writes
- Read-only AD computer inventory check
- Separate GUI and scripts

## Run

Requirements: Windows PowerShell 5.1, interactive Windows desktop. AD functions require RSAT ActiveDirectory module and read permissions.

```powershell
git clone https://github.com/Eris92/AdminMask.git
cd AdminMask
powershell.exe -NoProfile -STA -File .\adminMask.ps1
```

Or use `Start-AdminMask.cmd`. Example config files initialize only when local files are absent.

## Safety

- `adminMask_Run.ps1`: precheck only, never writes to AD
- `adminMask_Check.ps1`: checks the existence/status of AD computer objects, **not effective GPO**
- Local `config/hosts.csv`, `config/roles.csv`, `config/ad-ous.txt` are gitignored
- Tier semantics and effective GPO mapping must be confirmed before deployment
- OU discovery runs synchronously and may block GUI on large OUs

## Source tree

| File | Purpose |
|---|---|
| `adminMask.ps1` | WinForms GUI |
| `scripts/AdminMask.Common.ps1` | Storage, backup, validation |
| `scripts/AdminMask-Inventory.ps1` | AD computer discovery |
| `scripts/adminMask_Check.ps1` | AD inventory verification |
| `scripts/adminMask_Run.ps1` | Apply precheck, write-disabled |
| `config/*.example.*` | Local config templates |
| `docs/RECOVERY.md` | Scope of reconstruction and known gaps |

## Next development

1. Restore exact AD/GPO write target and mask/Tier semantics.
2. Add effective GPO verification.
3. Add asynchronous OU discovery with progress and cancellation.
4. Add Pester tests and signed EXE packaging.

## Changes (2026-11-23)

- Hosts view includes independently applied host text, Mask, Tier and OU filters. Each filter has an `All` option (host text can be blank); filters survive Reload.
- Host editor supports Tier `0`, `1`, `2`, OU `All` (stored as blank), and all valid role-mask combinations.
- Mask Calculator supports adding a custom single-bit role to `config/roles.csv`, then using the result for a host. Existing roles are backed up before changes.
- `Check AD` checks computer object inventory; `Linked GPOs` enumerates OU linked/inherited GPOs and **does not** establish application.
- `RSoP (selected)` attempts to retrieve the effective policies for the selected computer and writes an HTML report to the current user's temporary directory. Requires RSAT GroupPolicy module, remote access, and permissions.
- `Apply (plan only)` validates local masks but **does not change AD or GPO**.
- Fixed script ProjectRoot default: calculated within the script body instead of within the parameter initializer.

### Remaining limitations

- The reconstructed version cannot validate the original intended role-to-GPO rules until those rules are supplied.
- The OU discovery runs synchronously; large OUs may stall the GUI.
- The WinForms GUI has not been executed/tested on Windows in this environment.

## Mask data source clarification (2026-11-23)

**Current mask source is `config/hosts.csv` only.** Mask Calculator is independent. OU discovery previously assigned a default `Maska=0` to every newly discovered host, even when its real policy state was unknown. Discovery now leaves `Maska` and `Tier` empty (unknown) for new rows, and preserves existing CSV rows unchanged. Previously imported `0` values are not automatically altered because some zeros could be intentional.

`Use for host` now asks for confirmation before saving the calculated mask to the selected host in `hosts.csv`. This is a **CSV-only** change, not an AD / GPO write.

To synchronize **existing AD/GPO masks**, the authoritative attribute, registry policy value, GPO name/pattern or other data source must be identified and implemented. Until then, the UI cannot claim to display effective masks applied to remote hosts. Do not bulk-replace existing CSV values with guessed values.

## AD authoritative mask and OU Tier mapping (2026-11-23)

- `AD OUs`: choose `Tier = 0 / 1 / 2` (or Unassigned) when adding/updating each OU. Configuration is stored in local, gitignored `config/ou-tiers.csv`. Legacy `config/ad-ous.txt` entries are read automatically if no OU mapping CSV exists; they initially have Unassigned Tier.
- `AD OUs -> Mask attribute`: enter the **actual LDAP attribute name** containing an integer mask on computer objects, e.g. a custom schema attribute chosen by your organization. There is **no assumed default**. Saved in `config/settings.json`; template `config/settings.example.json`. Only read access to AD is used.
- `Discover recursive`: reads mask from the configured AD attribute, resolves Tier from the longest matching configured OU DN, and imports new computers without overwriting existing local inventory.
- `Hosts -> Sync from AD`: reads all configured OU trees and, after explicit confirmation, updates local host CSV with authoritative nonempty AD mask and mapped Tier; backs up CSV before writing. AD remains unchanged.
- If the AD attribute is not configured, no mask is inferred; discovered hosts have an empty (unknown) mask, never a fabricated zero. Blank AD values do not wipe an existing local mask.
- Previously imported zero masks remain until you run an explicit sync with the proper attribute configured.
- AD attribute values must be nonnegative base-10 integers; multivalued/non-numeric attributes are rejected.

**Limit:** no AD attribute name has been provided or independently verified; configure the real attribute before asserting mask accuracy. Tier is an OU mapping, not an AD computer attribute. No AD writes are implemented.

## Confirmed original AD fields

Historical AdminMask source context identifies AD computer attribute `investaAdminMask` as the bitmask source and also references `investaAdminGroups`. The default for `MaskAttribute` is now `investaAdminMask` (configurable). `investaAdminGroups` is **not** modified by this implementation. Set Tier per OU in the GUI; no default OU-to-Tier mapping was recovered.

After setting Tier per OU, use **Hosts > Sync from AD** to read current masks and update the local CSV on confirmation. This does not write AD.

## UI and policy audit update (2026-11-23)

- **Hosts > Mask filter**: `All` shows all values, `[Empty]` shows only hosts without an assigned mask. An actual mask `0` remains distinct from an empty field.
- **Hosts > Tier filter**: `All`, `[Empty]`, `0`, `1`, `2`.
- **Hosts > Select**: editable checkbox in the first column. Selections persist across filtering/reload and are used as scope for Operations. With no checked rows, Operations audits all hosts in CSV.
- **Hosts > Roles**: translates the numeric mask using the configured role bits; e.g. `63` maps to `L1, Dev, BI, Sec, TST, FK`. Unknown bits and missing masks are explicitly marked.
- **Mask Calculator**: stabilized checkbox layout and spacing.
- **Operations > Check Mask + GPO**: read-only audit. Compares each computer's CSV mask with AD `investaAdminMask`, scans accessible GPO XML for `investaAdminMask` and `investaAdminGroups` references and counts enabled GPO links with references. Writes a CSV report under `reports/`.
- **Operations > Check + RSoP**: additionally attempts HTML RSoP reports per checked computer (or all if none checked). May be slow and requires remote access and appropriate permissions.
- **Operations > Check AD**: read-only AD object checks. `Apply` remains plan-only until original write semantics have been validated.

**Evidence limits:** A GPO containing an attribute name or being linked to an OU does **not** prove that the mask is implemented by that GPO or that the client applied it. A meaningful compliance result requires the original policy mapping and effective-side checks; report statuses intentionally distinguish AD data comparison, GPO references and RSoP results. This change does not write to AD or modify GPOs.
