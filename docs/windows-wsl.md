# Experimental Windows desktop with WSL SSH

This optional adapter lets the Windows desktop app reuse a connection authenticated
with Linux OpenSSH inside WSL. It targets authorized login endpoints that require
interactive authentication and support ControlMaster. It does not add Linux control
socket support to native Win32 OpenSSH.

Build the source in [`windows/wsl-ssh-adapter`](../windows/wsl-ssh-adapter) locally.
No prebuilt executable or personal configuration is distributed. The integration
supports a specific Windows Store package identity and resolves its registered
version at launch instead of hardcoding a versioned WindowsApps directory.

## Connection flow

```text
Windows desktop SSH request
  -> dedicated ssh.exe adapter
  -> wsl.exe (explicit distribution and Linux user)
  -> Linux OpenSSH (existing authenticated control socket only)
  -> authorized login endpoint and codex-apocrita dispatcher
  -> Slurm job step in the user's controller allocation
```

Other recognized SSH destinations use native Windows OpenSSH. Unknown argument
syntax is refused instead of guessed. Target requests cannot enable a TTY,
forwarding, a new authentication flow, or a caller-supplied proxy command.
Stdin, stdout, and stderr use separate raw byte streams; do not insert PowerShell's
text pipeline into this protocol.

## Prerequisites

- Windows x64, Windows PowerShell 5.1, and PowerShell 7.
- The .NET Framework 4.x C# compiler normally supplied with Windows.
- Desktop Store package family `OpenAI.Codex_2p2nqsd0c76g0`. A different package
  identity requires review, not disabling the package check.
- Native Windows OpenSSH for destinations outside the configured target.
- WSL with a known distribution, Linux user, home, and `/usr/bin/ssh`.
- Working codex-apocrita in WSL, a concrete alias, and an authenticated master.
- Site permission for login-side `sbatch` allocation and login-side
  `srun --jobid --overlap` backend attachment. Technical success does not establish
  policy permission; follow any administrator prohibition.

Use the [installation guide](installation.md) for WSL-side setup. An existing
working installation does not need reinstalling to prepare this adapter. Preserve
existing SSH aliases and IDE settings. The WSL identity is local to that Linux
distribution and may differ from the HPC account.

## Configure the adapter

From the adapter directory in PowerShell 7:

```powershell
Copy-Item -LiteralPath .\adapter-config.example.json -Destination .\adapter-config.json
```

Replace the fictional example values with your existing setup:

| Setting | Meaning |
| --- | --- |
| `Distribution` | Exact WSL distribution name; inspect locally with `wsl --list --verbose`. |
| `User`, `LinuxHome` | WSL user and its absolute Linux home. |
| `TargetAlias` | Concrete codex-apocrita alias. |
| `TargetHost`, `TargetUser`, `TargetPort` | Authorized login endpoint and remote account, matching the WSL alias. |
| `LinuxSsh` | `/usr/bin/ssh` inside WSL. |
| `LinuxConfig` | SSH config under `LinuxHome/.ssh/`. |
| `ControlPath` | Existing master socket under `LinuxHome/.ssh/`; `%C` is supported. |
| `WindowsConfigPath` | Absolute Windows SSH config path used for desktop discovery. |
| `WindowsIdentityPath` | Optional recognized Windows key filename, or `null`; the key is not read or transferred. |
| `WindowsSsh` | Must be `System32\OpenSSH\ssh.exe` under the current Windows directory, normally `C:\Windows\System32\OpenSSH\ssh.exe`. Other executable locations are refused. |
| `MetadataLogging` | Defaults to `false`; optional local metadata excludes commands and stream contents. |

The Linux config must already contain the alias. `ssh -G ALIAS` inside WSL inspects
effective settings without connecting. Its output may include account and key
paths, so do not paste it unedited into a public issue.

The desktop also needs a concrete Windows SSH entry. If one does not exist,
append an entry after reviewing existing entries; do not duplicate an alias:

```sshconfig
Host apocrita-codex
    HostName login.example.invalid
    User hpcuser
    Port 22
```

Replace this example with the same endpoint/account/port/alias as the adapter.
The Windows installer does not rewrite SSH files or copy keys.

## Build and install

Review the scripts and follow your organization's execution policy. Installation
does not change that policy or require disabling security software.
Use an ASCII installation path when supporting BOM-less Windows PowerShell
profiles. The profile editor supports UTF-8 and BOM-marked UTF-16, and refuses
unrecognized encodings or edited managed markers rather than rewriting them.

