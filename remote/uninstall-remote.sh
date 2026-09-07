#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/slurm/bin:$HOME/.local/bin:$PATH"

purge_codex=0
[[ "${1:-}" == --purge-codex ]] && purge_codex=1
remote_root="$HOME/.local/share/codex-apocrita"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/codex-apocrita"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}/codex-apocrita"
job_tool="$remote_root/current/remote/codex-slurm-job"
runtime_common="$remote_root/current/remote/codex-runtime-common"

[[ "$(id -u)" -ne 0 ]] || { echo 'Refusing to run as root.' >&2; exit 1; }
if [[ -x "$job_tool" ]]; then "$job_tool" stop || true; fi
if [[ -r "$runtime_common" ]]; then
  # shellcheck source=codex-runtime-common
  source "$runtime_common"
  ca_remove_codex_tmp_link
fi

for link in "$HOME/.local/bin/codex" "$HOME/.local/bin/codex-direct" "$HOME/.local/bin/codex-apocrita-login-shell"; do
  if [[ -L "$link" ]]; then
    target=$(readlink "$link")
    case "$target" in *codex-apocrita*|*packages/standalone*) rm -f -- "$link" ;; esac
  fi
done

remove_blocks() {
  local file="$1" tmp
  [[ -f "$file" ]] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-uninstall.XXXXXX")
  awk '
    $0=="# >>> codex-apocrita >>>" {skip=1; next}
    $0=="# <<< codex-apocrita <<<" {skip=0; next}
    $0=="# CODEX_APOCRITA_SHELL_WRAPPER" {wrapper=1; next}
    $0=="# <<< CODEX_APOCRITA_SHELL_WRAPPER" {wrapper=0; next}
    !skip && !wrapper {print}
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}
remove_blocks "$HOME/.profile"; remove_blocks "$HOME/.bash_profile"; remove_blocks "$HOME/.bashrc"

rm -rf -- "$remote_root" "$state_root" "$config_root"
if [[ "$purge_codex" == 1 ]]; then rm -rf -- "$HOME/.codex/packages/standalone"; fi
echo 'Remote codex-apocrita components removed.'
