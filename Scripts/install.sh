#!/bin/zsh
# Installs Touchwire into ~/Applications and starts it as a LaunchAgent. It restarts if it crashes or is killed,
# but stays quit after Quit in its menu.
set -euo pipefail
cd "$(dirname "$0")/.."
LABEL=com.ggv.Touchwire
APP_DIR=~/Applications/Touchwire.app
PLIST=~/Library/LaunchAgents/$LABEL.plist
CONFIG_DIR=~/Library/Application\ Support/Touchwire

./Scripts/build.sh
mkdir -p "$CONFIG_DIR"
# Marks the stop as intended, so the protection service doesn't restart the app or lock the Mac. The app clears it.
touch "$CONFIG_DIR/quit-requested"
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
mkdir -p ~/Applications ~/Library/LaunchAgents "$CONFIG_DIR"
rm -rf "$APP_DIR"
cp -R build/Touchwire.app "$APP_DIR"

# A random ntfy topic works like a password: anyone who knows it can read the alerts.
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
  TOPIC="touchwire-$(openssl rand -hex 12)"
  cat > "$CONFIG_DIR/config.json" <<JSON
{
  "watchOnly": true,
  "ntfyServer": "https://ntfy.sh",
  "ntfyTopic": "$TOPIC",
  "rearmAfterIdleSeconds": 600,
  "notifyCooldownSeconds": 300,
  "disarmedReminderSeconds": 10800
}
JSON
  chmod 600 "$CONFIG_DIR/config.json"
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP_DIR/Contents/MacOS/Touchwire</string>
	</array>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "Installed and started $LABEL."
