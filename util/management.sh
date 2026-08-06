#! /bin/sh

# schmerdr — project (layout) management: new / load / edit / check.
# All paths are absolute (via LAYOUT_ROOT / ROOT_DIR) so these work from any CWD.

check_for_project() {
  if [ ! -f "$LAYOUT_ROOT/$1.sh" ]; then
    printf 'schmerdr: no layout named "%s" in %s\n' "$1" "$LAYOUT_ROOT" >&2
    return 1
  fi
}

new_project() {
  if [ ! -f "$ROOT_DIR/example.sh" ]; then
    printf 'schmerdr: template missing: %s/example.sh\n' "$ROOT_DIR" >&2
    return 1
  fi
  if [ -f "$LAYOUT_ROOT/$1.sh" ]; then
    printf 'schmerdr: layout "%s" already exists — use `schmerdr edit %s`\n' "$1" "$1" >&2
    return 1
  fi
  mkdir -p "$LAYOUT_ROOT" || return 1
  cp "$ROOT_DIR/example.sh" "$LAYOUT_ROOT/$1.sh" || return 1
  "${EDITOR:-vi}" "$LAYOUT_ROOT/$1.sh"
}

# load_project <name> [args...] : source the layout, passing args through as $1...
load_project() {
  _name="$1"; shift
  check_for_project "$_name" || return 1
  # Reset all layout state per load so a template can never run against ids from
  # a previous load in this shell (e.g. if new_workspace fails, downstream funcs
  # fail fast instead of hitting a now-closed workspace). ROOT defaults to the
  # invocation dir (usually a worktree); the template may override via project_root.
  ROOT="$PWD"; WS_ID=""; CUR_TAB=""; CUR_PANE=""; _TAB_MAP=""; PREV_PANE=""; PREV_READY=""
  # shellcheck disable=SC1090  # dynamic path is intentional
  . "$LAYOUT_ROOT/$_name.sh" "$@"
}

edit_project() {
  check_for_project "$1" || return 1
  "${EDITOR:-vi}" "$LAYOUT_ROOT/$1.sh"
}
