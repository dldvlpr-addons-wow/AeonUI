# MuscaUI 1.0.2

## Changes
- AeonUI is now MuscaUI. Your settings are carried over on first login. The chat command is now
  /musca (/aeon and /aeonui are gone). Remove the old AeonUI folders from Interface/AddOns before
  launching the game: with both installed, they share the same settings. Modules you had turned
  off in the AddOns list are enabled again under their new MuscaUI names.
- Setup assistant: five pages instead of eight. The Musca Auras class HUD is offered once, on the
  first page, with a single Import button: once you confirm the import, MuscaUI turns off its combat
  bars and places the HUD. Edit Mode, Cooldown Manager and recommended settings share one
  Advanced page.
- Setup assistant: closing it with Escape applies your module choices, like Finish. The summary
  has a Done and reload button.
- Reminders: hidden in combat. Out of combat they can take up to 0.3 s to appear, and a buff
  cast on a group member can take up to 10 s to leave the "members without" list.

## Fixes
- Action bars: mount and vehicle buttons now show as checked while you are mounted or in a vehicle.
- Action bars: Attack and Auto Shot buttons flash when you enter combat and while you auto-shoot.
- Loot: turning the module off no longer hides rolls in progress.

## Performance
- Less work per frame and per event across the whole UI: unit frames, resource bars, group frames,
  nameplates, action bars, bags, chat, minimap, quest tracker, alerts, reminders, swing timer,
  top bar, cooldown bars and icon skinning only update what changed.
- Settings backup is written out of combat only, after a change or every 60 seconds.

# MuscaUI 1.0.1

## Changes
- Quickdraw is now called Radial menu, and Shifter is now Movable windows. Your settings are kept.

# MuscaUI 1.0.0

## Split into separate addons
- MuscaUI is now a core addon plus eight parts, listed under MuscaUI in the game's AddOns list:
  Bags (bags, bank), Action Bars, Unit Frames (unit frames, resource bars), Group Frames
  (group frames, click casting), Nameplates, Chat (chat, bubbles), Minimap, Quest Tracker.
- Untick a part to use another addon instead (for example Bags for Bagnator), then `/reload`.
  Its settings are kept for when you tick it again.
- Install every folder of the zip in `Interface/AddOns`. The CurseForge app does it for you.
- ForeverMeter (damage meter) is now a required dependency: the CurseForge app installs it with MuscaUI.

## New
- Class profiles: one profile per way to play your class (setup assistant, Profiles page,
  `/musca install class <style>`), with the role layout plus resources, swing timer, cast bar,
  pet, totems, forms and reminders set for that style.
- Installing a profile that already exists asks: reinstall it, or switch to it keeping your settings.
- Chat: main window on the left, detached loot / trade window on the right, each movable and
  resizable, with a button to rearrange the windows.
- Options: simple and advanced modes (advanced settings hidden in simple mode, still found by search).
- Nameplates: shown on friendly NPCs, pets and guardians, with a range setting (up to 60 yards,
  the game's limit). This setting replaces the nameplate range option of the setup assistant.
- Nameplates: option to hide Blizzard floating names on NPCs, pets, guardians and totems.

## Fixes
- Reminders: no more `ADDON_ACTION_BLOCKED` on the reminder frame in combat.
- Reminders: the cast icon no longer comes back after the missing buff is cast.
- Reminders: turning the module off in combat now waits for the end of combat.
- Nameplate and group frame previews use their own example icons.
- Action bars: no more `ADDON_ACTION_BLOCKED` when hovering a button in combat.
- Action bars: dragging spells onto or off a button no longer raises `ADDON_ACTION_BLOCKED`.
- Action bars: icons no longer all turn grey during the global cooldown.
- Fonts: Korean, Chinese and Russian characters no longer show as squares with MuscaUI fonts.
