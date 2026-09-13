#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# bun — kept for non-interactive login shells, where .bashrc returns early at
# its interactive guard and never reaches its own (guarded) bun prepend.
export BUN_INSTALL="$HOME/.bun"
case ":$PATH:" in *":$BUN_INSTALL/bin:"*) ;; *) export PATH="$BUN_INSTALL/bin:$PATH" ;; esac
