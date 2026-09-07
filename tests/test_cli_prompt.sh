#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home

mkdir -p "$XDG_CONFIG_HOME/codex-apocrita"
cat > "$XDG_CONFIG_HOME/codex-apocrita/config" <<EOF
SSH_ALIAS=apocrita-codex
BASE_HOST=apocrita
COMMAND_NAME=apo
ENDPOINT=login.hpc.qmul.ac.uk
SOURCE_DIR=$TEST_ROOT
EOF

write_executable "$TEST_TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *profile-show*cpu* ]]; then
  cat <<OUT
JOB_NAME=codex-desktop
PARTITION=compute
NODES=1
NTASKS=1
CPUS_PER_TASK=4
MEM=12G
TIME=10:00:00
OUT
elif [[ "$*" == *profile-names* ]]; then
  printf 'cpu\nlarge\n'
fi
exit 0
EOF

bash "$TEST_ROOT/bin/codex-apocrita" test-prompt cpu > "$TEST_TMP/prompt"
assert_contains "$TEST_TMP/prompt" 'Then spawn exactly one subagent.'
assert_contains "$TEST_TMP/prompt" 'Return exactly one single-line JSON object'
assert_contains "$TEST_TMP/prompt" '"expected":{"cpu_count":4,"memory":"12G","time_limit":"10:00:00"}'
assert_contains "$TEST_TMP/prompt" 'Do not copy the root agent'
assert_contains "$TEST_TMP/prompt" 'retain its result before spawning the subagent'
assert_contains "$TEST_TMP/prompt" 'use at least 10000 ms'
assert_contains "$TEST_TMP/prompt" 'Use only these'
assert_contains "$TEST_TMP/prompt" '/bin/hostname'
assert_contains "$TEST_TMP/prompt" '/usr/bin/printenv SLURM_JOB_ID'
assert_contains "$TEST_TMP/prompt" '/bin/cat /proc/self/cgroup'
assert_contains "$TEST_TMP/prompt" '/usr/bin/awk -F:'
assert_contains "$TEST_TMP/prompt" 'Do not use Node.js, Python, Perl, Ruby'
assert_contains "$TEST_TMP/prompt" 'A subagent'
assert_contains "$TEST_TMP/prompt" 'orchestration error is not a root execution failure'
assert_contains "$TEST_TMP/prompt" 'do not use an elevated, escalated, or unsandboxed'
assert_contains "$TEST_TMP/prompt" '"root_default_exec_succeeded":false'
assert_contains "$TEST_TMP/prompt" '"subagent_default_exec_succeeded":false'
assert_contains "$TEST_TMP/prompt" '"fallback_used":false'

bash "$TEST_ROOT/bin/codex-apocrita" __complete profiles > "$TEST_TMP/profiles"
assert_contains "$TEST_TMP/profiles" 'cpu'

bash "$TEST_ROOT/bin/codex-apocrita" doctor > "$TEST_TMP/doctor"
assert_contains "$TEST_TMP/doctor" 'codex-apocrita:'
