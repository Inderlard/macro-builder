# macro-builder

Helper toolkit to **build and flash Klipper firmwares and Katapult bootloaders** from Mainsail (or SSH) using a single, user-friendly config file: `~/printer_data/config/builder.cfg`.

* Targets: **Klipper** (firmware) and **Katapult** (bootloader)
* Flash methods supported: **CAN** (Katapult), **USB** (Katapult), **microSD** (manual)
* Output: versioned artifacts under the repo’s `artifacts/` directory
* Optional: print **flash commands as SSH** lines or **as G-code** via `RUN_SHELL_COMMAND` (works from Mainsail buttons)

> Recommended environment: MainsailOS.

---

## Dependencies

* **(Klipper)[https://github.com/Klipper3d/klipper]** with the **`gcode_shell_command`** extra available
  (file: `~/klipper/klippy/extras/gcode_shell_command.py`)
* **(Katapult)[https://github.com/Arksine/katapult]** repository (for flashing tools and Katapult builds)
  (`~/katapult` with `scripts/flash_can.py` and `scripts/flashtool.py`)
* **G-Code Shell Command**
  (You can install it from (kiauh)[https://github.com/dw-0/kiauh] "4) [Advanced]" > "8) [G-Code Shell Command]")

> If either dependency is missing, the installer will stop and tell you how to fix it.

---


## Automatic Installation (recommended)
1. Clone this repo:

```bash
cd ~
git clone https://github.com/Inderlard/macro-builder
```

2. Ensure the scripts are executable:

```bash
chmod +x ~/macro-builder/build_klipper.sh
chmod +x ~/macro-builder/build_katapult.sh
chmod +x ~/macro-builder/tools/new_config_wizard.sh
chmod +x ~/macro-builder/tools/install.sh
```

3. Run the installer:

```bash
bash ~/macro-builder/tools/install.sh
```

4. Restart Klipper after install:

```bash
sudo systemctl restart klipper
```

---

## Manual Installation (advanced users)

1. Clone this repo:

```bash
cd ~
git clone https://github.com/Inderlard/macro-builder
```

2. Ensure the scripts are executable:

```bash
chmod +x ~/macro-builder/build_klipper.sh
chmod +x ~/macro-builder/build_katapult.sh
chmod +x ~/macro-builder/tools/new_config_wizard.sh
chmod +x ~/macro-builder/tools/install.sh
```

3. Create `~/printer_data/config/builder_macros.cfg` with (this configuration)[https://github.com/Inderlard/macro-builder/blob/main/examples/builder_macros.cfg]

> Optionally (recommaned) you can hide these two shell backends (not shown as buttons) in mainsail:
>   `FLASH_CAN` and `FLASH_USB` (type `gcode_shell_command`)

4. Include the macros at the **top** of `~/printer_data/config/printer.cfg`:

```ini
[include builder_macros.cfg]
```

5. Create `~/printer_data/config/builder.cfg` (or use the examples further below) describing what to build/flash.

6. Restart Klipper:

```bash
sudo systemctl restart klipper
```

---

## Moonraker update manager

```
[update_manager macro-builder]
type: git_repo
path: ~/macro-builder
origin: https://github.com/Inderlard/macro-builder
primary_branch: main
```

---

## What the Automatic Install Generates

* `~/printer_data/config/builder_macros.cfg`
  Exposes buttons/macros in Mainsail:

  * `BUILDER_KLIPPER_BUILD` / `BUILDER_KLIPPER_SHOW`
  * `BUILDER_KATAPULT_BUILD` / `BUILDER_KATAPULT_SHOW`
    And defines hidden backends:
  * `FLASH_CAN` (not a button)
  * `FLASH_USB` (not a button)

* `~/printer_data/config/builder.cfg`
  A single config file that **drives both builders** with commented examples for:

  * Klipper over **CAN**
  * Klipper via **microSD**
  * Katapult over **CAN**
  * (USB flashing supported via Katapult)

* Keeps your `printer.cfg` intact except for adding:

  ```ini
  [include builder_macros.cfg]
  ```

  at the top (backup is created).

---

## Wizard Usage (create `.config` files interactively)

Use the interactive assistant to create **Klipper** or **Katapult** `.config` files, just like KIAUH’s flow:

```bash
~/macro-builder/tools/new_config_wizard.sh
```

Flow:

1. Select **Klipper** or **Katapult**
2. The script launches `make menuconfig` in the proper repo
3. Configure your MCU options, **Save**, and Exit
4. Choose a filename (e.g. `ebb36_can.config` or `main_mcu.config`)
5. The file is stored in:

   * Klipper: `~/macro-builder/configs/klipper/`
   * Katapult: `~/macro-builder/configs/katapult/`

After that, reference it from `builder.cfg`.

> Tip: If you quit `menuconfig` with `q → Yes`, some builds save to `.config` in the repo; the wizard handles both cases.

---

## `builder.cfg` Configuration Guide

`builder.cfg` lives in `~/printer_data/config/builder.cfg`.
It drives **both** builders via section headers:

* `[klipper <NAME>]` → builds **Klipper firmware**
* `[katapult <NAME>]` → builds **Katapult bootloader**

**Fields (per section):**

* `name:` friendly label for artifacts
* `config:` a bare filename (searched under the repo:

  * `~/macro-builder/configs/klipper/` for `[klipper …]`
  * `~/macro-builder/configs/katapult/` for `[katapult …]`
    ) or a path (absolute, or relative to repo root)
* `out:` fixed output filename placed in `artifacts/klipper/` or `artifacts/katapult/`
* `type:` `can` | `usb` | `sd`
* `mcu_alias:` `mcu_alias1:` … aliases to match your `[mcu <alias>]` blocks in `printer.cfg`
  Use `main` to refer to the plain `[mcu]` (no alias)
* `flash terminal:` `ssh` | `gcode_shell`

  * `ssh` → prints Python commands you can paste in a shell
  * `gcode_shell` → prints `RUN_SHELL_COMMAND` lines you can send from Mainsail

**Example (edit to your needs):**

```ini
# --- Klipper over CAN (two toolheads, EBB36) ---
[klipper EBB36]
name: EBB36
config: ebb36_can.config
out: ebb.bin
type: can
mcu_alias: Fang1
mcu_alias1: Fang2
flash terminal: gcode_shell

# --- Klipper via microSD (mainboard) ---
[klipper MAIN]
name: MAIN
config: main_mcu.config
out: mks_monster8.bin
type: sd
mcu_alias: main
# flash terminal: (not applicable to sd)

# --- Katapult over CAN (toolheads) ---
[katapult EBB36]
name: EBB36
config: ebb36_can.config
out: ebb.bin
type: can
mcu_alias: Fang1
mcu_alias1: Fang2
flash terminal: ssh
```

**How to run from Mainsail:**

* `BUILDER_KLIPPER_BUILD` → compiles all `[klipper …]` sections and prints suggested flash commands
* `BUILDER_KLIPPERT_SHOW` → shows the last summary (`~/printer_data/system/builder_klipper_last.txt`)
* `BUILDER_KATAPULT_BUILD` / `BUILDER_KATAPULT_SHOW` → analogous for Katapult

**Flash command styles:**

* **SSH** (copy/paste into terminal):

  ```
  python3 ~/katapult/scripts/flash_can.py -i can0 -u <UUID> -f <bin>
  python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/<...> -f <bin>
  ```
* **From Mainsail via G-code**:

  ```
  RUN_SHELL_COMMAND CMD=FLASH_CAN  PARAMS="-i can0 -u <UUID> -f <bin>"
  RUN_SHELL_COMMAND CMD=FLASH_USB  PARAMS="-d /dev/serial/by-id/<...> -f <bin>"
  ```
* **microSD** (manual): the summary prints clear 1–2–3 steps

---

## Credits & License

* **Klipper** firmware — © Klipper3D project
* **Katapult** bootloader — © Arksine
* Inspiration for UX and flows — **KIAUH** by th33xitus and community
* **macro-builder** scripts and docs — © Contributors of this repository

This project is released under **GNU General Public License v3.0 (GPL-3.0)**.
You are free to use, modify, and distribute under the terms of the GPLv3. A copy of the license text should be included as `LICENSE` in the repository.

---

### Quick Troubleshooting

* “No configuration was saved” after `menuconfig`
  → Re-run the wizard and **press `S` (Save)** before exiting. The wizard also checks for repo `.config`.
* Mainsail doesn’t show flash backends as buttons
  → That’s intended: `FLASH_CAN` / `FLASH_USB` are `gcode_shell_command` (hidden). Use the BUILD/SHOW macros instead.
* CAN UUIDs or USB serial not detected
  → Ensure your `printer.cfg` has `[mcu <alias>]` sections with `canbus_uuid:` or `serial:` set. Use `mcu_alias:` keys in `builder.cfg` to match them.


