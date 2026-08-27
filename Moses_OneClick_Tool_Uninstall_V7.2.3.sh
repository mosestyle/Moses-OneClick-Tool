#!/usr/bin/env bash
set -euo pipefail

ONECLICK_VERSION="7.2.3"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
SERVICE_DIR="$HOME/.local/share/kio/servicemenus"
DATA_DIR="$HOME/.local/share/lutris-oneclick"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
EXTERNAL_MONITOR_SERVICE="$SYSTEMD_USER_DIR/moses-oneclick-external-monitor.service"
SGDB_CONFIG_DIR="$HOME/.var/app/net.lutris.Lutris/config/lutris-oneclick"
SGDB_CACHE_DIR="$HOME/.var/app/net.lutris.Lutris/cache/lutris-oneclick"

HELPER="$BIN_DIR/lutris-exe-helper"
LUTRIS_STEAM_WRAPPER="$BIN_DIR/oneclick-lutris-steam-launch"
REMOVE_HELPER="$BIN_DIR/lutris-complete-game-remove"
APP_DESKTOP="$APP_DIR/lutris-exe-installer.desktop"
SERVICE_DESKTOP="$SERVICE_DIR/lutris-exe-update.desktop"
FOLDER_SERVICE_DESKTOP="$SERVICE_DIR/oneclick-add-existing-folder.desktop"
FOLDER_INSTALL_SERVICE_DESKTOP="$SERVICE_DIR/oneclick-find-exe-install.desktop"
REMOVE_APP_DESKTOP="$APP_DIR/lutris-complete-game-remove.desktop"
STEAM_REPAIR_DESKTOP="$APP_DIR/lutris-steam-shortcut-repair.desktop"
TOOLS_DESKTOP="$APP_DIR/lutris-oneclick-tools.desktop"
OLD_SERVICE="$SERVICE_DIR/lutris-exe.desktop"

refresh_kde() {
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  kbuildsycoca6 >/dev/null 2>&1 || true
}

echo "Removing Moses OneClick Tool V${ONECLICK_VERSION} integration..."

systemctl --user disable --now moses-oneclick-external-monitor.service >/dev/null 2>&1 || true
rm -f "$EXTERNAL_MONITOR_SERVICE"
systemctl --user daemon-reload >/dev/null 2>&1 || true

rm -f \
  "$HELPER" \
  "$LUTRIS_STEAM_WRAPPER" \
  "$REMOVE_HELPER" \
  "$APP_DESKTOP" \
  "$SERVICE_DESKTOP" \
  "$FOLDER_SERVICE_DESKTOP" \
  "$FOLDER_INSTALL_SERVICE_DESKTOP" \
  "$REMOVE_APP_DESKTOP" \
  "$STEAM_REPAIR_DESKTOP" \
  "$TOOLS_DESKTOP" \
  "$OLD_SERVICE"

rm -rf "$DATA_DIR"
rm -rf "$HOME/.cache/lutris-exe-helper"
rm -rf "$SGDB_CONFIG_DIR" "$SGDB_CACHE_DIR"

# Restore Bottles as the EXE handler when it is installed, matching the setup script's uninstall behaviour.
if command -v flatpak >/dev/null 2>&1 && flatpak info com.usebottles.bottles >/dev/null 2>&1; then
  for mime in \
    application/x-ms-dos-executable \
    application/x-msdownload \
    application/vnd.microsoft.portable-executable
  do
    xdg-mime default com.usebottles.bottles.desktop "$mime" >/dev/null 2>&1 || true
  done
fi

refresh_kde

echo "Done. Moses OneClick Tool V${ONECLICK_VERSION} was removed."
echo "Your installed games, Steam Proton prefixes and Lutris Wine prefixes were NOT removed."
