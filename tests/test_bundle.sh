#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home

# shellcheck source=../lib/common.sh
source "$TEST_ROOT/lib/common.sh"
# shellcheck source=../lib/remote-deploy.sh
source "$TEST_ROOT/lib/remote-deploy.sh"

bundle="$TEST_TMP/remote.tar.gz"
ca_make_remote_bundle "$TEST_ROOT" "$bundle"
assert_file "$bundle"

if gzip -dc "$bundle" | strings | grep -Eq 'LIBARCHIVE\.xattr|SCHILY\.xattr'; then
  fail 'remote bundle contains extended-attribute PAX headers'
fi
