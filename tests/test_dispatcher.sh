#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
export TMPDIR="$TEST_TMP/tmp"
mkdir -p "$TMPDIR"
# The runtime targets Linux. This small legacy routing fixture also runs on
# macOS CI, where readlink lacks GNU -m; emulate only that operation locally.
write_executable "$TEST_TMP/bin/readlink" <<'EOF'
#!/usr/bin/env python3
import os, sys
assert sys.argv[1:3] == ["-m", "--"] and len(sys.argv) == 4
print(os.path.realpath(sys.argv[3]))
EOF
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
