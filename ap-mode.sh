#!/usr/bin/env bash
# ==============================================================================
# rtl8852cu-9M2PJU-dkms - Interactive Wi-Fi 6 / 5 GHz / 2.4 GHz AP Mode Script
# Repository: https://github.com/9M2PJU/rtl8852cu-9M2PJU-dkms
# Maintainer: 9M2PJU (https://hamradio.my)
#
# Supports:
#   - Mode A: hostapd + dnsmasq + NAT (Full Wi-Fi 6 / 80 MHz / 160 MHz AP)
#   - Mode B: NetworkManager hotspot (Zero extra packages, quick WPA2/WPA3 AP)
#
# Usage:
#   sudo ./ap-mode.sh          # Interactive setup wizard
#   sudo ./ap-mode.sh --stop   # Stop any running AP & restore interface
#   sudo ./ap-mode.sh --status # Show active AP status & connected clients
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/9M2PJU/rtl8852cu-9M2PJU-dkms/main/ap-mode.sh | sudo bash
# ==============================================================================

set -euo pipefail

STATE_DIR="/run/rtl8852cu-ap"
MODOPT_FILE="/etc/modprobe.d/8852cu.conf"
NM_CON_NAME="rtl8852cu-AP"

# --- Colors & UI --------------------------------------------------------------
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

info() { printf "${CYAN}ℹ${RESET}  %b\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET}  %b\n" "$*"; }
warn() { printf "${YELLOW}⚠${RESET}  %b\n" "$*"; }
err()  { printf "${RED}✖${RESET}  %b\n" "$*" >&2; }

need_root() {
    if [ "${EUID}" -ne 0 ]; then
        err "Please run as root (e.g., sudo $0)"
        exit 1
    fi
}

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

prompt_str() {
    local question="$1" default="$2" answer
    printf "${BOLD}?${RESET}  %s ${DIM}[default: %s]${RESET} " "$question" "$default" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    printf '%s\n' "${answer:-$default}"
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

detect_8852cu_iface() {
    local i drv
    for i in /sys/class/net/wl*; do
        [ -e "$i" ] || continue
        drv="$(basename "$(readlink -f "$i/device/driver" 2>/dev/null || true)")"
        case "$drv" in
            rtl8852cu|8852cu|rtw89_8852cu)
                basename "$i"
                return 0
                ;;
        esac
    done
    return 1
}

