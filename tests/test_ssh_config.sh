#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
write_executable "$TEST_TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -G ]]; then
  case "$2" in
    apocrita-login) resolved=login.hpc.qmul.ac.uk ;;
    apocrita-vscode) resolved=vscode.hpc.qmul.ac.uk ;;
    *) resolved=login.example ;;
  esac
  cat <<OUT
user abc123
hostname $resolved
port 2222
identityfile ~/.ssh/id_ed25519
identityfile none
OUT
fi
EOF
source "$TEST_ROOT/lib/common.sh"
source "$TEST_ROOT/lib/ssh-config.sh"
out="$TEST_TMP/fragment"
ca_render_ssh_fragment apocrita apocrita-codex login.hpc.qmul.ac.uk "$out"
assert_contains "$out" 'Host apocrita-codex'
assert_contains "$out" 'User abc123'
assert_contains "$out" 'IdentityFile ~/.ssh/id_ed25519'
assert_contains "$out" 'ControlMaster auto'
assert_contains "$out" 'ControlPath ~/.ssh/ca-%C'
! grep -Fq 'IdentityFile none' "$out" || fail 'none identity was copied'

mkdir -p "$HOME/.ssh"
cat > "$HOME/.ssh/config" <<'EOF'
Host unrelated
  HostName example.org
Host apocrita-vscode
  HostName vscode.hpc.qmul.ac.uk
Host apocrita-login
  HostName login.hpc.qmul.ac.uk
EOF
detected=$(ca_detect_apocrita_base_host "$HOME/.ssh/config" apocrita-codex)
[[ "$detected" == apocrita-login ]] || fail "expected login alias, got $detected"

cat > "$HOME/.ssh/config" <<'EOF'
Host apocrita-vscode
  HostName vscode.hpc.qmul.ac.uk
EOF
detected=$(ca_detect_apocrita_base_host "$HOME/.ssh/config" apocrita-codex)
[[ "$detected" == apocrita-vscode ]] || fail "expected vscode alias, got $detected"
