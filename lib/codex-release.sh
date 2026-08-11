#!/usr/bin/env bash

CA_CODEX_METADATA_URL='https://releases.openai.com/codex/channels/latest'

ca_codex_target_for_arch() {
  case "$1" in
    x86_64|amd64) printf 'x86_64-unknown-linux-musl\n' ;;
    aarch64|arm64) printf 'aarch64-unknown-linux-musl\n' ;;
    *) ca_die "Unsupported remote architecture: $1" ;;
  esac
}

ca_metadata_field_for_asset() {
  local metadata="$1" asset="$2" field="$3"
  awk -v asset="$asset" -v field="$field" '
    $0 ~ "\\\"name\\\"[[:space:]]*:[[:space:]]*\\\"" asset "\\\"" { found=1 }
    found && $0 ~ "\\\"" field "\\\"[[:space:]]*:" {
      line=$0; sub(/^.*:[[:space:]]*\"/, "", line); sub(/\"[,]?[[:space:]]*$/, "", line); print line; exit
    }
  ' "$metadata"
}

ca_fetch_codex_package() {
  local arch="$1" output_dir="$2" metadata target asset url digest archive actual version
  ca_require curl
  mkdir -p "$output_dir"
  metadata="$output_dir/release.json"
  curl -fsSL "$CA_CODEX_METADATA_URL" -o "$metadata"
  target=$(ca_codex_target_for_arch "$arch")
  asset="codex-package-$target.tar.gz"
  url=$(ca_metadata_field_for_asset "$metadata" "$asset" browser_download_url)
  digest=$(ca_metadata_field_for_asset "$metadata" "$asset" digest)
  digest="${digest#sha256:}"
  [[ "$digest" == [0-9a-fA-F][0-9a-fA-F]* && ${#digest} -eq 64 ]] || ca_die "No valid digest found for $asset."
  [[ -n "$url" ]] || ca_die "No download URL found for $asset."
  version=$(awk '/"tag_name"[[:space:]]*:/ { line=$0; sub(/^.*:[[:space:]]*"/, "", line); sub(/^rust-v/, "", line); sub(/^v/, "", line); sub(/"[,]?[[:space:]]*$/, "", line); print line; exit }' "$metadata")
  [[ -n "$version" ]] || ca_die 'Could not resolve the latest Codex version.'
  archive="$output_dir/$asset"
  ca_info "Downloading official Codex CLI $version for $target"
  curl -fsSL "$url" -o "$archive"
  actual=$(ca_sha256 "$archive")
  [[ "$actual" == "$digest" ]] || ca_die "Codex archive checksum mismatch."
  printf '%s|%s|%s|%s\n' "$archive" "$digest" "$version" "$target"
}
