## Clean installation

1. Confirm the account has a minimal working SSH alias with only its gateway, username, and identity file.
2. Run `./install.sh --dry-run` locally and verify it changes nothing.
3. Run the interactive installer with its default CPU profile.
4. Confirm no administrator command was requested and every created remote file is beneath the account's home directory.
5. Complete remote device-code authentication and run `apo doctor`.
6. Run the installer a second time and confirm the SSH include and shell blocks are not duplicated.

## Runtime placement

1. Run `apo` and wait for the allocation.
2. Enable the generated Codex-specific alias in Codex Desktop, not the account's usual login or VS Code alias, and add a new remote project in the shared Apocrita filesystem.
3. Run `apo test-prompt`, paste the complete generated prompt into the new task, and confirm it returns exactly one JSON object.
4. Confirm the root agent and exactly one subagent report the same job ID, a Slurm cgroup for that job, the requested CPU count, and the same private `~/.local/state/codex-apocrita/tmp/job-JOB_ID` directory.
5. Confirm both default-execution fields and `checks.all_checks_pass` are `true`, and `fallback_used` is `false`.
6. Confirm `apo logs 200` contains no new `CreateProcess`, `ENOENT`, or Bubblewrap mount errors.
7. While Desktop remains connected, run `apo doctor`, then repeat the prompt and confirm login-node diagnostics did not remove the compute app-server's helpers.
8. Repeat the complete runtime placement test on a second fresh allocation before release.

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
