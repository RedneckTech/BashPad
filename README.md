# BashPad

A dual-mode note-taking app for the terminal, written in Bash.

## Features

**CLI mode** — full-featured command-line note manager:

- Write timestamped notes with optional tags
- List the N most recent notes across all or specific notebooks
- Full-text regex search
- Tag filtering on list and search
- Delete notes by index
- View stats (notebook count, note count, date range)
- List notebooks with entry counts
- Watch notebooks in real time with `tail -F`
- Edit notebooks in `$EDITOR`
- Pipe output to system clipboard (`-c`)
- Tab completion for flags, notebooks, and tags

**TUI mode** *(planned)* — terminal UI via [Charmbracelet Gum](https://github.com/charmbracelet/gum).

## Installation

```bash
git clone git@github.com:RedneckTech/BashPad.git
cd BashPad
ln -s "$PWD/bashpad" ~/.local/bin/bashpad
```

For tab completion, add to your `.bashrc`:

```bash
source "/path/to/BashPad/lib/cli.sh"
```

To enable TUI mode (optional):

```bash
# Install gum from Charmbracelet
# macOS:  brew install gum
# Arch:   pacman -S gum
# Nix:    nix-env -iA nixpkgs.gum
```

## Quick Start

```bash
# Create a config and run (defaults to TUI, falls back to CLI if gum is missing)
bashpad

# Or set mode to CLI explicitly in ~/.config/bashpad/bashpad.conf
# mode=CLI

# Write your first note
bashpad "deploy script needs error handling"

# List recent notes
bashpad -l 5
```

When `bashpad` runs without a config, it creates `~/.config/bashpad/bashpad.conf` with default values. The `mode` key controls whether the CLI or TUI launches.

## CLI Usage

```
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
  -w              Watch notes with tail -F
  -e              Open notebooks directory in $EDITOR (or single notebook with -f)
  -h              Show this help
```

### Examples

```bash
# Write a note (uses default "notes" notebook)
bashpad "fix timeout in deploy script"

# Write a tagged note to a specific notebook
bashpad -f work -t urgent "finish Q3 report"

# List last 5 notes
bashpad -l 5

# List only notes tagged "work"
bashpad -T work -l

# Search for "deploy" across all notebooks
bashpad -s deploy

# Delete the most recent note
bashpad -d 1

# Show stats
bashpad -S

# Watch all notebooks in real time
bashpad -w

# Copy last 5 notes to clipboard
bashpad -cl 5
```

## Configuration

BashPad stores its config at `$XDG_CONFIG_HOME/bashpad/bashpad.conf` (defaults to `~/.config/bashpad/bashpad.conf`). If the file doesn't exist, it's created with defaults on first run.

| Key              | Default                     | Description                              |
|------------------|-----------------------------|------------------------------------------|
| `mode`           | `TUI`                       | `CLI` or `TUI`                           |
| `notes_dir`      | `$HOME/Documents/BashPad`   | Directory where notes are stored         |
| `editor`         | `$EDITOR` or `nano`         | Editor for `-e` action                   |
| `theme`          | `""` (follow desktop)       | Theme setting *(TUI, planned)*            |
| `file_extension` | `note`                      | Extension for note files                 |
| `show_hidden`    | `false`                     | Show hidden notebooks *(TUI, planned)*    |
| `autosave`       | `true`                      | Auto-save edits *(TUI, planned)*          |

All config keys are validated on load (e.g., `mode` must be `CLI` or `TUI`, booleans must be `true` or `false`). Paths can use `$HOME`, `${HOME}`, or `~` and will be expanded.

## File Format

Notes are stored as `<name>.<extension>` files under `notes_dir`. Each note is a paragraph-separated record:

```
date: 2025-07-15T14:30:00-04:00
tag: work
deploy script needs error handling for timeout cases

date: 2025-07-15T15:00:00-04:00
tags are not inherited between records — each note stands alone

```

- `date:` is always present (ISO-8601, auto-generated)
- `tag:` is optional
- Records are separated by a blank line

## Dependencies

| Dependency | Required | Used For              |
|------------|----------|-----------------------|
| `bash`     | Yes      | Everything            |
| `awk`      | Yes      | List, search, delete, stats |
| `date`     | Yes      | Timestamps            |
| `tail`     | Yes      | Watch mode            |
| `gum`      | Optional | TUI mode              |
| `wl-copy`, `xclip`, or `pbcopy` | Optional | Clipboard (`-c`) |

## Contributing

Bug reports and pull requests are welcome on [GitHub Issues](https://github.com/RedneckTech/BashPad/issues).

PRs should target the `main` branch. Before submitting, run `shellcheck` against the `lib/` directory to catch issues early. Follow the conventions already in the codebase:

- Use `fatal()` (from `lib/config.sh`) for unrecoverable errors
- Use `set_config_defaults` followed by `load_config` for config state
- New config keys go in both the `config_keys` array and `set_config_defaults()`
- Add a `validate_<key>()` function for any key that needs type checking

## License

[GPLv3](LICENSE)
