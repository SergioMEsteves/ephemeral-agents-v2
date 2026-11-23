# Special 3 — Connecting your Desktop to a project

> **In plain terms.** The system does nothing for you until your Desktop
> can reach the project's agent machine. This piece walks the one-time
> connection: what a "gateway connection" is, the seven steps to register
> one, what the session token is (and why it is the *only* credential the
> Desktop ever holds), how to test the link, and what each failure means
> when the test does not pass. It is written so a non-technical reader can
> follow it end to end; the operator's gate version of the same procedure
> is stage S7 of `deploy-v2/RUNBOOK-V2-BUILD.md`.

## What you are connecting to

Every project lives on its own agent machine (the VM-Xlg / VM-Xsm
templates, ADR-0002). On that machine, three things run:

- the **CoS** — the resident Hermes agent you will actually talk to
  (the `cos` profile, served by `hermes serve`);
- the **pipeline gateway** — the Go service that turns an approved
  submission into real work on the queue;
- the **manager** — the validator that checks every package before it
  is allowed to start.

The connection you register points at the **CoS backend**, not the
pipeline gateway: it is the long-lived Hermes service on the agent
machine, published on its own port (the deployment pins it at `:8084`,
while the pipeline gateway answers on `:8083`). Everything else — the
approval flow, the submission, the workers — happens *behind* the CoS.
Your Desktop only ever needs to reach the CoS.

## The session token: the one credential

When the CoS backend starts, the deployment stages a **session token** —
a long random string the backend requires on every request. Think of it
as a door key for this one agent machine:

- It lives in a gitignored file on the machine (never in the repo, never
  in chat).
- The Desktop stores it once, in the connection entry, and sends it with
  every request.
- **The Desktop holds only this token.** Its own credentials — its
  accounts, its keys, its memory — are never inherited by the CoS. The
  CoS cannot read your Desktop; it can only answer you. That is the
  link-security rule (M1 design §3), and it is why the Desktop can be
  trusted to talk to a machine that does work on your behalf.

## The seven steps

1. **Get the token.** The person who deployed the machine gives you the
   session token (or points you at the file it lives in). If you
   deployed it yourself, here is exactly where it is on the reference
   estate:

   - Machine: the agent machine (VM-Xa) — static address `192.0.2.10`
     in the reference estate, SSH user `poc`.
   - File: `/opt/ea/deploy-v2/m5/.env` on that machine — a gitignored,
     permission-0600 file the deployment staged. The variable you want
     is `COS_SESSION_TOKEN`.
   - Reading it: from the workstation,
     `ssh poc@192.0.2.10 'grep COS_SESSION_TOKEN /opt/ea/deploy-v2/m5/.env'`.
     Copy everything after the `=` sign. The token never belongs in the
     repo, in chat, or in a screenshot.

   Before moving on, confirm the thing you are about to connect to is
   actually running: `ssh poc@192.0.2.10 'docker ps --format
   "{{.Names}}" | grep ea-m5-cos'` should print `ea-m5-cos`. A token
   test against a stopped backend reads as "unreachable" and sends you
   debugging the wrong layer.
2. **Open the Desktop's gateway registry.** Settings → **Gateways**.
   This is the list of machines your Desktop knows how to talk to.
3. **Add a connection.** "Add connection" → **Remote gateway**.
4. **Name it.** Use the project name — this is how the connection shows
   up in the Sessions sidebar. One name per project (the desktop stays
   stateless; a project *is* a named connection).
5. **Enter the URL.** `http://<agent-machine-address>:<cos-port>` —
   for the reference estate: `http://192.0.2.10:8084`. The address
   is the agent machine's static IP; the port is the CoS backend's
   published port from the deployment.
6. **Paste the session token.** Choose session-token auth; paste the
   token from step 1. Save.
7. **Test.** Click **Test** on the connection row. Expect
   **"Reachable"** — the test exercises both the HTTP path and the
   WebSocket path chat actually uses.

That's it. The registry reconnects on its own after a restart of either
side — you do not need to redo this after a machine reboot (the
reconnect-after-reboot property is TP-V2-M1 assertion 12, gate-asserted).

## Using the connection

Once a connection is Reachable, open a session on it from the Sessions
sidebar. You will see the project's profiles (the `cos` profile is the
Chief of Staff). From there, the rules are Special 1 and Special 2: you
ask, the CoS proposes, you approve *in the tracker*, and the work
happens on the queue. Nothing starts because you chatted — only
approval starts work.

## If the test fails

Three failure modes, each with a distinct cause:

| Symptom | Likely cause | What to do |
|---|---|---|
| Timeout / unreachable | The machine is down, the CoS container is stopped, the port is wrong, or the firewall is closed | Confirm the machine answers (`ping` the address), confirm the CoS container is up (`docker ps | grep ea-m5-cos` on the agent machine), confirm the port matches the deployment (`:8084` for the CoS, `:8083` is the pipeline gateway — pointing the Desktop at 8083 connects you to the wrong service), and check the machine's firewall allows your subnet |
| 401 / unauthorized | The stored token does not match the token the backend is running | The token was rotated or the connection holds a stale copy — re-stage the token and re-paste it. On the reference estate that means re-reading `COS_SESSION_TOKEN` from `/opt/ea/deploy-v2/m5/.env` on VM-Xa — the container reloads it only on restart, so if the file changed, restart the CoS container, then paste the new token |
| HTTP passes but chat hangs | The WebSocket path is blocked | Something between Desktop and machine is blocking `/api/ws` — check any proxy in the path; the plain HTTP test can pass while WebSocket fails |

One habit worth keeping: after any restart of the agent machine, if a
session behaves oddly, run **Test** first. A redial usually fixes it
silently; a failed Test tells you which of the three rows above you are
in.

## What this piece is not

This is the one-time wiring, not the workflow. It does not cover what
the CoS does with a request (ch10, The Front Door), what approval means
(Special 2), or who may start work (Special 1) — read those next. And
per ADR-0002, a second project means a second connection: same seven
steps, its own token, its own name — the Desktop's registry holds one
entry per project, and a project's board and conversations are never
visible through another project's connection.
