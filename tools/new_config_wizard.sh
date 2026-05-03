#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- portable paths ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KLIP_REPO="${HOME}/klipper"
KATA_REPO="${HOME}/katapult"
BUILD_CFG="${HOME}/printer_data/config/builder.cfg"

# ---------- resolve data dir (mirrors libbuilder get_data_dir logic) ----------
# Reads [configs] path: from builder.cfg; falls back to default outside the git repo.
DEFAULT_DATA_DIR="${HOME}/printer_data/config/macro-builder"

_get_data_dir() {
    local data_dir="" in_configs=false line=""
    if [[ -f "${BUILD_CFG}" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" ]] && continue
            local line_lower="${line,,}"
            if [[ "$line_lower" == "[configs]" ]]; then in_configs=true; continue; fi
            if [[ "$line" =~ ^\[.*\]$ ]]; then in_configs=false; continue; fi
            if $in_configs; then
                local key="${line%%:*}" val="${line#*:}"
                key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
                val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
                key="${key,,}"
                if [[ "$key" == "path" && -n "$val" ]]; then
                    data_dir="${val/#\~/${HOME}}"
                    break
                fi
            fi
        done < "${BUILD_CFG}"
    fi
    printf '%s' "${data_dir:-${DEFAULT_DATA_DIR}}"
}

DATA_DIR="$(_get_data_dir)"
DEST_KLIP="${DATA_DIR}/configs/klipper"
DEST_KATA="${DATA_DIR}/configs/katapult"

# ---------- helpers ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required."; exit 1; }; }
trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

need make
mkdir -p "${DEST_KLIP}" "${DEST_KATA}"

echo "==============================="
echo "  macro-builder: Config Wizard"
echo "==============================="
echo "Select target:"
echo "  1) Klipper"
echo "  2) Katapult"
echo

target=""
while [[ -z "${target}" ]]; do
  read -rp "Enter 1 or 2: " ans
  case "${ans}" in
    1) target="klipper" ;;
    2) target="katapult" ;;
    *) echo "Invalid choice. Try again."; ;;
  esac
done

if [[ "${target}" == "klipper" ]]; then
  REPO="${KLIP_REPO}"
  DEST="${DEST_KLIP}"
  [[ -d "${REPO}" ]] || { echo "ERROR: Klipper repo not found at ${REPO}"; exit 1; }
  clean_cmd="make distclean"
  bin_name="Klipper"
else
  REPO="${KATA_REPO}"
  DEST="${DEST_KATA}"
  [[ -d "${REPO}" ]] || { echo "ERROR: Katapult repo not found at ${REPO}"; exit 1; }
  clean_cmd="make clean"
  bin_name="Katapult"
fi

# ---------- run menuconfig ----------
echo
echo "Launching '${bin_name} make menuconfig'..."
echo "Tips:"
echo "  • Configure your MCU options."
echo "  • Save and Exit when done."
echo

# Ensure curses can detect the terminal (fixes 'setupterm: could not find terminal')
export TERM="${TERM:-xterm-256color}"

pushd "${REPO}" >/dev/null

# Clean minimal to avoid stale config
${clean_cmd} >/dev/null 2>&1 || true

# Run menuconfig; kconfiglib writes to .config in the repo
make menuconfig || {
  echo
  echo "ERROR: 'make menuconfig' failed."
  echo "If you saw a curses/terminal error, make sure you are running"
  echo "this script inside an interactive SSH session (not piped/automated)."
  echo "Also try: export TERM=xterm-256color"
  popd >/dev/null
  exit 1
}

if [[ -s ".config" ]]; then
  SRC_CFG="${REPO}/.config"
else
  popd >/dev/null
  echo
  echo "ERROR: No configuration was saved (.config not found)."
  echo "Please re-run and save before exiting menuconfig."
  exit 1
fi

popd >/dev/null

echo
echo "Menuconfig finished."
echo "Choose a filename to store your configuration under:"
echo "Examples: 'ebb36_can.config', 'main_mcu.config'"

valid_name='^[A-Za-z0-9._+-]+$'
outname=""
while [[ -z "${outname}" ]]; do
  read -rp "Config filename (saved into ${DEST}/): " outname
  outname="$(echo "${outname}" | trim)"
  outname="${outname##*/}"                 # strip any path
  [[ "${outname}" =~ ${valid_name} ]] || { echo "Invalid name. Use letters, numbers, '.', '_', '+', '-' only."; outname=""; continue; }
  [[ "${outname}" == *.config ]] || outname="${outname}.config"
  if [[ -e "${DEST}/${outname}" ]]; then
    read -rp "'${outname}' exists. Overwrite? [y/N]: " ow
    [[ "${ow}" =~ ^[Yy]$ ]] || { echo "Choose another name."; outname=""; continue; }
  fi
done

cp -f "${SRC_CFG}" "${DEST}/${outname}"

echo
echo "Saved: ${DEST}/${outname}"
echo

# ---------- builder.cfg snippet ----------
if [[ "${target}" == "klipper" ]]; then
  echo "You can reference this config in builder.cfg like:"
  echo
  cat <<EOF
[klipper MY_MCU]
name: MY_MCU
config: ${outname}
out: my_mcu.bin
type: usb   # or can or sd
mcu_alias: my_alias_in_printer_cfg
# optional: mcu_alias1: another_alias
flash terminal: ssh   # or gcode_shell
EOF
else
  echo "You can reference this Katapult config in builder.cfg like:"
  echo
  # outname without the .config extension, used as the base for the out field
  base_out="${outname%.config}"
  cat <<EOF
[katapult MY_MCU]
name: MY_MCU
config: ${outname}
out: ${base_out}.bin
type: can   # or usb
mcu_alias: my_mcu_alias_in_printer_cfg
# optional: mcu_alias1: another_alias
flash terminal: ssh   # or gcode_shell
EOF
fi

echo
echo "All done ✔"