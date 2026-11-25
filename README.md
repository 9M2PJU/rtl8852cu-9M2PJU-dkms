<div align="center">

# 📡 rtl8852cu-9M2PJU-dkms (`8852cu.ko`)

**Linux DKMS Driver for Realtek RTL8832CU & RTL8852CU Wi-Fi 6 / 6E USB Adapters**  
*Maintained by **9M2PJU** - updated for modern **Linux 6.18 - 7.3+**, **Clang/LLVM (CachyOS)**, and **GCC** kernels.*

[![Linux Kernel](https://img.shields.io/badge/Linux_Kernel-5.15_-_7.3%2B-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://kernel.org)
[![Compiler](https://img.shields.io/badge/Compiler-GCC_%26_Clang%2FLLVM-262D3A?style=for-the-badge&logo=llvm&logoColor=white)](#compilers--distributions)
[![AUR Stable](https://img.shields.io/badge/AUR-rtl8852cu--9m2pju--dkms-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://aur.archlinux.org/packages/rtl8852cu-9m2pju-dkms)
[![AUR Git](https://img.shields.io/badge/AUR_Git-rtl8852cu--9m2pju--dkms--git-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://aur.archlinux.org/packages/rtl8852cu-9m2pju-dkms-git)
[![Companion GUI App](https://img.shields.io/badge/AP_GUI_App-AirCast--AP-4A86CF?style=for-the-badge&logo=gnome&logoColor=white)](https://github.com/9M2PJU/AirCast-AP)
[![License: GPL v2](https://img.shields.io/badge/License-GPL--2.0-blue?style=for-the-badge)](LICENSE)
[![Driver Version](https://img.shields.io/badge/Realtek_Base-v1.19.2.1_(20240510)-00ADD8?style=for-the-badge)](#about)

[✨ What's Changed](#-whats-changed-in-this-fork) •
[🪄 1-Line Installer](#-1-line-interactive-installer-recommended) •
[📶 AP Mode & AirCast-AP](#-ap--hotspot-mode--desktop-app--cli-wizard) •
[🚀 USB 3.0 High-Speed](#-usb-30-superspeed-tuning) •
[🔌 Supported Devices](#-supported-usb-devices) •
[☕ Support](#-support-this-project)

</div>

---

## 📖 About

`rtl8852cu-9M2PJU-dkms` is an actively maintained DKMS fork of the Realtek **v1.19.2.1 (20240510)** `8852cu.ko` out-of-tree USB Wi-Fi driver (originating from `morrownr/rtl8852cu-20240510` and `parheliamm/rtl8852cu-20240510`), patched to compile cleanly and run stably on bleeding-edge Linux **7.3+** kernels and **Clang/LLVM-built kernels** such as **CachyOS**.

> [!NOTE]
> **In-kernel driver note:** Linux includes an in-kernel `rtw89_8852cu` driver. If `rtw89_8852cu` works well on your kernel, prefer it. Use this DKMS driver when you need Realtek's vendor PHY/Wi-Fi 6/AP/USB-mode features or hit regressions with `rtw89_8852cu` - make sure to blacklist `rtw89_8852cu` when using `8852cu` so the two drivers do not conflict.

---

## ✨ What's Changed in This Fork

### 🆕 `2026-11-26` - Linux 7.3+ & Clang/LLVM Release (`8750f22`)

| Area | File(s) | Change & Why It Matters |
| :--- | :--- | :--- |
| **Linux 7.3 `cfg80211_ops` Crash Fix** | `os_dep/linux/ioctl_cfg80211.c` | Updated `add_key`, `get_key`, `del_key`, `set_default_mgmt_key`, `get_station`, `add_station`, `del_station`, `change_station`, `dump_station`, `cfg80211_new_sta`, and `cfg80211_del_sta` from `struct net_device *` to `struct wireless_dev *` (`LINUX_VERSION_CODE >= 7.3.0`). Updated `remain_on_channel` and `mgmt_tx` from `u64 *cookie` to `u64 cookie`, and added `int radio_idx` to `set_tx_power` (`>= 6.17.0`). **Fixes the kernel page-fault oops (`BUG: unable to handle page fault` in `cfg80211_rtw_add_key` → `rtw_cfg80211_sync_iftype`) when connecting via `wpa_supplicant`.** |
| **Clang/LLVM Auto-Detection** | `dkms-make.sh` | Automatically inspects `$ksrc/.config` and `$ksrc/include/config/auto.conf` for `CONFIG_CC_IS_CLANG=y` and passes `LLVM=1` automatically. Works seamlessly out-of-the-box on both **CachyOS (Clang/LLVM)** and standard **GCC** distros (Arch, Ubuntu, Debian, Fedora). |
| **Removed `strncpy()` Kernel API Fix** | `core/rtw_debug.c`, `os_dep/linux/ioctl_cfg80211.c`, `os_dep/linux/ioctl_linux.c`, `os_dep/linux/os_intfs.c`, `os_dep/linux/rtw_cfgvendor.c`, `os_dep/linux/usb_intf.c`, `phl/pltfm_ops_linux.h` | Replaced deprecated/removed kernel `strncpy()` calls with `strscpy()`, `memcpy()`, and an inline `_os_strncpy()` helper so Clang/LLVM and modern kernels compile without `Unknown symbol strncpy` or implicit-declaration errors. |
| **PPPoE Header & `CONFIG_BR_EXT` Fix** | `core/rtw_br_ext.c`, `core/rtw_xmit.c`, `Makefile` | Uses wire-layout byte offsets (`RTW_PPPOE_TAG` / `RTW_PPPOE_TAG_DATA`) for hidden kernel `pppoe_hdr` fields, disables `CONFIG_BR_EXT` cleanly, and adds a `#else` stub + `#ifdef CONFIG_BR_EXT` guard for `core_br_client_tx` (fixes `Unknown symbol core_br_client_tx`). |
| **Clean DKMS Config** | `dkms.conf` | Removed the deprecated `CLEAN` directive that caused DKMS warnings on modern `dkms` versions. |
| **Interactive 1-Line Installer** | `setup.sh` | Added guided `curl \| bash` installer that auto-detects distro, kernel, Clang/GCC, and USB adapter, then asks for install method (AUR vs GitHub DKMS), USB 3.0/2.0 mode, `rtw89_8852cu` blacklisting, and live module reload. |
| **Interactive Wi-Fi 6 AP Wizard** | `ap-mode.sh` | Added guided AP / hotspot script supporting both **`hostapd` + `dnsmasq` + `nftables`/`iptables` NAT** (full 5 GHz / 80 MHz Wi-Fi 6, WPA2/WPA3) and **NetworkManager (`nmcli`)** quick hotspot, with `--status`, `--stop`, QR code output, and automatic `rtw_he_enable=2 rtw_vht_enable=2` setup. |

### 📜 Prior Community Kernel Patches Included
- **Linux 6.18** (`df11acd`) - `cfg80211` / timer / kernel API updates
- **Linux 6.17** (`7a5f2c6`, `#38`) - `cfg80211` `radio_idx` support
- **Linux 6.16** (`c01bd40`) - kernel 6.16 compatibility fixes
- **Linux 5.15 - 6.15** - Realtek v1.19.2.1 (20240510) + `morrownr` & community patches

---

## 🎯 Features

- **Wi-Fi Standards:** IEEE 802.11 a/b/g/n/ac/ax (Wi-Fi 6 / 6E where hardware supports it), up to **160 MHz** channel width (VHT / HE)
- **Security:** WPA3-SAE R2, WPA2-AES/PSK/Enterprise (802.1X TLS/RADIUS), WPA, WEP, WPS (PIN/PBC)
- **Operating Modes:** Managed (Station), AP (`hostapd-rtl8852cu.conf`), P2P-Client / P2P-GO (Wi-Fi Direct / Miracast), IBSS, Wake-on-WLAN
- **USB Mode Control:** Switchable between USB 2.0 (`480M`) and USB 3.0 SuperSpeed (`5000M`) via `rtw_switch_usb_mode`

> [!WARNING]
> **Monitor mode is not supported** by Realtek's `8852cu` driver. If you need monitor mode / packet injection on Linux, use an adapter based on a MediaTek chipset (`mt7610u`, `mt7612u`, `mt7921au`).

---

## 🖥️ Compilers, Kernels & Distributions

| Category | Supported / Verified |
| :--- | :--- |
| **Linux Kernels** | `5.15 - 6.6` (Realtek) • `6.7 - 6.18` (community) • **`6.19 - 7.3+` (9M2PJU fork)** |
| **Compilers** | **GCC** 13, 14, 15, 16 • **Clang / LLVM** (auto-detected by `dkms-make.sh`) |
| **CPU Architectures** | `x86_64` / `amd64`, `i386`/`i686`, `aarch64` (`arm64`), `armv6l`/`armv7l`, `riscv` |
| **Verified Distros** | **CachyOS** (`7.3.6-1-cachyos`, Clang/LLVM), **Arch Linux**, **Debian**, **Ubuntu**, **Fedora**, **Manjaro**, **openSUSE Tumbleweed**, **Raspberry Pi OS**, **Zorin OS** |

---

## 🪄 1-Line Interactive Installer (Recommended)

Run a single command - `setup.sh` auto-detects your **distro**, **kernel**, **GCC vs Clang/LLVM**, and **USB adapter**, then walks you through clean interactive prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/9M2PJU/rtl8852cu-9M2PJU-dkms/main/setup.sh | bash
```

**What the interactive wizard asks & handles for you:**
1. **Install / Upgrade / Configure / Uninstall** - offers AUR (`yay`/`paru`) automatically on Arch/CachyOS, or GitHub DKMS (`install-driver.sh`) on any distro (Debian, Ubuntu, Fedora, openSUSE, etc.)
2. **USB Speed Mode** - choose between **USB 3.0 SuperSpeed (`5000M`)** for max throughput or **USB 2.0 (`480M`)** for hub compatibility (or keep existing `8852cu.conf`)
3. **In-Kernel Driver Blacklist** - optionally writes `/etc/modprobe.d/blacklist-rtw89-8852cu.conf` so `8852cu` binds without conflict
4. **Build Dependencies & Live Reload** - optionally installs matching kernel headers (`linux-cachyos-headers`, `linux-headers`, etc.) and reloads `8852cu` immediately with no reboot required

> [!TIP]
> Prefer to inspect the script before running? View [`setup.sh`](setup.sh) directly in this repo, or run `bash <(curl -fsSL https://raw.githubusercontent.com/9M2PJU/rtl8852cu-9M2PJU-dkms/main/setup.sh)`.

---

## ⚡ Quick Installation

### Option 1: Arch Linux / CachyOS via AUR (Recommended)

```bash
# Tagged stable release (recommended - fast tarball + verified SHA256):
yay -S rtl8852cu-9m2pju-dkms

# Or bleeding-edge git HEAD:
yay -S rtl8852cu-9m2pju-dkms-git
```

Blacklist the in-kernel `rtw89_8852cu` driver so `8852cu` binds cleanly:

```bash
echo "blacklist rtw89_8852cu" | sudo tee /etc/modprobe.d/blacklist-rtw89-8852cu.conf
```

Reboot or replug your USB Wi-Fi adapter.

---

### Option 2: DKMS Install Script (All Distros)

1. **Install build dependencies:**

<details>
<summary><b>Arch / CachyOS / Manjaro</b></summary>

```bash
sudo pacman -Syu
sudo pacman -S --needed linux-headers dkms git bc iw
# CachyOS users: install linux-cachyos-headers instead of linux-headers
```
</details>

<details>
<summary><b>Debian / Ubuntu / Kali / Raspberry Pi OS</b></summary>

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y linux-headers-$(uname -r) build-essential bc dkms git libelf-dev rfkill iw
```
</details>

<details>
<summary><b>Fedora</b></summary>

```bash
sudo dnf upgrade -y
sudo dnf install -y git dkms kernel-devel bc openssl
```
</details>

<details>
<summary><b>openSUSE</b></summary>

```bash
sudo zypper update
sudo zypper install -t pattern devel_kernel dkms
```
</details>

2. **Clone and install via DKMS:**

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/9M2PJU/rtl8852cu-9M2PJU-dkms.git
cd ~/src/rtl8852cu-9M2PJU-dkms
sudo ./install-driver.sh
```

> [!TIP]
> For non-interactive / automated installs, run `sudo ./install-driver.sh NoPrompt`.  
> Check installation status anytime with `dkms status`.

<details>
<summary><b>Option 3: Manual Build (Non-DKMS)</b></summary>

```bash
make clean
# On GCC kernels:
make -j$(nproc)
# On Clang/LLVM kernels (e.g. CachyOS):
make LLVM=1 -j$(nproc)

sudo make install        # or `sudo make sign-install` for Secure Boot
sudo reboot
```

To remove a manual install: `sudo make uninstall && sudo reboot`.
</details>

---

## 🚀 USB 3.0 SuperSpeed Tuning

By default, `8852cu.conf` sets `rtw_switch_usb_mode=0` (USB 2.0 `480M`) for maximum compatibility on noisy hubs. If your adapter is plugged into a **USB 3.0 port**, switching to USB 3.0 SuperSpeed (`5000M`) noticeably improves multi-stream throughput and reduces idle latency:

```bash
echo "options 8852cu rtw_switch_usb_mode=1" | sudo tee /etc/modprobe.d/8852cu.conf
sudo modprobe -r 8852cu && sudo modprobe 8852cu
```

Verify USB 3.0 (`5000M`) is active:

```bash
lsusb -t | grep -i rtl8852cu
# Expected: |__ Port 006: Dev 003, If 0, Class=Vendor Specific Class, Driver=rtl8852cu, 5000M
```

### 📊 Real-World Benchmark (ThinkPad T460 • CachyOS `7.3.6-1-cachyos` • `35bc:0102` • 5 GHz 80 MHz HE-NSS2)

| Metric | USB 2.0 (`rtw_switch_usb_mode=0`, `480M`) | USB 3.0 (`rtw_switch_usb_mode=1`, `5000M`) | Gain |
| :--- | :---: | :---: | :---: |
| **Cloudflare 100 MB (4-stream)** | 276.4 Mbps | **323.3 Mbps** | **+17.0%** |
| **Ookla Speedtest (KL)** | 202.9 Mbps | **335.1 Mbps** *(burst 420 Mbps)* | Full ISP saturation |
| **Idle Latency** | 4.29 ms | **3.09 ms** | **-1.20 ms** |
| **Kernel Errors / Packet Loss** | 0 / 0% | **0 / 0%** | Rock solid |

> [!TIP]
> See [`8852cu.conf`](8852cu.conf) or run `sudo ./edit-options.sh` for all supported module parameters, and [`hostapd-rtl8852cu.conf`](hostapd-rtl8852cu.conf) for raw `hostapd` reference settings.

---

## 📶 AP / Hotspot Mode - Desktop App & CLI Wizard

### 🖥️ Recommended: [**AirCast-AP**](https://github.com/9M2PJU/AirCast-AP) (Dedicated GTK4 + Libadwaita GUI & CLI App)

Want a full **native Wayland/GTK4 desktop app** for turning your RTL8852CU (or any Linux Wi-Fi card) into a **Wi-Fi 6 / 5 GHz Access Point** with **live scannable QR codes**, **connected-client monitoring**, **1-click RTL8852CU Wi-Fi 6 AP tuning**, and **NAT internet sharing**?

> 🚀 **Check out our companion app: [`9M2PJU/AirCast-AP`](https://github.com/9M2PJU/AirCast-AP)**
> ```bash
> # Arch / CachyOS (AUR):
> yay -S aircast-ap
>
> # All Linux distros (1-liner):
> curl -fsSL https://raw.githubusercontent.com/9M2PJU/AirCast-AP/main/install.sh | bash
> ```

<table>
  <tr>
    <td align="center" width="50%">
      <a href="https://github.com/9M2PJU/AirCast-AP">
        <img src="https://raw.githubusercontent.com/9M2PJU/AirCast-AP/main/docs/screenshots/aircast-main.png" alt="AirCast-AP Main GUI" width="100%" />
      </a><br/>
      <b>AirCast-AP - RTL8852CU Wi-Fi 6 AP Detection &amp; 1-Click Tuning</b>
    </td>
    <td align="center" width="50%">
      <a href="https://github.com/9M2PJU/AirCast-AP">
        <img src="https://raw.githubusercontent.com/9M2PJU/AirCast-AP/main/docs/screenshots/aircast-qr-clients.png" alt="AirCast-AP QR Code and Connected Clients" width="100%" />
      </a><br/>
      <b>Live Wi-Fi QR Code &amp; Connected Clients Monitor</b>
    </td>
  </tr>
</table>

### 🧰 Lightweight Built-in Script (`ap-mode.sh`)

Prefer a zero-GUI terminal wizard right from this repo?

```bash
# Run directly (1-liner):
curl -fsSL https://raw.githubusercontent.com/9M2PJU/rtl8852cu-9M2PJU-dkms/main/ap-mode.sh | sudo bash

# Or from a local clone:
sudo ./ap-mode.sh          # Launch interactive AP wizard
sudo ./ap-mode.sh --status # View active AP info & connected clients
sudo ./ap-mode.sh --stop   # Stop AP, clear NAT rules, restore client mode
```

**What `ap-mode.sh` handles automatically:**
- Auto-detects your `8852cu` interface (`wlan1`) and offers to enable `rtw_he_enable=2 rtw_vht_enable=2` in `/etc/modprobe.d/8852cu.conf` for full Wi-Fi 6 / 80 MHz AP mode
- Lets you choose between **`hostapd` + `dnsmasq` + NAT** (full Wi-Fi 6, 5 GHz 80 MHz / 2.4 GHz, WPA2 / WPA2+WPA3 / WPA3-SAE) or **NetworkManager (`nmcli`)** quick hotspot
- Configures IP forwarding + clean `nftables` (or `iptables`) NAT internet sharing from your chosen upstream interface
- Prints a terminal **Wi-Fi QR code** if `qrencode` is installed, and cleanly tears everything down on `Ctrl+C` or `--stop`

---

## 🔌 Supported USB Devices

Run `lsusb` to check your adapter's `VendorID:ProductID` (full list in [`supported-device-IDs`](supported-device-IDs) and `os_dep/linux/usb_intf.c`):

| USB ID | Device / Chipset | Notes |
| :---: | :--- | :--- |
| `0bda:c832` | Realtek RTL8832CU / RTL8852CU | Default Realtek ID |
| `0bda:c85a` | Realtek RTL8832CU / RTL8852CU | Default Realtek ID |
| `0bda:c85d` | Realtek RTL8832CU / RTL8852CU | Default Realtek ID |
| `0db0:991d` | MSI AXE5400 | Multi-state (`usb_modeswitch`) |
| `35b2:0502` | TP-Link RTL8852CU adapter | |
| `35bc:0101` | TP-Link Archer TX50UH V1 | Multi-state |
| `35bc:0102` | TP-Link Archer TXE70UH(EU) V1 / Realtek AX | Verified on Linux 7.3.6 (CachyOS) |

Also reported compatible: **EDUP AX5400 EP-AX1671 / EP-AX1671S**, **BrosTrend AX8**, **Wavlink WL-WN695X2-A**.

---

## 🔄 Upgrading & Uninstalling

<details>
<summary><b>Upgrading from Git</b></summary>

```bash
cd ~/src/rtl8852cu-9M2PJU-dkms
git pull
sudo ./install-driver.sh
```
</details>

<details>
<summary><b>Uninstalling</b></summary>

```bash
cd ~/src/rtl8852cu-9M2PJU-dkms
sudo ./uninstall-driver.sh
```
</details>

---

## 🛠️ Troubleshooting & Tips

- **Conflict with in-kernel `rtw89_8852cu`:** Check `lsmod | grep -E '8852|rtw89'`. If `rtw89_8852cu` is grabbing the adapter, add `blacklist rtw89_8852cu` to `/etc/modprobe.d/blacklist-rtw89-8852cu.conf` and reboot.
- **Multi-state adapters showing as USB CD-ROM (`0bda:1a2b`):** Make sure `usb_modeswitch` is installed so the dongle automatically switches to Wi-Fi mode.
- **Secure Boot:** DKMS signs modules automatically if MOK keys are enrolled (`/var/lib/dkms/mok.pub`). On Fedora, enroll with `sudo mokutil --import /var/lib/dkms/mok.pub`. See [`FAQ.md`](FAQ.md) for details.
- **Check active parameters:**
  ```bash
  grep '[[:alnum:]]' /sys/module/8852cu/parameters/*
  ```
- **USB stability:** Plug directly into a motherboard USB 3.0 port (avoid unshielded extension cables or underpowered hubs).

---

## ☕ Support This Project

If this driver saved you hours of kernel debugging or got your Wi-Fi 6/6E USB adapter running smoothly on Linux 7.3+ / CachyOS, consider supporting ongoing maintenance and amateur radio / open-source projects by **9M2PJU**:

<div align="center">

[![GitHub Sponsors](https://img.shields.io/badge/GitHub_Sponsors-9M2PJU-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/9M2PJU)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-9m2pju-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/9m2pju)
[![PayPal](https://img.shields.io/badge/PayPal-9M2PJU-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/paypalme/9M2PJU)
[![Wise](https://img.shields.io/badge/Wise-faizulz13-9FE870?style=for-the-badge&logo=wise&logoColor=black)](https://wise.com/pay/me/faizulz13)

</div>

---

## 🙏 Credits & License

- **Realtek Semiconductor Corp.** - Upstream `rtl8852cu` driver (`v1.19.2.1`)
- **[morrownr](https://github.com/morrownr/USB-WiFi)** & **[parheliamm](https://github.com/parheliamm/rtl8852cu-20240510)** - Original Linux community packaging, DKMS scripts, and kernel 6.x patches
- **9M2PJU** ([hamradio.my](https://hamradio.my)) - Linux 7.3+ `cfg80211` fixes, Clang/LLVM auto-detection, AUR maintenance

Licensed under the **GNU General Public License v2.0** ([`LICENSE`](LICENSE)).  
*73 de 9M2PJU!* 📻
