# How it works

## Request flow

```text
Codex Desktop
  │ OpenSSH sessions through a stable alias; ControlMaster multiplexes them to bypass interactive password prompts
  ▼
Apocrita login or VS Code endpoint
  │ ~/.local/bin/codex dispatches app-server only
  ▼
srun --jobid=<recorded job> --overlap
  │ Slurm applies CPU, memory, time, and cgroup limits
  ▼
Codex app-server on the allocated compute node
```

The login endpoint carries SSH control traffic and submits/attaches to Slurm. The Codex app-server, terminal processes, and subagents execute in the allocation.

## Why ControlMaster exists

Codex Desktop can invoke OpenSSH but cannot necessarily answer Apocrita's interactive password challenge. `apo` establishes one authenticated master connection in a terminal. Later Codex sessions reuse it through `ControlPath` without storing the password.

Changing networks breaks the underlying TCP connection. Run `apo` again to authenticate a new master.

## Dispatcher

The remote `~/.local/bin/codex` is deliberately not the upstream binary. It examines its arguments:

- commands containing `app-server` go through `codex-slurm`;
- ordinary CLI commands go to `codex-direct`.

The official standalone installation remains under `~/.codex/packages/standalone`. `codex-direct` points to its current release, so the integration does not modify OpenAI binaries.

This does mean the remote command named `codex` becomes the dispatcher for the account. Non-`app-server` commands are transparent pass-throughs to `codex-direct`; uninstall removes only the managed dispatcher link.

## Allocation attachment

`codex-slurm-job` submits a batch allocation whose payload is `sleep infinity`. It records the job ID and profile in a private state directory. The dispatcher validates that the job is running and owned by the current user, then starts Codex with:

```bash
srun --jobid=JOB_ID --overlap --unbuffered --ntasks=1 ...
```

`--overlap` lets the app-server, proxy, and execution helpers share the same requested allocation. They do not receive resources outside that job.

## Shared temporary directory

Apocrita can isolate `/tmp` between Slurm steps. Codex creates temporary process-launch helpers, and subagents may use a different step. If the helpers live in step-local `/tmp`, the second step fails with `No such file or directory`.

Every Codex step therefore receives the same private directory:

```text
~/.local/state/codex-apocrita/tmp/job-JOB_ID
```

It is mode `0700`, removed when the job stops, and cleaned after an allocation expires.

## Remote shell wrapper

Codex starts its remote server through the remote login shell. Bash may emit job-control warnings when asked for an interactive shell without a TTY, corrupting the app-server protocol. The installed wrapper removes only the `-i` flag for noninteractive SSH-launched Codex processes and delegates everything else to `/bin/bash`.

The remote Bash startup block is account-wide because the server cannot identify which client-side SSH alias was used. It changes `SHELL` only for noninteractive SSH sessions; it does not replace the user's interactive login shell. This is the most intrusive part of the integration and should be checked when another remote tool relies on the `SHELL` environment variable.

## Stable identity

The desktop always connects to the same SSH alias and shared Apocrita home directory. Compute-node names may change between allocations without changing Codex projects or task storage.
