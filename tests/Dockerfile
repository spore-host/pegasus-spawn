# Headless Pegasus 5.x + single-machine HTCondor (minicondor) for the
# DAGMan-composition test. Not shipped — a CI test rig only.
#
# Proves the one thing that needs a real Pegasus: that DAGMan runs the
# pegasus-spawn-run wrapper as a node in dependency order and tracks node
# success/failure by the wrapper's exit code (with RETRY). A stub `spawn` stands
# in for `spawn task run`, so NO AWS is involved.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tools + Python (Pegasus API + the wrapper).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg python3 python3-pip sudo procps \
    && rm -rf /var/lib/apt/lists/*

# HTCondor as a single-machine "minicondor" (official one-line installer). This
# gives condor_master + condor_schedd so condor_submit_dag / DAGMan can run a DAG
# locally with no separate compute backend.
RUN curl -fsSL https://get.htcondor.org | /bin/bash -s -- --no-dry-run --minicondor

# Pegasus 5.x from the official apt repository.
RUN curl -fsSL https://download.pegasus.isi.edu/pegasus/gpg.txt | gpg --dearmor -o /usr/share/keyrings/pegasus.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/pegasus.gpg] https://download.pegasus.isi.edu/pegasus/ubuntu jammy main" \
        > /etc/apt/sources.list.d/pegasus.list \
    && apt-get update && apt-get install -y --no-install-recommends pegasus \
    && rm -rf /var/lib/apt/lists/*

# A non-root user (HTCondor/DAGMan dislike running as root; Pegasus tutorial uses
# a 'scitech' user by convention).
RUN useradd -m -s /bin/bash scitech && echo "scitech ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER scitech
WORKDIR /home/scitech

# The adapter + test harness are mounted/copied in at run time by the CI job.
CMD ["/bin/bash"]
