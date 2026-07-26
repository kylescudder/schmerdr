#! /bin/sh

# schmerdr DSL — the vocabulary a layout template uses.
# Each function drives the herdr CLI and tracks "current" state in shell vars,
# because herdr addresses panes/tabs/workspaces by opaque id (unlike tmux's
# positional indices). Ids are captured from herdr's JSON output via jq.
#
# State: ROOT, NAME, WS_ID, CUR_TAB, CUR_PANE, _TAB_MAP ("label=id label=id ...")

# --- internal ---------------------------------------------------------------

# _herdr <args...> : run herdr, echo stdout, surface JSON-envelope errors.
_herdr() {
  _schmerdr_dbg "herdr $*"
  _out="$("$HERDR" "$@" 2>&1)"; _ec=$?
  _schmerdr_dbg "-> $_out"
  if [ "$_ec" -ne 0 ] || printf '%s' "$_out" | grep -q '"error"'; then
    _msg="$(printf '%s' "$_out" | jq -r '.error.message // empty' 2>/dev/null)"
    printf 'schmerdr: `herdr %s` failed: %s\n' "$1 $2" "${_msg:-$_out}" >&2
    return 1
  fi
  printf '%s' "$_out"
}

# _field <json> <jq-filter> : extract a scalar, empty on miss.
_field() { printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null; }

# _current_pane : id of the focused pane (fallback only — prefer ids from
# create/split results, since `pane current` follows the user's global focus).
_current_pane() {
  _cp="$(_herdr pane current)" || return 1
  _field "$_cp" '.result.pane.pane_id'
}

# --- layout vocabulary ------------------------------------------------------

# project_root [dir] : root cwd for the workspace and its panes (~ expanded).
# Optional — defaults to the directory you ran `schmerdr load` from, which is
# usually what you want from a worktree. Call it only to pin a fixed location.
project_root() { ROOT="${1:-$PWD}"; ROOT="${ROOT/#\~/$HOME}"; }

# workspace_name <name> : label for the workspace (and agent instance names).
workspace_name() { NAME="$1"; }

# new_workspace : create the workspace; sets WS_ID and CUR_PANE.
new_workspace() {
  : "${ROOT:=$PWD}"   # fall back to the current dir if no project_root given
  _ws="$(_herdr workspace create --label "$NAME" --cwd "$ROOT")" || return 1
  WS_ID="$(_field "$_ws" '.result.workspace.workspace_id')"
  CUR_TAB="$(_field "$_ws" '.result.tab.tab_id')"
  CUR_PANE="$(_field "$_ws" '.result.root_pane.pane_id')"
  [ -n "$WS_ID" ] && [ -n "$CUR_PANE" ] || {
    printf 'schmerdr: workspace create returned no id — aborting layout\n' >&2
    WS_ID=""; CUR_TAB=""; CUR_PANE=""; return 1
  }
  _TAB_MAP=""
  _schmerdr_dbg "workspace=$WS_ID tab=$CUR_TAB pane=$CUR_PANE"
}

# use_current_workspace : adopt the workspace/tab/pane you ran `schmerdr load`
# from (herdr exports HERDR_PANE_ID into each pane), instead of creating a new
# one. Use this when the worktree is already open in herdr and you just want to
# lay tabs/panes into that existing workspace. Replaces new_workspace.
use_current_workspace() {
  _p="${HERDR_PANE_ID:-}"
  [ -n "$_p" ] || _p="$(_current_pane)"
  [ -n "$_p" ] || { printf 'schmerdr: not inside a herdr pane (HERDR_PANE_ID unset) — run this from within herdr\n' >&2; return 1; }
  _pg="$(_herdr pane get "$_p")" || return 1
  CUR_PANE="$(_field "$_pg" '.result.pane.pane_id')"
  CUR_TAB="$(_field "$_pg" '.result.pane.tab_id')"
  WS_ID="$(_field "$_pg" '.result.pane.workspace_id')"
  [ -n "$WS_ID" ] && [ -n "$CUR_PANE" ] || {
    printf 'schmerdr: could not resolve current workspace from pane %s\n' "$_p" >&2
    WS_ID=""; CUR_TAB=""; CUR_PANE=""; return 1
  }
  _TAB_MAP=""
  _schmerdr_dbg "using current workspace=$WS_ID tab=$CUR_TAB pane=$CUR_PANE"
}

