#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
export SHELL=/bin/bash
mkdir -p "$HOME/.ssh"
printf '# user setting\n' > "$HOME/.bashrc"
printf '# user ssh setting\nHost apocrita\n  HostName original.example\n' > "$HOME/.ssh/config"
write_executable "$TEST_TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -G ]]; then
  cat <<OUT
user abc123
hostname original.example
port 22
identityfile ~/.ssh/id_ed25519
controlpath ~/.ssh/test-control
OUT
  exit
fi
exit 0
EOF
write_executable "$TEST_TMP/bin/scp" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$TEST_TMP/scp.log'
EOF
write_executable "$TEST_TMP/bin/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$TEST_TMP/sudo.log'
exit 99
EOF
real=$(command -v curl)
ln -s "$real" "$TEST_TMP/bin/curl"
run_install() {
  bash "$TEST_ROOT/install.sh" --yes --skip-auth --remote-install-mode remote \
    --base-host apocrita --ssh-alias apocrita-codex --command-name apo
}
bash "$TEST_ROOT/install.sh" --dry-run --yes --skip-auth --remote-install-mode remote \
  --base-host apocrita --ssh-alias apocrita-codex --command-name apo > "$TEST_TMP/dry-run"
assert_contains "$TEST_TMP/dry-run" 'Generated SSH fragment:'
assert_absent "$HOME/.ssh/codex-apocrita.conf"
run_install
run_install
assert_file "$HOME/.ssh/codex-apocrita.conf"
assert_contains "$HOME/.ssh/codex-apocrita.conf" 'Host apocrita-codex'
assert_count 1 'Include ~/.ssh/codex-apocrita.conf' "$HOME/.ssh/config"
assert_count 1 '# >>> codex-apocrita >>>' "$HOME/.bashrc"
[[ -L "$HOME/.local/bin/apo" ]] || fail 'apo symlink missing'
bash "$TEST_ROOT/install.sh" --from-config "$XDG_CONFIG_HOME/codex-apocrita/config" \
  --yes --skip-auth --remote-install-mode remote
assert_count 2 '.config/codex-apocrita/profiles/cpu.conf' "$TEST_TMP/scp.log"
assert_absent "$TEST_TMP/sudo.log"
bash "$XDG_DATA_HOME/codex-apocrita/current/uninstall.sh" --yes
assert_absent "$HOME/.ssh/codex-apocrita.conf"
assert_absent "$HOME/.local/bin/apo"
assert_contains "$HOME/.bashrc" '# user setting'
assert_count 0 '# >>> codex-apocrita >>>' "$HOME/.bashrc"
