#! /bin/sh

# schmerdr — paths, help text, and small internal helpers.
# ROOT_DIR is set by schmerdr.sh (the dir this repo lives in) before sourcing.

: "${ROOT_DIR:="$HOME/Documents/Repos/schmerdr"}"
# Layouts are user data: keep them in a writable dir independent of the install
# location, so a read-only (e.g. Homebrew) install still supports `schmerdr new`.
# Override with SCHMERDR_LAYOUTS.
LAYOUT_ROOT="${SCHMERDR_LAYOUTS:-${XDG_CONFIG_HOME:-$HOME/.config}/schmerdr/layouts}"

# herdr binary — override with HERDR=/path/to/herdr if not on PATH.
HERDR="${HERDR:-herdr}"

# Version — keep in sync with the git tag / Homebrew formula on each release.
SCHMERDR_VERSION="0.2.1"

# show_version : print just the version (for `schmerdr --version` / `-v`).
show_version() { printf 'schmerdr %s\n' "$SCHMERDR_VERSION"; }

show_help() {
  cat <<EOF
schmerdr $SCHMERDR_VERSION — template-driven workspace launcher for herdr

  Layouts live in: $LAYOUT_ROOT
  Template scaffold: $ROOT_DIR/example.sh

  Usage:
    schmerdr new    <name>            copy example.sh -> <name>.sh and open it
    schmerdr edit   <name>            edit an existing layout
    schmerdr load   <name> [args...]  build the workspace from <name>.sh
                                      (args are passed to the template as \$1, \$2, ...)
    schmerdr check  <name>            check whether a layout exists
    schmerdr version                  print the version (also -v, --version)
    schmerdr help                     show this message

  Example:
    schmerdr load cool-project Dev   # template runs: dotnet run --launch-profile Dev
EOF
}

# _schmerdr_dbg <msg> : print to stderr when SCHMERDR_DEBUG is set.
_schmerdr_dbg() { [ -n "$SCHMERDR_DEBUG" ] && printf 'schmerdr[dbg]: %s\n' "$*" >&2; return 0; }

# _ratio <val> : normalise "50%" or "0.5" -> "0.5" for herdr --ratio.
_ratio() {
  case "$1" in
    *%) awk "BEGIN{printf \"%g\", ${1%\%}/100}" ;;
    *)  printf '%s' "$1" ;;
  esac
}
