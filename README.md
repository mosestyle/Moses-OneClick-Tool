# Moses OneClick Tool V7.2.3

Moses OneClick Tool installs Windows games on SteamOS with Steam / Proton as the default backend, plus Smart Automatic / Lutris for games that need a Lutris recipe.

## V7.2.3 — stronger game-name cleanup + unified prefix view

### Find Game EXE name cleanup

The Dolphin context-menu actions **Find Game EXE + Install** and **Find Game EXE + Add to Steam** now use the same conservative title-cleanup rules as direct EXE handling.

Release/package suffixes such as these no longer become part of the game name when a cleaner game folder exists:

- `(incl. Update 5)` / `(incl Update 5)` / `[Update 5]`
- `including Update ...`
- `Patch ...`, `Hotfix ...`, `Upgrade ...`
- `(build 38862)`, `Build 38862`, revision/build suffixes
- common repack/release/platform suffixes already handled by earlier builds

Example:

```text
DuckTales Remastered (incl. Update 5)/DuckTales Remastered/setup.exe
```

is suggested as:

```text
DuckTales Remastered
```

The game-name field remains editable before continuing.

### Real named internal prefix root

Steam/Proton itself still needs the numeric `steamapps/compatdata/<AppID>` path. Removing that numeric path would break Proton, so V7.2.3 keeps it only as an internal compatibility symlink.

The **real** OneClick-owned internal prefix directories are now stored in a clean user-facing root:

```text
~/.local/share/oneclick-exe/game-prefixes/Steam-Proton/
├── DuckTales Remastered/
├── Hades II/
└── Core Keeper/
```

Steam may internally keep:

```text
steamapps/compatdata/3777682817 -> .../DuckTales Remastered
steamapps/compatdata/3676948235 -> .../Hades II
```

but **Open All Game Prefixes no longer opens raw Steam compatdata**, so those numeric compatibility links are kept out of the user-facing folder view.

Existing OneClick-owned internal named prefixes from V7.1.7-V7.2.1 are migrated to the new clean internal root when **Open All Game Prefixes** is used or when the game is prepared again. Non-OneClick Steam prefixes are never moved.

### External prefixes

External Steam/Proton prefixes remain real folders on the external drive:

```text
<external drive>/OneClick Games/Steam-Proton/Core Keeper/
<external drive>/OneClick Games/Steam-Proton/Braid Anniversary Edition/
```

**Open All Game Prefixes** now shows internal and external Steam/Proton games together in one clean game-name view. Internal entries remain the real prefix directories. External entries are game-named symlinks that point to the real prefix directory on the UUID-tracked removable drive.

For example:

```text
~/.local/share/oneclick-exe/game-prefixes/Steam-Proton/
├── DuckTales Remastered/          # real internal prefix
├── Hades II/                      # real internal prefix
├── Core Keeper -> <external>/OneClick Games/Steam-Proton/Core Keeper
└── Braid Anniversary Edition -> <external>/OneClick Games/Steam-Proton/Braid Anniversary Edition
```

Deleting an external display symlink does **not** delete the game bytes on the removable drive; OneClick recreates known links when the prefix view is opened again. Complete Game Removal remains the correct way to remove the full game/prefix/Steam integration.

## V7.2.1 — Smart/Lutris installer session cleanup

- Temporary Lutris installer sessions started by OneClick are cleaned up after Smart installation/validation.
- A Lutris session that was already open before installation is left untouched.
- Detached post-install workers no longer remain grouped as the visible **Moses OneClick Tool - Game Installer** application.

## V7.2.0 — English / Svenska

Settings -> About includes a Language selector. English is the default. Choosing Svenska translates the main UI, Settings, installer/action dialogs, and common confirmation/error/status messages while technical names such as Steam, Proton, Lutris, DXVK and SteamGridDB remain unchanged.

## Existing features

- Steam / Proton is the default installer backend.
- Smart Automatic / Lutris can discover and rank Lutris recipes, resolve known runtime requirements, and apply post-install fixes.
- Internal and external game storage support.
- UUID-based reconnect handling for external drives.
- External-drive formatting helpers for Btrfs, ext4 and NTFS with explicit destructive confirmation and drive labels.
- Btrfs Space Saver for approved Proton/Wine prefix locations.
- SteamGridDB + Steam artwork sources (`Both` is default).
- Main-EXE reselection for installations where the EXE chooser was needed.
- Complete Game Removal cleans managed game state, Steam shortcut, artwork, compatibility mapping and reachable game/prefix data.
- External-drive removal warning when game data is stored on disconnected media.
- Settings tabs: General, Storage and About.
