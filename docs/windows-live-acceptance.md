# Windows acceptance record, 2026-09-07

Status: local regression checks and a fresh-build SSH check passed. The complete
Desktop clean-install, restart, and rollback acceptance is **still pending**.
This record is not a recommendation to merge before those live checks finish.

## Candidate and backend scope

The Windows branch is based on upstream
`29448229bcf1cca4aaf2f0fc61e713ad9f57bfba`, including its node-local Codex
temporary-directory handling. Runtime files, upstream shell tests, installation
scripts, and libraries have no changes relative to that base.

The Windows source tested is commit
`95ccdf1923803b20921e35a82a091945ee0ef027`. Later documentation-only commits do
not change those adapter sources. The old backend proxy/version-home isolation
changes are absent from this branch and are retained only in a separate
experimental comparison branch. Their necessity after the upstream fix has not
been demonstrated, and their proxy homes still require deliberate cleanup after
the relevant clients and allocation are confirmed inactive.

## Verified local results

Environment: Windows 10 x64 (10.0.19045), PowerShell 7.6.5, Windows PowerShell
5.1.19041.6456, .NET Framework CLR 4.0.30319.42000, and WSL 2.

| Check | Observed result |
| --- | --- |
| SSH argument parser | 227 assertions passed |
| Static adapter configuration | 14 cases passed, invoked once by the core suite |
| Windows raw-byte transport | 17 cases passed |
| Desktop profile guard, PowerShell 7 | 33 cases passed |
| Desktop profile guard, Windows PowerShell 5.1 | 33 cases passed |
| Installation/profile lifecycle fixtures | 14 named checks passed |
| Full upstream shell suite in local WSL | All 12 test files passed, exit 0 |
| Static PowerShell parsing and Git whitespace checks | Passed |

The WSL suite used a fresh source export, the existing non-root local Linux user,
disposable HOME/XDG trees, and mocked SSH, Slurm, and Codex commands. No real HPC
test was performed by that suite. Its existing mocked download warning and two
awk quoting warnings did not cause failures.

Some preliminary sandbox-context Windows runs were refused by fixture-output
permissions or the execution policy for that context. The unchanged supported
commands subsequently passed under the normal Windows account. No execution
policy, authentication rule, or ownership guard was disabled.

## Fresh source and real SSH check

A new private ASCII directory was populated from `git archive` of the tested
commit. The adapter was compiled there using the Windows .NET Framework compiler.
No production executable, installation state, or launch lease was copied.
A new local configuration referenced the existing authenticated WSL master.

The newly built adapter successfully carried a read-only scheduler query to the
authorized Apocrita login endpoint and returned `RUNNING` with exit 0. This
establishes a real adapter/WSL/OpenSSH/login round trip. It does not establish
Desktop origin, an app-server session, root/subagent execution, or a clean
installation of the new upstream runtime.

Real read-only installation preflight refused the existing PowerShell profile
directories because they inherit additional write permissions. The refusal
occurred before profile or installed-configuration changes. The fresh executable
and its local configuration remain available for the planned maintenance test.
Resolve those directory permissions with an exact backup and rollback plan;
do not weaken the installer guard to obtain a passing result.

## Live checks still required

| Required acceptance step | Current status |
| --- | --- |
| Build adapter from clean committed source | Passed |
| Install into the actual Desktop profile environment | Pending; directory preflight refused |
| Launch Desktop through the new adapter | Pending |
| Connect Desktop to the rebased upstream runtime | Pending |
| Normal root command and file work | Pending on that exact runtime |
| Normal subagent command and file work | Pending on that exact runtime |
| Two concurrent Desktop tasks | Pending on that exact runtime |
| Fully restart Desktop and resume the same tasks | Pending |
| Roll back actual profile integration and restore the previous route | Pending; fixtures alone passed |

Existing production tasks were left running. The new upstream wrapper prepares
`HOME/.codex/tmp`, so changing only `CODEX_HOME` is insufficient for a separate
test backend. An isolated HOME/runtime staging plan was prepared but not deployed.
The attempted non-secret SSH environment marker was not delivered through the
current authenticated connection; no server configuration or authentication was
changed to force it through. A Desktop-wide CLI override would also affect the
local backend and other SSH connections, so it was not installed as a workaround.

The remaining procedure is described in [the Windows guide](windows-wsl.md#clean-install-restart-and-rollback-acceptance).
Actual Desktop lifecycle observations and new-runtime results will be added only
after they have been obtained. Host identities, account names, research paths,
job/task identifiers, raw application logs, and credentials are excluded from
this public record.
