#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/codex-apocrita/current/remote" "$HOME/.local/share/codex-apocrita/upstream-bin"
write_executable "$HOME/.local/bin/codex-direct" <<EOF
#!/usr/bin/env bash
printf 'direct:%s\n' "\$*" >> '$TEST_TMP/calls'
EOF
write_executable "$HOME/.local/share/codex-apocrita/current/remote/codex-slurm" <<EOF
#!/usr/bin/env bash
printf 'slurm:%s\n' "\$*" >> '$TEST_TMP/calls'
EOF
bash "$TEST_ROOT/remote/codex-dispatch" --version
bash "$TEST_ROOT/remote/codex-dispatch" app-server --listen stdio
assert_contains "$TEST_TMP/calls" 'direct:--version'
assert_contains "$TEST_TMP/calls" 'slurm:app-server --listen stdio'
