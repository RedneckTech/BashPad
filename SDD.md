# Software Design Document: note.sh

## 1. Overview

**note.sh** is a single-file, zero-dependency CLI note-taking tool written in Bash. It stores notes as plain text records in per-notebook `.note.txt` files under a configurable directory. Notes are timestamped, optionally tagged, and queryable via list, search, delete, and stats operations. A watch mode enables real-time monitoring, and an edit mode integrates with the user's preferred editor.

### Key Features

| Feature          | Description |
|------------------|-------------|
| Write            | Append a timestamped note to a notebook |
| List             | Show the N most recent notes across one or all notebooks |
| Search           | Full-text regex search across records |
| Tagging          | Assign tags to notes; filter list/search by tag |
| Delete           | Remove the N-th most recent note |
| Stats            | Aggregate note count, notebook count, and date range |
| Notebooks        | List all notebooks with entry counts |
| Watch            | `tail -F` one or all notebook files in real time |
| Edit             | Open a notebook or the notes directory in `$EDITOR` |
| Clipboard        | Pipe list/search output to the system clipboard |
| Tab Completion   | Bash programmable completion for flags, notebooks, and tags |

---

## 2. Architecture

### 2.1 Physical Structure

```
note.sh                  # single source file (455 lines)
├── Global config        # NOTES_DIR, DEFAULT_NOTEBOOK, color codes (lines 3–12)
├── note_usage()         # help text (lines 14–50)
├── _clipboard_cmd()     # detect available clipboard tool (lines 52–62)
├── note()               # main entry point (lines 64–412)
│   ├── Argument parsing (getopts loop, lines 79–108)
│   ├── Input validation (lines 114–135)
│   ├── File discovery   (lines 139–153)
│   ├── Helper functions (lines 158–186)
│   │   ├── _run_awk_filter()   # awk tag-filter preamble
│   │   ├── _clipboard_output() # tee to clipboard command
│   │   └── _output_or_clip()   # dispatch normal vs clipboard output
│   ├── Action dispatch  (case block, lines 190–411)
│   │   ├── write        (lines 191–201)
│   │   ├── list         (lines 203–245)
│   │   ├── search       (lines 247–282)
│   │   ├── delete       (lines 284–334)
│   │   ├── notebooks    (lines 336–355)
│   │   ├── stats        (lines 358–381)
│   │   ├── watch        (lines 384–397)
│   │   ├── edit         (lines 400–407)
│   │   └── help         (line 410)
│   └── End case
├── note "$@" invocation  # pass all CLI args into note() (line 414)
└── _note_complete()      # Bash completion function (lines 417–455)
    └── complete -F       # register completion for `note` command (line 455)
```

### 2.2 Execution Flow

```
CLI args → note() → getopts parse → input validation → file discovery → action dispatch → output
```

The script is **sourceable** (for completion) and **executable** (for direct use). The `note "$@"` call on line 414 is the sole top-level invocation, passing all CLI arguments into the `note()` function. The completion function `_note_complete()` is inert until Bash's `complete -F` registration triggers it.

### 2.3 Design Principles

- **Single-function monolith**: Everything lives inside `note()`, minimizing global state and making the script sourceable without side effects.
- **Pipe-oriented**: Actions produce output on stdout; clipboard integration wraps stdout with `tee`.
- **AWK as query engine**: List, search, delete, and stats all use `awk` with paragraph mode (`RS=''`) for record-oriented processing. No external databases.
- **No dependencies beyond POSIX**: Only `bash`, `awk`, `date`, `tail`, `touch`, `mkdir`, and optionally `wl-copy`/`xclip`/`pbcopy` are required.

---

## 3. Data Model

### 3.1 Storage Layout

```
$NOTES_DIR/                          # default: ~/Notes
├── notes.note.txt                   # default notebook
├── work.note.txt                    # user-created notebook
├── project-alpha.note.txt
└── ...
```

- `NOTES_DIR` is configurable via environment variable (line 3).
- Each notebook is a single file `<name>.note.txt`.
- The default notebook is `notes` (line 4).

### 3.2 Record Format

Notes are **paragraph-separated** records (blank line delimiter). Each record has this structure:

```
date: <ISO-8601 timestamp>
tag: <category>          ← optional, absent if no tag was given
<freeform note text>
                        ← trailing blank line terminates the record
```

**Example:**

