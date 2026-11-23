# Recovery ledger

Confirmed requirements from previous AdminMask conversations (2026-10-26 to 2026-10-30):

- External PowerShell scripts / CSV independent of EXE
- Hosts/roles centralized in hosts.csv / roles.csv
- Role mask: Default=0, L1=1, Dev=2, BI=4, Sec=8, TST=16, FK=32, CRM=64
- GUI OU Browse/Add/Update/Remove, recursive computer discovery
- Host removal, mask/tier dropdowns, checkbox mask calculator
- Backup hosts.csv and ad-ous.txt; preserve existing configs
- Previous packages: AdminMask-GUI.zip, AdminMask-GUI-EXE.zip, AdminMask-OU-GUI-v2.zip

Not recovered / not claimed:

- Byte-for-byte source, original GUI layout, EXE binary
- AD writes and effective GPO inspection behavior
- Original Tier value semantics, real host inventory
- Original PowerShell configuration schema beyond known fields

Security note: no environment data or production credentials are committed.
