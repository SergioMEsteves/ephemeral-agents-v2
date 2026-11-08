# V2 decision log — append-only

Every decision that shapes Version 2 is recorded here with its date,
rationale, and rejected alternatives. The V1 decisions are inherited from
the V1 record (`arvisdev/ephemeral-agents`, decision logs in
`deploy/m0/decision-log.md` and `deploy/m5/decision-log.md`, plus the book's
Chapter 12); this log starts at the V2 kickoff.

## 2026-11-08 · V2 kickoff — two-repo split

- **Decision:** Version 2 is developed in this **private** repository;
  the V1 record (`arvisdev/ephemeral-agents`) stays **public and frozen**.
- **Rationale:** GitHub visibility is per-repo, not per-folder. The V1
  record (thesis, design, proof, book) is a public artifact; V2 work needs
  private freedom. Two repos give both without per-folder ACLs (which
  GitHub does not offer) or mirror-push discipline (which risks leaks).
- **Rejected alternatives:** making the whole repo private at V2 (hides the
  public V1 record); keeping V2 in the public repo uncommitted (no version
  control for the most important work); fork-with-deletions (V1 content
  would remain in this repo's history; a fresh init with a hash citation is
  cleaner).
- **V1 baseline cited:** `arvisdev/ephemeral-agents @
  14bf62dc81729ed0ece355c30b5b6888d4fbf058`.

## 2026-11-08 — Baseline sync from the V1 record

- Synced the V1 record at `3c2b723` into this repo: the book (15 chapters,
  including the Evaluator's Guide and the reboot/restart lessons), the full
  executable layer (`deploy/`: idempotent install scripts, parameterized
  compose files, `deploy/restart-stack.sh`, operational notes in
  `deploy/README.md`), the license set, and the de-identified record
  documents (findings report, retrospective).
- All synced content carries V1's de-identification sweep: no IP addresses,
  usernames, passwords, or API keys in any tracked file; configuration values
  are env-driven (gitignored env files supply them at deploy time).
- Standing rule adopted: V2 begins from a synced baseline and stays synced —
  V1 fixes are backported here (and vice versa per the established
  convention); the reference hash above is re-cited, never "latest."
- First milestone unchanged: the Chief-of-Staff Hermes agent (see README).
