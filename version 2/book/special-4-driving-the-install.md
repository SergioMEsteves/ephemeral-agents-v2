# Special 4 — Driving the install from your Desktop

> **In plain terms.** Deploying this system used to mean reading a
> runbook and typing each command yourself. It does not anymore. You
> collect your inputs into one file, install one skill on your
> workstation's Hermes agent, and then *ask* it to run the build. The
> agent executes the runbook stage by stage — and, exactly like a human
> operator would, it stops at every gate, shows you the evidence, and
> waits for your go. This piece explains when to use it, where it runs
> from, and how a build day actually goes.

## When to use it

Use the install skill when you are bringing the system up on machines —
the first time, or re-building after a change. Do **not** use it for
day-to-day work: once the estate is up, you talk to the Chief of Staff
(book ch10, Specials 1–2). The install skill is the *construction crew*;
the CoS is the *building's manager*.

The right moment is defined by the checklist
(`deploy-v2/INSTALL-INPUTS-CHECKLIST.md`): accounts created, keys
gathered, four VMs addressed, inputs.yaml filled in and validated. When
that checklist's stop conditions are all true, you are ready.

## Where it runs from — and where it must never run from

The install runs from your **workstation's own Hermes agent** — the same
agent you chat with in the Desktop, on the machine that holds your SSH
keys and can reach every VM. That is the only machine with the right to
build.

It must **never** run from a remote session — from a project's CoS agent
or any gateway on an agent machine. The rule is the system's own first
principle: *the agent proposes, the code disposes* — an agent that
deploys its own estate would be both the proposer and the enforcer. The
skill refuses to run from a remote session and tells you why.

## How to set it up (once, ~5 minutes)

1. **Install the skill.** Copy `deploy-v2/skills/ea-install/` into your
   workstation agent's skills directory (`~/.hermes/skills/`). It
   appears as `ea-install` and loads automatically when you ask for an
   install.
2. **Fill in `deploy-v2/inputs.yaml`** (copy from
   `inputs.yaml.example`; every field has an EXAMPLE comment showing
   what real data looks like). Secrets are referenced by *path* only —
   the file must never contain an actual token or key.
3. **Validate:** ask the agent to run
   `python3 deploy-v2/render-inputs.py deploy-v2/inputs.yaml --check`.
   It checks the file against the schema, verifies every referenced key
   file exists, and refuses anything that looks like a pasted secret.
4. **Render:** `--render` writes the machine inventory the install
   scripts read and prints the staging plan — which secret lands on
   which machine at which stage.

## What a build day looks like

You say:

> *"Run the ephemeral-agents install. Use deploy-v2/inputs.yaml, follow
> the runbook, and stop at every gate for my approval."*

Then the agent works the runbook the way a careful operator would:

- **Pre-flight** — it checks the repo, the workstation tools, the
  validated inputs, and that it can reach all four machines by SSH
  without a password. Anything missing: it stops and tells you exactly
  what.
- **Stage by stage** — for each stage (chassis, registry, broker +
  engine, services, memory, front-of-house + CoS, desktop): a dry run
  first (`--check-only`), then the real apply, then the stage's gate —
  the test that proves the stage actually works.
- **At every gate it stops** and shows you: PASS or FAIL, the evidence
  file, what the next stage is. You say go (or don't). Nothing advances
  past a failed gate — that is the system's core discipline, and the
  agent is bound by it just like a human would be.
- **On a failure** — it diagnoses from the evidence, checks the project's
  issue ledger (most failure modes are already recorded there with their
  root cause and the rule that prevents them), attempts one fix, re-runs
  the gate. If it fails a second time, it stops and brings you the
  evidence and a recommendation — it will not keep trying on its own.
- **At the end** — a full gate table, the evidence paths, and the
  reminder to sign the test-procedure records. The final stage hands
  you the seven-step Desktop connection (Special 3), because only you
  can click it.

## What the agent will never do

- Never read a secret's value — it handles keys by file path, and the
  input validator refuses a file that contains a pasted secret.
- Never skip a stage, reorder stages, or run a stage whose predecessor's
  gate failed.
- Never work from a remote/CoS session.
- Never attempt more than one unapproved fix on a failing gate.

## The honest boundary

The agent executes; you still decide. The inputs are yours (the
checklist), the approvals at every gate are yours, the Desktop
connection is yours, and the signatures on the test-procedure records
are yours. The skill removes the typing, not the judgment — which is
the point: the build stays gated, auditable, and yours, whether a human
or an agent does the typing.
