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

# --- User config root handling ([configs] path in builder.cfg) ---

# Expand "~" and environment variables in a path (user-controlled)
expand_path() {
    local p="$1"
    eval "echo ${p}"
}

# True/false: does builder.cfg contain a [configs] section?
has_configs_section() {
    [[ -f "$BUILD_CFG" ]] && grep -qi '^[[:space:]]*\[configs\][[:space:]]*$' "$BUILD_CFG"
}

# Parse builder.cfg and return the custom configs root if present,
# otherwise return sensible default: ~/printer_data/config/macro-builder/configs
get_configs_root() {
    local root="" in=0 line lower
    if [[ -f "$BUILD_CFG" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # strip comments & trim
            line="${line%%#*}"
            line="$(string_trim "$line")"
            [[ -z "$line" ]] && continue
            lower="$(string_to_lower "$line")"

            if [[ "$lower" =~ ^\[configs\]$ ]]; then
                in=1; continue
            fi
            # end of block on next header
            if ((in)) && [[ "$lower" =~ ^\[[^]]+\]$ ]]; then
                break
            fi
            if ((in)) && [[ "$lower" =~ ^path[[:space:]]*:[[:space:]]*.*$ ]]; then
                root="${line#*:}"
                root="$(string_trim "$root")"
                break
            fi
        done < "$BUILD_CFG"
    fi
    [[ -z "$root" ]] && root="${HOME_DIR}/printer_data/config/macro-builder/configs"
    echo "$(expand_path "$root")"
}

# Resolved user config roots (used by builders and wizard)
readonly CFG_USER_ROOT="$(get_configs_root)"
readonly CFG_USER_BASE_KLIPPER="${CFG_USER_ROOT}/klipper"
readonly CFG_USER_BASE_KATAPULT="${CFG_USER_ROOT}/katapult"

# Resolve config search order: absolute -> user_base/file -> repo_base/file
resolve_config_2tier() {
    local value="$1" ; local repo_base="$2" ; local user_base="$3"
    if [[ "$value" = /* ]]; then
        printf '%s' "$value"
    else
        if [[ -n "$user_base" && -f "${user_base}/${value}" ]]; then
            printf '%s/%s' "$user_base" "$value"
        else
            printf '%s/%s' "$repo_base" "$value"
        fi
    fi
}


# Build types
readonly BUILD_TYPE_KLIPPER="klipper"
readonly BUILD_TYPE_KATAPULT="katapult"

### === LOGGING AND OUTPUT FUNCTIONS === ###

# Color codes for pretty output
# --- Color setup (TTY-aware) ---
if [[ -z "${MB_FORCE_PLAIN:-}" && -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
  COLOR_RED='\033[0;31m'
  COLOR_GREEN='\033[0;32m'
  COLOR_YELLOW='\033[1;33m'
  COLOR_BLUE='\033[0;34m'
  COLOR_RESET='\033[0m'
else
  COLOR_RED=''; COLOR_GREEN=''; COLOR_YELLOW=''; COLOR_BLUE=''; COLOR_RESET=''
fi

# --- Logging (to stdout, not stderr) ---
log_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"; }
log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"; }
log_warning() { echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $1"; }
log_error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"; }
fatal_error() { log_error "$1"; exit 1; }


### === STRING MANIPULATION FUNCTIONS === ###

# Trim leading and trailing whitespace from a string
string_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "$str"
}

# Convert string to lowercase / uppercase
string_to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
string_to_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# Convert alias to safe tag (A-Za-z0-9 + underscores)
alias_to_tag() {
    local alias="$1"
    alias="${alias//[^A-Za-z0-9]/_}"
    string_to_upper "$alias"
}

### === PATH AND FILE OPERATIONS === ###

ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || fatal_error "Failed to create directory: $dir"
    fi
}

validate_file() {
    local file="$1" ; local label="${2:-file}"
    [[ -f "$file" ]] || fatal_error "$label not found: $file"
}

# Resolve config path: if "value" is an absolute path use it; if just a filename, search under base.
resolve_config_path() {
    local value="$1" ; local base="$2"
    if [[ "$value" = /* ]]; then
        printf '%s' "$value"
    else
        printf '%s/%s' "$base" "$value"
    fi
}


# Current date as DD_MM_YYYY
get_current_date() { date +'%d_%m_%Y'; }

# Git short hash (first 9 of HEAD)
get_git_commit_hash() {
    local repo="$1"
    (cd "$repo" && git rev-parse --short=9 HEAD 2>/dev/null) || echo "unknown"
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

### === BUILDER.CFG PARSER === ###
# Fills:
#   - sections_arr: array with section names for given build_type ("klipper"/"katapult")
#   - config_map:   assoc array with keys: "<SECTION>.name" | .config | .out | .type | .aliases | .flash_mode
parse_builder_config() {
    local build_type="$1"
    local -n sections_arr="$2"
    local -n config_map="$3"

    [[ -f "$BUILD_CFG" ]] || return 0

    local -A section_tracker=()
    local current_section=""
    local line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(string_trim "$line")"
        [[ -z "$line" ]] && continue

        # Section header like: [klipper NAME] or [katapult NAME]
        if [[ "${line,}" =~ ^\[(${build_type}[[:space:]]+([^\]]+))\]$ ]]; then
            current_section="${BASH_REMATCH[2]}"
            if [[ -z "${section_tracker[$current_section]:-}" ]]; then
                section_tracker["$current_section"]=1
                sections_arr+=("$current_section")
            fi
            continue
        fi

        # Any other header finishes current section
        if [[ "$line" =~ ^\[[^]]+\]$ ]]; then
            current_section=""
            continue
        fi
        [[ -z "$current_section" ]] && continue

        # key: value
        IFS=':' read -r key value <<< "$line"
        key="$(string_trim "$(string_to_lower "$key")")"
        value="$(string_trim "$value")"

        case "$key" in
            name|config|out|type)
                config_map["${current_section}.${key}"]="$value"
                ;;
            mcu_alias|mcu_alias*)
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

    # Normalize aliases list
    for section in "${sections_arr[@]}"; do
        local alias_key="${section}.aliases"
        if [[ -n "${config_map[$alias_key]:-}" ]]; then
            config_map["$alias_key"]="$(string_trim "${config_map[$alias_key]}")"
        fi
    done
}

### === PRINTER.CFG PARSER === ###
# Populates associative maps (all keys are lowercased aliases):
#   can_map[alias]      = canbus_uuid
#   usb_map[alias]      = /dev/serial/by-id/....
#   can_labels[alias]   = pretty label like "mcu alias"
#   usb_labels[alias]   = pretty label
parse_printer_config() {
    local -n _can_map="$1"    # name-ref (use different local name to avoid circular warnings)
    local -n _usb_map="$2"
    local -n _can_labels="$3"
    local -n _usb_labels="$4"

    [[ -f "$PRINTER_CFG" ]] || return 0

    local current_alias="" current_label="" line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(string_trim "$line")"
        [[ -z "$line" ]] && continue

        local line_lower="$(string_to_lower "$line")"

        # [mcu] or [mcu alias]
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
        [[ -z "$current_alias" ]] && continue

        if [[ "$line_lower" =~ ^canbus_uuid[[:space:]]*: ]]; then
            local uuid="$(string_trim "${line#*:}")"
            _can_map["$current_alias"]="$uuid"
            _can_labels["$current_alias"]="$current_label"
            continue
        fi
        if [[ "$line_lower" =~ ^serial[[:space:]]*: ]]; then
            local serial="$(string_trim "${line#*:}")"
            _usb_map["$current_alias"]="$serial"
            _usb_labels["$current_alias"]="$current_label"
            continue
        fi
    done < "$PRINTER_CFG"
}

### === VERSIONED ARTIFACT NAME === ###
generate_versioned_filename() {
    local build_type="$1" ; local name="$2" ; local date_stamp="$3" ; local git_hash="$4"
    printf '%s-%s-%s-%s.bin' "$build_type" "$name" "$date_stamp" "$git_hash"
}

### === FLASH COMMAND GENERATION === ###

# Pick proper Katapult USB flasher
_pick_usb_flasher() {
    if [[ -f "${HOME_DIR}/katapult/scripts/flash_usb.py" ]]; then
        printf 'flash_usb.py'
    else
        printf 'flashtool.py'
    fi
}

# Generate CAN flash command based on mode
generate_can_flash_command() {
    local mode="$1" uuid="$2" bin_file="$3" label="$4"
    if [[ "$mode" == "gcode_shell" ]]; then
        printf 'RUN_SHELL_COMMAND CMD=FLASH_CAN PARAMS="-i can0 -u %s -f %s"    # %s' "$uuid" "$bin_file" "$label"
    else
        printf 'python3 %s/katapult/scripts/flash_can.py -i can0 -u %s -f %s    # %s' "$HOME_DIR" "$uuid" "$bin_file" "$label"
    fi
}

# Generate USB flash command based on mode
generate_usb_flash_command() {
    local mode="$1" device="$2" bin_file="$3" label="$4"
    local flasher_script="$(_pick_usb_flasher)"
    if [[ "$mode" == "gcode_shell" ]]; then
        printf 'RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS="-d %s -f %s"    # %s' "$device" "$bin_file" "$label"
    else
        printf 'python3 %s/katapult/scripts/%s -d %s -f %s    # %s' "$HOME_DIR" "$flasher_script" "$device" "$bin_file" "$label"
    fi
}

# Generate flash commands summary for a build section
# NOTE: use different local names for namerefs to avoid "circular name reference" warnings.
generate_flash_commands() {
    local section_name="$1"
    local binary_path="$2"
    local flash_type="$3"
    local flash_mode="$4"
    local aliases_str="$5"
    local -n _can_map_ref="$6"
    local -n _usb_map_ref="$7"

    local mode_label="SSH"
    [[ "$flash_mode" == "gcode_shell" ]] && mode_label="GCODE"

    # to array
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
                    local uuid="${_can_map_ref[$alias_key]:-}"
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
                    local device="${_usb_map_ref[$alias_key]:-}"
                    if [[ -n "$device" ]]; then
                        generate_usb_flash_command "$flash_mode" "$device" "$binary_path" "$alias"
                        printf '\n'
                    else
                        printf '#   alias "%s": serial not found in printer.cfg\n' "$alias"
                        local tag="$(alias_to_tag "$alias")"
                        if [[ "$flash_mode" == "gcode_shell" ]]; then
                            printf 'RUN_SHELL_COMMAND CMD=FLASH_USB PARAMS="-d /dev/serial/by-id/{{%s_SERIAL}} -f %s"    # %s\n' "$tag" "$binary_path" "$alias"
                        else
                            local flasher_script="$(_pick_usb_flasher)"
                            printf 'python3 %s/katapult/scripts/%s -d /dev/serial/by-id/{{%s_SERIAL}} -f %s    # %s\n' "$HOME_DIR" "$flasher_script" "$tag" "$binary_path" "$alias"
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
