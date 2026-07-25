# pegasus-spawn (prototype)

Run each [Pegasus WMS](https://pegasus.isi.edu) 5.x job on its own **ephemeral
spore.host EC2 instance**, auto-terminated — no compute scheduler, no standing
capacity.

> **Status: feasibility prototype — verified end-to-end.** Validated on real
> Pegasus 5.1.2 + HTCondor (DAGMan), including a real-AWS run where each job
> launched its own spore, ran, and the DAG succeeded (instances leak-checked +
> terminated). See "Verified" below.

## Why this shape (and why it's different from the other adapters)

The other spore.host adapters (nf-spawn, miniwdl-spawn, cwl-spawn, snakemake,
spawn-airflow) hook each engine's **native per-task executor**. Pegasus has no
such hook: `pegasus-plan` compiles an abstract workflow into an **HTCondor DAG**
and delegates execution to **DAGMan** — there is no pluggable executor/LRMS
plugin API.

So instead of integrating a custom scheduler, we make each **job's executable be
a wrapper** (`bin/pegasus-spawn-run`), using only documented Pegasus seams:

| Seam | What it does |
|------|--------------|
| **Transformation Catalog** (`type: installed`, `pfn` = the wrapper) | the job's executable is our wrapper |
| **`site: local`** (reserved submit-host site) | DAGMan runs the wrapper on the submit host (local universe), next to DAGMan — not on a compute node |
| **`profile pegasus gridstart NoGridStart`** | disables kickstart wrapping so the wrapper's own exit code governs the node |
| **`spawn task run --wait`** | the wrapper launches one purpose-sized spore, stages I/O via S3, runs the step, and the instance self-terminates; the wrapper blocks and returns the exit code |
| **DAGMan exit-code tracking + `RETRY`** | node success/failure = the wrapper's exit code; retries and monitoring work with no kickstart record |

**First-party precedent:** Pegasus already ships the HubZero `Distribute`
gridstart — a submit-host wrapper that redirects a job to a PBS cluster (`qsub` +
status poll). This adapter is the same pattern, targeting a spore instead of PBS.

## Architecture

```
   submit host (can itself be a spore)
   ┌─────────────────────────────────────────────┐
   │ Pegasus 5.x + local HTCondor schedd          │
   │                                              │
   │  DAGMan ──runs──▶ pegasus-spawn-run (job 1)  │──spawn task run──▶ spore ⇢ (runs step, terminates)
   │    │                                         │
   │    └──on success──▶ pegasus-spawn-run (job 2)│──spawn task run──▶ spore ⇢ (runs step, terminates)
   └─────────────────────────────────────────────┘
```

Every *step* is a true ephemeral spore. DAGMan only orchestrates the DAG on the
submit host — it never runs the heavy work.

## Requirements

- A **submit host** with Pegasus 5.x + a local HTCondor schedd. (Heaviest part —
  this is inherent to Pegasus; the host can be a spore.)
- `spawn` (and truffle, which spawn embeds) on `PATH`.
- **AWS credentials reachable by the job via the ambient chain** — an instance
  profile on the submit host, or `~/.aws/credentials`/`config`. **NOT** shell
  environment variables: HTCondor passes only the curated per-transformation env
  profiles to a job, so submit-shell `AWS_*` env vars do **not** reach the wrapper
  (verified — see below). Give the submit host an instance profile (or `~/.aws`)
  that can `ec2:RunInstances` etc.
- `SPAWN_WORKDIR_S3` = an `s3://bucket/prefix` you own (the work/exit-code bridge).

## Try it

```sh
pip install pegasus-wms.api
export SPAWN_WORKDIR_S3=s3://your-bucket/pegasus-spawn
python3 examples/workflow.py     # → workflow.yml, transformations.yml, sites.yml, pegasus.properties
pegasus-plan --sites local --output-sites local --dir submit --submit workflow.yml
```

Each job launches one spore, runs its step, and self-terminates; `pegasus-status`
tracks the DAG.

## Verified

Tested against **real Pegasus 5.1.2 + HTCondor 25.6.1** (the official
`pegasus/tutorial` container):

1. **DAGMan composition — success path:** both jobs' wrappers run in dependency
   order, exit 0 → node success → DAG `Success:1`, 100% done.
2. **DAGMan composition — failure path:** a wrapper exiting nonzero →
   `Node failed with status 42`, **`RETRY` fires**, DAG aborts, downstream job
   skipped → `Failure:1`. So DAGMan tracks node success/failure by the wrapper's
   exit code.
3. **Real-AWS end-to-end:** with real credentials, the two-job DAG launched **one
   real spore per job** (t3a.medium), each ran its step and reported exit 0, and
   the DAG succeeded (~$0.02 total).
4. **Self-termination verified (the ephemeral guarantee):** a single spore launched
   via `spawn task run` and watched **untouched** self-terminated **~2.5 min after
   task completion** — well before its 10-minute TTL backstop. So termination is
   driven by the completion **sentinel** (`/tmp/SPAWN_COMPLETE` → spored →
   `on_complete=terminate`), not by the TTL; the TTL is only the backstop. The
   ~2.5 min is the known spored monitor-loop latency (spawn#270), not a leak.
5. **Offline:** the wrapper's `TaskSpec` passes `spawn task run --dry-run`; the
   Pegasus API accepts the generated catalog/workflow.

The DAGMan-composition CI test (`.github/workflows/composition-test.yml`) runs
1+2 on every push with a stubbed `spawn` (no AWS), as a permanent regression guard.

## Known open questions (from the feasibility spike)

- **Input staging under `NoGridStart`** (Pegasus GitHub #1474 was a since-fixed
  bug dropping `transfer_input_files`). This prototype leaves data movement to the
  wrapper/spore via S3 (`PEGASUS_SPAWN_INPUTS`/`_OUTPUTS`), sidestepping it. If you
  want Pegasus to stage, prefer the coexistence path (`gridstart.launcher`
  prepending the wrapper *around* kickstart) over `NoGridStart`.
- **Concurrency** of many blocking wrappers in local universe on the submit host —
  bound via Pegasus's local-site job throttling / pinned vanilla universe.
- **Provenance:** `NoGridStart` forgoes kickstart invocation records. Use the
  coexistence path if you need them.
