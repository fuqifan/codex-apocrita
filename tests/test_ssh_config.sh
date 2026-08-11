#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
write_executable "$TEST_TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -G ]]; then
  cat <<OUT
user abc123
hostname login.example
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
