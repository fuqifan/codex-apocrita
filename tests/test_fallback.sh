#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
write_executable "$TEST_TMP/bin/ssh" <<EOF
#!/usr/bin/env bash
printf 'ssh:%s\n' "\$*" >> '$TEST_TMP/calls'
case "\$*" in
  *uname\ -m*) echo x86_64; exit 0;;
  *install-remote.sh*--package*) exit 0;;
  *install-remote.sh*) exit 1;;
esac
exit 0
EOF
write_executable "$TEST_TMP/bin/scp" <<EOF
#!/usr/bin/env bash
printf 'scp:%s\n' "\$*" >> '$TEST_TMP/calls'
EOF
source "$TEST_ROOT/lib/common.sh"
source "$TEST_ROOT/lib/remote-deploy.sh"
ca_make_remote_bundle() { printf bundle > "$2"; }
ca_fetch_codex_package() {
  mkdir -p "$2"; printf package > "$2/package.tar.gz"
  printf '%s|%064d|1.2.3|x86_64-unknown-linux-musl\n' "$2/package.tar.gz" 0
}
ca_remote_install "$TEST_ROOT" host auto
assert_contains "$TEST_TMP/calls" 'install-remote.sh'
assert_contains "$TEST_TMP/calls" '--package'
assert_contains "$TEST_TMP/calls" 'package.tar.gz'