Prepare, build, and install in a private local directory under the same Windows
account. Sources, the generated validator, and the configuration must belong to
that account; the installer checks that relevant files and directories are writable
only by the owner, SYSTEM, or Administrators. Reparse paths are refused. A checkout
created by a sandbox or another account, or one inheriting broader write access,
may fail preflight. Resolve the preparation environment before installation; do not
disable these checks or claim a refused preflight as successful deployment.

```powershell
pwsh -NoProfile -File .\Build.ps1
pwsh -NoProfile -File .\Install-Adapter.ps1 -ConfigPath .\adapter-config.json -CheckOnly
```

The check-only operation does not install a hook. Before installing, finish or
pause work that depends on the desktop connection and quit the desktop normally.
The installer refuses an active desktop process.

```powershell
pwsh -NoProfile -File .\Install-Adapter.ps1 -ConfigPath .\adapter-config.json
```

This validates the configuration, protects adapter files, and appends a marked
suffix to supported PowerShell profiles while preserving their existing contents.
Review its output for affected paths and backups. It does not replace system SSH,
modify the Store package, or add the adapter to user or machine PATH.

## Authenticate and launch

Use the existing workflow in a trusted WSL terminal:

```bash
apo ssh status
# Only if new interactive authentication is required:
apo ssh start
```

Enter secrets only in that terminal or the provider's authentication page. The
adapter reuses the master; if it disappears, the adapter fails without requesting
a password. Start or reuse a controller through the WSL-side workflow and verify
its owner and RUNNING state from the login-side scheduler before attachment.
Choose resources according to actual work and site rules; this adapter leaves
upstream resource defaults unchanged.

From the adapter directory:

```powershell
pwsh -NoProfile -File .\Start-DesktopWithAdapter.ps1 -CheckOnly
pwsh -NoProfile -File .\Start-DesktopWithAdapter.ps1
```

The launcher uses registered package metadata and the official activation API.
A short-lived lease identifies the launched process and lets only its matching
PowerShell child receive the adapter PATH. Ordinary shells do not qualify. If
the desktop is already running, quit it normally; the launcher will not kill it.

Select the configured alias in the desktop SSH settings, then the intended remote
project directory. Separate tasks may use separate roots within one controller.
They share resources and a Unix account; this is not operating-system isolation.

## Verify without compute probes

Run the [local Windows tests](windows-testing.md) first. For a real installation,
verify these observations separately:

1. WSL `apo ssh status` reports an authenticated master.
2. The desktop discovers the alias and opens a remote project.
3. A real desktop request completes without another password prompt.
4. Login-side `squeue`, `scontrol`, `sacct`, or appropriate `sstat` metadata links
   the backend to the expected owned, running allocation.
5. Multiple-task claims use actual task activity, not just concurrent test streams.

This guide does not require `apo doctor --runtime`, `runtime-check`, or extra
hostname/cgroup/affinity/test probes inside the controller. Follow site-specific
workload rules. If scientific compilation, testing, training, inference, and
processing must use separate saved `.sbatch` payloads submitted from login, keep
submission on the authenticated login control path. Do not submit from the compute
controller or reverse-SSH back to login.

## Troubleshooting and removal

| Symptom | Next check |
| --- | --- |
| `APOCRITA_REAUTH_REQUIRED` | Reauthenticate in the selected WSL distribution/user. |
| Alias not visible | Check the concrete Windows SSH entry and selected connection. |
| Adapter refuses a request | Check validated settings and supported options; do not enable arbitrary proxies or forwarding. |
| Store executable missing after update | Let the update finish and rerun the launch check. |
| Direct WindowsApps executable launch denied | Use the package-activation launcher; do not alter WindowsApps permissions. |
| Build output quarantined | Review security-product events and source/build provenance; use only a narrowly scoped, organization-approved exception if needed. |
| Connection works but a task fails | Investigate remote task configuration and permissions separately. |

Quit the desktop normally before removing the hook:

```powershell
pwsh -NoProfile -File .\Rollback-Adapter.ps1 -VerifyOnly
pwsh -NoProfile -File .\Rollback-Adapter.ps1
```

Removal checks the exact installed suffix and disables its lease. Source, private
configuration, and backups remain. It does not cancel Slurm jobs or remove WSL
authentication. If the suffix has changed, inspect the difference rather than
overwriting the profile.

## Evidence and limits

The design comes from an integration exercised on Windows x64, PowerShell 5.1/7,
WSL Ubuntu, Linux OpenSSH, and a Slurm-backed app-server. The generalized source
needs its own installation acceptance: success of an earlier machine-specific
installation is not a live acceptance test of this version.

There is no blanket guarantee for future desktop packages, all distributions or
security products, unattended goals, shutdown, sleep, network loss, allocation
expiry, or peak multi-task usage. Raw deployment logs, research tasks, credentials,
and proprietary desktop source are not included.
