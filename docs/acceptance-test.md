## Clean installation

1. Confirm the account has a minimal working SSH alias with only its gateway, username, and identity file.
2. Run `./install.sh --dry-run` locally and verify it changes nothing.
3. Run the interactive installer with its default CPU profile.
4. Confirm no administrator command was requested and every created remote file is beneath the account's home directory.
5. Complete remote device-code authentication and run `apo doctor`.
6. Run the installer a second time and confirm the SSH include and shell blocks are not duplicated.

## Runtime placement

1. Run `apo` and wait for the allocation.
2. Enable the generated alias in Codex Desktop and open a project in the shared Apocrita filesystem.
3. In the root agent, collect `hostname`, `SLURM_JOB_ID`, `/proc/self/cgroup`, `Cpus_allowed_list`, and `TMPDIR`.
4. Spawn at least two subagents and collect the same values from each.
5. Confirm every process reports the same job ID, a Slurm cgroup for that job, CPUs within the requested allocation, and the same private `~/.local/state/codex-apocrita/tmp/job-JOB_ID` directory.
6. Confirm ordinary file editing and terminal commands work from both root and subagent contexts.

## Failure and lifecycle paths

1. Interrupt a local `apo` wait while a job is pending, then confirm `apo status` and a later `apo` reuse it.
2. Force the local-upload install mode and confirm checksum verification and Codex startup.
3. Change the CPU profile, run `apo update`, and confirm the profile was preserved.
4. Exercise `apo rollback`, then update forward again.
5. Let or cancel an allocation, run `apo clean`, and confirm its private temporary directory is removed.
6. Run `apo off` and confirm both the allocation and SSH master stop.
7. Reinstall, run the ordinary uninstaller, and confirm managed local/remote files are gone while Codex's standalone package remains.
8. Reinstall and uninstall with `--purge-codex`; confirm the managed standalone package is also removed.
9. Confirm pre-existing SSH and shell lines remain and timestamped backups are available.

## Release record

Record the date, Codex Desktop version, installed remote Codex CLI version, local OS, endpoint class (`login` or `vscode`), and a pass/fail result for each section. Do not publish account identifiers.
