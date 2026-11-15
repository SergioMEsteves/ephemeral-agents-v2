# Chapter 8 — Credentials

> **In plain terms.** V1's rule stands: a worker gets its own key, made for
> its one task, scoped to the one place it needs to write, and destroyed
> when the task ends — with the destruction *proven*. V2 keeps the
> mechanism and hardens the proof: the token is issued, *verified working*,
> revoked, and then verified dead again — with the dead-check timed to
> outlast the provider's revocation propagation. And the estate now carries
> a second, blunt invariant with its own enforcement sweep: **no long-lived
> owner secret sits in any container.**

## 8.1 The principle, carried forward

The five properties from V1 (Chapter 2, P5 — least privilege, provably
brief) hold verbatim in V2: issued per task, scoped, short-lived, revoked
at completion, and proven dead. What the V2 build changed is not the
principle but the *evidence discipline*: every property in this chapter
exists as a gate assertion that runs live against the real provider, and
two of the build's own failures taught the assertions their current shape.

## 8.2 Per-run App installation tokens

The mechanism is V1's, re-proven under the `ea-` estate: an
organization-owned application identity whose private key lives on the
issuer VM — and nowhere else. Per run:

```
work order accepted
   → the issuer signs a short-lived assertion with the app's private key
      (RS256, iat back-dated 60 s, exp = iat + 540 s — 9 minutes,
      one minute under the provider's 10-minute cap)
   → exchanges it for an installation token (provider caps its TTL at 1 h)
   → the lifecycle injects ONLY that token into the spawn environment
   → worker clones, branches, edits, pushes — with this token alone
   → task ends; the reaper revokes the token
   → a verification call with the dead token returns 401 (proven)
```

The V2 build added a middle step to the proof, and it matters: the
verification call is a **repo-scoped read of the catalog repository**,
asserted *200* before revocation. Installation tokens are repo-scoped —
they authenticate against repository contents and are refused on the
identity endpoint — so a working check against the repo both proves the
token live *and* demonstrates its scope in the same call. The full loop —
issue → verified 200 → revoke → verified 401 — is gate evidence, not a
log line.

The coexistence period added a custody rule of its own: V2 did **not
mint** a new App identity. The live V1 app key was staged (copied, never
printed, permissions 0600) into the V2 issuer path — one organization, one
installation, one identity per estate while both organizations coexist.
Minting a second App to run beside the first would have created two
identity domains on one estate; the credential-preservation rule that
V2 learned for data volumes (ledger 3) applied to identity too.

## 8.3 Propagation-aware revocation

"Revoked" is a claim; "revoked" plus a timed dead-check is a result. The
V2 assertion: after the revoke call, the check **sleeps past the
provider's propagation window (5 seconds) before asserting 401**.

The sleep exists because the race is real and was observed live: an
earlier hardening run asserted the dead-check *immediately* after revoking
and read **200** — the token still authenticating while the revocation
propagated. Nothing was wrong with the revocation; the assertion was
faster than the truth. A propagation-aware check converts that
flakiness into determinism: the test now outlasts the window rather than
competing with it.

This is the credential chapter's version of a theme the whole build
repeats: **timing assertions must be derived from the observed behavior of
the real dependency, not from the convenience of the test script.**

## 8.4 Case study: `$tok: unbound variable` (ledger 13)

The dead-check itself had a defect first, and it failed in the most
silencing way possible.

**The symptom.** The hardening run died silently between "issued token →
200" and the revoke step. Under `set -u`, the post-revoke verification
referenced a variable (`$tok`) that the pre-revoke check had never
assigned — the pre-revoke check used `$src` — so the shell aborted at the
dead-check and the token was never revoked *in that run's flow*. The
failure surfaced only because the run's output stopped mid-sequence;
nothing errored loudly.

