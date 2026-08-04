#!/usr/bin/env bash

fatal() {
    echo '[fatal]' "$@" >&2
    exit 1
}

window() {
    local win_width win_height
    read -r win_height win_width < <(stty size 2>/dev/null || echo "0 80")
    echo "$win_width, $win_height"
    gum style \
        --foreground 212 --border-foreground 210 --border double \
        --align center --width "$((win_width - 2))" --height "$((win_height - 2))" \
        'hello world' 'this is a test'
}
