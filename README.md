# macro-builder

Helper toolkit to **build and flash Klipper firmwares and Katapult bootloaders** from UI (or SSH) using a single, user-friendly config file: `~/printer_data/config/builder.cfg`.

* Targets: **Klipper** (firmware) and **Katapult** (bootloader)
* Flash methods supported: **CAN** (Katapult), **USB** (Katapult), **microSD** (manual)
* Output: versioned artifacts under the repo’s `artifacts/` directory
* Optional: print **flash commands as SSH** lines or **as G-code** via `RUN_SHELL_COMMAND` (works from UI buttons)

> Recommended environment: MainsailOS.


> [!WARNING] 
> MCUs have a limited number of write cycles, so please bear this in mind; continuous updating is not recommended.
---

## Dependencies

* **[Klipper](https://github.com/Klipper3d/klipper)** with the **`gcode_shell_command`** extra available
  (file: `~/klipper/klippy/extras/gcode_shell_command.py`)
* **[Katapult](https://github.com/Arksine/katapult)** repository (for flashing tools and Katapult builds)
  (`~/katapult` with `scripts/flash_can.py` and `scripts/flashtool.py`)
* **G-Code Shell Command**
  (You can install it from [kiauh](https://github.com/dw-0/kiauh) "4) [Advanced]" > "8) [G-Code Shell Command]")

> If either dependency is missing, the installer will stop and tell you how to fix it.

---

## Disclaimer

The author(s) of this repository are not responsible for its use or any consequences that may arise from it.
If you download and use the repository, you do so at your own discretion and risk.

> [!WARNING] 
> This tool does not prevent you from making decisions, it just saves you work. For security reasons, scripts are not launched automatically.
> Please, always remember to check the commands and compare them with other guides.
> Also, always remember to verify that the board configuration is correct before compiling.
---


## Automatic Installation (recommended)
1. Clone this repo:

```bash
cd ~
git clone https://github.com/Inderlard/macro-builder
```

2. Run the installer:

```bash
bash ~/macro-builder/tools/install.sh
```

3. Restart Klipper after install:

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

2. Create `~/printer_data/config/builder_macros.cfg` with (this configuration)[https://github.com/Inderlard/macro-builder/blob/main/examples/builder_macros.cfg]

> Optionally (recommaned) you can hide these two shell backends (not shown as buttons) in UI:
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
  Exposes buttons/macros in Web UI:

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
  * `gcode_shell` → prints `RUN_SHELL_COMMAND` lines you can send from Web UI

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

**How to run from Web UI:**

* `BUILDER_KLIPPER_BUILD` → compiles all `[klipper …]` sections and prints suggested flash commands
* `BUILDER_KLIPPERT_SHOW` → shows the last summary (`~/printer_data/system/builder_klipper_last.txt`)
* `BUILDER_KATAPULT_BUILD` / `BUILDER_KATAPULT_SHOW` → analogous for Katapult

**Flash command styles:**

* **SSH** (copy/paste into terminal):

  ```
  python3 ~/katapult/scripts/flash_can.py -i can0 -u <UUID> -f <bin>
  python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/<...> -f <bin>
  ```
* **From Web UI via G-code**:

  ```
  RUN_SHELL_COMMAND CMD=FLASH_CAN  PARAMS="-i can0 -u <UUID> -f <bin>"
  RUN_SHELL_COMMAND CMD=FLASH_USB  PARAMS="-d /dev/serial/by-id/<...> -f <bin>"
  ```
* **microSD** (manual): the summary prints clear 1–2–3 steps

---

### Quick Troubleshooting

* “No configuration was saved” after `menuconfig`
  → Re-run the wizard and **press `S` (Save)** before exiting. The wizard also checks for repo `.config`.
* Web UI doesn’t show flash backends as buttons
  → That’s intended: `FLASH_CAN` / `FLASH_USB` are `gcode_shell_command` (hidden). Use the BUILD/SHOW macros instead.
* CAN UUIDs or USB serial not detected
  → Ensure your `printer.cfg` has `[mcu <alias>]` sections with `canbus_uuid:` or `serial:` set. Use `mcu_alias:` keys in `builder.cfg` to match them.


---

## Questions & Answers

**Q : What is the difference between macro-builder and UKAM?** \
A : UKAM is a great tool for keeping your klipper up to date. However, macro-builder does not aim to do exactly the same thing. Macro-builder focuses more on convenience and prioritises security above all else, i.e. it makes management easier for novice users through a more graphical interface. Macro-builder is still in development and has a long way to go before it can compare with tools such as UKAM. Although its objective is similar, its methods and target audience are different.

**Q : Is it absolutely necessary to use katapult even for USB?** \
A : Yes, at the moment the script only has this method, but we intend to add new forms in the future.

**Q: Why does macro-builder update katapult?** \
A : Tools such as UKAM decide not to update Katapult because there is no real reason to do so. And generally speaking, they are not wrong. Macro-builder supports loading Katapult for two reasons:
1. Flashing new boards.
When you purchase a new board, such as an EBB36 or others, it may be easier to add it to your configuration if you do not already have it and use macro-builder as a reliable tool to give it its first flash.
2. Critical or interesting updates.
At times, an update may be necessary (uncommon but not impossible). For these cases, you already have a tool that makes it easy, just as you already update Klipper.

**Q: Why macro-builder does not use rollback?** \
A: Macro-builder generates its own previous versions, does not verify the installed version, nor does it search for updates for Klipper or Katapult. This is because it aims to open the doors to experimenting more easily with configurations, allowing the user to flash a configuration and return to the last functional one if it fails.

**Q: How often should I update?** \
A: This is at your own discretion. Macro-builder is only a tool to facilitate and accommodate the work; you are the one who must decide when to load new firmware onto your boards and with what configuration.

---

## TODO

There are several things to do:
1. Add support for flashing all types of boards via USB.
2. Macro for "Build last working config --board --NbuildsBack"
3. Add pre-made klipper builds for well-known boards and configuration examples for each of them.
4. Add pre-made katapult builds for well-known boards and configuration examples for each of them (for first-time flashing and for updates).

---

## Aknowledgments

This script would not exist without [Klipper](https://github.com/Klipper3d/klipper), [Katapult](https://github.com/Arksine/katapult) and
[Moonraker](https://github.com/Arksine/moonraker). 
Many thanks to all contributors to these projects.

---

## Credits & License

* **Klipper** firmware — © Klipper3D project
* **Katapult** bootloader — © Arksine
* **Moonraker** Web API — © Arksine
* Inspiration for UX and flows — **KIAUH** by th33xitus and community
* **macro-builder** scripts and docs — © Contributors of this repository

This project is released under **GNU General Public License v3.0 (GPL-3.0)**.
You are free to use, modify, and distribute under the terms of the GPLv3. A copy of the license text should be included as `LICENSE` in the repository.

