# CLAUDE.md — pegasus-spawn

`pegasus-spawn` lets an existing [Pegasus WMS](https://pegasus.isi.edu) 5.x
workflow run chosen steps on ephemeral spore.host EC2 instances (one per job,
auto-terminated) — by making the job's executable a wrapper that calls
`spawn task run`, using only documented Pegasus seams (Transformation Catalog +
`site=local` + `gridstart=NoGridStart`). No custom scheduler/LRMS. Part of the
spore.host suite.

**Audience:** someone who ALREADY runs Pegasus + HTCondor and wants to point
specific transformations at spore.host. spore.host does not install or own
Pegasus/HTCondor — the user's existing submit host runs the DAG; only the chosen
steps burst to spores.

## Versioning & changelog (required)

Follows **[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)** and
keeps a **[Keep a Changelog](https://keepachangelog.com/en/1.1.0/)**-format
`CHANGELOG.md`. Update `## [Unreleased]` in the SAME PR as any user-facing change
(Added/Changed/Deprecated/Removed/Fixed/Security; Documentation for docs-only).
On release: promote Unreleased → `## [X.Y.Z] - YYYY-MM-DD`, open a fresh
Unreleased, update compare links, tag `vX.Y.Z`. Pre-1.0: breaking → MINOR.

## Layout

- `bin/pegasus-spawn-run` — the per-job wrapper (Pegasus job → TaskSpec → `spawn task run --wait`).
- `examples/workflow.py` — generates a Pegasus 5.x workflow with spawn-backed transformations.
- `tests/Dockerfile` + `tests/composition-test.sh` + `tests/stub-bin/spawn` — the
  DAGMan-composition CI test (real Pegasus + minicondor, stubbed `spawn`, no AWS).

## Test & validate

- Offline: `bin/pegasus-spawn-run <name>` with `PEGASUS_SPAWN_*` env builds a
  TaskSpec; validate with `spawn task run --dry-run`.
- Composition (CI): the DAGMan-composition test runs in GitHub Actions
  (`.github/workflows/composition-test.yml`) — build the Pegasus+minicondor image,
  run the example under real `pegasus-plan --submit`, assert node exit-code
  tracking + RETRY. Needs a privileged container (HTCondor schedd); runs in CI, not
  reliably on a dev macOS box.
- Real-AWS end-to-end (a user with Pegasus, or a gated dev run): point a real
  Pegasus workflow's transformation at the wrapper and watch a spore per job.

## Status

Feasibility prototype (see README). Wrapper↔spawn contract + Pegasus YAML
generation validated offline; DAGMan composition validated in CI; full real-spore
end-to-end is the remaining step.
