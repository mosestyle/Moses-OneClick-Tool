# Moses OneClick Tool
A small SteamOS/KDE helper for standalone Windows `.exe` games using **Steam / Proton by default**, with **Smart Automatic / Lutris** available for games that need extra compatibility help.

<img width="663" height="630" alt="image" src="https://github.com/user-attachments/assets/49f695dc-24c1-4582-91dc-03bf8364a71a" />   <img width="548" height="427" alt="image" src="https://github.com/user-attachments/assets/286f9ebf-d08a-466c-81e3-f8fd4580f71d" />


## Features

- **Double-click a Windows `.exe`** → opens the Moses OneClick installer with three choices:
  - **Install as a new game**
  - **Update an installed game**
  - **Add existing game to Steam (no install)**
- **Double-click an installer `.iso`** → Moses mounts it **read-only**, finds the installer inside, and opens the same Game Installer used for `.exe` files. No manual ISO extraction is needed.
- Standalone ISO installs can optionally **delete the ISO after a successful installation**. The ISO is kept by default.
- **Steam / Proton is the default backend.** New games are installed into their own Proton prefix and become normal non-Steam shortcuts that can later use Proton Experimental, GE-Proton or another compatibility tool from Steam Properties.
- **Smart Automatic / Lutris** is available for older or troublesome games. It can use Lutris install recipes, resolve known dependencies/runtimes and apply compatibility fixes automatically.
- The installer window has its own **Steam / Proton ↔ Smart Automatic / Lutris selector**, so you can change backend for one installation without changing your saved default.
- Choose between **internal storage or a supported external drive** when installing a game.
- External games are tracked by the drive's **filesystem UUID**, allowing Moses OneClick to reconnect them after unplugging/replugging the drive and keep them usable from both Desktop Mode and Gaming Mode.
- External-drive preparation supports:
  - **Btrfs** — recommended for SteamOS-only game drives and compatible with Space Saver
  - **ext4** — simple and reliable for SteamOS-only use
  - **NTFS** — useful for drives shared between SteamOS and Windows
- External drives can be given a custom name/label during formatting. Destructive formatting always requires explicit confirmation.
- **Btrfs Space Saver** can deduplicate matching data in approved Proton/Wine prefix locations to reduce duplicate storage use.
- Automatically creates and verifies the final **Steam / Gaming Mode shortcut** after installation.
- Smart update detection recognizes common updater/patch names and can run updates inside an installed game's existing Steam Proton or Lutris Wine prefix.
- **Sequential update chains** are supported. If a follow-up package contains several updates such as `1.12.0 → 1.16.0`, `1.16.0 → 1.16.1`, and `1.16.1 → 1.17.0`, Moses automatically runs them in the correct version order before final Steam shortcut/artwork completion.
- Folder scanning can recursively find likely installers or game executables while filtering obvious uninstallers, redistributables and helper files.
- Smart game-name detection cleans common version, update, build, platform and release-folder noise while keeping the name editable before continuing.
- When several possible main game executables are found, Moses OneClick lets you choose the correct one. Games that required this choice can later reopen the same EXE chooser without reinstalling the game.
- Automatic artwork support:
  - **Both — SteamGridDB + Steam** is the default artwork source
  - **Steam only** and **SteamGridDB only** are also available
  - SteamGridDB is preferred for high-quality artwork when an API key is configured, with Steam available as fallback in Both mode
  - Downloads and applies **Capsule, Wide Capsule, Hero, Logo and Icon** artwork
  - Artwork is cached so unchanged images are not downloaded again
- **Moses OneClick Tool** provides one clean GUI with:
  - Install Game
  - **Play Game**
  - Repair Steam Shortcut
  - Download + Apply All Artworks
  - Complete Game Removal
  - **StreamExtract**
  - **TempOverlay**
  - **Restart Steam**
- **StreamExtract** can download and extract direct ZIP/RAR links straight into Moses OneClick without first saving the complete source archive when the archive format/server supports streaming.
- StreamExtract supports **single links and multi-link jobs**:
  - Split RAR sets such as `Game.part1.rar`, `Game.part2.rar`, etc.
  - `.7z.001`, `.zip.001`, `.z01 + .zip`, and classic `.rar + .r00` multipart sets
  - Mixed batches containing a multipart base game plus separate update/patch archives
- **Multi-link downloads can be changed live from 1 to 10 simultaneous downloads** while a job is running. Increasing the value starts more queued files; lowering it safely takes effect as active downloads finish.
- StreamExtract's normal performance/thermal limit applies to the **combined download traffic**, not separately to each link.
- After a multipart archive is extracted successfully, the temporary downloaded compressed parts are removed automatically.
- **Keep extracted installer files after installation** keeps the extracted ISO/installer source and companion files. Temporary downloaded RAR/ZIP/7z parts are still removed after successful extraction.
- If StreamExtract produces an installer ISO, Moses automatically:
  - mounts the ISO read-only
  - finds the installer
  - opens the normal Game Installer
  - keeps the ISO mounted while setup is running
  - safely unmounts it afterward
  - continues with detected follow-up updates/patches
  - finalizes the Steam shortcut and artwork only after the installation/update chain is complete
