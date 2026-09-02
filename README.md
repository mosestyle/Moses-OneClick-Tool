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
- **Dependency Library + per-game dependency manager** — **Install / Repair Dependencies is always available**, even when no game is installed. With no game selected it opens Library mode so you can download/import dependency packs and inspect the shared cache. With exactly one game selected it also lets you install chosen redistributables inside that exact Steam Proton or Lutris Wine prefix. **Nothing is installed automatically** and all choices start unchecked.
- Recognizes common dependency installers such as **Microsoft Visual C++ Redistributables (x86/x64), DirectX Legacy Runtime, PhysX, OpenAL, XNA, .NET and VulkanRT**. Dependency scanning/installation supports both `.exe` and `.msi` packages, including XNA MSI installers.
- **Shared runtime installer cache** at `~/.local/share/oneclick-exe/runtime-cache/` automatically collects known redistributable installer sources found with installed/added games, deduplicates identical files by **SHA-256**, and reuses them later while keeping actual dependency installation isolated per game prefix. You can also place your own known redistributable `.exe`, `.msi`, and supported component `.zip` files anywhere inside this folder.
- **Portable Vulkan component bundles** are supported for files named like `VulkanRT-...-Components.zip` placed in the runtime cache. They appear as an advanced/manual dependency; Moses detects whether the selected game EXE is x86 or x64 and copies the matching `vulkan-1.dll` **and** `vulkaninfo.exe` beside that game EXE. Existing different files are preserved beside the game as visible `.backup` copies before replacement. PDB debug files are not copied. The ZIP remains cached for reuse.
- Dependency inventory is content-deduplicated, so the same redistributable no longer appears twice if an older build or a manual cache layout left duplicate copies in different folders.
- **Dependency pack import/download** — use **Import dependency ZIP…** to safely import a local `.zip` pack into its own folder under `runtime-cache/Imported Packs`, or **Download dependency pack from GitHub** for a normal GitHub `.zip` file page, GitHub Release asset, raw URL, or other direct HTTPS ZIP. Each GitHub ZIP gets its own visible folder under `runtime-cache/GitHub Packs/<pack-name>/`, so different packs can coexist and refreshing one does not replace the others.
- **Re-added Steam shortcut dependency repair** — dependency scanning/installation can use the selected game’s current EXE/start-folder snapshot if an older removal tombstone left the Steam shortcut valid but the old registry row hidden. Deliberately re-adding an existing game now resets that stale tombstone correctly.
- **Stable Steam metadata recovery** — if an older/experimental Moses build damaged the local game registry, the manager can rebuild entries from active Steam shortcuts that point into Moses game folders. This also covers complete games added with **Find Game EXE + Add to Steam**, which do not necessarily have a Proton-prefix ownership marker. The exact selected shortcut EXE (including a launcher EXE) is preserved.
- **One-click dependency set** — **Download official dependency set** fills `runtime-cache/Official Pack` without installing anything into a game. It includes the current **VC++ v14 runtime for Visual Studio 2015–2026** (x86+x64), legacy VC++ 2013/2012/2010/2008 packages, DirectX June 2010 offline runtime, NVIDIA PhysX, **.NET Framework 4, XNA Framework 4.0 Refresh, OpenAL 1.1**, plus the Moses-hosted **VulkanRT-1.3.290.0 Components** ZIP used for game-folder Vulkan fixes. The vendor redistributables come from their official HTTPS sources; the Vulkan Components ZIP comes from the Moses OneClick GitHub repository. When 7-Zip is available Moses expands DirectX into a reusable `DXSETUP.exe` + CAB bundle; OpenAL’s official ZIP is unpacked to its reusable `oalinst.exe`.
- If a game already launches correctly with its chosen Proton/Wine version, Moses leaves the prefix alone — redistributables are a **manual troubleshooting option**, not a default installation step.
- Right-click any Windows redistributable `.exe` in Dolphin → **Run as game dependency** → choose the target game. This is useful for special cases such as a game-specific `VulkanRT-...-Installer.exe`.
- **Sequential update chains** are supported. If a follow-up package contains several updates such as `1.12.0 → 1.16.0`, `1.16.0 → 1.16.1`, and `1.16.1 → 1.17.0`, Moses automatically runs them in the correct version order before final Steam shortcut/artwork completion.
- **Move to Game Folder + Add to Steam** — right-click an already-complete game folder in Dolphin to move the whole folder into `~/.local/share/oneclick-exe/game-prefixes/Steam-Proton/`, open the same EXE/name chooser used by **Find Game EXE + Add to Steam**, then create/verify the Steam shortcut and fetch artwork through the normal existing-game workflow. The chooser appears before the move, so cancelling leaves the source folder untouched. Existing destination names are never overwritten; Moses offers a safe numbered folder instead.
- Folder scanning can recursively find likely installers or game executables while filtering obvious uninstallers, redistributables and helper files.
- Smart game-name detection cleans common version, update, build, platform and release-folder noise while keeping the name editable before continuing.
- When several possible main game executables are found, Moses OneClick lets you choose the correct one. Games that required this choice can later reopen the same EXE chooser without reinstalling the game.
- Automatic artwork support:
  - **Both — Steam + SteamGridDB** is the default artwork source
  - **Steam only** and **SteamGridDB only** are also available
  - Official Steam artwork is preferred first in Both mode; SteamGridDB is used only as fallback for artwork types Steam cannot provide
  - Downloads and applies **Capsule, Wide Capsule, Hero, Logo and Icon** artwork
  - Artwork is cached so unchanged images are not downloaded again
