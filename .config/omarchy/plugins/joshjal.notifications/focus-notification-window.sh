#!/bin/bash
# Focus the window a notification came from: switch to its workspace, focus it,
# and if it is a hidden tab in a Hyprland group, bring that tab to the front.
#
# Usage: focus-notification-window.sh <app-name> [notification-body]
#
# Chromium-based apps (Helium webapps like Teams) all report the same app name,
# so the body's origin link (<a href="https://teams.microsoft.com/">) is the
# only thing telling them apart. It maps to the webapp window class
# chrome-<host>__<path>-Default. Anything else falls back to the same class
# match omarchy-hyprland-focus-app uses.

app=${1:-}
body=${2:-}
[[ -n $app || -n $body ]] || exit 1

clients=$(hyprctl clients -j 2>/dev/null) || exit 1

host=$(grep -oE 'href="https?://[^/"]+' <<<"$body" | head -n1 | sed -E 's|.*://||')

address=
if [[ -n $host ]]; then
  address=$(jq -r --arg prefix "chrome-$host" \
    'first(.[] | select((.class // "") | startswith($prefix))).address // empty' <<<"$clients")
fi

if [[ -z $address && -n $app ]]; then
  address=$(jq -r --arg pattern "$app" \
    'def matches($value): ($value // "") | test($pattern; "i");
     first(
       (.[] | select(matches(.class))),
       (.[] | select(.initialClass == "org.omarchy.agent" and matches(.initialTitle)))
     ).address // empty' <<<"$clients")
fi

[[ -n $address ]] || exit 0

focus() {
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
}

focus "$address"

# focus alone may leave a hidden group tab hidden. Cycle until it is visible,
# at most once around the group.
size=$(jq -r --arg a "$address" '.[] | select(.address == $a) | .grouped | length' <<<"$clients")
for ((i = 0; i < ${size:-0}; i++)); do
  visible=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$address" '.[] | select(.address == $a) | .visible')
  [[ $visible == true ]] && break
  hyprctl dispatch "hl.dsp.group.next()" >/dev/null 2>&1
done
