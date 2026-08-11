# Quick testing guide

Thank you for testing `codex-apocrita`. Start with a normal Apocrita SSH alias that already contains your username and private key. Run the installer on your own computer, not on Apocrita. No administrator access is required on either system.

Please use a small CPU allocation for this test. Submit substantial CPU or GPU work separately through Slurm as usual.

## 1. Install

Clone the private repository on macOS or Linux:

```bash
git clone https://github.com/Ellysian/codex-apocrita.git
cd codex-apocrita
```

Preview the installation without changing anything:

```bash
./install.sh --dry-run
```

Then run the interactive installer:

```bash
./install.sh
```

The defaults create:

- the local command `apo`;
- the SSH alias `apocrita-codex`;
- a 2-CPU, 8G, four-hour job on `compute`.

Choose the name of your existing SSH alias when prompted. Authentication happens in your terminal. The installer may also display a Codex device code; open the displayed page locally and approve it. Never enter an SSH password into Codex Desktop or save it in a script.

Open a new terminal after installation.

## 2. Start Codex

```bash
apo doctor
apo
```

Wait for `Ready`, then open Codex Desktop:

1. Open **Settings → Connections**.
2. Enable `apocrita-codex`, or the alias you selected.
3. Open a small test repository on Apocrita.

## 3. Verify the allocation

Send Codex this prompt:

```text
Run hostname, print SLURM_JOB_ID, show /proc/self/cgroup,
show Cpus_allowed_list from /proc/self/status, and print TMPDIR.
Then spawn two subagents and ask each to run the same checks.
Present all three results in a table.
```

The root agent and both subagents should report:

- the same compute-node hostname and Slurm job ID;
- a cgroup containing that job ID;
- a limited CPU set;
- the same private `~/.local/state/codex-apocrita/tmp/job-JOB_ID` directory.

Also ask the subagents to run `pwd`, `git status --short`, and `/usr/bin/true`. These commands should complete without a `No such file or directory` process-launch error.

## 4. Try the basic lifecycle

```bash
apo status
apo ssh off       # disconnect SSH without cancelling the job
apo ssh force     # authenticate again and reuse the job
apo stop          # cancel the job but keep SSH ready
apo               # start a new job
apo off           # stop both the job and SSH
```

To test a different allocation:

```bash
apo stop
apo config set cpu CPUS_PER_TASK=4 MEM=16G TIME=1:00:00
apo
apo doctor --runtime
```

## 5. Report the result

Please report:

- macOS or Linux version and shell;
- login or VS Code endpoint;
- whether installation, Desktop connection, root commands, and subagents worked;
- output from `apo doctor` and `apo status` with usernames, job IDs, node names, and private paths removed;
- the exact error and the step that produced it when something failed.

Never share passwords, private keys, device codes, API keys, Codex authentication files, or unsanitized logs.

When finished, stop the allocation with `apo off`. To remove the integration completely, run `apo uninstall`.