detect_default_upstream() {
    ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

# --- Stop / Cleanup -----------------------------------------------------------
stop_ap() {
    need_root
    local iface="" upstream="" mode=""
    if [ -f "${STATE_DIR}/state.env" ]; then
        # shellcheck disable=SC1091
        . "${STATE_DIR}/state.env" || true
    fi

    if [ "$mode" = "nmcli" ] || nmcli -t -f NAME con show --active 2>/dev/null | grep -qx "$NM_CON_NAME"; then
        info "Stopping NetworkManager hotspot (${NM_CON_NAME})..."
        nmcli con down "$NM_CON_NAME" >/dev/null 2>&1 || true
        nmcli con delete "$NM_CON_NAME" >/dev/null 2>&1 || true
        ok "NetworkManager hotspot stopped."
    fi

    if [ -f "${STATE_DIR}/hostapd.pid" ]; then
        kill "$(cat "${STATE_DIR}/hostapd.pid")" 2>/dev/null || true
    fi
    if [ -f "${STATE_DIR}/dnsmasq.pid" ]; then
        kill "$(cat "${STATE_DIR}/dnsmasq.pid")" 2>/dev/null || true
    fi

    # Remove NAT rules if created by this script
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet rtl8852cu_ap 2>/dev/null || true
    fi
    if [ -n "$iface" ] && [ -n "$upstream" ] && command -v iptables >/dev/null 2>&1; then
        iptables -t nat -D POSTROUTING -o "$upstream" -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -i "$iface" -o "$upstream" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i "$upstream" -o "$iface" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    fi

    if [ -n "$iface" ]; then
        ip addr flush dev "$iface" 2>/dev/null || true
        ip link set "$iface" down 2>/dev/null || true
        iw dev "$iface" set type managed 2>/dev/null || true
        ip link set "$iface" up 2>/dev/null || true
        if command -v nmcli >/dev/null 2>&1; then
            nmcli dev set "$iface" managed yes >/dev/null 2>&1 || true
        fi
        ok "Restored ${iface} to managed (client) mode."
    fi

    rm -rf "$STATE_DIR"
    ok "AP mode stopped cleanly."
}

show_status() {
    printf "\n${CYAN}╭─ 📡 RTL8852CU AP STATUS ─────────────────────────────────────╮${RESET}\n"
    if [ -f "${STATE_DIR}/state.env" ]; then
        # shellcheck disable=SC1091
        . "${STATE_DIR}/state.env"
        printf "${CYAN}│${RESET}  State     : ${GREEN}ACTIVE${RESET} (mode: %s)\n" "${mode:-unknown}"
        printf "${CYAN}│${RESET}  Interface : ${BOLD}%s${RESET} (%s)\n" "${iface:-?}" "${ap_ip:-10.42.88.1/24}"
        printf "${CYAN}│${RESET}  SSID      : ${BOLD}%s${RESET} (band: %s, ch: %s)\n" "${ssid:-?}" "${band_label:-?}" "${channel:-?}"
        printf "${CYAN}│${RESET}  Upstream  : %s\n" "${upstream:-none (local-only)}"
        printf "${CYAN}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"
        if [ -n "${iface:-}" ] && command -v iw >/dev/null 2>&1; then
            info "Connected clients on ${iface}:"
            iw dev "$iface" station dump | grep -E "^Station|signal:|rx bitrate:|tx bitrate:" || printf "   (none connected yet)\n"
        fi
    else
        printf "${CYAN}│${RESET}  State     : ${DIM}INACTIVE${RESET}\n"
        printf "${CYAN}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"
    fi
}

case "${1:-}" in
    --stop|-s)   stop_ap; exit 0 ;;
    --status|-i) show_status; exit 0 ;;
    --help|-h)
        printf "Usage: sudo %s [--stop | --status | --help]\n" "$0"
        exit 0
        ;;
esac

# --- Interactive Setup Wizard -------------------------------------------------
need_root

if [ ! -e /dev/tty ]; then
    err "No interactive terminal (/dev/tty) available."
    exit 1
fi

printf "\n${CYAN}╭──────────────────────────────────────────────────────────────╮${RESET}\n"
printf "${CYAN}│${RESET}  ${BOLD}📡 rtl8852cu-9M2PJU-dkms - Interactive AP / Hotspot Wizard${RESET}  ${CYAN}│${RESET}\n"
printf "${CYAN}│${RESET}  ${DIM}Wi-Fi 6 (802.11ax) • 5 GHz / 2.4 GHz • NAT Internet Sharing${RESET} ${CYAN}│${RESET}\n"
printf "${CYAN}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"

# 1. Detect Wi-Fi adapter
DEFAULT_IFACE="$(detect_8852cu_iface || true)"
if [ -z "$DEFAULT_IFACE" ]; then
    warn "No rtl8852cu/8852cu interface detected automatically."
    info "Available wireless interfaces:"
    iw dev 2>/dev/null | awk '/Interface/{print "   - " $2}' || true
    DEFAULT_IFACE="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}' || echo "wlan1")"
else
    ok "Detected Realtek 8852CU adapter: ${BOLD}${DEFAULT_IFACE}${RESET}"
fi

