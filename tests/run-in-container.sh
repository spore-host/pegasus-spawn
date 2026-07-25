#!/usr/bin/env bash
# Runs the DAGMan-composition test inside the Pegasus tutorial container.
# Started as root (to bring up condor), then runs Pegasus as the scitech user
# (HTCondor won't let root own jobs). Mode is chosen by $SPAWN_MODE:
#   stub  → tests/stub-bin/spawn on PATH (no AWS)
#   real  → the real spawn binary at /work-bin/spawn (launches spores; needs creds)
set -e

# Bring up a personal HTCondor.
condor_master
for i in $(seq 1 30); do condor_q >/dev/null 2>&1 && break; sleep 1; done

# Copy the repo to a scitech-owned workspace.
cp -r /work /home/scitech/pegasus-spawn
chown -R scitech:scitech-group /home/scitech/pegasus-spawn
pip3 install --quiet pegasus-wms.api 2>/dev/null || true

# Build the per-user run script.
cat > /home/scitech/go.sh <<'INNER'
set -e
export HOME=/home/scitech
cd /home/scitech/pegasus-spawn/examples

if [ "${SPAWN_MODE}" = "real" ]; then
    export PATH=/work-bin:/home/scitech/pegasus-spawn/bin:$PATH
else
    export PATH=/home/scitech/pegasus-spawn/tests/stub-bin:/home/scitech/pegasus-spawn/bin:$PATH
fi
echo "spawn = $(command -v spawn)"

python3 workflow.py >/dev/null
echo "--- plan + submit ---"
pegasus-plan --sites local --output-sites local --dir ./submit --submit workflow.yml 2>&1 | tail -8

RUNDIR=$(find ./submit -name '*.dag' -printf '%h\n' | head -1)
echo "RUNDIR=$RUNDIR"

for i in $(seq 1 90); do
    S=$(pegasus-status "$RUNDIR" 2>/dev/null | grep -iE 'Success|Failure' | tail -1)
    if [ -n "$S" ]; then echo "STATUS: $S"; break; fi
    sleep 5
done

echo "=== ANALYZER ==="
pegasus-analyzer "$RUNDIR" 2>&1 | tail -25 || true

echo "=== wrapper/stub invocations captured in job stdout ==="
grep -rh 'spawn task run\|fake-spawn\|launching spore' "$RUNDIR" 2>/dev/null | head -20 || true
INNER
chown scitech:scitech-group /home/scitech/go.sh

su scitech -c "SPAWN_MODE='${SPAWN_MODE:-stub}' SPAWN_WORKDIR_S3='${SPAWN_WORKDIR_S3:-s3://fake/peg}' SPAWN_REGION='${SPAWN_REGION:-us-east-1}' bash /home/scitech/go.sh"
