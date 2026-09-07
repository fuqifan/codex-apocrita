# Quick testing guide

Thank you for testing `codex-apocrita`. Start with a normal Apocrita SSH alias that already contains your username and private key. Run the installer on your own computer, not on Apocrita. No administrator access is required on either system.

Please use a small CPU allocation for this test. Submit substantial CPU or GPU work separately through Slurm as usual.

## 1. Install

Clone the public repository on macOS or Linux:

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
2. Enable the newly created `apocrita-codex` connection, or the new Codex SSH alias you selected during installation. Do **not** enable your usual Apocrita login-node or VS Code-node alias for this test.
3. Start a new chat, click on **Choose project**, and choose **New remote project**.
4. Select the new `apocrita-codex` connection.
5. Select any workspace on Apocrita and click **Add project**.

## 3. Verify the allocation

In your local terminal, generate the strict test prompt from the profile you installed:

```bash
apo test-prompt
```

For a different named profile, run `apo test-prompt PROFILE`. The command reads that remote profile when it runs, so its `expected.cpu_count`, `expected.memory`, and `expected.time_limit` values are generated from your current settings rather than copied from this guide.

Copy the entire generated prompt into the new Codex task. It requires the root agent and exactly one subagent to execute the checks independently and return one single-line JSON object with no Markdown. A successful result has this shape (values are illustrative):

```json
{"expected":{"cpu_count":4,"memory":"12G","time_limit":"10:00:00"},"root":{"hostname":"node123","slurm_job_id":"12345678","cgroup":"0::/system.slice/slurmstepd.scope/job_12345678/step_1/user/task_0\n","cpus_allowed_list":"2,10,19,21","cpu_count":4,"tmpdir":"/home/example/.local/state/codex-apocrita/tmp/job-12345678"},"subagent":{"hostname":"node123","slurm_job_id":"12345678","cgroup":"0::/system.slice/slurmstepd.scope/job_12345678/step_1/user/task_0\n","cpus_allowed_list":"2,10,19,21","cpu_count":4,"tmpdir":"/home/example/.local/state/codex-apocrita/tmp/job-12345678"},"checks":{"root_default_exec_succeeded":true,"subagent_default_exec_succeeded":true,"fallback_used":false,"same_hostname":true,"same_slurm_job_id":true,"job_id_present_in_root_cgroup":true,"job_id_present_in_subagent_cgroup":true,"same_tmpdir":true,"root_cpu_count_matches_profile":true,"subagent_cpu_count_matches_profile":true,"all_checks_pass":true}}
```

Confirm that:

- `checks.all_checks_pass` is `true`;
- both default-execution checks are `true` and `fallback_used` is `false`;
- both cgroups contain the reported Slurm job ID;
- both CPU counts match `expected.cpu_count`;
- root and subagent use the same compute node, job ID, and private `~/.local/state/codex-apocrita/tmp/job-JOB_ID` directory.

Because the subagent must execute terminal commands to collect its result, this also checks the shared temporary-directory fix for the former `No such file or directory` process-launch error.

If `apo logs` reports only an orchestration validation error such as `timeout_ms must be at least 10000`, regenerate the prompt after updating the integration. That error concerns how the agent waited for its subagent; it is not evidence of a Slurm, filesystem, or sandbox failure. The generated prompt requires the root probe to finish first so a later subagent orchestration error cannot erase a successful root result.

The generated prompt specifies absolute paths to standard POSIX utilities for both probes. This prevents an agent from choosing an optional interpreter such as Node.js that may not be installed on Apocrita. An exit status `127` with `node: command not found` is a diagnostic-command error, not a sandbox or subagent infrastructure failure.

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
