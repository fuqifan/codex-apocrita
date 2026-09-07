#!/usr/bin/env bash

ca_ssh_value() {
  ssh -G "$1" 2>/dev/null | awk -v key="$2" '$1 == key { $1=""; sub(/^ /, ""); print; exit }'
}

ca_ssh_values() {
  ssh -G "$1" 2>/dev/null | awk -v key="$2" '$1 == key { $1=""; sub(/^ /, ""); print }'
}

ca_detect_apocrita_base_host() {
  local config="${1:-$HOME/.ssh/config}" excluded="${2:-apocrita-codex}"
  local candidates candidate hostname vscode_candidate=''
  [[ -r "$config" ]] || return 1
  candidates=$(awk '
    $1 == "Host" {
      for (i=2; i<=NF; i++) {
        if ($i !~ /[*?!]/ && !seen[$i]++) print $i
      }
    }
  ' "$config")
  while IFS= read -r candidate; do
    [[ -n "$candidate" && "$candidate" != "$excluded" ]] || continue
    hostname=$(ca_ssh_value "$candidate" hostname)
    case "$hostname" in
      login.hpc.qmul.ac.uk) printf '%s\n' "$candidate"; return 0 ;;
      vscode.hpc.qmul.ac.uk) [[ -n "$vscode_candidate" ]] || vscode_candidate="$candidate" ;;
    esac
  done <<< "$candidates"
  [[ -n "$vscode_candidate" ]] || return 1
  printf '%s\n' "$vscode_candidate"
}

ca_render_ssh_fragment() {
  local base="$1" alias="$2" endpoint="$3" output="$4"
  local user port identity
  user=$(ca_ssh_value "$base" user)
  port=$(ca_ssh_value "$base" port)
  [[ -n "$user" ]] || ca_die "Could not resolve a user from SSH host '$base'."
  {
    printf '# Managed by codex-apocrita. Re-run install.sh to update.\n'
    printf 'Host %s\n' "$alias"
    printf '  HostName %s\n' "$endpoint"
    printf '  User %s\n' "$user"
    [[ -n "$port" ]] && printf '  Port %s\n' "$port"
    while IFS= read -r identity; do
      [[ -n "$identity" && "$identity" != none ]] && printf '  IdentityFile %s\n' "$identity"
    done < <(ca_ssh_values "$base" identityfile)
    cat <<'EOF'
  PreferredAuthentications publickey,keyboard-interactive,password
  PasswordAuthentication yes
  KbdInteractiveAuthentication yes
  ControlMaster auto
  ControlPath ~/.ssh/ca-%C
  ControlPersist yes
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ConnectTimeout 10
  ConnectionAttempts 3
EOF
  } > "$output"
}

ca_install_ssh_include() {
  local ssh_dir="$HOME/.ssh" main="$HOME/.ssh/config" fragment="$HOME/.ssh/codex-apocrita.conf"
  local include='Include ~/.ssh/codex-apocrita.conf' tmp stamp
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  stamp=$(date +%Y%m%d-%H%M%S)
  [[ -f "$main" ]] && cp -p "$main" "$main.codex-apocrita.$stamp.bak"
  [[ -f "$fragment" ]] && cp -p "$fragment" "$fragment.codex-apocrita.$stamp.bak"
  cp "$CA_SSH_FRAGMENT_TMP" "$fragment"
  chmod 600 "$fragment"
  if [[ ! -f "$main" ]]; then
    printf '%s\n' "$include" > "$main"
  elif ! grep -Fqx "$include" "$main"; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-ssh.XXXXXX")
    { printf '%s\n\n' "$include"; cat "$main"; } > "$tmp"
    mv "$tmp" "$main"
  fi
  chmod 600 "$main"
}
