#!/usr/bin/env bash

ca_start_master() {
  local alias="$1" socket
  if ssh -O check "$alias" >/dev/null 2>&1 && ssh -o BatchMode=yes "$alias" true >/dev/null 2>&1; then return; fi
  socket=$(ssh -G "$alias" 2>/dev/null | awk '$1=="controlpath"{print $2;exit}')
  ssh -O exit "$alias" >/dev/null 2>&1 || true
  [[ -n "$socket" ]] && rm -f -- "$socket"
  ca_info "Authenticate the reusable SSH connection for $alias"
  ssh -MNf "$alias" || ca_die 'SSH authentication failed.'
  for _ in {1..25}; do
    ssh -O check "$alias" >/dev/null 2>&1 && ssh -o BatchMode=yes "$alias" true >/dev/null 2>&1 && return
    sleep 0.2
  done
  ca_die 'SSH master did not become usable.'
}

ca_make_remote_bundle() {
  local source_root="$1" output="$2" stage
  stage=$(mktemp -d "${TMPDIR:-/tmp}/codex-apocrita-bundle.XXXXXX")
  mkdir -p "$stage/remote" "$stage/profiles"
  cp "$source_root"/remote/* "$stage/remote/"
  cp "$source_root"/profiles/cpu.conf "$stage/profiles/cpu.conf"
  cp "$source_root/VERSION" "$stage/VERSION"
  # macOS can attach com.apple.provenance to downloaded repository files.
  # COPYFILE_DISABLE avoids AppleDouble files; --no-xattrs prevents libarchive
  # from serializing the provenance attribute into PAX headers that GNU tar on
  # the remote host would otherwise warn about while extracting.
  COPYFILE_DISABLE=1 tar --no-xattrs -czf "$output" -C "$stage" .
  rm -rf "$stage"
}

ca_remote_install() {
  local source_root="$1" alias="$2" install_mode="$3" bundle tmp_remote command arch package_info archive digest version target package_remote package_dir
  bundle=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-remote.XXXXXX.tar.gz")
  ca_make_remote_bundle "$source_root" "$bundle"
  tmp_remote=".local/state/codex-apocrita/install-$$"
  # tmp_remote is generated locally from a numeric PID and contains no shell metacharacters.
  # shellcheck disable=SC2029
  ssh "$alias" "mkdir -p '$tmp_remote'"
  scp -q "$bundle" "$alias:$tmp_remote/integration.tar.gz"
  # shellcheck disable=SC2029
  ssh "$alias" "tar -xzf '$tmp_remote/integration.tar.gz' -C '$tmp_remote'"

  if [[ "$install_mode" == auto || "$install_mode" == remote ]]; then
    command="'$tmp_remote/remote/install-remote.sh'"
    if ssh -o BatchMode=yes "$alias" "bash -lc $(printf '%q' "$command")"; then
      # shellcheck disable=SC2029
      ssh -o BatchMode=yes "$alias" "rm -rf -- '$tmp_remote'" || ca_warn "Could not remove remote installer staging directory: $tmp_remote"
      rm -f "$bundle"
      return
    fi
    [[ "$install_mode" == auto ]] || ca_die 'Remote Codex download failed.'
    ca_warn 'Remote download failed; switching to verified local download and SSH upload.'
  fi

  arch=$(ssh -o BatchMode=yes "$alias" uname -m)
  package_dir="$(dirname "$bundle")/codex-package-$$"
  package_info=$(ca_fetch_codex_package "$arch" "$package_dir")
  IFS='|' read -r archive digest version target <<< "$package_info"
  package_remote="$tmp_remote/$(basename "$archive")"
  scp -q "$archive" "$alias:$package_remote"
  command="'$tmp_remote/remote/install-remote.sh' --package '$package_remote' --digest '$digest' --codex-version '$version' --target '$target'"
  ssh -o BatchMode=yes "$alias" "bash -lc $(printf '%q' "$command")"
  # shellcheck disable=SC2029
  ssh -o BatchMode=yes "$alias" "rm -rf -- '$tmp_remote'" || ca_warn "Could not remove remote installer staging directory: $tmp_remote"
  rm -f "$bundle"
  rm -rf -- "$package_dir"
}
