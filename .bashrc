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

# Point at the systemd-managed user ssh-agent (ssh-agent.socket): one agent per
# login session, socket-activated, cleaned up on logout. Keys load lazily on
# first use via AddKeysToAgent in ~/.ssh/config.
#
# Fills a gap, never overrides: skipped if something already exported
# SSH_AUTH_SOCK (1Password, gnome-keyring, a forwarded agent) and skipped if the
# socket isn't there, so a machine without the unit keeps whatever it already
# uses instead of getting a dead path.
if [ -z "$SSH_AUTH_SOCK" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$UID}/ssh-agent.socket" ]; then
  export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/ssh-agent.socket"
fi

export BUN_INSTALL="$HOME/.bun"
# Guarded: .bash_profile sources this file, so an unguarded prepend landed in
# PATH twice for login shells.
case ":$PATH:" in *":$BUN_INSTALL/bin:"*) ;; *) export PATH="$BUN_INSTALL/bin:$PATH" ;; esac

SCREENSAVERS=(~/.config/omarchy/branding/screensavers/*.txt)
cp "${SCREENSAVERS[RANDOM % ${#SCREENSAVERS[@]}]}" ~/.config/omarchy/branding/about.txt
fastfetch

# Turso
export PATH="$PATH:/home/joshjal/.turso"

# Bare dotfiles repo (work-tree = $HOME). See ~/README.md
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
# ~/.gitignore is deny-by-default, so tracking a NEW file needs -f. Already-tracked
# files are unaffected by gitignore and keep working with plain `dotfiles add`.
alias dotfiles-track='git --git-dir=$HOME/.dotfiles --work-tree=$HOME add -f'
alias agentfiles='git --git-dir=$HOME/.agentfiles --work-tree=$HOME'
alias agentfiles-track='git --git-dir=$HOME/.agentfiles --work-tree=$HOME add -f'

# mise: never hold back a release for being "too new".
# mise's minimum_release_age defaults to 24h (supply-chain gate, matches pnpm v11).
# ~/.config/mise/config.toml already sets it to 0; this env var also beats any
# project mise.toml or /etc/mise/conf.d drop-in that tries to re-impose it.
export MISE_MINIMUM_RELEASE_AGE=0
