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
  _TAB_MAP=""; HOME_PANE="$CUR_PANE"
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
  _TAB_MAP=""; HOME_PANE="$CUR_PANE"
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

# --- sequential startup -----------------------------------------------------
# Long-running siblings started at once (e.g. three `dotnet watch`) race on the
# same obj/bin under shared libs and fail. These two verbs serialise a boot:
# mark each service's "up" line with ready_when, then gate the next pane on it
# with wait_ready — so only one build runs at a time and services come up in
# order. The gate is TYPED INTO the waiting pane (not run by this script), so
# `schmerdr load` returns immediately and a deferred agent still starts promptly.
# It's also visible and interruptible: Ctrl-C a stuck wait and the queued command
# (typed ahead) runs anyway.

# ready_when <match> : record that the CURRENT pane's service is up once <match>
# appears in its output. Call it right after launching the service.
ready_when() {
  [ -n "$CUR_PANE" ] || { printf 'schmerdr: ready_when with no current pane\n' >&2; return 1; }
  PREV_PANE="$CUR_PANE"
  PREV_READY="${1:-Now listening on}"
  _schmerdr_dbg "ready_when pane=$PREV_PANE match='$PREV_READY'"
}

# wait_ready [timeout-ms] : in the CURRENT pane, block until the pane marked by
# the last ready_when logs its match, then let the pane's next commands run.
# Degrades safe: `herdr pane wait-output` exits non-zero on timeout, but since
# commands aren't chained the service still starts. Default 5min covers a cold
# first build; a real "up" line matches far sooner. (`herdr` must be on PATH in
# the pane, per the install docs.)
wait_ready() {
  _to="${1:-300000}"
  [ -n "$CUR_PANE" ]  || { printf 'schmerdr: wait_ready with no current pane\n' >&2; return 1; }
  [ -n "$PREV_PANE" ] || { printf 'schmerdr: wait_ready before any ready_when\n' >&2; return 1; }
  run_command "$HERDR pane wait-output $PREV_PANE --match '$PREV_READY' --timeout $_to"
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
  _raw="${2:-$NAME}"
  _aname=$(_agent_name "$_raw")
  [ -n "$CUR_PANE" ] || { printf 'schmerdr: start_agent with no current pane\n' >&2; return 1; }

  # Build the agent-start argv once. For claude, forward `--name <raw>` to the
  # launched process so BOTH names are set: the herdr sidebar label (sanitized
  # $_aname) and the Claude session display name (human $_raw — shown in the
  # prompt box, /resume picker, and terminal title). Other kinds: label only.
  set -- agent start "$_aname" --kind "$_kind" --pane "$CUR_PANE"
  [ "$_kind" = claude ] && set -- "$@" -- --name "$_raw"

  # If the target is the pane running `schmerdr load`, it's busy until this load
  # returns. Defer into the background: keep trying, and the instant the shell is
  # free the agent takes over THIS pane — no extra tab, names kept. Detach so the
  # shell doesn't print a "[n]+ done" job notice into the pane.
  if [ -n "$HERDR_PANE_ID" ] && [ "$CUR_PANE" = "$HERDR_PANE_ID" ]; then
    _schmerdr_dbg "deferring agent '$_aname' into load pane $CUR_PANE (starts when load finishes)"
    ( _j=0
      while [ "$_j" -lt 120 ]; do
        _o=$("$HERDR" "$@" 2>&1)
        printf '%s' "$_o" | grep -q '"error"' || exit 0
        printf '%s' "$_o" | grep -q 'agent_pane_busy' || { printf 'schmerdr: deferred agent start failed: %s\n' "$_o" >&2; exit 1; }
        _j=$((_j + 1)); sleep 0.25
      done
      printf 'schmerdr: deferred agent start timed out (pane stayed busy)\n' >&2
    ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
    return 0
  fi

  # Fresh pane: herdr types the launch command into the pane's shell, so it must
  # be at a ready prompt. Retry only while momentarily busy (e.g. an rc greeting).
  _i=0
  while :; do
    _out=$("$HERDR" "$@" 2>&1)
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
  _TAB_MAP=""; HOME_PANE="$CUR_PANE"
  _schmerdr_dbg "worktree workspace=$WS_ID pane=$CUR_PANE"
}

# focus_pane <id> : focus a specific pane and make it current.
focus_pane() { _herdr pane focus "$1" >/dev/null && CUR_PANE="$1"; }

# focus_home : return to the workspace's first pane — the one `schmerdr load` ran
# in (pane 1). Set by new_workspace / use_current_workspace / new_worktree, and
# survives splits (splitting a pane keeps the original). Handy for laying out all
# the other tabs/panes first and starting the agent LAST, into a settled layout:
# it also restores the CUR_PANE == HERDR_PANE_ID condition start_agent needs to
# take over the load pane.
focus_home() {
  [ -n "$HOME_PANE" ] || { printf 'schmerdr: focus_home: no home pane (call new_workspace/use_current_workspace first)\n' >&2; return 1; }
  focus_pane "$HOME_PANE"
}

# focus_tab <label> : focus a tab created earlier by name, and point CUR_PANE at
# that tab's pane so run_command/wait_ready target it (not whatever pane the
# script last touched). Prefers the tab's focused pane, falls back to its first.
# NOTE: if that pane runs an agent (e.g. the Agents tab), run_command types into
# the AGENT, not a shell — split a fresh pane first, or use a control-plane verb
# like open_browser.
focus_tab() {
  _id="$(printf '%s' "$_TAB_MAP" | tr ' ' '\n' | grep "^$1=" | head -1 | cut -d= -f2)"
  [ -n "$_id" ] || { printf 'schmerdr: no tab named "%s"\n' "$1" >&2; return 1; }
  _herdr tab focus "$_id" >/dev/null || return 1
  CUR_TAB="$_id"
  _pl="$(_herdr pane list --workspace "$WS_ID" 2>/dev/null)"
  _np="$(printf '%s' "$_pl" | jq -r --arg t "$_id" \
      '[.result.panes[]? | select(.tab_id==$t)] | ((map(select(.focused==true)) + .)[0]).pane_id // empty' 2>/dev/null)"
  [ -n "$_np" ] && CUR_PANE="$_np"
  _schmerdr_dbg "focus_tab '$1' -> tab=$CUR_TAB pane=${_np:-unchanged}"
}

# open_browser <url> [placement] : open herdr's built-in browser plugin pane at
# <url>. This is a control-plane action (herdr opens the pane itself) — do NOT try
# to open a browser via run_command, which only types text into a shell/agent.
# placement: tab (default) | right | down | overlay | zoomed. right/down split the
# CURRENT pane. The new pane becomes CUR_PANE.
open_browser() {
  _url="$1"; _place="${2:-tab}"
  [ -n "$_url" ]   || { printf 'schmerdr: open_browser needs a url\n' >&2; return 1; }
  [ -n "$WS_ID" ]  || { printf 'schmerdr: open_browser with no workspace\n' >&2; return 1; }
  set -- plugin pane open --plugin official.browser --entrypoint browser \
         --workspace "$WS_ID" --env "HERDR_BROWSER_INITIAL_URL=$_url" --focus
  case "$_place" in
    tab)            set -- "$@" --placement tab ;;
    right|down)     set -- "$@" --placement split --direction "$_place"
                    [ -n "$CUR_PANE" ] && set -- "$@" --target-pane "$CUR_PANE" ;;
    overlay|zoomed) set -- "$@" --placement "$_place" ;;
    *) printf 'schmerdr: open_browser: bad placement "%s" (tab|right|down|overlay|zoomed)\n' "$_place" >&2; return 1 ;;
  esac
  _bp="$(_herdr "$@")" || return 1
  _np="$(_field "$_bp" '.result.pane.pane_id // .result.root_pane.pane_id // .result.pane_id')"
  [ -n "$_np" ] && CUR_PANE="$_np"
  _schmerdr_dbg "open_browser url=$_url placement=$_place pane=${_np:-?}"
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
