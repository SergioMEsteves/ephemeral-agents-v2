# TP-M4 — Memory & Knowledge Access Gate results (V2, 2026-11-14)

Gate scoreboard — all seven mandatory cases PASS:

| ID | Case | Verdict | Evidence |
|---|---|---|---|
| TC-M4-01 | Hindsight network R/W (from spawned-agent container) | PASS | readback.txt — write persists; read-back equals written body |
| TC-M4-02 | Cross-task read-back | PASS | readback.txt — t3's q-driven recall payload contains t2's learning; scope rule holds |
| TC-M4-03 | llm-wiki clone + read ×3 | PASS | retrieval-hits.md — 3/3 (design standard, dev best practice, tool/skill topic), clone SHA 425b5bcd9df0 |
| TC-M4-04 | Catalog regression + wiring | PASS | m4-tests.txt G4 + vm-xb task log b1-004300-1 self-report (sources: agent_repo true, llm-wiki cloned, hindsight true; boot 2106 ms); worker/lifecycle images unchanged: ea/worker:1.0.0 sha256 afef41e44ce7… + ea/lifecycle:1.0.0 (M2-era builds, no M4 code redeploy) |
| TC-M4-05 | Hydration latency ×3 | PASS | latency-table.txt — 3/3 totals 0.92/0.80/0.79 s (clone 0.6–0.73 s, hindsight 10 ms, catalog 0.17 s) vs TTL 600 s ≈ 99.8% headroom |
| TC-M4-06 | Curation cycle | PASS | retrieval-hits.md — commit bc1fcd25a7af (new doc) + CHANGELOG 6776fd1888e2; fresh clone 6776fd1888e2: new doc FOUND, old docs FOUND |
| TC-M4-07 | Data isolation | PASS | isolation-check.txt — ea-hindsight-pg (pgvector/pg16, vm-hindsight, volume ea-hindsight_ea-hindsight-pg-data) distinct engine+host from Temporal's postgres:16 (vm-xb); V1's hindsight_hindsight-pg-data untouched; zero wiki containers/images (D-wiki-git) |

Abort conditions: none triggered.

## Coexistence note (V2-specific, beyond V1's TP)
- V2 hindsight = compose project `ea-hindsight`, host port 8082 (V1 keeps 8081), own volume — G6 isolation + TC-M4-07 double-verify.
- V2-specific V1 deviations: compose project/container names ea-*, own volume ea-hindsight-pg-data (fresh store, single t-g1 entry — V1 rows absent proves routing + isolation).

## Root-cause ledger (V2 M4 install + gate)
1. V2 compose initially kept V1's project name `hindsight` → compose up took over V1's stack and data volume. Fixed: project `ea-hindsight`, containers `ea-hindsight-*`, own volume, port 8082:8081 (commit 0209ffb). Restoration sequence executed; both stacks coexist.
2. HINDSIGHT_PORT made env-overridable (default 8082) in m4/install.sh; UFW rule + §2 wiring follow the var.
3. §2 wiring check now reads m3.env (env_file mechanism — HINDSIGHT_URL rides into executors via lifecycle spawn env), not a compose line grep.
4. Evidence snippet masks LLM_WIKI_READ_TOKEN (middle elided) — de-identification rule.
5. TP lookups needed an image with both git+curl (alpine/git lacks curl; nested-sh invocation garbles) — test-side only, no estate change.

## Informational
- I-M4-01: curation note in llm-wiki CHANGELOG.md (HITL-owned, append-only, commit 6776fd1888e2).
- I-M4-02: embedding provider — none staged; EMBEDDINGS=none zero-vector fallback active (D-embed). Reads are q-driven and functional (TC-M4-01/02 prove); semantic ranking remains the open D-embed item.

Signed: Hermes on owner's behalf per standing authorization (2026-11-05; all-PASS with evidence).
