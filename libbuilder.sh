#!/usr/bin/env bash
#
# libbuilder.sh - Common library for Klipper/Katapult build system
# Centralizes shared functionality, parsing, and utilities
#

set -Eeuo pipefail

### === CONSTANTS AND GLOBAL CONFIGURATION === ###
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOME_DIR="${HOME}"

# Core system paths
readonly PRINTER_CFG="${HOME_DIR}/printer_data/config/printer.cfg"
readonly BUILD_CFG="${HOME_DIR}/printer_data/config/builder.cfg"
readonly SYSTEM_DIR="${HOME_DIR}/printer_data/system"

# Build types
readonly BUILD_TYPE_KLIPPER="klipper"
readonly BUILD_TYPE_KATAPULT="katapult"

### === LOGGING AND OUTPUT FUNCTIONS === ###

# Color codes for pretty output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1" >&2
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1" >&2
}

log_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $1" >&2
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
}

fatal_error() {
    log_error "$1"
    exit 1
}

### === STRING MANIPULATION FUNCTIONS === ###

# Trim leading and trailing whitespace from a string
string_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"  # Remove leading whitespace
    str="${str%"${str##*[![:space:]]}"}"  # Remove trailing whitespace
    printf '%s' "$str"
}

# Convert string to lowercase
string_to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase  
string_to_upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

# Convert alias to safe tag (alphanumeric + underscores)
alias_to_tag() {
    local alias="$1"
    # Replace non-alphanumeric characters with underscores
    alias="${alias//[^A-Za-z0-9]/_}"
    string_to_upper "$alias"
}

### === PATH AND FILE OPERATIONS === ###

# Ensure directory exists, create if needed
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || fatal_error "Failed to create directory: $dir"
    fi
}