- GitHub dependency downloads accept normal GitHub file-page links (`.../blob/...`) as well as raw/release URLs; Vulkan component ZIPs are preserved intact in their own cache folder.
- **Moses OneClick Tool** provides one clean GUI with:
  - Install Game
  - **Play Game**
  - Repair Steam Shortcut
- Edit an existing Steam game name/main EXE from the pencil button; renaming keeps the same AppID/prefix and updates future artwork searches.
  - **Install / Repair Dependencies**
  - Download + Apply All Artworks
  - Complete Game Removal
  - **StreamExtract**
  - **TempOverlay**
  - **Restart Steam**
- **StreamExtract** can download and extract direct ZIP/RAR links straight into Moses OneClick without first saving the complete source archive when the archive format/server supports streaming.
- Direct-stream **RAR4/RAR5 completion is hardened** against SteamOS/libarchive's harmless end-of-stream `(null)` quirk. Moses recognizes successful `x path` member lines structurally even when SteamOS bsdtar emits them on stderr, keeps them out of the real diagnostic list, and verifies extracted RAR output against header metadata when available.
- StreamExtract supports **single links and multi-link jobs**:
  - Split RAR sets such as `Game.part1.rar`, `Game.part2.rar`, etc.
  - `.7z.001`, `.zip.001`, `.z01 + .zip`, and classic `.rar + .r00` multipart sets
  - Mixed batches containing a multipart base game plus separate update/patch archives, including **multipart update/patch sets**
