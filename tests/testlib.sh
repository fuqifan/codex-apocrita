#!/usr/bin/env bash
set -euo pipefail

export TEST_ROOT
TEST_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "expected file: $1"; }
assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] || fail "expected absent: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"; }
assert_count() {
  local expected="$1" pattern="$2" file="$3" actual
  actual=$(grep -Fc -- "$pattern" "$file" || true)
  [[ "$actual" == "$expected" ]] || fail "expected $expected occurrences of '$pattern' in $file, got $actual"
}
new_home() {
  TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/codex-apocrita-test.XXXXXX")
  export TEST_TMP HOME="$TEST_TMP/home" XDG_CONFIG_HOME="$TEST_TMP/config" XDG_STATE_HOME="$TEST_TMP/state" XDG_DATA_HOME="$TEST_TMP/data"
  mkdir -p "$HOME" "$TEST_TMP/bin"
  export PATH="$TEST_TMP/bin:/usr/local/bin:/usr/bin:/bin"
}
write_executable() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cp /dev/stdin "$path"
  chmod 755 "$path"
}
