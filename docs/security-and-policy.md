# Security and Apocrita policy

## Guarantees

The installers and runtime:

- never use `sudo`;
- never store or automate an Apocrita password;
- never copy Codex credentials automatically;
- never expose the Codex app-server on a public TCP listener;
- never SSH directly to an allocated compute node;
- validate ownership before attaching to or cancelling a Slurm job;
- use private configuration and state directories;
- verify uploaded Codex packages with SHA-256;
- preserve backups before editing SSH or shell configuration.

The project keeps persistent Codex data in `~/.codex` on GPFS. It relocates only the disposable `~/.codex/tmp` subtree to a node-local `/tmp/codex-apocrita-UID` directory. The runtime rejects non-directory or incorrectly owned targets and enforces mode `0700` before launching Codex.

The generated SSH master exists only to reuse authentication already completed by the user. Anyone able to access its local control socket can use that authenticated connection, so protect your local account and `~/.ssh` directory.

## Resource model

The login or VS Code endpoint submits the allocation and launches `srun`. The complete remote Codex session runs in that allocation on its assigned compute node: the app-server, root agent, subagents, terminal commands, repository inspection, builds, and tests all share the requested CPU and memory. Slurm's job cgroup enforces those limits; processes launched through the integration do not gain access to compute resources allocated to another user's job.

QMUL documents that compute-node SSH access is permitted only alongside a running job and adopted into that job's resources. This project takes a more conservative route: it does not SSH to compute nodes at all. See [QMUL GPU/SSH guidance](https://docs.hpc.qmul.ac.uk/using/usingGPU/) and the [Slurm overview](https://docs.hpc.qmul.ac.uk/using/submittingjobs/). This design is intended to comply with scheduler resource isolation. Users remain responsible for the current rules.

The default interactive profile is deliberately small. Its purpose is to give Codex enough capacity to inspect a repository, spawn a few subagents, edit files, and run modest development commands. Request only the resources and wall time needed for that interactive work.

Substantial computation should use the scheduler normally. Parallel CPU analysis, simulations, training, and GPU workloads should be submitted with `sbatch`, `srun`, or the user's established workflow as separate appropriately sized jobs. Codex may prepare, submit, and monitor those jobs, but heavy work should not be squeezed into the interactive Codex allocation merely by enlarging it indefinitely.

## Trust and scope

Inspect `install.sh` before running it. Use `--dry-run` to preview values and the generated SSH fragment.
