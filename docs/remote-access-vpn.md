# Restricted SSL VPN with MFA

## Goal

Allow an approved remote student to reach only the Proxmox web interface at `10.10.10.2:8006`. Do not expose Proxmox directly to the internet.

## 1. ISP router

Reserve the Sophos WAN address, then forward:

| External service | Protocol | Destination |
|---|---|---|
| SSL VPN | TCP 8443 | Sophos WAN address, TCP 8443 |
| VPN portal (temporary) | TCP 443 | Sophos WAN address, TCP 443 |

Remove TCP 443 after users have enrolled MFA and downloaded their configuration unless continued portal access is required. Never forward TCP 8006 or TCP 22 to Proxmox.

If the public IP changes, use dynamic DNS and place its hostname in Sophos **Override hostname**.

## 2. Sophos group and user

1. Create group `CloudGenius-Students-VPN`.
2. Create one local **User** account per student; never share accounts.
3. Add each user to the group.
4. Limit simultaneous sign-ins to one unless there is a documented need.
5. Do not create the student as a Sophos administrator.

## 3. MFA

Under **Authentication > Multi-factor authentication**:

- Select specific users and groups.
- Add `CloudGenius-Students-VPN`.
- Enable “Generate OTP token with next sign-in”.
- Require MFA for VPN portal and SSL VPN remote access.
- Keep Local as the SSL VPN authentication server.

The user scans the QR code privately. Treat the QR code, Base32/HEX secret, recovery codes, and screenshots as credentials. If exposed, delete/reset the token and enroll again.

For first portal sign-in, Sophos expects the account password followed immediately by the six-digit OTP:

```text
<password><six-digit-OTP>
```

## 4. Global SSL VPN settings

| Setting | Value |
|---|---|
| Protocol | TCP |
| Override hostname | `<PUBLIC_IP_OR_DDNS_NAME>` |
| Port | 8443 |
| Client pool | `10.50.0.0/24` |
| Lease mode | IPv4 only |
| Encryption | AES-256-GCM |
| Authentication | SHA2-256 |
| Idle disconnect | 15 minutes |

The override hostname is the lab owner's public endpoint, not the student's public IP.

## 5. Split-tunnel policy

Create host object `Proxmox-CloudGenius1` as IP host `10.10.10.2`.

Create SSL VPN policy `CloudGenius-Students-Restricted`:

- Members: `CloudGenius-Students-VPN`
- Use as default gateway: **Off**
- Permitted IPv4 resources: `Proxmox-CloudGenius1`
- Disconnect idle clients: **On**

## 6. Firewall and NAT

Create service `Proxmox-HTTPS-8006` using TCP source port 1:65535 and destination port 8006.

Create a top firewall rule:

| Field | Value |
|---|---|
| Source zone | VPN |
| Source network | `##ALL_SSLVPN_RW` |
| Match known users | Enabled |
| User/group | `CloudGenius-Students-VPN` |
| Destination zone | LAN |
| Destination | `Proxmox-CloudGenius1` |
| Service | `Proxmox-HTTPS-8006` |
| Action | Accept |
| Logging | Enabled |

Leave all other VPN-to-LAN access denied.

If Proxmox has no route back to `10.50.0.0/24`, link an SNAT rule with translated source **MASQ**. MASQ makes the connection appear to originate from the Sophos LAN address, preserving the return path. Do not configure DNAT or PAT for this VPN-to-LAN rule.

## 7. Client enrollment

1. Sign in to `https://<PUBLIC_IP_OR_DDNS_NAME>/vpnportal`.
2. Enroll OTP and download the SSL VPN `.ovpn` profile.
3. Install OpenVPN Connect and import the profile.
4. Connect using the assigned username and password+OTP.

Apple Silicon users should install the ARM64 OpenVPN Connect package.

## 8. Validation

```bash
ifconfig | grep 10.50
route -n get 10.10.10.2
nc -vz -w 5 10.10.10.2 8006
```

Expected: a `10.50.0.0/24` tunnel address, a host route via `utun`, TCP 8006 succeeds, other LAN services remain denied, and Sophos logs show the authenticated user.
