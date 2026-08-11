#!/usr/bin/env bash
set -euo pipefail
root=$(cd -P "$(dirname "$0")" && pwd)
failed=0
for test_file in "$root"/test_*.sh; do
  printf '==> %s\n' "$(basename "$test_file")"
  if bash "$test_file"; then printf 'PASS\n'; else failed=1; fi
done
exit "$failed"
