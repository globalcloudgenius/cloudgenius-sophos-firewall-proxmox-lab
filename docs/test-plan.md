# Validation Test Plan

| ID | Test | Expected result | Status |
|---|---|---|---|
| T01 | Deploy with `SW-22.0.1_MR-1-490.iso` | VM 101 is created and started | Passed |
| T02 | Installer writes the virtual disk | SFOS boots after ISO eject | Passed |
| T03 | Home serial registration | Home subscriptions show long-dated validity | Passed |
| T04 | Port mapping | Port1=LAN/vmbr1; Port2=WAN/vmbr0 | Passed |
| T05 | LAN gateway | Proxmox `10.10.10.2` reaches `10.10.10.1` | Passed |
| T06 | LAN DHCP | Client receives `10.10.10.100-200` with gateway `10.10.10.1` | Passed |
| T07 | Public SSL VPN transport | TCP 8443 reaches Sophos | Passed |
| T08 | MFA enrollment | User receives and activates OTP token | Passed |
| T09 | VPN connection | Client receives a `10.50.0.0/24` address | Passed |
| T10 | Split-tunnel route | `10.10.10.2` routes through VPN | Passed |
| T11 | Proxmox service | TCP `10.10.10.2:8006` succeeds | Passed |
| T12 | Unauthorized LAN service | Access is denied and logged | Pending |
| T13 | Proxmox RBAC | Student cannot alter host/firewall/ACL/storage | Pending |
| T14 | Backup | Protected stop-mode ZSTD backup completes | Pending |
| T15 | Restore drill | Backup restores into an isolated test VM | Pending |
| T16 | Secret scan | Repository contains no live identifiers or credentials | Passed |

Record date, tester, revision, expected and actual result, sanitized evidence, and remediation. Do not publish public IPs, serials, emails, MAC addresses, passwords, or OTP material.