# new_tab <label> : add a tab to the workspace; sets CUR_TAB and CUR_PANE.
new_tab() {
  [ -n "$WS_ID" ] || { printf 'schmerdr: new_tab "%s": no workspace (did new_workspace succeed?)\n' "$1" >&2; return 1; }
  _tb="$(_herdr tab create --workspace "$WS_ID" --label "$1" --cwd "$ROOT")" || return 1
  CUR_TAB="$(_field "$_tb" '.result.tab.tab_id')"
  CUR_PANE="$(_field "$_tb" '.result.root_pane.pane_id')"
  _TAB_MAP="$_TAB_MAP $1=$CUR_TAB"
  _schmerdr_dbg "tab '$1'=$CUR_TAB pane=$CUR_PANE"
}

# rename_tab <label> : rename the CURRENT tab and register it for focus_tab.
# Handy for the default tab a new workspace opens with — rename it instead of
# adding a new tab and leaving an empty "1" behind.
rename_tab() {
  [ -n "$CUR_TAB" ] || { printf 'schmerdr: rename_tab with no current tab\n' >&2; return 1; }
  _herdr tab rename "$CUR_TAB" "$1" >/dev/null || return 1
  _TAB_MAP="$_TAB_MAP $1=$CUR_TAB"
  _schmerdr_dbg "renamed tab $CUR_TAB -> '$1'"
}

# split_right [ratio] / split_down [ratio] : split CUR_PANE; CUR_PANE = new pane.
split_right() { _split right "${1:-0.5}"; }
split_down()  { _split down  "${1:-0.5}"; }
_split() {
  [ -n "$CUR_PANE" ] || { printf 'schmerdr: split: no current pane\n' >&2; return 1; }
  _sp="$(_herdr pane split --pane "$CUR_PANE" --direction "$1" \
        --ratio "$(_ratio "$2")" --cwd "$ROOT" --focus)" || return 1
  CUR_PANE="$(_field "$_sp" '.result.pane.pane_id')"
  _schmerdr_dbg "split $1 -> pane=$CUR_PANE"
}

# run_command <cmd...> : type a command line into CUR_PANE and press Enter.
# `herdr pane run` sends the text to the pane's interactive shell + Enter (it does
# NOT exec argv), so pass the raw command — no `--`, no shell wrapper. The pane's
# own login shell resolves PATH and interprets operators (>, |, &&), like shmux.
run_command() {
  [ -n "$CUR_PANE" ] || { printf 'schmerdr: run_command with no current pane\n' >&2; return 1; }
  _herdr pane run "$CUR_PANE" "$*" >/dev/null
}

# _agent_name <raw> : coerce a name to herdr's rules (must start with a-z, only
# [a-z0-9_-], max 32 chars) so a branch like "feature/PROJ-1_thing" is accepted.
_agent_name() {
  _n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | tr -s '-')
  _n=${_n#"${_n%%[a-z]*}"}          # drop leading chars until the first a-z
  _n=$(printf '%s' "$_n" | cut -c1-32)
  _n=${_n%-}                        # no trailing dash from truncation
  [ -n "$_n" ] || _n=agent
  printf '%s' "$_n"
}

