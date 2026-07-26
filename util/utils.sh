#! /bin/sh

# schmerdr — paths, help text, and small internal helpers.
# ROOT_DIR is set by schmerdr.sh (the dir this repo lives in) before sourcing.

: "${ROOT_DIR:="$HOME/Documents/Repos/schmerdr"}"
LAYOUT_ROOT="$ROOT_DIR/layouts"

# herdr binary — override with HERDR=/path/to/herdr if not on PATH.
HERDR="${HERDR:-herdr}"

show_help() {
  cat <<EOF
schmerdr — template-driven workspace launcher for herdr

  Layouts live in: $LAYOUT_ROOT
  Template scaffold: $ROOT_DIR/example.sh

  Usage:
    schmerdr new    <name>            copy example.sh -> <name>.sh and open it
    schmerdr edit   <name>            edit an existing layout
    schmerdr load   <name> [args...]  build the workspace from <name>.sh
                                      (args are passed to the template as \$1, \$2, ...)
    schmerdr check  <name>            check whether a layout exists
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
