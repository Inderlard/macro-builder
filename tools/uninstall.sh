#!/usr/bin/env bash
set -Eeuo pipefail

# === System paths (must match install.sh) ===
CFG_DIR="${HOME}/printer_data/config"
PRINTER_CFG="${CFG_DIR}/printer.cfg"
BUILDER_CFG="${CFG_DIR}/builder.cfg"
BUILDER_MACROS="${CFG_DIR}/builder_macros.cfg"
MB_DATA_DIR="${CFG_DIR}/macro-builder"

echo "== macro-builder uninstaller =="
echo

# -------------------------------------------------
# 1) Remove [include builder_macros.cfg] from printer.cfg
# -------------------------------------------------
if [[ -f "${PRINTER_CFG}" ]]; then
  if grep -qE '^\s*\[include\s+builder_macros\.cfg\]\s*$' "${PRINTER_CFG}"; then
    cp -f "${PRINTER_CFG}" "${PRINTER_CFG}.bak.$(date +%s)"
    sed -i '/^\s*\[include\s\+builder_macros\.cfg\]\s*$/d' "${PRINTER_CFG}"
    echo "[1/4] Removed '[include builder_macros.cfg]' from printer.cfg (backup created)."
  else
    echo "[1/4] '[include builder_macros.cfg]' not found in printer.cfg — nothing to remove."
  fi
else
  echo "[1/4] printer.cfg not found at '${PRINTER_CFG}' — skipping."
fi

# -------------------------------------------------
# 2) Remove builder_macros.cfg from user config
# -------------------------------------------------
if [[ -f "${BUILDER_MACROS}" ]]; then
  rm -f "${BUILDER_MACROS}"
  echo "[2/4] Removed builder_macros.cfg (${BUILDER_MACROS})."
else
  echo "[2/4] builder_macros.cfg not found — skipping."
fi

# -------------------------------------------------
# 3) Remove builder.cfg from user config
# -------------------------------------------------
if [[ -f "${BUILDER_CFG}" ]]; then
  rm -f "${BUILDER_CFG}"
  echo "[3/4] Removed builder.cfg (${BUILDER_CFG})."
else
  echo "[3/4] builder.cfg not found — skipping."
fi

# -------------------------------------------------
# 4) Remove macro-builder data directories (configs + artifacts)
# -------------------------------------------------
if [[ -d "${MB_DATA_DIR}" ]]; then
  rm -rf "${MB_DATA_DIR}"
  echo "[4/4] Removed data directory ${MB_DATA_DIR}/ (configs + artifacts)."
else
  echo "[4/4] Data directory '${MB_DATA_DIR}' not found — skipping."
fi

echo
echo "=== Uninstall complete ==="
echo "• printer.cfg:  '[include builder_macros.cfg]' line removed (if present)."
echo "• Removed:      ${BUILDER_MACROS}"
echo "• Removed:      ${BUILDER_CFG}"
echo "• Removed:      ${MB_DATA_DIR}/"
echo
echo "Restart Klipper to apply changes:"
echo "  sudo systemctl restart klipper"
