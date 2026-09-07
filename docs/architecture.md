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

The official standalone installation remains under `~/.codex/packages/standalone`. `codex-direct` is a small managed wrapper that prepares secure temporary storage and then executes the unmodified current release.

This does mean the remote command named `codex` becomes the dispatcher for the account. Non-`app-server` commands are transparent pass-throughs to `codex-direct`; uninstall removes only the managed dispatcher link.

The integration is not a proxy for the app-server protocol after launch. Once the dispatcher replaces itself with `srun` and the upstream Codex executable, Codex Desktop communicates with the ordinary Codex app-server over the SSH streams it opened. `apo logs` separately uses SSH to tail Codex's own persistent `~/.codex/app-server-control/app-server.log`; it does not read the disposable `~/.codex/tmp` tree or intercept live requests.

## Allocation attachment

`codex-slurm-job` submits a batch allocation whose payload is `sleep infinity`. It records the job ID and profile in a private state directory. The dispatcher validates that the job is running and owned by the current user, then starts Codex with:

```bash
srun --jobid=JOB_ID --overlap --unbuffered --ntasks=1 ...
```

`--overlap` lets the app-server, proxy, and execution helpers share the same requested allocation. They do not receive resources outside that job.

### Linux sandbox compatibility

Apocrita exposes its `/data` filesystem through autofs. Compute-node mount metadata can include inactive offset mounts for unrelated paths. Codex's Bubblewrap backend recursively reapplies mount flags and can fail when one of those inactive mountpoints has no directory in the new namespace, even when the selected task uses only the user's home directory.

The integration deliberately does not work around this by activating unrelated automounts, disabling sandboxing, enabling legacy Landlock, or replacing Bubblewrap with an unreviewed binary. Current Codex Desktop permission profiles require Bubblewrap's direct runtime enforcement and reject the legacy Landlock backend. On affected nodes this is a release blocker that requires an upstream Bubblewrap/Codex fix or an Apocrita mount-configuration change.

## Temporary storage

The integration manages two different kinds of temporary storage.

Every Codex Slurm step receives the same private `TMPDIR`:

```text
~/.local/state/codex-apocrita/tmp/job-JOB_ID
```

It is mode `0700`, removed when the job stops, and cleaned after an allocation expires.

Codex also creates internal sandbox aliases beneath `~/.codex/tmp`. That path cannot remain on GPFS: concurrent app-server and proxy processes rely on local file locks while cleaning those aliases, and shared-filesystem locking can let one process remove another process's live helper. The integration therefore manages `~/.codex/tmp` as a symlink to:

```text
/tmp/codex-apocrita-UID/codex-tmp
```

The target is a real, user-owned, mode-`0700` directory prepared before every Codex invocation. Because `/tmp` is local, login and compute processes cannot delete one another's helpers. Only disposable Codex temporary state moves there; authentication, configuration, databases, tasks, and the rest of `~/.codex` remain persistent on GPFS. Uninstall removes the managed symlink and restores an ordinary private `~/.codex/tmp` directory.

## Remote shell wrapper

Codex starts its remote server through the remote login shell. Bash may emit job-control warnings when asked for an interactive shell without a TTY, corrupting the app-server protocol. The installed wrapper removes only the `-i` flag for noninteractive SSH-launched Codex processes and delegates everything else to `/bin/bash`.

The remote Bash startup block is account-wide because the server cannot identify which client-side SSH alias was used. It changes `SHELL` only for noninteractive SSH sessions; it does not replace the user's interactive login shell. This is the most intrusive part of the integration and should be checked when another remote tool relies on the `SHELL` environment variable.

## Stable identity

The desktop always connects to the same SSH alias and shared Apocrita home directory. Compute-node names may change between allocations without changing Codex projects or task storage.
