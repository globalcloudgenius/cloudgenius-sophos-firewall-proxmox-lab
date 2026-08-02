# Proxmox Installation Runbook

## Version scope

- Sophos package: `VI-22.0.1_MR-1.KVM-490.zip`
- Target: Proxmox VE
- Appliance type: KVM/QEMU
- Status: In progress

Follow the current [Sophos Proxmox deployment documentation](https://docs.sophos.com/nsg/sophos-firewall/22.0/Help/en-us/webhelp/onlinehelp/VirtualAndSoftwareAppliancesHelp/KVM/ProxmoxInstall/) as the authoritative source.

## Prerequisites

- Supported Proxmox VE host
- KVM Sophos Firewall evaluation package
- Valid trial or license entitlement
- At least 1 vCPU, 4 GB RAM, 2 vNICs, 32 GB primary disk, and 80 GB report disk
- Planned bridge/interface mappings
- Administrative workstation able to reach the initial management network
- Backup of relevant Proxmox network configuration

## Safety checks

- Do not upload Sophos binaries, serial numbers, or license files to GitHub.
- Do not attach WAN and management to the same unrestricted bridge.
- Do not expose Proxmox or Sophos administration directly to the internet.
- Confirm bridge-to-physical-NIC mappings before starting the VM.
- Preserve a working route to Proxmox management.

## Implementation sequence

1. Extract the downloaded KVM ZIP locally.
2. Confirm that the primary and auxiliary QCOW2 disks are present.
3. Upload or securely copy the extracted disks to a temporary location on the selected Proxmox node.
4. Create the VM without installation media.
5. Allocate resources within the Sophos license limit.
6. Ensure **Start after created** is disabled until storage and networking are complete.
7. Import the primary and auxiliary disks into the selected Proxmox storage.
8. Attach the imported disks in the required order.
9. Add and map WAN, LAN, DMZ, and optional guest interfaces.
10. Disable QEMU Guest Agent if enabled.
11. Start the VM and observe the console.
12. From an isolated management workstation, connect to the documented initial Sophos management address and port.
13. Complete registration and basic setup.
14. Immediately restrict administrative access and replace default credentials through the supported setup flow.
15. Configure zones, routes, DNS, DHCP if required, firewall rules, NAT, and security profiles.
16. Back up the configuration.
17. Execute the validation test plan.
18. Capture only sanitized evidence.

## Example import pattern

Confirm storage identifiers and VM ID before running commands:

```bash
qm importdisk <VMID> PRIMARY-DISK.qcow2 <STORAGE_ID>
qm importdisk <VMID> AUXILIARY-DISK.qcow2 <STORAGE_ID>
```

The imported disks must then be attached to the VM through Proxmox hardware settings. Command syntax and generated disk identifiers can vary by Proxmox version and storage type.

## Post-install hardening

- Restrict web and SSH administration to the management zone.
- Disable unused administrative services.
- Synchronize time with approved NTP sources.
- Configure secure DNS behavior.
- Apply least-privilege firewall rules.
- Enable logging on security-relevant rules.
- Configure IPS and other licensed security profiles.
- Export and protect a configuration backup.
- Document firmware and pattern-update status.

## Completion evidence

- VM hardware summary
- Sanitized interface and zone configuration
- Policy table
- NAT validation
- Segmentation test results
- IPS or security-event evidence using safe test traffic
- Backup completion
- Final architecture diagram
