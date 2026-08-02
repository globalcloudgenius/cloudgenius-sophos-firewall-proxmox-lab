# Public Evidence Guide

## Publish

- Sanitized architecture diagrams
- Redacted VM resource summaries
- Zone and interface names without sensitive identifiers
- High-level firewall-policy matrices
- Test results
- Business outcomes
- Lessons learned
- Product version and update status
- Non-sensitive logs demonstrating expected behavior

## Do not publish

- Trial serial numbers or license files
- Usernames, passwords, MFA data, or recovery codes
- Public IP addresses
- MAC addresses when unnecessary
- Private keys, certificates, API tokens, or cookies
- Unredacted browser URLs containing internal hosts
- Employer or client data
- Sophos installation binaries
- Full production firewall exports
- Screenshots showing personal email or account identifiers

## Suggested folders

```text
evidence/
├── architecture/
├── installation/
├── policies/
├── testing/
└── operations/
```

Add evidence only after completing the relevant milestone. Name files clearly, for example:

```text
T05-guest-to-lan-denied-redacted.png
firewall-policy-matrix-v1.md
proxmox-vm-resources-redacted.png
```