```
date: 2025-07-15T14:30:00-04:00
tag: work
deploy script needs error handling for timeout cases

date: 2025-07-15T15:00:00-04:00
tags are not inherited between records — each note stands alone

```

**Constraints:**
- The `date:` line is always present (stamped by `date --iso-8601=seconds`).
- The `tag:` line is present only when `-t <tag>` is used at write time.
- A blank line always follows each record, acting as a paragraph separator (`\n\n`).
- Records are appended; the file grows monotonically unless a delete occurs.

### 3.3 Tag Semantics

- Tags are **flat strings** — no hierarchy or namespacing.
- A record can have at most one tag (write adds a single `tag: <value>` line).
- Tag filtering in list/search uses an awk function `has_tag()` that matches `tag: <value>` anywhere within the record.

---

## 4. Component Design

### 4.1 Argument Parsing (lines 79–136)

Uses `getopts` to process flags. All flags are optional and independent — there is no subcommand structure.

| Flag      | Type          | Sets              | Default |
|-----------|---------------|--------------------|---------|
| `-l [N]`  | optional arg  | `action=list`, `list_count=N` | 10 |
| `-s <kw>` | required arg  | `action=search`, `search_term=<kw>` | — |
| `-t <tag>`| required arg  | `tag=<tag>`        | —     |
| `-T <tag>`| required arg  | `tag_filter=<tag>` | —     |
| `-f <nb>` | required arg  | `notebook=<nb>`    | `notes` |
| `-d <N>`  | required arg  | `action=delete`, `delete_index=N` | — |
| `-L`      | boolean       | `action=notebooks` | —     |
| `-p`      | boolean       | `plain=1`          | 0     |
| `-S`      | boolean       | `action=stats`     | —     |
| `-w`      | boolean       | `action=watch`     | —     |
| `-e`      | boolean       | `action=edit`      | —     |
| `-c`      | boolean       | `clipboard=1`      | 0     |
| `-h`      | boolean       | `action=help`      | —     |

**Validation rules:**
- Notebook name must not contain `/` (line 114).
- `list_count` clamped to minimum 1 (line 118).
- Write action requires non-zero positional args (line 119).
- Search action requires non-empty search term (line 124).
- Delete action requires a positive integer index (line 130).

**Clipboard coercion (lines 111–112):** If `-c` is used but the action is not list or search, the action is force-set to `list`. Clipboard mode also forces `plain=1` to drop ANSI formatting.

### 4.2 File Discovery (lines 139–153)

For read-only actions (list, search, delete, stats), the script builds a `files` array:

- **Specific notebook** (`-f work`): Adds `$NOTES_DIR/work.note.txt` if it exists and is readable.
- **Default/all notebooks**: Globs `$NOTES_DIR/*.note.txt`, collecting all readable files.

Write, edit, watch, and notebooks actions do **not** use this array — they operate directly on `$single_file` or the directory glob.

### 4.3 Write Action (lines 191–201)

Appends a formatted record to `$single_file`:

```bash
{
    echo "date: $(date --iso-8601=seconds)"
    [[ -n "$tag" ]] && echo "tag: $tag"
    echo "$@"
    echo ""
} >> "$single_file"
```

The compound command `{ ... }` groups all writes into a single append-redirect, ensuring atomicity at the filesystem level for typical block sizes. The trailing blank line separates records.

### 4.4 List Action (lines 203–245)

**Algorithm:**

1. Awk reads all notebook files in paragraph mode (`RS=''`).
2. For each non-empty record where `has_tag()` returns true:
   - Extract the `date:` line.
   - Store the full record, filename, and date key in parallel arrays.
3. In the END block:
   - **Selection sort** the arrays by date key (ascending).
   - Output the `list_count` most recent entries (reverse iteration from `n` down to `start`).
4. Output formatting:
   - **Normal mode**: Each record is preceded by a cyan `### <filename> ###` header and followed by a dim `---` separator.
   - **Plain mode** (`-p`): Records separated by a blank line, no headers or ANSI codes.

**Performance note:** The selection sort is O(n²). For small note collections (< 1000 records) this is acceptable; for larger datasets it would benefit from pipeline-based sorting (`sort`).

### 4.5 Search Action (lines 247–282)

Iterates over each notebook file, running an awk script per file:

```awk
BEGIN { first = 1 }
$0 ~ term && has_tag($0) {
    if (plain && !first) printf "\n"
    first = 0
    # output record with optional header/separator
}
```

