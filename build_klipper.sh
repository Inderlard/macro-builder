#!/usr/bin/env bash
#
# build_klipper.sh - Klipper firmware build system
# Uses libbuilder.sh for common functionality
#

set -Eeuo pipefail

# Merge stderr into stdout so UI prints in order
exec 2>&1


### === SCRIPT BASE DIR (main script) === ###
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### === SOURCE SHARED LIBRARY === ###
# libbuilder define sus propias constantes (incl. SYSTEM_DIR, PRINTER_CFG, etc.)
source "${BASE_DIR}/libbuilder.sh" || {
    echo "ERROR: Failed to load libbuilder.sh"
    exit 1
}

### === SCRIPT CONFIGURATION (after sourcing lib) === ###
readonly BUILD_TYPE="klipper"

# Repos and paths
readonly REPO_DIR="${HOME}/klipper"
readonly LOG_SUMMARY="${SYSTEM_DIR}/builder_klipper_last.txt"

# User data lives outside the git repo to keep Moonraker happy
DATA_DIR="$(get_data_dir)"
readonly CFG_BASE="${DATA_DIR}/configs/klipper"
readonly OUT_DIR="${DATA_DIR}/artifacts/klipper"


### === KLIPPER-SPECIFIC FUNCTIONS === ###

# Build a single Klipper target
build_klipper_target() {
    local name="$1"          # Configuration name
    local cfg="$2"           # Config file path
    local out_fixed="$3"     # Output filename
    local rename_binary="$4" # Optional: rename final binary (without .bin extension)
    
    log_info "Building Klipper: $name"
    
    # Change to repository directory
    pushd "$REPO_DIR" >/dev/null
    
    # Clean previous build (distclean for Klipper)
    if ! make distclean >/dev/null 2>&1; then
        log_warning "Make distclean failed, continuing anyway..."
    fi
    
    # Resolve and validate config path
    local resolved_config
    resolved_config="$(resolve_config_path "$cfg" "$CFG_BASE")"
    validate_file "$resolved_config" "Klipper configuration"
    
    # Copy configuration and build
    cp -f "$resolved_config" .config || fatal_error "Failed to copy config"
    
    log_info "Running olddefconfig..."
    if ! make olddefconfig >/dev/null 2>&1; then
        log_warning "olddefconfig had warnings, continuing..."
    fi
    
    log_info "Compiling Klipper..."
    local cpu_cores
    cpu_cores="$(nproc)"
    if ! make -j"$cpu_cores" >/dev/null 2>&1; then
        fatal_error "Klipper compilation failed"
    fi
    
    # Verify output binary
    if [[ ! -f "out/klipper.bin" ]]; then
        fatal_error "Output binary not generated: out/klipper.bin"
    fi
    
    # Prepare artifacts
    local fixed_output="${OUT_DIR}/${out_fixed}"
    local date_stamp="$(get_current_date)"
    local git_hash="$(get_git_commit_hash "$REPO_DIR")"
    local versioned_output="$(generate_versioned_filename "$BUILD_TYPE" "$name" "$date_stamp" "$git_hash")"
    local versioned_path="${OUT_DIR}/${versioned_output}"
    
    # Remove existing fixed output and copy new binaries
    rm -f "$fixed_output"
    cp -f "out/klipper.bin" "$fixed_output" || fatal_error "Failed to copy fixed output"
    cp -f "out/klipper.bin" "$versioned_path" || fatal_error "Failed to copy versioned output"
    
    # Create checksum
    create_checksum "$versioned_path"
    
    # Rename final binary if rename_binary is set
    if [[ -n "$rename_binary" ]]; then
        local renamed_output="${OUT_DIR}/${rename_binary}.bin"
        cp -f "$fixed_output" "$renamed_output" || fatal_error "Failed to create renamed binary: $renamed_output"
        log_info "  Renamed: $(basename "$renamed_output")"
    fi
    
    popd >/dev/null
    
    log_success "Built: $name"
    log_info "  Fixed: $(basename "$fixed_output")"
    log_info "  Versioned: $(basename "$versioned_path")"
    [[ -n "$rename_binary" ]] && log_info "  SD-ready: ${rename_binary}.bin"
}

### === MAIN EXECUTION FUNCTION === ###

