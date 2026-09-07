#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home

# shellcheck source=../remote/codex-runtime-common
source "$TEST_ROOT/remote/codex-runtime-common"
mkdir -p "$HOME/.codex/tmp/arg0/old-helper"
ca_prepare_codex_tmp
[[ -L "$HOME/.codex/tmp" ]] || fail 'Codex tmp is not a managed symlink'
[[ "$(readlink "$HOME/.codex/tmp")" == "$CODEX_APOCRITA_LOCAL_RUNTIME_ROOT/codex-tmp" ]] ||
  fail 'Codex tmp points to the wrong node-local directory'
assert_absent "$HOME/.codex/tmp/arg0/old-helper"

remote_root="$HOME/.local/share/codex-apocrita"
mkdir -p "$remote_root/releases/0.1.0/remote" "$remote_root/upstream-bin"
cp "$TEST_ROOT/remote/codex-runtime-common" "$TEST_ROOT/remote/codex-direct" \
  "$remote_root/releases/0.1.0/remote/"
ln -s "$remote_root/releases/0.1.0" "$remote_root/current"
write_executable "$remote_root/upstream-bin/codex" <<'EOF'
#!/usr/bin/env bash
helper="$HOME/.codex/tmp/helper.$$"
mkdir -p "$helper"
sleep 0.2
[[ -d "$helper" ]] || exit 1
printf '%s\n' "$(readlink "$HOME/.codex/tmp")"
EOF

bash "$remote_root/current/remote/codex-direct" > "$TEST_TMP/first" & first=$!
bash "$remote_root/current/remote/codex-direct" > "$TEST_TMP/second" & second=$!
wait "$first" "$second"
assert_contains "$TEST_TMP/first" "$CODEX_APOCRITA_LOCAL_RUNTIME_ROOT/codex-tmp"
assert_contains "$TEST_TMP/second" "$CODEX_APOCRITA_LOCAL_RUNTIME_ROOT/codex-tmp"

ca_remove_codex_tmp_link
[[ -d "$HOME/.codex/tmp" && ! -L "$HOME/.codex/tmp" ]] ||
  fail 'uninstall did not restore a normal Codex tmp directory'
