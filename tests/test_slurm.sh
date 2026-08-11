#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
mkdir -p "$XDG_CONFIG_HOME/codex-apocrita/profiles"
cp "$TEST_ROOT/profiles/cpu.conf" "$XDG_CONFIG_HOME/codex-apocrita/profiles/cpu.conf"
write_executable "$TEST_TMP/bin/sbatch" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > '$TEST_TMP/sbatch'
echo 4242
EOF
write_executable "$TEST_TMP/bin/squeue" <<'EOF'
#!/usr/bin/env bash
job=; format=
for arg in "$@"; do case "$arg" in --jobs=*) job=${arg#*=};; --format=*) format=${arg#*=};; esac; done
[[ "$job" == 4242 ]] || exit 0
case "$format" in
  %T) echo RUNNING;; %u) id -un;; %N) echo node42;;
  '%N|%M|%l') echo 'node42|0:03|4:00:00';;
esac
EOF
write_executable "$TEST_TMP/bin/scancel" <<EOF
#!/usr/bin/env bash
echo "\$*" >> '$TEST_TMP/scancel'
EOF
write_executable "$TEST_TMP/bin/srun" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$TEST_TMP/srun'
while [[ \$# -gt 0 && \$1 != env ]]; do shift; done
shift
export SLURM_JOB_ID=4242
if [[ "\$*" == *'/proc/self/cgroup'* ]]; then
  tmp=''
  for arg in "\$@"; do case "\$arg" in TMPDIR=*) tmp=\${arg#*=};; esac; done
  printf 'node42\nSLURM_JOB_ID=4242\n0::/slurm/job_4242/step_1\nCpus_allowed_list:\t4-5\nTMPDIR=%s\n' "\$tmp"
  exit
fi
exec env "\$@"
EOF
job="$TEST_ROOT/remote/codex-slurm-job"
bash "$job" start cpu
bash "$job" wait
assert_contains "$TEST_TMP/sbatch" '--partition=compute'
assert_contains "$TEST_TMP/sbatch" '--cpus-per-task=2'
assert_contains "$TEST_TMP/sbatch" '--mem=8G'
assert_contains "$TEST_TMP/sbatch" '--time=4:00:00'
assert_contains "$TEST_TMP/sbatch" '--output=/dev/null'
bash "$job" profile-create larger cpu
bash "$job" profile-set larger CPUS_PER_TASK=6 MEM=20G
bash "$job" profile-show larger > "$TEST_TMP/profile"
assert_contains "$TEST_TMP/profile" 'CPUS_PER_TASK=6'
assert_contains "$TEST_TMP/profile" 'MEM=20G'
mkdir -p "$XDG_STATE_HOME/codex-apocrita/tmp/job-9999"
bash "$job" clean
assert_absent "$XDG_STATE_HOME/codex-apocrita/tmp/job-9999"
bash "$job" runtime-check > "$TEST_TMP/runtime"
assert_contains "$TEST_TMP/runtime" 'SLURM_JOB_ID=4242'
assert_contains "$TEST_TMP/runtime" '/slurm/job_4242/'
assert_contains "$TEST_TMP/runtime" 'Cpus_allowed_list:'
assert_contains "$TEST_TMP/runtime" "$XDG_STATE_HOME/codex-apocrita/tmp/job-4242"
assert_contains "$TEST_TMP/srun" '--jobid=4242'

mkdir -p "$HOME/.local/bin"
write_executable "$HOME/.local/bin/codex-direct" <<EOF
#!/usr/bin/env bash
printf 'job=%s tmp=%s args=%s\n' "\$SLURM_JOB_ID" "\$TMPDIR" "\$*" >> '$TEST_TMP/agents'
EOF
bash "$TEST_ROOT/remote/codex-slurm" app-server --agent root
bash "$TEST_ROOT/remote/codex-slurm" app-server --agent subagent
assert_count 2 'job=4242' "$TEST_TMP/agents"
assert_count 2 "tmp=$XDG_STATE_HOME/codex-apocrita/tmp/job-4242" "$TEST_TMP/agents"
