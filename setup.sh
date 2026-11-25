#!/usr/bin/env bash
# ==============================================================================
# rtl8852cu-9M2PJU-dkms - Interactive One-Liner Installer
# Repository: https://github.com/9M2PJU/rtl8852cu-9M2PJU-dkms
# Maintainer: 9M2PJU (https://hamradio.my)
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/9M2PJU/rtl8852cu-9M2PJU-dkms/main/setup.sh)
#   # or:
#   curl -fsSL https://raw.githubusercontent.com/9M2PJU/rtl8852cu-9M2PJU-dkms/main/setup.sh | bash
# ==============================================================================

set -euo pipefail

REPO_URL="https://github.com/9M2PJU/rtl8852cu-9M2PJU-dkms.git"
AUR_PKG="rtl8852cu-9m2pju-dkms-git"
DEFAULT_SRC_DIR="${HOME}/src/rtl8852cu-9M2PJU-dkms"
BLACKLIST_FILE="/etc/modprobe.d/blacklist-rtw89-8852cu.conf"
MODOPT_FILE="/etc/modprobe.d/8852cu.conf"

# --- Colors & UI Helpers ------------------------------------------------------
if [ -t 1 ] || [ -e /dev/tty ]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    CYAN='\033[1;36m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    RED='\033[1;31m'
    RESET='\033[0m'
else
    BOLD='' DIM='' CYAN='' GREEN='' YELLOW='' RED='' RESET=''
fi

info()    { printf "${CYAN}ℹ${RESET}  %b\n" "$*"; }
ok()      { printf "${GREEN}✓${RESET}  %b\n" "$*"; }
warn()    { printf "${YELLOW}⚠${RESET}  %b\n" "$*"; }
err()     { printf "${RED}✖${RESET}  %b\n" "$*" >&2; }

# Always read interactive answers from /dev/tty so `curl ... | bash` works!
prompt_yn() {
    local question="$1" default="${2:-y}" answer hint
    if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    while true; do
        printf "${BOLD}?${RESET}  %s ${DIM}%s${RESET} " "$question" "$hint" > /dev/tty
        IFS= read -r answer < /dev/tty || answer=""
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     printf "   Please answer y or n.\n" > /dev/tty ;;
        esac
    done
}

prompt_choice() {
    local prompt_text="$1" default="$2" max="$3" answer
    while true; do
        printf "${BOLD}?${RESET}  %s ${DIM}[default: %s]${RESET} " "$prompt_text" "$default" > /dev/tty
        IFS= read -r answer < /dev/tty || answer=""
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "$max" ]; then
            printf '%s\n' "$answer"
            return 0
        fi
        printf "   Please enter a number between 1 and %s.\n" "$max" > /dev/tty
    done
}

# --- Banner & System Detection ------------------------------------------------
printf "\n${CYAN}╭──────────────────────────────────────────────────────────────╮${RESET}\n"
printf "${CYAN}│${RESET}  ${BOLD}📡 rtl8852cu-9M2PJU-dkms - Interactive Linux Installer${RESET}      ${CYAN}│${RESET}\n"
printf "${CYAN}│${RESET}  ${DIM}Realtek RTL8832CU / RTL8852CU • Linux 5.15-7.3+ • GCC/LLVM${RESET}  ${CYAN}│${RESET}\n"
printf "${CYAN}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"

if [ ! -e /dev/tty ]; then
    err "No interactive terminal (/dev/tty) available. Run from an interactive shell."
    exit 1
fi

KERNEL_VER="$(uname -r)"
ARCH="$(uname -m)"
DISTRO_ID="unknown"
DISTRO_LIKE=""
DISTRO_NAME="Unknown Linux"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
fi