# Check module AP capabilities (rtw_he_enable=2 rtw_vht_enable=2 needed for Wi-Fi 6 / VHT AP)
HE_PARAM="$(cat /sys/module/8852cu/parameters/rtw_he_enable 2>/dev/null || echo "")"
VHT_PARAM="$(cat /sys/module/8852cu/parameters/rtw_vht_enable 2>/dev/null || echo "")"
if [ -n "$HE_PARAM" ] && { [ "$HE_PARAM" != "2" ] || [ "$VHT_PARAM" != "2" ]; }; then
    warn "Current 8852cu params: rtw_he_enable=${HE_PARAM}, rtw_vht_enable=${VHT_PARAM}"
    info "For full Wi-Fi 6 (HE) + 80/160 MHz (VHT) AP mode, Realtek requires rtw_he_enable=2 rtw_vht_enable=2."
    if prompt_yn "Enable rtw_he_enable=2 rtw_vht_enable=2 in ${MODOPT_FILE} and reload 8852cu now?" "y"; then
        if [ -f "$MODOPT_FILE" ] && grep -q '^options 8852cu ' "$MODOPT_FILE"; then
            for kv in "rtw_he_enable=2" "rtw_vht_enable=2"; do
                k="${kv%%=*}"
                if grep -q "${k}=" "$MODOPT_FILE"; then
                    sed -i "s/${k}=[0-9]/${kv}/" "$MODOPT_FILE"
                else
                    sed -i "s/^options 8852cu .*/& ${kv}/" "$MODOPT_FILE"
                fi
            done
        else
            printf "options 8852cu rtw_switch_usb_mode=1 rtw_he_enable=2 rtw_vht_enable=2\n" > "$MODOPT_FILE"
        fi
        modprobe -r 8852cu 2>/dev/null || true
        modprobe 8852cu
        sleep 3
        DEFAULT_IFACE="$(detect_8852cu_iface || echo "$DEFAULT_IFACE")"
        ok "Reloaded 8852cu with full Wi-Fi 6 AP parameters on ${DEFAULT_IFACE}."
    fi
fi

printf "\n${BOLD}Step 1/6 - Interface & Backend${RESET}\n"
AP_IFACE="$(prompt_str "AP wireless interface:" "$DEFAULT_IFACE")"

HAS_HOSTAPD=0
HAS_DNSMASQ=0
HAS_NMCLI=0
command -v hostapd >/dev/null 2>&1 && HAS_HOSTAPD=1
command -v dnsmasq >/dev/null 2>&1 && HAS_DNSMASQ=1
command -v nmcli   >/dev/null 2>&1 && HAS_NMCLI=1

printf "   1) ${BOLD}hostapd + dnsmasq${RESET} - Full Wi-Fi 6 (802.11ax), 80 MHz, WPA2/WPA3 %s\n" \
    "$([ "$HAS_HOSTAPD" -eq 1 ] && [ "$HAS_DNSMASQ" -eq 1 ] && echo "[Ready]" || echo "[Requires hostapd + dnsmasq]")"
printf "   2) ${BOLD}NetworkManager (nmcli)${RESET} - Quick hotspot, zero extra config %s\n" \
    "$([ "$HAS_NMCLI" -eq 1 ] && echo "[Ready]" || echo "[nmcli not found]")"
DEFAULT_BACKEND="$( [ "$HAS_HOSTAPD" -eq 1 ] && [ "$HAS_DNSMASQ" -eq 1 ] && echo 1 || echo 2 )"
BACKEND_CHOICE="$(prompt_choice "Select AP backend (1-2):" "$DEFAULT_BACKEND" "2")"

if [ "$BACKEND_CHOICE" -eq 1 ] && { [ "$HAS_HOSTAPD" -eq 0 ] || [ "$HAS_DNSMASQ" -eq 0 ]; }; then
    warn "hostapd and/or dnsmasq not installed."
    if prompt_yn "Install hostapd & dnsmasq automatically?" "y"; then
        if command -v pacman >/dev/null 2>&1; then
            pacman -S --needed --noconfirm hostapd dnsmasq
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y hostapd dnsmasq
            systemctl stop hostapd dnsmasq 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y hostapd dnsmasq
        else
            err "Please install 'hostapd' and 'dnsmasq' manually, then re-run."
            exit 1
        fi
    else
        err "Cannot run hostapd backend without hostapd + dnsmasq."
        exit 1
    fi