The search term is injected directly into the awk regex (`$0 ~ term`), meaning it supports POSIX extended regex syntax. Results are concatenated across notebooks and sent to stdout or clipboard.

### 4.6 Delete Action (lines 284–334)

**Two-pass algorithm:**

**Pass 1** — Locate the target record:
1. Awk collects all records sorted by date (same algorithm as list).
2. Computes `idx = n - target + 1` to map from "N-th most recent" to chronological index.
3. Outputs `<filename>\037<paragraph-number>` (using ASCII 31, the unit separator, as delimiter).

**Pass 2** — Remove and rewrite:
1. Awk reads the target file in paragraph mode.
2. Prints all records **except** the one at `paragraph-number`.
3. Output goes to a `.tmp` file.
4. On success, `mv` replaces the original.

**Atomicity:** The temp-file-and-rename strategy ensures the original file is not corrupted if awk fails mid-write.

**Error handling:** If no record exists at the given index (e.g., only 3 notes but `-d 5` is requested), pass 1 produces no output and the action fails with a message.

### 4.7 Notebooks Action (lines 336–355)

Enumerates all `.note.txt` files and counts records per file:

```bash
nb_count=$(awk -v RS='' 'NF > 0 { n++ } END { print n+0 }' "$f")
```

Output is a two-column table: notebook name (cyan) and entry count (dim). A summary footer shows total notebooks and total notes.

### 4.8 Stats Action (lines 358–381)

Uses awk to aggregate across all notebooks:

- Counts total records (`n`).
- Tracks `min_date` and `max_date` from the `date:` field in each record.

Output is a four-line key-value block:

```
notebooks  3
notes      47
from       2025-01-10T09:00:00-05:00
to         2025-07-15T18:30:00-04:00
```

### 4.9 Watch Action (lines 384–397)

Uses `exec tail -F` to replace the shell process:
- **Specific notebook**: `tail -F $NOTES_DIR/<nb>.note.txt`
- **All notebooks**: `tail -F $NOTES_DIR/*.note.txt` (nullglob guard prevents literal glob).

The `-F` flag (non-standard, GNU tail) follows by name, surviving log rotation. If no notebooks exist yet, a hint message is shown instead.

### 4.10 Edit Action (lines 400–407)

Opens the notebook file or notes directory in the user's preferred editor:

```
$EDITOR → $VISUAL → sensible-editor → vim
```

If the notebook doesn't exist, it is created with `touch` before opening.

### 4.11 Clipboard Integration (lines 52–62, 167–178)

`_clipboard_cmd()` probes for clipboard tools in order:
1. `wl-copy` (Wayland)
2. `xclip -selection clipboard` (X11)
3. `pbcopy` (macOS)

If none are found, output is still printed to stdout but a warning is emitted.

`_clipboard_output()` uses `tee >(clip_cmd)` to simultaneously print to stdout and pipe to clipboard, ensuring the user sees what was copied.

---

## 5. Key Algorithms

### 5.1 Record Boundary Detection

The script uses awk's **paragraph mode** (`RS=''`) to treat each note as a single record. Blank lines (`\n\n`) are record separators. This is the foundation for all query operations.

### 5.2 Date-Based Sorting (List, Delete)

In the list action's `END` block:

```
for (i = 1; i <= n; i++)
    for (j = i + 1; j <= n; j++)
        if (key[i] > key[j]) {
            # swap all parallel arrays
        }
```

This is an **in-place selection sort** operating on the date strings. ISO-8601 format ensures **lexicographic sorting equals chronological sorting**, so simple string comparison (`>`) is correct.

The sort is ascending; output iterates descending to show most recent first.

### 5.3 Tag Filtering

The `has_tag()` awk function is conditionally generated by `_run_awk_filter()`:

```awk
# When tag_filter is set:
function has_tag(rec) { return rec ~ "(^|\\n)tag: <value>(\\n|$)" }

# When no tag_filter:
function has_tag(rec) { return 1 }
```

The regex `(^|\n)tag: <value>(\n|$)` ensures the tag appears as a complete line within the record, not as a substring of another field. Since awk paragraph mode treats the entire record as `$0`, this regex effectively does multi-line matching.

### 5.4 Delete Index Mapping

The CLI uses 1-based "most recent first" indexing (`-d 1` = most recent note). Internally this is mapped to chronological position:

