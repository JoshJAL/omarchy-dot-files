#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Route Omarchy's idle screensaver through ~/.local/bin/omarchy-launch-screensaver
# (which randomizes the artwork, then execs the real launcher).
#
# The idle service runs `bash -lc omarchy-launch-screensaver`. Omarchy 4.0.4's
# env-bootstrap APPENDS ~/.local/bin to PATH so system binaries keep precedence,
# so the packaged /usr/bin copy wins and a file in ~/.local/bin cannot shadow it.
# A function does win over PATH lookup, and login shells (bash -lc) read this
# file, so define one here instead of reordering PATH for everything.
omarchy-launch-screensaver() { "$HOME/.local/bin/omarchy-launch-screensaver" "$@"; }
