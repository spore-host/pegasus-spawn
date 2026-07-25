#!/usr/bin/env python3
"""Example pegasus-spawn workflow — two jobs, each on its own ephemeral spore.

Generates a small Pegasus 5.x abstract workflow whose jobs run their real work on
spore.host EC2 instances (one per job, auto-terminated), using ONLY documented
Pegasus seams — no custom scheduler/LRMS/BOSCO:

  - Each transformation's physical executable is `pegasus-spawn-run` (the wrapper),
    registered INSTALLED on the reserved `local` site so DAGMan runs it on the
    submit host (local universe), next to DAGMan.
  - `profile pegasus gridstart NoGridStart` disables kickstart wrapping so the
    wrapper's own exit code governs the node (pair with pegasus.transfer of the
    real data left to the wrapper/spore via S3).
  - The wrapper reads PEGASUS_SPAWN_* env (set here as per-transformation profiles)
    to size the spore and stage inputs/outputs, then calls `spawn task run --wait`.

Run:
  python3 workflow.py        # writes workflow.yml + tc.yml + sites.yml
  pegasus-plan --conf pegasus.properties \
      --sites local --output-sites local \
      --dir submit workflow.yml
  # (submit host needs Pegasus 5.x + a local HTCondor schedd; the submit host
  #  itself can be a spore.)

Requires: pegasus-wms.api  (pip install pegasus-wms.api), spawn + truffle on PATH,
SPAWN_WORKDIR_S3 exported to an s3://bucket/prefix you own.
"""

import os
from pathlib import Path

from Pegasus.api import (
    Arch,
    Job,
    Namespace,
    Properties,
    Site,
    SiteCatalog,
    Transformation,
    TransformationCatalog,
    Workflow,
)

HERE = Path(__file__).resolve().parent
WRAPPER = str(HERE.parent / "bin" / "pegasus-spawn-run")
WORKDIR_S3 = os.environ.get("SPAWN_WORKDIR_S3", "s3://REPLACE-ME/pegasus-spawn")
REGION = os.environ.get("SPAWN_REGION", "us-east-1")


def spawn_transformation(name, cpu, memory_gib, container=None):
    """A Transformation whose executable is the wrapper, running on `local`.

    The PEGASUS_SPAWN_* env profiles are the per-job sizing/staging knobs the
    wrapper reads to build the TaskSpec. gridstart=NoGridStart makes DAGMan track
    the wrapper's exit code directly (no kickstart record needed).
    """
    t = Transformation(
        name,
        site="local",
        pfn=WRAPPER,
        is_stageable=False,  # INSTALLED — pfn is a local filesystem path
        arch=Arch.X86_64,
    )
    t.add_profiles(Namespace.PEGASUS, key="gridstart", value="NoGridStart")
    t.add_profiles(Namespace.ENV, key="SPAWN_WORKDIR_S3", value=WORKDIR_S3)
    t.add_profiles(Namespace.ENV, key="SPAWN_REGION", value=REGION)
    t.add_profiles(Namespace.ENV, key="SPAWN_TTL", value="1h")
    t.add_profiles(Namespace.ENV, key="PEGASUS_SPAWN_CPU", value=str(cpu))
    t.add_profiles(Namespace.ENV, key="PEGASUS_SPAWN_MEMORY_GIB", value=str(memory_gib))
    t.add_profiles(Namespace.ENV, key="PEGASUS_SPAWN_ARCH", value="x86_64")
    if container:
        t.add_profiles(Namespace.ENV, key="PEGASUS_SPAWN_CONTAINER", value=container)
    return t


def main():
    # Site catalog: only the reserved local site (submit host). Everything runs
    # its wrapper here; the wrapper fans out to spores.
    sc = SiteCatalog()
    local = Site("local", arch=Arch.X86_64)
    sc.add_sites(local)

    tc = TransformationCatalog()
    greet = spawn_transformation("greet", cpu=2, memory_gib=4)
    farewell = spawn_transformation("farewell", cpu=2, memory_gib=4)
    tc.add_transformations(greet, farewell)

    wf = Workflow("pegasus-spawn-demo")
    # Two sequential jobs — job2 depends on job1 — so we can see two spores launch
    # in DAG order, each self-terminating before the next.
    j1 = Job(greet).add_args("--name", "spore")
    j2 = Job(farewell).add_args("--name", "spore")
    wf.add_jobs(j1, j2)
    wf.add_dependency(j1, children=[j2])

    props = Properties()
    # Leave data transfer to the wrapper/spore (S3), not Pegasus, under NoGridStart.
    props["pegasus.transfer.links"] = "true"
    props.write()

    sc.write()
    tc.write()
    wf.write()
    print("Wrote workflow.yml, tc.yml, sites.yml, pegasus.properties")
    print("Wrapper:", WRAPPER)
    print("Workdir:", WORKDIR_S3)


if __name__ == "__main__":
    main()
