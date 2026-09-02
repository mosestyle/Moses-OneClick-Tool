#!/usr/bin/env bash
set -euo pipefail

ONECLICK_VERSION="7.4.54"
APP_ID="net.lutris.Lutris"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
SERVICE_DIR="$HOME/.local/share/kio/servicemenus"
HELPER="$BIN_DIR/lutris-exe-helper"
LUTRIS_STEAM_WRAPPER="$BIN_DIR/oneclick-lutris-steam-launch"
APP_DESKTOP="$APP_DIR/lutris-exe-installer.desktop"
SERVICE_DESKTOP="$SERVICE_DIR/lutris-exe-update.desktop"
REMOVE_APP_DESKTOP="$APP_DIR/lutris-complete-game-remove.desktop"
REMOVE_HELPER="$BIN_DIR/lutris-complete-game-remove"
STEAM_REPAIR_DESKTOP="$APP_DIR/lutris-steam-shortcut-repair.desktop"
TOOLS_DESKTOP="$APP_DIR/lutris-oneclick-tools.desktop"
DATA_DIR="$HOME/.local/share/lutris-oneclick"
ISO_HANDLER_BACKUP="$DATA_DIR/previous-iso-handlers.txt"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
EXTERNAL_MONITOR_SERVICE="$SYSTEMD_USER_DIR/moses-oneclick-external-monitor.service"
TOOLS_GUI="$DATA_DIR/lutris_oneclick_tools.py"
ACTION_GUI="$DATA_DIR/oneclick_action_dialog.py"
FOLDER_SERVICE_DESKTOP="$SERVICE_DIR/oneclick-add-existing-folder.desktop"
FOLDER_INSTALL_SERVICE_DESKTOP="$SERVICE_DIR/oneclick-find-exe-install.desktop"
OLD_SERVICE="$SERVICE_DIR/lutris-exe.desktop"
SGDB_CONFIG_DIR="$HOME/.var/app/net.lutris.Lutris/config/lutris-oneclick"
SGDB_CACHE_DIR="$HOME/.var/app/net.lutris.Lutris/cache/lutris-oneclick"
STREAMTOOLS_ROOT="$HOME/.local/share/moses-oneclick-tools/streamtools"
STREAMEXTRACT_DIR="$STREAMTOOLS_ROOT/StreamExtract"
TEMPOVERLAY_DIR="$STREAMTOOLS_ROOT/TempOverlay"
STREAMTOOLS_VENV="$STREAMTOOLS_ROOT/.venv"
STREAMEXTRACT_LAUNCHER="$BIN_DIR/moses-streamextract"
TEMPOVERLAY_LAUNCHER="$BIN_DIR/moses-tempoverlay"
TEMPOVERLAY_KWIN_RULE_ID="moses-oneclick-tempoverlay"

refresh_kde() {
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  kbuildsycoca6 >/dev/null 2>&1 || true
}

remember_iso_handlers() {
  mkdir -p "$DATA_DIR"
  touch "$ISO_HANDLER_BACKUP"
  local mime current
  for mime in \
    application/vnd.efi.iso \
    application/x-cd-image \
    application/x-iso9660-image
  do
    if ! grep -Fq "${mime}|" "$ISO_HANDLER_BACKUP" 2>/dev/null; then
      current="$(xdg-mime query default "$mime" 2>/dev/null || true)"
      if [[ "$current" != "lutris-exe-installer.desktop" ]]; then
        printf '%s|%s\n' "$mime" "$current" >> "$ISO_HANDLER_BACKUP"
      fi
    fi
  done
}

restore_iso_handlers() {
  [[ -f "$ISO_HANDLER_BACKUP" ]] || return 0
  local mime desktop
  while IFS='|' read -r mime desktop; do
    [[ -n "$mime" ]] || continue
    if [[ -n "$desktop" ]]; then
      xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
    fi
  done < "$ISO_HANDLER_BACKUP"
}

remove_moses_tempoverlay_kwin_rule() {
  if ! command -v kwriteconfig6 >/dev/null 2>&1 || ! command -v kreadconfig6 >/dev/null 2>&1; then
    return 0
  fi
  local current new_rules=() rule
  current="$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
  IFS=',' read -r -a _rules <<< "$current"
  for rule in "${_rules[@]:-}"; do
    rule="${rule//[[:space:]]/}"
    [[ -z "$rule" || "$rule" == "$TEMPOVERLAY_KWIN_RULE_ID" ]] && continue
    new_rules+=("$rule")
  done
  kwriteconfig6 --file kwinrulesrc --group "$TEMPOVERLAY_KWIN_RULE_ID" --delete >/dev/null 2>&1 || true
  kwriteconfig6 --file kwinrulesrc --group General --key rules "$(IFS=','; echo "${new_rules[*]:-}")" >/dev/null 2>&1 || true
  kwriteconfig6 --file kwinrulesrc --group General --key count "${#new_rules[@]}" >/dev/null 2>&1 || true
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  fi
}

uninstall_all() {
  echo "Removing Moses OneClick Tool integration..."
  # Best-effort cleanup of read-only ISO mounts created by StreamExtract. Busy
  # installer discs are never force-unmounted; udisks will refuse them safely.
  if [[ -x "$HELPER" ]]; then
    "$HELPER" stream-iso-cleanup-all >/dev/null 2>&1 || true
  fi
  systemctl --user disable --now moses-oneclick-external-monitor.service >/dev/null 2>&1 || true
  rm -f "$EXTERNAL_MONITOR_SERVICE"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  rm -f "$HELPER" "$LUTRIS_STEAM_WRAPPER" "$REMOVE_HELPER" "$APP_DESKTOP" "$SERVICE_DESKTOP" "$FOLDER_SERVICE_DESKTOP" "$FOLDER_INSTALL_SERVICE_DESKTOP" "$REMOVE_APP_DESKTOP" "$STEAM_REPAIR_DESKTOP" "$TOOLS_DESKTOP" "$OLD_SERVICE"
  rm -f "$STREAMEXTRACT_LAUNCHER" "$TEMPOVERLAY_LAUNCHER"
  rm -rf "$STREAMTOOLS_ROOT"
  remove_moses_tempoverlay_kwin_rule
  restore_iso_handlers
  rm -rf "$DATA_DIR"
  rm -rf "$HOME/.cache/lutris-exe-helper"
  rm -rf "$HOME/.local/share/oneclick-exe/runtime-cache"
  rm -rf "$SGDB_CONFIG_DIR" "$SGDB_CACHE_DIR"

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
  echo "Done. Your installed games, Steam Proton prefixes and Lutris Wine prefixes were NOT removed."
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall_all
  exit 0
fi

if ! command -v flatpak >/dev/null 2>&1; then
  echo "ERROR: Flatpak was not found."
  exit 1
fi

if ! flatpak info "$APP_ID" >/dev/null 2>&1; then
  echo "ERROR: The Flatpak/Discover version of Lutris is not installed."
  echo "Install Lutris from Discover first, then run this setup again."
  exit 1
fi

if ! command -v kdialog >/dev/null 2>&1; then
  echo "ERROR: kdialog was not found."
  exit 1
fi

mkdir -p "$BIN_DIR" "$APP_DIR" "$SERVICE_DIR" "$DATA_DIR" "$SYSTEMD_USER_DIR" "$HOME/.cache/lutris-exe-helper" "$STREAMEXTRACT_DIR" "$TEMPOVERLAY_DIR"
printf '%s\n' "$ONECLICK_VERSION" > "$DATA_DIR/version"

# ---------------------------------------------------------------------------
# Integrated StreamExtract v1.26 + TempOverlay
# ---------------------------------------------------------------------------
# These are installed as Moses-owned tools so the OneClick buttons keep
# working even if the user's old standalone SteamOS_StreamTools package is
# later removed.  Program files are refreshed on every Moses update, while
# the Python venv is reused whenever its dependencies are still healthy.
cat > "$STREAMEXTRACT_DIR/stream_extract_gui.py" <<'__MOSES_STREAM_EXTRACT_V08__'
from __future__ import annotations

import os
import re
import sys
import json
import time
import io
import threading
import concurrent.futures
import shutil
import subprocess
from pathlib import Path, PurePosixPath
from datetime import datetime
from urllib.parse import urlparse, unquote

import httpx
from PySide6.QtCore import QObject, QSettings, QThread, QTimer, Signal, Slot
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QSpinBox,
    QPlainTextEdit,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from stream_unzip import stream_unzip, UnzipError
from sensor_core import SensorReader, SensorSnapshot


APP_NAME = "StreamExtract"
APP_VERSION = "1.27"
# Larger application-level chunks reduce Python/Qt wakeups without changing the
# selected bandwidth cap. Network Range acceleration below uses its own bounded
# 16 MiB blocks and never stores the complete archive.
CHUNK_SIZE = 4 * 1024 * 1024
# StreamExtract v1.26 keeps the reliable multi-link/ISO/update pipeline and
# fixes SteamOS bsdtar RAR verbose-output classification. On SteamOS/libarchive,
# successful `x path` member lines may be emitted on stderr rather than stdout.
# Those structural member lines are now recognized as extracted members regardless
# of which pipe carried them, so they never pollute the diagnostic whitelist. The
# known RAR5 end-of-stream `(null)` quirk is accepted only after the complete remote
# archive was received and, when available, the extracted file count and logical
# byte size match the RAR header scan exactly. Genuine diagnostics remain fatal.
# Keep-files recovery, multipart base/update handling, sequential update chains and
# live 1-10 multi-link concurrency remain unchanged.
STREAM_HTTP_CHUNK_SIZE = 2 * 1024 * 1024
RANGE_HTTP_CHUNK_SIZE = 1024 * 1024
PARALLEL_RANGE_BLOCK_SIZE = 16 * 1024 * 1024
PARALLEL_RANGE_WORKERS = 3
MULTIPART_MAX_PARALLEL = 10
PARALLEL_RANGE_CACHE_BLOCKS = 4
# V1.2 no longer downloads fixed-size 64 MiB Range blocks before handing data
# to the ZIP decoder. It keeps one HTTP Range response open and feeds bytes to
# the decoder continuously. This removes the old download/pause/download rhythm.
HTTP_RETRYABLE_STATUS = {408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524}
HTTP_MAX_STATUS_RETRIES = 6
MIB = 1024 * 1024
HELPER_PATH = Path.home() / ".local/bin/lutris-exe-helper"


class UserCancelled(Exception):
    pass


class StreamTransportError(RuntimeError):
    """The remote HTTP byte stream cannot be continued safely."""
    pass


class RangeZipUnavailable(RuntimeError):
    """The server cannot provide the random HTTP byte ranges ZIP needs."""
    pass


class RangeZipUnsupported(RuntimeError):
    """The archive needs a ZIP feature handled by a fallback engine."""
    pass


class ArchiveNotZip(RuntimeError):
    """The remote payload is an archive format other than ZIP."""

    def __init__(self, archive_kind: str = "UNKNOWN"):
        self.archive_kind = (archive_kind or "UNKNOWN").upper()
        super().__init__(f"Detected {self.archive_kind} archive instead of ZIP.")


def detect_archive_kind(data: bytes) -> str:
    """Best-effort archive type detection from the first bytes."""
    head = bytes(data or b"")
    if head.startswith(b"Rar!\x1a\x07\x01\x00"):
        return "RAR5"
    if head.startswith(b"Rar!\x1a\x07\x00"):
        return "RAR4"
    if head.startswith((b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08")):
        return "ZIP"
    if head.startswith(b"7z\xbc\xaf\x27\x1c"):
        return "7Z"
    if head.startswith(b"\x1f\x8b"):
        return "GZIP"
    if head.startswith(b"BZh"):
        return "BZIP2"
    if head.startswith(b"\xfd7zXZ\x00"):
        return "XZ"
    if len(head) >= 262 and head[257:262] == b"ustar":
        return "TAR"
    return "UNKNOWN"


def get_zstd_zipfile_module():
    """Return a Python 3.14-compatible zipfile module with ZIP method 93."""
    if sys.version_info >= (3, 14):
        import zipfile as zstd_zipfile
        return zstd_zipfile
    try:
        from backports.zstd import zipfile as zstd_zipfile
        return zstd_zipfile
    except Exception as exc:
        raise RuntimeError(
            "The ZIP Zstandard helper (backports.zstd) is missing. "
            "Re-run the Moses OneClick setup so StreamExtract dependencies "
            "can be refreshed."
        ) from exc


class HTTPStreamingRangeReader(io.RawIOBase):
    """Seekable HTTP file facade with a continuous sequential stream.

    ZIP needs random access for its central directory and local file headers,
    but file payloads are read sequentially. Older StreamExtract versions
    fetched a whole fixed-size Range block before returning any bytes, which
    produced a visible download/pause/download rhythm at each block boundary.

    V1.2 instead opens one Range response at the current seek position and
    keeps it open while the ZIP decoder reads forward. A seek closes that
    response and opens a new one. If a proxy ends a response early, reading is
    resumed from the exact next byte without exposing a gap to zipfile.
    """

    def __init__(
        self, total_size: int, open_segment, on_network_bytes=None,
        network_chunk_size: int = RANGE_HTTP_CHUNK_SIZE,
    ):
        super().__init__()
        self.total_size = int(total_size)
        self.open_segment = open_segment
        self.on_network_bytes = on_network_bytes
        self.network_chunk_size = max(4096, int(network_chunk_size or RANGE_HTTP_CHUNK_SIZE))
        self.pos = 0
        self._pending = bytearray()
        self._segment_ctx = None
        self._response = None
        self._iterator = None
        self._network_pos = 0
        self._segment_end = None
        self._segment_had_data = False
        self._empty_reopens = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def _close_segment(self):
        ctx = self._segment_ctx
        response = self._response
        self._segment_ctx = None
        self._response = None
        self._iterator = None
        self._segment_end = None
        self._segment_had_data = False
        if ctx is not None:
            try:
                ctx.__exit__(None, None, None)
            except Exception:
                try:
                    if response is not None:
                        response.close()
                except Exception:
                    pass

    def close(self):
        self._close_segment()
        self._pending.clear()
        super().close()

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET:
            new_pos = int(offset)
        elif whence == io.SEEK_CUR:
            new_pos = self.pos + int(offset)
        elif whence == io.SEEK_END:
            new_pos = self.total_size + int(offset)
        else:
            raise ValueError("Invalid seek mode")
        if new_pos < 0:
            raise OSError("Negative seek position")
        new_pos = min(new_pos, self.total_size)

        if new_pos == self.pos:
            return self.pos

        # Forward seeks that stay inside already-buffered network bytes need no
        # new request. This also avoids needless reconnects for tiny ZIP seeks.
        if new_pos > self.pos and new_pos <= self.pos + len(self._pending):
            drop = new_pos - self.pos
            if drop:
                del self._pending[:drop]
            self.pos = new_pos
            return self.pos

        self._close_segment()
        self._pending.clear()
        self.pos = new_pos
        self._network_pos = new_pos
        self._empty_reopens = 0
        return self.pos

    def _ensure_segment(self):
        if self.pos >= self.total_size:
            return False
        if self._iterator is not None:
            return True

        ctx, response, segment_end = self.open_segment(self.pos)
        self._segment_ctx = ctx
        self._response = response
        self._iterator = response.iter_raw(chunk_size=self.network_chunk_size)
        self._network_pos = self.pos
        self._segment_end = segment_end
        self._segment_had_data = False
        return True

    def _next_network_chunk(self):
        while self.pos < self.total_size:
            if not self._ensure_segment():
                return b""

            try:
                chunk = next(self._iterator)
            except StopIteration:
                had_data = self._segment_had_data
                resume_at = self._network_pos
                self._close_segment()
                if resume_at >= self.total_size:
                    return b""
                if had_data:
                    self._empty_reopens = 0
                else:
                    self._empty_reopens += 1
                    if self._empty_reopens >= 4:
                        raise StreamTransportError(
                            f"The server repeatedly returned no ZIP data at byte {resume_at:,}."
                        )
                    time.sleep(0.10 * self._empty_reopens)
                # A proxy is allowed to end one HTTP response before EOF. The
                # next iteration reopens at the exact next byte.
                self.pos = resume_at
                continue
            except httpx.RequestError as exc:
                resume_at = self._network_pos
                self._close_segment()
                self._empty_reopens += 1
                if self._empty_reopens >= 4:
                    raise StreamTransportError(
                        f"The server repeatedly disconnected while reading byte {resume_at:,}."
                    ) from exc
                self.pos = resume_at
                time.sleep(min(0.10 * self._empty_reopens, 0.4))
                continue

            if not chunk:
                continue

            # Never consume beyond the announced range or archive end.
            limit = self.total_size - self._network_pos
            if self._segment_end is not None:
                limit = min(limit, int(self._segment_end) - self._network_pos + 1)
            if limit <= 0:
                resume_at = self._network_pos
                self._close_segment()
                self.pos = resume_at
                continue
            if len(chunk) > limit:
                chunk = chunk[:limit]
            if not chunk:
                continue

            if self.on_network_bytes is not None:
                self.on_network_bytes(len(chunk))
            self._network_pos += len(chunk)
            self._segment_had_data = True
            self._empty_reopens = 0
            return chunk

        return b""

    def read(self, size=-1):
        if self.pos >= self.total_size:
            return b""
        if size is None or size < 0:
            size = self.total_size - self.pos
        size = min(int(size), self.total_size - self.pos)
        if size <= 0:
            return b""

        out = bytearray()
        while len(out) < size:
            if self._pending:
                take = min(size - len(out), len(self._pending))
                out += self._pending[:take]
                del self._pending[:take]
                self.pos += take
                continue

            chunk = self._next_network_chunk()
            if not chunk:
                break
            self._pending.extend(chunk)

        return bytes(out)

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


class HTTPParallelRangeReader(io.RawIOBase):
    """Seekable remote-file facade with bounded parallel HTTP Range read-ahead.

    ZIP extraction alternates between short seeks (central directory/local headers)
    and long sequential payload reads. A single synchronous HTTP stream makes the
    network sit idle while Python decompresses/writes each returned chunk. This
    reader keeps only a few adjacent 16 MiB archive blocks in RAM and downloads
    them with up to three Range requests in parallel. The ZIP bytes are still
    presented strictly in archive order and the complete archive is never saved.

    Random seeks are safe: cached/future blocks are keyed by archive block index.
    Stale blocks are simply discarded by the bounded cache.
    """

    def __init__(
        self,
        total_size: int,
        fetch_exact_range,
        workers: int = PARALLEL_RANGE_WORKERS,
        block_size: int = PARALLEL_RANGE_BLOCK_SIZE,
        cache_blocks: int = PARALLEL_RANGE_CACHE_BLOCKS,
    ):
        super().__init__()
        self.total_size = max(0, int(total_size))
        self.fetch_exact_range = fetch_exact_range
        self.block_size = max(1024 * 1024, int(block_size))
        self.workers = max(1, min(int(workers), 4))
        self.cache_blocks = max(self.workers + 1, int(cache_blocks))
        self.pos = 0
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=self.workers,
            thread_name_prefix="streamextract-range",
        )
        self._futures: dict[int, concurrent.futures.Future] = {}
        self._cache: dict[int, bytes] = {}
        self._closed_parallel = False
        self._lock = threading.Lock()

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def _bounds(self, index: int):
        start = int(index) * self.block_size
        end = min(self.total_size - 1, start + self.block_size - 1)
        return start, end

    def _fetch_block(self, index: int):
        start, end = self._bounds(index)
        if start >= self.total_size or end < start:
            return b""
        return self.fetch_exact_range(start, end)

    def _schedule(self, index: int):
        if index < 0 or index * self.block_size >= self.total_size:
            return
        with self._lock:
            if index in self._cache or index in self._futures:
                return
            self._futures[index] = self._executor.submit(self._fetch_block, index)

    def _schedule_ahead(self, index: int):
        # Current block + the next blocks keep all Range workers useful while
        # decompression or disk writes are happening on the calling thread.
        for offset in range(self.workers):
            self._schedule(index + offset)

    def _get_block(self, index: int) -> bytes:
        with self._lock:
            cached = self._cache.get(index)
        if cached is not None:
            return cached

        self._schedule_ahead(index)
        with self._lock:
            future = self._futures.get(index)
        if future is None:
            return b""
        data = bytes(future.result())
        with self._lock:
            self._futures.pop(index, None)
            self._cache[index] = data
            # Keep memory bounded. Prefer the current/near-future area but do
            # not cancel already-running requests; completed stale data is tiny
            # compared with ever storing the full archive.
            if len(self._cache) > self.cache_blocks:
                keys = sorted(self._cache, key=lambda k: abs(k - index), reverse=True)
                while len(self._cache) > self.cache_blocks and keys:
                    self._cache.pop(keys.pop(0), None)
        self._schedule_ahead(index + 1)
        return data

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET:
            new_pos = int(offset)
        elif whence == io.SEEK_CUR:
            new_pos = self.pos + int(offset)
        elif whence == io.SEEK_END:
            new_pos = self.total_size + int(offset)
        else:
            raise ValueError("Invalid seek mode")
        if new_pos < 0:
            raise OSError("Negative seek position")
        self.pos = min(new_pos, self.total_size)
        return self.pos

    def read(self, size=-1):
        if self.pos >= self.total_size:
            return b""
        if size is None or size < 0:
            size = self.total_size - self.pos
        size = min(max(0, int(size)), self.total_size - self.pos)
        if size <= 0:
            return b""

        out = bytearray()
        while len(out) < size and self.pos < self.total_size:
            index = self.pos // self.block_size
            block = self._get_block(index)
            if not block:
                break
            block_start = index * self.block_size
            inside = self.pos - block_start
            if inside < 0 or inside >= len(block):
                break
            take = min(size - len(out), len(block) - inside)
            if take <= 0:
                break
            out.extend(block[inside:inside + take])
            self.pos += take
        return bytes(out)

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)

    def close(self):
        if self._closed_parallel:
            return
        self._closed_parallel = True
        try:
            self._executor.shutdown(wait=False, cancel_futures=True)
        except TypeError:
            self._executor.shutdown(wait=False)
        with self._lock:
            self._futures.clear()
            self._cache.clear()
        super().close()

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

def human_bytes(value: int | float | None) -> str:
    if value is None:
        return "Unknown"
    value = float(value)
    units = ["B", "KB", "MB", "GB", "TB"]
    for unit in units:
        if abs(value) < 1024.0 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024.0
    return f"{value:.1f} TB"


def parse_rate_limit(text: str) -> int:
    raw = text.strip().lower().replace(" ", "")
    raw = raw.replace("/sec", "/s").replace("ps", "/s")
    match = re.fullmatch(
        r"([0-9]+(?:\.[0-9]+)?)(kib|mib|gib|kb|mb|gb|kbit|mbit|gbit|kbps|mbps|gbps|b)(?:/s)?",
        raw,
    )
    if not match:
        raise ValueError(
            "Use a value such as 20 MiB/s, 20 MB/s, 100 Mbps, 1 Gbps, or 500 KB/s."
        )

    value = float(match.group(1))
    unit = match.group(2)
    if value <= 0:
        raise ValueError("The custom speed limit must be greater than 0.")

    byte_units = {
        "b": 1, "kb": 1000, "mb": 1000**2, "gb": 1000**3,
        "kib": 1024, "mib": 1024**2, "gib": 1024**3,
    }
    bit_units = {
        "kbit": 1000, "mbit": 1000**2, "gbit": 1000**3,
        "kbps": 1000, "mbps": 1000**2, "gbps": 1000**3,
    }
    if unit in byte_units:
        return int(value * byte_units[unit])
    return int(value * bit_units[unit] / 8)


CUSTOM_SPEED_UNITS = {
    "KB/s": 1024,
    "MB/s": 1024**2,
    "GB/s": 1024**3,
}


def parse_custom_rate_limit(value_text: str, unit_text: str) -> int:
    """Parse the v1.11 split Custom limit controls.

    StreamExtract has historically displayed binary-sized transfer values with
    the familiar KB/MB/GB labels, so these controls intentionally follow the
    same convention (MB/s == 1024**2 bytes/s here).
    """
    raw_value = (value_text or "").strip().replace(",", ".")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", raw_value):
        raise ValueError("Enter a number, for example 70, then choose KB/s, MB/s, or GB/s.")
    value = float(raw_value)
    if value <= 0:
        raise ValueError("The custom speed limit must be greater than 0.")
    multiplier = CUSTOM_SPEED_UNITS.get(unit_text)
    if multiplier is None:
        raise ValueError("Choose KB/s, MB/s, or GB/s.")
    return int(value * multiplier)


def split_saved_custom_limit(text: str) -> tuple[str, str]:
    """Migrate older one-field limits such as `80 MiB/s` into v1.11."""
    raw = (text or "").strip()
    compact = raw.lower().replace(" ", "")
    match = re.fullmatch(
        r"([0-9]+(?:\.[0-9]+)?)(kib|mib|gib|kb|mb|gb)(?:/s)?",
        compact,
    )
    if match:
        value = match.group(1)
        unit = match.group(2)
        if unit in {"kb", "kib"}:
            return value, "KB/s"
        if unit in {"gb", "gib"}:
            return value, "GB/s"
        return value, "MB/s"

    # Old versions also accepted bit-rate spellings. Preserve their effective
    # rate by converting them to a compact byte-rate value for the new controls.
    try:
        rate = parse_rate_limit(raw)
    except ValueError:
        return "20", "MB/s"
    if rate >= 1024**3:
        value, unit = rate / (1024**3), "GB/s"
    elif rate >= 1024**2:
        value, unit = rate / (1024**2), "MB/s"
    else:
        value, unit = rate / 1024, "KB/s"
    shown = f"{value:.3f}".rstrip("0").rstrip(".")
    return shown, unit


def decode_zip_name(raw: bytes) -> str:
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("cp437", errors="replace")


def safe_member_path(base: Path, member_name: str) -> Path:
    name = member_name.replace("\\", "/")
    if "\x00" in name:
        raise ValueError("ZIP entry contains a NUL character.")

    pure = PurePosixPath(name)
    if pure.is_absolute():
        raise ValueError(f"Unsafe absolute path: {member_name}")

    parts = [part for part in pure.parts if part not in ("", ".")]
    if any(part == ".." for part in parts):
        raise ValueError(f"Unsafe parent traversal: {member_name}")
    if parts and ":" in parts[0]:
        raise ValueError(f"Unsafe drive/path prefix: {member_name}")

    target = base.joinpath(*parts)
    base_resolved = base.resolve()
    target_parent = target.parent.resolve()
    try:
        target_parent.relative_to(base_resolved)
    except ValueError:
        raise ValueError(f"ZIP entry escapes destination: {member_name}")
    return target


def calculate_thermal_rate(
    base_rate: int | None,
    temp: float | None,
    enabled: bool,
    threshold: int,
) -> int | None:
    """Return an effective cap, applying progressive thermal protection."""
    if not enabled or temp is None or temp < threshold:
        return base_rate

    over = temp - threshold
    if over >= 10:
        if base_rate is None:
            return 4 * MIB
        return max(1 * MIB, min(int(base_rate * 0.20), 4 * MIB))
    if over >= 5:
        if base_rate is None:
            return 10 * MIB
        return max(1 * MIB, min(int(base_rate * 0.35), 10 * MIB))

    if base_rate is None:
        return 20 * MIB
    return max(1 * MIB, min(int(base_rate * 0.60), 20 * MIB))


class DownloadWorker(QObject):
    # IMPORTANT: PySide6 Signal(int) maps to a 32-bit C++ int. That overflows
    # at 2 GiB and made perfectly-known totals such as 6.9 GB arrive at the GUI
    # as negative/unknown. Keep byte counters as Python integers instead.
    download_progress = Signal(object, object, float)
    file_progress = Signal(str, object, object)
    log = Signal(str)
    finished = Signal()
    cancelled = Signal()
    failed = Signal(str)

    def __init__(
        self,
        url: str,
        destination: str,
        password: str,
        overwrite: bool,
        performance_mode: str,
        custom_rate_bps: int | None,
        range_connections: int,
        thermal_enabled: bool,
        thermal_threshold: int,
    ):
        super().__init__()
        self.url = url
        self.destination = Path(destination)
        self.password_text = password or ""
        self.password = password.encode("utf-8") if password else None
        self.overwrite = overwrite
        self.performance_mode = performance_mode
        self.range_connections = max(1, min(int(range_connections or 1), 3))
        self.base_rate_bps = {
            "Cool / Quiet": 12 * MIB,
            "Normal": 40 * MIB,
            "Maximum speed": None,
            "Custom": custom_rate_bps,
        }.get(performance_mode)

        self._cancel = threading.Event()
        self._active_part: Path | None = None
        self._active_archive: Path | None = None
        self._active_process: subprocess.Popen | None = None
        # Cache the size probe for the entire job. V1.0 could probe the same
        # signed URL again in a fallback path, which needlessly hammered some
        # download proxies and could turn a transient 503 into a hard failure.
        self._probe_attempted = False
        self._remote_size_cache = -1
        self._archive_kind_cache = "UNKNOWN"
        self._thermal_lock = threading.Lock()
        self._thermal_enabled = thermal_enabled
        self._thermal_threshold = thermal_threshold
        self._thermal_temp: float | None = None
        now = time.monotonic()
        self._rate_window_started = now
        self._rate_window_bytes = 0
        self._rate_window_rate: int | None = None
        # Parallel Range workers share one aggregate limiter/speed meter.
        # The locks keep the selected Custom/Thermal cap global rather than
        # accidentally applying the cap once per HTTP connection.
        self._throttle_lock = threading.Lock()
        self._range_speed_lock = threading.Lock()
        self._range_speed_window_started = now
        self._range_speed_window_bytes = 0
        self._range_last_speed = 0.0

        # V1.9 keeps the visible Download bar in one stable accounting domain:
        # final extracted bytes. ZIP learns this from its central directory.
        # RAR4/5 learns it from a lightweight HTTP Range header scan that skips
        # packed payloads instead of downloading the archive twice.
        self._overall_total = -1
        self._overall_source = ""
        self._archive_progress_entries: list[tuple[int, int, int]] = []
        self._archive_progress_index = 0
        self._archive_progress_completed = 0
        self._last_network_speed = 0.0
        # Expected RAR payload metadata learned by the lightweight header scan.
        # Used only to verify the extracted tree before forgiving libarchive's
        # known harmless RAR5 EOF `(null)` return code.
        self._rar_expected_file_count = 0
        self._rar_expected_unpacked_total = -1

    @Slot()
    def cancel(self):
        self._cancel.set()
        proc = self._active_process
        if proc is not None and proc.poll() is None:
            try:
                proc.terminate()
            except Exception:
                pass

    def update_thermal(self, temp: float | None, enabled: bool, threshold: int):
        with self._thermal_lock:
            self._thermal_temp = temp
            self._thermal_enabled = enabled
            self._thermal_threshold = threshold

    def update_performance(self, mode: str, custom_rate_bps: int | None):
        """Apply a new speed profile immediately while a download is running."""
        new_rate = {
            "Cool / Quiet": 12 * MIB,
            "Normal": 40 * MIB,
            "Maximum speed": None,
            "Custom": custom_rate_bps,
        }.get(mode)

        with self._thermal_lock:
            self.performance_mode = mode
            self.base_rate_bps = new_rate

        if new_rate is None:
            self.log.emit(f"Performance changed: {mode} (no base cap)")
        else:
            self.log.emit(
                f"Performance changed: {mode} ({human_bytes(new_rate)}/s)"
            )

    def effective_rate(self) -> int | None:
        with self._thermal_lock:
            temp = self._thermal_temp
            enabled = self._thermal_enabled
            threshold = self._thermal_threshold
            base_rate = self.base_rate_bps
        return calculate_thermal_rate(
            base_rate, temp, enabled, threshold
        )

    def _check_cancel(self):
        if self._cancel.is_set():
            raise UserCancelled()

    def _cleanup_active_part(self):
        if self._active_part and self._active_part.exists():
            try:
                self._active_part.unlink()
            except OSError:
                pass
        self._active_part = None

    def _cleanup_active_archive(self):
        if self._active_archive and self._active_archive.exists():
            try:
                self._active_archive.unlink()
            except OSError:
                pass
        self._active_archive = None

    @staticmethod
    def _retry_delay(response, attempt: int) -> float:
        """Short exponential retry, respecting a numeric Retry-After header."""
        try:
            retry_after = float(response.headers.get("Retry-After", ""))
            if retry_after >= 0:
                return min(max(retry_after, 0.25), 12.0)
        except Exception:
            pass
        return min(0.5 * (2 ** max(0, attempt)), 5.0)

    @staticmethod
    def _retryable_status(status: int) -> bool:
        return int(status) in HTTP_RETRYABLE_STATUS

    def _make_http_client(self):
        # A browser-like UA improves compatibility with signed CDN/proxy links
        # that reject unusual downloader identifiers. No cookies or auth data
        # are fabricated; the signed URL remains the authority.
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/128.0 Safari/537.36"
            ),
            "Accept": "*/*",
            "Accept-Encoding": "identity",
        }
        timeout = httpx.Timeout(connect=30.0, read=None, write=30.0, pool=30.0)
        return httpx.Client(
            follow_redirects=True,
            timeout=timeout,
            headers=headers,
        )

    @staticmethod
    def _parse_content_range(value: str | None):
        """Return (start, end, total-or-None) for a normal byte Content-Range."""
        if not value:
            return None
        match = re.match(
            r"^\s*bytes\s+(\d+)-(\d+)/(\d+|\*)\s*$",
            value,
            re.I,
        )
        if not match:
            return None
        start = int(match.group(1))
        end = int(match.group(2))
        if end < start:
            return None
        total = None if match.group(3) == "*" else int(match.group(3))
        if total is not None and total <= 0:
            total = None
        return start, end, total

    @classmethod
    def _parse_content_range_total(cls, value: str | None) -> int | None:
        parsed = cls._parse_content_range(value)
        if not parsed:
            return None
        return parsed[2]

    def _probe_remote_size(self, client) -> int:
        """Best-effort one-time range probe for the complete archive size.

        V1.1 avoids the old 0-0 micro-range and never probes the same signed
        link twice. Some proxy/CDN endpoints dislike tiny Range requests or
        briefly return 503 while a generated download is warming up.
        """
        if self._probe_attempted:
            return int(self._remote_size_cache or -1)

        self._probe_attempted = True
        self._remote_size_cache = -1
        probe_headers = {
            "Range": f"bytes=0-{MIB - 1}",
            "Accept-Encoding": "identity",
        }

        for attempt in range(HTTP_MAX_STATUS_RETRIES):
            self._check_cancel()
            try:
                with client.stream("GET", self.url, headers=probe_headers) as probe:
                    status = int(probe.status_code)
                    if self._retryable_status(status):
                        delay = self._retry_delay(probe, attempt)
                        self.log.emit(
                            f"Download server returned HTTP {status} during archive probe; "
                            f"retrying in {delay:.1f}s…"
                        )
                    else:
                        # Reuse this already-required probe to sniff the archive
                        # signature. This avoids a second tiny request just to
                        # distinguish ZIP from RAR/7z/etc.
                        try:
                            first_chunk = next(probe.iter_raw(chunk_size=4096), b"")
                            kind = detect_archive_kind(first_chunk)
                            if kind != "UNKNOWN":
                                self._archive_kind_cache = kind
                                self.log.emit(f"Detected archive format: {kind}")
                        except Exception:
                            pass

                        if status == 206:
                            total = self._parse_content_range_total(
                                probe.headers.get("Content-Range")
                            )
                            if total:
                                self._remote_size_cache = int(total)
                                self.log.emit(
                                    f"Remote archive size: {human_bytes(total)} "
                                    f"(HTTP Content-Range)"
                                )
                                return int(total)

                        # A normal 200 can still expose a trustworthy whole-file
                        # length when the server explicitly advertises ranges.
                        accept_ranges = probe.headers.get("Accept-Ranges", "").strip().lower()
                        length = probe.headers.get("Content-Length")
                        if status == 200 and accept_ranges == "bytes" and length and length.isdigit():
                            candidate = int(length)
                            if candidate > 0:
                                self._remote_size_cache = candidate
                                self.log.emit(
                                    f"Remote archive size: {human_bytes(candidate)} "
                                    f"(HTTP Content-Length)"
                                )
                                return candidate

                        if status >= 400:
                            self.log.emit(
                                f"Archive size probe returned HTTP {status}; "
                                "trying compatibility mode without another probe."
                            )
                        return -1
            except httpx.RequestError as exc:
                delay = min(0.5 * (2 ** attempt), 5.0)
                self.log.emit(
                    f"Archive size probe network retry {attempt + 1}/{HTTP_MAX_STATUS_RETRIES}: "
                    f"{type(exc).__name__}; retrying in {delay:.1f}s…"
                )

            if attempt + 1 < HTTP_MAX_STATUS_RETRIES:
                time.sleep(delay)

        self.log.emit(
            "Archive size probe could not get a stable response. "
            "Switching to compatibility download mode."
        )
        return -1

    def _reset_rate_window(self, rate: int | None = None):
        self._rate_window_started = time.monotonic()
        self._rate_window_bytes = 0
        self._rate_window_rate = rate

    def _throttle_network_bytes(self, byte_count: int):
        """Low-wakeup *aggregate* bandwidth limiter.

        V1.12 may have several HTTP Range workers receiving adjacent ZIP blocks
        at the same time. The lock intentionally makes all of them share one
        pacing window, so `80 MB/s` still means roughly 80 MB/s in total -- not
        80 MB/s per connection. Below the selected cap there is no artificial
        sleep, preserving the cooler v1.8 behavior.
        """
        byte_count = max(0, int(byte_count))
        if byte_count <= 0:
            return

        with self._throttle_lock:
            rate = self.effective_rate()
            now = time.monotonic()
            if not rate:
                self._reset_rate_window(None)
                return

            if self._rate_window_rate != rate:
                self._reset_rate_window(rate)
                now = self._rate_window_started

            elapsed = max(now - self._rate_window_started, 0.0)
            self._rate_window_bytes += byte_count
            target_elapsed = self._rate_window_bytes / float(rate)
            remaining = target_elapsed - elapsed

            while remaining > 0:
                self._check_cancel()
                current_rate = self.effective_rate()
                if not current_rate:
                    self._reset_rate_window(None)
                    return
                if current_rate != rate:
                    self._reset_rate_window(current_rate)
                    self._rate_window_bytes = byte_count
                    rate = current_rate
                    elapsed = 0.0
                    remaining = byte_count / float(rate)
                    continue

                time.sleep(min(0.05, remaining))
                elapsed = max(time.monotonic() - self._rate_window_started, 0.0)
                remaining = (self._rate_window_bytes / float(rate)) - elapsed

            if time.monotonic() - self._rate_window_started >= 0.50:
                self._reset_rate_window(rate)

    def _note_range_bytes(self, byte_count: int):
        with self._range_speed_lock:
            self._range_speed_window_bytes += max(0, int(byte_count))
            now = time.monotonic()
            elapsed = max(now - self._range_speed_window_started, 0.001)
            self._range_last_speed = self._range_speed_window_bytes / elapsed
            if elapsed >= 1.0:
                self._range_speed_window_started = now
                self._range_speed_window_bytes = 0

    def _smart_range_worker_count(self) -> int:
        """Return the user-selected ZIP HTTP Range connection count.

        V1.13 deliberately stops guessing from the speed cap. A 1-connection
        selection uses the continuous streaming Range reader, which tends to
        make Current file progress the smoothest. Selections 2-3 enable bounded
        parallel read-ahead. The bandwidth/thermal cap is still aggregate.
        """
        return max(1, min(int(self.range_connections or 1), PARALLEL_RANGE_WORKERS))

    def _set_overall_total(self, total: int, source: str = ""):
        total = int(total or -1)
        if total <= 0:
            return
        self._overall_total = total
        self._overall_source = str(source or "")
        self.download_progress.emit(0, total, self._last_network_speed)
        if source:
            self.log.emit(
                f"Final extracted size: {human_bytes(total)} ({source})"
            )

    def _set_archive_progress_map(
        self, entries: list[tuple[int, int, int]], total: int, source: str
    ):
        self._archive_progress_entries = list(entries or [])
        self._archive_progress_index = 0
        self._archive_progress_completed = 0
        self._set_overall_total(total, source)

    def _mapped_output_bytes(self, archive_position: int, archive_total: int) -> int:
        """Map sequential archive bytes to final extracted-byte progress.

        RAR metadata scanning gives us each file's packed data interval and
        unpacked size. Completed files therefore count exactly, while the file
        currently crossing the network is interpolated within its own packed
        interval. If only a final total is known (for a compatibility ZIP
        fallback), use the whole-archive ratio rather than switching the UI to
        a different size domain halfway through the job.
        """
        position = max(0, int(archive_position or 0))
        total_out = int(self._overall_total or -1)
        if total_out <= 0:
            return position

        entries = self._archive_progress_entries
        if entries:
            idx = min(self._archive_progress_index, len(entries))
            completed = int(self._archive_progress_completed)
            while idx < len(entries):
                data_start, data_end, unpacked = entries[idx]
                if data_end <= data_start:
                    completed += max(0, int(unpacked))
                    idx += 1
                    continue
                if position >= data_end:
                    completed += max(0, int(unpacked))
                    idx += 1
                    continue
                break
            self._archive_progress_index = idx
            self._archive_progress_completed = completed
            if idx >= len(entries):
                return min(completed, total_out)

            data_start, data_end, unpacked = entries[idx]
            if position <= data_start:
                return min(completed, total_out)
            packed = max(1, int(data_end) - int(data_start))
            inside = min(max(position - int(data_start), 0), packed)
            estimate = completed + int(max(0, int(unpacked)) * (inside / packed))
            return min(max(estimate, completed), total_out)

        if archive_total > 0:
            fraction = min(max(position / float(archive_total), 0.0), 1.0)
            return min(int(total_out * fraction), total_out)
        return 0

    def _emit_transport_progress(self, downloaded: int, archive_total: int, speed: float):
        """Emit the visible Download bar without mixing incompatible totals."""
        downloaded = max(0, int(downloaded or 0))
        archive_total = int(archive_total or -1)
        if archive_total <= 0 and int(self._remote_size_cache or -1) > 0:
            archive_total = int(self._remote_size_cache)
        speed = max(0.0, float(speed or 0.0))
        self._last_network_speed = speed

        if self._overall_total > 0:
            shown = self._mapped_output_bytes(downloaded, archive_total)
            self.download_progress.emit(shown, self._overall_total, speed)
        else:
            self.download_progress.emit(downloaded, archive_total, speed)

    @staticmethod
    def _read_rar5_vint_bytes(data: bytes, offset: int):
        value = 0
        shift = 0
        pos = int(offset)
        for _ in range(10):
            if pos >= len(data):
                raise ValueError("Truncated RAR5 variable integer")
            byte = data[pos]
            pos += 1
            value |= (byte & 0x7F) << shift
            if not (byte & 0x80):
                return value, pos
            shift += 7
        raise ValueError("RAR5 variable integer is too long")

    @staticmethod
    def _read_rar5_vint_stream(reader):
        value = 0
        shift = 0
        for _ in range(10):
            raw = reader.read(1)
            if len(raw) != 1:
                raise ValueError("Truncated RAR5 variable integer")
            byte = raw[0]
            value |= (byte & 0x7F) << shift
            if not (byte & 0x80):
                return value
            shift += 7
        raise ValueError("RAR5 variable integer is too long")

    def _scan_rar5_metadata(self, reader, total: int):
        reader.seek(0)
        signature = reader.read(8)
        if signature != b"Rar!\x1a\x07\x01\x00":
            raise ValueError("RAR5 signature was not found at byte 0")

        position = 8
        entries: list[tuple[int, int, int]] = []
        unpacked_total = 0
        file_count = 0
        block_count = 0

        while position < total:
            self._check_cancel()
            block_count += 1
            if block_count > 500000:
                raise ValueError("RAR5 contains an unreasonable number of headers")

            reader.seek(position)
            if len(reader.read(4)) != 4:  # Header CRC32.
                raise ValueError("Truncated RAR5 block CRC")
            header_size = self._read_rar5_vint_stream(reader)
            if header_size <= 0 or header_size > 2 * MIB:
                raise ValueError(f"Invalid RAR5 header size: {header_size}")
            header_start = reader.tell()
            header = reader.read(header_size)
            if len(header) != header_size:
                raise ValueError("Truncated RAR5 block header")

            idx = 0
            header_type, idx = self._read_rar5_vint_bytes(header, idx)
            header_flags, idx = self._read_rar5_vint_bytes(header, idx)
            if header_flags & 0x0008 or header_flags & 0x0010:
                raise ValueError("Multi-volume RAR progress cannot be sized from one URL")

            extra_size = 0
            if header_flags & 0x0001:
                extra_size, idx = self._read_rar5_vint_bytes(header, idx)
            data_size = 0
            if header_flags & 0x0002:
                data_size, idx = self._read_rar5_vint_bytes(header, idx)

            data_start = header_start + header_size
            next_position = data_start + int(data_size)
            if next_position <= position or next_position > total:
                raise ValueError("RAR5 block points outside the advertised archive size")

            if header_type == 4:
                # The archive encryption header means every following header is
                # AES-encrypted. A metadata-only range scan cannot safely infer
                # filenames/sizes without implementing the full RAR KDF/crypto.
                raise ValueError("RAR5 archive headers are encrypted")

            if header_type == 2:
                file_flags, idx = self._read_rar5_vint_bytes(header, idx)
                unpacked_size, idx = self._read_rar5_vint_bytes(header, idx)
                if file_flags & 0x0008:
                    raise ValueError("RAR5 contains a file with unknown unpacked size")
                is_dir = bool(file_flags & 0x0001)
                if not is_dir:
                    unpacked_size = max(0, int(unpacked_size))
                    unpacked_total += unpacked_size
                    file_count += 1
                    entries.append((data_start, next_position, unpacked_size))

            position = next_position
            if header_type == 5:
                break

        if file_count <= 0:
            raise ValueError("RAR5 header scan found no file entries")
        return unpacked_total, entries, file_count

    def _scan_rar4_metadata(self, reader, total: int):
        reader.seek(0)
        signature = reader.read(7)
        if signature != b"Rar!\x1a\x07\x00":
            raise ValueError("RAR4 signature was not found at byte 0")

        position = 7
        entries: list[tuple[int, int, int]] = []
        unpacked_total = 0
        file_count = 0
        block_count = 0

        while position < total:
            self._check_cancel()
            block_count += 1
            if block_count > 500000:
                raise ValueError("RAR4 contains an unreasonable number of headers")

            reader.seek(position)
            base = reader.read(7)
            if len(base) != 7:
                raise ValueError("Truncated RAR4 block header")
            head_type = base[2]
            flags = int.from_bytes(base[3:5], "little")
            head_size = int.from_bytes(base[5:7], "little")
            if head_size < 7 or head_size > 2 * MIB:
                raise ValueError(f"Invalid RAR4 header size: {head_size}")
            rest = reader.read(head_size - 7)
            if len(rest) != head_size - 7:
                raise ValueError("Truncated RAR4 block header")
            header = base + rest

            # RAR3/4 whole-archive header encryption hides all file headers.
            if head_type == 0x73 and (flags & 0x0080):
                raise ValueError("RAR4 archive headers are encrypted")

            data_size = 0
            if flags & 0x8000:
                if len(header) < 11:
                    raise ValueError("RAR4 long block is missing ADD_SIZE")
                data_size = int.from_bytes(header[7:11], "little")

            if head_type == 0x74:  # FILE_HEAD
                if len(header) < 32:
                    raise ValueError("RAR4 file header is too short")
                if flags & 0x0001 or flags & 0x0002:
                    raise ValueError("Multi-volume RAR progress cannot be sized from one URL")

                pack_low = int.from_bytes(header[7:11], "little")
                unp_low = int.from_bytes(header[11:15], "little")
                unp_ver = header[24]
                attr = int.from_bytes(header[28:32], "little")
                pack_high = 0
                unp_high = 0
                if flags & 0x0100:
                    if len(header) < 40:
                        raise ValueError("RAR4 large-file header is too short")
                    pack_high = int.from_bytes(header[32:36], "little")
                    unp_high = int.from_bytes(header[36:40], "little")

                packed_size = (pack_high << 32) | pack_low
                unpacked_size = (unp_high << 32) | unp_low
                if (not (flags & 0x0100) and unp_low == 0xFFFFFFFF) or (
                    (flags & 0x0100) and unpacked_size == 0xFFFFFFFFFFFFFFFF
                ):
                    raise ValueError("RAR4 contains a file with unknown unpacked size")

                if unp_ver >= 20:
                    is_dir = (flags & 0x00E0) == 0x00E0
                else:
                    is_dir = bool(attr & 0x0010)

                data_size = packed_size
                data_start = position + head_size
                next_position = data_start + packed_size
                if next_position <= position or next_position > total:
                    raise ValueError("RAR4 file points outside the advertised archive size")
                if not is_dir:
                    unpacked_size = max(0, int(unpacked_size))
                    unpacked_total += unpacked_size
                    file_count += 1
                    entries.append((data_start, next_position, unpacked_size))
            else:
                data_start = position + head_size
                next_position = data_start + int(data_size)
                if next_position <= position or next_position > total:
                    raise ValueError("RAR4 block points outside the advertised archive size")

            position = next_position
            if head_type == 0x7B:  # ENDARC_HEAD
                break

        if file_count <= 0:
            raise ValueError("RAR4 header scan found no file entries")
        return unpacked_total, entries, file_count

    def _prepare_rar_final_size(self, client, archive_kind: str, total: int):
        """Read only RAR headers, skipping packed payloads with HTTP seeks.

        This is deliberately not a first full download pass. The source RAR
        remains remote; large packed data regions are jumped over with Range
        seeks. It gives the UI a stable final extracted-size denominator before
        bsdtar starts consuming the real sequential stream.
        """
        if total <= 0:
            return False
        self.log.emit("Scanning RAR headers for final extracted size…")

        def open_segment(start):
            ctx, response, new_total, segment_end = self._open_response(
                client, total, int(start)
            )
            if new_total > 0 and new_total != total:
                ctx.__exit__(None, None, None)
                raise StreamTransportError(
                    "The remote archive changed size during the RAR metadata scan."
                )
            return ctx, response, segment_end

        reader = HTTPStreamingRangeReader(
            total, open_segment, None, network_chunk_size=64 * 1024
        )
        try:
            if archive_kind == "RAR5":
                unpacked_total, entries, file_count = self._scan_rar5_metadata(reader, total)
            elif archive_kind == "RAR4":
                unpacked_total, entries, file_count = self._scan_rar4_metadata(reader, total)
            else:
                return False
            self._rar_expected_file_count = int(file_count or 0)
            self._rar_expected_unpacked_total = int(unpacked_total or 0)
            self._set_archive_progress_map(
                entries, unpacked_total, f"{archive_kind} header scan, {file_count:,} files"
            )
            return True
        except UserCancelled:
            raise
        except Exception as exc:
            self._archive_progress_entries = []
            self.log.emit(
                "Could not pre-calculate the final RAR extracted size; "
                f"falling back to archive-byte progress. Details: {exc}"
            )
            return False
        finally:
            reader.close()

    def _fetch_exact_range(self, client, start: int, end: int, total: int) -> bytes:
        """Fetch [start, end] exactly, with status/network retry and resume."""
        if start < 0 or end < start or end >= total:
            raise StreamTransportError("Invalid HTTP range requested internally.")

        out = bytearray()
        cursor = start
        retries_without_progress = 0
        status_retries = 0
        while cursor <= end:
            self._check_cancel()
            headers = {
                "Range": f"bytes={cursor}-{end}",
                "Accept-Encoding": "identity",
            }
            before = cursor
            retry_delay = None
            retry_status = None
            try:
                with client.stream("GET", self.url, headers=headers) as response:
                    status = int(response.status_code)
                    if self._retryable_status(status):
                        retry_status = status
                        retry_delay = self._retry_delay(response, status_retries)
                    else:
                        response.raise_for_status()
                        parsed = self._parse_content_range(response.headers.get("Content-Range"))
                        if response.status_code != 206 or not parsed:
                            raise RangeZipUnavailable(
                                "The server did not honor an exact HTTP byte-range request."
                            )
                        got_start, got_end, got_total = parsed
                        if got_start != cursor:
                            raise StreamTransportError(
                                f"The server returned byte {got_start:,} when byte "
                                f"{cursor:,} was requested."
                            )
                        if got_total and got_total != total:
                            raise StreamTransportError(
                                "The remote archive changed size during extraction. "
                                "Generate a fresh download link and retry."
                            )

                        response_limit = min(end, got_end)
                        for chunk in response.iter_raw(chunk_size=RANGE_HTTP_CHUNK_SIZE):
                            self._check_cancel()
                            if not chunk:
                                continue
                            remaining = response_limit - cursor + 1
                            if remaining <= 0:
                                break
                            if len(chunk) > remaining:
                                chunk = chunk[:remaining]
                            self._throttle_network_bytes(len(chunk))
                            out.extend(chunk)
                            cursor += len(chunk)
                            self._note_range_bytes(len(chunk))
                            if cursor > response_limit:
                                break
            except RangeZipUnavailable:
                raise
            except httpx.HTTPStatusError as exc:
                # Non-transient 4xx/5xx. Range capability may be blocked while
                # a normal one-request download still works, so let the caller
                # use compatibility mode rather than hard-failing immediately.
                raise RangeZipUnavailable(
                    f"HTTP range request failed with status {exc.response.status_code}."
                ) from exc
            except httpx.RequestError as exc:
                if cursor == before:
                    retries_without_progress += 1
                else:
                    retries_without_progress = 0
                if retries_without_progress >= 4:
                    raise StreamTransportError(
                        f"The server repeatedly disconnected while reading byte {cursor:,}."
                    ) from exc
                self.log.emit(
                    f"Range connection interrupted at {human_bytes(cursor)}; resuming…"
                )
                time.sleep(min(0.25 * max(1, retries_without_progress), 1.0))
                continue

            if retry_status is not None:
                status_retries += 1
                if status_retries >= HTTP_MAX_STATUS_RETRIES:
                    raise RangeZipUnavailable(
                        f"The server kept returning HTTP {retry_status} to byte-range requests."
                    )
                self.log.emit(
                    f"HTTP {retry_status} for archive range at {human_bytes(cursor)}; "
                    f"retrying in {retry_delay:.1f}s…"
                )
                time.sleep(retry_delay)
                continue

            status_retries = 0
            if cursor == before:
                retries_without_progress += 1
                if retries_without_progress >= 4:
                    raise StreamTransportError(
                        f"The server returned no data for byte range {cursor:,}-{end:,}."
                    )
                time.sleep(0.15)
            else:
                retries_without_progress = 0

        return bytes(out)

    def _open_response(
        self,
        client,
        probed_total: int = -1,
        start_offset: int = 0,
    ):
        """Open one HTTP segment, retrying transient 503/5xx/429 responses."""
        headers = {"Accept-Encoding": "identity"}
        if start_offset > 0 or probed_total > 0:
            headers["Range"] = f"bytes={start_offset}-"

        last_status = None
        last_reason = ""
        for attempt in range(HTTP_MAX_STATUS_RETRIES):
            self._check_cancel()
            response_ctx = client.stream("GET", self.url, headers=headers)
            try:
                response = response_ctx.__enter__()
            except httpx.RequestError:
                if attempt + 1 >= HTTP_MAX_STATUS_RETRIES:
                    raise
                delay = min(0.5 * (2 ** attempt), 5.0)
                self.log.emit(
                    f"Connection could not be opened; retrying in {delay:.1f}s…"
                )
                time.sleep(delay)
                continue

            status = int(response.status_code)
            if self._retryable_status(status):
                last_status = status
                last_reason = str(response.reason_phrase or "")
                delay = self._retry_delay(response, attempt)
                response_ctx.__exit__(None, None, None)
                if attempt + 1 >= HTTP_MAX_STATUS_RETRIES:
                    break
                self.log.emit(
                    f"Download server returned HTTP {status} {last_reason}; "
                    f"retrying in {delay:.1f}s…"
                )
                time.sleep(delay)
                continue

            try:
                response.raise_for_status()
            except Exception:
                response_ctx.__exit__(*sys.exc_info())
                raise

            parsed_range = self._parse_content_range(
                response.headers.get("Content-Range")
            )

            if start_offset > 0:
                if response.status_code != 206:
                    response_ctx.__exit__(None, None, None)
                    raise StreamTransportError(
                        "The download server ended the transfer early and then "
                        "ignored HTTP byte-range resume. The archive cannot be "
                        "continued safely."
                    )
                if not parsed_range or parsed_range[0] != start_offset:
                    got = str(parsed_range[0]) if parsed_range else "an unknown offset"
                    response_ctx.__exit__(None, None, None)
                    raise StreamTransportError(
                        "The download server returned the wrong resume position "
                        f"(requested byte {start_offset}, got {got})."
                    )
            elif response.status_code == 206 and parsed_range and parsed_range[0] != 0:
                response_ctx.__exit__(None, None, None)
                raise StreamTransportError(
                    "The initial HTTP response did not start at byte 0, so the "
                    "archive stream would be incomplete."
                )

            total = probed_total
            if parsed_range and parsed_range[2]:
                total = parsed_range[2]
                self._remote_size_cache = int(total)
                self._probe_attempted = True

            # Do NOT treat Content-Length on an ordinary 200 as authoritative.
            # The user's proxy previously exposed only a ~73.6 MiB HTTP segment
            # even though the archive itself was several GiB.
            segment_end = parsed_range[1] if parsed_range else None
            return response_ctx, response, total, segment_end

        raise StreamTransportError(
            f"Download server kept returning HTTP {last_status or 'error'} "
            f"{last_reason} after {HTTP_MAX_STATUS_RETRIES} attempts. "
            "The link may still be generating, temporarily rate-limited, or expired."
        )

    def _iter_resumable_response(self, client):
        """
        Yield one byte-perfect archive stream across as many HTTP requests as
        needed. This specifically handles download proxies that stop each HTTP
        response after a fixed chunk (for example ~73.6 MB) even though the archive
        itself is several GB. Each next Range response is concatenated directly
        into the same extractor stdin, so the complete archive is still never saved.
        """
        total = self._probe_remote_size(client)
        downloaded = 0
        started = time.monotonic()
        last_emit = started
        speed_window_started = started
        speed_window_bytes = 0
        self._reset_rate_window(self.effective_rate())
        continuation_count = 0
        no_progress_count = 0
        max_continuations = 512

        self.log.emit(
            "Connected. Download size: "
            + (human_bytes(total) if total >= 0 else "unknown")
        )

        while True:
            self._check_cancel()
            segment_start = downloaded
            segment_error = None

            try:
                response_ctx, response, new_total, segment_end = self._open_response(
                    client,
                    total,
                    downloaded,
                )
            except httpx.RequestError as exc:
                # If we already know there are bytes left, a transient failure
                # while opening the continuation request can be retried safely.
                if total > 0 and downloaded < total:
                    continuation_count += 1
                    no_progress_count += 1
                    if (
                        continuation_count > max_continuations
                        or no_progress_count >= 4
                    ):
                        raise StreamTransportError(
                            "The server could not reopen the archive stream at "
                            f"byte {downloaded:,} after several attempts."
                        ) from exc
                    self.log.emit(
                        f"Connection retry at {human_bytes(downloaded)}: "
                        f"{type(exc).__name__}"
                    )
                    time.sleep(min(0.25 * no_progress_count, 1.0))
                    continue
                raise

            if new_total > 0:
                if total > 0 and new_total != total:
                    response_ctx.__exit__(None, None, None)
                    raise StreamTransportError(
                        "The download server changed the archive size while "
                        "resuming the transfer. Please generate a fresh link."
                    )
                total = new_total

            try:
                try:
                    # iter_raw() avoids transparent Content-Encoding decoding;
                    # the bytes sent to an extractor must match the archive byte-for-byte.
                    for chunk in response.iter_raw(chunk_size=STREAM_HTTP_CHUNK_SIZE):
                        self._check_cancel()
                        if not chunk:
                            continue

                        self._throttle_network_bytes(len(chunk))

                        downloaded += len(chunk)
                        speed_window_bytes += len(chunk)

                        if total > 0 and downloaded > total:
                            raise StreamTransportError(
                                "The server sent more bytes than the reported "
                                "archive size; refusing to feed a corrupted "
                                "stream to the extractor."
                            )

                        now = time.monotonic()
                        if now - last_emit >= 0.15:
                            window_elapsed = max(
                                now - speed_window_started,
                                0.001,
                            )
                            speed = speed_window_bytes / window_elapsed
                            self._emit_transport_progress(downloaded, total, speed)
                            last_emit = now

                        if now - speed_window_started >= 1.0:
                            speed_window_started = now
                            speed_window_bytes = 0

                        yield chunk
                except httpx.RequestError as exc:
                    segment_error = exc
            finally:
                response_ctx.__exit__(None, None, None)

            made_progress = downloaded - segment_start
            if made_progress > 0:
                no_progress_count = 0
            else:
                no_progress_count += 1

            # Known complete size: never accept an early end as EOF. Reopen
            # the URL with Range=<exact next byte>- and keep feeding the SAME
            # extraction process.
            if total > 0 and downloaded < total:
                continuation_count += 1
                if continuation_count > max_continuations or no_progress_count >= 4:
                    detail = (
                        f" Last network error: {type(segment_error).__name__}: "
                        f"{segment_error}"
                        if segment_error
                        else ""
                    )
                    raise StreamTransportError(
                        "The HTTP stream repeatedly stopped before the end of "
                        f"the archive ({human_bytes(downloaded)} of "
                        f"{human_bytes(total)} received)." + detail
                    )

                if segment_end is not None and downloaded - 1 < segment_end:
                    self.log.emit(
                        "HTTP segment ended unexpectedly before its advertised "
                        "range was complete."
                    )

                self.log.emit(
                    "HTTP segment ended before the archive was complete: "
                    f"{human_bytes(downloaded)} / {human_bytes(total)}."
                )
                self.log.emit(
                    f"Resuming seamlessly from byte {downloaded:,} "
                    "without saving the full archive..."
                )
                time.sleep(0.15)
                continue

            if segment_error is not None:
                raise segment_error

            # If total was unknown, a clean EOF is the only completion signal
            # available. The extractor will still validate the archive data.
            break

        elapsed = max(time.monotonic() - started, 0.001)
        self._emit_transport_progress(downloaded, total, downloaded / elapsed)
    def _read_process_output(
        self, pipe, label: str, tail: list[str], stats: dict | None = None,
        diagnostic_stream: bool = False,
    ):
        if pipe is None:
            return
        try:
            for raw in iter(pipe.readline, b""):
                if not raw:
                    break
                line = raw.decode("utf-8", errors="replace").strip()
                if not line:
                    continue

                tail.append(line)
                if len(tail) > 30:
                    del tail[:-30]

                # libarchive/bsdtar does not consistently keep verbose member
                # output on stdout. On SteamOS it can emit successful `x path`
                # lines on stderr. Classify structurally before considering which
                # pipe carried the line; otherwise every extracted member becomes a
                # fake diagnostic and the harmless RAR5 EOF workaround can never
                # activate. This also means names such as `errorcodes` are harmless.
                normalized = line
                lower = normalized.lower()
                has_tool_prefix = lower.startswith(("bsdtar:", "7z:", "7-zip:"))
                if has_tool_prefix:
                    normalized = normalized.split(":", 1)[1].lstrip()

                is_member_line = bool(re.match(r"^[xX]\s+.+", normalized))
                if is_member_line:
                    display = re.sub(r"^[xX]\s+", "", normalized, count=1)
                    is_tool_diagnostic = False
                else:
                    display = normalized
                    is_tool_diagnostic = bool(diagnostic_stream or has_tool_prefix)

                if stats is not None:
                    if is_tool_diagnostic:
                        stats.setdefault("diagnostics", []).append(line)
                    elif is_member_line:
                        stats["members"] = int(stats.get("members", 0)) + 1

                if is_tool_diagnostic:
                    self.log.emit(
                        line if has_tool_prefix else f"{label}: {line}"
                    )
                elif is_member_line:
                    self.file_progress.emit(display, 0, -1)
                    self.log.emit(f"Extracting: {display}")
                else:
                    # Non-diagnostic chatter (rare for bsdtar) is informational,
                    # not an extracted member and not an error.
                    self.log.emit(f"{label}: {display}")
        finally:
            try:
                pipe.close()
            except Exception:
                pass

    @staticmethod
    def _rar_bsdtar_benign_eof_only(diagnostics: list[str]) -> bool:
        """Recognize SteamOS/libarchive's RAR5 stdin EOF false-negative.

        We only forgive the non-zero bsdtar exit when *all* diagnostics are the
        known `(null)` + delayed-error pair. Any CRC, truncation, password,
        write, seek or other real error remains fatal.
        """
        if not diagnostics:
            return False
        saw_null = False
        for raw in diagnostics:
            text = str(raw or "").strip().lower()
            while text.startswith("bsdtar:"):
                text = text[len("bsdtar:"):].strip()
            if text == "(null)":
                saw_null = True
                continue
            if text == "error exit delayed from previous errors.":
                continue
            return False
        return saw_null

    def _verify_rar_extracted_payload(self):
        """Verify RAR output against metadata from the pre-stream header scan.

        Returns True/False when metadata is available, otherwise None. This is
        deliberately strict: the harmless bsdtar EOF quirk is only forgiven
        when the extracted regular-file count and logical byte total match the
        RAR headers exactly.
        """
        expected_files = int(self._rar_expected_file_count or 0)
        expected_bytes = int(self._rar_expected_unpacked_total or -1)
        if expected_files <= 0 or expected_bytes < 0:
            return None

        actual_files = 0
        actual_bytes = 0
        try:
            for root, _dirs, names in os.walk(self.destination):
                for name in names:
                    path = Path(root) / name
                    try:
                        if path.is_file():
                            st = path.stat()
                            actual_files += 1
                            actual_bytes += max(0, int(st.st_size))
                    except OSError:
                        return False
        except OSError:
            return False

        matched = actual_files == expected_files and actual_bytes == expected_bytes
        if matched:
            self.log.emit(
                "RAR output verification passed: "
                f"{actual_files:,} files / {human_bytes(actual_bytes)} exactly match the header scan."
            )
        else:
            self.log.emit(
                "RAR output verification did not match the header scan: "
                f"expected {expected_files:,} files / {human_bytes(expected_bytes)}, "
                f"found {actual_files:,} files / {human_bytes(actual_bytes)}."
            )
        return matched

    def _extract_with_http_range_zip(self):
        """Seekable HTTP ZIP engine.

        Unlike bsdtar-on-stdin, ZIP itself is treated as a seekable remote file.
        ZIP seeks become HTTP Range requests, while each sequential file read
        stays on one continuous HTTP response. The complete ZIP is never saved.
        This avoids libarchive's non-seekable ZIP/Zstd failure and supports ZIP
        Zstandard method 93 through Python 3.14/backports.zstd.
        """
        zstd_zipfile = get_zstd_zipfile_module()
        self.log.emit("Extraction engine: HTTP Range ZIP (seekable, Zstandard capable)")
        self.log.emit(
            "The archive stays remote. StreamExtract uses bounded HTTP Range read-ahead "
            "when the selected performance profile allows it; the complete ZIP is never "
            "saved before extraction."
        )

        self.destination.mkdir(parents=True, exist_ok=True)
        self._reset_rate_window(self.effective_rate())
        self._range_speed_window_started = time.monotonic()
        self._range_speed_window_bytes = 0
        self._range_last_speed = 0.0

        with self._make_http_client() as client:
            total = self._probe_remote_size(client)
            if self._archive_kind_cache not in ("UNKNOWN", "ZIP"):
                raise ArchiveNotZip(self._archive_kind_cache)
            if total <= 0:
                raise RangeZipUnavailable(
                    "The server did not expose the complete archive size through HTTP ranges."
                )

            def open_segment(start):
                ctx, response, new_total, segment_end = self._open_response(
                    client, total, int(start)
                )
                if new_total > 0 and new_total != total:
                    ctx.__exit__(None, None, None)
                    raise StreamTransportError(
                        "The remote archive changed size during extraction. "
                        "Generate a fresh download link and retry."
                    )
                return ctx, response, segment_end

            def account_network_bytes(byte_count):
                self._throttle_network_bytes(byte_count)
                self._note_range_bytes(byte_count)

            range_workers = self._smart_range_worker_count()
            if range_workers > 1:
                self.log.emit(
                    f"Range connections: {range_workers} (manual) • Smart Range acceleration on • "
                    f"{human_bytes(PARALLEL_RANGE_BLOCK_SIZE)} read-ahead blocks "
                    f"(bounded RAM cache; complete archive is never stored)."
                )

                def fetch_exact(start, end):
                    return self._fetch_exact_range(client, int(start), int(end), total)

                reader = HTTPParallelRangeReader(
                    total,
                    fetch_exact,
                    workers=range_workers,
                    block_size=PARALLEL_RANGE_BLOCK_SIZE,
                    cache_blocks=max(range_workers + 1, PARALLEL_RANGE_CACHE_BLOCKS),
                )
            else:
                self.log.emit(
                    "Range connections: 1 (manual) • continuous ZIP Range stream; "
                    "parallel read-ahead is off for smoother Current file progress."
                )
                reader = HTTPStreamingRangeReader(
                    total,
                    open_segment,
                    account_network_bytes,
                    network_chunk_size=RANGE_HTTP_CHUNK_SIZE,
                )
            try:
                zf = zstd_zipfile.ZipFile(reader, "r")
            except (UserCancelled, RangeZipUnavailable, StreamTransportError):
                raise
            except zstd_zipfile.BadZipFile as exc:
                raise ArchiveNotZip(self._archive_kind_cache) from exc
            except Exception as exc:
                raise RuntimeError(f"Could not read the ZIP central directory: {exc}") from exc

            with zf:
                infos = zf.infolist()
                if not infos:
                    raise RuntimeError("The ZIP archive contains no files.")

                total_unpacked = sum(
                    max(0, int(info.file_size or 0))
                    for info in infos if not info.is_dir()
                )
                progress_total = max(total_unpacked, 1)
                self._set_overall_total(
                    progress_total, f"ZIP central directory, {sum(1 for info in infos if not info.is_dir()):,} files"
                )

                supported = {0, 8, 12, 14, 93}
                methods = sorted({int(info.compress_type) for info in infos})
                unsupported = [m for m in methods if m not in supported]
                if unsupported:
                    raise RangeZipUnsupported(
                        "HTTP Range ZIP does not handle compression method(s) "
                        + ", ".join(str(m) for m in unsupported)
                        + "; a compatibility extractor is required."
                    )

                if 93 in methods:
                    self.log.emit(
                        "ZIP method 93 (Zstandard) detected — using the native "
                        "Python Zstandard ZIP decoder instead of bsdtar stdin."
                    )

                completed_unpacked = 0

                for info in infos:
                    self._check_cancel()
                    name = str(info.filename or "")
                    if not name:
                        continue
                    target = safe_member_path(self.destination, name)

                    if info.is_dir() or name.replace("\\", "/").endswith("/"):
                        target.mkdir(parents=True, exist_ok=True)
                        continue

                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() and not self.overwrite:
                        self.log.emit(f"Skipped existing: {name}")
                        completed_unpacked += max(0, int(info.file_size or 0))
                        self.download_progress.emit(
                            min(completed_unpacked, progress_total),
                            progress_total,
                            self._range_last_speed,
                        )
                        continue

                    expected = max(0, int(info.file_size or 0))
                    written = 0
                    part = target.with_name(target.name + ".streamextract.part")
                    self._active_part = part
                    try:
                        part.unlink(missing_ok=True)
                    except OSError:
                        pass

                    self.file_progress.emit(name, 0, expected)
                    self.log.emit(f"Extracting: {name}")

                    try:
                        with zf.open(info, "r", pwd=self.password) as source, open(part, "wb") as dest:
                            last_emit = time.monotonic()
                            while True:
                                self._check_cancel()
                                data = source.read(CHUNK_SIZE)
                                if not data:
                                    break
                                dest.write(data)
                                written += len(data)
                                now = time.monotonic()
                                overall_written = completed_unpacked + written
                                self.download_progress.emit(
                                    min(overall_written, progress_total),
                                    progress_total,
                                    self._range_last_speed,
                                )
                                if now - last_emit >= 0.10:
                                    self.file_progress.emit(name, written, expected)
                                    last_emit = now

                        self.file_progress.emit(name, written, expected)
                        if target.exists() and self.overwrite:
                            if target.is_dir():
                                shutil.rmtree(target)
                            else:
                                target.unlink()
                        os.replace(part, target)
                        self._active_part = None
                        completed_unpacked += expected
                        self.download_progress.emit(
                            min(completed_unpacked, progress_total),
                            progress_total,
                            self._range_last_speed,
                        )
                        self.log.emit(f"Done: {name} ({human_bytes(written)})")
                    except Exception:
                        self._cleanup_active_part()
                        raise

                self.download_progress.emit(progress_total, progress_total, self._range_last_speed)

    @staticmethod
    def _temp_zip_has_end_record(path: Path) -> bool:
        """Cheap completeness check: EOCD must live in the final ~64 KiB."""
        try:
            size = path.stat().st_size
            if size < 22:
                return False
            with open(path, "rb") as handle:
                handle.seek(max(0, size - 131072))
                tail = handle.read()
            return b"PK\x05\x06" in tail
        except Exception:
            return False

    def _resume_temp_archive(self, client, temp_path: Path):
        """Continue a cleanly-truncated proxy segment into the same temp ZIP."""
        cursor = temp_path.stat().st_size
        total = int(self._remote_size_cache or -1)
        started = time.monotonic()
        self._reset_rate_window(self.effective_rate())
        no_progress = 0

        with open(temp_path, "ab") as handle:
            while total <= 0 or cursor < total:
                self._check_cancel()
                before = cursor
                response_ctx, response, new_total, segment_end = self._open_response(
                    client, total, cursor
                )
                if new_total > 0:
                    total = int(new_total)
                    self._remote_size_cache = total
                    self._probe_attempted = True
                try:
                    for chunk in response.iter_raw(chunk_size=STREAM_HTTP_CHUNK_SIZE):
                        self._check_cancel()
                        if not chunk:
                            continue
                        if total > 0 and cursor + len(chunk) > total:
                            chunk = chunk[: max(0, total - cursor)]
                            if not chunk:
                                break
                        self._throttle_network_bytes(len(chunk))
                        handle.write(chunk)
                        cursor += len(chunk)
                        elapsed = max(time.monotonic() - started, 0.001)
                        self.download_progress.emit(cursor, total, cursor / elapsed)
                finally:
                    response_ctx.__exit__(None, None, None)

                if cursor == before:
                    no_progress += 1
                    if no_progress >= 3:
                        raise StreamTransportError(
                            "The download server accepted resume requests but returned no additional ZIP data."
                        )
                else:
                    no_progress = 0

                if total > 0 and cursor >= total:
                    break
                if total <= 0 and segment_end is None:
                    # We still do not know the full size. If the archive now has
                    # a valid end record, this clean EOF was the actual end.
                    handle.flush()
                    if self._temp_zip_has_end_record(temp_path):
                        break
                self.log.emit(
                    f"Compatibility download segment ended at {human_bytes(cursor)}; resuming…"
                )

        if not self._temp_zip_has_end_record(temp_path):
            raise StreamTransportError(
                "The source stopped before the ZIP end record and could not be resumed safely. "
                "Generate a fresh direct download link and retry."
            )

    def _extract_with_temp_seekable_archive(self, archive_kind: str = "ZIP"):
        """Seekable compatibility extraction for non-primary archive formats.

        ZIP and RAR are deliberately kept out of this path in StreamExtract v1.7:
        those primary formats must not silently consume space for a complete
        temporary source archive. This helper remains for formats such as 7z or
        other explicit compatibility cases.
        """
        archive_kind = (archive_kind or "UNKNOWN").upper()
        mode_name = "Reliable RAR/7z mode" if archive_kind in ("RAR4", "RAR5", "7Z") else "Compatibility mode"
        self.log.emit(
            f"{mode_name}: using one temporary seekable archive on the selected storage."
        )
        self.log.emit(
            f"Downloading temporary {archive_kind} archive once; it will be deleted automatically after extraction."
        )
        self.file_progress.emit(
            f"Downloading temporary {archive_kind} archive…", 0, -1
        )
        self.destination.mkdir(parents=True, exist_ok=True)
        ext = {"ZIP": "zip", "RAR4": "rar", "RAR5": "rar", "7Z": "7z"}.get(archive_kind, "archive")
        temp_path = self.destination.parent / (
            f".streamextract-archive-{os.getpid()}-{time.time_ns()}.{ext}.part"
        )
        self._active_archive = temp_path
        try:
            with self._make_http_client() as client:
                with open(temp_path, "wb") as handle:
                    for chunk in self._iter_resumable_response(client):
                        self._check_cancel()
                        handle.write(chunk)
                    handle.flush()
                    try:
                        os.fsync(handle.fileno())
                    except OSError:
                        pass

                if not temp_path.is_file() or temp_path.stat().st_size <= 0:
                    raise RuntimeError("The compatibility download produced an empty archive.")

                local_size = temp_path.stat().st_size
                expected_size = int(self._remote_size_cache or -1)
                if expected_size > 0 and local_size != expected_size:
                    raise StreamTransportError(
                        "The temporary archive did not reach the advertised remote size "
                        f"({human_bytes(local_size)} / {human_bytes(expected_size)})."
                    )

                self.file_progress.emit(
                    f"Temporary {archive_kind} archive ready — starting extraction…", 0, -1
                )
                self.log.emit(
                    f"Temporary {archive_kind} download complete ({human_bytes(local_size)}). Starting seekable extraction."
                )

                if archive_kind == "UNKNOWN":
                    try:
                        with open(temp_path, "rb") as sniff:
                            local_kind = detect_archive_kind(sniff.read(4096))
                        if local_kind == "UNKNOWN" and self._temp_zip_has_end_record(temp_path):
                            local_kind = "ZIP"
                        if local_kind != "UNKNOWN":
                            archive_kind = local_kind
                            self._archive_kind_cache = local_kind
                            self.log.emit(f"Detected local archive format: {local_kind}")
                    except Exception:
                        pass

                # ZIP has a cheap end-of-central-directory marker, so when
                # the proxy does not expose a trustworthy total we can still
                # catch the old fixed-segment (~73.6 MiB) truncation bug. RAR
                # and 7z are validated by the extractor instead.
                if archive_kind == "ZIP" and not self._temp_zip_has_end_record(temp_path):
                    self.log.emit(
                        "The first HTTP response ended before the ZIP directory. "
                        "Trying exact byte resume from the next byte…"
                    )
                    self._resume_temp_archive(client, temp_path)

            bsdtar = shutil.which("bsdtar")
            bsdtar_error = None
            if bsdtar:
                self.log.emit(
                    f"Extraction engine: seekable SteamOS libarchive file ({archive_kind})"
                )
                # This destination is a private per-job staging folder. A
                # seekable retry must be authoritative, so do not use `-k` here:
                # preserving files from an earlier failed streaming attempt can
                # make bsdtar fail again with "file exists" even after a perfect
                # re-download.
                cmd = [
                    bsdtar, "-xvf", str(temp_path),
                    "--safe-writes", "--no-same-owner", "--no-same-permissions",
                    "-C", str(self.destination),
                ]
                # bsdtar's documented --passphrase support is ZIP-specific.
                if self.password_text and archive_kind == "ZIP":
                    cmd.extend(["--passphrase", self.password_text])

                tail = []
                proc = subprocess.Popen(
                    cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                )
                self._active_process = proc
                self._read_process_output(proc.stdout, "bsdtar", tail)
                rc = proc.wait()
                self._active_process = None
                if rc == 0:
                    return
                detail = "\n".join(tail[-12:]).strip()
                bsdtar_error = (
                    "Seekable libarchive extraction failed."
                    + (f"\n\n{detail}" if detail else "")
                )
                self.log.emit(bsdtar_error)

            # Some SteamOS/Desktop installations also have 7z/7zz available.
            # It is a useful second RAR/7z decoder for archives libarchive does
            # not understand, especially newer or encrypted RAR variants.
            seven_zip = shutil.which("7zz") or shutil.which("7z") or shutil.which("7za")
            if seven_zip and archive_kind != "ZIP":
                self.log.emit(f"Trying 7-Zip compatibility extractor for {archive_kind}…")
                cmd = [
                    seven_zip, "x", str(temp_path),
                    f"-o{self.destination}", "-y",
                    "-aoa",
                ]
                if self.password_text:
                    cmd.append(f"-p{self.password_text}")
                tail = []
                proc = subprocess.Popen(
                    cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                )
                self._active_process = proc
                self._read_process_output(proc.stdout, "7z", tail)
                rc = proc.wait()
                self._active_process = None
                if rc == 0:
                    return
                detail = "\n".join(tail[-12:]).strip()
                raise RuntimeError(
                    f"7-Zip could not extract the {archive_kind} archive."
                    + (f"\n\n{detail}" if detail else "")
                )

            if archive_kind != "ZIP":
                if bsdtar_error:
                    raise RuntimeError(bsdtar_error)
                raise RuntimeError(
                    f"No installed extractor could open this {archive_kind} archive. "
                    "SteamOS bsdtar/libarchive (or 7z) is required."
                )

            # ZIP-only Python fallback keeps Zstandard method 93 working even
            # if libarchive is unavailable on a particular system.
            zstd_zipfile = get_zstd_zipfile_module()
            self.log.emit("Extraction engine: local seekable Python ZIP")
            with zstd_zipfile.ZipFile(temp_path, "r") as zf:
                for info in zf.infolist():
                    self._check_cancel()
                    name = str(info.filename or "")
                    if not name:
                        continue
                    target = safe_member_path(self.destination, name)
                    if info.is_dir() or name.replace("\\", "/").endswith("/"):
                        target.mkdir(parents=True, exist_ok=True)
                        continue
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() and not self.overwrite:
                        self.log.emit(f"Skipped existing: {name}")
                        continue
                    expected = max(0, int(info.file_size or 0))
                    written = 0
                    part = target.with_name(target.name + ".streamextract.part")
                    self._active_part = part
                    part.unlink(missing_ok=True)
                    self.file_progress.emit(name, 0, expected)
                    with zf.open(info, "r", pwd=self.password) as source, open(part, "wb") as dest:
                        while True:
                            self._check_cancel()
                            data = source.read(CHUNK_SIZE)
                            if not data:
                                break
                            dest.write(data)
                            written += len(data)
                            self.file_progress.emit(name, written, expected)
                    if target.exists() and self.overwrite:
                        if target.is_dir():
                            shutil.rmtree(target)
                        else:
                            target.unlink()
                    os.replace(part, target)
                    self._active_part = None
                    self.log.emit(f"Done: {name} ({human_bytes(written)})")
        finally:
            self._cleanup_active_part()
            self._cleanup_active_archive()

    def _extract_with_bsdtar(self, archive_kind: str = "archive"):
        """Stream an archive straight from HTTP into SteamOS libarchive.

        No complete RAR is ever written to disk. For the specific SteamOS
        libarchive/RAR5 stdin EOF bug, a non-zero exit is accepted only when
        the full advertised remote byte count was fed to bsdtar, at least one
        member was extracted, and the *only* diagnostics are the known
        `bsdtar: (null)` / delayed-error pair.
        """
        bsdtar = shutil.which("bsdtar")
        if not bsdtar:
            raise RuntimeError("SteamOS libarchive/bsdtar was not found.")

        archive_kind = (archive_kind or "archive").upper()
        self.log.emit(f"Extraction engine: SteamOS libarchive direct stream ({archive_kind})")
        self.log.emit("Efficiency path: 1 MiB sequential network reads + low-wakeup rate limiting")
        self.log.emit(
            f"The {archive_kind} archive is streamed directly into the extractor. "
            "The complete archive is NOT stored on disk."
        )

        self.destination.mkdir(parents=True, exist_ok=True)

        if archive_kind in ("RAR4", "RAR5"):
            # V1.27: do not block the start of large signed/proxy RAR downloads
            # with a remote random-seek header scan. Some hosts make that scan
            # appear frozen for many minutes. Start the proven sequential RAR
            # stream immediately; progress uses the remote archive byte count.
            self.log.emit("RAR direct-stream mode: starting extraction immediately (header pre-scan disabled).")

        cmd = [
            bsdtar,
            "-xvf", "-",
            "--safe-writes",
            "--no-same-owner",
            "--no-same-permissions",
            "-C", str(self.destination),
        ]

        if not self.overwrite:
            cmd.insert(3, "-k")

        if self.password_text and archive_kind == "ZIP":
            cmd.extend(["--passphrase", self.password_text])

        tail: list[str] = []
        stats = {"members": 0, "diagnostics": []}
        fed_bytes = 0
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=256 * 1024,
        )
        self._active_process = proc

        stdout_thread = threading.Thread(
            target=self._read_process_output,
            args=(proc.stdout, "bsdtar", tail, stats, False),
            daemon=True,
        )
        stderr_thread = threading.Thread(
            target=self._read_process_output,
            args=(proc.stderr, "bsdtar", tail, stats, True),
            daemon=True,
        )
        stdout_thread.start()
        stderr_thread.start()

        try:
            pipe_broken = False
            with self._make_http_client() as client:
                try:
                    for chunk in self._iter_resumable_response(client):
                        self._check_cancel()
                        if proc.poll() is not None:
                            pipe_broken = True
                            break
                        try:
                            view = memoryview(chunk)
                            while view:
                                written = proc.stdin.write(view)
                                if written is None:
                                    written = len(view)
                                if written <= 0:
                                    raise BrokenPipeError()
                                fed_bytes += int(written)
                                view = view[written:]
                        except (BrokenPipeError, OSError):
                            pipe_broken = True
                            break
                finally:
                    try:
                        if proc.stdin:
                            proc.stdin.close()
                    except Exception:
                        pass

            if self._cancel.is_set():
                raise UserCancelled()

            return_code = proc.wait()
            stdout_thread.join(timeout=2)
            stderr_thread.join(timeout=2)

            if return_code == 0:
                return

            expected = int(self._remote_size_cache or -1)
            full_stream = expected > 0 and fed_bytes == expected and not pipe_broken
            diagnostics = list(stats.get("diagnostics") or [])
            member_count = int(stats.get("members", 0) or 0)

            if (
                archive_kind in ("RAR4", "RAR5")
                and full_stream
                and member_count > 0
                and self._rar_bsdtar_benign_eof_only(diagnostics)
            ):
                verified = self._verify_rar_extracted_payload()
                if verified is not False:
                    verify_note = (
                        " Extracted output also matched the RAR header scan exactly."
                        if verified is True
                        else " Header-scan verification was unavailable, so the byte-complete stream and diagnostic whitelist were used."
                    )
                    self.log.emit(
                        "RAR stream reached the advertised end byte-for-byte. "
                        "SteamOS libarchive reported only its known harmless EOF `(null)` "
                        "diagnostic, so the already extracted files are accepted as complete."
                        + verify_note
                    )
                    self._emit_transport_progress(fed_bytes, expected, 0.0)
                    return
                self.log.emit(
                    "The RAR reached the advertised end, but extracted-output verification failed; "
                    "the non-zero bsdtar result remains fatal."
                )

            detail = "\n".join(tail[-12:]).strip()
            completeness = (
                f" Received {human_bytes(fed_bytes)} / {human_bytes(expected)}."
                if expected > 0
                else f" Received {human_bytes(fed_bytes)} before the extractor stopped."
            )
            raise RuntimeError(
                f"libarchive/bsdtar could not safely finish this {archive_kind} stream."
                + completeness
                + (f"\n\n{detail}" if detail else "")
            )
        finally:
            self._active_process = None
            if proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=2)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass

    def _extract_with_stream_unzip(self):
        """Compatibility fallback for ZIP layouts stream-unzip handles better."""
        self.log.emit("Extraction engine: stream-unzip compatibility fallback")

        with self._make_http_client() as client:
            incoming_chunks = self._iter_resumable_response(client)

            for raw_name, file_size, unzipped_chunks in stream_unzip(
                incoming_chunks,
                password=self.password,
                chunk_size=CHUNK_SIZE,
            ):
                    self._check_cancel()
                    name = decode_zip_name(raw_name)

                    if name.replace("\\", "/").endswith("/"):
                        directory = safe_member_path(self.destination, name)
                        directory.mkdir(parents=True, exist_ok=True)
                        for _ in unzipped_chunks:
                            self._check_cancel()
                        continue

                    target = safe_member_path(self.destination, name)
                    target.parent.mkdir(parents=True, exist_ok=True)

                    if target.exists() and not self.overwrite:
                        self.log.emit(f"Skipped existing: {name}")
                        for _ in unzipped_chunks:
                            self._check_cancel()
                        continue

                    expected = file_size if file_size is not None else -1
                    written = 0
                    part = target.with_name(
                        target.name + ".streamextract.part"
                    )
                    self._active_part = part

                    if part.exists():
                        try:
                            part.unlink()
                        except OSError:
                            pass

                    self.file_progress.emit(name, 0, expected)
                    self.log.emit(f"Extracting: {name}")

                    try:
                        with open(part, "wb") as f:
                            last_file_emit = time.monotonic()
                            for out_chunk in unzipped_chunks:
                                self._check_cancel()
                                f.write(out_chunk)
                                written += len(out_chunk)
                                now = time.monotonic()
                                if now - last_file_emit >= 0.10:
                                    self.file_progress.emit(
                                        name, written, expected
                                    )
                                    last_file_emit = now

                        self.file_progress.emit(name, written, expected)
                        if target.exists() and self.overwrite:
                            target.unlink()
                        os.replace(part, target)
                        self._active_part = None
                        self.log.emit(
                            f"Done: {name} ({human_bytes(written)})"
                        )
                    except Exception:
                        self._cleanup_active_part()
                        raise

    def run(self):
        try:
            self.destination.mkdir(parents=True, exist_ok=True)
            self.log.emit(f"Destination: {self.destination}")

            if self.base_rate_bps:
                self.log.emit(
                    f"Base performance: {self.performance_mode} "
                    f"({human_bytes(self.base_rate_bps)}/s)"
                )
            else:
                self.log.emit("Base performance: Maximum speed")

            if self._thermal_enabled:
                self.log.emit(
                    f"Automatic thermal protection: ON at "
                    f"{self._thermal_threshold}°C"
                )

            # V1.0: use a seekable HTTP-range ZIP reader first. ZIP archives
            # keep their authoritative directory at the end, and libarchive has
            # known problems with some ZIPs (especially Zstd/method 93) when the
            # archive is supplied through non-seekable stdin. HTTP Range gives
            # us true random access without ever saving the full ZIP.
            try:
                self._extract_with_http_range_zip()
            except UserCancelled:
                raise
            except ArchiveNotZip as archive_exc:
                archive_kind = archive_exc.archive_kind
                self._cleanup_active_part()

                if archive_kind in ("RAR4", "RAR5"):
                    self.log.emit(
                        f"Detected archive format: {archive_kind}. Switching to true direct-stream extraction."
                    )
                    try:
                        self._extract_with_bsdtar(archive_kind)
                    except Exception as rar_exc:
                        raise RuntimeError(
                            f"{archive_kind} streaming extraction failed. StreamExtract did NOT "
                            "download or keep a full temporary RAR archive. "
                            f"Details: {rar_exc}"
                        ) from rar_exc
                elif archive_kind == "7Z":
                    # 7z is not one of StreamExtract's advertised primary formats.
                    # Keep the existing compatibility path for now.
                    self.log.emit(
                        "7Z archive detected — using seekable compatibility extraction."
                    )
                    self._extract_with_temp_seekable_archive(archive_kind)
                else:
                    self.log.emit(
                        f"{archive_kind} archive detected — switching to multi-format extraction."
                    )
                    self._extract_with_temp_seekable_archive(archive_kind)
            except RangeZipUnsupported as range_exc:
                self.log.emit(str(range_exc))
                self.log.emit("Trying sequential ZIP streaming without storing the full archive.")
                self._cleanup_active_part()
                try:
                    self._extract_with_stream_unzip()
                except Exception as stream_exc:
                    raise RuntimeError(
                        "Neither the HTTP Range ZIP engine nor the sequential ZIP engine "
                        "can decode this archive layout. StreamExtract intentionally did "
                        "NOT download a full temporary ZIP. "
                        f"Details: {type(stream_exc).__name__}: {stream_exc}"
                    ) from stream_exc
            except RangeZipUnavailable as range_exc:
                self.log.emit(
                    "Seekable HTTP Range mode is unavailable for this link: "
                    + str(range_exc)
                )
                self._cleanup_active_part()

                # StreamExtract's storage contract is strict for ZIP/RAR: never
                # silently cache the whole source archive just to gain seekability.
                # If the early probe already identified RAR, use libarchive stdin.
                if self._archive_kind_cache in ("RAR4", "RAR5"):
                    self.log.emit(
                        f"Range support is not needed for {self._archive_kind_cache}; "
                        "switching to direct archive streaming."
                    )
                    self._extract_with_bsdtar(self._archive_kind_cache)
                else:
                    self.log.emit(
                        "Trying sequential ZIP streaming without storing the full archive."
                    )
                    try:
                        self._extract_with_stream_unzip()
                    except Exception as stream_exc:
                        raise RuntimeError(
                            "This server does not provide the random HTTP ranges required "
                            "for this ZIP layout, and the sequential ZIP engine could not "
                            "extract it. StreamExtract intentionally did NOT download a full "
                            f"temporary archive. Details: {type(stream_exc).__name__}: {stream_exc}"
                        ) from stream_exc

            self.log.emit(
                "Download and extraction completed successfully."
            )
            self.finished.emit()

        except UserCancelled:
            self._cleanup_active_part()
            self._cleanup_active_archive()
            self.log.emit("Cancelled.")
            self.cancelled.emit()
        except httpx.HTTPStatusError as exc:
            self._cleanup_active_archive()
            self.failed.emit(
                f"HTTP error {exc.response.status_code}: "
                f"{exc.response.reason_phrase}"
            )
        except httpx.RequestError as exc:
            self._cleanup_active_archive()
            self.failed.emit(f"Network error: {exc}")
        except UnzipError as exc:
            self._cleanup_active_archive()
            self.failed.emit(
                "The ZIP could not be streamed/extracted.\n\n"
                f"{type(exc).__name__}: {exc}"
            )
        except ValueError as exc:
            self._cleanup_active_archive()
            self.failed.emit(f"Blocked unsafe ZIP path:\n{exc}")
        except Exception as exc:
            self._cleanup_active_archive()
            self.failed.emit(f"{type(exc).__name__}: {exc}")


def _clean_download_filename(value: str, fallback: str) -> str:
    """Return a safe basename while preserving multipart suffixes exactly."""
    raw = unquote(str(value or "")).replace("\\", "/").split("/")[-1].strip()
    raw = raw.replace("\x00", "").strip(" .")
    if not raw or raw in {".", ".."}:
        raw = fallback
    # Linux permits many characters, but control characters are a bad idea for
    # extractor command lines and logs. Keep normal release punctuation/spaces.
    raw = re.sub(r"[\x00-\x1f\x7f]", "_", raw)
    return raw[:240] or fallback


def _content_disposition_filename(header: str | None) -> str:
    text = str(header or "")
    if not text:
        return ""
    # RFC 5987 form wins when present.
    match = re.search(r"(?i)filename\*\s*=\s*(?:UTF-8'')?([^;]+)", text)
    if match:
        return unquote(match.group(1).strip().strip('"'))
    match = re.search(r"(?i)filename\s*=\s*(?:\"([^\"]+)\"|([^;]+))", text)
    if match:
        return (match.group(1) or match.group(2) or "").strip()
    return ""


def _multipart_layout(names: list[str]) -> dict:
    """Validate one common split-archive naming set and choose its entry."""
    if len(names) < 2:
        return {"ok": False, "error": "At least two archive parts are required."}

    lowered = [str(name).casefold() for name in names]
    if len(set(lowered)) != len(lowered):
        return {"ok": False, "error": "Two links resolve to the same archive filename."}

    # Modern RAR: Game.part1.rar / Game.part01.rar / Game.part001.rar
    rar_matches = [re.match(r"(?i)^(.*?)(?:[._ -]?part[._ -]?)(\d+)\.rar$", n) for n in names]
    if all(rar_matches):
        bases = [m.group(1).rstrip(" ._- ").casefold() for m in rar_matches]
        nums = [int(m.group(2)) for m in rar_matches]
        if len(set(bases)) == 1:
            ordered = sorted(range(len(names)), key=lambda i: nums[i])
            seq = [nums[i] for i in ordered]
            if seq and seq[0] == 1 and seq == list(range(1, len(seq) + 1)):
                return {
                    "ok": True, "kind": "RAR multipart", "order": ordered,
                    "entry_index": ordered[0], "parts": seq,
                }
            missing = next((x for x in range(1, max(seq or [0]) + 1) if x not in seq), None)
            return {"ok": False, "error": f"RAR multipart set is incomplete; part {missing or 1} appears to be missing."}

    # 7-Zip / ZIP / generic split volumes: Game.7z.001, Game.zip.001 or Game.001
    numeric_matches = [re.match(r"(?i)^(.*?)(?:\.(7z|zip))?\.(\d{3,})$", n) for n in names]
    if all(numeric_matches):
        prefixes = [((m.group(1) or "") + (f".{m.group(2)}" if m.group(2) else "")).casefold() for m in numeric_matches]
        nums = [int(m.group(3)) for m in numeric_matches]
        if len(set(prefixes)) == 1:
            ordered = sorted(range(len(names)), key=lambda i: nums[i])
            seq = [nums[i] for i in ordered]
            if seq and seq[0] == 1 and seq == list(range(1, len(seq) + 1)):
                ext = (numeric_matches[0].group(2) or "split").upper()
                return {
                    "ok": True, "kind": f"{ext} split archive", "order": ordered,
                    "entry_index": ordered[0], "parts": seq,
                }
            missing = next((x for x in range(1, max(seq or [0]) + 1) if x not in seq), None)
            return {"ok": False, "error": f"Split archive is incomplete; volume {missing or 1:03d} appears to be missing."}

    # Classic split ZIP: Game.z01, Game.z02, ..., Game.zip.
    zip_main = [(i, re.match(r"(?i)^(.*?)\.zip$", n)) for i, n in enumerate(names)]
    zip_main = [(i, m) for i, m in zip_main if m]
    z_parts = [(i, re.match(r"(?i)^(.*?)\.z(\d+)$", n)) for i, n in enumerate(names)]
    z_parts = [(i, m) for i, m in z_parts if m]
    if len(zip_main) == 1 and len(z_parts) == len(names) - 1:
        main_i, main_m = zip_main[0]
        base = main_m.group(1).casefold()
        if all(m.group(1).casefold() == base for _, m in z_parts):
            nums = sorted(int(m.group(2)) for _, m in z_parts)
            if nums == list(range(1, len(nums) + 1)):
                ordered_z = [i for i, m in sorted(z_parts, key=lambda item: int(item[1].group(2)))]
                return {
                    "ok": True, "kind": "ZIP split archive", "order": ordered_z + [main_i],
                    "entry_index": main_i, "parts": nums + [len(nums) + 1],
                }
            missing = next((x for x in range(1, max(nums or [0]) + 1) if x not in nums), None)
            return {"ok": False, "error": f"ZIP split set is incomplete; .z{missing or 1:02d} appears to be missing."}

    # Classic RAR: Game.rar + Game.r00 + Game.r01 ...
    rar_main = [(i, re.match(r"(?i)^(.*?)\.rar$", n)) for i, n in enumerate(names)]
    rar_main = [(i, m) for i, m in rar_main if m]
    r_parts = [(i, re.match(r"(?i)^(.*?)\.r(\d+)$", n)) for i, n in enumerate(names)]
    r_parts = [(i, m) for i, m in r_parts if m]
    if len(rar_main) == 1 and len(r_parts) == len(names) - 1:
        main_i, main_m = rar_main[0]
        base = main_m.group(1).casefold()
        if all(m.group(1).casefold() == base for _, m in r_parts):
            nums = sorted(int(m.group(2)) for _, m in r_parts)
            if nums == list(range(0, len(nums))):
                ordered_r = [i for i, m in sorted(r_parts, key=lambda item: int(item[1].group(2)))]
                return {
                    "ok": True, "kind": "RAR classic multipart", "order": [main_i] + ordered_r,
                    "entry_index": main_i, "parts": [0] + nums,
                }
            missing = next((x for x in range(0, max(nums or [0]) + 1) if x not in nums), None)
            return {"ok": False, "error": f"Classic RAR set is incomplete; .r{missing or 0:02d} appears to be missing."}

    return {"ok": False, "error": "The files are not one supported continuous split archive."}


def _archive_name_looks_update(name: str) -> bool:
    """Conservatively recognize an archive set clearly named as an update/patch."""
    text = str(name or "").casefold()
    return bool(re.search(
        r"(?:^|[^a-z])(update|patch|hotfix|upgrade|fixpack|title[ ._-]*update)(?:\d|[^a-z]|$)",
        text,
    ))


def _batch_archive_layout(names: list[str]) -> dict:
    """Group pasted links into one base multipart set plus safe follow-ups.

    Multiple multipart sets are accepted only when exactly one set is a clear
    base and every other multipart set is clearly named as an update/patch/
    hotfix/upgrade. Ambiguous layouts are still rejected rather than guessed.
    """
    if len(names) < 2:
        return {"ok": False, "error": "At least two links are required for multi-link mode."}
    lowered = [str(x).casefold() for x in names]
    if len(set(lowered)) != len(lowered):
        return {"ok": False, "error": "Two links resolve to the same archive filename."}

    used: set[int] = set()
    groups: list[dict] = []

    def add_group(indices: list[int], label: str):
        subset = [names[i] for i in indices]
        layout = _multipart_layout(subset)
        if not layout.get("ok"):
            raise ValueError(str(layout.get("error") or f"Invalid {label} set."))
        # Convert subset-local indexes back to original meta indexes.
        order = [indices[int(i)] for i in layout["order"]]
        entry = indices[int(layout["entry_index"])]
        groups.append({
            "multipart": True,
            "kind": str(layout["kind"]),
            "indices": list(indices),
            "order": order,
            "entry_index": entry,
            "name": names[entry],
        })
        used.update(indices)

    # Modern .partN.rar sets.
    modern: dict[str, list[int]] = {}
    for i, name in enumerate(names):
        m = re.match(r"(?i)^(.*?)(?:[._ -]?part[._ -]?)(\d+)\.rar$", name)
        if m:
            modern.setdefault(m.group(1).rstrip(" ._- ").casefold(), []).append(i)
    for _base, indices in modern.items():
        add_group(indices, "RAR multipart")

    # Numeric split sets (.7z.001 / .zip.001 / generic .001).
    numeric: dict[str, list[int]] = {}
    for i, name in enumerate(names):
        if i in used:
            continue
        m = re.match(r"(?i)^(.*?)(?:\.(7z|zip))?\.(\d{3,})$", name)
        if m:
            key = ((m.group(1) or "") + (f".{m.group(2)}" if m.group(2) else "")).casefold()
            numeric.setdefault(key, []).append(i)
    for _base, indices in numeric.items():
        add_group(indices, "numeric split archive")

    # Classic ZIP .z01 + .zip.
    z_by_base: dict[str, list[int]] = {}
    zip_by_base: dict[str, int] = {}
    for i, name in enumerate(names):
        if i in used:
            continue
        m = re.match(r"(?i)^(.*?)\.z(\d+)$", name)
        if m:
            z_by_base.setdefault(m.group(1).casefold(), []).append(i)
            continue
        m = re.match(r"(?i)^(.*?)\.zip$", name)
        if m:
            zip_by_base[m.group(1).casefold()] = i
    for base, z_indices in z_by_base.items():
        if base not in zip_by_base:
            raise ValueError(f"ZIP split set '{names[z_indices[0]]}' is missing its final .zip volume.")
        add_group(z_indices + [zip_by_base[base]], "ZIP split archive")

    # Classic RAR .rar + .r00/.r01.
    r_by_base: dict[str, list[int]] = {}
    rar_by_base: dict[str, int] = {}
    for i, name in enumerate(names):
        if i in used:
            continue
        m = re.match(r"(?i)^(.*?)\.r(\d+)$", name)
        if m:
            r_by_base.setdefault(m.group(1).casefold(), []).append(i)
            continue
        m = re.match(r"(?i)^(.*?)\.rar$", name)
        if m:
            rar_by_base[m.group(1).casefold()] = i
    for base, r_indices in r_by_base.items():
        if base not in rar_by_base:
            raise ValueError(f"Classic RAR set '{names[r_indices[0]]}' is missing its .rar entry volume.")
        add_group([rar_by_base[base]] + r_indices, "classic RAR archive")

    # Anything left must be a normal independent archive, not an orphan volume.
    standalone_exts = (".rar", ".zip", ".7z", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2")
    extras = []
    for i, name in enumerate(names):
        if i in used:
            continue
        low = name.casefold()
        if re.search(r"(?i)(?:[._ -]?part[._ -]?)(\d+)\.rar$", name) or re.search(r"(?i)\.(?:7z|zip)?\.?(\d{3,})$", name) or re.search(r"(?i)\.[zr]\d+$", name):
            raise ValueError(f"'{name}' looks like an archive volume but does not have a complete matching set.")
        if not low.endswith(standalone_exts):
            raise ValueError(f"'{name}' is not a supported standalone archive in multi-link mode.")
        extras.append({
            "multipart": False,
            "kind": "Standalone archive",
            "indices": [i],
            "order": [i],
            "entry_index": i,
            "name": name,
        })

    multipart_groups = [g for g in groups if g.get("multipart")]
    if not multipart_groups:
        return {
            "ok": False,
            "error": (
                "The pasted links are separate archives, not one split archive. "
                "For safety, multi-link automatic installation currently needs one clear multipart base set."
            ),
        }

    multipart_followups: list[dict] = []
    if len(multipart_groups) == 1:
        primary = multipart_groups[0]
    else:
        update_groups = [
            g for g in multipart_groups
            if _archive_name_looks_update(str(g.get("name") or ""))
        ]
        base_groups = [g for g in multipart_groups if g not in update_groups]

        # Safe automatic case: exactly one multipart set does not look like an
        # update, while every other multipart set clearly does. Never guess the
        # base from size or number of volumes alone.
        if len(base_groups) == 1 and len(update_groups) == len(multipart_groups) - 1:
            primary = base_groups[0]
            multipart_followups = sorted(
                update_groups,
                key=lambda g: min(int(i) for i in (g.get("indices") or [10**9])),
            )
        else:
            detail = ", ".join(str(g.get("name") or "multipart set") for g in multipart_groups)
            return {
                "ok": False,
                "error": (
                    "More than one independent multipart archive set was detected, and Moses could not "
                    "safely identify exactly one base set plus clearly named update/patch sets. "
                    "Please run ambiguous sets separately. Detected sets: " + detail
                ),
            }

    followups = multipart_followups + extras
    return {
        "ok": True,
        "primary": primary,
        "extras": followups,
        "groups": [primary] + followups,
        "mixed": bool(followups),
        "multipart_followups": multipart_followups,
    }


def _safe_followup_folder_name(name: str, fallback: str) -> str:
    text = str(name or fallback)
    # Strip multipart volume suffixes so a 3-part update becomes one clean
    # follow-up folder name rather than ending in ``part1``.
    text = re.sub(r"(?i)(?:[._ -]?part[._ -]?\d+)\.rar$", "", text).strip()
    text = re.sub(r"(?i)(?:\.(?:7z|zip))?\.\d{3,}$", "", text).strip()
    text = re.sub(r"(?i)\.(?:rar|zip|7z|tar|gz|xz|bz2|tgz|txz|tbz2)$", "", text).strip()
    text = re.sub(r"[\\/:*?\"<>|\x00-\x1f]+", "_", text).strip(" ._")
    return (text[:120] or fallback)


class MultiPartDownloadWorker(DownloadWorker):
    """Reliable multi-link mode for a split base archive plus optional extras."""

    def __init__(self, urls: list[str], multipart_parallel: int, **kwargs):
        urls = [str(u).strip() for u in urls if str(u).strip()]
        if len(urls) < 2:
            raise ValueError("Multi-link mode needs at least two URLs.")
        super().__init__(url=urls[0], **kwargs)
        self.urls = urls
        self.multipart_parallel = max(1, min(int(multipart_parallel or 1), MULTIPART_MAX_PARALLEL))
        # The executor always owns up to 10 lightweight tasks, while this gate
        # controls how many files may actively transfer at once. This makes the
        # 1-10 GUI dropdown genuinely live: increasing the value releases queued
        # files immediately; decreasing it never aborts a transfer already in
        # progress and simply prevents new ones from starting until the active
        # count falls below the new limit.
        self._parallel_condition = threading.Condition()
        self._parallel_active = 0
        self._multipart_dir: Path | None = None
        self._progress_lock = threading.Lock()
        self._part_downloaded: dict[int, int] = {}
        self._part_totals: dict[int, int] = {}
        self._multipart_started = time.monotonic()

    def _cleanup_multipart_dir(self):
        path = self._multipart_dir
        self._multipart_dir = None
        if path and path.exists():
            try:
                shutil.rmtree(path)
            except OSError:
                pass

    def set_multipart_parallel(self, value: int):
        value = max(1, min(int(value or 1), MULTIPART_MAX_PARALLEL))
        with self._parallel_condition:
            old = int(self.multipart_parallel)
            self.multipart_parallel = value
            self._parallel_condition.notify_all()
        if value != old:
            if value > old:
                self.log.emit(f"Multi-link downloads changed live: up to {value} simultaneous file(s). Queued downloads can start now.")
            else:
                self.log.emit(
                    f"Multi-link downloads changed live: up to {value} simultaneous file(s). "
                    "Active transfers will finish safely; the lower limit applies to the next queued file(s)."
                )

    def _acquire_parallel_slot(self):
        while True:
            self._check_cancel()
            with self._parallel_condition:
                if self._parallel_active < self.multipart_parallel:
                    self._parallel_active += 1
                    return
                self._parallel_condition.wait(timeout=0.25)

    def _release_parallel_slot(self):
        with self._parallel_condition:
            self._parallel_active = max(0, int(self._parallel_active) - 1)
            self._parallel_condition.notify_all()

    def _probe_part(self, index: int, url: str) -> dict:
        fallback = _clean_download_filename(Path(unquote(urlparse(url).path)).name, f"file-{index + 1:02d}.archive")
        headers = {"Range": "bytes=0-0", "Accept-Encoding": "identity"}
        last_error = ""
        with self._make_http_client() as client:
            for attempt in range(HTTP_MAX_STATUS_RETRIES):
                self._check_cancel()
                try:
                    with client.stream("GET", url, headers=headers) as response:
                        status = int(response.status_code)
                        if self._retryable_status(status):
                            delay = self._retry_delay(response, attempt)
                            last_error = f"HTTP {status}"
                        elif status in (200, 206):
                            cd_name = _content_disposition_filename(response.headers.get("Content-Disposition"))
                            final_name = Path(unquote(urlparse(str(response.url)).path)).name
                            name = _clean_download_filename(cd_name or final_name or fallback, fallback)
                            total = -1
                            if status == 206:
                                total = int(self._parse_content_range_total(response.headers.get("Content-Range")) or -1)
                            if total <= 0:
                                length = str(response.headers.get("Content-Length") or "")
                                if status == 200 and length.isdigit():
                                    total = int(length)
                            return {"index": index, "url": url, "name": name, "total": total}
                        else:
                            response.raise_for_status()
                            raise RuntimeError(f"HTTP {status}")
                except UserCancelled:
                    raise
                except (httpx.RequestError, httpx.HTTPStatusError, RuntimeError) as exc:
                    last_error = str(exc)
                    delay = min(0.5 * (2 ** attempt), 5.0)
                if attempt + 1 < HTTP_MAX_STATUS_RETRIES:
                    time.sleep(delay)
        raise StreamTransportError(f"Could not inspect multi-link item {index + 1}: {last_error or 'no response'}")

    def _download_one_part(self, meta: dict, local_path: Path, ordinal: int, count: int):
        self._acquire_parallel_slot()
        try:
            return self._download_one_part_active(meta, local_path, ordinal, count)
        finally:
            self._release_parallel_slot()

    def _download_one_part_active(self, meta: dict, local_path: Path, ordinal: int, count: int):
        url = str(meta["url"])
        expected = int(meta.get("total") or -1)
        local_path.parent.mkdir(parents=True, exist_ok=True)
        part_tmp = local_path.with_name(local_path.name + ".download")
        part_tmp.unlink(missing_ok=True)
        downloaded = 0
        attempt = 0
        no_progress_retries = 0

        while expected <= 0 or downloaded < expected:
            self._check_cancel()
            headers = {"Accept-Encoding": "identity"}
            if downloaded > 0:
                headers["Range"] = f"bytes={downloaded}-"
            try:
                with self._make_http_client() as client:
                    with client.stream("GET", url, headers=headers) as response:
                        status = int(response.status_code)
                        if downloaded > 0 and status == 200:
                            downloaded = 0
                            part_tmp.unlink(missing_ok=True)
                        elif downloaded > 0 and status != 206:
                            response.raise_for_status()
                        elif downloaded == 0 and status not in (200, 206):
                            response.raise_for_status()

                        if expected <= 0:
                            if status == 206:
                                expected = int(self._parse_content_range_total(response.headers.get("Content-Range")) or -1)
                            if expected <= 0:
                                length = str(response.headers.get("Content-Length") or "")
                                if length.isdigit():
                                    expected = downloaded + int(length) if status == 206 else int(length)
                            if expected > 0:
                                with self._progress_lock:
                                    self._part_totals[int(meta["index"])] = expected

                        mode = "ab" if downloaded > 0 else "wb"
                        before = downloaded
                        with open(part_tmp, mode) as handle:
                            for chunk in response.iter_raw(chunk_size=STREAM_HTTP_CHUNK_SIZE):
                                self._check_cancel()
                                if not chunk:
                                    continue
                                self._throttle_network_bytes(len(chunk))
                                handle.write(chunk)
                                downloaded += len(chunk)
                                with self._progress_lock:
                                    self._part_downloaded[int(meta["index"])] = downloaded
                                    aggregate = sum(self._part_downloaded.values())
                                    known_totals = list(self._part_totals.values())
                                    aggregate_total = sum(known_totals) if len(known_totals) == len(self.urls) and all(x > 0 for x in known_totals) else -1
                                    elapsed = max(time.monotonic() - self._multipart_started, 0.001)
                                    speed = aggregate / elapsed
                                self.download_progress.emit(aggregate, aggregate_total, speed)
                                self.file_progress.emit(
                                    f"Downloading file {ordinal} of {count}: {local_path.name}",
                                    downloaded, expected,
                                )
                            handle.flush()
                            try:
                                os.fsync(handle.fileno())
                            except OSError:
                                pass

                        if expected > 0 and downloaded >= expected:
                            break
                        if downloaded == before:
                            no_progress_retries += 1
                            if no_progress_retries >= 3:
                                raise StreamTransportError(
                                    f"File {ordinal} stopped at {human_bytes(downloaded)} and could not be resumed."
                                )
                        else:
                            no_progress_retries = 0
                        attempt = 0
                        self.log.emit(
                            f"File {ordinal}/{count} connection ended at {human_bytes(downloaded)}; resuming…"
                        )
                        continue
            except UserCancelled:
                raise
            except (httpx.RequestError, httpx.HTTPStatusError, StreamTransportError) as exc:
                attempt += 1
                if attempt >= HTTP_MAX_STATUS_RETRIES:
                    raise StreamTransportError(f"File {ordinal}/{count} failed: {exc}") from exc
                delay = min(0.5 * (2 ** (attempt - 1)), 5.0)
                self.log.emit(f"File {ordinal}/{count} interrupted; retrying in {delay:.1f}s…")
                time.sleep(delay)

            if expected <= 0:
                break

        if expected > 0 and downloaded != expected:
            raise StreamTransportError(
                f"File {ordinal}/{count} was incomplete ({human_bytes(downloaded)} / {human_bytes(expected)})."
            )
        if downloaded <= 0 or not part_tmp.is_file():
            raise StreamTransportError(f"File {ordinal}/{count} downloaded no data.")
        os.replace(part_tmp, local_path)
        self.log.emit(f"Downloaded file {ordinal}/{count}: {local_path.name} ({human_bytes(downloaded)})")
        return downloaded

    def _extract_local_archive(self, entry_path: Path, kind: str, output_dir: Path, volume_count: int):
        self._check_cancel()
        output_dir.mkdir(parents=True, exist_ok=True)
        self.file_progress.emit(f"Extracting {kind}: {entry_path.name}…", 0, -1)
        self.log.emit(
            f"Extracting {kind} from {entry_path.name}"
            + (f" ({volume_count} volumes)" if volume_count > 1 else "")
            + f" → {output_dir}"
        )

        seven_zip = shutil.which("7zz") or shutil.which("7z") or shutil.which("7za")
        errors = []
        if seven_zip:
            cmd = [seven_zip, "x", str(entry_path), f"-o{output_dir}", "-y", "-aoa"]
            if self.password_text:
                cmd.append(f"-p{self.password_text}")
            tail = []
            self.log.emit("Archive extraction engine: 7-Zip")
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self._active_process = proc
            self._read_process_output(proc.stdout, "7z", tail)
            rc = proc.wait()
            self._active_process = None
            if rc == 0:
                return
            errors.append("7-Zip failed" + (f": {' | '.join(tail[-8:])}" if tail else ""))

        bsdtar = shutil.which("bsdtar")
        if bsdtar:
            cmd = [
                bsdtar, "-xvf", str(entry_path),
                "--safe-writes", "--no-same-owner", "--no-same-permissions",
                "-C", str(output_dir),
            ]
            if self.password_text and (entry_path.name.casefold().endswith(".zip") or kind.casefold().startswith("zip")):
                cmd.extend(["--passphrase", self.password_text])
            tail = []
            self.log.emit("Trying SteamOS libarchive/bsdtar fallback…")
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self._active_process = proc
            self._read_process_output(proc.stdout, "bsdtar", tail)
            rc = proc.wait()
            self._active_process = None
            if rc == 0:
                return
            errors.append("bsdtar failed" + (f": {' | '.join(tail[-8:])}" if tail else ""))

        if not seven_zip and not bsdtar:
            raise RuntimeError("No archive extractor was found. SteamOS 7-Zip or bsdtar/libarchive is required.")
        raise RuntimeError(
            f"'{entry_path.name}' could not be extracted. Make sure its archive data is complete and not damaged.\n\n"
            + "\n".join(errors[-2:])
        )

    def run(self):
        try:
            self.destination.mkdir(parents=True, exist_ok=True)
            self.log.emit(f"Destination: {self.destination}")
            self.log.emit(f"Multi-link mode: {len(self.urls)} links • up to {self.multipart_parallel} simultaneous download(s)")
            self.log.emit("Reliable multi-link mode stores compressed inputs temporarily, extracts them, then deletes those compressed inputs.")

            metas = []
            for index, url in enumerate(self.urls):
                self._check_cancel()
                self.file_progress.emit(f"Checking link {index + 1} of {len(self.urls)}…", 0, -1)
                meta = self._probe_part(index, url)
                metas.append(meta)
                if int(meta.get("total") or -1) > 0:
                    self._part_totals[index] = int(meta["total"])
                self._part_downloaded[index] = 0
                self.log.emit(
                    f"Link {index + 1}: {meta['name']}"
                    + (f" • {human_bytes(meta['total'])}" if int(meta.get('total') or -1) > 0 else " • size unknown")
                )

            try:
                batch = _batch_archive_layout([str(m["name"]) for m in metas])
            except ValueError as exc:
                raise RuntimeError(str(exc)) from exc
            if not batch.get("ok"):
                raise RuntimeError(str(batch.get("error") or "Unsupported multi-link archive layout."))

            primary = dict(batch["primary"])
            extras = [dict(x) for x in batch.get("extras") or []]
            self.log.emit(
                f"Detected primary {primary['kind']} with {len(primary['indices'])} continuous part(s)."
            )
            if extras:
                self.log.emit(
                    f"Also detected {len(extras)} follow-up archive source(s). They will be extracted separately so they can be chained after the base install."
                )
                for extra in extras:
                    if extra.get("multipart"):
                        self.log.emit(
                            f"Follow-up multipart update: {extra['name']} • {len(extra['indices'])} volume(s)"
                        )
                    else:
                        self.log.emit(f"Follow-up archive: {extra['name']}")

            multipart_dir = self.destination.parent / f".streamextract-multilink-{os.getpid()}-{time.time_ns()}"
            multipart_dir.mkdir(parents=True, exist_ok=False)
            self._multipart_dir = multipart_dir

            group_for_index = {}
            all_groups = [primary] + extras
            for group_no, group in enumerate(all_groups, start=1):
                group_dir = multipart_dir / f"group-{group_no:02d}"
                for i in group["indices"]:
                    group_for_index[int(i)] = group_dir

            local_paths = {
                int(m["index"]): group_for_index[int(m["index"])] / str(m["name"])
                for m in metas
            }
            known_total = sum(self._part_totals.values()) if len(self._part_totals) == len(metas) and all(x > 0 for x in self._part_totals.values()) else -1
            self.download_progress.emit(0, known_total, 0.0)
            self._multipart_started = time.monotonic()

            # Display order keeps the base multipart set together first, then extras.
            ordered_for_display = []
            for group in all_groups:
                ordered_for_display.extend(group["order"])
            ordinal = {original: pos + 1 for pos, original in enumerate(ordered_for_display)}

            futures = {}
            # Keep a stable pool large enough for the user's maximum setting.
            # The dynamic gate above decides how many are actually transferring.
            with concurrent.futures.ThreadPoolExecutor(max_workers=min(MULTIPART_MAX_PARALLEL, len(metas))) as pool:
                for meta in metas:
                    i = int(meta["index"])
                    futures[pool.submit(self._download_one_part, meta, local_paths[i], ordinal[i], len(metas))] = i
                try:
                    for future in concurrent.futures.as_completed(futures):
                        self._check_cancel()
                        future.result()
                except Exception:
                    self._cancel.set()
                    for future in futures:
                        future.cancel()
                    raise

            self._check_cancel()
            primary_entry = local_paths[int(primary["entry_index"])]
            if not primary_entry.is_file():
                raise RuntimeError(f"Primary multipart entry volume is missing after download: {primary_entry.name}")
            self._extract_local_archive(primary_entry, str(primary["kind"]), self.destination, len(primary["indices"]))

            manifest_extras = []
            if extras:
                follow_root = self.destination / "_StreamExtract Follow-up"
                for pos, extra in enumerate(extras, start=1):
                    self._check_cancel()
                    extra_entry = local_paths[int(extra["entry_index"])]
                    folder_name = _safe_followup_folder_name(extra.get("name") or "", f"Extra {pos}")
                    out_dir = follow_root / folder_name
                    suffix = 2
                    while out_dir.exists():
                        out_dir = follow_root / f"{folder_name} ({suffix})"
                        suffix += 1
                    extra_kind = str(extra.get("kind") or "Standalone archive")
                    extra_volumes = max(1, len(extra.get("indices") or [extra.get("entry_index")]))
                    self._extract_local_archive(extra_entry, extra_kind, out_dir, extra_volumes)
                    manifest_extras.append({
                        "name": str(extra.get("name") or extra_entry.name),
                        "path": str(out_dir.relative_to(self.destination)),
                        "kind": extra_kind,
                        "multipart": bool(extra.get("multipart")),
                        "volumes": extra_volumes,
                    })

                manifest = {
                    "version": 1,
                    "mode": "mixed-multilink",
                    "primary_kind": str(primary.get("kind") or "multipart"),
                    "primary_files": [str(metas[i]["name"]) for i in primary["order"]],
                    "extras": manifest_extras,
                }
                marker = self.destination / ".streamextract-batch.json"
                temp_marker = marker.with_suffix(".json.tmp")
                temp_marker.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
                temp_marker.replace(marker)
                self.log.emit(
                    "Follow-up archive source(s), including any multipart update sets, were extracted under '_StreamExtract Follow-up' and marked so ISO cleanup will preserve them until used."
                )

            self._cleanup_multipart_dir()
            self.log.emit("Multi-link extraction completed. Temporary compressed RAR/ZIP/7z inputs were deleted.")
            self.log.emit("Download and extraction completed successfully.")
            self.finished.emit()

        except UserCancelled:
            self._cleanup_multipart_dir()
            self.log.emit("Cancelled.")
            self.cancelled.emit()
        except Exception as exc:
            self._cleanup_multipart_dir()
            self.failed.emit(f"{type(exc).__name__}: {exc}")


def infer_game_name_from_url(url: str) -> str:
    """Best-effort readable game name for StreamExtract.

    Opaque CDN/tunnel URLs intentionally return an empty string so the user can
    type the real game name instead of getting a random token as a folder name.
    """
    try:
        raw = unquote(Path(urlparse(url).path).name).strip()
    except Exception:
        return ""
    if not raw:
        return ""
    raw = re.sub(r"(?i)\.(?:zip|7z|rar|tar|gz|xz|bz2)$", "", raw).strip()
    raw = re.sub(r"[._]+", " ", raw)
    raw = re.sub(r"\s+", " ", raw).strip(" -_")
    # Drop common release/update suffixes without trying to maintain a release database.
    raw = re.sub(r"(?i)\s*[\[(]?\s*(?:incl(?:uding)?\.?\s+)?(?:update|patch|hotfix|build|rev(?:ision)?)\s*[-_ ]*\d.*$", "", raw).strip()
    raw = re.sub(r"(?i)\s*[-–— ]+(?:elamigos|fitgirl|dodi|gog)\s*$", "", raw).strip(" -_")
    compact = re.sub(r"[^A-Za-z0-9]", "", raw)
    # Random-looking signed/hash download tokens are worse than asking the user.
    digits = sum(c.isdigit() for c in compact)
    mixed_transitions = len(re.findall(r"(?i)[a-z]\d|\d[a-z]", compact))
    # Signed CDN/tunnel tokens can contain spaces/dashes after URL decoding, so
    # word count alone is not a reliable human-name test. Refuse long, mixed
    # alphanumeric tokens rather than creating unreadable game-prefix folders.
    if len(compact) >= 28 and digits >= 5 and (mixed_transitions >= 3 or len(raw) >= 45):
        return ""
    if not re.search(r"[A-Za-z]", raw):
        return ""
    return raw[:110].strip()


def fmt_temp(value: float | None) -> str:
    return "—" if value is None else f"{value:.0f}°C"


def fmt_pct(value: float | None) -> str:
    return "—" if value is None else f"{value:.0f}%"


def fmt_duration(seconds: float | None) -> str:
    if seconds is None:
        return "—"
    total = max(0, int(seconds))
    days, rem = divmod(total, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, secs = divmod(rem, 60)
    if days:
        return f"{days}d {hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def fmt_clock(value: datetime | None) -> str:
    return "—" if value is None else value.strftime("%H:%M:%S")


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Moses OneClick Tool — StreamExtract")
        self.resize(790, 790)

        # Persist speed preferences between StreamExtract launches.
        self.settings = QSettings("Moses OneClick", "StreamExtract")
        saved_mode = str(self.settings.value("performance/mode", "Cool / Quiet") or "Cool / Quiet")
        if saved_mode not in {"Cool / Quiet", "Normal", "Maximum speed", "Custom"}:
            saved_mode = "Cool / Quiet"
        saved_custom = str(self.settings.value("performance/custom_limit", "20 MB/s") or "20 MB/s")
        saved_custom_value, saved_custom_unit = split_saved_custom_limit(saved_custom)
        try:
            saved_connections = int(self.settings.value("network/range_connections", 1) or 1)
        except (TypeError, ValueError):
            saved_connections = 1
        saved_connections = max(1, min(saved_connections, 3))
        try:
            saved_multipart_parallel = int(self.settings.value("network/multipart_parallel", 1) or 1)
        except (TypeError, ValueError):
            saved_multipart_parallel = 1
        saved_multipart_parallel = max(1, min(saved_multipart_parallel, MULTIPART_MAX_PARALLEL))
        saved_keep_source = str(
            self.settings.value("installer/keep_extracted_source", "false") or "false"
        ).strip().casefold() in {"1", "true", "yes", "on"}

        self.thread: QThread | None = None
        self.worker: DownloadWorker | None = None
        self.sensor_reader = SensorReader()
        self.latest_snapshot = SensorSnapshot()
        self.last_thermal_tier = None
        self.stream_session = None
        self.iso_session_id = ""
        self.iso_last_status = ""

        # Per-job timing is intentionally separate from the worker so the GUI
        # can show a live elapsed duration and keep the final duration after the
        # worker stops (success, failure, or cancellation).
        self.run_started_wall: datetime | None = None
        self.run_started_monotonic: float | None = None
        self.run_finished_wall: datetime | None = None
        self.run_total_seconds: float | None = None
        self.run_outcome = "Idle"

        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setSpacing(9)

        title = QLabel("<h2>StreamExtract</h2>")
        subtitle = QLabel(
            "Paste one direct ZIP/RAR link, or multiple links for a split archive plus optional update/companion archives."
        )
        subtitle.setWordWrap(True)
        layout.addWidget(title)
        layout.addWidget(subtitle)

        form = QFormLayout()

        url_row = QHBoxLayout()
        self.url_edit = QPlainTextEdit()
        self.url_edit.setPlaceholderText(
            "One direct URL, or paste all related links here (one per line).\n"
            "Example: Game.part1.rar, Game.part2.rar, Game-Update.rar"
        )
        self.url_edit.setFixedHeight(72)
        self.paste_btn = QPushButton("Paste")
        self.paste_btn.clicked.connect(self.paste_url)
        url_row.addWidget(self.url_edit)
        url_row.addWidget(self.paste_btn)
        form.addRow("Download URL(s):", url_row)

        self.storage_combo = QComboBox()
        self.storage_combo.addItem("Internal storage (default)", {"path": "", "fstype": "", "supported": True})
        self.load_storage_choices()
        self.storage_combo.setToolTip(
            "Choose where the extracted game files and its Proton prefix should live. "
            "External drives must remain connected when playing."
        )
        form.addRow("Storage:", self.storage_combo)

        self.password_edit = QLineEdit()
        self.password_edit.setEchoMode(QLineEdit.Password)
        self.password_edit.setPlaceholderText("Optional")
        form.addRow("Archive password:", self.password_edit)

        self.performance_combo = QComboBox()
        self.performance_combo.addItems(
            ["Cool / Quiet", "Normal", "Maximum speed", "Custom"]
        )
        self.performance_combo.setCurrentText(saved_mode)
        self.performance_combo.currentTextChanged.connect(
            self.on_performance_mode_changed
        )
        form.addRow("Performance:", self.performance_combo)

        # Compact split control: numeric value on the left, unit dropdown on the right.
        # This replaces the old full-width free-form string field.
        custom_limit_row = QHBoxLayout()
        custom_limit_row.setSpacing(8)
        self.custom_speed_edit = QLineEdit(saved_custom_value)
        self.custom_speed_edit.setPlaceholderText("70")
        self.custom_speed_edit.setMaximumWidth(140)
        self.custom_speed_edit.setMaxLength(12)
        self.custom_speed_unit_combo = QComboBox()
        self.custom_speed_unit_combo.addItems(["KB/s", "MB/s", "GB/s"])
        self.custom_speed_unit_combo.setCurrentText(saved_custom_unit)
        self.custom_speed_unit_combo.setMaximumWidth(120)

        self.connection_combo = QComboBox()
        self.connection_combo.addItem("1 connection", 1)
        self.connection_combo.addItem("2 connections", 2)
        self.connection_combo.addItem("3 connections", 3)
        for index in range(self.connection_combo.count()):
            if int(self.connection_combo.itemData(index) or 1) == saved_connections:
                self.connection_combo.setCurrentIndex(index)
                break
        self.connection_combo.setMaximumWidth(150)
        self.connection_combo.setToolTip(
            "ZIP HTTP Range connections. 1 is smoothest and usually coolest; "
            "2 is balanced; 3 can be faster on per-connection-limited servers but "
            "may make Current file progress more stop-and-go. RAR remains sequential."
        )
        self.connection_combo.currentIndexChanged.connect(self.on_connection_count_changed)

        custom_enabled = saved_mode == "Custom"
        self.custom_speed_edit.setEnabled(custom_enabled)
        self.custom_speed_unit_combo.setEnabled(custom_enabled)
        self.custom_speed_edit.textChanged.connect(self.on_custom_speed_changed)
        self.custom_speed_unit_combo.currentTextChanged.connect(self.on_custom_speed_changed)
        custom_limit_row.addWidget(self.custom_speed_edit)
        custom_limit_row.addWidget(self.custom_speed_unit_combo)
        custom_limit_row.addWidget(self.connection_combo)
        custom_limit_row.addStretch(1)
        form.addRow("Custom limit:", custom_limit_row)

        self.multipart_parallel_combo = QComboBox()
        for count in range(1, MULTIPART_MAX_PARALLEL + 1):
            label = "1 at a time" if count == 1 else f"{count} simultaneously"
            self.multipart_parallel_combo.addItem(label, count)
        for index in range(self.multipart_parallel_combo.count()):
            if int(self.multipart_parallel_combo.itemData(index) or 1) == saved_multipart_parallel:
                self.multipart_parallel_combo.setCurrentIndex(index)
                break
        self.multipart_parallel_combo.setMaximumWidth(220)
        self.multipart_parallel_combo.setToolTip(
            "Used when you paste 2 or more related links. Choose 1 for sequential downloads, "
            "or up to 10 simultaneous file downloads. You can change this while the job is running: "
            "raising it starts queued files immediately; lowering it waits for active files to finish safely. "
            "A split base archive plus a separate update archive is supported. "
            "Your selected speed/thermal cap remains aggregate across the whole job."
        )
        self.multipart_parallel_combo.currentIndexChanged.connect(self.on_multipart_parallel_changed)
        form.addRow("Multi-link downloads:", self.multipart_parallel_combo)

        self.overwrite_box = QCheckBox("Overwrite files that already exist")
        form.addRow("", self.overwrite_box)

        self.keep_extracted_box = QCheckBox("Keep extracted installer files after installation")
        self.keep_extracted_box.setChecked(saved_keep_source)
        self.keep_extracted_box.setToolTip(
            "Applies to extracted installer sources such as ISO/setup/update files. "
            "Temporary downloaded RAR/ZIP/7z inputs are always deleted after successful extraction so they do not duplicate storage. "
            "If unchecked, a consumed ISO/base installer source is deleted after a successful install and safe ISO unmount. "
            "For an already-complete/portable game archive with no setup.exe or installer ISO, the extracted game folder is the final game and is ALWAYS kept after success; this checkbox does not delete it. "
            "Independent follow-up/update installer files that have not been used are preserved for safety. "
            "If extraction itself fails, enabling this option preserves completed extracted output in a visible StreamExtract Recovery folder instead of deleting it. "
            "Installed/final game files are never deleted."
        )
        self.keep_extracted_box.stateChanged.connect(self.on_keep_extracted_changed)
        form.addRow("", self.keep_extracted_box)

        layout.addLayout(form)

        thermal_box = QGroupBox("Temperature monitor / thermal protection")
        thermal_layout = QVBoxLayout(thermal_box)

        sensor_row = QHBoxLayout()
        self.cpu_sensor = QLabel("CPU  —")
        self.gpu_sensor = QLabel("GPU  —")
        self.junction_sensor = QLabel("Junction  —")
        self.vram_sensor = QLabel("VRAM  —")
        self.fan_sensor = QLabel("Fan  —")
        for label in (
            self.cpu_sensor, self.gpu_sensor, self.junction_sensor,
            self.vram_sensor, self.fan_sensor
        ):
            sensor_row.addWidget(label)
        thermal_layout.addLayout(sensor_row)

        protection_row = QHBoxLayout()
        self.thermal_box = QCheckBox("Automatically slow down when hot")
        self.thermal_box.setChecked(True)
        self.thermal_box.stateChanged.connect(self.refresh_thermal_status)

        self.threshold_spin = QSpinBox()
        self.threshold_spin.setRange(55, 100)
        self.threshold_spin.setValue(75)
        self.threshold_spin.setSuffix(" °C")
        self.threshold_spin.valueChanged.connect(self.refresh_thermal_status)

        protection_row.addWidget(self.thermal_box)
        protection_row.addWidget(QLabel("Start at:"))
        protection_row.addWidget(self.threshold_spin)
        protection_row.addStretch(1)
        thermal_layout.addLayout(protection_row)

        self.thermal_status = QLabel("Waiting for temperature sensors…")
        self.thermal_status.setWordWrap(True)
        thermal_layout.addWidget(self.thermal_status)

        self.sensor_source = QLabel("")
        self.sensor_source.setWordWrap(True)
        thermal_layout.addWidget(self.sensor_source)
        layout.addWidget(thermal_box)

        button_row = QHBoxLayout()
        self.start_btn = QPushButton("Download && Extract")
        self.start_btn.setObjectName("primaryButton")
        self.start_btn.setDefault(True)
        self.start_btn.clicked.connect(self.start_download)
        self.cancel_btn = QPushButton("Cancel")
        self.cancel_btn.setObjectName("secondaryButton")
        self.cancel_btn.setEnabled(False)
        self.cancel_btn.clicked.connect(self.cancel_download)
        button_row.addWidget(self.start_btn)
        button_row.addWidget(self.cancel_btn)
        layout.addLayout(button_row)

        download_heading = QLabel("Download")
        download_heading.setObjectName("sectionHeading")
        layout.addWidget(download_heading)
        self.download_bar = QProgressBar()
        self.download_bar.setRange(0, 1000)
        self.download_status = QLabel("Waiting…")
        self.download_status.setWordWrap(True)
        layout.addWidget(self.download_bar)
        layout.addWidget(self.download_status)

        self.live_speed_hint = QLabel(
            "Performance can be changed while downloading."
        )
        self.live_speed_hint.setWordWrap(True)
        layout.addWidget(self.live_speed_hint)

        current_heading = QLabel("Current file")
        current_heading.setObjectName("sectionHeading")
        layout.addWidget(current_heading)
        self.file_label = QLabel("—")
        self.file_label.setWordWrap(True)
        self.file_bar = QProgressBar()
        self.file_bar.setRange(0, 1000)
        layout.addWidget(self.file_label)
        layout.addWidget(self.file_bar)

        self.log_box = QTextEdit()
        self.log_box.setReadOnly(True)
        self.log_box.setPlaceholderText("Activity will appear here.")
        layout.addWidget(self.log_box, 1)

        # Compact session summary replaces the old help paragraph. It remains
        # visible after completion so a screenshot immediately shows when the
        # job started, how long it ran, and when it ended.
        timing_row = QHBoxLayout()
        timing_row.setSpacing(14)
        self.started_label = QLabel("Started: —")
        self.duration_label = QLabel("Duration: —")
        self.finished_label = QLabel("Finished: —")
        self.total_time_label = QLabel("Total: —")
        for label in (
            self.started_label, self.duration_label,
            self.finished_label, self.total_time_label,
        ):
            label.setObjectName("timingLabel")
            timing_row.addWidget(label)
        timing_row.addStretch(1)
        self.save_log_btn = QPushButton("Save Log")
        self.save_log_btn.setObjectName("secondaryButton")
        self.save_log_btn.setToolTip("Save the StreamExtract activity and session details to a text file.")
        self.save_log_btn.clicked.connect(self.save_log)
        timing_row.addWidget(self.save_log_btn)
        layout.addLayout(timing_row)

        # Preserve the exact v0.8 layout/size behaviour.  Styling only: no
        # fixed/minimum row heights, wrapper widgets or compact-layout hacks.
        self.apply_moses_theme()

        self.sensor_timer = QTimer(self)
        self.sensor_timer.timeout.connect(self.poll_sensors)
        self.sensor_timer.start(1000)
        self.poll_sensors()

        self.run_timer = QTimer(self)
        self.run_timer.setInterval(500)
        self.run_timer.timeout.connect(self.refresh_run_timing)
        self.refresh_run_timing()

        self.iso_status_timer = QTimer(self)
        self.iso_status_timer.setInterval(1000)
        self.iso_status_timer.timeout.connect(self.poll_iso_session_status)


    def poll_iso_session_status(self):
        session_id = str(self.iso_session_id or "").strip()
        if not session_id:
            self.iso_status_timer.stop()
            return
        result = self._run_helper_json(["stream-iso-status", session_id], timeout=8)
        if not result.get("ok"):
            return
        status = str(result.get("status") or "").strip()
        if status and status != self.iso_last_status:
            self.iso_last_status = status
            labels = {
                "mounted": "ISO mounted — preparing installer…",
                "opening-installer": "ISO mounted — finding installer EXE…",
                "installer-dialog": "Installer found — waiting for your Game Installer choice…",
                "installing": "Game installer is running…",
                "install-finished": "Base installation finished — checking for follow-up updates…",
                "followup-dialog": "Opening the normal Game Installer for the follow-up update/patch…",
                "followup-installing": "Follow-up update/patch is running…",
                "followup-finished": "Follow-up update/patch finished — checking for the next one…",
                "steam-finalizing": "Install/update chain complete — finalizing Steam shortcut and artwork…",
                "done": "Installation complete — ISO unmounted and Steam integration finished.",
                "done-followup": "Installation complete — Steam integration finished; unused follow-up installer files were kept.",
                "install-failed": "Installation did not complete — installer source was kept.",
                "cancelled": "ISO installation cancelled — installer source was kept.",
                "no-installer": "ISO mounted, but no suitable installer EXE was found.",
                "invalid-installer": "Installer EXE became unavailable; ISO source was kept.",
                "busy-after-install": "Game installed, but ISO is still in use and was kept mounted for safety.",
                "unmount-failed": "Game installed, but the ISO could not be unmounted safely.",
                "error": "ISO installer bridge stopped unexpectedly; source was kept.",
            }
            text = labels.get(status, f"ISO installer status: {status}")
            if status == "done-followup" and str(result.get("followup_path") or "").strip():
                text += f" Follow-up folder: {result.get('followup_path')}"
            self.download_status.setText(text)
            self.append_log(text)
        if status in {"done", "done-followup", "install-failed", "cancelled", "no-installer", "invalid-installer", "busy-after-install", "unmount-failed", "error"}:
            self.iso_status_timer.stop()
            self.iso_session_id = ""


    def apply_moses_theme(self):
        # Moses OneClick colours on top of the original v0.8 geometry.
        # Deliberately avoid min-height/fixed-height rules here: Qt's native
        # size hints are what made v0.8 render correctly on SteamOS.
        self.setStyleSheet(r"""
            QMainWindow, QWidget {
                background-color: #f6f7f9;
                color: #202124;
                font-size: 13px;
            }
            QLabel {
                background: transparent;
                color: #202124;
            }
            QGroupBox {
                background-color: #f6f7f9;
                border: 1px solid #d5dde7;
                border-radius: 7px;
                margin-top: 10px;
                padding-top: 6px;
                font-weight: 600;
                color: #54595f;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px;
                background-color: #f6f7f9;
            }
            QLineEdit, QComboBox, QSpinBox, QTextEdit {
                background-color: #ffffff;
                color: #202124;
                border: 1px solid #cfd3d8;
                border-radius: 6px;
                padding: 6px 8px;
                selection-background-color: #2f80ed;
                selection-color: #ffffff;
            }
            QCheckBox {
                background: transparent;
                color: #202124;
                spacing: 8px;
                padding: 2px 0;
            }
            QCheckBox::indicator {
                width: 17px;
                height: 17px;
                border: 2px solid #7f8c9a;
                border-radius: 4px;
                background-color: #ffffff;
            }
            QCheckBox::indicator:hover {
                border-color: #2f80ed;
            }
            QCheckBox::indicator:checked {
                border-color: #2f80ed;
                background-color: #2f80ed;
            }
            QCheckBox::indicator:disabled {
                border-color: #c1c7ce;
                background-color: #eef0f2;
            }
            QLineEdit:focus, QComboBox:focus, QSpinBox:focus, QTextEdit:focus {
                border: 1px solid #2f80ed;
            }
            QComboBox::drop-down {
                border: 0;
            }
            QPushButton {
                background-color: #ffffff;
                color: #2f6fbd;
                border: 1px solid #b9cbe0;
                border-radius: 6px;
                padding: 7px 13px;
                font-weight: 600;
            }
            QPushButton:hover {
                background-color: #f1f6fc;
                border-color: #8fb2da;
            }
            QPushButton:disabled {
                color: #9aa0a6;
                background-color: #eef0f2;
                border-color: #d7dadd;
            }
            QPushButton#primaryButton {
                background-color: #2f80ed;
                color: #ffffff;
                border-color: #2f80ed;
            }
            QPushButton#primaryButton:hover {
                background-color: #1f6fd5;
                border-color: #1f6fd5;
            }
            QPushButton#secondaryButton {
                color: #4b5156;
                border-color: #cfd3d8;
            }
            QProgressBar {
                background-color: #ffffff;
                color: #34383d;
                border: 1px solid #cfd3d8;
                border-radius: 5px;
                min-height: 16px;
                text-align: center;
            }
            QProgressBar::chunk {
                background-color: #2f80ed;
                border-radius: 3px;
            }
            QTextEdit {
                font-family: monospace;
            }
            QLabel#sectionHeading {
                font-weight: 600;
                color: #34383d;
                padding-top: 1px;
            }
            QLabel#footNote {
                color: #70757a;
                font-size: 11px;
            }
            QLabel#timingLabel {
                color: #5f6368;
                font-size: 11px;
            }
            QToolTip {
                background-color: #ffffff;
                color: #202124;
                border: 1px solid #cfd3d8;
            }
        """)

    def refresh_run_timing(self):
        self.started_label.setText(f"Started: {fmt_clock(self.run_started_wall)}")
        self.finished_label.setText(f"Finished: {fmt_clock(self.run_finished_wall)}")

        if self.run_started_monotonic is None:
            elapsed = None
        elif self.run_finished_wall is None:
            elapsed = max(0.0, time.monotonic() - self.run_started_monotonic)
        else:
            elapsed = self.run_total_seconds

        self.duration_label.setText(f"Duration: {fmt_duration(elapsed)}")
        self.total_time_label.setText(
            f"Total: {fmt_duration(self.run_total_seconds) if self.run_finished_wall is not None else '—'}"
        )

    def begin_run_timing(self):
        self.run_started_wall = datetime.now().astimezone()
        self.run_started_monotonic = time.monotonic()
        self.run_finished_wall = None
        self.run_total_seconds = None
        self.run_outcome = "Running"
        self.run_timer.start()
        self.refresh_run_timing()
        self.append_log(f"Started: {self.run_started_wall.strftime('%Y-%m-%d %H:%M:%S %Z')}")

    def finish_run_timing(self, outcome: str):
        if self.run_started_monotonic is None:
            return
        if self.run_finished_wall is None:
            self.run_finished_wall = datetime.now().astimezone()
            self.run_total_seconds = max(0.0, time.monotonic() - self.run_started_monotonic)
        self.run_outcome = outcome
        self.run_timer.stop()
        self.refresh_run_timing()
        self.append_log(
            f"Finished: {self.run_finished_wall.strftime('%Y-%m-%d %H:%M:%S %Z')} "
            f"— {outcome} — total {fmt_duration(self.run_total_seconds)}"
        )

    def save_log(self):
        stamp_source = self.run_started_wall or datetime.now().astimezone()
        default_dir = Path.home() / "Downloads"
        if not default_dir.is_dir():
            default_dir = Path.home()
        default_path = default_dir / f"StreamExtract_Log_{stamp_source.strftime('%Y%m%d_%H%M%S')}.txt"
        filename, _ = QFileDialog.getSaveFileName(
            self,
            "Save StreamExtract log",
            str(default_path),
            "Text files (*.txt);;All files (*)",
        )
        if not filename:
            return

        raw_urls = self.input_urls(silent=True)
        safe_sources = []
        for raw_url in raw_urls:
            try:
                parsed = urlparse(raw_url)
                safe = f"{parsed.scheme}://{parsed.netloc}/[redacted]" if parsed.scheme and parsed.netloc else "—"
            except Exception:
                safe = "—"
            safe_sources.append(safe)
        safe_url = "; ".join(safe_sources) if safe_sources else "—"

        session = dict(self.stream_session or {})
        lines = [
            "Moses OneClick Tool — StreamExtract diagnostic log",
            f"StreamExtract version: {APP_VERSION}",
            f"Status: {self.run_outcome}",
            f"Started: {self.run_started_wall.strftime('%Y-%m-%d %H:%M:%S %Z') if self.run_started_wall else '—'}",
            f"Finished: {self.run_finished_wall.strftime('%Y-%m-%d %H:%M:%S %Z') if self.run_finished_wall else '—'}",
            f"Duration: {fmt_duration(self.run_total_seconds if self.run_finished_wall else (time.monotonic() - self.run_started_monotonic if self.run_started_monotonic is not None else None))}",
            f"Performance: {self.performance_combo.currentText()}",
            f"Custom limit: {self.custom_limit_text() if self.performance_combo.currentText() == 'Custom' else '—'}",
            f"ZIP Range connections: {self.selected_range_connections()}",
            f"Multi-link simultaneous downloads: {self.selected_multipart_parallel()}",
            f"Input link count: {len(raw_urls)}",
            f"Thermal protection: {'ON' if self.thermal_box.isChecked() else 'OFF'} at {self.threshold_spin.value()}°C",
            f"Download source: {safe_url}",
            "Download query/token: redacted",
            f"Files folder: {session.get('files_dir') or '—'}",
            "",
            "--- Activity log ---",
            self.log_box.toPlainText().rstrip(),
            "",
        ]
        try:
            Path(filename).write_text("\n".join(lines), encoding="utf-8")
        except Exception as exc:
            QMessageBox.critical(self, "Could not save log", str(exc))
            return
        QMessageBox.information(self, "Log saved", f"StreamExtract log saved to:\n{filename}")

    def custom_limit_text(self) -> str:
        return f"{self.custom_speed_edit.text().strip()} {self.custom_speed_unit_combo.currentText()}".strip()

    def custom_rate_from_controls(self) -> int:
        return parse_custom_rate_limit(
            self.custom_speed_edit.text(),
            self.custom_speed_unit_combo.currentText(),
        )

    def selected_range_connections(self) -> int:
        try:
            return max(1, min(int(self.connection_combo.currentData() or 1), 3))
        except (TypeError, ValueError):
            return 1

    @Slot(int)
    def on_connection_count_changed(self, _index: int):
        self.settings.setValue("network/range_connections", self.selected_range_connections())
        self.settings.sync()

    def selected_multipart_parallel(self) -> int:
        try:
            return max(1, min(int(self.multipart_parallel_combo.currentData() or 1), MULTIPART_MAX_PARALLEL))
        except (TypeError, ValueError):
            return 1

    @Slot(int)
    def on_multipart_parallel_changed(self, _index: int):
        value = self.selected_multipart_parallel()
        self.settings.setValue("network/multipart_parallel", value)
        self.settings.sync()
        worker = self.worker
        if isinstance(worker, MultiPartDownloadWorker):
            worker.set_multipart_parallel(value)
            self.download_status.setText(f"Multi-link download limit changed to {value} simultaneous file(s)…")

    def input_urls(self, silent: bool = False) -> list[str]:
        text = self.url_edit.toPlainText().strip()
        urls = re.findall(r"https?://\S+", text, flags=re.I)
        # Preserve paste order while removing accidental duplicate lines.
        unique = []
        seen = set()
        for url in urls:
            url = url.strip()
            if url and url not in seen:
                seen.add(url)
                unique.append(url)
        if not silent and text and not urls:
            QMessageBox.warning(self, "Invalid URL", "Please paste direct HTTP or HTTPS download URLs.")
        return unique

    def base_rate_from_ui(self) -> int | None:
        mode = self.performance_combo.currentText()
        if mode == "Cool / Quiet":
            return 12 * MIB
        if mode == "Normal":
            return 40 * MIB
        if mode == "Maximum speed":
            return None
        if mode == "Custom":
            try:
                return self.custom_rate_from_controls()
            except ValueError:
                return None
        return None

    def poll_sensors(self):
        self.latest_snapshot = self.sensor_reader.read()
        s = self.latest_snapshot
        self.cpu_sensor.setText(f"CPU  {fmt_temp(s.cpu_temp)}")
        self.gpu_sensor.setText(f"GPU  {fmt_temp(s.gpu_temp)}")
        self.junction_sensor.setText(f"Junction  {fmt_temp(s.gpu_junction_temp)}")
        self.vram_sensor.setText(f"VRAM  {fmt_temp(s.vram_temp)}")
        self.fan_sensor.setText(
            "Fan  —" if s.fan_rpm is None else f"Fan  {s.fan_rpm} RPM"
        )
        self.sensor_source.setText(
            f"CPU load {fmt_pct(s.cpu_usage)} • GPU load {fmt_pct(s.gpu_usage)} "
            f"• Sensor source: {s.source}"
        )

        if self.worker:
            self.worker.update_thermal(
                s.hottest_temp,
                self.thermal_box.isChecked(),
                self.threshold_spin.value(),
            )
        self.refresh_thermal_status()

    def refresh_thermal_status(self):
        temp = self.latest_snapshot.hottest_temp
        enabled = self.thermal_box.isChecked()
        threshold = self.threshold_spin.value()
        base_rate = self.base_rate_from_ui()
        effective = calculate_thermal_rate(base_rate, temp, enabled, threshold)

        if not enabled:
            self.thermal_status.setText("Thermal protection is OFF.")
            return
        if temp is None:
            self.thermal_status.setText(
                "Thermal protection is ON, but no temperature sensor was found."
            )
            return

        if temp < threshold:
            rate_text = (
                "unlimited" if effective is None else f"{human_bytes(effective)}/s"
            )
            self.thermal_status.setText(
                f"Hottest sensor: {temp:.0f}°C • Below {threshold}°C • "
                f"Current cap: {rate_text}"
            )
        else:
            rate_text = (
                "unlimited" if effective is None else f"{human_bytes(effective)}/s"
            )
            self.thermal_status.setText(
                f"THERMAL PROTECTION ACTIVE • Hottest sensor: {temp:.0f}°C • "
                f"Effective cap: {rate_text}"
            )

    @Slot(str)
    def on_performance_mode_changed(self, mode: str):
        custom_enabled = mode == "Custom"
        self.custom_speed_edit.setEnabled(custom_enabled)
        self.custom_speed_unit_combo.setEnabled(custom_enabled)
        self.settings.setValue("performance/mode", mode)
        self.settings.sync()

        custom_rate = None
        if mode == "Custom":
            try:
                custom_rate = self.custom_rate_from_controls()
            except ValueError:
                # Keep the previous worker cap until the custom value becomes
                # valid instead of interrupting an active download.
                self.refresh_thermal_status()
                return

        if self.worker:
            self.worker.update_performance(mode, custom_rate)

        self.refresh_thermal_status()

    @Slot(str)
    def on_custom_speed_changed(self, _text: str):
        if self.performance_combo.currentText() != "Custom":
            return

        try:
            custom_rate = self.custom_rate_from_controls()
        except ValueError:
            return

        self.settings.setValue("performance/custom_limit", self.custom_limit_text())
        self.settings.sync()

        if self.worker:
            self.worker.update_performance("Custom", custom_rate)

        self.refresh_thermal_status()

    def paste_url(self):
        text = QApplication.clipboard().text().strip()
        if text:
            # One click supports either a single long signed URL or a clipboard
            # containing multiple related archive links on separate lines.
            self.url_edit.setPlainText(text)

    def _run_helper_json(self, args, timeout=60 * 60):
        if not HELPER_PATH.is_file():
            return {"ok": False, "error": f"Moses OneClick helper was not found: {HELPER_PATH}"}
        try:
            result = subprocess.run(
                [str(HELPER_PATH), *args],
                text=True, capture_output=True, timeout=timeout,
            )
        except Exception as exc:
            return {"ok": False, "error": str(exc)}
        for line in reversed((result.stdout or "").splitlines()):
            line = line.strip()
            if not line:
                continue
            try:
                value = __import__("json").loads(line)
            except Exception:
                continue
            if isinstance(value, dict):
                return value
        detail = (result.stderr or result.stdout or "Moses OneClick helper returned no result.").strip()
        return {"ok": False, "error": detail}

    def load_storage_choices(self):
        payload = self._run_helper_json(["stream-storage-options"], timeout=15)
        for drive in payload.get("external", []) if isinstance(payload, dict) else []:
            if not isinstance(drive, dict):
                continue
            path = str(drive.get("path") or "").strip()
            if not path:
                continue
            label = str(drive.get("label") or Path(path).name or "External drive")
            fstype = str(drive.get("fstype") or "unknown")
            free = int(drive.get("free") or 0)
            suffix = f" · {free / (1024 ** 3):.1f} GiB free · {fstype}" if free else f" · {fstype}"
            if drive.get("filesystem_supported") and not drive.get("writable"):
                suffix += " · needs write-permission fix"
            elif not drive.get("filesystem_supported"):
                suffix += " · needs formatting for Proton/Wine"
            elif not drive.get("supported"):
                suffix += " · unavailable"
            self.storage_combo.addItem(f"External: {label}{suffix}", drive)

    def prepare_stream_destination(self, replace_existing=False):
        data = self.storage_combo.currentData() or {}
        path = str(data.get("path") or "") if isinstance(data, dict) else ""
        fstype = str(data.get("fstype") or "") if isinstance(data, dict) else ""
        # Always use a hidden per-job staging folder. The game name is chosen
        # automatically from the extracted files/EXE after extraction succeeds.
        return self._run_helper_json([
            "stream-prepare", path, fstype, "", "1" if replace_existing else "0", str(os.getpid())
        ])

    def set_running(self, running: bool):
        self.start_btn.setEnabled(not running)
        self.cancel_btn.setEnabled(running)
        self.url_edit.setEnabled(not running)
        self.storage_combo.setEnabled(not running)
        self.password_edit.setEnabled(not running)
        # Performance controls intentionally stay enabled during downloads so
        # the speed can be changed live.
        self.performance_combo.setEnabled(True)
        custom_enabled = self.performance_combo.currentText() == "Custom"
        self.custom_speed_edit.setEnabled(custom_enabled)
        self.custom_speed_unit_combo.setEnabled(custom_enabled)
        self.connection_combo.setEnabled(not running)
        # Multi-link concurrency is intentionally live. It is implemented with
        # a safe transfer gate, so raising/lowering it does not restart files.
        self.multipart_parallel_combo.setEnabled(True)
        self.overwrite_box.setEnabled(not running)
        # Keep-source is intentionally left enabled while a job is running.
        # Besides keeping its checked state visually obvious, the choice can be
        # changed live and is applied to the current StreamExtract session.
        self.keep_extracted_box.setEnabled(True)

    @Slot(int)
    def on_keep_extracted_changed(self, _state):
        keep = bool(self.keep_extracted_box.isChecked())
        self.settings.setValue("installer/keep_extracted_source", keep)
        self.settings.sync()
        if isinstance(self.stream_session, dict):
            old_keep = bool(self.stream_session.get("keep_extracted_source"))
            self.stream_session["keep_extracted_source"] = keep
            # Only log actual live changes after a StreamExtract job has begun.
            if self.worker is not None and old_keep != keep:
                self.append_log(
                    "Keep extracted installer files changed while running: "
                    + ("ON — installer source/recovery output will be kept." if keep else "OFF — consumed installer source may be cleaned after success; failed partial output may be removed.")
                )

    def validate_inputs(self):
        urls = self.input_urls()
        if not urls:
            if not self.url_edit.toPlainText().strip():
                QMessageBox.warning(self, "Invalid URL", "Please paste at least one direct HTTP or HTTPS download URL.")
            return None
        for url in urls:
            parsed = urlparse(url)
            if parsed.scheme not in ("http", "https") or not parsed.netloc:
                QMessageBox.warning(self, "Invalid URL", f"This is not a valid direct HTTP/HTTPS URL:\n\n{url}")
                return None

        custom_rate = None
        if self.performance_combo.currentText() == "Custom":
            try:
                custom_rate = self.custom_rate_from_controls()
            except ValueError as exc:
                QMessageBox.warning(self, "Invalid custom speed", str(exc))
                return None
        return urls, custom_rate, self.selected_range_connections(), self.selected_multipart_parallel()

    def start_download(self):
        validated = self.validate_inputs()
        if not validated:
            return
        urls, custom_rate, range_connections, multipart_parallel = validated

        self.download_status.setText("Preparing temporary game folder…")
        QApplication.processEvents()
        session = self.prepare_stream_destination(False)
        if session.get("conflict"):
            existing_path = str(session.get("files_dir") or "")
            answer = QMessageBox.question(
                self, "Temporary folder already contains files",
                f"A temporary StreamExtract folder already contains files:\n\n{existing_path}\n\n"
                "Replace those files with this new StreamExtract download?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer != QMessageBox.Yes:
                self.download_status.setText("Waiting…")
                return
            session = self.prepare_stream_destination(True)
        if not session.get("ok"):
            if not session.get("cancelled"):
                QMessageBox.warning(
                    self, "Storage could not be prepared",
                    str(session.get("error") or "The selected storage could not be prepared.")
                )
            self.download_status.setText("Waiting…")
            return
        destination = str(session.get("files_dir") or "")
        if not destination:
            QMessageBox.warning(self, "Storage could not be prepared", "No final game Files folder was returned.")
            self.download_status.setText("Waiting…")
            return
        session["keep_extracted_source"] = bool(self.keep_extracted_box.isChecked())
        self.stream_session = session
        self.settings.setValue("installer/keep_extracted_source", self.keep_extracted_box.isChecked())
        self.settings.sync()

        self.log_box.clear()
        self.begin_run_timing()
        self.append_log(f"Extracting directly to: {destination}")
        self.append_log(f"Input links: {len(urls)}")
        if len(urls) == 1:
            self.append_log(f"Selected ZIP Range connections: {range_connections}")
        else:
            self.append_log(f"Multi-link simultaneous downloads: {multipart_parallel}")
            self.append_log("Temporary downloaded archive inputs are deleted after successful extraction; independent follow-up installer files are preserved until used.")
        self.append_log(
            "Extracted installer source after successful ISO install: "
            + ("keep ISO/companion files" if self.keep_extracted_box.isChecked() else "delete after safe unmount")
        )
        self.download_bar.setRange(0, 1000)
        self.download_bar.setValue(0)
        self.download_bar.setFormat("%p%")
        self.file_bar.setRange(0, 1000)
        self.file_bar.setValue(0)
        self.file_bar.setFormat("%p%")
        self.file_label.setText("Waiting for first archive entry…")
        self.download_status.setText(f"Extracting directly to: {destination}")
        self.set_running(True)

        self.thread = QThread(self)
        common_worker_args = dict(
            destination=destination,
            password=self.password_edit.text(),
            overwrite=self.overwrite_box.isChecked(),
            performance_mode=self.performance_combo.currentText(),
            custom_rate_bps=custom_rate,
            range_connections=range_connections,
            thermal_enabled=self.thermal_box.isChecked(),
            thermal_threshold=self.threshold_spin.value(),
        )
        if len(urls) > 1:
            self.worker = MultiPartDownloadWorker(
                urls=urls, multipart_parallel=multipart_parallel, **common_worker_args
            )
            self.download_status.setText(
                f"Preparing multi-link archive batch: {len(urls)} links, up to {multipart_parallel} simultaneous downloads…"
            )
        else:
            self.worker = DownloadWorker(url=urls[0], **common_worker_args)
        self.worker.update_thermal(
            self.latest_snapshot.hottest_temp,
            self.thermal_box.isChecked(),
            self.threshold_spin.value(),
        )
        self.worker.moveToThread(self.thread)

        self.thread.started.connect(self.worker.run)
        self.worker.download_progress.connect(self.on_download_progress)
        self.worker.file_progress.connect(self.on_file_progress)
        self.worker.log.connect(self.append_log)
        self.worker.finished.connect(self.on_finished)
        self.worker.cancelled.connect(self.on_cancelled)
        self.worker.failed.connect(self.on_failed)
        self.worker.finished.connect(self.thread.quit)
        self.worker.cancelled.connect(self.thread.quit)
        self.worker.failed.connect(self.thread.quit)
        self.thread.finished.connect(self.thread.deleteLater)
        self.thread.start()

    def cancel_download(self):
        if self.worker:
            self.worker.cancel()
            self.cancel_btn.setEnabled(False)
            self.download_status.setText("Cancelling…")

    @Slot(object, object, float)
    def on_download_progress(self, downloaded: int, total: int, speed: float):
        # V1.10 keeps this bar in final extracted bytes whenever the archive
        # exposes enough metadata. Compatibility paths fall back to verified
        # remote archive bytes, but never invent a 100%/unknown total while a
        # trustworthy Content-Range size is already known.
        downloaded = max(0, int(downloaded or 0))
        total = int(total or -1)
        speed = max(0.0, float(speed or 0.0))
        if total > 0:
            shown = min(downloaded, total)
            fraction = max(0.0, min(shown / total, 1.0))
            self.download_bar.setRange(0, 1000)
            self.download_bar.setValue(int(fraction * 1000))
            self.download_status.setText(
                f"{human_bytes(shown)} / {human_bytes(total)} "
                f"— {fraction * 100:.1f}% — {human_bytes(speed)}/s"
            )
        else:
            # Indeterminate mode is more honest than a false 100% when a
            # proxy refuses to expose the real Content-Range total.
            self.download_bar.setRange(0, 0)
            self.download_status.setText(
                f"{human_bytes(downloaded)} downloaded "
                f"— total size unknown — {human_bytes(speed)}/s"
            )

    @Slot(str, object, object)
    def on_file_progress(self, name: str, written: int, expected: int):
        self.file_label.setText(name)
        if expected > 0:
            fraction = min(written / expected, 1.0)
            self.file_bar.setRange(0, 1000)
            self.file_bar.setValue(int(fraction * 1000))
            self.file_bar.setFormat(
                f"{human_bytes(written)} / {human_bytes(expected)} "
                f"— {fraction * 100:.1f}%"
            )
        else:
            self.file_bar.setRange(0, 0)
            self.file_bar.setFormat(human_bytes(written))

    @Slot(str)
    def append_log(self, text: str):
        self.log_box.append(text)

    @Slot()
    def on_finished(self):
        self.finish_run_timing("Completed")
        self.set_running(False)
        self.download_status.setText("Extraction complete — choose the game EXE…")

        # A job may previously have put the Download bar into Qt's indeterminate
        # range (0, 0). Always leave completion as a fixed, solid blue 100% bar.
        self.download_bar.setRange(0, 1000)
        self.download_bar.setValue(1000)
        self.download_bar.setFormat("100%")
        self.file_bar.setRange(0, 1000)
        self.file_bar.setValue(1000)
        self.worker = None

        session = dict(self.stream_session or {})
        files_dir = str(session.get("files_dir") or "")
        if not files_dir:
            QMessageBox.warning(
                self, "Extraction complete",
                "The archive was extracted, but Moses OneClick lost the final Files-folder information."
            )
            return

        # Extraction itself succeeded. Mark this StreamExtract session complete
        # before the EXE chooser opens, so failed-install cleanup never mistakes
        # a fully downloaded game for an abandoned partial folder.
        self._run_helper_json([
            "stream-complete",
            str(session.get("prefix_dir") or ""),
            str(session.get("session_id") or ""),
        ])

        # V1.14: if the extracted payload contains an installer ISO, do NOT
        # extract that ISO again. Hand it to Moses' read-only ISO bridge, which
        # mounts the image and opens the exact same Game Installer dialog used
        # when the user double-clicks a normal setup.exe. The bridge remains in
        # the background until installation ends, then safely unmounts the ISO
        # and optionally deletes it only after a verified successful install.
        iso_check = self._run_helper_json(["stream-iso-detect", files_dir], timeout=30)
        if iso_check.get("found"):
            iso_name = Path(str(iso_check.get("iso") or "Installer.iso")).name
            self.download_status.setText(f"Extraction complete — installer ISO detected: {iso_name}")
            self.append_log(f"Installer ISO detected: {iso_check.get('iso') or iso_name}")
            self.append_log("Mounting ISO read-only; the normal Moses Game Installer will open next.")
            iso_result = self._run_helper_json([
                "stream-iso-launch",
                files_dir,
                str(session.get("storage_mode") or "internal"),
                str(session.get("storage_root") or ""),
                "1" if bool(session.get("keep_extracted_source")) else "0",
            ], timeout=180)
            if iso_result.get("ok"):
                self.stream_session = None
                self.iso_session_id = str(iso_result.get("session_id") or "")
                self.iso_last_status = ""
                if self.iso_session_id:
                    self.iso_status_timer.start()
                mounted_iso = Path(str(iso_result.get("iso") or iso_name)).name
                self.download_status.setText(f"ISO mounted — opening Game Installer for {mounted_iso}…")
                self.append_log(f"ISO mounted read-only at: {iso_result.get('mountpoint') or 'system mount point'}")
                self.append_log("ISO lifecycle manager started; it will keep the disc mounted while the installer needs it.")
                if bool(session.get("keep_extracted_source")):
                    self.append_log("After a successful install: extracted installer source files will be kept.")
                else:
                    self.append_log("After a successful install: extracted installer source files will be deleted after safe unmount.")
                return
            if iso_result.get("cancelled"):
                self.download_status.setText("Extraction complete — ISO installation cancelled.")
                QMessageBox.information(
                    self, "Installer ISO kept",
                    "The archive finished extracting, but ISO installation was cancelled.\n\n"
                    f"The ISO was kept here:\n{iso_result.get('iso') or iso_check.get('iso') or files_dir}"
                )
                return
            self.download_status.setText("Extraction complete — installer ISO could not be opened.")
            QMessageBox.critical(
                self, "Could not open installer ISO",
                str(iso_result.get("error") or "The ISO could not be mounted safely.")
                + f"\n\nThe extracted ISO was kept at:\n{iso_result.get('iso') or iso_check.get('iso') or files_dir}"
            )
            return

        # No installer ISO: keep the existing portable/already-complete game
        # flow unchanged. It chooses/validates the main game EXE, creates the
        # Steam/Proton mapping, and starts artwork.
        result = self._run_helper_json([
            "stream-finalize",
            files_dir,
            str(session.get("storage_mode") or "internal"),
            str(session.get("storage_root") or ""),
            "",
        ])
        if result.get("ok"):
            self.stream_session = None
            name = str(result.get("name") or "Game")
            self.download_status.setText(f"Completed — {name} added to Moses OneClick.")
            if result.get("shortcut_state") == "pending_steam_restart":
                complete_text = (
                    f"{name} finished extracting successfully.\n\n"
                    "Steam is currently open, so the shortcut is queued and will be written as soon as "
                    "the Steam main client closes. Lingering steamwebhelper processes no longer block it. "
                    "Artwork is downloading in the background."
                )
            else:
                complete_text = (
                    f"{name} finished extracting and the Steam shortcut was created and verified.\n\n"
                    "Artwork is downloading in the background."
                )
            QMessageBox.information(
                self, "Game ready", complete_text
            )
            return

        if result.get("cancelled"):
            self.download_status.setText("Extraction complete — Add to Steam cancelled.")
            QMessageBox.information(
                self, "Extraction complete",
                "The game finished extracting, but Add to Steam was cancelled.\n\n"
                f"The extracted files were kept here:\n{result.get('files_dir') or files_dir}"
            )
            return

        self.download_status.setText("Extraction complete — Steam registration failed.")
        QMessageBox.critical(
            self, "Could not add game to Steam",
            str(result.get("error") or "The game was extracted, but Moses OneClick could not register it.")
            + f"\n\nExtracted files were kept at:\n{result.get('files_dir') or files_dir}"
        )

    @Slot()
    def on_cancelled(self):
        self.finish_run_timing("Cancelled")
        self.set_running(False)
        self.download_bar.setRange(0, 1000)
        self.download_bar.setValue(0)
        self.download_bar.setFormat("Cancelled")
        self.file_bar.setRange(0, 1000)
        self.file_bar.setValue(0)
        self.file_bar.setFormat("Cancelled")
        self.download_status.setText("Cancelled.")
        kept = str((self.stream_session or {}).get("files_dir") or "")
        note = "Download/extraction cancelled. The active partial file was removed."
        if kept:
            note += f"\n\nAny files already completed were kept here:\n{kept}"
        QMessageBox.information(self, "Cancelled", note)
        self.worker = None

    @Slot(str)
    def on_failed(self, message: str):
        self.finish_run_timing("Failed")
        # A QProgressBar with range 0..0 keeps animating forever. Freeze both
        # bars immediately so Failed really means all activity has stopped.
        self.set_running(False)
        self.download_bar.setRange(0, 1000)
        self.download_bar.setValue(0)
        self.download_bar.setFormat("Failed")
        self.file_bar.setRange(0, 1000)
        self.file_bar.setValue(0)
        self.file_bar.setFormat("Failed")
        self.download_status.setText("Failed — stopped and cleaned up.")
        self.append_log("ERROR: " + message.replace("\n", " "))

        session = dict(self.stream_session or {})
        preserved_path = ""
        if session:
            if bool(session.get("keep_extracted_source")):
                preserve = self._run_helper_json([
                    "stream-preserve-failed",
                    str(session.get("prefix_dir") or ""),
                    str(session.get("session_id") or ""),
                ])
                if preserve.get("ok"):
                    preserved_path = str(preserve.get("path") or session.get("files_dir") or "")
                    self.download_status.setText("Failed — extracted files preserved.")
                    self.append_log("Extraction failed, but completed output was preserved at: " + preserved_path)
                elif preserve.get("error"):
                    self.append_log("Preserve warning: " + str(preserve.get("error")))
            else:
                cleanup = self._run_helper_json([
                    "stream-abort",
                    str(session.get("prefix_dir") or ""),
                    str(session.get("session_id") or ""),
                ])
                if cleanup.get("removed"):
                    self.append_log(
                        "Removed incomplete StreamExtract folder: "
                        + str(session.get("prefix_dir") or "")
                    )
                elif cleanup.get("error"):
                    self.append_log("Cleanup warning: " + str(cleanup.get("error")))
        self.stream_session = None
        shown_message = message
        if preserved_path:
            shown_message += (
                "\n\nKeep extracted installer files was enabled, so Moses preserved everything "
                "that had already been written instead of deleting it.\n\nPreserved at:\n"
                + preserved_path
            )
        QMessageBox.critical(self, "StreamExtract error", shown_message)
        self.worker = None

    def closeEvent(self, event):
        self.settings.setValue("performance/mode", self.performance_combo.currentText())
        if self.performance_combo.currentText() == "Custom":
            try:
                self.custom_rate_from_controls()
                self.settings.setValue("performance/custom_limit", self.custom_limit_text())
            except ValueError:
                pass
        self.settings.setValue("network/multipart_parallel", self.selected_multipart_parallel())
        self.settings.sync()

        if self.worker and self.cancel_btn.isEnabled():
            answer = QMessageBox.question(
                self, "Download in progress",
                "A download is still running. Cancel it and close?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer == QMessageBox.No:
                event.ignore()
                return
            self.worker.cancel()
        event.accept()


def main():
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    window = MainWindow()
    window.show()

    def center_window():
        screen = window.screen() or app.primaryScreen()
        if screen is None:
            return
        frame = window.frameGeometry()
        frame.moveCenter(screen.availableGeometry().center())
        window.move(frame.topLeft())

    QTimer.singleShot(0, center_window)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
__MOSES_STREAM_EXTRACT_V08__

cat > "$STREAMEXTRACT_DIR/sensor_core.py" <<'__MOSES_SENSOR_CORE_V08__'
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import psutil


@dataclass
class SensorSnapshot:
    cpu_temp: float | None = None
    gpu_temp: float | None = None
    gpu_junction_temp: float | None = None
    vram_temp: float | None = None
    fan_rpm: int | None = None
    cpu_usage: float | None = None
    gpu_usage: float | None = None
    source: str = "No hardware sensor backend detected"

    @property
    def hottest_temp(self) -> float | None:
        values = [
            self.cpu_temp,
            self.gpu_temp,
            self.gpu_junction_temp,
            self.vram_temp,
        ]
        values = [v for v in values if v is not None]
        return max(values) if values else None


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except (OSError, PermissionError):
        return None


def _read_number(path: Path) -> float | None:
    text = _read_text(path)
    if text is None:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _millideg_to_c(value: float | None) -> float | None:
    if value is None:
        return None
    return value / 1000.0 if abs(value) > 1000 else value


class LinuxSensorReader:
    """
    SteamOS/Linux sensor reader.

    AMD GPUs normally expose edge/junction/memory temperatures and fan data
    through the amdgpu hwmon device. Ryzen CPUs normally expose Tctl/Tdie
    through k10temp.
    """

    CPU_HWMON_NAMES = {"k10temp", "coretemp", "zenpower", "cpu_thermal"}

    def __init__(
        self,
        hwmon_root: Path = Path("/sys/class/hwmon"),
        drm_root: Path = Path("/sys/class/drm"),
    ):
        self.hwmon_root = hwmon_root
        self.drm_root = drm_root

    def _hwmons(self):
        if not self.hwmon_root.exists():
            return []
        return sorted(self.hwmon_root.glob("hwmon*"))

    def _temperatures(self, hwmon: Path):
        result = []
        for input_path in sorted(hwmon.glob("temp*_input")):
            stem = input_path.stem.replace("_input", "")
            label = _read_text(hwmon / f"{stem}_label") or stem
            value = _millideg_to_c(_read_number(input_path))
            if value is not None and -20 <= value <= 150:
                result.append((label.strip(), value, input_path))
        return result

    def _read_cpu_temp(self) -> float | None:
        candidates = []
        preferred = []
        for hwmon in self._hwmons():
            name = (_read_text(hwmon / "name") or "").lower()
            if name not in self.CPU_HWMON_NAMES:
                continue
            for label, value, _ in self._temperatures(hwmon):
                lower = label.lower()
                candidates.append(value)
                if any(x in lower for x in ("tctl", "tdie", "package", "cpu")):
                    preferred.append(value)

        vals = preferred or candidates
        return max(vals) if vals else None

    def _find_amdgpu_hwmon(self) -> Path | None:
        # First prefer hwmon entries explicitly named amdgpu.
        for hwmon in self._hwmons():
            if (_read_text(hwmon / "name") or "").lower() == "amdgpu":
                return hwmon

        # Fallback through DRM device hwmon links.
        for card in sorted(self.drm_root.glob("card[0-9]*")):
            hwmon_dir = card / "device" / "hwmon"
            if not hwmon_dir.exists():
                continue
            for hwmon in sorted(hwmon_dir.glob("hwmon*")):
                if (_read_text(hwmon / "name") or "").lower() == "amdgpu":
                    return hwmon
        return None

    def _read_gpu(self):
        gpu_temp = None
        junction = None
        vram = None
        fan = None

        hwmon = self._find_amdgpu_hwmon()
        if hwmon is not None:
            unlabeled = []
            for label, value, path in self._temperatures(hwmon):
                lower = label.lower()
                if any(x in lower for x in ("mem", "memory", "vram")):
                    vram = value if vram is None else max(vram, value)
                elif any(x in lower for x in ("junction", "hotspot", "hot spot")):
                    junction = value if junction is None else max(junction, value)
                elif any(x in lower for x in ("edge", "gpu")):
                    gpu_temp = value if gpu_temp is None else max(gpu_temp, value)
                else:
                    unlabeled.append((path.name, value))

            # On many amdgpu devices temp1 is edge if labels are absent.
            if gpu_temp is None and unlabeled:
                gpu_temp = unlabeled[0][1]

            fan_values = []
            for fan_path in sorted(hwmon.glob("fan*_input")):
                value = _read_number(fan_path)
                if value is not None and value >= 0:
                    fan_values.append(int(value))
            if fan_values:
                fan = max(fan_values)

        gpu_usage = None
        for card in sorted(self.drm_root.glob("card[0-9]*")):
            busy = _read_number(card / "device" / "gpu_busy_percent")
            if busy is not None and 0 <= busy <= 100:
                gpu_usage = busy
                break

        return gpu_temp, junction, vram, fan, gpu_usage

    def read(self) -> SensorSnapshot:
        gpu, junction, vram, fan, gpu_usage = self._read_gpu()
        return SensorSnapshot(
            cpu_temp=self._read_cpu_temp(),
            gpu_temp=gpu,
            gpu_junction_temp=junction,
            vram_temp=vram,
            fan_rpm=fan,
            cpu_usage=psutil.cpu_percent(interval=None),
            gpu_usage=gpu_usage,
            source="SteamOS/Linux hwmon",
        )


class WindowsSensorReader:
    """
    Windows temperatures are read from LibreHardwareMonitor's WMI namespace
    if LibreHardwareMonitor is running. CPU usage still works without it.
    """

    def __init__(self):
        self._wmi = None
        self._wmi_error = None
        try:
            import wmi
            self._wmi = wmi.WMI(namespace=r"root\LibreHardwareMonitor")
        except Exception as exc:
            self._wmi_error = str(exc)

    def read(self) -> SensorSnapshot:
        snap = SensorSnapshot(
            cpu_usage=psutil.cpu_percent(interval=None),
            source="Windows (LibreHardwareMonitor not detected)",
        )
        if self._wmi is None:
            return snap

        try:
            sensors = self._wmi.Sensor()
        except Exception:
            return snap

        cpu_temps = []
        gpu_temps = []
        junction_temps = []
        vram_temps = []
        fan_values = []
        gpu_loads = []

        for sensor in sensors:
            name = str(getattr(sensor, "Name", "") or "")
            identifier = str(getattr(sensor, "Identifier", "") or "")
            stype = str(getattr(sensor, "SensorType", "") or "")
            value = getattr(sensor, "Value", None)
            try:
                value = float(value)
            except (TypeError, ValueError):
                continue

            text = f"{name} {identifier}".lower()

            if stype.lower() == "temperature":
                if "gpu" in text:
                    if any(x in text for x in ("memory", "vram", "mem junction")):
                        vram_temps.append(value)
                    elif any(x in text for x in ("hot spot", "hotspot", "junction")):
                        junction_temps.append(value)
                    else:
                        gpu_temps.append(value)
                elif any(x in text for x in ("cpu", "package", "tctl", "tdie")):
                    cpu_temps.append(value)

            elif stype.lower() == "fan" and "gpu" in text:
                fan_values.append(int(value))

            elif stype.lower() == "load" and "gpu" in text and "core" in text:
                gpu_loads.append(value)

        snap.cpu_temp = max(cpu_temps) if cpu_temps else None
        snap.gpu_temp = max(gpu_temps) if gpu_temps else None
        snap.gpu_junction_temp = max(junction_temps) if junction_temps else None
        snap.vram_temp = max(vram_temps) if vram_temps else None
        snap.fan_rpm = max(fan_values) if fan_values else None
        snap.gpu_usage = max(gpu_loads) if gpu_loads else None
        snap.source = "Windows / LibreHardwareMonitor WMI"
        return snap


class SensorReader:
    def __init__(self):
        if sys.platform.startswith("linux"):
            self.backend = LinuxSensorReader()
        elif sys.platform == "win32":
            self.backend = WindowsSensorReader()
        else:
            self.backend = None

        # Prime psutil so later cpu_percent calls are meaningful.
        psutil.cpu_percent(interval=None)

    def read(self) -> SensorSnapshot:
        if self.backend is None:
            return SensorSnapshot(cpu_usage=psutil.cpu_percent(interval=None))
        try:
            return self.backend.read()
        except Exception:
            # Monitoring must never crash the main app.
            return SensorSnapshot(
                cpu_usage=psutil.cpu_percent(interval=None),
                source="Sensor read error",
            )

__MOSES_SENSOR_CORE_V08__
cp "$STREAMEXTRACT_DIR/sensor_core.py" "$TEMPOVERLAY_DIR/sensor_core.py"

cat > "$TEMPOVERLAY_DIR/temp_overlay.py" <<'__MOSES_TEMP_OVERLAY_V08__'
from __future__ import annotations

import sys

from PySide6.QtCore import QEvent, QObject, QTimer, Qt
from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QApplication, QHBoxLayout, QLabel, QMenu, QPushButton,
    QVBoxLayout, QWidget,
)

from sensor_core import SensorReader

APP_NAME = "TempOverlay"
APP_VERSION = "0.5"


def temp_text(value):
    return "—" if value is None else f"{value:.0f}°C"


def pct_text(value):
    return "—" if value is None else f"{value:.0f}%"


class DragFilter(QObject):
    """Forward child-widget mouse presses to compositor-driven dragging."""
    def __init__(self, overlay):
        super().__init__(overlay)
        self.overlay = overlay

    def eventFilter(self, obj, event):
        if event.type() == QEvent.MouseButtonPress:
            if event.button() == Qt.LeftButton:
                self.overlay.start_system_drag()
                return True
            if event.button() == Qt.RightButton:
                self.overlay.show_context_menu(event.globalPosition().toPoint())
                return True
        return False


class Overlay(QWidget):
    def __init__(self):
        super().__init__()
        self.reader = SensorReader()
        self.compact = False
        self.always_on_top = True

        self.setWindowTitle(APP_NAME)
        self.setWindowFlags(
            Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        )
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.resize(320, 255)

        self.panel = QWidget(self)
        self.panel.setObjectName("panel")
        self.panel.setStyleSheet("""
            QWidget#panel {
                background: rgba(20, 20, 20, 220);
                border: 1px solid rgba(255, 255, 255, 45);
                border-radius: 12px;
            }
            QLabel { color: white; font-size: 14px; }
            QLabel#title { font-size: 15px; font-weight: bold; }
            QLabel#dragHint { color: rgba(255,255,255,150); font-size: 11px; }
            QPushButton {
                color: white;
                background: rgba(255,255,255,25);
                border: none;
                border-radius: 8px;
                min-width: 30px;
                min-height: 26px;
            }
            QPushButton:hover { background: rgba(255,255,255,50); }
        """)

        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(self.panel)

        layout = QVBoxLayout(self.panel)
        layout.setContentsMargins(14, 10, 14, 12)
        layout.setSpacing(6)

        top = QHBoxLayout()
        self.title = QLabel("TempOverlay")
        self.title.setObjectName("title")
        self.drag_hint = QLabel("drag anywhere")
        self.drag_hint.setObjectName("dragHint")
        self.close_btn = QPushButton("×")
        self.close_btn.setToolTip("Close TempOverlay")
        self.close_btn.clicked.connect(self.close)

        top.addWidget(self.title)
        top.addWidget(self.drag_hint)
        top.addStretch(1)
        top.addWidget(self.close_btn)
        layout.addLayout(top)

        self.cpu = QLabel("CPU                 —")
        self.gpu = QLabel("GPU                 —")
        self.junction = QLabel("GPU Junction        —")
        self.vram = QLabel("VRAM                —")
        self.fan = QLabel("Fan                 —")
        self.load = QLabel("CPU load —   GPU load —")
        self.source = QLabel("")
        self.source.setWordWrap(True)
        self.source.setStyleSheet(
            "color: rgba(255,255,255,150); font-size: 11px;"
        )

        for label in (
            self.cpu, self.gpu, self.junction,
            self.vram, self.fan, self.load, self.source
        ):
            layout.addWidget(label)

        # Make the whole visible surface draggable except the close button.
        self.drag_filter = DragFilter(self)
        for widget in (
            self.panel, self.title, self.drag_hint, self.cpu, self.gpu,
            self.junction, self.vram, self.fan, self.load, self.source
        ):
            widget.installEventFilter(self.drag_filter)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(1000)
        self.refresh()

    def refresh(self):
        s = self.reader.read()
        self.cpu.setText(f"CPU                 {temp_text(s.cpu_temp)}")
        self.gpu.setText(f"GPU                 {temp_text(s.gpu_temp)}")
        self.junction.setText(
            f"GPU Junction        {temp_text(s.gpu_junction_temp)}"
        )
        self.vram.setText(f"VRAM                {temp_text(s.vram_temp)}")
        self.fan.setText(
            "Fan                 —" if s.fan_rpm is None
            else f"Fan                 {s.fan_rpm} RPM"
        )
        self.load.setText(
            f"CPU load {pct_text(s.cpu_usage)}   GPU load {pct_text(s.gpu_usage)}"
        )
        self.source.setText(s.source)

    def start_system_drag(self):
        # Correct way to move a top-level window on KDE Wayland.
        handle = self.windowHandle()
        if handle is not None:
            try:
                handle.startSystemMove()
            except Exception:
                pass

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.start_system_drag()
            event.accept()
            return
        if event.button() == Qt.RightButton:
            self.show_context_menu(event.globalPosition().toPoint())
            event.accept()
            return
        super().mousePressEvent(event)

    def show_context_menu(self, pos):
        menu = QMenu(self)

        pin_action = QAction("Always on top (KDE): ON", self)
        pin_action.setEnabled(False)
        menu.addAction(pin_action)

        compact_action = QAction("Compact mode", self, checkable=True)
        compact_action.setChecked(self.compact)
        compact_action.triggered.connect(self.toggle_compact)
        menu.addAction(compact_action)

        menu.addSeparator()
        quit_action = QAction("Quit", self)
        quit_action.triggered.connect(self.close)
        menu.addAction(quit_action)
        menu.exec(pos)

    def toggle_always_on_top(self, checked):
        # The SteamOS installer enforces Keep Above through a KWin rule.
        self.always_on_top = True
        self.show()

    def toggle_compact(self, checked):
        self.compact = checked
        for widget in (self.junction, self.fan, self.load, self.source):
            widget.setVisible(not checked)
        self.adjustSize()


def main():
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    try:
        app.setDesktopFileName("tempoverlay")
    except Exception:
        pass
    overlay = Overlay()
    overlay.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

__MOSES_TEMP_OVERLAY_V08__

cat > "$STREAMTOOLS_ROOT/requirements.txt" <<'__MOSES_STREAM_REQS__'
PySide6>=6.7,<7
httpx>=0.27,<1
stream-unzip>=0.0.99
backports.zstd>=1.0.0; python_version < "3.14"
psutil>=5.9,<8
__MOSES_STREAM_REQS__

python3 -m py_compile \
  "$STREAMEXTRACT_DIR/stream_extract_gui.py" \
  "$STREAMEXTRACT_DIR/sensor_core.py" \
  "$TEMPOVERLAY_DIR/temp_overlay.py" \
  "$TEMPOVERLAY_DIR/sensor_core.py"

STREAM_VENV_OK=0
if [[ -x "$STREAMTOOLS_VENV/bin/python" ]]; then
  if "$STREAMTOOLS_VENV/bin/python" -c 'import PySide6, httpx, stream_unzip, psutil, sys, importlib; importlib.import_module("backports.zstd.zipfile" if sys.version_info < (3,14) else "zipfile")' >/dev/null 2>&1; then
    STREAM_VENV_OK=1
  fi
fi

if [[ "$STREAM_VENV_OK" -ne 1 ]]; then
  echo "Preparing StreamExtract / TempOverlay dependencies..."
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -m venv --help >/dev/null 2>&1; then
    echo "ERROR: Python 3 with the venv module is required for StreamExtract and TempOverlay."
    exit 1
  fi
  rm -rf "$STREAMTOOLS_VENV"
  python3 -m venv "$STREAMTOOLS_VENV"
  PIP_DISABLE_PIP_VERSION_CHECK=1 "$STREAMTOOLS_VENV/bin/python" -m pip install --upgrade pip
  PIP_DISABLE_PIP_VERSION_CHECK=1 "$STREAMTOOLS_VENV/bin/python" -m pip install -r "$STREAMTOOLS_ROOT/requirements.txt"
fi

cat > "$STREAMEXTRACT_LAUNCHER" <<EOF
#!/usr/bin/env bash
exec "$STREAMTOOLS_VENV/bin/python" "$STREAMEXTRACT_DIR/stream_extract_gui.py" "\$@"
EOF
cat > "$TEMPOVERLAY_LAUNCHER" <<EOF
#!/usr/bin/env bash
exec "$STREAMTOOLS_VENV/bin/python" "$TEMPOVERLAY_DIR/temp_overlay.py" "\$@"
EOF
chmod +x "$STREAMEXTRACT_LAUNCHER" "$TEMPOVERLAY_LAUNCHER"

# TempOverlay v0.8 deliberately keeps its own dark translucent theme.  KWin's
# explicit Keep Above rule makes the overlay reliable on SteamOS/Plasma Wayland.
if command -v kwriteconfig6 >/dev/null 2>&1 && command -v kreadconfig6 >/dev/null 2>&1; then
  CURRENT_RULES="$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
  FOUND=0
  IFS=',' read -r -a RULE_ARRAY <<< "$CURRENT_RULES"
  CLEAN_RULES=()
  for RULE in "${RULE_ARRAY[@]:-}"; do
    RULE="${RULE//[[:space:]]/}"
    [[ -z "$RULE" ]] && continue
    CLEAN_RULES+=("$RULE")
    [[ "$RULE" == "$TEMPOVERLAY_KWIN_RULE_ID" ]] && FOUND=1
  done
  [[ "$FOUND" -eq 0 ]] && CLEAN_RULES+=("$TEMPOVERLAY_KWIN_RULE_ID")
  kwriteconfig6 --file kwinrulesrc --group "$TEMPOVERLAY_KWIN_RULE_ID" --key Description "Moses OneClick TempOverlay - Always on top"
  kwriteconfig6 --file kwinrulesrc --group "$TEMPOVERLAY_KWIN_RULE_ID" --key title "TempOverlay"
  kwriteconfig6 --file kwinrulesrc --group "$TEMPOVERLAY_KWIN_RULE_ID" --key titlematch 1
  kwriteconfig6 --file kwinrulesrc --group "$TEMPOVERLAY_KWIN_RULE_ID" --key above true
  kwriteconfig6 --file kwinrulesrc --group "$TEMPOVERLAY_KWIN_RULE_ID" --key aboverule 2
  kwriteconfig6 --file kwinrulesrc --group General --key rules "$(IFS=','; echo "${CLEAN_RULES[*]}")"
  kwriteconfig6 --file kwinrulesrc --group General --key count "${#CLEAN_RULES[@]}"
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  fi
fi

cat > "$HELPER" <<'__PYHELPER_41C2__'
#!/usr/bin/env python3

import binascii
import configparser
import difflib
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import struct
import sys
import tarfile
import tempfile
import traceback
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

APP_ID = "net.lutris.Lutris"
CACHE_DIR = Path.home() / ".cache/lutris-exe-helper"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
TOOLS_GUI_PATH = Path.home() / ".local/share/lutris-oneclick/lutris_oneclick_tools.py"
ACTION_GUI_PATH = Path.home() / ".local/share/lutris-oneclick/oneclick_action_dialog.py"
BACKGROUND_ARTWORK_LOG = CACHE_DIR / "background-artwork.log"
ACTION_DIALOG_LOG = CACHE_DIR / "action-dialog.log"
ACTION_DIALOG_INTENTIONAL_CLOSE = CACHE_DIR / "action-dialog-intentional-close"

SETTINGS_FILE = Path.home() / ".var/app/net.lutris.Lutris/config/lutris-oneclick/settings.json"
STEAM_NATIVE_REGISTRY = Path.home() / ".local/share/oneclick-exe/steam-native-games.json"
REMOVAL_TOMBSTONE_DIR = Path.home() / ".local/share/oneclick-exe/removals"
RUNTIME_CACHE_ROOT = Path.home() / ".local/share/oneclick-exe/runtime-cache"
RUNTIME_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
STEAM_NATIVE_LOG = CACHE_DIR / "steam-native.log"
STEAM_SHORTCUT_DEBUG_LOG = CACHE_DIR / "steam-shortcut-debug.log"
ISO_INSTALL_LOG = CACHE_DIR / "iso-installer.log"
ISO_SESSION_DIR = CACHE_DIR / "iso-sessions"
ISO_SESSION_DIR.mkdir(parents=True, exist_ok=True)
PROTON_LOG_ROOT = CACHE_DIR / "proton-logs"
PROTON_LOG_ROOT.mkdir(parents=True, exist_ok=True)
DEFAULT_INSTALLER_BACKEND = "steam"
DEFAULT_STEAM_COMPAT_TOOL = "proton_experimental"
DEFAULT_ARTWORK_SOURCE = "both"
DEFAULT_LANGUAGE = "en"


def _load_ui_language():
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
        value = str(data.get("language") or DEFAULT_LANGUAGE).strip().lower()
        return value if value in {"en", "sv"} else DEFAULT_LANGUAGE
    except Exception:
        return DEFAULT_LANGUAGE


_HELPER_SV = {
    "Cancel": "Avbryt",
    "Continue": "Fortsätt",
    "Use this EXE": "Använd denna EXE",
    "Choose the main game EXE:": "Välj spelets huvud-EXE:",
    "Could not open main EXE chooser": "Kunde inte öppna valet av huvud-EXE",
    "Main EXE update failed": "Uppdatering av huvud-EXE misslyckades",
    "Apply EXE change now?": "Tillämpa EXE-bytet nu?",
    "Steam must reload this non-Steam shortcut before the new EXE can be used. Moses OneClick Tool can restart Steam cleanly now, apply the new EXE, and reopen Steam. Choose Cancel to apply it automatically the next time Steam closes or you switch modes.": "Steam måste läsa in den här icke-Steam-genvägen på nytt innan den nya EXE-filen kan användas. Moses OneClick Tool kan starta om Steam på ett säkert sätt nu, tillämpa den nya EXE-filen och öppna Steam igen. Välj Avbryt för att istället tillämpa ändringen automatiskt nästa gång Steam stängs eller du byter läge.",
    "Applying EXE change and restarting Steam…": "Tillämpar EXE-bytet och startar om Steam…",
    "Steam could not be stopped cleanly. The EXE change is saved and will apply the next time Steam is restarted.": "Steam kunde inte stängas på ett säkert sätt. EXE-bytet är sparat och tillämpas nästa gång Steam startas om.",
    "The Steam shortcut could not be finalized after the EXE change.": "Steam-genvägen kunde inte slutföras efter EXE-bytet.",
    "Steam did not become ready again after the EXE change. Open Steam normally; the new EXE has already been saved.": "Steam blev inte redo igen efter EXE-bytet. Öppna Steam normalt; den nya EXE-filen är redan sparad.",
    "EXE change pending Steam restart": "EXE-bytet väntar på omstart av Steam",
    "The new main EXE is saved, but Steam has not reloaded the shortcut yet. Restart Steam now so the new EXE can be launched.": "Den nya huvud-EXE-filen är sparad, men Steam har ännu inte läst in genvägen på nytt. Starta om Steam nu så att den nya EXE-filen kan startas.",
    "Detected game name (edit if needed):": "Upptäckt spelnamn (ändra vid behov):",
    "Steam installation folder could not be found.": "Steam-installationsmappen kunde inte hittas.",
    "Proton Experimental is not installed.": "Proton Experimental är inte installerat.",
    "No Steam-native One-Click games were found.": "Inga Steam-baserade Moses OneClick-spel hittades.",
    "The selected Steam-native game could not be found.": "Det valda Steam-spelet kunde inte hittas.",
    "Run this EXE inside which Steam game prefix?": "I vilket Steam-spelprefix ska denna EXE köras?",
    "Smart Lutris could not find a reliable online recipe. Using the normal local Lutris installer instead.": "Smart Lutris kunde inte hitta ett tillförlitligt online-recept. Den vanliga lokala Lutris-installationen används istället.",    "Final format confirmation": "Slutlig bekräftelse för formatering",
    "Name External Game Drive": "Namnge extern speldisk",
    "Format External Drive": "Formatera extern disk",
    "Choose the external drive/volume to format. Nothing is erased until you choose a filesystem and confirm FORMAT.": "Välj den externa disk/volym som ska formateras. Inget raderas förrän du väljer filsystem och bekräftar med FORMAT.",
    "No mounted removable/external drives were detected.": "Inga monterade flyttbara/externa diskar hittades.",
}


def _localize_helper_text(value):
    text = str(value)
    if _load_ui_language() != "sv":
        return text
    if text in _HELPER_SV:
        return _HELPER_SV[text]
    # Common fragments used by KDialog messages. Keep technical names untouched.
    replacements = [
        (" is already managed by the Steam backend.", " hanteras redan av Steam-backenden."),
        ("Re-run its installer anyway?", "Köra installationsprogrammet igen ändå?"),
        ("Install Proton Experimental from Steam first, then try the installer again.", "Installera Proton Experimental från Steam först och försök sedan igen."),
        ("Could not launch the installer with Proton Experimental:", "Kunde inte starta installationsprogrammet med Proton Experimental:"),
        ("Could not launch the update/patch with ", "Kunde inte starta uppdateringen/patchen med "),
        ("Log folder:", "Loggmapp:"),
        (" update exited unexpectedly. Retrying once automatically…", "-uppdateringen avslutades oväntat. Försöker automatiskt en gång till…"),
        (" update/patch finished. Steam was not restarted.", "-uppdateringen/patchen är klar. Steam startades inte om."),
        ("main EXE updated to", "huvud-EXE uppdaterad till"),
        ("External Lutris storage could not be prepared.", "Extern Lutris-lagring kunde inte förberedas."),
        ("No usable Lutris recipe was returned for", "Inget användbart Lutris-recept hittades för"),
        ("Using the normal local Lutris installer instead.", "Den vanliga lokala Lutris-installationen används istället."),
        ("Smart Lutris selected:", "Smart Lutris valde:"),
        ("Using", "Använder"),
        ("This is destructive. Type FORMAT to erase ", "Detta raderar allt. Skriv FORMAT för att radera "),
        (" and create ", " och skapa "),
        ("Choose the drive name that will be shown in SteamOS", "Välj diskens namn som ska visas i SteamOS"),
        (" and Windows", " och Windows"),
        ("You can change it later by formatting/renaming the volume again.", "Du kan ändra det senare genom att formatera/byta namn på volymen igen."),
        ("Could not unmount the external drive.", "Kunde inte avmontera den externa disken."),
        ("Formatting complete. Mounting the drive again…", "Formateringen är klar. Monterar disken igen…"),
        ("Setting safe SteamOS write permissions…", "Ställer in säkra skrivbehörigheter för SteamOS…"),
        ("drive is ready and writable.", "disken är klar och skrivbar."),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    return text


# V7.2.5: removable drives are identified by filesystem UUID, never by the
# temporary /run/media/deck/<label> mount path. The stable alias lives on the
# internal disk and is refreshed whenever the same physical volume is mounted
# again (including Gaming Mode).
EXTERNAL_DRIVE_REGISTRY = Path.home() / ".local/share/oneclick-exe/external-drive-registry.json"
EXTERNAL_ALIAS_ROOT = Path.home() / ".local/share/oneclick-exe/external-drive-links"
INTERNAL_PREFIX_ROOT = Path.home() / ".local/share/oneclick-exe/game-prefixes/Steam-Proton"
STREAM_STAGING_ROOT = Path.home() / ".local/share/oneclick-exe/stream-staging"


def _load_external_drive_registry():
    try:
        data = json.loads(EXTERNAL_DRIVE_REGISTRY.read_text(encoding="utf-8"))
        drives = data.get("drives", {}) if isinstance(data, dict) else {}
        return drives if isinstance(drives, dict) else {}
    except Exception:
        return {}


def _save_external_drive_registry(drives):
    EXTERNAL_DRIVE_REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    tmp = EXTERNAL_DRIVE_REGISTRY.with_suffix(".tmp")
    tmp.write_text(json.dumps({"version": 1, "drives": drives}, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(EXTERNAL_DRIVE_REGISTRY)


def _lsblk_uuid_records():
    try:
        result = subprocess.run(
            ["lsblk", "-J", "-o", "PATH,UUID,LABEL,FSTYPE,MOUNTPOINTS,RM,HOTPLUG"],
            text=True, capture_output=True, timeout=8, check=False,
        )
        data = json.loads(result.stdout or "{}") if result.returncode == 0 else {}
    except Exception:
        data = {}
    records = []
    def walk(nodes):
        for node in nodes or []:
            records.append(node)
            walk(node.get("children") or [])
    walk(data.get("blockdevices") or [])
    return records


def _filesystem_uuid_for_path(path_text):
    path = str(path_text or "").strip()
    if not path:
        return ""
    try:
        result = subprocess.run(
            ["findmnt", "-no", "UUID", "-T", path],
            text=True, capture_output=True, timeout=8, check=False,
        )
        value = (result.stdout or "").strip()
        if value:
            return value
    except Exception:
        pass
    try:
        source = subprocess.run(
            ["findmnt", "-no", "SOURCE", "-T", path],
            text=True, capture_output=True, timeout=8, check=False,
        ).stdout.strip()
        if source:
            value = subprocess.run(
                ["lsblk", "-no", "UUID", source],
                text=True, capture_output=True, timeout=8, check=False,
            ).stdout.strip()
            return value
    except Exception:
        pass
    return ""


def _block_record_for_uuid(uuid_text):
    wanted = str(uuid_text or "").strip().casefold()
    if not wanted:
        return None
    for node in _lsblk_uuid_records():
        if str(node.get("uuid") or "").strip().casefold() == wanted:
            return node
    return None


def _mounted_path_from_record(node):
    mounts = (node or {}).get("mountpoints") or []
    if isinstance(mounts, str):
        mounts = [mounts]
    for mount in mounts:
        if mount and Path(str(mount)).is_dir():
            return Path(str(mount))
    return None


def _refresh_external_drive_alias(uuid_text, try_mount=False):
    """Return the stable internal alias for UUID and refresh it to current mount.

    When try_mount=True, a present-but-unmounted removable volume is mounted via
    UDisks as the logged-in user. This is what makes known Btrfs/ext4 USB drives
    usable after unplug/replug in SteamOS Gaming Mode.
    """
    uuid_text = str(uuid_text or "").strip()
    if not uuid_text:
        return None
    EXTERNAL_ALIAS_ROOT.mkdir(parents=True, exist_ok=True)
    alias = EXTERNAL_ALIAS_ROOT / uuid_text
    node = _block_record_for_uuid(uuid_text)
    mount = _mounted_path_from_record(node)
    if node and mount is None and try_mount:
        device = str(node.get("path") or "").strip()
        if device and shutil.which("udisksctl"):
            try:
                subprocess.run(
                    ["udisksctl", "mount", "-b", device, "--no-user-interaction"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=20, check=False,
                )
            except Exception:
                pass
            for _ in range(20):
                time.sleep(0.25)
                node = _block_record_for_uuid(uuid_text)
                mount = _mounted_path_from_record(node)
                if mount is not None:
                    break
    if mount is not None:
        try:
            current = Path(os.readlink(alias)) if alias.is_symlink() else None
        except Exception:
            current = None
        if alias.exists() and not alias.is_symlink():
            # Never destroy a real user directory. Use a UUID-suffixed fallback.
            alias = EXTERNAL_ALIAS_ROOT / (uuid_text + ".link")
        if current is None or str(current) != str(mount):
            try:
                if alias.is_symlink() or alias.exists():
                    alias.unlink()
            except Exception:
                pass
            try:
                alias.symlink_to(mount, target_is_directory=True)
            except Exception:
                pass
        drives = _load_external_drive_registry()
        rec = dict(drives.get(uuid_text) or {})
        rec.update({
            "uuid": uuid_text,
            "label": str((node or {}).get("label") or rec.get("label") or "External drive"),
            "fstype": str((node or {}).get("fstype") or rec.get("fstype") or ""),
            "device": str((node or {}).get("path") or rec.get("device") or ""),
            "last_mount": str(mount),
            "updated_at": int(time.time()),
        })
        drives[uuid_text] = rec
        try:
            _save_external_drive_registry(drives)
        except Exception:
            pass
    return alias


def _register_external_drive(storage_root):
    root = Path(str(storage_root)).expanduser().resolve()
    uuid_text = _filesystem_uuid_for_path(root)
    if not uuid_text:
        raise RuntimeError(
            "The external drive has no readable filesystem UUID. Reconnect it and try again."
        )
    drives = _load_external_drive_registry()
    rec = dict(drives.get(uuid_text) or {})
    rec.update({
        "uuid": uuid_text,
        "label": root.name,
        "fstype": _filesystem_type_for_path(root),
        "last_mount": str(root),
        "updated_at": int(time.time()),
    })
    drives[uuid_text] = rec
    _save_external_drive_registry(drives)
    alias = _refresh_external_drive_alias(uuid_text, try_mount=False)
    if alias is None:
        raise RuntimeError("Could not create the stable external-drive alias.")
    return uuid_text, alias


def _stable_external_path(real_path, storage_root):
    root = Path(str(storage_root)).expanduser().resolve()
    real = Path(str(real_path)).expanduser()
    uuid_text, alias = _register_external_drive(root)
    try:
        rel = real.resolve(strict=False).relative_to(root)
    except Exception:
        rel = Path(os.path.relpath(str(real), str(root)))
    return alias / rel, uuid_text


def _external_monitor_once(try_mount=True):
    drives = _load_external_drive_registry()
    for uuid_text in list(drives):
        try:
            _refresh_external_drive_alias(uuid_text, try_mount=try_mount)
        except Exception:
            pass


def external_monitor_loop():
    # Lightweight user-session monitor. It does no polling of game files; only
    # lsblk/UDisks state. Respect an intentional manual Unmount/Eject: we mount
    # on service startup or after a physical disconnect -> reconnect transition,
    # not repeatedly while the same still-present device remains unmounted.
    previous_present = {}
    while True:
        drives = _load_external_drive_registry()
        for uuid_text in list(drives):
            node = _block_record_for_uuid(uuid_text)
            present = node is not None
            mounted = _mounted_path_from_record(node) is not None if node else False
            was_present = previous_present.get(uuid_text)
            should_mount = bool(present and not mounted and (was_present is None or was_present is False))
            try:
                _refresh_external_drive_alias(uuid_text, try_mount=should_mount)
            except Exception:
                pass
            previous_present[uuid_text] = present
        time.sleep(2.0)



def _path_under_root(path_text, root_text):
    try:
        return Path(str(path_text)).expanduser().relative_to(Path(str(root_text)).expanduser())
    except Exception:
        return None


def migrate_external_steam_paths():
    """Migrate pre-7.2.3 external Steam games to UUID-stable aliases.

    Safe to run repeatedly. It never moves game bytes; it only rewrites
    OneClick's registry, Steam's numeric compatdata symlink and (when possible)
    the non-Steam shortcut path.
    """
    games = load_steam_registry()
    changed = 0
    root = steam_root_path()
    for key, original in list(games.items()):
        entry = dict(original or {})
        if str(entry.get("storage_mode") or "").lower() != "external":
            continue
        try:
            appid = int(entry.get("appid") or key)
        except Exception:
            continue
        game_name = str(entry.get("name") or appid)
        storage_root = str(entry.get("storage_root") or "").strip()
        uuid_text = str(entry.get("storage_uuid") or "").strip()
        if not uuid_text and storage_root and Path(storage_root).exists():
            uuid_text = _filesystem_uuid_for_path(storage_root)
        if not uuid_text:
            # Cannot safely infer identity from a disconnected label/path.
            continue
        alias = _refresh_external_drive_alias(uuid_text, try_mount=False)
        if alias is None:
            continue

        # Prefix relative location. New installs already store alias-based paths;
        # old ones usually store /run/media/deck/<label>/OneClick Games/...
        compat_text = str(entry.get("compatdata") or "").strip()
        rel_prefix = None
        old_prefix = None
        if compat_text:
            compat_path = Path(compat_text)
            if str(compat_path).startswith(str(EXTERNAL_ALIAS_ROOT)):
                # V7.1.8 already stored the UUID alias, including the old
                # visible 'Game [AppID]' folder name. Preserve that exact old
                # target long enough to rename it safely below.
                old_prefix = compat_path
                try:
                    rel_prefix = compat_path.relative_to(alias)
                except Exception:
                    rel_prefix = None
            else:
                rel_prefix = _path_under_root(compat_text, storage_root) if storage_root else None
        safe_name = _safe_filename(game_name).replace('-', ' ').strip() or 'Game'
        if rel_prefix is None:
            rel_prefix = Path("OneClick Games") / "Steam-Proton" / safe_name
        stable_prefix = alias / rel_prefix
        desired_prefix = alias / "OneClick Games" / "Steam-Proton" / safe_name
        if old_prefix is None:
            old_prefix = stable_prefix
        # V7.2.5 migration: older external prefixes were named 'Game [AppID]'.
        # Rename only this registry-owned prefix, never arbitrary user folders.
        try:
            if old_prefix != desired_prefix and old_prefix.exists():
                if not desired_prefix.exists():
                    old_prefix.rename(desired_prefix)
                    stable_prefix = desired_prefix
                elif desired_prefix.resolve(strict=False) == old_prefix.resolve(strict=False):
                    stable_prefix = desired_prefix
            elif desired_prefix.exists():
                stable_prefix = desired_prefix
        except Exception:
            pass

        if root:
            numeric = root / "steamapps" / "compatdata" / str(appid)
            try:
                if numeric.is_symlink():
                    literal = os.readlink(numeric)
                    if os.path.normpath(literal) != os.path.normpath(str(stable_prefix)):
                        numeric.unlink(missing_ok=True)
                        numeric.symlink_to(stable_prefix, target_is_directory=True)
                elif not numeric.exists():
                    numeric.symlink_to(stable_prefix, target_is_directory=True)
            except Exception:
                pass

        updates = {
            "storage_uuid": uuid_text,
            "compatdata": str(stable_prefix),
            "updated_at": int(time.time()),
        }
        for field in ("final_exe", "start_dir", "installer"):
            value = str(entry.get(field) or "").strip()
            if not value:
                continue
            value_path = Path(value)
            # If we just renamed an alias-based old 'Game [AppID]' prefix, keep
            # the same relative file inside the new plain game-name folder.
            try:
                rel_old = value_path.relative_to(old_prefix)
            except Exception:
                rel_old = None
            if rel_old is not None and stable_prefix != old_prefix:
                updates[field] = str(stable_prefix / rel_old)
                continue
            if str(value_path).startswith(str(EXTERNAL_ALIAS_ROOT)):
                continue
            rel = _path_under_root(value, storage_root) if storage_root else None
            if rel is not None:
                updates[field] = str(alias / rel)

        new_entry = update_steam_registry_entry(appid, **updates)
        changed += 1
        final_text = str(new_entry.get("final_exe") or "").strip()
        if final_text and str(new_entry.get("status") or "") in {"installed", "pending_steam", "detached"}:
            if _steam_main_process_running():
                update_steam_registry_entry(appid, status="pending_steam")
                try:
                    launch_deferred_steam_finalizer(appid)
                except Exception:
                    pass
            else:
                try:
                    _finalize_steam_shortcut_now(appid, game_name, Path(final_text), str(new_entry.get("icon") or ""))
                except Exception:
                    pass
    return changed


def load_oneclick_settings():
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def installer_backend():
    backend = str(load_oneclick_settings().get("installer_backend", DEFAULT_INSTALLER_BACKEND)).strip().lower()
    return backend if backend in {"steam", "smart", "lutris"} else DEFAULT_INSTALLER_BACKEND


def load_steam_registry():
    try:
        data = json.loads(STEAM_NATIVE_REGISTRY.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            games = data.get("games", {})
            return games if isinstance(games, dict) else {}
    except Exception:
        pass
    return {}


def save_steam_registry(games):
    STEAM_NATIVE_REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    temp = STEAM_NATIVE_REGISTRY.with_suffix(".tmp")
    temp.write_text(json.dumps({"version": 1, "games": games}, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(STEAM_NATIVE_REGISTRY)


def update_steam_registry_entry(appid, **updates):
    games = load_steam_registry()
    key = str(int(appid))
    entry = dict(games.get(key) or {})
    current_status = str(entry.get("status") or "")
    new_status = str(updates.get("status") or "")

    # V7.2.5: Complete Game Removal leaves a hidden tombstone instead of
    # deleting the row immediately. This prevents a delayed installer watcher,
    # artwork worker or Steam finalizer from resurrecting a game after removal.
    # A real new installation explicitly starts with status=installing and is
    # allowed to replace the tombstone with a clean registry entry.
    if current_status == "removed":
        if new_status == "installing":
            entry = {}
        elif new_status:
            return entry

    entry.update(updates)
    entry["appid"] = int(appid)
    games[key] = entry
    save_steam_registry(games)
    return entry


def remove_steam_registry_entry(appid):
    games = load_steam_registry()
    key = str(int(appid))
    if key in games:
        games.pop(key, None)
        save_steam_registry(games)
        return True
    return False


def _removal_tombstone_time(appid):
    try:
        path = REMOVAL_TOMBSTONE_DIR / f"{int(appid)}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        return int(data.get("removed_at") or 0)
    except Exception:
        return 0


def _clear_removal_tombstone(appid):
    try:
        (REMOVAL_TOMBSTONE_DIR / f"{int(appid)}.json").unlink(missing_ok=True)
    except Exception:
        pass


def _safe_filename(text):
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", str(text or "game")).strip("-._")
    return value[:80] or "game"


def _new_proton_log_dir(game_name, appid, started_at):
    folder = PROTON_LOG_ROOT / f"{_safe_filename(game_name)}-{int(appid)}-{int(started_at)}"
    folder.mkdir(parents=True, exist_ok=True)
    _prune_proton_logs()
    return folder


def _prune_proton_logs(keep=10):
    try:
        dirs = sorted(
            [x for x in PROTON_LOG_ROOT.iterdir() if x.is_dir()],
            key=lambda x: x.stat().st_mtime,
            reverse=True,
        )
        for old in dirs[int(keep):]:
            shutil.rmtree(old, ignore_errors=True)
    except Exception:
        pass


def _directory_size(path):
    total = 0
    try:
        for root, _dirs, files in os.walk(path):
            for name in files:
                try:
                    total += (Path(root) / name).stat().st_size
                except OSError:
                    pass
    except Exception:
        pass
    return total


def _human_size(size):
    value = float(max(0, int(size or 0)))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024.0 or unit == "TB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024.0
    return f"{value:.1f} TB"


ONECLICK_PREFIX_MARKER = ".oneclick-exe-prefix.json"
ONECLICK_EXTERNAL_MARKER = ".oneclick-exe-external-game.json"
STREAM_IN_PROGRESS_MARKER = ".streamextract-in-progress.json"
STREAM_COMPLETE_MARKER = ".streamextract-complete.json"
SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS = {"ext4", "btrfs", "xfs", "f2fs"}


def _mounted_external_storage_choices():
    """Return mounted removable/external volumes for the install-location dropdown."""
    choices = []
    seen = set()
    try:
        result = subprocess.run(
            ["lsblk", "-J", "-b", "-o", "NAME,LABEL,UUID,MOUNTPOINTS,FSTYPE,SIZE,TYPE,RM,HOTPLUG"],
            text=True, capture_output=True, timeout=8, check=False,
        )
        data = json.loads(result.stdout or "{}") if result.returncode == 0 else {}
    except Exception:
        data = {}

    def walk(nodes):
        for node in nodes or []:
            mounts = node.get("mountpoints") or []
            if isinstance(mounts, str):
                mounts = [mounts]
            rm = bool(node.get("rm"))
            hotplug = bool(node.get("hotplug"))
            label = str(node.get("label") or node.get("name") or "External drive").strip()
            fstype = str(node.get("fstype") or "").strip().lower()
            uuid_text = str(node.get("uuid") or "").strip()
            size = int(node.get("size") or 0)
            for mount in mounts:
                if not mount:
                    continue
                mp = Path(str(mount))
                text = str(mp)
                externalish = rm or hotplug or text.startswith("/run/media/") or text.startswith("/media/")
                if not externalish or text in {"/", "/home"} or text in seen:
                    continue
                try:
                    if not mp.is_dir():
                        continue
                    usage = shutil.disk_usage(mp)
                    writable = os.access(mp, os.W_OK)
                except Exception:
                    continue
                seen.add(text)
                choices.append({
                    "path": text,
                    "label": label,
                    "fstype": fstype,
                    "uuid": uuid_text,
                    "size": size,
                    "free": int(usage.free),
                    "writable": bool(writable),
                    "filesystem_supported": bool(fstype in SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS),
                    "supported": bool(writable and fstype in SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS),
                })
            walk(node.get("children") or [])

    walk(data.get("blockdevices") or [])
    choices.sort(key=lambda x: (not x.get("supported", False), str(x.get("label", "")).casefold()))
    return choices


def _filesystem_type_for_path(path):
    try:
        result = subprocess.run(
            ["findmnt", "-no", "FSTYPE", "-T", str(path)],
            text=True, capture_output=True, timeout=8, check=False,
        )
        return (result.stdout or "").strip().lower()
    except Exception:
        return ""


def _validate_external_storage(path_text):
    if not str(path_text or "").strip():
        return None
    path = Path(str(path_text)).expanduser().resolve()
    if not path.is_dir():
        raise RuntimeError(f"The selected external drive is no longer mounted:\n\n{path}")
    if not os.access(path, os.W_OK):
        raise RuntimeError(f"The selected external drive is not writable:\n\n{path}")
    fstype = _filesystem_type_for_path(path)
    if fstype not in SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS:
        supported = ", ".join(sorted(SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS))
        raise RuntimeError(
            "This drive cannot safely hold a Wine/Proton prefix in One-Click.\n\n"
            f"Drive: {path}\nFilesystem: {fstype or 'unknown'}\n\n"
            f"For reliable Desktop + Gaming Mode use, format/use a Linux filesystem such as: {supported}. "
            "exFAT/FAT are intentionally blocked because Wine/Proton prefixes require filesystem features such as symbolic links."
        )
    return path




def _external_block_device_for_mount(path_text):
    """Resolve a removable mounted filesystem to its block partition safely."""
    path = Path(str(path_text or "")).expanduser().resolve()
    if not path.is_dir():
        raise RuntimeError(f"External drive is no longer mounted:\n\n{path}")
    try:
        source = subprocess.run(
            ["findmnt", "-no", "SOURCE", "-T", str(path)],
            text=True, capture_output=True, timeout=8, check=False,
        ).stdout.strip()
    except Exception:
        source = ""
    if not source.startswith("/dev/"):
        raise RuntimeError(
            "One-Click could not resolve this mounted volume to a removable block device.\n\n"
            f"Mount: {path}\nSource: {source or 'unknown'}\n\n"
            "For safety, network mounts, loop images and virtual filesystems are never formatted."
        )
    # Never offer formatting for the filesystem backing / or /home.
    for protected in ("/", str(Path.home())):
        try:
            protected_source = subprocess.run(
                ["findmnt", "-no", "SOURCE", "-T", protected],
                text=True, capture_output=True, timeout=8, check=False,
            ).stdout.strip()
        except Exception:
            protected_source = ""
        if protected_source and protected_source == source:
            raise RuntimeError("One-Click refused to format a system/internal filesystem.")
    try:
        props = subprocess.run(
            ["lsblk", "-J", "-o", "PATH,RM,HOTPLUG,TYPE,MOUNTPOINTS,LABEL,FSTYPE", source],
            text=True, capture_output=True, timeout=8, check=False,
        )
        data = json.loads(props.stdout or "{}") if props.returncode == 0 else {}
        node = (data.get("blockdevices") or [{}])[0]
        removable = bool(node.get("rm")) or bool(node.get("hotplug")) or str(path).startswith(("/run/media/", "/media/"))
    except Exception:
        removable = str(path).startswith(("/run/media/", "/media/"))
    if not removable:
        raise RuntimeError(
            "One-Click only offers automatic formatting for removable/external volumes.\n\n"
            f"Device: {source}"
        )
    return source


def _sanitize_external_drive_label(value, filesystem="", fallback="OneClickGames"):
    """Return a conservative cross-tool volume label.

    ext4 labels are limited to 16 bytes, so keep that format intentionally
    short. Btrfs/NTFS can hold longer labels, but 32 characters keeps KDE and
    Windows mount names readable.
    """
    raw = str(value or "").strip() or str(fallback or "OneClickGames").strip() or "OneClickGames"
    clean = re.sub(r"[^A-Za-z0-9 _.-]+", "", raw).strip() or "OneClickGames"
    limit = 16 if str(filesystem or "").lower() == "ext4" else 32
    # ASCII-only sanitizing above makes character length equal byte length.
    return clean[:limit].rstrip(" .") or "OneClickGames"


def _external_drive_label(path_text, filesystem=""):
    name = Path(str(path_text)).name.strip() or "OneClickGames"
    return _sanitize_external_drive_label(name, filesystem, "OneClickGames")


def _remount_block_device(source):
    result = subprocess.run(
        ["udisksctl", "mount", "-b", str(source)],
        text=True, capture_output=True, timeout=45, check=False,
    )
    # Query the kernel rather than depending on localized udisksctl output.
    try:
        mounts = subprocess.run(
            ["lsblk", "-n", "-o", "MOUNTPOINTS", str(source)],
            text=True, capture_output=True, timeout=8, check=False,
        ).stdout.splitlines()
        for item in mounts:
            item = item.strip()
            if item and Path(item).is_dir():
                return Path(item).resolve()
    except Exception:
        pass
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "The formatted drive could not be mounted again.").strip())
    raise RuntimeError("The drive was formatted, but One-Click could not find its new mount point.")


def _make_external_volume_writable(mount_path, source):
    """Make a verified removable Linux game volume writable by the SteamOS user.

    ext4/Btrfs roots are normally root:root after formatting. This helper is
    used either immediately after OneClick formats a verified external volume
    or after the user explicitly approves a non-destructive permission repair.
    The mount is re-checked against the expected /dev block partition before
    ownership is changed.
    """
    mounted = Path(str(mount_path)).expanduser().resolve()
    if not mounted.is_dir():
        raise RuntimeError(f"The newly formatted drive is not mounted:\n\n{mounted}")

    # Re-verify that the path is still backed by the exact block partition we
    # just formatted.  Never chown an arbitrary path if the mount changed.
    try:
        actual_source = subprocess.run(
            ["findmnt", "-no", "SOURCE", "-T", str(mounted)],
            text=True, capture_output=True, timeout=8, check=False,
        ).stdout.strip()
    except Exception:
        actual_source = ""
    if not actual_source.startswith("/dev/"):
        raise RuntimeError(
            "One-Click mounted the formatted drive, but could not verify its block device before setting permissions."
        )
    try:
        same_device = os.path.realpath(actual_source) == os.path.realpath(str(source))
    except Exception:
        same_device = actual_source == str(source)
    if not same_device:
        raise RuntimeError(
            "One-Click refused to change permissions because the remounted volume no longer matches the formatted device.\n\n"
            f"Expected: {source}\nMounted: {actual_source}"
        )

    uid, gid = os.getuid(), os.getgid()
    ownership = subprocess.run(
        ["pkexec", "chown", f"{uid}:{gid}", str(mounted)],
        text=True, capture_output=True, check=False,
    )
    if ownership.returncode != 0:
        raise RuntimeError(
            (ownership.stderr or ownership.stdout or
             "The drive was formatted, but One-Click could not make it writable by your SteamOS user.").strip()
        )

    # A real create/delete probe catches read-only remounts and permission
    # problems more reliably than os.access() alone.
    probe = mounted / f".oneclick-write-test-{os.getpid()}"
    try:
        probe.write_text("OneClick write test\n", encoding="utf-8")
        probe.unlink()
    except Exception as exc:
        try:
            probe.unlink(missing_ok=True)
        except Exception:
            pass
        raise RuntimeError(
            "The drive was formatted and mounted, but is still not writable by the current SteamOS user.\n\n"
            f"Drive: {mounted}\nError: {exc}"
        )
    return mounted


def _format_external_storage_assistant(path_text, current_fstype="", standalone=False):
    """Offer destructive reformatting only after two explicit confirmations.

    Returns the new mount path, or None when the user cancels/chooses a mode
    that is not safe for a full Wine/Proton prefix. With standalone=True this
    is a Settings storage operation, so NTFS formatting is allowed to finish
    without trying to start a Wine/Proton installation.
    """
    path = Path(str(path_text)).expanduser().resolve()
    source = _external_block_device_for_mount(path)
    current = str(current_fstype or _filesystem_type_for_path(path) or "unknown").lower()
    choice = dialog([
        "--title", "Prepare External Game Drive",
        "--menu",
        f"{path.name or 'External drive'} currently uses {current}. Choose how this drive will be used.\n\nWARNING: formatting erases everything on the selected volume.",
        "btrfs", "SteamOS only — Btrfs (recommended + Space Saver)",
        "ext4", "SteamOS only — ext4 (simple and reliable)",
        "ntfs", "SteamOS + Windows — NTFS (cross-platform game files)",
        "cancel", "Cancel",
    ])
    if not choice or choice == "cancel":
        return None
    if choice == "ntfs":
        # A complete Proton/Wine prefix must not be placed on NTFS. OneClick's
        # cross-platform split-prefix mode is intentionally not faked here.
        if standalone:
            ntfs_message = (
                "NTFS is the recommended choice when the same external drive must also be readable/writable in Windows.\n\n"
                "Format this external volume as NTFS now?"
            )
        else:
            ntfs_message = (
                "NTFS is best when the same drive must also be readable/writable in Windows.\n\n"
                "One-Click keeps full Wine/Proton prefixes on Linux filesystems because prefixes use Linux filesystem features. "
                "The current External Install mode therefore cannot safely continue on NTFS yet.\n\n"
                "Format this volume as NTFS anyway? (The current game install will stop afterwards.)"
            )
        if not confirm(ntfs_message):
            return None
    else:
        if not confirm(
            f"FORMAT {source} AS {choice.upper()}?\n\n"
            f"Everything currently stored on:\n{path}\n\nWILL BE PERMANENTLY ERASED."
        ):
            return None
    typed = dialog([
        "--title", "Final format confirmation",
        "--inputbox",
        f"This is destructive. Type FORMAT to erase {source} and create {choice.upper()}:",
        "",
    ])
    if typed != "FORMAT":
        return None

    default_label = _external_drive_label(path, choice)
    requested_label = dialog([
        "--title", "Name External Game Drive",
        "--inputbox",
        (
            "Choose the drive name that will be shown in SteamOS"
            + (" and Windows" if choice == "ntfs" else "")
            + ".\n\nYou can change it later by formatting/renaming the volume again."
        ),
        default_label,
    ])
    if requested_label is None:
        return None
    label = _sanitize_external_drive_label(requested_label, choice, default_label)

    # Unmount as root. pkexec presents the normal KDE authentication dialog.
    unmount = subprocess.run(["pkexec", "umount", str(source)], text=True, capture_output=True, check=False)
    if unmount.returncode != 0:
        raise RuntimeError((unmount.stderr or unmount.stdout or "Could not unmount the external drive.").strip())

    if choice == "btrfs":
        formatter = shutil.which("mkfs.btrfs") or "/usr/bin/mkfs.btrfs"
        cmd = ["pkexec", formatter, "-f", "-L", label, str(source)]
    elif choice == "ext4":
        formatter = shutil.which("mkfs.ext4") or "/usr/bin/mkfs.ext4"
        cmd = ["pkexec", formatter, "-F", "-L", label, str(source)]
    else:
        formatter = shutil.which("mkfs.ntfs") or shutil.which("mkntfs")
        if not formatter:
            # Best effort remount of the still-unmounted volume before returning.
            try:
                _remount_block_device(source)
            except Exception:
                pass
            raise RuntimeError(
                "The NTFS formatter is not installed on this SteamOS image.\n\n"
                "No data was formatted. Choose Btrfs/ext4, or format the drive as NTFS using KDE Partition Manager."
            )
        cmd = ["pkexec", formatter, "-F", "-L", label, str(source)]

    progress = _SmartProgressDialog("OneClick External Storage", f"Formatting {source} as {choice.upper()}…", 100)
    try:
        progress.set(20, f"Unmounted {source}. Formatting as {choice.upper()}…")
        result = subprocess.run(cmd, text=True, capture_output=True, check=False)
        if result.returncode != 0:
            raise RuntimeError((result.stderr or result.stdout or f"{choice.upper()} formatting failed.").strip())
        progress.set(78, "Formatting complete. Mounting the drive again…")
        mounted = _remount_block_device(source)
        if choice in {"btrfs", "ext4"}:
            progress.set(90, "Setting safe SteamOS write permissions…")
            mounted = _make_external_volume_writable(mounted, source)
        progress.set(100, f"{choice.upper()} drive is ready and writable.")
    finally:
        progress.close()

    if choice == "ntfs" and not standalone:
        subprocess.run([
            "kdialog", "--msgbox",
            f"{mounted} is now NTFS and can be shared with Windows.\n\n"
            "The current One-Click full-prefix install was not started because Proton/Wine prefixes are intentionally kept off NTFS."
        ])
        return None
    return mounted


def _format_external_drive_from_settings():
    """Interactive Settings formatter for currently mounted external volumes."""
    drives = _mounted_external_storage_choices()
    if not drives:
        raise RuntimeError("No mounted removable/external drives were detected.")

    args = [
        "--title", "Format External Drive", "--menu",
        "Choose the external drive/volume to format. Nothing is erased until you choose a filesystem and confirm FORMAT.",
    ]
    mapping = {}
    for idx, drive in enumerate(drives):
        key = str(idx)
        path = str(drive.get("path") or "")
        label = str(drive.get("label") or Path(path).name or tr("External drive"))
        fstype = str(drive.get("fstype") or "unknown")
        size = _human_size(int(drive.get("size") or 0))
        args.extend([key, f"{label} — {fstype} — {size} — {path}"])
        mapping[key] = drive
    picked = dialog(args)
    if picked is None or picked not in mapping:
        return {"ok": False, "cancelled": True}

    drive = mapping[picked]
    mounted = _format_external_storage_assistant(
        str(drive.get("path") or ""),
        str(drive.get("fstype") or ""),
        standalone=True,
    )
    if not mounted:
        return {"ok": False, "cancelled": True}
    return {
        "ok": True,
        "path": str(mounted),
        "fstype": _filesystem_type_for_path(mounted),
        "label": Path(str(mounted)).name,
    }


def _btrfs_space_saver_targets():
    """Return safe, bounded Btrfs locations containing Proton/Wine prefixes."""
    targets = []
    seen = set()
    steam_root = steam_root_path()
    if steam_root:
        compat = steam_root / "steamapps" / "compatdata"
        if compat.is_dir() and _filesystem_type_for_path(compat) == "btrfs":
            key = str(compat.resolve())
            seen.add(key)
            targets.append({"id": "internal-steam", "label": "Internal Steam Proton prefixes", "path": key, "fstype": "btrfs"})
    for drive in _mounted_external_storage_choices():
        if str(drive.get("fstype") or "").lower() != "btrfs":
            continue
        root = Path(str(drive.get("path") or "")) / "OneClick Games"
        if not root.is_dir():
            continue
        key = str(root.resolve())
        if key in seen:
            continue
        seen.add(key)
        label = str(drive.get("label") or Path(str(drive.get("path") or "")).name or "External Btrfs")
        targets.append({"id": f"external-{len(targets)}", "label": f"External: {label} — OneClick Games", "path": key, "fstype": "btrfs"})
    return targets


def _ioc(direction, io_type, nr, size):
    return ((int(direction) << 30) | (int(io_type) << 8) | int(nr) | (int(size) << 16))


_FILE_DEDUPE_RANGE = struct.Struct("=QQH6x")
_FILE_DEDUPE_INFO = struct.Struct("=qQQl4x")
_FIDEDUPERANGE = _ioc(3, 0x94, 54, _FILE_DEDUPE_RANGE.size)


def _dedupe_exact_files(source, destinations):
    """Ask the kernel to merge exact file ranges. Returns logical bytes merged."""
    total = 0
    chunk = 16 * 1024 * 1024
    with open(source, "rb", buffering=0) as src:
        for dest_path in destinations:
            try:
                with open(dest_path, "r+b", buffering=0) as dst:
                    size = min(os.fstat(src.fileno()).st_size, os.fstat(dst.fileno()).st_size)
                    offset = 0
                    while offset < size:
                        length = min(chunk, size - offset)
                        buf = bytearray(_FILE_DEDUPE_RANGE.size + _FILE_DEDUPE_INFO.size)
                        _FILE_DEDUPE_RANGE.pack_into(buf, 0, offset, length, 1)
                        _FILE_DEDUPE_INFO.pack_into(buf, _FILE_DEDUPE_RANGE.size, dst.fileno(), offset, 0, 0)
                        try:
                            fcntl.ioctl(src.fileno(), _FIDEDUPERANGE, buf, True)
                            _fd, _off, bytes_done, status = _FILE_DEDUPE_INFO.unpack_from(buf, _FILE_DEDUPE_RANGE.size)
                            if status == 0:
                                total += int(bytes_done or 0)
                        except OSError:
                            # Unsupported/misaligned tails are simply skipped; the
                            # kernel itself performs the final exact-byte compare.
                            pass
                        offset += length
            except (OSError, PermissionError):
                continue
    return total


def _sha256_file(path, block=1024 * 1024):
    h = hashlib.sha256()
    with open(path, "rb", buffering=0) as fh:
        while True:
            data = fh.read(block)
            if not data:
                break
            h.update(data)
    return h.digest()


def run_btrfs_space_saver(target_path):
    allowed = {str(Path(x["path"]).resolve()): x for x in _btrfs_space_saver_targets()}
    target = str(Path(str(target_path)).expanduser().resolve())
    if target not in allowed:
        raise RuntimeError("The selected Space Saver target is no longer an approved OneClick Btrfs prefix location.")
    if _filesystem_type_for_path(target) != "btrfs":
        raise RuntimeError("Btrfs Space Saver only runs on Btrfs filesystems.")

    # Only regular files >=64 KiB are worthwhile. Symlinks and special files are
    # never opened for writing. Group by size before hashing to keep I/O sane.
    groups = {}
    file_count = 0
    logical = 0
    progress = _SmartProgressDialog("Btrfs Proton Space Saver", "Scanning Proton/Wine prefixes…", 100)
    before_free = shutil.disk_usage(target).free
    try:
        for root, dirs, files in os.walk(target, followlinks=False):
            dirs[:] = [d for d in dirs if not Path(root, d).is_symlink()]
            for name in files:
                path = Path(root) / name
                try:
                    if path.is_symlink() or not path.is_file():
                        continue
                    st = path.stat()
                    if st.st_size < 64 * 1024:
                        continue
                except OSError:
                    continue
                groups.setdefault(int(st.st_size), []).append(path)
                file_count += 1
                logical += int(st.st_size)
                if file_count % 500 == 0:
                    progress.set(10, f"Scanning… {file_count:,} candidate files")

        candidate_groups = [paths for paths in groups.values() if len(paths) > 1]
        progress.set(20, f"Hashing duplicate-size groups… {len(candidate_groups):,} group(s)")
        exact = {}
        done = 0
        for paths in candidate_groups:
            for path in paths:
                try:
                    digest = _sha256_file(path)
                except OSError:
                    continue
                exact.setdefault((path.stat().st_size, digest), []).append(path)
            done += 1
            if done % 25 == 0 or done == len(candidate_groups):
                pct = 20 + int(45 * done / max(1, len(candidate_groups)))
                progress.set(pct, f"Hashing… {done:,}/{len(candidate_groups):,} groups")

        duplicate_sets = [paths for paths in exact.values() if len(paths) > 1]
        progress.set(68, f"Deduplicating {len(duplicate_sets):,} exact duplicate set(s)…")
        deduped = 0
        for idx, paths in enumerate(duplicate_sets, 1):
            deduped += _dedupe_exact_files(paths[0], paths[1:])
            if idx % 5 == 0 or idx == len(duplicate_sets):
                pct = 68 + int(30 * idx / max(1, len(duplicate_sets)))
                progress.set(pct, f"Deduplicating… {idx:,}/{len(duplicate_sets):,} sets")
        try:
            os.sync()
        except Exception:
            pass
        after_free = shutil.disk_usage(target).free
        freed = max(0, int(after_free - before_free))
        progress.set(100, "Btrfs Space Saver complete.")
    finally:
        progress.close()

    return {
        "ok": True,
        "path": target,
        "candidate_files": file_count,
        "logical_scanned": logical,
        "duplicate_sets": len(duplicate_sets) if 'duplicate_sets' in locals() else 0,
        "deduped_ranges_bytes": int(deduped if 'deduped' in locals() else 0),
        "freed_bytes": int(freed if 'freed' in locals() else 0),
    }

def _external_game_folder(storage_root, backend, game_name, stable_id=""):
    root = _validate_external_storage(storage_root)
    if root is None:
        return None
    safe_name = _safe_filename(game_name).replace("-", " ").strip() or "Game"
    branch = "Steam-Proton" if backend == "steam" else "Lutris"
    # V7.2.5: the REAL external folder is the readable game name, just like
    # internal compatdata. Steam's numeric AppID remains only in its internal
    # compatibility symlink/metadata and is never needed in the visible folder.
    path = root / "OneClick Games" / branch / safe_name
    path.mkdir(parents=True, exist_ok=True)
    # Keep Lutris target directories empty before its installer starts. Store
    # the external-ownership marker next to the folder rather than inside it.
    try:
        marker = path.parent / f".{path.name}{ONECLICK_EXTERNAL_MARKER}"
        marker.write_text(
            json.dumps({
                "owner": "oneclick-exe", "backend": backend, "game": game_name,
                "stable_id": str(stable_id or ""), "path": str(path),
                "created_at": int(time.time())
            }, indent=2),
            encoding="utf-8",
        )
    except Exception:
        pass
    return path


def _ensure_lutris_external_access(storage_root):
    root = _validate_external_storage(storage_root)
    if root is None:
        return
    _uuid, alias = _register_external_drive(root)
    # Grant both the current mount and the stable internal alias. Lutris config
    # uses the alias so unplug/replug does not require rewriting its YAML.
    for allowed in (root, EXTERNAL_ALIAS_ROOT):
        result = subprocess.run(
            ["flatpak", "override", "--user", f"--filesystem={allowed}", APP_ID],
            text=True, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise RuntimeError((result.stderr or result.stdout or "Could not grant Lutris access to the external drive.").strip())


def _steam_named_prefix_name(game_name):
    """Human-readable real folder name for OneClick-owned Steam prefixes."""
    name = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', ' - ', str(game_name or 'Game')).strip().strip('.')
    name = re.sub(r'\s+', ' ', name)
    return name[:110] or 'Game'


def _prefix_marker_appid(path):
    try:
        data = json.loads((Path(path) / ONECLICK_PREFIX_MARKER).read_text(encoding='utf-8'))
        return int(data.get('appid'))
    except Exception:
        return None


def _prepare_internal_named_steam_compatdata(appid, game_name):
    """Keep the real internal Proton prefix in a clean game-name-only folder.

    V7.2.5 layout:
      ~/.local/share/oneclick-exe/game-prefixes/Steam-Proton/Hades II/  <- REAL
      Steam/steamapps/compatdata/2334157344 -> .../Hades II            <- Steam only

    Steam still receives the numeric AppID path Proton expects, but users who
    choose Open All Game Prefixes no longer have to see the numeric links. Old
    OneClick-owned named prefixes inside Steam/compatdata are migrated safely.
    Unknown/non-OneClick prefixes are never moved.
    """
    steam_root = steam_root_path()
    if not steam_root:
        raise RuntimeError('Steam installation folder could not be found')
    compat_root = steam_root / 'steamapps' / 'compatdata'
    compat_root.mkdir(parents=True, exist_ok=True)
    INTERNAL_PREFIX_ROOT.mkdir(parents=True, exist_ok=True)
    numeric = compat_root / str(int(appid))
    base = _steam_named_prefix_name(game_name)
    named = INTERNAL_PREFIX_ROOT / base

    def choose_named_target():
        candidate = named
        if candidate.exists() or candidate.is_symlink():
            if candidate.is_dir() and not candidate.is_symlink() and _prefix_marker_appid(candidate) == int(appid):
                return candidate
            candidate = INTERNAL_PREFIX_ROOT / f'{base} [{int(appid)}]'
        return candidate

    def move_old_internal_target(old_target):
        old_target = Path(old_target)
        if old_target.parent != compat_root or _prefix_marker_appid(old_target) != int(appid):
            return old_target
        target = choose_named_target()
        if target.exists() and target.resolve(strict=False) != old_target.resolve(strict=False):
            if _prefix_marker_appid(target) != int(appid):
                raise RuntimeError(f'A game-named prefix folder already exists:\n\n{target}')
            return target
        if old_target.resolve(strict=False) != target.resolve(strict=False):
            old_target.rename(target)
        return target

    # Already using a OneClick symlink. Migrate an old same-filesystem named
    # target out of raw Steam compatdata; leave external targets alone.
    if numeric.is_symlink():
        target = numeric.resolve(strict=False)
        if target.exists() and target.is_dir() and _prefix_marker_appid(target) == int(appid):
            if target.parent == compat_root:
                target = move_old_internal_target(target)
                numeric.unlink(missing_ok=True)
                numeric.symlink_to(target, target_is_directory=True)
            elif target == INTERNAL_PREFIX_ROOT or INTERNAL_PREFIX_ROOT in target.parents:
                pass
            else:
                # A connected external OneClick prefix belongs to a different
                # storage mode; never silently convert it to internal.
                raise RuntimeError(
                    f'Steam AppID {appid} already points at another OneClick prefix:\n\n{target}\n\n'
                    'Use Complete Game Removal before changing this game to internal storage.'
                )
            _write_oneclick_prefix_marker(target, appid)
            return target

        raw_target = ''
        try:
            raw_target = os.readlink(numeric)
        except Exception:
            pass
        if not target.exists() and ('/run/media/' in raw_target or '/media/' in raw_target or 'OneClick Games' in raw_target or 'external-drive-links' in raw_target):
            numeric.unlink(missing_ok=True)
        elif target.exists():
            raise RuntimeError(
                f'Steam AppID {appid} already points at another prefix:\n\n{target}\n\n'
                'Use Complete Game Removal before changing this game to internal storage.'
            )
        else:
            numeric.unlink(missing_ok=True)

    # Migrate only real numeric prefixes that carry OneClick's ownership marker.
    if numeric.exists() and not numeric.is_symlink():
        if _prefix_marker_appid(numeric) != int(appid):
            raise RuntimeError(
                f'Steam already has a real compatdata folder for AppID {appid}:\n\n{numeric}\n\n'
                'Moses OneClick Tool will not move an unowned Steam/Proton prefix.'
            )
        target = choose_named_target()
        if target.exists() and target.resolve(strict=False) != numeric.resolve(strict=False):
            raise RuntimeError(f'A game-named prefix folder already exists:\n\n{target}')
        numeric.rename(target)
        numeric.symlink_to(target, target_is_directory=True)
        _write_oneclick_prefix_marker(target, appid)
        return target

    target = choose_named_target()
    target.mkdir(parents=True, exist_ok=True)
    _write_oneclick_prefix_marker(target, appid)
    if not numeric.exists() and not numeric.is_symlink():
        numeric.symlink_to(target, target_is_directory=True)
    return target

def _prepare_external_steam_compatdata(appid, game_name, storage_root):
    steam_root = steam_root_path()
    if not steam_root:
        raise RuntimeError("Steam installation folder could not be found")
    real_target = _external_game_folder(storage_root, "steam", game_name, str(int(appid)))
    target, uuid_text = _stable_external_path(real_target, storage_root)
    expected = steam_root / "steamapps" / "compatdata" / str(int(appid))
    expected.parent.mkdir(parents=True, exist_ok=True)

    if expected.is_symlink():
        try:
            # Compare the literal symlink destination too; resolve() can hide a
            # stale mount-path difference while a removable drive is absent.
            literal = os.readlink(expected)
            if os.path.normpath(literal) != os.path.normpath(str(target)):
                expected.unlink()
        except Exception:
            expected.unlink(missing_ok=True)
    elif expected.exists():
        # Never replace a real prefix silently. If it is only our own empty/new
        # prefix from this AppID, move it into the external target first.
        marker = expected / ONECLICK_PREFIX_MARKER
        if marker.is_file():
            try:
                real_target.mkdir(parents=True, exist_ok=True)
                for child in expected.iterdir():
                    if child.name == ONECLICK_PREFIX_MARKER:
                        continue
                    dest = real_target / child.name
                    if dest.exists():
                        raise RuntimeError(
                            f"Both internal and external prefix data already exist for {game_name}. "
                            "Use Complete Game Removal first, then retry the external install."
                        )
                    shutil.move(str(child), str(dest))
                shutil.rmtree(expected)
            except Exception as exc:
                raise RuntimeError(f"Could not move the existing One-Click prefix to external storage: {exc}") from exc
        else:
            raise RuntimeError(
                f"Steam already has a real compatdata folder for AppID {appid}:\n\n{expected}\n\n"
                "One-Click will not replace it with an external-storage link. Remove the old game/prefix first."
            )

    if not expected.exists() and not expected.is_symlink():
        expected.symlink_to(target, target_is_directory=True)
    _write_oneclick_prefix_marker(target, appid)
    return target


def _write_oneclick_prefix_marker(compatdata, appid):
    try:
        path = Path(compatdata)
        path.mkdir(parents=True, exist_ok=True)
        (path / ONECLICK_PREFIX_MARKER).write_text(
            json.dumps({"appid": int(appid), "created_at": int(time.time()), "owner": "oneclick-exe"}, indent=2),
            encoding="utf-8",
        )
    except Exception:
        pass


def _steam_shortcut_appids():
    path = _steam_shortcuts_vdf_path()
    if not path or not path.is_file():
        return set()
    code = r'''
import sys
from lutris.util.steam import vdf
path = sys.argv[1]
try:
    with open(path, "rb") as f:
        root = vdf.binary_loads(f.read())
except FileNotFoundError:
    raise SystemExit(0)
for item in (root.get("shortcuts") or {}).values():
    try:
        print(int(item.get("appid", 0)) & 0xffffffff)
    except Exception:
        pass
'''
    try:
        args = ["flatpak", "run", f"--filesystem={path.parent}:rw", "--command=python3", APP_ID,
                "-c", code, str(path)]
        result = subprocess.run(args, text=True, capture_output=True, timeout=20)
        if result.returncode != 0:
            # Lutris normally already has Steam filesystem access. Retry without
            # a per-run filesystem override for older Flatpak builds that do
            # not accept the :rw override syntax.
            result = subprocess.run(
                ["flatpak", "run", "--command=python3", APP_ID, "-c", code, str(path)],
                text=True, capture_output=True, timeout=20,
            )
        if result.returncode != 0:
            _steam_log_shortcut(
                f"read shortcuts failed path={path} rc={result.returncode} error={(result.stderr or result.stdout).strip()}"
            )
            return set()
        ids = {int(x.strip()) for x in result.stdout.splitlines() if x.strip().isdigit()}
        _steam_log_shortcut(f"read shortcuts path={path} count={len(ids)}")
        return ids
    except Exception as exc:
        _steam_log_shortcut(f"read shortcuts exception path={path}: {exc}")
        return set()


def _historical_oneclick_appids():
    ids = set()
    for key in load_steam_registry().keys():
        try:
            ids.add(int(key))
        except Exception:
            pass
    try:
        if STEAM_NATIVE_LOG.is_file():
            log_text = STEAM_NATIVE_LOG.read_text(encoding="utf-8", errors="replace")
            ids.update(int(x) for x in re.findall(r"/compatdata/(\d+)(?:/|\\)", log_text))
    except Exception:
        pass
    try:
        for item in PROTON_LOG_ROOT.iterdir():
            if item.is_dir():
                match = re.search(r"-(\d+)-\d+$", item.name)
                if match:
                    ids.add(int(match.group(1)))
    except Exception:
        pass
    root = steam_root_path()
    if root:
        compat_root = root / "steamapps" / "compatdata"
        try:
            for item in compat_root.iterdir():
                if item.is_dir() and item.name.isdigit() and (item / ONECLICK_PREFIX_MARKER).is_file():
                    ids.add(int(item.name))
        except Exception:
            pass
    return ids


def _safe_remove_failed_compatdata(appid, entry=None):
    entry = dict(entry or (load_steam_registry().get(str(int(appid))) or {}))
    if not entry or not bool(entry.get("cleanup_on_failure", False)):
        return 0, False
    if entry.get("final_exe"):
        return 0, False
    path_text = str(entry.get("compatdata") or "").strip()
    if not path_text:
        return 0, False
    root = steam_root_path()
    if not root:
        return 0, False
    path = Path(path_text).expanduser()
    expected = root / "steamapps" / "compatdata" / str(int(appid))
    try:
        if path.resolve() != expected.resolve():
            return 0, False
    except Exception:
        return 0, False
    if not path.exists():
        return 0, True
    size = _directory_size(path)
    shutil.rmtree(path)
    try:
        if expected.is_symlink():
            expected.unlink(missing_ok=True)
    except Exception:
        pass
    return size, True


def cleanup_tracked_failed_installs():
    """Remove orphaned One-Click Steam prefixes, including older V6 failures."""
    root = steam_root_path()
    if not root:
        return {"removed_count": 0, "bytes": 0, "removed": [], "skipped": ["Steam root not found"]}
    games = load_steam_registry()
    active_shortcuts = _steam_shortcut_appids()
    candidates = _historical_oneclick_appids()
    compat_root = root / "steamapps" / "compatdata"
    removed, skipped = _cleanup_failed_stream_prefixes(games)
    changed = False
    for appid in sorted(candidates):
        key = str(int(appid))
        entry = dict(games.get(key) or {})
        name = str(entry.get("name") or f"One-Click AppID {appid}")
        steam_link = compat_root / key
        path_text = str(entry.get("compatdata") or "").strip()
        path = Path(path_text).expanduser() if path_text else steam_link
        if int(appid) in active_shortcuts:
            skipped.append(name)
            continue
        final_exe = str(entry.get("final_exe") or "").strip()
        if final_exe and Path(final_exe).is_file():
            skipped.append(name)
            continue
        if str(entry.get("status") or "") in {"installed", "pending_steam"} and final_exe:
            skipped.append(name)
            continue
        try:
            # Internal prefixes resolve to themselves; external OneClick prefixes
            # resolve through Steam's numeric compatdata symlink to the same target.
            if path.resolve(strict=False) != steam_link.resolve(strict=False):
                skipped.append(name)
                continue
        except Exception:
            skipped.append(name)
            continue
        if not path.exists():
            if entry and str(entry.get("status") or "").startswith("install_failed"):
                entry["status"] = "install_failed_cleaned"
                entry["compatdata"] = ""
                games[key] = entry
                changed = True
            continue
        size = _directory_size(path)
        try:
            shutil.rmtree(path)
            if steam_link.is_symlink():
                steam_link.unlink(missing_ok=True)
        except Exception:
            skipped.append(name)
            continue
        removed.append((name, size))
        if entry:
            entry["status"] = "install_failed_cleaned"
            entry["compatdata"] = ""
            games[key] = entry
            changed = True
    if changed:
        save_steam_registry(games)
    return {
        "removed_count": len(removed),
        "bytes": sum(size for _name, size in removed),
        "removed": [name for name, _size in removed],
        "skipped": skipped,
        "candidates": len(candidates),
    }


def _steam_log_shortcut(message):
    try:
        with open(STEAM_SHORTCUT_DEBUG_LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.ctime()}: {message}\n")
    except Exception:
        pass


def _steam_root_candidates():
    candidates = [
        Path.home() / ".local/share/Steam",
        Path.home() / ".steam/steam",
        Path.home() / ".steam/root",
    ]
    result = []
    seen = set()
    for candidate in candidates:
        try:
            resolved = candidate.expanduser().resolve(strict=False)
        except Exception:
            resolved = candidate.expanduser()
        key = str(resolved)
        if key in seen or not candidate.exists():
            continue
        seen.add(key)
        result.append(resolved)
    return result


def _steam_block_close(text, open_index):
    depth = 0
    quoted = False
    escaped = False
    for i in range(open_index, len(text)):
        ch = text[i]
        if quoted:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def _steam_vdf_string(block, key):
    match = re.search(r'"' + re.escape(str(key)) + r'"\s*"([^"]*)"', block, re.IGNORECASE)
    return match.group(1) if match else ""


def _steam_autologin_user(root):
    path = Path(root) / "config/config.vdf"
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""
    return _steam_vdf_string(text, "AutoLoginUser").strip()


def _steam_login_user_configs(root):
    root = Path(root)
    login_path = root / "config/loginusers.vdf"
    try:
        text = login_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []

    autologin = _steam_autologin_user(root).casefold()
    found = []
    for match in re.finditer(r'"(\d{10,20})"\s*\{', text):
        steamid64 = match.group(1)
        open_index = text.find("{", match.end() - 1)
        close_index = _steam_block_close(text, open_index)
        if close_index < 0:
            continue
        block = text[open_index + 1:close_index]
        account_name = _steam_vdf_string(block, "AccountName").strip()
        most_recent = _steam_vdf_string(block, "MostRecent").strip() == "1"
        allow_auto = _steam_vdf_string(block, "AllowAutoLogin").strip() == "1"
        try:
            timestamp = int(_steam_vdf_string(block, "Timestamp") or 0)
        except Exception:
            timestamp = 0
        try:
            account_id = int(steamid64) & 0xffffffff
        except Exception:
            continue
        user_root = root / "userdata" / str(account_id)
        config = user_root / "config"
        if not user_root.is_dir():
            continue
        score = 0
        if autologin and account_name.casefold() == autologin:
            score += 1_000_000_000_000
        if most_recent:
            score += 500_000_000_000
        if allow_auto:
            score += 50_000_000_000
        score += max(0, timestamp)
        found.append((score, config, account_name, steamid64))
    found.sort(key=lambda x: x[0], reverse=True)
    return found


def steam_user_config_path():
    # Find the host Steam account that Steam itself considers current.
    roots = _steam_root_candidates()
    ranked = []
    for root in roots:
        for score, config, account_name, steamid64 in _steam_login_user_configs(root):
            ranked.append((score, config, account_name, steamid64, root))
    if ranked:
        ranked.sort(key=lambda x: x[0], reverse=True)
        _score, config, account_name, steamid64, root = ranked[0]
        _steam_log_shortcut(
            f"active Steam user: account={account_name or '?'} steamid64={steamid64} root={root} config={config}"
        )
        return config

    fallbacks = []
    for root in roots:
        userdata = root / "userdata"
        if not userdata.is_dir():
            continue
        try:
            children = list(userdata.iterdir())
        except Exception:
            continue
        for child in children:
            if not child.is_dir() or not child.name.isdigit() or child.name == "0":
                continue
            config = child / "config"
            if not config.is_dir():
                continue
            newest = 0.0
            for probe in (config / "localconfig.vdf", config / "shortcuts.vdf", config):
                try:
                    newest = max(newest, probe.stat().st_mtime)
                except Exception:
                    pass
            fallbacks.append((newest, config, root))
    if fallbacks:
        fallbacks.sort(key=lambda x: x[0], reverse=True)
        _mtime, config, root = fallbacks[0]
        _steam_log_shortcut(f"active Steam user fallback: root={root} config={config}")
        return config

    _steam_log_shortcut("active Steam user could not be located")
    return None


def _steam_shortcuts_vdf_path():
    config = steam_user_config_path()
    return (Path(config) / "shortcuts.vdf") if config else None


def steam_root_path():
    config = steam_user_config_path()
    if config:
        try:
            return Path(config).parents[2]
        except Exception:
            pass
    roots = _steam_root_candidates()
    return roots[0] if roots else None


def _steam_native_appid(game_name):
    # Stable across installer filenames and final EXE retargeting.
    unique = '\"OneClickSteamNative\"' + game_name.strip().casefold()
    return binascii.crc32(unique.encode("utf-8")) | 0x80000000


def _big_picture_id(appid):
    return ((int(appid) & 0xFFFFFFFF) << 32) | 0x02000000


def _steam_native_upsert_shortcut(appid, game_name, exe_path, start_dir, icon_path="", launch_options=""):
    path = _steam_shortcuts_vdf_path()
    if not path:
        raise RuntimeError("Steam active-user shortcuts.vdf could not be located")
    path.parent.mkdir(parents=True, exist_ok=True)
    code = r'''
import os, sys, shutil
from lutris.util.steam import vdf
path = sys.argv[1]
appid_u = int(sys.argv[2]) & 0xffffffff
appid_s = appid_u if appid_u < 0x80000000 else appid_u - 0x100000000
name, exe, startdir, icon, launch_options = sys.argv[3:8]
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path):
    with open(path, "rb") as f:
        root = vdf.binary_loads(f.read())
    current = list((root.get("shortcuts") or {}).values())
    backup = path + ".oneclick.bak"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
else:
    current = []
kept = []
for shortcut in current:
    try:
        sid = int(shortcut.get("appid", 0)) & 0xffffffff
    except Exception:
        sid = 0
    if sid != appid_u:
        kept.append(shortcut)
kept.append({
    "appid": appid_s,
    "AppName": name,
    "Exe": '"' + exe + '"',
    "StartDir": '"' + startdir + '"',
    "icon": icon,
    "ShortcutPath": "",
    "LaunchOptions": launch_options,
    "IsHidden": 0,
    "AllowDesktopConfig": 1,
    "AllowOverlay": 1,
    "OpenVR": 0,
    "Devkit": 0,
    "DevkitGameID": "",
    "DevkitOverrideAppID": 0,
    "LastPlayTime": 0,
    "FlatpakAppID": "",
    "tags": {},
})
updated = {"shortcuts": {str(i): item for i, item in enumerate(kept)}}
payload = vdf.binary_dumps(updated)
temp_path = path + ".oneclick.tmp"
with open(temp_path, "wb") as f:
    f.write(payload)
    f.flush()
    os.fsync(f.fileno())
os.replace(temp_path, path)
try:
    dfd = os.open(os.path.dirname(path), os.O_DIRECTORY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)
except Exception:
    pass
print(path)
'''
    _steam_log_shortcut(
        f"write begin AppID={int(appid) & 0xffffffff} name={game_name!r} path={path} exe={exe_path}"
    )
    flatpak_tail = ["-c", code, str(path), str(int(appid)), str(game_name), str(exe_path),
                    str(start_dir), str(icon_path or ""), str(launch_options or "")]
    result = subprocess.run(
        ["flatpak", "run", f"--filesystem={path.parent}:rw", "--command=python3", APP_ID, *flatpak_tail],
        text=True, capture_output=True, timeout=30,
    )
    if result.returncode != 0:
        result = subprocess.run(
            ["flatpak", "run", "--command=python3", APP_ID, *flatpak_tail],
            text=True, capture_output=True, timeout=30,
        )
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "Could not update Steam shortcut").strip()
        _steam_log_shortcut(f"write failed AppID={int(appid) & 0xffffffff} path={path}: {message}")
        raise RuntimeError(message)
    _steam_log_shortcut(f"write complete AppID={int(appid) & 0xffffffff} path={path}")
    return True


def _matching_brace_host(text, open_index):
    depth = 0
    quoted = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def _find_named_vdf_block_host(text, name, start=0, end=None):
    limit = len(text) if end is None else min(len(text), end)
    match = re.search(r'"' + re.escape(str(name)) + r'"', text[start:limit], re.IGNORECASE)
    if not match:
        return None
    key_start = start + match.start()
    key_end = start + match.end()
    open_index = text.find("{", key_end, limit)
    if open_index < 0:
        return None
    close_index = _matching_brace_host(text, open_index)
    if close_index < 0 or close_index >= limit:
        return None
    return key_start, open_index, close_index


def _set_steam_compat_mapping(appid, tool=DEFAULT_STEAM_COMPAT_TOOL, only_if_missing=False):
    root = steam_root_path()
    if not root:
        raise RuntimeError("Steam installation folder could not be found")
    path = root / "config/config.vdf"
    if not path.is_file():
        raise RuntimeError(f"Steam config.vdf was not found: {path}")
    text = path.read_text(encoding="utf-8", errors="replace")
    outer = _find_named_vdf_block_host(text, "CompatToolMapping")
    if not outer:
        raise RuntimeError("Steam CompatToolMapping section was not found")
    _, outer_open, outer_close = outer
    entry = _find_named_vdf_block_host(text, str(int(appid)), outer_open + 1, outer_close)
    if entry and only_if_missing:
        return False
    if entry:
        key_start, _, entry_close = entry
        line_start = text.rfind("\n", 0, key_start) + 1
        remove_end = entry_close + 1
        while remove_end < len(text) and text[remove_end] in " \t":
            remove_end += 1
        if remove_end < len(text) and text[remove_end] == "\r":
            remove_end += 1
        if remove_end < len(text) and text[remove_end] == "\n":
            remove_end += 1
        text = text[:line_start] + text[remove_end:]
        outer = _find_named_vdf_block_host(text, "CompatToolMapping")
        _, outer_open, outer_close = outer
    snippet = (
        f'\n\t\t\t\t\t\t"{int(appid)}"\n'
        '\t\t\t\t\t\t{\n'
        f'\t\t\t\t\t\t\t"name"\t\t"{tool}"\n'
        '\t\t\t\t\t\t\t"config"\t\t""\n'
        '\t\t\t\t\t\t\t"Priority"\t\t"250"\n'
        '\t\t\t\t\t\t}\n'
    )
    text = text[:outer_close] + snippet + text[outer_close:]
    backup = path.with_name("config.vdf.oneclick.bak")
    if not backup.exists():
        shutil.copy2(path, backup)
    temp = path.with_suffix(".vdf.tmp")
    temp.write_text(text, encoding="utf-8")
    temp.replace(path)
    return True



def _steam_library_roots():
    root = steam_root_path()
    roots = []
    if root:
        roots.append(root)
        lf = root / "steamapps/libraryfolders.vdf"
        if lf.is_file():
            try:
                text = lf.read_text(encoding="utf-8", errors="replace")
                for raw in re.findall(r'"path"\s*"([^"]+)"', text, re.IGNORECASE):
                    path = Path(raw.replace("\\\\", "\\")).expanduser()
                    if path.exists() and path not in roots:
                        roots.append(path)
            except Exception:
                pass
    return roots


def _find_proton_experimental():
    for library in _steam_library_roots():
        candidate = library / "steamapps/common/Proton - Experimental/proton"
        if candidate.is_file():
            return candidate
    for candidate in (
        Path.home() / ".local/share/Steam/steamapps/common/Proton - Experimental/proton",
        Path.home() / ".steam/root/steamapps/common/Proton - Experimental/proton",
    ):
        if candidate.is_file():
            return candidate.resolve()
    return None


def _current_steam_compat_tool(appid):
    """Read the compatibility tool Steam currently assigned to this shortcut."""
    root = steam_root_path()
    if not root:
        return ""
    path = root / "config/config.vdf"
    if not path.is_file():
        return ""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        outer = _find_named_vdf_block_host(text, "CompatToolMapping")
        if not outer:
            return ""
        _, outer_open, outer_close = outer
        entry = _find_named_vdf_block_host(text, str(int(appid)), outer_open + 1, outer_close)
        if not entry:
            return ""
        _, entry_open, entry_close = entry
        body = text[entry_open + 1:entry_close]
        match = re.search(r'"name"\s*"([^"]*)"', body, re.IGNORECASE)
        return match.group(1).strip() if match else ""
    except Exception:
        return ""


def _find_proton_for_tool(tool_name):
    """Best-effort resolver for Steam's selected official/custom Proton tool."""
    tool = str(tool_name or "").strip()
    if not tool or tool == "proton_experimental":
        return _find_proton_experimental(), "Proton Experimental"

    # Custom compatibility tools (GE-Proton etc.) advertise the exact tool
    # name in compatibilitytool.vdf. Check the normal SteamOS locations.
    roots = []
    steam_root = steam_root_path()
    if steam_root:
        roots.append(steam_root / "compatibilitytools.d")
    roots.extend([
        Path.home() / ".local/share/Steam/compatibilitytools.d",
        Path.home() / ".steam/root/compatibilitytools.d",
    ])
    seen = set()
    for root in roots:
        try:
            root = root.resolve()
        except Exception:
            pass
        if str(root) in seen or not root.is_dir():
            continue
        seen.add(str(root))
        direct = root / tool / "proton"
        if direct.is_file():
            return direct, tool
        try:
            for manifest in root.glob("*/compatibilitytool.vdf"):
                try:
                    data = manifest.read_text(encoding="utf-8", errors="ignore")
                except Exception:
                    continue
                if re.search(r'"' + re.escape(tool) + r'"\s*\{', data, re.IGNORECASE):
                    candidate = manifest.parent / "proton"
                    if candidate.is_file():
                        return candidate, tool
        except Exception:
            pass

    # For official non-Experimental tools the internal config name and folder
    # name are not always identical. Prefer safety over guessing: use current
    # Experimental in the *same prefix* if we cannot resolve the selected tool.
    return _find_proton_experimental(), "Proton Experimental (fallback)"


def _external_steam_launch_options(appid, entry=None):
    """Wrap Steam's normal %command% only for OneClick external Steam games.

    The wrapper resolves/mounts the physical volume by UUID at EVERY launch and
    exports the pressure-vessel/Proton paths before Steam's Proton command runs.
    This removes the dependency on whatever temporary /run/media/deck/<label>N
    path SteamOS happened to assign after a USB reconnect.
    """
    entry = dict(entry or (load_steam_registry().get(str(int(appid))) or {}))
    if str(entry.get("storage_mode") or "").lower() != "external":
        return ""
    helper = str(Path(__file__).resolve())
    return f'"{helper}" external-steam-launch {int(appid)} %command%'


def _append_colon_env(env, key, values):
    current = str(env.get(key) or "").strip()
    parts = [x for x in current.split(":") if x] if current else []
    for value in values:
        value = str(value or "").strip()
        if value and value not in parts:
            parts.append(value)
    if parts:
        env[key] = ":".join(parts)


def _external_steam_launch(appid, command):
    """Resolve an external Steam game immediately before Proton starts.

    Steam's Storage page can keep a stale /run/media path after a removable
    drive is unplugged/replugged.  A user manually removing/re-adding the Steam
    library fixes that because Steam then rebuilds its compatibility mount list.
    OneClick does the equivalent per-launch without requiring the drive to be a
    permanent Steam Library: resolve UUID, mount if needed, refresh OneClick's
    stable links, and explicitly share the live mount with pressure-vessel.
    """
    appid = int(appid)
    if not command:
        raise RuntimeError("Steam did not provide a command to launch.")
    entry = dict(load_steam_registry().get(str(appid)) or {})
    if str(entry.get("storage_mode") or "").lower() != "external":
        os.execvpe(command[0], command, os.environ.copy())

    uuid_text = str(entry.get("storage_uuid") or "").strip()
    storage_root = str(entry.get("storage_root") or "").strip()
    if not uuid_text and storage_root and Path(storage_root).exists():
        uuid_text = _filesystem_uuid_for_path(storage_root)
    if not uuid_text:
        raise RuntimeError("This external game has no saved drive UUID. Repair or reinstall the shortcut once with the drive connected.")

    alias = _refresh_external_drive_alias(uuid_text, try_mount=True)
    node = _block_record_for_uuid(uuid_text)
    mount = _mounted_path_from_record(node)
    if alias is None or mount is None:
        raise RuntimeError("The external game drive is not connected or could not be mounted.")

    # Re-run the migration after the device is live. This also upgrades older
    # 'Game [AppID]' external folders to the readable V7.2.5 naming scheme.
    try:
        migrate_external_steam_paths()
    except Exception:
        pass
    entry = dict(load_steam_registry().get(str(appid)) or entry)

    steam_root = steam_root_path()
    if steam_root:
        numeric = steam_root / "steamapps" / "compatdata" / str(appid)
        target_text = str(entry.get("compatdata") or "").strip()
        if target_text:
            target = Path(target_text)
            try:
                if numeric.is_symlink():
                    literal = os.readlink(numeric)
                    if os.path.normpath(literal) != os.path.normpath(str(target)):
                        numeric.unlink(missing_ok=True)
                        numeric.symlink_to(target, target_is_directory=True)
                elif not numeric.exists():
                    numeric.symlink_to(target, target_is_directory=True)
            except Exception:
                pass

    # Keep a conventional SteamLibrary skeleton on the device. It is harmless
    # for non-Steam games, makes the volume immediately addable in Steam's
    # Storage UI, and supplies a normal library path for Proton's container.
    steam_library = mount / "SteamLibrary"
    steamapps = steam_library / "steamapps"
    try:
        steamapps.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

    env = os.environ.copy()
    # Current steam-runtime documentation defines STEAM_COMPAT_MOUNTS as extra
    # read/write directories exposed to pressure-vessel. The library paths list
    # complements it for Proton/Steam compatibility-tool discovery.
    _append_colon_env(env, "STEAM_COMPAT_MOUNTS", [mount, mount / "OneClick Games"])
    _append_colon_env(env, "PRESSURE_VESSEL_FILESYSTEMS_RW", [mount])
    _append_colon_env(env, "STEAM_COMPAT_LIBRARY_PATHS", [steamapps, mount / "OneClick Games" / "Steam-Proton"])

    try:
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.ctime()}: external launch AppID {appid} UUID={uuid_text} mount={mount} command={command[0]}\\n")
    except Exception:
        pass
    os.execvpe(command[0], command, env)


def _finalize_steam_shortcut_now(appid, game_name, final_exe, icon_path=""):
    """Write and verify a completed non-Steam shortcut.

    Only Steam's *main client* is allowed to block the write. V7.4.18 used
    ``steam_is_running()``, which also counted lingering ``steamwebhelper``
    processes. On SteamOS those helpers can remain alive after the visible
    Steam client has closed, so the deferred writer could wait through every
    restart forever even though shortcuts.vdf was already safe to edit.

    External games may legitimately be disconnected while the shortcut is being
    repaired. Their UUID-stable alias is still safe to store in shortcuts.vdf.
    """
    if _steam_main_process_running():
        return False
    final_exe = Path(final_exe)
    entry = load_steam_registry().get(str(int(appid))) or {}
    if not final_exe.is_file() and str(entry.get("storage_mode") or "").lower() != "external":
        return False
    tool = _current_steam_compat_tool(appid) or str(entry.get("compat_tool") or DEFAULT_STEAM_COMPAT_TOOL)
    launch_options = _external_steam_launch_options(appid, entry)
    _steam_native_upsert_shortcut(
        appid, game_name, final_exe, final_exe.parent,
        icon_path or entry.get("icon", ""), launch_options
    )
    _set_steam_compat_mapping(appid, tool or DEFAULT_STEAM_COMPAT_TOOL, only_if_missing=True)

    # Do not claim success until the exact AppID can be read back from the
    # active user's shortcuts.vdf.
    if not _verify_steam_native_shortcut(appid):
        raise RuntimeError(
            "The shortcut writer finished, but the exact AppID could not be verified "
            "in Steam's active shortcuts.vdf."
        )

    update_steam_registry_entry(
        appid,
        name=game_name,
        final_exe=str(final_exe),
        start_dir=str(final_exe.parent),
        status="installed",
        backend="steam",
        compat_tool=tool or DEFAULT_STEAM_COMPAT_TOOL,
        exe_reselect_pending=False,
        shortcut_verified_at=int(time.time()),
        shortcut_vdf=str(_steam_shortcuts_vdf_path() or ""),
        updated_at=int(time.time()),
    )
    return True


def _deferred_steam_finalize(appid, max_wait=7 * 24 * 60 * 60):
    """Wait for the user to close Steam naturally, then finalize once.

    V7.4.20 deliberately does *not* wait for artwork. The shortcut itself is
    more important than its optional icon, and waiting for the artwork worker
    could make us miss the short window between Steam closing and reopening.
    Artwork can refresh the icon in a later pass after the shortcut already
    exists.

    Only the main Steam process blocks the write. Lingering steamwebhelper
    processes are ignored because they do not own the shortcut database.
    """
    appid = int(appid)
    deadline = time.time() + max_wait
    while time.time() < deadline:
        entry = load_steam_registry().get(str(appid)) or {}
        if entry.get("status") != "pending_steam":
            return
        final_text = str(entry.get("final_exe") or "")
        if not final_text:
            return

        if not _steam_main_process_running():
            # Let Steam finish its last shutdown writes, but keep this pause
            # short enough to catch an ordinary manual restart.
            time.sleep(0.35)
            if _steam_main_process_running():
                time.sleep(0.15)
                continue
            try:
                if _finalize_steam_shortcut_now(
                    appid,
                    entry.get("name") or str(appid),
                    Path(final_text),
                    entry.get("icon", ""),
                ):
                    return
            except Exception as exc:
                # Keep it pending so this worker can retry on the next safe
                # window instead of falsely marking the shortcut installed.
                update_steam_registry_entry(appid, status="pending_steam", updated_at=int(time.time()))
                with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
                    log.write(f"{time.ctime()}: deferred finalize AppID {appid} failed: {exc}\n")
                time.sleep(1.5)
        time.sleep(0.20)


def launch_deferred_steam_finalizer(appid):
    helper = str(Path(__file__).resolve())
    args = [sys.executable, helper, "finalize-pending-steam", str(int(appid))]
    # A transient user service survives closing One-Click/Dolphin and normally
    # survives the Desktop -> Gaming Mode transition. Fall back to a detached
    # process when systemd-run is unavailable.
    systemd_run = shutil.which("systemd-run")
    if systemd_run:
        unit = f"oneclick-steam-finalize-{int(appid)}-{int(time.time())}"
        result = subprocess.run(
            [systemd_run, "--user", "--quiet", "--collect", f"--unit={unit}", *args],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return True
    log = open(STEAM_NATIVE_LOG, "a", encoding="utf-8")
    subprocess.Popen(args, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    log.close()
    return True


def recover_pending_steam_shortcuts():
    """Resume shortcut writes left pending by an older OneClick build."""
    recovered = 0
    queued = 0
    for key, entry in list(load_steam_registry().items()):
        if str(entry.get("status") or "") != "pending_steam":
            continue
        final_text = str(entry.get("final_exe") or "").strip()
        if not final_text:
            continue
        try:
            appid = int(key)
        except Exception:
            continue

        if _steam_main_process_running():
            try:
                launch_deferred_steam_finalizer(appid)
                queued += 1
            except Exception:
                pass
            continue

        try:
            if _finalize_steam_shortcut_now(
                appid,
                entry.get("name") or str(appid),
                Path(final_text),
                entry.get("icon", ""),
            ):
                recovered += 1
        except Exception as exc:
            update_steam_registry_entry(appid, status="pending_steam", updated_at=int(time.time()))
            try:
                launch_deferred_steam_finalizer(appid)
                queued += 1
            except Exception:
                pass
            with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
                log.write(f"{time.ctime()}: pending shortcut recovery AppID {appid} failed: {exc}\n")
    return {"recovered": recovered, "queued": queued}


def _direct_update_watch(appid, game_name, proton_pid, proton_path, log_dir, update_exe="", retry_count=0):
    entry = load_steam_registry().get(str(int(appid))) or {}
    compat_text = str(entry.get("compatdata") or "")
    compatdata = Path(compat_text) if compat_text else (steam_root_path() / "steamapps/compatdata" / str(int(appid)))
    _wait_pid(int(proton_pid))
    _wait_wineserver_for_prefix(proton_path, compatdata)

    # Retry an updater only when its Proton log contains a clear crash marker.
    # We intentionally do not retry a normal/clean exit because many patchers
    # are not idempotent and running a successful patch twice would be unsafe.
    update_path = Path(update_exe) if update_exe else None
    if int(retry_count) < 1 and update_path and update_path.is_file() and _retryable_proton_failure(log_dir):
        try:
            retry_started = int(time.time())
            retry_log_dir = _new_proton_log_dir(f"{game_name}-update-retry", appid, retry_started)
            env, _ = _direct_proton_env(appid, retry_log_dir)
            launcher_log = open(retry_log_dir / "launcher.log", "a", encoding="utf-8")
            try:
                proc = subprocess.Popen(
                    [str(proton_path), "run", str(update_path)], cwd=str(update_path.parent), env=env,
                    stdout=launcher_log, stderr=launcher_log, start_new_session=True, close_fds=True,
                )
            finally:
                launcher_log.close()
            subprocess.run(
                ["kdialog", "--passivepopup", f"{game_name} update exited unexpectedly. Retrying once automatically…", "5"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            launch_direct_update_watcher(appid, game_name, proc.pid, proton_path, retry_log_dir, update_path, 1)
            return
        except Exception as exc:
            with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
                log.write(f"{time.ctime()}: update auto-retry AppID {appid} failed to launch: {exc}\n")

    subprocess.run(
        ["kdialog", "--passivepopup", f"{game_name} update/patch finished. Steam was not restarted.", "5"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def launch_direct_update_watcher(appid, game_name, proton_pid, proton_path, log_dir, update_exe="", retry_count=0):
    log = open(STEAM_NATIVE_LOG, "a", encoding="utf-8")
    args = [sys.executable, str(Path(__file__).resolve()), "protonwatch-update",
            str(int(appid)), str(game_name), str(int(proton_pid)), str(proton_path), str(log_dir),
            str(update_exe or ""), str(int(retry_count))]
    subprocess.Popen(args, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    log.close()


def _direct_proton_env(appid, proton_log_dir=None, storage_root="", game_name=""):
    root = steam_root_path()
    if not root:
        raise RuntimeError("Steam installation folder could not be found")
    if str(storage_root or "").strip():
        compatdata = _prepare_external_steam_compatdata(
            appid, game_name or f"OneClick-{int(appid)}", storage_root
        )
    else:
        compatdata = _prepare_internal_named_steam_compatdata(
            appid, game_name or f"OneClick-{int(appid)}"
        )
    env = os.environ.copy()
    env["STEAM_COMPAT_DATA_PATH"] = str(compatdata)
    env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = str(root)
    # Keep installer launches neutral, like the known-good V6.7.5 path.
    # Do NOT make the installer impersonate the final Steam shortcut: some
    # installers behave differently when SteamAppId/STEAM_COMPAT_APP_ID are
    # populated. Proton only needs SteamGameId for the PROTON_LOG filename,
    # so give logging its own harmless identity while keeping SteamAppId 0.
    env["STEAM_COMPAT_APP_ID"] = "0"
    env["SteamAppId"] = "0"
    env["SteamGameId"] = f"oneclick-{int(appid)}"
    # Installers and patchers do not need Proton's controller-friendly Xalia
    # helper. On SteamOS it can intermittently attach before an installer
    # window is ready and abort the setup with invalid-window-handle errors.
    # This environment is used only for One-Click's direct installer/update
    # runs; the installed game later uses Steam's normal Proton defaults.
    env["PROTON_USE_XALIA"] = "0"
    # Some heavily-compressed 32-bit installers (ISDone/unarc/cls-lolz style)
    # can exhaust or fragment their Win32 virtual address space when Proton's
    # Large Address Aware forcing is enabled. This is an installer-only
    # compatibility setting; the installed game later launches through Steam
    # with its normal Proton defaults.
    env["PROTON_FORCE_LARGE_ADDRESS_AWARE"] = "0"
    env["WINE_LARGE_ADDRESS_AWARE"] = "0"
    # PROTON_LOG=1 enables a very broad Wine trace and can generate hundreds
    # of MB during decompression, materially slowing a setup that is already
    # struggling. Keep normal installs lightweight and capture only Wine error
    # lines in launcher.log. Detailed Proton logging can be re-enabled later
    # for a specific diagnostic build if needed.
    env.pop("PROTON_LOG", None)
    env.pop("PROTON_LOG_DIR", None)
    if proton_log_dir:
        log_path = str(Path(proton_log_dir))
        env["PROTON_CRASH_REPORT_DIR"] = log_path
    env["WINEDEBUG"] = "err+all"
    return env, compatdata


def _wait_pid(pid, timeout=12 * 60 * 60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not _pid_alive(pid):
            return True
        time.sleep(0.5)
    return not _pid_alive(pid)


def _wait_wineserver_for_prefix(proton_path, compatdata, timeout=12 * 60 * 60):
    wineserver = Path(proton_path).parent / "files/bin/wineserver"
    if not wineserver.is_file():
        deadline = time.time() + timeout
        quiet_since = None
        pfx = str((Path(compatdata) / "pfx").resolve())
        compat_real = str(Path(compatdata).resolve())
        while time.time() < deadline:
            active = False
            try:
                for item in Path("/proc").iterdir():
                    if not item.name.isdigit():
                        continue
                    try:
                        data = (item / "environ").read_bytes()
                        if (f"WINEPREFIX={pfx}".encode() in data or
                                f"STEAM_COMPAT_DATA_PATH={compat_real}".encode() in data):
                            active = True
                            break
                    except Exception:
                        continue
            except Exception:
                pass
            if active:
                quiet_since = None
            elif quiet_since is None:
                quiet_since = time.time()
            elif time.time() - quiet_since >= 8:
                return True
            time.sleep(1.0)
        return False

    env = os.environ.copy()
    env["WINEPREFIX"] = str((Path(compatdata) / "pfx").resolve())
    try:
        subprocess.run([str(wineserver), "-w"], env=env, timeout=timeout,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False


def _retryable_proton_failure(log_dir):
    """Return True for transient Proton/installer failures worth one retry.

    Keep this conservative: the main known case is Xalia/window bootstrap
    failure. We also allow a very short failed first launch, which commonly
    indicates a bootstrap race rather than a completed/cancelled install.
    """
    markers = (
        "xalia.exe",
        "invalid window handle",
        "invalidcastexception",
        "exception handling",
        "unhandled exception",
        "segmentation fault",
    )
    try:
        root = Path(log_dir)
        for path in root.glob("*.log"):
            try:
                text = path.read_text(encoding="utf-8", errors="ignore").casefold()
            except Exception:
                continue
            if any(item in text for item in markers):
                return True
    except Exception:
        pass
    return False


def _launch_direct_proton_retry(appid, game_name, installer, proton_path, original_started_at):
    retry_started = int(time.time())
    retry_log_dir = _new_proton_log_dir(f"{game_name}-retry", appid, retry_started)
    env, _compatdata = _direct_proton_env(appid, retry_log_dir)
    launcher_log = open(retry_log_dir / "launcher.log", "a", encoding="utf-8")
    try:
        proc = subprocess.Popen(
            [str(proton_path), "run", str(installer)],
            cwd=str(Path(installer).parent), env=env, stdout=launcher_log, stderr=launcher_log,
            start_new_session=True, close_fds=True,
        )
    finally:
        launcher_log.close()
    update_steam_registry_entry(
        appid, status="installing_retry", retry_count=1,
        proton_log_dir=str(retry_log_dir), updated_at=int(time.time()),
    )
    with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as summary:
        summary.write(
            f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] AUTO-RETRY {game_name} "
            f"AppID={int(appid)} log={retry_log_dir}\n"
        )
    subprocess.run(
        ["kdialog", "--passivepopup",
         f"{game_name} installer exited unexpectedly. Retrying once automatically…", "5"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    _direct_proton_watch(int(appid), game_name, int(original_started_at), proc.pid, str(proton_path))


def _direct_proton_watch(appid, game_name, started_at, proton_pid, proton_path):
    appid = int(appid)
    entry = (load_steam_registry().get(str(appid)) or {})
    compatdata_text = entry.get("compatdata") or ""
    compatdata = Path(compatdata_text) if compatdata_text else None

    _wait_pid(int(proton_pid))
    if compatdata:
        _wait_wineserver_for_prefix(proton_path, compatdata)

    time.sleep(2.0)
    # V7.2.5 generation guard: an installer watcher from an older installation
    # must never resurrect a game after Complete Removal or overwrite a newer
    # reinstall of the same title/AppID.
    current = (load_steam_registry().get(str(appid)) or {})
    try:
        same_generation = int(current.get("created_at") or 0) == int(started_at)
    except Exception:
        same_generation = False
    if not current or current.get("status") == "removed" or not same_generation:
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.ctime()}: ignored stale installer watcher for AppID {appid} generation {started_at}\n")
        return
    entry = current
    final_exe = _find_game_exe(appid, game_name, started_at)
    if not final_exe:
        entry = (load_steam_registry().get(str(appid)) or entry or {})
        log_dir = str(entry.get("proton_log_dir") or PROTON_LOG_ROOT)
        installer_text = str(entry.get("installer") or "").strip()
        retry_count = int(entry.get("retry_count") or 0)
        elapsed = max(0, int(time.time()) - int(started_at))
        # One transparent retry covers the intermittent first-launch failure
        # seen with fresh Proton prefixes. Never clean the prefix between the
        # two attempts; the second attempt deliberately reuses it.
        if (retry_count < 1 and installer_text and Path(installer_text).is_file() and
                (_retryable_proton_failure(log_dir) or elapsed <= 60)):
            try:
                _launch_direct_proton_retry(appid, game_name, Path(installer_text), proton_path, started_at)
                return
            except Exception as retry_exc:
                with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as retry_log:
                    retry_log.write(f"{time.ctime()}: automatic retry for AppID {appid} failed to launch: {retry_exc}\n")

        cleanup_size = 0
        cleanup_done = False
        try:
            cleanup_size, cleanup_done = _safe_remove_failed_compatdata(appid, entry)
        except Exception:
            cleanup_done = False
        update_steam_registry_entry(
            appid,
            status="install_failed_cleaned" if cleanup_done else "install_failed",
            compatdata="" if cleanup_done else str(entry.get("compatdata") or ""),
            updated_at=int(time.time()),
        )

        cleanup_text = (
            f"\n\nThe incomplete Steam prefix was removed ({_human_size(cleanup_size)}) so failed installs do not build up."
            if cleanup_done and cleanup_size
            else ("\n\nThe incomplete Steam prefix was removed so failed installs do not build up." if cleanup_done else "")
        )
        retry = False
        if installer_text and Path(installer_text).is_file():
            retry = subprocess.run(
                [
                    "kdialog", "--warningyesno",
                    f"{game_name} did not complete with Proton Experimental.\n\n"
                    "Steam was NOT stopped and One-Click did not terminate the installer."
                    f"{cleanup_text}\n\n"
                    f"Installer diagnostics were saved in:\n{log_dir}\n\n"
                    "Retry this installer with Lutris / Wine?\n\nOne-Click will use Lutris\' normal Wine configuration (for example your System 11.0 setting).",
                ],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode == 0
        else:
            error(
                f"{game_name} did not complete with Proton Experimental.\n\n"
                f"Installer diagnostics were saved in:\n{log_dir}{cleanup_text}"
            )
            return

        if retry:
            try:
                # Do not reuse/mix the failed Proton prefix. Lutris gets its own
                # separate Wine prefix and we explicitly request System Wine.
                install_new_lutris(
                    Path(installer_text), game_name=game_name,
                    storage_path=str(entry.get("storage_root") or ""),
                )
                remove_steam_registry_entry(appid)
            except Exception as exc:
                error(
                    f"Could not start the Lutris / Wine fallback for {game_name}:\n\n{exc}\n\n"
                    f"The Proton diagnostic logs are still available in:\n{log_dir}"
                )
        return

    # ISO installs normally finalize immediately. Mixed StreamExtract batches
    # can deliberately pause here so optional update/patch EXEs run first; the
    # ISO lifecycle manager performs one final Steam close/write/verify/reopen
    # only after that chain is complete.
    defer_post = bool(entry.get("defer_post_install_finalize"))
    auto_finalize = bool(entry.get("auto_finalize_shortcut") or entry.get("source_iso_install")) and not defer_post
    update_steam_registry_entry(
        appid, name=game_name, final_exe=str(final_exe), start_dir=str(final_exe.parent),
        status="pending_followup" if defer_post else "pending_steam",
        backend="steam", compat_tool=DEFAULT_STEAM_COMPAT_TOOL,
        artwork_pending=True, updated_at=int(time.time()),
    )
    # Discover/cache redistributable installers shipped with the installed game.
    # This is cache-only: no VC++, DirectX, PhysX, etc. is executed automatically.
    launch_dependency_cache_refresh("steam", appid)
    if defer_post:
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.ctime()}: deferred Steam shortcut/artwork for AppID {appid} until StreamExtract follow-up chain completes\n")
        return
    if auto_finalize:
        commit = _commit_steam_shortcut_reliably(appid, game_name, final_exe, entry.get("icon", ""))
        launch_background_steam_artwork(appid, game_name)
        if commit.get("ok"):
            subprocess.run(
                ["kdialog", "--passivepopup",
                 f"{game_name} is installed and its Steam shortcut was created. Artwork is being applied in the background.", "8"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        else:
            update_steam_registry_entry(appid, status="pending_steam", updated_at=int(time.time()))
            launch_deferred_steam_finalizer(appid)
            with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
                log.write(f"{time.ctime()}: ISO auto-finalize AppID {appid} failed: {commit.get('error') or 'unknown error'}\n")
            subprocess.run(
                ["kdialog", "--passivepopup",
                 f"{game_name} installed, but the Steam shortcut is queued for the next clean Steam restart. Artwork is being applied in the background.", "9"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    else:
        launch_background_steam_artwork(appid, game_name)
        if _steam_main_process_running():
            launch_deferred_steam_finalizer(appid)
            subprocess.run(
                ["kdialog", "--passivepopup",
                 f"{game_name} is installed. Steam can stay open. The shortcut will finalize the next time Steam closes/restarts or you return to Gaming Mode.", "8"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        else:
            try:
                _finalize_steam_shortcut_now(appid, game_name, final_exe, entry.get("icon", ""))
            except Exception as exc:
                with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
                    log.write(f"{time.ctime()}: immediate finalize AppID {appid} failed: {exc}\n")


def launch_direct_proton_watcher(appid, game_name, started_at, proton_pid, proton_path):
    log = open(STEAM_NATIVE_LOG, "a", encoding="utf-8")
    args = [sys.executable, str(Path(__file__).resolve()), "protonwatch-native",
            str(int(appid)), game_name, str(int(started_at)), str(int(proton_pid)), str(proton_path)]
    subprocess.Popen(args, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    log.close()

def _steam_reaper_running(appid):
    try:
        result = subprocess.run(
            ["pgrep", "-af", f"SteamLaunch AppId={int(appid)}"],
            text=True,
            capture_output=True,
        )
        return result.returncode == 0 and bool(result.stdout.strip())
    except Exception:
        return False


def _wait_for_steam_ready(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if steam_is_running():
            time.sleep(2.0)
            return True
        time.sleep(0.5)
    return False


def _launch_steam_shortcut(appid):
    steam = shutil.which("steam")
    if not steam:
        raise RuntimeError("Steam executable was not found")
    bpid = _big_picture_id(appid)
    subprocess.Popen(
        [steam, f"steam://rungameid/{bpid}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return bpid


def _candidate_score(path, game_name, started_at=0):
    lower = str(path).lower().replace("\\", "/")
    stem = path.stem.lower()
    tokens = [x for x in re.findall(r"[a-z0-9]+", game_name.lower()) if len(x) > 1]
    score = 0

    # Never offer executables that merely belong to the fresh Proton/Wine
    # prefix. V6.0 could show steam.exe / iexplore.exe / wordpad.exe when a
    # bootstrap installer exited early; those are not game candidates.
    blocked_parts = (
        "/windows/", "/system32/", "/syswow64/", "/winsxs/",
        "/users/steamuser/appdata/", "/programdata/",
        "/program files (x86)/steam/", "/program files/steam/",
        "/internet explorer/", "/windows nt/", "/windows media player/",
        "/common files/", "/microsoft/edge/",
    )
    if any(x in lower for x in blocked_parts):
        return -10000

    system_stems = {
        "steam", "iexplore", "wordpad", "wmplayer", "explorer", "services",
        "rundll32", "regedit", "control", "hh", "wineboot", "winedevice",
        "plugplay", "rpcss", "svchost", "start",
    }
    if stem in system_stems:
        return -10000

    bad_names = (
        "unins", "uninstall", "setup", "installer", "installshield", "vc_redist", "vcredist",
        "dxsetup", "directx", "unitycrashhandler", "crashpad", "crashreport", "reporter",
        "dotnet", "redistributable", "prereq", "supporttool", "helper", "repair"
    )
    if any(x in stem for x in bad_names):
        score -= 180
    if any(x in lower for x in ("/redist/", "/_redist/", "/redists/", "/support/", "/prereq/")):
        score -= 120

    if "/gog games/" in lower:
        score += 120
    if "/program files" in lower:
        score += 25

    norm_stem = re.sub(r"[^a-z0-9]+", "", stem)
    norm_name = re.sub(r"[^a-z0-9]+", "", game_name.lower())
    if norm_name and norm_name in norm_stem:
        score += 120
    elif norm_stem and norm_stem in norm_name and len(norm_stem) >= 5:
        score += 80
    for token in tokens:
        if token in stem:
            score += 20
        if token in path.parent.name.lower():
            score += 10

    try:
        stat = path.stat()
        size = stat.st_size
        # Prefer files touched by this installation, but don't require the
        # timestamp because some installers preserve original file mtimes.
        if started_at and stat.st_mtime >= started_at - 10:
            score += 12
    except OSError:
        size = 0

    if size >= 20 * 1024 * 1024:
        score += 30
    elif size >= 5 * 1024 * 1024:
        score += 22
    elif size >= 1 * 1024 * 1024:
        score += 10
    elif size < 100 * 1024:
        score -= 30
    if "launcher" in stem:
        score += 3
    return score


def _prefix_runtime_processes(appid):
    """Return PIDs still running inside this Steam Proton prefix.

    GOG/InstallShield/Inno installers often launch a child process and let the
    original bootstrap EXE exit. Steam's reaper can therefore disappear while
    the real installer is still open. V6.0 treated that as completion and then
    shut Steam down, which killed the installer. Checking /proc environments
    keeps the watcher attached to the actual Proton prefix instead.
    """
    root = steam_root_path()
    if not root:
        return []
    compat = str((root / "steamapps" / "compatdata" / str(int(appid))).resolve())
    pfx = str((Path(compat) / "pfx").resolve())
    needles = (
        f"STEAM_COMPAT_DATA_PATH={compat}".encode(),
        f"WINEPREFIX={pfx}".encode(),
        f"STEAM_COMPAT_APP_ID={int(appid)}".encode(),
    )
    found = []
    proc = Path("/proc")
    try:
        entries = list(proc.iterdir())
    except Exception:
        return found
    own = os.getpid()
    for item in entries:
        if not item.name.isdigit():
            continue
        pid = int(item.name)
        if pid == own:
            continue
        try:
            data = (item / "environ").read_bytes()
            if any(n in data for n in needles):
                cmd = (item / "cmdline").read_bytes().replace(b"\\0", b" ").decode("utf-8", "ignore")
                found.append((pid, cmd))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return found


def _wait_for_steam_native_session(appid, initial_timeout=180, quiet_seconds=8, max_runtime=12 * 60 * 60):
    """Wait until the Steam/Proton installer is *actually* finished."""
    first_deadline = time.time() + initial_timeout
    seen = False
    while time.time() < first_deadline:
        if _steam_reaper_running(appid) or _prefix_runtime_processes(appid):
            seen = True
            break
        time.sleep(0.5)
    if not seen:
        return False

    deadline = time.time() + max_runtime
    quiet_since = None
    while time.time() < deadline:
        active = _steam_reaper_running(appid) or bool(_prefix_runtime_processes(appid))
        if active:
            quiet_since = None
        else:
            if quiet_since is None:
                quiet_since = time.time()
            elif time.time() - quiet_since >= quiet_seconds:
                return True
        time.sleep(1.0)
    return False


def _find_game_exe(appid, game_name, started_at=0):
    root = steam_root_path()
    if not root:
        return None
    drive_c = root / "steamapps" / "compatdata" / str(int(appid)) / "pfx" / "drive_c"
    if not drive_c.is_dir():
        return None
    candidates = []
    try:
        for path in drive_c.rglob("*.exe"):
            if path.is_file():
                score = _candidate_score(path, game_name, started_at)
                if score > -500:
                    candidates.append((score, path))
    except Exception:
        pass
    candidates.sort(key=lambda x: (-x[0], len(str(x[1]))))
    if not candidates:
        update_steam_registry_entry(appid, exe_reselect_available=False)
        return None

    best_score, best = candidates[0]
    second_score = candidates[1][0] if len(candidates) > 1 else -9999
    if best_score >= 70 and best_score - second_score >= 10:
        # The user never saw the ambiguity chooser during this installation.
        # Keep the Tools reselect button inactive for exactly this case.
        update_steam_registry_entry(appid, exe_reselect_available=False)
        return best

    # Don't show a chooser full of Proton's stock Windows programs. If nothing
    # looks remotely like the requested game, report a clean detection failure.
    plausible = [(score, path) for score, path in candidates if score >= 18]
    if not plausible:
        update_steam_registry_entry(appid, exe_reselect_available=False)
        return None

    # Persist that this *specific installation* required the main-EXE chooser.
    # OneClick Tools may later reopen the same chooser without forcing a full
    # reinstall. Games that never showed this chooser remain deliberately inert.
    update_steam_registry_entry(
        appid,
        exe_reselect_available=True,
        exe_reselect_root=str(drive_c),
        exe_reselect_shown_at=int(time.time()),
    )

    args = ["--menu", f"Choose the main game EXE for {game_name}:"]
    for _score, path in plausible[:12]:
        try:
            rel = path.relative_to(drive_c)
        except Exception:
            rel = path
        args.extend([str(path), str(rel)])
    choice = dialog(args)
    return Path(choice) if choice else None

def _reselect_drive_c(appid, entry):
    """Resolve the real drive_c for internal, external and migrated prefixes."""
    roots = []
    compat_text = str(entry.get("compatdata") or "").strip()
    if compat_text:
        roots.append(Path(compat_text).expanduser() / "pfx" / "drive_c")
    saved_root = str(entry.get("exe_reselect_root") or "").strip()
    if saved_root:
        roots.append(Path(saved_root).expanduser())
    steam_root = steam_root_path()
    if steam_root:
        roots.append(steam_root / "steamapps" / "compatdata" / str(int(appid)) / "pfx" / "drive_c")

    seen = set()
    for root in roots:
        try:
            key = str(root.resolve(strict=False))
        except Exception:
            key = str(root)
        if key in seen:
            continue
        seen.add(key)
        try:
            if root.is_dir():
                return root.resolve()
        except Exception:
            continue
    return None


def _reselect_exe_candidate_payload(appid):
    """Return chooser data without opening any host-side GUI.

    Moses OneClick Tools runs inside the Lutris Flatpak.  Opening KDialog from
    a detached host helper can silently fail on SteamOS/Wayland even though the
    helper itself starts correctly.  V7.2.5 therefore returns the candidates
    as JSON and lets the already-visible Tools GTK window own the chooser.
    """
    appid = int(appid)
    entry = load_steam_registry().get(str(appid)) or {}
    has_recorded_state = "exe_reselect_available" in entry
    if has_recorded_state and not bool(entry.get("exe_reselect_available")):
        return {"ok": True, "available": False, "reason": "not_eligible", "candidates": []}

    game_name = str(entry.get("name") or f"Steam game {appid}").strip()
    drive_c = _reselect_drive_c(appid, entry)
    if drive_c is None:
        return {
            "ok": False,
            "available": False,
            "error": "The game's Proton prefix is not currently available.",
            "game_name": game_name,
            "candidates": [],
        }

    all_candidates = []
    try:
        for path in drive_c.rglob("*.exe"):
            if path.is_file():
                score = _candidate_score(path, game_name, 0)
                if score > -500:
                    all_candidates.append((score, path.resolve()))
    except Exception:
        pass
    all_candidates.sort(key=lambda x: (-x[0], len(str(x[1]))))

    # Backward-compatible inference for old installs that predate the explicit
    # chooser-history flag. Explicit False from newer installs remains final.
    if not has_recorded_state:
        if not all_candidates:
            update_steam_registry_entry(appid, exe_reselect_available=False)
            return {"ok": True, "available": False, "reason": "no_candidates", "game_name": game_name, "candidates": []}
        best_score = all_candidates[0][0]
        second_score = all_candidates[1][0] if len(all_candidates) > 1 else -9999
        if best_score >= 70 and best_score - second_score >= 10:
            update_steam_registry_entry(appid, exe_reselect_available=False)
            return {"ok": True, "available": False, "reason": "auto_selected", "game_name": game_name, "candidates": []}
        plausible_legacy = [(score, path) for score, path in all_candidates if score >= 18]
        if not plausible_legacy:
            update_steam_registry_entry(appid, exe_reselect_available=False)
            return {"ok": True, "available": False, "reason": "no_candidates", "game_name": game_name, "candidates": []}
        update_steam_registry_entry(
            appid,
            exe_reselect_available=True,
            exe_reselect_root=str(drive_c),
            exe_reselect_inferred_at=int(time.time()),
        )

    candidates = [(score, path) for score, path in all_candidates if score >= 18]
    if not candidates:
        return {"ok": True, "available": False, "reason": "no_candidates", "game_name": game_name, "candidates": []}

    items = []
    for score, path in candidates[:16]:
        try:
            rel = path.relative_to(drive_c)
        except Exception:
            rel = path
        items.append({"path": str(path), "label": str(rel), "score": int(score)})

    current = str(entry.get("final_exe") or "").strip()
    try:
        current = str(Path(current).expanduser().resolve()) if current else ""
    except Exception:
        pass
    return {
        "ok": True,
        "available": True,
        "game_name": game_name,
        "drive_c": str(drive_c),
        "current_exe": current,
        "candidates": items,
    }


def _apply_reselected_steam_main_exe(appid, selected_path, launch_deferred=True):
    appid = int(appid)
    payload = _reselect_exe_candidate_payload(appid)
    if not payload.get("ok"):
        return payload
    if not payload.get("available"):
        return {"ok": False, "error": "No selectable game EXE is available for this installation."}

    try:
        selected = Path(str(selected_path)).expanduser().resolve()
    except Exception:
        return {"ok": False, "error": "The selected EXE path is invalid."}

    allowed = {str(Path(item.get("path") or "").expanduser().resolve()) for item in payload.get("candidates", [])}
    if str(selected) not in allowed or not selected.is_file():
        return {"ok": False, "error": "The selected EXE is no longer available in this game prefix."}

    entry = load_steam_registry().get(str(appid)) or {}
    game_name = str(entry.get("name") or payload.get("game_name") or f"Steam game {appid}").strip()
    drive_c = Path(str(payload.get("drive_c") or selected.parent))
    update_steam_registry_entry(
        appid,
        exe_reselect_available=True,
        exe_reselect_root=str(drive_c),
        final_exe=str(selected),
        start_dir=str(selected.parent),
        status="pending_steam",
        exe_reselect_pending=True,
        updated_at=int(time.time()),
    )

    pending = _steam_main_process_running()
    if pending:
        # V7.2.5 lets the visible Tools window decide whether the user wants
        # Steam restarted immediately or prefers to defer the shortcut reload.
        # Avoid starting a competing finalizer when the GUI requested no-defer.
        if launch_deferred:
            launch_deferred_steam_finalizer(appid)
    else:
        _finalize_steam_shortcut_now(
            appid, game_name, selected, str(entry.get("icon") or "")
        )
    return {
        "ok": True,
        "game_name": game_name,
        "final_exe": str(selected),
        "final_exe_name": selected.name,
        "pending_steam": bool(pending),
    }



def _rename_steam_native_game(appid, new_name, launch_deferred=True):
    """Rename a Moses Steam shortcut without changing its AppID or game files.

    Keeping the AppID stable is intentional: the Proton compatdata prefix,
    Steam artwork filenames, play history and compatibility-tool mapping all
    stay attached to the same non-Steam shortcut. Only the visible title and
    Moses artwork/search name are changed.
    """
    appid = int(appid)
    new_name = re.sub(r"\s+", " ", str(new_name or "").strip())
    if not new_name:
        return {"ok": False, "error": "Game name cannot be empty."}
    if len(new_name) > 180:
        return {"ok": False, "error": "Game name is too long."}

    entry = load_steam_registry().get(str(appid)) or {}
    if not entry:
        return {"ok": False, "error": "The selected Steam game could not be found."}
    if str(entry.get("status") or "") == "removed":
        return {"ok": False, "error": "This game was removed from Moses OneClick."}

    old_name = str(entry.get("name") or f"Steam game {appid}").strip()
    final_text = str(entry.get("final_exe") or "").strip()
    if not final_text:
        return {"ok": False, "error": "The selected game does not have a saved main EXE."}
    final_exe = Path(final_text).expanduser()

    if new_name == old_name:
        return {"ok": True, "changed": False, "old_name": old_name, "new_name": new_name, "pending_steam": False}

    pending = _steam_main_process_running()
    update_steam_registry_entry(
        appid,
        name=new_name,
        status="pending_steam" if pending else str(entry.get("status") or "installed"),
        updated_at=int(time.time()),
    )

    if pending:
        if launch_deferred:
            launch_deferred_steam_finalizer(appid)
    else:
        try:
            _finalize_steam_shortcut_now(appid, new_name, final_exe, str(entry.get("icon") or ""))
        except Exception as exc:
            update_steam_registry_entry(appid, status="pending_steam", updated_at=int(time.time()))
            return {"ok": False, "error": str(exc), "old_name": old_name, "new_name": new_name}

    return {
        "ok": True,
        "changed": True,
        "old_name": old_name,
        "new_name": new_name,
        "pending_steam": bool(pending),
        "appid": appid,
    }

def reselect_steam_main_exe(appid):
    """Legacy host-side entry point; kept for compatibility.

    New Tools builds use JSON candidate/apply modes so the chooser belongs to
    the visible GTK window and cannot disappear because of host display state.
    """
    payload = _reselect_exe_candidate_payload(appid)
    if not payload.get("ok") or not payload.get("available"):
        return
    args = ["--menu", f"Choose the main game EXE for {payload.get('game_name', 'Game')}:"]
    for item in payload.get("candidates", []):
        args.extend([str(item.get("path") or ""), str(item.get("label") or "")])
    choice = dialog(args)
    if choice:
        _apply_reselected_steam_main_exe(appid, choice)


def launch_background_steam_artwork(appid, game_name):
    if not TOOLS_GUI_PATH.is_file():
        return False
    try:
        log = open(BACKGROUND_ARTWORK_LOG, "a", encoding="utf-8")
        subprocess.Popen(
            ["flatpak", "run", "--command=python3", APP_ID, str(TOOLS_GUI_PATH),
             "--background-steam-artwork", str(int(appid)), str(game_name or "")],
            stdout=log, stderr=log, start_new_session=True, close_fds=True,
        )
        log.close()
        return True
    except Exception:
        return False


def _steam_native_watch(appid, game_name, started_at, restore_exe=""):
    appid = int(appid)
    if not _wait_for_steam_native_session(appid):
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.ctime()}: AppID {appid} did not reach a clean finished state\n")
        return

    entry = (load_steam_registry().get(str(appid)) or {})
    try:
        same_generation = int(entry.get("created_at") or 0) == int(started_at)
    except Exception:
        same_generation = False
    if not entry or entry.get("status") == "removed" or not same_generation:
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.ctime()}: ignored stale Steam watcher for AppID {appid} generation {started_at}\n")
        return
    if restore_exe:
        final_exe = Path(restore_exe)
    else:
        final_exe = _find_game_exe(appid, game_name, started_at)
        if not final_exe:
            error(
                f"{game_name} finished, but One-Click could not find a newly installed main game EXE.\n\n"
                "The installer may have been cancelled, installed outside the Steam Proton C: drive, "
                "or used an unusual launcher. No system/Proton EXE was selected."
            )
            return

    update_steam_registry_entry(
        appid, name=game_name, final_exe=str(final_exe), start_dir=str(final_exe.parent),
        status="pending_steam", backend="steam", updated_at=int(time.time()),
    )
    if not restore_exe:
        launch_background_steam_artwork(appid, game_name)
    if _steam_main_process_running():
        launch_deferred_steam_finalizer(appid)
    else:
        _finalize_steam_shortcut_now(appid, game_name, final_exe, entry.get("icon", ""))

def launch_steam_native_watcher(appid, game_name, started_at, restore_exe=""):
    log = open(STEAM_NATIVE_LOG, "a", encoding="utf-8")
    args = [sys.executable, str(Path(__file__).resolve()), "steamwatch-native", str(int(appid)), game_name, str(int(started_at))]
    if restore_exe:
        args.append(str(restore_exe))
    subprocess.Popen(args, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    log.close()



def _looks_like_update_exe(exe: Path):
    """Conservative filename-only update/patch detection.

    We intentionally preselect Update rather than silently routing it. The user
    can still choose Install as new game when a title genuinely contains one of
    these words.
    """
    text = exe.stem.casefold().replace("_", " ").replace("-", " ")
    return bool(re.search(r"\b(update|patch|hotfix|upgrade|fixpack|title update)\b", text))


def _derive_update_game_name(exe: Path):
    raw = exe.stem.strip()
    # Remove common update marker + optional version/build suffix, in either
    # "Game Update 1.42" or "Game 1.42 Update" style.
    raw = re.sub(
        r"(?ix)[\s_.-]+(?:update|patch|hotfix|upgrade|fixpack|title[\s_.-]*update)"
        r"(?:[\s_.-]+(?:v(?:er(?:sion)?)?[\s_.-]*)?\d+(?:\.\d+)+(?:[a-z0-9.-]*)?)?$",
        "",
        raw,
    )
    raw = re.sub(
        r"(?ix)[\s_.-]+(?:v(?:er(?:sion)?)?[\s_.-]*)?\d+(?:\.\d+)+(?:[a-z0-9.-]*)?"
        r"[\s_.-]+(?:update|patch|hotfix|upgrade)$",
        "",
        raw,
    )
    cleaned = _clean_installer_name(raw)
    if not cleaned:
        cleaned = _clean_installer_name(exe.parent.name)
    return _smart_title_case(cleaned) if cleaned else derive_default_name(exe)


def _read_action_gui_result(result):
    if result.returncode != 0:
        return None
    for line in reversed((result.stdout or "").splitlines()):
        if line.startswith("ONECLICK_RESULT="):
            try:
                value = json.loads(line.split("=", 1)[1])
                return value if isinstance(value, dict) else None
            except Exception:
                return None
    return None


def choose_new_exe_action(
    exe: Path, suggested_override="", source_iso=False,
    stream_keep_extracted_source=None, force_likely_update=False,
):
    # StreamExtract can know that an EXE came from an archive explicitly
    # classified as a follow-up update even when the executable itself has a
    # generic name such as setup.exe. Keep the normal filename heuristic for
    # ordinary double-clicks, but allow that trusted workflow to preselect
    # Update in the existing Game Installer dialog.
    likely_update = bool(force_likely_update or _looks_like_update_exe(exe))
    suggested = str(suggested_override or "").strip() or (_derive_update_game_name(exe) if likely_update else derive_default_name(exe))
    if not ACTION_GUI_PATH.is_file():
        error(
            "The One-Click installer dialog is missing.\n\n"
            "Please reinstall One-Click V7.2.3."
        )
        return None
    try:
        # A previous Tools launch may have intentionally closed an old action
        # dialog. Never let that marker suppress a real future dialog error.
        try:
            ACTION_DIALOG_INTENTIONAL_CLOSE.unlink(missing_ok=True)
        except Exception:
            pass

        result = subprocess.run(
            [
                "flatpak", "run", "--command=python3", APP_ID,
                str(ACTION_GUI_PATH), "new-exe", str(exe), suggested,
                "1" if likely_update else "0", installer_backend(),
                json.dumps(_mounted_external_storage_choices(), separators=(",", ":")),
                "1" if source_iso else "0",
                "1" if stream_keep_extracted_source is not None else "0",
                "1" if bool(stream_keep_extracted_source) else "0",
            ],
            text=True, capture_output=True, timeout=60 * 60,
        )
    except Exception as exc:
        try:
            ACTION_DIALOG_LOG.write_text(
                f"Failed to launch One-Click installer dialog: {exc}\n", encoding="utf-8"
            )
        except Exception:
            pass
        error(
            "One-Click could not open its installer dialog.\n\n"
            f"Details were saved to:\n{ACTION_DIALOG_LOG}"
        )
        return None

    parsed = _read_action_gui_result(result)
    if parsed:
        return parsed
    if result.returncode == 0:
        return None  # user cancelled/closed it

    # Opening One-Click Tools intentionally stops the Lutris Flatpak so its
    # database/config cannot be stale. The rich installer dialog lives inside
    # that same Flatpak, so it is terminated too. Treat that specific case as
    # a normal cancel/hand-off, not a crash.
    try:
        if ACTION_DIALOG_INTENTIONAL_CLOSE.is_file():
            age = time.time() - ACTION_DIALOG_INTENTIONAL_CLOSE.stat().st_mtime
            ACTION_DIALOG_INTENTIONAL_CLOSE.unlink(missing_ok=True)
            if 0 <= age <= 20:
                return None
    except Exception:
        pass

    try:
        ACTION_DIALOG_LOG.write_text(
            "One-Click installer dialog failed.\n\n"
            f"Exit code: {result.returncode}\n\n"
            f"STDOUT:\n{result.stdout or ''}\n\n"
            f"STDERR:\n{result.stderr or ''}\n",
            encoding="utf-8",
        )
    except Exception:
        pass
    error(
        "One-Click's installer dialog failed to start.\n\n"
        f"Please send this log if it happens again:\n{ACTION_DIALOG_LOG}"
    )
    return None

def _folder_norm_name(text: str) -> str:
    text = str(text or "").casefold().replace("&", " and ")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def _clean_folder_game_name(raw_name: str) -> str:
    """Turn release/package folder names into a plausible human game title.

    Find Game EXE often starts inside extracted release folders such as
    ``DuckTales Remastered (incl. Update 5)`` or
    ``Age of Empires Definitive Edition (build 38862)``.  Those package/build
    annotations are not part of the game title, so strip them before scoring
    path components.  Keep this deliberately suffix-only so legitimate words
    inside a title are not removed.
    """
    text = str(raw_name or "").strip()
    if not text:
        return ""

    release_groups = (
        r"elamigos|fitgirl|dodi|repack|portable|gog|codex|plaza|tenoke|"
        r"rune|flt|skidrow|empress|multi\d*|pcv?\d*|win(?:32|64)?|x(?:86|64)"
    )

    # Release folders frequently stack metadata, for example:
    #   Game (incl. Update 5)-elamigos
    #   Game-Update46777-elamigos
    #   Game (build 38862)
    # Repeat a few times so removing a release-group suffix exposes the update
    # suffix immediately before it.
    for _ in range(4):
        before = text

        # Plain trailing release/platform tags.
        text = re.sub(
            rf"(?ix)(?:[\s._-]+(?:{release_groups}))+$",
            "",
            text,
        ).strip(" -_.")

        # Bracketed packaging/build/update metadata.  Accept both ``incl`` and
        # ``incl.`` because both are common in extracted folder names.
        text = re.sub(
            r"(?ix)\s*[\[(]\s*(?:"
            r"(?:(?:incl\.?|including|with)\s+)?(?:update|patch|hotfix|upgrade)\b[^\])]*|"
            r"(?:build|revision|rev)\s*[-_. ]*\d[\w.-]*|"
            r"(?:pc|windows|win64|win32|x64|x86|portable|repack|gog|multi\d*|"
            r"elamigos|fitgirl|dodi|codex|plaza|tenoke|rune|flt|skidrow|empress)"
            r")\s*[\])]\s*$",
            "",
            text,
        ).strip(" -_.")

        # Unbracketed update/build suffixes, including compressed release names
        # like ``-Update46777``.
        text = re.sub(
            r"(?ix)[\s._-]+(?:"
            r"(?:(?:incl\.?|including|with)[\s._-]*)?(?:update|patch|hotfix|upgrade)[\s._-]*v?\d[\w.-]*|"
            r"(?:build|revision|rev)[\s._-]*\d[\w.-]*"
            r")$",
            "",
            text,
        ).strip(" -_.")

        if text == before:
            break

    text = _clean_installer_name(text)
    return _smart_title_case(text) if text else ""

def _folder_name_quality(name: str) -> int:
    """Score whether a path component looks like a real human game title."""
    clean = str(name or "").strip()
    if not clean:
        return -10000
    norm = _folder_norm_name(clean)
    if not norm:
        return -10000
    if norm in {
        "bin", "binaries", "game", "games", "setup", "installer", "install",
        "redist", "support", "data", "files", "program files", "program files x86",
    }:
        return -1000

    words = clean.split()
    letters = sum(ch.isalpha() for ch in clean)
    digits = sum(ch.isdigit() for ch in clean)
    score = 0
    score += min(len(words), 8) * 12
    if len(words) >= 2:
        score += 28
    if any(ch in clean for ch in ("'", ":", "-")):
        score += 8
    if 4 <= letters <= 80:
        score += 20
    if digits:
        ratio = digits / max(1, letters + digits)
        score -= int(ratio * 120)
    # Archive/release folder names are often one long token with digits woven
    # through otherwise recognizable words. Prefer a clean nested folder.
    if len(words) == 1 and len(clean) > 18:
        score -= 35
    if len(re.findall(r"(?i)[a-z]\d|\d[a-z]", clean)) >= 3:
        score -= 80
    if re.search(r"(?i)\b(?:update|patch|hotfix|upgrade|build|revision|rev|repack|elamigos|fitgirl|dodi)\b", clean):
        score -= 120
    return score


def _suggest_game_name_for_candidate(folder: Path, exe_path: Path, fallback: str = "") -> str:
    """Derive a display name from the most human-looking path component."""
    folder = folder.resolve()
    exe_path = exe_path.resolve()
    raw_candidates = []

    # A non-generic EXE filename can itself be the best clue for portable games.
    stem = exe_path.stem.strip()
    if stem.casefold() not in {
        "setup", "setup64", "setup_x64", "setup-x64", "install", "installer",
        "launcher", "start", "game", "update", "patch",
    }:
        raw_candidates.append(stem)

    current = exe_path.parent
    for _ in range(12):
        raw_candidates.append(current.name)
        if current == folder or current.parent == current:
            break
        try:
            current.relative_to(folder)
        except Exception:
            break
        current = current.parent
    raw_candidates.append(folder.name)
    if fallback:
        raw_candidates.append(fallback)

    best_name = ""
    best_score = -10000
    seen = set()
    for index, raw in enumerate(raw_candidates):
        clean = _clean_folder_game_name(raw)
        norm = _folder_norm_name(clean)
        if not clean or not norm or norm in seen:
            continue
        seen.add(norm)
        score = _folder_name_quality(clean)
        # Prefer the directory closest to the selected EXE when two names are
        # otherwise similarly plausible. This makes an inner clean game folder
        # beat an outer repack/update package folder.
        score += max(0, 30 - (index * 5))
        if score > best_score:
            best_name, best_score = clean, score
    return best_name or (_smart_title_case(_clean_installer_name(fallback)) if fallback else "New Game")


def _scan_game_folder_exes(folder: Path, game_name: str, limit=18, purpose="existing"):
    purpose = "install" if str(purpose).strip().lower() == "install" else "existing"
    folder = folder.resolve()
    candidates = []
    skip_dirs = {
        "$recycle.bin", "system volume information", "__pycache__", ".git",
        "redist", "redists", "_redist", "__redist", "redistributables",
        "directx", "vcredist", "dotnet", "prereq", "prereqs", "prerequisites",
    }
    # For installer discovery, folders literally named Installer/Installers or
    # Support may contain the real setup.exe. Existing-game discovery still
    # skips them so setup helpers are not mistaken for the final game EXE.
    if purpose != "install":
        skip_dirs.update({"support", "supportfiles", "installer", "installers"})
    norm_game = re.sub(r"[^a-z0-9]+", "", game_name.casefold())
    root_depth = len(folder.parts)
    seen = 0

    try:
        walker = os.walk(folder)
        for root_text, dirs, files in walker:
            root = Path(root_text)
            depth = len(root.parts) - root_depth
            if depth > 10:
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d.casefold() not in skip_dirs]
            for filename in files:
                if not filename.casefold().endswith(".exe"):
                    continue
                seen += 1
                if seen > 12000:
                    break
                path = root / filename
                score = _candidate_score(path, game_name, 0)
                low = path.stem.casefold()
                rel_text = str(path.relative_to(folder)).casefold().replace("\\", "/")

                norm_stem = re.sub(r"[^a-z0-9]+", "", low)
                if norm_game and (norm_game in norm_stem or norm_stem in norm_game) and len(norm_stem) >= 4:
                    score += 90
                if path.parent == folder:
                    score += 25

                if purpose == "install":
                    # Folder -> Find EXE + Install is intentionally looking for
                    # setup/installer/update executables.  Do NOT use the
                    # existing-game penalties here; those caused setup.exe to
                    # be discovered and then thrown away in V6.7.11.
                    if low in {"setup", "install", "installer"}:
                        score += 260
                    elif low.startswith(("setup", "install")):
                        score += 220
                    if any(x in low for x in ("update", "patch", "hotfix", "upgrade")):
                        score += 120
                    if any(x in low for x in ("unins", "uninstall", "crash", "report", "redist", "dxsetup")):
                        score -= 180
                    # Installer packages commonly keep setup.exe one or two
                    # levels below the folder the user right-clicked.
                    score += max(0, 28 - (depth * 4))
                else:
                    # Existing/portable game mode: strongly avoid setup/update
                    # utilities and prefer the actual gameplay executable.
                    if any(x in low for x in ("update", "patch", "hotfix", "unins", "uninstall", "setup", "installer", "crash", "report", "redist", "dxsetup")):
                        score -= 180
                    if any(x in rel_text for x in ("/redist/", "/_redist/", "/support/", "/installer/")):
                        score -= 120
                candidates.append((score, path))
            if seen > 12000:
                break
    except Exception:
        pass

    candidates.sort(key=lambda item: (-item[0], len(str(item[1]))))
    # Install mode is deliberately permissive because installer packages can
    # use generic names such as setup.exe. Existing-game mode stays stricter.
    threshold = -170 if purpose == "install" else -50
    useful = [(score, path) for score, path in candidates if score > threshold]
    return useful[: int(limit)]


def choose_game_exe_from_folder(folder: Path, suggested_name=None, purpose="existing"):
    purpose = "install" if str(purpose).strip().lower() == "install" else "existing"
    folder = folder.resolve()
    if suggested_name:
        rough_name = str(suggested_name).strip()
    elif folder.name.startswith(".streamextract-") or folder.parent.name.startswith(".streamextract-"):
        rough_name = ""
    else:
        rough_name = _smart_title_case(_clean_installer_name(folder.name) or folder.name)
    candidates = _scan_game_folder_exes(folder, rough_name, purpose=purpose)
    if not candidates:
        wanted = "Windows installer/update EXE" if purpose == "install" else "Windows game EXE"
        error(
            f"One-Click could not find any plausible {wanted} in this folder.\n\n"
            f"Folder:\n{folder}"
        )
        return None

    # The folder the user right-clicked may be a mangled release/archive name.
    # Use the best-ranked EXE path to infer a cleaner title, then re-rank once
    # using that title so the EXE ranking and display name reinforce each other.
    game_name = _suggest_game_name_for_candidate(folder, candidates[0][1], rough_name)
    if _folder_norm_name(game_name) != _folder_norm_name(rough_name):
        reranked = _scan_game_folder_exes(folder, game_name, purpose=purpose)
        if reranked:
            candidates = reranked

    payload = []
    for score, path in candidates:
        try:
            rel = str(path.relative_to(folder))
        except Exception:
            rel = str(path)
        try:
            size = path.stat().st_size
        except OSError:
            size = 0
        payload.append({
            "path": str(path),
            "label": rel,
            "score": int(score),
            "size": int(size),
            "suggested_name": _suggest_game_name_for_candidate(folder, path, game_name),
        })

    if not ACTION_GUI_PATH.is_file():
        error(
            "The One-Click existing-game dialog is missing.\n\n"
            "Please reinstall One-Click V7.2.3."
        )
        return None
    try:
        result = subprocess.run(
            [
                "flatpak", "run", "--command=python3", APP_ID,
                str(ACTION_GUI_PATH), "folder-install" if purpose == "install" else "folder", str(folder), game_name,
                json.dumps(payload, separators=(",", ":")),
            ],
            text=True, capture_output=True, timeout=60 * 60,
        )
        parsed = _read_action_gui_result(result)
        if parsed and parsed.get("exe"):
            return parsed
        if result.returncode == 0:
            return None
        ACTION_DIALOG_LOG.write_text(
            "One-Click existing-game dialog failed.\n\n"
            f"Exit code: {result.returncode}\n\n"
            f"STDOUT:\n{result.stdout or ''}\n\n"
            f"STDERR:\n{result.stderr or ''}\n",
            encoding="utf-8",
        )
        error(
            "One-Click's existing-game dialog failed to start.\n\n"
            f"Please send this log if it happens again:\n{ACTION_DIALOG_LOG}"
        )
        return None
    except Exception as exc:
        try:
            ACTION_DIALOG_LOG.write_text(
                f"Failed to launch existing-game dialog: {exc}\n", encoding="utf-8"
            )
        except Exception:
            pass
        error(
            "One-Click could not open its existing-game dialog.\n\n"
            f"Details were saved to:\n{ACTION_DIALOG_LOG}"
        )
        return None
def add_existing_steam_exe(exe: Path, game_name: str):
    """Register an already-complete Windows game without running an installer."""
    exe = exe.expanduser().resolve()
    if not exe.is_file():
        error(f"Game EXE was not found:\n\n{exe}")
        return
    game_name = str(game_name or "").strip() or _smart_title_case(_clean_installer_name(exe.parent.name) or exe.stem)
    appid = _steam_native_appid(game_name)
    existing = load_steam_registry().get(str(appid)) or {}
    # A title that was previously removed has a tombstone specifically to block
    # delayed background workers. A deliberate Add Existing action is different:
    # it is an explicit new registration, so reset that tombstone before writing
    # the new shortcut/EXE. Without this, Steam could contain the newly re-added
    # shortcut while Moses still thought the game was removed, breaking dependency
    # repair and other per-game actions.
    if str(existing.get("status") or "") == "removed":
        _clear_removal_tombstone(appid)
        update_steam_registry_entry(appid, status="installing", name=game_name, created_at=int(time.time()))
        existing = {}
    if existing.get("status") in {"installed", "pending_steam", "detached"} and existing.get("final_exe"):
        old = str(existing.get("final_exe") or "")
        if old != str(exe):
            if subprocess.run(
                ["kdialog", "--warningyesno",
                 f"{game_name} is already managed by One-Click.\n\n"
                 f"Current EXE:\n{old}\n\nReplace it with:\n{exe}?"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode != 0:
                return

    update_steam_registry_entry(
        appid,
        name=game_name,
        installer="",
        final_exe=str(exe),
        start_dir=str(exe.parent),
        status="pending_steam",
        backend="steam",
        compat_tool=str(existing.get("compat_tool") or DEFAULT_STEAM_COMPAT_TOOL),
        artwork_pending=False,
        created_at=int(existing.get("created_at") or time.time()),
        updated_at=int(time.time()),
    )

    commit = _commit_steam_shortcut_reliably(appid, game_name, exe, existing.get("icon", ""))
    if not commit.get("ok"):
        error(
            f"{game_name} was not added to Steam.\n\n"
            f"{commit.get('error') or 'The shortcut could not be created or verified.'}\n\n"
            "The game files were not changed."
        )
        return

    launch_dependency_cache_refresh("steam", appid)
    update_steam_registry_entry(appid, artwork_pending=True, updated_at=int(time.time()))
    launch_background_steam_artwork(appid, game_name)
    if commit.get("pending"):
        popup_text = (
            f"{game_name} is ready. Steam was NOT restarted. "
            "Restart/close Steam manually when you want and the shortcut will finalize automatically. "
            "Artwork is downloading in the background."
        )
    else:
        popup_text = (
            f"{game_name} was added to Steam successfully. "
            + ("Steam was restarted automatically and the shortcut was verified after restart. " if commit.get("restarted") else "")
            + "Artwork is downloading in the background."
        )
    subprocess.run(
        ["kdialog", "--passivepopup", popup_text, "8"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def add_existing_from_folder(folder: Path):
    folder = folder.expanduser().resolve()
    if not folder.is_dir():
        error(f"Folder was not found:\n\n{folder}")
        return
    picked = choose_game_exe_from_folder(folder)
    if not picked:
        return
    add_existing_steam_exe(Path(picked["exe"]), picked.get("name") or folder.name)


def move_existing_folder_to_game_root_and_add(folder: Path):
    """Move a complete game folder into Moses' internal Steam game root, then add it.

    The EXE/name chooser is intentionally shown before any filesystem move. If
    the user cancels that dialog, nothing is moved. Once confirmed, the whole
    selected folder is moved (renamed when possible, copied+removed across
    filesystems by shutil.move), the selected EXE path is rebased to the new
    location, and the normal Add Existing Steam workflow takes over.
    """
    folder = folder.expanduser().resolve()
    if not folder.is_dir():
        error(f"Folder was not found:\n\n{folder}")
        return

    INTERNAL_PREFIX_ROOT.mkdir(parents=True, exist_ok=True)
    root = INTERNAL_PREFIX_ROOT.expanduser().resolve()

    # Never allow a broad ancestor (Home, game-prefixes, etc.) to be moved into
    # its own descendant. A folder already inside the target root is safe and
    # simply skips the move step.
    if folder == root or folder in root.parents:
        error(
            "Please select the game's own folder, not the Moses Game Folder or one of its parent folders.\n\n"
            f"Game Folder:\n{root}"
        )
        return

    picked = choose_game_exe_from_folder(folder)
    if not picked:
        return

    selected_exe = Path(picked["exe"]).expanduser().resolve()
    game_name = (picked.get("name") or folder.name).strip() or folder.name
    try:
        relative_exe = selected_exe.relative_to(folder)
    except Exception:
        error(
            "The selected EXE is not inside the folder you chose.\n\n"
            f"Folder:\n{folder}\n\nEXE:\n{selected_exe}"
        )
        return

    # If the game is already somewhere inside Moses' Steam-Proton game root,
    # do not move it again; continue with the exact same Add Existing workflow.
    if folder == root or root in folder.parents:
        add_existing_steam_exe(selected_exe, game_name)
        return

    base_name = _steam_named_prefix_name(game_name or folder.name)
    destination = root / base_name

    if destination.exists() or destination.is_symlink():
        suffix = 2
        while suffix < 1000:
            candidate = root / f"{base_name} ({suffix})"
            if not candidate.exists() and not candidate.is_symlink():
                break
            suffix += 1
        else:
            error(
                "Moses could not find a free destination name in the Game Folder.\n\n"
                f"Game Folder:\n{root}"
            )
            return

        if not confirm(
            "A folder with this game name already exists in the Moses Game Folder.\n\n"
            f"Existing:\n{destination}\n\n"
            f"Move this folder as:\n{candidate.name}\n\nContinue?"
        ):
            return
        destination = candidate

    # Give immediate feedback. Same-filesystem moves are normally instant;
    # cross-filesystem moves may take longer because the files must be copied.
    subprocess.run(
        ["kdialog", "--passivepopup", f"Moving {folder.name} to the Moses Game Folder…", "5"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        moved_path = Path(shutil.move(str(folder), str(destination))).expanduser().resolve()
    except Exception as exc:
        error(
            "The game folder could not be moved. No Steam shortcut was created.\n\n"
            f"From:\n{folder}\n\nTo:\n{destination}\n\nError:\n{exc}"
        )
        return

    moved_exe = moved_path / relative_exe
    if not moved_exe.is_file():
        error(
            "The folder was moved, but Moses could not find the selected EXE at its new location.\n\n"
            f"Moved folder:\n{moved_path}\n\nExpected EXE:\n{moved_exe}\n\n"
            "The files were kept; you can right-click the moved folder and use Find Game EXE + Add to Steam."
        )
        return

    add_existing_steam_exe(moved_exe, game_name)


def _stream_direct_prefix_path(game_name, storage_mode="internal", storage_root=""):
    safe_name = _steam_named_prefix_name(game_name)
    if str(storage_mode).lower() == "external":
        root = _validate_external_storage(storage_root)
        return root / "OneClick Games" / "Steam-Proton" / safe_name
    INTERNAL_PREFIX_ROOT.mkdir(parents=True, exist_ok=True)
    return INTERNAL_PREFIX_ROOT / safe_name


def _stream_prepare_storage(storage_path="", storage_fstype="", game_name="", replace_existing=False, stream_pid=0):
    """Prepare either a named final folder or an invisible per-job staging folder.

    V7.4.12 keeps StreamExtract fully automatic: extraction always happens in a
    hidden .streamextract-<session>/Files staging folder and successful
    finalization renames that prefix to the game title chosen/detected from the EXE.
    """
    game_name = str(game_name or "").strip()
    storage_path = str(storage_path or "").strip()
    storage_fstype = str(storage_fstype or "").strip().lower()
    storage_mode = "external" if storage_path else "internal"

    if storage_mode == "external":
        storage_obj = Path(storage_path).expanduser().resolve()
        current_fs = str(storage_fstype or _filesystem_type_for_path(storage_obj) or "").lower()
        if current_fs in SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS and storage_obj.is_dir() and not os.access(storage_obj, os.W_OK):
            if not confirm(
                f"This external drive already uses {current_fs.upper()}, which is suitable for Steam/Proton, "
                "but its filesystem root is not writable by your SteamOS user.\n\n"
                "Moses OneClick Tool can fix the drive-root ownership without formatting or deleting game data.\n\n"
                f"Drive: {storage_obj}\n\nFix drive permissions now?"
            ):
                return {"ok": False, "cancelled": True}
            source = _external_block_device_for_mount(storage_obj)
            _make_external_volume_writable(storage_obj, source)

        try:
            storage_obj = _validate_external_storage(storage_obj)
        except Exception:
            replacement = _format_external_storage_assistant(str(storage_obj), current_fs)
            if not replacement:
                return {"ok": False, "cancelled": True}
            storage_obj = _validate_external_storage(replacement)

        _register_external_drive(storage_obj)
        storage_root = str(storage_obj)
        fstype = _filesystem_type_for_path(storage_obj)
        uuid_text = _filesystem_uuid_for_path(storage_obj)
        prefix_root = storage_obj / "OneClick Games" / "Steam-Proton"
    else:
        storage_obj = None
        storage_root = ""
        INTERNAL_PREFIX_ROOT.mkdir(parents=True, exist_ok=True)
        fstype = _filesystem_type_for_path(INTERNAL_PREFIX_ROOT)
        uuid_text = ""
        prefix_root = INTERNAL_PREFIX_ROOT

    prefix_root.mkdir(parents=True, exist_ok=True)
    session_seed = f"{time.time_ns()}:{os.getpid()}:{stream_pid}:{prefix_root}:{game_name}"
    session_id = hashlib.sha256(session_seed.encode("utf-8", errors="replace")).hexdigest()[:24]
    staging = not bool(game_name)
    if staging:
        prefix_dir = prefix_root / f".streamextract-{session_id[:16]}"
    else:
        prefix_dir = _stream_direct_prefix_path(game_name, storage_mode, storage_root)

    files_dir = prefix_dir / "Files"
    prefix_dir.mkdir(parents=True, exist_ok=True)

    has_content = False
    if files_dir.exists():
        try:
            has_content = any(files_dir.iterdir())
        except Exception:
            has_content = True
    if has_content and not bool(replace_existing):
        return {
            "ok": False,
            "conflict": True,
            "files_dir": str(files_dir),
            "storage_mode": storage_mode,
            "storage_root": storage_root,
            "game_name": game_name,
        }
    if has_content and bool(replace_existing):
        if files_dir.is_symlink() or files_dir.is_file():
            files_dir.unlink(missing_ok=True)
        else:
            shutil.rmtree(files_dir)
    files_dir.mkdir(parents=True, exist_ok=True)

    marker_payload = {
        "owner": "moses-streamextract",
        "status": "in_progress",
        "session_id": session_id,
        "stream_pid": int(stream_pid or 0),
        "game_name": game_name,
        "staging": staging,
        "created_at": int(time.time()),
    }
    try:
        (prefix_dir / STREAM_COMPLETE_MARKER).unlink(missing_ok=True)
        (prefix_dir / STREAM_IN_PROGRESS_MARKER).write_text(
            json.dumps(marker_payload, indent=2), encoding="utf-8"
        )
    except Exception as exc:
        return {"ok": False, "error": f"Could not mark the StreamExtract session: {exc}"}

    return {
        "ok": True,
        "storage_mode": storage_mode,
        "storage_root": storage_root,
        "storage_fstype": fstype,
        "storage_uuid": uuid_text,
        "game_name": game_name,
        "staging": staging,
        "prefix_dir": str(prefix_dir),
        "files_dir": str(files_dir),
        "session_id": session_id,
    }


def _stream_prefix_path_is_allowed(path: Path) -> bool:
    try:
        path = path.expanduser().resolve(strict=False)
        internal = INTERNAL_PREFIX_ROOT.expanduser().resolve(strict=False)
        if path.parent == internal:
            return True
        return path.parent.name == "Steam-Proton" and path.parent.parent.name == "OneClick Games"
    except Exception:
        return False


def _read_stream_marker(prefix_dir: Path):
    try:
        data = json.loads((prefix_dir / STREAM_IN_PROGRESS_MARKER).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _stream_mark_complete(prefix_text, session_id=""):
    prefix_dir = Path(str(prefix_text or "")).expanduser().resolve(strict=False)
    if not _stream_prefix_path_is_allowed(prefix_dir):
        return {"ok": False, "error": "Unsafe StreamExtract prefix path."}
    marker = _read_stream_marker(prefix_dir)
    if not marker or str(marker.get("session_id") or "") != str(session_id or ""):
        return {"ok": False, "error": "StreamExtract session marker did not match."}
    payload = dict(marker)
    payload["status"] = "complete"
    payload["completed_at"] = int(time.time())
    try:
        (prefix_dir / STREAM_COMPLETE_MARKER).write_text(json.dumps(payload, indent=2), encoding="utf-8")
        (prefix_dir / STREAM_IN_PROGRESS_MARKER).unlink(missing_ok=True)
        return {"ok": True}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def _stream_abort_prefix(prefix_text, session_id=""):
    prefix_dir = Path(str(prefix_text or "")).expanduser().resolve(strict=False)
    if not _stream_prefix_path_is_allowed(prefix_dir):
        return {"ok": False, "removed": False, "error": "Unsafe StreamExtract prefix path."}
    marker = _read_stream_marker(prefix_dir)
    if not marker or str(marker.get("session_id") or "") != str(session_id or ""):
        return {"ok": False, "removed": False, "error": "StreamExtract session marker did not match."}
    if str(marker.get("status") or "") != "in_progress":
        return {"ok": False, "removed": False, "error": "StreamExtract session is no longer marked in progress."}
    size = _directory_size(prefix_dir)
    try:
        shutil.rmtree(prefix_dir)
        return {"ok": True, "removed": True, "bytes": size}
    except Exception as exc:
        return {"ok": False, "removed": False, "error": str(exc)}


def _stream_preserve_failed_prefix(prefix_text, session_id=""):
    """Preserve a failed StreamExtract job in a visible recovery folder."""
    prefix_dir = Path(str(prefix_text or "")).expanduser().resolve(strict=False)
    if not _stream_prefix_path_is_allowed(prefix_dir):
        return {"ok": False, "error": "Unsafe StreamExtract prefix path."}
    marker = _read_stream_marker(prefix_dir)
    if not marker or str(marker.get("session_id") or "") != str(session_id or ""):
        return {"ok": False, "error": "StreamExtract session marker did not match."}
    if str(marker.get("status") or "") != "in_progress":
        return {"ok": False, "error": "StreamExtract session is no longer marked in progress."}

    parent = prefix_dir.parent
    stamp = time.strftime("%Y-%m-%d %H%M%S")
    base = parent / f"StreamExtract Recovery - {stamp}"
    target = base
    suffix = 2
    while target.exists():
        target = parent / f"{base.name} ({suffix})"
        suffix += 1

    payload = dict(marker)
    payload["status"] = "recovery"
    payload["failed_at"] = int(time.time())
    try:
        (prefix_dir / ".streamextract-recovery.json").write_text(
            json.dumps(payload, indent=2), encoding="utf-8"
        )
        (prefix_dir / STREAM_IN_PROGRESS_MARKER).unlink(missing_ok=True)
        prefix_dir.rename(target)
        return {
            "ok": True,
            "path": str(target),
            "files_dir": str(target / "Files"),
            "bytes": _directory_size(target),
        }
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def _pid_is_active_streamextract(pid):
    try:
        pid = int(pid or 0)
        if pid <= 1:
            return False
        cmdline = Path(f"/proc/{pid}/cmdline")
        if not cmdline.is_file():
            return False
        text = cmdline.read_bytes().replace(b"\x00", b" ").decode("utf-8", errors="replace").lower()
        return "stream_extract_gui.py" in text or "moses-streamextract" in text
    except Exception:
        return False


def _looks_like_legacy_opaque_stream_name(name):
    raw = str(name or "").strip()
    compact = re.sub(r"[^A-Za-z0-9]", "", raw)
    if len(compact) < 32:
        return False
    digits = sum(ch.isdigit() for ch in compact)
    transitions = len(re.findall(r"(?i)[a-z]\d|\d[a-z]", compact))
    return digits >= 5 and (len(raw) >= 45 or transitions >= 4)


def _stream_prefix_roots_for_cleanup():
    roots = [INTERNAL_PREFIX_ROOT]
    try:
        for item in _mounted_external_storage_choices():
            root_text = str(item.get("path") or "") if isinstance(item, dict) else ""
            if root_text:
                roots.append(Path(root_text) / "OneClick Games" / "Steam-Proton")
    except Exception:
        pass
    unique = []
    seen = set()
    for root in roots:
        try:
            key = str(Path(root).expanduser().resolve(strict=False))
        except Exception:
            continue
        if key not in seen:
            seen.add(key)
            unique.append(Path(key))
    return unique


def _cleanup_failed_stream_prefixes(games):
    referenced = set()
    for entry in (games or {}).values():
        path_text = str((entry or {}).get("compatdata") or "").strip()
        if path_text:
            try:
                referenced.add(str(Path(path_text).expanduser().resolve(strict=False)))
            except Exception:
                pass

    removed = []
    skipped = []
    for root in _stream_prefix_roots_for_cleanup():
        if not root.is_dir():
            continue
        try:
            children = list(root.iterdir())
        except Exception:
            continue
        for child in children:
            if not child.is_dir() or child.is_symlink():
                continue
            try:
                child_resolved = str(child.resolve(strict=False))
            except Exception:
                continue
            if child_resolved in referenced:
                continue
            if (child / ONECLICK_PREFIX_MARKER).is_file() or (child / STREAM_COMPLETE_MARKER).is_file():
                continue

            marker = _read_stream_marker(child)
            if marker:
                if _pid_is_active_streamextract(marker.get("stream_pid")):
                    skipped.append(child.name)
                    continue
                is_failed_candidate = str(marker.get("status") or "") == "in_progress"
            else:
                # V7.4.4 did not create StreamExtract session markers. Only use
                # a deliberately strict opaque-token heuristic for those legacy
                # leftovers, such as the long signed-link folder shown by the user.
                is_failed_candidate = _looks_like_legacy_opaque_stream_name(child.name)

            if not is_failed_candidate:
                continue
            size = _directory_size(child)
            try:
                shutil.rmtree(child)
                removed.append((child.name, size))
            except Exception:
                skipped.append(child.name)
    return removed, skipped


def _stream_finalize_extracted_game(files_text, storage_mode="internal", storage_root="", initial_game_name=""):
    """Register a game whose files already live in its final Files directory."""
    files_dir = Path(str(files_text or "")).expanduser().resolve()
    if not files_dir.is_dir():
        return {"ok": False, "error": f"Extracted files folder was not found: {files_dir}"}

    prefix_before = files_dir.parent
    is_staging = prefix_before.name.startswith(".streamextract-")
    initial_game_name = str(initial_game_name or "").strip()
    if not initial_game_name and not is_staging:
        initial_game_name = prefix_before.name
    picked = choose_game_exe_from_folder(files_dir, suggested_name=initial_game_name or None)
    if not picked:
        return {"ok": False, "cancelled": True, "files_dir": str(files_dir)}

    selected_exe = Path(str(picked.get("exe") or "")).expanduser().resolve()
    game_name = str(picked.get("name") or "").strip()
    if not game_name:
        game_name = initial_game_name or _suggest_game_name_for_candidate(files_dir, selected_exe, "New Game")
    try:
        exe_rel = selected_exe.relative_to(files_dir)
    except Exception:
        return {"ok": False, "error": "The selected EXE is outside the extracted game folder.", "files_dir": str(files_dir)}

    requested_mode = "external" if str(storage_mode).lower() == "external" else "internal"

    # Hidden StreamExtract staging folders are ALWAYS renamed after the EXE/name
    # is detected. Named jobs still rename only when the chooser corrects the title.
    if is_staging or _folder_norm_name(game_name) != _folder_norm_name(initial_game_name):
        try:
            old_prefix = files_dir.parent
            new_prefix = _stream_direct_prefix_path(game_name, requested_mode, storage_root)
            if new_prefix.resolve(strict=False) != old_prefix.resolve(strict=False):
                if new_prefix.exists() and any(new_prefix.iterdir()):
                    return {
                        "ok": False,
                        "error": f"A Moses OneClick folder already exists for {game_name}:\n\n{new_prefix}",
                        "files_dir": str(files_dir),
                    }
                new_prefix.parent.mkdir(parents=True, exist_ok=True)
                if new_prefix.exists():
                    new_prefix.rmdir()
                old_prefix.rename(new_prefix)
                files_dir = new_prefix / "Files"
                selected_exe = files_dir / exe_rel
        except Exception as exc:
            return {"ok": False, "error": f"Could not rename the game folder: {exc}", "files_dir": str(files_dir)}

    appid = _steam_native_appid(game_name)
    existing = dict(load_steam_registry().get(str(appid)) or {})
    if str(existing.get("status") or "") == "removed":
        _clear_removal_tombstone(appid)
        update_steam_registry_entry(appid, status="installing", name=game_name, created_at=int(time.time()))
        existing = {}
    existing_mode = str(existing.get("storage_mode") or "internal").lower() if existing else ""
    if existing and existing.get("status") in {"installed", "pending_steam", "detached"} and existing_mode != requested_mode:
        return {
            "ok": False,
            "error": (
                f"{game_name} is already managed on {existing_mode} storage. "
                "Use Complete Game Removal before importing the same game to a different storage location."
            ),
            "files_dir": str(files_dir),
        }

    try:
        # Mark the already-created real folder so the normal compatdata helper
        # recognizes it as OneClick-owned rather than creating a duplicate name.
        _write_oneclick_prefix_marker(files_dir.parent, appid)
        if requested_mode == "external":
            root = _validate_external_storage(storage_root)
            compatdata = _prepare_external_steam_compatdata(appid, game_name, root)
            final_exe = Path(compatdata) / "Files" / exe_rel
            saved_root = str(root)
            saved_uuid = _filesystem_uuid_for_path(root)
        else:
            compatdata = _prepare_internal_named_steam_compatdata(appid, game_name)
            final_exe = Path(compatdata) / "Files" / exe_rel
            saved_root = ""
            saved_uuid = ""
    except Exception as exc:
        return {"ok": False, "error": str(exc), "files_dir": str(files_dir)}

    if not final_exe.is_file():
        return {
            "ok": False,
            "error": f"The selected EXE could not be found in the final game folder: {final_exe}",
            "files_dir": str(files_dir),
        }

    now = int(time.time())
    update_steam_registry_entry(
        appid,
        name=game_name,
        installer="",
        final_exe=str(final_exe),
        start_dir=str(final_exe.parent),
        compatdata=str(compatdata),
        status="pending_steam",
        backend="steam",
        storage_mode=requested_mode,
        storage_root=saved_root,
        storage_uuid=saved_uuid,
        compat_tool=str(existing.get("compat_tool") or DEFAULT_STEAM_COMPAT_TOOL),
        # Commit the shortcut before starting the artwork worker. Older builds
        # waited for artwork_pending=False and could miss a very fast Steam
        # shutdown/restart window, leaving artwork present but no shortcut.
        artwork_pending=False,
        created_at=int(existing.get("created_at") or now),
        updated_at=now,
        stream_extract=True,
    )
    _clear_removal_tombstone(appid)

    commit = _commit_steam_shortcut_reliably(
        appid, game_name, final_exe, existing.get("icon", "")
    )
    if not commit.get("ok"):
        # Keep the fully extracted files and registry entry so Repair Steam
        # Shortcut can recover it. Never claim that Steam registration worked.
        update_steam_registry_entry(appid, status="pending_steam", updated_at=int(time.time()))
        return {
            "ok": False,
            "error": (
                "The game was extracted successfully, but the Steam shortcut could not be created or verified.\n\n"
                + str(commit.get("error") or "Unknown shortcut error")
                + "\n\nThe extracted game files were kept."
            ),
            "files_dir": str(files_dir),
        }

    # The shortcut now exists and was verified. Artwork can safely happen in
    # the background; even if its later icon refresh is deferred, the game is
    # already visible in Steam.
    launch_dependency_cache_refresh("steam", appid)
    update_steam_registry_entry(appid, artwork_pending=True, updated_at=int(time.time()))
    launch_background_steam_artwork(appid, game_name)

    return {
        "ok": True,
        "name": game_name,
        "appid": int(appid),
        "files_dir": str(files_dir),
        "final_exe": str(final_exe),
        "storage_mode": requested_mode,
        "shortcut_state": "pending_steam_restart" if commit.get("pending") else "ready",
        "steam_restarted": False,
    }


def _iso_log(message):
    try:
        with open(ISO_INSTALL_LOG, "a", encoding="utf-8") as log:
            log.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}\n")
    except Exception:
        pass


def _pid_alive(pid):
    """Return True only for a live, non-zombie process.

    V7.4.23 used kill(pid, 0), which also succeeds for a zombie. ISO installs
    keep the launcher helper alive while the installer runs, so an exited
    Proton child can briefly remain as Z until its parent reaps it. Treating Z
    as alive made the separate Steam watcher wait forever after setup.exe was
    closed, preventing game-EXE detection, artwork and shortcut creation.
    """
    try:
        pid = int(pid)
    except Exception:
        return False
    if pid <= 1:
        return False
    try:
        stat_text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="replace")
        tail = stat_text.rsplit(") ", 1)[1]
        state = tail.split(None, 1)[0] if tail else ""
        if state in {"Z", "X", "x"}:
            return False
    except FileNotFoundError:
        return False
    except Exception:
        pass
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, ValueError):
        return False
    except PermissionError:
        return True
    except Exception:
        return False


def _stream_find_iso_images(files_text):
    root = Path(str(files_text or "")).expanduser().resolve()
    if not root.is_dir():
        return []
    found = []
    try:
        for current, dirs, files in os.walk(root):
            # Avoid pathological archive trees while still finding normal nested Disc/ISO folders.
            try:
                depth = len(Path(current).relative_to(root).parts)
            except Exception:
                depth = 0
            if depth > 10:
                dirs[:] = []
                continue
            for filename in files:
                if filename.casefold().endswith(".iso"):
                    path = Path(current) / filename
                    try:
                        size = path.stat().st_size
                    except OSError:
                        size = 0
                    found.append((int(size), path.resolve()))
    except Exception:
        return []

    def rank(item):
        size, path = item
        name = path.name.casefold()
        score = min(int(size // (1024 * 1024)), 500000)
        if re.search(r"(?:disc|disk|cd)[ _.-]*1\b", name):
            score += 2_000_000
        if re.search(r"(?:disc|disk|cd)[ _.-]*(?:2|3|4|5)\b", name):
            score -= 2_000_000
        if "install" in name or "setup" in name:
            score += 200_000
        return (-score, len(str(path)), str(path).casefold())

    found.sort(key=rank)
    return [path for _size, path in found]


def _stream_iso_detect(files_text):
    images = _stream_find_iso_images(files_text)
    return {
        "ok": True,
        "found": bool(images),
        "count": len(images),
        "iso": str(images[0]) if images else "",
        "isos": [str(x) for x in images[:12]],
    }


def _choose_stream_iso(files_text):
    images = _stream_find_iso_images(files_text)
    if not images:
        return None
    if len(images) == 1:
        return images[0]

    # Multi-disc sets: prefer Disc/Disk/CD 1 automatically. Otherwise ask.
    for path in images:
        if re.search(r"(?:disc|disk|cd)[ _.-]*1\b", path.name.casefold()):
            return path

    args = ["--title", "Moses OneClick — Installer ISO", "--menu", "More than one ISO was found. Which disc contains the installer?"]
    for path in images[:12]:
        try:
            size = _human_size(path.stat().st_size)
        except Exception:
            size = ""
        label = f"{path.name}  —  {size}" if size else path.name
        args.extend([str(path), label])
    choice = dialog(args)
    return Path(choice).expanduser().resolve() if choice else None


def _decode_mount_path(value):
    """Decode util-linux escaped mount paths such as ``Sonic\040Mania``."""
    text = str(value or "").strip().strip("'\"")
    if not text:
        return ""
    # findmnt's text modes may escape spaces/tabs/newlines/backslashes using
    # octal sequences.  JSON output normally avoids this, but keep a fallback
    # for older SteamOS/util-linux builds.
    octal = {"040": " ", "011": "\t", "012": "\n", "134": "\\"}
    text = re.sub(r"\\(040|011|012|134)", lambda m: octal.get(m.group(1), m.group(0)), text)
    text = text.replace(r"\x20", " ")
    return text


def _findmnt_target_for_device(device):
    device = str(device or "").strip()
    if not device:
        return ""

    # Prefer structured JSON so labels/mount folders containing spaces are not
    # returned as util-linux escape sequences (the V7.4.21 Sonic Mania bug).
    try:
        result = subprocess.run(
            ["findmnt", "-J", "-S", device, "-o", "TARGET"],
            text=True, capture_output=True, timeout=5, check=False,
        )
        if result.returncode == 0 and (result.stdout or "").strip():
            payload = json.loads(result.stdout)
            for item in payload.get("filesystems") or []:
                target = _decode_mount_path(item.get("target"))
                if target:
                    return target
    except Exception:
        pass

    # lsblk JSON is a second independent source and also preserves spaces.
    try:
        result = subprocess.run(
            ["lsblk", "-J", "-o", "PATH,MOUNTPOINTS", device],
            text=True, capture_output=True, timeout=5, check=False,
        )
        if result.returncode == 0 and (result.stdout or "").strip():
            payload = json.loads(result.stdout)
            wanted = os.path.realpath(device)

            def walk(nodes):
                for node in nodes or []:
                    path = str(node.get("path") or "")
                    mounts = node.get("mountpoints") or []
                    if isinstance(mounts, str):
                        mounts = [mounts]
                    if not wanted or os.path.realpath(path) == wanted:
                        for mount in mounts:
                            target = _decode_mount_path(mount)
                            if target:
                                return target
                    found = walk(node.get("children") or [])
                    if found:
                        return found
                return ""

            target = walk(payload.get("blockdevices") or [])
            if target:
                return target
    except Exception:
        pass

    # Compatibility fallback for older findmnt builds.
    try:
        result = subprocess.run(
            ["findmnt", "-nr", "-S", device, "-o", "TARGET"],
            text=True, capture_output=True, timeout=5, check=False,
        )
        lines = (result.stdout or "").splitlines()
        if result.returncode == 0 and lines:
            return _decode_mount_path(lines[0])
    except Exception:
        pass
    return ""


def _mount_target_from_udisks_text(text):
    """Best-effort target extraction from UDisks success/AlreadyMounted text."""
    raw = str(text or "").strip()
    if not raw:
        return ""
    # Examples:
    #   Mounted /dev/loop0 at /run/media/deck/Sonic Mania.
    #   Device /dev/loop0 is already mounted at `/run/media/deck/Sonic Mania'.
    patterns = (
        r"already mounted at\s+[`'\"]?(.+?)[`'\"]?\.?$",
        r"\bmounted\s+.+?\s+at\s+[`'\"]?(.+?)[`'\"]?\.?$",
        r"\bat\s+[`'\"]?(.+?)[`'\"]?\.?$",
    )
    for line in reversed(raw.splitlines()):
        line = line.strip()
        for pattern in patterns:
            match = re.search(pattern, line, flags=re.IGNORECASE)
            if match:
                target = _decode_mount_path(match.group(1)).rstrip(".")
                if target:
                    return target
    return ""


def _loop_mount_candidates(loop_device):
    candidates = []
    try:
        result = subprocess.run(
            ["lsblk", "-lnpo", "NAME,TYPE", str(loop_device)],
            text=True, capture_output=True, timeout=5, check=False,
        )
        for line in (result.stdout or "").splitlines():
            parts = line.strip().split(None, 1)
            if not parts:
                continue
            name = parts[0]
            typ = parts[1].strip().casefold() if len(parts) > 1 else ""
            if typ in {"part", "rom"} and name not in candidates:
                candidates.append(name)
        if str(loop_device) not in candidates:
            candidates.append(str(loop_device))
    except Exception:
        candidates = [str(loop_device)]
    return candidates


def _existing_read_only_loop_for_iso(iso):
    """Return an existing read-only loop device backed by this ISO, if any."""
    losetup = shutil.which("losetup")
    if not losetup:
        return ""
    try:
        result = subprocess.run(
            [losetup, "-j", str(iso)],
            text=True, capture_output=True, timeout=8, check=False,
        )
        if result.returncode != 0:
            return ""
        for line in (result.stdout or "").splitlines():
            match = re.match(r"\s*(/dev/loop\d+)\s*:", line)
            if not match:
                continue
            device = match.group(1)
            try:
                ro = subprocess.run(
                    ["lsblk", "-dnro", "RO", device],
                    text=True, capture_output=True, timeout=5, check=False,
                )
                if ro.returncode == 0 and (ro.stdout or "").strip().splitlines()[:1] == ["1"]:
                    return device
            except Exception:
                continue
    except Exception:
        pass
    return ""


def _mount_iso_read_only(iso_path):
    iso = Path(str(iso_path)).expanduser().resolve()
    if not iso.is_file() or iso.suffix.casefold() != ".iso":
        raise RuntimeError(f"ISO file was not found: {iso}")
    udisks = shutil.which("udisksctl")
    if not udisks:
        raise RuntimeError(
            "SteamOS' udisksctl command was not found, so OneClick cannot mount the ISO safely."
        )

    # Recover a loop left behind by V7.4.21's false mount failure. The ISO may
    # already be correctly mounted even though the old GUI said it failed.
    loop_device = _existing_read_only_loop_for_iso(iso)
    if loop_device:
        _iso_log(f"Reusing existing read-only loop for ISO: {iso} -> {loop_device}")
    else:
        setup = subprocess.run(
            [udisks, "loop-setup", "--read-only", "--file", str(iso)],
            text=True, capture_output=True, timeout=90, check=False,
        )
        detail = ((setup.stdout or "") + "\n" + (setup.stderr or "")).strip()
        if setup.returncode != 0:
            raise RuntimeError(detail or "Could not create a read-only loop device for the ISO.")
        match = re.search(r"(/dev/loop\d+)", detail)
        if not match:
            raise RuntimeError("The ISO was attached, but OneClick could not determine its loop device.")
        loop_device = match.group(1)
    # Give udev a brief chance to expose partition children for hybrid/UDF ISOs.
    try:
        udevadm = shutil.which("udevadm")
        if udevadm:
            subprocess.run([udevadm, "settle", "--timeout=5"], timeout=7, check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

    errors = []
    for device in _loop_mount_candidates(loop_device):
        # SteamOS/KDE may auto-mount a freshly-created UDisks loop device. Give
        # that race a short chance to settle before issuing our own mount call.
        for _ in range(8):
            target = _findmnt_target_for_device(device)
            if target and Path(target).is_dir():
                _iso_log(f"ISO already mounted: {iso} -> {device} -> {target}")
                return {"iso": str(iso), "loop_device": loop_device, "mount_device": device, "mountpoint": target}
            time.sleep(0.10)

        for with_ro in (True, False):
            args = [udisks, "mount", "--block-device", device]
            # The backing loop itself is always read-only. Explicit ro is tried
            # first; fallback without -o handles UDisks builds that reject the
            # redundant option while remaining read-only at block level.
            if with_ro:
                args.extend(["--options", "ro"])
            mounted = subprocess.run(args, text=True, capture_output=True, timeout=90, check=False)
            text = ((mounted.stdout or "") + "\n" + (mounted.stderr or "")).strip()

            # Critical V7.4.22 fix: a successful UDisks mount can be followed by
            # an AlreadyMounted response if KDE/UDisks wins the race, and older
            # findmnt text output escaped spaces as \040. Re-query the real
            # mount state regardless of return code and accept AlreadyMounted as
            # success instead of trying a second mount and reporting a failure.
            for _ in range(20):
                target = _findmnt_target_for_device(device)
                if not target:
                    target = _mount_target_from_udisks_text(text)
                if target and Path(target).is_dir():
                    _iso_log(f"Mounted read-only ISO: {iso} -> {device} -> {target}")
                    return {"iso": str(iso), "loop_device": loop_device, "mount_device": device, "mountpoint": target}
                time.sleep(0.10)

            errors.append(text or f"Could not mount {device}.")
            if "alreadymounted" in text.casefold() or "already mounted" in text.casefold():
                # Do not issue another mount attempt after UDisks explicitly said
                # it is mounted. One final kernel query is safer and avoids the
                # misleading duplicate AlreadyMounted error seen in V7.4.21.
                target = _findmnt_target_for_device(device) or _mount_target_from_udisks_text(text)
                if target:
                    _iso_log(f"UDisks reported AlreadyMounted: {iso} -> {device} -> {target}")
                    return {"iso": str(iso), "loop_device": loop_device, "mount_device": device, "mountpoint": target}
                break

    # Never detach a loop device that is actually mounted just because one
    # userspace query failed. If any candidate has a mount point, return it.
    for device in _loop_mount_candidates(loop_device):
        target = _findmnt_target_for_device(device)
        if target:
            _iso_log(f"ISO mount recovered after UDisks race: {iso} -> {device} -> {target}")
            return {"iso": str(iso), "loop_device": loop_device, "mount_device": device, "mountpoint": target}

    try:
        subprocess.run([udisks, "loop-delete", "--block-device", loop_device], timeout=30, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    raise RuntimeError("Could not mount the ISO filesystem.\n\n" + "\n".join(x for x in errors[-3:] if x))


def _unmount_iso(loop_device, mount_device):
    udisks = shutil.which("udisksctl")
    if not udisks:
        return False, "udisksctl is unavailable"
    mount_device = str(mount_device or loop_device or "").strip()
    loop_device = str(loop_device or "").strip()
    errors = []
    if mount_device and _findmnt_target_for_device(mount_device):
        result = subprocess.run(
            [udisks, "unmount", "--block-device", mount_device],
            text=True, capture_output=True, timeout=60, check=False,
        )
        if result.returncode != 0:
            errors.append((result.stderr or result.stdout or "Could not unmount ISO").strip())
            return False, "\n".join(errors)
    if loop_device and Path(loop_device).exists():
        result = subprocess.run(
            [udisks, "loop-delete", "--block-device", loop_device],
            text=True, capture_output=True, timeout=60, check=False,
        )
        if result.returncode != 0:
            errors.append((result.stderr or result.stdout or "Could not detach ISO loop device").strip())
            return False, "\n".join(errors)
    return True, ""


def _path_is_inside(path, root):
    try:
        Path(path).resolve(strict=False).relative_to(Path(root).resolve(strict=False))
        return True
    except Exception:
        return False


def _mount_path_in_use(mountpoint):
    root = Path(str(mountpoint)).resolve(strict=False)
    fuser = shutil.which("fuser")
    if fuser:
        try:
            result = subprocess.run(
                [fuser, "-m", str(root)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=8, check=False,
            )
            return result.returncode == 0
        except Exception:
            pass

    # Fallback for SteamOS images without fuser: inspect cwd/exe/open fds in /proc.
    try:
        proc_entries = list(Path("/proc").iterdir())
    except Exception:
        return False
    own = os.getpid()
    for item in proc_entries:
        if not item.name.isdigit() or int(item.name) == own:
            continue
        try:
            for linkname in ("cwd", "exe"):
                try:
                    target = os.readlink(item / linkname)
                    if _path_is_inside(target, root):
                        return True
                except Exception:
                    pass
            fd_dir = item / "fd"
            try:
                for fd in fd_dir.iterdir():
                    try:
                        target = os.readlink(fd)
                        if _path_is_inside(target, root):
                            return True
                    except Exception:
                        continue
            except Exception:
                pass
        except Exception:
            continue
    return False


def _wait_mount_idle(mountpoint, timeout=10 * 60, quiet_seconds=8):
    deadline = time.time() + float(timeout)
    quiet_since = None
    while time.time() < deadline:
        if _mount_path_in_use(mountpoint):
            quiet_since = None
        else:
            if quiet_since is None:
                quiet_since = time.time()
            elif time.time() - quiet_since >= float(quiet_seconds):
                return True
        time.sleep(1.0)
    return not _mount_path_in_use(mountpoint)


def _select_iso_installer(mountpoint, iso_path):
    root = Path(str(mountpoint)).expanduser().resolve()
    iso = Path(str(iso_path)).expanduser().resolve()
    suggested = _smart_title_case(_clean_installer_name(iso.stem) or iso.stem)
    candidates = _scan_game_folder_exes(root, suggested, limit=24, purpose="install")
    if not candidates:
        return None

    best_score, best = candidates[0]
    second_score = candidates[1][0] if len(candidates) > 1 else -9999
    best_name = best.stem.casefold()
    obvious_name = (
        best_name in {"setup", "install", "installer", "autorun"}
        or best_name.startswith(("setup", "install"))
    )
    # Common disc layouts should go straight to the existing Game Installer
    # window without making the user pick setup.exe first. Ambiguous discs keep
    # the normal EXE chooser as a safe fallback.
    if len(candidates) == 1 or (obvious_name and best_score >= 120 and best_score - second_score >= 35):
        return {
            "exe": str(best),
            "name": _suggest_game_name_for_candidate(root, best, suggested),
            "auto_selected": True,
        }
    picked = choose_game_exe_from_folder(root, suggested_name=suggested, purpose="install")
    if picked:
        picked["auto_selected"] = False
    return picked


def _iso_session_file(session_id):
    safe = re.sub(r"[^a-zA-Z0-9_.-]+", "-", str(session_id or "")).strip("-")
    return ISO_SESSION_DIR / f"{safe or 'session'}.json"


def _write_iso_session(session_key, **updates):
    path = _iso_session_file(session_key)
    data = {}
    try:
        if path.is_file():
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                data = {}
    except Exception:
        data = {}
    data.update(updates)
    data["updated_at"] = int(time.time())
    try:
        temp = path.with_suffix(".json.tmp")
        temp.write_text(json.dumps(data, indent=2), encoding="utf-8")
        temp.replace(path)
    except Exception:
        pass
    return data


def _read_iso_session(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _stream_iso_cleanup_stale_sessions(force=False):
    cleaned = []
    skipped = []
    for marker in ISO_SESSION_DIR.glob("*.json"):
        data = _read_iso_session(marker)
        manager_pid = int(data.get("manager_pid") or 0)
        mountpoint = str(data.get("mountpoint") or "")
        if not force and manager_pid and _pid_alive(manager_pid):
            skipped.append(marker.name)
            continue
        if not force and mountpoint and _mount_path_in_use(mountpoint):
            skipped.append(marker.name)
            continue
        ok, detail = _unmount_iso(data.get("loop_device"), data.get("mount_device"))
        if ok:
            try:
                marker.unlink(missing_ok=True)
            except Exception:
                pass
            cleaned.append(marker.name)
        else:
            skipped.append(f"{marker.name}: {detail}")
    return {"ok": True, "cleaned": cleaned, "skipped": skipped}


def _reap_child_if_exited(pid):
    """Best-effort reap for a child owned by this helper; never blocks."""
    try:
        pid = int(pid or 0)
    except Exception:
        return False
    if pid <= 1:
        return False
    try:
        waited, _status = os.waitpid(pid, os.WNOHANG)
        return waited == pid
    except ChildProcessError:
        return False
    except Exception:
        return False


def _wait_iso_install_result(result, mountpoint, max_runtime=12 * 60 * 60):
    if not isinstance(result, dict) or not result.get("launched"):
        return False, "Installer was not launched."
    if result.get("completed"):
        return bool(result.get("ok", True)), str(result.get("detail") or "completed")
    backend = str(result.get("backend") or "").strip().lower()
    deadline = time.time() + int(max_runtime)

    if backend == "steam":
        appid = int(result.get("appid") or 0)
        started_at = int(result.get("started_at") or 0)
        launcher_pid = int(result.get("launcher_pid") or 0)
        launcher_reaped = False
        while time.time() < deadline:
            # The ISO manager owns the direct Proton Popen and remains alive.
            # Reap an exited launcher so it cannot remain a zombie and make the
            # separate Steam watcher think installation is still running.
            if launcher_pid and not launcher_reaped:
                launcher_reaped = _reap_child_if_exited(launcher_pid)
                if launcher_reaped:
                    _iso_log(f"Reaped completed Proton launcher PID {launcher_pid} for AppID {appid}")
            entry = load_steam_registry().get(str(appid)) or {}
            status = str(entry.get("status") or "")
            try:
                same_generation = int(entry.get("created_at") or 0) == started_at
            except Exception:
                same_generation = False
            if same_generation and status in {"pending_followup", "pending_steam", "installed", "detached"}:
                return True, status
            if same_generation and (status.startswith("install_failed") or status == "removed"):
                return False, status
            time.sleep(1.0)
        return False, "Installer timed out."

    if backend in {"lutris", "smart"}:
        prefix = str(result.get("config_prefix") or "")
        game_name = str(result.get("game_name") or "")
        min_game_id = int(result.get("min_game_id") or 0)
        seen_use = False
        idle_since = None
        launched_at = time.time()
        while time.time() < deadline:
            try:
                match = find_completed_install(prefix, game_name, min_game_id)
            except Exception:
                match = None
            if match:
                return True, "installed"
            busy = _mount_path_in_use(mountpoint)
            if busy:
                seen_use = True
                idle_since = None
            elif seen_use:
                if idle_since is None:
                    idle_since = time.time()
                elif time.time() - idle_since >= 90:
                    return False, "Installer closed before Lutris marked the game installed."
            elif time.time() - launched_at >= 5 * 60:
                return False, "Installer never started from the mounted ISO."
            time.sleep(3.0)
        return False, "Installer timed out."

    # Update/fallback mode: keep the disc until it has actually been used and
    # then becomes idle for a conservative period.
    seen_use = False
    idle_since = None
    while time.time() < deadline:
        busy = _mount_path_in_use(mountpoint)
        if busy:
            seen_use = True
            idle_since = None
        elif seen_use:
            if idle_since is None:
                idle_since = time.time()
            elif time.time() - idle_since >= 120:
                return True, "source-idle"
        time.sleep(2.0)
    return False, "Installer timed out."


def _read_stream_complete_marker(prefix_dir):
    try:
        data = json.loads((Path(prefix_dir) / STREAM_COMPLETE_MARKER).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _verified_stream_staging_source(files_text, iso_path):
    files_dir = Path(str(files_text or "")).expanduser().resolve(strict=False)
    iso = Path(str(iso_path or "")).expanduser().resolve(strict=False)
    prefix = files_dir.parent
    if files_dir.name != "Files" or not prefix.name.startswith(".streamextract-"):
        return None
    if not _stream_prefix_path_is_allowed(prefix) or not _path_is_inside(iso, files_dir):
        return None
    marker = _read_stream_complete_marker(prefix)
    if (
        not marker
        or str(marker.get("owner") or "") != "moses-streamextract"
        or str(marker.get("status") or "") != "complete"
    ):
        return None
    return prefix


def _read_stream_batch_manifest(files_text):
    files_dir = Path(str(files_text or "")).expanduser().resolve(strict=False)
    marker = files_dir / ".streamextract-batch.json"
    if not marker.is_file():
        return {}
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
    except Exception:
        return {}
    if not isinstance(data, dict) or str(data.get("mode") or "") != "mixed-multilink":
        return {}
    extras = []
    for item in data.get("extras") or []:
        if not isinstance(item, dict):
            continue
        rel = str(item.get("path") or "").strip()
        if not rel:
            continue
        candidate = (files_dir / rel).resolve(strict=False)
        if not _path_is_inside(candidate, files_dir):
            continue
        # Follow-up payloads are intentionally isolated under this folder by
        # StreamExtract so they cannot overwrite the primary ISO/source tree.
        try:
            rel_parts = candidate.relative_to(files_dir).parts
        except Exception:
            continue
        if not rel_parts or rel_parts[0] != "_StreamExtract Follow-up":
            continue
        if candidate.exists():
            extras.append({"name": str(item.get("name") or candidate.name), "path": candidate})
    if not extras:
        return {}
    return {"data": data, "extras": extras, "marker": marker, "files_dir": files_dir}


def _preserve_stream_followups(files_text, iso_path, game_name):
    """Move unused independent archives out before deleting the large base ISO.

    This is deliberately conservative: the base installer source may be deleted
    after a successful install, but an independent update/patch archive has not
    been consumed yet and must never disappear just because Keep source was off.
    """
    prefix = _verified_stream_staging_source(files_text, iso_path)
    manifest = _read_stream_batch_manifest(files_text)
    if prefix is None or not manifest:
        return {"ok": False, "found": False, "error": "No verified follow-up batch was found."}

    extras = list(manifest.get("extras") or [])
    if not extras:
        return {"ok": False, "found": False, "error": "No follow-up installer files were found."}

    safe_game = _safe_filename(game_name or Path(str(iso_path or "Installer")).stem).replace("-", " ").strip() or "Game"
    parent = prefix.parent
    dest = parent / f"{safe_game} - Follow-up Installers"
    suffix = 2
    while dest.exists():
        dest = parent / f"{safe_game} - Follow-up Installers ({suffix})"
        suffix += 1

    moved = []
    try:
        dest.mkdir(parents=True, exist_ok=False)
        for item in extras:
            source = Path(item["path"])
            target = dest / source.name
            target_suffix = 2
            while target.exists():
                target = dest / f"{source.name} ({target_suffix})"
                target_suffix += 1
            shutil.move(str(source), str(target))
            moved.append(str(target))

        # The independent follow-ups are now safely outside the temporary
        # StreamExtract prefix. Remove the entire consumed base source (ISO and
        # any companion files) to get the same space-saving result as normal.
        size = _directory_size(prefix)
        shutil.rmtree(prefix)
        return {
            "ok": True, "found": True, "path": str(dest), "count": len(moved),
            "moved": moved, "removed_base_bytes": int(size),
        }
    except Exception as exc:
        # Never delete the source tree if preservation did not complete. Some
        # items may already have moved, but both locations are kept and reported.
        return {
            "ok": False, "found": True, "path": str(dest) if dest.exists() else "",
            "count": len(moved), "moved": moved, "error": str(exc),
        }


def _delete_stream_iso_source_tree(files_text, iso_path):
    """Delete only a verified completed StreamExtract staging source tree."""
    prefix = _verified_stream_staging_source(files_text, iso_path)
    if prefix is None:
        return False, "Source folder was not a verified completed StreamExtract staging folder."
    try:
        size = _directory_size(prefix)
        shutil.rmtree(prefix)
        return True, f"Removed {size} bytes of extracted installer source files."
    except Exception as exc:
        return False, str(exc)


def _cleanup_empty_stream_iso_source(files_text, iso_path):
    files_dir = Path(str(files_text or "")).expanduser().resolve(strict=False)
    iso = Path(str(iso_path or "")).expanduser().resolve(strict=False)
    if not files_dir.is_dir() or not _path_is_inside(iso, files_dir):
        return False
    # Remove empty directories created around the ISO, but never delete any
    # other extracted file. If Files becomes empty and its parent is a verified
    # StreamExtract staging prefix, remove that empty staging prefix too.
    try:
        for root, dirs, files in os.walk(files_dir, topdown=False):
            path = Path(root)
            if files:
                continue
            try:
                path.rmdir()
            except OSError:
                pass
    except Exception:
        return False
    prefix = files_dir.parent
    if files_dir.exists():
        return False
    if _verified_stream_staging_source(files_dir, iso) is None:
        return False
    try:
        shutil.rmtree(prefix)
        return True
    except Exception:
        return False



def _followup_version_tuple(value):
    try:
        parts = tuple(int(part) for part in str(value or "").split(".") if part != "")
    except Exception:
        return ()
    if not parts:
        return ()
    # Treat 1.16 and 1.16.0 as the same boundary when connecting patch steps.
    parts = list(parts)
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def _followup_version_sort_key(value):
    value = tuple(value or ())
    return tuple(value[:8]) + (0,) * max(0, 8 - len(value))


def _followup_version_text(value):
    return ".".join(str(part) for part in tuple(value or ()))


def _followup_versions_from_text(value):
    # Dotted semantic/game versions only. A bare year/build number is not enough
    # to drive an automatic chain. This intentionally understands filenames such
    # as "update 1.12.0 - 1.16.0.exe" and "Patch_v1.16.0_to_v1.16.1.exe".
    found = re.findall(
        r"(?i)(?<!\d)(?:v(?:er(?:sion)?)?[\s._-]*)?(\d+(?:\.\d+){1,5})(?!\d)",
        str(value or ""),
    )
    out = []
    for item in found:
        version = _followup_version_tuple(item)
        if version and version not in out:
            out.append(version)
    return out


def _followup_version_info(exe, folder):
    exe = Path(str(exe or "")).expanduser().resolve(strict=False)
    folder = Path(str(folder or "")).expanduser().resolve(strict=False)
    # Prefer the EXE filename itself. If a package uses generic setup.exe files,
    # fall back to the relative path so an enclosing "Update 1.2 - 1.3" folder
    # can still provide the ordering information.
    texts = [exe.stem]
    try:
        rel = exe.relative_to(folder)
        texts.append(str(rel.parent))
        texts.append(str(rel))
    except Exception:
        pass
    for value in texts:
        versions = _followup_versions_from_text(value)
        if len(versions) >= 2:
            return {
                "start": versions[0], "end": versions[1],
                "versions": versions, "range": True,
            }
    for value in texts:
        versions = _followup_versions_from_text(value)
        if versions:
            return {
                "start": versions[0], "end": (),
                "versions": versions, "range": False,
            }
    return {"start": (), "end": (), "versions": [], "range": False}


def _followup_candidate_looks_update(exe, folder):
    exe = Path(str(exe or "")).expanduser().resolve(strict=False)
    folder = Path(str(folder or "")).expanduser().resolve(strict=False)
    low = exe.stem.casefold()
    if any(word in low for word in ("unins", "uninstall", "redist", "dxsetup", "vcredist", "crash", "report")):
        return False
    if _looks_like_update_exe(exe):
        return True
    info = _followup_version_info(exe, folder)
    if info.get("range"):
        return True
    try:
        rel_text = str(exe.relative_to(folder)).casefold().replace("_", " ").replace("-", " ")
    except Exception:
        rel_text = str(exe).casefold().replace("_", " ").replace("-", " ")
    package_text = (folder.name + " " + rel_text).casefold().replace("_", " ").replace("-", " ")
    return bool(re.search(
        r"(?:^|[^a-z])(update|patch|hotfix|upgrade|fixpack|title[ ._-]*update)(?:\d|[^a-z]|$)",
        package_text,
    ))


def _ordered_stream_followup_exes(folder, game_name=""):
    """Return a safe, deterministic update plan for one follow-up source.

    Multiple explicit version-range patchers are chained by matching each
    destination version to the next source version. When a branch exists, the
    smallest forward step wins so incremental patches are applied naturally.
    Anything disconnected/ambiguous is left unresolved and therefore preserved.
    """
    folder = Path(str(folder or "")).expanduser().resolve(strict=False)
    if not folder.is_dir():
        return {"steps": [], "unresolved": [], "reason": "missing-folder"}

    candidates = _scan_game_folder_exes(folder, str(game_name or ""), limit=96, purpose="install")
    if not candidates:
        return {"steps": [], "unresolved": [], "reason": "no-exes"}

    explicit = []
    generic = []
    seen = set()
    for score, path in candidates:
        path = Path(path).expanduser().resolve(strict=False)
        key = str(path)
        if key in seen or not path.is_file():
            continue
        seen.add(key)
        info = _followup_version_info(path, folder)
        item = {"path": path, "score": int(score), "info": info}
        if _followup_candidate_looks_update(path, folder):
            explicit.append(item)
        else:
            generic.append(item)

    pool = explicit
    if not pool:
        # Preserve the old safe generic setup fallback, but do not open the EXE
        # chooser merely because several unrelated helpers exist in the package.
        ranked = generic
        if not ranked:
            return {"steps": [], "unresolved": [], "reason": "no-update-exe"}
        ranked.sort(key=lambda item: (-item["score"], len(str(item["path"]))))
        if len(ranked) == 1:
            return {"steps": [ranked[0]["path"]], "unresolved": [], "reason": "single-generic"}
        top = ranked[0]
        second = ranked[1]
        low = top["path"].stem.casefold()
        if (low in {"setup", "install", "installer"} or low.startswith(("setup", "install"))) and top["score"] - second["score"] >= 30:
            return {"steps": [top["path"]], "unresolved": [], "reason": "obvious-generic"}
        return {"steps": [], "unresolved": [item["path"] for item in ranked], "reason": "ambiguous-generic"}

    # A single recognized updater is straightforward.
    if len(pool) == 1:
        return {"steps": [pool[0]["path"]], "unresolved": [], "reason": "single-update"}

    ranged = [item for item in pool if item["info"].get("start") and item["info"].get("end")]
    nonranged = [item for item in pool if item not in ranged]

    if ranged:
        unused = list(ranged)
        # The lowest source version is the natural first prerequisite. If two
        # patchers start there (incremental + cumulative), pick the smallest
        # forward destination and leave the alternate untouched for safety.
        first_start = min((item["info"]["start"] for item in unused), key=_followup_version_sort_key)
        current = first_start
        chain = []
        while True:
            options = [
                item for item in unused
                if item["info"]["start"] == current
                and _followup_version_sort_key(item["info"]["end"]) > _followup_version_sort_key(current)
            ]
            if not options:
                break
            options.sort(key=lambda item: (
                _followup_version_sort_key(item["info"]["end"]),
                -item["score"], len(str(item["path"])), str(item["path"]).casefold(),
            ))
            chosen = options[0]
            chain.append(chosen)
            unused.remove(chosen)
            current = chosen["info"]["end"]

        # If only one range step was connectable but there are other ranges,
        # sorting and blindly running them could skip a required prerequisite.
        # Keep those unresolved instead. For a genuinely connected chain (2+),
        # append single-version update EXEs only when they are newer than the
        # reached destination; these are common "Update 1.17.1.exe" packages.
        unresolved = list(unused)
        if len(chain) >= 2:
            singles = [item for item in nonranged if item["info"].get("start")]
            singles.sort(key=lambda item: (
                _followup_version_sort_key(item["info"]["start"]),
                -item["score"], str(item["path"]).casefold(),
            ))
            for item in singles:
                if _followup_version_sort_key(item["info"]["start"]) > _followup_version_sort_key(current):
                    chain.append(item)
                    current = item["info"]["start"]
                else:
                    unresolved.append(item)
            unresolved.extend(item for item in nonranged if item not in singles)
        else:
            unresolved.extend(nonranged)

        if chain:
            return {
                "steps": [item["path"] for item in chain],
                "unresolved": [item["path"] for item in unresolved],
                "reason": "version-range-chain",
                "start_version": _followup_version_text(first_start),
                "end_version": _followup_version_text(current),
            }

    # No usable range chain: ordered single-version patchers are still safe when
    # every recognized updater carries a distinct dotted version. Otherwise the
    # source is ambiguous and is preserved for manual inspection.
    versioned = [item for item in pool if item["info"].get("start")]
    if len(versioned) == len(pool):
        versioned.sort(key=lambda item: (
            _followup_version_sort_key(item["info"]["start"]),
            -item["score"], str(item["path"]).casefold(),
        ))
        versions = [item["info"]["start"] for item in versioned]
        if len(set(versions)) == len(versions):
            return {"steps": [item["path"] for item in versioned], "unresolved": [], "reason": "version-sorted"}

    # Last conservative fallback: choose one very obvious updater only if it is
    # clearly better than every other candidate. Never show Find Game EXE here;
    # ambiguous multi-update packages must not depend on a manual first pick.
    pool.sort(key=lambda item: (-item["score"], len(str(item["path"]))))
    top = pool[0]
    second = pool[1]
    if top["score"] - second["score"] >= 45:
        return {"steps": [top["path"]], "unresolved": [item["path"] for item in pool[1:]], "reason": "clear-top-update"}
    return {"steps": [], "unresolved": [item["path"] for item in pool], "reason": "ambiguous-updates"}


def _best_stream_followup_exe(folder, game_name=""):
    # Compatibility wrapper for any older call sites. New StreamExtract ISO
    # sessions use the complete ordered plan so they can run every update step.
    plan = _ordered_stream_followup_exes(folder, game_name)
    steps = list(plan.get("steps") or [])
    return Path(steps[0]) if steps else None

def _wait_managed_followup_update(result, max_runtime=12 * 60 * 60):
    if not isinstance(result, dict) or not result.get("launched"):
        return False, "Update/patch was not launched."
    if result.get("completed"):
        return bool(result.get("ok", True)), str(result.get("detail") or "completed")
    backend = str(result.get("backend") or "").strip().lower()
    if backend == "steam-update":
        pid = int(result.get("launcher_pid") or 0)
        deadline = time.time() + int(max_runtime)
        exit_code = None
        while time.time() < deadline:
            if pid <= 1:
                break
            try:
                waited, status = os.waitpid(pid, os.WNOHANG)
                if waited == pid:
                    try:
                        exit_code = os.waitstatus_to_exitcode(status)
                    except Exception:
                        exit_code = 0
                    break
            except ChildProcessError:
                if not _pid_alive(pid):
                    exit_code = 0
                    break
            except Exception:
                if not _pid_alive(pid):
                    exit_code = 0
                    break
            time.sleep(0.5)
        if exit_code is None and pid > 1 and _pid_alive(pid):
            return False, "Update/patch timed out."
        proton_path = str(result.get("proton_path") or "")
        compatdata = str(result.get("compatdata") or "")
        if proton_path and compatdata:
            _wait_wineserver_for_prefix(proton_path, Path(compatdata), timeout=max_runtime)
        if exit_code not in (None, 0):
            log_dir = str(result.get("log_dir") or "")
            return False, f"Update/patch launcher exited with code {exit_code}." + (f" Logs: {log_dir}" if log_dir else "")
        return True, "update-finished"
    # Lutris update helpers are currently blocking and return completed=True.
    # Keep a conservative PID fallback for any future backend that returns one.
    pid = int(result.get("launcher_pid") or 0)
    if pid > 1:
        deadline = time.time() + int(max_runtime)
        while time.time() < deadline and _pid_alive(pid):
            _reap_child_if_exited(pid)
            time.sleep(0.5)
        if _pid_alive(pid):
            return False, "Update/patch timed out."
        return True, "update-finished"
    return bool(result.get("ok", True)), str(result.get("detail") or "update-finished")


def _stream_update_target_from_base_result(result):
    if not isinstance(result, dict):
        return {}
    backend = str(result.get("backend") or "").strip().lower()
    if backend == "steam" and result.get("appid") is not None:
        return {"backend": "steam", "appid": int(result.get("appid"))}
    if backend in {"lutris", "smart"} and result.get("game_id") is not None:
        return {"backend": "lutris", "game_id": str(result.get("game_id"))}
    return {}


def _finalize_deferred_stream_steam(result):
    if not isinstance(result, dict) or str(result.get("backend") or "").strip().lower() != "steam":
        return {"ok": True, "needed": False}
    appid = int(result.get("appid") or 0)
    if appid <= 0:
        return {"ok": False, "needed": True, "error": "The Steam AppID for the completed installation was missing."}
    entry = load_steam_registry().get(str(appid)) or {}
    final_text = str(entry.get("final_exe") or "").strip()
    if not final_text or not Path(final_text).is_file():
        return {"ok": False, "needed": True, "error": "The installed game's final EXE could not be found before Steam finalization."}
    game_name = str(entry.get("name") or result.get("game_name") or appid)
    update_steam_registry_entry(
        appid, status="pending_steam", defer_post_install_finalize=False,
        auto_finalize_shortcut=True, artwork_pending=True, updated_at=int(time.time()),
    )
    commit = _commit_steam_shortcut_reliably(appid, game_name, Path(final_text), str(entry.get("icon") or ""))
    launch_background_steam_artwork(appid, game_name)
    if commit.get("ok"):
        return {"ok": True, "needed": True, "commit": commit}
    update_steam_registry_entry(appid, status="pending_steam", updated_at=int(time.time()))
    launch_deferred_steam_finalizer(appid)
    return {
        "ok": False, "needed": True,
        "error": str(commit.get("error") or "Steam shortcut was queued for the next clean Steam restart."),
        "queued": True,
    }


def _remove_consumed_followup_folder(path, files_dir):
    path = Path(str(path or "")).expanduser().resolve(strict=False)
    root = Path(str(files_dir or "")).expanduser().resolve(strict=False)
    if not path.is_dir() or not _path_is_inside(path, root):
        return False
    try:
        rel = path.relative_to(root)
        if not rel.parts or rel.parts[0] != "_StreamExtract Follow-up":
            return False
        shutil.rmtree(path)
        return True
    except Exception:
        return False


def _stream_iso_session(session_id):
    marker_path = _iso_session_file(session_id)
    session = _read_iso_session(marker_path)
    iso = Path(str(session.get("iso") or "")).expanduser().resolve()
    mountpoint = str(session.get("mountpoint") or "")
    loop_device = str(session.get("loop_device") or "")
    mount_device = str(session.get("mount_device") or "")
    files_dir = str(session.get("files_dir") or "")
    keep_extracted_source = bool(session.get("keep_extracted_source", True))
    # V7.4.30 also reuses this lifecycle manager for a user double-clicking a
    # standalone .iso in Dolphin.  StreamExtract sessions keep their batch
    # manifest/cleanup semantics; standalone ISOs have no StreamExtract source
    # tree and are never deleted unless the user explicitly checks Delete ISO.
    stream_managed = bool(session.get("stream_managed", True))
    follow_manifest = _read_stream_batch_manifest(files_dir) if stream_managed else {}
    follow_items = list(follow_manifest.get("extras") or []) if follow_manifest else []
    defer_post_finalize = bool(follow_items)
    _write_iso_session(session_id, manager_pid=os.getpid(), status="opening-installer")

    try:
        picked = _select_iso_installer(mountpoint, iso)
        if not picked:
            error(
                "The ISO was mounted successfully, but OneClick could not find a plausible Windows installer EXE.\n\n"
                f"ISO:\n{iso}\n\nThe ISO will be unmounted and kept."
            )
            _write_iso_session(session_id, status="no-installer")
            return
        exe = Path(str(picked.get("exe") or "")).expanduser().resolve()
        if not exe.is_file() or not _path_is_inside(exe, mountpoint):
            error("The selected installer EXE is no longer available inside the mounted ISO.")
            _write_iso_session(session_id, status="invalid-installer")
            return

        _write_iso_session(session_id, status="installer-dialog", installer=str(exe))

        result = handle_new_exe(
            exe, source_iso=str(iso), source_mountpoint=mountpoint,
            suggested_name=str(picked.get("name") or ""),
            stream_keep_extracted_source=(keep_extracted_source if stream_managed else None),
            defer_post_install_finalize=defer_post_finalize,
        )
        if not isinstance(result, dict) or not result.get("launched"):
            _write_iso_session(session_id, status="cancelled")
            return

        delete_iso = bool(result.get("delete_source_iso")) if str(result.get("action") or "") == "install" else False
        _write_iso_session(
            session_id, status="installing", install_result=result,
            delete_after_success=delete_iso, followup_count=len(follow_items),
        )
        success, detail = _wait_iso_install_result(result, mountpoint)
        _write_iso_session(session_id, status="install-finished" if success else "install-failed", result_detail=detail)
        if not success:
            subprocess.run(
                ["kdialog", "--passivepopup", "Installation did not complete successfully. The ISO was kept.", "7"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            return

        # Release the virtual disc before running independent update/patch EXEs.
        # Those follow-up installers live in normal extracted folders and do not
        # need the ISO to remain attached.
        if not _wait_mount_idle(mountpoint, timeout=10 * 60, quiet_seconds=8):
            _write_iso_session(session_id, status="busy-after-install")
            subprocess.run(
                ["kdialog", "--passivepopup", "The game installed successfully, but the ISO is still in use, so OneClick kept it mounted for safety.", "8"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            return

        ok, unmount_error = _unmount_iso(loop_device, mount_device)
        if not ok:
            _write_iso_session(session_id, status="unmount-failed", error=unmount_error)
            error(
                "The game installed successfully, but OneClick could not unmount the ISO safely.\n\n"
                f"{unmount_error}\n\nThe ISO file was NOT deleted."
            )
            return
        # From this point onward the finally block must not attempt a second unmount.
        mountpoint = ""
        loop_device = ""
        mount_device = ""
        _write_iso_session(session_id, mountpoint="", loop_device="", mount_device="")

        used_followups = 0
        skipped_followups = 0
        failed_followups = 0
        target = _stream_update_target_from_base_result(result)
        game_name = str(result.get("game_name") or picked.get("name") or iso.stem)
        stop_update_chain = False
        completed_update_steps = 0

        for source_index, item in enumerate(follow_items, start=1):
            source = Path(item.get("path") or "").expanduser().resolve(strict=False)
            label = str(item.get("name") or source.name or f"Follow-up {source_index}")
            if not source.is_dir():
                continue

            # Only auto-run sources that clearly look like an update/patch. DLC,
            # bonus content and redistributables remain preserved for inspection.
            label_hint = bool(re.search(
                r"(?i)(?:^|[^a-z])(update|patch|hotfix|upgrade|fixpack|title[ ._-]*update)(?:\d|[^a-z]|$)",
                label.replace("_", " ").replace("-", " "),
            ))
            quick_candidates = _scan_game_folder_exes(source, game_name, limit=32, purpose="install")
            exe_hint = any(_looks_like_update_exe(path) for _score, path in quick_candidates)
            version_range_hint = any(_followup_version_info(path, source).get("range") for _score, path in quick_candidates)
            if not (label_hint or exe_hint or version_range_hint):
                skipped_followups += 1
                _iso_log(f"Follow-up source was preserved but not auto-run because it did not look like an update/patch: {label}")
                continue

            if stop_update_chain:
                skipped_followups += 1
                _iso_log(f"Preserving later follow-up source because an earlier update step did not complete: {label}")
                continue

            plan = _ordered_stream_followup_exes(source, game_name)
            follow_exes = [Path(path) for path in (plan.get("steps") or []) if Path(path).is_file()]
            unresolved = [Path(path) for path in (plan.get("unresolved") or []) if Path(path).is_file()]
            if not follow_exes:
                skipped_followups += max(1, len(unresolved))
                error(
                    "A follow-up update/patch source was found, but Moses could not determine a safe automatic update order.\n\n"
                    f"Follow-up:\n{source}\n\nIts files were kept so you can inspect them manually."
                )
                _iso_log(f"No safe automatic update plan for {label}: {plan.get('reason')}; preserved source")
                continue

            if len(follow_exes) > 1:
                ordered_names = " -> ".join(path.name for path in follow_exes)
                _iso_log(
                    f"Detected {len(follow_exes)} ordered update steps in {label} "
                    f"({plan.get('reason')}): {ordered_names}"
                )
            else:
                _iso_log(f"Automatically continuing with detected follow-up update/patch: {follow_exes[0].name}")

            # Unresolved alternatives are deliberately not auto-run. This covers
            # branch/cumulative patchers that could overlap the incremental chain.
            # The containing source is therefore kept after the successful chain.
            if unresolved:
                skipped_followups += len(unresolved)
                _iso_log(
                    "Preserving unresolved/alternate update candidate(s): "
                    + "; ".join(path.name for path in unresolved)
                )

            source_all_steps_ok = True
            for step_in_source, follow_exe in enumerate(follow_exes, start=1):
                if not follow_exe.is_file():
                    source_all_steps_ok = False
                    failed_followups += 1
                    stop_update_chain = True
                    break

                completed_update_steps += 1
                step_label = follow_exe.name
                info = _followup_version_info(follow_exe, source)
                if info.get("start") and info.get("end"):
                    _iso_log(
                        f"Starting update step {step_in_source}/{len(follow_exes)} for {game_name}: "
                        f"{_followup_version_text(info['start'])} -> {_followup_version_text(info['end'])} ({step_label})"
                    )
                else:
                    _iso_log(f"Starting update step {step_in_source}/{len(follow_exes)} for {game_name}: {step_label}")

                _write_iso_session(
                    session_id, status="followup-dialog",
                    followup_index=completed_update_steps,
                    followup_source_index=source_index,
                    followup_source_total=len(follow_items),
                    followup_step=step_in_source,
                    followup_steps_in_source=len(follow_exes),
                    followup_name=step_label,
                    followup_installer=str(follow_exe),
                )
                update_result = handle_new_exe(
                    follow_exe, suggested_name=game_name,
                    preferred_update_target=target, managed_followup=True,
                    force_update_hint=True,
                )
                if not isinstance(update_result, dict) or not update_result.get("launched"):
                    skipped_followups += 1
                    source_all_steps_ok = False
                    stop_update_chain = True
                    _iso_log(f"Follow-up Game Installer was cancelled for update step: {step_label}; later updates were not started")
                    break

                _write_iso_session(
                    session_id, status="followup-installing",
                    followup_index=completed_update_steps,
                    followup_source_index=source_index,
                    followup_source_total=len(follow_items),
                    followup_step=step_in_source,
                    followup_steps_in_source=len(follow_exes),
                    followup_name=step_label,
                )
                update_ok, update_detail = _wait_managed_followup_update(update_result)
                _write_iso_session(
                    session_id, status="followup-finished",
                    followup_index=completed_update_steps,
                    followup_source_index=source_index,
                    followup_source_total=len(follow_items),
                    followup_step=step_in_source,
                    followup_steps_in_source=len(follow_exes),
                    followup_name=step_label,
                    followup_result=update_detail, followup_ok=bool(update_ok),
                )
                if update_ok and str(update_result.get("action") or "").strip().lower() == "update":
                    used_followups += 1
                    _iso_log(f"Follow-up update step completed: {step_label}")
                    continue

                failed_followups += 1
                source_all_steps_ok = False
                stop_update_chain = True
                _iso_log(f"Follow-up update step was not confirmed successful: {step_label} ({update_detail})")
                subprocess.run(
                    ["kdialog", "--passivepopup", f"The update step was not confirmed successful, so this and all later update files were kept: {step_label}", "8"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                break

            # Delete a follow-up source only after EVERY planned step inside it
            # succeeded and there are no unresolved alternative patchers. This is
            # crucial for packages like Elden Ring where one archive contains 3+
            # incremental EXEs; deleting after step 1 would lose steps 2 and 3.
            if source_all_steps_ok and not unresolved and follow_exes and not keep_extracted_source:
                _remove_consumed_followup_folder(source, files_dir)
                _iso_log(f"All {len(follow_exes)} update step(s) from {label} completed; consumed follow-up source removed")

        # For Steam/Proton base installs with follow-up sources, this is the
        # single final integration point: close Steam, write+verify shortcut,
        # reopen Steam, then apply artwork. No premature shortcut/artwork step
        # happens between the base setup and its update chain.
        _write_iso_session(session_id, status="steam-finalizing")
        finalization = _finalize_deferred_stream_steam(result) if defer_post_finalize else {"ok": True, "needed": False}
        if finalization.get("needed") and not finalization.get("ok"):
            _iso_log(f"Deferred StreamExtract Steam finalization queued/failed: {finalization.get('error')}")

        deleted = False
        source_tree_deleted = False
        source_cleanup_error = ""
        followup_path = ""
        followup_count = 0
        final_status = "done"
        if not keep_extracted_source:
            # Any successfully-used follow-up directories were removed above.
            # Preserve only the still-unused/failed ones, then remove the large
            # consumed base ISO/source tree. If none remain, delete the complete
            # verified StreamExtract staging prefix normally.
            followup = _preserve_stream_followups(files_dir, iso, game_name)
            if followup.get("found"):
                if followup.get("ok"):
                    followup_path = str(followup.get("path") or "")
                    followup_count = int(followup.get("count") or 0)
                    source_tree_deleted = True
                    deleted = True
                    final_status = "done-followup" if followup_count else "done"
                    _iso_log(
                        f"Preserved {followup_count} unused follow-up source(s) at {followup_path}; removed consumed base source tree."
                    )
                else:
                    partial_path = str(followup.get("path") or "")
                    source_cleanup_error = str(followup.get("error") or "Could not preserve follow-up installer files.")
                    if partial_path:
                        source_cleanup_error += f" Partial follow-up location: {partial_path}"
                    _iso_log(f"Follow-up preservation failed; base source was kept: {source_cleanup_error}")
            else:
                source_tree_deleted, source_cleanup_error = _delete_stream_iso_source_tree(files_dir, iso)
                deleted = source_tree_deleted
                if not source_tree_deleted:
                    _iso_log(f"Could not delete StreamExtract installer source tree {files_dir}: {source_cleanup_error}")
        elif delete_iso:
            try:
                iso.unlink()
                deleted = True
                _cleanup_empty_stream_iso_source(files_dir, iso)
            except Exception as exc:
                _iso_log(f"Could not delete completed ISO {iso}: {exc}")

        _write_iso_session(
            session_id, status=final_status, manager_pid=0, finished_at=int(time.time()),
            mountpoint="", loop_device="", mount_device="",
            deleted=deleted, source_tree_deleted=source_tree_deleted,
            source_cleanup_error=source_cleanup_error,
            followup_path=followup_path, followup_count=followup_count,
            followup_used=used_followups, followup_skipped=skipped_followups,
            followup_failed=failed_followups,
        )
        message = "Installation finished and the ISO was unmounted."
        if used_followups:
            message += f" {used_followups} follow-up update/patch{' was' if used_followups == 1 else 'es were'} installed."
        if followup_path:
            message += (
                f" {followup_count} unused follow-up installer source{' was' if followup_count == 1 else 's were'} kept at:\n{followup_path}"
            )
        elif not keep_extracted_source:
            if source_tree_deleted:
                message += " The consumed installer files were deleted to free disk space."
            else:
                message += " The extracted installer files could not be deleted, so they were kept."
        elif delete_iso:
            message += " The ISO was deleted to free disk space." if deleted else " The ISO could not be deleted, so it was kept."
        elif stream_managed:
            message += " The extracted installer files were kept."
        else:
            message += " The ISO was kept."
        subprocess.run(
            ["kdialog", "--passivepopup", message, "8"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception as exc:
        _iso_log(f"ISO session {session_id} failed: {exc}\n{traceback.format_exc()}")
        _write_iso_session(session_id, status="error", error=str(exc))
        error(
            "The ISO installer bridge stopped unexpectedly.\n\n"
            f"{exc}\n\nDiagnostic log:\n{ISO_INSTALL_LOG}\n\nThe installer source was kept."
        )
    finally:
        # Cancel/failure paths still unmount the virtual disc, but never delete
        # the ISO. Busy discs are left mounted instead of being force-removed.
        current = _read_iso_session(marker_path)
        status = str(current.get("status") or "")
        if status not in {"done", "done-followup"} and mountpoint and not _mount_path_in_use(mountpoint):
            ok, detail = _unmount_iso(loop_device, mount_device)
            if ok:
                _write_iso_session(
                    session_id, manager_pid=0, finished_at=int(time.time()),
                    mountpoint="", loop_device="", mount_device="",
                )
            elif detail:
                _iso_log(f"ISO cleanup after {status or 'unknown'} failed: {detail}")

def _stream_iso_status(session_id):
    path = _iso_session_file(session_id)
    if not path.is_file():
        return {"ok": False, "missing": True, "session_id": str(session_id or "")}
    data = _read_iso_session(path)
    data["ok"] = True
    data["session_id"] = str(data.get("session_id") or session_id or "")
    return data


def _stream_iso_launch(files_text, storage_mode="internal", storage_root="", keep_extracted_source=True):
    _stream_iso_cleanup_stale_sessions(force=False)
    files_dir = Path(str(files_text or "")).expanduser().resolve()
    if not files_dir.is_dir():
        return {"ok": False, "error": f"Extracted files folder was not found: {files_dir}"}
    iso = _choose_stream_iso(files_dir)
    if not iso:
        return {"ok": False, "cancelled": True, "error": "No ISO was selected."}
    try:
        mounted = _mount_iso_read_only(iso)
    except Exception as exc:
        return {"ok": False, "error": str(exc), "iso": str(iso)}

    session_id = f"{int(time.time())}-{os.getpid()}-{abs(hash(str(iso))) & 0xfffffff:x}"
    marker_path = _iso_session_file(session_id)
    try:
        # `_write_iso_session` deliberately uses `session_key` as its function
        # parameter name so the JSON payload can also store `session_id`.
        # V7.4.22 called a function whose first parameter was itself named
        # `session_id`, then supplied `session_id=` again for the JSON field,
        # which raised "got multiple values for argument 'session_id'" after
        # the ISO had already mounted successfully.
        _write_iso_session(
            session_id,
            session_id=session_id,
            created_at=int(time.time()),
            status="mounted",
            iso=str(iso),
            loop_device=str(mounted.get("loop_device") or ""),
            mount_device=str(mounted.get("mount_device") or ""),
            mountpoint=str(mounted.get("mountpoint") or ""),
            files_dir=str(files_dir),
            storage_mode=str(storage_mode or "internal"),
            storage_root=str(storage_root or ""),
            keep_extracted_source=bool(keep_extracted_source),
            stream_managed=True,
        )
        log = open(ISO_INSTALL_LOG, "a", encoding="utf-8")
        try:
            proc = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "stream-iso-session", session_id],
                stdout=log, stderr=log, start_new_session=True, close_fds=True,
            )
        finally:
            log.close()
        _write_iso_session(session_id, manager_pid=int(proc.pid))
    except Exception:
        # The ISO is already mounted at this point. If session startup itself
        # fails, undo our mount instead of leaving an orphan read-only loop.
        try:
            ok, detail = _unmount_iso(
                str(mounted.get("loop_device") or ""),
                str(mounted.get("mount_device") or ""),
            )
            if not ok and detail:
                _iso_log(f"ISO session startup rollback could not unmount {iso}: {detail}")
        except Exception as cleanup_exc:
            _iso_log(f"ISO session startup rollback failed for {iso}: {cleanup_exc}")
        try:
            marker_path.unlink(missing_ok=True)
        except Exception:
            pass
        raise
    return {
        "ok": True, "launched": True, "iso": str(iso),
        "mountpoint": str(mounted.get("mountpoint") or ""), "session_id": session_id,
    }


def _standalone_iso_launch(iso_text):
    """Mount one user-selected ISO read-only and hand its installer to Moses.

    This is the Dolphin double-click path.  It deliberately reuses the proven
    StreamExtract ISO lifecycle manager so setup.exe sees the mounted disc for
    the entire install, but it does NOT treat the ISO as StreamExtract-owned.
    The original ISO is kept by default and is deleted only when the normal
    Game Installer's explicit "Delete ISO after successful installation" box
    is checked.
    """
    _stream_iso_cleanup_stale_sessions(force=False)
    iso = Path(str(iso_text or "")).expanduser().resolve()
    if not iso.is_file() or iso.suffix.casefold() != ".iso":
        return {"ok": False, "error": f"ISO file was not found: {iso}"}
    try:
        mounted = _mount_iso_read_only(iso)
    except Exception as exc:
        return {"ok": False, "error": str(exc), "iso": str(iso)}

    session_id = f"{int(time.time())}-{os.getpid()}-{abs(hash(str(iso))) & 0xfffffff:x}"
    marker_path = _iso_session_file(session_id)
    try:
        _write_iso_session(
            session_id,
            session_id=session_id,
            created_at=int(time.time()),
            status="mounted",
            iso=str(iso),
            loop_device=str(mounted.get("loop_device") or ""),
            mount_device=str(mounted.get("mount_device") or ""),
            mountpoint=str(mounted.get("mountpoint") or ""),
            files_dir=str(iso.parent),
            storage_mode="internal",
            storage_root="",
            keep_extracted_source=True,
            stream_managed=False,
        )
        log = open(ISO_INSTALL_LOG, "a", encoding="utf-8")
        try:
            proc = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "stream-iso-session", session_id],
                stdout=log, stderr=log, start_new_session=True, close_fds=True,
            )
        finally:
            log.close()
        _write_iso_session(session_id, manager_pid=int(proc.pid))
    except Exception:
        try:
            ok, detail = _unmount_iso(
                str(mounted.get("loop_device") or ""),
                str(mounted.get("mount_device") or ""),
            )
            if not ok and detail:
                _iso_log(f"Standalone ISO startup rollback could not unmount {iso}: {detail}")
        except Exception as cleanup_exc:
            _iso_log(f"Standalone ISO startup rollback failed for {iso}: {cleanup_exc}")
        try:
            marker_path.unlink(missing_ok=True)
        except Exception:
            pass
        raise

    return {
        "ok": True, "launched": True, "iso": str(iso),
        "mountpoint": str(mounted.get("mountpoint") or ""), "session_id": session_id,
    }


def _dependency_version_hint(exe: Path):
    """Return a short human-readable VC++ generation hint from file/folder names."""
    try:
        bits = [exe.name] + [parent.name for parent in list(exe.parents)[:4]]
    except Exception:
        bits = [exe.name]
    text = " ".join(bits).casefold().replace("_", " ").replace("-", " ")
    checks = [
        (r"(?:vc\+\+|visual c\+\+)?\s*(?:latest\s*)?v14\b", "v14"),
        (r"2015\s*(?:to|through|–|—|-)\s*(?:2026|2022|2019)", None),
        (r"2015\s*2019", "2015–2019"),
        (r"2015\s*2022", "2015–2022"),
        (r"\b2013\b", "2013"),
        (r"\b2012\b", "2012"),
        (r"\b2010\b", "2010"),
        (r"\b2008\b", "2008"),
        (r"\b2005\b", "2005"),
    ]
    for pattern, fixed in checks:
        m = re.search(pattern, text)
        if m:
            if fixed:
                return fixed
            raw = m.group(0)
            nums = re.findall(r"20\d{2}", raw)
            if len(nums) >= 2:
                return f"{nums[0]}–{nums[1]}"
    # Common game-shipped filenames such as vcredist_2015-2019_x64.exe.
    m = re.search(r"(20\d{2})[^0-9]+(20\d{2})", text)
    if m:
        return f"{m.group(1)}–{m.group(2)}"
    return ""


def _dependency_metadata(exe: Path):
    """Classify common Windows game redistributables conservatively by filename.

    Automatic/recommended only covers redistributables that are normally safe to
    install into an individual game prefix. Vulkan and .NET stay manual because
    Proton/SteamOS often provides a better native/runtime path and some titles
    require a very specific version.
    """
    name = exe.name.casefold()
    stem = exe.stem.casefold()
    meta = {
        "kind": "custom", "label": exe.name, "recommended": False,
        "advanced": True, "arch": "", "cacheable": True,
    }
    if re.search(r"(?:^|[_ .-])vc(?:_?redist|redist)|vcredist", stem):
        arch = "x64" if re.search(r"(?:x64|amd64|64bit)", stem) else ("x86" if re.search(r"(?:x86|32bit)", stem) else "")
        version_hint = _dependency_version_hint(exe)
        version_text = f" {version_hint}" if version_hint else ""
        meta.update({
            "kind": "vcredist" + (f"-{arch}" if arch else ""),
            "label": "Microsoft Visual C++" + version_text + " Redistributable" + (f" ({arch})" if arch else ""),
            "recommended": True, "advanced": False, "arch": arch,
            "version_hint": version_hint,
        })
    elif name in {"dxsetup.exe", "dxwebsetup.exe"} or re.search(r"(?:^|[_ .-])directx(?:[_ .-]|$)", stem):
        meta.update({"kind": "directx", "label": "DirectX Legacy Runtime", "recommended": True, "advanced": False})
    elif stem.startswith("physx") or "physx" in stem:
        meta.update({"kind": "physx", "label": "NVIDIA PhysX Runtime", "recommended": True, "advanced": False})
    elif name in {"oalinst.exe", "openal.exe"} or "openal" in stem:
        meta.update({"kind": "openal", "label": "OpenAL Runtime", "recommended": True, "advanced": False})
    elif "xna" in stem:
        meta.update({"kind": "xna", "label": "Microsoft XNA Framework", "recommended": True, "advanced": False})
    elif stem.startswith(("dotnetfx", "ndp")) or re.search(r"(?:^|[_ .-])dotnet(?:[_ .-]|$)", stem):
        meta.update({"kind": "dotnet", "label": ".NET Framework Runtime", "recommended": False, "advanced": True})
    elif stem.startswith("vulkanrt") or "vulkan runtime" in stem.replace("_", " "):
        meta.update({
            "kind": "vulkanrt", "label": "Windows Vulkan Runtime (advanced)",
            "recommended": False, "advanced": True,
        })
    return meta


def _known_dependency_metadata(exe: Path):
    meta = _dependency_metadata(exe)
    return meta if meta.get("kind") != "custom" else None


def _component_bundle_metadata(path: Path):
    """Recognize portable dependency bundles that belong beside the game EXE.

    Moses keeps the VulkanRT Components ZIP format.  These are not
    normal installers and must not be run inside Wine/Proton; Moses selects the
    matching x86/x64 runtime DLLs and copies them beside the target game EXE.
    """
    name = path.name.casefold()
    if path.suffix.casefold() == ".zip" and "vulkanrt" in name and "component" in name:
        return {
            "kind": "vulkan-components",
            "label": "Vulkan Runtime Components (game folder)",
            "recommended": False,
            "advanced": True,
            "arch": "auto",
            "cacheable": False,
            "install_mode": "game-folder-components",
        }
    return None


def _dependency_scan_roots_for_steam(entry):
    roots = []
    final_text = str(entry.get("final_exe") or "").strip()
    start_text = str(entry.get("start_dir") or "").strip()
    for raw in (start_text, str(Path(final_text).parent) if final_text else ""):
        if not raw:
            continue
        p = Path(raw).expanduser().resolve(strict=False)
        # Include the game directory and a few nearby ancestors, but never scan
        # the whole Windows drive or Program Files tree just to find redists.
        for _ in range(4):
            if p.name.casefold() in {"drive_c", "program files", "program files (x86)", "windows", "users"}:
                break
            if p.is_dir() and p not in roots:
                roots.append(p)
            if p.parent == p:
                break
            p = p.parent
    return roots


def _dependency_scan_roots_for_lutris(game_id):
    db = database_path()
    if not db:
        return []
    conn = sqlite3.connect(db)
    try:
        row = conn.execute("SELECT directory FROM games WHERE CAST(id AS TEXT)=? LIMIT 1", (str(game_id),)).fetchone()
    finally:
        conn.close()
    if not row or not row[0]:
        return []
    p = Path(os.path.expanduser(str(row[0]))).resolve(strict=False)
    return [p] if p.is_dir() else []


def _scan_known_dependencies(roots, source_name="game"):
    items = []
    seen = set()
    skipped_dirs = {
        ".git", "__pycache__", "windows", "system32", "syswow64", "winsxs",
        "temp", "tmp", "cache", "shadercache",
    }
    visited_files = 0
    for root in roots:
        try:
            root = Path(root).expanduser().resolve(strict=False)
        except Exception:
            continue
        if not root.is_dir():
            continue
        base_depth = len(root.parts)
        try:
            walker = os.walk(root)
            for dirpath, dirs, files in walker:
                current = Path(dirpath)
                depth = len(current.parts) - base_depth
                if depth > 7:
                    dirs[:] = []
                    continue
                dirs[:] = [d for d in dirs if d.casefold() not in skipped_dirs]
                for filename in files:
                    visited_files += 1
                    if visited_files > 30000:
                        break
                    if Path(filename).suffix.casefold() not in {".exe", ".msi"}:
                        continue
                    path = current / filename
                    meta = _known_dependency_metadata(path)
                    if not meta:
                        continue
                    try:
                        key = str(path.resolve())
                    except Exception:
                        key = str(path)
                    if key in seen:
                        continue
                    seen.add(key)
                    try:
                        size = int(path.stat().st_size)
                    except OSError:
                        size = 0
                    item = dict(meta)
                    item.update({
                        "path": str(path), "filename": path.name, "size": size,
                        "source": source_name,
                    })
                    items.append(item)
                if visited_files > 30000:
                    break
        except Exception:
            continue
    order = {"vcredist-x86": 10, "vcredist-x64": 11, "vcredist": 12, "directx": 20,
             "xna": 30, "physx": 40, "openal": 50, "dotnet": 60, "vulkanrt": 70}
    items.sort(key=lambda x: (order.get(x.get("kind"), 99), x.get("filename", "").casefold()))
    return items


def _scan_component_bundles(roots, source_name="cache"):
    items = []
    seen = set()
    visited = 0
    for root in roots:
        try:
            root = Path(root).expanduser().resolve(strict=False)
        except Exception:
            continue
        if not root.is_dir():
            continue
        try:
            for dirpath, dirs, files in os.walk(root):
                dirs[:] = [d for d in dirs if d.casefold() not in {".git", "__pycache__", "tmp", "temp"}]
                for filename in files:
                    visited += 1
                    if visited > 10000:
                        break
                    if not filename.casefold().endswith(".zip"):
                        continue
                    path = Path(dirpath) / filename
                    meta = _component_bundle_metadata(path)
                    if not meta:
                        continue
                    try:
                        key = str(path.resolve())
                    except Exception:
                        key = str(path)
                    if key in seen:
                        continue
                    seen.add(key)
                    try:
                        size = int(path.stat().st_size)
                    except OSError:
                        size = 0
                    item = dict(meta)
                    item.update({"path": str(path), "filename": path.name, "size": size, "source": source_name})
                    items.append(item)
                if visited > 10000:
                    break
        except Exception:
            continue
    return items


def _dependency_item_content_key(item):
    """Content-aware identity so the same cache file never appears twice.

    Manual files placed directly in runtime-cache used to be copied into a
    SHA-256 bucket after first use, leaving both paths visible in the GUI.
    Hashing the inventory makes those physically duplicated sources one row.
    """
    path = Path(str(item.get("path") or "")).expanduser()
    kind = str(item.get("kind") or "custom")
    try:
        if path.is_file():
            return (kind, _sha256_file(path))
    except Exception:
        pass
    return (kind, str(item.get("filename") or "").casefold(), str(path))


def _dedupe_dependency_items(items):
    """Keep the dependency list clean without deleting cache files.

    Exact content duplicates are collapsed by SHA-256. Older Moses builds may
    also have left different cached copies under the *same filename* (for
    example one manual copy plus an older hashed cache copy). Showing both as
    identical-looking rows is confusing, so the GUI keeps only the first
    variant for a given dependency kind + filename. Game-provided sources are
    passed first and therefore win over cache copies. Different filenames such
    as vcredist_x86.exe and vcredist_2015-2019_x86.exe remain separate choices.
    """
    out = []
    seen_content = set()
    seen_name = set()
    for item in items:
        content_key = _dependency_item_content_key(item)
        if content_key in seen_content:
            continue
        seen_content.add(content_key)
        name_key = (
            str(item.get("kind") or "custom"),
            str(item.get("filename") or "").casefold(),
        )
        if name_key in seen_name:
            continue
        seen_name.add(name_key)
        out.append(item)
    return out


def _steam_dependency_entry(game_id, entry_hint=None):
    """Resolve a Steam/Proton game for dependency work without fragile status assumptions.

    Older Moses builds deliberately kept a ``removed`` tombstone to prevent a
    delayed worker from resurrecting a deleted game.  If that same title was
    later re-added as an existing Steam shortcut, the shortcut could be valid
    while the tombstone still made ``list_steam_native_games()`` hide the row.
    The manager GUI already has the selected game's current EXE/start folder,
    so dependency actions accept that trusted-in-process snapshot as a fallback.
    This does not revive arbitrary removed entries or install anything by itself.
    """
    game_id = str(game_id or "").strip()
    games = load_steam_registry()
    entry = None
    if game_id:
        direct = games.get(game_id)
        if isinstance(direct, dict):
            entry = dict(direct)
        if entry is None:
            for key, candidate in games.items():
                if not isinstance(candidate, dict):
                    continue
                try:
                    candidate_id = str(candidate.get("appid", key))
                except Exception:
                    candidate_id = str(key)
                if candidate_id == game_id:
                    entry = dict(candidate)
                    break

    hint = dict(entry_hint or {}) if isinstance(entry_hint, dict) else {}
    hint_id = str(hint.get("appid") or hint.get("id") or "").strip()
    if hint and hint_id and game_id and hint_id != game_id:
        hint = {}

    # Normal active registry entries remain the first choice.
    if entry and str(entry.get("status") or "") in {"installed", "detached", "pending_steam", "pending_followup"}:
        if hint:
            for field in ("name", "final_exe", "start_dir", "compatdata", "compat_tool", "storage_mode", "storage_root", "storage_uuid"):
                if not entry.get(field) and hint.get(field):
                    entry[field] = hint.get(field)
        return entry

    # Fallback for a currently selected/re-added shortcut whose registry row is
    # stale/removed.  Require an existing EXE or start directory so an old
    # tombstone cannot silently become a dependency target just from its name.
    if hint:
        final_text = str(hint.get("final_exe") or "").strip()
        start_text = str(hint.get("start_dir") or "").strip()
        final_ok = False
        start_ok = False
        try:
            final_ok = bool(final_text and Path(final_text).expanduser().is_file())
        except Exception:
            pass
        try:
            start_ok = bool(start_text and Path(start_text).expanduser().is_dir())
        except Exception:
            pass
        if final_ok or start_ok:
            merged = dict(entry or {})
            for field in ("name", "final_exe", "start_dir", "compatdata", "compat_tool", "storage_mode", "storage_root", "storage_uuid"):
                if hint.get(field) not in (None, ""):
                    merged[field] = hint.get(field)
            try:
                merged["appid"] = int(game_id)
            except Exception:
                merged["appid"] = game_id
            merged["dependency_hint_fallback"] = True
            return merged
    return None


def dependency_inventory(backend, game_id, entry_hint=None):
    backend = str(backend or "").strip().lower()
    game_id = str(game_id or "").strip()
    game_name = "Selected game"
    roots = []
    if backend == "cache":
        # Library-only mode: let the main Dependencies window manage/download
        # the shared cache even when no game is installed or selected.
        cache_items = _scan_known_dependencies([RUNTIME_CACHE_ROOT], "cache") if RUNTIME_CACHE_ROOT.is_dir() else []
        if RUNTIME_CACHE_ROOT.is_dir():
            cache_items.extend(_scan_component_bundles([RUNTIME_CACHE_ROOT], "cache"))
        return {
            "ok": True, "backend": "cache", "game_id": "", "game_name": "Dependency Library",
            "roots": [], "items": _dedupe_dependency_items(cache_items),
            "cache_dir": str(RUNTIME_CACHE_ROOT), "library_only": True,
        }
    if backend == "steam":
        entry = _steam_dependency_entry(game_id, entry_hint)
        if not entry:
            return {"ok": False, "error": "The selected Steam game could not be found. Refresh the game list or re-add its shortcut once."}
        game_name = str(entry.get("name") or game_id)
        roots = _dependency_scan_roots_for_steam(entry)
    elif backend == "lutris":
        try:
            games = {str(gid): name for gid, name in list_installed_wine_games()}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}
        if game_id not in games:
            return {"ok": False, "error": "The selected Lutris Wine game could not be found."}
        game_name = str(games[game_id])
        roots = _dependency_scan_roots_for_lutris(game_id)
    else:
        return {"ok": False, "error": "Unknown game backend."}

    # Refreshing the inventory may discover new redists shipped with this game.
    # Cache them for reuse, but NEVER run them automatically.
    try:
        cache_discovered_dependencies(roots)
    except Exception:
        pass
    game_items = _scan_known_dependencies(roots, "game")
    cache_items = _scan_known_dependencies([RUNTIME_CACHE_ROOT], "cache") if RUNTIME_CACHE_ROOT.is_dir() else []
    if RUNTIME_CACHE_ROOT.is_dir():
        cache_items.extend(_scan_component_bundles([RUNTIME_CACHE_ROOT], "cache"))
    # Prefer game-provided sources, then collapse exact duplicate cache content
    # by SHA-256. This also hides duplicate files left by older V7.4.35-39
    # builds without deleting anything from the user's cache.
    items = _dedupe_dependency_items(game_items + cache_items)
    return {
        "ok": True, "backend": backend, "game_id": game_id, "game_name": game_name,
        "roots": [str(x) for x in roots], "items": items,
        "cache_dir": str(RUNTIME_CACHE_ROOT),
    }


def _directory_size_bounded(path: Path, limit=800 * 1024 * 1024):
    total = 0
    try:
        for root, _dirs, files in os.walk(path):
            for name in files:
                try:
                    total += (Path(root) / name).stat().st_size
                except OSError:
                    pass
                if total > limit:
                    return total
    except Exception:
        return limit + 1
    return total


def _sha256_file(path: Path, chunk_size=4 * 1024 * 1024):
    """Hash a redistributable so identical installers are cached only once."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(chunk_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _sha256_directory(path: Path):
    """Content hash a small redistributable bundle such as DirectX June 2010."""
    h = hashlib.sha256()
    root = Path(path)
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            p = Path(dirpath) / name
            if p.is_file():
                files.append(p)
    for p in sorted(files, key=lambda x: str(x.relative_to(root)).casefold()):
        rel = str(p.relative_to(root)).replace(os.sep, "/")
        h.update(rel.encode("utf-8", errors="surrogatepass"))
        h.update(b"\0")
        try:
            h.update(str(p.stat().st_size).encode("ascii"))
        except OSError:
            h.update(b"0")
        h.update(b"\0")
        with open(p, "rb") as fh:
            while True:
                chunk = fh.read(4 * 1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
        h.update(b"\0")
    return h.hexdigest()


def cache_dependency_installer(exe: Path):
    """Cache a known redistributable by content without installing it.

    V7.4.36 deliberately separates *discover/cache* from *install*. The cache is
    shared, but installing a dependency remains an explicit per-game action.
    """
    exe = exe.expanduser().resolve()
    meta = _dependency_metadata(exe)
    if not exe.is_file():
        return exe
    # A manually curated source already living anywhere under runtime-cache is
    # already cached. Older builds copied it again into a hash bucket on first
    # use, which made the Dependencies window show duplicate rows.
    try:
        cache_root = RUNTIME_CACHE_ROOT.resolve()
        if exe == cache_root or cache_root in exe.parents:
            return exe
    except Exception:
        pass
    if meta.get("kind") == "custom":
        # A random EXE may require arbitrary sibling files and is not something
        # Moses should silently collect just because it was encountered.
        return exe

    kind = re.sub(r"[^a-z0-9._-]+", "-", str(meta.get("kind") or "custom").casefold()).strip("-") or "custom"
    kind_dir = RUNTIME_CACHE_ROOT / kind
    kind_dir.mkdir(parents=True, exist_ok=True)

    # Offline DirectX redistributables need the CAB files beside DXSETUP.exe.
    if meta.get("kind") == "directx" and exe.name.casefold() == "dxsetup.exe":
        parent = exe.parent
        pname = parent.name.casefold()
        size = _directory_size_bounded(parent)
        if any(token in pname for token in ("directx", "redist", "redistribut")) and size <= 800 * 1024 * 1024:
            try:
                digest = _sha256_directory(parent)
            except Exception:
                digest = ""
            if digest:
                bundle_root = kind_dir / digest[:20]
                bundle = bundle_root / parent.name
                cached = bundle / exe.name
                if not cached.is_file():
                    tmp_root = kind_dir / (digest[:20] + f".tmp-{os.getpid()}")
                    try:
                        if tmp_root.exists():
                            shutil.rmtree(tmp_root, ignore_errors=True)
                        tmp_bundle = tmp_root / parent.name
                        shutil.copytree(parent, tmp_bundle)
                        if bundle_root.exists():
                            shutil.rmtree(tmp_root, ignore_errors=True)
                        else:
                            os.replace(tmp_root, bundle_root)
                    except Exception:
                        shutil.rmtree(tmp_root, ignore_errors=True)
                        return exe
                return cached if cached.is_file() else exe
        # dxwebsetup.exe is standalone and falls through; an unbounded DXSETUP
        # bundle is safer to leave in place than to copy incompletely.
        if exe.name.casefold() == "dxsetup.exe":
            return exe

    try:
        digest = _sha256_file(exe)
    except Exception:
        return exe
    bucket = kind_dir / digest[:20]
    target = bucket / exe.name
    try:
        bucket.mkdir(parents=True, exist_ok=True)
        if not target.is_file():
            temp = bucket / (exe.name + f".tmp-{os.getpid()}")
            shutil.copy2(exe, temp)
            # Verify the copied bytes before publishing them into the shared cache.
            if _sha256_file(temp) != digest:
                temp.unlink(missing_ok=True)
                return exe
            os.replace(temp, target)
        return target
    except Exception:
        return exe


def cache_discovered_dependencies(roots):
    """Find known redistributables and put reusable sources in the shared cache.

    This function never launches an installer and never modifies a game prefix.
    """
    items = _scan_known_dependencies(roots, "game")
    cached = []
    seen = set()
    for item in items:
        raw = str(item.get("path") or "").strip()
        if not raw:
            continue
        source = Path(raw)
        try:
            target = cache_dependency_installer(source)
        except Exception:
            continue
        try:
            target = Path(target).resolve()
        except Exception:
            continue
        if not target.is_file() or RUNTIME_CACHE_ROOT not in target.parents:
            continue
        key = str(target)
        if key not in seen:
            seen.add(key)
            cached.append(key)
    return {"ok": True, "found": len(items), "cached": len(cached), "paths": cached}


def cache_game_dependencies(backend, game_id):
    """Refresh the cache for one managed game without installing anything."""
    backend = str(backend or "").strip().lower()
    game_id = str(game_id or "").strip()
    roots = []
    if backend == "steam":
        entries = {str(x.get("appid")): x for x in list_steam_native_games()}
        entry = entries.get(game_id)
        if not entry:
            return {"ok": False, "error": "The selected Steam game could not be found."}
        roots = _dependency_scan_roots_for_steam(entry)
    elif backend == "lutris":
        roots = _dependency_scan_roots_for_lutris(game_id)
        if not roots:
            return {"ok": False, "error": "The selected Lutris game could not be found."}
    else:
        return {"ok": False, "error": "Unknown game backend."}
    result = cache_discovered_dependencies(roots)
    result.update({"backend": backend, "game_id": game_id, "roots": [str(x) for x in roots]})
    return result


def launch_dependency_cache_refresh(backend, game_id):
    """Run dependency discovery in the background so install/add stays fast."""
    try:
        log_path = CACHE_DIR / "dependency-cache.log"
        log = open(log_path, "a", encoding="utf-8")
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "cache-game-dependencies", str(backend), str(game_id)],
            stdout=log, stderr=log, start_new_session=True, close_fds=True,
        )
        log.close()
        return True
    except Exception:
        try:
            log.close()
        except Exception:
            pass
        return False

def _run_dependency_steam(exe: Path, selected_appid, entry_hint=None):
    entry = _steam_dependency_entry(str(selected_appid), entry_hint)
    if not entry:
        return {"ok": False, "error": "The selected Steam-native game could not be found."}
    appid = int(entry["appid"])
    game_name = str(entry.get("name") or appid)
    selected_tool = _current_steam_compat_tool(appid) or str(entry.get("compat_tool") or DEFAULT_STEAM_COMPAT_TOOL)
    proton, resolved_name = _find_proton_for_tool(selected_tool)
    if not proton:
        return {"ok": False, "error": "Could not find a Proton executable for this game."}
    started_at = int(time.time())
    log_dir = _new_proton_log_dir(f"{game_name}-dependency", appid, started_at)
    try:
        env, compatdata = _direct_proton_env(appid, log_dir, game_name=game_name)
        launcher_log = open(log_dir / "launcher.log", "a", encoding="utf-8")
        try:
            command = [str(proton), "run", str(exe)]
            if exe.suffix.casefold() == ".msi":
                command = [str(proton), "run", "msiexec.exe", "/i", str(exe)]
            proc = subprocess.Popen(
                command, cwd=str(exe.parent), env=env,
                stdout=launcher_log, stderr=launcher_log, start_new_session=True, close_fds=True,
            )
        finally:
            launcher_log.close()
        _wait_pid(int(proc.pid))
        _wait_wineserver_for_prefix(proton, compatdata)
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as summary:
            summary.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] DEPENDENCY {game_name} AppID={appid} file={exe} tool={resolved_name} log={log_dir}\n")
        return {"ok": True, "game_name": game_name, "backend": "steam", "appid": appid, "log_dir": str(log_dir)}
    except Exception as exc:
        return {"ok": False, "error": f"Could not run the dependency with {resolved_name}: {exc}", "log_dir": str(log_dir)}


def _run_dependency_lutris(exe: Path, selected_game_id):
    if not database_path():
        return {"ok": False, "error": "Could not find the Lutris game database."}
    try:
        games = list_installed_wine_games()
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    by_id = {str(game_id): name for game_id, name in games}
    game_id = str(selected_game_id)
    if game_id not in by_id:
        return {"ok": False, "error": "The selected Lutris Wine game could not be found."}
    game_name = str(by_id[game_id])
    inside_flatpak = r"""
import os, sys, traceback
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
sys.argv[0] = "/app/bin/lutris"
from lutris.game import Game
from lutris.runners.commands.wine import wineexec
game_id, exe = sys.argv[1], os.path.abspath(sys.argv[2])
try:
    game = Game(game_id)
    if not game.is_installed or game.runner_name != "wine":
        raise RuntimeError("Selected game is not an installed Lutris Wine game.")
    runner = game.runner
    if not runner.prefix_path:
        raise RuntimeError("Lutris could not determine this game's Wine prefix.")
    runner.prelaunch()
    if exe.lower().endswith(".msi"):
        wineexec("msiexec", args='/i "' + exe.replace('"', '\"') + '"',
                 wine_path=runner.get_executable(), prefix=runner.prefix_path,
                 arch=runner.wine_arch, working_dir=os.path.dirname(exe), config=runner,
                 env=runner.get_env(os_env=True), runner=runner, blocking=True)
    else:
        wineexec(exe, wine_path=runner.get_executable(), prefix=runner.prefix_path,
                 arch=runner.wine_arch, working_dir=os.path.dirname(exe), config=runner,
                 env=runner.get_env(os_env=True), runner=runner, blocking=True)
except Exception:
    traceback.print_exc(); sys.exit(1)
"""
    result = subprocess.run(
        ["flatpak", "run", "--command=python3", APP_ID, "-c", inside_flatpak, game_id, str(exe)],
        text=True, capture_output=True,
    )
    if result.returncode != 0:
        log_file = CACHE_DIR / "last-dependency-error.txt"
        log_file.write_text((result.stdout or "") + "\n\nSTDERR:\n" + (result.stderr or ""), encoding="utf-8")
        return {"ok": False, "error": f"The dependency installer failed. Technical log: {log_file}"}
    return {"ok": True, "game_name": game_name, "backend": "lutris", "game_id": game_id}


def _dependency_target_game_exe(backend, game_id, entry_hint=None):
    backend = str(backend or "").strip().lower()
    game_id = str(game_id or "").strip()
    if backend == "steam":
        entry = _steam_dependency_entry(game_id, entry_hint)
        if entry:
            p = Path(str(entry.get("final_exe") or "")).expanduser()
            return p.resolve(strict=False) if p.is_file() else None
        return None
    if backend == "lutris":
        state = _smart_game_runtime_state(game_id)
        exe_text = str(state.get("exe") or "").strip() if state.get("ok") else ""
        if exe_text:
            p = Path(os.path.expanduser(exe_text))
            if p.is_file():
                return p.resolve(strict=False)
            record = _smart_lutris_game_config_record(game_id) or {}
            base = Path(os.path.expanduser(str(record.get("directory") or "")))
            candidate = (base / p).resolve(strict=False)
            if candidate.is_file():
                return candidate
        return None
    return None


def _pe_executable_arch(path: Path):
    """Return x86/x64/arm64 for a Windows PE executable without running it."""
    try:
        with open(path, "rb") as fh:
            if fh.read(2) != b"MZ":
                return ""
            fh.seek(0x3C)
            raw = fh.read(4)
            if len(raw) != 4:
                return ""
            pe_off = struct.unpack("<I", raw)[0]
            fh.seek(pe_off)
            if fh.read(4) != b"PE\0\0":
                return ""
            machine_raw = fh.read(2)
            if len(machine_raw) != 2:
                return ""
            machine = struct.unpack("<H", machine_raw)[0]
        return {0x014C: "x86", 0x8664: "x64", 0xAA64: "arm64"}.get(machine, "")
    except Exception:
        return ""


def _next_sidecar_backup(path: Path):
    """Return a visible side-by-side backup path that never overwrites one."""
    stem = path.stem
    suffix = path.suffix
    candidate = path.with_name(f"{stem}.backup{suffix}")
    counter = 2
    while candidate.exists():
        candidate = path.with_name(f"{stem}.backup-{counter}{suffix}")
        counter += 1
    return candidate


def _apply_vulkan_component_bundle(bundle: Path, backend, game_id, entry_hint=None):
    """Apply the matching portable Vulkan components beside the game EXE.

    Some standalone Windows games need a local Vulkan loader next to the main
    executable even though SteamOS itself already has Vulkan. The common
    VulkanRT Components ZIP contains both x86 and x64 trees, so Moses detects
    the target EXE architecture and copies the matching runtime payload only.

    Moses intentionally copies both vulkan-1.dll *and* vulkaninfo.exe from
    the matching architecture because this mirrors the manual layout that has
    proven useful for affected games. PDB debug files remain unnecessary and
    are not copied. Any different existing file is preserved beside the game
    as <name>.backup.<ext> (with a numeric suffix if needed) before replacement.
    """
    bundle = bundle.expanduser().resolve()
    meta = _component_bundle_metadata(bundle)
    if not meta:
        return {"ok": False, "error": f"Unsupported component bundle: {bundle.name}"}
    game_exe = _dependency_target_game_exe(backend, game_id, entry_hint)
    if not game_exe or not game_exe.is_file():
        return {"ok": False, "error": "Moses could not find the selected game's main EXE, so game-folder components were not copied."}
    arch = _pe_executable_arch(game_exe)
    if arch not in {"x86", "x64"}:
        return {"ok": False, "error": f"Could not determine whether {game_exe.name} is x86 or x64. Moses will not guess which Vulkan components to copy."}
    dest = game_exe.parent
    copied = []
    backups = []
    wanted = {"vulkan-1.dll", "vulkaninfo.exe"}
    try:
        with zipfile.ZipFile(bundle, "r") as zf:
            candidates = []
            for info in zf.infolist():
                if info.is_dir():
                    continue
                name = info.filename.replace("\\", "/")
                parts = [p for p in name.split("/") if p not in {"", "."}]
                if any(p == ".." for p in parts):
                    continue
                low_parts = [p.casefold() for p in parts]
                try:
                    low_parts.index(arch)
                except ValueError:
                    continue
                leaf = parts[-1]
                if leaf.casefold() not in wanted:
                    continue
                candidates.append((info, leaf))
            if not candidates:
                return {"ok": False, "error": f"No {arch} Vulkan runtime components were found in {bundle.name}."}
            # Stable ordering keeps the operation/log easy to understand.
            candidates.sort(key=lambda x: x[1].casefold())
            for info, leaf in candidates:
                target = dest / leaf
                data = zf.read(info)
                if target.is_file():
                    try:
                        if hashlib.sha256(target.read_bytes()).digest() == hashlib.sha256(data).digest():
                            copied.append(str(target))
                            continue
                    except Exception:
                        pass
                    backup = _next_sidecar_backup(target)
                    shutil.copy2(target, backup)
                    backups.append(str(backup))
                tmp = target.with_name(target.name + f".moses-{os.getpid()}.tmp")
                with open(tmp, "wb") as fh:
                    fh.write(data)
                    fh.flush()
                    os.fsync(fh.fileno())
                os.replace(tmp, target)
                copied.append(str(target))
    except zipfile.BadZipFile:
        return {"ok": False, "error": f"The component ZIP is damaged or unsupported: {bundle}"}
    except Exception as exc:
        return {"ok": False, "error": f"Could not apply Vulkan game-folder components: {exc}"}
    return {
        "ok": True, "backend": str(backend), "game_id": str(game_id),
        "game_exe": str(game_exe), "arch": arch, "copied": copied,
        "backups": backups, "component_bundle": str(bundle),
    }


def run_game_dependency(exe: Path, backend="", game_id="", cache_source=True, entry_hint=None):
    exe = exe.expanduser().resolve()
    if not exe.is_file():
        return {"ok": False, "error": f"Dependency installer was not found: {exe}"}
    backend = str(backend or "").strip().lower()
    game_id = str(game_id or "").strip()
    if not backend or not game_id:
        choices = []
        for entry in list_steam_native_games():
            if entry.get("final_exe"):
                choices.append((f"steam:{entry['appid']}", str(entry.get("name") or entry['appid']), "Steam / Proton"))
        try:
            for gid, name in list_installed_wine_games():
                choices.append((f"lutris:{gid}", str(name), "Lutris / Wine"))
        except Exception:
            pass
        if not choices:
            return {"ok": False, "cancelled": False, "error": "No installed OneClick Steam or Lutris games were found."}
        choices.sort(key=lambda x: x[1].casefold())
        args = ["--title", "Moses OneClick — Game Dependency", "--menu", "Install this dependency into which game's prefix?"]
        for key, name, label in choices:
            args.extend([key, f"{name}  —  {label}"])
        picked = dialog(args)
        if not picked:
            return {"ok": False, "cancelled": True}
        backend, game_id = picked.split(":", 1)
    run_exe = cache_dependency_installer(exe) if cache_source else exe
    if backend == "steam":
        return _run_dependency_steam(run_exe, game_id, entry_hint)
    if backend == "lutris":
        return _run_dependency_lutris(run_exe, game_id)
    return {"ok": False, "error": "Unknown game backend."}


def run_dependency_batch(backend, game_id, paths, entry_hint=None):
    clean = []
    for value in paths if isinstance(paths, list) else []:
        try:
            p = Path(str(value)).expanduser().resolve()
        except Exception:
            continue
        if p.is_file() and p.suffix.casefold() in {".exe", ".msi", ".zip"} and p not in clean:
            if p.suffix.casefold() == ".zip" and not _component_bundle_metadata(p):
                continue
            clean.append(p)
    if not clean:
        return {"ok": False, "error": "No supported dependency installers/components were selected."}
    completed = []
    for index, source in enumerate(clean, start=1):
        if source.suffix.casefold() == ".zip":
            result = _apply_vulkan_component_bundle(source, backend, game_id, entry_hint)
        else:
            result = run_game_dependency(source, backend, game_id, cache_source=True, entry_hint=entry_hint)
        if not result.get("ok"):
            result["completed"] = completed
            result["failed_file"] = str(source)
            result["index"] = index
            return result
        completed.append(str(source))
    return {"ok": True, "completed": completed, "count": len(completed)}


def _safe_dependency_pack_member(info: zipfile.ZipInfo):
    """Validate a dependency-pack ZIP member before writing it to disk."""
    name = info.filename.replace("\\", "/")
    parts = [p for p in name.split("/") if p not in {"", "."}]
    if not parts or any(p == ".." for p in parts):
        return None
    # Refuse absolute/drive-letter paths and Unix symlinks from untrusted ZIPs.
    if name.startswith("/") or re.match(r"^[A-Za-z]:", name):
        return None
    mode = (info.external_attr >> 16) & 0xFFFF
    if mode and (mode & 0o170000) == 0o120000:
        return None
    return Path(*parts)


def _extract_dependency_pack_archive(archive: Path, target: Path, max_unpacked=6 * 1024 * 1024 * 1024, max_entries=10000):
    """Safely extract a local dependency ZIP to target using atomic staging."""
    archive = Path(archive).expanduser().resolve()
    target = Path(target).expanduser()
    if not archive.is_file() or not zipfile.is_zipfile(archive):
        return {"ok": False, "error": "The selected file is not a valid ZIP dependency pack."}
    RUNTIME_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix=".dependency-import-", dir=str(RUNTIME_CACHE_ROOT)))
    staging = temp_root / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    total = 0
    written = 0
    try:
        with zipfile.ZipFile(archive, "r") as zf:
            infos = zf.infolist()
            if len(infos) > max_entries:
                return {"ok": False, "error": "Dependency pack contains too many files."}
            for info in infos:
                rel = _safe_dependency_pack_member(info)
                if rel is None:
                    return {"ok": False, "error": f"Unsafe path/symlink was found in dependency pack: {info.filename}"}
                total += int(info.file_size or 0)
                if total > max_unpacked:
                    return {"ok": False, "error": "Dependency pack exceeds the 6 GiB unpacked safety limit."}
                out = staging / rel
                if info.is_dir():
                    out.mkdir(parents=True, exist_ok=True)
                    continue
                out.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info, "r") as src, open(out, "wb") as dst:
                    shutil.copyfileobj(src, dst, length=1024 * 1024)
                    dst.flush()
                    os.fsync(dst.fileno())
                written += 1
        target.parent.mkdir(parents=True, exist_ok=True)
        old = target.parent / ("." + target.name + f".old-{os.getpid()}")
        shutil.rmtree(old, ignore_errors=True)
        if target.exists():
            os.replace(target, old)
        try:
            os.replace(staging, target)
        except Exception:
            if old.exists() and not target.exists():
                os.replace(old, target)
            raise
        shutil.rmtree(old, ignore_errors=True)
        return {"ok": True, "files": written, "unpacked_bytes": total, "cache_dir": str(target)}
    except zipfile.BadZipFile:
        return {"ok": False, "error": "The selected dependency pack is not a valid ZIP archive."}
    except Exception as exc:
        return {"ok": False, "error": f"Could not import dependency pack: {exc}"}
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)


def import_dependency_pack(path):
    """Import a user-downloaded ZIP into the shared runtime cache.

    Each unique ZIP gets a stable Imported Packs/<name>-<hash> folder, so
    importing the same file twice simply refreshes the same destination while
    different packs can coexist. The dependency inventory remains content-
    deduplicated by SHA-256.
    """
    archive = Path(str(path or "")).expanduser().resolve()
    if not archive.is_file():
        return {"ok": False, "error": f"Dependency pack was not found: {archive}"}
    if archive.suffix.casefold() != ".zip" or not zipfile.is_zipfile(archive):
        return {"ok": False, "error": "Choose a .zip dependency pack."}
    if archive.stat().st_size > 4 * 1024 * 1024 * 1024:
        return {"ok": False, "error": "Dependency pack is larger than the 4 GiB safety limit."}
    digest = _sha256_file(archive)

    # A VulkanRT Components ZIP is itself the reusable dependency artifact.
    # Preserve it as a ZIP rather than unpacking x86/x64 files into the cache.
    if _component_bundle_metadata(archive):
        target_dir = RUNTIME_CACHE_ROOT / "Imported Components"
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / archive.name
        if target.is_file():
            try:
                if _sha256_file(target) == digest:
                    return {"ok": True, "files": 1, "unpacked_bytes": int(archive.stat().st_size), "cache_dir": str(target_dir), "source": str(archive), "sha256": digest, "target": str(target), "component_bundle": True}
            except Exception:
                pass
            target = target_dir / f"{archive.stem}-{digest[:8]}{archive.suffix}"
        shutil.copy2(archive, target)
        return {"ok": True, "files": 1, "unpacked_bytes": int(target.stat().st_size), "cache_dir": str(target_dir), "source": str(archive), "sha256": digest, "target": str(target), "component_bundle": True}

    stem = re.sub(r"[^A-Za-z0-9._ -]+", "_", archive.stem).strip(" ._") or "Dependencies"
    target = RUNTIME_CACHE_ROOT / "Imported Packs" / f"{stem}-{digest[:8]}"
    result = _extract_dependency_pack_archive(archive, target)
    if result.get("ok"):
        result.update({"source": str(archive), "sha256": digest, "target": str(target)})
    return result


def _download_https_to(url, target: Path, max_bytes=512 * 1024 * 1024):
    url = str(url or "").strip()
    if not url.lower().startswith("https://"):
        raise RuntimeError("Official dependency download must use HTTPS.")
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + f".tmp-{os.getpid()}")
    req = urllib.request.Request(url, headers={"User-Agent": "Moses-OneClick-OfficialDependencies/7.4.46"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            final_url = str(resp.geturl() or url)
            if not final_url.lower().startswith("https://"):
                raise RuntimeError("Official dependency download redirected from HTTPS to HTTP and was blocked.")
            length = resp.headers.get("Content-Length")
            if length:
                try:
                    if int(length) > max_bytes:
                        raise RuntimeError(f"Download is larger than the {max_bytes // (1024*1024)} MiB safety limit.")
                except ValueError:
                    pass
            received = 0
            with open(tmp, "wb") as fh:
                while True:
                    chunk = resp.read(1024 * 1024)
                    if not chunk:
                        break
                    received += len(chunk)
                    if received > max_bytes:
                        raise RuntimeError(f"Download exceeded the {max_bytes // (1024*1024)} MiB safety limit.")
                    fh.write(chunk)
                fh.flush()
                os.fsync(fh.fileno())
        if not tmp.is_file() or tmp.stat().st_size == 0:
            raise RuntimeError("Downloaded file was empty.")
        os.replace(tmp, target)
        return {"path": str(target), "bytes": int(target.stat().st_size), "final_url": final_url}
    finally:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass


def download_official_dependency_set():
    """Download a conservative optional dependency library from vendor sources.

    Nothing here is installed into any game automatically. The files are only
    cached so the user can explicitly choose one later from Install / Repair
    Dependencies. Most items come from official Microsoft, NVIDIA, and OpenAL
    HTTPS endpoints. The Vulkan Components ZIP is the Moses project copy used by
    the game-folder Vulkan repair action and is stored separately in this set.
    """
    root = RUNTIME_CACHE_ROOT / "Official Pack"
    root.mkdir(parents=True, exist_ok=True)
    downloads = [
        ("VC++ 2015-2026 (Latest v14)/x86/vc_redist.x86.exe", "https://aka.ms/vc14/vc_redist.x86.exe", 80 * 1024 * 1024),
        ("VC++ 2015-2026 (Latest v14)/x64/vc_redist.x64.exe", "https://aka.ms/vc14/vc_redist.x64.exe", 80 * 1024 * 1024),
        ("VC++ 2013/x86/vcredist_x86.exe", "https://aka.ms/highdpimfc2013x86enu", 40 * 1024 * 1024),
        ("VC++ 2013/x64/vcredist_x64.exe", "https://aka.ms/highdpimfc2013x64enu", 40 * 1024 * 1024),
        ("VC++ 2012 Update 4/x86/vcredist_x86.exe", "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe", 40 * 1024 * 1024),
        ("VC++ 2012 Update 4/x64/vcredist_x64.exe", "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe", 40 * 1024 * 1024),
        ("VC++ 2010 SP1/x86/vcredist_x86.exe", "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe", 40 * 1024 * 1024),
        ("VC++ 2010 SP1/x64/vcredist_x64.exe", "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe", 40 * 1024 * 1024),
        ("VC++ 2008 SP1/x86/vcredist_x86.exe", "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe", 40 * 1024 * 1024),
        ("VC++ 2008 SP1/x64/vcredist_x64.exe", "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe", 40 * 1024 * 1024),
        ("DirectX June 2010/directx_Jun2010_redist.exe", "https://download.microsoft.com/download/8/4/a/84a35bf1-dafe-4ae8-82af-ad2ae20b6b14/directx_Jun2010_redist.exe", 180 * 1024 * 1024),
        ("PhysX/PhysX_9.26.0703_SystemSoftware.exe", "https://us.download.nvidia.com/Windows/9.26.0703/PhysX_9.26.0703_SystemSoftware.exe", 120 * 1024 * 1024),
        (".NET Framework 4/dotNetFx40_Full_x86_x64.exe", "https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe", 80 * 1024 * 1024),
        ("XNA Framework 4.0 Refresh/xnafx40_redist.msi", "https://download.microsoft.com/download/5/3/a/53a804c8-ec78-43cd-a0f0-2fb4d45603d3/xnafx40_redist.msi", 20 * 1024 * 1024),
        ("OpenAL 1.1/oalinst.zip", "https://www.openal.org/downloads/oalinst.zip", 20 * 1024 * 1024),
        ("Vulkan Runtime Components/VulkanRT-1.3.290.0-Components.zip", "https://raw.githubusercontent.com/mosestyle/Moses-OneClick-Tool/main/VulkanRT-1.3.290.0-Components.zip", 64 * 1024 * 1024),
    ]
    results = []
    failures = []
    for rel, url, max_bytes in downloads:
        target = root / rel
        try:
            info = _download_https_to(url, target, max_bytes=max_bytes)
            info.update({"name": rel, "url": url, "ok": True})
            results.append(info)
        except Exception as exc:
            failures.append({"name": rel, "url": url, "error": str(exc)})

    # OpenAL's official Windows installer is distributed as oalinst.zip. Keep
    # the Official Pack tidy by extracting oalinst.exe into its own folder and
    # removing only the downloaded wrapper ZIP.
    openal_zip = root / "OpenAL 1.1/oalinst.zip"
    openal_exe = root / "OpenAL 1.1/Windows Installer/oalinst.exe"
    if openal_zip.is_file() and not openal_exe.is_file():
        try:
            with zipfile.ZipFile(openal_zip, "r") as zf:
                candidate = next((i for i in zf.infolist() if not i.is_dir() and Path(i.filename).name.casefold() == "oalinst.exe"), None)
                if candidate:
                    openal_exe.parent.mkdir(parents=True, exist_ok=True)
                    tmp_openal = openal_exe.with_name(openal_exe.name + f".tmp-{os.getpid()}")
                    with zf.open(candidate, "r") as src, open(tmp_openal, "wb") as dst:
                        shutil.copyfileobj(src, dst, length=1024 * 1024)
                        dst.flush(); os.fsync(dst.fileno())
                    os.replace(tmp_openal, openal_exe)
            if openal_exe.is_file():
                openal_zip.unlink(missing_ok=True)
        except Exception:
            pass

    # The June 2010 download is a Microsoft self-extracting package. Expand it
    # once into a reusable DXSETUP + CAB directory when 7-Zip is available so
    # users can install the actual offline DirectX runtime into a game prefix.
    dx_sfx = root / "DirectX June 2010/directx_Jun2010_redist.exe"
    dx_dir = root / "DirectX June 2010/Offline Runtime"
    dxsetup = dx_dir / "DXSETUP.exe"
    if dx_sfx.is_file() and not dxsetup.is_file():
        seven = shutil.which("7zz") or shutil.which("7z") or shutil.which("7za")
        if seven:
            temp_dx = root / f".directx-extract-{os.getpid()}"
            shutil.rmtree(temp_dx, ignore_errors=True)
            temp_dx.mkdir(parents=True, exist_ok=True)
            try:
                proc = subprocess.run([seven, "x", "-y", f"-o{temp_dx}", str(dx_sfx)], text=True, capture_output=True, timeout=180)
                candidate = next((p for p in temp_dx.rglob("DXSETUP.exe") if p.is_file()), None)
                if proc.returncode == 0 and candidate:
                    # Put the complete extracted runtime (CABs included) in one
                    # visible reusable folder, preserving relative contents.
                    if dx_dir.exists():
                        shutil.rmtree(dx_dir, ignore_errors=True)
                    os.replace(temp_dx, dx_dir)
                    # The expanded DXSETUP + CAB bundle is the useful runtime
                    # source. Remove the self-extracting wrapper afterward so
                    # the Dependencies window does not show two DirectX rows.
                    try:
                        dx_sfx.unlink(missing_ok=True)
                    except Exception:
                        pass
                else:
                    shutil.rmtree(temp_dx, ignore_errors=True)
            except Exception:
                shutil.rmtree(temp_dx, ignore_errors=True)

    return {
        "ok": bool(results) and not failures,
        "partial": bool(results) and bool(failures),
        "downloaded": len(results), "failed": len(failures),
        "items": results, "failures": failures, "cache_dir": str(root),
        "directx_offline_ready": dxsetup.is_file(),
        "openal_ready": openal_exe.is_file(),
        "vulkan_components_ready": (root / "Vulkan Runtime Components/VulkanRT-1.3.290.0-Components.zip").is_file(),
    }


def _normalize_dependency_pack_url(url):
    """Accept ordinary GitHub file pages as well as direct/raw ZIP URLs.

    GitHub's /blob/ URL returns an HTML page. Moses converts the common
    github.com/OWNER/REPO/blob/REF/path.zip form to raw.githubusercontent.com
    before downloading. Other HTTPS URLs are left untouched.
    """
    url = str(url or "").strip()
    if not url.lower().startswith("https://"):
        return url
    try:
        parsed = urllib.parse.urlparse(url)
        host = parsed.netloc.casefold()
        parts = [urllib.parse.unquote(p) for p in parsed.path.split("/") if p]
        if host in {"github.com", "www.github.com"} and len(parts) >= 5 and parts[2].casefold() == "blob":
            owner, repo, ref = parts[0], parts[1], parts[3]
            rel = "/".join(urllib.parse.quote(p, safe="@:+,._-~") for p in parts[4:])
            return f"https://raw.githubusercontent.com/{urllib.parse.quote(owner, safe='._-~')}/{urllib.parse.quote(repo, safe='._-~')}/{urllib.parse.quote(ref, safe='@:+,._-~')}/{rel}"
    except Exception:
        pass
    return url


def _dependency_pack_url_filename(*urls):
    """Choose a safe ZIP filename from original/normalized/final download URLs."""
    for value in urls:
        try:
            name = Path(urllib.parse.unquote(urllib.parse.urlparse(str(value or "")).path)).name
        except Exception:
            name = ""
        if name.casefold().endswith(".zip"):
            clean = re.sub(r"[^A-Za-z0-9._ -]+", "_", name).strip(" ._")
            if clean:
                return clean
    return "Dependencies.zip"


def download_dependency_pack(url):
    """Download one HTTPS ZIP dependency pack and atomically refresh its cache.

    Normal GitHub /blob/ file links are converted to raw content automatically.
    GitHub Release assets, raw GitHub URLs, and other HTTPS ZIP endpoints also
    work directly. Ordinary packs are extracted under GitHub Packs/<pack-name>.
    A recognized VulkanRT Components ZIP is intentionally kept intact inside its
    own GitHub Packs folder so Moses can later select the matching x86/x64 files
    when applying it to a game.
    """
    url = str(url or "").strip()
    if not url.lower().startswith("https://"):
        return {"ok": False, "error": "Dependency packs must use an HTTPS URL."}
    normalized_url = _normalize_dependency_pack_url(url)
    if not normalized_url.lower().startswith("https://"):
        return {"ok": False, "error": "Dependency packs must use an HTTPS URL."}
    RUNTIME_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    max_download = 4 * 1024 * 1024 * 1024
    max_unpacked = 6 * 1024 * 1024 * 1024
    max_entries = 10000
    temp_root = Path(tempfile.mkdtemp(prefix=".dependency-pack-", dir=str(RUNTIME_CACHE_ROOT)))
    archive = temp_root / _dependency_pack_url_filename(url, normalized_url)
    staging = temp_root / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    try:
        req = urllib.request.Request(normalized_url, headers={"User-Agent": "Moses-OneClick-DependencyPack/7.4.46"})
        with urllib.request.urlopen(req, timeout=90) as resp:
            final_url = str(resp.geturl() or normalized_url)
            if not final_url.lower().startswith("https://"):
                return {"ok": False, "error": "The dependency-pack download redirected from HTTPS to an unencrypted URL and was blocked."}
            length = resp.headers.get("Content-Length")
            if length:
                try:
                    if int(length) > max_download:
                        return {"ok": False, "error": "Dependency pack is larger than the 4 GiB safety limit."}
                except ValueError:
                    pass
            received = 0
            with open(archive, "wb") as out:
                while True:
                    chunk = resp.read(1024 * 1024)
                    if not chunk:
                        break
                    received += len(chunk)
                    if received > max_download:
                        return {"ok": False, "error": "Dependency pack exceeded the 4 GiB safety limit while downloading."}
                    out.write(chunk)
                out.flush()
                os.fsync(out.fileno())

        # If a redirect supplied the useful filename, adopt it before component
        # detection so VulkanRT-...-Components.zip is recognized by name.
        actual_name = _dependency_pack_url_filename(url, normalized_url, final_url)
        if archive.name != actual_name:
            renamed = temp_root / actual_name
            os.replace(archive, renamed)
            archive = renamed

        if not zipfile.is_zipfile(archive):
            return {"ok": False, "error": "The URL did not return a valid ZIP dependency pack. GitHub file-page links are supported automatically; verify that the repository file itself is a ZIP."}

        component_meta = _component_bundle_metadata(archive)
        if component_meta:
            # Keep component bundles intact. Extracting both x86 and x64 trees
            # into the shared cache would lose the architecture boundary that
            # Moses needs when applying the bundle to a specific game.
            shutil.copy2(archive, staging / archive.name)
            total = int(archive.stat().st_size)
            written = 1
        else:
            total = 0
            written = 0
            with zipfile.ZipFile(archive, "r") as zf:
                infos = zf.infolist()
                if len(infos) > max_entries:
                    return {"ok": False, "error": "Dependency pack contains too many files."}
                for info in infos:
                    rel = _safe_dependency_pack_member(info)
                    if rel is None:
                        return {"ok": False, "error": f"Unsafe path/symlink was found in dependency pack: {info.filename}"}
                    total += int(info.file_size or 0)
                    if total > max_unpacked:
                        return {"ok": False, "error": "Dependency pack exceeds the 6 GiB unpacked safety limit."}
                    target_file = staging / rel
                    if info.is_dir():
                        target_file.mkdir(parents=True, exist_ok=True)
                        continue
                    target_file.parent.mkdir(parents=True, exist_ok=True)
                    with zf.open(info, "r") as src, open(target_file, "wb") as dst:
                        shutil.copyfileobj(src, dst, length=1024 * 1024)
                        dst.flush()
                        os.fsync(dst.fileno())
                    written += 1

        parsed_name = archive.stem
        pack_name = re.sub(r"[^A-Za-z0-9._ -]+", "_", urllib.parse.unquote(parsed_name)).strip(" ._") or "Dependencies"
        parent = RUNTIME_CACHE_ROOT / "GitHub Packs"
        parent.mkdir(parents=True, exist_ok=True)
        target = parent / pack_name
        old = parent / f".{pack_name}.old-{os.getpid()}"
        if old.exists():
            shutil.rmtree(old, ignore_errors=True)
        if target.exists():
            os.replace(target, old)
        try:
            os.replace(staging, target)
        except Exception:
            if old.exists() and not target.exists():
                os.replace(old, target)
            raise
        shutil.rmtree(old, ignore_errors=True)
        return {
            "ok": True, "url": url, "normalized_url": normalized_url, "final_url": final_url,
            "downloaded_bytes": int(archive.stat().st_size),
            "unpacked_bytes": total, "files": written, "cache_dir": str(target),
            "component_bundle": bool(component_meta), "archive_name": archive.name,
        }
    except urllib.error.HTTPError as exc:
        return {"ok": False, "error": f"Dependency pack download failed with HTTP {exc.code}."}
    except urllib.error.URLError as exc:
        return {"ok": False, "error": f"Could not reach dependency pack URL: {getattr(exc, 'reason', exc)}"}
    except zipfile.BadZipFile:
        return {"ok": False, "error": "Downloaded dependency pack is not a valid ZIP archive."}
    except Exception as exc:
        return {"ok": False, "error": f"Could not download/install dependency pack: {exc}"}
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)


def find_exe_and_open_installer(folder: Path):
    """Scan a folder for likely EXEs, then hand the chosen EXE to the normal double-click workflow."""
    folder = folder.expanduser().resolve()
    if not folder.is_dir():
        error(f"Folder was not found:\n\n{folder}")
        return
    picked = choose_game_exe_from_folder(folder, purpose="install")
    if not picked:
        return
    exe = Path(str(picked.get("exe") or "")).expanduser().resolve()
    if not exe.is_file():
        error(f"Selected EXE was not found:\n\n{exe}")
        return
    # Reuse the exact same Install / Update / Add Existing dialog and logic as
    # a normal double-click. The folder scanner merely saves the user from
    # browsing through a large directory tree manually.
    handle_new_exe(exe)


def handle_new_exe(
    exe: Path, source_iso="", source_mountpoint="", suggested_name="",
    stream_keep_extracted_source=None, preferred_update_target=None,
    managed_followup=False, force_update_hint=False,
    defer_post_install_finalize=False,
):
    choice = choose_new_exe_action(
        exe, suggested_override=suggested_name,
        source_iso=bool(str(source_iso or "").strip()),
        stream_keep_extracted_source=stream_keep_extracted_source,
        force_likely_update=force_update_hint,
    )
    if not choice:
        return {"ok": False, "cancelled": True}
    action = str(choice.get("action") or "").strip().lower()
    game_name = str(choice.get("name") or "").strip() or derive_default_name(exe)
    backend_override = str(choice.get("backend") or "").strip().lower()
    if backend_override not in {"steam", "smart", "lutris"}:
        backend_override = installer_backend()
    storage_path = str(choice.get("storage_path") or "").strip()
    storage_fstype = str(choice.get("storage_fstype") or "").strip().lower()
    if storage_path:
        # V7.2.5: distinguish an unsupported filesystem from a perfectly good
        # Linux filesystem whose freshly formatted root is simply owned by
        # root. The latter gets a non-destructive permission repair instead of
        # sending the user through formatting again.
        current_fs = str(storage_fstype or _filesystem_type_for_path(storage_path) or "").lower()
        storage_obj = Path(storage_path).expanduser().resolve()
        if current_fs in SUPPORTED_EXTERNAL_PREFIX_FILESYSTEMS and storage_obj.is_dir() and not os.access(storage_obj, os.W_OK):
            if not confirm(
                f"This external drive already uses {current_fs.upper()}, which is suitable for Steam/Proton and Lutris, "
                "but its filesystem root is not writable by your SteamOS user.\n\n"
                "OneClick can fix the drive-root ownership without formatting or deleting any game data.\n\n"
                f"Drive: {storage_obj}\n\nFix drive permissions now?"
            ):
                return
            try:
                source = _external_block_device_for_mount(storage_obj)
                _make_external_volume_writable(storage_obj, source)
            except Exception as perm_exc:
                error(str(perm_exc))
                return

        try:
            _validate_external_storage(storage_path)
        except Exception as exc:
            # Unsupported removable media (notably exFAT) gets the guarded
            # formatter. Formatting remains explicit and destructive actions
            # require both confirmation and typed FORMAT.
            try:
                replacement = _format_external_storage_assistant(storage_path, storage_fstype)
            except Exception as fmt_exc:
                error(str(fmt_exc))
                return
            if not replacement:
                return
            storage_path = str(replacement)
            storage_fstype = _filesystem_type_for_path(storage_path)
            try:
                _validate_external_storage(storage_path)
            except Exception as validate_exc:
                error(str(validate_exc))
                return

    if action == "update":
        # StreamExtract follow-up updates already know which base game was just
        # installed, so avoid asking the user to select that game a second time.
        target = preferred_update_target if isinstance(preferred_update_target, dict) else {}
        target_backend = str(target.get("backend") or "").strip().lower()
        if target_backend == "steam" and target.get("appid") is not None:
            return run_existing_steam(exe, target.get("appid"), managed_followup=managed_followup)
        if target_backend == "lutris" and target.get("game_id") is not None:
            return run_existing_lutris(exe, str(target.get("game_id")))
        # Ordinary double-click update path remains unchanged.
        return run_existing(exe)
    if action == "existing":
        if str(source_iso or "").strip():
            error(
                "This EXE is running from a mounted installer ISO.\n\n"
                "Add existing game to Steam would create a shortcut to the temporary mounted disc, "
                "so it would stop working after the ISO is unmounted.\n\n"
                "Choose Install as a new game instead."
            )
            return {"ok": False, "cancelled": True, "reason": "existing-from-iso"}
        # If the clicked EXE itself looks like an installer/update, scan its
        # enclosing folder instead of accidentally making setup.exe the game.
        low = exe.stem.casefold()
        if _looks_like_update_exe(exe) or re.search(r"\b(setup|install|installer|unins|uninstall)\b", low):
            picked = choose_game_exe_from_folder(exe.parent, game_name)
            if not picked:
                return
            return add_existing_steam_exe(Path(picked["exe"]), picked.get("name") or game_name)
        return add_existing_steam_exe(exe, game_name)
    if action == "install":
        result = install_new(
            exe, game_name=game_name, backend_override=backend_override,
            storage_path=storage_path, source_iso=bool(str(source_iso or "").strip()),
            defer_post_install_finalize=bool(defer_post_install_finalize),
        )
        if isinstance(result, dict) and str(source_iso or "").strip():
            result["delete_source_iso"] = bool(choice.get("delete_source_iso"))
        return result


def install_new_steam(
    exe: Path, game_name=None, storage_path="", source_iso=False,
    defer_post_install_finalize=False,
):
    if not game_name:
        game_name = dialog(["--inputbox", "Detected game name (edit if needed):", derive_default_name(exe)])
    if not game_name:
        return
    appid = _steam_native_appid(game_name)
    existing = load_steam_registry().get(str(appid))

    # Persistent removal tombstone wins over any stale row resurrected by an
    # installer/artwork worker from the previous generation.
    removed_at = _removal_tombstone_time(appid)
    if existing and removed_at:
        try:
            existing_created = int(existing.get("created_at") or 0)
            existing_updated = int(existing.get("updated_at") or 0)
        except Exception:
            existing_created = existing_updated = 0
        if max(existing_created, existing_updated) <= removed_at or existing.get("status") == "removed":
            remove_steam_registry_entry(appid)
            existing = None

    # V7.2.5: a hidden removal tombstone is intentionally reusable. Also
    # self-heal older stale registry rows left by V7.2.5 and earlier when both
    # the recorded game EXE and Proton prefix are already gone.
    if existing and existing.get("status") == "removed":
        remove_steam_registry_entry(appid)
        existing = None
    elif existing and existing.get("status") == "installed":
        final_text = str(existing.get("final_exe") or "").strip()
        compat_text = str(existing.get("compatdata") or "").strip()
        final_exists = bool(final_text and Path(final_text).is_file())
        compat_exists = bool(compat_text and Path(compat_text).exists())
        shortcut_exists = appid in _steam_shortcut_appids()
        old_external = str(existing.get("storage_mode") or "").lower() == "external"
        old_storage_root = str(existing.get("storage_root") or "").strip()
        old_storage_uuid = str(existing.get("storage_uuid") or "").strip()
        old_external_connected = False
        if old_storage_uuid:
            old_external_connected = _mounted_path_from_record(_block_record_for_uuid(old_storage_uuid)) is not None
        elif old_storage_root:
            try:
                target = subprocess.run(
                    ["findmnt", "-no", "TARGET", "-T", old_storage_root],
                    text=True, capture_output=True, timeout=5, check=False,
                ).stdout.strip()
                old_external_connected = bool(target and Path(target).resolve() == Path(old_storage_root).resolve())
            except Exception:
                old_external_connected = False

        stale_removed_state = (not final_exists and not compat_exists) or (not final_exists and not shortcut_exists)
        # A previous external install whose drive is currently absent must not
        # block a deliberate fresh internal install. The old external bytes are
        # left untouched; only stale local bookkeeping/broken compat links are reset.
        disconnected_external_reinstall = bool(old_external and not storage_path and not old_external_connected)

        if stale_removed_state or disconnected_external_reinstall:
            remove_steam_registry_entry(appid)
            try:
                numeric = steam_root_path() / "steamapps" / "compatdata" / str(int(appid))
                if numeric.is_symlink() and not numeric.resolve(strict=False).exists():
                    numeric.unlink(missing_ok=True)
            except Exception:
                pass
            existing = None
        elif subprocess.run(["kdialog", "--warningyesno",
                             f"{game_name} is already managed by the Steam backend.\n\nRe-run its installer anyway?"]).returncode != 0:
            return

    root = steam_root_path()
    proton = _find_proton_experimental()
    if not root:
        error("Steam installation folder could not be found.")
        return
    if not proton:
        error(
            "Proton Experimental is not installed.\n\n"
            "Install Proton Experimental from Steam first, then try the installer again."
        )
        return

    started_at = int(time.time())
    cleanup_on_failure = not bool(existing and existing.get("status") == "installed" and existing.get("final_exe"))
    proton_log_dir = _new_proton_log_dir(game_name, appid, started_at)
    try:
        env, compatdata = _direct_proton_env(
            appid, proton_log_dir, storage_root=storage_path, game_name=game_name
        )
        update_steam_registry_entry(
            appid, name=game_name, installer=str(exe), final_exe="", start_dir=str(exe.parent),
            compatdata=str(compatdata), status="installing", backend="steam",
            storage_mode="external" if storage_path else "internal",
            storage_root=str(storage_path or ""),
            storage_uuid=_filesystem_uuid_for_path(storage_path) if storage_path else "",
            compat_tool=DEFAULT_STEAM_COMPAT_TOOL, created_at=started_at,
            cleanup_on_failure=cleanup_on_failure, proton_log_dir=str(proton_log_dir),
            retry_count=0,
            source_iso_install=bool(source_iso),
            auto_finalize_shortcut=bool(source_iso and not defer_post_install_finalize),
            defer_post_install_finalize=bool(defer_post_install_finalize),
        )
        _clear_removal_tombstone(appid)
        launcher_log = open(proton_log_dir / "launcher.log", "a", encoding="utf-8")
        proc = subprocess.Popen(
            [str(proton), "run", str(exe)],
            cwd=str(exe.parent), env=env, stdout=launcher_log, stderr=launcher_log,
            start_new_session=True, close_fds=True,
        )
        launcher_log.close()
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as summary:
            summary.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {game_name} AppID={appid} log={proton_log_dir}\n")
    except Exception as exc:
        error(f"Could not launch the installer with Proton Experimental:\n\n{exc}\n\nLog folder:\n{proton_log_dir}")
        return

    # Steam stays open for the whole installer. Final Steam integration happens
    # only after Proton/Wine has completely finished.
    launch_direct_proton_watcher(appid, game_name, started_at, proc.pid, proton)
    return {
        "ok": True, "launched": True, "action": "install", "backend": "steam",
        "appid": int(appid), "game_name": str(game_name), "started_at": int(started_at),
        "launcher_pid": int(proc.pid),
    }


def list_steam_native_games():
    games = load_steam_registry()
    return [entry for entry in games.values() if entry.get("status") in {"installed", "detached", "pending_steam", "pending_followup"}]


def run_existing_steam(exe: Path, selected_appid=None, managed_followup=False):
    games = [x for x in list_steam_native_games() if x.get("final_exe")]
    if not games:
        error("No Steam-native One-Click games were found.")
        return
    by_id = {str(entry["appid"]): entry for entry in games}
    if selected_appid is not None:
        key = str(selected_appid)
        entry = by_id.get(key)
        if not entry:
            error("The selected Steam-native game could not be found.")
            return
    else:
        args = ["--menu", "Run this EXE inside which Steam game prefix?"]
        for entry in sorted(games, key=lambda x: str(x.get("name", "")).casefold()):
            key = str(entry["appid"])
            args.extend([key, entry.get("name", key)])
        key = dialog(args)
        if not key:
            return
        entry = by_id[key]
    appid = int(entry["appid"])
    game_name = str(entry.get("name") or appid)

    selected_tool = _current_steam_compat_tool(appid) or str(entry.get("compat_tool") or DEFAULT_STEAM_COMPAT_TOOL)
    proton, resolved_name = _find_proton_for_tool(selected_tool)
    if not proton:
        error(
            "Could not find a Proton executable for this game.\n\n"
            "Install Proton Experimental or select an installed Proton version in Steam and try again."
        )
        return

    started_at = int(time.time())
    log_dir = _new_proton_log_dir(f"{game_name}-update", appid, started_at)
    try:
        env, compatdata = _direct_proton_env(appid, log_dir)
        launcher_log = open(log_dir / "launcher.log", "a", encoding="utf-8")
        proc = subprocess.Popen(
            [str(proton), "run", str(exe)],
            cwd=str(exe.parent), env=env, stdout=launcher_log, stderr=launcher_log,
            start_new_session=True, close_fds=True,
        )
        launcher_log.close()
        with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as summary:
            summary.write(
                f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] UPDATE {game_name} AppID={appid} "
                f"tool={resolved_name} log={log_dir}\n"
            )
    except Exception as exc:
        error(f"Could not launch the update/patch with {resolved_name}:\n\n{exc}\n\nLog folder:\n{log_dir}")
        return

    if not managed_followup:
        launch_direct_update_watcher(appid, game_name, proc.pid, proton, log_dir, exe, 0)
    return {
        "ok": True, "launched": True, "action": "update", "backend": "steam-update",
        "appid": int(appid), "game_name": str(game_name), "launcher_pid": int(proc.pid),
        "proton_path": str(proton), "compatdata": str(compatdata), "log_dir": str(log_dir),
        "managed_followup": bool(managed_followup),
    }


def dialog(args):
    localized = []
    for arg in args:
        localized.append(_localize_helper_text(arg) if isinstance(arg, str) else arg)
    result = subprocess.run(["kdialog", *localized], text=True, capture_output=True)
    if result.returncode != 0:
        return None
    return result.stdout.rstrip("\n")


def confirm(message):
    """Return True only when the user explicitly accepts a KDialog yes/no prompt."""
    result = subprocess.run(["kdialog", "--yesno", _localize_helper_text(message)], text=True, capture_output=True)
    return result.returncode == 0


def error(message):
    subprocess.run(["kdialog", "--error", _localize_helper_text(message)])


def database_path():
    candidates = [
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/pga.db",
        Path.home() / ".local/share/lutris/pga.db",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None



def get_max_game_id():
    db = database_path()
    if not db:
        return 0
    try:
        conn = sqlite3.connect(db)
        try:
            row = conn.execute(
                "SELECT MAX(CAST(id AS INTEGER)) FROM games"
            ).fetchone()
            return int(row[0] or 0)
        finally:
            conn.close()
    except Exception:
        return 0


def steam_is_running():
    try:
        result = subprocess.run(
            ["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return True
        result = subprocess.run(
            ["pgrep", "-f", r"(^|/)steam(\s|$)|steamwebhelper"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except Exception:
        return False


def wait_for_steam_to_stop(timeout=45):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not _steam_main_process_running():
            return True
        time.sleep(0.25)
    return not _steam_main_process_running()


def _steam_main_process_running():
    try:
        if subprocess.run(
            ["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode == 0:
            return True
        result = subprocess.run(
            ["pgrep", "-f", r"(^|/)(steam|steam\.sh)(\s|$)"], text=True, capture_output=True,
        )
        return result.returncode == 0
    except Exception:
        return False


def _wait_shortcuts_vdf_quiet(timeout=6.0, quiet_for=1.0):
    path = _steam_shortcuts_vdf_path()
    if not path:
        return True
    deadline = time.time() + float(timeout)
    last = None
    stable_since = time.time()
    while time.time() < deadline:
        try:
            st = path.stat()
            signature = (st.st_mtime_ns, st.st_size)
        except FileNotFoundError:
            signature = (0, 0)
        except Exception:
            return True
        if signature != last:
            last = signature
            stable_since = time.time()
        elif time.time() - stable_since >= quiet_for:
            return True
        time.sleep(0.15)
    return True


def stop_steam_cleanly():
    if not _steam_main_process_running():
        _wait_shortcuts_vdf_quiet(timeout=2.0, quiet_for=0.6)
        return True
    steam = "/usr/lib/steam/steam" if Path("/usr/lib/steam/steam").is_file() else shutil.which("steam")
    if not steam:
        return False
    _steam_log_shortcut("requesting controlled Steam shutdown")
    try:
        subprocess.run(
            [steam, "-shutdown"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=12,
        )
    except subprocess.TimeoutExpired:
        pass
    except Exception as exc:
        _steam_log_shortcut(f"Steam shutdown command failed: {exc}")
        return False
    deadline = time.time() + 40
    while time.time() < deadline:
        if not _steam_main_process_running():
            _wait_shortcuts_vdf_quiet(timeout=6.0, quiet_for=1.0)
            _steam_log_shortcut("Steam main client stopped and shortcuts.vdf is quiet")
            return True
        time.sleep(0.20)
    _steam_log_shortcut("Steam main client did not stop before timeout")
    return not _steam_main_process_running()


def _clean_child_env():
    # Desktop-launched helpers inherit GIO/activation variables identifying the
    # parent as "One-Click Game Installer". If Steam inherits them, KDE's
    # PipeWire portal can attribute Steam's own capture request to One-Click and
    # repeatedly show a misleading screen-sharing dialog. Strip those variables
    # before launching Steam.
    env = os.environ.copy()
    for key in (
        "GIO_LAUNCHED_DESKTOP_FILE",
        "GIO_LAUNCHED_DESKTOP_FILE_PID",
        "DESKTOP_STARTUP_ID",
        "XDG_ACTIVATION_TOKEN",
    ):
        env.pop(key, None)
    return env


def start_steam():
    """Start Steam visibly without Jupiter's forced -pipewire argument."""
    env = _clean_child_env()
    direct = "/usr/lib/steam/steam" if Path("/usr/lib/steam/steam").is_file() else shutil.which("steam")
    if not direct:
        return False
    args = [direct]
    if direct == "/usr/lib/steam/steam":
        args.append("-steamdeck")
    try:
        subprocess.Popen(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
            env=env,
        )
        return True
    except Exception:
        return False


def show_steam_main_window():
    if not _steam_main_process_running():
        return False
    direct = "/usr/lib/steam/steam" if Path("/usr/lib/steam/steam").is_file() else shutil.which("steam")
    if not direct:
        return False
    try:
        subprocess.Popen(
            [direct, "steam://open/main"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
            env=_clean_child_env(),
        )
        return True
    except Exception:
        return False


def _verify_steam_native_shortcut(appid):
    try:
        present = (int(appid) & 0xffffffff) in _steam_shortcut_appids()
        _steam_log_shortcut(
            f"verify AppID={int(appid) & 0xffffffff} path={_steam_shortcuts_vdf_path()} present={present}"
        )
        return present
    except Exception as exc:
        _steam_log_shortcut(f"verify exception AppID={int(appid) & 0xffffffff}: {exc}")
        return False


def _commit_steam_shortcut_reliably(appid, game_name, final_exe, icon_path=""):
    appid = int(appid)
    steam_was_running = _steam_main_process_running()
    path = _steam_shortcuts_vdf_path()
    if not path:
        return {"ok": False, "error": "The active Steam user/config folder could not be located."}
    _steam_log_shortcut(
        f"commit start AppID={appid & 0xffffffff} name={game_name!r} steam_running={steam_was_running} path={path}"
    )
    if steam_was_running and not stop_steam_cleanly():
        return {
            "ok": False,
            "error": "Steam could not be closed cleanly, so OneClick refused to risk writing shortcuts.vdf while Steam could overwrite it.",
        }
    last_error = ""
    for attempt in (1, 2):
        try:
            if not _finalize_steam_shortcut_now(appid, game_name, Path(final_exe), icon_path):
                raise RuntimeError("The Steam shortcut writer did not complete.")
            if not _verify_steam_native_shortcut(appid):
                raise RuntimeError("The shortcut was written but could not be read back before Steam restarted.")
        except Exception as exc:
            last_error = str(exc)
            _steam_log_shortcut(f"commit attempt={attempt} pre-start failure: {exc}")
            if steam_was_running and not _steam_main_process_running():
                start_steam()
            return {"ok": False, "error": last_error}
        if not steam_was_running:
            _steam_log_shortcut(f"commit success AppID={appid & 0xffffffff}; Steam was already closed")
            return {"ok": True, "pending": False, "restarted": False}
        if not start_steam():
            _steam_log_shortcut(f"commit written AppID={appid & 0xffffffff}, but automatic Steam restart failed")
            return {
                "ok": True, "pending": False, "restarted": False,
                "warning": "Shortcut was verified, but Steam could not be restarted automatically.",
            }
        deadline = time.time() + 15
        while time.time() < deadline and not _steam_main_process_running():
            time.sleep(0.25)
        time.sleep(2.0)
        if _verify_steam_native_shortcut(appid):
            _steam_log_shortcut(f"commit success AppID={appid & 0xffffffff}; survived Steam restart attempt={attempt}")
            return {"ok": True, "pending": False, "restarted": True}
        last_error = "Steam removed or overwrote the shortcut after startup even though the pre-start write verified."
        _steam_log_shortcut(f"commit attempt={attempt} post-start verification failed")
        if attempt == 1:
            if not stop_steam_cleanly():
                break
            continue
    if steam_was_running and not _steam_main_process_running():
        start_steam()
    return {
        "ok": False,
        "error": last_error + f"\n\nTechnical log: {STEAM_SHORTCUT_DEBUG_LOG}",
    }


def create_or_repair_steam_shortcut(game_id):
    """Use Lutris' own Steam shortcut implementation after Steam is stopped."""
    inside_flatpak = r"""
import os
import sys
import traceback

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

wrapper = "/app/share/lutris/bin/lutris-wrapper"
if not os.path.isfile(wrapper):
    raise FileNotFoundError(
        f"Expected Lutris wrapper was not found at {wrapper}"
    )

sys.argv[0] = "/app/bin/lutris"

from lutris.game import Game
from lutris.util import resources
from lutris.util.steam import shortcut as steam_shortcut


def install_steamos_safe_shortcut_generator():
    # Use a tiny host-side wrapper instead of launching the Lutris Flatpak
    # directly from Steam. The wrapper keeps SteamGameId for UMU/Gaming Mode
    # but strips Steam's outer runtime/Proton variables before starting Lutris.
    # We deliberately keep Lutris' original explicit shortcut AppID, so
    # existing artwork filenames remain stable after Repair.
    original = steam_shortcut.generate_shortcut
    if getattr(original, "_lutris_oneclick_steamos_safe", False):
        return

    def fixed_generate_shortcut(game, launch_config_name):
        shortcut = original(game, launch_config_name)
        exe = str(shortcut.get("Exe", "")).strip('\"')
        if exe == "/usr/bin/flatpak":
            host_wrapper = os.path.expanduser("~/.local/bin/oneclick-lutris-steam-launch")
            shortcut["Exe"] = '"' + host_wrapper + '"'
            shortcut["StartDir"] = '"' + os.path.expanduser("~") + '"'
            shortcut["LaunchOptions"] = str(game.id)
        return shortcut

    fixed_generate_shortcut._lutris_oneclick_steamos_safe = True
    steam_shortcut.generate_shortcut = fixed_generate_shortcut


install_steamos_safe_shortcut_generator()

game_id = sys.argv[1]

try:
    game = Game(game_id)

    if not game.id:
        raise RuntimeError("The selected Lutris game could not be loaded.")
    if not game.is_installed:
        raise RuntimeError("The selected Lutris game is not installed.")
    if not game.config:
        raise RuntimeError("The selected Lutris game has no configuration.")

    # Avoid duplicates/stale entries, then create the primary shortcut
    # through Lutris' own shortcut implementation, with the current
    # SteamOS-safe Flatpak LaunchOptions backported above.
    steam_shortcut.remove_shortcut(game)
    steam_shortcut.create_shortcut(game, "")

except Exception:
    traceback.print_exc()
    sys.exit(1)
"""

    return subprocess.run(
        [
            "flatpak", "run", "--command=python3", APP_ID, "-c",
            inside_flatpak, str(game_id)
        ],
        text=True,
        capture_output=True,
    )


def repair_shortcut_with_steam_restart(
    game_id,
    game_name,
    ask=True,
    close_steam=True,
    reopen_steam=True,
):
    """Create/repair a Lutris Steam shortcut.

    Automatic installs can leave Desktop Steam running. The new shortcut will
    then be picked up the next time Steam reloads, such as when entering
    Gaming Mode.
    """
    if ask:
        confirm = subprocess.run(
            [
                "kdialog",
                "--title", "Add to Steam Gaming Mode",
                "--yesno",
                f"{game_name} is ready.\\n\\n"
                "Add/repair its Steam shortcut now?\\n\\n"
                "Steam may need to close briefly so the shortcut database can be updated."
            ]
        )
        if confirm.returncode != 0:
            return False

    steam_was_running = steam_is_running()

    if steam_was_running and close_steam:
        if not stop_steam_cleanly():
            error(
                "Steam could not be closed automatically.\\n\\n"
                "Nothing was changed. You can use "
                "'Lutris Steam Shortcut Repair' later."
            )
            return False

        # Give Steam a moment to finish saving its own shortcut database.
        time.sleep(1.5)

    result = create_or_repair_steam_shortcut(game_id)

    if result.returncode != 0:
        log_file = CACHE_DIR / "last-steam-shortcut-error.txt"
        log_file.write_text(
            (result.stdout or "") + "\\n\\nSTDERR:\\n" + (result.stderr or ""),
            encoding="utf-8",
        )

        if steam_was_running and close_steam and reopen_steam:
            start_steam()

        error(
            "The Steam shortcut could not be created.\\n\\n"
            "Steam was not left closed.\\n\\n"
            f"Technical log:\\n{log_file}"
        )
        return False

    if steam_was_running and close_steam and reopen_steam:
        start_steam()

    if steam_was_running and not close_steam:
        popup_text = (
            f"{game_name} was added to Steam.\\n"
            "It may not appear in Desktop Steam immediately. "
            "Return to Gaming Mode normally and it should appear there."
        )
    elif steam_was_running and close_steam and not reopen_steam:
        popup_text = (
            f"{game_name} was added to Steam.\\n"
            "Steam was left closed — just Return to Gaming Mode when you're ready."
        )
    else:
        popup_text = (
            f"{game_name} was added to Steam. "
            "It should appear under Non-Steam games / Gaming Mode."
        )

    # Automatic post-install shortcut creation should be completely silent.
    # Manual repair mode can still show feedback if explicitly requested.
    if ask:
        subprocess.run(
            [
                "kdialog",
                "--passivepopup",
                popup_text,
                "5",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return True


def find_completed_install(unique_config_prefix, game_name, min_id):
    db = database_path()
    if not db:
        return None

    conn = sqlite3.connect(db)
    try:
        # Best match: config path generated by THIS exact one-click install.
        row = conn.execute(
            """
            SELECT id, name, installed, runner, configpath
            FROM games
            WHERE configpath LIKE ?
            ORDER BY CAST(id AS INTEGER) DESC
            LIMIT 1
            """,
            (unique_config_prefix + "%",),
        ).fetchone()

        if row and int(row[2] or 0) == 1:
            return str(row[0]), row[1]

        # Fallback for future Lutris changes that rename config paths.
        row = conn.execute(
            """
            SELECT id, name, installed, runner, configpath
            FROM games
            WHERE CAST(id AS INTEGER) > ?
              AND name = ?
            ORDER BY CAST(id AS INTEGER) DESC
            LIMIT 1
            """,
            (int(min_id), game_name),
        ).fetchone()

        if row and int(row[2] or 0) == 1:
            return str(row[0]), row[1]

        return None
    finally:
        conn.close()


def launch_background_artwork(game_id, game_name):
    """Run the normal artwork engine silently after an automatic install.

    This never blocks or fails the installation flow. Official Steam artwork is
    attempted even if no SteamGridDB API key has been saved yet; SteamGridDB is
    simply unavailable as a fallback until the user saves a key in the Tools UI.
    """
    if not TOOLS_GUI_PATH.is_file():
        return False

    try:
        log = open(BACKGROUND_ARTWORK_LOG, "a", encoding="utf-8")
        subprocess.Popen(
            [
                "flatpak",
                "run",
                "--command=python3",
                APP_ID,
                str(TOOLS_GUI_PATH),
                "--background-artwork",
                str(game_id),
                str(game_name or ""),
            ],
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True,
        )
        log.close()
        return True
    except Exception:
        return False


def _finish_temporary_lutris_install_session(was_running_before, timeout=20):
    """Close only the Lutris session that OneClick spawned for an installer.

    `lutris -i` starts the full Lutris Flatpak. On SteamOS the installer window can
    disappear while the application instance itself remains alive and invisible.
    That stale instance can then swallow later Lutris/Play requests until the
    session is restarted. If Lutris was already open before OneClick began, leave
    it completely untouched.
    """
    if was_running_before:
        return True
    if not lutris_is_running():
        return True

    for _attempt in range(2):
        try:
            subprocess.run(
                ["flatpak", "kill", APP_ID],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=8,
                check=False,
                env=_clean_child_env(),
            )
        except Exception:
            pass

        deadline = time.time() + max(2, int(timeout / 2))
        while time.time() < deadline:
            if not lutris_is_running():
                # Give Flatpak/D-Bus a brief moment to release the old instance.
                time.sleep(0.8)
                return True
            time.sleep(0.25)

    return not lutris_is_running()


def watch_install_and_offer_steam(unique_config_prefix, game_name, min_id, smart_plan_path="", lutris_was_running_before=False):
    # Poll lightly in the background. If the user cancels the installer,
    # this watcher simply expires without changing anything.
    deadline = time.time() + (6 * 60 * 60)

    while time.time() < deadline:
        try:
            match = find_completed_install(
                unique_config_prefix, game_name, min_id
            )
        except Exception:
            match = None

        if match:
            game_id, detected_name = match

            # Let Lutris finish its final DB/config flush.
            time.sleep(3)

            # Smart recipes may contain explicit write_config compatibility fixes.
            # Verify those before the first Steam/Gaming Mode launch and safely
            # re-apply only the exact directive the selected Lutris recipe requested.
            if smart_plan_path:
                _smart_apply_write_config_fallback(game_id, smart_plan_path)
                smart_ok, smart_report = _smart_post_install_validate(game_id, smart_plan_path)
                if not smart_ok:
                    # Even a compatibility-validation failure must not leave the
                    # temporary Lutris installer application alive/invisible.
                    _finish_temporary_lutris_install_session(bool(lutris_was_running_before))
                    problems = []
                    for item in (smart_report.get("critical") or [])[:5]:
                        msg = str(item.get("message") or item.get("code") or "Compatibility validation failed")
                        if msg:
                            problems.append("• " + msg)
                    detail = "\n".join(problems) or str(smart_report.get("error") or "Smart compatibility validation failed.")
                    subprocess.run([
                        "kdialog", "--error",
                        "Smart Automatic did not mark this game Ready because a compatibility requirement was not applied.\n\n"
                        + detail +
                        "\n\nThe Lutris installation was kept, but OneClick did not create/finalize the Steam launch path."
                    ])
                    return

            # V7.2.5: local `lutris -i` installs can leave the full Flatpak
            # application alive after the installer window has been closed. If
            # OneClick started that session, shut it down cleanly now BEFORE
            # spawning fresh headless Flatpak jobs for shortcut/artwork. This
            # prevents invisible Lutris instances from swallowing future Play or
            # normal Lutris launches. A Lutris session that pre-existed the
            # installation is deliberately left alone.
            _finish_temporary_lutris_install_session(bool(lutris_was_running_before))

            # One-click behavior:
            # - no confirmation popup
            # - DO NOT close Desktop Steam
            # - write/repair the shortcut immediately
            # - Steam will pick it up naturally when it next reloads,
            #   e.g. when the user enters Gaming Mode
            shortcut_ok = repair_shortcut_with_steam_restart(
                game_id,
                detected_name or game_name,
                ask=False,
                close_steam=False,
                reopen_steam=False,
            )
            if shortcut_ok:
                # Fire-and-forget: artwork is downloaded/applied silently while
                # the user continues in Desktop Mode. It will already be ready
                # when Steam next reloads / Gaming Mode opens.
                launch_background_artwork(
                    game_id,
                    detected_name or game_name,
                )
            # Cache redistributable installer sources for later manual repair,
            # but never install them just because they were detected.
            launch_dependency_cache_refresh("lutris", game_id)
            return

        time.sleep(5)


def launch_install_watcher(unique_config_prefix, game_name, min_id, smart_plan_path="", lutris_was_running_before=False):
    log_file = CACHE_DIR / "steam-shortcut-watcher.log"

    try:
        log = open(log_file, "a", encoding="utf-8")
        subprocess.Popen(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                "watchsteam",
                unique_config_prefix,
                game_name,
                str(min_id),
                str(smart_plan_path or ""),
                "1" if lutris_was_running_before else "0",
            ],
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True,
            # Do not let KDE keep grouping this detached watcher under
            # "Moses OneClick Tool - Game Installer" after the visible
            # installer dialog has already finished.
            env=_clean_child_env(),
        )
        log.close()
    except Exception:
        # Installer itself should still work even if the optional watcher
        # cannot be launched.
        pass


def list_games_for_steam_repair():
    db = database_path()
    if not db:
        return []

    conn = sqlite3.connect(db)
    try:
        return conn.execute(
            """
            SELECT id, name
            FROM games
            WHERE installed = 1
              AND runner != 'steam'
              AND configpath IS NOT NULL
              AND configpath != ''
            ORDER BY name COLLATE NOCASE
            """
        ).fetchall()
    finally:
        conn.close()


def steam_shortcut_repair_menu():
    if not database_path():
        error(
            "Could not find the Lutris game database.\\n\\n"
            "Open Lutris once, close it, and try again."
        )
        return

    try:
        games = list_games_for_steam_repair()
    except Exception as exc:
        error(f"Could not read Lutris game list:\\n\\n{exc}")
        return

    if not games:
        error("No installed non-Steam Lutris games were found.")
        return

    args = ["--menu", "Choose a game to add/repair in Steam:"]
    for game_id, name in games:
        args.extend([str(game_id), name])

    game_id = dialog(args)
    if not game_id:
        return

    name = next(
        (name for gid, name in games if str(gid) == str(game_id)),
        "Selected game",
    )

    repair_shortcut_with_steam_restart(
        str(game_id),
        name,
        ask=True,
        close_steam=True,
        reopen_steam=False,
    )


def force_steam_shortcut_default_on():
    code = r'''
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
import os, sys
if os.path.isfile("/app/share/lutris/bin/lutris-wrapper"):
    sys.argv[0] = "/app/bin/lutris"
from lutris import settings
settings.write_setting("installer_create_steam_shortcut", True)
'''
    subprocess.run(
        ["flatpak", "run", "--command=python3", APP_ID, "-c", code],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _smart_title_case(text: str) -> str:
    """Make installer-style lowercase names look like game titles."""
    small_words = {
        "a", "an", "and", "as", "at", "but", "by", "for", "from",
        "in", "into", "of", "on", "or", "the", "to", "with",
    }
    roman = {
        "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x",
        "xi", "xii", "xiii", "xiv", "xv",
    }
    special = {
        "vr": "VR",
        "hd": "HD",
        "pc": "PC",
        "rpg": "RPG",
        "fps": "FPS",
        "goty": "GOTY",
        "dx": "DX",
    }

    words = text.split()
    out = []

    for index, word in enumerate(words):
        low = word.lower()

        if low in roman:
            out.append(low.upper())
            continue

        if low in special:
            out.append(special[low])
            continue

        if low in small_words and index not in (0, len(words) - 1):
            out.append(low)
            continue

        # Preserve mixed-case names if the original installer already had them.
        if any(ch.isupper() for ch in word[1:]):
            out.append(word)
        elif word:
            out.append(word[0].upper() + word[1:])
        else:
            out.append(word)

    return " ".join(out)


def _clean_installer_name(raw_name: str) -> str:
    """Best-effort cleanup for GOG and other common Windows installer names."""
    name = raw_name.strip()

    # Common installer prefixes:
    # setup_game, install-game, installer.game, gog_setup_game, etc.
    name = re.sub(
        r"(?ix)^"
        r"(?:gog[\s_.-]*)?"
        r"(?:setup|installer?|install|game[\s_.-]*installer|game[\s_.-]*setup)"
        r"[\s_.-]+",
        "",
        name,
    )

    # GOG and similar installers often end with metadata such as:
    # _(64bit)_(89650), (x64), (32bit), (windows), (gog), etc.
    metadata_pattern = re.compile(
        r"(?ix)"
        r"[\s_.-]*"
        r"\("
        r"(?:"
        r"x?64|amd64|64[\s_-]*bit|"
        r"x86|32[\s_-]*bit|"
        r"win(?:32|64)?|windows|"
        r"gog|offline|"
        r"\d{4,}"
        r")"
        r"\)"
        r"$"
    )

    previous = None
    while previous != name:
        previous = name
        name = metadata_pattern.sub("", name).strip(" _.-")

    # Also strip common architecture/platform tokens when not parenthesized.
    name = re.sub(
        r"(?ix)[\s_.-]+"
        r"(?:x64|amd64|64[\s_-]*bit|x86|32[\s_-]*bit|win64|win32|windows)"
        r"$",
        "",
        name,
    )

    # Strip a trailing dotted version, but keep normal title numbers.
    #
    # Examples removed:
    #   1.0
    #   1.0.30000
    #   v2.31
    #   version-1.4.2
    #
    # Examples preserved:
    #   The Witcher 3
    #   Cyberpunk 2077
    #   Resident Evil 4
    name = re.sub(
        r"(?ix)"
        r"[\s_-]+"
        r"(?:v(?:er(?:sion)?)?[\s_.-]*)?"
        r"\d+(?:\.\d+){1,}"
        r"(?:[a-z0-9.-]*)?"
        r"$",
        "",
        name,
    )

    # Trailing build/revision markers.
    name = re.sub(
        r"(?ix)[\s_.-]+(?:build|revision|rev)[\s_.-]*\d+$",
        "",
        name,
    )

    # Generic suffixes.
    name = re.sub(
        r"(?ix)[\s_.-]+(?:setup|installer?|install|offline[\s_-]*installer)$",
        "",
        name,
    )

    # Convert filename separators to normal spaces only AFTER stripping versions.
    name = re.sub(r"[_]+", " ", name)
    name = re.sub(r"\.{2,}", " ", name)
    name = re.sub(r"(?<!\d)\.(?!\d)", " ", name)
    name = re.sub(r"\s+", " ", name).strip(" -_.")

    return name


def derive_default_name(exe: Path):
    raw = exe.stem.strip()

    generic = {
        "setup", "setup64", "setup_x64", "setup-x64",
        "install", "installer", "gameinstaller",
        "game-installer", "start", "launcher",
    }

    # If the executable is literally just "setup.exe", the enclosing folder
    # is usually a better clue.
    if raw.lower() in generic and exe.parent.name:
        raw = exe.parent.name

    name = _clean_installer_name(raw)

    # If cleanup produced something useless, make one attempt using the folder.
    if not name or name.lower() in generic or re.fullmatch(r"[\d\s._-]+", name):
        name = _clean_installer_name(exe.parent.name)

    if not name:
        return "New Lutris Game"

    return _smart_title_case(name)


SMART_LUTRIS_LOG = CACHE_DIR / "smart-lutris-last.json"
SMART_RUNTIME_LOG = CACHE_DIR / "smart-runtime-last.json"

# Small, surgical compatibility overrides. This is intentionally NOT a giant
# game database: Lutris remains the primary source. Overrides only fill gaps
# where the published recipe/notes are too vague to select a known-good runtime.
SMART_COMPAT_OVERRIDES = {
    "halo-2": {
        "installer_contains": ("project cartographer", "cartographer"),
        "preferred_wine": "GE-Proton9-27",
        "forbid_wine_major": (10, 11),
        "min_dxvk": "2.5.3",
        "append_args": ("-nointro",),
        # wmp9 emits this warning in win64 prefixes. For this recipe the intro
        # is disabled and a known-good Proton 9 runtime is pinned, so the warning
        # is important diagnostic context but is not itself a hard failure.
        "expected_nonfatal_log": (
            "wm9codecs is not supported in win64 prefixes",
            "you are using a 64-bit wineprefix",
        ),
        "reason": "Project Cartographer has current Wine 10/11 media regressions; use the known-good GE-Proton 9 family.",
    },
}


def _smart_norm(text):
    return re.sub(r"[^a-z0-9]+", " ", str(text or "").casefold()).strip()


def _smart_tokens(text):
    stop = {"the", "and", "game", "setup", "installer", "install", "windows", "pc", "edition"}
    return {x for x in _smart_norm(text).split() if len(x) > 1 and x not in stop}


def _flatpak_lutris_api(mode, value):
    """Use the installed Lutris client's own Python/API, never HTML scraping."""
    code = r'''
import json, sys
from lutris import api
mode, value = sys.argv[1], sys.argv[2]
try:
    if mode == "search":
        payload = api.search_games(value) or {}
        out = {"ok": True, "results": payload.get("results", [])}
    elif mode == "installers":
        out = {"ok": True, "results": api.get_game_installers(value) or []}
    elif mode == "wine_versions":
        from lutris.util.wine.wine import get_installed_wine_versions
        out = {"ok": True, "results": list(get_installed_wine_versions() or [])}
    elif mode == "paths":
        from lutris import settings
        out = {"ok": True, "results": {"wine_dir": settings.WINE_DIR, "config_dir": settings.CONFIG_DIR}}
    else:
        raise ValueError("Unknown API mode")
    print(json.dumps(out))
except Exception as exc:
    print(json.dumps({"ok": False, "error": str(exc), "results": []}))
'''
    try:
        result = subprocess.run(
            ["flatpak", "run", "--command=python3", APP_ID, "-c", code, mode, str(value)],
            text=True, capture_output=True, timeout=45,
        )
        lines = [x.strip() for x in (result.stdout or "").splitlines() if x.strip()]
        if not lines:
            return {"ok": False, "error": (result.stderr or "No Lutris API response").strip(), "results": []}
        data = json.loads(lines[-1])
        return data if isinstance(data, dict) else {"ok": False, "error": "Invalid API response", "results": []}
    except Exception as exc:
        return {"ok": False, "error": str(exc), "results": []}


def _smart_game_score(query, game):
    q = _smart_norm(query)
    name = _smart_norm(game.get("name") or "")
    slug = _smart_norm(str(game.get("slug") or "").replace("-", " "))
    if not q or not name:
        return 0.0
    if q == name:
        base = 100.0
    elif q == slug:
        base = 98.0
    elif name.startswith(q) or q.startswith(name):
        base = 91.0
    else:
        ratio = difflib.SequenceMatcher(None, q, name).ratio()
        qt, nt = _smart_tokens(q), _smart_tokens(name)
        overlap = len(qt & nt) / max(1, len(qt | nt))
        base = ratio * 70.0 + overlap * 30.0
    try:
        platforms = " ".join(str(x.get("name") or "") for x in (game.get("platforms") or []) if isinstance(x, dict)).casefold()
        if "windows" in platforms:
            base += 2.0
    except Exception:
        pass
    return min(100.0, base)


def _walk_script_items(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk_script_items(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_script_items(child)


def _smart_recipe_text(installer):
    return " ".join(
        str(installer.get(k) or "")
        for k in ("name", "version", "slug", "installer_slug", "description", "notes")
    )


def _smart_recipe_winetricks(installer):
    verbs = []
    script = installer.get("script") or {}
    for node in _walk_script_items(script.get("installer") if isinstance(script, dict) else []):
        task = node.get("task") if isinstance(node, dict) else None
        if not isinstance(task, dict) or task.get("name") != "winetricks":
            continue
        app = str(task.get("app") or "").strip()
        if app:
            verbs.extend(x for x in re.split(r"[\s,]+", app) if x)
    return verbs


def _smart_recipe_arch(installer):
    script = installer.get("script") or {}
    game = script.get("game") if isinstance(script, dict) else {}
    if isinstance(game, dict) and str(game.get("arch") or "") in {"win32", "win64"}:
        return str(game.get("arch"))
    for node in _walk_script_items(script.get("installer") if isinstance(script, dict) else []):
        task = node.get("task") if isinstance(node, dict) else None
        if isinstance(task, dict) and task.get("name") == "create_prefix":
            arch = str(task.get("arch") or "")
            if arch in {"win32", "win64"}:
                return arch
    return "win64"


def _smart_installer_stats(installer, hints):
    script = installer.get("script") or {}
    files = (script.get("files") or []) if isinstance(script, dict) else []
    n_a = 0
    remote = 0
    for entry in files if isinstance(files, list) else []:
        if not isinstance(entry, dict):
            continue
        for value in entry.values():
            if isinstance(value, str):
                if value.strip().upper().startswith("N/A"):
                    n_a += 1
                elif value.startswith(("http://", "https://")):
                    remote += 1
            elif isinstance(value, dict):
                url = str(value.get("url") or "")
                if url.strip().upper().startswith("N/A"):
                    n_a += 1
                elif url.startswith(("http://", "https://")):
                    remote += 1

    winetricks = create_prefix = write_config = 0
    for node in _walk_script_items(script.get("installer") if isinstance(script, dict) else []):
        if "write_config" in node:
            write_config += 1
        task = node.get("task") if isinstance(node, dict) else None
        if isinstance(task, dict):
            if task.get("name") == "winetricks":
                winetricks += 1
            if task.get("name") == "create_prefix":
                create_prefix += 1

    runner = str(installer.get("runner") or "").casefold()
    version = str(installer.get("version") or "")
    slug = str(installer.get("slug") or installer.get("installer_slug") or "")
    description = str(installer.get("description") or "")
    notes = str(installer.get("notes") or "")
    text = " ".join([version, slug.replace("-", " "), description, notes]).casefold()
    score = 0.0
    if runner == "wine":
        score += 42
    elif runner in {"linux", "dosbox", "scummvm"}:
        score += 10
    else:
        score -= 35
    if isinstance(script, dict) and isinstance(script.get("game"), dict) and script["game"].get("exe"):
        score += 9
    if isinstance(script, dict) and script.get("installer"):
        score += 8
    score += min(remote * 4, 16)
    score += min(winetricks * 2, 10)
    score += min(create_prefix * 4, 8)
    score += min(write_config * 4, 12)
    if n_a == 0:
        score += 18
    else:
        score -= min(n_a * 12, 36)
    if "includes dependencies" in text or "dependencies required" in text:
        score += 16
    if "full game" in text or "complete" in text:
        score += 6
    if "installer" in version.casefold():
        score += 7
    if any(x in text for x in ("bring your own", "given archive", "select the zip", "requires user-provided")):
        score -= 15
    if any(x in text for x in ("legacy", "obsolete", "deprecated")):
        score -= 25
    if runner in {"xemu", "steam"}:
        score -= 50

    hint_tokens = set()
    for hint in hints:
        hint_tokens |= _smart_tokens(hint)
    meta_tokens = _smart_tokens(version + " " + slug.replace("-", " "))
    score += min(len(hint_tokens & meta_tokens) * 3, 15)
    return score, {
        "n_a": n_a,
        "remote": remote,
        "winetricks": winetricks,
        "write_config": write_config,
        "arch": _smart_recipe_arch(installer),
        "winetricks_verbs": _smart_recipe_winetricks(installer),
    }


def _smart_bind_clicked_installer(installer, exe):
    """Fill one obvious N/A setup-file request with the EXE the user already clicked."""
    data = json.loads(json.dumps(installer))
    script = data.get("script") or {}
    files = script.get("files") if isinstance(script, dict) else None
    candidates = []
    if isinstance(files, list):
        for entry in files:
            if not isinstance(entry, dict):
                continue
            for key, value in list(entry.items()):
                if isinstance(value, str) and value.strip().upper().startswith("N/A"):
                    candidates.append((entry, key, value))
                elif isinstance(value, dict):
                    url = str(value.get("url") or "")
                    if url.strip().upper().startswith("N/A"):
                        candidates.append((value, "url", url))
    if len(candidates) != 1:
        return data, False
    holder, key, prompt = candidates[0]
    low = prompt.casefold()
    suffix = exe.suffix.casefold()
    if any(word in low for word in ("zip", "archive", ".iso", "disc image")) and suffix == ".exe":
        return data, False
    if suffix == ".exe" and not any(x in low for x in ("zip", "archive", "iso")):
        holder[key] = str(exe)
        return data, True
    return data, False


def _smart_choose_game(query, games):
    ranked = sorted(((_smart_game_score(query, g), g) for g in games if isinstance(g, dict)), key=lambda x: x[0], reverse=True)
    if not ranked:
        return None, 0.0
    best_score, best = ranked[0]
    margin = best_score - (ranked[1][0] if len(ranked) > 1 else 0)
    if best_score >= 78 and (margin >= 8 or best_score >= 96):
        return best, best_score
    args = ["--title", "Smart Automatic / Lutris", "--menu", "OneClick found several possible games. Choose the correct one:"]
    choices = {}
    for index, (score, game) in enumerate(ranked[:6]):
        key = str(index)
        choices[key] = game
        label = f"{game.get('name','Unknown')}  —  match {int(round(score))}%"
        args.extend([key, label])
    picked = dialog(args)
    if picked is None:
        return None, 0.0
    game = choices.get(picked)
    return game, _smart_game_score(query, game or {})


def _smart_choose_installer(game, installers, hints):
    ranked = []
    for inst in installers:
        if not isinstance(inst, dict) or not inst.get("script"):
            continue
        score, stats = _smart_installer_stats(inst, hints)
        ranked.append((score, inst, stats))
    ranked.sort(key=lambda x: x[0], reverse=True)
    if not ranked:
        return None, 0.0, {}
    top_score, top, stats = ranked[0]
    margin = top_score - (ranked[1][0] if len(ranked) > 1 else -999)
    if top_score >= 35 and (margin >= 7 or len(ranked) == 1):
        return top, top_score, stats
    args = ["--title", "Smart Automatic / Lutris", "--menu", "Several Lutris recipes look suitable. Choose one:"]
    choices = {}
    for index, (score, inst, st) in enumerate(ranked[:7]):
        key = str(index)
        choices[key] = (inst, score, st)
        version = str(inst.get("version") or inst.get("slug") or "Installer")
        runner = str(inst.get("runner") or "?").title()
        extra = "automatic files" if st.get("n_a", 0) == 0 else f"{st.get('n_a')} file prompt(s)"
        args.extend([key, f"{version}  —  {runner}, {extra}"])
    picked = dialog(args)
    if picked is None:
        return None, 0.0, {}
    return choices.get(picked, (None, 0.0, {}))


def _smart_version_tuple(value):
    nums = re.findall(r"\d+", str(value or ""))
    return tuple(int(x) for x in nums[:4]) if nums else ()


def _smart_version_lt(a, b):
    aa, bb = list(_smart_version_tuple(a)), list(_smart_version_tuple(b))
    n = max(len(aa), len(bb), 1)
    aa += [0] * (n - len(aa))
    bb += [0] * (n - len(bb))
    return tuple(aa) < tuple(bb)


def _smart_versions_equivalent(a, b):
    def norm(v):
        v = str(v or "").strip().casefold()
        v = re.sub(r"-(?:x86_64|amd64)$", "", v)
        return v
    return bool(norm(a)) and norm(a) == norm(b)



def _smart_exact_ge_proton_tag(version):
    """Return a canonical exact GE-Proton tag, or empty for generic/latest versions."""
    value = re.sub(r"-(?:x86_64|amd64)$", "", str(version or "").strip(), flags=re.I)
    if re.fullmatch(r"GE-Proton\d+-\d+", value, flags=re.I):
        # Official release tags use this exact capitalization.
        m = re.fullmatch(r"ge-proton(\d+)-(\d+)", value, flags=re.I)
        return f"GE-Proton{m.group(1)}-{m.group(2)}" if m else value
    return ""


def _smart_installed_wine_versions():
    response = _flatpak_lutris_api("wine_versions", "")
    values = response.get("results") if response.get("ok") else []
    return [str(x) for x in (values or []) if str(x).strip()]


def _smart_qdbus_binary():
    for name in ("qdbus6", "qdbus", "qdbus-qt6", "qdbus-qt5"):
        path = shutil.which(name)
        if path:
            return path
    return ""


class _SmartProgressDialog:
    """Small KDE progress UI for Smart-managed downloads/components.

    KDialog returns a D-Bus service + object path. qdbus is then used to
    update the label/value while the slow work happens. If qdbus is missing,
    Smart mode simply falls back to the old passive notification.
    """

    def __init__(self, title, label, maximum=100):
        self.qdbus = _smart_qdbus_binary()
        self.ref = []
        self.maximum = max(1, int(maximum or 100))
        self.last_value = -1
        self.last_label = ""
        if not self.qdbus:
            subprocess.run(
                ["kdialog", "--passivepopup", str(label), "8"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            return
        try:
            result = subprocess.run(
                ["kdialog", "--title", str(title), "--progressbar", str(label), str(self.maximum)],
                text=True, capture_output=True, timeout=15,
            )
            parts = shlex.split((result.stdout or "").strip())
            if len(parts) >= 2:
                self.ref = parts[:2]
                self._call("showCancelButton", "false")
                self._call("setAutoClose", "false")
        except Exception:
            self.ref = []

    @property
    def active(self):
        return bool(self.qdbus and self.ref)

    def _call(self, *args):
        if not self.active:
            return False
        try:
            subprocess.run(
                [self.qdbus, *self.ref, *map(str, args)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=4,
            )
            return True
        except Exception:
            return False

    def set(self, value=None, label=None):
        if label is not None:
            label = str(label)
            if label != self.last_label:
                self._call("setLabelText", label)
                self.last_label = label
        if value is not None:
            try:
                value = max(0, min(self.maximum, int(value)))
            except Exception:
                value = 0
            if value != self.last_value:
                # KDE's documented KDialog progress interface accepts this form.
                self._call("Set", "", "value", str(value))
                self.last_value = value

    def close(self):
        if self.active:
            self._call("close")
        self.ref = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


def _smart_download_to(url, target, progress=None, start=0, span=100, label_prefix="Downloading"):
    request = urllib.request.Request(
        str(url),
        headers={
            "User-Agent": "OneClick-EXE/7.2.3",
            "Accept": "application/octet-stream",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response, open(target, "wb") as out:
        try:
            total = int(response.headers.get("Content-Length") or 0)
        except Exception:
            total = 0
        done = 0
        last_percent = -1
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            out.write(block)
            done += len(block)
            if progress and total > 0:
                percent = min(100, int(done * 100 / total))
                if percent != last_percent:
                    value = int(start + (span * percent / 100.0))
                    mib_done = done / (1024 * 1024)
                    mib_total = total / (1024 * 1024)
                    progress.set(value, f"{label_prefix}… {percent}%  ({mib_done:.0f}/{mib_total:.0f} MiB)")
                    last_percent = percent
            elif progress:
                # Content-Length is not guaranteed; at least keep the user informed.
                progress.set(start, f"{label_prefix}… {done / (1024 * 1024):.0f} MiB")
        if progress:
            progress.set(int(start + span), f"{label_prefix}… complete")


def _smart_safe_extract_tar(tar_path, destination):
    """Extract a trusted release tarball while rejecting traversal/device entries."""
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tar_path, "r:gz") as archive:
        for member in archive.getmembers():
            name = Path(member.name)
            if name.is_absolute() or ".." in name.parts or member.isdev():
                raise RuntimeError(f"Unsafe path in runtime archive: {member.name}")
            target = (destination / name).resolve()
            if target != destination and destination not in target.parents:
                raise RuntimeError(f"Archive path escapes destination: {member.name}")
            if member.issym() or member.islnk():
                link = Path(member.linkname)
                if link.is_absolute():
                    raise RuntimeError(f"Unsafe absolute link in runtime archive: {member.name}")
                # Relative links containing '..' are common in Proton archives;
                # allow them only when the resolved link target stays in staging.
                link_target = ((target.parent if member.issym() else destination) / link).resolve()
                if link_target != destination and destination not in link_target.parents:
                    raise RuntimeError(f"Archive link escapes destination: {member.name}")
        archive.extractall(destination)


def _smart_find_extracted_proton_root(staging, tag):
    preferred = Path(staging) / tag
    if (preferred / "proton").is_file():
        return preferred
    candidates = [p for p in Path(staging).iterdir() if p.is_dir() and (p / "proton").is_file()]
    return candidates[0] if len(candidates) == 1 else None


def _smart_ensure_exact_ge_proton(version):
    """Ensure an exact GE-Proton build exists before Lutris creates the prefix.

    The operation is user-visible in V7.2.5: metadata lookup, download,
    checksum verification, extraction and Lutris detection all update a KDE
    progress dialog instead of happening silently in the background.
    """
    tag = _smart_exact_ge_proton_tag(version)
    if not tag:
        return True, "not-an-exact-ge-proton-version"

    installed = _smart_installed_wine_versions()
    if any(_smart_versions_equivalent(x, tag) for x in installed):
        return True, "already-installed"

    paths = _flatpak_lutris_api("paths", "")
    wine_dir_value = ((paths.get("results") or {}).get("wine_dir") if paths.get("ok") else "") or ""
    if not wine_dir_value:
        return False, "Lutris did not report its Wine/Proton directory."
    wine_dir = Path(os.path.expanduser(str(wine_dir_value)))
    try:
        wine_dir.mkdir(parents=True, exist_ok=True)
    except Exception as exc:
        return False, f"Could not create Lutris runtime directory: {exc}"

    destination = wine_dir / tag
    if (destination / "proton").is_file():
        return True, "already-present-on-disk"

    api_url = f"https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/tags/{tag}"
    progress = _SmartProgressDialog(
        "OneClick Smart Automatic",
        f"Preparing required runtime {tag}…",
        100,
    )
    try:
        progress.set(2, f"Finding official {tag} release…")
        request = urllib.request.Request(
            api_url,
            headers={
                "User-Agent": "OneClick-EXE/7.2.3",
                "Accept": "application/vnd.github+json",
            },
        )
        with urllib.request.urlopen(request, timeout=45) as response:
            release = json.loads(response.read().decode("utf-8", "replace"))
        assets = release.get("assets") or []
        tar_asset = None
        checksum_asset = None
        for asset in assets:
            name = str((asset or {}).get("name") or "")
            url = str((asset or {}).get("browser_download_url") or "")
            if name == f"{tag}.tar.gz" and url:
                tar_asset = (name, url)
            elif name == f"{tag}.sha512sum" and url:
                checksum_asset = (name, url)
        if not tar_asset or not checksum_asset:
            return False, f"Official {tag} release assets or checksum were not found."

        with tempfile.TemporaryDirectory(prefix="oneclick-ge-proton-") as td:
            td = Path(td)
            tar_path = td / tar_asset[0]
            checksum_path = td / checksum_asset[0]

            progress.set(5, f"Downloading {tag}…")
            _smart_download_to(
                tar_asset[1], tar_path,
                progress=progress, start=5, span=62,
                label_prefix=f"Downloading {tag}",
            )
            progress.set(69, "Downloading official SHA-512 checksum…")
            _smart_download_to(
                checksum_asset[1], checksum_path,
                progress=progress, start=69, span=3,
                label_prefix="Downloading checksum",
            )

            progress.set(74, f"Verifying {tag} SHA-512…")
            checksum_text = checksum_path.read_text(encoding="utf-8", errors="replace")
            match = re.search(r"\b([0-9a-fA-F]{128})\b", checksum_text)
            if not match:
                return False, "Official GE-Proton checksum file did not contain a SHA-512 hash."
            expected = match.group(1).casefold()
            digest = hashlib.sha512()
            size = tar_path.stat().st_size if tar_path.exists() else 0
            done = 0
            with open(tar_path, "rb") as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(block)
                    done += len(block)
                    if size:
                        progress.set(74 + int(8 * done / size), f"Verifying {tag}… {int(done * 100 / size)}%")
            actual = digest.hexdigest().casefold()
            if actual != expected:
                return False, f"SHA-512 verification failed for {tag}."

            progress.set(84, f"Extracting {tag}…")
            staging = td / "extract"
            _smart_safe_extract_tar(tar_path, staging)
            root = _smart_find_extracted_proton_root(staging, tag)
            if not root:
                return False, f"The verified {tag} archive did not contain a usable Proton runtime."

            progress.set(92, f"Installing {tag} for Lutris…")
            if destination.exists():
                # Only replace an incomplete directory for this exact, verified tag.
                if (destination / "proton").is_file():
                    progress.set(100, f"{tag} is already ready.")
                    return True, "already-present-after-download"
                shutil.rmtree(destination)
            shutil.move(str(root), str(destination))

        if not (destination / "proton").is_file():
            return False, f"{tag} was extracted but its Proton launcher is missing."

        progress.set(97, "Refreshing Lutris runtime detection…")
        # Each query runs in a fresh Flatpak Python process, avoiding Lutris' in-process cache.
        installed_after = _smart_installed_wine_versions()
        if installed_after and not any(_smart_versions_equivalent(x, tag) for x in installed_after):
            return False, f"{tag} was installed but Lutris does not currently detect it."
        progress.set(100, f"{tag} is ready.")
        time.sleep(0.4)
        return True, "downloaded-and-verified"
    except urllib.error.HTTPError as exc:
        return False, f"GitHub returned HTTP {exc.code} while fetching {tag}."
    except urllib.error.URLError as exc:
        return False, f"Network error while fetching {tag}: {exc.reason}"
    except Exception as exc:
        return False, f"Could not prepare {tag}: {exc}"
    finally:
        progress.close()


def _smart_ensure_runtime_available(runtime_target):
    """Prepare an explicitly pinned runtime before installer/prefix creation."""
    target = str(runtime_target or "").strip()
    if not target:
        return True, "no-runtime-pin"
    if _smart_exact_ge_proton_tag(target):
        return _smart_ensure_exact_ge_proton(target)
    # The generic 'ge-proton' sentinel is intentionally left to Lutris/UMU,
    # while ordinary published Wine builds remain Lutris' responsibility.
    return True, "managed-by-lutris"


def _smart_note_constraints(installer):
    notes = str(installer.get("notes") or "")
    low = notes.casefold()
    out = {
        "requires_special_wine": False,
        "min_dxvk": "",
        "intro_danger": False,
        "notes": notes,
    }
    if any(x in low for x in ("wine-ge", "wine-tkg", "lutris wine", "proton required", "proton is required")):
        out["requires_special_wine"] = True
    patterns = (
        r"dxvk\s+versions?\s+lower\s+than\s+([0-9]+(?:\.[0-9]+){1,3})",
        r"dxvk[^\n\r]{0,45}(?:>=|at least|minimum(?: version)?)\s*([0-9]+(?:\.[0-9]+){1,3})",
    )
    for pattern in patterns:
        m = re.search(pattern, low, re.I)
        if m:
            out["min_dxvk"] = m.group(1)
            break
    if "intro video" in low and any(x in low for x in ("break your prefix", "do not enable intro", "don't enable intro", "black screen")):
        out["intro_danger"] = True
    return out


def _smart_match_override(game, installer):
    slug = str(game.get("slug") or installer.get("game_slug") or "").casefold()
    rule = SMART_COMPAT_OVERRIDES.get(slug)
    if not rule:
        return None
    text = _smart_recipe_text(installer).casefold()
    needles = tuple(str(x).casefold() for x in (rule.get("installer_contains") or ()))
    if needles and not any(x in text for x in needles):
        return None
    return dict(rule)


def _smart_append_launch_args(script, additions):
    game = script.setdefault("game", {})
    if not isinstance(game, dict):
        return []
    existing = str(game.get("args") or "").strip()
    try:
        tokens = shlex.split(existing) if existing else []
    except Exception:
        tokens = existing.split()
    changed = []
    for item in additions or ():
        item = str(item).strip()
        if item and item not in tokens:
            tokens.append(item)
            changed.append(item)
    game["args"] = " ".join(tokens)
    return changed


def _smart_resolve_runtime(game, installer):
    """Resolve vague Lutris notes into an explicit per-game runtime configuration."""
    data = json.loads(json.dumps(installer))
    script = data.get("script")
    if not isinstance(script, dict):
        return data, {"status": "unchanged", "reason": "No script dictionary"}

    constraints = _smart_note_constraints(data)
    override = _smart_match_override(game, data)
    wine_cfg = script.setdefault("wine", {}) if str(data.get("runner") or "").casefold() == "wine" else {}
    if not isinstance(wine_cfg, dict):
        wine_cfg = {}
        script["wine"] = wine_cfg

    explicit_wine = str(wine_cfg.get("version") or "").strip()
    target_wine = explicit_wine
    reason = "Published Lutris recipe already pins a Wine runtime." if explicit_wine else ""

    if override and override.get("preferred_wine"):
        target_wine = str(override["preferred_wine"])
        reason = str(override.get("reason") or "OneClick compatibility override")
    elif not target_wine and constraints.get("requires_special_wine"):
        # 'ge-proton' is Lutris' UMU-managed GE-Proton sentinel. Current Lutris
        # can fetch/manage it on demand; this prevents silently falling back to
        # distro/system Wine when the recipe explicitly requires GE/Proton.
        target_wine = "ge-proton"
        reason = "Recipe notes require Wine-GE/Wine-TKG/Lutris Wine/Proton; selected Lutris' UMU-managed GE-Proton instead of system Wine."

    min_dxvk = str((override or {}).get("min_dxvk") or constraints.get("min_dxvk") or "").strip()
    if target_wine:
        wine_cfg["version"] = target_wine
    if min_dxvk:
        wine_cfg["dxvk"] = True
        # GE-Proton ships its own current DXVK. For ordinary Wine recipes, pin
        # the minimum requested by the recipe so Lutris cannot use an older one.
        if not ("proton" in target_wine.casefold() if target_wine else False):
            current = str(wine_cfg.get("dxvk_version") or "").strip()
            if not current or _smart_version_lt(current, min_dxvk):
                wine_cfg["dxvk_version"] = min_dxvk

    appended = _smart_append_launch_args(script, (override or {}).get("append_args") or ())
    arch = _smart_recipe_arch(data)
    verbs = _smart_recipe_winetricks(data)
    warnings = []
    if arch == "win64" and any(v.casefold() == "wmp9" for v in verbs):
        warnings.append(
            "wmp9 is being installed in a win64 prefix; Winetricks may warn that wm9codecs itself is unavailable in win64. This is diagnostic, not automatically fatal."
        )
    if target_wine and target_wine.casefold() == "system":
        warnings.append("System Wine remained selected even though Smart mode was active.")

    report = {
        "status": "resolved",
        "runtime_target": target_wine,
        "runtime_reason": reason,
        "published_runtime": explicit_wine,
        "min_dxvk": min_dxvk,
        "dxvk_config": {k: wine_cfg.get(k) for k in ("dxvk", "dxvk_version") if k in wine_cfg},
        "arch": arch,
        "winetricks_verbs": verbs,
        "append_args": appended,
        "notes_require_special_wine": bool(constraints.get("requires_special_wine")),
        "intro_danger": bool(constraints.get("intro_danger")),
        "override": override or {},
        "preflight_warnings": warnings,
    }
    return data, report


def _smart_write_plan(game, installer, game_score, installer_score, stats, bound_file, script_path, compatibility=None, install_log=""):
    plan = {
        "created_at": int(time.time()),
        "game": {"name": game.get("name"), "slug": game.get("slug"), "score": round(game_score, 1)},
        "installer": {
            "version": installer.get("version"), "slug": installer.get("slug") or installer.get("installer_slug"),
            "runner": installer.get("runner"), "score": round(installer_score, 1), "stats": stats,
        },
        "clicked_file_auto_bound": bool(bound_file),
        "local_recipe": str(script_path),
        "install_log": str(install_log or ""),
        "compatibility": compatibility or {},
    }
    try:
        SMART_LUTRIS_LOG.write_text(json.dumps(plan, indent=2), encoding="utf-8")
        SMART_RUNTIME_LOG.write_text(json.dumps(plan.get("compatibility") or {}, indent=2), encoding="utf-8")
    except Exception:
        pass
    return plan


def _game_directory_for_id(game_id):
    db = database_path()
    if not db:
        return None
    try:
        conn = sqlite3.connect(db)
        try:
            row = conn.execute("SELECT directory FROM games WHERE id = ?", (str(game_id),)).fetchone()
            return Path(os.path.expanduser(row[0])).resolve(strict=False) if row and row[0] else None
        finally:
            conn.close()
    except Exception:
        return None


def _smart_apply_write_config_fallback(game_id, plan_path):
    """Re-apply explicit Lutris write_config directives if a completed install missed one."""
    try:
        plan = json.loads(Path(plan_path).read_text(encoding="utf-8"))
        recipe_path = Path(plan.get("local_recipe") or "")
        recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
        script = recipe.get("script") or {}
    except Exception:
        return []
    gamedir = _game_directory_for_id(game_id)
    if not gamedir:
        return []
    actions = []
    for item in script.get("installer") or []:
        if not isinstance(item, dict) or not isinstance(item.get("write_config"), dict):
            continue
        cfg = item["write_config"]
        file_text = str(cfg.get("file") or "")
        section = str(cfg.get("section") or "")
        key = str(cfg.get("key") or "")
        value = str(cfg.get("value") or "")
        if not (file_text and section and key):
            continue
        file_text = file_text.replace("$GAMEDIR", str(gamedir)).replace("$USER", os.environ.get("USER", "deck"))
        target = Path(file_text)
        try:
            existing = target.read_text(encoding="utf-8", errors="replace") if target.exists() else ""
            pattern = re.compile(r"(?im)^\s*" + re.escape(key) + r"\s*=\s*" + re.escape(value) + r"\s*$")
            if pattern.search(existing):
                actions.append({"file": str(target), "key": key, "status": "verified"})
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            parser = configparser.RawConfigParser(strict=False)
            parser.optionxform = str
            if existing:
                try:
                    parser.read_string(existing)
                except Exception:
                    parser = configparser.RawConfigParser(strict=False)
                    parser.optionxform = str
            if not parser.has_section(section):
                parser.add_section(section)
            parser.set(section, key, value)
            with target.open("w", encoding="utf-8") as fh:
                parser.write(fh, space_around_delimiters=False)
            actions.append({"file": str(target), "key": key, "status": "reapplied"})
        except Exception as exc:
            actions.append({"file": str(target), "key": key, "status": "failed", "error": str(exc)})
    if actions:
        try:
            report = dict(plan)
            report["post_install_write_config"] = actions
            Path(plan_path).write_text(json.dumps(report, indent=2), encoding="utf-8")
            SMART_LUTRIS_LOG.write_text(json.dumps(report, indent=2), encoding="utf-8")
        except Exception:
            pass
    return actions


def _smart_lutris_game_config_record(game_id):
    """Return runner/config metadata without importing Lutris' GUI stack.

    V7.0.3 used ``from lutris.game import Game`` in a background Flatpak
    process. On current Lutris/SteamOS that can initialize GTK/display modules,
    which is unsafe when the watcher is headless (Gaming Mode, no Xauthority,
    or a different GTK major already loaded). The SQLite row + YAML file are
    the authoritative persisted state we actually need here.
    """
    db = database_path()
    if not db:
        return None
    try:
        conn = sqlite3.connect(db)
        try:
            row = conn.execute(
                "SELECT runner, configpath, directory, installed, name FROM games WHERE id = ?",
                (str(game_id),),
            ).fetchone()
        finally:
            conn.close()
    except Exception:
        return None
    if not row:
        return None
    return {
        "runner": str(row[0] or ""),
        "configpath": str(row[1] or ""),
        "directory": str(row[2] or ""),
        "installed": bool(row[3]),
        "name": str(row[4] or ""),
    }


def _smart_lutris_game_config_path(game_id):
    record = _smart_lutris_game_config_record(game_id)
    if not record or not record.get("configpath"):
        return None, record

    config_id = str(record["configpath"]).strip()
    raw = Path(os.path.expanduser(config_id))
    candidates = []
    if raw.is_absolute():
        candidates.extend([raw, raw.with_suffix(".yml") if not raw.suffix else raw])
    else:
        # Flatpak Lutris uses XDG_CONFIG_HOME inside ~/.var/app/...; native
        # Lutris locations are retained as fallbacks for portability.
        # Lutris may persist game YAML below either XDG_CONFIG_HOME or
        # XDG_DATA_HOME.  Flatpak builds commonly keep pga.db in
        # ~/.var/app/net.lutris.Lutris/data/lutris, and settings.py can fall
        # back to that same data directory for CONFIG_DIR.  V7.0.4 only
        # searched the config-side path, which caused a false "config not
        # ready" result even though the installed game was fully playable.
        bases = []
        try:
            db = database_path()
            if db:
                bases.append(Path(db).resolve().parent / "games")
        except Exception:
            pass
        bases.extend([
            Path.home() / ".var/app/net.lutris.Lutris/config/lutris/games",
            Path.home() / ".var/app/net.lutris.Lutris/data/lutris/games",
            Path.home() / ".config/lutris/games",
            Path.home() / ".local/share/lutris/games",
        ])
        seen_bases = set()
        for base in bases:
            base_key = str(base)
            if base_key in seen_bases:
                continue
            seen_bases.add(base_key)
            candidates.append(base / config_id)
            if not config_id.endswith((".yml", ".yaml")):
                candidates.append(base / f"{config_id}.yml")
                candidates.append(base / f"{config_id}.yaml")

    seen = set()
    for candidate in candidates:
        key = str(candidate)
        if key in seen:
            continue
        seen.add(key)
        if candidate.is_file():
            return candidate, record
    return None, record


def _smart_yaml_decode_scalar(value):
    value = str(value or "").strip()
    if not value:
        return ""
    # Remove comments only for plain scalars. Quoted JSON/YAML strings may
    # legitimately contain '#'.
    if value.startswith('"'):
        try:
            return json.loads(value)
        except Exception:
            return value.strip('"')
    if value.startswith("'") and value.endswith("'") and len(value) >= 2:
        return value[1:-1].replace("''", "'")
    value = re.split(r"\s+#", value, maxsplit=1)[0].strip()
    low = value.casefold()
    if low in {"true", "yes", "on"}:
        return True
    if low in {"false", "no", "off"}:
        return False
    if low in {"null", "none", "~"}:
        return None
    return value


def _smart_yaml_format_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    # JSON double-quoted strings are valid YAML scalars and avoid edge cases
    # with ':', '#', paths and command-line arguments.
    return json.dumps(str(value), ensure_ascii=False)


def _smart_yaml_section_bounds(lines, section):
    section_re = re.compile(r"^" + re.escape(str(section)) + r"\s*:\s*(?:\{\s*\})?\s*(?:#.*)?$")
    start = None
    for i, line in enumerate(lines):
        if line[:1].isspace() or line.lstrip().startswith("#"):
            continue
        if section_re.match(line.rstrip("\n")):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    top_level = re.compile(r"^[A-Za-z0-9_.-]+\s*:")
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[:1].isspace() and top_level.match(line):
            end = i
            break
    return start, end


def _smart_yaml_get_scalar(text, section, key):
    lines = str(text or "").splitlines(True)
    bounds = _smart_yaml_section_bounds(lines, section)
    if not bounds:
        return None
    start, end = bounds
    key_re = re.compile(r"^\s+" + re.escape(str(key)) + r"\s*:\s*(.*?)\s*$")
    for i in range(start + 1, end):
        m = key_re.match(lines[i].rstrip("\n"))
        if m:
            return _smart_yaml_decode_scalar(m.group(1))
    return None


def _smart_yaml_set_scalar(text, section, key, value):
    lines = str(text or "").splitlines(True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    bounds = _smart_yaml_section_bounds(lines, section)
    formatted = _smart_yaml_format_scalar(value)
    if not bounds:
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.extend([f"{section}:\n", f"  {key}: {formatted}\n"])
        return "".join(lines)

    start, end = bounds
    # An inline empty mapping ("wine: {}") must become a normal mapping before
    # inserting a child key.
    if re.search(r":\s*\{\s*\}\s*(?:#.*)?$", lines[start].rstrip("\n")):
        lines[start] = f"{section}:\n"

    key_re = re.compile(r"^(\s+)" + re.escape(str(key)) + r"\s*:")
    child_indent = "  "
    for i in range(start + 1, end):
        if lines[i].strip() and lines[i][:1].isspace() and not lines[i].lstrip().startswith("#"):
            child_indent = re.match(r"^(\s+)", lines[i]).group(1)
            break
    for i in range(start + 1, end):
        m = key_re.match(lines[i])
        if m:
            lines[i] = f"{m.group(1)}{key}: {formatted}\n"
            return "".join(lines)
    lines.insert(end, f"{child_indent}{key}: {formatted}\n")
    return "".join(lines)


def _smart_write_lutris_yaml_atomic(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + f".oneclick-{os.getpid()}.tmp")
    old_mode = None
    try:
        if path.exists():
            old_mode = path.stat().st_mode & 0o777
    except Exception:
        pass
    temp.write_text(text, encoding="utf-8")
    if old_mode is not None:
        try:
            os.chmod(temp, old_mode)
        except Exception:
            pass
    os.replace(temp, path)


def _smart_game_runtime_state(game_id):
    """Read final game state directly from Lutris' persisted YAML.

    This intentionally does *not* import ``lutris.game`` and therefore works
    from the background watcher in Desktop Mode, Gaming Mode and headless
    sessions without GTK/glxinfo/Xauthority side effects.
    """
    path, record = _smart_lutris_game_config_path(game_id)
    if not record:
        return {"ok": False, "error": "Lutris game database row was not found."}
    if not path:
        return {
            "ok": False,
            "error": "Lutris game YAML has not been written yet.",
            "runner": record.get("runner"),
            "configpath": record.get("configpath"),
        }
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        runner = str(record.get("runner") or "wine")
        return {
            "ok": True,
            "runner": runner,
            "version": _smart_yaml_get_scalar(text, runner, "version"),
            "dxvk": _smart_yaml_get_scalar(text, runner, "dxvk"),
            "dxvk_version": _smart_yaml_get_scalar(text, runner, "dxvk_version"),
            "arch": _smart_yaml_get_scalar(text, "game", "arch"),
            "args": _smart_yaml_get_scalar(text, "game", "args"),
            "prefix": _smart_yaml_get_scalar(text, "game", "prefix") or record.get("directory"),
            "exe": _smart_yaml_get_scalar(text, "game", "exe"),
            "config_file": str(path),
        }
    except Exception as exc:
        return {"ok": False, "error": f"Could not read Lutris game YAML: {exc}", "config_file": str(path)}

def _smart_wait_game_runtime_state(game_id, timeout=45, settle_reads=2):
    """Wait until Lutris has flushed a usable per-game config after install.

    The database can report installed=1 a few seconds before the game YAML is
    fully readable. V7.0.2 validated too early in that window and could report
    a missing runtime/argument even though Lutris was still finishing its save.
    """
    deadline = time.time() + max(1, int(timeout))
    last = {"ok": False, "error": "Lutris game config is not ready yet."}
    good_reads = 0
    while time.time() < deadline:
        state = _smart_game_runtime_state(game_id)
        last = state
        if state.get("ok") and (state.get("exe") or state.get("prefix")):
            good_reads += 1
            if good_reads >= max(1, int(settle_reads)):
                return state
        else:
            good_reads = 0
        time.sleep(1.5)
    return last


def _smart_repair_game_runtime(game_id, compatibility):
    """Apply safe Smart fixes directly to the finished per-game YAML.

    Importing Lutris' Python Game object from a detached watcher caused GTK 3/4
    and DISPLAY authorization failures on current SteamOS. Persisted game YAML
    is the correct boundary for this small repair: only the exact runner,
    DXVK policy and explicit launch arguments selected by Smart are changed.
    """
    path, record = _smart_lutris_game_config_path(game_id)
    if not record:
        return {"ok": False, "error": "Lutris game database row was not found."}
    if not path:
        return {"ok": False, "error": "Lutris has not written the final game YAML yet."}

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        runner = str(record.get("runner") or "wine")
        wanted_version = str(compatibility.get("runtime_target") or "").strip()
        min_dxvk = str(compatibility.get("min_dxvk") or "").strip()
        additions = [str(x).strip() for x in (compatibility.get("append_args") or []) if str(x).strip()]
        changed = []

        if wanted_version:
            current = _smart_yaml_get_scalar(text, runner, "version")
            if not _smart_versions_equivalent(current, wanted_version):
                text = _smart_yaml_set_scalar(text, runner, "version", wanted_version)
                changed.append(f"{runner}.version={wanted_version}")

        if min_dxvk:
            current_dxvk = _smart_yaml_get_scalar(text, runner, "dxvk")
            if current_dxvk is not True:
                text = _smart_yaml_set_scalar(text, runner, "dxvk", True)
                changed.append(f"{runner}.dxvk=true")
            # Proton bundles DXVK; ordinary Wine can additionally be pinned to
            # the recipe's minimum DXVK version.
            if "proton" not in wanted_version.casefold():
                current_version = str(_smart_yaml_get_scalar(text, runner, "dxvk_version") or "")
                if not current_version or _smart_version_lt(current_version, min_dxvk):
                    text = _smart_yaml_set_scalar(text, runner, "dxvk_version", min_dxvk)
                    changed.append(f"{runner}.dxvk_version={min_dxvk}")

        if additions:
            current_args = str(_smart_yaml_get_scalar(text, "game", "args") or "").strip()
            try:
                tokens = shlex.split(current_args) if current_args else []
            except Exception:
                tokens = current_args.split()
            for item in additions:
                if item not in tokens:
                    tokens.append(item)
                    changed.append(f"game.args+={item}")
            text = _smart_yaml_set_scalar(text, "game", "args", " ".join(tokens))

        if changed:
            _smart_write_lutris_yaml_atomic(path, text)

        verify = _smart_game_runtime_state(game_id)
        return {
            "ok": bool(verify.get("ok")),
            "changed": changed,
            "config_file": str(path),
            "state": verify,
            "error": "" if verify.get("ok") else str(verify.get("error") or "Verification failed"),
        }
    except Exception as exc:
        return {"ok": False, "error": f"Could not repair Lutris YAML: {exc}", "config_file": str(path)}

def _smart_classify_install_log(log_text, compatibility, installation_completed=False):
    low = str(log_text or "").casefold()
    findings = []
    expected = tuple(str(x).casefold() for x in ((compatibility.get("override") or {}).get("expected_nonfatal_log") or ()))

    def add(severity, code, text):
        findings.append({"severity": severity, "code": code, "message": text})

    if "you appear to be using wine's new wow64 mode" in low and "experimental" in low:
        add("warning", "experimental-wow64", "Wine's experimental new WoW64 mode was used during installation.")
    if "wm9codecs is not supported in win64 prefixes" in low:
        sev = "expected" if any(x in low for x in expected if "wm9codecs" in x) else "warning"
        add(sev, "wm9codecs-win64", "Winetricks reports wm9codecs is unavailable in a win64 prefix.")
    if "you are using a 64-bit wineprefix" in low:
        add("info", "win64-verb-note", "Winetricks emitted its generic 64-bit-prefix compatibility note.")

    target = str(compatibility.get("runtime_target") or "")
    if target and target.casefold() not in {"ge-proton", "system"}:
        # This remains critical: changing the final runner afterwards cannot undo
        # a prefix that was actually created/configured using a forbidden runtime.
        if re.search(r"\bwith\s+wine-(?:10|11)(?:\.|\s|$)", low) or "wine version: system" in low:
            add("critical", "runtime-mismatch", f"Installer used system/new Wine instead of pinned {target}.")

    explicit_install_failure = any(
        marker in low
        for marker in (
            "last install command failed",
            "error while completing task",
            "installation failed",
            "installer failed",
            "failed to install",
        )
    )

    nonzero = []
    for match in re.finditer(r"(?:exit with return code|return code:)\s*(-?\d+)", low):
        try:
            rc = int(match.group(1))
        except Exception:
            continue
        if rc != 0 and rc not in nonzero:
            nonzero.append(rc)

    if nonzero:
        codes = ", ".join(str(x) for x in nonzero[:4])
        if explicit_install_failure or not installation_completed:
            add("critical", "nonzero-exit", f"Installer reported non-zero return code(s): {codes}.")
        else:
            # Lutris/GLib can surface child wait statuses such as 256 even after
            # the installer has completed and the game has been committed to the
            # library. Do not fail a completed installation on this line alone.
            add("warning", "nonzero-exit-observed", f"Installer log contains non-zero child status(es) {codes}, but Lutris marked the game installed; validating the resulting game configuration instead.")

    return findings


def _smart_post_install_validate(game_id, plan_path):
    """Wait for Lutris' final save, repair safe settings, then validate Ready state."""
    try:
        plan_path = Path(plan_path)
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return False, {"ok": False, "error": f"Could not read Smart plan: {exc}"}

    compatibility = dict(plan.get("compatibility") or {})

    # installed=1 can appear before Lutris' YAML/config is fully flushed. Wait
    # for a stable readable config before deciding that the runtime/args vanished.
    state = _smart_wait_game_runtime_state(game_id, timeout=45, settle_reads=2)
    target = str(compatibility.get("runtime_target") or "").strip()
    append_args = [str(x) for x in (compatibility.get("append_args") or []) if str(x).strip()]

    def state_needs_repair(current):
        if not current.get("ok"):
            return True
        if target and not _smart_versions_equivalent(current.get("version"), target):
            return True
        current_args = str(current.get("args") or "")
        if append_args and any(x not in current_args.split() for x in append_args):
            return True
        return False

    repair_attempts = []
    if state_needs_repair(state):
        # A safe repair only changes the selected per-game runner, enables the
        # required DXVK policy and appends explicit launch arguments. Retry a few
        # times because Lutris may still be replacing the just-installed YAML.
        for attempt in range(1, 4):
            repair = _smart_repair_game_runtime(game_id, compatibility)
            repair_attempts.append({"attempt": attempt, **(repair if isinstance(repair, dict) else {"result": str(repair)})})
            time.sleep(1.5)
            state = _smart_wait_game_runtime_state(game_id, timeout=12, settle_reads=1)
            if not state_needs_repair(state):
                break

    # installed=1 in pga.db is the authoritative installation-status flag.
    # Do not turn a harmless GLib child wait status (notably 256) into a fatal
    # installer error merely because our YAML lookup is temporarily unavailable.
    record = _smart_lutris_game_config_record(game_id) or {}
    installation_completed = bool(record.get("installed")) or bool(
        state.get("ok") and (state.get("exe") or state.get("prefix"))
    )
    findings = []
    log_path = Path(plan.get("install_log") or "") if plan.get("install_log") else None
    if log_path and log_path.is_file():
        try:
            findings = _smart_classify_install_log(
                log_path.read_text(encoding="utf-8", errors="replace"),
                compatibility,
                installation_completed=installation_completed,
            )
        except Exception:
            findings = []

    critical = [x for x in findings if x.get("severity") == "critical"]
    if not state.get("ok"):
        critical.append({
            "severity": "critical",
            "code": "config-not-ready",
            "message": "Lutris did not expose a readable final game configuration after waiting/retrying.",
        })
    if target and (not state.get("ok") or not _smart_versions_equivalent(state.get("version"), target)):
        extra = ""
        if repair_attempts:
            last = repair_attempts[-1]
            if last.get("error"):
                extra = f" Repair error: {last.get('error')}"
        critical.append({
            "severity": "critical",
            "code": "runtime-not-applied",
            "message": f"Required runtime {target} is not active in the installed game config.{extra}",
        })
    if append_args:
        final_args = str(state.get("args") or "") if state.get("ok") else ""
        missing = [x for x in append_args if x not in final_args.split()]
        if missing:
            critical.append({
                "severity": "critical",
                "code": "launch-args-missing",
                "message": "Required launch fix is missing after repair: " + " ".join(missing),
            })

    report = {
        "ok": not critical,
        "runtime_state": state,
        "repair_attempts": repair_attempts,
        "install_log_findings": findings,
        "critical": critical,
        "validated_at": int(time.time()),
    }
    plan["post_install_validation"] = report
    try:
        plan_path.write_text(json.dumps(plan, indent=2), encoding="utf-8")
        SMART_LUTRIS_LOG.write_text(json.dumps(plan, indent=2), encoding="utf-8")
    except Exception:
        pass
    return not critical, report


def install_new_smart_lutris(exe: Path, game_name=None, storage_path=""):
    if not game_name:
        game_name = derive_default_name(exe)
    query = str(game_name or derive_default_name(exe)).strip()
    hints = [query, exe.stem, exe.parent.name]
    if exe.parent.parent != exe.parent:
        hints.append(exe.parent.parent.name)

    search = _flatpak_lutris_api("search", query)
    games = search.get("results") if search.get("ok") else []
    if not games:
        subprocess.run(["kdialog", "--passivepopup", "Smart Lutris could not find a reliable online recipe. Using the normal local Lutris installer instead.", "6"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return install_new_lutris(exe, game_name=game_name, storage_path=storage_path)

    game, game_score = _smart_choose_game(query, games)
    if not game:
        return
    installers_response = _flatpak_lutris_api("installers", str(game.get("slug") or ""))
    installers = installers_response.get("results") if installers_response.get("ok") else []
    if not installers:
        subprocess.run(["kdialog", "--passivepopup", f"No usable Lutris recipe was returned for {game.get('name', query)}. Using the normal local Lutris installer instead.", "6"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return install_new_lutris(exe, game_name=game_name, storage_path=storage_path)

    selected, installer_score, stats = _smart_choose_installer(game, installers, hints)
    if not selected:
        return
    selected, bound_file = _smart_bind_clicked_installer(selected, exe)

    # V7.2.5: selecting the best YAML is only the first half. Resolve vague
    # Notes into an explicit runtime/DXVK/launch policy BEFORE prefix creation.
    selected, compatibility = _smart_resolve_runtime(game, selected)

    # If Smart pins an exact historical GE-Proton build, make sure it actually
    # exists before Lutris creates the prefix. Never silently fall back to
    # System Wine when the compatibility resolver selected a known-good build.
    runtime_target = str(compatibility.get("runtime_target") or "").strip()
    runtime_ok, runtime_status = _smart_ensure_runtime_available(runtime_target)
    compatibility["runtime_prepare_status"] = runtime_status
    if not runtime_ok:
        subprocess.run(
            [
                "kdialog", "--error",
                f"Smart Automatic could not prepare the required runtime {runtime_target or '(unspecified)'}.\n\n{runtime_status}\n\nThe game was not installed, so OneClick did not create a prefix with the wrong Wine version.",
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            SMART_RUNTIME_LOG.write_text(json.dumps(compatibility, indent=2), encoding="utf-8")
        except Exception:
            pass
        return

    if storage_path:
        try:
            _ensure_lutris_external_access(storage_path)
            real_external_prefix = _external_game_folder(
                storage_path, "lutris", str(game.get("name") or game_name),
                str(game.get("slug") or game_name),
            )
            external_prefix, storage_uuid = _stable_external_path(real_external_prefix, storage_path)
            script = selected.setdefault("script", {})
            if not isinstance(script, dict):
                raise RuntimeError("The selected Lutris recipe has an invalid script section.")
            game_cfg = script.setdefault("game", {})
            if not isinstance(game_cfg, dict):
                raise RuntimeError("The selected Lutris recipe has an invalid game section.")
            # Keep the full Wine prefix on the selected external drive. Steam's
            # shortcut for a Lutris-backed game still launches through the host
            # wrapper, so Desktop and Gaming Mode use this same Lutris prefix.
            game_cfg["prefix"] = str(external_prefix)

            def bind_external_gamedir(value):
                if isinstance(value, dict):
                    return {k: bind_external_gamedir(v) for k, v in value.items()}
                if isinstance(value, list):
                    return [bind_external_gamedir(v) for v in value]
                if isinstance(value, str):
                    return value.replace("$GAMEDIR", str(external_prefix))
                return value

            selected = bind_external_gamedir(selected)
            compatibility["storage_mode"] = "external"
            compatibility["storage_root"] = str(storage_path)
            compatibility["storage_uuid"] = str(storage_uuid)
            compatibility["external_prefix"] = str(external_prefix)
        except Exception as exc:
            subprocess.run(
                ["kdialog", "--error", f"External Lutris storage could not be prepared.\n\n{exc}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            return

    selected_slug = str(selected.get("slug") or selected.get("installer_slug") or "smart-installer")
    stamp = int(time.time())
    clean_slug = re.sub(r"[^a-z0-9]+", "-", selected_slug.casefold()).strip("-") or "smart-installer"
    local_recipe = CACHE_DIR / f"smart-{clean_slug}-{stamp}.yml"
    local_recipe.write_text(json.dumps(selected, indent=2), encoding="utf-8")
    install_log = CACHE_DIR / f"smart-install-{clean_slug}-{stamp}.log"
    plan_path = CACHE_DIR / f"smart-plan-{stamp}.json"
    plan = _smart_write_plan(
        game, selected, game_score, installer_score, stats, bound_file,
        local_recipe, compatibility=compatibility, install_log=install_log,
    )
    plan_path.write_text(json.dumps(plan, indent=2), encoding="utf-8")

    min_game_id = get_max_game_id()
    force_steam_shortcut_default_on()
    version = str(selected.get("version") or selected_slug)
    detail_bits = []
    if stats.get("winetricks"):
        detail_bits.append(f"{stats['winetricks']} dependency/config task(s)")
    if stats.get("write_config"):
        detail_bits.append(f"{stats['write_config']} compatibility config fix(es)")
    if compatibility.get("runtime_target"):
        detail_bits.append(f"runtime {compatibility['runtime_target']}")
    if compatibility.get("min_dxvk"):
        detail_bits.append(f"DXVK >= {compatibility['min_dxvk']}")
    detail = ", ".join(detail_bits) or "published Lutris compatibility recipe"
    subprocess.run(
        ["kdialog", "--passivepopup", f"Smart Lutris selected: {game.get('name', query)} → {version}\nUsing {detail}.", "8"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    # Remember whether the user already had the normal Lutris client open.
    # If not, the watcher may safely close OneClick's temporary installer
    # instance once installation/validation has finished.
    lutris_was_running_before = lutris_is_running()
    child_env = _clean_child_env()
    try:
        log_handle = open(install_log, "a", encoding="utf-8")
        subprocess.Popen(
            ["flatpak", "run", APP_ID, "-i", str(local_recipe)],
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            close_fds=True,
            env=child_env,
        )
        log_handle.close()
    except Exception:
        subprocess.Popen(
            ["flatpak", "run", APP_ID, "-i", str(local_recipe)],
            start_new_session=True,
            close_fds=True,
            env=child_env,
        )
    final_game_name = str(game.get("name") or game_name)
    launch_install_watcher(
        selected_slug,
        final_game_name,
        min_game_id,
        str(plan_path),
        lutris_was_running_before,
    )
    return {
        "ok": True, "launched": True, "action": "install", "backend": "smart",
        "config_prefix": str(selected_slug), "game_name": final_game_name,
        "min_game_id": int(min_game_id),
    }

def install_new_lutris(exe: Path, game_name=None, storage_path=""):
    if not game_name:
        game_name = dialog([
            "--inputbox",
            "Detected game name (edit if needed):",
            derive_default_name(exe),
        ])
    if not game_name:
        return

    slug = re.sub(r"[^a-z0-9]+", "-", game_name.lower()).strip("-") or "local-game"
    stamp = int(time.time())
    prefix_value = "$GAMEDIR"
    if storage_path:
        try:
            _ensure_lutris_external_access(storage_path)
            real_external_prefix = _external_game_folder(storage_path, "lutris", game_name, slug)
            external_prefix, _storage_uuid = _stable_external_path(real_external_prefix, storage_path)
            prefix_value = str(external_prefix)
        except Exception as exc:
            error(f"External Lutris storage could not be prepared:\n\n{exc}")
            return

    installer = {
        "name": game_name,
        "game_slug": slug,
        "version": "Local setup",
        "slug": f"{slug}-local-{stamp}",
        "runner": "wine",
        "script": {
            "game": {
                "exe": "_xXx_AUTO_WIN32_xXx_",
                "prefix": prefix_value,
            },
            "installer": [
                {
                    "task": {
                        "name": "wineexec",
                        "executable": str(exe),
                        "working_dir": str(exe.parent),
                        "arch": "win64",
                    }
                }
            ],
        },
    }

    installer_file = CACHE_DIR / f"{slug}-{stamp}.yml"
    installer_file.write_text(json.dumps(installer, indent=2), encoding="utf-8")

    # Remember where the database was before this install so the background
    # watcher can reliably identify the game that THIS installer creates.
    min_game_id = get_max_game_id()

    # Keep Lutris' normal checkbox enabled too.
    force_steam_shortcut_default_on()

    lutris_was_running_before = lutris_is_running()
    subprocess.Popen(
        ["flatpak", "run", APP_ID, "-i", str(installer_file)],
        start_new_session=True,
        close_fds=True,
        env=_clean_child_env(),
    )

    # After the installation is actually marked complete by Lutris, offer to
    # create/repair the Steam shortcut and clean up only the transient Lutris
    # instance that this installation started.
    unique_prefix = f"{slug}-local-{stamp}"
    launch_install_watcher(
        unique_prefix,
        game_name,
        min_game_id,
        "",
        lutris_was_running_before,
    )
    return {
        "ok": True, "launched": True, "action": "install", "backend": "lutris",
        "config_prefix": str(unique_prefix), "game_name": str(game_name),
        "min_game_id": int(min_game_id),
    }


def list_installed_wine_games():
    db = database_path()
    if not db:
        return []
    conn = sqlite3.connect(db)
    try:
        return conn.execute(
            """
            SELECT id, name
            FROM games
            WHERE installed = 1
              AND runner = 'wine'
              AND configpath IS NOT NULL
              AND configpath != ''
            ORDER BY name COLLATE NOCASE
            """
        ).fetchall()
    finally:
        conn.close()


def run_existing_lutris(exe: Path, selected_game_id=None):
    if not database_path():
        error("Could not find the Lutris game database.\n\nOpen Lutris once, close it, and try again.")
        return

    try:
        games = list_installed_wine_games()
    except Exception as exc:
        error(f"Could not read Lutris game list:\n\n{exc}")
        return

    if not games:
        error("No installed Lutris Wine games were found.")
        return

    by_id = {str(game_id): name for game_id, name in games}
    if selected_game_id is not None:
        game_id = str(selected_game_id)
        if game_id not in by_id:
            error("The selected Lutris Wine game could not be found.")
            return
    else:
        args = ["--menu", "Run this EXE inside which Lutris game?"]
        for game_id, name in games:
            args.extend([str(game_id), name])
        game_id = dialog(args)
        if not game_id:
            return

    inside_flatpak = r'''
import os
import sys
import traceback

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

wrapper = "/app/share/lutris/bin/lutris-wrapper"
if not os.path.isfile(wrapper):
    raise FileNotFoundError(f"Expected Lutris wrapper was not found at {wrapper}")

sys.argv[0] = "/app/bin/lutris"

from lutris.game import Game
from lutris.runners.commands.wine import wineexec

game_id = sys.argv[1]
exe = os.path.abspath(sys.argv[2])

try:
    game = Game(game_id)

    if not game.is_installed:
        raise RuntimeError("Selected game is not installed.")
    if game.runner_name != "wine":
        raise RuntimeError("Selected game is not using the Wine runner.")

    runner = game.runner
    if not runner.prefix_path:
        raise RuntimeError("Lutris could not determine this game's Wine prefix.")

    runner.prelaunch()

    wineexec(
        exe,
        wine_path=runner.get_executable(),
        prefix=runner.prefix_path,
        arch=runner.wine_arch,
        working_dir=os.path.dirname(exe),
        config=runner,
        env=runner.get_env(os_env=True),
        runner=runner,
        blocking=True,
    )
except Exception:
    traceback.print_exc()
    sys.exit(1)
'''

    result = subprocess.run(
        [
            "flatpak", "run", "--command=python3", APP_ID, "-c",
            inside_flatpak, str(game_id), str(exe)
        ],
        text=True,
        capture_output=True,
    )

    if result.returncode != 0:
        log_file = CACHE_DIR / "last-update-error.txt"
        log_file.write_text(
            (result.stdout or "") + "\n\nSTDERR:\n" + (result.stderr or ""),
            encoding="utf-8",
        )
        error(
            "The update could not be started.\n\n"
            "I saved the exact technical error here:\n\n"
            f"{log_file}\n\n"
            "Send that file if you need troubleshooting."
        )
        return {"ok": False, "launched": True, "completed": True, "action": "update", "backend": "lutris-update", "detail": "update failed"}
    return {"ok": True, "launched": True, "completed": True, "action": "update", "backend": "lutris-update", "detail": "update completed"}


def install_new(
    exe: Path, game_name=None, backend_override=None, storage_path="", source_iso=False,
    defer_post_install_finalize=False,
):
    backend = str(backend_override or installer_backend()).strip().lower()
    if backend == "smart":
        return install_new_smart_lutris(exe, game_name=game_name, storage_path=storage_path)
    if backend == "lutris":
        return install_new_lutris(exe, game_name=game_name, storage_path=storage_path)
    return install_new_steam(
        exe, game_name=game_name, storage_path=storage_path, source_iso=source_iso,
        defer_post_install_finalize=defer_post_install_finalize,
    )


def run_existing(exe: Path):
    """Choose the installed game's real backend; never guess from the global default."""
    choices = []
    for entry in list_steam_native_games():
        if entry.get("final_exe"):
            choices.append((f"steam:{entry['appid']}", str(entry.get("name") or entry["appid"]), "Steam / Proton"))
    try:
        for game_id, name in list_installed_wine_games():
            choices.append((f"lutris:{game_id}", str(name), "Lutris / Wine"))
    except Exception:
        pass
    if not choices:
        error("No installed One-Click Steam or Lutris games were found.")
        return
    choices.sort(key=lambda x: x[1].casefold())
    args = ["--title", "One-Click Game Update", "--menu", "Run this update / patch inside which installed game?"]
    for key, name, backend in choices:
        args.extend([key, f"{name}  —  {backend}"])
    picked = dialog(args)
    if not picked:
        return
    backend, game_id = picked.split(":", 1)
    if backend == "lutris":
        return run_existing_lutris(exe, game_id)
    return run_existing_steam(exe, game_id)


def lutris_is_running():
    try:
        result = subprocess.run(
            ["flatpak", "ps", "--columns=application"],
            text=True,
            capture_output=True,
        )
        return APP_ID in result.stdout.split()
    except Exception:
        return False


def close_lutris_for_removal(timeout=15):
    """Close the Flatpak Lutris app automatically before editing its database."""
    if not lutris_is_running():
        return True

    try:
        subprocess.run(
            ["flatpak", "kill", APP_ID],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
    except Exception:
        pass

    deadline = time.time() + timeout
    while time.time() < deadline:
        if not lutris_is_running():
            # Give SQLite/config writes a moment to finish settling.
            time.sleep(0.75)
            return True
        time.sleep(0.25)

    return not lutris_is_running()


def list_installed_wine_games_for_removal():
    db = database_path()
    if not db:
        return []

    conn = sqlite3.connect(db)
    try:
        return conn.execute(
            '''
            SELECT id, name, directory
            FROM games
            WHERE installed = 1
              AND runner = 'wine'
              AND directory IS NOT NULL
              AND directory != ''
              AND configpath IS NOT NULL
              AND configpath != ''
            ORDER BY name COLLATE NOCASE
            '''
        ).fetchall()
    finally:
        conn.close()


def safe_game_directory(path_text):
    if not path_text:
        raise RuntimeError("Lutris did not provide a game directory.")

    raw = Path(os.path.expanduser(path_text))
    if not raw.is_absolute():
        raise RuntimeError(f"The game directory is not an absolute path:\\n\\n{raw}")

    if raw.is_symlink():
        raise RuntimeError(
            "The game directory is a symbolic link.\\n\\n"
            "For safety, this helper will not permanently delete symlinked game folders.\\n\\n"
            f"Path:\\n{raw}"
        )

    path = raw.resolve(strict=False)
    home = Path.home().resolve()

    protected = {
        Path("/"),
        Path("/home"),
        Path("/var"),
        Path("/mnt"),
        Path("/media"),
        Path("/run"),
        home,
        home / "Games",
        home / "Desktop",
        home / "Documents",
        home / "Downloads",
        home / "Pictures",
        home / "Videos",
    }

    if path in protected:
        raise RuntimeError(
            "Refusing to delete a protected folder.\\n\\n"
            f"Path:\\n{path}"
        )

    if len(path.parts) < 4:
        raise RuntimeError(
            "Refusing to permanently delete this path because it is too close "
            "to a filesystem root.\\n\\n"
            f"Path:\\n{path}"
        )

    return path


def remove_lutris_entry(game_id):
    inside_flatpak = r'''
import os
import sys
import traceback

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

wrapper = "/app/share/lutris/bin/lutris-wrapper"
if not os.path.isfile(wrapper):
    raise FileNotFoundError(f"Expected Lutris wrapper was not found at {wrapper}")

sys.argv[0] = "/app/bin/lutris"

from lutris.game import Game
from lutris.util.steam import shortcut as steam_shortcut
from lutris.util.steam import vdf as steam_vdf

game_id = sys.argv[1]


def _text(item, key):
    value = item.get(key, "") if isinstance(item, dict) else ""
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    return str(value or "").strip().strip('"')


def _remove_matching_shortcuts(game):
    path = steam_shortcut.get_shortcuts_vdf_path()
    if not path or not os.path.exists(path):
        return []
    try:
        expected = int(steam_shortcut.generate_appid(game)) & 0xffffffff
    except Exception:
        expected = None
    gid = str(game.id or game_id)
    game_name = str(getattr(game, "name", "") or "").strip().casefold()

    with open(path, "rb") as fh:
        root = steam_vdf.binary_loads(fh.read())
    current = list((root.get("shortcuts") or {}).values())
    kept, removed = [], []
    for item in current:
        try:
            sid = int(item.get("appid", 0)) & 0xffffffff
        except Exception:
            sid = 0
        exe = _text(item, "Exe").casefold()
        launch = _text(item, "LaunchOptions")
        launch_low = launch.casefold()
        name = _text(item, "AppName").strip().casefold()
        gid_match = launch == gid or f"rungameid/{gid}" in launch_low or f"rungameid:{gid}" in launch_low
        lutris_signature = (
            "oneclick-lutris-steam-launch" in exe
            or "net.lutris.lutris" in launch_low
            or "lutris:rungameid" in launch_low
            or ("lutris" in exe and gid_match)
        )
        if (expected is not None and sid == expected) or gid_match or (game_name and name == game_name and lutris_signature):
            if sid and sid not in removed:
                removed.append(sid)
            continue
        kept.append(item)

    if len(kept) != len(current):
        updated = {"shortcuts": {str(i): item for i, item in enumerate(kept)}}
        temp = path + f".oneclick-{os.getpid()}.tmp"
        with open(temp, "wb") as fh:
            fh.write(steam_vdf.binary_dumps(updated))
        os.replace(temp, path)

        # Remove Steam grid files for every stale AppID variant as well.
        config_path = steam_shortcut.get_config_path()
        if config_path:
            grid = os.path.join(config_path, "grid")
            if os.path.isdir(grid):
                for sid in removed:
                    for stem in (str(sid), f"{sid}p", f"{sid}_hero", f"{sid}_logo", f"{sid}_icon"):
                        for filename in os.listdir(grid):
                            if filename.startswith(stem + "."):
                                try:
                                    os.unlink(os.path.join(grid, filename))
                                except OSError:
                                    pass
    return removed


try:
    game = Game(game_id)

    # Remove the current Lutris shortcut plus stale OneClick/Lutris shortcut
    # variants before deleting the library record.
    try:
        steam_shortcut.remove_shortcut(game)
    except Exception:
        pass
    _remove_matching_shortcuts(game)

    # delete_files=False deliberately avoids Lutris' Trash operation.
    if game.is_installed:
        game.uninstall(delete_files=False)

    if game.id is not None:
        game.delete()

except Exception:
    traceback.print_exc()
    sys.exit(1)
'''

    return subprocess.run(
        [
            "flatpak", "run", "--command=python3", APP_ID, "-c",
            inside_flatpak, str(game_id)
        ],
        text=True,
        capture_output=True,
    )


def complete_remove():
    # Make the removal tool one-click: if Lutris is open, close it automatically
    # before reading/modifying the game database.
    if not close_lutris_for_removal():
        error(
            "Lutris could not be closed automatically.\\n\\n"
            "Please close Lutris manually and try again."
        )
        return

    if not database_path():
        error("Could not find the Lutris game database.\\n\\nOpen Lutris once, close it, and try again.")
        return

    try:
        games = list_installed_wine_games_for_removal()
    except Exception as exc:
        error(f"Could not read the Lutris game list:\\n\\n{exc}")
        return

    if not games:
        error("No installed Lutris Wine games were found.")
        return

    game_map = {str(game_id): (name, directory) for game_id, name, directory in games}

    args = ["--menu", "Choose the Lutris game to completely remove:"]
    for game_id, name, directory in games:
        args.extend([str(game_id), f"{name}   —   {directory}"])

    game_id = dialog(args)
    if not game_id:
        return

    name, directory = game_map[game_id]

    try:
        game_path = safe_game_directory(directory)
    except Exception as exc:
        error(str(exc))
        return

    first = subprocess.run(
        [
            "kdialog",
            "--warningyesno",
            "Remove this game from Lutris?\\n\\n"
            f"{name}\\n\\n"
            "This will remove its Lutris entry, configuration and Steam shortcut.\\n\\n"
            f"Game folder:\\n{game_path}\\n\\n"
            "The game files will NOT be deleted until you confirm a second time."
        ]
    )
    if first.returncode != 0:
        return

    result = remove_lutris_entry(game_id)

    if result.returncode != 0:
        log_file = CACHE_DIR / "last-remove-error.txt"
        log_file.write_text(
            (result.stdout or "") + "\\n\\nSTDERR:\\n" + (result.stderr or ""),
            encoding="utf-8",
        )
        error(
            "Lutris could not remove the game entry.\\n\\n"
            "No game files were deleted.\\n\\n"
            "Technical log:\\n"
            f"{log_file}"
        )
        return

    if not game_path.exists():
        subprocess.run([
            "kdialog", "--msgbox",
            f"{name} was removed from Lutris and its Steam shortcut was removed.\\n\\n"
            "The game folder was already missing, so there were no files to delete."
        ])
        return

    second = subprocess.run(
        [
            "kdialog",
            "--title", "Permanent deletion",
            "--warningyesno",
            "PERMANENTLY DELETE THESE GAME FILES?\\n\\n"
            f"{name}\\n\\n"
            f"{game_path}\\n\\n"
            "This bypasses Lutris' Trash operation and deletes the folder directly.\\n\\n"
            "THIS CANNOT BE UNDONE."
        ]
    )
    if second.returncode != 0:
        subprocess.run([
            "kdialog", "--msgbox",
            f"{name} was removed from Lutris and Steam, but its files were kept at:\\n\\n{game_path}"
        ])
        return

    try:
        shutil.rmtree(game_path)
    except Exception as exc:
        error(
            "The Lutris entry and Steam shortcut were removed, but the game folder "
            "could not be deleted.\\n\\n"
            f"Path:\\n{game_path}\\n\\n"
            f"Error:\\n{exc}"
        )
        return

    subprocess.run([
        "kdialog", "--msgbox",
        f"{name} was completely removed.\\n\\n"
        "Removed:\\n"
        "• Lutris library entry\\n"
        "• Lutris game configuration\\n"
        "• Steam shortcut\\n"
        f"• Game folder: {game_path}"
    ])


def main():
    if len(sys.argv) < 2:
        sys.exit(2)

    mode = sys.argv[1]

    if mode == "tools":
        if len(sys.argv) != 3:
            sys.exit(2)

        gui_path = Path(sys.argv[2]).expanduser().resolve()
        if not gui_path.is_file():
            error(f"Tools GUI was not found:\n\n{gui_path}")
            return

        # V7.2.5: OneClick Tools and the normal Lutris client are allowed to
        # coexist. Read-only library refreshes use SQLite/YAML, and destructive
        # removal still performs its own explicit close only when required.
        # This also lets Play Game hand a launch request to an already-open
        # Lutris instance instead of killing it first.

        subprocess.Popen(
            [
                "flatpak",
                "run",
                "--command=python3",
                APP_ID,
                str(gui_path),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return

    if mode == "move-add-folder":
        if len(sys.argv) != 3:
            sys.exit(2)
        move_existing_folder_to_game_root_and_add(Path(sys.argv[2]))
        return

    if mode == "add-folder":
        if len(sys.argv) != 3:
            sys.exit(2)
        add_existing_from_folder(Path(sys.argv[2]))
        return

    if mode == "find-install-folder":
        if len(sys.argv) != 3:
            sys.exit(2)
        find_exe_and_open_installer(Path(sys.argv[2]))
        return

    if mode == "stream-storage-options":
        print(json.dumps({"ok": True, "external": _mounted_external_storage_choices()}))
        return

    if mode == "stream-prepare":
        storage_path = sys.argv[2] if len(sys.argv) >= 3 else ""
        storage_fstype = sys.argv[3] if len(sys.argv) >= 4 else ""
        game_name = sys.argv[4] if len(sys.argv) >= 5 else ""
        replace_existing = (sys.argv[5] if len(sys.argv) >= 6 else "0") == "1"
        stream_pid = int(sys.argv[6]) if len(sys.argv) >= 7 and str(sys.argv[6]).isdigit() else 0
        try:
            print(json.dumps(_stream_prepare_storage(storage_path, storage_fstype, game_name, replace_existing, stream_pid)))
        except Exception as exc:
            print(json.dumps({"ok": False, "error": str(exc)}))
            sys.exit(1)
        return

    if mode == "stream-abort":
        prefix_dir = sys.argv[2] if len(sys.argv) >= 3 else ""
        session_id = sys.argv[3] if len(sys.argv) >= 4 else ""
        print(json.dumps(_stream_abort_prefix(prefix_dir, session_id)))
        return

    if mode == "stream-complete":
        prefix_dir = sys.argv[2] if len(sys.argv) >= 3 else ""
        session_id = sys.argv[3] if len(sys.argv) >= 4 else ""
        print(json.dumps(_stream_mark_complete(prefix_dir, session_id)))
        return

    if mode == "stream-preserve-failed":
        prefix_dir = sys.argv[2] if len(sys.argv) >= 3 else ""
        session_id = sys.argv[3] if len(sys.argv) >= 4 else ""
        print(json.dumps(_stream_preserve_failed_prefix(prefix_dir, session_id)))
        return

    if mode == "stream-iso-detect":
        files_dir = sys.argv[2] if len(sys.argv) >= 3 else ""
        print(json.dumps(_stream_iso_detect(files_dir)))
        return

    if mode == "stream-iso-launch":
        files_dir = sys.argv[2] if len(sys.argv) >= 3 else ""
        storage_mode = sys.argv[3] if len(sys.argv) >= 4 else "internal"
        storage_root = sys.argv[4] if len(sys.argv) >= 5 else ""
        keep_extracted_source = (sys.argv[5] if len(sys.argv) >= 6 else "1") == "1"
        try:
            print(json.dumps(_stream_iso_launch(files_dir, storage_mode, storage_root, keep_extracted_source)))
        except Exception as exc:
            print(json.dumps({"ok": False, "error": str(exc), "files_dir": files_dir}))
            sys.exit(1)
        return

    if mode == "stream-iso-session":
        if len(sys.argv) != 3:
            sys.exit(2)
        _stream_iso_session(sys.argv[2])
        return

    if mode == "stream-iso-status":
        if len(sys.argv) != 3:
            sys.exit(2)
        print(json.dumps(_stream_iso_status(sys.argv[2])))
        return

    if mode == "stream-iso-cleanup-all":
        print(json.dumps(_stream_iso_cleanup_stale_sessions(force=True)))
        return

    if mode == "stream-finalize":
        if len(sys.argv) < 4:
            sys.exit(2)
        files_dir = sys.argv[2]
        storage_mode = sys.argv[3]
        storage_root = sys.argv[4] if len(sys.argv) >= 5 else ""
        initial_game_name = sys.argv[5] if len(sys.argv) >= 6 else ""
        try:
            print(json.dumps(_stream_finalize_extracted_game(files_dir, storage_mode, storage_root, initial_game_name)))
        except Exception as exc:
            print(json.dumps({"ok": False, "error": str(exc), "files_dir": files_dir}))
            sys.exit(1)
        return

    if mode == "dependency-pack-download":
        if len(sys.argv) != 3:
            sys.exit(2)
        result = download_dependency_pack(sys.argv[2])
        print(json.dumps(result))
        if not result.get("ok"):
            sys.exit(1)
        return

    if mode == "dependency-pack-import":
        if len(sys.argv) != 3:
            sys.exit(2)
        result = import_dependency_pack(sys.argv[2])
        print(json.dumps(result))
        if not result.get("ok"):
            sys.exit(1)
        return

    if mode == "dependency-official-download":
        result = download_official_dependency_set()
        print(json.dumps(result))
        if not result.get("ok") and not result.get("partial"):
            sys.exit(1)
        return

    if mode == "dependency-inventory":
        if len(sys.argv) not in {4, 5}:
            sys.exit(2)
        hint = {}
        if len(sys.argv) == 5:
            try:
                hint = json.loads(sys.argv[4])
            except Exception:
                hint = {}
        print(json.dumps(dependency_inventory(sys.argv[2], sys.argv[3], hint)))
        return

    if mode == "cache-game-dependencies":
        if len(sys.argv) != 4:
            sys.exit(2)
        result = cache_game_dependencies(sys.argv[2], sys.argv[3])
        print(json.dumps(result))
        if not result.get("ok"):
            sys.exit(1)
        return

    if mode == "dependency-batch":
        if len(sys.argv) not in {5, 6}:
            sys.exit(2)
        try:
            paths = json.loads(sys.argv[4])
        except Exception:
            paths = []
        hint = {}
        if len(sys.argv) == 6:
            try:
                hint = json.loads(sys.argv[5])
            except Exception:
                hint = {}
        result = run_dependency_batch(sys.argv[2], sys.argv[3], paths, hint)
        print(json.dumps(result))
        if result.get("ok"):
            try:
                subprocess.run(["kdialog", "--passivepopup", f"Installed {result.get('count', 0)} game dependency installer(s) into the selected prefix.", "6"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
        else:
            if not result.get("cancelled"):
                error(str(result.get("error") or "Dependency installation failed."))
            sys.exit(1)
        return

    if mode == "dependency":
        if len(sys.argv) != 3:
            sys.exit(2)
        result = run_game_dependency(Path(sys.argv[2]))
        if not result.get("ok"):
            if not result.get("cancelled"):
                error(str(result.get("error") or "Dependency installation failed."))
                sys.exit(1)
        else:
            try:
                subprocess.run(["kdialog", "--passivepopup", f"{Path(sys.argv[2]).name} finished installing into {result.get('game_name', 'the selected game')}.", "6"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass
        return

    if mode == "remove":
        if len(sys.argv) != 2:
            sys.exit(2)
        complete_remove()
        return

    if mode == "steamrepair":
        if len(sys.argv) != 2:
            sys.exit(2)
        steam_shortcut_repair_menu()
        return

    if mode == "watchsteam":
        if len(sys.argv) not in (5, 6, 7):
            sys.exit(2)
        watch_install_and_offer_steam(
            sys.argv[2],
            sys.argv[3],
            int(sys.argv[4]),
            sys.argv[5] if len(sys.argv) >= 6 else "",
            (sys.argv[6] == "1") if len(sys.argv) >= 7 else False,
        )
        return

    if mode == "protonwatch-native":
        if len(sys.argv) != 7:
            sys.exit(2)
        _direct_proton_watch(int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6])
        return

    if mode == "external-monitor":
        external_monitor_loop()
        return

    if mode == "external-steam-launch":
        if len(sys.argv) < 4:
            sys.exit(2)
        try:
            _external_steam_launch(int(sys.argv[2]), sys.argv[3:])
        except Exception as exc:
            try:
                subprocess.run(["kdialog", "--error", str(exc)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            except Exception:
                pass
            with open(STEAM_NATIVE_LOG, "a", encoding="utf-8") as log:
                log.write(f"{time.ctime()}: external launch failed AppID {sys.argv[2]}: {exc}\n")
            sys.exit(1)
        return

    if mode == "migrate-external-paths":
        try:
            print(migrate_external_steam_paths())
        except Exception:
            traceback.print_exc()
            sys.exit(1)
        return

    if mode == "format-external":
        try:
            print(json.dumps(_format_external_drive_from_settings()))
        except Exception as exc:
            print(json.dumps({"ok": False, "error": str(exc)}))
            sys.exit(1)
        return

    if mode == "btrfs-targets":
        print(json.dumps({"targets": _btrfs_space_saver_targets()}))
        return

    if mode == "btrfs-space-saver":
        if len(sys.argv) != 3:
            sys.exit(2)
        try:
            print(json.dumps(run_btrfs_space_saver(sys.argv[2])))
        except Exception as exc:
            print(json.dumps({"ok": False, "error": str(exc)}))
            sys.exit(1)
        return

    if mode == "cleanup-failed":
        result = cleanup_tracked_failed_installs()
        print(json.dumps(result))
        return

    if mode == "rename-steam-game":
        if len(sys.argv) not in (4, 5):
            sys.exit(2)
        no_defer = len(sys.argv) == 5 and sys.argv[4] == "no-defer"
        print(json.dumps(_rename_steam_native_game(
            int(sys.argv[2]), sys.argv[3], launch_deferred=not no_defer
        )))
        return

    if mode == "reselect-exe-candidates":
        if len(sys.argv) != 3:
            sys.exit(2)
        print(json.dumps(_reselect_exe_candidate_payload(int(sys.argv[2]))))
        return

    if mode == "reselect-exe-apply":
        if len(sys.argv) not in (4, 5):
            sys.exit(2)
        no_defer = len(sys.argv) == 5 and sys.argv[4] == "no-defer"
        print(json.dumps(_apply_reselected_steam_main_exe(
            int(sys.argv[2]), sys.argv[3], launch_deferred=not no_defer
        )))
        return

    if mode == "reselect-exe":
        if len(sys.argv) != 3:
            sys.exit(2)
        reselect_steam_main_exe(int(sys.argv[2]))
        return

    if mode == "finalize-pending-steam":
        if len(sys.argv) < 3:
            sys.exit(2)
        _deferred_steam_finalize(int(sys.argv[2]))
        return

    if mode == "recover-pending-steam":
        print(json.dumps(recover_pending_steam_shortcuts()))
        return

    if mode == "protonwatch-update":
        if len(sys.argv) < 7:
            sys.exit(2)
        update_exe = sys.argv[7] if len(sys.argv) >= 8 else ""
        retry_count = int(sys.argv[8]) if len(sys.argv) >= 9 and sys.argv[8] else 0
        _direct_update_watch(int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), sys.argv[5], sys.argv[6], update_exe, retry_count)
        return

    if mode == "steamwatch-native":
        if len(sys.argv) not in (5, 6):
            sys.exit(2)
        restore = sys.argv[5] if len(sys.argv) == 6 else ""
        _steam_native_watch(int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), restore)
        return

    if len(sys.argv) != 3:
        sys.exit(2)

    source = Path(sys.argv[2]).expanduser().resolve()
    if not source.is_file():
        error(f"File not found:\n\n{source}")
        sys.exit(1)

    if mode == "new":
        if source.suffix.casefold() == ".iso":
            result = _standalone_iso_launch(source)
            if not result.get("ok"):
                error(
                    "Moses could not open this installer ISO.\n\n"
                    + str(result.get("error") or "The ISO could not be mounted safely.")
                    + f"\n\nISO:\n{source}"
                )
                sys.exit(1)
            return
        handle_new_exe(source)
    elif mode == "existing":
        run_existing(source)
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
__PYHELPER_41C2__

chmod +x "$HELPER"

# V7.4.22: resume shortcut writes left pending by older builds. Run detached so
# setup is never delayed when Steam is open.
nohup "$HELPER" recover-pending-steam >/dev/null 2>&1 &

# V7.2.5: keep known removable game drives mounted/resolved by filesystem UUID
# in both Desktop Mode and Gaming Mode. This is a user service; it never touches
# unknown drives and never formats anything.
cat > "$EXTERNAL_MONITOR_SERVICE" <<__EXTERNAL_MONITOR_SERVICE__
[Unit]
Description=Moses OneClick external game drive resolver
After=default.target

[Service]
Type=simple
ExecStart=$HELPER external-monitor
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
__EXTERNAL_MONITOR_SERVICE__

systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user enable moses-oneclick-external-monitor.service >/dev/null 2>&1 || true
systemctl --user restart moses-oneclick-external-monitor.service >/dev/null 2>&1 || true
# Migrate older external Steam/Proton entries from temporary /run/media paths
# to the UUID-stable aliases. Safe and idempotent; game bytes are never moved.
"$HELPER" migrate-external-paths >/dev/null 2>&1 || true

# Small GTK dialog used for the double-click workflow and for adding an
# already-complete game folder. It runs inside the Lutris Flatpak so we can use
# GTK without requiring extra host packages beyond what One-Click already uses.
cat > "$ACTION_GUI" <<'__ACTION_GUI_V70__'
#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk, Pango

SETTINGS_FILE = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "lutris-oneclick" / "settings.json"


def load_language():
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
        value = str(data.get("language") or "en").strip().lower()
        return value if value in {"en", "sv"} else "en"
    except Exception:
        return "en"


SV = {
    "Moses OneClick Tool — Game Installer": "Moses OneClick Tool — Spelinstallation",
    "What would you like to do?": "Vad vill du göra?",
    "Backend for this new installation only. Your Settings default is not changed.": "Backend endast för den här nya installationen. Standardvalet i Inställningar ändras inte.",
    "GAME NAME": "SPELNAMN",
    "INSTALL LOCATION": "INSTALLATIONSPLATS",
    "Internal storage (default)": "Intern lagring (standard)",
    "External drive": "Extern disk",
    "needs write-permission fix": "behöver behörighetsfix",
    "needs formatting for Proton/Wine": "behöver formateras för Proton/Wine",
    "unavailable": "inte tillgänglig",
    "Choose where this new game's Wine/Proton prefix and installed files should live. External drives must remain connected when playing.": "Välj var spelets Wine/Proton-prefix och installerade filer ska ligga. Externa diskar måste vara anslutna när du spelar.",
    "This filename looks like an update or patch, so Update is selected automatically.": "Filnamnet ser ut som en uppdatering eller patch, därför väljs Uppdatera automatiskt.",
    "Install as a new game": "Installera som ett nytt spel",
    "Run this EXE as an installer using your selected One-Click backend.": "Kör denna EXE som installationsprogram med vald OneClick-backend.",
    "Update an installed game": "Uppdatera ett installerat spel",
    "Run this EXE inside an existing game's current Steam Proton or Lutris prefix.": "Kör denna EXE i ett befintligt spels nuvarande Steam Proton- eller Lutris-prefix.",
    "Add existing game to Steam (no install)": "Lägg till befintligt spel i Steam (ingen installation)",
    "Use an already-complete game EXE, create the Steam shortcut, and fetch artwork only.": "Använd en redan färdig spel-EXE, skapa Steam-genvägen och hämta endast artwork.",
    "Cancel": "Avbryt",
    "Continue": "Fortsätt",
    "Updates automatically use the selected installed game's existing backend/prefix.": "Uppdateringar använder automatiskt det valda spelets befintliga backend/prefix.",
    "Add existing game to Steam is always Steam-native.": "Lägg till befintligt spel i Steam använder alltid Steam-backenden.",
    "Mounted installer ISO": "Monterad installations-ISO",
    "The installer will run directly from the read-only ISO; the ISO does not need to be extracted.": "Installationen körs direkt från den skrivskyddade ISO-filen; ISO:n behöver inte extraheras.",
    "Delete ISO after successful installation": "Ta bort ISO efter lyckad installation",
    "StreamExtract source cleanup": "StreamExtract-källrensning",
    "The extracted installer files will be kept after a successful installation.": "De extraherade installationsfilerna behålls efter en lyckad installation.",
    "The extracted installer files will be deleted after a successful installation and safe ISO unmount.": "De extraherade installationsfilerna tas bort efter en lyckad installation och säker avmontering av ISO-filen.",
    "Find Game EXE": "Hitta spelets EXE",
    "Add Existing Game to Steam": "Lägg till befintligt spel i Steam",
    "Create Steam Shortcut": "Skapa Steam-genväg",
    "Choose the EXE to open": "Välj vilken EXE som ska öppnas",
    "Add an already-complete game": "Lägg till ett redan färdigt spel",
    "MAIN GAME EXE": "HUVUD-EXE FÖR SPELET",
    "Lutris / Wine (manual)": "Lutris / Wine (manuell)",
}


def tr(text):
    value = str(text)
    if load_language() != "sv":
        return value
    if value in SV:
        return SV[value]
    if value.startswith("One-Click scanned: "):
        return "OneClick skannade: " + value.split(": ", 1)[1]
    value = value.replace("External: ", "Extern: ")
    value = value.replace(" GiB free", " GiB ledigt")
    return value


def install_css():
    css = b"""
    window, dialog, .oneclick-root {
        background-color: #f6f7f9;
        color: #202124;
    }
    .headline { font-size: 16pt; font-weight: 700; color: #202124; }
    .subtitle { color: #70757a; font-size: 9.5pt; }
    .section { color: #6b7075; font-size: 8.5pt; font-weight: 700; letter-spacing: 0.7px; }
    .option-title { font-weight: 600; color: #202124; }
    .option-desc { color: #747983; font-size: 9pt; }
    .update-note {
        color: #6d5200; background-color: #fff4c2; border: 1px solid #ead58b;
        border-radius: 7px; padding: 7px;
    }
    entry {
        min-height: 34px; padding-left: 9px; padding-right: 9px;
        background-color: #ffffff; color: #202124;
        border: 1px solid #cfd3d8; border-radius: 7px;
    }
    entry:focus { border-color: #2f80ed; }
    combobox button {
        min-height: 40px; padding-left: 12px; padding-right: 12px;
        background-image: none; background-color: #ffffff; color: #202124;
        border: 1px solid #cfd3d8; border-radius: 7px; box-shadow: none;
    }
    button.primary {
        min-height: 36px; min-width: 112px; background-image: none;
        background-color: #2f80ed; color: #ffffff; border: 1px solid #2f80ed;
        border-radius: 7px; box-shadow: none; text-shadow: none; -gtk-icon-shadow: none;
    }
    button.primary label { color: #ffffff; text-shadow: none; }
    button.primary:hover { background-color: #1f6fd5; border-color: #1f6fd5; }
    button.secondary {
        min-height: 36px; min-width: 92px; background-image: none;
        background-color: #ffffff; color: #4b5156; border: 1px solid #cfd3d8;
        border-radius: 7px; box-shadow: none;
    }
    button.secondary:hover { background-color: #f0f2f4; }
    radiobutton { padding-top: 2px; padding-bottom: 2px; }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    screen = Gdk.Screen.get_default()
    if screen:
        Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def emit(value):
    print("ONECLICK_RESULT=" + json.dumps(value, ensure_ascii=False), flush=True)


def labeled_option(label, description, group=None):
    if group is None:
        radio = Gtk.RadioButton.new_with_label_from_widget(None, label)
    else:
        radio = Gtk.RadioButton.new_with_label_from_widget(group, label)
    radio.get_style_context().add_class("option-title")
    desc = Gtk.Label(label=description)
    desc.set_xalign(0)
    desc.set_line_wrap(True)
    desc.get_style_context().add_class("option-desc")
    desc.set_margin_start(24)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    box.pack_start(radio, False, False, 0)
    box.pack_start(desc, False, False, 0)
    return radio, box


def new_exe_dialog(
    exe_text, suggested, likely_update, default_backend="steam",
    external_choices_json="[]", source_iso=False,
    stream_cleanup_managed=False, stream_keep_extracted_source=True,
):
    try:
        external_choices = json.loads(external_choices_json or "[]")
    except Exception:
        external_choices = []
    if not isinstance(external_choices, list):
        external_choices = []
    dlg = Gtk.Dialog(title=tr("Moses OneClick Tool — Game Installer"))
    dlg.set_default_size(520, 475 if source_iso else 430)
    dlg.set_resizable(False)
    dlg.set_position(Gtk.WindowPosition.CENTER)
    dlg.set_icon_name("applications-games")
    dlg.set_default_response(Gtk.ResponseType.OK)
    # We use our own centered footer instead of GTK's side-aligned dialog action area.
    dlg.get_action_area().set_no_show_all(True)
    dlg.get_action_area().hide()

    area = dlg.get_content_area()
    area.get_style_context().add_class("oneclick-root")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    box.set_border_width(18)
    area.pack_start(box, True, True, 0)

    top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    heading = Gtk.Label(label=tr("What would you like to do?"))
    heading.set_xalign(0)
    heading.set_hexpand(True)
    heading.get_style_context().add_class("headline")
    top_row.pack_start(heading, True, True, 0)

    backend_combo = Gtk.ComboBoxText()
    backend_combo.append("steam", "Steam / Proton")
    backend_combo.append("smart", "Smart Automatic / Lutris")
    backend_combo.append("lutris", tr("Lutris / Wine (manual)"))
    backend_combo.set_active_id(default_backend if default_backend in {"steam", "smart", "lutris"} else "steam")
    backend_combo.set_tooltip_text(tr("Backend for this new installation only. Your Settings default is not changed."))
    top_row.pack_end(backend_combo, False, False, 0)
    box.pack_start(top_row, False, False, 0)

    file_label = Gtk.Label(label=Path(exe_text).name)
    file_label.set_xalign(0)
    file_label.set_ellipsize(Pango.EllipsizeMode.END)
    file_label.set_margin_top(4)
    file_label.set_margin_bottom(12)
    file_label.get_style_context().add_class("subtitle")
    box.pack_start(file_label, False, False, 0)

    delete_iso_box = None
    if source_iso:
        iso_title = Gtk.Label(label=tr("Mounted installer ISO"))
        iso_title.set_xalign(0)
        iso_title.get_style_context().add_class("section")
        box.pack_start(iso_title, False, False, 0)
        iso_hint = Gtk.Label(label=tr("The installer will run directly from the read-only ISO; the ISO does not need to be extracted."))
        iso_hint.set_xalign(0)
        iso_hint.set_line_wrap(True)
        iso_hint.get_style_context().add_class("option-desc")
        iso_hint.set_margin_bottom(4)
        box.pack_start(iso_hint, False, False, 0)
        if stream_cleanup_managed:
            cleanup_title = Gtk.Label(label=tr("StreamExtract source cleanup"))
            cleanup_title.set_xalign(0)
            cleanup_title.get_style_context().add_class("section")
            cleanup_title.set_margin_top(3)
            box.pack_start(cleanup_title, False, False, 0)
            cleanup_text = tr(
                "The extracted installer files will be kept after a successful installation."
                if stream_keep_extracted_source else
                "The extracted installer files will be deleted after a successful installation and safe ISO unmount."
            )
            cleanup_hint = Gtk.Label(label=cleanup_text)
            cleanup_hint.set_xalign(0)
            cleanup_hint.set_line_wrap(True)
            cleanup_hint.get_style_context().add_class("option-desc")
            cleanup_hint.set_margin_bottom(10)
            box.pack_start(cleanup_hint, False, False, 0)
        else:
            delete_iso_box = Gtk.CheckButton(label=tr("Delete ISO after successful installation"))
            delete_iso_box.set_active(False)
            delete_iso_box.set_margin_bottom(10)
            box.pack_start(delete_iso_box, False, False, 0)

    name_label = Gtk.Label(label=tr("GAME NAME"))
    name_label.set_xalign(0)
    name_label.set_margin_bottom(5)
    name_label.get_style_context().add_class("section")
    box.pack_start(name_label, False, False, 0)

    entry = Gtk.Entry()
    entry.set_text(suggested)
    entry.set_activates_default(True)
    entry.set_margin_bottom(13)
    box.pack_start(entry, False, False, 0)

    storage_label = Gtk.Label(label=tr("INSTALL LOCATION"))
    storage_label.set_xalign(0)
    storage_label.set_margin_bottom(5)
    storage_label.get_style_context().add_class("section")
    box.pack_start(storage_label, False, False, 0)

    storage_combo = Gtk.ComboBoxText()
    storage_combo.append("internal", tr("Internal storage (default)"))
    storage_map = {"internal": {"path": "", "fstype": "", "supported": True}}
    for idx, drive in enumerate(external_choices):
        if not isinstance(drive, dict):
            continue
        path = str(drive.get("path") or "").strip()
        if not path:
            continue
        key = f"external-{idx}"
        label = str(drive.get("label") or Path(path).name or tr("External drive"))
        fstype = str(drive.get("fstype") or "unknown")
        free = int(drive.get("free") or 0)
        free_gib = free / (1024 ** 3) if free else 0
        writable = bool(drive.get("writable", False))
        fs_supported = bool(drive.get("filesystem_supported", False))
        supported = bool(drive.get("supported", False))
        suffix = f" · {free_gib:.1f} GiB free · {fstype}" if free else f" · {fstype}"
        if fs_supported and not writable:
            suffix += " · " + tr("needs write-permission fix")
        elif not fs_supported:
            suffix += " · " + tr("needs formatting for Proton/Wine")
        elif not supported:
            suffix += " · " + tr("unavailable")
        storage_combo.append(key, tr(f"External: {label}{suffix}"))
        storage_map[key] = {"path": path, "fstype": fstype, "supported": supported}
    storage_combo.set_active_id("internal")
    storage_combo.set_tooltip_text(tr("Choose where this new game's Wine/Proton prefix and installed files should live. External drives must remain connected when playing."))
    storage_combo.set_margin_bottom(13)
    box.pack_start(storage_combo, False, False, 0)

    if likely_update:
        note = Gtk.Label(label=tr("This filename looks like an update or patch, so Update is selected automatically."))
        note.set_xalign(0)
        note.set_line_wrap(True)
        note.set_margin_bottom(10)
        note.get_style_context().add_class("update-note")
        box.pack_start(note, False, False, 0)

    install_radio, install_box = labeled_option(
        tr("Install as a new game"),
        tr("Run this EXE as an installer using your selected One-Click backend."),
    )
    update_radio, update_box = labeled_option(
        tr("Update an installed game"),
        tr("Run this EXE inside an existing game's current Steam Proton or Lutris prefix."),
        install_radio,
    )
    existing_radio, existing_box = labeled_option(
        tr("Add existing game to Steam (no install)"),
        tr("Use an already-complete game EXE, create the Steam shortcut, and fetch artwork only."),
        install_radio,
    )
    for opt in (install_box, update_box, existing_box):
        opt.set_margin_bottom(7)
        box.pack_start(opt, False, False, 0)

    footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    footer.set_halign(Gtk.Align.CENTER)
    footer.set_margin_top(8)
    cancel = Gtk.Button(label=tr("Cancel"))
    cancel.get_style_context().add_class("secondary")
    cancel.connect("clicked", lambda *_: dlg.response(Gtk.ResponseType.CANCEL))
    go = Gtk.Button(label=tr("Continue"))
    go.get_style_context().add_class("primary")
    go.connect("clicked", lambda *_: dlg.response(Gtk.ResponseType.OK))
    footer.pack_start(cancel, False, False, 0)
    footer.pack_start(go, False, False, 0)
    box.pack_start(footer, False, False, 0)
    entry.connect("activate", lambda *_: dlg.response(Gtk.ResponseType.OK))

    (update_radio if likely_update else install_radio).set_active(True)

    def sync_backend_sensitivity(*_args):
        is_install = install_radio.get_active()
        backend_combo.set_sensitive(is_install)
        storage_combo.set_sensitive(is_install)
        storage_label.set_sensitive(is_install)
        if delete_iso_box is not None:
            delete_iso_box.set_sensitive(is_install)
        if is_install:
            backend_combo.set_tooltip_text("Backend for this new installation only. Your Settings default is not changed.")
        elif update_radio.get_active():
            backend_combo.set_tooltip_text(tr("Updates automatically use the selected installed game's existing backend/prefix."))
        else:
            backend_combo.set_tooltip_text(tr("Add existing game to Steam is always Steam-native."))

    for radio in (install_radio, update_radio, existing_radio):
        radio.connect("toggled", sync_backend_sensitivity)
    sync_backend_sensitivity()

    dlg.show_all()
    response = dlg.run()
    name = entry.get_text().strip()
    if response == Gtk.ResponseType.OK and name:
        action = "install"
        if update_radio.get_active():
            action = "update"
        elif existing_radio.get_active():
            action = "existing"
        storage_id = storage_combo.get_active_id() or "internal"
        storage = storage_map.get(storage_id) or storage_map["internal"]
        emit({
            "action": action,
            "name": name,
            "backend": backend_combo.get_active_id() or default_backend,
            "storage_path": str(storage.get("path") or "") if action == "install" else "",
            "storage_fstype": str(storage.get("fstype") or "") if action == "install" else "",
            "storage_supported": bool(storage.get("supported", True)),
            "delete_source_iso": bool(delete_iso_box.get_active()) if (source_iso and delete_iso_box is not None and action == "install") else False,
        })
    dlg.destroy()


def human_size(value):
    try:
        size = float(value)
    except Exception:
        return ""
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{int(size)} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return ""


def folder_dialog(folder_text, suggested, payload_text, purpose="existing"):
    install_mode = str(purpose).strip().lower() == "install"
    try:
        items = json.loads(payload_text)
    except Exception:
        items = []
    if not isinstance(items, list) or not items:
        return

    dlg = Gtk.Dialog(title=tr("Find Game EXE") if install_mode else tr("Add Existing Game to Steam"))
    dlg.set_default_size(610, 390)
    dlg.set_resizable(False)
    dlg.set_position(Gtk.WindowPosition.CENTER)
    dlg.set_icon_name("applications-games")
    cancel = dlg.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
    cancel.get_style_context().add_class("secondary")
    go = dlg.add_button(tr("Continue") if install_mode else tr("Create Steam Shortcut"), Gtk.ResponseType.OK)
    go.get_style_context().add_class("primary")
    dlg.set_default_response(Gtk.ResponseType.OK)

    area = dlg.get_content_area()
    area.get_style_context().add_class("oneclick-root")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    box.set_border_width(24)
    area.pack_start(box, True, True, 0)

    heading = Gtk.Label(label=tr("Choose the EXE to open") if install_mode else tr("Add an already-complete game"))
    heading.set_xalign(0)
    heading.get_style_context().add_class("headline")
    box.pack_start(heading, False, False, 0)

    sub = Gtk.Label(label=tr(f"One-Click scanned: {folder_text}"))
    sub.set_xalign(0)
    sub.set_ellipsize(Pango.EllipsizeMode.END)
    sub.set_margin_top(4)
    sub.set_margin_bottom(18)
    sub.get_style_context().add_class("subtitle")
    box.pack_start(sub, False, False, 0)

    name_label = Gtk.Label(label=tr("GAME NAME"))
    name_label.set_xalign(0)
    name_label.set_margin_bottom(5)
    name_label.get_style_context().add_class("section")
    box.pack_start(name_label, False, False, 0)
    entry = Gtk.Entry()
    entry.set_text(suggested)
    entry.set_margin_bottom(16)
    box.pack_start(entry, False, False, 0)
    name_state = {"manual": False, "internal": False}

    def mark_name_manual(*_args):
        if not name_state["internal"]:
            name_state["manual"] = True

    entry.connect("changed", mark_name_manual)

    exe_label = Gtk.Label(label=tr("MAIN GAME EXE"))
    exe_label.set_xalign(0)
    exe_label.set_margin_bottom(6)
    exe_label.get_style_context().add_class("section")
    box.pack_start(exe_label, False, False, 0)

    combo = Gtk.ComboBoxText()
    for idx, item in enumerate(items):
        label = str(item.get("label") or item.get("path") or "")
        size = human_size(item.get("size") or 0)
        if size:
            label += f"   ·   {size}"
        combo.append(str(idx), label)
    combo.set_active(0)
    box.pack_start(combo, False, False, 0)

    def sync_name_to_exe(*_args):
        if name_state["manual"]:
            return
        active = combo.get_active()
        if not (0 <= active < len(items)):
            return
        candidate_name = str(items[active].get("suggested_name") or "").strip()
        if candidate_name and candidate_name != entry.get_text():
            name_state["internal"] = True
            try:
                entry.set_text(candidate_name)
            finally:
                name_state["internal"] = False

    combo.connect("changed", sync_name_to_exe)
    sync_name_to_exe()

    hint = Gtk.Label(label=(("Välj den EXE som OneClick ska använda. Spelnamnet hämtas från mapparna runt den valda EXE-filen; du kan fortfarande ändra namnet. Fortsätt öppnar den vanliga menyn Installera / Uppdatera / Lägg till befintligt." if load_language() == "sv" else "Choose the EXE you want One-Click to handle. The game name is inferred from the selected EXE's folders; you can still edit it. Continue opens the normal Install / Update / Add Existing menu.") if install_mode else ("Kandidater rangordnas efter matchning mot spelnamn, plats och filstorlek. Titeln följer vald EXE om du inte ändrar den manuellt. Setup-, updater-, redistributable- och crash-helper-EXE-filer prioriteras ned eller döljs." if load_language() == "sv" else "Candidates are ranked by game-name match, location and file size. The title follows the selected EXE unless you edit it manually. Setup, updater, redistributable and crash-helper EXEs are pushed down or hidden.")))
    hint.set_xalign(0)
    hint.set_line_wrap(True)
    hint.set_margin_top(10)
    hint.get_style_context().add_class("option-desc")
    box.pack_start(hint, False, False, 0)

    dlg.show_all()
    response = dlg.run()
    if response == Gtk.ResponseType.OK:
        active = combo.get_active()
        name = entry.get_text().strip()
        if 0 <= active < len(items) and name:
            emit({"name": name, "exe": str(items[active].get("path") or "")})
    dlg.destroy()


def main():
    install_css()
    if len(sys.argv) < 2:
        return
    mode = sys.argv[1]
    if mode == "new-exe" and len(sys.argv) >= 5:
        default_backend = sys.argv[5] if len(sys.argv) >= 6 else "steam"
        external_choices_json = sys.argv[6] if len(sys.argv) >= 7 else "[]"
        source_iso = (sys.argv[7] == "1") if len(sys.argv) >= 8 else False
        stream_cleanup_managed = (sys.argv[8] == "1") if len(sys.argv) >= 9 else False
        stream_keep_extracted_source = (sys.argv[9] == "1") if len(sys.argv) >= 10 else True
        new_exe_dialog(
            sys.argv[2], sys.argv[3], sys.argv[4] == "1", default_backend,
            external_choices_json, source_iso, stream_cleanup_managed,
            stream_keep_extracted_source,
        )
    elif mode == "folder" and len(sys.argv) >= 5:
        folder_dialog(sys.argv[2], sys.argv[3], sys.argv[4], "existing")
    elif mode == "folder-install" and len(sys.argv) >= 5:
        folder_dialog(sys.argv[2], sys.argv[3], sys.argv[4], "install")


if __name__ == "__main__":
    main()
__ACTION_GUI_V70__
chmod +x "$ACTION_GUI"

# Steam-facing launcher for Lutris-backed games. Steam itself can inject its
# runtime/Proton environment into child processes; that is useful for native
# Steam games but can confuse Lutris/UMU when Steam is only being used as a
# frontend. Keep SteamGameId/SteamAppId for UMU's Steam-mode window handling,
# while stripping the outer Steam compatibility/runtime variables before
# entering the Lutris Flatpak.
cat > "$LUTRIS_STEAM_WRAPPER" <<'__LUTRIS_STEAM_WRAPPER__'
#!/usr/bin/env bash
set -euo pipefail

GAME_ID="${1:-}"
if [[ -z "$GAME_ID" ]]; then
  exit 2
fi

STEAM_GAME_ID_VALUE="${SteamGameId:-${STEAM_GAME_ID:-}}"
STEAM_APP_ID_VALUE="${SteamAppId:-${STEAM_APP_ID:-}}"

export LC_ALL=C.UTF-8
export LANG="${LANG:-en_US.UTF-8}"

# Avoid leaking Steam's outer runtime/Proton state into Lutris/UMU. Do not
# unset SteamGameId/SteamAppId: current UMU uses them to identify a non-Steam
# shortcut when launched from Gaming Mode.
unset LD_PRELOAD || true
unset LD_LIBRARY_PATH || true
unset STEAM_RUNTIME || true
unset STEAM_RUNTIME_LIBRARY_PATH || true
unset STEAM_COMPAT_DATA_PATH || true
unset STEAM_COMPAT_CLIENT_INSTALL_PATH || true
unset STEAM_COMPAT_TOOL_PATHS || true
unset STEAM_COMPAT_MOUNTS || true
unset PROTONPATH || true
unset PROTON_VERB || true
unset WINEPREFIX || true
unset WINEDLLOVERRIDES || true

args=(run --env=LC_ALL=C.UTF-8)
if [[ -n "$STEAM_GAME_ID_VALUE" ]]; then
  args+=("--env=SteamGameId=$STEAM_GAME_ID_VALUE")
fi
if [[ -n "$STEAM_APP_ID_VALUE" ]]; then
  args+=("--env=SteamAppId=$STEAM_APP_ID_VALUE")
fi
args+=(net.lutris.Lutris "lutris:rungameid/$GAME_ID")

exec /usr/bin/flatpak "${args[@]}"
__LUTRIS_STEAM_WRAPPER__
chmod +x "$LUTRIS_STEAM_WRAPPER"

cat > "$TOOLS_GUI" <<'__TOOLS_GUI_4A91__'
#!/usr/bin/env python3

import json
import os
import re
import shutil
import shlex
import sqlite3
import ssl
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")

from gi.repository import Gtk, Gdk, GLib, GdkPixbuf, Gio

# Lutris imports must happen after forcing GTK 3.
sys.argv[0] = "/app/bin/lutris"

from lutris.game import Game
from lutris.util import resources
from lutris.util.steam import shortcut as steam_shortcut
from lutris.util.steam import vdf as steam_vdf

VERSION_FILE = Path.home() / ".local/share/lutris-oneclick/version"
try:
    TOOL_VERSION = VERSION_FILE.read_text(encoding="utf-8").strip() or "7.4.4"
except Exception:
    TOOL_VERSION = "7.4.4"
ONECLICK_PREFIX_MARKER = ".oneclick-exe-prefix.json"
ONECLICK_EXTERNAL_MARKER = ".oneclick-exe-external-game.json"
INTERNAL_PREFIX_ROOT = Path.home() / ".local/share/oneclick-exe/game-prefixes/Steam-Proton"
EXTERNAL_ALIAS_ROOT = Path.home() / ".local/share/oneclick-exe/external-drive-links"


def install_steamos_safe_shortcut_generator():
    # Use a tiny host-side wrapper instead of launching the Lutris Flatpak
    # directly from Steam. The wrapper keeps SteamGameId for UMU/Gaming Mode
    # but strips Steam's outer runtime/Proton variables before starting Lutris.
    # We deliberately keep Lutris' original explicit shortcut AppID, so
    # existing artwork filenames remain stable after Repair.
    original = steam_shortcut.generate_shortcut
    if getattr(original, "_lutris_oneclick_steamos_safe", False):
        return

    def fixed_generate_shortcut(game, launch_config_name):
        shortcut = original(game, launch_config_name)
        exe = str(shortcut.get("Exe", "")).strip('\"')
        if exe == "/usr/bin/flatpak":
            host_wrapper = os.path.expanduser("~/.local/bin/oneclick-lutris-steam-launch")
            shortcut["Exe"] = '"' + host_wrapper + '"'
            shortcut["StartDir"] = '"' + os.path.expanduser("~") + '"'
            shortcut["LaunchOptions"] = str(game.id)
        return shortcut

    fixed_generate_shortcut._lutris_oneclick_steamos_safe = True
    steam_shortcut.generate_shortcut = fixed_generate_shortcut


install_steamos_safe_shortcut_generator()


APP_ID = "net.lutris.Lutris"
SGDB_BASE_URL = "https://www.steamgriddb.com/api/v2"
SGDB_USER_AGENT = f"OneClick-Tools/{TOOL_VERSION}"
STEAM_STORE_SEARCH_URL = "https://store.steampowered.com/api/storesearch/"
STEAM_STORE_BROWSE_URL = "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/"
STEAM_ASSET_BASE_URL = "https://shared.steamstatic.com/store_item_assets/"
STEAM_LEGACY_ASSET_BASE_URL = "https://cdn.cloudflare.steamstatic.com/steam/apps"


def _xdg_dir(env_name, fallback_name):
    value = os.environ.get(env_name)
    if value:
        return Path(value)
    return Path.home() / fallback_name


SGDB_CONFIG_DIR = _xdg_dir("XDG_CONFIG_HOME", ".config") / "lutris-oneclick"
SGDB_CONFIG_FILE = SGDB_CONFIG_DIR / "steamgriddb.json"
SGDB_MATCH_OVERRIDES_FILE = SGDB_CONFIG_DIR / "steamgriddb-matches.json"
SETTINGS_FILE = SGDB_CONFIG_DIR / "settings.json"
STEAM_NATIVE_REGISTRY = Path.home() / ".local/share/oneclick-exe/steam-native-games.json"
REMOVAL_TOMBSTONE_DIR = Path.home() / ".local/share/oneclick-exe/removals"
DEFAULT_INSTALLER_BACKEND = "steam"
DEFAULT_STEAM_COMPAT_TOOL = "proton_experimental"
DEFAULT_ARTWORK_SOURCE = "both"
DEFAULT_LANGUAGE = "en"


def load_oneclick_settings():
    try:
        data = json.loads(SETTINGS_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_oneclick_settings(settings):
    SGDB_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    temp = SETTINGS_FILE.with_suffix(".tmp")
    temp.write_text(json.dumps(settings, indent=2, sort_keys=True), encoding="utf-8")
    try:
        os.chmod(temp, 0o600)
    except OSError:
        pass
    temp.replace(SETTINGS_FILE)
    try:
        os.chmod(SETTINGS_FILE, 0o600)
    except OSError:
        pass


def load_language():
    value = str(load_oneclick_settings().get("language") or DEFAULT_LANGUAGE).strip().lower()
    return value if value in {"en", "sv"} else DEFAULT_LANGUAGE


SV = {
    "SELECT GAME": "VÄLJ SPEL",
    "Select one or more games": "Välj ett eller flera spel",
    "Select games": "Välj spel",
    "All": "Alla",
    "Clear": "Rensa",
    "ACTIONS": "ÅTGÄRDER",
    "Install Game": "Installera spel",
    "Play Game": "Starta spel",
    "Repair Steam Shortcut": "Reparera Steam-genväg",
    "Install / Repair Dependencies": "Installera / reparera beroenden",
    "Download + Apply All Artworks": "Hämta + applicera all artwork",
    "Complete Game Removal": "Fullständig spelborttagning",
    "Restart Steam": "Starta om Steam",
    "Restarting Steam…": "Startar om Steam…",
    "Steam restarted.": "Steam har startats om.",
    "Steam restart failed": "Omstart av Steam misslyckades",
    "Steam could not be stopped cleanly.": "Steam kunde inte stängas på ett säkert sätt.",
    "Steam could not be started again.": "Steam kunde inte startas igen.",
    "StreamExtract could not be opened": "StreamExtract kunde inte öppnas",
    "TempOverlay could not be opened": "TempOverlay kunde inte öppnas",
    "StreamExtract opened.": "StreamExtract öppnades.",
    "TempOverlay opened.": "TempOverlay öppnades.",
    "Settings": "Inställningar",
    "Moses OneClick Tool — Settings": "Moses OneClick Tool — Inställningar",
    "Cancel": "Avbryt",
    "Save": "Spara",
    "General": "Allmänt",
    "Storage": "Lagring",
    "About": "Om",
    "INSTALLER BACKEND": "INSTALLATIONSBACKEND",
    "Steam / Proton is the default. Smart Automatic / Lutris is available for older or troublesome games.": "Steam / Proton är standard. Smart Automatic / Lutris finns för äldre eller problematiska spel.",
    "Steam / Proton (default)": "Steam / Proton (standard)",
    "Lutris / Wine (manual)": "Lutris / Wine (manuell)",
    "New Steam installs initially use Proton Experimental. You can change Proton later from Steam Properties → Compatibility.": "Nya Steam-installationer använder först Proton Experimental. Du kan senare byta Proton via Steam Egenskaper → Kompatibilitet.",
    "ARTWORK SOURCE": "ARTWORK-KÄLLA",
    "Both — Steam + SteamGridDB (default)": "Båda — Steam + SteamGridDB (standard)",
    "Steam only": "Endast Steam",
    "SteamGridDB only": "Endast SteamGridDB",
    "Both prefers official Steam artwork first, then falls back to SteamGridDB when Steam has no usable artwork for that slot.": "Båda föredrar officiell Steam-artwork först och använder SteamGridDB som reserv när Steam saknar användbar artwork för den platsen.",
    "STEAMGRIDDB API KEY": "STEAMGRIDDB API-NYCKEL",
    "Paste your personal SteamGridDB API key": "Klistra in din personliga SteamGridDB API-nyckel",
    "Saved persistently on this SteamOS user account.": "Sparas permanent på detta SteamOS-användarkonto.",
    "GAME FOLDERS": "SPELMAPPAR",
    "Open Selected Game Folder": "Öppna valt spels mapp",
    "Open the actual folder for the currently selected game": "Öppna den riktiga mappen för det valda spelet",
    "Open All Game Prefixes": "Öppna alla spelprefix",
    "Format External Drive": "Formatera extern disk",
    "EXTERNAL DRIVE": "EXTERN DISK",
    "BTRFS SPACE SAVER": "BTRFS SPACE SAVER",
    "Run Btrfs Space Saver": "Kör Btrfs Space Saver",
    "No Btrfs Proton/OneClick storage detected": "Ingen Btrfs Proton/OneClick-lagring hittades",
    "Deduplicate exact matching data across approved Proton/Wine prefixes using Btrfs Copy-on-Write.": "Deduplicera exakt matchande data mellan godkända Proton/Wine-prefix med Btrfs Copy-on-Write.",
    "CLEANUP": "STÄDNING",
    "Clean Failed Steam Installs": "Rensa misslyckade Steam-installationer",
    "Removes orphaned failed OneClick Proton prefixes while preserving active games.": "Tar bort övergivna misslyckade OneClick Proton-prefix utan att påverka aktiva spel.",
    "MOSES ONECLICK TOOL": "MOSES ONECLICK TOOL",
    "LANGUAGE": "SPRÅK",
    "English (default)": "Engelska (standard)",
    "Swedish": "Svenska",
    "Language changes are applied the next time a Moses OneClick window or installer dialog opens.": "Språkändringen används nästa gång ett Moses OneClick-fönster eller en installationsdialog öppnas.",
    "Moses OneClick Tool uses Steam / Proton by default, with Smart Automatic / Lutris, external drives, artwork management and Btrfs Space Saver when needed.": "Moses OneClick Tool använder Steam / Proton som standard, med Smart Automatic / Lutris, externa diskar, artwork-hantering och Btrfs Space Saver vid behov.",
    "Select one game first": "Välj ett spel först",
    "Game folder could not be opened": "Spelmappen kunde inte öppnas",
    "Game prefixes could not be opened": "Spelprefix kunde inte öppnas",
    "External drive ready": "Extern disk är klar",
    "External drive formatting failed": "Formatering av extern disk misslyckades",
    "Btrfs Space Saver complete": "Btrfs Space Saver är klar",
    "Btrfs Space Saver failed": "Btrfs Space Saver misslyckades",
    "Failed installs cleaned": "Misslyckade installationer rensades",
    "Nothing to clean": "Inget att rensa",
    "Cleanup failed": "Rensningen misslyckades",
    "Settings could not be saved": "Inställningarna kunde inte sparas",
    "Choose Windows Game Installer": "Välj Windows-installationsprogram",
    "Which game is this?": "Vilket spel är detta?",
    "Delete permanently": "Radera permanent",
    "Continue": "Fortsätt",
    "Use this EXE": "Använd denna EXE",
    "Choose the main game EXE:": "Välj spelets huvud-EXE:",
    "Could not open main EXE chooser": "Kunde inte öppna valet av huvud-EXE",
    "Main EXE update failed": "Uppdatering av huvud-EXE misslyckades",
    "Run Btrfs Space Saver?": "Köra Btrfs Space Saver?",
    "Moses OneClick Tool uses real game-named folders for its Proton prefixes; Steam keeps numeric AppID symlinks only for compatibility.": "Moses OneClick Tool använder riktiga mappar med spelnamn för Proton-prefix; Steam behåller numeriska AppID-länkar endast för kompatibilitet.",
    "Format a mounted external USB/SSD as Btrfs, ext4 or NTFS and choose its drive name": "Formatera en monterad extern USB/SSD som Btrfs, ext4 eller NTFS och välj diskens namn",
    "Btrfs/ext4: SteamOS only. NTFS: SteamOS + Windows. Formatting always asks first.": "Btrfs/ext4: endast SteamOS. NTFS: SteamOS + Windows. Formatering frågar alltid först.",
    "This can take a while on large prefix libraries. Games/installers should be closed while it runs. The Linux kernel performs an exact byte comparison before sharing any range.": "Detta kan ta en stund för stora prefixbibliotek. Spel/installationsprogram bör vara stängda under tiden. Linux-kärnan gör en exakt byte-jämförelse innan data delas.",
    "Close Settings, select exactly one game in Moses OneClick Tool, then open Settings again and press Open Selected Game Folder.": "Stäng Inställningar, välj exakt ett spel i Moses OneClick Tool, öppna sedan Inställningar igen och tryck på Öppna valt spels mapp.",
    "Formatted successfully as {fstype}.": "Formaterades korrekt som {fstype}.",
    "Mounted at:": "Monterad på:",
    "No orphaned OneClick Steam-native prefixes could be safely removed. Active shortcuts and successful installs are preserved.": "Inga övergivna OneClick Steam-prefix kunde tas bort säkert. Aktiva genvägar och fungerande installationer bevaras.",
}


def tr(text):
    value = str(text)
    if load_language() != "sv":
        return value
    if value in SV:
        return SV[value]
    # Small dynamic-status translator. Technical names/paths stay unchanged.
    replacements = [
        ("Select exactly one game first.", "Välj exakt ett spel först."),
        ("No One-Click Steam or Lutris games were found.", "Inga OneClick Steam- eller Lutris-spel hittades."),
        ("Opening the main EXE chooser for ", "Öppnar valet av huvud-EXE för "),
        ("Finding main EXE choices for ", "Söker huvud-EXE-alternativ för "),
        ("Choose the main game EXE for ", "Välj spelets huvud-EXE för "),
        ("Main EXE updated for ", "Huvud-EXE uppdaterad för "),
        ("Main EXE update failed.", "Uppdatering av huvud-EXE misslyckades."),
        ("Could not open main EXE chooser.", "Kunde inte öppna valet av huvud-EXE."),
        ("Launching ", "Startar "),
        (" through the running Steam client…", " via den körande Steam-klienten…"),
        (" through Lutris…", " via Lutris…"),
        ("Repairing shortcuts:", "Reparerar genvägar:"),
        ("Steam shortcut repair failed.", "Reparation av Steam-genväg misslyckades."),
        ("Opened game folder for ", "Öppnade spelmappen för "),
        ("Opened game prefix location(s)", "Öppnade spelprefixplats(er)"),
        ("External drive formatter opened…", "Formatering av extern disk öppnades…"),
        ("External drive formatting cancelled.", "Formatering av extern disk avbröts."),
        ("External drive ready: ", "Extern disk klar: "),
        ("Btrfs Space Saver is running…", "Btrfs Space Saver körs…"),
        ("Btrfs Space Saver completed.", "Btrfs Space Saver slutfördes."),
        ("Finding artwork for ", "Söker artwork för "),
        ("Artwork download failed.", "Hämtning av artwork misslyckades."),
        ("Removing games:", "Tar bort spel:"),
        ("Settings saved.", "Inställningarna sparades."),
        ("Installer backend:", "Installationsbackend:"),
        ("Artwork source:", "Artwork-källa:"),
        ("SteamGridDB API is ready.", "SteamGridDB API är klar."),
        ("SteamGridDB needs an API key before it can be used.", "SteamGridDB behöver en API-nyckel innan det kan användas."),
    ]
    for old, new in replacements:
        value = value.replace(old, new)
    return value


def load_installer_backend():
    value = str(load_oneclick_settings().get("installer_backend", DEFAULT_INSTALLER_BACKEND)).strip().lower()
    return value if value in {"steam", "smart", "lutris"} else DEFAULT_INSTALLER_BACKEND


def load_artwork_source():
    value = str(load_oneclick_settings().get("artwork_source", DEFAULT_ARTWORK_SOURCE)).strip().lower()
    return value if value in {"both", "steam", "steamgriddb"} else DEFAULT_ARTWORK_SOURCE


def load_steam_native_registry():
    try:
        data = json.loads(STEAM_NATIVE_REGISTRY.read_text(encoding="utf-8"))
        games = data.get("games", {}) if isinstance(data, dict) else {}
        return games if isinstance(games, dict) else {}
    except Exception:
        return {}


def save_steam_native_registry(games):
    STEAM_NATIVE_REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    temp = STEAM_NATIVE_REGISTRY.with_suffix(".tmp")
    temp.write_text(json.dumps({"version": 1, "games": games}, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(STEAM_NATIVE_REGISTRY)


def update_steam_native_registry(appid, **updates):
    games = load_steam_native_registry()
    key = str(int(appid))
    entry = dict(games.get(key) or {})
    current_status = str(entry.get("status") or "")
    new_status = str(updates.get("status") or "")
    if current_status == "removed":
        if new_status == "installing":
            entry = {}
        elif new_status:
            return entry
    entry.update(updates)
    entry["appid"] = int(appid)
    games[key] = entry
    save_steam_native_registry(games)
    return entry


def delete_steam_native_registry(appid):
    games = load_steam_native_registry()
    games.pop(str(int(appid)), None)
    save_steam_native_registry(games)


def record_removal_tombstone(appid):
    REMOVAL_TOMBSTONE_DIR.mkdir(parents=True, exist_ok=True)
    path = REMOVAL_TOMBSTONE_DIR / f"{int(appid)}.json"
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps({"appid": int(appid), "removed_at": int(time.time())}, indent=2), encoding="utf-8")
    temp.replace(path)
    return path


def queue_steam_native_icon_refresh(appid, icon_path):
    """Persist the icon path and update shortcuts.vdf on Steam's next close.

    Steam does not reliably reload external shortcuts.vdf edits while running,
    so never force-close it here. The host helper already knows how to wait
    until Steam naturally stops (for example when entering Gaming Mode).
    """
    icon_path = str(icon_path or "").strip()
    if not icon_path or not Path(icon_path).is_file():
        return False
    games = load_steam_native_registry()
    key = str(int(appid))
    entry = dict(games.get(key) or {})
    if not entry.get("final_exe"):
        return False
    entry["icon"] = icon_path
    entry["status"] = "pending_steam"
    entry["updated_at"] = int(time.time())
    entry["appid"] = int(appid)
    games[key] = entry
    save_steam_native_registry(games)

    host_helper = Path.home() / ".local/bin/lutris-exe-helper"
    if not host_helper.is_file():
        return True
    try:
        spawn = shutil.which("flatpak-spawn")
        if spawn:
            subprocess.Popen(
                [spawn, "--host", str(host_helper), "finalize-pending-steam", str(int(appid))],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True, close_fds=True,
            )
        else:
            subprocess.Popen(
                [str(host_helper), "finalize-pending-steam", str(int(appid))],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True, close_fds=True,
            )
    except Exception:
        # The path is still saved; Repair or a future installer finalizer can
        # apply it later even if the host-spawn helper was unavailable.
        pass
    return True

SGDB_CACHE_ROOT = _xdg_dir("XDG_CACHE_HOME", ".cache") / "lutris-oneclick" / "steamgriddb"
# Keep failure windows short: all five artwork types run concurrently, so a
# flaky CDN should cost seconds, not minutes.
SGDB_API_TIMEOUT = 5
SGDB_IMAGE_TIMEOUT = 3
STEAM_API_TIMEOUT = 5
STEAM_IMAGE_TIMEOUT = 4
SGDB_CACHE_FRESH_SECONDS = 24 * 60 * 60
# V7.4.52: trust SteamGridDB's own returned ordering. Older builds re-ranked
# the list by legacy score/dimensions, which could turn the website/API
# first choice into (for example) its 7th visible asset. Bump this when the
# SGDB selection policy changes so old SGDB-only cache entries are refreshed.
SGDB_SELECTION_POLICY_VERSION = 2
SGDB_CONFIG_LOCK = threading.Lock()


def load_sgdb_api_key():
    try:
        data = json.loads(SGDB_CONFIG_FILE.read_text(encoding="utf-8"))
        return str(data.get("api_key", "")).strip()
    except Exception:
        return ""


def load_sgdb_match_overrides():
    try:
        data = json.loads(SGDB_MATCH_OVERRIDES_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def get_sgdb_match_override(game_name):
    entry = load_sgdb_match_overrides().get(normalize_game_name(game_name))
    if isinstance(entry, dict) and entry.get("id") is not None:
        return entry
    return None


def save_sgdb_match_override(game_name, candidate):
    if not isinstance(candidate, dict) or candidate.get("id") is None:
        return False
    SGDB_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    data = load_sgdb_match_overrides()
    data[normalize_game_name(game_name)] = {
        "id": int(candidate["id"]),
        "name": str(candidate.get("name") or game_name),
        "types": candidate.get("types") or [],
        "verified": bool(candidate.get("verified")),
        "saved_at": int(time.time()),
    }
    temp = SGDB_MATCH_OVERRIDES_FILE.with_suffix(".tmp")
    temp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(SGDB_MATCH_OVERRIDES_FILE)
    return True


def save_sgdb_api_key(api_key):
    # Batch artwork jobs can overlap, so serialize the tiny settings write.
    with SGDB_CONFIG_LOCK:
        SGDB_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        temp = SGDB_CONFIG_FILE.with_suffix(".tmp")
        temp.write_text(json.dumps({"api_key": api_key}, indent=2), encoding="utf-8")
        try:
            os.chmod(temp, 0o600)
        except OSError:
            pass
        temp.replace(SGDB_CONFIG_FILE)
        try:
            os.chmod(SGDB_CONFIG_FILE, 0o600)
        except OSError:
            pass


def _host_run(command, timeout=20):
    """Run a small command on the SteamOS host from the Lutris Flatpak."""
    return subprocess.run(
        ["flatpak-spawn", "--host", "sh", "-lc", command],
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def host_steam_is_running():
    try:
        result = _host_run("pgrep -x steam >/dev/null 2>&1", timeout=5)
        return result.returncode == 0
    except Exception:
        return False


def stop_host_steam(timeout=18):
    """Stop Steam cleanly without entering steam-jupiter/-pipewire."""
    if not host_steam_is_running():
        return False
    try:
        # IMPORTANT: /usr/bin/steam on current SteamOS is steam-jupiter and
        # injects -pipewire even for a shutdown invocation. Use the inner host
        # launcher directly so clicking Restart Steam cannot trigger ScreenCast
        # during the *shutdown* half of the restart either.
        _host_run(
            "if [ -x /usr/lib/steam/steam ]; then "
            "/usr/lib/steam/steam -shutdown; else steam -shutdown; fi "
            ">/dev/null 2>&1 || true",
            timeout=8,
        )
    except Exception:
        pass
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not host_steam_is_running():
            return True
        time.sleep(0.4)
    return False


def start_host_steam():
    """Start Steam visibly without SteamOS Jupiter's forced PipeWire capture.

    Current SteamOS ``/usr/bin/steam-jupiter`` launches the real client with
    ``-steamdeck -pipewire``. The forced ``-pipewire`` argument is what opens
    KDE's Screen Sharing chooser. For this Desktop Mode restart we call the
    inner launcher directly with ``-steamdeck`` but without ``-pipewire``.
    """
    code = r"""
import os, pathlib, shutil, subprocess

env = os.environ.copy()
keys = {"DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP"}
try:
    out = subprocess.check_output(["systemctl", "--user", "show-environment"], text=True, stderr=subprocess.DEVNULL)
    for line in out.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k in keys and v:
            env[k] = v
except Exception:
    pass

for proc_name in ("plasmashell", "kwin_wayland", "kwin_x11"):
    try:
        pids = subprocess.check_output(["pgrep", "-u", str(os.getuid()), "-x", proc_name], text=True, stderr=subprocess.DEVNULL).split()
    except Exception:
        pids = []
    for pid in reversed(pids):
        try:
            raw = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
            for item in raw:
                if b"=" not in item:
                    continue
                k, v = item.split(b"=", 1)
                k = k.decode("utf-8", "ignore")
                if k in keys and v:
                    env[k] = v.decode("utf-8", "ignore")
            break
        except Exception:
            continue
    if env.get("DISPLAY") or env.get("WAYLAND_DISPLAY"):
        break

for key in ("GIO_LAUNCHED_DESKTOP_FILE", "GIO_LAUNCHED_DESKTOP_FILE_PID", "DESKTOP_STARTUP_ID", "XDG_ACTIVATION_TOKEN"):
    env.pop(key, None)

direct = "/usr/lib/steam/steam"
if not pathlib.Path(direct).is_file():
    direct = shutil.which("steam") or "/usr/bin/steam"
args = [direct]
if direct == "/usr/lib/steam/steam":
    args.append("-steamdeck")
subprocess.Popen(args, env=env, stdin=subprocess.DEVNULL,
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 start_new_session=True, close_fds=True)
"""
    try:
        result = subprocess.run(
            ["flatpak-spawn", "--host", "python3", "-c", code],
            text=True, capture_output=True, timeout=8, check=False,
        )
        return result.returncode == 0
    except Exception:
        return False


def show_host_steam_window():
    """Restore/focus Steam without re-entering steam-jupiter/-pipewire."""
    if not host_steam_is_running():
        return False
    try:
        # Resolve the direct Steam launcher on the host, not inside Lutris'
        # Flatpak. This URI is only for the already-running client and must not
        # pass through /usr/bin/steam-jupiter, which would add -pipewire again.
        command = (
            "if [ -x /usr/lib/steam/steam ]; then "
            "/usr/lib/steam/steam 'steam://open/main'; "
            "else steam 'steam://open/main'; fi >/dev/null 2>&1"
        )
        result = _host_run(command, timeout=8)
        return result.returncode == 0
    except Exception:
        return False

def steam_root_from_user_config(config_path):
    """Convert .../Steam/userdata/<uid>/config to the Steam install root."""
    path = Path(config_path).expanduser()
    for parent in (path, *path.parents):
        if parent.name == "userdata":
            return parent.parent
    # Normal Lutris/SteamOS layout fallback.
    try:
        return path.parents[2]
    except IndexError:
        return None


def build_named_compatdata_view():
    """Build the friendly all-prefix view used by Settings.

    Internal OneClick Steam/Proton prefixes are REAL game-named directories in
    ``INTERNAL_PREFIX_ROOT``.  External prefixes must remain on their removable
    filesystem, so this same view adds game-named symlinks to those real
    external directories.  Steam's required numeric ``compatdata/<AppID>``
    compatibility links stay hidden from this user-facing view.
    """
    config_path = steam_shortcut.get_config_path()
    if not config_path:
        raise RuntimeError("Steam's active user/config folder could not be found.")
    steam_root = steam_root_from_user_config(config_path)
    if not steam_root:
        raise RuntimeError("Steam installation folder could not be determined.")
    compat_root = Path(steam_root) / "steamapps" / "compatdata"
    compat_root.mkdir(parents=True, exist_ok=True)
    INTERNAL_PREFIX_ROOT.mkdir(parents=True, exist_ok=True)

    # First normalize older external OneClick paths/folder names. This is safe
    # to run repeatedly and never moves game bytes between filesystems.
    try:
        migrate_external_steam_paths()
    except Exception:
        pass

    # Remove obsolete display-only view from V7.1.0-V7.1.6. Only links/files
    # inside that known folder are touched; real directories are never deleted.
    old_view = compat_root / "_OneClick - Game Names"
    if old_view.is_dir() and not old_view.is_symlink():
        safe_to_remove = True
        for child in list(old_view.iterdir()):
            try:
                if child.is_symlink() or child.is_file():
                    child.unlink()
                else:
                    safe_to_remove = False
            except Exception:
                safe_to_remove = False
        if safe_to_remove:
            try:
                old_view.rmdir()
            except Exception:
                pass

    def clean_name(value):
        value = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', ' - ', str(value or 'Game')).strip().strip('.')
        value = re.sub(r'\s+', ' ', value)
        return value[:110] or 'Game'

    def marker_appid(path):
        try:
            data = json.loads((Path(path) / ONECLICK_PREFIX_MARKER).read_text(encoding='utf-8'))
            return int(data.get('appid'))
        except Exception:
            return None

    def target_for(name, appid):
        base = clean_name(name)
        candidate = INTERNAL_PREFIX_ROOT / base
        if candidate.exists() and marker_appid(candidate) != appid:
            candidate = INTERNAL_PREFIX_ROOT / f'{base} [{appid}]'
        return candidate

    migrated = 0
    games = load_steam_native_registry()

    # Real internal game-name directories.
    for key, entry in games.items():
        if str(entry.get('status') or '') not in {'installed', 'pending_steam', 'detached'}:
            continue
        if str(entry.get('storage_mode') or 'internal').lower() == 'external':
            continue
        try:
            appid = int(entry.get('appid') or key)
        except Exception:
            continue
        name = str(entry.get('name') or f'Game {appid}')
        numeric = compat_root / str(appid)

        if numeric.is_symlink():
            old_target = numeric.resolve(strict=False)
            if old_target.exists() and marker_appid(old_target) == appid:
                if old_target.parent == compat_root:
                    target = target_for(name, appid)
                    if target.exists() and target.resolve(strict=False) != old_target.resolve(strict=False):
                        if marker_appid(target) != appid:
                            continue
                    try:
                        if old_target.resolve(strict=False) != target.resolve(strict=False):
                            old_target.rename(target)
                        numeric.unlink(missing_ok=True)
                        numeric.symlink_to(target, target_is_directory=True)
                        update_steam_native_registry(appid, compatdata=str(target))
                        migrated += 1
                    except Exception:
                        continue
                elif old_target == INTERNAL_PREFIX_ROOT or INTERNAL_PREFIX_ROOT in old_target.parents:
                    if str(entry.get('compatdata') or '') != str(old_target):
                        update_steam_native_registry(appid, compatdata=str(old_target))
                    migrated += 1
            continue

        # Older OneClick builds may still have the real prefix at the numeric
        # Steam path. Move only folders carrying our ownership marker.
        if not numeric.is_dir() or marker_appid(numeric) != appid:
            continue
        target = target_for(name, appid)
        if target.exists() and target.resolve(strict=False) != numeric.resolve(strict=False):
            if marker_appid(target) != appid:
                continue
        try:
            if numeric.resolve(strict=False) != target.resolve(strict=False):
                numeric.rename(target)
            numeric.symlink_to(target, target_is_directory=True)
            update_steam_native_registry(appid, compatdata=str(target))
            migrated += 1
        except Exception:
            continue

    # Rebuild only our external display links. Internal real directories are
    # never removed here.  Broken links are deliberately kept/recreated for
    # known disconnected drives so the game remains identifiable by name.
    for child in list(INTERNAL_PREFIX_ROOT.iterdir()):
        if not child.is_symlink():
            continue
        try:
            literal = os.readlink(child)
        except Exception:
            literal = ''
        if ('external-drive-links' in literal or '/run/media/' in literal or
                '/media/' in literal or 'OneClick Games/Steam-Proton' in literal):
            try:
                child.unlink()
            except Exception:
                pass

    external_targets = []
    seen_targets = set()

    def remember_external(name, appid, target):
        target = Path(str(target))
        key = str(target)
        if not key or key in seen_targets:
            return
        seen_targets.add(key)
        external_targets.append((clean_name(name), int(appid) if appid is not None else None, target))

    # Registry is authoritative and also works while a known drive is absent.
    games = load_steam_native_registry()
    for key, entry in games.items():
        if str(entry.get('status') or '') not in {'installed', 'pending_steam', 'detached'}:
            continue
        if str(entry.get('storage_mode') or '').lower() != 'external':
            continue
        try:
            appid = int(entry.get('appid') or key)
        except Exception:
            appid = None
        name = str(entry.get('name') or (f'Game {appid}' if appid is not None else 'Game'))
        compat = str(entry.get('compatdata') or '').strip()
        uuid_text = str(entry.get('storage_uuid') or '').strip()
        target = Path(compat) if compat else None
        if (target is None or not str(target).strip()) and uuid_text:
            alias = _refresh_external_drive_alias(uuid_text, try_mount=False)
            if alias is not None:
                target = alias / 'OneClick Games' / 'Steam-Proton' / _steam_named_prefix_name(name)
        if target is not None:
            remember_external(name, appid, target)

    # Discovery fallback for older registry rows: scan every known UUID alias
    # for real external OneClick Steam-Proton folders and use their marker/name.
    try:
        if EXTERNAL_ALIAS_ROOT.is_dir():
            for alias in EXTERNAL_ALIAS_ROOT.iterdir():
                external_root = alias / 'OneClick Games' / 'Steam-Proton'
                if not external_root.is_dir():
                    continue
                for target in external_root.iterdir():
                    if not target.is_dir():
                        continue
                    appid = marker_appid(target)
                    entry = games.get(str(appid), {}) if appid is not None else {}
                    name = str(entry.get('name') or re.sub(r'\s*\[\d+\]\s*$', '', target.name) or target.name)
                    remember_external(name, appid, target)
    except Exception:
        pass

    external_links = 0
    for name, appid, target in external_targets:
        link = INTERNAL_PREFIX_ROOT / name
        # If the same title also has a real internal prefix, make the external
        # location explicit rather than hiding/overwriting the real directory.
        if link.exists() and not link.is_symlink():
            link = INTERNAL_PREFIX_ROOT / f'{name} (External)'
        if (link.exists() and not link.is_symlink()) or (link.is_symlink() and appid is not None and marker_appid(link.resolve(strict=False)) not in {None, appid}):
            suffix = f' [{appid}]' if appid is not None else ''
            link = INTERNAL_PREFIX_ROOT / f'{name} (External){suffix}'
        try:
            if link.is_symlink() or link.exists():
                if link.is_symlink():
                    link.unlink()
                elif link.is_dir():
                    continue
            link.symlink_to(target, target_is_directory=True)
            external_links += 1
        except Exception:
            continue

    visible_count = sum(1 for p in INTERNAL_PREFIX_ROOT.iterdir() if p.is_dir() or p.is_symlink())
    return INTERNAL_PREFIX_ROOT, visible_count

def _matching_brace(text, open_index):
    depth = 0
    quoted = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def _find_vdf_named_block(text, name, start=0, end=None):
    limit = len(text) if end is None else min(len(text), end)
    match = re.search(r'"' + re.escape(str(name)) + r'"', text[start:limit], re.IGNORECASE)
    if not match:
        return None
    key_start = start + match.start()
    key_end = start + match.end()
    open_index = text.find("{", key_end, limit)
    if open_index < 0:
        return None
    close_index = _matching_brace(text, open_index)
    if close_index < 0 or close_index >= limit:
        return None
    return key_start, open_index, close_index


def remove_steam_compat_mapping(config_path, appid):
    """Remove Steam's forced-Proton mapping for this Lutris launcher shortcut."""
    steam_root = steam_root_from_user_config(config_path)
    if not steam_root:
        return False
    config_vdf = steam_root / "config" / "config.vdf"
    if not config_vdf.is_file():
        return False

    try:
        text = config_vdf.read_text(encoding="utf-8", errors="replace")
        outer = _find_vdf_named_block(text, "CompatToolMapping")
        if not outer:
            return False
        _, outer_open, outer_close = outer
        inner_start = outer_open + 1
        inner_end = outer_close
        entry = _find_vdf_named_block(text, str(appid), inner_start, inner_end)
        if not entry:
            return False
        key_start, _entry_open, entry_close = entry

        # Remove the complete entry including indentation and one trailing newline.
        line_start = text.rfind("\n", 0, key_start) + 1
        remove_end = entry_close + 1
        while remove_end < len(text) and text[remove_end] in " \t":
            remove_end += 1
        if remove_end < len(text) and text[remove_end] == "\r":
            remove_end += 1
        if remove_end < len(text) and text[remove_end] == "\n":
            remove_end += 1

        backup = config_vdf.with_name("config.vdf.lutris-oneclick.bak")
        if not backup.exists():
            shutil.copy2(config_vdf, backup)
        temp = config_vdf.with_suffix(".vdf.tmp")
        temp.write_text(text[:line_start] + text[remove_end:], encoding="utf-8")
        temp.replace(config_vdf)
        return True
    except Exception:
        return False


def remove_steam_launcher_compatdata(config_path, appid):
    """Delete only the Proton prefix Steam created around the Lutris launcher."""
    steam_root = steam_root_from_user_config(config_path)
    if not steam_root:
        return False
    path = steam_root / "steamapps" / "compatdata" / str(appid)
    try:
        if path.is_dir():
            shutil.rmtree(path)
            return True
    except Exception:
        return False
    return False


def remove_game_artwork_files(config_path, appid):
    """Remove Steam-applied artwork and our cached downloads for one shortcut."""
    removed = 0
    grid_dir = Path(config_path) / "grid"
    stems = (
        str(appid),
        f"{appid}p",
        f"{appid}_hero",
        f"{appid}_logo",
        f"{appid}_icon",
    )
    try:
        if grid_dir.is_dir():
            for stem in stems:
                for path in grid_dir.glob(stem + ".*"):
                    if path.is_file():
                        path.unlink()
                        removed += 1
    except Exception:
        pass

    try:
        cache_dir = SGDB_CACHE_ROOT / str(appid)
        if cache_dir.is_dir():
            shutil.rmtree(cache_dir)
            removed += 1
    except Exception:
        pass
    return removed


def _shortcut_field_text(shortcut, key):
    value = shortcut.get(key, "") if isinstance(shortcut, dict) else ""
    if isinstance(value, bytes):
        try:
            value = value.decode("utf-8", errors="replace")
        except Exception:
            value = str(value)
    return str(value or "").strip().strip('"')


def remove_lutris_shortcuts_direct(game_id, game_name="", expected_appid=None):
    """Remove every Steam shortcut that clearly belongs to this Lutris game.

    Lutris' generated AppID can change when the launch command/Flatpak wrapper
    format changes between Lutris/OneClick versions. Removing only today's
    generated AppID can therefore leave an older shortcut behind. Match both
    the expected AppID and the persistent Lutris game-id/wrapper signature.
    Returns the unsigned AppIDs that were removed so artwork/compatdata can be
    cleaned for *all* stale variants.
    """
    path = steam_shortcut.get_shortcuts_vdf_path()
    if not path or not os.path.exists(path):
        return []

    with open(path, "rb") as fh:
        root = steam_vdf.binary_loads(fh.read())
    current = list((root.get("shortcuts") or {}).values())

    gid = str(game_id or "").strip()
    wanted_name = normalize_game_name(game_name) if game_name else ""
    expected_u = None
    try:
        if expected_appid is not None:
            expected_u = int(expected_appid) & 0xffffffff
    except Exception:
        expected_u = None

    kept = []
    removed_ids = []
    for shortcut in current:
        try:
            sid_u = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            sid_u = 0
        exe = _shortcut_field_text(shortcut, "Exe")
        launch = _shortcut_field_text(shortcut, "LaunchOptions")
        app_name = _shortcut_field_text(shortcut, "AppName")
        exe_low = exe.casefold()
        launch_low = launch.casefold()

        gid_match = bool(gid) and (
            launch == gid
            or f"rungameid/{gid}" in launch_low
            or f"rungameid:{gid}" in launch_low
        )
        lutris_signature = (
            "oneclick-lutris-steam-launch" in exe_low
            or "net.lutris.lutris" in launch_low
            or "lutris:rungameid" in launch_low
            or ("lutris" in exe_low and gid_match)
        )
        appid_match = expected_u is not None and sid_u == expected_u
        name_match = bool(wanted_name) and normalize_game_name(app_name) == wanted_name and lutris_signature

        if appid_match or gid_match or name_match:
            if sid_u and sid_u not in removed_ids:
                removed_ids.append(sid_u)
            continue
        kept.append(shortcut)

    if len(kept) != len(current):
        backup = path + ".oneclick-remove.bak"
        if not os.path.exists(backup):
            try:
                shutil.copy2(path, backup)
            except Exception:
                pass
        updated = {"shortcuts": {str(index): item for index, item in enumerate(kept)}}
        temp = path + f".oneclick-{os.getpid()}.tmp"
        with open(temp, "wb") as fh:
            fh.write(steam_vdf.binary_dumps(updated))
        os.replace(temp, path)

    return removed_ids


def steam_native_shortcut_exists(appid):
    appid_u = int(appid) & 0xffffffff
    try:
        for shortcut in steam_shortcut.get_shortcuts().values():
            try:
                sid = int(shortcut.get("appid", 0)) & 0xffffffff
            except Exception:
                sid = 0
            if sid == appid_u:
                return True
    except Exception:
        return False
    return False


def repair_steam_native_registry_from_owned_prefixes():
    """Recover Moses Steam metadata from the active Steam shortcuts.

    Stable V7.4.46 stored already-complete games in ``steam-native-games.json``.
    Some experimental builds could damage/replace that registry while leaving
    both the game folders and Steam shortcuts untouched.  Older recovery only
    trusted folders carrying ``.oneclick-exe-prefix.json``.  That missed games
    added through **Find Game EXE + Add to Steam**, because that workflow is not
    an installer and intentionally does not turn the selected game directory
    into a Proton-prefix folder or write a prefix-ownership marker there.

    Recovery is now based on two conservative proofs:
      1. an active Steam shortcut whose AppID matches a Moses-owned prefix marker; or
      2. an active Steam shortcut whose EXE/StartDir physically lives underneath
         Moses' own ``game-prefixes/Steam-Proton`` root.

    This restores complete-game imports such as RDR2/Spider-Man without scanning
    arbitrary Steam shortcuts or arbitrary folders elsewhere on disk.
    """
    try:
        shortcuts = list(steam_shortcut.get_shortcuts().values())
    except Exception:
        return 0

    if not shortcuts or not INTERNAL_PREFIX_ROOT.is_dir():
        return 0

    registry = load_steam_native_registry()
    changed = 0

    try:
        internal_root = INTERNAL_PREFIX_ROOT.expanduser().resolve(strict=False)
    except Exception:
        internal_root = INTERNAL_PREFIX_ROOT.expanduser()

    def clean_quoted(value):
        text = str(value or "").strip()
        if len(text) >= 2 and text[0] == text[-1] == '"':
            text = text[1:-1]
        return text

    def internal_game_root(value):
        """Return the first game-named folder under Moses' internal root."""
        text = clean_quoted(value)
        if not text:
            return None
        try:
            path = Path(text).expanduser().resolve(strict=False)
            rel = path.relative_to(internal_root)
        except Exception:
            return None
        if not rel.parts:
            return None
        first = str(rel.parts[0])
        # Never resurrect hidden StreamExtract staging/recovery plumbing as games.
        if not first or first.startswith('.') or first.startswith('_'):
            return None
        return internal_root / first

    # Build a marker map first.  This keeps the old strong ownership proof while
    # allowing complete-game shortcuts to be recovered without such a marker.
    marker_by_appid = {}
    try:
        for prefix in INTERNAL_PREFIX_ROOT.iterdir():
            if not prefix.is_dir():
                continue
            marker = prefix / ONECLICK_PREFIX_MARKER
            if not marker.is_file():
                continue
            try:
                marker_data = json.loads(marker.read_text(encoding="utf-8"))
                marker_appid = int(marker_data.get("appid")) & 0xffffffff
            except Exception:
                continue
            if marker_appid:
                marker_by_appid[marker_appid] = prefix
    except Exception:
        pass

    for shortcut in shortcuts:
        try:
            appid = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            continue
        if not appid:
            continue

        exe = clean_quoted(shortcut.get("Exe"))
        start_dir = clean_quoted(shortcut.get("StartDir"))
        exe_root = internal_game_root(exe)
        start_root = internal_game_root(start_dir)
        game_root = exe_root or start_root
        marker_root = marker_by_appid.get(appid)

        # Do not import ordinary Steam/non-Steam shortcuts.  At least one side
        # must prove the entry belongs to Moses.
        if marker_root is None and game_root is None:
            continue

        key = str(appid)
        entry = dict(registry.get(key) or {})
        app_name = str(shortcut.get("AppName") or "").strip()
        if not app_name:
            app_name = (game_root or marker_root).name

        # If an experimental build left a removal tombstone but the user still
        # has an ACTIVE shortcut into an existing Moses folder, this is the live
        # game.  Recover it instead of hiding it from the manager.
        new_entry = dict(entry)
        new_entry.update({
            "appid": int(appid),
            "name": app_name,
            "status": "installed",
            "backend": "steam",
            "storage_mode": str(entry.get("storage_mode") or "internal"),
        })

        # Preserve the exact shortcut target chosen by the user (Launcher.exe is
        # valid; Moses must not silently retarget it to another EXE).
        try:
            if exe and Path(exe).expanduser().is_file():
                new_entry["final_exe"] = exe
        except Exception:
            if exe:
                new_entry["final_exe"] = exe
        try:
            if start_dir and Path(start_dir).expanduser().is_dir():
                new_entry["start_dir"] = start_dir
        except Exception:
            if start_dir:
                new_entry["start_dir"] = start_dir

        # Only a real ownership marker proves that the game-named folder itself
        # is the OneClick Proton compatdata location.  For Add Existing games the
        # game folder merely contains files, while Steam creates compatdata later.
        if marker_root is not None:
            new_entry["compatdata"] = str(marker_root)
        elif not str(new_entry.get("compatdata") or "").strip():
            # Leave compatdata empty rather than lying.  Per-game Proton actions
            # can resolve Steam's numeric compatdata from this AppID when needed.
            new_entry.pop("compatdata", None)

        if new_entry != entry:
            registry[key] = new_entry
            changed += 1

    if changed:
        save_steam_native_registry(registry)
    return changed


def find_lutris_shortcut_appid(game_id, game_name, expected_appid):
    """Return the real Steam shortcut AppID for a OneClick/Lutris game.

    Lutris' shortcut_exists(game) can return False for OneClick shortcuts
    because OneClick intentionally swaps Lutris' Flatpak command for the
    host-side oneclick-lutris-steam-launch wrapper. Artwork does not need to
    reject that valid shortcut. Match the stable expected AppID first, then the
    wrapper + LaunchOptions game ID used by OneClick (including older formats).

    The second tuple item says whether an existing shortcut was observed. If no
    shortcut is visible yet, callers may still stage artwork under the expected
    AppID; a later shortcut finalize/repair uses that same ID.
    """
    try:
        expected_u = int(expected_appid) & 0xffffffff
    except Exception:
        expected_u = 0
    wanted_id = str(game_id or "").strip().strip('"')
    wanted_name = str(game_name or "").strip().casefold()

    try:
        shortcuts = list(steam_shortcut.get_shortcuts().values())
    except Exception:
        return expected_u, False

    # Exact generated AppID is the strongest signal and avoids name ambiguity.
    for shortcut in shortcuts:
        try:
            sid = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            continue
        if expected_u and sid == expected_u:
            return sid, True

    # OneClick's SteamOS-safe Lutris shortcut deliberately changes Exe, so
    # identify it from the wrapper signature + Lutris game id instead.
    for shortcut in shortcuts:
        try:
            sid = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            continue
        exe = str(shortcut.get("Exe", "") or "").strip().strip('"').casefold()
        launch = str(shortcut.get("LaunchOptions", "") or "").strip().strip('"')
        app_name = str(shortcut.get("AppName", "") or "").strip().casefold()
        oneclick_lutris = (
            "oneclick-lutris-steam-launch" in exe
            or ("flatpak" in exe and "lutris" in launch.casefold())
        )
        if oneclick_lutris and wanted_id and launch == wanted_id:
            return sid, True
        if oneclick_lutris and wanted_name and app_name == wanted_name:
            return sid, True

    return expected_u, False


def steam_native_upsert_shortcut(appid, game_name, exe_path, start_dir, icon_path="", launch_options=""):
    path = steam_shortcut.get_shortcuts_vdf_path()
    if not path:
        raise RuntimeError("Steam active-user shortcuts.vdf could not be located.")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            root = steam_vdf.binary_loads(fh.read())
        current = list((root.get("shortcuts") or {}).values())
        backup = path + ".oneclick.bak"
        if not os.path.exists(backup):
            shutil.copy2(path, backup)
    else:
        current = []
    appid_u = int(appid) & 0xffffffff
    appid_s = appid_u if appid_u < 0x80000000 else appid_u - 0x100000000
    kept = []
    for shortcut in current:
        try:
            sid = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            sid = 0
        if sid != appid_u:
            kept.append(shortcut)
    kept.append({
        "appid": appid_s,
        "AppName": str(game_name),
        "Exe": '"' + str(exe_path) + '"',
        "StartDir": '"' + str(start_dir) + '"',
        "icon": str(icon_path or ""),
        "ShortcutPath": "",
        "LaunchOptions": str(launch_options or ""),
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "tags": {},
    })
    updated = {"shortcuts": {str(index): item for index, item in enumerate(kept)}}
    with open(path, "wb") as fh:
        fh.write(steam_vdf.binary_dumps(updated))


def steam_native_remove_shortcut(appid):
    path = steam_shortcut.get_shortcuts_vdf_path()
    if not path or not os.path.exists(path):
        return False
    with open(path, "rb") as fh:
        root = steam_vdf.binary_loads(fh.read())
    current = list((root.get("shortcuts") or {}).values())
    appid_u = int(appid) & 0xffffffff
    kept = []
    removed = False
    for shortcut in current:
        try:
            sid = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            sid = 0
        if sid == appid_u:
            removed = True
        else:
            kept.append(shortcut)
    if removed:
        updated = {"shortcuts": {str(index): item for index, item in enumerate(kept)}}
        with open(path, "wb") as fh:
            fh.write(steam_vdf.binary_dumps(updated))
    return removed


def steam_native_remove_managed_shortcuts(appid, game_name="", final_exe=""):
    """Remove the OneClick Steam-native shortcut, including stale AppID variants.

    Primary identity is the stable OneClick AppID. For older/corrupted shortcut
    rows, an exact AppName + final EXE match is accepted as a safe fallback.
    Returns every unsigned shortcut AppID removed so artwork can be cleaned too.
    """
    path = steam_shortcut.get_shortcuts_vdf_path()
    if not path or not os.path.exists(path):
        return set()
    with open(path, "rb") as fh:
        root = steam_vdf.binary_loads(fh.read())
    current = list((root.get("shortcuts") or {}).values())
    expected = int(appid) & 0xffffffff
    wanted_name = str(game_name or "").strip().casefold()
    wanted_exe = os.path.normcase(os.path.normpath(str(final_exe or "").strip().strip('"'))) if final_exe else ""
    kept = []
    removed_ids = set()
    for shortcut in current:
        try:
            sid = int(shortcut.get("appid", 0)) & 0xffffffff
        except Exception:
            sid = 0
        app_name = str(shortcut.get("AppName") or shortcut.get("appname") or "").strip().casefold()
        exe = str(shortcut.get("Exe") or shortcut.get("exe") or "").strip().strip('"')
        exe_norm = os.path.normcase(os.path.normpath(exe)) if exe else ""
        exact_id = sid == expected
        exact_name = bool(wanted_name and app_name == wanted_name)
        exact_fallback = bool(wanted_name and wanted_exe and app_name == wanted_name and exe_norm == wanted_exe)
        # shortcuts.vdf contains only non-Steam shortcuts.  For a game that
        # Moses OneClick Tool is explicitly removing, an exact AppName is a
        # safe cleanup fallback for stale shortcut AppIDs left by older builds.
        if exact_id or exact_fallback or exact_name:
            removed_ids.add(sid)
        else:
            kept.append(shortcut)
    if removed_ids:
        backup = path + ".oneclick-remove.bak"
        if not os.path.exists(backup):
            try:
                shutil.copy2(path, backup)
            except Exception:
                pass
        updated = {"shortcuts": {str(index): item for index, item in enumerate(kept)}}
        with open(path, "wb") as fh:
            fh.write(steam_vdf.binary_dumps(updated))

        # Verify the actual shortcuts.vdf after writing. Complete Removal must
        # never claim success while the non-Steam shortcut is still present.
        try:
            with open(path, "rb") as fh:
                verify_root = steam_vdf.binary_loads(fh.read())
            leftovers = []
            for shortcut in (verify_root.get("shortcuts") or {}).values():
                try:
                    sid = int(shortcut.get("appid", 0)) & 0xffffffff
                except Exception:
                    sid = 0
                app_name = str(shortcut.get("AppName") or shortcut.get("appname") or "").strip().casefold()
                if sid == expected or (wanted_name and app_name == wanted_name):
                    leftovers.append(app_name or str(sid))
            if leftovers:
                raise RuntimeError("Steam shortcut removal could not be verified. Close Steam completely and retry Complete Game Removal.")
        except RuntimeError:
            raise
        except Exception as exc:
            raise RuntimeError(f"Could not verify Steam shortcut removal: {exc}") from exc
    return removed_ids


def steam_compat_mapping_exists(config_path, appid):
    steam_root = steam_root_from_user_config(config_path)
    if not steam_root:
        return False
    path = steam_root / "config" / "config.vdf"
    if not path.is_file():
        return False
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        outer = _find_vdf_named_block(text, "CompatToolMapping")
        if not outer:
            return False
        _, open_i, close_i = outer
        return _find_vdf_named_block(text, str(int(appid)), open_i + 1, close_i) is not None
    except Exception:
        return False


def ensure_steam_compat_mapping(config_path, appid, tool=DEFAULT_STEAM_COMPAT_TOOL):
    if steam_compat_mapping_exists(config_path, appid):
        return False
    steam_root = steam_root_from_user_config(config_path)
    if not steam_root:
        raise RuntimeError("Steam installation folder could not be found.")
    path = steam_root / "config" / "config.vdf"
    text = path.read_text(encoding="utf-8", errors="replace")
    outer = _find_vdf_named_block(text, "CompatToolMapping")
    if not outer:
        raise RuntimeError("Steam CompatToolMapping section was not found.")
    _, _open_i, close_i = outer
    snippet = (
        f'\n\t\t\t\t\t\t"{int(appid)}"\n'
        '\t\t\t\t\t\t{\n'
        f'\t\t\t\t\t\t\t"name"\t\t"{tool}"\n'
        '\t\t\t\t\t\t\t"config"\t\t""\n'
        '\t\t\t\t\t\t\t"Priority"\t\t"250"\n'
        '\t\t\t\t\t\t}\n'
    )
    backup = path.with_name("config.vdf.oneclick.bak")
    if not backup.exists():
        shutil.copy2(path, backup)
    temp = path.with_suffix(".vdf.tmp")
    temp.write_text(text[:close_i] + snippet + text[close_i:], encoding="utf-8")
    temp.replace(path)
    return True


def build_ssl_context():
    candidates = [
        os.environ.get("SSL_CERT_FILE", ""),
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/ssl/cert.pem",
        "/etc/pki/tls/certs/ca-bundle.crt",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            try:
                return ssl.create_default_context(cafile=candidate)
            except Exception:
                pass
    return ssl.create_default_context()


SGDB_SSL_CONTEXT = build_ssl_context()


def sgdb_error_text(payload):
    if not isinstance(payload, dict):
        return "Unknown SteamGridDB error."
    errors = payload.get("errors")
    if isinstance(errors, list) and errors:
        return ", ".join(str(x) for x in errors)
    if isinstance(errors, str) and errors:
        return errors
    return "Unknown SteamGridDB error."


def _sgdb_get_once(path, api_key, params=None):
    url = SGDB_BASE_URL + path
    if params:
        url += "?" + urllib.parse.urlencode(params)

    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "User-Agent": SGDB_USER_AGENT,
        },
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=SGDB_API_TIMEOUT,
            context=SGDB_SSL_CONTEXT,
        ) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read().decode("utf-8", "replace"))
            detail = sgdb_error_text(payload)
        except Exception:
            detail = str(exc.reason or exc)

        if exc.code in (401, 403):
            raise RuntimeError(
                "SteamGridDB rejected the API key. Check that it was copied correctly."
            ) from exc
        if exc.code == 429:
            raise RuntimeError(
                "SteamGridDB rate limit reached. Wait a little and try again."
            ) from exc
        raise RuntimeError(f"SteamGridDB request failed ({exc.code}): {detail}") from exc
    except urllib.error.URLError as exc:
        reason = str(getattr(exc, "reason", exc))
        if "CERTIFICATE_VERIFY_FAILED" in reason:
            raise RuntimeError(
                "Could not verify SteamGridDB's HTTPS certificate. "
                "SteamOS/Lutris may need its certificate store refreshed."
            ) from exc
        raise RuntimeError(f"Could not reach SteamGridDB: {reason}") from exc
    except ssl.SSLError as exc:
        raise RuntimeError(f"SteamGridDB HTTPS check failed: {exc}") from exc
    except (TimeoutError, ConnectionError, OSError) as exc:
        raise RuntimeError(f"Could not reach SteamGridDB: {exc}") from exc

    try:
        payload = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError("SteamGridDB returned an unreadable response.") from exc

    if not isinstance(payload, dict) or not payload.get("success"):
        raise RuntimeError(sgdb_error_text(payload))
    return payload.get("data")


def sgdb_get(path, api_key, params=None):
    """SteamGridDB request with one fast retry for transient network errors."""
    last_error = None
    for attempt in range(2):
        try:
            return _sgdb_get_once(path, api_key, params)
        except RuntimeError as exc:
            last_error = exc
            message = str(exc).lower()
            # Never retry credentials/rate-limit/client-side failures.
            if (
                "rejected the api key" in message
                or "rate limit" in message
                or "request failed (4" in message
            ):
                raise
            if attempt == 0:
                time.sleep(0.20)
    raise last_error


def get_json_url(url, timeout, label):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": SGDB_USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(
            request,
            timeout=timeout,
            context=SGDB_SSL_CONTEXT,
        ) as response:
            raw = response.read()
    except Exception as exc:
        raise RuntimeError(f"Could not reach {label}: {exc}") from exc
    try:
        return json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError(f"{label} returned an unreadable response.") from exc

def normalize_game_name(text):
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.casefold().replace("&", " and ")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def _append_unique_title(values, text):
    text = re.sub(r"\s+", " ", str(text or "")).strip(" -_:")
    if not text:
        return
    norm = normalize_game_name(text)
    if not norm:
        return
    if all(normalize_game_name(existing) != norm for existing in values):
        values.append(text)


def game_title_variants(game_name, extra_hints=None):
    """Generate conservative search aliases without blindly shortening titles.

    This specifically handles common installer/library labels such as
    "Deadpool the Video Game" while retaining the original title as the
    highest-priority query. Folder/EXE hints are only used when they look like
    human game names rather than generic Windows directories.
    """
    variants = []
    _append_unique_title(variants, game_name)

    base = re.sub(r"\s+", " ", str(game_name or "")).strip()
    safe_suffixes = [
        r"\s*[-:–—]?\s*(?:the\s+)?video\s+game$",
        r"\s*[-:–—]?\s*pc\s+version$",
        r"\s*[-:–—]?\s*windows\s+version$",
    ]
    for pattern in safe_suffixes:
        shortened = re.sub(pattern, "", base, flags=re.IGNORECASE).strip(" -_:.()[]")
        if shortened and shortened != base:
            _append_unique_title(variants, shortened)

    # Mild bracket cleanup is useful for labels like "Game (2013)" or
    # "Game [x64]". Never remove an arbitrary subtitle here.
    bracket_raw = re.sub(
        r"\s*[\[(](?:(?:19|20)\d{2}|x64|x86|64[- ]?bit|32[- ]?bit|windows|pc)[\])]\s*$",
        "",
        base,
        flags=re.IGNORECASE,
    )
    if bracket_raw != base:
        bracket_clean = bracket_raw.strip(" -_:.()[]")
        if bracket_clean:
            _append_unique_title(variants, bracket_clean)

    generic_dirs = {
        "bin", "binaries", "binary", "win64", "win32", "x64", "x86",
        "game", "games", "program files", "program files x86", "drive c",
        "gog games", "steamapps", "common",
    }
    for hint in extra_hints or []:
        hint = str(hint or "").strip()
        if not hint:
            continue
        hint = re.sub(r"\.(?:exe|bat|cmd|lnk)$", "", hint, flags=re.IGNORECASE)
        hint = re.sub(r"[_]+", " ", hint)
        hint = re.sub(r"\s+", " ", hint).strip(" -_:.()[]")
        if not hint or normalize_game_name(hint) in generic_dirs:
            continue
        if len(normalize_game_name(hint)) < 3:
            continue
        _append_unique_title(variants, hint)

    return variants[:6]


def _result_types(item):
    raw = item.get("types") if isinstance(item, dict) else None
    if isinstance(raw, list):
        return {str(x).casefold() for x in raw}
    if raw:
        return {str(raw).casefold()}
    return set()


def choose_game_match(query, results, aliases=None):
    if not isinstance(results, list) or not results:
        raise RuntimeError(f'No SteamGridDB match was found for "{query}".')

    alias_values = game_title_variants(query, aliases)
    normalized_aliases = [normalize_game_name(x) for x in alias_values if normalize_game_name(x)]
    original = normalize_game_name(query)

    exact = []
    for item in results:
        candidate = normalize_game_name(str(item.get("name", "")))
        if candidate and candidate in normalized_aliases:
            alias_index = normalized_aliases.index(candidate)
            types = _result_types(item)
            exact.append((
                alias_index,
                0 if "steam" in types else 1,
                0 if item.get("verified") else 1,
                item,
            ))
    if exact:
        exact.sort(key=lambda row: row[:3])
        return exact[0][3]

    ranked = []
    console_types = {"nes", "snes", "n64", "switch", "ps1", "ps2", "ps3", "ps4", "ps5", "xbox", "wii", "wiiu"}
    for item in results:
        candidate = normalize_game_name(str(item.get("name", "")))
        if not candidate:
            continue
        candidate_tokens = set(candidate.split())
        best_score = 0.0
        for alias in normalized_aliases or [original]:
            alias_tokens = set(alias.split())
            score = SequenceMatcher(None, alias, candidate).ratio()
            if alias_tokens and candidate_tokens:
                overlap = len(alias_tokens & candidate_tokens) / max(len(alias_tokens), len(candidate_tokens))
                score = max(score, overlap)
                # A candidate with extra words is risky (e.g. Deadpool (NES)
                # when searching Deadpool), so penalize extra candidate tokens.
                extra_candidate = candidate_tokens - alias_tokens
                if extra_candidate:
                    score -= min(0.24, 0.08 * len(extra_candidate))
                # If the only extra words are harmless descriptive suffix words
                # in our query, reward the shorter canonical database title.
                extra_alias = alias_tokens - candidate_tokens
                harmless = {"the", "video", "game", "pc", "windows", "version"}
                if candidate_tokens and candidate_tokens.issubset(alias_tokens) and extra_alias <= harmless:
                    score += 0.16
            best_score = max(best_score, score)

        types = _result_types(item)
        if "steam" in types:
            best_score += 0.06
        elif types & console_types:
            best_score -= 0.10
        if item.get("verified"):
            best_score += 0.03
        ranked.append((best_score, item))

    ranked.sort(key=lambda pair: pair[0], reverse=True)
    score, best = ranked[0]
    if score < 0.76:
        suggestions = ", ".join(
            str(item.get("name", "")) for _score, item in ranked[:4]
        )
        raise RuntimeError(
            f'Could not confidently match "{query}" on SteamGridDB. '
            f"Closest results: {suggestions or 'none'}."
        )
    return best


def sgdb_candidate_options(game_name, api_key, extra_hints=None, limit=5):
    """Return a short ranked list for the rare manual ambiguity chooser."""
    variants = game_title_variants(game_name, extra_hints)
    gathered = {}
    for search_title in variants[:6]:
        try:
            results = sgdb_get(
                "/search/autocomplete/" + urllib.parse.quote(search_title, safe=""),
                api_key,
            )
        except Exception:
            continue
        for item in results or []:
            if isinstance(item, dict) and item.get("id") is not None:
                gathered[str(item["id"])] = item

    aliases = [normalize_game_name(x) for x in variants if normalize_game_name(x)]
    wanted = normalize_game_name(game_name)
    console_types = {"nes", "snes", "n64", "switch", "ps1", "ps2", "ps3", "ps4", "ps5", "xbox", "wii", "wiiu"}
    ranked = []
    for item in gathered.values():
        candidate = normalize_game_name(str(item.get("name") or ""))
        if not candidate:
            continue
        score = max([SequenceMatcher(None, alias, candidate).ratio() for alias in aliases] or [SequenceMatcher(None, wanted, candidate).ratio()])
        types = _result_types(item)
        if candidate in aliases:
            score += 0.40
        if "steam" in types:
            score += 0.12
        if types & console_types:
            score -= 0.12
        if item.get("verified"):
            score += 0.05
        ranked.append((score, item))
    ranked.sort(key=lambda pair: pair[0], reverse=True)
    return [dict(item) for _score, item in ranked[:max(3, min(5, int(limit)))]]


def search_sgdb_game(game_name, api_key, extra_hints=None):
    """Search original title first, then safe aliases, deduplicating results."""
    variants = game_title_variants(game_name, extra_hints)
    gathered = {}
    last_error = None

    for search_title in variants:
        try:
            search_path = "/search/autocomplete/" + urllib.parse.quote(search_title, safe="")
            results = sgdb_get(search_path, api_key)
            if isinstance(results, list):
                for item in results:
                    if isinstance(item, dict) and item.get("id") is not None:
                        gathered[str(item.get("id"))] = item
            if gathered:
                try:
                    match = choose_game_match(game_name, list(gathered.values()), aliases=variants)
                    return match, search_title
                except RuntimeError as exc:
                    last_error = exc
        except Exception as exc:
            last_error = exc

    if gathered:
        return choose_game_match(game_name, list(gathered.values()), aliases=variants), (variants[-1] if variants else game_name)
    if last_error:
        raise last_error
    raise RuntimeError(f'No SteamGridDB match was found for "{game_name}".')


def choose_steam_match(query, results, aliases=None):
    """Conservatively choose a Steam Store result from a title-only search."""
    if not isinstance(results, list) or not results:
        return None

    usable = []
    for item in results:
        if not isinstance(item, dict) or not item.get("id"):
            continue
        item_type = str(item.get("type") or "app").lower()
        if item_type not in ("app", "game"):
            continue
        usable.append(item)
    if not usable:
        return None

    alias_values = game_title_variants(query, aliases)
    wanted_aliases = [normalize_game_name(x) for x in alias_values if normalize_game_name(x)]
    exact = [
        item for item in usable
        if normalize_game_name(str(item.get("name", ""))) in wanted_aliases
    ]
    if exact:
        exact.sort(key=lambda item: wanted_aliases.index(normalize_game_name(str(item.get("name", "")))))
        return exact[0]

    ranked = []
    for item in usable:
        candidate = normalize_game_name(str(item.get("name", "")))
        ratio = max(
            (SequenceMatcher(None, wanted, candidate).ratio() for wanted in wanted_aliases),
            default=0.0,
        ) if candidate else 0.0
        # Slightly reward containment, but remain conservative with editions/sequels.
        if candidate and any(wanted and (wanted in candidate or candidate in wanted) for wanted in wanted_aliases):
            ratio += 0.04
        ranked.append((ratio, item))
    ranked.sort(key=lambda pair: pair[0], reverse=True)
    if not ranked or ranked[0][0] < 0.82:
        return None
    return ranked[0][1]


def build_store_asset_url(asset_url_format, filename):
    asset_url_format = str(asset_url_format or "").strip()
    filename = str(filename or "").strip()
    if not asset_url_format or not filename:
        return ""
    return STEAM_ASSET_BASE_URL + asset_url_format.replace("${FILENAME}", filename)


def fetch_steam_store_item(appid):
    payload = {
        "ids": [{"appid": int(appid)}],
        "context": {
            "language": "english",
            "country_code": "US",
            "steam_realm": 1,
        },
        "data_request": {
            "include_basic_info": True,
            "include_assets": True,
        },
    }
    query = urllib.parse.urlencode({
        "input_json": json.dumps(payload, separators=(",", ":")),
    })
    data = get_json_url(
        STEAM_STORE_BROWSE_URL + "?" + query,
        STEAM_API_TIMEOUT,
        "Steam",
    )
    items = ((data or {}).get("response") or {}).get("store_items") or []
    for item in items:
        if isinstance(item, dict) and int(item.get("appid") or 0) == int(appid):
            return item
    return None


def resolve_steam_official(game_name, cached_appid=None, cached_name=None, search_hints=None):
    """Resolve a Steam AppID from the title, then fetch official asset metadata.

    Failure is intentionally non-fatal: SteamGridDB remains the primary source,
    and many GOG/Lutris titles may not have a Steam release at all.
    """
    appid = None
    matched_name = str(cached_name or "")
    if cached_appid:
        try:
            appid = int(cached_appid)
        except Exception:
            appid = None

    if appid is None:
        variants = game_title_variants(game_name, search_hints)
        gathered = {}
        match = None
        for search_title in variants[:4]:
            query = urllib.parse.urlencode({
                "term": search_title,
                "l": "english",
                "cc": "US",
            })
            data = get_json_url(
                STEAM_STORE_SEARCH_URL + "?" + query,
                STEAM_API_TIMEOUT,
                "Steam Store search",
            )
            for item in (data or {}).get("items") or []:
                if isinstance(item, dict) and item.get("id"):
                    gathered[str(item.get("id"))] = item
            match = choose_steam_match(game_name, list(gathered.values()), aliases=variants)
            if match is not None:
                break
        if match is None:
            return None
        appid = int(match["id"])
        matched_name = str(match.get("name") or game_name)

    store_item = None
    try:
        store_item = fetch_steam_store_item(appid)
        if isinstance(store_item, dict) and store_item.get("name"):
            matched_name = str(store_item.get("name"))
    except Exception:
        # Legacy direct CDN URLs below can still rescue header/logo on many apps.
        store_item = None

    return {
        "appid": appid,
        "name": matched_name or game_name,
        "item": store_item or {},
    }


def official_steam_urls(steam_info, spec_key):
    """Return deduplicated Valve-hosted candidates for one Steam artwork slot.

    Prefer the exact filenames returned by StoreBrowse when available.  Logo
    filenames are not currently exposed by StoreBrowse, so use Valve's normal
    unhashed/legacy library logo URLs as official candidates for that slot.
    """
    if not isinstance(steam_info, dict) or not steam_info.get("appid"):
        return []

    appid = int(steam_info["appid"])
    item = steam_info.get("item") or {}
    assets = item.get("assets") if isinstance(item, dict) else {}
    if not isinstance(assets, dict):
        assets = {}
    fmt = assets.get("asset_url_format")

    keys_by_type = {
        "capsule": ("library_capsule_2x", "library_capsule"),
        "wide_capsule": ("header_2x", "header"),
        "hero": ("library_hero_2x", "library_hero"),
        # StoreBrowse's Assets protobuf currently has no library-logo field.
        "logo": (),
        # community_icon is a SHA/hash, not a store_item_assets filename.
        "icon": (),
    }

    urls = []
    for key in keys_by_type.get(spec_key, ()):
        url = build_store_asset_url(fmt, assets.get(key))
        if url:
            urls.append(url)

    shared_unhashed = f"https://shared.steamstatic.com/store_item_assets/steam/apps/{appid}"
    legacy = f"{STEAM_LEGACY_ASSET_BASE_URL}/{appid}"

    if spec_key == "icon":
        icon_hash = str(assets.get("community_icon") or "").strip()
        if icon_hash:
            urls.extend([
                f"https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{appid}/{icon_hash}.jpg",
                f"https://steamcdn-a.akamaihd.net/steamcommunity/public/images/apps/{appid}/{icon_hash}.jpg",
            ])
        # Some titles also publish direct icon assets. These are only tried
        # after the hash-based official community icon.
        urls.extend([
            f"{shared_unhashed}/icon.png",
            f"{shared_unhashed}/icon.ico",
            f"{legacy}/icon.png",
            f"{legacy}/icon.ico",
        ])
    elif spec_key == "logo":
        # Valve's traditional Steam library logo endpoints. logo_2x is tried
        # first, then the normal logo. Keep both CDN layouts for compatibility
        # with older and newer titles.
        urls.extend([
            f"{legacy}/logo_2x.png",
            f"{legacy}/logo.png",
            f"{shared_unhashed}/logo_2x.png",
            f"{shared_unhashed}/logo.png",
        ])
    elif spec_key == "capsule":
        urls.extend([
            f"{legacy}/library_600x900_2x.jpg",
            f"{legacy}/library_600x900.jpg",
        ])
    elif spec_key == "wide_capsule":
        urls.extend([
            f"{legacy}/header_2x.jpg",
            f"{legacy}/header.jpg",
        ])
    elif spec_key == "hero":
        urls.extend([
            f"{legacy}/library_hero_2x.jpg",
            f"{legacy}/library_hero.jpg",
        ])

    deduped = []
    seen = set()
    for url in urls:
        url = str(url or "").strip()
        if url and url not in seen:
            seen.add(url)
            deduped.append(url)
    return deduped


def asset_extension(url):
    suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if suffix == ".jpeg":
        return ".jpg"
    if suffix in {".png", ".jpg", ".webp", ".ico"}:
        return suffix
    return ".png"


def rank_assets(items, preferred_dimensions=()):
    """Keep SteamGridDB's canonical result order.

    SteamGridDB already returns a ranked asset list. Older Moses builds
    re-sorted that list locally by dimensions, the legacy ``score`` field,
    upvotes and pixel area. That could promote an asset that appears much
    farther down on SteamGridDB (for example choice #7) over choice #1/#2.

    The API request already asks SteamGridDB for compatible dimensions, so
    the safest and most predictable policy is to preserve the provider order
    exactly and only use choice #2 if choice #1 cannot be downloaded.
    """
    if not isinstance(items, list) or not items:
        return []
    return [item for item in items if isinstance(item, dict)]


def remove_asset_siblings(grid_dir, stem, keep=None):
    for suffix in (".png", ".jpg", ".jpeg", ".webp", ".ico"):
        candidate = grid_dir / f"{stem}{suffix}"
        if keep is not None and candidate == keep:
            continue
        try:
            if candidate.exists():
                candidate.unlink()
        except OSError:
            pass


def download_file(url, target, timeout=SGDB_IMAGE_TIMEOUT):
    request = urllib.request.Request(
        url,
        headers={"User-Agent": SGDB_USER_AGENT},
    )
    temp = target.with_suffix(target.suffix + ".part")
    try:
        with urllib.request.urlopen(
            request,
            timeout=timeout,
            context=SGDB_SSL_CONTEXT,
        ) as response, open(temp, "wb") as output:
            shutil.copyfileobj(response, output)
        if temp.stat().st_size <= 0:
            raise RuntimeError("downloaded file was empty")
        temp.replace(target)
    finally:
        try:
            if temp.exists():
                temp.unlink()
        except OSError:
            pass


def download_file_with_retry(url, target, timeout, attempts=1):
    last_error = None
    for attempt in range(max(1, int(attempts))):
        try:
            download_file(url, target, timeout=timeout)
            return
        except urllib.error.HTTPError as exc:
            last_error = exc
            # Missing/forbidden artwork will not improve on an immediate retry.
            if 400 <= int(exc.code) < 500:
                break
        except Exception as exc:
            last_error = exc
        if attempt + 1 < attempts:
            time.sleep(0.20)
    if last_error is not None:
        raise last_error
    raise RuntimeError("download failed")


def normalize_steam_icon_png(source, target):
    """Write a real PNG icon regardless of the downloaded source type."""
    source = Path(source)
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    if source == target and target.suffix.lower() == ".png":
        return target
    temp = target.with_suffix(target.suffix + ".part.png")
    try:
        if source.suffix.lower() == ".png":
            shutil.copy2(source, temp)
        else:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(str(source))
            pixbuf.savev(str(temp), "png", [], [])
        temp.replace(target)
        return target
    finally:
        try:
            if temp.exists():
                temp.unlink()
        except OSError:
            pass


def apply_lutris_icon(source, lutris_icon_path):
    if not lutris_icon_path:
        return None
    try:
        source = Path(source)
        icon_target = Path(lutris_icon_path)
        icon_target.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix.lower() == ".png":
            shutil.copy2(source, icon_target)
        else:
            # Steam's official community icon is commonly JPEG. Lutris points
            # the shortcut at a .png path, so convert rather than merely giving
            # JPEG bytes a misleading .png extension.
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(str(source))
            temp = icon_target.with_suffix(icon_target.suffix + ".part.png")
            pixbuf.savev(str(temp), "png", [], [])
            temp.replace(icon_target)
        return None
    except Exception as exc:
        return f"Steam shortcut icon path: {exc}"

def load_artwork_metadata(cache_dir):
    path = cache_dir / "metadata.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_artwork_metadata(cache_dir, metadata):
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_dir / "metadata.json"
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def download_and_apply_all_artwork(game_name, grid_id, grid_dir, api_key, lutris_icon_path=None, search_hints=None):
    """Fetch/apply five artwork types using the user's provider preference.

    Artwork source modes:
      * both (default): prefer official Steam, then SteamGridDB as fallback
      * steam: official Valve-hosted artwork only
      * steamgriddb: SteamGridDB only

    All five slots run concurrently. In Both mode, official Steam is tried first
    for every slot and SteamGridDB is used only when Steam has no usable asset.
    Without an API key, Both naturally remains Steam-only.
    """
    cache_dir = SGDB_CACHE_ROOT / str(grid_id)
    cache_dir.mkdir(parents=True, exist_ok=True)
    grid_dir.mkdir(parents=True, exist_ok=True)

    metadata = load_artwork_metadata(cache_dir)
    normalized_name = normalize_game_name(game_name)
    source_mode = load_artwork_source()
    allow_steam = source_mode in {"both", "steam"}
    allow_sgdb = source_mode in {"both", "steamgriddb"}

    previous_assets = metadata.get("assets")
    if not isinstance(previous_assets, dict):
        previous_assets = {}

    cached_sgdb_id = None
    cached_steam_appid = None
    cached_steam_name = None
    if metadata.get("game_name_normalized") == normalized_name:
        try:
            cached_sgdb_id = int(metadata.get("sgdb_game_id"))
        except Exception:
            cached_sgdb_id = None
        try:
            cached_steam_appid = int(metadata.get("steam_appid"))
        except Exception:
            cached_steam_appid = None
        cached_steam_name = metadata.get("steam_game_name")

    # Resolve official Steam only when the selected artwork mode permits it.
    steam_info = None
    steam_resolve_error = None
    if allow_steam:
        try:
            steam_info = resolve_steam_official(
                game_name,
                cached_steam_appid,
                cached_steam_name,
                search_hints,
            )
        except Exception as exc:
            steam_resolve_error = str(exc)

    steam_appid = None
    steam_game_name = None
    if isinstance(steam_info, dict) and steam_info.get("appid"):
        steam_appid = int(steam_info["appid"])
        steam_game_name = str(steam_info.get("name") or game_name)

    # SteamGridDB is now truly fallback-only. Multiple artwork threads may need
    # it at once, so resolve the title exactly once behind this lock.
    sgdb_lock = threading.Lock()
    sgdb_state = {
        "resolved": False,
        "id": None,
        "name": game_name,
        "query": game_name,
        "error": None,
    }

    def ensure_sgdb_match():
        if sgdb_state["resolved"]:
            return sgdb_state
        with sgdb_lock:
            if sgdb_state["resolved"]:
                return sgdb_state
            if not allow_sgdb:
                sgdb_state["error"] = "SteamGridDB is disabled by the Artwork Source setting."
                sgdb_state["resolved"] = True
                return sgdb_state
            if not str(api_key or "").strip():
                sgdb_state["error"] = (
                    "No SteamGridDB API key is saved. Open Settings (gear icon) "
                    "to enable SteamGridDB artwork."
                )
                sgdb_state["resolved"] = True
                return sgdb_state
            try:
                override = get_sgdb_match_override(game_name)
                if override is not None:
                    match = dict(override)
                    sgdb_state["query"] = game_name
                elif cached_sgdb_id is not None:
                    match = {
                        "id": cached_sgdb_id,
                        "name": str(metadata.get("sgdb_game_name") or game_name),
                    }
                else:
                    match, matched_query = search_sgdb_game(game_name, api_key, search_hints)
                    sgdb_state["query"] = str(matched_query or game_name)
                if isinstance(match, dict) and match.get("id"):
                    sgdb_state["id"] = int(match["id"])
                    sgdb_state["name"] = str(match.get("name") or game_name)
                else:
                    sgdb_state["error"] = f'No SteamGridDB match was found for "{game_name}".'
            except Exception as exc:
                sgdb_state["error"] = str(exc)
            sgdb_state["resolved"] = True
        return sgdb_state

    specs = [
        {
            "key": "capsule",
            "label": "Capsule",
            "endpoint": "grids",
            "stem": f"{grid_id}p",
            "dimensions": ("600x900", "660x930", "342x482"),
            "mimes": "image/png,image/jpeg,image/webp",
        },
        {
            "key": "wide_capsule",
            "label": "Wide Capsule",
            "endpoint": "grids",
            "stem": str(grid_id),
            "dimensions": ("920x430", "460x215"),
            "mimes": "image/png,image/jpeg,image/webp",
        },
        {
            "key": "hero",
            "label": "Hero",
            "endpoint": "heroes",
            "stem": f"{grid_id}_hero",
            "dimensions": ("1920x620", "3840x1240", "1600x650"),
            "mimes": "image/png,image/jpeg,image/webp",
        },
        {
            "key": "logo",
            "label": "Logo",
            "endpoint": "logos",
            "stem": f"{grid_id}_logo",
            "dimensions": (),
            "mimes": "image/png,image/webp",
        },
        {
            "key": "icon",
            "label": "Icon",
            "endpoint": "icons",
            "stem": f"{grid_id}_icon",
            "dimensions": (),
            "mimes": "image/png,image/vnd.microsoft.icon",
        },
    ]

    try:
        cache_age = max(0, int(time.time()) - int(metadata.get("updated_at") or 0))
    except Exception:
        cache_age = SGDB_CACHE_FRESH_SECONDS + 1
    cache_is_fresh = cache_age <= SGDB_CACHE_FRESH_SECONDS
    saved_api_key = load_sgdb_api_key()

    def restore_cached(spec, provider_filter=None, allow_stale=False):
        if not allow_stale and not cache_is_fresh:
            return None
        old = previous_assets.get(spec["key"])
        if not isinstance(old, dict) or not old.get("id"):
            return None

        provider = str(old.get("provider") or "sgdb")
        if provider_filter and provider != provider_filter:
            return None
        # V7.4.52 selection fix: refresh only old SteamGridDB choices. Official
        # Steam artwork/cache is intentionally left completely unchanged.
        if provider == "sgdb":
            try:
                policy = int(metadata.get("sgdb_selection_policy_version") or 0)
            except Exception:
                policy = 0
            if policy != SGDB_SELECTION_POLICY_VERSION:
                return None
        # SGDB caches are tied to the user's API-backed provider state. Steam
        # official cache is independent of the SGDB key.
        if provider != "steam" and saved_api_key != api_key:
            return None

        old_cache_name = str(old.get("cache_file") or "")
        old_steam_name = str(old.get("steam_file") or "")
        old_cache = cache_dir / old_cache_name if old_cache_name else None
        old_target = grid_dir / old_steam_name if old_steam_name else None
        source = None
        if old_cache is not None and old_cache.is_file():
            source = old_cache
        elif old_target is not None and old_target.is_file():
            source = old_target
        if source is None or old_target is None:
            return None

        try:
            if source != old_target:
                shutil.copy2(source, old_target)
            icon_error = None
            if spec["key"] == "icon" and lutris_icon_path:
                icon_error = apply_lutris_icon(source, lutris_icon_path)
            if old_cache is not None and not old_cache.exists():
                shutil.copy2(old_target, old_cache)
            return {
                "key": spec["key"],
                "label": spec["label"],
                "api_ok": None,
                "selected": dict(old),
                "downloaded": False,
                "provider": provider,
                "fallback_rank": int(old.get("rank") or 1),
                "fresh_cache": not allow_stale,
                "icon_error": icon_error,
            }
        except Exception:
            return None

    def apply_source(spec, selected, source, cache_file, target, provider, downloaded, rank=1):
        try:
            # Steam's grid/_icon file alone is not enough for non-Steam
            # shortcuts. Normalize every icon to PNG so the shortcut can point
            # to a format Linux Steam renders reliably.
            if spec["key"] == "icon":
                png_cache = cache_dir / "icon.png"
                png_target = grid_dir / f'{spec["stem"]}.png'
                normalize_steam_icon_png(source, png_cache)
                source = png_cache
                cache_file = png_cache
                target = png_target

            remove_asset_siblings(cache_dir, spec["key"], keep=cache_file)
            remove_asset_siblings(grid_dir, spec["stem"], keep=target)
            if source != target:
                shutil.copy2(source, target)

            icon_error = None
            if spec["key"] == "icon" and lutris_icon_path:
                icon_error = apply_lutris_icon(source, lutris_icon_path)

            if source == target and not cache_file.exists():
                shutil.copy2(target, cache_file)

            selected_record = dict(selected)
            selected_record.update({
                "cache_file": cache_file.name,
                "steam_file": target.name,
                "provider": provider,
                "rank": int(rank or 1),
            })
            return {
                "key": spec["key"],
                "label": spec["label"],
                "api_ok": True if provider == "sgdb" else None,
                "selected": selected_record,
                "downloaded": bool(downloaded),
                "provider": provider,
                "fallback_rank": int(rank or 1),
                "icon_error": icon_error,
            }
        except Exception as exc:
            return {
                "key": spec["key"],
                "label": spec["label"],
                "api_ok": True if provider == "sgdb" else None,
                "failed": str(exc),
            }

    def process_spec(spec):
        errors = []
        api_ok = None
        steam_urls = []

        def try_steam():
            nonlocal steam_urls
            if not allow_steam:
                return None

            cached_official = restore_cached(spec, provider_filter="steam")
            if cached_official is not None:
                return cached_official

            steam_urls = official_steam_urls(steam_info, spec["key"])
            for steam_rank, image_url in enumerate(steam_urls[:4], start=1):
                ext = asset_extension(image_url)
                candidate_cache = cache_dir / f'{spec["key"]}{ext}'
                candidate_target = grid_dir / f'{spec["stem"]}{ext}'

                candidate_source = None
                old = previous_assets.get(spec["key"])
                if (
                    cache_is_fresh
                    and isinstance(old, dict)
                    and str(old.get("provider") or "") == "steam"
                    and str(old.get("url") or "") == image_url
                ):
                    old_file = old.get("cache_file")
                    if old_file:
                        old_cache = cache_dir / str(old_file)
                        if old_cache.is_file():
                            candidate_source = old_cache
                    if candidate_source is None and candidate_target.is_file():
                        candidate_source = candidate_target

                downloaded = False
                if candidate_source is None:
                    try:
                        download_file_with_retry(
                            image_url,
                            candidate_cache,
                            STEAM_IMAGE_TIMEOUT,
                            attempts=1,
                        )
                        candidate_source = candidate_cache
                        downloaded = True
                    except Exception as exc:
                        errors.append(f"Steam official #{steam_rank}: {exc}")
                        continue

                filename = Path(urllib.parse.urlparse(image_url).path).name
                return apply_source(
                    spec,
                    {
                        "id": f"steam:{steam_appid}:{filename}",
                        "url": image_url,
                        "score": 0,
                        "steam_appid": steam_appid,
                    },
                    candidate_source,
                    candidate_cache,
                    candidate_target,
                    "steam",
                    downloaded,
                    steam_rank,
                )

            # If Valve is temporarily unreachable, an older known-official copy
            # is still preferable to returning no artwork at all.
            return restore_cached(spec, provider_filter="steam", allow_stale=True)

        def try_sgdb():
            nonlocal api_ok
            if not allow_sgdb:
                return None

            cached_sgdb = restore_cached(spec, provider_filter="sgdb")
            if cached_sgdb is not None:
                return cached_sgdb

            sgdb = ensure_sgdb_match()
            sgdb_game_id = sgdb.get("id")
            if sgdb_game_id is None:
                if sgdb.get("error"):
                    errors.append(f"SteamGridDB: {sgdb['error']}")
                return None

            params = {
                "types": "static",
                "nsfw": "false",
                "humor": "false",
                "mimes": spec["mimes"],
            }
            if spec["dimensions"]:
                params["dimensions"] = ",".join(spec["dimensions"])

            try:
                items = sgdb_get(
                    f'/{spec["endpoint"]}/game/{sgdb_game_id}',
                    api_key,
                    params,
                )
                api_ok = True
                candidates = rank_assets(items, spec["dimensions"])
            except Exception as exc:
                candidates = []
                errors.append(f"SteamGridDB: {exc}")

            for candidate_rank, candidate in enumerate(candidates[:2], start=1):
                asset_id = str(candidate.get("id", ""))
                image_url = str(candidate.get("url", ""))
                if not asset_id or not image_url:
                    continue
                ext = asset_extension(image_url)
                candidate_cache = cache_dir / f'{spec["key"]}{ext}'
                candidate_target = grid_dir / f'{spec["stem"]}{ext}'

                old = previous_assets.get(spec["key"])
                candidate_source = None
                if (
                    cache_is_fresh
                    and isinstance(old, dict)
                    and str(old.get("provider") or "sgdb") == "sgdb"
                    and str(old.get("id", "")) == asset_id
                ):
                    old_file = old.get("cache_file")
                    if old_file:
                        old_cache = cache_dir / str(old_file)
                        if old_cache.is_file():
                            candidate_source = old_cache
                    if candidate_source is None and candidate_target.is_file():
                        candidate_source = candidate_target

                downloaded = False
                if candidate_source is None:
                    try:
                        download_file_with_retry(
                            image_url,
                            candidate_cache,
                            SGDB_IMAGE_TIMEOUT,
                            attempts=2 if candidate_rank == 1 else 1,
                        )
                        candidate_source = candidate_cache
                        downloaded = True
                    except Exception as exc:
                        errors.append(f"SGDB choice #{candidate_rank}: {exc}")
                        continue

                return apply_source(
                    spec,
                    {
                        "id": asset_id,
                        "url": image_url,
                        "score": int(candidate.get("score") or 0),
                        "language": str(candidate.get("language") or ""),
                        "sgdb_position": int(candidate_rank),
                    },
                    candidate_source,
                    candidate_cache,
                    candidate_target,
                    "sgdb",
                    downloaded,
                    candidate_rank,
                )
            return None

        # Both deliberately prefers official Steam first and uses SteamGridDB
        # only as a fallback for slots Steam cannot supply. The explicit
        # one-provider modes never touch the other provider.
        provider_order = (
            ("steam", "sgdb") if source_mode == "both"
            else (("steam",) if source_mode == "steam" else ("sgdb",))
        )
        for provider in provider_order:
            result = try_sgdb() if provider == "sgdb" else try_steam()
            if result is not None:
                return result

        if not errors and not steam_urls:
            return {
                "key": spec["key"],
                "label": spec["label"],
                "api_ok": api_ok,
                "missing": True,
            }

        detail = "; ".join(errors[-5:]) or "no compatible artwork found"
        return {
            "key": spec["key"],
            "label": spec["label"],
            "api_ok": api_ok,
            "failed": detail,
        }

    outcomes = {}
    with ThreadPoolExecutor(max_workers=len(specs)) as executor:
        future_map = {executor.submit(process_spec, spec): spec for spec in specs}
        for future in as_completed(future_map):
            spec = future_map[future]
            try:
                outcomes[spec["key"]] = future.result()
            except Exception as exc:
                outcomes[spec["key"]] = {
                    "key": spec["key"],
                    "label": spec["label"],
                    "api_ok": False,
                    "failed": str(exc),
                }

    if any(x.get("api_ok") is True for x in outcomes.values()):
        save_sgdb_api_key(api_key)

    new_assets = dict(previous_assets)
    downloaded = 0
    reused = 0
    applied = 0
    missing = []
    failed = []
    fallbacks = []
    provider_counts = {"sgdb": 0, "steam": 0}

    for spec in specs:
        outcome = outcomes.get(spec["key"], {})
        if outcome.get("missing"):
            missing.append(spec["label"])
            continue
        if outcome.get("failed"):
            failed.append(f'{spec["label"]}: {outcome["failed"]}')
            continue
        selected = outcome.get("selected")
        if not isinstance(selected, dict):
            failed.append(f'{spec["label"]}: no usable result')
            continue

        applied += 1
        if outcome.get("downloaded"):
            downloaded += 1
        else:
            reused += 1

        provider = str(outcome.get("provider") or selected.get("provider") or "sgdb")
        if provider in provider_counts:
            provider_counts[provider] += 1

        rank = int(outcome.get("fallback_rank") or 1)
        if provider == "sgdb":
            if rank > 1:
                fallbacks.append(f'{spec["label"]} fell back to SteamGridDB choice #{rank}')
            else:
                fallbacks.append(f'{spec["label"]} fell back to SteamGridDB')
        if outcome.get("icon_error"):
            failed.append(str(outcome["icon_error"]))

        new_assets[spec["key"]] = selected

    sgdb_game_id = sgdb_state.get("id") if sgdb_state.get("resolved") else cached_sgdb_id
    matched_name = sgdb_state.get("name") if sgdb_state.get("resolved") else str(metadata.get("sgdb_game_name") or game_name)

    # Remember any non-empty key after a successful artwork run, even when
    # official Steam supplied every slot and SteamGridDB did not need to be
    # contacted. Automatic post-install artwork can then use it later.
    if applied > 0 and str(api_key or "").strip():
        save_sgdb_api_key(str(api_key).strip())

    metadata = {
        "version": 6,
        "game_name": game_name,
        "game_name_normalized": normalized_name,
        "sgdb_game_id": sgdb_game_id,
        "sgdb_game_name": matched_name,
        "sgdb_search_query": sgdb_state.get("query") if sgdb_state.get("resolved") else metadata.get("sgdb_search_query"),
        "steam_appid": steam_appid,
        "steam_game_name": steam_game_name,
        "steam_grid_id": str(grid_id),
        "artwork_source": source_mode,
        "sgdb_selection_policy_version": SGDB_SELECTION_POLICY_VERSION,
        "assets": new_assets,
        "updated_at": int(time.time()),
    }
    save_artwork_metadata(cache_dir, metadata)

    if applied == 0:
        detail = "; ".join(failed) if failed else "No compatible static artwork was found."
        if steam_resolve_error:
            detail += f" Steam lookup: {steam_resolve_error}"
        raise RuntimeError(detail)

    return {
        "matched_name": matched_name,
        "sgdb_search_query": sgdb_state.get("query") if sgdb_state.get("resolved") else metadata.get("sgdb_search_query"),
        "steam_appid": steam_appid,
        "steam_game_name": steam_game_name,
        "applied": applied,
        "downloaded": downloaded,
        "reused": reused,
        "missing": missing,
        "failed": failed,
        "fallbacks": fallbacks,
        "provider_counts": provider_counts,
        "icon_path": (
            str(grid_dir / str(new_assets.get("icon", {}).get("steam_file")))
            if isinstance(new_assets.get("icon"), dict) and new_assets.get("icon", {}).get("steam_file")
            else ""
        ),
    }


def database_path():
    candidates = [
        Path.home() / ".var/app/net.lutris.Lutris/data/lutris/pga.db",
        Path.home() / ".local/share/lutris/pga.db",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def list_lutris_games():
    db = database_path()
    if not db:
        return []

    conn = sqlite3.connect(db)
    try:
        return conn.execute(
            """
            SELECT id, name, directory, runner
            FROM games
            WHERE installed = 1
              AND runner != 'steam'
              AND configpath IS NOT NULL
              AND configpath != ''
            ORDER BY name COLLATE NOCASE
            """
        ).fetchall()
    finally:
        conn.close()


def safe_game_directory(path_text, expected_steam_appid=None):
    if not path_text:
        raise RuntimeError("Lutris did not provide a game folder for this game.")

    raw = Path(os.path.expanduser(path_text))

    if not raw.is_absolute():
        raise RuntimeError(f"The game folder is not an absolute path:\n\n{raw}")

    # Steam-native OneClick prefixes are intentionally sometimes reached through
    # a symlink (for example Steam's numeric compatdata link, or an older OneClick
    # registry path). Refusing every symlink made Complete Game Removal unusable.
    # Follow it ONLY when the target proves ownership with OneClick's prefix marker
    # and the marker AppID matches the selected game. Arbitrary symlinks remain blocked.
    if raw.is_symlink():
        if expected_steam_appid is None:
            raise RuntimeError(
                "For safety, symbolic-link game folders are only deleted when they "
                "can be verified as a Moses OneClick Steam prefix."
            )
        target = raw.resolve(strict=False)
        try:
            marker_data = json.loads((target / ONECLICK_PREFIX_MARKER).read_text(encoding="utf-8"))
            marker_owner = str(marker_data.get("owner") or "")
            marker_appid = int(marker_data.get("appid"))
        except Exception:
            marker_owner = ""
            marker_appid = None
        if marker_owner != "oneclick-exe" or marker_appid != int(expected_steam_appid):
            raise RuntimeError(
                "The symbolic-link target could not be verified as this game's "
                "Moses OneClick Steam prefix, so it was not deleted.\n\n"
                f"Link:\n{raw}\n\nTarget:\n{target}"
            )
        raw = target

    path = raw.resolve(strict=False)
    home = Path.home().resolve()

    protected = {
        Path("/"),
        Path("/home"),
        Path("/var"),
        Path("/usr"),
        Path("/opt"),
        Path("/tmp"),
        home,
        home / "Games",
        home / "Desktop",
        home / "Downloads",
        home / "Documents",
    }

    if path in protected or len(path.parts) < 4:
        raise RuntimeError(
            "Refusing to permanently delete this protected folder:\n\n"
            f"{path}"
        )

    # External OneClick installs are allowed outside HOME only when the folder
    # carries a marker written by OneClick itself. Never turn this into a broad
    # /run/media deletion permission.
    try:
        path.relative_to(home)
    except ValueError:
        marker_ok = False
        markers = [
            path / ONECLICK_EXTERNAL_MARKER,
            path / ONECLICK_PREFIX_MARKER,
            path.parent / f".{path.name}{ONECLICK_EXTERNAL_MARKER}",
        ]
        for marker in markers:
            if not marker.is_file():
                continue
            try:
                data = json.loads(marker.read_text(encoding="utf-8"))
                marked_path = str(data.get("path") or "").strip()
                if data.get("owner") == "oneclick-exe" and (not marked_path or Path(marked_path).resolve(strict=False) == path):
                    marker_ok = True
                    break
            except Exception:
                pass
        if not marker_ok:
            raise RuntimeError(
                "For safety, folders outside your home directory can only be permanently deleted "
                "when they are marked as an external OneClick game."
            )

    return path


def message(parent, title, text, kind=Gtk.MessageType.INFO):
    dlg = Gtk.MessageDialog(
        transient_for=parent,
        modal=True,
        destroy_with_parent=True,
        message_type=kind,
        buttons=Gtk.ButtonsType.OK,
        text=tr(title),
    )
    dlg.format_secondary_text(tr(text))
    dlg.run()
    dlg.destroy()


def confirm(parent, title, text, destructive=False):
    dlg = Gtk.MessageDialog(
        transient_for=parent,
        modal=True,
        destroy_with_parent=True,
        message_type=Gtk.MessageType.WARNING if destructive else Gtk.MessageType.QUESTION,
        buttons=Gtk.ButtonsType.NONE,
        text=tr(title),
    )
    dlg.format_secondary_text(tr(text))
    dlg.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
    yes = dlg.add_button(
        tr("Delete permanently") if destructive else tr("Continue"),
        Gtk.ResponseType.OK,
    )

    if destructive:
        yes.get_style_context().add_class("destructive-action")
    else:
        yes.get_style_context().add_class("suggested-action")

    response = dlg.run()
    dlg.destroy()
    return response == Gtk.ResponseType.OK


def make_thermometer_button_icon():
    """Return a normal 16px Gtk.Image thermometer glyph for utility buttons.

    Gtk.Image participates in the same centering/layout rules as the other
    symbolic button icons. This avoids the baseline/allocation oddity of the
    old custom Gtk.DrawingArea, which could make the thermometer sit too high.
    """
    svg = b"""<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
      <g fill="none" stroke="#2f6fbd" stroke-width="1.45" stroke-linecap="round" stroke-linejoin="round">
        <path d="M6.25 9.55V3.75a1.75 1.75 0 0 1 3.5 0v5.8a3.25 3.25 0 1 1-3.5 0Z"/>
        <path d="M8 5.1v6.1"/>
      </g>
      <circle cx="8" cy="11.75" r="1.45" fill="#2f6fbd"/>
    </svg>"""
    try:
        loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
        loader.set_size(16, 16)
        loader.write(svg)
        loader.close()
        image = Gtk.Image.new_from_pixbuf(loader.get_pixbuf())
    except Exception:
        # Theme fallback; normally the embedded SVG above is used.
        image = Gtk.Image.new_from_icon_name("temperature-symbolic", Gtk.IconSize.BUTTON)
    image.set_valign(Gtk.Align.CENTER)
    image.set_halign(Gtk.Align.CENTER)
    return image



class OneClickTools(Gtk.Window):
    def __init__(self):
        super().__init__(title="Moses OneClick Tool")

        # IMPORTANT:
        # Do NOT use Gtk.HeaderBar / client-side decorations here.
        # SteamOS KDE/X11 can produce ugly drag ghosting with GTK3 CSD.
        # Let KWin draw the normal native title bar instead.
        self.set_default_size(540, 685)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_icon_name("applications-games")
        self.set_decorated(True)
        self.set_type_hint(Gdk.WindowTypeHint.NORMAL)

        settings = Gtk.Settings.get_default()
        if settings:
            try:
                settings.set_property("gtk-application-prefer-dark-theme", False)
                settings.set_property("gtk-theme-name", "Adwaita")
            except Exception:
                pass

        self.install_css()

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.get_style_context().add_class("window-root")
        self.add(root)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        body.set_border_width(26)
        root.pack_start(body, True, True, 0)

        # Header area. Keep Settings out of the main workflow: one small gear
        # in the top-right opens persistent application settings.
        header_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        header_row.set_margin_bottom(4)
        body.pack_start(header_row, False, False, 0)

        title = Gtk.Label()
        title.set_markup(
            "<span size='x-large' weight='bold'>Manage your games</span>"
        )
        title.set_xalign(0)
        title.set_hexpand(True)
        header_row.pack_start(title, True, True, 0)

        self.settings_btn = Gtk.Button()
        self.settings_btn.set_tooltip_text(tr("Settings"))
        self.settings_btn.set_size_request(40, 38)
        settings_icon = Gtk.Image.new_from_icon_name(
            "preferences-system-symbolic", Gtk.IconSize.BUTTON
        )
        self.settings_btn.add(settings_icon)
        self.settings_btn.get_style_context().add_class("icon-button")
        self.settings_btn.connect("clicked", self.on_settings)
        header_row.pack_end(self.settings_btn, False, False, 0)

        subtitle = Gtk.Label(
            label="Install through Steam or Lutris, manage dependencies and Steam shortcuts, fetch artwork, or remove games."
        )
        subtitle.set_xalign(0)
        subtitle.set_line_wrap(True)
        subtitle.set_margin_bottom(24)
        subtitle.get_style_context().add_class("subtitle")
        body.pack_start(subtitle, False, False, 0)

        # Game selector label — deliberately OUTSIDE the bordered selector.
        selector_label = Gtk.Label(label=tr("SELECT GAME"))
        selector_label.set_xalign(0)
        selector_label.set_margin_bottom(7)
        selector_label.get_style_context().add_class("section-label")
        body.pack_start(selector_label, False, False, 0)

        selector_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        selector_row.set_margin_bottom(22)
        body.pack_start(selector_row, False, False, 0)

        # One selector, now with multi-select support. No extra main action
        # buttons are needed: check one or more games here and the existing
        # artwork button applies to every checked game.
        self.selector_button = Gtk.MenuButton()
        self.selector_button.set_hexpand(True)
        self.selector_button.set_size_request(-1, 42)
        self.selector_button.get_style_context().add_class("game-selector")

        selector_content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.selector_summary = Gtk.Label(label=tr("Select one or more games"))
        self.selector_summary.set_xalign(0)
        self.selector_summary.set_hexpand(True)
        selector_arrow = Gtk.Image.new_from_icon_name(
            "pan-down-symbolic", Gtk.IconSize.BUTTON
        )
        selector_content.pack_start(self.selector_summary, True, True, 0)
        selector_content.pack_end(selector_arrow, False, False, 0)
        self.selector_button.add(selector_content)
        selector_row.pack_start(self.selector_button, True, True, 0)

        self.selector_popover = Gtk.Popover.new(self.selector_button)
        self.selector_popover.set_position(Gtk.PositionType.BOTTOM)
        popover_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        popover_box.set_border_width(10)

        popover_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        popover_title = Gtk.Label(label=tr("Select games"))
        popover_title.set_xalign(0)
        popover_title.set_hexpand(True)
        popover_title.get_style_context().add_class("section-label")
        popover_header.pack_start(popover_title, True, True, 0)

        select_all = Gtk.Button(label=tr("All"))
        select_all.set_tooltip_text("Select all installed games")
        select_all.get_style_context().add_class("mini-button")
        select_all.connect("clicked", self.on_select_all_games)
        popover_header.pack_start(select_all, False, False, 0)

        clear_all = Gtk.Button(label=tr("Clear"))
        clear_all.set_tooltip_text("Clear game selection")
        clear_all.get_style_context().add_class("mini-button")
        clear_all.connect("clicked", self.on_clear_game_selection)
        popover_header.pack_start(clear_all, False, False, 0)
        popover_box.pack_start(popover_header, False, False, 0)

        game_scroll = Gtk.ScrolledWindow()
        game_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        game_scroll.set_size_request(420, 230)
        game_scroll.set_shadow_type(Gtk.ShadowType.IN)
        self.game_list = Gtk.ListBox()
        self.game_list.set_selection_mode(Gtk.SelectionMode.NONE)
        game_scroll.add(self.game_list)
        popover_box.pack_start(game_scroll, True, True, 0)

        # Explicit confirmation makes multi-selection feel finished instead of
        # leaving the popover open after the user has checked the games.
        popover_footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        popover_footer.set_halign(Gtk.Align.CENTER)
        popover_footer.set_margin_top(2)
        selector_ok = Gtk.Button(label="OK")
        selector_ok.set_size_request(96, 34)
        selector_ok.get_style_context().add_class("primary")
        selector_ok.connect("clicked", lambda *_: self.selector_popover.popdown())
        popover_footer.pack_start(selector_ok, False, False, 0)
        popover_box.pack_start(popover_footer, False, False, 0)

        self.selector_popover.add(popover_box)
        self.selector_button.set_popover(self.selector_popover)
        # Gtk.Popover is attached outside the normal window widget tree.
        # Mark its child hierarchy visible explicitly; otherwise GTK can show
        # only the tiny popover arrow/shell with no game list inside it.
        popover_box.show_all()

        self.reselect_exe_btn = Gtk.Button()
        self.reselect_exe_btn.set_tooltip_text("Edit selected game name / main EXE")
        self.reselect_exe_btn.set_size_request(44, 42)
        reselect_image = Gtk.Image.new_from_icon_name(
            "document-edit-symbolic", Gtk.IconSize.BUTTON
        )
        self.reselect_exe_btn.add(reselect_image)
        self.reselect_exe_btn.connect("clicked", self.on_reselect_exe)
        self.reselect_exe_btn.get_style_context().add_class("icon-button")
        selector_row.pack_start(self.reselect_exe_btn, False, False, 0)

        self.refresh_btn = Gtk.Button()
        refresh = self.refresh_btn
        refresh.set_tooltip_text("Refresh game list")
        refresh.set_size_request(44, 42)
        refresh_image = Gtk.Image.new_from_icon_name(
            "view-refresh-symbolic", Gtk.IconSize.BUTTON
        )
        refresh.add(refresh_image)
        refresh.connect("clicked", lambda *_: self.refresh_games())
        refresh.get_style_context().add_class("icon-button")
        selector_row.pack_start(refresh, False, False, 0)

        # Actions
        actions_label = Gtk.Label(label=tr("ACTIONS"))
        actions_label.set_xalign(0)
        actions_label.set_margin_bottom(7)
        actions_label.get_style_context().add_class("section-label")
        body.pack_start(actions_label, False, False, 0)

        actions_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        actions_panel.get_style_context().add_class("actions-panel")
        body.pack_start(actions_panel, False, False, 0)

        self.install_btn = Gtk.Button()
        self.install_btn.set_hexpand(True)
        self.install_btn.set_size_request(-1, 46)
        self.install_btn.get_style_context().add_class("primary")
        self.install_btn.connect("clicked", self.on_install)

        install_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        install_box.set_halign(Gtk.Align.CENTER)
        install_icon = Gtk.Image.new_from_icon_name(
            "list-add-symbolic", Gtk.IconSize.BUTTON
        )
        install_text = Gtk.Label(label=tr("Install Game"))
        install_text.get_style_context().add_class("button-label")
        install_box.pack_start(install_icon, False, False, 0)
        install_box.pack_start(install_text, False, False, 0)
        self.install_btn.add(install_box)
        actions_panel.pack_start(self.install_btn, False, False, 0)

        self.play_btn = Gtk.Button()
        self.play_btn.set_hexpand(True)
        self.play_btn.set_size_request(-1, 46)
        self.play_btn.get_style_context().add_class("play")
        self.play_btn.set_tooltip_text("Launch the selected game using its Steam or Lutris backend")
        self.play_btn.connect("clicked", self.on_play)

        play_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        play_box.set_halign(Gtk.Align.CENTER)
        play_icon = Gtk.Image.new_from_icon_name(
            "media-playback-start-symbolic", Gtk.IconSize.BUTTON
        )
        play_text = Gtk.Label(label=tr("Play Game"))
        play_text.get_style_context().add_class("button-label")
        play_box.pack_start(play_icon, False, False, 0)
        play_box.pack_start(play_text, False, False, 0)
        self.play_btn.add(play_box)
        actions_panel.pack_start(self.play_btn, False, False, 0)

        self.repair_btn = Gtk.Button()
        self.repair_btn.set_hexpand(True)
        self.repair_btn.set_size_request(-1, 46)
        self.repair_btn.get_style_context().add_class("secondary")
        self.repair_btn.connect("clicked", self.on_repair)

        repair_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        repair_box.set_halign(Gtk.Align.CENTER)
        repair_icon = Gtk.Image.new_from_icon_name(
            "emblem-synchronizing-symbolic", Gtk.IconSize.BUTTON
        )
        repair_text = Gtk.Label(label=tr("Repair Steam Shortcut"))
        repair_text.get_style_context().add_class("button-label")
        repair_box.pack_start(repair_icon, False, False, 0)
        repair_box.pack_start(repair_text, False, False, 0)
        self.repair_btn.add(repair_box)
        actions_panel.pack_start(self.repair_btn, False, False, 0)

        self.dependencies_btn = Gtk.Button()
        self.dependencies_btn.set_hexpand(True)
        self.dependencies_btn.set_size_request(-1, 46)
        self.dependencies_btn.get_style_context().add_class("secondary")
        self.dependencies_btn.set_tooltip_text("Manage the shared dependency library anytime; with one game selected you can also install dependencies into that game's prefix")
        self.dependencies_btn.connect("clicked", self.on_dependencies)

        dependencies_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        dependencies_box.set_halign(Gtk.Align.CENTER)
        dependencies_icon = Gtk.Image.new_from_icon_name(
            "applications-system-symbolic", Gtk.IconSize.BUTTON
        )
        dependencies_text = Gtk.Label(label=tr("Install / Repair Dependencies"))
        dependencies_text.get_style_context().add_class("button-label")
        dependencies_box.pack_start(dependencies_icon, False, False, 0)
        dependencies_box.pack_start(dependencies_text, False, False, 0)
        self.dependencies_btn.add(dependencies_box)
        actions_panel.pack_start(self.dependencies_btn, False, False, 0)

        self.artwork_btn = Gtk.Button()
        self.artwork_btn.set_hexpand(True)
        self.artwork_btn.set_size_request(-1, 46)
        self.artwork_btn.get_style_context().add_class("secondary")
        self.artwork_btn.connect("clicked", self.on_artwork)

        artwork_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        artwork_box.set_halign(Gtk.Align.CENTER)
        artwork_icon = Gtk.Image.new_from_icon_name(
            "folder-download-symbolic", Gtk.IconSize.BUTTON
        )
        artwork_text = Gtk.Label(label=tr("Download + Apply All Artworks"))
        artwork_text.get_style_context().add_class("button-label")
        artwork_box.pack_start(artwork_icon, False, False, 0)
        artwork_box.pack_start(artwork_text, False, False, 0)
        self.artwork_btn.add(artwork_box)

        # Keep the main artwork action uncluttered, but provide one compact
        # folder button beside it for users who want to inspect/remove the
        # custom artwork files Steam is actually using.
        artwork_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        artwork_row.pack_start(self.artwork_btn, True, True, 0)

        self.artwork_folder_btn = Gtk.Button()
        self.artwork_folder_btn.set_size_request(48, 46)
        self.artwork_folder_btn.get_style_context().add_class("icon-button")
        self.artwork_folder_btn.set_tooltip_text("Open Steam artwork folder")
        self.artwork_folder_btn.connect("clicked", self.on_open_artwork_folder)
        folder_icon = Gtk.Image.new_from_icon_name(
            "folder-open-symbolic", Gtk.IconSize.BUTTON
        )
        self.artwork_folder_btn.add(folder_icon)
        artwork_row.pack_start(self.artwork_folder_btn, False, False, 0)
        actions_panel.pack_start(artwork_row, False, False, 0)

        self.remove_btn = Gtk.Button()
        self.remove_btn.set_hexpand(True)
        self.remove_btn.set_size_request(-1, 46)
        self.remove_btn.get_style_context().add_class("danger")
        self.remove_btn.connect("clicked", self.on_remove)

        remove_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        remove_box.set_halign(Gtk.Align.CENTER)
        remove_icon = Gtk.Image.new_from_icon_name(
            "user-trash-symbolic", Gtk.IconSize.BUTTON
        )
        remove_text = Gtk.Label(label=tr("Complete Game Removal"))
        remove_text.get_style_context().add_class("button-label")
        remove_box.pack_start(remove_icon, False, False, 0)
        remove_box.pack_start(remove_text, False, False, 0)
        self.remove_btn.add(remove_box)
        actions_panel.pack_start(self.remove_btn, False, False, 0)

        # Integrated utilities. Keep them equal-width and directly below game
        # removal, as separate tools rather than game-selection actions.
        utility_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        self.stream_extract_btn = Gtk.Button()
        self.stream_extract_btn.set_hexpand(True)
        self.stream_extract_btn.set_size_request(-1, 46)
        self.stream_extract_btn.get_style_context().add_class("secondary")
        self.stream_extract_btn.set_tooltip_text("Open the integrated StreamExtract downloader/extractor")
        self.stream_extract_btn.connect("clicked", self.on_stream_extract)

        stream_extract_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        stream_extract_box.set_halign(Gtk.Align.CENTER)
        stream_extract_icon = Gtk.Image.new_from_icon_name(
            "folder-download-symbolic", Gtk.IconSize.BUTTON
        )
        stream_extract_text = Gtk.Label(label="StreamExtract")
        stream_extract_text.get_style_context().add_class("button-label")
        stream_extract_box.pack_start(stream_extract_icon, False, False, 0)
        stream_extract_box.pack_start(stream_extract_text, False, False, 0)
        self.stream_extract_btn.add(stream_extract_box)
        utility_row.pack_start(self.stream_extract_btn, True, True, 0)

        self.temp_overlay_btn = Gtk.Button()
        self.temp_overlay_btn.set_hexpand(True)
        self.temp_overlay_btn.set_size_request(-1, 46)
        self.temp_overlay_btn.get_style_context().add_class("secondary")
        self.temp_overlay_btn.set_tooltip_text("Open the temperature overlay")
        self.temp_overlay_btn.connect("clicked", self.on_temp_overlay)

        temp_overlay_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        temp_overlay_box.set_halign(Gtk.Align.CENTER)
        # Use the same Gtk.Image layout as every other button icon. The small
        # embedded thermometer is intentionally generic and is not based on a
        # user-supplied picture.
        temp_overlay_icon = make_thermometer_button_icon()
        temp_overlay_text = Gtk.Label(label="TempOverlay")
        temp_overlay_text.get_style_context().add_class("button-label")
        temp_overlay_box.pack_start(temp_overlay_icon, False, False, 0)
        temp_overlay_box.pack_start(temp_overlay_text, False, False, 0)
        self.temp_overlay_btn.add(temp_overlay_box)
        utility_row.pack_start(self.temp_overlay_btn, True, True, 0)
        actions_panel.pack_start(utility_row, False, False, 0)

        self.status = Gtk.Label(label="")
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        # Gtk.Label can otherwise request its entire long status sentence as
        # one natural-width line, which makes a non-resizable GTK window grow
        # across the screen. Cap the natural width so the text wraps instead.
        self.status.set_max_width_chars(66)
        self.status.set_margin_top(16)
        self.status.get_style_context().add_class("status")
        body.pack_start(self.status, False, False, 0)

        footer_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        footer_row.set_margin_top(9)
        self.restart_steam_btn = Gtk.Button(label=tr("Restart Steam"))
        self.restart_steam_btn.set_size_request(118, 32)
        self.restart_steam_btn.get_style_context().add_class("mini-button")
        self.restart_steam_btn.set_tooltip_text("Close Steam cleanly and start it again automatically")
        self.restart_steam_btn.connect("clicked", self.on_restart_steam)
        footer_row.pack_start(self.restart_steam_btn, False, False, 0)

        # Keep the installed Moses version visible in the main menu so it is
        # immediately obvious which build is actually running.
        self.main_version_label = Gtk.Label(label=f"Version {TOOL_VERSION}")
        self.main_version_label.set_xalign(1)
        self.main_version_label.set_hexpand(True)
        self.main_version_label.get_style_context().add_class("footer-version")
        footer_row.pack_end(self.main_version_label, True, True, 0)
        body.pack_end(footer_row, False, False, 0)

        self.games = {}
        self.selected_ids = set()
        self.game_checks = {}
        # V7.2.5: game-name clicks are exclusive single-select, while the
        # checkbox remains the explicit multi-select control. This guard keeps
        # programmatic checkbox synchronization from re-entering toggle logic.
        self._selector_syncing = False
        self.artwork_busy = False
        self.refresh_games()

    def install_css(self):
        css = b"""
        window, .window-root {
            background-color: #f6f7f9;
            color: #202124;
        }

        .subtitle {
            color: #70757a;
            font-size: 10.5pt;
        }

        .api-hint {
            color: #7b8085;
            font-size: 9pt;
        }

        .footer-version {
            color: #8a8f94;
            font-size: 8.5pt;
        }

        entry {
            min-height: 38px;
            padding-left: 10px;
            padding-right: 10px;
            background-color: #ffffff;
            color: #202124;
            border: 1px solid #cfd3d8;
            border-radius: 7px;
        }

        entry:focus {
            border-color: #2f80ed;
        }

        .section-label {
            color: #6b7075;
            font-size: 8.5pt;
            font-weight: 700;
            letter-spacing: 0.7px;
        }

        combobox button {
            min-height: 40px;
            padding-left: 12px;
            padding-right: 12px;
            background-image: none;
            background-color: #ffffff;
            color: #202124;
            border: 1px solid #cfd3d8;
            border-radius: 7px;
            box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
        }

        combobox button:hover {
            border-color: #aeb4ba;
            background-color: #ffffff;
        }

        button.game-selector {
            min-height: 40px;
            padding-left: 12px;
            padding-right: 12px;
            background-image: none;
            background-color: #ffffff;
            color: #202124;
            border: 1px solid #cfd3d8;
            border-radius: 7px;
            box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
        }

        button.game-selector:hover {
            border-color: #aeb4ba;
            background-color: #ffffff;
        }

        button.mini-button {
            min-height: 26px;
            padding: 2px 9px;
            background-image: none;
            background-color: #ffffff;
            color: #2f6fbd;
            border: 1px solid #cfd3d8;
            border-radius: 5px;
            box-shadow: none;
        }

        button.mini-button:hover {
            background-color: #f3f8fd;
        }

        button.icon-button {
            min-width: 42px;
            min-height: 40px;
            padding: 0;
            background-image: none;
            background-color: #ffffff;
            color: #4b5156;
            border: 1px solid #cfd3d8;
            border-radius: 7px;
        }

        button.icon-button:hover {
            background-color: #f0f2f4;
        }

        .actions-panel {
            background-color: transparent;
        }

        button.primary {
            min-height: 44px;
            background-image: none;
            background-color: #2f80ed;
            color: #ffffff;
            border: 1px solid #2f80ed;
            border-radius: 7px;
            box-shadow: none;
            text-shadow: none;
            -gtk-icon-shadow: none;
        }

        button.primary label,
        button.primary image {
            color: #ffffff;
            text-shadow: none;
            -gtk-icon-shadow: none;
            box-shadow: none;
        }

        button.primary:hover {
            background-color: #1f6fd5;
            border-color: #1f6fd5;
            text-shadow: none;
            -gtk-icon-shadow: none;
        }

        button.primary:active {
            background-color: #195fb8;
            text-shadow: none;
            -gtk-icon-shadow: none;
        }

        button.play {
            min-height: 44px;
            background-image: none;
            background-color: #2e7d32;
            color: #ffffff;
            border: 1px solid #2e7d32;
            border-radius: 7px;
            box-shadow: none;
            text-shadow: none;
            -gtk-icon-shadow: none;
        }

        button.play label,
        button.play image {
            color: #ffffff;
            text-shadow: none;
            -gtk-icon-shadow: none;
            box-shadow: none;
        }

        button.play:hover {
            background-color: #256b2a;
            border-color: #256b2a;
        }

        button.play:active {
            background-color: #1f5d24;
        }

        button.secondary {
            min-height: 44px;
            background-image: none;
            background-color: #ffffff;
            color: #2f6fbd;
            border: 1px solid #b9cbe0;
            border-radius: 7px;
            box-shadow: none;
            text-shadow: none;
            -gtk-icon-shadow: none;
        }

        button.secondary label,
        button.secondary image {
            color: #2f6fbd;
            text-shadow: none;
            -gtk-icon-shadow: none;
            box-shadow: none;
        }

        button.secondary:hover {
            background-color: #f3f8fd;
            border-color: #8fb2da;
        }

        button.secondary:active {
            background-color: #e6f0fa;
        }

        button.danger {
            min-height: 44px;
            background-image: none;
            background-color: #ffffff;
            color: #c62828;
            border: 1px solid #e1b4b4;
            border-radius: 7px;
            box-shadow: none;
        }

        button.danger:hover {
            background-color: #fff4f4;
            border-color: #d98c8c;
        }

        button.danger:active {
            background-color: #fde8e8;
        }

        .button-label {
            font-weight: 600;
            text-shadow: none;
            -gtk-icon-shadow: none;
        }

        .status {
            color: #6b7075;
            font-size: 9.5pt;
        }

        .success {
            color: #2e7d32;
        }
        """

        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        screen = Gdk.Screen.get_default()
        if screen:
            Gtk.StyleContext.add_provider_for_screen(
                screen,
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

    def selected_games(self):
        return sorted(
            (self.games[sid] for sid in self.selected_ids if sid in self.games),
            key=lambda item: item["name"].casefold(),
        )

    def selected_game(self):
        items = self.selected_games()
        return items[0] if len(items) == 1 else None

    def set_status(self, text, success=False):
        text = tr(text)
        self.status.set_text(text)
        ctx = self.status.get_style_context()
        if success:
            ctx.add_class("success")
        else:
            ctx.remove_class("success")

    def _update_selector_summary(self):
        count = len(self.selected_ids)
        if count == 0:
            text = "Select one or more games"
        elif count == 1:
            sid = next(iter(self.selected_ids))
            text = self.games.get(sid, {}).get("name", "1 game selected")
        else:
            text = f"{count} games selected"
        self.selector_summary.set_text(text)

    def _update_action_sensitivity(self):
        count = len(self.selected_ids)
        available = bool(self.games) and not self.artwork_busy
        self.selector_button.set_sensitive(available)
        reselect_available = False
        if available and count == 1:
            selected = self.selected_game()
            reselect_available = bool(
                selected
                and selected.get("backend") == "steam"
                and (
                    selected.get("exe_reselect_available")
                    or not selected.get("exe_reselect_known", False)
                )
            )
        self.reselect_exe_btn.set_sensitive(reselect_available)
        self.refresh_btn.set_sensitive(not self.artwork_busy)
        # Repair stays single-game, while artwork and complete removal support
        # every checked game (including the selector's All option).
        self.repair_btn.set_sensitive(available and count >= 1)
        self.dependencies_btn.set_sensitive(True)
        # Play is intentionally single-game only. Steam-native entries that
        # have been detached from Steam cannot be launched until repaired.
        playable = False
        if available and count == 1:
            item = self.selected_game()
            playable = bool(item) and not (
                item.get("backend") == "steam" and item.get("status") == "detached"
            )
        self.play_btn.set_sensitive(playable)
        self.remove_btn.set_sensitive(available and count >= 1)
        self.artwork_btn.set_sensitive(available and count >= 1)
        self.artwork_folder_btn.set_sensitive(not self.artwork_busy)
        self.stream_extract_btn.set_sensitive(True)
        self.temp_overlay_btn.set_sensitive(True)

    def _apply_game_selection(self, selected_ids):
        """Synchronize selector state without turning name-clicks into multi-select."""
        wanted = {str(sid) for sid in selected_ids if str(sid) in self.games}
        self.selected_ids = wanted
        self._selector_syncing = True
        try:
            for sid, check in self.game_checks.items():
                active = sid in wanted
                if check.get_active() != active:
                    check.set_active(active)
        finally:
            self._selector_syncing = False
        self._update_selector_summary()
        self._update_action_sensitivity()

    def _rebuild_game_checks(self):
        for child in self.game_list.get_children():
            self.game_list.remove(child)
        self.game_checks.clear()

        for sid, item in sorted(
            self.games.items(), key=lambda pair: pair[1]["name"].casefold()
        ):
            row = Gtk.ListBoxRow()
            row.set_activatable(False)
            row.set_selectable(False)

            # V7.2.5 keeps V7.0.9's selection semantics but restores the
            # compact pre-V7.0.9 visual density. The game name is an EventBox
            # + normal Label instead of a Gtk.Button, so it does not inherit
            # button padding/min-height or make every game row look oversized.
            #   • checkbox click = explicit multi-select toggle
            #   • game-name click = exclusive single selection
            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
            check = Gtk.CheckButton()
            check.set_tooltip_text("Add or remove this game from multi-selection")
            check.set_active(sid in self.selected_ids)
            check.connect("toggled", self.on_game_toggled, sid)
            row_box.pack_start(check, False, False, 0)

            name_event = Gtk.EventBox()
            name_event.set_visible_window(False)
            name_event.set_hexpand(True)
            name_label = Gtk.Label(label=item["name"])
            name_label.set_xalign(0)
            name_label.set_margin_start(3)
            name_event.add(name_label)
            name_event.connect("button-release-event", self.on_game_name_clicked, sid)
            row_box.pack_start(name_event, True, True, 0)

            row.add(row_box)
            self.game_list.add(row)
            self.game_checks[sid] = check

        self.game_list.show_all()

    def on_game_name_clicked(self, _widget, _event, sid):
        # A normal click means "this game", not "add this game". Any previous
        # checkbox multi-selection is therefore collapsed to this single game.
        self._apply_game_selection({sid})
        return False

    def on_game_toggled(self, check, sid):
        if self._selector_syncing:
            return
        if check.get_active():
            self.selected_ids.add(sid)
        else:
            self.selected_ids.discard(sid)
        self._update_selector_summary()
        self._update_action_sensitivity()

    def on_select_all_games(self, _button):
        self._apply_game_selection(set(self.games))

    def on_clear_game_selection(self, _button):
        self._apply_game_selection(set())

    def refresh_games(self, preferred_id=None):
        # Stable-branch recovery: restore active Moses shortcuts even for
        # complete games added through Find Game EXE + Add to Steam (those do
        # not necessarily carry a Proton-prefix ownership marker).
        try:
            repair_steam_native_registry_from_owned_prefixes()
        except Exception:
            pass
        previous = set(self.selected_ids)
        if preferred_id:
            previous = {str(preferred_id)}
        self.games.clear()

        # Steam-native games installed by One-Click.
        native = load_steam_native_registry()
        for key, entry in native.items():
            status = str(entry.get("status") or "")
            try:
                appid = int(entry.get("appid", key))
            except Exception:
                continue
            stale_shortcut_leftover = False
            if status == "removed":
                # V7.2.5 recovery for removals performed by older buggy builds:
                # keep a removed entry visible ONLY while its non-Steam shortcut
                # still exists, so Complete Game Removal can clean that leftover.
                try:
                    stale_shortcut_leftover = steam_native_shortcut_exists(appid)
                except Exception:
                    stale_shortcut_leftover = False
                if not stale_shortcut_leftover:
                    continue
            elif status not in {"installed", "detached", "pending_steam"}:
                continue
            sid = f"steam:{appid}"
            self.games[sid] = {
                "id": str(appid),
                "name": str(entry.get("name") or f"Steam game {appid}"),
                "directory": str(entry.get("compatdata") or ""),
                "runner": "steam-proton",
                "backend": "steam",
                "appid": appid,
                "final_exe": str(entry.get("final_exe") or ""),
                "start_dir": str(entry.get("start_dir") or ""),
                "status": "removed_shortcut_leftover" if stale_shortcut_leftover else str(entry.get("status") or "installed"),
                "storage_mode": str(entry.get("storage_mode") or "internal"),
                "storage_root": str(entry.get("storage_root") or ""),
                "storage_uuid": str(entry.get("storage_uuid") or ""),
                "compatdata": str(entry.get("compatdata") or ""),
                "compat_tool": str(entry.get("compat_tool") or ""),
                "registry_status": status,
                "exe_reselect_available": bool(entry.get("exe_reselect_available")),
                "exe_reselect_known": "exe_reselect_available" in entry,
                "exe_reselect_pending": bool(entry.get("exe_reselect_pending")),
            }

        # Existing Lutris games remain fully supported as the alternate backend.
        try:
            rows = list_lutris_games()
        except Exception as exc:
            rows = []
            if not self.games:
                self.set_status(f"Could not read Lutris library: {exc}")

        for game_id, name, directory, runner in rows:
            sid = f"lutris:{game_id}"
            lutris_uuid = ""
            try:
                parts = Path(directory or "").parts
                if "external-drive-links" in parts:
                    idx = parts.index("external-drive-links")
                    if idx + 1 < len(parts):
                        lutris_uuid = str(parts[idx + 1])
            except Exception:
                pass
            self.games[sid] = {
                "id": str(game_id),
                "name": name,
                "directory": directory or "",
                "runner": runner or "",
                "backend": "lutris",
                "storage_mode": "external" if lutris_uuid else "internal",
                "storage_uuid": lutris_uuid,
            }

        if not self.games:
            self.selected_ids.clear()
            self._rebuild_game_checks()
            self._update_selector_summary()
            self._update_action_sensitivity()
            self.set_status("No One-Click Steam or Lutris games were found.")
            return

        kept = {sid for sid in previous if sid in self.games}
        if kept:
            self.selected_ids = kept
        else:
            first_sid = min(
                self.games,
                key=lambda sid: self.games[sid]["name"].casefold(),
            )
            self.selected_ids = {first_sid}

        self._rebuild_game_checks()
        self._update_selector_summary()
        self._update_action_sensitivity()
        self.set_status("")

    def on_reselect_exe(self, _button):
        """Edit the selected Steam game's visible name and/or main EXE.

        Renaming deliberately preserves the existing AppID and physical game
        folder. That means Proton compatdata, artwork slots and compatibility
        settings remain attached while the new title is used by Steam and by
        future artwork searches.
        """
        item = self.selected_game()
        if not item or item.get("backend") != "steam":
            return

        helper = Path.home() / ".local/bin/lutris-exe-helper"
        if not helper.is_file():
            return
        try:
            appid = int(item.get("appid") or item.get("id"))
        except Exception:
            return

        payload = {"ok": True, "available": False, "candidates": [], "game_name": item.get("name") or f"Steam game {appid}"}
        try:
            result = subprocess.run(
                ["flatpak-spawn", "--host", str(helper), "reselect-exe-candidates", str(appid)],
                text=True,
                capture_output=True,
                timeout=30,
                check=False,
            )
            if result.returncode == 0:
                candidate_payload = json.loads((result.stdout or "{}").strip() or "{}")
                if candidate_payload.get("ok"):
                    payload = candidate_payload
        except Exception:
            # Name editing must remain available even when the Proton prefix is
            # disconnected or there are no alternative EXE candidates.
            pass

        current_name = str(item.get("name") or payload.get("game_name") or f"Steam game {appid}").strip()
        chooser = Gtk.Dialog(
            title=tr(f"Edit {current_name}"),
            parent=self,
            flags=0,
        )
        chooser.set_default_size(650, 230)
        chooser.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
        ok_button = chooser.add_button(tr("Save changes"), Gtk.ResponseType.OK)
        ok_button.get_style_context().add_class("suggested-action")

        area = chooser.get_content_area()
        area.set_spacing(10)
        area.set_border_width(16)

        name_label = Gtk.Label(label=tr("GAME NAME"))
        name_label.set_xalign(0.0)
        name_label.get_style_context().add_class("section-label")
        area.pack_start(name_label, False, False, 0)

        name_entry = Gtk.Entry()
        name_entry.set_text(current_name)
        name_entry.set_activates_default(True)
        area.pack_start(name_entry, False, False, 0)

        candidates = list(payload.get("candidates") or []) if payload.get("available") else []
        combo = None
        current_exe = str(payload.get("current_exe") or item.get("final_exe") or "")
        if candidates:
            exe_label = Gtk.Label(label=tr("MAIN GAME EXE"))
            exe_label.set_xalign(0.0)
            exe_label.get_style_context().add_class("section-label")
            area.pack_start(exe_label, False, False, 0)

            combo = Gtk.ComboBoxText()
            active_index = 0
            for index, candidate in enumerate(candidates):
                path = str(candidate.get("path") or "")
                display = str(candidate.get("label") or path)
                combo.append(path, display)
                if current_exe and path == current_exe:
                    active_index = index
            combo.set_active(active_index)
            area.pack_start(combo, False, False, 0)
        else:
            hint = Gtk.Label(label=tr("The game name can be changed without moving the game folder or changing its Steam AppID."))
            hint.set_xalign(0.0)
            hint.set_line_wrap(True)
            hint.get_style_context().add_class("api-hint")
            area.pack_start(hint, False, False, 0)

        chooser.set_default_response(Gtk.ResponseType.OK)
        chooser.show_all()
        response = chooser.run()
        new_name = name_entry.get_text().strip() if response == Gtk.ResponseType.OK else ""
        selected_exe = combo.get_active_id() if (response == Gtk.ResponseType.OK and combo is not None) else None
        chooser.destroy()
        if response != Gtk.ResponseType.OK:
            self.set_status("")
            return
        if not new_name:
            message(self, tr("Game name could not be changed"), tr("Game name cannot be empty."), Gtk.MessageType.ERROR)
            return

        exe_changed = bool(selected_exe and current_exe and selected_exe != current_exe)
        name_changed = new_name != current_name
        pending_steam = False

        # Apply an EXE change first, if requested. It preserves the existing
        # title; the rename step below then becomes the final desired state.
        if exe_changed:
            try:
                result = subprocess.run(
                    ["flatpak-spawn", "--host", str(helper), "reselect-exe-apply", str(appid), selected_exe, "no-defer"],
                    text=True,
                    capture_output=True,
                    timeout=45,
                    check=False,
                )
                if result.returncode != 0:
                    raise RuntimeError((result.stderr or result.stdout or "Host helper exited unexpectedly.").strip())
                applied = json.loads((result.stdout or "{}").strip() or "{}")
                if not applied.get("ok"):
                    raise RuntimeError(str(applied.get("error") or "The selected EXE could not be applied."))
                pending_steam = pending_steam or bool(applied.get("pending_steam"))
            except Exception as exc:
                self.set_status(tr("Main EXE update failed."))
                message(self, tr("Main EXE update failed"), str(exc), Gtk.MessageType.ERROR)
                return

        if name_changed:
            try:
                result = subprocess.run(
                    ["flatpak-spawn", "--host", str(helper), "rename-steam-game", str(appid), new_name, "no-defer"],
                    text=True,
                    capture_output=True,
                    timeout=45,
                    check=False,
                )
                if result.returncode != 0:
                    raise RuntimeError((result.stderr or result.stdout or "Host helper exited unexpectedly.").strip())
                renamed = json.loads((result.stdout or "{}").strip() or "{}")
                if not renamed.get("ok"):
                    raise RuntimeError(str(renamed.get("error") or "The game name could not be changed."))
                pending_steam = pending_steam or bool(renamed.get("pending_steam"))
            except Exception as exc:
                self.set_status(tr("Game name update failed."))
                message(self, tr("Game name update failed"), str(exc), Gtk.MessageType.ERROR)
                return

        if not name_changed and not exe_changed:
            self.set_status(tr("No changes were made."))
            return

        # New name immediately becomes the artwork search title. Existing
        # artwork is intentionally left alone until the user requests another
        # Download + Apply All Artworks pass.
        display_name = new_name if name_changed else current_name
        if pending_steam:
            if self._offer_apply_pending_exe_now(appid):
                self.set_status(tr(f"Updated {display_name}."), success=True)
            else:
                self._queue_pending_steam_finalize(appid)
                self.set_status(tr(f"Updated {display_name}. Steam will refresh the shortcut when it next closes or changes mode."), success=True)
        else:
            self.set_status(tr(f"Updated {display_name}."), success=True)
        self.refresh_games(preferred_id=f"steam:{appid}")

    def _queue_pending_steam_finalize(self, appid):
        helper = Path.home() / ".local/bin/lutris-exe-helper"
        if not helper.is_file():
            return False
        try:
            command = (
                f"nohup {shlex.quote(str(helper))} finalize-pending-steam {int(appid)} "
                ">/dev/null 2>&1 &"
            )
            _host_run(command, timeout=5)
            return True
        except Exception:
            return False

    def _restart_steam_and_finalize_pending(self, appid):
        """Reload a pending non-Steam shortcut without rebooting SteamOS.

        Steam does not reliably hot-reload shortcuts.vdf.  Stop it cleanly, let
        the host helper commit the new target, then reopen Steam through its
        desktop identity so KDE/portal activation state is not inherited from
        the OneClick Flatpak.
        """
        helper = Path.home() / ".local/bin/lutris-exe-helper"
        if not helper.is_file():
            return False, tr("The Steam shortcut could not be finalized after the EXE change.")

        self.set_status(tr("Applying EXE change and restarting Steam…"))
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)

        if host_steam_is_running() and not stop_host_steam(timeout=22):
            self._queue_pending_steam_finalize(appid)
            return False, tr("Steam could not be stopped cleanly. The EXE change is saved and will apply the next time Steam is restarted.")

        try:
            result = subprocess.run(
                ["flatpak-spawn", "--host", str(helper), "finalize-pending-steam", str(int(appid))],
                text=True, capture_output=True, timeout=30, check=False,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or tr("The Steam shortcut could not be finalized after the EXE change.")).strip()
                return False, detail
        except Exception as exc:
            return False, str(exc)

        # Start Steam through its normal desktop identity.  This helper already
        # strips activation variables that previously triggered portal issues.
        start_host_steam()
        deadline = time.time() + 35
        while time.time() < deadline:
            if host_steam_is_running():
                # The process appears before the client is ready for steam://
                # requests, so give it a brief settle period and then restore
                # the main client window instead of leaving Steam minimized.
                time.sleep(2.5)
                show_host_steam_window()
                return True, ""
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)
            time.sleep(0.35)
        return False, tr("Steam did not become ready again after the EXE change. Open Steam normally; the new EXE has already been saved.")

    def _offer_apply_pending_exe_now(self, appid):
        if not confirm(
            self,
            tr("Apply EXE change now?"),
            tr("Steam must reload this non-Steam shortcut before the new EXE can be used. Moses OneClick Tool can restart Steam cleanly now, apply the new EXE, and reopen Steam. Choose Cancel to apply it automatically the next time Steam closes or you switch modes."),
        ):
            self._queue_pending_steam_finalize(appid)
            return False

        ok, detail = self._restart_steam_and_finalize_pending(appid)
        if not ok:
            message(self, tr("EXE change pending Steam restart"), detail, Gtk.MessageType.INFO)
        self.refresh_games(preferred_id=f"steam:{int(appid)}")
        return ok


    def _launch_moses_host_tool(self, launcher_name, friendly_name):
        launcher = Path.home() / ".local/bin" / launcher_name
        if not launcher.is_file():
            message(
                self,
                tr(f"{friendly_name} could not be opened"),
                f"The integrated launcher was not found:\n\n{launcher}",
                Gtk.MessageType.ERROR,
            )
            return False
        try:
            subprocess.Popen(
                ["flatpak-spawn", "--host", str(launcher)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                close_fds=True,
            )
            return True
        except Exception as exc:
            message(
                self,
                tr(f"{friendly_name} could not be opened"),
                str(exc),
                Gtk.MessageType.ERROR,
            )
            return False

    def on_stream_extract(self, _button):
        if self._launch_moses_host_tool("moses-streamextract", "StreamExtract"):
            self.set_status(tr("StreamExtract opened."), success=True)

    def on_temp_overlay(self, _button):
        if self._launch_moses_host_tool("moses-tempoverlay", "TempOverlay"):
            self.set_status(tr("TempOverlay opened."), success=True)

    def on_restart_steam(self, _button):
        # Never block the GTK main loop while waiting for Steam to shut down.
        self.restart_steam_btn.set_sensitive(False)
        self.set_status(tr("Restarting Steam…"))
        threading.Thread(target=self._restart_steam_worker, daemon=True).start()

    def _restart_steam_worker(self):
        ok = True
        detail = ""
        try:
            if host_steam_is_running():
                if not stop_host_steam(timeout=25):
                    ok = False
                    detail = tr("Steam could not be stopped cleanly.")
            if ok:
                if not start_host_steam():
                    ok = False
                    detail = tr("Steam could not be started again.")
                else:
                    deadline = time.time() + 35
                    while time.time() < deadline and not host_steam_is_running():
                        time.sleep(0.35)
                    if not host_steam_is_running():
                        ok = False
                        detail = tr("Steam could not be started again.")
                    else:
                        # Steam's process appears before its URI/shortcut handler
                        # is ready. Give the client a short settle period, then
                        # explicitly restore the main Steam window.
                        time.sleep(2.0)
                        show_host_steam_window()
        except Exception as exc:
            ok = False
            detail = str(exc)
        GLib.idle_add(self._finish_restart_steam, ok, detail)

    def _finish_restart_steam(self, ok, detail):
        self.restart_steam_btn.set_sensitive(True)
        if ok:
            self.set_status(tr("Steam restarted."), success=True)
        else:
            self.set_status(tr("Steam restart failed"))
            message(self, tr("Steam restart failed"), detail or tr("Steam could not be started again."), Gtk.MessageType.ERROR)
        return False

    def on_install(self, _button):
        chooser = Gtk.FileChooserDialog(
            title=tr("Choose Windows Game Installer"),
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        chooser.add_button("Cancel", Gtk.ResponseType.CANCEL)
        open_button = chooser.add_button("Install", Gtk.ResponseType.OK)
        open_button.get_style_context().add_class("suggested-action")

        exe_filter = Gtk.FileFilter()
        exe_filter.set_name("Windows executables (*.exe)")
        exe_filter.add_pattern("*.exe")
        exe_filter.add_pattern("*.EXE")
        chooser.add_filter(exe_filter)

        all_filter = Gtk.FileFilter()
        all_filter.set_name("All files")
        all_filter.add_pattern("*")
        chooser.add_filter(all_filter)

        response = chooser.run()
        filename = chooser.get_filename()
        chooser.destroy()

        if response != Gtk.ResponseType.OK or not filename:
            return

        exe = Path(filename).expanduser().resolve()

        if not exe.is_file():
            message(
                self,
                "Installer could not be opened",
                f"The selected file no longer exists:\\n\\n{exe}",
                Gtk.MessageType.ERROR,
            )
            return

        if exe.suffix.lower() != ".exe":
            if not confirm(
                self,
                "This file is not an .exe",
                f"{exe.name}\\n\\nContinue anyway?",
            ):
                return

        helper = Path.home() / ".local/bin/lutris-exe-helper"

        if not helper.is_file():
            message(
                self,
                "One-Click installer helper was not found",
                str(helper),
                Gtk.MessageType.ERROR,
            )
            return

        # The Tools GUI itself runs inside the Lutris Flatpak.
        # Ask Flatpak to run our existing host-side helper, so this follows
        # EXACTLY the same install path as double-click/Open with Lutris Installer.
        try:
            subprocess.Popen(
                [
                    "flatpak-spawn",
                    "--host",
                    str(helper),
                    "new",
                    str(exe),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as exc:
            message(
                self,
                "Could not start the installer",
                str(exc),
                Gtk.MessageType.ERROR,
            )
            return

        self.set_status(
            f"Opening installer for {exe.name} using the saved backend…",
            success=True,
        )


    def _dependency_inventory(self, item=None):
        helper = Path.home() / ".local/bin/lutris-exe-helper"
        if not helper.is_file():
            return {"ok": False, "error": "Moses dependency helper is missing."}
        if not item:
            backend = "cache"
            game_id = "-"
        else:
            backend = str(item.get("backend") or "")
            game_id = str(item.get("appid") if backend == "steam" else item.get("id") or "")
            if not game_id:
                return {"ok": False, "error": "The selected game identifier is missing."}
        hint = {}
        if item and backend == "steam":
            hint = {
                "appid": item.get("appid") or item.get("id"),
                "name": item.get("name") or "",
                "final_exe": item.get("final_exe") or "",
                "start_dir": item.get("start_dir") or "",
                "compatdata": item.get("compatdata") or "",
                "compat_tool": item.get("compat_tool") or "",
                "storage_mode": item.get("storage_mode") or "",
                "storage_root": item.get("storage_root") or "",
                "storage_uuid": item.get("storage_uuid") or "",
                "status": item.get("registry_status") or item.get("status") or "",
            }
        try:
            result = subprocess.run(
                ["flatpak-spawn", "--host", str(helper), "dependency-inventory", backend, game_id, json.dumps(hint)],
                text=True, capture_output=True, timeout=35,
            )
            lines = [x.strip() for x in (result.stdout or "").splitlines() if x.strip()]
            if not lines:
                return {"ok": False, "error": (result.stderr or "No dependency scan response.").strip()}
            return json.loads(lines[-1])
        except Exception as exc:
            return {"ok": False, "error": str(exc)}

    def _add_dependency_row(self, box, item, checks):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        check = Gtk.CheckButton()
        # V7.4.36: dependency repair is intentionally opt-in. Finding/caching a
        # redistributable must never mean Moses installs it automatically.
        check.set_active(False)
        row.pack_start(check, False, False, 0)
        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        title = Gtk.Label(label=str(item.get("label") or item.get("filename") or "Dependency"))
        title.set_xalign(0)
        title.get_style_context().add_class("button-label")
        detail_bits = [str(item.get("filename") or "")]
        if item.get("install_mode") == "game-folder-components":
            detail_bits.append("copies matching runtime DLLs beside game EXE")
        if item.get("source") == "cache":
            detail_bits.append("shared cache")
        elif item.get("source") == "game":
            detail_bits.append("detected in game files")
        if item.get("advanced"):
            detail_bits.append("manual / advanced")
        detail = Gtk.Label(label="  ·  ".join(x for x in detail_bits if x))
        detail.set_xalign(0)
        detail.get_style_context().add_class("api-hint")
        text_box.pack_start(title, False, False, 0)
        text_box.pack_start(detail, False, False, 0)
        row.pack_start(text_box, True, True, 0)
        box.pack_start(row, False, False, 0)
        checks.append((check, item))

    def on_dependencies(self, _button):
        item = self.selected_game()
        library_only = item is None
        payload = self._dependency_inventory(item)
        if not payload.get("ok"):
            message(self, "Dependencies could not be scanned", str(payload.get("error") or "Unknown error"), Gtk.MessageType.ERROR)
            return

        dlg = Gtk.Dialog(title=("Dependency Library" if library_only else f"Dependencies — {item.get('name', 'Game')}"), transient_for=self, modal=True)
        dlg.set_default_size(640, 540)
        dlg.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
        install_button = dlg.add_button("Install Selected", Gtk.ResponseType.OK)
        install_button.get_style_context().add_class("suggested-action")
        install_button.set_sensitive(not library_only)
        area = dlg.get_content_area()
        area.set_spacing(10)
        area.set_border_width(18)

        headline = Gtk.Label()
        headline.set_markup("<span size='large' weight='bold'>Dependency Library</span>" if library_only else "<span size='large' weight='bold'>Install / Repair Dependencies</span>")
        headline.set_xalign(0)
        area.pack_start(headline, False, False, 0)
        if library_only:
            desc_text = (
                "No game is selected, so this window is in Dependency Library mode. You can download the official pack, "
                "download your GitHub ZIP pack, import a local dependency ZIP, or inspect the shared runtime cache now. "
                "Nothing is installed into a game until you later select exactly one game and choose Install / Repair Dependencies."
            )
        else:
            desc_text = (
                "Nothing is installed automatically. Moses only detects and caches known redistributable installers/components for reuse. "
                "If the game already works with Proton/Wine, leave everything alone. If it does not launch, select only the dependency you want to try; "
                "it will be installed only into this game's existing prefix. All choices start unchecked."
            )
        desc = Gtk.Label(label=desc_text)
        desc.set_xalign(0); desc.set_line_wrap(True)
        desc.get_style_context().add_class("subtitle")
        area.pack_start(desc, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(270)
        list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=9)
        list_box.set_border_width(8)
        checks = []
        for dep in payload.get("items") or []:
            self._add_dependency_row(list_box, dep, checks)
        if not checks:
            empty = Gtk.Label(label=("The shared runtime cache is empty. Download the official pack, download your GitHub pack, or import a local dependency ZIP below." if library_only else "No known redistributables were detected in this game's files or the shared cache. You can still add a custom installer below."))
            empty.set_xalign(0); empty.set_line_wrap(True)
            empty.get_style_context().add_class("subtitle")
            list_box.pack_start(empty, False, False, 0)
        scroll.add(list_box)
        area.pack_start(scroll, True, True, 0)

        custom_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        custom_btn = Gtk.Button(label="+ Add custom dependency installer…")
        custom_btn.get_style_context().add_class("secondary")
        custom_btn.set_sensitive(not library_only)
        if library_only:
            custom_btn.set_tooltip_text("Select one game first to run a one-off custom dependency installer. Use Import dependency ZIP to add files to the shared library.")
        custom_row.pack_start(custom_btn, False, False, 0)
        cache_btn = Gtk.Button(label="Open shared runtime cache")
        cache_btn.get_style_context().add_class("secondary")
        custom_row.pack_end(cache_btn, False, False, 0)
        area.pack_start(custom_row, False, False, 0)
        pack_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        import_pack_btn = Gtk.Button(label="Import dependency ZIP…")
        import_pack_btn.get_style_context().add_class("secondary")
        official_pack_btn = Gtk.Button(label="Download official dependency set")
        official_pack_btn.get_style_context().add_class("secondary")
        pack_row.pack_start(import_pack_btn, True, True, 0)
        pack_row.pack_start(official_pack_btn, True, True, 0)
        area.pack_start(pack_row, False, False, 0)
        download_pack_btn = Gtk.Button(label="Download dependency pack from GitHub")
        download_pack_btn.get_style_context().add_class("secondary")
        area.pack_start(download_pack_btn, False, False, 0)

        def add_custom(_btn):
            chooser = Gtk.FileChooserDialog(title="Choose dependency installer", parent=dlg, action=Gtk.FileChooserAction.OPEN)
            chooser.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
            chooser.add_button("Add", Gtk.ResponseType.OK)
            flt = Gtk.FileFilter(); flt.set_name("Dependency installers/components (*.exe, *.msi, *.zip)"); flt.add_pattern("*.exe"); flt.add_pattern("*.EXE"); flt.add_pattern("*.msi"); flt.add_pattern("*.MSI"); flt.add_pattern("*.zip"); flt.add_pattern("*.ZIP"); chooser.add_filter(flt)
            response = chooser.run(); filename = chooser.get_filename(); chooser.destroy()
            if response == Gtk.ResponseType.OK and filename:
                p = Path(filename).expanduser().resolve()
                if p.is_file():
                    bundle_meta = {"kind": "", "label": p.name, "install_mode": ""}
                    if p.suffix.casefold() == ".zip" and "vulkanrt" in p.name.casefold() and "component" in p.name.casefold():
                        bundle_meta = {"kind": "vulkan-components", "label": "Vulkan Runtime Components (game folder)", "install_mode": "game-folder-components"}
                    dep = {"path": str(p), "filename": p.name, "label": bundle_meta.get("label") or p.name, "kind": bundle_meta.get("kind"), "install_mode": bundle_meta.get("install_mode"), "recommended": False, "advanced": True, "source": "manual"}
                    self._add_dependency_row(list_box, dep, checks)
                    list_box.show_all()
        custom_btn.connect("clicked", add_custom)

        def refresh_dependency_rows():
            nonlocal payload
            updated = self._dependency_inventory(item)
            if not updated.get("ok"):
                return
            payload = updated
            checks.clear()
            for child in list_box.get_children():
                list_box.remove(child)
            for dep in payload.get("items") or []:
                self._add_dependency_row(list_box, dep, checks)
            if not checks:
                empty = Gtk.Label(label=("The shared runtime cache is empty. Download the official pack, download your GitHub pack, or import a local dependency ZIP below." if library_only else "No known redistributables were detected in this game's files or the shared cache. You can still add a custom installer below."))
                empty.set_xalign(0); empty.set_line_wrap(True)
                empty.get_style_context().add_class("subtitle")
                list_box.pack_start(empty, False, False, 0)
            list_box.show_all()

        def import_pack(_btn):
            chooser = Gtk.FileChooserDialog(title="Import dependency ZIP", parent=dlg, action=Gtk.FileChooserAction.OPEN)
            chooser.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
            chooser.add_button("Import", Gtk.ResponseType.OK)
            flt = Gtk.FileFilter(); flt.set_name("Dependency ZIP (*.zip)"); flt.add_pattern("*.zip"); flt.add_pattern("*.ZIP"); chooser.add_filter(flt)
            response = chooser.run(); filename = chooser.get_filename(); chooser.destroy()
            if response != Gtk.ResponseType.OK or not filename:
                return
            helper = Path.home() / ".local/bin/lutris-exe-helper"
            import_pack_btn.set_sensitive(False)
            import_pack_btn.set_label("Importing dependency ZIP…")

            def worker():
                try:
                    result = subprocess.run(
                        ["flatpak-spawn", "--host", str(helper), "dependency-pack-import", str(filename)],
                        text=True, capture_output=True, timeout=900,
                    )
                    try:
                        payload_result = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                    except Exception:
                        payload_result = {"ok": False, "error": (result.stderr or result.stdout or "Dependency ZIP import failed.").strip()}
                except Exception as exc:
                    payload_result = {"ok": False, "error": str(exc)}

                def finish():
                    import_pack_btn.set_sensitive(True)
                    import_pack_btn.set_label("Import dependency ZIP…")
                    if payload_result.get("ok"):
                        refresh_dependency_rows()
                        count = int(payload_result.get("files") or 0)
                        message(dlg, "Dependency ZIP imported", f"Imported {count} file(s) into the shared runtime cache.", Gtk.MessageType.INFO)
                    else:
                        message(dlg, "Dependency ZIP import failed", str(payload_result.get("error") or "Unknown error"), Gtk.MessageType.ERROR)
                    return False
                GLib.idle_add(finish)
            threading.Thread(target=worker, daemon=True).start()

        import_pack_btn.connect("clicked", import_pack)

        def download_official_pack(_btn):
            helper = Path.home() / ".local/bin/lutris-exe-helper"
            official_pack_btn.set_sensitive(False)
            official_pack_btn.set_label("Downloading dependency set…")

            def worker():
                try:
                    result = subprocess.run(
                        ["flatpak-spawn", "--host", str(helper), "dependency-official-download"],
                        text=True, capture_output=True, timeout=1800,
                    )
                    try:
                        payload_result = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                    except Exception:
                        payload_result = {"ok": False, "error": (result.stderr or result.stdout or "Official dependency download failed.").strip()}
                except Exception as exc:
                    payload_result = {"ok": False, "error": str(exc)}

                def finish():
                    official_pack_btn.set_sensitive(True)
                    official_pack_btn.set_label("Download official dependency set")
                    if payload_result.get("ok") or payload_result.get("partial"):
                        refresh_dependency_rows()
                        downloaded = int(payload_result.get("downloaded") or 0)
                        failed = int(payload_result.get("failed") or 0)
                        dx_note = " DirectX June 2010 was expanded to its offline DXSETUP/CAB bundle." if payload_result.get("directx_offline_ready") else ""
                        vk_note = " Vulkan Runtime Components are ready." if payload_result.get("vulkan_components_ready") else ""
                        if failed:
                            message(dlg, "Dependency set partly downloaded", f"Downloaded {downloaded} item(s); {failed} item(s) could not be downloaded.{dx_note}{vk_note}", Gtk.MessageType.WARNING)
                        else:
                            message(dlg, "Dependency set ready", f"Downloaded {downloaded} dependency item(s) into the shared runtime cache.{dx_note}{vk_note}", Gtk.MessageType.INFO)
                    else:
                        failures = payload_result.get("failures") or []
                        detail = str(payload_result.get("error") or (failures[0].get("error") if failures else "Unknown error"))
                        message(dlg, "Official dependency download failed", detail, Gtk.MessageType.ERROR)
                    return False
                GLib.idle_add(finish)
            threading.Thread(target=worker, daemon=True).start()

        official_pack_btn.connect("clicked", download_official_pack)

        def download_pack(_btn):
            settings = load_oneclick_settings()
            url_dlg = Gtk.Dialog(title="Dependency pack source", transient_for=dlg, modal=True)
            url_dlg.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
            get_btn = url_dlg.add_button("Download", Gtk.ResponseType.OK)
            get_btn.get_style_context().add_class("suggested-action")
            box = url_dlg.get_content_area(); box.set_spacing(8); box.set_border_width(16)
            explain = Gtk.Label(label=(
                "Paste a GitHub ZIP file link, GitHub Release asset, raw URL, or another direct HTTPS ZIP URL. "
                "Normal github.com/.../blob/... links are converted to raw downloads automatically. Moses remembers "
                "the last URL, validates the ZIP, and refreshes its own GitHub Packs folder."
            ))
            explain.set_xalign(0); explain.set_line_wrap(True); explain.get_style_context().add_class("subtitle")
            box.pack_start(explain, False, False, 0)
            entry = Gtk.Entry()
            entry.set_placeholder_text("https://github.com/USER/REPO/blob/main/Dependencies.zip")
            old_vulkan_default = "https://github.com/mosestyle/Moses-OneClick-Tool/blob/main/VulkanRT-1.3.290.0-Components.zip"
            remembered_pack_url = str(settings.get("dependency_pack_url") or "").strip()
            # V7.4.45 used the project Vulkan ZIP as the fresh-install default.
            # It now comes with the one-click dependency set, so the GitHub field
            # is reserved for the user's own packs. Preserve genuinely custom URLs.
            if remembered_pack_url == old_vulkan_default:
                remembered_pack_url = ""
            entry.set_text(remembered_pack_url)
            box.pack_start(entry, False, False, 0)
            url_dlg.show_all()
            response = url_dlg.run(); url = entry.get_text().strip(); url_dlg.destroy()
            if response != Gtk.ResponseType.OK:
                return
            if not url.lower().startswith("https://"):
                message(dlg, "Invalid dependency pack URL", "Use a direct HTTPS ZIP URL.", Gtk.MessageType.ERROR)
                return
            settings["dependency_pack_url"] = url
            try:
                save_oneclick_settings(settings)
            except Exception:
                pass
            helper = Path.home() / ".local/bin/lutris-exe-helper"
            download_pack_btn.set_sensitive(False)
            download_pack_btn.set_label("Downloading dependency pack…")

            def worker():
                try:
                    result = subprocess.run(
                        ["flatpak-spawn", "--host", str(helper), "dependency-pack-download", url],
                        text=True, capture_output=True, timeout=900,
                    )
                    try:
                        payload_result = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                    except Exception:
                        payload_result = {"ok": False, "error": (result.stderr or result.stdout or "Dependency pack download failed.").strip()}
                except Exception as exc:
                    payload_result = {"ok": False, "error": str(exc)}

                def finish():
                    download_pack_btn.set_sensitive(True)
                    download_pack_btn.set_label("Download dependency pack from GitHub")
                    if payload_result.get("ok"):
                        refresh_dependency_rows()
                        count = int(payload_result.get("files") or 0)
                        message(dlg, "Dependency pack ready", f"Downloaded and refreshed {count} file(s) in its own GitHub Packs folder inside the shared runtime cache.", Gtk.MessageType.INFO)
                    else:
                        message(dlg, "Dependency pack download failed", str(payload_result.get("error") or "Unknown error"), Gtk.MessageType.ERROR)
                    return False
                GLib.idle_add(finish)
            threading.Thread(target=worker, daemon=True).start()

        download_pack_btn.connect("clicked", download_pack)

        def open_cache(_btn):
            cache_dir = str(payload.get("cache_dir") or "")
            if cache_dir:
                try:
                    subprocess.Popen(["flatpak-spawn", "--host", "xdg-open", cache_dir], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception as exc:
                    message(dlg, "Runtime cache could not be opened", str(exc), Gtk.MessageType.ERROR)
        cache_btn.connect("clicked", open_cache)

        dlg.show_all()
        response = dlg.run()
        if response != Gtk.ResponseType.OK or library_only:
            dlg.destroy(); return
        selected = [str(dep.get("path") or "") for check, dep in checks if check.get_active() and dep.get("path")]
        dlg.destroy()
        if not selected:
            message(self, "No dependencies selected", "Select at least one dependency installer, or use Add custom dependency installer.", Gtk.MessageType.INFO)
            return
        helper = Path.home() / ".local/bin/lutris-exe-helper"
        backend = str(item.get("backend") or "")
        game_id = str(item.get("appid") if backend == "steam" else item.get("id") or "")
        hint = {}
        if backend == "steam":
            hint = {
                "appid": item.get("appid") or item.get("id"),
                "name": item.get("name") or "",
                "final_exe": item.get("final_exe") or "",
                "start_dir": item.get("start_dir") or "",
                "compatdata": item.get("compatdata") or "",
                "compat_tool": item.get("compat_tool") or "",
                "storage_mode": item.get("storage_mode") or "",
                "storage_root": item.get("storage_root") or "",
                "storage_uuid": item.get("storage_uuid") or "",
                "status": item.get("registry_status") or item.get("status") or "",
            }
        try:
            subprocess.Popen(
                ["flatpak-spawn", "--host", str(helper), "dependency-batch", backend, game_id, json.dumps(selected), json.dumps(hint)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
            )
            self.set_status(f"Installing {len(selected)} dependency installer(s) into {item.get('name', 'the selected game')} one after another…", success=True)
        except Exception as exc:
            message(self, "Dependencies could not be started", str(exc), Gtk.MessageType.ERROR)


    def on_play(self, _button):
        item = self.selected_game()
        if not item:
            return

        name = str(item.get("name") or "Selected game")
        backend = str(item.get("backend") or "")

        try:
            if backend == "steam":
                if str(item.get("status") or "") == "detached":
                    message(
                        self,
                        "Steam shortcut is not installed",
                        "Repair the Steam shortcut first, then try Play Game again.",
                        Gtk.MessageType.INFO,
                    )
                    return

                appid = int(item.get("appid") or item.get("id"))
                if item.get("exe_reselect_pending"):
                    # A changed main EXE cannot be used until Steam reloads its
                    # non-Steam shortcut table. Offer the safe reload path
                    # instead of surfacing xdg-open's misleading launch error.
                    if not self._offer_apply_pending_exe_now(appid):
                        return
                    item = self.selected_game() or item

                if not host_steam_is_running():
                    message(
                        self,
                        "Steam is not running",
                        "Open Steam first, then press Play Game again. One-Click will not start Steam automatically in Desktop Mode because current SteamOS builds can trigger KDE's Screen Sharing permission dialog when Steam is launched externally.",
                        Gtk.MessageType.INFO,
                    )
                    return

                big_picture_id = ((appid & 0xFFFFFFFF) << 32) | 0x02000000
                uri = f"steam://rungameid/{big_picture_id}"
                # Hand the URI to the already-running Steam client through the
                # desktop handler. Do NOT exec/start Steam here: current
                # SteamOS/KDE builds can show a ScreenCast permission dialog
                # whenever Steam itself is launched from Desktop Mode.
                result = _host_run(
                    f"xdg-open {shlex.quote(uri)} >/dev/null 2>&1",
                    timeout=8,
                )
                if result.returncode != 0:
                    # xdg-open can occasionally lose the steam:// association
                    # after a client restart. Steam is already confirmed to be
                    # running, so handing the URI directly to its client IPC is
                    # safe and does not create a second Steam instance.
                    result = _host_run(
                        f"steam {shlex.quote(uri)} >/dev/null 2>&1",
                        timeout=8,
                    )
                if result.returncode != 0:
                    raise RuntimeError("The running Steam client did not accept the game launch request.")
                self.set_status(f"Launching {name} through the running Steam client…", success=True)
            elif backend == "lutris":
                game_id = str(item.get("id") or "").strip()
                if not game_id:
                    raise RuntimeError("The Lutris game ID is missing.")
                wrapper = str(Path.home() / ".local/bin/oneclick-lutris-steam-launch")
                subprocess.Popen(
                    [
                        "flatpak-spawn",
                        "--host",
                        wrapper,
                        game_id,
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                self.set_status(f"Launching {name} through Lutris…", success=True)
            else:
                raise RuntimeError("Unknown game backend.")
        except Exception as exc:
            message(
                self,
                "Game could not be launched",
                str(exc),
                Gtk.MessageType.ERROR,
            )


    def on_repair(self, _button):
        items = self.selected_games()
        if not items:
            return

        count = len(items)
        names = [item["name"] for item in items]
        preview = "\n".join(
            f"• {item['name']}  ({'Steam' if item.get('backend') == 'steam' else 'Lutris'})"
            for item in items[:10]
        )
        if count > 10:
            preview += f"\n• …and {count - 10} more"

        if not confirm(
            self,
            "Repair Steam shortcut?" if count == 1 else f"Repair {count} Steam shortcuts?",
            (
                f"{preview}\n\n"
                "Steam-native games are restored as direct Windows EXE shortcuts and keep your current Steam Proton choice. "
                "If no Proton mapping exists, Proton Experimental is assigned.\n\n"
                "Lutris games keep the V5.x Lutris launcher format and have accidental Steam-side Proton overrides cleared.\n\n"
                "Steam may close briefly and reopen automatically."
            ),
        ):
            return

        self.set_artwork_busy(True)
        self.set_status(
            f"Repairing Steam shortcut for {names[0]}…" if count == 1
            else f"Repairing {count} Steam shortcuts…"
        )
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)

        steam_was_running = host_steam_is_running()
        if steam_was_running and not stop_host_steam():
            self.set_artwork_busy(False)
            message(
                self,
                "Steam could not be closed",
                "Close Steam manually and press Repair Steam Shortcut again.",
                Gtk.MessageType.ERROR,
            )
            return

        repaired = []
        failed = []
        try:
            config_path = steam_shortcut.get_config_path()
            if not config_path:
                raise RuntimeError("Steam's active user/config folder could not be found.")

            for index, item in enumerate(items, start=1):
                if count > 1:
                    self.set_status(f"Repairing shortcuts: {index}/{count} — {item['name']}…")
                while Gtk.events_pending():
                    Gtk.main_iteration_do(False)
                try:
                    if item.get("backend") == "steam":
                        appid = int(item["appid"])
                        final_exe = Path(item.get("final_exe") or "")
                        if not final_exe.is_file():
                            raise RuntimeError(
                                "The installed game EXE is missing. If the game was moved, reinstall it or repair the registry entry."
                            )
                        start_dir = Path(item.get("start_dir") or final_exe.parent)
                        launch_options = ""
                        if str(item.get("storage_mode") or "").lower() == "external":
                            helper = Path.home() / ".local/bin/lutris-exe-helper"
                            launch_options = f'"{helper}" external-steam-launch {appid} %command%'
                        steam_native_upsert_shortcut(
                            appid,
                            item["name"],
                            final_exe,
                            start_dir,
                            launch_options=launch_options,
                        )
                        ensure_steam_compat_mapping(config_path, appid)
                        update_steam_native_registry(
                            appid,
                            status="installed",
                            final_exe=str(final_exe),
                            start_dir=str(start_dir),
                        )
                    else:
                        game = Game(item["id"])
                        if not game.id or not game.is_installed:
                            raise RuntimeError("Lutris could not load this installed game.")
                        appid = steam_shortcut.generate_appid(game)
                        remove_steam_compat_mapping(config_path, appid)
                        remove_steam_launcher_compatdata(config_path, appid)
                        steam_shortcut.remove_shortcut(game)
                        steam_shortcut.create_shortcut(game, "")
                    repaired.append(item["name"])
                except Exception as exc:
                    failed.append({"name": item["name"], "error": str(exc)})
        except Exception as exc:
            failed.append({"name": "Steam", "error": str(exc)})
        finally:
            # Leave Steam closed. Current SteamOS/Steam-Jupiter builds can trigger
            # KDE's screen-sharing portal whenever Desktop Steam is relaunched.
            # The user can Return to Gaming Mode or start Steam manually afterwards.
            self.set_artwork_busy(False)

        if repaired:
            text = (
                f"Steam shortcut repaired for {repaired[0]}." if len(repaired) == 1
                else f"Repaired {len(repaired)}/{count} selected Steam shortcuts."
            )
            if any(item.get("backend") == "steam" for item in items):
                text += " Steam-native shortcuts can use Proton normally from Properties → Compatibility."
            if any(item.get("backend") == "lutris" for item in items):
                text += " Lutris shortcuts should keep Steam Compatibility OFF."
            if failed:
                text += "\nCould not repair: " + " | ".join(
                    f"{x['name']}: {x['error']}" for x in failed[:4]
                )
            self.set_status(text, success=True)
        else:
            message(
                self,
                "Steam shortcut repair failed",
                "\n".join(f"• {x['name']}: {x['error']}" for x in failed[:8]),
                Gtk.MessageType.ERROR,
            )
            self.set_status("Steam shortcut repair failed.")

    def set_artwork_busy(self, busy):
        self.artwork_busy = bool(busy)
        self._update_action_sensitivity()

    def on_settings(self, _button):
        old_language = load_language()
        dlg = Gtk.Dialog(
            title=tr("Moses OneClick Tool — Settings"),
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
        )
        # V7.2.5: Settings keeps the General / Storage / About tabs, but the
        # dialog is deliberately wider/taller so the entire Storage page fits
        # without a vertical scrollbar on a normal SteamOS Desktop.
        dlg.set_default_size(660, 650)
        dlg.set_size_request(610, 610)
        dlg.set_resizable(True)
        dlg.add_button(tr("Cancel"), Gtk.ResponseType.CANCEL)
        save_btn = dlg.add_button(tr("Save"), Gtk.ResponseType.OK)
        save_btn.get_style_context().add_class("suggested-action")
        dlg.set_default_response(Gtk.ResponseType.OK)

        area = dlg.get_content_area()
        notebook = Gtk.Notebook()
        notebook.set_scrollable(True)
        notebook.set_border_width(8)
        area.pack_start(notebook, True, True, 0)

        def make_page(name, scroll=False):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            box.set_border_width(14)
            if scroll:
                scroller = Gtk.ScrolledWindow()
                scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
                scroller.add(box)
                notebook.append_page(scroller, Gtk.Label(label=name))
            else:
                notebook.append_page(box, Gtk.Label(label=name))
            return box

        def heading(box, text, top=0):
            label = Gtk.Label(label=text)
            label.set_xalign(0)
            label.set_margin_top(top)
            label.set_margin_bottom(7)
            label.get_style_context().add_class("section-label")
            box.pack_start(label, False, False, 0)
            return label

        def hint(box, text, top=6, bottom=0, css="api-hint"):
            label = Gtk.Label(label=text)
            label.set_xalign(0)
            label.set_line_wrap(True)
            label.set_max_width_chars(64)
            label.set_margin_top(top)
            label.set_margin_bottom(bottom)
            label.get_style_context().add_class(css)
            box.pack_start(label, False, False, 0)
            return label

        general_box = make_page(tr("General"))
        storage_box = make_page(tr("Storage"), scroll=False)
        about_box = make_page(tr("About"))

        # ---------- General ----------
        heading(general_box, tr("INSTALLER BACKEND"))
        hint(
            general_box,
            tr("Steam / Proton is the default. Smart Automatic / Lutris is available for older or troublesome games."),
            top=0, bottom=9, css="subtitle",
        )
        backend_combo = Gtk.ComboBoxText()
        backend_combo.append("steam", tr("Steam / Proton (default)"))
        backend_combo.append("smart", "Smart Automatic / Lutris")
        backend_combo.append("lutris", tr("Lutris / Wine (manual)"))
        backend_combo.set_active_id(load_installer_backend())
        general_box.pack_start(backend_combo, False, False, 0)
        hint(
            general_box,
            tr("New Steam installs initially use Proton Experimental. You can change Proton later from Steam Properties → Compatibility."),
            bottom=18,
        )

        heading(general_box, tr("ARTWORK SOURCE"))
        artwork_source_combo = Gtk.ComboBoxText()
        artwork_source_combo.append("both", tr("Both — Steam + SteamGridDB (default)"))
        artwork_source_combo.append("steam", tr("Steam only"))
        artwork_source_combo.append("steamgriddb", tr("SteamGridDB only"))
        artwork_source_combo.set_active_id(load_artwork_source())
        general_box.pack_start(artwork_source_combo, False, False, 0)
        hint(
            general_box,
            tr("Both prefers official Steam artwork first, then falls back to SteamGridDB when Steam has no usable artwork for that slot."),
            bottom=14, css="subtitle",
        )

        heading(general_box, tr("STEAMGRIDDB API KEY"))
        api_entry = Gtk.Entry()
        api_entry.set_visibility(True)
        api_entry.set_placeholder_text(tr("Paste your personal SteamGridDB API key"))
        api_entry.set_text(load_sgdb_api_key())
        api_entry.set_activates_default(True)
        general_box.pack_start(api_entry, False, False, 0)
        hint(general_box, tr("Saved persistently on this SteamOS user account."))

        # ---------- Storage ----------
        heading(storage_box, tr("GAME FOLDERS"))
        open_game_folder_btn = Gtk.Button(label=tr("Open Selected Game Folder"))
        open_game_folder_btn.set_tooltip_text(tr("Open the actual folder for the currently selected game"))
        storage_box.pack_start(open_game_folder_btn, False, False, 0)

        def open_selected_game_folder(_button):
            item = self.selected_game()
            if not item:
                message(
                    self,
                    "Select one game first",
                    tr("Close Settings, select exactly one game in Moses OneClick Tool, then open Settings again and press Open Selected Game Folder."),
                    Gtk.MessageType.INFO,
                )
                return
            try:
                if item.get("backend") == "steam":
                    final_exe = str(item.get("final_exe") or "").strip()
                    if final_exe and Path(final_exe).is_file():
                        folder = Path(final_exe).parent
                    else:
                        compatdata = str(item.get("directory") or "").strip()
                        if not compatdata:
                            raise RuntimeError("One-Click could not determine this Steam game's install folder.")
                        folder = Path(compatdata)
                else:
                    directory = str(item.get("directory") or "").strip()
                    if not directory:
                        raise RuntimeError("Lutris did not provide an install folder for this game.")
                    folder = Path(os.path.expanduser(directory))
                if not folder.exists():
                    raise RuntimeError(f"The game folder no longer exists:\n\n{folder}")
                try:
                    opened = Gio.AppInfo.launch_default_for_uri(folder.resolve().as_uri(), None)
                    if not opened:
                        raise RuntimeError("No default file manager accepted the folder URI.")
                except Exception:
                    subprocess.Popen(
                        ["xdg-open", str(folder)], stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL, start_new_session=True,
                    )
                self.set_status(f"Opened game folder for {item['name']}.")
            except Exception as exc:
                message(self, "Game folder could not be opened", str(exc), Gtk.MessageType.ERROR)

        open_game_folder_btn.connect("clicked", open_selected_game_folder)

        open_all_prefixes_btn = Gtk.Button(label=tr("Open All Game Prefixes"))
        open_all_prefixes_btn.set_tooltip_text("Open one clean game-name view: internal prefixes are real folders; external prefixes are named links to the real folders on the external drive.")
        open_all_prefixes_btn.set_margin_top(7)
        storage_box.pack_start(open_all_prefixes_btn, False, False, 0)

        def open_all_game_prefixes(_button):
            try:
                # Host-side migration keeps external UUID aliases and older
                # external folder names current before the friendly view is built.
                helper = Path.home() / ".local/bin/lutris-exe-helper"
                try:
                    subprocess.run(
                        ["flatpak-spawn", "--host", str(helper), "migrate-external-paths"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False,
                    )
                except Exception:
                    pass
                folder, count = build_named_compatdata_view()
                # V7.2.5 presents one clean folder: internal prefixes are real
                # directories and external prefixes are game-named links to the
                # real removable-drive directories.
                try:
                    opened = Gio.AppInfo.launch_default_for_uri(folder.resolve().as_uri(), None)
                    if not opened:
                        raise RuntimeError("No default file manager accepted the folder URI.")
                except Exception:
                    subprocess.Popen(
                        ["xdg-open", str(folder)], stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL, start_new_session=True,
                    )
                self.set_status(f"Opened {count} game-named prefix location(s). External games appear as links to their real folders.")
            except Exception as exc:
                message(self, "Game prefixes could not be opened", str(exc), Gtk.MessageType.ERROR)

        open_all_prefixes_btn.connect("clicked", open_all_game_prefixes)
        # V7.2.5: preferred Settings order is Open All first, then Selected.
        # GAME FOLDERS heading is child 0; move Open All directly below it.
        storage_box.reorder_child(open_all_prefixes_btn, 1)
        hint(storage_box, ("Internal prefixes are real game-name folders. External games appear here as game-name links to their real folders on the removable drive. Steam numeric AppID compatibility links stay hidden." if load_language() != "sv" else "Interna prefix är riktiga mappar med spelnamn. Externa spel visas här som länkar med spelnamn till de riktiga mapparna på den externa disken. Steams numeriska AppID-kompatibilitetslänkar hålls dolda."), bottom=10)

        heading(storage_box, tr("EXTERNAL DRIVE"))
        format_external_btn = Gtk.Button(label=tr("Format External Drive"))
        format_external_btn.set_tooltip_text(tr("Format a mounted external USB/SSD as Btrfs, ext4 or NTFS and choose its drive name"))
        storage_box.pack_start(format_external_btn, False, False, 0)
        hint(storage_box, tr("Btrfs/ext4: SteamOS only. NTFS: SteamOS + Windows. Formatting always asks first."), bottom=10)

        def format_external_drive(_button):
            try:
                helper = Path.home() / ".local/bin/lutris-exe-helper"
                self.set_status("External drive formatter opened…")
                result = subprocess.run(
                    ["flatpak-spawn", "--host", str(helper), "format-external"],
                    text=True, capture_output=True, timeout=60 * 60,
                )
                payload = {}
                try:
                    payload = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                except Exception:
                    payload = {}
                if payload.get("cancelled"):
                    self.set_status("External drive formatting cancelled.")
                    return
                if result.returncode != 0 or not payload.get("ok"):
                    raise RuntimeError(str(payload.get("error") or result.stderr or result.stdout or "External drive formatting failed.").strip())
                path = str(payload.get("path") or "External drive")
                fstype = str(payload.get("fstype") or "").upper()
                message(self, "External drive ready", (f"Formaterades korrekt som {fstype}.\n\nMonterad på:\n{path}" if load_language() == "sv" else f"Formatted successfully as {fstype}.\n\nMounted at:\n{path}"), Gtk.MessageType.INFO)
                self.set_status(f"External drive ready: {path}", success=True)
            except Exception as exc:
                message(self, "External drive formatting failed", str(exc), Gtk.MessageType.ERROR)

        format_external_btn.connect("clicked", format_external_drive)

        heading(storage_box, tr("BTRFS SPACE SAVER"), top=4)
        hint(
            storage_box,
            tr("Deduplicate exact matching data across approved Proton/Wine prefixes using Btrfs Copy-on-Write."),
            top=0, bottom=7, css="subtitle",
        )
        btrfs_combo = Gtk.ComboBoxText()
        btrfs_targets = []
        try:
            helper = Path.home() / ".local/bin/lutris-exe-helper"
            result = subprocess.run(
                ["flatpak-spawn", "--host", str(helper), "btrfs-targets"],
                text=True, capture_output=True, timeout=20,
            )
            if result.returncode == 0:
                payload = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                btrfs_targets = payload.get("targets") or []
        except Exception:
            btrfs_targets = []
        for idx, target in enumerate(btrfs_targets):
            btrfs_combo.append(str(idx), str(target.get("label") or target.get("path") or "Btrfs prefixes"))
        if btrfs_targets:
            btrfs_combo.set_active(0)
        else:
            btrfs_combo.append("none", tr("No Btrfs Proton/OneClick storage detected"))
            btrfs_combo.set_active_id("none")
            btrfs_combo.set_sensitive(False)
        storage_box.pack_start(btrfs_combo, False, False, 0)

        btrfs_btn = Gtk.Button(label=tr("Run Btrfs Space Saver"))
        btrfs_btn.set_margin_top(7)
        btrfs_btn.set_sensitive(bool(btrfs_targets))
        storage_box.pack_start(btrfs_btn, False, False, 0)

        def run_btrfs_saver(_button):
            active = btrfs_combo.get_active()
            if not (0 <= active < len(btrfs_targets)):
                return
            target = btrfs_targets[active]
            path = str(target.get("path") or "").strip()
            if not path:
                return
            confirm_dlg = Gtk.MessageDialog(
                transient_for=self, flags=Gtk.DialogFlags.MODAL,
                message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.YES_NO,
                text=tr("Run Btrfs Space Saver?"),
            )
            confirm_dlg.format_secondary_text(tr(
                "This can take a while on large prefix libraries. Games/installers should be closed while it runs. "
                "The Linux kernel performs an exact byte comparison before sharing any range."
            ))
            ok = confirm_dlg.run() == Gtk.ResponseType.YES
            confirm_dlg.destroy()
            if not ok:
                return
            try:
                helper = Path.home() / ".local/bin/lutris-exe-helper"
                self.set_status("Btrfs Space Saver is running…")
                result = subprocess.run(
                    ["flatpak-spawn", "--host", str(helper), "btrfs-space-saver", path],
                    text=True, capture_output=True, timeout=24 * 60 * 60,
                )
                payload = {}
                try:
                    payload = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                except Exception:
                    payload = {}
                if result.returncode != 0 or not payload.get("ok"):
                    raise RuntimeError(str(payload.get("error") or result.stderr or result.stdout or "Space Saver failed").strip())
                freed = int(payload.get("freed_bytes") or 0)
                merged = int(payload.get("deduped_ranges_bytes") or 0)
                def hsize(value):
                    v = float(max(0, value))
                    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
                        if v < 1024 or unit == "TiB":
                            return f"{int(v)} {unit}" if unit == "B" else f"{v:.1f} {unit}"
                        v /= 1024
                detail = f"Exact duplicate ranges merged: {hsize(merged)}."
                if freed:
                    detail += f"\nApproximate free-space increase after sync: {hsize(freed)}."
                else:
                    detail += "\nBtrfs may account/reclaim shared extents asynchronously, so free-space change can appear later."
                message(self, "Btrfs Space Saver complete", detail, Gtk.MessageType.INFO)
                self.set_status("Btrfs Space Saver completed.", success=True)
            except Exception as exc:
                message(self, "Btrfs Space Saver failed", str(exc), Gtk.MessageType.ERROR)

        btrfs_btn.connect("clicked", run_btrfs_saver)

        heading(storage_box, tr("CLEANUP"), top=10)
        cleanup_btn = Gtk.Button(label=tr("Clean Failed Steam Installs"))
        storage_box.pack_start(cleanup_btn, False, False, 0)
        hint(storage_box, tr("Removes orphaned failed OneClick Proton prefixes while preserving active games."))

        def clean_failed(_button):
            helper = Path.home() / ".local/bin/lutris-exe-helper"
            try:
                result = subprocess.run(
                    ["flatpak-spawn", "--host", str(helper), "cleanup-failed"],
                    text=True, capture_output=True, timeout=120,
                )
                if result.returncode != 0:
                    raise RuntimeError((result.stderr or result.stdout or "Cleanup failed").strip())
                data = json.loads((result.stdout or "{}").strip().splitlines()[-1])
                count = int(data.get("removed_count") or 0)
                freed = int(data.get("bytes") or 0)
                units = ["B", "KB", "MB", "GB", "TB"]
                value = float(freed)
                unit = units[0]
                for unit in units:
                    if value < 1024 or unit == units[-1]:
                        break
                    value /= 1024
                size_text = f"{int(value)} {unit}" if unit == "B" else f"{value:.1f} {unit}"
                if count:
                    message(self, "Failed installs cleaned", f"Removed {count} failed Steam prefix(es) and freed about {size_text}.", Gtk.MessageType.INFO)
                else:
                    message(self, "Nothing to clean", "No orphaned OneClick Steam-native prefixes could be safely removed. Active shortcuts and successful installs are preserved.", Gtk.MessageType.INFO)
            except Exception as exc:
                message(self, "Cleanup failed", str(exc), Gtk.MessageType.ERROR)

        cleanup_btn.connect("clicked", clean_failed)

        # ---------- About ----------
        heading(about_box, tr("MOSES ONECLICK TOOL"))
        about_title = Gtk.Label(label="Moses OneClick Tool")
        about_title.set_xalign(0)
        about_title.set_margin_bottom(4)
        about_box.pack_start(about_title, False, False, 0)
        version_value = Gtk.Label(label=f"Version {TOOL_VERSION}")
        version_value.set_xalign(0)
        version_value.get_style_context().add_class("subtitle")
        about_box.pack_start(version_value, False, False, 0)

        heading(about_box, tr("LANGUAGE"), top=18)
        language_combo = Gtk.ComboBoxText()
        language_combo.append("en", tr("English (default)"))
        language_combo.append("sv", tr("Swedish"))
        language_combo.set_active_id(load_language())
        about_box.pack_start(language_combo, False, False, 0)
        hint(
            about_box,
            tr("Language changes are applied the next time a Moses OneClick window or installer dialog opens."),
            top=6, bottom=8, css="subtitle",
        )

        hint(
            about_box,
            tr("Moses OneClick Tool uses Steam / Proton by default, with Smart Automatic / Lutris, external drives, artwork management and Btrfs Space Saver when needed."),
            top=14,
        )

        notebook.show_all()
        response = dlg.run()
        if response == Gtk.ResponseType.OK:
            api_key = api_entry.get_text().strip()
            backend = backend_combo.get_active_id() or DEFAULT_INSTALLER_BACKEND
            artwork_source = artwork_source_combo.get_active_id() or DEFAULT_ARTWORK_SOURCE
            language = language_combo.get_active_id() or DEFAULT_LANGUAGE
            try:
                save_sgdb_api_key(api_key)
                settings = load_oneclick_settings()
                settings["installer_backend"] = backend
                settings["artwork_source"] = artwork_source
                settings["language"] = language
                save_oneclick_settings(settings)
                if (
                    load_sgdb_api_key() != api_key
                    or load_installer_backend() != backend
                    or load_artwork_source() != artwork_source
                    or load_language() != language
                ):
                    raise RuntimeError("The saved settings could not be read back.")
                backend_label = {"steam": "Steam / Proton", "smart": "Smart Automatic / Lutris", "lutris": "Lutris / Wine (manual)"}.get(backend, "Steam / Proton")
                artwork_label = {"both": "Both", "steam": "Steam", "steamgriddb": "SteamGridDB"}.get(artwork_source, "Both")
                language_label = "Svenska" if language == "sv" else "English"
                self.set_status(
                    tr(f"Settings saved. Installer backend: {backend_label}. Artwork source: {artwork_label}.") + f" Language: {language_label}."
                    + (" SteamGridDB API is ready." if api_key else " SteamGridDB needs an API key before it can be used."),
                    success=True,
                )
            except Exception as exc:
                dlg.destroy()
                message(self, "Settings could not be saved", str(exc), Gtk.MessageType.ERROR)
                return
        dlg.destroy()
        if response == Gtk.ResponseType.OK and language != old_language:
            try:
                helper = Path.home() / ".local/bin/lutris-exe-helper"
                gui_path = Path.home() / ".local/share/lutris-oneclick/lutris_oneclick_tools.py"
                subprocess.Popen(
                    ["flatpak-spawn", "--host", str(helper), "tools", str(gui_path)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                )
                self.destroy()
            except Exception:
                pass

    def on_open_artwork_folder(self, _button):
        """Open Steam's active custom artwork folder in the file manager.

        This is deliberately the applied Steam grid folder, not our download
        cache, so deleting files here removes the custom artwork Steam shows.
        """
        try:
            config_path = steam_shortcut.get_config_path()
            if not config_path:
                raise RuntimeError(
                    "Steam's active user/config folder could not be found. "
                    "Start Steam once in Desktop Mode and try again."
                )

            grid_dir = Path(config_path) / "grid"
            grid_dir.mkdir(parents=True, exist_ok=True)

            # Gio normally routes the file:// URI through the desktop/Flatpak
            # portal and opens the user's normal file manager (Dolphin on
            # SteamOS). Keep xdg-open as a fallback for older portal setups.
            try:
                opened = Gio.AppInfo.launch_default_for_uri(grid_dir.as_uri(), None)
                if not opened:
                    raise RuntimeError("No default file manager accepted the folder URI.")
            except Exception:
                subprocess.Popen(
                    ["xdg-open", str(grid_dir)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            self.set_status(
                "Opened Steam artwork folder. Deleting files there removes "
                "the custom artwork Steam is currently using."
            )
        except Exception as exc:
            message(
                self,
                "Steam artwork folder could not be opened",
                str(exc),
                Gtk.MessageType.ERROR,
            )

    def on_artwork(self, _button):
        items = self.selected_games()
        if not items:
            return

        # The API key lives in Settings and is persisted immediately when the
        # user presses Save. Official Steam artwork can work without a key;
        # SteamGridDB simply becomes unavailable as a fallback if none is saved.
        api_key = load_sgdb_api_key()

        try:
            config_path = steam_shortcut.get_config_path()
            if not config_path:
                raise RuntimeError(
                    "Steam's active user/config folder could not be found. Start Steam once in Desktop Mode and try again."
                )
            grid_dir = Path(config_path) / "grid"
        except Exception as exc:
            message(
                self,
                "Artwork could not be prepared",
                str(exc),
                Gtk.MessageType.ERROR,
            )
            return

        jobs = []
        preparation_failures = []
        for item in items:
            try:
                if item.get("backend") == "steam":
                    appid = int(item["appid"])
                    if not steam_native_shortcut_exists(appid):
                        raise RuntimeError(
                            "No Steam shortcut was found. Use Repair Steam Shortcut first."
                        )
                    hints = []
                    final_exe = str(item.get("final_exe") or "")
                    if final_exe:
                        fp = Path(final_exe)
                        hints.extend([fp.parent.name, fp.stem])
                        if fp.parent.parent != fp.parent:
                            hints.append(fp.parent.parent.name)
                    jobs.append({
                        "name": item["name"],
                        "backend": "steam",
                        "appid": appid,
                        "grid_id": str(appid),
                        "grid_dir": grid_dir,
                        "lutris_icon_path": None,
                        "search_hints": hints,
                    })
                else:
                    game = Game(item["id"])
                    if not game.id or not game.is_installed:
                        raise RuntimeError("Lutris could not load this installed game.")

                    # V7.2.5: do not use Lutris shortcut_exists(game) as a gate.
                    # OneClick intentionally replaces Lutris' Flatpak Exe with
                    # oneclick-lutris-steam-launch, so Lutris can report False
                    # even though the Steam shortcut is valid. Resolve the real
                    # AppID directly. If the shortcut is still pending, stage
                    # artwork under the stable generated AppID so it appears as
                    # soon as the shortcut is finalized.
                    expected_appid = steam_shortcut.generate_appid(game)
                    actual_appid, shortcut_found = find_lutris_shortcut_appid(
                        game.id, item["name"], expected_appid
                    )
                    grid_id = actual_appid or (int(expected_appid) & 0xffffffff)

                    hints = []
                    directory = str(item.get("directory") or "")
                    if directory:
                        dp = Path(directory)
                        hints.extend([dp.name, dp.parent.name])
                    if getattr(game, "slug", None):
                        hints.append(str(game.slug).replace("-", " "))
                    jobs.append({
                        "name": item["name"],
                        "backend": "lutris",
                        "grid_id": grid_id,
                        "grid_dir": grid_dir,
                        "lutris_icon_path": Path(resources.get_icon_path(game.slug)),
                        "search_hints": hints,
                        "shortcut_found": bool(shortcut_found),
                    })
            except Exception as exc:
                preparation_failures.append({"name": item["name"], "error": str(exc)})

        if not jobs:
            details = "\n".join(
                f"• {entry['name']}: {entry['error']}"
                for entry in preparation_failures
            )
            message(
                self,
                "Artwork could not be prepared",
                details or "No selected game could be prepared.",
                Gtk.MessageType.ERROR,
            )
            return

        self.set_artwork_busy(True)
        selected_count = len(items)
        if selected_count == 1:
            self.set_status(f"Finding artwork for {items[0]['name']}…")
        else:
            self.set_status(
                f"Downloading artwork for {selected_count} selected games… "
                "Artwork types are fetched in parallel."
            )

        worker = threading.Thread(
            target=self._artwork_batch_worker,
            args=(jobs, api_key, preparation_failures),
            daemon=True,
        )
        worker.start()

    def _artwork_batch_worker(self, jobs, api_key, preparation_failures):
        results = list(preparation_failures)

        def run_job(job):
            result = download_and_apply_all_artwork(
                job["name"],
                job["grid_id"],
                job["grid_dir"],
                api_key,
                job["lutris_icon_path"],
                job.get("search_hints"),
            )
            if job.get("backend") == "steam" and result.get("icon_path"):
                queue_steam_native_icon_refresh(job["appid"], result["icon_path"])
            return {"name": job["name"], "result": result, "job": job}

        # Up to two games at once. Each game itself fetches its five artwork
        # types concurrently. Two is a deliberate ceiling so batch mode feels
        # fast without creating an excessive burst of SGDB/CDN requests.
        max_games = min(2, len(jobs))
        completed = 0
        with ThreadPoolExecutor(max_workers=max_games) as executor:
            future_map = {executor.submit(run_job, job): job for job in jobs}
            for future in as_completed(future_map):
                job = future_map[future]
                try:
                    results.append(future.result())
                except Exception as exc:
                    failed_entry = {"name": job["name"], "error": str(exc), "job": job}
                    # Only prepare the one-time chooser after a complete
                    # artwork failure. Partial 1-4/5 results never prompt.
                    if api_key and get_sgdb_match_override(job["name"]) is None:
                        try:
                            candidates = sgdb_candidate_options(
                                job["name"], api_key, job.get("search_hints"), 5
                            )
                            if candidates:
                                failed_entry["sgdb_candidates"] = candidates
                        except Exception:
                            pass
                    results.append(failed_entry)
                completed += 1
                GLib.idle_add(
                    self._artwork_batch_progress,
                    completed,
                    len(jobs),
                    job["name"],
                )

        GLib.idle_add(self._artwork_batch_finished, results)

    def _artwork_batch_progress(self, completed, total, game_name):
        if total > 1:
            self.set_status(
                f"Artwork progress: {completed}/{total} finished. Latest: {game_name}."
            )
        return False

    def _choose_sgdb_match_dialog(self, game_name, candidates):
        candidates = [x for x in (candidates or []) if isinstance(x, dict) and x.get("id") is not None][:5]
        if not candidates:
            return None

        dialog = Gtk.Dialog(
            title=tr("Which game is this?"),
            transient_for=self,
            flags=Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
        )
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Use selected game", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.set_resizable(False)

        area = dialog.get_content_area()
        area.set_spacing(12)
        area.set_margin_top(16)
        area.set_margin_bottom(16)
        area.set_margin_start(18)
        area.set_margin_end(18)

        label = Gtk.Label()
        label.set_xalign(0)
        label.set_line_wrap(True)
        label.set_max_width_chars(56)
        label.set_text(
            f'One-Click could not find any usable artwork for "{game_name}" automatically.\n\n'
            "Choose the correct SteamGridDB entry once. This choice will be remembered and you should not be asked again for this game."
        )
        area.pack_start(label, False, False, 0)

        combo = Gtk.ComboBoxText()
        for item in candidates:
            types = item.get("types") or []
            if not isinstance(types, list):
                types = [types]
            type_text = ", ".join(str(x) for x in types[:3] if x)
            flags = []
            if item.get("verified"):
                flags.append("verified")
            if type_text:
                flags.append(type_text)
            suffix = f"  —  {' / '.join(flags)}" if flags else ""
            combo.append(str(item["id"]), f'{item.get("name") or game_name}{suffix}')
        combo.set_active(0)
        area.pack_start(combo, False, False, 0)

        dialog.show_all()
        response = dialog.run()
        selected_id = combo.get_active_id() if response == Gtk.ResponseType.OK else None
        dialog.destroy()
        if not selected_id:
            return None
        for item in candidates:
            if str(item.get("id")) == str(selected_id):
                return item
        return None

    def _artwork_batch_finished(self, entries):
        self.set_artwork_busy(False)

        successes = [entry for entry in entries if isinstance(entry.get("result"), dict)]
        errors = [entry for entry in entries if entry.get("error")]

        # Rare one-time ambiguity fallback. Never show this for partial artwork:
        # it is only reached when a game got absolutely 0/5. Background
        # post-install artwork also never opens UI; the chooser appears only
        # after the user manually presses Download + Apply All Artworks.
        for failed_entry in errors:
            candidates = failed_entry.get("sgdb_candidates") or []
            if candidates and get_sgdb_match_override(failed_entry.get("name", "")) is None:
                choice = self._choose_sgdb_match_dialog(failed_entry.get("name", "Game"), candidates)
                if choice is not None:
                    save_sgdb_match_override(failed_entry.get("name", "Game"), choice)
                    self.set_status(
                        f"Remembered SteamGridDB match: {choice.get('name')}. Retrying artwork…"
                    )
                    GLib.idle_add(self.on_artwork, None)
                    return False
                break

        # Preserve the more detailed single-game result users already know.
        if len(entries) == 1 and successes:
            entry = successes[0]
            game_name = entry["name"]
            result = entry["result"]
            parts = [
                f"Applied {result['applied']}/5 artworks for {game_name}.",
                f"Downloaded {result['downloaded']} new file(s); reused {result['reused']} cached file(s).",
            ]
            if result.get("matched_name") and result["matched_name"] != game_name:
                query_used = str(result.get("sgdb_search_query") or game_name)
                if normalize_game_name(query_used) != normalize_game_name(game_name):
                    parts.append(f"SteamGridDB match: {result['matched_name']} (searched as {query_used}).")
                else:
                    parts.append(f"SteamGridDB match: {result['matched_name']}.")
            if result.get("steam_appid"):
                steam_label = result.get("steam_game_name") or game_name
                parts.append(f"Steam match: {steam_label} (AppID {result['steam_appid']}).")
            counts = result.get("provider_counts") or {}
            steam_count = int(counts.get("steam") or 0)
            sgdb_count = int(counts.get("sgdb") or 0)
            if steam_count or sgdb_count:
                source_bits = []
                if steam_count:
                    source_bits.append(f"Official Steam {steam_count}/5")
                if sgdb_count:
                    source_bits.append(f"SteamGridDB {sgdb_count}/5")
                parts.append("Sources: " + ", ".join(source_bits) + ".")
            if result.get("fallbacks"):
                parts.append("Fallback: " + ", ".join(result["fallbacks"]) + ".")
            if result.get("missing"):
                parts.append("Not available: " + ", ".join(result["missing"]) + ".")
            if result.get("failed"):
                parts.append("Some types failed: " + " | ".join(result["failed"]) + ".")
            parts.append("Return to Gaming Mode / reload Steam to see any artwork Steam has not hot-reloaded yet.")
            self.set_status("\n".join(parts), success=True)
            return False

        if len(entries) == 1 and errors:
            self.set_status("Artwork download failed.")
            message(
                self,
                "Artwork could not be applied",
                errors[0]["error"],
                Gtk.MessageType.ERROR,
            )
            return False

        complete = 0
        partial = []
        downloaded = 0
        reused = 0
        for entry in successes:
            result = entry["result"]
            downloaded += int(result.get("downloaded") or 0)
            reused += int(result.get("reused") or 0)
            if int(result.get("applied") or 0) == 5:
                complete += 1
            else:
                partial.append(f"{entry['name']} {result.get('applied', 0)}/5")

        parts = [
            f"Artwork finished for {len(entries)} games: {complete} complete, {len(partial)} partial, {len(errors)} failed.",
            f"Downloaded {downloaded} new file(s); reused {reused} cached file(s).",
        ]
        if partial:
            parts.append("Partial: " + ", ".join(partial) + ".")
        if errors:
            parts.append(
                "Failed: " + " | ".join(
                    f"{entry['name']}: {entry['error']}" for entry in errors[:4]
                ) + (" …" if len(errors) > 4 else ".")
            )
        parts.append("Return to Gaming Mode / reload Steam when the batch is finished.")
        self.set_status("\n".join(parts), success=bool(successes))
        return False

    def on_remove(self, _button):
        items = self.selected_games()
        if not items:
            return

        def mount_root_from_path(value):
            try:
                p = Path(os.path.expanduser(str(value or "")))
                parts = p.parts
                if len(parts) >= 5 and parts[:3] == ("/", "run", "media"):
                    return Path(*parts[:5])
                if len(parts) >= 4 and parts[:2] == ("/", "media"):
                    return Path(*parts[:4])
            except Exception:
                pass
            return None

        def external_state(item):
            root_text = str(item.get("storage_root") or "").strip()
            uuid_text = str(item.get("storage_uuid") or "").strip()
            explicit = str(item.get("storage_mode") or "").strip().lower() == "external"
            candidates = [
                str(item.get("final_exe") or ""),
                str(item.get("start_dir") or ""),
                str(item.get("directory") or ""),
            ]
            root = Path(os.path.expanduser(root_text)) if root_text else None
            uuid_connected = None
            if uuid_text:
                try:
                    info = subprocess.run(
                        ["lsblk", "-J", "-o", "UUID,MOUNTPOINTS"],
                        text=True, capture_output=True, timeout=5, check=False,
                    )
                    data = json.loads(info.stdout or "{}") if info.returncode == 0 else {}
                    def walk(nodes):
                        for node in nodes or []:
                            yield node
                            yield from walk(node.get("children") or [])
                    for node in walk(data.get("blockdevices") or []):
                        if str(node.get("uuid") or "").strip().casefold() != uuid_text.casefold():
                            continue
                        mounts = node.get("mountpoints") or []
                        if isinstance(mounts, str):
                            mounts = [mounts]
                        mounted = next((Path(str(x)) for x in mounts if x and Path(str(x)).is_dir()), None)
                        uuid_connected = mounted is not None
                        if mounted is not None:
                            root = mounted
                        break
                except Exception:
                    pass
            if root is None:
                for value in candidates:
                    guessed = mount_root_from_path(value)
                    if guessed is not None:
                        root = guessed
                        explicit = True
                        break
            # A Steam compatdata link can remain even while its external target is gone.
            directory = str(item.get("directory") or "").strip()
            target = None
            if directory:
                raw = Path(os.path.expanduser(directory))
                try:
                    if raw.is_symlink():
                        target = raw.resolve(strict=False)
                        guessed = mount_root_from_path(target)
                        if guessed is not None and root is None:
                            root = guessed
                            explicit = True
                except Exception:
                    target = None
            connected = bool(uuid_connected if uuid_connected is not None else (root and root.exists() and root.is_dir()))
            return {
                "external": bool(explicit or uuid_text or root is not None),
                "root": root,
                "connected": connected,
                "target": target,
            }

        external_infos = []
        for item in items:
            state = external_state(item)
            if state["external"]:
                external_infos.append((item, state))

        # V7.2.5: warn before touching Steam/Lutris state whenever an external
        # game is selected. A disconnected drive is especially important: the
        # library entry can be removed, but the actual files cannot be deleted.
        if external_infos:
            lines = []
            missing = 0
            for item, state in external_infos[:8]:
                root = state.get("root")
                where = str(root) if root else "external storage"
                if state.get("connected"):
                    lines.append(f"• {item['name']}: external drive connected — {where}")
                else:
                    missing += 1
                    lines.append(f"• {item['name']}: external drive NOT connected — {where}")
            if len(external_infos) > 8:
                lines.append(f"• …and {len(external_infos) - 8} more")
            detail = "\n".join(lines)
            if missing:
                detail += (
                    "\n\nOne or more external drives are not connected. If you continue, OneClick can remove "
                    "the Steam/Lutris shortcut, artwork and internal OneClick metadata, but it CANNOT delete "
                    "the actual game files that remain on the disconnected drive.\n\n"
                    "For a true Complete Game Removal, Cancel now, reconnect the drive, then remove the game again."
                )
            else:
                detail += (
                    "\n\nThese games are stored on external media. Continuing will remove their library/Steam integration first; "
                    "you will still receive the normal second confirmation before any reachable game files are permanently deleted."
                )
            if not confirm(self, "External game storage detected", detail):
                return

        prepared = []
        validation_errors = []
        for item in items:
            try:
                path_text = item.get("directory") or ""
                if item.get("backend") == "steam" and not path_text:
                    config_path = steam_shortcut.get_config_path()
                    steam_root = steam_root_from_user_config(config_path) if config_path else None
                    if steam_root:
                        path_text = str(steam_root / "steamapps" / "compatdata" / str(int(item["appid"])))

                state = external_state(item)
                can_delete_files = True
                if state.get("external") and not state.get("connected"):
                    # Do not reject Complete Removal merely because a removable
                    # drive is absent. The pre-flight dialog already made the
                    # limitation explicit; skip only physical file deletion.
                    candidate = state.get("target") or (Path(os.path.expanduser(path_text)) if path_text else Path("/nonexistent"))
                    game_path = Path(candidate).resolve(strict=False)
                    can_delete_files = False
                else:
                    # Steam external compatdata is a symlink into the external
                    # Btrfs/ext4 volume. Validate/delete the marked target, not
                    # an unverified link. Internal/legacy Steam links are also
                    # allowed when their target carries the matching OneClick marker.
                    candidate = state.get("target") if state.get("external") and state.get("target") else path_text
                    expected_appid = int(item["appid"]) if item.get("backend") == "steam" else None
                    game_path = safe_game_directory(str(candidate), expected_appid)

                source_link = None
                try:
                    original_path = Path(os.path.expanduser(path_text)) if path_text else None
                    if original_path is not None and original_path.is_symlink():
                        source_link = original_path
                except Exception:
                    source_link = None

                prepared.append({
                    "item": item,
                    "path": game_path,
                    "source_link": source_link,
                    "external": bool(state.get("external")),
                    "external_connected": bool(state.get("connected")),
                    "external_root": state.get("root"),
                    "can_delete_files": can_delete_files,
                })
            except Exception as exc:
                validation_errors.append(f"• {item['name']}: {exc}")

        if validation_errors:
            message(
                self,
                "Selected games cannot be removed safely",
                "Nothing was removed.\n\n" + "\n".join(validation_errors[:8])
                + ("\n…" if len(validation_errors) > 8 else ""),
                Gtk.MessageType.ERROR,
            )
            return

        count = len(prepared)
        preview = "\n".join(
            f"• {entry['item']['name']}  ({'Steam' if entry['item'].get('backend') == 'steam' else 'Lutris'})"
            for entry in prepared[:10]
        )
        if count > 10:
            preview += f"\n• …and {count - 10} more"

        if not confirm(
            self,
            f"Remove {prepared[0]['item']['name']}?" if count == 1 else f"Remove {count} selected games?",
            (
                f"{preview}\n\n"
                "This removes the Steam shortcut, custom artwork/cache and compatibility mapping. "
                "For Lutris games it also removes the Lutris library/config entry.\n\n"
                "The actual game files/prefixes are not deleted until the second confirmation."
            ),
        ):
            return

        self.remove_btn.set_sensitive(False)
        self.repair_btn.set_sensitive(False)
        self.artwork_btn.set_sensitive(False)
        self.selector_button.set_sensitive(False)
        self.refresh_btn.set_sensitive(False)
        self.set_status(
            f"Removing {prepared[0]['item']['name']}…" if count == 1
            else f"Removing {count} selected games…"
        )

        steam_was_running = host_steam_is_running()
        if steam_was_running and not stop_host_steam():
            self._update_action_sensitivity()
            message(
                self,
                "Steam could not be closed",
                "Nothing was removed. Close Steam manually and try again.",
                Gtk.MessageType.ERROR,
            )
            return

        removed = []
        failed = []
        cleanup_count = 0
        try:
            config_path = steam_shortcut.get_config_path()
            if not config_path:
                raise RuntimeError("Steam's active user/config folder could not be found.")

            for index, entry in enumerate(prepared, start=1):
                item = entry["item"]
                name = item["name"]
                if count > 1:
                    self.set_status(f"Removing games: {index}/{count} — {name}…")
                while Gtk.events_pending():
                    Gtk.main_iteration_do(False)

                try:
                    if item.get("backend") == "steam":
                        appid = int(item["appid"])
                        # Persistent generation barrier: even if an old detached
                        # watcher wakes later, it cannot make this removed game
                        # look installed again.
                        record_removal_tombstone(appid)
                        removed_shortcut_ids = steam_native_remove_managed_shortcuts(
                            appid, item.get("name") or "", item.get("final_exe") or ""
                        )
                        all_shortcut_ids = {int(appid) & 0xffffffff}
                        all_shortcut_ids.update(int(x) & 0xffffffff for x in removed_shortcut_ids)
                        for shortcut_appid in all_shortcut_ids:
                            remove_steam_compat_mapping(config_path, shortcut_appid)
                            cleanup_count += remove_game_artwork_files(config_path, shortcut_appid)
                        # V7.2.5: mark a hidden tombstone immediately. A delayed
                        # Steam finalizer must not be able to re-create the removed
                        # shortcut/registry state after Complete Game Removal.
                        update_steam_native_registry(
                            appid,
                            status="removed",
                            final_exe="",
                            start_dir="",
                            artwork_pending=False,
                            removed_at=int(time.time()),
                        )
                    else:
                        game = Game(item["id"])
                        appid = steam_shortcut.generate_appid(game)

                        # Ask Lutris first, then directly remove any stale
                        # shortcut variants left by older wrapper/AppID formats.
                        # This fixes games disappearing from OneClick/Lutris
                        # while their old Non-Steam shortcut remains in Steam.
                        try:
                            steam_shortcut.remove_shortcut(game)
                        except Exception:
                            pass
                        removed_appids = remove_lutris_shortcuts_direct(
                            item["id"], item.get("name") or "", appid
                        )
                        all_shortcut_ids = {int(appid) & 0xffffffff}
                        all_shortcut_ids.update(int(x) & 0xffffffff for x in removed_appids)
                        for shortcut_appid in all_shortcut_ids:
                            remove_steam_compat_mapping(config_path, shortcut_appid)
                            # This compatdata belongs only to Steam wrapping the
                            # Lutris Linux launcher, not the real Lutris prefix.
                            remove_steam_launcher_compatdata(config_path, shortcut_appid)
                            cleanup_count += remove_game_artwork_files(config_path, shortcut_appid)

                        if game.is_installed:
                            game.uninstall(delete_files=False)
                        if game.id is not None:
                            game.delete()
                    removed.append(entry)
                except Exception as exc:
                    failed.append({"name": name, "error": str(exc)})
        except Exception as exc:
            failed.append({"name": "Steam cleanup", "error": str(exc)})
        finally:
            # Do not auto-relaunch Desktop Steam after removal; this avoids the
            # current KDE/Steam PipeWire screen-share prompt.
            pass

        if not removed:
            self.refresh_games()
            message(
                self,
                "The selected games could not be removed",
                "No game files were permanently deleted.\n\n"
                + "\n".join(f"• {x['name']}: {x['error']}" for x in failed[:8]),
                Gtk.MessageType.ERROR,
            )
            return

        existing = [entry for entry in removed if entry.get("can_delete_files", True) and entry["path"].exists()]
        disconnected_external = [
            entry for entry in removed
            if entry.get("external") and not entry.get("external_connected")
        ]
        deleted = []
        kept_files = list(existing)
        delete_failures = []

        if existing:
            folder_preview = "\n".join(
                f"• {entry['item']['name']}: {entry['path']}"
                for entry in existing[:8]
            )
            if len(existing) > 8:
                folder_preview += f"\n• …and {len(existing) - 8} more"
            if confirm(
                self,
                "Permanently delete game files?" if len(existing) == 1 else f"Permanently delete files for {len(existing)} games?",
                folder_preview + "\n\nThis permanently deletes the listed folders/prefixes and cannot be undone.",
                destructive=True,
            ):
                kept_files = []
                for entry in sorted(existing, key=lambda x: len(x["path"].parts), reverse=True):
                    try:
                        shutil.rmtree(entry["path"])
                        # If this registry row originally pointed through a verified
                        # OneClick symlink, remove the link itself after deleting its
                        # owned target so no broken game-name/numeric alias is left.
                        try:
                            source_link = entry.get("source_link")
                            if source_link is not None and Path(source_link).is_symlink():
                                Path(source_link).unlink(missing_ok=True)
                        except Exception:
                            pass
                        try:
                            sibling_marker = entry["path"].parent / f".{entry['path'].name}{ONECLICK_EXTERNAL_MARKER}"
                            sibling_marker.unlink(missing_ok=True)
                        except Exception:
                            pass
                        if entry["item"].get("backend") == "steam":
                            try:
                                config_path = steam_shortcut.get_config_path()
                                steam_root = steam_root_from_user_config(config_path) if config_path else None
                                compat_link = (steam_root / "steamapps" / "compatdata" / str(int(entry["item"]["appid"]))) if steam_root else None
                                if compat_link and compat_link.is_symlink():
                                    compat_link.unlink(missing_ok=True)
                            except Exception:
                                pass
                        deleted.append(entry)
                        # Keep the hidden V7.2.5 removal tombstone. It is
                        # automatically replaced by a future fresh install.
                    except Exception as exc:
                        delete_failures.append({
                            "name": entry["item"]["name"],
                            "path": entry["path"],
                            "error": str(exc),
                        })
                        kept_files.append(entry)

        # Steam-native removals intentionally keep a hidden `removed` tombstone
        # so late background workers cannot resurrect the game. The tombstone is
        # ignored by OneClick Tools and replaced automatically on reinstall.

        self.refresh_games()

        parts = []
        if count == 1 and removed:
            name = removed[0]["item"]["name"]
            if disconnected_external:
                parts.append(f"{name} was removed from Steam/library, but its external game files were NOT deleted because the drive was not connected.")
            elif deleted:
                parts.append(f"{name} was completely removed.")
            elif kept_files:
                parts.append(f"{name} was removed from Steam/library, but its game files were kept.")
            else:
                parts.append(f"{name} was removed.")
        else:
            parts.append(f"Removed {len(removed)}/{count} selected games from their libraries/Steam shortcuts.")
            if deleted:
                parts.append(f"Deleted game folders/prefixes for {len(deleted)} game(s).")
            if kept_files:
                parts.append(f"Kept game files for {len(kept_files)} game(s).")
            if disconnected_external:
                parts.append(f"External files for {len(disconnected_external)} game(s) were not touched because their drive was disconnected.")
        if cleanup_count:
            parts.append("Steam artwork/cache and compatibility leftovers were cleaned up.")
        if failed:
            parts.append(
                "Could not remove: "
                + " | ".join(f"{x['name']}: {x['error']}" for x in failed[:4])
                + (" …" if len(failed) > 4 else "")
            )
        if delete_failures:
            parts.append(
                "Could not delete folders: "
                + " | ".join(f"{x['name']}: {x['error']}" for x in delete_failures[:4])
            )
        self.set_status("\n".join(parts), success=bool(removed))



def run_background_artwork(game_id, supplied_name=""):
    """Silently fetch/apply artwork for a freshly installed game.

    This is intentionally UI-free. It uses the exact same official-Steam-first
    engine as the manual button and writes a short result to stdout/stderr so
    the host watcher log remains useful for diagnostics.
    """
    try:
        game = Game(str(game_id))
        if not game.id or not game.is_installed:
            raise RuntimeError("Lutris could not load the newly installed game.")
        if not steam_shortcut.shortcut_exists(game):
            raise RuntimeError("The Steam shortcut is not available yet.")

        config_path = steam_shortcut.get_config_path()
        if not config_path:
            raise RuntimeError("Steam's active user/config folder could not be found.")

        game_name = str(supplied_name or game.name or game.slug or "Installed game")
        api_key = load_sgdb_api_key()
        hints = []
        try:
            if getattr(game, "directory", None):
                dp = Path(str(game.directory))
                hints.extend([dp.name, dp.parent.name])
        except Exception:
            pass
        if getattr(game, "slug", None):
            hints.append(str(game.slug).replace("-", " "))
        result = download_and_apply_all_artwork(
            game_name,
            steam_shortcut.generate_appid(game),
            Path(config_path) / "grid",
            api_key,
            Path(resources.get_icon_path(game.slug)),
            hints,
        )
        print(json.dumps({
            "game": game_name,
            "applied": result.get("applied"),
            "downloaded": result.get("downloaded"),
            "reused": result.get("reused"),
            "providers": result.get("provider_counts"),
        }, sort_keys=True))
        return 0
    except Exception as exc:
        print(f"Background artwork failed for {supplied_name or game_id}: {exc}", file=sys.stderr)
        return 1



def run_background_steam_artwork(appid, supplied_name=""):
    try:
        config_path = steam_shortcut.get_config_path()
        if not config_path:
            raise RuntimeError("Steam's active user/config folder could not be found.")
        appid = int(appid)
        registry = load_steam_native_registry()
        entry = registry.get(str(appid)) or {}
        game_name = str(supplied_name or entry.get("name") or f"Steam game {appid}")
        api_key = load_sgdb_api_key()
        hints = []
        final_exe = str(entry.get("final_exe") or "")
        if final_exe:
            fp = Path(final_exe)
            hints.extend([fp.parent.name, fp.stem])
            if fp.parent.parent != fp.parent:
                hints.append(fp.parent.parent.name)
        result = download_and_apply_all_artwork(
            game_name,
            str(appid),
            Path(config_path) / "grid",
            api_key,
            None,
            hints,
        )
        if result.get("icon_path"):
            queue_steam_native_icon_refresh(appid, result["icon_path"])
        update_steam_native_registry(appid, artwork_pending=False)
        print(json.dumps({
            "game": game_name,
            "appid": appid,
            "applied": result.get("applied"),
            "downloaded": result.get("downloaded"),
            "reused": result.get("reused"),
            "providers": result.get("provider_counts"),
        }, sort_keys=True))
        return 0
    except Exception as exc:
        try:
            update_steam_native_registry(int(appid), artwork_pending=False)
        except Exception:
            pass
        print(f"Background Steam artwork failed for {supplied_name or appid}: {exc}", file=sys.stderr)
        return 1


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--background-artwork":
        if len(sys.argv) < 3:
            sys.exit(2)
        supplied_name = sys.argv[3] if len(sys.argv) >= 4 else ""
        sys.exit(run_background_artwork(sys.argv[2], supplied_name))

    if len(sys.argv) >= 2 and sys.argv[1] == "--background-steam-artwork":
        if len(sys.argv) < 3:
            sys.exit(2)
        supplied_name = sys.argv[3] if len(sys.argv) >= 4 else ""
        sys.exit(run_background_steam_artwork(sys.argv[2], supplied_name))

    win = OneClickTools()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
__TOOLS_GUI_4A91__

chmod +x "$TOOLS_GUI"

# Dedicated launcher for complete game removal. This is intentionally separate
# from the .exe file handler so KDE Plasma can index it as a normal application.
cat > "$REMOVE_HELPER" <<'__REMOVEHELPER_5D91__'
#!/usr/bin/env bash
exec "$HOME/.local/bin/lutris-exe-helper" remove
__REMOVEHELPER_5D91__
chmod +x "$REMOVE_HELPER"

cat > "$APP_DESKTOP" <<__APPDESKTOP_73A0__
[Desktop Entry]
Type=Application
Name=Moses OneClick Tool - Game Installer
Comment=Install Windows EXE games or mounted ISO installers through Steam Proton or Lutris
Icon=applications-games
Exec=$HELPER new %f
Terminal=false
NoDisplay=true
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;application/vnd.efi.iso;application/x-cd-image;application/x-iso9660-image;
Categories=Game;
StartupNotify=true
__APPDESKTOP_73A0__

cat > "$SERVICE_DESKTOP" <<__SERVICEMENU_D58F__
[Desktop Entry]
Type=Service
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;
Actions=lutrisExisting;oneclickDependency;
X-KDE-Priority=TopLevel

[Desktop Action lutrisExisting]
Name=Run as game update / patch
Icon=applications-games
Exec=$HELPER existing %f

[Desktop Action oneclickDependency]
Name=Run as game dependency
Icon=applications-system-symbolic
Exec=$HELPER dependency %f
__SERVICEMENU_D58F__

chmod +x "$SERVICE_DESKTOP"

cat > "$FOLDER_SERVICE_DESKTOP" <<__FOLDER_SERVICE_V68__
[Desktop Entry]
Type=Service
MimeType=inode/directory;
Actions=oneclickMoveAddExistingFolder;oneclickAddExistingFolder;
X-KDE-Priority=TopLevel

[Desktop Action oneclickMoveAddExistingFolder]
Name=Move to Game Folder + Add to Steam
Icon=folder-move-symbolic
Exec=$HELPER move-add-folder %f

[Desktop Action oneclickAddExistingFolder]
Name=Find Game EXE + Add to Steam
Icon=folder-symbolic
Exec=$HELPER add-folder %f
__FOLDER_SERVICE_V68__
chmod +x "$FOLDER_SERVICE_DESKTOP"

cat > "$FOLDER_INSTALL_SERVICE_DESKTOP" <<__FOLDER_INSTALL_SERVICE_V6711__
[Desktop Entry]
Type=Service
MimeType=inode/directory;
Actions=oneclickFindExeInstall;
X-KDE-Priority=TopLevel

[Desktop Action oneclickFindExeInstall]
Name=Find Game EXE + Install
Icon=system-run-symbolic
Exec=$HELPER find-install-folder %f
__FOLDER_INSTALL_SERVICE_V6711__
chmod +x "$FOLDER_INSTALL_SERVICE_DESKTOP"

# Remove legacy standalone launchers from older versions.
rm -f "$REMOVE_APP_DESKTOP" "$STEAM_REPAIR_DESKTOP" "$REMOVE_HELPER"

cat > "$TOOLS_DESKTOP" <<__TOOLS_DESKTOP_7B33__
[Desktop Entry]
Type=Application
Version=1.0
Name=Moses OneClick Tool
GenericName=Steam and Lutris Game Manager
Comment=Install and manage Windows games through Steam Proton or Lutris
Icon=applications-games
Exec=$HELPER tools $TOOLS_GUI
TryExec=$HELPER
Terminal=false
NoDisplay=false
Categories=Game;Utility;
Keywords=Steam;Proton;Lutris;SteamGridDB;Artwork;Shortcut;Repair;Remove;Uninstall;Games;
StartupNotify=true
X-KDE-StartupNotify=true
__TOOLS_DESKTOP_7B33__

chmod +x "$TOOLS_DESKTOP"
rm -f "$OLD_SERVICE"

remember_iso_handlers

for mime in \
  application/x-ms-dos-executable \
  application/x-msdownload \
  application/vnd.microsoft.portable-executable \
  application/vnd.efi.iso \
  application/x-cd-image \
  application/x-iso9660-image
do
  xdg-mime default lutris-exe-installer.desktop "$mime" || true
done

refresh_kde

echo
echo "============================================================"
echo " Moses OneClick Tool V${ONECLICK_VERSION} installed successfully!"
echo "============================================================"
echo
echo "NEW GAME:"
echo "  Double-click any .exe OR .iso -> Moses OneClick Tool - Game Installer"
echo "  Default backend: Steam / Proton (Smart Automatic / Lutris and manual Lutris are optional per install)."
echo "  Steam backend launches the installer directly with Proton Experimental"
echo "  inside the exact Steam compatdata prefix reserved for the final game shortcut."
echo "  Steam stays open during normal installation. Standard double-click installs defer final shortcut integration until your next manual Steam close/restart or Return to Gaming Mode."
echo "  StreamExtract ISO installs use the reliable close/write/verify/reopen shortcut commit after setup finishes, so the ISO pipeline can complete automatically."
echo "  Failed new Steam installs are cleaned automatically, detailed Proton logs are kept, and Lutris + System Wine 11.0 is offered as a fallback."
echo "  Artwork is downloaded/applied automatically in the background."
echo "  After install, change Proton normally from Steam Properties -> Compatibility."
echo
echo "SMART DOUBLE-CLICK:"
echo "  Double-click any .exe -> choose Install, Update existing game, or Add existing game to Steam (no install)."
echo "  Double-click any .iso -> mount it read-only, find the installer EXE, and open the same Game Installer automatically."
echo "  Update/patch filenames are detected and preselected automatically."
echo
echo "EXISTING GAME FOLDER:"
echo "  Right-click a folder -> Move to Game Folder + Add to Steam"
echo "  Right-click a folder -> Find Game EXE + Add to Steam"
echo "  Right-click a folder -> Find Game EXE + Install"
echo "  The first creates a shortcut directly; the second scans for EXEs and then opens the normal One-Click Install / Update / Add Existing dialog."
echo
echo "UPDATE / PATCH:"
echo "  Right-click update.exe -> Run as game update / patch"
echo "  Right-click redistributable.exe -> Run as game dependency"
echo "  Steam backend runs the updater directly in the SAME Steam Proton prefix without restarting Steam; Lutris backend uses the Lutris prefix."
echo
echo "ONE-CLICK TOOLS:"
echo "  Application Launcher -> Moses OneClick Tool"
echo "  One clean native KDE-framed window for:"
echo "    - Install Game"
echo "    - Settings: Steam (default), Smart Automatic / Lutris, or manual Lutris + Artwork Source (Both default / Steam / SteamGridDB) + API key"
echo "    - Re-select Main EXE icon for Steam installs where the chooser appeared during installation"
echo "    - Repair Steam Shortcut (Steam-native + Lutris)"
echo "    - Install / Repair Dependencies (per-game prefix + shared installer cache)"
echo "    - Download + Apply All Artworks (Both/Steam/SteamGridDB selectable; Both defaults to Steam first + SteamGridDB fallback, multi-select; also automatic after install)"
echo "    - Small folder button opens Steam custom artwork folder"
echo "    - Complete Game Removal (Steam-native + Lutris; single, multiple, or All)"
echo "    - StreamExtract v1.14 integrated with Internal / External Moses storage
    - Completed StreamExtract games flow into EXE selection, Steam shortcut and artwork automatically
    - Installer ISOs are detected automatically, mounted read-only, and handed to the normal Game Installer without extracting the ISO
    - TempOverlay integrated into the main window"
echo "    - Restart Steam bypasses SteamOS' forced PipeWire capture prompt and reopens the client"
echo "  The window stays open after removal so you can continue managing games."
echo
echo "Close all Dolphin windows and open Dolphin again once."
echo
echo "To remove this integration later:"
echo "  bash \"$0\" --uninstall"
echo
