#!/bin/bash
# H3 trajectory sampler (D-eval-ci): monthly review input over the retained
# per-task logs. Run on the execution VM: sudo bash -s < this file.
# Prints a boundary-adherence summary from durable per-task artifacts only;
# a human reads it — it judges nothing.
set -u
LOGDIR=/var/ea/tasks
WINDOW_DAYS=30
cutoff=$(date -d "-$WINDOW_DAYS days" +%s)
echo "== trajectory sample $(date -u +%Y-%m-%dT%H:%M:%SZ) (window: last ${WINDOW_DAYS}d) =="
total=0; booterr=0; hydrated=0
for f in "$LOGDIR"/*.log; do
  [ -e "$f" ] || continue
  m=$(stat -c %Y "$f"); [ "$m" -ge "$cutoff" ] || continue
  total=$((total+1))
  tid=$(basename "$f" .log)
  flags=""
  if grep -q '"error"' "$f" 2>/dev/null; then booterr=$((booterr+1)); flags="$flags boot-error"; fi
  if grep -q 'UNTRUSTED MEMORY' "$f" 2>/dev/null; then hydrated=$((hydrated+1)); flags="$flags memory-hydrated"; fi
  sz=$(stat -c %s "$f")
  printf '%s  %-40s %7dB%s\n' "$(date -u -d @$m +%Y-%m-%dT%H:%MZ)" "$tid" "$sz" "${flags:+  flags:[$flags]}"
done
echo "--"
echo "task logs in window: $total   boot-error: $booterr   memory-hydrated: $hydrated"
echo "reading guide: the per-task log carries the executor boot self-report"
echo "(hydration provenance, boot time). Post-H2, hydrated memory appears only"
echo "inside UNTRUSTED MEMORY markers. Task outcomes (complete/failed) live in"
echo "the reports the manager serves (GET /gateway/reports/<task_id>); out-of-"
echo "scope pushes are visible in the repo's task branches. A boot-error rate"
echo "above ~10% in the window is a P1 for the next session."