```
idx = n - target + 1
```

`fnr[idx]` (the awk FNR of the corresponding paragraph) is then used to identify which paragraph to remove.

---

## 6. Configuration

### 6.1 Environment Variables

| Variable    | Purpose                                       | Default               |
|-------------|-----------------------------------------------|-----------------------|
| `NOTES_DIR` | Directory containing `.note.txt` notebooks    | `$HOME/Notes`         |
| `NO_COLOR`  | Disable ANSI color codes (if set and non-empty) | —                   |
| `EDITOR`    | Text editor for `-e` action                    | (falls through chain) |
| `VISUAL`    | Alternative editor, checked after `EDITOR`     | —                     |

### 6.2 Editor Fallback Chain

```
$EDITOR → $VISUAL → sensible-editor → vim
```

`sensible-editor` is probed via `command -v` before falling back to `vim`.

---

## 7. Bash Completion

### 7.1 Registration

```bash
complete -F _note_complete note
```

Registered unconditionally when the script is sourced (e.g., via `source note.sh` in `.bashrc`).

### 7.2 Completion Logic (`_note_complete()`, lines 417–455)

| Context (`$prev`) | Completion Candidates   | Source           |
|-------------------|-------------------------|------------------|
| `-f`              | Notebook names          | Glob `*.note.txt`, strip extension |
| `-t` or `-T`      | Existing tag values     | `awk '/^tag: / { print $2 }'` across all notebooks, `sort -u` |
| Any flag (`-*`)   | All option flags        | Static list: `-l -s -t -T -f -d -L -p -c -S -w -e -h` |

Tag completion is **dynamic** — it parses all `.note.txt` files on each tab-press, extracting unique tag values. This is O(n) in total notes but acceptable for interactive use.

---

## 8. Error Handling Strategy

| Condition                              | Behavior                              |
|----------------------------------------|---------------------------------------|
| `$NOTES_DIR` doesn't exist             | `mkdir -p`, fatal if creation fails   |
| Notebook file unreadable               | Emit error to stderr, return 1        |
| Invalid notebook name (contains `/`)   | Emit error, return 1                  |
| Write fails (disk full, permissions)   | Emit error, return 1                  |
| Delete target out of range             | Emit error, return 1                  |
| Delete temp-file write fails           | Clean up `.tmp` file, emit error      |
| No clipboard tool found                | Print output anyway, emit warning     |
| Empty note list/search                 | Print "(no notes)" to stdout          |

All fatal errors go to stderr and return non-zero. Informational messages (empty results, clipboard copied) go to stderr so stdout remains pipe-safe for plain mode.

---

## 9. Dependencies

| Dependency   | Required | Used In                                    |
|--------------|----------|--------------------------------------------|
| `bash`       | Yes      | Entire script                              |
| `awk`        | Yes      | List, search, delete, stats, notebooks     |
| `date`       | Yes      | Write (timestamp)                          |
| `tail`       | Yes      | Watch                                      |
| `mkdir`      | Yes      | Directory initialization                   |
| `touch`      | Yes      | Edit (create file if missing)              |
| `mv`         | Yes      | Delete (temp file rename)                  |
| `tee`        | Yes      | Clipboard output                           |
| `wl-copy`    | Optional | Clipboard (Wayland)                        |
| `xclip`      | Optional | Clipboard (X11)                            |
| `pbcopy`     | Optional | Clipboard (macOS)                          |
| `sensible-editor` | Optional | Edit fallback                          |
| `vim`        | Optional | Edit last-resort fallback                  |

---

## 10. Limitations & Future Considerations

1. **Sorting performance**: The O(n²) selection sort in awk becomes noticeable above ~1000 records. A future optimization could use `sort -t $'\t'` in a pipeline.
2. **Single tag per note**: The flat `tag:` line supports only one tag. Multi-tag support would require a delimiter convention (e.g., `tag: work,urgent`).
3. **No note editing**: Notes can be appended or deleted, but an existing note's text cannot be modified in-place without `-e` (manual editing of the raw file).
4. **Concurrency**: Two concurrent writes to the same notebook are append-safe (O_APPEND semantics), but a delete + write race could lose data.
5. **GNU tail dependency**: The `-F` flag in watch mode is GNU-specific; it will fail on BSD/macOS `tail`.
6. **No encryption or access control**: Notebook files are plain text with filesystem permissions only.
