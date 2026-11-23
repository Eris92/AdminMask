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
