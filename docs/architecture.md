# Architecture and Design

## Purpose

Deploy Sophos Firewall as the central security gateway for a segmented Proxmox enterprise lab.

## Design objectives

- Separate workloads by trust level and purpose.
- Apply default-deny, least-privilege access between zones.
- Protect administrative interfaces.
- Support controlled internet access, service publishing, and VPN.
- Generate security telemetry and operational evidence.
- Avoid exposing the Proxmox management plane directly to untrusted networks.

## Logical zones

| Zone | Reference subnet | Purpose | Default posture |
|---|---|---|---|
| WAN | ISP-provided | Untrusted upstream connectivity | Deny unsolicited inbound |
| LAN | 10.10.10.0/24 | Trusted users and domain clients | Controlled outbound |
| DMZ | 10.10.20.0/24 | Internet-facing or isolated services | Restricted both directions |
| Guest | 10.10.30.0/24 | Student or visitor connectivity | Internet only |
| Management | To be confirmed | Proxmox, firewall, storage administration | Administrator sources only |

## Traffic principles

1. WAN to internal zones is denied unless a documented service is explicitly published.
2. Guest cannot initiate connections to LAN, DMZ, management, Proxmox, or storage.
3. DMZ cannot initiate connections to LAN unless a specific application dependency is approved.
4. Management access is limited to known administrative devices.
5. Every allow rule must identify source, destination, service, security profile, logging, owner, and business justification.
6. Temporary rules must have an expiry date.

## Proxmox interface model

| Sophos interface | Proxmox bridge | Role |
|---|---|---|
| Port1 | WAN bridge | Upstream/ISP |
| Port2 | LAN bridge | Trusted LAN |
| Port3 | DMZ bridge | Isolated services |
| Port4 | Guest or VLAN trunk | Guest and additional segments |

Actual bridge names and physical NIC mappings will be documented after validation.

## Availability and recovery

This lab begins as a single firewall VM. Production adoption would require evaluation of:

- Redundant Proxmox nodes and network paths
- Sophos high availability and license requirements
- Configuration backup and tested restore
- UPS and power resilience
- Out-of-band management
- Change control and rollback

## Decision record

| Decision | Rationale | Status |
|---|---|---|
| Use KVM package | Proxmox VE uses KVM/QEMU | Approved |
| Import both Sophos QCOW2 disks | Primary system and report storage are required | Approved |
| Use 4+ vNICs | Clear zone separation and portfolio visibility | Planned |
| Keep management isolated | Protects hypervisor and firewall control planes | Planned |
| Publish sanitized evidence only | Protects credentials and internal details | Mandatory |
