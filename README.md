# Touchwire

Keeps an always-unlocked Mac mini safe enough to leave unlocked for remote agents. It locks the Mac and sends a push
notification when someone touches it physically, and stays out of the way of software input (cua-driver, Screen Sharing).

## States

- **Armed:** physical keyboard or mouse input, a new USB, HID or Thunderbolt device, or an unknown display trips it.
- **Tripped:** the Mac is locked. Unlocking at the Mac disarms it; unlocking through Screen Sharing (detected by its `screensharingd` and `ScreensharingAgent` processes) re-arms it.
- **Disarmed:** you're at the Mac. It re-arms after `rearmAfterIdleSeconds` without physical input, when the devices
  you plugged in are unplugged, or from the menu. It reminds you after `disarmedReminderSeconds`.

A device or display is unknown when it isn't in the saved setup. **Save Current Setup as Normal** in the menu saves
everything attached at that moment to `setup.json`. Until then, whatever was attached when Touchwire started counts.
The **Devices** submenu lists the normal setup (checked when attached) and what is attached but not saved.

`watchOnly: true` (the default) logs and notifies "would lock" without locking, to check the triggers first.

## Install

```sh
./Scripts/install.sh           # builds, installs to ~/Applications and starts the LaunchAgent
```

Then allow Touchwire in System Settings → Privacy & Security → Input Monitoring, and subscribe to the `ntfyTopic` from
`~/Library/Application Support/Touchwire/config.json` in the [ntfy app](https://ntfy.sh/). Use **Reload Config** in the
menu after editing the config.

## Files

- Config: `~/Library/Application Support/Touchwire/config.json`
- Saved setup: `~/Library/Application Support/Touchwire/setup.json`
- Log: `~/Library/Logs/Touchwire/events.jsonl` (one JSON event per line)