fi

printf "\n${BOLD}Step 2/6 - Network Name (SSID) & Password${RESET}\n"
AP_SSID="$(prompt_str "Wi-Fi SSID:" "9M2PJU-AX-AP")"
while true; do
    AP_PASS="$(prompt_str "WPA2/WPA3 Password (8-63 chars):" "9m2pju1234")"
    if [ "${#AP_PASS}" -ge 8 ] && [ "${#AP_PASS}" -le 63 ]; then
        break
    fi
    warn "Password must be between 8 and 63 characters."
done

printf "\n${BOLD}Step 3/6 - Band & Channel${RESET}\n"
printf "   1) ${BOLD}5 GHz Wi-Fi 6 (80 MHz, ch 36)${RESET} - Fastest (Recommended)\n"
printf "   2) ${BOLD}5 GHz Wi-Fi 6 (80 MHz, ch 149)${RESET} - Upper 5 GHz (non-DFS)\n"
printf "   3) ${BOLD}2.4 GHz Wi-Fi 6 (20 MHz, ch 6)${RESET} - Best range / IoT compatibility\n"
BAND_CHOICE="$(prompt_choice "Select band & channel (1-3):" "1" "3")"

case "$BAND_CHOICE" in
    1) HW_MODE="a"; CHANNEL="36";  CENTR_IDX="42";  BAND_LABEL="5 GHz (80 MHz)"; NM_BAND="a" ;;
    2) HW_MODE="a"; CHANNEL="149"; CENTR_IDX="155"; BAND_LABEL="5 GHz (80 MHz)"; NM_BAND="a" ;;
    3) HW_MODE="g"; CHANNEL="6";   CENTR_IDX="0";   BAND_LABEL="2.4 GHz (20 MHz)"; NM_BAND="bg" ;;
esac

printf "\n${BOLD}Step 4/6 - Country Code & Security${RESET}\n"
COUNTRY="$(prompt_str "Regulatory country code (2-letter ISO, e.g. MY, US, GB, DE):" "MY")"
COUNTRY="${COUNTRY^^}"

SEC_CHOICE=1
if [ "$BACKEND_CHOICE" -eq 1 ]; then
    printf "   1) ${BOLD}WPA2-PSK (AES/CCMP)${RESET} - Maximum device compatibility (Recommended)\n"
    printf "   2) ${BOLD}WPA2/WPA3 Mixed (SAE + PSK)${RESET} - Modern devices + legacy fallback\n"
    printf "   3) ${BOLD}WPA3-SAE Only${RESET} - Strict WPA3\n"
    SEC_CHOICE="$(prompt_choice "Select security mode (1-3):" "1" "3")"
fi

printf "\n${BOLD}Step 5/6 - Internet Sharing (NAT)${RESET}\n"
DEFAULT_UP="$(detect_default_upstream || true)"
[ "$DEFAULT_UP" = "$AP_IFACE" ] && DEFAULT_UP=""
SHARE_NET=0
UPSTREAM_IFACE=""
if prompt_yn "Share internet from another interface (NAT routing)?" "$([ -n "$DEFAULT_UP" ] && echo y || echo n)"; then
    SHARE_NET=1
    info "Available interfaces:"
    ip -br link show | awk '{print "   - " $1 " (" $2 ")"}'
    UPSTREAM_IFACE="$(prompt_str "Upstream internet interface:" "${DEFAULT_UP:-wlan0}")"
fi

