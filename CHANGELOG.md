# Changelog

All notable changes to **pegasus-spawn** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial feasibility prototype. `bin/pegasus-spawn-run` — a per-job wrapper that
  translates a Pegasus job invocation into a spawn `TaskSpec` and calls
  `spawn task run --wait`, so a chosen Pegasus 5.x transformation runs on an
  ephemeral spore.host instance (one per job, auto-terminated) using only
  documented Pegasus seams (Transformation Catalog `pfn`=wrapper, `site=local`,
  `gridstart=NoGridStart`) — no custom scheduler/LRMS.
- `examples/workflow.py` — generates a two-job Pegasus 5.x workflow with
  spawn-backed transformations (drop-in pattern: add these transformations to an
  existing Pegasus workflow).
- DAGMan-composition CI test (`tests/`): a real Pegasus 5.x + single-machine
  HTCondor (minicondor) container runs the example under `pegasus-plan --submit`
  with a stubbed `spawn` (no AWS), asserting DAGMan tracks node success/failure by
  the wrapper's exit code (and RETRY on nonzero).
