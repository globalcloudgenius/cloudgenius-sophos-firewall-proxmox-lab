# Public Evidence and Secret Handling

## Safe to publish

- Sanitized topology and address-role diagrams
- Product and firmware version
- VM resource allocation
- Generic policy matrices
- Redacted test results
- Backup method and restore procedure

## Never publish

- Sophos serial numbers or license records
- Public IP addresses or dynamic-DNS names
- Account email addresses or real usernames
- Passwords or browser-saved-password dialogs
- OTP QR codes, Base32/HEX secrets, OTP values, or recovery codes
- Private keys, certificates, cookies, or exported VPN profiles
- Full MAC addresses
- Router Wi-Fi SSIDs or passphrases
- Unredacted internal/admin URLs
- Sophos ISO files or proprietary binaries
- Firewall/Proxmox backup archives

A blurred value may still be recoverable. Prefer cropping or replacing it with a solid placeholder.

## Pre-commit review

```bash
git diff --check
git grep -nEI 'password|passphrase|secret|serial|BEGIN (RSA|OPENSSH|PRIVATE)|[0-9]{6}.*OTP'
git status --short
```

Review every image manually; text scanners cannot detect screenshot secrets. If an OTP secret or private key was published, remove it from history and rotate it immediately.
