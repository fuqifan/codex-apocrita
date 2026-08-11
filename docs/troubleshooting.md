# Troubleshooting

Start with:

```bash
apo doctor
apo status
apo logs 200
```

## Codex shows `Permission denied (password)`

Codex Desktop cannot answer Apocrita's interactive password prompt, so it may report `Permission denied (password)` when no authenticated SSH master is available. Run `apo ssh force` in a terminal, finish authentication there, and reconnect Codex Desktop. Don't put the password in `sshpass`, an `expect` script, or a file.

## SSH: disconnected

Network changes invalidate a ControlMaster TCP connection. Run `apo` again. The job may still be running; `apo` reuses it after the new master is ready.

## App-server WebSocket closes with code 1006

Check:

```bash
apo doctor
apo logs 200
```

Common causes are an expired allocation, remote Codex missing from PATH, incomplete authentication, or shell output corrupting the protocol. Re-run the idempotent installer if the remote shell wrapper or dispatcher is missing.

## Subagents fail with `No such file or directory`

Run `apo doctor --runtime` and confirm `TMPDIR` points beneath:

```text
~/.local/state/codex-apocrita/tmp/job-JOB_ID
```

If it reports `/tmp`, update or reinstall the integration. Step-local `/tmp` prevents fresh subagents from seeing Codex process helpers.

## Job remains pending

`apo` waits while Slurm reports `PENDING` or `CONFIGURING`. Use `squeue` on Apocrita to inspect the reason. You can interrupt the local wait without cancelling the job; `apo status` will still show it.

## Allocation expired

Run `apo`. Stale state is removed and a replacement allocation is submitted. Codex Desktop should reconnect after the backend starts.

## Remote download fails

Force local download and upload:

```bash
./install.sh --remote-install-mode upload
```

The package digest is checked locally and remotely.

## Host alias is missing in Desktop

Confirm it is concrete and resolvable:

```bash
ssh -G apocrita-codex | head
```

Pattern-only `Host *` entries are not discoverable as named hosts. Re-run the installer if the managed `Include ~/.ssh/codex-apocrita.conf` line is missing.
