#!/bin/bash
# ea-egress-firewall.sh — executor egress allow-list (ADR-0003, D-APlus-egress/H1b)
# Mode 1 (docker): containers on ea-net (172.18.0.0/16) in the DOCKER-USER chain.
# Mode 2 (podman): rootless pasta egress carries the host alias 192.0.2.15
#   (containers pin it via EA_NETWORK=pasta:-o,192.0.2.15); the OUTPUT rules
#   below apply the same allow-list to exactly that source. Host traffic
#   (source 192.0.2.11) is untouched.
# Allow-list (both modes): intra-stack, registry :5000, Hindsight :8082,
#   llm-proxy :9999 (docker host-IP rule), internet TCP 80/443.
# Everything else drops (LAN lateral movement, other VMs, PVE host, router).
set -euo pipefail
LAN="192.0.2.0/24"
EA_NET="172.18.0.0/16"
REGISTRY="192.0.2.13"
HINDSIGHT="192.0.2.12"
BROKER="192.0.2.11"
PODMAN_SRC="192.0.2.15"

# docker mode: DOCKER-USER is traversed before Docker's own rules; insert each
# rule at position 1 in REVERSE policy order so the final chain order is
# established -> intra-net -> registry -> hindsight -> llm-proxy -> internet -> DROP.
add() { iptables -C "$1" "${@:2}" 2>/dev/null || iptables -I "$1" 1 "${@:2}"; }

# NOTE: reversed order on purpose — see comment above.
add DOCKER-USER -s "$EA_NET" -j DROP
add DOCKER-USER -s "$EA_NET" -p tcp -m multiport --dports 80,443 ! -d "$LAN" -j ACCEPT
add DOCKER-USER -s "$EA_NET" -d "$BROKER" -p tcp --dport 9999 -j ACCEPT
add DOCKER-USER -s "$EA_NET" -d "$HINDSIGHT" -p tcp --dport 8082 -j ACCEPT
add DOCKER-USER -s "$EA_NET" -d "$REGISTRY" -p tcp --dport 5000 -j ACCEPT
add DOCKER-USER -s "$EA_NET" -d "$EA_NET" -j ACCEPT
add DOCKER-USER -s "$EA_NET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# podman mode: pasta user-space egress pinned to the alias .250 (OUTPUT chain).
ip addr add "$PODMAN_SRC/24" dev ens18 2>/dev/null || true
add OUTPUT -s "$PODMAN_SRC" -j DROP
add OUTPUT -s "$PODMAN_SRC" -p tcp -m multiport --dports 80,443 ! -d "$LAN" -j ACCEPT
add OUTPUT -s "$PODMAN_SRC" -p udp --dport 53 -j ACCEPT
add OUTPUT -s "$PODMAN_SRC" -d "$HINDSIGHT" -p tcp --dport 8082 -j ACCEPT
add OUTPUT -s "$PODMAN_SRC" -d "$REGISTRY" -p tcp --dport 5000 -j ACCEPT
add OUTPUT -s "$PODMAN_SRC" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "ea egress policy applied (docker DOCKER-USER + podman OUTPUT alias pin)"
