#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
label="com.$(id -un | tr -cd '[:alnum:]').spotify-refresh"
target="$HOME/Library/LaunchAgents/$label.plist"

sed -e "s|__REPO_PATH__|$root|g" -e "s|com.johncoote.spotify-refresh|$label|g" \
  "$root/setup/spotify-refresh.plist" > "$target"

plutil -lint "$target" > /dev/null
launchctl unload "$target" 2>/dev/null || true
launchctl load "$target"

echo "installed $label"
echo "runs Mondays 11:00, logs to $root/.refresh.log"
echo "trigger a test run with: launchctl start $label"
