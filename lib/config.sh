#!/usr/bin/env bash

fatal() {
    echo '[fatal]' "$@" >&2
    exit 1
}

app_name="bashpad"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
config_dir="$config_home/$app_name"
config_file="$config_dir/$app_name.conf"

# Every configurable variable must appear here.
config_keys=(
    mode
    notes_dir
    editor
    theme
    file_extension
    show_hidden
    autosave
)

set_config_defaults() {
    # mode can only be CLI or TUI
    mode="TUI"

    notes_dir="$HOME/Documents/BashPad"
    editor="${EDITOR:-nano}"

    # An empty theme means follow the user's desktop theme.
    theme=""

    file_extension="note"
    show_hidden=false
    autosave=true
}

set_config_defaults

trim_value() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    REPLY="$value"
}

is_config_key() {
    local wanted_key="$1"
    local key

    for key in "${config_keys[@]}"; do
        [[ "$key" == "$wanted_key" ]] && return 0
    done

    return 1
}

validate_boolean() {
    case "$1" in
    true | false)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

validate_mode() {
    case "$1" in
    CLI | TUI)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

validate_notes_dir() {
    [[ -n "$1" ]]
}

validate_editor() {
    [[ -n "$1" ]]
}

validate_file_extension() {
    local value="$1"

    [[ -n "$value" ]] || return 1
    [[ "$value" != */* ]] || return 1

    return 0
}

validate_show_hidden() {
    validate_boolean "$1"
}

validate_autosave() {
    validate_boolean "$1"
}

validate_config_value() {
    local key="$1"
    local value="$2"
    local validator="validate_$key"

    # A validator is optional. Keys without one accept any value.
    if declare -F "$validator" >/dev/null; then
        "$validator" "$value"
        return
    fi

    return 0
}

create_default_config() {
    local key
    local value

    mkdir -p "$config_dir" ||
        fatal "could not create config directory: $config_dir"

    [[ -e "$config_file" ]] && return 0

    {
        printf '%s\n' '# BashPad configuration'
        printf '%s\n' '# Empty theme means follow the desktop theme.'
        printf '\n'

        for key in "${config_keys[@]}"; do
            value="${!key}"

            # Store paths beneath HOME using a portable $HOME prefix.
            case "$value" in
            "$HOME" | "$HOME"/*)
                value="\$HOME${value#"$HOME"}"
                ;;
            esac

            printf '%s=%s\n' "$key" "$value"
        done
    } >"$config_file" ||
        fatal "could not create config file: $config_file"
}

load_config() {
    local line
    local line_number=0
    local key
    local value

    # Reset values so calling load_config more than once is predictable.
    set_config_defaults

    [[ -f "$config_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))

        trim_value "$line"
        line="$REPLY"

        # Ignore blank lines and comments.
        [[ -z "$line" || "$line" == \#* ]] && continue

        [[ "$line" == *=* ]] ||
            fatal "$config_file:$line_number: expected key=value"

        key="${line%%=*}"
        value="${line#*=}"

        trim_value "$key"
        key="$REPLY"

        trim_value "$value"
        value="$REPLY"

        is_config_key "$key" ||
            fatal "$config_file:$line_number: unknown key: $key"

        # Remove matching outer quotes.
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi

        # Expand common home-directory forms without evaluating shell code.
        case "$value" in
        '$HOME'*)
            value="$HOME${value#\$HOME}"
            ;;
        '${HOME}'*)
            value="$HOME${value#\$\{HOME\}}"
            ;;
        '~' | '~/'*)
            value="$HOME${value#\~}"
            ;;
        esac

        validate_config_value "$key" "$value" ||
            fatal "$config_file:$line_number: invalid value for $key: $value"

        printf -v "$key" '%s' "$value"
    done <"$config_file"
}
