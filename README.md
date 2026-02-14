# EbonholdBarBuilder

Action bar layout manager for World of Warcraft 3.3.5a (WotLK), built for **Project Ebonhold**.

**Version:** 0.5.4

## What it does

On Project Ebonhold, dying resets your character back to Level 1 while keeping overall progression. EbonholdBarBuilder saves your action bar layouts and automatically restores them as you level back up, so you never have to manually rebuild your bars after a death reset.

## Features

- **Master Layout** — Your highest-level layout is the single source of truth. During reruns (leveling back up after death), bars are restored from the master at every level-up.
- **Master Sync** — Bar changes made during reruns are detected and propagated back to the master layout, keeping it up to date.
  - **Synced:** Moving, swapping, and placing spells, items, macros, companions, and equipment sets. Removing macros, companions, or equipment sets (always available at any level, so removal is intentional).
  - **Not synced:** Removing spells or items from slots — these are ignored because you may not have learned the spell or looted the item yet at your current level.
- **Death Reset Handling** — Automatically detects the level 80 → 1 reset, preserves your high-level layout, and restores Level 1 bars if available.
- **Combat-Safe Restore** — If you level up during combat, the restore is deferred until combat ends.
- **Explorer UI** — Visual bar explorer showing all 10 action bars with keybindings, macro names, and per-slot inspection. Includes restore button and master sync toggle.
- **Multi-Spec Support** — Up to 5 spec profiles with independent layouts, integrated with Project Ebonhold's spec system.
- **Verify Pass** — After every restore, slots are re-checked and corrected for server overrides (e.g. auto-placed spells).

## Installation

1. Download or clone this repository.
2. Copy the `EbonholdBarBuilder` folder into your WoW `Interface/AddOns/` directory.
3. Restart WoW or reload the UI (`/reload`).

On first login, a dialog will ask whether to enable the addon for that character.

## Usage

All commands use the `/ebb` prefix:

| Command | Description |
|---------|-------------|
| `/ebb` | Show help |
| `/ebb ui` | Open the Explorer configuration panel |
| `/ebb save` | Save current action bars for your level |
| `/ebb restore` | Restore saved layout for your level |
| `/ebb status` | Show current spec, level, and layout info |
| `/ebb list` | List all saved layouts for the active spec |
| `/ebb specs` | Show all specs with layout counts |
| `/ebb clear` | Clear all layouts for the active spec |
| `/ebb enable` | Re-show the first-run enable/disable dialog |
| `/ebb debug` | Toggle debug mode |

## How it works

1. **Capture** — When action bar slots change, the addon waits briefly for further changes to settle, then takes a snapshot of all enabled slots.
2. **Save** — On first-time leveling, the snapshot is saved as a per-level layout. Only the highest level (master) is kept; lower layouts are pruned.
3. **Restore** — On level-up during a rerun, the master layout is restored: spells, items, macros, companions, and equipment sets are placed back on bars.
4. **Sync** — During reruns, any bar changes you make are diffed against a baseline snapshot and applied back to the master layout, so your master stays current.
5. **Verify** — After each restore, a verify pass corrects any slots where the server overrode the addon's placement.

## Architecture

All modules share state through the `EBB` addon table. Each file creates a subtable (e.g. `EBB.Capture`). Per-character data is stored in `EBB_CharDB` (SavedVariables).

| File | Responsibility |
|------|---------------|
| `Utils.lua` | Chat output, `DeepCopy`, `C_Timer` compatibility shim |
| `Settings.lua` | Constants (version, timing, slot counts), per-character settings |
| `ActionBar.lua` | WoW API wrapper: slot info, tooltip scanning, stance detection |
| `ClassBars.lua` | Class-specific bar configuration (stance bar mapping) |
| `Profile.lua` | Per-spec enabled slots and settings, 5 spec slots |
| `Layout.lua` | Per-level snapshot storage, dual storage (permanent + session), `SyncToMaster()` |
| `Capture.lua` | Snapshot creation, debounced scheduling, rerun-aware save/sync |
| `Restore.lua` | Slot restoration (spells, items, macros, companions), verify pass |
| `Spec.lua` | Spec system integration (Project Ebonhold + fallback) |
| `Core.lua` | Entry point: events, initialization, level-up/death handling, migrations |
| `MinimapButton.lua` | Minimap button with tooltip |
| `uiExplorer.lua` / `Explorer.lua` | Explorer UI creation / behavior |
| `uiFirstRun.lua` / `FirstRun.lua` | First-run dialog UI / behavior |

## Credits

Originally created by **supertuesday**. Forked and extended by **CiD1337**.
