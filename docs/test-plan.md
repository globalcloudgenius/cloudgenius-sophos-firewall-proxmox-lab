# Validation Test Plan

## Test status values

- Not started
- Passed
- Failed
- Blocked
- Not applicable

## Functional and security tests

| ID | Test | Expected result | Status |
|---|---|---|---|
| T01 | VM boots with both disks attached | Sophos console loads normally | Not started |
| T02 | Administrative workstation reaches management UI | Access works only from approved source | Not started |
| T03 | LAN client reaches approved internet services | Traffic is allowed, NATed, and logged | Not started |
| T04 | Guest reaches internet | Approved outbound traffic succeeds | Not started |
| T05 | Guest attempts LAN access | Connection is denied and logged | Not started |
| T06 | Guest attempts management access | Connection is denied and logged | Not started |
| T07 | DMZ attempts unauthorized LAN access | Connection is denied and logged | Not started |
| T08 | Approved LAN-to-DMZ application flow | Only documented ports succeed | Not started |
| T09 | Unsolicited inbound WAN traffic | Traffic is denied unless explicitly published | Not started |
| T10 | DNS resolution from each permitted zone | Approved DNS path succeeds | Not started |
| T11 | IPS safe validation scenario | Policy triggers or records expected event | Not started |
| T12 | Web/application policy test | Selected policy is enforced | Not started |
| T13 | VPN authentication and routing | Authorized access works as designed | Not started |
| T14 | Configuration backup | Backup completes and is protected | Not started |
| T15 | Restart test | Firewall returns to healthy state | Not started |
| T16 | Log and report review | Required events are visible and timestamped | Not started |

## Evidence requirements

For each completed test, record:

- Date
- Tester
- Configuration version
- Test source and destination
- Expected result
- Actual result
- Evidence filename
- Remediation, if required
- Retest result

Use benign validation traffic. Do not publish exploit payloads, credentials, public IP addresses, or private infrastructure details.
