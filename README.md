# pegasus-spawn (prototype)

Run each [Pegasus WMS](https://pegasus.isi.edu) 5.x job on its own **ephemeral
spore.host EC2 instance**, auto-terminated — no compute scheduler, no standing
capacity.

> **Status: feasibility prototype.** The wrapper → `spawn task run` contract and
> the Pegasus artifacts are validated offline. A gated real-AWS end-to-end run
> (Pegasus submit host + spores per job) is the remaining validation step — see
> "Live run" below.

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
- `spawn` and `truffle` on `PATH`, AWS credentials configured.
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

## Offline validation (done)

- `bin/pegasus-spawn-run` builds a valid `TaskSpec` from `PEGASUS_SPAWN_*` env +
  the Pegasus job argv, verified against `spawn task run --dry-run` (sizes a
  t3a.medium for cpu=2/mem=4, no launch).
- `examples/workflow.py` generates valid Pegasus 5.0.4 YAML (the Pegasus API
  accepts the Transformation Catalog with `pfn`=wrapper, `site=local`,
  `gridstart=NoGridStart`, per-job sizing env, and the job DAG).

## Live run (remaining)

The one thing only a live run settles (per the feasibility spike): that DAGMan
composes correctly with a real blocking `spawn task run` wrapper — node success/
failure by exit code, `RETRY` on failure, and input staging under `NoGridStart`.
Procedure: stand up a Pegasus 5.x submit host (a spore), run the example, and
observe one spore per job spinning up and self-terminating, leak-checked. This is
a gated real-AWS action.

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
