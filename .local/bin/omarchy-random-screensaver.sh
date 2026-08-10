#!/bin/bash

SCREENSAVER_DIR="$HOME/.config/omarchy/branding/screensavers"
SCREENSAVER_TARGET="$HOME/.config/omarchy/branding/screensaver.txt"

# Pick a random .txt file from the directory
files=("$SCREENSAVER_DIR"/*.txt)

if [[ ${#files[@]} -eq 0 ]]; then
    # No custom files, just launch normally
    omarchy-launch-screensaver "$@"
    exit
fi

random_file="${files[RANDOM % ${#files[@]}]}"
cp "$random_file" "$SCREENSAVER_TARGET"

omarchy-launch-screensaver "$@"
