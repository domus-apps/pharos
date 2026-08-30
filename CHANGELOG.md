# Changelog

All notable changes to Pharos are documented here. The release workflow publishes each version's section as the GitHub release notes and embeds it in the Sparkle appcast, so the in-app update dialog shows the same notes. A release fails early if its version has no section here.

Keep each bullet on a single line: release notes render line breaks literally (both on GitHub and in the update dialog), so wrapped lines would break mid-sentence.

## 1.1.2

### Added

- Spotlight now finds the app by its Korean name and by what it does — 파로스, 잠자기 방지, and keep awake all match.

## 1.1.1

- Fixed: installing by COPYING the app (instead of Finder-moving it) left it running from Gatekeeper's translocated read-only path, which blocked Sparkle updates — the app now detects this at launch, clears the quarantine flag, and relaunches itself from its real location.

## 1.1.0

### Added

- First-run onboarding that introduces the menu bar toggle and the timed presets.

## 1.0.0

- Initial release: keep your Mac awake from the menu bar — left-click the beacon to toggle, right-click for timed presets (from 15 minutes to 8 hours) with a live countdown.
- Optionally keep the display awake too (on by default — a dark, locked screen is indistinguishable from a sleeping Mac), toggleable while active.
- Choose the menu bar icon style (beacon, sun, eye, or coffee cup), hide the icon entirely, start keeping the Mac awake at launch, and launch at login.
- Sparkle keeps the app up to date.
