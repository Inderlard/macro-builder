# SETUP_GUIDE.md — CAN Bus Quick Setup Guide

> **Based on the community guide at [https://canbus.esoterical.online](https://canbus.esoterical.online)**
> This document is a condensed, generic reference. For full details, board-specific pinouts, and the most up-to-date instructions, **always visit the original guide**.

---

## Table of Contents

- [SETUP\_GUIDE.md — CAN Bus Quick Setup Guide](#setup_guidemd--can-bus-quick-setup-guide)
  - [Table of Contents](#table-of-contents)
  - [1. Overview \& Workflow](#1-overview--workflow)
  - [2. Prerequisites](#2-prerequisites)
  - [3. Step 1 — Candlelight (USB-CAN adapter firmware)](#3-step-1--candlelight-usb-can-adapter-firmware)
    - [Flash Candlelight](#flash-candlelight)
    - [Bring up the CAN interface](#bring-up-the-can-interface)
  - [4. Step 2 — Katapult on Toolheads and Mainboards](#4-step-2--katapult-on-toolheads-and-mainboards)
    - [`deployer.bin` vs `katapult.bin` — Critical Distinction](#deployerbin-vs-katapultbin--critical-distinction)
    - [Clean Install (`katapult.bin`)](#clean-install-katapultbin)
      - [1. Build Katapult for your board](#1-build-katapult-for-your-board)
      - [2. Put the board in DFU mode](#2-put-the-board-in-dfu-mode)
      - [3. Flash `katapult.bin` via DFU](#3-flash-katapultbin-via-dfu)
      - [4. Verify Katapult is running](#4-verify-katapult-is-running)
    - [Update / Re-flash (`deployer.bin`)](#update--re-flash-deployerbin)
      - [1. Build the deployer](#1-build-the-deployer)
      - [2. Send `deployer.bin` over CAN](#2-send-deployerbin-over-can)
  - [5. Step 3 — Klipper over CAN](#5-step-3--klipper-over-can)
      - [1. Build Klipper for your board](#1-build-klipper-for-your-board)
      - [2. Put the board in Katapult mode](#2-put-the-board-in-katapult-mode)
      - [3. Flash Klipper via Katapult](#3-flash-klipper-via-katapult)
      - [4. Verify Klipper is running](#4-verify-klipper-is-running)
  - [6. Board Configuration Examples](#6-board-configuration-examples)
    - [EBB36 V1.2](#ebb36-v12)
      - [Katapult `menuconfig` (EBB36 V1.2)](#katapult-menuconfig-ebb36-v12)
      - [Klipper `menuconfig` (EBB36 V1.2)](#klipper-menuconfig-ebb36-v12)
    - [EBB36 V2](#ebb36-v2)
      - [Katapult `menuconfig` (EBB36 V2)](#katapult-menuconfig-ebb36-v2)
      - [Klipper `menuconfig` (EBB36 V2)](#klipper-menuconfig-ebb36-v2)
    - [BTT U2C V2](#btt-u2c-v2)
      - [Flashing Candlelight on BTT U2C V2](#flashing-candlelight-on-btt-u2c-v2)
    - [MKS Monster 8 V1](#mks-monster-8-v1)
      - [Katapult `menuconfig` (MKS Monster 8 V1)](#katapult-menuconfig-mks-monster-8-v1)
      - [Klipper `menuconfig` (MKS Monster 8 V1 — USB-CAN bridge mode)](#klipper-menuconfig-mks-monster-8-v1--usb-can-bridge-mode)
  - [7. Verifying the CAN Network](#7-verifying-the-can-network)
    - [List all CAN nodes](#list-all-can-nodes)
    - [Check CAN interface statistics](#check-can-interface-statistics)
  - [8. Integrating with macro-builder](#8-integrating-with-macro-builder)
  - [9. Troubleshooting](#9-troubleshooting)
  - [10. Credits](#10-credits)

---

## 1. Overview & Workflow

Setting up a CAN bus network for Klipper involves four main stages, always in this order:

```
[Candlelight] → [Katapult on toolheads/mainboards] → [Klipper firmware]
                        ↑
              (deployer.bin for updates,
               katapult.bin for clean installs)
```

| Stage | What it does |
|---|---|
| **Candlelight** | Flashes the USB-CAN bridge adapter (e.g. BTT U2C) with the `candlelight` firmware so the host sees a `can0` network interface. |
| **Katapult** | Installs the Katapult bootloader on each MCU (toolhead, mainboard). This enables future firmware updates over CAN without physical access. |
| **Klipper** | Flashes the actual Klipper firmware onto each MCU via Katapult over CAN. |

> **Important:** This guide is generic. Board-specific menuconfig settings (processor, clock speed, CAN pins, etc.) vary. Always look up your exact board at **[https://canbus.esoterical.online](https://canbus.esoterical.online)**.

---

## 2. Prerequisites

- A Raspberry Pi (or equivalent SBC) running **MainsailOS** or similar Klipper host.
- **Klipper** installed (`~/klipper`).
- **Katapult** cloned (`~/katapult`):

  ```bash
  cd ~
  git clone https://github.com/Arksine/katapult
  ```

- A USB-CAN adapter (e.g. BTT U2C V2) or a mainboard capable of acting as a USB-CAN bridge.
- `python3-can` and `pyserial` installed:

  ```bash
  pip3 install pyserial
  pip3 install python-can
  ```

---

## 3. Step 1 — Candlelight (USB-CAN adapter firmware)

The USB-CAN adapter must be flashed with **Candlelight** firmware so the host OS recognises it as a CAN network interface (`can0`).

### Flash Candlelight

1. Download the appropriate Candlelight `.bin` for your adapter from the official releases or from [https://canbus.esoterical.online](https://canbus.esoterical.online).
2. Put the adapter in DFU mode (usually by holding BOOT and pressing RESET, or bridging BOOT0 to 3.3 V).
3. Flash via `dfu-util`:

   ```bash
   sudo dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D candlelight_fw.bin
   ```

4. Reconnect the adapter. Verify the interface appears:

   ```bash
   ip link show can0
   ```

### Bring up the CAN interface

Add the following to `/etc/network/interfaces.d/can0` (create if it doesn't exist):

```
allow-hotplug can0
iface can0 can static
    bitrate 1000000
    up ip link set $IFACE txqueuelen 1024
```

Then bring it up:

```bash
sudo ip link set up can0 type can bitrate 1000000
sudo ip link set can0 txqueuelen 1024
```

Verify:

```bash
ip -details link show can0
```

---

## 4. Step 2 — Katapult on Toolheads and Mainboards

Katapult is a lightweight bootloader that allows flashing firmware over CAN (or USB) without physical access to the board.

### `deployer.bin` vs `katapult.bin` — Critical Distinction

> ⚠️ **This is one of the most common sources of confusion. Read carefully.**

| File | When to use | What it does |
|---|---|---|
| **`katapult.bin`** | **Clean install only** — board has no Katapult yet | Full Katapult bootloader image. Must be flashed via DFU, STLink, or microSD. |
| **`deployer.bin`** | **Update / re-flash** — board already has Katapult | A self-deploying image that uses the *existing* Katapult to overwrite itself with a new version. Sent over CAN or USB via `flashtool.py`. |

**Rule of thumb:**
- First time on a new board → use `katapult.bin` (physical flash required).
- Updating Katapult on a board that already has it → use `deployer.bin` (over-the-air via CAN/USB).

---

### Clean Install (`katapult.bin`)

Use this path when the board has **no bootloader** yet.

#### 1. Build Katapult for your board

```bash
cd ~/katapult
make menuconfig
```

Configure for your specific board (processor, CAN speed, CAN pins). See [Board Configuration Examples](#6-board-configuration-examples) below and the full list at [https://canbus.esoterical.online](https://canbus.esoterical.online).

```bash
make clean
make
```

The output is `~/katapult/out/katapult.bin`.

#### 2. Put the board in DFU mode

- Hold **BOOT** button, press **RESET**, release RESET, then release BOOT.
- Verify DFU device is detected:

  ```bash
  lsusb | grep DFU
  # or
  dfu-util -l
  ```

#### 3. Flash `katapult.bin` via DFU

```bash
sudo dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D ~/katapult/out/katapult.bin
```

> Some boards use a different DFU address. Check [https://canbus.esoterical.online](https://canbus.esoterical.online) for your board.

#### 4. Verify Katapult is running

After power-cycling the board, query the CAN bus:

```bash
python3 ~/katapult/scripts/flashtool.py -i can0 -q
```

You should see the board listed with its UUID in **Katapult** mode.

---

### Update / Re-flash (`deployer.bin`)

Use this path when the board **already has Katapult** and you want to update it.

#### 1. Build the deployer

```bash
cd ~/katapult
make menuconfig   # same settings as the original install
make clean
make
```

The output is `~/katapult/out/deployer.bin`.

#### 2. Send `deployer.bin` over CAN

```bash
python3 ~/katapult/scripts/flashtool.py -i can0 -u <UUID> -f ~/katapult/out/deployer.bin
```

Replace `<UUID>` with the board's CAN UUID (obtained from `flashtool.py -i can0 -q`).

The deployer will overwrite the existing Katapult with the new version. The board will reboot into the updated Katapult automatically.

---

## 5. Step 3 — Klipper over CAN

Once Katapult is installed on all boards, flash Klipper firmware over CAN.

#### 1. Build Klipper for your board

```bash
cd ~/klipper
make menuconfig
```

Configure for your board (processor, CAN speed, CAN pins, Katapult offset). See [Board Configuration Examples](#6-board-configuration-examples).

```bash
make clean
make
```

Output: `~/klipper/out/klipper.bin`.

#### 2. Put the board in Katapult mode

If Klipper is already running on the board, you need to restart it into Katapult mode:

```bash
python3 ~/katapult/scripts/flashtool.py -i can0 -u <UUID> -r
```

Or, if the board is freshly flashed with Katapult and has never had Klipper, it will already be in Katapult mode.

#### 3. Flash Klipper via Katapult

```bash
python3 ~/katapult/scripts/flashtool.py -i can0 -u <UUID> -f ~/klipper/out/klipper.bin
```

#### 4. Verify Klipper is running

```bash
python3 ~/katapult/scripts/flashtool.py -i can0 -q
```

The board should now appear as a **Klipper** node (not Katapult).

---

## 6. Board Configuration Examples

> ⚠️ **These are example starting points only.** Exact menuconfig settings depend on your board revision, wiring, and CAN speed. Always verify against the official board page at **[https://canbus.esoterical.online](https://canbus.esoterical.online)**.

---

### EBB36 V1.2

**Processor:** STM32G0B1  
**CAN speed:** 1 000 000 bps  
**Typical CAN pins:** PB0 (TX), PB1 (RX)

#### Katapult `menuconfig` (EBB36 V1.2)

```
Micro-controller Architecture  →  STMicroelectronics STM32
Processor model                →  STM32G0B1
Build Katapult deployment application  →  Do not build
Clock Reference                →  8 MHz crystal
Communication interface        →  CAN bus (on PB0/PB1)
Application start offset       →  8KiB offset
CAN bus speed                  →  1000000
```

#### Klipper `menuconfig` (EBB36 V1.2)

```
Micro-controller Architecture  →  STMicroelectronics STM32
Processor model                →  STM32G0B1
Bootloader offset              →  8KiB bootloader
Clock Reference                →  8 MHz crystal
Communication interface        →  CAN bus (on PB0/PB1)
CAN bus speed                  →  1000000
```

---

### EBB36 V2

**Processor:** STM32G0B1  
**CAN speed:** 1 000 000 bps  
**Typical CAN pins:** PB0 (TX), PB1 (RX)

> EBB36 V2 shares the same processor as V1.2 but may differ in USB ID and some pin assignments. Confirm at [https://canbus.esoterical.online](https://canbus.esoterical.online).

#### Katapult `menuconfig` (EBB36 V2)

```
Micro-controller Architecture  →  STMicroelectronics STM32
Processor model                →  STM32G0B1
Build Katapult deployment application  →  Do not build
Clock Reference                →  8 MHz crystal
Communication interface        →  CAN bus (on PB0/PB1)
Application start offset       →  8KiB offset
CAN bus speed                  →  1000000
```

#### Klipper `menuconfig` (EBB36 V2)

```
Micro-controller Architecture  →  STMicroelectronics STM32
Processor model                →  STM32G0B1
Bootloader offset              →  8KiB bootloader
Clock Reference                →  8 MHz crystal
Communication interface        →  CAN bus (on PB0/PB1)
CAN bus speed                  →  1000000
```

---

### BTT U2C V2

The U2C V2 acts as a **USB-CAN bridge** (Candlelight adapter). It does **not** run Klipper or Katapult — it only provides the `can0` interface to the host.

**Processor:** STM32G0B1  
**Firmware:** Candlelight (not Klipper/Katapult)

#### Flashing Candlelight on BTT U2C V2

1. Download the Candlelight firmware for U2C V2 from [https://canbus.esoterical.online](https://canbus.esoterical.online) or the BTT GitHub.
2. Put the U2C in DFU mode (BOOT + RESET).
3. Flash:

   ```bash
   sudo dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D G0B1_candlelight_fw.bin
   ```

4. Reconnect and verify `can0` appears:

   ```bash
   ip link show can0
   ```

> If you want to use the U2C V2 as a **USB-CAN bridge running Klipper** (alternative mode), refer to [https://canbus.esoterical.online](https://canbus.esoterical.online) for the specific Klipper bridge firmware settings.

---

### MKS Monster 8 V1

The MKS Monster 8 V1 is a mainboard typically flashed via **microSD**. It can also act as a USB-CAN bridge for the CAN network.

**Processor:** STM32F407  
**Flash method:** microSD (for initial Katapult install) or USB DFU

#### Katapult `menuconfig` (MKS Monster 8 V1)

```
Micro-controller Architecture  →  STMicroelectronics STM32
Processor model                →  STM32F407
Build Katapult deployment application  →  Do not build
Clock Reference                →  8 MHz crystal
Communication interface        →  USB (for initial flash) or CAN bus
Application start offset       →  32KiB offset
```

#### Klipper `menuconfig` (MKS Monster 8 V1 — USB-CAN bridge mode)

```
Micro-controller Architecture  →  STMicroelectronics STM32
Processor model                →  STM32F407
Bootloader offset              →  32KiB bootloader
Clock Reference                →  8 MHz crystal
Communication interface        →  USB to CAN bus bridge (USB on PA11/PA12)
CAN bus speed                  →  1000000
```

> For the exact CAN TX/RX pins and microSD naming convention (`mks_monster8.bin` → rename to `Robin_nano_v3.bin` or similar), always check [https://canbus.esoterical.online](https://canbus.esoterical.online) and the MKS documentation.

---

## 7. Verifying the CAN Network

### List all CAN nodes

```bash
python3 ~/katapult/scripts/flashtool.py -i can0 -q
```

Expected output (example):

```
Resetting all bootloader node IDs...
Checking for Katapult nodes...
Detected UUID: aabbccddeeff, Application: Katapult
Detected UUID: 112233445566, Application: Klipper
```

### Check CAN interface statistics

```bash
ip -details -statistics link show can0
```

Look for `state UP` and low error counts.

---

## 8. Integrating with macro-builder

Once your boards are flashed with Katapult and Klipper, you can use **macro-builder** to manage future firmware builds and flash commands conveniently from the Klipper Web UI.

1. Follow the [macro-builder installation instructions](README.md).
2. Use the wizard to create `.config` files for each board:

   ```bash
   ~/macro-builder/tools/new_config_wizard.sh
   ```

3. Reference them in `~/printer_data/config/builder.cfg`:

   ```ini
   # Toolhead over CAN
   [klipper EBB36]
   name: EBB36
   config: ebb36_can.config
   out: ebb.bin
   type: can
   mcu_alias: toolhead
   flash terminal: gcode_shell

   # Mainboard via microSD
   [klipper MAIN]
   name: MAIN
   config: monster8.config
   out: mks_monster8.bin
   type: sd
   mcu_alias: main

   # Katapult update for toolhead (uses deployer.bin logic)
   [katapult EBB36]
   name: EBB36
   config: ebb36_can.config
   out: ebb_katapult.bin
   type: can
   mcu_alias: toolhead
   flash terminal: ssh
   ```

4. See [DOCUMENTATION.md](DOCUMENTATION.md) for the full `builder.cfg` reference.

---

## 9. Troubleshooting

| Problem | Likely cause | Solution |
|---|---|---|
| `can0` not found after connecting U2C | Candlelight not flashed or interface not brought up | Re-flash Candlelight; check `/etc/network/interfaces.d/can0` |
| `flashtool.py -q` shows no nodes | CAN bus not terminated or board not powered | Check 120 Ω termination resistors at both ends of the bus |
| DFU device not detected | Board not in DFU mode | Hold BOOT, tap RESET, release BOOT; check `lsusb` |
| Flashed `deployer.bin` but board won't boot | Wrong settings or wrong file for board | Use `katapult.bin` for a clean re-install via DFU |
| UUID changes after reflash | Normal behaviour | Update `canbus_uuid:` in `printer.cfg` |
| CAN errors / bus-off state | Bitrate mismatch or wiring issue | Ensure all nodes use the same bitrate (1 000 000 recommended) |

---

## 10. Credits

This guide is based on the excellent community documentation at:

> **[https://canbus.esoterical.online](https://canbus.esoterical.online)**

Many thanks to the authors and contributors of that resource for their thorough, board-specific CAN bus setup guides. If anything in this document is unclear or outdated, the original site is the authoritative reference.

Additional thanks to:
- **[Klipper](https://github.com/Klipper3d/klipper)** — the 3D printer firmware this all runs on.
- **[Katapult](https://github.com/Arksine/katapult)** — the bootloader that makes CAN flashing possible.
- The broader Klipper/Voron community for testing and documenting these workflows.
