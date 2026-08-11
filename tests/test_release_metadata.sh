#!/usr/bin/env bash
source "$(dirname "$0")/testlib.sh"
new_home
source "$TEST_ROOT/lib/common.sh"
source "$TEST_ROOT/lib/codex-release.sh"
cat > "$TEST_TMP/release.json" <<'EOF'
{
  "tag_name": "rust-v1.2.3",
  "assets": [{
    "name": "codex-package-x86_64-unknown-linux-musl.tar.gz",
    "browser_download_url": "https://example.invalid/package.tar.gz",
    "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }]
}
EOF
url=$(ca_metadata_field_for_asset "$TEST_TMP/release.json" codex-package-x86_64-unknown-linux-musl.tar.gz browser_download_url)
digest=$(ca_metadata_field_for_asset "$TEST_TMP/release.json" codex-package-x86_64-unknown-linux-musl.tar.gz digest)
[[ "$url" == https://example.invalid/package.tar.gz ]] || fail 'metadata URL parser failed'
[[ "$digest" == sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]] || fail 'metadata digest parser failed'