main() {
    log_info "Starting Klipper build process"
    
    # Initialize build environment
    ensure_directory "$OUT_DIR"
    ensure_directory "$(dirname "$LOG_SUMMARY")"
    
    # Parse builder configuration
    local sections=()
    declare -A builder_config
    parse_builder_config "$BUILD_TYPE" sections builder_config
    
    if [[ ${#sections[@]} -eq 0 ]]; then
        log_warning "No Klipper sections found in builder.cfg"
        exit 0
    fi
    
    log_info "Found ${#sections[@]} Klipper configuration(s)"
    
    # Build all targets
    for section in "${sections[@]}"; do
        local name="${builder_config[${section}.name]:-$section}"
        local config_file="${builder_config[${section}.config]:-}"
        local output_file="${builder_config[${section}.out]:-}"
        local rename_binary="${builder_config[${section}.rename_binary]:-}"
        
        if [[ -z "$config_file" || -z "$output_file" ]]; then
            log_error "Section '$section' missing config or out parameter"
            continue
        fi
        
        build_klipper_target "$name" "$config_file" "$output_file" "$rename_binary"
    done
    
    # Parse printer configuration for flash commands
    declare -A can_uuid_map usb_serial_map can_label_map usb_label_map
    parse_printer_config can_uuid_map usb_serial_map can_label_map usb_label_map
    
    # Generate summary
    local summary_file
    summary_file="$(mktemp -t klip_summary.XXXXXX)"
    
    {
        echo
        echo "=== KLIPPER FIRMWARES READY ==="
        for section in "${sections[@]}"; do
            local name="${builder_config[${section}.name]:-$section}"
            local output_file="${builder_config[${section}.out]:-}"
            local rename_binary="${builder_config[${section}.rename_binary]:-}"
            if [[ -n "$rename_binary" ]]; then
                echo "${name}: ${OUT_DIR}/${rename_binary}.bin  (renamed from ${output_file})"
            else
                echo "${name}: ${OUT_DIR}/${output_file}"
            fi
        done
        
        echo
        echo "=== FLASH COMMANDS ==="
        for section in "${sections[@]}"; do
            local name="${builder_config[${section}.name]:-$section}"
            local output_file="${builder_config[${section}.out]:-}"
            local rename_binary="${builder_config[${section}.rename_binary]:-}"
            local flash_type="${builder_config[${section}.type]:-can}"
            local flash_mode="${builder_config[${section}.flash_mode]:-ssh}"
            local aliases="${builder_config[${section}.aliases]:-}"
            
            # Use renamed binary path for flash commands if rename_binary is set
            local effective_filename="${output_file}"
            if [[ -n "$rename_binary" ]]; then
                effective_filename="${rename_binary}.bin"
            fi
            local binary_path="${OUT_DIR}/${effective_filename}"
            
            # For SD type with rename_binary, add explicit SD instructions
            if [[ "$flash_type" == "sd" && -n "$rename_binary" ]]; then
                printf '# [%s] via microSD (manual):\n' "$name"
                printf '# NOTA: Esta placa requiere el nombre de archivo exacto "%s.bin"\n' "$rename_binary"
                printf '1) Copia %s a la RAÍZ de una microSD FAT32.\n' "$binary_path"
                printf '   El archivo DEBE llamarse "%s.bin" para que la placa lo reconozca.\n' "$rename_binary"
                printf '2) Inserta la microSD en la placa y haz power-cycle.\n'
                printf '3) Muchas placas renombran el archivo a .CUR tras flashear.\n'
                echo
            else
                generate_flash_commands "$name" "$binary_path" "$flash_type" "$flash_mode" \
                    "$aliases" can_uuid_map usb_serial_map
                echo
            fi
        done
        
        echo
        echo "=== ARTIFACT CLEANUP (keeping last 10 per target) ==="
        for section in "${sections[@]}"; do
            local name="${builder_config[${section}.name]:-$section}"
            cleanup_old_artifacts "$OUT_DIR" "klipper-${name}-*.bin" 10
        done
    } > "$summary_file"
    
    # Save summary
    cp -f "$summary_file" "$LOG_SUMMARY"
    rm -f "$summary_file"
    
    log_success "Build summary saved to: $LOG_SUMMARY"
    log_info "Use 'BUILDER_KLIPPER_SHOW' in UI to view commands"
}

### === SCRIPT ENTRY POINT === ###
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi