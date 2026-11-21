# TC-M4-03 / TC-M4-06 clone lookups — 2026-11-14

## TC-M4-03 — llm-wiki shallow clone from a spawned container (ea-net) ×3 lookups
Clone: git clone --depth 1 (x-access-token auth from LLM_WIKI_READ_TOKEN) → SHA 425b5bcd9df0
- (a) design standard: design-standards/README.md — FOUND
- (b) dev best practice: dev-best-practices/evidence-first-debugging.md — FOUND
- (c) skill/tool topic: tools-and-skills/README.md — FOUND (placeholder stub awaiting curation; readable via README)
3/3 found. PASS.

## TC-M4-06 — curation cycle
Curation push (HITL per D-curation): commit bc1fcd25a7af — new doc `dev-best-practices/coexistence-port-allocations.md` (V2 M4 coexistence lesson); CHANGELOG entry 6776fd1888e2.
Fresh shallow clone from spawned container: SHA 6776fd1888e2.
- new doc FOUND: dev-best-practices/coexistence-port-allocations.md (content verified: "# Coexistence: port allocations on shared VMs (2026-11-14)")
- old docs still readable: dev-best-practices/evidence-first-debugging.md, design-standards/, tools-and-skills/ — all FOUND
PASS: new doc found; no regression on TC-M4-03's lookups.
