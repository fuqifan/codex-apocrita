___APO_COMMAND___completion() {
  local current previous
  current="${COMP_WORDS[COMP_CWORD]}"
  previous="${COMP_WORDS[COMP_CWORD-1]}"
  if [[ "$COMP_CWORD" -eq 1 ]]; then
    COMPREPLY=( $(compgen -W 'start cpu switch force restart status stop off config ssh doctor test-prompt logs clean update rollback uninstall help -h --help' -- "$current") )
  elif [[ "${COMP_WORDS[1]}" == config && "$COMP_CWORD" -eq 2 ]]; then
    COMPREPLY=( $(compgen -W 'list show create set delete' -- "$current") )
  elif [[ "${COMP_WORDS[1]}" == ssh ]]; then
    COMPREPLY=( $(compgen -W 'start status force off' -- "$current") )
  elif [[ "${COMP_WORDS[1]}" == config && "${COMP_WORDS[2]}" == set && "$COMP_CWORD" -ge 4 ]]; then
    COMPREPLY=( $(compgen -W 'JOB_NAME= PARTITION= ACCOUNT= CONSTRAINT= GRES= NODES= NTASKS= CPUS_PER_TASK= CPUS_PER_GPU= MEM= MEM_PER_CPU= TIME=' -- "$current") )
  elif [[ "$previous" == start || "$previous" == switch || "$previous" == restart || "$previous" == show || "$previous" == set || "$previous" == delete || "${COMP_WORDS[1]}" == test-prompt ]]; then
    COMPREPLY=( $(compgen -W "$(__APO_COMMAND__ __complete profiles 2>/dev/null)" -- "$current") )
  fi
}
complete -F ___APO_COMMAND___completion __APO_COMMAND__
