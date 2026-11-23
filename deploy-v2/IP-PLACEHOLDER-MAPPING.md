# IP placeholder mapping — de-identification for publication

The estate's real LAN addresses (RFC 1918, 192.0.2.0/24) are replaced
throughout this repository — tracked files **and full git history** — with
RFC 5737 documentation-range addresses (192.0.2.0/24, TEST-NET-1: reserved
for documentation, unroutable on the public internet). This makes the
"no real infrastructure identifiers in any downloadable artifact, history
included" rule hold for a public reader.

| Role | Real address | Placeholder |
|---|---|---|
| Router (gateway) | 192.0.2.254 | 192.0.2.254 |
| Proxmox host | 192.0.2.1 | 192.0.2.1 |
| VM-Xa (front-of-house) | 192.0.2.10 | 192.0.2.10 |
| VM-Xb (execution) | 192.0.2.11 | 192.0.2.11 |
| vm-hindsight (memory) | 192.0.2.12 | 192.0.2.12 |
| vm-docker-registry | 192.0.2.13 | 192.0.2.13 |
| (earlier registry address) | 192.0.2.14 | 192.0.2.14 |
| test clone vm-xlg-xa | 192.0.2.23 | 192.0.2.23 |
| test clone vm-xlg-exec | 192.0.2.22 | 192.0.2.22 |
| test clone vm-xlg-hindsight | 192.0.2.21 | 192.0.2.21 |
| test clone vm-xlg-registry | 192.0.2.20 | 192.0.2.20 |
| (doc example LAN) | 192.0.2.50–.53 | 192.0.2.50–.53 |
| (subnet literals) | 192.0.2.0/24 | 192.0.2.0/24 |

Rules:

- The substitution is mechanical and complete — a reader who wants to
  reproduce the estate substitutes their own addresses at the same roles;
  `deploy-v2/inputs.yaml` is the single source of truth for the real
  values, exactly as before.
- `10.0.0.1` appearing inside trivy evidence JSONs is quoted CVE
  description text (public upstream vulnerability prose), not an estate
  address — deliberately untouched.
- The placeholder form is the ranged literal (not `<vm-xa-ip>` prose
  placeholders) so render/validate paths in scripts and compose examples
  remain honest and greppable.
