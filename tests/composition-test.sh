#!/usr/bin/env bash
# composition-test.sh — proves DAGMan composes with the pegasus-spawn-run wrapper.
#
# Runs INSIDE a Pegasus + single-machine HTCondor container. With a stub `spawn`
# on PATH (no AWS), it drives real pegasus-plan + DAGMan and ASSERTS:
#   TEST 1 (happy path): both jobs' wrappers run in dependency order, exit 0 →
#     DAG succeeds (dagman.out reports DAG_STATUS_OK / all nodes Done), and BOTH
#     task_ids (greet, farewell) appear in the wrapper output.
#   TEST 2 (failure path): a wrapper exiting nonzero (FAKE_SPAWN_FAIL, delivered
#     as a per-transformation env profile so it reaches the job) → DAGMan marks
#     the node failed and the DAG fails; the downstream node does NOT run.
#
# Exits NONZERO if any assertion fails — so CI cannot be vacuously green.
set -euo pipefail

REPO="${REPO:-/work}"
export PATH="${REPO}/tests/stub-bin:${REPO}/bin:${PATH}"
export SPAWN_WORKDIR_S3="s3://fake-bucket/pegasus-spawn-test"
export SPAWN_REGION="us-east-1"

fail() { echo "COMPOSITION TEST FAILED: $*" >&2; exit 1; }

# HTCondor with DAGMAN_USE_STRICT treats a node log file under /tmp as a FATAL
# error, so run workflows from a non-/tmp scratch area under HOME.
WORKROOT="${HOME:-/home/scitech}/pegwf-runs"
mkdir -p "$WORKROOT"

echo "=== starting HTCondor ==="
sudo condor_master 2>/dev/null || condor_master
for i in $(seq 1 30); do condor_q >/dev/null 2>&1 && { echo "condor up (${i}s)"; break; }; sleep 1; done
condor_version | head -1; pegasus-version || true

# Wait for DAGMan to finish in a submit dir, returning its dagman.out path.
wait_for_dag() {  # $1 = rundir
    local rundir="$1" do_file
    for _ in $(seq 1 120); do
        do_file=$(find "$rundir" -name '*.dag.dagman.out' 2>/dev/null | head -1)
        if [ -n "$do_file" ] && grep -q "EXITING WITH STATUS" "$do_file" 2>/dev/null; then
            echo "$do_file"; return 0
        fi
        sleep 5
    done
    return 1
}

# Plan+submit the example and return ONLY the run dir (no extra echoes).
plan_submit() {  # $1 = label ; uses env FAKE injection done by caller
    local label="$1" wfdir
    wfdir="$(mktemp -d "${WORKROOT}/pegwf-${label}.XXXXXX")"
    cp "${REPO}/examples/workflow.py" "$wfdir/workflow.py"
    ( cd "$wfdir" && python3 workflow.py >/dev/null \
        && pegasus-plan --sites local --output-sites local --dir "$wfdir/submit" --submit workflow.yml >/dev/null 2>&1 )
    find "$wfdir/submit" -name '*.dag' -printf '%h\n' 2>/dev/null | head -1
}

echo "=== TEST 1: happy path — DAG should SUCCEED ==="
RUNDIR1=$(plan_submit ok)
[ -n "$RUNDIR1" ] || fail "TEST 1: plan/submit produced no run dir"
DO1=$(wait_for_dag "$RUNDIR1") || fail "TEST 1: DAGMan did not finish in time"
grep -q "DAG_STATUS_OK" "$DO1" || fail "TEST 1: DAG did not report DAG_STATUS_OK:\n$(tail -15 "$DO1")"
# both wrapper task_ids present, in the two job stdouts
IDS=$(find "$RUNDIR1" -name '*.out*' -exec grep -h 'task_id=' {} \; 2>/dev/null | sort -u)
echo "$IDS" | grep -q 'task_id=greet'    || fail "TEST 1: greet wrapper did not run (ids: $IDS)"
echo "$IDS" | grep -q 'task_id=farewell' || fail "TEST 1: farewell wrapper did not run (ids: $IDS)"
echo "TEST 1 PASS: DAG_STATUS_OK, both greet+farewell wrappers ran in order"

echo "=== TEST 2: failure path — first job's wrapper exits nonzero, DAG should FAIL ==="
# Deliver the fail trigger as a per-transformation env profile (submit-shell env
# does NOT reach the job — HTCondor only passes declared profiles).
FAILWF="$(mktemp -d "${WORKROOT}/pegwf-fail.XXXXXX")"
cp "${REPO}/examples/workflow.py" "$FAILWF/workflow.py"
python3 - "$FAILWF/workflow.py" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('greet = spawn_transformation("greet", cpu=2, memory_gib=4)',
            'greet = spawn_transformation("greet", cpu=2, memory_gib=4)\n    greet.add_profiles(Namespace.ENV, key="FAKE_SPAWN_FAIL", value="greet")')
open(p,"w").write(s)
PY
( cd "$FAILWF" && python3 workflow.py >/dev/null \
    && pegasus-plan --sites local --output-sites local --dir "$FAILWF/submit" --submit workflow.yml >/dev/null 2>&1 )
RUNDIR2=$(find "$FAILWF/submit" -name '*.dag' -printf '%h\n' 2>/dev/null | head -1)
[ -n "$RUNDIR2" ] || fail "TEST 2: plan/submit produced no run dir"
DO2=$(wait_for_dag "$RUNDIR2") || fail "TEST 2: DAGMan did not finish in time"
grep -q "failed with status 42" "$DO2" || fail "TEST 2: DAGMan did not see the wrapper's exit 42:\n$(tail -20 "$DO2")"
grep -qiE "DAG status: [^0]|Aborting DAG|EXITING WITH STATUS [^0]" "$DO2" || fail "TEST 2: DAG did not fail despite node failure:\n$(tail -20 "$DO2")"
# downstream farewell must NOT have run
if find "$RUNDIR2" -name '*.out*' -exec grep -hq 'task_id=farewell' {} \; 2>/dev/null; then
    fail "TEST 2: downstream 'farewell' ran even though 'greet' failed"
fi
echo "TEST 2 PASS: node failed with status 42, DAG aborted, downstream skipped"

echo "=== COMPOSITION VERIFIED: DAGMan tracks the wrapper's exit code (success + failure) ==="