- Recognized follow-up **updates / patches / hotfixes** are opened automatically after the base game installation. Non-update companion/DLC/redist files are not blindly auto-run.
- Failed or cancelled follow-up updates are preserved instead of being silently deleted.
- **TempOverlay** provides a lightweight always-on-top temperature monitor, with a compact thermometer icon in the main Moses OneClick window.
- **Restart Steam** cleanly restarts Steam and restores the main Steam window without the unwanted KDE Screen Sharing chooser seen with some SteamOS restart paths.
- Multiple games can be selected for batch repair, artwork and removal. **Play Game** is available when exactly one game is selected.
- Complete Removal can clean the managed game entry, Steam shortcut, artwork, OneClick metadata, compatibility data and reachable game/prefix files. External games are detected first so disconnected drives are not silently treated like local storage.
- Game prefixes use readable **game-name folders** in the Moses OneClick prefix view. External prefixes remain on their external drive and are linked into the same clean named view when available.
- **Settings** includes:
  - Default installer backend
  - Artwork source
  - Saved SteamGridDB API key
  - Internal/external storage tools
  - External-drive formatting
  - Btrfs Space Saver
  - Failed-install cleanup
  - **Language: English (default) or Svenska**
  - Current Moses OneClick Tool version
- Failed Steam-native installs are tracked so incomplete OneClick Proton prefixes can be cleaned without blindly deleting unrelated Steam data.
- Uses normal KDE/GTK window frames and a consistent Moses OneClick interface.

## Requirements

- SteamOS / KDE Plasma
- Steam
- Lutris installed from **Discover / Flatpak** for Smart Automatic / Lutris installs
- Proton Experimental available in Steam for the default Steam-native install workflow
- Python 3 with the `venv` module for the integrated StreamExtract / TempOverlay tools
- Internet access during the first integrated StreamExtract / TempOverlay setup so their Python dependencies can be installed
- A free SteamGridDB API key is optional but recommended for higher-quality community artwork

## Install

### Option 1 — Konsole

```bash
bash "$HOME/Downloads/Moses_OneClick_Tool_V7.4.33/Moses_OneClick_Tool_Setup_V7.4.33.sh"
```

### Option 2 — Right-click → Run in Konsole

1. Right-click `Moses_OneClick_Tool_Setup_V7.4.33.sh`
2. **Properties → Permissions**
3. Enable **Is executable**
4. Right-click again → **Run in Konsole**

Then close and reopen Dolphin once so KDE refreshes the Moses OneClick context-menu actions and file associations.

## Usage

<img width="398" height="548" alt="image" src="https://github.com/user-attachments/assets/23746d3d-26be-47d8-93bc-556ba6efc248" />

**Install a new game:** double-click its installer `.exe`, double-click an installer `.iso`, or open **Moses OneClick Tool → Install Game**. Choose Steam / Proton or Smart Automatic / Lutris and select internal or external storage if needed.

**Install from ISO:** double-click the `.iso`. Moses mounts it read-only, finds the installer and opens the normal Game Installer. The image stays mounted until setup is finished and is then safely unmounted.

**Update / patch:** open an updater and choose **Update an installed game**, then select the game whose existing prefix should be used. StreamExtract follow-up updates can be detected and chained automatically.

**StreamExtract — single link:** paste a direct ZIP/RAR link, choose storage/performance options, then use **Download & Extract**. After extraction Moses continues into the normal game/ISO installer workflow.

**StreamExtract — multiple links:** paste multiple direct links one per line. Moses detects supported multipart sets and separate follow-up archives automatically. Use **Multi-link downloads** to choose between **1 and 10 simultaneous downloads**, and you can change that value while downloading.

**Keep installer sources:** enable **Keep extracted installer files after installation** if you want to keep the resulting ISO/extracted installer source after a successful installation. Temporary compressed multipart files are still cleaned after successful extraction.

**Already have a complete game folder:** let Moses OneClick scan the folder for the likely game executable, or open the game's `.exe` and choose **Add existing game to Steam (no install)**.

**Manage games:** Application Launcher → **Moses OneClick Tool**.

**Play a game:** select one game in Moses OneClick Tool → **Play Game**.

**Artwork:** select one or more games → **Download + Apply All Artworks**. Configure the artwork source and optional SteamGridDB API key under **Settings**.

**Restart Steam:** use the small **Restart Steam** button at the bottom-left of the main window whenever you want Moses OneClick to close and reopen Steam automatically.

**External game drive:** connect the drive before launching an external game. Moses OneClick tracks prepared drives by UUID so reconnecting the same drive does not depend on its temporary mount-folder name.

**Language:** Settings → About → Language → choose **English** or **Svenska**. English is the default.

## Uninstall this integration

```bash
bash "$HOME/Downloads/Moses_OneClick_Tool_V7.4.33/Moses_OneClick_Tool_Uninstall_V7.4.33.sh"
```
gamescope -f -w 1280 -h 720 -W 1920 -H 1080 -- %command%
This removes the Moses OneClick helper, integration files, settings and OneClick caches. It does **not** automatically delete your installed games or existing Steam/Lutris game data unless you explicitly remove those games through the tool first.
