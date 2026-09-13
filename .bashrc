# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
# /etc/omarchy.conf is written by omarchy-dev-link. When absent, force the
# package default instead of preserving a stale inherited dev-link value before
# we decide which rc file to source.
if [[ -f /etc/omarchy.conf ]]; then
  source /etc/omarchy.conf
  export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
else
  export OMARCHY_PATH=/usr/share/omarchy
fi
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'
#
# Local secrets (API keys). Untracked, mode 600 — see ~/.config/secrets.env
[ -r "$HOME/.config/secrets.env" ] && . "$HOME/.config/secrets.env"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

SCREENSAVERS=(~/.config/omarchy/branding/screensavers/*.txt)
cp "${SCREENSAVERS[RANDOM % ${#SCREENSAVERS[@]}]}" ~/.config/omarchy/branding/about.txt
fastfetch
export PATH="/usr/local/bin:$PATH"

# Turso
export PATH="$PATH:/home/joshjal/.turso"

# Bare dotfiles repo (work-tree = $HOME). See ~/README.md
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# mise: never hold back a release for being "too new".
# mise's minimum_release_age defaults to 24h (supply-chain gate, matches pnpm v11).
# ~/.config/mise/config.toml already sets it to 0; this env var also beats any
# project mise.toml or /etc/mise/conf.d drop-in that tries to re-impose it.
export MISE_MINIMUM_RELEASE_AGE=0
