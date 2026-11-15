#!/usr/bin/env python3
# M5 §2' helper — idempotently set EA_EXECUTOR_DEFAULT=<default> in the live
# ea-m2 compose (the M3-era compose must not carry it: M2/M3 gates run the stub).
import sys

path, default = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines(keepends=True)
has = [l for l in lines if "EA_EXECUTOR_DEFAULT" in l and not l.strip().startswith("#")]
if not has:
    out = []
    for ln in lines:
        out.append(ln)
        if ln.strip().startswith("EA_IMAGE:"):
            out.append(f'      EA_EXECUTOR_DEFAULT: "{default}"\n')
    open(path, "w").write("".join(out))
    print("added")
else:
    print("already present")
