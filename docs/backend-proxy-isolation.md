# Isolate short-lived Codex clients from the listener home

## Experimental comparison after the node-local temporary-directory fix

This branch keeps the previous transient-client isolation changes available for
comparison against upstream commit `29448229bcf1cca4aaf2f0fc61e713ad9f57bfba`.
It is separate from the Windows adapter contribution: the Windows support PR
does not include or install these backend changes and uses the updated upstream
runtime. No result in this document establishes that this additional isolation
is still needed after the upstream temporary-directory fix. Test the upstream
runtime first, with the local synthetic and live integration results reported
separately.

Upstream now prepares `$HOME/.codex/tmp` as a link to node-local temporary
storage before each managed Codex invocation. This comparison changes
`CODEX_HOME` for version queries and proxies, while leaving `HOME` unchanged.
The upstream helper uses `HOME`, not `CODEX_HOME`: it therefore still prepares
the original `$HOME/.codex/tmp`, but does not relocate the isolated clients'
`CODEX_HOME/tmp` directories. Those client directories remain beneath the shared
state directory described below. This branch compares a different isolation
approach; it does not provide node-local temporary storage for every transient
client.

**Proxy homes are retained after exit and are not automatically cleaned.**
Neither this comparison branch nor its tests resolve that lifecycle limitation.
Any manual cleanup must first establish that the associated allocation and
client processes are inactive, then review only the owned managed paths. Do not
remove homes on age alone, after an ambiguous scheduler query, or while any
associated process may still hold a helper. The Windows adapter requires no
such proxy-home cleanup because it does not install this workaround.

The historical implementation rationale and validation below describe the
isolation patch itself. They are not a live acceptance result for the rebased
comparison or a recommendation to deploy it.

Local validation after rebasing, on 2026-09-07, passed the isolation suite:
32 tests ran, with 29 passing and three foreign-owner cases explicitly skipped
under an ordinary WSL user. The dispatcher, fake-Slurm, and upstream
temporary-directory shell fixtures also passed. The isolation suite replaces
`codex-direct` with a mock; the temporary-directory fixture exercises the new
upstream wrapper separately. These results do not test their combined behavior
with a real Codex executable or establish live HPC acceptance. No installed
Codex, SSH connection, or real scheduler was used by those fixtures.

## Implementation scope

The Slurm listener remains the owner of the real Codex configuration,
authentication, sessions and Goals. A version query and a byte proxy do not
need to initialize temporary helpers inside that same home. This change gives
those two clients separate homes while retaining the existing allocation,
listener connection and upstream executable.

This backend change is independent of the optional Windows/WSL adapter. It has
no Windows package paths, account names, fixed allocation IDs or resource sizes.
It does not install a service, submit an allocation, restart a listener or
change a permission profile.

## Why isolate initialization?

Codex 0.153.4 initializes per-process helper aliases in `CODEX_HOME/tmp/arg0`
before entering ordinary CLI command handling. Startup also attempts cleanup of
other alias directories using their file locks. A client that only prints a
version or relays bytes should not participate in the listener's helper cleanup.
Separate homes remove that interaction; this is not proof that a particular
filesystem has broken locking or that any specific client deleted a helper.
See the pinned official [arg0 implementation](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/arg0/src/lib.rs).

