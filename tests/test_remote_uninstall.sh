#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/codex-apocrita/releases/0.1.0/remote" \
  "$XDG_CONFIG_HOME/codex-apocrita" "$XDG_STATE_HOME/codex-apocrita" "$HOME/.codex/packages/standalone/current/bin"
cp "$TEST_ROOT/remote/codex-slurm-job" "$HOME/.local/share/codex-apocrita/releases/0.1.0/remote/codex-slurm-job"
chmod 755 "$HOME/.local/share/codex-apocrita/releases/0.1.0/remote/codex-slurm-job"
ln -s "$HOME/.local/share/codex-apocrita/releases/0.1.0" "$HOME/.local/share/codex-apocrita/current"
ln -s "$HOME/.local/share/codex-apocrita/current/remote/codex-dispatch" "$HOME/.local/bin/codex"
ln -s "$HOME/.codex/packages/standalone/current/bin/codex" "$HOME/.local/bin/codex-direct"
cat > "$HOME/.bashrc" <<'EOF'
# keep me
# >>> codex-apocrita >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< codex-apocrita <<<
# CODEX_APOCRITA_SHELL_WRAPPER
export SHELL=wrapper
# <<< CODEX_APOCRITA_SHELL_WRAPPER
EOF
bash "$TEST_ROOT/remote/uninstall-remote.sh" --purge-codex
assert_absent "$HOME/.local/share/codex-apocrita"
assert_absent "$XDG_CONFIG_HOME/codex-apocrita"
assert_absent "$XDG_STATE_HOME/codex-apocrita"
assert_absent "$HOME/.codex/packages/standalone"
assert_absent "$HOME/.local/bin/codex"
assert_absent "$HOME/.local/bin/codex-direct"
assert_contains "$HOME/.bashrc" '# keep me'
assert_count 0 '# >>> codex-apocrita >>>' "$HOME/.bashrc"
