#!/usr/bin/env bash
#
# Developer GRUB theme installer (Fedora)
#   sudo ./install.sh                      install the theme
#   sudo ./install.sh --enable-os-prober   also show Windows in the menu
#   sudo ./install.sh --uninstall          restore the backups
#
set -euo pipefail

THEME_NAME="developer-grub"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fedora keeps GRUB in /boot/grub2 (other distros use /boot/grub)
if [[ -d /boot/grub2 ]]; then GRUB_DIR="/boot/grub2"; else GRUB_DIR="/boot/grub"; fi
DEST_DIR="${GRUB_DIR}/themes/${THEME_NAME}"
GRUB_DEFAULT="/etc/default/grub"
GRUB_CFG="${GRUB_DIR}/grub.cfg"
BACKUP_SUFFIX=".${THEME_NAME}.backup"

MKCONFIG="$(command -v grub2-mkconfig || command -v grub-mkconfig || true)"
MKFONT="$(command -v grub2-mkfont || command -v grub-mkfont || true)"

ENABLE_OS_PROBER=0
UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --enable-os-prober) ENABLE_OS_PROBER=1 ;;
        --uninstall)        UNINSTALL=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

echo "========================================"
echo " Developer GRUB Theme Installer"
echo "========================================"
echo

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script with sudo:  sudo ./install.sh"
    exit 1
fi
[[ -n "$MKCONFIG" ]] || { echo "ERROR: grub2-mkconfig not found."; exit 1; }

# ------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------
if [[ $UNINSTALL -eq 1 ]]; then
    if [[ -f "${GRUB_DEFAULT}${BACKUP_SUFFIX}" ]]; then
        cp "${GRUB_DEFAULT}${BACKUP_SUFFIX}" "$GRUB_DEFAULT"
        echo "Restored $GRUB_DEFAULT"
    else
        echo "No backup of $GRUB_DEFAULT found."
    fi
    rm -rf "$DEST_DIR"
    "$MKCONFIG" -o "$GRUB_CFG"
    echo "Theme removed."
    exit 0
fi

# ------------------------------------------------------------
# Check files
# ------------------------------------------------------------
for f in background.png theme.txt select_c.png select_w.png select_e.png icons; do
    [[ -e "$SRC_DIR/$f" ]] || { echo "ERROR: $f not found next to install.sh."; exit 1; }
done

# Font used by the theme (DejaVu Sans Mono Bold ships with Fedora)
TTF=""
for p in /usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono-Bold.ttf \
         /usr/share/fonts/dejavu/DejaVuSansMono-Bold.ttf \
         /usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf; do
    [[ -f "$p" ]] && { TTF="$p"; break; }
done
if [[ -z "$TTF" ]]; then
    TTF="$(fc-list : file family style 2>/dev/null | grep -i 'DejaVu Sans Mono' | grep -i bold | head -1 | cut -d: -f1 || true)"
fi
if [[ -z "$TTF" || -z "$MKFONT" ]]; then
    echo "ERROR: need grub2-mkfont and DejaVu Sans Mono Bold."
    echo "       sudo dnf install dejavu-sans-mono-fonts grub2-tools-extra"
    exit 1
fi

# ------------------------------------------------------------
# Backup (only the first time, so the original is never lost)
# ------------------------------------------------------------
echo "[1/5] Creating backups..."
[[ -f "${GRUB_DEFAULT}${BACKUP_SUFFIX}" ]] || cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}${BACKUP_SUFFIX}"
if [[ -f "$GRUB_CFG" && ! -f "${GRUB_CFG}${BACKUP_SUFFIX}" ]]; then
    cp "$GRUB_CFG" "${GRUB_CFG}${BACKUP_SUFFIX}"
fi
echo "      Backups ready."

# ------------------------------------------------------------
# Install theme + fonts
# ------------------------------------------------------------
echo "[2/5] Installing theme to $DEST_DIR ..."
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR/icons"
cp "$SRC_DIR"/background.png "$SRC_DIR"/theme.txt "$SRC_DIR"/select_*.png "$DEST_DIR/"
cp "$SRC_DIR"/icons/*.png "$DEST_DIR/icons/"

for size in 16 22 30; do
    PF2="$DEST_DIR/devmono-${size}.pf2"
    "$MKFONT" -s "$size" -n DevMono -o "$PF2" "$TTF"
    # Make sure theme.txt uses the exact name stored in the font file
    actual="$(grep -a -o -E 'DevMono [A-Za-z ]+ [0-9]+' "$PF2" | head -1 || true)"
    wanted="DevMono Bold ${size}"
    if [[ -n "$actual" && "$actual" != "$wanted" ]]; then
        sed -i "s|${wanted}|${actual}|g" "$DEST_DIR/theme.txt"
    fi
done
echo "      Theme and fonts installed."

# ------------------------------------------------------------
# Configure /etc/default/grub
# ------------------------------------------------------------
echo "[3/5] Configuring GRUB..."

set_var() {   # set_var NAME VALUE  -> NAME="VALUE" (replace or append)
    local name="$1" value="$2"
    if grep -q "^${name}=" "$GRUB_DEFAULT"; then
        sed -i "s|^${name}=.*|${name}=\"${value}\"|" "$GRUB_DEFAULT"
    else
        echo "${name}=\"${value}\"" >> "$GRUB_DEFAULT"
    fi
}

set_var GRUB_THEME           "${DEST_DIR}/theme.txt"
set_var GRUB_GFXMODE         "1920x1080,auto"
set_var GRUB_GFXPAYLOAD_LINUX "keep"
set_var GRUB_TERMINAL_OUTPUT "gfxterm"
set_var GRUB_TIMEOUT_STYLE   "menu"
set_var GRUB_TIMEOUT         "5"
if [[ $ENABLE_OS_PROBER -eq 1 ]]; then
    set_var GRUB_DISABLE_OS_PROBER "false"
fi
echo "      /etc/default/grub updated."

# ------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------
echo "[4/5] Generating GRUB configuration..."
"$MKCONFIG" -o "$GRUB_CFG"

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------
echo "[5/5] Verifying..."
ok=1
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; ok=0; fi; }
check "GRUB_THEME set"       "grep -q '^GRUB_THEME=.*${THEME_NAME}/theme.txt' '$GRUB_DEFAULT'"
check "theme.txt installed"  "[[ -f '$DEST_DIR/theme.txt' ]]"
check "background installed" "[[ -f '$DEST_DIR/background.png' ]]"
check "fonts installed"      "[[ -f '$DEST_DIR/devmono-30.pf2' ]]"
check "theme in grub.cfg"    "grep -q '${THEME_NAME}' '$GRUB_CFG'"
[[ $ok -eq 1 ]] || { echo "Something failed - see above."; exit 1; }

echo
echo "Developer GRUB installed. No reboot was performed."
echo "To undo:  sudo ./install.sh --uninstall"
