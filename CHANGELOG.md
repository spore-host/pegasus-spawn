# Changelog

All notable changes to **pegasus-spawn** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-04

### Added

- **`SPAWN_COST_LIMIT`: a per-job spend cap** (#5). TTL was the only ceiling on a job,
  defaulting to 4h, so a workflow of N jobs had a worst case of N × 4h × the instance
  rate with no second belt. `spored` enforces TTL and cost **independently** — first
  limit to fire wins — so this is a genuine second limit.
  The failure it catches is a job that **hangs** rather than fails: it produces no exit
  status for Pegasus to retry or fail on, so it bills until the TTL expires. Pegasus's
  local-site throttling bounds *concurrency*, not spend, so it is not a substitute.
  Emitted only when set and positive. A non-numeric value degrades to "bounded by TTL
  only" with a warning rather than failing the job — it arrives as an environment string
  and a typo shouldn't kill an otherwise-fine workflow. (`--cost-limit` became a compute
  **+ storage** total in spawn 0.116.0.)

- `tests/lifecycle-test.sh`, an offline unit check for the lifecycle block. It runs in
  the fast CI job alongside the action-pin check, for the same reason: it needs neither
  Pegasus nor AWS, so a regression in the cost cap is reported in seconds instead of
  after an image build and a privileged HTCondor container.

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

### Fixed

- **A pin's version comment can no longer silently misstate what CI runs**
  ([#1](https://github.com/spore-host/pegasus-spawn/issues/1)). The hygiene check
  required only that *some* `# vN` comment be present, never that it was true — so
  a bare `# v7` passed while the SHA it labelled was a different v7.x, and a wrong
  label is worse than none: it makes a major-version jump read as a routine
  same-line bump. That is not hypothetical; Dependabot bumped nf-spawn's
  `checkout` pin to a **v7.0.1** SHA while leaving all five comments reading
  `# v6`, and the same check passed it. Two complementary halves now:
  `tests/ci-hygiene.sh` requires an exact `vX.Y.Z` (offline, hermetic), and a new
  `scripts/verify-pins.sh` resolves each SHA against the tag its comment claims
  and fails if they disagree (needs the network, so it stays out of the offline
  check). Neither alone is sufficient — a bare label defeats the second, an exact
  but false one defeats the first. Both comments here were `# v7` on a v7.0.1 SHA
  and now read `# v7.0.1`.

### Security

- **Pinned the one action ref to a commit SHA and added Dependabot to bump it**
  ([#1](https://github.com/spore-host/pegasus-spawn/issues/1)). `actions/checkout@v4`
  was a floating tag, and a tag is mutable — `@v4` means "whatever `v4` points at
  when the job runs." `actions/checkout@v6` genuinely moved (`df4cb1c` →
  `d23441a`) with no signal to consumers.
  - Lowest-risk repo in the suite — no release workflow, no publish authority, and
    the composition test uses a **stubbed `spawn`** with no AWS credentials and no
    real instances — so this is about not quietly diverging from the suite baseline
    rather than about protecting a secret. It also converges on the same
    `checkout` pin the sibling adapters use.
  - `.github/dependabot.yml` covers `github-actions` weekly with a 7-day cooldown.
    Pinning and Dependabot are one control, not two: a SHA never moves on its own,
    including past a security fix. There is no `pip` entry because this repo has no
    `pyproject.toml`; the file says so, so the omission reads as a decision.
  - `tests/ci-hygiene.sh` makes both halves regressions rather than conventions,
    and runs as its **own** fast CI job — a broken pin is reported in seconds
    instead of behind a Pegasus image build and a privileged HTCondor container.
    It's shell, not pytest, because this repo has no Python package; it follows
    `composition-test.sh`'s `fail()` idiom and asserts it found >0 refs so a
    parser that stops matching fails instead of passing vacuously.
  No behaviour change — CI wiring and tests only.

[Unreleased]: https://github.com/spore-host/pegasus-spawn/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/spore-host/pegasus-spawn/releases/tag/v0.1.0