The official proxy accepts `--sock`; without it, the socket location is derived
from the client home. The wrapper resolves the listener's original default
socket first, then changes only the proxy's `CODEX_HOME` and supplies that socket
explicitly. The long-lived listener continues using the original home and
authentication. See the [official proxy dispatch](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/cli/src/main.rs#L1265).

These interfaces were reviewed against 0.153.4. A different Codex release or a
different listener socket layout requires a compatibility review; the checks
do not silently fall back to initializing the original home.

## Invocation behavior

| Invocation | Behavior |
|---|---|
| Exactly `codex --version` | Run the existing `codex-direct` with a dedicated private version home. Preserve arguments, output and exit status. No Slurm step. |
| `codex -V`, combined version flags, ordinary CLI commands | Retain the original dispatcher routing and `CODEX_HOME`. These forms are outside the version-isolation guarantee. |
| Exactly `codex app-server proxy` | Enter the recorded RUNNING, user-owned allocation through the existing `srun`; create a unique private proxy home and pass the original listener socket with `--sock`. |
| Listener and other app-server commands without a `proxy` argument | Keep the original arguments and Codex home; run through the normal Slurm step entry. |
| Proxy arguments with additional flags or another argument arrangement | Reject explicitly. Custom `--sock`, config overrides and even proxy `--help` are outside this narrow wrapper contract. |

A proxy uses `${CODEX_HOME:-$HOME/.codex}/app-server-control/app-server-control.sock`
as its original listener socket. An explicitly configured `CODEX_HOME` is
supported when it is an absolute, owned directory satisfying the checks.
The listener home, control directory and socket must not themselves be symlinks;
the socket must be an owned Unix socket. Socket type and ownership alone do not
prove that the expected listener is ready or that an old socket is fresh.

The step entry requires its actual numeric Slurm job/step environment to match
the recorded job. The caller retains the existing RUNNING/owner validation and
`--jobid`, `--overlap`, `--ntasks=1` behavior. No per-task CPU, memory, GPU or
walltime value is introduced by this patch. Existing profiles continue to define
allocation resources.

## Directory and lifecycle boundaries

With `state=${XDG_STATE_HOME:-$HOME/.local/state}/codex-apocrita`, client homes are:

```text
$state/version-probe-home
$state/proxy-homes/job-<recorded-id>/request.<random>
```

The version home is mode 0700 and may retain only its own nonsymlink, user-owned
`tmp` directory between queries. Unexpected entries are rejected rather than
read, copied or removed. Each proxy receives a new empty mode-0700 directory.
No real authentication, configuration, sessions or Goal state is copied into
either kind of home. The real `HOME` remains unchanged.

Private state directories must be owned by the invoking user and must not
themselves be symlinks. Shared job temporary directories are checked before
creation or mode changes. Canonical private-home paths must lie outside the
effective system temporary directory, including aliases and the `/` boundary:
Codex's own helper initialization rejects homes beneath that directory. Linux
GNU `readlink -m` is used for this check.

The entry uses `exec` to preserve process identity, separate standard streams,
signals and exit status. It has no cleanup trap that could remove a helper while
a process is using it. **Proxy homes are retained after exit.** The existing
`apo clean` only handles its original temporary/staging areas; it does not clean
`proxy-homes` or the version home. This patch does not promise automatic expiry.
An operator may separately review cleanup after confirming that the associated
processes and allocation have finished. Do not delete homes on age alone while
they may still be in use.

These checks prevent common mistakes within the user-owned integration. They
are not an OS security boundary against another process running as that same
user, and they do not prove distributed filesystem lock semantics.

## Preserve unbuffered Slurm transport

The upstream caller already uses `srun --unbuffered`; this patch retains it.
Small WebSocket frames need not end in a newline. In the reviewed Slurm 25.11.7
implementation, buffered step output holds an incomplete line, whereas the
unbuffered path sends bytes. On PTY-enabled builds, unbuffered stdout clears
`OPOST`; it is distinct from requesting a full `--pty` terminal. Normal stdin
and stderr remain separate when that full-terminal mode is not requested.
See [Slurm's pinned I/O implementation](https://github.com/SchedMD/slurm/blob/slurm-25-11-7-1/src/slurmd/slurmstepd/io.c)
and the [srun option documentation](https://slurm.schedmd.com/srun.html#OPT_unbuffered).

The wrappers introduce neither `--pty` nor SSH terminal allocation. The local
fixtures verify flag preservation and binary stream/exit propagation through
the wrappers; they do not emulate a Slurm daemon or prove every Slurm release's
transport behavior.

## Local validation

Run the focused synthetic suite on a local development machine:

```bash
python3 tests/test_backend_isolation.py
```

The suite copies the actual three backend files into disposable fixtures and
uses synthetic Codex, queue and `srun` programs. Each subprocess receives a fresh
environment and fixture HOME. It does not run an installed Codex, SSH, scheduler,
allocation payload, scientific command or `runtime-check`.

Coverage includes isolated version queries, real fixture Unix sockets, custom
listener homes, distinct proxy homes, retained fictional listener sentinels,
unsafe paths, symlinks, ownership, TMPDIR boundaries, scheduler rejection,
unchanged listener arguments, binary streams, nonzero exit and SIGTERM/PID
propagation. Bash syntax checks are included. Three foreign-owner cases require
local root and otherwise report explicit skips; they change ownership only in
the disposable fixture.

The local Linux preparation run passed **32 tests, no skips** using those
temporary ownership fixtures. A separate ordinary-user run passed 29 tests and
explicitly skipped the three ownership-changing cases. The former routing test also supplies a small
fixture-only GNU `readlink -m` emulation for macOS CI. The new Python suite uses
real GNU `readlink` on Linux and emulates that operation on other local hosts;
the installed backend remains Linux-only. Portable ShellCheck 0.11.0 also passed
on the six changed Bash files and the complete 25-file CI shell collection,
without diagnostics. That static run used a temporary LF mirror for existing
Windows CRLF files and did not execute candidate scripts. macOS execution was
not performed during this local preparation. No cluster acceptance or long-term
stability claim follows from these results.

The release packager already includes `remote/*`, so the new step entry requires
no separate deployment script. Install and roll back the caller and entry as a
matched release through the existing reviewed lifecycle. Removing only the new
entry while the caller still references it is not a complete rollback. Preserve
client directories until their lifecycle has been checked; a release rollback
does not safely imply their removal.
