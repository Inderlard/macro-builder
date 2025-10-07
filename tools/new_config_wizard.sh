#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- portable paths ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KLIP_REPO="${HOME}/klipper"
KATA_REPO="${HOME}/katapult"
DEST_KLIP="${SCRIPT_DIR}/configs/klipper"
DEST_KATA="${SCRIPT_DIR}/configs/katapult"

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

# ---------- run menuconfig with robust save detection ----------
TMP_CFG="$(mktemp -t mb_cfg.XXXXXX)"
cleanup() { rm -f "${TMP_CFG}" 2>/dev/null || true; }
trap cleanup EXIT

echo
echo "Launching '${bin_name} make menuconfig'..."
echo "Tips:"
echo "  • Configure your MCU options."
echo "  • Press 'S' to Save (choose a filename), then OK and Exit."
echo "  • If you quit with 'q' → 'Yes', some builds save to '.config' in the repo."
echo

pushd "${REPO}" >/dev/null

# Clean minimal to avoid stale config
${clean_cmd} >/dev/null 2>&1 || true

# Try to write to a temp file; if UI ignores KCONFIG_CONFIG, it will write to './.config'
KCONFIG_CONFIG="${TMP_CFG}" make menuconfig || {
  echo
  echo "ERROR: 'make menuconfig' failed."
  echo "If you saw a dialog error, install ncurses:"
  echo "  sudo apt-get update && sudo apt-get install -y libncurses5-dev whiptail"
  popd >/dev/null
  exit 1
}

# Prefer temp file; fallback to repo .config
if [[ -s "${TMP_CFG}" ]]; then
  SRC_CFG="${TMP_CFG}"
elif [[ -s ".config" ]]; then
  SRC_CFG="${REPO}/.config"
else
  popd >/dev/null
  echo
  echo "ERROR: No configuration was saved."
  echo "Please re-run and press 'S' (Save) before exiting."
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
  cat <<EOF
[katapult MY_MCU]
name: MY_MCU
config: ${outname}
out: my_mcu.bin
type: can
mcu_alias: my_mcu_alias_in_printer_cfg
# optional: mcu_alias1: another_alias
flash terminal: ssh   # or gcode_shell
EOF
fi

echo
echo "All done ✔"
