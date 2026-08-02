#!/usr/bin/env bash

fatal() {
    echo '[fatal]' "$@" >&2
    exit 1
}
