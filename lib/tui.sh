#!/usr/bin/env bash

window() {
    local scr_width="$1"
    local scr_height="$2"

    gum style \
        --foreground 212 --border-foreground 210 --border double \
        --align center --width "$((scr_width - 2))" --height "$((scr_height - 2))" \
        'hello world' 'this is a test'
}
