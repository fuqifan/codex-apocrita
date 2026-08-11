#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=$(cd -P "$(dirname "$0")" && pwd)
# shellcheck source=lib/common.sh
source "$SOURCE_ROOT/lib/common.sh"
source "$SOURCE_ROOT/lib/ssh-config.sh"
source "$SOURCE_ROOT/lib/codex-release.sh"
source "$SOURCE_ROOT/lib/remote-deploy.sh"

base_host=apocrita
ssh_alias=apocrita-codex
command_name=apo
endpoint=login.hpc.qmul.ac.uk
partition=compute
cpus=2
memory=8G
walltime=4:00:00
dry_run=0
skip_auth=0
install_mode=auto
from_config=''
preserve_profile=0
CA_ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Connection:
  --base-host NAME           Existing SSH alias to copy credentials from (apocrita)
  --ssh-alias NAME           New Codex Desktop alias (apocrita-codex)
  --endpoint login|vscode|HOST
  --command-name NAME        Installed local command (apo)

Default CPU profile:
  --partition NAME           Slurm partition (compute)
  --cpus N                   CPUs per task (2)
  --memory SIZE              Total memory (8G)
  --time DURATION            Wall time (4:00:00)

Behavior:
  --remote-install-mode auto|remote|upload
  --skip-auth                Do not run remote Codex device login
  --yes, --non-interactive   Accept defaults or supplied flags
  --dry-run                  Print the plan without changing files
  --from-config FILE         Reinstall/update using an existing config
  -h, --help

This installer never invokes sudo and never stores your SSH password.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-host) base_host="$2"; shift ;; --ssh-alias) ssh_alias="$2"; shift ;;
    --command-name) command_name="$2"; shift ;; --endpoint) endpoint="$2"; shift ;;
    --partition) partition="$2"; shift ;; --cpus) cpus="$2"; shift ;;
    --memory) memory="$2"; shift ;; --time) walltime="$2"; shift ;;
    --remote-install-mode) install_mode="$2"; shift ;; --skip-auth) skip_auth=1 ;;
    --yes|--non-interactive) CA_ASSUME_YES=1 ;; --dry-run) dry_run=1 ;;
    --from-config) from_config="$2"; shift ;;
    -h|--help) usage; exit ;; *) ca_die "Unknown option: $1" ;;
  esac
  shift
done

if [[ -n "$from_config" ]]; then
  ca_load_config "$from_config"
  base_host="$CA_BASE_HOST"; ssh_alias="$CA_SSH_ALIAS"; command_name="$CA_COMMAND_NAME"; endpoint="$CA_ENDPOINT"
  preserve_profile=1
fi

[[ "$(id -u)" -ne 0 ]] || ca_die 'Refusing to run as root. This installer is entirely user-local.'

case "$endpoint" in login) endpoint=login.hpc.qmul.ac.uk ;; vscode) endpoint=vscode.hpc.qmul.ac.uk ;; esac

prompt_value() {
  local label="$1" current="$2" explanation="$3" answer
  [[ "$CA_ASSUME_YES" == 1 ]] && { printf '%s\n' "$current"; return; }
  printf '\n%s\n%s\nValue [%s]: ' "$label" "$explanation" "$current" >&2
  IFS= read -r answer; printf '%s\n' "${answer:-$current}"
}

if [[ "$CA_ASSUME_YES" != 1 && -z "$from_config" ]]; then
  cat <<'EOF'
codex-apocrita setup