COMPILER_MODE="GCC"
KSRC="/lib/modules/${KERNEL_VER}/build"
if { [ -r "${KSRC}/.config" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "${KSRC}/.config"; } || \
   { [ -r "${KSRC}/include/config/auto.conf" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "${KSRC}/include/config/auto.conf"; }; then
    COMPILER_MODE="Clang/LLVM (LLVM=1 auto-detected)"
fi

IS_ARCH=0
if [[ "$DISTRO_ID" =~ ^(arch|cachyos|endeavouros|manjaro|garuda)$ ]] || [[ "$DISTRO_LIKE" == *arch* ]]; then
    IS_ARCH=1
fi

AUR_HELPER=""
for h in yay paru; do
    if command -v "$h" >/dev/null 2>&1; then
        AUR_HELPER="$h"
        break
    fi
done

USB_FOUND="None detected right now (plug in anytime)"
if command -v lsusb >/dev/null 2>&1; then
    matched="$(lsusb | grep -iE '0bda:c832|0bda:c85a|0bda:c85d|0db0:991d|35b2:0502|35bc:0101|35bc:0102' || true)"
    if [ -n "$matched" ]; then
        USB_FOUND="$(printf '%s' "$matched" | head -n 1)"
    fi
fi

info "System detected:"
printf "   ├─ Distro   : ${BOLD}%s${RESET}\n" "$DISTRO_NAME"
printf "   ├─ Kernel   : ${BOLD}%s${RESET} (%s)\n" "$KERNEL_VER" "$ARCH"
printf "   ├─ Compiler : ${BOLD}%s${RESET}\n" "$COMPILER_MODE"
printf "   └─ Adapter  : ${BOLD}%s${RESET}\n\n" "$USB_FOUND"

# Ensure sudo access upfront
if [ "${EUID}" -ne 0 ]; then
    info "This installer needs sudo privileges for package/DKMS/modprobe setup."
    sudo -v < /dev/tty
fi

# --- Interactive Questions ----------------------------------------------------
printf "${BOLD}Step 1/4 - Choose Action & Installation Method${RESET}\n"
if [ "$IS_ARCH" -eq 1 ] && [ -n "$AUR_HELPER" ]; then
    printf "   1) Install / Upgrade via AUR (${BOLD}%s -S %s${RESET}) [Recommended for Arch/CachyOS]\n" "$AUR_HELPER" "$AUR_PKG"
    printf "   2) Install / Upgrade from GitHub via DKMS (${BOLD}install-driver.sh${RESET})\n"
    printf "   3) Configure USB mode / blacklist only (driver already installed)\n"
    printf "   4) Uninstall rtl8852cu driver\n"
    ACTION="$(prompt_choice "Select an option (1-4):" "1" "4")"
else
    printf "   1) Install / Upgrade from GitHub via DKMS (${BOLD}install-driver.sh${RESET}) [Recommended]\n"
    printf "   2) Configure USB mode / blacklist only (driver already installed)\n"
    printf "   3) Uninstall rtl8852cu driver\n"
    raw_action="$(prompt_choice "Select an option (1-3):" "1" "3")"
    case "$raw_action" in
        1) ACTION=2 ;;
        2) ACTION=3 ;;
        3) ACTION=4 ;;
    esac
fi

# Handle uninstall immediately
if [ "$ACTION" -eq 4 ]; then
    printf "\n"
    if prompt_yn "Remove rtl8852cu driver and DKMS module?" "n"; then
        if [ "$IS_ARCH" -eq 1 ] && pacman -Qi "$AUR_PKG" >/dev/null 2>&1; then
            sudo pacman -Rns "$AUR_PKG"
        elif [ -x "${DEFAULT_SRC_DIR}/uninstall-driver.sh" ]; then
            (cd "${DEFAULT_SRC_DIR}" && sudo ./uninstall-driver.sh NoPrompt)
        else
            warn "No package or ${DEFAULT_SRC_DIR}/uninstall-driver.sh found. Checking DKMS directly..."
            while IFS=',' read -r mod_ver _; do
                mod_ver="$(echo "$mod_ver" | xargs)"
                [ -n "$mod_ver" ] && sudo dkms remove "$mod_ver" --all || true
            done < <(dkms status rtl8852cu 2>/dev/null || true)
        fi
        if [ -f "$BLACKLIST_FILE" ] && prompt_yn "Also remove ${BLACKLIST_FILE} (re-enable in-kernel rtw89_8852cu)?" "y"; then
            sudo rm -f "$BLACKLIST_FILE"
            ok "Removed ${BLACKLIST_FILE}"
        fi
        ok "Uninstall complete!"
    else
        info "Cancelled."
    fi
    exit 0
