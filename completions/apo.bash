___APO_COMMAND___completion() {
  local current previous
  current="${COMP_WORDS[COMP_CWORD]}"
  previous="${COMP_WORDS[COMP_CWORD-1]}"
  if [[ "$COMP_CWORD" -eq 1 ]]; then
    COMPREPLY=( $(compgen -W 'start cpu switch status stop off config ssh doctor logs clean update rollback uninstall help' -- "$current") )
  elif [[ "${COMP_WORDS[1]}" == config && "$COMP_CWORD" -eq 2 ]]; then
    COMPREPLY=( $(compgen -W 'list show create set delete' -- "$current") )
  elif [[ "${COMP_WORDS[1]}" == ssh ]]; then
    COMPREPLY=( $(compgen -W 'start status force off' -- "$current") )
  elif [[ "$previous" == start || "$previous" == switch || "$previous" == show || "$previous" == set || "$previous" == delete ]]; then
    COMPREPLY=( $(compgen -W "$(__APO_COMMAND__ config list 2>/dev/null | awk 'NR>1 {print $1}')" -- "$current") )
  fi
}
complete -F ___APO_COMMAND___completion __APO_COMMAND__
