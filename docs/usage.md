# Commands and profiles

The examples use the default command name `apo`. Help automatically uses a customized name.

## Jobs

```bash
apo                     # start or reuse cpu
apo start NAME          # start or reuse a named profile
apo switch NAME         # confirm, stop, and replace the current job
apo status
apo stop                # allocation only
apo off                 # allocation and SSH master
```

Only one Codex allocation is recorded per remote account. `switch` is explicit because it cancels the current job.

## Profiles

```bash
apo config
apo config show cpu
apo config create longday cpu
apo config set longday CPUS_PER_TASK=4 MEM=16G TIME=8:00:00
apo config delete longday
```

Supported keys:

```text
JOB_NAME PARTITION ACCOUNT CONSTRAINT GRES
NODES NTASKS CPUS_PER_TASK CPUS_PER_GPU
MEM MEM_PER_CPU TIME
```

GPU profiles are intentionally not created automatically because partitions, accounts, constraints, and entitlements vary. Create one only after confirming your access with Apocrita documentation or support.

## Connection

```bash
apo ssh status
apo ssh start
apo ssh force
apo ssh off
```

## Diagnostics

```bash
apo doctor
apo doctor --runtime
apo logs 200
apo clean
```

`--runtime` requires a running allocation and prints the compute hostname, Slurm job ID, cgroup, CPU allowance, and temporary directory.

`apo clean` removes state for expired jobs, their shared temporary directories, and failed installer staging directories older than one day. Successful installations remove their staging data immediately.

## Updates and rollback

```bash
apo update
apo rollback
```

Updates are manual. Installations made from a Git checkout retain its path; `apo update` fast-forwards that checkout and reruns the idempotent installer. Both local and remote integrations retain a `previous` symlink for rollback.
