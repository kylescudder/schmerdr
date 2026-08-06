#! /bin/sh

# schmerdr — template-driven workspace launcher for herdr.
# Install: add `source ~/Documents/Repos/schmerdr/schmerdr.sh` to your ~/.zshrc

# Resolve the directory this file lives in (works when sourced), so every
# other path can be absolute — no dependence on the current working directory.
if [ -n "$ZSH_VERSION" ]; then
  ROOT_DIR="${${(%):-%x}:A:h}"
elif [ -n "$BASH_VERSION" ]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  ROOT_DIR="${ROOT_DIR:-$HOME/Documents/Repos/schmerdr}"
fi
export ROOT_DIR

. "$ROOT_DIR/util/utils.sh"
. "$ROOT_DIR/util/functions.sh"
. "$ROOT_DIR/util/management.sh"

schmerdr() {
  _cmd="$1"; shift 2>/dev/null
  case "$_cmd" in
    -h | --help | help | "")
      show_help ;;
    -v | --version | version)
      show_version ;;
    new | new_project)
      if [ -n "$1" ]; then new_project "$1"; else show_help; return 1; fi ;;
    edit | edit_project)
      if [ -n "$1" ]; then edit_project "$1"; else show_help; return 1; fi ;;
    check | check_for_project)
      if [ -n "$1" ]; then check_for_project "$1"; else show_help; return 1; fi ;;
    load | load_project)
      if [ -n "$1" ]; then load_project "$@"; else show_help; return 1; fi ;;
    *)
      printf 'schmerdr: unknown command "%s"\n\n' "$_cmd" >&2
      show_help; return 1 ;;
  esac
}
