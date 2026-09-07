#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home

sed 's/__APO_COMMAND__/apo/g' "$TEST_ROOT/completions/apo.bash" > "$TEST_TMP/apo.bash"
bash -n "$TEST_TMP/apo.bash"
assert_contains "$TEST_TMP/apo.bash" 'test-prompt'
assert_contains "$TEST_TMP/apo.bash" 'CPUS_PER_TASK='
assert_contains "$TEST_TMP/apo.bash" 'MEM_PER_CPU='
assert_contains "$TEST_TMP/apo.bash" '--help'
assert_contains "$TEST_TMP/apo.bash" '__complete profiles'
# shellcheck disable=SC1091
source "$TEST_TMP/apo.bash"
COMP_WORDS=(apo config set cpu CP)
COMP_CWORD=4
_apo_completion
[[ " ${COMPREPLY[*]} " == *' CPUS_PER_TASK= '* ]] || fail 'Bash setting completion failed'

sed 's/__APO_COMMAND__/apo/g' "$TEST_ROOT/completions/_apo" > "$TEST_TMP/_apo"
if command -v zsh >/dev/null 2>&1; then zsh -n "$TEST_TMP/_apo"; fi
assert_contains "$TEST_TMP/_apo" 'test-prompt'
assert_contains "$TEST_TMP/_apo" 'CPUS_PER_TASK='
assert_contains "$TEST_TMP/_apo" '__complete profiles'
