#!/usr/bin/env bash
#
# build_katapult.sh - Katapult bootloader build system
# Uses libbuilder.sh for common functionality
#

set -Eeuo pipefail

### === SCRIPT BASE DIR (main script) === ###
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### === SOURCE SHARED LIBRARY === ###
source "${BASE_DIR}/libbuilder.sh" || {
    echo "ERROR: Failed to load libbuilder.sh"
    exit 1
}

### === SCRIPT CONFIGURATION (after sourcing lib) === ###
readonly BUILD_TYPE="katapult"

# Repos and paths
readonly REPO_DIR="${HOME}/katapult"
readonly CFG_BASE="${BASE_DIR}/configs/katapult"
readonly OUT_DIR="${BASE_DIR}/artifacts/katapult"
readonly LOG_SUMMARY="${SYSTEM_DIR}/builder_katapult_last.txt"


### === SOURCE LIBRARY === ###
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/libbuilder.sh" || {
    echo "ERROR: Failed to load libbuilder.sh"
    exit 1
}

### === KATAPULT-SPECIFIC FUNCTIONS === ###

# Build a single Katapult target
build_katapult_target() {
    local name="$1"      # Configuration name
    local cfg="$2"       # Config file path
    local out_fixed="$3" # Output filename
    
    log_info "Building Katapult: $name"
    
    # Change to repository directory
    pushd "$REPO_DIR" >/dev/null
    
    # Clean previous build
    if ! make clean >/dev/null 2>&1; then
        log_warning "Make clean failed, continuing anyway..."
    fi
    
    # Resolve and validate config path
    local resolved_config
    resolved_config="$(resolve_config_path "$cfg" "$CFG_BASE")"
    validate_file "$resolved_config" "Katapult configuration"
    
    # Copy configuration and build
    cp -f "$resolved_config" .config || fatal_error "Failed to copy config"
    
    log_info "Running olddefconfig..."
    if ! make olddefconfig >/dev/null 2>&1; then
        log_warning "olddefconfig had warnings, continuing..."
    fi
    
    log_info "Compiling Katapult..."
    local cpu_cores
    cpu_cores="$(nproc)"
    if ! make -j"$cpu_cores" >/dev/null 2>&1; then
        fatal_error "Katapult compilation failed"
    fi
    
    # Verify output binary
    if [[ ! -f "out/katapult.bin" ]]; then
        fatal_error "Output binary not generated: out/katapult.bin"
    fi
    
    # Prepare artifacts
    local fixed_output="${OUT_DIR}/${out_fixed}"
    local date_stamp="$(get_current_date)"
    local git_hash="$(get_git_commit_hash "$REPO_DIR")"
    local versioned_output="$(generate_versioned_filename "$BUILD_TYPE" "$name" "$date_stamp" "$git_hash")"
    local versioned_path="${OUT_DIR}/${versioned_output}"
    
    # Remove existing fixed output and copy new binaries
    rm -f "$fixed_output"
    cp -f "out/katapult.bin" "$fixed_output" || fatal_error "Failed to copy fixed output"
    cp -f "out/katapult.bin" "$versioned_path" || fatal_error "Failed to copy versioned output"
    
    # Create checksum
    create_checksum "$versioned_path"
    
    popd >/dev/null
    
    log_success "Built: $name"
    log_info "  Fixed: $(basename "$fixed_output")"
    log_info "  Versioned: $(basename "$versioned_path")"
}

### === MAIN EXECUTION FUNCTION === ###

main() {
    log_info "Starting Katapult build process"
    
    # Initialize build environment
    ensure_directory "$OUT_DIR"
    ensure_directory "$(dirname "$LOG_SUMMARY")"
    
    # Parse builder configuration
    local sections=()
    declare -A builder_config
    parse_builder_config "$BUILD_TYPE" sections builder_config
    
    if [[ ${#sections[@]} -eq 0 ]]; then
        log_warning "No Katapult sections found in builder.cfg"
        exit 0
    fi
    
    log_info "Found ${#sections[@]} Katapult configuration(s)"
    
    # Build all targets
    for section in "${sections[@]}"; do
        local name="${builder_config[${section}.name]:-$section}"
        local config_file="${builder_config[${section}.config]:-}"
        local output_file="${builder_config[${section}.out]:-}"
        
        if [[ -z "$config_file" || -z "$output_file" ]]; then
            log_error "Section '$section' missing config or out parameter"
            continue
        fi
        
        build_katapult_target "$name" "$config_file" "$output_file"
    done
    
    # Parse printer configuration for flash commands
    declare -A can_uuid_map usb_serial_map can_label_map usb_label_map
    parse_printer_config can_uuid_map usb_serial_map can_label_map usb_label_map
    
    # Generate summary
    local summary_file
    summary_file="$(mktemp -t kata_summary.XXXXXX)"
    
    {
        echo
        echo "=== KATAPULT BOOTLOADERS READY ==="
        for section in "${sections[@]}"; do
            local name="${builder_config[${section}.name]:-$section}"
            local output_file="${builder_config[${section}.out]:-}"
            echo "${name}: ${OUT_DIR}/${output_file}"
        done
        
        echo
        echo "=== FLASH COMMANDS ==="
        for section in "${sections[@]}"; do
            local name="${builder_config[${section}.name]:-$section}"
            local output_file="${builder_config[${section}.out]:-}"
            local flash_type="${builder_config[${section}.type]:-can}"
            local flash_mode="${builder_config[${section}.flash_mode]:-ssh}"
            local aliases="${builder_config[${section}.aliases]:-}"
            
            local binary_path="${OUT_DIR}/${output_file}"
            generate_flash_commands "$name" "$binary_path" "$flash_type" "$flash_mode" \
                "$aliases" can_uuid_map usb_serial_map
            echo
        done
        
        echo
        echo "=== CLEANUP COMMANDS (keep last 10) ==="
        for section in "${sections[@]}"; do
            local name="${builder_config[${section}.name]:-$section}"
            echo "ls -1t ${OUT_DIR}/katapult-${name}-*.bin 2>/dev/null | tail -n +11 | xargs -r rm -f"
        done
    } > "$summary_file"
    
    # Save summary
    cp -f "$summary_file" "$LOG_SUMMARY"
    rm -f "$summary_file"
    
    log_success "Build summary saved to: $LOG_SUMMARY"
    log_info "Use 'BUILDER_KATAPULT_SHOW' in Mainsail to view commands"
}

### === SCRIPT ENTRY POINT === ###
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi