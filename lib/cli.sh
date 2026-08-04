#!/usr/bin/env bash

notes_dir="${notes_dir:-$HOME/Notes}"
file_extension="${file_extension:-note}"
DEFAULT_NOTEBOOK="notes"

if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    c_dim='\033[2m' c_cyan='\033[36m' c_green='\033[32m'
    c_yellow='\033[33m' c_blue='\033[34m' c_bold='\033[1m'
    c_reset='\033[0m'
else
    c_dim= c_cyan= c_green= c_yellow= c_blue= c_bold= c_reset=
fi

note_usage() {
    cat <<EOF
Usage: note [OPTIONS] [text...]
       note "some note text"

Options:
  -l [N]          List last N notes (default 10)
  -s <keyword>    Search notes for keyword
  -t <tag>        Tag note with a category (use with note text)
  -T <tag>        Filter list/search to notes with this tag
  -f <name>       Notebook name (default: notes)
  -L              List notebooks with entry counts
  -p              Plain output (no headers or separators; pipe-friendly)
  -c              Copy list/search output to clipboard
  -d <N>          Delete the Nth most-recent note (1 = most recent)
  -S              Show stats (total notes, notebooks, date range)
  -w              Watch notes with tail -f
  -e              Open notebooks directory in \$EDITOR (or single notebook with -f)
  -h              Show this help

Notebooks live in \$notes_dir (~/Notes) as *.\${file_extension} files.
List/search scan all notebooks unless narrowed with -f.

Examples:
  note "deploy script needs error handling"
  note -t work "finish Q3 report"
  note -f work "weekly standup notes"
  note -l 5
  note -cl 5               copy last 5 notes to clipboard
  note -T work -l           list only notes tagged "work"
  note -s deploy
  note -d 1                 delete the most recent note
  note -S
  note -w
  note -e
EOF
}

_clipboard_cmd() {
    if command -v wl-copy &>/dev/null; then
        echo "wl-copy"
    elif command -v xclip &>/dev/null; then
        echo "xclip -selection clipboard"
    elif command -v pbcopy &>/dev/null; then
        echo "pbcopy"
    else
        echo ""
    fi
}