- **Multi-link downloads can be changed live from 1 to 10 simultaneous downloads** while a job is running. Increasing the value starts more queued files; lowering it safely takes effect as active downloads finish.
- StreamExtract's normal performance/thermal limit applies to the **combined download traffic**, not separately to each link.
- After a multipart archive is extracted successfully, the temporary downloaded compressed parts are removed automatically.
- **Keep extracted installer files after installation** applies to installer sources such as ISO/setup/update files. For an already-complete game archive with no installer, the extracted game itself is always kept after success whether this option is on or off. When the option is on, a failed extraction also preserves completed output in a visible **StreamExtract Recovery** folder. Temporary downloaded RAR/ZIP/7z parts are still removed after successful extraction.
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
bash "$HOME/Downloads/Moses_OneClick_Tool_V7.4.55/Moses_OneClick_Tool_Setup_V7.4.55.sh"
```

### Option 2 — Right-click → Run in Konsole

1. Right-click `Moses_OneClick_Tool_Setup_V7.4.55.sh`
2. **Properties → Permissions**
3. Enable **Is executable**
4. Right-click again → **Run in Konsole**

Then close and reopen Dolphin once so KDE refreshes the Moses OneClick context-menu actions and file associations.


## Usage

<img width="398" height="548" alt="image" src="https://github.com/user-attachments/assets/23746d3d-26be-47d8-93bc-556ba6efc248" />

**Install a new game:** double-click its installer `.exe`, double-click an installer `.iso`, or open **Moses OneClick Tool → Install Game**. Choose Steam / Proton or Smart Automatic / Lutris and select internal or external storage if needed.

**Install from ISO:** double-click the `.iso`. Moses mounts it read-only, finds the installer and opens the normal Game Installer. The image stays mounted until setup is finished and is then safely unmounted.

**Update / patch:** open an updater and choose **Update an installed game**, then select the game whose existing prefix should be used. StreamExtract follow-up updates can be detected and chained automatically.

**Dependencies / redistributables:** open **Install / Repair Dependencies** at any time. With no game selected, Moses opens **Dependency Library** mode so you can download the official pack, download your GitHub ZIP, import a local ZIP, or open the cache even on a fresh installation with zero games. With exactly one managed game selected, Moses also scans that game and can install selected dependencies into its prefix. The shared cache is at `~/.local/share/oneclick-exe/runtime-cache/`. **Every dependency starts unchecked**: if the game already works, install nothing. If it does not launch, explicitly select only the VC++/DirectX/PhysX/OpenAL/XNA/.NET/VulkanRT installer(s) you want to try; normal `.exe`/`.msi` installers run only inside that game’s existing Proton/Wine prefix. Use **Import dependency ZIP…** for a pack you downloaded manually, **Download official dependency set** for the one-click curated set (including the reusable Vulkan Components ZIP), or **Download dependency pack from GitHub** for your own reusable HTTPS ZIP. You can also right-click a local redistributable `.exe` → **Run as game dependency** and choose the target game. A cached `VulkanRT-...-Components.zip` is handled differently: Moses detects the target game EXE architecture, copies the matching `vulkan-1.dll` and `vulkaninfo.exe` beside the game EXE, and makes visible `.backup` copies of different existing files before replacement.

**StreamExtract — single link:** paste a direct ZIP/RAR link, choose storage/performance options, then use **Download & Extract**. After extraction Moses continues into the normal game/ISO installer workflow.

**StreamExtract — multiple links:** paste multiple direct links one per line. Moses detects supported multipart sets and separate follow-up archives automatically. Use **Multi-link downloads** to choose between **1 and 10 simultaneous downloads**, and you can change that value while downloading.

**Keep installer sources:** enable **Keep extracted installer files after installation** if you want to keep the resulting ISO/extracted installer source after a successful installation. Temporary compressed multipart files are still cleaned after successful extraction.

**Already have a complete game folder:** right-click the folder → **Move to Game Folder + Add to Steam** if you want Moses to physically move the whole folder into its internal Steam-Proton game folder first, then choose the EXE/name and continue with the normal Steam shortcut + artwork flow. Use **Find Game EXE + Add to Steam** when you want the game to stay exactly where it already is. You can also open the game's `.exe` and choose **Add existing game to Steam (no install)**.

**Manage games:** Application Launcher → **Moses OneClick Tool**.

**Play a game:** select one game in Moses OneClick Tool → **Play Game**.

**Artwork:** select one or more games → **Download + Apply All Artworks**. Configure the artwork source and optional SteamGridDB API key under **Settings**.

**Restart Steam:** use the small **Restart Steam** button at the bottom-left of the main window whenever you want Moses OneClick to close and reopen Steam automatically.

**External game drive:** connect the drive before launching an external game. Moses OneClick tracks prepared drives by UUID so reconnecting the same drive does not depend on its temporary mount-folder name.

**Language:** Settings → About → Language → choose **English** or **Svenska**. English is the default.

## Uninstall this integration

```bash
bash "$HOME/Downloads/Moses_OneClick_Tool_V7.4.55/Moses_OneClick_Tool_Uninstall_V7.4.55.sh"
```

This removes the Moses OneClick helper, integration files, settings and OneClick caches. It does **not** automatically delete your installed games or existing Steam/Lutris game data unless you explicitly remove those games through the tool first.

## V7.4.55

- **StreamExtract direct installer chains:** extracted Windows setup packages are now detected before the portable-game finalizer. Moses installs the base setup first, then applies detected DLC/update EXEs in order.
- **Numbered DLC ordering:** filenames such as `dlc1`, `dlc2`, `dlc3` are explicitly sorted numerically, so archive extraction order no longer matters.
- Base + DLC/update chains reuse the same Proton/Lutris target; Steam shortcut/artwork finalization waits until the follow-up chain is finished.
- If a DLC/update is cancelled or fails, later installers are not run and the extracted source is kept for safety.

- **Both artwork mode is now Steam-first.** Moses tries official Steam artwork first for each capsule/hero/logo/icon slot and only uses SteamGridDB when Steam has no usable asset for that slot. Steam-only and SteamGridDB-only modes are unchanged.
- SteamGridDB selection still preserves SteamGridDB's own result order: choice #1 first and choice #2 only if #1 cannot be downloaded.
- Includes the V7.4.51 **Move to Game Folder + Add to Steam** workflow and the stable immediate-stream RAR behavior.
