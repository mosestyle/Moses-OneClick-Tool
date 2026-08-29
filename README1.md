# Moses OneClick Tool
A small SteamOS/KDE helper for standalone Windows `.exe` games using **Steam / Proton by default**, with **Smart Automatic / Lutris** available for games that need extra compatibility help.

<img width="663" height="630" alt="image" src="https://github.com/user-attachments/assets/49f695dc-24c1-4582-91dc-03bf8364a71a" />   <img width="548" height="427" alt="image" src="https://github.com/user-attachments/assets/286f9ebf-d08a-466c-81e3-f8fd4580f71d" />


## Features

- **Double-click a Windows `.exe`** → opens the Moses OneClick installer with three choices:
  - **Install as a new game**
  - **Update an installed game**
  - **Add existing game to Steam (no install)**
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
- Automatically creates the final **Steam / Gaming Mode shortcut** after installation.
- **V7.4.18 / StreamExtract v1.13 makes ZIP Range connections manually selectable.** A new dropdown sits directly to the right of the Custom speed unit and lets you choose **1, 2, or 3 connections**. One connection is the default and uses the smooth continuous Range reader; 2-3 enable bounded parallel read-ahead for servers where multiple connections improve throughput. The choice is independent of the Performance profile, is saved between launches, and thermal protection still limits aggregate bandwidth. Three connections do not extract three files at once: they prefetch different byte ranges of the same ZIP. Because parallel mode fetches read-ahead blocks before handing them to the ZIP decoder, Current file progress can look more stop-and-go on some servers; choosing 1 connection removes that parallel read-ahead behavior.
- **V7.4.17 / StreamExtract v1.12 introduced Smart Range acceleration while keeping downloads cool.** ZIP archives on Range-capable servers can use up to three bounded parallel HTTP Range connections with 16 MiB read-ahead blocks, overlapping network transfer with decompression/disk writes instead of forcing more CPU work. V7.4.18 replaces its automatic connection-count choice with the manual dropdown described above.
- **V7.4.15 / StreamExtract v1.10 fixes multi-gigabyte progress totals for real.** The previous worker signals used Qt/PySide `int`, which is 32-bit; any byte total above roughly 2 GiB could wrap negative in the GUI even after StreamExtract had correctly logged `Final extracted size: 6.9 GB`. Download and Current file byte counters now cross the worker thread as full Python integers, so known 6.9 GB, 15.1 GB, 50 GB, etc. totals remain known and the overall Download bar uses them correctly.
- **V7.4.15 also makes a completed StreamExtract bar visibly complete.** When extraction finishes, the Download bar exits indeterminate/animated mode and becomes a fixed solid 100% bar, matching the completed Current file bar.
- **V7.4.15 fixes Complete Game Removal for OneClick-owned Steam symlink prefixes.** Steam/Proton intentionally uses symlinks for some managed compatdata/prefix layouts. Removal now follows such a link only when the target contains Moses OneClick's ownership marker and the marker AppID exactly matches the selected game; then it deletes the owned target and cleans the verified link. Arbitrary/unverified symlinks are still refused.
- **V7.4.14 / StreamExtract v1.9 fixes the broken overall Download progress while keeping `Current file` unchanged.** Seekable ZIP archives now read the central directory first and use the sum of the final uncompressed file sizes as the stable progress total. RAR4/RAR5 use a lightweight HTTP Range header scan that skips packed payloads, so StreamExtract can normally know the final extracted size without downloading the complete RAR first. The Download line therefore stays in one domain such as `50 MB / 15.1 GB — 0.3% — 45.8 MB/s`, while the speed remains the real network speed. The existing `Remote archive size: ... (HTTP Content-Range)` log entry is kept.
- **V7.4.14 also makes Create Steam Shortcut non-disruptive.** If Steam is open, Moses OneClick no longer closes or restarts it. The shortcut is queued safely and finalized the next time *you* manually close/restart Steam or return to Gaming Mode; artwork can still download immediately. If Steam is already closed, the shortcut is written and verified immediately.
- **V7.4.13 / StreamExtract v1.8 reduced avoidable CPU heat during streaming extraction without lowering the selected download cap.** Sequential HTTP reads were increased from 64 KiB to 1 MiB, and the bandwidth limiter no longer performs tiny sleep/wake cycles when the real source speed is already below the selected limit. Seekable ZIP ranges keep a smaller 256 KiB buffer to avoid wasting data on ZIP seeks. RAR still streams directly into `bsdtar` and is never stored as a complete temporary archive.
- **V7.4.12 fixed intermittent missing Add Existing / StreamExtract shortcuts.** V7.4.14 supersedes its automatic-restart commit strategy with the safer manual/deferred behavior described above.
- Normal Steam-native installs and updates do **not force-restart Steam**. Pending shortcut changes are finalized when Steam naturally closes/restarts, such as when returning to Gaming Mode.
- Smart update detection recognizes common updater/patch names and can run updates inside an installed game's existing Steam Proton or Lutris Wine prefix.
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
  - **StreamExtract** — integrated from StreamExtract v1.13 with the Moses OneClick light/blue interface; choose internal or external game storage, stream-extract directly to that drive, then select the game EXE and let Moses OneClick create the Steam shortcut and artwork automatically
    - V7.4.12 / StreamExtract v1.7 restores the core **stream-first storage contract** for ZIP and RAR: the complete source archive is **not saved to disk first**. A 50 GB archive that expands to 70 GB is intended to need roughly the space for the extracted files, not 50 GB + 70 GB.
    - RAR4/RAR5 are detected automatically and streamed straight from HTTP into SteamOS `bsdtar/libarchive`. The previous V7.4.10 behavior that downloaded a complete temporary RAR before extraction has been removed.
    - Current SteamOS libarchive can sometimes finish a streamed RAR5 and then return `bsdtar: (null)` / `Error exit delayed from previous errors.` StreamExtract now accepts that specific EOF false-negative **only** when the full advertised remote byte count was delivered, at least one archive member was extracted, and no other extractor diagnostic occurred. CRC, truncation, password, write, seek, or other errors still fail normally.
    - ZIP Zstandard / method 93 continues to use the seekable **remote HTTP Range** ZIP engine, so the ZIP remains on the server. If Range is unavailable, StreamExtract tries its sequential ZIP engine; if neither streaming method can safely decode the archive, it fails with an explanation instead of silently downloading the complete ZIP as a temporary file.
    - Interrupted HTTP segments can still resume from the exact next byte while feeding the same extractor process, so a proxy/CDN ending one response early does not require saving the source archive.
    - The manual **Game name** field has been removed. Every download uses a hidden per-job staging folder; after extraction the normal EXE chooser detects/chooses the title and the prefix is renamed automatically.
    - StreamExtract opens centered on the screen, and unchecked/checked boxes now use a clearly visible bordered indicator.
    - Failed StreamExtract jobs freeze both progress bars, stop extraction work, and automatically remove the exact incomplete session folder; failed-install cleanup also detects abandoned sessions and the legacy opaque-token folders left by older builds.
    - The old help paragraph below the activity log is replaced by a live session summary showing **Started**, **Duration**, **Finished**, and final **Total** time. A **Save Log** button in the lower-right saves a diagnostic `.txt` with the session state, timings, performance/thermal settings and activity log; signed URL query tokens are redacted.
    - Overall **Download** progress uses final extracted bytes whenever archive metadata permits, while **Current file** remains a separate per-file progress bar. If a compatibility path cannot know the final extracted size safely, it falls back to the verified remote archive size rather than inventing a false total.
  - **TempOverlay** — the lightweight always-on-top temperature overlay
  - **Restart Steam** — cleanly closes Steam, restarts it without the unwanted KDE Screen Sharing chooser, and restores the main Steam window
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
bash "$HOME/Downloads/Moses_OneClick_Tool_V7.4.17/Moses_OneClick_Tool_Setup_V7.4.17.sh"
```

### Option 2 — Right-click → Run in Konsole

1. Right-click `Moses_OneClick_Tool_Setup_V7.4.17.sh`
2. **Properties → Permissions**
3. Enable **Is executable**
4. Right-click again → **Run in Konsole**

Then close and reopen Dolphin once so KDE refreshes the Moses OneClick context-menu actions.

## Usage

<img width="398" height="548" alt="image" src="https://github.com/user-attachments/assets/23746d3d-26be-47d8-93bc-556ba6efc248" />

**Install a new game:** double-click its installer `.exe` **or** open **Moses OneClick Tool → Install Game**. Choose Steam / Proton or Smart Automatic / Lutris and select internal or external storage if needed.

**Update / patch:** open an updater and choose **Update an installed game**, then select the game whose existing prefix should be used.

**Already have a complete game folder:** let Moses OneClick scan the folder for the likely game executable, or open the game's `.exe` and choose **Add existing game to Steam (no install)**.

**Manage games:** Application Launcher → **Moses OneClick Tool**.

**Play a game:** select one game in Moses OneClick Tool → **Play Game**.

**Artwork:** select one or more games → **Download + Apply All Artworks**. Configure the artwork source and optional SteamGridDB API key under **Settings**.

**Stream tools:** use **StreamExtract** or **TempOverlay** directly from the main Moses OneClick Tool window. StreamExtract supports direct ZIP and RAR/RAR5 archives and can target internal or external Moses game storage. There is no manual Game name field anymore: each download uses a hidden temporary session folder, then after extraction you choose the main game EXE and Moses OneClick detects the title, renames the folder, creates the Steam/Proton shortcut, and starts artwork automatically. Performance/Custom-limit choices persist between launches. TempOverlay keeps its original overlay design.

**Restart Steam:** use the small **Restart Steam** button at the bottom-left of the main window whenever you want Moses OneClick to close and reopen Steam automatically. V7.4.12 no longer routes shutdown, startup or the `steam://open/main` focus request through SteamOS' `steam-jupiter` wrapper. Current Jupiter builds inject `-pipewire`, which can trigger KDE's Screen Sharing chooser; Moses instead uses the inner `/usr/lib/steam/steam` launcher for this Desktop Mode restart, omits `-pipewire`, and restores the main Steam window instead of leaving Steam minimized in the tray.

**External game drive:** connect the drive before launching an external game. Moses OneClick tracks prepared drives by UUID so reconnecting the same drive does not depend on its temporary mount-folder name.

**Language:** Settings → About → Language → choose **English** or **Svenska**. English is the default.

## Uninstall this integration

```bash
bash "$HOME/Downloads/Moses_OneClick_Tool_V7.4.17/Moses_OneClick_Tool_Uninstall_V7.4.17.sh"
```

This removes the Moses OneClick helper, integration files, settings and OneClick caches. It does **not** automatically delete your installed games or existing Steam/Lutris game data unless you explicitly remove those games through the tool first.