note() {
    if [[ ! -d "$notes_dir" ]] && ! mkdir -p "$notes_dir" 2>/dev/null; then
        echo "note: cannot create notes directory '$notes_dir'" >&2
        return 1
    fi

    local notebook="$DEFAULT_NOTEBOOK"
    local tag="" tag_filter=""
    local action="write"
    local list_count=10
    local search_term=""
    local delete_index=0
    local plain=0 clipboard=0

    OPTIND=1
    while getopts "l:s:t:T:f:d:LpSwech" opt; do
        case $opt in
        l)
            action="list"
            [[ "$OPTARG" =~ ^[0-9]+$ ]] && list_count="$OPTARG"
            ;;
        s)
            action="search"
            search_term="$OPTARG"
            ;;
        t) tag="$OPTARG" ;;
        T) tag_filter="$OPTARG" ;;
        f) notebook="$OPTARG" ;;
        d)
            action="delete"
            delete_index="$OPTARG"
            ;;
        L) action="notebooks" ;;
        p) plain=1 ;;
        S) action="stats" ;;
        w) action="watch" ;;
        e) action="edit" ;;
        c) clipboard=1 ;;
        h) action="help" ;;
        *)
            note_usage >&2
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ "$clipboard" -eq 1 && "$action" != "list" && "$action" != "search" ]] && action="list"
    [[ "$clipboard" -eq 1 ]] && plain=1

    if [[ -z "$notebook" || "$notebook" =~ / ]]; then
        echo "note: invalid notebook name '$notebook'" >&2
        return 1
    fi
    if ((list_count < 1)); then list_count=1; fi
    if [[ "$action" == "write" && "$#" -eq 0 ]]; then
        echo "note: no text provided" >&2
        note_usage >&2
        return 1
    fi
    if [[ "$action" == "search" && -z "$search_term" ]]; then
        echo "note: empty search term" >&2
        note_usage >&2
        return 1
    fi
    if [[ "$action" == "delete" ]]; then
        if [[ ! "$delete_index" =~ ^[0-9]+$ ]] || ((delete_index < 1)); then
            echo "note: delete requires a positive number (e.g. -d 1 for most recent)" >&2
            note_usage >&2
            return 1
        fi
    fi

    local single_file="$notes_dir/${notebook}.${file_extension}"

    # Build file list for read-only actions (list, search, delete, stats)
    local files=()
    if [[ "$action" != "write" && "$action" != "edit" && "$action" != "watch" && "$action" != "notebooks" ]]; then
        if [[ "$notebook" != "$DEFAULT_NOTEBOOK" ]]; then
            if [[ -f "$single_file" && -r "$single_file" ]]; then
                files=("$single_file")
            elif [[ -f "$single_file" ]]; then
                echo "note: unreadable '$single_file'" >&2
                return 1
            fi
        else
            for f in "$notes_dir"/*."${file_extension}"; do
                [[ -f "$f" && -r "$f" ]] && files+=("$f")
            done
        fi
    fi

    # ----- helpers -----

    _run_awk_filter() {
        # Shared awk preamble for tag_filter
        if [[ -n "$tag_filter" ]]; then
            echo "function has_tag(rec) { return rec ~ \"(^|\\n)tag: $tag_filter(\\n|\$)\" }"
        else
            echo "function has_tag(rec) { return 1 }"
        fi
    }

    _clipboard_output() {
        local clip_cmd
        clip_cmd=$(_clipboard_cmd)
        if [[ -z "$clip_cmd" ]]; then
            cat
            echo "note: no clipboard tool found (install wl-copy, xclip, or similar)" >&2
            return 1
        else
            tee >(eval "$clip_cmd" >/dev/null 2>&1)
            echo "note: copied to clipboard" >&2
        fi
    }

    _output_or_clip() {
        if [[ "$clipboard" -eq 1 ]]; then
            _clipboard_output
        else
            cat
        fi
    }

    # ----- actions -----

    case $action in
    write)
        if ! {
            echo "date: $(date --iso-8601=seconds)"
            [[ -n "$tag" ]] && echo "tag: $tag"
            echo "$@"
            echo ""
        } >>"$single_file"; then
            echo "note: failed to write to '$single_file'" >&2
            return 1
        fi
        ;;

    list)
        if ((${#files[@]} == 0)); then
            echo "(no notes)"
            return 0
        fi
        local list_output
        list_output=$(awk -v RS='' -v count="$list_count" -v plain="$plain" "
            $(_run_awk_filter)
            NF > 0 && has_tag(\$0) {
                dateline = \"\"
                if (match(\$0, /date: [^\n]+/))
                    dateline = substr(\$0, RSTART, RLENGTH)
                n++
                rec[n] = \$0
                fname[n] = FILENAME
                fnr[n] = FNR
                key[n] = dateline
            }
            END {
                if (n == 0) exit
                for (i = 1; i <= n; i++)
                    for (j = i + 1; j <= n; j++)
                        if (key[i] > key[j]) {
                            t = key[i]; key[i] = key[j]; key[j] = t
                            t = rec[i]; rec[i] = rec[j]; rec[j] = t
                            t = fname[i]; fname[i] = fname[j]; fname[j] = t
                            t = fnr[i]; fnr[i] = fnr[j]; fnr[j] = t
                        }
                start = (n > count) ? n - count + 1 : 1
                for (i = n; i >= start; i--) {
                    fn = fname[i]; sub(/.*\//, \"\", fn)
                    if (!plain) printf \"${c_cyan}### %s ###${c_reset}\\n\", fn
                    printf \"%s\\n\", rec[i]
                    if (!plain) printf \"${c_dim}---${c_reset}\\n\"
                    else if (i > start) printf \"\\n\"
                }
            }" "${files[@]}")
        if [[ -z "$list_output" ]]; then
            [[ -n "$tag_filter" ]] && echo "(no notes matching tag '${tag_filter}')" || echo "(no notes)"
        else
            printf '%s\n' "$list_output" | _output_or_clip
        fi
        ;;

    search)
        if ((${#files[@]} == 0)); then
            echo "(no notes)"
            return 0
        fi
        local output=""
        for f in "${files[@]}"; do
            [[ ! -f "$f" ]] && continue
            local chunk
            chunk=$(awk -v RS='' -v term="$search_term" -v plain="$plain" '
                BEGIN { first = 1 }
                '"$(_run_awk_filter)"'
                $0 ~ term && has_tag($0) {
                    if (plain && !first) printf "\n"
                    first = 0
                    fn = FILENAME; sub(/.*\//, "", fn)
                    if (!plain) printf "'"${c_cyan}"'### %s ###'"${c_reset}"'\n", fn
                    printf "%s\n", $0
                    if (!plain) printf "'"${c_dim}"'---'"${c_reset}"'\n"
                }' "$f")
            if [[ -n "$chunk" ]]; then
                [[ -n "$output" ]] && output+=$'\n'
                output+="$chunk"
            fi
        done
        if [[ -z "$output" ]]; then
            echo "No notes matching '${search_term}'"
            return 0
        fi
        output+=$'\n'
        if [[ "$clipboard" -eq 1 ]]; then
            printf '%s' "$output" | _clipboard_output
        else
            printf '%s' "$output"
        fi
        ;;

    delete)
        if ((${#files[@]} == 0)); then
            echo "(no notes)" >&2
            return 1
        fi
        local del_info
        del_info=$(awk -v RS='' -v target="$delete_index" "
            $(_run_awk_filter)
            NF > 0 && has_tag(\$0) {
                dateline = \"\"
                if (match(\$0, /date: [^\n]+/))
                    dateline = substr(\$0, RSTART, RLENGTH)
                n++
                rec[n] = \$0
                fname[n] = FILENAME
                fnr[n] = FNR
                key[n] = dateline
            }
            END {
                if (n == 0) exit
                for (i = 1; i <= n; i++)
                    for (j = i + 1; j <= n; j++)
                        if (key[i] > key[j]) {
                            t = key[i]; key[i] = key[j]; key[j] = t
                            t = rec[i]; rec[i] = rec[j]; rec[j] = t
                            t = fname[i]; fname[i] = fname[j]; fname[j] = t
                            t = fnr[i]; fnr[i] = fnr[j]; fnr[j] = t
                        }
                idx = n - target + 1
                if (idx < 1 || idx > n) exit
                printf \"%s\\037%d\", fname[idx], fnr[idx]
            }" "${files[@]}")

        if [[ -z "$del_info" ]]; then
            echo "note: no entry $delete_index to delete" >&2
            return 1
        fi

        local del_file="${del_info%%$'\037'*}"
        local del_fnr="${del_info##*$'\037'}"

        if ! awk -v RS='' -v idx="$del_fnr" '
            NF > 0 && NR != idx { print; printf "\n" }
            ' "$del_file" >"$del_file.tmp" 2>/dev/null; then
            echo "note: failed to delete entry from '$del_file'" >&2
            rm -f "$del_file.tmp"
            return 1
        fi
        mv "$del_file.tmp" "$del_file"
        echo "Deleted entry $delete_index from $(basename "$del_file")"
        ;;

    notebooks)
        local total=0
        for f in "$notes_dir"/*."${file_extension}"; do
            [[ -f "$f" ]] || continue
            local nb nb_count
            nb=$(basename "$f" ."${file_extension}")
            nb_count=$(awk -v RS='' 'NF > 0 { n++ } END { print n+0 }' "$f")
            ((total += nb_count))
            printf "${c_cyan}%-20s${c_reset} ${c_dim}(%d)${c_reset}\n" "$nb" "$nb_count"
        done
        if ((total == 0)); then
            echo "(no notebooks)"
        else
            echo ""
            printf "${c_dim}%d notebook%s, %d total note%s${c_reset}\n" \
                "$(find "$notes_dir" -maxdepth 1 -name "*.${file_extension}" -type f 2>/dev/null | wc -l)" \
                "$( (($(find "$notes_dir" -maxdepth 1 -name "*.${file_extension}" -type f 2>/dev/null | wc -l) == 1)) && echo "" || echo "s")" \
                "$total" \
                "$( ((total == 1)) && echo "" || echo "s")"
        fi
        ;;

    stats)
        if ((${#files[@]} == 0)); then
            echo "0 notes in 0 notebooks"
            return 0
        fi
        local nb_count
        nb_count=$(find "$notes_dir" -maxdepth 1 -name "*.${file_extension}" -type f 2>/dev/null | wc -l)
        awk -v RS='' -v nb="$nb_count" "
            NF > 0 {
                if (match(\$0, /date: [^\n]+/)) {
                    d = substr(\$0, RSTART+6, RLENGTH-6)
                    if (min_date == \"\" || d < min_date) min_date = d
                    if (d > max_date) max_date = d
                }
                n++
            }
            END {
                printf \"${c_bold}notebooks${c_reset}  %d\\n\", nb
                printf \"${c_bold}notes${c_reset}      %d\\n\", n
                if (n > 0) {
                    printf \"${c_bold}from${c_reset}       %s\\n\", min_date
                    printf \"${c_bold}to${c_reset}         %s\\n\", max_date
                }
            }" "${files[@]}"
        ;;

    watch)
        if [[ "$notebook" != "$DEFAULT_NOTEBOOK" ]]; then
            [[ ! -f "$single_file" ]] && touch "$single_file"
            exec tail -F "$single_file"
        else
            shopt -s nullglob
            local wfiles=("$notes_dir"/*."${file_extension}")
            shopt -u nullglob
            if ((${#wfiles[@]} == 0)); then
                echo "(no notebooks yet — create one with: note \"first note\")"
            else
                exec tail -F "${wfiles[@]}"
            fi
        fi
        ;;

    edit)
        local editor="${EDITOR:-${VISUAL:-$(command -v sensible-editor 2>/dev/null && echo 'sensible-editor' || echo 'vim')}}"
        if [[ "$notebook" != "$DEFAULT_NOTEBOOK" ]]; then
            [[ ! -f "$single_file" ]] && touch "$single_file"
            $editor "$single_file"
        else
            $editor "$notes_dir"
        fi
        ;;

    help) note_usage ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$@" ]]; then
    note "$@"
fi

# ----- completion -----
_note_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD - 1]}"
    local dir="${notes_dir:-$HOME/Notes}"

    case "$prev" in
    -f)
        local notebooks=()
        for f in "$dir"/*."${file_extension}"; do
            [[ -f "$f" ]] || continue
            notebooks+=($(basename "$f" ."${file_extension}"))
        done
        COMPREPLY=($(compgen -W "${notebooks[*]}" -- "$cur"))
        return
        ;;
    -T)
        local tags=()
        if compgen -G "$dir/*.${file_extension}" >/dev/null 2>&1; then
            tags=($(awk '/^tag: / { print $2 }' "$dir"/*."${file_extension}" 2>/dev/null | sort -u))
        fi
        COMPREPLY=($(compgen -W "${tags[*]}" -- "$cur"))
        return
        ;;
    -t)
        local tags=()
        if compgen -G "$dir/*.${file_extension}" >/dev/null 2>&1; then
            tags=($(awk '/^tag: / { print $2 }' "$dir"/*."${file_extension}" 2>/dev/null | sort -u))
        fi
        COMPREPLY=($(compgen -W "${tags[*]}" -- "$cur"))
        return
        ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-l -s -t -T -f -d -L -p -c -S -w -e -h" -- "$cur"))
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$@" ]]; then
    complete -F _note_complete note
fi
