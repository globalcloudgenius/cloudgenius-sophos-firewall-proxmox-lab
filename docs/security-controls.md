# Security Controls

## Control objectives

| Control area | Implementation objective | Evidence |
|---|---|---|
| Administrative security | Management zone and approved source devices only | Sanitized access settings |
| Authentication | Strong unique credentials and supported MFA where available | Configuration confirmation |
| Segmentation | LAN, DMZ, guest, management, and WAN separation | Interface/zone diagram |
| Least privilege | Default deny and explicitly justified allow rules | Policy matrix |
| Threat prevention | IPS and licensed protections on relevant traffic | Policy and event evidence |
| Egress control | Restrict unnecessary outbound services | Rule review |
| Inbound exposure | Publish only approved services with NAT and protection | NAT/policy record |
| Logging | Log security decisions and administrative events | Report screenshots |
| Patch management | Maintain supported SFOS firmware and patterns | Version record |
| Backup | Encrypted/protected configuration backup and restore procedure | Backup log |
| Change management | Document purpose, testing, approval, and rollback | Change record |
| Privacy | Remove secrets and identifiers from public evidence | Evidence checklist |

## Minimum firewall policy fields

Every policy must document:

- Rule name
- Business purpose
- Source zone and network
- Destination zone and network
- Services
- Users or identity conditions
- Action
- NAT behavior
- Security profiles
- Logging
- Owner
- Review or expiry date

## Example policy intent

| Source | Destination | Service | Action | Notes |
|---|---|---|---|---|
| Management | Sophos admin | HTTPS administration | Allow | Approved admin devices only |
| Guest | Internet | DNS, HTTP/S | Allow | Apply security profiles |
| Guest | Internal zones | Any | Deny | Log violations |
| LAN | DMZ | Required application ports | Allow selectively | No broad any/any |
| WAN | Internal zones | Any | Deny | Publish approved services separately |

## Portfolio boundary

This repository documents architecture and implementation patterns. It must not contain working credentials, private certificates, serial numbers, public administrative endpoints, or security configurations copied from an employer or client.