This creates a stable SSH name for Codex Desktop and runs its remote backend
inside a Slurm allocation. It does not SSH to compute nodes directly.
EOF
  base_host=$(prompt_value 'Existing SSH host' "$base_host" 'An alias already present in ~/.ssh/config. Its username and private-key settings will be copied.')
  ssh_alias=$(prompt_value 'Codex SSH alias' "$ssh_alias" 'This is the host name you will enable in Codex Desktop. You may choose another unused alias.')
  command_name=$(prompt_value 'Local command' "$command_name" 'This is the short terminal command used to start, inspect, and stop the allocation.')
  endpoint_choice=$(prompt_value 'Endpoint' login 'Choose login (recommended/stable), vscode (may tolerate more sessions but can lag under load), or enter a custom authorized login-compatible hostname. Never enter a compute node.')
  case "$endpoint_choice" in login) endpoint=login.hpc.qmul.ac.uk ;; vscode) endpoint=vscode.hpc.qmul.ac.uk ;; *) endpoint="$endpoint_choice" ;; esac
  partition=$(prompt_value 'CPU partition' "$partition" 'The default compute profile is only a sample; adjust it for your workflow.')
  cpus=$(prompt_value 'CPU count' "$cpus" 'Two CPUs are a lean default for the Codex backend and ordinary development tools.')
  memory=$(prompt_value 'Memory' "$memory" '8G is a lean default. Increase it for memory-intensive builds or analysis.')
  walltime=$(prompt_value 'Wall time' "$walltime" 'Four hours is a sample. Eight hours may fit a full working day better.')
fi

