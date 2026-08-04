# Home Edition Installation Runbook

## Version scope

- Installer: `SW-22.0.1_MR-1-490.iso`
- Installed firmware: SFOS 22.0.1 MR-1 Build 490
- License: Sophos Firewall Home Edition
- Hypervisor: Proxmox VE 9.2.2 / KVM
- Deployment status: validated

This runbook uses only the **Home Edition software ISO**. The paid/evaluation `VI-*.KVM.zip` package, primary QCOW2 disk, and auxiliary/report QCOW2 disk are not part of this deployment.

## Prerequisites

1. Request a Sophos Firewall Home Edition serial through the official Home Edition page.
2. Download the Intel software ISO. Keep it outside Git.
3. Verify that WAN and LAN are separate Proxmox bridges.
4. Confirm the ISO storage accepts `iso` content and disk storage accepts `images`.
5. Install/enable Windows OpenSSH Client.
6. Back up relevant Proxmox configuration.
7. Confirm VMID and name are unused.

## Automated VM creation

```powershell
.\scripts\Deploy-Sophos-Home-Firewall-Proxmox.ps1 `
  -ProxmoxHost <PROXMOX_HOST> `
  -ProxmoxNode <PROXMOX_NODE> `
  -DiskStorage <VM_DISK_STORAGE> `
  -IsoStorage local `
  -WanBridge vmbr0 `
  -LanBridge vmbr1 `
  -VmId 101 `
  -IsoFile "$env:USERPROFILE\Downloads\SW-22.0.1_MR-1-490.iso"
```

Safe behavior:

- Enforces at most 4 CPU cores and 6144 MB RAM.
- Computes SHA-256 before upload and verifies it on Proxmox.
- Verifies node, bridges, storage state, and content types.
- Refuses existing VM names and VMIDs.
- Does not edit `/etc/network/interfaces`.
- Does not delete an existing VM.
- On failure, removes only an incomplete VM created by that run.
- Creates, validates, and starts the VM.

## Interactive installer

1. Open the VM console.
2. Confirm that the installer detects KVM and the intended 80 GB disk.
3. At the erase warning, continue only after confirming the disk belongs to the new VM.
4. Wait for “Firmware Installed”.
5. Remove/eject the installer ISO.
6. Set boot order to `scsi0` first.
7. Reboot.
8. Confirm the SFOS main menu appears.

## Initial management

The factory management address is normally `172.16.16.16:4444`. If it is not directly reachable, use a temporary SSH local forward through the Proxmox node:

```powershell
ssh -N -L 4444:172.16.16.16:4444 root@<PROXMOX_HOST>
```

Then browse to `https://127.0.0.1:4444`. Keep the PowerShell window open while using the tunnel.

During setup:

1. Set the firewall name and correct time zone.
2. Register with the Home Edition serial, not a 30-day trial serial.
3. Confirm the Home license and its long-dated subscription status.
4. Complete the wizard and allow the firewall to reboot.
5. Sign in with the administrator password created during setup.

## Validated network setup

1. Set Port1 to LAN, static `10.10.10.1/24`.
2. Set Port2 to WAN, DHCP.
3. Reserve the Sophos WAN address on the ISP router.
4. Enable the Port1 DHCP server with `10.10.10.100-10.10.10.200`.
5. Configure the Proxmox-side `vmbr1` address as `10.10.10.2/24`.
6. Test `ping -I vmbr1 -c 4 10.10.10.1`.
7. Access Sophos directly at `https://10.10.10.1:4444`.

Do not paste `iface vmbr1 ...` into a shell; it is configuration-file syntax. Apply persistent Proxmox network changes through the UI or a carefully reviewed `/etc/network/interfaces.new` commit.

## Post-install

- Eject the ISO and confirm disk-first boot.
- Restrict local service ACLs.
- Configure MFA and restricted SSL VPN.
- Create a non-root, least-privilege Proxmox account for each person.
- Enable logs on management-access rules.
- Take a protected stop-mode Proxmox backup with ZSTD.
- Export a Sophos configuration backup and protect it separately.
