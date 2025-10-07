#!/usr/bin/env bash
set -Eeuo pipefail

# === Portable paths ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINTER_CFG="${HOME}/printer_data/config/printer.cfg"
BUILD_CFG="${HOME}/printer_data/config/builder.cfg"

REPO_DIR="${HOME}/katapult"
CFG_BASE="${SCRIPT_DIR}/configs/katapult"
OUT_DIR="${SCRIPT_DIR}/artifacts/katapult"
LOG_SUMMARY="${HOME}/printer_data/system/builder_katapult_last.txt"

mkdir -p "${OUT_DIR}" "$(dirname "${LOG_SUMMARY}")"

# === Utils ===
trim(){ sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
resolve_cfg_path() {
  # Accepts bare filename (resolved under CFG_BASE), relative path (to repo root),
  # or absolute path. '~' is expanded to $HOME.
  local p="$1"; p="${p/#\~/$HOME}"
  if [[ "$p" == */* ]]; then
    [[ "$p" != /* ]] && printf '%s\n' "${SCRIPT_DIR}/$p" || printf '%s\n' "$p"
  else
    printf '%s/%s\n' "${CFG_BASE}" "$p"
  fi
}
print_can_cmd() { # mode uuid bin label
  local mode="$1" uuid="$2" bin="$3" label="$4"
  if [[ "$mode" == "gcode_shell" ]]; then
    echo "RUN_SHELL_COMMAND CMD=FLASH_CAN PARAMS=\"-i can0 -u ${uuid} -f ${bin}\"    # ${label}"
  else
    echo "python3 ${HOME}/katapult/scripts/flash_can.py -i can0 -u ${uuid} -f ${bin}    # ${label}"
  fi
}
print_usb_cmd() { # mode dev bin label
  local mode="$1" dev="$2" bin="$3" label="$4"
  if [[ "$mode" == "gcode_shell" ]]; then
    echo "RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS=\"-d ${dev} -f ${bin}\"    # ${label}"
  else
    echo "python3 ${HOME}/katapult/scripts/flashtool.py -d ${dev} -f ${bin}    # ${label}"
  fi
}

# === Version tagging ===
DATE="$(date +%d_%m_%Y)"
pushd "${REPO_DIR}" >/dev/null
GIT_HASH="$(git rev-parse --short HEAD || echo unknown)"
popd >/dev/null

build_one () {
  local name="$1" cfg="$2" out_fixed="$3"
  echo "==> Building Katapult ${name} ..."
  pushd "${REPO_DIR}" >/dev/null
  make clean
  local cfg_resolved; cfg_resolved="$(resolve_cfg_path "${cfg}")"
  [[ -f "${cfg_resolved}" ]] || { echo "[ERR] Missing config: ${cfg_resolved}"; popd >/dev/null; exit 1; }
  cp -f "${cfg_resolved}" .config
  make olddefconfig
  make -j"$(nproc)"
  [[ -f out/katapult.bin ]] || { echo "[ERR] out/katapult.bin was not generated"; popd >/dev/null; exit 1; }
  local dst_fixed="${OUT_DIR}/${out_fixed}"
  local dst_ver="${OUT_DIR}/katapult-${name}-${DATE}-${GIT_HASH}.bin"
  rm -f "${dst_fixed}"
  cp -f out/katapult.bin "${dst_fixed}"
  cp -f out/katapult.bin "${dst_ver}"
  sha256sum "${dst_ver}" > "${dst_ver}.sha256"
  popd >/dev/null
  echo "   -> ${dst_fixed}"
  echo "   -> ${dst_ver}"
}

# === Parse builder.cfg: ONLY [katapult ...] sections ===
declare -a SECTIONS=(); declare -A SEEN_SECTION
declare -A B_NAME B_CFG B_OUT B_TYPE B_ALIASES B_FLASHMODE
cur=""
while IFS= read -r raw || [[ -n "$raw" ]]; do
  raw="${raw%%#*}"; raw="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$raw" ]] && continue

  if [[ "${raw,,}" =~ ^\[katapult[[:space:]]+([^\]]+)\]$ ]]; then
    cur="${BASH_REMATCH[1]}"
    if [[ -z "${SEEN_SECTION[$cur]:-}" ]]; then SEEN_SECTION["$cur"]=1; SECTIONS+=("$cur"); fi
    continue
  fi
  # Any other header closes current [katapult ...] context
  if [[ "${raw}" =~ ^\[[^]]+\]$ ]]; then
    cur=""
    continue
  fi

  [[ -z "$cur" ]] && continue

  IFS=':' read -r k v <<<"$raw"
  k="$(echo "$k" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  v="$(echo "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$k" in
    name)   B_NAME["$cur"]="$v" ;;
    config) B_CFG["$cur"]="$v" ;;
    out)    B_OUT["$cur"]="$v" ;;
    type)   B_TYPE["$cur"]="$(echo "$v" | tr '[:upper:]' '[:lower:]')" ;;
    mcu_alias|mcu_alias*) B_ALIASES["$cur"]="$(printf '%s %s' "${B_ALIASES[$cur]:-}" "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" ;;
    flash\ terminal)
      v_low="$(echo "$v" | tr '[:upper:]' '[:lower:]')"
      [[ "$v_low" == "gcode_shell" || "$v_low" == "ssh" ]] || v_low="ssh"
      B_FLASHMODE["$cur"]="$v_low"
      ;;
  esac
done < "${BUILD_CFG}"

# === Build all katapult sections ===
for s in "${SECTIONS[@]}"; do build_one "${B_NAME[$s]:-$s}" "${B_CFG[$s]}" "${B_OUT[$s]}"; done

# === Index printer.cfg for alias->UUID/serial maps ===
declare -A CAN_BY_ALIAS CAN_LABEL USB_BY_ALIAS USB_LABEL
if [[ -f "${PRINTER_CFG}" ]]; then
  akey="" ; lbl=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | trim)"; [[ -z "$line" ]] && continue
    low="$(echo "$line" | tr '[:upper:]' '[:lower:]')"
    if [[ "$low" =~ ^\[(mcu)([[:space:]]+([^\]]+))?\]$ ]]; then
      if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
        alias_raw="$(echo "$line" | sed -E 's/^\[mcu[[:space:]]+//I; s/\]$//')"
        akey="$(echo "$alias_raw" | tr '[:upper:]' '[:lower:]')"; lbl="mcu ${alias_raw}"
      else akey="main"; lbl="mcu"; fi
      continue
    fi
    if echo "$low" | grep -Eq '^canbus_uuid[[:space:]]*:'; then
      uuid="$(echo "$line" | sed -E 's/^canbus_uuid[[:space:]]*:[[:space:]]*//I')"
      CAN_BY_ALIAS["$akey"]="$uuid"; CAN_LABEL["$akey"]="$lbl"; continue
    fi
    if echo "$low" | grep -Eq '^serial[[:space:]]*:'; then
      ser="$(echo "$line" | sed -E 's/^serial[[:space:]]*:[[:space:]]*//I')"
      USB_BY_ALIAS["$akey"]="$ser";  USB_LABEL["$akey"]="$lbl"; continue
    fi
  done < "${PRINTER_CFG}"
fi

# === Output ===
# --- Write summary to file, do not stream to console (avoids Mainsail reordering) ---
SUMMARY_FILE="$(mktemp -t mb_summary_kata.XXXXXX)"

{
  echo
  echo "=== BOOTLOADERS READY (KATAPULT) ==="
  for s in "${SECTIONS[@]}"; do
    echo "${B_NAME[$s]:-$s} : ${OUT_DIR}/${B_OUT[$s]}"
  done
  echo
  echo "=== KATAPULT FLASH COMMANDS (by aliases) ==="
for s in "${SECTIONS[@]}"; do
  name="${B_NAME[$s]:-$s}"
  outfile="${OUT_DIR}/${B_OUT[$s]}"
  type="${B_TYPE[$s]:-can}"
  mode="${B_FLASHMODE[$s]:-ssh}"
  read -r -a aliases <<<"${B_ALIASES[$s]:-}"

  case "$type" in
    can)
      mode_label="$([ "$mode" = "gcode_shell" ] && echo "GCODE" || echo "SSH")"
      echo "# [${name}] via CAN (${mode_label}):"
      ((${#aliases[@]}==0)) && echo "#   (Define at least one 'mcu_alias:' in builder.cfg)"
      for a in "${aliases[@]:-}"; do
        key="$(echo "$a" | tr '[:upper:]' '[:lower:]')"
        uuid="${CAN_BY_ALIAS[$key]:-}"
        if [[ -n "$uuid" ]]; then
          print_can_cmd "$mode" "$uuid" "$outfile" "$a"
        else
          echo "#   alias '${a}': UUID not found in printer.cfg"
          if [[ "$mode" == "gcode_shell" ]]; then
            echo "RUN_SHELL_COMMAND CMD=FLASH_CAN PARAMS=\"-i can0 -u <UUID_${a}> -f ${outfile}\""
          else
            echo "python3 ${HOME}/klipper/scripts/canbus_query.py can0"
            echo "python3 ${HOME}/katapult/scripts/flash_can.py -i can0 -u <UUID_${a}> -f ${outfile}"
          fi
        fi
      done
      echo
      ;;
    usb)
      mode_label="$([ "$mode" = "gcode_shell" ] && echo "GCODE" || echo "SSH")"
      echo "# [${name}] via USB (Katapult, ${mode_label}):"
      ((${#aliases[@]}==0)) && echo "#   (Define 'mcu_alias: main' or the exact alias)"
      for a in "${aliases[@]:-}"; do
        key="$(echo "$a" | tr '[:upper:]' '[:lower:]')"
        dev="${USB_BY_ALIAS[$key]:-}"
        if [[ -n "$dev" ]]; then
          print_usb_cmd "$mode" "$dev" "$outfile" "$a"
        else
          echo "#   alias '${a}': serial not found in printer.cfg"
          if [[ "$mode" == "gcode_shell" ]]; then
            echo "RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS=\"-d /dev/serial/by-id/<usb-...> -f ${outfile}\"    # ${a}"
          else
            echo "python3 ${HOME}/katapult/scripts/flash_usb.py -d /dev/serial/by-id/<usb-...> -f ${outfile}    # ${a}"
          fi
        fi
      done
      echo
      ;;
    sd)
      echo "# [${name}] via microSD (manual):"
      echo "1) Copy ${outfile} to the ROOT of a FAT32 microSD."
      echo "2) Insert the microSD into the board and power-cycle."
      echo "3) Many boards rename the file to .CUR after flashing."
      echo
      ;;
    *)
      echo "# [${name}] unknown type: ${type}"
      echo
      ;;
  esac
done
  echo
  echo "=== CLEANUP (keep last 10) ==="
  for s in "${SECTIONS[@]}"; do
    nm="${B_NAME[$s]:-$s}"
    echo "ls -1t ${OUT_DIR}/katapult-${nm}-*.bin 2>/dev/null | tail -n +11 | xargs -r rm -f   # ${nm}"
  done
} > "${SUMMARY_FILE}"

# Save as the “last” summary and keep console output minimal
mkdir -p "$(dirname "${LOG_SUMMARY}")"
cp -f "${SUMMARY_FILE}" "${LOG_SUMMARY}"
rm -f "${SUMMARY_FILE}"

echo "Summary saved to: ${LOG_SUMMARY}"
