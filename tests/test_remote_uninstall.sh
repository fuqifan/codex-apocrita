#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/codex-apocrita/releases/0.1.0/remote" \
  "$XDG_CONFIG_HOME/codex-apocrita" "$XDG_STATE_HOME/codex-apocrita" "$HOME/.codex/packages/standalone/current/bin"
cp "$TEST_ROOT/remote/codex-slurm-job" "$TEST_ROOT/remote/codex-runtime-common" \
  "$HOME/.local/share/codex-apocrita/releases/0.1.0/remote/"
chmod 755 "$HOME/.local/share/codex-apocrita/releases/0.1.0/remote/"*
ln -s "$HOME/.local/share/codex-apocrita/releases/0.1.0" "$HOME/.local/share/codex-apocrita/current"
ln -s "$HOME/.local/share/codex-apocrita/current/remote/codex-dispatch" "$HOME/.local/bin/codex"
ln -s "$HOME/.local/share/codex-apocrita/current/remote/codex-direct" "$HOME/.local/bin/codex-direct"
mkdir -p "$HOME/.codex/tmp/arg0"
source "$TEST_ROOT/remote/codex-runtime-common"
ca_prepare_codex_tmp
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
[[ -d "$HOME/.codex/tmp" && ! -L "$HOME/.codex/tmp" ]] || fail 'Codex tmp link was not restored'
assert_contains "$HOME/.bashrc" '# keep me'
assert_count 0 '# >>> codex-apocrita >>>' "$HOME/.bashrc"
