# Changelog

User-facing release notes. **The topmost `##` section is embedded in the in-app
update dialog** (Sparkle shows it to people when they update), so write each entry
for users, not developers. Add a new `## <version>` section at the top before you
tag a release.

## 1.2.0
- During a trial pause, SharePad now shows a live countdown in the share window
  and popover, so you know exactly when sharing resumes.
- You can now add your licence directly from the trial-pause message — no need to
  hunt through the menu.
- Your free trial is now remembered per Mac, so switching between iPads no longer
  resets it.
- Clearer popover guidance while the iPad is connecting or waking, and gentler
  feedback if it disconnects mid-session.

## 1.1.0
- SharePad now has a 7-day free trial. After it ends, sharing pauses briefly each
  session until you add a licence — a one-time £6.99 purchase that works offline,
  with no account.
- Already bought SharePad? You won't be charged again. In the menu bar choose
  "Enter licence…", then "Lost your key?" to fetch your key with your purchase
  email, and paste it in — the pause is gone for good.

## 1.0.6
- The in-app About panel now links to sharepad.co for buying and support, with
  quick "View Source" and "View Licence" links.
- Maintenance: internal reliability and release-pipeline improvements.

## 1.0.5
- If your iPad disconnects while you're sharing, SharePad now tells you: a
  brief alert appears in the menu-bar icon and the popover so you're not left
  wondering why your share went black.
- Privacy: only the iPad feed window can be picked in a video call's window
  picker. Other SharePad surfaces (the About panel, update dialogs) can't be
  shared by mistake.
- Smoother handling of edge cases: a stalled iPad start now surfaces honestly
  instead of looking live, and Camera-blocked-by-policy users see honest copy
  instead of a Settings button they can't use.

## 1.0.4
- Show or hide the share window from anywhere with a global keyboard shortcut
  (⌃⌥⌘H), no need to leave your call to reach the menu bar.
- Fix: the iPad now connects automatically the first time you plug it in, even
  while macOS is still settling the camera-permission and trust prompts.

## 1.0.3
- Maintenance release: security and code-signing updates behind the scenes. No
  changes to how SharePad works.

## 1.0.1
- Auto-update: SharePad now updates itself, and tells you what's new.

## 1.0.0
- First release. Plug in a USB-connected iPad and it appears as a clean,
  aspect-locked, always-ready window you can share in any video call, no more
  per-call QuickTime setup.
