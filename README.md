# schmerdr

Template-driven workspace launcher for [herdr](https://herdr.dev) — the same idea
as [`shmux`](../shmux) (per-project layout templates), but targeting herdr instead
of tmux, so a layout can also spin up **AI agents** and **git worktrees**.

You keep one small, editable shell template per project. `schmerdr load <name>`
sources it and drives herdr's CLI to build the workspace: tabs, pane splits,
commands, and agents.

## Install

```sh
# Add to ~/.zshrc
source ~/Documents/Repos/schmerdr/schmerdr.sh
```

Requires `herdr` on your `PATH` (or set `HERDR=/path/to/herdr`) and `jq`.

## Usage

```sh
schmerdr new    <name>            # copy example.sh -> ~/.config/schmerdr/layouts/<name>.sh and open it
schmerdr edit   <name>            # edit an existing layout
schmerdr load   <name> [args...]  # build the workspace (args -> $1, $2, ... in the template)
schmerdr check  <name>            # does this layout exist?
schmerdr help
```

### Runtime arguments

Args after the name are passed to the template as `$1`, `$2`, … — handy for
things like a .NET launch profile:

```sh
schmerdr load cool-project Dev     # template: dotnet run --launch-profile ${1:-Development}
```

## Layout DSL

Available inside a layout template:

| Function | Effect |
|---|---|
| `project_root [dir]` | Root cwd for the workspace/panes (`~` expanded). Optional — defaults to the dir you ran `schmerdr load` from (ideal for worktrees) |
| `workspace_name <name>` | Workspace label (also used for agent names) |
| `new_workspace` | Create the workspace |
| `new_worktree <branch> [base]` | Create a git-worktree-backed workspace instead |
| `use_current_workspace` | Adopt the workspace you ran `schmerdr load` from — lay tabs/panes into it instead of creating a new one (for a worktree already open in herdr). Use in place of `new_workspace` |
| `new_tab <label>` | Add a tab |
| `rename_tab <label>` | Rename the current tab (e.g. the default tab a new workspace opens with, to avoid an empty "1") |
| `split_right [ratio]` / `split_down [ratio]` | Split the current pane (`50%` or `0.5`) |
| `run_command <cmd...>` | Run a command in the current pane |
| `ready_when <match>` | Mark the current pane's service as "up" once `<match>` appears in its output (used with `wait_ready`) |
| `wait_ready [timeout-ms]` | Hold the current pane until the last `ready_when` pane logs its match, then let its commands run. Serialises a boot so sibling builds don't race (default 5min, degrades safe on timeout) |
| `start_agent <kind> [name]` | Start an AI agent (claude, codex, gemini, …). `name` sets **both** the herdr sidebar label (sanitized) and, for claude, the Claude session display name via `claude --name` (shown in the prompt box, `/resume` picker, and terminal title). Defaults to the workspace name; pass a per-worktree value |
| `prompt_agent <text...>` | Submit an initial prompt to the agent in the current pane |
| `focus_pane <id>` / `focus_tab <label>` | Focus a pane / a named tab. `focus_tab` also points the current pane at that tab's pane, so later `run_command`s target it |
| `open_browser <url> [placement]` | Open herdr's browser plugin pane at `<url>` (`tab` \| `right` \| `down` \| `overlay` \| `zoomed`). A control-plane action — don't try to open a browser via `run_command` |
| `focus_home` | Return to the workspace's first pane (the one `schmerdr load` ran in). Lets you lay out every other tab/pane first and start the agent last, into a settled layout |
| `attach` | Focus the workspace and attach the herdr client |

See `example.sh` for a full template.

## Notes

- Sequencing a boot: starting several long-running services at once makes their
  builds race over shared files (`obj/bin`, `node_modules`) and fail. Pair
  `ready_when "<up line>"` on a service with `wait_ready` in the next pane to
  bring them up one at a time. The gate is typed into the waiting pane (so
  `schmerdr load` returns immediately) and is interruptible — Ctrl-C a stuck wait
  and the queued command still runs. See `example.sh` and the `Odyssey` layout.
- herdr addresses panes/tabs/workspaces by opaque id, so the DSL captures ids
  from herdr's JSON output (via `jq`) and tracks the "current" pane/tab.
- Set `SCHMERDR_DEBUG=1` to echo every herdr call and its output.
- Layouts live in `~/.config/schmerdr/layouts` (override with `SCHMERDR_LAYOUTS`),
  created on first `schmerdr new`. They're kept outside the install dir so a
  read-only install (e.g. Homebrew) can still create them.
