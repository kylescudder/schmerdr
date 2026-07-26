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
schmerdr new    <name>            # copy example.sh -> layouts/<name>.sh and open it
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
| `start_agent <kind> [name]` | Start an AI agent (claude, codex, gemini, …). `name` is the herdr agent/session name shown in the sidebar — pass a per-worktree value; defaults to the workspace name |
| `prompt_agent <text...>` | Submit an initial prompt to the agent in the current pane |
| `focus_pane <id>` / `focus_tab <label>` | Focus a pane / a named tab |
| `attach` | Focus the workspace and attach the herdr client |

See `example.sh` for a full template.

## Notes

- herdr addresses panes/tabs/workspaces by opaque id, so the DSL captures ids
  from herdr's JSON output (via `jq`) and tracks the "current" pane/tab.
- Set `SCHMERDR_DEBUG=1` to echo every herdr call and its output.
- Layouts in `layouts/` are gitignored (personal); the tool itself is tracked.
