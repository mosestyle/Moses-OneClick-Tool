# Moses OneClick Tool

**Install, move, launch and manage Windows games on SteamOS from one place.**

Moses OneClick Tool integrates with KDE Dolphin and Steam to make it easier to use Windows `.exe` games on SteamOS. It uses **Steam + Proton by default**, with an optional **Smart Automatic / Lutris** installation mode for games that need extra compatibility support.

![Moses OneClick Tool](https://github.com/user-attachments/assets/49f695dc-24c1-4582-91dc-03bf8364a71a)

## Features

### Install and add games

- **Install a new game:** double-click a Windows setup `.exe`, open an installer `.iso`, or use **Install Game** in Moses.
- **Steam / Proton:** install each game into a managed Proton environment and create a non-Steam shortcut for Desktop Mode and Gaming Mode.
- **Smart Automatic / Lutris:** use the optional Lutris workflow for titles needing additional compatibility assistance.
- **Add an existing game:** find its main `.exe` and add it to Steam without reinstalling the game.
- **Install updates, patches, DLC and mods:** run them inside the selected game's existing Proton or Wine environment. Supported update chains can run in sequence.
- **Game Tools:** launch configuration utilities, mod managers and other EXEs with the same game's compatibility environment, without changing its main Steam shortcut.
- **ISO installers:** mount installer ISO images read-only, run setup, then unmount them when finished.

### Move games and manage storage

- **Move to Game Folder + Add to Steam:** move a complete game folder into Moses's internal game storage and register it in Steam.
- **Move to External Drive + Add to Steam:** select a connected external drive, transfer the game, monitor progress and elapsed time, and register its Steam shortcut. The original game folder is removed automatically after a successful, verified move.
- **External-drive reconnection:** Moses identifies supported external game drives by filesystem UUID, helping Steam find games when the same drive is unplugged and reconnected. The drive must be mounted to play a game stored on it.
- **Drive preparation:** use the storage tools to choose a drive and manage supported filesystems and formatting. Formatting erases data and requires explicit confirmation.
- **Btrfs Space Saver:** reduce duplicate storage in supported Proton/Wine prefix locations.
- **Open game folders and saves:** browse a selected game's files, Windows Documents directory and likely save-game locations.

### Steam library and artwork

- Automatically create and verify Steam shortcuts for supported game workflows.
- **Play Game**, **Repair Steam Shortcut** and **Restart Steam** from the main window.
- **Edit games:** change the display name or select another main game EXE without reinstalling the game.
- **Automatic artwork:** fetch capsule, wide capsule, hero, logo and icon images from Steam and/or SteamGridDB.
- **Search Artwork Match:** manually find the right Steam game when automatic matching fails. **Use Selected Game** can also update the game's displayed name in Moses and Steam to the selected official title.
- **Download + Apply All Artworks** for selected games. Previously downloaded artwork is cached where possible.
- **Complete Game Removal:** remove a managed game, its Steam shortcut, artwork and associated managed files. External game removal checks drive availability; review any removal confirmation before proceeding.

### Dependencies and compatibility

- **Install / Repair Dependencies:** inspect and choose optional Windows redistributables for a selected game. Nothing is automatically installed by this feature.
- Supports common **Visual C++**, **DirectX**, **PhysX**, **OpenAL**, **XNA**, **.NET** and **VulkanRT** packages, including supported `.exe`, `.msi` and component ZIP formats.
- **Dependency Library:** download the official dependency set, import ZIP files or download compatible packs from GitHub, even if no game is selected.
- Redistributable installers are cached for reuse under `~/.local/share/oneclick-exe/runtime-cache/`.
- The VulkanRT component ZIP is downloaded from the Moses OneClick Tool repository's `Tools` folder.

### Additional tools

- **StreamExtract:** download and extract compatible ZIP, RAR and 7z archives, including supported multipart and multi-link jobs, then continue into the normal game installation flow.
- **TempOverlay:** a compact, always-on-top temperature monitor.
- **MangoHud Level 2:** on the first installation, Moses configures its custom Level 2 performance overlay preset. In **Settings → General**, use **Restore Stock Preset** or **Apply Moses Preset** to switch between stock and the Moses layout. Later Moses updates leave your chosen configuration alone.
- **Language:** English or Swedish.

## Requirements

- **SteamOS with KDE Plasma** and **Steam**.
- **Proton Experimental** available in Steam for the default Steam / Proton installation workflow.
- **Lutris (Flatpak, available from Discover)** for the optional Smart Automatic / Lutris mode.
- **Python 3** and its `venv` module for the integrated StreamExtract and TempOverlay tools.
- An internet connection for artwork, optional dependency downloads and the first setup of integrated Python-based tools.
- A **SteamGridDB API key** is optional for community artwork.

## Installation

1. Download and extract the Moses OneClick Tool ZIP.
2. Open **Konsole** inside the extracted folder.
3. Run:

   ```bash
   bash Moses_OneClick_Tool_Setup_V7.4.113.sh
   ```

4. Close and reopen **Dolphin** so the new context-menu actions appear.
5. Open **Moses OneClick Tool** from the application launcher, or right-click a supported file or game folder in Dolphin.

**Upgrading:** Run the new setup script over your existing installation. There is no need to uninstall Moses first.

## Quick start

| What you want to do | How |
| --- | --- |
| Install a Windows game | Open its installer `.exe` or `.iso`, or choose **Install Game** |
| Add a game you already have | Right-click its folder and choose **Find Game EXE + Add to Steam** |
| Move a game into Moses storage | Right-click its folder and choose **Move to Game Folder + Add to Steam** |
| Move a game to an external drive | Right-click its folder and choose **Move to External Drive + Add to Steam** |
| Install a game update or mod | Choose **Install into an existing game** and select the target game |
| Fix missing artwork | Select the game and use **Search Artwork Match** or **Download + Apply All Artworks** |
| Find save files | Select a game → **Settings → Storage → Open Selected Game Save Folder** |
| Download optional dependencies | Open **Install / Repair Dependencies** |
| Switch the MangoHud Level 2 layout | **Settings → General → Restore Stock Preset / Apply Moses Preset** |
| Remove a managed game | Select it and choose **Complete Game Removal** |

## Where does Moses store files?

| Data | Typical path |
| --- | --- |
| Managed internal Steam/Proton game folders | `~/.local/share/oneclick-exe/game-prefixes/Steam-Proton/` |
| Downloaded dependency installers | `~/.local/share/oneclick-exe/runtime-cache/` |
| Moses configuration and helpers | `~/.local/share/lutris-oneclick/` |
| MangoHud performance overlay presets | `~/.config/MangoHud/presets.conf` |
| External-drive games | On the selected external drive under `OneClick Games/Steam-Proton/` |

Save-game locations depend on the game and its Proton/Wine prefix. Use **Open Selected Game Save Folder** rather than assuming saves are in your normal Linux Documents folder.

## Uninstall

Run the uninstall script supplied with the download:

```bash
bash Moses_OneClick_Tool_Uninstall_V7.4.113.sh
```

Uninstalling the integration is different from deleting an installed game. Check your game files and saves before removing any game or storage folder.

---

*Moses OneClick Tool is a third-party helper for SteamOS. Steam, Proton, Lutris, MangoHud and SteamGridDB are separate projects or services.*
