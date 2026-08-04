# Security Controls

| Control | Implemented baseline | Verification |
|---|---|---|
| Home-license resource cap | 4 vCPU, 6144 MB | Proxmox VM hardware |
| Network separation | WAN `vmbr0`, LAN `vmbr1` | VM NIC mapping |
| Admin plane | No public Proxmox 8006/SSH forwarding | Router and Sophos rule review |
| Remote access | SSL VPN TCP 8443 | External port test |
| Strong authentication | Individual user plus TOTP MFA | Authentication logs |
| Least privilege | VPN group to one host and TCP 8006 | Firewall rule and policy test |
| Split tunnel | Only `10.10.10.2` advertised | Client route table |
| Return routing | Linked MASQ only where required | NAT hit counter and connection test |
| Accountability | Firewall-rule logging and named users | Log viewer |
| Proxmox authorization | Separate non-root account with scoped role/pool | Proxmox permissions view |
| Recovery | Protected stop-mode VM backup, ZSTD | Backup task log |
| Secret hygiene | No serials, public IPs, emails, MACs, passwords, OTP secrets | Repository scan |

## Proxmox RBAC

VPN access is not authorization to administer Proxmox. For every remote user:

1. Create an individual Proxmox realm account.
2. Create a resource pool containing only approved VMs.
3. Assign a built-in or custom role with only required privileges.
4. Do not grant `Administrator`, root, node shell, storage deletion, network modification, or permission-management rights.
5. Require a second Proxmox factor where supported.
6. Review and remove access when the engagement ends.

A student/operator role may include VM audit, console, power management, and limited configuration for assigned VMs. It must not include host, firewall-VM, storage, cluster, or ACL administration.

## Backup versus snapshot

- **Backup** is the recovery control. Store it outside the VM disk, use stop mode for the cleanest firewall image, and mark it protected.
- **Snapshot** is a short-lived rollback point before a controlled change. It is not a backup.

Also export Sophos configuration backups and test restoration periodically.
