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

Watch-only is the default: triggers notify you without locking. Turn on **Lock the Mac when triggered** in Settings.
With **Block the physical input that triggers it** (needs Accessibility), that first keystroke or click is dropped before
any app sees it, until the lock screen is up. Physical input at the lock screen is never blocked, and only sends an
alert, since typing the password there is how you disarm it.

## Settings

**Settings…** in the menu (⌘,) edits everything, saved to `config.json` and applied at once: locking, input blocking,
re-arm and reminder times, the ntfy server and topic, permissions, the protection service and logging.

## Protection service

An optional root LaunchDaemon (`Touchwire --daemon`), installed from Settings after macOS asks for an administrator
password. Settings also shows the exact commands. It runs a root-owned copy of the app from
`/Library/PrivilegedHelperTools`, and:

- alerts on unknown devices while the app isn't running;
- restarts the app if it stops without **Quit Touchwire** (which leaves a `quit-requested` marker);
- locks the Mac (when locking is on) if the app is still missing 30 seconds later.

After rebuilding the app, Settings shows "Running an older version"; click **Update…**.

## Install

Download `Touchwire-<version>.dmg` from [Releases](https://github.com/gilitos92/Touchwire/releases) and drag Touchwire
into Applications. It needs macOS 26 or later.

Touchwire is self-signed, not notarized by Apple, so macOS blocks the first launch. Open it once, then go to
System Settings → Privacy & Security, click **Open Anyway** next to the Touchwire message, and confirm.

Then open **Settings…** from the menu bar icon and:

1. Turn on **Start at login and keep running**.
2. Grant **Input Monitoring**, and **Accessibility** to block input, then click **Restart Input Watch**.
3. Set an ntfy topic (or click **New Random Topic**) and follow it in the [ntfy app](https://ntfy.sh/).
4. Click **Save Current Setup as Normal** in the menu with only your own devices attached.
5. Optionally install the **Protection Service**.
6. When the alerts look right, turn on **Lock the Mac when triggered**.

## Development

```sh
./Scripts/install.sh           # builds, installs to ~/Applications and starts the LaunchAgent
```

Releases: tag `vX.Y.Z` on `main`, push the tag, then run `./Scripts/publish-release.sh`. It builds from the tag, signs
with `GGV`, and publishes a zip and DMG with the changelog section as notes.

## Files

- Config: `~/Library/Application Support/Touchwire/config.json`
- Saved setup: `~/Library/Application Support/Touchwire/setup.json`
- Log: `~/Library/Logs/Touchwire/events.jsonl` (one JSON event per line); the service logs to
  `/Library/Logs/Touchwire/daemon.jsonl`