# Resolve configuration path with multiple resolution strategies
resolve_config_path() {
    local raw_path="$1"
    local config_base="$2"
    
    # Expand tilde to home directory
    raw_path="${raw_path/#\~/$HOME_DIR}"
    
    if [[ "$raw_path" == */* ]]; then
        # Path contains slashes - could be relative or absolute
        if [[ "$raw_path" != /* ]]; then
            # Relative path - resolve from script directory
            printf '%s' "${SCRIPT_DIR}/${raw_path}"
        else
            # Absolute path - use as-is
            printf '%s' "$raw_path"
        fi
    else
        # Bare filename - resolve under config base directory
        printf '%s/%s' "$config_base" "$raw_path"
    fi
}

# Validate that file exists and is readable
validate_file() {
    local file_path="$1"
    local context="${2:-File}"
    
    if [[ ! -f "$file_path" ]]; then
        fatal_error "${context} not found: ${file_path}"
    fi
    
    if [[ ! -r "$file_path" ]]; then
        fatal_error "${context} not readable: ${file_path}"
    fi
}

### === CONFIGURATION PARSING === ###

# Parse builder.cfg for specific build type
parse_builder_config() {
    local build_type="$1"
    local -n sections_arr="$2"      # Reference to sections array
    local -n config_map="$3"        # Reference to config associative array
    
    # Clear references
    sections_arr=()
    declare -A section_tracker
    
    local current_section=""
    local line=""
    
    validate_file "$BUILD_CFG" "Builder configuration"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove comments and trim
        line="${line%%#*}"
        line="$(string_trim "$line")"
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Check for section headers
        if [[ "${line,,}" =~ ^\[(${build_type}[[:space:]]+([^\]]+))\]$ ]]; then
            current_section="${BASH_REMATCH[2]}"
            if [[ -z "${section_tracker[$current_section]:-}" ]]; then
                section_tracker["$current_section"]=1
                sections_arr+=("$current_section")
            fi
            continue
        fi
        
        # Any other section header closes current context
        if [[ "$line" =~ ^\[[^]]+\]$ ]]; then
            current_section=""
            continue
        fi
        
        # Skip if not in a relevant section
        [[ -z "$current_section" ]] && continue
        
        # Parse key:value pairs
        IFS=':' read -r key value <<< "$line"
        key="$(string_trim "$(string_to_lower "$key")")"
        value="$(string_trim "$value")"
        
        # Store in configuration map with section prefix
        case "$key" in
            name|config|out|type)
                config_map["${current_section}.${key}"]="$value"
                ;;
            mcu_alias|mcu_alias*)
                # Append to aliases list
                local alias_key="${current_section}.aliases"
                config_map["$alias_key"]="${config_map[$alias_key]:-} $value"
                ;;
            flash\ terminal)
                local mode="$(string_to_lower "$value")"
                if [[ "$mode" != "gcode_shell" && "$mode" != "ssh" ]]; then
                    mode="ssh"
                fi
                config_map["${current_section}.flash_mode"]="$mode"
                ;;
        esac
    done < "$BUILD_CFG"
    
    # Post-process aliases to trim and clean
    for section in "${sections_arr[@]}"; do
        local alias_key="${section}.aliases"
        if [[ -n "${config_map[$alias_key]:-}" ]]; then
            config_map["$alias_key"]="$(string_trim "${config_map[$alias_key]}")"
        fi
    done
}

# Parse printer.cfg for MCU information
parse_printer_config() {
    local -n can_map="$1"    # Reference for CAN UUIDs
    local -n usb_map="$2"    # Reference for USB serials
    local -n can_labels="$3" # Reference for CAN labels  
    local -n usb_labels="$4" # Reference for USB labels
    
    [[ -f "$PRINTER_CFG" ]] || return 0
    
    local current_alias=""
    local current_label=""
    local line=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(string_trim "$line")"
        [[ -z "$line" ]] && continue
        
        local line_lower="$(string_to_lower "$line")"
        
        # Detect [mcu] sections
        if [[ "$line_lower" =~ ^\[mcu([[:space:]]+([^\]]+))?\]$ ]]; then
            if [[ -n "${BASH_REMATCH[2]:-}" ]]; then
                current_alias="$(string_trim "${BASH_REMATCH[2]}")"
                current_alias="$(string_to_lower "$current_alias")"
                current_label="mcu ${current_alias}"
            else
                current_alias="main"
                current_label="mcu"
            fi
            continue
        fi
        
        # Skip if no MCU context
        [[ -z "$current_alias" ]] && continue
        
        # Extract CAN bus UUID
        if [[ "$line_lower" =~ ^canbus_uuid[[:space:]]*: ]]; then
            local uuid="$(string_trim "${line#*:}")"
            can_map["$current_alias"]="$uuid"
            can_labels["$current_alias"]="$current_label"
            continue
        fi
        
        # Extract serial device
        if [[ "$line_lower" =~ ^serial[[:space:]]*: ]]; then
            local serial="$(string_trim "${line#*:}")"
            usb_map["$current_alias"]="$serial"
            usb_labels["$current_alias"]="$current_label"
            continue
        fi
    done < "$PRINTER_CFG"
}

### === BUILD ARTIFACT MANAGEMENT === ###

# Generate versioned filename with date and git hash
generate_versioned_filename() {
    local build_type="$1"    # klipper or katapult
    local name="$2"          # Configuration name
    local date_stamp="$3"    # Date stamp
    local git_hash="$4"      # Git commit hash
    
    printf '%s-%s-%s-%s.bin' "$build_type" "$name" "$date_stamp" "$git_hash"
}

# Create checksum file for artifact
create_checksum() {
    local file_path="$1"
    local checksum_file="${file_path}.sha256"
    
    if sha256sum "$file_path" > "$checksum_file" 2>/dev/null; then
        log_info "Created checksum: $(basename "$checksum_file")"
    else
        log_warning "Failed to create checksum for: $(basename "$file_path")"
    fi
}

# Clean up old artifacts, keeping only specified number
cleanup_old_artifacts() {
    local artifacts_dir="$1"
    local pattern="$2"
    local keep_count="${3:-10}"
    
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$artifacts_dir" -name "$pattern" -type f -print0 2>/dev/null | sort -z)
    
    local total_files="${#files[@]}"
    if [[ $total_files -gt $keep_count ]]; then
        local files_to_remove=$((total_files - keep_count))
        log_info "Removing $files_to_remove old artifacts..."
        
        for ((i=0; i<files_to_remove; i++)); do
            rm -f "${files[$i]}"
            rm -f "${files[$i]}.sha256" 2>/dev/null || true
        done
    fi
}

### === FLASH COMMAND GENERATION === ###

# Generate CAN flash command based on mode
generate_can_flash_command() {
    local mode="$1"          # ssh or gcode_shell
    local uuid="$2"          # CAN UUID
    local bin_file="$3"      # Binary file path
    local label="$4"         # MCU label
    
    if [[ "$mode" == "gcode_shell" ]]; then
        printf 'RUN_SHELL_COMMAND CMD=FLASH_CAN PARAMS="-i can0 -u %s -f %s"    # %s' "$uuid" "$bin_file" "$label"
    else
        printf 'python3 %s/katapult/scripts/flash_can.py -i can0 -u %s -f %s    # %s' "$HOME_DIR" "$uuid" "$bin_file" "$label"
    fi
}

# Generate USB flash command based on mode  
generate_usb_flash_command() {
    local mode="$1"          # ssh or gcode_shell
    local device="$2"        # USB device
    local bin_file="$3"      # Binary file path
    local label="$4"         # MCU label
    
    # Determine which flasher to use
    local flasher_script="flashtool.py"
    if [[ -f "${HOME_DIR}/katapult/scripts/flash_usb.py" ]]; then
        flasher_script="flash_usb.py"
    fi
    
    if [[ "$mode" == "gcode_shell" ]]; then
        printf 'RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS="-d %s -f %s"    # %s' "$device" "$bin_file" "$label"
    else
        printf 'python3 %s/katapult/scripts/%s -d %s -f %s    # %s' "$HOME_DIR" "$flasher_script" "$device" "$bin_file" "$label"
    fi
}

# Generate flash commands summary for a build section
generate_flash_commands() {
    local section_name="$1"
    local binary_path="$2"
    local flash_type="$3"
    local flash_mode="$4"
    local aliases_str="$5"
    local -n can_uuid_map="$6"
    local -n usb_serial_map="$7"
    
    local mode_label=""
    if [[ "$flash_mode" == "gcode_shell" ]]; then
        mode_label="GCODE"
    else
        mode_label="SSH"
    fi
    
    # Convert aliases string to array
    local aliases=()
    if [[ -n "$aliases_str" ]]; then
        IFS=' ' read -r -a aliases <<< "$aliases_str"
    fi
    
    case "$flash_type" in
        can)
            printf '# [%s] via CAN (%s):\n' "$section_name" "$mode_label"
            if [[ ${#aliases[@]} -eq 0 ]]; then
                printf '#   (Define at least one mcu_alias in builder.cfg)\n'
            else
                for alias in "${aliases[@]}"; do
                    local alias_key="$(string_to_lower "$alias")"
                    local uuid="${can_uuid_map[$alias_key]:-}"
                    
                    if [[ -n "$uuid" ]]; then
                        generate_can_flash_command "$flash_mode" "$uuid" "$binary_path" "$alias"
                        printf '\n'
                    else
                        printf '#   alias "%s": UUID not found in printer.cfg\n' "$alias"
                        local tag="$(alias_to_tag "$alias")"
                        if [[ "$flash_mode" == "gcode_shell" ]]; then
                            printf 'RUN_SHELL_COMMAND CMD=FLASH_CAN PARAMS="-i can0 -u {{%s_UUID}} -f %s"\n' "$tag" "$binary_path"
                        else
                            printf 'python3 %s/klipper/scripts/canbus_query.py can0\n' "$HOME_DIR"
                            printf 'python3 %s/katapult/scripts/flash_can.py -i can0 -u {{%s_UUID}} -f %s\n' "$HOME_DIR" "$tag" "$binary_path"
                        fi
                    fi
                done
            fi
            ;;
            
        usb)
            printf '# [%s] via USB (%s):\n' "$section_name" "$mode_label"
            if [[ ${#aliases[@]} -eq 0 ]]; then
                printf '#   (Define mcu_alias: main or the exact alias)\n'
            else
                for alias in "${aliases[@]}"; do
                    local alias_key="$(string_to_lower "$alias")"
                    local device="${usb_serial_map[$alias_key]:-}"
                    
                    if [[ -n "$device" ]]; then
                        generate_usb_flash_command "$flash_mode" "$device" "$binary_path" "$alias"
                        printf '\n'
                    else
                        printf '#   alias "%s": serial not found in printer.cfg\n' "$alias"
                        local tag="$(alias_to_tag "$alias")"
                        if [[ "$flash_mode" == "gcode_shell" ]]; then
                            printf 'RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS="-d /dev/serial/by-id/{{%s_SERIAL}} -f %s"    # %s\n' "$tag" "$binary_path" "$alias"
                        else
                            printf 'python3 %s/katapult/scripts/flash_usb.py -d /dev/serial/by-id/{{%s_SERIAL}} -f %s    # %s\n' "$HOME_DIR" "$tag" "$binary_path" "$alias"
                        fi
                    fi
                done
            fi
            ;;
            
        sd)
            printf '# [%s] via microSD (manual):\n' "$section_name"
            printf '1) Copy %s to the ROOT of a FAT32 microSD.\n' "$binary_path"
            printf '2) Insert the microSD into the board and power-cycle.\n'
            printf '3) Many boards rename the file to .CUR after flashing.\n'
            ;;
            
        *)
            printf '# [%s] unknown flash type: %s\n' "$section_name" "$flash_type"
            ;;
    esac
}

### === DATE AND VERSION MANAGEMENT === ###

# Get current date in DD_MM_YYYY format
get_current_date() {
    date +%d_%m_%Y
}

# Get git commit hash from repository
get_git_commit_hash() {
    local repo_dir="$1"
    local hash="unknown"
    
    if [[ -d "$repo_dir" ]]; then
        pushd "$repo_dir" >/dev/null
        if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
            hash="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
        fi
        popd >/dev/null
    fi
    
    printf '%s' "$hash"
}