# start_agent <kind> [name] : start an interactive agent in CUR_PANE.
#   kind: claude, codex, gemini, cursor, opencode, copilot, ... (`herdr agent start`)
#   name: the herdr agent/session name shown in the sidebar. Defaults to the
#         workspace name; pass a per-worktree value (e.g. the branch/ticket) so
#         each worktree's agent is distinct. Sanitized to herdr's naming rules,
#         and passed as the first positional of `herdr agent start`.
start_agent() {
  _kind="$1"
  _aname=$(_agent_name "${2:-$NAME}")
  [ -n "$CUR_PANE" ] || { printf 'schmerdr: start_agent with no current pane\n' >&2; return 1; }
  # If the target is the pane running `schmerdr load`, it's busy until this load
  # returns. Defer into the background: keep trying, and the instant the shell is
  # free (load done) the agent takes over THIS pane — no extra tab, name kept.
  if [ -n "$HERDR_PANE_ID" ] && [ "$CUR_PANE" = "$HERDR_PANE_ID" ]; then
    _schmerdr_dbg "deferring agent '$_aname' into load pane $CUR_PANE (starts when load finishes)"
    ( _dp="$CUR_PANE"; _dk="$_kind"; _dn="$_aname"; _dj=0
      while [ "$_dj" -lt 120 ]; do
        _do=$("$HERDR" agent start "$_dn" --kind "$_dk" --pane "$_dp" 2>&1)
        printf '%s' "$_do" | grep -q '"error"' || exit 0
        printf '%s' "$_do" | grep -q 'agent_pane_busy' || { printf 'schmerdr: deferred agent start failed: %s\n' "$_do" >&2; exit 1; }
        _dj=$((_dj + 1)); sleep 0.25
      done
      printf 'schmerdr: deferred agent start timed out (pane stayed busy)\n' >&2
    ) >/dev/null 2>&1 &
    # Detach the job so the shell doesn't print a "[n]+ done (...)" completion
    # notice into the pane (it would land in the agent's input box).
    disown 2>/dev/null || true
    return 0
  fi
  # herdr types the launch command into the pane's shell, so it must be at a
  # ready prompt. A freshly-spawned pane may briefly be busy (e.g. a fastfetch
  # greeting in your rc) -> code "agent_pane_busy". Retry only on that, ~5s.
  _i=0
  while :; do
    _out=$("$HERDR" agent start "$_aname" --kind "$_kind" --pane "$CUR_PANE" 2>&1)
    printf '%s' "$_out" | grep -q '"error"' || { _schmerdr_dbg "agent '$_aname' started"; return 0; }
    if [ "$_i" -lt 20 ] && printf '%s' "$_out" | grep -q 'agent_pane_busy'; then
      _i=$((_i + 1)); sleep 0.25; continue
    fi
    _msg=$(printf '%s' "$_out" | jq -r '.error.message // empty' 2>/dev/null)
    printf 'schmerdr: `herdr agent start` failed: %s\n' "${_msg:-$_out}" >&2
    return 1
  done
}

# prompt_agent <text...> : submit an initial prompt to the agent in CUR_PANE.
prompt_agent() {
  [ -n "$CUR_PANE" ] || { printf 'schmerdr: prompt_agent with no current pane\n' >&2; return 1; }
  _herdr agent prompt --wait "$CUR_PANE" "$*" >/dev/null || \
  _herdr agent prompt "$CUR_PANE" "$*" >/dev/null
}

# new_worktree <branch> [base] : create a git-worktree-backed workspace.
# Replaces new_workspace when you want an isolated checkout.
new_worktree() {
  _branch="$1"; _base="$2"
  set -- worktree create --branch "$_branch" --label "$NAME"
  [ -n "$ROOT" ]  && set -- "$@" --cwd "$ROOT"
  [ -n "$_base" ] && set -- "$@" --base "$_base"
  _wt="$(_herdr "$@")" || return 1
  WS_ID="$(_field "$_wt" '.result.workspace.workspace_id // .result.workspace_id')"
  CUR_TAB="$(_field "$_wt" '.result.tab.tab_id')"
  CUR_PANE="$(_field "$_wt" '.result.root_pane.pane_id')"
  [ -z "$CUR_PANE" ] && CUR_PANE="$(_current_pane)"
  _TAB_MAP=""
  _schmerdr_dbg "worktree workspace=$WS_ID pane=$CUR_PANE"
}

# focus_pane <id> : focus a specific pane and make it current.
focus_pane() { _herdr pane focus "$1" >/dev/null && CUR_PANE="$1"; }

# focus_tab <label> : focus a tab created earlier by name.
focus_tab() {
  _id="$(printf '%s' "$_TAB_MAP" | tr ' ' '\n' | grep "^$1=" | head -1 | cut -d= -f2)"
  if [ -n "$_id" ]; then
    _herdr tab focus "$_id" >/dev/null && CUR_TAB="$_id"
  else
    printf 'schmerdr: no tab named "%s"\n' "$1" >&2; return 1
  fi
}

# attach : focus the workspace. If run from OUTSIDE herdr, also attach an
# interactive client; if already inside a herdr session (HERDR_ENV=1), just focus
# — launching herdr again would error with "nested herdr is disabled".
attach() {
  [ -n "$WS_ID" ] && _herdr workspace focus "$WS_ID" >/dev/null
  if [ "$HERDR_ENV" = "1" ]; then
    _schmerdr_dbg "inside herdr — focused workspace, skipping nested attach"
    return 0
  fi
  "$HERDR"
}