**The masking hazard.** The two variables were indistinguishable in the
terminal: the session's display masking renders secret-like strings as
`***`, so `$src` and `$tok` looked identical on every read of the script
— twice in this build, a *correct* file looked broken and a *broken* file
looked fine because display output was trusted. The rule now in force:
file contents are verified byte-level, never by display output.

**The rules (ledger 13).** Both halves of a lifecycle check read the
**same variable**; a revocation check sleeps past propagation (5 s)
before asserting; and the dead-check's expected status is 401, asserted,
not assumed. The fixed loop is what §8.2 describes — and it is the loop
that caught the propagation race of §8.3 on the next run.

## 8.5 No long-lived owner secret in any container

V2 states the boundary that V1 practiced: **every long-lived credential is
owned by exactly one service, and no container — executor or otherwise —
ever holds an owner-level secret.**

- **The provider credential follows the llm-proxy pattern.** The model
  router's API key is owned by the one service that owns the provider
  relationship (the llm-proxy); executors reach that service and carry
  only spawn-scoped, per-run keys injected at birth. A compromised
  executor yields a token that dies with the task — not the owner's
  standing identity.
- **The app private key lives on the issuer VM only**, 0600, never in an
  image, never in git. Workers receive its *product* (the per-run token),
  not the key.
- **The enforcement is a sweep, not a policy.** The M5 hardening stage
  inspects the environment of *every running container* for owner
  long-lived token patterns — any hit fails the install — and a secret
  scan runs against all nine deployed images. Zero findings is the pass
  condition; the scan evidence is filed per image.
- **Named residuals.** The two pinned agent runtimes bundle their own
  dependency trees, so their language-package findings are an accepted,
  decision-logged residual — fixes live upstream, and the refresh is a
  tracked item (Chapter 13). Secrets are not among them: the secret half
  of the scan is clean everywhere.

## 8.6 What each component may hold

The V2 edition of the trust map:

| Component | Holds | Never holds |
|---|---|---|
| Credential issuer (execution VM) | App private key (0600), issuer env (0600) | Anything in a container; nothing printed |
| Worker containers | One per-run installation token, in env | Any owner secret, any long-lived credential |
| llm-proxy | The provider API key (the one service that owns it) | — (it is the designated owner) |
| Front-of-house | A read-only catalog token | Any write credential |
| Human operator | Personal account, outside the system | Nothing injected into workers |

The invariant underneath the table, now enforced by the §8.5 sweep: **if a
container env contains an owner long-lived token, the architecture is
wrong — and the install dies.**

## 8.7 Design decisions and alternatives

**Decision: verify live *and* dead, repo-scoped.** V1 proved deadness;
V2 also proves liveness against the scoped resource before revoking. A
token that fails the pre-revoke check means the issuance path is broken —
a failure the dead-only check would have misread as success.

**Decision: sleep past propagation, then assert.** The alternative —
retry-until-401 — blurs a timing fact into eventual consistency. The
explicit sleep encodes the measured behavior of the provider and makes
the check deterministic and fast.

**Decision: same-variable discipline by construction.** The `$tok`/
`$src` split (ledger 13) is the argument: a lifecycle check is one
sequence over one variable, and the display-masking rule pushes all
verification to byte-level reads.

**Decision: one App identity per estate, staged not minted.** During
coexistence, V2 inherits the V1 identity rather than splitting it. A
second App would double the trust surface and orphan half the audit
trail; inheritance keeps one blast radius and one story.

## 8.8 The trust story in one paragraph

A skeptical auditor asks: "Your AI worker edited a repository. What could
it touch?" The V2 answer, with the mechanism: *one repository, one branch
it created itself, with a token that was verified working against exactly
that scope, then revoked, then — five seconds later, past the provider's
propagation window — verified dead with an asserted 401; while a sweep
proves no stronger credential ever entered any container's environment.*
No policy document says this; the assertion sequence says it. The
difference between trusting a system and verifying one is that every
clause of that sentence is a gate case with filed evidence.
