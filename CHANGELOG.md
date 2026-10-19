# Changelog

All notable changes to Touchwire are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-10-18

### Added

- An app icon in the Liquid Glass style, made with Icon Composer. It follows the light, dark, clear and tinted icon
  appearances.
- A license: GPL 3.0, with an added term that keeps the name and icon for the original project.

## [1.1.0] - 2026-10-18

### Added

- Automatic updates through [Sparkle](https://sparkle-project.org/): **Check for Updates…** in the menu, and
  **Check for updates automatically** and the app version in Settings. Updates are verified with an EdDSA signature.
- A copy opened outside the login agent (after an update, or by double-clicking) hands over to the agent, so Touchwire
  keeps restarting after crashes.

### Fixed

- The release script's signature check, which failed on every build.

## [1.0.0] - 2026-10-18

### Added

- Menu bar app that keeps an always-unlocked Mac safe: physical keyboard or mouse input, a device that isn't in the
  saved setup, or an unknown display trips it.
- Armed, Tripped and Disarmed states. Unlocking at the Mac disarms it; unlocking through Screen Sharing keeps it armed.
  It re-arms after a set time without physical input, when added devices are unplugged, or from the menu.
- Physical input is told apart from Screen Sharing and automation tools by the event's source process.
- Watch-only mode (the default) that notifies without locking.
- Blocking of the physical keystroke or click that trips it, until the lock screen is up (needs Accessibility).
- Push notifications through ntfy, with a per-trigger cooldown and a reminder while disarmed.
- **Save Current Setup as Normal**, and a **Devices** submenu listing saved and unsaved devices and displays.
- Settings window for locking, input blocking, timings, ntfy, permissions, Start at Login, logging and the protection
  service.
- Optional root protection service that watches devices while the app isn't running, restarts the app if it stops
  without Quit, and locks the Mac if it doesn't come back.
- JSON event log, which can be turned off.

[Unreleased]: https://github.com/gilitos92/Touchwire/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/gilitos92/Touchwire/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/gilitos92/Touchwire/releases/tag/v1.0.0
