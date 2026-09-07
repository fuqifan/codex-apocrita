# Local Windows adapter tests

Run the following commands from `windows/wsl-ssh-adapter` on Windows
x64. These compile the adapter's own source and execute local fixtures. No HPC
connection, desktop activation, profile installation, or live configuration
changes are needed.

```powershell
pwsh -NoProfile -File .\tests\Run-CoreTests.ps1
pwsh -NoProfile -File .\tests\Test-DesktopProfileGuard.ps1
powershell.exe -NoProfile -File .\tests\Test-DesktopProfileGuard.ps1
pwsh -NoProfile -File .\tests\Test-DesktopProfileLifecycle.ps1
```

The Windows workflow runs the same fixtures. If local execution policy prevents
a script from running, report that coverage as unavailable; do not change the
machine's execution policy just to obtain a passing test report.

## Parser and transport

Parser tests exercise configured target selection, unrelated-host fallback,
conflicting identity/port values, option arities, path validation, and enforced
noninteractive ControlMaster policies. Use fictional settings, including distinct
WSL and remote users. Transport tests cover raw bytes, simultaneous stdin/stdout/
stderr, command-line quoting, exit codes, and child-process cleanup.

Build fixtures from source. Generated executables and private adapter settings
must remain untracked.

## PowerShell and package activation

Profile tests use temporary profile paths and synthetic leases. Ordinary shells,
expired leases, mismatched process identity, untrusted files, and changed
configuration must not receive the adapter PATH. Pure activation tests inspect
arguments or use mocks; they must not activate the real Store app. Run guard tests
under Windows PowerShell 5.1 and PowerShell 7 where applicable.

## Backend mocks

The shell suite uses temporary home directories and mock executables. Proxy
isolation tests cover independent transient homes, the original listener socket,
retained proxy state, and invalid paths. See [backend isolation](backend-proxy-isolation.md)
for the manual cleanup requirement after processes and their allocation have ended.

When using WSL with a Windows checkout, preserve LF endings and executable bits.
Use an isolated local Linux copy if needed; never target the live remote install.

## Manual integration

Local tests do not establish Store activation, actual desktop SSH discovery, or
scheduler ownership and placement. Collect the separate observations in the
[Windows guide](windows-wsl.md#verify-without-compute-probes). Do not run compute
probes where policy prohibits them.

Before sharing failures, remove accounts, project paths, task contents, credentials,
and protocol payloads. Share a failing synthetic test name, sanitized error, and
relevant software versions.
