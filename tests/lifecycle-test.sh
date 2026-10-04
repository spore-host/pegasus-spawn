#!/usr/bin/env bash
# Unit check for the TaskSpec lifecycle block (pegasus-spawn#5).
#
# This repo has no Python test framework — it is a wrapper script plus a
# DAGMan-composition test — so this exercises _lifecycle() directly by loading
# bin/pegasus-spawn-run as a module. Cheap, offline, no Pegasus and no AWS.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import importlib.machinery, importlib.util, os, sys

loader = importlib.machinery.SourceFileLoader("pgs", "bin/pegasus-spawn-run")
spec = importlib.util.spec_from_loader("pgs", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)


def lifecycle(**env):
    for key in ("SPAWN_COST_LIMIT", "SPAWN_TTL"):
        os.environ.pop(key, None)
    os.environ.update(env)
    return mod._lifecycle()


BASE = {"ttl": "4h", "on_complete": "terminate"}

cases = [
    # name, got, want
    ("unset leaves spawn's default", lifecycle(), BASE),
    ("a positive cap is emitted", lifecycle(SPAWN_COST_LIMIT="0.05"),
     {**BASE, "cost_limit": 0.05}),
    ("whitespace survives a shell export", lifecycle(SPAWN_COST_LIMIT="  1.5 "),
     {**BASE, "cost_limit": 1.5}),
    ("empty is unset", lifecycle(SPAWN_COST_LIMIT=""), BASE),
    # A zero cap would mean "terminate immediately", never what someone typing 0
    # intends.
    ("zero is unset", lifecycle(SPAWN_COST_LIMIT="0"), BASE),
    ("negative is unset", lifecycle(SPAWN_COST_LIMIT="-1"), BASE),
    # A typo in a site config must not kill a workflow that is otherwise fine; it
    # degrades to "bounded by TTL only", which is the previous behaviour.
    ("junk degrades rather than failing", lifecycle(SPAWN_COST_LIMIT="lots"), BASE),
    ("ttl and cap coexist", lifecycle(SPAWN_TTL="30m", SPAWN_COST_LIMIT="2"),
     {"ttl": "30m", "on_complete": "terminate", "cost_limit": 2.0}),
]

failed = 0
for name, got, want in cases:
    ok = got == want
    failed += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if not ok:
        print(f"       got  {got}\n       want {want}")

if failed:
    print(f"\n{failed} lifecycle case(s) failed", file=sys.stderr)
    sys.exit(1)
print("\nall lifecycle cases passed")
PY