fi

printf "\n${BOLD}Step 2/4 - USB Speed Mode (rtw_switch_usb_mode)${RESET}\n"
printf "   1) ${BOLD}USB 3.0 SuperSpeed (5000M)${RESET} - Best throughput & lowest latency (Recommended for USB 3 ports)\n"
printf "   2) ${BOLD}USB 2.0 High-Speed (480M)${RESET}  - Maximum compatibility on noisy hubs or USB 2 ports\n"
printf "   3) Keep existing ${MODOPT_FILE} unchanged\n"
USB_CHOICE="$(prompt_choice "Select USB mode (1-3):" "1" "3")"

printf "\n${BOLD}Step 3/4 - In-Kernel Driver Conflict Prevention${RESET}\n"
DO_BLACKLIST=0
if prompt_yn "Blacklist in-kernel 'rtw89_8852cu' so '8852cu' binds cleanly?" "y"; then
    DO_BLACKLIST=1
fi

DO_DEPS=0
SRC_DIR="$DEFAULT_SRC_DIR"
if [ "$ACTION" -eq 2 ]; then
    printf "\n${BOLD}Step 4/4 - Build Dependencies & Source Directory${RESET}\n"
    if prompt_yn "Install/verify required build packages (dkms, git, bc, kernel headers)?" "y"; then
        DO_DEPS=1
    fi
    printf "${BOLD}?${RESET}  Clone directory ${DIM}[default: %s]${RESET} " "$DEFAULT_SRC_DIR" > /dev/tty
    IFS= read -r custom_dir < /dev/tty || custom_dir=""
    SRC_DIR="${custom_dir:-$DEFAULT_SRC_DIR}"
else
    printf "\n${BOLD}Step 4/4 - Confirm Summary${RESET}\n"
fi

# --- Summary & Confirmation ---------------------------------------------------
printf "\n${CYAN}┌─ Summary ───────────────────────────────────────────────────┐${RESET}\n"
case "$ACTION" in
    1) printf "│  Install method : AUR (%s -S %s)\n" "$AUR_HELPER" "$AUR_PKG" ;;
    2) printf "│  Install method : GitHub DKMS (%s)\n" "$SRC_DIR" ;;
    3) printf "│  Install method : Config-only (skip driver build)\n" ;;
esac
case "$USB_CHOICE" in
    1) printf "│  USB mode       : USB 3.0 SuperSpeed (rtw_switch_usb_mode=1)\n" ;;
    2) printf "│  USB mode       : USB 2.0 High-Speed (rtw_switch_usb_mode=0)\n" ;;
    3) printf "│  USB mode       : Keep existing\n" ;;
esac
printf "│  Blacklist rtw89: %s\n" "$([ "$DO_BLACKLIST" -eq 1 ] && echo "Yes (${BLACKLIST_FILE})" || echo "No")"
printf "${CYAN}└─────────────────────────────────────────────────────────────┘${RESET}\n\n"

if ! prompt_yn "Proceed now?" "y"; then
    info "Aborted by user. No changes were made."
    exit 0
fi

