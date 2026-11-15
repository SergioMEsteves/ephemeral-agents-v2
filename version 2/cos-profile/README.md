# CoS profile — VM-Xa resident Hermes Agent (M1/TP-V2-M1)
#
# Configuration, not custom code (M1 D3/§4): this directory is the profile
# wiring for the persistent Chief-of-Staff Hermes profile on vm-xa, deployed
# as an additional service of the ea-m5 compose (restart: unless-stopped,
# reboot-safe per book ch14 §14.8).
#
# Persona: bus-org/chief-of-staff from the roster repo — cloned at boot by
# the entrypoint (the executor hydration contract's first persistent
# consumer, M1 §4), then referenced by AGENTS.md.
#
# Credential contract (M1 §5 — asserted both ways by TP-V2-M1 assertion 6):
#   exactly FOUR env items, nothing else:
#     1. MODEL_API_BASE / MODEL_API_TOKEN — llm-proxy CoS-class token
#        (the proxy holds the provider key; cross-VM to vm-xb, allow-list
#        admits vm-xa)
#     2. GATEWAY_SESSION_TOKEN — inbound desktop↔CoS gateway auth
#     3. GATEWAY_API_TOKEN — outbound gateway client credential (submit
#        approved packages, read reports; ordinary client scope)
#     4. HINDSIGHT_URL / HINDSIGHT_WRITE_TOKEN — pointer writes after each
#        report lands (CoS-only write class)
#   Denied: no GitHub token, no broker/Temporal access, no direct manager
#   access beyond the gateway API, no registry write, no ssh keys.
#   The board is NOT a credential — it is native profile state (D12).
#
# State: the kanban board lives in the profile's own state dir (bind mount,
# reboot-durable) — the state store of record for submit-side intent
# (D12/ADR-0001). Desk-never-the-door: no code path moves a card to
# "submitted" except the approval flow.

The CoS system prompt lives in `AGENTS.md` (referenced by the profile via `AGENTS_MD`). The entrypoint is `cos-entrypoint.sh`.
