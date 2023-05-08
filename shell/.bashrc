# Avoid duplicates
HISTCONTROL=ignoredups:erasedups

export HISTSIZE=100000                   # big big history
export HISTFILESIZE=100000               # big big history

# When the shell exits, append to the history file instead of overwriting it
shopt -s histappend

# After each command, append to the history file and reread it
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"


complete -W "$(echo $(grep -E '(^[psgm]ssh |^ssh )' ~/.bash_history | sort -u | sed 's/^.*ssh //'))" sssh

complete -W "$(echo $(grep -E '(^[psgm]ssh |^ssh )' ~/.bash_history | sort -u | sed 's/^.*ssh //'))" pssh

complete -W "$(echo $(grep -E '(^[psgm]ssh |^ssh )' ~/.bash_history | sort -u | sed 's/^.*ssh //'))" gssh

complete -W "$(echo $(grep -E '(^[psgm]ssh |^ssh )' ~/.bash_history | sort -u | sed 's/^.*ssh //'))" mssh
