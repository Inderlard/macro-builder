# DOCUMENTATION.md — `builder.cfg` Guide

`builder.cfg` is a single, human-readable file that tells **macro-builder** what to build and how to propose flashing it.
It drives **both** builders:

* **Klipper** firmware builder (`build_klipper.sh`)
* **Katapult** bootloader builder (`build_katapult.sh`)

Each builder reads only the sections that match its type.

---

## 1) Location & Format

* File path: `~/printer_data/config/builder.cfg`
* INI–style sections and key/value pairs
* Comments start with `#` (everything after `#` on a line is ignored)
* Keys are case-insensitive; values keep case
* Whitespace around `:` is ignored

Example:

```ini
# A comment
[klipper EBB36]
name: EBB36
config: ebb36_can.config
out: ebb.bin
type: can
mcu_alias: Fang1
mcu_alias1: Fang2
flash terminal: gcode_shell
```

---

## 2) Sections (Blocks)

You can define two kinds of sections:

* `[klipper <NAME>]` – build **Klipper** firmware
* `[katapult <NAME>]` – build **Katapult** bootloader

`<NAME>` is a human label used in messages and versioned filenames.

You may add as many sections as you need; each section is independent.

---

## 3) Keys (Arguments)

All keys are per-section.

| Key              | Required | Values / Meaning                                                                                                | Default |
| ---------------- | -------- | --------------------------------------------------------------------------------------------------------------- | ------- |
| `name`           | Yes      | Friendly label used in logs and versioned files. Typically matches the section’s `<NAME>`.                      | —       |
| `config`         | Yes      | A `.config` file for **menuconfig** output. See [4. Config path resolution](#4-config-path-resolution).         | —       |
| `out`            | Yes      | Fixed output filename placed in the builder’s `artifacts/` directory (e.g. `ebb.bin`, `mks_monster8.bin`).      | —       |
| `type`           | Optional | `can` | `usb` | `sd` — indicates **how the firmware will be flashed** (affects suggested commands only).        | `can`*  |
| `mcu_alias*`     | Often    | One or more aliases mapping to `[mcu <alias>]` blocks in **printer.cfg**. Use `main` to refer to plain `[mcu]`. | —       |
| `flash terminal` | Optional | `ssh` or `gcode_shell` — format for the **suggested flash commands**.                                           | `ssh`   |

You can add multiple alias lines: `mcu_alias:`, `mcu_alias1:`, `mcu_alias2:`…
Each alias will produce its own suggested flash command.

---

## 4) Config path resolution

`config:` accepts:

1. **Bare filename** (recommended)

   * For `[klipper …]`: resolved under `~/macro-builder/configs/klipper/`
   * For `[katapult …]`: resolved under `~/macro-builder/configs/katapult/`
2. **Relative path** to the repo root `~/macro-builder/` (e.g. `configs/klipper/my.config`)
3. **Absolute path** (e.g. `/home/pi/custom/my.config`)
4. `~` is expanded to `$HOME`

> Use the **wizard** to create configs interactively from ssh:
> `~/macro-builder/tools/new_config_wizard.sh`

---

## 5) Alias resolution against `printer.cfg`

The builders parse your `~/printer_data/config/printer.cfg` and collect:

* `canbus_uuid:` from `[mcu <alias>]` → used for **CAN** flashing
* `serial:` from `[mcu <alias>]` (e.g. `/dev/serial/by-id/...`) → used for **USB** flashing
* A special alias `main` refers to the base `[mcu]` section (no alias name)

**Your aliases in `builder.cfg` must match these `printer.cfg` aliases** (case-insensitive).
If an alias is not found, the summary will say so and propose a fallback command.

---

## 6) Output files

Each build writes two artifacts:

1. **Fixed link** (what you referenced in `out:`):

   * Klipper: `~/macro-builder/artifacts/klipper/<out>`
   * Katapult: `~/macro-builder/artifacts/katapult/<out>`
2. **Versioned copy**:

   * `klipper-<NAME>-DD_MM_YYYY-<git_hash>.bin`
   * `katapult-<NAME>-DD_MM_YYYY-<git_hash>.bin`
     plus a `.sha256` checksum

The summary also prints **cleanup commands** to keep only the last 10 versions per target.

---

## 7) Suggested flash commands

The builders don’t flash automatically; they **print** commands tailored to each section:

* For `type: can`

  * `ssh` mode:
    `python3 ~/katapult/scripts/flash_can.py -i can0 -u <UUID> -f <bin>`
  * `gcode_shell` mode (usable from Mainsail macros):
    `RUN_SHELL_COMMAND CMD=FLASH_CAN PARAMS="-i can0 -u <UUID> -f <bin>"`

* For `type: usb`

  * `ssh`:
    `python3 ~/katapult/scripts/flashtool.py -d /dev/serial/by-id/<...> -f <bin>`
  * `gcode_shell`:
    `RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS="-d /dev/serial/by-id/<...> -f <bin>"`

* For `type: sd`
  A short step-by-step: copy `<bin>` to microSD root (FAT32), insert, power-cycle; the file often renames to `.CUR`.

---

## 8) Minimal, Practical Examples

### A) Two toolheads over CAN (Klipper)

```ini
[klipper EBB36]
name: EBB36
config: ebb36_can.config
out: ebb.bin
type: can
mcu_alias: ebb1
mcu_alias1: ebb2
flash terminal: gcode_shell
```
> It is assumed that the name of mcu_alias is the same as that of printer.cfg
> [mcu <mcu_alias>] This is useful so that the script offers the command to flash with the address or UUID included for each board 

### B) Mainboard via microSD (Klipper)

```ini
[klipper MAIN]
name: MAIN
config: main_mcu.config
out: main_mcu.bin
type: sd
mcu_alias: main
# flash terminal: (not used for sd)
```
> In the main board [mcu] un printer.cfg, is imperative to set "mcu_alias: main"


### C) Bootloader for toolheads over CAN (Katapult)

```ini
[katapult EBB36]
name: EBB36
config: ebb36_can.config
out: ebb.bin
type: can
mcu_alias: ebb1
mcu_alias1: ebb1
flash terminal: ssh
```

---

## 9) Common pitfalls & tips

* **No UUID/serial found for an alias**
  Check your `printer.cfg` has `[mcu <alias>]` with `canbus_uuid:` (CAN) or `serial:` (USB).
  Use `main` to target the base `[mcu]` block.

* **Menuconfig configs**
  Use the wizard to create/update `.config` files interactively; it handles where menuconfig saves.

* **G-code vs SSH output**
  Per-section control via `flash terminal:`.
  `gcode_shell` prints `RUN_SHELL_COMMAND …` lines you can send from Mainsail.

* **Multiple sections**
  You can define many `[klipper …]` / `[katapult …]` blocks. Each produces its own artifacts and commands.

* **Safety**
  The builders only compile and print commands; you choose when/how to flash.
