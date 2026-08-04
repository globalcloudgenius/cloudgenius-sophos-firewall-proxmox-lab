# Validated Architecture

## Purpose

Sophos Firewall Home Edition is the routed security boundary between the existing home network and the isolated CloudGenius lab. It provides DHCP, policy enforcement, NAT, logging, and remote-access VPN. Proxmox remains the hypervisor and does not replace Sophos as the lab gateway.

## Interface and address plan

| Component | Interface / bridge | Zone | Addressing | Purpose |
|---|---|---|---|---|
| Sophos Port1 | `net0 -> vmbr1` | LAN | `10.10.10.1/24` static | Lab gateway and DHCP |
| Proxmox node | `vmbr1` | LAN | `10.10.10.2/24` static | Restricted management |
| Sophos Port2 | `net1 -> vmbr0` | WAN | DHCP reservation | Upstream/home network |
| Proxmox node | `vmbr0` | Upstream management | Existing private address | Local administration |
| SSL VPN clients | Sophos virtual pool | VPN | `10.50.0.0/24` | Remote users |

Port order is important: **Port1 is LAN on vmbr1; Port2 is WAN on vmbr0.**

## Routing behavior

- Sophos owns `10.10.10.1/24` and is the default gateway for lab workloads.
- Proxmox owns `10.10.10.2/24` on `vmbr1`.
- LAN DHCP leases use `10.10.10.100-10.10.10.200`.
- Remote users receive `10.50.0.0/24` addresses.
- The student VPN is split-tunnel and advertises only approved hosts.
- The Proxmox access policy permits TCP 8006 only.
- A linked MASQ rule supplies symmetric return routing when Proxmox has no route to `10.50.0.0/24`.

## Trust boundaries

| From | To | Default |
|---|---|---|
| WAN | Sophos local services | Deny except explicit VPN services |
| WAN | LAN | Deny |
| VPN students | Proxmox management | Allow TCP 8006 only, matched user/group, logged |
| VPN students | Other LAN resources | Deny |
| LAN | WAN | Explicit policy only |
| Unapproved sources | Sophos/Proxmox administration | Deny |

## Proxmox VM baseline

| Setting | Value |
|---|---|
| Firmware | SeaBIOS |
| Machine | `pc` |
| CPU | Host, 4 cores |
| Memory | 6144 MB, ballooning disabled |
| Disk controller | VirtIO SCSI single |
| Disk | `scsi0`, 80 GB |
| Installer | `ide2`, software ISO |
| NIC model | `e1000` validated; `virtio` supported by script |
| Proxmox QEMU guest-agent integration | Disabled |
| Boot during installation | `ide2;scsi0` |
| Boot after installation | `scsi0` |

## Implemented network scope

This repository documents only the deployed two-interface design: Port1/LAN on `vmbr1` and Port2/WAN on `vmbr0`. It does not claim a guest network, DMZ, VLAN trunk, site-to-site VPN, or high-availability deployment.