# --- Execute ------------------------------------------------------------------
install_deps() {
    info "Installing build dependencies for ${DISTRO_ID}..."
    if [ "$IS_ARCH" -eq 1 ]; then
        local hdr="linux-headers"
        case "$KERNEL_VER" in
            *cachyos-lts*) hdr="linux-cachyos-lts-headers" ;;
            *cachyos*)     hdr="linux-cachyos-headers" ;;
            *lts*)         hdr="linux-lts-headers" ;;
            *zen*)         hdr="linux-zen-headers" ;;
            *hardened*)    hdr="linux-hardened-headers" ;;
        esac
        sudo pacman -S --needed --noconfirm "$hdr" dkms git bc iw
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "linux-headers-${KERNEL_VER}" build-essential bc dkms git libelf-dev rfkill iw
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git dkms kernel-devel bc openssl
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y -t pattern devel_kernel
        sudo zypper install -y dkms git bc
    else
        warn "Unrecognized package manager - ensure kernel headers, dkms, git, bc, and your compiler are installed."
    fi
}

if [ "$ACTION" -eq 1 ]; then
    info "Installing ${AUR_PKG} via ${AUR_HELPER}..."
    "$AUR_HELPER" -S --needed "$AUR_PKG" < /dev/tty
    ok "AUR package ${AUR_PKG} installed."
elif [ "$ACTION" -eq 2 ]; then
    [ "$DO_DEPS" -eq 1 ] && install_deps
    mkdir -p "$(dirname "$SRC_DIR")"
    if [ -d "${SRC_DIR}/.git" ]; then
        info "Updating existing clone in ${SRC_DIR}..."
        git -C "$SRC_DIR" pull --ff-only
    else
        info "Cloning ${REPO_URL} into ${SRC_DIR}..."
        git clone "$REPO_URL" "$SRC_DIR"
    fi
    info "Building and installing DKMS module (this may take a few minutes)..."
    (cd "$SRC_DIR" && sudo ./install-driver.sh NoPrompt)
    ok "DKMS driver built and installed."
fi

if [ "$DO_BLACKLIST" -eq 1 ]; then
    printf "# Managed by rtl8852cu-9M2PJU-dkms installer\nblacklist rtw89_8852cu\n" | sudo tee "$BLACKLIST_FILE" >/dev/null
    ok "Blacklisted in-kernel rtw89_8852cu (${BLACKLIST_FILE})"
fi

if [ "$USB_CHOICE" -eq 1 ] || [ "$USB_CHOICE" -eq 2 ]; then
    mode_val=$([ "$USB_CHOICE" -eq 1 ] && echo "1" || echo "0")
    if [ -f "$MODOPT_FILE" ] && grep -q '^options 8852cu ' "$MODOPT_FILE"; then
        if grep -q 'rtw_switch_usb_mode=' "$MODOPT_FILE"; then
            sudo sed -i "s/rtw_switch_usb_mode=[0-9]/rtw_switch_usb_mode=${mode_val}/" "$MODOPT_FILE"
        else
            sudo sed -i "s/^options 8852cu /&rtw_switch_usb_mode=${mode_val} /" "$MODOPT_FILE"
        fi
    else
        printf "# Managed by rtl8852cu-9M2PJU-dkms installer\noptions 8852cu rtw_switch_usb_mode=%s\n" "$mode_val" | sudo tee "$MODOPT_FILE" >/dev/null
    fi
    ok "Set rtw_switch_usb_mode=${mode_val} in ${MODOPT_FILE}"
fi

printf "\n"
if prompt_yn "Reload the 8852cu kernel module now (no reboot needed)?" "y"; then
    sudo modprobe -r rtw89_8852cu 2>/dev/null || true
    sudo modprobe -r 8852cu 2>/dev/null || true
    sudo modprobe 8852cu
    ok "8852cu module loaded!"
    if command -v dkms >/dev/null 2>&1; then
        dkms status rtl8852cu || true
    fi
else
    info "Skipped module reload - reboot or replug your USB WiFi adapter to activate."
fi

printf "\n${GREEN}${BOLD}All done!${RESET} 73 de 9M2PJU 📻  ${DIM}https://github.com/9M2PJU/rtl8852cu-9M2PJU-dkms${RESET}\n\n"