printf "\n${BOLD}Step 6/6 - Confirm & Launch${RESET}\n"
printf "\n${CYAN}┌─ AP Configuration Summary ──────────────────────────────────┐${RESET}\n"
printf "│  Backend   : %s\n" "$([ "$BACKEND_CHOICE" -eq 1 ] && echo "hostapd + dnsmasq (Wi-Fi 6)" || echo "NetworkManager (nmcli)")"
printf "│  Interface : %s\n" "$AP_IFACE"
printf "│  SSID      : %s\n" "$AP_SSID"
printf "│  Band / Ch : %s • Channel %s (%s)\n" "$BAND_LABEL" "$CHANNEL" "$COUNTRY"
printf "│  Internet  : %s\n" "$([ "$SHARE_NET" -eq 1 ] && echo "Shared via ${UPSTREAM_IFACE}" || echo "Local-only (no NAT)")"
printf "${CYAN}└─────────────────────────────────────────────────────────────┘${RESET}\n\n"

if ! prompt_yn "Start Access Point now?" "y"; then
    info "Cancelled."
    exit 0
fi

# Clean any prior AP state first
[ -d "$STATE_DIR" ] && stop_ap >/dev/null 2>&1 || true
mkdir -p "$STATE_DIR"

# --- Launch Backend B: NetworkManager -----------------------------------------
if [ "$BACKEND_CHOICE" -eq 2 ]; then
    info "Starting NetworkManager hotspot on ${AP_IFACE}..."
    nmcli con delete "$NM_CON_NAME" >/dev/null 2>&1 || true
    nmcli dev disconnect "$AP_IFACE" >/dev/null 2>&1 || true
    nmcli dev wifi hotspot ifname "$AP_IFACE" con-name "$NM_CON_NAME" ssid "$AP_SSID" band "$NM_BAND" channel "$CHANNEL" password "$AP_PASS"
    cat > "${STATE_DIR}/state.env" <<EOF
mode=nmcli
iface=${AP_IFACE}
ssid=${AP_SSID}
band_label="${BAND_LABEL}"
channel=${CHANNEL}
upstream=${UPSTREAM_IFACE}
ap_ip=10.42.0.1/24
EOF
    ok "Hotspot '${AP_SSID}' is LIVE on ${AP_IFACE}!"
    if command -v qrencode >/dev/null 2>&1; then
        printf "\n"
        qrencode -t ANSIUTF8 "WIFI:T:WPA;S:${AP_SSID};P:${AP_PASS};;"
    fi
    info "Check status: sudo $0 --status"
    info "Stop hotspot: sudo $0 --stop"
    exit 0
fi

# --- Launch Backend A: hostapd + dnsmasq + NAT --------------------------------
AP_SUBNET="10.42.88"
AP_IP="${AP_SUBNET}.1"

# Hand off interface from NetworkManager temporarily
if command -v nmcli >/dev/null 2>&1; then
    nmcli dev disconnect "$AP_IFACE" >/dev/null 2>&1 || true
    nmcli dev set "$AP_IFACE" managed no >/dev/null 2>&1 || true
fi

ip link set "$AP_IFACE" down
ip addr flush dev "$AP_IFACE"
ip addr add "${AP_IP}/24" dev "$AP_IFACE"
ip link set "$AP_IFACE" up

# Build hostapd.conf
HOSTAPD_CONF="${STATE_DIR}/hostapd.conf"
{
    cat <<EOF
interface=${AP_IFACE}
driver=nl80211
country_code=${COUNTRY}
ieee80211d=1
ssid=${AP_SSID}
hw_mode=${HW_MODE}
channel=${CHANNEL}
wmm_enabled=1
ieee80211n=1
ieee80211ax=1
he_bss_color=37
ht_capab=[LDPC][HT40+][SHORT-GI-20][SHORT-GI-40][TX-STBC][RX-STBC1][MAX-AMSDU-7935]
EOF
    if [ "$HW_MODE" = "a" ]; then
        cat <<EOF
ieee80211ac=1
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=${CENTR_IDX}
he_oper_chwidth=1
he_oper_centr_freq_seg0_idx=${CENTR_IDX}
vht_capab=[MAX-MPDU-7991][RXLDPC][SHORT-GI-80][TX-STBC-2BY1][RX-STBC-1][SU-BEAMFORMEE][MU-BEAMFORMEE][MAX-A-MPDU-LEN-EXP7]
EOF
    fi

    case "$SEC_CHOICE" in
        1)
            cat <<EOF
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=${AP_PASS}
EOF
            ;;
        2)
            cat <<EOF
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK SAE
ieee80211w=1
rsn_pairwise=CCMP
wpa_passphrase=${AP_PASS}
EOF
            ;;
        3)
            cat <<EOF
