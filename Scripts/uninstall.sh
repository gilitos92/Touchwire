#!/bin/zsh
# Stops Touchwire and removes the app and LaunchAgent. Keeps the config and logs.
set -euo pipefail
LABEL=com.ggv.Touchwire
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
rm -f ~/Library/LaunchAgents/$LABEL.plist
rm -rf ~/Applications/Touchwire.app
echo "Uninstalled. Config and logs are in ~/Library/Application Support/Touchwire and ~/Library/Logs/Touchwire."