ca_validate_name "$base_host" || ca_die 'Invalid base SSH host name.'
ca_validate_name "$ssh_alias" || ca_die 'Invalid Codex SSH alias.'
ca_validate_name "$command_name" || ca_die 'Invalid command name.'
[[ "$endpoint" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || ca_die 'Invalid endpoint hostname.'
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || ca_die 'CPU count must be a positive integer.'
[[ "$memory" =~ ^[1-9][0-9]*([KMGT])?$ ]] || ca_die 'Memory must look like 8G.'
[[ "$walltime" =~ ^[0-9]+(-[0-9]+)?(:[0-9]{1,2}){1,2}$ ]] || ca_die 'Invalid Slurm time.'
[[ "$install_mode" == auto || "$install_mode" == remote || "$install_mode" == upload ]] || ca_die 'Invalid remote install mode.'
for dependency in bash ssh scp awk sed tar curl mktemp; do ca_require "$dependency"; done
ssh -G "$base_host" >/dev/null 2>&1 || ca_die "SSH host '$base_host' cannot be resolved."

CA_SSH_FRAGMENT_TMP=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-ssh.XXXXXX")
ca_render_ssh_fragment "$base_host" "$ssh_alias" "$endpoint" "$CA_SSH_FRAGMENT_TMP"

if [[ ! -f "$HOME/.ssh/codex-apocrita.conf" && -f "$HOME/.ssh/config" ]] &&
   awk -v wanted="$ssh_alias" '$1=="Host" {for(i=2;i<=NF;i++) if($i==wanted) found=1} END{exit !found}' "$HOME/.ssh/config"; then
  ca_die "SSH alias '$ssh_alias' already exists outside the managed fragment. Choose --ssh-alias NAME."
fi
cat <<EOF

Installation plan
  command:       $command_name
  SSH alias:     $ssh_alias
  endpoint:      $endpoint
  base identity: $base_host
  CPU profile:   $partition, $cpus CPUs, $memory, $walltime
  Codex install: $install_mode, user-local only
  authentication: $([[ "$skip_auth" == 1 ]] && echo skipped || echo device-code login)

No sudo command will be run. No SSH password or Codex token will be copied.
EOF

if [[ "$dry_run" == 1 ]]; then
  echo; echo 'Generated SSH fragment:'; cat "$CA_SSH_FRAGMENT_TMP"; rm -f "$CA_SSH_FRAGMENT_TMP"; exit
fi
ca_confirm 'Continue with installation?' || ca_die 'Installation cancelled.'

ca_install_ssh_include
rm -f "$CA_SSH_FRAGMENT_TMP"
ca_start_master "$ssh_alias"
ca_remote_install "$SOURCE_ROOT" "$ssh_alias" "$install_mode"

if [[ "$preserve_profile" != 1 ]]; then
  profile_tmp=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-profile.XXXXXX")
  cat > "$profile_tmp" <<EOF
JOB_NAME=codex-desktop
PARTITION=$partition
NODES=1
NTASKS=1
CPUS_PER_TASK=$cpus
MEM=$memory
TIME=$walltime
EOF
  scp -q "$profile_tmp" "$ssh_alias:.config/codex-apocrita/profiles/cpu.conf"
  rm -f "$profile_tmp"
fi

version=$(cat "$SOURCE_ROOT/VERSION")
data_root=$(ca_data_dir); config_root=$(ca_config_dir); release_dir="$data_root/releases/$version"
mkdir -p "$data_root/releases" "$config_root" "$HOME/.local/bin"
stage="$data_root/releases/.staging.$version.$$"; rm -rf "$stage"; mkdir -p "$stage"
for item in bin lib completions docs remote profiles README.md LICENSE VERSION install.sh uninstall.sh; do cp -R "$SOURCE_ROOT/$item" "$stage/"; done
chmod 755 "$stage/install.sh" "$stage/uninstall.sh" "$stage/bin/codex-apocrita" "$stage/remote/"*
rm -rf "$release_dir"; mv "$stage" "$release_dir"
[[ -L "$data_root/current" ]] && ln -sfn "$(readlink "$data_root/current")" "$data_root/previous"
ln -sfn "$release_dir" "$data_root/current"
command_path="$HOME/.local/bin/$command_name"
if [[ -e "$command_path" || -L "$command_path" ]] &&
   [[ ! -L "$command_path" || "$(readlink "$command_path")" != *codex-apocrita/current/bin/codex-apocrita ]]; then
  mv "$command_path" "$command_path.codex-apocrita.$(date +%Y%m%d-%H%M%S).bak"
fi
ln -sfn "$data_root/current/bin/codex-apocrita" "$command_path"

cat > "$config_root/config" <<EOF
SSH_ALIAS=$ssh_alias
BASE_HOST=$base_host
COMMAND_NAME=$command_name
ENDPOINT=$endpoint
SOURCE_DIR=$SOURCE_ROOT
EOF
chmod 600 "$config_root/config"

install_shell_block() {
  local file="$1" shell_kind="$2" begin='# >>> codex-apocrita >>>' end='# <<< codex-apocrita <<<' tmp
  touch "$file"
  cp -p "$file" "$file.codex-apocrita.$(date +%Y%m%d-%H%M%S).bak"
  tmp=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-shell.XXXXXX")
  awk -v begin="$begin" -v end="$end" '$0==begin{skip=1;next} $0==end{skip=0;next} !skip{print}' "$file" > "$tmp"
  mv "$tmp" "$file"
  cat >> "$file" <<'EOF'

# >>> codex-apocrita >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
# <<< codex-apocrita <<<
EOF
  if [[ "$shell_kind" == zsh ]]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/codex-apocrita-zsh.XXXXXX")
    awk '
      $0=="# <<< codex-apocrita <<<" {
        print "fpath=(\"$HOME/.local/share/zsh/site-functions\" $fpath)"
        print "autoload -Uz compinit"
        print "compinit"
      }
      {print}
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
}
case "${SHELL:-}" in */zsh) install_shell_block "$HOME/.zshrc" zsh ;; *) install_shell_block "$HOME/.bashrc" bash ;; esac

mkdir -p "$HOME/.local/share/zsh/site-functions" "$HOME/.local/share/bash-completion/completions"
sed "s/__APO_COMMAND__/$command_name/g" "$SOURCE_ROOT/completions/_apo" > "$HOME/.local/share/zsh/site-functions/_$command_name"
sed "s/__APO_COMMAND__/$command_name/g" "$SOURCE_ROOT/completions/apo.bash" > "$HOME/.local/share/bash-completion/completions/$command_name"

if [[ "$skip_auth" != 1 ]]; then
  if ! ssh -o BatchMode=yes "$ssh_alias" '$HOME/.local/bin/codex-direct login status' >/dev/null 2>&1; then
    ca_info 'Authenticate the remote Codex CLI with the displayed device code'
    ssh -t "$ssh_alias" '$HOME/.local/bin/codex-direct login --device-auth'
  fi
fi

cat <<EOF

Installation complete.

Open a new terminal (or export PATH="\$HOME/.local/bin:\$PATH"), then run:
  $command_name doctor
  $command_name

In Codex Desktop, open Settings > Connections and enable: $ssh_alias
EOF