auth_algs=1
wpa=2
wpa_key_mgmt=SAE
ieee80211w=2
rsn_pairwise=CCMP
wpa_passphrase=${AP_PASS}
EOF
            ;;
    esac
} > "$HOSTAPD_CONF"

# Build dnsmasq.conf
DNSMASQ_CONF="${STATE_DIR}/dnsmasq.conf"
cat > "$DNSMASQ_CONF" <<EOF
interface=${AP_IFACE}
bind-interfaces
dhcp-range=${AP_SUBNET}.10,${AP_SUBNET}.200,255.255.255.0,12h
dhcp-option=option:router,${AP_IP}
dhcp-option=option:dns-server,1.1.1.1,8.8.8.8
dhcp-leasefile=${STATE_DIR}/dnsmasq.leases
pid-file=${STATE_DIR}/dnsmasq.pid
EOF

# Save state before starting daemons so Ctrl+C cleanup always works
cat > "${STATE_DIR}/state.env" <<EOF
mode=hostapd
iface=${AP_IFACE}
ssid=${AP_SSID}
band_label="${BAND_LABEL}"
channel=${CHANNEL}
upstream=${UPSTREAM_IFACE}
ap_ip=${AP_IP}/24
EOF

# Enable NAT if requested
if [ "$SHARE_NET" -eq 1 ] && [ -n "$UPSTREAM_IFACE" ]; then
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    if command -v nft >/dev/null 2>&1; then
        nft -f - <<EOF
table inet rtl8852cu_ap {
    chain forward {
        type filter hook forward priority 0; policy accept;
        iifname "${AP_IFACE}" oifname "${UPSTREAM_IFACE}" accept
        iifname "${UPSTREAM_IFACE}" oifname "${AP_IFACE}" ct state related,established accept
    }
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "${UPSTREAM_IFACE}" masquerade
    }
}
EOF
    elif command -v iptables >/dev/null 2>&1; then
        iptables -t nat -A POSTROUTING -o "$UPSTREAM_IFACE" -j MASQUERADE
        iptables -A FORWARD -i "$AP_IFACE" -o "$UPSTREAM_IFACE" -j ACCEPT
        iptables -A FORWARD -i "$UPSTREAM_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi
    ok "NAT internet sharing active: ${AP_IFACE} → ${UPSTREAM_IFACE}"
fi

# Start dnsmasq
dnsmasq --conf-file="$DNSMASQ_CONF"
ok "DHCP/DNS server running (${AP_SUBNET}.10-200)"

# Show QR code if qrencode is available
if command -v qrencode >/dev/null 2>&1; then
    printf "\n"
    qrencode -t ANSIUTF8 "WIFI:T:WPA;S:${AP_SSID};P:${AP_PASS};;"
fi

printf "\n"
if prompt_yn "Run AP in background (daemon mode)? (No = stay attached, Ctrl+C stops AP)" "n"; then
    hostapd -B -P "${STATE_DIR}/hostapd.pid" "$HOSTAPD_CONF"
    ok "Wi-Fi 6 AP '${AP_SSID}' is LIVE in background on ${AP_IFACE}!"
    info "Check status : sudo $0 --status"
    info "Stop AP      : sudo $0 --stop"
else
    trap 'printf "\n"; stop_ap; exit 0' INT TERM
    ok "Starting Wi-Fi 6 AP '${AP_SSID}' on ${AP_IFACE} (press Ctrl+C to stop & restore)..."
    hostapd -P "${STATE_DIR}/hostapd.pid" "$HOSTAPD_CONF"
    stop_ap
fi
